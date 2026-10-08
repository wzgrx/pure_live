import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/favorite/favorite_rules.dart';
import 'package:pure_live/features/favorite/follow_refresher.dart';
import 'package:pure_live/features/favorite/live_alerts.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/platform/live_alert_channel.dart';

/// The follows state, kept for the whole app session like 3.x's
/// `FavoriteController` (a GetX singleton): the home shell builds only the
/// visible tab, so the page itself comes and goes.
///
/// "开播提醒" (O01.1) posts through [liveAlertPosterProvider] (Android) and
/// also reads the recorder's checks of the same rooms.
final Provider<FavoriteController> favoriteControllerProvider = Provider((ref) {
  final services = ref.watch(appServicesProvider);
  final controller = FavoriteController(
    store: services.store,
    refresher: FollowRefresher(sites: services.sites),
    followsReady: services.followsReady,
    postLiveAlert: ref.watch(liveAlertPosterProvider),
  );
  final recorderChecks = services.recorder?.changes.listen(controller.recorderChanged);
  ref.onDispose(() {
    unawaited(recorderChecks?.cancel());
    controller.dispose();
  });
  return controller..start();
});

/// What the follows page shows and how it refreshes (3.x
/// `FavoriteController` and `favorite_startup_policy.dart`).
///
/// The follows, tags and their assignments come from the store and are
/// watched, so a follow added or a room updated anywhere shows here. A
/// refresh writes the fresh details back through `FollowStore.update`
/// (merge, not replace), all of a pass at once so cards do not reshuffle
/// as single requests finish (3.x).
///
/// Refreshes: every follow once at start, after the identity migration
/// (3.x verified on launch); the visible platform and tag on pull, on the
/// refresh button and when the follows tab is selected again; every follow
/// on the `autoRefreshFavorite` timer (silently) and when the app returns
/// from the background (`refreshFavoriteOnResume`, at most every 15 s).
///
/// "开播提醒" ([liveAlerts], O01.1; V01.1 L2, L5): every pass's rooms go to
/// it; the passes the user starts and watches (the start check, pull,
/// selecting follows again, the room switcher's button) only record what
/// is live. With "关注自动刷新" off and the alerts on, a timer checks only
/// the follows the alerts cover, every [liveAlertCheckInterval].
final class FavoriteController extends ChangeNotifier {
  /// Creates the controller; [postLiveAlert] posts "开播提醒" (null: none on
  /// this platform), whose own checks run every [liveAlertCheckInterval].
  new({
    required this.store,
    required this.refresher,
    Future<void>? followsReady,
    DateTime Function()? now,
    LiveAlertPoster? postLiveAlert,
    this.liveAlertCheckInterval = LiveAlerts.checkInterval,
  }) : _followsReady = followsReady ?? Future<void>.value(),
       _now = now ?? DateTime.now,
       liveAlerts = postLiveAlert == null ? null : LiveAlerts(settings: store.settings, post: postLiveAlert, now: now);

  /// Storage and settings.
  final LiveStore store;

  /// Runs the requests.
  final FollowRefresher refresher;

  /// "开播提醒"; null where nothing can be posted.
  final LiveAlerts? liveAlerts;

  /// How often "开播提醒" checks the follows it covers while "关注自动刷新"
  /// is off ([LiveAlerts.checkInterval]; shorter in tests).
  final Duration liveAlertCheckInterval;

  final Future<void> _followsReady;
  final DateTime Function() _now;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _autoRefresh;
  bool _disposed = false;

  /// The follows, in the user's order; empty until [loaded].
  List<LiveRoom> rooms = const [];

  /// The tags, in the user's order.
  List<StoreTag> tags = const [];

  /// Tag ids of each room, by identity key.
  Map<String, List<String>> assignments = const {};

  /// Whether the follows have been read once.
  bool loaded = false;

  /// The tab shown.
  FollowGroup group = FollowGroup.live;

  /// The platform shown ([allPlatforms] for all).
  String platform = allPlatforms;

  /// The tag shown ([allTags] for all).
  String tagId = allTags;

  /// The first check of every follow is running: cards show "verifying"
  /// (3.x `isVerifyingFavorites`).
  bool verifying = false;

  /// A refresh is running.
  bool refreshing = false;

  /// Progress of a visible refresh (0..1); null when none is shown.
  final ValueNotifier<double?> progress = ValueNotifier(null);

  /// Bumped to ask the page to show a tab (the empty state's "show offline").
  final ValueNotifier<FollowGroup?> requestedGroup = ValueNotifier(null);

  /// When the last refresh of every follow ended.
  DateTime? lastFullRefreshAt;

  /// Requests that failed in the last pass.
  int lastFailed = 0;

  Future<void>? _running;
  bool _runningFull = false;
  final Completer<List<LiveRoom>> _firstLoad = Completer();

  /// Starts watching the store and the home signals and checks every follow.
  void start() {
    _subscriptions
      ..add(
        store.follows.watchAll().listen((value) {
          rooms = value;
          loaded = true;
          if (!_firstLoad.isCompleted) _firstLoad.complete(value);
          _notify();
        }, onError: _followsFailed),
      )
      ..add(
        store.tags.watchAll().listen((value) {
          tags = value;
          if (tagId != allTags && !value.any((tag) => tag.id == tagId)) tagId = allTags;
          _notify();
        }, onError: _logError),
      )
      ..add(
        store.tags.watchAssignments().listen((value) {
          assignments = value;
          _notify();
        }, onError: _logError),
      )
      ..add(store.settings.changes.listen(_settingChanged));
    HomeSignals.favoritesReselected.addListener(_reselected);
    HomeSignals.resumedAfterBackground.addListener(_resumed);
    _scheduleAutoRefresh();
    _firstCheck = _verifyAll();
  }

  /// The order of live and replay follows, from the settings.
  FollowOrder get order => FollowOrder(
    preferRealOnline: store.settings.get(Settings.preferRealOnlineCounts),
    realOnlinePlatforms: store.settings.get(Settings.realOnlinePlatforms).toSet(),
    tags: tags,
  );

  /// The platform tabs.
  List<String> get platforms => platformTabs(rooms, store.settings.get(Settings.hotAreasList));

  /// The follows of [group] on [forPlatform] with the selected tag.
  List<LiveRoom> roomsFor(FollowGroup group, String forPlatform) =>
      roomsOf(rooms, group: group, platform: forPlatform, tagId: tagId, assignments: assignments, order: order);

  /// The tags offered for the shown tab and platform.
  List<StoreTag> get visibleTags =>
      tagsOf(rooms, group: group, platform: platform, tags: tags, assignments: assignments);

  /// Shows [value]; the tag filter goes back to all (3.x).
  void selectGroup(FollowGroup value) {
    if (group == value) return;
    group = value;
    tagId = allTags;
    _notify();
  }

  /// Shows [value]; the tag filter goes back to all (3.x).
  void selectPlatform(String value) {
    if (platform == value) return;
    platform = value;
    tagId = allTags;
    _notify();
  }

  /// Filters by tag [value].
  void selectTag(String value) {
    if (tagId == value) return;
    tagId = value;
    _notify();
  }

  /// Asks the page to show [value].
  // A request to the page, not a property of the controller.
  // ignore: use_setters_to_change_properties
  void showGroup(FollowGroup value) => requestedGroup.value = value;

  /// Refreshes the follows of the shown platform and tag, whatever their
  /// state (3.x pull to refresh, `_fullRefreshFilterRooms`).
  Future<void> refreshVisible() {
    final targets = [
      for (final room in rooms)
        if (onPlatform(room, platform) &&
            (tagId == allTags || (assignments[room.identityKey]?.contains(tagId) ?? false)))
          room,
    ];
    return _enqueue(targets, full: false, visible: true, bypassCooldown: true, alert: false);
  }

  /// Refreshes every follow; [alert]: "开播提醒" may post for this pass
  /// (false when the user started it and sees the result).
  Future<void> refreshAll({bool visible = true, bool bypassCooldown = true, bool alert = true}) =>
      _enqueue(rooms, full: true, visible: visible, bypassCooldown: bypassCooldown, alert: alert);

  /// The follows "开播提醒" covers ([liveAlertRooms]).
  List<LiveRoom> get liveAlertTargets =>
      liveAlertRooms(rooms, chosen: store.settings.get(Settings.liveAlertTagIds), tags: tags, assignments: assignments);

  /// The recorder's task list after a change: its fresh checks of rooms go
  /// to "开播提醒" like a pass's rooms.
  void recorderChanged(List<RecordTask> tasks) {
    final alerts = liveAlerts;
    if (alerts == null || _disposed) return;
    final checked = alerts.recorderChecks(tasks);
    if (checked.isEmpty) return;
    alerts.observe(checked, covered: _covered());
  }

  Set<String> _covered() => {for (final room in liveAlertTargets) room.identityKey};

  /// The first check of every follow (started by [start]; the splash page
  /// waits for it a little, 3.x).
  Future<void> get firstCheck => _firstCheck;
  Future<void> _firstCheck = Future.value();

  Future<void> _verifyAll() async {
    verifying = true;
    _notify();
    try {
      final first = await _firstLoad.future;
      await _followsReady;
      if (_disposed) return;
      // Read again only when the identity migration had follows to move;
      // otherwise the watched list is current.
      final all = first.any(LegacyRules.needsIdentityMigration) ? await store.follows.all() : rooms;
      if (_disposed) return;
      await _enqueue(all, full: true, visible: true, bypassCooldown: true, alert: false);
    } on Object catch (error, stack) {
      _logError(error, stack);
    } finally {
      verifying = false;
      _notify();
    }
  }

  /// Runs one pass after the one running; a pass of every follow already
  /// running covers the new request (3.x coalesced with the startup pass).
  Future<void> _enqueue(
    List<LiveRoom> targets, {
    required bool full,
    required bool visible,
    required bool bypassCooldown,
    required bool alert,
  }) async {
    // Waiters wake in order; each looks again, so passes never overlap.
    for (var running = _running; running != null; running = _running) {
      final coveredByRunning = _runningFull;
      await running;
      if (coveredByRunning) return;
    }
    if (_disposed) return;
    final pass = _pass(targets, full: full, visible: visible, bypassCooldown: bypassCooldown, alert: alert);
    _running = pass;
    _runningFull = full;
    try {
      await pass;
    } finally {
      if (identical(_running, pass)) _running = null;
    }
  }

  Future<void> _pass(
    List<LiveRoom> targets, {
    required bool full,
    required bool visible,
    required bool bypassCooldown,
    required bool alert,
  }) async {
    refreshing = true;
    if (visible) progress.value = 0;
    _notify();
    try {
      final result = await refresher.refresh(
        targets,
        concurrency: store.settings.get(Settings.maxConcurrentRefresh),
        bypassCooldown: bypassCooldown,
        cancelled: () => _disposed,
        onProgress: visible ? (done, total) => progress.value = total == 0 ? 1 : done / total : null,
      );
      if (_disposed) return;
      liveAlerts?.observe(result.rooms, covered: _covered(), quiet: !alert);
      lastFailed = result.failed;
      if (result.rooms.isNotEmpty) await store.follows.update(result.rooms);
      if (full) lastFullRefreshAt = _now();
    } on Object catch (error, stack) {
      _logError(error, stack);
    } finally {
      refreshing = false;
      if (!_disposed) progress.value = null;
      _notify();
    }
  }

  void _reselected() {
    if (refreshing) return;
    unawaited(refreshVisible());
  }

  void _resumed() {
    if (!store.settings.get(Settings.refreshFavoriteOnResume)) return;
    final last = lastFullRefreshAt;
    if (last != null && _now().difference(last) < HomeSignals.resumeRefreshAfter) return;
    unawaited(refreshAll());
  }

  void _settingChanged(Setting<Object> setting) {
    if (setting == Settings.autoRefreshFavorite ||
        setting == Settings.autoRefreshInterval ||
        setting == Settings.liveAlertEnabled) {
      if (setting == Settings.liveAlertEnabled && !(liveAlerts?.enabled ?? false)) liveAlerts?.tracker.forget();
      _scheduleAutoRefresh();
    } else if (setting == Settings.preferRealOnlineCounts ||
        setting == Settings.realOnlinePlatforms ||
        setting == Settings.hotAreasList) {
      _notify();
    }
  }

  /// "关注自动刷新" checks every follow at its interval; without it, the
  /// alerts check only the follows they cover, every
  /// [liveAlertCheckInterval]; with neither nothing runs (V01.1 L2).
  void _scheduleAutoRefresh() {
    _autoRefresh?.cancel();
    _autoRefresh = null;
    if (store.settings.get(Settings.autoRefreshFavorite)) {
      final minutes = store.settings.get(Settings.autoRefreshInterval);
      _autoRefresh = Timer.periodic(
        Duration(minutes: minutes),
        (_) => unawaited(refreshAll(visible: false, bypassCooldown: false)),
      );
    } else if (liveAlerts?.enabled ?? false) {
      _autoRefresh = Timer.periodic(
        liveAlertCheckInterval,
        (_) => unawaited(_enqueue(liveAlertTargets, full: false, visible: false, bypassCooldown: false, alert: true)),
      );
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// The follows could not be read: show the empty page instead of the
  /// skeleton and let the start check end.
  void _followsFailed(Object error, StackTrace stack) {
    _logError(error, stack);
    loaded = true;
    if (!_firstLoad.isCompleted) _firstLoad.complete(rooms);
    _notify();
  }

  void _logError(Object error, [StackTrace? stack]) =>
      log('Follows failed', name: 'FavoritePage', error: error, stackTrace: stack);

  @override
  void dispose() {
    _disposed = true;
    _autoRefresh?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    HomeSignals.favoritesReselected.removeListener(_reselected);
    HomeSignals.resumedAfterBackground.removeListener(_resumed);
    progress.dispose();
    requestedGroup.dispose();
    super.dispose();
  }
}
