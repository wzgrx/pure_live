// Legacy expected values for the recorded Douyu samples (spec/sites/douyu.md §11).
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/douyu/douyu_site.dart';

import 'support.dart';

void main() {
  group('S05 betard room detail', () {
    for (final sample in ['S05-live']) {
      test(sample, () async {
        final fixture = FixtureSample.load('douyu', sample);
        replay([fixture]);
        final roomId = fixture.url.pathSegments.last;
        final room = await DouyuSite().getRoomDetailForRefresh(platform: 'douyu', roomId: roomId);
        final payload = fixture.json;
        final roomInfo = (payload is Map ? payload : null)?['room'] as Map? ?? const {};
        expectRecorded(fixture, 'DouyuSite.getRoomDetailForRefresh + DouyuSite.isLiveRoomPayload', {
          'isLiveRoomPayload': DouyuSite.isLiveRoomPayload(roomInfo),
          'room': roomProjection(room),
        });
      });
    }
  });
}
