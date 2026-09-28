// Writes expected.json for the Steam broadcast samples: 3.x's parsers run over
// the recorded responses (docs/modules/M4.27-steambroadcast.md, "样本与 v3 的
// 冻结输出").
//
// The archive has no Steam broadcast expected.json (its legacy harness only
// covered five platforms, spec/sites/steambroadcast.md §11, and 3.x no longer
// builds). The code below is 3.x's SteamBroadcastApi, SteamBroadcastLink and
// SteamBroadcastSite, copied from legacy/lib/core/site/steambroadcast/
// (archive/v4). 3.x already injected its transport (`SteamBroadcastRequest`),
// so only that is replaced: `_fixtureRequest` answers from the samples by
// host, path and query, with the recorded status and body; a request without
// a sample throws a StateError, which 3.x's `_scope` reports as a `transport`
// failure, and is listed under `unmatched`. The streamed body reader
// (`_defaultRequest`, `_readBody`) is left out (it only ran on the network
// path) and the constructors require the transport. `withRequestCancellation`
// (legacy/lib/core/common/request_scope.dart) is copied with Dio's
// CancelToken reduced to a stub. `i18n` returns 3.x's zh.json text of the
// keys used. 3.x's LiveRoom, LiveArea, LiveCategory, LivePlayQuality,
// LiveDirectoryPage and LivePlayUrlResolution are reduced to the parts these
// classes use (toJson with 3.x's HttpHeaderPolicy.normalize). The site keeps
// its method bodies; `extends LiveSite`, `implements`, `@override` and
// `getDanmaku` (EmptyDanmaku) are dropped. The output format is the legacy
// harness's (`roomProjection`, `errorProjection`, `{generator, value}`);
// every entry point also records its requests and their headers.
//
// 3.x read a room from its watch page, `getbroadcastmpd` and (for playback)
// the HLS master; the archive recorded none of the watch pages and masters,
// so M4.27 recorded them on 2026-09-28 (`S05-*`, one moment, with 3.x's
// headers). `S05-watch-offline` is paired with the archive's
// `S04-mpd-offline` (the same account; the answer carries no time).
//
// 3.x parsed the pages with package:html, which the workspace does not depend
// on, so this runs with a throwaway package configuration (3.x's pubspec:
// html ^0.15.4; generated with 0.15.6, as for TwitCasting, niconico and
// Xiaohongshu). From the repository root:
//
//   d=$(mktemp -d)
//   printf 'name: g\nenvironment:\n  sdk: ^3.9.0\ndependencies:\n  html: 0.15.6\n' > "$d/pubspec.yaml"
//   (cd "$d" && dart pub get --offline)
//   dart --packages="$d/.dart_tool/package_config.json" fixtures/steambroadcast/legacy_expected.dart
//
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

const _root = 'fixtures/steambroadcast';

/// The live broadcaster of S01 (first card), S02-info-live, S03, S04 and S05.
const _live = '76561199485215572';

/// The offline account of S02-info-offline, S04-mpd-offline and S05.
const _offline = '76561197960287930';

const _directorySamples = ['S01-directory-p1', 'S01-directory-p2'];
const _liveSamples = ['S05-watch-live', 'S05-mpd-live', 'S05-master-live'];
const _offlineSamples = ['S05-watch-offline', 'S04-mpd-offline'];

/// Keywords run through 3.x's search on page 1: titles, games and names (any
/// case), a part of an id, words in no card, the live and offline ids and
/// watch links, a profile link (not a watch link), a blank.
const _keywords = [
  'NTE',
  'neverness',
  'pwm game',
  'ARTDOCK',
  '7656119948521',
  'zzqxnomatch',
  _live,
  ' $_live ',
  'https://steamcommunity.com/broadcast/watch/$_live',
  'https://steamcommunity.com/broadcast/watch/$_live?l=english',
  _offline,
  'https://steamcommunity.com/profiles/$_live',
  '   ',
];

/// Inputs for 3.x's `SteamBroadcastLink.parseSteamId` (no requests); the
/// first six and `7656119837352774` are 3.x's own test cases.
const _links = [
  '76561198373527746',
  'https://steamcommunity.com/broadcast/watch/76561198373527746?l=english',
  'https://steam.tv/example',
  'https://steamcommunity.com/app/730/broadcasts',
  'https://steamcommunity.com/broadcast/watch/76561198373527746/more',
  'https://steamcommunity.com.evil.test/broadcast/watch/76561198373527746',
  '7656119837352774',
  ' 76561198373527746 ',
  '76561198373527746x',
  '86561198373527746',
  'http://steamcommunity.com/broadcast/watch/76561198373527746',
  'https://steamcommunity.com/broadcast/watch/76561198373527746/',
  'https://STEAMCOMMUNITY.com/broadcast/watch/76561198373527746',
  'https://www.steamcommunity.com/broadcast/watch/76561198373527746',
  'https://steamcommunity.com:443/broadcast/watch/76561198373527746',
  'https://steamcommunity.com:8443/broadcast/watch/76561198373527746',
  'https://user@steamcommunity.com/broadcast/watch/76561198373527746',
  'https://steamcommunity.com/broadcast/watch/76561198373527746#chat',
  'ftp://steamcommunity.com/broadcast/watch/76561198373527746',
  'https://steamcommunity.com/Broadcast/watch/76561198373527746',
  'https://steamcommunity.com//broadcast//watch//76561198373527746',
  'https://steamcommunity.com/broadcast/watch/%37%36561198373527746',
  'https://steamcommunity.com/broadcast/watch/%FF',
  'https://steamcommunity.com/profiles/76561198373527746',
  'https://steamcommunity.com/id/probrawlhallastream/',
  'steamcommunity.com/broadcast/watch/76561198373527746',
];

void main() async {
  await _directory();
  await _directoryPage2();
  _mpd();
  await _liveRoom();
  await _offlineRoom();
  _master();
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];
final List<Map<String, Object?>> _requests = [];
final List<String> _unmatched = [];

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync()) as Map<String, dynamic>;

void _replay(List<String> samples) {
  _samples = [for (final sample in samples) _meta(sample)];
  _requests.clear();
  _unmatched.clear();
}

bool _sameQuery(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((entry) => b[entry.key] == entry.value);

/// 3.x's `SteamBroadcastRequest` over the samples.
Future<({int status, String body})> _fixtureRequest(Uri uri, Map<String, String> headers, CancelToken cancel) async {
  _requests.add({'url': '$uri', 'headers': headers});
  for (final meta in _samples) {
    final request = meta['request'] as Map<String, dynamic>;
    final recorded = Uri.parse(request['url'] as String);
    if (recorded.host == uri.host &&
        recorded.path == uri.path &&
        _sameQuery(recorded.queryParameters, uri.queryParameters)) {
      final status = (meta['response'] as Map)['status'] as int;
      return (status: status, body: File('$_root/${meta['sample']}/${meta['body']}').readAsStringSync());
    }
  }
  _unmatched.add('GET $uri');
  throw StateError('No recorded sample for GET $uri');
}

SteamBroadcastApi _api() => SteamBroadcastApi(request: _fixtureRequest);

SteamBroadcastSite _site() => SteamBroadcastSite(api: _api());

void _write(String sample, String generator, Object? value) {
  final file = File('$_root/$sample/expected.json');
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'generator': generator, 'value': jsonDecode(jsonEncode(value))})}\n',
  );
  stdout.writeln('wrote $sample');
}

Map<String, dynamic> _errorProjection(Object error) => {
  'throws': switch (error) {
    SteamBroadcastException(:final kind) => 'SteamBroadcastException.${kind.name}',
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
    ..['data'] = switch (room.data) {
      final SteamBroadcastRoom data => _broadcastProjection(data),
      _ => null,
    };
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
};

Map<String, Object?> _broadcastProjection(SteamBroadcastRoom room) => {
  'steamId': room.steamId,
  'broadcaster': room.broadcaster,
  'title': room.title,
  'game': room.game,
  'cover': room.cover,
  'avatar': room.avatar,
  'currentViewers': room.currentViewers,
  'state': room.state.name,
  'master': room.master?.toString(),
};

Object? _broadcastPage(SteamBroadcastPage page) => {
  'rooms': [for (final room in page.rooms) _broadcastProjection(room)],
  'hasMore': page.hasMore,
};

final _trending = LiveArea(
  platform: 'steambroadcast',
  areaType: 'community',
  areaId: 'trending',
  areaName: '热门社区直播',
  typeName: 'Steam Broadcasts',
);

String _body(String sample, String name) => File('$_root/$sample/$name').readAsStringSync();

Object? _jsonBody(String sample) => jsonDecode(_body(sample, 'body.json'));

// Samples ---------------------------------------------------------------------

/// S01 page 1: the category, the directory, 3.x's slices, the search (with
/// the S05 rooms for the exact lookups) and the link rules.
Future<void> _directory() async {
  _replay([..._directorySamples, ..._liveSamples, ..._offlineSamples]);
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
    'parseDirectoryHtml': _sync(
      () => _broadcastPage(SteamBroadcastApi.parseDirectoryHtml(_body('S01-directory-p1', 'body.html'), page: 1)),
    ),
    'parseDirectoryHtml(page: 2)': _sync(
      () => _broadcastPage(SteamBroadcastApi.parseDirectoryHtml(_body('S01-directory-p1', 'body.html'), page: 2)),
    ),
  };
  value['getDirectoryPage'] = {
    'recommend:1': await _traced(() => _site().getDirectoryPage(page: 1, cancel: CancelToken()), _page),
    'trending:1': await _traced(
      () => _site().getDirectoryPage(page: 1, category: _trending, cancel: CancelToken()),
      _page,
    ),
    'recommend:0': await _traced(() => _site().getDirectoryPage(page: 0, cancel: CancelToken()), _page),
    'recommend:10001': await _traced(() => _site().getDirectoryPage(page: 10001, cancel: CancelToken()), _page),
    'otherArea:1': await _traced(
      () => _site().getDirectoryPage(
        category: LiveArea(platform: 'steambroadcast', areaType: 'community', areaId: 'other', areaName: 'x'),
        cancel: CancelToken(),
      ),
      _page,
    ),
  };
  value['getRecommendRooms'] = {
    for (final (page, size) in [(1, 30), (1, 10), (1, 3), (1, 0), (0, 30), (1, 100)])
      'page $page size $size': await _traced(() => _site().getRecommendRooms(page: page, pageSize: size), _rooms),
  };
  value['getCategoryRooms'] = {
    'trending page 1': await _traced(() => _site().getCategoryRooms(_trending, page: 1), _rooms),
    'trending page 1 size 3': await _traced(() => _site().getCategoryRooms(_trending, page: 1, pageSize: 3), _rooms),
    'otherPlatform': await _traced(
      () => _site().getCategoryRooms(LiveArea(platform: 'bilibili', areaType: 'community', areaId: 'trending')),
      _rooms,
    ),
  };
  final search = <String, Object?>{};
  for (final keyword in _keywords) {
    search['$keyword page 1'] = await _traced(
      () => _site().searchRoomsCancellable(keyword, page: 1, pageSize: 30, cancel: CancelToken()),
      _rooms,
    );
  }
  search['pwm page 1 size 101'] = await _traced(() => _site().searchRooms('pwm', page: 1, pageSize: 101), _rooms);
  search['pwm page 0'] = await _traced(() => _site().searchRooms('pwm', page: 0), _rooms);
  search['NTE page 1 size 0'] = await _traced(() => _site().searchRooms('NTE', page: 1, pageSize: 0), _rooms);
  search['$_live page 2'] = await _traced(() => _site().searchRooms(_live, page: 2), _rooms);
  value['searchRooms'] = search;
  value['SteamBroadcastLink.parseSteamId'] = {for (final link in _links) link: SteamBroadcastLink.parseSteamId(link)};
  value['SteamBroadcastLink.watchUrl'] = {
    for (final id in [_live, ' $_live ', 'https://steamcommunity.com/broadcast/watch/$_live', '123'])
      id: _sync(() => SteamBroadcastLink.watchUrl(id)),
  };
  value['parseViewerCount'] = {
    for (final text in [
      '6,763 viewers',
      '6,763 viewers ',
      '1 viewer',
      '12.345 viewers',
      '1 234 viewers',
      'viewers',
      '0 viewers',
      '1234567890123 viewers',
      '5 watching',
      '',
    ])
      text: SteamBroadcastApi.parseViewerCount(text),
  };
  _write(
    'S01-directory-p1',
    'SteamBroadcastSite.getCategores + getDirectoryPage + getRecommendRooms + getCategoryRooms + '
        'searchRoomsCancellable (with S01-directory-p2, S05-*, S04-mpd-offline) + SteamBroadcastApi.parseDirectoryHtml '
        '+ parseViewerCount + SteamBroadcastLink',
    value,
  );
}

/// S01 page 2: the directory, the slices and the search of page 2.
Future<void> _directoryPage2() async {
  _replay(_directorySamples);
  _write('S01-directory-p2', 'SteamBroadcastSite.getDirectoryPage + getRecommendRooms + searchRooms (page 2)', {
    'parseDirectoryHtml': _sync(
      () => _broadcastPage(SteamBroadcastApi.parseDirectoryHtml(_body('S01-directory-p2', 'body.html'), page: 2)),
    ),
    'getDirectoryPage': await _traced(() => _site().getDirectoryPage(page: 2, cancel: CancelToken()), _page),
    'getRecommendRooms': await _traced(() => _site().getRecommendRooms(page: 2), _rooms),
    'searchRooms': {
      for (final keyword in ['a', 'zzqxnomatch'])
        keyword: await _traced(
          () => _site().searchRoomsCancellable(keyword, page: 2, cancel: CancelToken()),
          _rooms,
        ),
    },
  });
}

/// `getbroadcastmpd`: 3.x's parse of the recorded answers, of every
/// `success` 3.x named and of the CDN parameters it appended.
void _mpd() {
  Object? parse(Object? json, {String steamId = _live}) =>
      _sync(() => _broadcastProjection(SteamBroadcastApi.parseBroadcastJson(json, steamId: steamId, broadcaster: 'X')));
  Map<String, dynamic> live() => Map<String, dynamic>.of(_jsonBody('S04-mpd-live')! as Map<String, dynamic>);
  _write('S04-mpd-live', 'SteamBroadcastApi.parseBroadcastJson', {
    'recorded': parse(_jsonBody('S04-mpd-live')),
    'otherSteamId': parse(_jsonBody('S04-mpd-live'), steamId: _offline),
    'success': {
      for (final success in [
        'ready',
        'READY',
        'unavailable',
        'offline',
        'not_live',
        'no_broadcast',
        'user_restricted',
        'waiting',
        'waiting_to_start',
        'waiting_for_start',
        'something_new',
        '',
        42,
        null,
      ])
        '$success': parse(live()..['success'] = success),
    },
    'title': {
      for (final title in ['A title', '  spaced   title ', '', null, 7]) '$title': parse(live()..['title'] = title),
    },
    'num_viewers': {
      for (final viewers in [0, 12, -1, 3.7, '15', ' 16 ', 'x', null, true])
        '$viewers': parse(live()..['num_viewers'] = viewers),
    },
    'cdn_auth_url_parameters': {
      for (final auth in [
        null,
        '',
        '  ',
        '&token=abc',
        '?token=abc&exp=1',
        '&&a=1',
        'a=1&a=2',
        'broadcast_origin=x',
        'a b=1',
        'a=1#x',
        '&',
        'a',
        7,
      ])
        '$auth': parse(live()..['cdn_auth_url_parameters'] = auth),
    },
    'hls_url': {
      for (final url in [
        'http://cache15-lax2.steamcontent.com/broadcast/$_live/2173332649075168964/hls_manifest/0/cache15-lax2.steamcontent.com/master.m3u8?broadcast_origin=ext3-sgp1.steamserver.net',
        'https://broadcast.st.dl.eccdnx.com/broadcast/$_live/2173332649075168964/hls_manifest/0/broadcast.st.dl.eccdnx.com/master.m3u8?broadcast_origin=ext3-sgp1.steamserver.net',
        'https://cache15-lax2.steamcontent.com/broadcast/$_live/2173332649075168964/hls_manifest/0/cache9-lax2.steamcontent.com/master.m3u8?broadcast_origin=ext3-sgp1.steamserver.net',
        'https://cache15-lax2.steamcontent.com/broadcast/$_offline/2173332649075168964/hls_manifest/0/cache15-lax2.steamcontent.com/master.m3u8?broadcast_origin=ext3-sgp1.steamserver.net',
        'https://cache15-lax2.steamcontent.com/broadcast/$_live/2173332649075168964/hls_manifest/0/cache15-lax2.steamcontent.com/master.m3u8',
        'https://cache15-lax2.steamcontent.com/broadcast/$_live/2173332649075168964/hls_manifest/0/cache15-lax2.steamcontent.com/master.m3u8?broadcast_origin=example.com',
        'https://cache15-lax2.steamcontent.com:8443/broadcast/$_live/2173332649075168964/hls_manifest/0/cache15-lax2.steamcontent.com/master.m3u8?broadcast_origin=ext3-sgp1.steamserver.net',
        '',
        null,
      ])
        '$url': parse(live()..['hls_url'] = url),
    },
    'notAnObject': parse(const ['ready']),
  });
  _write('S04-mpd-offline', 'SteamBroadcastApi.parseBroadcastJson', {
    'recorded': parse(_jsonBody('S04-mpd-offline'), steamId: _offline),
  });
  _write('S05-mpd-live', 'SteamBroadcastApi.parseBroadcastJson', {
    'recorded': parse(_jsonBody('S05-mpd-live')),
  });
}

/// A room at every depth, its live status, qualities and URLs, with every
/// request.
Future<Map<String, Object?>> _roomCalls(String roomId) async {
  final value = <String, Object?>{
    'getRoomDetail': await _traced(
      () => _site().getRoomDetail(roomId: roomId, platform: 'steambroadcast'),
      _roomProjection,
    ),
    'getRoomDetailForRefresh': await _traced(
      () => _site().getRoomDetailForRefresh(roomId: roomId, platform: 'steambroadcast'),
      _roomProjection,
    ),
    'getRoomDetailForRecording': await _traced(
      () => _site().getRoomDetailForRecording(roomId: roomId, platform: 'steambroadcast'),
      _roomProjection,
    ),
    'getLiveStatus': await _traced(
      () => _site().getLiveStatus(platform: 'steambroadcast', roomId: roomId),
      (live) => live,
    ),
  };
  final auto = LivePlayQuality(id: 'auto', quality: '自适应 HLS');
  for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh']) {
    final site = _site();
    final LiveRoom detail;
    try {
      detail = depth == 'getRoomDetail'
          ? await site.getRoomDetail(roomId: roomId, platform: 'steambroadcast')
          : await site.getRoomDetailForRefresh(roomId: roomId, platform: 'steambroadcast');
    } on Object catch (error) {
      value['$depth → streams'] = _errorProjection(error);
      continue;
    }
    value['$depth → streams'] = {
      'getPlayQualites': await _traced(() => site.getPlayQualites(detail: detail), _qualities),
      'resolvePlayUrlsRaw': await _traced(() => site.resolvePlayUrlsRaw(detail: detail, quality: auto), _resolution),
      'resolvePlayUrlsForRecoveryRaw': await _traced(
        () => site.resolvePlayUrlsForRecoveryRaw(detail: detail, quality: auto),
        _resolution,
      ),
      'getPlayUrls': await _traced(() => site.getPlayUrls(detail: detail, quality: auto), (urls) => urls),
      'otherQuality': await _traced(
        () => site.resolvePlayUrlsRaw(
          detail: detail,
          quality: LivePlayQuality(id: 'source', quality: 'x'),
        ),
        _resolution,
      ),
    };
  }
  return value;
}

/// S05 live: the watch page, the room at every depth (from the directory's
/// card too), the streams and the watch page checks.
Future<void> _liveRoom() async {
  _replay([..._liveSamples, ..._directorySamples]);
  final value = await _roomCalls(_live);
  value['getRoomDetail(watch link)'] = await _traced(
    () => _site().getRoomDetail(roomId: 'https://steamcommunity.com/broadcast/watch/$_live', platform: 'steambroadcast'),
    _roomProjection,
  );
  value['getRoomDetail(other platform)'] = await _traced(
    () => _site().getRoomDetail(roomId: _live, platform: 'bilibili'),
    _roomProjection,
  );
  value['getRoomDetail(not an id)'] = await _traced(
    () => _site().getRoomDetail(roomId: '123', platform: 'steambroadcast'),
    _roomProjection,
  );
  // 3.x's site remembers the cards it listed and fills a detail's missing
  // fields from them.
  final remembered = _site();
  value['after the directory'] = await _traced(() async {
    await remembered.getDirectoryPage(page: 1, cancel: CancelToken());
    final detail = await remembered.getRoomDetail(roomId: _live, platform: 'steambroadcast');
    final refreshed = await remembered.getRoomDetailForRefresh(roomId: _live, platform: 'steambroadcast');
    return [detail, refreshed];
  }, _rooms);
  final watch = _body('S05-watch-live', 'body.html');
  value['parseWatchHtml'] = {
    'recorded': _sync(() => SteamBroadcastApi.parseWatchHtml(watch, expectedSteamId: _live).broadcaster),
    'otherSteamId': _sync(() => SteamBroadcastApi.parseWatchHtml(watch, expectedSteamId: _offline).broadcaster),
    'withoutConfig': _sync(
      () => SteamBroadcastApi.parseWatchHtml(
        watch.replaceFirst('data-broadcastsinfo=', 'data-other='),
        expectedSteamId: _live,
      ).broadcaster,
    ),
    'badConfig': _sync(
      () => SteamBroadcastApi.parseWatchHtml(
        watch.replaceFirst('data-broadcastsinfo="{', 'data-broadcastsinfo="{x'),
        expectedSteamId: _live,
      ).broadcaster,
    ),
    'titleOnly': _sync(
      () => SteamBroadcastApi.parseWatchHtml(
        watch.replaceFirst(RegExp('<meta property="og:title"[^>]*>'), ''),
        expectedSteamId: _live,
      ).broadcaster,
    ),
    'noTitle': _sync(
      () => SteamBroadcastApi.parseWatchHtml(
        watch
            .replaceFirst(RegExp('<meta property="og:title"[^>]*>'), '')
            .replaceFirst(RegExp('<title>[^<]*</title>'), ''),
        expectedSteamId: _live,
      ).broadcaster,
    ),
    'unknownAccount': _sync(
      () => SteamBroadcastApi.parseWatchHtml(
        watch.replaceAll('PWM Game Manager', _live),
        expectedSteamId: _live,
      ).broadcaster,
    ),
    'emptyName': _sync(
      () => SteamBroadcastApi.parseWatchHtml(
        watch.replaceAll('PWM Game Manager', ''),
        expectedSteamId: _live,
      ).broadcaster,
    ),
  };
  _write(
    'S05-watch-live',
    'SteamBroadcastSite room calls (with S05-mpd-live, S05-master-live; S01 for the remembered cards) + '
        'SteamBroadcastApi.parseWatchHtml',
    value,
  );
}

/// S05 offline: the room at every depth, its live status and streams.
Future<void> _offlineRoom() async {
  _replay(_offlineSamples);
  final value = await _roomCalls(_offline);
  value['parseWatchHtml'] = _sync(
    () => SteamBroadcastApi.parseWatchHtml(_body('S05-watch-offline', 'body.html'), expectedSteamId: _offline)
        .broadcaster,
  );
  _write('S05-watch-offline', 'SteamBroadcastSite room calls (with S04-mpd-offline)', value);
}

/// S05 master: 3.x's check of the HLS master against the account and host.
void _master() {
  final master = _body('S05-master-live', 'body.m3u8');
  final url = Uri.parse((_jsonBody('S05-mpd-live')! as Map<String, dynamic>)['hls_url'] as String);
  Object? check(String text, {String steamId = _live, Uri? expected}) => _sync(() {
    SteamBroadcastApi.validateMaster(text, expectedSteamId: steamId, expectedMaster: expected ?? url);
    return 'valid';
  });
  final host = url.host;
  final lines = const LineSplitter().convert(master);
  final variant = lines.firstWhere((line) => line.startsWith('https://'));
  _write('S05-master-live', 'SteamBroadcastApi.validateMaster', {
    'recorded': check(master),
    'otherSteamId': check(master, steamId: _offline),
    'otherHost': check(master, expected: url.replace(host: 'cache1-lax1.steamcontent.com')),
    'variantOnOtherHost': check(master.replaceFirst(variant, variant.replaceFirst(host, 'example.com'))),
    'audioOnOtherHost': check(master.replaceFirst('URI="https://$host', 'URI="https://example.com')),
    'variantWithoutOrigin': check(master.replaceFirst(variant, variant.split('?').first)),
    'noVariant': check(lines.where((line) => !line.startsWith('#EXT-X-STREAM-INF') && line != variant).join('\n')),
    'notHls': check('<html></html>'),
    'relativeVariant': check(master.replaceFirst(variant, '6000000/video.m3u8')),
    'seventeenVariants': check(
      [
        '#EXTM3U',
        for (var index = 0; index < 17; index++) ...['#EXT-X-STREAM-INF:BANDWIDTH=${index + 1}', variant],
      ].join('\n'),
    ),
  });
}

// 3.x models (the parts the Steam broadcast classes use) ----------------------

enum LiveStatus { live, offline, replay, unknown, banned }

enum AudienceMetricType { popularity, onlineViewers, totalViewers, followers, unknown }

/// Dio's CancelToken, reduced to what 3.x's Steam broadcast classes use.
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
      'steambroadcast_category_trending': '热门社区直播',
      'steambroadcast_chat_notice': 'Steam 远端聊天尚待接入；界面人数来自平台明确返回的当前并发观看数。',
      'steambroadcast_restricted_notice': '该 Steam 直播受账号访问范围限制，界面保持未知状态，不将其显示成未开播。',
      'steambroadcast_quality_auto': '自适应 HLS',
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

// 3.x's Steam broadcast adapter (legacy/lib/core/site/steambroadcast/) --------
//
// Unchanged apart from the model names above and the transport: no Dio, so
// `CancelToken` is the stub above, and `_defaultRequest` / `_readBody` are
// left out (the constructors require the transport).

// steam_broadcast_link.dart

abstract final class SteamBroadcastLink {
  static final RegExp _steamId = RegExp(r'^7656119\d{10}$');

  static String watchUrl(String raw) => 'https://steamcommunity.com/broadcast/watch/${requireSteamId(raw)}';

  static String requireSteamId(String raw) {
    final value = parseSteamId(raw);
    if (value == null) throw const FormatException('Invalid Steam broadcast identity');
    return value;
  }

  static String? parseSteamId(String raw) {
    final value = raw.trim();
    if (_steamId.hasMatch(value)) return value;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != 'steamcommunity.com' ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 80 && uri.port != 443)) {
      return null;
    }
    late final List<String> segments;
    try {
      segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList(growable: false);
    } on FormatException {
      return null;
    }
    if (segments.length != 3 || segments[0] != 'broadcast' || segments[1] != 'watch') return null;
    return _steamId.hasMatch(segments[2]) ? segments[2] : null;
  }
}

// steam_broadcast_api.dart

enum SteamBroadcastFailure {
  transport,
  access,
  missing,
  rateLimited,
  service,
  schema,
  identity,
  cancelled,
  mediaUnavailable,
}

final class SteamBroadcastException implements Exception {
  const SteamBroadcastException(this.kind);

  final SteamBroadcastFailure kind;

  @override
  String toString() => 'Steam Broadcast ${kind.name}';
}

enum SteamBroadcastState { live, offline, restricted, unknown }

final class SteamBroadcastRoom {
  const SteamBroadcastRoom({
    required this.steamId,
    required this.broadcaster,
    required this.title,
    required this.game,
    required this.cover,
    required this.avatar,
    required this.currentViewers,
    required this.state,
    required this.master,
  });

  final String steamId;
  final String broadcaster;
  final String title;
  final String game;
  final String cover;
  final String avatar;
  final int? currentViewers;
  final SteamBroadcastState state;
  final Uri? master;

  SteamBroadcastRoom enrich(SteamBroadcastRoom known) => SteamBroadcastRoom(
    steamId: steamId,
    broadcaster: broadcaster == steamId || broadcaster == 'Steam broadcaster' ? known.broadcaster : broadcaster,
    title: title == 'Steam Broadcast' ? known.title : title,
    game: game.isEmpty ? known.game : game,
    cover: cover.isEmpty ? known.cover : cover,
    avatar: avatar.isEmpty ? known.avatar : avatar,
    currentViewers: currentViewers ?? known.currentViewers,
    state: state,
    master: master,
  );
}

final class SteamBroadcastPage {
  SteamBroadcastPage({required Iterable<SteamBroadcastRoom> rooms, required this.hasMore})
    : rooms = List.unmodifiable(rooms);

  final List<SteamBroadcastRoom> rooms;
  final bool hasMore;
}

typedef SteamBroadcastRequest =
    Future<({int status, String body})> Function(Uri uri, Map<String, String> headers, CancelToken cancel);

class SteamBroadcastApi {
  SteamBroadcastApi({required SteamBroadcastRequest request, this.deadline = const Duration(seconds: 25)})
    : _request = request;

  static const String origin = 'https://steamcommunity.com';
  static const int responseLimit = 4 * 1024 * 1024;
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
  static const Map<String, String> directoryHeaders = {
    'User-Agent': userAgent,
    'Accept': 'text/html, */*; q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': '$origin/?subsection=broadcasts',
    'X-Requested-With': 'XMLHttpRequest',
  };

  static Map<String, String> roomHeaders(String steamId, {bool json = false}) => {
    'User-Agent': userAgent,
    'Accept': json ? 'application/json, text/javascript, */*; q=0.8' : 'text/html,application/xhtml+xml,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': SteamBroadcastLink.watchUrl(steamId),
    if (json) 'X-Requested-With': 'XMLHttpRequest',
  };

  static Map<String, String> mediaHeaders(String steamId) => {
    'User-Agent': userAgent,
    'Origin': origin,
    'Referer': SteamBroadcastLink.watchUrl(steamId),
  };

  final SteamBroadcastRequest _request;
  final Duration deadline;

  Future<T> _scope<T>(CancelToken? caller, Future<T> Function(CancelToken) work) =>
      withRequestCancellation(caller, (transport) async {
        if (transport.isCancelled) throw const SteamBroadcastException(SteamBroadcastFailure.cancelled);
        try {
          return await Future.any<T>([
            work(transport),
            transport.whenCancel.then<T>((_) => throw const SteamBroadcastException(SteamBroadcastFailure.cancelled)),
          ]).timeout(deadline);
        } on TimeoutException {
          throw const SteamBroadcastException(SteamBroadcastFailure.transport);
        } catch (error) {
          if (caller?.isCancelled == true || transport.isCancelled) {
            throw const SteamBroadcastException(SteamBroadcastFailure.cancelled);
          }
          if (error is SteamBroadcastException) rethrow;
          throw const SteamBroadcastException(SteamBroadcastFailure.transport);
        }
      });

  Future<String> _get(Uri uri, Map<String, String> headers, CancelToken cancel) async {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasFragment) {
      throw const SteamBroadcastException(SteamBroadcastFailure.identity);
    }
    final response = await _request(uri, headers, cancel);
    _throwStatus(response.status);
    if (response.body.length > responseLimit) throw const SteamBroadcastException(SteamBroadcastFailure.schema);
    return response.body;
  }

  Future<SteamBroadcastPage> directory({int page = 1, CancelToken? cancel}) => _scope(cancel, (token) async {
    if (page < 1 || page > 10000) throw const SteamBroadcastException(SteamBroadcastFailure.schema);
    final uri = Uri.parse('$origin/apps/allcontenthome').replace(
      queryParameters: {
        'l': 'english',
        'browsefilter': 'trend',
        'appHubSubSection': '13',
        'forceanon': '1',
        'p': '$page',
        'broadcastsoffset': '${(page - 1) * 10}',
        'numperpage': '10',
      },
    );
    return parseDirectoryHtml(await _get(uri, directoryHeaders, token), page: page);
  });

  Future<SteamBroadcastRoom> room(String rawSteamId, {bool includeMedia = false, CancelToken? cancel}) =>
      _scope(cancel, (token) async {
        final steamId = SteamBroadcastLink.parseSteamId(rawSteamId);
        if (steamId == null) throw const SteamBroadcastException(SteamBroadcastFailure.identity);
        final watch = await _get(Uri.parse(SteamBroadcastLink.watchUrl(steamId)), roomHeaders(steamId), token);
        final metadata = parseWatchHtml(watch, expectedSteamId: steamId);
        final endpoint = Uri.parse(
          '$origin/broadcast/getbroadcastmpd/',
        ).replace(queryParameters: {'broadcastid': '0', 'steamid': steamId, 'viewertoken': '0', 'sessionid': ''});
        late final SteamBroadcastRoom room;
        try {
          room = parseBroadcastJson(
            jsonDecode(await _get(endpoint, roomHeaders(steamId, json: true), token)),
            steamId: steamId,
            broadcaster: metadata.broadcaster,
          );
        } on FormatException {
          throw const SteamBroadcastException(SteamBroadcastFailure.schema);
        }
        if (includeMedia && room.state == SteamBroadcastState.live) {
          final master = room.master;
          if (master == null) throw const SteamBroadcastException(SteamBroadcastFailure.mediaUnavailable);
          validateMaster(
            await _get(master, mediaHeaders(steamId), token),
            expectedSteamId: steamId,
            expectedMaster: master,
          );
        }
        return room;
      });

  static SteamBroadcastPage parseDirectoryHtml(String source, {required int page}) {
    if (source.length > responseLimit || page < 1) {
      throw const SteamBroadcastException(SteamBroadcastFailure.schema);
    }
    final document = html_parser.parseFragment(source);
    final seen = <String>{};
    final rooms = <SteamBroadcastRoom>[];
    for (final card in document.querySelectorAll('.Broadcast_Card')) {
      final steamId = SteamBroadcastLink.parseSteamId(
        card.querySelector('a[href*="/broadcast/watch/"]')?.attributes['href'] ?? '',
      );
      if (steamId == null || !seen.add(steamId)) continue;
      final contentType = _text(card.querySelector('.apphub_CardContentType'));
      final game = _text(card.querySelector('.apphub_CardContentTitle'));
      final broadcaster = _firstText([
        card.querySelector('.apphub_CardContentAuthorName a')?.text,
        card.querySelector('.apphub_CardContentAuthorName')?.text,
        steamId,
      ]);
      final cover = _image(card.querySelector('.apphub_CardContentPreviewImage')?.attributes['src'], steamId: steamId);
      final avatar = _avatar(card.querySelector('.appHubIconHolder img')?.attributes['src']);
      rooms.add(
        SteamBroadcastRoom(
          steamId: steamId,
          broadcaster: broadcaster,
          title: _stripBroadcastSuffix(contentType.isEmpty ? game : contentType),
          game: game,
          cover: cover,
          avatar: avatar,
          currentViewers: parseViewerCount(_text(card.querySelector('.apphub_CardContentViewers'))),
          state: SteamBroadcastState.live,
          master: null,
        ),
      );
    }
    final nextPage = int.tryParse(document.querySelector('input[name="p"]')?.attributes['value'] ?? '');
    final nextOffset = int.tryParse(
      document.querySelector('input[name="broadcastsoffset"]')?.attributes['value'] ?? '',
    );
    return SteamBroadcastPage(
      rooms: rooms,
      hasMore: rooms.isNotEmpty && nextPage == page + 1 && nextOffset == page * 10,
    );
  }

  static ({String broadcaster}) parseWatchHtml(String source, {required String expectedSteamId}) {
    if (source.length > responseLimit) throw const SteamBroadcastException(SteamBroadcastFailure.schema);
    final document = html_parser.parse(source);
    final config = document.querySelector('#application_config')?.attributes['data-broadcastsinfo'];
    if (config == null) throw const SteamBroadcastException(SteamBroadcastFailure.missing);
    late final Map<String, dynamic> decoded;
    try {
      decoded = _object(jsonDecode(config));
    } on FormatException {
      throw const SteamBroadcastException(SteamBroadcastFailure.schema);
    }
    if (_string(decoded['steamid']) != expectedSteamId) {
      throw const SteamBroadcastException(SteamBroadcastFailure.identity);
    }
    final title =
        document.querySelector('meta[property="og:title"]')?.attributes['content'] ??
        document.querySelector('title')?.text ??
        '';
    final match = RegExp(r'^Steam Community\s*::\s*(.+?)\s*::\s*Broadcast$', caseSensitive: false).firstMatch(title);
    final broadcaster = match?.group(1)?.trim();
    return (broadcaster: broadcaster == null || broadcaster.isEmpty ? 'Steam broadcaster' : broadcaster);
  }

  static SteamBroadcastRoom parseBroadcastJson(Object? value, {required String steamId, required String broadcaster}) {
    final root = _object(value);
    final success = _string(root['success']).toLowerCase();
    final state = switch (success) {
      'ready' => SteamBroadcastState.live,
      'unavailable' || 'offline' || 'not_live' || 'no_broadcast' => SteamBroadcastState.offline,
      'user_restricted' => SteamBroadcastState.restricted,
      'waiting' || 'waiting_to_start' || 'waiting_for_start' => SteamBroadcastState.unknown,
      _ => SteamBroadcastState.unknown,
    };
    Uri? master;
    if (state == SteamBroadcastState.live) {
      final raw = _string(root['hls_url']);
      master = _mediaUri(raw, steamId);
      if (master == null) throw const SteamBroadcastException(SteamBroadcastFailure.schema);
      master = _appendCdnAuth(master, root['cdn_auth_url_parameters']);
    }
    final title = _optionalText(root['title']);
    return SteamBroadcastRoom(
      steamId: steamId,
      broadcaster: broadcaster,
      title: title.isEmpty ? 'Steam Broadcast' : title,
      game: '',
      cover: '',
      avatar: '',
      currentViewers: _nonNegativeInt(root['num_viewers']),
      state: state,
      master: master,
    );
  }

  static void validateMaster(String source, {required String expectedSteamId, required Uri expectedMaster}) {
    if (source.length > 1024 * 1024 || !source.trimLeft().startsWith('#EXTM3U')) {
      throw const SteamBroadcastException(SteamBroadcastFailure.schema);
    }
    final lines = const LineSplitter().convert(source);
    var variants = 0;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        variants++;
        var next = index + 1;
        while (next < lines.length && lines[next].trim().startsWith('#')) {
          next++;
        }
        if (next >= lines.length || !_validChild(lines[next].trim(), expectedSteamId, expectedMaster.host)) {
          throw const SteamBroadcastException(SteamBroadcastFailure.schema);
        }
      }
      if (line.startsWith('#EXT-X-MEDIA:')) {
        final match = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (match == null || !_validChild(match.group(1)!, expectedSteamId, expectedMaster.host)) {
          throw const SteamBroadcastException(SteamBroadcastFailure.schema);
        }
      }
    }
    if (variants < 1 || variants > 16) throw const SteamBroadcastException(SteamBroadcastFailure.schema);
  }

  static int? parseViewerCount(String text) {
    final match = RegExp(r'^\s*([0-9][0-9,._\s]*)\s+viewers?\b', caseSensitive: false).firstMatch(text);
    final normalized = match?.group(1)?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    if (normalized.isEmpty || normalized.length > 12) return null;
    return int.tryParse(normalized);
  }

  static Uri? _mediaUri(String raw, String steamId) {
    if (raw.length > 8192 || RegExp(r'[\s\x00-\x1f]').hasMatch(raw)) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !_isMediaHost(uri.host) ||
        (uri.hasPort && uri.port != 443)) {
      return null;
    }
    final escapedId = RegExp.escape(steamId);
    final path = RegExp(
      '^/broadcast/$escapedId/[1-9][0-9]{0,19}/hls_manifest/0/([^/]+)/master[.]m3u8\$',
    ).firstMatch(uri.path);
    if (path == null || path.group(1)?.toLowerCase() != uri.host.toLowerCase()) return null;
    if (!_validOrigin(uri.queryParameters['broadcast_origin'])) return null;
    return uri;
  }

  static Uri _appendCdnAuth(Uri uri, Object? value) {
    if (value == null) return uri;
    if (value is! String) throw const SteamBroadcastException(SteamBroadcastFailure.schema);
    var raw = value.trim();
    if (raw.isEmpty) return uri;
    while (raw.startsWith('&') || raw.startsWith('?')) {
      raw = raw.substring(1);
    }
    if (raw.isEmpty || raw.length > 4096 || RegExp(r'[\s#]').hasMatch(raw)) {
      throw const SteamBroadcastException(SteamBroadcastFailure.schema);
    }
    final parsed = Uri(query: raw).queryParametersAll;
    if (parsed.isEmpty || parsed.length > 16 || parsed.containsKey('broadcast_origin')) {
      throw const SteamBroadcastException(SteamBroadcastFailure.schema);
    }
    for (final entry in parsed.entries) {
      if (!RegExp(r'^[A-Za-z0-9_.~-]{1,128}$').hasMatch(entry.key) ||
          entry.value.isEmpty ||
          entry.value.length > 8 ||
          entry.value.any((item) => item.isEmpty || item.length > 2048)) {
        throw const SteamBroadcastException(SteamBroadcastFailure.schema);
      }
    }
    return Uri.parse('${uri.toString()}&$raw');
  }

  static bool _validChild(String raw, String steamId, String host) {
    final uri = Uri.tryParse(raw);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment &&
        uri.host.toLowerCase() == host.toLowerCase() &&
        uri.path.startsWith('/broadcast/$steamId/') &&
        uri.path.contains('/hls_manifest/0/') &&
        _validOrigin(uri.queryParameters['broadcast_origin']);
  }

  static String _image(Object? value, {required String steamId}) {
    final raw = _optionalText(value);
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.host.toLowerCase() != 'steambroadcast.akamaized.net' ||
        !uri.path.startsWith('/broadcast/$steamId/')) {
      return '';
    }
    return uri.toString();
  }

  static String _avatar(Object? value) {
    final raw = _optionalText(value);
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.host.toLowerCase() != 'avatars.akamai.steamstatic.com') {
      return '';
    }
    return uri.toString();
  }

  static bool _isMediaHost(String host) {
    final value = host.toLowerCase();
    return value.endsWith('.steamcontent.com') || value == 'steamcontent.com';
  }

  static bool _validOrigin(String? value) {
    if (value == null || value.length > 255) return false;
    final host = value.toLowerCase();
    return host == 'steamserver.net' || host.endsWith('.steamserver.net');
  }

  static String _stripBroadcastSuffix(String value) =>
      value.replaceFirst(RegExp(r':\s*Broadcast\s*$', caseSensitive: false), '').trim();

  static String _text(Element? element) => element?.text.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';

  static String _firstText(Iterable<Object?> values) {
    for (final value in values) {
      final text = _optionalText(value);
      if (text.isNotEmpty) return text;
    }
    throw const SteamBroadcastException(SteamBroadcastFailure.schema);
  }

  static String _string(Object? value) {
    final result = _optionalText(value);
    if (result.isEmpty) throw const SteamBroadcastException(SteamBroadcastFailure.schema);
    return result;
  }

  static String _optionalText(Object? value) {
    if (value == null) return '';
    if (value is! String || value.length > 65536) {
      throw const SteamBroadcastException(SteamBroadcastFailure.schema);
    }
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static int? _nonNegativeInt(Object? value) {
    if (value == null) return null;
    final parsed = switch (value) {
      int number => number,
      num number when number.isFinite => number.toInt(),
      String text => int.tryParse(text.trim()),
      _ => null,
    };
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map) throw const SteamBroadcastException(SteamBroadcastFailure.schema);
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static void _throwStatus(int status) {
    final failure = switch (status) {
      200 => null,
      400 || 422 => SteamBroadcastFailure.schema,
      401 || 403 => SteamBroadcastFailure.access,
      404 => SteamBroadcastFailure.missing,
      429 => SteamBroadcastFailure.rateLimited,
      >= 500 => SteamBroadcastFailure.service,
      _ => SteamBroadcastFailure.transport,
    };
    if (failure != null) throw SteamBroadcastException(failure);
  }
}

// steam_broadcast_site.dart

final class SteamBroadcastSite {
  SteamBroadcastSite({required SteamBroadcastApi api}) : _api = api;

  final SteamBroadcastApi _api;
  final Map<String, SteamBroadcastRoom> _known = {};

  String get id => 'steambroadcast';

  String get name => 'Steam Broadcasts';

  String get directoryNoticeKey => 'steambroadcast_directory_scope';

  Future<List<LiveCategory>> getCategores(int page, int pageSize) async => page == 1 && pageSize > 0
      ? [
          LiveCategory(
            id: id,
            name: name,
            children: [
              LiveArea(
                platform: id,
                areaType: 'community',
                areaId: 'trending',
                areaName: i18n('steambroadcast_category_trending'),
                typeName: name,
              ),
            ],
          ),
        ]
      : [];

  void _category(LiveArea? category) {
    if (category != null &&
        (category.platform != id || category.areaType != 'community' || category.areaId != 'trending')) {
      throw const SteamBroadcastException(SteamBroadcastFailure.identity);
    }
  }

  void _remember(Iterable<SteamBroadcastRoom> rooms) {
    for (final room in rooms) {
      _known[room.steamId] = room;
    }
  }

  static LiveRoom _room(SteamBroadcastRoom room, {required bool includeMedia}) {
    final viewers = room.currentViewers?.toString();
    final status = switch (room.state) {
      SteamBroadcastState.live => LiveStatus.live,
      SteamBroadcastState.offline => LiveStatus.offline,
      SteamBroadcastState.restricted || SteamBroadcastState.unknown => LiveStatus.unknown,
    };
    return LiveRoom(
      platform: 'steambroadcast',
      roomId: room.steamId,
      userId: room.steamId,
      title: room.title,
      nick: room.broadcaster,
      avatar: room.avatar.isEmpty ? room.cover : room.avatar,
      cover: room.cover,
      area: room.game.isEmpty ? 'Steam Community' : room.game,
      link: SteamBroadcastLink.watchUrl(room.steamId),
      liveStatus: status,
      watching: viewers ?? '',
      onlineViewers: viewers,
      audienceMetricType: viewers == null ? AudienceMetricType.unknown : AudienceMetricType.onlineViewers,
      notice: room.state == SteamBroadcastState.restricted
          ? i18n('steambroadcast_restricted_notice')
          : i18n('steambroadcast_chat_notice'),
      httpHeaders: SteamBroadcastApi.mediaHeaders(room.steamId),
      data: includeMedia ? room : null,
    );
  }

  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    _category(category);
    if (page < 1) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    final result = await _api.directory(page: page, cancel: cancel);
    _remember(result.rooms);
    return LiveDirectoryPage(
      rooms: result.rooms.map((room) => _room(room, includeMedia: false)),
      page: page,
      hasMore: result.hasMore,
    );
  }

  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return [];
    final result = await _api.directory(page: page);
    _remember(result.rooms);
    return result.rooms
        .take(pageSize.clamp(1, 60))
        .map((room) => _room(room, includeMedia: false))
        .toList(growable: false);
  }

  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    _category(category);
    return getRecommendRooms(page: page, pageSize: pageSize);
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
    if (raw.isEmpty || page < 1 || pageSize < 1 || pageSize > 100) return [];
    final steamId = SteamBroadcastLink.parseSteamId(raw);
    if (steamId != null) {
      if (page != 1) return [];
      try {
        return [await _detail(steamId, id, includeMedia: false, cancel: cancel)];
      } on SteamBroadcastException catch (error) {
        if (error.kind == SteamBroadcastFailure.missing) return [];
        rethrow;
      }
    }
    final query = raw.toLowerCase();
    final result = await _api.directory(page: page, cancel: cancel);
    _remember(result.rooms);
    return result.rooms
        .where(
          (room) =>
              room.steamId.contains(query) ||
              room.broadcaster.toLowerCase().contains(query) ||
              room.title.toLowerCase().contains(query) ||
              room.game.toLowerCase().contains(query),
        )
        .take(pageSize)
        .map((room) => _room(room, includeMedia: false))
        .toList(growable: false);
  }

  String _steamId(String roomId, String platform) {
    if (platform.trim().toLowerCase() != id) throw const SteamBroadcastException(SteamBroadcastFailure.identity);
    final value = SteamBroadcastLink.parseSteamId(roomId);
    if (value == null) throw const SteamBroadcastException(SteamBroadcastFailure.identity);
    return value;
  }

  Future<LiveRoom> _detail(String roomId, String platform, {required bool includeMedia, CancelToken? cancel}) async {
    final steamId = _steamId(roomId, platform);
    var room = await _api.room(steamId, includeMedia: includeMedia, cancel: cancel);
    final known = _known[steamId];
    if (known != null) room = room.enrich(known);
    _known[steamId] = room;
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
    if (detail.effectiveLiveStatus == LiveStatus.unknown) {
      throw const SteamBroadcastException(SteamBroadcastFailure.access);
    }
    return detail.isLiveNow;
  }

  SteamBroadcastRoom _snapshot(LiveRoom detail) {
    final steamId = _steamId(detail.roomId ?? '', detail.platform ?? '');
    final room = detail.data;
    if (room is! SteamBroadcastRoom || room.steamId != steamId || room.state != SteamBroadcastState.live) {
      throw const SteamBroadcastException(SteamBroadcastFailure.mediaUnavailable);
    }
    if (room.master == null) throw const SteamBroadcastException(SteamBroadcastFailure.mediaUnavailable);
    return room;
  }

  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    if (detail.isExplicitlyOfflineNow) return const [];
    _snapshot(detail);
    return [LivePlayQuality(id: 'auto', quality: i18n('steambroadcast_quality_auto'))];
  }

  Future<LivePlayUrlResolution> _resolve(LiveRoom detail, LivePlayQuality quality, {required bool refresh}) async {
    var room = _snapshot(detail);
    if (quality.selectionId != 'auto') throw const SteamBroadcastException(SteamBroadcastFailure.schema);
    if (refresh) {
      room = _snapshot(await _detail(room.steamId, id, includeMedia: true));
    }
    return LivePlayUrlResolution(urls: [room.master!.toString()], appliedQualityData: 'auto');
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
