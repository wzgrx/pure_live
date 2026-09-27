// v4 Douyin parsing against the recorded samples, compared with the legacy
// parser's frozen output. Deviations the spec (or DIAGNOSIS) requires are
// asserted explicitly.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _load(String sample) => Fixture.load('douyin', sample);

void main() {
  test('S01 categories match legacy ids, names and areas (each category lists itself first)', () {
    final fixture = _load('S01-home');
    final categories = DouyinParse.categories(fixture.body, status: fixture.status, headers: _headers(fixture));
    final legacy = fixture.legacy as Map<String, dynamic>;
    expect(legacy['categoryDataFound'], isTrue);
    final expected = (legacy['categories'] as List).cast<Map<String, dynamic>>();
    expect(categories.map((c) => c.id), expected.map((c) => c['id']));
    expect(categories.map((c) => c.name), expected.map((c) => c['name']));
    for (final (index, category) in categories.indexed) {
      final areas = (expected[index]['children'] as List).cast<Map<String, dynamic>>();
      expect(category.areas.map((a) => a.id), areas.map((a) => a['areaId']));
      expect(category.areas.map((a) => a.name), areas.map((a) => a['areaName']));
      expect(category.areas.map((a) => a.categoryId), areas.map((a) => a['areaType']));
      expect(category.areas.first.id, category.id);
    }
    expect(DouyinParse.partitionParams('1,1'), {'partition': '1', 'partition_type': '1'});
  });

  group('S02 feed', () {
    final fixture = _load('S02-feed');
    final legacy = fixture.legacy as Map<String, dynamic>;
    final rooms = _rawRooms(fixture);

    test('cards match legacy; one page; area and audience follow the spec', () {
      final page = DouyinParse.feed(fixture.body, status: fixture.status, headers: _headers(fixture));
      final expected = (legacy['rooms'] as List).cast<Map<String, dynamic>>();
      _expectCards(page.items, expected, rooms);
      expect(page.items.every((r) => r.state == LiveState.live), isTrue);
      // Spec §2: the feed takes no offset, so there is no next page (even
      // though extra.has_more is true).
      expect(page.isLast, isTrue);
      // Spec §2: without tag_name/partition_road_map/tags the legacy wrote
      // the UI copy "热门推荐"; v4 reports no area.
      expect(expected.map((r) => r['area']).toSet(), {'热门推荐'});
      expect(page.items.map((r) => r.area).toSet(), {null});
    });

    test('qualities and lines of every room match legacy', () {
      final streams = legacy['streams'] as Map<String, dynamic>;
      expect(streams.keys, rooms.keys);
      for (final MapEntry(key: webRid, value: room) in rooms.entries) {
        final expected = ((streams[webRid] as Map<String, dynamic>)['qualities'] as List).cast<Map<String, dynamic>>();
        _expectStreams(room['stream_url'] as Map<String, dynamic>, expected, fixture.capturedAt, webRid);
      }
    });

    test('codec: sdk_params.VCodec and options v_codec agree; HEVC rooms exist', () {
      final codecs = <String?>{};
      for (final MapEntry(key: webRid, value: room) in rooms.entries) {
        final streamUrl = room['stream_url'] as Map<String, dynamic>;
        final pull = (streamUrl['live_core_sdk_data'] as Map<String, dynamic>)['pull_data'] as Map<String, dynamic>;
        final options = {
          for (final q
              in ((pull['options'] as Map<String, dynamic>?)?['qualities'] as List? ?? const [])
                  .cast<Map<String, dynamic>>())
            q['sdk_key']: q['v_codec'],
        };
        for (final quality in DouyinParse.qualities(streamUrl)) {
          final codec = DouyinParse.streams(
            streamUrl,
            issuedAt: fixture.capturedAt,
            webRid: webRid,
            quality: quality.id,
          ).lines.first.codec;
          codecs.add(codec);
          final option = options[quality.id];
          if (option == null) continue;
          expect(codec, option == '264' ? 'avc' : 'hevc', reason: '$webRid ${quality.id} v_codec $option');
        }
      }
      expect(codecs, containsAll(['avc', 'hevc']));
    });
  });

  group('S03 partition rooms', () {
    for (final (sample, next) in [
      ('S03-partition-p1', '15'),
      ('S03-partition-p2', '30'),
      ('S03-partition-empty', null),
    ]) {
      test('$sample matches legacy; the cursor is data.offset', () {
        final fixture = _load(sample);
        final offset = int.parse(fixture.url.queryParameters['offset']!);
        final page = DouyinParse.partitionRooms(
          fixture.body,
          offset: offset,
          status: fixture.status,
          headers: _headers(fixture),
        );
        final expected = ((fixture.legacy as Map<String, dynamic>)['rooms'] as List).cast<Map<String, dynamic>>();
        _expectCards(page.items, expected, _rawRooms(fixture));
        expect(page.items.map((r) => r.area), expected.map((r) => r['area']));
        // Ends by data.count == 0 (the empty page reports offset 0), never by item count.
        expect(page.next?.value, next);
      });
    }
  });

  group('S04 enter', () {
    for (final sample in ['S04-enter-live', 'S04-enter-live-portrait', 'S04-enter-offline']) {
      test('$sample detail and qualities match legacy', () {
        final fixture = _load(sample);
        final webRid = fixture.url.queryParameters['web_rid']!;
        final room = DouyinParse.enter(
          fixture.body,
          webRid: webRid,
          status: fixture.status,
          headers: _headers(fixture),
        );
        final legacy = fixture.legacy as Map<String, dynamic>;
        expect(legacy['requests'], ['GET live.douyin.com/webcast/room/web/enter/']);
        final raw = ((jsonDecode(fixture.body) as Map)['data'] as Map)['data'] as List;
        _expectDetail(room, legacy['room'] as Map<String, dynamic>, raw.first as Map<String, dynamic>);
        _expectStreamsOrNone(room, legacy, fixture.capturedAt);
      });
    }

    test('S04 offline: status 4 with data.room_status 2; anchor from data.user; no audience', () {
      final fixture = _load('S04-enter-offline');
      final room = DouyinParse.enter(fixture.body, webRid: '745964462470');
      expect(room.detail.state, LiveState.offline);
      expect(room.detail.card.anchorName, '喜剧电影笑不停');
      expect(room.detail.card.audience, Audience.none);
      expect(room.streamUrl, isNull);
      expect(
        () => DouyinParse.streams(room.streamUrl, issuedAt: fixture.capturedAt),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('S04 portrait: the default quality is origin; lines carry headers, codec and a 7-day lease', () {
      final fixture = _load('S04-enter-live-portrait');
      final room = DouyinParse.enter(fixture.body, webRid: '153806988623');
      expect(DouyinParse.defaultQuality(room.streamUrl!), 'origin');
      final set = DouyinParse.streams(room.streamUrl, issuedAt: fixture.capturedAt, webRid: '153806988623');
      expect(set.selected.id, 'origin');
      expect(set.lines.map((l) => (l.format, l.lineId)), [(StreamFormat.flv, 'flv'), (StreamFormat.hls, 'hls')]);
      for (final line in set.lines) {
        expect(line.headers, {
          'user-agent': DouyinParse.userAgent,
          'origin': 'https://live.douyin.com',
          'referer': 'https://live.douyin.com/153806988623',
        });
        expect(line.codec, 'avc');
        expect(line.confirmed, isNull);
        expect(line.lease!.cutsConnection, isFalse);
        expect(line.lease!.expiresAt!.difference(fixture.capturedAt).inMinutes, closeTo(7 * 24 * 60, 1));
      }
      // FULL_HD1 is the same stream as origin; asking for it plays origin.
      expect(
        DouyinParse.streams(room.streamUrl, issuedAt: fixture.capturedAt, quality: 'FULL_HD1').selected.id,
        'origin',
      );
    });

    test('S04 not found (4001038) is NotFound; legacy fell back to HTML and failed on HEAD', () {
      final fixture = _load('S04-enter-notfound');
      expect(((fixture.legacy as Map<String, dynamic>)['error'] as Map<String, dynamic>)['type'], 'HttpError');
      expect(
        () => DouyinParse.enter(fixture.body, webRid: '999999999999', status: fixture.status),
        throwsA(isA<NotFound>()),
      );
    });

    test('S04 empty 200 without ttwid is RiskControl (spec §9); legacy failed on HEAD', () {
      final fixture = _load('S04-enter-no-cookie');
      expect(fixture.body, isEmpty);
      expect(((fixture.legacy as Map<String, dynamic>)['error'] as Map<String, dynamic>)['type'], 'HttpError');
      expect(
        () => DouyinParse.enter(fixture.body, webRid: '547977714661', status: fixture.status),
        throwsA(isA<RiskControl>()),
      );
    });
  });

  group('S05 reflow', () {
    test('S05-reflow-live: identity is owner.web_rid; detail and qualities match legacy', () {
      final fixture = _load('S05-reflow-live');
      final room = DouyinParse.reflow(fixture.body, status: fixture.status, headers: _headers(fixture));
      final legacy = fixture.legacy as Map<String, dynamic>;
      final raw = ((jsonDecode(fixture.body) as Map)['data'] as Map)['room'] as Map<String, dynamic>;
      expect(room.sessionEnded, isFalse);
      _expectDetail(room, legacy['room'] as Map<String, dynamic>, raw);
      _expectStreamsOrNone(room, legacy, fixture.capturedAt);
    });

    test('S05-reflow-shortlink-live resolves to the web_rid legacy returned', () {
      final fixture = _load('S05-reflow-shortlink-live');
      final result = (fixture.legacy as Map<String, dynamic>)['result'] as List;
      expect(DouyinParse.reflow(fixture.body).detail.ref, RoomRef(result[1] as String, result[0] as String));
    });

    test('S05-reflow-ended: status 4 → query enter with owner.web_rid (legacy did the same)', () {
      final fixture = _load('S05-reflow-ended');
      final room = DouyinParse.reflow(fixture.body);
      final legacy = fixture.legacy as Map<String, dynamic>;
      expect(legacy['requests'], [
        'GET webcast.amemv.com/webcast/room/reflow/info/',
        'GET live.douyin.com/webcast/room/web/enter/',
      ]);
      expect(room.sessionEnded, isTrue);
      expect(room.detail.state, LiveState.offline);
      expect(room.detail.ref.roomId, '745964462470');
      final enterFixture = _load('S04-enter-offline');
      final entered = DouyinParse.enter(enterFixture.body, webRid: room.detail.ref.roomId);
      final raw = ((jsonDecode(enterFixture.body) as Map)['data'] as Map)['data'] as List;
      _expectDetail(entered, legacy['room'] as Map<String, dynamic>, raw.first as Map<String, dynamic>);
    });
  });

  group('S06 room page (HTML fallback)', () {
    final fixture = _load('S06-room-html-live');
    final legacy = fixture.legacy as Map<String, dynamic>;
    final legacyRoom = legacy['room'] as Map<String, dynamic>;
    late DouyinRoom room;
    setUpAll(() {
      room = DouyinParse.roomPage(
        fixture.body,
        webRid: '547977714661',
        status: fixture.status,
        headers: _headers(fixture),
      );
    });

    test('detail matches legacy except the spec §4 introduction and the exact online count', () {
      expect(room.detail.ref.roomId, legacyRoom['roomId']);
      expect(room.detail.card.title, legacyRoom['title']);
      expect(room.detail.card.anchorName, legacyRoom['nick']);
      expect(room.detail.avatar.toString(), legacyRoom['avatar']);
      expect(room.detail.card.cover.toString(), legacyRoom['cover']);
      expect(room.detail.state, LiveState.live);
      expect(room.detail.link.toString(), legacyRoom['link']);
      // Spec §4 table: the legacy HTML path filled the introduction with the
      // title; v4 reads owner.signature, which this page does not carry.
      expect(legacyRoom['introduction'], legacyRoom['title']);
      expect(room.detail.introduction, isNull);
      final danmaku = legacyRoom['danmakuData'] as Map<String, dynamic>;
      expect(room.detail.danmakuKeys, {
        'webRid': danmaku['webRid'],
        'roomId': danmaku['roomId'],
        'userUniqueId': danmaku['userId'],
      });
      // DIAGNOSIS "enter 没有 room.user_count 时取分档文本": legacy showed "5000+";
      // v4 takes the exact stats.user_count_str.
      expect(legacyRoom['onlineViewers'], '5000+');
      expect(room.detail.card.audience, const Audience(online: 5562, cumulative: 30574140));
      expect(legacyRoom['totalViewers'], '30574140');
    });

    test(
      r'stream_data "$13" is resolved from the page payload: v4 keeps the stream_data qualities (REG-DOUYIN-018)',
      () {
        // Legacy unescaped the page with string replaces and never resolved the
        // RSC reference, so stream_data failed to decode and only the old
        // FULL_HD1/HD1/SD2/SD1 maps were used (MD was lost).
        final expected = (legacy['qualities'] as List).cast<Map<String, dynamic>>();
        expect(expected.map((q) => q['id']), ['full_hd1', 'hd1', 'sd2', 'sd1']);
        final qualities = DouyinParse.qualities(room.streamUrl!);
        expect(qualities.map((q) => q.id), ['origin', 'hd', 'sd', 'ld', 'md']);
        for (final old in expected) {
          // Each legacy quality is the same stream as one v4 quality (an alias).
          final set = DouyinParse.streams(room.streamUrl, issuedAt: fixture.capturedAt, quality: old['id'] as String);
          expect(set.lines.map((l) => l.url.toString()), old['urls'], reason: '${old['id']} → ${set.selected.id}');
        }
        expect(DouyinParse.defaultQuality(room.streamUrl!), 'origin');
      },
    );
  });

  group('S08 search', () {
    test('S08-live-search-anon: 2483 请先登录 is NeedsLogin; legacy returned no rooms', () {
      final fixture = _load('S08-live-search-anon');
      expect((fixture.legacy as Map<String, dynamic>)['rooms'], isEmpty);
      expect(() => DouyinParse.searchPage(fixture.body, offset: 0, status: fixture.status), throwsA(isA<NeedsLogin>()));
    });

    test('S08-general-search-anon: the chunk-framed body is read; NeedsLogin (legacy: HttpError)', () {
      final fixture = _load('S08-general-search-anon');
      expect(fixture.body, startsWith('5c\r\n'));
      final legacy = fixture.legacy as Map<String, dynamic>;
      expect((legacy['error'] as Map<String, dynamic>)['type'], 'HttpError');
      expect(() => DouyinParse.searchPage(fixture.body, offset: 0, status: fixture.status), throwsA(isA<NeedsLogin>()));
    });

    test('S08-partition-search: matching partitions are areas with the ids legacy requested', () {
      final fixture = _load('S08-partition-search');
      final areas = DouyinParse.partitionSearch(fixture.body, status: fixture.status);
      expect(areas.map((a) => (a.id, a.name)), [('1010032,1', '和平精英')]);
      final requests = ((fixture.legacy as Map<String, dynamic>)['partitionRoomRequests'] as List)
          .cast<Map<String, dynamic>>();
      final params = DouyinParse.partitionParams(areas.single.id);
      for (final request in requests) {
        expect(params, {'partition': request['partition'], 'partition_type': request['partition_type']});
      }
    });

    test('S08-partition-rooms-unsigned: empty 200 + bdturing-verify is RiskControl; legacy saw null data', () {
      final fixture = _load('S08-partition-rooms-unsigned');
      expect((fixture.legacy as Map<String, dynamic>)['data'], isNull);
      expect(_headers(fixture), contains('bdturing-verify'));
      expect(
        () => DouyinParse.partitionRooms(fixture.body, offset: 0, status: fixture.status, headers: _headers(fixture)),
        throwsA(isA<RiskControl>()),
      );
    });

    test('S08-partition-rooms-amemv matches the legacy partition-match result', () {
      final fixture = _load('S08-partition-rooms-amemv');
      final page = DouyinParse.partitionRooms(
        fixture.body,
        offset: 0,
        areaName: '和平精英',
        status: fixture.status,
        headers: _headers(fixture),
      );
      final expected = ((fixture.legacy as Map<String, dynamic>)['rooms'] as List).cast<Map<String, dynamic>>();
      _expectCards(page.items, expected, _rawRooms(fixture));
      // tag_name is empty here; legacy and v4 both label the rooms with the browsed partition.
      expect(page.items.map((r) => r.area), expected.map((r) => r['area']));
      expect(page.next?.value, '20');
    });
  });

  test('S09 user/me 20003 is NeedsLogin; legacy returned the error data as user info', () {
    for (final sample in ['S09-user-me-no-cookie', 'S09-user-me-invalid-cookie']) {
      final fixture = _load(sample);
      final info = (fixture.legacy as Map<String, dynamic>)['info'] as Map<String, dynamic>;
      expect(info['message'], "User doesn't login", reason: sample);
      expect(() => DouyinParse.accountName(fixture.body, status: fixture.status), throwsA(isA<NeedsLogin>()));
    }
  });

  group('rules without samples', () {
    test('§1 a numeric id longer than 16 digits is a room_id', () {
      expect(DouyinParse.isRoomId('7687741736843512602'), isTrue);
      expect(DouyinParse.isRoomId('547977714661'), isFalse);
      expect(DouyinParse.isRoomId('abc'), isFalse);
    });

    test('§4 audience: display_type 1 is online, 3 cumulative, others ignored; cumulative 0 is a placeholder', () {
      Audience audience(Map<String, dynamic> room) => DouyinParse.enter(
        jsonEncode({
          'status_code': 0,
          'data': {
            'data': [
              {'id_str': '7000000000000000001', 'status': 2, 'title': 't', ...room},
            ],
          },
        }),
        webRid: '1',
      ).detail.card.audience;
      expect(
        audience({
          'room_view_stats': {'display_type': 1, 'display_value': 713},
          'stats': {'total_user': 0, 'total_user_str': '2万+'},
        }),
        const Audience(online: 713, cumulative: 20000),
      );
      expect(
        audience({
          'user_count': 0,
          'room_view_stats': {'display_type': 3, 'display_value': 395780},
        }),
        const Audience(online: 0, cumulative: 395780),
      );
      expect(
        audience({
          'user_count_str': '2000+',
          'room_view_stats': {'display_type': 7, 'display_value': 55},
        }),
        const Audience(online: 2000),
      );
    });

    test('§4 enter: an empty room list is NotFound; room_status decides only when status is absent', () {
      String enter(List<Object?> rooms, {Object? roomStatus}) => jsonEncode({
        'status_code': 0,
        'data': {'data': rooms, 'room_status': ?roomStatus},
      });
      expect(() => DouyinParse.enter(enter(const []), webRid: '1'), throwsA(isA<NotFound>()));
      final room = {'id_str': '7000000000000000001', 'title': 't'};
      expect(DouyinParse.enter(enter([room], roomStatus: 0), webRid: '1').detail.state, LiveState.live);
      expect(DouyinParse.enter(enter([room], roomStatus: 2), webRid: '1').detail.state, LiveState.offline);
      expect(() => DouyinParse.enter(enter([room]), webRid: '1'), throwsA(isA<ApiChanged>()));
      expect(
        DouyinParse.enter(
          enter([
            {...room, 'status': '2'},
          ], roomStatus: 2),
          webRid: '1',
        ).detail.state,
        LiveState.live,
      );
    });

    test('§9 HTTP and status_code mapping', () {
      expect(
        () => DouyinParse.feed('{}', status: 429, headers: const {'Retry-After': '30'}),
        throwsA(isA<RateLimited>().having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 30))),
      );
      expect(() => DouyinParse.feed('', status: 503), throwsA(isA<NetworkFailure>()));
      expect(() => DouyinParse.feed('x', status: 403), throwsA(isA<RiskControl>()));
      expect(() => DouyinParse.feed('<html>'), throwsA(isA<RiskControl>()));
      expect(() => DouyinParse.feed('{"status_code": 10011, "data": {}}'), throwsA(isA<ApiChanged>()));
      expect(() => DouyinParse.feed('[]'), throwsA(isA<ApiChanged>()));
      expect(() => DouyinParse.reflow('{"status_code":0,"data":{"room":{"status":2}}}'), throwsA(isA<ApiChanged>()));
      expect(() => DouyinParse.roomPage('<html></html>', webRid: '1'), throwsA(isA<ApiChanged>()));
      expect(() => DouyinParse.categories('<html></html>'), throwsA(isA<ApiChanged>()));
    });

    test('§2 feed: old data.data shape, JSON-string rooms, room_id fallback, dedupe and area tags', () {
      final page = DouyinParse.feed(
        jsonEncode({
          'data': {
            'data': [
              {
                'web_rid': '11',
                'data': jsonEncode({
                  'title': 'a',
                  'owner': {'nickname': 'A'},
                  'partition_road_map': [
                    {'title': '游戏'},
                  ],
                }),
              },
              {
                'web_rid': '0',
                'room': {'id_str': '7000000000000000002', 'title': 'b', 'tag_name': '音乐'},
              },
              {'web_rid': '11', 'title': 'dup', 'owner': <String, dynamic>{}},
              'junk',
            ],
          },
        }),
      );
      expect(page.items.map((r) => (r.ref.roomId, r.title, r.anchorName, r.area)), [
        ('11', 'a', 'A', '游戏'),
        ('7000000000000000002', 'b', '', '音乐'),
      ]);
      expect(page.isLast, isTrue);
    });

    test('§2 partition cursor: stops when count is 0 or the offset does not advance', () {
      String body(int count, int offset) => jsonEncode({
        'status_code': 0,
        'data': {'count': count, 'offset': offset, 'data': const <Object>[]},
      });
      expect(DouyinParse.partitionRooms(body(15, 30), offset: 15).next, const PageCursor('30'));
      expect(DouyinParse.partitionRooms(body(15, 15), offset: 15).isLast, isTrue);
      expect(DouyinParse.partitionRooms(body(0, 45), offset: 30).isLast, isTrue);
    });

    test('§3 search: nested/JSON-string rooms, web_rid else room_id, status 2 live, dedupe, has_more cursor', () {
      final room = {
        'id_str': '7000000000000000003',
        'status': 2,
        'title': 'live',
        'owner': {'web_rid': '22', 'nickname': 'B'},
        'user_count': 5,
        'cover': {
          'url_list': ['https://p.test/c.jpg'],
        },
      };
      final body = jsonEncode({
        'status_code': 0,
        'has_more': 1,
        'cursor': 20,
        'data': [
          {
            'lives': {'rawdata': jsonEncode(room)},
          },
          {
            'aweme_info': {
              'live_info': {
                'rawdata': {'room_id': '7000000000000000004', 'status': 4, 'title': 'ended', 'nickname': 'C'},
              },
            },
          },
          {
            'lives': {'rawdata': jsonEncode(room)},
          },
        ],
      });
      final page = DouyinParse.searchPage(body, offset: 10);
      expect(page.items.map((r) => (r.ref.roomId, r.state, r.anchorName)), [
        ('22', LiveState.live, 'B'),
        ('7000000000000000004', LiveState.offline, 'C'),
      ]);
      expect(page.items.first.audience, const Audience(online: 5));
      expect(page.items.first.cover.toString(), 'https://p.test/c.jpg');
      expect(DouyinParse.isRoomId(page.items.last.ref.roomId), isTrue);
      expect(page.next, const PageCursor('20'));
      expect(DouyinParse.searchPage(body.replaceFirst('"has_more":1', '"has_more":0'), offset: 10).isLast, isTrue);

      // The general search frames documents as hex byte-length chunks.
      final document = jsonEncode({
        'status_code': 0,
        'data': [
          {
            'lives': {'rawdata': jsonEncode(room)},
          },
        ],
      });
      final framed = '${utf8.encode(document).length.toRadixString(16)}\r\n$document\r\n0\r\n\r\n';
      expect(DouyinParse.searchPage(framed, offset: 0).items.single.ref.roomId, '22');
    });

    group('§5 qualities', () {
      Map<String, dynamic> streamUrl({
        List<Map<String, Object?>> options = const [],
        Map<String, Object?> data = const {},
        Map<String, String> flv = const {},
        Map<String, String> hls = const {},
        Map<String, String> names = const {},
      }) => {
        'live_core_sdk_data': {
          'pull_data': {
            'options': {'qualities': options},
            'stream_data': jsonEncode({'data': data}),
          },
        },
        'flv_pull_url': flv,
        'hls_pull_url_map': hls,
        'resolution_name': names,
      };
      Map<String, Object?> main(String name, {String codec = 'h264', String query = ''}) => {
        'main': {
          'flv': 'https://a.test/$name.flv?expire=6ac221a0$query',
          'hls': 'https://a.test/$name.m3u8?expire=6ac221a0$query',
          'sdk_params': jsonEncode({'VCodec': codec}),
        },
      };

      test('audio-only keys and only_audio URLs are excluded; nothing left is StreamUnavailable', () {
        final url = streamUrl(
          data: {
            'ao': main('ao'),
            'x': main('x', query: '&only_audio=1'),
            'md': main('md'),
          },
        );
        expect(DouyinParse.qualities(url).map((q) => q.id), ['md']);
        expect(
          () => DouyinParse.streams(streamUrl(data: {'ao': main('ao')}), issuedAt: DateTime.utc(2026, 9, 27)),
          throwsA(isA<StreamUnavailable>()),
        );
      });

      test('order: semantic tier, then level, then bitrate, then id; bitrate never outranks the tier', () {
        final url = streamUrl(
          options: [
            {'sdk_key': 'origin', 'name': '原画', 'level': 4, 'v_bit_rate': 100},
            {'sdk_key': 'hd', 'name': '超清', 'level': 3, 'v_bit_rate': 4000000},
            {'sdk_key': 'custom', 'name': 'Custom', 'level': 2},
            {'sdk_key': 'zz', 'v_bit_rate': 500},
            {'sdk_key': 'aa', 'v_bit_rate': 500},
          ],
          data: {
            for (final key in ['hd', 'custom', 'origin', 'zz', 'aa']) key: main(key),
          },
        );
        expect(DouyinParse.qualities(url).map((q) => (q.id, q.label)), [
          ('origin', '原画'),
          ('hd', '超清'),
          ('custom', 'Custom'),
          ('aa', 'aa'),
          ('zz', 'zz'),
        ]);
      });

      test('old maps join by key case-insensitively; aliases with the same URLs collapse', () {
        final url = streamUrl(
          data: {'uhd': main('uhd', codec: 'h265')},
          flv: {'FULL_HD1': 'https://a.test/uhd.flv?expire=6ac221a0', 'SD1': 'https://a.test/sd1.flv?expire=6ac221a0'},
          hls: {
            'full_hd1': 'https://a.test/uhd.m3u8?expire=6ac221a0',
            'sd1': 'https://a.test/sd1.m3u8?expire=6ac221a0',
          },
          names: {'sd1': 'SD1'},
        );
        expect(DouyinParse.qualities(url).map((q) => (q.id, q.label)), [('full_hd1', '蓝光'), ('sd1', '标清')]);
        final set = DouyinParse.streams(url, issuedAt: DateTime.utc(2026, 9, 27), quality: 'uhd');
        expect(set.selected.id, 'full_hd1');
        expect(set.lines.map((l) => (l.format, l.lineId, l.url.path)), [
          (StreamFormat.flv, 'flv', '/uhd.flv'),
          (StreamFormat.hls, 'hls', '/uhd.m3u8'),
        ]);
        // Only the uhd stream_data entry reports the codec; the survivor inherits it.
        expect(DouyinParse.streams(url, issuedAt: DateTime.utc(2026, 9, 27)).lines.map((l) => l.codec).toSet(), {
          'hevc',
        });
      });

      test('two URLs of one format get distinct line ids', () {
        final url = streamUrl(data: {'hd': main('hd')}, flv: {'HD': 'https://b.test/hd.flv'});
        final lines = DouyinParse.streams(url, issuedAt: DateTime.utc(2026, 9, 27)).lines;
        expect(lines.map((l) => l.lineId), ['flv', 'hls', 'flv-2']);
        expect(lines.map((l) => l.codec).toSet(), {'avc'});
      });
    });

    test('§6 lease: expire decimal or hex, wsTime+keeptime, k+t; unknown schemes have none', () {
      final issued = DateTime.utc(2026, 9, 27, 9, 51, 28);
      final expiry = DateTime.utc(2026, 10, 4, 9, 51, 28);
      for (final query in [
        'expire=1791107488',
        'expire=6ac221a0',
        'volcTime=1791107488',
        'keeptime=00093a80&wsTime=6ab8e720',
        'k=abc&t=1791107488',
      ]) {
        final lease = DouyinParse.lease(Uri.parse('https://a.test/x.flv?$query'), issued)!;
        expect(lease.expiresAt, expiry, reason: query);
        expect(lease.refreshAt, expiry.subtract(const Duration(minutes: 10)), reason: query);
        expect(lease.cutsConnection, isFalse, reason: query);
      }
      for (final query in ['auth_key=0795179846-7-2-x', 't=1791107488', 'expire=0', '']) {
        expect(DouyinParse.lease(Uri.parse('https://a.test/x.flv?$query'), issued), isNull, reason: query);
      }
      final short = DouyinParse.lease(Uri.parse('https://a.test/x.flv?expire=1790502748'), issued)!;
      expect(short.expiresAt!.difference(short.refreshAt), const Duration(seconds: 15));
    });

    test('§6 playback headers without a web_rid use the site root; never a cookie', () {
      expect(DouyinParse.playHeaders(), {
        'user-agent': DouyinParse.userAgent,
        'origin': 'https://live.douyin.com',
        'referer': 'https://live.douyin.com/',
      });
    });

    test(r'page payload: RSC "$$" escapes and "$undefined" are decoded', () {
      String push(String chunk) => '<script>self.__pace_f.push([1,${jsonEncode(chunk)}])</script>';
      final state = {
        'roomStore': {
          'roomInfo': {
            'room': {'id_str': '7000000000000000005', 'status': 4, 'title': r'$$5 room', 'owner': r'$undefined'},
            'anchor': {'nickname': 'D'},
          },
        },
        'userStore': {
          'odin': {'user_unique_id': '123'},
        },
      };
      final html =
          push('0:I["x"]\n') +
          push(
            '1:${jsonEncode([
              r'$',
              r'$L2',
              null,
              {'state': state},
            ])}\n',
          );
      final room = DouyinParse.roomPage(html, webRid: '33');
      expect(room.detail.card.title, r'$5 room');
      expect(room.detail.card.anchorName, 'D');
      expect(room.detail.state, LiveState.offline);
      expect(room.detail.danmakuKeys, {'webRid': '33', 'roomId': '7000000000000000005'});
    });
  });
}

/// Response headers with lower-case names; repeated values joined.
Map<String, String> _headers(Fixture fixture) => {
  for (final MapEntry(:key, :value) in ((fixture.meta['response'] as Map<String, dynamic>)['headers'] as Map).entries)
    '$key'.toLowerCase(): value is List ? value.join(', ') : '$value',
};

/// The raw room objects of a list sample by identity (feed envelopes or
/// partition items), for the audience fields the legacy output lost.
Map<String, Map<String, dynamic>> _rawRooms(Fixture fixture) {
  final root = jsonDecode(fixture.body) as Map<String, dynamic>;
  final data = root['data'];
  final items = data is List ? data : (data as Map<String, dynamic>)['data'] as List;
  return {
    for (final item in items.cast<Map<String, dynamic>>())
      '${item['web_rid']}': switch (item['data'] ?? item['room']) {
        final String json => jsonDecode(json) as Map<String, dynamic>,
        final Map<String, dynamic> room => room,
        _ => throw StateError('no room'),
      },
  };
}

void _expectCards(List<RoomCard> cards, List<Map<String, dynamic>> legacy, Map<String, Map<String, dynamic>> raw) {
  expect(cards.map((r) => r.ref.roomId), legacy.map((r) => r['roomId']));
  expect(cards.map((r) => r.title), legacy.map((r) => r['title']));
  expect(cards.map((r) => r.anchorName), legacy.map((r) => r['nick']));
  expect(cards.map((r) => r.cover?.toString()), legacy.map((r) => _blankToNull(r['cover'])));
  expect(cards.map((r) => r.state == LiveState.live), legacy.map((r) => r['status']));
  for (final (index, card) in cards.indexed) {
    _expectAudience(card.audience, legacy[index], raw[card.ref.roomId]!);
  }
}

void _expectDetail(DouyinRoom room, Map<String, dynamic> legacy, Map<String, dynamic> raw) {
  final detail = room.detail;
  expect(detail.ref, RoomRef('douyin', legacy['roomId'] as String));
  expect(detail.card.title, legacy['title']);
  expect(detail.card.anchorName, legacy['nick']);
  expect(detail.avatar?.toString(), _blankToNull(legacy['avatar']));
  expect(detail.card.cover?.toString(), _blankToNull(legacy['cover']));
  expect(detail.card.area, _blankToNull(legacy['area']));
  expect(detail.state == LiveState.live, legacy['status']);
  expect(detail.state == LiveState.offline, legacy['liveStatus'] == 1);
  expect(detail.introduction, _blankToNull(legacy['introduction']));
  expect(detail.notice, _blankToNull(legacy['notice']));
  expect(detail.link.toString(), legacy['link']);
  final danmaku = legacy['danmakuData'] as Map<String, dynamic>;
  // The visitor id is the adapter's (one per process); the cookie comes from
  // the credential store, not from the detail.
  expect(detail.danmakuKeys, {'webRid': danmaku['webRid'], 'roomId': danmaku['roomId']});
  expect(room.streamUrl != null, legacy['streamUrlKept']);
  _expectAudience(detail.card.audience, legacy, raw);
}

/// Online matches legacy when legacy had an exact count; the spec §4 /
/// DIAGNOSIS corrections are asserted where they apply.
void _expectAudience(Audience audience, Map<String, dynamic> legacy, Map<String, dynamic> room) {
  final reason = '${legacy['roomId']}';
  final legacyOnline = legacy['onlineViewers'] as String;
  final legacyTotal = legacy['totalViewers'] as String;
  if (legacyOnline.isEmpty && legacyTotal.isEmpty) {
    expect(audience, Audience.none, reason: reason);
    return;
  }
  expect(audience.popularity, isNull, reason: reason);
  final stats = room['stats'] as Map<String, dynamic>? ?? const {};
  final view = room['room_view_stats'] as Map<String, dynamic>? ?? const {};
  if (int.tryParse(legacyOnline) != null) {
    expect(audience.online, int.parse(legacyOnline), reason: reason);
  } else {
    // DIAGNOSIS "enter 没有 room.user_count 时取分档文本": legacy showed the
    // bucket ("2000+"); v4 takes the exact stats.user_count_str.
    expect(legacyOnline, endsWith('+'), reason: reason);
    expect(audience.online, int.parse(stats['user_count_str'] as String), reason: reason);
    expect(audience.online, greaterThanOrEqualTo(parseChineseCount(legacyOnline)!), reason: reason);
  }
  if (view['display_type'] == 1) {
    // DIAGNOSIS "不看 room_view_stats.display_type" (spec §4 correction):
    // display_type 1 is the online count ("713在线观众"); legacy reported it as
    // cumulative. v4 reports it as online and takes the cumulative from stats.
    expect(int.parse(legacyTotal), view['display_value'], reason: reason);
    expect(audience.online, view['display_value'], reason: reason);
    final total = parseChineseCount(stats['total_user_str']);
    expect(audience.cumulative, total != null && total > 0 ? total : null, reason: reason);
    expect(audience.cumulative, isNot(int.parse(legacyTotal)), reason: reason);
  } else {
    expect(view['display_type'], 3, reason: reason);
    expect(audience.cumulative, int.parse(legacyTotal), reason: reason);
  }
}

void _expectStreamsOrNone(DouyinRoom room, Map<String, dynamic> legacy, DateTime issuedAt) {
  final expected = (legacy['qualities'] as List).cast<Map<String, dynamic>>();
  if (room.streamUrl == null) {
    expect(expected, isEmpty);
    return;
  }
  _expectStreams(room.streamUrl!, expected, issuedAt, room.detail.ref.roomId);
}

/// Qualities (id, label, rank) and each quality's lines match legacy; every
/// line has a format matching its URL, the room's headers and, when the URL
/// carries an expiry, a 7-day lease that does not cut the connection.
void _expectStreams(
  Map<String, dynamic> streamUrl,
  List<Map<String, dynamic>> legacy,
  DateTime issuedAt,
  String webRid,
) {
  final qualities = DouyinParse.qualities(streamUrl);
  expect(qualities.map((q) => q.id), legacy.map((q) => q['id']), reason: webRid);
  expect(qualities.map((q) => q.label), legacy.map((q) => q['quality']), reason: webRid);
  expect(qualities.map((q) => q.rank), legacy.map((q) => q['sort']), reason: webRid);
  for (final (index, quality) in qualities.indexed) {
    final set = DouyinParse.streams(streamUrl, issuedAt: issuedAt, webRid: webRid, quality: quality.id);
    expect(set.qualities, qualities);
    expect(set.selected, quality);
    expect(set.lines.map((l) => l.url.toString()), legacy[index]['urls'], reason: '$webRid ${quality.id}');
    expect(set.lines.map((l) => l.lineId).toSet().length, set.lines.length);
    for (final line in set.lines) {
      final reason = '$webRid ${quality.id} ${line.url}';
      expect(line.format, line.url.path.endsWith('.flv') ? StreamFormat.flv : StreamFormat.hls, reason: reason);
      expect(line.requested, quality);
      expect(line.headers['referer'], 'https://live.douyin.com/$webRid');
      expect(line.codec, anyOf('avc', 'hevc', isNull), reason: reason);
      final lease = line.lease;
      if (lease == null) {
        // Only the auth_key scheme (timestamp scrubbed in the samples) has no readable expiry.
        expect(line.url.queryParameters, contains('auth_key'), reason: reason);
        continue;
      }
      expect(lease.cutsConnection, isFalse, reason: reason);
      expect(lease.expiresAt!.difference(issuedAt).inSeconds, closeTo(7 * 24 * 3600, 5), reason: reason);
    }
  }
}

/// Legacy writes a missing field as ''; v4 uses null.
String? _blankToNull(Object? value) => value == null || value == '' ? null : value as String;
