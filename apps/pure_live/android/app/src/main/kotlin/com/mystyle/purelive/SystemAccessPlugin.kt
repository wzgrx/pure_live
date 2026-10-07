package com.mystyle.purelive

import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * `pure_live/system_access` (3.x used permission_handler for both):
 * - `canInstallPackages`: whether this app may install APKs (the update
 *   download, API 26+ "install unknown apps");
 * - `openInstallSettings`: the system page that grants it;
 * - `localNetworkGranted`: whether sockets to the local network are allowed
 *   (Android 17 / API 37 `ACCESS_LOCAL_NETWORK`; true before API 37);
 * - `requestLocalNetwork`: asks for it and answers whether it is granted;
 * - `sensorLandscape`: holds the activity sideways turning over with the
 *   phone even while auto-rotate is off (issue #36; Flutter's two landscapes
 *   are USER_LANDSCAPE, which stays put then). Flutter's next preferred
 *   orientations replace it.
 * - `autoRotate`: whether the system's auto-rotate is on; leaving a
 *   fullscreen with it off turns the phone upright before letting go (O05.3).
 *   Only read: writing the setting would need WRITE_SETTINGS.
 */
internal class SystemAccessPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener {
    companion object {
        private const val CHANNEL = "pure_live/system_access"
        private const val LOCAL_NETWORK = "android.permission.ACCESS_LOCAL_NETWORK"
        private const val LOCAL_NETWORK_SDK = 37
        // Every listener sees every permission result: request codes must be
        // unique across the app's plugins (PermissionsPlugin has 20261001,
        // 20261002; RecorderPlugin 20260907).
        private const val LOCAL_NETWORK_REQUEST = 20261003
    }

    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var activity: ActivityPluginBinding? = null
    private var pending: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activity?.removeRequestPermissionsResultListener(this)
        activity = null
        pending?.success(localNetworkGranted())
        pending = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canInstallPackages" -> result.success(canInstallPackages())
            "openInstallSettings" -> result.success(openInstallSettings())
            "localNetworkGranted" -> result.success(localNetworkGranted())
            "requestLocalNetwork" -> requestLocalNetwork(result)
            "sensorLandscape" -> result.success(sensorLandscape())
            "autoRotate" -> result.success(autoRotate())
            else -> result.notImplemented()
        }
    }

    private fun canInstallPackages(): Boolean {
        val context = context ?: return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.packageManager.canRequestPackageInstalls()
    }

    private fun openInstallSettings(): Boolean {
        val context = context ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            (activity?.activity ?: context).startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun localNetworkGranted(): Boolean {
        val context = context ?: return true
        if (Build.VERSION.SDK_INT < LOCAL_NETWORK_SDK) return true
        return context.checkSelfPermission(LOCAL_NETWORK) == PackageManager.PERMISSION_GRANTED
    }

    private fun sensorLandscape(): Boolean {
        val host = activity?.activity ?: return false
        host.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        return true
    }

    private fun autoRotate(): Boolean {
        val context = context ?: return false
        return Settings.System.getInt(context.contentResolver, Settings.System.ACCELEROMETER_ROTATION, 0) != 0
    }

    private fun requestLocalNetwork(result: MethodChannel.Result) {
        if (localNetworkGranted()) {
            result.success(true)
            return
        }
        val host = activity?.activity
        if (host == null || pending != null) {
            result.success(false)
            return
        }
        pending = result
        host.requestPermissions(arrayOf(LOCAL_NETWORK), LOCAL_NETWORK_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != LOCAL_NETWORK_REQUEST) return false
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pending?.success(granted)
        pending = null
        return true
    }
}
