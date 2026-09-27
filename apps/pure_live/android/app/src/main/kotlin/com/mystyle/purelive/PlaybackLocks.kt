package com.mystyle.purelive

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The Wi-Fi lock of background playback (spec/modules/playback.md PERF-2), on
 * channel `purelive/playback` (lib/features/system/android_media.dart). The
 * partial wake lock comes with audio_service's foreground service.
 *
 * One lock per process, so an activity attaching to the cached engine again
 * does not leave a second lock behind.
 */
internal object PlaybackLocks {
    private const val CHANNEL = "purelive/playback"
    private const val TAG = "purelive:playback"
    private var wifiLock: WifiManager.WifiLock? = null

    fun attach(context: Context, messenger: BinaryMessenger) {
        val appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setWifiLock" -> {
                    setWifiLock(appContext, call.argument<Boolean>("held") == true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // FULL_HIGH_PERF keeps Wi-Fi awake with the screen off (the low-latency
    // mode only works in the foreground); deprecated but still what streaming
    // players use.
    @Suppress("DEPRECATION")
    private fun setWifiLock(context: Context, held: Boolean) {
        val lock = wifiLock ?: run {
            val manager = context.getSystemService(WifiManager::class.java) ?: return
            manager.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, TAG).apply {
                setReferenceCounted(false)
            }.also { wifiLock = it }
        }
        if (held && !lock.isHeld) {
            lock.acquire()
        } else if (!held && lock.isHeld) {
            lock.release()
        }
    }
}
