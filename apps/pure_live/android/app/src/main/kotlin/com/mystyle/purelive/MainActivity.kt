package com.mystyle.purelive

import android.content.Intent
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

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
        MethodChannel(messenger, "purelive/keystore").setMethodCallHandler { call, result ->
            try {
                val data = call.argument<ByteArray>("data")!!
                val aad = call.argument<ByteArray>("aad")!!
                when (call.method) {
                    "seal" -> result.success(seal(data, aad))
                    "open" -> result.success(open(data, aad))
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                // No secret material in the message: only the kind of failure.
                result.error("keystore", error.javaClass.simpleName, null)
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

    /**
     * Secrets at rest (spec/modules/store.md §4): AES-256-GCM with a
     * non-exportable Android Keystore key. Blob = 12-byte IV + ciphertext + tag;
     * the reference name is the associated data.
     */
    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun seal(plaintext: ByteArray, aad: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        cipher.updateAAD(aad)
        return cipher.iv + cipher.doFinal(plaintext)
    }

    private fun open(blob: ByteArray, aad: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, blob.copyOfRange(0, 12)))
        cipher.updateAAD(aad)
        return cipher.doFinal(blob.copyOfRange(12, blob.size))
    }

    private companion object {
        const val KEY_ALIAS = "purelive.secrets.v1"
    }
}
