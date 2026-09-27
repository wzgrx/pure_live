import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/alerts/live_alerts.dart';
import 'package:pure_live_app/features/diagnostics/diagnostics_page.dart';

/// Followed rooms as stored, newest state first; the page never waits for the
/// network to show them.
final followsProvider = StreamProvider<List<FollowedRoom>>((ref) => ref.watch(storeProvider).follows.watchAll());

/// Result of one refresh of the follows' live states.
final class FollowRefreshResult {
  const new({required this.checked, required this.failedPlatforms});

  /// Rooms whose state was fetched.
  final int checked;

  /// Platforms that failed, for the banner (principles §4.1: 平台异常时顶部显示横幅).
  final Set<String> failedPlatforms;
}

/// Refreshes the live state of every followed room and writes the results to
/// the store; the list updates through [followsProvider].
class FollowRefreshNotifier extends AsyncNotifier<FollowRefreshResult?> {
  Timer? _timer;

  @override
  Future<FollowRefreshResult?> build() {
    final settings = ref.read(storeProvider).settings;
    // Refresh when the app comes back (default on) and on a timer (default
    // off), as the 3.x settings did; the interval is in minutes. Live alerts
    // need the timer too, so they run it while on (F-NEW-01); it keeps
    // running in the background as long as the process lives.
    final lifecycle = AppLifecycleListener(
      onResume: () {
        if (settings.get(Settings.refreshFollowsOnResume)) unawaited(refresh());
      },
    );
    void schedule() {
      _timer?.cancel();
      final periodic = settings.get(Settings.autoRefreshFollows) || settings.get(Settings.liveAlerts);
      _timer = periodic
          ? Timer.periodic(Duration(minutes: settings.get(Settings.autoRefreshInterval)), (_) => unawaited(refresh()))
          : null;
    }

    schedule();
    final scheduleSettings = {Settings.autoRefreshFollows.id, Settings.autoRefreshInterval.id, Settings.liveAlerts.id};
    final changes = settings.changes.where(scheduleSettings.contains).listen((_) => schedule());
    ref.onDispose(() {
      lifecycle.dispose();
      _timer?.cancel();
      unawaited(changes.cancel());
    });
    return refresh();
  }

  /// Fetches every followed room's detail, stores the results and then
  /// announces rooms that went live (F-NEW-01).
  Future<FollowRefreshResult> refresh() async {
    final store = ref.read(storeProvider);
    final sites = ref.read(sitesProvider);
    final alerts = ref.read(liveAlertServiceProvider);
    final log = ref.read(appLogProvider);
    // The states stored before this refresh: live alerts compare against them.
    final follows = await store.follows.all();
    final queue = [...follows.map((follow) => follow.ref).where((room) => sites.containsKey(room.platform))];
    final details = <RoomDetail>[];
    final failed = <String>{};

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final room = queue.removeLast();
        try {
          details.add(await sites[room.platform]!.rooms.detail(room));
        } on NotFound {
          // A removed room keeps its last known card; the row says so later.
        } on Object {
          failed.add(room.platform);
        }
      }
    }

    // Requests in flight at once, so a long follow list does not trip rate limits.
    final concurrency = store.settings.get(Settings.maxConcurrentRefresh);
    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    if (details.isNotEmpty) await store.rooms.update([for (final detail in details) RoomSnapshot.fromDetail(detail)]);
    final result = FollowRefreshResult(checked: details.length, failedPlatforms: failed);
    if (ref.mounted) state = AsyncData(result);
    try {
      await alerts.afterRefresh(follows, [for (final detail in details) LiveObservation.fromDetail(detail)]);
    } on Object catch (error, stack) {
      log.error('alerts', 'live alerts failed', error, stack);
    }
    return result;
  }
}

/// The follows' refresh state.
final followRefreshProvider = AsyncNotifierProvider<FollowRefreshNotifier, FollowRefreshResult?>(
  FollowRefreshNotifier.new,
);
