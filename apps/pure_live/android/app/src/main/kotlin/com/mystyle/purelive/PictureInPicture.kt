package com.mystyle.purelive

import android.annotation.SuppressLint
import android.app.Activity
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Rect
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Rational
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * System picture-in-picture for the room video (spec/modules/playback.md PIP-2),
 * on channel `purelive/pip` (lib/features/system/pip.dart).
 *
 * Dart sends the aspect ratio (as width/height integers), the video's rect in
 * window pixels, the play state and the auto-enter flag with `enter` and
 * `update`. The activity reports `modeChanged` and the PiP window's play/pause
 * action back on the same channel. Method calls in both directions keep working
 * when a new activity attaches to the cached engine.
 */
internal class PictureInPicture(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)
    private var aspect: Rational? = null
    private var sourceRect: Rect? = null
    private var playing = true
    private var autoEnter = false
    private var receiverRegistered = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != ACTION_CONTROL) return
            channel.invokeMethod("action", intent.getStringExtra(EXTRA_CONTROL))
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(supported)
                "enter" -> {
                    read(call.arguments)
                    result.success(enter())
                }
                "update" -> {
                    read(call.arguments)
                    apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        registerReceiver()
    }

    private val supported: Boolean
        get() = activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun read(arguments: Any?) {
        val map = arguments as? Map<*, *> ?: return
        val width = (map["width"] as? Number)?.toInt() ?: 0
        val height = (map["height"] as? Number)?.toInt() ?: 0
        aspect = if (width > 0 && height > 0) clamp(Rational(width, height)) else null
        val rect = map["sourceRect"] as? List<*>
        sourceRect = if (rect != null && rect.size == 4) {
            val (left, top, right, bottom) = rect.map { (it as? Number)?.toInt() ?: 0 }
            Rect(left, top, right, bottom).takeIf { it.width() > 0 && it.height() > 0 }
        } else {
            null
        }
        (map["playing"] as? Boolean)?.let { playing = it }
        (map["autoEnter"] as? Boolean)?.let { autoEnter = it }
    }

    /** Android rejects ratios outside 1:2.39 to 2.39:1; stay a little inside. */
    private fun clamp(ratio: Rational): Rational {
        val value = ratio.toFloat()
        return when {
            value > MAX_RATIO -> Rational(235, 100)
            value < 1 / MAX_RATIO -> Rational(100, 235)
            else -> ratio
        }
    }

    private fun params(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setActions(listOf(playPauseAction()))
        aspect?.let { builder.setAspectRatio(it) }
        sourceRect?.let { builder.setSourceRectHint(it) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnter)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun playPauseAction(): RemoteAction {
        val control = if (playing) CONTROL_PAUSE else CONTROL_PLAY
        val intent = Intent(ACTION_CONTROL).setPackage(activity.packageName).putExtra(EXTRA_CONTROL, control)
        val pending = PendingIntent.getBroadcast(
            activity,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val icon = Icon.createWithResource(
            activity,
            if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
        )
        val title = if (playing) "暂停" else "播放"
        return RemoteAction(icon, title, title, pending)
    }

    private fun enter(): Boolean {
        if (!supported) return false
        return try {
            activity.enterPictureInPictureMode(params())
        } catch (error: RuntimeException) {
            // IllegalStateException (not resumed) or IllegalArgumentException.
            false
        }
    }

    private fun apply() {
        if (!supported) return
        try {
            activity.setPictureInPictureParams(params())
        } catch (error: RuntimeException) {
            // The next update sends everything again.
        }
    }

    /** Android 11 and older have no auto-enter flag: enter when the user leaves. */
    fun onUserLeaveHint() {
        if (autoEnter && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enter()
    }

    fun onModeChanged(active: Boolean) {
        channel.invokeMethod("modeChanged", active)
    }

    /** Stops receiving PiP actions for this activity. */
    fun detach() {
        if (!receiverRegistered) return
        receiverRegistered = false
        try {
            activity.unregisterReceiver(receiver)
        } catch (error: IllegalArgumentException) {
            // Already unregistered.
        }
    }

    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    private fun registerReceiver() {
        val filter = IntentFilter(ACTION_CONTROL)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            activity.registerReceiver(receiver, filter)
        }
        receiverRegistered = true
    }

    private companion object {
        const val CHANNEL = "purelive/pip"
        const val ACTION_CONTROL = "com.mystyle.purelive.PIP_CONTROL"
        const val EXTRA_CONTROL = "control"
        const val CONTROL_PLAY = "play"
        const val CONTROL_PAUSE = "pause"
        const val REQUEST_CODE = 7301
        const val MAX_RATIO = 2.35f
    }
}
