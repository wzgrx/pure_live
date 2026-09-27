package com.mystyle.purelive

import android.app.Activity
import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.speech.RecognizerIntent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * TV support on channel `purelive/tv` (spec/design/principles.md §5.1 rule 1,
 * §5.3): whether this device is a television, and the platform speech
 * recognizer for TV search.
 *
 * - `device` → `{television, leanback, touchscreen, voiceSearch}`: the UI mode
 *   type, the leanback (or television) feature, a touchscreen, and whether an
 *   activity answers RecognizerIntent.ACTION_RECOGNIZE_SPEECH.
 * - `recognizeSpeech {prompt}` → the first result, or null when cancelled.
 *
 * A plugin rather than code in MainActivity: it is added with one line in
 * configureFlutterEngine, and re-binds to each new activity of the engine
 * (audio_service keeps the engine alive between activities).
 */
class TvSupport : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingSpeech: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) = attach(binding)

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = attach(binding)

    override fun onDetachedFromActivityForConfigChanges() = detach()

    override fun onDetachedFromActivity() = detach()

    private fun attach(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    private fun detach() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        // A recognizer that outlives its activity never answers.
        pendingSpeech?.success(null)
        pendingSpeech = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "device" -> result.success(device())
            "recognizeSpeech" -> recognizeSpeech(call.argument<String>("prompt"), result)
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION") // FEATURE_TELEVISION: older boxes declare only this one.
    private fun device(): Map<String, Boolean> {
        val ctx = context ?: return emptyMap()
        val packages = ctx.packageManager
        val uiMode = (ctx.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager)?.currentModeType
        return mapOf(
            "television" to (uiMode == Configuration.UI_MODE_TYPE_TELEVISION),
            "leanback" to (
                packages.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
                    packages.hasSystemFeature(PackageManager.FEATURE_TELEVISION)
                ),
            "touchscreen" to packages.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN),
            "voiceSearch" to (speechIntent(null).resolveActivity(packages) != null),
        )
    }

    private fun speechIntent(prompt: String?) = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        if (prompt != null) putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
    }

    private fun recognizeSpeech(prompt: String?, result: MethodChannel.Result) {
        val host: Activity = activityBinding?.activity ?: run {
            result.success(null)
            return
        }
        // A newer request replaces one still open.
        pendingSpeech?.success(null)
        pendingSpeech = result
        try {
            host.startActivityForResult(speechIntent(prompt), REQUEST_SPEECH)
        } catch (error: ActivityNotFoundException) {
            pendingSpeech = null
            result.success(null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_SPEECH) return false
        val result = pendingSpeech ?: return true
        pendingSpeech = null
        val text = if (resultCode == Activity.RESULT_OK) {
            data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
        } else {
            null
        }
        result.success(text)
        return true
    }

    private companion object {
        const val CHANNEL = "purelive/tv"

        /** Below 16 bits, as FragmentActivity requires. */
        const val REQUEST_SPEECH = 0x7456
    }
}
