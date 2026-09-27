import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/clock.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/alerts/live_alerts.dart';
import 'package:pure_live_app/features/diagnostics/diagnostics_page.dart';

/// Followed rooms as stored, newest state first; the page never waits for the
/// network to show them.
final followsProvider = StreamProvider<List<FollowedRoom>>((ref) => ref.watch(storeProvider).follows.watchAll());

/// Result of one refresh of the follows' live states.
final class FollowRefreshResult {
  const new({
    required this.checked,
    required this.failedPlatforms,
    this.failed = const {},
    this.missing = const {},
    this.skipped = const {},
    this.liveSince = const {},
    this.at,
  });

  /// Rooms whose state was fetched.
  final int checked;

  /// Platforms that failed, for the banner (principles §4.1: 平台异常时顶部显示横幅).
  final Set<String> failedPlatforms;

  /// Keys of rooms whose state could not be fetched: they show as unknown,
  /// never with the state of an earlier run (F-FAV-03, store.md §6.4.10).
  final Set<String> failed;

  /// Keys of rooms the platform says do not exist.
  final Set<String> missing;

  /// Keys of rooms skipped because this build has no adapter for their
  /// platform (F-FAV-08).
  final Set<String> skipped;

  /// When the current broadcast of a live room started, if the platform says
  /// (the 开播时间 order, F-FAV-01).
  final Map<String, DateTime> liveSince;

  /// When the results were stored. A room whose stored data changed later
  /// (opened, followed again) has fresher data than this refresh.
  final DateTime? at;
}

/// Refreshes the live state of every followed room and writes the results to
/// the store; the list updates through [followsProvider].
///
/// The first refresh starts with the provider (at launch); until it is done
/// the state has no value and the follows page says it is checking
/// (F-FAV-03). Results are written in one transaction and published once.
class FollowRefreshNotifier extends AsyncNotifier<FollowRefreshResult?> {
  /// How long the app must have been away before a resume refreshes (F-APP-03).
  static const staleAfter = Duration(seconds: 15);

  /// Delay after a resume, so the retained list paints first (F-APP-03).
  static const resumeDelay = Duration(milliseconds: 450);

  Timer? _timer;
  Timer? _resumeTimer;
  Future<FollowRefreshResult>? _running;
  DateTime? _lastDone;

  @override
  Future<FollowRefreshResult?> build() {
    final settings = ref.read(storeProvider).settings;
    // Refresh when the app comes back (default on) and on a timer (default
    // off), as the 3.x settings did; the interval is in minutes. Live alerts
    // need the timer too, so they run it while on (F-NEW-01); it keeps
    // running in the background as long as the process lives.
    final lifecycle = AppLifecycleListener(onResume: resumed, onHide: () => _resumeTimer?.cancel());
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
      _resumeTimer?.cancel();
      unawaited(changes.cancel());
    });
    return _start();
  }

  /// The app came back to the foreground: when "回到应用时刷新关注" is on and
  /// the last refresh is at least [staleAfter] old, refresh after
  /// [resumeDelay] (3.x favorite_controller.dart:185-210, F-APP-03).
  void resumed() {
    _resumeTimer?.cancel();
    if (!ref.read(storeProvider).settings.get(Settings.refreshFollowsOnResume)) return;
    final last = _lastDone;
    final now = ref.read(clockProvider)();
    if (last != null && now.difference(last) < staleAfter) return;
    _resumeTimer = Timer(resumeDelay, () => unawaited(refresh()));
  }

  /// Fetches every followed room's detail, stores the results and then
  /// announces rooms that went live (F-NEW-01). A refresh asked for while one
  /// runs joins it instead of starting a second pass.
  Future<FollowRefreshResult> refresh() {
    final running = _running;
    if (running != null) return running;
    // Keep the last result while loading, so the page shows a spinner but
    // no card moves until the new result is published (F-FAV-03).
    final previous = state.value;
    final log = ref.read(appLogProvider);
    if (ref.mounted && state.hasValue) state = const AsyncLoading<FollowRefreshResult?>();
    return _start().catchError((Object error, StackTrace stack) {
      // A store failure: the spinner stops and the last result stays (the
      // error keeps the previous value); timers and pull-to-refresh get the
      // last result instead of an unhandled error.
      log.error('follows', 'refresh failed', error, stack);
      if (ref.mounted) state = AsyncError<FollowRefreshResult?>(error, stack);
      return previous ?? const FollowRefreshResult(checked: 0, failedPlatforms: {});
    });
  }

  Future<FollowRefreshResult> _start() {
    final pass = _refresh();
    _running = pass;
    return pass.whenComplete(() {
      if (identical(_running, pass)) _running = null;
    });
  }

  Future<FollowRefreshResult> _refresh() async {
    _resumeTimer?.cancel();
    final store = ref.read(storeProvider);
    final sites = ref.read(sitesProvider);
    final alerts = ref.read(liveAlertServiceProvider);
    final log = ref.read(appLogProvider);
    final clock = ref.read(clockProvider);
    // The states stored before this refresh: live alerts compare against them.
    final follows = await store.follows.all();
    // F-FAV-08: platforms without an adapter are skipped and marked.
    final skipped = {
      for (final follow in follows)
        if (!sites.containsKey(follow.ref.platform)) follow.ref.key,
    };
    final queue = [...follows.map((follow) => follow.ref).where((room) => sites.containsKey(room.platform))];
    final details = <RoomDetail>[];
    final failed = <String>{};
    final failedRooms = <String>{};
    final missing = <String>{};

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final room = queue.removeLast();
        try {
          details.add(await sites.of(room.platform).rooms.detail(room));
        } on NotFound {
          // A removed room keeps its last known card and says it is gone.
          missing.add(room.key);
        } on Object {
          // Network, risk control, parsing: the state is unknown, never the
          // cached one (spec/regressions.md, detail errors are typed).
          failed.add(room.platform);
          failedRooms.add(room.key);
        }
      }
    }

    // Requests in flight at once, so a long follow list does not trip rate limits.
    final concurrency = store.settings.get(Settings.maxConcurrentRefresh);
    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    // One transaction: the list changes once (F-FAV-03).
    if (details.isNotEmpty) await store.rooms.update([for (final detail in details) RoomSnapshot.fromDetail(detail)]);
    final done = clock();
    _lastDone = done;
    final result = FollowRefreshResult(
      checked: details.length,
      failedPlatforms: failed,
      failed: failedRooms,
      missing: missing,
      skipped: skipped,
      liveSince: {
        for (final detail in details)
          if (detail.state == LiveState.live && detail.card.liveSince != null) detail.ref.key: detail.card.liveSince!,
      },
      at: done,
    );
    // Published before the alerts, which may wait on the system.
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
