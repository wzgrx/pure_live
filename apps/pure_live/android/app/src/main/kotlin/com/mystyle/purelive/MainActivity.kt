package com.mystyle.purelive

import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Hands text shared into the app (a room link or share code, spec/product.md §5)
 * to Dart: the text of the launching intent once, later shares as events.
 * Playlist files shared into the app or opened with it (spec/modules/iptv.md
 * §6) go the same way as `{name, bytes}` on their own channel.
 *
 * Extends audio_service's activity so the media service and the activity share
 * one Flutter engine (background play, F-BG-01); the engine outlives the
 * activity while background audio plays. Picture-in-picture is
 * [PictureInPicture]; the Wi-Fi lock is [PlaybackLocks].
 */
class MainActivity : AudioServiceActivity() {
    private var pendingText: String? = null
    private var pendingFile: Map<String, Any>? = null
    private var pip: PictureInPicture? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        pip?.detach()
        pip = PictureInPicture(this, messenger)
        PlaybackLocks.attach(applicationContext, messenger)
        MethodChannel(messenger, "purelive/share").setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingText" -> {
                    result.success(pendingText)
                    pendingText = null
                }
                "takePendingFile" -> {
                    result.success(pendingFile)
                    pendingFile = null
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
                    shareEvents = sink
                }

                override fun onCancel(arguments: Any?) {
                    shareEvents = null
                }
            },
        )
        EventChannel(messenger, "purelive/share/files").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    fileEvents = sink
                }

                override fun onCancel(arguments: Any?) {
                    fileEvents = null
                }
            },
        )
        // The engine outlives the activity (audio_service caches it), so Dart
        // may already listen: a share that starts a new activity goes out as
        // an event, otherwise it waits for takePendingText / takePendingFile.
        deliver(intent)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        pip?.onUserLeaveHint()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pip?.onModeChanged(isInPictureInPictureMode)
    }

    override fun onDestroy() {
        pip?.detach()
        pip = null
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliver(intent)
    }

    private fun deliver(intent: Intent?) {
        val text = sharedText(intent)
        if (text != null) {
            val sink = shareEvents
            if (sink != null) sink.success(text) else pendingText = text
            return
        }
        val file = sharedFile(intent) ?: return
        val sink = fileEvents
        if (sink != null) sink.success(file) else pendingFile = file
    }

    /**
     * The file of a SEND (EXTRA_STREAM) or VIEW (content URI) intent: its display
     * name and bytes, or null when there is none, it is larger than
     * [MAX_SHARED_FILE] or it cannot be read.
     */
    private fun sharedFile(intent: Intent?): Map<String, Any>? {
        if (intent == null) return null
        val uri = when (intent.action) {
            Intent.ACTION_SEND -> streamOf(intent)
            Intent.ACTION_VIEW -> intent.data
            else -> null
        } ?: return null
        if (uri.scheme != "content") return null
        return try {
            var name: String? = null
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) name = cursor.getString(0)
            }
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                val out = ByteArrayOutputStream()
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    out.write(buffer, 0, read)
                    if (out.size() > MAX_SHARED_FILE) return null
                }
                out.toByteArray()
            } ?: return null
            mapOf("name" to (name ?: uri.lastPathSegment ?: "playlist"), "bytes" to bytes)
        } catch (error: Exception) {
            // Unreadable or the grant was revoked: nothing to import.
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun streamOf(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
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

        /** Largest playlist file handed to Dart (spec/modules/iptv.md §6). */
        const val MAX_SHARED_FILE = 32 * 1024 * 1024

        /**
         * Dart's share listener. Kept per process, not per activity: the cached
         * engine keeps its subscription when a new activity registers the channel
         * again, and that subscription's sink stays valid.
         */
        var shareEvents: EventChannel.EventSink? = null

        /** Dart's playlist-file listener, kept per process like [shareEvents]. */
        var fileEvents: EventChannel.EventSink? = null
    }
}
