import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/app_log.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/logic/blocked_count.dart';
import 'package:pure_live/features/live_play/logic/gift_combiner.dart';
import 'package:pure_live/features/live_play/logic/membership_cards.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/system_access.dart';
import 'package:pure_live/shared/danmaku/emotes.dart';
import 'package:pure_live/shared/danmaku/gift_flights.dart';
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
    this.emotes,
    DateTime Function()? now,
    this.refreshInterval = const Duration(seconds: 60),
    this.danmakuStartTimeout = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now {
    _filter = DanmakuMessageFilter(clock: _now)..shapeOf = chatTextShaper(emotes, _room.platform);
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

  /// The bundled emoticon lists: "屏蔽只有表情的弹幕" and "屏蔽超长弹幕" read
  /// a message as the chat list draws it (D02.2 c3); null knows only the
  /// codes a message names and Unicode emoji.
  final EmoteLibrary? emotes;

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
  /// frame (B08: the controller no longer notifies for each message); at
  /// most [GiftCombiner.maxGiftLines] of its lines are gifts (D07.1).
  final ChatFeed chat = ChatFeed(giftCapacity: GiftCombiner.maxGiftLines);

  /// Merges and limits the platform's gifts into [chat] (D07.1).
  late final GiftCombiner _gifts = GiftCombiner(feed: chat, clock: _now);

  /// The gifts that fly over the picture ("飞行弹幕显示礼物", A08.12).
  late final GiftFlights _giftFlights = GiftFlights(
    clock: _now,
    emit: (message) {
      if (!_disposed && flyGifts) _flying.add(message);
    },
    streamer: () => _room.nick,
  );

  /// The messages of this room the user's blocks hid ("本场已屏蔽 N 条",
  /// D02.2 c4).
  final BlockedCount blocked = BlockedCount();
  final StreamController<LiveMessage> _flying = StreamController.broadcast(sync: true);
  final StreamController<LiveRetraction> _retractions = StreamController.broadcast(sync: true);
  final List<StreamSubscription<Object?>> _subscriptions = [];
  LiveQualityDiscoveryScope _qualityScope = LiveQualityDiscoveryScope();
  Timer? _refreshTimer;
  Timer? _superChatTimer;
  int _epoch = 0;
  int _danmakuEpoch = 0;

  /// A refresh while playing found the room off air (C01.6): on air again
  /// is a new broadcast.
  bool _sawOffline = false;

  /// The stream open is the platform's carousel video ([playCarousel]), not
  /// a broadcast; a load forgets it.
  bool _carousel = false;
  bool _disposed = false;
  int _maskedChats = 0;
  int _namedChats = 0;
  bool _unsupportedShown = false;
  bool _historyRecorded = false;
  // C01.4: entering the room says once that the platform served another
  // tier; a refresh or a reload does not say it again.
  bool _servedToastShown = false;
  int _loggedRecovery = 0;

  /// Counts the streams handed to the session: a recovery of an older one
  /// no longer names the quality shown ([_refreshPlan]).
  int _opens = 0;

  /// G03.1: the start-up marks of entering the room (T0 is this
  /// controller's creation: the page's `initState`, or the release of a
  /// swipe); only the first load's open is timed, so a refresh, a retry or
  /// a quality switch writes no timing line. Null once handed to the
  /// session or once the first load did not open a stream.
  StartupMarks? _startup = StartupMarks();

  /// The epoch of the first load, the one [_startup] times.
  int? _startupEpoch;

  LiveRoom _room;
  RoomStage _stage = RoomStage.loading;
  Object? _failure;
  List<LivePlayQuality> _qualities = const [];
  int _qualityIndex = 0;
  bool _switching = false;
  bool _switchingLine = false;
  List<LiveSuperChatMessage> _superChats = const [];
  bool _audioOnly = false;
  Timer? _sleepTimer;
  DateTime? _sleepDeadline;
  int _sleepMinutes = 60;
  bool _sleepSession = false;
  EpgProgramme? _catchup;
  ChatConnection _chatConnection = ChatConnection.idle;

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

  /// Gifts appear in the chat list (B-21): the `showChatGifts` setting
  /// (A08.6 c3; the room kept it in `meta` before).
  bool get showGifts => store.settings.get(Settings.showChatGifts);

  /// The platform's valuable gifts fly over the picture (A08.12: the
  /// `danmakuShowGifts` setting, whether or not the list shows gifts).
  bool get flyGifts => store.settings.get(Settings.danmakuShowGifts);

  /// Memberships and subscriptions are also cards among the super chats
  /// (D07.2: the `superChatIncludesMembership` setting, "上舰和开会员进醒目留言").
  bool get membershipCards => store.settings.get(Settings.superChatIncludesMembership);

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
    await _renewDanmaku('a login change');
  }

  /// Fresh danmaku arguments from the room entry (`getRoomDetail`; most
  /// platforms' light refresh has none), then the danmaku again: after a
  /// login change (B06 c1), a new broadcast, or a connection that ended
  /// (C01.6). A failed fetch reconnects with the arguments the room has.
  Future<void> _renewDanmaku(String why) async {
    if (!_danmakuStage || !_wantsDanmaku) return;
    final epoch = _epoch;
    if (danmakuSupported && site.id != SiteIds.iptv) {
      try {
        final fetched = await site.getRoomDetail(roomId: _room.roomId);
        if (!_current(epoch)) return;
        if (fetched.danmakuData case final Object data) _room = _room.copyWith(danmakuData: data);
      } on Object catch (error) {
        // The connection still renews a missing token itself.
        developer.log('Danmaku arguments after $why failed', name: 'LivePlay', error: error);
        if (!_current(epoch)) return;
      }
    }
    await _syncDanmaku(force: true);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// B-7: "Twitch 的 Cookie 已失效，已改为匿名观看…" (Twitch is the one
  /// platform that reports a refused cookie).
  void _onCookieRefused() {
    if (!_disposed) toast?.call(i18n('twitch_cookie_expired'));
  }

  /// G02.2: one app log line per recovery attempt of the session, with its
  /// count and the failure's code (no address, no headers), also on logcat:
  /// `playback: recovering #2 buffering_stall_timeout`.
  void _logRecovery(PlaybackState state) {
    final attempt = state.recovery;
    if (attempt > _loggedRecovery) {
      final line = 'recovering #$attempt ${state.recoveryCause ?? '-'}';
      AppLog.instance.info('playback', line);
      debugPrint('playback: $line');
    }
    _loggedRecovery = attempt;
  }

  /// G03.1: one app log line per timed open (the room's entry), also on
  /// logcat (`adb logcat -s flutter | grep playback-timing`):
  /// `playback-timing site=bilibili room=1a2b3c route=direct engine=new
  /// result=playing detail=312 qualities=0 urls=405 engineReady=180 input=2
  /// load=96 firstFrame=640 playing=702 total=1697`.
  void _logTiming(PlaybackTiming timing) {
    final line = timing.line(room: roomTag(_room.platform, _room.roomId));
    AppLog.instance.info('playback', line);
    debugPrint(line);
  }

  /// A short tag of a room for the timing line (no room number in the log):
  /// the first six hex digits of the 32-bit FNV-1a hash of
  /// `platform:roomId`.
  @visibleForTesting
  static String roomTag(String platform, String roomId) {
    var hash = 0x811c9dc5;
    for (final unit in '$platform:$roomId'.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0').substring(0, 6);
  }

  /// The start-up marks for an open of [epoch], handed over once.
  StartupMarks? _takeStartup(int epoch) {
    if (epoch != _startupEpoch) return null;
    final startup = _startup;
    _startup = null;
    return startup;
  }

  /// Subscribes to the session's recoveries, danmaku and settings, loads
  /// the room and starts the periodic refresh.
  Future<void> start() async {
    _subscriptions
      ..add(session.states.listen(_logRecovery))
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
    // A08.6 c3: the settings page changes it for the rooms already open.
    _subscriptions.add(store.settings.watch(Settings.showChatGifts).skip(1).listen(_onShowGifts));
    // A08.12: "只显示值钱的礼物" takes the cheap gift lines away at once.
    _subscriptions.add(store.settings.watch(Settings.chatGiftsAboveTier).skip(1).listen(_onGiftTier));
    _subscriptions.add(store.settings.watch(Settings.superChatIncludesMembership).skip(1).listen(_onMembershipCards));
    // B-7 (E06.2 c4): the platform refused the stored cookie and plays on
    // anonymously; it reports each cookie once, and the room says so.
    if (site case final LiveSiteCookieRefusals refusals) {
      _subscriptions.add(refusals.cookieRefusals.listen((_) => _onCookieRefused()));
    }
    // YouTube's connection reads "show all chat" when it starts (C01.6).
    if (site.id == SiteIds.youtube) {
      _subscriptions.add(
        store.settings.watch(Settings.youtubeShowAllChat).skip(1).listen((_) => unawaited(_syncDanmaku(force: true))),
      );
    }
    await _reloadFilter();
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
    Settings.blockEmoteOnlyDanmaku,
    Settings.blockLongDanmaku,
    Settings.blockLongDanmakuLength,
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
      blockEmoteOnly: settings.get(Settings.blockEmoteOnlyDanmaku),
      blockLong: settings.get(Settings.blockLongDanmaku),
      blockLongLength: settings.get(Settings.blockLongDanmakuLength),
    );
  }

  /// Fetches the room detail and plays it when it is on air (3.x
  /// `onInitPlayerState`). Also the "refresh room" action and the retry
  /// after a failed detail.
  Future<void> load() async {
    if (_disposed) return;
    final epoch = ++_epoch;
    // G03.1: only the first load is the room's entry.
    if (_startupEpoch == null) {
      _startupEpoch = epoch;
    } else {
      _startup = null;
    }
    _startWhenBack = false;
    _sawOffline = false;
    _carousel = false;
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
      _startup = null;
      await _stopStream();
      _notify();
      return;
    }
    if (!_current(epoch)) return;
    _startup?.markDetail();
    _room = fetched.withAudienceFallbackFrom(requested).fillFromDetail(requested);
    _notify();
    unawaited(_saveFollowSnapshot());
    if (!_room.isPlayableNow) {
      _stage = RoomStage.offline;
      _startup = null;
      await _stopStream();
      _notify();
      return;
    }
    await _startStream(epoch);
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;

  /// The carousel video plays ([playCarousel]): the room is still not on
  /// air.
  bool get playingCarousel => _carousel && _stage == RoomStage.playing;

  /// The picture's "播放轮播" (E06.2 c1, UPGRADES 1-1; 3.x could not play a
  /// carousel): a room the platform loops old videos in plays the one in
  /// rotation from the platform's `play_time` ([LivePlayUrlResolution.start]).
  /// The room stays offline in the model ([LiveRoom.isPlayableNow]), so
  /// follows and recording are untouched; the video's end is no replay's
  /// end (`onDemand` stays false): recovery asks again and gets the next
  /// video. A refresh that finds the broadcast on air loads it instead.
  Future<void> playCarousel() async {
    if (_disposed || _stage != RoomStage.offline || !carouselPlayable(_room)) return;
    final epoch = ++_epoch;
    _startup = null;
    _carousel = true;
    // As a room entry: "正在进入直播间…" while the qualities and the video
    // are fetched.
    _stage = RoomStage.loading;
    _failure = null;
    _notify();
    await _startStream(epoch);
  }

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
    _startup?.markQualities();
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
    _startup = null;
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
    if (!userChoice) _startup?.markUrls();
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
    final opened = ++_opens;
    _stage = RoomStage.playing;
    _failure = null;
    _notify();
    final quality = _qualities[playing];
    final startup = userChoice ? null : _takeStartup(epoch);
    await session.open(
      PlaybackRequest(
        site: site.id,
        plan: _plan(resolution),
        refresh: () => _refreshPlan(opened, quality),
        audioOnly: _audioOnly,
        volume: _volume(),
        startup: startup,
        onTiming: startup == null ? null : _logTiming,
      ),
    );
    return _current(epoch);
  }

  /// The plan of [resolution]; a carousel video starts where the platform's
  /// loop is (1-1: `play_time`), also after a recovery took the next one.
  PlaybackPlan _plan(LivePlayUrlResolution resolution) => PlaybackPlan.of(
    site.id == SiteIds.iptv ? _withIptvHeaders(resolution) : resolution,
    preferH264: store.settings.get(Settings.preferH264),
    onDemand: _room.isRecord,
    start: resolution.start,
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

  /// The plan of a recovery (or a lease renewal) of open [opened], which
  /// played [quality]: the quality shown now is asked for again, and the
  /// tier the platform answers with is what the quality button names
  /// ([_showServed]).
  Future<PlaybackPlan> _refreshPlan(int opened, LivePlayQuality quality) async {
    bool current() => !_disposed && opened == _opens && _stage == RoomStage.playing;
    final requested = current() ? _qualities[_qualityIndex] : quality;
    final resolution = await site.resolvePlayUrlsForRecovery(detail: _room, quality: requested);
    if (current()) _showServed(requested, resolution);
    return _plan(resolution);
  }

  /// UPGRADES 11-1 (E06.2 c5): a recovery the platform answered with
  /// another tier (Picarto's streamer changed the profile, 720p60 →
  /// 1080p60) names the tier now played, by C01.4's rule
  /// ([resolveServedPlayQuality]: a tier outside the list takes the
  /// requested entry's place). No toast: C01.4 says it on entering and on
  /// the user's own choice only. 3.x kept the old name.
  void _showServed(LivePlayQuality requested, LivePlayUrlResolution resolution) {
    final served = resolveServedPlayQuality(
      platform: site.id,
      qualities: _qualities,
      requested: requested,
      resolution: resolution,
    );
    final found = _qualities.indexWhere((q) => q.selectionId == served.selectionId);
    final at = found >= 0 ? found : _qualityIndex;
    final shown = _qualities[at];
    if (at == _qualityIndex &&
        shown.quality == served.quality &&
        '${shown.selectionId}' == '${served.selectionId}' &&
        shown.isPlaybackUnconfirmed == served.isPlaybackUnconfirmed) {
      return;
    }
    _qualities = List.unmodifiable(List.of(_qualities)..[at] = served);
    _qualityIndex = at;
    _notify();
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

  /// Shows or hides gifts in the chat list of every room (the setting).
  Future<void> setShowGifts({required bool show}) async {
    if (showGifts == show) return;
    await _guard(() => store.settings.set(Settings.showChatGifts, show), 'gift switch');
    // At once for this room; the others hear it from the setting.
    _onShowGifts(show);
  }

  void _onShowGifts(bool show) {
    if (_disposed) return;
    if (!show) {
      chat.removeWhere((line) => line.kind == ChatLineKind.gift);
      _gifts.clear();
    }
    _notify();
  }

  /// A08.12: on, the platform's gift lines below "值钱" go (local gifts
  /// stay); off, the next gifts show whatever they are worth.
  void _onGiftTier(bool valuableOnly) {
    if (_disposed || !valuableOnly) return;
    chat.removeWhere(
      (line) =>
          line.kind == ChatLineKind.gift &&
          !(line.message?.isLocal ?? true) &&
          (line.message?.gift?.tier ?? LiveGiftTier.normal) == LiveGiftTier.normal,
    );
  }

  /// D07.2: off, the membership cards leave the super chats at once (the
  /// lines in the chat list stay); on, the next memberships get one.
  void _onMembershipCards(bool on) {
    if (_disposed || on || !_superChats.any(isMembershipCard)) return;
    _superChats = List.unmodifiable(_superChats.where((superChat) => !isMembershipCard(superChat)));
    _scheduleSuperChatExpiry();
    _notify();
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
    // withheld keeps its danmaku; it is tried again by "重试". A carousel
    // video gives way to the broadcast when the streamer comes on air.
    final reload =
        (!playing && _stage != RoomStage.unplayable && fetched.isPlayableNow) ||
        (playing && !fetched.isPlayableNow && session.state.status == PlaybackStatus.error) ||
        (playing && _carousel && fetched.isPlayableNow);
    if (reload && (mayAutoStart?.call() ?? true)) {
      await load();
      return;
    }
    // Away from the app: only the state is updated; the start waits.
    if (reload) _startWhenBack = true;
    // A new broadcast while the session went on (C01.6): its danmaku
    // arguments may have changed, and the old connection may not end
    // (SHOWROOM, Kilakila, TwitCasting keep it open).
    final newBroadcast = playing && !reload && _isNewBroadcast(fetched);
    if (playing && !reload) _sawOffline = !fetched.isPlayableNow;
    _room = _room.mergeFrom(fetched).withAudienceFallbackFrom(_room);
    _notify();
    if (!playing || reload) return;
    if (newBroadcast) {
      unawaited(_renewDanmaku('a new broadcast'));
    } else if (danmaku.status == DanmakuStatus.closed) {
      // A refresh with arguments was merged in; one without asks the entry.
      unawaited(fetched.danmakuData == null ? _renewDanmaku('a closed connection') : _syncDanmaku(force: true));
    }
  }

  /// How far apart two starts of the same broadcast may be: some platforms
  /// count back from the time on air (SOOP's `BTIME`, Kugou's list).
  static const Duration _startJitter = Duration(minutes: 2);

  /// Whether [fetched] is another broadcast than the one playing: its start
  /// moved, or the room is on air again after a refresh found it off.
  bool _isNewBroadcast(LiveRoom fetched) {
    if (!fetched.isPlayableNow) return false;
    if (_sawOffline) return true;
    final before = _room.startedAt;
    final after = fetched.startedAt;
    return before != null && after != null && after.difference(before).abs() > _startJitter;
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
  /// (U.2g c11), and the platform gave danmaku arguments: its danmaku
  /// connects. A room without arguments (an AcFun paid show) stays idle
  /// instead of failing the connection (E05.4), as multi-view does.
  bool get _danmakuStage =>
      (_stage == RoomStage.playing || (_stage == RoomStage.unplayable && _room.isLiveNow)) && _room.danmakuData != null;

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
        switch (_filter.judge(message)) {
          case DanmakuVerdict.shown:
            break;
          case DanmakuVerdict.blocked:
            blocked.add();
            return;
          case DanmakuVerdict.duplicate || DanmakuVerdict.repeated || DanmakuVerdict.similar:
            return;
        }
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
        // D07.2: a subscription's notice stays the list's one line; with
        // "上舰和开会员进醒目留言" it is a card among the super chats too.
        _addMembershipCard(message);
      case LiveMessageType.gift:
        // B-21: a line in the chat list, not on the video; the switch hides
        // them, and then nothing is filtered or merged (D07.1 c5). D07.1:
        // blocked viewers and words and the duplicate gate apply; a combo is
        // one line, and the lines are limited. A08.12: the valuable ones fly
        // too with "飞行弹幕显示礼物", which does not need the list's switch.
        final list = showGifts;
        final fly = flyGifts;
        // D07.2: a guard or another membership is also a card among the
        // super chats (its own switch, whatever the list shows); the list
        // keeps the gift line, so the event is one line there, never a gift
        // line and a super chat line.
        final card = membershipCards && _isMembership(message.gift);
        if ((!list && !fly && !card) || message.message.trim().isEmpty) return;
        switch (_filter.judge(message)) {
          case DanmakuVerdict.shown:
            break;
          case DanmakuVerdict.blocked:
            // A blocked gift counts too ("本场已屏蔽 N 条", D02.2 c4).
            blocked.add();
            return;
          case DanmakuVerdict.duplicate || DanmakuVerdict.repeated || DanmakuVerdict.similar:
            return;
        }
        if (card) _addMembershipCard(message);
        if (list) {
          _gifts.minTier = store.settings.get(Settings.chatGiftsAboveTier)
              ? LiveGiftTier.valuable
              : LiveGiftTier.normal;
          _gifts.add(message);
        }
        if (fly) _giftFlights.add(message);
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

  bool _localReplayed = false;

  /// Local danmaku sent here before the room was entered (D08.1 c6),
  /// oldest first: at the top of the chat list, not over the picture, not
  /// counted as new and past the platform filters, as [addLocal]. Once per
  /// controller: a room handed back by the floating window has them already.
  void replayLocal(List<LiveMessage> messages) {
    if (_disposed || _localReplayed) return;
    _localReplayed = true;
    chat
      ..addOldest([
        for (final message in messages)
          if (message.message.trim().isNotEmpty) ChatLine.chat(message),
      ])
      ..flush();
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

  static bool _isMembership(LiveGift? gift) =>
      gift != null && (gift.kind == LiveGiftKind.membership || gift.kind == LiveGiftKind.subscription);

  /// D07.2: [message]'s card among the super chats ([membershipCard]) while
  /// "上舰和开会员进醒目留言" is on; nothing for other messages.
  void _addMembershipCard(LiveMessage message) {
    if (!membershipCards) return;
    final card = membershipCard(message, platform: _room.platform, now: _now());
    if (card == null) return;
    _addSuperChats([card]);
    _notify();
  }

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
  /// ones off the list (3.x `DanmakuMessageActions.showKeywordDialog`); a
  /// `/…/` word matches as a pattern ([DanmakuBlockPattern], D02.2), checked
  /// by the field before. Returns whether the word was new.
  Future<bool> blockKeyword(String keyword) async {
    final word = keyword.trim();
    if (word.isEmpty) return false;
    final added = await store.blockLists.add(BlockKind.keyword, word);
    final matcher = DanmakuBlockList(keywords: [word]);
    // D07.1: blocked words block the platform's gifts too.
    bool blockable(ChatLine line) =>
        line.kind == ChatLineKind.chat || (line.kind == ChatLineKind.gift && !(line.message?.isLocal ?? true));
    chat.removeWhere((line) => blockable(line) && matcher.matchesText(line.text));
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
    _giftFlights.dispose();
    unawaited(_flying.close());
    unawaited(_retractions.close());
    chat.dispose();
    blocked.dispose();
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
