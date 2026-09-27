package com.mystyle.purelive

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Hands text shared into the app (a room link or share code, spec/product.md §5)
 * to Dart: the text of the launching intent once, later shares as events.
 */
class MainActivity : FlutterActivity() {
    private var pendingText: String? = null
    private var events: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingText = sharedText(intent)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "purelive/share").setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingText" -> {
                    result.success(pendingText)
                    pendingText = null
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "purelive/share/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    events = sink
                }

                override fun onCancel(arguments: Any?) {
                    events = null
                }
            },
        )
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = sharedText(intent) ?: return
        val sink = events
        if (sink != null) sink.success(text) else pendingText = text
    }

    private fun sharedText(intent: Intent?): String? =
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            intent.getStringExtra(Intent.EXTRA_TEXT)?.takeIf { it.isNotBlank() }
        } else {
            null
        }
}
