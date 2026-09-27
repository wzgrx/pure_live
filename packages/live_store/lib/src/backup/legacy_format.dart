import 'package:live_core/live_core.dart';
import 'package:live_store/src/backup/import_plan.dart';
import 'package:live_store/src/backup/import_report.dart';
import 'package:live_store/src/backup/json_read.dart';
import 'package:live_store/src/block_rules.dart';
import 'package:live_store/src/follow_areas.dart';
import 'package:live_store/src/room_prefs.dart';
import 'package:live_store/src/rooms.dart';
import 'package:live_store/src/secrets/secret_store.dart';
import 'package:live_store/src/settings/registry.dart';
import 'package:live_store/src/settings/setting.dart';
import 'package:live_store/src/tags.dart';
import 'package:meta/meta.dart';

/// Reader of the 3.x backup and export formats (store.md §7.4), also used
/// for the flat key/value map of a 3.x Hive box (§6). Rewritten from the
/// spec; `legacy/lib/common/services/settings/backup_controller.dart` was
/// only read for the format.
@internal
abstract final class LegacyFormat {
  /// Sections of a versioned (v2/v3) backup.
  static const sections = {
    'app',
    'theme',
    'roomCard',
    'font',
    'player',
    'danmaku',
    'volume',
    'favorite',
    'history',
    'webdav',
    'iptv',
    'cookie',
    'proxy',
    'windowSize',
    'exit',
    'startup',
    'tags',
    'refresh',
    'page',
  };

  static const _metaKeys = {'backupVersion', 'backupScope', 'sensitiveDataIncluded'};

  static const _collectionKeys = {
    'favoriteRooms',
    'favoriteAreas',
    'historyRooms',
    'shieldList',
    'blockedDanmakuUsers',
    'roomVolumes',
    'portraitRoomOverrides',
    'webDavConfigs',
    'currentWebDavConfig',
    'custom_tags_data',
  };

  /// 3.x cookie keys and their secret references (store.md §1.4).
  static final Map<String, String> cookieKeys = {
    for (final platform in ['bilibili', 'huya', 'douyu', 'douyin', 'kuaishou', 'twitch', 'soop', 'yy'])
      '${platform}Cookie': SecretRefs.cookie(platform),
    'douyuLtp0': SecretRefs.douyuLtp0,
    'douyuDid': SecretRefs.douyuDid,
  };

  /// 3.x keys dropped on purpose (store.md §6.4.3, §6.4.4).
  static const _obsoleteKeys = {
    'taobaoCookie',
    'autoRefreshTime',
    'showSplashPage',
    'cached_area_pics',
    'audioOnly',
    'videoPlayerKey',
    'savedMenuIds',
  };

  static const _portraitOverrides = {'automatic', 'portrait', 'landscape'};

  /// Whether [json] is a 3.x backup of any shape.
  static bool recognizes(Map<String, Object?> json) {
    if (json.containsKey('backupVersion')) return true;
    return _flatRecognized(json);
  }

  static bool _flatRecognized(Map<String, Object?> json) {
    final tags = json['custom_tags_data'];
    if (tags is Map && (tags.containsKey('tags') || tags.containsKey('roomTagsMap'))) return true;
    if (json.containsKey('pipDanmaNoEmojiMode')) return true;
    return json.keys.any(
      (key) =>
          (key != 'custom_tags_data' && _collectionKeys.contains(key)) ||
          cookieKeys.containsKey(key) ||
          _legacyNames.contains(key),
    );
  }

  static final Set<String> _legacyNames = {
    for (final setting in Settings.all)
      for (final legacy in setting.legacy) legacy.name,
  };

  /// Builds a plan from a 3.x document. With [followsOnly] only follows and
  /// followed areas are read (the "restore follows" entry). Throws
  /// [FormatException] for a document that is not a valid 3.x backup.
  static ImportPlan parse(
    Map<String, Object?> json, {
    required bool followsOnly,
    required DateTime now,
    required int localHistoryLimit,
  }) {
    final plan = ImportPlan();
    final report = plan.report;
    final version = json['backupVersion'];
    if (version != null && (version is! int || version < 1)) throw const FormatException('Invalid backup version');
    final followsFile = version != null && json['backupScope'] == 'favorites';
    plan.followsOnlySource = followsFile;

    final Map<String, Object?> flat;
    if (version == null) {
      if (!_flatRecognized(json)) throw const FormatException('No recognized backup settings');
      report.format = 'legacy';
      flat = json;
    } else {
      report.format = followsFile ? 'v$version-follows' : 'v$version';
      flat = <String, Object?>{};
      var recognized = false;
      for (final name in sections) {
        final section = json[name];
        if (section == null) continue;
        if (section is! Map || section.keys.any((key) => key is! String)) {
          throw FormatException('Invalid backup section: $name');
        }
        if (section.isNotEmpty) recognized = true;
        if (name == 'tags') {
          flat['custom_tags_data'] = section;
        } else {
          flat.addAll(section.cast<String, Object?>());
        }
      }
      for (final key in json.keys) {
        if (!sections.contains(key) && !_metaKeys.contains(key)) report.note('backup', 'unknownSection', key);
      }
      if (!recognized) throw const FormatException('No recognized backup settings');
    }

    if (followsOnly || followsFile) {
      if (!flat.containsKey('favoriteRooms') && !flat.containsKey('favoriteAreas')) {
        throw const FormatException('No favorite lists in backup');
      }
      _follows(plan, flat, now);
      _followAreas(plan, flat);
      return plan;
    }

    final consumed = <String>{..._metaKeys};
    plan.settings = _settings(flat, report, consumed);
    _follows(plan, flat, now);
    _followAreas(plan, flat);
    final limit = (plan.settings!['history.limit'] as int?) ?? localHistoryLimit;
    _history(plan, flat, limit);
    _tags(plan, flat);
    _blockRules(plan, flat, now);
    _roomPrefs(plan, flat);
    _secrets(plan, flat);
    if (flat.containsKey('webDavConfigs') || flat.containsKey('currentWebDavConfig')) {
      report.note('webdavProfiles', 'unsupported');
    }
    consumed
      ..addAll(_collectionKeys)
      ..addAll(cookieKeys.keys)
      ..addAll(_obsoleteKeys);
    for (final key in flat.keys) {
      if (!consumed.contains(key)) report.drop('settings', 'unknownKey', key);
    }
    return plan;
  }

  static Map<String, Object> _settings(Map<String, Object?> flat, ImportReport report, Set<String> consumed) {
    final result = <String, Object>{};
    var read = 0;
    for (final setting in Settings.all) {
      for (final legacy in setting.legacy) {
        if (!flat.containsKey(legacy.name)) continue;
        consumed.add(legacy.name);
        if (result.containsKey(setting.id)) continue;
        read++;
        final value = setting.decode(legacy.apply(flat[legacy.name]));
        if (value == null) {
          report.drop('settings', 'invalidValue', legacy.name);
        } else {
          result[setting.id] = value;
        }
      }
    }
    // The preferred platform must be visible (store.md §6.4.8).
    final platforms = result[Settings.catalogPlatforms.id] as List<String>?;
    final preferred = result[Settings.catalogPreferred.id] as String?;
    if (platforms != null && platforms.isNotEmpty && preferred != null && !platforms.contains(preferred)) {
      result[Settings.catalogPreferred.id] = platforms.first;
    }
    report
      ..read('settings', read)
      ..written('settings', result.length);
    return result;
  }

  /// Reads a 3.x `LiveRoom` JSON object; null (and a report entry) when its
  /// identity is invalid (store.md §2, §6.4.7, §6.4.11).
  static ImportedRoom? room(Map<String, Object?> json, ImportReport report, String section) {
    final platform = JsonRead.text(json['platform']) ?? '';
    final roomId = JsonRead.text(json['roomId']) ?? '';
    final RoomRef ref;
    try {
      ref = RoomRef(platform, roomId);
    } on FormatException {
      report.drop(section, 'invalidRoom', '$platform:$roomId');
      return null;
    }
    var online = JsonRead.count(json['onlineViewers']);
    var popularity = JsonRead.count(json['popularity']);
    if (ref.platform == 'huya' && online != null) {
      popularity ??= online;
      online = null;
    }
    final extra = <String, Object?>{
      for (final key in [
        'notice',
        'introduction',
        'epgId',
        'currentProgramme',
        'currentProgrammeDescription',
        'catchUpUrl',
        'catchUpStart',
        'catchUpEnd',
        'catchUpMode',
        'catchUpSource',
        'catchUpDays',
        'catchUpCorrectionHours',
      ])
        if (_present(json[key])) key: json[key],
      if (json['isCatchUp'] == true) 'isCatchUp': true,
      if (JsonRead.count(json['followers']) case final followers? when followers > 0) 'followers': followers,
      if (json['httpHeaders'] case final Map<Object?, Object?> headers when headers.isNotEmpty)
        'httpHeaders': {
          for (final MapEntry(:key, :value) in headers.entries)
            if (key is String && value is String) key: value,
        },
    };
    return ImportedRoom(
      RoomSnapshot(
        ref: ref,
        anchorName: JsonRead.nonEmpty(json['nick']),
        title: JsonRead.nonEmpty(json['title']),
        avatar: JsonRead.uri(json['avatar']),
        cover: JsonRead.uri(json['cover']),
        area: JsonRead.nonEmpty(json['area']),
        userId: JsonRead.nonEmpty(json['userId']),
        audience: Audience(online: online, popularity: popularity, cumulative: JsonRead.count(json['totalViewers'])),
        state: _state(json),
      ),
      extra: extra,
    );
  }

  static bool _present(Object? value) => value != null && value != '' && value != false;

  static LiveState? _state(Map<String, Object?> json) {
    if (json['isRecord'] == true) return LiveState.replay;
    final index = json['liveStatus'];
    if (index is int) {
      return switch (index) {
        0 => LiveState.live,
        1 || 4 => LiveState.offline,
        2 => LiveState.replay,
        _ => null,
      };
    }
    final status = json['status'];
    return status is bool ? (status ? LiveState.live : LiveState.offline) : null;
  }

  static List<ImportedRoom> _rooms(Object? value, String name, ImportReport report) {
    final items = JsonRead.collection(value, name);
    final rooms = <ImportedRoom>[];
    for (final raw in items) {
      final item = JsonRead.item(raw);
      if (item == null) {
        report.drop(name, 'invalidItem');
        continue;
      }
      final parsed = room(item, report, name);
      if (parsed != null) rooms.add(parsed);
    }
    return rooms;
  }

  static void _follows(ImportPlan plan, Map<String, Object?> flat, DateTime now) {
    if (!flat.containsKey('favoriteRooms')) return;
    final report = plan.report;
    final items = JsonRead.collection(flat['favoriteRooms'], 'favoriteRooms');
    report.read('follows', items.length);
    final rooms = dedupeRooms(
      _rooms(items, 'follows', report),
      (room) => room.ref,
      (first, later) => first.fillFrom(later),
      report: report,
      section: 'follows',
    );
    plan.follows = [for (final room in rooms) PlannedFollow(room, followedAt: now)];
    report.written('follows', rooms.length);
  }

  static void _followAreas(ImportPlan plan, Map<String, Object?> flat) {
    if (!flat.containsKey('favoriteAreas')) return;
    final report = plan.report;
    final items = JsonRead.collection(flat['favoriteAreas'], 'favoriteAreas');
    report.read('followAreas', items.length);
    final seen = <String>{};
    final areas = <FollowedArea>[];
    for (final raw in items) {
      final item = JsonRead.item(raw);
      final area = item == null
          ? null
          : FollowedArea(
              platform: JsonRead.text(item['platform']) ?? '',
              namespace: JsonRead.text(item['areaType']) ?? '',
              areaId: JsonRead.text(item['areaId']) ?? '',
              areaName: JsonRead.text(item['areaName']) ?? '',
              typeName: JsonRead.text(item['typeName']) ?? '',
              areaPic: JsonRead.nonEmpty(item['areaPic']),
              shortName: JsonRead.nonEmpty(item['shortName']),
              order: areas.length,
            );
      if (area == null || !area.isValid) {
        report.drop('followAreas', 'invalidItem', area?.key);
      } else if (!seen.add(area.key)) {
        report.drop('followAreas', 'duplicate', area.key);
      } else {
        areas.add(area);
      }
    }
    plan.followAreas = areas;
    report.written('followAreas', areas.length);
  }

  static void _history(ImportPlan plan, Map<String, Object?> flat, int limit) {
    if (!flat.containsKey('historyRooms')) return;
    final report = plan.report;
    final items = JsonRead.collection(flat['historyRooms'], 'historyRooms');
    report.read('history', items.length);
    final entries = <PlannedHistory>[];
    for (final raw in items) {
      final item = JsonRead.item(raw);
      if (item == null) {
        report.drop('history', 'invalidItem');
        continue;
      }
      final parsed = room(item, report, 'history');
      if (parsed != null) entries.add(PlannedHistory(parsed, lastWatchedAt: JsonRead.millis(item['lastWatchedAt'])));
    }
    var deduped = dedupeRooms(
      entries,
      (entry) => entry.room.ref,
      (first, later) =>
          PlannedHistory(first.room.fillFrom(later.room), lastWatchedAt: first.lastWatchedAt ?? later.lastWatchedAt),
      report: report,
      section: 'history',
    );
    if (limit > 0 && deduped.length > limit) {
      for (final entry in deduped.skip(limit)) {
        report.drop('history', 'overLimit', entry.room.ref.key);
      }
      deduped = deduped.take(limit).toList();
    }
    plan.history = deduped;
    report.written('history', deduped.length);
  }

  static void _tags(ImportPlan plan, Map<String, Object?> flat) {
    final data = JsonRead.object(flat['custom_tags_data']);
    if (data == null) return;
    final report = plan.report;

    final alias = <String, String>{};
    if (data.containsKey('tags')) {
      final items = data['tags'] is List ? data['tags']! as List : throw const FormatException('Invalid tags');
      report.read('tags', items.length);
      final raw = <({String id, String name, String description, int order})>[];
      for (final item in items) {
        final map = JsonRead.item(item);
        if (map == null) {
          report.drop('tags', 'invalidItem');
          continue;
        }
        raw.add((
          id: JsonRead.text(map['id']) ?? '',
          name: JsonRead.text(map['name']) ?? '',
          description: JsonRead.text(map['description']) ?? '',
          order: JsonRead.count(map['order']) ?? 0,
        ));
      }
      final sorted = [...raw.indexed]
        ..sort((a, b) => a.$2.order != b.$2.order ? a.$2.order.compareTo(b.$2.order) : a.$1.compareTo(b.$1));
      final byName = <String, String>{};
      final ids = <String>{};
      final tags = <Tag>[];
      for (final (_, tag) in sorted) {
        if (tag.name.isEmpty) {
          report.drop('tags', 'invalidItem', tag.id);
          continue;
        }
        final folded = TagStore.fold(tag.name);
        final existing = byName[folded];
        if (existing != null) {
          if (tag.id.isNotEmpty) alias.putIfAbsent(tag.id, () => existing);
          report.drop('tags', 'duplicate', tag.name);
          continue;
        }
        // Replacement ids are derived, not random, so importing the same
        // file twice gives the same ids (store.md §0 rule 2).
        var id = tag.id;
        for (var n = 1; id.isEmpty || ids.contains(id); n++) {
          id = '${tag.id.isEmpty ? 'tag' : tag.id}~$n';
        }
        if (tag.id.isNotEmpty) alias.putIfAbsent(tag.id, () => id);
        ids.add(id);
        byName[folded] = id;
        tags.add(Tag(id: id, name: tag.name, description: tag.description, order: tags.length));
      }
      plan.tags = tags;
      report.written('tags', tags.length);
    }

    final map = data['roomTagsMap'];
    if (map == null) return;
    if (map is! Map) throw const FormatException('Invalid roomTagsMap');
    final known = {...alias.values};
    if (plan.tags == null) {
      report.note('roomTags', 'unsupported', 'membership without tags');
      return;
    }
    final byRoomId = <String, Set<RoomRef>>{};
    for (final room in [...?plan.follows?.map((follow) => follow.room), ...?plan.history?.map((entry) => entry.room)]) {
      byRoomId.putIfAbsent(room.ref.roomId, () => {}).add(room.ref);
    }
    final membership = <RoomRef, Set<String>>{};
    var read = 0;
    for (final MapEntry(:key, :value) in map.entries) {
      read++;
      final keyText = key.toString().trim();
      final tagIds = <String>{};
      for (final id in value is List ? value : const []) {
        final resolved = alias[JsonRead.text(id) ?? ''];
        if (resolved == null || !known.contains(resolved)) {
          report.drop('roomTags', 'unknownTag', '$id');
        } else {
          tagIds.add(resolved);
        }
      }
      if (tagIds.isEmpty) continue;
      final Set<RoomRef> refs;
      if (keyText.contains(':')) {
        try {
          refs = {RoomRef.parse(keyText)};
        } on FormatException {
          report.drop('roomTags', 'invalidRoom', keyText);
          continue;
        }
      } else {
        refs = byRoomId[keyText] ?? const {};
        if (refs.isEmpty) {
          report.drop('roomTags', 'unmatchedRoom', keyText);
          continue;
        }
      }
      for (final ref in refs) {
        membership.putIfAbsent(ref, () => {}).addAll(tagIds);
      }
    }
    plan.roomTags = membership;
    report
      ..read('roomTags', read)
      ..written('roomTags', membership.length);
  }

  static void _blockRules(ImportPlan plan, Map<String, Object?> flat, DateTime now) {
    final rules = <BlockKind, List<BlockRule>>{};
    for (final (key, kind) in [('shieldList', BlockKind.keyword), ('blockedDanmakuUsers', BlockKind.user)]) {
      if (!flat.containsKey(key)) continue;
      final items = JsonRead.collection(flat[key], key);
      final seen = <String>{};
      final list = <BlockRule>[];
      for (final item in items) {
        final value = JsonRead.nonEmpty(item);
        if (value == null) {
          plan.report.drop('blockRules', 'invalidItem');
        } else if (!seen.add(BlockRuleStore.fold(value))) {
          plan.report.drop('blockRules', 'duplicate', value);
        } else {
          list.add(BlockRule(kind: kind, value: value, createdAt: now));
        }
      }
      rules[kind] = list;
      plan.report
        ..read('blockRules.${kind.name}', items.length)
        ..written('blockRules.${kind.name}', list.length);
    }
    if (rules.isNotEmpty) plan.blockRules = rules;
  }

  static void _roomPrefs(ImportPlan plan, Map<String, Object?> flat) {
    final report = plan.report;
    final prefs = <PlannedRoomPref>[];
    final volumes = flat.containsKey('roomVolumes') ? JsonRead.object(flat['roomVolumes']) : null;
    if (volumes != null) {
      for (final MapEntry(:key, :value) in volumes.entries) {
        final ref = volumeKeyRef(key);
        if (ref == null) {
          report.drop('roomPrefs', 'invalidRoom', key);
          continue;
        }
        if (value is! num || !value.isFinite) {
          report.drop('roomPrefs', 'invalidValue', key);
          continue;
        }
        prefs.add(PlannedRoomPref(ref, RoomPrefStore.volume, value.toDouble().clamp(0, 1).toDouble()));
      }
    }
    final overrides = flat.containsKey('portraitRoomOverrides') ? JsonRead.object(flat['portraitRoomOverrides']) : null;
    if (overrides != null) {
      for (final MapEntry(:key, :value) in overrides.entries) {
        final RoomRef ref;
        try {
          ref = RoomRef.parse(key);
        } on FormatException {
          report.drop('roomPrefs', 'invalidRoom', key);
          continue;
        }
        if (value is! String || !_portraitOverrides.contains(value)) {
          report.drop('roomPrefs', 'invalidValue', key);
          continue;
        }
        prefs.add(PlannedRoomPref(ref, RoomPrefStore.portraitLayout, value));
      }
    }
    if (volumes == null && overrides == null) return;
    plan.roomPrefs = prefs;
    report.written('roomPrefs', prefs.length);
  }

  /// Parses a 3.x volume key `room_vol_<platform>_<roomId>` (store.md §2).
  static RoomRef? volumeKeyRef(String key) {
    const prefix = 'room_vol_';
    if (!key.startsWith(prefix)) return null;
    final rest = key.substring(prefix.length);
    final separator = rest.indexOf('_');
    if (separator <= 0) return null;
    try {
      return RoomRef(rest.substring(0, separator), rest.substring(separator + 1));
    } on FormatException {
      return null;
    }
  }

  static void _secrets(ImportPlan plan, Map<String, Object?> flat) {
    final secrets = <String, String?>{};
    for (final MapEntry(key: name, value: ref) in cookieKeys.entries) {
      if (!flat.containsKey(name)) continue;
      final value = flat[name];
      if (value is! String) continue;
      final normalized = normalizeCookie(value);
      secrets[ref] = normalized.isEmpty ? null : normalized;
    }
    if (secrets.isEmpty) return;
    plan
      ..secrets = secrets
      ..report.secretsPresent = true;
  }

  /// Cookie text as 3.x normalised it: control characters removed, trimmed.
  static String normalizeCookie(String value) => value.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').trim();

  /// The settings a 3.x key feeds, for tests and the migration report.
  static List<Setting<Object>> settingsFor(String legacyKey) => [
    for (final setting in Settings.all)
      if (setting.legacy.any((legacy) => legacy.name == legacyKey)) setting,
  ];
}
