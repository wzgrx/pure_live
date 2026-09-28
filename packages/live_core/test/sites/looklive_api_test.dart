// LOOK Live parsing against the recorded samples, compared field by field
// with 3.x's frozen output (expected.json, written by
// fixtures/looklive/legacy_expected.dart from 3.x's LookLiveApi, LookLiveLink
// and LookLiveSite). Every intended difference is listed with its reason;
// everything else must match. The synthetic cases are the edited copies the
// generator ran through 3.x (`variants`) and 3.x's look_live_site_test.dart.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('looklive', name);

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

/// The `result` of a traced legacy call.
Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

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

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {String reason = ''}) {
  final expected = _maps(legacy);
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(_projection(room), expected[index], reason: '$reason[$index]');
  }
}

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
/// or after a list that saw [known]: the room, its qualities and both
/// lines, compared with [legacy] (a `_variantCalls` entry, or a
/// `_roomCalls` entry without the traces).
void _expectRoomEntry(String body, String roomId, Map<String, dynamic> legacy, {LookLiveRoom? known}) {
  final expected = legacy['getRoomDetail'];
  final kind = _failure(expected);
  if (kind != null) {
    expect(() => LookLiveApi.room(body, roomId: roomId), _typed(kind), reason: kind);
    return;
  }
  var room = LookLiveApi.room(body, roomId: roomId);
  if (known != null) room = room.enrich(known);
  _expectParity(_projection(LookLiveApi.liveRoom(room, withData: true)), expected! as Map<String, dynamic>);
  final legacyQualities = legacy['getRoomDetail → getPlayQualites'];
  final error = room.streamError;
  if (error == null) {
    expect(_qualities(LookLiveApi.qualities(room)), _legacyQualities(legacyQualities));
  } else if (room.state == LookLiveState.offline) {
    expect(legacyQualities, isEmpty, reason: '3.x: no qualities; now StreamUnavailable (difference 3)');
    expect(error, isA<StreamUnavailable>());
  } else {
    expect(_failure(legacyQualities), 'mediaUnavailable');
    expect(error, room.state == LookLiveState.restricted ? isA<NeedsLogin>() : isA<StreamUnavailable>());
  }
  for (final id in [LookLiveApi.hlsId, LookLiveApi.flvId]) {
    final value = legacy['getRoomDetail → resolvePlayUrlsRaw($id)'];
    if (_failure(value) != null) {
      expect(error != null || room.variants.every((variant) => variant.id != id), isTrue, reason: id);
      continue;
    }
    final line = LookLiveApi.line(room, id);
    expect([line.url], (value! as Map)['urls'], reason: id);
    expect((value as Map<String, dynamic>)['appliedQualityData'], id);
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
      expect(_lookPage(page), _result(_legacy('S01-video-p1')['directory(video, 1)']));
      expect(page.rooms, hasLength(3));
      expect(page.hasMore, isFalse);
      final card = page.rooms.first;
      expect((card.roomId, card.popularity, card.currentViewers), (_video, 440, 1));
      expect(card.streamType, isNull, reason: 'the lists carry no liveStreamType');
      expect(card.variants.map((variant) => variant.uri.scheme), everyElement('https'));
    });

    test("the merged first page as rooms: every field of 3.x's directory (video, then voice)", () {
      final video = LookLiveApi.directory(_body('S01-video-p1'), kind: LookLiveKind.video);
      final audio = LookLiveApi.directory(_body('S02-audio-p1'), kind: LookLiveKind.audio);
      final legacy =
          _result((_legacy('S01-video-p1')['getDirectoryPage'] as Map<String, dynamic>)['page 1'])!
              as Map<String, dynamic>;
      _expectRooms([
        for (final room in [...video.rooms, ...audio.rooms]) LookLiveApi.liveRoom(room),
      ], legacy['rooms']);
      final card = LookLiveApi.liveRoom(video.rooms.first);
      expect(card.effectiveOnlineViewers, '1', reason: 'onlineNumber is current viewers (REG-COMMON-004)');
      expect(card.effectivePopularity, '440', reason: 'popularity is heat, kept apart');
      expect(card.audienceMetricType, AudienceMetricType.onlineViewers);
      expect(card.httpHeaders, LookLiveApi.mediaHeaders(_video), reason: "3.x's room headers (in the 3.x JSON)");
      expect(card.data, isNull, reason: 'a card cannot be played');
      expect(card.notice, LookLiveApi.chatNotice);
    });

    test("3.x's list checks on edited copies", () {
      final legacy = _legacy('S01-video-p1')['variants'] as Map<String, dynamic>;
      final bodies = _listVariants();
      expect(
        bodies.keys.toSet(),
        containsAll(legacy.keys.where((key) => !key.contains(':') && !key.contains(' answered '))),
      );
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
        if (kind != null) {
          expect(() => LookLiveApi.directory(body, kind: LookLiveKind.video), _typed(kind), reason: name);
          continue;
        }
        expect(_lookPage(LookLiveApi.directory(body, kind: LookLiveKind.video), take: 2), expected, reason: name);
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
          reason: name,
        );
      }
      // 3.x's link threw a FormatException on a number that is not 2 to 18
      // digits, failing the page; now that is ApiChanged.
      for (final name in ['liveRoomNo one digit', 'liveRoomNo 19 digits']) {
        expect((legacy['getDirectoryPage(video): $name'] as Map)['throws'], 'FormatException');
        final card = LookLiveApi.directory(bodies[name]!, kind: LookLiveKind.video).rooms.first;
        expect(() => LookLiveApi.liveRoom(card), throwsA(isA<ApiChanged>()), reason: name);
      }
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
      expect(_lookPage(page), _result(_legacy('S02-audio-p1')['directory(audio, 1)']));
      expect(page.rooms, hasLength(19));
      expect(page.hasMore, isTrue);
      expect(page.rooms.map((room) => room.kind), everyElement(LookLiveKind.audio));
    });

    test("the video list's rule keeps the injected card: a type 50 room without streams (3.x)", () {
      final legacy = _legacy('S02-audio-p1');
      final page = LookLiveApi.directory(_body('S02-audio-p1'), kind: LookLiveKind.video);
      expect(_lookPage(page), _result(legacy['directory(video, 1) answered with this list']));
      final card = page.rooms.single;
      expect(card.variants, isEmpty);
      expect(card.isAppOnly, isFalse, reason: 'the lists carry no liveStreamType (3.x, problem 4)');
      _expectRooms([LookLiveApi.liveRoom(card)], _result(legacy['getCategoryRooms(video) answered with this list']));
    });

    test('page 2: 20 voice cards, more pages; the rooms match 3.x', () {
      final legacy = _legacy('S02-audio-p2');
      final page = LookLiveApi.directory(_body('S02-audio-p2'), kind: LookLiveKind.audio);
      expect(_lookPage(page), _result(legacy['directory(audio, 2)']));
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
    for (final (sample, roomId) in [
      ('S03-room-video', _video),
      ('S03-room-audio', _audio),
      ('S04-room-offline', _offline),
      ('S04-room-apponly', _appOnly),
    ]) {
      test('$sample: the room answer, with and without streams, and the room at every depth match 3.x', () {
        final legacy = _legacy(sample)['recorded'] as Map<String, dynamic>;
        final body = _body(sample);
        expect(_lookRoom(LookLiveApi.room(body, roomId: roomId)), _result(legacy['api.room']));
        final refresh = LookLiveApi.room(body, roomId: roomId, withMedia: false);
        expect(_lookRoom(refresh), _result(legacy['api.room(includeMedia: false)']));
        final entry = LookLiveApi.liveRoom(LookLiveApi.room(body, roomId: roomId), withData: true);
        _expectParity(_projection(entry), _result(legacy['getRoomDetail'])! as Map<String, dynamic>);
        _expectParity(_projection(entry), _result(legacy['getRoomDetailForRecording'])! as Map<String, dynamic>);
        _expectParity(
          _projection(LookLiveApi.liveRoom(refresh)),
          _result(legacy['getRoomDetailForRefresh'])! as Map<String, dynamic>,
        );
        _expectRoomEntry(body, roomId, {for (final MapEntry(:key, :value) in legacy.entries) key: _result(value)});
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
      expect(hls.headers, isEmpty, reason: "3.x's player sent no LOOK headers");
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
    });

    test('the app-only room: live, stream type 50, no streams; its notice; StreamUnavailable', () {
      final room = LookLiveApi.room(_body('S04-room-apponly'), roomId: _appOnly);
      expect((room.state, room.streamType, room.isAppOnly), (LookLiveState.live, 50, true));
      expect(room.variants, isEmpty);
      expect(LookLiveApi.liveRoom(room).notice, '${LookLiveApi.appOnlyNotice}\n${LookLiveApi.chatNotice}');
      expect(room.streamError, isA<StreamUnavailable>());
    });

    test("3.x's room checks on edited copies, before and after the video list", () {
      final legacy = _legacy('S03-room-video')['variants'] as Map<String, dynamic>;
      final bodies = _roomVariants();
      expect(bodies.keys.toSet(), legacy.keys.toSet());
      for (final MapEntry(key: name, value: body) in bodies.entries) {
        final expected = legacy[name] as Map<String, dynamic>;
        _expectRoomEntry(body, _video, expected);
        final refresh = expected['getRoomDetailForRefresh'];
        final kind = _failure(refresh);
        if (kind != null) {
          expect(() => LookLiveApi.room(body, roomId: _video, withMedia: false), _typed(kind), reason: name);
        } else {
          _expectParity(
            _projection(LookLiveApi.liveRoom(LookLiveApi.room(body, roomId: _video, withMedia: false))),
            refresh! as Map<String, dynamic>,
            reason: name,
          );
        }
        if (expected['after the list'] case final Map<String, dynamic> after) {
          _expectRoomEntry(body, _video, after, known: _videoCard());
        }
      }
    });

    test('the live status by state: live, offline; restricted and unknown are errors (3.x: access)', () {
      final legacy = _legacy('S03-room-video')['variants'] as Map<String, dynamic>;
      for (final (name, state) in [
        ('liveStatus 0', LookLiveState.offline),
        ('liveStatus -1', LookLiveState.offline),
        ('liveStatus -10', LookLiveState.restricted),
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
      final restricted = LookLiveApi.liveRoom(LookLiveApi.room(_roomVariants()['liveStatus -10']!, roomId: _video));
      expect(restricted.liveStatus, LiveStatus.unknown, reason: '3.x shows restricted rooms as unknown');
      expect(restricted.notice, '${LookLiveApi.restrictedNotice}\n${LookLiveApi.chatNotice}');
    });

    test('a refreshed stream type 50 room says app-only even with addresses (3.x reads no streams then)', () {
      final legacy = _legacy('S03-room-video')['variants'] as Map<String, dynamic>;
      final body = _roomVariants()['liveStreamType 50']!;
      final refresh = LookLiveApi.liveRoom(LookLiveApi.room(body, roomId: _video, withMedia: false));
      final entry = LookLiveApi.liveRoom(LookLiveApi.room(body, roomId: _video), withData: true);
      expect(refresh.notice, ((legacy['liveStreamType 50'] as Map)['getRoomDetailForRefresh'] as Map)['notice']);
      expect(refresh.notice, contains(LookLiveApi.appOnlyNotice));
      expect(entry.notice, LookLiveApi.chatNotice);
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
      );
      expect(() => LookLiveApi.room('$exact ', roomId: _video), throwsA(isA<ApiChanged>()));
      final wide = '{"code":200,"data":{"x":"${'中' * (LookLiveApi.responseLimit ~/ 3)}"}}';
      expect(wide.length, lessThan(LookLiveApi.responseLimit));
      expect(() => LookLiveApi.room(wide, roomId: _video), throwsA(isA<ApiChanged>()), reason: 'counted in bytes');
    });
  });
}
