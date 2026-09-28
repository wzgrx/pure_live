// PandaTV parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/pandalive/legacy_expected.dart from 3.x's PandaLiveApi,
// PandaLiveLink and PandaLiveSite). Every intended difference is listed
// with its reason; everything else must match. The synthetic cases port
// 3.x's pandalive_site_test.dart and pandalive_native_search_test.dart
// (the parsing parts) and cover the regression entries of the archived spec
// (REG-PANDALIVE-001–005) and the shapes 3.x refused.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('pandalive', name);

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

/// The outcome of a counted legacy call (`{requests, value}`).
Map<String, dynamic> _outcome(String name, String key) => _legacy(name)[key] as Map<String, dynamic>;

Object? _value(String name, String key) => _outcome(name, key)['value'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

/// 3.x put the media headers on every room (`httpHeaders`), where only
/// IPTV's are read (3.x's PlaybackHeaderResolver built PandaTV's again from
/// the room id); they now travel on every line.
const _headersMoved = {'httpHeaders'};

PandaLiveMember _member(String sample, String userId) {
  final fixture = _sample(sample);
  return PandaLiveApi.member(fixture.body, userId: userId, status: fixture.status);
}

/// `S04-member-live` as the answer for broadcaster [userId] number [index]
/// (the legacy harness's answer for the refused `live/play` samples).
String _syntheticMember(String userId, int index, {required bool adult}) {
  final member = jsonDecode(_sample('S04-member-live').body) as Map<String, dynamic>;
  (member['media'] as Map<String, dynamic>)
    ..['userId'] = userId
    ..['userIdx'] = index
    ..['isAdult'] = adult;
  (member['bjInfo'] as Map<String, dynamic>)
    ..['id'] = userId
    ..['idx'] = index;
  return jsonEncode(member);
}

/// A broadcast as the platform lists it (3.x's test `_media`).
Map<String, Object?> _media({String id = 'fixture_101', int index = 101, Map<String, Object?> changes = const {}}) => {
  'code': '${index}_fixture',
  'title': 'Fixture live',
  'userId': id,
  'userIdx': index,
  'userNick': 'Fixture owner',
  'category': 'talk',
  'isAdult': false,
  'isPw': false,
  'user': 127,
  'isLive': true,
  'playCnt': 900,
  'fanCnt': 9371,
  'thumbUrl': 'https://cdn.pandalive.co.kr/cover.jpg',
  'ivsThumbnail': 'https://cdn.pandalive.co.kr/ivs.jpg',
  'userImg': 'https://cdn.pandalive.co.kr/avatar.jpg',
  ...changes,
};

/// A `member/bj` answer (3.x's test `_member`).
String _memberAnswer({
  String id = 'fixture_101',
  int index = 101,
  Object? media,
  Map<String, Object?> info = const {},
}) => jsonEncode({
  'fanGrade': <Object?>[],
  'media': ?media,
  'bjInfo': {
    'idx': index,
    'id': id,
    'nick': 'Fixture owner',
    'thumbUrl': 'https://cdn.pandalive.co.kr/avatar.jpg',
    'channelTitle': 'Fixture channel',
    'channelDesc': 'Fixture introduction',
    'channelBannerUrl': 'https://cdn.pandalive.co.kr/banner.jpg',
    'fanCnt': 9371,
    ...info,
  },
  'result': true,
  'message': '',
});

const _masterUrl = 'https://fixture.us-west-2.playback.live-video.net/api/video/v1/fixture.m3u8?token=fixture';

/// A `live/play` answer (3.x's test `_play`).
String _playAnswer({Object? media, Object? playList, Map<String, Object?> changes = const {}}) => jsonEncode({
  'media': media ?? _media(),
  'PlayList':
      playList ??
      {
        'hls3': [
          {'name': '자동', 'sort': 1, 'url': _masterUrl},
        ],
        'hls2': <Object?>[],
        'hls': <Object?>[],
      },
  'channel': '101',
  'token': 'chat-token',
  'result': true,
  'message': '시청이 시작되었습니다.',
  ...changes,
});

String _refusal(String? code, {String message = 'refused'}) => jsonEncode({
  'result': false,
  'message': message,
  if (code != null) 'errorData': {'code': code},
});

/// A paged answer (`live/index`, `live/bj_list`).
String _page(List<Object?> rows, {int page = 1, int size = 30, int? total, Map<String, Object?> paging = const {}}) =>
    jsonEncode({
      'list': rows,
      'page': {
        'offset': (page - 1) * size,
        'limit': size,
        'total': total ?? (page - 1) * size + rows.length,
        'page': page,
        ...paging,
      },
      'result': true,
      'message': '',
    });

/// A `live/bj_list` row (3.x's test `_bj`).
Map<String, Object?> _broadcaster({String id = 'see994', int index = 202, Object? media, Object? block = false}) => {
  'userId': id,
  'userIdx': index,
  'userNick': '가온主播',
  'thumbUrl': 'https://cdn.pandalive.co.kr/avatar.jpg',
  'blockService': block,
  'media': ?media,
};

String _masterText(List<String> variants) => ['#EXTM3U', ...variants, ''].join('\n');

String _variant(
  String resolution, {
  int bandwidth = 1000,
  String frameRate = '30.000',
  String? uri,
  String? codecs,
}) => [
  '#EXT-X-STREAM-INF:BANDWIDTH=$bandwidth,RESOLUTION=$resolution,CODECS="${codecs ?? 'avc1.4D401F,mp4a.40.2'}",FRAME-RATE=$frameRate',
  uri ?? 'https://fixture.playlist.live-video.net/v1/playlist/$resolution-$bandwidth.m3u8',
].join('\n');

final DateTime _issuedAt = DateTime.utc(2026, 9, 27, 18, 50);

List<LivePlayQuality> _qualities(String text, {String master = _masterUrl, String userId = 'fixture_101'}) =>
    PandaLiveApi.qualities(text, master: Uri.parse(master), userId: userId, issuedAt: _issuedAt);

LivePlayLine _line(LivePlayQuality quality) => (quality.data! as List<LivePlayLine>).single;

void main() {
  group('catalog', () {
    test("3.x's fixed catalog: one category, the public area", () {
      final legacy = _maps(_value('S01-index-hot', 'getCategores(1)'));
      final categories = PandaLiveApi.categories();
      expect(categories.map((category) => category.id), legacy.map((category) => category['id']));
      expect(categories.map((category) => category.name), legacy.map((category) => category['name']));
      final areas = _maps(legacy.single['children']);
      expect(categories.single.children, hasLength(areas.length));
      _expectParity(categories.single.children.single.toJson(), areas.single);
      expect(categories.single.children.single.areaName, '公开直播');
      expect(_value('S01-index-hot', 'getCategores(2)'), 0);
      expect(_legacy('S01-index-hot')['directoryNoticeKey'], 'pandalive_directory_scope');
      expect(_legacy('S01-index-hot')['name'], PandaLiveApi.categoryName);
    });

    test('checkArea: null or the public area; anything else is a caller error (3.x: identity)', () {
      PandaLiveApi.checkArea(null);
      PandaLiveApi.checkArea(PandaLiveApi.categories().single.children.single);
      expect(_value('S01-index-hot', 'getDirectoryPage(1, other area)'), containsPair('message', 'PandaTV identity'));
      for (final area in [
        const LiveArea(platform: 'pandalive', areaType: 'directory', areaId: 'newbj'),
        const LiveArea(platform: 'pandalive', areaType: 'category', areaId: 'public'),
        const LiveArea(platform: 'chzzk', areaType: 'directory', areaId: 'public'),
      ]) {
        expect(() => PandaLiveApi.checkArea(area), throwsArgumentError, reason: '$area');
      }
    });

    test('checkPage: 1–1000 (3.x: schema, before any request)', () {
      expect(_value('S01-index-hot', 'getDirectoryPage(0)'), containsPair('message', 'PandaTV schema'));
      PandaLiveApi.checkPage(1);
      PandaLiveApi.checkPage(1000);
      expect(() => PandaLiveApi.checkPage(0), throwsRangeError);
      expect(() => PandaLiveApi.checkPage(1001), throwsRangeError);
    });
  });

  group('S01 public directory', () {
    test('page 1: same 30 rooms, fields and "more" as 3.x', () {
      final fixture = _sample('S01-index-hot');
      final legacy = _value('S01-index-hot', 'getDirectoryPage(1)')! as Map<String, dynamic>;
      final page = PandaLiveApi.livePage(fixture.body, page: 1, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      expect(page.rooms, hasLength(30));
      expect(page.rooms.map((room) => room.roomId), rooms.map((room) => room['roomId']));
      for (final (index, room) in page.rooms.indexed) {
        _expectParity(_projection(room), rooms[index], changed: _headersMoved, reason: 'p1[$index]');
        expect(room.httpHeaders, isEmpty);
      }
      expect(page.hasMore, legacy['hasMore']);
      expect(page.page, 1);
      for (final key in ['getRecommendRooms(1)', 'getCategoryRooms(1)']) {
        expect(_maps(_value('S01-index-hot', key)).map((room) => room['roomId']), rooms.map((room) => room['roomId']));
      }
    });

    test('the last page (offset 120 of 128): same 8 rooms, no more', () {
      final fixture = _sample('S01-index-hot-last');
      final legacy = _value('S01-index-hot-last', 'getDirectoryPage(5)')! as Map<String, dynamic>;
      final page = PandaLiveApi.livePage(fixture.body, page: 5, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      expect(page.rooms, hasLength(8));
      for (final (index, room) in page.rooms.indexed) {
        _expectParity(_projection(room), rooms[index], changed: _headersMoved, reason: 'p5[$index]');
      }
      expect(page.hasMore, isFalse);
      expect(legacy['hasMore'], isFalse);
    });

    test("the form is 3.x's: 30 by popularity from the page's offset", () {
      final sent = (_outcome('S01-index-hot', 'getDirectoryPage(1)')['requests'] as List).single as Map;
      expect(PandaLiveApi.directoryForm(1), sent['form']);
      expect(PandaLiveApi.directoryForm(1).keys, (sent['form'] as Map).keys, reason: 'field order');
      final last = (_outcome('S01-index-hot-last', 'getDirectoryPage(5)')['requests'] as List).single as Map;
      expect(PandaLiveApi.directoryForm(5), last['form']);
    });

    test("cards: 3.x's live card rules (ported from pandalive_site_test's directory case)", () {
      final page = PandaLiveApi.livePage(_page([_media()], page: 2, total: 61), page: 2);
      final room = page.rooms.single;
      expect(page.hasMore, isTrue);
      expect(room.roomId, 'fixture_101');
      expect(room.userId, 'fixture_101', reason: '3.x: the card userId is the id, the detail its number');
      expect(room.onlineViewers, '127');
      expect(room.followers, '9371');
      expect(room.totalViewers, '', reason: 'playCnt is not concurrency (3.x notice)');
      expect(room.effectiveAudienceMetricType, AudienceMetricType.onlineViewers);
      expect(room.cover, 'https://cdn.pandalive.co.kr/cover.jpg');
      expect(room.area, 'talk');
      expect(room.notice, PandaLiveApi.chatNotice);
      expect(room.link, 'https://www.pandalive.co.kr/live/play/fixture_101');
    });

    test('cards: adult, else password notices; the cover falls back on ivsThumbnail only when thumbUrl is absent', () {
      LiveRoom card(Map<String, Object?> changes) => PandaLiveApi.liveCard(_media(changes: changes))!;
      expect(card({'isAdult': true, 'isPw': true}).notice, PandaLiveApi.adultNotice);
      expect(card({'isAdult': 'N', 'isPw': 'Y'}).notice, PandaLiveApi.passwordNotice);
      expect(card({'isAdult': 0, 'isPw': 0}).notice, PandaLiveApi.chatNotice);
      expect(card({'thumbUrl': null}).cover, 'https://cdn.pandalive.co.kr/ivs.jpg');
      expect(card({'thumbUrl': ''}).cover, '', reason: "3.x's `??`: an empty thumbUrl is kept");
    });

    test('rows 3.x refused (failing the whole page) are skipped or left empty', () {
      final page = PandaLiveApi.livePage(
        _page([
          _media(changes: {'isLive': false}),
          _media(id: 'bad/id'),
          _media(changes: {'userId': null}),
          'not a row',
          _media(id: 'untitled', changes: {'title': '', 'userNick': ' '}),
          _media(
            id: 'odd',
            changes: {
              'userImg': 'https://evil.example/avatar.jpg',
              'thumbUrl': 'http://cdn.pandalive.co.kr/cover.jpg',
              'category': 7,
              'user': -1,
              'fanCnt': 'many',
              'isAdult': 'maybe',
              'userIdx': 0,
            },
          ),
          _media(id: 'Odd'),
        ]),
        page: 1,
      );
      expect(page.rooms.map((room) => room.roomId), ['untitled', 'odd'], reason: 'a broadcaster once, without case');
      final untitled = page.rooms.first;
      expect(untitled.nick, 'untitled');
      expect(untitled.title, 'untitled');
      final odd = page.rooms.last;
      expect([odd.avatar, odd.cover, odd.area, odd.onlineViewers, odd.followers], everyElement(''));
      expect(odd.notice, PandaLiveApi.chatNotice);
    });

    test("the page must be the one asked (3.x's _pagedRows); else ApiChanged", () {
      for (final (body, reason) in [
        (_page([], paging: {'offset': 30}), 'offset'),
        (_page([], paging: {'limit': 20}), 'limit'),
        (_page([], paging: {'page': 2}), 'page'),
        (_page([], paging: {'total': null}), 'total'),
        (_page(List.filled(65, _media())), 'over 64 rows'),
        (jsonEncode({'result': true, 'list': <Object?>[]}), 'no page'),
        (
          jsonEncode({
            'result': true,
            'page': {'offset': 0, 'limit': 30, 'total': 0, 'page': 1},
            'list': <String, Object?>{},
          }),
          'list',
        ),
        (jsonEncode({'list': <Object?>[], 'page': <String, Object?>{}}), 'no result flag'),
        (jsonEncode({'result': 'true', 'list': <Object?>[], 'page': <String, Object?>{}}), 'result is not a flag'),
        (_refusal(null), 'refused without a code'),
        ('<html>', 'not JSON'),
      ]) {
        expect(() => PandaLiveApi.livePage(body, page: 1), throwsA(isA<ApiChanged>()), reason: reason);
      }
      expect(PandaLiveApi.livePage(_page([], total: 0), page: 1).hasMore, isFalse);
      final skipped = PandaLiveApi.livePage(_page(['not a row', _media()], total: 3), page: 1);
      expect(skipped.rooms, hasLength(1));
      expect(skipped.hasMore, isTrue, reason: '3.x counted the rows sent, skipped ones included');
      expect(PandaLiveApi.livePage(_page(['not a row', _media()], total: 2), page: 1).hasMore, isFalse);
    });
  });

  group('S03 search', () {
    test('LIVE search (20 a page): same 2 live cards as 3.x', () {
      final fixture = _sample('S03-search-live');
      final legacy = _value('S03-search-live', 'searchLive')! as Map<String, dynamic>;
      final page = PandaLiveApi.livePage(fixture.body, page: 1, size: 20, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      expect(page.rooms.map((room) => room.roomId), ['daisy00', 'chirch']);
      for (final (index, room) in page.rooms.indexed) {
        _expectParity(_projection(room), rooms[index], changed: _headersMoved, reason: 'live[$index]');
      }
      expect(page.hasMore, legacy['hasMore']);
    });

    test('BJ search (20 a page): same 4 broadcasters as 3.x, live and offline, userId their number', () {
      final fixture = _sample('S03-search-bj');
      final legacy = _value('S03-search-bj', 'searchBroadcasters')! as Map<String, dynamic>;
      final page = PandaLiveApi.broadcasterPage(fixture.body, page: 1, size: 20, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      expect(page.rooms.map((room) => room.roomId), ['daisy00', 'flffl369', 'hhd006', 'candygirl35']);
      for (final (index, room) in page.rooms.indexed) {
        _expectParity(_projection(room), rooms[index], changed: _headersMoved, reason: 'bj[$index]');
      }
      expect(page.rooms.first.isLiveNow, isTrue);
      expect(page.rooms.first.userId, '24133575');
      expect(page.rooms.skip(1).map((room) => room.liveStatus), everyElement(LiveStatus.offline));
      expect(page.hasMore, legacy['hasMore']);
    });

    test("the forms and Referers are 3.x's", () {
      final sent = (_outcome('S03-search-live', 'searchRooms')['requests'] as List).cast<Map<String, dynamic>>();
      expect(sent.map((request) => request['url']), [
        'https://api.pandalive.co.kr/v1/live/bj_list',
        'https://api.pandalive.co.kr/v1/live/index',
      ]);
      final broadcasters = PandaLiveApi.broadcasterSearchForm('데이지', page: 1, size: 20);
      expect(broadcasters, sent.first['form']);
      expect(broadcasters.keys, (sent.first['form'] as Map).keys);
      final live = PandaLiveApi.liveSearchForm('데이지', page: 1, size: 20);
      expect(live, sent.last['form']);
      expect(live.keys, (sent.last['form'] as Map).keys);
      expect(PandaLiveApi.searchReferer('bj', '데이지'), sent.first['referer']);
      expect(PandaLiveApi.searchReferer('live', '데이지'), sent.last['referer']);
      expect(PandaLiveApi.liveSearchForm('가온', page: 2, size: 2), containsPair('offset', '2'));
    });

    test("BJ rows: 3.x's skips (blocked, no id or number, someone else's media) and states", () {
      final page = PandaLiveApi.broadcasterPage(
        _page([
          _broadcaster(
            id: 'gaoninc',
            index: 101,
            media: _media(id: 'gaoninc'),
          ),
          _broadcaster(id: '1506087545@ka', index: 303),
          _broadcaster(id: 'bad', index: 404, media: _media()),
          _broadcaster(
            id: 'number',
            index: 405,
            media: _media(id: 'number', index: 406),
          ),
          _broadcaster(id: 'blocked', block: true),
          _broadcaster(id: 'blocked2', block: 'Y'),
          _broadcaster(id: 'no/id'),
          _broadcaster(id: 'noindex', index: 0),
          _broadcaster(id: 'oddmedia', index: 7, media: 'live'),
          _broadcaster(
            id: 'unknown',
            index: 8,
            media: _media(id: 'unknown', index: 8, changes: {'isLive': null, 'isPw': true}),
          ),
          _broadcaster(
            id: 'ended',
            index: 9,
            media: _media(id: 'ended', index: 9, changes: {'isLive': false, 'isAdult': true}),
          ),
        ], size: 11),
        page: 1,
        size: 11,
      );
      expect(page.rooms.map((room) => room.roomId), ['gaoninc', '1506087545@ka', 'unknown', 'ended']);
      final [live, offline, unknown, ended] = page.rooms;
      expect(live.liveStatus, LiveStatus.live);
      expect(live.onlineViewers, '127');
      expect(live.title, 'Fixture live');
      expect(live.userId, '101');
      expect(offline.liveStatus, LiveStatus.offline);
      expect(offline.onlineViewers, '');
      expect(offline.title, '가온主播');
      expect(offline.cover, '');
      expect(offline.link, 'https://www.pandalive.co.kr/live/play/1506087545@ka');
      expect(unknown.liveStatus, LiveStatus.unknown);
      expect(unknown.onlineViewers, '');
      expect(unknown.notice, PandaLiveApi.passwordNotice);
      expect(ended.liveStatus, LiveStatus.offline);
      expect(ended.notice, PandaLiveApi.adultNotice);
      expect(page.hasMore, isFalse);
    });
  });

  group('S04 member/bj', () {
    test("live broadcaster: the refresh room is 3.x's, live by the listed media", () {
      final member = _member('S04-member-live', 'daisy00');
      expect(member.index, 24133575);
      expect(member.media, isNotNull);
      final room = PandaLiveApi.refreshRoom(member);
      _expectParity(
        _projection(room),
        _value('S04-member-live', 'getRoomDetailForRefresh')! as Map<String, dynamic>,
        changed: _headersMoved,
      );
      expect(room.userId, '24133575');
      expect(room.onlineViewers, '50', reason: 'member/bj media');
      expect(room.introduction, '데이지ღ님의 방송국에 어서오세요.');
      expect(_value('S04-member-live', 'getLiveStatus'), isTrue);
    });

    test("offline broadcaster: the channel as 3.x's profile room", () {
      final member = _member('S04-member-offline', 'flffl369');
      expect(member.media, isNull);
      final room = PandaLiveApi.profileRoom(member);
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        _expectParity(
          _projection(room),
          _value('S04-member-offline', key)! as Map<String, dynamic>,
          changed: _headersMoved,
          reason: key,
        );
      }
      expect(PandaLiveApi.refreshRoom(member).toJson(), room.toJson());
      expect(room.title, '데이지ෆ님의 방송국');
      expect(room.cover, '', reason: 'no banner');
      expect(_value('S04-member-offline', 'getLiveStatus'), isFalse);
    });

    test('no such broadcaster (HTTP 400) is NotFound (REG-PANDALIVE-001; 3.x: schema)', () {
      final fixture = _sample('S04-member-notfound');
      expect(fixture.status, 400);
      expect(_value('S04-member-notfound', 'getRoomDetail'), containsPair('message', 'PandaTV schema'));
      expect(
        () => PandaLiveApi.member(fixture.body, userId: 'zxqvnouserfix', status: fixture.status),
        throwsA(isA<NotFound>()),
      );
      expect(
        () => PandaLiveApi.member(_refusal(null, message: '유저 정보가 없습니다.'), userId: 'a1'),
        throwsA(isA<NotFound>()),
        reason: 'also with HTTP 200',
      );
    });

    test('identity: the id is kept as asked, compared without case; anything else is ApiChanged', () {
      final member = PandaLiveApi.member(_memberAnswer(media: _media()), userId: 'Fixture_101');
      expect(member.userId, 'Fixture_101');
      expect(PandaLiveApi.refreshRoom(member).roomId, 'Fixture_101');
      for (final (body, reason) in [
        (_memberAnswer(id: 'someone'), 'bjInfo of another'),
        (_memberAnswer(index: 0), 'no number'),
        (_memberAnswer(media: _media(id: 'someone')), 'media of another'),
        (_memberAnswer(media: _media(index: 102)), 'media of another number'),
        (_memberAnswer(media: 'live'), 'media is not an object'),
        (jsonEncode({'result': true}), 'no bjInfo'),
        (_refusal(null), 'refused without a code'),
      ]) {
        expect(() => PandaLiveApi.member(body, userId: 'fixture_101'), throwsA(isA<ApiChanged>()), reason: reason);
      }
    });

    test("the form is 3.x's (fan grades asked, never read)", () {
      final sent = (_outcome('S04-member-live', 'getRoomDetailForRefresh')['requests'] as List).single as Map;
      expect(PandaLiveApi.memberForm('daisy00'), sent['form']);
      expect(sent['referer'], PandaLiveApi.roomUrl('daisy00'));
    });

    test('fields 3.x refused (failing the room) are left empty or fall back', () {
      final member = PandaLiveApi.member(
        _memberAnswer(
          media: _media(changes: {'userNick': '', 'title': ' ', 'userImg': 'ftp://x', 'user': 'x'}),
          info: {'channelTitle': '', 'thumbUrl': 'https://evil.example/a.jpg', 'fanCnt': -1},
        ),
        userId: 'fixture_101',
      );
      final room = PandaLiveApi.refreshRoom(member);
      expect(room.nick, 'Fixture owner');
      expect(room.title, 'Fixture owner');
      expect(room.avatar, '');
      expect(room.onlineViewers, '');
      expect(room.followers, '9371', reason: 'media fanCnt');
      final bare = PandaLiveApi.member(
        _memberAnswer(info: {'nick': null, 'channelTitle': null, 'fanCnt': null}),
        userId: 'fixture_101',
      );
      final offline = PandaLiveApi.profileRoom(bare);
      expect([offline.nick, offline.title], ['fixture_101', 'fixture_101']);
      expect(offline.followers, '');
    });
  });

  group('S05 live/play', () {
    final member = _member('S04-member-live', 'daisy00');

    test("a live broadcast: its master, chat channel and token; the room is 3.x's entry", () {
      final fixture = _sample('S05-play-live');
      final play = PandaLiveApi.play(fixture.body, member: member, status: fixture.status);
      expect(play.isLive, isTrue);
      expect(play.code, isNull);
      expect(play.master?.host, 'ffdced10e5f6.us-west-2.playback.live-video.net');
      expect(play.master?.path, _sample('S06-master').url.path);
      expect(play.chatChannel, '24133575');
      expect(play.chatToken, isNotEmpty);
      final (:room, :unavailable) = PandaLiveApi.playRoom(member, play);
      expect(unavailable, isNull);
      for (final key in ['getRoomDetail', 'getRoomDetailForRecording']) {
        _expectParity(
          _projection(room),
          _value('S04-member-live', key)! as Map<String, dynamic>,
          changed: _headersMoved,
          reason: key,
        );
      }
      expect(room.onlineViewers, '47', reason: 'live/play media');
      final sent = (_outcome('S04-member-live', 'getRoomDetail')['requests'] as List).cast<Map<String, dynamic>>();
      expect(PandaLiveApi.playForm('daisy00'), sent[1]['form']);
      expect(PandaLiveApi.playForm('daisy00').keys, (sent[1]['form'] as Map).keys);
    });

    test('ended (HTTP 400 castEnd): offline room, StreamUnavailable (REG-PANDALIVE-001; 3.x: schema)', () {
      final fixture = _sample('S05-play-castend');
      expect(fixture.status, 400);
      expect(_value('S05-play-castend', 'getRoomDetail'), containsPair('message', 'PandaTV schema'));
      expect(_value('S05-play-castend', 'live/play'), containsPair('message', 'PandaTV schema'));
      final owner = PandaLiveApi.member(_syntheticMember('flffl369', 28103135, adult: false), userId: 'flffl369');
      final play = PandaLiveApi.play(fixture.body, member: owner, status: fixture.status);
      expect(play.code, 'castEnd');
      expect(play.isLive, isFalse);
      final (:room, :unavailable) = PandaLiveApi.playRoom(owner, play);
      expect(room.toJson(), PandaLiveApi.profileRoom(owner).toJson(), reason: "3.x's code: `_profileRoom`");
      expect(room.liveStatus, LiveStatus.offline);
      expect(unavailable, isA<StreamUnavailable>());
    });

    test('adult (HTTP 400 needAdult): live with the adult notice, NeedsLogin (3.x: schema)', () {
      final fixture = _sample('S05-play-needlogin');
      expect(fixture.status, 400);
      expect(_value('S05-play-needlogin', 'getRoomDetail'), containsPair('message', 'PandaTV schema'));
      final owner = PandaLiveApi.member(_syntheticMember('youngddo819', 1000001, adult: true), userId: 'youngddo819');
      final play = PandaLiveApi.play(fixture.body, member: owner, status: fixture.status);
      expect(play.code, 'needAdult');
      final (:room, :unavailable) = PandaLiveApi.playRoom(owner, play);
      expect(room.liveStatus, LiveStatus.live);
      expect(room.notice, PandaLiveApi.adultNotice);
      expect(room.toJson(), {
        ...PandaLiveApi.refreshRoom(owner).toJson(),
        'notice': PandaLiveApi.adultNotice,
      }, reason: "3.x's code: `_restrictedRoom` of the member/bj media");
      expect(unavailable, isA<NeedsLogin>());
    });

    test("the other refusals: 3.x's notices, and why the stream is missing", () {
      final owner = PandaLiveApi.member(_memberAnswer(media: _media()), userId: 'fixture_101');
      for (final (code, notice, matcher) in [
        ('needPassword', PandaLiveApi.passwordNotice, isA<StreamUnavailable>()),
        ('password', PandaLiveApi.passwordNotice, isA<StreamUnavailable>()),
        ('needLogin', PandaLiveApi.restrictedNotice, isA<NeedsLogin>()),
        ('fanOnly', PandaLiveApi.restrictedNotice, isA<StreamUnavailable>()),
        (null, PandaLiveApi.restrictedNotice, isA<StreamUnavailable>()),
      ]) {
        final play = PandaLiveApi.play(_refusal(code), member: owner, status: 400);
        expect(play.code, code ?? '');
        final (:room, :unavailable) = PandaLiveApi.playRoom(owner, play);
        expect(room.isLiveNow, isTrue, reason: '$code');
        expect(room.notice, notice, reason: '$code');
        expect(unavailable, matcher, reason: '$code');
      }
    });

    test('accepted but not live: the offline profile room; live without HLS: the room, StreamUnavailable', () {
      final owner = PandaLiveApi.member(_memberAnswer(media: _media()), userId: 'fixture_101');
      final ended = PandaLiveApi.play(
        _playAnswer(media: _media(changes: {'isLive': false})),
        member: owner,
      );
      expect(ended.master, isNull);
      final offline = PandaLiveApi.playRoom(owner, ended);
      expect(offline.room.toJson(), PandaLiveApi.profileRoom(owner).toJson());
      expect(offline.unavailable, isA<StreamUnavailable>());
      final whipOnly = PandaLiveApi.play(
        _playAnswer(
          playList: {
            'hls3': <Object?>[],
            'hls': [
              {'name': '자동', 'url': ''},
            ],
            'whip': [
              {'token': 'x'},
            ],
          },
        ),
        member: owner,
      );
      expect(whipOnly.master, isNull);
      final live = PandaLiveApi.playRoom(owner, whipOnly);
      expect(live.room.isLiveNow, isTrue);
      expect(live.room.cover, 'https://cdn.pandalive.co.kr/cover.jpg');
      expect(live.unavailable, isA<StreamUnavailable>());
    });

    test("the master is the first of hls3, hls2, hls (3.x's _firstMaster), and must be IVS", () {
      final owner = PandaLiveApi.member(_memberAnswer(media: _media()), userId: 'fixture_101');
      Uri? master(Object playList) => PandaLiveApi.play(_playAnswer(playList: playList), member: owner).master;
      const second = 'https://b.us-west-2.playback.live-video.net/api/video/v1/b.m3u8';
      expect(
        master({
          'hls': [
            {'url': _masterUrl},
          ],
          'hls2': [
            {'url': second},
          ],
        }),
        Uri.parse(second),
      );
      for (final (playList, reason) in [
        (
          {
            'hls3': [
              {'url': 'https://live-video.net.evil.test/a.m3u8'},
            ],
          },
          'lookalike host',
        ),
        (
          {
            'hls3': [
              {'url': 'https://a.live-video.net/a.mp4'},
            ],
          },
          'not a playlist',
        ),
        (
          {
            'hls3': [
              {'url': 'http://a.live-video.net/a.m3u8'},
            ],
          },
          'not https',
        ),
        ({'hls3': 'x'}, 'not a list'),
        (
          {
            'hls3': ['x'],
          },
          'not an object',
        ),
      ]) {
        expect(() => master(playList), throwsA(isA<ApiChanged>()), reason: reason);
      }
      expect(() => PandaLiveApi.play(_playAnswer(playList: 'x'), member: owner), throwsA(isA<ApiChanged>()));
    });

    test("an answer that is not the broadcaster's, or without a result flag, is ApiChanged", () {
      final owner = PandaLiveApi.member(_memberAnswer(media: _media()), userId: 'fixture_101');
      for (final body in [
        _playAnswer(media: _media(id: 'someone')),
        _playAnswer(media: _media(index: 9)),
        _playAnswer(changes: {'media': null}),
        _playAnswer(changes: {'result': null}),
        '',
      ]) {
        expect(() => PandaLiveApi.play(body, member: owner), throwsA(isA<ApiChanged>()), reason: body);
      }
      expect(() => PandaLiveApi.play('', member: owner, status: 400), throwsA(isA<ApiChanged>()));
    });
  });

  group('S06 IVS master', () {
    test("3.x's qualities: names, ids, ranks and variant URLs", () {
      final fixture = _sample('S06-master');
      final qualities = PandaLiveApi.qualities(
        fixture.body,
        master: fixture.url,
        userId: 'daisy00',
        issuedAt: fixture.capturedAt,
      );
      final legacy = _maps(_legacy('S06-master')['qualities']);
      expect(qualities.map((quality) => quality.quality), legacy.map((quality) => quality['quality']));
      expect(qualities.map((quality) => quality.id), legacy.map((quality) => quality['id']));
      expect(qualities.map((quality) => quality.sort), legacy.map((quality) => quality['sort']));
      expect(qualities.map((quality) => quality.quality), [
        '1080p30 · HLS',
        '720p30 · HLS',
        '480p30 · HLS',
        '360p30 · HLS',
        '160p30 · HLS',
      ]);
      final streams = _maps(_legacy('S06-master')['parseManifest']);
      expect(qualities.map((quality) => _line(quality).url), streams.map((stream) => stream['uri']));
    });

    test('each quality is one line: the variant with the media headers, HLS, its codec and lease', () {
      final fixture = _sample('S06-master');
      final qualities = PandaLiveApi.qualities(
        fixture.body,
        master: fixture.url,
        userId: 'daisy00',
        issuedAt: fixture.capturedAt,
      );
      final legacyHeaders = (_legacy('S04-member-live')['PandaLiveApi.mediaHeaders'] as Map).map(
        (key, value) => MapEntry('$key'.toLowerCase(), value),
      );
      for (final quality in qualities) {
        final line = _line(quality);
        expect(line.headers, legacyHeaders, reason: 'PlaybackHeaderResolver: PandaLiveApi.mediaHeaders(roomId)');
        expect(line.headers['origin'], 'https://www.pandalive.co.kr', reason: 'REG-PANDALIVE-003');
        expect(line.format, StreamFormat.hls);
        expect(line.codec, 'avc');
        expect(line.lineId, 'ivs');
        expect(line.lease?.refreshAt, fixture.capturedAt.add(const Duration(minutes: 30)), reason: 'REG-PANDALIVE-005');
        expect(line.lease?.expiresAt, isNull);
        expect(line.lease?.cutsConnection, isTrue);
        expect(Uri.parse(line.url).host, endsWith('.playlist.live-video.net'), reason: 'REG-PANDALIVE-002');
      }
    });

    test("3.x's naming: 60 from 50 fps, 30 from 25, none below; a repeated id gets _<n>; best first", () {
      final qualities = _qualities(
        _masterText([
          _variant('1280x720', bandwidth: 2000),
          _variant('1920x1080', bandwidth: 6000, frameRate: '60.000'),
          _variant('1280x720', bandwidth: 3000),
          _variant('640x360', bandwidth: 500, frameRate: '20.000'),
          _variant('1280x720', bandwidth: 2500, frameRate: '59.940'),
        ]),
      );
      expect(qualities.map((quality) => quality.id), ['1080p60', '720p60', '720p30_3', '720p30', '360p']);
      expect(qualities.map((quality) => quality.quality), [
        '1080p60 · HLS',
        '720p60 · HLS',
        '720p30 · HLS',
        '720p30 · HLS',
        '360p · HLS',
      ]);
      expect(qualities[2].sort, 720 * 10000000 + 3000);
    });

    test("3.x's site test master: 1080p60, 720p60, 480p30", () {
      final qualities = _qualities(
        _masterText([
          '#EXT-X-STREAM-INF:BANDWIDTH=8659202,RESOLUTION=1920x1080,FRAME-RATE=60.000',
          'https://fixture.playlist.live-video.net/1080.m3u8',
          '#EXT-X-STREAM-INF:BANDWIDTH=3422999,RESOLUTION=1280x720,FRAME-RATE=60.000',
          'https://fixture.playlist.live-video.net/720.m3u8',
          '#EXT-X-STREAM-INF:BANDWIDTH=1427999,RESOLUTION=852x480,FRAME-RATE=30.000',
          'https://fixture.playlist.live-video.net/480.m3u8',
        ]),
      );
      expect(qualities.map((quality) => quality.id), ['1080p60', '720p60', '480p30']);
      expect(_line(qualities[1]).url, contains('/720.m3u8'));
      expect(_line(qualities.first).codec, isNull, reason: 'no CODECS');
    });

    test('relative variants resolve against the master; HEVC is named', () {
      final qualities = _qualities(_masterText([_variant('1920x1080', uri: 'v/1080.m3u8', codecs: 'hvc1.1.6.L120')]));
      expect(_line(qualities.single).url, 'https://fixture.us-west-2.playback.live-video.net/api/video/v1/v/1080.m3u8');
      expect(_line(qualities.single).codec, 'hevc');
    });

    test('a variant without a resolution (audio only) is left out (3.x failed the room); none left is '
        'StreamUnavailable', () {
      final qualities = _qualities(
        _masterText([
          '#EXT-X-STREAM-INF:BANDWIDTH=160000,CODECS="mp4a.40.2"',
          'https://fixture.playlist.live-video.net/audio.m3u8',
          _variant('1280x720'),
        ]),
      );
      expect(qualities.map((quality) => quality.id), ['720p30']);
      expect(
        () => _qualities(
          _masterText(['#EXT-X-STREAM-INF:BANDWIDTH=1,CODECS="mp4a.40.2"', 'https://a.playlist.live-video.net/a.m3u8']),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(() => _qualities(_masterText([])), throwsA(isA<StreamUnavailable>()));
    });

    test("what 3.x refused is ApiChanged: lookalike hosts (3.x's test), not a master, a variant without URI", () {
      for (final (text, reason) in [
        (
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1280x720\nhttps://live-video.net.evil.test/720.m3u8\n',
          'lookalike media host',
        ),
        (_masterText([_variant('1280x720', uri: 'https://a.live-video.net/720.ts')]), 'not a playlist'),
        ('<html>', 'not a master'),
        (_masterText(['#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1280x720']), 'no URI'),
        (_masterText(['#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1280x720', '#EXT-X-ENDLIST']), 'a tag for URI'),
        (_masterText([_variant('1280x720', frameRate: '300')]), 'frame rate'),
        (_masterText([_variant('1280x720', bandwidth: -1)]), 'bandwidth'),
      ]) {
        expect(() => _qualities(text), throwsA(isA<ApiChanged>()), reason: reason);
      }
      expect(
        () => _qualities(_masterText([_variant('1280x720')]), master: 'https://example.com/a.m3u8'),
        throwsA(isA<ApiChanged>()),
        reason: 'the master itself',
      );
    });

    test('master answers: 404 StreamUnavailable, a second read 403 RiskControl (REG-PANDALIVE-002)', () {
      expect(PandaLiveApi.master('#EXTM3U'), '#EXTM3U');
      for (final (status, matcher) in [
        (404, isA<StreamUnavailable>()),
        (403, isA<RiskControl>()),
        (401, isA<RiskControl>()),
        (400, isA<ApiChanged>()),
        (429, isA<RateLimited>()),
        (500, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
      ]) {
        expect(() => PandaLiveApi.master('', status: status), throwsA(matcher), reason: '$status');
      }
      expect(
        () => PandaLiveApi.master('#' * (PandaLiveApi.manifestLimit + 1)),
        throwsA(isA<ApiChanged>()),
        reason: "3.x's 1 MiB",
      );
    });

    test('resolution: the line of the quality asked, applied as asked; else why not', () {
      final qualities = _qualities(_masterText([_variant('1920x1080'), _variant('1280x720')]));
      final data = PandaLiveRoomData(userId: 'fixture_101', userIndex: 101, qualities: qualities);
      final resolution = PandaLiveApi.resolution(data, const LivePlayQuality(quality: 'x', id: '720p30'));
      expect(resolution.appliedQualityData, '720p30');
      expect(resolution.urls, [_line(qualities[1]).url]);
      expect(resolution.lines.single.headers, PandaLiveApi.mediaHeaders('fixture_101'));
      expect(
        () => PandaLiveApi.resolution(data, const LivePlayQuality(quality: 'x', id: '480p30')),
        throwsA(isA<StreamUnavailable>()),
      );
      final adult = PandaLiveRoomData(userId: 'a', userIndex: 1, unavailable: const NeedsLogin('pandalive'));
      expect(() => PandaLiveApi.playQualities(adult), throwsA(isA<NeedsLogin>()));
    });
  });

  group('answers', () {
    test("statuses as 3.x's _read classed them, except that 400 is read (REG-PANDALIVE-001)", () {
      for (final (status, matcher) in [
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (500, isA<NetworkFailure>()),
        (503, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
      ]) {
        expect(
          () => PandaLiveApi.answer('', what: 'x', status: status),
          throwsA(matcher),
          reason: '$status',
        );
      }
      expect(PandaLiveApi.statusError(200, 'x'), isNull);
      expect(PandaLiveApi.statusError(400, 'x'), isNull);
      expect(() => PandaLiveApi.answer('', what: 'x', status: 400), throwsA(isA<ApiChanged>()));
      expect(
        () => PandaLiveApi.answer('{"result":true,"x":"${'a' * PandaLiveApi.responseLimit}"}', what: 'x'),
        throwsA(isA<ApiChanged>()),
        reason: "3.x's 4 MiB",
      );
    });

    test('refusals by code and message', () {
      Map<String, dynamic> refused(String? code, {String message = 'x'}) =>
          jsonDecode(_refusal(code, message: message)) as Map<String, dynamic>;
      for (final (code, matcher) in [
        ('castEnd', isA<StreamUnavailable>()),
        ('needAdult', isA<NeedsLogin>()),
        ('needLogin', isA<NeedsLogin>()),
        ('needPassword', isA<StreamUnavailable>()),
        ('other', isA<StreamUnavailable>()),
        (null, isA<ApiChanged>()),
      ]) {
        expect(PandaLiveApi.refusal(refused(code), what: 'x'), matcher, reason: '$code');
      }
      expect(PandaLiveApi.refusal(refused(null, message: '유저 정보가 없습니다.'), what: 'x'), isA<NotFound>());
      expect(PandaLiveApi.refusalCode(refused('castEnd')), 'castEnd');
      expect(PandaLiveApi.refusalCode({'errorData': 'x'}), '');
    });

    test('flags as 3.x read them; anything else is not a flag (3.x: schema)', () {
      expect([true, 'Y', 'y', 1].map(PandaLiveApi.flag), everyElement(isTrue));
      expect([false, 'N', 'n', 0].map(PandaLiveApi.flag), everyElement(isFalse));
      expect([null, 'yes', 2, <Object?>[]].map(PandaLiveApi.flag), everyElement(isNull));
    });

    test('images: https on a pandalive.co.kr subdomain (3.x); else empty (3.x: schema)', () {
      expect(PandaLiveApi.image(' https://cdn.pandalive.co.kr/a.jpg '), 'https://cdn.pandalive.co.kr/a.jpg');
      for (final value in [
        'http://cdn.pandalive.co.kr/a.jpg',
        'https://pandalive.co.kr/a.jpg',
        'https://evilpandalive.co.kr/a.jpg',
        'https://cdn.pandalive.co.kr.evil.test/a.jpg',
        'https://user@cdn.pandalive.co.kr/a.jpg',
        '//cdn.pandalive.co.kr/a.jpg',
        '',
        null,
        7,
      ]) {
        expect(PandaLiveApi.image(value), '', reason: '$value');
      }
    });
  });

  group('links', () {
    test("3.x's link rule on every vector; /play/<id> is now a room (3.x: not a link)", () {
      final legacy = (_legacy('S04-member-live')['PandaLiveLink.parse'] as Map).cast<String, Object?>();
      const changed = {
        // The website's live page; 3.x's /live/play/<id> redirects there.
        'https://www.pandalive.co.kr/play/daisy00': 'daisy00',
        'https://m.pandalive.co.kr/play/daisy00': 'daisy00',
      };
      for (final MapEntry(key: url, value: id) in legacy.entries) {
        expect(PandaLiveApi.roomIdFromUrl(url), changed[url] ?? id, reason: url);
      }
      expect(legacy['https://www.pandalive.co.kr/play/daisy00'], isNull);
    });

    test('a path that does not decode is not a link (3.x threw)', () {
      expect(PandaLiveApi.roomIdFromUrl('https://www.pandalive.co.kr/live/play/%FF'), isNull);
      expect(PandaLiveApi.roomIdFromUrl('https://www.pandalive.co.kr/channel/%E0%A4%A'), isNull);
    });

    test("ids, the room page and the media headers are 3.x's", () {
      final legacy = _legacy('S04-member-live');
      final ids = (legacy['PandaLiveLink.parseOrId'] as Map).cast<String, Object?>();
      for (final MapEntry(key: text, value: id) in ids.entries) {
        expect(PandaLiveApi.roomIdFromUrl(text.trim()) ?? PandaLiveApi.normalizeUserId(text), id, reason: text);
      }
      expect(PandaLiveApi.normalizeUserId('name@ka/evil'), isNull);
      expect(PandaLiveApi.normalizeUserId('a' * 65), isNull);
      expect(PandaLiveApi.normalizeUserId(7), isNull);
      expect(PandaLiveApi.roomUrl('daisy00'), legacy['PandaLiveLink.url']);
      expect(PandaLiveApi.roomUrl('1506087545@ka'), contains('1506087545'));
      expect(
        PandaLiveApi.mediaHeaders('daisy00'),
        (legacy['PandaLiveApi.mediaHeaders'] as Map).map((key, value) => MapEntry('$key'.toLowerCase(), value)),
      );
    });
  });
}
