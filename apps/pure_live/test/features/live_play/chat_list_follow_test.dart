// B08 c1 (audit B-6, research S5): the room tells the chat list of new
// lines at most once a frame and nobody else; the list is reversed, follows
// without jumping and holds still while it is scrolled up.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import 'live_play_support.dart';

final class _Room {
  new(this.services, this.danmaku);

  final AppServices services;
  final FakeDanmaku danmaku;
}

Future<_Room> _pump(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(400, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  RoomOrientationChoice.clearSession();
  final services = (await tester.runAsync(testServices))!;
  await tester.runAsync(loadStrings);
  final previous = AppNavigator.toast;
  AppNavigator.toast = (_) {};
  addTearDown(() => AppNavigator.toast = previous);
  // Douyu: no Bilibili names hint above the list.
  final platform = _DouyuSite(liveRoom(startedAt: DateTime.now().subtract(const Duration(minutes: 30))));
  final danmaku = FakeDanmaku();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({platform.id: () => platform})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({platform.id: () => danmaku})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(FakeEngine())),
      ],
      child: MaterialApp(
        theme: const LiveTheme().light,
        home: LivePlayPage(
          route: RouteArgs(
            RoutePath.kLivePlay,
            arguments: LiveRoom(platform: platform.id, roomId: '6', nick: '主播'),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  return _Room(services, danmaku);
}

class _DouyuSite extends FakeSite {
  new(super.room);

  @override
  String get id => SiteIds.douyu;
}

Future<void> _close(WidgetTester tester, _Room room) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(room.services.close);
}

LiveRoomController _controller(WidgetTester tester) => tester.widget<ChatList>(find.byType(ChatList)).controller;

final Finder _list = find.byKey(const ValueKey('live-play-chat'));

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.descendant(of: _list, matching: find.byType(Scrollable))).position;

Finder _line(int i) => find.text('第 $i 条', findRichText: true);

void _chats(_Room room, int from, int to) {
  for (var i = from; i < to; i++) {
    room.danmaku.chat('第 $i 条', user: '观众$i', id: 'm$i');
  }
}

/// Frames at 120 Hz.
Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(microseconds: 8333));
  }
}

void main() {
  testWidgets('messages between two frames: the list builds once, the room hears nothing, the flying layer at once', (
    tester,
  ) async {
    final room = await _pump(tester);
    final controller = _controller(tester);
    var roomHeard = 0;
    var feedHeard = 0;
    void onRoom() => roomHeard++;
    void onFeed() => feedHeard++;
    controller.addListener(onRoom);
    controller.chat.addListener(onFeed);
    final flown = <String>[];
    final flying = controller.flying.listen((message) => flown.add(message.message));
    addTearDown(flying.cancel);
    var listBuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget.key == const ValueKey('live-play-chat')) listBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    _chats(room, 0, 30);
    expect(flown, hasLength(30), reason: 'the flying layer gets each message as it comes');
    expect(controller.chat.length, greaterThanOrEqualTo(30), reason: 'the lines are there at once');
    expect(controller.chat.pending, isTrue);
    expect(feedHeard, 0, reason: 'the list hears at the next frame');
    expect(roomHeard, 0, reason: 'chat is not news for the rest of the room page');
    await tester.pump();
    expect(feedHeard, 1);
    expect(listBuilds, 1);
    expect(_line(29), findsOneWidget);
    expect(roomHeard, 0);

    debugOnRebuildDirtyWidget = null;
    controller
      ..removeListener(onRoom)
      ..chat.removeListener(onFeed);
    await _close(tester, room);
  });

  testWidgets('following: new lines come in at the bottom, nothing jumps, old lines are not built again', (
    tester,
  ) async {
    final room = await _pump(tester);
    _chats(room, 0, 40);
    await tester.pump();
    final position = _position(tester);
    expect(position.pixels, 0);
    var moves = 0;
    void onMove() => moves++;
    position.addListener(onMove);
    final built = <int>[];
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget case final ChatLineView view) built.add(view.line.id);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    final firstNew = _controller(tester).chat.added;

    for (var batch = 0; batch < 10; batch++) {
      _chats(room, 40 + batch * 4, 44 + batch * 4);
      await _frames(tester, 1);
    }
    debugOnRebuildDirtyWidget = null;
    position.removeListener(onMove);
    expect(moves, 0, reason: 'no jumpTo: the reversed list keeps 0 at the newest line');
    expect(position.pixels, 0);
    expect(built, isNotEmpty);
    expect(built.every((id) => id >= firstNew), isTrue, reason: 'only new lines are built: $built');
    expect(built.toSet().length, built.length, reason: 'each once');
    // The newest line is the lowest one, at the bottom of the list.
    final newest = tester.getRect(_line(79));
    expect(newest.bottom, lessThanOrEqualTo(tester.getRect(_list).bottom));
    expect(newest.top, greaterThan(tester.getRect(_line(78)).top));
    expect(find.byKey(const ValueKey('live-play-new-messages')), findsNothing);
    await _close(tester, room);
  });

  testWidgets('scrolled up, the lines stay put while new ones are counted; the button follows again', (tester) async {
    final room = await _pump(tester);
    _chats(room, 0, 60);
    await tester.pump();
    await tester.drag(_list, const Offset(0, 300));
    await _frames(tester, 3);
    expect(_position(tester).pixels, greaterThan(24));
    expect(find.byKey(const ValueKey('live-play-new-messages')), findsOneWidget);
    expect(find.text('回到底部'), findsOneWidget);
    final listRect = tester.getRect(_list);
    final visible = [
      for (var i = 59; i >= 0; i--)
        if (_line(i).evaluate().isNotEmpty && listRect.contains(tester.getCenter(_line(i)))) i,
    ];
    expect(visible.length, greaterThan(2));
    final watched = visible[visible.length ~/ 2];
    final other = visible.first;
    final rect = tester.getRect(_line(watched));

    // More than the feed keeps (500): the lines on screen stay all the same.
    for (var batch = 0; batch < 30; batch++) {
      _chats(room, 60 + batch * 20, 80 + batch * 20);
      await _frames(tester, 1);
    }
    expect(tester.getRect(_line(watched)), rect);
    expect(find.text('600 条新弹幕，点击回到底部'), findsOneWidget);
    expect(_line(659), findsNothing);

    // A line taken back goes from the held list too.
    room.danmaku.emit(
      const DanmakuReceived(
        LiveMessage(
          type: LiveMessageType.retraction,
          userName: '',
          message: '',
          color: LiveMessageColor.white,
          data: LiveRetraction.message('m0'),
        ),
      ),
    );
    room.danmaku.emit(
      DanmakuReceived(
        LiveMessage(
          type: LiveMessageType.retraction,
          userName: '',
          message: '',
          color: LiveMessageColor.white,
          data: LiveRetraction.message('m$other'),
        ),
      ),
    );
    await _frames(tester, 1);
    expect(_line(other), findsNothing);

    await tester.tap(find.byKey(const ValueKey('live-play-new-messages')));
    await _frames(tester, 2);
    expect(_position(tester).pixels, 0);
    expect(find.byKey(const ValueKey('live-play-new-messages')), findsNothing);
    expect(_line(659), findsOneWidget);
    expect(tester.getRect(_line(659)).bottom, lessThanOrEqualTo(listRect.bottom));
    await _close(tester, room);
  });

  testWidgets('a drag that ends back at the bottom follows again', (tester) async {
    final room = await _pump(tester);
    _chats(room, 0, 60);
    await tester.pump();
    await tester.drag(_list, const Offset(0, 200));
    await _frames(tester, 3);
    expect(find.byKey(const ValueKey('live-play-new-messages')), findsOneWidget);
    _chats(room, 60, 65);
    await _frames(tester, 1);
    expect(find.text('5 条新弹幕，点击回到底部'), findsOneWidget);
    await tester.drag(_list, const Offset(0, -400));
    await _frames(tester, 3);
    expect(_position(tester).pixels, 0);
    expect(find.byKey(const ValueKey('live-play-new-messages')), findsNothing);
    expect(_line(64), findsOneWidget, reason: 'the lines that came meanwhile');
    _chats(room, 65, 66);
    await _frames(tester, 1);
    expect(_line(65), findsOneWidget);
    await _close(tester, room);
  });
}
