// Legacy expected values for the recorded Huya samples (spec/sites/huya.md §11).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/core/site/huya/huya_site.dart';

import 'huya_support.dart';
import 'support.dart';

void main() {
  setUpHuyaSettings();

  group('S01 bussLive categories', () {
    const samples = ['S01-buss1', 'S01-buss2', 'S01-buss8', 'S01-buss3'];
    for (final sample in samples) {
      test(sample, () async {
        final fixture = huyaSample(sample);
        replayHuya([for (final each in samples) huyaSample(each)]);
        final categories = await HuyaSite().getCategores(1, 1000);
        final category = categories.singleWhere((item) => item.id == fixture.url.queryParameters['bussType']);
        expectRecorded(fixture, 'HuyaSite.getCategores', {
          'id': category.id,
          'name': category.name,
          'children': [for (final area in category.children) area.toJson()],
        });
      });
    }
  });

  group('S02 getLiveListByPage recommend', () {
    for (final sample in ['S02-page1', 'S02-page2', 'S02-last', 'S02-beyond']) {
      test(sample, () async {
        final fixture = huyaSample(sample);
        replayHuya([fixture]);
        final page = int.parse(fixture.url.queryParameters['page']!);
        final rooms = await HuyaSite().getRecommendRooms(page: page);
        expectRecorded(fixture, 'HuyaSite.getRecommendRooms', {
          'rooms': [for (final room in rooms) roomProjection(room)],
        });
      });
    }
  });

  group('S03 getLiveListByPage area rooms', () {
    for (final sample in ['S03-hot-page1', 'S03-hot-page2', 'S03-cold-page1', 'S03-cold-page2']) {
      test(sample, () async {
        final fixture = huyaSample(sample);
        replayHuya([fixture]);
        final query = fixture.url.queryParameters;
        final area = LiveArea(platform: 'huya', areaId: query['gameId']);
        final rooms = await HuyaSite().getCategoryRooms(area, page: int.parse(query['page']!));
        expectRecorded(fixture, 'HuyaSite.getCategoryRooms', {
          'rooms': [for (final room in rooms) roomProjection(room)],
        });
      });
    }
  });

  group('S04 getSearchContent v=4', () {
    for (final sample in ['S04-results', 'S04-page2', 'S04-empty', 'S04-fallback']) {
      test(sample, () async {
        final fixture = huyaSample(sample);
        replayHuya([fixture]);
        final query = fixture.url.queryParameters;
        final rows = int.parse(query['rows']!);
        final page = int.parse(query['start']!) ~/ rows + 1;
        final rooms = await HuyaSite().searchRooms(query['q']!, page: page, pageSize: rows);
        expectRecorded(fixture, 'HuyaSite.searchRooms', {
          'rooms': [for (final room in rooms) roomProjection(room)],
        });
      });
    }
  });

  group('S05 profileRoom live', () {
    for (final sample in ['S05-multicdn', 'S05-xingxiu', 'S05-ratearray']) {
      test(sample, () async {
        final fixture = huyaSample(sample);
        replayHuya([fixture]);
        final roomId = fixture.url.queryParameters['roomid']!;
        final site = HuyaSite();
        final room = await site.getRoomDetail(platform: 'huya', roomId: roomId);
        final data = room.data as HuyaUrlDataModel;
        final refreshed = await site.getRoomDetailForRefresh(platform: 'huya', roomId: roomId);
        final payload = fixture.json;
        final liveData = payload['data']['liveData'] as Map;
        final bitRateInfo = liveData['bitRateInfo'];
        expectRecorded(
          fixture,
          'HuyaSite.getRoomDetail + getRoomDetailForRefresh + parsePlayQualities + parseBitRates + status/audience helpers',
          {
            'getRoomDetail': roomProjection(room),
            'data': huyaDataProjection(data),
            'parsePlayQualities': [
              for (final quality in HuyaSite.parsePlayQualities(data)) huyaQualityProjection(quality),
            ],
            'parseBitRates': {
              'bitRateInfo': [
                for (final rate in HuyaSite.parseBitRates(
                  bitRateInfo is String ? jsonDecode(bitRateInfo) : bitRateInfo,
                ))
                  huyaBitRateProjection(rate),
              ],
              'flvRateArray': [
                for (final rate in HuyaSite.parseBitRates(payload['data']['stream']['flv']['rateArray']))
                  huyaBitRateProjection(rate),
              ],
            },
            'helpers': huyaPayloadHelpers(payload),
            'getRoomDetailForRefresh': roomProjection(refreshed),
          },
        );
      });
    }
  });

  group('S06 profileRoom not live', () {
    for (final sample in ['S06-off', 'S06-replay', 'S06-notfound', 'S06-alias']) {
      test(sample, () async {
        final fixture = huyaSample(sample);
        replayHuya([fixture]);
        final roomId = fixture.url.queryParameters['roomid']!;
        final site = HuyaSite();
        expectRecorded(fixture, 'HuyaSite.getRoomDetail + getRoomDetailForRecording + getRoomDetailForRefresh', {
          'getRoomDetail': await huyaOutcome(
            () => site.getRoomDetail(platform: 'huya', roomId: roomId),
            roomProjection,
          ),
          'getRoomDetailForRecording': await huyaOutcome(
            () => site.getRoomDetailForRecording(platform: 'huya', roomId: roomId),
            roomProjection,
          ),
          'getRoomDetailForRefresh': await huyaOutcome(
            () => site.getRoomDetailForRefresh(platform: 'huya', roomId: roomId),
            roomProjection,
          ),
          'helpers': huyaPayloadHelpers(fixture.json),
        });
      });
    }
  });
}
