// 17LIVE parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/17live/legacy_expected.dart from 3.x's SeventeenLiveApi,
// SeventeenLiveLink and SeventeenLiveSite). Every intended difference is
// listed with its reason (M4.33 differences, and the M4.U rows 33-1 to 33-7
// of docs/specs/UPGRADES.md); everything else must match. The synthetic cases
// port 3.x's seventeenlive_public_catalog_test.dart and cover the regression
// entries of the archived spec (REG-17LIVE-001–004) and the shapes 3.x
// refused. S02-sections-hk and S04-live-army (M4.U.33) have no 3.x output.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('17live', name);

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

/// The outcome of a legacy call (`{requests, value}`).
Object? _value(String name, String key) => (_legacy(name)[key] as Map<String, dynamic>)['value'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

/// 3.x put the media headers on every card (`httpHeaders`), where only
/// IPTV's are read (3.x's PlaybackHeaderResolver built 17LIVE's itself);
/// they now travel on every line.
const _headersMoved = {'httpHeaders'};

/// Keys M4.U added to a live room: `startedAt` (33-7) and `restriction`
/// (unified rule). 3.x wrote neither; they are written only when set.
const _newKeys = {'startedAt', 'restriction'};

/// Asserts that 3.x's [legacy] room has none of [_newKeys] and [room] has
/// the given ones.
void _expectNewKeys(LiveRoom room, Map<String, dynamic> legacy, {DateTime? startedAt, LiveRestriction? restriction}) {
  for (final key in _newKeys) {
    expect(legacy.containsKey(key), isFalse, reason: '3.x wrote no $key');
  }
  expect(room.startedAt, startedAt);
  expect(room.restriction, restriction);
}

/// `beginTime` of S04-live-live (1790531684).
final _liveSince = DateTime.utc(2026, 9, 27, 17, 54, 44);

/// 3.x's quality ids → the current ones (33-2), as M9 migrates them.
const _qualityIds = {'enhanced': 'enhanced', 'hd': 'hd', 'h264': 'h264', 'standard': 'source'};

/// 3.x's quality names → the current ones (33-2: 标准 is 原画).
const _qualityNames = {
  '增强高清 · FLV': '增强高清 · FLV',
  '高清 · FLV': '高清 · FLV',
  'H.264 · FLV': 'H.264 · FLV',
  '标准 · FLV': '原画 · FLV',
};

/// A 3.x pull URL as the current code gives it: always https (33-3).
String _https(Object? url) => '$url'.replaceFirst(RegExp('^http://'), 'https://');

/// 3.x's [urls] of quality [id] as the adapter gives them: over https
/// (33-3), without Wansu's H.264 transcode, which is not served (E03.18).
List<String> _served(String id, Object? urls) => [
  for (final url in urls! as List)
    if (id != 'h264' || !'$url'.contains('://wansu-')) _https(url),
];

const _live = '27484154';
const _offline = '28371376';
const _army = '376827';

LiveRoom _entered(String sample, String roomId) {
  final fixture = _sample(sample);
  return SeventeenLiveApi.enteredRoom(fixture.body, roomId: roomId, status: fixture.status);
}

SeventeenLiveRoomData _data(LiveRoom room) => room.data! as SeventeenLiveRoomData;

/// A stream object as the samples have it (3.x's test fixture).
Map<String, Object?> _stream(
  int roomId, {
  int status = 2,
  Object? ownerRoomId,
  String name = 'Fixture',
  String? userId,
  Map<String, Object?> changes = const {},
  Map<String, Object?> userChanges = const {},
}) {
  final uid = userId ?? 'user-$roomId';
  return {
    'liveStreamID': roomId,
    'userID': uid,
    'status': status,
    'caption': 'Current broadcast',
    'liveViewerCount': 12,
    'viewerCount': 90,
    'coverPhoto': 'http://cdn.17app.co/snapshot/$uid.jpg',
    'userInfo': {
      'roomID': ownerRoomId,
      'userID': uid,
      'displayName': name,
      'picture': 'avatar.jpg',
      'followerCount': 80,
      ...userChanges,
    },
    ...changes,
  };
}

String _sections(List<Object?> sections, {Object? cursor = ''}) => jsonEncode({'cursor': cursor, 'sections': sections});

Map<String, Object?> _section(String id, List<Object?> streams) => {
  'id': id,
  'grids': [
    for (final stream in streams) {'type': 1, 'stream': stream},
  ],
};

List<String> _ids(Iterable<LiveRoom> rooms) => [for (final room in rooms) room.roomId];

/// A provider of `pullURLsInfo.rtmpURLs` (the Tencent CDN, as recorded).
Map<String, Object?> _provider(String host, String uid, {Map<String, Object?> changes = const {}}) => {
  'provider': 17,
  'url': 'http://$host/live/${uid}_enhance003.flv',
  'urlLowQuality': 'http://$host/live/$uid.flv',
  'webUrl': 'http://$host/live/${uid}_enhance003.flv',
  'webUrlLowQuality': 'http://$host/live/$uid.flv',
  'urlHighQuality': 'http://$host/live/$uid.flv',
  'url264': 'http://$host/live/${uid}_h264.flv',
  'urlLowBitrateHD': 'http://$host/live/${uid}_enhance003.flv',
  'urlQualityEnhancedHD': 'http://$host/live/${uid}_enhance002.flv',
  ...changes,
};

String _room(Map<String, Object?> stream) => jsonEncode(stream);

void main() {
  group('S01 sections (JP)', () {
    test('page 1: same rooms, cursor and end as 3.x', () {
      final fixture = _sample('S01-sections-jp');
      final legacy = _value('S01-sections-jp', 'getDirectoryPageAtCursor(1)')! as Map<String, dynamic>;
      final page = SeventeenLiveApi.sectionsPage(fixture.body, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      expect(_ids(page.rooms), rooms.map((room) => room['roomId']));
      expect(page.rooms, hasLength(30));
      for (final (index, room) in page.rooms.indexed) {
        _expectParity(_projection(room), rooms[index], changed: _headersMoved, reason: 'p1[$index]');
        expect(room.httpHeaders, isEmpty);
        expect(room.data, isNull, reason: 'list cards carry no playback (3.x)');
        // Section rows have no beginTime; no premiumContent is no lock.
        _expectNewKeys(room, rooms[index], restriction: LiveRestriction.none);
      }
      expect(page.nextCursor, legacy['nextCursor']);
      expect(page.hasMore, legacy['hasMore']);
      expect(
        _ids(page.rooms),
        _maps((_value('S01-sections-jp', 'getDirectoryPage(1)')! as Map)['rooms']).map((room) => room['roomId']),
      );
    });

    test('page 2 after the cursor: same rooms and end as 3.x (the group call section counts)', () {
      final fixture = _sample('S01-sections-jp-p2');
      final cursor = _legacy('S01-sections-jp-p2')['cursor'] as String;
      expect(fixture.url.queryParameters['cursor'], cursor);
      final legacy = _value('S01-sections-jp-p2', 'getDirectoryPageAtCursor(2)')! as Map<String, dynamic>;
      final page = SeventeenLiveApi.sectionsPage(fixture.body, cursor: cursor, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      expect(_ids(page.rooms), ['28571668']);
      for (final (index, room) in page.rooms.indexed) {
        _expectParity(_projection(room), rooms[index], changed: _headersMoved, reason: 'p2[$index]');
      }
      expect(page.nextCursor, isNull);
      expect(page.hasMore, isFalse);
      expect(legacy['hasMore'], isFalse);
    });

    test('the TW page through the same rules: same rooms and cursor as 3.x', () {
      final fixture = _sample('S02-sections-tw');
      final legacy = _value('S02-sections-tw', 'getDirectoryPageAtCursor(1)')! as Map<String, dynamic>;
      final page = SeventeenLiveApi.sectionsPage(fixture.body, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      expect(_ids(page.rooms), rooms.map((room) => room['roomId']));
      expect(page.rooms, hasLength(20));
      for (final (index, room) in page.rooms.indexed) {
        _expectParity(_projection(room), rooms[index], changed: _headersMoved, reason: 'tw[$index]');
        _expectNewKeys(room, rooms[index], restriction: LiveRestriction.none);
      }
      expect(page.nextCursor, legacy['nextCursor']);
      // Its two army-only rows are offline: not listed, as in 3.x.
      expect(fixture.body, contains('"premiumType": 2'));
    });

    test('33-1: the HK page (no 3.x output) through the same rules; a locked live row is listed and marked', () {
      final fixture = _sample('S02-sections-hk');
      expect(fixture.url.queryParameters['region'], 'HK');
      final page = SeventeenLiveApi.sectionsPage(fixture.body, status: fixture.status);
      expect(page.rooms, hasLength(32));
      expect(page.nextCursor, '1790628721486100100:25:20:10-mrL5rBIVbWblU1v9gn-7T0M4StQ=');
      expect(page.rooms.every((room) => room.isLiveNow), isTrue);
      final army = page.rooms.singleWhere((room) => room.roomId == _army);
      expect(army.liveStatus, LiveStatus.live, reason: 'a locked live stays live (unified rule)');
      expect(army.restriction, LiveRestriction.subscribersOnly, reason: 'premiumType 2, ARMY');
      expect(army.isRestricted, isTrue);
      expect(army.followGroup, FollowGroup.live);
      expect(page.rooms.where((room) => room.restriction != LiveRestriction.none), [army]);
      expect(page.rooms.map((room) => room.startedAt).toSet(), {null}, reason: 'section rows have no beginTime');
    });

    test("cards as 3.x's _card: age notice, no owner roomID needed, current viewers only", () {
      final fixture = _sample('S01-sections-jp');
      final room = SeventeenLiveApi.sectionsPage(fixture.body).rooms.first;
      expect(room.platform, '17live');
      expect(room.roomId, '29759207');
      expect(room.userId, 'e5317d38-5be7-4a16-864d-73503090c5f7');
      expect(room.link, 'https://17.live/en/live/29759207');
      expect(room.notice, '17LIVE 要求观看者年满 18 周岁。');
      expect(room.liveStatus, LiveStatus.live);
      expect(room.audienceMetricType, AudienceMetricType.onlineViewers);
      expect(room.onlineViewers, '5');
      expect(room.totalViewers, '', reason: 'the rows have no viewerCount');
      expect(room.followers, '', reason: 'the rows have no followerCount');
      expect(room.watching, '');
      expect(room.area, '');
      expect(room.cover, startsWith('https://cdn.17app.co/snapshot/'));
      expect(room.avatar, startsWith('https://cdn.17app.co/'));
    });

    test("3.x's catalog test: banners skipped, live rows once, a row of another owner dropped", () {
      final body = _sections([
        _section('TopBanner', [_stream(1)]),
        _section('Label', [
          _stream(2),
          _stream(2),
          _stream(3, status: 0),
          _stream(3),
          _stream(4, userId: 'owner')..['userID'] = 'other',
        ]),
      ], cursor: 'opaque:cursor/one=');
      final page = SeventeenLiveApi.sectionsPage(body);
      expect(_ids(page.rooms), ['2', '3']);
      expect(page.rooms.first.onlineViewers, '12');
      expect(page.rooms.first.totalViewers, '90');
      expect(page.rooms.first.followers, '80');
      expect(page.rooms.first.cover, 'https://cdn.17app.co/snapshot/user-2.jpg');
      expect(page.nextCursor, 'opaque:cursor/one=');
      expect(page.hasMore, isTrue);
      final last = SeventeenLiveApi.sectionsPage(
        _sections([
          _section('Latest', [_stream(5)]),
        ]),
      );
      expect(_ids(last.rooms), ['5']);
      expect(last.hasMore, isFalse);
    });

    test('archive and VOD sections are skipped, others (group call, PK) are read (3.x)', () {
      final body = _sections([
        _section('ArchiveVideo', [_stream(1)]),
        _section('Vod', [_stream(2)]),
        _section('ArchiveClip', [_stream(3)]),
        _section('GroupCall', [_stream(4)]),
        _section('PK', [_stream(5)]),
      ]);
      expect(_ids(SeventeenLiveApi.sectionsPage(body).rooms), ['3', '4', '5']);
      expect(SeventeenLiveApi.skippedSections, {'TopBanner', 'ArchiveVideo', 'Vod'});
    });

    test("a row is dropped for anything 3.x's _room refused (list content as 3.x)", () {
      final rows = [
        _stream(10),
        _stream(11, ownerRoomId: 99),
        _stream(12, ownerRoomId: 'x'),
        _stream(13, userChanges: {'displayName': '', 'openID': ''}),
        _stream(14, userChanges: {'displayName': 7}),
        _stream(15, userChanges: {'followerCount': -1}),
        _stream(16, changes: {'caption': 5}),
        _stream(17, changes: {'liveViewerCount': 'many'}),
        _stream(18, userChanges: {'bio': false}),
        _stream(19, changes: {'userID': ' '}),
        _stream(20, changes: {'userInfo': null}),
        _stream(21, changes: {'status': 1}),
        _stream(22, changes: {'liveStreamID': 0}),
        _stream(23, userChanges: {'displayName': '', 'openID': 'open-23'}),
        _stream(24, ownerRoomId: 24),
      ];
      final page = SeventeenLiveApi.sectionsPage(_sections([_section('Label', rows)]));
      expect(_ids(page.rooms), ['10', '23', '24']);
      expect(page.rooms[1].nick, 'open-23');
    });

    test('unlike 3.x, a section or grid that is not an object is skipped, not the page', () {
      final body = jsonEncode({
        'cursor': null,
        'sections': [
          'banner',
          {'id': 'Label', 'grids': 'none'},
          {
            'id': 'Label',
            'grids': [
              3,
              {'stream': null},
              {'stream': 'x'},
              {'stream': _stream(7)},
            ],
          },
          {'id': 'Latest'},
        ],
      });
      final page = SeventeenLiveApi.sectionsPage(body);
      expect(_ids(page.rooms), ['7']);
      expect(page.hasMore, isFalse);
    });

    test('the cursor: repeated or empty ends; not text, too long or with a control character is ApiChanged', () {
      expect(SeventeenLiveApi.sectionsPage(_sections(const [], cursor: 'a'), cursor: 'a').nextCursor, isNull);
      expect(SeventeenLiveApi.sectionsPage(_sections(const [])).hasMore, isFalse);
      for (final cursor in [12, 'x' * 513, 'a\nb']) {
        expect(
          () => SeventeenLiveApi.sectionsPage(_sections(const [], cursor: cursor)),
          throwsA(isA<ApiChanged>()),
          reason: '$cursor',
        );
      }
      expect(() => SeventeenLiveApi.sectionsPage('[]'), throwsA(isA<ApiChanged>()));
      expect(() => SeventeenLiveApi.sectionsPage('{"sections":{}}'), throwsA(isA<ApiChanged>()));
    });

    test("checkCursor and sectionsQuery: 3.x's request; a region's (33-1)", () {
      expect(SeventeenLiveApi.sectionsQuery(null), {'count': '20', 'typeTab': '2', 'region': 'JP', 'cursor': ''});
      expect(SeventeenLiveApi.sectionsQuery('c')['cursor'], 'c');
      expect(SeventeenLiveApi.sectionsQuery(null, regionCode: 'TW'), {
        'count': '20',
        'typeTab': '2',
        'region': 'TW',
        'cursor': '',
      });
      SeventeenLiveApi.checkCursor(null);
      SeventeenLiveApi.checkCursor('x' * 512);
      for (final cursor in ['', 'x' * 513, 'a\u0000b']) {
        expect(() => SeventeenLiveApi.checkCursor(cursor), throwsArgumentError, reason: cursor);
      }
    });
  });

  group('catalog (33-1)', () {
    test('one category of three regions; the areas are what the directory asks for', () {
      final category = SeventeenLiveApi.category;
      expect(category.id, 'region');
      expect(category.name, '地区');
      expect(category.children.map((area) => (area.areaId, area.areaName)), [('JP', '日本'), ('TW', '台湾'), ('HK', '香港')]);
      for (final area in category.children) {
        expect(area.platform, '17live');
        expect(area.areaType, 'region');
        expect(area.typeName, '地区');
        expect(area.identityKey, isNotNull);
        expect(SeventeenLiveApi.regionOf(area), area.areaId);
        expect(SeventeenLiveApi.regionOf(LiveArea.fromJson(area.toJson())), area.areaId, reason: 'a stored area');
      }
      expect(SeventeenLiveApi.regionOf(null), 'JP', reason: 'the recommendations stay Japan (3.x)');
      expect(SeventeenLiveApi.regionOf(const LiveArea(platform: '17LIVE', areaId: ' tw ')), 'TW');
    });

    test('an area that is not a region, or of another platform, is a caller error', () {
      for (final area in [
        const LiveArea(platform: '17live', areaId: 'US'),
        const LiveArea(platform: '17live', areaId: ' '),
        const LiveArea(platform: 'showroom', areaId: 'JP'),
        const LiveArea(areaId: 'JP'),
      ]) {
        expect(() => SeventeenLiveApi.regionOf(area), throwsArgumentError, reason: '$area');
      }
    });

    test('the directory notice is written for viewers (unified rule), naming the regions', () {
      expect(SeventeenLiveApi.directoryScope, contains('日本、台湾、香港'));
      expect(SeventeenLiveApi.directoryScope, isNot(contains('原生游标')));
    });
  });

  group('S03 search', () {
    test('same cards as 3.x', () {
      final fixture = _sample('S03-search');
      final legacy = _maps(_value('S03-search', 'searchRooms'));
      final rooms = SeventeenLiveApi.searchRooms(fixture.body, status: fixture.status);
      expect(_ids(rooms), legacy.map((room) => room['roomId']));
      for (final (index, room) in rooms.indexed) {
        _expectParity(_projection(room), legacy[index], changed: _headersMoved, reason: 'search[$index]');
        // Search rows carry beginTime (33-7) and premiumContent: null.
        _expectNewKeys(room, legacy[index], startedAt: _liveSince, restriction: LiveRestriction.none);
      }
      expect(rooms.single.totalViewers, '1138');
      expect(rooms.single.followers, '2775');
      final none = _sample('S03-search-none');
      expect(SeventeenLiveApi.searchRooms(none.body), isEmpty);
      expect(_value('S03-search-none', 'searchRooms'), isEmpty);
    });

    test("3.x's search test: live rows named by their owner, once", () {
      final rooms = SeventeenLiveApi.searchRooms(
        jsonEncode([
          _stream(123, ownerRoomId: 123, name: 'あかり'),
          _stream(123, ownerRoomId: 123),
          _stream(124, status: 0, ownerRoomId: 124),
          _stream(125, ownerRoomId: 999),
          _stream(125, ownerRoomId: 125),
          _stream(126, ownerRoomId: 126, userId: 'valid')..['userID'] = 'other',
          _stream(127),
          'row',
        ]),
      );
      expect(_ids(rooms), ['123', '125']);
      expect(rooms.first.nick, 'あかり');
      expect(rooms.first.onlineViewers, '12');
      expect(rooms.first.totalViewers, '90');
      expect(rooms.first.data, isNull);
      expect(() => rooms.add(rooms.first), throwsUnsupportedError);
    });

    test('an answer that is not a list is ApiChanged', () {
      expect(() => SeventeenLiveApi.searchRooms('{}'), throwsA(isA<ApiChanged>()));
      expect(() => SeventeenLiveApi.searchRooms('<html>'), throwsA(isA<ApiChanged>()));
    });

    test('33-5: the keyword is trimmed and cut to 100 UTF-16 units, never inside a surrogate pair', () {
      expect(SeventeenLiveApi.searchKeyword('  Re:Zero '), 'Re:Zero');
      expect(SeventeenLiveApi.searchKeyword('x' * 101), 'x' * 100);
      expect(SeventeenLiveApi.searchKeyword('x' * 100), 'x' * 100);
      expect(SeventeenLiveApi.searchKeyword('${'x' * 99}😀tail'), 'x' * 99, reason: 'the pair is not split');
      expect(SeventeenLiveApi.searchKeyword('${'x' * 98}😀tail'), '${'x' * 98}😀');
      expect(SeventeenLiveApi.searchKeyword('${'x' * 99} tail'), 'x' * 99, reason: 'trimmed again');
      expect(SeventeenLiveApi.searchKeyword('   '), '');
    });

    test('33-5: only a web address (<scheme>://) is not a keyword; a colon is (3.x: any URI scheme)', () {
      for (final text in ['https://other.test/live/1', 'HTTP://17.live/', ' ftp://x ', 'app+x.y-z://open', 'a://']) {
        expect(SeventeenLiveApi.isUrl(text), isTrue, reason: text);
      }
      for (final text in ['Re:Zero', 'mailto:someone', '12:30', 'https:/x', '1a://x', '花音']) {
        expect(SeventeenLiveApi.isUrl(text), isFalse, reason: text);
      }
    });
  });

  group('S04 rooms', () {
    test('live: entry, refresh and recording rooms as 3.x, with the start time (33-7) and no lock', () {
      final fixture = _sample('S04-live-live');
      for (final key in ['getRoomDetail', 'getRoomDetailForRecording']) {
        final legacy = _value('S04-live-live', key)! as Map<String, dynamic>;
        final entered = _entered('S04-live-live', _live);
        _expectParity(_projection(entered), legacy, changed: _headersMoved, reason: key);
        _expectNewKeys(entered, legacy, startedAt: _liveSince, restriction: LiveRestriction.none);
        expect(entered.danmakuData, const SeventeenLiveDanmakuArgs(roomId: _live), reason: '33-4');
      }
      final refreshed = SeventeenLiveApi.refreshRoom(fixture.body, roomId: _live);
      final legacyRefresh = _value('S04-live-live', 'getRoomDetailForRefresh')! as Map<String, dynamic>;
      _expectParity(_projection(refreshed), legacyRefresh, changed: _headersMoved);
      _expectNewKeys(refreshed, legacyRefresh, startedAt: _liveSince, restriction: LiveRestriction.none);
      expect(refreshed.toJson()['startedAt'], '2026-09-27T17:54:44.000Z');
      expect(refreshed.toJson()['restriction'], 'none');
      expect(refreshed.danmakuData, isNull, reason: 'a refresh is a card');
      expect(refreshed.data, isNull);
      expect(refreshed.onlineViewers, '108');
      expect(refreshed.totalViewers, '1138');
      expect(refreshed.followers, '2775');
      expect(refreshed.introduction, startsWith('皆さんのお力で'));
      expect(_value('S04-live-live', 'getLiveStatus'), isTrue);
    });

    test("live: 3.x's four qualities renamed and reordered (33-2), every URL as 3.x's over https (33-3)", () {
      final data = _data(_entered('S04-live-live', _live));
      expect(data.roomId, _live);
      expect(data.userId, '20015b43-ab03-43d8-a37e-32250131d6bc');
      expect(data.unavailable, isNull);
      final legacy = _maps(_value('S04-live-live', 'getPlayQualites'));
      expect(legacy.map((q) => q['quality']), ['增强高清 · FLV', '高清 · FLV', 'H.264 · FLV', '标准 · FLV']);
      // changed: names, ids, order and 原画's sort (33-2). Each of 3.x's
      // qualities is one quality now, through the id and name maps.
      expect(data.qualities.map((q) => q.quality), ['原画 · FLV', '增强高清 · FLV', '高清 · FLV', 'H.264 · FLV']);
      expect(data.qualities.map((q) => q.id), ['source', 'enhanced', 'hd', 'h264']);
      expect(data.qualities.map((q) => q.sort), [500, 400, 300, 200]);
      for (final old in legacy) {
        final id = SeventeenLiveApi.qualityIdFromLegacy('${old['id']}');
        expect(id, _qualityIds[old['id']]);
        final current = data.qualities.singleWhere((q) => q.id == id);
        expect(current.quality, _qualityNames[old['quality']]);
        expect(current.sort, id == 'source' ? 500 : old['sort'], reason: '3.x sorted 标准 last (100)');
      }
      expect(SeventeenLiveApi.playQualities(data).map((q) => q.id), ['h264', 'source', 'enhanced', 'hd']);
      expect(SeventeenLiveApi.playQualities(data, preferH264: false).map((q) => q.id), [
        'source',
        'enhanced',
        'hd',
        'h264',
      ]);
      final urls = _legacy('S04-live-live')['getPlayUrls'] as Map<String, dynamic>;
      final resolved = _legacy('S04-live-live')['resolvePlayUrlsRaw'] as Map<String, dynamic>;
      for (final MapEntry(key: old, value: id) in _qualityIds.entries) {
        final quality = data.qualities.singleWhere((q) => q.id == id);
        final resolution = SeventeenLiveApi.resolution(data, quality);
        // changed: https (33-3); the same URLs otherwise.
        expect(resolution.urls, _served(id, (urls[old] as Map)['value']), reason: old);
        final applied = (resolved[old] as Map)['value'] as Map;
        expect(applied['appliedQualityData'], old);
        expect(resolution.appliedQualityData, id, reason: '33-2: the current id');
        expect(resolution.urls, _served(id, applied['urls']));
        expect(resolution.urls.every((url) => url.startsWith('https://')), isTrue);
        // 3.x's id still plays (a stored quality M9 did not migrate).
        final byOldId = SeventeenLiveApi.resolution(data, LivePlayQuality(quality: 'x', id: old));
        expect(byOldId.urls, resolution.urls);
        expect(byOldId.appliedQualityData, id);
      }
    });

    test('lines: media headers, FLV, one per CDN in the answer order, no lease (REG-17LIVE-002, 003)', () {
      final data = _data(_entered('S04-live-live', _live));
      final legacyHeaders = {
        for (final MapEntry(:key, :value) in (_legacy('S04-live-live')['mediaHeaders'] as Map).entries)
          '$key'.toLowerCase(): value,
      };
      for (final quality in data.qualities) {
        final lines = quality.data! as List<LivePlayLine>;
        expect(
          lines.map((line) => line.lineId),
          quality.id == 'h264' ? ['tencent'] : ['tencent', 'wansu'],
          reason: "the first CDN serves; Wansu's H.264 is not served (E03.18)",
        );
        for (final line in lines) {
          expect(line.headers, legacyHeaders);
          expect(line.headers['referer'], 'https://17.live/en/live/$_live');
          expect(line.format, StreamFormat.flv);
          expect(line.lease, isNull);
          expect(line.codec, quality.id == 'h264' ? 'avc' : isNull, reason: 'REG-17LIVE-001');
        }
      }
      final tencent = (data.qualities.first.data! as List<LivePlayLine>).first.url;
      final recorded = _sample('S04-live-live').body;
      expect(recorded, contains(tencent.replaceFirst('https://', 'http://')), reason: 'recorded over http');
      // changed: 3.x played the Tencent CDN over http, as given (33-3).
      expect(tencent, startsWith('https://tencent-global-pull-rtmp.17app.co/'));
    });

    test('S04-live-wansu (E03.18): Wansu serves first; no H.264 (its url264 is not served), 原画 plays first', () {
      final data = _data(_entered('S04-live-wansu', '29167718'));
      expect(data.unavailable, isNull);
      final recorded = jsonDecode(_sample('S04-live-wansu').body) as Map<String, dynamic>;
      final providers = ((recorded['pullURLsInfo'] as Map)['rtmpURLs'] as List).cast<Map<String, dynamic>>();
      expect(providers.map((provider) => provider['provider']), [5, 17], reason: 'Wansu first');
      expect(providers.first['url264'], isNotEmpty, reason: 'the field is there, the stream is not');
      expect(data.qualities.map((q) => q.id), ['source', 'enhanced', 'hd']);
      expect(SeventeenLiveApi.playQualities(data).map((q) => q.id), ['source', 'enhanced', 'hd']);
      for (final quality in data.qualities) {
        final lines = quality.data! as List<LivePlayLine>;
        expect(lines.map((line) => line.lineId), ['wansu', 'tencent'], reason: 'the first CDN serves');
      }
    });

    test('offline: rooms as 3.x; no stream (3.x gave an empty quality list)', () {
      final fixture = _sample('S04-live-offline');
      final entered = _entered('S04-live-offline', _offline);
      _expectParity(
        _projection(entered),
        _value('S04-live-offline', 'getRoomDetail')! as Map<String, dynamic>,
        changed: _headersMoved,
      );
      _expectParity(
        _projection(SeventeenLiveApi.refreshRoom(fixture.body, roomId: _offline)),
        _value('S04-live-offline', 'getRoomDetailForRefresh')! as Map<String, dynamic>,
        changed: _headersMoved,
      );
      expect(entered.liveStatus, LiveStatus.offline);
      expect(entered.onlineViewers, '', reason: "the last broadcast's counts are not shown");
      expect(entered.totalViewers, '');
      expect(fixture.body, contains('"beginTime": 1790508495'));
      _expectNewKeys(
        entered,
        _value('S04-live-offline', 'getRoomDetail')! as Map<String, dynamic>,
        // Neither is filled offline: beginTime is the last broadcast's.
      );
      expect(entered.danmakuData, const SeventeenLiveDanmakuArgs(roomId: _offline), reason: 'the channel stays');
      expect(_value('S04-live-offline', 'getPlayQualites'), isEmpty);
      expect(() => SeventeenLiveApi.playQualities(_data(entered)), throwsA(isA<StreamUnavailable>()));
      expect(_value('S04-live-offline', 'getLiveStatus'), isFalse);
    });

    test('an unknown room (HTTP 520 stream not found) is NotFound (REG-17LIVE-004; 3.x said service)', () {
      final fixture = _sample('S04-live-notfound');
      expect(fixture.status, 520);
      expect(
        () => SeventeenLiveApi.refreshRoom(fixture.body, roomId: '999999999', status: fixture.status),
        throwsA(isA<NotFound>()),
      );
      expect(
        () => SeventeenLiveApi.enteredRoom(fixture.body, roomId: '999999999', status: fixture.status),
        throwsA(isA<NotFound>()),
      );
      expect((_value('S04-live-notfound', 'getRoomDetail')! as Map)['message'], '17LIVE service');
    });

    test("3.x's identity rules: the owner's roomID is required, the room and user must match", () {
      String answer(Map<String, Object?> stream) => _room(stream);
      expect(
        () => SeventeenLiveApi.refreshRoom(answer(_stream(123)), roomId: '123'),
        throwsA(isA<ApiChanged>()),
        reason: '3.x: strict owner room identity even when directory summaries omit it',
      );
      for (final stream in [
        _stream(124, ownerRoomId: 124),
        _stream(123, ownerRoomId: 124),
        _stream(123, ownerRoomId: 123)..['userID'] = 'other',
        _stream(123, ownerRoomId: 123, changes: {'userInfo': 'x'}),
        _stream(123, ownerRoomId: 123, changes: {'userID': null}),
      ]) {
        expect(
          () => SeventeenLiveApi.enteredRoom(answer(stream), roomId: '123'),
          throwsA(isA<ApiChanged>()),
          reason: '$stream',
        );
      }
      final room = SeventeenLiveApi.refreshRoom(answer(_stream(123, ownerRoomId: '123')), roomId: '123');
      expect(room.roomId, '123');
      expect(() => SeventeenLiveApi.refreshRoom('[]', roomId: '123'), throwsA(isA<ApiChanged>()));
    });

    test('a status other than live or offline is an unknown state (3.x), with no stream', () {
      final room = SeventeenLiveApi.enteredRoom(_room(_stream(123, ownerRoomId: 123, status: 1)), roomId: '123');
      expect(room.liveStatus, LiveStatus.unknown);
      expect(room.onlineViewers, '');
      expect(() => SeventeenLiveApi.playQualities(_data(room)), throwsA(isA<ApiChanged>()));
    });

    test('unlike 3.x, a room field that is not as expected is left empty instead of failing the room', () {
      final room = SeventeenLiveApi.refreshRoom(
        _room(
          _stream(
            123,
            ownerRoomId: 123,
            changes: {'caption': 5, 'liveViewerCount': -1, 'viewerCount': 'x'},
            userChanges: {'displayName': 7, 'openID': 'open', 'followerCount': -3, 'bio': false},
          ),
        ),
        roomId: '123',
      );
      expect(room.nick, 'open');
      expect(room.title, 'open');
      expect(room.onlineViewers, '');
      expect(room.totalViewers, '');
      expect(room.followers, '');
      expect(room.introduction, '');
      final nameless = SeventeenLiveApi.refreshRoom(
        _room(_stream(123, ownerRoomId: 123, userChanges: {'displayName': null})),
        roomId: '123',
      );
      expect(nameless.nick, '');
      expect(nameless.title, 'Current broadcast');
    });

    test('audio rooms: the area 3.x showed', () {
      final room = SeventeenLiveApi.refreshRoom(
        _room(_stream(123, ownerRoomId: 123, changes: {'audioOnly': 1})),
        roomId: '123',
      );
      expect(room.area, '音频直播');
      expect(
        SeventeenLiveApi.refreshRoom(
          _room(_stream(123, ownerRoomId: 123, changes: {'audioOnly': '0'})),
          roomId: '123',
        ).area,
        '',
      );
    });

    test('an army-only live (S04-live-army, no 3.x output): live and marked, its pull URLs not played', () {
      final fixture = _sample('S04-live-army');
      expect(fixture.body, contains('tencent-global-pull-rtmp'), reason: 'the answer carries pull URLs');
      final entered = SeventeenLiveApi.enteredRoom(fixture.body, roomId: _army, status: fixture.status);
      final refreshed = SeventeenLiveApi.refreshRoom(fixture.body, roomId: _army);
      for (final room in [entered, refreshed]) {
        expect(room.liveStatus, LiveStatus.live);
        expect(room.restriction, LiveRestriction.subscribersOnly);
        expect(room.followGroup, FollowGroup.live);
        expect(room.startedAt, DateTime.utc(2026, 9, 28, 20, 46, 5), reason: 'beginTime 1790628365');
        expect(room.onlineViewers, '1');
      }
      final data = _data(entered);
      expect(data.qualities, isEmpty, reason: 'the website locks it; 3.x played it');
      expect(
        () => SeventeenLiveApi.playQualities(data),
        throwsA(isA<StreamUnavailable>().having((e) => e.detail, 'detail', contains('army members'))),
      );
      expect(entered.danmakuData, const SeventeenLiveDanmakuArgs(roomId: _army));
    });

    test("restrictions: premiumContent by the website's isLocked rule, only while live", () {
      Map<String, Object?> premium(Object? type, {bool paid = false}) => {
        'premiumType': type,
        'price': 0,
        'paymentInfo': {'paid': paid},
      };
      for (final (content, expected) in <(Object?, LiveRestriction?)>[
        (null, LiveRestriction.none),
        (premium(0), LiveRestriction.none),
        (premium(null), LiveRestriction.none),
        (premium(1), LiveRestriction.paid),
        (premium('1'), LiveRestriction.paid),
        (premium(2), LiveRestriction.subscribersOnly),
        (premium(3), LiveRestriction.unplayable),
        (premium(9), LiveRestriction.unplayable),
        (premium(2, paid: true), LiveRestriction.none),
        ({'premiumType': 1}, LiveRestriction.paid),
        ('locked', null),
        (const [1], null),
      ]) {
        expect(SeventeenLiveApi.restrictionOf(content), expected, reason: '$content');
        final answer = _stream(123, ownerRoomId: 123, changes: {'premiumContent': content});
        expect(SeventeenLiveApi.refreshRoom(_room(answer), roomId: '123').restriction, expected, reason: '$content');
        final row = SeventeenLiveApi.searchRooms(jsonEncode([answer])).single;
        expect(row.restriction, expected, reason: 'a list row keeps its lock: $content');
      }
      final offline = _stream(123, ownerRoomId: 123, status: 0, changes: {'premiumContent': premium(2)});
      expect(SeventeenLiveApi.refreshRoom(_room(offline), roomId: '123').restriction, isNull);
      final unknown = _stream(123, ownerRoomId: 123, status: 1, changes: {'premiumContent': premium(2)});
      expect(SeventeenLiveApi.refreshRoom(_room(unknown), roomId: '123').restriction, isNull);
    });

    test('a locked live names its lock when played; one that cannot be read plays, as 3.x', () {
      for (final (type, text) in [(1, 'premium live'), (2, 'army members'), (3, 'locked live (unplayable)')]) {
        final room = SeventeenLiveApi.enteredRoom(
          _room(
            _stream(
              123,
              ownerRoomId: 123,
              userId: 'uid',
              changes: {
                'premiumContent': {'premiumType': type},
                'pullURLsInfo': {
                  'rtmpURLs': [_provider('tencent-global-pull-rtmp.17app.co', 'uid')],
                },
              },
            ),
          ),
          roomId: '123',
        );
        expect(room.isLiveNow, isTrue);
        expect(
          () => SeventeenLiveApi.playQualities(_data(room)),
          throwsA(isA<StreamUnavailable>().having((e) => e.detail, 'detail', contains(text))),
          reason: '$type',
        );
      }
      final unreadable = SeventeenLiveApi.enteredRoom(
        _room(
          _stream(
            123,
            ownerRoomId: 123,
            userId: 'uid',
            changes: {
              'premiumContent': 'x',
              'pullURLsInfo': {
                'rtmpURLs': [_provider('tencent-global-pull-rtmp.17app.co', 'uid')],
              },
            },
          ),
        ),
        roomId: '123',
      );
      expect(unreadable.restriction, isNull);
      expect(SeventeenLiveApi.playQualities(_data(unreadable)), hasLength(4));
    });

    test('33-7: beginTime while live, Unix seconds in 2000–2100; nothing offline or unreadable', () {
      DateTime? started(Object? begin, {int status = 2}) => SeventeenLiveApi.refreshRoom(
        _room(_stream(123, ownerRoomId: 123, status: status, changes: {'beginTime': begin})),
        roomId: '123',
      ).startedAt;
      expect(started(1790531684), _liveSince);
      expect(started(1790531684, status: 0), isNull);
      for (final begin in [null, 0, -1, '1790531684', 1790531684.0, 946684799, 4102444801, true]) {
        expect(started(begin), isNull, reason: '$begin');
      }
      expect(SeventeenLiveApi.startTime(946684800), DateTime.utc(2000));
      final row = SeventeenLiveApi.sectionsPage(
        _sections([
          _section('Label', [
            _stream(5, changes: {'beginTime': 1790531684}),
          ]),
        ]),
      ).rooms.single;
      expect(row.startedAt, _liveSince, reason: 'a section row with beginTime has it too');
    });
  });

  group('streams', () {
    Map<String, Object?> live({Object? providers, Object? fallback, bool withPull = true}) => _stream(
      123,
      ownerRoomId: 123,
      userId: 'uid',
      changes: {
        'pullURLsInfo': ?(withPull ? {'rtmpURLs': providers} : null),
        'rtmpUrls': fallback,
      },
    );

    const tencent = 'tencent-global-pull-rtmp.17app.co';
    const wansu = 'wansu-global-pull-rtmp-latency.17app.co';

    List<LivePlayQuality> offered(Map<String, Object?> answer) =>
        _data(SeventeenLiveApi.enteredRoom(_room(answer), roomId: '123')).qualities;

    test('a live room without any pull URL is entered; its stream says why (3.x failed the entry)', () {
      for (final answer in [
        live(providers: const []),
        live(withPull: false),
        live(
          providers: [
            {'url': 'rtmp://x/live/a.flv', 'url264': ''},
          ],
        ),
      ]) {
        final room = SeventeenLiveApi.enteredRoom(_room(answer), roomId: '123');
        expect(room.isLiveNow, isTrue);
        expect(() => SeventeenLiveApi.playQualities(_data(room)), throwsA(isA<StreamUnavailable>()));
      }
    });

    test('unified rule "容错": pull data 3.x could not read no longer fails the entry; a bad part loses itself', () {
      // Nothing readable: the room is entered (3.x failed it), playing it is
      // ApiChanged naming what was skipped; the refresh is not affected.
      for (final answer in [
        live(providers: 'x'),
        live(providers: ['x']),
        live(
          providers: [
            {'provider': 17, 'url264': 5},
          ],
        ),
      ]) {
        final room = SeventeenLiveApi.enteredRoom(_room(answer), roomId: '123');
        expect(room.isLiveNow, isTrue);
        expect(() => SeventeenLiveApi.playQualities(_data(room)), throwsA(isA<ApiChanged>()), reason: '$answer');
        expect(SeventeenLiveApi.refreshRoom(_room(answer), roomId: '123').isLiveNow, isTrue);
      }
      // A bad provider or field loses only itself (3.x: the whole room).
      final skipped = <String>[];
      final qualities = SeventeenLiveApi.qualities(
        live(
          providers: [
            'x',
            _provider(tencent, 'uid', changes: {'url264': 5}),
            _provider(wansu, 'uid'),
          ],
        ),
        roomId: '123',
        skipped: skipped,
      );
      expect(skipped, ['provider 0 is not an object', 'provider 1: url264 is not text']);
      expect(qualities.map((q) => q.id), [
        'source',
        'enhanced',
        'hd',
      ], reason: "Tencent's H.264 field was bad and Wansu's H.264 is not served (E03.18)");
      final source = qualities.first.data! as List<LivePlayLine>;
      expect(source.map((line) => line.lineId), ['tencent', 'wansu']);
      // More than 16 providers: the first 16 are read (3.x refused them all).
      final many = <String>[];
      expect(
        SeventeenLiveApi.qualities(
          live(providers: List.filled(17, _provider(tencent, 'uid'))),
          roomId: '123',
          skipped: many,
        ),
        hasLength(4),
      );
      expect(many, ['1 providers over 16']);
    });

    test('E03.18: H.264 is offered only when the first provider (the one serving) is not Wansu, '
        'and never from Wansu', () {
      // Wansu first: its url264 is not served (404 or no data), and Tencent
      // does not serve while Wansu does; no H.264, 原画 plays first.
      final wansuFirst = offered(live(providers: [_provider(wansu, 'uid'), _provider(tencent, 'uid')]));
      expect(wansuFirst.map((q) => q.id), ['source', 'enhanced', 'hd']);
      final data = _data(
        SeventeenLiveApi.enteredRoom(
          _room(live(providers: [_provider(wansu, 'uid'), _provider(tencent, 'uid')])),
          roomId: '123',
        ),
      );
      expect(SeventeenLiveApi.playQualities(data).first.id, 'source');
      // Tencent first: its transcode serves; Wansu's url264 is left out.
      final tencentFirst = offered(live(providers: [_provider(tencent, 'uid'), _provider(wansu, 'uid')]));
      expect(tencentFirst.map((q) => q.id), ['source', 'enhanced', 'hd', 'h264']);
      final h264 = tencentFirst.last.data! as List<LivePlayLine>;
      expect(h264.map((line) => line.lineId), ['tencent']);
      // Wansu alone: nothing to transcode.
      expect(offered(live(providers: [_provider(wansu, 'uid')])).map((q) => q.id), ['source', 'enhanced', 'hd']);
    });

    test('rtmpUrls when there is no pullURLsInfo; an empty rtmpURLs list is not replaced (3.x)', () {
      final fallback = offered(live(withPull: false, fallback: [_provider(tencent, 'uid')]));
      expect(fallback.map((q) => q.id), ['source', 'enhanced', 'hd', 'h264']);
      expect(() => offered(live(providers: const [], fallback: [_provider(tencent, 'uid')])), returnsNormally);
      expect(offered(live(providers: const [], fallback: [_provider(tencent, 'uid')])), isEmpty);
    });

    test("every field of every provider is a line, each URL once (3.x's _streams)", () {
      final qualities = offered(
        live(
          providers: [
            _provider(
              tencent,
              'uid',
              changes: {'url': 'http://$tencent/live/uid_other.flv', 'urlLowBitrateHD': null, 'urlHighQuality': ''},
            ),
            _provider(wansu, 'uid'),
            _provider(wansu, 'uid'),
          ],
        ),
      );
      final hd = qualities.firstWhere((q) => q.id == 'hd').data! as List<LivePlayLine>;
      expect(hd.map((line) => line.url), [
        'https://$tencent/live/uid_enhance003.flv',
        'https://$tencent/live/uid_other.flv',
        'https://$wansu/live/uid_enhance003.flv',
      ]);
      final source = qualities.firstWhere((q) => q.id == 'source').data! as List<LivePlayLine>;
      expect(source.map((line) => line.lineId), ['tencent', 'wansu']);
    });

    test('an http and an https URL of the same stream are one line (33-3)', () {
      final qualities = offered(
        live(
          providers: [
            _provider(tencent, 'uid', changes: {'urlHighQuality': 'https://$tencent/live/uid.flv'}),
          ],
        ),
      );
      final source = qualities.first.data! as List<LivePlayLine>;
      expect(source.map((line) => line.url), ['https://$tencent/live/uid.flv']);
    });

    test('a quality with no URL is left out, best first', () {
      final qualities = offered(
        live(
          providers: [
            _provider(tencent, 'uid', changes: {'urlQualityEnhancedHD': null, 'url264': ''}),
          ],
        ),
      );
      expect(qualities.map((q) => q.id), ['source', 'hd']);
      expect(qualities.map((q) => q.sort), [500, 300]);
      final data = _data(
        SeventeenLiveApi.enteredRoom(_room(live(providers: [_provider(tencent, 'uid')])), roomId: '123'),
      );
      expect(SeventeenLiveApi.playQualities(data).map((q) => q.id), ['h264', 'source', 'enhanced', 'hd']);
      final noH264 = _data(
        SeventeenLiveApi.enteredRoom(
          _room(
            live(
              providers: [
                _provider(tencent, 'uid', changes: {'url264': null}),
              ],
            ),
          ),
          roomId: '123',
        ),
      );
      expect(SeventeenLiveApi.playQualities(noH264).map((q) => q.id), [
        'source',
        'enhanced',
        'hd',
      ], reason: 'without the transcode, 原画 is the default either way');
    });

    test("pullUrl: an .flv on a *pull-rtmp*.17app.co host (3.x's _mediaUri), always https (33-3)", () {
      for (final (url, expected) in [
        ('http://tencent-global-pull-rtmp.17app.co/live/a.flv', 'https://tencent-global-pull-rtmp.17app.co/live/a.flv'),
        ('HTTP://Tencent-Global-Pull-Rtmp.17app.co/live/a.flv', 'https://tencent-global-pull-rtmp.17app.co/live/a.flv'),
        ('http://pull-rtmp.17app.co:80/a.flv?t=1&u=2', 'https://pull-rtmp.17app.co/a.flv?t=1&u=2'),
        ('http://pull-rtmp.17app.co:8080/a.flv', 'http://pull-rtmp.17app.co:8080/a.flv'),
        ('https://wansu-global-pull-rtmp-latency.17app.co/vod/a.FLV', null),
        ('https://pull-rtmp.17app.co/a.flv?t=1', null),
        ('https://pull-rtmp.17app.co:8443/a.flv', null),
      ]) {
        expect(SeventeenLiveApi.pullUrl(url).toString(), expected ?? url, reason: url);
      }
      for (final url in [
        '',
        'rtmp://tencent-global-pull-rtmp.17app.co/live/a.flv',
        'https://tencent-global-pull-rtmp.17app.co/live/a.m3u8',
        'https://cdn.17app.co/live/a.flv',
        'https://pull-rtmp.17app.co.evil.test/a.flv',
        'https://user@pull-rtmp.17app.co/a.flv',
        'https://pull-rtmp.17app.co/a.flv#x',
        'https://pull-rtmp.17app.co/a b.flv',
        'https://pull-rtmp.17app.co/a.flv\n',
      ]) {
        expect(SeventeenLiveApi.pullUrl(url), isNull, reason: url);
      }
    });

    test('resolution: the asked quality applied; another is StreamUnavailable (3.x mediaUnavailable)', () {
      final data = _data(_entered('S04-live-live', _live));
      final h264 = data.qualities.firstWhere((q) => q.id == 'h264');
      final resolution = SeventeenLiveApi.resolution(data, h264);
      expect(resolution.appliedQualityData, 'h264');
      expect(resolution.lines.every((line) => line.codec == 'avc'), isTrue);
      for (final id in ['x', 'SOURCE ', '']) {
        expect(
          () => SeventeenLiveApi.resolution(data, LivePlayQuality(quality: 'x', id: id)),
          throwsA(isA<StreamUnavailable>()),
          reason: id,
        );
      }
      // changed: 3.x's "unknown quality" was id `source`, which is 原画 now
      // (33-2).
      expect((_value('S04-live-live', 'getPlayUrls(unknown quality)')! as Map)['message'], '17LIVE mediaUnavailable');
      final source = SeventeenLiveApi.resolution(data, const LivePlayQuality(quality: 'x', id: 'source'));
      expect(source.appliedQualityData, 'source');
      expect(source.lines.map((line) => line.codec), [null, null], reason: 'the broadcaster may push HEVC');
      final byName = SeventeenLiveApi.resolution(data, const LivePlayQuality(quality: 'hd', id: 'hd'));
      expect(byName.urls, hasLength(2));
    });

    test('33-2: the id map for M9: standard is source, any case; other ids kept', () {
      expect(SeventeenLiveApi.legacyQualityIds, {'standard': 'source'});
      expect(SeventeenLiveApi.qualityIdFromLegacy('standard'), 'source');
      expect(SeventeenLiveApi.qualityIdFromLegacy(' Standard '), 'source');
      for (final id in ['source', 'enhanced', 'hd', 'h264', 'other']) {
        expect(SeventeenLiveApi.qualityIdFromLegacy(id), id);
        expect(SeventeenLiveApi.qualityIdFromLegacy(SeventeenLiveApi.qualityIdFromLegacy(id)), id);
      }
      expect(SeventeenLiveApi.qualityNames.keys, SeventeenLiveApi.qualityFields.keys);
      expect(SeventeenLiveApi.qualitySorts.keys, SeventeenLiveApi.qualityFields.keys);
    });
  });

  group('answers', () {
    test("statuses as 3.x's _fetch classed them, except 520 stream not found and 420", () {
      expect(SeventeenLiveApi.statusError(200, '', 'x'), isNull);
      for (final (status, matcher) in [
        (400, isA<ApiChanged>()),
        (420, isA<ApiChanged>()),
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (500, isA<NetworkFailure>()),
        (520, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
        (204, isA<NetworkFailure>()),
      ]) {
        expect(SeventeenLiveApi.statusError(status, '', 'x'), matcher, reason: '$status');
      }
      const notFound = '{"errorCode":0,"errorMessage":"stream not found"}';
      expect(SeventeenLiveApi.statusError(520, notFound, 'x'), isA<NotFound>());
      expect(
        SeventeenLiveApi.statusError(420, '{"errorCode":7,"errorMessage":"no such section"}', 'x'),
        isA<ApiChanged>(),
        reason: 'a refused parameter, not throttling (3.x took 420 for RateLimited)',
      );
      expect(SeventeenLiveApi.statusError(520, '{"errorMessage":"busy"}', 'x'), isA<NetworkFailure>());
    });

    test('an answer over 4 MiB or not JSON is ApiChanged', () {
      expect(() => SeventeenLiveApi.decode('x' * (4 * 1024 * 1024 + 1), what: 'x'), throwsA(isA<ApiChanged>()));
      expect(() => SeventeenLiveApi.decode('<html>', what: 'x'), throwsA(isA<ApiChanged>()));
      expect(SeventeenLiveApi.decode('[]', what: 'x'), isEmpty);
    });

    test("image: the two 17LIVE hosts or a bare file name, always https (3.x's _image)", () {
      expect(SeventeenLiveApi.image('avatar.jpg'), 'https://cdn.17app.co/avatar.jpg');
      expect(SeventeenLiveApi.image('/a/b.png'), 'https://cdn.17app.co/a/b.png');
      expect(SeventeenLiveApi.image('http://cdn.17app.co/snapshot/u?t=1'), 'https://cdn.17app.co/snapshot/u?t=1');
      expect(
        SeventeenLiveApi.image('https://assets-17app.akamaized.net/a.png'),
        'https://assets-17app.akamaized.net/a.png',
      );
      for (final value in [
        null,
        '',
        3,
        'https://evil.test/a.png',
        'https://user@cdn.17app.co/a.png',
        'https://cdn.17app.co/a.png#x',
        '../a.png',
        'a b.png',
        'ftp://cdn.17app.co/a.png',
      ]) {
        expect(SeventeenLiveApi.image(value), '', reason: '$value');
      }
    });
  });

  group('links and headers', () {
    test("roomIdFromUrl: 3.x's SeventeenLiveLink.parse on every recorded vector", () {
      final links = _legacy('S04-live-live')['links'] as Map<String, dynamic>;
      expect(links, hasLength(28));
      for (final MapEntry(key: link, value: legacy as Map<String, dynamic>) in links.entries) {
        final parse = legacy['parse'];
        if (parse is Map) {
          // 3.x threw on a path it could not decode; it is no link now.
          expect(SeventeenLiveApi.roomIdFromUrl(link), isNull, reason: link);
          continue;
        }
        if (link == 'https://www.17.live/ja/live/27484154') {
          // changed: www.17.live is the website too (33-6).
          expect(parse, isNull);
          expect(legacy['parseOrId'], isNull);
          expect(SeventeenLiveApi.roomIdFromUrl(link), _live);
          continue;
        }
        expect(SeventeenLiveApi.roomIdFromUrl(link), parse, reason: link);
        expect(SeventeenLiveApi.normalizeRoomId(link), legacy['normalizeRoomId'], reason: link);
        expect(
          SeventeenLiveApi.roomIdFromUrl(link) ?? SeventeenLiveApi.normalizeRoomId(link),
          legacy['parseOrId'],
          reason: link,
        );
      }
    });

    test('33-6: www.17.live pages are rooms, in any case; other subdomains are not', () {
      for (final link in [
        'https://www.17.live/ja/live/$_live',
        'http://WWW.17.LIVE/live/$_live',
        'https://www.17.live/zh-Hant/profile/r/$_live',
        'https://www.17.live:443/en/live/$_live?lang=en#chat',
      ]) {
        expect(SeventeenLiveApi.roomIdFromUrl(link), _live, reason: link);
      }
      for (final link in [
        'https://m.17.live/ja/live/$_live',
        'https://www.www.17.live/ja/live/$_live',
        'https://www17.live/ja/live/$_live',
        'https://user@www.17.live/ja/live/$_live',
        'https://www.17.live/ja/profile/$_live',
      ]) {
        expect(SeventeenLiveApi.roomIdFromUrl(link), isNull, reason: link);
      }
    });

    test("headers and the room page as 3.x's", () {
      Map<String, String> lower(Object? headers) => {
        for (final MapEntry(:key, :value) in (headers! as Map).entries) '$key'.toLowerCase(): '$value',
      };
      final legacy = _legacy('S04-live-live');
      expect(SeventeenLiveApi.requestHeaders(_live), lower(legacy['requestHeaders']));
      expect(SeventeenLiveApi.catalogHeaders, lower(legacy['catalogHeaders']));
      expect(SeventeenLiveApi.mediaHeaders(_live), lower(legacy['mediaHeaders']));
      expect(SeventeenLiveApi.roomUrl(_live), 'https://17.live/en/live/$_live');
      expect((_value('S04-live-live', 'getRoomDetail')! as Map)['link'], SeventeenLiveApi.roomUrl(_live));
    });
  });
}
