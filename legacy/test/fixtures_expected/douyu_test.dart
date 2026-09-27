// Legacy expected values for the recorded Douyu samples (spec/sites/douyu.md §11).
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/core/site/douyu/douyu_site.dart';
import 'package:pure_live/core/site/v4_bridge/v4_bridge.dart';
import 'package:pure_live/core/site/douyu/douyu_utils.dart';
import 'package:pure_live/modules/search/web_search_room_parser.dart';

import 'douyu_support.dart';
import 'support.dart';

void main() {
  // These tests freeze the legacy parsers; keep lists off the v4 bridge.
  setUpAll(() => V4Bridge.platformsOverride = const {});
  tearDownAll(() => V4Bridge.platformsOverride = null);

  test('S01-cate-list', () async {
    final fixture = FixtureSample.load('douyu', 'S01-cate-list');
    replay([fixture]);
    final categories = await DouyuSite().getCategores(1, 0);
    expectRecorded(fixture, 'DouyuSite.getCategores', [
      for (final category in categories)
        {
          'id': category.id,
          'name': category.name,
          'children': [for (final area in category.children) area.toJson()],
        },
    ]);
  });

  group('S02 mixList category rooms', () {
    for (final sample in ['S02-mixlist-page1', 'S02-mixlist-last', 'S02-mixlist-beyond']) {
      test(sample, () async {
        final fixture = FixtureSample.load('douyu', sample);
        replay([fixture]);
        final [scope, page] = fixture.url.pathSegments.skip(fixture.url.pathSegments.length - 2).toList();
        final area = LiveArea(platform: 'douyu', areaId: scope.substring(2));
        final rooms = await DouyuSite().getCategoryRooms(area, page: int.parse(page));
        expectRecorded(fixture, 'DouyuSite.getCategoryRooms', [for (final room in rooms) roomProjection(room)]);
      });
    }
  });

  group('S03 allpage recommend rooms', () {
    for (final sample in ['S03-allpage-page1', 'S03-allpage-last', 'S03-allpage-beyond']) {
      test(sample, () async {
        final fixture = FixtureSample.load('douyu', sample);
        replay([fixture]);
        final rooms = await DouyuSite().getRecommendRooms(page: int.parse(fixture.url.pathSegments.last));
        expectRecorded(fixture, 'DouyuSite.getRecommendRooms', [for (final room in rooms) roomProjection(room)]);
      });
    }
  });

  group('S04 searchShow', () {
    for (final sample in [
      'S04-search-page1',
      'S04-search-page2',
      'S04-search-mixed',
      'S04-search-empty',
      'S04-search-error-kw',
      'S04-search-error-blank',
    ]) {
      test(sample, () async {
        final fixture = FixtureSample.load('douyu', sample);
        replay([fixture]);
        final query = fixture.url.queryParameters;
        final result = await settle(
          () async => [
            for (final room in await DouyuSite().searchRooms(
              query['kw']!,
              page: int.parse(query['page']!),
              pageSize: int.parse(query['pageSize']!),
            ))
              roomProjection(room),
          ],
        );
        expectRecorded(fixture, 'DouyuSite.searchRooms', result);
      });
    }
  });

  group('S05 betard room detail', () {
    for (final sample in ['S05-live', 'S05-offline', 'S05-replay-videoloop']) {
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

    for (final sample in ['S05-not-found', 'S05-alias-betard']) {
      test(sample, () async {
        final fixture = FixtureSample.load('douyu', sample);
        replay([fixture]);
        final roomId = fixture.url.pathSegments.last;
        final result = await settle(
          () async => roomProjection(await DouyuSite().getRoomDetailForRefresh(platform: 'douyu', roomId: roomId)),
        );
        expectRecorded(fixture, 'DouyuSite.getRoomDetailForRefresh', result);
      });
    }

    test('S05-alias-redirect', () {
      // Legacy never follows this redirect: the manual link tool passes the
      // alias to betard (S05-alias-betard). Freeze what the legacy room-URL
      // parser makes of the alias URL and of the redirect target.
      final fixture = FixtureSample.load('douyu', 'S05-alias-redirect');
      final location = (fixture.meta['response'] as Map<String, dynamic>)['headers']['location'] as String;
      final target = fixture.url.resolve(location).toString();
      Map<String, String>? parse(String url) {
        final parsed = WebSearchRoomParser.parse(url);
        return parsed == null ? null : {'platform': parsed.platform, 'roomId': parsed.roomId};
      }

      expectRecorded(fixture, 'WebSearchRoomParser.parse', {
        'status': fixture.status,
        'location': target,
        'aliasUrl': parse(fixture.url.toString()),
        'redirectTarget': parse(target),
      });
    });
  });

  test('S06-encryption', () {
    final fixture = FixtureSample.load('douyu', 'S06-encryption');
    final data = Map<String, dynamic>.from(fixture.json['data'] as Map);
    final capturedAt = DateTime.parse(fixture.meta['capturedAt'] as String).millisecondsSinceEpoch ~/ 1000;
    final expireAt = data['expire_at'] as int;
    expectRecorded(fixture, 'DouyuUtils.isEncryptionKeyUsable + DouyuUtils.buildSignedData', {
      'usableAtCapture': DouyuUtils.isEncryptionKeyUsable(data, nowSeconds: capturedAt),
      'usable31sBeforeExpiry': DouyuUtils.isEncryptionKeyUsable(data, nowSeconds: expireAt - 31),
      'usable30sBeforeExpiry': DouyuUtils.isEncryptionKeyUsable(data, nowSeconds: expireAt - 30),
      // The scrubbed descriptor still signs offline (rid 4489985, metadata form).
      'signedAtCapture': Uri.splitQueryString(
        DouyuUtils.buildSignedData(
          encryptionKey: data,
          roomId: '4489985',
          timestampSeconds: capturedAt,
          deviceId: fixture.url.queryParameters['did']!,
        ),
      ),
    });
  });

  test('S07-vectors', () {
    expectVectors('../fixtures/douyu/S07-vectors/vectors.json', 'vectors', signVector);
  });

  group('S08 getH5PlayV1 metadata (rate -1, cdn "")', () {
    for (final sample in ['S08-meta-4489985', 'S08-meta-24422']) {
      test(sample, () async {
        final fixture = FixtureSample.load('douyu', sample);
        final roomId = fixture.url.pathSegments.last;
        final data = DouyuSite.parsePlayResponse(fixture.json);
        final cdns = DouyuSite.parseCdnCodes(data);
        replayPlay([fixture]);
        final qualities = await DouyuSite().getPlayQualites(detail: douyuRoom(roomId));
        final expected = <String, Object?>{
          'parseCdnCodes': cdns,
          'parsePlayQualities': [
            for (final quality in DouyuSite.parsePlayQualities(data, cdns)) qualityProjection(quality),
          ],
          'getPlayQualites': [for (final quality in qualities) qualityProjection(quality)],
          'parsePlayUrl': DouyuSite.parsePlayUrl(data),
        };
        if (roomId == '24422') {
          // Cohort grouping over the per-CDN samples S09-24422-r0-{hw,hs}-h5.
          replayPlay([
            FixtureSample.load('douyu', 'S09-24422-r0-hw-h5'),
            FixtureSample.load('douyu', 'S09-24422-r0-hs-h5'),
          ]);
          final source = qualities.firstWhere((quality) => quality.id == 0);
          final resolution = await DouyuSite().resolvePlayUrlsRaw(detail: douyuRoom(roomId), quality: source);
          expected['resolvePlayUrlsRaw(rate 0)'] = resolutionProjection(resolution);
        }
        expectRecorded(
          fixture,
          'DouyuSite.parsePlayResponse + parseCdnCodes + parsePlayQualities + parsePlayUrl + getPlayQualites'
          '${roomId == '24422' ? ' + resolvePlayUrlsRaw' : ''}',
          expected,
        );
      });
    }
  });

  group('S09 getH5PlayV1 per CDN', () {
    for (final sample in [
      'S09-4489985-r0-hw-h5',
      'S09-24422-r0-hw-h5',
      'S09-24422-r0-hs-h5',
      'S09-24422-r2-hw-h5',
      'S09-24422-r0-tct-h5',
    ]) {
      test(sample, () async {
        final fixture = FixtureSample.load('douyu', sample);
        final form = recordedForm(fixture);
        replayPlay([fixture]);
        final resolution = await DouyuSite().resolvePlayUrl(
          fixture.url.pathSegments.last,
          int.parse(form['rate']!),
          form['cdn']!,
        );
        expectRecorded(fixture, 'DouyuSite.parsePlayUrl + DouyuSite.resolvePlayUrl', {
          'parsePlayUrl': DouyuSite.parsePlayUrl(DouyuSite.parsePlayResponse(fixture.json)),
          'resolvePlayUrl': resolutionProjection(resolution),
        });
      });
    }
  });

  group('S10 getH5PlayV1 errors', () {
    for (final sample in ['S10-offline', 'S10-wrong-did']) {
      test(sample, () async {
        final fixture = FixtureSample.load('douyu', sample);
        replayPlay([fixture]);
        expectRecorded(fixture, 'DouyuSite.parsePlayResponse + DouyuSite.getPlayQualites', {
          'parsePlayResponse': await settle(() => DouyuSite.parsePlayResponse(fixture.json)),
          'getPlayQualites': await settle(
            () async => [
              for (final quality in await DouyuSite().getPlayQualites(detail: douyuRoom(fixture.url.pathSegments.last)))
                qualityProjection(quality),
            ],
          ),
        });
      });
    }
  });

  test('S12-synthetic', () {
    expectVectors('../fixtures/douyu/S12-synthetic/vectors.json', 'cases', sessionCase);
  });
}
