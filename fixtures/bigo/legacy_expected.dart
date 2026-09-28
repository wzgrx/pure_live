// Writes expected.json for the Bigo Live samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.24-bigo.md, "样本与 v3 的冻结输出").
//
// The archive has no Bigo expected.json (its legacy harness only covered five
// platforms, spec/sites/bigo.md §11, and 3.x no longer builds). The code
// below is 3.x's BigoApi, BigoSite, BigoLink, BigoTokenCodec,
// BigoHlsProtection and BigoInputRecipe, copied from
// legacy/lib/core/site/bigo/ (archive/v4). 3.x already injected its transport
// (`BigoRequest`), its token data builder and its JSONP callback names, so
// only these are replaced:
// - the transport answers from the samples by method, host, path and query
//   (the random `callback` and `data` of the token requests and the `token`
//   of the studio request are not compared: the samples scrubbed them), with
//   the empty body 3.x read for any status other than 200; a request without
//   a sample throws a StateError, which 3.x's `_scope` reports as a
//   `transport` failure, and is listed under `unmatched`;
// - the callback names are the ones the samples were recorded with
//   (`jsonp_purelive_t`, then `jsonp_purelive_s`), which pass 3.x's check;
// - the token data is 3.x's `BigoTokenCodec.buildData` with a fixed salt and
//   nonce, so the output does not change between runs.
// `withRequestCancellation` (legacy/lib/core/common/request_scope.dart) is
// copied with Dio's CancelToken reduced to a stub; `kIsWeb` is false; the
// streamed body reader (`_defaultRequest`, `readBody`) is left out (it only
// ran on the network path). `i18n` returns 3.x's zh.json text of the keys
// used. 3.x's LiveRoom, LiveArea, LiveCategory, LivePlayQuality,
// LiveDirectoryPage and LivePlayUrlResolution are reduced to the parts these
// classes use (toJson with 3.x's HttpHeaderPolicy.normalize). The output
// format is the legacy harness's (`roomProjection`, `errorProjection`,
// `{generator, value}`); every entry point also records its requests.
//
// The live studio sample (S03-studio-live) has an `http://` avatar, which
// 3.x's parser rejects (`_httpsUri`), so every 3.x room call on it fails. To
// compare the other fields as well, S03-studio-live also records 3.x's
// output for the same answer with only the avatar's scheme made `https`
// (`avatarHttps`).
//
// BigoTokenCodec uses PointyCastle, which the workspace does not depend on,
// so this runs with a throwaway package configuration (the versions 3.x
// resolved). From the repository root:
//
//   d=$(mktemp -d)
//   printf 'name: g\nenvironment:\n  sdk: ^3.9.0\ndependencies:\n  crypto: 3.0.7\n  pointycastle: 4.0.0\n' > "$d/pubspec.yaml"
//   (cd "$d" && dart pub get --offline)
//   dart --packages="$d/.dart_tool/package_config.json" fixtures/bigo/legacy_expected.dart
//
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';
import 'package:pointycastle/paddings/pkcs7.dart';

const _root = 'fixtures/bigo';

/// The room of the studio samples, as the directory lists it.
const _room = '414439909';

/// The salt and nonce of the fixed token data (3.x's own test used these).
final Uint8List _salt = Uint8List.fromList(const [0, 1, 2, 3, 4, 5, 6, 7]);
const _nonce = '0123456789abcdef0123456789abcdef';

/// Keywords run through 3.x's search against S01 and the studio samples:
/// titles and nicknames (any case), a word in no card, the listed id, its
/// room links, a letters-only word in no card (3.x looks it up as an id), a
/// URL of another site and a blank.
const _keywords = [
  'Pk',
  'pk CHALLENGE',
  'qashia',
  'MR',
  '赚钱',
  'nickname words',
  _room,
  'https://www.bigo.tv/$_room',
  'https://www.bigo.tv/en/$_room',
  'zzqxnomatch',
  'http://example.com/x',
  '  ',
];

/// Links for 3.x's `BigoLink.parse` (no requests).
const _links = [
  'https://www.bigo.tv/414439909',
  'https://www.bigo.tv/qashia305',
  'https://bigo.tv/qashia305',
  'http://www.bigo.tv/qashia305',
  'https://www.bigo.tv/en/qashia305',
  'https://www.bigo.tv/cn/qashia305?from=share',
  'https://www.bigo.tv/zh-CN/qashia305',
  'https://www.bigo.tv/en/qashia305/extra',
  'https://www.bigo.tv/',
  'https://www.bigo.tv/search',
  'https://www.bigo.tv/Live',
  'https://www.bigo.tv/show',
  'https://www.bigo.tv/user',
  'https://www.bigo.tv/qashia305#x',
  'https://www.bigo.tv:444/qashia305',
  'https://www.bigo.tv:443/qashia305',
  'https://user@www.bigo.tv/qashia305',
  'https://m.bigo.tv/qashia305',
  'https://www.bigo.tv.evil.test/qashia305',
  'ftp://www.bigo.tv/qashia305',
  'https://www.bigo.tv/a%2Fb',
  'https://www.bigo.tv/.hidden',
  'https://www.bigo.tv/q.a-b_c',
];

void main() async {
  await _directory();
  await _studio();
  await _notoken();
  _token();
  _playlist();
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];
Map<String, String> _bodies = {};
final List<String> _requests = [];
final List<String> _unmatched = [];

/// Query and form fields the samples scrubbed or that change per run.
const _uncompared = {'callback', 'data', 'token'};

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync()) as Map<String, dynamic>;

/// Loads [samples]; [bodies] replaces a sample's body, by sample name.
void _replay(List<String> samples, {Map<String, String> bodies = const {}}) {
  _samples = [for (final sample in samples) _meta(sample)];
  _bodies = bodies;
  _requests.clear();
  _unmatched.clear();
}

Map<String, String> _compared(Map<String, String> fields) => {
  for (final entry in fields.entries)
    if (!_uncompared.contains(entry.key)) entry.key: entry.value,
};

bool _sameFields(Map<String, String> a, Map<String, String> b) {
  final left = _compared(a);
  final right = _compared(b);
  return left.length == right.length && left.entries.every((entry) => right[entry.key] == entry.value);
}

/// 3.x's `BigoRequest` over the samples: 3.x read no body for a status other
/// than 200.
Future<({int status, String body})> _fixtureRequest(
  String method,
  Uri uri,
  Map<String, String>? form,
  CancelToken cancel,
) async {
  final query = _compared(uri.queryParameters);
  _requests.add(
    '$method ${uri.scheme}://${uri.host}${uri.path}'
    '${query.isEmpty ? '' : '?${[for (final MapEntry(:key, :value) in query.entries) '$key=$value'].join('&')}'}'
    '${form == null ? '' : ' form ${jsonEncode(form)}'}',
  );
  for (final meta in _samples) {
    final request = meta['request'] as Map<String, dynamic>;
    final recorded = Uri.parse(request['url'] as String);
    final body = request['body'];
    final recordedForm = body is String && body.isNotEmpty ? Uri.splitQueryString(body) : null;
    if (request['method'] == method &&
        recorded.host == uri.host &&
        recorded.path == uri.path &&
        _sameFields(recorded.queryParameters, uri.queryParameters) &&
        (recordedForm == null) == (form == null) &&
        (form == null || _sameFields(recordedForm!, form))) {
      final status = (meta['response'] as Map)['status'] as int;
      if (status != 200) return (status: status, body: '');
      final sample = meta['sample'] as String;
      return (status: 200, body: _bodies[sample] ?? File('$_root/$sample/${meta['body']}').readAsStringSync());
    }
  }
  _unmatched.add('$method $uri');
  throw StateError('No recorded sample for $method $uri');
}

/// The callback names of the recorded token requests, in order.
BigoJsonpCallbackFactory _callbacks() {
  var next = 0;
  return () => (next++).isEven ? 'jsonp_purelive_t' : 'jsonp_purelive_s';
}

String _tokenData(String timestamp) => BigoTokenCodec.buildData(timestamp, salt: _salt, randomHex: _nonce);

BigoApi _api() => BigoApi(request: _fixtureRequest, tokenDataBuilder: _tokenData, callbackFactory: _callbacks());

BigoSite _site() => BigoSite(api: _api());

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
  final json = room.toJson()
    ..['link'] = room.link
    ..['danmakuData'] = room.danmakuData?.toString();
  json.removeWhere(
    (key, value) => value == null || (value is Map && value.isEmpty) || (value is List && value.isEmpty),
  );
  return json;
}

List<Map<String, dynamic>> _rooms(List<LiveRoom> rooms) => [for (final room in rooms) _roomProjection(room)];

Object? _page(LiveDirectoryPage page) => {'rooms': _rooms(page.rooms), 'page': page.page, 'hasMore': page.hasMore};

Object? _qualities(List<LivePlayQuality> qualities) => [
  for (final quality in qualities)
    {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort, 'data': quality.data},
];

Object? _resolution(LivePlayUrlResolution resolution) => {
  'urls': resolution.urls,
  'appliedQualityData': resolution.appliedQualityData,
  'inputRecipe': switch (resolution.inputRecipe) {
    final BigoInputRecipe recipe => {'siteId': recipe.siteId, 'identity': recipe.identity},
    _ => null,
  },
};

Object? _studioProjection(BigoStudioRoom room) => {
  'requestedSiteId': room.status.requestedSiteId,
  'canonicalSiteId': room.status.canonicalSiteId,
  'ownerId': room.status.ownerId,
  'access': room.status.access.name,
  'reportedAlive': room.status.reportedAlive,
  'roomStatus': room.status.roomStatus,
  'roomType': room.status.roomType,
  'roomId': room.roomId,
  'nickname': room.nickname,
  'title': room.title,
  'category': room.category,
  'avatar': room.avatar,
  'hls': room.hls?.toString(),
};

List<int> _hex(String hex) => [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];

String _toHex(List<int> bytes) => [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();

final _publicArea = LiveArea(
  platform: 'bigo',
  areaType: 'public',
  areaId: '72',
  areaName: '公开推荐',
  typeName: 'Bigo Live',
);

// Samples ---------------------------------------------------------------------

/// `vedioList/72`: the category, the native directory pages, 3.x's slices,
/// the search over the snapshot (with the studio samples for the exact
/// lookups), the 30 s cache and the link rules.
Future<void> _directory() async {
  const samples = ['S01-list', 'S02-time-live', 'S02-status-live', 'S03-studio-live'];
  _replay(samples);
  final value = <String, Object?>{
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
    'getCategores(page: 2)': await _traced(() => _site().getCategores(2, 30), (categories) => categories.length),
    'getCategores(pageSize: 0)': await _traced(() => _site().getCategores(1, 0), (categories) => categories.length),
  };
  value['getDirectoryPage'] = {
    for (final page in [1, 2, 3])
      'recommend:$page': await _traced(() => _site().getDirectoryPage(page: page, cancel: CancelToken()), _page),
    'public:1': await _traced(
      () => _site().getDirectoryPage(page: 1, category: _publicArea, cancel: CancelToken()),
      _page,
    ),
    'otherArea:1': await _traced(
      () => _site().getDirectoryPage(
        category: LiveArea(platform: 'bigo', areaType: 'public', areaId: '73', areaName: 'x'),
        cancel: CancelToken(),
      ),
      _page,
    ),
    'recommend:0': await _traced(() => _site().getDirectoryPage(page: 0, cancel: CancelToken()), _page),
  };
  value['getRecommendRooms'] = {
    for (final (page, size) in [(1, 30), (1, 20), (2, 20), (1, 8), (3, 8), (4, 8), (1, 100), (1, 101), (0, 30), (1, 0)])
      'page $page size $size': await _traced(() => _site().getRecommendRooms(page: page, pageSize: size), _rooms),
  };
  value['getCategoryRooms'] = {
    'public page 1': await _traced(() => _site().getCategoryRooms(_publicArea, page: 1), _rooms),
    'public page 2 size 8': await _traced(() => _site().getCategoryRooms(_publicArea, page: 2, pageSize: 8), _rooms),
    'otherPlatform': await _traced(
      () => _site().getCategoryRooms(LiveArea(platform: 'bilibili', areaType: 'public', areaId: '72')),
      _rooms,
    ),
  };
  final search = <String, Object?>{};
  for (final keyword in _keywords) {
    search['$keyword page 1'] = await _traced(
      () => _site().searchRoomsCancellable(keyword, page: 1, pageSize: 20, cancel: CancelToken()),
      _rooms,
    );
  }
  search['Pk page 2'] = await _traced(
    () => _site().searchRoomsCancellable('Pk', page: 2, pageSize: 20, cancel: CancelToken()),
    _rooms,
  );
  search['long'] = await _traced(
    () => _site().searchRoomsCancellable('a' * 101, page: 1, pageSize: 20, cancel: CancelToken()),
    _rooms,
  );
  search['Pk without a token'] = await _traced(() => _site().searchRooms('Pk', page: 1, pageSize: 20), _rooms);
  value['searchRooms (pageSize 20)'] = search;
  // The same exact lookups when the studio answer has an https avatar.
  _replay(samples, bodies: {'S03-studio-live': _avatarHttps()});
  value['searchRooms avatarHttps'] = {
    for (final keyword in [_room, 'https://www.bigo.tv/$_room'])
      keyword: await _traced(
        () => _site().searchRoomsCancellable(keyword, page: 1, pageSize: 20, cancel: CancelToken()),
        _rooms,
      ),
  };
  _replay(samples);
  // The 30 s cache: calls on one site without a cancel token share one
  // request; a call with a token asks again.
  final cached = _site();
  value['cache'] = await _traced(() async {
    await cached.getRecommendRooms();
    await cached.getCategoryRooms(_publicArea);
    await cached.searchRooms('Pk');
    await cached.getDirectoryPage();
    await cached.getDirectoryPage(cancel: CancelToken());
    return true;
  }, (value) => value);
  value['BigoLink.parse'] = {for (final link in _links) link: BigoLink.parse(link)};
  value['BigoLink.parseOrSiteId'] = {
    for (final text in ['qashia305', ' 414439909 ', 'a b', '../x', 'https://www.bigo.tv/qashia305', '_x', '.x'])
      text: BigoLink.parseOrSiteId(text),
  };
  value['BigoLink.url'] = {
    for (final id in ['qashia305', 'a/b']) id: _sync(() => BigoLink.url(id)),
  };
  _write(
    'S01-list',
    'BigoSite.getCategores + getDirectoryPage + getRecommendRooms + getCategoryRooms + searchRoomsCancellable '
        '(with S02-time-live, S02-status-live, S03-studio-live) + BigoLink',
    value,
  );
}

/// S03-studio-live's body with only the avatar's scheme made https.
String _avatarHttps() {
  final body = File('$_root/S03-studio-live/body.json').readAsStringSync();
  final changed = body.replaceFirst('"avatar": "http://', '"avatar": "https://');
  if (changed == body) throw StateError('S03-studio-live has no http avatar');
  return changed;
}

/// The studio flow for [reference] at every depth, the live status, the
/// qualities, the owned input and recovery, with every request.
Future<Map<String, Object?>> _roomCalls(String reference) async {
  final site = _site();
  final entry = <String, Object?>{
    'getRoomDetail': await _traced(() => site.getRoomDetail(roomId: reference, platform: 'bigo'), _roomProjection),
    'getRoomDetailForRefresh': await _traced(
      () => site.getRoomDetailForRefresh(roomId: reference, platform: 'bigo'),
      _roomProjection,
    ),
    'getRoomDetailForRecording': await _traced(
      () => site.getRoomDetailForRecording(roomId: reference, platform: 'bigo'),
      _roomProjection,
    ),
    'getLiveStatus': await _traced(() => site.getLiveStatus(roomId: reference, platform: 'bigo'), (live) => live),
    'studioRoom': await _traced(() => _api().studioRoom(siteId: reference), _studioProjection),
  };
  for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
    LiveRoom? detail;
    try {
      detail = await switch (depth) {
        'getRoomDetail' => site.getRoomDetail(roomId: reference, platform: 'bigo'),
        'getRoomDetailForRefresh' => site.getRoomDetailForRefresh(roomId: reference, platform: 'bigo'),
        _ => site.getRoomDetailForRecording(roomId: reference, platform: 'bigo'),
      };
    } on Object {
      detail = null;
    }
    if (detail == null) continue;
    final room = detail;
    final quality = LivePlayQuality(id: 'live', quality: i18n('bigo_quality_live'));
    entry['$depth → getPlayQualites'] = await _traced(() => site.getPlayQualites(detail: room), _qualities);
    entry['$depth → resolvePlayUrlsRaw'] = await _traced(
      () => site.resolvePlayUrlsRaw(detail: room, quality: quality),
      _resolution,
    );
    entry['$depth → resolvePlayUrlsForRecoveryRaw'] = await _traced(
      () => site.resolvePlayUrlsForRecoveryRaw(detail: room, quality: quality),
      _resolution,
    );
    entry['$depth → getPlayUrls'] = await _traced(() => site.getPlayUrls(detail: room, quality: quality), (u) => u);
    entry['$depth → resolvePlayUrlsRaw(auto)'] = await _traced(
      () => site.resolvePlayUrlsRaw(
        detail: room,
        quality: LivePlayQuality(id: 'auto', quality: 'auto'),
      ),
      _resolution,
    );
  }
  return entry;
}

/// The web token and `getInternalStudioInfo` of the live room: as recorded
/// (3.x rejects its http avatar) and with an https avatar.
Future<void> _studio() async {
  const samples = ['S02-time-live', 'S02-status-live', 'S03-studio-live'];
  _replay(samples);
  final value = <String, Object?>{
    'recorded': {
      _room: await _roomCalls(_room),
      'notASiteId': await _traced(() => _site().getRoomDetail(roomId: '../x', platform: 'bigo'), _roomProjection),
      'otherPlatform': await _traced(() => _site().getRoomDetail(roomId: _room, platform: 'bilibili'), _roomProjection),
    },
  };
  _replay(samples, bodies: {'S03-studio-live': _avatarHttps()});
  value['avatarHttps'] = {_room: await _roomCalls(_room)};
  _write(
    'S03-studio-live',
    'BigoSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
        'getPlayQualites + resolvePlayUrlsRaw + resolvePlayUrlsForRecoveryRaw + getPlayUrls + BigoApi.studioRoom '
        '(with S02-time-live, S02-status-live; avatarHttps: the avatar made https)',
    value,
  );
}

/// The form request 3.x's `studioStatus` sends (it is what this sample
/// recorded) and 3.x's reading of a `needLogin` answer: the studio parser,
/// and the rooms when the tokenized studio request is answered with it.
Future<void> _notoken() async {
  _replay(['S03-studio-notoken']);
  final body = File('$_root/S03-studio-notoken/body.json').readAsStringSync();
  final json = jsonDecode(body) as Map<String, dynamic>;
  final value = <String, Object?>{
    'studioStatus': await _traced(
      () => _api().studioStatus(siteId: _room, expectedOwnerId: 409742853),
      (status) => {
        'canonicalSiteId': status.canonicalSiteId,
        'ownerId': status.ownerId,
        'access': status.access.name,
        'reportedAlive': status.reportedAlive,
        'roomStatus': status.roomStatus,
        'roomType': status.roomType,
      },
    ),
    'parseStudioRoom': _sync(() => _studioProjection(BigoApi.parseStudioRoom(json, siteId: _room))),
  };
  _replay(['S02-time-live', 'S02-status-live', 'S03-studio-live'], bodies: {'S03-studio-live': body});
  value['asTokenAnswer'] = {_room: await _roomCalls(_room)};
  _write(
    'S03-studio-notoken',
    'BigoApi.studioStatus + parseStudioRoom; asTokenAnswer: the BigoSite calls with the tokenized studio request '
        'answered by this body (with S02-time-live, S02-status-live)',
    value,
  );
}

/// The two JSONP answers of the web token, and 3.x's token data.
void _token() {
  final time = File('$_root/S02-time-live/body.txt').readAsStringSync();
  final status = File('$_root/S02-status-live/body.txt').readAsStringSync();
  _write('S02-time-live', "BigoApi._jsonp (3.x's callback check)", {
    'jsonp_purelive_t': _sync(() => BigoApi._jsonp(time, 'jsonp_purelive_t')),
    'jsonp_other': _sync(() => BigoApi._jsonp(time, 'jsonp_other')),
  });
  _write('S02-status-live', "BigoApi._jsonp + BigoTokenCodec.buildData (3.x's codec, fixed salt and nonce)", {
    'jsonp_purelive_s': _sync(() => BigoApi._jsonp(status, 'jsonp_purelive_s')),
    'tokenData': {
      for (final timestamp in ['1672503768', '1723456789', '1790000000'])
        timestamp: BigoTokenCodec.buildData(timestamp, salt: _salt, randomHex: _nonce),
    },
    'tokenData(1790000000, salt 1..8)': BigoTokenCodec.buildData(
      '1790000000',
      salt: Uint8List.fromList(const [1, 2, 3, 4, 5, 6, 7, 8]),
      randomHex: _nonce,
    ),
    'tokenData errors': {
      'timestamp': _sync(() => BigoTokenCodec.buildData('12a', salt: _salt, randomHex: _nonce)),
      'salt': _sync(() => BigoTokenCodec.buildData('1', salt: Uint8List(7), randomHex: _nonce)),
      'nonce': _sync(() => BigoTokenCodec.buildData('1', salt: _salt, randomHex: 'XYZ')),
    },
  });
}

/// The media playlist's protection tag and 3.x's segment transform.
void _playlist() {
  final playlist = File('$_root/S04-playlist/body.m3u8').readAsStringSync();
  final recorded = Uint8List(376)..setAll(0, _hex('3853197ab543cc34d1eb3b1446042e58'));
  final counting = Uint8List.fromList(List.generate(188 * 3, (index) => index & 0xff));
  _write('S04-playlist', 'BigoHlsProtection.seedFromManifest + transformSegment', {
    'seedFromManifest': _sync(() => BigoHlsProtection.seedFromManifest(playlist)),
    'seedFromManifest(3.x tag)': _sync(
      () => BigoHlsProtection.seedFromManifest('#EXTM3U\n#EXT-X-BIGO-WEB-PROTECTION:SEED=807018584\n'),
    ),
    'seedFromManifest(too large)': _sync(
      () => BigoHlsProtection.seedFromManifest('#EXT-X-BIGO-WEB-PROTECTION:SEED=4294967296\n'),
    ),
    'transformSegment(recorded packet, 2020359253)': _toHex(
      BigoHlsProtection.transformSegment(recorded, 2020359253).sublist(0, 16),
    ),
    'transformSegment(counting, 807018584)': _toHex(BigoHlsProtection.transformSegment(counting, 807018584)),
    'transformSegment(375 bytes)': _sync(() => BigoHlsProtection.transformSegment(Uint8List(375), 1)),
    'transformSegment(seed 2^32)': _sync(() => BigoHlsProtection.transformSegment(Uint8List(376), 4294967296)),
  });
}

// 3.x models (the parts the Bigo classes use) ---------------------------------

enum LiveStatus { live, offline, replay, unknown, banned }

enum AudienceMetricType { popularity, onlineViewers, totalViewers, followers, unknown }

/// Dio's CancelToken, reduced to what 3.x's Bigo classes use.
class CancelToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancel => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// 3.x's request_scope.dart.
Future<T> withRequestCancellation<T>(CancelToken? caller, Future<T> Function(CancelToken transport) consume) async {
  final transport = CancelToken();
  if (caller?.isCancelled == true) transport.cancel();
  final forwarding = caller?.whenCancel.asStream().listen((_) {
    if (!transport.isCancelled) transport.cancel();
  });
  try {
    return await consume(transport);
  } finally {
    await forwarding?.cancel();
    if (!transport.isCancelled) transport.cancel();
    await transport.whenCancel;
  }
}

String i18n(String key) =>
    const {
      'bigo_category_public': '公开推荐',
      'bigo_chat_notice': 'Bigo Live 远端聊天尚待接入；目录 user_count 仅作为当前直播在线人数，房间详情缺值时保持未知。',
      'bigo_login_required': '该房间当前要求登录，直播状态与媒体保持未知。',
      'bigo_access_restricted': '该房间受密码或付费访问限制，直播状态与媒体保持未知。',
      'bigo_quality_live': '直播自动',
    }[key] ??
    (throw StateError('No zh.json text for $key'));

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

abstract interface class LiveInputRecipe {
  String get identity;
}

class LivePlayUrlResolution {
  const LivePlayUrlResolution({required this.urls, this.appliedQualityData}) : inputRecipe = null;

  const LivePlayUrlResolution.owned({required LiveInputRecipe input, this.appliedQualityData})
    : inputRecipe = input,
      urls = const [];

  final List<String> urls;
  final Object? appliedQualityData;
  final LiveInputRecipe? inputRecipe;
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

// 3.x's Bigo adapter (legacy/lib/core/site/bigo/) -----------------------------
//
// Unchanged apart from the model names above and the transport: no Dio, so
// `CancelToken` is the stub above, `kIsWeb` is false, and `_defaultRequest`
// / `readBody` are left out; the default callback and token builders stay.

// bigo_api.dart

enum BigoFailure {
  transport,
  access,
  missing,
  rateLimited,
  service,
  api,
  schema,
  identity,
  unknownState,
  notLive,
  mediaUnavailable,
  cancelled,
}

enum BigoAccess { public, loginRequired, restricted }

class BigoException implements Exception {
  const BigoException(this.kind);
  final BigoFailure kind;
  @override
  String toString() => 'Bigo ${kind.name}';
}

class BigoDirectoryCard {
  const BigoDirectoryCard({
    required this.siteId,
    required this.ownerId,
    required this.broadcastId,
    required this.sid,
    required this.title,
    required this.nickname,
    required this.cover,
    required this.reportedViewers,
    required this.locked,
    required this.roomFlag,
  });
  final String siteId;
  final int ownerId;
  // JSON numbers here exceed JS's exact integer range. Preserve native int64
  // spelling; do not convert through a double or use it as the public site ID.
  final String broadcastId;
  final int sid;
  final String title;
  final String nickname;
  final String? cover;
  final int? reportedViewers;
  final bool locked;
  final int roomFlag;
}

/// Metadata only. Access-gated alive=0 is not a verified offline observation.
/// Media parsing/registration awaits an actual permitted media response.
class BigoStudioStatus {
  const BigoStudioStatus({
    required this.requestedSiteId,
    required this.ownerId,
    required this.canonicalSiteId,
    required this.access,
    required this.reportedAlive,
    required this.roomStatus,
    required this.roomType,
  });
  final String requestedSiteId;
  final String canonicalSiteId;
  final int ownerId;
  final BigoAccess access;
  final bool? reportedAlive;
  final int roomStatus;
  final String roomType;
}

class BigoStudioRoom {
  const BigoStudioRoom({
    required this.status,
    required this.roomId,
    required this.nickname,
    required this.title,
    required this.category,
    required this.avatar,
    required this.hls,
  });

  final BigoStudioStatus status;
  final String? roomId;
  final String nickname;
  final String title;
  final String category;
  final String? avatar;
  final Uri? hls;
}

typedef BigoRequest = Future<({int status, String body})> Function(
  String method,
  Uri uri,
  Map<String, String>? form,
  CancelToken cancel,
);
typedef BigoTokenDataBuilder = String Function(String timestamp);
typedef BigoJsonpCallbackFactory = String Function();

class BigoApi {
  BigoApi({
    required BigoRequest request,
    BigoTokenDataBuilder? tokenDataBuilder,
    BigoJsonpCallbackFactory? callbackFactory,
    this.deadline = const Duration(seconds: 20),
  }) : _request = request,
       _tokenDataBuilder = tokenDataBuilder ?? BigoTokenCodec.buildData,
       _callbackFactory = callbackFactory ?? _defaultCallback;
  static const origin = 'https://ta.bigo.tv/official_website';
  static const securityOrigin = 'https://sec.bigo.sg/v1/webjs';
  static const webOrigin = 'https://www.bigo.tv';
  static const headers = {'Origin': webOrigin, 'Referer': '$webOrigin/', 'User-Agent': 'Mozilla/5.0'};
  static const responseLimit = 1024 * 1024;
  final BigoRequest _request;
  final BigoTokenDataBuilder _tokenDataBuilder;
  final BigoJsonpCallbackFactory _callbackFactory;
  final Duration deadline;

  static String _defaultCallback() =>
      'jsonpcallback_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecondsSinceEpoch % 1000000}';

  Future<T> _scope<T>(CancelToken? caller, Future<T> Function(CancelToken) work) =>
      withRequestCancellation(caller, (transport) async {
        if (transport.isCancelled) throw const BigoException(BigoFailure.cancelled);
        try {
          return await Future.any<T>([
            work(transport),
            transport.whenCancel.then<T>((_) => throw const BigoException(BigoFailure.cancelled)),
          ]).timeout(deadline);
        } on TimeoutException {
          throw const BigoException(BigoFailure.transport);
        } catch (error) {
          if (caller?.isCancelled == true) throw const BigoException(BigoFailure.cancelled);
          if (error is BigoException) rethrow;
          throw const BigoException(BigoFailure.transport);
        }
      });

  Future<String> _readResponse(String method, Uri uri, CancelToken cancel, {Map<String, String>? form}) async {
    if (cancel.isCancelled) throw const BigoException(BigoFailure.cancelled);
    final response = await _request(method, uri, form, cancel);
    if (cancel.isCancelled) throw const BigoException(BigoFailure.cancelled);
    final failure = switch (response.status) {
      200 => null,
      401 || 403 => BigoFailure.access,
      404 => BigoFailure.missing,
      429 => BigoFailure.rateLimited,
      >= 500 => BigoFailure.service,
      _ => BigoFailure.transport,
    };
    if (failure != null) throw BigoException(failure);
    if (response.body.length > responseLimit || utf8.encode(response.body).length > responseLimit) {
      throw const BigoException(BigoFailure.schema);
    }
    return response.body;
  }

  Future<Map<String, dynamic>> _readUri(String method, Uri uri, CancelToken cancel, {Map<String, String>? form}) async {
    try {
      return _object(jsonDecode(await _readResponse(method, uri, cancel, form: form)));
    } on FormatException {
      throw const BigoException(BigoFailure.schema);
    }
  }

  Future<Map<String, dynamic>> _read(String path, CancelToken cancel, {Map<String, String>? form}) =>
      _readUri(form == null ? 'GET' : 'POST', Uri.parse('$origin$path'), cancel, form: form);

  /// Verified US/English homepage request; finite snapshot, not all rooms or
  /// a pagination contract. The server returned 20 rows despite fetchNum=10.
  Future<List<BigoDirectoryCard>> directory({CancelToken? cancel}) => _scope(
    cancel,
    (token) async =>
        parseDirectory(await _read('/OInterfaceWeb/vedioList/72?tabType=00&fetchNum=10&lang=en&countryCode=US', token)),
  );

  Future<BigoStudioStatus> studioStatus({required String siteId, required int expectedOwnerId, CancelToken? cancel}) =>
      _scope(cancel, (token) async {
        validateSiteId(siteId);
        _ownerId(expectedOwnerId);
        return parseStudioStatus(
          await _read('/studio/getInternalStudioInfo', token, form: {'siteId': siteId, 'supportHevc': '0'}),
          siteId: siteId,
          expectedOwnerId: expectedOwnerId,
        );
      });

  /// Resolves the current public web token before reading status/media. The
  /// token and HLS lease remain inside the caller-owned request scope.
  Future<BigoStudioRoom> studioRoom({required String siteId, int? expectedOwnerId, CancelToken? cancel}) =>
      _scope(cancel, (token) async {
        validateSiteId(siteId);
        if (expectedOwnerId != null) _ownerId(expectedOwnerId);
        final accessToken = await _webToken(token);
        final uri = Uri.parse('$origin/studio/getInternalStudioInfo')
            .replace(queryParameters: <String, String>{'siteId': siteId, 'verify': '', 'token': accessToken});
        return parseStudioRoom(await _readUri('POST', uri, token), siteId: siteId, expectedOwnerId: expectedOwnerId);
      });

  Future<String> _webToken(CancelToken cancel) async {
    final timestampCallback = _callback();
    final timestampJson = _jsonp(
      await _readResponse(
        'GET',
        Uri.parse('$securityOrigin/t').replace(queryParameters: {'callback': timestampCallback}),
        cancel,
      ),
      timestampCallback,
    );
    if (timestampJson['code'] is! int) throw const BigoException(BigoFailure.schema);
    final timestamp = _text(timestampJson['time']);
    if (!RegExp(r'^[0-9]{1,20}$').hasMatch(timestamp)) throw const BigoException(BigoFailure.schema);
    final statusCallback = _callback();
    final statusJson = _jsonp(
      await _readResponse(
        'GET',
        Uri.parse('$securityOrigin/status')
            .replace(queryParameters: {'callback': statusCallback, 'data': _tokenDataBuilder(timestamp)}),
        cancel,
      ),
      statusCallback,
    );
    final accessToken = _text(statusJson['token']);
    if (accessToken.isEmpty || accessToken.length > 4096 || RegExp(r'[\x00-\x20\x7f]').hasMatch(accessToken)) {
      throw const BigoException(BigoFailure.schema);
    }
    return accessToken;
  }

  String _callback() {
    final value = _callbackFactory();
    if (!RegExp(r'^jsonp[A-Za-z0-9_]{1,96}$').hasMatch(value)) throw const BigoException(BigoFailure.schema);
    return value;
  }

  static Map<String, dynamic> _jsonp(String source, String callback) {
    final prefix = '$callback(';
    final trimmed = source.trim();
    if (!trimmed.startsWith(prefix) || !trimmed.endsWith(');')) throw const BigoException(BigoFailure.schema);
    final body = trimmed.substring(prefix.length, trimmed.length - 2);
    try {
      return _object(jsonDecode(body));
    } on FormatException {
      throw const BigoException(BigoFailure.schema);
    }
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) throw const BigoException(BigoFailure.schema);
    return value;
  }

  static String _text(Object? value) {
    if (value is! String) throw const BigoException(BigoFailure.schema);
    return value;
  }

  static int _number(Object? value) {
    if (value is! int || value < 0) throw const BigoException(BigoFailure.schema);
    return value;
  }

  static int _ownerId(Object? value) {
    if (value is! int || value < 1 || value > 9007199254740991) throw const BigoException(BigoFailure.identity);
    return value;
  }

  static String validateSiteId(String value) {
    if (!RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$').hasMatch(value)) {
      throw const BigoException(BigoFailure.identity);
    }
    return value;
  }

  static bool _binary(Object? value) {
    if (value is! int || (value != 0 && value != 1)) throw const BigoException(BigoFailure.schema);
    return value == 1;
  }

  static bool _boolean(Object? value) {
    if (value is! bool) throw const BigoException(BigoFailure.schema);
    return value;
  }

  static Map<String, dynamic> _success(Map<String, dynamic> json) {
    final code = json['code'];
    if (code is! int) throw const BigoException(BigoFailure.schema);
    if (code != 0) throw const BigoException(BigoFailure.api);
    return _object(json['data']);
  }

  static List<BigoDirectoryCard> parseDirectory(Map<String, dynamic> json) {
    final envelope = _success(json);
    if (envelope['resCode'] is! String) throw const BigoException(BigoFailure.schema);
    if (envelope['resCode'] != '0') throw const BigoException(BigoFailure.api);
    final rows = envelope['data'];
    if (rows is! List || rows.length > 500) throw const BigoException(BigoFailure.schema);
    final seen = <String>{};
    final owners = <int>{};
    final result = <BigoDirectoryCard>[];
    for (final row in rows) {
      final item = _object(row);
      final siteId = validateSiteId(_text(item['bigo_id']));
      final owner = _ownerId(item['owner']);
      if (!seen.add(siteId) || !owners.add(owner)) throw const BigoException(BigoFailure.identity);
      final broadcast = item['room_id'];
      if (broadcast is! int || broadcast < 1 || (false && broadcast > 9007199254740991)) {
        throw const BigoException(BigoFailure.identity);
      }
      result.add(
        BigoDirectoryCard(
          siteId: siteId,
          ownerId: owner,
          broadcastId: broadcast.toString(),
          sid: _ownerId(item['sid']),
          title: _text(item['room_topic']),
          nickname: _text(item['nick_name']),
          cover: item['cover_m'] == null ? null : _text(item['cover_m']),
          reportedViewers: item['user_count'] == null ? null : _number(item['user_count']),
          locked: _binary(item['is_locked']),
          roomFlag: _number(item['room_flag']),
        ),
      );
    }
    return List.unmodifiable(result);
  }

  static BigoStudioStatus parseStudioStatus(
    Map<String, dynamic> json, {
    required String siteId,
    required int expectedOwnerId,
  }) {
    validateSiteId(siteId);
    _ownerId(expectedOwnerId);
    final data = _success(json);
    final owner = _ownerId(data['uid']);
    if (owner != expectedOwnerId) throw const BigoException(BigoFailure.identity);
    final login = _boolean(data['needLogin']);
    final password = _boolean(data['passRoom']);
    final paid = _text(data['isPaidShow']);
    if (!{'', '0', '1'}.contains(paid)) throw const BigoException(BigoFailure.schema);
    final alive = _binary(data['alive']);
    final access = login
        ? BigoAccess.loginRequired
        : (password || paid == '1')
        ? BigoAccess.restricted
        : BigoAccess.public;
    return BigoStudioStatus(
      requestedSiteId: siteId,
      ownerId: owner,
      canonicalSiteId: validateSiteId(_text(data['clientBigoId'])),
      access: access,
      reportedAlive: access == BigoAccess.public ? alive : null,
      roomStatus: _number(data['roomStatus']),
      roomType: _text(data['roomType']),
    );
  }

  static BigoStudioRoom parseStudioRoom(Map<String, dynamic> json, {required String siteId, int? expectedOwnerId}) {
    validateSiteId(siteId);
    if (expectedOwnerId != null) _ownerId(expectedOwnerId);
    final data = _success(json);
    final owner = _ownerId(data['uid']);
    if (expectedOwnerId != null && owner != expectedOwnerId) throw const BigoException(BigoFailure.identity);
    final status = parseStudioStatus(json, siteId: siteId, expectedOwnerId: owner);
    final rawRoomId = data['roomId'];
    final roomId = rawRoomId == null || rawRoomId == '' || rawRoomId == '0' ? null : _text(rawRoomId);
    if (roomId != null && !RegExp(r'^[1-9][0-9]{0,31}$').hasMatch(roomId)) {
      throw const BigoException(BigoFailure.schema);
    }
    final nickname = data['nick_name'] == null ? '' : _text(data['nick_name']);
    final title = data['roomTopic'] == null ? '' : _text(data['roomTopic']);
    final category = data['gameTitle'] == null ? '' : _text(data['gameTitle']);
    final rawAvatar = data['avatar'];
    final avatar = rawAvatar == null || rawAvatar == '' ? null : _httpsUri(_text(rawAvatar)).toString();
    final rawHls = data['hls_src'];
    final hls = rawHls == null || rawHls == '' ? null : _httpsUri(_text(rawHls), hls: true);
    if (status.access != BigoAccess.public && hls != null) throw const BigoException(BigoFailure.schema);
    if (status.reportedAlive == false && hls != null) throw const BigoException(BigoFailure.schema);
    return BigoStudioRoom(
      status: status,
      roomId: roomId,
      nickname: nickname,
      title: title,
      category: category,
      avatar: avatar,
      hls: hls,
    );
  }

  static Uri _httpsUri(String source, {bool hls = false}) {
    final uri = Uri.tryParse(source);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (hls && !uri.path.toLowerCase().endsWith('.m3u8'))) {
      throw const BigoException(BigoFailure.schema);
    }
    return uri;
  }
}

// bigo_token.dart

/// Reproduces the current public Bigo web token envelope. The passphrase is a
/// website protocol constant used by the browser bundle, not account material.
final class BigoTokenCodec {
  const BigoTokenCodec._();

  static const _passphrase = 'undefinedval0x01';

  static String buildData(String timestamp, {Uint8List? salt, String? randomHex}) {
    if (!RegExp(r'^[0-9]{1,20}$').hasMatch(timestamp)) {
      throw const FormatException('Invalid Bigo token timestamp');
    }
    final random = Random.secure();
    final actualSalt = salt ?? Uint8List.fromList(List<int>.generate(8, (_) => random.nextInt(256)));
    if (actualSalt.length != 8) throw const FormatException('Invalid Bigo token salt');
    final dr = randomHex ?? List<String>.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(dr)) throw const FormatException('Invalid Bigo token nonce');
    final payload = utf8.encode(
      jsonEncode(<String, String>{
        'dr': dr,
        'business': 'bigolive-video',
        'scene': '',
        'at_time': timestamp,
        'ver': '2.0',
      }),
    );
    final (key, iv) = _evpBytesToKey(
      Uint8List.fromList(utf8.encode(_passphrase)),
      Uint8List.fromList(actualSalt),
      keyLength: 32,
      ivLength: 16,
    );
    final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..init(
        true,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV(KeyParameter(key), iv),
          null,
        ),
      );
    final encrypted = cipher.process(Uint8List.fromList(payload));
    return base64Encode(<int>[...ascii.encode('Salted__'), ...actualSalt, ...encrypted]);
  }

  static (Uint8List, Uint8List) _evpBytesToKey(
    Uint8List password,
    Uint8List salt, {
    required int keyLength,
    required int ivLength,
  }) {
    final output = BytesBuilder(copy: false);
    Uint8List previous = Uint8List(0);
    while (output.length < keyLength + ivLength) {
      previous = Uint8List.fromList(md5.convert(<int>[...previous, ...password, ...salt]).bytes);
      output.add(previous);
    }
    final bytes = output.takeBytes();
    return (Uint8List.sublistView(bytes, 0, keyLength), Uint8List.sublistView(bytes, keyLength, keyLength + ivLength));
  }
}

// bigo_hls_protection.dart

/// Parser and packet-prefix transform for Bigo's public web HLS extension.
/// Applying [transformSegment] twice with the same seed restores the source.
final class BigoHlsProtection {
  const BigoHlsProtection._();

  static final RegExp _tag = RegExp(
    r'^#EXT-X-BIGO-WEB-PROTECTION:SEED=([0-9]+)\s*$',
    multiLine: true,
    caseSensitive: false,
  );

  static int? seedFromManifest(String manifest) {
    final match = _tag.firstMatch(manifest);
    if (match == null) return null;
    final value = int.tryParse(match.group(1)!);
    if (value == null || value < 0 || value > 0xffffffff) {
      throw const FormatException('Invalid Bigo HLS protection seed');
    }
    return value;
  }

  static Uint8List transformSegment(List<int> source, int seed) {
    if (seed < 0 || seed > 0xffffffff) throw const FormatException('Invalid Bigo HLS protection seed');
    if (source.length < 376) throw const FormatException('Truncated Bigo HLS segment');
    final packets = Uint8List.fromList(source);
    for (var packet = 0; packet < 2; packet++) {
      var state = (seed ^ ((packet + 1) * 2654435769)) & 0xffffffff;
      if (state == 0) state = 1831565813;
      final packetOffset = packet * 188;
      for (var offset = 0; offset < 16; offset++) {
        state = (state ^ ((state << 13) & 0xffffffff)) & 0xffffffff;
        state = (state ^ (state >> 17)) & 0xffffffff;
        state = (state ^ ((state << 5) & 0xffffffff)) & 0xffffffff;
        var mask = state & 0xff;
        if (mask == 0) mask = 165;
        packets[packetOffset + offset] ^= mask;
      }
    }
    return packets;
  }
}

// bigo_input_recipe.dart

final class BigoInputRecipe implements LiveInputRecipe {
  BigoInputRecipe(String siteId) : siteId = BigoApi.validateSiteId(siteId);

  final String siteId;

  @override
  String get identity => 'bigo:$siteId:live';
}

// bigo_link.dart

final class BigoLink {
  const BigoLink._();

  static const _reserved = {'about', 'download', 'index', 'live', 'login', 'search', 'signup'};

  static String? parse(String raw) {
    if (raw.length > 8192 || RegExp(r'[\x00-\x20\x7f]').hasMatch(raw)) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      return null;
    }
    final host = uri.host.toLowerCase();
    if (host != 'bigo.tv' && host != 'www.bigo.tv') return null;
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList(growable: false);
    final candidate = switch (segments) {
      [final id] => id,
      [final locale, final id] when RegExp(r'^[a-zA-Z]{2}$').hasMatch(locale) => id,
      _ => null,
    };
    if (candidate == null || _reserved.contains(candidate.toLowerCase())) return null;
    try {
      return BigoApi.validateSiteId(candidate);
    } on BigoException {
      return null;
    }
  }

  static String? parseOrSiteId(String raw) {
    final value = raw.trim();
    final parsed = parse(value);
    if (parsed != null) return parsed;
    try {
      return BigoApi.validateSiteId(value);
    } on BigoException {
      return null;
    }
  }

  static String url(String siteId) => 'https://www.bigo.tv/${BigoApi.validateSiteId(siteId)}';
}

// bigo_site.dart (the platform argument kept; `getDanmaku` left out)

final class BigoSite {
  BigoSite({BigoApi? api}) : _api = api!;

  final BigoApi _api;
  Future<List<BigoDirectoryCard>>? _directoryRequest;
  DateTime? _directoryAt;

  String get id => 'bigo';

  String get name => 'Bigo Live';

  String get directoryNoticeKey => 'bigo_directory_scope';

  Future<List<BigoDirectoryCard>> _directory({CancelToken? cancel}) {
    if (cancel != null) return _api.directory(cancel: cancel);
    final now = DateTime.now();
    final cached = _directoryRequest;
    if (cached != null && _directoryAt != null && now.difference(_directoryAt!) < const Duration(seconds: 30)) {
      return cached;
    }
    late final Future<List<BigoDirectoryCard>> request;
    request = _api
        .directory()
        .then((value) {
          _directoryAt = DateTime.now();
          return value;
        })
        .catchError((Object error) {
          if (identical(_directoryRequest, request)) {
            _directoryRequest = null;
            _directoryAt = null;
          }
          throw error;
        });
    return _directoryRequest = request;
  }

  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    if (page != 1 || pageSize < 1) return [];
    return [
      LiveCategory(
        id: id,
        name: name,
        children: [
          LiveArea(
            platform: id,
            areaType: 'public',
            areaId: '72',
            areaName: i18n('bigo_category_public'),
            typeName: name,
          ),
        ],
      ),
    ];
  }

  void _category(LiveArea? category) {
    if (category != null && (category.platform != id || category.areaType != 'public' || category.areaId != '72')) {
      throw const BigoException(BigoFailure.identity);
    }
  }

  static List<T> _page<T>(List<T> values, int page, int pageSize) {
    if (page < 1 || pageSize < 1 || pageSize > 100) return [];
    final start = (page - 1) * pageSize;
    if (start >= values.length) return [];
    return values.sublist(start, (start + pageSize).clamp(0, values.length));
  }

  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    _category(category);
    if (page < 1) throw const BigoException(BigoFailure.schema);
    final cards = await _directory(cancel: cancel);
    const size = 20;
    final rooms = _page(cards, page, size).map(_card).toList(growable: false);
    return LiveDirectoryPage(rooms: rooms, page: page, hasMore: page * size < cards.length);
  }

  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async =>
      _page(await _directory(), page, pageSize).map(_card).toList(growable: false);

  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    _category(category);
    return getRecommendRooms(page: page, pageSize: pageSize);
  }

  static LiveRoom _card(BigoDirectoryCard card) {
    final viewers = card.reportedViewers?.toString();
    return LiveRoom(
      platform: 'bigo',
      roomId: card.siteId,
      userId: '${card.ownerId}',
      title: card.title.isEmpty ? card.nickname : card.title,
      nick: card.nickname,
      cover: card.cover ?? '',
      avatar: card.cover ?? '',
      area: 'Bigo Live',
      link: BigoLink.url(card.siteId),
      liveStatus: LiveStatus.live,
      watching: viewers ?? '',
      onlineViewers: viewers,
      totalViewers: null,
      audienceMetricType: AudienceMetricType.onlineViewers,
      notice: i18n('bigo_chat_notice'),
      httpHeaders: BigoApi.headers,
    );
  }

  LiveRoom _room(BigoStudioRoom room, {required bool includeMedia}) {
    final status = room.status;
    final liveStatus = switch ((status.access, status.reportedAlive, room.hls)) {
      (BigoAccess.public, true, Uri()) => LiveStatus.live,
      (BigoAccess.public, false, _) => LiveStatus.offline,
      _ => LiveStatus.unknown,
    };
    final notice = switch (status.access) {
      BigoAccess.loginRequired => i18n('bigo_login_required'),
      BigoAccess.restricted => i18n('bigo_access_restricted'),
      BigoAccess.public => i18n('bigo_chat_notice'),
    };
    return LiveRoom(
      platform: id,
      roomId: status.canonicalSiteId,
      userId: '${status.ownerId}',
      title: room.title.isEmpty ? room.nickname : room.title,
      nick: room.nickname,
      avatar: room.avatar ?? '',
      cover: room.avatar ?? '',
      area: room.category.isEmpty ? name : room.category,
      link: BigoLink.url(status.canonicalSiteId),
      liveStatus: liveStatus,
      onlineViewers: null,
      totalViewers: null,
      notice: notice,
      httpHeaders: BigoApi.headers,
      data: includeMedia && liveStatus == LiveStatus.live ? room : null,
    );
  }

  String _identity(String roomId, String platform) {
    if (platform.trim().toLowerCase() != id) throw const BigoException(BigoFailure.identity);
    return BigoApi.validateSiteId(roomId);
  }

  Future<LiveRoom> _detail(String roomId, String platform, {required bool includeMedia}) async =>
      _room(await _api.studioRoom(siteId: _identity(roomId, platform)), includeMedia: includeMedia);

  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) =>
      _detail(roomId, platform, includeMedia: true);

  Future<LiveRoom> getRoomDetailForRefresh({required String roomId, required String platform}) =>
      _detail(roomId, platform, includeMedia: false);

  Future<LiveRoom> getRoomDetailForRecording({required String roomId, required String platform}) =>
      _detail(roomId, platform, includeMedia: true);

  Future<bool> getLiveStatus({required String platform, required String roomId}) async {
    final room = await getRoomDetailForRefresh(roomId: roomId, platform: platform);
    if (room.effectiveLiveStatus == LiveStatus.unknown) throw const BigoException(BigoFailure.unknownState);
    return room.isLiveNow;
  }

  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    if (page != 1 || pageSize < 1) return const [];
    final query = keyword.trim();
    final linkId = BigoLink.parse(query);
    if (linkId != null) return _exactSearch(linkId, cancel: cancel);
    if (query.isEmpty ||
        query.length > 100 ||
        RegExp(r'[\x00-\x1f]').hasMatch(query) ||
        Uri.tryParse(query)?.hasScheme == true) {
      return const [];
    }
    final siteId = BigoLink.parseOrSiteId(query);
    final looksLikeId = siteId != null && RegExp(r'[0-9_.-]').hasMatch(query);
    if (looksLikeId) {
      final exact = await _exactSearch(siteId, cancel: cancel);
      if (exact.isNotEmpty) return exact;
    }
    // The public web search endpoints currently return null even for a known
    // live ID. Filter the verified finite recommendation snapshot instead of
    // presenting that empty response as a platform-wide search result.
    final cards = await _directory(cancel: cancel);
    if (cancel?.isCancelled == true) throw const BigoException(BigoFailure.cancelled);
    if (siteId != null && !looksLikeId && cards.any((card) => card.siteId.toLowerCase() == query.toLowerCase())) {
      return _exactSearch(siteId, cancel: cancel);
    }
    final needle = query.toLowerCase();
    final matches = <String, LiveRoom>{};
    for (final card in cards) {
      if (card.nickname.toLowerCase().contains(needle) || card.title.toLowerCase().contains(needle)) {
        matches.putIfAbsent(card.siteId.toLowerCase(), () => _card(card));
      }
    }
    if (matches.isNotEmpty) return List.unmodifiable(matches.values);
    if (siteId != null && !looksLikeId) return _exactSearch(siteId, cancel: cancel);
    return const [];
  }

  Future<List<LiveRoom>> _exactSearch(String siteId, {CancelToken? cancel}) async {
    try {
      return [_room(await _api.studioRoom(siteId: siteId, cancel: cancel), includeMedia: false)];
    } on BigoException catch (error) {
      if (error.kind == BigoFailure.missing) return const [];
      rethrow;
    }
  }

  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    final siteId = _identity(detail.roomId ?? '', detail.platform ?? '');
    if (detail.isExplicitlyOfflineNow) return const [];
    final room = detail.data;
    if (detail.effectiveLiveStatus != LiveStatus.live ||
        room is! BigoStudioRoom ||
        room.status.canonicalSiteId != siteId) {
      throw const BigoException(BigoFailure.mediaUnavailable);
    }
    return [LivePlayQuality(id: 'live', quality: i18n('bigo_quality_live'))];
  }

  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final siteId = _identity(detail.roomId ?? '', detail.platform ?? '');
    if (detail.isExplicitlyOfflineNow) throw const BigoException(BigoFailure.notLive);
    if (quality.selectionId != 'live' || (await getPlayQualites(detail: detail)).isEmpty) {
      throw const BigoException(BigoFailure.mediaUnavailable);
    }
    return LivePlayUrlResolution.owned(input: BigoInputRecipe(siteId), appliedQualityData: 'live');
  }

  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => resolvePlayUrlsRaw(detail: detail, quality: quality);

  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    await resolvePlayUrlsRaw(detail: detail, quality: quality);
    return const [];
  }
}
