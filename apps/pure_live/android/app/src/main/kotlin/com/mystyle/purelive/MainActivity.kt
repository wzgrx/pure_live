package com.mystyle.purelive

import android.app.AlertDialog
import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.hardware.display.DisplayManager
import android.media.AudioManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.text.InputType
import android.util.Rational
import android.util.TypedValue
import android.view.Display
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.window.BackEvent
import android.window.OnBackAnimationCallback
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app's activity (3.x MainActivity at v3.2.11). Like 3.x it is
 * audio_service's [AudioServiceActivity]: the Flutter engine is cached, so
 * the live room's media notification (M13.14) and recording keep running
 * when the activity goes away.
 *
 * Channels:
 * - `pure_live/display_mode`: the refresh-rate hint of AdaptiveRefreshRateScope;
 * - `pure_live/background_playback`: wake and Wi-Fi locks while playing in the background;
 * - `pure_live/predictive_back`: the live room's back arbitration;
 * - `pure_live/app`: back to the background, whether this is a television
 *   (the TV interface, M14.1) and a native one-line text input for the remote;
 * - `pure_live/secret_cipher`, `pure_live/native_http`, `pure_live/multicast_lock`
 *   (registered by [AppChannelsPlugin], so they also work on an engine without
 *   an activity);
 * - `pure_live/recorder`: recording's foreground service and storage access
 *   ([RecorderPlugin]);
 * - `pure_live/pip`: the live room's picture-in-picture (3.x used the
 *   floating plugin); `changed` reports entering and leaving;
 * - `pure_live/device_controls`: the media volume and the window's
 *   brightness for the live room's gestures (3.x used the volume_controller
 *   and screen_brightness plugins).
 */
class MainActivity : AudioServiceActivity() {
    companion object {
        private const val DISPLAY_MODE_CHANNEL = "pure_live/display_mode"
        private const val BACKGROUND_PLAYBACK_CHANNEL = "pure_live/background_playback"
        private const val PREDICTIVE_BACK_CHANNEL = "pure_live/predictive_back"
        private const val APP_CHANNEL = "pure_live/app"
        private const val PIP_CHANNEL = "pure_live/pip"
        private const val DEVICE_CONTROLS_CHANNEL = "pure_live/device_controls"
        private var playbackWakeLock: PowerManager.WakeLock? = null
        private var playbackWifiLock: WifiManager.WifiLock? = null
    }

    // Android's dynamic policy until Dart asks for the high rate.
    private var highRefreshRateEnabled = false
    private var displayModeChannel: MethodChannel? = null
    private var predictiveBackChannel: MethodChannel? = null
    private var pipChannel: MethodChannel? = null
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
        // Recording's foreground service and storage access (M13.15).
        if (!flutterEngine.plugins.has(RecorderPlugin::class.java)) {
            flutterEngine.plugins.add(RecorderPlugin())
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
        // closing it (3.x used the move_to_desktop plugin). The TV interface
        // (M14.1) asks whether this is a television and types text through a
        // native dialog: the system keyboard opens reliably from an EditText,
        // where Flutter's text input stays closed on some TV boxes.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "moveToBack" -> result.success(moveTaskToBack(true))
                "isTelevision" -> result.success(isTelevision())
                "inputText" -> showTextInput(
                    call.argument<String>("title") ?: "",
                    call.argument<String>("hint") ?: "",
                    call.argument<String>("text") ?: "",
                    result,
                )

                else -> result.notImplemented()
            }
        }
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(pictureInPictureSupported())
                    "enter" -> result.success(
                        enterPictureInPicture(call.argument<Int>("width") ?: 16, call.argument<Int>("height") ?: 9),
                    )

                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CONTROLS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getVolume" -> result.success(mediaVolume())
                "setVolume" -> {
                    setMediaVolume(call.argument<Double>("value") ?: 0.0)
                    result.success(null)
                }

                "getBrightness" -> result.success(windowBrightness())
                "setBrightness" -> {
                    setWindowBrightness((call.argument<Double>("value") ?: 0.5).toFloat())
                    result.success(null)
                }

                "resetBrightness" -> {
                    setWindowBrightness(WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE)
                    result.success(null)
                }

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

    /** A television: the TV UI mode, or a device with the leanback feature (Android TV, Google TV, most boxes). */
    private fun isTelevision(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        if (uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) return true
        return packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
    }

    /**
     * One line of text from the system keyboard: [text] to edit, null when
     * cancelled. Done or search on the keyboard confirms, like OK.
     */
    private fun showTextInput(title: String, hint: String, text: String, result: MethodChannel.Result) {
        var answered = false
        fun answer(value: String?) {
            if (answered) return
            answered = true
            result.success(value)
        }
        val input = EditText(this).apply {
            setText(text)
            setSelection(text.length)
            this.hint = hint
            isSingleLine = true
            inputType = InputType.TYPE_CLASS_TEXT
            imeOptions = EditorInfo.IME_ACTION_DONE or EditorInfo.IME_FLAG_NO_EXTRACT_UI
        }
        val padding = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 20f, resources.displayMetrics).toInt()
        val frame = FrameLayout(this).apply {
            setPadding(padding, padding / 2, padding, 0)
            addView(input)
        }
        val dialog = AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle(title.ifEmpty { null })
            .setView(frame)
            .setPositiveButton(android.R.string.ok) { _, _ -> answer(input.text.toString()) }
            .setNegativeButton(android.R.string.cancel) { _, _ -> answer(null) }
            .create()
        dialog.setOnDismissListener { answer(null) }
        input.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE || actionId == EditorInfo.IME_ACTION_SEARCH ||
                actionId == EditorInfo.IME_ACTION_GO
            ) {
                answer(input.text.toString())
                dialog.dismiss()
                true
            } else {
                false
            }
        }
        dialog.setOnShowListener {
            input.requestFocus()
            input.postDelayed({
                (getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)
                    ?.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
            }, 120)
        }
        dialog.window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)
        try {
            dialog.show()
        } catch (_: RuntimeException) {
            answer(null)
        }
    }

    private fun pictureInPictureSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun enterPictureInPicture(width: Int, height: Int): Boolean {
        if (!pictureInPictureSupported()) return false
        // Android accepts ratios between 1:2.39 and 2.39:1.
        val ratio = (width.coerceAtLeast(1).toDouble() / height.coerceAtLeast(1)).coerceIn(1 / 2.39, 2.39)
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(Rational((ratio * 1000).toInt(), 1000))
            .build()
        return try {
            enterPictureInPictureMode(params)
        } catch (_: IllegalStateException) {
            false
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("changed", isInPictureInPictureMode)
    }

    private fun mediaVolume(): Double {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        return if (max <= 0) 0.0 else audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max
    }

    private fun setMediaVolume(value: Double) {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val index = kotlin.math.round(value.coerceIn(0.0, 1.0) * max).toInt()
        try {
            audio.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
        } catch (_: SecurityException) {
            // Do Not Disturb refuses volume changes.
        }
    }

    private fun windowBrightness(): Double {
        val own = window.attributes.screenBrightness
        if (own >= 0) return own.toDouble()
        return try {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS) / 255.0
        } catch (_: Settings.SettingNotFoundException) {
            0.5
        }
    }

    private fun setWindowBrightness(value: Float) {
        val attributes = window.attributes
        attributes.screenBrightness =
            if (value < 0) WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE else value.coerceIn(0.01f, 1f)
        window.attributes = attributes
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
        pipChannel = null
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
