// Kuaishou parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json). Every intended difference is listed
// with its reason; everything else must match.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('kuaishou', name);

const _names = {'1': '热门', '2': '网游', '3': '单机', '4': '手游', '5': '棋牌', '6': '娱乐', '7': '综合', '8': '文化'};

/// The room keys v4 added after 3.x (M2.1); 3.x's output never has them.
const _v4Keys = ['startedAt', 'restriction'];

/// Asserts that [actual] (a `toJson`) equals 3.x's [legacy] map on every key
/// 3.x wrote, except [changed] (intended differences) and the projections
/// compared separately (`danmakuData`, `qualities`). 3.x wrote null where the
/// immutable model writes ''. The v4 keys must be exactly [added] (M4.U.5,
/// the unified principles of docs/UPGRADES.md).
void _expectParity(
  Map<String, Object?> actual,
  Map<String, dynamic> legacy, {
  Set<String> changed = const {},
  Map<String, Object?> added = const {},
  String? reason,
}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (changed.contains(key) || key == 'danmakuData' || key == 'qualities') continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
  for (final key in _v4Keys) {
    expect(actual[key], added[key], reason: '${reason ?? ''} $key (v4 key)');
  }
}

/// M4.U.5 (unified principles "开播时间", "受限"): a list card starts at its
/// `statrtTime` (epoch milliseconds) and, having streams, is unrestricted.
Map<String, Object?> _cardKeys(Map<String, dynamic> card) => {
  'startedAt': DateTime.fromMillisecondsSinceEpoch(card['statrtTime'] as int, isUtc: true).toIso8601String(),
  'restriction': 'none',
};

/// 3.x's quality projection: label, id, sort and the line URLs.
List<Map<String, Object?>> _projection(List<LivePlayQuality> qualities) => [
  for (final quality in qualities)
    {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort, 'lines': quality.data},
];

/// The danmaku arguments as 3.x's projection wrote them.
Map<String, String>? _danmaku(LiveRoom room) => switch (room.danmakuData) {
  final KuaishouDanmakuArgs args => {'liveStreamId': args.liveStreamId, 'cookie': args.cookie},
  _ => null,
};

Map<String, dynamic> _data(Fixture fixture) =>
    (jsonDecode(fixture.body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;

/// The raw cards of a list sample in server order (home/list flattened).
List<Map<String, dynamic>> _rawCards(Fixture fixture) {
  final data = _data(fixture);
  if (!fixture.url.path.endsWith('home/list')) return (data['list'] as List).cast<Map<String, dynamic>>();
  return [
    for (final group in (data['list'] as List).cast<Map<String, dynamic>>())
      for (final label in (group['gameLiveInfo'] as List).cast<Map<String, dynamic>>())
        ...(label['liveInfo'] as List).cast<Map<String, dynamic>>(),
  ];
}

/// The signature expiry a sample URL carries, by CDN: 8 hex digits for tx
/// and ws, 10 decimal digits for ty and bd.
int? _signedExpiry(Uri url) {
  final query = url.queryParameters;
  return switch (url.host.split('.').first) {
    'tx-origin' => int.parse(query['txTime']!, radix: 16),
    'ws-origin' => int.parse(query['wsTime']!, radix: 16),
    'hw-origin' => int.parse(query['hwTime']!, radix: 16),
    'ty-origin' => int.parse(query['ty_Time']!),
    'bd-origin' => int.parse(query['wsTime']!),
    _ => null,
  };
}

/// Every line of every quality of [playUrls]: 3.x's URLs, the media headers,
/// FLV, the CDN host as line id and a lease 24 hours after [issuedAt].
void _expectLines(Object? playUrls, {required String roomId, required DateTime issuedAt}) {
  final qualities = KuaishouApi.qualities(playUrls);
  for (final quality in qualities) {
    final resolution = KuaishouApi.resolution(playUrls, quality: quality, roomId: roomId, issuedAt: issuedAt);
    expect(resolution.urls, quality.data, reason: '${quality.quality}: the lines are 3.x’s URLs');
    expect(resolution.appliedQualityData, quality.id);
    for (final line in resolution.lines) {
      final url = Uri.parse(line.url);
      expect(line.headers, KuaishouApi.mediaHeaders(roomId));
      expect(line.format, StreamFormat.flv);
      expect(line.lineId, startsWith(url.host));
      final name = url.pathSegments.last;
      expect(line.codec, RegExp('_(Game|Show|Ec)Avc').hasMatch(name) || playUrls is Map ? 'avc' : isNull, reason: name);
      final lease = line.lease!;
      expect(lease.cutsConnection, isFalse);
      expect(lease.expiresAt!.difference(lease.refreshAt), KuaishouApi.leaseLead);
      if (url.host.startsWith('ali-origin')) {
        // auth_key is scrubbed as a whole: its expiry is synthetic.
        expect(lease.expiresAt!.isAfter(issuedAt), isTrue);
      } else {
        expect(lease.expiresAt!.millisecondsSinceEpoch ~/ 1000, _signedExpiry(url), reason: url.host);
        expect(lease.expiresAt!.difference(issuedAt).inSeconds, closeTo(86400, 5), reason: '24 hours after issue');
      }
    }
  }
}

void main() {
  group('S01 category/data', () {
    for (final name in [
      for (var type = 1; type <= 8; type++) 'S01-category-type$type-p1',
      'S01-category-type1-p2',
      'S01-category-type5-p2',
    ]) {
      test('$name: areas match 3.x; paging follows hasMore', () {
        final fixture = _sample(name);
        final type = fixture.url.queryParameters['type']!;
        final result = KuaishouApi.areas(fixture.body, categoryId: type, categoryName: _names[type]!);
        final legacy = ((fixture.legacy as Map)['getSubCategores'] as List).cast<Map<String, dynamic>>();
        expect(result.areas, hasLength(legacy.length));
        for (final (index, area) in result.areas.indexed) {
          _expectParity(area.toJson(), legacy[index], reason: '$name[$index]');
        }
        expect(result.hasMore, _data(fixture)['hasMore'] == true);
      });
    }

    test('the eight fixed categories of 3.x', () {
      expect({for (final top in KuaishouApi.topCategories) top.id: top.name}, _names);
    });
  });

  group('S02/S03 area rooms', () {
    for (final name in [
      'S02-gameboard-p1',
      'S02-gameboard-p2',
      'S03-non-gameboard-p1',
      'S03-non-gameboard-p2',
      'S03-non-gameboard-p2-cursor',
    ]) {
      test('$name: cards, danmaku arguments and qualities match 3.x', () {
        final fixture = _sample(name);
        final result = KuaishouApi.areaRooms(fixture.body, issuedAt: fixture.capturedAt);
        final legacy = (fixture.legacy as List).cast<Map<String, dynamic>>();
        final raw = _rawCards(fixture);
        expect(result.rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        for (final (index, room) in result.rooms.indexed) {
          // link: 3.x wrote the broadcast's liveStreamId there (search wrote
          // the page URL); it is the room page now and the liveStreamId is in
          // KuaishouRoomData (REG-KUAISHOU-023).
          _expectParity(
            room.toJson(),
            legacy[index],
            changed: {'link'},
            added: _cardKeys(raw[index]),
            reason: '$name[$index]',
          );
          expect(room.link, 'https://live.kuaishou.com/u/${room.roomId}');
          expect(_danmaku(room), legacy[index]['danmakuData']);
          final data = room.data! as KuaishouRoomData;
          expect(data.liveStreamId, legacy[index]['link']);
          expect(data.issuedAt, fixture.capturedAt);
          expect(_projection(KuaishouApi.qualities(data.playUrls)), legacy[index]['qualities']);
          _expectLines(raw[index]['playUrls'], roomId: room.roomId, issuedAt: fixture.capturedAt);
        }
        expect(result.hasMore, isTrue, reason: 'every recorded page says hasMore');
      });
    }

    test('non-gameboard pages carry the cursor of the next page; gameboard pages do not', () {
      expect(KuaishouApi.areaRooms(_sample('S02-gameboard-p1').body, issuedAt: DateTime(2026)).cursor, isNull);
      final page1 = KuaishouApi.areaRooms(_sample('S03-non-gameboard-p1').body, issuedAt: DateTime(2026));
      expect(page1.cursor, '610_950484466');
      // The request 3.x made for page 2 (no cursor) got page 1 again
      // (REG-KUAISHOU-022); with the cursor it is a different page.
      final repeated = KuaishouApi.areaRooms(_sample('S03-non-gameboard-p2').body, issuedAt: DateTime(2026));
      expect(repeated.rooms.map((room) => room.roomId), page1.rooms.map((room) => room.roomId));
      final real = KuaishouApi.areaRooms(_sample('S03-non-gameboard-p2-cursor').body, issuedAt: DateTime(2026));
      expect(
        real.rooms.map((room) => room.roomId).toSet().intersection(page1.rooms.map((r) => r.roomId).toSet()),
        isEmpty,
      );
      expect(real.cursor, '257_1252287100');
    });

    test('the 【回放】 loop card stays live as in 3.x', () {
      final rooms = KuaishouApi.areaRooms(_sample('S02-gameboard-p1').body, issuedAt: DateTime(2026)).rooms;
      final loop = rooms.singleWhere((room) => room.title.startsWith('【回放】'));
      expect(loop.roomId, 'KPL704668133');
      expect(loop.isLiveNow, isTrue);
    });

    test('2K and 蓝光 tiers keep their platform names and levels, best first', () {
      final raw = _rawCards(_sample('S02-gameboard-p1'))
          .firstWhere((card) => (card['author'] as Map)['id'] == 'tingan666');
      expect(KuaishouApi.qualities(raw['playUrls']).map((quality) => '${quality.quality}/${quality.sort}'), [
        '2K/250',
        '蓝光 质臻/130',
        '蓝光 4M/70',
        '超清/50',
        '高清/30',
      ]);
    });

    test('cards without cover, caption, area or audience are kept; cards without an author id are skipped '
        '(REG-KUAISHOU-020: 3.x failed the page)', () {
      final body = jsonEncode({
        'data': {
          'hasMore': false,
          'list': [
            {
              'id': 'L1',
              'author': {'id': 'abc'},
            },
            {'id': 'L2', 'author': <String, dynamic>{}},
            'not a card',
          ],
        },
      });
      final result = KuaishouApi.areaRooms(body, issuedAt: DateTime(2026), cookie: 'did=1');
      expect(result.rooms.single.roomId, 'abc');
      final room = result.rooms.single;
      expect((room.cover, room.title, room.nick, room.area, room.watching), ('', '', '', '', ''));
      expect((room.startedAt, room.restriction), (null, null));
      expect(_danmaku(room), {'liveStreamId': 'L1', 'cookie': 'did=1'});
      expect(result.hasMore, isFalse);
      expect(KuaishouApi.areaRooms('{"data":{"hasMore":true,"list":[]}}', issuedAt: DateTime(2026)).hasMore, isFalse);
    });
  });

  test('S04 home list: one card per streamer, the card’s cover and caption (REG-KUAISHOU-017)', () {
    final fixture = _sample('S04-home-list');
    final rooms = KuaishouApi.recommendRooms(fixture.body, issuedAt: fixture.capturedAt);
    final legacy = (fixture.legacy as List).cast<Map<String, dynamic>>();
    final raw = _rawCards(fixture);
    expect(legacy, hasLength(48));
    // 3.x listed mnxfsj666888 twice (热推直播 and 手游直播); the first stays.
    final first = <String, int>{};
    for (final (index, room) in legacy.indexed) {
      first.putIfAbsent(room['roomId'] as String, () => index);
    }
    expect(rooms, hasLength(47));
    expect(rooms.map((room) => room.roomId), first.keys);
    for (final (position, room) in rooms.indexed) {
      final index = first.values.elementAt(position);
      final card = raw[index];
      // cover: 3.x showed the area poster (gameInfo.poster); title: 3.x
      // showed the streamer bio. Both are the card's now, like the area
      // lists (the bio stays the introduction and notice). link: see area
      // rooms.
      _expectParity(
        room.toJson(),
        legacy[index],
        changed: {'cover', 'title', 'link'},
        added: _cardKeys(card),
        reason: 'S04[$index]',
      );
      expect(legacy[index]['cover'], (card['gameInfo'] as Map)['poster']);
      expect(room.cover, anyOf(card['poster'], '${card['poster']}.jpg'), reason: 'the card, .jpg appended as 3.x did');
      final bio = ((card['author'] as Map)['description'] as String?)?.replaceAll('\n', ' ') ?? '';
      expect(legacy[index]['title'], bio);
      final caption = card['caption'] as String? ?? '';
      expect(room.title, caption.isEmpty ? bio : caption);
      expect(_danmaku(room), legacy[index]['danmakuData']);
    }
    for (final (index, card) in raw.indexed) {
      expect(_projection(KuaishouApi.qualities(card['playUrls'])), legacy[index]['qualities']);
    }
  });

  group('search', () {
    test('S06 result 2 is RateLimited, not “no results” (REG-KUAISHOU-015; 3.x returned [])', () {
      final fixture = _sample('S06-search-author-ratelimited');
      expect(fixture.legacy, isEmpty);
      expect(
        () => KuaishouApi.searchRooms(fixture.body, status: fixture.status),
        throwsA(isA<RateLimited>().having((error) => error.detail, 'detail', contains('操作太快'))),
      );
    });

    test('S08 result 10 (the guest gate) is RiskControl; 3.x returned []', () {
      final fixture = _sample('S08-search-livestream-busy');
      expect(fixture.legacy, isEmpty);
      expect(() => KuaishouApi.searchRooms(fixture.body), throwsA(isA<RiskControl>()));
    });

    // 3.x test/kuaishou_author_search_test.dart.
    test('live, offline and banned streamers; no audience instead of 0 (REG-KUAISHOU-010)', () {
      final rooms = KuaishouApi.searchRooms(
        jsonEncode({
          'data': {
            'type': 'authors',
            'result': 1,
            'list': [
              {
                'id': 'live_streamer',
                'name': 'Live streamer',
                'description': 'Nightly at 8',
                'avatar': 'https://example.com/a.jpg',
                'living': true,
                'counts': {'fan': '2960.9w'},
                'bannedStatus': {'banned': false},
              },
              {'id': 'offline_streamer', 'name': 'Offline streamer', 'living': false},
              {
                'id': 'banned_streamer',
                'name': 'Banned',
                'living': true,
                'bannedStatus': {'banned': true},
              },
              {'id': '', 'name': 'No id'},
              'not a map',
            ],
          },
        }),
      );
      expect(rooms.map((room) => room.roomId), ['live_streamer', 'offline_streamer', 'banned_streamer']);
      final live = rooms.first;
      expect(live.platform, 'kuaishou');
      expect((live.nick, live.title, live.userId), ('Live streamer', 'Live streamer', 'live_streamer'));
      expect((live.avatar, live.cover), ('https://example.com/a.jpg', 'https://example.com/a.jpg'));
      expect(live.followers, '2960.9w');
      expect(live.introduction, 'Nightly at 8');
      expect(live.link, 'https://live.kuaishou.com/u/live_streamer');
      expect(live.liveStatus, LiveStatus.live);
      expect(live.audienceValue(preferRealOnline: false, platformEnabled: false), isEmpty);
      expect(rooms[1].liveStatus, LiveStatus.offline);
      expect(rooms[1].followers, '0');
      expect(rooms[2].liveStatus, LiveStatus.banned);
    });

    test('result 1 without results is empty; other shapes are ApiChanged (3.x returned [] for all)', () {
      expect(KuaishouApi.searchRooms('{"data":{"result":1,"list":[]}}'), isEmpty);
      expect(KuaishouApi.searchRooms('{"data":{"result":1}}'), isEmpty);
      for (final body in ['{"data":{"list":"x"}}', '{"data":{"result":3}}', '{"data":null}', 'null', '<html>']) {
        expect(() => KuaishouApi.searchRooms(body), throwsA(isA<ApiChanged>()), reason: body);
      }
    });
  });

  group('S09-S12 room page', () {
    for (final name in ['S09-room-live', 'S09-room-live-replay']) {
      test('$name matches 3.x; qualities and lines from the page', () {
        final fixture = _sample(name);
        final requested = fixture.url.pathSegments.last;
        final legacy = fixture.legacy as Map<String, dynamic>;
        final room = KuaishouApi.roomDetail(
          fixture.body,
          requestedId: requested,
          issuedAt: fixture.capturedAt,
          cookie: 'fixture_cookie=1',
        );
        for (final entry in ['getRoomDetail', 'getRoomDetailForRefresh']) {
          final expected = legacy[entry] as Map<String, dynamic>;
          // watching, onlineViewers: 3.x showed gameInfo.watchingCount, a
          // figure of the whole area (“1万+” for both 王者荣耀 rooms); the
          // page has none for the room (REG-KUAISHOU-016).
          // followers: author.counts.fan, which 3.x never read.
          // link: see area rooms.
          // title: 3.x wrote the streamer bio; the page has no broadcast
          // title, so it is empty and the card's stays (A-3).
          // v4 keys (M4.U.5): living with streams is unrestricted; the page
          // has no broadcast start.
          _expectParity(
            room.toJson(),
            expected,
            changed: {'watching', 'onlineViewers', 'followers', 'link', 'title'},
            added: const {'restriction': 'none'},
            reason: '$name $entry',
          );
          expect(expected['watching'], '1万+');
          expect(_danmaku(room), expected['danmakuData']);
          expect((room.title, room.introduction), ('', expected['introduction']), reason: 'A-3');
        }
        expect(room.roomId, requested, reason: 'a follow keeps the id it was made with');
        expect(room.audienceValue(preferRealOnline: false, platformEnabled: false), isEmpty);
        expect(room.followers, isNot('0'));
        final data = room.data! as KuaishouRoomData;
        expect(data.liveStreamId, (legacy['getRoomDetail'] as Map)['link']);
        expect(_projection(KuaishouApi.qualities(data.playUrls)), legacy['parsePlayQualities']);
        expect((data.playUrls! as Map)['hevc'], isEmpty);
        _expectLines(data.playUrls, roomId: requested, issuedAt: fixture.capturedAt);
      });
    }

    test('a follow refresh leaves the streams out', () {
      final fixture = _sample('S09-room-live');
      final room = KuaishouApi.roomDetail(
        fixture.body,
        requestedId: 'baixi9999999999',
        issuedAt: fixture.capturedAt,
        withStreams: false,
      );
      expect((room.data! as KuaishouRoomData).playUrls, isNull);
      expect((room.data! as KuaishouRoomData).liveStreamId, 'XT8F1KPOf0c');
      expect(room.restriction, LiveRestriction.none, reason: 'the same page: the refresh sees the streams too');
      expect(room.startedAt, isNull);
    });

    test("M13.16: the page's emoji table goes to the danmaku, https, codes only", () {
      final fixture = _sample('S09-room-live');
      final room = KuaishouApi.roomDetail(fixture.body, requestedId: 'baixi9999999999', issuedAt: fixture.capturedAt);
      final emotes = (room.danmakuData! as KuaishouDanmakuArgs).emotes;
      expect(emotes, hasLength(207));
      expect(emotes['[笑哭]'], startsWith('https://'));
      expect(emotes['[666]'], 'https://ali2.a.yximgs.com/bs2/emotion/1704763447505third_party_s1296657489.png');
      final table = KuaishouApi.emojiTable({
        'pcConfig': {
          'pcConfig': {
            'config': {
              'pcLive.webConfig.emojiPanel': {'[a]': '//x.yximgs.com/a.png', 'b': '//x/b.png', '[c]': '', '[d]': 3},
            },
          },
        },
      });
      expect(table, {'[a]': 'https://x.yximgs.com/a.png'});
      expect(KuaishouApi.emojiTable(const {}), isEmpty);
    });

    test('S11 offline room is offline without cover or danmaku (REG-KUAISHOU-020; 3.x threw TypeError)', () {
      final fixture = _sample('S11-room-offline');
      final legacy = fixture.legacy as Map<String, dynamic>;
      expect((legacy['getRoomDetailForRefresh'] as Map)['throws'], 'TypeError');
      expect((legacy['getRoomDetail'] as Map)['liveStatus'], LiveStatus.unknown.index, reason: '3.x hid the error');
      final room = KuaishouApi.roomDetail(fixture.body, requestedId: 'tianci666', issuedAt: fixture.capturedAt);
      final author =
          (((KuaishouApi.initialState(fixture.body)['liveroom'] as Map)['playList'] as List).first as Map)['author']
              as Map;
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.roomId, 'tianci666');
      expect(room.nick, author['name']);
      expect(room.title, isEmpty, reason: 'A-3: no broadcast title on the page; 3.x showed the bio');
      expect(room.introduction, author['description']);
      expect((room.cover, room.area, room.watching), ('', '', ''), reason: 'no audience for an offline room, not 0');
      expect(room.danmakuData, isNull);
      expect((room.data! as KuaishouRoomData).liveStreamId, isNull);
      expect(KuaishouApi.qualities((room.data! as KuaishouRoomData).playUrls), isEmpty);
      expect((room.restriction, room.startedAt), (null, null), reason: 'M4.U.5: nothing to say for an offline room');
      expect(room.toJson().keys, isNot(anyOf(contains('restriction'), contains('startedAt'))));
    });

    test('S12 errorType 22 is NotFound (3.x threw TypeError or showed an unknown room)', () {
      final fixture = _sample('S12-room-notfound');
      expect(((fixture.legacy as Map)['getRoomDetail'] as Map)['liveStatus'], LiveStatus.unknown.index);
      expect(
        () => KuaishouApi.roomDetail(fixture.body, requestedId: 'purelive_fixture_404', issuedAt: fixture.capturedAt),
        throwsA(isA<NotFound>().having((error) => error.detail, 'detail', contains('22'))),
      );
    });

    test('the state is cut by JSON structure; “undefined” inside strings stays (REG-KUAISHOU-018)', () {
      final state = KuaishouApi.initialState(_sample('S11-room-offline').body);
      final room = ((state['liveroom'] as Map)['playList'] as List).first as Map;
      // 3.x rewrote every “undefined”, turning this URL into …/live/null.
      expect((room['liveStream'] as Map)['url'], 'https://m.gifshow.com/fw/live/undefined');
      expect(room.containsKey('authToken') && room['authToken'] == null, isTrue);
      const html =
          '<script>window.__INITIAL_STATE__ '
          r'= {"a":"x;y}","b":undefined,"c":["undefinedX",undefined],"d":"q\"undefined"};(function(){})();</script>';
      final parsed = KuaishouApi.initialState(html);
      expect(parsed['a'], 'x;y}');
      expect(parsed.containsKey('b') && parsed['b'] == null, isTrue);
      expect(parsed['c'], ['undefinedX', null]);
      expect(parsed['d'], 'q"undefined');
      expect(() => KuaishouApi.initialState('<script>window.__INITIAL_STATE__={"a":1'), throwsA(isA<ApiChanged>()));
    });

    String page(Map<String, dynamic> room) =>
        '<html><script>window.__INITIAL_STATE__=${jsonEncode({
          'liveroom': {
            'playList': [room],
          },
        })};(function(){})();</script></html>';

    test('isLiving true, 1 and "true" in any case are live (REG-KUAISHOU-007)', () {
      for (final value in <Object?>[true, 1, 'true', 'TRUE']) {
        final room = KuaishouApi.roomDetail(
          page({
            'isLiving': value,
            'author': {'id': 'abc'},
          }),
          requestedId: 'abc',
          issuedAt: DateTime(2026),
        );
        expect(room.isLiveNow, isTrue, reason: '$value');
      }
      for (final value in <Object?>[false, 0, 'false', null]) {
        final room = KuaishouApi.roomDetail(page({'isLiving': value}), requestedId: 'abc', issuedAt: DateTime(2026));
        expect(room.effectiveLiveStatus, LiveStatus.offline, reason: '$value');
      }
    });

    test('the requested id stays the identity whatever author.id says', () {
      final room = KuaishouApi.roomDetail(
        page({
          'isLiving': true,
          'author': {'id': 'ATM-Heros'},
        }),
        requestedId: ' atm-heros ',
        issuedAt: DateTime(2026),
      );
      expect(room.roomId, 'atm-heros');
      expect(room.link, 'https://live.kuaishou.com/u/atm-heros');
    });

    test('verification pages and other errorTypes are RiskControl, the user’s cookie suspect when sent '
        '(REG-KUAISHOU-008)', () {
      final other = page({
        'isLiving': false,
        'errorType': {'type': 31, 'title': '错误代码31'},
      });
      expect(
        () => KuaishouApi.roomDetail(other, requestedId: 'abc', issuedAt: DateTime(2026), userCookie: true),
        throwsA(
          isA<RiskControl>()
              .having((error) => error.cookieSuspect, 'cookieSuspect', isTrue)
              .having((error) => error.detail, 'detail', allOf(contains('31'), contains('错误代码31'))),
        ),
      );
      const captcha = '<html><div id="captcha">请完成安全验证</div></html>';
      expect(
        () => KuaishouApi.roomDetail(captcha, requestedId: 'abc', issuedAt: DateTime(2026)),
        throwsA(isA<RiskControl>().having((error) => error.cookieSuspect, 'cookieSuspect', isFalse)),
      );
      expect(
        () => KuaishouApi.roomDetail(
          page({'isLiving': true}),
          requestedId: 'abc',
          issuedAt: DateTime(2026),
          url: Uri.parse('https://captcha.zt.kuaishou.com/iframe/index.html'),
        ),
        throwsA(isA<RiskControl>()),
        reason: 'redirected to a verification page',
      );
      expect(
        () => KuaishouApi.roomDetail('<html>maintenance</html>', requestedId: 'abc', issuedAt: DateTime(2026)),
        throwsA(isA<ApiChanged>()),
      );
      expect(
        () => KuaishouApi.roomDetail(
          '<script>window.__INITIAL_STATE__={"liveroom":{"playList":[]}};</script>',
          requestedId: 'abc',
          issuedAt: DateTime(2026),
        ),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('HTTP status: 429 RateLimited, 5xx NetworkFailure, 403 RiskControl, 404 ApiChanged', () {
      Object? thrown(int status) {
        try {
          KuaishouApi.roomDetail('', requestedId: 'a', issuedAt: DateTime(2026), status: status, userCookie: true);
        } on SiteError catch (error) {
          return error;
        }
        return null;
      }

      expect(thrown(429), isA<RateLimited>());
      expect(thrown(502), isA<NetworkFailure>());
      expect(thrown(403), isA<RiskControl>().having((error) => error.cookieSuspect, 'cookieSuspect', isTrue));
      expect(thrown(404), isA<ApiChanged>());
      expect(() => KuaishouApi.recommendRooms('', issuedAt: DateTime(2026), status: 401), throwsA(isA<RiskControl>()));
      expect(
        () => KuaishouApi.areas('{"data":{"result":2,"error_msg":"操作太快了"}}', categoryId: '1', categoryName: '热门'),
        throwsA(isA<RateLimited>()),
        reason: 'the result table holds for every live_api answer',
      );
      expect(
        () => KuaishouApi.areaRooms('{"data":{"hasMore":true}}', issuedAt: DateTime(2026)),
        throwsA(isA<ApiChanged>()),
      );
    });
  });

  group('streams', () {
    Map<String, dynamic> representation(String name, int level, String url) => {
      'name': name,
      'shortName': name,
      'level': level,
      'bitrate': level * 30,
      'url': url,
    };
    Map<String, dynamic> descriptor(List<Map<String, dynamic>> representations) => {
      'adaptationSet': {'representation': representations},
    };
    Map<String, dynamic> lines(String prefix) => descriptor([
      representation('高清', 30, 'https://$prefix/hd.flv'),
      representation('蓝光 4M', 70, 'https://$prefix/4m.flv'),
    ]);

    // 3.x test/kuaishou_playback_parser_test.dart.
    test('room page {h264, hevc}: best first, the H.264 URLs', () {
      final qualities = KuaishouApi.qualities({'h264': lines('line-a'), 'hevc': <String, dynamic>{}});
      expect(qualities.map((quality) => quality.quality), ['蓝光 4M', '高清']);
      expect(qualities.first.sort, 70);
      expect(qualities.first.data, ['https://line-a/4m.flv']);
    });

    test('card descriptor lists merge their CDN lines per quality (REG-KUAISHOU-003)', () {
      final qualities = KuaishouApi.qualities([lines('line-a'), lines('line-b'), lines('line-a')]);
      expect(qualities, hasLength(2));
      expect(qualities.first.data, ['https://line-a/4m.flv', 'https://line-b/4m.flv']);
      expect(qualities.last.data, ['https://line-a/hd.flv', 'https://line-b/hd.flv']);
    });

    test('HEVC only when there is no H.264 (REG-KUAISHOU-002)', () {
      final qualities = KuaishouApi.qualities({'h264': <String, dynamic>{}, 'hevc': lines('hevc-line')});
      expect(qualities, hasLength(2));
      expect(qualities.first.data, ['https://hevc-line/4m.flv']);
      final resolution = KuaishouApi.resolution(
        {'h264': <String, dynamic>{}, 'hevc': lines('hevc-line')},
        quality: qualities.first,
        roomId: 'r',
        issuedAt: DateTime(2026),
      );
      expect(resolution.lines.single.codec, 'hevc');
    });

    test('malformed and non-http entries are ignored; nothing playable is StreamUnavailable', () {
      final playUrls = [
        {
          'adaptationSet': {
            'representation': [
              {'name': 'bad', 'level': 1, 'url': 'javascript:alert(1)'},
              {'name': 'missing', 'level': 2},
              {'name': 'relative', 'level': 3, 'url': '/relative.flv'},
            ],
          },
        },
        null,
      ];
      expect(KuaishouApi.qualities(playUrls), isEmpty);
      for (final value in <Object?>[
        playUrls,
        null,
        <String, dynamic>{'h264': <String, dynamic>{}},
      ]) {
        expect(
          () => KuaishouApi.resolution(
            value,
            quality: const LivePlayQuality(quality: '高清', id: '高清\u000030'),
            roomId: 'r',
            issuedAt: DateTime(2026),
          ),
          throwsA(isA<StreamUnavailable>()),
          reason: '$value',
        );
      }
    });

    test('names fall back to shortName, qualityType and 清晰度 {sort}; sort is level, else bitrate', () {
      const base = 'https://tx-origin.pull.yximgs.com/gifshow/abc_GameAvcHdL0.flv';
      final qualities = KuaishouApi.qualities(
        descriptor([
          {'shortName': '4M', 'bitrate': 4000, 'url': '$base?a=1'},
          {'qualityType': 'HIGH', 'level': 50, 'url': '$base?a=2'},
          {'url': '$base?a=3'},
        ]),
      );
      expect(qualities.map((quality) => '${quality.quality}/${quality.sort}'), ['4M/4000', '高清/50', '清晰度 0/0']);
      expect(qualities.map((quality) => quality.id), ['4M\u00004000', 'HIGH\u000050', '清晰度 0\u00000']);
    });

    test('a quality that is gone falls to the next lower one', () {
      final playUrls = descriptor([
        representation('高清', 30, 'https://a/30.flv'),
        representation('蓝光', 70, 'https://a/70.flv'),
      ]);
      String pick(int sort) => KuaishouApi.resolution(
        playUrls,
        quality: LivePlayQuality(quality: 'x', id: 'gone', sort: sort),
        roomId: 'r',
        issuedAt: DateTime(2026),
      ).urls.single;
      expect(pick(130), 'https://a/70.flv');
      expect(pick(50), 'https://a/30.flv');
      expect(pick(10), 'https://a/30.flv');
    });

    test('a quality merged from descriptors of two codecs plays one codec; 3.x mixed them', () {
      const avc = 'https://tx-origin.pull.yximgs.com/gifshow/abc_GameAvcHdL0.flv?txTime=6aba3f2e';
      const hevc = 'https://ws-origin.pull.yximgs.com/gifshow/abc_GameHevcHdL0.flv?wsTime=6aba3f2e';
      const plain = 'https://tx-origin.pull.yximgs.com/gifshow/abc_ma1500.flv?txTime=6aba3f2e';
      final playUrls = [
        descriptor([representation('超清', 50, avc)]),
        descriptor([representation('超清', 50, hevc)]),
        descriptor([representation('超清', 50, plain)]),
      ];
      final quality = KuaishouApi.qualities(playUrls).single;
      expect(quality.data, [avc, hevc, plain], reason: '3.x’s quality data');
      final resolution = KuaishouApi.resolution(playUrls, quality: quality, roomId: 'r', issuedAt: DateTime(2026));
      expect(resolution.urls, [avc, plain]);
      expect(resolution.lines.map((line) => line.codec), ['avc', null]);
      expect(resolution.lines.map((line) => line.lineId), ['tx-origin.pull.yximgs.com', 'tx-origin.pull.yximgs.com#2']);
    });

    test('media headers: lower case, the room page as referer, the cookie only when given', () {
      expect(KuaishouApi.mediaHeaders(''), {
        'user-agent': KuaishouApi.mediaUserAgent,
        'origin': 'https://live.kuaishou.com',
        'referer': 'https://live.kuaishou.com/',
      });
      final headers = KuaishouApi.mediaHeaders('room 1', cookie: ' did=1;\r\n kpn=GAME ');
      expect(headers['referer'], 'https://live.kuaishou.com/u/room%201');
      expect(headers['cookie'], 'did=1; kpn=GAME');
      expect(KuaishouApi.mediaHeaders('x', cookie: '  ').containsKey('cookie'), isFalse);
      expect(KuaishouApi.mediaUserAgent, contains('Chrome/140.0.0.0'), reason: '3.x’s media UA');
    });

    test('lease: hex and decimal times, auth_key, nothing recognisable, already expired, short lifetimes', () {
      final issued = DateTime.utc(2026, 9, 27);
      final expiry = issued.add(const Duration(hours: 24)).millisecondsSinceEpoch ~/ 1000;
      final hex = expiry.toRadixString(16);
      for (final query in [
        'txTime=$hex',
        'wsTime=$hex',
        'hwTime=$hex',
        'ty_Time=$expiry',
        'wsTime=$expiry',
        'auth_key=$expiry-0-0-abc',
      ]) {
        final lease = KuaishouApi.lease(Uri.parse('https://cdn.test/a.flv?x=1&$query&y=2'), issued)!;
        expect(lease.expiresAt, issued.add(const Duration(hours: 24)), reason: query);
        expect(lease.refreshAt, issued.add(const Duration(hours: 23, minutes: 50)), reason: query);
        expect(lease.cutsConnection, isFalse);
      }
      expect(KuaishouApi.lease(Uri.parse('https://cdn.test/a.flv?stat=1'), issued), isNull);
      final past = (issued.millisecondsSinceEpoch ~/ 1000 - 60).toRadixString(16);
      expect(KuaishouApi.lease(Uri.parse('https://cdn.test/a.flv?txTime=$past'), issued), isNull);
      final soon = (issued.millisecondsSinceEpoch ~/ 1000 + 400).toRadixString(16);
      final short = KuaishouApi.lease(Uri.parse('https://cdn.test/a.flv?txTime=$soon'), issued)!;
      expect(short.expiresAt!.difference(short.refreshAt), const Duration(seconds: 100));
    });

    test('new CDNs: bd-origin wsTime is decimal, ali-origin expiry comes from auth_key', () {
      final hosts = <String>{};
      for (final name in ['S02-gameboard-p2', 'S03-non-gameboard-p1', 'S03-non-gameboard-p2-cursor']) {
        final fixture = _sample(name);
        for (final card in _rawCards(fixture)) {
          for (final quality in KuaishouApi.qualities(card['playUrls'])) {
            hosts.addAll([for (final url in quality.data! as List<String>) Uri.parse(url).host.split('.').first]);
          }
        }
      }
      expect(hosts, containsAll(['tx-origin', 'ws-origin', 'ty-origin', 'bd-origin', 'ali-origin']));
    });
  });

  group('session', () {
    test('S09 Set-Cookie: the cookies 3.x’s jar kept', () {
      final fixture = _sample('S09-room-live');
      final headers = ((fixture.meta['response'] as Map)['headers'] as Map)['set-cookie'] as List;
      expect(KuaishouApi.setCookies(headers.cast<String>()), {
        'kuaishou.live.bfb1s': '092bf5827afad90f04b7f1694477c8a5',
        'clientid': '3',
        'did': 'bjh_227k205y2093qn7d7389m2u2tqfv3ni9',
        'client_key': '26550b54',
        'kpn': 'PQSH_HVMK',
      });
      expect(KuaishouApi.setCookies(['a=1; Max-Age=0', 'b=; path=/', '=x', 'c d=1', 'e=2; max-age=60']), {'e': '2'});
    });

    test('the device report carries the did and 3.x’s fixed values', () {
      final payload = KuaishouApi.devicePayload('web_1', timestamp: 1700000000000, incrementId: 1234);
      final common = payload['common']! as Map<String, Object>;
      expect((common['identity_package']! as Map)['device_id'], 'web_1');
      expect((common['app_package']! as Map)['product_name'], 'KS_GAME_LIVE_PC');
      final log = (payload['logs']! as List).single as Map<String, Object>;
      expect((log['client_timestamp'], log['client_increment_id']), (1700000000000, 1234));
      expect(jsonDecode(jsonEncode(payload)), isA<Map<String, dynamic>>());
    });
  });

  test('covers: .jpg appended to extensionless screenshots as 3.x did; nothing for none (3.x threw)', () {
    String cover(Object? poster) => KuaishouApi.areaRooms(
      jsonEncode({
        'data': {
          'list': [
            {
              'author': {'id': 'a'},
              'poster': poster,
            },
          ],
        },
      }),
      issuedAt: DateTime(2026),
    ).rooms.single.cover;
    expect(cover('https://live4.static.yximgs.com/live/game/screenshot/X~1~1'), endsWith('X~1~1.jpg'));
    expect(cover('https://p2-pro.a.yximgs.com/uhead/AB/x.jpg'), 'https://p2-pro.a.yximgs.com/uhead/AB/x.jpg');
    expect(cover('https://a.test/x.WEBP'), 'https://a.test/x.WEBP');
    expect(cover('https://a.test/x?size=1'), 'https://a.test/x?size=1', reason: '3.x appended into the query');
    expect(cover(null), '');
  });

  group('M4.U.5 upgrades (unified principles)', () {
    const stream = {
      'adaptationSet': {
        'representation': [
          {'name': '高清', 'level': 30, 'url': 'https://tx-origin.pull.yximgs.com/gifshow/x_GameAvcSdL0.flv'},
        ],
      },
    };
    String list(List<Map<String, dynamic>> cards) => jsonEncode({
      'data': {'hasMore': false, 'list': cards},
    });
    Map<String, dynamic> card(Map<String, dynamic> fields) => {
      'id': 'L1',
      'author': {'id': 'abc'},
      ...fields,
    };
    String page(Map<String, dynamic> room) =>
        '<html><script>window.__INITIAL_STATE__=${jsonEncode({
          'liveroom': {
            'playList': [room],
          },
        })};(function(){})();</script></html>';

    test('开播时间: a card starts at statrtTime (epoch ms), else startTime; placeholders and seconds are none', () {
      DateTime? started(Map<String, dynamic> fields) =>
          KuaishouApi.areaRooms(list([card(fields)]), issuedAt: DateTime(2026)).rooms.single.startedAt;
      final at = DateTime.utc(2026, 9, 27, 9, 19, 38, 677);
      expect(started({'statrtTime': 1790500778677}), at);
      expect(started({'statrtTime': '1790500778677'}), at);
      expect(started({'startTime': 1790500778677}), at, reason: 'the correct spelling, should the platform fix it');
      expect(started({'statrtTime': 0, 'startTime': 1790500778677}), at);
      for (final value in <Object?>[null, 0, -1, 1790500778, 1790500778.5, 'soon', 17905007786770]) {
        expect(started({'statrtTime': value}), isNull, reason: '$value');
      }
      final room = KuaishouApi.areaRooms(
        list([
          card({'statrtTime': 1790500778677}),
        ]),
        issuedAt: DateTime(2026),
      ).rooms.single;
      expect(room.toJson()['startedAt'], '2026-09-27T09:19:38.677Z');
      expect(LiveRoom.fromJson(room.toJson()).startedAt, at);
      final recommended = KuaishouApi.recommendRooms(
        jsonEncode({
          'data': {
            'list': [
              {
                'gameLiveInfo': [
                  {
                    'liveInfo': [
                      card({'statrtTime': 1790500778677}),
                    ],
                  },
                ],
              },
            ],
          },
        }),
        issuedAt: DateTime(2026),
      ).single;
      expect(recommended.startedAt, at, reason: 'recommendation cards too');
    });

    test('受限: a card with a playable stream is unrestricted; without one it is unknown and still live', () {
      List<LiveRoom> rooms(List<Map<String, dynamic>> cards) =>
          KuaishouApi.areaRooms(list(cards), issuedAt: DateTime(2026)).rooms;
      final parsed = rooms([
        card({
          'playUrls': [stream],
        }),
        {
          'id': 'L2',
          'author': {'id': 'no_streams'},
        },
        {
          'id': 'L3',
          'author': {'id': 'bad_streams'},
          'playUrls': [
            {
              'adaptationSet': {
                'representation': [
                  {'name': '高清', 'level': 30, 'url': 'javascript:alert(1)'},
                ],
              },
            },
          ],
        },
      ]);
      expect(parsed.map((room) => room.restriction), [LiveRestriction.none, null, null]);
      expect(parsed.every((room) => room.isLiveNow && room.followGroup == FollowGroup.live), isTrue);
    });

    test('受限: a living page without a playable stream is live and unplayable, with or without streams', () {
      for (final playUrls in <Object?>[
        null,
        <String, dynamic>{'h264': <String, dynamic>{}, 'hevc': <String, dynamic>{}},
        <String, dynamic>{
          'h264': {
            'adaptationSet': {
              'representation': [
                {'name': '高清', 'level': 30, 'url': '/relative.flv'},
              ],
            },
          },
        },
      ]) {
        for (final withStreams in [true, false]) {
          final room = KuaishouApi.roomDetail(
            page({
              'isLiving': true,
              'author': {'id': 'abc'},
              'liveStream': {'id': 'L1', 'playUrls': playUrls},
            }),
            requestedId: 'abc',
            issuedAt: DateTime(2026),
            withStreams: withStreams,
          );
          expect(room.liveStatus, LiveStatus.live, reason: '$playUrls');
          expect(room.restriction, LiveRestriction.unplayable, reason: '$playUrls');
          expect((room.isLiveNow, room.isPlayableNow, room.followGroup), (true, true, FollowGroup.live));
          expect(room.toJson()['restriction'], 'unplayable');
        }
      }
      final playable = KuaishouApi.roomDetail(
        page({
          'isLiving': true,
          'liveStream': {
            'privateLive': true,
            'playUrls': {'h264': stream},
          },
        }),
        requestedId: 'abc',
        issuedAt: DateTime(2026),
      );
      expect(playable.restriction, LiveRestriction.none, reason: 'privateLive is not read (never seen true)');
      final offline = KuaishouApi.roomDetail(
        page({
          'isLiving': false,
          'liveStream': {'playUrls': <String, dynamic>{}},
        }),
        requestedId: 'abc',
        issuedAt: DateTime(2026),
      );
      expect(offline.restriction, isNull);
    });

    test('房间身份: S13 the page of a lower-case id is the streamer in its own spelling', () {
      final fixture = _sample('S13-room-id-case');
      expect(fixture.url.path, '/u/kpl704668133');
      final state = KuaishouApi.initialState(fixture.body);
      final raw = ((state['liveroom'] as Map)['playList'] as List).first as Map;
      expect((raw['author'] as Map)['id'], 'KPL704668133', reason: 'the platform answers its own spelling');
      final replay = _sample('S09-room-live-replay');
      final recorded = KuaishouApi.roomDetail(replay.body, requestedId: 'KPL704668133', issuedAt: replay.capturedAt);
      final room = KuaishouApi.roomDetail(fixture.body, requestedId: 'kpl704668133', issuedAt: fixture.capturedAt);
      expect(room.roomId, 'kpl704668133', reason: 'the requested spelling stays (M2.1)');
      expect((room.nick, room.isLiveNow), (recorded.nick, true));
      expect((room.data! as KuaishouRoomData).liveStreamId, (recorded.data! as KuaishouRoomData).liveStreamId);
      expect(room.hasSameIdentity(recorded), isTrue);
      expect(room.identityKey, 'kuaishou:kpl704668133');
      expect(SiteIds.ignoresRoomIdCase('kuaishou'), isTrue);
      expect(room.restriction, LiveRestriction.none);
      final data = room.data! as KuaishouRoomData;
      expect(KuaishouApi.qualities(data.playUrls).map((quality) => quality.sort), [130, 70, 50, 30]);
      _expectLines(data.playUrls, roomId: room.roomId, issuedAt: fixture.capturedAt);
    });
  });

  group('M4.D H.265 qualities (优先 H.264)', () {
    // S10: a room page whose H.265 set has 4K and 蓝光 质臻 that H.264 lacks
    // (2026-09-30, anonymous session); both FLV with codec id 12.
    final fixture = _sample('S10-room-live-hevc');
    final room = KuaishouApi.roomDetail(fixture.body, requestedId: 'KPL704668133', issuedAt: fixture.capturedAt);
    final playUrls = (room.data! as KuaishouRoomData).playUrls;

    test('S10: H.264 qualities first as before, the H.265-only ones after with “ · H.265”', () {
      expect((room.isLiveNow, room.restriction), (true, LiveRestriction.none));
      final on = KuaishouApi.qualities(playUrls);
      expect(on.map((quality) => quality.quality), ['蓝光 4M', '超清', '高清', '4K · H.265', '蓝光 质臻 · H.265']);
      expect(on.map((quality) => quality.id), [
        '蓝光 4M\u000070',
        '超清\u000050',
        '高清\u000030',
        '4K · H.265\u0000490',
        '蓝光 质臻 · H.265\u0000130',
      ]);
      for (final quality in on.take(3)) {
        expect((quality.data! as List).single, contains('SportAvc'), reason: 'H.264 tiers keep only their H.264 URL');
      }
      final off = KuaishouApi.qualities(playUrls, preferH264: false);
      expect(off.map((quality) => quality.sort), [490, 130, 70, 50, 30], reason: 'off: by sort (3.x order)');
    });

    test('S10: an H.265 quality plays its HEVC FLV line; a missing quality falls to H.264', () {
      final qualities = KuaishouApi.qualities(playUrls);
      final uhd = KuaishouApi.resolution(
        playUrls,
        quality: qualities[3],
        roomId: room.roomId,
        issuedAt: fixture.capturedAt,
      );
      final line = uhd.lines.single;
      expect((line.codec, line.format, uhd.appliedQualityData), ('hevc', StreamFormat.flv, '4K · H.265\u0000490'));
      expect(line.url, contains('SportHevcUltra4kL2Promax.flv'));
      expect(line.headers, KuaishouApi.mediaHeaders(room.roomId));
      expect(line.lease!.expiresAt!.difference(fixture.capturedAt).inHours, 24);
      String? fallback(int sort) => KuaishouApi.resolution(
        playUrls,
        quality: LivePlayQuality(quality: '蓝光 质臻', id: '蓝光 质臻\u0000$sort', sort: sort),
        roomId: room.roomId,
        issuedAt: fixture.capturedAt,
      ).appliedQualityData?.toString();
      expect(fallback(130), '蓝光 4M\u000070', reason: 'a saved H.264 preference never lands on H.265');
      expect(fallback(10), '高清\u000030');
    });
  });

  group('A-3 detail title (F.5a)', () {
    test('entering from a card keeps its title; refreshes and follows never put the bio back', () {
      final fixture = _sample('S09-room-live');
      final detail = KuaishouApi.roomDetail(fixture.body, requestedId: 'baixi9999999999', issuedAt: fixture.capturedAt);
      final card = LiveRoom(platform: 'kuaishou', roomId: 'baixi9999999999', title: '今晚冲王者');
      final entered = detail.fillFromDetail(card);
      expect(entered.title, '今晚冲王者', reason: "the card's broadcast title, not the bio");
      expect(entered.introduction, detail.introduction, reason: 'the bio stays in the room information');
      expect(entered.nick, detail.nick, reason: "the page's name wins over an empty card one");
      final refreshed = entered.mergeFrom(
        KuaishouApi.roomDetail(
          fixture.body,
          requestedId: 'baixi9999999999',
          issuedAt: fixture.capturedAt,
          withStreams: false,
        ),
      );
      expect(refreshed.title, '今晚冲王者', reason: 'the 60 s room refresh and the follow refresh keep it');
      expect(detail.fillFromDetail(null).title, isEmpty, reason: 'a link without a card has no title');
    });
  });
}
