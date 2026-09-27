import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/core/danmaku/douyin_danmaku.dart';
import 'package:pure_live/core/danmaku/proto/douyin.pb.dart';
import 'package:pure_live/core/site/douyin/douyin_site.dart';
import 'package:pure_live/core/utils/douyin/douyin_request_params.dart';

void main() {
  group('Douyin danmaku protocol', () {
    DouyinDanmaku createDanmaku(List<LiveMessage> received) {
      final danmaku = DouyinDanmaku();
      danmaku.danmakuArgs = DouyinDanmakuArgs(webRid: 'web', roomId: '100', userId: 'guest', cookie: '');
      danmaku.onMessage = received.add;
      return danmaku;
    }

    test('preserves room, id, user and timestamp metadata', () {
      final received = <LiveMessage>[];
      final danmaku = createDanmaku(received);
      final createdAt = DateTime(2026, 8, 17, 12).millisecondsSinceEpoch;
      final chat = ChatMessage(
        common: Common(roomId: Int64(100), msgId: Int64(9001), createTime: Int64(createdAt)),
        user: User(id: Int64(7), nickName: 'viewer'),
        content: 'hello',
      );

      danmaku.unPackWebcastChatMessage(chat.writeToBuffer(), envelopeMessageId: '8001');

      expect(received, hasLength(1));
      expect(received.single.userId, '7');
      expect(received.single.messageId, 'douyin:9001');
      expect(received.single.sentAt?.millisecondsSinceEpoch, createdAt);
    });

    test('drops chat payloads carrying another room id', () {
      final received = <LiveMessage>[];
      final danmaku = createDanmaku(received);
      final chat = ChatMessage(
        common: Common(roomId: Int64(200), msgId: Int64(1)),
        user: User(id: Int64(7), nickName: 'viewer'),
        content: 'wrong room',
      );

      danmaku.unPackWebcastChatMessage(chat.writeToBuffer());

      expect(received, isEmpty);
    });

    test('signs two current WebSocket edges without corrupting the signature alphabet', () {
      final base = Uri.parse(
        'wss://webcast100-ws-web-lq.douyin.com/webcast/im/push/v2/'
        '?room_id=100&user_unique_id=guest',
      );

      final urls = DouyinDanmaku.buildServerUrls(base, signature: 'A+B/C=');

      expect(urls, hasLength(2));
      expect(urls.map((url) => Uri.parse(url).host).toSet(), {
        'webcast100-ws-web-lq.douyin.com',
        'webcast100-ws-web-hl.douyin.com',
      });
      for (final url in urls) {
        final parsed = Uri.parse(url);
        expect(parsed.path, '/webcast/im/push/v2/');
        expect(parsed.queryParameters['room_id'], '100');
        expect(parsed.queryParameters['user_unique_id'], 'guest');
        expect(parsed.queryParameters['signature'], 'A+B/C=');
        expect(url, isNot(contains('signature=A+B/C=')));
      }
    });

    test('handshake matches the room origin and diagnostics redact the cookie', () {
      final args = DouyinDanmakuArgs(
        webRid: 'web-room',
        roomId: '100',
        userId: 'guest',
        cookie: 'ttwid=secret-session',
      );

      final headers = DouyinDanmaku.buildHandshakeHeaders(args);

      expect(headers['Origin'], 'https://live.douyin.com');
      expect(headers['Referer'], 'https://live.douyin.com/web-room');
      expect(headers['Cookie'], 'ttwid=secret-session');
      expect(args.toString(), isNot(contains('secret-session')));
      expect(args.toString(), contains('<redacted>'));
    });

    test('anonymous handshake omits an empty cookie', () {
      final headers = DouyinDanmaku.buildHandshakeHeaders(
        DouyinDanmakuArgs(webRid: 'web-room', roomId: '100', userId: 'guest', cookie: '   '),
      );

      expect(headers, isNot(contains('Cookie')));
    });

    test('uses the current Webcast SDK and browser-shaped visitor ID', () {
      final visitorId = DouyinSite.generateAnonymousUserUniqueId();

      expect(DouyinRequestParams.sdkVersion, '1.0.15');
      expect(DouyinRequestParams.browserVersion, startsWith('5.0 (Windows NT 10.0; Win64; x64)'));
      expect(visitorId, matches(RegExp(r'^7[3-9]\d{17}$')));
    });
  });
}
