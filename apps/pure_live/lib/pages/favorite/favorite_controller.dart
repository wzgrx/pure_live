import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/home/home_menu.dart';
import 'package:pure_live/pages/favorite/favorite_rules.dart';
import 'package:pure_live/pages/favorite/follow_refresher.dart';

/// The follows state, kept for the whole app session like 3.x's
/// `FavoriteController` (a GetX singleton): the home shell builds only the
/// visible tab, so the page itself comes and goes.
final Provider<FavoriteController> favoriteControllerProvider = Provider((ref) {
  final services = ref.watch(appServicesProvider);
  final controller = FavoriteController(
    store: services.store,
    refresher: FollowRefresher(sites: services.sites),
    followsReady: services.followsReady,
  );
  ref.onDispose(controller.dispose);
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
final class FavoriteController extends ChangeNotifier {
  /// Creates the controller.
  new({required this.store, required this.refresher, Future<void>? followsReady, DateTime Function()? now})
    : _followsReady = followsReady ?? Future<void>.value(),
      _now = now ?? DateTime.now;

  /// Storage and settings.
  final LiveStore store;

  /// Runs the requests.
  final FollowRefresher refresher;

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
    unawaited(_verifyAll());
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
    return _enqueue(targets, full: false, visible: true, bypassCooldown: true);
  }

  /// Refreshes every follow.
  Future<void> refreshAll({bool visible = true, bool bypassCooldown = true}) =>
      _enqueue(rooms, full: true, visible: visible, bypassCooldown: bypassCooldown);

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
      await _enqueue(all, full: true, visible: true, bypassCooldown: true);
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
  }) async {
    // Waiters wake in order; each looks again, so passes never overlap.
    for (var running = _running; running != null; running = _running) {
      final coveredByRunning = _runningFull;
      await running;
      if (coveredByRunning) return;
    }
    if (_disposed) return;
    final pass = _pass(targets, full: full, visible: visible, bypassCooldown: bypassCooldown);
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
    if (setting == Settings.autoRefreshFavorite || setting == Settings.autoRefreshInterval) {
      _scheduleAutoRefresh();
    } else if (setting == Settings.preferRealOnlineCounts ||
        setting == Settings.realOnlinePlatforms ||
        setting == Settings.hotAreasList) {
      _notify();
    }
  }

  void _scheduleAutoRefresh() {
    _autoRefresh?.cancel();
    _autoRefresh = null;
    if (!store.settings.get(Settings.autoRefreshFavorite)) return;
    final minutes = store.settings.get(Settings.autoRefreshInterval);
    _autoRefresh = Timer.periodic(
      Duration(minutes: minutes),
      (_) => unawaited(refreshAll(visible: false, bypassCooldown: false)),
    );
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
