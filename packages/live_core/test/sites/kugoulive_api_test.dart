// Kugou Live parsing against the recorded samples, compared field by field
// with 3.x's frozen output (expected.json, written by
// fixtures/kugoulive/legacy_expected.dart from 3.x's KugouLiveApi,
// KugouLiveLink and KugouLiveSite). Every intended difference is listed
// with its reason; everything else must match. The synthetic cases port the
// parsing parts of 3.x's kugou_live_site_test.dart and cover the pitfalls of
// the archived spec (§10) and the shapes 3.x refused.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('kugoulive', name);

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

/// The value of a traced legacy call (`{requests, value}`).
Object? _value(String name, String key) => (_legacy(name)[key] as Map<String, dynamic>)['value'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

/// 3.x wrote its media headers into every room (`httpHeaders`), where only
/// IPTV's are read: its PlaybackHeaderResolver has no Kugou Live branch.
/// They now travel on every line.
const _headersMoved = {'httpHeaders'};

/// A list row as the platform sends it (3.x's test `_directoryJson` rows).
Map<String, Object?> _row(Map<String, Object?> changes) => {
  'roomId': 5085706,
  'userId': 1826299225,
  'kugouId': 1826299225,
  'nickName': '小初CHU',
  'label': '一起看烟花',
  'imgPath': 'http://p3.fx.kgimg.com/v2/fxroomcover/cover.jpg',
  'userLogo': 'http://p3.fx.kgimg.com/v2/fxuserlogo/avatar.jpg',
  'viewerNum': 79,
  'hot': 11266,
  'fansCount': 6539,
  'liveStatus': 1,
  ...changes,
};

String _list(List<Object?> rows, {Object? hasNextPage = 1}) => jsonEncode({
  'code': 0,
  'data': {'hasNextPage': hasNextPage, 'list': rows},
});

/// A room info answer (3.x's test `_roomJson`).
String _roomInfo({Map<String, Object?> info = const {}, Map<String, Object?> data = const {}}) => jsonEncode({
  'code': 0,
  'data': {
    'liveSessionId': 'fixture-session',
    'liveType': 0,
    'normalRoomInfo': {
      'fansCount': 9083,
      'imgPath': '/v2/fxroomcover/cover.jpg',
      'kugouId': 1797665793,
      'limitType': 0,
      'nickName': 'Q梦星冉',
      'publicMesg': '如果做人必须得有抱负',
      'privateMesg': '一起看烟花',
      'userId': 1797665793,
      'userLogo': '/v2/fxuserlogo/avatar.jpg',
      ...info,
    },
    ...data,
  },
});

/// A signed media URL (3.x's test `_signedUrl`).
String _signed(String host, {String room = '5085706', String path = 'fx_hifi_1797665793.flv', String line = '105'}) =>
    'https://$host/live/$path?cn=fx&txSecret=0123456789abcdef0123456789abcdef'
    '&txTime=6AB1DA15&token=0-$room-0-1010-7-1000-fixture-$line';

String _streams(List<Object?> lines, {Object? status = 1, Object? roomId = 5085706}) => jsonEncode({
  'code': 0,
  'data': {'status': status, 'roomId': roomId, 'lines': lines},
});

void main() {
  group('S01 home page areas', () {
    test('areas and the catalog match 3.x (推荐 included, personal routes left out)', () {
      final fixture = _sample('S01-home');
      final areas = KugouLiveApi.areas(fixture.body, status: fixture.status);
      final legacy = _maps(_legacy('S01-home')['parseCategoriesHtml']);
      expect(areas.map((area) => area.areaId), legacy.map((area) => area['id']));
      expect(areas.map((area) => area.areaName), legacy.map((area) => area['name']));
      expect(areas.first.areaId, KugouLiveApi.recommendAreaId);
      for (final (key, size) in [('getCategores(1, 1000)', 1000), ('getCategores(1, 3)', 3)]) {
        final categories = KugouLiveApi.catalog(areas, size);
        final legacyCategories = _maps(_value('S01-home', key));
        expect(categories, hasLength(1));
        expect(categories.single.id, legacyCategories.single['id']);
        expect(categories.single.name, legacyCategories.single['name']);
        final legacyAreas = _maps(legacyCategories.single['children']);
        expect(categories.single.children, hasLength(legacyAreas.length), reason: key);
        for (final (index, area) in categories.single.children.indexed) {
          _expectParity(area.toJson(), legacyAreas[index], reason: '$key[$index]');
        }
      }
    });

    test('a page without area links gives 3.x fixed list', () {
      final areas = KugouLiveApi.areas('<html><body>no categories</body></html>');
      final legacy = _maps(_legacy('S01-home')['parseCategoriesHtml(no links)']);
      expect(
        [for (final area in areas) (area.areaId, area.areaName)],
        [for (final area in legacy) (area['id'], area['name'])],
      );
      expect(areas.every((area) => area.platform == 'kugoulive' && area.areaType == 'official'), isTrue);
    });

    test('3.x link rule: title required, page order, once each, entities decoded', () {
      final areas = KugouLiveApi.areas('''
        <a href="/pcindex/category/3001" title="关注">关注</a>
        <a href="/pcindex/category/8000" title="推荐">推荐</a>
        <a href='https://fanxing.kugou.com/pcindex/category/7024?x=1' class="tab" title='舞蹈 &amp; 热舞'>舞蹈</a>
        <a href="/pcindex/category/7024" title="重复">重复</a>
        <a href="/pcindex/category/1009" target="_blank">颜值</a>
        <a href="/pcindex/category/3009" title="我看过的"></a>
      ''');
      expect([for (final area in areas) (area.areaId, area.areaName)], [('8000', '推荐'), ('7024', '舞蹈 & 热舞')]);
    });

    test('the home page status is checked', () {
      expect(() => KugouLiveApi.areas('', status: 503), throwsA(isA<NetworkFailure>()));
      expect(() => KugouLiveApi.areas('', status: 403), throwsA(isA<RiskControl>()));
    });
  });

  group('S02/S03 room lists', () {
    for (final (sample, page) in [('S02-recommend-p1', 1), ('S02-recommend-p2', 2)]) {
      test('$sample: the rooms, their order and paging match 3.x', () {
        final fixture = _sample(sample);
        final result = KugouLiveApi.directoryPage(fixture.body, page: page, status: fixture.status);
        final legacy = _value(sample, 'getDirectoryPage($page)')! as Map<String, dynamic>;
        final rooms = _maps(legacy['rooms']);
        expect(result.page, legacy['page']);
        expect(result.hasMore, legacy['hasMore']);
        expect(result.rooms.map((room) => room.roomId), rooms.map((room) => room['roomId']));
        for (final (index, room) in result.rooms.indexed) {
          _expectParity(_projection(room), rooms[index], changed: _headersMoved, reason: '$sample[$index]');
          expect(room.httpHeaders, isEmpty);
        }
      });
    }

    test('S03 area rows are wrapped as `star`; `status` is the state; the last page', () {
      final fixture = _sample('S03-area-7024-p1');
      final result = KugouLiveApi.directoryPage(fixture.body, page: 1, status: fixture.status);
      final legacy = _value('S03-area-7024-p1', 'getDirectoryPage(1, 7024)')! as Map<String, dynamic>;
      final rooms = _maps(legacy['rooms']);
      expect(result.hasMore, isFalse);
      expect(legacy['hasMore'], isFalse);
      expect(result.rooms, hasLength(rooms.length));
      for (final (index, room) in result.rooms.indexed) {
        _expectParity(_projection(room), rooms[index], changed: _headersMoved, reason: 'S03[$index]');
        expect(room.liveStatus, LiveStatus.live);
        expect(room.onlineViewers, isNotEmpty, reason: '`getViewerNum`');
      }
    });

    test('pitfall: a phone broadcast (`liveStatus` 6) stays unknown, as 3.x showed it', () {
      final fixture = _sample('S02-recommend-p2');
      final raw = ((jsonDecode(fixture.body) as Map)['data'] as Map)['list'] as List;
      final phones = {
        for (final row in raw.cast<Map<String, dynamic>>())
          if (row['liveStatus'] == 6) '${row['roomId']}',
      };
      expect(phones, {'50595748', '50236352'});
      final rooms = KugouLiveApi.directoryPage(fixture.body, page: 2).rooms;
      for (final room in rooms.where((room) => phones.contains(room.roomId))) {
        expect(room.liveStatus, LiveStatus.unknown, reason: room.roomId);
      }
      // The room itself is live (S04-room-mobile, liveType 2 with a session).
      final mobile = _sample('S04-room-mobile');
      expect(KugouLiveApi.roomInfo(mobile.body, roomId: '50595748').state, KugouLiveState.live);
    });

    test('3.x cards keep viewers, popularity and followers apart', () {
      final page = KugouLiveApi.directoryPage(
        _list([
          _row({}),
          {
            'uiType': 'star',
            'data': {
              'roomId': 3437578,
              'userId': 1454781559,
              'kugouId': 1454781559,
              'nickName': '圆周率zz',
              'label': '能吹能唱能跳',
              'getViewerNum': 8,
              'hot': 32895,
              'fansCount': 30283,
              'status': 1,
            },
          },
        ]),
        page: 1,
      );
      expect(page.hasMore, isTrue);
      expect(page.rooms, hasLength(2));
      final first = page.rooms.first;
      expect((first.onlineViewers, first.popularity, first.followers, first.watching), ('79', '11266', '6539', '79'));
      expect(first.audienceMetricType, AudienceMetricType.onlineViewers);
      expect(first.userId, '1826299225');
      expect(first.link, 'https://fanxing.kugou.com/5085706');
      expect(first.area, '酷狗直播');
      expect(first.notice, KugouLiveApi.chatNotice);
      expect(first.cover, 'https://p3.fx.kgimg.com/v2/fxroomcover/cover.jpg', reason: 'http made https');
      expect(page.rooms.last.onlineViewers, '8');
      expect(page.rooms.last.liveStatus, LiveStatus.live);
    });

    test('card fallbacks and checks follow 3.x', () {
      LiveRoom card(Map<String, Object?> changes) => KugouLiveApi.card(_row(changes))!;
      expect(card({'label': '', 'topicContent': '话题'}).title, '话题');
      expect(card({'label': null, 'performContent': '表演'}).title, '表演');
      expect(card({'label': 'null'}).title, '小初CHU');
      expect(card({'label': '', 'nickName': ''}).title, 'Kugou Live');
      expect(card({'nickName': ' '}).nick, 'Kugou Live');
      expect(card({'userId': ''}).userId, '1826299225', reason: 'kugouId when userId is empty');
      expect(card({'userLogo': null}).avatar, 'https://p3.fx.kgimg.com/v2/fxroomcover/cover.jpg');
      expect(card({'userLogo': null, 'logo': '//p3.fx.kgimg.com/a.jpg'}).avatar, 'https://p3.fx.kgimg.com/a.jpg');
      expect(card({'userLogo': '', 'logo': 'https://p3.fx.kgimg.com/a.jpg'}).avatar, card({}).cover, reason: '3.x');
      expect(card({'imgPath': null, 'imagePath': '/v2/x.jpg'}).cover, 'https://p3.fx.kgimg.com/v2/x.jpg');
      expect(card({'viewerNum': null}).audienceMetricType, AudienceMetricType.popularity);
      expect(card({'viewerNum': null}).watching, '11266');
      final bare = card({'viewerNum': null, 'hot': null, 'fansCount': null});
      expect((bare.audienceMetricType, bare.watching, bare.followers), (AudienceMetricType.unknown, '', ''));
      expect(card({'viewerNum': '0'}).onlineViewers, '0', reason: 'a zero is a value (search rows)');
      for (final (value, status) in [
        (1, LiveStatus.live),
        ('1', LiveStatus.live),
        (0, LiveStatus.offline),
        (-1, LiveStatus.offline),
        (6, LiveStatus.unknown),
        (2, LiveStatus.unknown),
        (null, LiveStatus.unknown),
      ]) {
        expect(card({'liveStatus': value}).liveStatus, status, reason: '$value');
      }
      expect(card({'liveStatus': null, 'status': 0, 'liveType': 1}).liveStatus, LiveStatus.offline);
      expect(card({'liveStatus': null, 'liveType': 1}).liveStatus, LiveStatus.live);
      for (final id in [null, '', '12', 0, '012345', 123456789012, 'abc']) {
        expect(KugouLiveApi.card(_row({'roomId': id})), isNull, reason: '$id');
      }
    });

    test('images follow 3.x allow list and rewrites', () {
      for (final (raw, expected) in [
        ('/v2/fxuserlogo//v2/fxuserlogo/a.jpg', 'https://p3.fx.kgimg.com/v2/fxuserlogo/a.jpg'),
        ('//s1.fx.kgimg.com/a.png', 'https://s1.fx.kgimg.com/a.png'),
        ('http://p3.fx.kgimg.com/a.jpg_45x45.jpg', 'https://p3.fx.kgimg.com/a.jpg_45x45.jpg'),
        ('https://singerimg.kugou.com/a.jpg', 'https://singerimg.kugou.com/a.jpg'),
        ('https://kgimg.com/a.jpg', 'https://kgimg.com/a.jpg'),
        ('https://p3.fx.kgimg.com:443/a.jpg', 'https://p3.fx.kgimg.com:443/a.jpg'),
        ('https://p3.fx.kgimg.com:8443/a.jpg', ''),
        ('https://user@p3.fx.kgimg.com/a.jpg', ''),
        ('https://evil.test/a.jpg', ''),
        ('https://kgimg.com.evil.test/a.jpg', ''),
        ('ftp://p3.fx.kgimg.com/a.jpg', ''),
        ('null', ''),
        (null, ''),
        (' ', ''),
      ]) {
        expect(KugouLiveApi.image(raw), expected, reason: '$raw');
      }
    });

    test('a room once per page; answers 3.x refused', () {
      final page = KugouLiveApi.directoryPage(
        _list([
          _row({}),
          _row({'label': 'again'}),
          'not a row',
          {'uiType': 'star', 'data': 'not a row'},
        ], hasNextPage: true),
        page: 3,
      );
      expect(page.rooms.map((room) => room.title), ['一起看烟花']);
      expect((page.page, page.hasMore), (3, true));
      expect(KugouLiveApi.directoryPage(_list([], hasNextPage: 0), page: 1).hasMore, isFalse);
      expect(KugouLiveApi.directoryPage(_list([_row({})], hasNextPage: null), page: 1).hasMore, isFalse);
      for (final body in [
        'not json',
        '[]',
        jsonEncode({'code': 1, 'msg': 'busy', 'data': <String, Object?>{}}),
        jsonEncode({'code': 0, 'data': <String, Object?>{}}),
        jsonEncode({'code': 0}),
      ]) {
        expect(() => KugouLiveApi.directoryPage(body, page: 1), throwsA(isA<ApiChanged>()), reason: body);
      }
      expect(
        () => KugouLiveApi.directoryPage('x' * (KugouLiveApi.responseLimit + 1), page: 1),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('the list URLs are 3.x requests, byte for byte', () {
      final recommend = (_legacy('S02-recommend-p1')['getDirectoryPage(1)'] as Map)['requests'] as List;
      expect('${KugouLiveApi.directoryUrl(1, '8000')}', (recommend.single as Map)['url']);
      final area = (_legacy('S03-area-7024-p1')['getDirectoryPage(1, 7024)'] as Map)['requests'] as List;
      expect('${KugouLiveApi.directoryUrl(1, '7024')}', (area.single as Map)['url']);
      expect(KugouLiveApi.directoryUrl(2, '8000').queryParameters['page'], '2');
    });

    test('areas: 推荐 by default; other platforms, types and ids are caller errors', () {
      const area = LiveArea(platform: 'kugoulive', areaType: 'official', areaId: ' 7024 ');
      expect(KugouLiveApi.areaId(null), '8000');
      expect(KugouLiveApi.areaId(area), '7024');
      // 3.x refused ids outside the catalog it had loaded (or its fixed list).
      expect(
        KugouLiveApi.areaId(const LiveArea(platform: 'kugoulive', areaType: 'official', areaId: '100003')),
        '100003',
      );
      for (final bad in const [
        LiveArea(platform: 'huya', areaType: 'official', areaId: '7024'),
        LiveArea(platform: 'kugoulive', areaType: 'custom', areaId: '7024'),
        LiveArea(platform: 'kugoulive', areaType: 'official', areaId: 'dance'),
        LiveArea(platform: 'kugoulive', areaType: 'official', areaId: '123456789'),
      ]) {
        expect(() => KugouLiveApi.areaId(bad), throwsArgumentError, reason: '$bad');
      }
    });
  });

  group('S04 room info', () {
    for (final (sample, id, status) in [
      ('S04-room-live', '3197156', LiveStatus.live),
      ('S04-room-mobile', '50595748', LiveStatus.live),
      ('S04-room-offline', '1014306', LiveStatus.offline),
    ]) {
      test('$sample: the refresh room matches 3.x', () {
        final fixture = _sample(sample);
        final (:room, :state) = KugouLiveApi.roomInfo(fixture.body, roomId: id, status: fixture.status);
        _expectParity(
          _projection(room),
          _value(sample, 'getRoomDetailForRefresh')! as Map<String, dynamic>,
          changed: _headersMoved,
          reason: sample,
        );
        expect(room.liveStatus, status);
        expect(state, status == LiveStatus.live ? KugouLiveState.live : KugouLiveState.offline);
        expect(_value(sample, 'getLiveStatus'), status == LiveStatus.live);
        expect((room.watching, room.onlineViewers, room.popularity), ('', '', ''), reason: 'the lists have them');
      });
    }

    test('pitfall: the title is `publicMesg`, as 3.x showed it (`privateMesg` is not the list label)', () {
      final fixture = _sample('S04-room-live');
      final info = ((jsonDecode(fixture.body) as Map)['data'] as Map)['normalRoomInfo'] as Map;
      final room = KugouLiveApi.roomInfo(fixture.body, roomId: '3197156').room;
      expect(room.title, info['publicMesg']);
      final card = KugouLiveApi.directoryPage(_sample('S02-recommend-p1').body, page: 1).rooms.first;
      expect(card.roomId, '3197156');
      expect(card.title, isNot(info['privateMesg']), reason: 'the archived spec assumed they match');
    });

    test('S04-room-notfound is NotFound (3.x showed a room named "Kugou Live")', () {
      final fixture = _sample('S04-room-notfound');
      final legacy = _value('S04-room-notfound', 'getRoomDetailForRefresh')! as Map<String, dynamic>;
      expect((legacy['nick'], legacy['title'], legacy['liveStatus']), ('Kugou Live', 'Kugou Live', 3));
      expect(() => KugouLiveApi.roomInfo(fixture.body, roomId: '999'), throwsA(isA<NotFound>()));
    });

    test('the states: restricted, offline, live, no session', () {
      ({LiveRoom room, KugouLiveState state}) parse({
        Map<String, Object?> info = const {},
        Map<String, Object?> data = const {},
      }) => KugouLiveApi.roomInfo(
        _roomInfo(info: info, data: data),
        roomId: '5085706',
      );
      final restricted = parse(info: {'limitType': 2}, data: {'liveType': -1});
      expect(restricted.state, KugouLiveState.restricted);
      expect(restricted.room.liveStatus, LiveStatus.unknown);
      expect(restricted.room.notice, '${KugouLiveApi.restrictedNotice}\n${KugouLiveApi.chatNotice}');
      expect(parse(data: {'liveType': -1}).state, KugouLiveState.offline);
      expect(parse(data: {'liveType': '-1', 'liveSessionId': 'x'}).state, KugouLiveState.offline);
      expect(parse(data: {'liveType': 2}).state, KugouLiveState.live);
      final unknown = parse(data: {'liveSessionId': ''});
      expect(unknown.state, KugouLiveState.unknown);
      expect(unknown.room.liveStatus, LiveStatus.unknown);
      expect(KugouLiveApi.playbackError(KugouLiveState.live, '1'), isNull);
      expect(KugouLiveApi.playbackError(KugouLiveState.offline, '1'), isA<StreamUnavailable>());
      expect(KugouLiveApi.playbackError(KugouLiveState.unknown, '1'), isA<StreamUnavailable>());
      expect(KugouLiveApi.playbackError(KugouLiveState.restricted, '1'), isA<NeedsLogin>());
    });

    test('3.x detail fields: title and nick fallbacks, images, followers, identity', () {
      final room = KugouLiveApi.roomInfo(_roomInfo(), roomId: '5085706').room;
      expect(room.roomId, '5085706');
      expect(room.title, '如果做人必须得有抱负');
      expect(room.nick, 'Q梦星冉');
      expect(room.avatar, 'https://p3.fx.kgimg.com/v2/fxuserlogo/avatar.jpg');
      expect(room.cover, 'https://p3.fx.kgimg.com/v2/fxroomcover/cover.jpg');
      expect(room.followers, '9083');
      expect(room.audienceMetricType, AudienceMetricType.unknown);
      expect(KugouLiveApi.roomInfo(_roomInfo(info: {'publicMesg': ''}), roomId: '5085706').room.title, '一起看烟花');
      final nameless = KugouLiveApi.roomInfo(
        _roomInfo(info: {'publicMesg': null, 'privateMesg': 'null', 'nickName': ''}),
        roomId: '5085706',
      ).room;
      expect((nameless.nick, nameless.title), ('Kugou Live', 'Kugou Live'), reason: 'a room with a kugouId exists');
      expect(
        () => KugouLiveApi.roomInfo(_roomInfo(info: {'nickName': '', 'kugouId': '0'}), roomId: '5085706'),
        throwsA(isA<NotFound>()),
      );
      expect(
        () => KugouLiveApi.roomInfo(_roomInfo(info: {'nickName': null, 'kugouId': null}), roomId: '5085706'),
        throwsA(isA<NotFound>()),
      );
    });

    test('broken answers are ApiChanged', () {
      for (final body in [
        jsonEncode({
          'code': 0,
          'data': {'liveType': 0},
        }),
        jsonEncode({
          'code': 0,
          'data': {'normalRoomInfo': 'x', 'liveType': 0},
        }),
        jsonEncode({'code': 110, 'msg': '系统繁忙', 'data': <String, Object?>{}}),
        '<html>',
      ]) {
        expect(() => KugouLiveApi.roomInfo(body, roomId: '5085706'), throwsA(isA<ApiChanged>()), reason: body);
      }
      expect(KugouLiveApi.roomInfoUrl('3197156').toString(), startsWith('https://service2.fanxing.kugou.com/'));
      final requests = (_legacy('S04-room-live')['getRoomDetailForRefresh'] as Map)['requests'] as List;
      expect('${KugouLiveApi.roomInfoUrl('3197156')}', (requests.single as Map)['url']);
    });
  });

  group('S05 streams', () {
    List<KugouLiveVariant> live() => KugouLiveApi.variants(_sample('S05-stream-live').body, roomId: '3197156');

    test('the variants match 3.x (one FLV tier, both lines, each URL once)', () {
      final legacy = _maps(_legacy('S05-stream-live')['parseMediaJson(3197156)']);
      final variants = live();
      expect(variants.map((variant) => variant.id), legacy.map((variant) => variant['id']));
      for (final (index, variant) in variants.indexed) {
        final expected = legacy[index];
        expect(
          (variant.protocol, variant.rate, variant.codec, variant.layout),
          (expected['protocol'], expected['rate'], expected['codec'], expected['layout']),
        );
        expect(variant.lines.map((line) => line.url), expected['urls']);
      }
      final entered = _legacy('S04-room-live')['data.variants'];
      expect(entered, _legacy('S05-stream-live')['parseMediaJson(3197156)']);
    });

    test('lines carry the media headers, FLV, H.264, the line and the lease', () {
      final lines = live().single.lines;
      expect(lines.map((line) => line.lineId), ['sid5', 'sid40']);
      expect(lines.map((line) => Uri.parse(line.url).host), [
        'tx105.liveplay.live.kugou.com',
        'tx2.liveplay.live.kugou.com',
      ]);
      final legacyHeaders = (_legacy('S04-room-live')['KugouLiveApi.mediaHeaders'] as Map).map(
        (key, value) => MapEntry('$key'.toLowerCase(), value),
      );
      for (final line in lines) {
        expect(line.headers, legacyHeaders);
        expect(line.format, StreamFormat.flv);
        expect(line.codec, 'avc');
        final expires = DateTime.fromMillisecondsSinceEpoch(0x6ABA00B5 * 1000, isUtc: true);
        expect(line.lease!.expiresAt, expires);
        expect(line.lease!.refreshAt, expires.subtract(const Duration(minutes: 5)));
        expect(line.lease!.cutsConnection, isFalse);
      }
      final fixture = _sample('S05-stream-live');
      expect(
        lines.first.lease!.expiresAt!.difference(fixture.capturedAt).inMinutes,
        inInclusiveRange(12 * 60 - 2, 12 * 60 + 2),
        reason: 'txTime is about 12 hours after issue',
      );
    });

    test('qualities and resolution match 3.x', () {
      final variants = live();
      final qualities = KugouLiveApi.qualities(variants);
      final legacy = _maps(_value('S04-room-live', 'getPlayQualites'));
      expect(
        [for (final quality in qualities) (quality.quality, quality.id, quality.sort, quality.data)],
        [for (final quality in legacy) (quality['quality'], quality['id'], quality['sort'], quality['data'])],
      );
      final resolved = (_legacy('S04-room-live')['resolvePlayUrlsRaw'] as Map)['flv:4:1:2'] as Map;
      final resolution = KugouLiveApi.resolution(variants.single);
      expect(resolution.urls, (resolved['value'] as Map)['urls']);
      expect(resolution.appliedQualityData, (resolved['value'] as Map)['appliedQualityData']);
      expect(
        resolution.lines.first.lease!.expiresAt!.toIso8601String(),
        ((resolved['value'] as Map)['invalidAt'] as List).first,
      );
    });

    test('an offline answer is StreamUnavailable; another room is ApiChanged (3.x: mediaUnavailable)', () {
      expect(_legacy('S05-stream-offline')['parseMediaJson(1014306)'], {
        'throws': 'KugouLiveException',
        'message': 'Kugou Live mediaUnavailable',
      });
      expect(
        () => KugouLiveApi.variants(_sample('S05-stream-offline').body, roomId: '1014306'),
        throwsA(isA<StreamUnavailable>()),
      );
      expect((_legacy('S05-stream-live')['parseMediaJson(3197157)'] as Map)['message'], 'Kugou Live mediaUnavailable');
      expect(
        () => KugouLiveApi.variants(_sample('S05-stream-live').body, roomId: '3197157'),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('3.x grouping: room-bound URLs, duplicates across lines once, tiers by rate, HLS apart', () {
      final variants = KugouLiveApi.variants(
        _streams([
          {
            'sid': 5,
            'streamProfiles': [
              {
                'layout': 1,
                'codec': 1,
                'rate': 4,
                'httpsFlv': [_signed('tx105.liveplay.live.kugou.com'), _signed('tx105.liveplay.live.kugou.com')],
                'httpsHls': [_signed('tx105.liveplay.live.kugou.com', path: 'x.m3u8')],
              },
              {
                'layout': 1,
                'codec': 2,
                'rate': 5,
                'httpsFlv': [_signed('tx105.liveplay.live.kugou.com', path: 'hevc.flv')],
              },
            ],
          },
          {
            'sid': 40,
            'streamProfiles': [
              {
                'layout': 1,
                'codec': 1,
                'rate': 4,
                'httpsFlv': [
                  _signed('tx106.liveplay.live.kugou.com', line: '106'),
                  _signed('tx105.liveplay.live.kugou.com'),
                  _signed('other.live.kugou.com'),
                  _signed('tx106.liveplay.live.kugou.com', room: '9999999'),
                ],
                'httpsHls': <String>[],
              },
            ],
          },
        ]),
        roomId: '5085706',
      );
      expect(variants.map((variant) => variant.id), ['flv:5:2:1', 'flv:4:1:1', 'hls:4:1:1']);
      expect(variants[0].lines.single.codec, isNull, reason: 'codec 2 is not verified');
      expect(variants[1].lines.map((line) => line.lineId), ['sid5', 'sid40']);
      expect(variants[1].lines, hasLength(2));
      expect(variants[2].lines.single.format, StreamFormat.hls);
      final qualities = KugouLiveApi.qualities(variants);
      expect(qualities.map((quality) => quality.quality), ['FLV 码率档 5', 'FLV 码率档 4', 'HLS 码率档 4']);
      expect(qualities.map((quality) => quality.sort), [52, 42, 41]);
      expect(
        () => KugouLiveApi.variants(
          _streams([
            {
              'sid': 5,
              'streamProfiles': [
                {
                  'rate': 4,
                  'httpsFlv': [_signed('tx105.liveplay.live.kugou.com', room: '1')],
                },
              ],
            },
          ]),
          roomId: '5085706',
        ),
        throwsA(isA<StreamUnavailable>()),
        reason: 'no accepted URL',
      );
      expect(
        () => KugouLiveApi.variants(_streams([], status: 0), roomId: '5085706'),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(() => KugouLiveApi.variants(_streams([]), roomId: '5085706'), throwsA(isA<StreamUnavailable>()));
    });

    test('media URLs as 3.x accepted them', () {
      final url = live().single.lines.first.url;
      final legacy = _legacy('S04-room-live')['KugouLiveApi.validateMediaUri'] as Map<String, dynamic>;
      for (final (name, candidate, protocol, room) in [
        ('recorded', url, 'flv', '3197156'),
        ('another room', url, 'flv', '3197157'),
        ('as hls', url, 'hls', '3197156'),
        ('http', url.replaceFirst('https://', 'http://'), 'flv', '3197156'),
        ('other host', url.replaceFirst('tx105.liveplay.live.kugou.com', 'tx105.live.kugou.com'), 'flv', '3197156'),
        ('port', url.replaceFirst('.com/', '.com:8443/'), 'flv', '3197156'),
        ('no txSecret', url.replaceFirst(RegExp('txSecret=[^&]+'), 'txSecret='), 'flv', '3197156'),
        ('short txTime', url.replaceFirst('txTime=6ABA00B5', 'txTime=6AB'), 'flv', '3197156'),
        ('fragment', '$url#x', 'flv', '3197156'),
      ]) {
        expect(
          KugouLiveApi.mediaUrl(candidate, roomId: room, protocol: protocol)?.toString(),
          legacy[name],
          reason: name,
        );
      }
      expect(
        KugouLiveApi.mediaUrl(url.replaceFirst('txTime=6ABA00B5', 'txTime=%FF'), roomId: '3197156', protocol: 'flv'),
        isNull,
      );
    });

    test('lease times match 3.x', () {
      final now = DateTime.utc(2026, 9, 27, 18);
      final legacy = _legacy('S04-room-live')['lease'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in legacy.entries) {
        final times = value as Map<String, dynamic>;
        expect(KugouLiveApi.invalidAt(key)?.toIso8601String(), times['invalidAt'], reason: key);
        expect(KugouLiveApi.refreshAt(key, now: now)?.toIso8601String(), times['refreshAt'], reason: key);
      }
      expect(KugouLiveApi.lease(Uri.parse('https://tx2.liveplay.live.kugou.com/live/x.flv')), isNull);
      expect(KugouLiveApi.invalidAt('https://x/?txTime=%FF'), isNull);
    });

    test('the stream URL is 3.x request with the clock value', () {
      final requests = (_legacy('S04-room-live')['getRoomDetail'] as Map)['requests'] as List;
      expect(
        '${KugouLiveApi.streamUrl('3197156', millis: 1790531600000)}'.replaceFirst('_=1790531600000', '_=<ms>'),
        (requests.last as Map)['url'],
      );
    });
  });

  group('S06 search', () {
    test('the streamers match 3.x, live or not, in order', () {
      final fixture = _sample('S06-search');
      final rooms = KugouLiveApi.searchRooms(fixture.body, callback: 'pureLive1', status: fixture.status);
      final legacy = _maps(_value('S06-search', 'searchRooms(1, 100)'));
      expect(rooms, hasLength(98));
      expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
      for (final (index, room) in rooms.indexed) {
        _expectParity(_projection(room), legacy[index], changed: _headersMoved, reason: 'S06[$index]');
      }
      expect(rooms.where((room) => room.liveStatus == LiveStatus.live), hasLength(6));
      expect(rooms.where((room) => room.liveStatus == LiveStatus.offline), hasLength(92));
      expect(rooms.every((room) => room.title == room.nick), isTrue, reason: 'no label in search rows');
      expect(rooms.first.avatar, endsWith('_45x45.jpg'), reason: '`logo`, as 3.x');
    });

    test('no result', () {
      final fixture = _sample('S06-search-empty');
      expect(KugouLiveApi.searchRooms(fixture.body, callback: 'pureLive1'), isEmpty);
      expect(_value('S06-search-empty', 'searchRooms(qzxqzxpurelivezz)'), isEmpty);
    });

    test('3.x JSONP rules', () {
      final body = _sample('S06-search').body;
      expect(_legacy('S06-search')['parseSearchJsonp(no callback check)'], 98);
      expect(KugouLiveApi.searchRooms(body), hasLength(98));
      expect((_legacy('S06-search')['parseSearchJsonp(other callback)'] as Map)['message'], 'Kugou Live schema');
      expect(() => KugouLiveApi.searchRooms(body, callback: 'other'), throwsA(isA<ApiChanged>()));
      final json = jsonEncode({
        'status': 1,
        'data': {
          'anchor': {
            'list': [
              {'roomId': 5085706, 'userId': 1, 'kugouId': 1, 'nickName': 'live anchor', 'liveStatus': 1},
              {'roomId': 5085707, 'userId': 2, 'kugouId': 2, 'nickName': 'offline anchor', 'liveStatus': 0},
              {'roomId': 5085707, 'nickName': 'again', 'liveStatus': 0},
            ],
          },
        },
      });
      final rooms = KugouLiveApi.searchRooms('fixtureCallback($json);', callback: 'fixtureCallback');
      expect(rooms.map((room) => (room.nick, room.liveStatus)), [
        ('live anchor', LiveStatus.live),
        ('offline anchor', LiveStatus.offline),
      ]);
      for (final text in [
        json,
        '($json)',
        'fixtureCallback($json) trailing',
        'bad-name($json)',
        'fixtureCallback(not json)',
        'fixtureCallback({"code":2,"data":{}})',
      ]) {
        expect(() => KugouLiveApi.searchRooms(text), throwsA(isA<ApiChanged>()), reason: text);
      }
      expect(KugouLiveApi.searchRooms('cb({"code":0,"data":{}})'), isEmpty);
      expect(() => KugouLiveApi.searchRooms('', status: 429), throwsA(isA<RateLimited>()));
    });

    test('the search URL is 3.x request', () {
      final requests = (_legacy('S06-search')['searchRooms(1, 30)'] as Map)['requests'] as List;
      expect(
        '${KugouLiveApi.searchUrl('唱歌', 'pureLive1')}'.replaceFirst('callback=pureLive1', 'callback=<callback>'),
        (requests.single as Map)['url'],
      );
    });
  });

  group('links', () {
    test('room numbers and links follow 3.x `KugouLiveLink.parseRoomId`', () {
      final legacy = _legacy('S04-room-live')['KugouLiveLink.parseRoomId'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in legacy.entries) {
        expect(KugouLiveApi.parseRoomId(key), value, reason: key);
        final isNumber = RegExp(r'^\s*\d+\s*$').hasMatch(key);
        expect(KugouLiveApi.roomIdFromUrl(key), isNumber ? isNull : value, reason: 'URL only: $key');
      }
      expect(KugouLiveApi.roomIdFromUrl('https://fanxing.kugou.com/%FF'), isNull);
      expect(KugouLiveApi.roomIdFromUrl('https://mfanxing.kugou.com/?roomId=%FF'), isNull);
    });

    test('room page and media headers match 3.x', () {
      final legacy = _legacy('S04-room-live')['KugouLiveLink.watchUrl'] as Map<String, dynamic>;
      expect(KugouLiveApi.roomUrl('3197156'), legacy['3197156']);
      final headers = _legacy('S04-room-live')['KugouLiveApi.mediaHeaders'] as Map<String, dynamic>;
      expect(KugouLiveApi.mediaHeaders('3197156'), {
        for (final MapEntry(:key, :value) in headers.entries) key.toLowerCase(): value,
      });
    });
  });

  test('status mapping', () {
    for (final (status, matcher) in [
      (200, isNull),
      (204, isNull),
      (302, isA<NetworkFailure>()),
      (400, isA<ApiChanged>()),
      (422, isA<ApiChanged>()),
      (401, isA<RiskControl>()),
      (403, isA<RiskControl>()),
      (451, isA<RegionBlocked>()),
      (404, isA<NotFound>()),
      (410, isA<NotFound>()),
      (429, isA<RateLimited>()),
      (500, isA<NetworkFailure>()),
      (503, isA<NetworkFailure>()),
    ]) {
      expect(KugouLiveApi.statusError(status, 'x'), matcher, reason: '$status');
    }
  });
}
