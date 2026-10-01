import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/toolbox/toolbox_actions.dart';
import 'package:pure_live/features/toolbox/toolbox_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/links/supported_platforms.dart';

import '../../support.dart';

/// A Douyu room with two qualities and two lines.
final class _FakeSite extends LiveSite {
  int details = 0;

  @override
  String get id => SiteIds.douyu;

  @override
  String get name => 'Douyu';

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    details++;
    return LiveRoom(
      platform: id,
      roomId: roomId,
      watching: '',
      liveStatus: roomId == '404' ? LiveStatus.offline : LiveStatus.live,
    );
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async => const [
    LivePlayQuality(quality: '原画'),
    LivePlayQuality(quality: '高清'),
  ];

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async => [
    'https://line1.example/${quality.quality}.flv',
    'https://line2.example/${quality.quality}.flv',
  ];
}

final class _Harness {
  new(this.toasts, this.copied, this.site);

  final List<String> toasts;
  final List<String> copied;
  final _FakeSite site;
}

Future<_Harness> _pump(WidgetTester tester, {String? clipboard, Size size = const Size(420, 900)}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  addTearDown(() => tester.runAsync(services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  final toasts = <String>[];
  final previousToast = AppNavigator.toast;
  AppNavigator.toast = toasts.add;
  addTearDown(() => AppNavigator.toast = previousToast);
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  final site = _FakeSite();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const ToolboxPage(route: RouteArgs(RoutePath.kToolbox)),
      ),
      GoRoute(
        path: RoutePath.kLivePlay,
        builder: (_, state) {
          final room = state.extra! as LiveRoom;
          return Scaffold(body: Text('room ${room.platform} ${room.roomId}'));
        },
      ),
    ],
  );
  AppNavigator.router = router;
  addTearDown(() => AppNavigator.router = null);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        toolboxClipboardProvider.overrideWithValue(() async => clipboard),
        toolboxSiteProvider.overrideWithValue((platform) => platform == SiteIds.douyu ? site : null),
      ],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp.router(
          theme: const LiveTheme(primaryColor: Colors.blue).light,
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(toasts, copied, site);
}

Future<void> _enter(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('toolbox-link')), text);
  await tester.pump();
}

/// Lets the platform calls (real futures) finish, then the frames (a
/// running action spins, so frames are pumped for a while, not settled).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  testWidgets('opens the room of a link', (tester) async {
    await _pump(tester);
    await _enter(tester, '快来看 https://www.douyu.com/9999。');
    await tester.tap(find.byKey(const ValueKey('toolbox-jump')));
    await _settle(tester);
    expect(find.text('room douyu 9999'), findsOneWidget);
    // The navigator's double-tap guard.
    await tester.pump(AppNavigator.openGuard);
  });

  testWidgets('copies a stream address after choosing quality and line', (tester) async {
    final harness = await _pump(tester);
    await _enter(tester, 'https://www.douyu.com/9999');
    await tester.tap(find.byKey(const ValueKey('toolbox-direct-link')));
    await _settle(tester);
    expect(find.text('选择清晰度'), findsOneWidget);
    await tester.tap(find.text('高清'));
    await _settle(tester);
    expect(find.text('选择线路'), findsOneWidget);
    await tester.tap(find.text('线路2'));
    await _settle(tester);
    expect(harness.copied, ['https://line2.example/高清.flv']);
    expect(harness.toasts.last, '已复制直链');
  });

  testWidgets('cancelling the choice ends the action quietly', (tester) async {
    final harness = await _pump(tester);
    await _enter(tester, 'https://www.douyu.com/9999');
    await tester.tap(find.byKey(const ValueKey('toolbox-direct-link')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('toolbox-cancel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('toolbox-choice-cancel')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('toolbox-choice-dialog')), findsNothing);
    expect(find.byKey(const ValueKey('toolbox-cancel')), findsNothing);
    expect(harness.copied, isEmpty);
    expect(harness.toasts, isEmpty);
  });

  testWidgets('tells why a link gives nothing', (tester) async {
    final harness = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('toolbox-jump')));
    await _settle(tester);
    expect(harness.toasts.last, '链接不能为空');

    await _enter(tester, 'https://example.com/nothing');
    await tester.tap(find.byKey(const ValueKey('toolbox-jump')));
    await _settle(tester);
    expect(harness.toasts.last, '无法解析此链接');

    await _enter(tester, 'https://rumble.com/someone');
    await tester.tap(find.byKey(const ValueKey('toolbox-jump')));
    await _settle(tester);
    expect(harness.toasts.last, contains('已下线'));

    await _enter(tester, 'https://www.douyu.com/404');
    await tester.tap(find.byKey(const ValueKey('toolbox-direct-link')));
    await _settle(tester);
    expect(harness.toasts.last, '主播未开播，没有直播流地址');
  });

  testWidgets('fills the empty box from the clipboard and lists the platforms', (tester) async {
    final harness = await _pump(tester, clipboard: 'https://live.bilibili.com/123');
    await _settle(tester);
    final field = tester.widget<TextField>(find.byKey(const ValueKey('toolbox-link')));
    expect(field.controller!.text, 'https://live.bilibili.com/123');
    expect(harness.toasts, ['已自动填充剪贴板中的直播链接']);

    await tester.tap(find.byKey(const ValueKey('toolbox-supported')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('toolbox-platform-bilibili')), findsOneWidget);
    expect(find.byKey(const ValueKey('toolbox-platform-iptv')), findsNothing);
  });

  testWidgets('portrait: group title outside the card, one box, two buttons side by side, list folded', (tester) async {
    await _pump(tester);
    // c3: the group title sits above the card, the explanation inside it.
    final title = tester.getRect(find.text('平台链接'));
    final card = tester.getRect(find.byKey(const ValueKey('toolbox-link-card')));
    final box = tester.getRect(find.byKey(const ValueKey('toolbox-link')));
    expect(title.bottom, lessThan(box.top));
    expect(find.text('粘贴直播间链接或分享文字，可以直接打开直播间，也可以获取直播流地址'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    // c5: paste while empty.
    expect(find.byKey(const ValueKey('toolbox-paste')), findsOneWidget);
    expect(find.byKey(const ValueKey('toolbox-clear')), findsNothing);
    expect(
      find.descendant(of: find.byKey(const ValueKey('toolbox-paste')), matching: find.byIcon(AppIcons.pasteText)),
      findsOneWidget,
    );
    // c2: "链接跳转" (filled) left of "获取直链" (tonal), on one row under the box.
    final jump = tester.getRect(find.byKey(const ValueKey('toolbox-jump')));
    final link = tester.getRect(find.byKey(const ValueKey('toolbox-direct-link')));
    expect(jump.top, greaterThan(box.bottom));
    expect(jump.top, link.top);
    expect(jump.right, lessThan(link.left));
    expect(jump.height, greaterThanOrEqualTo(48));
    expect(
      find.descendant(of: find.byKey(const ValueKey('toolbox-jump')), matching: find.byIcon(AppIcons.linkJump)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('toolbox-direct-link')),
        matching: find.byIcon(AppIcons.streamLink),
      ),
      findsOneWidget,
    );
    expect(find.text('链接跳转'), findsOneWidget);
    expect(find.text('获取直链'), findsOneWidget);
    // c4: the supported list is its own card under it, folded.
    final supported = tester.getRect(find.byKey(const ValueKey('toolbox-supported')));
    expect(supported.top, greaterThan(card.bottom));
    expect(find.text('支持解析列表'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^共 \d+ 个平台$')), findsOneWidget);
    expect(find.byKey(const ValueKey('toolbox-platform-douyu')), findsNothing);
    // 393 wide: the content fills the width less the gutters.
    expect(card.left, 16);
    expect(card.width, 420 - 32);

    // Typing turns "paste" into "clear", which empties the box.
    await _enter(tester, 'https://www.douyu.com/9999');
    expect(find.byKey(const ValueKey('toolbox-paste')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('toolbox-clear')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('toolbox-link'))).controller!.text, isEmpty);
  });

  testWidgets('while busy the buttons are off and a line says what is done, with cancel', (tester) async {
    final harness = await _pump(tester);
    await _enter(tester, 'https://www.douyu.com/9999');
    await tester.tap(find.byKey(const ValueKey('toolbox-direct-link')));
    await _settle(tester);
    // The quality dialog is open; behind it the page says what it does.
    expect(find.text('正在读取直播流地址…'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('toolbox-jump'))).onPressed, isNull);
    // c8: a 20 px title, options at the start, each at least 56 high.
    final dialogTitle = tester.widget<Text>(find.text('选择清晰度'));
    expect(dialogTitle.style!.fontSize, 20);
    final first = tester.getRect(find.byKey(const ValueKey('toolbox-choice-0')));
    final dialog = tester.getRect(find.byKey(const ValueKey('toolbox-choice-dialog')));
    expect(first.height, greaterThanOrEqualTo(56));
    expect(tester.getTopLeft(find.text('原画')).dx - first.left, 24);
    expect(tester.getCenter(find.text('原画')).dx, lessThan(dialog.center.dx));
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    await tester.tap(find.text('高清'));
    await _settle(tester);
    // The line's address is one line.
    final address = tester.widget<Text>(find.text('https://line1.example/高清.flv'));
    expect(address.maxLines, 1);
    expect(address.overflow, TextOverflow.ellipsis);
    // Cancelling the choice ends the action and the busy line.
    await tester.tap(find.byKey(const ValueKey('toolbox-choice-cancel')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('toolbox-busy')), findsNothing);
    expect(harness.copied, isEmpty);
  });

  testWidgets('landscape phone and wide window: one column at most 720, centred', (tester) async {
    await _pump(tester, size: const Size(852, 393));
    var card = tester.getRect(find.byKey(const ValueKey('toolbox-link-card')));
    expect(card.width, 720);
    expect(card.center.dx, 426);
    // A short window gets the compact app bar of the settings pages.
    expect(tester.getSize(find.byType(AppBar)).height, 48);
    final jump = tester.getRect(find.byKey(const ValueKey('toolbox-jump')));
    final link = tester.getRect(find.byKey(const ValueKey('toolbox-direct-link')));
    expect(jump.top, link.top);

    await _pump(tester, size: const Size(1280, 800));
    card = tester.getRect(find.byKey(const ValueKey('toolbox-link-card')));
    expect(card.width, 720);
    expect(card.center.dx, 640);
    final supported = tester.getRect(find.byKey(const ValueKey('toolbox-supported')));
    expect(supported.width, 720);
    expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
  });

  test('the platform list has the platforms with link rules only', () async {
    final services = await testServices();
    addTearDown(services.close);
    final ids = [for (final site in linkPlatforms(services.sites)) site.id];
    expect(ids, contains(SiteIds.douyu));
    expect(ids, isNot(contains(SiteIds.iptv)));
    expect(ids, isNot(contains('huajiao')));
  });
}
