import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/image_cache.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/shared/danmaku/chat_list_settings.dart';

import '../../support.dart';

// E06.2 c2, c3 (UPGRADES B-14, B-16): the platform's name colour and
// badges, and the PK partner's "对方", on the chat list's lines.

const _fixtures = '../../fixtures';

/// The first comment of 17LIVE's `S06-live` (观众4), read as the danmaku
/// connection reads it: a name colour and three badges.
LiveMessage _seventeenLiveComment() {
  for (final line in File('$_fixtures/17live/danmaku/S06-live/frames.jsonl').readAsLinesSync()) {
    final frame = jsonDecode(line) as Map<String, Object?>;
    if (frame['dir'] != 'in' || frame['url'] != null) continue;
    final text = frame['text'];
    if (text is! String) continue;
    if (jsonDecode(text) case {'action': 15, 'messages': final List<Object?> items}) {
      for (final item in items.cast<Map<String, Object?>>()) {
        final payload = SeventeenLiveDanmakuProtocol.payload(item['data']);
        if (payload == null || payload['type'] != 3) continue;
        return SeventeenLiveDanmakuProtocol.message({'type': 3, 'commentMsg': payload['commentMsg']}, id: '1')!;
      }
    }
  }
  throw StateError('no comment in S06-live');
}

/// The PK partner's chat of Kugou's `S09-pk-chat`, joined as room 1073619.
LiveMessage _kugouPartnerChat() {
  final line = File('$_fixtures/kugoulive/danmaku/S09-pk-chat/frames.jsonl').readAsLinesSync().first;
  final frame = jsonDecode(line) as Map<String, Object?>;
  return KugouLiveDanmakuProtocol.decode(base64Decode(frame['b64']! as String), roomId: '1073619').messages.single;
}

LiveMessage _chat({LiveMessageColor color = LiveMessageColor.white, LiveMessageColor? nameColor}) =>
    LiveMessage(type: LiveMessageType.chat, userName: '观众', message: '你好', color: color, nameColor: nameColor);

/// Answers image requests with a PNG, except for addresses in [missing].
final class _Pictures extends FileService {
  new(this.bytes, {this.missing = const {}});

  final List<int> bytes;
  final Set<String> missing;

  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) async =>
      _Picture(missing.contains(url) ? const [] : bytes, status: missing.contains(url) ? 404 : 200);
}

final class _Picture implements FileServiceResponse {
  new(this.bytes, {required this.status});

  final List<int> bytes;
  final int status;

  @override
  Stream<List<int>> get content => Stream.value(bytes);

  @override
  int get contentLength => bytes.length;

  @override
  String? get eTag => null;

  @override
  String get fileExtension => '.png';

  @override
  int get statusCode => status;

  @override
  DateTime get validTill => DateTime.now().add(const Duration(days: 1));
}

Future<void> _pumpLine(WidgetTester tester, LiveMessage message, {ChatListStyle style = ChatListStyle.compact}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: const LiveTheme().light,
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: ChatLineView(line: ChatLine.chat(message), style: style),
        ),
      ),
    ),
  );
}

/// The colour of the span that says [text] in the line's rich text.
Color? _spanColour(WidgetTester tester, String text) {
  Color? found;
  for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
    widget.text.visitChildren((span) {
      if (span is TextSpan && span.text == text) found = span.style?.color;
      return found == null;
    });
    if (found != null) return found;
  }
  return null;
}

void main() {
  setUpAll(loadStrings);

  group('B-14: the name colour', () {
    testWidgets("17LIVE's name colour wins over the message colour, on both styles", (tester) async {
      final comment = _seventeenLiveComment();
      expect(comment.nameColor, const LiveMessageColor(0x9e, 0x7b, 0xff));
      final theme = const LiveTheme().light;
      await _pumpLine(tester, comment);
      final name = '${comment.userName.trim()}：';
      expect(_spanColour(tester, name), chatNameColor(comment.nameColor!, theme.colorScheme.surface));

      // The message's own colour is not the name's when the platform gives one.
      const red = LiveMessageColor(0xe5, 0x39, 0x35);
      await _pumpLine(tester, _chat(color: red, nameColor: comment.nameColor));
      expect(_spanColour(tester, '观众：'), chatNameColor(comment.nameColor!, theme.colorScheme.surface));
      await _pumpLine(tester, _chat(color: red));
      expect(_spanColour(tester, '观众：'), chatNameColor(red, theme.colorScheme.surface), reason: 'none: the colour');

      await _pumpLine(
        tester,
        _chat(color: red, nameColor: comment.nameColor),
        style: ChatListStyle.card,
      );
      // A08.10: the card's name ends as the compact line's does.
      expect(_spanColour(tester, '观众：'), chatNameColor(comment.nameColor!, theme.colorScheme.surfaceContainerLowest));
    });

    testWidgets('a pale name colour keeps 4.5:1; white takes the secondary colour', (tester) async {
      final theme = const LiveTheme().light;
      await _pumpLine(tester, _chat(nameColor: const LiveMessageColor(0xff, 0xee, 0x58)));
      final pale = _spanColour(tester, '观众：')!;
      expect(contrastRatio(pale, theme.colorScheme.surface), greaterThanOrEqualTo(chatNameContrast));
      await _pumpLine(tester, _chat(nameColor: LiveMessageColor.white));
      expect(_spanColour(tester, '观众：'), theme.colorScheme.onSurfaceVariant);
    });
  });

  group('B-14: the badges', () {
    late BaseCacheManager? previous;
    setUp(() => previous = AppImageCache.manager);
    tearDown(() => AppImageCache.manager = previous);

    Future<void> load(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
    }

    testWidgets('in order before the name, 16 high; one that fails takes no room', (tester) async {
      final comment = _seventeenLiveComment();
      expect(comment.badges, hasLength(3));
      final png = File('assets/emo/images/bilibili/dog.png').readAsBytesSync();
      AppImageCache.manager = CacheManager(
        Config(
          'badges',
          repo: NonStoringObjectProvider(),
          fileSystem: MemoryCacheSystem(),
          fileService: _Pictures(png, missing: {comment.badges[1].url}),
        ),
      );
      await _pumpLine(tester, comment);
      final badges = find.byType(ChatBadge);
      await load(tester);
      expect(badges, findsNWidgets(3));
      Rect at(int index) => tester.getRect(find.byKey(ValueKey('live-play-chat-badge-$index')));
      expect(at(0).height, ChatBadge.height);
      expect(at(0).width, greaterThan(ChatBadge.gap), reason: 'the picture and its gap');
      expect(at(1).size, Size.zero, reason: 'failed: nothing, no gap');
      expect(at(2).height, ChatBadge.height);
      expect(at(0).right, lessThanOrEqualTo(at(2).left), reason: "the platform's order");
      final line = tester.getRect(find.byKey(const ValueKey('live-play-chat-line')));
      expect(at(0).left - line.left, lessThan(1), reason: 'first on the line, before the name');

      // The card style draws them too.
      await _pumpLine(tester, comment, style: ChatListStyle.card);
      await load(tester);
      expect(badges, findsNWidgets(3));
      // flutter_cache_manager's clean-up after a lookup, 10 s later.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('without badges there is no badge', (tester) async {
      await _pumpLine(tester, _chat());
      expect(find.byType(ChatBadge), findsNothing);
    });
  });

  group('B-16: the PK partner', () {
    testWidgets('a Kugou PK partner\'s chat says "对方" before the name, on both styles', (tester) async {
      final partner = _kugouPartnerChat();
      expect(partner.isFromOtherRoom, isTrue);
      for (final style in ChatListStyle.values) {
        await _pumpLine(tester, partner, style: style);
        final mark = find.byKey(const ValueKey('live-play-chat-other-room'));
        expect(mark, findsOneWidget, reason: '$style');
        expect(find.descendant(of: mark, matching: find.text('对方')), findsOneWidget);
      }
      await _pumpLine(tester, _chat());
      expect(find.byKey(const ValueKey('live-play-chat-other-room')), findsNothing, reason: "this room's own");
    });
  });
}
