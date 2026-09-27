import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/alerts/alert_notifier.dart';
import 'package:pure_live_app/features/alerts/programme_reminders.dart';
import 'package:pure_live_app/features/diagnostics/diagnostics_page.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';

/// Opens the location a notification carries (F-NEW-01): a room opens above
/// the current page; the combined live alert switches to the follows page's
/// live tab. Anything else is ignored.
void openAlertPayload(GoRouter router, String payload, {DateTime Function() now = DateTime.now}) {
  final uri = Uri.tryParse(payload);
  // Only app locations: the app writes these payloads itself.
  if (uri == null || uri.hasScheme || uri.hasAuthority) return;
  if (uri.pathSegments.length == 3 && uri.pathSegments.first == 'room') {
    unawaited(router.push(uri.path));
    return;
  }
  if (uri.path == '/follows') {
    // A fresh `at` makes the page apply the tab even when it already shows
    // the same location.
    router.go(
      Uri(
        path: '/follows',
        queryParameters: {...uri.queryParameters, 'at': '${now().millisecondsSinceEpoch}'},
      ).toString(),
    );
  }
}

/// Notifications after the first frame (ADR draft-live-alerts): taps open
/// their location; while live alerts are on the plugin runs, the follow
/// refresh (and its timer) runs even if the follows page never opens, and a
/// notification that launched the app opens its location; programme
/// reminders are restored. Platforms without notifications do nothing.
final alertStartupProvider = Provider<void>((ref) {
  final notifier = ref.read(alertNotifierProvider);
  if (!notifier.supported) return;
  final router = ref.read(routerProvider);
  final settings = ref.read(storeProvider).settings;
  final log = ref.read(appLogProvider);
  final taps = notifier.taps.listen((payload) => openAlertPayload(router, payload));

  Future<void>? started;
  Future<void> start() => started ??= () async {
    try {
      final launch = await notifier.start();
      if (launch != null) openAlertPayload(router, launch);
    } on Object catch (error) {
      log.warning('alerts', 'notifications did not start', error);
    }
  }();

  Future<void> liveAlertsChanged() async {
    if (!settings.get(Settings.liveAlerts)) return;
    await start();
    try {
      // Notifications turned off in the system settings: the switch follows.
      if (!await notifier.permitted()) {
        log.info('alerts', 'notifications are not allowed; live alerts turned off');
        await settings.set(Settings.liveAlerts, false);
        return;
      }
    } on Object catch (error) {
      log.warning('alerts', 'permission check failed', error);
    }
    if (ref.mounted) ref.read(followRefreshProvider);
  }

  unawaited(liveAlertsChanged());
  unawaited(
    ref.read(programmeRemindersProvider.notifier).restore().then((pending) {
      if (pending > 0) unawaited(start());
    }, onError: (Object error) => log.warning('alerts', 'restoring programme reminders failed', error)),
  );
  final changes = settings.changes
      .where((id) => id == Settings.liveAlerts.id)
      .listen((_) => unawaited(liveAlertsChanged()));
  ref.onDispose(() {
    unawaited(taps.cancel());
    unawaited(changes.cancel());
  });
});
