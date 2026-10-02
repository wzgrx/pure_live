// AcFun parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json: 3.x's acfun_*.dart run over the same
// samples, docs/E-直播平台/E02-其他国内平台/E02.3-AcFun直播/record.md). Every intended difference is listed
// with its reason; everything else must match.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('acfun', name);

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

/// When the S06 startPlay answer arrived.
final DateTime _issuedAt = DateTime.utc(2026, 9, 27, 17, 46, 25);

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
    if (changed.contains(key) || key == 'data') continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
}

/// Rooms against 3.x's: same rooms in the same order, every field equal.
void _expectRooms(List<LiveRoom> rooms, Object? legacy, {required String reason}) {
  final expected = (legacy! as List).cast<Map<String, dynamic>>();
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(room.toJson(), expected[index], reason: '$reason[$index]');
  }
}

/// The keys [actual] (a `toJson`) has beyond 3.x's [legacy] map, which
/// leaves out nulls and empty collections: the v4 keys M2.1 added (3.x
/// ignores them when reading).
Set<String> _added(Map<String, Object?> actual, Map<String, dynamic> legacy) => {
  for (final MapEntry(:key, :value) in actual.entries)
    if (value != null && !(value is Iterable && value.isEmpty) && !(value is Map && value.isEmpty))
      if (!legacy.containsKey(key)) key,
};

/// The raw list cards of a `channel/list` sample.
List<Map<String, dynamic>> _cards(String name) =>
    (((jsonDecode(_sample(name).body) as Map<String, dynamic>)['channelListData'] as Map)['liveList'] as List)
        .cast<Map<String, dynamic>>();

/// The broadcast of the live startPlay sample.
AcfunRoomData _liveData() => AcfunApi.startPlay(_sample('S06-startplay-live').body, issuedAt: _issuedAt).data!;

/// The `data.videoPlayRes` of the live startPlay sample.
Object? _videoPlayRes() =>
    ((jsonDecode(_sample('S06-startplay-live').body) as Map<String, dynamic>)['data'] as Map)['videoPlayRes'];

/// A `videoPlayRes` of [groups] (one list of representations per manifest).
Map<String, Object?> _manifest(List<List<Map<String, Object?>>> groups) => {
  'liveAdaptiveManifest': [
    for (final group in groups)
      {
        'adaptationSet': {'representation': group},
      },
  ],
};

Map<String, Object?> _representation(String type, int? level, String url, {String? label, int? bitrate}) => {
  'qualityType': type,
  'level': ?level,
  'bitrate': ?bitrate,
  'url': url,
  'name': ?label,
};

/// A `live/info` answer (3.x's contract test fixture).
Map<String, Object?> _info({bool live = true, Object? author = 42, Map<String, Object?>? user}) => {
  'result': 0,
  'authorId': author,
  'user':
      user ??
      {'id': '42', 'name': 'Fixture broadcaster', 'headUrl': 'https://img.example/avatar.jpg', 'fanCountValue': 250},
  if (live) ...{
    'liveId': 'live-a',
    'streamName': 'stream-a',
    'title': 'Fixture live',
    'onlineCount': 87,
    'likeCount': 9000000,
  },
};

/// A search answer (3.x's navigation test fixture).
String _searchCard(
  int id, {
  Object? flag = '',
  String? href,
  String name = 'Fixture &amp; live',
  String avatar = '//img.example/a.jpg',
}) =>
    '''
<div class="search-up" data-up-exposure-log='${jsonEncode({'up_id': id, 'is_on_live': ?flag})}'>
<img class="up__avatar live-avatar" src="$avatar">
<div class="up__main__name"><a href="${href ?? '/u/$id'}">$name</a></div>
<div class="info__danmaku-count">2.4万&ensp;粉丝</div>
<div class="up__main__intro">Fixture &lt;stream&gt;</div>
</div>''';

String _searchAnswer(List<String> cards, {required int total, bool blankZero = false, bool emptyMarker = true}) =>
    '${jsonEncode({
      'html': '<span class="total-num" data-total="${blankZero ? '' : total}">共$total条结果</span>'
          '${cards.join()}${cards.isEmpty && emptyMarker ? '<div class="empty-page"></div>' : ''}',
      'scripts': ['throw new Error("never execute")'],
    })}/*<!-- fetch-stream -->*/';

void main() {
  group('S01 catalog', () {
    test('the areas 3.x listed but 全部 (10-2), in answer order, under the site name', () {
      final fixture = _sample('S01-list-filters');
      final areas = AcfunApi.areas(fixture.body, typeName: 'AcFun 直播', status: fixture.status);
      final category = (_legacy('S01-list-filters')['getCategores'] as List).single as Map<String, dynamic>;
      expect((category['id'], category['name']), ('acfun', 'AcFun 直播'));
      final all = (category['children'] as List).cast<Map<String, dynamic>>();
      // changed: 10-2 leaves out 全部 (filter 0), the recommendations again.
      expect((all.first['areaId'], all.first['areaName']), ('0', '全部'));
      final legacy = all.skip(1).toList();
      expect(areas.map((area) => area.areaName), ['虚拟偶像', '游戏', '娱乐', '其他']);
      expect(areas, hasLength(legacy.length));
      for (final (index, area) in areas.indexed) {
        // 3.x wrote shortName null, the model ''; 3.x reads both the same.
        _expectParity(area.toJson(), legacy[index], reason: 'S01[$index]');
      }
    });

    test("3.x's category checks: filters without type, id or name are left out; none at all is ApiChanged", () {
      String answer(Object? filters) => jsonEncode({
        'channelListData': {'result': 0, 'liveList': <Object>[], 'pcursor': 'no_more'},
        'channelFilters': filters,
      });
      final areas = AcfunApi.areas(
        answer({
          'liveChannelDisplayFilters': [
            {
              'displayFilters': [
                {'filterType': 1, 'filterId': 0, 'name': '全部'},
                {'filterType': '1', 'filterId': '4', 'name': '虚拟偶像', 'cover': '//img.example/virtual.jpg'},
                {'filterType': 1, 'filterId': -2, 'name': 'Invalid'},
                {'filterType': 1, 'filterId': 4, 'name': 'Duplicate'},
                {'filterType': 1, 'filterId': 5},
              ],
            },
          ],
        }),
        typeName: 'AcFun 直播',
      );
      expect(areas.map((area) => (area.areaType, area.areaId, area.areaName)), [('1', '4', '虚拟偶像')]);
      expect(areas.last.areaPic, 'https://img.example/virtual.jpg');
      for (final broken in <Object?>[
        null,
        <String, Object>{},
        {'liveChannelDisplayFilters': <String, Object>{}},
        {'liveChannelDisplayFilters': <Object>[]},
        // Only 全部 (10-2 leaves it out): no area at all.
        {
          'liveChannelDisplayFilters': [
            {
              'displayFilters': [
                {'filterType': 1, 'filterId': 0, 'name': '全部'},
              ],
            },
          ],
        },
      ]) {
        expect(() => AcfunApi.areas(answer(broken), typeName: ''), throwsA(isA<ApiChanged>()), reason: '$broken');
      }
      expect(
        () => AcfunApi.areas(
          jsonEncode({
            'channelListData': {'result': 1},
          }),
          typeName: '',
        ),
        throwsA(isA<ApiChanged>()),
        reason: 'the list envelope must be a success',
      );
    });

    test('the filter query of an area (3.x encoding)', () {
      expect(jsonDecode(AcfunApi.filterQuery(type: 1, id: 4)), [
        {'filterType': 1, 'filterId': 4},
      ]);
    });
  });

  group('lists', () {
    test('S01 recommendations: the 19 rooms 3.x listed, one page (no_more)', () {
      final fixture = _sample('S01-list-all');
      final page = AcfunApi.directory(fixture.body, status: fixture.status);
      _expectRooms(page.rooms, _legacy('S01-list-all')['getRecommendRooms'], reason: 'S01');
      expect(page.rooms, hasLength(19));
      expect(page.next, isNull);
      expect(page.rooms.every((room) => room.isLiveNow), isTrue);
    });

    test('S01, S02: every card starts at its createTime (10-3) and has no restriction; nothing else is added', () {
      for (final (name, method) in [('S01-list-all', 'getRecommendRooms'), ('S02-list-game', 'getCategoryRooms')]) {
        final fixture = _sample(name);
        final rooms = AcfunApi.directory(fixture.body, status: fixture.status).rooms;
        final cards = _cards(name);
        final legacy = (_legacy(name)[method] as List).cast<Map<String, dynamic>>();
        for (final (index, room) in rooms.indexed) {
          final start = DateTime.fromMillisecondsSinceEpoch(cards[index]['createTime'] as int, isUtc: true);
          expect(room.startedAt, start, reason: '$name[$index]');
          expect(room.startedAt!.isBefore(fixture.capturedAt), isTrue, reason: '$name[$index]');
          // No paidShowUuid next to paidShowUserBuyStatus: not a paid show.
          expect(cards[index], containsPair('paidShowUserBuyStatus', false));
          expect(cards[index].containsKey('paidShowUuid'), isFalse);
          expect(room.restriction, LiveRestriction.none, reason: '$name[$index]');
          // changed (new keys, which 3.x does not read): startedAt (10-3),
          // restriction (unified principles, M2.1).
          expect(_added(room.toJson(), legacy[index]), {'startedAt', 'restriction'}, reason: '$name[$index]');
          expect(room.toJson()['startedAt'], start.toIso8601String());
          expect(room.toJson()['restriction'], 'none');
        }
      }
    });

    test('S02 area rooms of 游戏: the 8 rooms 3.x listed, the area as each card names it', () {
      final fixture = _sample('S02-list-game');
      final page = AcfunApi.directory(fixture.body, status: fixture.status);
      _expectRooms(page.rooms, _legacy('S02-list-game')['getCategoryRooms'], reason: 'S02');
      expect(page.rooms, hasLength(8));
      expect(page.next, isNull);
    });

    test('a paid show (paidShowUuid) is live and paid unless bought; no paid-show fields say nothing', () {
      LiveRoom card(Map<String, Object?> extra) => AcfunApi.directory(
        jsonEncode({
          'result': 0,
          'pcursor': 'no_more',
          'liveList': [
            {..._info(), ...extra},
          ],
        }),
      ).rooms.single;
      final paid = card({'paidShowUuid': 'show-a', 'paidShowUserBuyStatus': false});
      expect((paid.effectiveLiveStatus, paid.restriction), (LiveStatus.live, LiveRestriction.paid));
      expect(paid.followGroup, FollowGroup.live, reason: 'a restricted live room stays live');
      expect(card({'paidShowUuid': 'show-a', 'paidShowUserBuyStatus': true}).restriction, LiveRestriction.none);
      expect(card({'paidShowUuid': '', 'paidShowUserBuyStatus': false}).restriction, LiveRestriction.none);
      expect(card({}).restriction, isNull, reason: 'the answer says nothing');
      final offline = AcfunApi.roomDetail(
        jsonEncode({..._info(live: false), 'paidShowUuid': 'show-a', 'createTime': 1790519855941}),
        authorId: '42',
      );
      expect((offline.restriction, offline.startedAt), (null, null), reason: 'neither belongs to an offline room');
    });

    test('start times are epoch milliseconds; zero, seconds and other values are none', () {
      expect(AcfunApi.startedAt(1790519855941), DateTime.utc(2026, 9, 27, 14, 37, 35, 941));
      expect(AcfunApi.startedAt('1790519855941'), DateTime.utc(2026, 9, 27, 14, 37, 35, 941));
      for (final value in [null, 0, -1, 1790519855, 'x', 1.5, true, 17905198559410]) {
        expect(AcfunApi.startedAt(value), isNull, reason: '$value');
      }
    });

    test('the online count is concurrent viewers, likes are not an audience (3.x contract test)', () {
      final room = AcfunApi.directory(
        jsonEncode({
          'channelListData': {
            'result': 0,
            'liveList': [_info()],
            'pcursor': 'opaque-next',
          },
        }),
      ).rooms.single;
      expect(room.onlineViewers, '87');
      expect(room.watching, '87');
      expect(room.popularity, isEmpty);
      expect(room.effectiveAudienceMetricType, AudienceMetricType.onlineViewers);
      final unknown = AcfunApi.roomDetail(jsonEncode({..._info(), 'onlineCount': 'unavailable'}), authorId: '42');
      expect(unknown.onlineViewers, isEmpty);
      expect(unknown.watching, isEmpty);
    });

    test("the cursor is kept as the site gives it; 3.x's envelope checks stay", () {
      String answer(Object? cursor, {bool withCursor = true}) =>
          jsonEncode({'result': 0, 'liveList': <Object>[], if (withCursor) 'pcursor': cursor});
      expect(AcfunApi.directory(answer('opaque-next')).next, 'opaque-next');
      expect(AcfunApi.directory(answer(30)).next, '30');
      expect(AcfunApi.directory(answer('no_more')).next, isNull);
      expect(AcfunApi.directory(answer('')).next, isNull);
      for (final broken in [
        answer(null),
        answer(<String, Object>{}),
        answer(<Object>[]),
        answer('', withCursor: false),
      ]) {
        expect(() => AcfunApi.directory(broken), throwsA(isA<ApiChanged>()), reason: broken);
      }
      expect(
        () => AcfunApi.directory(jsonEncode({'result': 7, 'liveList': <Object>[], 'pcursor': ''})),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('a card that does not check out is left out (3.x failed the whole page)', () {
      final page = AcfunApi.directory(
        jsonEncode({
          'channelListData': {
            'result': 0,
            'pcursor': 'no_more',
            'liveList': [
              _info(),
              {..._info(), 'authorId': 'x'},
              {..._info(), 'authorId': 43},
              _info(author: 44, user: {'id': '44'}),
              'not a card',
            ],
          },
        }),
      );
      expect(page.rooms.map((room) => room.roomId), ['42']);
    });
  });

  group('S04 search', () {
    for (final (name, page, count) in [
      ('S04-search-p1', 1, 30),
      ('S04-search-p4', 4, 10),
      ('S04-search-fuzzy', 1, 8),
      ('S04-search-none', 1, 0),
    ]) {
      test('$name: the authors and total 3.x read', () {
        final fixture = _sample(name);
        final result = AcfunApi.searchPage(fixture.body, page: page, status: fixture.status);
        final legacy = _legacy(name)['parsePage'] as Map<String, dynamic>;
        expect(result.total, legacy['total']);
        _expectRooms(result.rooms, legacy['rooms'], reason: name);
        expect(result.rooms, hasLength(count));
      });
    }

    test('followers are "N 粉丝" as written, through the &ensp; between them', () {
      final rooms = AcfunApi.searchPage(_sample('S04-search-p1').body, page: 1).rooms;
      expect(rooms.first.followers, '2.4万');
      expect(rooms.map((room) => room.followers).where((value) => value.isEmpty), isEmpty);
      expect(rooms.every((room) => room.effectiveLiveStatus == LiveStatus.offline), isTrue);
      expect(rooms.every((room) => room.onlineViewers.isEmpty && room.watching.isEmpty), isTrue);
    });

    test("liveId strings, explicit offline and unknown (3.x's navigation test)", () {
      final result = AcfunApi.searchPage(
        _searchAnswer([_searchCard(1, flag: 'live-opaque'), _searchCard(2), _searchCard(3, flag: null)], total: 3),
        page: 1,
      );
      expect(result.rooms.map((room) => room.effectiveLiveStatus), [
        LiveStatus.live,
        LiveStatus.offline,
        LiveStatus.unknown,
      ]);
      final first = result.rooms.first;
      expect(first.nick, 'Fixture & live');
      expect(first.introduction, 'Fixture <stream>');
      expect(first.followers, '2.4万');
      expect(first.avatar, 'https://img.example/a.jpg');
      expect(first.link, 'https://live.acfun.cn/live/1');
      expect(first.effectiveAudienceMetricType, AudienceMetricType.unknown);
    });

    test('a blank total with the empty-page marker is no results; a page past the total is empty', () {
      expect(AcfunApi.searchPage(_searchAnswer([], total: 0, blankZero: true), page: 1).rooms, isEmpty);
      expect(AcfunApi.searchPage(_searchAnswer([], total: 100), page: 99).rooms, isEmpty);
      expect(
        () => AcfunApi.searchPage(_searchAnswer([], total: 0, emptyMarker: false), page: 1),
        throwsA(isA<ApiChanged>()),
      );
    });

    test("blocked, cut or error answers are ApiChanged, not \"no results\" (3.x's checks)", () {
      for (final body in [
        '<html>access denied</html>',
        jsonEncode({'html': '<div class="empty-page"></div>'}),
        _searchAnswer([], total: 50, emptyMarker: false),
        _searchAnswer([_searchCard(1), _searchCard(2)], total: 1),
      ]) {
        expect(() => AcfunApi.searchPage(body, page: 1), throwsA(isA<ApiChanged>()), reason: body);
      }
      expect(() => AcfunApi.searchPage('', page: 1, status: 403), throwsA(isA<RiskControl>()), reason: 'REG-ACFUN-006');
    });

    test('a card whose author, link or name does not check out is left out (3.x failed the page)', () {
      final rooms = AcfunApi.searchPage(
        _searchAnswer([
          _searchCard(1, href: '/u/2'),
          _searchCard(2, href: 'https://wrong.example/u/2'),
          _searchCard(3, href: 'javascript:/u/3'),
          _searchCard(4, name: ' '),
          _searchCard(5),
          _searchCard(5),
          _searchCard(6, href: 'https://www.acfun.cn/u/6?from=search'),
        ], total: 7),
        page: 1,
      ).rooms;
      expect(rooms.map((room) => room.roomId), ['5', '6']);
      final data = AcfunApi.searchPage(_searchAnswer([_searchCard(1, avatar: 'data:payload')], total: 1), page: 1);
      expect(data.rooms.single.avatar, isEmpty);
    });
  });

  group('S05 room', () {
    test('live: the room 3.x built, with the signature as introduction', () {
      final fixture = _sample('S05-info-live');
      final room = AcfunApi.roomDetail(fixture.body, authorId: '40740702', status: fixture.status);
      final legacy = _legacy('S05-info-live');
      // 3.x left the introduction empty; the streamer's signature is what its
      // search cards showed as the introduction.
      _expectParity(
        room.toJson(),
        legacy['getRoomDetailForRefresh'] as Map<String, dynamic>,
        changed: {'introduction'},
      );
      expect(room.introduction, startsWith('大家好！这里是个人势虚拟偶像'));
      expect(room.isLiveNow, isTrue);
      expect(room.onlineViewers, '116');
      expect(room.followers, '5313');
      expect(room.data, isNull, reason: 'the broadcast comes from startPlay');
      // 10-3: createTime; the restriction of live/info (no paid show).
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 14, 37, 35, 941));
      expect(room.startedAt!.isBefore(fixture.capturedAt), isTrue);
      expect(room.restriction, LiveRestriction.none);
      // changed: new keys startedAt (10-3) and restriction (M2.1); the
      // introduction 3.x left empty (M4.10).
      expect(_added(room.toJson(), legacy['getRoomDetailForRefresh'] as Map<String, dynamic>), {
        'startedAt',
        'restriction',
        'introduction',
      });
    });

    test('offline: the room 3.x built (no title, cover or audience)', () {
      final fixture = _sample('S05-info-offline');
      final room = AcfunApi.roomDetail(fixture.body, authorId: '1', status: fixture.status);
      _expectParity(
        room.toJson(),
        _legacy('S05-info-offline')['getRoomDetailForRefresh'] as Map<String, dynamic>,
        changed: {'introduction'},
      );
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.watching, isEmpty, reason: "not 3.x's '0' default");
      expect(room.introduction, '我们不是直销!是传销!');
      expect((room.startedAt, room.restriction), (null, null), reason: 'no broadcast');
    });

    test('an unknown author is NotFound (3.x: a schema error)', () {
      final fixture = _sample('S05-info-missing');
      expect((_legacy('S05-info-missing')['getRoomDetailForRefresh'] as Map)['throws'], containsPair('kind', 'schema'));
      expect(
        () => AcfunApi.roomDetail(fixture.body, authorId: '99999999999', status: fixture.status),
        throwsA(isA<NotFound>()),
      );
    });

    test("only an identity-complete success is a room (3.x's contract test)", () {
      expect(
        AcfunApi.roomDetail(jsonEncode(_info(live: false)), authorId: '42').effectiveLiveStatus,
        LiveStatus.offline,
      );
      expect(AcfunApi.roomDetail(jsonEncode(_info()), authorId: '42').isLiveNow, isTrue);
      for (final (body, kind) in <(Map<String, Object?>, Matcher)>[
        ({}, isA<ApiChanged>()),
        ({'result': 0}, isA<NotFound>()),
        ({..._info(live: false), 'authorId': 43}, isA<ApiChanged>()),
        ({..._info(live: false), 'result': 429}, isA<ApiChanged>()),
        (
          {
            ..._info(live: false),
            'user': {'id': '42'},
          },
          isA<NotFound>(),
        ),
      ]) {
        expect(() => AcfunApi.roomDetail(jsonEncode(body), authorId: '42'), throwsA(kind), reason: '$body');
      }
      // 3.x also required liveId and streamName together; the state is liveId.
      expect(AcfunApi.roomDetail(jsonEncode({..._info(), 'streamName': ''}), authorId: '42').isLiveNow, isTrue);
    });

    test('HTTP statuses and non-JSON answers are typed', () {
      expect(() => AcfunApi.roomDetail('', authorId: '1', status: 502), throwsA(isA<NetworkFailure>()));
      expect(() => AcfunApi.roomDetail('', authorId: '1', status: 429), throwsA(isA<RateLimited>()));
      expect(() => AcfunApi.roomDetail('', authorId: '1', status: 403), throwsA(isA<RiskControl>()));
      expect(() => AcfunApi.roomDetail('', authorId: '1', status: 404), throwsA(isA<ApiChanged>()));
      expect(() => AcfunApi.roomDetail('<html>403</html>', authorId: '1'), throwsA(isA<ApiChanged>()));
    });
  });

  group('S06 visitor session', () {
    test('the session 3.x logged in with', () {
      final fixture = _sample('S06-visitor');
      final visitor = AcfunApi.visitor(fixture.body, deviceId: 'web_0123456789abcdef', status: fixture.status);
      final legacy = _legacy('S06-visitor');
      final query = legacy['startPlayQuery'] as Map<String, dynamic>;
      expect(visitor.userId, query['userId']);
      expect(visitor.token, query['acfun.api.visitor_st']);
      expect(visitor.deviceId, 'web_0123456789abcdef');
      final security = visitor.security;
      expect(security, isNotNull);
      expect(visitor.toString(), isNot(contains(visitor.token)));
      expect(visitor.toString(), isNot(contains('$security')));
    });

    test('acSecurity is optional: only danmaku needs it (the archived v4 failed streams without it)', () {
      final visitor = AcfunApi.visitor(
        jsonEncode({'result': 0, 'userId': 12345, 'acfun.api.visitor_st': 'fixture-visitor-token'}),
        deviceId: 'web_x',
      );
      expect((visitor.userId, visitor.token, visitor.security), ('12345', 'fixture-visitor-token', null));
    });

    test('a refused login is RiskControl; an incomplete one ApiChanged', () {
      expect(() => AcfunApi.visitor(jsonEncode({'result': 401}), deviceId: 'web_x'), throwsA(isA<RiskControl>()));
      for (final body in [
        {'result': 0, 'acfun.api.visitor_st': 't'},
        {'result': 0, 'userId': 0, 'acfun.api.visitor_st': 't'},
        {'result': 0, 'userId': 1},
        <String, Object>{},
      ]) {
        expect(
          () => AcfunApi.visitor(jsonEncode(body), deviceId: 'web_x'),
          throwsA(isA<ApiChanged>()),
          reason: '$body',
        );
      }
    });
  });

  group('S06 streams', () {
    test("live: the broadcast and the qualities 3.x read, in 3.x's order", () {
      final fixture = _sample('S06-startplay-live');
      final play = AcfunApi.startPlay(fixture.body, issuedAt: _issuedAt, status: fixture.status);
      final legacy = _legacy('S06-startplay-live')['playback'] as Map<String, dynamic>;
      final data = play.data!;
      expect(data.liveId, legacy['liveId']);
      expect([
        for (final quality in data.qualities)
          {'id': quality.id, 'label': quality.label, 'rank': quality.rank, 'urls': quality.urls},
      ], legacy['qualities']);
      expect(data.qualities.map((quality) => quality.label), ['蓝光 8M', '蓝光 4M', '超清', '高清']);
      expect(play.tickets, hasLength(4));
      expect(play.enterRoomAttach, isNotEmpty);
      expect(data.issuedAt, _issuedAt);
      // A broadcast that plays has no restriction; liveStartTime is the
      // createTime of live/info (10-3).
      expect(play.restriction, LiveRestriction.none);
      expect(data.startedAt, DateTime.utc(2026, 9, 27, 14, 37, 35, 941));
    });

    test("the qualities as 3.x listed them, and each one's URLs", () {
      final data = _liveData();
      final legacy = _legacy('S05-info-live');
      final qualities = AcfunApi.playQualities(data);
      expect([
        for (final quality in qualities)
          {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort, 'data': quality.data},
      ], legacy['getPlayQualites']);
      final urls = legacy['getPlayUrls'] as Map<String, dynamic>;
      for (final quality in qualities) {
        expect(AcfunApi.resolution(data, qualityId: quality.id).urls, urls['${quality.id}']);
      }
    });

    test("lines carry 3.x's media headers, FLV, the CDN as line id and the signature's lease", () {
      final resolution = AcfunApi.resolution(_liveData(), qualityId: 'BLUE_RAY');
      final line = resolution.lines.single;
      expect(resolution.appliedQualityData, 'BLUE_RAY');
      expect(line.headers, {
        'user-agent': AcfunApi.userAgent,
        'referer': 'https://live.acfun.cn/',
        'origin': 'https://live.acfun.cn',
      });
      expect(line.headers, HttpHeaderPolicy.normalize({...AcfunApi.apiHeaders, 'origin': AcfunApi.origin}));
      expect(line.format, StreamFormat.flv);
      expect(line.lineId, 'ali-acfun-adaptive.pull.etoote.com');
      final expiry = DateTime.fromMillisecondsSinceEpoch(1793123185 * 1000, isUtc: true);
      expect(expiry.difference(_issuedAt), const Duration(days: 30));
      expect(line.lease!.expiresAt, expiry);
      expect(line.lease!.refreshAt, expiry.subtract(const Duration(minutes: 10)));
      expect(line.lease!.cutsConnection, isFalse);
    });

    test('a quality the answer does not offer is StreamUnavailable, never another one', () {
      expect(() => AcfunApi.resolution(_liveData(), qualityId: 'ORIGIN'), throwsA(isA<StreamUnavailable>()));
    });

    test('offline: 129004 is StreamUnavailable (3.x: a service error)', () {
      final fixture = _sample('S06-startplay-offline');
      expect((_legacy('S06-startplay-offline')['playback'] as Map)['throws'], containsPair('result', 129004));
      expect(
        () => AcfunApi.startPlay(fixture.body, issuedAt: _issuedAt, status: fixture.status),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('a paid show without a ticket (380205) is live but paid: no broadcast, no tickets (3.x: RiskControl)', () {
      final play = AcfunApi.startPlay(
        jsonEncode({'result': AcfunApi.paidShowResult, 'error_msg': 'x'}),
        issuedAt: _issuedAt,
      );
      expect(play.data, isNull);
      expect(play.restriction, LiveRestriction.paid);
      expect(play.tickets, isEmpty);
      expect(play.enterRoomAttach, isEmpty);
    });

    test('another result is RiskControl (the session was refused); no liveId ApiChanged', () {
      expect(
        () => AcfunApi.startPlay(jsonEncode({'result': 401, 'error_msg': 'x'}), issuedAt: _issuedAt),
        throwsA(isA<RiskControl>()),
      );
      expect(
        () => AcfunApi.startPlay(jsonEncode({'result': 1, 'data': <String, Object>{}}), issuedAt: _issuedAt),
        throwsA(isA<ApiChanged>()),
      );
      expect(() => AcfunApi.startPlay(jsonEncode({'data': 1}), issuedAt: _issuedAt), throwsA(isA<ApiChanged>()));
    });
  });

  group('qualities', () {
    test('ordered by rank, not answer order; CDN lines merged, signatures untouched (3.x contract test)', () {
      const signed = 'https://cdn.example/high.flv?sign=a%2Bb%2Fc%3D&expires=9';
      final result = AcfunApi.qualities(
        jsonEncode(
          _manifest([
            [
              _representation('HIGH', 50, signed, label: '超清'),
              _representation('STANDARD', 30, 'https://cdn.example/low.flv'),
              _representation('BLUE_RAY', 130, 'https://cdn.example/best.flv', label: '蓝光 8M'),
            ],
            [_representation('HIGH', 50, 'https://backup.example/high.flv'), _representation('HIGH', 50, signed)],
          ]),
        ),
      );
      expect(result.map((quality) => quality.id), ['BLUE_RAY', 'HIGH', 'STANDARD']);
      expect(result[1].urls, [signed, 'https://backup.example/high.flv']);
      expect(result.first.label, '蓝光 8M');
      expect(() => result[1].urls.add('x'), throwsUnsupportedError);
      final data = AcfunRoomData(liveId: 'l', qualities: result, issuedAt: _issuedAt);
      final lines = AcfunApi.resolution(data, qualityId: 'HIGH').lines;
      expect(lines.map((line) => line.url), [signed, 'https://backup.example/high.flv']);
      expect(lines.map((line) => line.lineId), ['cdn.example', 'backup.example']);
      expect(lines.map((line) => line.lease), [null, null], reason: 'no auth_key, no lease');
    });

    test('level and bitrate are different scales: a level always ranks first (REG-ACFUN-005)', () {
      final result = AcfunApi.qualities(
        _manifest([
          [
            // No level: ranks by bitrate, below every level (the archived v4
            // compared `level ?? bitrate` and put this first).
            _representation('NO_LEVEL', null, 'https://cdn.example/a.flv', label: '无等级', bitrate: 8000),
            _representation('STANDARD', 30, 'https://cdn.example/b.flv', label: '高清', bitrate: 1000),
            _representation('BLUE_RAY', 130, 'https://cdn.example/c.flv', label: '蓝光 8M', bitrate: 8000),
            _representation('SMALL', null, 'https://cdn.example/d.flv', label: '小', bitrate: 500),
          ],
        ]),
      );
      expect(result.map((quality) => quality.id), ['BLUE_RAY', 'STANDARD', 'NO_LEVEL', 'SMALL']);
      expect(result.map((quality) => quality.rank), [1000130, 1000030, 8000, 500]);
      expect(AcfunApi.qualityRank(level: 0, bitrate: 999999), greaterThan(AcfunApi.qualityRank(bitrate: 999999)));
    });

    test('hidden and non-web media are left out; unknown quality ids stay apart (3.x contract test)', () {
      final result = AcfunApi.qualities(
        _manifest([
          [
            _representation('FUTURE', 150, 'https://cdn.example/future.flv', label: '原画 60帧'),
            {..._representation('HIDDEN', 999, 'https://cdn.example/hide.flv'), 'hidden': true},
            _representation('INJECTED', 999, 'javascript:alert(1)'),
            _representation('USERINFO', 999, 'https://user:password@cdn.example/video'),
            {'id': 0, 'url': 'https://cdn.example/id.flv', 'bitrate': 1000},
          ],
        ]),
      );
      expect(result.map((quality) => quality.id), ['FUTURE', 'id:0']);
      expect(result.first.label, '原画 60帧');
    });

    test("labels without a name are 3.x's, never an invented bitrate", () {
      final result = AcfunApi.qualities(
        _manifest([
          [
            _representation('BLUE_RAY', 130, 'https://cdn.example/a.flv'),
            _representation('SUPER', 70, 'https://cdn.example/b.flv'),
            _representation('HIGH', 50, 'https://cdn.example/c.flv'),
            _representation('STANDARD', 30, 'https://cdn.example/d.flv'),
            _representation('OTHER', 10, 'https://cdn.example/e.flv'),
          ],
        ]),
      );
      expect(result.map((quality) => quality.label), ['高码率', '蓝光', '超清', '高清', '画质 OTHER']);
      expect(result.first.label, isNot(contains('8M')));
    });

    test('the sample answer is a JSON string; an object works too', () {
      final raw = _videoPlayRes();
      expect(raw, isA<String>());
      expect(
        AcfunApi.qualities(jsonDecode(raw! as String)).map((quality) => quality.id),
        AcfunApi.qualities(raw).map((quality) => quality.id),
      );
    });

    test('a broken contract is ApiChanged; nothing playable StreamUnavailable', () {
      for (final raw in <Object?>[
        null,
        '<html>blocked</html>',
        {'liveAdaptiveManifest': <String, Object>{}},
      ]) {
        expect(() => AcfunApi.qualities(raw), throwsA(isA<ApiChanged>()), reason: '$raw');
      }
      for (final raw in <Object?>[
        {'liveAdaptiveManifest': <Object>[]},
        _manifest([
          [
            {'url': 'https://cdn.example/a.flv'},
          ],
        ]),
      ]) {
        expect(() => AcfunApi.qualities(raw), throwsA(isA<StreamUnavailable>()), reason: '$raw');
      }
    });

    test('HLS by path; a lease only for a key still valid', () {
      final data = AcfunRoomData(
        liveId: 'l',
        qualities: [
          AcfunQuality(
            id: 'HIGH',
            label: '超清',
            rank: 1,
            urls: const [
              'https://cdn.example/a.m3u8?auth_key=1790531185-0-0-x',
              'https://cdn.example/b.flv?auth_key=1790532085-0-0-x',
            ],
          ),
        ],
        issuedAt: _issuedAt,
      );
      final lines = AcfunApi.resolution(data, qualityId: 'HIGH').lines;
      expect(lines.map((line) => line.format), [StreamFormat.hls, StreamFormat.flv]);
      expect(lines.map((line) => line.lineId), ['cdn.example', 'cdn.example#2']);
      expect(lines.first.lease, isNull, reason: 'expired on issue');
      // 15 minutes: renewed a quarter of the lifetime before expiry.
      expect(
        lines.last.lease!.refreshAt,
        _issuedAt.add(const Duration(minutes: 15)).subtract(const Duration(minutes: 3, seconds: 45)),
      );
    });
  });

  test('danmaku arguments keep the session secrets out of diagnostics', () {
    final args = AcfunDanmakuArgs(
      authorId: '42',
      liveId: 'live-a',
      visitor: const AcfunVisitor(userId: '1', deviceId: 'web_x', token: 'secret-token', security: 'secret-key'),
      tickets: const ['ticket-a'],
      enterRoomAttach: 'attach',
    );
    expect(args.toString(), allOf(contains('live-a'), isNot(contains('secret')), isNot(contains('ticket-a'))));
    expect(args.headers, {'user-agent': AcfunApi.userAgent, 'origin': 'https://live.acfun.cn'});
  });
}
