// Baidu Live parsing against the recorded samples, compared field by field
// with 3.x's frozen output (expected.json, written by
// fixtures/baidulive/legacy_expected.dart from 3.x's BaiduLiveApi,
// BaiduLiveLink and BaiduLiveSite). Every intended difference is listed
// with its reason (M4.30's differences and the M4.U items 30-1…30-10);
// everything else must match. The synthetic cases port 3.x's
// baidu_live_site_test.dart (the parsing parts) and cover the pitfalls of
// the archived spec (§10) and the shapes 3.x refused. The samples recorded
// for M4.U (S01-feed-news-p1, S02-room-clarity, -clarity-hevc, -hevc,
// -preview) have no 3.x output.
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

/// Keys of every room that differ from 3.x on purpose:
/// - `httpHeaders` (M4.30 difference 1): 3.x put the media headers on every
///   room, where only IPTV's are read (3.x's PlaybackHeaderResolver had no
///   Baidu branch, so playback sent none); they travel on every line;
/// - `notice` (30-10): the notices are written for users; M5.26 shows the
///   chat, so the notice no longer says it cannot be seen (3.x's text is
///   [BaiduLiveApi.legacyChatNotice]).
const _changed = {'httpHeaders', 'notice'};

/// A live room's keys that differ besides [_changed]: `introduction`
/// (30-7), 3.x showed none.
const Set<String> _changedLive = {..._changed, 'introduction'};

/// An ended room's keys that differ besides [_changed]: `liveStatus` and
/// `isRecord` (30-4), the ended broadcast is a replay (3.x: offline).
const Set<String> _changedEnded = {..._changed, 'liveStatus', 'isRecord'};

const _liveRoom = '11560887291';
const _endedRoom = '11583715413';
const _clarityRoom = '11586212983';
const _clarityHevcRoom = '11585517323';
const _hevcRoom = '11586291324';
const _previewRoom = '11586142356';

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

/// The fields 3.x's parser reported for a room, without its variants
/// (compared on their own: 30-1 regrouped them).
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
};

/// [legacy] (3.x's parsed room) without `variants`.
Map<String, dynamic> _withoutVariants(Object? legacy) => {...legacy! as Map<String, dynamic>}..remove('variants');

/// A variant as `{id, name, codec, sort, lines: [url…]}`.
Map<String, Object?> _variant(BaiduLiveVariant variant) => {
  'id': variant.id,
  'name': variant.name,
  'codec': variant.codec,
  'sort': variant.sort,
  'lines': [for (final source in variant.sources) '${source.format.name} ${source.url}'],
};

/// 3.x's URL as the tier now carries it: `flv-live.bdstatic.com` is played
/// over http (30-9).
String _now(String legacyUrl) =>
    legacyUrl.replaceFirst('https://flv-live.bdstatic.com/', 'http://flv-live.bdstatic.com/');

/// Asserts that every variant 3.x offered for a room ([legacy], 3.x's
/// `{id, protocol, urls}`) is now part of one tier (30-1): 3.x's id maps to
/// the tier's id, and the tier's first lines are 3.x's URLs of all the
/// variants it absorbed, FLV before HLS, in 3.x's order.
void _expectLegacyVariants(List<BaiduLiveVariant> variants, List<Map<String, dynamic>> legacy) {
  final absorbed = <String, List<String>>{};
  for (final protocol in ['flv', 'hls']) {
    for (final old in legacy.where((old) => old['protocol'] == protocol)) {
      final id = BaiduLiveApi.qualityIdFromLegacy(old['id'] as String);
      absorbed.putIfAbsent(id, () => []).addAll([for (final url in (old['urls'] as List).cast<String>()) _now(url)]);
    }
  }
  expect(absorbed, isNotEmpty);
  for (final MapEntry(key: id, value: urls) in absorbed.entries) {
    final variant = variants.singleWhere((variant) => variant.id == id, orElse: () => fail('no tier $id'));
    expect(variant.sources.take(urls.length).map((source) => '${source.url}'), urls, reason: id);
  }
}

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

/// The command 371 of a room answer.
Map<String, dynamic> _command371(String body) =>
    ((jsonDecode(body) as Map<String, dynamic>)['data'] as Map<String, dynamic>)['371'] as Map<String, dynamic>;

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
          'has_pay_service': 0,
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
      expect(
        [for (final room in page.rooms) _parsed(room)],
        [for (final room in _maps(legacy['rooms'])) _withoutVariants(room)],
      );
      expect(page.rooms.every((room) => room.variants.isEmpty), isTrue);
    });

    test('the second page (same session, index 2) parses as in 3.x, without channels', () {
      final legacy = _legacy('S01-feed-rec-p2')['parseDirectoryJson']! as Map<String, dynamic>;
      final page = _feed('S01-feed-rec-p2');
      expect(
        [page.sessionId, page.refreshIndex, page.hasMore],
        [legacy['sessionId'], legacy['refreshIndex'], legacy['hasMore']],
      );
      expect(page.categories, isEmpty);
      expect(
        [for (final room in page.rooms) _parsed(room)],
        [for (final room in _maps(legacy['rooms'])) _withoutVariants(room)],
      );
    });

    test("cards are 3.x's rooms field by field (recommendations and shopping); not paid", () {
      for (final (sample, key) in [
        ('S01-feed-rec-p1', 'getDirectoryPage(1)'),
        ('S01-feed-shopping-p1', 'getDirectoryPage(1, shopping)'),
      ]) {
        final legacy = _maps((_value(sample, key)! as Map<String, dynamic>)['rooms']);
        final rooms = [for (final room in _feed(sample).rooms) BaiduLiveApi.liveRoom(room)];
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']), reason: sample);
        for (final (index, room) in rooms.indexed) {
          _expectParity(_projection(room), legacy[index], changed: _changed, reason: '$sample[$index]');
          expect(room.httpHeaders, isEmpty);
          expect(room.data, isNull);
          expect(room.notice, BaiduLiveApi.chatNotice, reason: '30-10');
          // Every recorded card says `has_pay_service: 0`.
          expect(room.restriction, LiveRestriction.none, reason: '$sample[$index]');
          expect(room.startedAt, isNull, reason: 'cards have no start');
          expect(room.introduction, isNull);
        }
      }
    });

    test("the feed form is 3.x's and signs as the recording (S01 p1, p2, shopping, news)", () {
      for (final sample in ['S01-feed-rec-p1', 'S01-feed-rec-p2', 'S01-feed-shopping-p1', 'S01-feed-news-p1']) {
        final fixture = _sample(sample);
        final body = (fixture.meta['request'] as Map<String, dynamic>)['body'] as String;
        final recorded = Uri.splitQueryString(body);
        if (sample != 'S01-feed-news-p1') {
          final signature = _legacy(sample)['signature'] as Map<String, dynamic>;
          expect(signature['signFeedParameters'], recorded['sign'], reason: '3.x signs the recording ($sample)');
        }
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
      expect(room.restriction, isNull, reason: 'no has_pay_service: the card does not tell');
    });

    test('cards: states (ended is a replay, 30-4), no stand-in names (30-10), image hosts; bad rows skipped', () {
      BaiduLiveRoom card(Map<String, Object?> changes) => BaiduLiveApi.page(_card(changes)).rooms.single;
      for (final (status, state, liveStatus) in [
        (1, BaiduLiveState.live, LiveStatus.live),
        (0, BaiduLiveState.preview, LiveStatus.offline),
        (2, BaiduLiveState.offline, LiveStatus.offline),
        (3, BaiduLiveState.replay, LiveStatus.replay),
        (9, BaiduLiveState.unknown, LiveStatus.unknown),
        (null, BaiduLiveState.unknown, LiveStatus.unknown),
      ]) {
        final room = card({'live_status': status});
        expect(room.state, state, reason: '$status');
        expect(room.currentViewers, state == BaiduLiveState.live ? 43 : null, reason: 'viewers only while live');
        expect(BaiduLiveApi.liveRoom(room).liveStatus, liveStatus, reason: '$status');
      }
      final bare = card({
        'title': ' ',
        'host': {'name': ''},
        'live_tag': '',
        'left_label': {'text': '家居日用'},
        'cover': 'http://pic.rmb.bdstatic.com/bjh/fixture.jpeg',
      });
      // 3.x wrote "Baidu Live" as both; the UI shows the platform's name for
      // an empty nick (M2.1 displayNick), and a stored follow keeps its own.
      expect(bare.nick, '');
      expect(bare.title, '');
      expect(bare.category, '家居日用');
      expect(bare.cover, '', reason: 'https only');
      final room = BaiduLiveApi.liveRoom(bare);
      expect(room.userId, bare.roomId, reason: 'no anchor id: the room id');
      expect(room.avatar, '', reason: 'no avatar and no cover');
      expect(room.followers, '');
      expect(room.hasNick, isFalse);
      expect(room.displayNick(BaiduLiveApi.siteName), BaiduLiveApi.siteName);
      expect(
        card({
          'title': '',
          'host': {'name': 'Anchor'},
        }).title,
        'Anchor',
        reason: "3.x: the nick when there's no title",
      );
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

    test('card restrictions (30-4, 30-5): paid by has_pay_service; an ended card without a recording is unplayable', () {
      BaiduLiveRoom card(Map<String, Object?> changes) => BaiduLiveApi.page(_card(changes)).rooms.single;
      const recording =
          'https://p2.bdstatic.com/rtmp.liveshow.lss-user.baidubce.com/live/stream_bduid_1_11572411040/recording_1-L_24_3760.m3u8';
      for (final (changes, restriction) in [
        (<String, Object?>{}, LiveRestriction.none),
        ({'has_pay_service': 1}, LiveRestriction.paid),
        ({'has_pay_service': null}, null),
        ({'live_status': 3, 'play_url': recording}, LiveRestriction.none),
        ({'live_status': 3, 'play_url': recording.replaceFirst('https', 'http')}, LiveRestriction.none),
        ({'live_status': 3, 'play_url': ''}, LiveRestriction.unplayable),
        (
          {'live_status': 3, 'play_url': 'http://flv.liveshow.lss-user.baidubce.com/live/a_11572411040.flv'},
          LiveRestriction.unplayable,
        ),
        ({'live_status': 3, 'play_url': recording, 'has_pay_service': 1}, LiveRestriction.paid),
        ({'live_status': 0, 'has_pay_service': 1}, null),
        ({'live_status': 2}, null),
      ]) {
        final room = card(changes);
        expect(room.restriction, restriction, reason: '$changes');
        expect(BaiduLiveApi.liveRoom(room).restriction, restriction, reason: '$changes');
      }
      final paid = BaiduLiveApi.liveRoom(card({'has_pay_service': '1'}));
      expect(paid.liveStatus, LiveStatus.live, reason: '30-5: still live');
      expect(paid.isRestricted, isTrue);
      expect(paid.notice, '${BaiduLiveApi.restrictedNotice}\n${BaiduLiveApi.chatNotice}');
      final ended = BaiduLiveApi.liveRoom(card({'live_status': 3, 'play_url': ''}));
      expect(ended.followGroup, FollowGroup.offline, reason: 'a replay without a recording is grouped as offline');
      expect(BaiduLiveApi.liveRoom(card({'live_status': 3, 'play_url': recording})).followGroup, FollowGroup.replay);
    });

    test('the news channel (S01-feed-news-p1): live, an ended card with its recording, announced cards', () {
      final page = _feed('S01-feed-news-p1');
      expect(page.rooms, hasLength(10));
      expect(page.hasMore, isTrue);
      final rooms = {for (final room in page.rooms) room.roomId: BaiduLiveApi.liveRoom(room)};
      final ended = rooms['11562145409']!;
      expect(
        [ended.liveStatus, ended.restriction, ended.followGroup],
        [LiveStatus.replay, LiveRestriction.none, FollowGroup.replay],
      );
      expect(ended.onlineViewers, '', reason: 'viewers only while live');
      for (final id in ['11586142356', '11586239156', '11585790893']) {
        expect(rooms[id]!.liveStatus, LiveStatus.offline, reason: 'announced ($id)');
        expect(rooms[id]!.restriction, isNull, reason: id);
      }
      final live = [
        for (final room in rooms.values)
          if (room.isLiveNow) room,
      ];
      expect(live, hasLength(6));
      expect(live.every((room) => room.restriction == LiveRestriction.none), isTrue);
      expect(rooms[_clarityRoom]!.nick, '长江新闻号');
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
    test("live: parsed as in 3.x; 3.x's variants are the first lines of the new tiers (30-1)", () {
      final room = _room('S02-room-live', _liveRoom);
      final legacy = _legacy('S02-room-live')['parseRoomJson'] as Map<String, dynamic>;
      expect(_parsed(room), _withoutVariants(legacy));
      _expectLegacyVariants(room.variants, _maps(legacy['variants']));
    });

    test("live: the room, the refresh and the recording detail are 3.x's, with the start, introduction, none", () {
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
          changed: _changedLive,
          reason: key,
        );
        expect(detail.httpHeaders, isEmpty);
        expect(detail.data, withData ? same(room) : isNull, reason: key);
        expect(detail.notice, BaiduLiveApi.chatNotice, reason: '30-10');
        expect(detail.introduction, '传承易经智慧的奥秘，师傅一笔一划传授，大白话上课，轻松易懂，零基础也能学得会', reason: '30-7');
        // create_time 1789574398.
        expect(detail.startedAt, DateTime.utc(2026, 9, 16, 15, 59, 58));
        expect(detail.restriction, LiveRestriction.none);
        expect(detail.toJson()['restriction'], 'none');
      }
      expect(BaiduLiveApi.liveRoom(room).link, 'https://live.baidu.com/m/room/$_liveRoom');
    });

    test('live: 原画, 720p, 480p (30-1); every 3.x quality plays through its id; lines with the media headers', () {
      final room = _room('S02-room-live', _liveRoom);
      final qualities = BaiduLiveApi.qualities(room);
      expect(
        [for (final quality in qualities) (quality.quality, quality.id, quality.sort)],
        [('原画', 'source', 1000002), ('720p', '720p', 7202), ('480p', '480p', 4802)],
      );
      expect(
        BaiduLiveApi.qualities(room, preferH264: false).map((quality) => quality.id),
        qualities.map((quality) => quality.id),
        reason: 'all H.264: the setting changes nothing',
      );
      const stream = 'stream_bduid_6325759471_11560887291';
      expect(
        {for (final variant in room.variants) variant.id: _variant(variant)['lines']},
        {
          'source': [
            'flv https://hls-live.bdstatic.com/live/$stream.flv?kabr_spts=-3000&logid=722978952&ls_from=searchbox_371&ls_scene=baidu_liveshow',
            'flv http://flv-live.bdstatic.com/live/$stream.flv',
            'flv http://flv.liveshow.lss-user.baidubce.com/live/$stream.flv?kabr_spts=-3000&logid=722978952&ls_from=searchbox_371&ls_scene=baidu_liveshow',
            'hls http://hls.liveshow.lss-user.baidubce.com/live/$stream.m3u8',
          ],
          '720p': [
            'hls https://hls.liveshow.bdstatic.com/live/$stream-L3.m3u8',
            'flv http://flv.liveshow.lss-user.baidubce.com/live/$stream-L3.flv',
            'flv http://flv2.liveshow.lss-user.baidubce.com/live/$stream-L3.flv',
            'hls http://hls.liveshow.lss-user.baidubce.com/live/$stream-L3.m3u8',
            'hls http://hls2.liveshow.lss-user.baidubce.com/live/$stream-L3/playlist.m3u8',
          ],
          '480p': [
            'flv http://flv.liveshow.lss-user.baidubce.com/live/$stream-L4.flv',
            'flv http://flv2.liveshow.lss-user.baidubce.com/live/$stream-L4.flv',
            'hls http://hls.liveshow.lss-user.baidubce.com/live/$stream-L4.m3u8',
            'hls http://hls2.liveshow.lss-user.baidubce.com/live/$stream-L4/playlist.m3u8',
          ],
        },
      );
      // 3.x's two qualities, by 3.x's ids: the same URLs first (30-9: the
      // second FLV line is http), the new id applied.
      final legacy = _value('S02-room-live', 'getPlayQualites')! as List;
      expect(legacy.map((quality) => (quality as Map)['id']), ['hls:720:avc', 'flv:0:avc']);
      final raw = _legacy('S02-room-live')['resolvePlayUrlsRaw'] as Map<String, dynamic>;
      for (final old in _maps(legacy)) {
        final resolution = BaiduLiveApi.resolution(
          room,
          LivePlayQuality(quality: old['quality'] as String, id: old['id']),
        );
        final urls = (((raw['${old['id']}'] as Map)['value'] as Map)['urls'] as List).cast<String>();
        expect(resolution.urls.take(urls.length), urls.map(_now), reason: '${old['id']}');
        expect(resolution.appliedQualityData, BaiduLiveApi.qualityIdFromLegacy(old['id'] as String));
      }
      for (final quality in qualities) {
        final resolution = BaiduLiveApi.resolution(room, quality);
        expect(resolution.appliedQualityData, quality.id);
        for (final line in resolution.lines) {
          expect(line.headers, {
            'user-agent': BaiduLiveApi.userAgent,
            'origin': 'https://live.baidu.com',
            'referer': 'https://live.baidu.com/m/room/$_liveRoom',
          });
          expect(line.format, line.url.contains('.m3u8') ? StreamFormat.hls : StreamFormat.flv);
          expect(line.codec, 'avc');
          expect(line.lease, isNull, reason: 'no signature, no expiry');
        }
      }
      expect(BaiduLiveApi.resolution(room, qualities.first).lines.map((line) => line.lineId), [
        'hls-live.bdstatic.com',
        'flv-live.bdstatic.com',
        'flv.liveshow.lss-user.baidubce.com',
        'hls.liveshow.lss-user.baidubce.com',
      ]);
      expect(
        () => BaiduLiveApi.resolution(room, const LivePlayQuality(quality: 'x', id: '1080p')),
        throwsA(isA<StreamUnavailable>()),
      );
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

    test('ended (status 3): a replay playing its recording (30-4); its leftover url_list is not played', () {
      final room = _room('S02-room-ended', _endedRoom);
      expect(_parsed(room), _withoutVariants(_legacy('S02-room-ended')['parseRoomJson']));
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        _expectParity(
          _projection(BaiduLiveApi.liveRoom(room, withData: key != 'getRoomDetailForRefresh')),
          _value('S02-room-ended', key)! as Map<String, dynamic>,
          changed: _changedEnded,
          reason: key,
        );
      }
      final detail = BaiduLiveApi.liveRoom(room);
      // 3.x: offline (liveStatus 1, isRecord false).
      expect([detail.liveStatus, detail.isRecord, detail.isLiveNow], [LiveStatus.replay, true, false]);
      expect(
        [detail.restriction, detail.followGroup, detail.startedAt],
        [LiveRestriction.none, FollowGroup.replay, null],
      );
      expect(detail.introduction, isNull, reason: 'an empty description');
      // 3.x answered an empty list; the recording is played now, H.264 first.
      expect(_value('S02-room-ended', 'getPlayQualites'), isEmpty);
      expect(
        [for (final quality in BaiduLiveApi.qualities(room)) (quality.quality, quality.id)],
        [('标清', 'replay:sd'), ('720p · H.265', 'replay:720p:hevc')],
      );
      expect(BaiduLiveApi.qualities(room, preferH264: false).map((quality) => quality.id), [
        'replay:sd',
        'replay:720p:hevc',
      ]);
      const base =
          'https://p2.bdstatic.com/rtmp.liveshow.lss-user.baidubce.com/live/stream_bduid_7108620967_11583715413';
      final sd = BaiduLiveApi.resolution(room, BaiduLiveApi.qualities(room).first);
      expect(sd.urls, ['$base/merged_1790528530185_939700_24_36096.m3u8']);
      expect(sd.appliedQualityData, 'replay:sd');
      final line = sd.lines.single;
      expect([line.format, line.codec, line.lineId, line.lease], [StreamFormat.hls, 'avc', 'p2.bdstatic.com', null]);
      final hevc = BaiduLiveApi.resolution(room, BaiduLiveApi.qualities(room).last).lines.single;
      expect([hevc.url, hevc.codec], ['$base/merged_1790528529280_847531_21_36090.m3u8', 'hevc']);
      expect(
        room.variants.expand((variant) => variant.sources).any((source) => source.url.path.contains('-L3')),
        isFalse,
        reason: 'url_list still lists the ended stream',
      );
    });

    test('not found (data.371 null) is NotFound (3.x: missing)', () {
      expect(_legacy('S02-room-notfound')['parseRoomJson'], containsPair('message', 'Baidu Live missing'));
      expect(() => _room('S02-room-notfound', '99999999999'), throwsA(isA<NotFound>()));
    });

    test("3.x's room case: the clarity tier, the url_list tier and the source", () {
      final room = BaiduLiveApi.room(jsonEncode(_roomJson), expectedRoomId: '11572411040');
      expect(room.state, BaiduLiveState.live);
      expect(room.currentViewers, 43);
      expect(room.followers, 91);
      expect(
        [for (final variant in room.variants) (variant.id, variant.codec)],
        [('source', null), ('1080p', 'avc'), ('720p', 'avc')],
      );
      // A clarity list: whether the source is H.264 is not told; with
      // "优先 H.264" it comes after the H.264 tiers.
      expect(BaiduLiveApi.qualities(room).map((quality) => quality.id), ['1080p', '720p', 'source']);
      expect(room.variants[2].sources.map((source) => '${source.url}'), [
        'https://hls.liveshow.bdstatic.com/live/stream_bduid_836143438_11572411040-mid-LV720.m3u8',
        'http://hls.liveshow.lss-user.baidubce.com/live/stream_bduid_836143438_11572411040-mid-LV720.m3u8',
      ]);
      expect(
        room.variants.expand((variant) => variant.sources).any((source) => source.url.path.endsWith('-L1.flv')),
        isFalse,
        reason: 'live_flv_url names a stream no list places',
      );
      expect(
        BaiduLiveApi.mediaUrl(
          'https://hls-live.bdstatic.com/live/stream_bduid_1_99999999999.flv',
          roomId: '11572411040',
          protocol: 'flv',
        ),
        isNull,
      );
    });

    test("3.x's media URL rule over the recorded hosts, schemes and paths; the current CDN (30-1) and http (30-9)", () {
      final legacy = _legacy('S02-room-live')['BaiduLiveApi.validateMediaUri'] as Map<String, dynamic>;
      const stream = 'stream_bduid_6325759471_11560887291';
      // The intended differences; every other vector is 3.x's.
      final changed = {
        // 30-9: the host's https certificate does not match it.
        'flv https://flv-live.bdstatic.com/live/$stream.flv': 'http://flv-live.bdstatic.com/live/$stream.flv',
        // 30-1: the platform's current CDN is a backup line, kept http.
        'flv http://flv.liveshow.lss-user.baidubce.com/live/$stream-L3.flv':
            'http://flv.liveshow.lss-user.baidubce.com/live/$stream-L3.flv',
        'hls http://hls2.liveshow.lss-user.baidubce.com/live/$stream-L3/playlist.m3u8':
            'http://hls2.liveshow.lss-user.baidubce.com/live/$stream-L3/playlist.m3u8',
      };
      expect(legacy.keys, containsAll(changed.keys));
      for (final MapEntry(:key, :value) in legacy.entries) {
        final space = key.indexOf(' ');
        final protocol = key.substring(0, space);
        final url = key.substring(space + 1);
        expect(
          BaiduLiveApi.mediaUrl(url, roomId: _liveRoom, protocol: protocol)?.toString(),
          changed.containsKey(key) ? changed[key] : value,
          reason: key,
        );
      }
    });

    test('states (30-5): paid, forbidden and banned keep the state, marked; playback says why', () {
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
        expect(parsed.startedAt, state == BaiduLiveState.live ? isNotNull : isNull, reason: '$status');
        if (state != BaiduLiveState.live) {
          expect(() => BaiduLiveApi.qualities(parsed), throwsA(isA<StreamUnavailable>()), reason: '$status');
        }
      }
      // The live sample has no recording: an ended copy of it is unplayable.
      expect(room({'status': '3'}).restriction, LiveRestriction.unplayable);
      expect(BaiduLiveApi.liveRoom(room({'status': '3'})).followGroup, FollowGroup.offline);
      for (final status in ['-1', 2, '7']) {
        expect(room({'status': status}).restriction, isNull, reason: 'not live or ended: not told ($status)');
      }
      for (final (changes, restriction, message) in [
        ({'has_pay_service': '1'}, LiveRestriction.paid, '(paid)'),
        ({'is_forbidden_url': 1}, LiveRestriction.unplayable, '(unplayable: forbidden or banned)'),
        ({'ban_status': 1}, LiveRestriction.unplayable, '(unplayable: forbidden or banned)'),
        ({'has_pay_service': 1, 'ban_status': 1}, LiveRestriction.unplayable, '(unplayable: forbidden or banned)'),
      ]) {
        final parsed = room(changes);
        expect(parsed.state, BaiduLiveState.live, reason: '$changes');
        expect(parsed.restriction, restriction, reason: '$changes');
        final detail = BaiduLiveApi.liveRoom(parsed);
        // 3.x showed these as unknown.
        expect(detail.liveStatus, LiveStatus.live, reason: '$changes');
        expect(detail.followGroup, FollowGroup.live, reason: '$changes');
        expect(detail.restriction, restriction, reason: '$changes');
        expect(detail.notice, '${BaiduLiveApi.restrictedNotice}\n${BaiduLiveApi.chatNotice}');
        expect(detail.onlineViewers, '25357', reason: 'live: the viewers are shown');
        expect(
          () => BaiduLiveApi.qualities(parsed),
          throwsA(isA<StreamUnavailable>().having((error) => '$error', 'message', contains(message))),
          reason: '$changes',
        );
        expect(
          () => BaiduLiveApi.resolution(parsed, const LivePlayQuality(quality: '原画', id: 'source')),
          throwsA(isA<StreamUnavailable>()),
          reason: '$changes',
        );
      }
      final paidOffline = BaiduLiveApi.liveRoom(room({'has_pay_service': 1, 'status': '2'}));
      expect([paidOffline.liveStatus, paidOffline.restriction], [LiveStatus.offline, null]);
      expect(paidOffline.notice, startsWith(BaiduLiveApi.restrictedNotice), reason: 'as 3.x, the notice says so');
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
      expect(() => parse({'error_code': '7', 'template': 'preview'}), throwsA(isA<ApiChanged>()));
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
      // 30-10: 3.x wrote "Baidu Live" for the nick and the title.
      expect(
        [nameless.nick, nameless.title, nameless.cover, nameless.category, nameless.followers, nameless.introduction],
        ['', '', '', '', null, ''],
      );
      expect(BaiduLiveApi.liveRoom(nameless).area, BaiduLiveApi.siteName);
      expect(BaiduLiveApi.liveRoom(nameless).introduction, isNull);
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
      // A live room's top-level fields are not the preview's: `source` is 1.
      expect(
        parse({
          'host': {'uk': 'u'},
          'source': 1,
        }).nick,
        '',
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

    test("when 3.x's hosts give nothing, every tier still plays from the platform's current CDN (kept http)", () {
      final room = BaiduLiveApi.room(
        _liveAnswer(video: {'live_hls_url': '', 'live_flv_url': '', 'live_flv_url_origin': ''}),
        expectedRoomId: _liveRoom,
      );
      const stream = 'stream_bduid_6325759471_11560887291';
      expect(
        {for (final variant in room.variants) variant.id: _variant(variant)['lines']},
        {
          'source': [
            'flv http://flv.liveshow.lss-user.baidubce.com/live/$stream.flv?kabr_spts=-3000&logid=722978952&ls_from=searchbox_371&ls_scene=baidu_liveshow',
            'hls http://hls.liveshow.lss-user.baidubce.com/live/$stream.m3u8',
          ],
          '720p': [
            'flv http://flv.liveshow.lss-user.baidubce.com/live/$stream-L3.flv',
            'flv http://flv2.liveshow.lss-user.baidubce.com/live/$stream-L3.flv',
            'hls http://hls.liveshow.lss-user.baidubce.com/live/$stream-L3.m3u8',
            'hls http://hls2.liveshow.lss-user.baidubce.com/live/$stream-L3/playlist.m3u8',
          ],
          '480p': [
            'flv http://flv.liveshow.lss-user.baidubce.com/live/$stream-L4.flv',
            'flv http://flv2.liveshow.lss-user.baidubce.com/live/$stream-L4.flv',
            'hls http://hls.liveshow.lss-user.baidubce.com/live/$stream-L4.m3u8',
            'hls http://hls2.liveshow.lss-user.baidubce.com/live/$stream-L4/playlist.m3u8',
          ],
        },
      );
      expect(room.variants.first.codec, 'avc', reason: 'avc_url names the source');
      final line = BaiduLiveApi.resolution(room, BaiduLiveApi.qualities(room).first).lines.first;
      expect(line.headers['referer'], 'https://live.baidu.com/m/room/$_liveRoom');
      expect(line.lineId, 'flv.liveshow.lss-user.baidubce.com');
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
      expect(nothing.restriction, LiveRestriction.unplayable, reason: 'live without a stream this client accepts');
      expect(() => BaiduLiveApi.qualities(nothing), throwsA(isA<StreamUnavailable>()));
    });

    test('media URLs: the room must be named, the path and extension right; hosts and schemes', () {
      String? url(String raw, {String protocol = 'flv'}) =>
          BaiduLiveApi.mediaUrl(raw, roomId: _liveRoom, protocol: protocol)?.toString();
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
      expect(url('https://hls-live.bdstatic.com:8443/live/a_$_liveRoom.flv'), isNull);
      expect(
        url('http://flv-live.bdstatic.com/live/a_$_liveRoom.flv'),
        'http://flv-live.bdstatic.com/live/a_$_liveRoom.flv',
      );
      expect(url('https://flv-live.bdstatic.com:8443/live/a_$_liveRoom.flv'), isNull);
      expect(
        url('http://flv.liveshow.lss-user.baidubce.com/live/a_$_liveRoom.flv'),
        'http://flv.liveshow.lss-user.baidubce.com/live/a_$_liveRoom.flv',
      );
      expect(
        url('http://flv.liveshow.lss-user.baidubce.com/live/a_${_liveRoom}_wz_hevc.flv'),
        'http://flv.liveshow.lss-user.baidubce.com/live/a_${_liveRoom}_wz_hevc.flv',
        reason: 'hevc_url: the id followed by _',
      );
      expect(url('http://flv.liveshow.lss-user.baidubce.com:8080/live/a_$_liveRoom.flv'), isNull);
      expect(url('http://lss-user.baidubce.com.evil.test/live/a_$_liveRoom.flv'), isNull);
      expect(url('rtmp://rtmp.liveshow.lss-user.baidubce.com/live/a_$_liveRoom'), isNull);
      expect(url('https://p2.bdstatic.com/live/a_$_liveRoom.flv'), isNull, reason: 'not a live stream host');
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
      expect(ended.restriction, LiveRestriction.none, reason: "this answer's, not the card's");
      final described = _room('S02-room-live', _liveRoom);
      expect(
        BaiduLiveApi.room(
          _liveAnswer(video: {'description': ''}),
          expectedRoomId: _liveRoom,
        ).enrich(described).introduction,
        described.introduction,
      );
    });
  });

  group('M4.U tiers (30-1, 30-2)', () {
    test('a clarity list (S02-room-clarity): 1080p, 720p, 540p, 480p and the source, whose codec is not told', () {
      final room = _room('S02-room-clarity', _clarityRoom);
      const stream = 'stream_bduid_836143438_11586212983';
      const query = '?kabr_spts=-3000&logid=3549026539&ls_from=searchbox_371&ls_scene=baidu_liveshow';
      expect(
        [for (final variant in room.variants) _variant(variant)],
        [
          {
            'id': 'source',
            'name': '原画',
            'codec': null,
            'sort': 1000001,
            'lines': [
              'flv http://flv-live.bdstatic.com/live/$stream.flv',
              'hls http://hls.liveshow.lss-user.baidubce.com/live/$stream.m3u8',
            ],
          },
          {
            'id': '1080p',
            'name': '1080p',
            'codec': 'avc',
            'sort': 10802,
            'lines': ['flv https://hls-live.bdstatic.com/live/$stream-LV1080.flv$query'],
          },
          {
            'id': '720p',
            'name': '720p',
            'codec': 'avc',
            'sort': 7202,
            'lines': [
              'flv https://hls-live.bdstatic.com/live/$stream-mid-LV720.flv$query',
              'hls https://hls.liveshow.bdstatic.com/live/$stream-L1.m3u8',
              'flv http://flv.liveshow.lss-user.baidubce.com/live/$stream-L1.flv',
              'flv http://flv2.liveshow.lss-user.baidubce.com/live/$stream-L1.flv',
              'flv http://flv.liveshow.lss-user.baidubce.com/live/$stream-mid-LV720.flv$query',
              'hls http://hls.liveshow.lss-user.baidubce.com/live/$stream-L1.m3u8',
              'hls http://hls2.liveshow.lss-user.baidubce.com/live/$stream-L1/playlist.m3u8',
            ],
          },
          {
            'id': '540p',
            'name': '540p',
            'codec': 'avc',
            'sort': 5402,
            'lines': ['flv https://hls-live.bdstatic.com/live/$stream-LV540.flv$query'],
          },
          {
            'id': '480p',
            'name': '480p',
            'codec': 'avc',
            'sort': 4802,
            'lines': [
              'flv http://flv.liveshow.lss-user.baidubce.com/live/$stream-L2.flv',
              'flv http://flv2.liveshow.lss-user.baidubce.com/live/$stream-L2.flv',
              'hls http://hls.liveshow.lss-user.baidubce.com/live/$stream-L2.m3u8',
              'hls http://hls2.liveshow.lss-user.baidubce.com/live/$stream-L2/playlist.m3u8',
            ],
          },
        ],
      );
      expect(BaiduLiveApi.qualities(room).map((quality) => quality.quality), ['1080p', '720p', '540p', '480p', '原画']);
      expect(BaiduLiveApi.qualities(room, preferH264: false).map((quality) => quality.quality), [
        '原画',
        '1080p',
        '720p',
        '540p',
        '480p',
      ]);
      final source = BaiduLiveApi.resolution(room, const LivePlayQuality(quality: '原画', id: 'source'));
      expect(source.lines.map((line) => line.codec), [null, null], reason: 'not told');
      expect(
        BaiduLiveApi.resolution(
          room,
          const LivePlayQuality(quality: '720p', id: '720p'),
        ).lines.map((line) => line.lineId),
        [
          'hls-live.bdstatic.com',
          'hls.liveshow.bdstatic.com',
          'flv.liveshow.lss-user.baidubce.com',
          'flv2.liveshow.lss-user.baidubce.com',
          'flv.liveshow.lss-user.baidubce.com#2',
          'hls.liveshow.lss-user.baidubce.com',
          'hls2.liveshow.lss-user.baidubce.com',
        ],
      );
      final detail = BaiduLiveApi.liveRoom(room);
      expect(
        [detail.liveStatus, detail.restriction, detail.startedAt],
        [LiveStatus.live, LiveRestriction.none, DateTime.utc(2026, 9, 28, 14, 13, 20)],
      );
      expect(detail.nick, '长江新闻号');
    });

    test('an H.265 original with a clarity list (S02-room-clarity-hevc): not told either, so H.264 first', () {
      final room = _room('S02-room-clarity-hevc', _clarityHevcRoom);
      expect(
        [for (final variant in room.variants) (variant.id, variant.codec)],
        [('source', null), ('1080p', 'avc'), ('720p', 'avc'), ('540p', 'avc'), ('480p', 'avc')],
      );
      expect(BaiduLiveApi.qualities(room).first.id, '1080p', reason: 'the default is H.264');
    });

    test('an H.265 original (S02-room-hevc): 原画 · H.265 apart, 720p and 480p in H.264 first', () {
      final room = _room('S02-room-hevc', _hevcRoom);
      const stream = 'stream_bduid_7029522182_11586291324';
      const query = '?kabr_spts=-3000&logid=2465795029&ls_from=searchbox_371&ls_scene=baidu_liveshow';
      expect(
        [for (final variant in room.variants) _variant(variant)],
        [
          {
            'id': 'source:hevc',
            'name': '原画 · H.265',
            'codec': 'hevc',
            'sort': 1000000,
            'lines': [
              'flv http://flv-live.bdstatic.com/live/$stream.flv',
              'flv http://flv.liveshow.lss-user.baidubce.com/live/${stream}_wz_hevc.flv$query',
              'hls http://hls.liveshow.lss-user.baidubce.com/live/$stream.m3u8',
            ],
          },
          {
            'id': '720p',
            'name': '720p',
            'codec': 'avc',
            'sort': 7202,
            'lines': [
              'flv https://hls-live.bdstatic.com/live/$stream-L3.flv$query',
              'hls https://hls.liveshow.bdstatic.com/live/$stream-L3.m3u8',
              'flv http://flv.liveshow.lss-user.baidubce.com/live/$stream-L3.flv',
              'flv http://flv2.liveshow.lss-user.baidubce.com/live/$stream-L3.flv',
              'hls http://hls.liveshow.lss-user.baidubce.com/live/$stream-L3.m3u8',
              'hls http://hls2.liveshow.lss-user.baidubce.com/live/$stream-L3/playlist.m3u8',
            ],
          },
          {
            'id': '480p',
            'name': '480p',
            'codec': 'avc',
            'sort': 4802,
            'lines': [
              'flv http://flv.liveshow.lss-user.baidubce.com/live/$stream-L4.flv',
              'flv http://flv2.liveshow.lss-user.baidubce.com/live/$stream-L4.flv',
              'hls http://hls.liveshow.lss-user.baidubce.com/live/$stream-L4.m3u8',
              'hls http://hls2.liveshow.lss-user.baidubce.com/live/$stream-L4/playlist.m3u8',
            ],
          },
        ],
      );
      expect(BaiduLiveApi.qualities(room).map((quality) => quality.quality), ['720p', '480p', '原画 · H.265']);
      expect(BaiduLiveApi.qualities(room, preferH264: false).map((quality) => quality.quality), [
        '原画 · H.265',
        '720p',
        '480p',
      ]);
      final hevc = BaiduLiveApi.resolution(room, const LivePlayQuality(quality: '原画 · H.265', id: 'source:hevc'));
      expect(hevc.lines.map((line) => line.codec), everyElement('hevc'));
      expect(hevc.appliedQualityData, 'source:hevc');
      // A stored 3.x "FLV 原始线路" is the H.264 source, which this room has
      // not: it is not offered (the H.265 one is only picked by hand).
      expect(
        () => BaiduLiveApi.resolution(room, const LivePlayQuality(quality: 'x', id: 'flv:0:avc')),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('clarity entries in H.265 (hevc_flv) are a tier of their own', () {
      final room = BaiduLiveApi.room(
        _liveAnswer(
          video: {
            'url_clarity_list': [
              {
                'resolution': 1080,
                'urls': {
                  'avc_flv': 'https://hls-live.bdstatic.com/live/stream_bduid_1_11560887291-LV1080.flv',
                  'hevc_flv': 'https://hls-live.bdstatic.com/live/stream_bduid_1_11560887291-LV1080-h265.flv',
                },
              },
              {
                'resolution': 0,
                'urls': {'avc_flv': 'https://hls-live.bdstatic.com/live/stream_bduid_1_11560887291-X.flv'},
              },
            ],
          },
        ),
        expectedRoomId: _liveRoom,
      );
      expect(
        [for (final variant in room.variants) (variant.id, variant.name, variant.codec)],
        [
          ('source', '原画', 'avc'),
          ('1080p', '1080p', 'avc'),
          ('1080p:hevc', '1080p · H.265', 'hevc'),
          ('720p', '720p', 'avc'),
          ('480p', '480p', 'avc'),
        ],
        reason: 'an entry without a height is skipped',
      );
      expect(BaiduLiveApi.qualities(room).map((quality) => quality.id), [
        'source',
        '1080p',
        '720p',
        '480p',
        '1080p:hevc',
      ]);
      expect(BaiduLiveApi.qualities(room, preferH264: false).map((quality) => quality.id), [
        'source',
        '1080p',
        '1080p:hevc',
        '720p',
        '480p',
      ]);
    });

    test("3.x's quality ids map to the tiers (for M9); any other id is kept", () {
      for (final MapEntry(:key, :value) in BaiduLiveApi.legacyQualityIds.entries) {
        expect(BaiduLiveApi.qualityIdFromLegacy(key), value, reason: key);
      }
      expect(BaiduLiveApi.qualityIdFromLegacy(' FLV:360:AVC '), '360p');
      for (final id in ['source', '720p', 'source:hevc', 'replay:sd', 'flv:720:hevc', 'rtmp:720:avc', '']) {
        expect(BaiduLiveApi.qualityIdFromLegacy(id), id, reason: 'kept: $id');
        expect(BaiduLiveApi.qualityIdFromLegacy(BaiduLiveApi.qualityIdFromLegacy(id)), id, reason: 'idempotent');
      }
      // Every id 3.x produced from the recorded answers is in the table.
      for (final sample in ['S02-room-live']) {
        for (final quality in _maps(_value(sample, 'getPlayQualites'))) {
          expect(BaiduLiveApi.legacyQualityIds, contains(quality['id']), reason: '${quality['id']}');
        }
      }
    });
  });

  group('M4.U replays (30-4)', () {
    const base = 'https://p2.bdstatic.com/rtmp.liveshow.lss-user.baidubce.com/live/stream_bduid_1_11583715413';

    String ended(Object? replayList) =>
        _command({..._command371(_sample('S02-room-ended').body), 'replay_list': replayList});

    test('the recording: clarity entries by their title, else the video; H.265 entries apart; bad URLs skipped', () {
      BaiduLiveRoom room(Object? replayList) => BaiduLiveApi.room(ended(replayList), expectedRoomId: _endedRoom);
      final plain = room([
        {'video': 'http://p2.bdstatic.com/rtmp.liveshow.lss-user.baidubce.com/live/stream_bduid_1_11583715413/a.m3u8'},
      ]);
      expect(
        [for (final variant in plain.variants) (variant.id, variant.name, variant.codec)],
        [('replay', '回放', 'avc')],
      );
      expect(plain.variants.single.sources.single.url.scheme, 'https', reason: 'http made https');
      final two = room([
        {'video': ''},
        {
          'video': '$base/v.m3u8',
          'videoInfo': {
            'ext': {
              'clarityUrl': [
                {'key': 'HD', 'title': '高清', 'url': '$base/hd.m3u8'},
                {'key': 'SD', 'title': '', 'url': '$base/sd.m3u8'},
                {'key': 'sd', 'title': '重复', 'url': '$base/sd2.m3u8'},
                {'key': 'bad key', 'title': 'x', 'url': '$base/x.m3u8'},
                {'key': 'LD', 'title': '流畅', 'url': 'https://evil.example/stream_bduid_1_11583715413/ld.m3u8'},
              ],
            },
          },
          'video_hevc': {'1080p': '$base/h.m3u8', '720p': 'https://p2.bdstatic.com/other_1/h.m3u8'},
        },
      ]);
      expect(
        [for (final variant in two.variants) (variant.id, variant.name, variant.codec)],
        [('replay:hd', '高清', 'avc'), ('replay:sd', 'SD', 'avc'), ('replay:1080p:hevc', '1080p · H.265', 'hevc')],
        reason: 'the first entry without a recording is passed over',
      );
      final none = room([
        {'video': 'https://p2.bdstatic.com/other_1/v.m3u8', 'video_hevc': 'not json'},
      ]);
      expect(none.variants, isEmpty);
      expect(none.restriction, LiveRestriction.unplayable);
      expect(BaiduLiveApi.liveRoom(none).followGroup, FollowGroup.offline);
      expect(
        () => BaiduLiveApi.qualities(none),
        throwsA(isA<StreamUnavailable>().having((error) => '$error', 'message', contains('without a recording'))),
      );
      expect(room(null).restriction, LiveRestriction.unplayable);
      final paid = BaiduLiveApi.room(
        jsonEncode({
          'errno': 0,
          'data': {
            '371': {
              ..._command371(ended(null)),
              'replay_list': [
                {'video': '$base/v.m3u8'},
              ],
              'has_pay_service': 1,
            },
          },
        }),
        expectedRoomId: _endedRoom,
      );
      expect(paid.restriction, LiveRestriction.paid);
      expect(() => BaiduLiveApi.qualities(paid), throwsA(isA<StreamUnavailable>()));
    });

    test('recording URLs: https m3u8 on bdstatic.com under the room stream', () {
      String? url(String raw) => BaiduLiveApi.replayUrl(raw, _endedRoom)?.toString();
      expect(url('$base/a.m3u8'), '$base/a.m3u8');
      expect(url('${base.replaceFirst('https', 'http')}/a.m3u8'), '$base/a.m3u8');
      expect(url('$base/a.mp4'), isNull);
      expect(url('$base/a.m3u8#x'), isNull);
      expect(url('https://p2.bdstatic.com:8443/live/stream_bduid_1_11583715413/a.m3u8'), isNull);
      expect(url('https://p2.bdstatic.com/live/stream_bduid_1_1158371541/a.m3u8'), isNull, reason: 'another room');
      expect(url('https://bdstatic.com.evil.test/live/stream_bduid_1_11583715413/a.m3u8'), isNull);
      expect(url('https://user@p2.bdstatic.com/live/stream_bduid_1_11583715413/a.m3u8'), isNull);
      expect(url(''), isNull);
    });
  });

  group('M4.U other items', () {
    test('an announced broadcast (S02-room-preview): its own shape, offline, no start (3.x refused it)', () {
      final room = _room('S02-room-preview', _previewRoom);
      expect(room.state, BaiduLiveState.preview);
      expect(
        [room.userId, room.nick, room.title, room.avatar, room.cover, room.category, room.followers],
        [
          'W6egNwOMg9YzIy5hDOHz2w',
          '向东传媒',
          '听！号声穿越90年——沿着红军足迹，弘扬伟大长征精神，书写更多的“新长征故事”',
          'https://avatar.bdstatic.com/it/u=2198437777,2624610511&fm=3012&app=3012&autime=1789606187&size=b200,200',
          'https://p2.bdstatic.com/liveUpload/pc_client_2e2b0b307db6074d449f358711a87ae9.jpeg',
          '时事',
          1610,
        ],
      );
      expect(room.introduction, startsWith('1934年10月至1936年10月'));
      final detail = BaiduLiveApi.liveRoom(room);
      expect([detail.liveStatus, detail.startedAt, detail.restriction], [LiveStatus.offline, null, null]);
      expect(() => BaiduLiveApi.qualities(room), throwsA(isA<StreamUnavailable>()));
    });

    test('the start (unified principle): create_time while live; zero, blanks and milliseconds are none', () {
      for (final (value, expected) in [
        (1789574398, DateTime.utc(2026, 9, 16, 15, 59, 58)),
        ('1789574398', DateTime.utc(2026, 9, 16, 15, 59, 58)),
        (0, null),
        (-5, null),
        ('', null),
        ('abc', null),
        (1789574398000, null),
        (1.5, null),
        (null, null),
      ]) {
        expect(BaiduLiveApi.startedAt(value), expected, reason: '$value');
        final room = BaiduLiveApi.room(_liveAnswer(changes: {'create_time': value}), expectedRoomId: _liveRoom);
        expect(room.startedAt, expected, reason: '$value');
      }
      expect(BaiduLiveApi.startedAt(1789574398)!.isUtc, isTrue);
    });

    test('the notices are written for users (30-10)', () {
      for (final text in [BaiduLiveApi.chatNotice, BaiduLiveApi.restrictedNotice, BaiduLiveApi.directoryScope]) {
        expect(text, isNot(matches(RegExp('[A-Za-z_]{3,}'))), reason: 'no field names or English: $text');
      }
      expect(BaiduLiveApi.restrictedNotice, isNot(contains('未知')), reason: '30-5: no longer shown as unknown');
    });
  });

  group('links', () {
    test("3.x's rule over room ids and links (BaiduLiveLink.parseRoomId); http links too (30-8)", () {
      final legacy = _legacy('S02-room-live')['BaiduLiveLink.parseRoomId'] as Map<String, dynamic>;
      expect(legacy, hasLength(26));
      // 30-8: 3.x's test pinned http links as refused.
      const changed = {'http://live.baidu.com/m/room/11560887291': '11560887291'};
      for (final MapEntry(:key, :value) in legacy.entries) {
        final expected = changed.containsKey(key) ? changed[key] : value;
        expect(BaiduLiveApi.parseRoomId(key), expected, reason: key);
        final isUrl = key.contains('://');
        expect(BaiduLiveApi.roomIdFromUrl(key), isUrl ? expected : null, reason: 'links only: $key');
      }
      expect(legacy, contains(changed.keys.single));
      expect(BaiduLiveApi.roomUrl(_liveRoom), _legacy('S02-room-live')['BaiduLiveLink.watchUrl']);
    });

    test("3.x's link cases; http on its default port; a link that does not decode is no link (3.x threw)", () {
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
        'http://live.baidu.com/m/room/11572411040',
        'HTTP://live.baidu.com:80/m/room/11572411040',
        'http://live.baidu.com/m/media/pclive/pchome/live.html?room_id=11572411040',
        'http://live.baidu.com/m/media/multipage/liveshow/index/cadm?room_id=11572411040',
      ]) {
        expect(BaiduLiveApi.roomIdFromUrl(value), '11572411040', reason: value);
      }
      for (final value in [
        'https://live.baidu.com/search?room_id=11572411040',
        'https://live.baidu.com.evil.test/m/room/11572411040',
        'https://user@live.baidu.com/m/room/11572411040',
        'http://live.baidu.com:443/m/room/11572411040',
        'https://live.baidu.com:80/m/room/11572411040',
        'ftp://live.baidu.com/m/room/11572411040',
        '12',
        'https://live.baidu.com/m/media/pclive/pchome/live.html?room_id=%FF',
        'https://live.baidu.com/%FF/m/room/11572411040',
      ]) {
        expect(BaiduLiveApi.parseRoomId(value), isNull, reason: value);
      }
    });
  });

  group('danmaku arguments (M5.26)', () {
    const chatRoom = '11548522172';

    Map<String, dynamic> command(String sample) =>
        ((jsonDecode(_sample(sample).body) as Map<String, dynamic>)['data'] as Map<String, dynamic>)['371']
            as Map<String, dynamic>;

    /// An http URL as https.
    String https(Object? url) => (url! as String).replaceFirst('http://', 'https://');

    /// A live command with [changes] applied, as a room of [chatRoom].
    BaiduLiveDanmakuArgs? argsOf(Map<String, Object?> changes, {Map<String, Object?> video = const {}}) {
      final base = command('S02-room-chat')..addAll(changes);
      base['video'] = {...base['video'] as Map<String, dynamic>, ...video};
      return BaiduLiveApi.danmakuArgs(base, chatRoom);
    }

    test('S02-room-chat: the three lists, 5 s, and when the signature runs out; room entry carries them', () {
      final body = command('S02-room-chat');
      final room = _room('S02-room-chat', chatRoom);
      final args = room.danmaku!;
      expect(args.roomId, chatRoom);
      // The page asks over its own protocol (https); the query is kept.
      expect(args.chatList.toString(), https(body['chat_msg_hls_url']));
      expect(args.reliableList.toString(), https(body['reliable_msg_hls_url']));
      expect(args.hostList.toString(), https(body['host_msg_hls_url']));
      expect(args.chatList.path, '/v1/liveshowstatic/live_11548522172.m3u8');
      expect(args.pullInterval, const Duration(seconds: 5));
      // Signed at the recording (12:23:03 UTC) for 15768000 s (182.5 days).
      final signed = RegExp(r'/(\d{4}-\d\d-\d\dT[\d:]+Z)/15768000/').firstMatch(body['chat_msg_hls_url'] as String)!;
      expect(args.expiresAt, DateTime.parse(signed.group(1)!).add(const Duration(seconds: 15768000)));
      expect(args.expiresAt, DateTime.utc(2027, 4, 1, 0, 23, 3));
      final captured = _sample('S02-room-chat').capturedAt;
      expect(args.expiresAt!.difference(captured).inDays, 182);
      expect(args.isExpiredAt(captured), isFalse);
      expect(args.isExpiredAt(args.expiresAt!.subtract(const Duration(seconds: 1))), isFalse);
      expect(args.isExpiredAt(args.expiresAt!), isTrue);
      expect(args.toString(), 'BaiduLiveDanmakuArgs(11548522172)', reason: 'no signature in logs');
      expect(BaiduLiveApi.liveRoom(room, withData: true).danmakuData, same(args));
      expect(BaiduLiveApi.liveRoom(room).danmakuData, isNull, reason: 'lists and follow refreshes');
    });

    test('the older samples: lists whose signatures were scrubbed say no expiry; not live has none', () {
      for (final (sample, id) in [
        ('S02-room-live', _liveRoom),
        ('S02-room-clarity', _clarityRoom),
        ('S02-room-hevc', _hevcRoom),
      ]) {
        final body = command(sample);
        final args = _room(sample, id).danmaku!;
        expect(args.chatList.toString(), https(body['chat_msg_hls_url']), reason: sample);
        expect(args.hostList.toString(), https(body['host_msg_hls_url']), reason: sample);
        expect(args.expiresAt, isNull, reason: '$sample: the whole authorization was scrubbed');
        expect(args.isExpiredAt(DateTime.utc(2100)), isFalse);
      }
      expect(_room('S02-room-ended', _endedRoom).danmaku, isNull, reason: 'ended: the replay has no chat to poll');
      expect(_room('S02-room-preview', _previewRoom).danmaku, isNull);
      expect(BaiduLiveApi.liveRoom(_room('S02-room-ended', _endedRoom), withData: true).danmakuData, isNull);
    });

    test('the chat list falls back to video.msg_hls_url; lists must be m3u8 on liveshowstatic.baidu.com', () {
      final video = command('S02-room-chat')['video'] as Map<String, dynamic>;
      expect(argsOf({'chat_msg_hls_url': null})!.chatList.toString(), https(video['msg_hls_url']));
      expect(argsOf({'chat_msg_hls_url': ''}, video: {'msg_hls_url': null}), isNull);
      const base = 'liveshowstatic.baidu.com/v1/liveshowstatic/live_1.m3u8';
      for (final valid in [
        'http://$base',
        'https://$base',
        'HTTP://LIVESHOWSTATIC.baidu.com/v1/a.m3u8?authorization=x',
      ]) {
        expect(BaiduLiveApi.messageList(valid)?.scheme, 'https', reason: valid);
      }
      const escaped = '$base?authorization=bce-auth-v1%2Fak%2F2026-09-30T12%3A00%3A00Z%2F60%2Fhost%2Fsig';
      expect(BaiduLiveApi.messageList('http://$escaped').toString(), 'https://$escaped', reason: 'query kept as given');
      for (final invalid in [
        'ftp://$base',
        'http://evil.example.com/v1/live_1.m3u8',
        'http://liveshowstatic.baidu.com.evil.test/v1/live_1.m3u8',
        'http://user@$base',
        'http://$base#fragment',
        'http://liveshowstatic.baidu.com/v1/live_1.ts',
        '/v1/liveshowstatic/live_1.m3u8',
        '',
        42,
        null,
      ]) {
        expect(BaiduLiveApi.messageList(invalid), isNull, reason: '$invalid');
      }
      final args = argsOf({'reliable_msg_hls_url': 'http://evil.example.com/a.m3u8', 'host_msg_hls_url': null})!;
      expect(args.reliableList, isNull);
      expect(args.hostList, isNull);
    });

    test('the poll interval: positive seconds within 1–10, else 5 s; the video one when the room has none', () {
      for (final (value, seconds) in [
        (3, 3),
        ('7', 7),
        (' 2 ', 2),
        (1, 1),
        (30, 10),
        (0, 5),
        (-2, 5),
        ('x', 5),
        (2.5, 5),
        (null, 5),
      ]) {
        expect(
          argsOf({'msg_hls_pull_internal_in_second': value})!.pullInterval,
          Duration(seconds: seconds),
          reason: '$value',
        );
      }
      expect(
        argsOf(
          {'msg_hls_pull_internal_in_second': null},
          video: {'msg_hls_pull_internal_in_second': '4'},
        )!.pullInterval,
        const Duration(seconds: 4),
      );
    });

    test('the signature: bce-auth-v1 time plus validity, plain or escaped; anything else says nothing', () {
      Uri list(String authorization) =>
          Uri.parse('http://liveshowstatic.baidu.com/v1/liveshowstatic/live_1.m3u8?x=1&authorization=$authorization');
      expect(
        BaiduLiveApi.signatureExpiry(list('bce-auth-v1/ak/2026-09-30T12:00:00Z/3600/host/sig')),
        DateTime.utc(2026, 9, 30, 13),
      );
      expect(
        BaiduLiveApi.signatureExpiry(list('bce-auth-v1%2Fak%2F2026-09-30T12%3A00%3A00Z%2F60%2Fhost%2Fsig')),
        DateTime.utc(2026, 9, 30, 12, 1),
      );
      for (final authorization in [
        'gze-sqpv-e3%2F8e9557sx16od118v726720u25xa2w6p9%2F4540-82-83D49%3A89%3A54B%2F09756953%2Fqdme%2Fz8n',
        'bce-auth-v2/ak/2026-09-30T12:00:00Z/3600/host/sig',
        'bce-auth-v1/ak/2026-09-30T12:00:00/3600/host/sig',
        'bce-auth-v1/ak/2026-13-45T12:00:00Z/3600/host/sig',
        'bce-auth-v1/ak/2026-09-30T12:00:00Z/0/host/sig',
        'bce-auth-v1/ak/2026-09-30T12:00:00Z/-1/host/sig',
        'bce-auth-v1/ak/2026-09-30T12:00:00Z/12345678901/host/sig',
        'bce-auth-v1/ak/2026-09-30T12:00:00Z',
        '',
      ]) {
        expect(BaiduLiveApi.signatureExpiry(list(authorization)), isNull, reason: authorization);
      }
      expect(BaiduLiveApi.signatureExpiry(Uri.parse('http://liveshowstatic.baidu.com/v1/a.m3u8')), isNull);
    });

    test("enrich keeps this answer's lists; equality and hash", () {
      final room = _room('S02-room-chat', chatRoom);
      final card = BaiduLiveRoom(
        roomId: chatRoom,
        userId: 'uk',
        nick: 'nick',
        title: 'title',
        avatar: '',
        cover: '',
        category: '',
        currentViewers: 1,
        followers: null,
        state: BaiduLiveState.live,
      );
      expect(room.enrich(card).danmaku, same(room.danmaku));
      expect(card.enrich(room).danmaku, isNull, reason: 'a card has no lists of its own');
      final again = _room('S02-room-chat', chatRoom).danmaku!;
      expect(again, room.danmaku);
      expect(again.hashCode, room.danmaku.hashCode);
      expect(again == argsOf({'msg_hls_pull_internal_in_second': 6}), isFalse);
    });

    test('the room notice no longer says the chat cannot be seen; 3.x text kept (M5.26)', () {
      expect(BaiduLiveApi.chatNotice, '人数是正在观看的人数，主播的粉丝数另外显示。');
      expect(BaiduLiveApi.chatNotice, isNot(contains('聊天')));
      final legacy = _legacy('S02-room-live')['getRoomDetail'] as Map<String, dynamic>;
      expect((legacy['value'] as Map<String, dynamic>)['notice'], BaiduLiveApi.legacyChatNotice);
      expect(BaiduLiveApi.liveRoom(_room('S02-room-chat', chatRoom)).notice, BaiduLiveApi.chatNotice);
    });
  });
}
