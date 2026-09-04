import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/soop/soop_site.dart';

void main() {
  group('SOOP danmaku endpoint', () {
    test('maps the plain chat port to the adjacent official WSS port', () {
      final url = SoopSite.buildDanmakuWebSocketUrl(
        channel: const <String, dynamic>{'CHDOMAIN': 'chat-DEE9364C.sooplive.com', 'CHPT': '9000'},
        roomId: 'khm11903',
      );

      expect(url, 'wss://chat-dee9364c.sooplive.com:9001/Websocket/khm11903');
    });

    test('derives the secure host from CHIP when CHDOMAIN is absent', () {
      final url = SoopSite.buildDanmakuWebSocketUrl(
        channel: const <String, dynamic>{'CHIP': '222.233.54.76', 'CHPT': 9000},
        roomId: 'room id',
      );

      expect(url, 'wss://chat-dee9364c.sooplive.co.kr:9001/Websocket/room%20id');
    });

    test('rejects incomplete and overflowing endpoints', () {
      expect(
        () => SoopSite.buildDanmakuWebSocketUrl(
          channel: const <String, dynamic>{'CHDOMAIN': 'chat.example', 'CHPT': 65535},
          roomId: 'room',
        ),
        throwsFormatException,
      );
      expect(
        () => SoopSite.buildDanmakuWebSocketUrl(
          channel: const <String, dynamic>{'CHIP': '999.1.1.1', 'CHPT': 9000},
          roomId: 'room',
        ),
        throwsFormatException,
      );
    });
  });
}
