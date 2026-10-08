package com.mystyle.purelive

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.URI
import java.nio.ByteBuffer
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction
import java.security.KeyStore
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The app's own channels that do not need an activity:
 * - `pure_live/secret_cipher`: seals cookies and passwords with an Android
 *   Keystore key (live_store's SecretCipher);
 * - `pure_live/native_http`: HTTPS through the platform TLS stack for hosts
 *   that refuse dart:io (Twitch GraphQL through a proxy; Kick later);
 * - `pure_live/text_codec`: GBK playlists (IPTV);
 * - `pure_live/multicast_lock`: the Wi-Fi multicast lock of DLNA discovery;
 * - `pure_live/live_alerts`: `post` "开播提醒" ([LiveAlerts], O01.1).
 */
internal class AppChannelsPlugin : FlutterPlugin {
    private val channels = mutableListOf<MethodChannel>()
    private var executor: ExecutorService? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val pool = Executors.newFixedThreadPool(2)
        executor = pool
        val context = binding.applicationContext
        val messenger = binding.binaryMessenger
        channel(messenger, "pure_live/secret_cipher") { call, result ->
            background(pool, result) { SecretCipherChannel.handle(call) }
        }
        channel(messenger, "pure_live/native_http") { call, result ->
            background(pool, result) { NativeHttpChannel.handle(call) }
        }
        channel(messenger, "pure_live/text_codec") { call, result ->
            background(pool, result) { TextCodecChannel.handle(call) }
        }
        channel(messenger, "pure_live/live_alerts") { call, result ->
            when (call.method) {
                "post" -> result.success(LiveAlerts.post(context, call.arguments))
                else -> result.notImplemented()
            }
        }
        channel(messenger, "pure_live/multicast_lock") { call, result ->
            when (call.method) {
                "acquire" -> result.success(acquireMulticastLock(context))
                "release" -> {
                    releaseMulticastLock()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channels.forEach { it.setMethodCallHandler(null) }
        channels.clear()
        executor?.shutdownNow()
        executor = null
        releaseMulticastLock()
    }

    private fun channel(messenger: BinaryMessenger, name: String, handler: MethodChannel.MethodCallHandler) {
        channels += MethodChannel(messenger, name).also { it.setMethodCallHandler(handler) }
    }

    private fun background(pool: ExecutorService, result: MethodChannel.Result, work: () -> Any?) {
        val main = Handler(Looper.getMainLooper())
        pool.execute {
            try {
                val value = work()
                main.post {
                    if (value === NotImplemented) result.notImplemented() else result.success(value)
                }
            } catch (error: Throwable) {
                main.post { result.error("failed", error.message ?: error.javaClass.simpleName, null) }
            }
        }
    }

    private fun acquireMulticastLock(context: Context): Boolean {
        val current = multicastLock
        if (current?.isHeld == true) return true
        val wifi = context.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return false
        val lock = wifi.createMulticastLock("pure_live:dlna").apply { setReferenceCounted(false) }
        return try {
            lock.acquire()
            multicastLock = lock
            true
        } catch (_: SecurityException) {
            false
        }
    }

    private fun releaseMulticastLock() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }
}

/** Marks a method the handler does not know. */
internal object NotImplemented

/**
 * Strict decoding of legacy text (IPTV playlists in GBK; 3.x used the
 * charset_converter plugin). Malformed input is an error, not U+FFFD.
 */
internal object TextCodecChannel {
    private val ALLOWED = setOf("GBK", "GB18030")

    fun handle(call: MethodCall): Any? = when (call.method) {
        "decode" -> {
            val charset = (call.argument<String>("charset") ?: "GBK").uppercase()
            require(charset in ALLOWED) { "Charset not allowed" }
            Charset.forName(charset).newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(call.argument<ByteArray>("bytes")!!))
                .toString()
        }

        else -> NotImplemented
    }
}

/**
 * AES-256-GCM under a non-exportable Android Keystore key. The secret's name
 * is the associated data, so a sealed value cannot be moved to another name.
 * Layout: 12-byte IV, then ciphertext and tag.
 */
internal object SecretCipherChannel {
    private const val KEY_ALIAS = "pure_live.secrets.v1"
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128

    fun handle(call: MethodCall): Any? = when (call.method) {
        "seal" -> seal(call.argument<String>("ref")!!, call.argument<String>("plain")!!)
        "open" -> open(call.argument<String>("ref")!!, call.argument<ByteArray>("sealed")!!)
        else -> NotImplemented
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
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

    private fun seal(ref: String, plain: String): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(ref.toByteArray(Charsets.UTF_8))
        val body = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        return cipher.iv + body
    }

    private fun open(ref: String, sealed: ByteArray): String {
        require(sealed.size > IV_BYTES) { "Sealed value too short" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, sealed, 0, IV_BYTES))
        cipher.updateAAD(ref.toByteArray(Charsets.UTF_8))
        return String(cipher.doFinal(sealed, IV_BYTES, sealed.size - IV_BYTES), Charsets.UTF_8)
    }
}

/**
 * One HTTPS request through the platform stack (3.x NativeHttpChannel, made
 * general: method, headers and body come from Dart). Only [ALLOWED_HOSTS] are
 * reachable, so the channel cannot be used to reach arbitrary addresses.
 */
internal object NativeHttpChannel {
    /** Twitch GraphQL (3.x) and Kick's API (UPGRADES X-1, M4.34: Cloudflare refuses dart:io's TLS there). */
    private val ALLOWED_HOSTS = setOf("gql.twitch.tv", "kick.com")
    private const val MAX_RESPONSE_BYTES = 8 * 1024 * 1024
    private val DISALLOWED_HEADERS = setOf(
        "accept-encoding",
        "connection",
        "content-length",
        "host",
        "proxy-authorization",
        "proxy-connection",
    )

    fun handle(call: MethodCall): Any? = when (call.method) {
        "send" -> send(call)
        "allowedHosts" -> ALLOWED_HOSTS.toList()
        else -> NotImplemented
    }

    private fun send(call: MethodCall): Map<String, Any> {
        val urlValue = call.argument<String>("url") ?: error("Missing URL")
        val uri = URI(urlValue)
        require(uri.scheme.equals("https", ignoreCase = true) && uri.host.lowercase() in ALLOWED_HOSTS) {
            "Native HTTP host is not allowed"
        }
        val method = (call.argument<String>("method") ?: "GET").uppercase()
        require(method in setOf("GET", "POST", "HEAD")) { "Native HTTP method is not allowed" }
        val timeoutMillis = (call.argument<Number>("timeoutMillis")?.toInt() ?: 20_000).coerceIn(1_000, 60_000)
        val proxyHost = call.argument<String>("proxyHost")?.trim().orEmpty()
        val proxyPort = call.argument<Number>("proxyPort")?.toInt() ?: 0
        val proxy = if (proxyHost.isNotEmpty() && proxyPort in 1..65_535) {
            Proxy(Proxy.Type.HTTP, InetSocketAddress.createUnresolved(proxyHost, proxyPort))
        } else {
            Proxy.NO_PROXY
        }
        val connection = (uri.toURL().openConnection(proxy) as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = timeoutMillis
            readTimeout = timeoutMillis
            instanceFollowRedirects = false
            useCaches = false
            doInput = true
        }
        try {
            val headers = call.argument<Map<*, *>>("headers").orEmpty()
            for ((rawName, rawValue) in headers) {
                val name = rawName?.toString()?.trim().orEmpty()
                val value = rawValue?.toString().orEmpty()
                if (name.isEmpty() || name.lowercase() in DISALLOWED_HEADERS || value.contains('\r') ||
                    value.contains('\n')
                ) {
                    continue
                }
                connection.setRequestProperty(name, value)
            }
            val body = call.argument<ByteArray>("body")
            if (body != null && method == "POST") {
                connection.doOutput = true
                connection.setFixedLengthStreamingMode(body.size)
                connection.outputStream.use { it.write(body) }
            }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val bytes = stream?.use(::readBounded) ?: ByteArray(0)
            val responseHeaders = mutableMapOf<String, List<String>>()
            for ((name, values) in connection.headerFields) {
                if (name != null) responseHeaders[name.lowercase()] = values
            }
            return mapOf("status" to status, "headers" to responseHeaders, "body" to bytes)
        } finally {
            connection.disconnect()
        }
    }

    private fun readBounded(input: InputStream): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(16 * 1024)
        var total = 0
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            total += read
            require(total <= MAX_RESPONSE_BYTES) { "Native HTTP response exceeded 8 MiB" }
            output.write(buffer, 0, read)
        }
        return output.toByteArray()
    }
}
