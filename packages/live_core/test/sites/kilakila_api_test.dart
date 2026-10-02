// KilaKila parsing against the recorded samples, compared field by field
// with 3.x's frozen output (expected.json, written by
// fixtures/kilakila/legacy_expected.dart from 3.x's KilakilaApi, KilakilaLink
// and KilakilaSite). Every intended difference is listed with its reason
// (an M4.U item number, docs/specs/UPGRADES.md, for the approved upgrades);
// everything else must match. The synthetic cases port 3.x's
// kilakila_api_test.dart, kilakila_owner_test.dart, kilakila_link_test.dart
// and kilakila_directory_contract_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('kilakila', name);

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

/// The keys [actual] (a projection) has beyond 3.x's [legacy] map, which
/// leaves out nulls and empty collections: the v4 keys M2.1 added
/// (`startedAt`, `restriction`; 3.x ignores them when reading) and the
/// introduction 3.x did not read.
Set<String> _newKeys(Map<String, Object?> actual, Map<String, dynamic> legacy) => {
  for (final MapEntry(:key, :value) in actual.entries)
    if (value != null && !(value is Iterable && value.isEmpty) && !(value is Map && value.isEmpty))
      if (!legacy.containsKey(key)) key,
};

/// What the upgrades change on a live broadcast's room: the listeners
/// (15-2) and so the audience metric.
const _audience = {'onlineViewers', 'totalViewers', 'audienceMetricType'};

/// The detail keys 3.x did not read (M4.15 difference 6).
const _profileKeys = {'introduction', 'followers'};

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

/// The outcome of a counted legacy call (`{value, requests}`).
Object? _value(String name, String key) => (_legacy(name)[key] as Map<String, dynamic>)['value'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

const _liveOwner = '3674092253247';
const _liveBroadcast = '2268450556051718173';
const _rid = '9007199254740993123';
const _flv = 'https://pull.live.hongrenshuo.com.cn/hrs/$_rid.flv?auth_key=fixture%2Bonly&extra=one%2Ftwo';
const _hls = 'https://pull.live.hongrenshuo.com.cn/hrs/$_rid.m3u8?auth_key=fixture%2Bonly';

/// 3.x's test anchor.
Map<String, dynamic> _owner() => {
  'id': 100,
  'nickname': 'Fixture',
  'headPortraitUrl': 'https://img.example/avatar.png',
};

/// 3.x's test broadcast of `getRoomInfo`.
Map<String, dynamic> _info() => {
  'roomIdStr': _rid,
  'uid': 100,
  'userInfo': _owner(),
  'title': 'Music',
  'status': 4,
  'goldPrice': 0,
  'watchNumber': 9,
  'defaultBackgroundPicUrl': 'https://img.example/cover.png',
  'flvPlayUrl': _flv,
  'hlsPlayUrl': _hls,
  'pushFlow': 'rtmp://push.example/SECRET_NOT_A_PLAY_URL',
};

String _roomInfo(Object? b, {int code = 200}) => jsonEncode({
  'h': {'code': code, 'success': code == 200},
  'b': b,
});

KilakilaBroadcast _parseInfo(Object? b, {int code = 200, String? uid}) => KilakilaApi.roomInfo(
  _roomInfo(b, code: code),
  broadcastId: _rid,
  uid: uid,
);

/// 3.x's test timeline row.
Map<String, dynamic> _row({String rid = _rid, int dataType = 8, Object uid = 100}) => {
  'dataType': dataType,
  'roomResq': _info()
    ..['roomIdStr'] = rid
    ..['uid'] = uid,
  'userResp': _owner()..['id'] = uid,
};

String _page({List<Object>? rows, Object page = 1, Object size = 10, Object last = false}) => jsonEncode({
  'code': 200,
  'data': {
    'body': {
      'h': {'code': 200, 'success': true},
      'b': {
        'pageNo': page,
        'pageSize': size,
        'isLastPage': last,
        'data': rows ?? [_row()],
      },
    },
  },
});

LiveDirectoryPage _timeline(String body, {int page = 1, int pageSize = 10, int type = 0}) =>
    KilakilaApi.timelinePage(body, page: page, pageSize: pageSize, type: type);

/// 3.x's test profile.
String _profile({Object? card, Map<String, dynamic>? user, int code = 200, bool withCard = true}) => jsonEncode({
  'code': code,
  'data': {
    'userResp': user ?? {'nickname': 'Fixture anchor', 'headPortraitUrl': 'https://img.example/avatar.png'},
    if (withCard) 'liveCard': card,
  },
});

Map<String, dynamic> _card([String room = _rid]) => {
  'roomIdStr': room,
  'uid': 100,
  'status': 4,
  'goldPrice': 0,
  'title': 'Fixture live',
  'roomSourceType': 0,
  'recommendSource': 0,
  'flvPlayUrl': 'https://pull.live.hongrenshuo.com.cn/hrs/$room.flv?auth_key=fixture',
  'pushFlow': 'rtmp://push.example/DO_NOT_USE',
};

String _search(String anchors) => '<html><div class="userList">$anchors</div></html>';

KilakilaRoomData _data(KilakilaBroadcast broadcast, {DateTime? issuedAt}) =>
    KilakilaRoomData(issuedAt: issuedAt ?? DateTime.utc(2026, 9, 27), broadcast: broadcast);

List<int> _hex(String text) => [
  for (var i = 0; i < text.length; i += 2) int.parse(text.substring(i, i + 2), radix: 16),
];

List<Map<String, dynamic>> _vectors() =>
    (jsonDecode(File('../../fixtures/kilakila/S09-share-vectors/vectors.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

void main() {
  group('S01 timelines', () {
    for (final (name, page, type) in [
      ('S01-timeline-hot-p1', 1, 0),
      ('S01-timeline-hot-p2', 2, 0),
      ('S01-timeline-hot-last', 55, 0),
      ('S01-timeline-new-p1', 1, 107),
    ]) {
      test('$name matches 3.x', () {
        final fixture = _sample(name);
        final result = _timeline(fixture.body, page: page, type: type);
        final legacy = _value(name, 'getDirectoryPage')! as Map<String, dynamic>;
        expect((result.page, result.hasMore), (legacy['page'], legacy['hasMore']));
        final rooms = _maps(legacy['rooms']);
        expect(result.rooms.map((room) => room.roomId), rooms.map((room) => room['roomId']));
        for (final (index, room) in result.rooms.indexed) {
          // 15-2: the cumulative listeners (watchNumber); unified rules: the
          // restriction (none, a new key).
          _expectParity(_projection(room), rooms[index], changed: _audience, reason: '$name[$index]');
          expect(_newKeys(_projection(room), rooms[index]), {'restriction'});
          expect((room.restriction, room.startedAt), (LiveRestriction.none, null), reason: 'lists have no start');
          expect(room.data, isNull, reason: 'list cards carry no stream data');
        }
        expect(_value(name, 'getCategoryRooms'), legacy['rooms']);
      });
    }

    test('the room is the anchor: the uid, the anchor page, no broadcast id (REG-KILAKILA-001)', () {
      final result = _timeline(_sample('S01-timeline-hot-p1').body);
      final first = result.rooms.first;
      expect(first.roomId, '3738290188297');
      expect(first.userId, first.roomId);
      expect(first.link, 'https://live.hongrenshuo.com.cn/index/roomuser/uid/3738290188297');
      expect(jsonEncode(first.toJson()), isNot(contains('2267924182039789690')));
      expect(first.isLiveNow, isTrue);
    });

    test('15-2: cards show watchNumber as cumulative listeners, never as online (REG-KILAKILA-003)', () {
      final rooms = _timeline(_sample('S01-timeline-hot-p1').body).rooms;
      expect(rooms.map((room) => room.totalViewers), [
        '635',
        '617',
        '1132',
        '287',
        '355',
        '327',
        '156',
        '225',
        '113',
        '58',
      ]);
      for (final room in rooms) {
        expect((room.watching, room.onlineViewers, room.popularity), ('', '', ''));
        expect(room.audienceMetricType, AudienceMetricType.onlineViewers);
        expect(room.audienceValue(preferRealOnline: false, platformEnabled: true), room.totalViewers);
        expect(room.audienceType(preferRealOnline: false, platformEnabled: true), AudienceMetricType.totalViewers);
        expect(
          room.audienceValue(preferRealOnline: true, platformEnabled: true),
          isEmpty,
          reason: 'online listeners come only with room entry and refresh',
        );
      }
      final capability = AudiencePlatformCapability.of('kilakila');
      expect((capability.hasPopularity, capability.hasTotalViewers), (false, true));
      expect(capability.onlineAvailability, AudienceOnlineAvailability.roomRealtime);
    });

    test('the rising stars use dataType 2; the hot timeline does not take them', () {
      final body = _sample('S01-timeline-new-p1').body;
      expect(_timeline(body, type: 107).rooms, hasLength(10));
      expect(_timeline(body).rooms, isEmpty);
      expect(
        _timeline(
          _page(
            rows: [
              _row(dataType: 2),
              _row(rid: '123', uid: 101),
            ],
          ),
        ).rooms,
        hasLength(1),
      );
      expect(
        _timeline(
          _page(
            rows: [
              _row(dataType: 3),
              _row(rid: '123', uid: 101),
            ],
          ),
          type: 107,
        ).rooms,
        hasLength(1),
      );
      expect(
        () => _timeline(_page(rows: [_row(dataType: 2)..['userResp'] = (_owner()..['id'] = 101)]), type: 107),
        throwsA(isA<ApiChanged>()),
        reason: 'an accepted rising-star row still needs its own anchor',
      );
    });

    test('pages end at isLastPage, not at a page of other row types (3.x; REG-KILAKILA-005)', () {
      expect(_timeline(_sample('S01-timeline-hot-last').body, page: 55).hasMore, isFalse);
      for (final last in [true, false]) {
        final page = _timeline(
          _page(
            rows: [
              {'dataType': 7},
            ],
            last: last,
          ),
        );
        expect(page.rooms, isEmpty);
        expect(page.hasMore, !last);
      }
    });

    test('each broadcast and then each anchor once; other rows skipped (3.x)', () {
      final page = _timeline(
        _page(
          page: 2,
          size: 12,
          rows: [
            _row(),
            _row(),
            {'dataType': 9},
            _row(rid: '123'),
            _row(rid: '124', uid: 101),
          ],
        ),
        page: 2,
        pageSize: 12,
        type: 107,
      );
      expect(page.rooms.map((room) => room.roomId), ['100', '101']);
      expect(page.hasMore, isTrue);
      expect(page.page, 2);
    });

    test('15-3: the rising stars end at a page without rows and without isLastPage (S01-timeline-new-tail)', () {
      final tail = _sample('S01-timeline-new-tail');
      expect(tail.url.queryParameters, containsPair('type', '107'));
      final page = _timeline(tail.body, page: 51, type: 107);
      expect(page.rooms, isEmpty);
      expect(page.hasMore, isFalse, reason: '3.x: ApiChanged (no isLastPage)');
      for (final last in [false, null]) {
        final body = jsonDecode(_page(rows: [])) as Map<String, dynamic>;
        final b = ((body['data'] as Map)['body'] as Map)['b'] as Map;
        if (last == null) b.remove('isLastPage');
        expect(_timeline(jsonEncode(body)).hasMore, isFalse, reason: 'isLastPage $last');
      }
      final withRows = jsonDecode(_page()) as Map<String, dynamic>;
      (((withRows['data'] as Map)['body'] as Map)['b'] as Map).remove('isLastPage');
      final open = _timeline(jsonEncode(withRows));
      expect((open.rooms.length, open.hasMore), (1, true), reason: 'a page with rows and no isLastPage goes on');
    });

    test('15-3: a timeline ends at page 100 (REG-KILAKILA-005)', () {
      expect(KilakilaApi.maxPages, 100);
      expect(_timeline(_page(page: 99), page: 99).hasMore, isTrue);
      expect(_timeline(_page(page: 100), page: 100).hasMore, isFalse);
      expect(_timeline(_page(page: 100, last: true), page: 100).hasMore, isFalse);
    });

    test('a broken row is left out; the rest of the page stays (unified rules, 容错)', () {
      final page = _timeline(
        _page(
          rows: [
            'not a row',
            <String, Object?>{},
            _row(rid: '1')..['userResp'] = <String, Object?>{},
            _row(rid: '2')..['roomResq'] = (_info()..['title'] = ' '),
            _row(rid: '3', uid: 101)..['userResp'] = (_owner()..['id'] = 102),
            _row(),
            {'dataType': 9},
          ],
        ),
      );
      expect(page.rooms.map((room) => room.roomId), ['100'], reason: '3.x failed the whole page');
      expect(page.hasMore, isTrue);
    });

    test('a page that does not echo the request, or whose rows are all broken, is ApiChanged (3.x)', () {
      for (final body in [
        _page(page: 2),
        _page(size: 20),
        _page(last: 'false'),
        jsonEncode({
          'code': 200,
          'data': {
            'body': {
              'h': {'code': 200, 'success': true},
            },
          },
        }),
        jsonEncode({'code': 500, 'data': null}),
        jsonEncode({
          'code': 200,
          'data': {
            'body': {
              'h': {'code': 5966, 'success': false},
            },
          },
        }),
        _page(rows: List<Object>.filled(1001, {'dataType': 9})),
        _page(rows: [<String, Object?>{}]),
        _page(rows: [_row()..['userResp'] = <String, Object?>{}]),
        _page(rows: [_row()..['roomResq'] = (_info()..['title'] = ' ')]),
        _page(
          rows: [
            {'dataType': 9},
            'not a row',
          ],
        ),
        'not json',
      ]) {
        expect(() => _timeline(body), throwsA(isA<ApiChanged>()), reason: body);
      }
    });

    test("the catalog is 3.x's: one category, the two timelines", () {
      final legacy = _maps(_legacy('S01-timeline-hot-p1')['getCategores']).single;
      final category = KilakilaApi.categories().single;
      expect((category.id, category.name), (legacy['id'], legacy['name']));
      final areas = _maps(legacy['children']);
      expect(category.children, hasLength(areas.length));
      for (final (index, area) in category.children.indexed) {
        _expectParity(area.toJson(), areas[index], reason: 'area $index');
      }
      expect(_legacy('S01-timeline-hot-p1')['getCategores(2)'], 0);
      expect(_legacy('S01-timeline-hot-p1')['directoryNoticeKey'], 'kilakila_directory_scope');
    });

    test('an area that is not a KilaKila timeline is a caller error (3.x)', () {
      expect(KilakilaApi.timelineType(null), 0);
      expect(KilakilaApi.timelineType(KilakilaApi.categories().single.children.last), 107);
      for (final area in [
        const LiveArea(platform: 'other', areaType: 'timeline', areaId: '0'),
        const LiveArea(platform: 'kilakila', areaId: '0'),
        const LiveArea(platform: 'kilakila', areaType: 'timeline', areaId: '99'),
      ]) {
        expect(() => KilakilaApi.timelineType(area), throwsArgumentError);
      }
    });
  });

  group('S03 search', () {
    for (final name in ['S03-search', 'S03-search-p2', 'S03-search-empty']) {
      test('$name matches 3.x', () {
        final fixture = _sample(name);
        final rooms = KilakilaApi.searchPage(fixture.body, status: fixture.status);
        final legacy = _maps(_value(name, 'searchRooms'));
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        for (final (index, room) in rooms.indexed) {
          _expectParity(_projection(room), legacy[index], reason: '$name[$index]');
          expect(room.isLiveStatusPending, isTrue, reason: 'the page says nothing about broadcasts');
        }
      });
    }

    test('names keep their characters; ampersands and emoji are text', () {
      final names = KilakilaApi.searchPage(_sample('S03-search').body).map((room) => room.nick);
      expect(names, contains('海盐&芝士『散修』🍰'));
    });

    test("3.x's synthetic page: each anchor once, avatar from the header image", () {
      final rooms = KilakilaApi.searchPage(
        _search(
          [
            '<a href="/zhubo/100"><div class="anchor-name">音乐主播</div>',
            '<div class="anchorHeaderImg"><img src="https://img.example/avatar.png"></div></a>',
            '<a href="/zhubo/100"><div class="anchor-name">音乐主播</div></a>',
            '<a href="/zhubo/101"><div class="anchorInfo"><div class="anchor-name"> 音乐&amp;电台 </div></div></a>',
          ].join(),
        ),
      );
      expect(rooms.map((room) => room.roomId), ['100', '101']);
      expect(rooms.map((room) => room.nick), ['音乐主播', '音乐&电台']);
      expect(rooms.first.avatar, 'https://img.example/avatar.png');
      expect(rooms.last.avatar, isEmpty);
      expect(rooms.first.title, rooms.first.nick);
    });

    test('comments and scripts are not markup; only the list counts', () {
      final rooms = KilakilaApi.searchPage(
        [
          '<!-- <div class="userList"><a href="/zhubo/1">x</a></div> -->',
          "<script>var x = '<div class=\"userList\"><a href=\"/zhubo/2\">';</script>",
          '<div class="box userList"><a href="/zhubo/100"><div class="anchor-name">A</div></a><div>ad</div></div>',
          '<a href="/zhubo/200"><div class="anchor-name">outside</div></a>',
        ].join(),
      );
      expect(rooms.map((room) => room.roomId), ['100']);
    });

    test('a broken entry is left out; the rest of the page stays (unified rules, 容错)', () {
      final rooms = KilakilaApi.searchPage(
        _search(
          [
            '<a href="https://evil.test/zhubo/1"><div class="anchor-name">x</div></a>',
            '<a href="/zhubo/2"><div class="anchor-name"> </div></a>',
            '<a href="/zhubo/100"><div class="anchor-name">A</div></a>',
          ].join(),
        ),
      );
      expect(rooms.map((room) => room.roomId), ['100'], reason: '3.x failed the whole page');
    });

    test('an empty list is no result; a page whose entries are all broken is ApiChanged (3.x)', () {
      expect(KilakilaApi.searchPage('<div class="userList"></div>'), isEmpty);
      for (final html in [
        '<div class="userList"><a href="https://evil.test/zhubo/1">x</a></div>',
        '<div class="userList"><a href="/zhubo/1"><div class="anchor-name"> </div></a></div>',
        '<div class="userList"><a href="/zhubo/01"><div class="anchor-name">x</div></a></div>',
        '<div class="userList"><a><div class="anchor-name">x</div></a></div>',
        '<html>no list</html>',
        '<div class="userList">${'<div></div>' * 101}</div>',
      ]) {
        expect(() => KilakilaApi.searchPage(html), throwsA(isA<ApiChanged>()), reason: html);
      }
    });

    test("the page's path: keyword as one segment, /p/<n> after page 1 (3.x)", () {
      expect(KilakilaApi.searchUrl(' 音乐/ASMR ', 2).pathSegments, ['aboutus', 'serach', 'kw', '音乐/ASMR', 'p', '2']);
      expect(KilakilaApi.searchUrl('小', 1).toString(), _sample('S03-search').url.toString());
      expect(KilakilaApi.searchUrl('小', 2).toString(), _sample('S03-search-p2').url.toString());
    });

    test('15-5: a keyword over 100 UTF-16 units is cut there, never inside a surrogate pair (3.x refused it)', () {
      expect(KilakilaApi.keywordLimit, 100);
      expect(KilakilaApi.searchKeyword('a' * 100), 'a' * 100);
      expect(KilakilaApi.searchKeyword(' ${'a' * 101} '), 'a' * 100);
      expect(KilakilaApi.searchKeyword('小' * 150), '小' * 100);
      expect(KilakilaApi.searchKeyword('${'a' * 98}😀b'), '${'a' * 98}😀', reason: 'the pair ends at 100');
      expect(KilakilaApi.searchKeyword('${'a' * 99}😀'), 'a' * 99, reason: 'a cut pair is dropped');
      expect(KilakilaApi.searchKeyword('${'a' * 99} ${'b' * 10}'), 'a' * 99, reason: 'trimmed after the cut');
      expect(KilakilaApi.searchKeyword('  '), isEmpty);
      expect(KilakilaApi.searchUrl('小' * 150, 1).pathSegments[3], '小' * 100);
    });
  });

  group('S04 profiles', () {
    test("S04-owner-live: the refresh detail is 3.x's, with the introduction, followers, listeners and start", () {
      final profile = KilakilaApi.profile(_sample('S04-owner-live').body, uid: _liveOwner);
      final legacy = _value('S04-owner-live', 'getRoomDetailForRefresh')! as Map<String, dynamic>;
      final room = KilakilaApi.profileDetail(profile);
      // 3.x read neither the introduction nor the follower count (M4.15);
      // 15-2: the listeners; unified rules: the start and the restriction.
      _expectParity(_projection(room), legacy, changed: {..._profileKeys, ..._audience});
      expect(_newKeys(_projection(room), legacy), {'introduction', 'startedAt', 'restriction'});
      expect(room.introduction, startsWith('个播：晚22'));
      expect(room.followers, '19998');
      expect(room.isLiveNow, isTrue);
      expect((room.onlineViewers, room.totalViewers), ('193', '1136'));
      expect(room.audienceValue(preferRealOnline: true, platformEnabled: true), '193');
      expect(room.audienceValue(preferRealOnline: false, platformEnabled: true), '1136');
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 14, 6, 42, 790), reason: 'actualTime, not liveStartTime');
      expect(room.restriction, LiveRestriction.none);
      expect(profile.current!.broadcastId, _liveBroadcast);
      expect(room.data, isNull, reason: 'the card has no pull URLs');
    });

    test("S04-owner-live: the exact search result is 3.x's, with the listeners and start", () {
      final profile = KilakilaApi.profile(_sample('S04-owner-live').body, uid: _liveOwner);
      final legacy = _maps(_value('S04-owner-live', 'searchRooms(uid)')).single;
      final room = KilakilaApi.room(profile.current!);
      _expectParity(_projection(room), legacy, changed: _audience);
      expect(_newKeys(_projection(room), legacy), {'startedAt', 'restriction'});
      expect(_value('S04-owner-live', 'searchRooms(ownerUrl)'), _value('S04-owner-live', 'searchRooms(uid)'));
    });

    test('S04-owner-offline: 15-1: no advertised broadcast is offline (3.x: unknown)', () {
      final profile = KilakilaApi.profile(_sample('S04-owner-offline').body, uid: '1775178981381');
      expect(profile.current, isNull);
      final room = KilakilaApi.profileDetail(profile);
      final legacy = _value('S04-owner-offline', 'getRoomDetailForRefresh')! as Map<String, dynamic>;
      _expectParity(_projection(room), legacy, changed: {..._profileKeys, 'liveStatus'});
      expect(legacy['liveStatus'], LiveStatus.unknown.index);
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.isExplicitlyOfflineNow, isTrue);
      expect(room.followGroup, FollowGroup.offline);
      expect(room.title, isEmpty, reason: 'no title, never a placeholder');
      expect(_newKeys(_projection(room), legacy), {'introduction'}, reason: 'no start, no restriction while offline');
      expect((room.onlineViewers, room.totalViewers), ('', ''));
      final searched = KilakilaApi.profileRoom(profile);
      _expectParity(
        _projection(searched),
        _maps(_value('S04-owner-offline', 'searchRooms(uid)')).single,
        changed: {'liveStatus'},
      );
      expect((searched.effectiveLiveStatus, searched.title), (LiveStatus.offline, searched.nick));
    });

    test('S04-owner-notfound: code 1013 is NotFound (3.x)', () {
      expect(_value('S04-owner-notfound', 'getRoomDetailForRefresh'), {
        'throws': 'KilakilaException',
        'message': 'Kilakila notFound',
      });
      expect(() => KilakilaApi.profile(_sample('S04-owner-notfound').body, uid: '1'), throwsA(isA<NotFound>()));
    });

    test('empty cards are no broadcast; partial or foreign cards are ApiChanged (3.x)', () {
      for (final empty in [
        <String, Object?>{},
        {'roomSourceType': 0, 'recommendSource': 0},
      ]) {
        expect(
          KilakilaApi.profile(_profile(card: empty), uid: '100').current,
          isNull,
          reason: '$empty',
        );
      }
      final live = KilakilaApi.profile(_profile(card: _card()), uid: '100');
      expect(live.current!.broadcastId, _rid);
      expect(live.current!.flv, isNull, reason: 'a card carries no stream');
      for (final broken in <Object?>[
        null,
        <Object?>[],
        {'title': 'partial'},
        {'status': 4},
        {'roomSourceType': null},
        {'unexpected': 0},
        _card()..['uid'] = 200,
        _card()..['title'] = '',
      ]) {
        expect(
          () => KilakilaApi.profile(_profile(card: broken), uid: '100'),
          throwsA(isA<ApiChanged>()),
          reason: '$broken',
        );
      }
      expect(
        () => KilakilaApi.profile(_profile(withCard: false), uid: '100'),
        throwsA(isA<ApiChanged>()),
        reason: 'a missing card is not an empty one',
      );
    });

    test('the profile must name this anchor; other codes are ApiChanged (3.x)', () {
      for (final user in <Map<String, dynamic>?>[
        {},
        {'nickname': ''},
        {'nickname': 'x', 'id': 200},
      ]) {
        expect(
          () => KilakilaApi.profile(
            _profile(card: const <String, Object?>{}, user: user),
            uid: '100',
          ),
          throwsA(isA<ApiChanged>()),
          reason: '$user',
        );
      }
      expect(
        KilakilaApi.profile(
          _profile(card: const <String, Object?>{}, user: {'nickname': 'x', 'id': 100}),
          uid: '100',
        ).nick,
        'x',
      );
      for (final code in [1, 500]) {
        expect(() => KilakilaApi.profile(_profile(code: code), uid: '100'), throwsA(isA<ApiChanged>()));
      }
    });
  });

  group('S05 broadcasts and streams', () {
    final fixture = _sample('S05-room-live');

    test('S05-room-live: getRoomInfo matches 3.x (ids, names, cover, state, price, pull URLs)', () {
      final broadcast = KilakilaApi.roomInfo(fixture.body, broadcastId: _liveBroadcast, uid: _liveOwner);
      final legacy = _value('S05-room-live', 'detail(playback: true)')! as Map<String, dynamic>;
      expect(
        {
          'roomId': broadcast.broadcastId,
          'userId': broadcast.uid,
          'title': broadcast.title,
          'nick': broadcast.nick,
          'cover': broadcast.cover,
          'avatar': broadcast.avatar,
          'statusCode': broadcast.status,
          'goldPrice': broadcast.goldPrice,
          'isLive': broadcast.isLive,
          'media': {'flv': ?broadcast.flv, 'hls': ?broadcast.hls},
        },
        {...legacy}
          ..remove('watchNumber')
          ..remove('link'),
      );
      // getRoomInfo has the cumulative listeners, but neither the listeners
      // now nor the start (only the anchor's card has them).
      expect((broadcast.total, broadcast.online, broadcast.startedAt), (1135, null, null));
    });

    test('S04 + S05: room entry, its quality and lines match 3.x', () {
      final profile = KilakilaApi.profile(_sample('S04-owner-live').body, uid: _liveOwner);
      final broadcast = KilakilaApi.roomInfo(fixture.body, broadcastId: _liveBroadcast, uid: _liveOwner);
      final room = KilakilaApi.enteredRoom(profile, broadcast);
      final legacyRoom = _value('S04-owner-live', 'getRoomDetail')! as Map<String, dynamic>;
      // 15-7: the card's cover (3.x: getRoomInfo's default background);
      // 15-2: the listeners, now from the card and so far from getRoomInfo.
      _expectParity(_projection(room), legacyRoom, changed: {..._profileKeys, ..._audience, 'cover'});
      expect(_newKeys(_projection(room), legacyRoom), {'introduction', 'startedAt', 'restriction'});
      expect(legacyRoom['cover'], broadcast.cover, reason: "3.x's cover is getRoomInfo's gif");
      expect(room.cover, profile.current!.cover);
      expect(room.cover, endsWith('PC.png'));
      expect(room.cover, KilakilaApi.profileDetail(profile).cover, reason: 'the same cover as the refresh');
      expect((room.onlineViewers, room.totalViewers), ('193', '1135'));
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 14, 6, 42, 790));
      expect(room.restriction, LiveRestriction.none);

      final data = _data(broadcast, issuedAt: fixture.capturedAt);
      final quality = KilakilaApi.qualities(data).single;
      final legacy = _maps(_legacy('S04-owner-live')['getPlayQualites']);
      // 15-6: 3.x's two qualities FLV and HLS are one 原画 with two lines.
      expect(legacy.map((quality) => (quality['quality'], quality['id'], quality['sort'])), [
        ('FLV', 'flv', 0),
        ('HLS', 'hls', 0),
      ]);
      expect((quality.quality, quality.id, quality.sort), ('原画', 'original', 0));
      final resolution = KilakilaApi.resolution(data, quality);
      expect(resolution.urls, [for (final old in legacy) ...(old['getPlayUrls'] as List)]);
      expect(resolution.appliedQualityData, 'original');
      expect(resolution.lines.map((line) => (line.lineId, line.format)), [
        ('flv', StreamFormat.flv),
        ('hls', StreamFormat.hls),
      ]);
      for (final line in resolution.lines) {
        expect(line.headers, {'referer': 'https://live.kilakila.cn/', 'user-agent': 'Mozilla/5.0'});
        final lease = line.lease!;
        expect(lease.expiresAt, DateTime.fromMillisecondsSinceEpoch(1793120972 * 1000, isUtc: true));
        expect(lease.expiresAt!.difference(fixture.capturedAt).inHours, inInclusiveRange(719, 720));
        expect(lease.expiresAt!.difference(lease.refreshAt), const Duration(minutes: 10));
        expect(lease.cutsConnection, line.format == StreamFormat.hls);
      }
      // 3.x recovered the FLV quality; its URL is the first line now.
      final recovery = _value('S04-owner-live', 'resolvePlayUrlsForRecoveryRaw')! as Map<String, dynamic>;
      expect(recovery['urls'], [resolution.urls.first]);
      expect(recovery['appliedQualityData'], 'flv');
      for (final old in legacy) {
        final migrated = KilakilaApi.resolution(
          data,
          LivePlayQuality(quality: old['quality'] as String, id: old['id']),
        );
        expect(migrated.urls, resolution.urls, reason: '${old['id']}');
        expect(migrated.appliedQualityData, 'original', reason: '${old['id']}');
      }
    });

    test('15-6: the quality id map for M9', () {
      expect(KilakilaApi.legacyQualityIds, {'flv': 'original', 'hls': 'original'});
      expect(KilakilaApi.qualityIdFromLegacy('flv'), 'original');
      expect(KilakilaApi.qualityIdFromLegacy(' HLS '), 'original');
      expect(KilakilaApi.qualityIdFromLegacy('original'), 'original');
      expect(KilakilaApi.qualityIdFromLegacy('other'), 'other');
    });

    test("15-7: the card of another broadcast lends nothing; a card without a cover keeps getRoomInfo's", () {
      final broadcast = _parseInfo(_info(), uid: '100');
      final withCover = KilakilaApi.profile(
        _profile(
          card: _card()
            ..['backPic'] = 'https://img.example/back.png'
            ..['actualTime'] = 1790518002790
            ..['onlineNumber'] = 7,
        ),
        uid: '100',
      );
      final entered = KilakilaApi.enteredRoom(withCover, broadcast);
      expect((entered.cover, entered.onlineViewers, entered.totalViewers), ('https://img.example/back.png', '7', '9'));
      expect(entered.startedAt, DateTime.utc(2026, 9, 27, 14, 6, 42, 790));
      final bare = KilakilaApi.enteredRoom(KilakilaApi.profile(_profile(card: _card()), uid: '100'), broadcast);
      expect((bare.cover, bare.onlineViewers, bare.startedAt), ('https://img.example/cover.png', '', null));
      final other = KilakilaApi.enteredRoom(
        KilakilaApi.profile(_profile(card: _card('123')..['backPic'] = 'https://img.example/other.png'), uid: '100'),
        broadcast,
      );
      expect(other.cover, 'https://img.example/cover.png');
      final none = KilakilaApi.enteredRoom(
        KilakilaApi.profile(_profile(card: const <String, Object?>{}), uid: '100'),
        broadcast,
      );
      expect((none.cover, none.isLiveNow), ('https://img.example/cover.png', true));
    });

    test('S05-room-replay: 15-1: an ended broadcast (10) is offline (3.x: unknown); its stream is unavailable', () {
      final replay = _sample('S05-room-replay');
      final broadcast = KilakilaApi.roomInfo(replay.body, broadcastId: '2261269383617708096');
      final legacy = _value('S05-room-replay', 'detail(playback: false)')! as Map<String, dynamic>;
      expect(
        (broadcast.status, broadcast.uid, broadcast.title),
        (legacy['statusCode'], legacy['userId'], legacy['title']),
      );
      expect((broadcast.isLive, broadcast.hasEnded), (false, true));
      final room = KilakilaApi.room(broadcast);
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.isRecord, isFalse, reason: "the recording is not the anchor room's replay");
      expect((room.startedAt, room.restriction, room.totalViewers), (null, null, ''));
      // 3.x: stateUnsupported at room entry.
      expect(_value('S05-room-replay', 'detail(playback: true)'), {
        'throws': 'KilakilaException',
        'message': 'Kilakila stateUnsupported',
      });
      expect(() => KilakilaApi.qualities(_data(broadcast)), throwsA(isA<StreamUnavailable>()));
    });

    test('S05-room-notfound: 5201 is NotFound (3.x: service)', () {
      expect(_value('S05-room-notfound', 'detail(playback: false)'), {
        'throws': 'KilakilaException',
        'message': 'Kilakila service',
      });
      expect(() => KilakilaApi.roomInfo(_sample('S05-room-notfound').body, broadcastId: '1'), throwsA(isA<NotFound>()));
    });

    test('5966 is a historical replay: StreamUnavailable (3.x: historicalReplay)', () {
      expect(() => _parseInfo({'userInfo': _owner()}, code: 5966), throwsA(isA<StreamUnavailable>()));
    });

    test("3.x's broadcast: distinct anchor and broadcast ids, the push address never read", () {
      final broadcast = _parseInfo(_info(), uid: '100');
      expect(
        (broadcast.broadcastId, broadcast.uid, broadcast.nick, broadcast.title),
        (_rid, '100', 'Fixture', 'Music'),
      );
      expect(broadcast.cover, 'https://img.example/cover.png');
      expect((broadcast.flv, broadcast.hls), (_flv, _hls));
      final room = KilakilaApi.room(broadcast);
      expect((room.roomId, room.link), ('100', 'https://live.hongrenshuo.com.cn/index/roomuser/uid/100'));
      expect(jsonEncode(room.toJson()), allOf(isNot(contains('SECRET')), isNot(contains(_rid))));
    });

    test('15-6: one 原画, FLV then HLS; a missing or bad one only drops its line', () {
      final both = KilakilaApi.qualities(_data(_parseInfo(_info()))).single;
      expect((both.quality, both.id), ('原画', 'original'));
      expect(both.data, [_flv, _hls]);
      for (final info in [
        _info()..remove('flvPlayUrl'),
        _info()..['flvPlayUrl'] = 'https://pull.live.hongrenshuo.com.cn/hrs/123.flv?auth_key=x',
      ]) {
        final data = _data(_parseInfo(info));
        final quality = KilakilaApi.qualities(data).single;
        expect(quality.data, [_hls]);
        expect(KilakilaApi.resolution(data, quality).lines.single.lineId, 'hls');
      }
    });

    test('push-only, wrong-room and wrong-host media leave no stream (3.x)', () {
      for (final info in [
        _info()
          ..remove('flvPlayUrl')
          ..remove('hlsPlayUrl'),
        _info()
          ..['flvPlayUrl'] = _flv.replaceAll(_rid, '123')
          ..['hlsPlayUrl'] = '',
        _info()
          ..['flvPlayUrl'] = 'https://pull.live.hongrenshuo.com.cn.evil.test/hrs/$_rid.flv'
          ..['hlsPlayUrl'] = null,
      ]) {
        expect(() => KilakilaApi.qualities(_data(_parseInfo(info))), throwsA(isA<StreamUnavailable>()));
      }
      expect(
        () => KilakilaApi.qualities(KilakilaRoomData(issuedAt: DateTime.utc(2026))),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test("pull URL checks: duplicate auth, ports, credentials, fragments, encodings (3.x's cases)", () {
      for (final value in [
        '$_flv&auth_key=second',
        _flv.replaceFirst('https:', 'http:'),
        _flv.replaceFirst('https://', 'https://user@'),
        _flv.replaceFirst('.cn/', '.cn:8787/'),
        '$_flv#tail',
        _flv.split('?').first,
        '${_flv.split('?').first}?auth_key=',
        '${_flv.split('?').first}?auth_key=%FF',
        'rtmp://push.example/SECRET_NOT_A_PLAY_URL',
        42,
      ]) {
        expect(
          KilakilaApi.mediaUrl(value, broadcastId: _rid, format: StreamFormat.flv),
          isNull,
          reason: '$value',
        );
      }
      expect(KilakilaApi.mediaUrl(_flv, broadcastId: _rid, format: StreamFormat.flv), _flv);
      expect(KilakilaApi.mediaUrl(_flv, broadcastId: _rid, format: StreamFormat.hls), isNull);
      expect(KilakilaApi.mediaUrl(_flv, broadcastId: _rid, format: StreamFormat.other), isNull);
    });

    test('a paid broadcast is live and marked paid; its stream is unavailable, naming it (checked first)', () {
      final broadcast = _parseInfo(_info()..['goldPrice'] = 10);
      final room = KilakilaApi.room(broadcast);
      expect((room.isLiveNow, room.restriction, room.isRestricted), (true, LiveRestriction.paid, true));
      expect(room.followGroup, FollowGroup.live);
      final paid = isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('(paid)'));
      // 3.x: NeedsLogin, though KilaKila has no login (M2.1: paid is
      // StreamUnavailable with the reason).
      expect(() => KilakilaApi.qualities(_data(broadcast)), throwsA(paid));
      expect(
        () => KilakilaApi.qualities(
          _data(
            _parseInfo(
              _info()
                ..['goldPrice'] = 10
                ..['status'] = 5,
            ),
          ),
        ),
        throwsA(paid),
      );
      expect(KilakilaApi.room(_parseInfo(_info())).restriction, LiveRestriction.none);
    });

    test('an unknown status stays unknown, never offline or a replay; no stream (3.x)', () {
      final broadcast = _parseInfo(_info()..['status'] = 5);
      expect(broadcast.status, 5);
      final room = KilakilaApi.room(broadcast);
      expect(room.effectiveLiveStatus, LiveStatus.unknown);
      expect((room.restriction, room.totalViewers), (null, ''), reason: 'only a live broadcast has them');
      expect(() => KilakilaApi.qualities(_data(broadcast)), throwsA(isA<StreamUnavailable>()));
    });

    test('a quality the broadcast does not offer is StreamUnavailable; 3.x ids name 原画', () {
      final data = _data(_parseInfo(_info()..remove('hlsPlayUrl')));
      expect(
        () => KilakilaApi.resolution(data, const LivePlayQuality(quality: 'RTMP', id: 'rtmp')),
        throwsA(isA<StreamUnavailable>()),
      );
      final old = KilakilaApi.resolution(data, const LivePlayQuality(quality: 'HLS', id: 'hls'));
      expect(old.urls, [_flv], reason: 'the broadcast has only FLV now');
      expect(old.appliedQualityData, 'original');
    });

    test('the start is actualTime in milliseconds, on the card of a live broadcast only', () {
      for (final (value, start) in <(Object?, DateTime?)>[
        (1790518002790, DateTime.utc(2026, 9, 27, 14, 6, 42, 790)),
        ('1790518002790', DateTime.utc(2026, 9, 27, 14, 6, 42, 790)),
        (1790518002, null),
        (0, null),
        (-1, null),
        (1790518002790.5, null),
        ('soon', null),
        (null, null),
      ]) {
        expect(KilakilaApi.startedAt(value), start, reason: '$value');
      }
      final card = KilakilaApi.profile(
        _profile(
          card: _card()
            ..['actualTime'] = 1790518002790
            ..['liveStartTime'] = 1790440003051,
        ),
        uid: '100',
      ).current!;
      expect(KilakilaApi.room(card).startedAt, DateTime.utc(2026, 9, 27, 14, 6, 42, 790));
      final setUp = KilakilaApi.profile(_profile(card: _card()..['liveStartTime'] = 1790440003051), uid: '100');
      expect(KilakilaApi.room(setUp.current!).startedAt, isNull, reason: 'liveStartTime is when it was set up');
      final ended = KilakilaApi.profile(
        _profile(
          card: _card()
            ..['status'] = 10
            ..['actualTime'] = 1790518002790,
        ),
        uid: '100',
      );
      expect(KilakilaApi.room(ended.current!).startedAt, isNull);
    });

    test('15-2: listeners are counts of 0 or more; others are left out, never an error', () {
      for (final (value, count) in <(Object, int?)>[
        (193, 193),
        ('193', 193),
        (0, 0),
        (-1, null),
        (1.5, null),
        ('many', null),
      ]) {
        final card = KilakilaApi.profile(
          _profile(
            card: _card()
              ..['onlineNumber'] = value
              ..['watchNumber'] = value,
          ),
          uid: '100',
        ).current!;
        expect((card.online, card.total), (count, count), reason: '$value');
        expect(KilakilaApi.room(card).onlineViewers, count?.toString() ?? '', reason: '$value');
      }
    });

    test('another broadcast or anchor, rounded or odd ids, a missing price are ApiChanged (3.x)', () {
      for (final info in [
        _info()..['roomIdStr'] = '123',
        _info()..['uid'] = 101,
        _info()..['userInfo'] = (_owner()..['id'] = 101),
        _info()..['roomIdStr'] = int.parse(_rid),
        _info()..['roomIdStr'] = 9007199254740992.0,
        _info()..['uid'] = true,
        _info()..remove('goldPrice'),
        _info()..['goldPrice'] = -1,
        _info()..['goldPrice'] = 0.0,
        _info()..['status'] = true,
        _info()..['title'] = ' ',
      ]) {
        expect(() => _parseInfo(info), throwsA(isA<ApiChanged>()), reason: '$info');
      }
      expect(() => _parseInfo(_info(), uid: '101'), throwsA(isA<ApiChanged>()));
    });

    test('bad optional pictures are empty rather than borrowed (3.x)', () {
      final broadcast = _parseInfo(
        _info()
          ..['defaultBackgroundPicUrl'] = 'javascript:bad'
          ..['userInfo'] = (_owner()..['headPortraitUrl'] = 'https://user@img.example/a'),
      );
      expect((broadcast.cover, broadcast.avatar), ('', ''));
      expect(_parseInfo(_info()..['backPic'] = '//img.example/back.png').cover, 'https://img.example/back.png');
    });

    test('broken envelopes and unknown codes are ApiChanged (3.x)', () {
      for (final body in [
        '[]',
        jsonEncode({'h': <String, Object?>{}}),
        jsonEncode({
          'h': {'code': 200, 'success': false},
          'b': _info(),
        }),
        jsonEncode({
          'h': {'code': true, 'success': true},
        }),
        _roomInfo(null),
        _roomInfo(null, code: 9999),
        'not json',
      ]) {
        expect(() => KilakilaApi.roomInfo(body, broadcastId: _rid), throwsA(isA<ApiChanged>()), reason: body);
      }
    });

    test('HTTP statuses have their own errors, never an offline room (3.x)', () {
      for (final (status, matcher) in [
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (503, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
      ]) {
        expect(
          () => KilakilaApi.roomInfo('untrusted SECRET response', broadcastId: _rid, status: status),
          throwsA(matcher),
          reason: '$status',
        );
        expect(() => KilakilaApi.searchPage('', status: status), throwsA(matcher), reason: '$status');
      }
    });

    test('an answer over 1 MiB is ApiChanged, counted in UTF-8 bytes (3.x)', () {
      final big = _roomInfo(_info()..['title'] = List.filled(400000, '中').join());
      expect(big.length, lessThan(KilakilaApi.responseLimit));
      expect(() => KilakilaApi.roomInfo(big, broadcastId: _rid), throwsA(isA<ApiChanged>()));
    });

    test('leases: 10 minutes or a quarter of the lifetime before auth_key; none when past or missing', () {
      final issued = DateTime.utc(2026, 9, 27);
      final expiry = issued.add(const Duration(minutes: 20)).millisecondsSinceEpoch ~/ 1000;
      final short = KilakilaApi.lease(
        'https://pull.live.hongrenshuo.com.cn/hrs/1.m3u8?auth_key=$expiry-0-0-abc',
        issuedAt: issued,
      )!;
      expect(short.refreshAt, issued.add(const Duration(minutes: 15)));
      expect(short.cutsConnection, isTrue);
      final past = issued.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/ 1000;
      expect(KilakilaApi.lease('https://x.test/1.flv?auth_key=$past-0-0-abc', issuedAt: issued), isNull);
      expect(KilakilaApi.lease('https://x.test/1.flv?auth_key=fixture', issuedAt: issued), isNull);
      expect(KilakilaApi.lease('https://x.test/1.flv', issuedAt: issued), isNull);
    });
  });

  group('links', () {
    test('AES-128-CBC matches SP 800-38A F.2.2; bad padding and lengths are FormatExceptions', () {
      final plain = Aes128Cbc.decryptBlocks(
        _hex('7649abac8119b246cee98e9b12e9197d5086cb9b507219ee95db113a917678b2'),
        key: _hex('2b7e151628aed2a6abf7158809cf4f3c'),
        iv: _hex('000102030405060708090a0b0c0d0e0f'),
      );
      expect(plain, _hex('6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51'));
      expect(
        () => Aes128Cbc.decrypt(
          _hex('7649abac8119b246cee98e9b12e9197d'),
          key: List.filled(16, 0),
          iv: List.filled(16, 0),
        ),
        throwsFormatException,
      );
      expect(
        () => Aes128Cbc.decrypt([1, 2, 3], key: List.filled(16, 0), iv: List.filled(16, 0)),
        throwsFormatException,
      );
      expect(() => Aes128Cbc.decrypt(List.filled(16, 0), key: [1], iv: List.filled(16, 0)), throwsFormatException);
    });

    final vectors = _vectors();
    final legacy = _vectorsLegacy();
    for (final (index, vector) in vectors.indexed) {
      test('share vector ${vector['name']} matches 3.x and the independent generator (REG-KILAKILA-002)', () {
        final link = KilakilaLink.parse(vector['url'] as String);
        final parsed = link == null ? null : {'kind': link.kind.name, 'id': link.id};
        expect(parsed, legacy[index]['parse']);
        expect(legacy[index]['name'], vector['name']);
        if (vector['valid'] == true) {
          expect(parsed, {'kind': vector['kind'], 'id': vector['id']});
        } else {
          expect(link, isNull);
        }
      });
    }

    test('S06: the room page redirects to the encrypted detail link of the same broadcast (3.x)', () {
      final redirect = _sample('S06-room-redirect');
      final location = ((redirect.meta['response'] as Map)['headers'] as Map)['location'] as String;
      final legacy = _legacy('S06-room-redirect');
      expect(legacy['KilakilaLink.parse(location)'], {'kind': 'broadcast', 'id': _liveBroadcast});
      expect(KilakilaLink.parse(location), const KilakilaLink(KilakilaLinkKind.broadcast, _liveBroadcast));
      expect(
        KilakilaLink.parse(redirect.url.toString()),
        const KilakilaLink(KilakilaLinkKind.broadcast, _liveBroadcast),
      );
    });

    test('plain links keep anchor and broadcast apart (3.x)', () {
      for (final host in ['live.kilakila.cn', 'www.hongdoufm.com']) {
        for (final scheme in ['http', 'https']) {
          expect(KilakilaLink.parse('$scheme://$host/room/123'), const KilakilaLink(KilakilaLinkKind.broadcast, '123'));
          expect(
            KilakilaLink.parse('$scheme://$host/PcLive/index/detail?id=123'),
            const KilakilaLink(KilakilaLinkKind.broadcast, '123'),
          );
        }
        expect(KilakilaLink.parse('https://$host/room/$_rid'), const KilakilaLink(KilakilaLinkKind.broadcast, _rid));
      }
      expect(
        KilakilaLink.parse('https://live.hongrenshuo.com.cn/index/roomuser/uid/123'),
        const KilakilaLink(KilakilaLinkKind.owner, '123'),
      );
      expect(
        KilakilaLink.parse('https://live.kilakila.cn/zhubo/123'),
        const KilakilaLink(KilakilaLinkKind.owner, '123'),
      );
      expect(KilakilaApi.ownerUrl('100'), 'https://live.hongrenshuo.com.cn/index/roomuser/uid/100');
    });

    test('malformed or ambiguous URLs are no links (3.x)', () {
      for (final url in [
        'https://live.kilakila.cn.evil.test/room/123',
        'https://user@live.kilakila.cn/room/123',
        'https://x@live.kilakila.cn/room/$_rid',
        'https://live.kilakila.cn:8787/room/123',
        'file:///room/123',
        'https://live.kilakila.cn/room/123#',
        'https://live.kilakila.cn/room/$_rid#other',
        'https://live.kilakila.cn/room/123/extra',
        'https://live.kilakila.cn/%72oom/123',
        'https://live.kilakila.cn/room/0',
        'https://live.kilakila.cn/room/00123',
        'https://live.kilakila.cn/room/123?id=456',
        'https://live.kilakila.cn/room/123?_specific_parameter=bad',
        'https://live.kilakila.cn/room/OPAQUE==',
        'https://live.kilakila.cn/room/%FF',
        'https://live.kilakila.cn/PcLive/index/detail?id=123&id=456',
        'https://live.kilakila.cn/PcLive/index/detail?id=123&_specific_parameter=bad',
        'https://live.kilakila.cn/PcLive/index/detail?_specific_parameter=bad&sign=bad',
        'https://live.kilakila.cn/PcLive/index/detail?_specific_parameter=bad&_specific_parameter=bad',
        'https://live.kilakila.cn/PcLive/index/detail?_specific_parameter=%FF',
        'https://live.kilakila.cn/PcLive/index/detail?_specific_parameter=%GG',
        'https://live.kilakila.cn/PcLive/index/detail?_specific_parameter=',
        'https://live.kilakila.cn/PcLive/index/detail/$_rid',
        'https://live.kilakila.cn/index/roomuser/uid/123',
        'https://live.hongrenshuo.com.cn/room/123',
        'http://live.hongrenshuo.com.cn/index/roomuser/uid/123',
        'https://live.hongrenshuo.com.cn/index/roomuser/uid/123?uid=456',
        'https://live.hongrenshuo.com.cn/index/roomuser/uid/0',
        'https://live.hongrenshuo.com.cn/index/roomuser/uid/123/',
        'https://live.hongrenshuo.com.cn:8787/index/roomuser/uid/123',
        'https://live.kilakila.cn/room/123 456',
        'https://live.kilakila.cn/zhubo/123?uid=456',
        'https://live.kilakila.cn/zhubo/123/extra',
        'https://live.kilakila.cn/%7Ahubo/123',
        'https://live.kilakila.cn/zhubo/00123',
        '看 https://live.kilakila.cn/room/123',
        'not a link',
      ]) {
        expect(KilakilaLink.parse(url), isNull, reason: url);
      }
    });

    test('raw, escaped and unpadded payloads agree; a tracking parameter is kept out (3.x)', () {
      final url = vectors.first['url'] as String;
      final payload = Uri.parse(url).queryParameters['_specific_parameter']!;
      const prefix = 'https://live.kilakila.cn/PcLive/index/detail?_specific_parameter=';
      final standard = payload.replaceAll('-', '+').replaceAll('_', '/');
      for (final encoded in [
        payload,
        payload.replaceAll('=', ''),
        Uri.encodeQueryComponent(payload),
        Uri.encodeQueryComponent(standard),
      ]) {
        expect(KilakilaLink.parse('$prefix$encoded')?.id, vectors.first['id'], reason: encoded);
      }
      expect(KilakilaLink.parse('$url&from=share')?.id, vectors.first['id']);
      expect(KilakilaLink.parse('$url&id=123'), isNull);
    });

    test('the signature binds the scheme, host and route as written (3.x)', () {
      final url = vectors.first['url'] as String;
      expect(KilakilaLink.parse(url.replaceFirst('https:', 'http:')), isNull);
      expect(KilakilaLink.parse(url.replaceFirst('/detail?', '/detail/?')), isNull);
      expect(KilakilaLink.parse(url.replaceFirst('/PcLive/', '/%50cLive/')), isNull);
      final path = vectors.firstWhere((vector) => vector['name'] == 'new-live.kilakila.cn-room')['url'] as String;
      expect(KilakilaLink.parse(path.replaceFirst('/room/', '/%72oom/')), isNull);
    });

    test('arbitrary ciphertext fails without throwing (3.x)', () {
      for (var i = 0; i < 256; i++) {
        final data = List.generate(32, (index) => (i + index) % 256);
        expect(KilakilaLink.parse('https://live.kilakila.cn/room/${base64Url.encode(data)}'), isNull);
      }
      expect(KilakilaLink.parse('https://live.kilakila.cn/room/${'a' * 9000}'), isNull);
      expect(KilakilaLink.parse('https://live.kilakila.cn/room/${'a' * 4097}'), isNull);
    });
  });
}

List<Map<String, dynamic>> _vectorsLegacy() => _maps(
  (jsonDecode(File('../../fixtures/kilakila/S09-share-vectors/expected.json').readAsStringSync())
      as Map<String, dynamic>)['value'],
);
