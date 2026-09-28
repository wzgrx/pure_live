// Six Rooms parsing against the recorded samples, compared field by field
// with 3.x's frozen output (expected.json, written by
// fixtures/sixroom/legacy_expected.dart from 3.x's SixRoomApi, SixRoomLink
// and SixRoomSite). Every intended difference is listed with its reason;
// everything else must match. The synthetic cases are the harness's changed
// copies of the samples, and 3.x's own sixroom_site_test.dart fixtures.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('sixroom', name);

const _live = '8838';
const _liveUid = '56182128';
const _offline = '191111';
const _offlineUid = '63213382';

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

/// The `result` of a traced legacy call.
Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

/// Asserts that [room] (a `toJson` plus `link`) equals 3.x's [legacy]
/// projection on every key 3.x wrote, except [changed] (intended
/// differences) and `data` (3.x's `SixRoomRoom`, compared on its own). 3.x
/// wrote null where the immutable model writes ''.
void _expectParity(LiveRoom room, Object? legacy, {Set<String> changed = const {}, String reason = ''}) {
  final actual = {...room.toJson(), 'link': room.link};
  for (final MapEntry(:key, :value) in (legacy! as Map<String, dynamic>).entries) {
    if (changed.contains(key) || key == 'data') continue;
    expect(actual[key] ?? '', value ?? '', reason: '$reason $key');
  }
}

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {String reason = ''}) {
  final expected = _maps(legacy);
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(room, expected[index], reason: '$reason[$index]');
  }
}

/// Asserts that [room] equals 3.x's `SixRoomRoom` projection [legacy]: the
/// same fields, and the one variant as [SixRoomRoom.stream].
void _expectRoom(SixRoomRoom room, Object? legacy, {String reason = ''}) {
  final expected = legacy! as Map<String, dynamic>;
  final actual = <String, Object?>{
    'roomId': room.roomId,
    'userId': room.userId,
    'liveId': room.liveId,
    'nick': room.nick,
    'title': room.title,
    'avatar': room.avatar,
    'cover': room.cover,
    'category': room.category,
    'popularity': room.popularity,
    'followers': room.followers,
    'state': room.state.name,
    'variants': [
      if (room.stream case final stream?)
        {
          'id': SixRoomApi.qualityId,
          'protocol': 'flv',
          'resolution': stream.resolution,
          'bitrate': stream.bitrate,
          'urls': ['${stream.url}'],
        },
    ],
  };
  for (final MapEntry(:key, :value) in expected.entries) {
    expect(actual[key], value, reason: '$reason ${expected['roomId']} $key');
  }
}

void _expectRoomList(List<SixRoomRoom> rooms, Object? legacy, {String reason = ''}) {
  final expected = _maps(legacy);
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectRoom(room, expected[index], reason: '$reason[$index]');
  }
}

/// [legacy] is 3.x's failure [kind] (`SixRoomException.<kind>`).
void _expectLegacyFailure(Object? legacy, String kind, {String reason = ''}) =>
    expect(legacy, containsPair('throws', 'SixRoomException.$kind'), reason: reason);

Matcher _throwsA<T>() => throwsA(isA<T>());

/// The homepage's rows (`typeList`), decoded.
List<Object?> _homeRows() {
  final literal = RegExp(r'"typeList":("(?:[^"\\]|\\.)*")').firstMatch(_sample('S04-home').body)!.group(1)!;
  return jsonDecode(jsonDecode(literal) as String) as List<Object?>;
}

/// A homepage whose `typeList` is [rows] (the harness's `_withRows`).
String _withRows(List<Object?> rows) =>
    '<html><script>window.__SMARTY_ALL_VARIABLES__ = ${jsonEncode({'typeList': jsonEncode(rows)})};</script></html>';

Map<String, dynamic> _inroom([String sample = 'S05-inroom-live']) =>
    jsonDecode(_sample(sample).body) as Map<String, dynamic>;

Map<String, dynamic> _content(Map<String, dynamic> root) => root['content'] as Map<String, dynamic>;

Map<String, dynamic> _section(Map<String, dynamic> root, String name) => _content(root)[name] as Map<String, dynamic>;

/// The live inroom answer with [edit] applied, as text.
String _changed(void Function(Map<String, dynamic> root) edit) {
  final root = _inroom();
  edit(root);
  return jsonEncode(root);
}

SixRoomRoom _parseRoom(String body, {String roomId = _live, String userId = _liveUid, bool media = true}) =>
    SixRoomApi.room(body, roomId: roomId, userId: userId, media: media);

// 3.x's own fixtures (sixroom_site_test.dart).
final String _legacyDirectoryHtml = _withRows([
  {
    'rid': '8838',
    'uid': '56182128',
    'liveid': '222415076',
    'username': '唯一主播',
    'livetitle': '今晚唱歌',
    'count': '23104',
    'anchor_area': '歌区',
    'picuser': 'https://vi1.6rooms.com/live/avatar-1.jpg',
    'pospic': 'https://vi0.6rooms.com/live/cover-1.jpg',
  },
  {
    'rid': '1890',
    'uid': '31648937',
    'liveid': '222415100',
    'username': '小荷叶~加油',
    'userMood': '努力直播',
    'count': 3749,
    'anchor_area': '歌区',
    'picuser': 'https://vi0.6rooms.com/live/avatar-2.jpg',
    'pic': 'https://vi0.6rooms.com/live/cover-2.jpg',
  },
  {
    'rid': '578888',
    'uid': '82340792',
    'liveid': '222414543',
    'username': '户外主播',
    'livetitle': '清明上河图',
    'count': '15802',
    'anchor_area': '脱口秀',
    'picuser': 'https://vi2.6rooms.com/live/avatar-3.jpg',
    'pospic': 'https://vi1.6rooms.com/live/cover-3.jpg',
  },
]);

const String _legacySearchHtml = '''
<html><body><div class="page-search page-search-user"><ul class="search-user">
<li data-uid="31648937"><a class="user-box" href="/profile/1890"><div class="pic"><img data-src="https://vi0.6rooms.com/live/a.jpg"></div><div class="alias">小荷叶~加油</div></a></li>
<li data-uid="98073893"><a class="user-box" href="/profile/243126861"><div class="pic"><img data-src="https://vi1.6rooms.com/live/b.jpg"></div><div class="alias">小荷叶～</div></a></li>
</ul></div></body></html>
''';

const String _legacyRoomHtml = '''
<html><head><link rel="canonical" href="https://v.6.cn/8838"></head><body><script>
var room = {rid: '56182128', roomid: '8838', liveid: '222415076'};
</script></body></html>
''';

final String _legacyLiveRoomJson = jsonEncode({
  'flag': '001',
  'content': {
    'roominfo': {
      'id': '56182128',
      'rid': '8838',
      'alias': '唯一主播',
      'headPicUrl': 'https://vi1.6rooms.com/live/avatar.jpg',
      'anchor_area': '歌区',
    },
    'liveinfo': {
      'id': '222415076',
      'title': '今晚唱歌',
      'flvtitle': 'v56182128-222415076',
      'spredPic': 'https://vi0.6rooms.com/live/cover.jpg',
      'content': {
        '1': {
          'streamInfo': {
            'v56182128-222415076': {'resolution': '1024x768', 'videoBitrate': 2653},
          },
        },
      },
    },
    'roomParamInfo': {'uid': '56182128', 'fans_num': 425585},
    'isPriveRoom': 0,
    'blackScreenInfo': {'msg': ''},
  },
});

final String _legacyOfflineRoomJson = jsonEncode({
  'flag': '001',
  'content': {
    'roominfo': {'id': '98073893', 'rid': '243126861', 'alias': '小荷叶～', 'anchor_area': ''},
    'liveinfo': {'id': '', 'title': '', 'flvtitle': ''},
    'roomParamInfo': {'uid': '98073893', 'fans_num': 36},
    'isPriveRoom': 0,
    'blackScreenInfo': {'msg': ''},
  },
});

void main() {
  group('catalog and links', () {
    test("3.x's one category and six areas", () {
      final legacy = _legacy('S04-home');
      final categories = SixRoomApi.categories();
      final expected = _maps(_result(legacy['getCategores'])).single;
      expect((categories.single.id, categories.single.name), (expected['id'], expected['name']));
      expect(
        [for (final area in categories.single.children) area.toJson()],
        [
          for (final area in _maps(expected['children'])) {...area, 'areaPic': '', 'shortName': ''},
        ],
        reason: "3.x wrote null for areaPic and shortName; the model writes ''",
      );
      expect([
        for (final area in SixRoomApi.categories(limit: 3).single.children) area.areaId,
      ], _result(legacy['getCategores(pageSize: 3)']));
      expect(legacy['name'], SixRoomApi.siteName);
      expect({
        for (final MapEntry(:key, :value) in (legacy['SixRoomApi.mediaHeaders'] as Map<String, dynamic>).entries)
          key.toLowerCase(): value,
      }, SixRoomApi.mediaHeaders(_live));
      expect(SixRoomApi.areaIdOf(null), 'all');
      expect(
        SixRoomApi.areaIdOf(const LiveArea(platform: 'sixroom', areaType: 'official', areaId: ' song ')),
        'song',
        reason: '3.x trimmed the area id',
      );
      for (final area in const [
        LiveArea(platform: 'bilibili', areaType: 'official', areaId: 'song'),
        LiveArea(platform: 'sixroom', areaType: 'u0', areaId: 'song'),
        LiveArea(platform: 'sixroom', areaType: 'official', areaId: 'u10'),
      ]) {
        expect(SixRoomApi.areaIdOf(area), isNull, reason: '$area');
      }
    });

    test("links match 3.x's SixRoomLink", () {
      final legacy = _legacy('S04-home')['SixRoomLink.parseRoomId'] as Map<String, dynamic>;
      expect(legacy, hasLength(38));
      for (final MapEntry(:key, :value) in legacy.entries) {
        if (key == 'https://v.6.cn/%FF') {
          // 3.x threw decoding the path; it is no room.
          expect(value, containsPair('throws', 'FormatException'));
          expect(SixRoomApi.roomIdOf(key), isNull);
          continue;
        }
        expect(SixRoomApi.roomIdOf(key), value, reason: key);
      }
      final watch = _legacy('S04-home')['SixRoomLink.watchUrl'] as Map<String, dynamic>;
      for (final raw in [_live, ' $_live ', 'https://m.6.cn/profile/$_live']) {
        expect(SixRoomApi.link(SixRoomApi.roomIdOf(raw)!), watch[raw], reason: raw);
      }
      expect(watch['1'], containsPair('throws', 'FormatException'));
      expect(SixRoomApi.roomIdOf('1'), isNull);
    });
  });

  group('homepage', () {
    test("every room matches 3.x's parse, and every card 3.x's page", () {
      final legacy = _legacy('S04-home');
      final rooms = SixRoomApi.directory(_sample('S04-home').body);
      _expectRoomList(rooms, legacy['parseDirectoryHtml']);
      expect(rooms, hasLength(443));
      final pages = legacy['getDirectoryPage(all)'] as Map<String, dynamic>;
      final cards = [for (final traced in pages.values) ...(_result(traced)! as Map<String, dynamic>)['rooms'] as List];
      _expectRooms([for (final room in rooms) SixRoomApi.liveRoom(room)], cards);
      for (final room in rooms) {
        expect(SixRoomApi.liveRoom(room).httpHeaders, SixRoomApi.mediaHeaders(room.roomId));
      }
    });

    test("areas filter the homepage like 3.x's pages", () {
      final rooms = SixRoomApi.directory(_sample('S04-home').body);
      final legacy = _legacy('S04-home')['getDirectoryPage(category)'] as Map<String, dynamic>;
      for (final MapEntry(key: areaId, value: pages) in legacy.entries) {
        final ids = [
          for (final traced in (pages as Map<String, dynamic>).values)
            ...((_result(traced)! as Map<String, dynamic>)['rooms'] as List).cast<String>(),
        ];
        expect([for (final room in SixRoomApi.inArea(rooms, areaId)) room.roomId], ids, reason: areaId);
      }
    });

    test("changed homepages match 3.x's parse", () {
      final legacy = _legacy('S04-home')['parseDirectoryHtml(variants)'] as Map<String, dynamic>;
      final rows = _homeRows();
      final first = Map<String, Object?>.from(rows.first! as Map);
      final variants = <String, List<Object?>>{
        'braces in strings': [
          {...first, 'livetitle': r'a } { "b" \ c'},
        ],
        'duplicate rid': [
          first,
          {...first, 'username': 'second'},
        ],
        'bad rid': [
          {...first, 'rid': '0123'},
          {...first, 'rid': 8838},
          {...first, 'rid': '1'},
        ],
        'numbers': [
          {...first, 'rid': 8838, 'uid': 56182128, 'liveid': 222, 'count': 23104},
        ],
        'lid': [
          {...(Map.of(first)..remove('liveid')), 'lid': '333'},
        ],
        'titles': [
          {...first, 'rid': '1001', 'livetitle': '  a   title ', 'userMood': 'mood'},
          {...first, 'rid': '1002', 'livetitle': '', 'userMood': 'mood'},
          {...first, 'rid': '1003', 'livetitle': '', 'userMood': ''},
          {...first, 'rid': '1004', 'livetitle': '', 'userMood': '', 'username': ''},
          {...first, 'rid': '1005', 'livetitle': null, 'userMood': null, 'username': null},
        ],
        'images': [
          {...first, 'rid': '1001', 'pospic': '', 'pic': 'https://vi0.6rooms.com/live/p.jpg'},
          {...first, 'rid': '1002', 'pospic': '', 'pic': '', 'pospic_sp': 'https://vi2.6rooms.com/live/sp.jpg'},
          {
            ...first,
            'rid': '1003',
            'pospic': 'http://vi0.6rooms.com/live/h.jpg',
            'picuser': '//vi1.6rooms.com/live/a.jpg',
          },
          {...first, 'rid': '1004', 'pospic': 'https://example.com/x.jpg', 'pic': '', 'pospic_sp': '', 'picuser': ''},
          {...first, 'rid': '1005', 'pospic': 'https://vi0.xiu123.cn/x.jpg', 'picuser': 'https://6.cn/a.jpg'},
          {
            ...first,
            'rid': '1006',
            'pospic': 'https://vi0.6rooms.com:8443/x.jpg',
            'picuser': 'https://u@vi1.6rooms.com/a',
          },
          {...first, 'rid': '1007', 'pospic': 'https://vi0.6rooms.com/x.jpg#f', 'picuser': 'ftp://vi1.6rooms.com/a'},
          {...first, 'rid': '1008', 'pospic': 'https://evil6rooms.com/x.jpg', 'picuser': 'https://vi1.6ROOMS.com/a'},
        ],
        'count': [
          {...first, 'rid': '1001', 'count': '1,234'},
          {...first, 'rid': '1002', 'count': -5},
          {...first, 'rid': '1003', 'count': '-5'},
          {...first, 'rid': '1004', 'count': 3.7},
          {...first, 'rid': '1005', 'count': 'x'},
          {...first, 'rid': '1006', 'count': null},
          {...first, 'rid': '1007', 'count': ''},
        ],
        'area': [
          {...first, 'rid': '1001', 'anchor_area': '  舞区 '},
          {...first, 'rid': '1002', 'anchor_area': null},
        ],
        'not a map': [1, 'x', null, first],
      };
      for (final MapEntry(:key, :value) in variants.entries) {
        _expectRoomList(SixRoomApi.directory(_withRows(value)), legacy[key], reason: key);
      }
      // 3.x's `schema`: no room at all, no marker, no typeList, not JSON,
      // unterminated.
      for (final (key, body) in [
        ('empty', _withRows(const [])),
        (
          'bad uid',
          _withRows([
            {...first, 'uid': ''},
            {...first, 'rid': '8839', 'uid': '1'},
          ]),
        ),
        ('no marker', '<html></html>'),
        ('typeList missing', '<script>window.__SMARTY_ALL_VARIABLES__ = {"x":1};</script>'),
        ('typeList not JSON', '<script>window.__SMARTY_ALL_VARIABLES__ = {"typeList":"[x"};</script>'),
        ('unterminated', '<script>window.__SMARTY_ALL_VARIABLES__ = {"typeList":"[]"'),
      ]) {
        _expectLegacyFailure(legacy[key], 'schema', reason: key);
        expect(() => SixRoomApi.directory(body), _throwsA<ApiChanged>(), reason: key);
      }
      expect(
        SixRoomApi.directory(
          '<script>window.__SMARTY_ALL_VARIABLES__ = ${jsonEncode({'typeList': rows.take(2).toList()})};</script>',
        ),
        hasLength(legacy['typeList as a list']! as int),
      );
    });

    test("3.x's own lobby fixture", () {
      final rooms = SixRoomApi.directory(_legacyDirectoryHtml);
      expect(rooms.map((room) => room.roomId), ['8838', '1890', '578888']);
      expect(rooms.first.userId, '56182128');
      expect(rooms.first.popularity, 23104);
      expect(rooms.first.category, '歌区');
      expect(rooms.first.state, SixRoomState.live);
      expect(rooms[1].title, '努力直播');
      expect(rooms.last.category, '脱口秀');
      final card = SixRoomApi.liveRoom(rooms.first);
      expect(card.audienceMetricType, AudienceMetricType.popularity);
      expect((card.popularity, card.watching, card.followers), ('23104', '23104', ''));
      expect([for (final room in SixRoomApi.inArea(rooms, 'song')) room.roomId], ['8838', '1890']);
    });
  });

  group('search', () {
    test("search pages match 3.x's parse", () {
      final legacy = _legacy('S02-search');
      final rooms = SixRoomApi.search(_sample('S02-search').body);
      _expectRoomList(rooms, legacy['parseSearchHtml']);
      expect(rooms, hasLength(35));
      _expectRooms([
        for (final room in rooms.take(3)) SixRoomApi.liveRoom(room),
      ], _result((legacy['searchRooms'] as Map<String, dynamic>)['"诺" page 1 size 3']));
      expect(SixRoomApi.search(_sample('S02-search-empty').body), isEmpty);
      expect(_legacy('S02-search-empty')['parseSearchHtml'], isEmpty);
      final variants = legacy['parseSearchHtml(variants)'] as Map<String, dynamic>;
      _expectRoomList(
        SixRoomApi.search('''
<div class="page-search-user"><ul class="search-user">
<li data-uid="31648937"><a class="user-box" href="/profile/1890"><div class="pic"><img src="//vi0.6rooms.com/live/a.jpg"></div><div class="alias"> 小荷叶   加油 </div></a></li>
<li data-uid="31648937"><a class="user-box" href="/1890"><div class="alias">again</div></a></li>
<li data-uid="1"><a class="user-box" href="/1891"><div class="alias">bad uid</div></a></li>
<li data-uid="31648938"><a class="user-box" href="/search.php"><div class="alias">bad link</div></a></li>
<li data-uid="31648939"><a class="user-box" href="https://m.6.cn/1892"><div class="alias"></div></a></li>
<li data-uid="31648940"><a class="user-box" href="https://example.com/1893"><div class="alias">other host</div></a></li>
<li data-uid="31648941"><a class="other" href="/1894"><div class="alias">no user-box</div></a></li>
<li><a class="user-box" href="/1895"><div class="alias">no uid</div></a></li>
</ul><ul class="other"><li data-uid="31648942"><a class="user-box" href="/1896"></a></li></ul></div>
'''),
        variants['duplicate and invalid'],
      );
      // 3.x's `schema` without the result block, `access` on a prompt page.
      _expectLegacyFailure(variants['no result block'], 'schema');
      expect(() => SixRoomApi.search('<html><body><div class="x"></div></body></html>'), _throwsA<ApiChanged>());
      _expectLegacyFailure(variants['remind page'], 'access');
      expect(
        () => SixRoomApi.search('<div class="remind"><div class="rcontent">x</div></div>'),
        throwsA(isA<RiskControl>().having((error) => error.detail, 'detail', contains('x'))),
      );
    });

    test('a keyword over 15 characters is no result (3.x: access)', () {
      // 6.cn answers "输入内容过长" (S05-search-long, 20 characters); 3.x let
      // keywords of up to 80 through and failed on the prompt page.
      _expectLegacyFailure(_legacy('S05-search-long')['parseSearchHtml'], 'access');
      expect(SixRoomApi.search(_sample('S05-search-long').body), isEmpty);
    });

    test("3.x's own search fixture", () {
      final rooms = SixRoomApi.search(_legacySearchHtml);
      expect(rooms, hasLength(2));
      expect((rooms.first.roomId, rooms.first.userId, rooms.first.nick), ('1890', '31648937', '小荷叶~加油'));
      expect(rooms.first.state, SixRoomState.unknown);
      expect(rooms.last.roomId, '243126861');
      expect(rooms.last.avatar, startsWith('https://vi1.6rooms.com/'));
      final card = SixRoomApi.liveRoom(rooms.first);
      expect((card.liveStatus, card.area, card.cover), (LiveStatus.unknown, SixRoomApi.siteName, ''));
      expect(card.avatar, 'https://vi0.6rooms.com/live/a.jpg');
    });
  });

  group('room page', () {
    test("the user id next to the room's roomid, which 3.x no longer found (root cause of its broken rooms)", () {
      // 3.x wanted `roomid: '<n>'` quoted; the page writes `roomid: 8838,`
      // (sample S05-page-live), so every room without a remembered user id
      // failed with `schema`.
      for (final (sample, roomId, userId) in [
        ('S05-page-live', _live, _liveUid),
        ('S05-page-offline', _offline, _offlineUid),
        ('S03-room-live', '16066', '53007895'),
        ('S03-room-offline', _offline, _offlineUid),
      ]) {
        _expectLegacyFailure(_legacy(sample)['recorded'], 'schema', reason: sample);
        expect(SixRoomApi.userIdOf(_sample(sample).body, roomId: roomId), userId, reason: sample);
      }
    });

    test("changed pages match 3.x's lookup", () {
      final legacy = _legacy('S05-page-live');
      final live = _sample('S05-page-live').body;
      final quoted = live.replaceFirst('roomid: $_live,', "roomid: '$_live',");
      for (final (key, body, roomId) in [
        ('roomid quoted (3.x format)', quoted, _live),
        ('roomid quoted, double quotes', live.replaceFirst('roomid: $_live,', 'roomid: "$_live",'), _live),
        ('roomid quoted, link asked', quoted, 'https://v.6.cn/$_live'),
        ("3.x's test page", _legacyRoomHtml, _live),
      ]) {
        expect(SixRoomApi.userIdOf(body, roomId: roomId), legacy[key], reason: key);
      }
      expect(
        SixRoomApi.userIdOf(
          _sample('S05-page-offline').body.replaceFirst('roomid: $_offline,', "roomid: '$_offline',"),
          roomId: _offline,
        ),
        _legacy('S05-page-offline')['roomid quoted (3.x format)'],
      );
      // 3.x's `identity` and `schema`: the page is not the room's.
      for (final (key, body, roomId) in [
        ('roomid quoted, other room asked', quoted, '8839'),
        (
          'roomid quoted, canonical of another room',
          quoted.replaceFirst('href="https://v.6.cn/$_live"', 'href="https://v.6.cn/8839"'),
          _live,
        ),
        ('roomid quoted, no canonical', quoted.replaceFirst('rel="canonical"', 'rel="x"'), _live),
        ('roomid quoted, rid of another room', quoted.replaceFirst("roomid: '$_live'", "roomid: '8839'"), _live),
        ('no rid', quoted.replaceFirst("rid: '$_liveUid'", "xid: '$_liveUid'"), _live),
        ('unquoted roomid with more digits', live.replaceFirst('roomid: $_live,', 'roomid: ${_live}9,'), _live),
      ]) {
        expect(legacy[key], containsPair('throws', anyOf('SixRoomException.identity', 'SixRoomException.schema')));
        expect(() => SixRoomApi.userIdOf(body, roomId: roomId), _throwsA<ApiChanged>(), reason: key);
      }
      // 3.x's `missing`: a prompt page or a short page.
      for (final (key, body) in [
        ('remind page', _sample('S05-search-long').body),
        ('short page', '<html><head></head><body>x</body></html>'),
      ]) {
        _expectLegacyFailure(legacy[key], 'missing', reason: key);
        expect(() => SixRoomApi.userIdOf(body, roomId: _live), _throwsA<NotFound>(), reason: key);
      }
      // A room id that is none is the caller's error (3.x: identity).
      _expectLegacyFailure(legacy['roomid quoted, bad id asked'], 'identity');
      expect(() => SixRoomApi.userIdOf(quoted, roomId: 'abc'), throwsArgumentError);
      // The 404 page read as an answer: another room's page (3.x: identity);
      // its status makes it NotFound.
      _expectLegacyFailure(_legacy('S03-room-notfound')['parseRoomUserIdHtml'], 'identity');
      final notFound = _sample('S03-room-notfound');
      expect(() => SixRoomApi.userIdOf(notFound.body, roomId: '99999999999'), _throwsA<ApiChanged>());
      expect(
        () => SixRoomApi.userIdOf(notFound.body, roomId: '99999999999', status: notFound.status),
        _throwsA<NotFound>(),
      );
    });

    test("3.x's own room page", () {
      expect(SixRoomApi.userIdOf(_legacyRoomHtml, roomId: '8838'), '56182128');
    });
  });

  group('inroom', () {
    test("the recorded answers match 3.x's parse", () {
      final legacy = _legacy('S05-inroom-live')['parseRoomJson'] as Map<String, dynamic>;
      _expectRoom(_parseRoom(_sample('S05-inroom-live').body), legacy['recorded']);
      _expectRoom(_parseRoom(_sample('S05-inroom-live').body, media: false), legacy['recorded (includeMedia false)']);
      _expectRoom(_parseRoom(_sample('S05-inroom-live').body, roomId: 'https://v.6.cn/$_live'), legacy['link asked']);
      final offline = _legacy('S05-inroom-offline')['parseRoomJson'] as Map<String, dynamic>;
      _expectRoom(
        _parseRoom(_sample('S05-inroom-offline').body, roomId: _offline, userId: _offlineUid),
        offline['recorded'],
      );
      final live = _parseRoom(_sample('S05-inroom-live').body);
      expect(live.stream!.codec, 'avc', reason: 'streamInfo.videoCodec AVC (3.x did not read it)');
      expect(live.ownerAvatar, startsWith('https://vi1.6rooms.com/'), reason: 'roominfo.uoption.picuser');
      expect(live.avatar, isEmpty, reason: '3.x looked for headPicUrl and picuser, which the answer lacks');
    });

    test("changed answers match 3.x's parse", () {
      final legacy = _legacy('S05-inroom-live')['parseRoomJson'] as Map<String, dynamic>;
      final liveInfo = _section(_inroom(), 'liveinfo');
      final flvTitle = liveInfo['flvtitle'] as String;
      final liveId = liveInfo['id'] as String;
      final variants = <String, String>{
        'roominfo without id': _changed((root) => _section(root, 'roominfo').remove('id')),
        'private (1)': _changed((root) => _content(root)['isPriveRoom'] = 1),
        'private ("1")': _changed((root) => _content(root)['isPriveRoom'] = '1'),
        'private (true)': _changed((root) => _content(root)['isPriveRoom'] = true),
        'private ("0")': _changed((root) => _content(root)['isPriveRoom'] = '0'),
        'black screen': _changed((root) => _content(root)['blackScreenInfo'] = {'msg': ' 黑屏 ', 'endtm': 1}),
        'black screen not a map': _changed((root) => _content(root)['blackScreenInfo'] = 'x'),
        'no live id': _changed((root) => _section(root, 'liveinfo').remove('id')),
        'no stream name': _changed((root) => _section(root, 'liveinfo')['flvtitle'] = ''),
        'stream name -many': _changed((root) => _section(root, 'liveinfo')['flvtitle'] = '$flvTitle-many'),
        'no stream info': _changed((root) => _section(root, 'liveinfo').remove('content')),
        'bitrate instead of videoBitrate': _changed((root) {
          final lanes = _section(root, 'liveinfo')['content'] as Map<String, dynamic>;
          final info =
              ((lanes['1'] as Map<String, dynamic>)['streamInfo'] as Map<String, dynamic>)[flvTitle]
                  as Map<String, dynamic>;
          info['bitrate'] = info.remove('videoBitrate');
        }),
        'stream info in another lane': _changed((root) {
          final lanes = _section(root, 'liveinfo')['content'] as Map<String, dynamic>;
          lanes['2'] = lanes.remove('1');
        }),
        'title': _changed((root) => _section(root, 'liveinfo')['title'] = '  今晚   唱歌 '),
        'userMood': _changed((root) => _section(root, 'roominfo')['userMood'] = '签名'),
        'no alias': _changed((root) => _section(root, 'roominfo')['alias'] = ''),
        'no alias, no title': _changed((root) {
          _section(root, 'roominfo')['alias'] = null;
          _section(root, 'liveinfo')['title'] = null;
        }),
      };
      for (final MapEntry(:key, :value) in variants.entries) {
        _expectRoom(_parseRoom(value), legacy[key], reason: key);
      }
      final avatars = legacy['avatars'] as Map<String, dynamic>;
      for (final (field, url) in [
        ('headPicUrl', 'https://vi1.6rooms.com/live/a.jpg'),
        ('headPicUrl', 'http://vi1.6rooms.com/live/a.jpg'),
        ('headPicUrl', '//vi1.6rooms.com/live/a.jpg'),
        ('headPicUrl', 'https://example.com/a.jpg'),
        ('headPicUrl', 'https://vi1.xiu123.cn/a.jpg'),
        ('picuser', 'https://vi1.6rooms.com/live/p.jpg'),
      ]) {
        _expectRoom(
          _parseRoom(_changed((root) => _section(root, 'roominfo')[field] = url)),
          avatars['$field $url'],
          reason: '$field $url',
        );
      }
      final covers = legacy['covers'] as Map<String, dynamic>;
      for (final (key, edit) in <(String, void Function(Map<String, dynamic>))>[
        ('no spredPic', (info) => info.remove('spredPic')),
        (
          'no spredPic, no pospic',
          (info) => info
            ..remove('spredPic')
            ..remove('pospic'),
        ),
        (
          'only pic',
          (info) => info
            ..remove('spredPic')
            ..remove('pospic')
            ..['largepic'] = ''
            ..['pic'] = 'https://vi0.6rooms.com/live/pic.jpg',
        ),
        (
          'no image',
          (info) => info
            ..remove('spredPic')
            ..remove('pospic')
            ..['largepic'] = ''
            ..['pic'] = '',
        ),
      ]) {
        _expectRoom(_parseRoom(_changed((root) => edit(_section(root, 'liveinfo')))), covers[key], reason: key);
      }
      final category = legacy['category'] as Map<String, dynamic>;
      _expectRoom(
        _parseRoom(_changed((root) => _section(root, 'roominfo')['anchor_area'] = '')),
        category['no anchor_area'],
      );
      _expectRoom(
        _parseRoom(
          _changed(
            (root) => _section(root, 'roominfo')
              ..['anchor_area'] = ''
              ..['rtypename'] = '',
          ),
        ),
        category['neither'],
      );
      final fans = legacy['fans_num'] as Map<String, dynamic>;
      for (final value in <Object?>['1,234', -1, 3.9, null, 'x', '12']) {
        _expectRoom(
          _parseRoom(_changed((root) => _section(root, 'roomParamInfo')['fans_num'] = value)),
          fans['$value'],
          reason: 'fans_num $value',
        );
      }
      // A live room whose stream name does not match 3.x's rule has no
      // variant in 3.x; it keeps its state and says why.
      for (final (key, body) in [
        (
          'stream name of another user',
          _changed((root) => _section(root, 'liveinfo')['flvtitle'] = 'v99999999-$liveId'),
        ),
        ('stream name with a path', _changed((root) => _section(root, 'liveinfo')['flvtitle'] = '$flvTitle/x')),
        (
          'live id not digits',
          _changed(
            (root) => _section(root, 'liveinfo')
              ..['id'] = 'x$liveId'
              ..['flvtitle'] = 'v$_liveUid-x$liveId',
          ),
        ),
      ]) {
        final room = _parseRoom(body);
        _expectRoom(room, legacy[key], reason: key);
        expect(room.mediaError, isA<ApiChanged>(), reason: key);
        expect(SixRoomApi.roomData(room).streamError, isA<ApiChanged>(), reason: key);
      }
    });

    test('failures are typed where 3.x had identity, access and schema', () {
      final legacy = _legacy('S05-inroom-live')['parseRoomJson'] as Map<String, dynamic>;
      final body = _sample('S05-inroom-live').body;
      // The answer is another room or broadcaster's (3.x: identity).
      for (final (key, roomId, userId) in [
        ('other room asked', '8839', _liveUid),
        ('other user asked', _live, '56182129'),
      ]) {
        _expectLegacyFailure(legacy[key], 'identity', reason: key);
        expect(
          () => _parseRoom(body, roomId: roomId, userId: userId),
          _throwsA<ApiChanged>(),
          reason: key,
        );
      }
      _expectLegacyFailure(legacy['roominfo of another room'], 'identity');
      expect(() => _parseRoom(_changed((root) => _section(root, 'roominfo')['rid'] = '8839')), _throwsA<ApiChanged>());
      _expectLegacyFailure(
        (_legacy('S05-inroom-offline')['parseRoomJson'] as Map<String, dynamic>)['other user asked'],
        'identity',
      );
      // A user id that is none is the caller's error (3.x: identity).
      _expectLegacyFailure(legacy['bad user asked'], 'identity');
      expect(() => _parseRoom(body, userId: '1'), throwsArgumentError);
      // 3.x's `access`: flag 402 (6.cn's "暂不能进入此房间！", a user without
      // a room) is NotFound; another flag RiskControl; no flag ApiChanged.
      _expectLegacyFailure(legacy['flag 402'], 'access');
      _expectLegacyFailure(_legacy('S05-inroom-missing')['parseRoomJson'], 'access');
      expect(
        () => SixRoomApi.room(_sample('S05-inroom-missing').body, roomId: '99999999999', userId: '99999999999'),
        throwsA(isA<NotFound>().having((error) => error.detail, 'detail', contains('暂不能进入此房间'))),
      );
      expect(() => _parseRoom(_changed((root) => root['flag'] = '402')), _throwsA<NotFound>());
      expect(() => _parseRoom(_changed((root) => root['flag'] = '203')), _throwsA<RiskControl>());
      _expectLegacyFailure(legacy['flag missing'], 'access');
      _expectLegacyFailure(legacy['flag number'], 'access');
      expect(() => _parseRoom(_changed((root) => root.remove('flag'))), _throwsA<ApiChanged>());
      expect(() => _parseRoom(_changed((root) => root['flag'] = 1)), _throwsA<ApiChanged>());
      // 3.x's `schema`: the answer's shape.
      for (final (key, text) in [
        ('no content', _changed((root) => root['content'] = 'x')),
        ('no roominfo', _changed((root) => _content(root).remove('roominfo'))),
        ('no liveinfo', _changed((root) => _content(root).remove('liveinfo'))),
        ('no roomParamInfo', _changed((root) => _content(root).remove('roomParamInfo'))),
        ('not JSON', '<html>'),
        ('a list', '[1]'),
      ]) {
        _expectLegacyFailure(legacy[key], 'schema', reason: key);
        expect(() => _parseRoom(text), _throwsA<ApiChanged>(), reason: key);
      }
    });

    test("3.x's mediaUri", () {
      final legacy = _legacy('S05-inroom-live')['mediaUri'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in legacy.entries) {
        final [userId, liveId, name] = key.split(' ');
        expect(
          SixRoomApi.mediaUri(userId: userId, liveId: liveId, flvTitle: name)?.toString(),
          value,
          reason: key,
        );
      }
    });

    test("rooms read with a known user id are 3.x's (avatar: the cover, as 3.x showed)", () {
      final legacy = _legacy('S05-inroom-live')['knownUserId'] as Map<String, dynamic>;
      for (final media in [true, false]) {
        final room = _parseRoom(_sample('S05-inroom-live').body, media: media);
        _expectParity(SixRoomApi.liveRoom(room), _result(legacy['includeMedia $media']), reason: '$media');
        final data = (_result(legacy['includeMedia $media'])! as Map<String, dynamic>)['data'];
        // 3.x's refreshed rooms carried no data.
        if (media) _expectRoom(room, data);
        if (!media) expect(data, isNull);
      }
      final offline = _parseRoom(_sample('S05-inroom-offline').body, roomId: _offline, userId: _offlineUid);
      _expectParity(SixRoomApi.liveRoom(offline), _result(_legacy('S05-inroom-offline')['knownUserId']));
      // Without avatar and cover, the answer's own avatar (3.x left it empty).
      final bare = _parseRoom(
        _changed(
          (root) => _section(root, 'liveinfo')
            ..remove('spredPic')
            ..remove('pospic')
            ..['largepic'] = ''
            ..['pic'] = '',
        ),
      );
      expect(SixRoomApi.liveRoom(bare).avatar, bare.ownerAvatar);
      expect(bare.ownerAvatar, isNotEmpty);
    });

    test("3.x's own inroom fixtures", () {
      final room = SixRoomApi.room(_legacyLiveRoomJson, roomId: '8838', userId: '56182128');
      expect(room.state, SixRoomState.live);
      expect(room.followers, 425585);
      expect((room.stream!.resolution, room.stream!.bitrate), ('1024x768', 2653));
      expect('${room.stream!.url}', endsWith('/v56182128-222415076.flv'));
      expect(SixRoomApi.mediaUri(userId: '56182128', liveId: '222415076', flvTitle: 'v99999999-222415076'), isNull);
      final offline = SixRoomApi.room(_legacyOfflineRoomJson, roomId: '243126861', userId: '98073893');
      expect(offline.state, SixRoomState.offline);
      expect(offline.stream, isNull);
      expect(SixRoomApi.liveRoom(offline).area, SixRoomApi.siteName);
    });
  });

  group('rooms, qualities and lines', () {
    test("3.x's quality label, the line and the room data", () {
      final live = _parseRoom(_sample('S05-inroom-live').body);
      final streams =
          (_legacy('S05-inroom-live')['after the directory'] as Map<String, dynamic>)['getRoomDetail → streams']
              as Map<String, dynamic>;
      final legacyQuality = _maps(_result(streams['getPlayQualites'])).single;
      final quality = SixRoomApi.quality(live.stream!);
      expect((quality.quality, quality.id, quality.sort), (legacyQuality['quality'], legacyQuality['id'], 2652));
      expect(quality.quality, 'FLV 原始线路 · 1024x768 · 2652 kbps');
      expect(SixRoomApi.quality(SixRoomStream(url: live.stream!.url)).quality, 'FLV 原始线路');
      expect(SixRoomApi.quality(SixRoomStream(url: live.stream!.url)).sort, 1);
      expect(SixRoomApi.quality(SixRoomStream(url: live.stream!.url, bitrate: 900)).quality, 'FLV 原始线路 · 900 kbps');
      final line = SixRoomApi.line(live.stream!);
      expect([line.url], (_result(streams['resolvePlayUrlsRaw'])! as Map<String, dynamic>)['urls']);
      expect((line.format, line.codec, line.lineId, line.lease), (StreamFormat.flv, 'avc', 'wlive', null));
      expect(line.headers, isEmpty, reason: "3.x's player and recorder sent no Six Rooms headers");
      expect(SixRoomApi.roomData(live).streamError, isNull);
      final refreshed = _parseRoom(_sample('S05-inroom-live').body, media: false);
      expect(SixRoomApi.roomData(refreshed).streamError, isA<StreamUnavailable>());
      final offline = _parseRoom(_sample('S05-inroom-offline').body, roomId: _offline, userId: _offlineUid);
      expect(SixRoomApi.roomData(offline).streamError, isA<StreamUnavailable>());
      final private = _parseRoom(_changed((root) => _content(root)['isPriveRoom'] = 1));
      expect(SixRoomApi.roomData(private).streamError, isA<StreamUnavailable>());
      final room = SixRoomApi.liveRoom(private);
      expect(room.liveStatus, LiveStatus.unknown, reason: 'never offline (3.x)');
      expect(room.notice, '${SixRoomApi.restrictedNotice}\n${SixRoomApi.chatNotice}');
    });

    test('enrich takes what the answer lacks from the earlier card (3.x)', () {
      final card = SixRoomApi.directory(_sample('S04-home').body).first;
      final room = _parseRoom(_sample('S05-inroom-live').body).enrich(card);
      expect(room.avatar, card.avatar);
      expect(room.popularity, card.popularity);
      expect(room.title, isNot(card.title), reason: "the answer's title is not the placeholder");
      expect(room.followers, 425628);
      expect(room.stream, isNotNull);
      final search = SixRoomApi.search(_sample('S02-search').body)[1];
      final offline = _parseRoom(_sample('S05-inroom-offline').body, roomId: _offline, userId: _offlineUid);
      expect(search.enrich(offline).state, SixRoomState.offline, reason: 'an unknown card takes the known state');
    });

    test("statuses map to typed errors (3.x's _throwStatus), and the 8 MiB limit", () {
      for (final (status, matcher) in [
        (404, isA<NotFound>()),
        (410, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (302, isA<RiskControl>()),
        (500, isA<NetworkFailure>()),
        (400, isA<NetworkFailure>()),
        (100, isA<NetworkFailure>()),
      ]) {
        expect(() => SixRoomApi.directory('', status: status), throwsA(matcher), reason: '$status');
        expect(() => SixRoomApi.search('', status: status), throwsA(matcher), reason: '$status');
      }
      expect(SixRoomApi.search(_sample('S02-search-empty').body, status: 204), isEmpty);
      final large = '<html>${'x' * SixRoomApi.responseLimit}</html>';
      expect(() => SixRoomApi.search(large), _throwsA<ApiChanged>());
      final wide = '<html>${'六' * (SixRoomApi.responseLimit ~/ 3 + 1)}</html>';
      expect(() => SixRoomApi.search(wide), _throwsA<ApiChanged>(), reason: 'counted in UTF-8 bytes');
    });
  });
}
