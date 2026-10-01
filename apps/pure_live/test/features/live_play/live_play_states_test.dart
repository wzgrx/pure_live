// The live room's states of U.2g (docs/ui/compare/U.2g/README.md): one
// picture state for every case, its words and buttons in order, no bars
// while nothing plays, and the IPTV guide in place of the chat.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/dialogs/iptv_guide.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/iptv_guide_rows.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/logic/room_status.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import 'live_play_support.dart';

/// A platform whose detail waits for [gate] (the room loading).
class _SlowSite extends FakeSite {
  new(super.room);

  final Completer<void> gate = Completer();

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    await gate.future;
    return await super.getRoomDetail(roomId: roomId);
  }
}

/// An IPTV channel (the platform id is what matters to the page).
class _ChannelSite extends FakeSite {
  new(super.room);

  @override
  String get id => SiteIds.iptv;

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async => [
    const LivePlayQuality(quality: '默认', id: 'default'),
  ];

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async => [
    detail.link!,
  ];
}

/// An engine that opens and never plays (the stream that takes long).
final class _SilentEngine implements PlayerEngine {
  final StreamController<EngineEvent> _events = StreamController.broadcast(sync: true);

  @override
  bool get reportsFrames => false;

  @override
  Stream<EngineEvent> get events => _events.stream;

  @override
  Future<void> open(EngineMedia media) async => _events.add(const EngineBuffering(buffering: true));

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setAudioOnly({required bool enabled}) async {}

  @override
  Future<void> dispose() => _events.close();
}

final class _Room {
  new(this.services, this.danmaku, this.toasts);

  final AppServices services;
  final FakeDanmaku danmaku;
  final List<String> toasts;
}

Future<_Room> _pump(
  WidgetTester tester, {
  required FakeSite site,
  double width = 400,
  double height = 900,
  PlayerEngine? engine,
}) async {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  RoomOrientationChoice.clearSession();
  final services = (await tester.runAsync(testServices))!;
  await tester.runAsync(loadStrings);
  final danmaku = FakeDanmaku();
  final toasts = <String>[];
  final previous = AppNavigator.toast;
  AppNavigator.toast = toasts.add;
  addTearDown(() => AppNavigator.toast = previous);
  final player = engine ?? FakeEngine();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({site.id: () => site})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({site.id: () => danmaku})),
        playbackSessionFactoryProvider.overrideWithValue(
          ({config}) => PlaybackSession(engine: () async => player, opener: MediaOpener()),
        ),
      ],
      child: MaterialApp(
        theme: const LiveTheme().light,
        home: LivePlayPage(
          route: RouteArgs(
            RoutePath.kLivePlay,
            arguments: LiveRoom(platform: site.id, roomId: '6', nick: '主播'),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return _Room(services, danmaku, toasts);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Future<void> _close(WidgetTester tester, _Room room) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(room.services.close);
}

/// The state's buttons, left to right.
List<String> _buttons(WidgetTester tester) {
  const keys = [
    'live-play-state-switch-room',
    'live-play-state-refresh',
    'live-play-state-retry',
    'live-play-state-switch-line',
    'live-play-state-login',
    'live-play-state-open',
    'live-play-state-play-again',
  ];
  final found =
      [
        for (final key in keys)
          if (find.byKey(ValueKey(key)).evaluate().isNotEmpty) key,
      ]..sort(
        (a, b) => tester.getCenter(find.byKey(ValueKey(a))).dx.compareTo(tester.getCenter(find.byKey(ValueKey(b))).dx),
      );
  return [for (final key in found) key.replaceFirst('live-play-state-', '')];
}

PictureState _state({
  RoomStage stage = RoomStage.playing,
  Object? failure,
  LiveRoom? room,
  PlaybackState playback = const PlaybackState(status: PlaybackStatus.playing),
  bool reconnecting = false,
  int attempts = 0,
  bool audioOnly = false,
  bool restoring = false,
  bool slow = false,
}) => pictureStateOf(
  stage: stage,
  failure: failure,
  room: room ?? liveRoom(),
  playback: playback,
  reconnecting: reconnecting,
  attempts: attempts,
  audioOnly: audioOnly,
  restoring: restoring,
  slow: slow,
);

void main() {
  setUpAll(loadStrings);

  group('picture states (c2-c15)', () {
    test('loading, connecting and slow say what they wait for', () {
      expect(_state(stage: RoomStage.loading).title, '正在进入直播间…');
      final connecting = _state(playback: const PlaybackState(status: PlaybackStatus.opening, lineCount: 2));
      expect(connecting.kind, PictureStateKind.connecting);
      expect(connecting.title, '正在连接直播流…');
      expect(connecting.actions, isEmpty);
      final slow = _state(playback: const PlaybackState(status: PlaybackStatus.buffering, lineCount: 2), slow: true);
      expect(slow.kind, PictureStateKind.slow);
      expect(slow.reason, '比平时慢，可以换一条线路试试');
      expect(slow.actions, [PictureAction.switchLine, PictureAction.retry]);
      expect(
        _state(playback: const PlaybackState(status: PlaybackStatus.buffering, lineCount: 1), slow: true).actions,
        [PictureAction.retry],
        reason: 'one line: nothing to switch to',
      );
    });

    test('offline, banned, carousel and unknown each say their own (c7, c10)', () {
      final offline = _state(
        stage: RoomStage.offline,
        room: liveRoom(status: LiveStatus.offline),
      );
      expect((offline.kind, offline.title, offline.reason), (PictureStateKind.offline, '当前主播未开播或已下播', '开播后会自动开始播放'));
      expect(offline.actions, [PictureAction.switchRoom, PictureAction.refresh]);
      expect(offline.dim, PictureDim.cover);
      expect(offline.showsStreamer, isTrue);
      final banned = _state(
        stage: RoomStage.offline,
        room: liveRoom(status: LiveStatus.banned),
      );
      expect((banned.kind, banned.title), (PictureStateKind.banned, '该直播间已被平台封禁或关闭'));
      expect(banned.actions, [PictureAction.switchRoom, PictureAction.refresh]);
      final carousel = _state(
        stage: RoomStage.offline,
        room: liveRoom(status: LiveStatus.carousel),
      );
      expect((carousel.title, carousel.reason), ('主播未开播，正在轮播往期视频', '开播后会自动开始播放'));
      final unknown = _state(
        stage: RoomStage.offline,
        room: liveRoom(status: LiveStatus.unknown),
      );
      expect(unknown.title, '暂时无法确认直播状态');
      expect(unknown.actions, [PictureAction.refresh, PictureAction.switchRoom]);
    });

    test('a failed detail by reason; a missing room only offers another (c10)', () {
      final failed = _state(stage: RoomStage.failed, failure: const NetworkFailure(SiteIds.bilibili));
      expect(failed.kind, PictureStateKind.detailFailed);
      expect(failed.actions, [PictureAction.retry, PictureAction.switchRoom]);
      final missing = _state(stage: RoomStage.failed, failure: const NotFound(SiteIds.bilibili));
      expect((missing.kind, missing.title), (PictureStateKind.notFound, '直播间不存在或已被删除'));
      expect(missing.actions, [PictureAction.switchRoom]);
    });

    test('restrictions give the reason and the next step (c11)', () {
      PictureState restricted(LiveRestriction restriction) => _state(
        stage: RoomStage.unplayable,
        failure: const StreamUnavailable(SiteIds.bilibili, 'no qualities'),
        room: liveRoom(restriction: restriction),
      );
      final login = restricted(LiveRestriction.needsLogin);
      expect((login.kind, login.title), (PictureStateKind.restricted, '该直播需要登录平台账号才能观看'));
      expect(login.actions, [PictureAction.login, PictureAction.retry]);
      final paid = restricted(LiveRestriction.paid);
      expect(paid.title, '这是付费直播，需要在平台购买后观看');
      expect(paid.actions, [PictureAction.openInPlatform, PictureAction.switchRoom]);
      for (final kind in [
        LiveRestriction.subscribersOnly,
        LiveRestriction.private,
        LiveRestriction.appOnly,
        LiveRestriction.password,
        LiveRestriction.adult,
      ]) {
        expect(restricted(kind).actions, [PictureAction.openInPlatform, PictureAction.switchRoom], reason: '$kind');
      }
      expect(restricted(LiveRestriction.regionBlocked).actions, [PictureAction.retry, PictureAction.switchRoom]);
      final noUrl = _state(stage: RoomStage.unplayable, failure: const StreamUnavailable(SiteIds.bilibili, 'no urls'));
      expect((noUrl.kind, noUrl.title), (PictureStateKind.noStream, '平台显示在播，但没有给出可播放的地址'));
      expect(noUrl.actions, [PictureAction.retry, PictureAction.switchRoom]);
      final loginFailure = _state(stage: RoomStage.unplayable, failure: const NeedsLogin(SiteIds.bilibili));
      expect(loginFailure.actions, [PictureAction.login, PictureAction.retry]);
    });

    test('playback failure, reconnecting, audio only, restoring, ended (c12-c15)', () {
      final failed = _state(
        playback: const PlaybackState(
          status: PlaybackStatus.error,
          lineCount: 2,
          error: PlayerException(message: 'x', type: PlayerErrorType.network),
        ),
      );
      expect((failed.title, failed.reason), ('播放已中断', '网络连接失败'));
      expect(failed.actions, [PictureAction.retry, PictureAction.switchLine]);
      expect(failed.dim, PictureDim.heavy);
      final reconnecting = _state(
        playback: const PlaybackState(status: PlaybackStatus.buffering, lineCount: 2),
        reconnecting: true,
        attempts: 2,
      );
      expect((reconnecting.title, reconnecting.dim), ('正在重连（第 2 次）', PictureDim.light));
      expect(reconnecting.actions, [PictureAction.switchLine]);
      expect(_state(audioOnly: true).kind, PictureStateKind.audioOnly);
      expect(_state(restoring: true).title, '正在恢复实时画面');
      final ended = _state(playback: const PlaybackState(status: PlaybackStatus.completed));
      expect(ended.title, '回放已播完');
      expect(ended.actions, [PictureAction.playAgain, PictureAction.switchRoom]);
      expect(_state().kind, PictureStateKind.none);
    });

    test('bars only once a stream is open (c5)', () {
      expect(pictureHasControls(RoomStage.playing), isTrue);
      for (final stage in [RoomStage.loading, RoomStage.offline, RoomStage.failed, RoomStage.unplayable]) {
        expect(pictureHasControls(stage), isFalse, reason: '$stage');
      }
    });
  });

  group('the IPTV guide rows (c17)', () {
    final now = DateTime(2026, 10, 1, 21, 36);
    EpgProgramme at(int day, int hour, int minute, String title, {int length = 60}) {
      // Days after the 15th are September's.
      final start = DateTime(2026, day > 15 ? 9 : 10, day, hour, minute);
      return EpgProgramme(
        channelId: 'c',
        sourceId: 's',
        start: start,
        stop: start.add(Duration(minutes: length)),
        title: title,
      );
    }

    final programmes = [
      at(29, 20, 0, '很早以前'),
      at(1, 19, 30, '候鸟迁徙'),
      at(1, 20, 30, '海岸线'),
      at(1, 21, 30, '江河万里'),
      at(1, 22, 30, '森林的秘密'),
      at(2, 0, 10, '高原上的四季'),
    ];

    test('grouped by day; replayable, gone, live and scheduled; the anchor puts the live one third', () {
      final entries = guideEntries(
        programmes,
        now: now,
        catchUp: const CatchUp(mode: 'default', days: 2),
      );
      expect(entries.whereType<GuideDay>().map((d) => d.day.day), [29, 1, 2]);
      final kinds = [for (final e in entries.whereType<GuideProgramme>()) e.kind];
      expect(kinds, [
        GuideProgrammeKind.gone,
        GuideProgrammeKind.replayable,
        GuideProgrammeKind.replayable,
        GuideProgrammeKind.live,
        GuideProgrammeKind.scheduled,
        GuideProgrammeKind.scheduled,
      ]);
      // Heading 29, gone, heading 1, two replayable, then live: two rows up.
      expect(guideAnchorOffset(entries), guideDayHeight * 2 + guideRowHeight * 3 - guideRowHeight * 2);
      final replaying = guideEntries(
        programmes,
        now: now,
        catchUp: const CatchUp(mode: 'default', days: 2),
        replaying: programmes[1],
      );
      expect((replaying[3] as GuideProgramme).kind, GuideProgrammeKind.replaying);
    });

    test('day labels, catch-up note and time', () {
      expect(guideDayLabel(DateTime(2026, 10), now), '今天 · 10月1日 周四');
      expect(guideDayLabel(DateTime(2026, 10, 2), now), '明天 · 10月2日 周五');
      expect(guideDayLabel(DateTime(2026, 9, 30), now), '昨天 · 9月30日 周三');
      expect(guideDayLabel(DateTime(2026, 9, 28), now), '9月28日 周一');
      expect(guideCatchupNote(const CatchUp(mode: 'default', days: 2), now), '可回看 2 天');
      expect(guideCatchupNote(const CatchUp(mode: 'disabled'), now), '不支持回看');
      expect(guideCatchupNote(const CatchUp(mode: 'default'), now), '');
      expect(guideTime(DateTime(2026, 10, 1, 9, 5)), '09:05');
    });
  });

  group('in the room', () {
    testWidgets('loading: the state says it enters the room; no bars, the tabs work (c3, c5)', (tester) async {
      final site = _SlowSite(liveRoom());
      final room = await _pump(tester, site: site);
      expect(find.text('正在进入直播间…'), findsOneWidget);
      expect(find.byKey(const ValueKey('video-state-spinner')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-play-pause')), findsNothing);
      expect(find.byKey(const ValueKey('live-play-top-bar')), findsNothing);
      expect(find.byKey(const ValueKey('live-play-tabs')), findsOneWidget);
      site.gate.complete();
      await _settle(tester);
      expect(find.text('正在进入直播间…'), findsNothing);
      expect(find.byKey(const ValueKey('live-play-pause')), findsOneWidget);
      await _close(tester, room);
    });

    testWidgets('offline: streamer, one sentence, switch room then refresh; the chat shows the notice (c7)', (
      tester,
    ) async {
      final room = await _pump(tester, site: FakeSite(liveRoom(status: LiveStatus.offline)));
      expect(find.text('当前主播未开播或已下播'), findsOneWidget);
      expect(find.text('开播后会自动开始播放'), findsOneWidget);
      expect(find.byKey(const ValueKey('video-state-avatar')), findsOneWidget);
      expect(_buttons(tester), ['switch-room', 'refresh']);
      expect(find.byKey(const ValueKey('live-play-pause')), findsNothing);
      expect(room.toasts, isEmpty, reason: 'S18: the picture says it, no message');
      expect(find.text('每晚八点开播'), findsWidgets);
      expect(find.text('开播后这里显示弹幕'), findsOneWidget);
      await _close(tester, room);
    });

    testWidgets('restricted: the reason, its next step, and the danmaku still connects (c11)', (tester) async {
      final site = FakeSite(liveRoom(restriction: LiveRestriction.needsLogin))..qualities = const [];
      final room = await _pump(tester, site: site);
      expect(find.text('该直播需要登录平台账号才能观看'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('video-state-lock')),
        findsOneWidget,
        reason: 'the lock stays on a short picture',
      );
      expect(_buttons(tester), ['login', 'retry']);
      expect(room.danmaku.connects, isNotEmpty);
      await _close(tester, room);

      final paid = FakeSite(liveRoom(restriction: LiveRestriction.paid))..qualities = const [];
      final second = await _pump(tester, site: paid);
      expect(find.text('在哔哩哔哩打开'), findsOneWidget);
      expect(_buttons(tester), ['open', 'switch-room']);
      await _close(tester, second);
    });

    testWidgets('slow: after 8 s the state says so and offers another line and retry (c4)', (tester) async {
      final room = await _pump(tester, site: FakeSite(liveRoom()), engine: _SilentEngine());
      expect(find.text('正在连接直播流…'), findsOneWidget);
      expect(find.text('比平时慢，可以换一条线路试试'), findsNothing);
      await tester.pump(const Duration(seconds: 9));
      expect(find.text('比平时慢，可以换一条线路试试'), findsOneWidget);
      expect(_buttons(tester), ['switch-line', 'retry']);
      // The bars stay: a stream is open (c5).
      expect(find.byKey(const ValueKey('live-play-pause')), findsOneWidget);
      await _close(tester, room);
    });

    testWidgets('fullscreen offline keeps a reduced top bar: back, no audio only (c6, c9)', (tester) async {
      final room = await _pump(tester, site: FakeSite(liveRoom(status: LiveStatus.offline)), width: 852, height: 393);
      // No bars while nothing plays: fullscreen by the keyboard (F).
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(find.byKey(const ValueKey('live-play-back')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-play-switch-room')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-play-audio-only')), findsNothing);
      expect(find.text('当前主播未开播或已下播'), findsOneWidget);
      await _close(tester, room);
    });

    testWidgets('wide: the state on the left, the chat column says the room is offline', (tester) async {
      final room = await _pump(tester, site: FakeSite(liveRoom(status: LiveStatus.offline)), width: 1280, height: 800);
      expect(find.byKey(const ValueKey('live-play-desktop-split')), findsOneWidget);
      final state = tester.getCenter(find.text('当前主播未开播或已下播'));
      final hint = tester.getCenter(find.text('开播后这里显示弹幕'));
      expect(state.dx, lessThan(hint.dx));
      expect(find.byKey(const ValueKey('video-state-icon')), findsNothing);
      await _close(tester, room);
    });
  });

  group('an IPTV channel keeps its guide where a room has its chat (c16, Z1)', () {
    LiveRoom channel() => LiveRoom(
      platform: SiteIds.iptv,
      roomId: 'cctv',
      title: '纪实频道',
      link: 'http://tv.example/live.m3u8',
      liveStatus: LiveStatus.live,
    );

    testWidgets('portrait: the picture at 16:9 and the guide under it', (tester) async {
      final room = await _pump(tester, site: _ChannelSite(channel()));
      expect(find.byKey(const ValueKey('live-play-channel-stack')), findsOneWidget);
      final guide = tester.getRect(find.byKey(const ValueKey('live-play-guide-view')));
      final stack = tester.getRect(find.byKey(const ValueKey('live-play-channel-stack')));
      expect(guide.top - stack.top, closeTo(400 * 9 / 16, 1));
      expect(find.text('还没有节目单'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-play-tabs')), findsNothing);
      await _close(tester, room);
    });

    testWidgets('wide: the right column folds away with its handle', (tester) async {
      final room = await _pump(tester, site: _ChannelSite(channel()), width: 1280, height: 800);
      expect(find.byKey(const ValueKey('live-play-channel-split')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-play-guide-view')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('live-play-guide-fold')));
      await tester.pump();
      expect(find.byKey(const ValueKey('live-play-guide-view')), findsNothing);
      // The picture's guide button unfolds it again.
      await tester.tap(find.byKey(const ValueKey('live-play-guide')));
      await tester.pump();
      expect(find.byKey(const ValueKey('live-play-guide-view')), findsOneWidget);
      await _close(tester, room);
    });

    testWidgets('fullscreen: the guide button opens it on the right; Esc closes it first', (tester) async {
      final room = await _pump(tester, site: _ChannelSite(channel()), width: 852, height: 393);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('live-play-guide')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('panel-guide')), findsOneWidget);
      final panel = tester.getRect(find.byKey(const ValueKey('live-play-side-panel')));
      expect(panel.width, 360);
      expect(panel.right, 852);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('panel-guide')), findsNothing);
      expect(find.byKey(const ValueKey('live-play-back')), findsOneWidget, reason: 'still in fullscreen');
      await _close(tester, room);
    });
  });

  group('the IPTV guide (c16-c19)', () {
    final now = DateTime(2026, 10, 1, 21, 36);
    EpgProgramme at(int hour, int minute, String title) {
      final start = DateTime(2026, 10, 1, hour, minute);
      return EpgProgramme(
        channelId: 'c',
        sourceId: 's',
        start: start,
        stop: start.add(const Duration(minutes: 60)),
        title: title,
      );
    }

    Future<(LiveRoomController, LiveStore)> host(
      WidgetTester tester, {
      required Future<List<EpgProgramme>> Function(DateTime, DateTime) loader,
      String source = 'guide',
    }) async {
      final store = (await tester.runAsync(() => LiveStore.memory(cipher: FakeCipher())))!;
      await tester.runAsync(() => store.settings.set(Settings.selectedSourceId, source));
      final channel = LiveRoom(
        platform: SiteIds.iptv,
        roomId: 'cctv',
        title: '纪实频道',
        link: 'http://tv.example/live.m3u8',
        liveStatus: LiveStatus.live,
        catchUp: const CatchUp(mode: 'default', days: 2),
      );
      final controller = LiveRoomController(
        room: channel,
        site: FakeSite(channel),
        session: fakeSession(FakeEngine()),
        danmaku: FakeDanmaku(),
        danmakuSupported: false,
        store: store,
        refreshInterval: Duration.zero,
        now: () => now,
      );
      final services = (await tester.runAsync(testServices))!;
      addTearDown(() => tester.runAsync(services.close));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appServicesProvider.overrideWithValue(services), storeProvider.overrideWithValue(store)],
          child: MaterialApp(
            theme: const LiveTheme().light,
            home: Scaffold(
              body: SizedBox(
                width: 393,
                height: 600,
                child: IptvGuideView(key: UniqueKey(), controller: controller, loader: loader),
              ),
            ),
          ),
        ),
      );
      return (controller, store);
    }

    testWidgets('the programmes by day; head, live mark, replay words; a scheduled one says so', (tester) async {
      final toasts = <String>[];
      final previous = AppNavigator.toast;
      AppNavigator.toast = toasts.add;
      addTearDown(() => AppNavigator.toast = previous);
      final (controller, _) = await host(
        tester,
        loader: (from, to) async => [at(19, 30, '候鸟迁徙'), at(20, 30, '海岸线'), at(21, 30, '江河万里'), at(22, 30, '森林的秘密')],
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      await tester.pump();
      expect(find.text('节目单'), findsOneWidget);
      expect(find.text('可回看 2 天'), findsOneWidget);
      expect(find.text('今天 · 10月1日 周四'), findsOneWidget);
      expect(find.byKey(const ValueKey('iptv-live-mark')), findsOneWidget);
      expect(find.text('回看'), findsNWidgets(2));
      await tester.tap(find.text('森林的秘密'));
      await tester.pump();
      expect(toasts, ['该节目尚未开播']);
      controller.dispose();
    });

    testWidgets('loading, failed with retry, not configured with import, empty', (tester) async {
      final gate = Completer<List<EpgProgramme>>();
      final (first, _) = await host(tester, loader: (from, to) => gate.future);
      expect(find.text('正在读取节目单…'), findsOneWidget);
      gate.completeError(StateError('x'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(find.text('节目单读取失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      first.dispose();

      final (second, _) = await host(tester, loader: (from, to) async => const [], source: '');
      await tester.pump();
      expect(find.text('还没有节目单'), findsOneWidget);
      expect(find.text('去导入节目单'), findsOneWidget);
      second.dispose();

      final (third, _) = await host(tester, loader: (from, to) async => const []);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(find.text('暂无后续节目排班信息'), findsOneWidget);
      expect(find.text('这个频道在节目单里没有节目'), findsOneWidget);
      third.dispose();
    });
  });
}
