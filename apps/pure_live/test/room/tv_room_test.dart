import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/network.dart';
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
import 'package:pure_live_app/features/room/room_switch.dart';
import 'package:pure_live_app/features/room/tv_room.dart';

import '../danmaku/fake_danmaku.dart';

final class _QuietSite implements RoomSource, StreamSource {
  @override
  Future<RoomDetail> detail(RoomRef ref) async => liveRoom(id: ref.roomId);

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) => Completer<StreamSet>().future;
}

/// The room page on a remote (live-room §3.5, principles §6.3) and the
/// keyboard's PageUp and PageDown (§6.2).
void main() {
  RoomEntry entry(String id) => RoomEntry(RoomRef('douyu', id), name: '主播$id');

  FollowedRoom follow(String id, int online) => FollowedRoom(
    room: StoredRoom(
      ref: RoomRef('douyu', id),
      anchorName: '主播$id',
      title: '标题$id',
      updatedAt: DateTime(2026),
      audience: Audience(online: online),
      lastState: LiveState.live,
    ),
    followedAt: DateTime(2026),
    order: 0,
  );

  Future<void> openRoom(
    WidgetTester tester, {
    RoomOrigin? origin,
    List<FollowedRoom> follows = const [],
    bool tv = true,
  }) async {
    tester.view.physicalSize = tv ? const Size(960, 540) : const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    final session = PlaybackSession(engine: () => throw UnimplementedError('no engine in widget tests'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          sitesProvider.overrideWithValue({'douyu': PlatformSite(_QuietSite())}),
          roomDetailProvider.overrideWith((ref, room) async => liveRoom(id: room.roomId)),
          isFollowedProvider.overrideWith((ref, room) => Stream.value(false)),
          danmakuSourceProvider.overrideWithValue(FakeDanmakuSource()),
          blockRulesProvider.overrideWith((ref) => Stream.value(const [])),
          playbackSessionProvider.overrideWith((ref) => session),
          followsProvider.overrideWith((ref) => Stream.value(follows)),
          // This run already checked the follows (F-FAV-03).
          followRefreshProvider.overrideWith(_Checked.new),
          historyProvider.overrideWith((ref) => Stream.value(const [])),
          // Real time passes while a picture is captured: no platform network state.
          networkKindProvider.overrideWith((ref) => Stream.value(NetworkKind.unmetered)),
        ],
        child: MaterialApp(
          theme: tv ? PureTheme.tv(Appearance.dark) : PureTheme.of(Appearance.light),
          builder: (context, child) => TvRoot(
            config: TvConfig(enabled: tv),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RoomPage(room: RoomRef('douyu', '1'), origin: origin),
                    ),
                  ),
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

  PlayerView player(WidgetTester tester) => tester.widget<PlayerView>(find.byType(PlayerView));
  String showing(WidgetTester tester) => player(tester).detail.ref.roomId;
  TvRoomLayerState layer(WidgetTester tester) => tester.state<TvRoomLayerState>(find.byType(TvRoomLayer));

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('TV-01, TV-02: always fullscreen; up and down, CH+ and CH− step through the list without wrapping', (
    tester,
  ) async {
    await openRoom(tester, origin: RoomOrigin([entry('1'), entry('2'), entry('3')], label: '推荐'));
    expect(player(tester).presentation, RoomPresentation.fullscreen);
    expect(player(tester).tv, isTrue);
    expect(find.byTooltip('全屏 (F)'), findsNothing, reason: 'no touch bars on TV');

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(showing(tester), '2');
    expect(find.textContaining('主播2  2/3'), findsOneWidget, reason: 'the switch hint');
    await press(tester, LogicalKeyboardKey.channelDown);
    expect(showing(tester), '3');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(showing(tester), '3', reason: 'the end holds');
    expect(find.text('已经是最后一个了'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.channelUp);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(showing(tester), '1');
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(showing(tester), '1');
    expect(find.text('已经是第一个了'), findsOneWidget);

    // TV-06: nothing open, back leaves the room.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(RoomPage), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('TV-03..TV-06: left lists the rooms, right the settings, OK the control row; back closes each first', (
    tester,
  ) async {
    await openRoom(tester, origin: RoomOrigin([entry('1'), entry('2'), entry('3')], label: '推荐'));

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(layer(tester).panel, TvPanel.rooms);
    expect(find.text('推荐'), findsOneWidget);
    expect(find.text('正在看'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.select);
    expect(showing(tester), '3', reason: 'OK on a listed room switches to it');
    expect(layer(tester).panel, TvPanel.none);

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(layer(tester).panel, TvPanel.settings);
    expect(find.text('播放设置'), findsOneWidget);
    expect(find.text('画面比例'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(layer(tester).panel, TvPanel.none, reason: 'back closes the panel first');
    expect(find.byType(RoomPage), findsOneWidget);

    // A long OK opens the settings as well (no menu key on new remotes).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(layer(tester).panel, TvPanel.settings);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(layer(tester).panel, TvPanel.none, reason: 'the opposite arrow closes a panel');

    await press(tester, LogicalKeyboardKey.select);
    expect(layer(tester).controlsVisible, isTrue);
    expect(find.text('刷新'), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget, reason: 'the place in the list');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(showing(tester), '3', reason: 'with the control row up, the D-pad moves between buttons');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(layer(tester).controlsVisible, isFalse, reason: 'back hides the control row first');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(RoomPage), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('T-05: without a list of its own the room steps through the live follows by audience', (tester) async {
    await openRoom(tester, follows: [follow('small', 10), follow('1', 300), follow('big', 900)]);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(showing(tester), 'big');
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(showing(tester), 'small');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('TV-04: the control row keeps inside the safe margins and scrolls to the focused button', (tester) async {
    await openRoom(tester, origin: RoomOrigin([for (var i = 1; i <= 8; i++) entry('$i')], label: '推荐'));
    await press(tester, LogicalKeyboardKey.select);
    expect(layer(tester).controlsVisible, isTrue);
    const right = 960 - TvMetrics.safeX;
    // "1 / 8" ends at the right margin, not halfway along the row.
    expect(tester.getRect(find.byKey(const ValueKey('tv-room-position'))).right, closeTo(right, 0.5));
    final row = find.byKey(const ValueKey('tv-room-buttons'));
    expect(tester.getRect(row).left, TvMetrics.safeX);
    expect(tester.getRect(row).right, closeTo(right, 0.5));
    expect(tester.widget<SingleChildScrollView>(row).clipBehavior, isNot(Clip.none), reason: 'nothing past the margin');
    // Seven buttons do not fit: each one the D-pad reaches is shown whole.
    final buttons = find.descendant(of: row, matching: find.byType(FilledButton));
    expect(buttons, findsNWidgets(7));
    for (var i = 0; i < 6; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
      final rect = FocusManager.instance.primaryFocus!.rect;
      expect(rect.left, greaterThanOrEqualTo(TvMetrics.safeX - 0.5), reason: 'button ${i + 2}');
      expect(rect.right, lessThanOrEqualTo(right + 0.5), reason: 'button ${i + 2}');
    }
    await tester.pump(const Duration(seconds: 5));
  });

  group('on a white frame', () {
    setUp(() => debugPictureBackground = Colors.white);
    tearDown(() => debugPictureBackground = Colors.black);

    testWidgets('principles §2.2: the info bar sits on 60% black to the bottom edge', (tester) async {
      await openRoom(tester, origin: RoomOrigin([entry('1'), entry('2')], label: '推荐'));
      await press(tester, LogicalKeyboardKey.select);
      final bar = find.byKey(const ValueKey('tv-room-bar'));
      final image = (await tester.runAsync(() => captureImage(tester.element(bar))))!;
      final bytes = (await tester.runAsync(image.toByteData))!;
      Color at(double x, double y) {
        final offset = (y.floor() * image.width + x.floor()) * 4;
        return Color.fromARGB(255, bytes.getUint8(offset), bytes.getUint8(offset + 1), bytes.getUint8(offset + 2));
      }

      expect(at(480, 100), Colors.white, reason: 'the picture above the bar stays clear');
      final rect = tester.getRect(bar);
      // In the side margin, beside the name, the title and the buttons, and
      // below them to the edge.
      for (final y in [rect.top + 1, rect.center.dy, rect.bottom - 1, 539.0]) {
        expect(at(20, y), const Color(0xFF666666), reason: 'at $y');
      }
      image.dispose();
      await tester.pump(const Duration(seconds: 5));
    });
  });

  testWidgets('§6.2: PageDown and PageUp switch rooms on a keyboard too', (tester) async {
    await openRoom(tester, origin: RoomOrigin([entry('1'), entry('2')]), tv: false);
    expect(player(tester).presentation, RoomPresentation.inline);
    await press(tester, LogicalKeyboardKey.pageDown);
    expect(showing(tester), '2');
    await press(tester, LogicalKeyboardKey.pageUp);
    expect(showing(tester), '1');
    await tester.pump(const Duration(seconds: 5));
  });
}

/// A first refresh that already finished.
class _Checked extends FollowRefreshNotifier {
  @override
  Future<FollowRefreshResult?> build() async =>
      FollowRefreshResult(checked: 1, failedPlatforms: const {}, at: DateTime(2020));
}
