import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pure_live_app/features/alerts/local_notifier.dart';

/// The system notification channels of the app (F-NEW-01).
enum AlertChannel {
  /// A followed streamer went live.
  live,

  /// An IPTV programme the user asked about starts soon (F-IPTV-09).
  programme,
}

/// One system notification: [payload] is the app location a tap opens.
@immutable
final class AlertNotice {
  /// Creates a notice.
  const new({required this.id, required this.channel, required this.title, required this.body, required this.payload});

  /// Notification id; a second notice with the same id replaces the first.
  final int id;

  /// Which channel it goes to.
  final AlertChannel channel;

  /// First line.
  final String title;

  /// Second line.
  final String body;

  /// App location opened by a tap (see `openAlertPayload`).
  final String payload;

  @override
  bool operator ==(Object other) =>
      other is AlertNotice &&
      other.id == id &&
      other.channel == channel &&
      other.title == title &&
      other.body == body &&
      other.payload == payload;

  @override
  int get hashCode => Object.hash(id, channel, title, body, payload);

  @override
  String toString() => 'AlertNotice($id, $title, $body, $payload)';
}

/// A stable positive notification id for [key] (FNV-1a, 31 bits), so the
/// same room or programme replaces its earlier notification.
int alertIdOf(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  // 0 and 1 are left for the combined notices.
  return (hash & 0x7fffffff) | 2;
}

/// Sends system notifications and reports taps. The app talks only to this
/// interface; tests use a fake (ADR draft-live-alerts).
abstract interface class AlertNotifier {
  /// Whether this platform shows notifications (Android and Windows); other
  /// platforms skip them silently.
  bool get supported;

  /// Payloads of notifications tapped while the app runs.
  Stream<String> get taps;

  /// Starts the platform side once (later calls return at once) and returns
  /// the payload of the notification that launched the app, if any.
  Future<String?> start();

  /// Whether the app may show notifications now.
  Future<bool> permitted();

  /// Asks for the notification permission where the system has one (Android
  /// 13+); returns whether notifications are allowed afterwards.
  Future<bool> requestPermission();

  /// Shows [notice]; failures are logged by the caller.
  Future<void> show(AlertNotice notice);
}

/// Platforms without notifications: nothing is shown and nothing is asked.
final class NoAlertNotifier implements AlertNotifier {
  /// Creates the notifier.
  const new();

  @override
  bool get supported => false;

  @override
  Stream<String> get taps => const Stream.empty();

  @override
  Future<String?> start() async => null;

  @override
  Future<bool> permitted() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> show(AlertNotice notice) async {}
}

/// The notifier of this platform: the system notifications on Android and
/// Windows (flutter_local_notifications), nothing elsewhere. Decided by the
/// real operating system, so widget tests on a desktop host never reach the
/// plugin.
final alertNotifierProvider = Provider<AlertNotifier>((ref) {
  if (kIsWeb || !(Platform.isAndroid || Platform.isWindows)) return const NoAlertNotifier();
  final notifier = LocalAlertNotifier();
  ref.onDispose(notifier.dispose);
  return notifier;
});
