// v4 Kuaishou parsing against the recorded samples, compared with the legacy
// parser's frozen output. Deviations the spec requires are asserted explicitly.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _load(String sample) => Fixture.load('kuaishou', sample);

Map<String, dynamic> _data(Fixture fixture) =>
    (jsonDecode(fixture.body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;

/// The raw cards of a list sample in server order (home/list flattened).
List<Map<String, dynamic>> _rawCards(Fixture fixture) {
  final data = _data(fixture);
  if (fixture.url.path.endsWith('home/list')) {
    return [
      for (final group in (data['list'] as List).cast<Map<String, dynamic>>())
        for (final sub in (group['gameLiveInfo'] as List).cast<Map<String, dynamic>>())
          ...(sub['liveInfo'] as List).cast<Map<String, dynamic>>(),
    ];
  }
  return (data['list'] as List).cast<Map<String, dynamic>>();
}

List<Map<String, dynamic>> _legacyList(Fixture fixture) => (fixture.legacy as List).cast<Map<String, dynamic>>();

/// Legacy LiveRoom.parseAudienceNumber (lib/common/models/live_room.dart:774).
int? _legacyCount(Object? value) {
  final text = value?.toString().trim().toLowerCase() ?? '';
  final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*(亿|万|千|[kwm])?').firstMatch(text.replaceAll(',', ''));
  if (match == null) return null;
  final scale = switch (match.group(2)) {
    '亿' => 100000000,
    '万' || 'w' => 10000,
    '千' || 'k' => 1000,
    'm' => 1000000,
    _ => 1,
  };
  return (double.parse(match.group(1)!) * scale).round();
}

/// Legacy covers append `.jpg` to extensionless screenshot URLs (site:127-133).
/// Both forms serve the same JPEG bytes (checked 2026-09-27), so v4 keeps the
/// platform URL as given (spec §4 “封面”, §12 item 8).
String? _legacyCover(Uri? cover) {
  if (cover == null) return null;
  final text = cover.toString();
  const images = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'avif'};
  return images.contains(text.split('.').last.toLowerCase()) ? text : '$text.jpg';
}

/// The expiry the sample URL carries, decoded by the §6 table: 8 hex digits
/// for tx/ws/hw, 10 decimal digits for ty and the new bd-origin CDN.
int? _signedExpiry(Uri url) {
  final query = url.queryParameters;
  final host = url.host.split('.').first;
  return switch (host) {
    'tx-origin' => int.parse(query['txTime']!, radix: 16),
    'ws-origin' => int.parse(query['wsTime']!, radix: 16),
    'hw-origin' => int.parse(query['hwTime']!, radix: 16),
    'ty-origin' => int.parse(query['ty_Time']!),
    'bd-origin' => int.parse(query['wsTime']!),
    _ => null,
  };
}

void _expectLine(StreamLine line, {required DateTime issuedAt, required String roomId}) {
  expect(line.format, StreamFormat.flv);
  // Card descriptors carry no codec key; the stream name tells (…_GameAvcSdL0,
  // …_ShowAvc…, …_EcAvc…); the bare …_ma1500 names do not, so their codec is unknown.
  final name = line.url.pathSegments.last;
  expect(line.codec, RegExp('_(Game|Show|Ec)Avc').hasMatch(name) ? 'avc' : isNull, reason: name);
  expect(line.lineId, line.url.host);
  expect(line.confirmed, isNull, reason: 'Kuaishou has no confirmation step (§5)');
  expect(line.headers, KuaishouParse.playHeaders(roomId));
  final lease = line.lease!;
  expect(lease.cutsConnection, isFalse);
  if (line.url.host.startsWith('ali-origin')) {
    // auth_key is scrubbed: its embedded expiry is synthetic, only its presence counts.
    expect(lease.expiresAt!.isAfter(issuedAt), isTrue);
  } else {
    expect(lease.expiresAt!.millisecondsSinceEpoch ~/ 1000, _signedExpiry(line.url), reason: line.url.host);
    // Every recorded signature is issue time + 24 h.
    expect(lease.expiresAt!.difference(issuedAt).inSeconds, closeTo(86400, 5), reason: line.url.host);
  }
  expect(lease.expiresAt!.difference(lease.refreshAt), const Duration(minutes: 10));
}

/// Compares v4 qualities and per-quality lines of [playUrls] with the legacy
/// `parsePlayQualities` projection.
void _expectQualitiesMatchLegacy(
  Object? playUrls,
  List<dynamic> legacy, {
  required String roomId,
  required DateTime issuedAt,
}) {
  final expected = legacy.cast<Map<String, dynamic>>();
  final qualities = KuaishouParse.qualities(playUrls);
  expect(qualities.map((q) => q.label), expected.map((q) => q['quality']));
  expect(qualities.map((q) => q.id), expected.map((q) => q['id']));
  expect(qualities.map((q) => q.rank), expected.map((q) => q['sort']));
  if (expected.isEmpty) {
    expect(
      () => KuaishouParse.streams(playUrls, roomId: roomId, issuedAt: issuedAt),
      throwsA(isA<StreamUnavailable>()),
    );
    return;
  }
  for (final (index, quality) in qualities.indexed) {
    final set = KuaishouParse.streams(playUrls, roomId: roomId, issuedAt: issuedAt, quality: quality);
    expect(set.qualities, qualities);
    expect(set.selected, quality);
    expect(set.lines.map((l) => l.url.toString()), expected[index]['lines']);
    for (final line in set.lines) {
      expect(line.requested, quality);
      _expectLine(line, issuedAt: issuedAt, roomId: roomId);
    }
  }
  expect(KuaishouParse.streams(playUrls, roomId: roomId, issuedAt: issuedAt).selected, qualities.first);
}

void main() {
  group('S01 category/data', () {
    const names = {'1': '热门', '2': '网游', '3': '单机', '4': '手游', '5': '棋牌', '6': '娱乐', '7': '综合', '8': '文化'};

    test('the eight fixed first-level categories match legacy', () {
      expect({for (final c in KuaishouParse.topCategories) c.id: c.name}, names);
    });

    for (final sample in [
      for (var type = 1; type <= 8; type++) 'S01-category-type$type-p1',
      'S01-category-type1-p2',
      'S01-category-type5-p2',
    ]) {
      test(sample, () {
        final fixture = _load(sample);
        final type = fixture.url.queryParameters['type']!;
        final page = int.parse(fixture.url.queryParameters['page']!);
        final cursor = page == 1 ? null : PageCursor('$page');
        expect(KuaishouParse.categoryUri(type, cursor: cursor), fixture.url);
        final result = KuaishouParse.areaPage(fixture.body, categoryId: type, cursor: cursor);
        final legacy = ((fixture.legacy as Map<String, dynamic>)['getSubCategores'] as List)
            .cast<Map<String, dynamic>>();
        expect(result.items.map((a) => a.id), legacy.map((a) => a['areaId']));
        expect(result.items.map((a) => a.name), legacy.map((a) => a['areaName']));
        expect(result.items.map((a) => a.icon?.toString()), legacy.map((a) => a['areaPic']));
        expect(result.items.map((a) => a.categoryId), legacy.map((a) => a['areaType']));
        expect(legacy.map((a) => a['typeName']).toSet(), {names[type]});
        // Paging follows data.hasMore (§2), not “page has >= size items”.
        expect(result.isLast, _data(fixture)['hasMore'] != true);
        if (!result.isLast) {
          expect(KuaishouParse.categoryUri(type, cursor: result.next).queryParameters['page'], '${page + 1}');
        }
      });
    }

    test('type 1 page 1 points at the recorded page 2 request', () {
      final page1 = KuaishouParse.areaPage(_load('S01-category-type1-p1').body, categoryId: '1');
      expect(KuaishouParse.categoryUri('1', cursor: page1.next), _load('S01-category-type1-p2').url);
    });

    test('a full traversal of type 5 requests the pages legacy requested', () {
      final pages = {
        for (final p in ['1', '2']) p: _load('S01-category-type5-p$p'),
      };
      final legacy = (pages['2']!.legacy as Map<String, dynamic>)['getAllSubCategores'] as Map<String, dynamic>;
      final requested = <String>[];
      final ids = <String>[];
      PageCursor? cursor;
      do {
        final page = KuaishouParse.categoryUri('5', cursor: cursor).queryParameters['page']!;
        requested.add(page);
        final result = KuaishouParse.areaPage(pages[page]!.body, categoryId: '5', cursor: cursor);
        ids.addAll(result.items.map((a) => a.id));
        cursor = result.next;
      } while (cursor != null);
      expect(requested, legacy['requestedPages']);
      expect(ids, legacy['areaIds']);
    });

    test('热门 repeats areas of the other categories, so areas are deduplicated per category only', () {
      final hot = {
        for (final p in ['p1', 'p2'])
          ...KuaishouParse.areaPage(_load('S01-category-type1-$p').body, categoryId: '1').items.map((a) => a.id),
      };
      final others = {
        for (var type = 2; type <= 8; type++)
          ...KuaishouParse.areaPage(
            _load('S01-category-type$type-p1').body,
            categoryId: '$type',
          ).items.map((a) => a.id),
      };
      expect(hot.difference(others), isEmpty, reason: 'every recorded 热门 area also sits in its own category');
    });
  });

  group('S02/S03 area rooms', () {
    for (final sample in [
      'S02-gameboard-p1',
      'S02-gameboard-p2',
      'S03-non-gameboard-p1',
      'S03-non-gameboard-p2',
      'S03-non-gameboard-p2-cursor',
    ]) {
      test(sample, () {
        final fixture = _load(sample);
        final query = fixture.url.queryParameters;
        final page = int.parse(query['page']!);
        final cursor = page == 1 ? null : PageCursor(query['cursor'] == null ? '$page' : '$page:${query['cursor']}');
        final result = KuaishouParse.areaRooms(fixture.body, cursor: cursor);
        final legacy = _legacyList(fixture);
        final raw = _rawCards(fixture);
        final rooms = result.items;
        expect(rooms.map((r) => r.ref.roomId), legacy.map((r) => r['roomId']));
        expect(rooms.map((r) => r.title), legacy.map((r) => r['title']));
        expect(rooms.map((r) => r.anchorName), legacy.map((r) => r['nick']));
        expect(rooms.map((r) => r.area), legacy.map((r) => r['area']));
        expect(rooms.map((r) => r.audience), legacy.map((r) => Audience(online: _legacyCount(r['onlineViewers']))));
        expect(rooms.map((r) => _legacyCover(r.cover)), legacy.map((r) => r['cover']));
        expect(rooms.map((r) => r.cover?.toString()), raw.map((r) => r['poster']));
        expect(rooms.map((r) => r.liveSince?.millisecondsSinceEpoch), raw.map((r) => r['statrtTime']));
        for (final (index, room) in rooms.indexed) {
          // Legacy marks every list card live; a 【回放】 caption is a loop room (replay).
          expect(legacy[index]['status'], isTrue);
          expect(room.state, room.title.startsWith('【回放】') ? LiveState.replay : LiveState.live);
          expect(legacy[index]['link'], raw[index]['id'], reason: 'liveStreamId is not the room id (§1)');
          _expectQualitiesMatchLegacy(
            raw[index]['playUrls'],
            legacy[index]['qualities'] as List,
            roomId: room.ref.roomId,
            issuedAt: fixture.capturedAt,
          );
        }
        expect(result.isLast, isFalse, reason: 'every recorded page says hasMore: true');
      });
    }

    test('gameboard page 1 points at the recorded page 2 request (no cursor on gameboard)', () {
      final page1 = KuaishouParse.areaRooms(_load('S02-gameboard-p1').body);
      expect(page1.next, const PageCursor('2'));
      expect(KuaishouParse.areaRoomsUri('1001', cursor: page1.next), _load('S02-gameboard-p2').url);
      expect(KuaishouParse.areaRoomsUri('1001'), _load('S02-gameboard-p1').url);
    });

    test('non-gameboard page 2 carries data.cursor (REG-KUAISHOU-022; legacy repeated page 1)', () {
      final page1 = KuaishouParse.areaRooms(_load('S03-non-gameboard-p1').body);
      expect(page1.next, const PageCursor('2:610_950484466'));
      expect(KuaishouParse.areaRoomsUri('1000004'), _load('S03-non-gameboard-p1').url);
      expect(KuaishouParse.areaRoomsUri('1000004', cursor: page1.next), _load('S03-non-gameboard-p2-cursor').url);
      // The legacy request (no cursor) got page 1 again; the real page 2 is disjoint.
      final ids = page1.items.map((r) => r.ref).toSet();
      final legacyPage2 = KuaishouParse.areaRooms(_load('S03-non-gameboard-p2').body, cursor: const PageCursor('2'));
      expect(legacyPage2.items.map((r) => r.ref).toSet(), ids);
      final realPage2 = KuaishouParse.areaRooms(_load('S03-non-gameboard-p2-cursor').body, cursor: page1.next);
      expect(realPage2.items.map((r) => r.ref).toSet().intersection(ids), isEmpty);
      expect(realPage2.next, const PageCursor('3:257_1252287100'));
    });

    test('the KPL 【回放】 card is replay, all other cards live', () {
      final rooms = KuaishouParse.areaRooms(_load('S02-gameboard-p1').body).items;
      final replay = rooms.where((r) => r.state == LiveState.replay).toList();
      expect(replay.map((r) => r.ref.roomId), ['KPL704668133']);
      expect(replay.single.title, '【回放】2026KPL夏季赛精彩赛事集锦');
    });

    test('new CDNs: bd-origin wsTime is decimal, ali-origin expiry comes from auth_key', () {
      final hosts = <String>{};
      for (final sample in ['S02-gameboard-p2', 'S03-non-gameboard-p1', 'S03-non-gameboard-p2-cursor']) {
        final fixture = _load(sample);
        for (final card in _rawCards(fixture)) {
          final set = KuaishouParse.streams(card['playUrls'], roomId: 'x', issuedAt: fixture.capturedAt);
          for (final line in set.lines) {
            hosts.add(line.url.host.split('.').first);
            _expectLine(line, issuedAt: fixture.capturedAt, roomId: 'x');
          }
        }
      }
      expect(hosts, containsAll(['tx-origin', 'ws-origin', 'ty-origin', 'bd-origin', 'ali-origin']));
    });

    test('2K and 蓝光 tiers keep their platform names and levels', () {
      final raw = _rawCards(_load('S02-gameboard-p1')).firstWhere((c) => (c['author'] as Map)['id'] == 'tingan666');
      expect(KuaishouParse.qualities(raw['playUrls']).map((q) => '${q.label}/${q.rank}'), [
        '2K/250',
        '蓝光 质臻/130',
        '蓝光 4M/70',
        '超清/50',
        '高清/30',
      ]);
    });
  });

  test('S04 home list: one card per streamer, cover poster, title caption (REG-KUAISHOU-017)', () {
    final fixture = _load('S04-home-list');
    final result = KuaishouParse.recommended(fixture.body);
    final legacy = _legacyList(fixture);
    final raw = _rawCards(fixture);
    expect(result.isLast, isTrue);
    expect(legacy, hasLength(48));
    expect(raw, hasLength(48));
    // Legacy lists mnxfsj666888 twice (热推直播 and 手游直播); v4 keeps the first.
    final firstIndex = <String, int>{};
    for (final (index, card) in legacy.indexed) {
      firstIndex.putIfAbsent(card['roomId'] as String, () => index);
    }
    final kept = firstIndex.values.toList();
    expect(result.items, hasLength(47));
    expect(result.items.map((r) => r.ref.roomId), kept.map((i) => legacy[i]['roomId']));
    expect(result.items.map((r) => r.anchorName), kept.map((i) => legacy[i]['nick']));
    expect(result.items.map((r) => r.area), kept.map((i) => legacy[i]['area']));
    expect(result.items.map((r) => r.audience.online), kept.map((i) => _legacyCount(legacy[i]['onlineViewers'])));
    for (final (position, room) in result.items.indexed) {
      final index = kept[position];
      final card = raw[index];
      // Legacy took the area poster as cover and the streamer bio as title.
      expect(legacy[index]['cover'], (card['gameInfo'] as Map)['poster']);
      expect(room.cover?.toString(), card['poster']);
      expect(room.title, (card['caption'] as String?) ?? '');
      final bio = ((card['author'] as Map)['description'] as String?)?.replaceAll('\n', ' ') ?? '';
      expect(legacy[index]['title'], bio);
      expect(room.state, LiveState.live);
    }
    // Every legacy entry's qualities, including the duplicate.
    for (final (index, card) in raw.indexed) {
      _expectQualitiesMatchLegacy(
        card['playUrls'],
        legacy[index]['qualities'] as List,
        roomId: legacy[index]['roomId'] as String,
        issuedAt: fixture.capturedAt,
      );
    }
  });

  group('search', () {
    test('S06 result 2 is RateLimited, not “no results” (REG-KUAISHOU-015; legacy returned [])', () {
      final fixture = _load('S06-search-author-ratelimited');
      expect(fixture.legacy, isEmpty);
      final keyword = fixture.url.queryParameters['keyword']!;
      expect(KuaishouParse.searchUri(keyword), fixture.url);
      expect(
        () => KuaishouParse.searchPage(fixture.body),
        throwsA(isA<RateLimited>().having((e) => e.detail, 'detail', contains('操作太快'))),
      );
    });

    test('S08 result 10 (anonymous liveStream search gate) is RiskControl; legacy returned []', () {
      final fixture = _load('S08-search-livestream-busy');
      expect(fixture.legacy, isEmpty);
      expect(() => KuaishouParse.searchPage(fixture.body), throwsA(isA<RiskControl>()));
    });
  });

  group('S09-S12 room page', () {
    Map<String, dynamic> legacyDetail(Fixture fixture) =>
        (fixture.legacy as Map<String, dynamic>)['getRoomDetail'] as Map<String, dynamic>;

    for (final sample in ['S09-room-live', 'S09-room-live-replay']) {
      test('$sample detail', () {
        final fixture = _load(sample);
        final roomId = fixture.url.pathSegments.last;
        expect(KuaishouParse.roomUri(roomId), fixture.url);
        final detail = KuaishouParse.detail(fixture.body, roomId: roomId, status: fixture.status);
        final legacy = legacyDetail(fixture);
        expect(detail.ref, RoomRef('kuaishou', legacy['roomId'] as String));
        expect(detail.card.title, legacy['title']);
        expect(detail.card.anchorName, legacy['nick']);
        expect(detail.avatar?.toString(), legacy['avatar']);
        expect(_legacyCover(detail.card.cover), legacy['cover']);
        expect(detail.card.area, legacy['area']);
        expect(detail.introduction, legacy['introduction']);
        expect(detail.notice, legacy['notice']);
        expect(detail.danmakuKeys, {'liveStreamId': legacy['link']});
        expect(detail.link, fixture.url);
        expect(legacy['status'], isTrue);
        expect(detail.state, LiveState.live);
        // Legacy showed gameInfo.watchingCount (an area figure, “1万+”) as the
        // room's online count; the page has no room-level measure (REG-KUAISHOU-016).
        expect(legacy['onlineViewers'], '1万+');
        expect(detail.card.audience.isEmpty, isTrue);
        // The refresh path gave the same room.
        final refresh = (fixture.legacy as Map<String, dynamic>)['getRoomDetailForRefresh'] as Map<String, dynamic>;
        expect(refresh['roomId'], legacy['roomId']);
        expect(refresh['status'], isTrue);
      });

      test('$sample streams', () {
        final fixture = _load(sample);
        final roomId = fixture.url.pathSegments.last;
        final legacy = (fixture.legacy as Map<String, dynamic>)['parsePlayQualities'] as List;
        final set = KuaishouParse.roomStreams(fixture.body, roomId: roomId, issuedAt: fixture.capturedAt);
        expect(set.qualities.map((q) => q.id), legacy.map((q) => (q as Map)['id']));
        final state = KuaishouParse.initialState(fixture.body);
        final room = ((state['liveroom'] as Map)['playList'] as List).first as Map;
        final playUrls = (room['liveStream'] as Map)['playUrls'];
        expect((playUrls as Map)['hevc'], isEmpty);
        _expectQualitiesMatchLegacy(playUrls, legacy, roomId: roomId, issuedAt: fixture.capturedAt);
      });
    }

    test('S09 loop room: live on the page, replay with the card’s 【回放】 caption', () {
      final card = KuaishouParse.areaRooms(_load('S02-gameboard-p1').body).items
          .firstWhere((r) => r.ref.roomId == 'KPL704668133');
      final fixture = _load('S09-room-live-replay');
      final detail = KuaishouParse.detail(fixture.body, roomId: 'KPL704668133', cardTitle: card.title);
      expect(detail.state, LiveState.replay);
      expect(detail.card.title, card.title, reason: 'the card caption wins over the bio (§4 标题)');
      // An ordinary caption keeps the room live.
      final live = KuaishouParse.detail(_load('S09-room-live').body, roomId: 'baixi9999999999', cardTitle: '才艺白希营业啦');
      expect(live.state, LiveState.live);
      expect(live.card.title, '才艺白希营业啦');
    });

    test('S11 offline room is offline without cover or liveStreamId (REG-KUAISHOU-020; legacy threw TypeError)', () {
      final fixture = _load('S11-room-offline');
      final legacy = fixture.legacy as Map<String, dynamic>;
      expect((legacy['getRoomDetailForRefresh'] as Map)['throws'], 'TypeError');
      // Legacy getRoomDetail swallowed the error into an “unknown state” room (liveStatus 3).
      expect(legacyDetail(fixture)['liveStatus'], 3);
      final detail = KuaishouParse.detail(fixture.body, roomId: 'tianci666');
      expect(detail.state, LiveState.offline);
      expect(detail.ref.roomId, 'tianci666');
      expect(detail.card.anchorName, 'CHEN天赐〽️王者荣耀');
      expect(detail.card.title, '每晚9点左右直播. 商务：Martin8765');
      expect(detail.card.cover, isNull);
      expect(detail.card.area, isNull);
      expect(detail.card.audience.isEmpty, isTrue, reason: 'offline is empty, not 0 (§4 人数)');
      expect(detail.avatar, isNotNull);
      expect(detail.danmakuKeys, isEmpty);
      expect(
        () => KuaishouParse.roomStreams(fixture.body, roomId: 'tianci666', issuedAt: fixture.capturedAt),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('S11 state is cut by JSON structure: “undefined” inside a string stays (REG-KUAISHOU-018)', () {
      final state = KuaishouParse.initialState(_load('S11-room-offline').body);
      final room = ((state['liveroom'] as Map)['playList'] as List).first as Map;
      // Legacy replaced every “undefined”, turning this URL into …/live/null.
      expect((room['liveStream'] as Map)['url'], 'https://m.gifshow.com/fw/live/undefined');
      expect(room.containsKey('authToken') && room['authToken'] == null, isTrue);
      expect((room['status'] as Map)['forbiddenState'], 671);
    });

    test('S12 errorType 22 is NotFound (legacy threw TypeError / returned an unknown-state room)', () {
      final fixture = _load('S12-room-notfound');
      expect(((fixture.legacy as Map<String, dynamic>)['getRoomDetailForRefresh'] as Map)['throws'], 'TypeError');
      expect(legacyDetail(fixture)['liveStatus'], 3);
      expect(
        () => KuaishouParse.detail(fixture.body, roomId: 'purelive_fixture_404'),
        throwsA(isA<NotFound>().having((e) => e.detail, 'detail', contains('22'))),
      );
      expect(
        () => KuaishouParse.roomStreams(fixture.body, roomId: 'purelive_fixture_404', issuedAt: fixture.capturedAt),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('rules without samples', () {
    Map<String, dynamic> representation(String name, int level, String url) => {
      'name': name,
      'level': level,
      'bitrate': level * 30,
      'url': url,
    };
    Map<String, dynamic> descriptor(List<Map<String, dynamic>> representations) => {
      'adaptationSet': {'representation': representations},
    };
    const avc = 'https://tx-origin.pull.yximgs.com/gifshow/abcdefghijk_GameAvcHdL0.flv?txTime=6aba3f2e';
    const hevc = 'https://ws-origin.pull.yximgs.com/gifshow/abcdefghijk_GameHevcHdL0.flv?wsTime=6aba3f2e';
    final issuedAt = DateTime.utc(2026, 9, 27, 10, 19, 26);

    String roomPage(Map<String, dynamic> room) =>
        '<html><script>window.__INITIAL_STATE__=${jsonEncode({
          'liveroom': {
            'playList': [room],
          },
        })};(function(){var s;})();</script></html>';

    test('room page {h264: {}, hevc: …} falls back to HEVC and says so', () {
      final set = KuaishouParse.streams(
        {
          'h264': <String, dynamic>{},
          'hevc': descriptor([representation('超清', 50, hevc)]),
        },
        roomId: 'r',
        issuedAt: issuedAt,
      );
      expect(set.lines.single.codec, 'hevc');
      expect(set.qualities.single.label, '超清');
    });

    test('H.264 wins over HEVC, within a descriptor and across descriptors (REG-KUAISHOU-002)', () {
      final both = {
        'h264': descriptor([representation('超清', 50, avc)]),
        'hevc': descriptor([representation('超清', 50, hevc), representation('蓝光', 70, hevc)]),
      };
      expect(KuaishouParse.qualities(both).map((q) => q.label), ['超清']);
      // Two bare descriptors of the same tiers: legacy merged the HEVC URL in as
      // a second line; v4 drops it, so no tier mixes codecs.
      final set = KuaishouParse.streams(
        [
          descriptor([representation('超清', 50, avc)]),
          descriptor([representation('超清', 50, hevc)]),
        ],
        roomId: 'r',
        issuedAt: issuedAt,
      );
      expect(set.lines.map((l) => l.url.toString()), [avc]);
      expect(set.lines.single.codec, 'avc');
    });

    test('descriptors of one tier merge into distinct lines; duplicates and non-http URLs drop (REG-KUAISHOU-003)', () {
      const second = 'https://tx-origin.pull.yximgs.com/gifshow/abcdefghijk_GameAvcHdL0.flv?txTime=6aba3f2f&n=2';
      const third = 'https://hw-origin.pull.yximgs.com/gifshow/abcdefghijk_GameAvcHdL0.flv?hwTime=6aba3f2f';
      final set = KuaishouParse.streams(
        [
          descriptor([representation('超清', 50, avc), representation('高清', 30, 'rtmp://x/y')]),
          {
            'representation': [
              representation('超清', 50, avc),
              representation('超清', 50, second),
              representation('超清', 50, third),
              representation('原画', 90, '/relative.flv'),
            ],
          },
        ],
        roomId: 'r',
        issuedAt: issuedAt,
      );
      expect(set.qualities.map((q) => q.label), ['超清']);
      expect(set.lines.map((l) => l.url.toString()), [avc, second, third]);
      expect(set.lines.map((l) => l.lineId), [
        'tx-origin.pull.yximgs.com',
        'tx-origin.pull.yximgs.com#2',
        'hw-origin.pull.yximgs.com',
      ]);
      expect(set.lines.last.lease!.expiresAt!.millisecondsSinceEpoch ~/ 1000, 0x6aba3f2f);
    });

    test('names fall back to shortName, qualityType and 清晰度 {sort}; sort = level ?? bitrate ?? 0', () {
      final qualities = KuaishouParse.qualities(
        descriptor([
          {'shortName': '4M', 'bitrate': 4000, 'url': '$avc&a=1'},
          {'qualityType': 'STANDARD', 'level': 30, 'url': '$avc&a=2'},
          {'qualityType': 'WQHD_2K', 'level': 250, 'url': '$avc&a=3'},
          {'url': '$avc&a=4'},
        ]),
      );
      expect(qualities.map((q) => '${q.label}/${q.rank}'), ['4M/4000', '2K/250', '高清/30', '清晰度 0/0']);
      expect(qualities.map((q) => q.id), ['4M\u00004000', 'WQHD_2K\u0000250', 'STANDARD\u000030', '清晰度 0\u00000']);
    });

    test('no playable representation is StreamUnavailable', () {
      for (final playUrls in <Object?>[
        null,
        <String, dynamic>{'h264': <String, dynamic>{}, 'hevc': <String, dynamic>{}},
        [descriptor([])],
      ]) {
        expect(
          () => KuaishouParse.streams(playUrls, roomId: 'r', issuedAt: issuedAt),
          throwsA(isA<StreamUnavailable>()),
          reason: '$playUrls',
        );
      }
    });

    test('a quality that is not offered falls to the next lower tier', () {
      final playUrls = descriptor([representation('高清', 30, '$avc&q=30'), representation('蓝光', 70, '$avc&q=70')]);
      Quality pick(int rank) => KuaishouParse.streams(
        playUrls,
        roomId: 'r',
        issuedAt: issuedAt,
        quality: Quality(id: 'gone', label: 'x', rank: rank),
      ).selected;
      expect(pick(130).label, '蓝光');
      expect(pick(50).label, '高清');
      expect(pick(10).label, '高清');
    });

    test('play headers: lower-case, room referer, cookie only when configured, no line breaks', () {
      expect(KuaishouParse.playHeaders(null), {
        'user-agent': contains('Chrome/140.0.0.0'),
        'origin': 'https://live.kuaishou.com',
        'referer': 'https://live.kuaishou.com/',
      });
      final headers = KuaishouParse.playHeaders('ATM-Heros', userCookie: ' did=1;\r\n kpn=GAME ');
      expect(headers['referer'], 'https://live.kuaishou.com/u/ATM-Heros');
      expect(headers['cookie'], 'did=1; kpn=GAME');
      expect(headers.keys.every((k) => k == k.toLowerCase()), isTrue);
      expect(KuaishouParse.playHeaders('x', userCookie: '  ').containsKey('cookie'), isFalse);
    });

    test('lease: hex and decimal times, auth_key, nothing recognisable, already expired', () {
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
        final lease = KuaishouParse.lease(Uri.parse('https://cdn.test/a.flv?$query'), issued)!;
        expect(lease.expiresAt, issued.add(const Duration(hours: 24)), reason: query);
        expect(lease.refreshAt, issued.add(const Duration(hours: 23, minutes: 50)), reason: query);
        expect(lease.cutsConnection, isFalse);
      }
      expect(KuaishouParse.lease(Uri.parse('https://cdn.test/a.flv?stat=1'), issued), isNull);
      final past = (issued.millisecondsSinceEpoch ~/ 1000 - 60).toRadixString(16);
      expect(KuaishouParse.lease(Uri.parse('https://cdn.test/a.flv?txTime=$past'), issued), isNull);
      // A short lifetime refreshes a quarter of it early.
      final soon = (issued.millisecondsSinceEpoch ~/ 1000 + 400).toRadixString(16);
      final short = KuaishouParse.lease(Uri.parse('https://cdn.test/a.flv?txTime=$soon'), issued)!;
      expect(short.expiresAt!.difference(short.refreshAt), const Duration(seconds: 100));
    });

    test('isLiving accepts true, 1 and "true" in any case (REG-KUAISHOU-007)', () {
      for (final value in <Object?>[true, 1, 'true', 'TRUE']) {
        final page = roomPage({
          'isLiving': value,
          'author': {'id': 'abc'},
          'liveStream': <String, dynamic>{},
        });
        expect(KuaishouParse.detail(page, roomId: 'abc').state, LiveState.live, reason: '$value');
      }
      for (final value in <Object?>[false, 0, 'false', null]) {
        final page = roomPage({
          'isLiving': value,
          'author': {'id': 'abc'},
        });
        expect(KuaishouParse.detail(page, roomId: 'abc').state, LiveState.offline, reason: '$value');
      }
    });

    test('author.id missing falls back to the requested id', () {
      final detail = KuaishouParse.detail(roomPage({'isLiving': false, 'author': <String, dynamic>{}}), roomId: 'abc');
      expect(detail.ref, RoomRef('kuaishou', 'abc'));
      expect(detail.link, Uri.parse('https://live.kuaishou.com/u/abc'));
    });

    test('other errorType values are RiskControl with type and title; cookie suspect when a user cookie was sent', () {
      final page = roomPage({
        'isLiving': false,
        'errorType': {'type': 31, 'title': '错误代码31'},
      });
      expect(
        () => KuaishouParse.detail(page, roomId: 'abc', userCookie: true),
        throwsA(
          isA<RiskControl>()
              .having((e) => e.cookieSuspect, 'cookieSuspect', isTrue)
              .having((e) => e.detail, 'detail', allOf(contains('31'), contains('错误代码31'))),
        ),
      );
    });

    test('state extraction: “;” inside strings, bare undefined, missing state, captcha page', () {
      const html =
          r'<script>window.__INITIAL_STATE__ = {"a":"x;y}","b":undefined,"c":["undefinedX",undefined],"d":"q\"undefined","liveroom":{"playList":[]}};(function(){})();</script>';
      final state = KuaishouParse.initialState(html);
      expect(state['a'], 'x;y}');
      expect(state.containsKey('b') && state['b'] == null, isTrue);
      expect(state['c'], ['undefinedX', null]);
      expect(state['d'], 'q"undefined');
      expect(() => KuaishouParse.detail(html, roomId: 'abc'), throwsA(isA<ApiChanged>()));
      expect(
        () => KuaishouParse.detail('<html><div id="captcha">请完成安全验证</div></html>', roomId: 'abc'),
        throwsA(isA<RiskControl>()),
      );
      expect(() => KuaishouParse.detail('<html>maintenance</html>', roomId: 'abc'), throwsA(isA<ApiChanged>()));
      expect(() => KuaishouParse.initialState('<script>window.__INITIAL_STATE__={"a":1'), throwsA(isA<ApiChanged>()));
    });

    test('HTTP status: 429 RateLimited, 5xx NetworkFailure, 403 RiskControl', () {
      expect(() => KuaishouParse.detail('', roomId: 'a', status: 429), throwsA(isA<RateLimited>()));
      expect(() => KuaishouParse.areaRooms('', status: 502), throwsA(isA<NetworkFailure>()));
      expect(() => KuaishouParse.recommended('', status: 403), throwsA(isA<RiskControl>()));
    });

    test('author search maps living, banned and empty ids; audience stays empty (REG-KUAISHOU-010)', () {
      final body = jsonEncode({
        'data': {
          'type': 'authors',
          'result': 1,
          'ussid': 'dXNzaWQ=',
          'list': [
            {
              'id': 'tianci666',
              'name': 'A',
              'avatar': 'https://p.test/a.jpg',
              'living': true,
              'counts': {'fan': '2960.4w', 'follow': '12'},
            },
            {'id': '', 'name': 'skipped'},
            {
              'id': 'ATM-Heros',
              'name': 'B',
              'living': true,
              'bannedStatus': {'banned': true},
            },
            {'id': '3xgw4a6r5eiu4nu', 'name': 'C', 'living': false},
          ],
        },
      });
      final page = KuaishouParse.searchPage(body);
      expect(page.items.map((r) => r.ref.roomId), ['tianci666', 'ATM-Heros', '3xgw4a6r5eiu4nu']);
      expect(page.items.map((r) => r.state), [LiveState.live, LiveState.offline, LiveState.offline]);
      expect(page.items.first.title, 'A');
      expect(page.items.first.cover, Uri.parse('https://p.test/a.jpg'));
      expect(page.items.every((r) => r.audience.isEmpty), isTrue);
      expect(page.items.map((r) => r.followers), [29604000, null, null], reason: '`counts.fan` with units');
      expect(page.next, const PageCursor('2:dXNzaWQ='));
      expect(KuaishouParse.searchUri('王者', cursor: page.next).queryParameters, {
        'keyword': '王者',
        'page': '2',
        'lssid': 'dXNzaWQ=',
      });
    });

    test('author search: result 1 with an empty list is the end; unknown shapes are ApiChanged', () {
      final empty = KuaishouParse.searchPage('{"data":{"result":1,"list":[]}}', cursor: const PageCursor('4'));
      expect(empty.items, isEmpty);
      expect(empty.isLast, isTrue);
      for (final body in ['{"data":{"result":1}}', '{"data":{"result":3}}', '{"data":{}}', '<html>']) {
        expect(() => KuaishouParse.searchPage(body), throwsA(isA<ApiChanged>()), reason: body);
      }
    });

    test('catalog answers with result 2 are RateLimited; missing lists are ApiChanged', () {
      const limited = '{"data":{"result":2,"error_msg":"操作太快了，请稍微休息一下"}}';
      expect(() => KuaishouParse.areaPage(limited, categoryId: '1'), throwsA(isA<RateLimited>()));
      expect(() => KuaishouParse.areaRooms('{"data":{"hasMore":true}}'), throwsA(isA<ApiChanged>()));
      expect(() => KuaishouParse.recommended('{"data":null}'), throwsA(isA<ApiChanged>()));
    });

    test('list cards: a missing poster or caption does not fail the page; counts with units (REG-KUAISHOU-020)', () {
      Map<String, dynamic> card(String id, Object? watching) => {
        'id': 'L$id',
        'author': {'id': id, 'name': id},
        'watchingCount': watching,
      };
      final body = jsonEncode({
        'data': {
          'hasMore': false,
          'list': [
            card('a', '1.0万'),
            card('b', '10万+'),
            card('c', '2.5w'),
            card('d', '1,234'),
            card('e', 38),
            card('f', null),
            {'id': 'Lx', 'author': <String, dynamic>{}},
          ],
        },
      });
      final page = KuaishouParse.areaRooms(body);
      expect(page.isLast, isTrue);
      expect(page.items.map((r) => r.audience.online), [10000, 100000, 25000, 1234, 38, null]);
      expect(page.items.every((r) => r.cover == null && r.title.isEmpty), isTrue);
    });

    test('hasMore with an empty page ends the list instead of looping', () {
      expect(KuaishouParse.areaRooms('{"data":{"hasMore":true,"list":[],"cursor":"1_2"}}').isLast, isTrue);
    });

    test('cursors from other adapters are rejected', () {
      expect(() => KuaishouParse.areaRoomsUri('1001', cursor: const PageCursor('x')), throwsArgumentError);
    });
  });
}
