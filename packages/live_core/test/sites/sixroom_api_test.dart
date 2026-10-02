// Six Rooms parsing against the recorded samples, compared field by field
// with 3.x's frozen output (expected.json, written by
// fixtures/sixroom/legacy_expected.dart from 3.x's SixRoomApi, SixRoomLink
// and SixRoomSite). Every intended difference is listed with its reason
// (`changed:` with the upgrade's number, docs/specs/UPGRADES.md); everything else
// must match. The synthetic cases are the harness's changed copies of the
// samples, and 3.x's own sixroom_site_test.dart fixtures. The mobile lists
// and the web subarea (M4.U.31, 31-4) have no 3.x output; their samples
// (S01, S06) are checked on their own.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('sixroom', name);

const _live = '8838';
const _liveUid = '56182128';
const _offline = '191111';
const _offlineUid = '63213382';

/// The live room's signature (`roomParamInfo.operation.userMood`, also the
/// homepage card's `userMood`) and own avatar (`roominfo.uoption.picuser`,
/// also the homepage card's `picuser`).
const _liveSignature = '但行好事，莫问前程';
const _liveAvatar = 'https://vi1.6rooms.com/live/2023/11/27/03/1003v1701026023898195476.jpg';
const _offlineSignature = '前行再难感恩有你陪伴';
const _offlineAvatar = 'https://vi3.6rooms.com/live/2016/06/01/14/1003v1464762358720321773.jpg';

/// The live broadcast's start: inroom `liveinfo.starttime` 1790594729, the
/// homepage card's `realstarttime`.
final _liveStart = DateTime.utc(2026, 9, 28, 11, 25, 29);

/// Room keys every room changed: the notice is in words for users now
/// (unified rule "说明文字"), and since M5.27 (chat is shown) it only says
/// what the audience number is.
const _notice = {'notice'};

/// Room keys of a room read from inroom: the title is the broadcaster's
/// signature (31-2; 3.x's was the name), the avatar the broadcaster's own
/// (31-1; 3.x showed the cover), and the notice.
const _inroomRoom = {'title', 'avatar', 'notice'};

/// `SixRoomRoom` keys of an inroom answer: 31-2 and 31-1 as above.
const _inroomParse = {'title', 'avatar'};

/// Room keys of a search card: its state (31-3; 3.x's were all unknown), no
/// area stand-in (unified rule "占位信息": 3.x wrote the platform's name),
/// and the notice.
const _searchCard = {'liveStatus', 'status', 'area', 'notice'};

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

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {Set<String> changed = const {}, String reason = ''}) {
  final expected = _maps(legacy);
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(room, expected[index], changed: changed, reason: '$reason[$index]');
  }
}

/// [room]'s fields under the names of 3.x's `SixRoomRoom` projection, and
/// the one variant as [SixRoomRoom.stream].
Map<String, Object?> _projection(SixRoomRoom room) => {
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

/// Asserts that [room] equals 3.x's `SixRoomRoom` projection [legacy]
/// except [changed].
void _expectRoom(SixRoomRoom room, Object? legacy, {Set<String> changed = const {}, String reason = ''}) {
  final expected = legacy! as Map<String, dynamic>;
  final actual = _projection(room);
  for (final MapEntry(:key, :value) in expected.entries) {
    if (changed.contains(key)) continue;
    expect(actual[key], value, reason: '$reason ${expected['roomId']} $key');
  }
}

void _expectRoomList(List<SixRoomRoom> rooms, Object? legacy, {Set<String> changed = const {}, String reason = ''}) {
  final expected = _maps(legacy);
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectRoom(room, expected[index], changed: changed, reason: '$reason[$index]');
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

/// Page [page] of [size] of the mobile list sample [name] of [type].
SixRoomListPage _list(String name, String type, {required int page, required int size}) =>
    SixRoomApi.list(_sample(name).body, type: type, page: page, size: size);

/// A mobile list answer of [type] with [rows] and [count] rooms in all.
String _listAnswer(String type, List<Object?> rows, {int? count}) => jsonEncode({
  'flag': '001',
  'content': {
    type: rows,
    'roomListCount': {type: ?count},
  },
});

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
    test("3.x's one category and six areas, and where their rooms come from now (31-4)", () {
      final legacy = _legacy('S04-home');
      final categories = SixRoomApi.categories();
      final expected = _maps(_result(legacy['getCategores'])).single;
      expect((categories.single.id, categories.single.name), (expected['id'], expected['name']));
      expect(
        [for (final area in categories.single.children) area.toJson()],
        [
          for (final area in _maps(expected['children'])) {...area, 'areaPic': '', 'shortName': ''},
        ],
        reason: "3.x wrote null for areaPic and shortName; the model writes ''. The ids and names are 3.x's",
      );
      expect([
        for (final area in SixRoomApi.categories(limit: 3).single.children) area.areaId,
      ], _result(legacy['getCategores(pageSize: 3)']));
      expect(legacy['name'], SixRoomApi.siteName);
      expect({
        for (final MapEntry(:key, :value) in (legacy['SixRoomApi.mediaHeaders'] as Map<String, dynamic>).entries)
          key.toLowerCase(): value,
      }, SixRoomApi.mediaHeaders(_live));
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
      // All rooms stay the homepage; 星颜 is the web's subarea 10 (the app's
      // u10 answers nothing, S06-list-u10-p1); the rest are mobile lists.
      expect(
        {for (final area in categories.single.children) area.areaId: SixRoomApi.mobileTypeOf(area.areaId)},
        {'all': null, 'song': 'u0', 'dance': 'u1', 'talk': 'u2', 'face': null, 'party': 'u8'},
      );
      expect(
        [for (final area in categories.single.children) SixRoomApi.subareaOf(area.areaId)],
        [null, null, null, null, 10, null],
      );
      expect(SixRoomApi.recommendType, 'special');
      // The recorded requests: the archive's list form, the web's subarea.
      for (final name in ['S01-list-u0-p1', 'S06-list-special-p1', 'S06-list-u0-p2']) {
        final url = _sample(name).url;
        final type = url.queryParameters['type']!;
        final page = int.parse(url.queryParameters['p']!);
        final size = int.parse(url.queryParameters['size']!);
        expect(
          SixRoomApi.listUrl(type, page: page, size: size).queryParameters,
          url.queryParameters,
          reason: name,
        );
        expect(SixRoomApi.listUrl(type, page: page, size: size).replace(query: ''), url.replace(query: ''));
      }
      expect(SixRoomApi.subareaUrl(10), _sample('S06-subarea-face').url);
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

  group('homepage (all rooms)', () {
    test("every room matches 3.x's parse, and every card 3.x's page", () {
      final legacy = _legacy('S04-home');
      final rooms = SixRoomApi.directory(_sample('S04-home').body);
      _expectRoomList(rooms, legacy['parseDirectoryHtml']);
      expect(rooms, hasLength(443));
      final pages = legacy['getDirectoryPage(all)'] as Map<String, dynamic>;
      final cards = [for (final traced in pages.values) ...(_result(traced)! as Map<String, dynamic>)['rooms'] as List];
      final shown = [for (final room in rooms) SixRoomApi.liveRoom(room)];
      _expectRooms(shown, cards, changed: {..._notice, 'area'});
      for (final (index, room) in shown.indexed) {
        expect(room.httpHeaders, SixRoomApi.mediaHeaders(room.roomId));
        expect(room.notice, SixRoomApi.chatNotice);
        // One room has no area: 3.x wrote the platform's name, now none
        // (unified rule "占位信息").
        final area = (cards[index] as Map<String, dynamic>)['area'];
        expect(room.area, area == SixRoomApi.siteName ? '' : area, reason: room.roomId);
        expect(room.startedAt, isNotNull, reason: 'realstarttime (M2.1)');
        expect(room.restriction, isNull, reason: 'a card says nothing about restrictions');
      }
      expect(shown.where((room) => room.area!.isEmpty), hasLength(1));
      final live = rooms.firstWhere((room) => room.roomId == _live);
      expect((live.startedAt, live.avatar, live.title), (_liveStart, _liveAvatar, _liveSignature));
    });

    test("changed homepages match 3.x's parse; names and titles are empty, not 3.x's `Six Rooms`", () {
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
        final rooms = SixRoomApi.directory(_withRows(value));
        if (key != 'titles') {
          _expectRoomList(rooms, legacy[key], reason: key);
          continue;
        }
        // 3.x's `Six Rooms` for a row without a name (unified rule
        // "占位信息"): now empty, so a follow keeps the name it stored.
        _expectRoomList(rooms, legacy[key], changed: const {'nick', 'title'}, reason: key);
        final expected = _maps(legacy[key]);
        for (final (index, room) in rooms.indexed) {
          String blank(Object? value) => value == 'Six Rooms' ? '' : value! as String;
          expect((room.nick, room.title), (blank(expected[index]['nick']), blank(expected[index]['title'])));
        }
        expect([for (final room in rooms) room.nick].skip(3), ['', '']);
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
      // A start that is none: 0, negative, not a number.
      for (final value in <Object?>[0, '0', -1, 'x', null, '']) {
        final room = SixRoomApi.directory(
          _withRows([
            {...first, 'realstarttime': value},
          ]),
        ).single;
        expect(room.startedAt, isNull, reason: '$value');
      }
      expect(
        SixRoomApi.directory(
          _withRows([
            {...first, 'realstarttime': 1790594729},
          ]),
        ).single.startedAt,
        _liveStart,
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
      expect(card.startedAt, isNull, reason: 'no realstarttime');
    });
  });

  group('mobile lists (31-4)', () {
    test('pages of the app lists: live cards, and whether the list goes on', () {
      // 歌区 at 20 a page (the archive's recording): 59 rooms, page 3 is the
      // last (19), page 4 empty.
      final first = _list('S01-list-u0-p1', 'u0', page: 1, size: 20);
      expect((first.rooms.length, first.hasMore), (20, true));
      final last = _list('S01-list-u0-p3', 'u0', page: 3, size: 20);
      expect((last.rooms.length, last.hasMore), (19, false));
      final past = _list('S01-list-u0-p4', 'u0', page: 4, size: 20);
      expect((past.rooms.length, past.hasMore), (0, false));
      // At 30 a page (what the adapter asks, S06): 34 rooms, 30 + 4.
      for (final (name, type, page, rooms, more) in [
        ('S06-list-special-p1', 'special', 1, 30, true),
        ('S06-list-special-p2', 'special', 2, 4, false),
        ('S06-list-u0-p1', 'u0', 1, 30, true),
        ('S06-list-u0-p2', 'u0', 2, 4, false),
        ('S06-list-u1-p1', 'u1', 1, 18, false),
        ('S06-list-u2-p1', 'u2', 1, 5, false),
        ('S06-list-u8-p1', 'u8', 1, 17, false),
        ('S01-list-special-p1', 'special', 1, 20, true),
        ('S01-list-u8-p1', 'u8', 1, 19, false),
      ]) {
        final size = int.parse(_sample(name).url.queryParameters['size']!);
        final result = _list(name, type, page: page, size: size);
        expect((result.rooms.length, result.hasMore), (rooms, more), reason: name);
        for (final room in result.rooms) {
          expect(room.state, SixRoomState.live, reason: '$name ${room.roomId}');
          expect(SixRoomApi.isUserId(room.userId), isTrue, reason: '$name ${room.roomId}');
          expect(room.startedAt, isNotNull, reason: '$name ${room.roomId}: realstarttime');
          expect(room.avatar, isEmpty, reason: '$name ${room.roomId}: the app list has no avatar');
          expect(room.cover, isNotEmpty, reason: '$name ${room.roomId}');
          expect(room.nick, isNotEmpty, reason: '$name ${room.roomId}');
        }
        if (type != 'special') {
          final area = {'u0': '歌区', 'u1': '舞区', 'u2': '脱口秀', 'u8': '派对'}[type];
          expect(result.rooms.map((room) => room.category).toSet(), {area}, reason: name);
        }
      }
      // The recommendations span the areas, 星颜 included.
      expect(
        _list('S06-list-special-p1', 'special', page: 1, size: 30).rooms.map((room) => room.category).toSet(),
        containsAll(['歌区', '舞区', '脱口秀', '星颜']),
      );
      // 星颜 (`u10`) answers `content: []`.
      final face = _list('S06-list-u10-p1', 'u10', page: 1, size: 30);
      expect((face.rooms.length, face.hasMore), (0, false));
      // One card in full (S01 歌区 page 1): no live title, so the signature.
      final card = first.rooms.first;
      expect(
        (card.roomId, card.userId, card.liveId, card.nick, card.title, card.category, card.popularity),
        ('16066', '53007895', '222427077', '莹儿～晚上见', '不谈亏欠，不负遇见', '歌区', 6428),
      );
      expect(card.cover, startsWith('https://vi0.6rooms.com/live/2023/08/05/02/1010v1691173802439697214.jpg'));
      expect(card.startedAt, DateTime.utc(2026, 9, 27, 12, 28, 46));
      final room = SixRoomApi.liveRoom(card);
      expect((room.liveStatus, room.area, room.popularity, room.avatar), (LiveStatus.live, '歌区', '6428', ''));
      expect(room.audienceMetricType, AudienceMetricType.popularity);
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 12, 28, 46));
    });

    test('a bad row is skipped; a list that cannot be read is an error, not an empty list', () {
      final rows = _content(jsonDecode(_sample('S06-list-u2-p1').body) as Map<String, dynamic>)['u2'] as List;
      final good = Map<String, Object?>.from(rows.first as Map);
      final mixed = SixRoomApi.list(
        _listAnswer('u2', [
          1,
          {...good, 'rid': '0'},
          {...good, 'uid': ''},
          good,
          {...good, 'username': 'again'},
          {...good, 'rid': '1234', 'livetitle': '', 'userMood': '', 'username': '', 'realstarttime': 0},
        ], count: 6),
        type: 'u2',
        page: 1,
        size: 30,
      );
      expect(mixed.rooms.map((room) => room.roomId), [good['rid'], '1234']);
      expect(mixed.rooms.last.nick, isEmpty, reason: "no name: empty, not 3.x's `Six Rooms`");
      expect(mixed.rooms.last.title, isEmpty);
      expect(mixed.rooms.last.startedAt, isNull);
      expect(mixed.hasMore, isFalse, reason: '1 × 30 is past the 6 rooms');
      // Without a count, a full page goes on.
      expect(SixRoomApi.list(_listAnswer('u2', [good, good]), type: 'u2', page: 1, size: 1).hasMore, isTrue);
      expect(SixRoomApi.list(_listAnswer('u2', [good]), type: 'u2', page: 1, size: 2).hasMore, isFalse);
      for (final (body, matcher) in [
        (_listAnswer('u2', [1, 'x']), _throwsA<ApiChanged>()),
        (_listAnswer('u1', [good]), _throwsA<ApiChanged>()),
        (jsonEncode({'flag': '001', 'content': 'x'}), _throwsA<ApiChanged>()),
        (jsonEncode({'content': <Object?>[]}), _throwsA<ApiChanged>()),
        (jsonEncode({'flag': 1, 'content': <Object?>[]}), _throwsA<ApiChanged>()),
        ('<html>', _throwsA<ApiChanged>()),
        (jsonEncode({'flag': '203', 'content': '请稍后再试'}), throwsA(isA<RiskControl>())),
      ]) {
        expect(() => SixRoomApi.list(body, type: 'u2', page: 1, size: 30), matcher, reason: body);
      }
      expect(() => SixRoomApi.list('', type: 'u2', page: 1, size: 30, status: 429), throwsA(isA<RateLimited>()));
    });
  });

  group('web subarea (星颜, 31-4)', () {
    test('the featured rooms, then the rest, once each, with avatars', () {
      final rooms = SixRoomApi.subarea(_sample('S06-subarea-face').body);
      expect(rooms.map((room) => room.roomId), [
        '644435',
        '803428',
        '748781',
        '67999',
        '199411',
        '949818',
        '945486',
        '677777',
        '649470',
      ]);
      for (final room in rooms) {
        expect(room.category, '星颜', reason: room.roomId);
        expect(room.state, SixRoomState.live);
        expect(room.avatar, startsWith('https://vi'), reason: '${room.roomId}: picuser');
        expect(room.nick, isNotEmpty, reason: '${room.roomId}: alias or username');
        expect(room.popularity, isNotNull);
      }
      // The featured rows have no realstarttime (only "3小时7分前").
      expect([for (final room in rooms.take(3)) room.startedAt], [null, null, null]);
      expect(rooms[3].startedAt, DateTime.fromMillisecondsSinceEpoch(1790606019000, isUtc: true));
      expect((rooms.first.nick, rooms.first.title, rooms.first.popularity), ('苏杳yao~🍒', '喂一口吧好哥哥', 3777));
    });

    test('an answer without its lists is an error; a flag is RiskControl', () {
      for (final (body, matcher) in [
        (jsonEncode({'flag': '001', 'content': <String, Object?>{}}), _throwsA<ApiChanged>()),
        (jsonEncode({'flag': '001', 'content': <Object?>[]}), _throwsA<ApiChanged>()),
        (
          jsonEncode({
            'flag': '001',
            'content': {
              'bigLiveList': {'list': <Object?>[]},
              'liveList': {
                '1': {'rid': 'x'},
              },
            },
          }),
          _throwsA<ApiChanged>(),
        ),
        (jsonEncode({'flag': '105', 'content': 'x'}), throwsA(isA<RiskControl>())),
      ]) {
        expect(() => SixRoomApi.subarea(body), matcher, reason: body);
      }
      expect(
        SixRoomApi.subarea(
          jsonEncode({
            'flag': '001',
            'content': {
              'bigLiveList': {'list': <Object?>[]},
              'liveList': <String, Object?>{},
            },
          }),
        ),
        isEmpty,
        reason: 'no 星颜 room live',
      );
    });
  });

  group('search', () {
    test("search pages match 3.x's parse, now with the live mark (31-3)", () {
      final legacy = _legacy('S02-search');
      final body = _sample('S02-search').body;
      final rooms = SixRoomApi.search(body);
      _expectRoomList(rooms, legacy['parseSearchHtml'], changed: const {'state'});
      expect(rooms, hasLength(35));
      // Two cards carry `<i class="live" title="直播中">` and link the room;
      // the others link the profile.
      expect(
        [
          for (final room in rooms)
            if (room.state == SixRoomState.live) room.roomId,
        ],
        ['277288', '68160'],
      );
      expect(rooms.where((room) => room.state == SixRoomState.offline), hasLength(33));
      expect('class="live"'.allMatches(body), hasLength(2));
      final shown = [for (final room in rooms.take(3)) SixRoomApi.liveRoom(room)];
      _expectRooms(
        shown,
        _result((legacy['searchRooms'] as Map<String, dynamic>)['"诺" page 1 size 3']),
        changed: _searchCard,
      );
      expect([for (final room in shown) room.liveStatus], [LiveStatus.live, LiveStatus.offline, LiveStatus.offline]);
      expect(shown.map((room) => room.area), everyElement(''));
      expect(SixRoomApi.search(_sample('S02-search-empty').body), isEmpty);
      expect(_legacy('S02-search-empty')['parseSearchHtml'], isEmpty);
      final variants = legacy['parseSearchHtml(variants)'] as Map<String, dynamic>;
      final changed = SixRoomApi.search('''
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
''');
      // The profile link is offline, the room link without a mark unknown
      // (31-3); no name is empty, not 3.x's `Six Rooms` (unified rule
      // "占位信息").
      _expectRoomList(changed, variants['duplicate and invalid'], changed: const {'state', 'nick', 'title'});
      expect(
        [for (final room in changed) (room.state, room.nick, room.title)],
        [(SixRoomState.offline, '小荷叶 加油', '小荷叶 加油'), (SixRoomState.unknown, '', '')],
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
      expect(rooms.first.state, SixRoomState.offline, reason: 'a profile link without the live mark (31-3)');
      expect(rooms.last.roomId, '243126861');
      expect(rooms.last.avatar, startsWith('https://vi1.6rooms.com/'));
      final card = SixRoomApi.liveRoom(rooms.first);
      expect((card.liveStatus, card.area, card.cover), (LiveStatus.offline, '', ''));
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
    test("the recorded answers match 3.x's parse; the signature, the own avatar and the start are new", () {
      final legacy = _legacy('S05-inroom-live')['parseRoomJson'] as Map<String, dynamic>;
      final live = _parseRoom(_sample('S05-inroom-live').body);
      _expectRoom(live, legacy['recorded'], changed: _inroomParse);
      _expectRoom(
        _parseRoom(_sample('S05-inroom-live').body, media: false),
        legacy['recorded (includeMedia false)'],
        changed: _inroomParse,
      );
      _expectRoom(
        _parseRoom(_sample('S05-inroom-live').body, roomId: 'https://v.6.cn/$_live'),
        legacy['link asked'],
        changed: _inroomParse,
      );
      final offlineLegacy = _legacy('S05-inroom-offline')['parseRoomJson'] as Map<String, dynamic>;
      final offline = _parseRoom(_sample('S05-inroom-offline').body, roomId: _offline, userId: _offlineUid);
      _expectRoom(offline, offlineLegacy['recorded'], changed: _inroomParse);
      // 31-2: 3.x read `roominfo.userMood` (absent), so the title was the
      // name; the signature is `roomParamInfo.operation.userMood`, the text
      // the homepage card shows.
      expect((live.title, (legacy['recorded'] as Map)['title']), (_liveSignature, live.nick));
      expect(offline.title, _offlineSignature);
      // 31-1: the broadcaster's avatar `roominfo.uoption.picuser` (3.x read
      // `headPicUrl` and `picuser`, empty and absent, and showed the cover).
      expect((live.avatar, offline.avatar), (_liveAvatar, _offlineAvatar));
      // M2.1: the start while live; no restriction stated.
      expect((live.startedAt, offline.startedAt), (_liveStart, null));
      expect((live.restriction, offline.restriction), (LiveRestriction.none, LiveRestriction.none));
      expect(live.stream!.codec, 'avc', reason: 'streamInfo.videoCodec AVC (3.x did not read it)');
    });

    test("changed answers match 3.x's parse, except the upgrades", () {
      final legacy = _legacy('S05-inroom-live')['parseRoomJson'] as Map<String, dynamic>;
      final liveInfo = _section(_inroom(), 'liveinfo');
      final flvTitle = liveInfo['flvtitle'] as String;
      final liveId = liveInfo['id'] as String;
      final variants = <String, String>{
        'roominfo without id': _changed((root) => _section(root, 'roominfo').remove('id')),
        'private ("0")': _changed((root) => _content(root)['isPriveRoom'] = '0'),
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
      };
      for (final MapEntry(:key, :value) in variants.entries) {
        final room = _parseRoom(value);
        // The title stays 3.x's where the answer has a live title or 3.x's
        // `roominfo.userMood`; else it is the signature (31-2).
        final keepsTitle = key == 'title' || key == 'userMood';
        _expectRoom(room, legacy[key], changed: {'avatar', if (!keepsTitle) 'title'}, reason: key);
        expect(room.avatar, _liveAvatar, reason: '$key: 31-1');
        if (!keepsTitle) expect(room.title, _liveSignature, reason: '$key: 31-2');
      }
      // A private room or a black screen: live, with the restriction (M2.1;
      // 3.x showed them as unknown), and no stream.
      for (final (key, edit, restriction) in <(String, void Function(Map<String, dynamic>), LiveRestriction)>[
        ('private (1)', (root) => _content(root)['isPriveRoom'] = 1, LiveRestriction.private),
        ('private ("1")', (root) => _content(root)['isPriveRoom'] = '1', LiveRestriction.private),
        ('private (true)', (root) => _content(root)['isPriveRoom'] = true, LiveRestriction.private),
        (
          'black screen',
          (root) => _content(root)['blackScreenInfo'] = {'msg': ' 黑屏 ', 'endtm': 1},
          LiveRestriction.unplayable,
        ),
      ]) {
        final room = _parseRoom(_changed(edit));
        expect(legacy[key], containsPair('state', 'restricted'), reason: key);
        _expectRoom(room, legacy[key], changed: {..._inroomParse, 'state'}, reason: key);
        expect((room.state, room.restriction, room.stream), (SixRoomState.live, restriction, null), reason: key);
        expect(room.startedAt, _liveStart, reason: key);
        final shown = SixRoomApi.liveRoom(room);
        expect((shown.liveStatus, shown.isLiveNow, shown.isRestricted), (LiveStatus.live, true, true));
        expect(shown.notice, '${SixRoomApi.restrictedNotice}\n${SixRoomApi.chatNotice}');
        expect(SixRoomApi.roomData(room).streamError, isA<StreamUnavailable>(), reason: key);
      }
      expect(
        SixRoomApi.roomData(
          _parseRoom(_changed((root) => _content(root)['blackScreenInfo'] = {'msg': ' 黑屏 ', 'endtm': 1})),
        ).streamError?.detail,
        contains('黑屏'),
      );
      // Restricted without a live id is offline; with a live id and no
      // stream name it is still live.
      final ended = _parseRoom(
        _changed((root) {
          _content(root)['isPriveRoom'] = 1;
          _section(root, 'liveinfo').remove('id');
        }),
      );
      expect((ended.state, ended.restriction, ended.startedAt), (SixRoomState.offline, LiveRestriction.private, null));
      final hidden = _parseRoom(
        _changed((root) {
          _content(root)['isPriveRoom'] = 1;
          _section(root, 'liveinfo')['flvtitle'] = '';
        }),
      );
      expect(hidden.state, SixRoomState.live);
      // An answer without either field says nothing about restrictions.
      final silent = _parseRoom(
        _changed((root) {
          _content(root).remove('isPriveRoom');
          _content(root).remove('blackScreenInfo');
        }),
      );
      expect((silent.restriction, silent.state), (null, SixRoomState.live));
      // No name: empty, not 3.x's `Six Rooms` (unified rule "占位信息").
      for (final (key, edit) in <(String, void Function(Map<String, dynamic>))>[
        ('no alias', (root) => _section(root, 'roominfo')['alias'] = ''),
        (
          'no alias, no title',
          (root) {
            _section(root, 'roominfo')['alias'] = null;
            _section(root, 'liveinfo')['title'] = null;
          },
        ),
      ]) {
        final room = _parseRoom(_changed(edit));
        _expectRoom(room, legacy[key], changed: {..._inroomParse, 'nick'}, reason: key);
        expect((room.nick, room.title), ('', _liveSignature), reason: key);
      }
      final bare = _parseRoom(
        _changed((root) {
          _section(root, 'roominfo').remove('alias');
          _section(root, 'roomParamInfo').remove('operation');
        }),
      );
      expect((bare.nick, bare.title), ('', ''));
      final avatars = legacy['avatars'] as Map<String, dynamic>;
      for (final (field, url) in [
        ('headPicUrl', 'https://vi1.6rooms.com/live/a.jpg'),
        ('headPicUrl', 'http://vi1.6rooms.com/live/a.jpg'),
        ('headPicUrl', '//vi1.6rooms.com/live/a.jpg'),
        ('headPicUrl', 'https://example.com/a.jpg'),
        ('headPicUrl', 'https://vi1.xiu123.cn/a.jpg'),
        ('picuser', 'https://vi1.6rooms.com/live/p.jpg'),
      ]) {
        final expected = avatars['$field $url'] as Map<String, dynamic>;
        final room = _parseRoom(_changed((root) => _section(root, 'roominfo')[field] = url));
        _expectRoom(room, expected, changed: _inroomParse, reason: '$field $url');
        // 3.x's avatar when it found one; else the broadcaster's own (31-1).
        final avatar = expected['avatar'] as String;
        expect(room.avatar, avatar.isEmpty ? _liveAvatar : avatar, reason: '$field $url');
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
        _expectRoom(
          _parseRoom(_changed((root) => edit(_section(root, 'liveinfo')))),
          covers[key],
          changed: _inroomParse,
          reason: key,
        );
      }
      final category = legacy['category'] as Map<String, dynamic>;
      _expectRoom(
        _parseRoom(_changed((root) => _section(root, 'roominfo')['anchor_area'] = '')),
        category['no anchor_area'],
        changed: _inroomParse,
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
        changed: _inroomParse,
      );
      final fans = legacy['fans_num'] as Map<String, dynamic>;
      for (final value in <Object?>['1,234', -1, 3.9, null, 'x', '12']) {
        _expectRoom(
          _parseRoom(_changed((root) => _section(root, 'roomParamInfo')['fans_num'] = value)),
          fans['$value'],
          changed: _inroomParse,
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
        _expectRoom(room, legacy[key], changed: _inroomParse, reason: key);
        expect(room.mediaError, isA<ApiChanged>(), reason: key);
        expect(SixRoomApi.roomData(room).streamError, isA<ApiChanged>(), reason: key);
      }
      // A start that is none.
      for (final value in <Object?>['', '0', 0, null, 'x']) {
        expect(
          _parseRoom(_changed((root) => _section(root, 'liveinfo')['starttime'] = value)).startedAt,
          isNull,
          reason: '$value',
        );
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

    test("rooms read with a known user id are 3.x's, except the signature and the avatar (31-1, 31-2)", () {
      final legacy = _legacy('S05-inroom-live')['knownUserId'] as Map<String, dynamic>;
      for (final media in [true, false]) {
        final room = _parseRoom(_sample('S05-inroom-live').body, media: media);
        final shown = SixRoomApi.liveRoom(room);
        final expected = _result(legacy['includeMedia $media'])! as Map<String, dynamic>;
        _expectParity(shown, expected, changed: _inroomRoom, reason: '$media');
        // 3.x showed the cover as the avatar; now the broadcaster's own.
        expect((expected['avatar'], shown.avatar), (expected['cover'], _liveAvatar));
        expect((shown.title, shown.startedAt, shown.restriction), (_liveSignature, _liveStart, LiveRestriction.none));
        final data = expected['data'];
        // 3.x's refreshed rooms carried no data.
        if (media) _expectRoom(room, data, changed: _inroomParse);
        if (!media) expect(data, isNull);
      }
      final offline = _parseRoom(_sample('S05-inroom-offline').body, roomId: _offline, userId: _offlineUid);
      final shown = SixRoomApi.liveRoom(offline);
      _expectParity(shown, _result(_legacy('S05-inroom-offline')['knownUserId']), changed: _inroomRoom);
      expect((shown.title, shown.avatar, shown.startedAt), (_offlineSignature, _offlineAvatar, null));
      // Without any avatar: none, never the cover (3.x's fallback).
      final bare = _parseRoom(_changed((root) => _section(root, 'roominfo').remove('uoption')));
      expect((bare.avatar, SixRoomApi.liveRoom(bare).avatar), ('', ''));
      expect(bare.cover, isNotEmpty);
    });

    test("3.x's own inroom fixtures", () {
      final room = SixRoomApi.room(_legacyLiveRoomJson, roomId: '8838', userId: '56182128');
      expect(room.state, SixRoomState.live);
      expect(room.followers, 425585);
      expect((room.stream!.resolution, room.stream!.bitrate), ('1024x768', 2653));
      expect('${room.stream!.url}', endsWith('/v56182128-222415076.flv'));
      expect(room.avatar, 'https://vi1.6rooms.com/live/avatar.jpg');
      expect(SixRoomApi.mediaUri(userId: '56182128', liveId: '222415076', flvTitle: 'v99999999-222415076'), isNull);
      final offline = SixRoomApi.room(_legacyOfflineRoomJson, roomId: '243126861', userId: '98073893');
      expect(offline.state, SixRoomState.offline);
      expect(offline.stream, isNull);
      expect(SixRoomApi.liveRoom(offline).area, '', reason: "no area: none, not 3.x's platform name");
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
      expect(
        SixRoomApi.roomData(private).streamError,
        isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('private')),
      );
      final room = SixRoomApi.liveRoom(private, data: SixRoomApi.roomData(private));
      expect(
        (room.liveStatus, room.restriction, room.followGroup),
        (LiveStatus.live, LiveRestriction.private, FollowGroup.live),
        reason: 'a restricted broadcast is live (M2.1; 3.x: unknown)',
      );
      expect(room.notice, '${SixRoomApi.restrictedNotice}\n${SixRoomApi.chatNotice}');
      expect(SixRoomApi.liveRoom(live).notice, SixRoomApi.chatNotice);
      expect(SixRoomApi.chatNotice, '人数是平台的热度，不是正在观看的人数。', reason: 'M5.27: chat is shown, so no "chat not shown" part');
    });

    test("enrich takes what the answer lacks from the earlier card; a broadcast's numbers only while it goes on", () {
      final card = SixRoomApi.directory(_sample('S04-home').body).firstWhere((room) => room.roomId == _live);
      final room = _parseRoom(_sample('S05-inroom-live').body).enrich(card);
      expect(room.avatar, card.avatar);
      expect(room.popularity, card.popularity, reason: 'the same broadcast 222428847 (3.x)');
      expect(room.title, _liveSignature);
      expect(room.followers, 425628);
      expect(room.stream, isNotNull);
      final search = SixRoomApi.search(_sample('S02-search').body)[1];
      final offline = _parseRoom(_sample('S05-inroom-offline').body, roomId: _offline, userId: _offlineUid);
      expect(search.enrich(offline).state, SixRoomState.offline);
      // 31-5: an ended broadcast keeps no card's popularity or start (3.x
      // kept the popularity); the followers stay.
      final ended = _parseRoom(_changed((root) => _section(root, 'liveinfo').remove('id'))).enrich(card);
      expect(
        (ended.state, ended.popularity, ended.startedAt, ended.followers),
        (SixRoomState.offline, null, null, 425628),
      );
      expect(SixRoomApi.liveRoom(ended).popularity, '');
      // Another broadcast neither.
      final later = _parseRoom(
        _changed((root) {
          _section(root, 'liveinfo')
            ..['id'] = '222428999'
            ..['flvtitle'] = 'v$_liveUid-222428999'
            ..remove('starttime');
        }),
      ).enrich(card);
      expect((later.state, later.popularity, later.startedAt), (SixRoomState.live, null, null));
      // A card of the same broadcast takes the start a room gave.
      final bareCard = SixRoomApi.directory(
        _withRows([
          {'rid': _live, 'uid': _liveUid, 'liveid': '222428847', 'username': 'x'},
        ]),
      ).single;
      expect(bareCard.enrich(_parseRoom(_sample('S05-inroom-live').body)).startedAt, _liveStart);
      // A restriction stays with its broadcast.
      final private = _parseRoom(_changed((root) => _content(root)['isPriveRoom'] = 1));
      expect(bareCard.enrich(private).restriction, LiveRestriction.private);
      expect(
        SixRoomApi.directory(
          _withRows([
            {'rid': _live, 'uid': _liveUid, 'liveid': '222428999', 'username': 'x'},
          ]),
        ).single.enrich(private).restriction,
        isNull,
      );
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
        expect(() => SixRoomApi.subarea('', status: status), throwsA(matcher), reason: '$status');
      }
      expect(SixRoomApi.search(_sample('S02-search-empty').body, status: 204), isEmpty);
      final large = '<html>${'x' * SixRoomApi.responseLimit}</html>';
      expect(() => SixRoomApi.search(large), _throwsA<ApiChanged>());
      final wide = '<html>${'六' * (SixRoomApi.responseLimit ~/ 3 + 1)}</html>';
      expect(() => SixRoomApi.search(wide), _throwsA<ApiChanged>(), reason: 'counted in UTF-8 bytes');
    });
  });
}
