package com.mystyle.purelive

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * `pure_live/permissions` (3.x used permission_handler's `notification` and
 * `ignoreBatteryOptimizations`; M12.5 → F.0a): what background playback,
 * the sleep timer and recording ask for.
 *
 * - `notificationState`: `granted`, `askable` (the system dialog can ask) or
 *   `blocked` (refused for good, switched off in the settings, or Android
 *   12 and older where nothing can be asked; docs/T13/T13a/T13a.1 c13).
 *   Refused for good is told from the rationale flag after a first request.
 * - `requestNotifications`: the system dialog; whether they are allowed.
 * - `batteryUnrestricted`, `requestBatteryUnrestricted`: the battery
 *   exemption and the system's dialog for it.
 * - `openNotificationSettings`: this app's notification page of the
 *   system settings (the app's details where there is none).
 */
internal class PermissionsPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener {
    companion object {
        private const val CHANNEL = "pure_live/permissions"
        private const val NOTIFICATION_REQUEST = 20261001
        private const val BATTERY_REQUEST = 20261002
        private const val PREFERENCES = "pure_live_permissions"
        private const val NOTIFICATIONS_ASKED = "notificationsAsked"
    }

    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var activity: ActivityPluginBinding? = null
    private var notificationResult: MethodChannel.Result? = null
    private var batteryResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "notificationState" -> result.success(notificationState())
            "requestNotifications" -> requestNotifications(result)
            "batteryUnrestricted" -> result.success(batteryUnrestricted())
            "requestBatteryUnrestricted" -> requestBatteryUnrestricted(result)
            "openNotificationSettings" -> result.success(openNotificationSettings())
            else -> result.notImplemented()
        }
    }

    private fun notificationsAllowed(): Boolean {
        val context = context ?: return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return true
        return manager.areNotificationsEnabled()
    }

    private fun asked(): Boolean =
        context?.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)?.getBoolean(NOTIFICATIONS_ASKED, false) ?: false

    private fun notificationState(): String {
        val context = context ?: return "granted"
        if (notificationsAllowed()) return "granted"
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return "blocked"
        // Granted but switched off in the system settings: no dialog helps.
        if (context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            return "blocked"
        }
        val activity = activity?.activity
        if (activity != null && activity.shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)) {
            return "askable"
        }
        // Before any request there is no rationale either.
        return if (asked()) "blocked" else "askable"
    }

    private fun requestNotifications(result: MethodChannel.Result) {
        if (notificationsAllowed()) return result.success(true)
        val activity: Activity = activity?.activity ?: return result.success(false)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            return result.success(false)
        }
        if (notificationResult != null) return result.success(false)
        notificationResult = result
        activity.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit()
            .putBoolean(NOTIFICATIONS_ASKED, true).apply()
        try {
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
        } catch (_: Exception) {
            notificationResult = null
            result.success(false)
        }
    }

    private fun batteryUnrestricted(): Boolean {
        val context = context ?: return true
        val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return true
        return power.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun requestBatteryUnrestricted(result: MethodChannel.Result) {
        if (batteryUnrestricted()) return result.success(true)
        val activity: Activity = activity?.activity ?: return result.success(false)
        if (batteryResult != null) return result.success(false)
        batteryResult = result
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                .setData(Uri.parse("package:${activity.packageName}"))
            activity.startActivityForResult(intent, BATTERY_REQUEST)
        } catch (_: Exception) {
            // Some vendor builds remove the dialog.
            batteryResult = null
            result.success(false)
        }
    }

    private fun openNotificationSettings(): Boolean {
        val context = activity?.activity ?: context ?: return false
        val details = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:${context.packageName}"))
        val notifications = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        return start(context, notifications) || start(context, details)
    }

    private fun start(context: Context, intent: Intent): Boolean = try {
        if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        true
    } catch (_: Exception) {
        false
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != BATTERY_REQUEST) return false
        val result = batteryResult ?: return true
        batteryResult = null
        result.success(batteryUnrestricted())
        return true
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != NOTIFICATION_REQUEST) return false
        val result = notificationResult ?: return true
        notificationResult = null
        result.success(notificationsAllowed())
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activity?.removeActivityResultListener(this)
        activity?.removeRequestPermissionsResultListener(this)
        activity = null
        notificationResult?.success(notificationsAllowed())
        notificationResult = null
        batteryResult?.success(batteryUnrestricted())
        batteryResult = null
    }
}
