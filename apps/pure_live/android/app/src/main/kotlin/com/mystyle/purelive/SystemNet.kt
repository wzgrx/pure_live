package com.mystyle.purelive

import android.content.Context
import android.net.ConnectivityManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The network's HTTP proxy for "跟随系统代理" (F-SET-07): the default network's
 * proxy as the user or a proxy app set it, on channel `purelive/net`.
 */
class SystemNet(private val context: Context) {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "purelive/net").setMethodCallHandler { call, result ->
            when (call.method) {
                "systemProxy" -> result.success(systemProxy())
                else -> result.notImplemented()
            }
        }
    }

    private fun systemProxy(): Map<String, Any>? {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return null
        val proxy = manager.defaultProxy ?: return null
        val host = proxy.host
        // A PAC-only proxy has no host; mpv and dart:io need a host and port.
        if (host.isNullOrEmpty() || proxy.port <= 0) return null
        return mapOf(
            "host" to host,
            "port" to proxy.port,
            "exclusions" to proxy.exclusionList.toList(),
        )
    }
}
