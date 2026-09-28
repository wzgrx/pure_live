// Baidu Live parsing against the recorded samples, compared field by field
// with 3.x's frozen output (expected.json, written by
// fixtures/baidulive/legacy_expected.dart from 3.x's BaiduLiveApi,
// BaiduLiveLink and BaiduLiveSite). Every intended difference is listed
// with its reason; everything else must match. The synthetic cases port
// 3.x's baidu_live_site_test.dart (the parsing parts) and cover the pitfalls
// of the archived spec (§10) and the shapes 3.x refused.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('baidulive', name);

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

/// The value of a counted legacy call (`{requests, value}`).
Object? _value(String name, String key) => (_legacy(name)[key] as Map<String, dynamic>)['value'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

/// 3.x put the media headers on every room (`httpHeaders`), where only
/// IPTV's are read (3.x's PlaybackHeaderResolver had no Baidu branch, so
/// playback sent none); they now travel on every line.
const _headersMoved = {'httpHeaders'};

const _liveRoom = '11560887291';
const _endedRoom = '11583715413';

BaiduLivePage _feed(String sample) {
  final fixture = _sample(sample);
  return BaiduLiveApi.page(fixture.body, status: fixture.status);
}

BaiduLiveRoom _room(String sample, String roomId) {
  final fixture = _sample(sample);
  return BaiduLiveApi.room(fixture.body, expectedRoomId: roomId, status: fixture.status);
}

/// The live sample's command with [changes] applied to it (and [video] to
/// its `video`).
String _liveAnswer({Map<String, Object?> changes = const {}, Map<String, Object?> video = const {}}) {
  final root = jsonDecode(_sample('S02-room-live').body) as Map<String, dynamic>;
  final command = (root['data'] as Map<String, dynamic>)['371'] as Map<String, dynamic>..addAll(changes);
  command['video'] = {...command['video'] as Map<String, dynamic>, ...video};
  return jsonEncode(root);
}

/// The fields 3.x's parser reported for a room.
Map<String, Object?> _parsed(BaiduLiveRoom room) => {
  'roomId': room.roomId,
  'userId': room.userId,
  'nick': room.nick,
  'title': room.title,
  'avatar': room.avatar,
  'cover': room.cover,
  'category': room.category,
  'currentViewers': room.currentViewers,
  'followers': room.followers,
  'state': room.state.name,
  'variants': [
    for (final variant in room.variants)
      {
        'id': variant.id,
        'protocol': variant.protocol,
        'resolution': variant.resolution,
        'codec': variant.codec,
        'urls': [for (final url in variant.urls) '$url'],
      },
  ],
};

/// 3.x's test directory: ten live cards and two channels.
final Map<String, Object?> _directoryJson = {
  'errno': 0,
  'data': {
    'feed': {
      'inner_errno': 0,
      'session_id': 'fixture-session',
      'refresh_index': 1,
      'items': List.generate(
        10,
        (index) => {
          'room_id': 11572411040 + index,
          'title': index == 0 ? '长江新闻号正在播出' : '直播 $index',
          'cover': 'https://pic.rmb.bdstatic.com/bjh/fixture-$index.jpeg',
          'live_status': 1,
          'audience_count': 43 + index,
          'live_tag': '新闻',
          'host': {
            'uk': 'fixture-$index',
            'name': index == 0 ? '长江新闻号' : '主播 $index',
            'avatar': 'https://avatar.bdstatic.com/it/u=$index&size=b200,200',
          },
        },
      ),
    },
    'tab': {
      'inner_errno': 0,
      'items': [
        {'name': '推荐', 'type': 'rec', 'channel_id': 570},
        {'name': '健康', 'type': 'health', 'channel_id': 612},
      ],
    },
  },
};

/// 3.x's test room: a clarity entry at 1080 and a `url_list` entry at 720.
final Map<String, Object?> _roomJson = {
  'errno': 0,
  'data': {
    '371': {
      'error_code': '0',
      'status': '0',
      'share_url': 'https://live.baidu.com/m/media/multipage/liveshow/index/news?room_id=11572411040',
      'online_users': '43',
      'real_fans_num': 91,
      'category': '新闻',
      'has_pay_service': 0,
      'is_forbidden_url': 0,
      'ban_status': 0,
      'host': {
        'uk': 'fixture-host',
        'nick_name': '长江新闻号',
        'fans': '90',
        'image': {'image_33': 'https://avatar.bdstatic.com/it/u=1&size=b200,200'},
      },
      'video': {
        'title': '长江新闻号正在播出',
        'cover': {'cover_100': 'https://pic.rmb.bdstatic.com/bjh/fixture.jpeg'},
        'live_hls_url': 'http://hls.liveshow.bdstatic.com/live/stream_bduid_836143438_11572411040-mid-LV720.m3u8',
        'live_flv_url': 'https://hls-live.bdstatic.com/live/stream_bduid_836143438_11572411040-L1.flv',
        'live_flv_url_origin': 'https://flv-live.bdstatic.com/live/stream_bduid_836143438_11572411040.flv',
        'url_clarity_list': [
          {
            'resolution': 1080,
            'urls': {
              'avc_flv': 'https://hls-live.bdstatic.com/live/stream_bduid_836143438_11572411040-LV1080.flv?logid=1',
            },
          },
        ],
        'url_list': [
          {
            'resolution': 720,
            'urls': [
              {
                'hls':
                    'http://hls.liveshow.lss-user.baidubce.com/live/stream_bduid_836143438_11572411040-mid-LV720.m3u8',
              },
            ],
          },
        ],
      },
    },
  },
};

/// A room command with [command] as its 371.
String _command(Map<String, Object?> command) => jsonEncode({
  'errno': '0',
  'data': {'371': command},
});

String _card(Map<String, Object?> changes) => jsonEncode({
  'errno': 0,
  'data': {
    'feed': {
      'inner_errno': 0,
      'session_id': '1',
      'refresh_index': 1,
      'items': [
        {
          'room_id': 11572411040,
          'title': 'Fixture',
          'cover': 'https://pic.rmb.bdstatic.com/bjh/fixture.jpeg',
          'live_status': 1,
          'audience_count': 43,
          'live_tag': '新闻',
          'host': {'uk': 'fixture', 'name': 'Anchor', 'avatar': 'https://avatar.bdstatic.com/it/u=1'},
          ...changes,
        },
      ],
    },
  },
});

void main() {
  group('catalog', () {
    test("3.x's fixed channels until a first feed page: one category, seven areas", () {
      final legacy = _maps(_value('S01-feed-rec-p1', 'getCategores(1) before the feed'));
      final categories = BaiduLiveApi.categories(BaiduLiveApi.fallbackCategories);
      expect(categories.map((category) => category.id), legacy.map((category) => category['id']));
      expect(categories.map((category) => category.name), legacy.map((category) => category['name']));
      final areas = _maps(legacy.single['children']);
      expect(categories.single.children, hasLength(7));
      for (final (index, area) in categories.single.children.indexed) {
        _expectParity(area.toJson(), areas[index], reason: 'area $index');
      }
      expect(_value('S01-feed-rec-p1', 'getCategores(2)'), 0);
      expect(_value('S01-feed-rec-p1', 'getCategores(1, pageSize 0)'), 0);
      expect(_legacy('S01-feed-rec-p1')['name'], BaiduLiveApi.siteName);
      expect(_legacy('S01-feed-rec-p1')['directoryNoticeKey'], BaiduLiveApi.directoryNoticeKey);
    });

    test("the first feed page's tab list is the catalog after it (S01-feed-rec-p1)", () {
      final legacy = _maps(_value('S01-feed-rec-p1', 'getCategores(1) after the feed'));
      final categories = BaiduLiveApi.categories(_feed('S01-feed-rec-p1').categories);
      final areas = _maps(legacy.single['children']);
      expect(categories.single.children.map((area) => area.areaId), areas.map((area) => area['areaId']));
      for (final (index, area) in categories.single.children.indexed) {
        _expectParity(area.toJson(), areas[index], reason: 'area $index');
      }
    });

    test('channels: a lower-case id, a name and a positive channel id, each once', () {
      final channels = BaiduLiveApi.channels({
        'inner_errno': 0,
        'items': [
          {'type': 'REC', 'name': '推荐', 'channel_id': '570'},
          {'type': 'rec', 'name': '推荐 2', 'channel_id': 571},
          {'type': '9bad', 'name': 'x', 'channel_id': 1},
          {'type': 'news', 'name': '', 'channel_id': 575},
          {'type': 'auto', 'name': '汽车', 'channel_id': 0},
          'not an item',
          {'type': 'leisure', 'name': '休闲', 'channel_id': 616},
        ],
      });
      expect(channels.map((channel) => (channel.id, channel.name, channel.channelId)), [
        ('rec', '推荐', 570),
        ('leisure', '休闲', 616),
      ]);
      expect(BaiduLiveApi.channels(null), isEmpty);
      expect(BaiduLiveApi.channels(<String, Object?>{}), isEmpty);
    });
  });

  group('S01 feed', () {
    test('the first page parses as in 3.x: session, index, "more", channels and cards', () {
      final legacy = _legacy('S01-feed-rec-p1')['parseDirectoryJson']! as Map<String, dynamic>;
      final page = _feed('S01-feed-rec-p1');
      expect(page.sessionId, legacy['sessionId']);
      expect(page.refreshIndex, legacy['refreshIndex']);
      expect(page.hasMore, legacy['hasMore']);
      expect([
        for (final channel in page.categories) {'id': channel.id, 'name': channel.name, 'channelId': channel.channelId},
      ], legacy['categories']);
      expect([for (final room in page.rooms) _parsed(room)], legacy['rooms']);
    });

    test('the second page (same session, index 2) parses as in 3.x, without channels', () {
      final legacy = _legacy('S01-feed-rec-p2')['parseDirectoryJson']! as Map<String, dynamic>;
      final page = _feed('S01-feed-rec-p2');
      expect(
        [page.sessionId, page.refreshIndex, page.hasMore],
        [legacy['sessionId'], legacy['refreshIndex'], legacy['hasMore']],
      );
      expect(page.categories, isEmpty);
      expect([for (final room in page.rooms) _parsed(room)], legacy['rooms']);
    });

    test("cards are 3.x's rooms field by field (recommendations and shopping)", () {
      for (final (sample, key) in [
        ('S01-feed-rec-p1', 'getDirectoryPage(1)'),
        ('S01-feed-shopping-p1', 'getDirectoryPage(1, shopping)'),
      ]) {
        final legacy = _maps((_value(sample, key)! as Map<String, dynamic>)['rooms']);
        final rooms = [for (final room in _feed(sample).rooms) BaiduLiveApi.liveRoom(room)];
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']), reason: sample);
        for (final (index, room) in rooms.indexed) {
          _expectParity(_projection(room), legacy[index], changed: _headersMoved, reason: '$sample[$index]');
          expect(room.httpHeaders, isEmpty);
          expect(room.data, isNull);
        }
      }
    });

    test("the feed form is 3.x's and signs as the recording (S01 p1, p2, shopping)", () {
      for (final sample in ['S01-feed-rec-p1', 'S01-feed-rec-p2', 'S01-feed-shopping-p1']) {
        final fixture = _sample(sample);
        final body = (fixture.meta['request'] as Map<String, dynamic>)['body'] as String;
        final recorded = Uri.splitQueryString(body);
        final signature = _legacy(sample)['signature'] as Map<String, dynamic>;
        expect(signature['signFeedParameters'], recorded['sign'], reason: '3.x signs the recording ($sample)');
        expect(BaiduLiveApi.signFeed(recorded), recorded['sign'], reason: sample);
        final channel = BaiduLiveApi.fallbackCategories.firstWhere((channel) => channel.id == recorded['tab']);
        final first = recorded['refresh_type'] == '0';
        final form = BaiduLiveApi.feedForm(
          channel: channel,
          first: first,
          deviceId: recorded['uid']!,
          now: DateTime.fromMillisecondsSinceEpoch(int.parse(recorded['timestamp']!) * 1000),
          sessionId: recorded['session_id']!,
          refreshIndex: int.parse(recorded['refresh_index']!),
        );
        expect(form, recorded, reason: sample);
        final order = body.split('&').map((field) => field.split('=').first);
        expect(form.keys, order, reason: 'field order ($sample)');
      }
      expect(BaiduLiveApi.signFeed({'b': '2', 'a': '1'}), _legacy('S01-feed-rec-p1')['signFeedParameters(b=2, a=1)']);
      expect(BaiduLiveApi.signFeed({'b': '2', 'a': '1'}), '6ccb27769bec11fe1c1db46f74b97f15');
    });

    test("3.x's directory case: ten live cards keep their viewers; two channels", () {
      final page = BaiduLiveApi.page(jsonEncode(_directoryJson));
      expect(page.rooms, hasLength(10));
      expect(page.rooms.first.roomId, '11572411040');
      expect(page.rooms.first.currentViewers, 43);
      expect(page.rooms.first.state, BaiduLiveState.live);
      expect(page.categories.map((item) => item.id), ['rec', 'health']);
      expect(page.sessionId, 'fixture-session');
      expect(page.refreshIndex, 1);
      expect(page.hasMore, isTrue);
      final room = BaiduLiveApi.liveRoom(page.rooms.first);
      expect(room.onlineViewers, '43');
      expect(room.audienceMetricType, AudienceMetricType.onlineViewers);
    });

    test('cards: states, fallbacks, image hosts; a room once; rows without a room id skipped', () {
      BaiduLiveRoom card(Map<String, Object?> changes) => BaiduLiveApi.page(_card(changes)).rooms.single;
      for (final (status, state) in [
        (1, BaiduLiveState.live),
        (0, BaiduLiveState.preview),
        (2, BaiduLiveState.offline),
        (3, BaiduLiveState.replay),
        (9, BaiduLiveState.unknown),
        (null, BaiduLiveState.unknown),
      ]) {
        final room = card({'live_status': status});
        expect(room.state, state, reason: '$status');
        expect(room.currentViewers, state == BaiduLiveState.live ? 43 : null, reason: 'viewers only while live');
        expect(BaiduLiveApi.liveRoom(room).liveStatus, switch (state) {
          BaiduLiveState.live => LiveStatus.live,
          BaiduLiveState.unknown => LiveStatus.unknown,
          _ => LiveStatus.offline,
        });
      }
      final bare = card({
        'title': ' ',
        'host': {'name': ''},
        'live_tag': '',
        'left_label': {'text': '家居日用'},
        'cover': 'http://pic.rmb.bdstatic.com/bjh/fixture.jpeg',
      });
      expect(bare.nick, BaiduLiveApi.anonymousName);
      expect(bare.title, BaiduLiveApi.anonymousName);
      expect(bare.category, '家居日用');
      expect(bare.cover, '', reason: 'https only');
      final room = BaiduLiveApi.liveRoom(bare);
      expect(room.userId, bare.roomId, reason: 'no anchor id: the room id');
      expect(room.avatar, '', reason: 'no avatar and no cover');
      expect(room.followers, '');
      expect(card({'cover': 'https://evil.example/c.jpg'}).cover, '');
      expect(
        card({'cover': 'https://huibo-data.cdn.bcebos.com/c.png'}).cover,
        'https://huibo-data.cdn.bcebos.com/c.png',
      );
      expect(card({'cover': 'https://user@pic.bdstatic.com/c.png'}).cover, '');
      expect(
        card({
          'host': {'avatar': 'https://img.bdimg.com/a.png', 'name': 'a'},
        }).avatar,
        'https://img.bdimg.com/a.png',
      );
      final base = jsonDecode(_card(const {})) as Map<String, dynamic>;
      final feed = (base['data'] as Map<String, dynamic>)['feed'] as Map<String, dynamic>;
      final item = (feed['items'] as List).single as Map<String, dynamic>;
      feed['items'] = [
        item,
        {...item, 'title': 'again'},
        {...item, 'room_id': '012345'},
        {...item, 'room_id': 'abc'},
        'not a card',
      ];
      final page = BaiduLiveApi.page(jsonEncode(base));
      expect(page.rooms.map((room) => room.title), ['Fixture']);
      expect(page.hasMore, isFalse, reason: 'five items: fewer than ten');
    });

    test('a feed 3.x refused is ApiChanged; a failed tab block no longer fails the page', () {
      Map<String, dynamic> base() => jsonDecode(jsonEncode(_directoryJson)) as Map<String, dynamic>;
      Map<String, dynamic> feedOf(Map<String, dynamic> root) =>
          (root['data'] as Map<String, dynamic>)['feed'] as Map<String, dynamic>;
      for (final (edit, reason) in [
        ((Map<String, dynamic> root) => root['errno'] = 1, 'errno'),
        ((Map<String, dynamic> root) => feedOf(root)['inner_errno'] = 2, 'inner_errno'),
        ((Map<String, dynamic> root) => feedOf(root)['session_id'] = '', 'session'),
        ((Map<String, dynamic> root) => feedOf(root)['refresh_index'] = -1, 'refresh index'),
        ((Map<String, dynamic> root) => root.remove('data'), 'no data'),
      ]) {
        final root = base();
        edit(root);
        expect(() => BaiduLiveApi.page(jsonEncode(root)), throwsA(isA<ApiChanged>()), reason: reason);
      }
      expect(() => BaiduLiveApi.page('<html>'), throwsA(isA<ApiChanged>()));
      expect(() => BaiduLiveApi.page('[]'), throwsA(isA<ApiChanged>()));
      expect(
        () => BaiduLiveApi.page(jsonEncode(_directoryJson) + ' ' * BaiduLiveApi.responseLimit),
        throwsA(isA<ApiChanged>()),
      );
      // 3.x failed the whole page (`service`); the channels are kept instead.
      final root = base();
      ((root['data'] as Map<String, dynamic>)['tab'] as Map<String, dynamic>)['inner_errno'] = 5;
      final page = BaiduLiveApi.page(jsonEncode(root));
      expect(page.rooms, hasLength(10));
      expect(page.categories, isEmpty);
    });
  });

  group('S02 rooms', () {
    test('live: parsed as in 3.x, variants and URLs included', () {
      expect(_parsed(_room('S02-room-live', _liveRoom)), _legacy('S02-room-live')['parseRoomJson']);
    });

    test("live: the room, the refresh and the recording detail are 3.x's", () {
      final room = _room('S02-room-live', _liveRoom);
      for (final (key, withData) in [
        ('getRoomDetail', true),
        ('getRoomDetailForRefresh', false),
        ('getRoomDetailForRecording', true),
      ]) {
        final detail = BaiduLiveApi.liveRoom(room, withData: withData);
        _expectParity(
          _projection(detail),
          _value('S02-room-live', key)! as Map<String, dynamic>,
          changed: _headersMoved,
          reason: key,
        );
        expect(detail.httpHeaders, isEmpty);
        expect(detail.data, withData ? same(room) : isNull, reason: key);
      }
      expect(BaiduLiveApi.liveRoom(room).link, 'https://live.baidu.com/m/room/$_liveRoom');
    });

    test("live: 3.x's qualities, URLs and applied quality; lines with the media headers", () {
      final room = _room('S02-room-live', _liveRoom);
      final qualities = BaiduLiveApi.qualities(room);
      expect([
        for (final quality in qualities) {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort},
      ], _value('S02-room-live', 'getPlayQualites'));
      expect(qualities.map((quality) => quality.quality), ['HLS 720P · AVC', 'FLV 原始线路 · AVC']);
      final raw = _legacy('S02-room-live')['resolvePlayUrlsRaw'] as Map<String, dynamic>;
      final urls = _legacy('S02-room-live')['getPlayUrls'] as Map<String, dynamic>;
      for (final quality in qualities) {
        final resolution = BaiduLiveApi.resolution(room, quality);
        final legacy = (raw['${quality.id}'] as Map<String, dynamic>)['value'] as Map<String, dynamic>;
        expect(resolution.urls, legacy['urls'], reason: '${quality.id}');
        expect(resolution.urls, (urls['${quality.id}'] as Map<String, dynamic>)['value'], reason: '${quality.id}');
        expect(resolution.appliedQualityData, legacy['appliedQualityData']);
        for (final line in resolution.lines) {
          expect(line.headers, {
            'user-agent': BaiduLiveApi.userAgent,
            'origin': 'https://live.baidu.com',
            'referer': 'https://live.baidu.com/m/room/$_liveRoom',
          });
          expect(line.format, quality.id.toString().startsWith('hls') ? StreamFormat.hls : StreamFormat.flv);
          expect(line.codec, 'avc');
          expect(line.lineId, Uri.parse(line.url).host);
          expect(line.lease, isNull, reason: 'no signature, no expiry');
        }
      }
      expect(BaiduLiveApi.resolution(room, qualities.last).lines.map((line) => line.lineId), [
        'hls-live.bdstatic.com',
        'flv-live.bdstatic.com',
      ]);
      expect(
        () => BaiduLiveApi.resolution(room, const LivePlayQuality(quality: 'x', id: 'flv:1080:avc')),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('the media headers are the ones 3.x wrote into rooms (names now lower case)', () {
      final legacy = (_legacy('S02-room-live')['BaiduLiveApi.mediaHeaders'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key.toLowerCase(), value),
      );
      expect(BaiduLiveApi.mediaHeaders(_liveRoom), legacy);
      final api = (_legacy('S02-room-live')['BaiduLiveApi.apiHeaders'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key.toLowerCase(), value),
      );
      expect(BaiduLiveApi.apiHeaders, api);
    });

    test('a share_url of another room is ApiChanged (3.x: identity)', () {
      expect(_legacy('S02-room-live')['parseRoomJson(another room)'], containsPair('message', 'Baidu Live identity'));
      expect(() => _room('S02-room-live', _endedRoom), throwsA(isA<ApiChanged>()));
    });

    test('ended (status 3): offline as in 3.x; its leftover url_list is not played', () {
      final room = _room('S02-room-ended', _endedRoom);
      expect(_parsed(room), _legacy('S02-room-ended')['parseRoomJson']);
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        _expectParity(
          _projection(BaiduLiveApi.liveRoom(room, withData: key != 'getRoomDetailForRefresh')),
          _value('S02-room-ended', key)! as Map<String, dynamic>,
          changed: _headersMoved,
          reason: key,
        );
      }
      expect(BaiduLiveApi.liveRoom(room).liveStatus, LiveStatus.offline);
      // 3.x answered an empty list; the player now learns why.
      expect(_value('S02-room-ended', 'getPlayQualites'), isEmpty);
      expect(() => BaiduLiveApi.qualities(room), throwsA(isA<StreamUnavailable>()));
      expect(room.variants, isEmpty, reason: 'url_list still lists the ended stream');
    });

    test('not found (data.371 null) is NotFound (3.x: missing)', () {
      expect(_legacy('S02-room-notfound')['parseRoomJson'], containsPair('message', 'Baidu Live missing'));
      expect(() => _room('S02-room-notfound', '99999999999'), throwsA(isA<NotFound>()));
    });

    test("3.x's room case: FLV and HLS variants bound to the room, all https", () {
      final room = BaiduLiveApi.room(jsonEncode(_roomJson), expectedRoomId: '11572411040');
      expect(room.state, BaiduLiveState.live);
      expect(room.currentViewers, 43);
      expect(room.followers, 91);
      expect(room.variants.map((item) => item.id), containsAll(['flv:1080:avc', 'hls:720:avc']));
      expect(room.variants.expand((item) => item.urls).every((uri) => uri.scheme == 'https'), isTrue);
      expect(room.variants.map((item) => item.id), ['flv:1080:avc', 'hls:720:avc'], reason: 'best first');
      expect(
        BaiduLiveApi.mediaUrl(
          'https://hls-live.bdstatic.com/live/stream_bduid_1_99999999999.flv',
          roomId: '11572411040',
          protocol: 'flv',
        ),
        isNull,
      );
      expect(
        BaiduLiveApi.mediaUrl(
          'https://hls.liveshow.lss-user.baidubce.com/live/stream_bduid_1_11572411040.m3u8',
          roomId: '11572411040',
          protocol: 'hls',
        ),
        isNull,
      );
    });

    test("3.x's media URL rule over the recorded hosts, schemes and paths", () {
      final legacy = _legacy('S02-room-live')['BaiduLiveApi.validateMediaUri'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in legacy.entries) {
        final space = key.indexOf(' ');
        final protocol = key.substring(0, space);
        final url = key.substring(space + 1);
        expect(
          BaiduLiveApi.mediaUrl(url, roomId: _liveRoom, protocol: protocol)?.toString(),
          value,
          reason: key,
        );
      }
    });

    test('states: status and restrictions as in 3.x; restricted rooms say so and stay unknown', () {
      BaiduLiveRoom room(Map<String, Object?> changes) =>
          BaiduLiveApi.room(_liveAnswer(changes: changes), expectedRoomId: _liveRoom);
      for (final (status, state) in [
        ('0', BaiduLiveState.live),
        ('-1', BaiduLiveState.preview),
        ('1', BaiduLiveState.preview),
        (2, BaiduLiveState.offline),
        ('20', BaiduLiveState.offline),
        ('3', BaiduLiveState.replay),
        ('7', BaiduLiveState.unknown),
      ]) {
        final parsed = room({'status': status});
        expect(parsed.state, state, reason: '$status');
        expect(parsed.variants, state == BaiduLiveState.live ? isNotEmpty : isEmpty, reason: '$status');
        expect(parsed.currentViewers, state == BaiduLiveState.live ? 25357 : null, reason: '$status');
        if (state != BaiduLiveState.live) {
          expect(() => BaiduLiveApi.qualities(parsed), throwsA(isA<StreamUnavailable>()), reason: '$status');
        }
      }
      for (final (changes, error) in [
        ({'has_pay_service': '1'}, isA<NeedsLogin>()),
        ({'is_forbidden_url': 1}, isA<StreamUnavailable>()),
        ({'ban_status': 1}, isA<StreamUnavailable>()),
        ({'has_pay_service': 1, 'ban_status': 1}, isA<StreamUnavailable>()),
        ({'has_pay_service': 1, 'status': '2'}, isA<StreamUnavailable>()),
      ]) {
        final parsed = room(changes);
        expect(parsed.state, BaiduLiveState.restricted, reason: '$changes');
        expect(parsed.variants, isEmpty, reason: '$changes');
        final detail = BaiduLiveApi.liveRoom(parsed);
        expect(detail.liveStatus, LiveStatus.unknown, reason: '3.x: never shown as offline');
        expect(detail.notice, '${BaiduLiveApi.restrictedNotice}\n${BaiduLiveApi.chatNotice}');
        expect(detail.onlineViewers, '');
        expect(() => BaiduLiveApi.qualities(parsed), throwsA(error), reason: '$changes');
      }
      expect(BaiduLiveApi.liveRoom(room(const {})).notice, BaiduLiveApi.chatNotice);
    });

    test('a command 3.x refused: missing rooms NotFound, other codes and shapes ApiChanged', () {
      final root = jsonDecode(_liveAnswer()) as Map<String, dynamic>;
      final command = (root['data'] as Map<String, dynamic>)['371'] as Map<String, dynamic>;
      BaiduLiveRoom parse(Map<String, Object?> changes) =>
          BaiduLiveApi.room(_command({...command, ...changes}), expectedRoomId: _liveRoom);
      expect(() => parse({'error_code': '1'}), throwsA(isA<NotFound>()));
      expect(() => parse({'error_code': 4}), throwsA(isA<NotFound>()));
      expect(() => parse({'error_code': '7'}), throwsA(isA<ApiChanged>()));
      expect(() => parse({'error_code': null}), throwsA(isA<ApiChanged>()));
      expect(() => parse({'host': null, 'video': <String, Object?>{}}), throwsA(isA<NotFound>()));
      expect(() => BaiduLiveApi.room(_command(const {}), expectedRoomId: _liveRoom), throwsA(isA<NotFound>()));
      expect(
        () => BaiduLiveApi.room(jsonEncode({'errno': 1, 'data': <String, Object?>{}}), expectedRoomId: _liveRoom),
        throwsA(isA<ApiChanged>()),
      );
      expect(() => BaiduLiveApi.room('not json', expectedRoomId: _liveRoom), throwsA(isA<ApiChanged>()));
      final nameless = parse({
        'host': {'uk': 'u'},
        'video': {'cover': <String, Object?>{}},
        'category': '',
        'real_fans_num': null,
      });
      expect(
        [nameless.nick, nameless.title, nameless.cover, nameless.category, nameless.followers],
        [BaiduLiveApi.anonymousName, BaiduLiveApi.anonymousName, '', '', null],
      );
      expect(BaiduLiveApi.liveRoom(nameless).area, BaiduLiveApi.siteName);
      expect(
        parse({
          'real_fans_num': null,
          'host': {'fans': '12'},
        }).followers,
        12,
        reason: 'host.fans',
      );
      expect(
        parse({
          'video': {
            'cover': {'vertical_cover': 'https://p2.bdstatic.com/v.jpg'},
          },
        }).cover,
        'https://p2.bdstatic.com/v.jpg',
      );
    });

    test("status codes: 3.x's mapping, typed", () {
      for (final (status, type) in [
        (400, isA<ApiChanged>()),
        (422, isA<ApiChanged>()),
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (451, isA<RegionBlocked>()),
        (404, isA<NotFound>()),
        (410, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (500, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
      ]) {
        expect(
          () => BaiduLiveApi.room('', expectedRoomId: _liveRoom, status: status),
          throwsA(type),
          reason: '$status',
        );
        expect(() => BaiduLiveApi.page('', status: status), throwsA(type), reason: '$status');
      }
      expect(BaiduLiveApi.statusError(204, 'x'), isNull);
    });

    test("fallback: when 3.x's hosts give nothing, the platform's current CDN is played (kept http)", () {
      final room = BaiduLiveApi.room(
        _liveAnswer(video: {'live_hls_url': '', 'live_flv_url': '', 'live_flv_url_origin': ''}),
        expectedRoomId: _liveRoom,
      );
      const stream = 'stream_bduid_6325759471_11560887291';
      expect(
        {for (final variant in room.variants) variant.id: variant.urls.map((url) => '$url').toList()},
        {
          'flv:720:avc': [
            'http://flv.liveshow.lss-user.baidubce.com/live/$stream-L3.flv',
            'http://flv2.liveshow.lss-user.baidubce.com/live/$stream-L3.flv',
          ],
          'hls:720:avc': [
            'http://hls.liveshow.lss-user.baidubce.com/live/$stream-L3.m3u8',
            'http://hls2.liveshow.lss-user.baidubce.com/live/$stream-L3/playlist.m3u8',
          ],
          'flv:480:avc': [
            'http://flv.liveshow.lss-user.baidubce.com/live/$stream-L4.flv',
            'http://flv2.liveshow.lss-user.baidubce.com/live/$stream-L4.flv',
          ],
          'hls:480:avc': [
            'http://hls.liveshow.lss-user.baidubce.com/live/$stream-L4.m3u8',
            'http://hls2.liveshow.lss-user.baidubce.com/live/$stream-L4/playlist.m3u8',
          ],
          'flv:0:avc': [
            'http://flv.liveshow.lss-user.baidubce.com/live/$stream.flv?kabr_spts=-3000&logid=722978952&ls_from=searchbox_371&ls_scene=baidu_liveshow',
          ],
          'hls:0:avc': ['http://hls.liveshow.lss-user.baidubce.com/live/$stream.m3u8'],
        },
      );
      final line = BaiduLiveApi.resolution(room, BaiduLiveApi.qualities(room).first).lines.first;
      expect(line.headers['referer'], 'https://live.baidu.com/m/room/$_liveRoom');
      expect(line.lineId, 'flv.liveshow.lss-user.baidubce.com');
      // 3.x's own hosts win whenever they give anything.
      expect(_room('S02-room-live', _liveRoom).variants.map((variant) => variant.id), ['hls:720:avc', 'flv:0:avc']);
      final nothing = BaiduLiveApi.room(
        _liveAnswer(
          video: {
            'live_hls_url': '',
            'live_flv_url': '',
            'live_flv_url_origin': '',
            'live_hls_url_origin': '',
            'url_list': <Object?>[],
            'avc_url': 'https://evil.example/live/$stream.flv',
            'play_url': '',
          },
        ),
        expectedRoomId: _liveRoom,
      );
      expect(nothing.state, BaiduLiveState.live, reason: 'still entered (3.x failed the entry)');
      expect(() => BaiduLiveApi.qualities(nothing), throwsA(isA<StreamUnavailable>()));
    });

    test('media URLs: the room must be named, the path and extension right; fallback hosts only as fallback', () {
      String? url(String raw, {String protocol = 'flv', bool fallback = false}) =>
          BaiduLiveApi.mediaUrl(raw, roomId: _liveRoom, protocol: protocol, fallback: fallback)?.toString();
      expect(
        url('http://hls-live.bdstatic.com/live/a_$_liveRoom.flv'),
        'https://hls-live.bdstatic.com/live/a_$_liveRoom.flv',
      );
      expect(url('https://hls-live.bdstatic.com/live/a_${_liveRoom}0.flv'), isNull);
      expect(
        url('https://hls-live.bdstatic.com/live/a_$_liveRoom.FLV'),
        'https://hls-live.bdstatic.com/live/a_$_liveRoom.FLV',
      );
      expect(url('https://hls-live.bdstatic.com/live/a_$_liveRoom.flv#x'), isNull);
      expect(url('http://flv.liveshow.lss-user.baidubce.com/live/a_$_liveRoom.flv'), isNull);
      expect(
        url('http://flv.liveshow.lss-user.baidubce.com/live/a_$_liveRoom.flv', fallback: true),
        'http://flv.liveshow.lss-user.baidubce.com/live/a_$_liveRoom.flv',
      );
      expect(url('http://flv.liveshow.lss-user.baidubce.com:8080/live/a_$_liveRoom.flv', fallback: true), isNull);
      expect(url('http://lss-user.baidubce.com.evil.test/live/a_$_liveRoom.flv', fallback: true), isNull);
      expect(url('rtmp://rtmp.liveshow.lss-user.baidubce.com/live/a_$_liveRoom', fallback: true), isNull);
    });

    test('enrich: what an earlier card had fills what the command left out; viewers only while live', () {
      final card = BaiduLiveApi.page(_card({'room_id': 11560887291})).rooms.single;
      final sparse = BaiduLiveApi.room(
        _liveAnswer(
          changes: {
            'host': {'uk': ''},
            'video': {'cover': <String, Object?>{}, 'title': ''},
            'category': '',
            'online_users': null,
            'real_fans_num': null,
          },
        ),
        expectedRoomId: _liveRoom,
      ).enrich(card);
      expect(
        [sparse.userId, sparse.nick, sparse.title, sparse.avatar, sparse.cover, sparse.category],
        [
          'fixture',
          'Anchor',
          'Fixture',
          'https://avatar.bdstatic.com/it/u=1',
          'https://pic.rmb.bdstatic.com/bjh/fixture.jpeg',
          '新闻',
        ],
      );
      expect(sparse.currentViewers, 43, reason: 'live: the card viewers (3.x)');
      final ended = _room(
        'S02-room-ended',
        _endedRoom,
      ).enrich(BaiduLiveApi.page(_card({'room_id': 11583715413})).rooms.single);
      // 3.x kept the card's viewers on an ended room (and labelled them as
      // current viewers).
      expect(ended.currentViewers, isNull);
      expect(BaiduLiveApi.liveRoom(ended).audienceMetricType, AudienceMetricType.unknown);
      expect(ended.nick, '霞浦贵人笑', reason: 'a given field wins');
    });
  });

  group('links', () {
    test("3.x's rule over room ids and links (BaiduLiveLink.parseRoomId)", () {
      final legacy = _legacy('S02-room-live')['BaiduLiveLink.parseRoomId'] as Map<String, dynamic>;
      expect(legacy, hasLength(26));
      for (final MapEntry(:key, :value) in legacy.entries) {
        expect(BaiduLiveApi.parseRoomId(key), value, reason: key);
        final isUrl = key.contains('://');
        expect(BaiduLiveApi.roomIdFromUrl(key), isUrl ? value : null, reason: 'links only: $key');
      }
      expect(BaiduLiveApi.roomUrl(_liveRoom), _legacy('S02-room-live')['BaiduLiveLink.watchUrl']);
    });

    test("3.x's link cases; a link that does not decode is no link (3.x threw)", () {
      expect(BaiduLiveApi.parseRoomId('11572411040'), '11572411040');
      expect(BaiduLiveApi.roomIdFromUrl('https://live.baidu.com/m/room/11572411040?source=anchorrooms'), '11572411040');
      expect(
        BaiduLiveApi.roomIdFromUrl(
          'https://live.baidu.com/m/media/pclive/pchome/live.html?room_id=11572411040&source=h5pre',
        ),
        '11572411040',
      );
      expect(
        BaiduLiveApi.roomIdFromUrl('https://live.baidu.com/m/media/multipage/liveshow/index/cadm?room_id=11572411040'),
        '11572411040',
      );
      for (final value in [
        'https://live.baidu.com/search?room_id=11572411040',
        'https://live.baidu.com.evil.test/m/room/11572411040',
        'https://user@live.baidu.com/m/room/11572411040',
        'http://live.baidu.com/m/room/11572411040',
        '12',
        'https://live.baidu.com/m/media/pclive/pchome/live.html?room_id=%FF',
        'https://live.baidu.com/%FF/m/room/11572411040',
      ]) {
        expect(BaiduLiveApi.parseRoomId(value), isNull, reason: value);
      }
    });
  });
}
