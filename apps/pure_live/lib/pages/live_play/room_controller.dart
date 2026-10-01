import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/live_play/chat_feed.dart';
import 'package:pure_live/pages/live_play/room_texts.dart';

/// Where the room page is (3.x kept `isLoading`, `success`, `isLiving` and
/// `loadError` as four flags that could contradict each other).
enum RoomStage {
  /// The room detail is being fetched.
  loading,

  /// The detail could not be fetched; [LiveRoomController.failure] says why.
  failed,

  /// The platform says the room is not broadcasting (offline, banned,
  /// carousel) or did not say (pending).
  offline,

  /// On air, but no stream could be resolved (no qualities, no URLs, or the
  /// platform refused: login, region, paid); [LiveRoomController.failure].
  unplayable,

  /// A stream is open in the session; its own state says playing, buffering
  /// or failed.
  playing,
}

/// The room page's logic (3.x `LivePlayController`, `PlayerController` and
/// `DanmakuController` without GetX): room detail, qualities and lines,
/// playback, danmaku, super chats, audience and the periodic refresh.
///
/// Everything it needs is passed in, so tests drive it with fakes.
class LiveRoomController extends ChangeNotifier {
  /// Creates the controller for [room] on [site]; call [start].
  new({
    required this._room,
    required this.site,
    required this.session,
    required this.danmaku,
    required this.danmakuSupported,
    required this.store,
    this.mobile = false,
    this.toast,
    DateTime Function()? now,
    this.refreshInterval = const Duration(seconds: 60),
    this.danmakuStartTimeout = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now {
    _filter = DanmakuMessageFilter(clock: _now);
  }

  /// The platform.
  final LiveSite site;

  /// The player; the page owns it and disposes it after this controller.
  final PlaybackSession session;

  /// The danmaku connection of [site].
  final DanmakuConnection danmaku;

  /// Whether the platform has danmaku at all (3.x: `engine is EmptyDanmaku`).
  final bool danmakuSupported;

  /// Settings, follows, history and block lists.
  final LiveStore store;

  /// A phone: the system volume governs (3.x forced 1.0 there).
  final bool mobile;

  /// Shows a short message (the app's SnackBar).
  final void Function(String message)? toast;

  /// How often the room detail is fetched again while the page is open.
  final Duration refreshInterval;

  /// How long the first danmaku attempt may take (Kuaishou's poll waits up
  /// to 20 s before it tries its backup host, so 3.x's 20 s cut it off).
  final Duration danmakuStartTimeout;

  final DateTime Function() _now;
  late final DanmakuMessageFilter _filter;
  final DanmakuNoticeThrottle _notices = DanmakuNoticeThrottle();

  /// The chat list.
  final ChatFeed chat = ChatFeed();
  final StreamController<LiveMessage> _flying = StreamController.broadcast(sync: true);
  final StreamController<LiveRetraction> _retractions = StreamController.broadcast(sync: true);
  final List<StreamSubscription<Object?>> _subscriptions = [];
  LiveQualityDiscoveryScope _qualityScope = LiveQualityDiscoveryScope();
  Timer? _refreshTimer;
  Timer? _superChatTimer;
  int _epoch = 0;
  int _danmakuEpoch = 0;
  bool _disposed = false;
  bool _maskedNameShown = false;
  bool _unsupportedShown = false;
  bool _historyRecorded = false;

  LiveRoom _room;
  RoomStage _stage = RoomStage.loading;
  Object? _failure;
  List<LivePlayQuality> _qualities = const [];
  int _qualityIndex = 0;
  bool _switching = false;
  List<LiveSuperChatMessage> _superChats = const [];

  /// The room as known now (the card's data until the detail arrives).
  LiveRoom get room => _room;

  /// Where the page is.
  RoomStage get stage => _stage;

  /// Why [stage] is [RoomStage.failed] or [RoomStage.unplayable].
  Object? get failure => _failure;

  /// The platform's qualities, best first.
  List<LivePlayQuality> get qualities => _qualities;

  /// The quality that plays.
  int get qualityIndex => _qualityIndex;

  /// A quality switch is resolving.
  bool get switching => _switching;

  /// Super chats still on display, oldest first.
  List<LiveSuperChatMessage> get superChats => _superChats;

  /// Chat messages for the flying layer, as they pass the filters.
  Stream<LiveMessage> get flying => _flying.stream;

  /// Messages the platform took back (the flying layer removes them).
  Stream<LiveRetraction> get retractions => _retractions.stream;

  /// What "now" is (tests fix it).
  DateTime now() => _now();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Subscribes to danmaku and settings, loads the room and starts the
  /// periodic refresh.
  Future<void> start() async {
    _subscriptions
      ..add(danmaku.events.listen(_onDanmaku))
      ..add(store.blockLists.watch(BlockKind.keyword).listen((_) => unawaited(_reloadFilter())))
      ..add(store.blockLists.watch(BlockKind.user).listen((_) => unawaited(_reloadFilter())));
    for (final setting in _filterSettings) {
      _subscriptions.add(store.settings.watch(setting).skip(1).listen((_) => unawaited(_reloadFilter())));
    }
    for (final setting in [Settings.enableDanmakuDisplay, Settings.enablePipDanmaku]) {
      _subscriptions.add(store.settings.watch(setting).skip(1).listen((_) => unawaited(_syncDanmaku())));
    }
    await _reloadFilter();
    if (refreshInterval > Duration.zero) {
      _refreshTimer = Timer.periodic(refreshInterval, (_) => unawaited(refreshDetail()));
    }
    await load();
  }

  static const List<Setting<Object>> _filterSettings = [
    Settings.collapseRepeatedDanmaku,
    Settings.repeatedDanmakuWindowSeconds,
    Settings.enableDanmakuSimilarityFilter,
    Settings.danmakuSimilarityThreshold,
    Settings.danmakuSimilarityCacheDuration,
    Settings.danmakuSimilarityMaxCacheSize,
  ];

  Future<void> _reloadFilter() async {
    final settings = store.settings;
    final keywords = await store.blockLists.list(BlockKind.keyword);
    final users = await store.blockLists.list(BlockKind.user);
    if (_disposed) return;
    _filter.settings = DanmakuFilterSettings(
      collapseRepeated: settings.get(Settings.collapseRepeatedDanmaku),
      repeatedWindowSeconds: settings.get(Settings.repeatedDanmakuWindowSeconds),
      similarityEnabled: settings.get(Settings.enableDanmakuSimilarityFilter),
      similarityThreshold: settings.get(Settings.danmakuSimilarityThreshold),
      similarityCacheSeconds: settings.get(Settings.danmakuSimilarityCacheDuration),
      similarityMaxCacheSize: settings.get(Settings.danmakuSimilarityMaxCacheSize),
      blockedUsers: users,
      blockedKeywords: keywords,
    );
  }

  /// Fetches the room detail and plays it when it is on air (3.x
  /// `onInitPlayerState`). Also the "refresh room" action and the retry
  /// after a failed detail.
  Future<void> load() async {
    if (_disposed) return;
    final epoch = ++_epoch;
    _stage = RoomStage.loading;
    _failure = null;
    _notify();
    final requested = _room;
    final LiveRoom fetched;
    try {
      fetched = await site.getRoomDetail(roomId: requested.roomId);
    } on Object catch (error, stackTrace) {
      if (!_current(epoch)) return;
      developer.log('Room detail failed', name: 'LivePlay', error: error, stackTrace: stackTrace);
      // The stored identity and names stay; the state becomes pending
      // (M4 notes: a failed request is no evidence the broadcast ended).
      _room = requested.pendingAfterError();
      _stage = RoomStage.failed;
      _failure = error;
      await _stopStream();
      _notify();
      return;
    }
    if (!_current(epoch)) return;
    _room = fetched.withAudienceFallbackFrom(requested).fillFromDetail(requested);
    _notify();
    unawaited(_saveFollowSnapshot());
    if (!_room.isPlayableNow) {
      _stage = RoomStage.offline;
      await _stopStream();
      _notify();
      return;
    }
    await _startStream(epoch);
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;

  Future<void> _stopStream() async {
    _qualityScope.cancel();
    unawaited(danmaku.close());
    _clearSuperChats();
    if (session.state.status != PlaybackStatus.idle) await session.stop();
  }

  Future<void> _startStream(int epoch) async {
    unawaited(_qualityScope.close());
    final scope = _qualityScope = LiveQualityDiscoveryScope();
    final previous = _qualities.elementAtOrNull(_qualityIndex);
    final List<LivePlayQuality> found;
    try {
      found = _normalizeQualities(await scope.discover(site, _room));
    } on Object catch (error) {
      if (!_current(epoch)) return;
      _unplayable(error);
      return;
    }
    if (!_current(epoch)) return;
    if (found.isEmpty) {
      _unplayable(StreamUnavailable(site.id, 'no qualities'));
      return;
    }
    _qualities = found;
    final kept = previous == null ? -1 : found.indexWhere((q) => q.selectionId == previous.selectionId);
    _qualityIndex = kept >= 0 ? kept : defaultQualityIndex(found, store.settings.get(Settings.preferResolution));
    _notify();
    final opened = await _openQuality(_qualityIndex, epoch, userChoice: false);
    if (!opened || !_current(epoch)) return;
    if (!_historyRecorded && site.id != SiteIds.iptv) {
      _historyRecorded = true;
      unawaited(_guard(() => store.history.record(_room, now: _now()), 'history'));
    }
    unawaited(_syncDanmaku(force: true));
    unawaited(_loadSuperChats(epoch));
  }

  void _unplayable(Object error) {
    developer.log('Room cannot play', name: 'LivePlay', error: error);
    _stage = RoomStage.unplayable;
    _failure = error;
    unawaited(session.stop());
    _notify();
  }

  /// Resolves quality [index] and opens it. Returns whether a stream opened.
  Future<bool> _openQuality(int index, int epoch, {required bool userChoice}) async {
    final requested = _qualities[index];
    final LivePlayUrlResolution resolution;
    try {
      resolution = site is LivePlayRecoveryResolver && userChoice
          ? await site.resolvePlayUrlsForRecovery(detail: _room, quality: requested)
          : await site.resolvePlayUrls(detail: _room, quality: requested);
    } on Object catch (error) {
      if (!_current(epoch)) return false;
      if (userChoice && _stage == RoomStage.playing) {
        toast?.call(failureText(error));
        return false;
      }
      _unplayable(error);
      return false;
    }
    if (!_current(epoch)) return false;
    if (!resolution.hasSources) {
      if (userChoice && _stage == RoomStage.playing) {
        toast?.call(i18n('cannot_read_play_url'));
        return false;
      }
      _unplayable(StreamUnavailable(site.id, 'no urls'));
      return false;
    }
    final applied = resolveAppliedPlayQuality(qualities: _qualities, requested: requested, resolution: resolution);
    final appliedIndex = _qualities.indexWhere((q) => q.selectionId == applied.selectionId);
    final playing = appliedIndex >= 0 ? appliedIndex : index;
    if (userChoice && playing != index) {
      toast?.call(i18n('quality_limited_to', args: {'quality': _qualities[playing].quality}));
    }
    _qualities = List.unmodifiable(List.of(_qualities)..[playing] = applied);
    _qualityIndex = playing;
    _stage = RoomStage.playing;
    _failure = null;
    _notify();
    final quality = _qualities[playing];
    await session.open(
      PlaybackRequest(site: site.id, plan: _plan(resolution), refresh: () => _refreshPlan(quality), volume: _volume()),
    );
    return _current(epoch);
  }

  PlaybackPlan _plan(LivePlayUrlResolution resolution) =>
      PlaybackPlan.of(resolution, preferH264: store.settings.get(Settings.preferH264), onDemand: _room.isRecord);

  Future<PlaybackPlan> _refreshPlan(LivePlayQuality quality) async {
    final resolution = await site.resolvePlayUrlsForRecovery(detail: _room, quality: quality);
    return _plan(resolution);
  }

  double _volume() {
    final settings = store.settings;
    if (settings.get(Settings.globalVolumeMute)) return 0;
    // 3.x's adapter forced 1.0 on phones: the system volume governs there.
    if (mobile) return 1;
    final saved = <String, double>{
      for (final MapEntry(:key, :value) in settings.get(Settings.roomVolumes).entries)
        if (value is num) key: value.toDouble(),
    };
    return roomVolume(
      platform: _room.platform,
      roomId: _room.roomId,
      saved: saved,
      globalMute: false,
      mobile: false,
      defaultDesktop: settings.get(Settings.defaultDesktopVolume),
    );
  }

  /// Plays quality [index] (3.x `setResolution(changeQuality)`); the old
  /// stream keeps playing until the new one resolves.
  Future<void> selectQuality(int index) async {
    if (_switching || index < 0 || index >= _qualities.length || index == _qualityIndex) return;
    if (_stage != RoomStage.playing) return;
    _switching = true;
    _notify();
    try {
      await _openQuality(index, _epoch, userChoice: true);
    } finally {
      _switching = false;
      _notify();
    }
  }

  /// Plays line [index] of the current quality.
  Future<void> selectLine(int index) => session.selectLine(index);

  /// The retry button: the stream again when only playback failed, else the
  /// whole room.
  Future<void> retry() async {
    if (_stage == RoomStage.playing && session.state.status == PlaybackStatus.error) {
      final failure = session.state.failure;
      if (failure != SourceFailureKind.terminal) {
        await session.retry();
        return;
      }
    }
    await load();
  }

  /// Fetches the detail again in the background (title, audience, state):
  /// a room that comes on air starts playing, and a danmaku connection that
  /// ended (a broadcast ended and restarted, B-24) connects again.
  Future<void> refreshDetail() async {
    if (_disposed || _stage == RoomStage.loading) return;
    final epoch = _epoch;
    LiveRoom fetched;
    try {
      fetched = switch (site) {
        final LiveSiteRoomRefresher refresher => await refresher.getRoomDetailForRefresh(roomId: _room.roomId),
        _ => await site.getRoomDetail(roomId: _room.roomId),
      };
    } on Object catch (error) {
      developer.log('Room refresh failed', name: 'LivePlay', error: error);
      return;
    }
    if (!_current(epoch) || fetched.isLiveStatusPending) return;
    final playing = _stage == RoomStage.playing;
    if (!playing && fetched.isPlayableNow) {
      await load();
      return;
    }
    if (playing && !fetched.isPlayableNow && session.state.status == PlaybackStatus.error) {
      await load();
      return;
    }
    _room = _room.mergeFrom(fetched).withAudienceFallbackFrom(_room);
    _notify();
    if (playing && danmaku.status == DanmakuStatus.closed) unawaited(_syncDanmaku(force: true));
  }

  /// A followed room's card gets the fresh detail (3.x
  /// `_updateFavoriteRoomSnapshot`); rooms not followed are untouched.
  Future<void> _saveFollowSnapshot() => _guard(() => store.follows.update([_room]), 'follow snapshot');

  Future<void> _guard(Future<Object?> Function() action, String what) async {
    try {
      await action();
    } on Object catch (error, stackTrace) {
      developer.log('Saving $what failed', name: 'LivePlay', error: error, stackTrace: stackTrace);
    }
  }

  // ---- danmaku ----

  bool get _wantsDanmaku =>
      store.settings.get(Settings.enableDanmakuDisplay) || store.settings.get(Settings.enablePipDanmaku);

  Future<void> _syncDanmaku({bool force = false}) async {
    if (_disposed) return;
    if (_stage != RoomStage.playing || !_wantsDanmaku || site.id == SiteIds.iptv) {
      await danmaku.close();
      return;
    }
    if (!danmakuSupported) {
      if (!_unsupportedShown) {
        _unsupportedShown = true;
        _system(i18n('live_play_danmaku_unsupported'));
      }
      return;
    }
    if (!force && danmaku.status != DanmakuStatus.idle && danmaku.status != DanmakuStatus.closed) return;
    final epoch = ++_danmakuEpoch;
    _maskedNameShown = false;
    if (_room.isRecord) _system(i18n('recording_mode_notice'));
    _system(i18n('connect_danmaku_server'));
    try {
      await danmaku.connect(_room.danmakuData).timeout(danmakuStartTimeout);
    } on TimeoutException {
      if (epoch != _danmakuEpoch || _disposed) return;
      await danmaku.close();
      _system(i18n('danmaku_connection_timeout'));
    } on Object catch (error, stackTrace) {
      if (epoch != _danmakuEpoch || _disposed) return;
      developer.log('Danmaku start failed', name: 'LivePlay', error: error, stackTrace: stackTrace);
      await danmaku.close();
      _system(i18n('live_play_danmaku_connect_failed'));
    }
  }

  void _onDanmaku(DanmakuEvent event) {
    if (_disposed) return;
    switch (event) {
      case DanmakuReady():
        _system(i18n('danmaku_connected'));
      case DanmakuReceived(:final message):
        _onMessage(message);
      case DanmakuReconnecting(:final reason):
        _system(interruptionText(reason));
      case DanmakuClosed(:final reason):
        _system(closeText(reason));
    }
  }

  void _onMessage(LiveMessage message) {
    switch (message.type) {
      case LiveMessageType.chat:
        if (!_filter.accepts(message)) return;
        if (!_maskedNameShown &&
            _room.platform == SiteIds.bilibili &&
            RegExp(r'\*{2,}|＊{2,}').hasMatch(message.userName)) {
          _maskedNameShown = true;
          _system(i18n('bilibili_guest_name_masked'));
        }
        chat.add(ChatLine.chat(message));
        _flying.add(message);
        _notify();
      case LiveMessageType.online:
        _applyAudience(message.data);
      case LiveMessageType.superChat:
        if (message.data case final LiveSuperChatMessage superChat) {
          _addSuperChats([superChat]);
          chat.add(ChatLine.superChat(superChat));
          _notify();
        }
      case LiveMessageType.retraction:
        if (message.data case final LiveRetraction retraction) {
          chat.retract(retraction);
          _retractions.add(retraction);
          _notify();
        }
      case LiveMessageType.notice:
        if (message.message.trim().isEmpty || !_notices.accepts(message.message)) return;
        chat.add(ChatLine.notice(message));
        _notify();
      case LiveMessageType.gift:
        // Gifts are reported but not shown yet (B-21, decided with the gift UI).
        return;
    }
  }

  void _system(String text) {
    chat.add(ChatLine.system(text));
    _notify();
  }

  /// An audience figure from the danmaku (3.x `updateRuntimeAudience`).
  void _applyAudience(Object? data) {
    final update = switch (data) {
      final LiveAudienceUpdate update => update,
      final num value => LiveAudienceUpdate(
        kind: _room.platform == SiteIds.bilibili
            ? LiveAudienceMetricKind.popularity
            : LiveAudienceMetricKind.onlineViewers,
        value: value.toInt(),
      ),
      _ => null,
    };
    if (update == null || update.value < 0) return;
    final text = '${update.value}';
    final candidate = switch (update.kind) {
      LiveAudienceMetricKind.popularity => _room.copyWith(
        popularity: text,
        watching: text,
        audienceMetricType: AudienceMetricType.popularity,
      ),
      LiveAudienceMetricKind.onlineViewers => _room.copyWith(onlineViewers: text),
      LiveAudienceMetricKind.totalViewers => _room.copyWith(totalViewers: text),
    };
    _room = candidate.withAudienceFallbackFrom(_room);
    _notify();
  }

  // ---- super chats ----

  Future<void> _loadSuperChats(int epoch) async {
    try {
      final list = await site.getSuperChatMessage(roomId: _room.roomId);
      if (!_current(epoch)) return;
      _addSuperChats(list);
      _notify();
    } on Object catch (error) {
      developer.log('Super chats failed', name: 'LivePlay', error: error);
    }
  }

  void _addSuperChats(Iterable<LiveSuperChatMessage> incoming) {
    final now = _now();
    final next = <LiveSuperChatMessage>{..._superChats, ...incoming}.where((sc) => sc.endTime.isAfter(now)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    _superChats = List.unmodifiable(next);
    _scheduleSuperChatExpiry();
  }

  void _scheduleSuperChatExpiry() {
    _superChatTimer?.cancel();
    if (_superChats.isEmpty || _disposed) return;
    final next = _superChats.map((sc) => sc.endTime).reduce((a, b) => a.isBefore(b) ? a : b);
    final delay = next.difference(_now());
    _superChatTimer = Timer(delay.isNegative ? Duration.zero : delay + const Duration(milliseconds: 1), () {
      _addSuperChats(const []);
      _notify();
    });
  }

  void _clearSuperChats() {
    _superChatTimer?.cancel();
    _superChats = const [];
  }

  // ---- blocking ----

  /// Blocks [userName]'s messages from now on and takes theirs off the list.
  Future<void> blockUser(String userName) async {
    final name = userName.trim();
    if (name.isEmpty) return;
    await store.blockLists.add(BlockKind.user, name);
    chat.removeWhere((line) => line.message?.userName.trim().toLowerCase() == name.toLowerCase());
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _refreshTimer?.cancel();
    _superChatTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_qualityScope.close());
    unawaited(danmaku.close());
    unawaited(_flying.close());
    unawaited(_retractions.close());
    super.dispose();
  }
}

/// [qualities] without blank labels and repeated options, in the platform's
/// order (3.x `normalizePlayQualities`).
List<LivePlayQuality> _normalizeQualities(List<LivePlayQuality> qualities) {
  final seen = <String>{};
  return [
    for (final quality in qualities)
      if (quality.quality.trim().isNotEmpty && seen.add('${quality.selectionId}')) quality,
  ];
}

/// The quality to start with (3.x `_setDefaultResolution`): the one named
/// like the preference, else the same relative position in the list (3.x's
/// five names from best to worst).
@visibleForTesting
int defaultQualityIndex(List<LivePlayQuality> qualities, String preferred) {
  if (qualities.isEmpty) return 0;
  final exact = qualities.indexWhere((q) => q.quality == preferred);
  if (exact >= 0) return exact;
  const names = ['原画', '蓝光8M', '蓝光4M', '超清', '流畅'];
  final level = names.indexOf(preferred);
  if (level < 0) return 0;
  final ratio = level / (names.length - 1);
  return (ratio * (qualities.length - 1)).round().clamp(0, qualities.length - 1);
}
