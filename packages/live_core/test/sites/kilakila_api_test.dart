// KilaKila parsing against the recorded samples, compared field by field
// with 3.x's frozen output (expected.json, written by
// fixtures/kilakila/legacy_expected.dart from 3.x's KilakilaApi, KilakilaLink
// and KilakilaSite). Every intended difference is listed with its reason;
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
          _expectParity(_projection(room), rooms[index], reason: '$name[$index]');
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

    test('no audience: watchNumber is cumulative listeners, 3.x showed none (REG-KILAKILA-003)', () {
      for (final room in _timeline(_sample('S01-timeline-hot-p1').body).rooms) {
        expect((room.watching, room.onlineViewers, room.totalViewers, room.popularity), ('', '', '', ''));
        expect(room.audienceMetricType, AudienceMetricType.unknown);
        expect(
          room.audienceValue(preferRealOnline: false, platformEnabled: true),
          isEmpty,
          reason: 'cards show no number, as in 3.x',
        );
      }
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

    test('pages end at isLastPage, not at a short or empty page (3.x; REG-KILAKILA-005)', () {
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

    test('a page that does not echo the request, or a broken row, is ApiChanged (3.x)', () {
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

    test('an empty list is no result; a broken page is ApiChanged (3.x)', () {
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
      expect(KilakilaApi.isSearchable('a' * 100), isTrue);
      expect(KilakilaApi.isSearchable('a' * 101), isFalse);
      expect(KilakilaApi.isSearchable('  '), isFalse);
    });
  });

  group('S04 profiles', () {
    test("S04-owner-live: the refresh detail is 3.x's, with the introduction and followers", () {
      final profile = KilakilaApi.profile(_sample('S04-owner-live').body, uid: _liveOwner);
      final legacy = _value('S04-owner-live', 'getRoomDetailForRefresh')! as Map<String, dynamic>;
      final room = KilakilaApi.profileDetail(profile);
      // 3.x read neither the introduction nor the follower count.
      _expectParity(_projection(room), legacy, changed: {'introduction', 'followers'});
      expect(room.introduction, startsWith('个播：晚22'));
      expect(room.followers, '19998');
      expect(room.isLiveNow, isTrue);
      expect(profile.current!.broadcastId, _liveBroadcast);
      expect(room.data, isNull, reason: 'the card has no pull URLs');
    });

    test("S04-owner-live: the exact search result is 3.x's", () {
      final profile = KilakilaApi.profile(_sample('S04-owner-live').body, uid: _liveOwner);
      final legacy = _maps(_value('S04-owner-live', 'searchRooms(uid)')).single;
      _expectParity(_projection(KilakilaApi.room(profile.current!)), legacy);
      expect(_value('S04-owner-live', 'searchRooms(ownerUrl)'), _value('S04-owner-live', 'searchRooms(uid)'));
    });

    test('S04-owner-offline: no advertised broadcast is unknown, not offline (3.x)', () {
      final profile = KilakilaApi.profile(_sample('S04-owner-offline').body, uid: '1775178981381');
      expect(profile.current, isNull);
      final room = KilakilaApi.profileDetail(profile);
      _expectParity(
        _projection(room),
        _value('S04-owner-offline', 'getRoomDetailForRefresh')! as Map<String, dynamic>,
        changed: {'introduction', 'followers'},
      );
      expect(room.effectiveLiveStatus, LiveStatus.unknown);
      expect(room.isExplicitlyOfflineNow, isFalse);
      expect(room.title, isEmpty);
      _expectParity(
        _projection(KilakilaApi.profileRoom(profile)),
        _maps(_value('S04-owner-offline', 'searchRooms(uid)')).single,
      );
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
    });

    test('S04 + S05: room entry, its qualities and lines match 3.x', () {
      final profile = KilakilaApi.profile(_sample('S04-owner-live').body, uid: _liveOwner);
      final broadcast = KilakilaApi.roomInfo(fixture.body, broadcastId: _liveBroadcast, uid: _liveOwner);
      final room = KilakilaApi.withProfile(KilakilaApi.room(broadcast), profile);
      _expectParity(
        _projection(room),
        _value('S04-owner-live', 'getRoomDetail')! as Map<String, dynamic>,
        changed: {'introduction', 'followers'},
      );
      final data = _data(broadcast, issuedAt: fixture.capturedAt);
      final qualities = KilakilaApi.qualities(data);
      final legacy = _maps(_legacy('S04-owner-live')['getPlayQualites']);
      expect(qualities.map((quality) => (quality.quality, quality.id, quality.sort)), [
        for (final quality in legacy) (quality['quality'], quality['id'], quality['sort']),
      ]);
      for (final (index, quality) in qualities.indexed) {
        final resolution = KilakilaApi.resolution(data, quality);
        expect(resolution.urls, legacy[index]['getPlayUrls']);
        expect(resolution.appliedQualityData, quality.id);
        final line = resolution.lines.single;
        expect(line.headers, {'referer': 'https://live.kilakila.cn/', 'user-agent': 'Mozilla/5.0'});
        expect(line.lineId, quality.id);
        expect(line.format, quality.id == 'flv' ? StreamFormat.flv : StreamFormat.hls);
        final lease = line.lease!;
        expect(lease.expiresAt, DateTime.fromMillisecondsSinceEpoch(1793120972 * 1000, isUtc: true));
        expect(lease.expiresAt!.difference(fixture.capturedAt).inHours, inInclusiveRange(719, 720));
        expect(lease.expiresAt!.difference(lease.refreshAt), const Duration(minutes: 10));
        expect(lease.cutsConnection, quality.id == 'hls');
      }
      final recovery = _value('S04-owner-live', 'resolvePlayUrlsForRecoveryRaw')! as Map<String, dynamic>;
      expect(recovery['urls'], legacy.first['getPlayUrls']);
      expect(recovery['appliedQualityData'], 'flv');
    });

    test('S05-room-replay: status 10 stays unknown as in 3.x; its stream is unavailable', () {
      final replay = _sample('S05-room-replay');
      final broadcast = KilakilaApi.roomInfo(replay.body, broadcastId: '2261269383617708096');
      final legacy = _value('S05-room-replay', 'detail(playback: false)')! as Map<String, dynamic>;
      expect(
        (broadcast.status, broadcast.uid, broadcast.title),
        (legacy['statusCode'], legacy['userId'], legacy['title']),
      );
      expect(broadcast.isLive, isFalse);
      expect(KilakilaApi.room(broadcast).effectiveLiveStatus, LiveStatus.unknown);
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

    test('FLV then HLS; a missing one does not hide the other (3.x)', () {
      final both = KilakilaApi.qualities(_data(_parseInfo(_info())));
      expect(both.map((quality) => (quality.quality, quality.id)), [('FLV', 'flv'), ('HLS', 'hls')]);
      expect(both.first.data, [_flv]);
      final hls = KilakilaApi.qualities(_data(_parseInfo(_info()..remove('flvPlayUrl'))));
      expect(hls.map((quality) => quality.id), ['hls']);
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

    test('a paid broadcast is live but needs an account (3.x: restricted, checked first)', () {
      final broadcast = _parseInfo(_info()..['goldPrice'] = 10);
      expect(KilakilaApi.room(broadcast).isLiveNow, isTrue);
      expect(() => KilakilaApi.qualities(_data(broadcast)), throwsA(isA<NeedsLogin>()));
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
        throwsA(isA<NeedsLogin>()),
      );
    });

    test('an unknown status stays unknown, never offline or a replay; no stream (3.x)', () {
      final broadcast = _parseInfo(_info()..['status'] = 5);
      expect(broadcast.status, 5);
      expect(KilakilaApi.room(broadcast).effectiveLiveStatus, LiveStatus.unknown);
      expect(() => KilakilaApi.qualities(_data(broadcast)), throwsA(isA<StreamUnavailable>()));
    });

    test('a quality the broadcast does not offer is StreamUnavailable', () {
      final data = _data(_parseInfo(_info()..remove('hlsPlayUrl')));
      expect(
        () => KilakilaApi.resolution(data, const LivePlayQuality(quality: 'HLS', id: 'hls')),
        throwsA(isA<StreamUnavailable>()),
      );
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
