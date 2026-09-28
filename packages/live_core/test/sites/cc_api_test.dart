// NetEase CC parsing against the recorded samples, compared field by field
// with 3.x's frozen output (expected.json, written by
// fixtures/cc/legacy_expected.dart from 3.x's parsers). Every intended
// difference is listed with its reason; everything else must match.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('cc', name);

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

List<Map<String, dynamic>> _rooms(Object? legacy) =>
    ((legacy! as Map<String, dynamic>)['rooms'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _json(String body) => jsonDecode(body) as Map<String, dynamic>;

/// The Dashen configuration sample with [edit] applied to its live entries.
String _config(void Function(Map<String, dynamic> root, List<Object?> entries) edit) {
  final root = _json(_sample('S01-dashen-config').body);
  final result = root['result'] as Map<String, dynamic>;
  final group = (result['itemList'] as List).cast<Map<String, dynamic>>().firstWhere(
    (item) => item['name'] == '直播入口列表',
  );
  edit(result, group['itemList'] as List<Object?>);
  return jsonEncode(root);
}

void main() {
  group('S01 catalog', () {
    final games = _sample('S01-dashen-games');
    final config = _sample('S01-dashen-config');

    test('the Dashen live entries: categories, areas and official rooms match 3.x (REG-CC-001)', () {
      final categories = CcApi.categories(games.body, config.body, gamesStatus: games.status);
      final legacy = (config.legacy as List).cast<Map<String, dynamic>>();
      expect(categories.map((category) => category.id), legacy.map((category) => category['id']));
      expect(categories.map((category) => category.name), legacy.map((category) => category['name']));
      for (final (index, category) in categories.indexed) {
        final areas = (legacy[index]['children'] as List).cast<Map<String, dynamic>>();
        expect(category.children, hasLength(areas.length));
        for (final (position, area) in category.children.indexed) {
          _expectParity(area.toJson(), areas[position], reason: 'S01[$index][$position]');
        }
      }
      expect(categories.map((category) => category.children.length), [20, 4]);
      expect(categories.last.children.first.areaId, 'official:249133');
    });

    test('official entries open the website, rebuilt from their id', () {
      final official = CcApi.categories(games.body, config.body).last.children.first;
      expect(CcApi.isOfficialEntry(official), isTrue);
      expect(
        CcApi.officialEntryUri(LiveArea.fromJson(official.toJson())).toString(),
        'https://cc.163.com/249133/?open=blizzardtv&from=8382&platform=ds',
      );
      for (final id in ['official:../file', 'official:0', 'official:https://example.test']) {
        expect(
          CcApi.officialEntryUri(LiveArea(platform: 'cc', areaId: id)),
          isNull,
          reason: id,
        );
      }
      expect(CcApi.officialEntryUri(const LiveArea(platform: 'huya', areaId: 'official:249133')), isNull);
      expect(CcApi.officialEntryUri(const LiveArea(platform: 'cc', areaId: '3')), isNull);
      expect(CcApi.isListableArea(official), isFalse);
      expect(CcApi.isListableArea(const LiveArea(platform: 'cc', areaId: '3', areaType: '2')), isTrue);
      expect(CcApi.isListableArea(const LiveArea(areaId: '3')), isTrue, reason: 'old records without a platform');
    });

    test('hidden entries are left out; a hidden or empty configuration is an empty catalog', () {
      final hidden = _config((_, entries) => (entries.first! as Map<String, dynamic>)['hidden'] = true);
      expect(CcApi.categories(games.body, hidden).expand((category) => category.children), hasLength(23));
      expect(CcApi.categories(games.body, _config((_, entries) => entries.clear())), isEmpty);
      expect(CcApi.categories(games.body, _config((root, _) => root['hidden'] = true)), isEmpty);
    });

    test('an irregular catalog fails whole, never partly (3.x)', () {
      final broken = {
        'foreign host': _config(
          (_, entries) => (entries.last! as Map<String, dynamic>)['content'] = 'https://example.test/123/',
        ),
        'plain http': _config(
          (_, entries) => (entries.last! as Map<String, dynamic>)['content'] = 'http://cc.163.com/123/',
        ),
        'unknown route': _config(
          (_, entries) => (entries.last! as Map<String, dynamic>)['content'] = 'https://cc.163.com/unrecognized/',
        ),
        'no game': _config((_, entries) => (entries.last! as Map<String, dynamic>)['name'] = 'missing-game'),
        'duplicate entry': _config((_, entries) => entries.add(entries.first)),
        'no live group': _config((root, _) => root['itemList'] = const <Object?>[]),
        'another configuration': _config((root, _) => root['id'] = 'x'),
      };
      for (final MapEntry(key: reason, value: body) in broken.entries) {
        expect(() => CcApi.categories(games.body, body), throwsA(isA<ApiChanged>()), reason: reason);
      }
      expect(() => CcApi.categories(games.body, '<html>migration</html>'), throwsA(isA<ApiChanged>()));
      expect(() => CcApi.categories('{"code":500}', config.body), throwsA(isA<ApiChanged>()));
      expect(() => CcApi.categories(games.body, config.body, configStatus: 503), throwsA(isA<NetworkFailure>()));
    });
  });

  group('S02 area rooms', () {
    for (final (name, gametype) in [
      ('S02-area-page1', '9141'),
      ('S02-area-beyond', '9141'),
      ('S02-area-empty', '65005'),
    ]) {
      test('$name matches 3.x', () {
        final fixture = _sample(name);
        final rooms = CcApi.categoryRooms(fixture.body, gametype: gametype, status: fixture.status);
        final legacy = _rooms(fixture.legacy);
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        for (final (index, room) in rooms.indexed) {
          _expectParity(_projection(room), legacy[index], reason: '$name[$index]');
        }
      });
    }

    test('heat and concurrent viewers stay apart (REG-CC-002)', () {
      final room = CcApi.categoryRooms(_sample('S02-area-page1').body, gametype: '9141').first;
      expect(room.popularity, '298945');
      expect(room.onlineViewers, '716');
      expect(room.watching, '298945');
      expect(room.effectiveAudienceMetricType, AudienceMetricType.popularity);
      expect(room.audienceValue(preferRealOnline: true, platformEnabled: true), '716');
    });

    test('a "【重播】" rebroadcast stays live, as 3.x showed it', () {
      final rooms = CcApi.categoryRooms(_sample('S02-area-page1').body, gametype: '9141');
      final replay = rooms.firstWhere((room) => room.roomId == '351834961');
      expect(replay.title, startsWith('【重播】'));
      expect(replay.isLiveNow, isTrue);
    });

    test('status 1 live, 0 offline, anything else unknown; videos are not rooms', () {
      final body = jsonEncode({
        'gametype': '3',
        'lives': [
          for (final (id, status) in [('101', 1), ('102', 0), ('103', 99)])
            {'cuteid': id, 'status': status, 'webcc_visitor': 800, 'vision_visitor': 7, 'gamename': 'Game'},
        ],
        'videos': [
          {'cuteid': '999'},
        ],
      });
      final rooms = CcApi.categoryRooms(body, gametype: '3');
      expect(rooms.map((room) => room.effectiveLiveStatus), [LiveStatus.live, LiveStatus.offline, LiveStatus.unknown]);
      expect(rooms.first.area, 'Game', reason: 'gamename when game_name is missing');
    });

    test('a failed or mismatched answer is ApiChanged, not a short page (3.x)', () {
      for (final bad in <Object?>[
        '<!DOCTYPE html>',
        {'error': 'fixture'},
        {'gametype': 4, 'lives': <Object?>[]},
        {'gametype': 3, 'lives': <String, Object?>{}},
        {
          'gametype': 3,
          'lives': [null],
        },
        {
          'gametype': 3,
          'lives': [
            {'cuteid': null},
          ],
        },
      ]) {
        final body = bad is String ? bad : jsonEncode(bad);
        expect(() => CcApi.categoryRooms(body, gametype: '3'), throwsA(isA<ApiChanged>()), reason: body);
      }
      expect(() => CcApi.categoryRooms('', gametype: '3', status: 503), throwsA(isA<NetworkFailure>()));
    });
  });

  group('S03 recommend', () {
    for (final name in ['S03-live-page1', 'S03-live-last', 'S03-live-beyond']) {
      test('$name matches 3.x', () {
        final fixture = _sample(name);
        final rooms = CcApi.recommendRooms(fixture.body, status: fixture.status);
        final legacy = _rooms(fixture.legacy);
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        for (final (index, room) in rooms.indexed) {
          _expectParity(_projection(room), legacy[index], reason: '$name[$index]');
          expect(room.isLiveNow, isTrue);
        }
      });
    }

    test('no area, as 3.x showed: the rows carry only gamename, 3.x read game_name', () {
      final fixture = _sample('S03-live-page1');
      final raw = (_json(fixture.body)['lives'] as List).cast<Map<String, dynamic>>();
      expect(raw.every((row) => row['game_name'] == null && row['gamename'] != null), isTrue);
      expect(CcApi.recommendRooms(fixture.body).every((room) => room.area!.isEmpty), isTrue);
    });

    test('rows without a cuteid are skipped (3.x wrote the room id "null")', () {
      final rooms = CcApi.recommendRooms(
        jsonEncode({
          'lives': [
            {'title': 'x'},
            {'cuteid': 5, 'title': 't', 'hot_score': 10},
          ],
        }),
      );
      expect(rooms.single.roomId, '5');
      expect(rooms.single.cover, '');
      expect(() => CcApi.recommendRooms('{}'), throwsA(isA<ApiChanged>()));
    });
  });

  group('S04 search', () {
    for (final name in ['S04-search-page1', 'S04-search-empty', 'S04-search-beyond']) {
      test('$name matches 3.x', () {
        final fixture = _sample(name);
        final rooms = CcApi.searchRooms(fixture.body, status: fixture.status);
        final legacy = (fixture.legacy as Map<String, dynamic>)['searchRooms'] as List;
        expect(rooms, hasLength(legacy.length));
        for (final (index, room) in rooms.indexed) {
          _expectParity(_projection(room), legacy[index] as Map<String, dynamic>, reason: '$name[$index]');
        }
        final anchors = (fixture.legacy as Map<String, dynamic>)['searchAnchors'] as List;
        expect([
          for (final room in rooms)
            {'roomId': room.roomId, 'avatar': room.avatar, 'userName': room.nick, 'liveStatus': room.isLiveNow},
        ], anchors);
      });
    }

    test('live and offline streamers; the portrait is the card image, followers the audience (3.x)', () {
      final rooms = CcApi.searchRooms(_sample('S04-search-page1').body);
      expect(rooms, hasLength(20));
      expect(rooms.where((room) => room.isLiveNow), hasLength(4));
      final offline = rooms.firstWhere((room) => room.roomId == '700700');
      expect(offline.isExplicitlyOfflineNow, isTrue);
      expect(offline.cover, offline.avatar);
      expect(offline.effectiveAudienceMetricType, AudienceMetricType.followers);
      expect(offline.watching, offline.followers);
    });
  });

  group('S05 detail', () {
    for (final (name, lives, ccid) in [
      ('S05-channel-live', 'S05-lives-live', '341438909'),
      ('S05-channel-replay', 'S05-lives-replay', '732923115'),
    ]) {
      test('$name: the room, its qualities and URLs match 3.x', () {
        final channel = CcApi.liveChannel(_sample(lives).body, ccid: ccid);
        final fixture = _sample(name);
        expect(fixture.url.queryParameters['channelids'], channel);
        final room = CcApi.channelRoom(fixture.body, ccid: ccid, status: fixture.status)!;
        final legacy = fixture.legacy as Map<String, dynamic>;
        for (final key in ['getRoomDetailForRefresh', 'getRoomDetail']) {
          // link: the room page; 3.x kept its redirect playlist there, only
          // to build stream URLs from (now CcRoomData.playlist).
          _expectParity(_projection(room), legacy[key] as Map<String, dynamic>, changed: {'link'}, reason: name);
        }
        final row = (_json(fixture.body)['data'] as List).cast<Map<String, dynamic>>().single;
        final data = room.data! as CcRoomData;
        expect(room.link, 'https://cc.163.com/$ccid/');
        expect(data.playlist, row['m3u8']);
        expect(room.userId, fixture.url.queryParameters['channelids'], reason: 'cc://join-room/{ccid}/{cid}/');
        expect(room.isLiveNow, isTrue, reason: 'a 【重播】 channel stays live, as in 3.x');
        expect([
          for (final quality in CcApi.legacyQualities(data))
            {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort, 'getPlayUrls': quality.data},
        ], legacy['getPlayQualites']);
      });
    }

    test('an offline anchor: 3.x failed (状态未知); refreshes mark it offline (REG-CC-003)', () {
      final lives = _sample('S05-lives-offline');
      final legacy = lives.legacy as Map<String, dynamic>;
      expect((legacy['getRoomDetailForRefresh'] as Map<String, dynamic>)['throws'], 'RangeError');
      expect((legacy['getRoomDetail'] as Map<String, dynamic>)['liveStatus'], LiveStatus.unknown.index);
      expect(CcApi.liveChannel(lives.body, ccid: '376267758'), isNull);
      expect(CcApi.channelRoom(_sample('S05-channel-null').body, ccid: '376267758'), isNull);
      final refreshed = CcApi.offlineRoom('376267758');
      expect(refreshed.isExplicitlyOfflineNow, isTrue);
      final stored = LiveRoom(roomId: '376267758', platform: 'cc', nick: '路人7758', watching: '12', title: 't');
      final merged = stored.mergeFrom(refreshed);
      expect((merged.nick, merged.title, merged.watching), ('路人7758', 't', '12'), reason: 'the card keeps the rest');
      expect(merged.isExplicitlyOfflineNow, isTrue);
    });

    test('an offline anchor on room entry: the room page fills the room', () {
      final room = CcApi.pageRoom(_sample('S05-page-offline').body, ccid: '376267758');
      expect(room.roomId, '376267758');
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.nick, '路人7758');
      expect(room.title, '路人7758的直播');
      expect(room.area, '其他游戏');
      expect(room.avatar, 'http://cc.res.netease.com/webcc/portrait/nsep/22_v2');
      expect(room.userId, '6734256');
      expect(room.watching, '39802', reason: "3.x's rule without heat or viewers: the followers");
      expect(room.effectiveAudienceMetricType, AudienceMetricType.followers);
      expect(room.notice, isNull, reason: 'empty announcement');
      expect(room.data, isNull);
    });

    test('an unknown anchor: 3.x showed an error room; the room page says NotFound', () {
      final lives = _sample('S05-lives-missing');
      final legacy = lives.legacy as Map<String, dynamic>;
      expect((legacy['getRoomDetail'] as Map<String, dynamic>)['liveStatus'], LiveStatus.unknown.index);
      expect(CcApi.liveChannel(lives.body, ccid: '88888888888'), isNull);
      expect(() => CcApi.pageRoom(_sample('S05-page-missing').body, ccid: '88888888888'), throwsA(isA<NotFound>()));
    });

    test('channel and page errors are typed', () {
      expect(() => CcApi.liveChannel('{"code":"BAD_REQUEST"}', ccid: 'abc', status: 400), throwsA(isA<NotFound>()));
      expect(() => CcApi.liveChannel('{"code":"ERR","data":{}}', ccid: '1'), throwsA(isA<ApiChanged>()));
      expect(() => CcApi.liveChannel('{"code":"OK","data":{}}', ccid: '1'), throwsA(isA<ApiChanged>()));
      final live = _sample('S05-channel-live').body;
      expect(() => CcApi.channelRoom(live, ccid: '1'), throwsA(isA<ApiChanged>()), reason: 'another anchor');
      final ended = live.replaceFirst('"status": 1,', '"nolive": 1, "status": 1,');
      expect(ended, isNot(live));
      expect(CcApi.channelRoom(ended, ccid: '341438909'), isNull, reason: 'the broadcast ended in between');
      expect(() => CcApi.pageRoom('<html></html>', ccid: '1'), throwsA(isA<ApiChanged>()));
      final offline = _sample('S05-page-offline').body;
      expect(() => CcApi.pageRoom(offline, ccid: '1'), throwsA(isA<ApiChanged>()), reason: 'another anchor');
      expect(() => CcApi.pageRoom(offline, ccid: '376267758', status: 502), throwsA(isA<NetworkFailure>()));
    });
  });

  group("3.x's streams", () {
    CcRoomData data() => CcApi.channelRoom(_sample('S05-channel-live').body, ccid: '341438909')!.data! as CcRoomData;

    test('every tier leads to the one redirect playlist, as 3.x played it (REG-CC-004 kept)', () {
      final qualities = CcApi.legacyQualities(data());
      expect(qualities.map((quality) => quality.quality), ['原画', '高清', '标准', '低清']);
      const base = 'http://cgi.v.cc.163.com/redirect/video/341438909.m3u8?secret=bac6536f08';
      for (final quality in qualities) {
        expect(
          (quality.data! as List).every((url) => '$url'.startsWith('$base&')),
          isTrue,
          reason: '${quality.id}: the same playlist with the tier’s signature appended, which the site ignores',
        );
      }
    });

    test('lines: the URLs with 3.x media headers, HLS, the quality assumed applied', () {
      final quality = CcApi.legacyQualities(data()).first;
      final resolution = CcApi.legacyResolution(quality, roomId: '341438909');
      expect(resolution.urls, quality.data);
      expect(resolution.appliedQualityData, 'original');
      for (final line in resolution.lines) {
        expect(line.headers, {
          'user-agent': CcApi.userAgent,
          'origin': 'https://cc.163.com',
          'referer': 'https://cc.163.com/341438909/',
        });
        expect(line.format, StreamFormat.hls);
        expect(line.lease, isNull);
      }
    });

    test('a quickplay object lists its own URLs; tiers without URLs are left out; unknown tiers by bitrate', () {
      final qualities = CcApi.legacyQualities(
        const CcRoomData(
          streams: {
            'resolution': {
              'high': {
                'vbr': 2000,
                'cdn': {'xx': 'https://x.test/b.flv', 'ali': '//a.test/a.flv'},
              },
              'custom': {
                'vbr': 3000,
                'cdn': {'ali': 'https://a.test/c.flv'},
              },
              'low': {'vbr': 500, 'cdn': <String, Object?>{}},
            },
          },
        ),
      );
      expect(qualities.map((quality) => (quality.id, quality.quality)), [('high', '高清'), ('custom', 'custom')]);
      expect(qualities.first.data, ['https://a.test/a.flv', 'https://x.test/b.flv'], reason: 'ali before others');
      expect(CcApi.legacyQualities(const CcRoomData()), isEmpty);
    });
  });

  group('S06 fallback streams (video_play_url)', () {
    test('one stream per tier, named by the site', () {
      final qualities = CcApi.qualities(CcApi.playData(_sample('S06-play-default').body));
      expect(
        [for (final quality in qualities) (quality.quality, quality.id, quality.data, quality.sort)],
        [
          ('原画', 'original', 'original', 4),
          ('超清', 'ultra', 'ultra', 3),
          ('高清', 'high', 'high', 2),
          ('标清', 'standard', 'standard', 1),
        ],
      );
    });

    test('the default answer: lines on cdn_sel and bakcdn_sel, media headers, FLV and a lease (REG-CC-005)', () {
      final fixture = _sample('S06-play-default');
      final data = CcApi.playData(fixture.body, status: fixture.status);
      expect(CcApi.uncoveredCdns(data), isEmpty);
      final resolution = CcApi.resolution([(data: data, issuedAt: fixture.capturedAt)], roomId: '341438909');
      expect(resolution.appliedQualityData, 'original');
      expect(resolution.qualityUnconfirmed, isFalse);
      expect(resolution.lines.map((line) => line.lineId), ['hs', 'ali']);
      expect(resolution.urls, [data['videourl'], data['bakvideourl']]);
      for (final line in resolution.lines) {
        expect(line.headers, CcApi.mediaHeaders('341438909'));
        expect(line.format, StreamFormat.flv);
        final lease = line.lease!;
        final expiry = int.parse(Uri.parse(line.url).queryParameters['auth_key']!.split('-').first);
        expect(lease.expiresAt, DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true));
        expect(lease.expiresAt!.difference(fixture.capturedAt).inSeconds, inInclusiveRange(290, 300));
        expect(lease.expiresAt!.difference(lease.refreshAt), CcApi.leaseLead);
        expect(lease.cutsConnection, isFalse, reason: 'an established connection outlives the key');
      }
    });

    test('a requested tier is confirmed; a CDN the server answers with another adds no line', () {
      final high = _sample('S06-play-high');
      final hs = _sample('S06-play-high-hs');
      expect(hs.url.queryParameters['cdn'], 'hs');
      final resolution = CcApi.resolution([
        (data: CcApi.playData(high.body), issuedAt: high.capturedAt),
        (data: CcApi.playData(hs.body), issuedAt: hs.capturedAt),
      ], roomId: '341438909');
      expect(resolution.appliedQualityData, 'high');
      expect(resolution.lines.map((line) => line.lineId), ['ali']);
      expect(Uri.parse(resolution.urls.single).path, endsWith('tc2.flv'));
      final shown = resolveAppliedPlayQuality(
        qualities: CcApi.qualities(CcApi.playData(high.body)),
        requested: const LivePlayQuality(quality: '高清', id: 'high', data: 'high'),
        resolution: resolution,
      );
      expect(shown.quality, '高清');
      expect(shown.isPlaybackUnconfirmed, isFalse);
    });

    test('a CDN answer at another tier is dropped', () {
      final base = _json(_sample('S06-play-default').body);
      final other = {...base, 'vbrname_sel': 'high', 'cdn_sel': 'ks', 'videourl': 'https://ks.test/a.flv'}
        ..remove('bakvideourl');
      final resolution = CcApi.resolution([
        (data: {...base}..remove('bakvideourl'), issuedAt: DateTime.utc(2026)),
        (data: other, issuedAt: DateTime.utc(2026)),
      ], roomId: '1');
      expect(resolution.lines.map((line) => line.lineId), ['hs']);
    });

    test('an anchor without a stream is 410 Gone: StreamUnavailable', () {
      final fixture = _sample('S06-play-offline');
      expect(() => CcApi.playData(fixture.body, status: fixture.status), throwsA(isA<StreamUnavailable>()));
      expect(() => CcApi.playData('<html>', status: 404), throwsA(isA<StreamUnavailable>()));
      expect(() => CcApi.playData('', status: 502), throwsA(isA<NetworkFailure>()));
      expect(
        () => CcApi.resolution([(data: <String, dynamic>{}, issuedAt: DateTime.utc(2026))], roomId: '1'),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('qualities fall back to vbrname_sel; unnamed tiers keep 3.x names or their code', () {
      expect(CcApi.qualities({'vbrname_sel': 'high'}).single.quality, '高清');
      expect(CcApi.qualities({'vbrname_sel': 'medium'}).single.quality, '标准');
      expect(
        CcApi.qualities({
          'vbrname_list': ['blueray_5M_avc'],
        }).single.quality,
        'blueray_5M_avc',
      );
      expect(() => CcApi.qualities(const {}), throwsA(isA<ApiChanged>()));
    });

    test('leases: none without auth_key or when past; a short life renews at a quarter', () {
      final issued = DateTime.utc(2026, 9, 27, 12);
      final seconds = issued.millisecondsSinceEpoch ~/ 1000;
      expect(CcApi.lease(Uri.parse('https://x.test/a.flv'), issued), isNull);
      expect(CcApi.lease(Uri.parse('https://x.test/a.flv?auth_key=${seconds - 1}-r-0-h'), issued), isNull);
      final lease = CcApi.lease(Uri.parse('https://x.test/a.flv?auth_key=${seconds + 100}-r-0-h'), issued)!;
      expect(lease.expiresAt!.difference(lease.refreshAt), const Duration(seconds: 25));
      expect(CcApi.mediaHeaders(' ')['referer'], 'https://cc.163.com/');
    });
  });
}
