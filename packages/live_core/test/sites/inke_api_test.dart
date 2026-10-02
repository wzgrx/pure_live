// Inke parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/inke/legacy_expected.dart from 3.x's InkeApi and InkeSite). Every
// intended difference is listed with its reason (M4.14's, and the M4.U
// upgrades by their docs/specs/UPGRADES.md numbers); everything else must match.
// The synthetic cases port 3.x's inke_api_test.dart and
// inke_application_test.dart.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('inke', name);

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

/// 3.x's room projection: toJson plus `link`.
Map<String, Object?> _projection(LiveRoom room) => {...room.toJson(), 'link': room.link};

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

/// The `result` of a traced legacy call.
Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {String reason = ''}) {
  final expected = _maps(legacy);
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(_projection(room), expected[index], reason: '$reason[$index]');
  }
}

String _web(Object? data, {int code = 0}) => jsonEncode({'error_code': code, 'message': 'ok', 'data': data});

String _app(Object? live, {int code = 0}) => jsonEncode({'dm_error': code, 'error_msg': '操作成功', 'live': live});

const _media = 'https://live-pull-ws.ikstatic.cn/live/200_t.flv?wsSecret=fixture%2Bonly&wsABStime=70000000';

const _zego =
    'http://live-pull-zego.ikstatic.cn/inkemain/200_0_en.flv?stream_id=200_0_en&codecInfo=8192'
    '&wsSecret=fixture&wsABStime=70000000';

/// The audience keys the app's answer fills (14-3).
const _audienceKeys = {'watching', 'onlineViewers', 'popularity', 'audienceMetricType'};

/// 3.x's test showcase row.
Map<String, dynamic> _row({Object uid = 100, String liveId = '200', String url = _media, String nick = 'Fixture'}) => {
  'uid': uid,
  'live_id': liveId,
  'nick': nick,
  'level': 60,
  'gender': 0,
  'portrait': 'https://img.ikstatic.cn/fixture.jpg',
  'stream_addr': url,
};

/// 3.x's test room answer.
Map<String, dynamic> _info({String liveId = '200'}) => {
  'live_uid': '100',
  'liveid': liveId,
  'status': 1,
  'live_name': 'Music',
  'media_info': {'inke_id': 100, 'nick': 'Fixture', 'level': 60, 'portrait': 'https://img.ikstatic.cn/fixture.jpg'},
  'portrait': 'https://img.ikstatic.cn/fixture.jpg',
  'records': <Object?>[],
};

/// 3.x's test channel.
Map<String, dynamic> _group({String key = 'MUSIC', List<Object?>? rows}) => {
  'tab_key': key,
  'channel_name': 'Music',
  'list': rows ?? [_row()],
};

/// A `now_publish` broadcast of anchor 100.
Map<String, dynamic> _live({
  Object creator = 100,
  Object status = 1,
  String id = '200',
  String url = _media,
  String? zego,
}) => {
  'creator': creator,
  'id': id,
  'status': status,
  'name': 'Music',
  'stream_addr': url,
  'stream_multi_addr': zego ?? _zego.replaceAll('200_0_en', '${id}_0_en'),
};

void main() {
  group('S01 catalog and channels', () {
    for (final name in ['S01-channels', 'S05-unlisted-channels']) {
      test('$name: the catalog and every channel page match 3.x', () {
        final fixture = _sample(name);
        final legacy = _legacy(name);
        final category = InkeApi.categories(fixture.body, status: fixture.status).single;
        final known = _maps(legacy['getCategores']).single;
        expect((category.id, category.name), (known['id'], known['name']));
        // changed: the first area is the website's top list, 3.x's
        // recommendations (14-1: the recommendations are the app's hot list).
        expect(category.children.first, same(InkeApi.topArea));
        final areas = _maps(known['children']);
        final channels = category.children.skip(1).toList();
        expect(channels, hasLength(areas.length));
        for (final (index, area) in channels.indexed) {
          _expectParity(area.toJson(), areas[index], reason: '$name area $index');
        }
        final pages = legacy['getDirectoryPage'] as Map<String, dynamic>;
        expect(pages.keys, channels.map((area) => area.areaId));
        for (final MapEntry(:key, :value) in pages.entries) {
          final page = InkeApi.channelPage(fixture.body, tabKey: key);
          final want = _result(value)! as Map<String, dynamic>;
          expect((page.page, page.hasMore), (want['page'], want['hasMore']));
          _expectRooms(page.rooms, want['rooms'], reason: '$name $key');
          expect(page.rooms.every((room) => room.isLiveNow && room.data == null), isTrue);
        }
      });
    }

    test('S01-channels: the top list, then the six channels of the site, in its order (14-1)', () {
      final category = InkeApi.categories(_sample('S01-channels').body).single;
      expect(category.children.map((area) => area.areaName), ['官网推荐', '音乐', '舞蹈', '新颜', '校园', '男神', '派对']);
      expect(category.children.map((area) => area.areaType).toSet(), {'showcase'});
      expect(category.children.map((area) => area.typeName).toSet(), {'映客官网精选'});
      expect(InkeApi.topArea.areaId, 'Live_top_pc', reason: 'no channel key can be it (they are alphanumeric)');
      expect(InkeApi.topArea.platform, 'inke');
    });

    test('channel keys pick the real group, whatever the order; an unknown one is NotFound (3.x)', () {
      final body = _web({
        'list': [
          _group(),
          _group(key: 'CHAT', rows: [_row(uid: 101)]),
        ],
      });
      expect(InkeApi.categories(body).single.children.map((area) => area.areaId), ['Live_top_pc', 'MUSIC', 'CHAT']);
      expect(InkeApi.channelPage(body, tabKey: 'CHAT').rooms.single.roomId, '101');
      expect(() => InkeApi.channelPage(body, tabKey: 'missing'), throwsA(isA<NotFound>()));
    });

    test('a repeated or unsafe key, a nameless channel or a bad list skips that channel (容错; 3.x failed)', () {
      for (final groups in <List<Object?>>[
        [
          _group(),
          _group(rows: [_row(uid: 999)]),
        ],
        [_group(key: 'BAD')..['list'] = <String, Object?>{}, _group()],
        [_group(key: '../path'), _group()],
        [_group(key: 'NAMELESS')..['channel_name'] = ' ', _group()],
        [_group(key: 'x' * 65), _group()],
        [
          _group(
            key: 'LONG',
            rows: List.generate(1001, (index) => _row(uid: index + 1)),
          ),
          _group(),
        ],
        ['not a channel', _group()],
      ]) {
        final body = _web({'list': groups});
        expect(InkeApi.categories(body).single.children.map((area) => area.areaId), [
          'Live_top_pc',
          'MUSIC',
        ], reason: '$groups');
        expect(InkeApi.channelRooms(body).map((room) => room.roomId), ['100'], reason: 'the first MUSIC');
      }
    });

    test('no list of channels, or over 100, still fails the catalog', () {
      for (final groups in <Object?>[
        List.generate(101, (index) => _group(key: 'K$index')),
        {'MUSIC': _group()},
        'channels',
      ]) {
        expect(() => InkeApi.categories(_web({'list': groups})), throwsA(isA<ApiChanged>()), reason: '$groups');
        expect(() => InkeApi.channelRooms(_web({'list': groups})), throwsA(isA<ApiChanged>()), reason: '$groups');
      }
    });
  });

  group('S01 top list (the area 官网推荐)', () {
    for (final name in ['S01-top', 'S05-unlisted-top']) {
      test("$name: 3.x's recommendations, now the top area, match 3.x", () {
        final fixture = _sample(name);
        final page = InkeApi.topPage(fixture.body, status: fixture.status);
        final want = _result(_legacy(name)['getDirectoryPage'])! as Map<String, dynamic>;
        expect((page.page, page.hasMore), (want['page'], want['hasMore']));
        _expectRooms(page.rooms, want['rooms'], reason: name);
      });
    }

    test('one finite page, each uid once, no audience (3.x)', () {
      final page = InkeApi.topPage(
        _web({
          'list': [_row(), _row(), _row(uid: 101)],
        }),
      );
      expect(page.rooms.map((room) => room.roomId), ['100', '101']);
      final room = page.rooms.first;
      expect(room.watching, isEmpty);
      expect(room.audienceMetricType, AudienceMetricType.unknown);
      // changed: the platform has concurrent viewers since M4.U (14-3, in
      // the app's answers); a showcase card still has none.
      expect(room.supportsRealOnlineCount, isTrue);
      expect(room.hasRealOnlineCount, isFalse);
      expect(room.audienceValue(preferRealOnline: false, platformEnabled: true), isEmpty);
      expect((room.startedAt, room.restriction), (null, null), reason: 'the showcases tell neither');
      expect((room.title, room.nick, room.userId), ('Fixture', 'Fixture', '100'));
      expect((room.avatar, room.cover), ('https://img.ikstatic.cn/fixture.jpg', 'https://img.ikstatic.cn/fixture.jpg'));
      expect(room.link, 'https://www.inke.cn/liveroom/index.html?uid=100&id=200');
      expect(page.hasMore, isFalse);
      expect(() => page.rooms.add(room), throwsUnsupportedError);
    });

    test('a row without a uid, broadcast id or nickname is skipped (容错; 3.x failed the list)', () {
      for (final row in <Object?>[
        _row(uid: '0100'),
        _row(uid: 1.5),
        _row(liveId: ''),
        _row(nick: ' '),
        _row()..remove('nick'),
        'row',
      ]) {
        final page = InkeApi.topPage(
          _web({
            'list': [row, _row(uid: 101)],
          }),
        );
        expect(page.rooms.map((room) => room.roomId), ['101'], reason: '$row');
      }
      expect(() => InkeApi.topPage(_web({'list': 'rows'})), throwsA(isA<ApiChanged>()));
      expect(
        () => InkeApi.topPage(_web({'list': List.generate(1001, (index) => _row(uid: index + 1))})),
        throwsA(isA<ApiChanged>()),
      );
    });
  });

  group('S02 app hot list (14-1, 14-3, 14-4)', () {
    final fixture = _sample('S02-simpleall');
    final page = InkeApi.hotPage(fixture.body, status: fixture.status);
    final lives = ((jsonDecode(fixture.body) as Map<String, dynamic>)['lives'] as List).cast<Map<String, dynamic>>();

    test('the recommendations: every live broadcast of the hot list, in order, one page', () {
      expect((page.page, page.hasMore), (1, false));
      expect(page.rooms.map((room) => room.roomId), [
        for (final live in lives) '${(live['creator'] as Map<String, dynamic>)['id']}',
      ]);
      expect(page.rooms, hasLength(15));
      expect(page.rooms.every((room) => room.isLiveNow && room.data == null), isTrue);
    });

    test("each card: the app's title, cover, start time and audience; no restriction (a line is given)", () {
      for (final (index, room) in page.rooms.indexed) {
        final live = lives[index];
        final creator = live['creator'] as Map<String, dynamic>;
        final name = live['name'] as String;
        expect((room.userId, room.nick), ('${creator['id']}', creator['nick']), reason: '$index');
        expect(room.title, name == '正在直播中' ? creator['nick'] : name, reason: '$index');
        expect(room.avatar, creator['portrait'], reason: '$index');
        expect(room.cover, (live['cover'] as String).isEmpty ? creator['portrait'] : live['cover'], reason: '$index');
        expect(room.link, 'https://www.inke.cn/liveroom/index.html?uid=${creator['id']}&id=${live['id']}');
        expect(
          room.startedAt,
          DateTime.fromMillisecondsSinceEpoch((live['start_time'] as int) * 1000, isUtc: true),
          reason: '$index',
        );
        final real = '${(live['numbers'] as Map<String, dynamic>)['real']}';
        expect((room.onlineViewers, room.watching, room.popularity), (real, real, '${live['online_users']}'));
        expect(room.audienceMetricType, AudienceMetricType.onlineViewers);
        expect(room.restriction, LiveRestriction.none, reason: '$index');
      }
    });

    test('the first card, and the audience as shown: "N人在看" as concurrent viewers, online_users as heat', () {
      final room = page.rooms.first;
      expect((room.roomId, room.title, room.nick), ('761920733', '雪儿🧸', '雪儿🧸'));
      expect(room.cover, 'https://img.ikstatic.cn/MTc4OTQwNjk5NTk4NyM0MjMjanBn.jpg');
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 15, 7, 27));
      expect(room.audienceValue(preferRealOnline: true, platformEnabled: true), '1586');
      expect(room.audienceType(preferRealOnline: true, platformEnabled: true), AudienceMetricType.onlineViewers);
      expect(room.audienceValue(preferRealOnline: false, platformEnabled: true), '2993');
      expect(room.audienceType(preferRealOnline: false, platformEnabled: true), AudienceMetricType.popularity);
      final json = room.toJson();
      expect((json['startedAt'], json['restriction']), ('2026-09-27T15:07:27.000Z', 'none'));
      expect(LiveRoom.fromJson(json).startedAt, room.startedAt);
    });

    test('the placeholder title "正在直播中" is no title: the nickname stands in (统一原则: 占位信息)', () {
      final untitled = page.rooms.where((room) => const {'2777275', '731562193'}.contains(room.roomId)).toList();
      expect(untitled.map((room) => room.title), ['🌸⁷⁷ 不忘初心', '🎶九酱全网㊗️多米9.28🎂']);
      expect(page.rooms.map((room) => room.title), isNot(contains('正在直播中')));
      final coverless = untitled.first;
      expect(coverless.cover, coverless.avatar, reason: 'no cover: the avatar, as 3.x');
      final titled = page.rooms.singleWhere((room) => room.roomId == '756317788');
      expect((titled.title, titled.nick), ('抽个金锤吧', '江江～'));
    });

    test('a row that is not a live broadcast with a uid and an id is skipped; each uid once', () {
      Map<String, dynamic> live({Object creator = 100, Object id = '200', Object status = 1}) => {
        'creator': {'id': creator, 'nick': 'Fixture'},
        'id': id,
        'status': status,
        'name': 'Music',
        'stream_addr': _media,
      };
      final body = jsonEncode({
        'dm_error': 0,
        'lives': [
          live(creator: '0100'),
          live(creator: 'x'),
          live(id: ''),
          live(status: 0),
          {'creator': 100, 'id': '200', 'status': 1},
          'row',
          live(),
          live(id: '201'),
          live(creator: 101, id: '300'),
        ],
      });
      final rooms = InkeApi.hotPage(body).rooms;
      expect(rooms.map((room) => room.roomId), ['100', '101']);
      expect(rooms.first.link, endsWith('&id=200'));
      expect(() => InkeApi.hotPage('{"dm_error":0,"lives":{}}'), throwsA(isA<ApiChanged>()));
      expect(() => InkeApi.hotPage('{"dm_error":0}'), throwsA(isA<ApiChanged>()));
      expect(() => InkeApi.hotPage('{"dm_error":499,"lives":[]}'), throwsA(isA<ApiChanged>()));
      expect(() => InkeApi.hotPage('', status: 503), throwsA(isA<NetworkFailure>()));
      expect(InkeApi.hotPage('{"dm_error":0,"lives":[]}').rooms, isEmpty);
    });

    test('a broadcast without a line, audience or start time: no restriction known, no numbers', () {
      final body = jsonEncode({
        'dm_error': 0,
        'lives': [
          {
            'creator': {'id': 100, 'nick': 'Fixture', 'portrait': 'https://img.ikstatic.cn/a.jpg'},
            'id': '200',
            'status': 1,
            'name': '',
            'start_time': 0,
            'online_users': -1,
            'numbers': {'real': 'many'},
          },
        ],
      });
      final room = InkeApi.hotPage(body).rooms.single;
      expect((room.title, room.cover), ('Fixture', 'https://img.ikstatic.cn/a.jpg'));
      expect((room.startedAt, room.restriction), (null, null));
      expect((room.watching, room.onlineViewers, room.popularity), ('', '', ''));
      expect(room.audienceMetricType, AudienceMetricType.unknown);
    });

    test('start times: Unix seconds from 2000 to 2100, else none', () {
      expect(InkeApi.startTime(1790521647), DateTime.utc(2026, 9, 27, 15, 7, 27));
      expect(InkeApi.startTime('1790521647'), DateTime.utc(2026, 9, 27, 15, 7, 27));
      for (final value in <Object?>[0, -1, 946684799, 1790521647000, 4102444801, 'x', 1.5, null]) {
        expect(InkeApi.startTime(value), isNull, reason: '$value');
      }
    });
  });

  group('search', () {
    final top = InkeApi.topPage(_sample('S01-top').body).rooms;
    final channels = InkeApi.channelRooms(_sample('S01-channels').body);
    final hot = InkeApi.hotPage(_sample('S02-simpleall').body).rooms;
    final legacy = _legacy('S01-top')['searchRooms'] as Map<String, dynamic>;
    const keywords = ['糖果', '西', '欧阳', 'mee', '🎶', 'zxqvnoresultfixture'];

    for (final keyword in keywords) {
      test('"$keyword" over the S01 showcases matches 3.x', () {
        final rooms = InkeApi.searchShowcases(keyword, [...top, ...channels]);
        _expectRooms(rooms, _result(legacy[keyword]), reason: keyword);
      });
    }

    test('pages of the matches match 3.x', () {
      for (final page in [1, 2, 3]) {
        final rooms = InkeApi.searchShowcases('🎶', [...top, ...channels], page: page, pageSize: 3);
        _expectRooms(rooms, _result(legacy['🎶 page $page, pageSize 3']), reason: 'page $page');
      }
    });

    test('a room in the top list and a channel is found once; case is ignored (3.x)', () {
      expect(InkeApi.searchShowcases(' 糖果 ', [...top, ...channels]).map((room) => room.roomId), [
        '757370483',
      ], reason: 'in the top list and 舞蹈');
      expect(InkeApi.searchShowcases('MEE', [...top, ...channels]).single.nick, 'Mee 蓝');
      expect(InkeApi.searchShowcases('  ', [...top, ...channels]), isEmpty);
    });

    for (final keyword in keywords) {
      test('14-2: "$keyword" also over the app hot list: 3.x\'s matches first, the app\'s cards where it has them', () {
        final rooms = InkeApi.searchShowcases(keyword, [...top, ...channels], hot: hot);
        final known = _maps(_result(legacy[keyword]));
        final knownIds = [for (final room in known) room['roomId']];
        final extra = [
          for (final room in hot)
            if (room.nick.toLowerCase().contains(keyword) && !knownIds.contains(room.roomId)) room.roomId,
        ];
        expect(rooms.map((room) => room.roomId), [...knownIds, ...extra].take(20), reason: keyword);
        final cards = {for (final room in hot) room.roomId: room};
        for (final (index, room) in rooms.indexed) {
          if (cards[room.roomId] case final card?) {
            // changed: the hot list's card (14-4: the app's title and cover;
            // 14-3: its audience), plus its start time and restriction.
            expect(room, same(card), reason: '$keyword ${room.roomId}');
          } else {
            _expectParity(_projection(room), known[index], reason: '$keyword ${room.roomId}');
          }
        }
      });
    }

    test('14-2: a room only the hot list has is found; one in both is the hot card at its first place', () {
      expect(InkeApi.searchShowcases('喜锦鲤', [...top, ...channels]), isEmpty, reason: 'not in the showcases');
      final found = InkeApi.searchShowcases('喜锦鲤', [...top, ...channels], hot: hot).single;
      expect((found.roomId, found.onlineViewers, found.popularity), ('2533970', '1944', '7124'));
      final both = InkeApi.searchShowcases('雪儿', [...top, ...channels], hot: hot);
      expect(both.map((room) => room.roomId), ['761920733']);
      expect((both.single.title, both.single.startedAt), ('雪儿🧸', DateTime.utc(2026, 9, 27, 15, 7, 27)));
      expect(InkeApi.searchShowcases('🎶', [...top, ...channels], hot: hot, page: 9, pageSize: 3), isEmpty);
    });
  });

  group('S03 detail', () {
    test('S03-share-live: the room matches 3.x at every depth; the broadcast id is kept aside', () {
      final fixture = _sample('S03-share-live');
      final legacy = _legacy('S03-share-live');
      final room = InkeApi.detail(fixture.body, uid: '771067357', status: fixture.status);
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        _expectParity(_projection(room), _result(legacy[key])! as Map<String, dynamic>, reason: key);
      }
      _expectParity(_projection(room), _maps(_result(legacy['searchRooms'])).single, reason: 'search');
      expect(room.roomId, '771067357', reason: 'the uid asked for (3.x)');
      expect((room.data! as InkeRoomData).liveId, '1790521153165881');
      expect(InkeApi.externalRoomUrl(room), legacy['externalRoomUrl']);
      expect(room.introduction, isNull, reason: '3.x set none; media_info.description is a placeholder');
      expect((room.startedAt, room.restriction), (null, null), reason: 'the website tells neither');
    });

    test('S03-share-offline: code 1099999920 is offline with only the uid, as 3.x', () {
      final fixture = _sample('S03-share-offline');
      final legacy = _legacy('S03-share-offline');
      final room = InkeApi.detail(fixture.body, uid: '1', status: fixture.status);
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        _expectParity(_projection(room), _result(legacy[key])! as Map<String, dynamic>, reason: key);
      }
      expect(room.isExplicitlyOfflineNow, isTrue);
      expect(room.data, isNull);
      expect(room.link, 'https://www.inke.cn/liveroom/index.html?uid=1');
      expect(InkeApi.externalRoomUrl(room), legacy['externalRoomUrl'], reason: 'no broadcast: the home page');
      expect(legacy['getPlayQualites'], isEmpty);
      expect((room.startedAt, room.restriction), (null, null));
    });

    test('S05-unlisted-share: 3.x failed the room it could not find a pull URL for; now it opens', () {
      final fixture = _sample('S05-unlisted-share');
      final legacy = _legacy('S05-unlisted-share');
      // changed: getRoomDetail and getRoomDetailForRecording. 3.x looked for the
      // broadcast in the showcases (four requests) and failed the whole room;
      // the room is now the refresh's, and the stream is resolved when played.
      for (final key in ['getRoomDetail', 'getRoomDetailForRecording']) {
        final result = _result(legacy[key])! as Map<String, dynamic>;
        expect(result['throws'], 'InkeException', reason: key);
        expect(result['message'], contains('官网精选未提供'), reason: key);
        expect((legacy[key] as Map<String, dynamic>)['requests'], hasLength(4));
      }
      final room = InkeApi.detail(fixture.body, uid: '778920027');
      _expectParity(_projection(room), _result(legacy['getRoomDetailForRefresh'])! as Map<String, dynamic>);
      expect(room.isLiveNow, isTrue);
      expect((room.data! as InkeRoomData).liveId, '1790588581683219');
    });

    test('an answer that is not the live room of that anchor is ApiChanged, never offline (3.x)', () {
      for (final edit in <void Function(Map<String, dynamic>)>[
        (info) => info['media_info'] = {'inke_id': 101, 'nick': 'Other'},
        (info) => info['media_info'] = {'inke_id': 100, 'nick': ' '},
        (info) => info['media_info'] = 'none',
        (info) => info['live_uid'] = '101',
        (info) => info['status'] = 2,
        (info) => info['liveid'] = '',
        (info) => info
          ..clear()
          ..['noCurrentBroadcast'] = true,
      ]) {
        final info = _info();
        edit(info);
        expect(() => InkeApi.detail(_web(info), uid: '100'), throwsA(isA<ApiChanged>()), reason: '$info');
      }
      for (final status in [1, '1', true]) {
        expect(InkeApi.detail(_web(_info()..['status'] = status), uid: '100').isLiveNow, isTrue, reason: '$status');
      }
      final untitled = InkeApi.detail(_web(_info()..['live_name'] = ''), uid: '100');
      expect(untitled.title, 'Fixture', reason: 'the nickname stands in');
    });

    test('S06-placeholder-share: the title "正在直播中" is no title, the nickname stands in (统一原则: 占位信息)', () {
      final fixture = _sample('S06-placeholder-share');
      final room = InkeApi.detail(fixture.body, uid: '778398645', status: fixture.status);
      final info = (jsonDecode(fixture.body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      expect(info['live_name'], '正在直播中', reason: '3.x showed it as the title');
      expect((room.title, room.nick), ('西宝😘', '西宝😘'));
      final spaced = InkeApi.detail(_web(_info()..['live_name'] = ' 正在直播中 '), uid: '100');
      expect(spaced.title, 'Fixture');
    });

    test('only the room endpoint reads code 1099999920 as offline (3.x)', () {
      const offline = '{"error_code":1099999920,"data":null}';
      expect(InkeApi.detail(offline, uid: '100').isExplicitlyOfflineNow, isTrue);
      expect(() => InkeApi.topPage(offline), throwsA(isA<ApiChanged>()));
      expect(() => InkeApi.categories(offline), throwsA(isA<ApiChanged>()));
      expect(() => InkeApi.detail('{"error_code":12345,"data":null}', uid: '100'), throwsA(isA<ApiChanged>()));
    });
  });

  group("the app's broadcast in the room (14-3, 14-4)", () {
    LiveRoom enriched(String share, String publish, String uid) {
      final received = _sample(publish).capturedAt;
      final room = InkeApi.detail(_sample(share).body, uid: uid);
      return InkeApi.withBroadcast(room, InkeApi.broadcast(_sample(publish).body, uid: uid)!, receivedAt: received);
    }

    test("S03 + S04: 3.x's room with the app's cover, audience, start time and lines", () {
      final room = enriched('S03-share-live', 'S04-publish-live', '771067357');
      final legacy = _result(_legacy('S03-share-live')['getRoomDetail'])! as Map<String, dynamic>;
      // changed: the cover is the app's (14-4); the audience is the app's
      // (14-3). The title ('木子') and the link are the same.
      _expectParity(_projection(room), legacy, changed: {'cover', ..._audienceKeys});
      expect(room.cover, 'https://img.ikstatic.cn/MTc2NDc0ODEyNjMyOSM3NjYjanBn.jpg');
      expect((room.onlineViewers, room.popularity, room.watching), ('12', '12', '12'));
      expect(room.audienceMetricType, AudienceMetricType.onlineViewers);
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 14, 59, 52));
      expect(room.restriction, LiveRestriction.none);
      final plain = InkeApi.detail(_sample('S03-share-live').body, uid: '771067357');
      expect(room.toJson().keys.toSet().difference(plain.toJson().keys.toSet()), {'startedAt', 'restriction'});
      final data = room.data! as InkeRoomData;
      expect(data.liveId, '1790521153165881');
      expect(data.receivedAt, _sample('S04-publish-live').capturedAt);
      expect(data.broadcast!.pullUrl, startsWith('https://live-pull-ws.ikstatic.cn/live/1790521153165881_t.flv?'));
      expect(data.broadcast!.originUrl, startsWith('http://live-pull-zego.ikstatic.cn/inkemain/1790521153165881_0_en'));
    });

    test('S05: the app has no cover, so the website picture stays; the audience and start time are added', () {
      final room = enriched('S05-unlisted-share', 'S05-unlisted-publish', '778920027');
      final legacy = _result(_legacy('S05-unlisted-share')['getRoomDetailForRefresh'])! as Map<String, dynamic>;
      _expectParity(_projection(room), legacy, changed: _audienceKeys);
      expect((room.onlineViewers, room.popularity), ('29', '29'));
      expect(room.startedAt, DateTime.utc(2026, 9, 28, 9, 43, 32));
    });

    test("S06: both titles are the placeholder: the nickname; the cover and audience are the app's", () {
      final room = enriched('S06-placeholder-share', 'S06-placeholder-publish', '778398645');
      expect((room.title, room.cover), ('西宝😘', 'http://img.ikstatic.cn/MTc4ODM2NTQ3NzUzNyM4MDMjanBn.jpg'));
      expect((room.onlineViewers, room.popularity), ('1743', '4457'));
      expect(room.startedAt, DateTime.utc(2026, 9, 28, 12, 35, 38));
      expect(room.restriction, LiveRestriction.none);
    });

    test("the app's title wins when it has one; a newer broadcast id moves the link", () {
      final room = InkeApi.detail(_web(_info()), uid: '100');
      final newer = InkeApi.broadcast(_app(_live(id: '201')..['name'] = 'Late show'), uid: '100')!;
      final merged = InkeApi.withBroadcast(room, newer, receivedAt: DateTime.utc(2026));
      expect(merged.title, 'Late show');
      expect(merged.link, 'https://www.inke.cn/liveroom/index.html?uid=100&id=201');
      expect((merged.data! as InkeRoomData).liveId, '201');
      final placeholder = InkeApi.broadcast(_app(_live()..['name'] = '正在直播中'), uid: '100')!;
      expect(InkeApi.withBroadcast(room, placeholder, receivedAt: DateTime.utc(2026)).title, 'Music');
      final lineless = InkeApi.broadcast(
        _app(_live(url: '', zego: '')),
        uid: '100',
      )!;
      final unknown = InkeApi.withBroadcast(room, lineless, receivedAt: DateTime.utc(2026));
      expect(unknown.restriction, isNull, reason: 'no line: the answer says nothing about a restriction');
      expect((unknown.watching, unknown.audienceMetricType), ('', AudienceMetricType.unknown));
    });

    test('a later refresh of another state drops the start time (M2.1 merge rule)', () {
      final live = enriched('S03-share-live', 'S04-publish-live', '771067357');
      final offline = InkeApi.detail(_sample('S03-share-offline').body, uid: '1');
      final stored = LiveRoom(platform: 'inke', roomId: '771067357').mergeFrom(live);
      expect(stored.startedAt, isNotNull);
      final ended = stored.mergeFrom(LiveRoom(platform: 'inke', roomId: '771067357', liveStatus: offline.liveStatus));
      expect((ended.startedAt, ended.restriction), (null, null));
      expect(ended.cover, live.cover, reason: 'an empty cover keeps the stored one');
    });
  });

  group('streams', () {
    test("S03-share-live: 3.x's quality; its showcase URL is found byte for byte by the fallback", () {
      final legacy = _legacy('S03-share-live');
      final quality = _maps(legacy['getPlayQualites']).single;
      expect(
        (InkeApi.flv.quality, InkeApi.flv.id, InkeApi.flv.sort),
        (quality['quality'], quality['id'], quality['sort']),
      );
      final urls = InkeApi.showcaseUrls(
        _sample('S01-top').body,
        path: 'Live_top_pc',
        uid: '771067357',
        liveId: '1790521153165881',
      );
      expect(urls, quality['getPlayUrls']);
      final recovery = _result(legacy['resolvePlayUrlsForRecoveryRaw'])! as Map<String, dynamic>;
      expect(urls, recovery['urls']);
      expect(InkeApi.flv.selectionId, recovery['appliedQualityData']);
    });

    test('S04-publish-live: the app names the same broadcast and the same Wangsu stream as 3.x (REG-INKE-001)', () {
      final fixture = _sample('S04-publish-live');
      final broadcast = InkeApi.broadcast(fixture.body, uid: '771067357', status: fixture.status)!;
      expect(broadcast.liveId, '1790521153165881', reason: "live_share_pc's liveid");
      final legacy = Uri.parse(
        (_maps(_legacy('S03-share-live')['getPlayQualites']).single['getPlayUrls'] as List).single as String,
      );
      final url = Uri.parse(broadcast.pullUrl!);
      // The same stream: host, path and stream_id as 3.x's.
      expect((url.scheme, url.host, url.path), (legacy.scheme, legacy.host, legacy.path));
      expect(url.queryParameters.keys, legacy.queryParameters.keys);
      _expectParity(
        url.queryParameters,
        legacy.queryParameters,
        // The signature and its expiry: the URL comes from another request
        // (now_publish, not the top list), signed separately.
        changed: {'wsSecret', 'wsABStime'},
        reason: 'pull URL',
      );
      expect(url.queryParameters['wsABStime'], isNot(legacy.queryParameters['wsABStime']));
      final live = (jsonDecode(fixture.body) as Map<String, dynamic>)['live'] as Map<String, dynamic>;
      final zego = live['stream_multi_addr'] as String;
      expect(InkeApi.plainFlv(zego, liveId: broadcast.liveId), isNull, reason: 'HEVC (REG-INKE-002)');
      expect(broadcast.originUrl, zego, reason: 'the original line, as its own quality (14-5)');
      expect(
        (broadcast.title, broadcast.cover, broadcast.online, broadcast.heat),
        ('木子', 'https://img.ikstatic.cn/MTc2NDc0ODEyNjMyOSM3NjYjanBn.jpg', 12, 12),
      );
      expect(broadcast.startedAt, DateTime.utc(2026, 9, 27, 14, 59, 52));
    });

    test('S05: a broadcast outside every showcase: 3.x found nothing, the app gives its URL (REG-INKE-001)', () {
      const uid = '778920027';
      const liveId = '1790588581683219';
      final requests = (_legacy('S05-unlisted-share')['getRoomDetail'] as Map<String, dynamic>)['requests'] as List;
      expect(requests.skip(1).map((url) => Uri.parse(url as String).path), [
        '/web/Live_top_pc',
        '/web/Live_hot_pc',
        '/web/Live_channel_pc',
      ]);
      for (final (name, path) in [
        ('S05-unlisted-top', 'Live_top_pc'),
        ('S05-unlisted-hot', 'Live_hot_pc'),
        ('S05-unlisted-channels', 'Live_channel_pc'),
      ]) {
        expect(
          InkeApi.showcaseUrls(_sample(name).body, path: path, uid: uid, liveId: liveId),
          isEmpty,
          reason: name,
        );
      }
      final broadcast = InkeApi.broadcast(_sample('S05-unlisted-publish').body, uid: uid)!;
      expect(broadcast.liveId, liveId);
      expect(broadcast.pullUrl, startsWith('https://live-pull-ws.ikstatic.cn/live/${liveId}_t.flv?'));
      expect(broadcast.originUrl, startsWith('http://live-pull-zego.ikstatic.cn/inkemain/${liveId}_0_en.flv?'));
    });

    test("S05 showcases: the fallback finds what 3.x's lookup found for every row, in as many requests", () {
      final legacy = _legacy('S05-unlisted-hot');
      const paths = [
        ('S05-unlisted-top', 'Live_top_pc'),
        ('S05-unlisted-hot', 'Live_hot_pc'),
        ('S05-unlisted-channels', 'Live_channel_pc'),
      ];
      final bodies = [for (final (name, _) in paths) _sample(name).body];
      expect(legacy, hasLength(44));
      for (final MapEntry(:key, :value) in legacy.entries) {
        final [uid, liveId] = key.split('/');
        var asked = 0;
        var urls = const <String>[];
        for (final (index, (_, path)) in paths.indexed) {
          asked++;
          urls = InkeApi.showcaseUrls(bodies[index], path: path, uid: uid, liveId: liveId);
          if (urls.isNotEmpty) break;
        }
        final want = value as Map<String, dynamic>;
        expect(urls, want['result'], reason: key);
        expect(asked, (want['requests'] as List).length, reason: key);
      }
    });

    test('S04-publish-offline: no broadcast', () {
      final fixture = _sample('S04-publish-offline');
      expect(InkeApi.broadcast(fixture.body, uid: '1', status: fixture.status), isNull);
    });

    test('the line: media headers, FLV, H.264, the Wangsu line id and the wsABStime lease', () {
      final fixture = _sample('S04-publish-live');
      final url = InkeApi.broadcast(fixture.body, uid: '771067357')!.pullUrl!;
      final resolution = InkeApi.resolution([url], issuedAt: fixture.capturedAt);
      final line = resolution.lines.single;
      expect(line.url, url, reason: 'the signed query as written');
      expect(line.headers, {
        'referer': 'https://www.inke.cn/',
        'origin': 'https://www.inke.cn',
        'user-agent': 'Mozilla/5.0',
      });
      expect(line.headers.keys, isNot(contains('cookie')));
      expect((line.format, line.codec, line.lineId), (StreamFormat.flv, 'avc', 'ws'));
      final expiry = DateTime.fromMillisecondsSinceEpoch(0x6ab96f0b * 1000, isUtc: true);
      expect(line.lease!.expiresAt, expiry);
      expect(line.lease!.refreshAt, expiry.subtract(const Duration(minutes: 10)));
      expect(line.lease!.cutsConnection, isFalse, reason: 'Wangsu checks the signature when a connection opens');
      expect(expiry.difference(fixture.capturedAt), greaterThan(const Duration(minutes: 110)));
      expect(resolution.appliedQualityData, 'flv');
    });

    test('14-5: the original line: Zego, FLV, HEVC, its own line id and lease (a day after the start)', () {
      final fixture = _sample('S04-publish-live');
      final broadcast = InkeApi.broadcast(fixture.body, uid: '771067357')!;
      final resolution = InkeApi.originalResolution(broadcast.originUrl!, issuedAt: fixture.capturedAt);
      final line = resolution.lines.single;
      expect(line.url, broadcast.originUrl, reason: 'as written, http included');
      expect(line.headers, InkeApi.headers);
      expect((line.format, line.codec, line.lineId), (StreamFormat.flv, 'hevc', 'zego'));
      final expiry = DateTime.fromMillisecondsSinceEpoch(0x6aba80e8 * 1000, isUtc: true);
      expect(expiry.difference(broadcast.startedAt!), const Duration(days: 1));
      expect(line.lease!.expiresAt, expiry);
      expect(line.lease!.refreshAt, expiry.subtract(const Duration(minutes: 10)));
      expect(resolution.appliedQualityData, 'origin');
      expect((InkeApi.original.quality, InkeApi.original.id), ('原画', 'origin'));
      expect(InkeApi.original.sort, greaterThan(InkeApi.flv.sort));
    });

    test('14-5: Zego URLs: this broadcast only; HEVC only for codecInfo=8192', () {
      expect(InkeApi.zegoFlv(_zego, liveId: '200'), _zego);
      expect(InkeApi.zegoFlv(_zego.replaceFirst('http:', 'https:'), liveId: '200'), startsWith('https:'));
      for (final url in [
        _zego.replaceAll('ikstatic.cn', 'ikstatic.cn.evil.test'),
        _zego.replaceAll('200_0_en.flv', '201_0_en.flv'),
        _zego.replaceAll('/inkemain/', '/live/'),
        _zego.replaceAll('http:', 'file:'),
        _zego.replaceAll('http://', 'http://name@'),
        _zego.replaceFirst('.cn/', '.cn:8080/'),
        '$_zego#fragment',
        _media,
        '',
      ]) {
        expect(InkeApi.zegoFlv(url, liveId: '200'), isNull, reason: url);
      }
      expect(InkeApi.zegoFlv(_zego, liveId: '../200'), isNull);
      expect(InkeApi.zegoCodec(_zego), 'hevc');
      expect(InkeApi.zegoCodec(_zego.replaceAll('codecInfo=8192', 'codecInfo=7')), isNull);
      expect(InkeApi.zegoCodec(_zego.replaceAll('&codecInfo=8192', '')), isNull);
      expect(InkeApi.zegoLine(_zego.replaceAll('&codecInfo=8192', ''), issuedAt: DateTime.utc(2026)).codec, isNull);
    });

    test('leases: a quarter of a short lifetime; none without one wsABStime or once expired', () {
      final issued = DateTime.fromMillisecondsSinceEpoch(0x70000000 * 1000 - 20 * 60 * 1000, isUtc: true);
      final lease = InkeApi.lease(_media, issuedAt: issued)!;
      expect(lease.expiresAt, DateTime.fromMillisecondsSinceEpoch(0x70000000 * 1000, isUtc: true));
      expect(lease.expiresAt!.difference(lease.refreshAt), const Duration(minutes: 5));
      expect(InkeApi.lease(_media, issuedAt: lease.expiresAt!), isNull);
      for (final url in [
        'https://live-pull-ws.ikstatic.cn/live/200_t.flv?wsSecret=x',
        '$_media&wsABStime=70000001',
        _media.replaceFirst('70000000', 'zz'),
        _media.replaceFirst('70000000', '0'),
      ]) {
        expect(InkeApi.lease(url, issuedAt: issued), isNull, reason: url);
      }
    });

    test("pull URLs: 3.x's check, the signed query as written, no other host, broadcast or protocol", () {
      expect(InkeApi.plainFlv(_media, liveId: '200'), _media);
      expect(InkeApi.plainFlv(_media.replaceFirst('https:', 'http:'), liveId: '200'), startsWith('http:'));
      expect(InkeApi.plainFlv(' $_media ', liveId: '200'), _media);
      for (final url in [
        _media.replaceAll('ikstatic.cn', 'ikstatic.cn.evil.test'),
        _media.replaceAll('200_t', '201_t'),
        _media.replaceAll('200_t', '200_0_en'),
        _media.replaceAll('https:', 'file:'),
        _media.replaceAll('https://', 'https://name@'),
        _media.replaceFirst('.cn/', '.cn:8443/'),
        '$_media#fragment',
        'http://live-pull-zego.ikstatic.cn/inkemain/200_0_en.flv?codecInfo=8192',
        '',
      ]) {
        expect(InkeApi.plainFlv(url, liveId: '200'), isNull, reason: url);
      }
      expect(InkeApi.plainFlv(_media, liveId: '../200'), isNull);
      expect(InkeApi.plainFlv(42, liveId: '200'), isNull);
    });

    test('now_publish: the anchor asked for, status 1 is live, anything else no broadcast', () {
      expect(InkeApi.broadcast(_app(_live()), uid: '100')!.pullUrl, _media);
      expect(InkeApi.broadcast(_app(_live()), uid: '100')!.originUrl, _zego);
      expect(InkeApi.broadcast(_app(_live(creator: '100')), uid: '100')!.liveId, '200');
      expect(InkeApi.broadcast(_app(_live(status: 0)), uid: '100'), isNull);
      expect(InkeApi.broadcast(_app(_live(status: '1')), uid: '100'), isNotNull);
      final zegoOnly = InkeApi.broadcast(_app(_live(url: '')), uid: '100')!;
      expect((zegoOnly.liveId, zegoOnly.pullUrl, zegoOnly.originUrl), ('200', null, _zego));
      expect(zegoOnly.hasLine, isTrue);
      final lineless = InkeApi.broadcast(
        _app(_live(url: '', zego: 'x')),
        uid: '100',
      )!;
      expect((lineless.pullUrl, lineless.originUrl, lineless.hasLine), (null, null, false));
      expect(() => InkeApi.broadcast(_app(_live(creator: 101)), uid: '100'), throwsA(isA<ApiChanged>()));
      expect(() => InkeApi.broadcast(_app(_live(id: 'x')), uid: '100'), throwsA(isA<ApiChanged>()));
      expect(() => InkeApi.broadcast(_app('live'), uid: '100'), throwsA(isA<ApiChanged>()));
      expect(() => InkeApi.broadcast(_app(null, code: 499), uid: '100'), throwsA(isA<ApiChanged>()));
      expect(() => InkeApi.broadcast('{"live":null}', uid: '100'), throwsA(isA<ApiChanged>()));
    });

    test('the hot lists are a map of lists; each showcase only by its own shape; bad rows are skipped', () {
      final hot = _web({
        'list': {
          'recommend': <Object?>[],
          'hot': [_row(uid: 'x'), 'row', _row()],
          'broken': 'list',
        },
      });
      expect(InkeApi.showcaseUrls(hot, path: 'Live_hot_pc', uid: '100', liveId: '200'), [_media]);
      expect(
        () => InkeApi.showcaseUrls(hot, path: 'Live_top_pc', uid: '100', liveId: '200'),
        throwsA(isA<ApiChanged>()),
      );
      final channels = _web({
        'list': [_group()],
      });
      expect(InkeApi.showcaseUrls(channels, path: 'Live_channel_pc', uid: '100', liveId: '200'), [_media]);
      expect(InkeApi.showcaseUrls(channels, path: 'Live_channel_pc', uid: '100', liveId: '199'), isEmpty);
      final twice = _web({
        'list': [_row(), _row(), _row(uid: 101)],
      });
      expect(InkeApi.showcaseUrls(twice, path: 'Live_top_pc', uid: '100', liveId: '200'), [_media]);
    });
  });

  group('envelope', () {
    test('HTTP failures are typed and never look offline (3.x)', () {
      for (final (status, matcher) in [
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (500, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
        (204, isA<NetworkFailure>()),
      ]) {
        expect(
          () => InkeApi.detail('sensitive response must not appear', uid: '100', status: status),
          throwsA(matcher),
          reason: '$status',
        );
        expect(
          () => InkeApi.broadcast('x', uid: '100', status: status),
          throwsA(matcher),
          reason: '$status',
        );
        expect(() => InkeApi.hotPage('x', status: status), throwsA(matcher), reason: '$status');
      }
    });

    test('bodies that are not JSON objects, without a code or data, or over 1 MiB are ApiChanged (3.x)', () {
      for (final body in [
        'not json',
        '[]',
        '{"data":{}}',
        '{"error_code":"x","data":{}}',
        '{"error_code":0,"data":[]}',
        '{"error_code":0}',
        'x' * (InkeApi.responseLimit + 1),
        jsonEncode({
          'error_code': 0,
          'data': {'large': List.filled(400000, '映').join()},
        }),
      ]) {
        expect(
          () => InkeApi.detail(body, uid: '100'),
          throwsA(isA<ApiChanged>()),
          reason: body.length > 40 ? body.substring(0, 40) : body,
        );
      }
      expect(InkeApi.webData('{"error_code":"0","data":{"a":1}}', what: 'x'), {'a': 1});
    });
  });

  group('links', () {
    test('web room pages: the uid, whatever broadcast id they carry (3.x)', () {
      for (final host in ['inke.cn', 'www.inke.cn', 'inke.com', 'www.inke.com', 'WWW.INKE.CN']) {
        expect(
          InkeApi.roomIdFromUri(Uri.parse('https://$host/liveroom/index.html?uid=100&id=999')),
          '100',
          reason: host,
        );
      }
      expect(InkeApi.roomIdFromUri(Uri.parse('http://www.inke.cn:80/liveroom/index.html?uid=100')), '100');
      for (final url in [
        'https://www.inke.cn.evil.test/liveroom/index.html?uid=100',
        'https://name@www.inke.cn/liveroom/index.html?uid=100',
        'https://www.inke.cn:8787/liveroom/index.html?uid=100',
        'https://www.inke.cn/?uid=100',
        'https://www.inke.cn/liveroom/index.html?uid=100&uid=101',
        'https://www.inke.cn/liveroom/index.html?uid=0',
        'https://www.inke.cn/liveroom/index.html?uid=0100',
        'https://www.inke.cn/liveroom/index.html?id=100',
        'file:///liveroom/index.html?uid=100',
        'https://m.inke.cn/liveroom/index.html?uid=100',
      ]) {
        expect(InkeApi.roomIdFromUri(Uri.parse(url)), isNull, reason: url);
      }
      expect(InkeApi.roomIdFromUri(null), isNull);
    });

    test("app share pages (the app's share_addr, which 3.x did not know)", () {
      final live =
          (jsonDecode(_sample('S04-publish-live').body) as Map<String, dynamic>)['live'] as Map<String, dynamic>;
      final share = live['share_addr'] as String;
      expect(share, startsWith('https://mlive2.inke.cn/app/'));
      expect(InkeApi.roomIdFromUri(Uri.parse(share)), '771067357');
      expect(InkeApi.roomIdFromUri(Uri.parse('https://mlive.inke.cn/app/hot/live?uid=100')), '100');
      for (final url in [
        'https://mlive2.inke.cn/web/hot/live?uid=100',
        'https://mlive2.inke.cn.evil.test/app/hot/live?uid=100',
        'https://mliveX.inke.cn/app/hot/live?uid=100',
        'https://mlive2.inke.cn/app/hot/live?liveid=100',
        'https://mlive2.inke.cn:8443/app/hot/live?uid=100',
      ]) {
        expect(InkeApi.roomIdFromUri(Uri.parse(url)), isNull, reason: url);
      }
    });

    test('opening in the browser needs this uid and one numeric broadcast id, else the home page (3.x)', () {
      const valid = 'https://www.inke.cn/liveroom/index.html?uid=100&id=199';
      expect(InkeApi.externalRoomUrl(LiveRoom(platform: 'inke', roomId: '100', link: valid)), valid);
      expect(
        InkeApi.externalRoomUrl(LiveRoom(platform: 'inke', link: 'https://example.test/?id=199')),
        'https://www.inke.cn/',
      );
      for (final link in <String?>[
        null,
        '',
        '  ',
        valid.split('&id=').first,
        '$valid&id=200',
        valid.replaceFirst('uid=100', 'uid=101'),
        valid.replaceFirst('id=199', 'id=abc'),
        valid.replaceFirst('inke.cn', 'inke.cn.evil.test'),
        'https://www.inke.cn/liveroom/index.html?uid=100&id=%FF',
        'https://mlive2.inke.cn/app/hot/live?uid=100&liveid=199',
      ]) {
        expect(
          InkeApi.externalRoomUrl(LiveRoom(platform: 'inke', roomId: '100', link: link)),
          'https://www.inke.cn/',
          reason: '$link',
        );
      }
      expect(InkeApi.externalRoomUrl(LiveRoom(platform: 'other', roomId: '100', link: valid)), 'https://www.inke.cn/');
    });
  });
}
