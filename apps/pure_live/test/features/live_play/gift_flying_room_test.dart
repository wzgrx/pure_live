// A08.12 (docs/A-界面设计/A08-弹幕界面/A08.12-礼物开关和飞行弹幕里的礼物): "飞行弹幕显示礼物" in the
// room: the valuable gifts fly over the picture upright and in the landscape
// fullscreen, clear of the controls' bars; off (the default) none does.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/player/player_controls.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

import '../../support.dart';
import 'live_play_support.dart';

final class _Room {
  new(this.services, this.danmaku);

  final AppServices services;
  final FakeDanmaku danmaku;
}

LiveMessage _gift(String user, String name, int goldSeeds, {String id = ''}) {
  final gift = LiveGift(name: name, id: name, totalValue: goldSeeds, unit: LiveGiftUnit.goldSeed);
  return LiveMessage(
    type: LiveMessageType.gift,
    userName: user,
    userId: user,
    message: gift.plainText,
    color: LiveMessageColor.white,
    messageId: id,
    data: gift,
  );
}

Future<_Room> _pump(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  Map<Setting<Object>, Object> settings = const {},
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  RoomOrientationChoice.clearSession();
  final services = (await tester.runAsync(testServices))!;
  await tester.runAsync(loadStrings);
  for (final MapEntry(:key, :value) in settings.entries) {
    await tester.runAsync(() => services.store.settings.set(key, value));
  }
  final danmaku = FakeDanmaku();
  final previous = AppNavigator.toast;
  AppNavigator.toast = (_) {};
  addTearDown(() => AppNavigator.toast = previous);
  final site = FakeSite(liveRoom(startedAt: DateTime.now().subtract(const Duration(minutes: 30))));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => site})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: () => danmaku})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(FakeEngine())),
      ],
      child: MaterialApp(
        theme: const LiveTheme().light,
        home: LivePlayPage(
          route: RouteArgs(
            RoutePath.kLivePlay,
            arguments: LiveRoom(platform: SiteIds.bilibili, roomId: '6', nick: '主播'),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return _Room(services, danmaku);
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
  debugDefaultTargetPlatformOverride = null;
}

DanmakuOverlayState _layer(WidgetTester tester) => tester.state(find.byType(DanmakuOverlay));

DanmakuOverlay _overlay(WidgetTester tester) => tester.widget(find.byType(DanmakuOverlay));

/// The flying gifts and where they are.
List<(String, Rect)> _gifts(WidgetTester tester) => [
  for (final (message, rect) in _layer(tester).debugFlying)
    if (message.type == LiveMessageType.gift) (message.message, rect),
];

Future<void> _frames(WidgetTester tester, int count) async {
  await tester.pump();
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('off by default: gifts only in the list, nothing more flies', (tester) async {
    final room = await _pump(tester);
    room.danmaku
      ..emit(const DanmakuReady())
      ..emit(DanmakuReceived(_gift('甲', '火箭', 500000, id: '1')))
      ..chat('聊天');
    await _frames(tester, 10);
    expect(_gifts(tester), isEmpty);
    expect(_layer(tester).flyingCount, 1, reason: 'the chat');
    expect(find.textContaining('火箭', findRichText: true), findsWidgets, reason: 'the gift line');
    await _close(tester, room);
  });

  testWidgets('upright: a valuable gift scrolls in a lane below the bar, a cheap one does not fly', (tester) async {
    final room = await _pump(tester, settings: {Settings.danmakuShowGifts: true});
    expect(_overlay(tester).giftClearance, const EdgeInsets.symmetric(vertical: controlBarHeight));
    room.danmaku
      ..emit(const DanmakuReady())
      ..emit(DanmakuReceived(_gift('甲', '小心心', 1000, id: '1')))
      ..emit(DanmakuReceived(_gift('乙', '告白气球', 52000, id: '2')));
    await _frames(tester, 30);
    final gifts = _gifts(tester);
    expect([for (final (words, _) in gifts) words], ['乙 送出 告白气球 ×1']);
    expect(gifts.single.$2.top, greaterThanOrEqualTo(controlBarHeight));
    expect(tester.takeException(), isNull);
    await _close(tester, room);
  });

  testWidgets('landscape fullscreen: a precious gift stands at the top under the top bar, the others clear of the '
      'bars; the chat as before', (tester) async {
    final room = await _pump(tester, size: const Size(852, 393), settings: {Settings.danmakuShowGifts: true});
    expect(find.byKey(const ValueKey('live-play-landscape-chat')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-play-fullscreen')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('live-play-landscape-chat')), findsNothing, reason: 'the fullscreen');
    expect(tester.getSize(find.byType(DanmakuOverlay)), const Size(852, 393));
    final clearance = _overlay(tester).giftClearance;
    expect(clearance.top, greaterThanOrEqualTo(controlBarHeight));
    expect(clearance.bottom, greaterThanOrEqualTo(controlBarHeight));
    room.danmaku
      ..emit(const DanmakuReady())
      ..chat('聊天')
      ..emit(DanmakuReceived(_gift('甲', '火箭', 500000, id: '1')))
      ..emit(DanmakuReceived(_gift('乙', '告白气球', 52000, id: '2')));
    await _frames(tester, 10);
    final box = tester.getSize(find.byType(DanmakuOverlay));
    final gifts = {for (final (words, rect) in _gifts(tester)) words: rect};
    expect(gifts.keys, unorderedEquals(['甲 送出 火箭 ×1', '乙 送出 告白气球 ×1']));
    final held = gifts['甲 送出 火箭 ×1']!;
    expect(held.top, greaterThanOrEqualTo(clearance.top), reason: 'under the top bar');
    expect(held.center.dx, closeTo(box.width / 2, 1), reason: 'centred');
    final scrolling = gifts['乙 送出 告白气球 ×1']!;
    expect(scrolling.top, greaterThanOrEqualTo(clearance.top));
    expect(scrolling.bottom, lessThanOrEqualTo(box.height - clearance.bottom));
    // It stands while the others fly.
    await _frames(tester, 60);
    expect(_gifts(tester).firstWhere((gift) => gift.$1 == '甲 送出 火箭 ×1').$2, held);
    expect(tester.takeException(), isNull);
    await _close(tester, room);
  });
}
