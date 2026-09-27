import 'package:flutter/material.dart' hide Page;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/testing.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/app.dart';
import 'package:pure_live_app/core/engine.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/core/tv.dart';
import 'package:pure_live_app/features/danmaku/danmaku_preferences.dart';
import 'package:pure_live_app/features/danmaku/danmaku_source.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/follows/follows_page.dart';
import 'package:pure_live_app/features/follows/groups.dart';
import 'package:pure_live_app/features/room/player_view.dart';
import 'package:pure_live_app/features/room/room_page.dart';

import '../danmaku/fake_danmaku.dart';
import '../fakes.dart';

class _NoRefresh extends FollowRefreshNotifier {
  @override
  Future<FollowRefreshResult?> build() async => null;
}

/// The whole app on a TV (principles §5.3, §6.3): the rail shell on the
/// 960×540 canvas, the follows grid under the remote, a room opened with OK
/// that switches through the live follows, and focus back on the card.
void main() {
  testWidgets('a TV starts in TV mode: rail, dark theme, 4-column grid, rooms by remote and back to the card', (
    tester,
  ) async {
    // A box that reports 1920×1080 logical pixels: scaled to the canvas.
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    final site = FakeSite('douyu');
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
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
    // Audience order: r1 … r6.
    final follows = [for (var i = 1; i <= 6; i++) follow('r$i', 1000 - i)];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tvDeviceProvider.overrideWithValue(const TvDevice(television: true)),
          sitesProvider.overrideWithValue({for (final id in platformOrder) id: PlatformSite(FakeSite(id))}),
          storeProvider.overrideWithValue(store),
          recordManagerProvider.overrideWithValue(fakeRecordManager()),
          engineFactoryProvider.overrideWithValue(FakeEngine.new),
          followsProvider.overrideWith((ref) => Stream.value(follows)),
          tagsProvider.overrideWith((ref) => Stream.value(const [])),
          followRefreshProvider.overrideWith(_NoRefresh.new),
          isFollowedProvider.overrideWith((ref, room) => Stream.value(true)),
          roomDetailProvider.overrideWith((ref, room) => site.detail(room)),
          danmakuSourceProvider.overrideWithValue(FakeDanmakuSource()),
          blockRulesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const PureLiveApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TvNavScaffold), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final page = tester.element(find.byType(FollowsPage));
    expect(MediaQuery.sizeOf(page), const Size(960, 540), reason: 'the canvas');
    expect(Theme.of(page).brightness, Brightness.dark);
    expect(find.byType(RoomCardView), findsNWidgets(6));
    final first = tester.getRect(find.byType(RoomCardView).at(0));
    final fifth = tester.getRect(find.byType(RoomCardView).at(4));
    expect(fifth.top, greaterThan(first.bottom), reason: 'four columns: the fifth card starts the second row');

    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    expect(focused(), 'tv-rail-0', reason: 'the remote starts on the rail');
    await press(LogicalKeyboardKey.arrowRight);
    await press(LogicalKeyboardKey.arrowDown);
    expect(focused(), 'follows-grid-0');
    await press(LogicalKeyboardKey.arrowRight);
    await press(LogicalKeyboardKey.arrowDown);
    expect(focused(), 'follows-grid-5', reason: 'down into the short second row');

    // OK opens the room: fullscreen, and down steps to the next live follow.
    await press(LogicalKeyboardKey.select);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(RoomPage), findsOneWidget);
    PlayerView player() => tester.widget<PlayerView>(find.byType(PlayerView));
    expect(player().detail.ref.roomId, 'r6');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(player().detail.ref.roomId, 'r5');

    // Back leaves the room and focus is on the card the room was opened from.
    await tester.binding.handlePopRoute();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(RoomPage), findsNothing);
    expect(focused(), 'follows-grid-5');
    await tester.pump(const Duration(seconds: 5));
  });
}
