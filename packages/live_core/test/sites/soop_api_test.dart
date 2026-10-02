// SOOP parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json: 3.x's soop_site.dart run over the same
// samples, docs/E-直播平台/E03-海外平台/E03.1-SOOP/record.md). Every intended difference is listed
// with its reason (the M4.U upgrades by item number, 7-1 … 7-9 in
// docs/specs/UPGRADES.md); everything else must match. Samples recorded for M4.U
// (password, subscribers-only, 1440p) have no 3.x output.
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
/// equal but [changed] and title and name, which are 3.x's with their HTML
/// entities decoded (7-2). The new keys `startedAt` and `restriction` are
/// checked by their own tests (3.x wrote neither).
void _expectRooms(List<LiveRoom> rooms, Object? legacy, {required String reason, Set<String> changed = const {}}) {
  final expected = (legacy! as List).cast<Map<String, dynamic>>();
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(room.toJson(), expected[index], changed: {'title', 'nick', ...changed}, reason: '$reason[$index]');
    expect(room.title, decodeHtmlEntities('${expected[index]['title'] ?? ''}'), reason: '7-2 $reason[$index]');
    expect(room.nick, decodeHtmlEntities('${expected[index]['nick'] ?? ''}'), reason: '7-2 $reason[$index]');
  }
}

/// The list entries of a sample's answer (`data.list`, `broad` or
/// `REAL_BROAD`).
List<Map<String, dynamic>> _entries(String name) {
  final root = jsonDecode(_sample(name).body) as Map<String, dynamic>;
  final list = (root['data'] as Map<String, dynamic>?)?['list'] ?? root['broad'] ?? root['REAL_BROAD'];
  return (list as List).cast<Map<String, dynamic>>();
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

    test('titles and names have their HTML entities decoded (7-2; 3.x showed &amp; and &gt;&lt;)', () {
      final area = SoopApi.areaRooms(_sample('S02-area-p1').body, areaName: '');
      final legacy = (_legacy('S02-area-p1')['rooms'] as List).cast<Map<String, dynamic>>();
      expect(legacy.where((room) => '${room['title']}'.contains('&amp;')), hasLength(2));
      expect(area.where((room) => room.title.contains('&amp;') || room.title.contains('&gt;')), isEmpty);
      expect(area.map((room) => room.title), containsAll(['랜만><', '928개 냠냠 & 역팬1000개, 방셀 핀볼']));
      final main = SoopApi.recommendRooms(_sample('S03-main-p1').body);
      expect(main.where((room) => room.title == '랜만><'), hasLength(1));
      final room = SoopApi.recommendRooms(
        jsonEncode({
          'broad': [
            {'user_id': 'ab12', 'broad_title': 'a &amp; b &#39;c&#39;', 'user_nick': 'x&lt;y&gt;'},
          ],
        }),
      ).single;
      expect((room.title, room.nick), ("a & b 'c'", 'x<y>'));
    });

    test('cards carry the start time: broad_start in Korean time (7-9)', () {
      for (final (name, captured) in [
        ('S02-area-p1', _sample('S02-area-p1').capturedAt),
        ('S03-main-p1', _sample('S03-main-p1').capturedAt),
        ('S04-search-p1', _sample('S04-search-p1').capturedAt),
      ]) {
        final rooms = switch (name) {
          'S02-area-p1' => SoopApi.areaRooms(_sample(name).body, areaName: ''),
          'S03-main-p1' => SoopApi.recommendRooms(_sample(name).body),
          _ => SoopApi.searchRooms(_sample(name).body),
        };
        final entries = _entries(name);
        expect(rooms, hasLength(entries.length));
        for (final (index, room) in rooms.indexed) {
          expect(room.startedAt, isNotNull, reason: '$name ${room.roomId}');
          expect(room.startedAt!.isUtc, isTrue);
          // Read as UTC the latest starts would be after the recording.
          expect(room.startedAt!.isBefore(captured), isTrue, reason: '$name ${room.roomId}');
          expect(
            room.startedAt!.add(const Duration(hours: 9)).toIso8601String().substring(0, 19).replaceFirst('T', ' '),
            '${entries[index]['broad_start']}'.substring(0, 19),
            reason: '$name ${room.roomId}',
          );
        }
      }
      // khm11903 on the air since 19:59:31 KST, as BTIME says (S05).
      final khm = SoopApi.areaRooms(_sample('S02-area-p1').body, areaName: '').first;
      expect((khm.roomId, khm.startedAt), ('khm11903', DateTime.utc(2026, 9, 22, 10, 59, 31)));
      expect(khm.toJson()['startedAt'], '2026-09-22T10:59:31.000Z');
    });

    test('cards carry the restriction; restricted broadcasts stay live cards', () {
      final area = SoopApi.areaRooms(_sample('S02-area-p1').body, areaName: '');
      final entries = _entries('S02-area-p1');
      for (final (index, room) in area.indexed) {
        final adult = entries[index]['grade'] == 19;
        expect(room.restriction, adult ? LiveRestriction.adult : LiveRestriction.none, reason: room.roomId);
        expect(room.isLiveNow, isTrue);
        expect(room.followGroup, FollowGroup.live);
      }
      expect(area.where((room) => room.restriction == LiveRestriction.adult), hasLength(13));
      final main = SoopApi.recommendRooms(_sample('S03-main-p1').body);
      expect(main.where((room) => room.restriction == LiveRestriction.adult), hasLength(2));
      expect(main.where((room) => room.restriction == LiveRestriction.none), hasLength(58));
      // Search: `broad_grade` 19 with `is_password` Y is a password room
      // (the stronger restriction), 19 alone adult.
      final search = SoopApi.searchRooms(_sample('S04-search-p1').body);
      expect(
        {for (final room in search) room.restriction},
        {LiveRestriction.none, LiveRestriction.password, LiveRestriction.adult},
      );
      expect(search.where((room) => room.restriction == LiveRestriction.password), hasLength(1));
      expect(search.where((room) => room.restriction == LiveRestriction.adult), hasLength(1));
      // Subscribers only (`subscription_only` 2, recorded 2026-09-29 in the
      // recommendations; S05-live-subscribers).
      final subscribers = SoopApi.recommendRooms(
        jsonEncode({
          'broad': [
            {'user_id': 'kirababy2', 'is_password': 'N', 'subscription_only': '2', 'broad_grade': '0'},
            {'user_id': 'ab12', 'is_password': 'N', 'subscription_only': '2', 'broad_grade': '19'},
            {'user_id': 'cd34'},
          ],
        }),
      );
      expect(subscribers.map((room) => room.restriction), [
        LiveRestriction.subscribersOnly,
        LiveRestriction.subscribersOnly,
        null,
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

    test("S04 search: the rooms 3.x found, with the area from broad_cate_name (7-3; 3.x's was empty)", () {
      final fixture = _sample('S04-search-p1');
      final rooms = SoopApi.searchRooms(fixture.body, status: fixture.status);
      // area: 3.x read `standard_broad_cate_name`, which the answers no
      // longer carry, and showed none (7-3).
      _expectRooms(rooms, _legacy('S04-search-p1')['rooms'], reason: 'S04', changed: {'area'});
      final legacy = (_legacy('S04-search-p1')['rooms'] as List).cast<Map<String, dynamic>>();
      expect(legacy.every((room) => (room['area'] ?? '') == ''), isTrue);
      expect(rooms.map((room) => room.area), [for (final entry in _entries('S04-search-p1')) entry['broad_cate_name']]);
      expect(rooms.first.area, '종합게임');
      expect(rooms.every((room) => room.area!.isNotEmpty), isTrue);
      // Without broad_cate_name, 3.x's field is still read.
      final old = SoopApi.searchRooms(
        jsonEncode({
          'REAL_BROAD': [
            {'user_id': 'ab12', 'standard_broad_cate_name': 'x &amp; y'},
          ],
        }),
      );
      expect(old.single.area, 'x & y');
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
      // New keys (3.x wrote neither): BTIME 455474 s before the recording
      // is the station's and the lists' broad_start, 19:59:31 KST; BPWD N,
      // P_MIN_TIER 0 and GRADE 0 say no restriction.
      expect(fixture.capturedAt.difference(_now).inSeconds, 0);
      expect(room.startedAt, DateTime.utc(2026, 9, 22, 10, 59, 31));
      expect(room.restriction, LiveRestriction.none);
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
      test('$name: RESULT 0 is offline at every depth (7-4; 3.x: a failed load at room entry)', () {
        final fixture = _sample(name);
        final legacy = _legacy(name);
        final room = SoopApi.roomDetail(fixture.body, requestedId: id, now: _now, withDanmaku: true);
        _expectParity(room.toJson(), legacy['getRoomDetailForRefresh'] as Map<String, dynamic>, reason: name);
        _expectParity(room.toJson(), legacy['getRoomDetailForRecording'] as Map<String, dynamic>, reason: name);
        expect(room.effectiveLiveStatus, LiveStatus.offline, reason: 'the player API cannot tell an unknown id');
        expect(room.data, isNull);
        expect(room.startedAt, isNull);
        expect(room.restriction, isNull, reason: 'no broadcast to judge');
        // 3.x's room entry lumped RESULT 0 with failures: an error room,
        // state unknown, "获取房间信息失败". Now offline there too (7-4);
        // the station tells an unknown streamer apart (7-5).
        _expectParity(
          room.toJson(),
          legacy['getRoomDetail'] as Map<String, dynamic>,
          changed: {'liveStatus', 'watching'},
          reason: '7-4 $name',
        );
        expect((legacy['getRoomDetail'] as Map)['liveStatus'], LiveStatus.unknown.index);
        expect(room.toJson()['liveStatus'], LiveStatus.offline.index);
        expect(legacy['getPlayQualites'], isEmpty);
      });
    }

    test('S05 adult: RESULT -6 is a live, age-restricted room (7-5; 3.x: unknown state, StateError)', () {
      final fixture = _sample('S05-live-adult');
      final legacy = _legacy('S05-live-adult');
      final room = SoopApi.roomDetail(fixture.body, requestedId: 'bumzi98', now: fixture.capturedAt);
      expect(room.isLiveNow, isTrue);
      expect(room.followGroup, FollowGroup.live);
      expect(room.restriction, LiveRestriction.adult);
      expect(room.isRestricted, isTrue);
      expect(room.title, '다시보기 X 추석 토끼 떡 찧다가 술마시는중');
      // BTIME 14665 before the recording: 22:26:31 KST, the station's
      // broad_start (S05-station-adult).
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 13, 26, 31));
      expect(room.data, isNull, reason: 'no stream without an adult-verified login');
      expect(room.nick, '', reason: 'the answer names no streamer; the station does at room entry');
      expect(SoopApi.noStream(room), isA<NeedsLogin>());
      expect((legacy['getRoomDetail'] as Map)['liveStatus'], LiveStatus.unknown.index);
      expect(((legacy['getRoomDetailForRefresh'] as Map)['throws'] as Map)['type'], 'StateError');
      expect(((legacy['getRoomDetailForRecording'] as Map)['throws'] as Map)['type'], 'StateError');
    });

    test('S05 adult with a password: RESULT -8 is live and password-protected (7-8)', () {
      final fixture = _sample('S05-live-adult-password');
      final room = SoopApi.roomDetail(fixture.body, requestedId: 'qazeee', now: fixture.capturedAt);
      expect(room.isLiveNow, isTrue);
      expect(room.restriction, LiveRestriction.password, reason: 'a login alone does not open it');
      expect(room.title, '회복중..');
      expect(
        room.startedAt,
        fixture.capturedAt.subtract(const Duration(seconds: 13497)).copyWith(microsecond: 0, millisecond: 0),
      );
      expect(
        SoopApi.noStream(room),
        isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('password')),
      );
    });

    test('S05 subscribers only: RESULT -14 is live for subscribers only, without title or time', () {
      final fixture = _sample('S05-live-subscribers');
      final room = SoopApi.roomDetail(fixture.body, requestedId: 'kirababy2', now: _now, withDanmaku: true);
      expect(room.isLiveNow, isTrue);
      expect(room.restriction, LiveRestriction.subscribersOnly);
      expect((room.title, room.startedAt, room.danmakuData), ('', null, null));
      expect(
        SoopApi.noStream(room),
        isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('subscribers')),
      );
    });

    test('S05 password: RESULT 1 with BPWD Y is live, password-protected, with its broadcast (7-8)', () {
      final fixture = _sample('S05-live-password');
      final room = SoopApi.roomDetail(fixture.body, requestedId: 'nsh100427', now: fixture.capturedAt);
      expect(room.isLiveNow, isTrue);
      expect(room.restriction, LiveRestriction.password);
      expect((room.data! as SoopRoomData).password, isTrue);
      expect(room.title, '다잉라이트');
      expect(room.nick, '아스모.');
      expect(
        room.startedAt,
        fixture.capturedAt.subtract(const Duration(seconds: 9694)).copyWith(microsecond: 0, millisecond: 0),
      );
    });

    test('RESULT 1 restrictions: a password before subscribers only before adult; none when all are clear', () {
      Map<String, Object?> live(Map<String, Object?> flags) => {
        'RESULT': 1,
        'BNO': '1',
        'VIEWPRESET': [
          {'name': 'original'},
        ],
        ...flags,
      };
      LiveRestriction? restriction(Map<String, Object?> flags) =>
          SoopApi.roomDetail(_channel(live(flags)), requestedId: 'ab12', now: _now).restriction;
      expect(restriction({'BPWD': 'N', 'P_MIN_TIER': '0', 'GRADE': '0'}), LiveRestriction.none);
      expect(restriction({'BPWD': 'Y', 'P_MIN_TIER': '2', 'GRADE': '19'}), LiveRestriction.password);
      expect(restriction({'BPWD': 'N', 'P_MIN_TIER': '2', 'GRADE': '19'}), LiveRestriction.subscribersOnly);
      expect(restriction({'BPWD': 'N', 'P_MIN_TIER': '0', 'GRADE': '19'}), LiveRestriction.adult);
      expect(restriction({}), isNull, reason: 'no flag, no judgement');
    });

    test('RESULT -2 is banned at every depth (7-4); no VIEWPRESET is offline', () {
      final banned = SoopApi.roomDetail(_channel({'RESULT': -2}), requestedId: 'ab12', now: _now, withDanmaku: true);
      expect(banned.effectiveLiveStatus, LiveStatus.banned);
      expect(banned.restriction, isNull);
      expect(SoopApi.noStream(banned), isA<StreamUnavailable>());
      // 3.x's rule at every depth: RESULT 1 without presets is an offline
      // room.
      final idle = SoopApi.roomDetail(
        _channel({'RESULT': 1, 'BJID': 'ab12', 'BNO': '9', 'TITLE': 'x', 'BTIME': 60, 'BPWD': 'N'}),
        requestedId: 'ab12',
        now: _now,
        withDanmaku: true,
      );
      expect(idle.effectiveLiveStatus, LiveStatus.offline);
      expect(idle.data, isNull, reason: 'no broadcast to stream');
      expect((idle.startedAt, idle.restriction), (null, null), reason: 'not live');
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

  group('station (7-5)', () {
    SoopStation station(String name) {
      final fixture = _sample(name);
      return SoopApi.station(fixture.body, status: fixture.status);
    }

    test('S05 station: the profile, and the broadcast while one is on', () {
      final live = station('S05-station-live');
      expect(live.nick, '봉준');
      expect(live.avatar, 'https://profile.img.sooplive.co.kr/LOGO/kh/khm11903/khm11903.jpg');
      expect(live.introduction, '스타1 전프로게이머 김봉준 입니다.');
      final broadcast = live.broadcast!;
      expect(broadcast.bno, '297314125');
      expect(broadcast.title, '봉준');
      expect(broadcast.viewers, '35465');
      expect(broadcast.startedAt, DateTime.utc(2026, 9, 22, 10, 59, 31), reason: 'broad_start 19:59:31 KST');
      expect(broadcast.restriction, LiveRestriction.none);
      final offline = station('S05-station-offline');
      expect((offline.nick, offline.broadcast), ('김민교.', null));
      expect(offline.introduction, '실력과 재미와 감동을 겸비한 방송');
      final adult = station('S05-station-adult');
      expect(adult.broadcast!.restriction, LiveRestriction.adult);
      expect(adult.broadcast!.viewers, '3209');
      expect(adult.introduction, '', reason: 'an empty station_title');
      expect(station('S05-station-subscribers').broadcast!.restriction, LiveRestriction.subscribersOnly);
    });

    test('an unknown streamer is NotFound (HTTP 515, code 9000); other failures as every answer', () {
      final missing = _sample('S05-station-missing');
      expect(missing.status, 515);
      expect(() => SoopApi.station(missing.body, status: missing.status), throwsA(isA<NotFound>()));
      expect(() => SoopApi.station('bad gateway', status: 502), throwsA(isA<NetworkFailure>()));
      expect(() => SoopApi.station('{"x":1}'), throwsA(isA<ApiChanged>()));
    });

    test("live: the station adds the profile picture, tagline and viewers; the player API's answer stays", () {
      final fixture = _sample('S05-live-live');
      final room = SoopApi.roomDetail(fixture.body, requestedId: 'khm11903', now: _now, withDanmaku: true);
      final entry = SoopApi.withStation(room, station('S05-station-live'), now: _now);
      expect(entry.avatar, 'https://profile.img.sooplive.co.kr/LOGO/kh/khm11903/khm11903.jpg');
      expect(entry.introduction, '스타1 전프로게이머 김봉준 입니다.');
      expect((entry.onlineViewers, entry.watching), ('35465', '35465'));
      expect(entry.effectiveAudienceMetricType, AudienceMetricType.onlineViewers);
      for (final (label, value, expected) in [
        ('title', entry.title, room.title),
        ('nick', entry.nick, room.nick),
        ('cover', entry.cover, room.cover),
        ('area', entry.area, room.area),
      ]) {
        expect(value, expected, reason: label);
      }
      expect(entry.startedAt, room.startedAt);
      expect(entry.restriction, LiveRestriction.none);
      expect(entry.data, same(room.data));
      expect(entry.danmakuData, same(room.danmakuData));
      // 3.x's room: no introduction, no audience, the built avatar.
      _expectParity(
        entry.toJson(),
        _legacy('S05-live-live')['getRoomDetail'] as Map<String, dynamic>,
        changed: {'userId', 'cover', 'data', 'danmakuData', 'avatar', 'introduction', 'watching', 'onlineViewers'},
        reason: '7-5',
      );
    });

    test('a live answer keeps its figures when the station names another broadcast', () {
      final fixture = _sample('S05-live-live');
      final room = SoopApi.roomDetail(fixture.body, requestedId: 'khm11903', now: _now);
      const other = SoopStation(
        nick: 'x',
        avatar: 'https://a/b.jpg',
        broadcast: SoopStationBroadcast(bno: '1', viewers: '5', restriction: LiveRestriction.password),
      );
      final entry = SoopApi.withStation(room, other, now: _now);
      expect((entry.avatar, entry.onlineViewers, entry.restriction), ('https://a/b.jpg', '', LiveRestriction.none));
      expect(entry.nick, '봉준', reason: "the answer's name stays");
    });

    test('offline (7-4): the profile only; the unknown streamer is told apart by the station', () {
      final fixture = _sample('S05-live-offline');
      final room = SoopApi.roomDetail(fixture.body, requestedId: 'phonics1', now: _now, withDanmaku: true);
      final entry = SoopApi.withStation(room, station('S05-station-offline'), now: _now);
      expect(entry.effectiveLiveStatus, LiveStatus.offline);
      expect(entry.nick, '김민교.');
      expect(entry.avatar, 'https://profile.img.sooplive.co.kr/LOGO/ph/phonics1/phonics1.jpg');
      expect(entry.introduction, '실력과 재미와 감동을 겸비한 방송');
      expect((entry.title, entry.cover, entry.startedAt, entry.restriction), ('', '', null, null));
      expect(entry.followGroup, FollowGroup.offline);
    });

    test('age-restricted (7-5): live with the station name, picture, viewers, cover and start time', () {
      final fixture = _sample('S05-live-adult');
      final room = SoopApi.roomDetail(fixture.body, requestedId: 'bumzi98', now: fixture.capturedAt);
      final entry = SoopApi.withStation(room, station('S05-station-adult'), now: _now);
      expect(entry.isLiveNow, isTrue);
      expect(entry.restriction, LiveRestriction.adult);
      expect(entry.nick, '하니니');
      expect(entry.title, '다시보기 X 추석 토끼 떡 찧다가 술마시는중');
      expect(entry.avatar, 'https://profile.img.sooplive.co.kr/LOGO/bu/bumzi98/bumzi98.jpg');
      expect(entry.onlineViewers, '3209');
      expect(entry.cover, 'https://liveimg.sooplive.co.kr/m/297428401?_t=${_now.millisecondsSinceEpoch}');
      expect(entry.startedAt, DateTime.utc(2026, 9, 27, 13, 26, 31), reason: "BTIME's, the same as broad_start");
      expect(entry.data, isNull);
      expect(SoopApi.noStream(entry), isA<NeedsLogin>());
    });

    test('subscribers only: the station supplies title, cover and start time the answer lacks', () {
      final fixture = _sample('S05-live-subscribers');
      final room = SoopApi.roomDetail(fixture.body, requestedId: 'kirababy2', now: _now);
      final entry = SoopApi.withStation(room, station('S05-station-subscribers'), now: _now);
      expect(entry.isLiveNow, isTrue);
      expect(entry.restriction, LiveRestriction.subscribersOnly);
      expect(entry.title, '햇비랑 프클하려고 왔음');
      expect(entry.nick, '유키라');
      expect(entry.onlineViewers, '41');
      expect(entry.cover, 'https://liveimg.sooplive.co.kr/m/297445461?_t=${_now.millisecondsSinceEpoch}');
      expect(entry.startedAt, DateTime.utc(2026, 9, 28, 10, 51, 15), reason: 'broad_start 19:51:15 KST');
    });

    test('offline in the player API but on air at the station: live, and unplayable unless restricted', () {
      final room = SoopApi.roomDetail(_channel({'RESULT': 0}), requestedId: 'ab12', now: _now);
      const onAir = SoopStation(
        nick: 'n',
        broadcast: SoopStationBroadcast(bno: '7', title: 't', viewers: '3'),
      );
      final entry = SoopApi.withStation(room, onAir, now: _now);
      expect(entry.isLiveNow, isTrue);
      expect(entry.restriction, LiveRestriction.unplayable);
      expect((entry.title, entry.onlineViewers), ('t', '3'));
      expect(SoopApi.noStream(entry), isA<StreamUnavailable>());
      const locked = SoopStation(
        broadcast: SoopStationBroadcast(bno: '7', restriction: LiveRestriction.password),
      );
      expect(SoopApi.withStation(room, locked, now: _now).restriction, LiveRestriction.password);
      final banned = SoopApi.roomDetail(_channel({'RESULT': -2}), requestedId: 'ab12', now: _now);
      final blocked = SoopApi.withStation(banned, onAir, now: _now);
      expect((blocked.effectiveLiveStatus, blocked.nick), (LiveStatus.banned, 'n'), reason: 'banned stays banned');
    });
  });

  group('restriction and time helpers', () {
    test('restrictionOf reads every spelling the answers use', () {
      expect(SoopApi.restrictionOf(), isNull);
      expect(SoopApi.restrictionOf(password: 'N', subscribers: '0', grade: '0'), LiveRestriction.none);
      for (final yes in [true, 1, '1', 'Y', 'y', 'true']) {
        expect(SoopApi.restrictionOf(password: yes), LiveRestriction.password, reason: '$yes');
      }
      for (final no in [false, 0, '0', 'N', '']) {
        expect(SoopApi.restrictionOf(password: no), LiveRestriction.none, reason: '$no');
      }
      expect(SoopApi.restrictionOf(subscribers: 2), LiveRestriction.subscribersOnly);
      expect(SoopApi.restrictionOf(grade: 19), LiveRestriction.adult);
      expect(SoopApi.restrictionOf(grade: '19', subscribers: '1'), LiveRestriction.subscribersOnly);
    });

    test('stricter keeps the stronger restriction', () {
      expect(SoopApi.stricter(null, null), isNull);
      expect(SoopApi.stricter(LiveRestriction.none, null), LiveRestriction.none);
      expect(SoopApi.stricter(LiveRestriction.adult, LiveRestriction.subscribersOnly), LiveRestriction.subscribersOnly);
      expect(SoopApi.stricter(LiveRestriction.password, LiveRestriction.adult), LiveRestriction.password);
      expect(SoopApi.stricter(LiveRestriction.none, LiveRestriction.adult), LiveRestriction.adult);
    });

    test('koreanTime: KST to UTC; malformed or impossible times are null', () {
      expect(SoopApi.koreanTime('2026-09-22 19:59:31'), DateTime.utc(2026, 9, 22, 10, 59, 31));
      expect(SoopApi.koreanTime('2026-09-22 19:59:31.0'), DateTime.utc(2026, 9, 22, 10, 59, 31));
      expect(SoopApi.koreanTime('2026-09-23 03:00:00'), DateTime.utc(2026, 9, 22, 18));
      for (final bad in [null, '', '0000-00-00 00:00:00', '2026-13-01 00:00:00', '2026-09-22', 'x', 1700000000]) {
        expect(SoopApi.koreanTime(bad), isNull, reason: '$bad');
      }
    });

    test('startedBefore: whole seconds before now; missing, zero or negative is null', () {
      final now = DateTime.utc(2026, 9, 27, 17, 30, 45, 900);
      expect(SoopApi.startedBefore(455474, now), DateTime.utc(2026, 9, 22, 10, 59, 31));
      expect(SoopApi.startedBefore('60', now), DateTime.utc(2026, 9, 27, 17, 29, 45));
      for (final bad in [null, 0, -5, '', 'x']) {
        expect(SoopApi.startedBefore(bad, now), isNull, reason: '$bad');
      }
    });
  });

  group('qualities', () {
    test("S05: 3.x's qualities, but 720p (hd4k) is “超清” after the source and before 540p (7-1)", () {
      final fixture = _sample('S05-live-live');
      final data = SoopApi.roomDetail(fixture.body, requestedId: 'khm11903', now: _now).data! as SoopRoomData;
      final qualities = SoopApi.qualities(data.presets);
      final legacy = (_legacy('S05-live-live')['getPlayQualites'] as List).cast<Map<String, dynamic>>();
      // 3.x: hd4k had no tier, so it sorted by bitrate alone after 360p,
      // under its request name.
      expect(legacy.map((quality) => quality['quality']), ['原画', '高清', '标清', 'hd4k']);
      expect(legacy.last['sort'], 4000);
      Map<String, Object?> json(LivePlayQuality quality) => {
        'quality': quality.quality,
        'id': quality.id,
        'data': quality.data,
        'sort': quality.sort,
      };
      // The other three are 3.x's, name, id and order value alike; hd4k
      // changed its name and order value (7-1), not its id.
      expect([
        for (final quality in qualities)
          if (quality.id != 'hd4k') json(quality),
      ], legacy.sublist(0, 3));
      final hd4k = qualities.singleWhere((quality) => quality.id == 'hd4k');
      expect((hd4k.quality, hd4k.sort, hd4k.data), ('超清', 350004000, const <String>[]));
      expect(qualities.map((quality) => quality.quality), ['原画', '超清', '高清', '标清']);
      expect(qualities.map((quality) => quality.id), ['original', 'hd4k', 'hd', 'sd']);
      expect(data.presets.firstWhere((preset) => preset.name == 'hd4k').bps, 4000);
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

    test("tiers: original > master > fullhd > hd4k > hd > sd > low > other names by bitrate (3.x's, 7-1)", () {
      final names = ['low', 'x2', 'sd', 'hd', 'hd4k', 'fullhd', 'master', 'original', 'x1'];
      final qualities = SoopApi.qualities([
        for (final name in names) SoopPreset(name: name, bps: name == 'x1' ? 90000 : 10),
      ]);
      expect(qualities.map((quality) => quality.id), [
        'original',
        'master',
        'fullhd',
        'hd4k',
        'hd',
        'sd',
        'low',
        'x1',
        'x2',
      ]);
      expect(SoopApi.qualitySort('original', 0), 600000000);
      expect(SoopApi.qualitySort('hd4k', 4000), 350004000);
      expect(SoopApi.qualitySort('HD4K', 0), 350000000, reason: 'case ignored');
      expect(SoopApi.qualitySort('hd', 99999999), lessThan(SoopApi.qualitySort('hd4k', 0)), reason: 'tiers never mix');
      expect(SoopApi.qualitySort('x', 4000), 4000);
      expect(SoopApi.qualityName(const SoopPreset(name: 'HD4K')), '超清');
      expect(SoopApi.qualityName(const SoopPreset(name: 'hd8k')), '蓝光');
      expect(SoopApi.qualityName(const SoopPreset(name: 'original')), '原画');
      expect(SoopApi.qualitySort('hd8k', 8000), 400008000);
    });

    test('a 1440p source: its 1080p transcode hd8k is “蓝光” right after it (7-1; 3.x: “hd8k”, last)', () {
      final fixture = _sample('S05-live-1440p');
      final room = SoopApi.roomDetail(fixture.body, requestedId: 'rrvv17', now: fixture.capturedAt);
      final data = room.data! as SoopRoomData;
      expect(
        [for (final preset in data.presets) '${preset.name}:${preset.bps}'],
        ['sd:500', 'hd:1000', 'hd4k:4000', 'hd8k:8000', 'original:16000', 'auto:16000'],
      );
      final qualities = SoopApi.qualities(data.presets);
      expect(qualities.map((quality) => quality.id), ['original', 'hd8k', 'hd4k', 'hd', 'sd']);
      expect(qualities.map((quality) => quality.quality), ['原画', '蓝光', '超清', '高清', '标清']);
      expect(
        room.startedAt,
        fixture.capturedAt.subtract(const Duration(seconds: 18545)).copyWith(millisecond: 0, microsecond: 0),
      );
      expect(room.restriction, LiveRestriction.none);
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
      // From CHIP the host is on sooplive.com, where every CHDOMAIN is
      // (7-6; 3.x's case expected `.sooplive.co.kr`).
      final ip = SoopApi.danmakuArgs({'CHIP': '222.233.54.76', 'CHPT': 9000, 'CHATNO': '1'}, roomId: 'room id')!;
      expect(ip.url.toString(), 'wss://chat-dee9364c.sooplive.com:9001/Websocket/room%20id');
      expect(ip.plainUrl.toString(), 'ws://chat-dee9364c.sooplive.com:9000/Websocket/room%20id');
      expect(SoopApi.danmakuArgs({'CHDOMAIN': 'chat.example', 'CHPT': 65535, 'CHATNO': '1'}, roomId: 'room'), isNull);
      expect(SoopApi.danmakuArgs({'CHIP': '999.1.1.1', 'CHPT': 9000, 'CHATNO': '1'}, roomId: 'room'), isNull);
      expect(SoopApi.danmakuArgs({'CHDOMAIN': 'chat.example', 'CHPT': 9000}, roomId: 'room'), isNull);
      expect(SoopApi.danmakuArgs({'CHDOMAIN': 'chat.example', 'CHPT': 9000, 'CHATNO': '1'}, roomId: ' '), isNull);
    });

    test('the host built from CHIP is the one the API names in CHDOMAIN (7-6)', () {
      for (final name in ['S05-live-live', 'S05-live-password']) {
        final channel = SoopApi.channel(_sample(name).body).channel;
        final named = SoopApi.danmakuArgs(channel, roomId: 'a')!;
        final built = SoopApi.danmakuArgs({...channel}..remove('CHDOMAIN'), roomId: 'a')!;
        expect(built.url, named.url, reason: name);
        expect(built.plainUrl, named.plainUrl, reason: name);
      }
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

  group('app links (7-9)', () {
    test('the app link list entries carry (S02 `scheme`) names the streamer', () {
      final entry = _entries('S02-area-p1').first;
      expect(entry['scheme'], 'sooplive://player/live?broad_no=297314125&user_id=khm11903&channel=');
      expect(SoopApi.appLinkRoomId('${entry['scheme']}'), 'khm11903');
      expect(
        SoopApi.appLink('khm11903', bno: '297314125'),
        'sooplive://player/live?broad_no=297314125&user_id=khm11903',
      );
      expect(SoopApi.appLink(' khm11903 '), 'sooplive://player/live?user_id=khm11903');
      expect(SoopApi.appLinkRoomId(SoopApi.appLink('khm11903')), 'khm11903');
    });

    test('other schemes, pages and ids are not app links', () {
      expect(SoopApi.appLinkRoomId('SOOPLIVE://PLAYER/LIVE?user_id=KHM11903'), 'khm11903');
      for (final link in [
        'sooplive://player/vod?user_id=khm11903',
        'sooplive://station?user_id=khm11903',
        'sooplive://player/live?broad_no=1',
        'sooplive://player/live?user_id=a/b',
        'https://play.sooplive.co.kr/player/live?user_id=khm11903',
        'afreeca://player/live?user_id=khm11903',
        '',
      ]) {
        expect(SoopApi.appLinkRoomId(link), isNull, reason: link);
      }
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

    test('S06 password: the key is refused without the password (RESULT 0), named as such (7-8)', () {
      final fixture = _sample('S06-aid-password');
      expect(SoopApi.channel(fixture.body).result, 0);
      expect(
        () => SoopApi.aid(fixture.body, status: fixture.status, password: true),
        throwsA(
          isA<StreamUnavailable>().having((error) => error.detail, 'detail', 'aid: RESULT 0, password-protected'),
        ),
      );
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
