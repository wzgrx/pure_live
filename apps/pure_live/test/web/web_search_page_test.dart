import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/web/web_engine.dart';
import 'package:pure_live_app/features/search/web_search_page.dart';

import '../accounts/account_fakes.dart';
import '../fakes.dart';
import 'fake_web.dart';

/// An adapter without native search (the shape of some third-batch sites).
final class _NoSearchSite implements LiveSite, LinkResolver {
  new(this.id);

  @override
  final String id;

  @override
  String get name => id;

  @override
  Future<RoomRef?> resolve(String input) async {
    final url = Uri.tryParse(input);
    final segment = url?.pathSegments.firstOrNull;
    if (url == null || url.host != 'picarto.tv' || segment == null || segment == 'search') return null;
    return RoomRef(id, segment.toLowerCase());
  }
}

void main() {
  late FakeWebEngine engine;
  late TextEditingController box;

  Future<void> pumpSearch(
    WidgetTester tester, {
    required Map<String, PlatformSite> sites,
    WebAvailability web = WebAvailability.available,
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    engine = FakeWebEngine(state: web);
    box = TextEditingController();
    addTearDown(box.dispose);
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(
          path: '/search',
          builder: (context, state) => Scaffold(
            appBar: AppBar(
              title: TextField(controller: box),
              actions: [WebSearchButton(keyword: box)],
            ),
          ),
        ),
        GoRoute(
          path: '/web-search',
          builder: (context, state) =>
              WebSearchPage(platform: state.uri.queryParameters['platform']!, keyword: state.uri.queryParameters['q']!),
        ),
        GoRoute(
          path: '/room/:platform/:roomId',
          builder: (context, state) =>
              Text('ROOM ${state.pathParameters['platform']}/${state.pathParameters['roomId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sitesProvider.overrideWithValue(sites),
          enabledPlatformsProvider.overrideWithValue(sites.keys.toList()),
          webEngineProvider.overrideWithValue(engine),
          linkResolverProvider.overrideWithValue((input) async {
            for (final site in sites.values) {
              final room = await site.links.resolve(input);
              if (room != null) return room;
            }
            return null;
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  final nativeOnly = {'douyu': PlatformSite(FakeSite('douyu')), 'huya': PlatformSite(FakeSite('huya'))};
  final withWebOnly = {...nativeOnly, 'picarto': PlatformSite(_NoSearchSite('picarto'))};

  testWidgets('F-SRC-02: no entry while every platform searches natively, or without a browser', (tester) async {
    await pumpSearch(tester, sites: nativeOnly);
    expect(find.byTooltip('网页搜索'), findsNothing);
  });

  testWidgets('F-SRC-02: no entry on a platform without a browser', (tester) async {
    await pumpSearch(tester, sites: withWebOnly, web: WebAvailability.unsupported);
    expect(find.byTooltip('网页搜索'), findsNothing);
  });

  testWidgets('F-SRC-02: Windows without WebView2 explains the install instead of opening', (tester) async {
    await pumpSearch(tester, sites: withWebOnly, web: WebAvailability.missingRuntime);
    await tester.enterText(find.byType(TextField), 'cat');
    await tester.tap(find.byTooltip('网页搜索'));
    await settle(tester);
    expect(find.text('需要 WebView2 运行时'), findsOneWidget);
    expect(engine.pages, isEmpty);
    await tester.tap(find.text('取消'));
    await settle(tester);
  });

  testWidgets('F-SRC-02: a room link opened in the page is offered and opens the room', (tester) async {
    await pumpSearch(tester, sites: withWebOnly);
    await tester.tap(find.byTooltip('网页搜索'));
    await settle(tester);
    expect(find.text('先输入要搜索的关键词'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '猫');
    await tester.tap(find.byTooltip('网页搜索'));
    await settle(tester);
    final page = engine.pages.single;
    expect(page.loads, [Uri.parse('https://picarto.tv/search?q=${Uri.encodeComponent('猫')}')]);
    expect(find.text('网页搜索 · Picarto'), findsOneWidget);

    // Not a room: the page goes on.
    expect(await page.navigate(Uri.parse('https://picarto.tv/search?q=dog')), isTrue);
    // A room: held, and offered.
    expect(await page.navigate(Uri.parse('https://picarto.tv/Alice')), isFalse);
    await settle(tester);
    expect(find.text('识别到直播间'), findsOneWidget);
    expect(find.text('Picarto · alice'), findsOneWidget);
    await tester.tap(find.text('打开直播间'));
    await settle(tester);
    expect(find.text('ROOM picarto/alice'), findsOneWidget);
  });

  testWidgets('F-SRC-02: 留在网页 continues to the page and does not ask again', (tester) async {
    await pumpSearch(tester, sites: withWebOnly);
    await tester.enterText(find.byType(TextField), 'cat');
    await tester.tap(find.byTooltip('网页搜索'));
    await settle(tester);
    final page = engine.pages.single;
    expect(await page.navigate(Uri.parse('https://picarto.tv/Bob')), isFalse);
    await settle(tester);
    await tester.tap(find.text('留在网页'));
    await settle(tester);
    expect(page.loads.last, Uri.parse('https://picarto.tv/Bob'));
    expect(await page.navigate(Uri.parse('https://picarto.tv/Bob')), isTrue);
    await settle(tester);
    expect(find.text('识别到直播间'), findsNothing);
  });

  testWidgets('F-SRC-02: a single-page site that shows a room steps back before the room opens', (tester) async {
    await pumpSearch(tester, sites: withWebOnly);
    await tester.enterText(find.byType(TextField), 'cat');
    await tester.tap(find.byTooltip('网页搜索'));
    await settle(tester);
    final page = engine.pages.single..pushState(Uri.parse('https://picarto.tv/Erin'));
    // The offer comes after the resolution; then the sheet slides in.
    await settle(tester);
    await settle(tester);
    expect(find.text('Picarto · erin'), findsOneWidget);
    await tester.tap(find.text('打开直播间'));
    await settle(tester);
    expect(find.text('ROOM picarto/erin'), findsOneWidget);
    expect(page.history.last.path, '/search', reason: 'the web room page is left');
  });

  testWidgets('F-SRC-02: 本页的房间 lists the room links on the page', (tester) async {
    await pumpSearch(tester, sites: withWebOnly);
    await tester.enterText(find.byType(TextField), 'cat');
    await tester.tap(find.byTooltip('网页搜索'));
    await settle(tester);
    final page = engine.pages.single
      ..scriptResult = jsonEncode(
        jsonEncode(['https://picarto.tv/Carol', '/search?q=x', 'https://picarto.tv/Dave', 'https://picarto.tv/carol']),
      );
    await tester.tap(find.byTooltip('本页的房间'));
    await settle(tester);
    expect(find.text('Picarto · carol'), findsOneWidget);
    expect(find.text('Picarto · dave'), findsOneWidget);
    await tester.tap(find.text('Picarto · dave'));
    await settle(tester);
    expect(find.text('ROOM picarto/dave'), findsOneWidget);
    expect(page.disposed, isFalse, reason: 'the search stays below the room');
  });

  testWidgets('F-SRC-02: a page that fails offers a retry', (tester) async {
    await pumpSearch(tester, sites: withWebOnly);
    await tester.enterText(find.byType(TextField), 'cat');
    await tester.tap(find.byTooltip('网页搜索'));
    await settle(tester);
    engine.pages.single.fail();
    await tester.pump();
    expect(find.text('网页没有打开'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(engine.pages.single.reloads, 1);
  });
}
