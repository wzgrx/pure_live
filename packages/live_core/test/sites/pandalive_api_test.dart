// PandaTV parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/pandalive/legacy_expected.dart from 3.x's PandaLiveApi,
// PandaLiveLink and PandaLiveSite). Every intended difference is listed
// with its reason (an M4.U item number of docs/specs/UPGRADES.md for the approved
// upgrades); everything else must match. The synthetic cases port 3.x's
// pandalive_site_test.dart and pandalive_native_search_test.dart (the
// parsing parts) and cover the regression entries of the archived spec
// (REG-PANDALIVE-001–005) and the shapes 3.x refused.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('pandalive', name);

/// Keys 3.x never wrote: M2.1's, and `totalViewers` (25-3; 3.x's rooms had
/// no cumulative audience). [_expectParity] checks them apart.
const _newKeys = ['startedAt', 'restriction', 'totalViewers'];

/// Asserts that [actual] (a `toJson`) equals 3.x's [legacy] map on every key
/// 3.x wrote, except [changed] (intended differences), and that the new
/// keys are exactly [added]. 3.x wrote null where the immutable model
/// writes ''.
void _expectParity(
  Map<String, Object?> actual,
  Map<String, dynamic> legacy, {
  Set<String> changed = const {},
  Map<String, Object?> added = const {},
  String? reason,
}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (changed.contains(key)) continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
  for (final key in _newKeys) {
    expect(actual[key] ?? '', added[key] ?? '', reason: '${reason ?? ''} $key (new key)');
  }
}

/// 3.x's room projection: toJson plus `link`.
Map<String, Object?> _projection(LiveRoom room) => {...room.toJson(), 'link': room.link};

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

/// The outcome of a counted legacy call (`{requests, value}`).
Map<String, dynamic> _outcome(String name, String key) => _legacy(name)[key] as Map<String, dynamic>;

Object? _value(String name, String key) => _outcome(name, key)['value'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

/// The rows of a paged sample.
List<Map<String, dynamic>> _rows(String sample) =>
    ((jsonDecode(_sample(sample).body) as Map)['list'] as List).cast<Map<String, dynamic>>();

/// `startTime` read as Korean time, independently of the parser (25-12).
String _kst(Object? startTime) =>
    DateTime.parse('${(startTime! as String).replaceFirst(' ', 'T')}+09:00').toUtc().toIso8601String();

/// What every room 3.x wrote changes: its link (25-4), its notice (25-7:
/// all four notices are rewritten for users) and `httpHeaders` (3.x put
/// the media headers on every room, where only IPTV's are read; they now
/// travel on every line, M4.25).
const _roomChanged = {'httpHeaders', 'link', 'notice'};

/// What a live broadcast's room changes besides [_roomChanged]: its area,
/// the category's name (25-8).
const Set<String> _liveChanged = {..._roomChanged, 'area'};

/// What a live card of `live/index` changes besides [_liveChanged]: its
/// userId, the broadcaster's number (25-10; 3.x wrote the login id).
const Set<String> _cardChanged = {..._liveChanged, 'userId'};

/// What a rerun's room changes besides the rest: its state, a replay (the
/// unified rule on replays and reruns, as Twitch's 8-9; 3.x: live).
const _rerunChanged = {'liveStatus', 'isRecord', 'status'};

/// [_cardChanged] for the card of [row], with [_rerunChanged] for a rerun.
Set<String> _cardChangedFor(Map<String, dynamic> row) => {
  ..._cardChanged,
  if (row['onAirType'] == 'rec') ..._rerunChanged,
};

/// The new keys of a live broadcast [media] (a `live/index` row or
/// `media`): its start (25-12), cumulative viewers (25-3) and restriction
/// (the recorded ones are all free: none).
Map<String, Object?> _liveAdded(Map<String, dynamic> media) => {
  'startedAt': _kst(media['startTime']),
  'totalViewers': '${media['playCnt']}',
  'restriction': 'none',
};

/// Asserts the new values of [_cardChanged] on the card of [row].
void _expectCardChanges(LiveRoom room, Map<String, dynamic> row, {String? reason}) {
  expect(room.userId, '${row['userIdx']}', reason: '$reason userId (25-10)');
  expect(room.area, PandaLiveApi.areaNames[row['category']], reason: '$reason area (25-8)');
  expect(room.link, 'https://www.pandalive.co.kr/play/${row['userId']}', reason: '$reason link (25-4)');
  expect(room.notice, PandaLiveApi.chatNotice, reason: '$reason notice (25-7)');
  final rerun = row['onAirType'] == 'rec';
  expect(room.liveStatus, rerun ? LiveStatus.replay : LiveStatus.live, reason: '$reason rerun');
  expect(room.followGroup, rerun ? FollowGroup.replay : FollowGroup.live, reason: '$reason rerun');
  expect(room.isPlayableNow, isTrue, reason: '$reason rerun');
}

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
  String? video,
}) => [
  '#EXT-X-STREAM-INF:BANDWIDTH=$bandwidth,RESOLUTION=$resolution,CODECS="${codecs ?? 'avc1.4D401F,mp4a.40.2'}"${video == null ? '' : ',VIDEO="$video"'},FRAME-RATE=$frameRate',
  uri ?? 'https://fixture.playlist.live-video.net/v1/playlist/$resolution-$bandwidth.m3u8',
].join('\n');

final DateTime _issuedAt = DateTime.utc(2026, 9, 27, 18, 50);

List<LivePlayQuality> _qualities(String text, {String master = _masterUrl, String userId = 'fixture_101'}) =>
    PandaLiveApi.qualities(text, master: Uri.parse(master), userId: userId, issuedAt: _issuedAt);

LivePlayLine _line(LivePlayQuality quality) => (quality.data! as List<LivePlayLine>).single;

void main() {
  group('catalog', () {
    test("3.x's public area, and the new broadcasters after it (25-1)", () {
      final legacy = _maps(_value('S01-index-hot', 'getCategores(1)'));
      final categories = PandaLiveApi.categories();
      expect(categories.map((category) => category.id), legacy.map((category) => category['id']));
      expect(categories.map((category) => category.name), legacy.map((category) => category['name']));
      final areas = _maps(legacy.single['children']);
      expect(areas, hasLength(1));
      final [public, newcomers] = categories.single.children;
      _expectParity(public.toJson(), areas.single);
      expect(public.areaName, '公开直播');
      expect(newcomers.toJson(), {
        ...public.toJson(),
        'areaId': PandaLiveApi.newBroadcasterAreaId,
        'areaName': PandaLiveApi.newBroadcasterAreaName,
      });
      expect([newcomers.areaId, newcomers.areaName], ['newbj', '新人主播']);
      expect(_value('S01-index-hot', 'getCategores(2)'), 0);
      expect(_legacy('S01-index-hot')['directoryNoticeKey'], 'pandalive_directory_scope');
      expect(_legacy('S01-index-hot')['name'], PandaLiveApi.categoryName);
    });

    test('checkArea: null or one of the two areas, by id; anything else is a caller error (3.x: identity)', () {
      final [public, newcomers] = PandaLiveApi.categories().single.children;
      expect(PandaLiveApi.checkArea(null), 'public');
      expect(PandaLiveApi.checkArea(public), 'public');
      expect(PandaLiveApi.checkArea(newcomers), 'newbj');
      expect(
        PandaLiveApi.checkArea(
          LiveArea.fromJson(_maps(_maps(_value('S01-index-hot', 'getCategores(1)')).single['children']).single),
        ),
        'public',
        reason: 'the area 3.x stored',
      );
      expect(_value('S01-index-hot', 'getDirectoryPage(1, other area)'), containsPair('message', 'PandaTV identity'));
      for (final area in [
        const LiveArea(platform: 'pandalive', areaType: 'directory', areaId: 'hot'),
        const LiveArea(platform: 'pandalive', areaType: 'category', areaId: 'public'),
        const LiveArea(platform: 'chzzk', areaType: 'directory', areaId: 'newbj'),
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

    test('the directory notice is written for users (25-7)', () {
      for (final text in ['offset', 'BJ', '原生', '/']) {
        expect(PandaLiveApi.directoryScope, isNot(contains(text)), reason: text);
      }
      expect(PandaLiveApi.directoryScope, contains('新人主播'));
    });
  });

  group('S01 public directory', () {
    test('page 1: the same 30 rooms, fields and "more" as 3.x, with the upgrades', () {
      final fixture = _sample('S01-index-hot');
      final legacy = _value('S01-index-hot', 'getDirectoryPage(1)')! as Map<String, dynamic>;
      final page = PandaLiveApi.livePage(fixture.body, page: 1, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      final rows = _rows('S01-index-hot');
      expect(page.rooms, hasLength(30));
      expect(page.rooms.map((room) => room.roomId), rooms.map((room) => room['roomId']));
      for (final (index, room) in page.rooms.indexed) {
        _expectParity(
          _projection(room),
          rooms[index],
          changed: _cardChangedFor(rows[index]),
          added: _liveAdded(rows[index]),
          reason: 'p1[$index]',
        );
        _expectCardChanges(room, rows[index], reason: 'p1[$index]');
        expect(room.httpHeaders, isEmpty);
      }
      expect(page.hasMore, legacy['hasMore']);
      expect(page.page, 1);
      for (final key in ['getRecommendRooms(1)', 'getCategoryRooms(1)']) {
        expect(_maps(_value('S01-index-hot', key)).map((room) => room['roomId']), rooms.map((room) => room['roomId']));
      }
    });

    test('the last page (offset 120 of 128): the same 8 rooms, no more', () {
      final fixture = _sample('S01-index-hot-last');
      final legacy = _value('S01-index-hot-last', 'getDirectoryPage(5)')! as Map<String, dynamic>;
      final page = PandaLiveApi.livePage(fixture.body, page: 5, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      final rows = _rows('S01-index-hot-last');
      expect(page.rooms, hasLength(8));
      for (final (index, room) in page.rooms.indexed) {
        _expectParity(
          _projection(room),
          rooms[index],
          changed: _cardChangedFor(rows[index]),
          added: _liveAdded(rows[index]),
          reason: 'p5[$index]',
        );
        _expectCardChanges(room, rows[index], reason: 'p5[$index]');
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

    test("cards: 3.x's live card rules (ported from pandalive_site_test's directory case), with the upgrades", () {
      final page = PandaLiveApi.livePage(_page([_media()], page: 2, total: 61), page: 2);
      final room = page.rooms.single;
      expect(page.hasMore, isTrue);
      expect(room.roomId, 'fixture_101');
      expect(room.userId, '101', reason: '25-10: the number, as details (3.x: the id)');
      expect(room.onlineViewers, '127');
      expect(room.totalViewers, '900', reason: '25-3: playCnt');
      expect(room.followers, '9371');
      expect(room.effectiveAudienceMetricType, AudienceMetricType.onlineViewers);
      expect(room.cover, 'https://cdn.pandalive.co.kr/cover.jpg');
      expect(room.area, '聊天', reason: '25-8: talk');
      expect(room.notice, PandaLiveApi.chatNotice);
      expect(room.link, 'https://www.pandalive.co.kr/play/fixture_101');
      expect(room.startedAt, isNull, reason: 'no startTime');
      expect(room.restriction, isNull, reason: 'no type: not known');
    });

    test('cards: the restriction of the flags and its notice; the cover falls back on ivsThumbnail only when '
        'thumbUrl is absent', () {
      LiveRoom card(Map<String, Object?> changes) => PandaLiveApi.liveCard(_media(changes: changes))!;
      for (final (changes, restriction, notice) in [
        ({'isAdult': true, 'isPw': true, 'type': 'fan'}, LiveRestriction.adult, PandaLiveApi.adultNotice),
        ({'isAdult': 'N', 'isPw': 'Y', 'type': 'fan'}, LiveRestriction.password, PandaLiveApi.passwordNotice),
        ({'isAdult': 0, 'isPw': 0, 'type': 'fan'}, LiveRestriction.subscribersOnly, PandaLiveApi.fansNotice),
        ({'type': 'free'}, LiveRestriction.none, PandaLiveApi.chatNotice),
        ({'type': 'vip'}, null, PandaLiveApi.chatNotice),
        ({'isAdult': 'maybe'}, null, PandaLiveApi.chatNotice),
      ]) {
        final room = card(changes);
        expect(room.restriction, restriction, reason: '$changes');
        expect(room.notice, notice, reason: '$changes');
        expect(room.isLiveNow, isTrue, reason: '$changes: a restricted broadcast is live');
      }
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
              'playCnt': 'many',
              'fanCnt': 'many',
              'isAdult': 'maybe',
              'userIdx': 0,
              'startTime': '0000-00-00 00:00:00',
            },
          ),
          _media(id: 'Odd'),
        ]),
        page: 1,
      );
      expect(page.rooms.map((room) => room.roomId), ['untitled', 'odd'], reason: 'a broadcaster once, without case');
      final untitled = page.rooms.first;
      expect(untitled.nick, '', reason: 'the unified rule on placeholders (M4.25 wrote the id)');
      expect(untitled.title, '');
      expect(untitled.displayNick('PandaTV'), 'PandaTV');
      final odd = page.rooms.last;
      expect([
        odd.avatar,
        odd.cover,
        odd.area,
        odd.onlineViewers,
        odd.totalViewers,
        odd.followers,
        odd.userId,
      ], everyElement(''));
      expect(odd.startedAt, isNull);
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

  group('S02 new broadcasters (25-1)', () {
    test("the website's form (onlyNewBj=Y) and its 7 live cards, parsed as the public directory's", () {
      final fixture = _sample('S02-index-newbj');
      final sent = Uri.splitQueryString((fixture.meta['request'] as Map)['body'] as String);
      final form = PandaLiveApi.directoryForm(1, areaId: PandaLiveApi.newBroadcasterAreaId);
      expect(form, sent);
      expect(form.keys, sent.keys, reason: 'field order');
      final page = PandaLiveApi.livePage(fixture.body, page: 1, status: fixture.status);
      final rows = _rows('S02-index-newbj');
      expect(rows.map((row) => row['newBjYN']), everyElement('Y'));
      expect(page.rooms.map((room) => room.roomId), rows.map((row) => row['userId']));
      expect(page.hasMore, isFalse);
      for (final (index, room) in page.rooms.indexed) {
        final row = rows[index];
        _expectCardChanges(room, row, reason: '[$index]');
        expect(room.startedAt?.toIso8601String(), _kst(row['startTime']));
        expect(room.totalViewers, '${row['playCnt']}');
        expect(room.onlineViewers, '${row['user']}');
        expect(room.restriction, LiveRestriction.none);
      }
    });
  });

  group('reruns (the unified rule on replays and reruns)', () {
    test('the recorded reruns: rec on both fields, a [녹] title; replays, playable, in the replay group', () {
      for (final (sample, count, total) in [('S01-index-hot', 5, 30), ('S02-index-newbj', 2, 7)]) {
        final rows = _rows(sample);
        final reruns = rows.where(PandaLiveApi.isRerun).toList();
        expect([reruns.length, rows.length], [count, total], reason: sample);
        for (final row in reruns) {
          expect([row['onAirType'], row['liveType']], ['rec', 'rec'], reason: '${row['userId']}');
          expect(row['title'], startsWith('[녹]'), reason: '${row['userId']}');
        }
        final fixture = _sample(sample);
        final page = PandaLiveApi.livePage(fixture.body, page: 1, status: fixture.status);
        final replays = page.rooms.where((room) => room.liveStatus == LiveStatus.replay);
        expect(replays.map((room) => room.roomId), reruns.map((row) => row['userId']), reason: sample);
        for (final room in replays) {
          expect(room.isRecord, isTrue);
          expect(room.isLiveNow, isFalse);
          expect(room.isPlayableNow, isTrue);
          expect(room.followGroup, FollowGroup.replay);
          expect(room.toJson(), containsPair('liveStatus', LiveStatus.replay.index));
        }
      }
    });

    test('either field says it; a rerun keeps its audience, start, restriction and notice', () {
      for (final changes in [
        {'onAirType': 'rec', 'liveType': 'rec'},
        {'onAirType': 'rec'},
        {'liveType': 'rec'},
      ]) {
        final card = PandaLiveApi.liveCard(
          _media(changes: {...changes, 'startTime': '2026-09-28 20:00:00', 'type': 'free', 'isPw': true}),
        )!;
        expect(card.liveStatus, LiveStatus.replay, reason: '$changes');
        expect([card.onlineViewers, card.totalViewers], ['127', '900'], reason: '$changes');
        expect(card.startedAt, DateTime.utc(2026, 9, 28, 11), reason: '$changes');
        expect(card.restriction, LiveRestriction.password, reason: '$changes');
        expect(card.notice, PandaLiveApi.passwordNotice, reason: '$changes');
      }
      for (final changes in [
        {'onAirType': 'live', 'liveType': 'live'},
        {'onAirType': 'REC'},
        const <String, Object?>{},
      ]) {
        expect(PandaLiveApi.liveCard(_media(changes: changes))!.liveStatus, LiveStatus.live, reason: '$changes');
      }
      expect(
        PandaLiveApi.liveCard(_media(changes: {'onAirType': 'rec', 'isLive': false})),
        isNull,
        reason: 'only on-air rows are cards',
      );
    });

    test('the BJ search, the refresh and room entry (accepted or refused) say replay too', () {
      const rec = {'onAirType': 'rec', 'liveType': 'rec'};
      final row = PandaLiveApi.profileCard(
        _broadcaster(
          id: 'fixture_101',
          index: 101,
          media: _media(changes: rec),
        ),
      )!;
      expect(row.liveStatus, LiveStatus.replay);
      expect(row.totalViewers, '900');
      final ended = PandaLiveApi.profileCard(
        _broadcaster(
          id: 'fixture_101',
          index: 101,
          media: _media(changes: {...rec, 'isLive': false}),
        ),
      )!;
      expect(ended.liveStatus, LiveStatus.offline);
      final member = PandaLiveApi.member(
        _memberAnswer(media: _media(changes: rec)),
        userId: 'fixture_101',
      );
      expect(PandaLiveApi.listedLive(member), isTrue);
      expect(PandaLiveApi.refreshRoom(member).liveStatus, LiveStatus.replay);
      final accepted = PandaLiveApi.playRoom(
        member,
        PandaLiveApi.play(
          _playAnswer(media: _media(changes: rec)),
          member: member,
        ),
      );
      expect(accepted.room.liveStatus, LiveStatus.replay);
      expect(accepted.room.restriction, LiveRestriction.none);
      expect(accepted.unavailable, isNull, reason: 'it plays like a live broadcast');
      final refused = PandaLiveApi.playRoom(
        member,
        PandaLiveApi.play(_refusal('needAdult'), member: member, status: 400),
      );
      expect(refused.room.liveStatus, LiveStatus.replay);
      expect(refused.room.restriction, LiveRestriction.adult);
      expect(refused.unavailable, isA<NeedsLogin>());
      final live = PandaLiveApi.member(_memberAnswer(media: _media()), userId: 'fixture_101');
      expect(PandaLiveApi.refreshRoom(live).liveStatus, LiveStatus.live);
    });
  });

  group('upgrades of the cards', () {
    test('startTime is Korean time (25-12, REG-PANDALIVE-004)', () {
      expect(PandaLiveApi.koreanTime('2026-09-28 02:00:35'), DateTime.utc(2026, 9, 27, 17, 0, 35));
      expect(PandaLiveApi.koreanTime(' 2026-01-01 08:59:59 '), DateTime.utc(2025, 12, 31, 23, 59, 59));
      for (final value in [
        '0000-00-00 00:00:00',
        '2026-02-30 10:00:00',
        '2026-09-28 24:00:00',
        '2026-09-28 10:60:00',
        '2026-09-28T02:00:35',
        '2026-09-28 02:00',
        '1999-12-31 12:00:00',
        '',
        null,
        1790535014,
      ]) {
        expect(PandaLiveApi.koreanTime(value), isNull, reason: '$value');
      }
      final fixture = _sample('S01-index-hot');
      final newest = _rows('S01-index-hot')
          .map((row) => PandaLiveApi.koreanTime(row['startTime'])!)
          .reduce((left, right) => left.isAfter(right) ? left : right);
      expect(newest.isBefore(fixture.capturedAt), isTrue, reason: 'read as UTC, starts would lie in the future');
      expect(fixture.capturedAt.difference(newest), lessThan(const Duration(hours: 1)));
    });

    test('category codes are named (25-8); an unknown code is shown as sent', () {
      expect(
        {
          for (final code in ['ind', 'talk', 'music', 'game', 'sports', 'etc']) code: PandaLiveApi.areaNameOf(code),
        },
        {'ind': '个人直播', 'talk': '聊天', 'music': '音乐', 'game': '游戏', 'sports': '体育', 'etc': '其他'},
      );
      expect(PandaLiveApi.areaNameOf(' IND '), '个人直播');
      expect(PandaLiveApi.areaNameOf('cook'), 'cook');
      expect(PandaLiveApi.areaNameOf(null), '');
      final codes = {
        for (final sample in ['S01-index-hot', 'S01-index-hot-last', 'S02-index-newbj', 'S03-search-live'])
          for (final row in _rows(sample)) row['category'],
      };
      expect(PandaLiveApi.areaNames.keys, containsAll(codes), reason: 'every recorded code has a name');
    });

    test('the notices are written for users (25-7); 3.x spoke of fields and a pending chat', () {
      for (final notice in [
        PandaLiveApi.chatNotice,
        PandaLiveApi.adultNotice,
        PandaLiveApi.passwordNotice,
        PandaLiveApi.fansNotice,
        PandaLiveApi.restrictedNotice,
      ]) {
        for (final text in ['user 字段', 'playCnt', '尚待接入']) {
          expect(notice, isNot(contains(text)), reason: '$notice: $text');
        }
      }
      expect(PandaLiveApi.chatNotice, contains('累计'), reason: '25-3');
    });

    test('the cumulative audience is a PandaTV metric now (25-3)', () {
      final capability = AudiencePlatformCapability.of('pandalive');
      expect((capability.hasPopularity, capability.hasTotalViewers), (false, true));
      expect(capability.onlineAvailableInRoomLists, isTrue);
      final card = PandaLiveApi.liveCard(_media())!;
      expect(card.audienceValue(preferRealOnline: false, platformEnabled: false), '900');
      expect(card.audienceType(preferRealOnline: false, platformEnabled: false), AudienceMetricType.totalViewers);
      expect(card.audienceValue(preferRealOnline: true, platformEnabled: true), '127');
    });
  });

  group('S03 search', () {
    test('LIVE search (20 a page): the same 2 live cards as 3.x, with the upgrades', () {
      final fixture = _sample('S03-search-live');
      final legacy = _value('S03-search-live', 'searchLive')! as Map<String, dynamic>;
      final page = PandaLiveApi.livePage(fixture.body, page: 1, size: 20, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      final rows = _rows('S03-search-live');
      expect(page.rooms.map((room) => room.roomId), ['daisy00', 'chirch']);
      for (final (index, room) in page.rooms.indexed) {
        _expectParity(
          _projection(room),
          rooms[index],
          changed: _cardChangedFor(rows[index]),
          added: _liveAdded(rows[index]),
          reason: 'live[$index]',
        );
        _expectCardChanges(room, rows[index], reason: 'live[$index]');
      }
      expect(page.hasMore, legacy['hasMore']);
    });

    test('BJ search (20 a page): the same 4 broadcasters as 3.x, live and offline, userId their number', () {
      final fixture = _sample('S03-search-bj');
      final legacy = _value('S03-search-bj', 'searchBroadcasters')! as Map<String, dynamic>;
      final page = PandaLiveApi.broadcasterPage(fixture.body, page: 1, size: 20, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      final rows = _rows('S03-search-bj');
      expect(page.rooms.map((room) => room.roomId), ['daisy00', 'flffl369', 'hhd006', 'candygirl35']);
      for (final (index, room) in page.rooms.indexed) {
        final media = rows[index]['media'] as Map<String, dynamic>?;
        _expectParity(
          _projection(room),
          rooms[index],
          changed: media == null ? _roomChanged : _liveChanged,
          added: media == null ? const {} : _liveAdded(media),
          reason: 'bj[$index]',
        );
        expect(room.link, PandaLiveApi.roomUrl(room.roomId));
        expect(room.notice, PandaLiveApi.chatNotice);
      }
      expect(page.rooms.first.isLiveNow, isTrue);
      expect(page.rooms.first.userId, '24133575');
      expect(page.rooms.first.area, '个人直播');
      expect(page.rooms.skip(1).map((room) => room.liveStatus), everyElement(LiveStatus.offline));
      expect(page.hasMore, legacy['hasMore']);
    });

    test("the forms are 3.x's", () {
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
            media: _media(id: 'gaoninc', changes: {'startTime': '2026-09-28 20:00:00', 'type': 'free'}),
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
            media: _media(
              id: 'ended',
              index: 9,
              changes: {'isLive': false, 'isAdult': true, 'startTime': '2026-09-28 20:00:00'},
            ),
          ),
        ], size: 11),
        page: 1,
        size: 11,
      );
      expect(page.rooms.map((room) => room.roomId), ['gaoninc', '1506087545@ka', 'unknown', 'ended']);
      final [live, offline, unknown, ended] = page.rooms;
      expect(live.liveStatus, LiveStatus.live);
      expect(live.onlineViewers, '127');
      expect(live.totalViewers, '900');
      expect(live.startedAt, DateTime.utc(2026, 9, 28, 11));
      expect(live.restriction, LiveRestriction.none);
      expect(live.title, 'Fixture live');
      expect(live.userId, '101');
      expect(offline.liveStatus, LiveStatus.offline);
      expect(offline.onlineViewers, '');
      expect(offline.title, '가온主播');
      expect(offline.cover, '');
      expect(offline.link, 'https://www.pandalive.co.kr/play/1506087545@ka');
      expect(unknown.liveStatus, LiveStatus.unknown);
      expect([unknown.onlineViewers, unknown.totalViewers], ['', '']);
      expect(unknown.restriction, isNull, reason: 'only a live broadcast has one');
      expect(unknown.notice, PandaLiveApi.passwordNotice);
      expect(ended.liveStatus, LiveStatus.offline);
      expect(ended.startedAt, isNull, reason: 'not live');
      expect(ended.restriction, isNull);
      expect(ended.notice, PandaLiveApi.adultNotice);
      expect(page.hasMore, isFalse);
    });

    test('an empty nick stays empty (the unified rule on placeholders)', () {
      final page = PandaLiveApi.broadcasterPage(
        _page([
          {'userId': 'see994', 'userIdx': 202, 'userNick': ' '},
        ], size: 1),
        page: 1,
        size: 1,
      );
      expect([page.rooms.single.nick, page.rooms.single.title], ['', '']);
    });
  });

  group('S04 member/bj', () {
    test("live broadcaster: the refresh room is 3.x's, live by the listed media, with the upgrades", () {
      final member = _member('S04-member-live', 'daisy00');
      expect(member.index, 24133575);
      expect(member.media, isNotNull);
      expect(PandaLiveApi.listedLive(member), isTrue);
      final room = PandaLiveApi.refreshRoom(member);
      _expectParity(
        _projection(room),
        _value('S04-member-live', 'getRoomDetailForRefresh')! as Map<String, dynamic>,
        changed: _liveChanged,
        added: _liveAdded(member.media!),
      );
      expect(room.userId, '24133575');
      expect(room.onlineViewers, '50', reason: 'member/bj media');
      expect(room.totalViewers, '903');
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 17, 0, 35));
      expect(room.area, '个人直播');
      expect(room.link, 'https://www.pandalive.co.kr/play/daisy00');
      expect(room.introduction, '데이지ღ님의 방송국에 어서오세요.');
      expect(_value('S04-member-live', 'getLiveStatus'), isTrue);
    });

    test("offline broadcaster: the channel as 3.x's profile room", () {
      final member = _member('S04-member-offline', 'flffl369');
      expect(member.media, isNull);
      expect(PandaLiveApi.listedLive(member), isFalse);
      final room = PandaLiveApi.profileRoom(member);
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        _expectParity(
          _projection(room),
          _value('S04-member-offline', key)! as Map<String, dynamic>,
          changed: _roomChanged,
          reason: key,
        );
      }
      expect(PandaLiveApi.refreshRoom(member).toJson(), room.toJson());
      expect(room.title, '데이지ෆ님의 방송국');
      expect(room.cover, '', reason: 'no banner');
      expect(room.notice, PandaLiveApi.chatNotice);
      expect([room.startedAt, room.restriction], [null, null], reason: 'offline');
      expect(_value('S04-member-offline', 'getLiveStatus'), isFalse);
    });

    test('media that says it is not live is offline (25-6; 3.x: live whenever listed)', () {
      final ended = PandaLiveApi.member(
        _memberAnswer(media: _media(changes: {'isLive': false})),
        userId: 'fixture_101',
      );
      expect(PandaLiveApi.listedLive(ended), isFalse);
      expect(PandaLiveApi.refreshRoom(ended).toJson(), PandaLiveApi.profileRoom(ended).toJson());
      expect(PandaLiveApi.refreshRoom(ended).liveStatus, LiveStatus.offline);
      for (final isLive in [true, 'Y', null, 'maybe']) {
        final member = PandaLiveApi.member(
          _memberAnswer(media: _media(changes: {'isLive': isLive})),
          userId: 'fixture_101',
        );
        expect(PandaLiveApi.listedLive(member), isTrue, reason: '$isLive: as 3.x unless it says false');
        expect(PandaLiveApi.refreshRoom(member).isLiveNow, isTrue, reason: '$isLive');
      }
    });

    test("a refresh shows the flags' restriction and notice", () {
      for (final (changes, restriction, notice) in [
        ({'type': 'free'}, LiveRestriction.none, PandaLiveApi.chatNotice),
        ({'isAdult': true}, LiveRestriction.adult, PandaLiveApi.adultNotice),
        ({'isPw': true, 'type': 'free'}, LiveRestriction.password, PandaLiveApi.passwordNotice),
        ({'type': 'fan'}, LiveRestriction.subscribersOnly, PandaLiveApi.fansNotice),
        (const <String, Object?>{}, null, PandaLiveApi.chatNotice),
      ]) {
        final member = PandaLiveApi.member(
          _memberAnswer(media: _media(changes: changes)),
          userId: 'fixture_101',
        );
        final room = PandaLiveApi.refreshRoom(member);
        expect(room.restriction, restriction, reason: '$changes');
        expect(room.notice, notice, reason: '$changes');
        expect(room.isLiveNow, isTrue, reason: '$changes');
      }
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

    test('the form asks for the broadcast alone (25-9; 3.x also asked for the fan grades, never read)', () {
      final sent = (_outcome('S04-member-live', 'getRoomDetailForRefresh')['requests'] as List).single as Map;
      expect(sent['form'], {'userId': 'daisy00', 'info': 'media fanGrade'});
      expect(PandaLiveApi.memberForm('daisy00'), {'userId': 'daisy00', 'info': 'media'});
      expect(PandaLiveApi.memberForm('daisy00').keys, (sent['form'] as Map).keys, reason: 'field order');
      final recorded = Uri.splitQueryString((_sample('S04-member-live').meta['request'] as Map)['body'] as String);
      expect(PandaLiveApi.memberForm('daisy00'), recorded, reason: 'what the samples were recorded with');
      expect(sent['referer'], 'https://www.pandalive.co.kr/live/play/daisy00');
      expect(PandaLiveApi.roomUrl('daisy00'), 'https://www.pandalive.co.kr/play/daisy00', reason: '25-4');
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
      expect([offline.nick, offline.title], ['', ''], reason: 'the unified rule on placeholders (M4.25: the id)');
      expect(offline.followers, '');
    });
  });

  group('S05 live/play', () {
    final member = _member('S04-member-live', 'daisy00');

    test("a live broadcast: its master and chat; the room is 3.x's entry, with the upgrades", () {
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
      final media = (jsonDecode(fixture.body) as Map<String, dynamic>)['media'] as Map<String, dynamic>;
      for (final key in ['getRoomDetail', 'getRoomDetailForRecording']) {
        _expectParity(
          _projection(room),
          _value('S04-member-live', key)! as Map<String, dynamic>,
          changed: _liveChanged,
          added: _liveAdded(media),
          reason: key,
        );
      }
      expect(room.onlineViewers, '47', reason: 'live/play media');
      expect(room.restriction, LiveRestriction.none);
      final sent = (_outcome('S04-member-live', 'getRoomDetail')['requests'] as List).cast<Map<String, dynamic>>();
      expect(PandaLiveApi.playForm('daisy00'), sent[1]['form']);
      expect(PandaLiveApi.playForm('daisy00').keys, (sent[1]['form'] as Map).keys);
    });

    test('the chat arguments of a live broadcast (25-2): its user, channel and token', () {
      final fixture = _sample('S05-play-live');
      final play = PandaLiveApi.play(fixture.body, member: member, status: fixture.status);
      final args = PandaLiveApi.danmakuArgs(member, play)!;
      expect(args.userId, 'daisy00');
      expect(args.channel, '24133575');
      expect(args.token, play.chatToken);
      expect(args.token!.split('.'), hasLength(3), reason: 'a JWT');
      expect('$args', isNot(contains(args.token)), reason: 'no token in logs');
      expect(PandaLiveApi.chatServer, Uri.parse('wss://chat-ws.neolive.kr/connection/websocket'));
      final owner = PandaLiveApi.member(_memberAnswer(media: _media()), userId: 'fixture_101');
      for (final (channel, expected) in [(101, '101'), ('abc', '101'), (null, '101'), ('202', '202')]) {
        final answer = PandaLiveApi.play(_playAnswer(changes: {'channel': channel}), member: owner);
        expect(PandaLiveApi.danmakuArgs(owner, answer)?.channel, expected, reason: '$channel');
      }
      final noToken = PandaLiveApi.play(_playAnswer(changes: {'token': null}), member: owner);
      expect(PandaLiveApi.danmakuArgs(owner, noToken)?.token, isNull);
      expect(PandaLiveApi.danmakuArgs(owner, PandaLiveApi.play(_refusal('needAdult'), member: owner)), isNull);
      final ended = PandaLiveApi.play(
        _playAnswer(media: _media(changes: {'isLive': false})),
        member: owner,
      );
      expect(PandaLiveApi.danmakuArgs(owner, ended), isNull);
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
      expect(room.restriction, isNull);
      expect(unavailable, isA<StreamUnavailable>());
    });

    test('adult (HTTP 400 needAdult): live, adult, with its notice; NeedsLogin (3.x: schema)', () {
      final fixture = _sample('S05-play-needlogin');
      expect(fixture.status, 400);
      expect(_value('S05-play-needlogin', 'getRoomDetail'), containsPair('message', 'PandaTV schema'));
      final owner = PandaLiveApi.member(_syntheticMember('youngddo819', 1000001, adult: true), userId: 'youngddo819');
      final play = PandaLiveApi.play(fixture.body, member: owner, status: fixture.status);
      expect(play.code, 'needAdult');
      final (:room, :unavailable) = PandaLiveApi.playRoom(owner, play);
      expect(room.liveStatus, LiveStatus.live);
      expect(room.restriction, LiveRestriction.adult);
      expect(room.notice, PandaLiveApi.adultNotice);
      expect(room.toJson(), PandaLiveApi.refreshRoom(owner).toJson(), reason: "3.x's code: the member/bj media");
      expect(unavailable, isA<NeedsLogin>());
    });

    test('the other refusals: the restriction of the code, else of the flags; its notice and error', () {
      for (final (code, changes, restriction, notice, matcher) in [
        (
          'needPassword',
          const <String, Object?>{},
          LiveRestriction.password,
          PandaLiveApi.passwordNotice,
          isA<StreamUnavailable>(),
        ),
        (
          'password',
          const <String, Object?>{},
          LiveRestriction.password,
          PandaLiveApi.passwordNotice,
          isA<StreamUnavailable>(),
        ),
        (
          'needLogin',
          const <String, Object?>{},
          LiveRestriction.needsLogin,
          PandaLiveApi.restrictedNotice,
          isA<NeedsLogin>(),
        ),
        // An anonymous viewer of a password room is refused needLogin (2026-09-29).
        (
          'needLogin',
          {'isPw': true, 'type': 'free'},
          LiveRestriction.password,
          PandaLiveApi.passwordNotice,
          isA<StreamUnavailable>(),
        ),
        (
          'needLogin',
          {'type': 'fan'},
          LiveRestriction.subscribersOnly,
          PandaLiveApi.fansNotice,
          isA<StreamUnavailable>(),
        ),
        ('needLogin', {'isAdult': true}, LiveRestriction.adult, PandaLiveApi.adultNotice, isA<NeedsLogin>()),
        ('needLogin', {'type': 'free'}, LiveRestriction.needsLogin, PandaLiveApi.restrictedNotice, isA<NeedsLogin>()),
        (
          'fanOnly',
          const <String, Object?>{},
          LiveRestriction.unplayable,
          PandaLiveApi.restrictedNotice,
          isA<StreamUnavailable>(),
        ),
        (
          null,
          const <String, Object?>{},
          LiveRestriction.unplayable,
          PandaLiveApi.restrictedNotice,
          isA<StreamUnavailable>(),
        ),
      ]) {
        final owner = PandaLiveApi.member(
          _memberAnswer(media: _media(changes: changes)),
          userId: 'fixture_101',
        );
        final play = PandaLiveApi.play(_refusal(code), member: owner, status: 400);
        expect(play.code, code ?? '');
        final (:room, :unavailable) = PandaLiveApi.playRoom(owner, play);
        final reason = '$code $changes';
        expect(room.isLiveNow, isTrue, reason: reason);
        expect(room.restriction, restriction, reason: reason);
        expect(room.notice, notice, reason: reason);
        expect(unavailable, matcher, reason: reason);
        expect('$unavailable', contains(restriction.name), reason: reason);
      }
    });

    test('accepted but not live: the offline profile room; live without HLS: the room, unplayable', () {
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
      expect(live.room.restriction, LiveRestriction.unplayable);
      expect(live.room.notice, PandaLiveApi.chatNotice);
      expect(live.room.cover, 'https://cdn.pandalive.co.kr/cover.jpg');
      expect(live.unavailable, isA<StreamUnavailable>());
    });

    test("the master is the first usable of hls3, hls2, hls (3.x's _firstMaster); none usable is ApiChanged", () {
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
      expect(
        master({
          'hls3': [
            'x',
            {'url': 'https://live-video.net.evil.test/a.m3u8'},
          ],
          'hls2': 'x',
          'hls': [
            {'url': second},
          ],
        }),
        Uri.parse(second),
        reason: 'the unified rule: a bad address only loses itself (3.x: ApiChanged)',
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
    List<LivePlayQuality> recorded() {
      final fixture = _sample('S06-master');
      return PandaLiveApi.qualities(fixture.body, master: fixture.url, userId: 'daisy00', issuedAt: fixture.capturedAt);
    }

    test("25-5: the source is 原画, the ids lose 30; the variants, order and URLs are 3.x's", () {
      final qualities = recorded();
      final legacy = _maps(_legacy('S06-master')['qualities']);
      expect(legacy.map((quality) => quality['quality']), [
        '1080p30 · HLS',
        '720p30 · HLS',
        '480p30 · HLS',
        '360p30 · HLS',
        '160p30 · HLS',
      ]);
      expect(qualities.map((quality) => quality.quality), ['原画', '720p', '480p', '360p', '160p']);
      expect(qualities.map((quality) => quality.id), ['1080p', '720p', '480p', '360p', '160p']);
      expect(
        qualities.map((quality) => quality.id),
        legacy.map((quality) => PandaLiveApi.qualityIdFromLegacy(quality['id'] as String)),
        reason: "3.x's ids map onto the new ones",
      );
      expect(qualities.first.sort, PandaLiveApi.sourceRank + (legacy.first['sort'] as int), reason: 'the source first');
      expect(qualities.skip(1).map((quality) => quality.sort), legacy.skip(1).map((quality) => quality['sort']));
      final streams = _maps(_legacy('S06-master')['parseManifest']);
      expect(qualities.map((quality) => _line(quality).url), streams.map((stream) => stream['uri']));
    });

    test('each quality is one line: the variant with the media headers, HLS, its codec and lease', () {
      final fixture = _sample('S06-master');
      final legacyHeaders = (_legacy('S04-member-live')['PandaLiveApi.mediaHeaders'] as Map).map(
        (key, value) => MapEntry('$key'.toLowerCase(), value),
      );
      for (final quality in recorded()) {
        final line = _line(quality);
        expect(line.headers, {
          ...legacyHeaders,
          'referer': 'https://www.pandalive.co.kr/play/daisy00',
        }, reason: "PlaybackHeaderResolver's values, the Referer the room's page (25-4)");
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

    test('ids: 60 from 50 fps, nothing below (25-5; 3.x: 30 from 25); a repeated id gets _<n>; best first', () {
      final qualities = _qualities(
        _masterText([
          _variant('1280x720', bandwidth: 2000),
          _variant('1920x1080', bandwidth: 6000, frameRate: '60.000'),
          _variant('1280x720', bandwidth: 3000),
          _variant('640x360', bandwidth: 500, frameRate: '20.000'),
          _variant('1280x720', bandwidth: 2500, frameRate: '59.940'),
        ]),
      );
      expect(qualities.map((quality) => quality.id), ['1080p60', '720p60', '720p_3', '720p', '360p']);
      expect(qualities.map((quality) => quality.quality), ['1080p60', '720p60', '720p_3', '720p', '360p']);
      expect(qualities[2].sort, 720 * 10000000 + 3000);
    });

    test('the source rendition (VIDEO="chunked") is 原画 and first, whatever its place', () {
      final qualities = _qualities(
        _masterText([
          _variant('1920x1080', bandwidth: 9000, frameRate: '60.000'),
          _variant('1280x720', bandwidth: 3000, frameRate: '60.000', video: 'chunked'),
          _variant('852x480', video: '480p30'),
        ]),
      );
      expect(qualities.map((quality) => quality.quality), ['原画', '1080p60', '480p']);
      expect(qualities.map((quality) => quality.id), ['720p60', '1080p60', '480p']);
      expect(qualities.first.sort, greaterThan(qualities[1].sort));
      final plain = _qualities(_masterText([_variant('1920x1080'), _variant('1280x720')]));
      expect(plain.map((quality) => quality.quality), ['1080p', '720p'], reason: 'no source rendition named');
    });

    test("3.x's site test master: 1080p60, 720p60, 480p", () {
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
      expect(qualities.map((quality) => quality.id), ['1080p60', '720p60', '480p']);
      expect(_line(qualities[1]).url, contains('/720.m3u8'));
      expect(_line(qualities.first).codec, isNull, reason: 'no CODECS');
    });

    test("3.x's ids for the stored preferences (M9): <height>p30 is <height>p, everything else stays", () {
      for (final (old, now) in [
        ('1080p30', '1080p'),
        (' 720p30 ', '720p'),
        ('720p30_3', '720p_3'),
        ('1080p60', '1080p60'),
        ('720p60_2', '720p60_2'),
        ('360p', '360p'),
        ('1080p', '1080p'),
        ('p30', 'p30'),
        ('1080p300', '1080p300'),
        ('原画', '原画'),
      ]) {
        expect(PandaLiveApi.qualityIdFromLegacy(old), now, reason: old);
        expect(PandaLiveApi.qualityIdFromLegacy(now), now, reason: 'applied twice');
      }
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
      expect(qualities.map((quality) => quality.id), ['720p']);
      expect(
        () => _qualities(
          _masterText(['#EXT-X-STREAM-INF:BANDWIDTH=1,CODECS="mp4a.40.2"', 'https://a.playlist.live-video.net/a.m3u8']),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(() => _qualities(_masterText([])), throwsA(isA<StreamUnavailable>()));
    });

    test('a broken variant only loses itself (the unified rule; 3.x failed the room); none usable is ApiChanged', () {
      final broken = [
        (_variant('1920x1080', uri: 'https://live-video.net.evil.test/1080.m3u8'), 'lookalike media host'),
        (_variant('1920x1080', uri: 'https://a.live-video.net/1080.ts'), 'not a playlist'),
        ('#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1920x1080\n#EXT-X-ENDLIST', 'a tag for URI'),
        (_variant('1920x1080', frameRate: '300'), 'frame rate'),
        (_variant('1920x1080', bandwidth: -1), 'bandwidth'),
      ];
      for (final (variant, reason) in broken) {
        final qualities = _qualities(_masterText([variant, _variant('1280x720')]));
        expect(qualities.map((quality) => quality.id), ['720p'], reason: reason);
        expect(() => _qualities(_masterText([variant])), throwsA(isA<ApiChanged>()), reason: reason);
      }
      expect(
        () => _qualities(_masterText(['#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1280x720'])),
        throwsA(isA<ApiChanged>()),
        reason: 'no URI at the end',
      );
    });

    test('a tag between a variant and its URI keeps the variant (the reading shared with YouTube, F.5a)', () {
      final qualities = _qualities(
        _masterText([
          '#EXT-X-STREAM-INF:BANDWIDTH=1000,RESOLUTION=1280x720,FRAME-RATE=30.000',
          '#EXT-X-PROGRAM-DATE-TIME:2026-10-02T00:00:00Z',
          'https://fixture.playlist.live-video.net/v1/playlist/720.m3u8',
        ]),
      );
      expect(qualities.map((quality) => quality.id), ['720p']);
      expect(_line(qualities.single).url, 'https://fixture.playlist.live-video.net/v1/playlist/720.m3u8');
    });

    test('what is not a master is ApiChanged, as 3.x', () {
      expect(() => _qualities('<html>'), throwsA(isA<ApiChanged>()));
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

    test('resolution: the line of the quality asked (a 3.x id too), applied as the new id; else why not', () {
      final qualities = _qualities(_masterText([_variant('1920x1080'), _variant('1280x720')]));
      final data = PandaLiveRoomData(userId: 'fixture_101', userIndex: 101, qualities: qualities);
      final resolution = PandaLiveApi.resolution(data, const LivePlayQuality(quality: 'x', id: '720p'));
      expect(resolution.appliedQualityData, '720p');
      expect(resolution.urls, [_line(qualities[1]).url]);
      expect(resolution.lines.single.headers, PandaLiveApi.mediaHeaders('fixture_101'));
      final legacy = PandaLiveApi.resolution(data, const LivePlayQuality(quality: '720p30 · HLS', id: '720p30'));
      expect(legacy.appliedQualityData, '720p', reason: "3.x's id (25-5)");
      expect(legacy.urls, resolution.urls);
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

    test("ids are 3.x's; the room page is the website's /play/ (25-4); the media headers keep 3.x's values", () {
      final legacy = _legacy('S04-member-live');
      final ids = (legacy['PandaLiveLink.parseOrId'] as Map).cast<String, Object?>();
      for (final MapEntry(key: text, value: id) in ids.entries) {
        expect(PandaLiveApi.roomIdFromUrl(text.trim()) ?? PandaLiveApi.normalizeUserId(text), id, reason: text);
      }
      expect(PandaLiveApi.normalizeUserId('name@ka/evil'), isNull);
      expect(PandaLiveApi.normalizeUserId('a' * 65), isNull);
      expect(PandaLiveApi.normalizeUserId(7), isNull);
      expect(legacy['PandaLiveLink.url'], 'https://www.pandalive.co.kr/live/play/daisy00');
      expect(PandaLiveApi.roomUrl('daisy00'), 'https://www.pandalive.co.kr/play/daisy00');
      expect(PandaLiveApi.roomIdFromUrl(PandaLiveApi.roomUrl('daisy00')), 'daisy00');
      expect(
        PandaLiveApi.roomIdFromUrl(legacy['PandaLiveLink.url']! as String),
        'daisy00',
        reason: '3.x links stay rooms',
      );
      expect(PandaLiveApi.roomUrl('1506087545@ka'), contains('1506087545'));
      final legacyHeaders = (legacy['PandaLiveApi.mediaHeaders'] as Map).map(
        (key, value) => MapEntry('$key'.toLowerCase(), value),
      );
      expect(PandaLiveApi.mediaHeaders('daisy00'), {...legacyHeaders, 'referer': PandaLiveApi.roomUrl('daisy00')});
    });
  });
}
