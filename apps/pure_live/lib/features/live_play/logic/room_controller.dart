import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/system_access.dart';
import 'package:pure_live/shared/rooms/play_quality.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

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

/// Where the room's danmaku connection is, for the chat list's empty states
/// (docs/A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页 c2: 3.x showed the same blank list whether it was
/// connecting, connected with nobody talking, timed out or not offered).
enum ChatConnection {
  /// Not asked for (loading, offline, danmaku switched off, IPTV).
  idle,

  /// Connecting.
  connecting,

  /// Connected.
  connected,

  /// The first attempt did not answer in time; it was released and may be
  /// tried again.
  timedOut,

  /// The connection failed or ended for good; it may be tried again.
  failed,

  /// The platform has no danmaku (3.x `EmptyDanmaku`, NetEase CC).
  unsupported,
}

/// What the chat list says above its lines about Bilibili's names (task
/// B06 c1): the server masks every name (`观***`) for a connection that is
/// not logged in, whatever the client reads.
enum ChatNameHint {
  /// Nothing to say: not Bilibili, no danmaku, or full names.
  none,

  /// No Bilibili login: "访客模式下哔哩哔哩会隐藏昵称 · 去登录".
  guest,

  /// A login is stored but the names still come masked: "登录已失效 ·
  /// 重新登录".
  loginExpired,
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
    this.sleepSessionOnStart = false,
    this.minuteLength = const Duration(minutes: 1),
    this.network,
    DateTime Function()? now,
    this.refreshInterval = const Duration(seconds: 60),
    this.danmakuStartTimeout = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now {
    _filter = DanmakuMessageFilter(clock: _now);
    _statusLines = DanmakuNoticeThrottle(clock: _now);
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

  /// Starts as a sleep session: audio only with the sleep timer of
  /// `asmrSleepMinutes` (3.x's automatic ASMR mode on Android).
  final bool sleepSessionOnStart;

  /// A minute of the sleep timer (tests shorten it).
  final Duration minuteLength;

  /// Reads the network for the first quality: mobile data uses
  /// [Settings.preferResolutionCellular] (3.x `_setDefaultResolution`);
  /// null always uses [Settings.preferResolution].
  final NetworkProbe? network;

  /// How often the room detail is fetched again while the page is open.
  final Duration refreshInterval;

  /// Whether the periodic refresh may start playback by itself now (C01.5):
  /// the background policy answers false while the app is away and the room
  /// was not playing when it left, so a broadcast that begins then makes no
  /// sound nobody asked for (3.x had no periodic refresh at all). Null
  /// always may.
  bool Function()? mayAutoStart;

  /// A refresh found the room playable while it could not start; the
  /// background policy loads it when the app is back ([takeStartWhenBack]).
  bool _startWhenBack = false;

  /// Whether a refresh left the start for the app's return; reading clears it.
  bool takeStartWhenBack() {
    final start = _startWhenBack;
    _startWhenBack = false;
    return start;
  }

  /// How long the first danmaku attempt may take (Kuaishou's poll waits up
  /// to 20 s before it tries its backup host, so 3.x's 20 s cut it off).
  final Duration danmakuStartTimeout;

  final DateTime Function() _now;
  late final DanmakuMessageFilter _filter;
  final DanmakuNoticeThrottle _notices = DanmakuNoticeThrottle();

  /// The app's own status lines: the same line twice within 3 s shows once
  /// (3.x `_addStatusMessage`).
  late final DanmakuNoticeThrottle _statusLines;

  /// The chat list; it tells its own listeners of new lines, at most once a
  /// frame (B08: the controller no longer notifies for each message).
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
  int _maskedChats = 0;
  int _namedChats = 0;
  bool _unsupportedShown = false;
  bool _historyRecorded = false;
  // C01.4: entering the room says once that the platform served another
  // tier; a refresh or a reload does not say it again.
  bool _servedToastShown = false;

  LiveRoom _room;
  RoomStage _stage = RoomStage.loading;
  Object? _failure;
  List<LivePlayQuality> _qualities = const [];
  int _qualityIndex = 0;
  bool _switching = false;
  bool _switchingLine = false;
  List<LiveSuperChatMessage> _superChats = const [];
  bool _showGifts = true;
  bool _audioOnly = false;
  Timer? _sleepTimer;
  DateTime? _sleepDeadline;
  int _sleepMinutes = 60;
  bool _sleepSession = false;
  EpgProgramme? _catchup;
  ChatConnection _chatConnection = ChatConnection.idle;

  /// The meta key of the "show gifts" switch (B-21).
  static const String showGiftsKey = 'live_play.showGifts';

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

  /// A line switch is opening (3.x's `isStreamSwitching` covered both: the
  /// quality and line buttons wait while either switches).
  bool get switchingLine => _switchingLine;

  /// Super chats still on display, oldest first.
  List<LiveSuperChatMessage> get superChats => _superChats;

  /// Chat messages for the flying layer, as they pass the filters.
  Stream<LiveMessage> get flying => _flying.stream;

  /// Messages the platform took back (the flying layer removes them).
  Stream<LiveRetraction> get retractions => _retractions.stream;

  /// What "now" is (tests fix it).
  DateTime now() => _now();

  /// Gifts appear in the chat list (B-21); the switch is kept in `meta`.
  bool get showGifts => _showGifts;

  /// Video is off: only the sound plays (3.x's headphone button).
  bool get audioOnly => _audioOnly;

  /// When the sleep timer stops the room, or null when it is off.
  DateTime? get sleepDeadline => _sleepDeadline;

  /// The sleep timer's last length in minutes (3.x `closeTimes`, 60).
  int get sleepMinutes => _sleepMinutes;

  /// A sleep session runs: it keeps playing in the background until its
  /// timer ends (`shouldContinueInBackground`).
  bool get sleepSessionActive => _sleepSession && _sleepDeadline != null;

  /// The IPTV programme being replayed, or null for the live channel.
  EpgProgramme? get catchup => _catchup;

  /// Where the danmaku connection is (the chat list's empty states).
  ChatConnection get chatConnection => _chatConnection;

  void _setChat(ChatConnection value) {
    if (_chatConnection == value) return;
    _chatConnection = value;
    _notify();
  }

  /// Connects the danmaku again after a timeout or a failure (the chat
  /// list's "重新连接", U.2e c2).
  Future<void> reconnectDanmaku() => _syncDanmaku(force: true);

  /// Masked chats in one connection, with no full name among them, after
  /// which a stored Bilibili login counts as expired ([ChatNameHint]).
  static const int maskedChatsForExpiredLogin = 3;

  /// What the chat list says about Bilibili's names (B06 c1): [ChatNameHint.guest]
  /// while a Bilibili room's danmaku is on without a login,
  /// [ChatNameHint.loginExpired] when a login is stored but this connection
  /// got [maskedChatsForExpiredLogin] masked names and no full one.
  ChatNameHint get nameHint {
    if (_room.platform != SiteIds.bilibili) return ChatNameHint.none;
    if (_chatConnection == ChatConnection.idle || _chatConnection == ChatConnection.unsupported) {
      return ChatNameHint.none;
    }
    if (!_signedIn) return ChatNameHint.guest;
    return _maskedChats >= maskedChatsForExpiredLogin && _namedChats == 0
        ? ChatNameHint.loginExpired
        : ChatNameHint.none;
  }

  bool get _signedIn => store.secrets.cookieFor(SiteIds.bilibili)?.trim().isNotEmpty ?? false;

  /// The Bilibili login changed (signed in from the hint, signed out, or
  /// renewed): fresh danmaku credentials for the new login, then the
  /// danmaku again, so the names come as the new login sees them (B06 c1).
  Future<void> _onLoginChanged(String platform) async {
    if (_disposed || platform != SiteIds.bilibili || _room.platform != SiteIds.bilibili) return;
    _notify();
    if (!_danmakuStage || !_wantsDanmaku) return;
    final epoch = _epoch;
    try {
      final fetched = await site.getRoomDetail(roomId: _room.roomId);
      if (!_current(epoch)) return;
      if (fetched.danmakuData case final Object data) _room = _room.copyWith(danmakuData: data);
    } on Object catch (error) {
      // The connection still renews a missing token itself.
      developer.log('Danmaku credentials after a login change failed', name: 'LivePlay', error: error);
      if (!_current(epoch)) return;
    }
    await _syncDanmaku(force: true);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Subscribes to danmaku and settings, loads the room and starts the
  /// periodic refresh.
  Future<void> start() async {
    _subscriptions
      ..add(danmaku.events.listen(_onDanmaku))
      ..add(store.blockLists.watch(BlockKind.keyword).listen((_) => unawaited(_reloadFilter())))
      ..add(store.blockLists.watch(BlockKind.user).listen((_) => unawaited(_reloadFilter())))
      ..add(store.secrets.cookieChanges.listen((platform) => unawaited(_onLoginChanged(platform))));
    for (final setting in _filterSettings) {
      _subscriptions.add(store.settings.watch(setting).skip(1).listen((_) => unawaited(_reloadFilter())));
    }
    for (final setting in [Settings.enableDanmakuDisplay, Settings.enablePipDanmaku]) {
      _subscriptions.add(store.settings.watch(setting).skip(1).listen((_) => unawaited(_syncDanmaku())));
    }
    await _reloadFilter();
    await _guard(() async {
      _showGifts = await store.meta.get(showGiftsKey) != '0';
    }, 'gift switch');
    if (sleepSessionOnStart) {
      _audioOnly = true;
      _sleepSession = true;
      setSleepTimer(enabled: true, minutes: store.settings.get(Settings.asmrSleepMinutes));
    }
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
    _startWhenBack = false;
    _stage = RoomStage.loading;
    _failure = null;
    _catchup = null;
    _notify();
    final requested = _room.catchUp.isActive ? _room.withoutCatchUp() : _room;
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
    _chatConnection = ChatConnection.idle;
    unawaited(danmaku.close());
    _clearSuperChats();
    if (session.state.status != PlaybackStatus.idle) await session.stop();
  }

  /// The preferred quality name for the network now.
  Future<String> _preferredQuality() async {
    final kind = await network?.call() ?? NetworkKind.other;
    final setting = kind == NetworkKind.mobile ? Settings.preferResolutionCellular : Settings.preferResolution;
    return store.settings.get<String>(setting);
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
    final kept = previous == null ? -1 : found.indexWhere((q) => q.selectionId == previous.selectionId);
    final preferred = kept >= 0 ? null : await _preferredQuality();
    if (!_current(epoch)) return;
    _qualities = found;
    _qualityIndex = kept >= 0
        ? kept
        : defaultQualityIndex(found, preferred!, preferH264: store.settings.get<bool>(Settings.preferH264));
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
    // U.2g c11: the room is on air, so its danmaku and super chats show
    // while the picture says why it cannot play (3.x connected them too and
    // hid them).
    if (_room.isLiveNow) {
      unawaited(_syncDanmaku(force: true));
      unawaited(_loadSuperChats(_epoch));
    }
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
    // A LAN source (a home IPTV server) needs Android 17's local-network
    // permission first; refused, the user is told and the open fails as usual.
    await ensureLocalNetworkFor(resolution.lines.map((line) => line.url), toast: toast);
    if (!_current(epoch)) return false;
    // C01.4: a confirmed tier the list does not have (a Bilibili guest in a
    // room listed as 原画 only, served 250) is named by the platform, as the
    // recorder names it, and takes the requested entry's place.
    final applied = resolveServedPlayQuality(
      platform: site.id,
      qualities: _qualities,
      requested: requested,
      resolution: resolution,
    );
    final appliedIndex = _qualities.indexWhere((q) => q.selectionId == applied.selectionId);
    final playing = appliedIndex >= 0 ? appliedIndex : index;
    if (applied.selectionId != requested.selectionId && (userChoice || !_servedToastShown)) {
      if (!userChoice) _servedToastShown = true;
      toast?.call(i18n('quality_limited_to', args: {'quality': applied.quality}));
    }
    _qualities = List.unmodifiable(List.of(_qualities)..[playing] = applied);
    _qualityIndex = playing;
    _stage = RoomStage.playing;
    _failure = null;
    _notify();
    final quality = _qualities[playing];
    await session.open(
      PlaybackRequest(
        site: site.id,
        plan: _plan(resolution),
        refresh: () => _refreshPlan(quality),
        audioOnly: _audioOnly,
        volume: _volume(),
      ),
    );
    return _current(epoch);
  }

  PlaybackPlan _plan(LivePlayUrlResolution resolution) => PlaybackPlan.of(
    site.id == SiteIds.iptv ? _withIptvHeaders(resolution) : resolution,
    preferH264: store.settings.get(Settings.preferH264),
    onDemand: _room.isRecord,
  );

  /// IPTV lines with the user's agent (`customIptvUserAgent`) under the
  /// playlist's own headers (3.x `PlaybackHeaderResolver`: the channel's
  /// `http-user-agent` wins over the setting).
  LivePlayUrlResolution _withIptvHeaders(LivePlayUrlResolution resolution) {
    if (resolution.inputRecipe != null) return resolution;
    return LivePlayUrlResolution.lines(
      [for (final line in resolution.lines) _iptvLine(line.url, line: line)],
      appliedQualityData: resolution.appliedQualityData,
      qualityUnconfirmed: resolution.qualityUnconfirmed,
    );
  }

  LivePlayLine _iptvLine(String url, {LivePlayLine? line}) => LivePlayLine(
    url,
    headers: iptvPlayHeaders(
      userAgent: store.settings.get(Settings.customIptvUserAgent),
      room: _room.httpHeaders,
      line: line?.headers ?? const {},
    ),
    format: line?.format,
    codec: line?.codec,
    lineId: line?.lineId,
    lease: line?.lease,
  );

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

  /// The player's volume, 0 to 1.
  double get volume => session.state.volume;

  /// Sets the player's volume; [save] keeps it as this room's volume (3.x
  /// `LiveRoomVolumeManager`, the `roomVolumes` setting).
  Future<void> setVolume(double value, {bool save = false}) async {
    final volume = value.isFinite ? value.clamp(0.0, 1.0) : 1.0;
    await session.setVolume(volume);
    _notify();
    if (save) await saveVolume();
  }

  /// Keeps the current volume as this room's.
  Future<void> saveVolume() => _guard(() async {
    final settings = store.settings;
    final saved = Map<String, Object?>.of(settings.get(Settings.roomVolumes));
    saved[roomVolumeKey(_room.platform, _room.roomId)] = double.parse(volume.toStringAsFixed(2));
    await settings.set(Settings.roomVolumes, saved);
  }, 'room volume');

  /// Turns video off or on (3.x's headphone button); the stream stays.
  Future<void> setAudioOnly({required bool enabled}) async {
    if (_audioOnly == enabled) return;
    _audioOnly = enabled;
    if (!enabled && _sleepSession) {
      // Back to video ends the automatic sleep session (3.x).
      _sleepSession = false;
      setSleepTimer(enabled: false, minutes: _sleepMinutes);
    }
    _notify();
    await session.setAudioOnly(enabled: enabled);
  }

  /// Shows or hides gifts in the chat list and remembers the choice.
  Future<void> setShowGifts({required bool show}) async {
    if (_showGifts == show) return;
    _showGifts = show;
    if (!show) chat.removeWhere((line) => line.kind == ChatLineKind.gift);
    _notify();
    await _guard(() => store.meta.set(showGiftsKey, show ? '1' : '0'), 'gift switch');
  }

  /// Starts (or restarts) the sleep timer for [minutes], or stops it (3.x
  /// `applyRoomPlaybackTimer`): when it ends the room pauses.
  void setSleepTimer({required bool enabled, required int minutes}) {
    _sleepMinutes = minutes.clamp(1, 525600);
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepDeadline = null;
    if (enabled && !_disposed) {
      final length = minuteLength * _sleepMinutes;
      _sleepDeadline = _now().add(length);
      _sleepTimer = Timer(length, _sleepEnded);
    } else {
      _sleepSession = false;
    }
    _notify();
  }

  void _sleepEnded() {
    _sleepTimer = null;
    _sleepDeadline = null;
    _sleepSession = false;
    unawaited(session.pause());
    toast?.call(i18n('room_playback_timer_finished'));
    _notify();
  }

  // ---- IPTV catch-up ----

  /// Replays [programme] of this IPTV channel (3.x `playCatchup`); returns
  /// the text key of the reason when it cannot, null when it plays.
  Future<String?> playCatchup(EpgProgramme programme) async {
    if (site.id != SiteIds.iptv || _stage != RoomStage.playing) return 'catchup_unavailable';
    final now = _now();
    final phase = classifyIptvProgramme(start: programme.start, stop: programme.stop, now: now);
    if (phase == IptvProgrammePhase.scheduled) return 'program_scheduled_hint';
    if (phase == IptvProgrammePhase.live) {
      await backToLive();
      return null;
    }
    final catchUp = _room.catchUp;
    final availability = evaluateIptvCatchupAvailability(
      programmeStop: programme.stop,
      now: now,
      mode: catchUp.mode,
      source: catchUp.source,
      days: catchUp.days,
    );
    if (availability != IptvCatchupAvailability.available) return 'catchup_unavailable';
    final live = (_room.link ?? _room.data?.toString() ?? '').trim();
    final String url;
    try {
      url = buildIptvCatchupUrl(
        originalUrl: live,
        start: programme.start,
        stop: programme.stop,
        type: CatchupUrlType.playseek,
        now: now,
        mode: catchUp.mode,
        source: catchUp.source,
        correctionHours: catchUp.correctionHours,
      );
    } on Object {
      return 'invalid_play_url';
    }
    final epoch = _epoch;
    _catchup = programme;
    _room = _room.copyWith(
      catchUp: CatchUp(
        url: url,
        active: true,
        start: programme.start.millisecondsSinceEpoch,
        end: programme.stop.millisecondsSinceEpoch,
        mode: catchUp.mode,
        source: catchUp.source,
        days: catchUp.days,
        correctionHours: catchUp.correctionHours,
      ),
    );
    _notify();
    await ensureLocalNetworkFor([url], toast: toast);
    if (!_current(epoch)) return 'play_video_failed';
    await session.open(
      PlaybackRequest(
        site: site.id,
        plan: PlaybackPlan.of(LivePlayUrlResolution.lines([_iptvLine(url)]), onDemand: true),
        audioOnly: _audioOnly,
        volume: _volume(),
      ),
    );
    return _current(epoch) ? null : 'play_video_failed';
  }

  /// Leaves the replay for the live channel (3.x `returnToLive`).
  Future<void> backToLive() async {
    if (_catchup == null) return;
    _catchup = null;
    _room = _room.withoutCatchUp();
    _notify();
    await _startStream(_epoch);
  }

  /// Plays quality [index] (3.x `setResolution(changeQuality)`); the old
  /// stream keeps playing until the new one resolves.
  Future<void> selectQuality(int index) async {
    if (_switching || _switchingLine || index < 0 || index >= _qualities.length || index == _qualityIndex) return;
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

  /// Plays line [index] of the current quality; the old line plays until
  /// the new one opens.
  Future<void> selectLine(int index) async {
    if (_switching || _switchingLine) return;
    _switchingLine = true;
    _notify();
    try {
      await session.selectLine(index);
    } finally {
      _switchingLine = false;
      _notify();
    }
  }

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
    // A room that came on air starts playing (U.2g c8); a failed stream of a
    // broadcast that ended is reloaded. A room on air whose stream is
    // withheld keeps its danmaku; it is tried again by "重试".
    final reload =
        (!playing && _stage != RoomStage.unplayable && fetched.isPlayableNow) ||
        (playing && !fetched.isPlayableNow && session.state.status == PlaybackStatus.error);
    if (reload && (mayAutoStart?.call() ?? true)) {
      await load();
      return;
    }
    // Away from the app: only the state is updated; the start waits.
    if (reload) _startWhenBack = true;
    _room = _room.mergeFrom(fetched).withAudienceFallbackFrom(_room);
    _notify();
    if (playing && !reload && danmaku.status == DanmakuStatus.closed) unawaited(_syncDanmaku(force: true));
  }

  /// A followed room's card gets the fresh detail (3.x
  /// `_updateFavoriteRoomSnapshot`); rooms not followed are untouched.
  Future<void> _saveFollowSnapshot() => _guard(() => store.follows.update([_room]), 'follow snapshot');

  Future<void> _guard(Future<void> Function() action, String what) async {
    try {
      await action();
    } on Object catch (error, stackTrace) {
      developer.log('Saving $what failed', name: 'LivePlay', error: error, stackTrace: stackTrace);
    }
  }

  // ---- danmaku ----

  bool get _wantsDanmaku =>
      store.settings.get(Settings.enableDanmakuDisplay) || store.settings.get(Settings.enablePipDanmaku);

  /// The room has a stream, or is on air and only its stream is withheld
  /// (U.2g c11): its danmaku connects.
  bool get _danmakuStage => _stage == RoomStage.playing || (_stage == RoomStage.unplayable && _room.isLiveNow);

  Future<void> _syncDanmaku({bool force = false}) async {
    if (_disposed) return;
    if (!_danmakuStage || !_wantsDanmaku || site.id == SiteIds.iptv) {
      _setChat(ChatConnection.idle);
      await danmaku.close();
      return;
    }
    if (!danmakuSupported) {
      _setChat(ChatConnection.unsupported);
      if (!_unsupportedShown) {
        _unsupportedShown = true;
        _system(i18n('live_play_danmaku_unsupported'));
      }
      return;
    }
    if (!force && danmaku.status != DanmakuStatus.idle && danmaku.status != DanmakuStatus.closed) return;
    final epoch = ++_danmakuEpoch;
    _maskedChats = 0;
    _namedChats = 0;
    _setChat(ChatConnection.connecting);
    if (_room.isRecord) _system(i18n('recording_mode_notice'));
    _system(i18n('connect_danmaku_server'));
    try {
      await danmaku.connect(_room.danmakuData).timeout(danmakuStartTimeout);
      if (epoch == _danmakuEpoch && !_disposed && danmaku.isConnected) _setChat(ChatConnection.connected);
    } on TimeoutException {
      if (epoch != _danmakuEpoch || _disposed) return;
      await danmaku.close();
      _setChat(ChatConnection.timedOut);
      _system(i18n('danmaku_connection_timeout'));
    } on Object catch (error, stackTrace) {
      if (epoch != _danmakuEpoch || _disposed) return;
      developer.log('Danmaku start failed', name: 'LivePlay', error: error, stackTrace: stackTrace);
      await danmaku.close();
      _setChat(ChatConnection.failed);
      _system(i18n('live_play_danmaku_connect_failed'));
    }
  }

  void _onDanmaku(DanmakuEvent event) {
    if (_disposed) return;
    switch (event) {
      case DanmakuReady():
        _setChat(ChatConnection.connected);
        _system(i18n('danmaku_connected'));
      case DanmakuReceived(:final message):
        _onMessage(message);
      case DanmakuReconnecting(:final reason):
        _setChat(ChatConnection.connecting);
        _system(interruptionText(reason));
      case DanmakuClosed(:final reason):
        _setChat(ChatConnection.failed);
        _system(closeText(reason));
    }
  }

  /// A message from the platform. Chat, notices, gifts and retractions only
  /// change [chat], which tells the list itself (B08); the room's listeners
  /// hear of what they show: the super chats and [nameHint].
  void _onMessage(LiveMessage message) {
    switch (message.type) {
      case LiveMessageType.chat:
        // B06: the names tell whether this connection is a guest's
        // ([nameHint]); 3.x added a system line here every connection.
        if (_room.platform == SiteIds.bilibili && message.userName.trim().isNotEmpty) {
          final masked = BilibiliDanmakuProtocol.isMaskedName(message.userName);
          if (masked) {
            _maskedChats++;
          } else {
            _namedChats++;
          }
          // The hint turns at the last masked name it waits for, or at the
          // first full name after them.
          if (masked
              ? _maskedChats == maskedChatsForExpiredLogin && _namedChats == 0
              : _namedChats == 1 && _maskedChats >= maskedChatsForExpiredLogin) {
            _notify();
          }
        }
        if (!_filter.accepts(message)) return;
        chat.add(ChatLine.chat(message));
        _flying.add(message);
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
        }
      case LiveMessageType.notice:
        if (message.message.trim().isEmpty || !_notices.accepts(message.message)) return;
        chat.add(ChatLine.notice(message));
      case LiveMessageType.gift:
        // B-21: a line in the chat list, not on the video; the switch hides them.
        if (!_showGifts || message.message.trim().isEmpty) return;
        chat.add(ChatLine.gift(message));
    }
  }

  /// A message composed on this device (the local interaction, U.2k): a line
  /// in the chat list at once, and over the picture when [fly]. It skips the
  /// platform filters and the gift switch, as 3.x's local messages did; the
  /// list shows it without waiting for the next frame.
  void addLocal(LiveMessage message, {required bool fly}) {
    if (_disposed || message.message.trim().isEmpty) return;
    chat.add(message.type == LiveMessageType.gift ? ChatLine.gift(message) : ChatLine.chat(message));
    if (fly) _flying.add(message);
    chat.flush();
  }

  void _system(String text) {
    if (!_statusLines.accepts(text)) return;
    chat.add(ChatLine.system(text));
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

  /// Blocks messages containing [keyword] from now on and takes the matching
  /// ones off the list (3.x `DanmakuMessageActions.showKeywordDialog`).
  /// Returns whether the word was new.
  Future<bool> blockKeyword(String keyword) async {
    final word = keyword.trim();
    if (word.isEmpty) return false;
    final added = await store.blockLists.add(BlockKind.keyword, word);
    final lower = word.toLowerCase();
    chat.removeWhere((line) => line.kind == ChatLineKind.chat && line.text.toLowerCase().contains(lower));
    _notify();
    return added;
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _refreshTimer?.cancel();
    _superChatTimer?.cancel();
    _sleepTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_qualityScope.close());
    unawaited(danmaku.close());
    unawaited(_flying.close());
    unawaited(_retractions.close());
    chat.dispose();
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

/// The headers of an IPTV stream: the user's agent ([userAgent], the
/// `customIptvUserAgent` setting) under the channel's playlist headers
/// ([room]) and the line's own ([line]); 3.x `PlaybackHeaderResolver`.
Map<String, String> iptvPlayHeaders({
  required String userAgent,
  Map<String, String> room = const {},
  Map<String, String> line = const {},
}) {
  final headers = <String, String>{};
  final agent = userAgent.trim();
  if (agent.isNotEmpty) headers['user-agent'] = agent;
  for (final entry in [...room.entries, ...line.entries]) {
    headers
      ..removeWhere((key, _) => key.toLowerCase() == entry.key.toLowerCase())
      ..[entry.key] = entry.value;
  }
  return headers;
}
