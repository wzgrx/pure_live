import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart' show BlockKind;
import 'package:pure_live_app/features/danmaku/chat_actions.dart';
import 'package:pure_live_app/features/danmaku/chat_panel.dart';
import 'package:pure_live_app/features/danmaku/room_danmaku.dart';

import 'fake_danmaku.dart';

void main() {
  late FakeDanmakuSource source;
  late DateTime now;

  setUp(() {
    source = FakeDanmakuSource();
    now = DateTime(2026, 9, 27, 20);
  });

  /// The chat panel of a live room, 360 × 480, with the room page's block
  /// wiring: the room filters at once, the store gets the rule.
  Future<(RoomDanmaku, List<(BlockKind, String)>)> pumpPanel(WidgetTester tester) async {
    final danmaku = RoomDanmaku(
      source: source,
      room: liveRoom(),
      filters: const DanmakuFilterSettings(),
      enabled: true,
      now: () => now,
    );
    final stored = <(BlockKind, String)>[];
    void block(BlockKind kind, String value) {
      danmaku.block(kind, value);
      stored.add((kind, value));
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              height: 480,
              child: Builder(
                builder: (context) => ChatPanel(
                  danmaku: danmaku,
                  enabled: true,
                  onLine: (line) => unawaited(showChatLineActions(context, line: line, onBlock: block)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    addTearDown(() => unawaited(danmaku.dispose()));
    return (danmaku, stored);
  }

  Future<void> deliver(WidgetTester tester, DanmakuBatch batch) async {
    source.feeds.single.emit(batch);
    await tester.pump();
    // LST-2: the list redraws at most every 80 ms.
    await tester.pump(const Duration(milliseconds: 100));
  }

  ChatListState list(WidgetTester tester) => tester.state<ChatListState>(find.byType(ChatList));

  testWidgets('LST-2: follows the newest line, freezes when the user scrolls up and counts new lines', (tester) async {
    await pumpPanel(tester);
    await deliver(tester, batchOf([for (var i = 0; i < 40; i++) chatLine('u$i', 'm$i')]));
    expect(find.textContaining('m39'), findsOneWidget);
    expect(find.textContaining('m0'), findsNothing);
    expect(list(tester).following, isTrue);

    // Scrolling towards older lines stops following.
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(list(tester).following, isFalse);
    expect(find.text('回到最新'), findsOneWidget);
    final tile = find.byType(ChatLineTile).first;
    final line = tester.widget<ChatLineTile>(tile).line;
    final anchor = tester.getTopLeft(tile);
    final same = find.byWidgetPredicate((widget) => widget is ChatLineTile && identical(widget.line, line));

    await deliver(tester, batchOf([for (var i = 40; i < 45; i++) chatLine('u$i', 'm$i')]));
    expect(find.text('新消息 5'), findsOneWidget);
    expect(find.textContaining('m44'), findsNothing);
    expect(tester.getTopLeft(same), anchor, reason: 'nothing moves under the finger');

    await tester.tap(find.text('新消息 5'));
    await tester.pumpAndSettle();
    expect(list(tester).following, isTrue);
    expect(find.textContaining('m44'), findsOneWidget);
    expect(find.text('新消息 5'), findsNothing);

    await deliver(tester, batchOf([chatLine('u45', 'm45')]));
    expect(find.textContaining('m45'), findsOneWidget, reason: 'following again');
  });

  testWidgets('F-LI-01: a local line shows at once, on this device only, and the list follows it', (tester) async {
    await pumpPanel(tester);
    await deliver(tester, batchOf([for (var i = 0; i < 40; i++) chatLine('u$i', 'm$i')]));
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(list(tester).following, isFalse);

    await tester.enterText(find.byKey(const ValueKey('local-chat-input')), '  主播  加油  ');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(list(tester).following, isTrue, reason: 'LST-2: a local line brings the list back to the newest');
    expect(find.textContaining('主播 加油'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('local-chat-input'))).controller!.text, isEmpty);
    expect(source.feeds.single.settings, isEmpty, reason: 'nothing goes to the worker or the platform');

    // Blank input sends nothing.
    await tester.enterText(find.byKey(const ValueKey('local-chat-input')), '   ');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatLineTile).evaluate().length, lessThanOrEqualTo(41));
  });

  testWidgets('LST-3: blocking while frozen removes the lines and keeps the position', (tester) async {
    final (danmaku, _) = await pumpPanel(tester);
    await deliver(tester, batchOf([for (var i = 0; i < 40; i++) chatLine(i.isEven ? 'even' : 'odd', 'm$i')]));
    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(list(tester).following, isFalse);

    danmaku.block(BlockKind.user, 'odd');
    await tester.pump();
    expect(list(tester).following, isFalse);
    expect(find.textContaining('odd：'), findsNothing);
    expect(find.textContaining('even：'), findsWidgets);
  });

  testWidgets('LST-5: super chats are pinned above the list and leave when they end', (tester) async {
    await pumpPanel(tester);
    await deliver(
      tester,
      batchOf(
        [chatLine('viewer', '普通弹幕')],
        superChats: [superChat('sc', '老板', '醒目留言内容', end: now.add(const Duration(seconds: 60)), price: 50)],
      ),
    );
    expect(find.text('醒目留言内容'), findsOneWidget);
    expect(find.text('¥50'), findsOneWidget);
    expect(tester.getTopLeft(find.text('醒目留言内容')).dy, lessThan(tester.getTopLeft(find.textContaining('普通弹幕')).dy));

    // The same super chat again (polling platforms repeat it) is not added twice.
    await deliver(
      tester,
      batchOf(const [], superChats: [superChat('sc', '老板', '醒目留言内容', end: now.add(const Duration(seconds: 60)))]),
    );
    expect(find.text('醒目留言内容'), findsOneWidget);

    now = now.add(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 61));
    expect(find.text('醒目留言内容'), findsNothing);
  });

  testWidgets('F-DM-04: long-press a line → 屏蔽用户 hides that user at once and stores the rule', (tester) async {
    final (danmaku, stored) = await pumpPanel(tester);
    await deliver(tester, batchOf([chatLine('Spammer', '加群领福利'), chatLine('fan', '主播好'), chatLine('Spammer', '再发一次')]));

    await tester.longPress(find.textContaining('加群领福利'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('屏蔽关键词'), findsOneWidget);
    await tester.tap(find.text('屏蔽用户'));
    await tester.pumpAndSettle();

    expect(stored, [(BlockKind.user, 'Spammer')]);
    expect(danmaku.filters.blockedUsers, ['Spammer']);
    expect(find.textContaining('加群领福利'), findsNothing);
    expect(find.textContaining('再发一次'), findsNothing);
    expect(find.textContaining('主播好'), findsOneWidget);
    expect(find.text('已屏蔽用户“Spammer”'), findsOneWidget);

    // Later lines from the same user are filtered by the worker from now on.
    expect(source.feeds.single.current.blockedUsers, ['Spammer']);
  });

  testWidgets('F-DM-04: tap a line → 屏蔽关键词 edits the word from the text', (tester) async {
    final (danmaku, stored) = await pumpPanel(tester);
    await deliver(tester, batchOf([chatLine('a', '加群领福利 快来'), chatLine('b', '主播好')]));

    await tester.tap(find.textContaining('加群领福利'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('屏蔽关键词'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)));
    expect(field.controller!.text, '加群领福利 快来');
    await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)), '加群');
    await tester.tap(find.widgetWithText(FilledButton, '屏蔽'));
    await tester.pumpAndSettle();

    expect(stored, [(BlockKind.keyword, '加群')]);
    expect(danmaku.filters.blockedWords, ['加群']);
    expect(find.textContaining('加群领福利'), findsNothing);
    expect(find.textContaining('主播好'), findsOneWidget);
  });

  testWidgets('gifts are single list lines; the audience and connection show in the status line', (tester) async {
    await pumpPanel(tester);
    expect(find.text('正在连接弹幕…'), findsOneWidget);
    await deliver(
      tester,
      batchOf(
        [chatLine('a', 'hi')],
        gifts: [giftLine('老板', '火箭', count: 2)],
        online: {AudienceKind.online: 35512},
        system: [const DanmakuSystem(room: 'douyu:1', session: 1, receivedAt: 9, status: DanmakuStatus.connected)],
      ),
    );
    expect(find.textContaining('送出 火箭 ×2'), findsOneWidget);
    expect(find.text('在线 3.6万'), findsOneWidget);
    expect(find.text('正在连接弹幕…'), findsNothing);
  });

  testWidgets('F-DM-01: with danmaku off the panel offers to turn it on', (tester) async {
    var enabled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatPanel(danmaku: null, enabled: false, onLine: (_) {}, onEnable: () => enabled++),
        ),
      ),
    );
    expect(find.text('弹幕已关闭'), findsOneWidget);
    await tester.tap(find.text('打开弹幕'));
    expect(enabled, 1);
  });
}
