package com.mystyle.purelive

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * `pure_live/recorder` (3.x RecorderBackgroundPlugin and permission_handler's
 * storage requests, reduced to what the recorder uses):
 * - `setActive {active, title, text, …}`: starts [RecorderForegroundService]
 *   and answers once it is in the foreground, or stops it; `update` sends
 *   new words, `alert {id, title, text}` posts "录制已停止" ([RecordWords],
 *   docs/A-界面设计/A14-系统界面/A14.1-系统界面 c3–c5);
 * - to Dart, `stopAll` when the notification's "停止录制" is pressed;
 * - `requestStorage`: all-files access (API 30+, the system settings page) or
 *   the storage permission (API 26–29); answers whether it is granted;
 * - `storageGranted`: the same without asking;
 * - to Dart, `interrupted {reason}` when Android ended the service
 *   (`timeout`, `service_stopped`).
 *
 * The recorder lives in this engine's Dart isolate, so the service stops
 * with the engine.
 */
internal class RecorderPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener,
    RecorderForegroundService.Listener {
    companion object {
        private const val CHANNEL = "pure_live/recorder"
        private const val ERROR = "recorder_background_unavailable"
        private const val START_TIMEOUT_MILLIS = 15_000L
        private const val STORAGE_REQUEST = 20260907
    }

    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var activity: ActivityPluginBinding? = null
    private val handler = Handler(Looper.getMainLooper())
    private var active = false
    private var pendingStart: MethodChannel.Result? = null
    private var storageResult: MethodChannel.Result? = null
    private val startTimeout = Runnable { failStart("Timed out while starting the recording service") }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
        RecorderForegroundService.listener = this
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        if (RecorderForegroundService.listener === this) RecorderForegroundService.listener = null
        handler.removeCallbacks(startTimeout)
        pendingStart?.error(ERROR, "Recorder engine detached", null)
        pendingStart = null
        if (active) context?.let(RecorderForegroundService::stop)
        active = false
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setActive" -> setActive(call, result)
            "update" -> {
                context?.let { RecorderForegroundService.update(it, RecordWords.from(call.arguments)) }
                result.success(null)
            }

            "alert" -> {
                val context = context
                if (context != null) {
                    RecorderForegroundService.alert(
                        context,
                        call.argument<String>("id").orEmpty(),
                        call.argument<String>("title").orEmpty().take(120),
                        call.argument<String>("text").orEmpty().take(400),
                        RecordWords.from(call.arguments),
                    )
                }
                result.success(null)
            }

            "storageGranted" -> result.success(storageGranted())
            "requestStorage" -> requestStorage(result)
            else -> result.notImplemented()
        }
    }

    private fun setActive(call: MethodCall, result: MethodChannel.Result) {
        val context = context ?: return result.error(ERROR, "Recorder engine detached", null)
        if (call.argument<Boolean>("active") != true) {
            handler.removeCallbacks(startTimeout)
            pendingStart?.error(ERROR, "Superseded by a stop request", null)
            pendingStart = null
            if (active) RecorderForegroundService.stop(context)
            active = false
            result.success(null)
            return
        }
        if (active && pendingStart == null) return result.success(null)
        if (pendingStart != null) return result.error(ERROR, "The recording service is already starting", null)
        pendingStart = result
        active = true
        handler.postDelayed(startTimeout, START_TIMEOUT_MILLIS)
        try {
            RecorderForegroundService.start(context, RecordWords.from(call.arguments))
        } catch (exception: Exception) {
            failStart(exception.localizedMessage ?: "Foreground service startup failed")
        }
    }

    private fun failStart(message: String) {
        handler.removeCallbacks(startTimeout)
        val result = pendingStart ?: return
        pendingStart = null
        if (active) context?.let(RecorderForegroundService::stop)
        active = false
        result.error(ERROR, message.replace(Regex("[\\r\\n\\t]+"), " ").take(240), null)
    }

    override fun onReady() {
        handler.removeCallbacks(startTimeout)
        pendingStart?.success(null)
        pendingStart = null
    }

    override fun onStartFailed(message: String) = failStart(message)

    override fun onEnded(reason: String) {
        if (!active) return
        if (pendingStart != null) {
            failStart("The recording service stopped during startup")
            return
        }
        active = false
        channel?.invokeMethod("interrupted", mapOf("reason" to reason))
    }

    // The notification's "停止录制" (U.14 c4): the recorder stops its tasks
    // and then releases the service.
    override fun onStopRequested() {
        if (active) channel?.invokeMethod("stopAll", null)
    }

    private fun storageGranted(): Boolean {
        val context = context ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestStorage(result: MethodChannel.Result) {
        if (storageGranted()) return result.success(true)
        val activity: Activity = activity?.activity ?: return result.success(false)
        if (storageResult != null) return result.error(ERROR, "A storage request is already open", null)
        storageResult = result
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val appPage = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                    .setData(Uri.parse("package:${activity.packageName}"))
                val intent = if (appPage.resolveActivity(activity.packageManager) != null) {
                    appPage
                } else {
                    Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                }
                activity.startActivityForResult(intent, STORAGE_REQUEST)
            } else {
                activity.requestPermissions(
                    arrayOf(
                        Manifest.permission.WRITE_EXTERNAL_STORAGE,
                        Manifest.permission.READ_EXTERNAL_STORAGE,
                    ),
                    STORAGE_REQUEST,
                )
            }
        } catch (exception: Exception) {
            storageResult = null
            result.success(false)
        }
    }

    private fun finishStorage() {
        val result = storageResult ?: return
        storageResult = null
        result.success(storageGranted())
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != STORAGE_REQUEST) return false
        finishStorage()
        return true
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != STORAGE_REQUEST) return false
        finishStorage()
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activity?.removeActivityResultListener(this)
        activity?.removeRequestPermissionsResultListener(this)
        activity = null
        finishStorage()
    }
}
