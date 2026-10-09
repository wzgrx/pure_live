import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_store/src/accounts.dart';
import 'package:live_store/src/legacy/legacy_rules.dart';
import 'package:live_store/src/local_events.dart';
import 'package:live_store/src/rooms.dart';
import 'package:live_store/src/secrets.dart';
import 'package:live_store/src/settings/setting.dart';
import 'package:live_store/src/settings/settings.dart';
import 'package:live_store/src/tags.dart';
import 'package:live_store/src/webdav.dart';

/// 3.x data read from its Hive box or a backup file, converted to v4 types
/// and repaired, ready to be written. A null collection means "not in the
/// source" (a restore leaves that part of the store alone).
final class LegacySnapshot {
  new _();

  /// Reads the raw entries of 3.x's `app_settings` box (`HiveBoxReader`).
  /// Damaged values are skipped (listed in [skipped]); never throws.
  factory fromHive(Map<String, Object?> raw) {
    final snapshot = LegacySnapshot._()
      .._source = raw
      .._readSettings((setting) => raw.containsKey(setting.key) ? raw[setting.key] : _absent)
      .._readCollections(
        follows: raw['favoriteRooms'],
        areas: raw['favoriteAreas'],
        history: raw['historyRooms'],
        tags: raw['user_custom_tags_v5'],
        roomTags: raw['room_to_tags_mapping_v1'],
        keywords: raw['shieldList'],
        users: raw['blockedDanmakuUsers'],
        webdav: raw['webDavConfigs'],
        currentWebDav: raw['currentWebDavConfig'],
        strict: false,
      )
      .._readSecrets(raw)
      .._upgradeThemeColor()
      .._applyHiveCounters(raw)
      .._keepOtherValues(raw);
    return snapshot;
  }

  /// Reads a 3.x (or v4) backup: the flat format without `backupVersion`,
  /// or the sectioned versions 2..4. Throws [FormatException] for a file
  /// that is not a backup or has a malformed section, before anything is
  /// written (3.x checked the same, backup_controller.dart:146-168).
  factory fromBackup(Map<String, Object?> json) {
    final version = json['backupVersion'];
    if (version != null && (version is! int || version < 1)) throw const FormatException('Invalid backup version');
    final snapshot = LegacySnapshot._().._source = json;
    if (version == null) {
      final tags = json['custom_tags_data'];
      snapshot
        .._readSettings((setting) => _field(json, setting))
        .._readCollections(
          follows: json['favoriteRooms'],
          areas: json['favoriteAreas'],
          history: json['historyRooms'],
          tags: tags is Map ? tags['tags'] : null,
          roomTags: tags is Map ? tags['roomTagsMap'] : null,
          keywords: json['shieldList'],
          users: json['blockedDanmakuUsers'],
          webdav: json['webDavConfigs'],
          currentWebDav: json['currentWebDavConfig'],
          strict: true,
        )
        .._readSecrets(json);
    } else {
      final sections = <String, Map<String, Object?>>{};
      for (final entry in json.entries) {
        final value = entry.value;
        if (entry.key == 'backupVersion' || entry.key == 'sensitiveDataIncluded' || entry.key == 'backupScope') {
          continue;
        }
        if (value == null) continue;
        if (value is! Map) {
          if (_knownSections.contains(entry.key)) throw FormatException('Invalid backup section: ${entry.key}');
          continue;
        }
        sections[entry.key] = value.cast<String, Object?>();
      }
      final windowSize = sections['windowSize'];
      if (windowSize != null && windowSize['windowsPip'] is Map) {
        sections['windowSize'] = {...windowSize, ...(windowSize['windowsPip']! as Map).cast<String, Object?>()};
      }
      final rememberPip = sections['player']?['rememberPipPosition'];
      if (rememberPip != null && sections['windowSize']?['rememberPipPosition'] == null) {
        sections['windowSize'] = {...?sections['windowSize'], 'rememberPipPosition': rememberPip};
      }
      final favorite = sections['favorite'];
      final history = sections['history'];
      final tags = sections['tags'];
      final webdav = sections['webdav'];
      snapshot
        .._readSettings((setting) {
          final section = sections[setting.section];
          return section == null ? _absent : _field(section, setting);
        })
        .._readCollections(
          follows: favorite == null ? null : favorite['favoriteRooms'],
          areas: favorite == null ? null : favorite['favoriteAreas'],
          history: history == null ? null : history['historyRooms'],
          tags: tags == null ? null : tags['tags'],
          roomTags: tags == null ? null : tags['roomTagsMap'],
          keywords: favorite == null ? null : favorite['shieldList'],
          users: favorite == null ? null : favorite['blockedDanmakuUsers'],
          webdav: webdav == null ? null : webdav['webDavConfigs'],
          currentWebDav: webdav == null ? null : webdav['currentWebDavConfig'],
          strict: true,
        );
      if (sections['cookie'] case final cookie?) snapshot._readSecrets(cookie);
      // D08.1: a device sync of only the local history (`BackupService`
      // restores it).
      if (sections.containsKey(LocalEventStore.backupSection)) snapshot._recognized = true;
      snapshot.favoritesOnly = json['backupScope'] == 'favorites';
    }
    // 3.x's files (version 3 and older) carry its default blue; v4's own
    // backups keep whatever the user picked.
    if (version == null || (version as int) < 4) snapshot._upgradeThemeColor();
    if (!snapshot._recognized) throw const FormatException('No recognized backup settings');
    return snapshot;
  }

  static const Object _absent = Object();

  static const Set<String> _knownSections = {
    'app', 'theme', 'roomCard', 'font', 'player', 'danmaku', 'volume', 'favorite', 'history', 'webdav', //
    'iptv', 'cookie', 'proxy', 'windowSize', 'exit', 'startup', 'refresh', 'page', 'tags',
  };

  static Object? _field(Map<String, Object?> section, Setting<Object> setting) {
    for (final key in [setting.backupKey, setting.key, ...setting.legacyKeys]) {
      if (section.containsKey(key)) return section[key];
    }
    return _absent;
  }

  late Map<String, Object?> _source;
  bool _recognized = false;

  /// Whether the file was a follows-only backup (`backupScope: favorites`).
  bool favoritesOnly = false;

  /// Settings present in the source, repaired.
  final Map<Setting<Object>, Object> settings = {};

  /// Followed rooms, valid and unique, in order.
  List<LiveRoom>? follows;

  /// Followed areas.
  List<LiveArea>? followAreas;

  /// History, newest first.
  List<LiveRoom>? history;

  /// Follow groups.
  List<StoreTag>? tags;

  /// Group assignments keyed by [LiveRoom.identityKey].
  Map<String, List<String>>? roomTags;

  /// Danmaku keyword blocks.
  List<String>? blockedKeywords;

  /// Danmaku user blocks.
  List<String>? blockedUsers;

  /// WebDAV servers.
  List<WebDavConfig>? webdav;

  /// Name of the current WebDAV server.
  String? currentWebDav;

  /// Cookies and Douyu passport values by [SecretRefs] name.
  Map<String, String>? secrets;

  /// The remembered sign-ins by platform (V01.2: `cookie` section,
  /// `<site>Accounts`); null when the file has none.
  Map<String, List<SavedAccount>>? savedAccounts;

  /// The suffix of the remembered sign-ins' key in the `cookie` section.
  static const String accountsSuffix = 'Accounts';

  /// 3.x values other modules own (recorder settings and tasks with quality
  /// ids converted, local interaction), kept verbatim (Hive only).
  final Map<String, Object?> otherValues = {};

  /// What could not be read, for the import report.
  final List<String> skipped = [];

  void _readSettings(Object? Function(Setting<Object>) valueOf) {
    for (final setting in Settings.all) {
      final raw = valueOf(setting);
      if (identical(raw, _absent)) continue;
      _recognized = true;
      final page = setting == Settings.pageSizeOptions && raw is List ? raw.join(',') : raw;
      final value = setting.decode(page);
      if (value == null) {
        skipped.add('setting ${setting.key}');
      } else {
        settings[setting] = setting.normalize(value);
      }
    }
    if (settings[Settings.hotAreasList] case final List<String> home) {
      settings[Settings.hotAreasList] = LegacyRules.homePlatforms(home, LegacyRules.currentCatalogVersion);
    }
    if (settings[Settings.preferPlatform] case final String preferred) {
      final home = settings[Settings.hotAreasList] as List<String>? ?? Settings.hotAreasList.defaultValue;
      settings[Settings.preferPlatform] = LegacyRules.preferredPlatform(preferred, home);
    }
    if (settings[Settings.savedMenuIds] case final List<String> menus) {
      settings[Settings.savedMenuIds] = LegacyRules.menuIds(menus);
    }
  }

  void _readCollections({
    required Object? follows,
    required Object? areas,
    required Object? history,
    required Object? tags,
    required Object? roomTags,
    required Object? keywords,
    required Object? users,
    required Object? webdav,
    required Object? currentWebDav,
    required bool strict,
  }) {
    List<Map<String, Object?>>? objects(String name, Object? raw) {
      if (raw == null) return null;
      _recognized = true;
      final list = _objectList(raw, strict: strict, name: name);
      if (list == null) skipped.add(name);
      return list;
    }

    if (objects('favoriteRooms', follows) case final list?) {
      this.follows = uniqueRooms(list.map(_room));
    }
    if (objects('historyRooms', history) case final list?) {
      this.history = uniqueRooms(list.map(_room));
    }
    if (objects('favoriteAreas', areas) case final list?) {
      followAreas = [for (final item in list) LiveArea.fromJson(item)];
    }
    if (objects('tags', tags) case final list?) {
      final read = [for (final item in list) StoreTag.fromJson(item)];
      final orders = [for (final item in list) _int(item['order']) ?? 0];
      final indexes = List.generate(read.length, (i) => i)..sort((a, b) => orders[a].compareTo(orders[b]));
      this.tags = [for (final i in indexes) read[i]];
    }
    if (roomTags != null) {
      _recognized = true;
      if (roomTags is Map) {
        this.roomTags = _rekeyRoomTags(roomTags);
      } else if (strict) {
        throw const FormatException('Invalid backup section: tags');
      } else {
        skipped.add('roomTags');
      }
    }
    blockedKeywords = _strings(keywords, strict: strict, name: 'shieldList');
    blockedUsers = _strings(users, strict: strict, name: 'blockedDanmakuUsers');
    if (objects('webDavConfigs', webdav) case final list?) {
      this.webdav = [for (final item in list) WebDavConfig.fromJson(item)];
    }
    if (currentWebDav is String && currentWebDav.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(currentWebDav);
        if (decoded is Map && decoded['name'] != null) this.currentWebDav = '${decoded['name']}';
      } on FormatException {
        skipped.add('currentWebDavConfig');
      }
    }
  }

  LiveRoom _room(Map<String, Object?> json) =>
      LegacyRules.clearPlaceholders(LegacyRules.clearStaleNotice(LiveRoom.fromJson(json)));

  /// 3.x keyed group assignments `platform:roomId` (lower-case platform,
  /// case kept) and, before that, by the room id alone. Keys become v4
  /// identity keys; a room-id-only key is given to every followed or
  /// history room with that id (3.x `migrateLegacyRoomTagKeys`).
  Map<String, List<String>> _rekeyRoomTags(Map<Object?, Object?> raw) {
    final rooms = [...?follows, ...?history];
    final result = <String, List<String>>{};
    void add(String key, List<String> ids) {
      final list = result.putIfAbsent(key, () => []);
      for (final id in ids) {
        if (!list.contains(id)) list.add(id);
      }
    }

    for (final entry in raw.entries) {
      final key = '${entry.key}'.trim();
      final value = entry.value;
      if (key.isEmpty || value is! List) continue;
      final ids = [for (final id in value) '$id'.trim()]..removeWhere((id) => id.isEmpty);
      final colon = key.indexOf(':');
      if (colon > 0) {
        add(LiveRoom.identityKeyFor(platform: key.substring(0, colon), roomId: key.substring(colon + 1)), ids);
        continue;
      }
      for (final room in rooms.where((room) => room.roomId.trim() == key)) {
        add(room.identityKey, ids);
      }
    }
    return result;
  }

  List<String>? _strings(Object? raw, {required bool strict, required String name}) {
    if (raw == null) return null;
    _recognized = true;
    if (raw is! List) {
      if (strict) throw FormatException('Invalid backup field: $name');
      skipped.add(name);
      return null;
    }
    final seen = <String>{};
    return [
      for (final item in raw)
        if ('$item'.trim() case final text when text.isNotEmpty && seen.add(text.toLowerCase())) text,
    ];
  }

  /// Model lists in any of 3.x's shapes: a JSON string `{"list": [...]}`
  /// (2.1+), a list of JSON strings (up to 2.0), or a list of objects
  /// (backups). A damaged item is skipped; a damaged list is null (Hive) or
  /// an error (backups, as 3.x's strict parsing).
  List<Map<String, Object?>>? _objectList(Object? raw, {required bool strict, required String name}) {
    var decoded = raw;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } on FormatException {
        if (strict) throw FormatException('Invalid backup field: $name');
        return null;
      }
    }
    if (decoded is Map) decoded = decoded['list'];
    if (decoded is! List) {
      if (strict) throw FormatException('Invalid backup field: $name');
      return null;
    }
    final result = <Map<String, Object?>>[];
    for (final item in decoded) {
      Object? value = item;
      if (value is String) {
        try {
          value = jsonDecode(value);
        } on FormatException {
          skipped.add('$name item');
          continue;
        }
      }
      if (value is Map) {
        result.add(value.map((key, v) => MapEntry('$key', v)));
      } else {
        skipped.add('$name item');
      }
    }
    return result;
  }

  /// 3.x's cookie keys: `<platform>Cookie` (Taobao's was deleted by 3.x),
  /// Douyu's passport `douyuLtp0` and `douyuDid`.
  void _readSecrets(Map<String, Object?> source) {
    final found = <String, String>{};
    final accounts = <String, List<SavedAccount>>{};
    for (final entry in source.entries) {
      final value = entry.value;
      if (_accountsKey.firstMatch(entry.key) case final match? when value is List) {
        accounts[match.group(1)!] = [for (final item in value) ?SavedAccount.fromJson(item)];
        continue;
      }
      if (value is! String) continue;
      final match = RegExp(r'^([a-z0-9]+)Cookie$').firstMatch(entry.key);
      if (match != null && match.group(1) != 'taobao') {
        found[SecretRefs.cookie(match.group(1)!)] = normalizeCookie(value);
      } else if (entry.key == 'douyuLtp0') {
        found[SecretRefs.douyuLtp0] = normalizeCookie(value);
      } else if (entry.key == 'douyuDid') {
        found[SecretRefs.douyuDid] = normalizeCookie(value);
      }
    }
    if (accounts.isNotEmpty) {
      _recognized = true;
      savedAccounts = accounts;
    }
    if (found.isEmpty) return;
    _recognized = true;
    secrets = found;
  }

  static final RegExp _accountsKey = RegExp('^([a-z0-9]+)$accountsSuffix\$');

  void _upgradeThemeColor() {
    if (settings[Settings.themeColorSwitch] case final String hex) {
      settings[Settings.themeColorSwitch] = LegacyRules.themeColor(hex);
    }
  }

  /// The migration counters only the Hive box has: platform list version,
  /// audience-metric version, danmaku interaction version, and the retired
  /// high-refresh switch.
  void _applyHiveCounters(Map<String, Object?> raw) {
    final catalog = _int(raw['siteCatalogMigration']) ?? 0;
    final home = settings[Settings.hotAreasList] as List<String>? ?? Settings.hotAreasList.defaultValue;
    final repairedHome = raw.containsKey('hotAreasList')
        ? LegacyRules.homePlatforms(
            Settings.hotAreasList.decode(raw['hotAreasList']) ?? Settings.hotAreasList.defaultValue,
            catalog,
          )
        : home;
    settings[Settings.hotAreasList] = repairedHome;
    settings[Settings.preferPlatform] = LegacyRules.preferredPlatform(
      settings[Settings.preferPlatform] as String? ?? Settings.preferPlatform.defaultValue,
      repairedHome,
    );
    final audience = _int(raw['audienceMetricMigration']) ?? 0;
    if (raw.containsKey('realOnlinePlatforms') || audience > 0) {
      settings[Settings.realOnlinePlatforms] = LegacyRules.realOnlinePlatforms(
        settings[Settings.realOnlinePlatforms] as List<String>? ?? Settings.realOnlinePlatforms.defaultValue,
        audience,
      );
    }
    if ((_int(raw['danmakuInteractionMigration']) ?? 0) < 1) {
      settings
        ..[Settings.enableDanmakuTapInteraction] = true
        ..[Settings.enableDanmakuLongPressInteraction] = true;
    }
    if (!raw.containsKey('refreshRateMode') && raw.containsKey('enableHighRefreshRate')) {
      settings[Settings.refreshRateMode] = raw['enableHighRefreshRate'] == true ? 'balanced' : 'powerSaving';
    }
  }

  static const Set<String> _consumed = {
    'favoriteRooms', 'favoriteAreas', 'historyRooms', 'user_custom_tags_v5', 'room_to_tags_mapping_v1', //
    'shieldList', 'blockedDanmakuUsers', 'webDavConfigs', 'currentWebDavConfig', 'douyuLtp0', 'douyuDid',
    'siteCatalogMigration', 'audienceMetricMigration', 'danmakuInteractionMigration', 'enableHighRefreshRate',
    'settingsUpgradeSchema', 'settingsUpgradeImportedSources', 'legacy_settings_migrated_to_v2',
    'migration.room_scoped_audio_only.v231', 'audioOnly', 'cached_area_pics', 'taobaoCookie',
  };

  void _keepOtherValues(Map<String, Object?> raw) {
    for (final entry in raw.entries) {
      if (_consumed.contains(entry.key) || Settings.byKey(entry.key) != null || entry.key.endsWith('Cookie')) continue;
      otherValues[entry.key] = entry.key == 'recorder_tasks' ? _recorderTasks(entry.value) : entry.value;
    }
  }

  /// 3.x's recorder tasks with `selectedQualityId` converted
  /// ([LegacyRules.qualityId]); the rest is M8's to read.
  Object? _recorderTasks(Object? raw) {
    if (raw is! String) return raw;
    try {
      final tasks = jsonDecode(raw);
      if (tasks is! List) return raw;
      return jsonEncode([
        for (final task in tasks)
          if (task is Map && task['selectedQualityId'] is String && task['platform'] is String)
            {...task, 'selectedQualityId': LegacyRules.qualityId('${task['platform']}', '${task['selectedQualityId']}')}
          else
            task,
      ]);
    } on FormatException {
      return raw;
    }
  }

  /// The raw source, for diagnostics.
  Map<String, Object?> get source => _source;

  static int? _int(Object? value) => value is num ? value.toInt() : int.tryParse('${value ?? ''}');
}
