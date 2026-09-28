// JD Live parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/jdlive/legacy_expected.dart from 3.x's JdLiveApi, JdLiveLink and
// JdLiveSite). Every intended difference is listed with its reason;
// everything else must match. The synthetic cases are the edited copies the
// generator ran through 3.x (`variants`) and 3.x's jd_live_site_test.dart.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('jdlive', name);

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

/// The `result` of a traced legacy call.
Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

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

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {String reason = ''}) {
  final expected = _maps(legacy);
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(_projection(room), expected[index], reason: '$reason[$index]');
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

void _expectPage(JdLivePage page, Object? legacy, {int? rooms, String reason = ''}) {
  final expected = legacy! as Map<String, dynamic>;
  expect(page.nextCount, expected['nextCount'], reason: reason);
  expect(page.hasMore, expected['hasMore'], reason: reason);
  final listed = expected['rooms'];
  if (listed is int) {
    expect(page.rooms, hasLength(listed), reason: reason);
    return;
  }
  final broadcasts = _maps(listed);
  final actual = rooms == null ? page.rooms : page.rooms.take(rooms).toList();
  expect(actual.map(_broadcast), broadcasts, reason: reason);
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

/// S02-play-live's JSON with `data` fields replaced (null removes one) and
/// root fields in [root].
String _editedPlay(Map<String, Object?> data, {Map<String, Object?> root = const {}}) {
  final json = jsonDecode(_sample('S02-play-live').body) as Map<String, dynamic>;
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
    });

    test('page 2: 30 more, none repeated, currentCount 67', () {
      final page = JdLiveApi.directory(_sample('S01-list-p2').body, page: 2);
      _expectPage(page, _legacy('S01-list-p2')['parseDirectoryJson']);
      final first = JdLiveApi.directory(_sample('S01-list-p1').body, page: 1);
      expect(
        page.rooms.map((room) => room.liveId).toSet().intersection(first.rooms.map((room) => room.liveId).toSet()),
        isEmpty,
      );
      expect(page.nextCount, 67);
    });

    test("the cards as rooms: every field of 3.x's directory pages 1 and 2", () {
      final pages = _legacy('S01-list-p1')['getDirectoryPage'] as Map<String, dynamic>;
      for (final (sample, page) in [('S01-list-p1', 1), ('S01-list-p2', 2)]) {
        final rooms = [
          for (final card in JdLiveApi.directory(_sample(sample).body, page: page).rooms) JdLiveApi.room(card),
        ];
        final legacy = _result(pages['page $page'])! as Map<String, dynamic>;
        _expectRooms(rooms, legacy['rooms'], reason: 'page $page');
      }
      final card = JdLiveApi.room(JdLiveApi.directory(_sample('S01-list-p1').body, page: 1).rooms.first);
      expect(card.userId, '24304104', reason: 'the shop account');
      expect(card.area, 'JD Live');
      expect(card.effectiveTotalViewers, '37', reason: 'pv is cumulative (REG-COMMON-004)');
      expect(card.effectiveOnlineViewers, isEmpty);
      expect(card.httpHeaders, JdLiveApi.mediaHeaders(_archivedLive), reason: "3.x's room headers (in the 3.x JSON)");
      expect(card.data, isNull, reason: 'a card cannot be played');
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
      for (final MapEntry(key: name, value: body) in bodies.entries) {
        final legacy = variants[name];
        final failure = _failure(legacy);
        if (failure != null) {
          expect(() => JdLiveApi.directory(body, page: 1), _typed(failure), reason: name);
        } else {
          _expectPage(JdLiveApi.directory(body, page: 1), legacy, rooms: 2, reason: name);
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
    test("the live answer: state, cover and one stream key, no names (3.x's parseRoomJson)", () {
      final room = JdLiveApi.play(_sample('S02-play-live').body, liveId: _archivedLive);
      expect(_broadcast(room), _legacy('S02-play-live')['parseRoomJson']);
      expect(room.state, JdLiveState.live);
      expect(room.nick, JdLiveApi.siteName, reason: 'the answer has no names');
      expect(room.streamError, isNull);
      expect(
        () => JdLiveApi.play(_sample('S02-play-live').body, liveId: '48378945'),
        throwsA(isA<ApiChanged>()),
        reason: "3.x's identity check: an answer for another broadcast",
      );
    });

    test('the room at refresh depth matches 3.x: the placeholder names, the cover as avatar, no views', () {
      final legacy = (_legacy('S02-play-live')['recorded'] as Map<String, dynamic>)['getRoomDetailForRefresh'];
      final room = JdLiveApi.room(JdLiveApi.play(_sample('S02-play-live').body, liveId: _archivedLive));
      _expectParity(_projection(room), _result(legacy)! as Map<String, dynamic>);
      expect((room.title, room.nick, room.userId), ('JD Live', 'JD Live', _archivedLive));
      expect(room.avatar, room.cover);
      expect(room.effectiveAudienceMetricType, AudienceMetricType.unknown);
      expect(room.data, isNull);
    });

    test('the list card completes the play answer (3.x enrich): names, account, avatar, views; cover stays', () {
      final known = JdLiveApi.directory(_sample('S01-list-p1').body, page: 1).rooms.first;
      final room = JdLiveApi.play(_sample('S02-play-live').body, liveId: _archivedLive).enrich(known);
      final legacy =
          (_legacy('S01-list-p1')['known'] as Map<String, dynamic>)['getRoomDetailForRefresh after the list'];
      _expectParity(_projection(JdLiveApi.room(room)), _result(legacy)! as Map<String, dynamic>);
      expect(room.cover, isNot(known.cover), reason: "3.x kept the play answer's blurredImg");
      expect(room.hls, isNotNull);
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
      for (final MapEntry(key: name, value: body) in bodies.entries) {
        final legacy = variants[name] as Map<String, dynamic>;
        final refresh = legacy['getRoomDetailForRefresh'];
        final failure = _failure(refresh);
        if (failure != null) {
          expect(() => JdLiveApi.play(body, liveId: _archivedLive), _typed(failure), reason: name);
          continue;
        }
        final broadcast = JdLiveApi.play(body, liveId: _archivedLive);
        _expectParity(_projection(JdLiveApi.room(broadcast)), refresh! as Map<String, dynamic>, reason: name);
        _expectParity(
          _projection(JdLiveApi.room(broadcast, withData: true)),
          legacy['getRoomDetail']! as Map<String, dynamic>,
          reason: '$name entry',
        );
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
          expect(broadcast.streamError, isA<SiteError>(), reason: name);
        }
      }
    });

    test('states: app-only is NeedsLogin, others not live are StreamUnavailable (3.x: mediaUnavailable)', () {
      final restricted = JdLiveApi.play(_editedPlay({'secret': 1}), liveId: _archivedLive);
      expect(restricted.state, JdLiveState.restricted);
      expect(restricted.streamError, isA<NeedsLogin>());
      final room = JdLiveApi.room(restricted, withData: true);
      expect((room.liveStatus, room.notice), (LiveStatus.unknown, JdLiveApi.restrictedNotice));
      for (final (status, state, liveStatus) in [
        (0, JdLiveState.preview, LiveStatus.offline),
        (2, JdLiveState.offline, LiveStatus.offline),
        (3, JdLiveState.replay, LiveStatus.offline),
        (10, JdLiveState.paused, LiveStatus.unknown),
        (11, JdLiveState.paused, LiveStatus.unknown),
        (99, JdLiveState.unknown, LiveStatus.unknown),
      ]) {
        final broadcast = JdLiveApi.play(_editedPlay({'status': status}), liveId: _archivedLive);
        expect(broadcast.state, state, reason: '$status');
        expect(broadcast.streamError, isA<StreamUnavailable>(), reason: '$status');
        expect(JdLiveApi.room(broadcast).liveStatus, liveStatus, reason: '$status');
      }
      expect(JdLiveApi.state(1, secret: '1'), JdLiveState.restricted);
      expect(JdLiveApi.state(1.0), JdLiveState.live);
      expect(JdLiveApi.state(true), JdLiveState.unknown);
    });

    test('the old id: status 3 without addresses is offline (3.x: not replay)', () {
      final legacy = _legacy('S02-play-old');
      final room = JdLiveApi.play(_sample('S02-play-old').body, liveId: '10000');
      expect(_broadcast(room), legacy['parseRoomJson']);
      for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        final expected = _result((legacy['recorded'] as Map<String, dynamic>)[depth])! as Map<String, dynamic>;
        _expectParity(_projection(JdLiveApi.room(room, withData: depth != 'getRoomDetailForRefresh')), expected);
      }
      expect(JdLiveApi.room(room).liveStatus, LiveStatus.offline);
      expect(room.streamError, isA<StreamUnavailable>());
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
    test('the list page has 29 broadcasts: 3.x does not ask for page 2', () {
      final page = JdLiveApi.directory(_sample('S04-list').body, page: 1);
      _expectPage(page, _legacy('S04-list')['parseDirectoryJson']);
      expect((page.rooms.length, page.nextCount, page.hasMore), (29, 36, false));
    });

    test('room entry: every field of 3.x, with the play answer as data', () {
      final legacy = _legacy('S04-play-live');
      final broadcast = JdLiveApi.play(_sample('S04-play-live').body, liveId: _live);
      expect(_broadcast(broadcast), legacy['parseRoomJson']);
      final recorded = legacy['recorded'] as Map<String, dynamic>;
      for (final depth in ['getRoomDetail', 'getRoomDetailForRecording']) {
        final room = JdLiveApi.room(broadcast, withData: true);
        _expectParity(_projection(room), _result(recorded[depth])! as Map<String, dynamic>, reason: depth);
        expect(room.data, same(broadcast));
      }
      final known = JdLiveApi.directory(_sample('S04-list').body, page: 1).rooms.first;
      final enriched = JdLiveApi.room(broadcast.enrich(known), withData: true);
      final after = (legacy['after the list'] as Map<String, dynamic>)['getRoomDetail'];
      _expectParity(_projection(enriched), _result(after)! as Map<String, dynamic>);
      expect((enriched.title, enriched.nick), ('国民喜糖徐福记优选', '徐福记食品店'));
    });

    test("qualities and lines: 3.x's names and ids; the line has its format and host, no headers or lease", () {
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
        expect(line.headers, isEmpty, reason: "3.x's player had no JD headers (PlaybackHeaderResolver)");
        expect(line.lease, isNull, reason: 'no signature or expiry');
        expect(line.codec, isNull);
      }
      expect(JdLiveApi.line(broadcast, 'hls').url, '$_stream.m3u8');
      expect(() => JdLiveApi.line(broadcast, 'auto'), throwsArgumentError);
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
}
