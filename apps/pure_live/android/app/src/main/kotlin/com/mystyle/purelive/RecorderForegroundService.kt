package com.mystyle.purelive

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager

/**
 * Foreground lifetime of active recordings (3.x RecorderForegroundService at
 * v3.2.11). The recorder stays in Dart; this service only shows Android that
 * the app is working (data sync) and holds the wake and Wi-Fi locks while it
 * runs. [RecorderPlugin] starts and stops it and learns when Android ends it
 * early: the Android 15 data-sync time limit ([onTimeout]) or an unexpected
 * destroy.
 */
class RecorderForegroundService : Service() {
    internal interface Listener {
        fun onReady()
        fun onStartFailed(message: String)
        fun onEnded(reason: String)
    }

    companion object {
        private const val ACTION_START = "com.mystyle.purelive.recorder.START"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val CHANNEL_ID = "pure_live_recording"
        private const val NOTIFICATION_ID = 20260906

        private val mainHandler = Handler(Looper.getMainLooper())
        internal var listener: Listener? = null
        private var running: RecorderForegroundService? = null

        internal fun start(context: Context, title: String, text: String) {
            val intent = Intent(context, RecorderForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_TEXT, text)
            }
            context.startForegroundService(intent)
        }

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
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate() {
        super.onCreate()
        running = this
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Recording", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Active live-stream recording"
                setShowBadge(false)
            },
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action != ACTION_START) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty()
        val text = intent.getStringExtra(EXTRA_TEXT).orEmpty()
        try {
            val notification = buildNotification(title, text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            foreground = true
            acquireLocks()
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

    private fun releaseLocks() {
        wifiLock?.let { if (it.isHeld) it.release() }
        wifiLock = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    private fun buildNotification(title: String, text: String): Notification {
        val openApp = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openApp,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(pendingIntent)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }
}
