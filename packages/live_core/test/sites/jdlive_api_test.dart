// JD Live parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/jdlive/legacy_expected.dart from 3.x's JdLiveApi, JdLiveLink and
// JdLiveSite). Every intended difference is listed with its reason (the
// M4.28 differences, and the M4.U upgrades by item number, docs/specs/UPGRADES.md
// 28-1 to 28-7); everything else must match. The synthetic cases are the
// edited copies the generator ran through 3.x (`variants`) and 3.x's
// jd_live_site_test.dart. The S05 samples (M4.U.28) have no 3.x output.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('jdlive', name);

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

/// The `result` of a traced legacy call.
Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

/// Room keys every room changed: the notice is in words for users now (the
/// unified rule for developer notes, M4.U), and since M5.24 (chat is shown)
/// it only explains the number.
const _notice = {'notice'};

/// Room keys a play answer without a list card changed: 28-2 (no `JD Live`
/// title or shop name, no broadcast id as the shop account, no cover as the
/// avatar: all empty, so a follow keeps what it stored), 28-3 (the blurred
/// image is not the cover) and the notice.
const _playOnly = {'title', 'nick', 'userId', 'avatar', 'cover', 'notice'};

/// Room keys a play answer completed from a list card changed: 28-3 (the
/// card's cover instead of the blurred image) and the notice.
const _afterCard = {'cover', 'notice'};

/// Broadcast keys a play answer changed: 28-2 (names empty) and 28-3 (the
/// blurred image is the background, not the cover).
const _playBroadcast = {'nick', 'title', 'cover'};

/// Asserts that [actual] (a `toJson`) equals 3.x's [legacy] map on every key
/// 3.x wrote, except [changed] (intended differences). 3.x wrote null where
/// the immutable model writes '' (`totalViewers` without views, the area's
/// `areaPic`).
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

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {Set<String> changed = const {}, String reason = ''}) {
  final expected = _maps(legacy);
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(_projection(room), expected[index], changed: changed, reason: '$reason[$index]');
  }
}

/// 3.x's projection of a `JdLiveRoom`.
Map<String, Object?> _broadcast(JdLiveRoom room) => {
  'liveId': room.liveId,
  'authorId': room.authorId,
  'nick': room.nick,
  'title': room.title,
  'avatar': room.avatar,
  'cover': room.cover,
  'totalViews': room.totalViews,
  'state': room.state.name,
  'hls': room.hls?.toString(),
  'flv': room.flv?.toString(),
};

void _expectBroadcast(JdLiveRoom room, Object? legacy, {Set<String> changed = const {}, String reason = ''}) {
  final actual = _broadcast(room);
  for (final MapEntry(:key, :value) in (legacy! as Map<String, dynamic>).entries) {
    if (changed.contains(key)) continue;
    expect(actual[key], value, reason: '$reason $key');
  }
}

/// Asserts a page against 3.x's: the next count, the broadcasts (the first
/// [rooms] when given) except [changed] keys, and whether another page
/// follows, which is 28-1's rule now: the page had a broadcast (3.x: 30 of
/// them).
void _expectPage(JdLivePage page, Object? legacy, {int? rooms, Set<String> changed = const {}, String reason = ''}) {
  final expected = legacy! as Map<String, dynamic>;
  expect(page.nextCount, expected['nextCount'], reason: reason);
  expect(page.hasMore, page.rooms.isNotEmpty, reason: '$reason: 28-1');
  final listed = expected['rooms'];
  if (listed is int) {
    expect(page.rooms, hasLength(listed), reason: reason);
    expect(expected['hasMore'], listed >= 30, reason: "$reason: 3.x's rule");
    return;
  }
  final broadcasts = _maps(listed);
  final actual = rooms == null ? page.rooms : page.rooms.take(rooms).toList();
  expect(actual.map((room) => room.liveId), broadcasts.map((room) => room['liveId']), reason: reason);
  for (final (index, room) in actual.indexed) {
    _expectBroadcast(room, broadcasts[index], changed: changed, reason: '$reason[$index]');
  }
}

/// 3.x's failure kind of a legacy error projection (`JD Live <kind>`), or
/// null when it did not fail.
String? _failure(Object? legacy) {
  if (legacy is! Map || legacy['throws'] != 'JdLiveException') return null;
  return (legacy['message']! as String).replaceFirst('JD Live ', '');
}

/// The `SiteError` a 3.x failure kind of the API layer is now.
Matcher _typed(String kind) => throwsA(switch (kind) {
  'schema' || 'identity' || 'service' => isA<ApiChanged>(),
  'missing' => isA<NotFound>(),
  'access' => isA<RiskControl>(),
  'rateLimited' => isA<RateLimited>(),
  'transport' => isA<NetworkFailure>(),
  _ => throw ArgumentError(kind),
});

/// [sample]'s JSON with the first broadcast card edited by [edit].
String _editedCard(String sample, void Function(Map<String, dynamic> card) edit, {int index = 0}) {
  final json = jsonDecode(_sample(sample).body) as Map<String, dynamic>;
  final cards = [
    for (final card in (json['data'] as Map<String, dynamic>)['list'] as List)
      if ((card as Map<String, dynamic>)['templateType'] == 1) card,
  ];
  edit(cards[index]);
  return jsonEncode(json);
}

String _editedList(String sample, void Function(Map<String, dynamic> json) edit) {
  final json = jsonDecode(_sample(sample).body) as Map<String, dynamic>;
  edit(json);
  return jsonEncode(json);
}

/// [sample]'s play JSON with `data` fields replaced (null removes one) and
/// root fields in [root].
String _editedPlay(Map<String, Object?> data, {Map<String, Object?> root = const {}, String sample = 'S02-play-live'}) {
  final json = jsonDecode(_sample(sample).body) as Map<String, dynamic>;
  final fields = json['data'] as Map<String, dynamic>;
  for (final MapEntry(:key, :value) in data.entries) {
    value == null ? fields.remove(key) : fields[key] = value;
  }
  for (final MapEntry(:key, :value) in root.entries) {
    value == null ? json.remove(key) : json[key] = value;
  }
  return jsonEncode(json);
}

const _archivedLive = '48378944';
const _live = '48395626';
const _stream = 'https://zt-pull-ai.jdcloud.com/live/F366C61365FB1F9B4BC62D90DBE239B1_fhd';
const _recording =
    'https://discover.300hu.com/m3u8/48395626/48395626_1790617263553_1_qtrans.m3u8'
    '?originM3u8=48395626_1790012438_1790617202_1790617263553_qt.m3u8';

void main() {
  group('S01 featured list', () {
    test('the one category and its area match 3.x', () {
      final legacy = _result(_legacy('S01-list-p1')['getCategores'])! as List;
      final categories = JdLiveApi.categories();
      final expected = legacy.single as Map<String, dynamic>;
      expect((categories.single.id, categories.single.name), (expected['id'], expected['name']));
      _expectParity(categories.single.children.single.toJson(), _maps(expected['children']).single);
      expect(JdLiveApi.isArea(categories.single.children.single), isTrue);
      expect(JdLiveApi.isArea(const LiveArea(platform: 'jdlive', areaType: 'official', areaId: 'other')), isFalse);
      expect(JdLiveApi.isArea(const LiveArea(platform: 'bilibili', areaType: 'official', areaId: 'featured')), isFalse);
    });

    test('page 1: 30 broadcasts of 37 entries (7 promotions skipped), currentCount 37, another page', () {
      final page = JdLiveApi.directory(_sample('S01-list-p1').body, page: 1);
      _expectPage(page, _legacy('S01-list-p1')['parseDirectoryJson']);
      expect(page.rooms, hasLength(30));
      expect((page.nextCount, page.hasMore), (37, true));
      final first = page.rooms.first;
      expect(first.nick, '海信诚一恒专卖店');
      expect(first.totalViews, 37);
      expect(first.hls, isNull, reason: 'cards have no media');
      expect(first.restriction, isNull, reason: 'the list does not say');
      expect(first.background, isEmpty);
    });

    test('page 2: 30 more, none repeated, currentCount 67', () {
      final page = JdLiveApi.directory(_sample('S01-list-p2').body, page: 2, after: 37);
      _expectPage(page, _legacy('S01-list-p2')['parseDirectoryJson']);
      final first = JdLiveApi.directory(_sample('S01-list-p1').body, page: 1);
      expect(
        page.rooms.map((room) => room.liveId).toSet().intersection(first.rooms.map((room) => room.liveId).toSet()),
        isEmpty,
      );
      expect((page.nextCount, page.hasMore), (67, true));
    });

    test("the cards as rooms: every field of 3.x's directory pages 1 and 2", () {
      final pages = _legacy('S01-list-p1')['getDirectoryPage'] as Map<String, dynamic>;
      for (final (sample, page) in [('S01-list-p1', 1), ('S01-list-p2', 2)]) {
        final rooms = [
          for (final card in JdLiveApi.directory(_sample(sample).body, page: page).rooms) JdLiveApi.room(card),
        ];
        final legacy = _result(pages['page $page'])! as Map<String, dynamic>;
        _expectRooms(rooms, legacy['rooms'], changed: _notice, reason: 'page $page');
      }
      final card = JdLiveApi.room(JdLiveApi.directory(_sample('S01-list-p1').body, page: 1).rooms.first);
      expect(card.userId, '24304104', reason: 'the shop account');
      expect(card.area, 'JD Live');
      expect(card.effectiveTotalViewers, '37', reason: 'pv is cumulative (REG-COMMON-004)');
      expect(card.effectiveOnlineViewers, isEmpty);
      expect(card.httpHeaders, JdLiveApi.mediaHeaders(_archivedLive), reason: "3.x's room headers (in the 3.x JSON)");
      expect(card.data, isNull, reason: 'a card cannot be played');
      expect((card.restriction, card.startedAt), (null, null), reason: 'the list says neither');
      expect(card.notice, JdLiveApi.chatNotice);
    });

    test("3.x's list checks on edited copies", () {
      final variants = _legacy('S01-list-p1')['variants'] as Map<String, dynamic>;
      Map<String, dynamic> data(Map<String, dynamic> card) => card['data'] as Map<String, dynamic>;
      final bodies = <String, String>{
        'userName null': _editedCard('S01-list-p1', (c) => data(c)['userName'] = null),
        'userName number': _editedCard('S01-list-p1', (c) => data(c)['userName'] = 7),
        'title blank': _editedCard('S01-list-p1', (c) => data(c)['title'] = '  \n '),
        'title spaced': _editedCard('S01-list-p1', (c) => data(c)['title'] = ' a\n\tb  c '),
        'userPic http': _editedCard('S01-list-p1', (c) => data(c)['userPic'] = 'http://img30.360buyimg.com/a.png'),
        'userPic other host': _editedCard('S01-list-p1', (c) => data(c)['userPic'] = 'https://example.com/a.png'),
        'userPic protocol-relative': _editedCard(
          'S01-list-p1',
          (c) => data(c)['userPic'] = '//img30.360buyimg.com/a.png',
        ),
        'userPic number': _editedCard('S01-list-p1', (c) => data(c)['userPic'] = 1),
        'indexImage missing': _editedCard('S01-list-p1', (c) => data(c).remove('indexImage')),
        'userPic missing': _editedCard('S01-list-p1', (c) => data(c).remove('userPic')),
        'pv negative': _editedCard('S01-list-p1', (c) => data(c)['pv'] = -1),
        'pv text': _editedCard('S01-list-p1', (c) => data(c)['pv'] = '12'),
        'pv missing': _editedCard('S01-list-p1', (c) => data(c).remove('pv')),
        'status 0': _editedCard('S01-list-p1', (c) => data(c)['status'] = 0),
        'status 2': _editedCard('S01-list-p1', (c) => data(c)['status'] = 2),
        'status 3': _editedCard('S01-list-p1', (c) => data(c)['status'] = 3),
        'status 10': _editedCard('S01-list-p1', (c) => data(c)['status'] = 10),
        'status 99': _editedCard('S01-list-p1', (c) => data(c)['status'] = 99),
        'status missing': _editedCard('S01-list-p1', (c) => data(c).remove('status')),
        'authorId missing': _editedCard('S01-list-p1', (c) => data(c).remove('authorId')),
        'liveId differs from id': _editedCard('S01-list-p1', (c) => data(c)['liveId'] = '48000001'),
        'liveId missing': _editedCard('S01-list-p1', (c) => data(c).remove('liveId')),
        'id missing': _editedCard('S01-list-p1', (c) => data(c).remove('id')),
        'liveId short': _editedCard('S01-list-p1', (c) {
          data(c)['liveId'] = '1234';
          data(c)['id'] = 1234;
        }),
        'second card repeats the first': _editedCard('S01-list-p1', (c) {
          data(c)['liveId'] = _archivedLive;
          data(c)['id'] = int.parse(_archivedLive);
        }, index: 1),
        'templateType text': _editedCard('S01-list-p1', (c) => c['templateType'] = '1'),
        'templateType 2': _editedCard('S01-list-p1', (c) => c['templateType'] = 2),
        'data not an object': _editedCard('S01-list-p1', (c) => c['data'] = 'x'),
        'list item not an object': _editedList('S01-list-p1', (j) => ((j['data'] as Map)['list'] as List).insert(0, 5)),
        'list not a list': _editedList('S01-list-p1', (j) => (j['data'] as Map)['list'] = <String, Object?>{}),
        'list empty': _editedList('S01-list-p1', (j) => (j['data'] as Map)['list'] = <Object?>[]),
        'currentCount missing': _editedList('S01-list-p1', (j) => (j['data'] as Map).remove('currentCount')),
        'currentCount text': _editedList('S01-list-p1', (j) => (j['data'] as Map)['currentCount'] = '37'),
        'code 2': _editedList('S01-list-p1', (j) => j['code'] = '2'),
        'code number 0': _editedList('S01-list-p1', (j) => j['code'] = 0),
        'subCode 1': _editedList('S01-list-p1', (j) => j['subCode'] = '1'),
        'subCode missing': _editedList('S01-list-p1', (j) => j.remove('subCode')),
        'data missing': jsonEncode({'code': '0', 'subCode': '0'}),
      };
      expect(bodies.keys.toSet(), variants.keys.toSet());
      // An entry that cannot be read is skipped now; 3.x failed the page
      // (the unified fault tolerance). The broadcasts left.
      const skipped = {
        'userName number': 29,
        'userPic number': 29,
        'data not an object': 29,
        'list item not an object': 30,
      };
      // A blank name or title stays empty (28-2; 3.x: `JD Live`).
      const blank = {'userName null': 'nick', 'title blank': 'title'};
      for (final MapEntry(key: name, value: body) in bodies.entries) {
        final legacy = variants[name];
        final failure = _failure(legacy);
        if (skipped[name] case final left?) {
          expect(failure, 'schema', reason: name);
          final page = JdLiveApi.directory(body, page: 1);
          expect((page.rooms.length, page.hasMore), (left, true), reason: name);
          if (name != 'list item not an object') {
            expect(page.rooms.map((room) => room.liveId), isNot(contains(_archivedLive)), reason: name);
          }
        } else if (failure != null) {
          expect(() => JdLiveApi.directory(body, page: 1), _typed(failure), reason: name);
        } else {
          final page = JdLiveApi.directory(body, page: 1);
          final field = blank[name];
          _expectPage(page, legacy, rooms: 2, changed: {?field}, reason: name);
          if (field != null) expect(_broadcast(page.rooms.first)[field], isEmpty, reason: name);
        }
      }
    });

    test("3.x's link rules: ids, lives.jd.com fragment routes, the room page", () {
      final legacy = _legacy('S01-list-p1')['JdLiveLink.parseLiveId'] as Map<String, dynamic>;
      for (final MapEntry(key: input, :value) in legacy.entries) {
        expect(JdLiveApi.liveIdOf(input), value, reason: input);
        final isUrl = input.contains('://');
        expect(JdLiveApi.liveIdFromUrl(input), isUrl ? value : null, reason: 'URL only: $input');
      }
      final links = _legacy('S01-list-p1')['JdLiveLink.watchUrl'] as Map<String, dynamic>;
      for (final MapEntry(key: input, :value) in links.entries) {
        final id = JdLiveApi.liveIdOf(input);
        if (value is String) {
          expect(JdLiveApi.link(id!), value, reason: input);
        } else {
          expect(id, isNull, reason: input);
        }
      }
      expect(JdLiveApi.isLiveId('12345'), isTrue);
      expect(JdLiveApi.isLiveId('01234'), isFalse);
      expect(JdLiveApi.isLiveId('1234'), isFalse);
    });

    test('requests: 3.x query of the list and the play answer', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1790533000000);
      final list = JdLiveApi.listUrl(page: 2, count: 37, timestamp: 1790533000000, now: now);
      expect(list.queryParameters, _sample('S01-list-p2').url.queryParameters);
      expect(list.host, 'api.m.jd.com');
      final play = JdLiveApi.playUrl(_archivedLive, now: now);
      expect(play.queryParameters, _sample('S02-play-live').url.queryParameters);
      expect(JdLiveApi.apiHeaders, {
        'accept': 'application/json, text/plain, */*',
        'origin': 'https://lives.jd.com',
        'referer': 'https://lives.jd.com/',
        'user-agent': JdLiveApi.userAgent,
      });
    });
  });

  group('S02 play answer', () {
    test("the live answer: state, background and one stream key, no names (3.x's parseRoomJson)", () {
      final room = JdLiveApi.play(_sample('S02-play-live').body, liveId: _archivedLive);
      final legacy = _legacy('S02-play-live')['parseRoomJson'] as Map<String, dynamic>;
      _expectBroadcast(room, legacy, changed: _playBroadcast);
      expect((room.nick, room.title, room.cover), ('', '', ''), reason: '28-2, 28-3 (3.x: JD Live, the blurred image)');
      expect(room.background, legacy['cover'], reason: '28-3: the blurred image is the background');
      expect(room.state, JdLiveState.live);
      expect((room.appOnly, room.restriction), (false, LiveRestriction.none));
      expect(room.streamError, isNull);
      expect(
        () => JdLiveApi.play(_sample('S02-play-live').body, liveId: '48378945'),
        throwsA(isA<ApiChanged>()),
        reason: "3.x's identity check: an answer for another broadcast",
      );
    });

    test('the room at refresh depth: empty names, account, avatar and cover (28-2, 28-3); the rest as 3.x', () {
      final legacy = (_legacy('S02-play-live')['recorded'] as Map<String, dynamic>)['getRoomDetailForRefresh'];
      final room = JdLiveApi.room(JdLiveApi.play(_sample('S02-play-live').body, liveId: _archivedLive));
      final expected = _result(legacy)! as Map<String, dynamic>;
      _expectParity(_projection(room), expected, changed: _playOnly);
      expect((expected['title'], expected['nick'], expected['userId']), ('JD Live', 'JD Live', _archivedLive));
      expect(expected['avatar'], expected['cover'], reason: '3.x: the blurred image as avatar and cover');
      expect((room.title, room.nick, room.userId, room.avatar, room.cover), ('', '', null, '', ''));
      expect(room.displayNick('京东直播'), '京东直播', reason: '28-2: the interface shows the platform name');
      expect(room.restriction, LiveRestriction.none);
      expect(room.startedAt, isNull, reason: 'JD Live gives no start time');
      expect(room.effectiveAudienceMetricType, AudienceMetricType.unknown);
      expect(room.data, isNull);
      expect(room.notice, JdLiveApi.chatNotice);
    });

    test('a follow keeps its stored names, account, avatar and cover when refreshed (28-2, 28-3)', () {
      final card = JdLiveApi.room(JdLiveApi.directory(_sample('S01-list-p1').body, page: 1).rooms.first);
      final refreshed = JdLiveApi.room(JdLiveApi.play(_sample('S02-play-live').body, liveId: _archivedLive));
      final merged = card.mergeFrom(refreshed);
      expect(
        (merged.title, merged.nick, merged.userId, merged.avatar, merged.cover),
        (card.title, card.nick, card.userId, card.avatar, card.cover),
      );
      expect((merged.liveStatus, merged.restriction), (LiveStatus.live, LiveRestriction.none));
    });

    test('the list card completes the play answer (3.x enrich): names, account, avatar, views and cover (28-3)', () {
      final known = JdLiveApi.directory(_sample('S01-list-p1').body, page: 1).rooms.first;
      final answer = JdLiveApi.play(_sample('S02-play-live').body, liveId: _archivedLive);
      final room = answer.enrich(known);
      final legacy =
          (_legacy('S01-list-p1')['known'] as Map<String, dynamic>)['getRoomDetailForRefresh after the list'];
      final expected = _result(legacy)! as Map<String, dynamic>;
      _expectParity(_projection(JdLiveApi.room(room)), expected, changed: _afterCard);
      expect(expected['cover'], answer.background, reason: "3.x kept the play answer's blurred image");
      expect(room.cover, known.cover, reason: "28-3: the card's cover");
      expect(room.background, answer.background);
      expect(room.hls, isNotNull);
      expect(room.restriction, LiveRestriction.none);
    });

    test("3.x's play checks on edited copies: states, notices, stream keys, hosts, envelope", () {
      final variants = _legacy('S02-play-live')['variants'] as Map<String, dynamic>;
      const key = '834C6A62B3177AB5FDD83B3EAC6DC6EA';
      const flv = 'https://zt-pull-ai.jdcloud.com/live/${key}_fhd.flv';
      final bodies = <String, String>{
        'secret 1': _editedPlay({'secret': 1}),
        'secret 1 offline': _editedPlay({'secret': 1, 'status': 2, 'videoUrl': '', 'h5VideoUrl': ''}),
        'status 0': _editedPlay({'status': 0}),
        'status 2': _editedPlay({'status': 2}),
        'status 3': _editedPlay({'status': 3}),
        'status 10': _editedPlay({'status': 10}),
        'status 11': _editedPlay({'status': 11}),
        'status 99': _editedPlay({'status': 99}),
        'status text': _editedPlay({'status': '1'}),
        'status missing': _editedPlay({'status': null}),
        'secret missing': _editedPlay({'secret': null}),
        'liveId text': _editedPlay({'liveId': _archivedLive}),
        'liveId other': _editedPlay({'liveId': 48378945}),
        'videoUrl missing': _editedPlay({'videoUrl': null}),
        'videoUrl empty': _editedPlay({'videoUrl': ''}),
        'videoUrl number': _editedPlay({'videoUrl': 7}),
        'videoUrl http': _editedPlay({'videoUrl': flv.replaceFirst('https:', 'http:')}),
        'videoUrl other key': _editedPlay({'videoUrl': flv.replaceFirst(key, 'OTHER')}),
        'videoUrl other host': _editedPlay({'videoUrl': flv.replaceFirst('zt-pull-ai.jdcloud.com', 'example.com')}),
        'videoUrl other port': _editedPlay({'videoUrl': flv.replaceFirst('.com/', '.com:8443/')}),
        'videoUrl not /live/': _editedPlay({'videoUrl': flv.replaceFirst('/live/', '/vod/')}),
        'videoUrl with query': _editedPlay({'videoUrl': '$flv?sign=x'}),
        'h5VideoUrl missing': _editedPlay({'h5VideoUrl': null}),
        'both missing': _editedPlay({'h5VideoUrl': null, 'videoUrl': null}),
        'pcVideoUrl only': _editedPlay({'videoUrl': ''}),
        'blurredImg missing': _editedPlay({'blurredImg': null}),
        'blurredImg other host': _editedPlay({'blurredImg': 'https://example.com/a.jpg'}),
        'blurredImg number': _editedPlay({'blurredImg': 3}),
        'code 2': _editedPlay({}, root: {'code': '2'}),
        'subCode 1': _editedPlay({}, root: {'subCode': '1'}),
        'data missing': _editedPlay({}, root: {'data': null}),
      };
      expect(bodies.keys.toSet(), variants.keys.toSet());
      // 3.x failed the whole room (refresh too) for these; now one bad
      // address costs only its quality: the FLV comes from `pcVideoUrl`
      // (28-4), and a background that is not text is no background (the
      // unified fault tolerance). The qualities left.
      const tolerated = {
        'videoUrl missing': ['hls', 'flv'],
        'videoUrl empty': ['hls', 'flv'],
        'videoUrl number': ['hls', 'flv'],
        'videoUrl http': ['hls', 'flv'],
        'videoUrl other key': ['hls', 'flv'],
        'videoUrl other host': ['hls', 'flv'],
        'videoUrl other port': ['hls', 'flv'],
        'videoUrl not /live/': ['hls', 'flv'],
        'pcVideoUrl only': ['hls', 'flv'],
        'h5VideoUrl missing': ['flv'],
        'both missing': ['flv'],
        'blurredImg number': ['hls', 'flv'],
      };
      // States that changed: app-only is live (or what its status says),
      // marked appOnly (the unified rule for restricted broadcasts; 3.x:
      // unknown); status 3 is a replay, unplayable without a recording on
      // JD Cloud's video service (the unified replay rule; 3.x: offline).
      const states = {
        'secret 1': (LiveStatus.live, LiveRestriction.appOnly),
        'secret 1 offline': (LiveStatus.offline, LiveRestriction.appOnly),
        'status 3': (LiveStatus.replay, LiveRestriction.unplayable),
      };
      for (final MapEntry(key: name, value: body) in bodies.entries) {
        final legacy = variants[name] as Map<String, dynamic>;
        final refresh = legacy['getRoomDetailForRefresh'];
        final failure = _failure(refresh);
        if (tolerated[name] case final ids?) {
          expect(failure, 'schema', reason: name);
          final broadcast = JdLiveApi.play(body, liveId: _archivedLive);
          final room = JdLiveApi.room(broadcast, withData: true);
          expect((room.liveStatus, room.restriction), (LiveStatus.live, LiveRestriction.none), reason: name);
          expect(broadcast.streamError, isNull, reason: name);
          expect([for (final quality in JdLiveApi.qualities(broadcast)) quality.id], ids, reason: name);
          for (final id in ids) {
            expect(JdLiveApi.line(broadcast, id).url, contains(key), reason: '$name $id: the same stream');
          }
          continue;
        }
        if (failure != null) {
          expect(() => JdLiveApi.play(body, liveId: _archivedLive), _typed(failure), reason: name);
          continue;
        }
        final broadcast = JdLiveApi.play(body, liveId: _archivedLive);
        final state = states[name];
        final changed = {
          ..._playOnly,
          if (state != null) ...{'liveStatus', 'status', 'isRecord'},
        };
        _expectParity(
          _projection(JdLiveApi.room(broadcast)),
          refresh! as Map<String, dynamic>,
          changed: changed,
          reason: name,
        );
        _expectParity(
          _projection(JdLiveApi.room(broadcast, withData: true)),
          legacy['getRoomDetail']! as Map<String, dynamic>,
          changed: changed,
          reason: '$name entry',
        );
        if (state != null) {
          final room = JdLiveApi.room(broadcast);
          expect((room.liveStatus, room.restriction), state, reason: name);
        }
        // 3.x's qualities: the two for a live broadcast, [] for an offline
        // room (now StreamUnavailable, see jdlive_site_test), else
        // mediaUnavailable.
        final qualities = legacy['getRoomDetail → getPlayQualites'];
        if (qualities is List && qualities.isNotEmpty) {
          expect(broadcast.streamError, isNull, reason: name);
          expect(
            [for (final quality in JdLiveApi.qualities(broadcast)) quality.id],
            [for (final quality in qualities) (quality as Map)['id']],
            reason: name,
          );
        } else {
          expect(broadcast.streamError, isA<StreamUnavailable>(), reason: name);
        }
      }
    });

    test('states and restrictions: app-only is StreamUnavailable with its reason, the notice says so', () {
      final restricted = JdLiveApi.play(_editedPlay({'secret': 1}), liveId: _archivedLive);
      expect((restricted.state, restricted.appOnly), (JdLiveState.live, true));
      expect(
        restricted.streamError,
        isA<StreamUnavailable>().having((error) => '$error', 'reason', contains('app only')),
        reason: 'M2.1: appOnly is StreamUnavailable (3.x: NeedsLogin, M4.28)',
      );
      final room = JdLiveApi.room(restricted, withData: true);
      expect((room.liveStatus, room.isLiveNow, room.followGroup), (LiveStatus.live, true, FollowGroup.live));
      expect(
        (room.restriction, room.isRestricted, room.notice),
        (LiveRestriction.appOnly, true, JdLiveApi.restrictedNotice),
      );
      for (final (status, state, liveStatus) in [
        (0, JdLiveState.preview, LiveStatus.offline),
        (2, JdLiveState.offline, LiveStatus.offline),
        (10, JdLiveState.paused, LiveStatus.unknown),
        (11, JdLiveState.paused, LiveStatus.unknown),
        (99, JdLiveState.unknown, LiveStatus.unknown),
      ]) {
        final broadcast = JdLiveApi.play(_editedPlay({'status': status}), liveId: _archivedLive);
        expect(broadcast.state, state, reason: '$status');
        expect(broadcast.streamError, isA<StreamUnavailable>(), reason: '$status');
        final room = JdLiveApi.room(broadcast);
        expect((room.liveStatus, room.restriction), (liveStatus, LiveRestriction.none), reason: '$status');
      }
      expect(JdLiveApi.state('1'), JdLiveState.live);
      expect(JdLiveApi.state(1.0), JdLiveState.live);
      expect(JdLiveApi.state(true), JdLiveState.unknown);
      expect(JdLiveApi.chatNotice, isNot(contains('pv')), reason: 'plain words, no field names');
    });

    test('the old id: status 3 without a recording is an unplayable replay (3.x: offline)', () {
      final legacy = _legacy('S02-play-old');
      final room = JdLiveApi.play(_sample('S02-play-old').body, liveId: '10000');
      _expectBroadcast(room, legacy['parseRoomJson'], changed: _playBroadcast);
      for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        final expected = _result((legacy['recorded'] as Map<String, dynamic>)[depth])! as Map<String, dynamic>;
        final actual = JdLiveApi.room(room, withData: depth != 'getRoomDetailForRefresh');
        _expectParity(_projection(actual), expected, changed: {..._playOnly, 'liveStatus', 'isRecord'}, reason: depth);
        expect((expected['liveStatus'], expected['isRecord']), (1, false), reason: '3.x: offline');
      }
      final replay = JdLiveApi.room(room);
      expect((replay.liveStatus, replay.restriction), (LiveStatus.replay, LiveRestriction.unplayable));
      expect(replay.followGroup, FollowGroup.offline, reason: 'an unplayable replay is grouped offline (M2.1)');
      expect(room.streamError, isA<StreamUnavailable>());
      expect(JdLiveApi.qualities(room), isEmpty);
    });
  });

  group('S03 statuses', () {
    test("3.x's status mapping of the API: 403 (the detail endpoint without h5st) is RiskControl", () {
      final legacy = _legacy('S03-detail-403');
      expect(_sample('S03-detail-403').status, 403);
      expect(_sample('S03-detail-403').body, isEmpty);
      final kinds = <int, Matcher>{
        403: throwsA(isA<RiskControl>()),
        401: throwsA(isA<RiskControl>()),
        404: throwsA(isA<NotFound>()),
        429: throwsA(isA<RateLimited>()),
        400: throwsA(isA<ApiChanged>()),
        422: throwsA(isA<ApiChanged>()),
        500: throwsA(isA<NetworkFailure>()),
        503: throwsA(isA<NetworkFailure>()),
        302: throwsA(isA<NetworkFailure>()),
        204: throwsA(isA<NetworkFailure>()),
      };
      for (final MapEntry(key: status, value: matcher) in kinds.entries) {
        final calls = legacy['status $status'] as Map<String, dynamic>;
        expect(_failure(_result(calls['getRoomDetailForRefresh'])), isNotNull, reason: '$status');
        expect(
          () => JdLiveApi.play('', liveId: _archivedLive, status: status),
          matcher,
          reason: '$status',
        );
        expect(() => JdLiveApi.directory('', page: 1, status: status), matcher, reason: 'list $status');
      }
      expect(_failure(_result(legacy['list not JSON'])), 'schema');
      expect(() => JdLiveApi.directory('not json', page: 1), throwsA(isA<ApiChanged>()));
    });

    test('4 MiB answer limit in UTF-8 bytes', () {
      final body = '{"code":"0","subCode":"0","data":{"list":[],"currentCount":0,"x":"${'x' * (4 * 1024 * 1024)}"}}';
      expect(() => JdLiveApi.directory(body, page: 1), throwsA(isA<ApiChanged>()));
      final wide = '{"code":"0","subCode":"0","data":{"list":[],"currentCount":0,"x":"${'京' * (1400 * 1024)}"}}';
      expect(() => JdLiveApi.directory(wide, page: 1), throwsA(isA<ApiChanged>()), reason: 'under 4 Mi characters');
    });
  });

  group('S04 recorded together', () {
    test('the list page has 29 broadcasts: 3.x did not ask for page 2, now it does (28-1)', () {
      final page = JdLiveApi.directory(_sample('S04-list').body, page: 1);
      final legacy = _legacy('S04-list')['parseDirectoryJson'] as Map<String, dynamic>;
      _expectPage(page, legacy);
      expect(legacy['hasMore'], isFalse, reason: '3.x: fewer than 30 broadcasts');
      expect((page.rooms.length, page.nextCount, page.hasMore), (29, 36, true));
    });

    test('room entry: every field of 3.x but 28-2 and 28-3, with the play answer as data', () {
      final legacy = _legacy('S04-play-live');
      final broadcast = JdLiveApi.play(_sample('S04-play-live').body, liveId: _live);
      _expectBroadcast(broadcast, legacy['parseRoomJson'], changed: _playBroadcast);
      final recorded = legacy['recorded'] as Map<String, dynamic>;
      for (final depth in ['getRoomDetail', 'getRoomDetailForRecording']) {
        final room = JdLiveApi.room(broadcast, withData: true);
        _expectParity(_projection(room), _result(recorded[depth])! as Map<String, dynamic>, changed: _playOnly);
        expect(room.data, same(broadcast));
      }
      final known = JdLiveApi.directory(_sample('S04-list').body, page: 1).rooms.first;
      final enriched = JdLiveApi.room(broadcast.enrich(known), withData: true);
      final after = (legacy['after the list'] as Map<String, dynamic>)['getRoomDetail'];
      _expectParity(_projection(enriched), _result(after)! as Map<String, dynamic>, changed: _afterCard);
      expect((enriched.title, enriched.nick), ('国民喜糖徐福记优选', '徐福记食品店'));
      expect(enriched.cover, known.cover, reason: "28-3: the card's indexImage");
      expect((enriched.data! as JdLiveRoom).background, contains('!q70.jpg'), reason: 'the blurred image');
    });

    test("qualities and lines: 3.x's names and ids; the line has its format, host and media headers (28-5)", () {
      final legacy = _legacy('S04-play-live')['recorded'] as Map<String, dynamic>;
      final broadcast = JdLiveApi.play(_sample('S04-play-live').body, liveId: _live);
      final qualities = JdLiveApi.qualities(broadcast);
      final expected = _maps(_result(legacy['getRoomDetail → getPlayQualites']));
      expect(qualities.map((quality) => (quality.quality, quality.id, quality.sort)), [
        for (final quality in expected) (quality['quality'], quality['id'], quality['sort']),
      ]);
      for (final id in ['hls', 'flv']) {
        final line = JdLiveApi.line(broadcast, id);
        final urls = (_result(legacy['getRoomDetail → resolvePlayUrlsRaw($id)'])! as Map<String, dynamic>)['urls'];
        expect([line.url], urls, reason: id);
        expect(line.format, id == 'hls' ? StreamFormat.hls : StreamFormat.flv);
        expect(line.lineId, 'zt-pull-ai.jdcloud.com');
        expect(line.headers, {
          'origin': 'https://lives.jd.com',
          'referer': 'https://lives.jd.com/#/$_live',
          'user-agent': JdLiveApi.userAgent,
        }, reason: "28-5: the web's media headers (3.x's player sent none)");
        expect(line.lease, isNull, reason: 'no signature or expiry');
        expect(line.codec, isNull);
      }
      expect(JdLiveApi.line(broadcast, 'hls').url, '$_stream.m3u8');
      expect(() => JdLiveApi.line(broadcast, 'auto'), throwsArgumentError);
      expect(() => JdLiveApi.line(broadcast, JdLiveApi.replayId), throwsA(isA<StreamUnavailable>()));
    });

    test("the playlist check matches 3.x's validatePlaylist", () {
      final legacy = _legacy('S04-playlist');
      final hls = Uri.parse('$_stream.m3u8');
      final recorded = _sample('S04-playlist').body;
      final segment = recorded.trim().split('\n').last;
      final bodies = <String, String>{
        'recorded': recorded,
        'CRLF': recorded.replaceAll('\n', '\r\n'),
        'leading blank': '\n  $recorded',
        'other stem': recorded.replaceAll('F366C61365FB1F9B4BC62D90DBE239B1_fhd', 'OTHER_fhd'),
        'absolute same host': recorded.replaceFirst(segment, 'https://zt-pull-ai.jdcloud.com/live/$segment'),
        'absolute other host': recorded.replaceFirst(segment, 'https://example.com/live/$segment'),
        'absolute http': recorded.replaceFirst(segment, 'http://zt-pull-ai.jdcloud.com/live/$segment'),
        'host in another case': recorded.replaceFirst(segment, 'https://ZT-PULL-AI.jdcloud.com/live/$segment'),
        'port 443': recorded.replaceFirst(segment, 'https://zt-pull-ai.jdcloud.com:443/live/$segment'),
        'other port': recorded.replaceFirst(segment, 'https://zt-pull-ai.jdcloud.com:8443/live/$segment'),
        'outside /live/': recorded.replaceFirst(segment, '../vod/$segment'),
        'root-relative': recorded.replaceFirst(segment, '/live/$segment'),
        'fragment': recorded.replaceFirst(segment, '$segment#x'),
        'user info': recorded.replaceFirst(segment, 'https://u@zt-pull-ai.jdcloud.com/live/$segment'),
        'URI attribute same stream': recorded.replaceFirst(
          '#EXT-X-DISCONTINUITY\n',
          '#EXT-X-MAP:URI="F366C61365FB1F9B4BC62D90DBE239B1_fhd-init.mp4"\n',
        ),
        'URI attribute other stream': recorded.replaceFirst(
          '#EXT-X-DISCONTINUITY\n',
          '#EXT-X-KEY:URI="https://example.com/k"\n',
        ),
        'only tags': '#EXTM3U\n#EXT-X-VERSION:3\n',
        'only a URI attribute': '#EXTM3U\n#EXT-X-MAP:URI="F366C61365FB1F9B4BC62D90DBE239B1_fhd-init.mp4"\n',
        'not a playlist': '<html></html>',
        'empty': '',
        '1000 segments': '#EXTM3U\n${List.filled(1000, segment).join('\n')}\n',
        '1001 segments': '#EXTM3U\n${List.filled(1001, segment).join('\n')}\n',
        'over 1 MiB': '#EXTM3U\n$segment\n#${'x' * (1024 * 1024)}\n',
      };
      expect(bodies.keys.toSet(), legacy.keys.toSet());
      for (final MapEntry(key: name, value: body) in bodies.entries) {
        if (legacy[name] == 'ok') {
          expect(() => JdLiveApi.checkPlaylist(body, expected: hls), returnsNormally, reason: name);
        } else {
          expect(() => JdLiveApi.checkPlaylist(body, expected: hls), throwsA(isA<ApiChanged>()), reason: name);
        }
      }
      expect(() => JdLiveApi.checkPlaylist('%zz\n', expected: hls), throwsA(isA<ApiChanged>()));
    });

    test('a playlist 404 is StreamUnavailable (3.x: "missing", the room not found); other statuses as the API', () {
      final legacy = _legacy('S04-play-live')['playlist 404'] as Map<String, dynamic>;
      expect(_failure(_result(legacy['getRoomDetail'])), 'missing');
      final hls = Uri.parse('$_stream.m3u8');
      expect(() => JdLiveApi.checkPlaylist('', expected: hls, status: 404), throwsA(isA<StreamUnavailable>()));
      expect(() => JdLiveApi.checkPlaylist('', expected: hls, status: 403), throwsA(isA<RiskControl>()));
      expect(() => JdLiveApi.checkPlaylist('', expected: hls, status: 502), throwsA(isA<NetworkFailure>()));
    });
  });

  group('S05 upgrades (M4.U.28, no 3.x output)', () {
    test('28-1: the list goes on while a page has broadcasts; the last one (20) is not 30, the empty one ends', () {
      final first = JdLiveApi.directory(_sample('S05-list-p1').body, page: 1);
      expect((first.rooms.length, first.nextCount, first.hasMore), (30, 37, true));
      final last = JdLiveApi.directory(_sample('S05-list-p7').body, page: 7, after: 187);
      expect((last.rooms.length, last.nextCount, last.hasMore), (20, 215, true), reason: '3.x stopped here (< 30)');
      final entries = ((jsonDecode(_sample('S05-list-p7').body) as Map)['data'] as Map)['list'] as List;
      expect(
        [for (final entry in entries) (entry as Map)['templateType']].where((type) => type == 3),
        hasLength(8),
        reason: "official replays are not the featured list's broadcasts (skipped, as 3.x)",
      );
      final end = JdLiveApi.directory(_sample('S05-list-p8').body, page: 8, after: 215);
      expect(end.rooms, isEmpty);
      expect((end.nextCount, end.hasMore), (215, false));
      final stuck = JdLiveApi.directory(_sample('S05-list-p7').body, page: 8, after: 215);
      expect(stuck.hasMore, isFalse, reason: 'currentCount did not move on');
    });

    test('fault tolerance: an unreadable entry is skipped; a page of nothing but unreadable entries fails', () {
      final one = _editedList('S05-list-p7', (json) {
        final list = (json['data'] as Map)['list'] as List;
        final entry = list.firstWhere((entry) => (entry as Map)['templateType'] == 1) as Map;
        (entry['data'] as Map)['title'] = ['not text'];
        list.add({'templateType': 1, 'data': 7});
      });
      final page = JdLiveApi.directory(one, page: 7, after: 187);
      expect((page.rooms.length, page.hasMore), (19, true));
      final none = _editedList('S05-list-p7', (json) => (json['data'] as Map)['list'] = [5, 'x', null]);
      expect(() => JdLiveApi.directory(none, page: 7), throwsA(isA<ApiChanged>()));
      final promotions = _editedList(
        'S05-list-p7',
        (json) => (json['data'] as Map)['list'] = [
          {'templateType': -100, 'cardId': '28'},
        ],
      );
      expect(JdLiveApi.directory(promotions, page: 7).rooms, isEmpty, reason: 'nothing unreadable');
    });

    test('a replay plays its recording on JD Cloud video (the unified replay rule): one quality "原画"', () {
      final replay = JdLiveApi.play(_sample('S05-play-replay').body, liveId: _live);
      expect(replay.state, JdLiveState.replay);
      expect(replay.recording, Uri.parse(_recording));
      expect((replay.hls, replay.flv), (null, null), reason: 'the three fields hold the recording');
      expect((replay.restriction, replay.streamError), (LiveRestriction.none, null));
      final room = JdLiveApi.room(replay, withData: true);
      expect((room.liveStatus, room.isRecord, room.isPlayableNow), (LiveStatus.replay, true, true));
      expect(room.followGroup, FollowGroup.replay);
      expect((room.title, room.nick, room.cover), ('', '', ''), reason: '28-2, 28-3');
      expect(JdLiveApi.qualities(replay), [JdLiveApi.replayQuality]);
      expect((JdLiveApi.replayQuality.quality, JdLiveApi.replayQuality.id), ('原画', 'replay'));
      final line = JdLiveApi.line(replay, JdLiveApi.replayId);
      expect((line.url, line.format, line.lineId), (_recording, StreamFormat.hls, 'discover.300hu.com'));
      expect(line.headers, JdLiveApi.mediaHeaders(_live), reason: '28-5');
      expect(() => JdLiveApi.line(replay, JdLiveApi.hlsId), throwsA(isA<StreamUnavailable>()));
      for (final (name, value) in [
        ('other host', _recording.replaceFirst('discover.300hu.com', 'example.com')),
        ('http', _recording.replaceFirst('https:', 'http:')),
        ('not a playlist', _recording.replaceFirst('.m3u8?', '.mp4?')),
        ('a live stream', '$_stream.m3u8'),
      ]) {
        final edited = JdLiveApi.play(
          _editedPlay({'h5VideoUrl': value, 'videoUrl': value, 'pcVideoUrl': value}, sample: 'S05-play-replay'),
          liveId: _live,
        );
        expect((edited.recording, edited.restriction), (null, LiveRestriction.unplayable), reason: name);
        expect(JdLiveApi.room(edited).followGroup, FollowGroup.offline, reason: name);
      }
      final second = JdLiveApi.play(_editedPlay({'h5VideoUrl': ''}, sample: 'S05-play-replay'), liveId: _live);
      expect(second.recording, Uri.parse(_recording), reason: '`videoUrl` when `h5VideoUrl` is empty');
    });

    test('an ended broadcast still carries its stopped live addresses: offline, not playable', () {
      final ended = JdLiveApi.play(_sample('S05-play-ended').body, liveId: '48378908');
      expect((ended.state, ended.recording), (JdLiveState.offline, null));
      expect(ended.hls, isNotNull);
      expect(ended.streamError, isA<StreamUnavailable>());
      final room = JdLiveApi.room(ended);
      expect((room.liveStatus, room.restriction), (LiveStatus.offline, LiveRestriction.none));
      expect(() => JdLiveApi.line(ended, JdLiveApi.hlsId), throwsA(isA<StreamUnavailable>()));
    });

    test('28-4: the FLV of the playlist stream key; a live answer without any address is live and unplayable', () {
      const other = 'https://zt-pull-ai.jdcloud.com/live/OTHER_fhd.flv';
      final mismatch = JdLiveApi.play(_editedPlay({'videoUrl': other}, sample: 'S04-play-live'), liveId: _live);
      expect(mismatch.flv.toString(), '$_stream.flv', reason: '`pcVideoUrl`, of the same stream as the playlist');
      final noneMatches = JdLiveApi.play(
        _editedPlay({'videoUrl': other, 'pcVideoUrl': other}, sample: 'S04-play-live'),
        liveId: _live,
      );
      expect((noneMatches.hls.toString(), noneMatches.flv), ('$_stream.m3u8', null));
      expect(JdLiveApi.qualities(noneMatches), [JdLiveApi.hlsQuality]);
      final flvOnly = JdLiveApi.play(
        _editedPlay({'h5VideoUrl': null, 'videoUrl': other}, sample: 'S04-play-live'),
        liveId: _live,
      );
      expect(flvOnly.flv.toString(), other, reason: 'without a playlist any JD FLV does');
      expect(() => JdLiveApi.line(flvOnly, JdLiveApi.hlsId), throwsA(isA<StreamUnavailable>()));
      final bare = JdLiveApi.play(
        _editedPlay({'h5VideoUrl': 1, 'videoUrl': null, 'pcVideoUrl': 'x'}, sample: 'S04-play-live'),
        liveId: _live,
      );
      expect((bare.state, bare.restriction), (JdLiveState.live, LiveRestriction.unplayable));
      expect(bare.streamError, isA<StreamUnavailable>());
      final room = JdLiveApi.room(bare);
      expect((room.liveStatus, room.followGroup), (LiveStatus.live, FollowGroup.live));
    });

    test('28-7 blocked: the unsigned shop playback list has titles, covers and start times, no names or live one', () {
      // livePlayBackToM (the web's shop replay tab) takes the shop account
      // and lists past broadcasts only.
      final shop = (jsonDecode(_sample('S05-playback').body) as Map)['data'] as List;
      final ended = shop.cast<Map<String, dynamic>>().firstWhere((entry) => entry['liveId'] == _live);
      expect(ended['title'], '国民喜糖徐福记优选');
      expect(ended['beginTime'], 1790012438000, reason: 'the start in the recording address too');
      expect(_recording, contains('_1790012438_'));
      expect(shop.cast<Map<String, dynamic>>().every((entry) => !entry.containsKey('userName')), isTrue);
      final card = JdLiveApi.directory(_sample('S05-list-p1').body, page: 1).rooms.first;
      expect((card.state, card.authorId), (JdLiveState.live, '26206329'));
      expect(_sample('S05-playback-live').url.queryParameters['body'], contains(card.authorId));
      final listed = ((jsonDecode(_sample('S05-playback-live').body) as Map)['data'] as List)
          .map((entry) => (entry as Map)['liveId'])
          .toList();
      expect(listed, isNot(contains(card.liveId)), reason: "the shop's current broadcast is not in it");
    });
  });

  group('M5.24 chat', () {
    test('a live room entry carries its chat arguments; refresh, app-only and not live rooms do not', () {
      final live = JdLiveApi.play(_sample('S04-play-live').body, liveId: _live);
      final args = JdLiveApi.room(live, withData: true).danmakuData;
      expect(args, isA<JdLiveDanmakuArgs>().having((args) => args.liveId, 'liveId', _live));
      expect('$args', 'JdLiveDanmakuArgs($_live)');
      expect(JdLiveApi.room(live).danmakuData, isNull, reason: 'a refresh or a card: no request, no chat');
      final withoutData = [
        ('app-only', JdLiveApi.play(_editedPlay({'secret': 1}), liveId: _archivedLive)),
        ('ended', JdLiveApi.play(_sample('S05-play-ended').body, liveId: '48378908')),
        ('replay', JdLiveApi.play(_sample('S05-play-replay').body, liveId: _live)),
        ('paused', JdLiveApi.play(_editedPlay({'status': 10}), liveId: _archivedLive)),
        ('preview', JdLiveApi.play(_editedPlay({'status': 0}), liveId: _archivedLive)),
      ];
      for (final (name, broadcast) in withoutData) {
        expect(JdLiveApi.room(broadcast, withData: true).danmakuData, isNull, reason: name);
      }
      final unplayable = JdLiveApi.play(
        _editedPlay({'h5VideoUrl': 1, 'videoUrl': null, 'pcVideoUrl': 'x'}, sample: 'S04-play-live'),
        liveId: _live,
      );
      expect(
        JdLiveApi.room(unplayable, withData: true).danmakuData,
        isA<JdLiveDanmakuArgs>(),
        reason: 'live without an address: its chat still runs',
      );
    });

    test('the notice only explains the number now; the chat gives the viewers in the room', () {
      expect(JdLiveApi.chatNotice, '列表里的人数是累计观看；直播中连上弹幕后，显示的是正在观看的人数。');
      expect(JdLiveApi.chatNotice, isNot(contains('聊天')), reason: 'M5.24: chat is shown');
      final capability = AudiencePlatformCapability.of('jdlive');
      expect(capability.onlineAvailability, AudienceOnlineAvailability.roomRealtime);
      expect((capability.hasTotalViewers, capability.hasPopularity), (true, false));
    });
  });
}
