package com.mystyle.purelive

import android.app.AlertDialog
import android.app.AppOpsManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.hardware.display.DisplayManager
import android.media.AudioManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import android.text.InputType
import android.util.Rational
import android.util.TypedValue
import android.view.Display
import android.view.Surface
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
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
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The app's activity (3.x MainActivity at v3.2.11). Like 3.x it is
 * audio_service's [AudioServiceActivity]: the Flutter engine is cached, so
 * the live room's media notification (M13.14) and recording keep running
 * when the activity goes away.
 *
 * Channels:
 * - `pure_live/display_mode`: the refresh rate AdaptiveRefreshRateScope asks
 *   for and, while the live room plays, the rate chosen for the video (U.2i;
 *   P01: [applyRefreshRate]);
 * - `pure_live/background_playback`: wake and Wi-Fi locks while playing in the background;
 * - `pure_live/predictive_back`: the live room's back arbitration;
 * - `pure_live/app`: back to the background, whether this is a television
 *   (the TV interface, M14.1) and a native one-line text input for the remote;
 * - `pure_live/secret_cipher`, `pure_live/native_http`, `pure_live/multicast_lock`
 *   (registered by [AppChannelsPlugin], so they also work on an engine without
 *   an activity);
 * - `pure_live/recorder`: recording's foreground service and storage access
 *   ([RecorderPlugin]);
 * - `pure_live/system_access`: installing update packages and the
 *   local-network permission ([SystemAccessPlugin]);
 * - `pure_live/pip`: the live room's picture-in-picture (3.x used the
 *   floating plugin); `changed` reports entering and leaving. U.2j: `status`
 *   tells whether the system settings turned it off for the app, `enter`
 *   answers `entered`, `disabled` or `failed`, `openSettings` opens the app's
 *   picture-in-picture page of the system settings, `setAutoEnter` lets
 *   leaving the app (home, recents) enter it by itself; U.14 c7:
 *   `setPlaying {playing, play, pause}` shows the window's pause / play
 *   action, a tap is sent back as `togglePlay`;
 * - `pure_live/share_intake` ([ShareIntakePlugin]), `pure_live/permissions`
 *   ([PermissionsPlugin]): F.0a;
 * - `pure_live/background_guide` ([BackgroundGuidePlugin]): the "后台播放检查"
 *   state and the vendors' system pages (O01.3);
 * - `pure_live/app` `setSplashTheme {mode}`: Android 13's splash screen in
 *   the app's own light or dark (U.14 c9);
 * - `pure_live/app` `startupInfo`, `reportFullyDrawn`: the start-up's
 *   timing (R04.1): whether this is the process's first start of Dart (a
 *   cold start) and the process's age; home's first content drawn;
 * - `pure_live/device_controls`: the media volume and the window's
 *   brightness for the live room's gestures (3.x used the volume_controller
 *   and screen_brightness plugins), and the battery level of the fullscreen
 *   bars (3.x used battery_plus).
 */
class MainActivity : AudioServiceActivity() {
    companion object {
        private const val DISPLAY_MODE_CHANNEL = "pure_live/display_mode"
        private const val BACKGROUND_PLAYBACK_CHANNEL = "pure_live/background_playback"
        private const val PREDICTIVE_BACK_CHANNEL = "pure_live/predictive_back"
        private const val APP_CHANNEL = "pure_live/app"
        private const val PIP_CHANNEL = "pure_live/pip"
        private const val DEVICE_CONTROLS_CHANNEL = "pure_live/device_controls"
        private const val PIP_TOGGLE = "com.mystyle.purelive.PIP_TOGGLE"
        private var playbackWakeLock: PowerManager.WakeLock? = null
        private var playbackWifiLock: WifiManager.WifiLock? = null

        // Android 10-13: the lock that works with the screen off (O01.3 R4).
        private var playbackBackgroundWifiLock: WifiManager.WifiLock? = null

        // R04.1: taken by the first `startupInfo` of the process; a Dart
        // start after it (a recreated activity, a restart) is not cold.
        private val coldStartTaken = AtomicBoolean(false)
    }

    // Android's dynamic policy until Dart asks for the high rate.
    private var highRefreshRateEnabled = false

    // P01: while the live room plays, the rate Dart chose for the video, to
    // declare on Flutter's surface as a fixed source; 0 = nothing plays.
    private var playbackFrameRate = 0f

    // P01: while the live room plays, the window's hint where nothing can be
    // declared (Android 8-11); 0 = the system's choice.
    private var playbackWindowRate = 0f
    private var displayModeChannel: MethodChannel? = null
    private var predictiveBackChannel: MethodChannel? = null
    private var pipChannel: MethodChannel? = null

    // U.14 c7: the picture-in-picture window's pause / play action.
    private var pipPlaying: Boolean? = null
    private var pipPlayLabel = "播放"
    private var pipPauseLabel = "暂停"
    private var pipReceiverRegistered = false
    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            pipChannel?.invokeMethod("togglePlay", null)
        }
    }

    // U.2j J1: leaving the app enters picture-in-picture while the room plays.
    private var autoEnterPip = false
    private var autoEnterRatio = Rational(16, 9)
    private var predictiveBackEnabled = false
    private var predictiveBackRegistered = false
    private var displayListenerRegistered = false
    private var lastPublishedDisplayModeInfo: Map<String, Any>? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val displayModeRefresh = Runnable {
        // A new surface (back from the background) forgets the declaration.
        val info = applyRefreshRate()
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

    /**
     * R04.1: FlutterActivity reports "fully drawn" at the first Flutter frame
     * (API 29+), and Android keeps only the first report of a launch, so the
     * app's own report when home's first content shows (`reportFullyDrawn`
     * on `pure_live/app`) was ignored: K90 logged "Fully drawn" equal to
     * TotalTime (~360 ms) while home came at ~1.1 s. Only the app reports.
     */
    override fun onFlutterUiDisplayed() {}

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(AppChannelsPlugin::class.java)) {
            flutterEngine.plugins.add(AppChannelsPlugin())
        }
        // Recording's foreground service and storage access (M13.15).
        if (!flutterEngine.plugins.has(RecorderPlugin::class.java)) {
            flutterEngine.plugins.add(RecorderPlugin())
        }
        // Installing update packages and the local-network permission (M12.4).
        if (!flutterEngine.plugins.has(SystemAccessPlugin::class.java)) {
            flutterEngine.plugins.add(SystemAccessPlugin())
        }
        // Shares, "open with", shortcuts and the clipboard's change time (F.0a).
        if (!flutterEngine.plugins.has(ShareIntakePlugin::class.java)) {
            flutterEngine.plugins.add(ShareIntakePlugin())
        }
        // Notifications and battery optimisation (F.0a).
        if (!flutterEngine.plugins.has(PermissionsPlugin::class.java)) {
            flutterEngine.plugins.add(PermissionsPlugin())
        }
        // "后台播放检查": the vendor's background state and pages (O01.3).
        if (!flutterEngine.plugins.has(BackgroundGuidePlugin::class.java)) {
            flutterEngine.plugins.add(BackgroundGuidePlugin())
        }
        displayModeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DISPLAY_MODE_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setHighRefreshRate" -> {
                        highRefreshRateEnabled = call.argument<Boolean>("enabled") ?: true
                        playbackFrameRate = (call.argument<Number>("frameRate")?.toFloat() ?: 0f).coerceAtLeast(0f)
                        playbackWindowRate = (call.argument<Number>("refreshRate")?.toFloat() ?: 0f).coerceAtLeast(0f)
                        val info = applyRefreshRate()
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
                "setSplashTheme" -> {
                    setSplashTheme(call.argument<String>("mode"))
                    result.success(null)
                }
                "startupInfo" -> result.success(
                    mapOf(
                        "cold" to coldStartTaken.compareAndSet(false, true),
                        "sinceProcessStart" to SystemClock.elapsedRealtime() - Process.getStartElapsedRealtime(),
                    ),
                )
                "reportFullyDrawn" -> {
                    reportFullyDrawn()
                    result.success(null)
                }
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
                    "status" -> result.success(pictureInPictureStatus())
                    "enter" -> result.success(
                        enterPictureInPicture(call.argument<Int>("width") ?: 16, call.argument<Int>("height") ?: 9),
                    )

                    "openSettings" -> result.success(openPictureInPictureSettings())
                    "setPlaying" -> {
                        setPictureInPicturePlaying(
                            call.argument<Boolean>("playing"),
                            call.argument<String>("play"),
                            call.argument<String>("pause"),
                        )
                        result.success(null)
                    }
                    "setAutoEnter" -> {
                        setAutoEnterPictureInPicture(
                            call.argument<Boolean>("enabled") ?: false,
                            call.argument<Int>("width") ?: 16,
                            call.argument<Int>("height") ?: 9,
                        )
                        result.success(null)
                    }

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

                "getBattery" -> result.success(batteryLevel())

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
        applyRefreshRate()
    }

    /** The battery charge in percent, or null when the device reports none. */
    private fun batteryLevel(): Int? {
        val manager = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager ?: return null
        val level = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return if (level in 0..100) level else null
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

    /** Android accepts ratios between 1:2.39 and 2.39:1. */
    private fun pictureInPictureRatio(width: Int, height: Int): Rational {
        val ratio = (width.coerceAtLeast(1).toDouble() / height.coerceAtLeast(1)).coerceIn(1 / 2.39, 2.39)
        return Rational((ratio * 1000).toInt(), 1000)
    }

    /**
     * Whether the system settings let this app use picture-in-picture
     * ("Settings > Apps > Picture-in-picture"); 3.x ignored a refusal.
     */
    @Suppress("DEPRECATION")
    private fun pictureInPictureAllowed(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager ?: return true
        val mode = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_PICTURE_IN_PICTURE, Process.myUid(), packageName)
            } else {
                appOps.checkOpNoThrow(AppOpsManager.OPSTR_PICTURE_IN_PICTURE, Process.myUid(), packageName)
            }
        } catch (_: RuntimeException) {
            return true
        }
        return mode != AppOpsManager.MODE_IGNORED && mode != AppOpsManager.MODE_ERRORED
    }

    private fun pictureInPictureStatus(): String = when {
        !pictureInPictureSupported() -> "unsupported"
        !pictureInPictureAllowed() -> "disabled"
        else -> "allowed"
    }

    private fun enterPictureInPicture(width: Int, height: Int): String {
        if (!pictureInPictureSupported()) return "failed"
        if (!pictureInPictureAllowed()) return "disabled"
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(pictureInPictureRatio(width, height))
            .setActions(pictureInPictureActions())
            .build()
        return try {
            if (enterPictureInPictureMode(params)) "entered" else "failed"
        } catch (ignored: IllegalStateException) {
            "failed"
        } catch (ignored: IllegalArgumentException) {
            "failed"
        }
    }

    /**
     * This app's page of the system's picture-in-picture settings; the app's
     * details page where a vendor build has none.
     */
    private fun openPictureInPictureSettings(): Boolean {
        val uri = Uri.fromParts("package", packageName, null)
        val intents = listOf(
            Intent("android.settings.PICTURE_IN_PICTURE_SETTINGS", uri),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri),
        )
        for (intent in intents) {
            try {
                startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: ActivityNotFoundException) {
                // The next one.
            } catch (_: SecurityException) {
                // The next one.
            }
        }
        return false
    }

    /**
     * Android 12 and later enter picture-in-picture by themselves on the way
     * home (smoothly); 8-11 enter from [onUserLeaveHint].
     */
    private fun setAutoEnterPictureInPicture(enabled: Boolean, width: Int, height: Int) {
        autoEnterPip = enabled && pictureInPictureSupported()
        autoEnterRatio = pictureInPictureRatio(width, height)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || !pictureInPictureSupported()) return
        try {
            setPictureInPictureParams(
                PictureInPictureParams.Builder()
                    .setAspectRatio(autoEnterRatio)
                    .setAutoEnterEnabled(autoEnterPip)
                    .setActions(pictureInPictureActions())
                    .build(),
            )
        } catch (ignored: IllegalStateException) {
            // The activity is going away.
        } catch (ignored: IllegalArgumentException) {
            // A ratio the device refuses.
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!autoEnterPip || Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || isInPictureInPictureMode || !pictureInPictureAllowed()) return
        try {
            enterPictureInPictureMode(
                PictureInPictureParams.Builder()
                    .setAspectRatio(autoEnterRatio)
                    .setActions(pictureInPictureActions())
                    .build(),
            )
        } catch (_: IllegalStateException) {
            // Refused; the room pauses as it would without it.
        } catch (ignored: IllegalArgumentException) {
            // Refused.
        }
    }

    /**
     * The pause / play action of the picture-in-picture window (U.14 c7; 3.x
     * had none): shown while a room is bound ([playing] not null), the
     * system draws it; a tap reaches Dart as `togglePlay`.
     */
    private fun pictureInPictureActions(): List<RemoteAction> {
        val playing = pipPlaying ?: return emptyList()
        val label = if (playing) pipPauseLabel else pipPlayLabel
        val tap = PendingIntent.getBroadcast(
            this,
            0,
            Intent(PIP_TOGGLE).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val icon = Icon.createWithResource(this, if (playing) R.drawable.ic_pip_pause else R.drawable.ic_pip_play)
        return listOf(RemoteAction(icon, label, label, tap))
    }

    private fun setPictureInPicturePlaying(playing: Boolean?, play: String?, pause: String?) {
        pipPlaying = playing
        if (!play.isNullOrBlank()) pipPlayLabel = play
        if (!pause.isNullOrBlank()) pipPauseLabel = pause
        if (playing != null && !pipReceiverRegistered) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(pipReceiver, IntentFilter(PIP_TOGGLE), Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(pipReceiver, IntentFilter(PIP_TOGGLE))
            }
            pipReceiverRegistered = true
        }
        if (!pictureInPictureSupported()) return
        try {
            // Merged into the window's current parameters.
            setPictureInPictureParams(PictureInPictureParams.Builder().setActions(pictureInPictureActions()).build())
        } catch (_: IllegalStateException) {
            // The activity is going away.
        } catch (_: IllegalArgumentException) {
            // Refused.
        }
    }

    /** Android 13+: the next cold start's splash in the app's own light or dark (U.14 c9). */
    private fun setSplashTheme(mode: String?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val theme = when (mode) {
            "Light" -> R.style.SplashTheme_Light
            "Dark" -> R.style.SplashTheme_Dark
            // Resources.ID_NULL: back to the manifest theme (the system's light or dark).
            else -> 0
        }
        try {
            splashScreen.setSplashScreenTheme(theme)
        } catch (_: RuntimeException) {
            // A vendor build without it.
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

    /**
     * The wake and Wi-Fi locks while a room plays away from the app (Dart
     * holds them only while something is kept, O01.3). Wi-Fi: the
     * low-latency lock works only while the app is in front with the screen
     * on (picture-in-picture), so Android 10-13 also hold the high-performance
     * lock, the one that keeps Wi-Fi out of power save in the background;
     * from Android 14 the system turns that one into a low-latency lock, so
     * it is not asked for twice; before 10 it is the only one.
     */
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

            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            if (playbackWifiLock == null) {
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
            if (playbackBackgroundWifiLock == null &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE
            ) {
                playbackBackgroundWifiLock = wifiManager.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                    "$packageName:backgroundPlaybackScreenOff",
                ).apply { setReferenceCounted(false) }
            }
            if (playbackBackgroundWifiLock?.isHeld == false) playbackBackgroundWifiLock?.acquire()
        } else {
            if (playbackBackgroundWifiLock?.isHeld == true) playbackBackgroundWifiLock?.release()
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
        if (pipReceiverRegistered) {
            try {
                unregisterReceiver(pipReceiver)
            } catch (_: IllegalArgumentException) {
                // Not registered.
            }
            pipReceiverRegistered = false
        }
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

    /**
     * Asks the display for a refresh rate (P01, docs/R-性能和流畅度/R02-刷新率/R02.1-刷新率和帧率匹配
     * "4.0.x 修订"; Dart decides which rate, this decides how):
     *
     * - the live room plays: Android 12+ only declares Dart's rate on
     *   Flutter's surface as a fixed source, switched only when seamless (the
     *   video is a texture inside that surface; Android ignores the window's
     *   preferred rate for a surface that declares one, so the hint is
     *   cleared). Android 8-11 cannot limit the switch to seamless ones and
     *   keep the window hint (U.2i);
     * - nothing plays and Dart asks for the high rate: Android 16+ declares
     *   the highest rate as a minimum (AT_LEAST, meant for interfaces); 8-15
     *   keep the window hint (3.x);
     * - otherwise both are cleared: the system's choice.
     *
     * Always a number, never a frame-rate category: the K90's HIGH category
     * is 90 Hz.
     */
    private fun applyRefreshRate(): Map<String, Any> {
        val activeDisplay = activeDisplay() ?: return displayModeInfo()
        val currentMode = activeDisplay.mode
        val compatibleModes = activeDisplay.supportedModes.filter {
            it.physicalWidth == currentMode.physicalWidth && it.physicalHeight == currentMode.physicalHeight
        }
        val topMode = compatibleModes.maxWithOrNull(
            compareBy<Display.Mode> { it.refreshRate }.thenBy { it.modeId },
        ) ?: currentMode
        // The playback's rate as the nearest mode of this resolution.
        val playbackMode = playbackWindowRate.takeIf { it > 0f }?.let { rate ->
            compatibleModes.minByOrNull { kotlin.math.abs(it.refreshRate - rate) }
        }
        val playing = playbackFrameRate > 0f
        var surfaceRate = 0f
        var compatibility = Surface.FRAME_RATE_COMPATIBILITY_DEFAULT
        var windowRate = 0f
        when {
            playing && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                surfaceRate = playbackFrameRate
                compatibility = Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE
            }

            playing -> windowRate = playbackMode?.refreshRate ?: 0f
            highRefreshRateEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA -> {
                surfaceRate = topMode.refreshRate
                compatibility = Surface.FRAME_RATE_COMPATIBILITY_AT_LEAST
            }

            highRefreshRateEnabled -> windowRate = topMode.refreshRate
        }
        applySurfaceFrameRate(surfaceRate, compatibility)

        val attributes = window.attributes
        // Only the rate hint changes; pinning a display mode id can force a
        // heavy vendor mode switch (3.x).
        val targetModeId = 0
        if (
            attributes.preferredDisplayModeId != targetModeId ||
            kotlin.math.abs(attributes.preferredRefreshRate - windowRate) > 0.01f
        ) {
            attributes.preferredDisplayModeId = targetModeId
            attributes.preferredRefreshRate = windowRate
            window.attributes = attributes
        }
        val requestedMode = when {
            playing -> playbackMode ?: currentMode
            highRefreshRateEnabled -> topMode
            else -> currentMode
        }
        return displayModeInfo(requestedMode)
    }

    /**
     * Declares [rate] on Flutter's surface, or clears the declaration (0).
     * Android 12 and later only, where the switch can be limited to seamless
     * ones.
     */
    private fun applySurfaceFrameRate(rate: Float, compatibility: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val surface = flutterSurfaceView()?.holder?.surface ?: return
        if (!surface.isValid) return
        try {
            surface.setFrameRate(
                rate,
                if (rate > 0f) compatibility else Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS,
            )
        } catch (ignored: IllegalArgumentException) {
            // A rate the system does not take: it keeps its own choice.
        } catch (ignored: IllegalStateException) {
            // The surface went away meanwhile.
        }
    }

    /** Flutter's [SurfaceView] (none with a texture render mode). */
    private fun flutterSurfaceView(): SurfaceView? {
        val root: View = findViewById(FlutterActivity.FLUTTER_VIEW_ID) ?: window.decorView
        return findSurfaceView(root)
    }

    private fun findSurfaceView(view: View): SurfaceView? {
        if (view is SurfaceView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findSurfaceView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
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
