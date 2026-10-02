// The room's four tabs of U.2e (docs/A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页/README.md): the chat
// list's states, super chats, the settings tab and the block list.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/danmaku/super_chats.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/block_manager.dart';

import '../../support.dart';
import 'live_play_support.dart';

/// A danmaku server that does not answer.
final class _SilentDanmaku implements DanmakuConnection {
  final StreamController<DanmakuEvent> _events = StreamController.broadcast(sync: true);

  /// Connection attempts.
  int connects = 0;

  @override
  DanmakuStatus status = DanmakuStatus.idle;

  @override
  Stream<DanmakuEvent> get events => _events.stream;

  @override
  bool get isConnected => false;

  @override
  Duration get heartbeatInterval => Duration.zero;

  @override
  Future<void> connect(Object? args) {
    connects++;
    status = DanmakuStatus.connecting;
    return Completer<void>().future;
  }

  @override
  void heartbeat() {}

  @override
  Future<void> close() async => status = DanmakuStatus.idle;
}

/// Douyin: no super chats (3.x).
class _DouyinSite extends FakeSite {
  new(super.room);

  @override
  String get id => SiteIds.douyin;
}

final class _Room {
  new(this.services, this.danmaku);

  final AppServices services;
  final DanmakuConnection danmaku;
}

Future<_Room> _pump(
  WidgetTester tester, {
  FakeSite? site,
  double width = 400,
  double height = 900,
  DanmakuConnection? danmaku,
  bool danmakuSupported = true,
  Future<void> Function(LiveStore store)? before,
}) async {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  RoomOrientationChoice.clearSession();
  final services = (await tester.runAsync(testServices))!;
  await tester.runAsync(loadStrings);
  if (before != null) await tester.runAsync(() => before(services.store));
  final previous = AppNavigator.toast;
  AppNavigator.toast = (_) {};
  addTearDown(() => AppNavigator.toast = previous);
  final platform = site ?? FakeSite(liveRoom(startedAt: DateTime.now().subtract(const Duration(minutes: 30))));
  final connection = danmaku ?? FakeDanmaku();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({platform.id: () => platform})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({if (danmakuSupported) platform.id: () => connection})),
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
  await _settle(tester);
  return _Room(services, connection);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Future<void> _close(WidgetTester tester, _Room room) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(room.services.close);
}

Finder _in(String key, Finder finder) => find.descendant(of: find.byKey(ValueKey(key)), matching: finder);

/// [texts] found, top to bottom.
List<String> _topDown(WidgetTester tester, List<String> texts) {
  final found = [
    for (final text in texts)
      if (find.text(text).evaluate().isNotEmpty) text,
  ]..sort((a, b) => tester.getTopLeft(find.text(a).first).dy.compareTo(tester.getTopLeft(find.text(b).first).dy));
  return found;
}

LiveSuperChatMessage _superChat(String name, int price, String top, String bottom, DateTime start, Duration left) =>
    LiveSuperChatMessage(
      userName: name,
      face: '',
      message: '$name 的留言',
      price: price,
      startTime: start,
      endTime: start.add(left),
      backgroundColor: top,
      backgroundBottomColor: bottom,
    );

void main() {
  group('chat list states (c2, c3)', () {
    testWidgets('connecting says so in the middle; the timeout offers to reconnect', (tester) async {
      final danmaku = _SilentDanmaku();
      final room = await _pump(tester, danmaku: danmaku);
      expect(find.byKey(const ValueKey('live-play-chat-connecting')), findsOneWidget);
      expect(_in('live-play-chat-connecting', find.text('开始连接弹幕服务器')), findsOneWidget);
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      expect(find.byKey(const ValueKey('live-play-chat-timeout')), findsOneWidget);
      expect(find.text('弹幕服务器连接超时'), findsOneWidget);
      expect(find.text('已自动释放，可以重新连接'), findsOneWidget);
      await tester.tap(find.text('重新连接'));
      await tester.pump();
      expect(danmaku.connects, 2);
      expect(find.byKey(const ValueKey('live-play-chat-connecting')), findsOneWidget);
      // The second attempt times out as well before the room closes.
      await tester.pump(const Duration(seconds: 31));
      await _close(tester, room);
    });

    testWidgets('connected and quiet, then the first message brings the list (U.2a labels)', (tester) async {
      final room = await _pump(tester);
      expect(find.text('还没有弹幕'), findsOneWidget);
      expect(find.text('弹幕服务器连接正常，新弹幕会显示在这里'), findsOneWidget);
      (room.danmaku as FakeDanmaku).chat('前排', user: '星河');
      await tester.pump();
      expect(find.text('还没有弹幕'), findsNothing);
      expect(find.byKey(const ValueKey('live-play-system-line')), findsWidgets);
      expect(find.byKey(const ValueKey('live-play-chat-line')), findsOneWidget);
      await _close(tester, room);
    });

    testWidgets('a platform without danmaku says so; the other tabs still work', (tester) async {
      final room = await _pump(tester, danmakuSupported: false);
      expect(find.text('哔哩哔哩的直播间没有弹幕'), findsOneWidget);
      expect(find.text('醒目留言、弹幕设置、屏蔽管理照常可用'), findsOneWidget);
      await _close(tester, room);
    });

    testWidgets('display off: the hint and a button that turns it back on', (tester) async {
      final room = await _pump(tester, before: (store) => store.settings.set(Settings.enableDanmakuDisplay, false));
      expect(find.text('全局弹幕显示已关闭'), findsOneWidget);
      expect(find.text('仍可切换到“弹幕设置”调整主播放器和小窗弹幕。'), findsOneWidget);
      await tester.tap(find.text('开启弹幕显示'));
      await _settle(tester);
      expect(room.services.store.settings.get(Settings.enableDanmakuDisplay), isTrue);
      expect(find.text('全局弹幕显示已关闭'), findsNothing);
      await _close(tester, room);
    });

    testWidgets('"N 条新弹幕" uses the ink on the primary colour (c4)', (tester) async {
      final room = await _pump(tester, height: 600);
      final danmaku = room.danmaku as FakeDanmaku;
      for (var i = 0; i < 30; i++) {
        danmaku.chat('第 $i 条');
      }
      await tester.pump();
      await tester.drag(find.byKey(const ValueKey('live-play-chat')), const Offset(0, 300));
      await tester.pump();
      danmaku.chat('新的');
      await tester.pump();
      final button = tester.widget<FilledButton>(find.byKey(const ValueKey('live-play-new-messages')));
      final scheme = Theme.of(tester.element(find.byType(LivePlayPage))).colorScheme;
      expect(button.style?.foregroundColor?.resolve({}), scheme.onPrimary);
      await _close(tester, room);
    });
  });

  group('super chats (c5-c7)', () {
    testWidgets('newest first, ink by contrast, no shadow, one shared clock', (tester) async {
      final now = DateTime.now();
      final site = FakeSite(liveRoom())
        ..superChats = [
          _superChat(
            '清欢',
            50,
            '#DBFFFD',
            '#427D9E',
            now.subtract(const Duration(seconds: 30)),
            const Duration(minutes: 1),
          ),
          _superChat(
            '星河',
            30,
            '#EDF5FF',
            '#2A60B2',
            now.subtract(const Duration(seconds: 20)),
            const Duration(minutes: 2),
          ),
          _superChat(
            '夜猫子',
            100,
            '#FFF1C5',
            '#E2B52B',
            now.subtract(const Duration(seconds: 10)),
            const Duration(minutes: 5),
          ),
        ];
      final room = await _pump(tester, site: site);
      await tester.tap(_in('live-play-tabs', find.text('醒目留言')));
      await tester.pumpAndSettle();
      expect(_topDown(tester, ['夜猫子', '星河', '清欢']), ['夜猫子', '星河', '清欢']);
      // The ￥100 gold takes dark ink (3.x: white at 1.9:1).
      final body = tester.widget<SelectableText>(
        find.descendant(of: find.byKey(const ValueKey('super-chat-body')).first, matching: find.byType(SelectableText)),
      );
      expect(body.style?.color, InkOnColor.ink);
      for (final element in find.byKey(const ValueKey('super-chat-card')).evaluate()) {
        final decoration = (element.widget as DecoratedBox).decoration as BoxDecoration;
        expect(decoration.boxShadow, isNull);
      }
      expect(find.byKey(const ValueKey('super-chat-time')), findsNWidgets(3));
      expect(find.text('SC'), findsNWidgets(3));
      await _close(tester, room);
    });

    testWidgets('a platform without super chats says so (c7)', (tester) async {
      final room = await _pump(tester, site: _DouyinSite(liveRoom()));
      await tester.tap(_in('live-play-tabs', find.text('醒目留言')));
      await tester.pumpAndSettle();
      expect(find.text('暂无醒目留言'), findsOneWidget);
      expect(find.text('抖音的直播间没有醒目留言。'), findsOneWidget);
      await _close(tester, room);
    });

    testWidgets('a narrow column stacks the head (3.x, under 280)', (tester) async {
      final now = DateTime(2026, 10, 1, 21);
      final superChat = _superChat('夜猫子', 100, '#FFF1C5', '#E2B52B', now, const Duration(minutes: 4, seconds: 36));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 290,
              child: SuperChatList(messages: [superChat], now: () => now),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('super-chat-head-stacked')), findsOneWidget);
      expect(find.text('04:36'), findsOneWidget);
      expect(superChatRemaining(superChat, now.add(const Duration(minutes: 5))), '00:00');
    });
  });

  group('settings tab (c8-c10, E1)', () {
    testWidgets('the U.2f component with "改动立即生效" by the first title; list and mini window last', (tester) async {
      final room = await _pump(tester, height: 6000);
      await tester.tap(_in('live-play-tabs', find.text('弹幕设置')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('panel-group-note'))).data, '改动立即生效');
      expect(find.byKey(const ValueKey('room-panel-close')), findsNothing, reason: 'no header in the tab');
      expect(_topDown(tester, ['观看模板', '显示范围', '样式', '重复弹幕', '画面弹幕交互', '流畅度', '弹幕列表样式', '小窗弹幕']), [
        '观看模板',
        '显示范围',
        '样式',
        '重复弹幕',
        '画面弹幕交互',
        '流畅度',
        '弹幕列表样式',
        '小窗弹幕',
      ]);
      // c10: units like the main danmaku's.
      expect(find.byKey(const ValueKey('danmaku-value-pipFontSize')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('danmaku-value-pipFontSize'))).data, '12.0 px');
      expect(tester.widget<Text>(find.byKey(const ValueKey('danmaku-value-pipSpeed'))).data, '90 px/s');
      expect(tester.widget<Text>(find.byKey(const ValueKey('danmaku-value-pipInterval'))).data, '0.35 秒');
      // Kept platform colours grey the colour out instead of hiding it.
      final colour = find.ancestor(
        of: find.byKey(const ValueKey('danmaku-setting-pipColor')),
        matching: find.byType(InkWell),
      );
      expect(tester.widget<InkWell>(colour.first).onTap, isNull);
      await tester.tap(find.byKey(const ValueKey('danmaku-switch-pipOriginalColor')));
      await _settle(tester);
      expect(tester.widget<InkWell>(colour.first).onTap, isNotNull);
      // Mini window danmaku off folds the rest away (3.x).
      await tester.tap(find.byKey(const ValueKey('danmaku-switch-pip')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('danmaku-setting-pipFontSize')), findsNothing);
      expect(room.services.store.settings.get(Settings.enablePipDanmaku), isFalse);
      await _close(tester, room);
    });

    testWidgets("the picture's danmaku settings panel ends with the same two groups (E1 A)", (tester) async {
      final room = await _pump(tester, height: 6000);
      await tester.tap(find.byKey(const ValueKey('live-play-danmaku-settings')));
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('panel-danmaku'));
      expect(find.descendant(of: panel, matching: find.text('小窗显示弹幕')), findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('弹幕列表样式')), findsOneWidget);
      await _close(tester, room);
    });
  });

  group('block list (c11-c16, E3, E4)', () {
    Future<LiveStore> host(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(400, 2000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final services = (await tester.runAsync(testServices))!;
      addTearDown(() => tester.runAsync(services.close));
      await tester.runAsync(loadStrings);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appServicesProvider.overrideWithValue(services)],
          child: MaterialApp(
            theme: const LiveTheme().light,
            home: const Scaffold(body: DanmakuBlockManager()),
          ),
        ),
      );
      await _settle(tester);
      return services.store;
    }

    testWidgets('words first, then viewers, then the filters; empty sections say what goes there', (tester) async {
      await host(tester);
      expect(_topDown(tester, ['弹幕关键词屏蔽', '已屏蔽用户（0）', '平台弹幕过滤', '相似弹幕过滤']), [
        '弹幕关键词屏蔽',
        '已屏蔽用户（0）',
        '平台弹幕过滤',
        '相似弹幕过滤',
      ]);
      expect(find.text('暂无屏蔽关键词'), findsOneWidget);
      expect(find.text('添加关键词后，包含该内容的弹幕将被自动过滤'), findsOneWidget);
      expect(find.text('还没有屏蔽的用户；长按弹幕可屏蔽发送者'), findsOneWidget);
      // c16: the similarity sliders are greyed out while it is off.
      final slider = tester.widget<Slider>(find.byKey(const ValueKey('danmaku-slider-similarityThreshold')));
      expect(slider.onChanged, isNull);
    });

    testWidgets('add, a duplicate is said under the field and kept; remove with undo', (tester) async {
      final store = await host(tester);
      await tester.enterText(find.byKey(const ValueKey('live-play-block-input')), '剧透');
      await tester.tap(find.byKey(const ValueKey('live-play-block-add')));
      await _settle(tester);
      expect(await tester.runAsync(() => store.blockLists.list(BlockKind.keyword)), ['剧透']);
      expect(find.byKey(const ValueKey('block-chip-keyword-剧透')), findsOneWidget);
      expect(find.text('已添加1个关键词'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('live-play-block-input')), '剧透');
      await tester.tap(find.byKey(const ValueKey('live-play-block-add')));
      await _settle(tester);
      expect(find.text('“剧透”已经在屏蔽列表里'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('live-play-block-input'))).controller?.text, '剧透');

      // Only the × removes (a 48-high target), and it can be undone.
      expect(tester.getSize(find.byKey(const ValueKey('block-chip-remove-剧透'))).height, 48);
      await tester.tap(find.text('剧透').last);
      await _settle(tester);
      expect(await tester.runAsync(() => store.blockLists.list(BlockKind.keyword)), ['剧透']);
      await tester.tap(find.byKey(const ValueKey('block-chip-remove-剧透')));
      await _settle(tester);
      expect(await tester.runAsync(() => store.blockLists.list(BlockKind.keyword)), isEmpty);
      expect(find.text('已移除“剧透”'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('撤销'));
      await _settle(tester);
      expect(await tester.runAsync(() => store.blockLists.list(BlockKind.keyword)), ['剧透']);
    });
  });

  group('wide and landscape (c17)', () {
    testWidgets('1280 x 800 and a phone held sideways put the tabs in the right column', (tester) async {
      for (final size in const [Size(1280, 800), Size(852, 393)]) {
        final room = await _pump(tester, width: size.width, height: size.height);
        expect(find.byKey(const ValueKey('live-play-desktop-split')), findsOneWidget, reason: '$size');
        final tabs = tester.getRect(find.byKey(const ValueKey('live-play-tabs')));
        expect(tabs.left, greaterThan(size.width / 2), reason: '$size');
        await _close(tester, room);
      }
    });
  });
}
