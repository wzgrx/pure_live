import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/features/room/room_menus.dart';

RoomDetail _detail(String platform, String id, [Map<String, String> keys = const {}]) => RoomDetail(
  card: RoomCard(ref: RoomRef(platform, id), title: 't', anchorName: 'a', state: LiveState.live),
  link: Uri.parse('https://example.com/$id'),
  danmakuKeys: keys,
);

void main() {
  test("F-ROOM-18: 3.x's app links, only where the platform's ids are known", () {
    expect(nativeAppLink(_detail('bilibili', '6732538')).toString(), 'bilibili://live/6732538');
    expect(nativeAppLink(_detail('douyu', '252140')).toString(), contains('rid%3D252140'));
    expect(
      nativeAppLink(_detail('douyin', '123', {'roomId': '7400000000000000000'})).toString(),
      'snssdk1128://webcast_room?room_id=7400000000000000000',
    );
    expect(nativeAppLink(_detail('douyin', '123')), isNull, reason: 'no internal room id');
    expect(nativeAppLink(_detail('huya', '998', {'subSid': '1234'})).toString(), contains('channelid%3D1234'));
    expect(nativeAppLink(_detail('huya', '998', {'subSid': '0'})), isNull);
    expect(nativeAppLink(_detail('kuaishou', 'abc', {'liveStreamId': 's1'})).toString(), contains('liveStreamId=s1'));
    expect(nativeAppLink(_detail('twitch', 'shroud')), isNull);
  });
}
