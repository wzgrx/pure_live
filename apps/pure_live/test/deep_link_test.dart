import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/core/deep_link.dart';
import 'package:pure_live_app/features/sync/lan_sync.dart';

void main() {
  test('F-APP-05: purelive://room/<platform>/<roomId> opens the room', () {
    expect(DeepLink.parse('purelive://room/douyu/252140'), RoomDeepLink(RoomRef('douyu', '252140')));
    expect(DeepLink.parse('  PureLive://room/Huya/998/  '), RoomDeepLink(RoomRef('huya', '998')));
    final link = roomDeepLink(RoomRef('bilibili', '6732538'));
    expect(link.toString(), 'purelive://room/bilibili/6732538');
    expect(DeepLink.parse(link.toString()), RoomDeepLink(RoomRef('bilibili', '6732538')));
  });

  test('F-SYNC-01: the LAN sync QR link opens the send page with the address', () {
    final qr = LanSyncProtocol.qrUri(host: '192.168.1.5', port: 39888, code: '123456').toString();
    expect(DeepLink.parse(qr), SyncDeepLink(qr));
    expect(syncLocation(qr), startsWith('/me/backup/lan?target='));
    expect(Uri.parse(syncLocation(qr)).queryParameters['target'], qr);
  });

  test('other text and broken links are not deep links', () {
    for (final text in [
      'https://www.douyu.com/252140',
      'purelive://room/douyu',
      'purelive://room/douyu/0',
      'purelive://room//1',
      'purelive://elsewhere/x',
      'mystyle://room/douyu/1',
      '看看 purelive://room/douyu/1',
      '',
    ]) {
      expect(DeepLink.parse(text), isNull, reason: text);
    }
  });
}
