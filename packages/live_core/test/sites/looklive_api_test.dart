// LOOK Live parsing against the recorded samples, compared field by field
// with 3.x's frozen output (expected.json, written by
// fixtures/looklive/legacy_expected.dart from 3.x's LookLiveApi, LookLiveLink
// and LookLiveSite). Every intended difference is listed with its reason
// (`changed:` and the upgrade item, docs/specs/UPGRADES.md 32-x); everything else
// must match. The synthetic cases are the edited copies the generator ran
// through 3.x (`variants`) and 3.x's look_live_site_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('looklive', name);

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

/// The `result` of a traced legacy call.
Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

/// Changed on every room: the notices are in words for users (M4.U, the
/// unified rule on notices), and M5.28 shows LOOK chat, so the chat notice
/// no longer says it is missing; asserted by their own tests.
const _notice = {'notice'};

/// Changed for an ended or banned room after a list card of the same
/// broadcast: the card's heat and viewers are no longer taken (32-5).
const _audience = {'watching', 'audienceMetricType', 'popularity', 'onlineViewers'};

/// Changed on 3.x's projection of a list card: the stream type is the
/// card's `type` (32-4; 3.x read `liveStreamType`, which the lists lack),
/// so a type 50 card without streams is app-only.
const _card = {'streamType', 'isAppOnly'};

/// Asserts that [actual] (a `toJson`) equals 3.x's [legacy] map on every key
/// 3.x wrote, except [changed] (intended differences). 3.x wrote null where
/// the immutable model writes '' (the viewers and heat of a room without
/// them, the area's `areaPic`).
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

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {Set<String> changed = _notice, String reason = ''}) {
  final expected = _maps(legacy);
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(_projection(room), expected[index], changed: changed, reason: '$reason[$index]');
  }
}

Map<String, Object?> _without(Map<String, Object?> map, Set<String> keys) => {
  for (final MapEntry(:key, :value) in map.entries)
    if (!keys.contains(key)) key: value,
};

/// 3.x's projection of a `LookLiveRoom`.
Map<String, Object?> _lookRoom(LookLiveRoom room) => {
  'roomId': room.roomId,
  'userId': room.userId,
  'sessionId': room.sessionId,
  'title': room.title,
  'nick': room.nick,
  'avatar': room.avatar,
  'cover': room.cover,
  'kind': room.kind.name,
  'streamType': room.streamType,
  'state': room.state.name,
  'popularity': room.popularity,
  'currentViewers': room.currentViewers,
  'isAppOnly': room.isAppOnly,
  'variants': [
    for (final variant in room.variants) {'id': variant.id, 'protocol': variant.format.name, 'uri': '${variant.uri}'},
  ],
};

Map<String, Object?> _lookPage(LookLivePage page, {int? take}) => {
  'rooms': [for (final room in take == null ? page.rooms : page.rooms.take(take)) _lookRoom(room)],
  'hasMore': page.hasMore,
};

/// Asserts that [page] is 3.x's [legacy] `directory` page (its first
/// [take] rooms) but for the list cards' [_card] keys (32-4).
void _expectLookPage(LookLivePage page, Object? legacy, {int? take, String reason = ''}) {
  final expected = legacy! as Map<String, dynamic>;
  final actual = _lookPage(page, take: take);
  expect(actual['hasMore'], expected['hasMore'], reason: reason);
  expect(
    [for (final room in actual['rooms']! as List) _without(room as Map<String, Object?>, _card)],
    [for (final room in _maps(expected['rooms'])) _without(room, _card)],
    reason: reason,
  );
}

/// 3.x's failure kind of a legacy error projection (`LOOK Live <kind>`),
/// or null when it did not fail.
String? _failure(Object? legacy) {
  if (legacy is! Map || legacy['throws'] != 'LookLiveException') return null;
  return (legacy['message']! as String).replaceFirst('LOOK Live ', '');
}

/// The `SiteError` a 3.x failure kind of the parsing layer is now: the
/// answer's shape and codes are `ApiChanged` ("service" here is a JSON
/// `code`; HTTP 5xx is covered with the statuses).
Matcher _typed(String kind) => throwsA(switch (kind) {
  'schema' || 'identity' || 'service' => isA<ApiChanged>(),
  'missing' => isA<NotFound>(),
  'access' => isA<RiskControl>(),
  'rateLimited' => isA<RateLimited>(),
  'transport' => isA<NetworkFailure>(),
  'mediaUnavailable' => isA<StreamUnavailable>(),
  _ => throw ArgumentError(kind),
});

const _video = '21623631';
const _audio = '181408025';
const _offline = '325808387';
const _appOnly = '645235480';

/// The recorded video list's first card (the room of S03-room-video).
LookLiveRoom _videoCard() => LookLiveApi.directory(_sample('S01-video-p1').body, kind: LookLiveKind.video).rooms.first;

String _body(String sample) => _sample(sample).body;

/// [sample]'s list with the `liveData` of item [index] edited by [edit].
String _editedLive(String sample, void Function(Map<String, dynamic> live) edit, {int index = 0}) {
  final json = jsonDecode(_body(sample)) as Map<String, dynamic>;
  final items = (json['data'] as Map<String, dynamic>)['itemList'] as List;
  edit((items[index] as Map<String, dynamic>)['liveData'] as Map<String, dynamic>);
  return jsonEncode(json);
}

String _editedItem(String sample, void Function(Map<String, dynamic> item) edit) {
  final json = jsonDecode(_body(sample)) as Map<String, dynamic>;
  edit(((json['data'] as Map<String, dynamic>)['itemList'] as List).first as Map<String, dynamic>);
  return jsonEncode(json);
}

String _editedRoot(String sample, void Function(Map<String, dynamic> json) edit) {
  final json = jsonDecode(_body(sample)) as Map<String, dynamic>;
  edit(json);
  return jsonEncode(json);
}

String _editedRoom(
  String sample,
  void Function(Map<String, dynamic> data, Map<String, dynamic> info, Map<String, dynamic> anchor) edit,
) {
  final json = jsonDecode(_body(sample)) as Map<String, dynamic>;
  final data = json['data'] as Map<String, dynamic>;
  edit(data, data['roomInfo'] as Map<String, dynamic>, data['anchor'] as Map<String, dynamic>);
  return jsonEncode(json);
}

/// The edited copies of S01-video-p1 the generator ran through 3.x's
/// `directory` (legacy_expected.dart `_listVariants`).
Map<String, String> _listVariants() {
  Map<String, dynamic> user(Map<String, dynamic> live) => live['userInfo'] as Map<String, dynamic>;
  Map<String, dynamic> urls(Map<String, dynamic> live) => live['liveUrl'] as Map<String, dynamic>;
  String live(void Function(Map<String, dynamic> live) edit, {int index = 0}) =>
      _editedLive('S01-video-p1', edit, index: index);
  String item(void Function(Map<String, dynamic> item) edit) => _editedItem('S01-video-p1', edit);
  String root(void Function(Map<String, dynamic> json) edit) => _editedRoot('S01-video-p1', edit);
  String data(void Function(Map<String, dynamic> data) edit) =>
      root((json) => edit(json['data'] as Map<String, dynamic>));
  const flv = 'http://pull0583d674.live.126.net/live/800897349fe246e994f36976011de4d5.flv';
  const hls = 'http://pull0583d674.live.126.net/live/800897349fe246e994f36976011de4d5/playlist.m3u8';
  final items = ((jsonDecode(_body('S01-video-p1')) as Map)['data'] as Map)['itemList'] as List;
  return {
    'recorded': _body('S01-video-p1'),
    'type number 1': item((i) => i['type'] = 1),
    'type 2': item((i) => i['type'] = '2'),
    'type missing': item((i) => i.remove('type')),
    'liveData null': item((i) => i['liveData'] = null),
    'liveData text': item((i) => i['liveData'] = 'x'),
    'item not an object': data((d) => (d['itemList'] as List).insert(0, 5)),
    'liveType 2': live((l) => l['liveType'] = 2),
    'liveType 3': live((l) => l['liveType'] = 3),
    'liveType text': live((l) => l['liveType'] = '1'),
    'liveType missing': live((l) => l.remove('liveType')),
    'userInfo missing': live((l) => l.remove('userInfo')),
    'liveRoomNo text': live((l) => user(l)['liveRoomNo'] = _video),
    'liveRoomNo spaced text': live((l) => user(l)['liveRoomNo'] = ' $_video '),
    'liveRoomNo 0': live((l) => user(l)['liveRoomNo'] = 0),
    'liveRoomNo one digit': live((l) => user(l)['liveRoomNo'] = 7),
    'liveRoomNo 19 digits': live((l) => user(l)['liveRoomNo'] = int.parse('1234567890123456789')),
    'liveRoomNo missing': live((l) => user(l).remove('liveRoomNo')),
    'userId missing': live((l) => user(l).remove('userId')),
    'liveId missing': live((l) => l.remove('liveId')),
    'liveTitle missing': live((l) => l.remove('liveTitle')),
    'liveTitle number': live((l) => l['liveTitle'] = 5),
    'liveTitle spaced': live((l) => l['liveTitle'] = '  a  b \n'),
    'nickname missing': live((l) => user(l).remove('nickname')),
    'avatarUrl missing': live((l) => user(l).remove('avatarUrl')),
    'avatarUrl https': live((l) => user(l)['avatarUrl'] = 'https://p3.music.126.net/a.jpg'),
    'avatarUrl with port': live((l) => user(l)['avatarUrl'] = 'http://p3.music.126.net:8080/a.jpg'),
    'avatarUrl protocol-relative': live((l) => user(l)['avatarUrl'] = '//p3.music.126.net/a.jpg'),
    'avatarUrl ftp': live((l) => user(l)['avatarUrl'] = 'ftp://p3.music.126.net/a.jpg'),
    'avatarUrl user info': live((l) => user(l)['avatarUrl'] = 'http://u@p3.music.126.net/a.jpg'),
    'avatarUrl fragment': live((l) => user(l)['avatarUrl'] = 'http://p3.music.126.net/a.jpg#x'),
    'avatarUrl other host': live((l) => user(l)['avatarUrl'] = 'http://example.com/a.jpg'),
    'liveCoverUrl missing': live((l) => l.remove('liveCoverUrl')),
    'popularity missing': live((l) => l.remove('popularity')),
    'popularity text': live((l) => l['popularity'] = '12'),
    'popularity negative': live((l) => l['popularity'] = -1),
    'popularity fraction': live((l) => l['popularity'] = 1.5),
    'onlineNumber missing': live((l) => l.remove('onlineNumber')),
    'onlineNumber zero': live((l) => l['onlineNumber'] = 0),
    'onlineNumber negative': live((l) => l['onlineNumber'] = -3),
    'onlineNumber text': live((l) => l['onlineNumber'] = '9'),
    'liveUrl null': live((l) => l['liveUrl'] = null),
    'liveUrl text': live((l) => l['liveUrl'] = 'x'),
    'liveUrl empty': live((l) => l['liveUrl'] = <String, Object?>{}),
    'hlsPullUrl missing': live((l) => urls(l).remove('hlsPullUrl')),
    'httpPullUrl empty': live((l) => urls(l)['httpPullUrl'] = ''),
    'hlsPullUrl https': live((l) => urls(l)['hlsPullUrl'] = hls.replaceFirst('http:', 'https:')),
    'hlsPullUrl with query': live((l) => urls(l)['hlsPullUrl'] = '$hls?netease=x'),
    'hlsPullUrl upper-case scheme': live((l) => urls(l)['hlsPullUrl'] = hls.replaceFirst('http:', 'HTTP:')),
    'hlsPullUrl spaced': live((l) => urls(l)['hlsPullUrl'] = ' $hls '),
    'hlsPullUrl other host': live(
      (l) => urls(l)['hlsPullUrl'] = hls.replaceFirst('pull0583d674.live.126.net', 'example.com'),
    ),
    'hlsPullUrl lookalike host': live(
      (l) => urls(l)['hlsPullUrl'] = hls.replaceFirst('live.126.net', 'live.126.net.evil.test'),
    ),
    'hlsPullUrl with port': live((l) => urls(l)['hlsPullUrl'] = hls.replaceFirst('.net/', '.net:8080/')),
    'hlsPullUrl user info': live((l) => urls(l)['hlsPullUrl'] = hls.replaceFirst('//', '//u@')),
    'hlsPullUrl fragment': live((l) => urls(l)['hlsPullUrl'] = '$hls#x'),
    'hlsPullUrl upper-case key': live(
      (l) => urls(l)['hlsPullUrl'] = hls.replaceFirst('800897349fe246e9', '800897349FE246E9'),
    ),
    'hlsPullUrl as FLV': live((l) => urls(l)['hlsPullUrl'] = flv),
    'hlsPullUrl rtmp': live((l) => urls(l)['hlsPullUrl'] = hls.replaceFirst('http:', 'rtmp:')),
    'hlsPullUrl long query': live((l) => urls(l)['hlsPullUrl'] = '$hls?${'a' * 2049}'),
    'httpPullUrl number': live((l) => urls(l)['httpPullUrl'] = 7),
    'httpPullUrl without query': live((l) => urls(l)['httpPullUrl'] = flv),
    'httpPullUrl as HLS': live((l) => urls(l)['httpPullUrl'] = hls),
    'liveStreamType 50 without liveUrl': live((l) {
      l['liveStreamType'] = 50;
      l['liveUrl'] = null;
    }),
    'second card repeats the first': live((l) => user(l)['liveRoomNo'] = int.parse(_video), index: 1),
    'itemList null': data((d) => d['itemList'] = null),
    'itemList not a list': data((d) => d['itemList'] = <String, Object?>{}),
    'itemList empty': data((d) => d['itemList'] = <Object?>[]),
    'itemList 100 entries': data((d) => d['itemList'] = List.filled(100, items.first)),
    'itemList 101 entries': data((d) => d['itemList'] = List.filled(101, items.first)),
    'hasMore missing': data((d) => d.remove('hasMore')),
    'hasMore text': data((d) => d['hasMore'] = 'true'),
    'hasMore true': data((d) => d['hasMore'] = true),
    'code 404': root((j) => j['code'] = 404),
    'code 424': root((j) => j['code'] = 424),
    'code 520': root((j) => j['code'] = 520),
    'code 522': root((j) => j['code'] = 522),
    'code 555': root((j) => j['code'] = 555),
    'code 500': root((j) => j['code'] = 500),
    'code 301': root((j) => j['code'] = 301),
    'code text': root((j) => j['code'] = '200'),
    'code missing': root((j) => j.remove('code')),
    'data null': root((j) => j['data'] = null),
    'data list': root((j) => j['data'] = <Object?>[]),
    'root list': '[]',
    'not JSON': '<html></html>',
    'empty body': '',
  };
}

/// List variants 3.x failed on (or, for the room numbers, failed to make
/// rooms of) whose entry is now skipped (32-6).
const _skippedEntries = {
  'liveData text',
  'item not an object',
  'liveType 3',
  'liveType missing',
  'userInfo missing',
  'liveRoomNo 0',
  'liveRoomNo one digit',
  'liveRoomNo 19 digits',
  'liveRoomNo missing',
  'userId missing',
  'liveId missing',
  'popularity negative',
  'popularity fraction',
  'onlineNumber negative',
};

/// List variants with a bad address 3.x failed on, and the streams the
/// first card keeps now (32-6).
const _badAddresses = {
  'liveUrl text': <String>[],
  'hlsPullUrl other host': ['flv:source'],
  'hlsPullUrl lookalike host': ['flv:source'],
  'hlsPullUrl with port': ['flv:source'],
  'hlsPullUrl user info': ['flv:source'],
  'hlsPullUrl fragment': ['flv:source'],
  'hlsPullUrl upper-case key': ['flv:source'],
  'hlsPullUrl as FLV': ['flv:source'],
  'hlsPullUrl rtmp': ['flv:source'],
  'hlsPullUrl long query': ['flv:source'],
  'httpPullUrl as HLS': ['hls:source'],
};

typedef _RoomEdit = void Function(Map<String, dynamic> data, Map<String, dynamic> info, Map<String, dynamic> anchor);

/// The edited copies of S03-room-video the generator ran through 3.x's room
/// calls (legacy_expected.dart `_roomVariants`).
Map<String, String> _roomVariants() {
  const hls = 'http://pull0583d674.live.126.net/live/800897349fe246e994f36976011de4d5/playlist.m3u8';
  Map<String, dynamic> urls(Map<String, dynamic> info) => info['liveUrl'] as Map<String, dynamic>;
  final edits = <String, _RoomEdit>{
    'liveStatus 0': (d, i, a) => d['liveStatus'] = 0,
    'liveStatus -1': (d, i, a) => d['liveStatus'] = -1,
    'liveStatus -10': (d, i, a) => d['liveStatus'] = -10,
    'liveStatus 2': (d, i, a) => d['liveStatus'] = 2,
    'liveStatus text': (d, i, a) => d['liveStatus'] = '1',
    'liveStatus missing': (d, i, a) => d.remove('liveStatus'),
    'liveType 2': (d, i, a) => i['liveType'] = 2,
    'liveType 3': (d, i, a) => i['liveType'] = 3,
    'liveType missing': (d, i, a) => i.remove('liveType'),
    'liveStreamType 50': (d, i, a) => i['liveStreamType'] = 50,
    'liveStreamType 50 without liveUrl': (d, i, a) {
      i['liveStreamType'] = 50;
      i['liveUrl'] = null;
    },
    'liveStreamType missing without liveUrl': (d, i, a) {
      i.remove('liveStreamType');
      i['liveUrl'] = null;
    },
    'liveUrl null': (d, i, a) => i['liveUrl'] = null,
    'liveUrl empty': (d, i, a) => i['liveUrl'] = <String, Object?>{},
    'liveUrl text': (d, i, a) => i['liveUrl'] = 'x',
    'hlsPullUrl missing': (d, i, a) => urls(i).remove('hlsPullUrl'),
    'httpPullUrl missing': (d, i, a) => urls(i).remove('httpPullUrl'),
    'hlsPullUrl other host': (d, i, a) => urls(i)['hlsPullUrl'] = hls.replaceFirst('pull0583d674.live.126.net', 'x.cn'),
    'liveStatus -1 with an invalid hlsPullUrl': (d, i, a) {
      d['liveStatus'] = -1;
      urls(i)['hlsPullUrl'] = 'x';
    },
    'roomInfo missing': (d, i, a) => d.remove('roomInfo'),
    'roomInfo id missing': (d, i, a) => i.remove('id'),
    'anchor missing': (d, i, a) => d.remove('anchor'),
    'anchor liveRoomNo other': (d, i, a) => a['liveRoomNo'] = '21623632',
    'anchor liveRoomNo number': (d, i, a) => a['liveRoomNo'] = int.parse(_video),
    'anchor userId missing': (d, i, a) => a.remove('userId'),
    'title missing': (d, i, a) => i.remove('title'),
    'title spaced': (d, i, a) => i['title'] = '  ASOT \n',
    'nickName number': (d, i, a) => a['nickName'] = 3,
    'avatarUrl missing': (d, i, a) => a.remove('avatarUrl'),
    'avatarUrl and liveCoverUrl missing': (d, i, a) {
      a.remove('avatarUrl');
      i.remove('liveCoverUrl');
    },
  };
  final roots = <String, void Function(Map<String, dynamic> json)>{
    'code 404': (j) => j['code'] = 404,
    'code 424': (j) => j['code'] = 424,
    'code 520': (j) => j['code'] = 520,
    'code 522': (j) => j['code'] = 522,
    'code 555': (j) => j['code'] = 555,
    'code 500': (j) => j['code'] = 500,
    'code text': (j) => j['code'] = '200',
    'code missing': (j) => j.remove('code'),
    'data null': (j) => j['data'] = null,
  };
  return {
    for (final MapEntry(key: name, value: edit) in edits.entries) name: _editedRoom('S03-room-video', edit),
    for (final MapEntry(key: name, value: edit) in roots.entries) name: _editedRoot('S03-room-video', edit),
  };
}

/// The legacy qualities as (name, id, sort).
List<(Object?, Object?, Object?)> _legacyQualities(Object? legacy) => [
  for (final quality in _maps(legacy)) (quality['quality'], quality['id'], quality['sort']),
];

List<(Object?, Object?, Object?)> _qualities(List<LivePlayQuality> qualities) => [
  for (final quality in qualities) (quality.quality, quality.id, quality.sort),
];

/// 3.x's room calls at room entry for [body] (the room of [roomId]), before
/// or after a list that saw [known]: the room (but for [changed]), its
/// qualities and both lines, compared with [legacy] (a `_variantCalls`
/// entry, or a `_roomCalls` entry without the traces).
void _expectRoomEntry(
  String body,
  String roomId,
  Map<String, dynamic> legacy, {
  LookLiveRoom? known,
  Set<String> changed = _notice,
  String reason = '',
}) {
  final expected = legacy['getRoomDetail'];
  final kind = _failure(expected);
  if (kind != null) {
    expect(() => LookLiveApi.room(body, roomId: roomId), _typed(kind), reason: '$reason $kind');
    return;
  }
  var room = LookLiveApi.room(body, roomId: roomId);
  if (known != null) room = room.enrich(known);
  _expectParity(
    _projection(LookLiveApi.liveRoom(room, withData: true)),
    expected! as Map<String, dynamic>,
    changed: changed,
    reason: reason,
  );
  final legacyQualities = legacy['getRoomDetail → getPlayQualites'];
  final error = room.streamError;
  if (error == null) {
    expect(_qualities(LookLiveApi.qualities(room)), _legacyQualities(legacyQualities), reason: reason);
  } else if (room.state == LookLiveState.offline) {
    expect(legacyQualities, isEmpty, reason: '3.x: no qualities; now StreamUnavailable (difference 3)');
    expect(error, isA<StreamUnavailable>());
  } else {
    // 3.x: mediaUnavailable; a banned room (3.x: restricted, NeedsLogin in
    // M4.32) says so with StreamUnavailable too (32-2).
    expect(_failure(legacyQualities), 'mediaUnavailable', reason: reason);
    expect(error, isA<StreamUnavailable>(), reason: reason);
  }
  for (final id in [LookLiveApi.hlsId, LookLiveApi.flvId]) {
    final value = legacy['getRoomDetail → resolvePlayUrlsRaw($id)'];
    if (_failure(value) != null) {
      expect(error != null || room.variants.every((variant) => variant.id != id), isTrue, reason: '$reason $id');
      continue;
    }
    final line = LookLiveApi.line(room, id);
    expect([line.url], (value! as Map)['urls'], reason: '$reason $id');
    expect((value as Map<String, dynamic>)['appliedQualityData'], id);
    // Changed (32-3): the line carries the web's media headers.
    expect(line.headers, LookLiveApi.mediaHeaders(roomId), reason: '$reason $id');
  }
}

void main() {
  group('S01 video list', () {
    test('the one category and its two areas match 3.x; a page size of 1 keeps the video area', () {
      final legacy = _legacy('S01-video-p1');
      final expected = _maps(_result(legacy['getCategores'])).single;
      final category = LookLiveApi.categories().single;
      expect((category.id, category.name), (expected['id'], expected['name']));
      for (final (index, area) in category.children.indexed) {
        _expectParity(area.toJson(), _maps(expected['children'])[index]);
      }
      expect([
        for (final area in LookLiveApi.categories(pageSize: 1).single.children) area.areaId,
      ], _result(legacy['getCategores(pageSize: 1)']));
      expect(LookLiveApi.kindOf(LookLiveApi.videoArea), LookLiveKind.video);
      expect(LookLiveApi.kindOf(LookLiveApi.audioArea), LookLiveKind.audio);
      expect(LookLiveApi.kindOf(null), isNull);
      for (final area in const [
        LiveArea(platform: 'looklive', areaType: 'official', areaId: 'other'),
        LiveArea(platform: 'looklive', areaType: 'hot', areaId: 'video'),
        LiveArea(platform: 'bilibili', areaType: 'official', areaId: 'video'),
      ]) {
        expect(() => LookLiveApi.kindOf(area), throwsArgumentError, reason: '3.x: identity, a caller error');
      }
    });

    test("the weapi envelope is 3.x's encryptPayload byte for byte (the recorded forms)", () {
      final legacy = _legacy('S01-video-p1')['encryptPayload'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in legacy.entries) {
        expect(LookLiveApi.envelope(jsonDecode(key)), value, reason: key);
      }
      final recorded = Uri.splitQueryString(
        (_sample('S03-room-video').meta['request'] as Map<String, dynamic>)['body'] as String,
      );
      expect(LookLiveApi.envelope(LookLiveApi.roomPayload(_video)), recorded);
      expect(
        LookLiveApi.formBody(LookLiveApi.roomPayload(_video)),
        (_sample('S03-room-video').meta['request'] as Map<String, dynamic>)['body'],
      );
      expect(LookLiveApi.encSecKey, hasLength(256));
      expect(LookLiveApi.listPayload(3), {'offset': 40, 'limit': 20});
    });

    test("3.x's request headers (dio's form type) and media headers", () {
      final headers = _legacy('S01-video-p1')['headers'] as Map<String, dynamic>;
      String lower(Map<String, dynamic> map) =>
          jsonEncode({for (final MapEntry(:key, :value) in map.entries) key.toLowerCase(): value});
      expect(
        jsonEncode({...LookLiveApi.requestHeaders}..remove('content-type')),
        lower(headers['requestHeaders'] as Map<String, dynamic>),
      );
      expect(LookLiveApi.requestHeaders['content-type'], 'application/x-www-form-urlencoded');
      expect(
        jsonEncode(LookLiveApi.mediaHeaders(_video)),
        lower(headers['mediaHeaders($_video)'] as Map<String, dynamic>),
      );
    });

    test("page 1: 3.x's three video cards with heat, viewers and streams; the end of the list", () {
      final page = LookLiveApi.directory(_body('S01-video-p1'), kind: LookLiveKind.video);
      _expectLookPage(page, _result(_legacy('S01-video-p1')['directory(video, 1)']));
      expect(page.rooms, hasLength(3));
      expect(page.hasMore, isFalse);
      final card = page.rooms.first;
      expect((card.roomId, card.popularity, card.currentViewers), (_video, 440, 1));
      expect(card.variants.map((variant) => variant.uri.scheme), everyElement('https'));
      // Changed (32-4): the stream type is the card's `type` (3.x: null,
      // the lists carry no liveStreamType); 51 is a type LOOK's web client
      // does not name, with streams.
      expect(page.rooms.map((room) => room.streamType), [1, 1, 51]);
      expect(page.rooms.map((room) => room.isAppOnly), everyElement(isFalse));
    });

    test("the merged first page as rooms: every field of 3.x's directory (video, then voice)", () {
      final video = LookLiveApi.directory(_body('S01-video-p1'), kind: LookLiveKind.video);
      final audio = LookLiveApi.directory(_body('S02-audio-p1'), kind: LookLiveKind.audio);
      final legacy =
          _result((_legacy('S01-video-p1')['getDirectoryPage'] as Map<String, dynamic>)['page 1'])!
              as Map<String, dynamic>;
      final rooms = [
        for (final room in [...video.rooms, ...audio.rooms]) LookLiveApi.liveRoom(room),
      ];
      _expectRooms(rooms, legacy['rooms']);
      final card = LookLiveApi.liveRoom(video.rooms.first);
      expect(card.effectiveOnlineViewers, '1', reason: 'onlineNumber is current viewers (REG-COMMON-004)');
      expect(card.effectivePopularity, '440', reason: 'popularity is heat, kept apart');
      expect(card.audienceMetricType, AudienceMetricType.onlineViewers);
      expect(card.httpHeaders, LookLiveApi.mediaHeaders(_video), reason: "3.x's room headers (in the 3.x JSON)");
      expect(card.data, isNull, reason: 'a card cannot be played');
      expect(card.notice, LookLiveApi.chatNotice);
      // New keys (M2.1): cards that can be played do not tell tickets, so no
      // restriction; the lists have no start.
      expect(rooms.map((room) => room.restriction), everyElement(isNull));
      expect(rooms.map((room) => room.startedAt), everyElement(isNull));
      expect(rooms.map((room) => room.liveStatus), everyElement(LiveStatus.live));
    });

    test("3.x's list checks on edited copies", () {
      final legacy = _legacy('S01-video-p1')['variants'] as Map<String, dynamic>;
      final bodies = _listVariants();
      expect(
        bodies.keys.toSet(),
        containsAll(legacy.keys.where((key) => !key.contains(':') && !key.contains(' answered '))),
      );
      final recorded = LookLiveApi.directory(_body('S01-video-p1'), kind: LookLiveKind.video);
      final recordedIds = [for (final room in recorded.rooms) room.roomId];
      for (final MapEntry(key: name, value: body) in bodies.entries) {
        final expected = legacy[name];
        final kind = _failure(expected);
        if (name == 'itemList null') {
          // Changed: past its end a list answers `itemList: null` with
          // `hasMore: false` (S04-video-p2); that is an empty last page now
          // (3.x failed on it, see difference 1).
          expect(kind, 'schema');
          final page = LookLiveApi.directory(body, kind: LookLiveKind.video);
          expect(page.rooms, isEmpty);
          expect(page.hasMore, isFalse);
          continue;
        }
        if (_skippedEntries.contains(name)) {
          // Changed (32-6): an entry that cannot be read is skipped; 3.x
          // failed the page (or, for 1 and 19 digit room numbers, the rooms
          // it made from the page).
          expect(kind ?? 'kept', isIn(['schema', 'kept']), reason: name);
          final page = LookLiveApi.directory(body, kind: LookLiveKind.video);
          expect(
            page.rooms.map((room) => room.roomId),
            name == 'item not an object' ? recordedIds : recordedIds.skip(1),
            reason: name,
          );
          expect(page.hasMore, isFalse, reason: name);
          continue;
        }
        if (_badAddresses[name] case final left?) {
          // Changed (32-6): a bad address costs only that stream of the
          // card; 3.x failed the page.
          expect(kind, 'schema', reason: name);
          final page = LookLiveApi.directory(body, kind: LookLiveKind.video);
          expect(page.rooms.map((room) => room.roomId), recordedIds, reason: name);
          final card = page.rooms.first;
          expect(card.variants.map((variant) => variant.id), left, reason: name);
          expect(
            _without(_lookRoom(card), {'variants'}),
            _without(_lookRoom(recorded.rooms.first), {'variants'}),
            reason: name,
          );
          expect(card.restriction, left.isEmpty ? LiveRestriction.unplayable : isNull, reason: name);
          continue;
        }
        if (kind != null) {
          expect(() => LookLiveApi.directory(body, kind: LookLiveKind.video), _typed(kind), reason: name);
          continue;
        }
        _expectLookPage(LookLiveApi.directory(body, kind: LookLiveKind.video), expected, take: 2, reason: name);
      }
      expect(
        _lookPage(LookLiveApi.directory(_body('S01-video-p1'), kind: LookLiveKind.audio)),
        legacy['audio list answered with this video list'],
        reason: 'the voice list keeps only voice cards',
      );
      expect(
        () => LookLiveApi.directory(
          _editedRoot(
            'S01-video-p1',
            (j) => (j['data'] as Map<String, dynamic>)['itemList'] = null,
          ).replaceFirst('"hasMore":false', '"hasMore":true'),
          kind: LookLiveKind.video,
        ),
        throwsA(isA<ApiChanged>()),
        reason: 'no list while more is promised is still a changed answer',
      );
    });

    test('cards as rooms on edited copies: avatar falls back to the cover, the audience, app-only notice', () {
      final legacy = _legacy('S01-video-p1')['variants'] as Map<String, dynamic>;
      final bodies = _listVariants();
      for (final name in [
        'avatarUrl missing',
        'onlineNumber missing',
        'no audience',
        'liveStreamType 50 without liveUrl',
      ]) {
        final body = name == 'no audience'
            ? _editedLive('S01-video-p1', (l) {
                l
                  ..remove('onlineNumber')
                  ..remove('popularity');
              })
            : bodies[name]!;
        final room = LookLiveApi.liveRoom(LookLiveApi.directory(body, kind: LookLiveKind.video).rooms.first);
        _expectParity(
          _projection(room),
          legacy['getDirectoryPage(video): $name'] as Map<String, dynamic>,
          changed: _notice,
          reason: name,
        );
        final appOnly = name == 'liveStreamType 50 without liveUrl';
        expect(room.restriction, appOnly ? LiveRestriction.appOnly : isNull, reason: name);
        expect(
          room.notice,
          appOnly ? '${LookLiveApi.appOnlyNotice}\n${LookLiveApi.chatNotice}' : LookLiveApi.chatNotice,
          reason: name,
        );
      }
      // 3.x's link threw a FormatException on a number that is not 2 to 18
      // digits, failing the page; now the card is skipped (32-6), and such a
      // room is still ApiChanged.
      for (final name in ['liveRoomNo one digit', 'liveRoomNo 19 digits']) {
        expect((legacy['getDirectoryPage(video): $name'] as Map)['throws'], 'FormatException');
        expect(LookLiveApi.directory(bodies[name]!, kind: LookLiveKind.video).rooms.map((room) => room.roomId), [
          '217327486',
          '95878198',
        ], reason: name);
      }
      final short = LookLiveRoom(
        roomId: '7',
        userId: '1',
        sessionId: '1',
        kind: LookLiveKind.video,
        state: LookLiveState.live,
      );
      expect(() => LookLiveApi.liveRoom(short), throwsA(isA<ApiChanged>()));
    });

    test("room numbers and links: 3.x's parseRoomId and watchUrl", () {
      final legacy = _legacy('S01-video-p1');
      for (final MapEntry(:key, :value) in (legacy['LookLiveLink.parseRoomId'] as Map<String, dynamic>).entries) {
        expect(LookLiveApi.roomIdOf(key), value, reason: key);
        if (LookLiveApi.isRoomNumber(key.trim())) {
          expect(LookLiveApi.roomIdFromUrl(key), isNull, reason: 'a number is not a link: $key');
        } else {
          expect(LookLiveApi.roomIdFromUrl(key), value, reason: key);
        }
      }
      for (final MapEntry(:key, :value) in (legacy['LookLiveLink.watchUrl'] as Map<String, dynamic>).entries) {
        final roomId = LookLiveApi.roomIdOf(key);
        if (value is Map) {
          expect(roomId, isNull, reason: key);
        } else {
          expect(LookLiveApi.link(roomId!), value, reason: key);
        }
      }
    });
  });

  group('S02 voice list', () {
    test('page 1: 19 voice cards; the injected video card is skipped; more pages', () {
      final page = LookLiveApi.directory(_body('S02-audio-p1'), kind: LookLiveKind.audio);
      _expectLookPage(page, _result(_legacy('S02-audio-p1')['directory(audio, 1)']));
      expect(page.rooms, hasLength(19));
      expect(page.hasMore, isTrue);
      expect(page.rooms.map((room) => room.kind), everyElement(LookLiveKind.audio));
      expect(page.rooms.map((room) => room.streamType), everyElement(6), reason: "voice cards' type (32-4)");
    });

    test('the injected card is a type 50 room without streams: app-only on the card (32-4)', () {
      final legacy = _legacy('S02-audio-p1');
      final page = LookLiveApi.directory(_body('S02-audio-p1'), kind: LookLiveKind.video);
      _expectLookPage(page, _result(legacy['directory(video, 1) answered with this list']));
      final card = page.rooms.single;
      expect(card.variants, isEmpty);
      // Changed (32-4): 3.x read `liveStreamType`, which the lists lack, and
      // showed this card as an ordinary live room until the room was opened.
      final v3Card = _maps((_result(legacy['directory(video, 1) answered with this list'])! as Map)['rooms']).single;
      expect((v3Card['streamType'], v3Card['isAppOnly']), (null, false));
      expect((card.streamType, card.isAppOnly), (50, true));
      final room = LookLiveApi.liveRoom(card);
      _expectRooms([room], _result(legacy['getCategoryRooms(video) answered with this list']));
      expect((room.liveStatus, room.restriction), (LiveStatus.live, LiveRestriction.appOnly));
      expect(room.notice, '${LookLiveApi.appOnlyNotice}\n${LookLiveApi.chatNotice}');
      expect((room.isLiveNow, room.isRestricted, room.followGroup), (true, true, FollowGroup.live));
    });

    test('page 2: 20 voice cards, more pages; the rooms match 3.x', () {
      final legacy = _legacy('S02-audio-p2');
      final page = LookLiveApi.directory(_body('S02-audio-p2'), kind: LookLiveKind.audio);
      _expectLookPage(page, _result(legacy['directory(audio, 2)']));
      _expectRooms([
        for (final room in page.rooms) LookLiveApi.liveRoom(room),
      ], _result(legacy['getCategoryRooms(audio, 2)']));
      expect(page.rooms.first.roomId, _audio);
      expect(page.rooms[1].roomId, _offline);
    });
  });

  group('S04 video page 2', () {
    test('past its end the list answers itemList null: an empty last page (3.x failed, difference 1)', () {
      final legacy = _legacy('S04-video-p2');
      expect(_failure(_result(legacy['directory(video, 2)'])), 'schema');
      final page = LookLiveApi.directory(_body('S04-video-p2'), kind: LookLiveKind.video);
      expect(page.rooms, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });

  group('rooms', () {
    for (final (sample, roomId, startedAt, restriction) in [
      ('S03-room-video', _video, DateTime.utc(2026, 8, 26, 8, 33, 20, 612), LiveRestriction.none),
      ('S03-room-audio', _audio, DateTime.utc(2026, 9, 27, 17, 12, 0, 883), LiveRestriction.none),
      ('S04-room-offline', _offline, null, LiveRestriction.none),
      ('S04-room-apponly', _appOnly, DateTime.utc(2026, 8, 18, 18, 4, 34, 614), LiveRestriction.appOnly),
    ]) {
      test('$sample: the room answer, with and without streams, and the room at every depth match 3.x', () {
        final legacy = _legacy(sample)['recorded'] as Map<String, dynamic>;
        final body = _body(sample);
        expect(_lookRoom(LookLiveApi.room(body, roomId: roomId)), _result(legacy['api.room']));
        final refresh = LookLiveApi.room(body, roomId: roomId, withMedia: false);
        expect(_lookRoom(refresh), _result(legacy['api.room(includeMedia: false)']));
        final entry = LookLiveApi.liveRoom(LookLiveApi.room(body, roomId: roomId), withData: true);
        _expectParity(_projection(entry), _result(legacy['getRoomDetail'])! as Map<String, dynamic>, changed: _notice);
        _expectParity(
          _projection(entry),
          _result(legacy['getRoomDetailForRecording'])! as Map<String, dynamic>,
          changed: _notice,
        );
        final refreshed = LookLiveApi.liveRoom(refresh);
        _expectParity(
          _projection(refreshed),
          _result(legacy['getRoomDetailForRefresh'])! as Map<String, dynamic>,
          changed: _notice,
        );
        _expectRoomEntry(body, roomId, {for (final MapEntry(:key, :value) in legacy.entries) key: _result(value)});
        // New keys (M2.1): the start of a live broadcast (`startTime`), and
        // the restriction, at every depth.
        for (final room in [entry, refreshed]) {
          expect((room.startedAt, room.restriction), (startedAt, restriction), reason: sample);
          expect(room.toJson()['startedAt'], startedAt?.toIso8601String(), reason: sample);
        }
      });
    }

    test('the video room: a video room with both streams; no audience before a list', () {
      final room = LookLiveApi.room(_body('S03-room-video'), roomId: _video);
      expect((room.kind, room.state, room.streamType), (LookLiveKind.video, LookLiveState.live, 1));
      expect(room.variants.map((variant) => variant.id), [LookLiveApi.hlsId, LookLiveApi.flvId]);
      final detail = LookLiveApi.liveRoom(room, withData: true);
      expect((detail.watching, detail.effectiveOnlineViewers, detail.effectivePopularity), ('', '', ''));
      expect(detail.data, same(room));
      expect(detail.area, '视频直播');
      final hls = LookLiveApi.line(room, LookLiveApi.hlsId);
      expect(hls.url, 'https://pull0583d674.live.126.net/live/800897349fe246e994f36976011de4d5/playlist.m3u8');
      expect((hls.format, hls.lineId), (StreamFormat.hls, 'pull0583d674.live.126.net'));
      // Changed (32-3): the web's media headers (3.x's player sent none).
      expect(hls.headers, {
        'origin': 'https://look.163.com',
        'referer': 'https://look.163.com/live?id=$_video',
        'user-agent': 'Mozilla/5.0',
      });
      expect(LookLiveApi.line(room, LookLiveApi.flvId).headers, LookLiveApi.mediaHeaders(_video));
      expect((hls.lease, hls.codec), (null, null));
      expect(LookLiveApi.line(room, LookLiveApi.flvId).format, StreamFormat.flv);
      expect(
        () => LookLiveApi.line(room, 'auto'),
        throwsArgumentError,
        reason: '3.x: mediaUnavailable after a request',
      );
    });

    test('the voice room is in the voice area; the ended room is offline without streams', () {
      final audio = LookLiveApi.liveRoom(LookLiveApi.room(_body('S03-room-audio'), roomId: _audio));
      expect(audio.area, '语音直播');
      final ended = LookLiveApi.room(_body('S04-room-offline'), roomId: _offline);
      expect(ended.state, LookLiveState.offline);
      expect(ended.variants, isEmpty, reason: 'the answer still lists the old addresses; 3.x read them only when live');
      expect(ended.streamError, isA<StreamUnavailable>());
      expect(LookLiveApi.liveRoom(ended).liveStatus, LiveStatus.offline);
      expect(ended.startedAt, isNull, reason: 'its startTime is the ended broadcast');
    });

    test('the app-only room: live, stream type 50, no streams; its notice; StreamUnavailable', () {
      final room = LookLiveApi.room(_body('S04-room-apponly'), roomId: _appOnly);
      expect((room.state, room.streamType, room.isAppOnly), (LookLiveState.live, 50, true));
      expect(room.variants, isEmpty);
      final detail = LookLiveApi.liveRoom(room);
      expect(detail.notice, '${LookLiveApi.appOnlyNotice}\n${LookLiveApi.chatNotice}');
      expect(
        (detail.liveStatus, detail.restriction, detail.followGroup),
        (LiveStatus.live, LiveRestriction.appOnly, FollowGroup.live),
      );
      expect(room.streamError, isA<StreamUnavailable>().having((error) => '$error', 'text', contains('LOOK app only')));
    });

    test("3.x's room checks on edited copies, before and after the video list", () {
      final legacy = _legacy('S03-room-video')['variants'] as Map<String, dynamic>;
      final bodies = _roomVariants();
      expect(bodies.keys.toSet(), legacy.keys.toSet());
      for (final MapEntry(key: name, value: body) in bodies.entries) {
        final expected = legacy[name] as Map<String, dynamic>;
        switch (name) {
          case 'liveUrl text' || 'hlsPullUrl other host':
            // Changed (32-6): 3.x failed the room entry on a bad address;
            // now only that stream is left out. The room is the refresh's.
            expect(_failure(expected['getRoomDetail']), 'schema', reason: name);
            final room = LookLiveApi.room(body, roomId: _video);
            final text = name == 'liveUrl text';
            expect(room.variants.map((variant) => variant.id), text ? isEmpty : [LookLiveApi.flvId], reason: name);
            final detail = LookLiveApi.liveRoom(room, withData: true);
            _expectParity(
              _projection(detail),
              expected['getRoomDetailForRefresh'] as Map<String, dynamic>,
              changed: _notice,
              reason: name,
            );
            expect(detail.restriction, text ? LiveRestriction.unplayable : LiveRestriction.none, reason: name);
            expect(room.streamError, text ? isA<StreamUnavailable>() : isNull, reason: name);
            if (!text) expect(_qualities(LookLiveApi.qualities(room)), [('FLV 原始线路', 'flv:source', 1)]);
            continue;
          case 'code 424' || 'code 555':
            // Changed: the room answer's 424 (app only) and 555 (a private
            // room with a password) say why the room cannot be watched
            // (LOOK's web client); 3.x: access, M4.32 RiskControl.
            expect(_failure(expected['getRoomDetail']), 'access', reason: name);
            for (final withMedia in [true, false]) {
              expect(
                () => LookLiveApi.room(body, roomId: _video, withMedia: withMedia),
                throwsA(isA<StreamUnavailable>()),
                reason: name,
              );
            }
            continue;
        }
        // Changed (32-2): -10 is banned (LOOK's `FORBID`), 3.x unknown.
        final changed = {..._notice, if (name == 'liveStatus -10') 'liveStatus'};
        _expectRoomEntry(body, _video, expected, changed: changed, reason: name);
        final refresh = expected['getRoomDetailForRefresh'];
        final kind = _failure(refresh);
        if (kind != null) {
          expect(() => LookLiveApi.room(body, roomId: _video, withMedia: false), _typed(kind), reason: name);
        } else {
          _expectParity(
            _projection(LookLiveApi.liveRoom(LookLiveApi.room(body, roomId: _video, withMedia: false))),
            refresh! as Map<String, dynamic>,
            changed: changed,
            reason: name,
          );
        }
        if (expected['after the list'] case final Map<String, dynamic> after) {
          // Changed (32-5): an ended or banned room no longer takes the
          // card's heat and viewers.
          final ended = name == 'liveStatus -1' || name == 'liveStatus -10';
          _expectRoomEntry(
            body,
            _video,
            after,
            known: _videoCard(),
            changed: {...changed, if (ended) ..._audience},
            reason: '$name after the list',
          );
          if (ended) {
            final v3 = after['getRoomDetail'] as Map<String, dynamic>;
            expect((v3['popularity'], v3['onlineViewers']), ('440', '1'), reason: '3.x kept the ended card');
            final room = LookLiveApi.liveRoom(LookLiveApi.room(body, roomId: _video).enrich(_videoCard()));
            expect((room.effectivePopularity, room.effectiveOnlineViewers), ('', ''), reason: name);
          }
        }
      }
    });

    test('the state by liveStatus and the live status: -10 and -4 banned, -2 offline (32-2)', () {
      final legacy = _legacy('S03-room-video')['variants'] as Map<String, dynamic>;
      for (final (name, state) in [
        ('liveStatus 0', LookLiveState.offline),
        ('liveStatus -1', LookLiveState.offline),
        ('liveStatus -10', LookLiveState.banned),
        ('liveStatus 2', LookLiveState.unknown),
        ('liveStatus missing', LookLiveState.unknown),
        ('liveStatus text', LookLiveState.live),
      ]) {
        final room = LookLiveApi.room(_roomVariants()[name]!, roomId: _video, withMedia: false);
        expect(room.state, state, reason: name);
        final status = (legacy[name] as Map<String, dynamic>)['getLiveStatus'];
        expect(status, switch (state) {
          LookLiveState.live => true,
          LookLiveState.offline => false,
          _ => {'throws': 'LookLiveException', 'message': 'LOOK Live access'},
        });
      }
      // Changed (32-2): 3.x took -10 for a private or account-restricted
      // room and showed it as unknown with a notice; LOOK's web client names
      // it FORBID. It is banned: not live, grouped with offline, and says
      // so when played.
      final v3 = (legacy['liveStatus -10'] as Map<String, dynamic>)['getRoomDetail'] as Map<String, dynamic>;
      expect((v3['liveStatus'], v3['status']), (LiveStatus.unknown.index, false));
      for (final status in [-10, -4]) {
        final body = _body('S03-room-video').replaceFirst('"liveStatus": 1', '"liveStatus": $status');
        final room = LookLiveApi.room(body, roomId: _video);
        expect((room.state, room.variants.length, room.startedAt), (LookLiveState.banned, 0, null), reason: '$status');
        final detail = LookLiveApi.liveRoom(room, withData: true);
        expect(
          (detail.liveStatus, detail.isLiveNow, detail.isExplicitlyOfflineNow, detail.followGroup),
          (LiveStatus.banned, false, true, FollowGroup.offline),
          reason: '$status',
        );
        expect(detail.toJson()['liveStatus'], LiveStatus.banned.index);
        expect(detail.restriction, LiveRestriction.none);
        expect(detail.notice, '${LookLiveApi.bannedNotice}\n${LookLiveApi.chatNotice}');
        expect(room.streamError, isA<StreamUnavailable>());
      }
      final closed = LookLiveApi.room(
        _body('S03-room-video').replaceFirst('"liveStatus": 1', '"liveStatus": -2'),
        roomId: _video,
      );
      expect(closed.state, LookLiveState.offline, reason: "the web shows '- 直播间已关闭 -' for -1, 0 and -2");
      expect(LookLiveApi.liveRoom(closed).notice, LookLiveApi.chatNotice);
    });

    test('a refreshed stream type 50 room with addresses is not app-only (3.x said it was, problem 3)', () {
      final legacy = _legacy('S03-room-video')['variants'] as Map<String, dynamic>;
      final body = _roomVariants()['liveStreamType 50']!;
      final refresh = LookLiveApi.liveRoom(LookLiveApi.room(body, roomId: _video, withMedia: false));
      final entry = LookLiveApi.liveRoom(LookLiveApi.room(body, roomId: _video), withData: true);
      // Changed (32-4): the refresh sees the addresses without reading them.
      expect(
        ((legacy['liveStreamType 50'] as Map)['getRoomDetailForRefresh'] as Map)['notice'],
        contains('请在 LOOK 客户端中观看'),
      );
      expect((refresh.notice, refresh.restriction), (LookLiveApi.chatNotice, LiveRestriction.none));
      expect((entry.notice, entry.restriction), (LookLiveApi.chatNotice, LiveRestriction.none));
      final appOnly = LookLiveApi.liveRoom(
        LookLiveApi.room(_roomVariants()['liveStreamType 50 without liveUrl']!, roomId: _video, withMedia: false),
      );
      expect(appOnly.restriction, LiveRestriction.appOnly, reason: 'without addresses, a refresh tells it');
    });

    test("stream addresses: 3.x's host, path and query rules, made https", () {
      final legacy = _legacy('S03-room-video')['LookLiveApi.mediaUri'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in legacy.entries) {
        final protocol = key.substring(0, key.indexOf(' '));
        final raw = key.substring(key.indexOf(' ') + 1);
        final format = switch (protocol) {
          'hls' => StreamFormat.hls,
          'flv' => StreamFormat.flv,
          _ => StreamFormat.other,
        };
        if (value is Map) {
          expect(() => LookLiveApi.mediaUri(raw, format: format), throwsA(isA<ApiChanged>()), reason: key);
        } else {
          expect('${LookLiveApi.mediaUri(raw, format: format)}', value, reason: key);
        }
      }
    });

    test('the answer must be for the room asked (3.x: identity)', () {
      final legacy = _legacy('S03-room-video');
      expect(_failure(_result(legacy['api.room(21623632) answered with this room'])), 'identity');
      expect(() => LookLiveApi.room(_body('S03-room-video'), roomId: '21623632'), throwsA(isA<ApiChanged>()));
    });
  });

  group('not found and statuses', () {
    test("code 404 is NotFound (3.x's missing)", () {
      final legacy = _legacy('S03-room-notfound');
      expect(legacy['request'], '{"liveRoomNo":"1"}', reason: 'recorded for a number 3.x never sends');
      expect(_failure(_result(legacy['api.room(1)'])), isNull);
      expect((_result(legacy['api.room(1)'])! as Map)['throws'], 'FormatException');
      for (final call in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording', 'getLiveStatus']) {
        expect(_failure(_result((legacy['recorded'] as Map<String, dynamic>)[call])), 'missing', reason: call);
      }
      expect(() => LookLiveApi.room(_body('S03-room-notfound'), roomId: '99999999'), throwsA(isA<NotFound>()));
      expect(
        () => LookLiveApi.directory(_body('S03-room-notfound'), kind: LookLiveKind.video),
        throwsA(isA<NotFound>()),
      );
    });

    test("HTTP statuses: 3.x's mapping (5xx and the rest are network failures)", () {
      final legacy = _legacy('S03-room-notfound');
      for (final status in [401, 403, 404, 429, 500, 502, 503, 302, 400, 204]) {
        final kind = _failure(_result((legacy['room status $status'] as Map<String, dynamic>)['getRoomDetail']));
        final matcher = switch (kind) {
          'access' => isA<RiskControl>(),
          'missing' => isA<NotFound>(),
          'rateLimited' => isA<RateLimited>(),
          'service' || 'transport' => isA<NetworkFailure>(),
          _ => throw StateError('$status: $kind'),
        };
        expect(
          () => LookLiveApi.room('', roomId: _video, status: status),
          throwsA(matcher),
          reason: '$status',
        );
        expect(
          () => LookLiveApi.directory('', kind: LookLiveKind.audio, status: status),
          throwsA(matcher),
          reason: '$status',
        );
      }
    });

    test('bodies: empty, not JSON and over 2 MiB are ApiChanged; exactly 2 MiB is read (3.x, in bytes)', () {
      final legacy = _legacy('S03-room-notfound');
      for (final name in ['empty 200', 'not JSON', 'over 2 MiB']) {
        expect(_failure(_result(legacy['room $name'])), 'schema', reason: name);
      }
      expect(() => LookLiveApi.room('', roomId: _video), throwsA(isA<ApiChanged>()));
      expect(() => LookLiveApi.room('<html></html>', roomId: _video), throwsA(isA<ApiChanged>()));
      final body = _body('S03-room-video');
      final exact = '$body${' ' * (LookLiveApi.responseLimit - utf8.encode(body).length)}';
      _expectParity(
        _projection(LookLiveApi.liveRoom(LookLiveApi.room(exact, roomId: _video, withMedia: false))),
        _result(legacy['room at 2 MiB'])! as Map<String, dynamic>,
        changed: _notice,
      );
      expect(() => LookLiveApi.room('$exact ', roomId: _video), throwsA(isA<ApiChanged>()));
      final wide = '{"code":200,"data":{"x":"${'中' * (LookLiveApi.responseLimit ~/ 3)}"}}';
      expect(wide.length, lessThan(LookLiveApi.responseLimit));
      expect(() => LookLiveApi.room(wide, roomId: _video), throwsA(isA<ApiChanged>()), reason: 'counted in bytes');
    });
  });

  group('upgrades (M4.U)', () {
    /// S03-room-video's answer with [edit] applied to its `data`.
    String room(void Function(Map<String, dynamic> data, Map<String, dynamic> info) edit) =>
        _editedRoom('S03-room-video', (data, info, anchor) => edit(data, info));

    test('startedAt: the start of a live broadcast only; zero, missing or not a number is none', () {
      for (final (value, expected) in [
        (1790529120883, DateTime.utc(2026, 9, 27, 17, 12, 0, 883)),
        ('1790529120883', DateTime.utc(2026, 9, 27, 17, 12, 0, 883)),
        (0, null),
        (-5, null),
        (null, null),
        ('soon', null),
        (1.5, null),
      ]) {
        final body = room((data, info) => info['startTime'] = value);
        expect(LookLiveApi.room(body, roomId: _video).startedAt, expected, reason: '$value');
        expect(LookLiveApi.room(body, roomId: _video, withMedia: false).startedAt, expected, reason: '$value');
      }
      for (final status in [0, -1, -2, -4, -10, 2]) {
        final body = room((data, info) => data['liveStatus'] = status);
        expect(LookLiveApi.room(body, roomId: _video).startedAt, isNull, reason: 'liveStatus $status');
      }
      final card = _videoCard();
      expect(card.startedAt, isNull, reason: 'the lists do not say');
      final detail = LookLiveApi.liveRoom(LookLiveApi.room(_body('S03-room-video'), roomId: _video).enrich(card));
      expect(detail.startedAt, DateTime.utc(2026, 8, 26, 8, 33, 20, 612), reason: "the answer's, not the card's");
      expect(detail.startedAt!.isUtc, isTrue);
    });

    test('restriction: app-only, ticket and unplayable live rooms stay live; none otherwise (M2.1)', () {
      LiveRoom at(String body, {bool withMedia = true}) => LookLiveApi.liveRoom(
        LookLiveApi.room(body, roomId: _video, withMedia: withMedia),
        withData: withMedia,
      );
      for (final (name, body, entry, refresh) in [
        ('recorded', _body('S03-room-video'), LiveRestriction.none, LiveRestriction.none),
        (
          'type 50 without addresses',
          room((data, info) {
            info['liveStreamType'] = 50;
            info['liveUrl'] = null;
          }),
          LiveRestriction.appOnly,
          LiveRestriction.appOnly,
        ),
        (
          'a ticket',
          room((data, info) => data['feeInfo'] = {'fee': true, 'sessionKey': ''}),
          LiveRestriction.paid,
          LiveRestriction.paid,
        ),
        (
          'a ticket without a session key',
          room((data, info) => data['feeInfo'] = {'fee': 1}),
          LiveRestriction.paid,
          LiveRestriction.paid,
        ),
        (
          'a bought ticket',
          room((data, info) => data['feeInfo'] = {'fee': true, 'sessionKey': 'k'}),
          LiveRestriction.none,
          LiveRestriction.none,
        ),
        ('no fee', room((data, info) => data['feeInfo'] = {'fee': false}), LiveRestriction.none, LiveRestriction.none),
        (
          'no address',
          room((data, info) => info['liveUrl'] = null),
          LiveRestriction.unplayable,
          LiveRestriction.unplayable,
        ),
        (
          'only bad addresses',
          room((data, info) => info['liveUrl'] = {'hlsPullUrl': 'http://x.cn/a.m3u8', 'httpPullUrl': 'x'}),
          LiveRestriction.unplayable,
          LiveRestriction.none,
        ),
        ('offline', room((data, info) => data['liveStatus'] = -1), LiveRestriction.none, LiveRestriction.none),
        ('banned', room((data, info) => data['liveStatus'] = -10), LiveRestriction.none, LiveRestriction.none),
        ('unknown', room((data, info) => data['liveStatus'] = 2), null, null),
      ]) {
        final entered = at(body);
        final refreshed = at(body, withMedia: false);
        expect((entered.restriction, refreshed.restriction), (entry, refresh), reason: name);
        if (entry != null && entry != LiveRestriction.none) {
          expect(
            (entered.liveStatus, entered.isLiveNow, entered.followGroup),
            (LiveStatus.live, true, FollowGroup.live),
            reason: name,
          );
          expect(entered.toJson()['restriction'], entry.name, reason: name);
          expect((entered.data! as LookLiveRoom).streamError, isA<StreamUnavailable>(), reason: name);
        }
      }
      final paid = at(room((data, info) => data['feeInfo'] = {'fee': true}));
      expect(paid.notice, '${LookLiveApi.paidNotice}\n${LookLiveApi.chatNotice}');
      expect(
        (paid.data! as LookLiveRoom).streamError,
        isA<StreamUnavailable>().having((error) => '$error', 'text', contains('ticket')),
      );
      expect(at(_body('S03-room-video')).toJson()['restriction'], 'none');
      final unknown = at(room((data, info) => data['liveStatus'] = 2)).toJson();
      expect(unknown.containsKey('restriction'), isFalse, reason: 'an unknown state does not tell');
    });

    test('a refresh that saw the card of the same broadcast plays its streams: not unplayable (3.x enrich)', () {
      final body = room((data, info) => info['liveUrl'] = null);
      final refreshed = LookLiveApi.room(body, roomId: _video, withMedia: false);
      expect(LookLiveApi.liveRoom(refreshed).restriction, LiveRestriction.unplayable);
      final completed = refreshed.enrich(_videoCard());
      expect(completed.variants, hasLength(2));
      expect(LookLiveApi.liveRoom(completed).restriction, LiveRestriction.none);
    });

    test('32-5: the audience of the same broadcast only while this answer is live', () {
      final card = _videoCard();
      for (final (status, kept) in [
        (1, true),
        (0, false),
        (-1, false),
        (-2, false),
        (-4, false),
        (-10, false),
        (2, false),
      ]) {
        final answer = LookLiveApi.room(room((data, info) => data['liveStatus'] = status), roomId: _video);
        final completed = answer.enrich(card);
        expect(
          (completed.popularity, completed.currentViewers),
          kept ? (440, 1) : (null, null),
          reason: 'liveStatus $status',
        );
        expect((completed.nick, completed.userId), (answer.nick, answer.userId), reason: 'names are kept');
      }
      final other = LookLiveApi.room(room((data, info) => info['id'] = 5), roomId: _video).enrich(card);
      expect((other.popularity, other.currentViewers), (null, null), reason: 'another broadcast');
    });

    test('32-6: a page of only unreadable entries is still ApiChanged; the others are skipped', () {
      final all = _editedRoot('S01-video-p1', (json) {
        final items = (json['data'] as Map<String, dynamic>)['itemList'] as List;
        for (final item in items) {
          (((item as Map<String, dynamic>)['liveData'] as Map<String, dynamic>)['userInfo'] as Map).remove('userId');
        }
      });
      expect(() => LookLiveApi.directory(all, kind: LookLiveKind.video), throwsA(isA<ApiChanged>()));
      final one = _editedLive('S01-video-p1', (live) => live['popularity'] = -1, index: 1);
      expect(LookLiveApi.directory(one, kind: LookLiveKind.video).rooms.map((room) => room.roomId), [
        _video,
        '95878198',
      ]);
      final twoBad = _editedLive('S01-video-p1', (live) {
        (live['liveUrl'] as Map<String, dynamic>)
          ..['hlsPullUrl'] = 'http://example.com/live/x/playlist.m3u8'
          ..['httpPullUrl'] = 'rtmp://pull0583d674.live.126.net/live/x';
      });
      final card = LookLiveApi.directory(twoBad, kind: LookLiveKind.video).rooms.first;
      expect((card.roomId, card.variants.length, card.hasAddress), (_video, 0, true));
      expect(LookLiveApi.liveRoom(card).restriction, LiveRestriction.unplayable);
    });

    test("the room answer's 424 and 555 say why; on the lists they stay RiskControl, 520 and 522 too", () {
      String code(String sample, int value) => _editedRoot(sample, (json) => json['code'] = value);
      expect(
        () => LookLiveApi.room(code('S03-room-video', 424), roomId: _video),
        throwsA(isA<StreamUnavailable>().having((error) => '$error', 'text', contains('LOOK app only'))),
      );
      expect(
        () => LookLiveApi.room(code('S03-room-video', 555), roomId: _video),
        throwsA(isA<StreamUnavailable>().having((error) => '$error', 'text', contains('password'))),
      );
      for (final value in [520, 522]) {
        expect(() => LookLiveApi.room(code('S03-room-video', value), roomId: _video), throwsA(isA<RiskControl>()));
      }
      for (final value in [424, 520, 522, 555]) {
        expect(
          () => LookLiveApi.directory(code('S01-video-p1', value), kind: LookLiveKind.video),
          throwsA(isA<RiskControl>()),
          reason: '$value',
        );
      }
    });

    test('notices in words for users (M4.U); the chat notice only explains the numbers (M5.28)', () {
      // M5.28 shows LOOK chat: "这里暂时看不到 LOOK 直播的聊天。" is gone.
      expect(LookLiveApi.chatNotice, '人数是正在观看的人数，热度另外显示。');
      expect(LookLiveApi.appOnlyNotice, '这场 LOOK 直播只能在 LOOK App 里观看。');
      expect(LookLiveApi.bannedNotice, '这个 LOOK 直播间被平台禁播或正在违规整改，现在不能观看。');
      expect(LookLiveApi.paidNotice, '这场 LOOK 直播要购票才能观看。');
      for (final notice in [
        LookLiveApi.chatNotice,
        LookLiveApi.appOnlyNotice,
        LookLiveApi.bannedNotice,
        LookLiveApi.paidNotice,
      ]) {
        expect(notice, isNot(matches(RegExp('popularity|onlineNumber|尚待接入|暂时看不到|未知状态|官网|房型'))));
      }
    });
  });

  group('chat (M5.28)', () {
    test('room entry and recording carry the chat of a live room: its Yunxin chatroom (roomInfo.roomId)', () {
      for (final (sample, roomId, chatroomId) in [
        ('S03-room-video', _video, '462192286'),
        ('S03-room-audio', _audio, '16272838887'),
        ('S04-room-apponly', _appOnly, '15148749147'),
      ]) {
        final room = LookLiveApi.room(_body(sample), roomId: roomId);
        expect((room.chatroomId, room.anonymousMode), (chatroomId, false), reason: sample);
        final args = LookLiveDanmakuArgs(roomId: roomId, chatroomId: chatroomId);
        expect(room.danmakuArgs, args, reason: sample);
        expect(LookLiveApi.liveRoom(room, withData: true).danmakuData, args, reason: sample);
        // A refresh keeps no data, as for the streams.
        final refresh = LookLiveApi.room(_body(sample), roomId: roomId, withMedia: false);
        expect(refresh.danmakuArgs, args, reason: sample);
        expect(LookLiveApi.liveRoom(refresh).danmakuData, isNull, reason: sample);
      }
      expect(
        '${LookLiveApi.room(_body('S03-room-video'), roomId: _video).danmakuArgs}',
        'LookLiveDanmakuArgs(21623631, chatroom 462192286)',
      );
    });

    test('no chat for a room that is not live, a list card or an answer without a chatroom', () {
      final offline = LookLiveApi.room(_body('S04-room-offline'), roomId: _offline);
      expect(offline.chatroomId, '909690154');
      expect(offline.danmakuArgs, isNull);
      expect(LookLiveApi.liveRoom(offline, withData: true).danmakuData, isNull);
      for (final status in [-10, -4, 0, 7]) {
        final room = LookLiveApi.room(
          _editedRoom('S03-room-video', (data, info, anchor) => data['liveStatus'] = status),
          roomId: _video,
        );
        expect(room.danmakuArgs, isNull, reason: '$status');
      }
      expect(_videoCard().chatroomId, '');
      expect(_videoCard().danmakuArgs, isNull);
      for (final value in [null, '', 0, -1, '0462192286', 'room', 1.5, true, '12345678901234567890']) {
        final room = LookLiveApi.room(
          _editedRoom('S03-room-video', (data, info, anchor) => info['roomId'] = value),
          roomId: _video,
        );
        expect(room.chatroomId, '', reason: '$value');
        expect(LookLiveApi.liveRoom(room, withData: true).danmakuData, isNull, reason: '$value');
      }
      final text = LookLiveApi.room(
        _editedRoom('S03-room-video', (data, info, anchor) => info['roomId'] = ' 462192286 '),
        roomId: _video,
      );
      expect(text.chatroomId, '462192286');
    });

    test("anonymousMode (the room page masks the viewers' names) is read as true only", () {
      for (final (value, expected) in [(true, true), (false, false), (null, false), ('true', false), (1, false)]) {
        final room = LookLiveApi.room(
          _editedRoom('S03-room-video', (data, info, anchor) => data['anonymousMode'] = value),
          roomId: _video,
        );
        expect(room.anonymousMode, expected, reason: '$value');
        expect(room.danmakuArgs?.anonymousMode, expected, reason: '$value');
      }
    });

    test("the chat stays the answer's when a card of the same broadcast completes it", () {
      final room = LookLiveApi.room(_body('S03-room-video'), roomId: _video).enrich(_videoCard());
      expect(room.danmakuArgs, const LookLiveDanmakuArgs(roomId: _video, chatroomId: '462192286'));
      final card = _videoCard().enrich(LookLiveApi.room(_body('S03-room-video'), roomId: _video));
      expect(card.danmakuArgs, isNull);
    });

    test('chat servers: the request of the website and the recorded answer (S05-live)', () {
      expect(LookLiveApi.chatAddressPath, '/weapi/livestream/chat/address');
      expect(LookLiveApi.chatAddressPayload('447365581'), {'liveRoomNo': '447365581', 'os': 0});
      expect(jsonEncode(LookLiveApi.chatAddressPayload('447365581')), '{"liveRoomNo":"447365581","os":0}');
      final recorded =
          (jsonDecode(File('../../fixtures/looklive/danmaku/S05-live/frames.jsonl').readAsLinesSync().first)
                  as Map<String, dynamic>)['text']
              as String;
      expect(LookLiveApi.chatAddresses(recorded), [
        'chatwl01.yunxinfw.com:443',
        'chatwl01-bgp.yunxinfw.com:443',
        'chatwl02-bgp.yunxinfw.com:443',
        'chatwl02.yunxinfw.com:443',
      ]);
    });

    test('chat servers: host:port entries only, in order, once; a room that is not live is NotFound', () {
      String answer(Object? address, {Object? code = 200}) => jsonEncode({
        'code': code,
        'msg': null,
        'message': code == 404 ? '无资源' : null,
        'data': code == 200 ? {'address': address} : null,
        'success': code == 200,
      });
      expect(
        LookLiveApi.chatAddresses(
          answer([
            ' CHATWL01.yunxinfw.com:443 ',
            'chatwl01.yunxinfw.com:443',
            'chatwl02.yunxinfw.com:8443',
            '127.0.0.1:9000',
            'chatwl03.yunxinfw.com',
            'chatwl04.yunxinfw.com:0',
            'chatwl05.yunxinfw.com:65536',
            'chatwl06.yunxinfw.com:443/path',
            'https://chatwl07.yunxinfw.com:443',
            'user@chatwl08.yunxinfw.com:443',
            'localhost:443',
            '-bad.yunxinfw.com:443',
            'chatwl09.yunxinfw.com:65535',
            443,
            null,
            {'host': 'chatwl10.yunxinfw.com'},
          ]),
        ),
        ['chatwl01.yunxinfw.com:443', 'chatwl02.yunxinfw.com:8443', '127.0.0.1:9000', 'chatwl09.yunxinfw.com:65535'],
      );
      expect(() => LookLiveApi.chatAddresses(answer(null, code: 404)), throwsA(isA<NotFound>()));
      for (final address in [
        <Object?>[],
        ['nothing'],
        'chatwl01.yunxinfw.com:443',
        null,
        {'a': 1},
      ]) {
        expect(() => LookLiveApi.chatAddresses(answer(address)), throwsA(isA<ApiChanged>()), reason: '$address');
      }
      expect(() => LookLiveApi.chatAddresses(answer(null, code: 500)), throwsA(isA<ApiChanged>()));
      expect(() => LookLiveApi.chatAddresses('not json'), throwsA(isA<ApiChanged>()));
      expect(
        () => LookLiveApi.chatAddresses(answer(['chatwl01.yunxinfw.com:443']), status: 503),
        throwsA(isA<NetworkFailure>()),
      );
      expect(
        () => LookLiveApi.chatAddresses(answer(['chatwl01.yunxinfw.com:443']), status: 403),
        throwsA(isA<RiskControl>()),
      );
    });
  });
}
