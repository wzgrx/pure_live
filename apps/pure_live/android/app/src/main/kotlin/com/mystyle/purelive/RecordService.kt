package com.mystyle.purelive

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import com.ryanheise.audioservice.AudioService
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * Recording in the background (spec/modules/record.md §16.1, F-REC-06;
 * docs/adr/draft-record-service.md) on channel `purelive/record`
 * (lib/core/recording.dart `RecordKeepAlive`).
 *
 * Dart drives it from the recorder's active task count: `update` with the
 * notification title and text while one or more recordings run, `stop` when
 * none is left. While active it holds:
 * - the foreground service [RecordService], type `specialUse` (no daily
 *   limit; `dataSync` stops after 6 h in 24 h on Android 15+), so the process
 *   keeps foreground-service priority with the screen off;
 * - a partial wake lock and a high-performance Wi-Fi lock, so the CPU and
 *   Wi-Fi keep reading the stream;
 * - a binding to audio_service's AudioService: the Flutter engine is shared
 *   with it and is destroyed when AudioService goes away with no activity
 *   attached, which would end the recording when the user closes the app.
 *
 * If the system times the service out anyway ([Service.onTimeout], Android
 * 15+), the service stops at once as required, the wake lock stays for up to
 * [DRAIN_MILLIS] and Dart gets `onTimeout` to finish the files; its `stop`
 * releases everything.
 *
 * One state per process: an activity attaching to the cached engine again
 * only replaces the channel and the activity used to ask for the
 * notification permission.
 */
internal object RecordKeepAlive {
    private const val CHANNEL = "purelive/record"
    private const val LOCK_TAG = "purelive:record"
    private const val DRAIN_MILLIS = 45_000L
    private const val MEDIA_BROWSER_SERVICE = "android.media.browse.MediaBrowserService"
    private const val REQUEST_NOTIFICATIONS = 0x7265

    private val handler = Handler(Looper.getMainLooper())
    private val drainDeadline = Runnable { release() }
    private var appContext: Context? = null
    private var activity: WeakReference<Activity>? = null
    private var channel: MethodChannel? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var engineBinding: ServiceConnection? = null
    private var askedNotifications = false

    /** Generation of the service start Dart currently wants; 0 = none. */
    private var generation = 0L
    private var nextGeneration = 0L

    /** Notification title, for example "正在录制 2 个直播间". */
    var title = ""
        private set

    /** Notification text, for example the streamers' names. */
    var text = ""
        private set

    fun attach(activity: Activity, messenger: BinaryMessenger) {
        appContext = activity.applicationContext
        this.activity = WeakReference(activity)
        channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(::onCall) }
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext
        if (context == null) {
            result.error("record", "not attached", null)
            return
        }
        when (call.method) {
            "update" -> {
                title = call.argument<String>("title").orEmpty().take(120)
                text = call.argument<String>("text").orEmpty().take(240)
                result.success(start(context))
            }
            "stop" -> {
                stop(context)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Starts or refreshes the service; false when Android refused the start. */
    private fun start(context: Context): Boolean {
        handler.removeCallbacks(drainDeadline)
        acquireLocks(context)
        bindEngine(context)
        askForNotifications()
        if (generation != 0L) {
            RecordService.running?.refresh()
            return true
        }
        val started = ++nextGeneration
        return try {
            context.startForegroundService(
                Intent(context, RecordService::class.java).putExtra(RecordService.EXTRA_GENERATION, started),
            )
            generation = started
            true
        } catch (error: Exception) {
            // Android 12+ refuses a start from the background
            // (ForegroundServiceStartNotAllowedException). The locks and the
            // engine binding still help while the process lives; the next
            // update tries again.
            false
        }
    }

    private fun stop(context: Context) {
        if (generation != 0L) {
            generation = 0L
            context.stopService(Intent(context, RecordService::class.java))
        }
        release()
    }

    /** The system timed the service out; it has stopped itself. */
    fun onServiceTimeout(serviceGeneration: Long) {
        if (serviceGeneration == generation) generation = 0L
        handler.removeCallbacks(drainDeadline)
        handler.postDelayed(drainDeadline, DRAIN_MILLIS)
        channel?.invokeMethod("onTimeout", null)
    }

    /** The service of [serviceGeneration] ended without Dart asking; the next update starts it again. */
    fun onServiceEnded(serviceGeneration: Long) {
        if (serviceGeneration == generation) generation = 0L
    }

    @SuppressLint("WakelockTimeout")
    @Suppress("DEPRECATION")
    private fun acquireLocks(context: Context) {
        val wake = wakeLock ?: context.getSystemService(PowerManager::class.java)
            ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, LOCK_TAG)
            ?.apply { setReferenceCounted(false) }
            ?.also { wakeLock = it }
        if (wake != null && !wake.isHeld) wake.acquire()
        // FULL_HIGH_PERF keeps Wi-Fi awake with the screen off (as PlaybackLocks does).
        val wifi = wifiLock ?: context.getSystemService(WifiManager::class.java)
            ?.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, LOCK_TAG)
            ?.apply { setReferenceCounted(false) }
            ?.also { wifiLock = it }
        if (wifi != null && !wifi.isHeld) wifi.acquire()
    }

    private fun release() {
        handler.removeCallbacks(drainDeadline)
        wakeLock?.let { if (it.isHeld) it.release() }
        wifiLock?.let { if (it.isHeld) it.release() }
        unbindEngine()
    }

    private fun bindEngine(context: Context) {
        if (engineBinding != null) return
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, service: IBinder?) = Unit

            override fun onServiceDisconnected(name: ComponentName?) = Unit
        }
        val intent = Intent(context, AudioService::class.java).setAction(MEDIA_BROWSER_SERVICE)
        try {
            if (context.bindService(intent, connection, Context.BIND_AUTO_CREATE)) {
                engineBinding = connection
            } else {
                context.unbindService(connection)
            }
        } catch (error: Exception) {
            // Without the binding the recording still runs while an activity
            // or background playback holds the engine.
        }
    }

    private fun unbindEngine() {
        val connection = engineBinding ?: return
        engineBinding = null
        try {
            appContext?.unbindService(connection)
        } catch (error: IllegalArgumentException) {
            // Already gone with its service.
        }
    }

    /**
     * Android 13+ shows the recording notification only with the
     * notification permission; asked once per process, while the app is in
     * front. Recording works either way (the service then shows only in the
     * system's task manager).
     */
    private fun askForNotifications() {
        if (askedNotifications || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val current = activity?.get() ?: return
        if (current.isFinishing || current.isDestroyed || !current.hasWindowFocus()) return
        askedNotifications = true
        if (current.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            current.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
        }
    }
}

/**
 * The recording foreground service (spec/modules/record.md §16.1): only the
 * notification "正在录制 N 个直播间"; the recording itself runs in Dart and
 * [RecordKeepAlive] holds the locks. Type `specialUse` from Android 14, the
 * manifest's type before.
 */
class RecordService : Service() {
    private var generation = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        generation = intent?.getLongExtra(EXTRA_GENERATION, 0L) ?: 0L
        try {
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (error: Exception) {
            // A missing manifest entry or a system refusal: record without the service.
            RecordKeepAlive.onServiceEnded(generation)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    /** Android 15+: a foreground service type ran out of time; stop within seconds. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        RecordKeepAlive.onServiceTimeout(generation)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        if (running === this) running = null
        RecordKeepAlive.onServiceEnded(generation)
        super.onDestroy()
    }

    /** Shows the current title and text. */
    fun refresh() {
        getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager?.getNotificationChannel(CHANNEL_ID) == null) {
            manager?.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "录制", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "录制直播时的常驻通知"
                    setShowBadge(false)
                },
            )
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        val builder = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(RecordKeepAlive.title)
            .setContentText(RecordKeepAlive.text)
            .setContentIntent(open)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    companion object {
        const val EXTRA_GENERATION = "generation"
        private const val CHANNEL_ID = "com.mystyle.purelive.recording"
        private const val NOTIFICATION_ID = 0x7265_636f

        /** The running instance, for notification updates. */
        var running: RecordService? = null
            private set
    }
}
