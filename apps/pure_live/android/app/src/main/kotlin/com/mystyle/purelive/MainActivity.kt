package com.mystyle.purelive

import android.content.Context
import android.hardware.display.DisplayManager
import android.media.AudioManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.view.Display
import android.window.BackEvent
import android.window.OnBackAnimationCallback
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app's activity (3.x MainActivity at v3.2.11, without the recorder and
 * audio_service parts, which come back with M7/M8).
 *
 * Channels:
 * - `pure_live/display_mode`: the refresh-rate hint of AdaptiveRefreshRateScope;
 * - `pure_live/background_playback`: wake and Wi-Fi locks while playing in the background;
 * - `pure_live/predictive_back`: the live room's back arbitration;
 * - `pure_live/secret_cipher`, `pure_live/native_http`, `pure_live/multicast_lock`
 *   (registered by [AppChannelsPlugin], so they also work on an engine without
 *   an activity).
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val DISPLAY_MODE_CHANNEL = "pure_live/display_mode"
        private const val BACKGROUND_PLAYBACK_CHANNEL = "pure_live/background_playback"
        private const val PREDICTIVE_BACK_CHANNEL = "pure_live/predictive_back"
        private const val APP_CHANNEL = "pure_live/app"
        private var playbackWakeLock: PowerManager.WakeLock? = null
        private var playbackWifiLock: WifiManager.WifiLock? = null
    }

    // Android's dynamic policy until Dart asks for the high rate.
    private var highRefreshRateEnabled = false
    private var displayModeChannel: MethodChannel? = null
    private var predictiveBackChannel: MethodChannel? = null
    private var predictiveBackEnabled = false
    private var predictiveBackRegistered = false
    private var displayListenerRegistered = false
    private var lastPublishedDisplayModeInfo: Map<String, Any>? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val displayModeRefresh = Runnable {
        val info = applyPreferredDisplayMode(highRefreshRateEnabled)
        if (info != lastPublishedDisplayModeInfo) {
            lastPublishedDisplayModeInfo = info
            displayModeChannel?.invokeMethod("displayModeChanged", info)
        }
    }
    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) = scheduleDisplayModeRefresh()

        override fun onDisplayRemoved(displayId: Int) = scheduleDisplayModeRefresh()

        override fun onDisplayChanged(displayId: Int) {
            val currentDisplayId = activeDisplay()?.displayId
            if (currentDisplayId == null || currentDisplayId == displayId) {
                scheduleDisplayModeRefresh()
            }
        }
    }

    private val predictiveBackCallback =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            @Suppress("NewApi")
            OnBackInvokedCallback { dispatchPresentationBack() }
        } else {
            null
        }

    @Suppress("NewApi")
    private val predictiveBackAnimationCallback =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            object : OnBackAnimationCallback {
                override fun onBackStarted(backEvent: BackEvent) {
                    predictiveBackChannel?.invokeMethod("backStarted", null)
                }

                override fun onBackProgressed(backEvent: BackEvent) {
                    predictiveBackChannel?.invokeMethod(
                        "backProgress",
                        mapOf("progress" to backEvent.progress.toDouble()),
                    )
                }

                override fun onBackCancelled() {
                    predictiveBackChannel?.invokeMethod("backCancelled", null)
                }

                override fun onBackInvoked() {
                    dispatchPresentationBack()
                }
            }
        } else {
            null
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(AppChannelsPlugin::class.java)) {
            flutterEngine.plugins.add(AppChannelsPlugin())
        }
        displayModeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DISPLAY_MODE_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setHighRefreshRate" -> {
                        highRefreshRateEnabled = call.argument<Boolean>("enabled") ?: true
                        val info = applyPreferredDisplayMode(highRefreshRateEnabled)
                        lastPublishedDisplayModeInfo = info
                        result.success(info)
                    }

                    "getDisplayModeInfo" -> result.success(displayModeInfo())
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKGROUND_PLAYBACK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepAlive" -> {
                    setPlaybackKeepAlive(call.argument<Boolean>("enabled") ?: false)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
        // Back on the home page sends the app to the background instead of
        // closing it (3.x used the move_to_desktop plugin).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "moveToBack" -> result.success(moveTaskToBack(true))
                else -> result.notImplemented()
            }
        }
        predictiveBackChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PREDICTIVE_BACK_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        setPredictiveBackEnabled(call.argument<Boolean>("enabled") ?: false)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
        }
        applyPreferredDisplayMode(highRefreshRateEnabled)
    }

    private fun dispatchPresentationBack() {
        if (predictiveBackEnabled) {
            predictiveBackChannel?.invokeMethod("backInvoked", null)
        }
    }

    private fun setPredictiveBackEnabled(enabled: Boolean) {
        if (predictiveBackEnabled == enabled) return
        predictiveBackEnabled = enabled
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (enabled) registerPredictiveBack() else unregisterPredictiveBack()
        }
    }

    @Suppress("NewApi")
    private fun registerPredictiveBack() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || predictiveBackRegistered) return
        val callback = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            predictiveBackAnimationCallback
        } else {
            predictiveBackCallback
        } ?: return
        // Flutter registers its callback at DEFAULT; the live room must run
        // first so fullscreen Back leaves fullscreen instead of the route.
        onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_OVERLAY, callback)
        predictiveBackRegistered = true
    }

    @Suppress("NewApi")
    private fun unregisterPredictiveBack() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || !predictiveBackRegistered) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            predictiveBackAnimationCallback?.let(onBackInvokedDispatcher::unregisterOnBackInvokedCallback)
        } else {
            predictiveBackCallback?.let(onBackInvokedDispatcher::unregisterOnBackInvokedCallback)
        }
        predictiveBackRegistered = false
    }

    @Deprecated("Hardware Back on vendor builds still arrives here; keep the live room's arbitration.")
    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (predictiveBackEnabled) {
            dispatchPresentationBack()
            return
        }
        super.onBackPressed()
    }

    override fun onStart() {
        super.onStart()
        registerDisplayListener()
        scheduleDisplayModeRefresh(delayMillis = 0)
    }

    @Suppress("DEPRECATION")
    private fun setPlaybackKeepAlive(enabled: Boolean) {
        if (enabled) {
            if (playbackWakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                playbackWakeLock = powerManager.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "$packageName:backgroundPlayback",
                ).apply { setReferenceCounted(false) }
            }
            if (playbackWakeLock?.isHeld != true) playbackWakeLock?.acquire()

            if (playbackWifiLock == null) {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                playbackWifiLock = wifiManager.createWifiLock(mode, "$packageName:backgroundPlayback").apply {
                    setReferenceCounted(false)
                }
            }
            if (playbackWifiLock?.isHeld != true) playbackWifiLock?.acquire()
        } else {
            if (playbackWifiLock?.isHeld == true) playbackWifiLock?.release()
            if (playbackWakeLock?.isHeld == true) playbackWakeLock?.release()
        }
    }

    override fun onResume() {
        super.onResume()
        // Volume keys control media while this window is in front.
        volumeControlStream = AudioManager.STREAM_MUSIC
        scheduleDisplayModeRefresh(delayMillis = 0)
        if (predictiveBackEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerPredictiveBack()
        }
    }

    override fun onStop() {
        unregisterDisplayListener()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) unregisterPredictiveBack()
        super.onStop()
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(displayModeRefresh)
        displayModeChannel = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) unregisterPredictiveBack()
        predictiveBackChannel = null
        super.onDestroy()
    }

    private fun registerDisplayListener() {
        if (displayListenerRegistered) return
        val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        displayManager.registerDisplayListener(displayListener, mainHandler)
        displayListenerRegistered = true
    }

    private fun unregisterDisplayListener() {
        if (!displayListenerRegistered) return
        val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        displayManager.unregisterDisplayListener(displayListener)
        displayListenerRegistered = false
        mainHandler.removeCallbacks(displayModeRefresh)
    }

    private fun scheduleDisplayModeRefresh(delayMillis: Long = 160) {
        mainHandler.removeCallbacks(displayModeRefresh)
        mainHandler.postDelayed(displayModeRefresh, delayMillis)
    }

    @Suppress("DEPRECATION")
    private fun activeDisplay(): Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay

    private fun applyPreferredDisplayMode(enabled: Boolean): Map<String, Any> {
        val activeDisplay = activeDisplay() ?: return displayModeInfo()
        val currentMode = activeDisplay.mode
        val compatibleModes = activeDisplay.supportedModes.filter {
            it.physicalWidth == currentMode.physicalWidth && it.physicalHeight == currentMode.physicalHeight
        }
        val preferredMode = compatibleModes.maxWithOrNull(
            compareBy<Display.Mode> { it.refreshRate }.thenBy { it.modeId },
        ) ?: currentMode

        val attributes = window.attributes
        // Only the rate hint changes; pinning a display mode id can force a
        // heavy vendor mode switch (3.x).
        val targetModeId = 0
        val targetRefreshRate = if (enabled) preferredMode.refreshRate else 0f
        if (
            attributes.preferredDisplayModeId != targetModeId ||
            kotlin.math.abs(attributes.preferredRefreshRate - targetRefreshRate) > 0.01f
        ) {
            attributes.preferredDisplayModeId = targetModeId
            attributes.preferredRefreshRate = targetRefreshRate
            window.attributes = attributes
        }
        return displayModeInfo(if (enabled) preferredMode else currentMode)
    }

    private fun displayModeInfo(preferredMode: Display.Mode? = null): Map<String, Any> {
        val activeDisplay = activeDisplay() ?: return mapOf("enabled" to highRefreshRateEnabled)
        val currentMode = activeDisplay.mode
        val compatibleModes = activeDisplay.supportedModes.filter {
            it.physicalWidth == currentMode.physicalWidth && it.physicalHeight == currentMode.physicalHeight
        }
        val rates = compatibleModes
            .map { it.refreshRate.toDouble() }
            .distinctBy { kotlin.math.round(it * 100).toInt() }
            .sorted()
        val bestMode = preferredMode ?: compatibleModes.maxByOrNull { it.refreshRate } ?: currentMode

        return mapOf(
            "enabled" to highRefreshRateEnabled,
            "currentRefreshRate" to currentMode.refreshRate.toDouble(),
            "maxRefreshRate" to (rates.maxOrNull() ?: currentMode.refreshRate.toDouble()),
            "preferredRefreshRate" to bestMode.refreshRate.toDouble(),
            "supportedRefreshRates" to rates,
            "width" to currentMode.physicalWidth,
            "height" to currentMode.physicalHeight,
            "displayId" to activeDisplay.displayId,
            "preferredDisplayModeId" to window.attributes.preferredDisplayModeId,
            "requestedRefreshRate" to window.attributes.preferredRefreshRate.toDouble(),
        )
    }
}
