// Bilibili parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json). Every intended difference is listed
// with its reason; everything else must match.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('bilibili', name);

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

/// [body] with `data.room_info` (getInfoByRoom) changed by [change].
String _editRoomInfo(String body, void Function(Map<String, dynamic> room) change) {
  final root = jsonDecode(body) as Map<String, dynamic>;
  change((root['data'] as Map<String, dynamic>)['room_info'] as Map<String, dynamic>);
  return jsonEncode(root);
}

/// [body] with `data` (getRoomPlayInfo) changed by [change].
String _editPlay(String body, void Function(Map<String, dynamic> data) change) {
  final root = jsonDecode(body) as Map<String, dynamic>;
  change(root['data'] as Map<String, dynamic>);
  return jsonEncode(root);
}

void main() {
  test('S01 categories: ids, names and areas match 3.x', () {
    final fixture = _sample('S01-guest');
    final categories = BilibiliApi.categories(fixture.body, status: fixture.status);
    final legacy = (fixture.legacy as List).cast<Map<String, dynamic>>();
    expect(categories.map((category) => category.id), legacy.map((category) => category['id']));
    expect(categories.map((category) => category.name), legacy.map((category) => category['name']));
    for (final (index, category) in categories.indexed) {
      final areas = (legacy[index]['children'] as List).cast<Map<String, dynamic>>();
      expect(category.children, hasLength(areas.length));
      for (final (position, area) in category.children.indexed) {
        _expectParity(area.toJson(), areas[position], reason: 'S01[$index][$position]');
      }
    }
  });

  test('S02 a -352 area list is RiskControl (3.x wrapped it in two Exceptions)', () {
    for (final name in ['S02-risk352', 'S02-signed-risk352']) {
      final fixture = _sample(name);
      final thrown = (fixture.legacy as Map<String, dynamic>)['throws'] as Map<String, dynamic>;
      expect(thrown['message'], startsWith('Exception: Exception:'), reason: name);
      expect(() => BilibiliApi.roomList(fixture.body, status: fixture.status), throwsA(isA<RiskControl>()));
    }
  });

  group('S03/S04 recommend', () {
    for (final name in ['S03-page1', 'S03-out-of-range', 'S04-page1']) {
      test('$name: same rooms in the same order as 3.x', () {
        final fixture = _sample(name);
        final result = BilibiliApi.roomList(fixture.body, status: fixture.status);
        final legacy = (fixture.legacy as List).cast<Map<String, dynamic>>();
        expect(result.rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        for (final (index, room) in result.rooms.indexed) {
          // totalViewers: the "N人看过" count 3.x dropped (the capability table
          // already says Bilibili has cumulative viewers).
          _expectParity(room.toJson(), legacy[index], changed: {'totalViewers'}, reason: '$name[$index]');
          expect(room.onlineViewers, isEmpty, reason: '`online` is popularity, never a head count');
        }
        expect(result.hasMore, legacy.isNotEmpty, reason: 'neither endpoint reports an end');
      });
    }

    test('"N人看过" is cumulative viewers; "N人气" (switch false) only repeats popularity', () {
      final fixture = _sample('S03-page1');
      final raw = ((jsonDecode(fixture.body) as Map)['data'] as List).cast<Map<String, dynamic>>();
      for (final room in BilibiliApi.roomList(fixture.body).rooms) {
        final show = raw.firstWhere((item) => '${item['roomid']}' == room.roomId)['watched_show'] as Map?;
        expect(room.totalViewers, show?['switch'] == true ? '${show!['num']}' : '', reason: room.roomId);
      }
    });
  });

  test('M4.D S17 area rooms (room/v1/area/getRoomList): live rooms by popularity, all fields read', () {
    final fixture = _sample('S17-area-page1');
    final result = BilibiliApi.roomList(fixture.body, status: fixture.status);
    expect(result.rooms, hasLength(30));
    expect(result.hasMore, isTrue);
    final first = result.rooms.first;
    expect(first.roomId, '545068', reason: 'the long id; `link` has the short one');
    expect(first.liveStatus, LiveStatus.live);
    expect(first.area, '英雄联盟');
    expect(first.popularity, '526382');
    expect(first.cover, endsWith('.jpg@400w.jpg'));
    for (final room in result.rooms) {
      expect([room.title, room.nick, room.avatar, room.cover, room.popularity], everyElement(isNotEmpty));
    }
    final popularity = [for (final room in result.rooms) int.parse(room.popularity)];
    expect(popularity, [...popularity]..sort((a, b) => b.compareTo(a)));
    expect(BilibiliApi.roomList('{"code":0,"data":[]}').hasMore, isFalse, reason: 'past the last page');
  });

  group('S05 search', () {
    test('M4.D: an area named by the keyword comes without the highlight tags', () {
      final fixture = _sample('S05-area-keyword');
      expect(fixture.body, contains(r'"cate_name":"<em class=\"keyword\">英雄联盟</em>"'));
      final rooms = BilibiliApi.searchRooms(fixture.body, page: 1, status: fixture.status);
      expect(rooms, hasLength(36));
      expect(rooms.where((room) => room.area!.contains('<')), isEmpty);
      expect(rooms.first.area, '英雄联盟');
    });

    for (final name in ['S05-live-results', 'S05-no-buvid3']) {
      test('$name: 3.x rooms first, then the matching streamers 3.x never showed', () {
        final fixture = _sample(name);
        final rooms = BilibiliApi.searchRooms(fixture.body, page: 1, status: fixture.status);
        final legacy = (fixture.legacy as List).cast<Map<String, dynamic>>();
        final raw = (((jsonDecode(fixture.body) as Map)['data'] as Map)['result'] as Map).cast<String, dynamic>();
        final liveRooms = (raw['live_room'] as List).cast<Map<String, dynamic>>();
        for (final (index, room) in rooms.take(legacy.length).indexed) {
          // cover: the room cover (`user_cover`, what 3.x asked for with
          // cover_type=user_cover) instead of the keyframe in `cover`; 3.x also
          // wrote `https:https://…` for absolute covers.
          // totalViewers: see recommend.
          _expectParity(room.toJson(), legacy[index], changed: {'cover', 'totalViewers'}, reason: '$name[$index]');
          expect(room.cover, startsWith('https://i0.hdslb.com/bfs/live/'), reason: 'room cover, not a keyframe');
          expect(
            room.cover,
            contains(liveRooms[index]['user_cover'].toString().replaceFirst(RegExp('^(https?:)?//'), '')),
          );
        }
        expect(legacy.where((room) => '${room['cover']}'.startsWith('https:https:')), isNotEmpty);
        final users = rooms.skip(legacy.length).toList();
        expect(users, isNotEmpty);
        expect(users.every((room) => room.title.isEmpty && room.cover.isEmpty), isTrue);
        expect(rooms.map((room) => room.roomId).toSet(), hasLength(rooms.length), reason: 'no duplicates');
        expect(
          BilibiliApi.searchRooms(fixture.body, page: 2),
          hasLength(legacy.length),
          reason: 'streamers on page 1 only',
        );
        // 1-1: the streamers' live_status 2 is the carousel, 0 offline.
        final liveUsers = (raw['live_user'] as List).cast<Map<String, dynamic>>();
        for (final room in users) {
          final user = liveUsers.firstWhere((item) => '${item['roomid']}' == room.roomId);
          expect(
            room.effectiveLiveStatus,
            user['live_status'] == 2 ? LiveStatus.carousel : LiveStatus.offline,
            reason: room.roomId,
          );
          expect(room.startedAt, isNull, reason: '0000-00-00 00:00:00 is no time');
        }
        expect(users.where((room) => room.liveStatus == LiveStatus.carousel).map((room) => room.roomId), [
          '5440',
          '22462095',
        ]);
      });
    }

    test("start time: a live room's live_time is Beijing time (UTC+8)", () {
      final fixture = _sample('S05-live-results');
      final rooms = BilibiliApi.searchRooms(fixture.body, page: 1).where((room) => room.isLiveNow).toList();
      expect(rooms, hasLength(14));
      // "2026-09-27 14:59:59"
      expect(rooms.first.startedAt, DateTime.utc(2026, 9, 27, 6, 59, 59));
      for (final room in rooms) {
        expect(room.startedAt, isNotNull, reason: room.roomId);
        expect(room.startedAt!.isAfter(fixture.capturedAt), isFalse, reason: 'started before the search');
      }
      // The latest start ("17:53:25") is 28 seconds before the capture, so the
      // text is not UTC.
      final latest = rooms.map((room) => room.startedAt!).reduce((a, b) => a.isAfter(b) ? a : b);
      expect(fixture.capturedAt.difference(latest), lessThan(const Duration(minutes: 1)));
    });

    test('no results and out of range are empty', () {
      for (final name in ['S05-no-results', 'S05-out-of-range']) {
        final fixture = _sample(name);
        final page = int.parse(fixture.url.queryParameters['page']!);
        expect(
          BilibiliApi.searchRooms(fixture.body, page: page, status: fixture.status),
          isEmpty,
          reason: name,
        );
      }
    });
  });

  group('S06 room detail', () {
    for (final name in ['S06-live', 'S06-offline', 'S06-replay', 'S06-short-id', 'S06-short-id-long']) {
      test('$name matches 3.x', () {
        final fixture = _sample(name);
        final requested = fixture.url.queryParameters['room_id']!;
        final detail = BilibiliApi.roomDetail(fixture.body, requestedId: requested, status: fixture.status);
        final legacy = fixture.legacy as Map<String, dynamic>;
        final json = detail.room.toJson();
        final room = legacy['getRoomDetailForRefresh'] as Map<String, dynamic>;
        // introduction: HTML made plain text (3.x kept `<p>…</p>`);
        // totalViewers: see recommend;
        // liveStatus: the carousel (live_status 2) is its own state, index 5
        // instead of 3.x's offline (1-1). `status` and `isRecord` are unchanged,
        // so 3.x still reads the room as offline.
        _expectParity(
          json,
          room,
          changed: {'introduction', 'totalViewers', if (name == 'S06-replay') 'liveStatus'},
          reason: name,
        );
        // M2.1's keys, which 3.x never wrote: the start time of a live room
        // and the restriction (none in every sample).
        expect(json.containsKey('startedAt'), detail.room.isLiveNow, reason: name);
        expect(json['restriction'], 'none', reason: name);
        expect(detail.longId, '${legacy['parseRoomInfoResponse.room_info.room_id']}');
        expect(detail.room.roomId, requested, reason: 'a follow keeps the id it was made with');
      });
    }

    test('1-1: a carousel (live_status 2) is its own state, grouped with offline and not playable', () {
      final fixture = _sample('S06-replay');
      final room = BilibiliApi.roomDetail(fixture.body, requestedId: '5440').room;
      expect(room.effectiveLiveStatus, LiveStatus.carousel);
      expect(room.isLiveNow, isFalse);
      expect(room.isPlayableNow, isFalse);
      expect(room.isExplicitlyOfflineNow, isTrue, reason: 'recording treats it as off air');
      expect(room.followGroup, FollowGroup.offline);
      expect(room.toJson(), containsPair('liveStatus', LiveStatus.carousel.index));
      expect(room.toJson(), allOf(containsPair('status', false), containsPair('isRecord', false)));
      expect(room.startedAt, isNull);
      expect(room.introduction, '凡人线下嘉年华', reason: 'its HTML description becomes text');
      final offline = BilibiliApi.roomDetail(_sample('S06-offline').body, requestedId: '22647871').room;
      expect(offline.effectiveLiveStatus, LiveStatus.offline, reason: 'live_status 0 stays offline');
    });

    test("start time: a live room's live_start_time (Unix seconds) as UTC; none off air", () {
      DateTime? started(String name) {
        final fixture = _sample(name);
        return BilibiliApi.roomDetail(
          fixture.body,
          requestedId: fixture.url.queryParameters['room_id']!,
        ).room.startedAt;
      }

      expect(started('S06-live'), DateTime.utc(2026, 9, 27, 8, 56, 16));
      expect(started('S06-short-id'), DateTime.utc(2026, 9, 7, 6, 22, 39));
      expect(started('S06-short-id-long'), DateTime.utc(2026, 9, 7, 6, 22, 39));
      expect(started('S06-offline'), isNull, reason: 'live_start_time 0');
      expect(started('S06-replay'), isNull, reason: 'a carousel is not a broadcast');
      final live = _sample('S06-live');
      expect(
        BilibiliApi.roomDetail(live.body, requestedId: '42062').room.toJson()['startedAt'],
        '2026-09-27T08:56:16.000Z',
      );
      expect(started('S06-live')!.isBefore(live.capturedAt), isTrue);
    });

    test('restriction: special_type 1 on a live room is paid and still live; otherwise none', () {
      final live = _sample('S06-live');
      expect(BilibiliApi.roomDetail(live.body, requestedId: '42062').room.restriction, LiveRestriction.none);
      final paid = BilibiliApi.roomDetail(
        _editRoomInfo(live.body, (room) => room['special_type'] = 1),
        requestedId: '42062',
      ).room;
      expect(paid.restriction, LiveRestriction.paid);
      expect(paid.isLiveNow, isTrue);
      expect(paid.isRestricted, isTrue);
      expect(paid.followGroup, FollowGroup.live);
      final offline = _sample('S06-offline');
      expect(
        BilibiliApi.roomDetail(
          _editRoomInfo(offline.body, (room) => room['special_type'] = 1),
          requestedId: '22647871',
        ).room.restriction,
        LiveRestriction.none,
        reason: 'no broadcast to restrict',
      );
      expect(
        BilibiliApi.roomDetail(
          _editRoomInfo(live.body, (room) => room.remove('special_type')),
          requestedId: '42062',
        ).room.restriction,
        isNull,
        reason: 'without the field the response says nothing',
      );
    });

    test('missing rooms are NotFound; -352 is RiskControl', () {
      final missing = _sample('S06-not-found');
      expect(
        () => BilibiliApi.roomDetail(missing.body, requestedId: '999999999', status: missing.status),
        throwsA(isA<NotFound>()),
      );
      final risk = _sample('S06-risk352');
      expect(
        () => BilibiliApi.roomDetail(risk.body, requestedId: '42062', status: risk.status),
        throwsA(isA<RiskControl>()),
      );
    });

    test('a string live_status "1" is live (REG-BILIBILI-019)', () {
      final fixture = _sample('S06-live');
      final body = fixture.body.replaceFirst(RegExp('"live_status": *1'), '"live_status": "1"');
      expect(body, isNot(fixture.body));
      expect(BilibiliApi.roomDetail(body, requestedId: '42062').room.isLiveNow, isTrue);
    });
  });

  group('S07 play', () {
    for (final name in [
      'S07-guest-qn0',
      'S07-guest-qn10000',
      'S07-hevc-qn10000',
      'S07-short-id',
      'S07-short-id-long',
    ]) {
      test('$name: qualities, URLs and the applied quality match 3.x', () {
        final fixture = _sample(name);
        final legacy = fixture.legacy as Map<String, dynamic>;
        final data = BilibiliApi.playData(fixture.body, status: fixture.status);
        final qualities = BilibiliApi.qualities(data);
        expect([
          for (final quality in qualities)
            {'quality': quality.quality, 'id': quality.id, 'data': quality.data, 'sort': quality.sort},
        ], legacy['parsePlayQualities']);
        final resolution = BilibiliApi.resolution(
          data,
          requestedQn: legacy['requestedQn'],
          roomId: fixture.url.queryParameters['room_id']!,
          issuedAt: fixture.capturedAt,
        );
        final expected = legacy['parsePlayUrlResolution'] as Map<String, dynamic>;
        // A response with both codecs (the HEVC sample asked for codec=0,1):
        // 3.x mixed AVC and HEVC lines in one set; one codec is kept now.
        final legacyUrls = (expected['urls'] as List).cast<String>();
        expect(resolution.urls, [
          for (final url in legacyUrls)
            if (!url.contains('hevc') && !url.contains('codec=1')) url,
        ]);
        expect(resolution.lines.map((line) => line.codec).toSet(), hasLength(1));
        expect(resolution.appliedQualityData, expected['appliedQualityData']);
        expect(resolution.qualityUnconfirmed, expected['qualityUnconfirmed']);
      });
    }

    test('a guest asking for 10000 is served 250, and the lines say so (REG-BILIBILI-001)', () {
      final fixture = _sample('S07-guest-qn10000');
      final data = BilibiliApi.playData(fixture.body);
      final resolution = BilibiliApi.resolution(data, requestedQn: 10000, roomId: '1', issuedAt: fixture.capturedAt);
      expect(resolution.appliedQualityData, 250);
      final shown = resolveAppliedPlayQuality(
        qualities: BilibiliApi.qualities(data),
        requested: const LivePlayQuality(quality: '原画', id: 10000, data: 10000),
        resolution: resolution,
      );
      expect(shown.quality, '超清');
    });

    test('lines describe themselves: media headers, format, codec and a lease from expires', () {
      final fixture = _sample('S07-guest-qn0');
      final resolution = BilibiliApi.resolution(
        BilibiliApi.playData(fixture.body),
        requestedQn: 0,
        roomId: '42062',
        issuedAt: fixture.capturedAt,
        cookie: 'buvid3=x;',
      );
      for (final line in resolution.lines) {
        expect(line.headers, {
          'user-agent': BilibiliApi.userAgent,
          'origin': 'https://live.bilibili.com',
          'referer': 'https://live.bilibili.com/42062',
          'cookie': 'buvid3=x;',
        });
        expect(line.headers.keys, isNot(contains('authority')), reason: 'REG-BILIBILI-016');
        expect(line.format, Uri.parse(line.url).path.endsWith('.flv') ? StreamFormat.flv : StreamFormat.hls);
        expect(line.codec, 'avc');
        final lease = line.lease!;
        expect(lease.expiresAt!.difference(lease.refreshAt), BilibiliApi.leaseLead);
        expect(lease.cutsConnection, isFalse);
      }
      expect(resolution.lines.map((line) => line.url).toSet(), hasLength(resolution.lines.length));
    });

    test('offline and carousel rooms give guests no stream: StreamUnavailable (3.x threw FormatException)', () {
      for (final (name, state) in [('S07-offline', 'offline'), ('S07-replay', 'carousel')]) {
        final fixture = _sample(name);
        expect(
          () => BilibiliApi.playData(fixture.body, status: fixture.status),
          throwsA(isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains(state))),
          reason: name,
        );
      }
    });

    test('1-1 (F.5a): a carousel without a stream is told apart; its video and file are read', () {
      expect(BilibiliApi.carouselWithoutStream(_sample('S07-replay').body), isTrue);
      for (final name in ['S07-offline', 'S07-guest-qn0']) {
        expect(BilibiliApi.carouselWithoutStream(_sample(name).body), isFalse, reason: name);
      }
      expect(BilibiliApi.carouselWithoutStream('<html>'), isFalse);
      expect(BilibiliApi.carouselWithoutStream('{"code":-352}'), isFalse);
      expect(
        BilibiliApi.carouselWithoutStream(_editPlay(_sample('S07-guest-qn0').body, (data) => data['live_status'] = 2)),
        isFalse,
        reason: 'signed in, the carousel has a stream',
      );

      String round(Map<String, Object?> data) => jsonEncode({'code': 0, 'message': '0', 'data': data});
      final video = BilibiliApi.roundPlayVideo(round({'bvid': 'BV1zKZrYAEi8', 'cid': '29153362694', 'play_time': 61}));
      expect(video, (bvid: 'BV1zKZrYAEi8', cid: 29153362694, start: const Duration(seconds: 61)));
      expect(
        BilibiliApi.roundPlayVideo(round({'bvid': 'BV1zKZrYAEi8', 'cid': 1, 'play_time': -5})).start,
        Duration.zero,
      );
      expect(BilibiliApi.roundPlayVideo(round({'bvid': 'BV1zKZrYAEi8', 'cid': 1})).start, Duration.zero);
      for (final data in <Map<String, Object?>>[
        {'bvid': 'BV1zKZrYAEi8', 'cid': -1},
        {'bvid': '', 'cid': 5},
        {'bvid': 'av170001', 'cid': 5},
      ]) {
        expect(() => BilibiliApi.roundPlayVideo(round(data)), throwsA(isA<StreamUnavailable>()), reason: '$data');
      }
      expect(() => BilibiliApi.roundPlayVideo('{"code":0,"data":null}'), throwsA(isA<ApiChanged>()));
      expect(() => BilibiliApi.roundPlayVideo('{"code":-352,"message":"-352"}'), throwsA(isA<RiskControl>()));

      final file = Fixture.load('live_vod', 'V09-playurl-mp4');
      expect(
        BilibiliApi.videoPlayUrl('BV1zKZrYAEi8', 29153362694),
        file.url,
        reason: "the recorded request, the TV client's",
      );
      final resolution = BilibiliApi.videoResolution(
        file.body,
        bvid: 'BV1zKZrYAEi8',
        start: const Duration(seconds: 61),
        cookie: 'buvid3=x',
      );
      expect(resolution.lines.single.url, contains('29153362694-1-160.mp4'));
      expect(resolution.lines.single.headers, {
        'user-agent': BilibiliApi.userAgent,
        'referer': 'https://www.bilibili.com/video/BV1zKZrYAEi8/',
        'cookie': 'buvid3=x',
      });
      expect((resolution.start, resolution.appliedQualityData), (const Duration(seconds: 61), 'carousel'));
      expect(
        () => BilibiliApi.videoResolution('{"code":0,"data":{"durl":[]}}', bvid: 'BV1zKZrYAEi8', start: Duration.zero),
        throwsA(isA<StreamUnavailable>()),
      );
      final backups = BilibiliApi.videoResolution(
        jsonEncode({
          'code': 0,
          'data': {
            'durl': [
              {
                'url': 'https://a.bilivideo.com/1.mp4',
                'backup_url': ['https://b.bilivideo.com/1.mp4', 'ftp://c/1.mp4', 'https://a.bilivideo.com/1.mp4'],
              },
            ],
          },
        }),
        bvid: 'BV1zKZrYAEi8',
        start: Duration.zero,
      );
      expect(backups.urls, ['https://a.bilivideo.com/1.mp4', 'https://b.bilivideo.com/1.mp4']);
    });

    test('1-1: a carousel that comes with a stream (a signed-in user) is played', () {
      final fixture = _sample('S07-guest-qn0');
      final data = BilibiliApi.playData(_editPlay(fixture.body, (data) => data['live_status'] = 2));
      expect(BilibiliApi.qualities(data), isNotEmpty);
      final resolution = BilibiliApi.resolution(data, requestedQn: 0, roomId: '42062', issuedAt: fixture.capturedAt);
      expect(resolution.lines, isNotEmpty);
    });

    test('a paid broadcast without a ticket (1 in all_special_types) says so', () {
      final fixture = _sample('S07-offline');
      final paid = _editPlay(fixture.body, (data) {
        data['live_status'] = 1;
        data['all_special_types'] = [1, 50];
      });
      expect(
        () => BilibiliApi.playData(paid),
        throwsA(isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('paid broadcast'))),
      );
      final live = _editPlay(fixture.body, (data) => data['live_status'] = 1);
      expect(
        () => BilibiliApi.playData(live),
        throwsA(isA<StreamUnavailable>().having((error) => error.detail, 'detail', isNot(contains('paid')))),
      );
    });
  });

  group('session', () {
    test('S09 danmaku credentials: token and endpoints, the general gateway first', () {
      final fixture = _sample('S09-guest');
      final info = BilibiliApi.danmakuInfo(fixture.body, status: fixture.status);
      final legacy = jsonDecode(((fixture.legacy as Map)['room'] as Map)['danmakuData'] as String) as Map;
      expect(info.servers.map((uri) => uri.toString()), legacy['serverUrls']);
      expect(info.token, isNotEmpty);
      expect(info.servers.first.toString(), BilibiliApi.danmakuGateway);
    });

    test('S10 guest buvid and the cookie built from it', () {
      final fixture = _sample('S10-guest');
      final legacy = fixture.legacy as Map<String, dynamic>;
      final buvid = BilibiliApi.buvid(fixture.body, status: fixture.status);
      expect(buvid.buvid3, (legacy['getBuvid'] as Map)['b_3']);
      expect(buvid.buvid4, (legacy['getBuvid'] as Map)['b_4']);
      final cookie = BilibiliApi.cookie(buvid3: buvid.buvid3, buvid4: buvid.buvid4);
      expect(BilibiliApi.apiHeaders(cookie), legacy['getHeader']);
      expect(BilibiliApi.cookie(buvid3: 'a', buvid4: 'b', loginCookie: 'SESSDATA=s'), 'SESSDATA=s;buvid3=a;buvid4=b;');
      expect(BilibiliApi.cookie(buvid3: 'a', buvid4: 'b', loginCookie: 'buvid3=own; x=1'), 'buvid3=own; x=1');
    });

    test('S11 WBI keys and mixin key match 3.x', () {
      final fixture = _sample('S11-guest');
      final legacy = fixture.legacy as Map<String, dynamic>;
      final keys = BilibiliApi.wbiKeys(fixture.body, status: fixture.status);
      expect(keys.imgKey, legacy['imgKey']);
      expect(keys.subKey, legacy['subKey']);
      expect(BilibiliApi.mixinKey(keys.imgKey, keys.subKey), legacy['mixinKey']);
    });

    test('WBI signing: sorted, filtered, encoded, md5 over query and mixin key', () {
      final query = BilibiliApi.wbiQuery({'room_id': '42062', 'z': "a b!'()*"}, wts: 1700000000);
      expect(query, 'room_id=42062&wts=1700000000&z=a%20b');
      final signed = BilibiliSite.wbiSign(
        {'foo': '114', 'bar': '514', 'zab': '1919810'},
        imgKey: '7cd084941338484aae1ad9425b84077c',
        subKey: '4932caff0ff746eab6f01bf08b70ac45',
        wts: 1702204169,
      );
      // The published example of the WBI algorithm.
      expect(signed, 'bar=514&foo=114&wts=1702204169&zab=1919810&w_rid=8f6f2b5b3d485fe1886cec6a0be8c5d4');
    });

    test('S12 access id', () {
      final fixture = _sample('S12-guest');
      expect(BilibiliApi.accessId(fixture.body), (fixture.legacy as Map)['getAccessId']);
    });

    test('S15 QR code and poll states', () {
      final generate = _sample('S15-generate');
      final code = BilibiliApi.qrCode(generate.body, status: generate.status);
      expect(code.key, (generate.legacy as Map)['qrcodeKey']);
      expect(code.url.toString(), (generate.legacy as Map)['qrcodeUrl']);
      expect(BilibiliApi.qrPoll(_sample('S15-poll-86101').body), BilibiliQrState.waiting);
      expect(BilibiliApi.qrPoll(_sample('S15-poll-86038').body), BilibiliQrState.expired);
    });

    test('S16 an expired cookie is NeedsLogin', () {
      final fixture = _sample('S16-no-cookie');
      expect(() => BilibiliApi.account(fixture.body, status: fixture.status), throwsA(isA<NeedsLogin>()));
    });

    test('danmaku uid: guest 0, else DedeUserID of the same cookie, else the stored uid', () {
      expect(BilibiliApi.danmakuUid(cookie: '', storedUid: 7), 0);
      expect(BilibiliApi.danmakuUid(cookie: 'SESSDATA=x; DedeUserID=123; b=1', storedUid: 7), 123);
      expect(BilibiliApi.danmakuUid(cookie: 'SESSDATA=x', storedUid: 7), 7);
      expect(BilibiliApi.danmakuUid(cookie: 'SESSDATA=x', storedUid: 0), 0);
    });
  });

  test('envelope errors are typed', () {
    expect(() => BilibiliApi.liveStatus('{"code":0,"data":{}}', status: 412), throwsA(isA<RateLimited>()));
    expect(() => BilibiliApi.liveStatus('', status: 502), throwsA(isA<NetworkFailure>()));
    expect(() => BilibiliApi.liveStatus('{"code":-412}'), throwsA(isA<RateLimited>()));
    expect(() => BilibiliApi.liveStatus('<html>'), throwsA(isA<ApiChanged>()));
    expect(() => BilibiliApi.liveStatus('{"code":1}'), throwsA(isA<ApiChanged>()));
    expect(BilibiliApi.liveStatus('{"code":0,"data":{"live_status":1}}'), isTrue);
    expect(BilibiliApi.liveStatus('{"code":0,"data":{"live_status":2}}'), isFalse, reason: 'a carousel is not live');
  });

  test('super chats: display window, sender and price; entries without a time are skipped', () {
    final chats = BilibiliApi.superChats(
      jsonEncode({
        'code': 0,
        'data': {
          'list': [
            {
              'id': 9,
              'message': '加油',
              'price': 30,
              'start_time': 1700000000,
              'end_time': 1700000060,
              'background_color': '#EDF5FF',
              'background_bottom_color': '#2A60B2',
              'user_info': {'uname': 'u', 'face': '//i0.hdslb.com/f.jpg'},
            },
            {'message': 'no time'},
          ],
        },
      }),
    );
    expect(chats, hasLength(1));
    expect(chats.single.messageId, '9');
    // D07.2: yuan, the unit of the platform table (superChatUnits).
    expect((chats.single.price, chats.single.unit), (30, LiveGiftUnit.yuan));
    expect(superChatUnits[SiteIds.bilibili], LiveGiftUnit.yuan);
    expect(chats.single.face, 'https://i0.hdslb.com/f.jpg@200w.jpg');
    expect(chats.single.endTime.difference(chats.single.startTime), const Duration(minutes: 1));
  });

  group('D07.4 gift table', () {
    test('S18-gift-config: the gifts by id, the guards by level, pictures https', () {
      final fixture = _sample('S18-gift-config');
      final table = BilibiliApi.giftCatalog(fixture.body, status: fixture.status);
      expect(fixture.url, BilibiliApi.giftConfigUrl);
      expect(table.gifts.keys, unorderedEquals(['31164', '1', '31036', '31039', '35969', '3', '30607', '34315']));
      expect(
        table['31039'],
        BilibiliGiftInfo(
          id: '31039',
          name: '牛哇牛哇',
          price: 100,
          icon: Uri.parse('https://s1.hdslb.com/bfs/live/91ac8e35dd93a7196325f1e2052356e71d135afb.png'),
        ),
      );
      expect((table['30607']!.name, table['30607']!.price, table['30607']!.silver), ('小心心', 0, true));
      expect((table['1']!.price, table['1']!.silver), (100, true));
      expect(table['34315']!.price, 9900);
      expect({for (final MapEntry(:key, :value) in table.guards.entries) key: value.name}, {1: '总督', 2: '提督', 3: '舰长'});
      expect(table.guards.values.every((guard) => guard.icon!.scheme == 'https'), isTrue);
      expect(table.isEmpty, isFalse);
      expect(BilibiliGiftCatalog.empty.isEmpty, isTrue);
    });

    test('entries without an id or a name are left out; a bad envelope is a SiteError', () {
      final table = BilibiliApi.giftCatalog(
        jsonEncode({
          'code': 0,
          'data': {
            'list': [
              {'id': 0, 'name': 'x'},
              {'id': 5, 'name': ''},
              {'id': 6, 'name': 'ok', 'price': -1, 'img_basic': 'http://i0.hdslb.com/a.png'},
              'not a gift',
            ],
            'guard_resources': [
              {'level': 0, 'name': 'none'},
              {'level': 3, 'name': '舰长'},
            ],
          },
        }),
      );
      expect(table.gifts.values, [
        BilibiliGiftInfo(id: '6', name: 'ok', icon: Uri.parse('https://i0.hdslb.com/a.png')),
      ]);
      expect(table.guards.keys, [3]);
      expect(() => BilibiliApi.giftCatalog('{"code":-400,"message":"bad"}'), throwsA(isA<SiteError>()));
      expect(() => BilibiliApi.giftCatalog('{"code":0}'), throwsA(isA<ApiChanged>()));
      expect(() => BilibiliApi.giftCatalog('<html>', status: 502), throwsA(isA<NetworkFailure>()));
    });

    test('guard names and gift pictures', () {
      expect([for (var level = 0; level <= 4; level++) BilibiliApi.guardName(level)], ['', '总督', '提督', '舰长', '']);
      expect(BilibiliApi.giftIcon('//s1.hdslb.com/a.png'), Uri.parse('https://s1.hdslb.com/a.png'));
      expect(BilibiliApi.giftIcon('http://example.com/a.png'), Uri.parse('http://example.com/a.png'));
      expect(BilibiliApi.giftIcon(''), isNull);
      expect(BilibiliApi.giftIcon(null), isNull);
    });
  });
}
