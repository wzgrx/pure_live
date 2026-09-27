import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pure_live_app/features/alerts/alert_notifier.dart';

/// System notifications through flutter_local_notifications on Android and
/// Windows (ADR ADR 0028).
final class LocalAlertNotifier implements AlertNotifier {
  /// Creates the notifier; nothing touches the system before [start].
  new([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _taps = StreamController.broadcast();
  Future<String?>? _started;

  /// Windows identity of the preview build: its own AppUserModelID (the
  /// Android application id) and activator GUID, so toasts never mix with
  /// the 3.x app's `com.mystyle.purelive`.
  static const windowsAppUserModelId = 'com.mystyle.purelive.next';

  /// COM activator of the preview's toasts (generated for v4, 2026-09-28).
  static const windowsGuid = '80b8bd95-5a1b-451f-91bf-f0ca23a581a1';

  static const _liveChannel = AndroidNotificationChannel(
    'live_alerts',
    '开播提醒',
    description: '关注的主播开播时提醒',
    importance: Importance.high,
  );

  static const _programmeChannel = AndroidNotificationChannel(
    'programme_reminders',
    '节目提醒',
    description: '网络电视节目开始前 1 分钟提醒',
    importance: Importance.high,
  );

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  bool get supported => true;

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<String?> start() => _started ??= _start();

  Future<String?> _start() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        // Status bar icon: the launcher's monochrome layer.
        android: AndroidInitializationSettings('ic_launcher_monochrome'),
        windows: WindowsInitializationSettings(
          appName: '纯粹直播 预览',
          appUserModelId: windowsAppUserModelId,
          guid: windowsGuid,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty && !_taps.isClosed) _taps.add(payload);
      },
    );
    if (Platform.isAndroid) {
      final android = _android;
      await android?.createNotificationChannel(_liveChannel);
      await android?.createNotificationChannel(_programmeChannel);
    }
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch == null || !launch.didNotificationLaunchApp) return null;
    final payload = launch.notificationResponse?.payload;
    return payload == null || payload.isEmpty ? null : payload;
  }

  @override
  Future<bool> permitted() async {
    if (!Platform.isAndroid) return true;
    await start();
    return await _android?.areNotificationsEnabled() ?? true;
  }

  @override
  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return true;
    await start();
    // Below Android 13 there is nothing to ask; the answer is whether the
    // user turned the app's notifications off in the system settings.
    final granted = await _android?.requestNotificationsPermission();
    return granted ?? await permitted();
  }

  @override
  Future<void> show(AlertNotice notice) async {
    await start();
    final channel = switch (notice.channel) {
      AlertChannel.live => _liveChannel,
      AlertChannel.programme => _programmeChannel,
    };
    await _plugin.show(
      id: notice.id,
      title: notice.title,
      body: notice.body,
      payload: notice.payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.event,
        ),
        windows: const WindowsNotificationDetails(),
      ),
    );
  }

  /// Closes [taps].
  Future<void> dispose() => _taps.close();
}
