// Writes expected.json for the LOOK Live samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.32-looklive.md, "样本与 v3 的冻结输出").
//
// The archive has no LOOK Live expected.json (its legacy harness only
// covered five platforms, spec/sites/looklive.md §11, and 3.x no longer
// builds). The code at the end of this file is 3.x's LookLiveLink,
// LookLiveApi and LookLiveSite, copied from legacy/lib/core/site/looklive/
// (archive/v4) by a script that only makes these edits (each checked to
// apply exactly once): the imports; the network-only `_defaultRequest` and
// `_readBody` are left out, so the transport is required; `extends LiveSite
// implements …`, the `@override` marks and the danmaku getter are left out;
// the site's default api is required. 3.x already injected its transport
// (`LookLiveRequest`), so only that function is replaced: it undoes the two
// AES layers of the weapi form and answers from the samples by path and
// plaintext payload. A request without a sample throws a StateError, which
// 3.x's `_post` reports as a `transport` failure; it is also listed under
// `unmatched`. The requests are written as `POST <url> <payload>`; 3.x sent
// every one with its `requestHeaders` (written once under `headers`).
//
// `i18n` returns 3.x's zh.json text of the keys used. Dio's CancelToken is a
// stub; 3.x's LiveRoom, LiveArea, LiveCategory, LivePlayQuality,
// LivePlayUrlResolution and LiveDirectoryPage are reduced to the parts these
// classes use (constructor defaults, the mutable fields, the state getters,
// selectionId, toJson with 3.x's HttpHeaderPolicy.normalize), as in
// fixtures/jdlive/legacy_expected.dart.
//
// Samples: S01-video-p1, S02-audio-p1/-p2 and S03-room-video/-audio/-notfound
// are the archive's (2026-09-27); S04-video-p2 (the video list's second
// page, which 3.x's merged directory asks for), S04-room-offline (a room of
// S02-audio-p2 that has ended since) and S04-room-apponly (liveStreamType 50
// without media) were recorded for M4.32 (2026-09-28) with 3.x's request.
// Synthetic answers are marked where used: edited copies of the recorded
// answers pin 3.x's rules (`variants`), and a few requests the samples do
// not cover are answered with an edited or the not-found sample.
//
// The output format is the legacy harness's (`roomProjection`,
// `errorProjection`, `{generator, value}`); every call also records the
// requests it sent.
//
// LookLiveApi encrypts with PointyCastle, which the workspace does not
// depend on, so this runs with a throwaway package configuration (the
// version 3.x resolved). From the repository root:
//
//   d=$(mktemp -d)
//   printf 'name: g\nenvironment:\n  sdk: ^3.9.0\ndependencies:\n  pointycastle: 4.0.0\n' > "$d/pubspec.yaml"
//   (cd "$d" && dart pub get --offline)
//   dart --packages="$d/.dart_tool/package_config.json" fixtures/looklive/legacy_expected.dart
//
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';
import 'package:pointycastle/paddings/pkcs7.dart';

const _root = 'fixtures/looklive';

/// S01-video-p1's first card and S03-room-video.
const _video = '21623631';

/// S02-audio-p2's first card and S03-room-audio.
const _audio = '181408025';

/// A card of S02-audio-p2 whose broadcast has ended since (S04-room-offline).
const _offline = '325808387';

/// A room without web media (S04-room-apponly).
const _appOnly = '645235480';

/// Synthetic look-ups answered with S03-room-notfound's body.
const _unknownIds = ['2162', '99999999'];

void main() async {
  await _videoList();
  await _audioList();
  await _audioPage2();
  await _videoPage2();
  await _roomVideo();
  await _roomAudio();
  await _roomMissing();
  await _roomOffline();
  await _roomAppOnly();
}

// Harness ---------------------------------------------------------------------

/// An answer to the POST of [payload] (plaintext JSON) to [path].
final class _Answer {
  _Answer(this.path, this.payload, this.status, this.body);

  final String path;
  final String payload;
  final int status;
  final String body;
}

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync()) as Map<String, dynamic>;

String _body(String sample) => File('$_root/$sample/${_meta(sample)['body']}').readAsStringSync();

String _decrypt(String data, String key) {
  final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
    ..init(
      false,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV(
          KeyParameter(Uint8List.fromList(utf8.encode(key))),
          Uint8List.fromList(utf8.encode('0102030405060708')),
        ),
        null,
      ),
    );
  return utf8.decode(cipher.process(base64Decode(data)));
}

/// The plaintext payload of a weapi form: the two AES layers undone.
String _payload(Map<String, String> form) =>
    _decrypt(_decrypt(form['params']!, '0123456789abcdef'), '0CoJUm6Qyw8W8jud');

/// [sample]'s request path and plaintext payload.
({String path, String payload}) _request(String sample) {
  final request = _meta(sample)['request'] as Map<String, dynamic>;
  return (
    path: Uri.parse(request['url'] as String).path,
    payload: _payload(Uri.splitQueryString(request['body'] as String)),
  );
}

/// [sample]'s answer; [body], [status] and [payload] replace the recorded
/// ones.
_Answer _sample(String sample, {String? body, int? status, String? payload}) {
  final request = _request(sample);
  return _Answer(
    request.path,
    payload ?? request.payload,
    status ?? (_meta(sample)['response'] as Map<String, dynamic>)['status'] as int,
    body ?? _body(sample),
  );
}

const _videoPath = '/weapi/livestream/homepage/recommend';
const _audioPath = '/weapi/livestream/listen/homepage/recommend/list';
const _roomPath = '/weapi/livestream/room/get/v3';

String _listPayload(int page) => jsonEncode({'offset': (page - 1) * 20, 'limit': 20});

String _roomPayload(String id) => jsonEncode({'liveRoomNo': id});

List<_Answer> _answers = [];
final List<String> _requests = [];
final List<String> _unmatched = [];

void _replay(List<_Answer> answers) {
  _answers = answers;
  _requests.clear();
  _unmatched.clear();
}

/// Every recorded sample, and the synthetic not-found look-ups.
List<_Answer> _all() => [
  _sample('S01-video-p1'),
  _sample('S02-audio-p1'),
  _sample('S02-audio-p2'),
  _sample('S04-video-p2'),
  _sample('S03-room-video'),
  _sample('S03-room-audio'),
  _sample('S03-room-notfound'),
  _sample('S04-room-offline'),
  _sample('S04-room-apponly'),
  for (final id in _unknownIds) _sample('S03-room-notfound', payload: _roomPayload(id)),
];

/// 3.x's `LookLiveRequest` over the answers.
Future<({int status, String body})> _fixtureRequest(Uri uri, Map<String, String> form, CancelToken? cancel) async {
  final payload = _payload(form);
  final keys = form.keys.toList()..sort();
  final expectedKey = LookLiveApi.encryptPayload(const {})['encSecKey'];
  final odd = keys.join(',') != 'encSecKey,params' || form['encSecKey'] != expectedKey;
  final line = 'POST $uri $payload${odd ? ' form ${jsonEncode(form)}' : ''}';
  _requests.add(line);
  for (final answer in _answers) {
    if (uri.host == 'api.look.163.com' && answer.path == uri.path && answer.payload == payload) {
      return (status: answer.status, body: answer.body);
    }
  }
  _unmatched.add(line);
  throw StateError('No recorded sample for $line');
}

LookLiveApi _api() => LookLiveApi(request: _fixtureRequest);

LookLiveSite _site() => LookLiveSite(api: _api());

void _write(String sample, String generator, Object? value) {
  final file = File('$_root/$sample/expected.json');
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'generator': generator, 'value': jsonDecode(jsonEncode(value))})}\n',
  );
  stdout.writeln('wrote $sample');
}

Map<String, dynamic> _errorProjection(Object error) => {
  'throws': switch (error) {
    TypeError() => 'TypeError',
    FormatException() => 'FormatException',
    StateError() => 'StateError',
    _ => error.runtimeType.toString(),
  },
  'message': error.toString(),
};

Object? _sync(Object? Function() body) {
  try {
    return body();
  } on Object catch (error) {
    return _errorProjection(error);
  }
}

Future<Object?> _outcome<T>(Future<T> Function() body, Object? Function(T value) project) async {
  try {
    return project(await body());
  } on Object catch (error) {
    return _errorProjection(error);
  }
}

/// [body]'s outcome and the requests it sent.
Future<Map<String, Object?>> _traced<T>(Future<T> Function() body, Object? Function(T value) project) async {
  _requests.clear();
  _unmatched.clear();
  final result = await _outcome(body, project);
  return {
    'result': result,
    'requests': [..._requests],
    if (_unmatched.isNotEmpty) 'unmatched': [..._unmatched],
  };
}

Map<String, dynamic> _roomProjection(LiveRoom room) {
  final json = room.toJson()..['link'] = room.link;
  json.removeWhere(
    (key, value) => value == null || (value is Map && value.isEmpty) || (value is List && value.isEmpty),
  );
  return json;
}

List<Map<String, dynamic>> _rooms(List<LiveRoom> rooms) => [for (final room in rooms) _roomProjection(room)];

Object? _page(LiveDirectoryPage page) => {'rooms': _rooms(page.rooms), 'page': page.page, 'hasMore': page.hasMore};

/// Room ids only, for results whose rooms another entry already lists in
/// full.
List<String?> _ids(List<LiveRoom> rooms) => [for (final room in rooms) room.roomId];

Object? _pageIds(LiveDirectoryPage page) => {'roomIds': _ids(page.rooms), 'page': page.page, 'hasMore': page.hasMore};

Object? _qualities(List<LivePlayQuality> qualities) => [
  for (final quality in qualities)
    {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort, 'data': quality.data},
];

Object? _resolution(LivePlayUrlResolution resolution) => {
  'urls': resolution.urls,
  'appliedQualityData': resolution.appliedQualityData,
};

Object? _lookRoom(LookLiveRoom room) => {
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
    for (final variant in room.variants) {'id': variant.id, 'protocol': variant.protocol, 'uri': '${variant.uri}'},
  ],
};

Object? _lookPage(LookLivePage page, {int? take}) => {
  'rooms': [for (final room in take == null ? page.rooms : page.rooms.take(take)) _lookRoom(room)],
  'hasMore': page.hasMore,
};

LiveArea _area(String id, {String platform = 'looklive', String type = 'official'}) =>
    LiveArea(platform: platform, areaType: type, areaId: id, areaName: id);

LivePlayQuality _quality(String id) => LivePlayQuality(id: id, quality: id);

/// [sample]'s list with the `liveData` of item [index] edited by [edit].
String _editedLive(String sample, void Function(Map<String, dynamic> live) edit, {int index = 0}) {
  final json = jsonDecode(_body(sample)) as Map<String, dynamic>;
  final items = (json['data'] as Map<String, dynamic>)['itemList'] as List;
  edit((items[index] as Map<String, dynamic>)['liveData'] as Map<String, dynamic>);
  return jsonEncode(json);
}

/// [sample]'s list with item [index] edited by [edit].
String _editedItem(String sample, void Function(Map<String, dynamic> item) edit, {int index = 0}) {
  final json = jsonDecode(_body(sample)) as Map<String, dynamic>;
  final items = (json['data'] as Map<String, dynamic>)['itemList'] as List;
  edit(items[index] as Map<String, dynamic>);
  return jsonEncode(json);
}

/// [sample]'s JSON edited by [edit] (the root object).
String _editedRoot(String sample, void Function(Map<String, dynamic> json) edit) {
  final json = jsonDecode(_body(sample)) as Map<String, dynamic>;
  edit(json);
  return jsonEncode(json);
}

/// [sample]'s room answer edited by [edit] (`data`, `roomInfo`, `anchor`).
String _editedRoom(
  String sample,
  void Function(Map<String, dynamic> data, Map<String, dynamic> info, Map<String, dynamic> anchor) edit,
) {
  final json = jsonDecode(_body(sample)) as Map<String, dynamic>;
  final data = json['data'] as Map<String, dynamic>;
  edit(data, data['roomInfo'] as Map<String, dynamic>, data['anchor'] as Map<String, dynamic>);
  return jsonEncode(json);
}

// Lists -----------------------------------------------------------------------

/// Keywords run through 3.x's search: names and titles in other cases,
/// spaces around, a single digit, no match, the recorded rooms (look-ups),
/// room links, a share text, another site's link and blanks.
const _keywords = [
  'Armin',
  'armin VAN',
  'ASOT',
  '电台',
  '  电台  ',
  '1',
  'zzqnomatch',
  _video,
  _audio,
  _offline,
  _appOnly,
  '2162',
  '99999999',
  'https://look.163.com/live?id=$_video',
  'https://look.163.com/live?id=$_video&position=3',
  'LOOK https://look.163.com/live?id=$_video',
  'https://example.com/live?id=$_video',
  '',
  '  ',
];

/// Inputs for 3.x's `LookLiveLink.parseRoomId` (no requests).
const _links = [
  _video,
  ' $_video ',
  '1',
  '12',
  '0123',
  '123456789012345678',
  '1234567890123456789',
  'https://look.163.com/live?id=$_video',
  'https://look.163.com/live?id=$_video&position=3',
  'http://look.163.com/live?id=$_video',
  'HTTPS://LOOK.163.COM/LIVE?id=$_video',
  'https://look.163.com/live/?id=$_video',
  'https://look.163.com//live?id=$_video',
  'https://look.163.com:443/live?id=$_video',
  'https://look.163.com:80/live?id=$_video',
  'http://look.163.com:443/live?id=$_video',
  'https://look.163.com:8443/live?id=$_video',
  'https://user@look.163.com/live?id=$_video',
  'https://look.163.com/live?id=$_video#chat',
  'https://look.163.com/live?id=$_video&id=2',
  'https://look.163.com/live?ID=$_video',
  'https://look.163.com/live?id=0123',
  'https://look.163.com/live?id=1',
  'https://look.163.com/live?id=abc',
  'https://look.163.com/live?id=%3121623631',
  'https://look.163.com/live',
  'https://look.163.com/hot?id=$_video',
  'https://look.163.com/live/$_video',
  'https://look.163.com/live/room?id=$_video',
  'https://look.163.com.evil.test/live?id=$_video',
  'https://m.look.163.com/live?id=$_video',
  'ftp://look.163.com/live?id=$_video',
  'https://look.163.com/%FF?id=$_video',
  'https://look.163.com/live?id=%FF',
  'LOOK https://look.163.com/live?id=$_video',
  'https://look.163.com/live?id=$_video\n',
  'https://look.163.com/live?id=$_video　',
  'look.163.com/live?id=$_video',
];

/// The video list: the category, the merged and per-kind directory, the
/// recommendations and areas, 3.x's search over them, the list cards
/// enriching a detail, the link rules and 3.x's list checks.
Future<void> _videoList() async {
  _replay(_all());
  final value = <String, Object?>{
    'headers': {
      'requestHeaders': LookLiveApi.requestHeaders,
      'mediaHeaders($_video)': LookLiveApi.mediaHeaders(_video),
    },
    'encryptPayload': {
      for (final payload in <Map<String, Object?>>[
        {'offset': 0, 'limit': 20},
        {'offset': 20, 'limit': 20},
        {'liveRoomNo': _video},
        {'liveRoomNo': _audio},
        {'liveRoomNo': _offline},
        {'liveRoomNo': _appOnly},
        {},
      ])
        jsonEncode(payload): LookLiveApi.encryptPayload(payload),
    },
    'getCategores': await _traced(
      () => _site().getCategores(1, 30),
      (categories) => [
        for (final category in categories)
          {
            'id': category.id,
            'name': category.name,
            'children': [for (final area in category.children) area.toJson()],
          },
      ],
    ),
    'getCategores(pageSize: 1)': await _traced(
      () => _site().getCategores(1, 1),
      (categories) => [for (final area in categories.single.children) area.areaId],
    ),
    'getCategores(page: 2)': await _traced(() => _site().getCategores(2, 30), (categories) => categories.length),
    'getCategores(pageSize: 0)': await _traced(() => _site().getCategores(1, 0), (categories) => categories.length),
    'directory(video, 1)': await _traced(() => _api().directory(kind: LookLiveKind.video, page: 1), _lookPage),
    'directory(video, 0)': await _traced(() => _api().directory(kind: LookLiveKind.video, page: 0), _lookPage),
    'directory(video, 10001)': await _traced(
      () => _api().directory(kind: LookLiveKind.video, page: 10001),
      _lookPage,
    ),
  };
  value['getDirectoryPage'] = {
    'page 1': await _traced(() => _site().getDirectoryPage(page: 1), _page),
    'page 2': await _traced(() => _site().getDirectoryPage(page: 2), _pageIds),
    'page 3': await _traced(() => _site().getDirectoryPage(page: 3), _pageIds),
    'video page 1': await _traced(() => _site().getDirectoryPage(page: 1, category: _area('video')), _pageIds),
    'video page 2': await _traced(() => _site().getDirectoryPage(page: 2, category: _area('video')), _pageIds),
    'audio page 1': await _traced(() => _site().getDirectoryPage(page: 1, category: _area('audio')), _pageIds),
    'audio page 2': await _traced(() => _site().getDirectoryPage(page: 2, category: _area('audio')), _pageIds),
    'otherArea': await _traced(() => _site().getDirectoryPage(category: _area('other')), _pageIds),
    'otherType': await _traced(() => _site().getDirectoryPage(category: _area('video', type: 'hot')), _pageIds),
    'otherPlatform': await _traced(
      () => _site().getDirectoryPage(category: _area('video', platform: 'bilibili')),
      _pageIds,
    ),
    'page 0': await _traced(() => _site().getDirectoryPage(page: 0), _pageIds),
    'page 10001': await _traced(() => _site().getDirectoryPage(page: 10001), _pageIds),
  };
  // Page 2 when the video list's second page is empty rather than null
  // (synthetic).
  _replay([
    ..._all().where((answer) => answer.path != _videoPath || answer.payload != _listPayload(2)),
    _Answer(_videoPath, _listPayload(2), 200, jsonEncode({
      'code': 200,
      'data': {'itemList': [], 'hasMore': false},
    })),
  ]);
  (value['getDirectoryPage'] as Map<String, Object?>)['page 2 with an empty video page'] = await _traced(
    () => _site().getDirectoryPage(page: 2),
    _pageIds,
  );
  _replay(_all());
  final recommend = <String, Object?>{};
  for (final (page, size) in [(1, 30), (1, 1), (1, 10), (1, 100), (0, 30), (1, 0), (2, 30)]) {
    recommend['page $page size $size'] = await _traced(
      () => _site().getRecommendRooms(page: page, pageSize: size),
      _ids,
    );
  }
  value['getRecommendRooms'] = recommend;
  value['getCategoryRooms'] = {
    'video page 1': await _traced(() => _site().getCategoryRooms(_area('video')), _ids),
    'audio page 1': await _traced(() => _site().getCategoryRooms(_area('audio')), _ids),
    'audio page 2': await _traced(() => _site().getCategoryRooms(_area('audio'), page: 2), _ids),
    'audio page 1 size 5': await _traced(() => _site().getCategoryRooms(_area('audio'), pageSize: 5), _ids),
    'audio page 0': await _traced(() => _site().getCategoryRooms(_area('audio'), page: 0), _ids),
    'otherArea': await _traced(() => _site().getCategoryRooms(_area('other')), _ids),
  };
  final search = <String, Object?>{};
  for (final keyword in _keywords) {
    search[keyword] = await _traced(
      () => _site().searchRoomsCancellable(keyword, cancel: CancelToken()),
      keyword == '1' ? _ids : _rooms,
    );
  }
  search['Armin page 2'] = await _traced(() => _site().searchRoomsCancellable('Armin', page: 2), _ids);
  search['$_video page 2'] = await _traced(() => _site().searchRoomsCancellable(_video, page: 2), _ids);
  search['电台 size 1'] = await _traced(() => _site().searchRoomsCancellable('电台', pageSize: 1), _ids);
  search['电台 size 100'] = await _traced(() => _site().searchRoomsCancellable('电台', pageSize: 100), _ids);
  search['电台 size 101'] = await _traced(() => _site().searchRoomsCancellable('电台', pageSize: 101), _ids);
  search['电台 size 0'] = await _traced(() => _site().searchRoomsCancellable('电台', pageSize: 0), _ids);
  search['Armin without a token'] = await _traced(() => _site().searchRooms('Armin'), _rooms);
  value['searchRoomsCancellable'] = search;
  // The list cards fill what the room answer lacks (3.x's `_known`).
  var site = _site();
  final known = <String, Object?>{
    'getRoomDetailForRefresh before the list': await _traced(
      () => site.getRoomDetailForRefresh(roomId: _video, platform: 'looklive'),
      _roomProjection,
    ),
    'getDirectoryPage 1': await _traced(() => site.getDirectoryPage(page: 1), (page) => page.rooms.length),
    'getRoomDetailForRefresh after the list': await _traced(
      () => site.getRoomDetailForRefresh(roomId: _video, platform: 'looklive'),
      _roomProjection,
    ),
    'getRoomDetail after the list': await _traced(
      () => site.getRoomDetail(roomId: _video, platform: 'looklive'),
      _roomProjection,
    ),
    'searchRooms after the list': await _traced(() => site.searchRooms(_video), _rooms),
  };
  site = _site();
  await site.getRoomDetail(roomId: _video, platform: 'looklive');
  known['getDirectoryPage 1 after the room'] = await _traced(
    () => site.getDirectoryPage(page: 1),
    (page) => _roomProjection(page.rooms.first),
  );
  site = _site();
  await site.searchRoomsCancellable('Armin', cancel: CancelToken());
  known['getRoomDetailForRefresh after a search'] = await _traced(
    () => site.getRoomDetailForRefresh(roomId: _video, platform: 'looklive'),
    _roomProjection,
  );
  value['known'] = known;
  value['LookLiveLink.parseRoomId'] = {for (final link in _links) link: LookLiveLink.parseRoomId(link)};
  value['LookLiveLink.watchUrl'] = {
    for (final id in [_video, ' $_video ', 'https://look.163.com/live?id=$_video&x=1', '1', 'abc'])
      id: _sync(() => LookLiveLink.watchUrl(id)),
  };
  value['variants'] = await _listVariants();
  _write(
    'S01-video-p1',
    'LookLiveSite.getCategores + getDirectoryPage + getRecommendRooms + getCategoryRooms + searchRoomsCancellable '
        '(with every other sample; synthetic: an empty video page 2, not-found look-ups of 2162 and 99999999) + '
        'LookLiveApi.directory + encryptPayload + LookLiveLink; variants: LookLiveApi.directory of edited copies',
    value,
  );
}

/// 3.x's list checks on edited copies of S01-video-p1 (the video list).
Future<Map<String, Object?>> _listVariants() async {
  Future<Object?> parse(String body, {String path = _videoPath, LookLiveKind kind = LookLiveKind.video}) async {
    _replay([_Answer(path, _listPayload(1), 200, body)]);
    return _outcome(() => _api().directory(kind: kind, page: 1), (page) => _lookPage(page, take: 2));
  }

  Future<Object?> live(void Function(Map<String, dynamic> live) edit, {int index = 0}) =>
      parse(_editedLive('S01-video-p1', edit, index: index));

  Future<Object?> item(void Function(Map<String, dynamic> item) edit) => parse(_editedItem('S01-video-p1', edit));

  Future<Object?> root(void Function(Map<String, dynamic> json) edit) => parse(_editedRoot('S01-video-p1', edit));

  Future<Object?> data(void Function(Map<String, dynamic> data) edit) =>
      root((json) => edit(json['data'] as Map<String, dynamic>));

  Map<String, dynamic> user(Map<String, dynamic> live) => live['userInfo'] as Map<String, dynamic>;
  Map<String, dynamic> urls(Map<String, dynamic> live) => live['liveUrl'] as Map<String, dynamic>;
  const flv = 'http://pull0583d674.live.126.net/live/800897349fe246e994f36976011de4d5.flv';
  const hls = 'http://pull0583d674.live.126.net/live/800897349fe246e994f36976011de4d5/playlist.m3u8';
  final items = ((jsonDecode(_body('S01-video-p1')) as Map)['data'] as Map)['itemList'] as List;
  final result = <String, Object?>{
    'recorded': await parse(_body('S01-video-p1')),
    'type number 1': await item((i) => i['type'] = 1),
    'type 2': await item((i) => i['type'] = '2'),
    'type missing': await item((i) => i.remove('type')),
    'liveData null': await item((i) => i['liveData'] = null),
    'liveData text': await item((i) => i['liveData'] = 'x'),
    'item not an object': await data((d) => (d['itemList'] as List).insert(0, 5)),
    'liveType 2': await live((l) => l['liveType'] = 2),
    'liveType 3': await live((l) => l['liveType'] = 3),
    'liveType text': await live((l) => l['liveType'] = '1'),
    'liveType missing': await live((l) => l.remove('liveType')),
    'userInfo missing': await live((l) => l.remove('userInfo')),
    'liveRoomNo text': await live((l) => user(l)['liveRoomNo'] = '$_video'),
    'liveRoomNo spaced text': await live((l) => user(l)['liveRoomNo'] = ' $_video '),
    'liveRoomNo 0': await live((l) => user(l)['liveRoomNo'] = 0),
    'liveRoomNo one digit': await live((l) => user(l)['liveRoomNo'] = 7),
    'liveRoomNo 19 digits': await live((l) => user(l)['liveRoomNo'] = 1234567890123456789),
    'liveRoomNo missing': await live((l) => user(l).remove('liveRoomNo')),
    'userId missing': await live((l) => user(l).remove('userId')),
    'liveId missing': await live((l) => l.remove('liveId')),
    'liveTitle missing': await live((l) => l.remove('liveTitle')),
    'liveTitle number': await live((l) => l['liveTitle'] = 5),
    'liveTitle spaced': await live((l) => l['liveTitle'] = '  a  b \n'),
    'nickname missing': await live((l) => user(l).remove('nickname')),
    'avatarUrl missing': await live((l) => user(l).remove('avatarUrl')),
    'avatarUrl https': await live((l) => user(l)['avatarUrl'] = 'https://p3.music.126.net/a.jpg'),
    'avatarUrl with port': await live((l) => user(l)['avatarUrl'] = 'http://p3.music.126.net:8080/a.jpg'),
    'avatarUrl protocol-relative': await live((l) => user(l)['avatarUrl'] = '//p3.music.126.net/a.jpg'),
    'avatarUrl ftp': await live((l) => user(l)['avatarUrl'] = 'ftp://p3.music.126.net/a.jpg'),
    'avatarUrl user info': await live((l) => user(l)['avatarUrl'] = 'http://u@p3.music.126.net/a.jpg'),
    'avatarUrl fragment': await live((l) => user(l)['avatarUrl'] = 'http://p3.music.126.net/a.jpg#x'),
    'avatarUrl other host': await live((l) => user(l)['avatarUrl'] = 'http://example.com/a.jpg'),
    'liveCoverUrl missing': await live((l) => l.remove('liveCoverUrl')),
    'popularity missing': await live((l) => l.remove('popularity')),
    'popularity text': await live((l) => l['popularity'] = '12'),
    'popularity negative': await live((l) => l['popularity'] = -1),
    'popularity fraction': await live((l) => l['popularity'] = 1.5),
    'onlineNumber missing': await live((l) => l.remove('onlineNumber')),
    'onlineNumber zero': await live((l) => l['onlineNumber'] = 0),
    'onlineNumber negative': await live((l) => l['onlineNumber'] = -3),
    'onlineNumber text': await live((l) => l['onlineNumber'] = '9'),
    'liveUrl null': await live((l) => l['liveUrl'] = null),
    'liveUrl text': await live((l) => l['liveUrl'] = 'x'),
    'liveUrl empty': await live((l) => l['liveUrl'] = <String, Object?>{}),
    'hlsPullUrl missing': await live((l) => urls(l).remove('hlsPullUrl')),
    'httpPullUrl empty': await live((l) => urls(l)['httpPullUrl'] = ''),
    'hlsPullUrl https': await live((l) => urls(l)['hlsPullUrl'] = hls.replaceFirst('http:', 'https:')),
    'hlsPullUrl with query': await live((l) => urls(l)['hlsPullUrl'] = '$hls?netease=x'),
    'hlsPullUrl upper-case scheme': await live((l) => urls(l)['hlsPullUrl'] = hls.replaceFirst('http:', 'HTTP:')),
    'hlsPullUrl spaced': await live((l) => urls(l)['hlsPullUrl'] = ' $hls '),
    'hlsPullUrl other host': await live(
      (l) => urls(l)['hlsPullUrl'] = hls.replaceFirst('pull0583d674.live.126.net', 'example.com'),
    ),
    'hlsPullUrl lookalike host': await live(
      (l) => urls(l)['hlsPullUrl'] = hls.replaceFirst('live.126.net', 'live.126.net.evil.test'),
    ),
    'hlsPullUrl with port': await live((l) => urls(l)['hlsPullUrl'] = hls.replaceFirst('.net/', '.net:8080/')),
    'hlsPullUrl user info': await live((l) => urls(l)['hlsPullUrl'] = hls.replaceFirst('//', '//u@')),
    'hlsPullUrl fragment': await live((l) => urls(l)['hlsPullUrl'] = '$hls#x'),
    'hlsPullUrl upper-case key': await live(
      (l) => urls(l)['hlsPullUrl'] = hls.replaceFirst('800897349fe246e9', '800897349FE246E9'),
    ),
    'hlsPullUrl as FLV': await live((l) => urls(l)['hlsPullUrl'] = flv),
    'hlsPullUrl rtmp': await live((l) => urls(l)['hlsPullUrl'] = hls.replaceFirst('http:', 'rtmp:')),
    'hlsPullUrl long query': await live((l) => urls(l)['hlsPullUrl'] = '$hls?${'a' * 2049}'),
    'httpPullUrl number': await live((l) => urls(l)['httpPullUrl'] = 7),
    'httpPullUrl without query': await live((l) => urls(l)['httpPullUrl'] = flv),
    'httpPullUrl as HLS': await live((l) => urls(l)['httpPullUrl'] = hls),
    'liveStreamType 50 without liveUrl': await live((l) {
      l['liveStreamType'] = 50;
      l['liveUrl'] = null;
    }),
    'second card repeats the first': await live((l) => user(l)['liveRoomNo'] = int.parse(_video), index: 1),
    'itemList null': await data((d) => d['itemList'] = null),
    'itemList not a list': await data((d) => d['itemList'] = <String, Object?>{}),
    'itemList empty': await data((d) => d['itemList'] = []),
    'itemList 100 entries': await data((d) => d['itemList'] = List.filled(100, items.first)),
    'itemList 101 entries': await data((d) => d['itemList'] = List.filled(101, items.first)),
    'hasMore missing': await data((d) => d.remove('hasMore')),
    'hasMore text': await data((d) => d['hasMore'] = 'true'),
    'hasMore true': await data((d) => d['hasMore'] = true),
    'code 404': await root((j) => j['code'] = 404),
    'code 424': await root((j) => j['code'] = 424),
    'code 520': await root((j) => j['code'] = 520),
    'code 522': await root((j) => j['code'] = 522),
    'code 555': await root((j) => j['code'] = 555),
    'code 500': await root((j) => j['code'] = 500),
    'code 301': await root((j) => j['code'] = 301),
    'code text': await root((j) => j['code'] = '200'),
    'code missing': await root((j) => j.remove('code')),
    'data null': await root((j) => j['data'] = null),
    'data list': await root((j) => j['data'] = []),
    'root list': await parse('[]'),
    'not JSON': await parse('<html></html>'),
    'empty body': await parse(''),
    'audio list answered with this video list': await parse(
      _body('S01-video-p1'),
      path: _audioPath,
      kind: LookLiveKind.audio,
    ),
  };
  // The site maps each card with LookLiveLink.watchUrl (2 to 18 digits).
  for (final (name, number) in [('liveRoomNo one digit', 7), ('liveRoomNo 19 digits', 1234567890123456789)]) {
    final body = _editedLive('S01-video-p1', (l) => user(l)['liveRoomNo'] = number);
    _replay([_Answer(_videoPath, _listPayload(1), 200, body)]);
    result['getDirectoryPage(video): $name'] = await _outcome(
      () => _site().getDirectoryPage(category: _area('video')),
      _pageIds,
    );
  }
  _replay([_Answer(_videoPath, _listPayload(1), 200, _editedLive('S01-video-p1', (l) => user(l).remove('avatarUrl')))]);
  result['getDirectoryPage(video): avatarUrl missing'] = await _outcome(
    () => _site().getDirectoryPage(category: _area('video')),
    (page) => _roomProjection(page.rooms.first),
  );
  _replay([_Answer(_videoPath, _listPayload(1), 200, _editedLive('S01-video-p1', (l) => l.remove('onlineNumber')))]);
  result['getDirectoryPage(video): onlineNumber missing'] = await _outcome(
    () => _site().getDirectoryPage(category: _area('video')),
    (page) => _roomProjection(page.rooms.first),
  );
  _replay([
    _Answer(
      _videoPath,
      _listPayload(1),
      200,
      _editedLive('S01-video-p1', (l) {
        l.remove('onlineNumber');
        l.remove('popularity');
      }),
    ),
  ]);
  result['getDirectoryPage(video): no audience'] = await _outcome(
    () => _site().getDirectoryPage(category: _area('video')),
    (page) => _roomProjection(page.rooms.first),
  );
  _replay([
    _Answer(
      _videoPath,
      _listPayload(1),
      200,
      _editedLive('S01-video-p1', (l) {
        l['liveStreamType'] = 50;
        l['liveUrl'] = null;
      }),
    ),
  ]);
  result['getDirectoryPage(video): liveStreamType 50 without liveUrl'] = await _outcome(
    () => _site().getDirectoryPage(category: _area('video')),
    (page) => _roomProjection(page.rooms.first),
  );
  return result;
}

/// The voice list: its cards, and the injected video card kept by the video
/// list's rule.
Future<void> _audioList() async {
  _replay(_all());
  final value = <String, Object?>{
    'directory(audio, 1)': await _traced(() => _api().directory(kind: LookLiveKind.audio, page: 1), _lookPage),
  };
  _replay([_videoAnswer(_body('S02-audio-p1'))]);
  value['directory(video, 1) answered with this list'] = await _traced(
    () => _api().directory(kind: LookLiveKind.video, page: 1),
    _lookPage,
  );
  value['getCategoryRooms(video) answered with this list'] = await _traced(
    () => _site().getCategoryRooms(_area('video')),
    _rooms,
  );
  _write(
    'S02-audio-p1',
    'LookLiveApi.directory (audio page 1; video page 1 answered with this list) + '
        'LookLiveSite.getCategoryRooms (video, answered with this list)',
    value,
  );
}

_Answer _videoAnswer(String body) => _Answer(_videoPath, _listPayload(1), 200, body);

/// The voice list's second page.
Future<void> _audioPage2() async {
  _replay(_all());
  _write('S02-audio-p2', 'LookLiveApi.directory (audio page 2) + LookLiveSite.getCategoryRooms (audio page 2)', {
    'directory(audio, 2)': await _traced(() => _api().directory(kind: LookLiveKind.audio, page: 2), _lookPage),
    'getCategoryRooms(audio, 2)': await _traced(() => _site().getCategoryRooms(_area('audio'), page: 2), _rooms),
  });
}

/// The video list's second page (`itemList` null), which 3.x's merged
/// directory asks for.
Future<void> _videoPage2() async {
  _replay(_all());
  _write(
    'S04-video-p2',
    'LookLiveApi.directory (video page 2) + LookLiveSite.getDirectoryPage + getRecommendRooms + getCategoryRooms '
        '(page 2, with S02-audio-p2)',
    {
      'directory(video, 2)': await _traced(() => _api().directory(kind: LookLiveKind.video, page: 2), _lookPage),
      'getDirectoryPage(page: 2)': await _traced(() => _site().getDirectoryPage(page: 2), _pageIds),
      'getRecommendRooms(page: 2)': await _traced(() => _site().getRecommendRooms(page: 2), _ids),
      'getCategoryRooms(video, 2)': await _traced(() => _site().getCategoryRooms(_area('video'), page: 2), _ids),
    },
  );
}

// Rooms -----------------------------------------------------------------------

/// The rooms at every depth, the live status, the qualities, the URLs and
/// the recovery of [id], with every request.
Future<Map<String, Object?>> _roomCalls(String id) async {
  final site = _site();
  final entry = <String, Object?>{
    'getRoomDetail': await _traced(() => site.getRoomDetail(roomId: id, platform: 'looklive'), _roomProjection),
    'getRoomDetailForRefresh': await _traced(
      () => site.getRoomDetailForRefresh(roomId: id, platform: 'looklive'),
      _roomProjection,
    ),
    'getRoomDetailForRecording': await _traced(
      () => site.getRoomDetailForRecording(roomId: id, platform: 'looklive'),
      _roomProjection,
    ),
    'getLiveStatus': await _traced(() => site.getLiveStatus(roomId: id, platform: 'looklive'), (live) => live),
  };
  for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
    final fresh = _site();
    LiveRoom? detail;
    try {
      detail = await switch (depth) {
        'getRoomDetail' => fresh.getRoomDetail(roomId: id, platform: 'looklive'),
        'getRoomDetailForRefresh' => fresh.getRoomDetailForRefresh(roomId: id, platform: 'looklive'),
        _ => fresh.getRoomDetailForRecording(roomId: id, platform: 'looklive'),
      };
    } on Object {
      detail = null;
    }
    if (detail == null) continue;
    final room = detail;
    entry['$depth → getPlayQualites'] = await _traced(() => fresh.getPlayQualites(detail: room), _qualities);
    for (final quality in ['hls:source', 'flv:source', 'auto']) {
      entry['$depth → resolvePlayUrlsRaw($quality)'] = await _traced(
        () => fresh.resolvePlayUrlsRaw(detail: room, quality: _quality(quality)),
        _resolution,
      );
    }
    for (final quality in ['flv:source', 'auto']) {
      entry['$depth → resolvePlayUrlsForRecoveryRaw($quality)'] = await _traced(
        () => fresh.resolvePlayUrlsForRecoveryRaw(detail: room, quality: _quality(quality)),
        _resolution,
      );
    }
    entry['$depth → getPlayUrls(hls:source)'] = await _traced(
      () => fresh.getPlayUrls(detail: room, quality: _quality('hls:source')),
      (urls) => urls,
    );
  }
  entry['otherPlatform'] = await _traced(
    () => _site().getRoomDetail(roomId: id, platform: 'bilibili'),
    _roomProjection,
  );
  entry['platform in another case'] = await _traced(
    () => _site().getRoomDetailForRefresh(roomId: id, platform: ' LookLive '),
    _roomProjection,
  );
  entry['room link as id'] = await _traced(
    () => _site().getRoomDetailForRefresh(roomId: 'https://look.163.com/live?id=$id', platform: 'looklive'),
    _roomProjection,
  );
  entry['api.room'] = await _traced(() => _api().room(id), _lookRoom);
  entry['api.room(includeMedia: false)'] = await _traced(() => _api().room(id, includeMedia: false), _lookRoom);
  return entry;
}

/// The recorded video room: every depth, the list cards filling it, the
/// media rules and 3.x's room checks on edited copies.
Future<void> _roomVideo() async {
  _replay(_all());
  final value = <String, Object?>{
    'recorded': await _roomCalls(_video),
    'invalid ids': {
      for (final id in ['', '1', 'abc', '0123', 'https://look.163.com/hot?id=$_video'])
        id: await _traced(() => _site().getRoomDetail(roomId: id, platform: 'looklive'), _roomProjection),
    },
  };
  var site = _site();
  await site.getDirectoryPage(page: 1);
  value['after the list'] = {
    'getRoomDetail': await _traced(() => site.getRoomDetail(roomId: _video, platform: 'looklive'), _roomProjection),
    'getLiveStatus': await _traced(() => site.getLiveStatus(roomId: _video, platform: 'looklive'), (live) => live),
  };
  // The answer for another room number (synthetic).
  _replay([_sample('S03-room-video', payload: _roomPayload('21623632'))]);
  value['api.room(21623632) answered with this room'] = await _traced(() => _api().room('21623632'), _lookRoom);
  const flv = 'http://pull0583d674.live.126.net/live/800897349fe246e994f36976011de4d5.flv?netease=x';
  const hls = 'http://pull0583d674.live.126.net/live/800897349fe246e994f36976011de4d5/playlist.m3u8';
  value['LookLiveApi.mediaUri'] = {
    for (final (raw, protocol) in [
      (hls, 'hls'),
      (flv, 'flv'),
      (hls, 'flv'),
      (flv, 'hls'),
      (hls, 'rtmp'),
      (' $hls ', 'hls'),
      (hls.replaceFirst('http:', 'https:'), 'hls'),
      (hls.replaceFirst('http:', 'HTTPS:'), 'hls'),
      (hls.replaceFirst('pull0583d674', 'PULL0583D674'), 'hls'),
      (hls.replaceFirst('pull0583d674.', ''), 'hls'),
      (hls.replaceFirst('pull0583d674.', 'a.b.'), 'hls'),
      (hls.replaceFirst('pull0583d674', 'pull_1'), 'hls'),
      (hls.replaceFirst('.net/', '.net:80/'), 'hls'),
      ('$hls?${'a' * 2048}', 'hls'),
      ('$hls?${'a' * 2049}', 'hls'),
      ('$hls/', 'hls'),
      (hls.replaceFirst('/live/', '/live//'), 'hls'),
      (hls.replaceFirst('/live/', '/vod/'), 'hls'),
      ('', 'hls'),
    ])
      '$protocol $raw': _sync(() => '${LookLiveApi.mediaUri(raw, protocol: protocol)}'),
  };
  value['variants'] = await _roomVariants();
  _write(
    'S03-room-video',
    'LookLiveSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
        'getPlayQualites + resolvePlayUrlsRaw + resolvePlayUrlsForRecoveryRaw + getPlayUrls + LookLiveApi.room + '
        'mediaUri (with S01-video-p1, S02-audio-p1; synthetic: this answer for room 21623632); '
        'variants: edited copies at every depth',
    value,
  );
}

/// 3.x's room checks: the room at every depth for edited copies of
/// S03-room-video, before and after the video list.
Future<Map<String, Object?>> _roomVariants() async {
  const hls = 'http://pull0583d674.live.126.net/live/800897349fe246e994f36976011de4d5/playlist.m3u8';
  final variants = <String, void Function(Map<String, dynamic> data, Map<String, dynamic> info, Map<String, dynamic> anchor)>{
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
    'hlsPullUrl missing': (d, i, a) => (i['liveUrl'] as Map<String, dynamic>).remove('hlsPullUrl'),
    'httpPullUrl missing': (d, i, a) => (i['liveUrl'] as Map<String, dynamic>).remove('httpPullUrl'),
    'hlsPullUrl other host': (d, i, a) =>
        (i['liveUrl'] as Map<String, dynamic>)['hlsPullUrl'] = hls.replaceFirst('pull0583d674.live.126.net', 'x.cn'),
    'liveStatus -1 with an invalid hlsPullUrl': (d, i, a) {
      d['liveStatus'] = -1;
      (i['liveUrl'] as Map<String, dynamic>)['hlsPullUrl'] = 'x';
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
  final bodies = <String, String>{
    for (final MapEntry(key: name, value: edit) in variants.entries) name: _editedRoom('S03-room-video', edit),
    for (final MapEntry(key: name, value: edit) in roots.entries) name: _editedRoot('S03-room-video', edit),
  };
  final result = <String, Object?>{};
  for (final MapEntry(key: name, value: body) in bodies.entries) {
    final answers = [
      _sample('S01-video-p1'),
      _sample('S02-audio-p1'),
      _sample('S03-room-video', body: body),
    ];
    _replay(answers);
    final entry = await _variantCalls(_site());
    if (const {
      'liveUrl null',
      'liveUrl empty',
      'liveStreamType 50 without liveUrl',
      'liveStreamType missing without liveUrl',
      'hlsPullUrl missing',
      'liveStatus -10',
      'liveStatus -1',
    }.contains(name)) {
      final site = _site();
      await site.getDirectoryPage(page: 1);
      entry['after the list'] = await _variantCalls(site);
    }
    result[name] = entry;
  }
  return result;
}

Future<Map<String, Object?>> _variantCalls(LookLiveSite site) async {
  final entry = <String, Object?>{
    'getRoomDetailForRefresh': await _outcome(
      () => site.getRoomDetailForRefresh(roomId: _video, platform: 'looklive'),
      _roomProjection,
    ),
    'getLiveStatus': await _outcome(() => site.getLiveStatus(roomId: _video, platform: 'looklive'), (l) => l),
  };
  LiveRoom? detail;
  try {
    detail = await site.getRoomDetail(roomId: _video, platform: 'looklive');
    entry['getRoomDetail'] = _roomProjection(detail);
  } on Object catch (error) {
    entry['getRoomDetail'] = _errorProjection(error);
  }
  if (detail != null) {
    final room = detail;
    entry['getRoomDetail → getPlayQualites'] = await _outcome(() => site.getPlayQualites(detail: room), _qualities);
    for (final quality in ['hls:source', 'flv:source']) {
      entry['getRoomDetail → resolvePlayUrlsRaw($quality)'] = await _outcome(
        () => site.resolvePlayUrlsRaw(detail: room, quality: _quality(quality)),
        _resolution,
      );
    }
  }
  return entry;
}

/// The recorded voice room, also after the voice list's second page (its
/// first card).
Future<void> _roomAudio() async {
  _replay(_all());
  final value = <String, Object?>{'recorded': await _roomCalls(_audio)};
  final site = _site();
  await site.getCategoryRooms(_area('audio'), page: 2);
  value['after audio page 2'] = {
    'getRoomDetail': await _traced(() => site.getRoomDetail(roomId: _audio, platform: 'looklive'), _roomProjection),
    'getRoomDetailForRefresh': await _traced(
      () => site.getRoomDetailForRefresh(roomId: _audio, platform: 'looklive'),
      _roomProjection,
    ),
  };
  _write(
    'S03-room-audio',
    'LookLiveSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
        'getPlayQualites + resolvePlayUrlsRaw + resolvePlayUrlsForRecoveryRaw + getPlayUrls + LookLiveApi.room '
        '(with S02-audio-p2)',
    value,
  );
}

/// The not-found answer at every depth and in the search; the HTTP statuses
/// and bodies 3.x mapped, answering the room and list requests.
Future<void> _roomMissing() async {
  _replay(_all());
  // The sample asked for room "1", a number 3.x never sends (room numbers
  // have 2 to 18 digits); its answer is replayed for 99999999 (synthetic).
  const id = '99999999';
  final value = <String, Object?>{
    'request': _request('S03-room-notfound').payload,
    'api.room(1)': await _traced(() => _api().room('1'), _lookRoom),
    'recorded': await _roomCalls(id),
    'searchRooms': await _traced(() => _site().searchRooms(id), _rooms),
  };
  for (final status in [401, 403, 404, 429, 500, 502, 503, 302, 400, 204]) {
    _replay([_sample('S03-room-video', status: status, body: '')]);
    final site = _site();
    value['room status $status'] = {
      'getRoomDetail': await _traced(() => site.getRoomDetail(roomId: _video, platform: 'looklive'), _roomProjection),
      'getRoomDetailForRefresh': await _traced(
        () => site.getRoomDetailForRefresh(roomId: _video, platform: 'looklive'),
        _roomProjection,
      ),
      'getLiveStatus': await _traced(() => site.getLiveStatus(roomId: _video, platform: 'looklive'), (l) => l),
      'searchRooms': await _traced(() => site.searchRooms(_video), _rooms),
    };
  }
  for (final (name, status, body) in [
    ('empty 200', 200, ''),
    ('not JSON', 200, '<html></html>'),
    ('over 2 MiB', 200, '{"code":200,"data":{}}${' ' * (2 * 1024 * 1024)}'),
    ('at 2 MiB', 200, _paddedTo(_body('S03-room-video'), 2 * 1024 * 1024)),
  ]) {
    _replay([_sample('S03-room-video', status: status, body: body)]);
    value['room $name'] = await _traced(
      () => _site().getRoomDetailForRefresh(roomId: _video, platform: 'looklive'),
      _roomProjection,
    );
  }
  for (final (name, status, body) in [
    ('status 404', 404, ''),
    ('status 503', 503, ''),
    ('not JSON', 200, 'x'),
  ]) {
    _replay([_sample('S01-video-p1', status: status, body: body), _sample('S02-audio-p1')]);
    value['video list $name'] = {
      'getDirectoryPage': await _traced(() => _site().getDirectoryPage(page: 1), _pageIds),
      'getCategoryRooms(audio)': await _traced(() => _site().getCategoryRooms(_area('audio')), _ids),
      'searchRooms': await _traced(() => _site().searchRooms('电台'), _ids),
    };
  }
  _write(
    'S03-room-notfound',
    "LookLiveSite's rooms, live status and search on this answer (replayed for room 99999999: the sample asked for "
        'room 1, which 3.x never sends); the room request answered with each HTTP status '
        'and with bodies that are empty, not JSON or over 2 MiB; the video list answered with 404, 503 and not JSON',
    value,
  );
}

/// [body] padded with trailing spaces to exactly [bytes] UTF-8 bytes.
String _paddedTo(String body, int bytes) => '$body${' ' * (bytes - utf8.encode(body).length)}';

/// A room of S02-audio-p2 that has ended since: every depth, and after the
/// list that saw it live (the same broadcast).
Future<void> _roomOffline() async {
  _replay(_all());
  final value = <String, Object?>{'recorded': await _roomCalls(_offline)};
  final site = _site();
  await site.getCategoryRooms(_area('audio'), page: 2);
  value['after audio page 2'] = {
    'getRoomDetailForRefresh': await _traced(
      () => site.getRoomDetailForRefresh(roomId: _offline, platform: 'looklive'),
      _roomProjection,
    ),
    'getRoomDetail': await _traced(() => site.getRoomDetail(roomId: _offline, platform: 'looklive'), _roomProjection),
    'getLiveStatus': await _traced(() => site.getLiveStatus(roomId: _offline, platform: 'looklive'), (l) => l),
  };
  _write(
    'S04-room-offline',
    'LookLiveSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
        'getPlayQualites + resolvePlayUrlsRaw + resolvePlayUrlsForRecoveryRaw + getPlayUrls + LookLiveApi.room '
        '(with S02-audio-p2)',
    value,
  );
}

/// A live room without web media (liveStreamType 50).
Future<void> _roomAppOnly() async {
  _replay(_all());
  _write(
    'S04-room-apponly',
    'LookLiveSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
        'getPlayQualites + resolvePlayUrlsRaw + resolvePlayUrlsForRecoveryRaw + getPlayUrls + LookLiveApi.room',
    {'recorded': await _roomCalls(_appOnly)},
  );
}

// Stubs -----------------------------------------------------------------------

/// Dio's CancelToken, reduced to what 3.x's LOOK Live classes use.
class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

String i18n(String key) =>
    const {
      'site_looklive': 'LOOK 直播',
      'looklive_category_video': '视频直播',
      'looklive_category_audio': '语音直播',
      'looklive_chat_notice': 'LOOK 远端聊天尚待接入；官网 popularity 按平台热度展示，onlineNumber 按当前观看人数单独展示。',
      'looklive_restricted_notice': '该 LOOK 直播受私密房或账号访问条件限制，界面保持未知状态。',
      'looklive_app_only_notice': '该直播使用官网未开放网页媒体的房型，请在 LOOK 客户端中观看。',
      'looklive_quality_hls': 'HLS 原始线路',
      'looklive_quality_flv': 'FLV 原始线路',
    }[key] ??
    (throw StateError('No zh.json text for $key'));

// 3.x models (the parts the LOOK Live classes use) -----------------------------

enum LiveStatus { live, offline, replay, unknown, banned }

enum AudienceMetricType { popularity, onlineViewers, totalViewers, followers, unknown }

class HttpHeaderPolicy {
  static final RegExp _validName = RegExp(r'^[a-z0-9-]+$');

  static Map<String, String> normalize(Map<dynamic, dynamic>? source) {
    if (source == null || source.isEmpty) return const <String, String>{};
    final result = <String, String>{};
    for (final entry in source.entries) {
      if (entry.key is! String || entry.value is! String) continue;
      final name = canonicalName(entry.key as String);
      final value = (entry.value as String).replaceAll(RegExp(r'[\u0000-\u001F\u007F]+'), ' ').trim();
      if (name != null && value.isNotEmpty) result[name] = value;
    }
    if (result.isEmpty) return const <String, String>{};
    final sorted = result.entries.toList()..sort((left, right) => left.key.compareTo(right.key));
    return Map<String, String>.unmodifiable({for (final entry in sorted) entry.key: entry.value});
  }

  static String? canonicalName(String raw) {
    var name = raw.trim().toLowerCase();
    if (name.startsWith('!')) name = name.substring(1);
    name = switch (name) {
      'http-user-agent' => 'user-agent',
      'http-referrer' || 'http-referer' || 'referrer' => 'referer',
      'cookies' => 'cookie',
      _ => name,
    };
    return name.isNotEmpty && _validName.hasMatch(name) ? name : null;
  }
}

class LiveArea {
  LiveArea({this.platform, this.areaType, this.typeName, this.areaId, this.areaName, this.areaPic, this.shortName});

  String? platform;
  String? areaType;
  String? typeName;
  String? areaId;
  String? areaName;
  String? areaPic;
  String? shortName;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'platform': platform,
    'areaType': areaType,
    'typeName': typeName,
    'areaId': areaId,
    'areaName': areaName,
    'areaPic': areaPic,
    'shortName': shortName,
  };
}

class LiveCategory {
  LiveCategory({required this.id, required this.name, required this.children});

  final String name;
  final String id;
  final List<LiveArea> children;
}

class LivePlayQuality {
  LivePlayQuality({required this.quality, this.data, this.id, this.sort = 0});

  final String quality;
  final dynamic data;
  final Object? id;
  final int sort;

  Object get selectionId => id ?? quality;
}

class LivePlayUrlResolution {
  const LivePlayUrlResolution({required this.urls, this.appliedQualityData});

  final List<String> urls;
  final Object? appliedQualityData;
}

class LiveDirectoryPage {
  LiveDirectoryPage({required Iterable<LiveRoom> rooms, required this.page, required this.hasMore})
    : rooms = List.unmodifiable(rooms);
  final List<LiveRoom> rooms;
  final int page;
  final bool hasMore;
}

class LiveRoom {
  LiveRoom({
    this.roomId,
    this.userId,
    this.link,
    this.title = '',
    this.nick = '',
    this.avatar = '',
    this.cover = '',
    this.area,
    this.watching = '0',
    this.audienceMetricType,
    this.popularity = '',
    this.onlineViewers = '',
    this.totalViewers = '',
    this.followers = '0',
    this.platform,
    LiveStatus? liveStatus,
    this.data,
    this.danmakuData,
    this.isRecord = false,
    this.status = false,
    this.notice,
    this.introduction,
    this.httpHeaders = const <String, String>{},
  }) : liveStatus = liveStatus ?? _legacyStatusToLiveStatus(status: status, isRecord: isRecord);

  String? roomId;
  String? userId;
  String? link;
  String? title;
  String? nick;
  String? avatar;
  String? cover;
  String? area;
  String? watching;
  AudienceMetricType? audienceMetricType;
  String? popularity;
  String? onlineViewers;
  String? totalViewers;
  String? followers;
  String? platform;
  String? introduction;
  String? notice;
  bool? status;
  dynamic data;
  dynamic danmakuData;
  bool? isRecord;
  LiveStatus? liveStatus;
  Map<String, String> httpHeaders;

  static LiveStatus? _legacyStatusToLiveStatus({required bool? status, required bool? isRecord}) {
    if (isRecord == true) return LiveStatus.replay;
    if (status == true) return LiveStatus.live;
    if (status == false) return LiveStatus.offline;
    return null;
  }

  LiveStatus get effectiveLiveStatus {
    if (isRecord == true || liveStatus == LiveStatus.replay) return LiveStatus.replay;
    final canonical = liveStatus;
    if (canonical != null) return canonical;
    return _legacyStatusToLiveStatus(status: status, isRecord: isRecord) ?? LiveStatus.unknown;
  }

  bool get isLiveNow => effectiveLiveStatus == LiveStatus.live;

  bool get isExplicitlyOfflineNow =>
      effectiveLiveStatus == LiveStatus.offline || effectiveLiveStatus == LiveStatus.banned;

  AudienceMetricType get effectiveAudienceMetricType {
    if (audienceMetricType != null && audienceMetricType != AudienceMetricType.unknown) return audienceMetricType!;
    return AudienceMetricType.unknown;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'roomId': roomId,
    'userId': userId,
    'title': title,
    'nick': nick,
    'avatar': avatar,
    'cover': cover,
    'area': area,
    'watching': watching,
    'audienceMetricType': effectiveAudienceMetricType.name,
    'popularity': popularity,
    'onlineViewers': onlineViewers,
    'totalViewers': totalViewers,
    'followers': followers,
    'platform': platform,
    'tagIds': <String>[],
    'liveStatus': effectiveLiveStatus.index,
    'isRecord': isRecord,
    'status': isLiveNow,
    'notice': notice,
    'introduction': introduction,
    'isCatchUp': false,
    'httpHeaders': HttpHeaderPolicy.normalize(httpHeaders),
  };
}

// 3.x's look_live_link.dart ------------------------------------------------------

abstract final class LookLiveLink {
  static final RegExp _roomId = RegExp(r'^[1-9][0-9]{1,17}$');

  static String watchUrl(String raw) => 'https://look.163.com/live?id=${requireRoomId(raw)}';

  static String requireRoomId(String raw) {
    final value = parseRoomId(raw);
    if (value == null) throw const FormatException('Invalid LOOK Live room identity');
    return value;
  }

  static String? parseRoomId(String raw) {
    final value = raw.trim();
    if (_roomId.hasMatch(value)) return value;
    if (value.length > 8192 || RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.toLowerCase() != 'look.163.com' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 80 && uri.port != 443) ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    try {
      final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList(growable: false);
      if (segments.length != 1 || segments.single.toLowerCase() != 'live') return null;
      final ids = uri.queryParametersAll['id'];
      if (ids == null || ids.length != 1 || !_roomId.hasMatch(ids.single)) return null;
      return ids.single;
    } on FormatException {
      return null;
    }
  }
}

// 3.x's look_live_api.dart -------------------------------------------------------

enum LookLiveFailure { transport, access, missing, rateLimited, service, schema, identity, cancelled, mediaUnavailable }

final class LookLiveException implements Exception {
  const LookLiveException(this.kind);

  final LookLiveFailure kind;

  @override
  String toString() => 'LOOK Live ${kind.name}';
}

enum LookLiveKind { video, audio }

enum LookLiveState { live, offline, restricted, unknown }

final class LookLiveVariant {
  const LookLiveVariant({required this.id, required this.protocol, required this.uri});

  final String id;
  final String protocol;
  final Uri uri;
}

final class LookLiveRoom {
  LookLiveRoom({
    required this.roomId,
    required this.userId,
    required this.sessionId,
    required this.title,
    required this.nick,
    required this.avatar,
    required this.cover,
    required this.kind,
    required this.streamType,
    required this.state,
    required this.popularity,
    required this.currentViewers,
    required Iterable<LookLiveVariant> variants,
  }) : variants = List.unmodifiable(variants);

  final String roomId;
  final String userId;
  final String sessionId;
  final String title;
  final String nick;
  final String avatar;
  final String cover;
  final LookLiveKind kind;
  final int? streamType;
  final LookLiveState state;
  final int? popularity;
  final int? currentViewers;
  final List<LookLiveVariant> variants;

  bool get isAppOnly => streamType == 50 && variants.isEmpty;

  LookLiveRoom enrich(LookLiveRoom known) {
    final sameSession = sessionId.isNotEmpty && sessionId == known.sessionId;
    final effectiveStreamType = streamType ?? known.streamType;
    final keepKnownVariants =
        variants.isEmpty &&
        sameSession &&
        state == LookLiveState.live &&
        known.state == LookLiveState.live &&
        effectiveStreamType != 50;
    return LookLiveRoom(
      roomId: roomId,
      userId: userId.isEmpty ? known.userId : userId,
      sessionId: sessionId,
      title: title.isEmpty ? known.title : title,
      nick: nick.isEmpty ? known.nick : nick,
      avatar: avatar.isEmpty ? known.avatar : avatar,
      cover: cover.isEmpty ? known.cover : cover,
      kind: kind,
      streamType: effectiveStreamType,
      state: state,
      popularity: popularity ?? (sameSession ? known.popularity : null),
      currentViewers: currentViewers ?? (sameSession ? known.currentViewers : null),
      variants: keepKnownVariants ? known.variants : variants,
    );
  }
}

final class LookLivePage {
  LookLivePage({required Iterable<LookLiveRoom> rooms, required this.hasMore}) : rooms = List.unmodifiable(rooms);

  final List<LookLiveRoom> rooms;
  final bool hasMore;
}

typedef LookLiveRequest = Future<({int status, String body})> Function(
  Uri uri,
  Map<String, String> form,
  CancelToken? cancel,
);

/// Anonymous LOOK website contracts. The AES/RSA envelope is the public
/// browser request format shared by the current official web bundle.
class LookLiveApi {
  LookLiveApi({required LookLiveRequest request, this.deadline = const Duration(seconds: 20)})
    : _request = request;

  static const origin = 'https://look.163.com';
  static const apiOrigin = 'https://api.look.163.com';
  static const responseLimit = 2 * 1024 * 1024;
  static const serverPageSize = 20;
  static const _nonce = '0CoJUm6Qyw8W8jud';
  static const _secretKey = '0123456789abcdef';
  static const _iv = '0102030405060708';
  static const _publicKey = '010001';
  static const _modulus =
      '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec'
      '4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813'
      'cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';
  static const requestHeaders = <String, String>{
    'Accept': 'application/json, text/plain, */*',
    'Origin': origin,
    'Referer': '$origin/',
    'User-Agent': 'Mozilla/5.0',
  };

  final LookLiveRequest _request;
  final Duration deadline;

  static Map<String, String> encryptPayload(Map<String, Object?> payload) {
    final first = _aes(jsonEncode(payload), _nonce);
    final params = _aes(first, _secretKey);
    final reversed = Uint8List.fromList(utf8.encode(_secretKey).reversed.toList(growable: false));
    final text = reversed.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final encrypted = BigInt.parse(
      text,
      radix: 16,
    ).modPow(BigInt.parse(_publicKey, radix: 16), BigInt.parse(_modulus, radix: 16));
    return {'params': params, 'encSecKey': encrypted.toRadixString(16).padLeft(256, '0')};
  }

  static String _aes(String value, String key) {
    final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..init(
        true,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV(KeyParameter(Uint8List.fromList(utf8.encode(key))), Uint8List.fromList(utf8.encode(_iv))),
          null,
        ),
      );
    return base64Encode(cipher.process(Uint8List.fromList(utf8.encode(value))));
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, Object?> payload, {CancelToken? cancel}) async {
    if (cancel?.isCancelled == true) throw const LookLiveException(LookLiveFailure.cancelled);
    late final ({int status, String body}) response;
    try {
      response = await _request(Uri.parse('$apiOrigin$path'), encryptPayload(payload), cancel).timeout(deadline);
    } on TimeoutException {
      throw const LookLiveException(LookLiveFailure.transport);
    } catch (error) {
      if (cancel?.isCancelled == true) throw const LookLiveException(LookLiveFailure.cancelled);
      if (error is LookLiveException) rethrow;
      throw const LookLiveException(LookLiveFailure.transport);
    }
    if (cancel?.isCancelled == true) throw const LookLiveException(LookLiveFailure.cancelled);
    final failure = switch (response.status) {
      200 => null,
      401 || 403 => LookLiveFailure.access,
      404 => LookLiveFailure.missing,
      429 => LookLiveFailure.rateLimited,
      >= 500 => LookLiveFailure.service,
      _ => LookLiveFailure.transport,
    };
    if (failure != null) throw LookLiveException(failure);
    if (response.body.length > responseLimit || utf8.encode(response.body).length > responseLimit) {
      throw const LookLiveException(LookLiveFailure.schema);
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const LookLiveException(LookLiveFailure.schema);
    }
    final root = _object(decoded);
    final code = _integer(root['code']);
    if (code == 404) throw const LookLiveException(LookLiveFailure.missing);
    if (code == 424 || code == 520 || code == 522 || code == 555) {
      throw const LookLiveException(LookLiveFailure.access);
    }
    if (code != 200) throw const LookLiveException(LookLiveFailure.service);
    return _object(root['data']);
  }

  Future<LookLivePage> directory({required LookLiveKind kind, int page = 1, CancelToken? cancel}) async {
    if (page < 1 || page > 10000) throw const LookLiveException(LookLiveFailure.schema);
    final path = kind == LookLiveKind.audio
        ? '/weapi/livestream/listen/homepage/recommend/list'
        : '/weapi/livestream/homepage/recommend';
    final data = await _post(path, {'offset': (page - 1) * serverPageSize, 'limit': serverPageSize}, cancel: cancel);
    final rows = data['itemList'];
    final hasMore = data['hasMore'];
    if (rows is! List || rows.length > 100 || hasMore is! bool) {
      throw const LookLiveException(LookLiveFailure.schema);
    }
    final rooms = <String, LookLiveRoom>{};
    for (final raw in rows) {
      final item = _object(raw);
      if ('${item['type']}' != '1' || item['liveData'] == null) continue;
      final live = _object(item['liveData']);
      final liveType = _integer(live['liveType']);
      if (liveType != 1 && liveType != 2) throw const LookLiveException(LookLiveFailure.schema);
      // The official voice feed occasionally injects a video/multi-room card.
      // Preserve the category identity rather than failing or mislabelling it.
      if ((liveType == 2 ? LookLiveKind.audio : LookLiveKind.video) != kind) continue;
      final room = _directoryRoom(live, expectedKind: kind);
      rooms[room.roomId] = room;
    }
    return LookLivePage(rooms: rooms.values, hasMore: hasMore);
  }

  Future<LookLiveRoom> room(String input, {bool includeMedia = true, CancelToken? cancel}) async {
    final id = LookLiveLink.requireRoomId(input);
    final data = await _post('/weapi/livestream/room/get/v3', {'liveRoomNo': id}, cancel: cancel);
    final anchor = _object(data['anchor']);
    final returnedId = _identifier(anchor['liveRoomNo']);
    if (returnedId != id) throw const LookLiveException(LookLiveFailure.identity);
    final info = _object(data['roomInfo']);
    final liveType = _integer(info['liveType']);
    final state = switch (_integer(data['liveStatus'])) {
      1 => LookLiveState.live,
      0 || -1 => LookLiveState.offline,
      -10 => LookLiveState.restricted,
      _ => LookLiveState.unknown,
    };
    if (liveType != 1 && liveType != 2) throw const LookLiveException(LookLiveFailure.schema);
    return LookLiveRoom(
      roomId: id,
      userId: _identifier(anchor['userId']),
      sessionId: _identifier(info['id']),
      title: _text(info['title']),
      nick: _text(anchor['nickName']),
      avatar: _picture(anchor['avatarUrl']),
      cover: _picture(info['liveCoverUrl']),
      kind: liveType == 2 ? LookLiveKind.audio : LookLiveKind.video,
      streamType: _integer(info['liveStreamType']),
      state: state,
      popularity: null,
      currentViewers: null,
      variants: includeMedia && state == LookLiveState.live ? _variants(info['liveUrl']) : const [],
    );
  }

  static LookLiveRoom _directoryRoom(Map<String, dynamic> live, {required LookLiveKind expectedKind}) {
    final user = _object(live['userInfo']);
    final liveType = _integer(live['liveType']);
    if (liveType != 1 && liveType != 2) throw const LookLiveException(LookLiveFailure.schema);
    final actualKind = liveType == 2 ? LookLiveKind.audio : LookLiveKind.video;
    if (actualKind != expectedKind) throw const LookLiveException(LookLiveFailure.schema);
    final popularity = _nonNegative(live['popularity']);
    final currentViewers = _nonNegative(live['onlineNumber']);
    return LookLiveRoom(
      roomId: _identifier(user['liveRoomNo']),
      userId: _identifier(user['userId']),
      sessionId: _identifier(live['liveId']),
      title: _text(live['liveTitle']),
      nick: _text(user['nickname']),
      avatar: _picture(user['avatarUrl']),
      cover: _picture(live['liveCoverUrl']),
      kind: actualKind,
      streamType: _integer(live['liveStreamType']),
      state: LookLiveState.live,
      popularity: popularity,
      currentViewers: currentViewers,
      variants: _variants(live['liveUrl']),
    );
  }

  static List<LookLiveVariant> _variants(Object? raw) {
    if (raw == null) return const [];
    final data = _object(raw);
    final result = <LookLiveVariant>[];
    for (final entry in const [('hls', 'hlsPullUrl'), ('flv', 'httpPullUrl')]) {
      final value = _text(data[entry.$2]);
      if (value.isEmpty) continue;
      final uri = mediaUri(value, protocol: entry.$1);
      result.add(LookLiveVariant(id: '${entry.$1}:source', protocol: entry.$1, uri: uri));
    }
    return List.unmodifiable(result);
  }

  static Uri mediaUri(String raw, {required String protocol}) {
    final source = Uri.tryParse(raw.trim());
    if (source == null ||
        !const {'http', 'https'}.contains(source.scheme.toLowerCase()) ||
        source.userInfo.isNotEmpty ||
        source.hasPort ||
        source.fragment.isNotEmpty ||
        !RegExp(r'^[a-z0-9-]+\.live\.126\.net$').hasMatch(source.host.toLowerCase()) ||
        source.query.length > 2048) {
      throw const LookLiveException(LookLiveFailure.schema);
    }
    final validPath = switch (protocol) {
      'hls' => RegExp(r'^/live/[a-f0-9]{32}/playlist\.m3u8$').hasMatch(source.path),
      'flv' => RegExp(r'^/live/[a-f0-9]{32}\.flv$').hasMatch(source.path),
      _ => false,
    };
    if (!validPath) throw const LookLiveException(LookLiveFailure.schema);
    return source.replace(scheme: 'https');
  }

  static Map<String, String> mediaHeaders(String roomId) => {
    'Origin': origin,
    'Referer': LookLiveLink.watchUrl(roomId),
    'User-Agent': 'Mozilla/5.0',
  };

  static Map<String, dynamic> _object(Object? raw) {
    if (raw is! Map || raw.keys.any((key) => key is! String)) {
      throw const LookLiveException(LookLiveFailure.schema);
    }
    return Map<String, dynamic>.from(raw);
  }

  static String _text(Object? raw) => raw is String ? raw.trim() : '';

  static int? _integer(Object? raw) => raw is int ? raw : (raw is String ? int.tryParse(raw) : null);

  static int? _nonNegative(Object? raw) {
    if (raw == null) return null;
    final value = _integer(raw);
    if (value == null || value < 0) throw const LookLiveException(LookLiveFailure.schema);
    return value;
  }

  static String _identifier(Object? raw) {
    final value = raw is int ? '$raw' : (raw is String ? raw.trim() : '');
    if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(value)) {
      throw const LookLiveException(LookLiveFailure.schema);
    }
    return value;
  }

  static String _picture(Object? raw) {
    final value = _text(raw);
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.fragment.isNotEmpty) {
      return '';
    }
    return uri.replace(scheme: 'https').toString();
  }
}

// 3.x's look_live_site.dart ------------------------------------------------------

final class LookLiveSite {
  LookLiveSite({required LookLiveApi api}) : _api = api;

  final LookLiveApi _api;
  final Map<String, LookLiveRoom> _known = {};

  String get id => 'looklive';

  String get name => i18n('site_looklive');

  String get directoryNoticeKey => 'looklive_directory_scope';

  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    if (page != 1 || pageSize < 1) return const [];
    return [
      LiveCategory(
        id: id,
        name: name,
        children: [
          LiveArea(
            platform: id,
            areaType: 'official',
            areaId: 'video',
            areaName: i18n('looklive_category_video'),
            typeName: name,
          ),
          LiveArea(
            platform: id,
            areaType: 'official',
            areaId: 'audio',
            areaName: i18n('looklive_category_audio'),
            typeName: name,
          ),
        ].take(pageSize).toList(growable: false),
      ),
    ];
  }

  LookLiveKind? _category(LiveArea? category) {
    if (category == null) return null;
    if (category.platform != id || category.areaType != 'official') {
      throw const LookLiveException(LookLiveFailure.identity);
    }
    return switch (category.areaId) {
      'video' => LookLiveKind.video,
      'audio' => LookLiveKind.audio,
      _ => throw const LookLiveException(LookLiveFailure.identity),
    };
  }

  void _remember(Iterable<LookLiveRoom> rooms) {
    for (var room in rooms) {
      final known = _known[room.roomId];
      if (known != null) room = room.enrich(known);
      _known[room.roomId] = room;
    }
  }

  static LiveRoom _room(LookLiveRoom room, {required bool includeMedia}) {
    final online = room.currentViewers?.toString();
    final popularity = room.popularity?.toString();
    final notices = <String>[
      if (room.state == LookLiveState.restricted) i18n('looklive_restricted_notice'),
      if (room.isAppOnly) i18n('looklive_app_only_notice'),
      i18n('looklive_chat_notice'),
    ];
    return LiveRoom(
      platform: 'looklive',
      roomId: room.roomId,
      userId: room.userId,
      title: room.title,
      nick: room.nick,
      avatar: room.avatar.isEmpty ? room.cover : room.avatar,
      cover: room.cover,
      area: i18n(room.kind == LookLiveKind.audio ? 'looklive_category_audio' : 'looklive_category_video'),
      link: LookLiveLink.watchUrl(room.roomId),
      liveStatus: switch (room.state) {
        LookLiveState.live => LiveStatus.live,
        LookLiveState.offline => LiveStatus.offline,
        LookLiveState.restricted || LookLiveState.unknown => LiveStatus.unknown,
      },
      watching: online ?? popularity ?? '',
      onlineViewers: online,
      popularity: popularity,
      audienceMetricType: online != null
          ? AudienceMetricType.onlineViewers
          : (popularity != null ? AudienceMetricType.popularity : AudienceMetricType.unknown),
      notice: notices.join('\n'),
      httpHeaders: LookLiveApi.mediaHeaders(room.roomId),
      data: includeMedia ? room : null,
    );
  }

  Future<LookLivePage> _directory(int page, LookLiveKind? kind, CancelToken? cancel) async {
    if (page < 1) return LookLivePage(rooms: const [], hasMore: false);
    if (kind != null) return _api.directory(kind: kind, page: page, cancel: cancel);
    final results = await Future.wait([
      _api.directory(kind: LookLiveKind.video, page: page, cancel: cancel),
      _api.directory(kind: LookLiveKind.audio, page: page, cancel: cancel),
    ]);
    final rooms = <String, LookLiveRoom>{};
    for (final result in results) {
      for (final room in result.rooms) {
        rooms.putIfAbsent(room.roomId, () => room);
      }
    }
    return LookLivePage(rooms: rooms.values, hasMore: results.any((result) => result.hasMore));
  }

  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    final result = await _directory(page, _category(category), cancel);
    _remember(result.rooms);
    return LiveDirectoryPage(
      rooms: result.rooms.map((room) => _room(_known[room.roomId]!, includeMedia: false)),
      page: page,
      hasMore: result.hasMore,
    );
  }

  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return const [];
    return (await getDirectoryPage(page: page)).rooms.take(pageSize).toList(growable: false);
  }

  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return const [];
    return (await getDirectoryPage(page: page, category: category)).rooms.take(pageSize).toList(growable: false);
  }

  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    final raw = keyword.trim();
    if (raw.isEmpty || page != 1 || pageSize < 1 || pageSize > 100) return const [];
    final roomId = LookLiveLink.parseRoomId(raw);
    if (roomId != null) {
      try {
        return [await _detail(roomId, id, includeMedia: false, cancel: cancel)];
      } on LookLiveException catch (error) {
        if (error.kind == LookLiveFailure.missing) return const [];
        rethrow;
      }
    }
    final query = raw.toLowerCase();
    final result = await _directory(1, null, cancel);
    _remember(result.rooms);
    return result.rooms
        .where(
          (room) =>
              room.roomId.contains(query) ||
              room.nick.toLowerCase().contains(query) ||
              room.title.toLowerCase().contains(query),
        )
        .take(pageSize)
        .map((room) => _room(_known[room.roomId]!, includeMedia: false))
        .toList(growable: false);
  }

  String _roomId(String roomId, String platform) {
    if (platform.trim().toLowerCase() != id) throw const LookLiveException(LookLiveFailure.identity);
    final value = LookLiveLink.parseRoomId(roomId);
    if (value == null) throw const LookLiveException(LookLiveFailure.identity);
    return value;
  }

  Future<LiveRoom> _detail(String roomId, String platform, {required bool includeMedia, CancelToken? cancel}) async {
    final normalized = _roomId(roomId, platform);
    var room = await _api.room(normalized, includeMedia: includeMedia, cancel: cancel);
    final known = _known[normalized];
    if (known != null) room = room.enrich(known);
    _known[normalized] = room;
    return _room(room, includeMedia: includeMedia);
  }

  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) =>
      _detail(roomId, platform, includeMedia: true);

  Future<LiveRoom> getRoomDetailForRecording({required String roomId, required String platform}) =>
      _detail(roomId, platform, includeMedia: true);

  Future<LiveRoom> getRoomDetailForRefresh({required String roomId, required String platform}) =>
      _detail(roomId, platform, includeMedia: false);

  Future<bool> getLiveStatus({required String platform, required String roomId}) async {
    final detail = await getRoomDetailForRefresh(roomId: roomId, platform: platform);
    if (detail.effectiveLiveStatus == LiveStatus.unknown) throw const LookLiveException(LookLiveFailure.access);
    return detail.isLiveNow;
  }

  LookLiveRoom _snapshot(LiveRoom detail) {
    final roomId = _roomId(detail.roomId ?? '', detail.platform ?? '');
    final room = detail.data;
    if (room is! LookLiveRoom || room.roomId != roomId) {
      throw const LookLiveException(LookLiveFailure.identity);
    }
    if (room.state != LookLiveState.live || room.variants.isEmpty) {
      throw const LookLiveException(LookLiveFailure.mediaUnavailable);
    }
    return room;
  }

  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    if (detail.isExplicitlyOfflineNow) return const [];
    final room = _snapshot(detail);
    return room.variants
        .map(
          (variant) => LivePlayQuality(
            id: variant.id,
            quality: i18n(variant.protocol == 'hls' ? 'looklive_quality_hls' : 'looklive_quality_flv'),
            sort: variant.protocol == 'hls' ? 2 : 1,
          ),
        )
        .toList(growable: false);
  }

  Future<LivePlayUrlResolution> _resolve(LiveRoom detail, LivePlayQuality quality, {required bool refresh}) async {
    var room = _snapshot(detail);
    if (refresh) room = _snapshot(await _detail(room.roomId, id, includeMedia: true));
    final selectionId = quality.selectionId.toString();
    for (final variant in room.variants) {
      if (variant.id != selectionId) continue;
      return LivePlayUrlResolution(urls: [variant.uri.toString()], appliedQualityData: variant.id);
    }
    throw const LookLiveException(LookLiveFailure.mediaUnavailable);
  }

  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) =>
      _resolve(detail, quality, refresh: false);

  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => _resolve(detail, quality, refresh: true);

  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await _resolve(detail, quality, refresh: false)).urls;
}
