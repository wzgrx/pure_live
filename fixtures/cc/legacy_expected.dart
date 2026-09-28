// Writes expected.json for the CC samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.09-cc.md, "样本与 v3 的冻结输出").
//
// The archive has no CC expected.json (its legacy harness only covered five
// platforms, and 3.x no longer builds). The parsing below is 3.x's code,
// copied from legacy/lib/core/site/cc/cc_site.dart and cc_catalog.dart
// (archive/v4) with only the transport replaced: `_getJson` answers from the
// samples by host and path, like the legacy FixtureAdapter, and throws a
// StateError for a request without a sample. `_LegacyRoom` is the part of
// 3.x's LiveRoom (legacy/lib/common/models/live_room.dart) these parsers
// use: constructor defaults, copyWith, getLiveRoomWithError and toJson.
// The output format is the legacy harness's (`roomProjection`,
// `errorProjection`, `{generator, value}`).
//
// Run from the repository root: dart run fixtures/cc/legacy_expected.dart
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/cc';

void main() {
  _catalog();
  for (final (sample, page) in [
    ('S02-area-page1', 1),
    ('S02-area-beyond', 2),
  ]) {
    _categoryRooms(sample, '9141', page);
  }
  _categoryRooms('S02-area-empty', '65005', 1);
  for (final (sample, page) in [
    ('S03-live-page1', 1),
    ('S03-live-last', 4),
    ('S03-live-beyond', 11),
  ]) {
    _recommend(sample, page);
  }
  for (final sample in [
    'S04-search-page1',
    'S04-search-empty',
    'S04-search-beyond',
  ]) {
    _search(sample);
  }
  _detail('S05-channel-live', [
    'S05-lives-live',
    'S05-channel-live',
  ], '341438909');
  _detail('S05-channel-replay', [
    'S05-lives-replay',
    'S05-channel-replay',
  ], '732923115');
  _detail('S05-lives-offline', [
    'S05-lives-offline',
    'S05-channel-null',
  ], '376267758');
  _detail('S05-lives-missing', [
    'S05-lives-missing',
    'S05-channel-null',
  ], '88888888888');
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync())
        as Map<String, dynamic>;

Object? _getJson(String url, {Map<String, dynamic>? queryParameters}) {
  final uri = Uri.parse(url);
  for (final meta in _samples) {
    final recorded = Uri.parse((meta['request'] as Map)['url'] as String);
    if (recorded.host == uri.host && recorded.path == uri.path) {
      return jsonDecode(
        File('$_root/${meta['sample']}/${meta['body']}').readAsStringSync(),
      );
    }
  }
  throw StateError(
    'No recorded sample for GET ${uri.replace(queryParameters: queryParameters)}',
  );
}

Object? _postJson(String url, {Object? data}) => _getJson(url);

void _replay(List<String> samples) =>
    _samples = [for (final sample in samples) _meta(sample)];

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
    NoSuchMethodError() => 'NoSuchMethodError',
    _ => error.runtimeType.toString(),
  },
  'message': error.toString(),
};

Object? _outcome<T>(T Function() body, Object? Function(T value) project) {
  try {
    return project(body());
  } on Object catch (error) {
    return _errorProjection(error);
  }
}

Map<String, dynamic> _roomProjection(_LegacyRoom room) {
  final json = room.toJson()
    ..['link'] = room.link
    ..['danmakuData'] = room.danmakuData?.toString();
  json.removeWhere(
    (key, value) =>
        value == null ||
        (value is Map && value.isEmpty) ||
        (value is List && value.isEmpty),
  );
  return json;
}

// Samples ---------------------------------------------------------------------

void _catalog() {
  _replay(['S01-dashen-games', 'S01-dashen-config']);
  _write(
    'S01-dashen-config',
    'CCSite.getCategores (with S01-dashen-games)',
    _outcome(
      () => CCCatalog.parse(
        _getJson(
          'https://inf.ds.163.com/v1/web/game-center/basic/base-info-list/by-type',
          queryParameters: {'gameType': 'NETEASE'},
        ),
        _postJson(
          'https://inf-act.ds.163.com/v1/act-web/pageConf/commonAppConfig',
          data: {'id': CCCatalog.configurationId},
        ),
      ),
      (categories) => [
        for (final category in categories)
          {
            'id': category.id,
            'name': category.name,
            'children': [for (final area in category.children) area.toJson()],
          },
      ],
    ),
  );
}

void _categoryRooms(String sample, String game, int page) {
  _replay([sample]);
  final area = _LegacyArea(platform: 'cc', areaId: game, areaType: '1');
  _write(
    sample,
    'CCSite.getCategoryRooms + _CCCategoryDirectory.hasMore',
    _outcome(
      () => CCSite().getCategoryRooms(area, page: page, pageSize: 30),
      (rooms) => {
        'rooms': [for (final room in rooms) _roomProjection(room)],
        'hasMore': rooms.length == 30,
      },
    ),
  );
}

void _recommend(String sample, int page) {
  _replay([sample]);
  _write(
    sample,
    'CCSite.getRecommendRooms',
    _outcome(
      () => CCSite().getRecommendRooms(page: page, pageSize: 30),
      (rooms) => {
        'rooms': [for (final room in rooms) _roomProjection(room)],
      },
    ),
  );
}

void _search(String sample) {
  _replay([sample]);
  final query = Uri.parse((_meta(sample)['request'] as Map)['url'] as String)
      .queryParameters;
  final keyword = query['query']!;
  final page = int.parse(query['page']!);
  final size = int.parse(query['size']!);
  _write(sample, 'CCSite.searchRooms + searchAnchors', {
    'searchRooms': _outcome(
      () => CCSite().searchRooms(keyword, page: page, pageSize: size),
      (rooms) => [for (final room in rooms) _roomProjection(room)],
    ),
    'searchAnchors': _outcome(
      () => CCSite().searchAnchors(keyword, page: page, pageSize: size),
      (anchors) => [
        for (final anchor in anchors)
          {
            'roomId': anchor.roomId,
            'avatar': anchor.avatar,
            'userName': anchor.userName,
            'liveStatus': anchor.liveStatus,
          },
      ],
    ),
  });
}

void _detail(String sample, List<String> samples, String roomId) {
  _replay(samples);
  final site = CCSite();
  final value = <String, Object?>{
    'getRoomDetailForRefresh': _outcome(
      () => site.getRoomDetailForRefresh(platform: 'cc', roomId: roomId),
      _roomProjection,
    ),
    'getRoomDetail': _roomProjection(
      site.getRoomDetail(platform: 'cc', roomId: roomId),
    ),
  };
  final detail = site.getRoomDetail(platform: 'cc', roomId: roomId);
  final qualities = site.getPlayQualites(detail: detail);
  value['getPlayQualites'] = [
    for (final quality in qualities)
      {
        'quality': quality.quality,
        'id': quality.id,
        'sort': quality.sort,
        'getPlayUrls': site.getPlayUrls(detail: detail, quality: quality),
      },
  ];
  _write(
    sample,
    'CCSite.getRoomDetailForRefresh + getRoomDetail + getPlayQualites + getPlayUrls',
    value,
  );
}

// 3.x models (the parts the CC parsers use) -------------------------------------

enum LiveStatus { live, offline, replay, unknown, banned }

enum AudienceMetricType {
  popularity,
  onlineViewers,
  totalViewers,
  followers,
  unknown,
}

class _LegacyArea {
  _LegacyArea({
    this.platform,
    this.areaType,
    this.typeName,
    this.areaId,
    this.areaName,
    this.areaPic,
  });

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

class _LegacyCategory {
  _LegacyCategory({
    required this.id,
    required this.name,
    required this.children,
  });

  final String name;
  final String id;
  final List<_LegacyArea> children;
}

class _LegacyAnchor {
  _LegacyAnchor({
    required this.roomId,
    required this.avatar,
    required this.userName,
    required this.liveStatus,
  });

  final String roomId;
  final String avatar;
  final String userName;
  final bool liveStatus;
}

class _LegacyQuality {
  _LegacyQuality({required this.quality, this.data, this.id, this.sort = 0});

  final String quality;
  final dynamic data;
  final Object? id;
  final int sort;
}

class _LegacyRoom {
  _LegacyRoom({
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
  }) : liveStatus =
           liveStatus ??
           _legacyStatusToLiveStatus(status: status, isRecord: isRecord);

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

  static LiveStatus? _legacyStatusToLiveStatus({
    required bool? status,
    required bool? isRecord,
  }) {
    if (isRecord == true) return LiveStatus.replay;
    if (status == true) return LiveStatus.live;
    if (status == false) return LiveStatus.offline;
    return null;
  }

  String get normalizedPlatformId => (platform ?? '').trim().toLowerCase();

  LiveStatus get effectiveLiveStatus {
    if (isRecord == true || liveStatus == LiveStatus.replay)
      return LiveStatus.replay;
    final canonical = liveStatus;
    if (canonical != null) return canonical;
    return _legacyStatusToLiveStatus(status: status, isRecord: isRecord) ??
        LiveStatus.unknown;
  }

  bool get isLiveNow => effectiveLiveStatus == LiveStatus.live;

  AudienceMetricType get effectiveAudienceMetricType {
    if (audienceMetricType != null &&
        audienceMetricType != AudienceMetricType.unknown)
      return audienceMetricType!;
    return switch (normalizedPlatformId) {
      'bilibili' ||
      'douyu' ||
      'huya' ||
      'cc' ||
      'yy' ||
      'missevan' => AudienceMetricType.popularity,
      'kuaishou' || 'twitch' || 'soop' => AudienceMetricType.onlineViewers,
      'douyin' => AudienceMetricType.totalViewers,
      _ => AudienceMetricType.unknown,
    };
  }

  _LegacyRoom copyWith({
    String? watching,
    bool? status,
    bool? isRecord,
    LiveStatus? liveStatus,
  }) => _LegacyRoom(
    roomId: roomId,
    userId: userId,
    link: link,
    title: title,
    nick: nick,
    avatar: avatar,
    cover: cover,
    area: area,
    watching: watching ?? this.watching,
    audienceMetricType: audienceMetricType,
    popularity: popularity,
    onlineViewers: onlineViewers,
    totalViewers: totalViewers,
    followers: followers,
    platform: platform,
    introduction: introduction,
    notice: notice,
    status: status ?? this.status,
    data: data,
    danmakuData: danmakuData,
    isRecord: isRecord ?? this.isRecord,
    liveStatus: liveStatus ?? this.liveStatus,
  );

  _LegacyRoom getLiveRoomWithError() => copyWith(
    liveStatus: LiveStatus.unknown,
    status: false,
    isRecord: false,
    watching: (watching ?? '').trim() == '0' ? '' : watching,
  );

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
    'httpHeaders': <String, String>{},
  };
}

/// 3.x's LiveQualityLabel.normalize for the CC path (the raw label is always
/// Chinese or the tier key there).
String _qualityLabel({required String rawLabel, Object? id, int? bitrate}) {
  final raw = rawLabel.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (RegExp(r'[㐀-鿿]').hasMatch(raw)) return raw;
  final token = (raw.isNotEmpty ? raw : id?.toString() ?? '')
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '');
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
  final idText = id?.toString().trim() ?? '';
  return idText.isEmpty ? '默认' : '清晰度 $idText';
}

// 3.x's CC parsers (legacy/lib/core/site/cc/cc_catalog.dart) -----------------

class CCCatalog {
  static const configurationId = '67b32cdd1801fc391a6c2657';

  static List<_LegacyCategory> parse(
    Object? gamePayload,
    Object? configPayload, {
    String categoryLabel = '直播分类',
    String officialLabel = '官方房间/专题',
  }) {
    final gameRows = _list(_envelope(gamePayload)['result'], 2000);
    final metadata = <String, Map>{};
    for (final raw in gameRows) {
      final row = _map(raw);
      final key = _text(row['appKey'], 64);
      if (metadata.containsKey(key))
        throw const FormatException('Duplicate CC game key');
      metadata[key] = row;
    }
    final config = _map(_envelope(configPayload)['result']);
    if (config['id'] != configurationId)
      throw const FormatException('Mismatched CC configuration');
    if (_hidden(config)) return [];
    final groups = _list(
      config['itemList'],
      256,
    ).map(_map).where((row) => row['name'] == '直播入口列表').toList();
    if (groups.length != 1)
      throw const FormatException('Missing or ambiguous CC live entry group');
    if (_hidden(groups.single)) return [];

    final categories = <_LegacyArea>[];
    final official = <_LegacyArea>[];
    final identities = <String>{};
    for (final raw in _list(groups.single['itemList'], 256)) {
      final entry = _map(raw);
      if (_hidden(entry)) continue;
      final key = _text(entry['name'], 64);
      final game = metadata[key];
      if (game == null)
        throw const FormatException('CC live entry has no matching game');
      final url = Uri.tryParse(_text(entry['content'], 2048));
      if (url == null ||
          url.scheme != 'https' ||
          url.host != 'cc.163.com' ||
          url.userInfo.isNotEmpty ||
          url.hasPort ||
          url.hasFragment) {
        throw const FormatException('Invalid CC live entry destination');
      }
      final category = RegExp(r'^/n/ds_category/([1-9][0-9]{0,15})/$')
          .firstMatch(url.path);
      final room = RegExp(r'^/([1-9][0-9]{0,15})/$').firstMatch(url.path);
      if (category == null && room == null)
        throw const FormatException('Unknown CC live entry route');
      final id = category != null
          ? category.group(1)!
          : 'official:${room!.group(1)}';
      if (!identities.add(id))
        throw const FormatException('Duplicate CC live entry identity');
      final parent = category != null ? '1' : 'official';
      final label = category != null ? categoryLabel : officialLabel;
      final area = _LegacyArea(
        platform: 'cc',
        areaId: id,
        areaType: parent,
        typeName: label,
        areaName: _text(game['name'], 200),
        areaPic: _image(game['icon']),
      );
      (category != null ? categories : official).add(area);
    }
    return [
      if (categories.isNotEmpty)
        _LegacyCategory(id: '1', name: categoryLabel, children: categories),
      if (official.isNotEmpty)
        _LegacyCategory(
          id: 'official',
          name: officialLabel,
          children: official,
        ),
    ];
  }

  static Map _envelope(Object? value) {
    final envelope = _map(value);
    if (envelope['code'] != 200)
      throw const FormatException('CC catalogue request was not successful');
    return envelope;
  }

  static Map _map(Object? value) {
    if (value is! Map)
      throw const FormatException('Invalid CC catalogue object');
    return value;
  }

  static List _list(Object? value, int limit) {
    if (value is! List || value.length > limit)
      throw const FormatException('Invalid CC catalogue list');
    return value;
  }

  static String _text(Object? value, int limit) {
    if (value is! String || value.trim().isEmpty || value.length > limit) {
      throw const FormatException('Invalid CC catalogue text');
    }
    return value.trim();
  }

  static bool _hidden(Map value) {
    final hidden = value['hidden'];
    if (hidden != null && hidden is! bool)
      throw const FormatException('Invalid CC visibility');
    return hidden == true;
  }

  static String _image(Object? value) {
    if (value is! String || value.length > 2048) return '';
    final uri = Uri.tryParse(value);
    return uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? value
        : '';
  }
}

// 3.x's CC parsers (legacy/lib/core/site/cc/cc_site.dart) --------------------

class CCSite {
  final String kUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36";

  List<_LegacyRoom> getCategoryRooms(
    _LegacyArea category, {
    int page = 1,
    int pageSize = 30,
  }) {
    final game = category.areaId?.trim() ?? '';
    final platform = category.platform?.trim().toLowerCase() ?? '';
    if (!RegExp(r'^[1-9][0-9]{0,15}$').hasMatch(game) ||
        (platform.isNotEmpty && platform != 'cc') ||
        page < 1 ||
        page > 100000 ||
        pageSize < 1 ||
        pageSize > 1000) {
      throw ArgumentError('Invalid CC category or pagination');
    }
    final result = _getJson(
      'https://cc.163.com/api/category/$game/',
      queryParameters: {
        'format': 'json',
        'tag_id': 0,
        'start': (page - 1) * pageSize,
        'size': pageSize,
      },
    );
    if (result is! Map ||
        result['gametype']?.toString() != game ||
        result['lives'] is! List) {
      throw const FormatException('Invalid CC category response');
    }
    final rows = result['lives'] as List;
    if (rows.length > 1000)
      throw const FormatException('CC category response exceeds row limit');
    final items = <_LegacyRoom>[];
    for (final item in rows) {
      if (item is! Map) throw const FormatException('Invalid CC category room');
      final rawId = item['cuteid'];
      if ((rawId is! String && rawId is! int) ||
          (rawId is int && rawId > 9007199254740991) ||
          !RegExp(r'^[1-9][0-9]{0,31}$').hasMatch(rawId.toString())) {
        throw const FormatException('Invalid CC category room identity');
      }
      String text(Object? value) => value is String ? value : '';
      final audience = parseRoomAudience(Map<String, dynamic>.from(item));
      final status = int.tryParse(item['status']?.toString() ?? '');
      items.add(
        _LegacyRoom(
          roomId: rawId.toString(),
          title: text(item['title']),
          cover: text(item['cover']),
          nick: text(item['nickname']),
          watching: audience.popularity.isNotEmpty
              ? audience.popularity
              : audience.onlineViewers,
          popularity: audience.popularity,
          onlineViewers: audience.onlineViewers,
          audienceMetricType: audience.popularity.isNotEmpty
              ? AudienceMetricType.popularity
              : AudienceMetricType.onlineViewers,
          avatar: text(item['purl']),
          area: text(item['game_name']).isNotEmpty
              ? text(item['game_name'])
              : text(item['gamename']),
          liveStatus: status == 1
              ? LiveStatus.live
              : status == 0
              ? LiveStatus.offline
              : LiveStatus.unknown,
          status: status == 1,
          platform: 'cc',
        ),
      );
    }
    return items;
  }

  List<_LegacyQuality> getPlayQualites({required _LegacyRoom detail}) {
    final rawData = detail.data;
    if (rawData is! Map) return const <_LegacyQuality>[];
    final qualities = <_LegacyQuality>[];
    var reflect = {
      'blueray': '原画',
      'original': '原画',
      'high': '高清',
      'medium': '标准',
      'standard': '标准',
      'low': '低清',
      'ultra': '蓝光',
    };

    const priority = ['hs', 'ks', 'ali', 'fws', 'wy'];
    final isLiveStream = rawData['resolution'] == null;
    final qualityData = isLiveStream ? rawData : rawData['resolution'];
    if (qualityData is! Map) return const <_LegacyQuality>[];
    final qulityList = qualityData;
    qulityList.forEach((key, value) {
      if (value is! Map) return;
      final cdn = isLiveStream ? value['CDN_FMT'] : value['cdn'];
      if (cdn is! Map) return;
      final preferredLines = <String>[];
      final otherLines = <String>[];
      cdn.forEach((line, lineValue) {
        final baseUrl = detail.link?.trim() ?? '';
        final url = isLiveStream && baseUrl.isNotEmpty
            ? _resolveLiveCdnUrl(baseUrl, lineValue)
            : _normalizeDirectUrl(lineValue);
        if (Uri.tryParse(url)?.hasScheme != true) return;
        final target = priority.contains(line.toString().toLowerCase())
            ? preferredLines
            : otherLines;
        if (!target.contains(url)) target.add(url);
      });
      final lines = <String>[...preferredLines, ...otherLines];
      if (lines.isEmpty) return;
      final bitrateKbps = int.tryParse(value['vbr']?.toString() ?? '') ?? 0;
      final sort = _qualitySort(key.toString(), bitrateKbps);
      qualities.add(
        _LegacyQuality(
          quality: _qualityLabel(
            rawLabel: reflect[key] ?? key.toString(),
            id: key,
            bitrate: bitrateKbps > 0 ? bitrateKbps * 1000 : null,
          ),
          id: key.toString(),
          sort: sort,
          data: List<String>.unmodifiable(lines),
        ),
      );
    });
    qualities.sort((a, b) => b.sort.compareTo(a.sort));

    return qualities;
  }

  static int _qualitySort(String rawKey, int bitrateKbps) {
    final key = rawKey.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    final rank = switch (key) {
      'blueray' || 'original' || 'origin' || 'source' => 6,
      'ultra' => 5,
      'high' || 'hd' => 4,
      'medium' || 'standard' || 'sd' => 3,
      'low' || 'ld' => 2,
      _ => 0,
    };
    return rank == 0
        ? bitrateKbps
        : rank * 1000000 + bitrateKbps.clamp(0, 999999);
  }

  static String _resolveLiveCdnUrl(String baseUrl, dynamic lineValue) {
    final value = lineValue?.toString().trim() ?? '';
    if (value.startsWith('//')) return 'https:$value';
    final direct = Uri.tryParse(value);
    if (direct?.hasScheme == true) {
      return const {'http', 'https'}.contains(direct!.scheme.toLowerCase())
          ? value
          : '';
    }
    if (value.isEmpty) return baseUrl;
    final suffix = value.replaceFirst(RegExp(r'^[?&]+'), '');
    return '$baseUrl${baseUrl.contains('?') ? '&' : '?'}$suffix';
  }

  static String _normalizeDirectUrl(dynamic lineValue) {
    final value = lineValue?.toString().trim() ?? '';
    return value.startsWith('//') ? 'https:$value' : value;
  }

  List<String> getPlayUrls({
    required _LegacyRoom detail,
    required _LegacyQuality quality,
  }) {
    final data = quality.data;
    if (data is! List) return const <String>[];
    return data
        .map((item) => item.toString().trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
  }

  List<_LegacyRoom> getRecommendRooms({int page = 1, int pageSize = 30}) {
    try {
      dynamic result = _getJson(
        "https://cc.163.com/api/category/live/",
        queryParameters: {
          "format": "json",
          "start": (page - 1) * pageSize,
          "size": pageSize,
        },
      );

      var items = <_LegacyRoom>[];
      for (var item in result["lives"]) {
        final audience = parseRoomAudience(
          Map<String, dynamic>.from(item as Map),
        );
        var roomItem = _LegacyRoom(
          roomId: item["cuteid"].toString(),
          title: item["title"].toString(),
          cover: item["cover"].toString(),
          nick: item["nickname"].toString(),
          watching: audience.popularity.isNotEmpty
              ? audience.popularity
              : audience.onlineViewers,
          popularity: audience.popularity,
          onlineViewers: audience.onlineViewers,
          audienceMetricType: audience.popularity.isNotEmpty
              ? AudienceMetricType.popularity
              : AudienceMetricType.onlineViewers,
          avatar: item["purl"],
          area: item["game_name"] ?? '',
          liveStatus: LiveStatus.live,
          status: true,
          platform: 'cc',
        );
        items.add(roomItem);
      }
      return items;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  _LegacyRoom getRoomDetail({
    required String platform,
    required String roomId,
  }) {
    try {
      return _loadRoomDetail(roomId);
    } catch (e) {
      // 3.x first tried the player's current room; the harness has none.
      return _LegacyRoom(
        roomId: roomId,
        platform: platform,
      ).getLiveRoomWithError();
    }
  }

  _LegacyRoom getRoomDetailForRefresh({
    required String platform,
    required String roomId,
  }) => _loadRoomDetail(roomId);

  _LegacyRoom _loadRoomDetail(String roomId) {
    const url = "https://api.cc.163.com/v1/activitylives/anchor/lives";
    dynamic result = _getJson(url, queryParameters: {'anchor_ccid': roomId});
    final channelId = result['data'][roomId]['channel_id'];
    final urlToGetReal =
        "https://cc.163.com/live/channel/?channelids=$channelId";
    dynamic resultReal = _getJson(
      urlToGetReal,
      queryParameters: {'anchor_ccid': roomId},
    );
    final roomInfo = resultReal["data"][0];
    final audience = parseRoomAudience(
      Map<String, dynamic>.from(roomInfo as Map),
    );
    final nativeMetric = audience.popularity.isNotEmpty
        ? audience.popularity
        : audience.onlineViewers;
    final live = int.tryParse(roomInfo['status']?.toString() ?? '') == 1;
    return _LegacyRoom(
      cover: roomInfo["cover"],
      watching: nativeMetric.isNotEmpty
          ? nativeMetric
          : roomInfo["follower_num"].toString(),
      popularity: audience.popularity,
      onlineViewers: audience.onlineViewers,
      audienceMetricType: audience.popularity.isNotEmpty
          ? AudienceMetricType.popularity
          : audience.onlineViewers.isNotEmpty
          ? AudienceMetricType.onlineViewers
          : AudienceMetricType.followers,
      roomId: roomInfo["ccid"].toString(),
      area: roomInfo["gamename"],
      title: roomInfo["title"],
      nick: roomInfo["nickname"].toString(),
      avatar: roomInfo["purl"].toString(),
      introduction: roomInfo["personal_label"],
      notice: roomInfo["personal_label"],
      status: live,
      liveStatus: live ? LiveStatus.live : LiveStatus.offline,
      platform: 'cc',
      link: roomInfo['m3u8'],
      userId: roomInfo['cid'].toString(),
      data: roomInfo["quickplay"] ?? roomInfo["stream_list"],
    );
  }

  static ({String popularity, String onlineViewers}) parseRoomAudience(
    Map<String, dynamic> room,
  ) {
    final popularity = _firstAudienceValue([
      room['webcc_visitor'],
      room['hot_score'],
      room['visitor'],
      room['total_visitor'],
    ]);
    final onlineViewers = _firstAudienceValue([
      room['vision_visitor'],
      room['online_num'],
    ]);
    return (popularity: popularity, onlineViewers: onlineViewers);
  }

  static String _firstAudienceValue(Iterable<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text != 'null' && RegExp(r'[0-9]').hasMatch(text))
        return text;
    }
    return '';
  }

  List<_LegacyRoom> searchRooms(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) {
    final effectivePageSize = pageSize.clamp(1, 50);
    dynamic result = _getJson(
      // 3.x asked for /search/anchor; the site answers 301 to this recorded
      // /search/anchor/ with the same query, and dio followed it.
      "https://cc.163.com/search/anchor/",
      queryParameters: {
        "query": keyword,
        "size": effectivePageSize,
        "page": page,
      },
    );
    var items = <_LegacyRoom>[];
    var queryList = result["webcc_anchor"]["result"] ?? [];
    for (var item in queryList) {
      var roomItem = _LegacyRoom(
        roomId: item["cuteid"].toString(),
        title: item["title"],
        cover: item["portrait"],
        nick: item["nickname"].toString(),
        area: item["game_name"] ?? '',
        status: item['status'] == 1,
        liveStatus: item['status'] != null && item['status'] == 1
            ? LiveStatus.live
            : LiveStatus.offline,
        avatar: item["portrait"].toString(),
        watching: item["follower_num"].toString(),
        followers: item["follower_num"].toString(),
        audienceMetricType: AudienceMetricType.followers,
        platform: 'cc',
      );
      items.add(roomItem);
    }
    return items;
  }

  List<_LegacyAnchor> searchAnchors(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) {
    final rooms = searchRooms(keyword, page: page, pageSize: pageSize);
    return rooms
        .map(
          (room) => _LegacyAnchor(
            roomId: room.roomId ?? '',
            avatar: room.avatar ?? '',
            userName: room.nick ?? '',
            liveStatus: room.isLiveNow,
          ),
        )
        .toList();
  }
}
