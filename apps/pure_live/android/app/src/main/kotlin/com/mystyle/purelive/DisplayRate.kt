package com.mystyle.purelive

import android.app.Activity
import android.os.Build
import android.view.Display
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The window's refresh-rate hint for the 刷新率 setting (F-SET-08), on channel
 * `purelive/display`: `setHighRefreshRate(enabled)` asks for the highest rate
 * of the current resolution, or gives the choice back to the system.
 *
 * Only `preferredRefreshRate` changes: pinning `preferredDisplayModeId` too
 * can force a heavy vendor mode switch (3.x lesson).
 */
class DisplayRate(private val activity: Activity) {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "purelive/display").setMethodCallHandler { call, result ->
            when (call.method) {
                "setHighRefreshRate" -> {
                    apply(call.argument<Boolean>("enabled") ?: false)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun apply(enabled: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val display = currentDisplay() ?: return
        val current = display.mode
        val best = display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: current
        val target = if (enabled) best.refreshRate else 0f
        val attributes = activity.window.attributes
        if (attributes.preferredDisplayModeId != 0 || kotlin.math.abs(attributes.preferredRefreshRate - target) > 0.01f) {
            attributes.preferredDisplayModeId = 0
            attributes.preferredRefreshRate = target
            activity.window.attributes = attributes
        }
    }

    @Suppress("DEPRECATION")
    private fun currentDisplay(): Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) activity.display else activity.windowManager.defaultDisplay
}
