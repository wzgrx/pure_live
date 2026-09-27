import 'package:flutter/material.dart' hide Page;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/testing.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/app/app.dart';
import 'package:pure_live_app/core/engine.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/danmaku/danmaku_preferences.dart';
import 'package:pure_live_app/features/danmaku/danmaku_source.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/room/room_page.dart';
import 'package:pure_live_app/features/search/search_page.dart';

import 'danmaku/fake_danmaku.dart';
import 'fakes.dart';

/// A refresh that finishes at once; widget tests run on a fake clock where the
/// database's real asynchronous work never completes.
class _NoRefresh extends FollowRefreshNotifier {
  @override
  Future<FollowRefreshResult?> build() async => null;
}

void main() {
  test('link detection', () {
    expect(looksLikeLink('https://www.douyu.com/288016'), isTrue);
    expect(looksLikeLink('复制打开抖音 v.douyin.com/abc'), isTrue);
    expect(looksLikeLink('英雄联盟'), isFalse);
    expect(looksLikeLink('288016'), isFalse);
  });

  testWidgets('starts on 关注, discovers rooms and opens one', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sites = {
      for (final id in platformOrder)
        id: PlatformSite(
          FakeSite(
            id,
            pages: [
              Page([FakeSite(id).card('$id-1')]),
            ],
          ),
        ),
    };
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sitesProvider.overrideWithValue(sites),
          storeProvider.overrideWithValue(store),
          recordManagerProvider.overrideWithValue(fakeRecordManager()),
          engineFactoryProvider.overrideWithValue(FakeEngine.new),
          followsProvider.overrideWith((ref) => Stream.value(const [])),
          followRefreshProvider.overrideWith(_NoRefresh.new),
          isFollowedProvider.overrideWith((ref, room) => Stream.value(false)),
          roomDetailProvider.overrideWith((ref, room) => sites[room.platform]!.rooms.detail(room)),
          // The room page connects chat: no worker isolate and no drift
          // streams on the fake clock.
          danmakuSourceProvider.overrideWithValue(FakeDanmakuSource()),
          blockRulesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const PureLiveApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有关注的主播'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('去发现'));
    await tester.pumpAndSettle();
    expect(find.text('主播bilibili-1'), findsOneWidget);

    await tester.tap(find.text('主播bilibili-1'));
    // The room plays now (fake engine): a buffering spinner animates, so pump
    // for a while instead of waiting for the tree to settle.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    // Compact width: video on top, chat first, room info in the second tab.
    await tester.tap(find.text('直播间'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('标题bilibili-1'), findsWidgets);
    expect(find.text('打开原站'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('§6.2: Ctrl+F opens search with its box focused', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sitesProvider.overrideWithValue({for (final id in platformOrder) id: PlatformSite(FakeSite(id))}),
          storeProvider.overrideWithValue(store),
          recordManagerProvider.overrideWithValue(fakeRecordManager()),
          followsProvider.overrideWith((ref) => Stream.value(const [])),
          followRefreshProvider.overrideWith(_NoRefresh.new),
        ],
        child: const PureLiveApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);
    final bar = tester.widget<SearchBar>(find.byType(SearchBar));
    expect(bar.focusNode!.hasFocus, isTrue);
  });
}
