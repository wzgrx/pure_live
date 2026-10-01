import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where the notification permission stands.
enum NotificationPermission {
  /// Notifications show.
  granted,

  /// Off, and the system dialog can still ask (Android 13+).
  askable,

  /// Off for good: refused twice, or switched off in the system settings
  /// (below Android 13 there is nothing to ask); only the settings page
  /// helps (docs/ui/compare/U.14 c13).
  blocked,
}

/// Android's notification permission and battery-optimisation exemption
/// (`pure_live/permissions`, `PermissionsPlugin.kt`; 3.x used
/// permission_handler, M12.5 → F.0a). Elsewhere, and when the native side
/// fails, everything reads as allowed so nothing is blocked, and no
/// settings page opens.
class SystemPermissions {
  /// Creates the permissions over [channel]; `android` defaults to the
  /// platform.
  const new({this.channel = const MethodChannel('pure_live/permissions'), this._android});

  /// The native channel.
  final MethodChannel channel;

  final bool? _android;

  /// Whether there is anything to ask for (Android).
  bool get applies => _android ?? (!kIsWeb && Platform.isAndroid);

  /// The notification permission now.
  Future<NotificationPermission> notifications() async =>
      switch (await _call<String>('notificationState', fallback: 'granted')) {
        'askable' => NotificationPermission.askable,
        'blocked' => NotificationPermission.blocked,
        _ => NotificationPermission.granted,
      };

  /// Shows the system's notification dialog; whether notifications are
  /// allowed afterwards.
  Future<bool> requestNotifications() async => await _call<bool>('requestNotifications', fallback: true) ?? true;

  /// Whether the app is exempt from battery optimisation.
  Future<bool> batteryUnrestricted() async => await _call<bool>('batteryUnrestricted', fallback: true) ?? true;

  /// Shows the system's exemption dialog; whether the app is exempt
  /// afterwards.
  Future<bool> requestBatteryUnrestricted() async =>
      await _call<bool>('requestBatteryUnrestricted', fallback: true) ?? true;

  /// Opens the app's notification settings; whether a page opened.
  Future<bool> openNotificationSettings() async =>
      await _call<bool>('openNotificationSettings', fallback: false) ?? false;

  Future<T?> _call<T>(String method, {required T fallback}) async {
    if (!applies) return fallback;
    try {
      return await channel.invokeMethod<T>(method) ?? fallback;
    } on PlatformException catch (error) {
      log('$method failed: ${error.message}', name: 'SystemPermissions');
      return fallback;
    } on MissingPluginException {
      return fallback;
    }
  }
}
