// U.2b2 (docs/T05/T05c/T05c.1 c14, X1 A): the list a room was opened from
// goes along, and the portrait fullscreen swipes through it on the same
// player.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/room_layout.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/logic/room_playlist.dart';
import 'package:pure_live/features/live_play/player/player_view.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import 'live_play_support.dart';

LiveRoom _room(String id, {String platform = SiteIds.bilibili}) =>
    LiveRoom(platform: platform, roomId: id, nick: '主播$id', title: '标题$id', area: '分区$id', liveStatus: LiveStatus.live);

/// A platform answering every room by its id, and naming the room in its
/// lines.
class _ListSite extends FakeSite {
  new(this.rooms) : super(rooms.values.first);

  final Map<String, LiveRoom> rooms;

  /// The rooms asked for, in order.
  final List<String> asked = [];

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    asked.add(roomId);
    return rooms[roomId] ?? (throw StateError('no room $roomId'));
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async => [
    'https://a.example/${detail.roomId}/index.m3u8',
  ];
}

/// An engine whose stop waits for [gate] (a switch still stopping).
final class _GateEngine implements PlayerEngine {
  final StreamController<EngineEvent> _events = StreamController.broadcast(sync: true);
  final List<EngineMedia> opens = [];
  Completer<void>? gate;

  @override
  bool get reportsFrames => false;

  @override
  Stream<EngineEvent> get events => _events.stream;

  @override
  Future<void> open(EngineMedia media) async {
    opens.add(media);
    _events
      ..add(const EngineBuffering(buffering: false))
      ..add(const EnginePlaying(playing: true));
  }

  @override
  Future<void> stop() async {
    await gate?.future;
  }

  /// Reports [event] as the engine.
  void emit(EngineEvent event) => _events.add(event);

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

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
  new(this.services, this.site, this.engine, this.sessions);

  final AppServices services;
  final _ListSite site;
  final _GateEngine engine;
  final List<PlaybackSession> sessions;
}

final Map<String, LiveRoom> _rooms = {
  for (final id in ['5', '6', '7']) id: _room(id),
};

/// The room of [arguments] on a phone, its stream portrait.
Future<_Room> _pump(WidgetTester tester, {required Object arguments, bool swipe = true}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  tester.view
    ..physicalSize = const Size(393, 852)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  RoomOrientationChoice.clearSession();
  final services = (await tester.runAsync(testServices))!;
  await tester.runAsync(loadStrings);
  await tester.runAsync(() => services.store.settings.set(Settings.portraitFullscreenSwipeSwitch, swipe));
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  final previous = AppNavigator.toast;
  AppNavigator.toast = (_) {};
  addTearDown(() => AppNavigator.toast = previous);
  final site = _ListSite(_rooms);
  final engine = _GateEngine();
  final sessions = <PlaybackSession>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => site})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: FakeDanmaku.new})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) {
          final session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
          sessions.add(session);
          return session;
        }),
      ],
      child: MaterialApp(
        theme: const LiveTheme().light,
        home: LivePlayPage(route: RouteArgs(RoutePath.kLivePlay, arguments: arguments)),
      ),
    ),
  );
  await _settle(tester);
  engine.emit(const EngineVideoSize(720, 1280));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return _Room(services, site, engine, sessions);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Future<void> _close(WidgetTester tester, _Room room) async {
  room.engine.gate?.complete();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(room.services.close);
  debugDefaultTargetPlatformOverride = null;
}

Finder _key(String key) => find.byKey(ValueKey(key));

/// Into the portrait fullscreen with the fullscreen button.
Future<void> _portraitFullscreen(WidgetTester tester) async {
  await tester.tap(_key('live-play-fullscreen'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  // The controls hide after 4 s; the picture is free to swipe.
  await tester.pump(const Duration(seconds: 5));
}

/// The room the player shows.
String _shown(WidgetTester tester) => tester.widget<RoomPlayer>(find.byType(RoomPlayer)).controller.room.roomId;

/// Swipes the middle of the picture by [dy] and lets the room settle.
Future<void> _swipe(WidgetTester tester, double dy, {double x = 196}) async {
  await tester.timedDragFrom(Offset(x, 420), Offset(0, dy), const Duration(milliseconds: 400));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await _settle(tester);
}

void main() {
  group('U.2b2 logic', () {
    test('c1: the list goes along with the usable rooms; a lone room or an empty list does not', () {
      final room = _room('6');
      final arguments = AppNavigator.liveRoomArguments(room, [
        _room('5'),
        room,
        _room('8', platform: 'huajiao'),
        _room(''),
        _room('7'),
      ]);
      expect(arguments, isA<LiveRoomArgs>());
      final args = arguments as LiveRoomArgs;
      expect(args.room, room);
      expect(args.playlist.map((item) => item.roomId), ['5', '6', '7'], reason: 'retired platforms and no id left out');
      expect(AppNavigator.liveRoomArguments(room, const []), same(room));
      expect(AppNavigator.liveRoomArguments(room, [room]), same(room));
      expect(LiveRoomArgs.roomOf(args), room);
      expect(LiveRoomArgs.roomOf(room), room);
      expect(LiveRoomArgs.roomOf('x'), isNull);
    });

    test('c4, c5: the list wraps around; a room missing from it goes first; a lone room has none', () {
      final list = RoomPlaylist([_room('5'), _room('6'), _room('7')], current: _room('6'));
      expect((list.index, list.swipeable), (1, true));
      expect(list.neighbour(1)?.roomId, '7');
      expect(list.neighbour(-1)?.roomId, '5');
      expect(list.move(1).roomId, '7');
      expect(list.move(1).roomId, '5', reason: 'past the end: back to the start (the TV)');
      expect(list.move(-1).roomId, '7');
      final missing = RoomPlaylist([_room('5')], current: _room('9'));
      expect(missing.rooms.map((room) => room.roomId), ['9', '5']);
      expect(missing.index, 0);
      final lone = RoomPlaylist([_room('6')], current: _room('6'));
      expect(lone.swipeable, isFalse);
      expect(lone.neighbour(1), isNull);
    });

    test('c3: thirds with the swipe (brightness, room, volume), halves without', () {
      expect(pictureDragAt(x: 100, width: 393), PictureDrag.brightness);
      expect(pictureDragAt(x: 200, width: 393), PictureDrag.volume);
      expect(pictureDragAt(x: 100, width: 393, switchRooms: true), PictureDrag.brightness);
      expect(pictureDragAt(x: 196, width: 393, switchRooms: true), PictureDrag.switchRoom);
      expect(pictureDragAt(x: 300, width: 393, switchRooms: true), PictureDrag.volume);
    });

    test('c4: a third of the screen or a fling switches; a fling back keeps the room', () {
      expect(swipeSwitchStep(offset: -290, extent: 852, velocity: 0), 1, reason: 'up: the next room');
      expect(swipeSwitchStep(offset: 290, extent: 852, velocity: 0), -1, reason: 'down: the previous room');
      expect(swipeSwitchStep(offset: -200, extent: 852, velocity: 0), 0);
      expect(swipeSwitchStep(offset: -60, extent: 852, velocity: -900), 1, reason: 'a fling');
      expect(swipeSwitchStep(offset: -30, extent: 852, velocity: -900), 0, reason: 'too short even for a fling');
      expect(swipeSwitchStep(offset: -400, extent: 852, velocity: 900), 0, reason: 'flung back');
      expect(swipeSwitchStep(offset: 0, extent: 852, velocity: -900), 0);
    });
  });

  group('U.2b2 room', () {
    testWidgets('c5: up swipes to the next room on the same player and page; down back; wraps; history', (
      tester,
    ) async {
      final room = await _pump(
        tester,
        arguments: LiveRoomArgs(room: _rooms['6']!, playlist: _rooms.values.toList()),
      );
      await _portraitFullscreen(tester);
      expect(_shown(tester), '6');
      final session = tester.widget<RoomPlayer>(find.byType(RoomPlayer)).controller.session;

      await _swipe(tester, -400);
      expect(_shown(tester), '7');
      expect(room.sessions, hasLength(1), reason: 'one player for every room');
      expect(tester.widget<RoomPlayer>(find.byType(RoomPlayer)).controller.session, same(session));
      expect(room.engine.opens.last.uri.path, '/7/index.m3u8');
      expect(find.byType(LivePlayPage), findsOneWidget);
      expect(
        tester.widget<RoomPlayer>(find.byType(RoomPlayer)).display,
        RoomDisplay.portraitFullscreen,
        reason: 'still the portrait fullscreen',
      );

      await _swipe(tester, -400);
      expect(_shown(tester), '5', reason: 'past the end: the start');
      await _swipe(tester, 400);
      expect(_shown(tester), '7', reason: 'down: the previous');
      expect(room.engine.opens.map((media) => media.uri.pathSegments.first), ['6', '7', '5', '7']);
      final history = (await tester.runAsync(room.services.store.history.all))!;
      expect(history.map((item) => item.roomId).toSet(), {'5', '6', '7'});
      await _close(tester, room);
    });

    testWidgets('c5: swipes while the room before still stops start only the last room', (tester) async {
      final room = await _pump(
        tester,
        arguments: LiveRoomArgs(room: _rooms['6']!, playlist: _rooms.values.toList()),
      );
      await _portraitFullscreen(tester);
      room.engine.gate = Completer<void>();
      await _swipe(tester, -400);
      expect(_shown(tester), '7');
      await _swipe(tester, -400);
      expect(_shown(tester), '5');
      expect(room.site.asked, ['6'], reason: 'nothing starts before the player is stopped');
      room.engine.gate!.complete();
      room.engine.gate = null;
      await _settle(tester);
      expect(room.site.asked, ['6', '5'], reason: 'room 7 never started');
      expect(room.engine.opens.map((media) => media.uri.pathSegments.first), ['6', '5']);
      await _close(tester, room);
    });

    testWidgets('c4: the next room follows the finger with its name; past a third "松手换到这个直播间"; short springs back', (
      tester,
    ) async {
      final room = await _pump(
        tester,
        arguments: LiveRoomArgs(room: _rooms['6']!, playlist: _rooms.values.toList()),
      );
      await _portraitFullscreen(tester);
      final drag = await tester.startGesture(const Offset(196, 420));
      await drag.moveBy(const Offset(0, -40));
      await drag.moveBy(const Offset(0, -60));
      await tester.pump();
      final preview = _key('live-play-swipe-preview-${_rooms['7']!.identityKey}');
      expect(preview, findsOneWidget);
      expect(find.descendant(of: preview, matching: find.text('主播7')), findsOneWidget);
      expect(tester.widget<Text>(_key('live-play-swipe-line')).data, '哔哩哔哩 · 分区7');
      expect(tester.getTopLeft(preview).dy, closeTo(852 - 100 + kDragSlopDefault, 30), reason: 'it follows the finger');

      await drag.moveBy(const Offset(0, -250));
      await tester.pump();
      expect(tester.widget<Text>(_key('live-play-swipe-line')).data, '哔哩哔哩 · 分区7 · 松手换到这个直播间');
      // Back under a third and let go slowly: the room stays.
      await drag.moveBy(const Offset(0, 200));
      await tester.pump(const Duration(seconds: 1));
      await drag.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _settle(tester);
      expect(_shown(tester), '6');
      expect(preview, findsNothing);
      expect(room.site.asked, ['6']);
      await _close(tester, room);
    });

    testWidgets('c3: off, without a list, or on the sides: no switch and no preview', (tester) async {
      // The setting off (default).
      var room = await _pump(
        tester,
        arguments: LiveRoomArgs(room: _rooms['6']!, playlist: _rooms.values.toList()),
        swipe: false,
      );
      expect(room.services.store.settings.get(Settings.portraitFullscreenSwipeSwitch), isFalse);
      await _portraitFullscreen(tester);
      expect(_key('live-play-swipe-stage'), findsNothing);
      await _swipe(tester, -400);
      expect(_shown(tester), '6');
      await _close(tester, room);

      // A lone room (a link, the history).
      room = await _pump(tester, arguments: _rooms['6']!);
      await _portraitFullscreen(tester);
      expect(_key('live-play-swipe-stage'), findsNothing);
      await _swipe(tester, -400);
      expect(_shown(tester), '6');
      await _close(tester, room);

      // The left and right thirds stay brightness and volume.
      room = await _pump(
        tester,
        arguments: LiveRoomArgs(room: _rooms['6']!, playlist: _rooms.values.toList()),
      );
      await _portraitFullscreen(tester);
      expect(_key('live-play-swipe-stage'), findsOneWidget);
      await _swipe(tester, -400, x: 60);
      await _swipe(tester, -400, x: 385);
      expect(_shown(tester), '6');
      expect(room.site.asked, ['6']);
      await _close(tester, room);
    });

    testWidgets('c5: a landscape room swiped to stays in the portrait fullscreen over the ambient background', (
      tester,
    ) async {
      final room = await _pump(
        tester,
        arguments: LiveRoomArgs(room: _rooms['6']!, playlist: _rooms.values.toList()),
      );
      await _portraitFullscreen(tester);
      await _swipe(tester, -400);
      // Room 7 plays a landscape picture.
      final session = tester.widget<RoomPlayer>(find.byType(RoomPlayer)).controller.session;
      expect(session.state.status, PlaybackStatus.playing);
      room.engine.emit(const EngineVideoSize(1920, 1080));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.widget<RoomPlayer>(find.byType(RoomPlayer)).display,
        RoomDisplay.portraitFullscreen,
        reason: 'still the portrait fullscreen',
      );
      expect(tester.widget<RoomPlayer>(find.byType(RoomPlayer)).presentation, PicturePresentation.ambient);
      expect(find.byType(AmbientBackdrop), findsOneWidget);
      await _close(tester, room);
    });
  });
}
