// YY parsing against the recorded samples, compared field by field with
// 3.x's output (expected.json, written by the transcribed 3.x parser in
// fixtures/yy/legacy_expected.dart: the 3.x app no longer builds). Every
// intended difference is listed with its reason (the M4.06 review, or the
// upgrade number of docs/UPGRADES.md); everything else must match.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('yy', name);

/// `startTime` (Unix seconds) as the room's start.
DateTime _start(Object? seconds) => DateTime.fromMillisecondsSinceEpoch((seconds! as int) * 1000, isUtc: true);

/// Asserts 6-2's title against 3.x's: YY's default title `<nickname> 正在直播`
/// loses its suffix, any other title is 3.x's. Returns whether it changed.
bool _expectTitle(String actual, Object? legacy, {String? reason}) {
  final text = (legacy as String?) ?? '';
  final changed = text.endsWith('正在直播');
  expect(actual, changed ? text.substring(0, text.length - '正在直播'.length).trim() : text, reason: '$reason title');
  if (changed) expect(actual, isNot(contains('正在直播')), reason: '$reason title');
  return changed;
}

/// Asserts that [actual] (a `toJson`) equals 3.x's [legacy] projection on
/// every key 3.x wrote, except [changed] (intended differences) and
/// `danmakuData` (compared as 3.x's string). 3.x wrote null where the
/// immutable model writes ''.
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

Map<String, dynamic> _legacy(Fixture fixture) => fixture.legacy as Map<String, dynamic>;

List<Map<String, dynamic>> _legacyList(Fixture fixture, String key) =>
    (_legacy(fixture)[key] as List).cast<Map<String, dynamic>>();

/// The raw `data.data` cards of a page.action sample.
List<Map<String, dynamic>> _rawCards(Fixture fixture) =>
    ((((jsonDecode(fixture.body) as Map)['data'] as Map)['data'] as List?) ?? const []).cast<Map<String, dynamic>>();

/// The raw `docs` of a search sample.
List<Map<String, dynamic>> _rawDocs(Fixture fixture, String tab) =>
    ((((((jsonDecode(fixture.body) as Map)['data'] as Map)['searchResult'] as Map)['response'] as Map)[tab]
                as Map)['docs']
            as List)
        .cast<Map<String, dynamic>>();

/// The gears of a stream-manager sample that have a web stream
/// (`stream_key`).
Set<String> _webGears(Fixture fixture) => {
  for (final stream
      in (((jsonDecode(fixture.body) as Map)['channel_stream_info'] as Map)['streams'] as List)
          .cast<Map<String, dynamic>>())
    if (stream['stream_key'] != null)
      if ((jsonDecode(stream['json'] as String) as Map)['gear_info'] case final Map<String, dynamic> info)
        '${info['gear']}',
};

String _https(String url) => url.startsWith('http://') ? 'https://${url.substring(7)}' : url;

void main() {
  group('S01/S02 catalog', () {
    test('S01 header: the three categories of 3.x', () {
      final fixture = _sample('S01-header');
      final tabs = YyApi.categoryTabs(fixture.body, status: fixture.status);
      expect(
        [for (final tab in tabs) (tab.id, tab.name)],
        [
          for (final category in (fixture.legacy as List).cast<Map<String, dynamic>>())
            (category['id'], category['name']),
        ],
      );
    });

    for (final (name, id, title) in [
      ('S01-category-ent', '1', '娱乐'),
      ('S01-category-game', '2', '游戏'),
      ('S01-category-other', '3', '其他'),
    ]) {
      test('$name: areas match 3.x; each with its page', () {
        final fixture = _sample(name);
        final areas = YyApi.areas(fixture.body, categoryId: id, categoryName: title, status: fixture.status);
        final legacy = _legacyList(fixture, 'areas');
        expect(areas, hasLength(legacy.length));
        final raw = ((jsonDecode(fixture.body) as Map)['data'] as List).cast<Map<String, dynamic>>();
        for (final (index, entry) in areas.indexed) {
          // areaPic: 3.x kept the http:// address (image.yy.com serves it
          // over https too); shortName: read from the area page by the site
          // (yy_site_test compares it with 3.x's).
          _expectParity(entry.area.toJson(), legacy[index], changed: {'areaPic', 'shortName'}, reason: '$name[$index]');
          expect(entry.area.areaPic, _https(legacy[index]['areaPic'] as String));
          expect(entry.page, Uri.parse(_https(raw[index]['url'] as String)), reason: "3.x's normalizeWebUrl");
          // C-19: only 小视频 is a short-video page.
          expect(YyApi.isShortVideoPage(entry.page), entry.area.areaName == '小视频', reason: '$name[$index]');
        }
      });
    }

    test('S02 area pages: the pageInfo module and shortName of 3.x', () {
      for (final name in ['S02-area-page-dance', 'S02-area-page-lol']) {
        final fixture = _sample(name);
        final legacy = _legacy(fixture);
        final module = YyApi.pageInfo(fixture.body)!;
        expect({
          'moduleId': module.moduleId,
          'biz': module.biz,
          'subBiz': module.subBiz,
        }, legacy['parseCategoryPageInfo']);
        expect(YyApi.shortName(module), legacy['shortName'], reason: name);
        expect(YyApi.moduleOf(YyApi.shortName(module)), module);
      }
      expect(YyApi.hasListing(YyApi.pageInfo(_sample('S02-area-page-dance').body)!), isTrue);
      expect(
        YyApi.hasListing(YyApi.pageInfo(_sample('S02-area-page-lol').body)!),
        isFalse,
        reason: 'server-rendered areas: moduleId 0, biz "null"',
      );
      expect(YyApi.pageInfo('var pageInfo = {biz: "sing"};'), isNull, reason: '3.x test: incomplete metadata');
      expect(
        YyApi.pageInfo('''
<script>var pageInfo = {
            pageBar: {totalPages: 8, moduleId: 308, biz: 'sing', subBiz: "idx"},
            position: 'secondary'
          };</script>'''),
        (moduleId: 308, biz: 'sing', subBiz: 'idx'),
        reason: '3.x test: the JavaScript literal without a JS runtime',
      );
      expect(YyApi.moduleOf('{"moduleId":"313","biz":"dance","subBiz":"idx"}'), (
        moduleId: 313,
        biz: 'dance',
        subBiz: 'idx',
      ));
      expect(YyApi.moduleOf(''), isNull);
      expect(YyApi.moduleOf('{"biz":"dance"}'), isNull);
    });
  });

  group('S02/S03 room lists', () {
    for (final (name, defaultTitles) in [('S02-dance-p1', 7), ('S02-dance-p5', 2), ('S02-dance-p6', 0)]) {
      test('$name: the same live rooms as 3.x, named after the area; start times; default titles (6-2)', () {
        final fixture = _sample(name);
        final rooms = YyApi.roomList(fixture.body, area: '舞蹈', status: fixture.status);
        final legacy = _legacyList(fixture, 'rooms');
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        final raw = _rawCards(fixture);
        var changed = 0;
        for (final (index, room) in rooms.indexed) {
          // title: 6-2 (the default title `<nickname> 正在直播` without its
          // suffix; lists carry the same value as search's channelName).
          _expectParity(room.toJson(), legacy[index], changed: {'title'}, reason: '$name[$index]');
          if (_expectTitle(room.title, legacy[index]['title'], reason: '$name[$index]')) changed++;
          expect(room.audienceMetricType, AudienceMetricType.popularity, reason: '`users` is heat (REG-YY-006)');
          expect(room.onlineViewers, isEmpty);
          final data = room.data! as YyRoomData;
          expect((data.sid, data.ssid), ('${raw[index]['sid']}', '${raw[index]['ssid']}'));
          // New key (M2.1): the start is the card's startTime.
          expect(room.startedAt, _start(raw[index]['startTime']));
          expect(room.toJson()['startedAt'], room.startedAt!.toIso8601String());
          expect(room.restriction, isNull, reason: 'YY says nothing about restrictions');
        }
        expect(changed, defaultTitles);
      });
    }

    for (final (name, defaultTitles) in [('S03-recommend-p1', 1), ('S03-recommend-p2', 0), ('S03-recommend-p3', 0)]) {
      test('$name: the same rooms as 3.x; no area instead of the raw biz `other` (6-3)', () {
        final fixture = _sample(name);
        final rooms = YyApi.roomList(fixture.body, status: fixture.status);
        final legacy = _legacyList(fixture, 'rooms');
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        final raw = _rawCards(fixture);
        var changed = 0;
        for (final (index, room) in rooms.indexed) {
          // area: 6-3 (3.x wrote the raw biz `other`); title: 6-2.
          _expectParity(room.toJson(), legacy[index], changed: {'area', 'title'}, reason: '$name[$index]');
          expect(legacy[index]['area'], 'other');
          expect(room.area, isEmpty);
          if (_expectTitle(room.title, legacy[index]['title'], reason: '$name[$index]')) changed++;
          expect(room.startedAt, _start(raw[index]['startTime']));
        }
        expect(changed, defaultTitles);
        final named = YyApi.roomList(fixture.body, areaNames: const {'other': '推荐'});
        expect(named.every((room) => room.area == ''), isTrue, reason: '`other` names no area');
      });
    }

    test('an area page names a biz (6-3), else the preset (C-21); an unknown biz is no name', () {
      String page(String biz) => jsonEncode({
        'resultCode': 0,
        'data': {
          'data': [
            {'sid': 7, 'biz': biz},
          ],
        },
      });
      expect(YyApi.roomList(page('dance'), areaNames: const {'dance': '热舞'}).single.area, '热舞', reason: 'learnt first');
      expect(YyApi.roomList(page('dance')).single.area, '舞蹈', reason: 'C-21 preset; 3.x showed `dance`');
      expect(YyApi.roomList(page('chicken')).single.area, isEmpty, reason: 'four game areas share it');
      expect(YyApi.bizAreaNames, {
        'sing': '音乐',
        'talk': '脱口秀',
        'dance': '舞蹈',
        'red': '户外',
        'pretty': '颜值',
        'mc': '喊麦',
        'sport': '体育',
        'car': '二次元',
        'game': '王者荣耀',
        'zonghe': '综合',
      });
      expect(YyApi.roomList(page('zonghe')).single.area, '综合', reason: 'the rooms of 综合, an area without listing');
      expect(YyApi.roomList(page('dance'), area: '热舞').single.area, '热舞', reason: 'an area listing names its rooms');
    });

    test('data null (an area without listing) is empty; another resultCode is ApiChanged', () {
      expect(YyApi.roomList('{"resultCode":0,"data":{"totalCount":0,"data":null}}'), isEmpty);
      expect(() => YyApi.roomList('{"resultCode":1,"data":null}'), throwsA(isA<ApiChanged>()));
      expect(() => YyApi.roomList('<html>'), throwsA(isA<ApiChanged>()));
      expect(() => YyApi.roomList('', status: 502), throwsA(isA<NetworkFailure>()));
      expect(() => YyApi.roomList('', status: 429), throwsA(isA<RateLimited>()));
    });

    test('a card without a channel number is skipped; a missing thumb2 falls back to thumb', () {
      final rooms = YyApi.roomList(
        jsonEncode({
          'resultCode': 0,
          'data': {
            'data': [
              {'name': 'no sid'},
              {'sid': 7, 'thumb': '//img.yy.com/a.jpg'},
            ],
          },
        }),
      );
      expect(rooms.single.roomId, '7');
      expect(rooms.single.cover, 'https://img.yy.com/a.jpg');
      expect(rooms.single.startedAt, isNull, reason: 'no startTime');
    });

    test('start times: Unix seconds, as numbers or strings; 0 and nonsense are none', () {
      expect(YyApi.startedAt(1790527818), DateTime.utc(2026, 9, 27, 16, 50, 18));
      expect(YyApi.startedAt('1790527818'), DateTime.utc(2026, 9, 27, 16, 50, 18));
      for (final value in [0, -1, null, '', 'x', 1.5, 100000000000]) {
        expect(YyApi.startedAt(value), isNull, reason: '$value');
      }
    });

    test('M4.D: an area without JSON listing lists the cards its page renders', () {
      final rooms = YyApi.pageRooms(_sample('S02-area-page-mobilelive').body, area: '手机直播');
      expect(rooms, hasLength(18));
      expect(rooms.map((room) => room.roomId).toSet(), hasLength(18));
      final first = rooms.first;
      expect(first.toJson(), containsPair('roomId', '1414821761'));
      expect(
        (first.title, first.nick, first.userId, first.area, first.popularity, first.liveStatus),
        ('每天直播就是凑活活着', '朵朵公主（瞅你咋地）、', '3067162903', '手机直播', '21000', LiveStatus.live),
      );
      expect(first.cover, startsWith('https://mobilelivephoto.bs2dl.yy.com/live/'));
      expect(first.avatar, startsWith('https://downhdlogo.yy.com/hdlogo/'));
      expect(first.startedAt, _start(1790789171), reason: 'data-pid carries startTime');
      expect((first.data! as YyRoomData).ssid, '1414821761');
      expect(rooms.where((room) => room.nick == YyApi.placeholderName), isEmpty);
      expect(YyApi.pageRooms(_sample('S02-area-page-sv').body, area: '小视频'), isEmpty, reason: 'short videos');
      expect(YyApi.pageRooms(_sample('S02-area-page-lol').body, area: '英雄联盟'), isEmpty);
    });
  });

  group('S04 search', () {
    for (final (name, defaultTitles) in [('S04-search-p1', 4), ('S04-search-p50', 0), ('S04-search-empty', 0)]) {
      test('$name: the same rooms as 3.x; titles without ` 正在直播` (6-2)', () {
        final fixture = _sample(name);
        final rooms = YyApi.searchRooms(fixture.body, status: fixture.status);
        final legacy = _legacyList(fixture, 'rooms');
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        final raw = _rawDocs(fixture, '120');
        var changed = 0;
        for (final (index, room) in rooms.indexed) {
          // area: 3.x read `biz`, which search results do not have, and
          // wrote ''; `category` is the area name. title: 6-2.
          _expectParity(room.toJson(), legacy[index], changed: {'area', 'title'}, reason: '$name[$index]');
          expect(legacy[index]['area'], '');
          expect(room.area, raw[index]['category']);
          if (_expectTitle(room.title, legacy[index]['title'], reason: '$name[$index]')) changed++;
          expect(room.startedAt, isNull, reason: 'search results carry no start time');
        }
        expect(changed, defaultTitles);
      });
    }

    test('S04 6-2: the default title `<streamer> 正在直播` is the streamer; titles of their own stay', () {
      final rooms = YyApi.searchRooms(_sample('S04-search-p1').body);
      final room = rooms.first;
      expect(room.title, '创艺灵珊', reason: '3.x: 创艺灵珊 正在直播');
      expect(room.isLiveNow, isTrue);
      expect(room.link, 'https://www.yy.com/93379291');
      expect(rooms[1].title, '想你的风吹到了@8582');
      expect(rooms.firstWhere((room) => room.roomId == '1354260427').title, '熊猫', reason: '3.x: 熊猫  正在直播');
      for (final (raw, title) in [
        ('【森宁】刘饱饱正在直播', '【森宁】刘饱饱'),
        ('小书生{修身}正在直播', '小书生{修身}'),
        ('正在直播', ''),
        ('正在直播的舞蹈', '正在直播的舞蹈'),
        ('  ', ''),
        (null, ''),
      ]) {
        expect(YyApi.title(raw), title, reason: '$raw');
      }
    });

    test('S04 streamers match 3.x; `liveOn` is kept (6-6)', () {
      final fixture = _sample('S04-search-anchors');
      final anchors = YyApi.searchAnchors(fixture.body, status: fixture.status);
      expect([
        for (final anchor in anchors)
          {
            'roomId': anchor.roomId,
            'avatar': anchor.avatar,
            'userName': anchor.userName,
            'liveStatus': anchor.liveStatus,
          },
      ], _legacyList(fixture, 'anchors'));
      // The "unreliable" state (M4.06 candidate 6): 22490906 is a guild's
      // channel. When both samples were recorded, 燃舞蹈-福星 (uid
      // 107923068) performed there, while the streamer the search lists at
      // 22490906 is 燃舞蹈-Chisato (uid 411865223): `liveOn` 0 is that
      // streamer's own state.
      final shared = _rawDocs(fixture, '1').firstWhere((doc) => doc['sid'] == '22490906');
      final performer = (jsonDecode(_sample('S05-detail-live').body) as Map)['data'] as Map;
      expect((shared['uid'], shared['liveOn']), ('411865223', '0'));
      expect('${performer['uid']}', isNot(shared['uid']));
      expect(
        YyApi.searchAnchors(
          jsonEncode({
            'success': true,
            'status': 0,
            'data': {
              'searchResult': {
                'response': {
                  '1': {
                    'docs': [
                      {'sid': '87016563', 'name': 'Kasy', 'liveOn': '1'},
                      {'sid': '1355114567', 'name': 'kasy', 'liveOn': '0'},
                    ],
                  },
                },
              },
            },
          }),
        ).map((anchor) => anchor.liveStatus),
        [true, false],
      );
    });

    test('a failed search is ApiChanged, not an empty result', () {
      expect(() => YyApi.searchRooms('{"success":false,"status":1,"message":"x"}'), throwsA(isA<ApiChanged>()));
      expect(() => YyApi.searchRooms('{"success":true,"status":0,"data":{}}'), throwsA(isA<ApiChanged>()));
      expect(() => YyApi.searchRooms('<html>'), throwsA(isA<ApiChanged>()));
    });
  });

  group('S05 detail', () {
    test('S05-detail-live matches 3.x: popularity, danmaku arguments, link; start time; no `other` area', () {
      final fixture = _sample('S05-detail-live');
      final legacy = _legacy(fixture);
      final room = YyApi.liveDetail(fixture.body, requestedId: legacy['roomId'] as String, status: fixture.status)!;
      final expected = legacy['room'] as Map<String, dynamic>;
      // area: 6-3 (3.x wrote the raw biz `other`).
      _expectParity(room.toJson(), expected, changed: {'area'});
      expect(expected['area'], 'other');
      expect(room.area, isEmpty);
      _expectTitle(room.title, expected['title']);
      expect(room.danmakuData.toString(), expected['danmakuData']);
      expect(room.danmakuData, const YyDanmakuArgs(topSid: 22490906, subSid: 22490906));
      final data = room.data! as YyRoomData;
      expect((data.sid, data.ssid), ('22490906', '22490906'));
      // New keys (M2.1): the start is `startTime`; nothing says whether the
      // room is restricted.
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 16, 50, 18));
      expect(room.startedAt!.isBefore(fixture.capturedAt), isTrue);
      expect(room.toJson()['startedAt'], '2026-09-27T16:50:18.000Z');
      expect(room.restriction, isNull);
      expect(room.toJson().containsKey('restriction'), isFalse);
      expect(
        YyApi.liveDetail(fixture.body, requestedId: '22490906', areaNames: const {'other': '其他'})!.area,
        isEmpty,
        reason: '`other` names no area',
      );
      final dance = fixture.body.replaceFirst('"biz": "other"', '"biz": "dance"');
      expect(YyApi.liveDetail(dance, requestedId: '22490906', areaNames: const {'dance': '热舞'})!.area, '热舞');
      expect(YyApi.liveDetail(dance, requestedId: '22490906')!.area, '舞蹈', reason: 'C-21 preset; 3.x showed `dance`');
    });

    test('offline and unknown channels both answer data: null', () {
      for (final name in ['S05-detail-offline', 'S05-detail-missing']) {
        final fixture = _sample(name);
        expect(YyApi.liveDetail(fixture.body, requestedId: _legacy(fixture)['roomId'] as String), isNull);
      }
    });

    test('S05 an offline room without its page (refresh, recording) is 3.x’s', () {
      final legacy = _legacy(_sample('S05-detail-offline'))['room'] as Map<String, dynamic>;
      final room = YyApi.offlineRoom(requestedId: '85520900');
      _expectParity(room.toJson(), legacy);
      expect(room.toJson().keys, containsAll(legacy.keys.where((key) => key != 'danmakuData')));
      expect(
        (YyApi.offlineRoom(
                  requestedId: '2149',
                  channel: const YyRoomData(sid: '35340121', ssid: '35340121'),
                ).data!
                as YyRoomData)
            .sid,
        '35340121',
      );
    });

    test('S05 an offline room on entry keeps 3.x’s state and adds the streamer and title of its page', () {
      final page = YyApi.roomPage(_sample('S05-page-offline').body);
      final room = YyApi.offlineRoom(requestedId: '85520900', page: page);
      final legacy = _legacy(_sample('S05-detail-offline'))['room'] as Map<String, dynamic>;
      // 3.x had only the id and the state; the page names the streamer, the
      // channel title, its area and the room page.
      _expectParity(room.toJson(), legacy, changed: {'title', 'nick', 'avatar'});
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.nick, '小洲- 00000o0000');
      expect(room.title, startsWith('卓越988'));
      expect(room.avatar, startsWith('https://downhdlogo.yy.com/'));
      expect(room.area, '段子手');
      expect(room.link, 'https://www.yy.com/85520900');
      expect(room.startedAt, isNull);
      expect(room.restriction, isNull);
      // 6-7: 3.x gave offline rooms no danmaku arguments; the page names the
      // channel, and its chat is open while nobody broadcasts.
      expect(legacy['danmakuData'], isNull);
      expect(room.danmakuData, const YyDanmakuArgs(topSid: 85520900, subSid: 85520900));
      final short = YyApi.offlineRoom(requestedId: '2149', page: YyApi.roomPage(_sample('S05-page-asid').body));
      expect(
        short.danmakuData,
        const YyDanmakuArgs(topSid: 35340121, subSid: 35340121),
        reason: 'the canonical channel',
      );
      expect(YyApi.offlineRoom(requestedId: '85520900').danmakuData, isNull, reason: 'without the page, 3.x’s room');
    });

    test('room pages: the 404 page is NotFound; a short number names its canonical channel', () {
      expect(() => YyApi.roomPage(_sample('S05-page-missing').body), throwsA(isA<NotFound>()));
      final short = YyApi.roomPage(_sample('S05-page-asid').body);
      expect((short.sid, short.ssid), ('35340121', '35340121'));
      expect(short.title, '【晨一】晨一@小影');
      final live = YyApi.roomPage(_sample('S05-page-live').body);
      expect(live.nick, '燃舞蹈-福星', reason: 'the performer, as liveInfoDetail names it');
      expect(() => YyApi.roomPage('<html></html>'), throwsA(isA<ApiChanged>()));
      expect(() => YyApi.roomPage('', status: 503), throwsA(isA<NetworkFailure>()));
    });

    test('M4.D: a page naming its streamer YY用户 with the default portrait names nobody', () {
      final page = YyApi.roomPage(_sample('S05-page-placeholder').body);
      expect((page.sid, page.nick, page.avatar), ('1454853871', '', ''));
      expect(page.title, startsWith('8042~心儿'), reason: 'the channel title is real');
      final room = YyApi.offlineRoom(requestedId: '1454853871', page: page);
      expect((room.nick, room.avatar), ('', ''), reason: 'mergeFrom keeps a stored name and avatar');
    });

    test('another resultCode is ApiChanged (3.x threw FormatException)', () {
      expect(() => YyApi.liveDetail('{"resultCode":-1}', requestedId: '1'), throwsA(isA<ApiChanged>()));
      expect(() => YyApi.liveDetail('{"resultCode":0,"data":[]}', requestedId: '1'), throwsA(isA<ApiChanged>()));
    });
  });

  group('S06 stream-manager', () {
    for (final name in [
      'S06-streams-g1',
      'S06-streams-g2',
      'S06-streams-g2-l10',
      'S06-streams-g2-l14',
      'S06-streams-g3',
      'S06-streams-offline',
    ]) {
      test('$name: 3.x’s qualities with a web stream, and 3.x’s URLs', () {
        final fixture = _sample(name);
        final legacy = _legacy(fixture);
        final streams = YyApi.streams(fixture.body, status: fixture.status);
        // Gears without a stream_key (mix 1, 超清 here) have no web stream:
        // asking for them is answered with another gear (REG-YY-004).
        final web = _webGears(fixture);
        expect(
          YyApi.qualities(streams).map(
            (quality) => {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort, 'data': quality.data},
          ),
          [
            for (final quality in _legacyList(fixture, 'parsePlayQualities'))
              if (web.contains(quality['id'])) quality,
          ],
        );
        final resolution = YyApi.resolution(streams, issuedAt: fixture.capturedAt);
        expect(resolution.urls, legacy['parsePlayUrls']);
      });
    }

    test('lines: FLV, 3.x’s media headers, line_seq and the lease of t (issue + 600 s)', () {
      final fixture = _sample('S06-streams-g2');
      final resolution = YyApi.resolution(YyApi.streams(fixture.body), issuedAt: fixture.capturedAt, cookie: 'yyuid=1');
      final line = resolution.lines.single;
      expect(line.headers, {
        'origin': 'https://www.yy.com',
        'referer': 'https://www.yy.com/',
        'user-agent': YyApi.mediaUserAgent,
        'cookie': 'yyuid=1',
      });
      expect(line.format, StreamFormat.flv);
      expect(line.lineId, '14');
      final lease = line.lease!;
      expect(lease.expiresAt!.millisecondsSinceEpoch ~/ 1000, int.parse(Uri.parse(line.url).queryParameters['t']!));
      expect(lease.expiresAt!.difference(fixture.capturedAt).inSeconds, inInclusiveRange(599, 601));
      expect(lease.expiresAt!.difference(lease.refreshAt), YyApi.leaseLead);
      expect(lease.cutsConnection, isFalse);
      expect(resolution.appliedQualityData, '2');
      expect(resolution.qualityUnconfirmed, isFalse);
    });

    test('the applied gear is the stream served: gear 3 is answered with gear 2 (REG-YY-004)', () {
      final requested = {
        'S06-streams-g1': '1',
        'S06-streams-g2': '2',
        'S06-streams-g3': '2',
        'S06-streams-g2-l10': '2',
      };
      for (final MapEntry(key: name, value: gear) in requested.entries) {
        final fixture = _sample(name);
        expect(
          YyApi.resolution(YyApi.streams(fixture.body), issuedAt: fixture.capturedAt).appliedQualityData,
          gear,
          reason: name,
        );
      }
      final g3 = _sample('S06-streams-g3');
      final streams = YyApi.streams(g3.body);
      final shown = resolveAppliedPlayQuality(
        qualities: YyApi.qualities(streams),
        requested: const LivePlayQuality(quality: '超清', id: '3', data: '3'),
        resolution: YyApi.resolution(streams, issuedAt: g3.capturedAt),
      );
      expect(shown.quality, '高清');
    });

    test('line_seq picks the CDN', () {
      final l10 = _sample('S06-streams-g2-l10');
      final l14 = _sample('S06-streams-g2-l14');
      expect(
        Uri.parse(YyApi.resolution(YyApi.streams(l10.body), issuedAt: l10.capturedAt).urls.single).host,
        'tx-flv-web.yy.com',
      );
      expect(
        Uri.parse(YyApi.resolution(YyApi.streams(l14.body), issuedAt: l14.capturedAt).urls.single).host,
        'ks-flv-web.yy.com',
      );
    });

    test('an offline channel lists no gear and no line', () {
      final fixture = _sample('S06-streams-offline');
      final streams = YyApi.streams(fixture.body);
      expect(YyApi.qualities(streams), isEmpty);
      expect(YyApi.resolution(streams, issuedAt: fixture.capturedAt).hasSources, isFalse);
      expect(YyApi.otherLines(streams), isEmpty);
    });

    test('6-4: the other CDN line of the served stream, from stream_line_list', () {
      final lines = {
        for (final name in ['S06-streams-g1', 'S06-streams-g2', 'S06-streams-g2-l10', 'S06-streams-g3'])
          name: YyApi.otherLines(YyApi.streams(_sample(name).body)),
      };
      expect(lines, {
        'S06-streams-g1': [10],
        'S06-streams-g2': [10],
        'S06-streams-g2-l10': [14],
        'S06-streams-g3': [10],
      });
      expect(
        YyApi.otherLines({
          'avp_info_res': {
            'stream_line_addr': {
              'k': {'line_seq': 3},
            },
            'stream_line_list': {
              'k': {
                'line_infos': [
                  {'line_seq': 3},
                  {'line_seq': '5'},
                  {'line_seq': 5},
                  {'line_seq': -1},
                  'bad',
                ],
              },
            },
          },
        }),
        [5],
      );
    });

    test('6-4: the lines of one gear on both CDNs, each with its own lease; another gear is left out', () {
      final g2 = _sample('S06-streams-g2');
      final l10 = _sample('S06-streams-g2-l10');
      final first = YyApi.resolution(YyApi.streams(g2.body), issuedAt: g2.capturedAt);
      final other = YyApi.resolution(YyApi.streams(l10.body), issuedAt: l10.capturedAt);
      final merged = YyApi.withLines(first, [other]);
      expect(merged.lines.map((line) => (line.lineId, Uri.parse(line.url).host)), [
        ('14', 'ks-flv-web.yy.com'),
        ('10', 'tx-flv-web.yy.com'),
      ]);
      expect(merged.lines.map((line) => line.format), everyElement(StreamFormat.flv));
      expect(merged.lines.last.lease!.expiresAt!.difference(l10.capturedAt).inSeconds, inInclusiveRange(599, 601));
      expect(merged.appliedQualityData, '2');
      expect(merged.qualityUnconfirmed, isFalse);
      final g1 = _sample('S06-streams-g1');
      final lower = YyApi.resolution(YyApi.streams(g1.body), issuedAt: g1.capturedAt);
      expect(YyApi.withLines(first, [lower]).lines, hasLength(1), reason: 'gear 1 is another quality');
      expect(YyApi.withLines(first, [first]).lines, hasLength(1), reason: 'the same URL once');
      final unknown = LivePlayUrlResolution.lines(first.lines, qualityUnconfirmed: true);
      expect(YyApi.withLines(unknown, [other]).lines, hasLength(1), reason: 'the served gear is unknown');
    });

    test('6-4: the request for another line is the recorded one (line_seq 10, the served gear)', () {
      final fixture = _sample('S06-streams-g2-l10');
      final recorded = jsonDecode((fixture.meta['request'] as Map)['body'] as String) as Map<String, dynamic>;
      final body = YyApi.streamManagerBody(
        sid: '22490906',
        ssid: '22490906',
        gear: 2,
        sequence: (recorded['head'] as Map)['seq'] as int,
        line: 10,
      );
      expect((jsonDecode(jsonEncode(body)) as Map)['avp_parameter'], recorded['avp_parameter']);
      expect(
        (YyApi.streamManagerBody(sid: '1', ssid: '1', gear: 1, sequence: 0)['avp_parameter']! as Map)['line_seq'],
        -1,
        reason: '3.x let the server choose',
      );
    });

    test('quality ids once stream-manager lists the qualities (M9): 4000 is the best stream, 1200 the lowest', () {
      final gears = YyApi.qualities(YyApi.streams(_sample('S06-streams-g1').body));
      expect(gears.map((quality) => quality.id), ['2', '1']);
      expect(YyApi.flvQualityId('mobile-hls:4000', gears), '2');
      expect(YyApi.flvQualityId('mobile-hls:1200', gears), '1');
      const bluRay = [
        LivePlayQuality(quality: '蓝光', id: '4', data: '4', sort: 4000),
        LivePlayQuality(quality: '高清', id: '2', data: '2', sort: 2300),
        LivePlayQuality(quality: '流畅', id: '1', data: '1', sort: 600),
      ];
      expect(YyApi.flvQualityId('mobile-hls:4000', bluRay), '4', reason: '4000 serves …_0_0_0, 蓝光 there');
      expect(YyApi.flvQualityId('mobile-hls:1200', bluRay), '1');
      expect(YyApi.flvQualityId('2', bluRay), '2');
      expect(YyApi.flvQualityId('mobile-hls:4000', const []), isNull);
    });

    test('3.x test: one quality per gear; a name used twice gets the gear; URLs validated', () {
      String stream(String key, String json) => jsonEncode({'stream_key': key, 'json': json});
      final streams = jsonDecode('''
{
        "channel_stream_info": {"streams": [
          ${stream('a', '{"gear_info":{"name":"高清","gear":"4"},"rate":"4000"}')},
          ${stream('b', '{"gear_info":{"name":"高清","gear":"2"},"rate":2000}')},
          ${stream('duplicate', '{"gear_info":{"name":"重复","gear":"2"},"rate":1000}')},
          {"json": "{\\"gear_info\\":{\\"name\\":\\"超清\\",\\"gear\\":\\"3\\"},\\"rate\\":3000}"}
        ]},
        "avp_info_res": {"stream_line_addr": {
          "a": {"line_seq": 1, "cdn_info": {"url": "//cdn.test/live.flv?t=1"}},
          "duplicate": {"cdn_info": {"url": "https://cdn.test/live.flv?t=1"}},
          "bad": {"cdn_info": {"url": "javascript:alert(1)"}}
        }}
      }''') as Map<String, dynamic>;
      expect(YyApi.qualities(streams).map((quality) => (quality.id, quality.quality)), [
        ('4', '高清 · 4'),
        ('2', '高清 · 2'),
      ]);
      final resolution = YyApi.resolution(streams, issuedAt: DateTime.utc(2026));
      expect(resolution.urls, ['https://cdn.test/live.flv?t=1']);
      expect(resolution.lines.single.lease, isNull, reason: 't=1 is long past');
      expect(resolution.appliedQualityData, '4');
    });

    test('the request body is 3.x’s JSON; errors are typed', () {
      final fixture = _sample('S06-streams-g2');
      final recorded = jsonDecode((fixture.meta['request'] as Map)['body'] as String) as Map<String, dynamic>;
      final body = YyApi.streamManagerBody(
        sid: '22490906',
        ssid: '22490906',
        gear: 2,
        sequence: (recorded['head'] as Map)['seq'] as int,
      );
      // The recording asked as Chrome 140 at 1920×1080; 3.x's body says
      // Chrome 128 at 1366×768.
      final client = {
        ...recorded['client_attribute'] as Map,
        'osversion': '128.0.0.0',
        'width': '1366',
        'height': '768',
      };
      expect(jsonDecode(jsonEncode(body)), {...recorded, 'client_attribute': client});
      expect(
        () => YyApi.streams(r'{"res_code":500,"msg":"{\"code\":100001,\"detail\":\"call timeout\"}"}', status: 500),
        throwsA(isA<NetworkFailure>()),
      );
      expect(() => YyApi.streams('ErrAuthNotPass', status: 403), throwsA(isA<ApiChanged>()));
      expect(() => YyApi.streams('<html>'), throwsA(isA<ApiChanged>()));
    });
  });

  group('S07 mobile HLS', () {
    test('S07-mobile-hls: 3.x’s payload, quality and URL', () {
      final fixture = _sample('S07-mobile-hls');
      final legacy = _legacy(fixture);
      final hls = YyApi.mobileHls(fixture.body, status: fixture.status)!;
      final payload = legacy['parseMobileHlsPayload'] as Map<String, dynamic>;
      expect(hls.url.toString(), payload['hls']);
      expect((hls.width, hls.height, hls.video), (payload['width'], payload['height'], payload['video']));
      final qualities = YyApi.mobileQualities([(rate: '1200', hls: hls), (rate: '4000', hls: null)]);
      expect([
        for (final quality in qualities)
          {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort, 'data': quality.data},
      ], legacy['mobileQualities']);
      final resolution = YyApi.mobileResolution(hls, rate: '1200', cookie: 'yyuid=1');
      expect(resolution.urls, legacy['getPlayUrls']);
      final line = resolution.lines.single;
      expect(line.format, StreamFormat.hls);
      expect(line.headers, YyApi.mediaHeaders(cookie: 'yyuid=1'));
      expect(line.lease, isNull, reason: 'the HLS t is the issue time, not an expiry');
      expect(resolution.appliedQualityData, 'mobile-hls:1200');
      expect(YyApi.mobileResolution(hls).appliedQualityData, isNull, reason: 'a fallback confirms nothing');
    });

    test('S07-mobile-hls-offline: no stream (3.x: null)', () {
      final fixture = _sample('S07-mobile-hls-offline');
      expect(_legacy(fixture)['parseMobileHlsPayload'], isNull);
      expect(YyApi.mobileHls(fixture.body, status: fixture.status), isNull);
    });

    test('3.x test: rates serving the same stream keep the higher; other codes and schemes are no stream', () {
      YyMobileHls hls(String video, int width, int height) =>
          (url: Uri.parse('https://sslproxy.yy.com/$video.m3u8'), width: width, height: height, video: video);
      final same = YyApi.mobileQualities([
        (rate: '1200', hls: hls('v0', 720, 1280)),
        (rate: '4000', hls: hls('v0', 720, 1280)),
      ]);
      expect(same.map((quality) => (quality.quality, quality.id)), [('高清 · 720p', 'mobile-hls:4000')]);
      final both = YyApi.mobileQualities([
        (rate: '1200', hls: hls('v1', 360, 640)),
        (rate: '4000', hls: hls('v0', 720, 1280)),
      ]);
      expect(both.map((quality) => quality.quality), ['高清 · 720p', '流畅 · 360p']);
      expect(YyApi.mobileHls('{"code":1,"hls":"https://cdn.test/live.m3u8"}'), isNull);
      expect(YyApi.mobileHls('{"code":0,"hls":"javascript:alert(1)"}'), isNull);
      expect(() => YyApi.mobileHls('not-json'), throwsA(isA<ApiChanged>()));
    });
  });

  group('headers and arguments', () {
    test('API headers are 3.x’s getHeaders; media headers 3.x’s PlaybackHeaderResolver', () {
      expect(YyApi.apiHeaders(), {
        'accept': '*/*',
        'origin': 'https://www.yy.com',
        'referer': 'https://www.yy.com/',
        'sec-fetch-dest': 'empty',
        'sec-fetch-mode': 'cors',
        'sec-fetch-site': 'same-site',
        'user-agent': YyApi.userAgent,
      });
      expect(YyApi.apiHeaders(cookie: ' a=1 ')['cookie'], 'a=1');
      expect(YyApi.mediaHeaders(), {
        'origin': 'https://www.yy.com',
        'referer': 'https://www.yy.com/',
        'user-agent': YyApi.mediaUserAgent,
      });
      expect(YyApi.streamManagerHeaders('1', '2'), containsPair('content-type', 'text/plain;charset=UTF-8'));
      expect(YyApi.streamManagerHeaders('1', '2'), containsPair('referer', 'https://www.yy.com/1/2'));
      expect(YyApi.mobileHlsHeaders('1', '2'), containsPair('referer', 'https://wap.yy.com/mobileweb/1/2'));
      expect(YyApi.mobileHlsHeaders('1', '2'), containsPair('user-agent', YyApi.mobileUserAgent));
    });

    test('danmaku arguments print as 3.x’s', () {
      expect(const YyDanmakuArgs(topSid: 1, subSid: 2).toString(), '{"topSid":1,"subSid":2}');
    });

    test('a lease a quarter of a short lifetime early; none past expiry', () {
      final issued = DateTime.utc(2026, 9, 27);
      final seconds = issued.millisecondsSinceEpoch ~/ 1000;
      final short = YyApi.lease(Uri.parse('https://cdn.test/a.flv?t=${seconds + 120}'), issued)!;
      expect(short.expiresAt!.difference(short.refreshAt), const Duration(seconds: 30));
      expect(YyApi.lease(Uri.parse('https://cdn.test/a.flv?t=${seconds - 1}'), issued), isNull);
      expect(YyApi.lease(Uri.parse('https://cdn.test/a.flv'), issued), isNull);
    });
  });
}
