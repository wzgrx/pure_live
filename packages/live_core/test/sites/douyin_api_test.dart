// Douyin parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json). Every intended difference is listed
// with its reason; everything else must match. The rules 3.x's own tests
// fixed (test/douyin_*_test.dart) are ported at the end.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('douyin', name);

Map<String, List<String>> _headers(Fixture fixture) => {
  for (final MapEntry(:key, :value) in ((fixture.meta['response'] as Map)['headers'] as Map).entries)
    '$key'.toLowerCase(): value is List ? [for (final item in value) '$item'] : ['$value'],
};

/// The room keys v4 added (M2.1), which 3.x never wrote.
const _v4Keys = {'startedAt', 'restriction'};

/// Asserts that [actual] (a `toJson`) equals 3.x's [legacy] map on every key
/// 3.x wrote, except [changed] (intended differences). 3.x wrote null where
/// the immutable model writes ''. The danmaku arguments and whether the
/// stream description was kept are not room JSON and are checked apart.
/// The v4 keys must be exactly [added] (M4.U, see each call's reason).
void _expectParity(
  Map<String, Object?> actual,
  Map<String, dynamic> legacy, {
  Set<String> changed = const {},
  Map<String, Object?> added = const {},
  String? reason,
}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (changed.contains(key) || key == 'danmakuData' || key == 'streamUrlKept') continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
  for (final key in _v4Keys) {
    expect(actual[key], added[key], reason: '${reason ?? ''} $key (v4 key)');
  }
}

/// M4.U (unified principle "受限", M2.1): a live detail with a video stream
/// says it has no restriction.
const Map<String, Object?> _playable = {'restriction': 'none'};

/// The raw room objects of a list sample by identity (feed envelopes or
/// partition items).
Map<String, Map<String, dynamic>> _rawRooms(Fixture fixture) {
  final data = (jsonDecode(fixture.body) as Map<String, dynamic>)['data'];
  final items = data is List ? data : (data as Map<String, dynamic>)['data'] as List;
  return {
    for (final item in items.cast<Map<String, dynamic>>())
      '${item['web_rid']}': switch (item['data'] ?? item['room']) {
        final String json => jsonDecode(json) as Map<String, dynamic>,
        final Map<String, dynamic> room => room,
        _ => throw StateError('no room'),
      },
  };
}

/// 3.x read `room_view_stats.display_value` as the cumulative count whatever
/// `display_type` said. With display type 1 it is the online count
/// ("713在线观众", what Douyin itself shows): the card keeps 3.x's number,
/// now as the online count, and has no cumulative count (REG-DOUYIN-008).
void _expectListRooms(List<LiveRoom> rooms, List<Map<String, dynamic>> legacy, Fixture fixture) {
  final raw = _rawRooms(fixture);
  expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
  for (final (index, room) in rooms.indexed) {
    final source = raw[room.roomId]!;
    final view = source['room_view_stats'] as Map<String, dynamic>;
    final name = '${fixture.meta['sample']}[$index]';
    if (view['display_type'] == 3) {
      _expectParity(room.toJson(), legacy[index], reason: name);
      continue;
    }
    expect(view['display_type'], 1, reason: name);
    expect(legacy[index]['totalViewers'], '${view['display_value']}', reason: '3.x took the online count as total');
    _expectParity(room.toJson(), legacy[index], changed: {'totalViewers', 'audienceMetricType'}, reason: name);
    expect(room.totalViewers, isEmpty, reason: name);
    expect(room.audienceMetricType, AudienceMetricType.onlineViewers, reason: name);
    expect(room.onlineViewers, '${view['display_value']}', reason: name);
  }
}

/// Quality list as 3.x's player saw it.
List<Map<String, Object?>> _qualities(List<LivePlayQuality> qualities) => [
  for (final quality in qualities)
    {'id': quality.id, 'quality': quality.quality, 'sort': quality.sort, 'urls': quality.data},
];

void main() {
  test('S01 categories: ids, names and areas match 3.x (each category lists itself first)', () {
    final fixture = _sample('S01-home');
    final categories = DouyinApi.categories(fixture.body, status: fixture.status, headers: _headers(fixture));
    final legacy = fixture.legacy as Map<String, dynamic>;
    expect(legacy['categoryDataFound'], isTrue);
    final expected = (legacy['categories'] as List).cast<Map<String, dynamic>>();
    expect(categories.map((category) => category.id), expected.map((category) => category['id']));
    expect(categories.map((category) => category.name), expected.map((category) => category['name']));
    for (final (index, category) in categories.indexed) {
      final areas = (expected[index]['children'] as List).cast<Map<String, dynamic>>();
      final twoLevels = category.children.where((area) => area.areaType == category.id).toList();
      expect(twoLevels, hasLength(areas.length));
      for (final (position, area) in twoLevels.indexed) {
        _expectParity(area.toJson(), areas[position], reason: 'S01[$index][$position]');
      }
      expect(category.children.every((area) => area.platform == 'douyin'), isTrue);
    }
    expect(DouyinApi.partition('1010032,1'), (partition: '1010032', type: '1'));
    expect(() => DouyinApi.partition('1010032'), throwsA(isA<NotFound>()));
  });

  test('S01 games (C-12): each 游戏 sub-category is followed by its games, a game listed twice once', () {
    final fixture = _sample('S01-home');
    final categories = DouyinApi.categories(fixture.body, status: fixture.status, headers: _headers(fixture));
    final games = categories.singleWhere((category) => category.name == '游戏').children;
    expect(games, hasLength(1 + 7 + 138), reason: '141 listed, 3 of them under two sub-categories');
    expect(games.map((area) => area.areaId).toSet(), hasLength(games.length));
    final shooting = games.indexWhere((area) => area.areaName == '射击游戏');
    expect(games[shooting + 1].toJson(), {
      'platform': 'douyin',
      'areaType': '1,1',
      'typeName': '射击游戏',
      'areaId': '1010032,1',
      'areaName': '和平精英',
      'areaPic': '',
      'shortName': '',
    });
    final lol = games.singleWhere((area) => area.areaName == '英雄联盟');
    expect((lol.areaId, lol.areaType, lol.typeName), ('1010014,1', '2,1', '竞技游戏'));
    expect(DouyinApi.partition(lol.areaId), (partition: '1010014', type: '1'));
    expect(games.singleWhere((area) => area.areaName == '星际战甲').typeName, '单机游戏', reason: 'also under 角色扮演');
    expect(categories.where((category) => category.name != '游戏').map((category) => category.children.length).toSet(), {
      1,
    });
  });

  group('S02 feed', () {
    final fixture = _sample('S02-feed');
    final legacy = fixture.legacy as Map<String, dynamic>;

    test('rooms, order and fields match 3.x; the online count is no longer called cumulative', () {
      final rooms = DouyinApi.feed(fixture.body, status: fixture.status, headers: _headers(fixture));
      // No v4 keys: the list's start_time and create_time are a placeholder
      // 0, and a list says nothing about restrictions.
      _expectListRooms(rooms, (legacy['rooms'] as List).cast<Map<String, dynamic>>(), fixture);
      expect(_rawRooms(fixture).values.map((room) => (room['start_time'], room['create_time'])).toSet(), {(0, 0)});
      expect(rooms.map((room) => room.area).toSet(), {DouyinApi.recommendArea});
      expect(rooms.every((room) => room.isLiveNow && room.link == 'https://live.douyin.com/${room.roomId}'), isTrue);
    });

    test('the qualities of every room match 3.x', () {
      final streams = legacy['streams'] as Map<String, dynamic>;
      final raw = _rawRooms(fixture);
      expect(streams.keys, raw.keys);
      for (final MapEntry(key: webRid, value: room) in raw.entries) {
        final expected = (streams[webRid] as Map<String, dynamic>)['qualities'];
        expect(_qualities(DouyinApi.qualities(room['stream_url'] as Map<String, dynamic>)), expected, reason: webRid);
      }
    });

    test('codec from sdk_params.VCodec agrees with options v_codec; HEVC rooms exist', () {
      final codecs = <String?>{};
      for (final MapEntry(key: webRid, value: room) in _rawRooms(fixture).entries) {
        final streamUrl = room['stream_url'] as Map<String, dynamic>;
        final pull = (streamUrl['live_core_sdk_data'] as Map<String, dynamic>)['pull_data'] as Map<String, dynamic>;
        final options = {
          for (final option
              in ((pull['options'] as Map?)?['qualities'] as List? ?? const []).cast<Map<String, dynamic>>())
            option['sdk_key']: option['v_codec'],
        };
        for (final quality in DouyinApi.qualities(streamUrl)) {
          final lines = DouyinApi.resolution(
            streamUrl,
            quality: quality,
            webRid: webRid,
            issuedAt: fixture.capturedAt,
          ).lines;
          codecs.add(lines.first.codec);
          final option = options[quality.id];
          if (option != null) {
            expect(lines.first.codec, option == '264' ? 'avc' : 'hevc', reason: '$webRid ${quality.id}');
          }
        }
      }
      expect(codecs, containsAll(['avc', 'hevc']));
    });
  });

  group('S03 partition rooms', () {
    for (final (name, more) in [
      ('S03-partition-p1', true),
      ('S03-partition-p2', true),
      ('S03-partition-empty', false),
    ]) {
      test('$name matches 3.x; more pages follow data.offset', () {
        final fixture = _sample(name);
        final offset = int.parse(fixture.url.queryParameters['offset']!);
        final page = DouyinApi.partitionRooms(
          fixture.body,
          offset: offset,
          status: fixture.status,
          headers: _headers(fixture),
        );
        final legacy = ((fixture.legacy as Map<String, dynamic>)['rooms'] as List).cast<Map<String, dynamic>>();
        _expectListRooms(page.rooms, legacy, fixture);
        expect(page.rooms.map((room) => room.area), legacy.map((room) => room['area']));
        expect(page.hasMore, more, reason: 'data.count and data.offset, never the number of rooms');
      });
    }

    test('a captcha (empty 200 with bdturing-verify) is RiskControl; 3.x saw null data', () {
      final fixture = _sample('S08-partition-rooms-unsigned');
      expect((fixture.legacy as Map<String, dynamic>)['data'], isNull);
      expect(
        () => DouyinApi.partitionRooms(fixture.body, offset: 0, status: fixture.status, headers: _headers(fixture)),
        throwsA(isA<RiskControl>()),
      );
    });
  });

  group('S04 enter', () {
    for (final name in ['S04-enter-live', 'S04-enter-live-portrait', 'S04-enter-offline']) {
      test('$name: the room, its danmaku ids and qualities match 3.x', () {
        final fixture = _sample(name);
        final webRid = fixture.url.queryParameters['web_rid']!;
        final parsed = DouyinApi.enter(
          fixture.body,
          webRid: webRid,
          status: fixture.status,
          headers: _headers(fixture),
        );
        final legacy = fixture.legacy as Map<String, dynamic>;
        final legacyRoom = legacy['room'] as Map<String, dynamic>;
        final raw = (((jsonDecode(fixture.body) as Map)['data'] as Map)['data'] as List).first as Map<String, dynamic>;
        final stats = raw['stats'] as Map<String, dynamic>?;
        // enter has no start time (no start_time or create_time): startedAt
        // stays null; a live room with video says it has no restriction.
        switch (name) {
          case 'S04-enter-live':
            // The exact online count (stats.user_count_str "2665") instead of
            // the bucketed room.user_count_str "2000+" (REG-DOUYIN-008).
            _expectParity(parsed.room.toJson(), legacyRoom, changed: {'onlineViewers'}, added: _playable);
            expect(legacyRoom['onlineViewers'], '2000+');
            expect(parsed.room.onlineViewers, stats!['user_count_str']);
          case 'S04-enter-live-portrait':
            // display_type 1: "2268在线观众" is the online count, which 3.x
            // showed as cumulative; the number stays, its meaning changes.
            _expectParity(
              parsed.room.toJson(),
              legacyRoom,
              changed: {'onlineViewers', 'totalViewers', 'audienceMetricType'},
              added: _playable,
            );
            expect((legacyRoom['totalViewers'], legacyRoom['onlineViewers']), ('2268', '2000+'));
            expect((parsed.room.onlineViewers, parsed.room.totalViewers, parsed.room.watching), ('2268', '', '2268'));
            expect(parsed.room.audienceMetricType, AudienceMetricType.onlineViewers);
            expect(stats!['user_count_str'], '2268');
          default:
            // Offline: neither a start time nor a restriction.
            _expectParity(parsed.room.toJson(), legacyRoom);
        }
        expect(parsed.room.roomId, webRid, reason: 'the identity is the requested web_rid');
        final danmaku = legacyRoom['danmakuData'] as Map<String, dynamic>;
        expect(parsed.roomId, danmaku['roomId']);
        expect(parsed.streamUrl != null, legacyRoom['streamUrlKept']);
        expect(_qualities(DouyinApi.qualities(parsed.streamUrl)), legacy['qualities']);
      });
    }

    test('a missing web_rid (4001038) is NotFound; 3.x fell back to the page and failed on HEAD', () {
      final fixture = _sample('S04-enter-notfound');
      expect(((fixture.legacy as Map)['error'] as Map)['message'], '发送HEAD请求失败');
      expect(
        () => DouyinApi.enter(fixture.body, webRid: '999999999999', status: fixture.status),
        throwsA(isA<NotFound>()),
      );
    });

    test('an empty 200 (no ttwid) is RiskControl; 3.x fell back to the page and failed on HEAD', () {
      final fixture = _sample('S04-enter-no-cookie');
      expect(fixture.body, isEmpty);
      expect(((fixture.legacy as Map)['error'] as Map)['type'], 'HttpError');
      expect(
        () => DouyinApi.enter(fixture.body, webRid: '547977714661', status: fixture.status),
        throwsA(isA<RiskControl>()),
      );
    });
  });

  group('S05 reflow', () {
    test('S05-reflow-live: identity is owner.web_rid; room and qualities match 3.x; the start time', () {
      final fixture = _sample('S05-reflow-live');
      final parsed = DouyinApi.reflow(fixture.body, status: fixture.status, headers: _headers(fixture));
      final legacy = fixture.legacy as Map<String, dynamic>;
      final legacyRoom = legacy['room'] as Map<String, dynamic>;
      final raw = ((jsonDecode(fixture.body) as Map)['data'] as Map)['room'] as Map<String, dynamic>;
      expect((raw['start_time'], raw['create_time']), (1789942248, 1789941901));
      // M4.U (unified principle "开播时间", M2.1): reflow's start_time.
      _expectParity(parsed.room.toJson(), legacyRoom, added: {..._playable, 'startedAt': '2026-09-20T22:10:48.000Z'});
      expect(parsed.room.startedAt, DateTime.utc(2026, 9, 20, 22, 10, 48));
      expect(parsed.sessionEnded, isFalse);
      expect(parsed.roomId, fixture.url.queryParameters['room_id']);
      expect(parsed.roomId, (legacyRoom['danmakuData'] as Map)['roomId']);
      expect(_qualities(DouyinApi.qualities(parsed.streamUrl)), legacy['qualities']);
    });

    test('S05-reflow-ended: status 4 → enter by owner.web_rid, as 3.x did', () {
      final fixture = _sample('S05-reflow-ended');
      final legacy = fixture.legacy as Map<String, dynamic>;
      expect(legacy['requests'], [
        'GET webcast.amemv.com/webcast/room/reflow/info/',
        'GET live.douyin.com/webcast/room/web/enter/',
      ]);
      final parsed = DouyinApi.reflow(fixture.body);
      expect(parsed.sessionEnded, isTrue);
      expect(parsed.room.roomId, (legacy['room'] as Map)['roomId']);
      expect(
        (parsed.room.startedAt, parsed.room.restriction),
        (null, null),
        reason: 'an ended broadcast has no start time to show (its start_time is 2024-06-03), nor a restriction',
      );
      final enter = _sample('S04-enter-offline');
      final entered = DouyinApi.enter(enter.body, webRid: parsed.room.roomId);
      _expectParity(entered.room.toJson(), legacy['room'] as Map<String, dynamic>);
    });

    test("S05-reflow-shortlink-live: the short link's web_rid is 3.x's answer", () {
      final fixture = _sample('S05-reflow-shortlink-live');
      final result = (fixture.legacy as Map<String, dynamic>)['result'] as List;
      expect(DouyinApi.reflowWebRid(fixture.body), result.first);
      expect(DouyinApi.reflow(fixture.body).room.roomId, result.first);
    });
  });

  group('S06 room page', () {
    final fixture = _sample('S06-room-html-live');
    final legacy = fixture.legacy as Map<String, dynamic>;
    final legacyRoom = legacy['room'] as Map<String, dynamic>;
    final parsed = DouyinApi.roomPage(
      fixture.body,
      webRid: '547977714661',
      status: fixture.status,
      headers: _headers(fixture),
    );

    test('the room matches 3.x but for the introduction and the exact online count', () {
      // introduction: 3.x filled it with the title; the page has no
      // owner.signature. onlineViewers: the exact count, not "5000+". The
      // page has no start time.
      _expectParity(parsed.room.toJson(), legacyRoom, changed: {'introduction', 'onlineViewers'}, added: _playable);
      expect(legacyRoom['introduction'], legacyRoom['title']);
      expect(parsed.room.introduction, '');
      expect(legacyRoom['onlineViewers'], '5000+');
      expect(parsed.room.onlineViewers, matches(RegExp(r'^\d+$')));
      final danmaku = legacyRoom['danmakuData'] as Map<String, dynamic>;
      expect(parsed.roomId, danmaku['roomId']);
      expect(parsed.userUniqueId, danmaku['userId'], reason: "the page's own 19-digit visitor id");
    });

    test(r'stream_data "$13" is resolved: the new qualities, each old one an alias (REG-DOUYIN-018)', () {
      // 3.x never resolved the payload reference, so stream_data failed to
      // decode and only the old FULL_HD1/HD1/SD2/SD1 maps remained (no MD).
      final expected = (legacy['qualities'] as List).cast<Map<String, dynamic>>();
      expect(expected.map((quality) => quality['id']), ['full_hd1', 'hd1', 'sd2', 'sd1']);
      final qualities = DouyinApi.qualities(parsed.streamUrl);
      expect(qualities.map((quality) => quality.id), ['origin', 'hd', 'sd', 'ld', 'md']);
      for (final old in expected) {
        final alias = DouyinApi.qualityFor(parsed.streamUrl, old['id'])!;
        expect(alias.data, old['urls'], reason: '${old['id']} is ${alias.id}');
      }
    });
  });

  group('S08 search', () {
    test('live search without a login is NeedsLogin (2483); 3.x read it as no results', () {
      final fixture = _sample('S08-live-search-anon');
      expect((fixture.legacy as Map)['rooms'], isEmpty);
      expect(() => DouyinApi.searchRooms(fixture.body, status: fixture.status), throwsA(isA<NeedsLogin>()));
    });

    test('the general search body is chunk framed and read; NeedsLogin (3.x: HttpError)', () {
      final fixture = _sample('S08-general-search-anon');
      expect(fixture.body, startsWith('5c\r\n'));
      expect(((fixture.legacy as Map)['error'] as Map)['type'], 'HttpError');
      expect(() => DouyinApi.searchRooms(fixture.body, status: fixture.status), throwsA(isA<NeedsLogin>()));
    });

    test('name-matched partitions are the areas 3.x asked for rooms', () {
      final fixture = _sample('S08-partition-search');
      final areas = DouyinApi.partitionSearch(fixture.body, status: fixture.status);
      expect(areas.map((area) => (area.areaId, area.areaName)), [('1010032,1', '和平精英')]);
      final requests = ((fixture.legacy as Map)['partitionRoomRequests'] as List).cast<Map<String, dynamic>>();
      for (final request in requests) {
        expect('${request['partition']},${request['partition_type']}', areas.single.areaId);
      }
    });

    test('the amemv partition rooms match 3.x; an empty tag_name shows the partition', () {
      final fixture = _sample('S08-partition-rooms-amemv');
      final rooms = DouyinApi.partitionRooms(
        fixture.body,
        offset: 0,
        areaName: '和平精英',
        status: fixture.status,
        headers: _headers(fixture),
      ).rooms;
      final legacy = ((fixture.legacy as Map)['rooms'] as List).cast<Map<String, dynamic>>();
      _expectListRooms(rooms, legacy, fixture);
      expect(rooms.map((room) => room.area).toSet(), {'和平精英'});
    });
  });

  test('S09 user/me 20003 is NeedsLogin; 3.x returned the error data as the account', () {
    for (final name in ['S09-user-me-no-cookie', 'S09-user-me-invalid-cookie']) {
      final fixture = _sample(name);
      expect(((fixture.legacy as Map)['info'] as Map)['message'], "User doesn't login", reason: name);
      expect(() => DouyinApi.account(fixture.body, status: fixture.status), throwsA(isA<NeedsLogin>()));
    }
    expect(
      DouyinApi.account(
        jsonEncode({
          'status_code': 0,
          'data': {'nickname': ' 主播 '},
        }),
      ),
      '主播',
    );
  });

  group('lines', () {
    final fixture = _sample('S04-enter-live-portrait');
    final parsed = DouyinApi.enter(fixture.body, webRid: '153806988623');

    test('each line has the media headers, its format and codec, and a lease from its expiry', () {
      final quality = DouyinApi.qualities(parsed.streamUrl).first;
      final resolution = DouyinApi.resolution(
        parsed.streamUrl,
        quality: quality,
        webRid: '153806988623',
        issuedAt: fixture.capturedAt,
        cookie: 'ttwid=x',
      );
      expect(resolution.appliedQualityData, 'origin');
      expect(resolution.urls, quality.data);
      expect(resolution.lines.map((line) => (line.format, line.lineId)), [
        (StreamFormat.flv, 'flv'),
        (StreamFormat.hls, 'hls'),
      ]);
      for (final line in resolution.lines) {
        expect(line.headers, {
          'user-agent': DouyinApi.userAgent,
          'origin': 'https://live.douyin.com',
          'referer': 'https://live.douyin.com/153806988623',
          'cookie': 'ttwid=x',
        });
        expect(line.codec, 'avc');
        final lease = line.lease!;
        expect(lease.cutsConnection, isFalse);
        expect(lease.expiresAt!.difference(fixture.capturedAt).inMinutes, closeTo(7 * 24 * 60, 1));
        expect(lease.expiresAt!.difference(lease.refreshAt), DouyinApi.leaseLead);
      }
    });

    test('an alias id plays its quality; an unknown id plays the URLs it carries', () {
      final alias = DouyinApi.resolution(
        parsed.streamUrl,
        quality: const LivePlayQuality(quality: '蓝光', id: 'FULL_HD1'),
        webRid: '1',
        issuedAt: fixture.capturedAt,
      );
      expect(alias.appliedQualityData, 'origin');
      final unknown = DouyinApi.resolution(
        parsed.streamUrl,
        quality: const LivePlayQuality(quality: 'x', id: 'gone', data: ['https://a.test/x.m3u8', 'ftp://a.test/y']),
        webRid: '1',
        issuedAt: fixture.capturedAt,
      );
      expect(unknown.lines.map((line) => (line.url, line.format)), [('https://a.test/x.m3u8', StreamFormat.hls)]);
      expect(unknown.appliedQualityData, 'gone');
    });

    test('media headers without a web_rid use the site root; no cookie, no header', () {
      expect(DouyinApi.mediaHeaders(''), {
        'user-agent': DouyinApi.userAgent,
        'origin': 'https://live.douyin.com',
        'referer': 'https://live.douyin.com/',
      });
    });

    test('lease: expire decimal or hex, volcTime, wsTime + keeptime, k + t; others have none', () {
      final issued = DateTime.utc(2026, 9, 27, 9, 51, 28);
      final expiry = DateTime.utc(2026, 10, 4, 9, 51, 28);
      for (final query in [
        'expire=1791107488',
        'expire=6ac221a0',
        'volcTime=1791107488',
        'keeptime=00093a80&wsTime=6ab8e720',
        'k=abc&t=1791107488',
      ]) {
        final lease = DouyinApi.lease(Uri.parse('https://a.test/x.flv?$query'), issued)!;
        expect(lease.expiresAt, expiry, reason: query);
        expect(lease.refreshAt, expiry.subtract(const Duration(minutes: 10)), reason: query);
      }
      for (final query in ['auth_key=0795179846-7-2-x', 't=1791107488', 'expire=0', '']) {
        expect(DouyinApi.lease(Uri.parse('https://a.test/x.flv?$query'), issued), isNull, reason: query);
      }
      final short = DouyinApi.lease(Uri.parse('https://a.test/x.flv?expire=1790502748'), issued)!;
      expect(short.expiresAt!.difference(short.refreshAt), const Duration(seconds: 15), reason: 'a quarter');
    });
  });

  group('F.1b picture size (3.x LiveStreamGeometryHint)', () {
    Map<String, (int?, int?)> sizes(String sample, String webRid) {
      final fixture = _sample(sample);
      final parsed = DouyinApi.enter(fixture.body, webRid: webRid);
      return {
        for (final quality in DouyinApi.qualities(parsed.streamUrl))
          '${quality.id}': switch (DouyinApi.resolution(
            parsed.streamUrl,
            quality: quality,
            webRid: webRid,
            issuedAt: fixture.capturedAt,
          ).lines) {
            final lines => (lines.first.width, lines.first.height),
          },
      };
    }

    test('every line of a quality carries the size the recorded samples declare', () {
      expect(sizes('S04-enter-live-portrait', '153806988623'), {
        'origin': (1088, 1920),
        'hd': (720, 1270),
        'sd': (540, 952),
        'ld': (480, 847),
        'md': (240, 423),
      });
      expect(sizes('S04-enter-live', '547977714661')['origin'], (1920, 1080));
      // The game room's original quality declares no resolution anywhere:
      // no size rather than another quality's.
      final game = sizes('S04-enter-live-game', '1');
      expect(game['origin'], (null, null));
      expect(game['full_hd1'], (1440, 1080), reason: 'uhd, its alias, declares it');

      final fixture = _sample('S04-enter-live-portrait');
      final parsed = DouyinApi.enter(fixture.body, webRid: '153806988623');
      final origin = DouyinApi.resolution(
        parsed.streamUrl,
        quality: DouyinApi.qualities(parsed.streamUrl).first,
        webRid: '153806988623',
        issuedAt: fixture.capturedAt,
      );
      expect(origin.lines, hasLength(2));
      for (final line in origin.lines) {
        expect(line.declaredAspectRatio, closeTo(1088 / 1920, 1e-9));
      }
      // An id the description does not have plays its own URLs, unsized.
      final unknown = DouyinApi.resolution(
        parsed.streamUrl,
        quality: const LivePlayQuality(quality: 'x', id: 'gone', data: ['https://a.test/x.flv']),
        webRid: '1',
        issuedAt: fixture.capturedAt,
      );
      expect(unknown.lines.single.width, isNull);
      // Normalising keeps the size.
      final spaced = LivePlayUrlResolution.lines(const [
        LivePlayLine(' https://a.test/x.flv ', width: 720, height: 1280),
      ]).normalized();
      expect((spaced.lines.single.width, spaced.lines.single.height), (720, 1280));
    });

    test("3.x's order: main, sdk_params width/height, sdk_params resolution, the quality's, the default's", () {
      ({int width, int height})? size({
        Map<String, dynamic>? main,
        Map<String, dynamic> descriptor = const {},
        Map<String, dynamic>? defaultQuality,
      }) => DouyinApi.pictureSize(main: main, descriptor: descriptor, defaultQuality: defaultQuality);

      final sdk = jsonEncode({'width': 720, 'height': 1280, 'resolution': '1080x1920'});
      expect(size(main: {'width': 540, 'height': 960, 'sdk_params': sdk}), (width: 540, height: 960));
      expect(size(main: {'sdk_params': sdk}), (width: 720, height: 1280));
      expect(
        size(
          main: {
            'sdk_params': jsonEncode({'resolution': '1080 × 1920'}),
          },
        ),
        (width: 1080, height: 1920),
      );
      expect(
        size(main: const {}, descriptor: {'resolution': '720x1280'}, defaultQuality: {'resolution': '1920x1080'}),
        (width: 720, height: 1280),
      );
      expect(size(main: const {}, defaultQuality: {'resolution': '1920x1080'}), (width: 1920, height: 1080));
      expect(size(main: const {}), isNull);
      // Implausible values do not count; the next source is used.
      expect(size(main: {'width': 0, 'height': 1280}, descriptor: {'resolution': '720x1280'}), (
        width: 720,
        height: 1280,
      ));
      expect(size(main: {'width': 100, 'height': 1280}), isNull, reason: 'under 120');
      expect(size(main: {'width': 4000, 'height': 1000}), isNull, reason: 'wider than 3.5');
      expect(size(main: {'width': 20000, 'height': 10000}), isNull, reason: 'over 16384');
    });
  });

  group('rules 3.x fixed (test/douyin_*_test.dart)', () {
    Map<String, dynamic> streamUrl({
      List<Map<String, Object?>> options = const [],
      Object? data,
      Map<String, String> flv = const {},
      Map<String, String> hls = const {},
      Map<String, String> names = const {},
    }) => {
      'live_core_sdk_data': {
        'pull_data': {
          'stream_data': data == null ? '' : jsonEncode({'data': data}),
          'options': {'qualities': options},
        },
      },
      'flv_pull_url': flv,
      'hls_pull_url_map': hls,
      'resolution_name': names,
    };

    test('old URL maps join by sdk key, never by position (REG-DOUYIN-004)', () {
      final qualities = DouyinApi.qualities(
        streamUrl(
          options: [
            {'name': '高清', 'sdk_key': 'HD1', 'v_bit_rate': 2000000},
            {'name': '流畅', 'sdk_key': 'SD2', 'v_bit_rate': 500000},
          ],
          flv: {'SD2': 'https://cdn.test/sd2.flv', 'HD1': 'https://cdn.test/hd1.flv'},
          hls: {'HD1': 'https://cdn.test/hd1.m3u8', 'SD2': 'https://cdn.test/sd2.m3u8'},
        ),
      );
      expect(qualities.map((quality) => quality.quality), ['高清', '流畅']);
      expect(qualities.first.selectionId, 'hd1');
      expect(qualities.first.data, ['https://cdn.test/hd1.flv', 'https://cdn.test/hd1.m3u8']);
      expect(qualities.last.data, ['https://cdn.test/sd2.flv', 'https://cdn.test/sd2.m3u8']);
    });

    test('stream_data qualities; advertised keys without URLs are left out', () {
      final qualities = DouyinApi.qualities(
        streamUrl(
          options: [
            {'name': '原画', 'sdk_key': 'origin'},
            {'name': '高清', 'sdk_key': 'HD'},
            {'name': '失效项', 'sdk_key': 'missing'},
          ],
          data: {
            'origin': {
              'main': {'flv': 'https://cdn.test/source.flv'},
            },
            'hd': {
              'main': {'flv': 'https://cdn.test/hd.flv', 'hls': 'https://cdn.test/hd.m3u8'},
            },
          },
        ),
      );
      expect(qualities.map((quality) => quality.quality), ['原画', '高清']);
      expect(qualities.map((quality) => quality.selectionId), ['origin', 'hd']);
    });

    test('tiers rank before the instantaneous bitrate; labels are localized (REG-DOUYIN-005)', () {
      final qualities = DouyinApi.qualities(
        streamUrl(
          options: [
            {'name': 'origin', 'sdk_key': 'origin', 'level': 4, 'v_bit_rate': 1200000},
            {'name': 'HD', 'sdk_key': 'HD', 'level': 3, 'v_bit_rate': 3000000},
            {'name': 'SD', 'sdk_key': 'SD', 'level': 2, 'v_bit_rate': 1500000},
            {'name': 'LD', 'sdk_key': 'LD', 'level': 1, 'v_bit_rate': 600000},
          ],
          data: {
            for (final key in ['origin', 'hd', 'sd', 'ld'])
              key: {
                'main': {'flv': 'https://cdn.test/$key.flv'},
              },
          },
        ),
      );
      expect(qualities.map((quality) => quality.quality), ['原画', '超清', '高清', '标清']);
      expect(qualities.map((quality) => quality.selectionId), ['origin', 'hd', 'sd', 'ld']);
    });

    test('old keys, sdk metadata and aliases with the same URLs (REG-DOUYIN-005/006)', () {
      const shared = 'https://cdn.test/source.flv';
      final qualities = DouyinApi.qualities(
        streamUrl(
          data: {
            'origin': {
              'main': {'flv': shared},
            },
            'FULL_HD1': {
              'main': {'flv': 'https://cdn.test/blue.flv'},
            },
            'HD1': {
              'main': {'flv': 'https://cdn.test/super.flv'},
            },
            'SD2': {
              'main': {'flv': 'https://cdn.test/high.flv'},
            },
            'SD1': {
              'main': {'flv': 'https://cdn.test/standard.flv'},
            },
            'MD': {
              'main': {
                'flv': 'https://cdn.test/smooth.flv',
                'sdk_params': jsonEncode({'vbitrate': 300000, 'resolution': '360x640'}),
              },
            },
            'ORIGION': {
              'main': {'flv': shared},
            },
          },
        ),
      );
      expect(qualities.map((quality) => quality.quality), ['原画', '蓝光', '超清', '高清', '标清', '流畅']);
      expect(qualities.map((quality) => quality.selectionId), ['origin', 'full_hd1', 'hd1', 'sd2', 'sd1', 'md']);
      expect(qualities.last.sort, 1000000);
    });

    test('audio-only renditions are not video qualities (REG-DOUYIN-001)', () {
      final qualities = DouyinApi.qualities(
        streamUrl(
          options: [
            {'name': '原画', 'sdk_key': 'origin'},
            {'name': 'ao', 'sdk_key': 'ao'},
            {'name': 'audio', 'sdk_key': 'future_audio'},
          ],
          data: {
            'origin': {
              'main': {'flv': 'https://cdn.test/source.flv?expire=1'},
            },
            'ao': {
              'main': {'flv': 'https://cdn.test/source.flv?expire=1&only_audio=1'},
            },
            'future_audio': {
              'main': {'flv': 'https://cdn.test/future.flv?only_audio=true'},
            },
          },
        ),
      );
      expect(qualities.map((quality) => quality.selectionId), ['origin']);
      expect(qualities.single.quality, '原画');
      expect(DouyinApi.qualities(null), isEmpty);
    });

    Map<String, dynamic> feedBody(Object? data, {int code = 0}) => {'status_code': code, 'data': data};

    test('the feed: the envelope list and the older data.data list, JSON-string rooms (REG-DOUYIN-007)', () {
      final current = DouyinApi.feed(
        jsonEncode(
          feedBody([
            {
              'web_rid': '123456',
              'data': {
                'id_str': '7654321',
                'title': '当前推荐直播',
                'owner': {
                  'nickname': '主播',
                  'web_rid': '123456',
                  'avatar_thumb': {
                    'url_list': ['https://example.com/avatar.webp'],
                  },
                },
                'cover': {
                  'url_list': ['https://example.com/cover.webp'],
                },
                'room_view_stats': {'display_value': '1.2万', 'user_count': 321},
              },
            },
          ]),
        ),
      );
      final room = current.single;
      expect((room.roomId, room.title, room.nick), ('123456', '当前推荐直播', '主播'));
      expect((room.cover, room.avatar), ('https://example.com/cover.webp', 'https://example.com/avatar.webp'));
      expect((room.totalViewers, room.onlineViewers), ('1.2万', '321'), reason: 'no display_type: 3.x rule');
      expect(room.isLiveNow, isTrue);

      final old = DouyinApi.feed(
        jsonEncode(
          feedBody({
            'data': [
              {
                'title': '旧结构',
                'owner': {'nickname': '旧主播', 'web_rid': 'legacy'},
                'cover': {
                  'url_list': ['https://example.com/legacy.webp'],
                },
              },
              {
                'web_rid': 'encoded',
                'data': jsonEncode({
                  'title': '字符串结构',
                  'owner': {'nickname': '新主播'},
                }),
              },
              {'web_rid': 'legacy', 'title': 'dup', 'owner': <String, dynamic>{}},
              'junk',
            ],
          }),
        ),
      );
      expect(old.map((room) => (room.roomId, room.title)), [('legacy', '旧结构'), ('encoded', '字符串结构')]);
    });

    test('the feed: user_count is online, a total_user of 0 is a placeholder, areas from tags', () {
      final rooms = DouyinApi.feed(
        jsonEncode(
          feedBody([
            {
              'web_rid': 'online-room',
              'data': {
                'title': '在线口径',
                'user_count': 1757,
                'stats': {'total_user': 0, 'user_count_str': '1757'},
                'owner': {'nickname': '主播'},
                'partition_road_map': [
                  {'title': '游戏'},
                ],
              },
            },
            {
              'web_rid': '0',
              'room': {'id_str': '7000000000000000002', 'title': 'b', 'tag_name': '音乐'},
            },
          ]),
        ),
      );
      final room = rooms.first;
      expect((room.watching, room.onlineViewers, room.totalViewers), ('1757', '1757', ''));
      expect(room.audienceMetricType, AudienceMetricType.onlineViewers);
      expect(rooms.map((room) => (room.roomId, room.area)), [('online-room', '游戏'), ('7000000000000000002', '音乐')]);
    });

    test('a feed rejection is typed, not an index error', () {
      expect(() => DouyinApi.feed(jsonEncode(feedBody(const [], code: 10001))), throwsA(isA<ApiChanged>()));
      expect(() => DouyinApi.feed(jsonEncode(feedBody(const [], code: 2483))), throwsA(isA<NeedsLogin>()));
    });

    test('audience: display_type 1 is online, 3 cumulative, others ignored; exact beats bucketed (REG-DOUYIN-008)', () {
      LiveRoom room(Map<String, dynamic> fields) => DouyinApi.enter(
        jsonEncode({
          'status_code': 0,
          'data': {
            'data': [
              {'id_str': '7000000000000000001', 'status': 2, 'title': 't', ...fields},
            ],
          },
        }),
        webRid: '1',
      ).room;
      final online = room({
        'room_view_stats': {'display_type': 1, 'display_value': 713},
        'stats': {'total_user': 0, 'total_user_str': '2万+'},
      });
      expect((online.onlineViewers, online.totalViewers, online.watching), ('713', '', '713'));
      expect(online.audienceMetricType, AudienceMetricType.onlineViewers);
      final cumulative = room({
        'user_count': 0,
        'room_view_stats': {'display_type': 3, 'display_value': 395780},
      });
      expect((cumulative.onlineViewers, cumulative.totalViewers), ('0', '395780'));
      final other = room({
        'user_count_str': '2000+',
        'room_view_stats': {'display_type': 7, 'display_value': 55},
      });
      expect((other.onlineViewers, other.totalViewers), ('2000+', ''));
      expect(other.audienceMetricType, AudienceMetricType.onlineViewers);
      final exact = room({
        'user_count_str': '2000+',
        'stats': {'user_count_str': '2665'},
      });
      expect(exact.onlineViewers, '2665');
      // 3.x's audience test: explicit online fields, never a cumulative one.
      expect(
        room({
          'room_view_stats': {'online_user_for_anchor': 3210, 'display_value': '56万'},
        }).onlineViewers,
        '3210',
      );
      expect(
        room({
          'room_view_stats': {'display_value': '56万'},
          'stats': {'total_user': 560000, 'total_user_str': '56万+'},
        }).onlineViewers,
        '',
      );
      final offline = room({'status': 4, 'user_count': 9});
      expect((offline.watching, offline.onlineViewers, offline.isExplicitlyOfflineNow), ('', '', true));
    });

    test(
      'search: nested and JSON-string rooms, web_rid else room_id, status 2 live, no duplicates (REG-DOUYIN-014)',
      () {
        String body(List<Object?> data) => jsonEncode({'status_code': 0, 'data': data});
        final rooms = DouyinApi.searchRooms(
          body([
            {
              'lives': {
                'rawdata': jsonEncode({
                  'id_str': 'internal-room-id',
                  'status': 2,
                  'title': '三角洲行动',
                  'owner': {
                    'nickname': '主播',
                    'avatar_thumb': {
                      'url_list': ['https://example.com/avatar.webp'],
                    },
                  },
                  'cover': {
                    'url_list': ['https://example.com/cover.webp'],
                  },
                  'room_view_stats': {'user_count': 321},
                }),
              },
            },
            {
              'aweme_info': {
                'live_info': {
                  'rawdata': {'room_id': '7000000000000000004', 'status': 4, 'title': 'ended', 'nickname': 'C'},
                },
              },
            },
            for (var i = 0; i < 2; i++)
              {
                'rawdata': jsonEncode({
                  'id_str': 'session-id',
                  'status': 2,
                  'title': '直播标题',
                  'owner': {'nickname': '主播', 'web_rid': 'stable-web-rid'},
                }),
              },
          ]),
        );
        expect(rooms.map((room) => (room.roomId, room.effectiveLiveStatus)), [
          ('internal-room-id', LiveStatus.live),
          ('7000000000000000004', LiveStatus.offline),
          ('stable-web-rid', LiveStatus.live),
        ]);
        expect(rooms.first.link, 'https://live.douyin.com/internal-room-id');
        expect(rooms.first.onlineViewers, '321');
        expect(rooms.first.cover, 'https://example.com/cover.webp');
        final framed = body([
          {
            'lives': {
              'rawdata': jsonEncode({
                'id_str': '1',
                'status': 2,
                'owner': {'web_rid': '22', 'nickname': 'B'},
              }),
            },
          },
        ]);
        expect(
          DouyinApi.searchRooms('${utf8.encode(framed).length.toRadixString(16)}\r\n$framed\r\n0\r\n\r\n')
              .single
              .roomId,
          '22',
        );
      },
    );

    test(r'page payload: "$$" escapes and "$undefined" are decoded', () {
      String push(String chunk) => '<script>self.__pace_f.push([1,${jsonEncode(chunk)}])</script>';
      final state = {
        'roomStore': {
          'roomInfo': {
            'room': {'id_str': '7000000000000000005', 'status': 4, 'title': r'$$5 room', 'owner': r'$undefined'},
            'anchor': {'nickname': 'D'},
          },
        },
        'userStore': {
          'odin': {'user_unique_id': '123'},
        },
      };
      final html =
          push('0:I["x"]\n') +
          push(
            '1:${jsonEncode([
              r'$',
              r'$L2',
              null,
              {'state': state},
            ])}\n',
          );
      final parsed = DouyinApi.roomPage(html, webRid: '33');
      expect((parsed.room.title, parsed.room.nick, parsed.room.isExplicitlyOfflineNow), (r'$5 room', 'D', true));
      expect((parsed.roomId, parsed.userUniqueId), ('7000000000000000005', null));
    });
  });

  group('M4.U upgrades', () {
    DouyinRoom enter(Map<String, Object?> data, Map<String, Object?> room) => DouyinApi.enter(
      jsonEncode({
        'status_code': 0,
        'data': {
          ...data,
          'data': [
            {'id_str': '7000000000000000001', 'title': 't', ...room},
          ],
        },
      }),
      webRid: '1',
    );

    Map<String, dynamic> recorded(String name) =>
        (jsonDecode(_sample(name).body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    final stream = ((recorded('S04-enter-live')['data'] as List).first as Map<String, dynamic>)['stream_url'];

    test('4-1: a missing status defers to data.room_status (0 live); status wins; neither is offline', () {
      // 3.x read a missing status as offline whatever room_status said.
      final live = enter({'room_status': 0}, {'stream_url': stream});
      expect((live.room.effectiveLiveStatus, live.room.isLiveNow), (LiveStatus.live, true));
      expect(live.streamUrl, isNotNull, reason: 'a live room keeps its streams');
      expect(DouyinApi.qualities(live.streamUrl), isNotEmpty);
      for (final (data, room, status) in [
        ({'room_status': '0'}, <String, Object?>{'status': ''}, LiveStatus.live),
        ({'room_status': 2}, <String, Object?>{}, LiveStatus.offline),
        ({'room_status': 1}, <String, Object?>{}, LiveStatus.offline),
        (<String, Object?>{}, <String, Object?>{}, LiveStatus.offline),
        ({'room_status': 0}, <String, Object?>{'status': 4}, LiveStatus.offline),
        ({'room_status': 2}, <String, Object?>{'status': 2}, LiveStatus.live),
      ]) {
        expect(enter(data, room).room.effectiveLiveStatus, status, reason: '$data $room');
      }
      // The recorded answers agree: status 2 with room_status 0, status 4
      // with room_status 2 (S04).
      for (final (name, roomStatus) in [('S04-enter-live', 0), ('S04-enter-offline', 2)]) {
        expect(recorded(name)['room_status'], roomStatus, reason: name);
      }
    });

    test('restriction (unified principle): a live detail without a video stream is unplayable', () {
      expect(enter(const {}, {'status': 2, 'stream_url': stream}).room.restriction, LiveRestriction.none);
      final bare = enter(const {}, {'status': 2}).room;
      expect((bare.isLiveNow, bare.restriction), (true, LiveRestriction.unplayable));
      expect(bare.followGroup, FollowGroup.live, reason: 'still live, marked on the card');
      final audioOnly = enter(const {}, {
        'status': 2,
        'stream_url': {
          'flv_pull_url': {'ao': 'https://cdn.test/a.flv?only_audio=1'},
        },
      }).room;
      expect(audioOnly.restriction, LiveRestriction.unplayable);
      expect(enter(const {}, {'status': 4}).room.restriction, isNull, reason: 'offline: nothing to restrict');
    });

    test('start time (unified principle): start_time, else create_time, in seconds; only while live', () {
      DateTime? startedAt(Map<String, Object?> room) => enter(const {}, {'status': 2, ...room}).room.startedAt;
      expect(startedAt({'start_time': 1789942248, 'create_time': 1789941901}), DateTime.utc(2026, 9, 20, 22, 10, 48));
      expect(startedAt({'start_time': 0, 'create_time': '1789941901'}), DateTime.utc(2026, 9, 20, 22, 5, 1));
      for (final value in [0, -1, '', 'x', 1789942248000, null]) {
        expect(startedAt({'start_time': value}), isNull, reason: '$value');
      }
      expect(enter(const {}, {'status': 4, 'start_time': 1789942248}).room.startedAt, isNull);
      expect(
        enter(const {}, {'status': 2, 'start_time': 1789942248}).room.toJson()['startedAt'],
        '2026-09-20T22:10:48.000Z',
      );
    });

    test('placeholder (unified principle, M2.1): a search card without a nickname has an empty name', () {
      final room = DouyinApi.searchRooms(
        jsonEncode({
          'status_code': 0,
          'data': [
            {
              'rawdata': jsonEncode({'id_str': '9', 'status': 2, 'title': 't'}),
            },
          ],
        }),
      ).single;
      // 3.x wrote "抖音直播"; empty keeps a follow's stored name and the UI
      // shows the localized site name.
      expect((room.nick, room.hasNick, room.displayNick('抖音')), ('', false, '抖音'));
    });
  });

  group('M4.D', () {
    test('S04-enter-live-game (2026-10-01): the detail names the game; 3.x left the area empty', () {
      final fixture = _sample('S04-enter-live-game');
      final parsed = DouyinApi.enter(fixture.body, webRid: '128200725053');
      expect(
        (parsed.room.area, parsed.room.isLiveNow, parsed.room.restriction),
        ('英雄联盟手游', true, LiveRestriction.none),
      );
      expect(parsed.roomId, '7691363078381833000');
      expect(DouyinApi.qualities(parsed.streamUrl).map((quality) => quality.id), isNotEmpty);
    });

    test('area: the game, else the road map (sub-partition, then partition); none stays empty', () {
      final data = (jsonDecode(_sample('S04-enter-live-game').body) as Map<String, dynamic>)['data'] as Map;
      final road = data['partition_road_map'];
      String? area(Map<String, Object?> extra, Map<String, Object?> room) => DouyinApi.enter(
        jsonEncode({
          'status_code': 0,
          'data': {
            ...extra,
            'data': [
              {'id_str': '7000000000000000001', 'status': 2, ...room},
            ],
          },
        }),
        webRid: '1',
      ).room.area;
      const noGame = {
        'game_data': {
          'game_tag_info': {'is_game': 2, 'game_tag_id': 0, 'game_tag_name': ''},
        },
      };
      expect(area({'partition_road_map': road}, noGame), '竞技游戏', reason: 'the sub-partition has no title');
      expect(
        area({
          'partition_road_map': {
            'partition': {'title': '竞技游戏'},
            'sub_partition': {
              'partition': {'title': '英雄联盟'},
            },
          },
        }, noGame),
        '英雄联盟',
      );
      expect(area({'partition_road_map': <String, Object?>{}}, noGame), '', reason: 'S04-enter-live, a chat room');
      expect(DouyinApi.enter(_sample('S04-enter-live').body, webRid: '547977714661').room.area, '');
    });
  });

  group('danmaku arguments', () {
    const args = DouyinDanmakuArgs(webRid: '5479', roomId: '7687', userId: '7312345678901234567', cookie: 'ttwid=s');

    test("3.x's handshake headers (REG-DOUYIN-003); no cookie, no header", () {
      expect(args.headers, {
        'user-agent': DouyinApi.userAgent,
        'cookie': 'ttwid=s',
        'origin': 'https://live.douyin.com',
        'referer': 'https://live.douyin.com/5479',
      });
      const guest = DouyinDanmakuArgs(webRid: '1', roomId: '2', userId: '3', cookie: ' ');
      expect(guest.headers.containsKey('cookie'), isFalse);
    });

    test('diagnostics never show the cookie', () {
      expect(args.toString(), isNot(contains('ttwid')));
      expect(jsonDecode(args.toString()), {
        'webRid': '5479',
        'roomId': '7687',
        'userId': '7312345678901234567',
        'cookie': '<redacted>',
      });
    });
  });

  test('errors are typed: captcha, 429, 5xx, 401/403, empty and non-JSON bodies, status codes', () {
    expect(
      () => DouyinApi.feed(
        '{}',
        status: 429,
        headers: const {
          'retry-after': ['30'],
        },
      ),
      throwsA(isA<RateLimited>().having((error) => error.retryAfter, 'retryAfter', const Duration(seconds: 30))),
    );
    expect(() => DouyinApi.feed('', status: 503), throwsA(isA<NetworkFailure>()));
    expect(() => DouyinApi.feed('x', status: 403), throwsA(isA<RiskControl>()));
    expect(() => DouyinApi.feed('x', status: 404), throwsA(isA<ApiChanged>()));
    expect(() => DouyinApi.feed(''), throwsA(isA<RiskControl>()));
    expect(() => DouyinApi.feed('<html>'), throwsA(isA<RiskControl>()));
    expect(() => DouyinApi.feed('[]'), throwsA(isA<ApiChanged>()));
    expect(() => DouyinApi.feed('{"status_code": 0, "data": {}}'), throwsA(isA<ApiChanged>()));
    expect(
      () => DouyinApi.enter('{"status_code":0,"data":{"data":[]}}', webRid: '1'),
      throwsA(isA<NotFound>()),
      reason: 'an empty room list',
    );
    expect(() => DouyinApi.reflow('{"status_code":0,"data":{"room":{"status":2}}}'), throwsA(isA<ApiChanged>()));
    expect(
      DouyinApi.enter('{"status_code":0,"data":{"data":[{"status":"2","title":"t"}]}}', webRid: '1').room.isLiveNow,
      isTrue,
      reason: 'a string "2" is live',
    );
    expect(() => DouyinApi.roomPage('<html></html>', webRid: '1'), throwsA(isA<ApiChanged>()));
    expect(() => DouyinApi.categories('<html></html>'), throwsA(isA<ApiChanged>()));
    for (final body in [
      'null',
      '[]',
      '{}',
      '{"data":[]}',
      '{"data":{"room":null}}',
      '{"data":{"room":{"owner":{}}}}',
      '{"data":{"room":{"owner":{"web_rid":[]}}}}',
      '{"data":{"room":{"owner":{"web_rid":"not-a-room"}}}}',
      'not json',
    ]) {
      expect(DouyinApi.reflowWebRid(body), isNull, reason: body);
    }
    expect(DouyinApi.reflowWebRid('{"data":{"room":{"owner":{"web_rid":456}}}}'), '456');
    expect(DouyinApi.isRoomId('7687741736843512602'), isTrue);
    expect(DouyinApi.isRoomId('547977714661'), isFalse);
  });
}
