// Writes fixtures/yy/*/expected.json: what 3.x's YY parser makes of each
// recorded sample.
//
// The 3.x app can no longer be built (archived v4, ADR 0016), so its
// `test/fixtures_expected` harness cannot replay these samples the way it did
// for Bilibili and Kuaishou. This file is a line-by-line transcription of the
// parsing in `legacy/lib/core/site/yy/yy_site.dart` (archive/v4) instead:
// every function below keeps the 3.x body and only swaps `HttpClient` for the
// recorded response, decoded the way 3.x's Dio did (JSON content types become
// objects, anything else stays text for `YYSite.decode`). The room and area
// JSON is 3.x's `toJson` projected like `roomProjection` in 3.x's
// `test/fixtures_expected/support.dart`; quality labels use 3.x's
// `LiveQualityLabel` (the branches reachable for `yy`).
//
// Run from the repository root:
//
//   dart run fixtures/yy/legacy_expected.dart
//
// Review the diff of every expected.json before committing it.
// ignore_for_file: avoid_dynamic_calls
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/yy';
const _generatorNote = 'transcribed 3.x parser (fixtures/yy/legacy_expected.dart)';

void main() {
  _header();
  for (final sample in ['S01-category-ent', 'S01-category-game', 'S01-category-other']) {
    _subCategories(sample);
  }
  for (final sample in ['S02-area-page-dance', 'S02-area-page-lol']) {
    _areaPage(sample);
  }
  for (final sample in ['S02-dance-p1', 'S02-dance-p5', 'S02-dance-p6']) {
    _categoryRooms(sample);
  }
  for (final sample in ['S03-recommend-p1', 'S03-recommend-p2', 'S03-recommend-p3']) {
    _recommend(sample);
  }
  for (final sample in ['S04-search-p1', 'S04-search-p50', 'S04-search-empty']) {
    _searchRooms(sample);
  }
  _searchAnchors('S04-search-anchors');
  for (final sample in ['S05-detail-live', 'S05-detail-offline', 'S05-detail-missing']) {
    _detail(sample);
  }
  for (final sample in [
    'S06-streams-g1',
    'S06-streams-g2',
    'S06-streams-g2-l10',
    'S06-streams-g2-l14',
    'S06-streams-g3',
    'S06-streams-offline',
  ]) {
    _streams(sample);
  }
  for (final sample in ['S07-mobile-hls', 'S07-mobile-hls-offline']) {
    _mobileHls(sample);
  }
}

// Samples -------------------------------------------------------------------

final class _Sample {
  _Sample(this.name) : meta = jsonDecode(File('$_root/$name/meta.json').readAsStringSync()) as Map<String, dynamic>;

  final String name;
  final Map<String, dynamic> meta;

  Uri get url => Uri.parse((meta['request'] as Map<String, dynamic>)['url'] as String);

  String get body => File('$_root/$name/${meta['body']}').readAsStringSync();

  Map<String, dynamic>? get requestJson {
    final body = (meta['request'] as Map<String, dynamic>)['body'];
    return body is String ? jsonDecode(body) as Map<String, dynamic> : null;
  }

  String get _contentType {
    final value = ((meta['response'] as Map<String, dynamic>)['headers'] as Map<String, dynamic>)['content-type'];
    return ((value is List ? value.first : value) ?? '').toString().toLowerCase();
  }

  /// What 3.x's `HttpClient.getJson`/`postJson` returned: 3.x's
  /// `CustomTransformer` turned `json;…` into `application/json…`, and Dio
  /// decoded JSON content types; any other body stayed a string.
  dynamic get dioJson {
    final type = _contentType.startsWith('json;') ? 'application/json${_contentType.substring(4)}' : _contentType;
    final mime = type.split(';').first.trim();
    final json = mime == 'application/json' || mime == 'text/json' || mime.endsWith('+json');
    return json ? jsonDecode(body) : body;
  }

  void write(String generator, Object? value) {
    final normalized = jsonDecode(jsonEncode(value));
    File('$_root/$name/expected.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'generator': '$generator; $_generatorNote', 'value': normalized})}\n',
    );
    stdout.writeln('wrote $_root/$name/expected.json');
  }
}

void _header() {
  final sample = _Sample('S01-header');
  final result = YYSite.decode(sample.dioJson);
  final categories = [
    for (final item in result['categoryTabs'] ?? [])
      {'id': item['id'].toString(), 'name': item['title'].toString(), 'children': <Object?>[]},
  ];
  sample.write('YYSite.getCategores (categoryTabs → LiveCategory before its areas are added)', categories);
}

/// Area pages that were recorded, by the URL 3.x requested.
final Map<String, _Sample> _areaPages = {
  for (final name in ['S02-area-page-dance', 'S02-area-page-lol']) _Sample(name).url.toString(): _Sample(name),
};

void _subCategories(String name) {
  final sample = _Sample(name);
  final parentId = sample.url.queryParameters['parentId']!;
  final names = {'1': '娱乐', '2': '游戏', '3': '其他'};
  final site = YYSite();
  final unrecorded = <String>[];
  final areas = site.getSubCategores(LiveCategory(id: parentId, name: names[parentId]!), sample.dioJson, (url) {
    final page = _areaPages[url];
    if (page == null) {
      unrecorded.add(url);
      return null;
    }
    return page.body;
  });
  sample.write(
    'YYSite.getSubCategores (area pages served from S02-area-page-*; an unrecorded area page is treated as one '
    'without pageInfo, so its shortName stays null)',
    {
      'areas': [for (final area in areas) area.toJson()],
      'bizAreaNameMap': site.bizAreaNameMap,
      'unrecordedAreaPages': unrecorded,
    },
  );
}

void _areaPage(String name) {
  final sample = _Sample(name);
  final pageInfo = YYSite.parseCategoryPageInfo(sample.body);
  sample.write('YYSite.parseCategoryPageInfo (+ the shortName getSubCategores stores)', {
    'parseCategoryPageInfo': pageInfo,
    'shortName': pageInfo == null ? null : json.encode(pageInfo),
  });
}

void _categoryRooms(String name) {
  final sample = _Sample(name);
  final query = sample.url.queryParameters;
  final shortName = json.encode(YYSite.parseCategoryPageInfo(_Sample('S02-area-page-dance').body));
  final area = LiveArea(areaId: '4', areaName: '舞蹈', areaType: '1', platform: 'yy', shortName: shortName);
  final built = YYSite.categoryRoomsQuery(area, page: int.parse(query['page']!), pageSize: 30);
  sample.write('YYSite.getCategoryRooms (area 舞蹈 with the shortName of S02-area-page-dance)', {
    'query': {for (final entry in built.entries) entry.key: '${entry.value}'},
    'rooms': [for (final room in YYSite().getCategoryRooms(area, sample.dioJson)) roomProjection(room)],
  });
}

void _recommend(String name) {
  final sample = _Sample(name);
  final page = int.parse(sample.url.queryParameters['page']!);
  sample.write('YYSite.getRecommendRooms (fresh site: bizAreaNameMap empty)', {
    'query': {for (final entry in YYSite.recommendQuery(page: page, pageSize: 30).entries) entry.key: '${entry.value}'},
    'rooms': [for (final room in YYSite().getRecommendRooms(sample.dioJson)) roomProjection(room)],
  });
}

void _searchRooms(String name) {
  final sample = _Sample(name);
  final query = sample.url.queryParameters;
  sample.write('YYSite.searchRooms (fresh site: bizAreaNameMap empty)', {
    'query': {
      for (final entry in YYSite.searchQuery(query['q']!, t: '120', page: int.parse(query['n']!)).entries)
        entry.key: '${entry.value}',
    },
    'rooms': [for (final room in YYSite().searchRooms(sample.dioJson)) roomProjection(room)],
  });
}

void _searchAnchors(String name) {
  final sample = _Sample(name);
  final query = sample.url.queryParameters;
  sample.write('YYSite.searchAnchors', {
    'query': {
      for (final entry in YYSite.searchQuery(query['q']!, t: '1', page: int.parse(query['n']!)).entries)
        entry.key: '${entry.value}',
    },
    'anchors': [for (final anchor in YYSite().searchAnchors(sample.dioJson)) anchor.toJson()],
  });
}

void _detail(String name) {
  final sample = _Sample(name);
  final roomId = sample.url.pathSegments[2];
  Object? outcome;
  try {
    outcome = roomProjection(YYSite().fetchRoomDetail(platform: 'yy', roomId: roomId, response: sample.dioJson));
  } on Object catch (error) {
    outcome = {'throws': error.runtimeType.toString(), 'message': error.toString()};
  }
  sample.write('YYSite._fetchRoomDetail (getRoomDetail, getRoomDetailForRefresh, getRoomDetailForRecording)', {
    'roomId': roomId,
    'room': outcome,
  });
}

void _streams(String name) {
  final sample = _Sample(name);
  final payload = YYSite.decode(sample.dioJson);
  final avp = sample.requestJson!['avp_parameter'] as Map<String, dynamic>;
  sample.write('YYSite.parsePlayQualities + parsePlayUrls (the 3.x request was form-encoded; see M4.06)', {
    'requestedGear': avp['gear'],
    'requestedLine': avp['line_seq'],
    'parsePlayQualities': [for (final quality in YYSite.parsePlayQualities(payload)) quality.toJson()],
    'parsePlayUrls': YYSite.parsePlayUrls(payload),
  });
}

void _mobileHls(String name) {
  final sample = _Sample(name);
  final rate = sample.url.pathSegments.last;
  final payload = YYSite.parseMobileHlsPayload(sample.body);
  // `_getMobileHlsQualities` asks for 1200 and 4000; only this rate was
  // recorded, the other is taken as failed (3.x logged and skipped it).
  final qualities = YYSite.mobileHlsQualities([
    for (final wanted in YYSite._mobileHlsRates) (rate: wanted, payload: wanted == rate ? payload : null),
  ]);
  final url = payload?['hls']?.toString().trim() ?? '';
  sample.write('YYSite.parseMobileHlsPayload + _getMobileHlsQualities (only rate $rate answered) + getPlayUrls', {
    'parseMobileHlsPayload': payload,
    'mobileQualities': [for (final quality in qualities) quality.toJson()],
    'getPlayUrls': url.isEmpty ? <String>[] : <String>[url],
  });
}

// 3.x models (legacy/lib/common/models/live_room.dart, live_area.dart,
// model/live_play_quality.dart, live_anchor_item.dart), reduced to the fields
// the YY adapter writes -------------------------------------------------------

enum LiveStatus { live, offline, replay, unknown, banned }

enum AudienceMetricType { popularity, onlineViewers, totalViewers, followers, unknown }

final class LiveRoom {
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
    this.platform,
    LiveStatus? liveStatus,
    this.danmakuData,
    this.status = false,
  }) : liveStatus = liveStatus ?? (status == true ? LiveStatus.live : LiveStatus.offline);

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
  String? platform;
  LiveStatus? liveStatus;
  Object? danmakuData;
  bool? status;

  bool get isLiveNow => liveStatus == LiveStatus.live;

  /// 3.x's `effectiveAudienceMetricType` for YY rooms.
  AudienceMetricType get effectiveAudienceMetricType =>
      audienceMetricType != null && audienceMetricType != AudienceMetricType.unknown
      ? audienceMetricType!
      : AudienceMetricType.popularity;

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
    'onlineViewers': '',
    'totalViewers': '',
    'followers': '0',
    'platform': platform,
    'tagIds': <String>[],
    'liveStatus': liveStatus!.index,
    'isRecord': false,
    'status': isLiveNow,
    'notice': null,
    'introduction': null,
    'epgId': null,
    'currentProgramme': null,
    'currentProgrammeDescription': null,
    'catchUpUrl': null,
    'isCatchUp': false,
    'catchUpStart': null,
    'catchUpEnd': null,
    'catchUpMode': null,
    'catchUpSource': null,
    'catchUpDays': null,
    'catchUpCorrectionHours': null,
    'httpHeaders': <String, String>{},
    'lastWatchedAt': null,
  };
}

/// 3.x's `roomProjection` (test/fixtures_expected/support.dart).
Map<String, dynamic> roomProjection(LiveRoom room) {
  final json = room.toJson()
    ..['link'] = room.link
    ..['danmakuData'] = room.danmakuData?.toString();
  json.removeWhere(
    (key, value) => value == null || (value is Map && value.isEmpty) || (value is List && value.isEmpty),
  );
  return json;
}

final class LiveArea {
  LiveArea({this.platform, this.areaType, this.typeName, this.areaId, this.areaName, this.areaPic, this.shortName});

  String? platform = '';
  String? areaType = '';
  String? typeName = '';
  String? areaId = '';
  String? areaName = '';
  String? areaPic = '';
  String? shortName = '';

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

final class LiveCategory {
  LiveCategory({required this.id, required this.name});

  final String id;
  final String name;
}

final class LivePlayQuality {
  LivePlayQuality({required this.quality, this.data, this.id, this.sort = 0});

  final String quality;
  final dynamic data;
  final Object? id;
  final int sort;

  Map<String, dynamic> toJson() => {'quality': quality, 'id': id, 'sort': sort, 'data': data};
}

final class LiveAnchorItem {
  LiveAnchorItem({required this.roomId, required this.avatar, required this.userName, required this.liveStatus});

  final String roomId;
  final String avatar;
  final String userName;
  final bool liveStatus;

  Map<String, dynamic> toJson() => {'roomId': roomId, 'avatar': avatar, 'userName': userName, 'liveStatus': liveStatus};
}

/// 3.x's `YyDanmakuArgs` (legacy/lib/core/danmaku/yy_danmaku.dart:13-23).
final class YyDanmakuArgs {
  YyDanmakuArgs({required this.topSid, required this.subSid});

  final int topSid;
  final int subSid;

  @override
  String toString() => json.encode({'topSid': topSid, 'subSid': subSid});
}

/// 3.x's `LiveQualityLabel.normalize` (legacy/lib/core/utils/live_quality_label.dart)
/// for `platform: 'yy'`.
String normalizeQualityLabel({required String rawLabel, Object? id, int? bitrate, String? resolution}) {
  final raw = rawLabel.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (RegExp(r'[㐀-鿿]').hasMatch(raw)) return raw;
  final token = (raw.isNotEmpty ? raw : id?.toString() ?? '').toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '');
  final mapped = switch (token) {
    'original' || 'origin' || 'origion' || 'source' => '原画',
    'blue' || 'bluray' || 'blueray' => '蓝光',
    'uhd' || 'super' || 'superhd' || 'fullhd' || 'fhd' => '超清',
    'hd' || 'high' => '高清',
    'sd' || 'standard' || 'medium' => '标清',
    'low' || 'ld' || 'smooth' || 'fluent' => '流畅',
    'auto' => '自动',
    'default' => '默认',
    _ => null,
  };
  if (mapped != null) return mapped;
  if (raw.isNotEmpty) return raw;
  if (bitrate != null && bitrate > 0) {
    if (bitrate >= 1000000) {
      final mbps = bitrate / 1000000;
      return '${mbps.toStringAsFixed(mbps == mbps.roundToDouble() ? 0 : 1)} Mbps';
    }
    return '${(bitrate / 1000).round()} Kbps';
  }
  final idText = id?.toString().trim() ?? '';
  return idText.isEmpty ? '默认' : '清晰度 $idText';
}

// 3.x's YYSite (legacy/lib/core/site/yy/yy_site.dart) -------------------------
//
// Each method keeps the 3.x body; a response parameter replaces the awaited
// HttpClient call on the marked line.

final class YYSite {
  static const List<String> _mobileHlsRates = <String>['1200', '4000'];
  static const String _mobileHlsPrefix = 'mobile-hls:';

  // site:72-86
  String validImgUrl(String imgUrl) {
    if (imgUrl.isEmpty) {
      return '';
    }
    if (imgUrl.startsWith('//')) {
      return 'https:$imgUrl';
    }
    if (imgUrl.startsWith('http://')) {
      return 'https://${imgUrl.substring(7)}';
    }
    return imgUrl;
  }

  // site:88-93
  static dynamic decode(dynamic data) {
    if (data is String) {
      return json.decode(data);
    }
    return data;
  }

  // site:95-98
  static int? _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  // site:100-105
  static bool isLiveValue(dynamic value) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'live';
  }

  // site:107-120
  static Map<String, dynamic>? parseCategoryPageInfo(String html) {
    final source = RegExp(r'pageInfo\s*=\s*(\{[\s\S]*?\})\s*;', multiLine: true).firstMatch(html)?.group(1);
    if (source == null) return null;

    final moduleId = int.tryParse(RegExp(r'''moduleId\s*:\s*['"]?(-?\d+)''').firstMatch(source)?.group(1) ?? '');
    final biz = RegExp(r'''biz\s*:\s*['"]([^'"]+)''').firstMatch(source)?.group(1)?.trim() ?? '';
    final subBiz = RegExp(r'''subBiz\s*:\s*['"]([^'"]+)''').firstMatch(source)?.group(1)?.trim() ?? '';
    if (moduleId == null || biz.isEmpty || subBiz.isEmpty) return null;
    return <String, dynamic>{'moduleId': moduleId, 'biz': biz, 'subBiz': subBiz};
  }

  // site:122-128
  static String normalizeWebUrl(String value) {
    final url = value.trim();
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('http://')) return 'https://${url.substring(7)}';
    return url;
  }

  // site:180-214; [response] is the getCategory.action answer, [areaPage]
  // the getText of an area page (null: the page has no pageInfo).
  List<LiveArea> getSubCategores(LiveCategory liveCategory, dynamic response, String? Function(String url) areaPage) {
    final resultText = response;
    final result = decode(resultText);
    final List<LiveArea> subs = [];
    for (final item in result['data'] ?? []) {
      final subCategory = LiveArea(
        areaId: item['id'].toString(),
        areaName: item['title']?.toString() ?? '',
        areaType: liveCategory.id,
        platform: 'yy',
        areaPic: item['cover']?.toString() ?? '',
        typeName: liveCategory.name,
      );
      final url = normalizeWebUrl(item['url']?.toString() ?? '');
      if (url.isEmpty) {
        subs.add(subCategory);
        continue;
      }
      final resultText = areaPage(url); // HttpClient.instance.getText(url, …)
      final pageInfo = resultText == null ? null : parseCategoryPageInfo(resultText);
      if (pageInfo != null) {
        subCategory.shortName = json.encode(pageInfo);
        final biz = pageInfo['biz']?.toString() ?? '';
        if (biz.isNotEmpty) bizAreaNameMap.putIfAbsent(biz, () => subCategory.areaName ?? biz);
      }

      subs.add(subCategory);
    }

    return subs;
  }

  // site:224-234: the query of getCategoryRooms.
  static Map<String, dynamic> categoryRoomsQuery(LiveArea category, {required int page, required int pageSize}) {
    final requestPageSize = pageSize;
    final shortName = category.shortName ?? '{}';
    final decodeShortName = decode(shortName) as Map;
    final Map<String, dynamic> queryParameters = {'page': page, 'pageSize': requestPageSize};
    for (final key in decodeShortName.keys) {
      queryParameters[key.toString()] = decodeShortName[key];
    }
    return queryParameters;
  }

  // site:236-271
  List<LiveRoom> getCategoryRooms(LiveArea category, dynamic response) {
    final resultText = response; // HttpClient.instance.getJson('https://www.yy.com/more/page.action', …)
    final result = decode(resultText);
    final List<LiveRoom> items = [];
    final data = result['data']?['data'] ?? [];
    for (final item in data) {
      final users = item['users']?.toString() ?? '';
      items.add(
        LiveRoom(
          roomId: item['sid']?.toString() ?? '',
          title: item['desc']?.toString() ?? '',
          cover: validImgUrl(item['thumb2']?.toString() ?? ''),
          nick: item['name']?.toString() ?? '',
          userId: item['uid']?.toString() ?? '',
          watching: users,
          popularity: users,
          audienceMetricType: AudienceMetricType.popularity,
          avatar: validImgUrl(item['avatar']?.toString() ?? ''),
          area: category.areaName,
          liveStatus: LiveStatus.live,
          status: true,
          platform: 'yy',
        ),
      );
    }
    return items;
  }

  // site:358-375
  static Map<String, dynamic>? parseMobileHlsPayload(String payload) {
    final source = payload.trim();
    final jsonStart = source.indexOf('{');
    final jsonEnd = source.lastIndexOf('}');
    if (jsonStart < 0 || jsonEnd < jsonStart) return null;
    try {
      final value = json.decode(source.substring(jsonStart, jsonEnd + 1));
      if (value is! Map || _asInt(value['code']) != 0) return null;
      final url = value['hls']?.toString().trim() ?? '';
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme || !const {'http', 'https'}.contains(uri.scheme)) return null;
      return Map<String, dynamic>.from(value);
    } on Object {
      return null;
    }
  }

  // site:405-429 (the loop of _getMobileHlsQualities over the answers)
  static List<LivePlayQuality> mobileHlsQualities(List<({String rate, Map<String, dynamic>? payload})> responses) {
    final byStream = <String, LivePlayQuality>{};
    for (final response in responses) {
      final payload = response.payload;
      if (payload == null) continue;
      final width = _asInt(payload['width']) ?? 0;
      final height = _asInt(payload['height']) ?? 0;
      final shortEdge = width > 0 && height > 0 ? (width < height ? width : height) : 0;
      final streamKey = payload['video']?.toString().trim();
      final identity = streamKey?.isNotEmpty == true ? streamKey! : '${width}x$height';
      final rate = int.tryParse(response.rate) ?? 0;
      final tier = response.rate == _mobileHlsRates.first ? '流畅' : '高清';
      final resolution = shortEdge > 0 ? ' · ${shortEdge}p' : '';
      byStream[identity] = LivePlayQuality(
        quality: '$tier$resolution',
        id: '$_mobileHlsPrefix${response.rate}',
        sort: rate,
        data: '$_mobileHlsPrefix${response.rate}',
      );
    }
    final qualities = byStream.values.toList(growable: false);
    qualities.sort((left, right) => right.sort.compareTo(left.sort));
    return qualities;
  }

  // site:450-496
  static List<LivePlayQuality> parsePlayQualities(dynamic payload) {
    final channelStreamInfo = payload is Map ? payload['channel_stream_info'] : null;
    final streams = channelStreamInfo is Map ? channelStreamInfo['streams'] : null;
    if (streams is! List) return const <LivePlayQuality>[];

    final records = <({String name, String gear, int rate})>[];
    final seenGears = <String>{};
    for (final stream in streams.whereType<Map>()) {
      final jsonText = stream['json']?.toString().trim() ?? '';
      if (jsonText.isEmpty) continue;
      try {
        final decoded = json.decode(jsonText);
        final gearInfo = decoded is Map ? decoded['gear_info'] : null;
        if (gearInfo is! Map) continue;
        final name = gearInfo['name']?.toString().trim() ?? '';
        final gear = gearInfo['gear']?.toString().trim() ?? '';
        final rate = int.tryParse(decoded['rate']?.toString() ?? '') ?? 0;
        if (name.isEmpty || gear.isEmpty || !seenGears.add(gear)) continue;
        records.add((name: name, gear: gear, rate: rate));
      } on Object {
        // CoreLog.error('YY parse quality error: $error');
      }
    }

    final nameCounts = <String, int>{};
    for (final record in records) {
      nameCounts.update(record.name, (count) => count + 1, ifAbsent: () => 1);
    }
    final qualities = records
        .map(
          (record) => LivePlayQuality(
            quality: normalizeQualityLabel(
              rawLabel: nameCounts[record.name] == 1 ? record.name : '${record.name} · ${record.gear}',
              id: record.gear,
              bitrate: record.rate > 0 ? record.rate * 1000 : null,
            ),
            id: record.gear,
            sort: record.rate,
            data: record.gear,
          ),
        )
        .toList(growable: false);
    qualities.sort((left, right) => right.sort.compareTo(left.sort));
    return qualities;
  }

  // site:529-548
  static List<String> parsePlayUrls(dynamic payload) {
    final avpInfoRes = payload is Map ? payload['avp_info_res'] : null;
    final streamLineAddr = avpInfoRes is Map ? avpInfoRes['stream_line_addr'] : null;
    if (streamLineAddr is! Map) return const <String>[];

    final urls = <String>[];
    for (final value in streamLineAddr.values.whereType<Map>()) {
      final cdnInfo = value['cdn_info'];
      if (cdnInfo is! Map) continue;
      var url = cdnInfo['url']?.toString().trim() ?? '';
      if (url.startsWith('//')) url = 'https:$url';
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme || !const {'http', 'https'}.contains(uri.scheme) || urls.contains(url)) {
        continue;
      }
      urls.add(url);
    }
    return urls;
  }

  // site:556-559: the query of getRecommendRooms.
  static Map<String, dynamic> recommendQuery({required int page, required int pageSize}) => {
    'page': page,
    'pageSize': pageSize,
    'biz': 'other',
    'subBiz': 'idx',
    'moduleId': '-1',
  };

  // site:554-591
  List<LiveRoom> getRecommendRooms(dynamic response) {
    final resultText = response; // HttpClient.instance.getJson('https://www.yy.com/more/page.action', …)
    final result = decode(resultText);
    final List<LiveRoom> items = [];
    final data = result['data']?['data'] ?? [];
    for (final item in data) {
      final users = item['users']?.toString() ?? '';
      final biz = item['biz']?.toString() ?? '';
      final area = bizAreaNameMap[biz] ?? biz;
      items.add(
        LiveRoom(
          roomId: item['sid']?.toString() ?? '',
          title: item['desc']?.toString() ?? '',
          cover: validImgUrl(item['thumb2']?.toString() ?? ''),
          nick: item['name']?.toString() ?? '',
          userId: item['uid']?.toString() ?? '',
          watching: users,
          popularity: users,
          audienceMetricType: AudienceMetricType.popularity,
          avatar: validImgUrl(item['avatar']?.toString() ?? ''),
          area: area,
          liveStatus: LiveStatus.live,
          status: true,
          platform: 'yy',
        ),
      );
    }
    return items;
  }

  // site:597
  final Map<String, String> bizAreaNameMap = {};

  // site:665-701
  LiveRoom fetchRoomDetail({required String platform, required String roomId, required dynamic response}) {
    final decoded = decode(
      response,
    ); // HttpClient.instance.getJson('https://www.yy.com/api/liveInfoDetail/$roomId/$roomId/0')
    final resultCode = decoded is Map ? int.tryParse(decoded['resultCode']?.toString() ?? '') : null;
    if (decoded is! Map || resultCode != 0) {
      throw const FormatException('YY room detail response is invalid');
    }
    final rawItem = decoded['data'];
    if (rawItem is! Map) {
      return LiveRoom(roomId: roomId, platform: platform, status: false, liveStatus: LiveStatus.offline);
    }
    final item = Map<String, dynamic>.from(rawItem);
    final topSid = _asInt(item['sid']) ?? _asInt(roomId) ?? 0;
    final subSid = _asInt(item['ssid']) ?? topSid;
    final biz = item['biz']?.toString() ?? '';
    return LiveRoom(
      roomId: item['sid']?.toString() ?? roomId,
      title: item['desc']?.toString() ?? '',
      cover: validImgUrl(item['thumb2']?.toString() ?? ''),
      nick: item['name']?.toString() ?? '',
      userId: item['uid']?.toString() ?? '',
      watching: item['users']?.toString() ?? '',
      popularity: item['users']?.toString() ?? '',
      audienceMetricType: AudienceMetricType.popularity,
      avatar: validImgUrl(item['avatar']?.toString() ?? ''),
      area: bizAreaNameMap[biz] ?? biz,
      liveStatus: LiveStatus.live,
      status: true,
      platform: 'yy',
      danmakuData: YyDanmakuArgs(topSid: topSid, subSid: subSid),
      link: 'https://www.yy.com/$roomId',
    );
  }

  // site:709-713 and 755-759: the query of searchRooms (t=120) and
  // searchAnchors (t=1).
  static Map<String, dynamic> searchQuery(String keyword, {required String t, required int page}) => {
    'q': keyword,
    't': t,
    'n': page,
  };

  // site:707-747
  List<LiveRoom> searchRooms(dynamic response) {
    final resultText = response; // HttpClient.instance.getJson('https://www.yy.com/apiSearch/doSearch.json', …)
    final result = decode(resultText);
    final List<LiveRoom> items = [];
    final docs = result['data']?['searchResult']?['response']?['120']?['docs'] ?? [];
    for (final item in docs) {
      final users = item['users']?.toString() ?? '';
      final roomId = item['sid']?.toString() ?? '';
      final isLive = isLiveValue(item['liveOn']);
      items.add(
        LiveRoom(
          roomId: roomId,
          title: item['channelName']?.toString() ?? '',
          cover: validImgUrl(item['posterurl']?.toString() ?? ''),
          nick: item['name']?.toString() ?? '',
          userId: item['uid']?.toString() ?? '',
          watching: users,
          popularity: users,
          audienceMetricType: AudienceMetricType.popularity,
          avatar: validImgUrl(item['headurl']?.toString() ?? ''),
          area: bizAreaNameMap[item['biz']?.toString() ?? ''] ?? item['biz']?.toString() ?? '',
          liveStatus: isLive ? LiveStatus.live : LiveStatus.offline,
          status: isLive,
          platform: 'yy',
          link: 'https://www.yy.com/$roomId',
        ),
      );
    }
    return items;
  }

  // site:753-779
  List<LiveAnchorItem> searchAnchors(dynamic response) {
    final resultText = response; // HttpClient.instance.getJson('https://www.yy.com/apiSearch/doSearch.json', …)
    final result = decode(resultText);
    final List<LiveAnchorItem> items = [];
    final docs = result['data']?['searchResult']?['response']?['1']?['docs'] ?? [];
    for (final item in docs) {
      items.add(
        LiveAnchorItem(
          roomId: item['sid']?.toString() ?? item['ssid']?.toString() ?? '',
          avatar: validImgUrl(item['headurl']?.toString() ?? ''),
          userName: item['name']?.toString() ?? item['stageName']?.toString() ?? '',
          liveStatus: isLiveValue(item['liveOn']),
        ),
      );
    }
    return items;
  }
}
