// Legacy expected values for the recorded Douyin samples (spec/sites/douyin.md §11).
//
// Instance methods run through the production Dio with the network adapter
// replaced (douyin_support.dart matches host + path, because Douyin serves the
// same path from live.douyin.com and webcast.amemv.com). Signed requests are
// re-signed with random msToken/a_bogus during replay; only paths are compared.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/site/douyin/douyin_search.dart';
import 'package:pure_live/core/site/douyin/douyin_site.dart';

import 'douyin_support.dart';
import 'support.dart';

FixtureSample _load(String sample) => FixtureSample.load('douyin', sample);

/// The HTML samples (S01, S06) wait until live_cli scrubs `&quot;`-quoted JSON
/// and `&`-separated URL parameters; their tests run once recorded.
Object _missing(String sample) =>
    Directory('fixtures/douyin/$sample').existsSync() ? false : '$sample is not recorded yet (HTML scrubbing)';

Future<Map<String, dynamic>> _roomDetail(DouyinFixtureAdapter adapter, String roomId) async {
  final room = await DouyinSite().getRoomDetail(platform: 'douyin', roomId: roomId);
  final qualities = DouyinSite.parseStreamQualities(room.data);
  return {
    'requests': adapter.requestLog,
    'room': douyinRoomProjection(room),
    'qualities': qualityProjection(qualities),
    'geometry': geometryPerQuality(room.data, qualities),
  };
}

Future<Map<String, dynamic>> _roomDetailError(DouyinFixtureAdapter adapter, String roomId) async {
  Object? error;
  try {
    await DouyinSite().getRoomDetail(platform: 'douyin', roomId: roomId);
  } on Object catch (caught) {
    error = caught;
  }
  expect(error, isNotNull, reason: 'the legacy detail never returns an unknown-status room');
  return {'requests': adapter.requestLog, 'error': errorProjection(error!)};
}

const _detailGenerator =
    'DouyinSite.getRoomDetail + DouyinSite.parseStreamQualities + LiveStreamGeometryHintResolver.resolveDouyin';

void main() {
  setUpDouyinSettings();

  test('S01-home', () async {
    final fixture = _load('S01-home');
    final extracted = DouyinSite().extractCategoryDataJson(fixture.bodyFile.readAsStringSync());
    replayDouyin([fixture]);
    final categories = await DouyinSite().getCategores(1, 30);
    expectRecorded(fixture, 'DouyinSite.extractCategoryDataJson + DouyinSite.getCategores', {
      'categoryDataFound': extracted.isNotEmpty,
      'categories': [
        for (final category in categories)
          {
            'id': category.id,
            'name': category.name,
            'children': [
              for (final area in category.children)
                {
                  'areaId': area.areaId,
                  'areaType': area.areaType,
                  'typeName': area.typeName,
                  'areaName': area.areaName,
                },
            ],
          },
      ],
    });
  }, skip: _missing('S01-home'));

  test('S02-feed', () {
    final fixture = _load('S02-feed');
    final payload = fixture.json as Map<String, dynamic>;
    final rooms = DouyinSite.parseRecommendRooms(payload);
    final streams = <String, dynamic>{};
    for (final envelope in (payload['data'] as List).whereType<Map>()) {
      final raw = envelope['data'];
      final room = raw is String ? jsonDecode(raw) : raw;
      if (room is! Map) continue;
      final qualities = DouyinSite.parseStreamQualities(room['stream_url']);
      streams['${envelope['web_rid']}'] = {
        'qualities': qualityProjection(qualities),
        'geometry': geometryPerQuality(room['stream_url'], qualities),
      };
    }
    expectRecorded(
      fixture,
      'DouyinSite.parseRecommendRooms (douyinOnlineViewers/douyinTotalViewers) + DouyinSite.parseStreamQualities '
      '+ LiveStreamGeometryHintResolver.resolveDouyin',
      {
        'rooms': [for (final room in rooms) douyinRoomProjection(room)],
        'streams': streams,
      },
    );
  });

  group('S03 partition rooms', () {
    for (final (sample, page) in [('S03-partition-p1', 1), ('S03-partition-p2', 2), ('S03-partition-empty', 101)]) {
      test(sample, () async {
        final fixture = _load(sample);
        final adapter = replayDouyin([fixture]);
        final area = LiveArea(
          platform: 'douyin',
          areaId: '${fixture.url.queryParameters['partition']},${fixture.url.queryParameters['partition_type']}',
          areaType: '103,4',
          typeName: '游戏',
          areaName: '射击游戏',
        );
        final rooms = await DouyinSite().getCategoryRooms(area, page: page);
        expect(adapter.requests.single.uri.queryParameters['offset'], fixture.url.queryParameters['offset']);
        expectRecorded(fixture, 'DouyinSite.getCategoryRooms', {
          'rooms': [for (final room in rooms) douyinRoomProjection(room)],
        });
      });
    }
  });

  group('S04 enter', () {
    for (final sample in ['S04-enter-live', 'S04-enter-live-portrait', 'S04-enter-offline']) {
      test(sample, () async {
        final fixture = _load(sample);
        final adapter = replayDouyin([fixture]);
        expectRecorded(fixture, _detailGenerator, await _roomDetail(adapter, fixture.url.queryParameters['web_rid']!));
      });
    }
    // status_code 4001038 and the empty 200 both fall through to the HTML
    // path, which has no recorded page here; the legacy then fails on HEAD.
    for (final sample in ['S04-enter-notfound', 'S04-enter-no-cookie']) {
      test(sample, () async {
        final fixture = _load(sample);
        final adapter = replayDouyin([fixture]);
        expectRecorded(
          fixture,
          'DouyinSite.getRoomDetail (enter, then HTML fallback without a recorded page)',
          await _roomDetailError(adapter, fixture.url.queryParameters['web_rid']!),
        );
      });
    }
  });

  group('S05 reflow', () {
    test('S05-reflow-live', () async {
      final fixture = _load('S05-reflow-live');
      final adapter = replayDouyin([fixture]);
      expectRecorded(fixture, _detailGenerator, await _roomDetail(adapter, fixture.url.queryParameters['room_id']!));
    });

    test('S05-reflow-ended', () async {
      // status 4: the legacy re-queries enter with owner.web_rid; S04-enter-offline
      // was recorded for that web_rid.
      final fixture = _load('S05-reflow-ended');
      final adapter = replayDouyin([fixture, _load('S04-enter-offline')]);
      expectRecorded(fixture, _detailGenerator, await _roomDetail(adapter, fixture.url.queryParameters['room_id']!));
    });

    test('S05-reflow-shortlink-live', () async {
      // The v.douyin.com hop is synthetic (S07 has no recorded share link); it
      // redirects to the room's own share_url, as the app's share sheet does.
      final fixture = _load('S05-reflow-shortlink-live');
      final shareUrl = ((fixture.json as Map)['data'] as Map)['room']['share_url'] as String;
      final adapter = DouyinFixtureAdapter([fixture], redirects: {'https://v.douyin.com/fixture/': shareUrl});
      final result = await LiveUrlTool.parseLiveUrl(
        'https://v.douyin.com/fixture/',
        clientFactory: () => Dio()..httpClientAdapter = adapter,
      );
      expect(adapter.requests.last.uri.queryParameters['room_id'], fixture.url.queryParameters['room_id']);
      expectRecorded(fixture, 'LiveUrlTool.parseLiveUrl(clientFactory:)', {
        'requests': adapter.requestLog,
        'result': result,
      });
    });
  });

  test('S06-room-html-live', () async {
    final fixture = _load('S06-room-html-live');
    final adapter = replayDouyin([fixture]);
    expectRecorded(fixture, _detailGenerator, await _roomDetail(adapter, fixture.url.pathSegments.first));
  }, skip: _missing('S06-room-html-live'));

  group('S08 search', () {
    test('S08-live-search-anon', () {
      final fixture = _load('S08-live-search-anon');
      final rooms = DouyinSearch.parseSearchPayloadForTesting((fixture.json as Map)['data']);
      expectRecorded(fixture, 'DouyinSearch.parseSearchPayloadForTesting', {
        'rooms': [for (final room in rooms) douyinRoomProjection(room)],
      });
    });

    // Bodies that are not a single JSON document: how the legacy JSON request
    // hands them to the search code.
    for (final sample in ['S08-general-search-anon', 'S08-partition-rooms-unsigned']) {
      test(sample, () async {
        final fixture = _load(sample);
        replayDouyin([fixture]);
        Object? data;
        Object? error;
        try {
          data = await HttpClient.instance.getJson(fixture.url.toString());
        } on Object catch (caught) {
          error = caught;
        }
        expectRecorded(fixture, 'HttpClient.getJson (as used by DouyinSearch)', {
          'dataType': data?.runtimeType.toString(),
          'data': data,
          if (error != null) 'error': errorProjection(error),
        });
      });
    }

    test('S08 DouyinSearch.search flow', () async {
      final live = _load('S08-live-search-anon');
      final general = _load('S08-general-search-anon');
      final partitions = _load('S08-partition-search');
      final unsigned = _load('S08-partition-rooms-unsigned');
      final amemv = _load('S08-partition-rooms-amemv');
      final adapter = replayDouyin([live, general, partitions, unsigned, amemv]);
      final keyword = partitions.url.queryParameters['keyword']!;
      final rooms = await DouyinSearch.search(keyword);
      expectRecorded(partitions, 'DouyinSearch.search (anonymous request sequence)', {
        'requests': adapter.requestLog,
        'partitionRoomRequests': [
          for (final request in adapter.requests)
            if (request.uri.path == '/webcast/web/partition/detail/room/v2/')
              {
                'host': request.uri.host,
                for (final name in ['partition', 'partition_type', 'count', 'offset'])
                  name: request.uri.queryParameters[name],
              },
        ],
      });
      expectRecorded(amemv, 'DouyinSearch.search (partition-match fallback result)', {
        'rooms': [for (final room in rooms) douyinRoomProjection(room)],
      });
    });
  });

  group('S09 user/me', () {
    for (final (sample, cookie) in [
      ('S09-user-me-no-cookie', ''),
      ('S09-user-me-invalid-cookie', 'sessionid=fixture'),
    ]) {
      test(sample, () async {
        final fixture = _load(sample);
        replayDouyin([fixture]);
        expectRecorded(fixture, 'DouyinSite.getUserInfoByCookie', {
          'info': await DouyinSite().getUserInfoByCookie(cookie),
        });
      });
    }
  });
}
