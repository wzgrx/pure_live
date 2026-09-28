import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/error_view.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/rooms/card_marks.dart';
import 'package:pure_live_app/features/rooms/room_grid.dart';
import 'package:pure_live_app/features/search/search_empty.dart';

import 'fakes.dart';
import 'icon_finder.dart';

/// Loading, empty and error states of the design review (principles §2.5,
/// §3.3, §7.8).
void main() {
  Widget themed(Widget child) => MaterialApp(
    theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
    home: Scaffold(body: child),
  );

  group("errors in the user's words", () {
    test('an unclassified error never shows its own text', () {
      final text = describeError(StateError('Bad state: https://api.example/secret?token=1'));
      expect(text.title, '出错了');
      expect(text.message, isNot(contains('Bad state')));
      expect(text.message, contains('诊断包'));
      expect(text.retryable, isTrue);
    });

    testWidgets('a network failure shows the broken antenna and 重试', (tester) async {
      var retried = 0;
      await tester.pumpWidget(themed(ErrorView(const NetworkFailure('douyu', 'reset'), onRetry: () => retried++)));
      expect(tester.widget<IllustrationView>(find.byType(IllustrationView)).illustration, Illustration.offline);
      expect(find.text('网络连接失败'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(retried, 1);
    });

    testWidgets('a missing room is not retried; a page title replaces the described one', (tester) async {
      await tester.pumpWidget(themed(ErrorView(const NotFound('douyu'), title: '读取失败', onRetry: () {})));
      expect(tester.widget<IllustrationView>(find.byType(IllustrationView)).illustration, Illustration.error);
      expect(find.text('读取失败'), findsOneWidget);
      expect(find.text('房间号可能已经失效，或者主播换了房间。'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
    });

    testWidgets('compact error views in sheets keep the small icon', (tester) async {
      await tester.pumpWidget(themed(const ErrorView(NetworkFailure('douyu'), compact: true)));
      expect(find.byType(IllustrationView), findsNothing);
      expect(findIcon(LiveIcons.error), findsOneWidget);
    });
  });

  testWidgets("principles §7.8: the loading skeleton has the grid's geometry, so cards land where blocks were", (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    Future<List<Rect>> covers(Widget grid) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeProvider.overrideWithValue(store),
            recordingRoomsProvider.overrideWith((ref) => Stream.value(const {})),
          ],
          child: themed(grid),
        ),
      );
      await tester.pump();
      return [
        for (final element in find.byType(AspectRatio).evaluate().take(4))
          tester.getRect(find.byWidget(element.widget)),
      ];
    }

    final skeleton = await covers(const RoomGridSkeleton());
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final site = FakeSite('douyu');
    final cards = await covers(
      RoomCardGrid(
        items: [for (var i = 0; i < 6; i++) site.card('10$i')],
        hasMore: false,
        onLoadMore: () {},
        onRefresh: () async {},
      ),
    );
    expect(skeleton, cards);
  });

  group('search without results', () {
    Future<GoRouter> pumpSearch(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: '/empty',
        routes: [
          GoRoute(
            path: '/empty',
            builder: (context, state) => const Scaffold(body: SearchEmptyView()),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => Scaffold(body: Text('搜索 ${state.uri.queryParameters['q'] ?? ''}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
          routerConfig: router,
        ),
      );
      return router;
    }

    testWidgets('suggests the spelling, another platform and 粘贴链接', (tester) async {
      await pumpSearch(tester);
      expect(tester.widget<IllustrationView>(find.byType(IllustrationView)).illustration, Illustration.noResults);
      expect(find.text('没有找到相关的直播间'), findsOneWidget);
      expect(find.textContaining('错字'), findsOneWidget);
      expect(find.textContaining('换个平台'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '粘贴链接'), findsOneWidget);
    });

    testWidgets('粘贴链接 with an empty clipboard opens search and says why', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpSearch(tester);
      await tester.tap(find.text('粘贴链接'));
      await tester.pumpAndSettle();
      expect(find.text('搜索 '), findsOneWidget);
      expect(find.textContaining('剪贴板里没有文字'), findsOneWidget);
    });
  });
}
