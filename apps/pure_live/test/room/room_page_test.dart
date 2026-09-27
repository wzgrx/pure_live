import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart' show DanmakuStatus, DanmakuSystem;
import 'package:live_media/live_media.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart' show Appearance, PureTheme;
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/danmaku/danmaku_preferences.dart';
import 'package:pure_live_app/features/danmaku/danmaku_source.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/me/history_page.dart';
import 'package:pure_live_app/features/room/playback.dart';
import 'package:pure_live_app/features/room/player_view.dart';
import 'package:pure_live_app/features/room/presentation.dart';
import 'package:pure_live_app/features/room/room_page.dart';

import '../danmaku/fake_danmaku.dart';

final class _QuietSite implements RoomSource, StreamSource {
  @override
  Future<RoomDetail> detail(RoomRef ref) async => liveRoom(id: ref.roomId);

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) => Completer<StreamSet>().future;
}

final class _RecordingWriter implements BlockRuleWriter {
  final List<(BlockKind, String)> added = [];

  @override
  Future<bool> add(BlockKind kind, String value) async {
    added.add((kind, value));
    return true;
  }

  @override
  Future<bool> remove(BlockKind kind, String value) async => true;
}

void main() {
  late FakeDanmakuSource source;
  late _RecordingWriter writer;

  Future<void> openRoom(WidgetTester tester, {Size size = const Size(393, 852), bool fullscreenDefault = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    if (fullscreenDefault) await tester.runAsync(() => store.settings.set(Settings.fullScreenDefault, true));
    source = FakeDanmakuSource();
    writer = _RecordingWriter();
    final session = PlaybackSession(engine: () => throw UnimplementedError('no engine in widget tests'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          sitesProvider.overrideWithValue({'douyu': PlatformSite(_QuietSite())}),
          roomDetailProvider.overrideWith((ref, room) async => liveRoom(id: room.roomId)),
          isFollowedProvider.overrideWith((ref, room) => Stream.value(false)),
          danmakuSourceProvider.overrideWithValue(source),
          blockRulesProvider.overrideWith((ref) => Stream.value(const [])),
          blockRuleWriterProvider.overrideWithValue(writer),
          playbackSessionProvider.overrideWith((ref) => session),
          followsProvider.overrideWith((ref) => Stream.value(const [])),
          historyProvider.overrideWith(
            (ref) => Stream.value([
              HistoryEntry(
                room: StoredRoom(
                  ref: RoomRef('douyu', '2'),
                  anchorName: '主播2',
                  title: '标题2',
                  updatedAt: DateTime(2026),
                ),
              ),
            ]),
          ),
        ],
        child: MaterialApp(
          theme: PureTheme.of(Appearance.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => RoomPage(room: RoomRef('douyu', '1')))),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  RoomPresentation shown(WidgetTester tester) => tester.widget<PlayerView>(find.byType(PlayerView)).presentation;

  testWidgets('§3.6: back leaves fullscreen first, then the room', (tester) async {
    await openRoom(tester);
    expect(find.byType(RoomPage), findsOneWidget);
    expect(shown(tester), RoomPresentation.inline);

    await tester.tap(find.byKey(const ValueKey('room-fullscreen')));
    await tester.pumpAndSettle();
    expect(shown(tester), RoomPresentation.fullscreen);
    // INV-ROOM-07: a change waits for the previous one (the test platform
    // never answers, so for its 1 s limit).
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(shown(tester), RoomPresentation.fullscreen);
    await tester.pump(const Duration(seconds: 1));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(RoomPage), findsOneWidget, reason: 'the first back only leaves fullscreen');
    expect(shown(tester), RoomPresentation.inline);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(RoomPage), findsNothing);
    expect(find.text('open'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  void background(WidgetTester tester) {
    [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
  }

  void foreground(WidgetTester tester) {
    [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
  }

  testWidgets('LST-4: back from the background, a chat connection that gave up connects again', (tester) async {
    await openRoom(tester);
    expect(source.feeds, hasLength(1));
    const timeout = DanmakuSystem(room: 'douyu:1', session: 1, receivedAt: 1, status: DanmakuStatus.timeout);
    source.feeds.single.emit(batchOf(const [], system: [timeout]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    background(tester);
    await tester.pump();
    foreground(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(source.feeds, hasLength(1), reason: 'the return settles first');
    await tester.pump(const Duration(milliseconds: 200));
    // A subscription's cancel completes on the real microtask queue.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(source.feeds, hasLength(2));
    expect(source.feeds.first.closed, isTrue);

    // A healthy connection is left alone.
    background(tester);
    await tester.pump();
    foreground(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(source.feeds, hasLength(2));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('F-DM-04: blocking from the chat list filters at once and stores the rule', (tester) async {
    await openRoom(tester);
    expect(source.feeds, hasLength(1));
    source.feeds.single.emit(batchOf([chatLine('Spammer', '加群领福利'), chatLine('fan', '主播好')]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('加群领福利'), findsOneWidget);

    await tester.longPress(find.textContaining('加群领福利'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('屏蔽用户'));
    await tester.pumpAndSettle();

    expect(writer.added, [(BlockKind.user, 'Spammer')]);
    expect(source.feeds.single.current.blockedUsers, ['Spammer']);
    expect(find.textContaining('加群领福利'), findsNothing);
    expect(find.textContaining('主播好'), findsOneWidget);
  });

  testWidgets('theater on large windows: T enters, Esc leaves; the info bar hides in theater', (tester) async {
    await openRoom(tester, size: const Size(1400, 900));
    expect(find.text('加入多画面'), findsOneWidget);
    await tester.tap(find.byTooltip('剧场模式 (T)'));
    await tester.pumpAndSettle();
    expect(shown(tester), RoomPresentation.theater);
    expect(find.text('加入多画面'), findsNothing);
    await tester.pump(const Duration(seconds: 1));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(shown(tester), RoomPresentation.inline);
    expect(find.text('加入多画面'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pumpAndSettle();
    expect(shown(tester), RoomPresentation.theater);
    // C folds the chat panel away and back.
    expect(find.text('正在连接弹幕…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(find.text('正在连接弹幕…'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(find.text('正在连接弹幕…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('F-ROOM-15: with 进入直播间自动全屏 on, fullscreen follows 1 s after entry', (tester) async {
    await openRoom(tester, fullscreenDefault: true);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    expect(shown(tester), RoomPresentation.fullscreen);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('F-ROOM-11: switching rooms keeps the page and the surface, and opens the new chat', (tester) async {
    await openRoom(tester);
    final surface = tester.state<PlayerViewState>(find.byType(PlayerView));
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('切换直播间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('观看历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主播2'));
    await tester.pumpAndSettle();

    expect(tester.widget<PlayerView>(find.byType(PlayerView)).detail.ref, RoomRef('douyu', '2'));
    expect(tester.state<PlayerViewState>(find.byType(PlayerView)), same(surface), reason: 'one surface (PS-3)');
    expect(source.feeds, hasLength(2));
    expect(source.feeds.first.closed, isTrue, reason: 'CONN-4: the old room disconnects');
    expect(source.feeds.last.room.ref, RoomRef('douyu', '2'));
  });

  testWidgets('D-12: D hides danmaku on the video and shows it again', (tester) async {
    await openRoom(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(RoomPage)));
    expect(container.read(danmakuPrefsProvider).hidden, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    expect(container.read(danmakuPrefsProvider).hidden, isTrue);
    expect(source.feeds.single.budgets.last.perSecond, 0);
    await tester.pump(const Duration(seconds: 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    expect(container.read(danmakuPrefsProvider).hidden, isFalse);
    await tester.pump(const Duration(seconds: 2));
  });
}
