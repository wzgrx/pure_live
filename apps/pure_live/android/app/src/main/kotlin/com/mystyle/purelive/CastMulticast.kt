package com.mystyle.purelive

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Wi-Fi multicast lock for the DLNA search (F-CAST-01, docs/adr/0027-dlna-cast.md):
 * many Wi-Fi drivers filter multicast while no app holds this lock, and SSDP
 * traffic is lost. Channel `purelive/cast`: `acquire` holds the lock (returns
 * whether it is held), `release` lets it go. Dart counts overlapping searches
 * and calls each once, so the lock is not reference-counted here; the system
 * drops it with the process.
 *
 * Registered from MainActivity.configureFlutterEngine:
 *
 *     CastMulticast(applicationContext).register(messenger)
 *
 * Needs `android.permission.CHANGE_WIFI_MULTICAST_STATE` in the manifest.
 */
class CastMulticast(context: Context) {
    private val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
    private var lock: WifiManager.MulticastLock? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> result.success(acquire())
                "release" -> {
                    release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun acquire(): Boolean {
        val manager = wifi ?: return false
        return try {
            val held = lock ?: manager.createMulticastLock(TAG).also {
                it.setReferenceCounted(false)
                lock = it
            }
            if (!held.isHeld) held.acquire()
            true
        } catch (error: RuntimeException) {
            // SecurityException without the permission: search without the lock.
            false
        }
    }

    private fun release() {
        val held = lock ?: return
        try {
            if (held.isHeld) held.release()
        } catch (error: RuntimeException) {
            // Already released by the system.
        }
    }

    private companion object {
        const val CHANNEL = "purelive/cast"
        const val TAG = "purelive:cast"
    }
}
