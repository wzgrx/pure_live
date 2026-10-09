// Huya parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json). Every intended difference is listed
// with its reason; everything else must match. The signing and Tars vectors
// were computed by running 3.x (HuyaSite.buildAntiCode, BaseTarsHttp).
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('huya', name);

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
    if (changed.contains(key) || key == 'danmakuData') continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
}

Uint8List _hex(String hex) =>
    Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);

String _fm(String template) => Uri.encodeComponent(base64Encode(utf8.encode(template)));

String _wsTime(DateTime time) => (time.millisecondsSinceEpoch ~/ 1000).toRadixString(16);

/// S05-multicdn's streamer and a stream name prefix used by 3.x vectors.
const _presenter = 1346609715;
const _vectorStream = '78941969-2559461593-10992803837303062528';

HuyaLine _line(StreamFormat format, String base, {String antiCode = 'wsSecret=token&wsTime=6a87f351'}) => HuyaLine(
  cdnType: 'AL',
  format: format,
  base: HuyaApi.secureBase(base),
  streamName: 'stream-name',
  antiCode: antiCode,
  presenterUid: 123,
);

void main() {
  group('S01 categories', () {
    for (final (name, id) in [('S01-buss1', '1'), ('S01-buss2', '2'), ('S01-buss8', '8'), ('S01-buss3', '3')]) {
      test('$name: names, ids and areas match 3.x', () {
        final fixture = _sample(name);
        final legacy = fixture.legacy as Map<String, dynamic>;
        final top = HuyaApi.topCategories.singleWhere((category) => category.id == id);
        expect((top.id, top.name), (legacy['id'], legacy['name']));
        final areas = HuyaApi.areas(fixture.body, categoryId: id, categoryName: top.name, status: fixture.status);
        final children = (legacy['children'] as List).cast<Map<String, dynamic>>();
        expect(areas, hasLength(children.length));
        for (final (index, area) in areas.indexed) {
          _expectParity(area.toJson(), children[index], reason: '$name[$index]');
        }
      });
    }

    test('a gid written as 2165.0 is the area id "2165"', () {
      final fixture = _sample('S01-buss2');
      expect(fixture.body, contains('"gid": 2793.0'));
      final area = HuyaApi.areas(fixture.body, categoryId: '2', categoryName: '单机').first;
      expect(area.areaId, '2793');
      expect(area.areaPic, 'https://huyaimg.msstatic.com/cdnimage/game/2793-MS.jpg');
    });

    test('the four top-level categories in platform order', () {
      expect(HuyaApi.topCategories.map((category) => category.id), ['1', '2', '8', '3']);
    });
  });

  group('S02/S03 room lists', () {
    for (final (name, more) in [
      ('S02-page1', true),
      ('S02-page2', true),
      ('S02-last', false),
      ('S02-beyond', false),
      ('S03-hot-page1', true),
      ('S03-hot-page2', true),
      ('S03-cold-page1', false),
      ('S03-cold-page2', false),
    ]) {
      test('$name: same rooms in the same order as 3.x', () {
        final fixture = _sample(name);
        final page = int.parse(fixture.url.queryParameters['page']!);
        final result = HuyaApi.roomList(fixture.body, page: page, status: fixture.status);
        final legacy = ((fixture.legacy as Map)['rooms'] as List).cast<Map<String, dynamic>>();
        expect(result.rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        for (final (index, room) in result.rooms.indexed) {
          _expectParity(room.toJson(), legacy[index], reason: '$name[$index]');
          expect(room.onlineViewers, isEmpty, reason: 'totalCount is heat, never a head count (REG-HUYA-014)');
          expect(room.audienceMetricType, AudienceMetricType.popularity);
          // M2.1 fields, outside the keys 3.x wrote: every recorded card has
          // isRoomPay "0"; lists carry no start time.
          expect((room.restriction, room.startedAt), (LiveRestriction.none, null), reason: '$name[$index]');
        }
        expect(result.hasMore, more, reason: 'totalPage, or an empty page past the end');
      });
    }

    test('isRoomPay marks a paid card, still live; a card without the flag leaves it unknown (M2.1)', () {
      final body = jsonEncode({
        'status': 200,
        'data': {
          'totalPage': 1,
          'datas': [
            {'profileRoom': '1', 'isRoomPay': '1', 'roomPayTag': '付费'},
            {'profileRoom': '2', 'isRoomPay': true},
            {'profileRoom': '3', 'isRoomPay': '0'},
            {'profileRoom': '4'},
          ],
        },
      });
      final rooms = HuyaApi.roomList(body, page: 1).rooms;
      expect(rooms.map((room) => room.restriction), [
        LiveRestriction.paid,
        LiveRestriction.paid,
        LiveRestriction.none,
        null,
      ]);
      expect(rooms.every((room) => room.isLiveNow && room.followGroup == FollowGroup.live), isTrue);
      expect(rooms.first.isRestricted, isTrue);
    });

    test('a cover without a query gets the thumbnail style; a missing one stays empty', () {
      final body = jsonEncode({
        'status': 200,
        'data': {
          'totalPage': 1,
          'datas': [
            {'profileRoom': '1', 'screenshot': 'https://a.msstatic.com/c.jpg', 'introduction': '', 'roomName': 'r'},
            {'profileRoom': '2', 'screenshot': null},
            {'profileRoom': null},
          ],
        },
      });
      final rooms = HuyaApi.roomList(body, page: 1).rooms;
      expect(rooms.map((room) => room.cover), ['https://a.msstatic.com/c.jpg?x-oss-process=style/w338_h190&', '']);
      expect(rooms.first.title, 'r', reason: 'the room name when there is no introduction');
    });
  });

  group('S04 search', () {
    for (final name in ['S04-results', 'S04-fallback', 'S04-empty']) {
      test('$name matches 3.x', () {
        final fixture = _sample(name);
        final query = fixture.url.queryParameters;
        final rooms = HuyaApi.searchRooms(
          fixture.body,
          start: int.parse(query['start']!),
          rows: int.parse(query['rows']!),
          status: fixture.status,
        );
        final legacy = ((fixture.legacy as Map)['rooms'] as List).cast<Map<String, dynamic>>();
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        for (final (index, room) in rooms.indexed) {
          _expectParity(room.toJson(), legacy[index], reason: '$name[$index]');
          // The search docs tell neither (M2.1): unknown, not "none".
          expect((room.restriction, room.startedAt), (null, null), reason: '$name[$index]');
        }
      });
    }

    test('S04-page2: the repeated first page is dropped (3.x showed all 40 docs)', () {
      final fixture = _sample('S04-page2');
      final legacy = ((fixture.legacy as Map)['rooms'] as List).cast<Map<String, dynamic>>();
      expect(legacy, hasLength(40));
      final rooms = HuyaApi.searchRooms(fixture.body, start: 20, rows: 20);
      final firstPage = legacy.take(20).map((room) => room['roomId']).toSet();
      final expected = legacy.skip(20).where((room) => !firstPage.contains(room['roomId'])).toList();
      expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']));
      for (final (index, room) in rooms.indexed) {
        _expectParity(room.toJson(), expected[index], reason: 'S04-page2[$index]');
      }
    });

    test('the room id comes from the streamer entry with the same uid and yyid', () {
      final body = jsonEncode({
        'response': {
          '1': {
            'docs': [
              {'uid': 7, 'yyid': 8, 'room_id': 660000},
            ],
          },
          '3': {
            'docs': [
              {'uid': 7, 'yyid': 8, 'room_id': 1, 'game_nick': 'a'},
              {'uid': 7, 'yyid': 9, 'room_id': 2, 'game_nick': 'b'},
            ],
          },
        },
      });
      final rooms = HuyaApi.searchRooms(body, start: 0, rows: 20);
      expect(rooms.map((room) => room.roomId), ['660000', '2']);
      expect(rooms.map((room) => room.userId), ['8', '9']);
    });

    test('streamers (v=1): room, avatar, name and live flag', () {
      final anchors = HuyaApi.searchAnchors(
        jsonEncode({
          'response': {
            '1': {
              'docs': [
                {
                  'room_id': 660000,
                  'game_avatarUrl180': '//a.msstatic.com/x.jpg',
                  'game_nick': 'n',
                  'gameLiveOn': true,
                },
                {'room_id': 0, 'game_nick': 'no room'},
                {'room_id': '880351', 'game_nick': 'off', 'gameLiveOn': false},
              ],
            },
          },
        }),
      );
      expect(anchors.map((anchor) => (anchor.roomId, anchor.userName, anchor.liveStatus)), [
        ('660000', 'n', true),
        ('880351', 'off', false),
      ]);
      expect(anchors.first.avatar, 'https://a.msstatic.com/x.jpg');
    });
  });

  group('S05/S06 room detail', () {
    for (final (name, startedAt) in [
      ('S05-multicdn', DateTime.utc(2025, 12, 29, 20, 22, 10)),
      ('S05-xingxiu', DateTime.utc(2026, 9, 26, 16, 2, 1)),
      ('S05-ratearray', DateTime.utc(2026, 9, 27, 9, 35, 10)),
    ]) {
      test('$name: room, qualities and lines match 3.x', () {
        final fixture = _sample(name);
        final requested = fixture.url.queryParameters['roomid']!;
        final profile = HuyaApi.profile(fixture.body, requestedId: requested, status: fixture.status);
        final legacy = fixture.legacy as Map<String, dynamic>;
        _expectParity(profile.room.toJson(), legacy['getRoomDetail'] as Map<String, dynamic>, reason: name);
        _expectParity(profile.room.toJson(), legacy['getRoomDetailForRefresh'] as Map<String, dynamic>, reason: name);
        expect(profile.room.roomId, requested);
        expect(profile.room.isLiveNow, isTrue);
        expect(profile.hasStream, isTrue);
        // M2.1 fields, outside the keys 3.x wrote: liveData.startTime (Unix
        // seconds) and the pay / secret flags (all clear here).
        expect(profile.room.startedAt, startedAt);
        expect(profile.room.restriction, LiveRestriction.none);
        expect(profile.room.toJson(), containsPair('startedAt', startedAt.toIso8601String()));
        expect(profile.replay, isNull);

        expect(
          [
            for (final quality in profile.qualities)
              {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort},
          ],
          [
            for (final quality in (legacy['parsePlayQualities'] as List).cast<Map<String, dynamic>>())
              {'quality': quality['quality'], 'id': quality['id'], 'sort': quality['sort']},
          ],
        );
        expect(profile.qualities.map((quality) => quality.data), profile.qualities.map((quality) => quality.id));

        final lines = ((legacy['data'] as Map)['lines'] as List).cast<Map<String, dynamic>>();
        expect(
          [
            for (final line in profile.lines)
              [line.cdnType, line.format.name, line.base, line.streamName, line.presenterUid, line.antiCode],
          ],
          [
            for (final line in lines)
              [
                line['cdnType'],
                line['lineType'],
                line['secureHuyaCdnBase'],
                line['streamName'],
                line['presenterUid'],
                line[line['lineType'] == 'flv' ? 'flvAntiCode' : 'hlsAntiCode'],
              ],
          ],
        );

        final danmaku = jsonDecode((legacy['getRoomDetail'] as Map)['danmakuData'] as String) as Map;
        expect(profile.presenterUid, danmaku['uid']);
        if (name == 'S05-ratearray') {
          // 3.x took the channels from the last line matched in multiLine;
          // this live room has none, so it lost the message board. They come
          // from baseSteamInfoList (every CDN has the same ids) or chTopId now.
          expect((danmaku['topSid'], danmaku['subSid']), (0, 0));
          expect((profile.topSid, profile.subSid), (1319535174649, 1319535174649));
        } else {
          expect((profile.topSid, profile.subSid), (danmaku['topSid'], danmaku['subSid']));
        }
      });
    }

    test('S05-ratearray: live with a stream but no multiLine has no line; its rate comes from rateArray', () {
      final profile = HuyaApi.profile(_sample('S05-ratearray').body, requestedId: '30925595');
      expect(profile.lines, isEmpty);
      expect(profile.qualities.single.quality, '蓝光');
    });

    test('S06-off matches 3.x on room entry, recording and refresh', () {
      final fixture = _sample('S06-off');
      final legacy = fixture.legacy as Map<String, dynamic>;
      final profile = HuyaApi.profile(fixture.body, requestedId: '441195', status: fixture.status);
      for (final entry in ['getRoomDetail', 'getRoomDetailForRecording', 'getRoomDetailForRefresh']) {
        _expectParity(profile.room.toJson(), (legacy[entry] as Map)['value'] as Map<String, dynamic>, reason: entry);
      }
      expect(profile.room.isExplicitlyOfflineNow, isTrue);
      expect(profile.hasStream, isFalse);
      expect(profile.lines, isEmpty);
      expect(profile.qualities, isEmpty);
      expect(profile.topSid, isPositive, reason: 'chTopId: offline rooms have no baseSteamInfoList');
      // liveData.startTime is the last broadcast's; an offline room has no
      // start time and no restriction (M2.1).
      expect((profile.room.startedAt, profile.room.restriction, profile.replay), (null, null, null));
    });

    test('S06-replay is a replay as 3.x refreshed it, on every entry point, and plays its recording (3-1)', () {
      final fixture = _sample('S06-replay');
      final legacy = fixture.legacy as Map<String, dynamic>;
      final profile = HuyaApi.profile(fixture.body, requestedId: '102411', status: fixture.status);
      _expectParity(
        profile.room.toJson(),
        (legacy['getRoomDetailForRefresh'] as Map)['value'] as Map<String, dynamic>,
        reason: 'S06-replay',
      );
      // 3.x's room entry gave an error room (unknown) and its recording
      // detail a FormatException for the same answer; both are the replay
      // room now.
      expect(((legacy['getRoomDetail'] as Map)['value'] as Map)['liveStatus'], LiveStatus.unknown.index);
      expect((legacy['getRoomDetailForRecording'] as Map)['error'], 'FormatException');
      expect(profile.room.effectiveLiveStatus, LiveStatus.replay);
      expect(profile.room.isRecord, isTrue);
      expect(profile.room.isLiveNow, isFalse);
      expect(profile.hasStream, isFalse);
      expect(profile.lines, isEmpty);
      // 3-1: liveData.hls is the recording (3.x never played it). The room
      // stays in the replay group, playable, without a start time.
      const recording =
          'https://videotx-platform.cdn.huya.com/vhuya/danmu/liverecord/679257140/'
          '7bcaab29-46d5-4127-945f-4110189e671f.m3u8?bitrate=0&client=81&definition=350&pid=679257140'
          '&scene=livereplay&vid=1126494362&hyvid=1126494362&hyauid=679257140&hyroomid=0&hyratio=0'
          '&hyscence=livereplay&appid=66&domainid=41&srckey=YfEmSCSkFIYrUpW8CZY5Ig%3D%3D&';
      expect(profile.replay!.url, recording);
      expect(profile.replay!.videoId, 1126494362);
      expect(profile.replay.toString(), 'HuyaReplay(1126494362)', reason: 'no srckey in diagnostics');
      expect(profile.room.restriction, LiveRestriction.none);
      expect(profile.room.followGroup, FollowGroup.replay);
      expect(profile.room.startedAt, isNull);
      expect(profile.qualities.map((quality) => (quality.quality, quality.id, quality.data)), [
        ('360P', '350', recording),
      ], reason: 'the definition profileRoom names, until getMomentContent lists the others');
    });

    test('a replay without a recording is unplayable and grouped with offline rooms (3-1, M2.1)', () {
      final data = (jsonDecode(_sample('S06-replay').body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      final live = data['liveData'] as Map<String, dynamic>;
      String wrapped() => jsonEncode({'status': 200, 'message': '', 'data': data});

      live['hls'] = null;
      final fromHlsUrl = HuyaApi.profile(wrapped(), requestedId: '102411');
      expect(fromHlsUrl.replay!.videoId, 1126494362, reason: 'hlsUrl when hls is missing');

      for (final (hlsUrl, why) in [
        (null, 'no recording'),
        ('', 'blank'),
        ('https://videotx-platform.cdn.huya.com/vhuya/x.mp4', 'not a playlist'),
        ('rtmp://videotx-platform.cdn.huya.com/x.m3u8', 'not http'),
      ]) {
        live['hlsUrl'] = hlsUrl;
        final profile = HuyaApi.profile(wrapped(), requestedId: '102411');
        expect(profile.room.effectiveLiveStatus, LiveStatus.replay, reason: why);
        expect(profile.room.restriction, LiveRestriction.unplayable, reason: why);
        expect(profile.room.followGroup, FollowGroup.offline, reason: why);
        expect(profile.room.isPlayableNow, isTrue, reason: 'entry explains why it cannot play (M2.1)');
        expect(profile.replay, isNull, reason: why);
        expect(profile.qualities, isEmpty, reason: why);
      }
    });

    test('a live room: isRoomPay is paid, isSecret a password, both paid; no flag is unknown (M2.1)', () {
      Map<String, dynamic> liveData() =>
          (jsonDecode(_sample('S05-ratearray').body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      String wrapped(Map<String, dynamic> data) => jsonEncode({'status': 200, 'message': '', 'data': data});
      LiveRestriction? restriction(void Function(Map<String, dynamic> data, Map<String, dynamic> live) edit) {
        final data = liveData();
        edit(data, data['liveData'] as Map<String, dynamic>);
        return HuyaApi.profile(wrapped(data), requestedId: '30925595').room.restriction;
      }

      expect(restriction((data, live) => data['isRoomPay'] = true), LiveRestriction.paid);
      expect(restriction((data, live) => live['isRoomPay'] = '1'), LiveRestriction.paid);
      expect(restriction((data, live) => data['isPayRoom'] = 1), LiveRestriction.paid);
      expect(restriction((data, live) => live['isSecret'] = 1), LiveRestriction.password);
      expect(
        restriction((data, live) {
          live['isSecret'] = 1;
          data['isRoomPay'] = true;
        }),
        LiveRestriction.paid,
        reason: 'the web player: isSecret && !isPayRoom',
      );
      expect(
        restriction((data, live) {
          data.remove('isRoomPay');
          live.remove('isSecret');
        }),
        isNull,
      );
      final paid = liveData()..['isRoomPay'] = true;
      final room = HuyaApi.profile(wrapped(paid), requestedId: '30925595').room;
      expect((room.isLiveNow, room.followGroup, room.isRestricted), (true, FollowGroup.live, true));
    });

    test('startedAt: liveData.startTime seconds, a numeric string too; 0 or missing is none (M2.1)', () {
      DateTime? startedAt(Object? value) {
        final data =
            (jsonDecode(_sample('S05-ratearray').body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
        (data['liveData'] as Map<String, dynamic>)['startTime'] = value;
        return HuyaApi.profile(
          jsonEncode({'status': 200, 'message': '', 'data': data}),
          requestedId: '30925595',
        ).room.startedAt;
      }

      expect(startedAt('1790501710'), DateTime.utc(2026, 9, 27, 9, 35, 10));
      expect(startedAt(0), isNull);
      expect(startedAt(null), isNull);
      expect(startedAt('soon'), isNull);
    });

    test('S06-notfound and S06-alias (status 422) are NotFound (3.x: an error room or FormatException)', () {
      for (final (name, id) in [('S06-notfound', '999999999'), ('S06-alias', 'lpl')]) {
        final fixture = _sample(name);
        final legacy = fixture.legacy as Map<String, dynamic>;
        expect(((legacy['getRoomDetail'] as Map)['value'] as Map)['liveStatus'], LiveStatus.unknown.index);
        expect((legacy['getRoomDetailForRefresh'] as Map)['error'], 'FormatException');
        expect(
          () => HuyaApi.profile(fixture.body, requestedId: id, status: fixture.status),
          throwsA(isA<NotFound>()),
          reason: name,
        );
      }
    });

    Map<String, dynamic> offBody() =>
        (jsonDecode(_sample('S06-off').body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    String wrap(Map<String, dynamic> data) => jsonEncode({'status': 200, 'message': '', 'data': data});

    test('liveStatus is trimmed and upper-cased; REPLAY is a replay; only OFF, OFFLINE, CLOSED are offline', () {
      for (final (raw, status) in [
        (' on ', LiveStatus.live),
        (' replay ', LiveStatus.replay),
        ('offline', LiveStatus.offline),
        ('CLOSED', LiveStatus.offline),
        ('OFF', LiveStatus.offline),
      ]) {
        final room = HuyaApi.profile(wrap(offBody()..['liveStatus'] = raw), requestedId: '441195').room;
        expect(room.effectiveLiveStatus, status, reason: raw);
      }
    });

    test('an unknown or missing liveStatus is ApiChanged, never offline (REG-HUYA-015)', () {
      for (final raw in ['PAUSE', null]) {
        expect(
          () => HuyaApi.profile(wrap(offBody()..['liveStatus'] = raw), requestedId: '441195'),
          throwsA(isA<ApiChanged>()),
        );
      }
    });

    test('the audience is popularity: totalCount, else userCount; never concurrent viewers (REG-HUYA-014)', () {
      final data = offBody();
      (data['liveData'] as Map<String, dynamic>)
        ..['totalCount'] = ''
        ..['userCount'] = '4200000';
      final room = HuyaApi.profile(wrap(data), requestedId: '441195').room;
      expect((room.popularity, room.watching, room.onlineViewers), ('4200000', '4200000', ''));
      expect(room.audienceMetricType, AudienceMetricType.popularity);
    });

    test('an introduction-less room takes the room name as its title (3.x left it empty)', () {
      final data = offBody();
      (data['liveData'] as Map<String, dynamic>)
        ..['introduction'] = ''
        ..['roomName'] = 'room name';
      expect(HuyaApi.profile(wrap(data), requestedId: '441195').room.title, 'room name');
    });

    test('errors are typed: 429, 5xx, other statuses, HTML, data that is not an object', () {
      expect(() => HuyaApi.profile('{}', requestedId: '1', status: 429), throwsA(isA<RateLimited>()));
      expect(() => HuyaApi.profile('', requestedId: '1', status: 502), throwsA(isA<NetworkFailure>()));
      expect(() => HuyaApi.profile('', requestedId: '1', status: 403), throwsA(isA<ApiChanged>()));
      expect(() => HuyaApi.profile('<html>', requestedId: '1'), throwsA(isA<ApiChanged>()));
      expect(() => HuyaApi.profile('{"status":500}', requestedId: '1'), throwsA(isA<ApiChanged>()));
      expect(() => HuyaApi.profile('{"status":200,"data":[]}', requestedId: '1'), throwsA(isA<ApiChanged>()));
      expect(() => HuyaApi.roomList('{"status":200,"data":{}}', page: 1), throwsA(isA<ApiChanged>()));
      expect(() => HuyaApi.searchRooms('{}', start: 0, rows: 20), throwsA(isA<ApiChanged>()));
    });
  });

  group('qualities', () {
    Map<String, dynamic> data({Object? bitRateInfo, List<Object?>? rateArray}) => {
      'liveData': {'bitRateInfo': ?bitRateInfo},
      'stream': {
        'flv': {'rateArray': ?rateArray},
      },
    };

    test('only advertised rates, stable ids, the source first; duplicates, negatives and blanks dropped', () {
      final qualities = HuyaApi.qualities(
        data(
          bitRateInfo: jsonEncode([
            {'sDisplayName': '超清', 'iBitRate': 2000},
            {'sDisplayName': '蓝光4M', 'iBitRate': 0},
            {'sDisplayName': '重复超清', 'iBitRate': 2000},
            {'sDisplayName': ' ', 'iBitRate': 1000},
            {'sDisplayName': '负数', 'iBitRate': -1},
            {'sDisplayName': '流畅', 'iBitRate': 500},
          ]),
        ),
      );
      expect(qualities.map((quality) => quality.quality), ['蓝光4M', '超清', '流畅']);
      expect(qualities.map((quality) => quality.selectionId), [0, 2000, 500]);
    });

    test('bitRateInfo as a list; missing or undecodable falls back to rateArray', () {
      final rates = [
        {'sDisplayName': '蓝光', 'iBitRate': 0},
      ];
      expect(HuyaApi.qualities(data(bitRateInfo: rates)).single.quality, '蓝光');
      expect(HuyaApi.qualities(data(bitRateInfo: '{bad', rateArray: rates)).single.quality, '蓝光');
      expect(HuyaApi.qualities(data(bitRateInfo: '', rateArray: rates)).single.quality, '蓝光');
    });

    test('no rate list gives one source quality, never an invented transcode (REG-HUYA-013)', () {
      final qualities = HuyaApi.qualities(data());
      expect(qualities.map((quality) => (quality.quality, quality.selectionId)), [('原画', 0)]);
    });
  });

  group('replay recordings (3-1)', () {
    test('S15-vod: the source as 原画, then 720P and 360P; ids are the definitions, data the https playlists', () {
      final fixture = _sample('S15-vod');
      final qualities = HuyaApi.replayQualities(fixture.body, status: fixture.status);
      expect(qualities.map((quality) => (quality.quality, quality.id)), [
        ('原画', 'yuanhua'),
        ('720P', '1300'),
        ('360P', '350'),
      ]);
      expect(qualities.map((quality) => quality.sort), [HuyaApi.sourceRank, 720, 360]);
      for (final quality in qualities) {
        final url = Uri.parse(quality.data! as String);
        expect((url.scheme, url.host), ('https', 'videotx-platform.cdn.huya.com'));
        expect(url.path, endsWith('.m3u8'));
        expect(url.queryParameters['vid'], '1126494362');
      }
      // The 360P definition is the recording profileRoom names (S06-replay):
      // same file and id, so the fallback quality and the full list agree.
      final replay = HuyaApi.profile(_sample('S06-replay').body, requestedId: '102411').replay!;
      expect(Uri.parse(qualities.last.data! as String).path, Uri.parse(replay.url).path);
      expect(HuyaApi.replayQuality(replay.url).selectionId, qualities.last.selectionId);
    });

    test('S15-vod-missing: an unknown video lists nothing; a status other than 200 is ApiChanged', () {
      final fixture = _sample('S15-vod-missing');
      expect(HuyaApi.replayQualities(fixture.body, status: fixture.status), isEmpty);
      expect(() => HuyaApi.replayQualities('{"status":404,"msg":"x"}'), throwsA(isA<ApiChanged>()));
      expect(() => HuyaApi.replayQualities('', status: 502), throwsA(isA<NetworkFailure>()));
    });

    test('definitions: blank or duplicated ones dropped; a definition without defName takes the known name', () {
      String entry(String definition, {String? name, int height = 0}) => jsonEncode({
        'defName': ?name,
        'height': '$height',
        'm3u8': 'http://videotx-platform.cdn.huya.com/r/$definition.m3u8?definition=$definition&vid=7',
      });
      final body =
          '{"status":200,"data":{"moment":{"videoInfo":{"definitions":['
          '${entry('350', height: 360)},${entry('1300', name: '720P', height: 720)},'
          '${entry('350', name: 'again', height: 360)},{"m3u8":""},{"url":"https://x.test/a.flv"},'
          '${entry('9000', name: '2K', height: 1440)}]}}}}';
      final qualities = HuyaApi.replayQualities(body);
      expect(qualities.map((quality) => (quality.quality, quality.id)), [
        ('2K', '9000'),
        ('720P', '1300'),
        ('360P', '350'),
      ]);
    });

    test('recording URLs: http(s) .m3u8 only; http on huya.com becomes https; other hosts are kept', () {
      expect(
        HuyaApi.replayUrl(' http://videoal-platform.cdn.huya.com/a/b.m3u8?definition=350&srckey=k%3D& '),
        'https://videoal-platform.cdn.huya.com/a/b.m3u8?definition=350&srckey=k%3D&',
      );
      expect(HuyaApi.replayUrl('http://vod.example/b.M3U8'), 'http://vod.example/b.M3U8');
      for (final value in [null, 350, '', 'https://x.huya.com/a.flv', 'ftp://x.huya.com/a.m3u8', '/a.m3u8']) {
        expect(HuyaApi.replayUrl(value), isNull, reason: '$value');
      }
    });

    test('the one quality of a recording: named by its definition, else 默认 with the label as its identity', () {
      final source = HuyaApi.replayQuality('https://v.huya.com/a.m3u8?definition=yuanhua');
      expect((source.quality, source.id, source.sort), ('原画', 'yuanhua', HuyaApi.sourceRank));
      final unknown = HuyaApi.replayQuality('https://v.huya.com/a.m3u8');
      expect((unknown.quality, unknown.id, unknown.selectionId), ('默认', null, '默认'));
      expect(HuyaApi.replayQuality('https://v.huya.com/a.m3u8?definition=1300').quality, '720P');
    });
  });

  group('signing (3.x buildAntiCode vectors)', () {
    const vectors = [
      (
        antiCode: 'wsSecret=stale&wsTime=6b49d278&fm=cHJlZml4XyQwXyQxXyQyXyQz&ctype=huya_live&fs=bgct&t=100&codec=264',
        stream: 'stream-name',
        uid: 1400123456789,
        now: 1800000000000,
        signed:
            'wsTime=6b49d278&ctype=huya_live&fs=bgct&t=100&codec=264&wsSecret=461723da82a735de0c2299b561428ec2'
            '&seqid=3200123456789&ver=1&u=1399563556349',
      ),
      (
        antiCode:
            'wsTime=6b49d278&fm=cHJlZml4LXYyfCQxfHZpZXdlcj0kMHxoYXNoPSQyfGxlYXNlPSQzfHRhaWw%3D&ctype=huya_live'
            '&t=100&codec=264',
        stream: 'stream-name',
        uid: 1400123456789,
        now: 1800000000000,
        signed:
            'wsTime=6b49d278&ctype=huya_live&t=100&codec=264&wsSecret=74fa5368c8966e5e6d007a6acfd3f941'
            '&seqid=3200123456789&ver=1&fs=bgct&u=1399563556349',
      ),
      (
        antiCode: 'wsTime=6b49d278&fm=cHJlZml4XyQwXyQxXyQyXyQz&t=100',
        stream: 'stream-name',
        uid: 1471259343403,
        now: 1800000000000,
        signed:
            'wsTime=6b49d278&t=100&wsSecret=4ebc14c64af251c9798fda4926b9da4d&seqid=3271259343403'
            '&ctype=huya_webh5&ver=1&fs=bgct&u=1472703638413',
      ),
      (
        antiCode:
            'wsSecret=30f2c946b62c16182f518a97aeae1fe4&wsTime=6aba3701'
            '&fm=RFdxOEJjSjNoNkRKdDZUWV8kMF8kMV8kMl8kMw%3D%3D&ctype=tars_mp&fs=bgct&t=102',
        stream: _vectorStream,
        uid: _presenter,
        now: 1790502272850,
        signed:
            'wsTime=6aba3701&ctype=tars_mp&fs=bgct&t=102&wsSecret=aef6026e05937ac844020a139aca4dc9'
            '&seqid=1791848882565&ver=1&u=1134703440',
      ),
      (
        antiCode: 'wsTime=6aba3701&fm=bmF0aXZlXyQwXyQxXyQyXyQz&ctype=huya_pc_exe&t=100',
        stream: _vectorStream,
        uid: _presenter,
        now: 1790502272850,
        signed:
            'wsTime=6aba3701&ctype=huya_pc_exe&t=100&wsSecret=2d7f25a2f40f9051a4c6fada21554094'
            '&seqid=1791848882565&ver=1&fs=bgct&u=1134703440',
      ),
    ];
    for (final (index, vector) in vectors.indexed) {
      test('vector ${index + 1}', () {
        final signed = HuyaApi.signAntiCode(
          vector.antiCode,
          streamName: vector.stream,
          uid: vector.uid,
          clock: HuyaSignClock(),
          now: DateTime.fromMillisecondsSinceEpoch(vector.now, isUtc: true),
        );
        expect(signed, vector.signed);
      });
    }

    test('WAP (t=103) signs with the plain uid and adds uid and a random uuid', () {
      final signed = HuyaApi.signAntiCode(
        'wsTime=6b49d278&fm=d2FwXyQwXyQxXyQyXyQz&ctype=huya_live&t=103&sphd=264_*',
        streamName: 'stream-name',
        uid: 1400123456789,
        clock: HuyaSignClock(),
        now: DateTime.fromMillisecondsSinceEpoch(1800000000000, isUtc: true),
        random: Random(3),
      );
      // 3.x re-encoded the parameters it does not own (sphd=264_%2A); they
      // keep their spelling now. The signature does not cover them.
      expect(
        signed.replaceFirst(RegExp(r'uuid=\d+$'), 'uuid=*'),
        'wsTime=6b49d278&ctype=huya_live&t=103&sphd=264_*&wsSecret=e8c5486afea4e995cd0f6893295be906'
        '&seqid=3200123456789&ver=1&fs=bgct&uid=1400123456789&uuid=*',
      );
      expect(Uri.splitQueryString(signed).containsKey('u'), isFalse);
    });

    test('the whole server template is signed, whatever its layout (REG-HUYA-005)', () {
      const template = r'prefix-v2|$1|viewer=$0|hash=$2|lease=$3|tail';
      final now = DateTime.fromMillisecondsSinceEpoch(1800000000000, isUtc: true);
      final wsTime = _wsTime(now.add(const Duration(minutes: 2)));
      final signed = Uri.splitQueryString(
        HuyaApi.signAntiCode(
          'wsTime=$wsTime&fm=${_fm(template)}&ctype=huya_live&t=100&codec=264',
          streamName: 'stream-name',
          uid: 1400123456789,
          clock: HuyaSignClock(),
          now: now,
        ),
      );
      final hash = md5.convert(utf8.encode('${signed['seqid']}|huya_live|100')).toString();
      final input = template
          .replaceFirst(r'$0', '${HuyaApi.rotateUid(1400123456789)}')
          .replaceFirst(r'$1', 'stream-name')
          .replaceFirst(r'$2', hash)
          .replaceFirst(r'$3', wsTime);
      expect(signed['wsSecret'], md5.convert(utf8.encode(input)).toString());
      expect(signed.containsKey('fm'), isFalse, reason: 'fm never reaches the CDN');
    });

    final now = DateTime.fromMillisecondsSinceEpoch(1800000000000, isUtc: true);
    String code(String template, {Duration wsTimeFromNow = const Duration(minutes: 2)}) =>
        'wsTime=${_wsTime(now.add(wsTimeFromNow))}&fm=${_fm(template)}&ctype=huya_live&t=100';
    String sign(String antiCode, {HuyaSignClock? clock}) =>
        HuyaApi.signAntiCode(antiCode, streamName: 's', uid: 123, clock: clock ?? HuyaSignClock(), now: now);
    Matcher fails(HuyaSignFailure kind) =>
        throwsA(isA<HuyaSignException>().having((failure) => failure.kind, 'kind', kind));

    test('malformed templates fail before any URL is built (REG-HUYA-005)', () {
      expect(() => sign(code(r'prefix_$0_$1')), fails(HuyaSignFailure.malformed));
      expect(() => sign('fm=${_fm(r'$0$1$2$3')}&ctype=x'), fails(HuyaSignFailure.malformed));
      expect(() => sign('wsTime=zz&fm=${_fm(r'$0$1$2$3')}'), fails(HuyaSignFailure.malformed));
      expect(() => sign('wsTime=6b49d278&fm=%%%'), fails(HuyaSignFailure.malformed));
      expect(() => sign('wsTime=6b49d278&fm=@@@@'), fails(HuyaSignFailure.malformed));
      // The recorded samples scrub fm into exactly such a value.
      final data = (jsonDecode(_sample('S05-multicdn').body) as Map)['data'] as Map;
      final base = ((data['stream'] as Map)['baseSteamInfoList'] as List).first as Map;
      expect(() => sign(base['sFlvAntiCode'] as String), fails(HuyaSignFailure.malformed));
    });

    test('wsTime is never extended: kept as served, expired past wsTime + 300 s (REG-HUYA-004)', () {
      final nearEnd = code(r'$0$1$2$3', wsTimeFromNow: const Duration(seconds: -300));
      expect(Uri.splitQueryString(sign(nearEnd))['wsTime'], _wsTime(now.subtract(const Duration(seconds: 300))));
      final expired = code(r'$0$1$2$3', wsTimeFromNow: const Duration(seconds: -301));
      expect(() => sign(expired), fails(HuyaSignFailure.expired));
    });

    test('a query without an fm value is returned unchanged and does not advance the clock', () {
      final clock = HuyaSignClock();
      for (final token in ['', 'wsSecret=signed&wsTime=6b49d278&ctype=huya_live&t=100', 'fm=&wsTime=1']) {
        expect(sign(token, clock: clock), token);
      }
      expect(clock.next(now), now.millisecondsSinceEpoch);
      expect(HuyaApi.hasTemplate('a=1&fm=x'), isTrue);
      expect(HuyaApi.hasTemplate('xfm=1'), isFalse);
    });

    test('seqid strictly increases per clock, so concurrent opens differ (REG-HUYA-007)', () {
      final clock = HuyaSignClock();
      final antiCode = code(r'prefix_$0_$1_$2_$3');
      final signed = [for (var i = 0; i < 64; i++) Uri.splitQueryString(sign(antiCode, clock: clock))];
      final seqIds = [for (final query in signed) int.parse(query['seqid']!)];
      for (var i = 1; i < seqIds.length; i++) {
        expect(seqIds[i], seqIds[i - 1] + 1);
      }
      expect(signed.map((query) => query['wsSecret']).toSet(), hasLength(64));
      expect(signed.map((query) => query['wsTime']).toSet(), hasLength(1));
      expect(clock.next(now.add(const Duration(seconds: 1))), now.millisecondsSinceEpoch + 1000);
    });

    test('rotl64 keeps the high 32 bits of a real anonymous uid (REG-HUYA-008)', () {
      expect(HuyaApi.rotateUid(_presenter), 1134703440);
      expect(HuyaApi.rotateUid(1400123456789), 1399563556349);
      expect(HuyaApi.rotateUid(1471259343403), 1472703638413);
      expect(HuyaApi.rotateUid(1471259343403), greaterThan(0xFFFFFFFF));
      expect(HuyaApi.unrotateUid(1472703638413), 1471259343403);
    });
  });

  group('media URL and headers', () {
    test('FLV and HLS: the https base, the extension, codec=264 added, ratio set', () {
      final flv = HuyaApi.mediaUrl(
        _line(StreamFormat.flv, 'http://al.flv.huya.com/src'),
        antiCode: 'wsSecret=flv&wsTime=6a87f351',
        bitRate: 8000,
      );
      expect(
        flv.toString(),
        'https://al.flv.huya.com/src/stream-name.flv?wsSecret=flv&wsTime=6a87f351&codec=264&ratio=8000',
      );
      final hls = HuyaApi.mediaUrl(
        _line(StreamFormat.hls, 'http://al.hls.huya.com/src/'),
        antiCode: 'wsSecret=hls&wsTime=6a87f351',
        bitRate: 2000,
      );
      expect(
        hls.toString(),
        'https://al.hls.huya.com/src/stream-name.m3u8?wsSecret=hls&wsTime=6a87f351&codec=264&ratio=2000',
      );
    });

    test('a captured ratio is replaced, the source removes it, a codec is kept (REG-HUYA-012)', () {
      expect(HuyaApi.mediaQuery('a=1&codec=265&ratio=4000&ratio=9', bitRate: 2000), 'a=1&codec=265&ratio=2000');
      expect(HuyaApi.mediaQuery('a=1&ratio=500', bitRate: 0), 'a=1&codec=264');
      // codec=265 only asks: a room without an HEVC transcode answers H.264.
      expect(HuyaApi.codecOf(Uri.parse('https://x/y.flv?codec=265')), isNull);
      expect(HuyaApi.codecOf(Uri.parse('https://x/y.flv?codec=264')), 'avc');
    });

    test('with hevc (优先 H.264 off) an FLV line asks for codec=265, HLS stays on 264, a captured codec is kept', () {
      final flv = HuyaApi.mediaUrl(
        _line(StreamFormat.flv, 'https://al.flv.huya.com/src'),
        antiCode: 'a=1',
        bitRate: 0,
        hevc: true,
      );
      final hls = HuyaApi.mediaUrl(
        _line(StreamFormat.hls, 'https://al.hls.huya.com/src'),
        antiCode: 'a=1',
        bitRate: 0,
        hevc: true,
      );
      expect(flv.query, 'a=1&codec=265');
      expect(hls.query, 'a=1&codec=264');
      expect(HuyaApi.mediaQuery('a=1&codec=264', bitRate: 0, hevc: true), 'a=1&codec=264');
    });

    test('only http bases on huya.com become https', () {
      expect(HuyaApi.secureBase('http://tx.flv.huya.com/src'), 'https://tx.flv.huya.com/src');
      expect(HuyaApi.secureBase('http://example.com/src'), 'http://example.com/src');
      expect(HuyaApi.secureBase('http://huya.com.example/src'), 'http://huya.com.example/src');
    });

    test('media headers: the HYSDK UA by default, Origin, the room as Referer, the cookie (REG-HUYA-024)', () {
      expect(HuyaApi.mediaHeaders('660000'), {
        'user-agent': HuyaApi.hysdkUserAgent,
        'origin': 'https://www.huya.com',
        'referer': 'https://www.huya.com/660000',
      });
      expect(HuyaApi.mediaHeaders(' ', userAgent: 'ua', cookie: ' yyuid=1 '), {
        'user-agent': 'ua',
        'origin': 'https://www.huya.com',
        'referer': 'https://www.huya.com/',
        'cookie': 'yyuid=1',
      });
    });

    test('line diagnostics carry the host and CDN, never tokens or stream names (REG-HUYA-023)', () {
      final text = _line(
        StreamFormat.flv,
        'https://al-game.flv.huya.com/src',
        antiCode: 'wsSecret=private-token&wsTime=7fffffff',
      ).toString();
      expect(text, allOf(contains('al-game.flv.huya.com'), contains('AL')));
      expect(text, isNot(anyOf(contains('private-token'), contains('wsSecret'), contains('stream-name'))));
      expect(const HuyaUserId(cookie: 'secret', guid: 'g', huyaUa: 'ua').toString(), isNot(contains('secret')));
    });
  });

  group('leases', () {
    final now = DateTime.utc(2026, 8, 29, 12);

    test('native FLV: min(wsTime + 300 s, token), refreshed 30 s before; the connection is kept (REG-HUYA-002)', () {
      final ws = _wsTime(now.add(const Duration(minutes: 1)));
      final url = Uri.parse('https://al.flv.huya.com/src/s.flv?wsTime=$ws&ctype=huya_pc_exe&t=100&seqid=1&u=1');
      expect(HuyaApi.isNativeFlv(url), isTrue);
      final lease = HuyaApi.lease(url, builtAt: now)!;
      expect(lease.expiresAt, now.add(const Duration(minutes: 6)));
      expect(lease.refreshAt, now.add(const Duration(minutes: 5, seconds: 30)));
      expect(lease.cutsConnection, isFalse);
      final token = HuyaApi.tokenWindow('wsTime=$ws', expireTime: 90, receivedAt: now);
      final bounded = HuyaApi.lease(url, builtAt: now, token: token)!;
      expect(
        (bounded.refreshAt, bounded.expiresAt),
        (now.add(const Duration(seconds: 60)), now.add(const Duration(seconds: 90))),
      );
    });

    test('web FLV and HLS: 100/125 s from the signed issue time, not from when it is read (REG-HUYA-001)', () {
      const url =
          'https://al-game.flv.huya.com/live.flv?wsTime=6a94f03e&t=102&seqid=3259308803203&u=1470177679757&wsSecret=v';
      final issuedAt = DateTime.fromMillisecondsSinceEpoch(1788059326826, isUtc: true);
      expect(HuyaApi.signedIssuedAt(Uri.parse(url)), issuedAt);
      final lease = HuyaApi.lease(Uri.parse(url), builtAt: issuedAt.add(const Duration(seconds: 90)))!;
      expect(lease.refreshAt, issuedAt.add(const Duration(seconds: 100)));
      expect(lease.expiresAt, issuedAt.add(const Duration(seconds: 125)));
      expect(lease.cutsConnection, isTrue);
    });

    test('WAP signatures read the plain uid', () {
      const uid = 1400123456789;
      const issued = 1800000000000;
      final ws = _wsTime(DateTime.fromMillisecondsSinceEpoch(issued, isUtc: true).add(const Duration(hours: 1)));
      final url = Uri.parse('https://al-hls.huya.com/live.m3u8?wsTime=$ws&t=103&seqid=${uid + issued}&uid=$uid');
      expect(HuyaApi.signedIssuedAt(url), DateTime.fromMillisecondsSinceEpoch(issued, isUtc: true));
    });

    test('a static token without seqid counts from when the URL was built (REG-HUYA-019)', () {
      final url = Uri.parse(
        'https://al-game.flv.huya.com/src/s.flv?wsSecret=legacy&wsTime=7fffffff&ctype=tars_mp&t=102',
      );
      expect(HuyaApi.signedIssuedAt(url), isNull);
      final lease = HuyaApi.lease(url, builtAt: now)!;
      expect(
        (lease.refreshAt, lease.expiresAt),
        (now.add(const Duration(seconds: 100)), now.add(const Duration(seconds: 125))),
      );
    });

    test('other hosts: only wsTime bounds the URL; nothing bounds a URL without it', () {
      final ws = _wsTime(now.add(const Duration(minutes: 1)));
      final lease = HuyaApi.lease(Uri.parse('https://cdn.example/live.flv?wsTime=$ws&wsSecret=v'))!;
      expect(
        (lease.refreshAt, lease.expiresAt),
        (now.add(const Duration(minutes: 5, seconds: 30)), now.add(const Duration(minutes: 6))),
      );
      expect(lease.cutsConnection, isFalse);
      expect(HuyaApi.lease(Uri.parse('https://cdn.example/live.flv')), isNull);
    });

    test('token windows: wsTime + 300 s, or an earlier iExpireTime in ms, s or seconds after receipt', () {
      final ws = _wsTime(now.add(const Duration(hours: 1)));
      final plain = HuyaApi.tokenWindow(
        'wsSecret=x&wsTime=${_wsTime(now.add(const Duration(minutes: 1)))}',
        expireTime: 0,
        receivedAt: now,
      );
      expect(
        (plain.refreshAt, plain.invalidAt),
        (now.add(const Duration(minutes: 5, seconds: 30)), now.add(const Duration(minutes: 6))),
      );
      expect(
        HuyaApi.tokenWindow('wsTime=$ws', expireTime: 90, receivedAt: now).invalidAt,
        now.add(const Duration(seconds: 90)),
      );
      final seconds = now.add(const Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000;
      expect(
        HuyaApi.tokenWindow('wsTime=$ws', expireTime: seconds, receivedAt: now).invalidAt,
        now.add(const Duration(minutes: 10)),
      );
      final millis = now.add(const Duration(minutes: 20)).millisecondsSinceEpoch;
      expect(
        HuyaApi.tokenWindow('wsTime=$ws', expireTime: millis, receivedAt: now).invalidAt,
        now.add(const Duration(minutes: 20)),
      );
      expect(() => HuyaApi.tokenWindow(' ', expireTime: 0, receivedAt: now), throwsA(isA<ApiChanged>()));
      expect(() => HuyaApi.tokenWindow('wsSecret=x', expireTime: 0, receivedAt: now), throwsA(isA<ApiChanged>()));
    });

    test('credential families (3.x HuyaTransportPolicy)', () {
      expect(
        HuyaApi.hasShortTransportLease(Uri.parse('https://al.flv.huya.com/live.flv?ctype=huya_pc_exe&t=100')),
        isFalse,
      );
      for (final url in [
        'https://al.flv.huya.com/live.flv?ctype=huya_live&t=100',
        'https://al.flv.huya.com/live.flv?ctype=huya_webh5&t=100',
        'https://al.flv.huya.com/live.flv',
        'https://al.hls.huya.com/live.m3u8?ctype=huya_pc_exe&t=100',
      ]) {
        expect(HuyaApi.hasShortTransportLease(Uri.parse(url)), isTrue, reason: url);
      }
      for (final url in ['https://huya.com.example/live.flv', 'https://example.com/live.flv', 'not a URL']) {
        expect(HuyaApi.hasShortTransportLease(Uri.parse(url)), isFalse, reason: url);
      }
    });
  });

  group('refreshed line (3.x HuyaTransportPolicy table, REG-HUYA-010)', () {
    const al = 'https://al.flv.huya.com/src/room.flv?ctype=huya_pc_exe&t=100';
    const tx = 'https://tx.flv.huya.com/src/room.flv?ctype=huya_pc_exe&t=100';
    const web = 'https://tx.flv.huya.com/src/room.flv?ctype=huya_live';
    const hls = 'https://tx.hls.huya.com/src/room.m3u8?ctype=huya_live';
    for (final scenario in [
      (name: 'query renewal keeps the same CDN', current: '$tx&seqid=old', urls: [tx, al], advance: false, expected: 0),
      (
        name: 'rotated stream name keeps the CDN',
        current: tx.replaceFirst('room.flv', 'old.flv'),
        urls: [tx, al],
        advance: false,
        expected: 0,
      ),
      (
        name: 'missing current CDN takes the first native fallback',
        current: tx,
        urls: [al, hls],
        advance: true,
        expected: 0,
      ),
      (
        name: 'a sole failed native line may fall back to web FLV',
        current: tx,
        urls: [tx, web, hls],
        advance: true,
        expected: 1,
      ),
      (name: 'a sole failed FLV line may fall back to HLS', current: tx, urls: [tx, hls], advance: true, expected: 1),
      (name: 'an HLS choice stays HLS', current: hls, urls: [hls, tx], advance: false, expected: 0),
      (
        name: 'a failed HLS line may fall back to native FLV',
        current: hls,
        urls: [hls, tx],
        advance: true,
        expected: 1,
      ),
      (name: 'a native CDN wraps within native choices', current: tx, urls: [al, tx, hls], advance: true, expected: 0),
      (name: 'another native CDN before web', current: tx, urls: [tx, web, al], advance: true, expected: 2),
      (name: 'a single remaining source reopens after a real EOF', current: tx, urls: [tx], advance: true, expected: 0),
      (
        name: 'a foreign host never supplies Huya identity',
        current: 'https://huya.com.example/room.flv',
        urls: [tx, al],
        advance: false,
        expected: 1,
      ),
    ]) {
      test(scenario.name, () {
        expect(
          HuyaApi.selectRefreshedLine(
            urls: scenario.urls,
            currentUrl: scenario.current,
            currentLineIndex: 1,
            advanceLine: scenario.advance,
          ),
          scenario.expected,
        );
      });
    }

    test('no identity and empty lists keep the bounded index', () {
      expect(HuyaApi.selectRefreshedLine(urls: [], currentUrl: tx, currentLineIndex: 9, advanceLine: true), 0);
      expect(HuyaApi.selectRefreshedLine(urls: [al, tx], currentUrl: null, currentLineIndex: 9, advanceLine: false), 1);
      expect(HuyaApi.selectRefreshedLine(urls: [al, tx], currentUrl: null, currentLineIndex: -1, advanceLine: true), 1);
    });
  });

  group('Tars and WUP (3.x BaseTarsHttp vectors)', () {
    test('native getCdnTokenInfoEx request: no cookie, no viewer uid, the pc_exe identity', () {
      expect(
        HuyaApi.cdnTokenRequest(
          flvUrl: '',
          streamName: _vectorStream,
          userId: const HuyaUserId(huyaUa: HuyaApi.nativeTarsUserAgent),
        ),
        _hex(
          '0000009210032c3c4c56066c6976657569661167657443646e546f6b656e496e666f45787d0000650800010604745265711d'
          '0000580a0600162837383934313936392d323535393436313539332d31303939323830333833373330333036323532382c3a'
          '0c16002600361770635f6578652637303630303030266f6666696369616c46005c660076000b40420b8c980ca80c',
        ),
      );
    });

    test('web getCdnTokenInfoEx request, short and long (string4) cookie', () {
      const cookie = 'yyuid=1400123456789; foo=bar';
      HuyaUserId viewer(String cookie) =>
          HuyaUserId(uid: 1400123456789, guid: 'fixture-guid', huyaUa: HuyaApi.webTarsUserAgent, cookie: cookie);
      expect(
        HuyaApi.cdnTokenRequest(
          flvUrl: 'https://tx.flv.huya.com/src',
          streamName: 'stream-name',
          userId: viewer(cookie),
        ),
        _hex(
          '000000c010032c3c4c56066c6976657569661167657443646e546f6b656e496e666f45787d000100920800010604745265711d'
          '000100840a061b68747470733a2f2f74782e666c762e687579612e636f6d2f737263160b73747265616d2d6e616d652c3a03'
          '00000145fddc7d15160c666978747572652d6775696426003615776562683526302e312e3026776562736f636b6574461c79'
          '797569643d313430303132333435363738393b20666f6f3d6261725c660076000b40420b8c980ca80c',
        ),
      );
      final longCookie = 'yyuid=1400123456789; ${List.filled(40, 'k=v123').join('; ')}';
      final cookieHex = [for (final byte in utf8.encode(longCookie)) byte.toRadixString(16).padLeft(2, '0')].join();
      expect(
        HuyaApi.cdnTokenRequest(
          flvUrl: 'https://al.flv.huya.com/src',
          streamName: 'stream-name',
          userId: viewer(longCookie),
        ),
        _hex(
          '000001fa10032c3c4c56066c6976657569661167657443646e546f6b656e496e666f45787d000101cc080001060474526571'
          '1d000101be0a061b68747470733a2f2f616c2e666c762e687579612e636f6d2f737263160b73747265616d2d6e616d652c3a'
          '0300000145fddc7d15160c666978747572652d6775696426003615776562683526302e312e3026776562736f636b65744700'
          '000153${cookieHex}5c660076000b40420b8c980ca80c',
        ),
      );
    });

    test('getCdnTokenInfoEx answers: token and expiry; a signed int8 return code (3.x read 253)', () {
      final ok = HuyaApi.cdnTokenResponse(
        _hex(
          '0000009810032c3c4c56066c6976657569661167657443646e546f6b656e496e666f45787d00006b08000206001d0000010c06'
          '04745273701d0000570a065077735365637265743d61626326777354696d653d366162613337303126666d3d63484a6c5a6d'
          '6c345879517758795178587951795879517a2663747970653d687579615f70635f65786526743d31303011012c0b8c980ca80c',
        ),
      );
      expect(ok, (
        code: 0,
        token: 'wsSecret=abc&wsTime=6aba3701&fm=cHJlZml4XyQwXyQxXyQyXyQz&ctype=huya_pc_exe&t=100',
        expireTime: 300,
      ));
      final refused = HuyaApi.cdnTokenResponse(
        _hex(
          '0000004710032c3c4c56066c6976657569661167657443646e546f6b656e496e666f45787d00001a08000206001d00000200fd'
          '0604745273701d0000050a06001c0b8c980ca80c',
        ),
      );
      expect((refused.code, refused.token), (-3, ''));
    });

    test('packets round-trip; truncated or foreign bytes are ApiChanged; 5xx is NetworkFailure', () {
      final packet = WupPacket(
        servant: 'wupui',
        function: 'f',
        params: {'tReq': WupPacket.intParam(70000), 'x': WupPacket.structParam((writer) => writer.writeInt(20, -5))},
      ).encode();
      final decoded = WupPacket.decode(packet);
      expect((decoded.servant, decoded.function, decoded.code), ('wupui', 'f', 0));
      expect(TarsStruct.decode(decoded.params['tReq']!).integer(0), 70000);
      expect(decoded.struct('x')!.integer(20), -5);
      for (final bad in [packet.sublist(0, packet.length - 3), Uint8List(3), utf8.encode('<html>')]) {
        expect(() => HuyaApi.cdnTokenResponse(bad), throwsA(isA<ApiChanged>()));
      }
      expect(() => HuyaApi.cdnTokenResponse(packet, status: 502), throwsA(isA<NetworkFailure>()));
    });

    test('decoded values: every type round-trips; malformed input is a FormatException', () {
      final value = TarsStruct({
        0: 0,
        1: -1,
        2: 300,
        3: 70000,
        4: 1 << 40,
        5: 'text',
        6: 'x' * 300,
        7: Uint8List.fromList([1, 2, 255]),
        8: const <Object?>['a', 1],
        9: const <Object?, Object?>{'k': 'v'},
        10: const TarsStruct({0: 1}),
        11: 1.5,
      });
      final round = TarsStruct.decode(value.encode());
      expect(round.integer(1), -1, reason: 'int8 is signed');
      expect(round.integer(4), 1 << 40);
      expect(round.string(6), hasLength(300));
      expect(round.bytes(7), [1, 2, 255]);
      expect(round.list(8), ['a', 1]);
      expect(round.map(9), {'k': 'v'});
      expect(round.struct(10)!.integer(0), 1);
      expect(round.fields[11], 1.5);
      expect(round.encode(), value.encode());
      for (final bad in [
        [0x06, 0x05, 0x61],
        [0x0A, 0x00],
        [0x0B],
        [0x09, 0x02, 0x7F],
        [0x0E],
      ]) {
        expect(() => TarsStruct.decode(bad), throwsFormatException, reason: '$bad');
      }
    });

    test('headline message board request (wupui.getHeadLineMessageBoard)', () {
      final packet = WupPacket.decode(HuyaApi.messageBoardRequest(1346609715));
      expect((packet.servant, packet.function), ('wupui', 'getHeadLineMessageBoard'));
      final request = packet.struct('tReq')!;
      expect(request.integer(0), 1346609715);
      expect(request.string(1), '');
      expect(request.struct(2)!.string(3), HuyaApi.hysdkUserAgent);
      expect((request.integer(3), request.integer(4)), (0, 10));
    });

    test('board entries: ids kept, empty and expired entries dropped, price from iCostPay', () {
      final now = DateTime.utc(2026, 9, 27, 12);
      TarsStruct entry(int id, int countdown, {String text = 'message', int total = 60}) => TarsStruct({
        0: const TarsStruct({1: ' nick ', 2: '//a.msstatic.com/f.jpg'}),
        1: text,
        4: total,
        5: countdown,
        9: id,
        12: 1200,
      });
      final bytes = WupPacket(
        servant: 'wupui',
        function: 'getHeadLineMessageBoard',
        params: {
          '': WupPacket.intParam(0),
          'tRsp':
              (TarsWriter()..writeValue(
                    0,
                    TarsStruct({
                      1: TarsStruct({
                        1: <Object?>[entry(2, 50), entry(1, 10), entry(3, 30, text: ' '), entry(4, 0, total: 0)],
                      }),
                    }),
                  ))
                  .toBytes(),
        },
      ).encode();
      final chats = HuyaApi.superChats(bytes, now: now);
      expect(chats.map((chat) => chat.messageId), ['huya:2', 'huya:1']);
      final first = chats.first;
      expect((first.userName, first.face, first.price), ('nick', 'https://a.msstatic.com/f.jpg', 12));
      // D07.2: the unit of the platform table (superChatUnits).
      expect(first.unit, LiveGiftUnit.yuan);
      expect(superChatUnits[SiteIds.huya], first.unit);
      expect(first.endTime, now.add(const Duration(seconds: 50)));
      expect(first.startTime, now.subtract(const Duration(seconds: 10)));
      expect((first.backgroundColor, first.backgroundBottomColor), ('#ffffff', '#246488'));
      final refused = WupPacket(
        servant: 'wupui',
        function: 'getHeadLineMessageBoard',
        params: {'': WupPacket.intParam(-1)},
      ).encode();
      expect(() => HuyaApi.superChats(refused, now: now), throwsA(isA<ApiChanged>()));
    });

    test('S11: the recorded board answer (empty) decodes', () {
      final frames = File('../../fixtures/huya/danmaku/S11-live/frames.jsonl').readAsLinesSync();
      final board = frames
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .firstWhere((frame) => frame['url'] == 'https://wup.huya.com/');
      final bytes = base64Decode(board['b64'] as String);
      expect(WupPacket.decode(bytes).function, 'getHeadLineMessageBoard');
      expect(HuyaApi.superChats(bytes, now: DateTime.utc(2026, 9, 27)), isEmpty);
    });
  });

  group('identity and helpers', () {
    test('yyuid only from an exact cookie field above 0', () {
      expect(HuyaApi.viewerUidFromCookie('foo=1; yyuid=1400123456789; bar=2'), 1400123456789);
      expect(HuyaApi.viewerUidFromCookie('foo=yyuid=12; bar=2'), isNull);
      expect(HuyaApi.viewerUidFromCookie('yyuid=0'), isNull);
      expect(HuyaApi.viewerUidFromCookie(null), isNull);
    });

    test('the temporary uid stays in range without RangeError; the GUID is 32 hex digits (REG-HUYA-017)', () {
      final random = Random(9);
      for (var i = 0; i < 100; i++) {
        expect(HuyaApi.fallbackViewerUid(random), inInclusiveRange(1400000000000, 1400000000000 + 99999999999));
      }
      expect(HuyaApi.guid(random), matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('anonymous login, player configuration and room pages', () {
      expect(HuyaApi.anonymousUid('{"returnCode":0,"data":{"uid":1400123456789}}'), 1400123456789);
      expect(HuyaApi.anonymousUid('{"data":{"uid":0}}'), isNull);
      expect(HuyaApi.anonymousUid('<html>'), isNull);
      expect(HuyaApi.anonymousUid('{"data":{"uid":1}}', status: 500), isNull);
      expect(
        HuyaApi.playUserAgent({
          'huya': {'user_agent': ' ua '},
        }),
        'ua',
      );
      expect(HuyaApi.playUserAgent({'huya': <String, Object?>{}}), isNull);
      expect(HuyaApi.playUserAgent(null), isNull);
      expect(
        HuyaApi.roomIdFromPage(
          '<script>var TT_ROOM_DATA = {"state":"ON","profileRoom":"660000"};\nvar X = 1;</script>',
        ),
        '660000',
      );
      expect(HuyaApi.roomIdFromPage('window.x = {"profileRoom":880351};'), '880351');
      expect(HuyaApi.roomIdFromPage('<html>没有找到该房间</html>'), isNull);
      expect(HuyaApi.roomIdFromPage('{"profileRoom":"0"}'), isNull);
    });

    test("the HYSDK UA is the PC client's 7100004; an older configured HYSDK UA falls back to it", () {
      // Upstream a858550bb (E01.8): the PC client simple_live and upstream send.
      expect(HuyaApi.hysdkUserAgent, 'HYSDK(Windows,30000002)_APP(pc_exe&7100004&official)_SDK(trans&2.40.0.6448)');
      Map<String, Object?> config(String ua) => {
        'huya': {'user_agent': ua},
      };
      // The upstream repository's play_config.json still names 7090000.
      expect(
        HuyaApi.playUserAgent(config('HYSDK(Windows,30000002)_APP(pc_exe&7090000&official)_SDK(trans&2.35.0.5996)')),
        isNull,
      );
      const newer = 'HYSDK(Windows,30000002)_APP(pc_exe&7110000&official)_SDK(trans&2.41.0.1)';
      expect(HuyaApi.playUserAgent(config(newer)), newer);
      expect(HuyaApi.playUserAgent(config(HuyaApi.hysdkUserAgent)), HuyaApi.hysdkUserAgent);
      // Not a HYSDK UA with a client version: the configuration decides.
      expect(HuyaApi.playUserAgent(config('HYSDK(custom)')), 'HYSDK(custom)');
      expect(HuyaApi.playUserAgent(config('Mozilla/5.0 pc_exe&1&official')), 'Mozilla/5.0 pc_exe&1&official');
    });

    test('danmaku arguments print as 3.x did', () {
      expect(
        const HuyaDanmakuArgs(uid: 1346609715, topSid: 1346609715, subSid: 1346609715).toString(),
        ((_sample('S05-multicdn').legacy as Map)['getRoomDetail'] as Map)['danmakuData'],
      );
    });
  });
}
