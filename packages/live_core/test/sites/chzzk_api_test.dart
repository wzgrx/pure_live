// CHZZK parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/chzzk/legacy_expected.dart from 3.x's ChzzkApi, ChzzkLink and
// ChzzkSite). Every intended difference is listed with its reason (an M4.U
// item number of docs/specs/UPGRADES.md for the approved upgrades); everything
// else must match. The synthetic cases port 3.x's chzzk_live_detail_test.dart
// and cover the regression entries of the archived spec (REG-CHZZK-001–004)
// and the shapes 3.x refused.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('chzzk', name);

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

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

/// The outcome of a counted legacy call (`{requests, value}`).
Object? _value(String name, String key) => (_legacy(name)[key] as Map<String, dynamic>)['value'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

/// The rows of a lives or categories answer.
List<Map<String, dynamic>> _rows(String sample) =>
    (((jsonDecode(_sample(sample).body) as Map)['content'] as Map)['data'] as List).cast<Map<String, dynamic>>();

/// 3.x put the media headers on live cards (`httpHeaders`), where only
/// IPTV's are read (3.x's PlaybackHeaderResolver ignored them for CHZZK);
/// they now travel on every line.
const _headersMoved = {'httpHeaders'};

/// `openDate` read as Korean time, independently of the parser.
String _kst(String openDate) => DateTime.parse('${openDate.replaceFirst(' ', 'T')}+09:00').toUtc().toIso8601String();

bool _abroad(Map<String, dynamic> row) => row['blindType'] == 'ABROAD' || row['krOnlyViewing'] == true;

/// What the upgrades change on a lives row's card: the notice of an adult
/// row (unified rule on development notes: 3.x's text spoke of a "public
/// anonymous media source") and of a region-locked row (20-8: 3.x had
/// none).
Set<String> _cardChanged(Map<String, dynamic> row) => {
  ..._headersMoved,
  if (row['adult'] == true || _abroad(row)) 'notice',
};

/// The v4 keys of a lives row's card: its start (Korean `openDate`) and its
/// restriction (20-8: region-locked, else adult, else none).
Map<String, Object?> _cardAdded(Map<String, dynamic> row) => {
  'startedAt': _kst(row['openDate'] as String),
  'restriction': _abroad(row)
      ? 'regionBlocked'
      : row['adult'] == true
      ? 'adult'
      : 'none',
};

const _live = 'af3323d30e11ae42c39d7203c7e07fa2';
const _offline = '12bba8d480ba0ffaf85656afd76fa792';
const _region = '75cbf189b3bb8f9f687d2aca0d0a382b';
const _adult = '7ce8032370ac5121dcabce7bad375ced';
const _missing = '00000000000000000000000000000000';

ChzzkChannel _owner(String sample, String id) {
  final fixture = _sample(sample);
  return ChzzkApi.channel(fixture.body, channelId: id, status: fixture.status);
}

/// The channel of a live-detail sample recorded without its channel answer
/// (region, adult): the live's own `channel` object, as the harness answered.
ChzzkChannel _ownerFromLive(String sample, String id) {
  final live = (jsonDecode(_sample(sample).body) as Map<String, dynamic>)['content'] as Map<String, dynamic>;
  return ChzzkApi.channel(jsonEncode({'code': 200, 'content': live['channel']}), channelId: id);
}

ChzzkLive? _liveOf(String sample, ChzzkChannel owner) {
  final fixture = _sample(sample);
  return ChzzkApi.liveDetail(fixture.body, owner: owner, status: fixture.status);
}

String _api(Object? content, {int code = 200}) => jsonEncode({'code': code, 'message': null, 'content': content});

/// A `v1/lives` row.
Map<String, dynamic> _row(
  int liveId, {
  String channelId = _live,
  int viewers = 100,
  Map<String, dynamic> changes = const {},
}) => {
  'liveId': liveId,
  'liveTitle': 'Live $liveId',
  'liveImageUrl': 'https://livecloud-thumb.akamaized.net/chzzk/$liveId/image_{type}.jpg',
  'defaultThumbnailImageUrl': null,
  'concurrentUserCount': viewers,
  'cvExposure': true,
  'adult': false,
  'openDate': '2026-09-29 03:43:51',
  'liveCategoryValue': 'Talk',
  'channel': {
    'channelId': channelId,
    'channelName': 'Streamer $liveId',
    'channelImageUrl': 'https://nng-phinf.pstatic.net/$liveId.png',
  },
  ...changes,
};

String _page(List<Object?> rows, {Object? next}) => _api({
  'size': rows.length,
  'page': next == null ? null : {'next': next, 'prev': null},
  'data': rows,
});

String _hex(int index) => index.toRadixString(16).padLeft(32, '0');

/// A `v3.1 live-detail` answer.
String _detail({
  String status = 'OPEN',
  Object? playback,
  Map<String, dynamic> changes = const {},
  String channelId = _live,
}) => _api({
  'liveId': 1,
  'liveTitle': 'Title',
  'status': status,
  'liveImageUrl': null,
  'defaultThumbnailImageUrl': null,
  'concurrentUserCount': 5,
  'cvExposure': true,
  'openDate': '2026-09-28 20:31:48',
  'adult': false,
  'krOnlyViewing': false,
  'timeMachineActive': false,
  'chatChannelId': 'Chat01',
  'liveCategoryValue': 'Talk',
  'livePlaybackJson': playback,
  'channel': {
    'channelId': channelId,
    'channelName': 'Live name',
    'channelImageUrl': 'https://nng-phinf.pstatic.net/live.png',
  },
  ...changes,
});

const _hlsMaster = 'https://livecloud.akamaized.net/chzzk/a/b_hls_playlist.m3u8?hdnts=st=1~exp=1900000000~acl=*';
const _llhlsMaster = 'https://livecloud.akamaized.net/chzzk/a/b_playlist.m3u8?hdnts=st=1~exp=1900000000~acl=*';

String _playback(List<Map<String, Object?>> media) => jsonEncode({'meta': <String, Object?>{}, 'media': media});

List<Map<String, Object?>> get _twoMedia => [
  {'mediaId': 'HLS', 'protocol': 'HLS', 'path': _hlsMaster},
  {'mediaId': 'LLHLS', 'protocol': 'HLS', 'path': _llhlsMaster, 'latency': 'lowLatency'},
];

const _channelOwner = ChzzkChannel(
  id: _live,
  name: 'Owner',
  avatar: 'https://nng-phinf.pstatic.net/owner.png',
  description: 'About',
  followers: 12,
  isLive: true,
);

String _masterText(List<String> variants) => ['#EXTM3U', '#EXT-X-VERSION:7', ...variants, ''].join('\n');

/// The catalog of the four recorded `categories/live` pages.
List<LiveCategory> _recordedCatalog() => ChzzkApi.categories([
  for (var page = 1; page <= 4; page++) ChzzkApi.categoryPage(_sample('S01-categories-p$page').body).areas,
]);

void main() {
  group('catalog (20-1)', () {
    test("the platform's areas by type (3.x had one fixed area); S01's four pages", () {
      final catalog = _recordedCatalog();
      expect(catalog.map((category) => category.id), ['GAME', 'ENTERTAINMENT', 'ETC'], reason: 'no SPORTS recorded');
      expect(catalog.map((category) => category.name), ['游戏', '娱乐', '其他']);
      final rows = [for (var page = 1; page <= 4; page++) ..._rows('S01-categories-p$page')];
      final ids = {for (final row in rows) row['categoryId']};
      expect(rows, hasLength(200));
      expect(ids, hasLength(194), reason: 'counts moved between the requests: six areas were listed twice');
      final areas = [for (final category in catalog) ...category.children];
      expect(areas.map((area) => area.areaId).toSet(), ids);
      expect(areas, hasLength(194));
      final first = catalog.first.children.first;
      expect(first.toJson(), {
        'platform': 'chzzk',
        'areaType': 'GAME',
        'typeName': '游戏',
        'areaId': 'Grand_Theft_Auto_V',
        'areaName': 'Grand Theft Auto V',
        'areaPic': rows.first['posterImageUrl'],
        'shortName': '',
      });
      final talk = catalog.last.children.firstWhere((area) => area.areaId == 'talk');
      expect(talk.areaName, 'talk');
      expect(talk.areaPic, startsWith('https://ssl.pstatic.net/'));
      // The areas keep the platform's order (by viewers) within each type.
      final games = [
        for (final row in rows)
          if (row['categoryType'] == 'GAME') row['categoryId'],
      ];
      expect(catalog.first.children.map((area) => area.areaId), games.toSet().toList());
    });

    test("each page's next is the following page's query, as recorded", () {
      for (var page = 1; page <= 3; page++) {
        final next = ChzzkApi.categoryPage(_sample('S01-categories-p$page').body).next!;
        expect(ChzzkApi.categoriesQuery(next), _sample('S01-categories-p${page + 1}').url.queryParameters);
      }
      expect(ChzzkApi.categoriesQuery(const {}), _sample('S01-categories-p1').url.queryParameters);
      expect(ChzzkApi.categoryPage(_api({'size': 0, 'page': null, 'data': <Object?>[]})).next, isNull);
      expect(
        ChzzkApi.categoryPage(
          _api({
            'page': {
              'next': {'categoryId': 'x'},
            },
            'data': <Object?>[],
          }),
        ).next,
        isNull,
        reason: 'an empty page ends the list',
      );
    });

    test('malformed entries are skipped; a page of them only is ApiChanged; SPORTS and unknown types', () {
      final page = ChzzkApi.categoryPage(
        _api({
          'data': [
            {'categoryType': 'SPORTS', 'categoryId': 'baseball', 'categoryValue': '야구'},
            {'categoryType': 'GAME', 'categoryId': 'Mount_&_Blade2_Bannerlord', 'categoryValue': ''},
            {'categoryType': 'GAME', 'categoryId': '../x'},
            {'categoryType': 'GAME', 'categoryId': null},
            {'categoryType': 'G A', 'categoryId': 'y'},
            {'categoryType': 'NEW_TYPE', 'categoryId': 'z', 'posterImageUrl': 'https://example.com/z.png'},
            'not an entry',
          ],
        }),
      );
      expect(page.areas.map((area) => area.areaId), ['baseball', 'Mount_&_Blade2_Bannerlord', 'z']);
      expect(page.areas[1].areaName, 'Mount_&_Blade2_Bannerlord', reason: 'no name: the id');
      expect(page.areas[2].areaPic, '', reason: "images only from NAVER's CDNs");
      final catalog = ChzzkApi.categories([page.areas]);
      expect(catalog.map((category) => (category.id, category.name)), [
        ('GAME', '游戏'),
        ('SPORTS', '体育'),
        ('NEW_TYPE', 'NEW_TYPE'),
      ]);
      expect(
        () => ChzzkApi.categoryPage(
          _api({
            'data': [
              {'categoryType': 'GAME'},
            ],
          }),
        ),
        throwsA(isA<ApiChanged>()),
      );
      expect(() => ChzzkApi.categoryPage(_api({'data': null})), throwsA(isA<ApiChanged>()));
      expect(ChzzkApi.categories(const []), isEmpty);
    });

    test("3.x's stored popular area still lists the site-wide lives; page 2 of the catalog stays empty", () {
      final legacy = _maps(_value('S03-lives-p1', 'getCategores(1)'));
      _expectParity(ChzzkApi.popularArea.toJson(), _maps(legacy.single['children']).single);
      expect(ChzzkApi.popularArea.areaName, '公开热门直播');
      expect(ChzzkApi.isPopular(ChzzkApi.popularArea), isTrue);
      expect(ChzzkApi.livesUrl(ChzzkApi.popularArea, null).toString(), _sample('S03-lives-p1').url.toString());
      expect(_value('S03-lives-p1', 'getCategores(2)'), 0);
      expect(_legacy('S03-lives-p1')['directoryNoticeKey'], 'chzzk_directory_scope');
      final catalog = _recordedCatalog();
      expect(catalog.expand((category) => category.children).where(ChzzkApi.isPopular), isEmpty);
    });

    test('checkArea: null, the popular area or a catalog area; anything else is a caller error', () {
      ChzzkApi.checkArea(null);
      ChzzkApi.checkArea(ChzzkApi.popularArea);
      ChzzkApi.checkArea(_recordedCatalog().first.children.first);
      ChzzkApi.checkArea(const LiveArea(platform: 'chzzk', areaType: 'GAME', areaId: 'Mount_&_Blade2_Bannerlord'));
      for (final area in [
        const LiveArea(platform: 'chzzk', areaType: 'directory', areaId: 'League_of_Legends'),
        const LiveArea(platform: 'chzzk', areaId: 'League_of_Legends'),
        const LiveArea(platform: 'chzzk', areaType: 'GAME'),
        const LiveArea(platform: 'chzzk', areaType: 'GAME', areaId: 'a/b'),
        const LiveArea(platform: 'chzzk', areaType: 'GAME', areaId: '..'),
        const LiveArea(platform: 'chzzk', areaType: 'GAME', areaId: 'a b'),
        const LiveArea(platform: 'chzzk', areaType: '../GAME', areaId: 'x'),
        const LiveArea(platform: 'soop', areaType: 'directory', areaId: 'popular'),
        const LiveArea(platform: 'soop', areaType: 'GAME', areaId: 'League_of_Legends'),
      ]) {
        expect(() => ChzzkApi.checkArea(area), throwsArgumentError, reason: '$area');
      }
    });

    test("an area's lives are v2/categories/<type>/<id>/lives, the id path-encoded (S02)", () {
      const lol = LiveArea(platform: 'chzzk', areaType: 'GAME', areaId: 'League_of_Legends');
      expect(ChzzkApi.livesUrl(lol, null), _sample('S02-category-lives-p1').url);
      final cursor = ChzzkApi.encodeCursor(21, 21339818);
      expect(ChzzkApi.livesUrl(lol, cursor).path, _sample('S02-category-lives-p2').url.path);
      expect(ChzzkApi.livesUrl(lol, cursor).queryParameters, _sample('S02-category-lives-p2').url.queryParameters);
      expect(
        ChzzkApi.livesUrl(
          const LiveArea(platform: 'chzzk', areaType: 'GAME', areaId: 'Mount_&_Blade2_Bannerlord'),
          null,
        ).toString(),
        // `&` may stay in a path; the platform answers it (2026-09-29).
        'https://api.chzzk.naver.com/service/v2/categories/GAME/Mount_&_Blade2_Bannerlord/lives?size=30',
      );
      expect(
        ChzzkApi.livesUrl(const LiveArea(platform: 'chzzk', areaType: 'GAME', areaId: '한글%'), null).path,
        '/service/v2/categories/GAME/%ED%95%9C%EA%B8%80%25/lives',
      );
      expect(ChzzkApi.livesUrl(null, null).toString(), 'https://api.chzzk.naver.com/service/v1/lives?size=30');
    });
  });

  group('S02 area lives (20-1)', () {
    test('the rows are live cards like the site-wide list; the cursor is exclusive', () {
      final p1 = ChzzkApi.lives(_sample('S02-category-lives-p1').body);
      final rows = _rows('S02-category-lives-p1');
      expect(p1.rooms.map((room) => room.roomId), rows.map((row) => (row['channel'] as Map)['channelId']));
      expect(p1.rooms.first.area, '리그 오브 레전드');
      expect(p1.rooms.map((room) => room.isLiveNow), everyElement(isTrue));
      expect(ChzzkApi.decodeCursor(p1.nextCursor!), (viewers: 21, liveId: 21339818));
      final p2 = ChzzkApi.lives(_sample('S02-category-lives-p2').body, cursor: p1.nextCursor);
      expect(p2.rooms, hasLength(30));
      expect(
        p2.rooms.map((room) => room.roomId).toSet().intersection(p1.rooms.map((room) => room.roomId).toSet()),
        isEmpty,
      );
      expect(p2.hasMore, isTrue);
    });

    test('an unknown area is an empty last page (S02-category-lives-empty)', () {
      final page = ChzzkApi.lives(_sample('S02-category-lives-empty').body);
      expect(page.rooms, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
    });
  });

  group('S03 popular directory', () {
    test('page 1: same rooms, cursor and end as 3.x', () {
      final fixture = _sample('S03-lives-p1');
      final legacy = _value('S03-lives-p1', 'getDirectoryPage(1)')! as Map<String, dynamic>;
      final page = ChzzkApi.lives(fixture.body, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      final rows = _rows('S03-lives-p1');
      expect(page.rooms.map((room) => room.roomId), rooms.map((room) => room['roomId']));
      for (final (index, room) in page.rooms.indexed) {
        _expectParity(
          _projection(room),
          rooms[index],
          changed: _cardChanged(rows[index]),
          added: _cardAdded(rows[index]),
          reason: 'p1[$index]',
        );
        expect(room.httpHeaders, isEmpty);
      }
      expect(page.nextCursor, legacy['nextCursor']);
      expect(page.hasMore, legacy['hasMore']);
      for (final key in ['getRecommendRooms(1)', 'getCategoryRooms(1)']) {
        expect(_maps(_value('S03-lives-p1', key)).map((room) => room['roomId']), rooms.map((room) => room['roomId']));
      }
    });

    test('page 2 after the cursor: same rooms, cursor and end as 3.x', () {
      final fixture = _sample('S03-lives-p2');
      final cursor = _legacy('S03-lives-p2')['cursor'] as String;
      final legacy = _value('S03-lives-p2', 'getDirectoryPageAtCursor(2)')! as Map<String, dynamic>;
      final page = ChzzkApi.lives(fixture.body, cursor: cursor, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      final rows = _rows('S03-lives-p2');
      expect(page.rooms.map((room) => room.roomId), rooms.map((room) => room['roomId']));
      for (final (index, room) in page.rooms.indexed) {
        _expectParity(
          _projection(room),
          rooms[index],
          changed: _cardChanged(rows[index]),
          added: _cardAdded(rows[index]),
          reason: 'p2[$index]',
        );
      }
      expect(page.nextCursor, legacy['nextCursor']);
      expect(page.hasMore, isTrue);
      expect(_value('S03-lives-p2', 'getDirectoryPage(2)'), legacy, reason: 'replay gives the same page');
    });

    test('20-8: region-locked rows carry the region notice and restriction; adult rows theirs', () {
      final rows = _rows('S03-lives-p1');
      final rooms = ChzzkApi.lives(_sample('S03-lives-p1').body).rooms;
      for (final (index, row) in rows.indexed) {
        final room = rooms[index];
        if (_abroad(row)) {
          expect(room.notice, ChzzkApi.regionNotice, reason: '$index');
          expect(room.restriction, LiveRestriction.regionBlocked);
        } else if (row['adult'] == true) {
          expect(room.notice, ChzzkApi.adultNotice, reason: '$index');
          expect(room.restriction, LiveRestriction.adult);
        } else {
          expect(room.notice, isNull, reason: '$index');
          expect(room.restriction, LiveRestriction.none);
        }
        expect(room.isLiveNow, isTrue, reason: 'restricted lives are still live');
        expect(room.followGroup, FollowGroup.live);
        expect(room.audienceMetricType, AudienceMetricType.onlineViewers);
      }
      expect(rows.where(_abroad), hasLength(3));
      expect(rows.where((row) => row['adult'] == true), hasLength(4));
      // A region-locked adult row names the region, as the detail does.
      final both = ChzzkApi.lives(
        _page([
          _row(1, changes: const {'adult': true, 'blindType': 'ABROAD'}),
        ]),
      ).rooms.single;
      expect(both.notice, ChzzkApi.regionNotice);
      expect(both.restriction, LiveRestriction.regionBlocked);
      final krOnly = ChzzkApi.lives(
        _page([
          _row(1, changes: const {'krOnlyViewing': true}),
        ]),
      ).rooms.single;
      expect(krOnly.restriction, LiveRestriction.regionBlocked);
    });

    test('a row with a paid product has no known restriction (none of 600 lives had one)', () {
      final rooms = ChzzkApi.lives(
        _page([
          _row(3, channelId: _hex(1), changes: const {'paidProductId': 'P1'}),
          _row(2, channelId: _hex(2), changes: const {'watchPartyPaidProductId': 'W1'}),
          _row(1, channelId: _hex(3), changes: const {'paidProductId': null, 'watchPartyPaidProductId': null}),
        ]),
      ).rooms;
      expect(rooms.map((room) => room.restriction), [null, null, LiveRestriction.none]);
    });

    test('the start is openDate in Korean time; a missing or malformed one is left out', () {
      final rows = _rows('S03-lives-p1');
      final rooms = ChzzkApi.lives(_sample('S03-lives-p1').body).rooms;
      expect(rooms.first.startedAt, DateTime.utc(2026, 9, 27, 12, 55, 34), reason: rows.first['openDate'] as String);
      final odd = ChzzkApi.lives(
        _page([
          _row(3, channelId: _hex(1), changes: const {'openDate': null}),
          _row(2, channelId: _hex(2), changes: const {'openDate': '2026-02-30 10:00:00'}),
          _row(1, channelId: _hex(3), changes: const {'openDate': '2026-09-29T03:43:51'}),
        ]),
      ).rooms;
      expect(odd.map((room) => room.startedAt), [null, null, DateTime.utc(2026, 9, 28, 18, 43, 51)]);
    });

    test('seoulTime', () {
      expect(ChzzkApi.seoulTime('2026-09-27 17:52:04'), DateTime.utc(2026, 9, 27, 8, 52, 4));
      expect(ChzzkApi.seoulTime('2026-01-01 03:00:00'), DateTime.utc(2025, 12, 31, 18));
      expect(ChzzkApi.seoulTime(' 2026-09-27 17:52:04 '), DateTime.utc(2026, 9, 27, 8, 52, 4));
      for (final value in [
        null,
        '',
        '0000-00-00 00:00:00',
        '1999-12-31 23:00:00',
        '2026-09-27',
        42,
        '2026-13-01 00:00:00',
      ]) {
        expect(ChzzkApi.seoulTime(value), isNull, reason: '$value');
      }
    });

    test('the cursor is the last row sent (exclusive): S03 p1 ends where p2 starts', () {
      final p1 = _rows('S03-lives-p1');
      final p2 = _rows('S03-lives-p2');
      final next = ChzzkApi.decodeCursor(ChzzkApi.lives(_sample('S03-lives-p1').body).nextCursor!);
      expect(next.liveId, p1.last['liveId']);
      expect(next.viewers, p1.last['concurrentUserCount']);
      expect({for (final row in p1) row['liveId']}.intersection({for (final row in p2) row['liveId']}), isEmpty);
    });

    test('20-6: 30 rows, also after a cursor (3.x asked 31 there), with its two fields', () {
      expect(ChzzkApi.livesQuery(null), {'size': '30'});
      expect(ChzzkApi.livesQuery(ChzzkApi.encodeCursor(2187, 21334270)), {
        'size': '30',
        'concurrentUserCount': '2187',
        'liveId': '21334270',
      });
      expect(ChzzkApi.encodeCursor(2187, 21334270), '{"v":2187,"l":21334270}');
      expect(_sample('S03-lives-p2').url.queryParameters['size'], '30', reason: 'what the platform was asked');
    });

    test('a first row that is the cursor row is still dropped (a guard; the platform starts after it)', () {
      final cursor = ChzzkApi.encodeCursor(100, 900);
      final page = ChzzkApi.lives(
        _page(
          [_row(900, channelId: _hex(1)), _row(899, channelId: _hex(2))],
          next: {'concurrentUserCount': 90, 'liveId': 899},
        ),
        cursor: cursor,
      );
      expect(page.rooms.map((room) => room.roomId), [_hex(2)]);
    });

    test('more than 30 rows: the rest is cut and the next page starts right after the 30th', () {
      // 3.x kept `page.next` (the last row sent), so a cut row was never shown.
      final rows = [
        for (var index = 0; index < 31; index++) _row(1000 - index, channelId: _hex(index + 1), viewers: 500 - index),
      ];
      final cursor = ChzzkApi.encodeCursor(600, 2000);
      final page = ChzzkApi.lives(_page(rows, next: {'concurrentUserCount': 470, 'liveId': 970}), cursor: cursor);
      expect(page.rooms, hasLength(30));
      expect(page.rooms.last.roomId, _hex(30));
      expect(ChzzkApi.decodeCursor(page.nextCursor!), (viewers: 471, liveId: 971));
      expect(page.hasMore, isTrue);
      // The same page with the cursor row repeated first (an inclusive
      // server) keeps 30 rows and the platform's next cursor.
      final inclusive = ChzzkApi.lives(
        _page(
          [_row(2000, channelId: _hex(99), viewers: 600), ...rows.take(30)],
          next: {'concurrentUserCount': 471, 'liveId': 971},
        ),
        cursor: cursor,
      );
      expect(inclusive.rooms.map((room) => room.roomId), page.rooms.map((room) => room.roomId));
      expect(inclusive.nextCursor, page.nextCursor);
    });

    test('a cut row without a viewer count falls back to page.next', () {
      final rows = [
        for (var index = 0; index < 31; index++)
          _row(
            1000 - index,
            channelId: _hex(index + 1),
            changes: index == 29 ? const {'concurrentUserCount': null} : const {},
          ),
      ];
      final page = ChzzkApi.lives(
        _page(rows, next: {'concurrentUserCount': 7, 'liveId': 970}),
        cursor: ChzzkApi.encodeCursor(600, 2000),
      );
      expect(page.rooms, hasLength(30));
      expect(ChzzkApi.decodeCursor(page.nextCursor!), (viewers: 7, liveId: 970));
    });

    test('the end: no page.next, a repeated cursor, or an empty page', () {
      expect(ChzzkApi.lives(_page([_row(1)])).hasMore, isFalse);
      final cursor = ChzzkApi.encodeCursor(1, 5);
      final repeated = ChzzkApi.lives(_page([_row(4)], next: {'concurrentUserCount': 1, 'liveId': 5}), cursor: cursor);
      expect(repeated.nextCursor, isNull);
      final empty = ChzzkApi.lives(_page([], next: {'concurrentUserCount': 1, 'liveId': 4}), cursor: cursor);
      expect(empty.rooms, isEmpty);
      expect(empty.hasMore, isFalse, reason: '3.x: a cursor and a non-empty page');
      expect(ChzzkApi.lives(_api({'size': 0, 'page': null, 'data': <Object?>[]})).hasMore, isFalse);
    });

    test('a channel appears once per page', () {
      final page = ChzzkApi.lives(_page([_row(3), _row(2), _row(1, channelId: _hex(7))]));
      expect(page.rooms.map((room) => room.roomId), [_live, _hex(7)]);
      expect(page.rooms.first.title, 'Live 3');
    });

    test('rows 3.x refused are skipped or filled in, not the page failed', () {
      final page = ChzzkApi.lives(
        _page([
          _row(9, changes: const {'channel': null}),
          _row(8, channelId: 'NOT-A-CHANNEL'),
          _row(7, channelId: _hex(3), changes: const {'liveId': 0}),
          'not a row',
          _row(6, channelId: _hex(4), changes: const {'liveTitle': '  ', 'adult': 'yes', 'liveCategoryValue': 5}),
          _row(5, channelId: _hex(5), changes: const {'concurrentUserCount': -3}),
        ]),
      );
      expect(page.rooms.map((room) => room.roomId), [_hex(4), _hex(5)]);
      expect(page.rooms.first.title, 'Streamer 6', reason: 'an empty title is the channel name, as in the detail');
      expect(page.rooms.first.notice, isNull);
      expect(page.rooms.first.restriction, LiveRestriction.none, reason: 'adult must be true');
      expect(page.rooms.first.area, '');
      expect(page.rooms.last.onlineViewers, '');
    });

    test('REG-CHZZK-002: viewers only when cvExposure is true', () {
      final page = ChzzkApi.lives(
        _page([
          _row(3, channelId: _hex(1), viewers: 42),
          _row(2, channelId: _hex(2), viewers: 42, changes: const {'cvExposure': false}),
          _row(1, channelId: _hex(3), viewers: 42, changes: const {'cvExposure': null}),
        ]),
      );
      expect(page.rooms.map((room) => room.onlineViewers), ['42', '', '']);
    });

    test('REG-CHZZK-003: the cover template is 480 wide; else the default thumbnail; else none', () {
      final page = ChzzkApi.lives(
        _page([
          _row(3, channelId: _hex(1)),
          _row(
            2,
            channelId: _hex(2),
            changes: const {'liveImageUrl': null, 'defaultThumbnailImageUrl': 'https://ssl.pstatic.net/default.png'},
          ),
          _row(1, channelId: _hex(3), changes: const {'liveImageUrl': null}),
        ]),
      );
      expect(page.rooms[0].cover, 'https://livecloud-thumb.akamaized.net/chzzk/3/image_480.jpg');
      expect(page.rooms[1].cover, 'https://ssl.pstatic.net/default.png');
      expect(page.rooms[2].cover, '');
      final sample = ChzzkApi.lives(_sample('S03-lives-p1').body).rooms;
      expect(sample.where((room) => room.cover.contains('{type}')), isEmpty);
      expect(sample.where((room) => room.cover.endsWith('image_480.jpg')), isNotEmpty);
    });

    test('images: https on NAVER CDNs only (3.x)', () {
      expect(ChzzkApi.image('https://nng-phinf.pstatic.net/a.png'), 'https://nng-phinf.pstatic.net/a.png');
      expect(ChzzkApi.image('https://livecloud-thumb.akamaized.net/a.jpg'), isNotEmpty);
      for (final url in [
        'http://nng-phinf.pstatic.net/a.png',
        'https://example.com/a.png',
        'https://pstatic.net.example.com/a.png',
        'https://user@nng-phinf.pstatic.net/a.png',
        'https://nng-phinf.pstatic.net/a.png#x',
        null,
        42,
      ]) {
        expect(ChzzkApi.image(url), '', reason: '$url');
      }
    });

    test('malformed pages are ApiChanged; the cursor must be ours', () {
      expect(() => ChzzkApi.lives(_api(null)), throwsA(isA<ApiChanged>()));
      expect(() => ChzzkApi.lives(_api({'data': 'x'})), throwsA(isA<ApiChanged>()));
      expect(
        () => ChzzkApi.lives(_page([_row(1)], next: {'concurrentUserCount': -1, 'liveId': 1})),
        throwsA(isA<ApiChanged>()),
      );
      for (final cursor in [
        '',
        'x',
        '{"v":1}',
        '{"v":1,"l":0}',
        '{"v":-1,"l":2}',
        '{"v":1,"l":2,"x":3}',
        '[1,2]',
        'x' * 200,
      ]) {
        expect(() => ChzzkApi.decodeCursor(cursor), throwsArgumentError, reason: cursor);
        expect(() => ChzzkApi.livesUrl(null, cursor), throwsArgumentError, reason: cursor);
      }
      expect(ChzzkApi.decodeCursor('{"v":0,"l":2}'), (viewers: 0, liveId: 2));
    });

    test('the directory notice says what the lists are, without development terms (20-6)', () {
      expect(ChzzkApi.directoryScope, isNot(contains('边界')));
      expect(ChzzkApi.directoryScope, isNot(contains('cvExposure')));
      expect(ChzzkApi.directoryScope, isNot(contains('concurrentUserCount')));
      expect(ChzzkApi.directoryScope, contains('分类'));
    });
  });

  group('S04 channel search', () {
    for (final name in ['S04-search-channels', 'S04-search-empty']) {
      test('$name: same cards as 3.x', () {
        final fixture = _sample(name);
        final rooms = ChzzkApi.searchRooms(fixture.body, status: fixture.status);
        final legacy = _maps(_value(name, 'searchRooms'));
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        for (final (index, room) in rooms.indexed) {
          _expectParity(_projection(room), legacy[index], reason: '$name[$index]');
        }
      });
    }

    test('live and offline channels; the title is the name, the cover the avatar', () {
      final rooms = ChzzkApi.searchRooms(_sample('S04-search-channels').body);
      expect(rooms.where((room) => room.isLiveNow), isNotEmpty);
      expect(rooms.where((room) => room.effectiveLiveStatus == LiveStatus.offline), isNotEmpty);
      for (final room in rooms) {
        expect(room.title, room.nick);
        expect(room.cover, room.avatar);
        expect(room.link, 'https://chzzk.naver.com/live/${room.roomId}');
      }
    });

    test('a result without a channel id is skipped (3.x failed the page)', () {
      final rooms = ChzzkApi.searchRooms(
        _api({
          'data': [
            {'channel': null},
            {
              'channel': {'channelId': null, 'channelName': 'x'},
            },
            {
              'channel': {'channelId': _live, 'channelName': '', 'followerCount': 'many', 'openLive': 'true'},
            },
          ],
        }),
      );
      expect(rooms.single.roomId, _live);
      expect(rooms.single.title, '');
      expect(rooms.single.followers, '');
      expect(rooms.single.isLiveNow, isFalse, reason: 'openLive must be true');
      expect(() => ChzzkApi.searchRooms(_api({'data': null})), throwsA(isA<ApiChanged>()));
    });

    test('20-5: a keyword over 100 UTF-16 units is cut there, never inside a surrogate pair (3.x refused it)', () {
      expect(ChzzkApi.searchKeyword('  배틀  '), '배틀');
      expect(ChzzkApi.searchKeyword('a' * 100), 'a' * 100);
      expect(ChzzkApi.searchKeyword('a' * 150), 'a' * 100);
      expect(ChzzkApi.searchKeyword('${'a' * 99}😀tail'), 'a' * 99, reason: 'the emoji would be split');
      expect(ChzzkApi.searchKeyword('${'a' * 98}😀tail'), '${'a' * 98}😀');
      expect(ChzzkApi.searchKeyword('${'a' * 50}${' ' * 60}b'), 'a' * 50, reason: 'trimmed again');
      expect(ChzzkApi.searchKeyword('   '), '');
      expect(ChzzkApi.searchPageSize, 20);
    });
  });

  group('S05 channel', () {
    for (final (name, id) in [('S05-channel-live', _live), ('S05-channel-offline', _offline)]) {
      test('$name: same channel as 3.x', () {
        final legacy = _value(name, 'channel')! as Map<String, dynamic>;
        final channel = _owner(name, id);
        expect(channel.id, legacy['id']);
        expect(channel.name, legacy['name']);
        expect(channel.avatar, legacy['avatar']);
        expect(channel.description, legacy['description']);
        expect(channel.followers, legacy['followers']);
        expect(channel.isLive, legacy['isLive']);
      });
    }

    test('S05-channel-notfound: an unknown id is NotFound (3.x: identity)', () {
      expect((_value('S05-channel-notfound', 'channel')! as Map)['message'], 'CHZZK identity');
      final fixture = _sample('S05-channel-notfound');
      expect(
        () => ChzzkApi.channel(fixture.body, channelId: _missing, status: fixture.status),
        throwsA(isA<NotFound>()),
      );
      expect(() => ChzzkApi.channel(_api(null), channelId: _live), throwsA(isA<NotFound>()));
    });

    test('another channel is ApiChanged', () {
      expect(
        () => ChzzkApi.channel(_api({'channelId': _offline, 'channelName': 'x'}), channelId: _live),
        throwsA(isA<ApiChanged>()),
      );
      expect(
        () => ChzzkApi.channel(_api({'channelId': 'AF3323D30E11AE42C39D7203C7E07FA2'}), channelId: _live),
        throwsA(isA<ApiChanged>()),
      );
    });
  });

  group('S06 room detail', () {
    for (final (name, owner, changed, added) in [
      (
        'S06-live-detail-live',
        () => _owner('S05-channel-live', _live),
        // 20-10: the rewind notice is written for users.
        {..._headersMoved, 'notice'},
        {'startedAt': _kst('2026-09-27 17:52:04'), 'restriction': 'none'},
      ),
      (
        'S06-live-detail-offline',
        () => _owner('S05-channel-offline', _offline),
        _headersMoved,
        const <String, Object?>{},
      ),
      (
        'S06-live-detail-region',
        () => _ownerFromLive('S06-live-detail-region', _region),
        _headersMoved,
        {'startedAt': _kst('2026-09-27 21:55:34'), 'restriction': 'regionBlocked'},
      ),
      (
        'S06-live-detail-adult',
        () => _ownerFromLive('S06-live-detail-adult', _adult),
        // The unified rule on development notes: the adult notice is
        // written for users.
        {..._headersMoved, 'notice'},
        {'startedAt': _kst('2026-09-27 20:15:24'), 'restriction': 'adult'},
      ),
    ]) {
      test('$name: same room as 3.x', () {
        final channel = owner();
        final room = ChzzkApi.room(channel, _liveOf(name, channel));
        for (final key in ['getRoomDetailForRefresh', 'getRoomDetail', 'getRoomDetailForRecording']) {
          _expectParity(
            _projection(room),
            _value(name, key)! as Map<String, dynamic>,
            changed: changed,
            added: added,
            reason: '$name $key',
          );
        }
        expect(room.httpHeaders, isEmpty);
      });
    }

    test('the open live: its card with the channel followers, introduction, start and the rewind notice', () {
      final owner = _owner('S05-channel-live', _live);
      final live = _liveOf('S06-live-detail-live', owner)!;
      expect(live.isLive, isTrue);
      expect(live.media.map((media) => media.id), ['HLS', 'LLHLS']);
      expect(live.chatChannelId, 'N2lpu9');
      final room = ChzzkApi.room(owner, live);
      expect(room.followers, '106641');
      expect(room.introduction, owner.description);
      expect(room.onlineViewers, '11370');
      expect(room.notice, ChzzkApi.timeMachineNotice);
      expect(room.area, 'Grand Theft Auto V');
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 8, 52, 4));
      expect(room.restriction, LiveRestriction.none);
      expect(room.totalViewers, '', reason: '20-3: accumulateCount is 0 while live');
    });

    test('20-10: the rewind notice is for users (3.x: a development note)', () {
      expect(_value('S06-live-detail-live', 'getRoomDetail'), containsPair('notice', contains('HLS')));
      expect(ChzzkApi.timeMachineNotice, isNot(contains('HLS')));
      expect(ChzzkApi.timeMachineNotice, contains('回看'));
      expect(ChzzkApi.adultNotice, isNot(contains('媒体源')));
    });

    test('a closed live is the channel card; offline even when the channel still says live (20-7)', () {
      final owner = _owner('S05-channel-offline', _offline);
      final live = _liveOf('S06-live-detail-offline', owner)!;
      expect(live.isLive, isFalse);
      expect(live.media, isEmpty);
      expect(live.startedAt, isNull, reason: 'openDate of a closed live is not a current start');
      final room = ChzzkApi.room(owner, live);
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.title, owner.name);
      expect(room.cover, owner.avatar);
      expect(room.restriction, isNull);
      expect(room.startedAt, isNull);
      final racing = ChzzkApi.room(
        ChzzkChannel(id: owner.id, name: owner.name, avatar: owner.avatar, isLive: true),
        live,
      );
      expect(racing.effectiveLiveStatus, LiveStatus.offline, reason: '3.x took openLive and showed it live');
      expect(
        ChzzkApi.room(
          ChzzkChannel(id: owner.id, name: owner.name, avatar: owner.avatar, isLive: true),
          null,
        ).effectiveLiveStatus,
        LiveStatus.offline,
        reason: 'never broadcast',
      );
      expect(ChzzkApi.liveDetail(_api(null), owner: owner), isNull);
    });

    test('REG-CHZZK-001: a region-locked live opens with its notice; its stream is RegionBlocked', () {
      final owner = _ownerFromLive('S06-live-detail-region', _region);
      final live = _liveOf('S06-live-detail-region', owner)!;
      expect(live.isLive, isTrue);
      expect(live.krOnly, isTrue);
      expect(live.abroadBlind, isTrue);
      expect(live.media, isEmpty);
      final room = ChzzkApi.room(owner, live);
      expect(room.isLiveNow, isTrue);
      expect(room.notice, ChzzkApi.regionNotice);
      expect(room.restriction, LiveRestriction.regionBlocked);
      expect(ChzzkApi.unavailable(live), isA<RegionBlocked>());
      // 3.x's chzzk_live_detail_test.dart: v3.1 fields with krOnlyViewing and
      // no playback, the title kept.
      final ported = ChzzkApi.liveDetail(
        _detail(
          changes: {
            'liveId': 21307904,
            'liveTitle': 'Asian Games marathon',
            'krOnlyViewing': true,
            'concurrentUserCount': 1200,
            'chatChannelId': null,
          },
        ),
        owner: _channelOwner,
      )!;
      expect(ChzzkApi.room(_channelOwner, ported).title, 'Asian Games marathon');
      expect(ChzzkApi.room(_channelOwner, ported).notice, isNotEmpty);
      expect(ChzzkApi.unavailable(ported), isA<RegionBlocked>());
      // 20-8: hidden abroad alone is region-locked too (3.x noticed only
      // krOnlyViewing).
      final hiddenAbroad = ChzzkApi.liveDetail(_detail(changes: {'blindType': 'ABROAD'}), owner: _channelOwner)!;
      expect(ChzzkApi.room(_channelOwner, hiddenAbroad).notice, ChzzkApi.regionNotice);
      expect(ChzzkApi.room(_channelOwner, hiddenAbroad).restriction, LiveRestriction.regionBlocked);
      expect(ChzzkApi.unavailable(hiddenAbroad), isA<RegionBlocked>());
    });

    test('an adult live opens with its notice; its stream needs a login', () {
      final owner = _ownerFromLive('S06-live-detail-adult', _adult);
      final live = _liveOf('S06-live-detail-adult', owner)!;
      expect(live.adult, isTrue);
      final room = ChzzkApi.room(owner, live);
      expect(room.notice, ChzzkApi.adultNotice);
      expect(room.cover, '');
      expect(room.restriction, LiveRestriction.adult);
      expect(ChzzkApi.unavailable(live), isA<NeedsLogin>());
    });

    test("3.x's notice order: region (20-8: or hidden abroad), adult without playback, rewind, adult", () {
      String? notice(Map<String, dynamic> changes, {bool media = false}) => ChzzkApi.room(
        _channelOwner,
        ChzzkApi.liveDetail(
          _detail(playback: media ? _playback(_twoMedia) : null, changes: changes),
          owner: _channelOwner,
        ),
      ).notice;
      expect(notice({'krOnlyViewing': true, 'adult': true, 'timeMachineActive': true}), ChzzkApi.regionNotice);
      expect(notice({'blindType': 'ABROAD', 'adult': true}), ChzzkApi.regionNotice);
      expect(notice({'adult': true, 'timeMachineActive': true}), ChzzkApi.adultNotice);
      expect(notice({'adult': true, 'timeMachineActive': true}, media: true), ChzzkApi.timeMachineNotice);
      expect(notice({'adult': true}, media: true), ChzzkApi.adultNotice);
      expect(notice({}, media: true), isNull);
    });

    test('restrictions of an open live: none with playback; else region, adult, paid, unplayable', () {
      (LiveRestriction?, SiteError) of(Map<String, dynamic> changes, {bool media = false}) {
        final live = ChzzkApi.liveDetail(
          _detail(playback: media ? _playback(_twoMedia) : null, changes: changes),
          owner: _channelOwner,
        )!;
        expect(ChzzkApi.room(_channelOwner, live).restriction, ChzzkApi.restriction(live));
        return (ChzzkApi.restriction(live), ChzzkApi.unavailable(live));
      }

      expect(of({'krOnlyViewing': true}, media: true).$1, LiveRestriction.none, reason: 'playback given');
      final region = of({'krOnlyViewing': true, 'adult': true});
      expect(region.$1, LiveRestriction.regionBlocked);
      expect(region.$2, isA<RegionBlocked>());
      final adult = of({'adult': true, 'paidProduct': <String, Object?>{}});
      expect(adult.$1, LiveRestriction.adult);
      expect(adult.$2, isA<NeedsLogin>());
      final paid = of({
        'paidProduct': {'productId': 'P1'},
      });
      expect(paid.$1, LiveRestriction.paid);
      expect(paid.$2, isA<StreamUnavailable>().having((error) => error.detail, 'detail', 'paid live'));
      expect(of({'watchPartyPaidProductId': 'W1'}).$1, LiveRestriction.paid);
      final bare = of({});
      expect(bare.$1, LiveRestriction.unplayable);
      expect(bare.$2, isA<StreamUnavailable>());
      expect(ChzzkApi.restriction(null), isNull);
    });

    test('S06-live-detail-notfound: HTTP 404 is NotFound (3.x: missing)', () {
      expect((_value('S06-live-detail-notfound', 'liveDetail')! as Map)['message'], 'CHZZK missing');
      final fixture = _sample('S06-live-detail-notfound');
      expect(
        () => ChzzkApi.liveDetail(
          fixture.body,
          owner: const ChzzkChannel(id: _missing, name: '', avatar: ''),
          status: fixture.status,
        ),
        throwsA(isA<NotFound>()),
      );
    });

    test('CLOSED is offline too; any other status is ApiChanged, never offline', () {
      expect(ChzzkApi.liveDetail(_detail(status: 'CLOSED'), owner: _channelOwner)!.isLive, isFalse);
      for (final status in ['READY', '', null]) {
        expect(
          () => ChzzkApi.liveDetail(_detail(changes: {'status': status}), owner: _channelOwner),
          throwsA(isA<ApiChanged>()),
          reason: '$status',
        );
      }
    });

    test("a live of another channel is ApiChanged; a live without its channel uses the owner's", () {
      expect(() => ChzzkApi.liveDetail(_detail(channelId: _offline), owner: _channelOwner), throwsA(isA<ApiChanged>()));
      final bare = ChzzkApi.liveDetail(_detail(changes: {'channel': null, 'liveTitle': ''}), owner: _channelOwner)!;
      expect(bare.nick, 'Owner');
      expect(bare.avatar, _channelOwner.avatar);
      expect(bare.title, 'Owner', reason: "3.x: an empty title is the channel's name");
    });

    test('REG-CHZZK-002 in the detail: viewers only when cvExposure is true', () {
      final hidden = ChzzkApi.liveDetail(_detail(changes: {'cvExposure': false}), owner: _channelOwner);
      expect(ChzzkApi.room(_channelOwner, hidden).onlineViewers, '');
      final shown = ChzzkApi.liveDetail(_detail(), owner: _channelOwner);
      expect(ChzzkApi.room(_channelOwner, shown).onlineViewers, '5');
    });

    test('an unusable livePlaybackJson keeps the room; the stream reports it', () {
      for (final playback in [
        '{',
        42,
        _playback([
          {'mediaId': 'HLS', 'path': _hlsMaster},
        ]),
        _playback([
          {'mediaId': 'HLS', 'protocol': 'HLS', 'path': 'https://example.com/a.m3u8'},
        ]),
        jsonEncode({'media': null}),
      ]) {
        final live = ChzzkApi.liveDetail(_detail(playback: playback), owner: _channelOwner)!;
        expect(live.media, isEmpty, reason: '$playback');
        expect(live.mediaError, isA<ApiChanged>(), reason: '$playback');
        final room = ChzzkApi.room(_channelOwner, live);
        expect(room.isLiveNow, isTrue);
        expect(room.restriction, isNull, reason: 'unknown');
        expect(ChzzkApi.unavailable(live), same(live.mediaError));
        expect(ChzzkApi.roomData(_live, live).unavailable, same(live.mediaError));
      }
      final closed = ChzzkApi.liveDetail(
        _detail(status: 'CLOSE', playback: '{'),
        owner: _channelOwner,
      )!;
      expect(closed.mediaError, isNull, reason: 'read only for an open live');
      expect(ChzzkApi.unavailable(closed), isA<StreamUnavailable>());
    });

    test('the playback data room entry keeps: the masters, or why there are none', () {
      final owner = _owner('S05-channel-live', _live);
      final live = ChzzkApi.roomData(_live, _liveOf('S06-live-detail-live', owner));
      expect(live.channelId, _live);
      expect(live.media.map((media) => media.id), ['HLS', 'LLHLS']);
      expect(live.unavailable, isNull);
      final region = _ownerFromLive('S06-live-detail-region', _region);
      expect(ChzzkApi.roomData(_region, _liveOf('S06-live-detail-region', region)).unavailable, isA<RegionBlocked>());
      expect(ChzzkApi.roomData(_live, null).unavailable, isA<StreamUnavailable>());
      expect(ChzzkApi.unavailable(null), isA<StreamUnavailable>());
    });

    test('20-3 is blocked: accumulateCount is 0 on every open live, set only after it closed', () {
      for (final sample in ['S06-live-detail-live', 'S06-live-detail-region', 'S06-live-detail-adult']) {
        expect(((jsonDecode(_sample(sample).body) as Map)['content'] as Map)['accumulateCount'], 0, reason: sample);
      }
      expect(((jsonDecode(_sample('S06-live-detail-offline').body) as Map)['content'] as Map)['accumulateCount'], 161);
      for (final sample in ['S03-lives-p1', 'S03-lives-p2', 'S02-category-lives-p1', 'S02-category-lives-p2']) {
        expect(_rows(sample).map((row) => row['accumulateCount']), everyElement(0), reason: sample);
      }
      expect(AudiencePlatformCapability.of('chzzk').hasTotalViewers, isFalse);
    });
  });

  group('livePlaybackJson', () {
    test('HLS and LLHLS of protocol HLS, in order, each master once', () {
      final media = ChzzkApi.media(
        _playback([
          {'mediaId': 'DASH', 'protocol': 'DASH', 'path': 'https://livecloud.akamaized.net/a.mpd'},
          ..._twoMedia,
          {'mediaId': 'HLS', 'protocol': 'HLS', 'path': _hlsMaster},
          {'mediaId': 'LOW', 'protocol': 'HLS', 'path': 'https://livecloud.akamaized.net/low.m3u8'},
        ]),
      );
      expect(media.map((item) => item.id), ['HLS', 'LLHLS']);
      expect(media.first.url, Uri.parse(_hlsMaster));
      expect(ChzzkApi.media(null), isEmpty);
      expect(ChzzkApi.media(''), isEmpty);
      expect(
        ChzzkApi.media(
          _playback([
            {'mediaId': 'DASH', 'protocol': 'DASH', 'path': 'https://livecloud.akamaized.net/a.mpd'},
          ]),
        ),
        isEmpty,
        reason: 'no HLS master: nothing to play, not a changed API',
      );
    });

    test('the recorded playback has the two masters of S07', () {
      final live = (jsonDecode(_sample('S06-live-detail-live').body) as Map)['content'] as Map;
      final media = ChzzkApi.media(live['livePlaybackJson']);
      expect(media.map((item) => item.url.path), [
        _sample('S07-master-hls').url.path,
        _sample('S07-master-llhls').url.path,
      ]);
    });

    test('masters must be plain https URLs on akamaized.net; with no usable one it is ApiChanged', () {
      for (final path in [
        'http://livecloud.akamaized.net/a.m3u8',
        'https://akamaized.net.example.com/a.m3u8',
        'https://user@livecloud.akamaized.net/a.m3u8',
        'https://livecloud.akamaized.net/a.m3u8#x',
        'https://livecloud.akamaized.net/a b.m3u8',
        '',
        null,
      ]) {
        final item = {'mediaId': 'HLS', 'protocol': 'HLS', 'path': path};
        expect(() => ChzzkApi.media(_playback([item])), throwsA(isA<ApiChanged>()), reason: '$path');
        // Unified rule: a bad master only drops itself (3.x refused the live).
        expect(ChzzkApi.media(_playback([item, _twoMedia.last])).map((media) => media.id), ['LLHLS'], reason: '$path');
      }
      expect(
        ChzzkApi.media(
          _playback([
            {'mediaId': 'HLS'},
            _twoMedia.first,
          ]),
        ).map((media) => media.id),
        ['HLS'],
        reason: 'an item without protocol',
      );
      expect(
        () => ChzzkApi.media(_playback([for (var index = 0; index < 17; index++) _twoMedia.first])),
        throwsA(isA<ApiChanged>()),
      );
    });
  });

  group('S07 qualities and lines', () {
    for (final (name, mediaId) in [('S07-master-hls', 'HLS'), ('S07-master-llhls', 'LLHLS')]) {
      test('$name: same qualities and URLs as 3.x', () {
        final fixture = _sample(name);
        final qualities = ChzzkApi.qualities([
          (media: ChzzkMedia(mediaId, fixture.url), body: fixture.body),
        ], issuedAt: fixture.capturedAt);
        final legacy = _maps(_value(name, 'qualities'));
        expect(qualities.map((quality) => quality.quality), legacy.map((quality) => quality['quality']));
        expect(qualities.map((quality) => quality.id), legacy.map((quality) => quality['id']));
        expect(qualities.map((quality) => quality.sort), legacy.map((quality) => quality['sort']));
        for (final (index, quality) in qualities.indexed) {
          final lines = quality.data! as List<LivePlayLine>;
          expect(lines.map((line) => line.url), legacy[index]['data'], reason: '${quality.id}');
          expect(lines.map((line) => line.lineId), everyElement(mediaId));
        }
      });
    }

    test('S06-live-detail-live: both masters make one quality list, HLS line first (3.x)', () {
      final live = (jsonDecode(_sample('S06-live-detail-live').body) as Map)['content'] as Map;
      final media = ChzzkApi.media(live['livePlaybackJson']);
      final hls = _sample('S07-master-hls');
      final qualities = ChzzkApi.qualities([
        (media: media[0], body: hls.body),
        (media: media[1], body: _sample('S07-master-llhls').body),
      ], issuedAt: hls.capturedAt);
      final legacy = _maps(_value('S06-live-detail-live', 'getPlayQualites'));
      expect(qualities.map((quality) => quality.quality), legacy.map((quality) => quality['quality']));
      expect(qualities.map((quality) => quality.id), ['1080p60', '720p60', '480p', '360p', '144p']);
      expect(qualities.map((quality) => quality.sort), legacy.map((quality) => quality['sort']));
      final urls = (_legacy('S06-live-detail-live')['getPlayUrls'] as Map).cast<String, dynamic>();
      for (final (index, quality) in qualities.indexed) {
        final lines = quality.data! as List<LivePlayLine>;
        expect(lines.map((line) => line.url), legacy[index]['data']);
        expect(lines.map((line) => line.url), urls[quality.id]);
        expect(lines.map((line) => line.lineId), ['HLS', 'LLHLS']);
      }
    });

    test('lines carry the media headers, HLS, the codec and the token lease', () {
      final fixture = _sample('S07-master-hls');
      final best = ChzzkApi.qualities([
        (media: ChzzkMedia('HLS', fixture.url), body: fixture.body),
      ], issuedAt: fixture.capturedAt).first;
      final line = (best.data! as List<LivePlayLine>).single;
      expect(line.headers, {
        'user-agent': ChzzkApi.userAgent,
        'referer': 'https://chzzk.naver.com/',
      }, reason: "3.x's PlaybackHeaderResolver branch for CHZZK");
      expect(line.format, StreamFormat.hls);
      expect(line.codec, 'avc');
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(1790586285 * 1000, isUtc: true);
      expect(line.lease!.expiresAt, expiresAt, reason: "the variant's hdntl exp");
      expect(line.lease!.refreshAt, expiresAt.subtract(const Duration(minutes: 10)));
      expect(line.lease!.cutsConnection, isTrue);
      expect(expiresAt.difference(fixture.capturedAt), greaterThan(const Duration(hours: 16)));
    });

    test("a variant without hdntl takes the master's hdnts; short lifetimes renew at a quarter", () {
      final issuedAt = DateTime.utc(2030);
      final seconds = issuedAt.millisecondsSinceEpoch ~/ 1000;
      final master = Uri.parse('https://livecloud.akamaized.net/a/m.m3u8?hdnts=st=1~exp=${seconds + 400}~acl=*~hmac=x');
      final lease = ChzzkApi.lease(master.resolve('720p/c.m3u8'), master: master, issuedAt: issuedAt)!;
      expect(lease.expiresAt, issuedAt.add(const Duration(seconds: 400)));
      expect(lease.refreshAt, issuedAt.add(const Duration(seconds: 300)));
      expect(ChzzkApi.masterExpiry(master), issuedAt.add(const Duration(seconds: 400)));
      expect(
        ChzzkApi.lease(master.resolve('c.m3u8'), master: master, issuedAt: issuedAt.add(const Duration(hours: 1))),
        isNull,
      );
      expect(
        ChzzkApi.lease(
          Uri.parse('https://livecloud.akamaized.net/c.m3u8'),
          master: Uri.parse('https://livecloud.akamaized.net/m.m3u8'),
          issuedAt: issuedAt,
        ),
        isNull,
      );
      expect(ChzzkApi.masterExpiry(Uri.parse('https://livecloud.akamaized.net/m.m3u8')), isNull);
    });

    test('lines are handed out until one is due; masters are asked until their token nearly expires', () {
      final fixture = _sample('S07-master-hls');
      final qualities = ChzzkApi.qualities([
        (media: ChzzkMedia('HLS', fixture.url), body: fixture.body),
      ], issuedAt: fixture.capturedAt);
      final refreshAt = (qualities.first.data! as List<LivePlayLine>).first.lease!.refreshAt;
      expect(ChzzkApi.linesFresh(qualities, fixture.capturedAt), isTrue);
      expect(ChzzkApi.linesFresh(qualities, refreshAt.subtract(const Duration(seconds: 1))), isTrue);
      expect(ChzzkApi.linesFresh(qualities, refreshAt), isFalse);
      final media = [ChzzkMedia('HLS', fixture.url)];
      final expiry = ChzzkApi.masterExpiry(fixture.url)!;
      expect(ChzzkApi.mastersFresh(media, fixture.capturedAt), isTrue);
      expect(ChzzkApi.mastersFresh(media, expiry.subtract(const Duration(minutes: 11))), isTrue);
      expect(ChzzkApi.mastersFresh(media, expiry.subtract(const Duration(minutes: 10))), isFalse);
      expect(
        ChzzkApi.mastersFresh([ChzzkMedia('HLS', Uri.parse('https://livecloud.akamaized.net/m.m3u8'))], expiry),
        isTrue,
      );
    });

    test('ranked by height then bandwidth; 60 at 50 fps or more; same URL once', () {
      final master = Uri.parse(_hlsMaster);
      final qualities = ChzzkApi.qualities([
        (
          media: ChzzkMedia('HLS', master),
          body: _masterText([
            '#EXT-X-STREAM-INF:BANDWIDTH=900,RESOLUTION=1280x720,FRAME-RATE=30.000',
            '720a.m3u8',
            '#EXT-X-STREAM-INF:BANDWIDTH=2000,RESOLUTION=1280x720,FRAME-RATE=50.000',
            '720b.m3u8',
            '#EXT-X-STREAM-INF:BANDWIDTH=1000,RESOLUTION=1280x720,FRAME-RATE=29.970',
            '720c.m3u8',
            '#EXT-X-STREAM-INF:BANDWIDTH=5000,RESOLUTION=640x360',
            '360.m3u8',
            '#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"',
            'audio.m3u8',
          ]),
        ),
        (
          media: ChzzkMedia('LLHLS', Uri.parse(_llhlsMaster)),
          body: _masterText([
            '#EXT-X-STREAM-INF:BANDWIDTH=900,RESOLUTION=1280x720,CODECS="hvc1.1.6.L93.B0"',
            '720a.m3u8',
          ]),
        ),
      ], issuedAt: DateTime.utc(2030));
      expect(qualities.map((quality) => quality.id), ['720p60', '720p', '360p'], reason: 'audio only left out');
      expect(qualities.map((quality) => quality.quality), ['720p60 · HLS', '720p · HLS', '360p · HLS']);
      expect(qualities[1].sort, 720 * 10000000 + 900, reason: 'the first variant of the quality');
      final lines = qualities[1].data! as List<LivePlayLine>;
      expect(lines.map((line) => line.url), [
        'https://livecloud.akamaized.net/chzzk/a/720a.m3u8',
        'https://livecloud.akamaized.net/chzzk/a/720c.m3u8',
      ], reason: 'the LLHLS 720a has the same URL');
      expect(lines.map((line) => line.codec), [null, null]);
    });

    test(
      'an unreadable master is ApiChanged alone and only loses its lines otherwise; no video is StreamUnavailable',
      () {
        final media = ChzzkMedia('HLS', Uri.parse(_hlsMaster));
        final unreadable = [
          'not a playlist',
          _masterText(['#EXT-X-SESSION-KEY:METHOD=AES-128', '#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1x1', 'a.m3u8']),
          _masterText(['#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1x1', 'http://livecloud.akamaized.net/a.m3u8']),
        ];
        final good = (
          media: ChzzkMedia('LLHLS', Uri.parse(_llhlsMaster)),
          body: _masterText(['#EXT-X-STREAM-INF:BANDWIDTH=900,RESOLUTION=1280x720', '720.m3u8']),
        );
        for (final body in unreadable) {
          expect(
            () => ChzzkApi.qualities([(media: media, body: body)], issuedAt: DateTime.utc(2030)),
            throwsA(isA<ApiChanged>()),
            reason: body,
          );
          final kept = ChzzkApi.qualities([(media: media, body: body), good], issuedAt: DateTime.utc(2030));
          expect(kept.single.id, '720p', reason: body);
          expect((kept.single.data! as List<LivePlayLine>).map((line) => line.lineId), ['LLHLS']);
        }
        expect(
          () => ChzzkApi.qualities([
            (media: media, body: _masterText(['#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"', 'audio.m3u8'])),
          ], issuedAt: DateTime.utc(2030)),
          throwsA(isA<StreamUnavailable>()),
        );
        expect(() => ChzzkApi.qualities(const [], issuedAt: DateTime.utc(2030)), throwsA(isA<StreamUnavailable>()));
      },
    );

    test('codecs', () {
      expect(ChzzkApi.codecOf('avc1.640028,mp4a.40.2'), 'avc');
      expect(ChzzkApi.codecOf('mp4a.40.2, avc3.4D001F'), 'avc');
      expect(ChzzkApi.codecOf('hev1.1.6.L93.B0,mp4a.40.2'), 'hevc');
      expect(ChzzkApi.codecOf('HVC1.1.6'), 'hevc');
      expect(ChzzkApi.codecOf('mp4a.40.2'), isNull);
      expect(ChzzkApi.codecOf(null), isNull);
    });

    test('the resolution of a quality: its lines, applied as asked; a quality not offered is StreamUnavailable', () {
      final fixture = _sample('S07-master-hls');
      final qualities = ChzzkApi.qualities([
        (media: ChzzkMedia('HLS', fixture.url), body: fixture.body),
      ], issuedAt: fixture.capturedAt);
      final resolution = ChzzkApi.resolution(qualities, const LivePlayQuality(quality: 'any', id: '480p'));
      expect(resolution.appliedQualityData, '480p');
      expect(resolution.lines.single.url, contains('/480p/'));
      expect(
        () => ChzzkApi.resolution(qualities, const LivePlayQuality(quality: '4K', id: '2160p')),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test("the quality ids and names are 3.x's: no id map for M9", () {
      final legacy = _maps(_value('S06-live-detail-live', 'getPlayQualites'));
      expect(legacy.map((quality) => quality['id']), ['1080p60', '720p60', '480p', '360p', '144p']);
      expect(legacy.map((quality) => quality['quality']), everyElement(endsWith(' · HLS')));
    });
  });

  group('answers', () {
    test("statuses as 3.x's _read classed them", () {
      expect(ChzzkApi.statusError(200, 'x'), isNull);
      expect(ChzzkApi.statusError(400, 'x'), isA<ApiChanged>());
      expect(ChzzkApi.statusError(401, 'x'), isA<RiskControl>());
      expect(ChzzkApi.statusError(403, 'x'), isA<RiskControl>());
      expect(ChzzkApi.statusError(404, 'x'), isA<NotFound>());
      expect(ChzzkApi.statusError(429, 'x'), isA<RateLimited>());
      for (final status in [500, 503, 302, 204, 0]) {
        expect(ChzzkApi.statusError(status, 'x'), isA<NetworkFailure>(), reason: '$status');
      }
    });

    test('code other than 200, not JSON, too long: ApiChanged', () {
      expect(() => ChzzkApi.content(_api({}, code: 9004), what: 'x'), throwsA(isA<ApiChanged>()));
      expect(() => ChzzkApi.content('<html>', what: 'x'), throwsA(isA<ApiChanged>()));
      expect(() => ChzzkApi.content('[]', what: 'x'), throwsA(isA<ApiChanged>()));
      expect(() => ChzzkApi.content(' ' * (ChzzkApi.responseLimit + 1), what: 'x'), throwsA(isA<ApiChanged>()));
      expect(ChzzkApi.content(_api({'a': 1}), what: 'x'), {'a': 1});
    });

    test('a master: 404 means the stream is gone; others as the API', () {
      expect(() => ChzzkApi.master('', what: 'HLS master', status: 404), throwsA(isA<StreamUnavailable>()));
      expect(() => ChzzkApi.master('', what: 'HLS master', status: 403), throwsA(isA<RiskControl>()));
      expect(() => ChzzkApi.master('', what: 'HLS master', status: 502), throwsA(isA<NetworkFailure>()));
      expect(ChzzkApi.master('#EXTM3U', what: 'HLS master'), '#EXTM3U');
    });
  });

  group('links', () {
    test("3.x's ChzzkLink: the live page, any case, returned in lower case", () {
      for (final (url, id) in [
        ('https://chzzk.naver.com/live/$_live', _live),
        ('http://chzzk.naver.com/live/$_live/', _live),
        ('https://CHZZK.naver.com/live/${_live.toUpperCase()}', _live),
        ('https://chzzk.naver.com//live//$_live?from=share#t', _live),
        ('  https://chzzk.naver.com/live/$_live  ', _live),
      ]) {
        expect(ChzzkApi.roomIdFromUrl(url), id, reason: url);
      }
    });

    test('20-4: the channel page, with or without a tab, is the channel (3.x did not take it)', () {
      for (final url in [
        'https://chzzk.naver.com/$_live',
        'https://chzzk.naver.com/${_live.toUpperCase()}/',
        'http://chzzk.naver.com/$_live?from=share#t',
        'https://chzzk.naver.com/$_live/videos',
        'https://chzzk.naver.com/$_live/community',
      ]) {
        expect(ChzzkApi.roomIdFromUrl(url), _live, reason: url);
      }
    });

    test('not rooms: other hosts, other paths, user info, other schemes', () {
      for (final url in [
        'https://m.chzzk.naver.com/live/$_live',
        'https://game.naver.com/live/$_live',
        'https://chzzk.naver.com/live/${_live.substring(1)}',
        'https://chzzk.naver.com/live/$_live/extra',
        'https://chzzk.naver.com/$_live/videos/1',
        'https://chzzk.naver.com/${_live.substring(1)}',
        'https://chzzk.naver.com/video/123',
        'https://chzzk.naver.com/live',
        'https://chzzk.naver.com/',
        'https://user@chzzk.naver.com/live/$_live',
        'ftp://chzzk.naver.com/live/$_live',
        'https://chzzk.naver.com/live/%FF',
        '',
      ]) {
        expect(ChzzkApi.roomIdFromUrl(url), isNull, reason: url);
      }
    });

    test('the room link is the live page', () {
      expect(ChzzkApi.roomUrl(_live), 'https://chzzk.naver.com/live/$_live');
      expect(ChzzkApi.isChannelId(_live), isTrue);
      expect(ChzzkApi.isChannelId(_live.toUpperCase()), isFalse, reason: '3.x checked lower case');
    });
  });
}
