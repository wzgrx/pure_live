// NetEase CC parsing against the recorded samples, compared field by field
// with 3.x's frozen output (expected.json, written by
// fixtures/cc/legacy_expected.dart from 3.x's parsers). Every intended
// difference is listed with its reason (a docs/T02/T02b/T02b.2/record.md
// difference, or an approved upgrade of docs/specs/UPGRADES.md: 9-1 to 9-7);
// everything else must match.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('cc', name);

/// Keys 3.x never wrote (M2.1); [_expectParity] checks them apart.
const _v4Keys = ['startedAt', 'restriction'];

/// Asserts that [actual] (a `toJson`) equals 3.x's [legacy] map on every key
/// 3.x wrote, except [changed] (intended differences), and that the v4 keys
/// are exactly [added]. 3.x wrote null where the immutable model writes ''.
void _expectParity(
  Map<String, Object?> actual,
  Map<String, dynamic> legacy, {
  Set<String> changed = const {},
  Map<String, Object?> added = const {},
  String? reason,
}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (changed.contains(key)) continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
  for (final key in _v4Keys) {
    expect(actual[key], added[key], reason: '${reason ?? ''} $key (v4 key)');
  }
}

/// 3.x's room projection: toJson plus `link`.
Map<String, Object?> _projection(LiveRoom room) => {...room.toJson(), 'link': room.link};

List<Map<String, dynamic>> _rooms(Object? legacy) =>
    ((legacy! as Map<String, dynamic>)['rooms'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _json(String body) => jsonDecode(body) as Map<String, dynamic>;

List<Map<String, dynamic>> _rows(String body, String key) => (_json(body)[key] as List).cast<Map<String, dynamic>>();

/// 9-3: 3.x showed a "【重播】" rebroadcast live; its state keys changed.
const _rebroadcastKeys = {'liveStatus', 'status', 'isRecord'};

bool _isRebroadcast(Map<String, dynamic> row) => '${row['title']}'.startsWith('【重播】');

/// The v4 keys of a room on air (unified principles "开播时间", "受限"): its
/// `startat` in Beijing time, and no restriction since it carries a tier
/// list.
Map<String, Object?> _onAirKeys(Map<String, dynamic> row) => {
  'startedAt': DateTime.parse('${(row['startat'] as String).replaceFirst(' ', 'T')}+08:00').toUtc().toIso8601String(),
  'restriction': 'none',
};

/// The Dashen configuration sample with [edit] applied to its live entries.
String _config(void Function(Map<String, dynamic> root, List<Object?> entries) edit) {
  final root = _json(_sample('S01-dashen-config').body);
  final result = root['result'] as Map<String, dynamic>;
  final group = (result['itemList'] as List).cast<Map<String, dynamic>>().firstWhere(
    (item) => item['name'] == '直播入口列表',
  );
  edit(result, group['itemList'] as List<Object?>);
  return jsonEncode(root);
}

/// The mobile catalog from the recorded samples, as `CcSite` builds it.
List<LiveCategory> _mobileCatalog() {
  final samples = {'1': 'S01-cate-online', '2': 'S01-cate-mobile', '4': 'S01-cate-esports', '5': 'S01-cate-show'};
  return [
    for (final (:id, :name) in CcApi.categoryTypes(_sample('S01-cate-all').body))
      LiveCategory(
        id: id,
        name: name,
        children: CcApi.categoryAreas(_sample(samples[id]!).body, id: id, name: name),
      ),
  ];
}

void main() {
  group('S01 catalog (9-4)', () {
    final games = _sample('S01-dashen-games');
    final config = _sample('S01-dashen-config');

    test('the mobile catalog: 4 categories, 106 areas, in the server order', () {
      expect(CcApi.categoryTypes(_sample('S01-cate-all').body), [
        (id: '1', name: '网游'),
        (id: '2', name: '手游'),
        (id: '4', name: '竞技'),
        (id: '5', name: '综艺'),
      ], reason: '全部 (0) is not a category');
      final catalog = _mobileCatalog();
      expect(catalog.map((category) => category.children.length), [33, 63, 8, 2]);
      final areas = catalog.expand((category) => category.children).toList();
      expect(areas.map((area) => area.areaId).toSet(), hasLength(106));
      final data = _json(_sample('S01-cate-all').body)['data'] as Map<String, dynamic>;
      final all = _rows(jsonEncode(data['category_info']), 'game_list');
      expect(areas.map((area) => area.areaId).toSet(), all.map((row) => row['gametype']).toSet());
      final first = catalog[1].children.first;
      expect(first.toJson(), {
        'platform': 'cc',
        'areaType': '2',
        'typeName': '手游',
        'areaId': '9141',
        'areaName': '蛋仔派对',
        'areaPic': 'http://cotton.res.netease.com/buckets/4NhQWd/files/SsQAfB8',
        'shortName': '',
      });
      expect(areas.every(CcApi.isListableArea), isTrue);
      expect(areas.firstWhere((area) => area.areaId == '0').areaName, '其他游戏', reason: 'game type 0 lists too');
    });

    test("3.x's areas stay reachable; its official entries are kept as they were", () {
      final legacy = (config.legacy as List).cast<Map<String, dynamic>>();
      expect(legacy.map((category) => category['id']), ['1', 'official']);
      // 9-4: 3.x's "直播分类" (20 Dashen areas) is replaced by the mobile
      // catalog. Followed areas are identified by their game type, which
      // lists whatever the catalog; all but 9050 (明日之后, not in the
      // mobile catalog) are also in it.
      final mobile = {for (final category in _mobileCatalog()) ...category.children.map((area) => area.areaId)};
      final old = (legacy.first['children'] as List).cast<Map<String, dynamic>>();
      expect(old, hasLength(20));
      expect([for (final area in old) area['areaId'] as String].where((id) => !mobile.contains(id)), ['9050']);
      expect(old.every((area) => CcApi.isListableArea(LiveArea.fromJson(area))), isTrue);
      // The official category matches 3.x.
      final official = CcApi.officialAreas(games.body, config.body, gamesStatus: games.status);
      final areas = (legacy.last['children'] as List).cast<Map<String, dynamic>>();
      expect(official, hasLength(areas.length));
      for (final (index, area) in official.indexed) {
        expect(area.toJson(), {...areas[index], 'shortName': ''}, reason: 'official[$index]');
      }
      expect(official.first.areaId, 'official:249133');
    });

    test('official entries open the website, rebuilt from their id', () {
      final official = CcApi.officialAreas(games.body, config.body).first;
      expect(CcApi.isOfficialEntry(official), isTrue);
      expect(
        CcApi.officialEntryUri(LiveArea.fromJson(official.toJson())).toString(),
        'https://cc.163.com/249133/?open=blizzardtv&from=8382&platform=ds',
      );
      for (final id in ['official:../file', 'official:0', 'official:https://example.test']) {
        expect(
          CcApi.officialEntryUri(LiveArea(platform: 'cc', areaId: id)),
          isNull,
          reason: id,
        );
      }
      expect(CcApi.officialEntryUri(const LiveArea(platform: 'huya', areaId: 'official:249133')), isNull);
      expect(CcApi.officialEntryUri(const LiveArea(platform: 'cc', areaId: '3')), isNull);
      expect(CcApi.isListableArea(official), isFalse);
      expect(CcApi.isListableArea(const LiveArea(platform: 'cc', areaId: '3', areaType: '2')), isTrue);
      expect(CcApi.isListableArea(const LiveArea(areaId: '3')), isTrue, reason: 'old records without a platform');
      for (final id in ['', '00', '-1', '3?x=y', '../3']) {
        expect(
          CcApi.isListableArea(LiveArea(platform: 'cc', areaId: id)),
          isFalse,
          reason: id,
        );
      }
    });

    test('hidden entries are left out; a hidden or empty configuration lists none', () {
      final hidden = _config((_, entries) => (entries.first! as Map<String, dynamic>)['hidden'] = true);
      expect(CcApi.officialAreas(games.body, hidden), hasLength(3));
      final odd = _config((_, entries) => (entries.first! as Map<String, dynamic>)['hidden'] = 'yes');
      expect(CcApi.officialAreas(games.body, odd), hasLength(3), reason: 'a hidden that is not a bool hides');
      expect(CcApi.officialAreas(games.body, _config((_, entries) => entries.clear())), isEmpty);
      expect(CcApi.officialAreas(games.body, _config((root, _) => root['hidden'] = true)), isEmpty);
    });

    test('a bad official entry is skipped, not the rest (容错)', () {
      final broken = {
        'foreign host': _config(
          (_, entries) => (entries.first! as Map<String, dynamic>)['content'] = 'https://example.test/249133/',
        ),
        'plain http': _config(
          (_, entries) => (entries.first! as Map<String, dynamic>)['content'] = 'http://cc.163.com/249133/',
        ),
        'unknown route': _config(
          (_, entries) => (entries.first! as Map<String, dynamic>)['content'] = 'https://cc.163.com/unrecognized/',
        ),
        'no game': _config((_, entries) => (entries.first! as Map<String, dynamic>)['name'] = 'missing-game'),
        'not an object': _config((_, entries) => entries[0] = 'd90'),
      };
      for (final MapEntry(key: reason, value: body) in broken.entries) {
        final official = CcApi.officialAreas(games.body, body);
        expect(official.map((area) => area.areaId), [
          'official:341427600',
          'official:341436398',
          'official:586568',
        ], reason: reason);
      }
      expect(CcApi.officialAreas(games.body, _config((_, entries) => entries.add(entries.first))), hasLength(4));
    });

    test('an unreadable answer is an error (the adapter then leaves the official entries out)', () {
      for (final body in [
        _config((root, _) => root['itemList'] = const <Object?>[]),
        _config((root, _) => root['id'] = 'x'),
        '<html>migration</html>',
      ]) {
        expect(() => CcApi.officialAreas(games.body, body), throwsA(isA<ApiChanged>()));
      }
      expect(() => CcApi.officialAreas('{"code":500}', config.body), throwsA(isA<ApiChanged>()));
      expect(() => CcApi.officialAreas(games.body, config.body, configStatus: 503), throwsA(isA<NetworkFailure>()));
    });

    test('mobile catalog: bad rows are skipped, a bad answer is an error', () {
      final types = CcApi.categoryTypes(
        jsonEncode({
          'code': 0,
          'data': {
            'category_info': {
              'cate_list': [
                {'cate_type': 0, 'name': '全部'},
                {'cate_type': 1, 'name': 'A &amp; B'},
                {'cate_type': 1, 'name': 'again'},
                {'cate_type': 'x', 'name': 'bad'},
                {'cate_type': 3},
                null,
              ],
            },
          },
        }),
      );
      expect(types, [(id: '1', name: 'A & B')]);
      final areas = CcApi.categoryAreas(
        jsonEncode({
          'code': 0,
          'data': {
            'category_info': {
              'game_list': [
                {'gametype': 7, 'name': 'Game &amp; More', 'cover': '//x.test/a.png'},
                {'gametype': '7', 'name': 'again'},
                {'gametype': 'abc', 'name': 'bad'},
                {'gametype': '08', 'name': 'bad'},
                {'gametype': '9', 'name': ' '},
                {'name': 'no type'},
                'row',
              ],
            },
          },
        }),
        id: '1',
        name: 'A',
      );
      expect(areas.map((area) => (area.areaId, area.areaName, area.areaPic)), [
        ('7', 'Game & More', 'https://x.test/a.png'),
      ]);
      expect(CcApi.categoryAreas('{"code":0,"data":{"category_info":{}}}', id: '1', name: 'A'), isEmpty);
      for (final body in ['<html>', '{"code":1}', '{"code":0,"data":{}}']) {
        expect(() => CcApi.categoryTypes(body), throwsA(isA<ApiChanged>()), reason: body);
      }
      expect(() => CcApi.categoryAreas('', id: '1', name: 'A', status: 503), throwsA(isA<NetworkFailure>()));
    });
  });

  group('S02 area rooms', () {
    for (final (name, gametype) in [
      ('S02-area-page1', '9141'),
      ('S02-area-beyond', '9141'),
      ('S02-area-empty', '65005'),
    ]) {
      test('$name matches 3.x', () {
        final fixture = _sample(name);
        final rooms = CcApi.categoryRooms(fixture.body, gametype: gametype, status: fixture.status);
        final legacy = _rooms(fixture.legacy);
        final rows = _rows(fixture.body, 'lives');
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        for (final (index, room) in rooms.indexed) {
          _expectParity(
            _projection(room),
            legacy[index],
            changed: {if (_isRebroadcast(rows[index])) ..._rebroadcastKeys},
            added: _onAirKeys(rows[index]),
            reason: '$name[$index]',
          );
        }
      });
    }

    test('heat and concurrent viewers stay apart (REG-CC-002)', () {
      final room = CcApi.categoryRooms(_sample('S02-area-page1').body, gametype: '9141').first;
      expect(room.popularity, '298945');
      expect(room.onlineViewers, '716');
      expect(room.watching, '298945');
      expect(room.effectiveAudienceMetricType, AudienceMetricType.popularity);
      expect(room.audienceValue(preferRealOnline: true, platformEnabled: true), '716');
    });

    test('a "【重播】" rebroadcast is a replay that plays, grouped apart from live rooms (9-3)', () {
      final rooms = CcApi.categoryRooms(_sample('S02-area-page1').body, gametype: '9141');
      final replay = rooms.firstWhere((room) => room.roomId == '351834961');
      expect(replay.title, startsWith('【重播】'));
      expect(replay.effectiveLiveStatus, LiveStatus.replay);
      expect((replay.isLiveNow, replay.isPlayableNow), (false, true));
      expect(replay.followGroup, FollowGroup.replay);
      expect(replay.restriction, LiveRestriction.none);
      expect(rooms.where((room) => room.isRecord), hasLength(3));
      expect(rooms.where((room) => room.isLiveNow), hasLength(10));
    });

    test('status 1 on air, 0 offline, anything else unknown; start and restriction only on air', () {
      final body = jsonEncode({
        'gametype': '3',
        'lives': [
          for (final (id, status) in [('101', 1), ('102', 0), ('103', 99)])
            {
              'cuteid': id,
              'status': status,
              'webcc_visitor': 800,
              'vision_visitor': 7,
              'gamename': 'Game',
              'startat': '2026-09-27 20:00:00',
              'stream_list': {
                'original': {'vbr': 1000},
              },
            },
          {'cuteid': '104', 'status': 1, 'title': ' 【重播】x', 'startat': '0000-00-00 00:00:00'},
        ],
        'videos': [
          {'cuteid': '999'},
        ],
      });
      final rooms = CcApi.categoryRooms(body, gametype: '3');
      expect(rooms.map((room) => room.effectiveLiveStatus), [
        LiveStatus.live,
        LiveStatus.offline,
        LiveStatus.unknown,
        LiveStatus.replay,
      ]);
      expect(rooms.map((room) => room.startedAt), [DateTime.utc(2026, 9, 27, 12), null, null, null]);
      expect(rooms.map((room) => room.restriction), [LiveRestriction.none, null, null, null]);
      expect(rooms.first.area, 'Game', reason: 'gamename when game_name is missing');
    });

    test('a bad row is skipped (容错); a failed or mismatched answer is ApiChanged, not a short page', () {
      for (final rows in [
        [null],
        [
          {'cuteid': null},
        ],
        [
          {'cuteid': 'abc', 'status': 1},
        ],
      ]) {
        final body = jsonEncode({
          'gametype': 3,
          'lives': [
            ...rows,
            {'cuteid': 5, 'status': 1},
          ],
        });
        expect(CcApi.categoryRooms(body, gametype: '3').map((room) => room.roomId), ['5'], reason: body);
      }
      for (final bad in <Object?>[
        '<!DOCTYPE html>',
        {'error': 'fixture'},
        {'gametype': 4, 'lives': <Object?>[]},
        {'gametype': 3, 'lives': <String, Object?>{}},
        {'gametype': 3, 'lives': List.filled(1001, <String, Object?>{})},
      ]) {
        final body = bad is String ? bad : jsonEncode(bad);
        expect(() => CcApi.categoryRooms(body, gametype: '3'), throwsA(isA<ApiChanged>()), reason: body);
      }
      expect(() => CcApi.categoryRooms('', gametype: '3', status: 503), throwsA(isA<NetworkFailure>()));
      expect(CcApi.categoryRooms('{"gametype":0,"lives":[]}', gametype: '0'), isEmpty, reason: '其他游戏');
    });

    test("startat is Beijing time: the channel's liveMinute counts from it", () {
      final fixture = _sample('S05-channel-live');
      final row = _rows(fixture.body, 'data').single;
      final room = CcApi.channelRoom(fixture.body, ccid: '341438909')!;
      expect(room.startedAt, DateTime.utc(2026, 9, 14, 6, 53, 45));
      expect(fixture.capturedAt.difference(room.startedAt!).inMinutes, closeTo(row['liveMinute'] as int, 1));
    });
  });

  group('S03 recommend', () {
    for (final name in ['S03-live-page1', 'S03-live-last', 'S03-live-beyond']) {
      test('$name matches 3.x', () {
        final fixture = _sample(name);
        final rooms = CcApi.recommendRooms(fixture.body, status: fixture.status);
        final legacy = _rooms(fixture.legacy);
        final rows = _rows(fixture.body, 'lives');
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        for (final (index, room) in rooms.indexed) {
          _expectParity(
            _projection(room),
            legacy[index],
            changed: {
              'area', // 9-2
              if (_isRebroadcast(rows[index])) ..._rebroadcastKeys,
            },
            added: _onAirKeys(rows[index]),
            reason: '$name[$index]',
          );
          expect(room.isPlayableNow, isTrue);
        }
      });
    }

    test('cards show their area: the rows carry only gamename, 3.x read game_name (9-2)', () {
      final fixture = _sample('S03-live-page1');
      final rows = _rows(fixture.body, 'lives');
      expect(rows.every((row) => row['game_name'] == null && row['gamename'] != null), isTrue);
      final rooms = CcApi.recommendRooms(fixture.body);
      expect(rooms.map((room) => room.area), rows.map((row) => row['gamename']));
      expect(rooms.first.area, '蛋仔派对');
      expect(_rooms(fixture.legacy).every((room) => (room['area'] ?? '') == ''), isTrue, reason: '3.x showed none');
    });

    test('rebroadcasts are replays, the others live (9-3)', () {
      final rooms = CcApi.recommendRooms(_sample('S03-live-page1').body);
      expect(rooms.where((room) => room.isRecord), hasLength(20));
      expect(rooms.where((room) => room.isLiveNow), hasLength(10));
      expect(rooms.where((room) => room.isRecord).every((room) => room.title.startsWith('【重播】')), isTrue);
    });

    test('rows without a cuteid are skipped (3.x wrote the room id "null")', () {
      final rooms = CcApi.recommendRooms(
        jsonEncode({
          'lives': [
            {'title': 'x'},
            {'cuteid': 5, 'title': 't', 'hot_score': 10},
          ],
        }),
      );
      expect(rooms.single.roomId, '5');
      expect(rooms.single.cover, '');
      expect(rooms.single.area, '');
      expect(rooms.single.restriction, isNull, reason: 'no tier list: the answer does not say');
      expect(() => CcApi.recommendRooms('{}'), throwsA(isA<ApiChanged>()));
    });
  });

  group('S04 search', () {
    for (final name in ['S04-search-page1', 'S04-search-empty', 'S04-search-beyond']) {
      test('$name matches 3.x', () {
        final fixture = _sample(name);
        final rooms = CcApi.searchRooms(fixture.body, status: fixture.status);
        final legacy = (fixture.legacy as Map<String, dynamic>)['searchRooms'] as List;
        final rows = _rows(jsonEncode(_json(fixture.body)['webcc_anchor']), 'result');
        expect(rooms, hasLength(legacy.length));
        for (final (index, room) in rooms.indexed) {
          final onAir = rows[index]['status'] == 1;
          _expectParity(
            _projection(room),
            legacy[index] as Map<String, dynamic>,
            changed: {
              if (onAir) ...{'cover', 'watching', 'popularity', 'audienceMetricType'}, // 9-5
              if (onAir && _isRebroadcast(rows[index])) ..._rebroadcastKeys,
            },
            added: onAir ? _onAirKeys(rows[index]) : const {},
            reason: '$name[$index]',
          );
        }
        final anchors = ((fixture.legacy as Map<String, dynamic>)['searchAnchors'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          [
            for (final room in rooms)
              {'roomId': room.roomId, 'avatar': room.avatar, 'userName': room.nick, 'liveStatus': room.isLiveNow},
          ],
          [
            for (final (index, anchor) in anchors.indexed)
              // 9-3: a rebroadcasting official account is not live.
              {...anchor, if (_isRebroadcast(rows[index])) 'liveStatus': false},
          ],
        );
      });
    }

    test('on air: the broadcast cover and heat (9-5); offline: portrait and followers (3.x)', () {
      final fixture = _sample('S04-search-page1');
      final rooms = CcApi.searchRooms(fixture.body);
      expect(rooms, hasLength(20));
      expect(rooms.where((room) => room.isPlayableNow), hasLength(4));
      expect(rooms.where((room) => room.isLiveNow).map((room) => room.roomId), ['1234567'], reason: '3 rebroadcasts');
      final live = rooms.firstWhere((room) => room.roomId == '1234567');
      final row = _rows(
        jsonEncode(_json(fixture.body)['webcc_anchor']),
        'result',
      ).firstWhere((row) => row['cuteid'] == 1234567);
      expect(live.cover, row['cover']);
      expect(live.cover, isNot(live.avatar));
      expect((live.watching, live.popularity, live.followers), ('135162', '135162', '577617'));
      expect(live.effectiveAudienceMetricType, AudienceMetricType.popularity);
      expect(live.startedAt, DateTime.utc(2026, 3, 17, 10, 19, 1));
      final offline = rooms.firstWhere((room) => room.roomId == '700700');
      expect(offline.isExplicitlyOfflineNow, isTrue);
      expect(offline.cover, offline.avatar);
      expect(offline.effectiveAudienceMetricType, AudienceMetricType.followers);
      expect(offline.watching, offline.followers);
      expect((offline.startedAt, offline.restriction), (null, null), reason: 'startat is the last broadcast');
    });

    test('on air without heat or cover: the follower count and the portrait', () {
      final room = CcApi.searchRooms(
        jsonEncode({
          'webcc_anchor': {
            'result': [
              {'cuteid': 5, 'status': 1, 'hot_score': 0, 'follower_num': 12, 'portrait': 'https://x.test/p.png'},
            ],
          },
        }),
      ).single;
      expect((room.cover, room.watching, room.popularity), ('https://x.test/p.png', '12', ''));
      expect(room.effectiveAudienceMetricType, AudienceMetricType.followers);
      expect((room.startedAt, room.restriction), (null, null));
    });
  });

  group('S05 detail', () {
    for (final (name, lives, ccid) in [
      ('S05-channel-live', 'S05-lives-live', '341438909'),
      ('S05-channel-replay', 'S05-lives-replay', '732923115'),
    ]) {
      test("$name: the room matches 3.x; 3.x's qualities and URLs are the fallback's", () {
        final channel = CcApi.liveChannel(_sample(lives).body, ccid: ccid);
        final fixture = _sample(name);
        expect(fixture.url.queryParameters['channelids'], channel);
        final room = CcApi.channelRoom(fixture.body, ccid: ccid, status: fixture.status)!;
        final legacy = fixture.legacy as Map<String, dynamic>;
        final row = _rows(fixture.body, 'data').single;
        for (final key in ['getRoomDetailForRefresh', 'getRoomDetail']) {
          _expectParity(
            _projection(room),
            legacy[key] as Map<String, dynamic>,
            changed: {
              // The room page; 3.x kept its redirect playlist there, only to
              // build stream URLs from (now CcRoomData.playlist).
              'link',
              'followers', // 9-6
              if (_isRebroadcast(row)) ..._rebroadcastKeys,
            },
            added: _onAirKeys(row),
            reason: name,
          );
        }
        final data = room.data! as CcRoomData;
        expect(room.link, 'https://cc.163.com/$ccid/');
        expect(room.followers, '${row['follower_num']}', reason: '9-6; 3.x wrote "0"');
        expect(data.playlist, row['m3u8']);
        expect(room.userId, fixture.url.queryParameters['channelids'], reason: 'cc://join-room/{ccid}/{cid}/');
        expect(room.isPlayableNow, isTrue);
        expect(room.effectiveLiveStatus, _isRebroadcast(row) ? LiveStatus.replay : LiveStatus.live);
        expect([
          for (final quality in CcApi.legacyQualities(data))
            {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort, 'getPlayUrls': quality.data},
        ], legacy['getPlayQualites']);
      });
    }

    test('an offline anchor: 3.x failed (状态未知); refreshes mark it offline (REG-CC-003)', () {
      final lives = _sample('S05-lives-offline');
      final legacy = lives.legacy as Map<String, dynamic>;
      expect((legacy['getRoomDetailForRefresh'] as Map<String, dynamic>)['throws'], 'RangeError');
      expect((legacy['getRoomDetail'] as Map<String, dynamic>)['liveStatus'], LiveStatus.unknown.index);
      expect(CcApi.liveChannel(lives.body, ccid: '376267758'), isNull);
      expect(CcApi.channelRoom(_sample('S05-channel-null').body, ccid: '376267758'), isNull);
      final refreshed = CcApi.offlineRoom('376267758');
      expect(refreshed.isExplicitlyOfflineNow, isTrue);
      final stored = LiveRoom(roomId: '376267758', platform: 'cc', nick: '路人7758', watching: '12', title: 't');
      final merged = stored.mergeFrom(refreshed);
      expect((merged.nick, merged.title, merged.watching), ('路人7758', 't', '12'), reason: 'the card keeps the rest');
      expect(merged.isExplicitlyOfflineNow, isTrue);
    });

    test('an offline anchor on room entry: the room page fills the room', () {
      final room = CcApi.pageRoom(_sample('S05-page-offline').body, ccid: '376267758');
      expect(room.roomId, '376267758');
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.nick, '路人7758');
      expect(room.title, '路人7758的直播');
      expect(room.area, '其他游戏');
      expect(room.avatar, 'http://cc.res.netease.com/webcc/portrait/nsep/22_v2');
      expect(room.userId, '6734256');
      expect(room.watching, '39802', reason: "3.x's rule without heat or viewers: the followers");
      expect(room.followers, '39802', reason: '9-6');
      expect(room.effectiveAudienceMetricType, AudienceMetricType.followers);
      expect(room.notice, isNull, reason: 'empty announcement');
      expect((room.startedAt, room.restriction), (null, null));
      expect(room.data, isNull);
    });

    test('an unknown anchor: 3.x showed an error room; the room page says NotFound', () {
      final lives = _sample('S05-lives-missing');
      final legacy = lives.legacy as Map<String, dynamic>;
      expect((legacy['getRoomDetail'] as Map<String, dynamic>)['liveStatus'], LiveStatus.unknown.index);
      expect(CcApi.liveChannel(lives.body, ccid: '88888888888'), isNull);
      expect(() => CcApi.pageRoom(_sample('S05-page-missing').body, ccid: '88888888888'), throwsA(isA<NotFound>()));
    });

    test('recommendbyccid tells an existing anchor from an unknown id (9-7)', () {
      final offline = _sample('S09-exists-offline');
      final missing = _sample('S09-exists-missing');
      expect(offline.url.queryParameters['ccid'], '376267758', reason: 'the offline anchor of S05');
      expect(missing.url.queryParameters['ccid'], '88888888888', reason: 'the unknown id of S05');
      expect(CcApi.anchorExists(offline.body, status: offline.status), isTrue);
      expect(CcApi.anchorExists(missing.body, status: missing.status), isFalse);
      expect(_json(missing.body)['msg'], '没有对应的ccid');
      for (final body in ['{"code":2,"msg":"x"}', '{"msg":""}', '<html>', '[]']) {
        expect(() => CcApi.anchorExists(body), throwsA(isA<ApiChanged>()), reason: body);
      }
      expect(() => CcApi.anchorExists('', status: 503), throwsA(isA<NetworkFailure>()));
      expect(() => CcApi.anchorExists('', status: 429), throwsA(isA<RateLimited>()));
    });

    test('channel and page errors are typed', () {
      expect(() => CcApi.liveChannel('{"code":"BAD_REQUEST"}', ccid: 'abc', status: 400), throwsA(isA<NotFound>()));
      expect(() => CcApi.liveChannel('{"code":"ERR","data":{}}', ccid: '1'), throwsA(isA<ApiChanged>()));
      expect(() => CcApi.liveChannel('{"code":"OK","data":{}}', ccid: '1'), throwsA(isA<ApiChanged>()));
      final live = _sample('S05-channel-live').body;
      expect(() => CcApi.channelRoom(live, ccid: '1'), throwsA(isA<ApiChanged>()), reason: 'another anchor');
      final ended = live.replaceFirst('"status": 1,', '"nolive": 1, "status": 1,');
      expect(ended, isNot(live));
      expect(CcApi.channelRoom(ended, ccid: '341438909'), isNull, reason: 'the broadcast ended in between');
      expect(() => CcApi.pageRoom('<html></html>', ccid: '1'), throwsA(isA<ApiChanged>()));
      final offline = _sample('S05-page-offline').body;
      expect(() => CcApi.pageRoom(offline, ccid: '1'), throwsA(isA<ApiChanged>()), reason: 'another anchor');
      expect(() => CcApi.pageRoom(offline, ccid: '376267758', status: 502), throwsA(isA<NetworkFailure>()));
    });

    test('an offline channel answer has no start or restriction; a live one without tiers no restriction', () {
      final row = _rows(_sample('S05-channel-live').body, 'data').single;
      final offline = CcApi.channelRoom(
        jsonEncode({
          'data': [
            {...row, 'status': 0},
          ],
        }),
        ccid: '341438909',
      )!;
      expect((offline.effectiveLiveStatus, offline.startedAt, offline.restriction), (LiveStatus.offline, null, null));
      final bare = CcApi.channelRoom(
        jsonEncode({
          'data': [
            {...row}..remove('stream_list'),
          ],
        }),
        ccid: '341438909',
      )!;
      expect((bare.isLiveNow, bare.restriction), (true, null));
    });
  });

  group("3.x's streams (the fallback since 9-1)", () {
    CcRoomData data() => CcApi.channelRoom(_sample('S05-channel-live').body, ccid: '341438909')!.data! as CcRoomData;

    test('every tier leads to the one redirect playlist, as 3.x played it (REG-CC-004)', () {
      final qualities = CcApi.legacyQualities(data());
      expect(qualities.map((quality) => quality.quality), ['原画', '高清', '标准', '低清']);
      const base = 'http://cgi.v.cc.163.com/redirect/video/341438909.m3u8?secret=bac6536f08';
      for (final quality in qualities) {
        expect(
          (quality.data! as List).every((url) => '$url'.startsWith('$base&')),
          isTrue,
          reason: '${quality.id}: the same playlist with the tier’s signature appended, which the site ignores',
        );
      }
    });

    test('lines: the URLs with 3.x media headers, HLS, the quality assumed applied', () {
      final quality = CcApi.legacyQualities(data()).first;
      final resolution = CcApi.legacyResolution(quality, roomId: '341438909');
      expect(resolution.urls, quality.data);
      expect(resolution.appliedQualityData, 'original');
      for (final line in resolution.lines) {
        expect(line.headers, {
          'user-agent': CcApi.userAgent,
          'origin': 'https://cc.163.com',
          'referer': 'https://cc.163.com/341438909/',
        });
        expect(line.format, StreamFormat.hls);
        expect(line.lease, isNull);
      }
    });

    test('a quickplay object lists its own URLs; tiers without URLs are left out; unknown tiers by bitrate', () {
      final qualities = CcApi.legacyQualities(
        const CcRoomData(
          streams: {
            'resolution': {
              'high': {
                'vbr': 2000,
                'cdn': {'xx': 'https://x.test/b.flv', 'ali': '//a.test/a.flv'},
              },
              'custom': {
                'vbr': 3000,
                'cdn': {'ali': 'https://a.test/c.flv'},
              },
              'low': {'vbr': 500, 'cdn': <String, Object?>{}},
            },
          },
        ),
      );
      expect(qualities.map((quality) => (quality.id, quality.quality)), [('high', '高清'), ('custom', 'custom')]);
      expect(qualities.first.data, ['https://a.test/a.flv', 'https://x.test/b.flv'], reason: 'ali before others');
      expect(CcApi.legacyQualities(const CcRoomData()), isEmpty);
    });
  });

  group('S06 streams: video_play_url (9-1)', () {
    test('one stream per tier, named by the site', () {
      final qualities = CcApi.qualities(CcApi.playData(_sample('S06-play-default').body));
      expect(
        [for (final quality in qualities) (quality.quality, quality.id, quality.data, quality.sort)],
        [
          ('原画', 'original', 'original', 4),
          ('超清', 'ultra', 'ultra', 3),
          ('高清', 'high', 'high', 2),
          ('标清', 'standard', 'standard', 1),
        ],
      );
    });

    test('a room with more tiers: 蓝光 ones between the source and 超清', () {
      final fixture = _sample('S06-play-replay');
      expect(fixture.url.path, '/video_play_url/732923115', reason: 'the rebroadcast of S05-channel-replay');
      final qualities = CcApi.qualities(CcApi.playData(fixture.body, status: fixture.status));
      expect(
        [for (final quality in qualities) (quality.quality, quality.id)],
        [
          ('原画', 'original'),
          ('蓝光5M', 'blueray_5M_avc'),
          ('蓝光3M', 'blueray_3M_avc_lowfps'),
          ('超清', 'ultra'),
          ('高清', 'high'),
          ('标清', 'standard'),
        ],
      );
      expect(qualities.map((quality) => quality.sort), [6, 5, 4, 3, 2, 1]);
    });

    test("3.x's quality ids map to the tier with the same stream, for M9", () {
      expect(CcApi.legacyQualityIds, {
        'original': 'original',
        'high': 'ultra',
        'medium': 'high',
        'low': 'standard',
        'blueray_20M': 'blueray_5M_avc',
      });
      expect(CcApi.qualityIdFromLegacy(' medium '), 'high');
      expect(CcApi.qualityIdFromLegacy('high'), 'ultra', reason: "3.x's high is 2 Mbps: now 超清");
      expect(CcApi.qualityIdFromLegacy('custom'), 'custom');
      // Every tier 3.x listed maps to a tier the same room offers now.
      for (final (channel, ccid, play) in [
        ('S05-channel-live', '341438909', 'S06-play-default'),
        ('S05-channel-replay', '732923115', 'S06-play-replay'),
      ]) {
        final data = CcApi.channelRoom(_sample(channel).body, ccid: ccid)!.data! as CcRoomData;
        final ids = CcApi.qualities(CcApi.playData(_sample(play).body)).map((quality) => quality.id).toSet();
        for (final quality in CcApi.legacyQualities(data)) {
          expect(ids, contains(CcApi.qualityIdFromLegacy('${quality.id}')), reason: '$channel ${quality.id}');
        }
      }
      // The stream names agree where both answers were recorded.
      final tiers = (_rows(_sample('S05-channel-live').body, 'data').single['stream_list'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, (value as Map<String, dynamic>)['streamname'] as String),
      );
      String stream(String sample) =>
          Uri.parse(_json(_sample(sample).body)['videourl'] as String).pathSegments.last.replaceFirst('.flv', '');
      expect(stream('S06-play-default'), tiers['original']);
      expect(stream('S06-play-high'), tiers['medium'], reason: "3.x's medium is now high");
    });

    test('the default answer: lines on cdn_sel and bakcdn_sel, media headers, FLV and a lease (REG-CC-005)', () {
      final fixture = _sample('S06-play-default');
      final data = CcApi.playData(fixture.body, status: fixture.status);
      expect(CcApi.uncoveredCdns(data), isEmpty);
      final resolution = CcApi.resolution([(data: data, issuedAt: fixture.capturedAt)], roomId: '341438909');
      expect(resolution.appliedQualityData, 'original');
      expect(resolution.qualityUnconfirmed, isFalse);
      expect(resolution.lines.map((line) => line.lineId), ['hs', 'ali']);
      expect(resolution.urls, [data['videourl'], data['bakvideourl']]);
      for (final line in resolution.lines) {
        expect(line.headers, CcApi.mediaHeaders('341438909'));
        expect(line.format, StreamFormat.flv);
        final lease = line.lease!;
        final expiry = int.parse(Uri.parse(line.url).queryParameters['auth_key']!.split('-').first);
        expect(lease.expiresAt, DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true));
        expect(lease.expiresAt!.difference(fixture.capturedAt).inSeconds, inInclusiveRange(290, 300));
        expect(lease.expiresAt!.difference(lease.refreshAt), CcApi.leaseLead);
        expect(lease.cutsConnection, isFalse, reason: 'an established connection outlives the key');
      }
    });

    test('a requested tier is confirmed; a CDN the server answers with another adds no line', () {
      final high = _sample('S06-play-high');
      final hs = _sample('S06-play-high-hs');
      expect(hs.url.queryParameters['cdn'], 'hs');
      final resolution = CcApi.resolution([
        (data: CcApi.playData(high.body), issuedAt: high.capturedAt),
        (data: CcApi.playData(hs.body), issuedAt: hs.capturedAt),
      ], roomId: '341438909');
      expect(resolution.appliedQualityData, 'high');
      expect(resolution.lines.map((line) => line.lineId), ['ali']);
      expect(Uri.parse(resolution.urls.single).path, endsWith('tc2.flv'));
      final shown = resolveAppliedPlayQuality(
        qualities: CcApi.qualities(CcApi.playData(high.body)),
        requested: const LivePlayQuality(quality: '高清', id: 'high', data: 'high'),
        resolution: resolution,
      );
      expect(shown.quality, '高清');
      expect(shown.isPlaybackUnconfirmed, isFalse);
    });

    test('a CDN answer at another tier is dropped', () {
      final base = _json(_sample('S06-play-default').body);
      final other = {...base, 'vbrname_sel': 'high', 'cdn_sel': 'ks', 'videourl': 'https://ks.test/a.flv'}
        ..remove('bakvideourl');
      final resolution = CcApi.resolution([
        (data: {...base}..remove('bakvideourl'), issuedAt: DateTime.utc(2026)),
        (data: other, issuedAt: DateTime.utc(2026)),
      ], roomId: '1');
      expect(resolution.lines.map((line) => line.lineId), ['hs']);
    });

    test('an anchor without a stream is 410 Gone: StreamUnavailable', () {
      final fixture = _sample('S06-play-offline');
      expect(() => CcApi.playData(fixture.body, status: fixture.status), throwsA(isA<StreamUnavailable>()));
      expect(() => CcApi.playData('<html>', status: 404), throwsA(isA<StreamUnavailable>()));
      expect(() => CcApi.playData('', status: 502), throwsA(isA<NetworkFailure>()));
      expect(
        () => CcApi.resolution([(data: <String, dynamic>{}, issuedAt: DateTime.utc(2026))], roomId: '1'),
        throwsA(isA<ApiChanged>()),
      );
    });

    test("qualities fall back to vbrname_sel; unnamed tiers take the site's names; the source is 原画", () {
      expect(CcApi.qualities({'vbrname_sel': 'high'}).single.quality, '高清');
      expect(CcApi.qualities({'vbrname_sel': 'ultra'}).single.quality, '超清', reason: "3.x's table said 蓝光");
      expect(CcApi.qualities({'vbrname_sel': 'standard'}).single.quality, '标清');
      expect(
        CcApi.qualities({
          'vbrname_list': ['original'],
          'vbrname_mapping': {'original': '蓝光原画'},
        }).single.quality,
        '原画',
      );
      expect(
        CcApi.qualities({
          'vbrname_list': ['blueray_5M_avc'],
        }).single.quality,
        'blueray_5M_avc',
      );
      expect(() => CcApi.qualities(const {}), throwsA(isA<ApiChanged>()));
    });

    test('leases: none without auth_key or when past; a short life renews at a quarter', () {
      final issued = DateTime.utc(2026, 9, 27, 12);
      final seconds = issued.millisecondsSinceEpoch ~/ 1000;
      expect(CcApi.lease(Uri.parse('https://x.test/a.flv'), issued), isNull);
      expect(CcApi.lease(Uri.parse('https://x.test/a.flv?auth_key=${seconds - 1}-r-0-h'), issued), isNull);
      final lease = CcApi.lease(Uri.parse('https://x.test/a.flv?auth_key=${seconds + 100}-r-0-h'), issued)!;
      expect(lease.expiresAt!.difference(lease.refreshAt), const Duration(seconds: 25));
      expect(CcApi.mediaHeaders(' ')['referer'], 'https://cc.163.com/');
    });
  });
}
