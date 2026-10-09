// The local interaction's structured history
// (docs/D-弹幕/D08-本地互动/D08.1-结构化的本地历史): entries written by what is
// sent, the old lines taken in once, read in the language of now, the
// history's parts and "再发一次", the export, and entering a room again.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_settings_page.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

import '../../support.dart';
import 'local_interaction_support.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _in(String key, Finder finder) => find.descendant(of: _key(key), matching: finder);

LocalRoomSession _session(WidgetTester tester) => LocalRoomScope.maybeOf(tester.element(find.byType(DanmakuOverlay)))!;

const Duration _second = Duration(seconds: 1);

const LocalPlace _here = (platform: SiteIds.bilibili, roomId: '6', roomName: '主播');

/// A local danmaku sent in room [roomId] [ago] before now.
LocalEvent _sent(String text, Duration ago, {String roomId = '6'}) => LocalEvent(
  at: DateTime.now().subtract(ago),
  kind: LocalEventKind.chat,
  platform: SiteIds.bilibili,
  roomId: roomId,
  roomName: roomId == '6' ? '主播' : '别的主播',
  text: text,
);

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}

String? _count(WidgetTester tester) => tester.widget<Text>(_key('local-history-count')).data;

Future<void> _openPanel(WidgetTester tester) async {
  await tester.tap(_key('live-play-menu'));
  await tester.pumpAndSettle();
  await tester.tap(_key('room-menu-localInteraction'));
  await tester.pumpAndSettle();
}

Future<void> _toHistory(WidgetTester tester) async {
  await tester.drag(_key('local-panel-list'), const Offset(0, -1500));
  await tester.pumpAndSettle();
}

/// The texts of the chat list's lines, top to bottom.
List<String> _chatLines(WidgetTester tester, List<String> texts) =>
    [
      for (final text in texts)
        if (find.textContaining(text, findRichText: true).evaluate().isNotEmpty) text,
    ]..sort(
      (a, b) => tester
          .getTopLeft(find.textContaining(a, findRichText: true).first)
          .dy
          .compareTo(tester.getTopLeft(find.textContaining(b, findRichText: true).first).dy),
    );

void main() {
  group('entries (c1, c2, c3)', () {
    test(
      'a danmaku, a gift and coins write one each; the old lines come in once; read in the language of now',
      () async {
        final store = await LiveStore.memory(cipher: FakeCipher());
        addTearDown(store.close);
        await loadStrings();
        await store.settings.set(Settings.localInteractionHistory, ['增加本地体验币 +500']);
        var now = DateTime(2026, 10, 9, 20);
        final local = LocalInteraction(store.settings, events: store.localEvents, now: () => now);
        addTearDown(local.dispose);
        await local.start();
        await _until(() => local.events.length == 1);
        expect(
          (local.events.single.kind, local.describe(local.events.single)),
          (LocalEventKind.legacy, '增加本地体验币 +500'),
        );

        local.recordChat(' 晚上好 ', _here);
        now = now.add(const Duration(minutes: 1));
        final snack = LocalCatalog.giftsFor(SiteIds.bilibili).first;
        expect(local.sendGift(snack, platform: SiteIds.bilibili, place: _here), isNotNull);
        now = now.add(const Duration(minutes: 1));
        local.recharge(2000);
        // Shown at once, newest first.
        expect(
          [for (final e in local.events) local.describe(e)],
          ['增加本地体验币 +2000', '🌶️ 送出 辣条 ×1', '晚上好', '增加本地体验币 +500'],
        );
        // D-018: 3.x's sentences are still written (the danmaku never was).
        expect(local.history, ['增加本地体验币 +2000', '🌶️ 📺 舰队等级 · 听众 · Pure Live 送出 辣条 ×1', '增加本地体验币 +500']);

        // Stored with the room, the time and the style.
        await _until(() => local.events.every((e) => e.id != null));
        final stored = await store.localEvents.all();
        expect(
          [for (final e in stored) e.kind],
          [LocalEventKind.recharge, LocalEventKind.gift, LocalEventKind.chat, LocalEventKind.legacy],
        );
        final chat = stored[2];
        expect(
          (chat.platform, chat.roomId, chat.roomName, chat.text, chat.at),
          ('bilibili', '6', '主播', '晚上好', DateTime(2026, 10, 9, 20)),
        );
        expect(chat.style, contains('"localInteraction.danmakuFontSize":'));
        expect((stored[1].giftId, stored[1].count, stored[1].coins, stored[1].roomId), ('bili_snack', 1, 10, '6'));
        expect((stored.first.coins, stored.first.inRoom), (2000, false));

        // c5: another language, the same entries in it; the old line as it was.
        await loadStrings(AppLanguage.en);
        expect(local.describe(stored[1]), '🌶️ sent Spicy snack ×1');
        expect(local.describe(stored.first), 'Added local experience coins +2000');
        expect(local.describe(stored.last), '增加本地体验币 +500');
        await loadStrings();

        // The parts.
        expect([for (final f in LocalHistoryFilter.values) stored.where(f.accepts).length], [4, 1, 1, 1]);

        // Started again (the next launch): the old lines are not taken twice.
        final again = LocalInteraction(store.settings, events: store.localEvents);
        addTearDown(again.dispose);
        await again.start();
        await _until(() => again.events.length == 4);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(again.events, stored);
      },
    );

    test('the clear takes the entries too; its undo puts them back under their ids (A08.13)', () async {
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      await loadStrings();
      var now = DateTime(2026, 10, 9, 20);
      final local = LocalInteraction(store.settings, events: store.localEvents, now: () => now = now.add(_second));
      addTearDown(local.dispose);
      await local.start();
      local
        ..recordChat('一', _here)
        ..recharge(500);
      await _until(() => local.events.length == 2 && local.events.every((e) => e.id != null));
      final before = local.events;
      final cleared = local.clearHistory();
      expect(cleared.events, before);
      expect(cleared.lines, ['增加本地体验币 +500']);
      expect(local.events, isEmpty);
      await _until(() => local.events.isEmpty);
      expect(await store.localEvents.all(), isEmpty);
      local
        ..recordChat('二', _here)
        ..restoreHistory(cleared);
      expect([for (final e in local.events) e.text], ['二', '', '一']);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final stored = await store.localEvents.all();
      expect(stored.sublist(1), before);
      expect(local.events, stored);
      expect(local.history, ['增加本地体验币 +500']);
    });
  });

  group('entering a room again (c6)', () {
    Future<LocalRoom> enter(WidgetTester tester, {double width = 400, double height = 900, bool replay = true}) =>
        pumpLocalRoom(
          tester,
          width: width,
          height: height,
          settings: {if (!replay) Settings.localInteractionReplayOnEnter: false},
          prepare: (store) => store.localEvents.addAll([
            _sent('太早了', const Duration(hours: 25)),
            _sent('之前一', const Duration(minutes: 40)),
            _sent('别的房间', const Duration(minutes: 35), roomId: '7'),
            LocalEvent(
              at: DateTime.now().subtract(const Duration(minutes: 32)),
              kind: LocalEventKind.gift,
              platform: SiteIds.bilibili,
              roomId: '6',
              giftId: 'bili_snack',
              count: 1,
            ),
            _sent('之前二', const Duration(minutes: 30)),
          ]),
        );

    Future<void> platformLine(WidgetTester tester, LocalRoom room) async {
      room.danmaku.emit(
        const DanmakuReceived(
          LiveMessage(type: LiveMessageType.chat, userName: '观众', message: '平台的话', color: LiveMessageColor.white),
        ),
      );
      await settleLocal(tester);
    }

    for (final (name, width, height) in [
      ('portrait', 400.0, 900.0),
      ('landscape phone', 852.0, 393.0),
      ('wide', 1280.0, 800.0),
    ]) {
      testWidgets('$name: the last day\'s local danmaku of this room on top, "之前发的", not flying, not new', (
        tester,
      ) async {
        final room = await enter(tester, width: width, height: height);
        await platformLine(tester, room);
        expect(_key('live-play-local-replayed'), findsNWidgets(2));
        expect(_in('live-play-local-line', find.text('之前发的')), findsNWidgets(2));
        expect(_chatLines(tester, ['之前一', '之前二', '平台的话']), ['之前一', '之前二', '平台的话']);
        expect(find.textContaining('太早了', findRichText: true), findsNothing, reason: 'older than 24 h');
        expect(find.textContaining('别的房间', findRichText: true), findsNothing);
        expect(find.textContaining('辣条', findRichText: true), findsNothing, reason: 'only danmaku come back');
        final flying = tester.state<DanmakuOverlayState>(find.byType(DanmakuOverlay));
        expect(flying.flyingCount, 1, reason: 'only the platform line flies');
        expect(_key('live-play-new-messages'), findsNothing);
        expect(room.toasts, isEmpty);
        await closeLocalRoom(tester, room);
      });
    }

    testWidgets('"进房放回" off: the room as before', (tester) async {
      final room = await enter(tester, replay: false);
      expect(_key('live-play-local-replayed'), findsNothing);
      expect(find.textContaining('之前二', findRichText: true), findsNothing);
      await closeLocalRoom(tester, room);
    });

    testWidgets('sent, left, entered again: they come back once; what this visit sends is not doubled', (tester) async {
      var room = await pumpLocalRoom(tester);
      final session = _session(tester);
      for (final text in ['第一句', '第二句', '第三句']) {
        expect(session.sendChat(text), isTrue);
      }
      await settleLocal(tester);
      expect(_key('live-play-local-replayed'), findsNothing);
      final stored = (await tester.runAsync(room.services.store.localEvents.all))!;
      expect(
        [for (final e in stored) (e.text, e.roomId, e.kind)],
        [('第三句', '6', LocalEventKind.chat), ('第二句', '6', LocalEventKind.chat), ('第一句', '6', LocalEventKind.chat)],
      );

      await leaveLocalRoom(tester);
      room = await pumpLocalRoom(tester, reuse: room.services);
      expect(_key('live-play-local-replayed'), findsNWidgets(3));
      expect(_chatLines(tester, ['第一句', '第二句', '第三句']), ['第一句', '第二句', '第三句']);
      _session(tester).sendChat('第四句');
      await settleLocal(tester);
      expect(_key('live-play-local-line'), findsNWidgets(4));
      expect(_key('live-play-local-replayed'), findsNWidgets(3));
      await closeLocalRoom(tester, room);
    });
  });

  group('the history in the panel and on the settings page (c5)', () {
    Future<void> seed(LiveStore store) async {
      await store.settings.set(Settings.localInteractionHistory, ['旧的一行']);
      await store.localEvents.addAll([
        _sent('晚上好', const Duration(minutes: 20)),
        LocalEvent(
          at: DateTime.now().subtract(const Duration(minutes: 10)),
          kind: LocalEventKind.gift,
          platform: SiteIds.bilibili,
          roomId: '6',
          roomName: '主播',
          giftId: 'bili_snack',
          count: 1,
          coins: 10,
        ),
        LocalEvent(at: DateTime.now().subtract(const Duration(minutes: 5)), kind: LocalEventKind.recharge, coins: 500),
        _sent('那边的话', const Duration(minutes: 15), roomId: '7'),
      ]);
    }

    testWidgets('parts, when and where, "只看本直播间", "再发一次" (a gift costs again)', (tester) async {
      final room = await pumpLocalRoom(tester, prepare: seed);
      await _openPanel(tester);
      await _toHistory(tester);
      final local = _session(tester).interaction;
      expect(local.events, hasLength(5), reason: 'the old line came in too');
      expect(_count(tester), '5 条');
      expect(_in('local-history-row-4', find.text('旧的一行')), findsOneWidget);
      expect(_in('local-history-row-4', find.text('旧记录')), findsOneWidget);
      expect(_key('local-history-again-4'), findsNothing, reason: 'an old line cannot be sent again');
      expect(_in('local-history-row-0', find.text('增加本地体验币 +500')), findsOneWidget);
      expect(_key('local-history-again-0'), findsNothing);

      await tester.tap(_key('local-history-filter-chat'));
      await tester.pumpAndSettle();
      expect(_count(tester), '2 条');
      final detail = tester.widget<Text>(_key('local-history-detail-1')).data!;
      expect(detail, matches(RegExp(r'^(\d{4}-)?(\d\d-\d\d )?\d\d:\d\d · 主播$')));
      expect(_in('local-history-row-0', find.text('那边的话')), findsOneWidget);
      await tester.tap(_key('local-history-room'));
      await tester.pumpAndSettle();
      expect(_count(tester), '1 条');
      expect(_in('local-history-row-0', find.text('晚上好')), findsOneWidget);

      // Again: a new line in the list and a new entry.
      await tester.tap(_key('local-history-again-0'));
      await tester.pumpAndSettle();
      expect(room.toasts, ['已再发一次']);
      expect(local.events.first.text, '晚上好');
      expect(local.events, hasLength(6));
      expect(_count(tester), '2 条');

      // A gift: its coins again; not enough, the usual words.
      await tester.tap(_key('local-history-filter-gift'));
      await tester.pumpAndSettle();
      expect(_in('local-history-row-0', find.text('🌶 送出 辣条 ×1')), findsOneWidget);
      final coins = local.coins;
      await tester.tap(_key('local-history-again-0'));
      await tester.pumpAndSettle();
      expect(local.coins, coins - 10);
      expect(_count(tester), '2 条');
      await tester.runAsync(() => room.settings.set(Settings.localInteractionCoins, 5));
      await settleLocal(tester);
      await tester.tap(_key('local-history-again-0'));
      await tester.pumpAndSettle();
      expect(room.toasts.last, '体验币余额不足');
      expect(_count(tester), '2 条');

      await tester.tap(_key('local-history-filter-coins'));
      await tester.pumpAndSettle();
      expect(_count(tester), '0 条', reason: 'coins are added in no room');
      await tester.tap(_key('local-history-room'));
      await tester.pumpAndSettle();
      expect(_count(tester), '1 条');
      await closeLocalRoom(tester, room);
    });

    testWidgets('settings page: the same history, no "再发一次", copied to the clipboard; the replay switch', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(400, 3200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final services = (await tester.runAsync(() async {
        final services = await testServices();
        await seed(services.store);
        return services;
      }))!;
      await tester.runAsync(loadStrings);
      final toasts = <String>[];
      final previous = AppNavigator.toast;
      AppNavigator.toast = toasts.add;
      addTearDown(() => AppNavigator.toast = previous);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appServicesProvider.overrideWithValue(services)],
          child: MaterialApp(
            theme: const LiveTheme().light,
            builder: (context, child) =>
                MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
            home: const LocalInteractionSettingsPage(),
          ),
        ),
      );
      await settleLocal(tester);
      expect(_count(tester), '5 条');
      expect(_key('local-history-room'), findsNothing, reason: 'no room here');
      expect(find.byKey(const ValueKey('local-history-again-1')), findsNothing);

      await tester.tap(_key('local-history-export'));
      await tester.pump();
      final lines = copied!.split('\n');
      expect(lines, hasLength(5));
      expect(lines.first, matches(RegExp(r'^\d{4}-\d\d-\d\d \d\d:\d\d · 币 · 增加本地体验币 \+500$')));
      expect(lines[1], endsWith(' · 主播 · 礼物 · 🌶️ 送出 辣条 ×1'));
      expect(lines.last, '旧记录 · 旧的一行');
      expect(toasts, ['已复制 5 条本地互动记录']);

      expect(find.text('进房放回之前发的本地弹幕'), findsOneWidget);
      expect(
        tester.widget<Switch>(_key('local-settings-switch-replay')).value,
        isTrue,
        reason: 'on by default (D-040)',
      );
      await tester.tap(_key('local-settings-replay'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(services.store.settings.get(Settings.localInteractionReplayOnEnter), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(services.close);
    });
  });
}
