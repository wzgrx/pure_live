package com.mystyle.purelive

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent

/**
 * "开播提醒" (docs/O-Android系统集成/O01-通知和前台服务/O01.1-开播提醒; V01.1 L7):
 * Dart posts one notification per followed room that began a broadcast
 * (`pure_live/live_alerts` `post`, registered by [AppChannelsPlugin]) while
 * the app runs; nothing here schedules or checks anything.
 *
 * - Channel "开播提醒" (default importance: a sound, no pop-up), created on
 *   the first post with Dart's name and description.
 * - One notification per room (tag `live_alert:<platform>:<roomId>`): the
 *   room's next broadcast replaces it; several rooms are several
 *   notifications, which Android bundles from four on.
 * - A tap opens the room like the launcher's room shortcuts
 *   ([ShareIntakePlugin.ACTION_OPEN] with `platform`, `roomId`, `title`,
 *   `nick`), in the running task or a new activity on the cached engine.
 * - `since` (the broadcast's start, epoch ms) is the notification's time.
 *
 * Answers whether notifications are allowed (Android drops the post when
 * they are not: no permission on Android 13+, or switched off).
 */
internal object LiveAlerts {
    private const val CHANNEL_ID = "pure_live_live_alerts"
    private const val NOTIFICATION_ID = 20261008

    fun post(context: Context, arguments: Any?): Boolean {
        val map = arguments as? Map<*, *> ?: return false
        fun text(key: String, limit: Int) = (map[key] as? String)?.trim()?.take(limit).orEmpty()
        val platform = text("platform", 40)
        val roomId = text("roomId", 200)
        if (platform.isEmpty() || roomId.isEmpty()) return false
        return try {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    text("channel", 40).ifEmpty { "开播提醒" },
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply { description = text("channelDescription", 120) },
            )
            val key = "$platform:$roomId"
            val open = PendingIntent.getActivity(
                context,
                request(key),
                Intent(context, MainActivity::class.java)
                    .setAction(ShareIntakePlugin.ACTION_OPEN)
                    .putExtra("platform", platform)
                    .putExtra("roomId", roomId)
                    .putExtra("title", text("roomTitle", 200))
                    .putExtra("nick", text("nick", 120))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val body = text("text", 240)
            val builder = Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_playback)
                .setContentTitle(text("title", 120))
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setContentIntent(open)
                .setCategory(Notification.CATEGORY_SOCIAL)
                .setAutoCancel(true)
            val since = (map["since"] as? Number)?.toLong()
            if (since != null && since > 0) builder.setWhen(since).setShowWhen(true)
            manager.notify("live_alert:$key", NOTIFICATION_ID, builder.build())
            manager.areNotificationsEnabled()
        } catch (_: Exception) {
            false
        }
    }

    /**
     * The request code of [key]'s tap: one per room, since Android keeps one
     * pending intent per code and the extras do not tell them apart. Clear
     * of the recording reminders' codes (0x1000 + 28 bits) and the ongoing
     * notification's 0–4.
     */
    private fun request(key: String): Int = 0x20000000 + (key.hashCode() and 0x0FFFFFFF)
}
