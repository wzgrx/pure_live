package com.mystyle.purelive

import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * `pure_live/share_intake` (3.x used the share_handler plugin with a local
 * AGP patch; M12.5 → F.0a): what other apps hand to Pure Live, and what the
 * launcher shortcuts and the recording notifications open.
 *
 * - [ACTION_OPEN] (shortcuts, notifications; docs/ui/compare/U.14 c3, c5,
 *   c15): `route` opens a page (only [OPENABLE_ROUTES]), `platform` +
 *   `roomId` a room; delivered as
 *   `shared {route}` or `shared {room: {platform, roomId, title, nick}}`.
 *   With the recording centre, [EXTRA_TASK] (a task id, the "录制已停止"
 *   reminder, F02 c2) comes along as `shared {route, task}`.
 * - `setRecentRooms [{platform, roomId, title, nick}]`: the launcher icon's
 *   long press shows "搜索直播", "录制中心" and these rooms (dynamic
 *   shortcuts, so the debug build's own id works too).
 * - Shared text and files (`SEND`, `SEND_MULTIPLE`) and files opened with
 *   the app (`VIEW` of a `content:` or `file:` URI). Files are copied into
 *   the cache (`share_intake/<random>/<name>`) while the grant lasts, on a
 *   worker thread; Dart deletes each folder after the import, and leftovers
 *   are removed when the engine starts.
 * - The intent that started the activity is read once (not again when the
 *   activity is recreated or opened from Recents); later ones arrive through
 *   `onNewIntent` (the activity is `singleTask`).
 * - `listen` (Dart): from now on deliver shares as `shared {text, files:
 *   [{path, name}]}`; answers the ones that came before.
 * - `clipboardStamp`: when the clipboard last changed (API 26+), from its
 *   description, which Android does not report as a clipboard access; -1
 *   when it is empty, null when unknown.
 */
internal class ShareIntakePlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.NewIntentListener {
    companion object {
        /** Opens a page (`route`) or a room (`platform`, `roomId`, `title`, `nick`). */
        internal const val ACTION_OPEN = "com.mystyle.purelive.OPEN"
        internal const val EXTRA_ROUTE = "route"

        /** The recording task the recording centre points at. */
        internal const val EXTRA_TASK = "task"
        internal const val ROUTE_SEARCH = "/search"
        internal const val ROUTE_RECORDINGS = "/record_mannager"

        /**
         * The pages [ACTION_OPEN] may open. The activity is exported (it is
         * the launcher's), so any app can send the action; other routes are
         * dropped here and again in Dart (`ShareIntake.openableRoutes`).
         */
        private val OPENABLE_ROUTES = setOf(ROUTE_SEARCH, ROUTE_RECORDINGS)

        /** The intent that opens [route] in the app. */
        internal fun openRoute(context: Context, route: String): Intent =
            Intent(context, MainActivity::class.java)
                .setAction(ACTION_OPEN)
                .putExtra(EXTRA_ROUTE, route)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        private const val CHANNEL = "pure_live/share_intake"
        private const val HANDLED = "com.mystyle.purelive.share_handled"
        private const val STAGING = "share_intake"
        private const val MAX_FILES = 20
        private const val MAX_FILE_BYTES = 256L * 1024 * 1024
        private const val MAX_TEXT = 64 * 1024
        private const val MAX_NAME = 120
        private const val MAX_TASK_ID = 200
    }

    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var activity: ActivityPluginBinding? = null
    private val handler = Handler(Looper.getMainLooper())
    private var worker: ExecutorService? = null
    private val pending = mutableListOf<Map<String, Any?>>()
    private var listening = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
        val staging = File(binding.applicationContext.cacheDir, STAGING)
        // Copies of an earlier run; this worker copies new shares after it.
        worker = Executors.newSingleThreadExecutor().also { it.execute { staging.deleteRecursively() } }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
        listening = false
        pending.clear()
        worker?.shutdown()
        worker = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listen" -> {
                listening = true
                result.success(pending.toList())
                pending.clear()
            }

            "clipboardStamp" -> result.success(clipboardStamp())
            "setRecentRooms" -> {
                setShortcuts(call.arguments as? List<*> ?: emptyList<Any>())
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /** Search, the recording centre and up to two recent rooms (U.14 c15). */
    private fun setShortcuts(rooms: List<*>) {
        val context = context ?: return
        val manager = context.getSystemService(ShortcutManager::class.java) ?: return
        val shortcuts = mutableListOf(
            ShortcutInfo.Builder(context, "search")
                .setShortLabel(context.getString(R.string.shortcut_search))
                .setIcon(Icon.createWithResource(context, R.drawable.ic_shortcut_search))
                .setIntent(openRoute(context, ROUTE_SEARCH))
                .setRank(0)
                .build(),
            ShortcutInfo.Builder(context, "recordings")
                .setShortLabel(context.getString(R.string.shortcut_recordings))
                .setIcon(Icon.createWithResource(context, R.drawable.ic_shortcut_record))
                .setIntent(openRoute(context, ROUTE_RECORDINGS))
                .setRank(1)
                .build(),
        )
        for ((index, value) in rooms.take(2).withIndex()) {
            val room = value as? Map<*, *> ?: continue
            val platform = room["platform"] as? String ?: continue
            val roomId = room["roomId"] as? String ?: continue
            val nick = (room["nick"] as? String).orEmpty().trim()
            val title = (room["title"] as? String).orEmpty().trim()
            val label = nick.ifEmpty { title.ifEmpty { roomId } }
            val intent = Intent(context, MainActivity::class.java)
                .setAction(ACTION_OPEN)
                .putExtra("platform", platform)
                .putExtra("roomId", roomId)
                .putExtra("title", title)
                .putExtra("nick", nick)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            shortcuts += ShortcutInfo.Builder(context, "room_$index")
                .setShortLabel(label.take(24))
                .setLongLabel(if (title.isEmpty()) label else "$label · $title".take(48))
                .setIcon(Icon.createWithResource(context, R.drawable.ic_shortcut_room))
                .setIntent(intent)
                .setRank(2 + index)
                .build()
        }
        try {
            manager.dynamicShortcuts = shortcuts.take(manager.maxShortcutCountPerActivity.coerceAtLeast(2))
        } catch (_: Exception) {
            // Rate-limited or refused by the launcher.
        }
    }

    private fun clipboardStamp(): Long? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val clipboard = context?.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return null
        return try {
            if (!clipboard.hasPrimaryClip()) -1L else clipboard.primaryClipDescription?.timestamp
        } catch (_: Exception) {
            null
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addOnNewIntentListener(this)
        val intent = binding.activity.intent ?: return
        // Recents replays the intent that once started the task.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        receive(intent)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding
        binding.addOnNewIntentListener(this)
    }

    override fun onDetachedFromActivity() {
        activity?.removeOnNewIntentListener(this)
        activity = null
    }

    override fun onNewIntent(intent: Intent): Boolean {
        receive(intent)
        return false
    }

    private fun receive(intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE &&
            action != Intent.ACTION_VIEW && action != ACTION_OPEN
        ) {
            return
        }
        // The same intent object comes back when the activity is attached
        // again (the engine outlives it).
        if (intent.getBooleanExtra(HANDLED, false)) return
        intent.putExtra(HANDLED, true)
        if (action == ACTION_OPEN) {
            val route = intent.getStringExtra(EXTRA_ROUTE)
            val platform = intent.getStringExtra("platform")
            val roomId = intent.getStringExtra("roomId")
            when {
                route != null -> if (route in OPENABLE_ROUTES) deliver(openPage(route, intent))
                platform != null && roomId != null -> deliver(
                    mapOf(
                        "room" to mapOf(
                            "platform" to platform,
                            "roomId" to roomId,
                            "title" to intent.getStringExtra("title").orEmpty(),
                            "nick" to intent.getStringExtra("nick").orEmpty(),
                        ),
                    ),
                )
            }
            return
        }
        val text = sharedText(intent)
        val uris = sharedUris(intent).take(MAX_FILES)
        if (text == null && uris.isEmpty()) return
        val context = context ?: return
        val worker = worker ?: return
        worker.execute {
            val files = uris.mapNotNull { stage(context, it) }
            val payload = mapOf("text" to text, "files" to files)
            handler.post { deliver(payload) }
        }
    }

    /**
     * `{route}`, with `task` for the recording centre (any app may send the
     * action, so it is only an id the page looks for).
     */
    private fun openPage(route: String, intent: Intent): Map<String, Any?> {
        val task = intent.getStringExtra(EXTRA_TASK)?.trim()?.takeIf { it.isNotEmpty() && it.length <= MAX_TASK_ID }
        if (route != ROUTE_RECORDINGS || task == null) return mapOf("route" to route)
        return mapOf("route" to route, "task" to task)
    }

    private fun deliver(payload: Map<String, Any?>) {
        val channel = channel ?: return
        if (listening) channel.invokeMethod("shared", payload) else pending.add(payload)
    }

    private fun sharedText(intent: Intent): String? {
        val text = when (intent.action) {
            Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE ->
                intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                    ?: intent.getCharSequenceArrayListExtra(Intent.EXTRA_TEXT)?.joinToString("\n")
                    ?: intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString()

            // A deep link (purelive:, mystyle:) is read as text.
            Intent.ACTION_VIEW -> intent.data?.takeUnless { isFileUri(it) }?.toString()
            else -> null
        }
        return text?.take(MAX_TEXT)?.takeIf { it.isNotBlank() }
    }

    @Suppress("DEPRECATION")
    private fun sharedUris(intent: Intent): List<Uri> = when (intent.action) {
        Intent.ACTION_SEND -> listOfNotNull(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            },
        )

        Intent.ACTION_SEND_MULTIPLE -> (
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
            }
            ).orEmpty().filterNotNull()

        Intent.ACTION_VIEW -> listOfNotNull(intent.data?.takeIf(::isFileUri))
        else -> emptyList()
    }

    private fun isFileUri(uri: Uri): Boolean =
        uri.scheme.equals("content", ignoreCase = true) || uri.scheme.equals("file", ignoreCase = true)

    /** Copies [uri] into the cache; null when it cannot be read. */
    private fun stage(context: Context, uri: Uri): Map<String, String>? {
        val directory = File(File(context.cacheDir, STAGING), UUID.randomUUID().toString())
        var staged = false
        try {
            val input = open(context, uri) ?: return null
            input.use { source ->
                val name = safeName(displayName(context, uri), context.contentResolver.getType(uri))
                if (!directory.mkdirs()) return null
                val target = File(directory, name)
                target.outputStream().use { sink -> copyLimited(source, sink) }
                staged = true
                return mapOf("path" to target.absolutePath, "name" to name)
            }
        } catch (_: Exception) {
            return null
        } finally {
            if (!staged) directory.deleteRecursively()
        }
    }

    private fun open(context: Context, uri: Uri): InputStream? {
        if (!uri.scheme.equals("file", ignoreCase = true)) return context.contentResolver.openInputStream(uri)
        val file = File(uri.path ?: return null).canonicalFile
        // Another app must not get the app's own files imported.
        val own = File(context.applicationInfo.dataDir).canonicalPath
        if (file.path.startsWith(own) || !file.isFile) return null
        return file.inputStream()
    }

    private fun copyLimited(source: InputStream, sink: java.io.OutputStream) {
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            val read = source.read(buffer)
            if (read < 0) return
            total += read
            if (total > MAX_FILE_BYTES) throw java.io.IOException("Shared file too large")
            sink.write(buffer, 0, read)
        }
    }

    private fun displayName(context: Context, uri: Uri): String? {
        if (uri.scheme.equals("content", ignoreCase = true)) {
            try {
                context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) {
                        val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index >= 0) it.getString(index)?.let { name -> return name }
                    }
                }
            } catch (_: Exception) {
                // Some providers refuse queries; the path still names it.
            }
        }
        return uri.lastPathSegment
    }

    /** A file name without folders or control characters, with an extension from [mimeType] when it has none. */
    private fun safeName(name: String?, mimeType: String?): String {
        val leaf = name.orEmpty().substringAfterLast('/').substringAfterLast('\\')
            .filter { it >= ' ' && it != '\u007f' && it != ':' }
            .trim().take(MAX_NAME)
        val base = leaf.takeUnless { it.isEmpty() || it == "." || it == ".." } ?: "shared_${System.currentTimeMillis()}"
        if (base.contains('.')) return base
        val extension = mimeType?.let { MimeTypeMap.getSingleton().getExtensionFromMimeType(it) }
        return if (extension.isNullOrEmpty()) base else "$base.$extension"
    }
}
