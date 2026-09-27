import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_store/src/backup/import_plan.dart';
import 'package:live_store/src/backup/import_report.dart';
import 'package:live_store/src/backup/json_read.dart';
import 'package:live_store/src/backup/record_tasks.dart';
import 'package:live_store/src/backup/secret_envelope.dart';
import 'package:live_store/src/block_rules.dart';
import 'package:live_store/src/follow_areas.dart';
import 'package:live_store/src/iptv.dart';
import 'package:live_store/src/live_store.dart';
import 'package:live_store/src/rooms.dart';
import 'package:live_store/src/secrets/secret_store.dart';
import 'package:live_store/src/settings/registry.dart';
import 'package:live_store/src/settings/setting.dart';
import 'package:live_store/src/settings/values.dart';
import 'package:live_store/src/tags.dart';
import 'package:meta/meta.dart';

/// What a backup contains (store.md §7.1).
enum BackupScope {
  /// Settings, follows, tags, history, block rules, room preferences.
  full,

  /// Follows and followed areas only.
  follows,
}

/// Thrown for a backup written by a newer app (`version` above 4).
final class BackupTooNewException implements Exception {
  /// Creates the exception for [version].
  const new(this.version);

  /// The backup's format version.
  final int version;

  @override
  String toString() => 'BackupTooNewException: backup version $version needs a newer app';
}

/// The v4 backup document (store.md §7.1–7.3).
@internal
abstract final class V4Format {
  /// Value of `format`.
  static const format = 'pure_live.backup';

  /// Value of `version`.
  static const version = 4;

  /// Sections this app writes and reads.
  static const _known = {
    'settings',
    'follows',
    'followAreas',
    'tags',
    'roomTags',
    'history',
    'blockRules',
    'roomPrefs',
    'iptv',
    'recordTasks',
  };

  /// Sections of the format this app does not store yet; restoring leaves
  /// them out (and local data unchanged).
  static const _later = {'webdavProfiles'};

  /// Whether [json] is a v4 document.
  static bool recognizes(Map<String, Object?> json) => json['format'] == format;

  /// Builds the document from [store].
  static Future<Map<String, Object?>> export(
    LiveStore store, {
    required BackupScope scope,
    required String appVersion,
    required String platform,
    required DateTime createdAt,
    SecretStore? secrets,
    String? passphrase,
    int iterations = SecretEnvelope.defaultIterations,
    RecordTaskBackup? recordTasks,
  }) async {
    final created = '${createdAt.toUtc().toIso8601String().substring(0, 19)}Z';
    final sections = <String, Object?>{
      if (scope == BackupScope.full) 'settings': store.settings.export({SettingScope.synced, SettingScope.device}),
      'follows': [
        for (final follow in await store.follows.all())
          {..._room(follow.room), 'followedAt': follow.followedAt.millisecondsSinceEpoch, 'order': follow.order},
      ],
      'followAreas': [
        for (final area in await store.followAreas.all())
          {
            'platform': area.platform,
            'namespace': area.namespace,
            'areaId': area.areaId,
            'areaName': area.areaName,
            'typeName': area.typeName,
            if (area.areaPic != null) 'areaPic': area.areaPic,
            if (area.shortName != null) 'shortName': area.shortName,
            'order': area.order,
          },
      ],
    };
    if (scope == BackupScope.full) {
      final db = store.database;
      sections['tags'] = [
        for (final tag in await store.tags.all())
          {'id': tag.id, 'name': tag.name, 'description': tag.description, 'order': tag.order},
      ];
      final membership = await db
          .customSelect(
            'SELECT r.platform, r.room_id, group_concat(t.tag, char(31)) AS tag_ids FROM room_tags t '
            'JOIN rooms r ON r.id = t.room GROUP BY r.id ORDER BY r.id',
            readsFrom: {db.roomTags, db.rooms},
          )
          .get();
      sections['roomTags'] = [
        for (final row in membership)
          {
            'platform': row.read<String>('platform'),
            'roomId': row.read<String>('room_id'),
            'tagIds': row.read<String>('tag_ids').split('\u001f'),
          },
      ];
      sections['history'] = [
        for (final entry in await store.history.all())
          {..._room(entry.room), 'lastWatchedAt': entry.lastWatchedAt?.millisecondsSinceEpoch},
      ];
      sections['blockRules'] = [
        for (final rule in await store.blockRules.all())
          {'kind': rule.kind.name, 'value': rule.value, 'createdAt': rule.createdAt.millisecondsSinceEpoch},
      ];
      final prefs = await db
          .customSelect(
            'SELECT r.platform, r.room_id, p.key, p.value FROM room_prefs p JOIN rooms r ON r.id = p.room '
            'ORDER BY r.id, p.key',
            readsFrom: {db.roomPrefs, db.rooms},
          )
          .get();
      sections['roomPrefs'] = [
        for (final row in prefs)
          {
            'platform': row.read<String>('platform'),
            'roomId': row.read<String>('room_id'),
            'key': row.read<String>('key'),
            'value': jsonDecode(row.read<String>('value')),
          },
      ];
      // Recording tasks live in the recorder's own file (spec/modules/record.md §13).
      if (recordTasks != null) {
        sections['recordTasks'] = [
          for (final (index, task) in (await recordTasks.exportTasks()).indexed) task.toJson(order: index),
        ];
      }
      // URL playlists and guides only: an imported file stays on its device,
      // and channels and programmes come back with the next sync (iptv.md §7).
      sections['iptv'] = {
        'playlists': [
          for (final playlist in await store.iptv.playlists())
            if (playlist.isRemote)
              {
                'name': playlist.name,
                'url': playlist.source,
                if (playlist.userAgent != null) 'userAgent': playlist.userAgent,
                'autoSync': playlist.autoSync,
                'order': playlist.order,
              },
        ],
        'epgSources': [
          for (final guide in await store.iptv.guideSources())
            if (guide.isRemote)
              {
                'name': guide.name,
                'url': guide.source,
                'autoSync': guide.autoSync,
                'selected': guide.selected,
                'order': guide.order,
              },
        ],
      };
    }
    Map<String, Object?>? sealed;
    if (passphrase != null && secrets != null && scope == BackupScope.full) {
      if (passphrase.isEmpty) throw ArgumentError.value('', 'passphrase', 'Must not be empty');
      sealed = await SecretEnvelope.seal(
        secrets.exportAll(),
        passphrase,
        associatedData: '$format|$version|$created',
        iterations: iterations,
      );
    }
    return {
      'format': format,
      'version': version,
      'createdAt': created,
      'app': {'version': appVersion, 'platform': platform},
      'scope': scope.name,
      'sections': sections,
      'secrets': sealed,
    };
  }

  static Map<String, Object?> _room(StoredRoom room) => {
    'platform': room.ref.platform,
    'roomId': room.ref.roomId,
    'nick': room.anchorName,
    'title': room.title,
    if (room.avatar != null) 'avatar': room.avatar.toString(),
    if (room.cover != null) 'cover': room.cover.toString(),
    if (room.area != null) 'area': room.area,
    if (room.userId != null) 'userId': room.userId,
  };

  /// Builds a plan from a v4 document. Throws [FormatException] for a
  /// malformed document and [BackupTooNewException] for a newer one.
  static Future<ImportPlan> parse(
    Map<String, Object?> json, {
    required bool followsOnly,
    required String localPlatform,
    required int localHistoryLimit,
    String? passphrase,
  }) async {
    final plan = ImportPlan();
    final report = plan.report..format = 'v4';
    final docVersion = json['version'];
    if (docVersion is! int) throw const FormatException('Invalid backup version');
    if (docVersion > version) throw BackupTooNewException(docVersion);
    if (docVersion != version) throw const FormatException('Invalid backup version');
    final scope = json['scope'];
    if (scope != 'full' && scope != 'follows') throw const FormatException('Invalid backup scope');
    plan.followsOnlySource = scope == 'follows';
    final sections = json['sections'];
    if (sections is! Map<String, Object?>) throw const FormatException('Missing backup sections');
    for (final name in sections.keys) {
      if (_later.contains(name)) {
        report.note(name, 'unsupported');
      } else if (!_known.contains(name)) {
        report.note('backup', 'unknownSection', name);
      }
    }

    final follows = _list(sections, 'follows', report, (item) {
      final room = _importedRoom(item, report, 'follows');
      if (room == null) return null;
      return (PlannedFollow(room, followedAt: JsonRead.millis(item['followedAt']) ?? DateTime.utc(1970)), _order(item));
    });
    if (follows != null) plan.follows = _ordered(follows, report);
    final areas = _list(sections, 'followAreas', report, (item) {
      final area = FollowedArea(
        platform: JsonRead.text(item['platform']) ?? '',
        namespace: JsonRead.text(item['namespace']) ?? '',
        areaId: JsonRead.text(item['areaId']) ?? '',
        areaName: JsonRead.text(item['areaName']) ?? '',
        typeName: JsonRead.text(item['typeName']) ?? '',
        areaPic: JsonRead.nonEmpty(item['areaPic']),
        shortName: JsonRead.nonEmpty(item['shortName']),
        order: _order(item),
      );
      if (!area.isValid) {
        report.drop('followAreas', 'invalidItem', area.key);
        return null;
      }
      return area;
    });
    if (areas != null) plan.followAreas = _uniqueAreas(areas, report);
    if (followsOnly || plan.followsOnlySource) {
      _countWritten(plan);
      return plan;
    }

    final settings = sections['settings'];
    if (settings != null) {
      if (settings is! Map<String, Object?>) throw const FormatException('Invalid backup section: settings');
      final app = JsonRead.object(json['app']);
      plan
        ..includeDeviceSettings = app?['platform'] == localPlatform
        ..replaceSettings = true
        ..settings = _settings(settings, report, includeDevice: plan.includeDeviceSettings);
    }
    final tags = _list(sections, 'tags', report, (item) {
      final id = JsonRead.nonEmpty(item['id']);
      final name = JsonRead.nonEmpty(item['name']);
      if (id == null || name == null) {
        report.drop('tags', 'invalidItem', id);
        return null;
      }
      return Tag(id: id, name: name, description: JsonRead.text(item['description']) ?? '', order: _order(item));
    });
    if (tags != null) plan.tags = _uniqueTags(tags, report);
    final tagIds = plan.tags?.map((tag) => tag.id).toSet();
    final roomTags = _list(sections, 'roomTags', report, (item) {
      final ref = _ref(item, report, 'roomTags');
      final ids = item['tagIds'];
      if (ref == null || ids is! List) return null;
      return (ref, {for (final id in ids) ?JsonRead.nonEmpty(id)});
    });
    if (roomTags != null) {
      final membership = <RoomRef, Set<String>>{};
      for (final (ref, ids) in roomTags) {
        for (final id in ids) {
          if (tagIds != null && !tagIds.contains(id)) {
            report.drop('roomTags', 'unknownTag', id);
          } else {
            membership.putIfAbsent(ref, () => {}).add(id);
          }
        }
      }
      plan.roomTags = membership;
    }
    final settingsLimit = plan.settings?[Settings.historyLimit.id] as int?;
    final limit = settingsLimit ?? (plan.replaceSettings ? Settings.historyLimit.defaultValue : localHistoryLimit);
    final history = _list(sections, 'history', report, (item) {
      final room = _importedRoom(item, report, 'history');
      return room == null ? null : PlannedHistory(room, lastWatchedAt: JsonRead.millis(item['lastWatchedAt']));
    });
    if (history != null) plan.history = _history(history, report, limit);
    final rules = _list(sections, 'blockRules', report, (item) {
      final kind = BlockKind.values.asNameMap()[item['kind']];
      final value = JsonRead.nonEmpty(item['value']);
      if (kind == null || value == null) {
        report.drop('blockRules', 'invalidItem', value);
        return null;
      }
      return BlockRule(kind: kind, value: value, createdAt: JsonRead.millis(item['createdAt']) ?? DateTime.utc(1970));
    });
    if (rules != null) {
      final seen = <BlockRule>{};
      plan.blockRules = {for (final kind in BlockKind.values) kind: []};
      for (final rule in rules) {
        if (!seen.add(rule)) {
          report.drop('blockRules', 'duplicate', rule.value);
        } else {
          plan.blockRules![rule.kind]!.add(rule);
        }
      }
    }
    if (sections['iptv'] case final Object iptv) plan.iptv = _iptv(iptv, report);
    final recordTasks = _list(sections, 'recordTasks', report, (item) => _recordTask(item, report));
    if (recordTasks != null) {
      final sorted = [...recordTasks.indexed]
        ..sort((a, b) => a.$2.$2 != b.$2.$2 ? a.$2.$2.compareTo(b.$2.$2) : a.$1.compareTo(b.$1));
      final seen = <RoomRef>{};
      plan.recordTasks = [
        for (final (_, (task, _)) in sorted)
          if (seen.add(task.ref)) task else ?_dropTask(task, report),
      ];
    }
    plan.roomPrefs = _list(sections, 'roomPrefs', report, (item) {
      final ref = _ref(item, report, 'roomPrefs');
      final key = JsonRead.nonEmpty(item['key']);
      final value = item['value'];
      if (ref == null || key == null || value == null) return null;
      return PlannedRoomPref(ref, key, value);
    });

    final secrets = json['secrets'];
    if (secrets != null) {
      report.secretsPresent = true;
      if (passphrase == null || passphrase.isEmpty) {
        report
          ..secretsSkipped = true
          ..note('secrets', 'locked');
      } else {
        try {
          plan.secrets = await SecretEnvelope.open(
            secrets,
            passphrase,
            associatedData: '$format|$version|${json['createdAt']}',
          );
        } on WrongPassphraseException {
          report
            ..secretsSkipped = true
            ..note('secrets', 'wrongPassphrase');
        }
      }
    }
    _countWritten(plan);
    return plan;
  }

  static void _countWritten(ImportPlan plan) {
    final report = plan.report;
    if (plan.follows case final follows?) report.written('follows', follows.length);
    if (plan.followAreas case final areas?) report.written('followAreas', areas.length);
    if (plan.settings case final settings?) report.written('settings', settings.length);
    if (plan.tags case final tags?) report.written('tags', tags.length);
    if (plan.roomTags case final roomTags?) report.written('roomTags', roomTags.length);
    if (plan.history case final history?) report.written('history', history.length);
    if (plan.blockRules case final rules?) {
      report.written('blockRules', rules.values.fold(0, (sum, list) => sum + list.length));
    }
    if (plan.roomPrefs case final prefs?) report.written('roomPrefs', prefs.length);
    if (plan.iptv case final iptv?) {
      report
        ..written('iptvPlaylists', iptv.playlists.length)
        ..written('iptvGuides', iptv.guides.length);
    }
  }

  /// The `iptv` section: `playlists` (alias `providers`) and `epgSources`,
  /// each a list of `{name, url, …}` with an http(s) URL, unique by URL.
  static PlannedIptv _iptv(Object section, ImportReport report) {
    if (section is! Map<String, Object?>) throw const FormatException('Invalid backup section: iptv');
    List<PlannedIptvSource> read(String name, Object? list, {required bool guides}) {
      if (list == null) return const [];
      if (list is! List) throw FormatException('Invalid backup section: iptv.$name');
      report.read(name, list.length);
      final items = <(int, PlannedIptvSource)>[];
      final urls = <String>{};
      for (final raw in list) {
        final item = raw is Map<String, Object?> ? raw : null;
        final url = JsonRead.nonEmpty(item?['url']);
        if (item == null || url == null || !isRemoteSource(url)) {
          report.drop(name, 'invalidItem', url);
          continue;
        }
        if (!urls.add(url)) {
          report.drop(name, 'duplicate', url);
          continue;
        }
        items.add((
          _order(item),
          PlannedIptvSource(
            name: JsonRead.nonEmpty(item['name']) ?? url,
            url: url,
            userAgent: guides ? null : JsonRead.nonEmpty(item['userAgent']),
            autoSync: item['autoSync'] != false,
            selected: guides && item['selected'] == true,
          ),
        ));
      }
      final sorted = [...items.indexed]
        ..sort((a, b) => a.$2.$1 != b.$2.$1 ? a.$2.$1.compareTo(b.$2.$1) : a.$1.compareTo(b.$1));
      return [for (final (_, (_, source)) in sorted) source];
    }

    return PlannedIptv(
      playlists: read('iptvPlaylists', section['playlists'] ?? section['providers'], guides: false),
      guides: read('iptvGuides', section['epgSources'], guides: true),
    );
  }

  static Map<String, Object> _settings(
    Map<String, Object?> values,
    ImportReport report, {
    required bool includeDevice,
  }) {
    report.read('settings', values.length);
    final result = <String, Object>{};
    for (final MapEntry(:key, :value) in values.entries) {
      final setting = Settings.byId(key);
      if (setting == null || setting.scope == SettingScope.internal) {
        report.drop('settings', 'unknownKey', key);
        continue;
      }
      if (setting.scope == SettingScope.device && !includeDevice) {
        report.drop('settings', 'otherPlatform', key);
        continue;
      }
      final decoded = setting.decode(value);
      if (decoded == null) {
        report.drop('settings', 'invalidValue', key);
        continue;
      }
      result[key] = decoded;
    }
    return result;
  }

  /// Reads section [name] as a list of objects; null when absent. Throws
  /// [FormatException] when it is not a list; items that [read] rejects
  /// (null) are skipped.
  static List<T>? _list<T extends Object>(
    Map<String, Object?> sections,
    String name,
    ImportReport report,
    T? Function(Map<String, Object?> item) read,
  ) {
    final section = sections[name];
    if (section == null) return null;
    if (section is! List) throw FormatException('Invalid backup section: $name');
    report.read(name, section.length);
    final result = <T>[];
    for (final raw in section) {
      final item = raw is Map<String, Object?> ? read(raw) : null;
      if (raw is! Map<String, Object?>) report.drop(name, 'invalidItem');
      if (item != null) result.add(item);
    }
    return result;
  }

  static int _order(Map<String, Object?> item) => JsonRead.count(item['order']) ?? 0;

  /// One `recordTasks` item (store.md §7.1): a room and how to record it.
  /// An unknown quality falls back to the default quality.
  static (BackupRecordTask, int)? _recordTask(Map<String, Object?> item, ImportReport report) {
    final ref = _ref(item, report, 'recordTasks');
    if (ref == null) return null;
    final name = item['quality'];
    final quality = QualityPreference.values.asNameMap()[name];
    if (name != null && quality == null) report.note('recordTasks', 'invalidValue', ref.key);
    return (
      BackupRecordTask(
        ref: ref,
        createdAt: JsonRead.millis(item['createdAt']) ?? DateTime.utc(1970),
        anchorName: JsonRead.text(item['nick']) ?? '',
        title: JsonRead.text(item['title']) ?? '',
        avatar: JsonRead.uri(item['avatar']),
        cover: JsonRead.uri(item['cover']),
        quality: quality,
        autoReconnect: item['autoReconnect'] != false,
        monitor: item['monitor'] == true,
      ),
      _order(item),
    );
  }

  static BackupRecordTask? _dropTask(BackupRecordTask task, ImportReport report) {
    report.drop('recordTasks', 'duplicate', task.ref.key);
    return null;
  }

  static RoomRef? _ref(Map<String, Object?> item, ImportReport report, String section) {
    final platform = JsonRead.text(item['platform']) ?? '';
    final roomId = JsonRead.text(item['roomId']) ?? '';
    try {
      return RoomRef(platform, roomId);
    } on FormatException {
      report.drop(section, 'invalidRoom', '$platform:$roomId');
      return null;
    }
  }

  static ImportedRoom? _importedRoom(Map<String, Object?> item, ImportReport report, String section) {
    final ref = _ref(item, report, section);
    if (ref == null) return null;
    return ImportedRoom(
      RoomSnapshot(
        ref: ref,
        anchorName: JsonRead.nonEmpty(item['nick']),
        title: JsonRead.nonEmpty(item['title']),
        avatar: JsonRead.uri(item['avatar']),
        cover: JsonRead.uri(item['cover']),
        area: JsonRead.nonEmpty(item['area']),
        userId: JsonRead.nonEmpty(item['userId']),
      ),
    );
  }

  static List<PlannedFollow> _ordered(List<(PlannedFollow, int)> items, ImportReport report) {
    final sorted = [...items.indexed]
      ..sort((a, b) => a.$2.$2 != b.$2.$2 ? a.$2.$2.compareTo(b.$2.$2) : a.$1.compareTo(b.$1));
    return dedupeRooms(
      [for (final (_, (follow, _)) in sorted) follow],
      (follow) => follow.room.ref,
      (first, later) => PlannedFollow(first.room.fillFrom(later.room), followedAt: first.followedAt),
      report: report,
      section: 'follows',
    );
  }

  static List<FollowedArea> _uniqueAreas(List<FollowedArea> areas, ImportReport report) {
    final sorted = [...areas]..sort((a, b) => a.order.compareTo(b.order));
    final seen = <String>{};
    return [
      for (final area in sorted)
        if (seen.add(area.key)) area else ?_dropArea(area, report),
    ];
  }

  static FollowedArea? _dropArea(FollowedArea area, ImportReport report) {
    report.drop('followAreas', 'duplicate', area.key);
    return null;
  }

  static List<Tag> _uniqueTags(List<Tag> tags, ImportReport report) {
    final sorted = [...tags]..sort((a, b) => a.order.compareTo(b.order));
    final ids = <String>{};
    final names = <String>{};
    final result = <Tag>[];
    for (final tag in sorted) {
      if (!ids.add(tag.id) || !names.add(TagStore.fold(tag.name))) {
        report.drop('tags', 'duplicate', tag.name);
        continue;
      }
      result.add(Tag(id: tag.id, name: tag.name, description: tag.description, order: result.length));
    }
    return result;
  }

  static List<PlannedHistory> _history(List<PlannedHistory> entries, ImportReport report, int limit) {
    var result = dedupeRooms(
      entries,
      (entry) => entry.room.ref,
      (first, later) => PlannedHistory(first.room.fillFrom(later.room), lastWatchedAt: first.lastWatchedAt),
      report: report,
      section: 'history',
    );
    if (limit > 0 && result.length > limit) {
      for (final entry in result.skip(limit)) {
        report.drop('history', 'overLimit', entry.room.ref.key);
      }
      result = result.take(limit).toList();
    }
    return result;
  }
}
