package com.mystyle.purelive

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager

/**
 * What the recording notifications say (docs/ui/compare/U.14 c3–c5), sent
 * by Dart with every change: [title] and [text] ("正在录制 · 晚风" over the
 * title and quality, or "正在录制 N 个直播间" over the streamers), [since]
 * for the system's clock (no refresh every second), the button words and
 * the channel names.
 */
internal data class RecordWords(
    val title: String,
    val text: String,
    val since: Long?,
    val stop: String,
    val center: String,
    val open: String,
    val channel: String,
    val channelDescription: String,
    val alertChannel: String,
    val alertChannelDescription: String,
) {
    companion object {
        /** Reads the channel's map; missing words fall back to 3.x's. */
        fun from(arguments: Any?): RecordWords {
            val map = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            fun text(key: String, fallback: String, limit: Int = 120) =
                (map[key] as? String)?.trim()?.take(limit)?.ifEmpty { null } ?: fallback
            return RecordWords(
                title = text("title", "直播录制进行中"),
                text = text("text", "", 240),
                since = (map["since"] as? Number)?.toLong(),
                stop = text("stop", "停止录制"),
                center = text("center", "录制中心"),
                open = text("open", "打开录制中心"),
                channel = text("channel", "录制"),
                channelDescription = text("channelDescription", ""),
                alertChannel = text("alertChannel", "录制提醒"),
                alertChannelDescription = text("alertChannelDescription", ""),
            )
        }
    }
}

/**
 * Foreground lifetime of active recordings (3.x RecorderForegroundService at
 * v3.2.11). The recorder stays in Dart; this service only shows Android that
 * the app is working (data sync) and holds the wake and Wi-Fi locks while it
 * runs. [RecorderPlugin] starts and stops it and learns when Android ends it
 * early: the Android 15 data-sync time limit ([onTimeout]) or an unexpected
 * destroy.
 *
 * The notification (U.14 c2–c5): the record dot in the status bar; who is
 * recorded and since when, updated by Dart ([update]); "停止录制" (Dart stops
 * the recordings, [Listener.onStopRequested]) and "录制中心"; a tap opens the
 * recording centre. Channels "录制" (3.x "Recording") and "录制提醒" for
 * [alert] ("录制已停止", posted by Dart when Android stopped it or a recording
 * failed in the background).
 *
 * Recording after the app is swiped away (M8.1): the recorder runs in the
 * Flutter engine that [MainActivity] (an AudioServiceActivity) keeps cached,
 * so it outlives the activity while this service keeps the process. The one
 * thing that destroys that engine without the activity is audio_service
 * itself: when its media service ends (background playback stopped) and no
 * activity is attached, `AudioServicePlugin.disposeFlutterEngine` destroys
 * the engine, and the recordings with it. While recording, this service
 * therefore binds to the media service (without creating it), so it is not
 * destroyed before the recordings end.
 */
class RecorderForegroundService : Service() {
    internal interface Listener {
        fun onReady()
        fun onStartFailed(message: String)
        fun onEnded(reason: String)
        fun onStopRequested()
    }

    companion object {
        private const val ACTION_START = "com.mystyle.purelive.recorder.START"
        private const val ACTION_STOP_ALL = "com.mystyle.purelive.recorder.STOP_ALL"
        private const val CHANNEL_ID = "pure_live_recording"
        private const val ALERT_CHANNEL_ID = "pure_live_recording_alerts"
        private const val NOTIFICATION_ID = 20260906

        private val mainHandler = Handler(Looper.getMainLooper())
        internal var listener: Listener? = null
        private var running: RecorderForegroundService? = null
        private var words = RecordWords.from(null)

        internal fun start(context: Context, words: RecordWords) {
            this.words = words
            val intent = Intent(context, RecorderForegroundService::class.java).apply { action = ACTION_START }
            context.startForegroundService(intent)
        }

        /** New words for the notification while it shows. */
        internal fun update(context: Context, words: RecordWords) {
            this.words = words
            val service = running ?: return
            if (!service.foreground) return
            try {
                channels(context, words)
                context.getSystemService(NotificationManager::class.java)
                    .notify(NOTIFICATION_ID, service.buildNotification(words))
            } catch (_: Exception) {
                // Notifications are off; the service keeps running.
            }
        }

        /** Posts the "录制已停止" reminder [id] (one per task). */
        internal fun alert(context: Context, id: String, title: String, text: String, words: RecordWords) {
            try {
                channels(context, words)
                val notification = Notification.Builder(context, ALERT_CHANNEL_ID)
                    .setSmallIcon(R.drawable.ic_stat_record_stopped)
                    .setContentTitle(title)
                    .setContentText(text)
                    .setStyle(Notification.BigTextStyle().bigText(text))
                    .setContentIntent(openRecordings(context, 1))
                    .addAction(Notification.Action.Builder(null, words.open, openRecordings(context, 2)).build())
                    .setCategory(Notification.CATEGORY_ERROR)
                    .setAutoCancel(true)
                    .build()
                context.getSystemService(NotificationManager::class.java)
                    .notify("record_alert:$id", NOTIFICATION_ID + 1, notification)
            } catch (_: Exception) {
                // Notifications are off.
            }
        }

        /** Creates (or renames: 3.x's English "Recording") the two channels. */
        private fun channels(context: Context, words: RecordWords) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, words.channel, NotificationManager.IMPORTANCE_LOW).apply {
                    description = words.channelDescription
                    setShowBadge(false)
                },
            )
            manager.createNotificationChannel(
                NotificationChannel(ALERT_CHANNEL_ID, words.alertChannel, NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = words.alertChannelDescription
                },
            )
        }

        /** The recording centre, in the running task or a new activity on the cached engine. */
        private fun openRecordings(context: Context, request: Int): PendingIntent = PendingIntent.getActivity(
            context,
            request,
            ShareIntakePlugin.openRoute(context, ShareIntakePlugin.ROUTE_RECORDINGS),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        /** Stops the service on request (not reported as an interruption). */
        internal fun stop(context: Context) {
            val service = running
            if (service != null) {
                service.stoppedOnRequest = true
                service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
                service.stopSelf()
            } else {
                context.stopService(Intent(context, RecorderForegroundService::class.java))
            }
        }

        private fun post(action: (Listener) -> Unit) {
            mainHandler.post { listener?.let(action) }
        }
    }

    private var foreground = false
    private var stoppedOnRequest = false
    private var holdingMediaService = false
    private val mediaServiceHold = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) = Unit

        override fun onServiceDisconnected(name: ComponentName?) = Unit
    }
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate() {
        super.onCreate()
        running = this
        channels(this, words)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // "停止录制" on the notification: Dart stops the recordings, then
        // releases the service.
        if (intent?.action == ACTION_STOP_ALL) {
            if (foreground) post { it.onStopRequested() }
            return START_NOT_STICKY
        }
        if (intent?.action != ACTION_START) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        try {
            val notification = buildNotification(words)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            foreground = true
            acquireLocks()
            holdMediaService()
            post { it.onReady() }
        } catch (exception: Exception) {
            stoppedOnRequest = true
            post { it.onStartFailed(exception.localizedMessage ?: "Foreground service startup failed") }
            stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // Android 15 limits background data-sync services to six hours a day and
    // requires a prompt stop here.
    override fun onTimeout(startId: Int, fgsType: Int) {
        if (fgsType != ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC || stoppedOnRequest) return
        stoppedOnRequest = true
        post { it.onEnded("timeout") }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        releaseMediaService()
        releaseLocks()
        if (running === this) running = null
        if (foreground && !stoppedOnRequest) post { it.onEnded("service_stopped") }
        foreground = false
        super.onDestroy()
    }

    private fun acquireLocks() {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:recording").apply {
            setReferenceCounted(false)
            acquire()
        }
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            wifiLock = wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "$packageName:recording").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Exception) {
            // Recording continues without the Wi-Fi lock.
        }
    }

    // Flags 0: binds when audio_service's media service runs (or once it
    // starts), never starts it.
    private fun holdMediaService() {
        if (holdingMediaService) return
        val intent = Intent("android.media.browse.MediaBrowserService")
            .setClassName(this, "com.ryanheise.audioservice.AudioService")
        holdingMediaService = try {
            bindService(intent, mediaServiceHold, 0)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun releaseMediaService() {
        if (!holdingMediaService) return
        holdingMediaService = false
        try {
            unbindService(mediaServiceHold)
        } catch (_: Exception) {
            // Never bound.
        }
    }

    private fun releaseLocks() {
        wifiLock?.let { if (it.isHeld) it.release() }
        wifiLock = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    private fun buildNotification(words: RecordWords): Notification {
        val stopAll = PendingIntent.getService(
            this,
            3,
            Intent(this, RecorderForegroundService::class.java).setAction(ACTION_STOP_ALL),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_recording)
            .setContentTitle(words.title)
            .setContentText(words.text)
            .setContentIntent(openRecordings(this, 0))
            .addAction(Notification.Action.Builder(null, words.stop, stopAll).build())
            .addAction(Notification.Action.Builder(null, words.center, openRecordings(this, 4)).build())
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
        val since = words.since
        if (since != null) builder.setWhen(since).setShowWhen(true).setUsesChronometer(true)
        return builder.build()
    }
}
