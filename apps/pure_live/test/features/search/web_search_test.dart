import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/search/web_search_view.dart';

import '../../support.dart';

void main() {
  setUpAll(loadStrings);

  group('web search route', () {
    late List<Uri> uris;

    setUp(() => uris = []);

    Future<void> show(WidgetTester tester, Object? arguments, {Size size = const Size(393, 852)}) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: const LiveTheme().light,
            home: WebSearchView(
              key: UniqueKey(),
              arguments: arguments,
              inApp: false,
              openExternal: (uri) async {
                uris.add(uri);
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets("3.x's arguments, invalid ones refused", (tester) async {
      await show(tester, {'url': 'ftp://x.test/', 'platform': 'huya'});
      expect(find.byKey(const ValueKey('web-search-invalid')), findsOneWidget);
      expect(find.text('网页搜索暂不可用'), findsOneWidget);
      expect(find.text('网页搜索地址无效，请返回搜索页后重试。'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '关闭'), findsOneWidget);
      expect(WebSearchRequest.parse({'url': 'https://u:p@x.test/', 'platform': 'huya'}), isNull);
      expect(WebSearchRequest.parse({'url': 'https://x.test/', 'platform': 'HUYA', 'keyword': ' a '})?.keyword, 'a');
      expect(uris, isEmpty);
    });

    testWidgets('U.5b c2, c7: the system browser opens at once; the page says how to come back', (tester) async {
      await show(tester, {'url': 'https://www.huya.com/search?hsk=a', 'platform': 'HUYA', 'keyword': 'lol'});
      expect(uris.single.host, 'www.huya.com');
      expect(find.text('网页搜索'), findsOneWidget);
      expect(find.text('虎牙 · lol'), findsOneWidget);
      final title = tester.getRect(find.byKey(const ValueKey('page-title')));
      expect(title.left, lessThan(80), reason: 'two lines on the left');
      expect(find.text('网页搜索在系统浏览器中打开。找到想看的直播间后复制它的链接，回到搜索框粘贴即可直接进入。'), findsOneWidget);
      expect(find.text('www.huya.com'), findsOneWidget);
      expect(find.byKey(const ValueKey('web-search-external')), findsNothing, reason: 'the button below does it');
      expect(find.byKey(const ValueKey('web-search-close')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('web-search-open-external')));
      await tester.pump();
      expect(uris, hasLength(2));
    });

    for (final (width, left, barWidth) in [(393.0, 12.0, 369.0), (852.0, 420.0, 420.0), (1280.0, 816.0, 440.0)]) {
      testWidgets('U.5b c4: the room bar at ${width.toInt()} wide', (tester) async {
        tester.view
          ..physicalSize = Size(width, 800)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final events = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: const LiveTheme().light,
            home: Scaffold(
              body: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    WebSearchRoomBar.place(
                      width: constraints.maxWidth,
                      bar: WebSearchRoomBar(
                        platform: 'bilibili',
                        roomId: '21452505',
                        onEnter: () => events.add('enter'),
                        onDismiss: () => events.add('dismiss'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final bar = tester.getRect(find.byKey(const ValueKey('web-search-room-bar')));
        expect(bar.left, closeTo(left, 0.5));
        expect(bar.width, closeTo(barWidth, 0.5));
        expect(find.text('这是一个直播间'), findsOneWidget);
        expect(find.text('哔哩哔哩 · 房间号 21452505'), findsOneWidget);
        // Logo, words, "进入", ✕ from left to right.
        final logo = tester.getCenter(find.byType(PlatformLogo)).dx;
        final words = tester.getCenter(find.text('这是一个直播间')).dx;
        final enter = tester.getCenter(find.byKey(const ValueKey('web-search-room-enter'))).dx;
        final dismiss = tester.getCenter(find.byKey(const ValueKey('web-search-room-dismiss'))).dx;
        expect(
          [logo, words, enter, dismiss],
          orderedEquals(
            [
              ...[logo, words, enter, dismiss],
            ]..sort(),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('web-search-room-enter')));
        await tester.tap(find.byKey(const ValueKey('web-search-room-dismiss')));
        expect(events, ['enter', 'dismiss']);
      });
    }

    testWidgets('U.5b c6: a page that failed offers retry and the system browser', (tester) async {
      final events = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WebSearchFailure(onRetry: () => events.add('retry'), onOpenExternal: () => events.add('external')),
          ),
        ),
      );
      expect(find.text('网页搜索暂不可用'), findsOneWidget);
      expect(find.byIcon(AppIcons.networkError), findsOneWidget);
      final retry = tester.getRect(find.byKey(const ValueKey('web-search-retry')));
      final external = tester.getRect(find.byKey(const ValueKey('web-search-failed-external')));
      expect(external.top, greaterThan(retry.bottom));
      await tester.tap(find.byKey(const ValueKey('web-search-retry')));
      await tester.tap(find.byKey(const ValueKey('web-search-failed-external')));
      expect(events, ['retry', 'external']);
    });
  });
}
