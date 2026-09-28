// SOOP parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json: 3.x's soop_site.dart run over the same
// samples, docs/modules/M4.07-soop.md). Every intended difference is listed
// with its reason; everything else must match.
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('soop', name);

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

final DateTime _now = DateTime.utc(2026, 9, 27, 17, 30, 45);

/// Asserts that [actual] (a `toJson`) equals 3.x's [legacy] map on every key
/// 3.x wrote, except [changed] (intended differences). 3.x wrote null where
/// the immutable model writes ''.
void _expectParity(
  Map<String, Object?> actual,
  Map<String, dynamic> legacy, {
  Set<String> changed = const {},
  String? reason,
}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (changed.contains(key)) continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
}

/// List cards against 3.x's: same rooms in the same order, every field
/// equal.
void _expectRooms(List<LiveRoom> rooms, Object? legacy, {required String reason}) {
  final expected = (legacy! as List).cast<Map<String, dynamic>>();
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(room.toJson(), expected[index], reason: '$reason[$index]');
  }
}

/// The `CHANNEL` of a synthetic player API answer.
String _channel(Map<String, Object?> fields) => jsonEncode({'CHANNEL': fields});

void main() {
  group('S01 catalog', () {
    for (var page = 1; page <= 5; page++) {
      test('page $page: the areas 3.x listed', () {
        final fixture = _sample('S01-category-p$page');
        final result = SoopApi.categoryPage(fixture.body, status: fixture.status);
        final legacy = (_legacy('S01-category-p$page')['areas'] as List).cast<Map<String, dynamic>>();
        expect(result.areas.map((area) => area.areaId), legacy.map((area) => area['areaId']));
        for (final (index, area) in result.areas.indexed) {
          // 3.x wrote shortName null, the model ''; 3.x reads both the same.
          _expectParity(area.toJson(), legacy[index], reason: 'S01-p$page[$index]');
        }
        expect(result.hasMore, page < 5, reason: '`is_more` is false on the last page only');
      });
    }

    test('3.x walked five pages to 544 areas under one category "热门" (id 1)', () {
      final walked = (_legacy('S01-category-p1')['getCategores'] as List).single as Map<String, dynamic>;
      expect(walked, {'id': '1', 'name': '热门', 'areas': 544, 'pages': 5});
      expect(SoopApi.category, (id: '1', name: '热门'));
    });

    test("without `is_more` a full page has more (3.x's rule)", () {
      Map<String, Object?> page(int count) => {
        'result': 1,
        'data': {
          'list': [
            for (var i = 0; i < count; i++) {'category_no': '$i', 'category_name': 'a$i'},
          ],
        },
      };
      expect(SoopApi.categoryPage(jsonEncode(page(120))).hasMore, isTrue);
      expect(SoopApi.categoryPage(jsonEncode(page(119))).hasMore, isFalse);
      expect(SoopApi.categoryPage(jsonEncode(page(0))).hasMore, isFalse);
    });
  });

  group('lists', () {
    for (final (name, area) in [('S02-area-p1', '토크/캠방'), ('S02-area-short', 'FC 온라인')]) {
      test('$name: the rooms 3.x listed, the area named as asked', () {
        final fixture = _sample(name);
        final rooms = SoopApi.areaRooms(fixture.body, areaName: area, status: fixture.status);
        _expectRooms(rooms, _legacy(name)['rooms'], reason: name);
        expect(rooms.every((room) => room.area == area && room.isLiveNow), isTrue);
      });
    }

    test('titles keep their HTML entities as 3.x showed them (decoding is a later upgrade)', () {
      final rooms = SoopApi.areaRooms(_sample('S02-area-p1').body, areaName: '');
      expect(rooms.where((room) => room.title.contains('&amp;')), isNotEmpty);
      expect(SoopApi.recommendRooms(_sample('S03-main-p1').body).where((room) => room.title.contains('&gt;&lt;')), [
        isA<LiveRoom>(),
      ]);
    });

    for (final page in [1, 36, 37]) {
      test('S03 recommendations page $page: the rooms 3.x listed', () {
        final fixture = _sample('S03-main-p$page');
        final rooms = SoopApi.recommendRooms(fixture.body, status: fixture.status);
        _expectRooms(rooms, _legacy('S03-main-p$page')['rooms'], reason: 'S03-p$page');
        if (page == 37) expect(rooms, isEmpty, reason: 'the list ends with an empty page');
      });
    }

    test('the audience is PC plus mobile, never the PC-only current_view_cnt (REG-SOOP-003)', () {
      final fixture = _sample('S03-main-p1');
      final raw = ((jsonDecode(fixture.body) as Map)['broad'] as List).cast<Map<String, dynamic>>();
      final rooms = SoopApi.recommendRooms(fixture.body);
      var split = 0;
      for (final (index, room) in rooms.indexed) {
        final pc = int.parse('${raw[index]['pc_view_cnt']}');
        final mobile = int.parse('${raw[index]['mobile_view_cnt']}');
        expect(room.onlineViewers, '${raw[index]['total_view_cnt']}', reason: room.roomId);
        expect(int.parse(room.onlineViewers), pc + mobile, reason: room.roomId);
        if (mobile > 0) {
          split++;
          expect(room.onlineViewers, isNot('${raw[index]['current_view_cnt']}'), reason: room.roomId);
        }
        expect(room.effectiveAudienceMetricType, AudienceMetricType.onlineViewers);
      }
      expect(split, greaterThan(0));
    });

    test('S04 search: the rooms 3.x found, without an area as in 3.x', () {
      final fixture = _sample('S04-search-p1');
      final rooms = SoopApi.searchRooms(fixture.body, status: fixture.status);
      _expectRooms(rooms, _legacy('S04-search-p1')['rooms'], reason: 'S04');
      // 3.x read `standard_broad_cate_name`, which the answers no longer
      // carry; `broad_cate_name` has the area (a later upgrade).
      expect(rooms.every((room) => room.area == ''), isTrue);
      expect(fixture.body, contains('"broad_cate_name"'));
    });

    test('an empty search page is empty although HAS_MORE_LIST says more (REG-SOOP-007)', () {
      final fixture = _sample('S04-search-empty');
      final root = jsonDecode(fixture.body) as Map<String, dynamic>;
      expect(root['HAS_MORE_LIST'], isTrue);
      expect(SoopApi.searchRooms(fixture.body, status: fixture.status), isEmpty);
      expect(_legacy('S04-search-empty')['rooms'], isEmpty);
    });

    test('cards without user_id are skipped; missing fields are empty (3.x wrote "null" or threw)', () {
      final rooms = SoopApi.recommendRooms(
        jsonEncode({
          'broad': [
            {'broad_title': 'no id'},
            {'user_id': 'ab12'},
          ],
        }),
      );
      expect(rooms.single.roomId, 'ab12');
      expect(rooms.single.nick, '');
      expect(rooms.single.cover, '');
      expect(rooms.single.avatar, 'https://stimg.sooplive.co.kr/LOGO/ab/ab12/m/ab12.webp');
      expect(rooms.single.onlineViewers, '');
      final area = SoopApi.areaRooms(
        jsonEncode({
          'result': 1,
          'data': {
            'list': [
              {'user_id': 'cd34', 'thumbnail': '//liveimg.sooplive.com/m/1'},
            ],
          },
        }),
        areaName: 'x',
      ).single;
      expect(area.avatar, SoopApi.avatar('cd34'), reason: 'without user_profile_img the built avatar');
      expect(area.cover, 'https://liveimg.sooplive.com/m/1');
    });
  });

  group('audience', () {
    test("3.x's cases (legacy test/soop_platform_test.dart)", () {
      expect(
        SoopApi.onlineViewers({'current_view_cnt': '6372', 'm_current_view_cnt': '7834', 'total_view_cnt': '14206'}),
        '14206',
      );
      expect(SoopApi.onlineViewers({'pc_view_cnt': 12, 'mobile_view_cnt': 8}), '20');
      expect(SoopApi.onlineViewers({'view_cnt': 321}), '321');
      expect(SoopApi.onlineViewers({'RESULT': 1}), isEmpty);
      expect(SoopApi.onlineViewers({'total_view_cnt': 0}), '0');
    });

    test('PC plus mobile when there is no total; commas are ignored', () {
      expect(SoopApi.onlineViewers({'current_view_cnt': '10', 'm_current_view_cnt': '5'}), '15');
      expect(SoopApi.onlineViewers({'current_view_cnt': '10'}), '10');
      expect(SoopApi.onlineViewers({'total_view_cnt': '1,234'}), '1234');
      expect(SoopApi.onlineViewers({'total_view_cnt': '0', 'pc_view_cnt': '3', 'mobile_view_cnt': '4'}), '7');
      expect(SoopApi.onlineViewers({'pc_view_cnt': '0', 'mobile_view_cnt': '0'}), '0');
    });
  });

  group('S05 room', () {
    test('live: the room 3.x built, with the requested id and the broadcast in SoopRoomData', () {
      final fixture = _sample('S05-live-live');
      final legacy = _legacy('S05-live-live');
      final room = SoopApi.roomDetail(
        fixture.body,
        requestedId: 'khm11903',
        now: _now,
        withDanmaku: true,
        status: fixture.status,
      );
      final expected = legacy['getRoomDetail'] as Map<String, dynamic>;
      // userId: 3.x kept the broadcast number (BNO) there; it is in
      // SoopRoomData now. cover: 3.x's cache buster is the clock. data and
      // danmakuData are compared below.
      _expectParity(room.toJson(), expected, changed: {'userId', 'cover', 'data', 'danmakuData'}, reason: 'live');
      expect(room.userId, isNull);
      expect(room.cover, '${expected['cover']}'.replaceFirst('{now}', '${_now.millisecondsSinceEpoch}'));
      expect(room.link, 'https://play.sooplive.co.kr/khm11903');
      final data = room.data! as SoopRoomData;
      final legacyData = expected['data'] as Map<String, dynamic>;
      expect(data.bno, legacyData['bno']);
      expect(data.bno, expected['userId']);
      expect(data.rmd, legacyData['rmd']);
      expect(data.cdn, legacyData['cdn']);
      expect(data.password, isFalse);
      expect(data.presets.map((preset) => preset.name), [
        for (final preset in legacyData['viewpreset'] as List) (preset as Map)['name'],
      ]);
      expect(data.codecOf('original'), 'avc');
      expect(data.codecOf('auto'), isNull);
      final args = room.danmakuData! as SoopDanmakuArgs;
      final legacyArgs = expected['danmakuData'] as Map<String, dynamic>;
      expect(args.url.toString(), legacyArgs['url']);
      expect(args.chatNo, legacyArgs['chatNo']);
      _expectParity(
        SoopApi.roomDetail(fixture.body, requestedId: 'khm11903', now: _now).toJson(),
        legacy['getRoomDetailForRefresh'] as Map<String, dynamic>,
        changed: {'userId', 'cover', 'data'},
        reason: 'refresh',
      );
      expect((legacy['getRoomDetailForRefresh'] as Map).containsKey('danmakuData'), isFalse);
      expect(SoopApi.roomDetail(fixture.body, requestedId: 'khm11903', now: _now).danmakuData, isNull);
    });

    test('the requested id stays the identity (3.x took BJID)', () {
      final fixture = _sample('S05-live-live');
      final room = SoopApi.roomDetail(fixture.body, requestedId: 'KHM11903', now: _now);
      expect(room.roomId, 'KHM11903');
      expect(room.avatar, 'https://stimg.sooplive.co.kr/LOGO/kh/khm11903/khm11903.jpg', reason: 'the avatar is BJID');
    });

    for (final (name, id) in [('S05-live-offline', 'phonics1'), ('S05-live-missing', 'zzzqqqxxxnotexist1')]) {
      test('$name: RESULT 0 is offline on refresh and recording, a failed load at room entry, as in 3.x', () {
        final fixture = _sample(name);
        final legacy = _legacy(name);
        final room = SoopApi.roomDetail(fixture.body, requestedId: id, now: _now);
        _expectParity(room.toJson(), legacy['getRoomDetailForRefresh'] as Map<String, dynamic>, reason: name);
        _expectParity(room.toJson(), legacy['getRoomDetailForRecording'] as Map<String, dynamic>, reason: name);
        expect(room.effectiveLiveStatus, LiveStatus.offline, reason: 'REG-SOOP-005 kept: an unknown id too');
        expect(room.data, isNull);
        // 3.x's room entry lumped RESULT 0 with failures: an error room,
        // state unknown, "获取房间信息失败".
        expect((legacy['getRoomDetail'] as Map)['liveStatus'], LiveStatus.unknown.index);
        expect(
          () => SoopApi.roomDetail(fixture.body, requestedId: id, now: _now, withDanmaku: true, roomEntry: true),
          throwsA(isA<StreamUnavailable>()),
        );
        expect(legacy['getPlayQualites'], isEmpty);
      });
    }

    test('S05 adult: RESULT -6 is NeedsLogin (3.x: an unknown-state room, and StateError on refresh)', () {
      final fixture = _sample('S05-live-adult');
      final legacy = _legacy('S05-live-adult');
      expect(() => SoopApi.roomDetail(fixture.body, requestedId: 'bumzi98', now: _now), throwsA(isA<NeedsLogin>()));
      expect((legacy['getRoomDetail'] as Map)['liveStatus'], LiveStatus.unknown.index);
      expect(((legacy['getRoomDetailForRefresh'] as Map)['throws'] as Map)['type'], 'StateError');
      expect(((legacy['getRoomDetailForRecording'] as Map)['throws'] as Map)['type'], 'StateError');
    });

    test("RESULT -2 is banned (3.x's refresh), a failed load at room entry; no VIEWPRESET is offline", () {
      final banned = SoopApi.roomDetail(_channel({'RESULT': -2}), requestedId: 'ab12', now: _now);
      expect(banned.effectiveLiveStatus, LiveStatus.banned);
      expect(
        () => SoopApi.roomDetail(_channel({'RESULT': -2}), requestedId: 'ab12', now: _now, roomEntry: true),
        throwsA(isA<StreamUnavailable>()),
      );
      // 3.x's rule at every depth, room entry included: RESULT 1 without
      // presets is an offline room.
      final idle = SoopApi.roomDetail(
        _channel({'RESULT': 1, 'BJID': 'ab12', 'BNO': '9', 'TITLE': 'x'}),
        requestedId: 'ab12',
        now: _now,
        roomEntry: true,
      );
      expect(idle.effectiveLiveStatus, LiveStatus.offline);
      expect(idle.data, isNull, reason: 'no broadcast to stream');
    });

    test('missing fields are empty (3.x wrote "null" or threw); a password broadcast is marked', () {
      final room = SoopApi.roomDetail(
        _channel({
          'RESULT': 1,
          'VIEWPRESET': [
            {'name': 'hd', 'bps': 1000},
          ],
          'BPWD': 'Y',
          'BJID': 'a',
        }),
        requestedId: 'a',
        now: _now,
        withDanmaku: true,
      );
      expect(room.title, '');
      expect(room.nick, '');
      expect(room.cover, '');
      expect(room.avatar, '', reason: 'a one-letter id has no avatar path (3.x threw)');
      expect(room.danmakuData, isNull, reason: 'no chat server');
      expect((room.data! as SoopRoomData).password, isTrue);
    });

    test("answers that are not the player API's are typed errors", () {
      expect(() => SoopApi.channel('<html></html>'), throwsA(isA<ApiChanged>()));
      expect(() => SoopApi.channel('{"x":1}'), throwsA(isA<ApiChanged>()));
      expect(() => SoopApi.channel(_channel({'GDPR': false})), throwsA(isA<ApiChanged>()));
      expect(
        () => SoopApi.roomDetail(_channel({'RESULT': -7}), requestedId: 'a', now: _now),
        throwsA(isA<ApiChanged>()),
      );
      expect(() => SoopApi.channel('', status: 502), throwsA(isA<NetworkFailure>()));
      expect(() => SoopApi.channel('', status: 429), throwsA(isA<RateLimited>()));
      expect(() => SoopApi.channel('', status: 403), throwsA(isA<RiskControl>()));
      expect(() => SoopApi.channel('', status: 404), throwsA(isA<ApiChanged>()));
      expect(() => SoopApi.categoryPage('{"result":0,"msg":"x"}'), throwsA(isA<ApiChanged>()));
      expect(() => SoopApi.searchRooms('{"RESULT":"-1"}'), throwsA(isA<ApiChanged>()));
      expect(() => SoopApi.recommendRooms('{"broad":{}}'), throwsA(isA<ApiChanged>()));
    });
  });

  group('qualities', () {
    test("S05: 3.x's qualities, names, order and order values", () {
      final fixture = _sample('S05-live-live');
      final data = SoopApi.roomDetail(fixture.body, requestedId: 'khm11903', now: _now).data! as SoopRoomData;
      final qualities = SoopApi.qualities(data.presets);
      expect([
        for (final quality in qualities)
          {'quality': quality.quality, 'id': quality.id, 'data': quality.data, 'sort': quality.sort},
      ], _legacy('S05-live-live')['getPlayQualites']);
      // The 720p preset (hd4k) has no tier: it sorts by bitrate alone, after
      // 360p, under its request name, as 3.x showed it (a later upgrade).
      expect(qualities.map((quality) => quality.quality), ['原画', '高清', '标清', 'hd4k']);
    });

    test("3.x's case: auto and repeats dropped, a source without bitrate first (REG-SOOP-004)", () {
      final qualities = SoopApi.qualities(
        SoopApi.presets([
          {'name': 'auto', 'bps': 0},
          {'name': 'AUTO', 'bps': 0},
          {'name': 'original', 'bps': '0'},
          {'name': 'hd', 'bps': 2000000},
          {'name': 'HD', 'bps': 1000000},
          {'name': ' ', 'bps': 1},
        ]),
      );
      expect(qualities.map((quality) => quality.selectionId), ['original', 'hd']);
      expect(qualities.map((quality) => quality.quality), ['原画', '高清']);
      expect(qualities.first.sort, greaterThan(qualities.last.sort));
    });

    test('tiers: original > master > fullhd > hd > sd > low > other names by bitrate (3.x)', () {
      final names = ['low', 'x2', 'sd', 'hd', 'hd4k', 'fullhd', 'master', 'original', 'x1'];
      final qualities = SoopApi.qualities([
        for (final name in names) SoopPreset(name: name, bps: name == 'x1' ? 90000 : 10),
      ]);
      expect(qualities.map((quality) => quality.id), [
        'original',
        'master',
        'fullhd',
        'hd',
        'sd',
        'low',
        'x1',
        'x2',
        'hd4k',
      ]);
      expect(SoopApi.qualitySort('original', 0), 600000000);
      expect(SoopApi.qualitySort('hd4k', 4000), 4000);
    });
  });

  group('danmaku arguments', () {
    test("the TLS port next to CHPT (3.x's URL), the plain port, CHATNO and 3.x's headers", () {
      final fixture = _sample('S05-live-live');
      final channel = SoopApi.channel(fixture.body).channel;
      final args = SoopApi.danmakuArgs(channel, roomId: 'khm11903', cookie: 'a=1')!;
      expect(args.url.toString(), 'wss://chat-6e0a4c4e.sooplive.com:9001/Websocket/khm11903');
      expect(args.plainUrl.toString(), 'ws://chat-6e0a4c4e.sooplive.com:9000/Websocket/khm11903');
      expect(args.chatNo, '4172');
      // 3.x: getHeaders() with its UA and Origin replaced.
      expect(args.headers, {
        'accept': '*/*',
        'origin': 'https://play.sooplive.co.kr',
        'referer': 'https://www.sooplive.co.kr/',
        'sec-fetch-dest': 'empty',
        'sec-fetch-mode': 'cors',
        'sec-fetch-site': 'same-site',
        'user-agent': SoopApi.userAgent,
        'cookie': 'a=1',
      });
      expect(SoopApi.danmakuArgs(channel, roomId: 'khm11903')!.headers.containsKey('cookie'), isFalse);
    });

    test("3.x's endpoint cases (legacy test/soop_danmaku_endpoint_test.dart)", () {
      final domain = SoopApi.danmakuArgs({
        'CHDOMAIN': 'chat-DEE9364C.sooplive.com',
        'CHPT': '9000',
        'CHATNO': '1',
      }, roomId: 'khm11903')!;
      expect(domain.url.toString(), 'wss://chat-dee9364c.sooplive.com:9001/Websocket/khm11903');
      // From CHIP, 3.x's `.sooplive.co.kr` (the hosts the API names are on
      // sooplive.com; switching is a later upgrade).
      final ip = SoopApi.danmakuArgs({'CHIP': '222.233.54.76', 'CHPT': 9000, 'CHATNO': '1'}, roomId: 'room id')!;
      expect(ip.url.toString(), 'wss://chat-dee9364c.sooplive.co.kr:9001/Websocket/room%20id');
      expect(SoopApi.danmakuArgs({'CHDOMAIN': 'chat.example', 'CHPT': 65535, 'CHATNO': '1'}, roomId: 'room'), isNull);
      expect(SoopApi.danmakuArgs({'CHIP': '999.1.1.1', 'CHPT': 9000, 'CHATNO': '1'}, roomId: 'room'), isNull);
      expect(SoopApi.danmakuArgs({'CHDOMAIN': 'chat.example', 'CHPT': 9000}, roomId: 'room'), isNull);
      expect(SoopApi.danmakuArgs({'CHDOMAIN': 'chat.example', 'CHPT': 9000, 'CHATNO': '1'}, roomId: ' '), isNull);
    });

    test('the recorded danmaku session used the same endpoints', () {
      final meta = jsonDecode(_danmakuMeta()) as Map<String, dynamic>;
      final handshakes = [for (final shake in meta['handshakes'] as List) (shake as Map)['url']];
      final keys = meta['danmakuKeys'] as Map<String, dynamic>;
      final args = SoopApi.danmakuArgs({
        'CHDOMAIN': keys['chatHost'],
        'CHPT': keys['chatPort'],
        'CHATNO': keys['chatNo'],
      }, roomId: '${keys['bj']}')!;
      expect([args.url.toString(), args.plainUrl.toString()], handshakes);
    });
  });

  group('S06 streams', () {
    test('the assignment request and its playlist match 3.x', () {
      for (final name in ['original', 'hd']) {
        final fixture = _sample('S06-assign-$name');
        final legacy = _legacy('S06-assign-$name');
        final url = SoopApi.assignUrl(
          rmd: 'https://livestream-manager.sooplive.com',
          cdn: 'gcp_cdn',
          bno: '297314125',
          quality: name,
        );
        expect(url.toString(), (legacy['request'] as Map)['url']);
        expect(SoopApi.assignedPlaylist(fixture.body, status: fixture.status), legacy['getCdnUrl']);
      }
    });

    test('return_type and RMD rules', () {
      expect(SoopApi.returnType('gs_cdn'), 'gs_cdn_pc_web');
      expect(SoopApi.returnType('lg_cdn_x'), 'lg_cdn_pc_web');
      expect(SoopApi.returnType('gcp_cdn'), 'gcp_cdn');
      expect(
        SoopApi.assignUrl(rmd: 'https://m.example/base/', cdn: 'c', bno: '1', quality: 'hd').toString(),
        'https://m.example/base/broad_stream_assign.html?return_type=c&broad_key=1-common-hd-hls',
      );
      expect(() => SoopApi.assignUrl(rmd: 'nothing', cdn: 'c', bno: '1', quality: 'hd'), throwsA(isA<ApiChanged>()));
      expect(() => SoopApi.assignedPlaylist('{"result":"0"}'), throwsA(isA<StreamUnavailable>()));
      expect(() => SoopApi.assignedPlaylist('{"result":"1"}'), throwsA(isA<ApiChanged>()));
    });

    test('the stream key matches 3.x; an age-restricted key is NeedsLogin (3.x got an empty key)', () {
      for (final name in ['original', 'hd']) {
        final fixture = _sample('S06-aid-$name');
        expect(SoopApi.aid(fixture.body, status: fixture.status), _legacy('S06-aid-$name')['getStreamAid']);
      }
      final adult = _sample('S06-aid-adult');
      expect(_legacy('S06-aid-adult')['getStreamAid'], '');
      expect(() => SoopApi.aid(adult.body, status: adult.status), throwsA(isA<NeedsLogin>()));
      expect(
        () => SoopApi.aid(_channel({'RESULT': -10}), password: true),
        throwsA(isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('password'))),
      );
      expect(() => SoopApi.aid(_channel({'RESULT': 1, 'AID': ''})), throwsA(isA<StreamUnavailable>()));
    });

    test("the line: 3.x's URL with the media headers 3.x's player sent, HLS, no lease", () {
      final legacy = _legacy('S06-aid-original');
      final resolution = SoopApi.resolution(
        playlist: _legacy('S06-assign-original')['getCdnUrl'] as String,
        aid: legacy['getStreamAid'] as String,
        roomId: 'khm11903',
        quality: 'original',
        cdn: 'gcp_cdn',
        codec: 'avc',
        cookie: 'a=1',
      );
      expect(resolution.urls, legacy['getPlayUrls']);
      final line = resolution.lines.single;
      // 3.x's PlaybackHeaderResolver, SOOP branch.
      expect(line.headers, {
        'user-agent': SoopApi.mediaUserAgent,
        'origin': 'https://www.sooplive.co.kr',
        'referer': 'https://play.sooplive.co.kr/khm11903',
        'cookie': 'a=1',
      });
      expect(line.format, StreamFormat.hls);
      expect(line.codec, 'avc');
      expect(line.lineId, 'gcp_cdn');
      expect(line.lease, isNull, reason: 'a keyed playlist keeps working (REG-SOOP-008)');
      expect(resolution.appliedQualityData, 'original', reason: 'assumed applied, as 3.x did');
      expect(resolution.qualityUnconfirmed, isFalse);
      expect(SoopApi.resolution(playlist: 'https://h/p.m3u8?x=1', aid: 'k', roomId: 'a', quality: 'hd', cdn: '').urls, [
        'https://h/p.m3u8?x=1&aid=k',
      ]);
    });

    test('media headers without a room or a cookie', () {
      expect(SoopApi.mediaHeaders(''), {
        'user-agent': SoopApi.mediaUserAgent,
        'origin': 'https://www.sooplive.co.kr',
        'referer': 'https://www.sooplive.co.kr/',
      });
      expect(SoopApi.mediaHeaders('room 1', cookie: ' ')['referer'], 'https://play.sooplive.co.kr/room%201');
    });

    test("the API headers are 3.x's getHeaders(), without an empty cookie", () {
      final legacy = (_legacy('S02-area-p1')['request'] as Map)['headers'] as Map<String, dynamic>;
      expect(legacy['Cookie'], '');
      expect(SoopApi.apiHeaders(), {
        for (final MapEntry(:key, :value) in legacy.entries)
          if (key != 'Cookie') key.toLowerCase(): value,
      });
      expect(SoopApi.apiHeaders(cookie: 'a=1')['cookie'], 'a=1');
    });
  });
}

/// The recorded danmaku session's meta.json (fixtures/soop/danmaku, for M5).
String _danmakuMeta() => File('../../fixtures/soop/danmaku/S07-live/meta.json').readAsStringSync();
