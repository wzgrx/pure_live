import 'dart:async';

import 'package:pure_live_app/features/alerts/alert_notifier.dart';

/// A notifier that records what the app shows and answers permission
/// requests with [grant], like the plugin: [start] runs once and hands back
/// the launching notification's payload.
final class FakeAlertNotifier implements AlertNotifier {
  new({this.grant = true, this.allowed = true, this.launchPayload, this.failShow = false});

  /// Answer to [requestPermission].
  bool grant;

  /// Answer to [permitted] before any request.
  bool allowed;

  /// Payload of the notification that "launched" the app.
  String? launchPayload;

  /// Makes [show] throw, like a plugin error.
  bool failShow;

  /// Notices shown, in order.
  final shown = <AlertNotice>[];

  /// Number of permission requests.
  int requests = 0;

  /// Number of [start] calls; each reports [launchPayload] like the plugin.
  int starts = 0;

  final _taps = StreamController<String>.broadcast();

  /// Simulates a tap on a notification carrying [payload].
  void tap(String payload) => _taps.add(payload);

  @override
  bool get supported => true;

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<String?> start() async {
    starts++;
    return launchPayload;
  }

  @override
  Future<bool> permitted() async => allowed;

  @override
  Future<bool> requestPermission() async {
    requests++;
    allowed = grant;
    return grant;
  }

  @override
  Future<void> show(AlertNotice notice) async {
    await start();
    if (failShow) throw StateError('notification failed');
    shown.add(notice);
  }
}
