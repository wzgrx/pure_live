// "+1（本地）" in a danmaku's panel (docs/A-界面设计/A08-弹幕界面/A08.14-长按弹幕面板加一):
// a platform's danmaku goes out once more as a local one, with the user's
// local profile and style; one's own says "再发一次"; none while the local
// interaction is off, outside a room's local interaction, or on a gift,
// a super chat or a notice.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/message_panel.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

import 'local_interaction_support.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _in(String key, Finder finder) => find.descendant(of: _key(key), matching: finder);

const String _row = 'live-play-send-local-again';

/// The visible keys of [keys], top to bottom.
List<String> _column(WidgetTester tester, List<String> keys) => [
  for (final key in keys)
    if (_key(key).evaluate().isNotEmpty) key,
]..sort((a, b) => tester.getTopLeft(_key(a)).dy.compareTo(tester.getTopLeft(_key(b)).dy));

RoomPanelController _panels(WidgetTester tester) =>
    RoomPanelScope.maybeOf(tester.element(find.byType(DanmakuOverlay)))!;

LocalRoomSession _session(WidgetTester tester) => LocalRoomScope.maybeOf(tester.element(find.byType(DanmakuOverlay)))!;

/// A platform's danmaku in the chat list, long pressed: its panel.
Future<void> _longPressChat(WidgetTester tester, LocalRoom room, String text) async {
  room.danmaku.chat(text, user: '路人', id: 'm-$text');
  await settleLocal(tester);
  await tester.longPress(find.textContaining(text, findRichText: true).first);
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, LiveMessage message) async {
  _panels(tester).openMessage(message);
  await tester.pumpAndSettle();
}

List<LiveMessage> _localLines(LocalRoom room, WidgetTester tester) => [
  for (final line in _session(tester).room.chat.lines)
    if (line.message case final message? when message.isLocal) message,
];

void main() {
  testWidgets('a platform danmaku: "+1（本地）" under "复制"; sent with the local profile and style, recorded', (
    tester,
  ) async {
    final room = await pumpLocalRoom(tester);
    await _longPressChat(tester, room, '前排[doge]');
    expect(_key('live-play-message-panel'), findsOneWidget);
    expect(_column(tester, ['live-play-copy-message', _row, 'live-play-block-user', 'live-play-block-keyword']), [
      'live-play-copy-message',
      _row,
      'live-play-block-user',
      'live-play-block-keyword',
    ], reason: 'under "复制", over the blocking (3.x order kept)');
    expect(_in(_row, find.text('+1（本地）')), findsOneWidget);
    expect(_in(_row, find.textContaining('用你的本地身份和样式再发一次，只有你看得')), findsOneWidget);
    expect(_in(_row, find.byIcon(AppIcons.localSendAgain)), findsOneWidget);

    final flying = tester.state<DanmakuOverlayState>(find.byType(DanmakuOverlay));
    final before = flying.flyingCount;
    await tester.tap(_key(_row));
    await tester.pump();
    expect(flying.flyingCount, before + 1, reason: 'over the picture, as the composer sends');
    await settleLocal(tester);
    await tester.pumpAndSettle();
    expect(_key('live-play-message-panel'), findsNothing, reason: 'the panel closes');
    expect(room.toasts, ['已发送本地弹幕']);
    final local = _localLines(room, tester);
    expect(local, hasLength(1));
    final sent = local.single;
    // The words as they came (an emote's code too), as the user.
    expect(sent.message, '前排[doge]');
    expect(sent.userName, '📺 舰队等级 · 听众 · Pure Live');
    final interaction = _session(tester).interaction;
    final style = interaction.currentStyle;
    expect(
      (sent.style?.fontSize, sent.style?.fontWeight, sent.style?.placement, sent.style?.strokeColor),
      (style.fontSize, style.fontWeight, style.placement, style.strokeColor),
      reason: 'the local style',
    );
    expect(sent.color, LiveMessageColor.numberToColor(interaction.color));
    expect(_key('live-play-local-line'), findsOneWidget, reason: 'in the chat list at once');
    // D08.1: the history has it, with the room.
    final entry = interaction.events.first;
    expect(entry.kind, LocalEventKind.chat);
    expect(entry.text, '前排[doge]');
    expect((entry.platform, entry.roomId), (SiteIds.bilibili, '6'));
    await closeLocalRoom(tester, room);
  });

  testWidgets('own local danmaku: "再发一次", the same way', (tester) async {
    final room = await pumpLocalRoom(tester);
    expect(_session(tester).sendChat('主播晚上好'), isTrue);
    await tester.pump();
    await tester.longPress(_key('live-play-local-line'));
    await tester.pumpAndSettle();
    expect(_column(tester, ['live-play-copy-message', _row]), ['live-play-copy-message', _row]);
    expect(_in(_row, find.text('再发一次')), findsOneWidget);
    expect(_in(_row, find.text('+1（本地）')), findsNothing);
    await tester.tap(_key(_row));
    await settleLocal(tester);
    await tester.pumpAndSettle();
    expect(_key('live-play-local-line'), findsNWidgets(2));
    expect(room.toasts, ['已发送本地弹幕']);
    expect([for (final e in _session(tester).interaction.events) e.text], ['主播晚上好', '主播晚上好']);
    await closeLocalRoom(tester, room);
  });

  testWidgets('longer than a local danmaku may be: the first 40 characters go out', (tester) async {
    final room = await pumpLocalRoom(tester);
    final long = '${'一' * 30}😀${'二' * 29}';
    await _open(
      tester,
      LiveMessage(type: LiveMessageType.chat, userName: '路人', message: long, color: LiveMessageColor.white),
    );
    await tester.tap(_key(_row));
    await settleLocal(tester);
    final sent = _localLines(room, tester).single.message;
    expect(sent.characters.length, LocalCatalog.danmakuLimit);
    expect(sent, '${'一' * 30}😀${'二' * 9}', reason: 'an emoji is one character');
    expect(_session(tester).interaction.events.first.text, sent);
    await closeLocalRoom(tester, room);
  });

  testWidgets('the local interaction off: no row; turned off with the panel open: it goes', (tester) async {
    final room = await pumpLocalRoom(tester, settings: {Settings.localInteractionEnabled: false});
    await _longPressChat(tester, room, '前排');
    expect(_key('live-play-copy-message'), findsOneWidget);
    expect(_key(_row), findsNothing);
    expect(_key('live-play-block-keyword'), findsOneWidget);
    await closeLocalRoom(tester, room);

    final again = await pumpLocalRoom(tester);
    await _longPressChat(tester, again, '后排');
    expect(_key(_row), findsOneWidget);
    _session(tester).interaction.enabled = false;
    await tester.pumpAndSettle();
    expect(_key(_row), findsNothing);
    await closeLocalRoom(tester, again);
  });

  testWidgets('a gift, a super chat, a notice and a local gift have none', (tester) async {
    final room = await pumpLocalRoom(tester);
    for (final message in [
      const LiveMessage(type: LiveMessageType.gift, userName: '路人', message: '送出 辣条 ×1', color: LiveMessageColor.white),
      const LiveMessage(type: LiveMessageType.superChat, userName: '路人', message: '加油', color: LiveMessageColor.white),
      const LiveMessage(type: LiveMessageType.notice, userName: '', message: '欢迎来到直播间', color: LiveMessageColor.white),
      const LiveMessage(type: LiveMessageType.chat, userName: '路人', message: '   ', color: LiveMessageColor.white),
    ]) {
      await _open(tester, message);
      expect(_key('live-play-message-panel'), findsOneWidget, reason: message.message);
      expect(_key(_row), findsNothing, reason: message.message);
      _panels(tester).close();
      await tester.pumpAndSettle();
    }
    final session = _session(tester);
    expect(session.sendGift(LocalCatalog.giftsFor(SiteIds.bilibili).first), isTrue);
    await tester.pump();
    final gift = _localLines(room, tester).single;
    await _open(tester, gift);
    expect(_key('live-play-copy-message'), findsOneWidget);
    expect(_key(_row), findsNothing);
    await closeLocalRoom(tester, room);
  });

  testWidgets('landscape fullscreen: the panel a flying danmaku opens has it too; what it sends flies', (tester) async {
    final room = await pumpLocalRoom(tester, width: 852, height: 393);
    await tester.tap(_key('live-play-fullscreen'));
    await settleLocal(tester);
    await tester.pumpAndSettle();
    // A tap on a flying danmaku (F.2b, D-038) opens the panel of its message.
    await _open(
      tester,
      const LiveMessage(type: LiveMessageType.chat, userName: '路人', message: '666', color: LiveMessageColor.white),
    );
    expect(tester.getRect(_key('live-play-message-panel')), const Rect.fromLTRB(852.0 - 360, 0, 852, 393));
    expect(_in('live-play-message-panel', find.text('+1（本地）')), findsOneWidget);
    final flying = tester.state<DanmakuOverlayState>(find.byType(DanmakuOverlay));
    final before = flying.flyingCount;
    await tester.tap(_key(_row));
    await tester.pump();
    expect(flying.flyingCount, before + 1, reason: 'over the picture, as the composer sends');
    expect(_key('live-play-back'), findsOneWidget, reason: 'still in the fullscreen');
    expect(room.toasts, ['已发送本地弹幕']);
    await closeLocalRoom(tester, room);
  });

  testWidgets("a panel without the room's local interaction (multi-view, the TV): no row", (tester) async {
    final room = await pumpLocalRoom(tester);
    final controller = _session(tester).room;
    final navigator = Navigator.of(tester.element(find.byType(LivePlayPage)));
    // The route is under the app's navigator, outside the room page and its
    // LocalRoomScope, as the multi-view's sheet.
    final route = MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: RoomMessagePanel(
          controller: controller,
          message: const LiveMessage(
            type: LiveMessageType.chat,
            userName: '路人',
            message: '前排',
            color: LiveMessageColor.white,
          ),
          onClose: () {},
        ),
      ),
    );
    navigator.push(route).ignore();
    await tester.pumpAndSettle();
    expect(_key('live-play-copy-message'), findsOneWidget);
    expect(_key(_row), findsNothing);
    navigator.removeRoute(route);
    await tester.pumpAndSettle();
    await closeLocalRoom(tester, room);
  });
}
