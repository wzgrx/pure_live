import 'package:live_store/live_store.dart';
import 'package:pure_live/shared/backup/backup_data.dart';

/// A part of the data device sync can send or take on its own
/// (docs/J-设置和数据/J05-设备同步/J05.1-同步前勾选内容): the parts of
/// [BackupService]'s file, which is what device sync carries.
enum SyncPart {
  /// Every setting (playback, danmaku, look, home, …).
  settings('remote_sync_part_settings'),

  /// Followed rooms.
  follows('backup_part_follows'),

  /// Followed areas.
  areas('backup_part_areas'),

  /// Watch history.
  history('backup_part_history'),

  /// Follow groups.
  tags('backup_part_tags'),

  /// Danmaku keyword blocks.
  keywords('backup_part_keywords'),

  /// Danmaku user blocks.
  users('backup_part_users'),

  /// WebDAV servers (only with "同步账号 Cookie").
  webdav('backup_part_webdav'),

  /// Platform sign-ins (only with "同步账号 Cookie").
  accounts('remote_sync_part_accounts'),

  /// The local interaction's history (D08.1 c4): offered, not ticked
  /// ([optIn]).
  localEvents('backup_part_local_events');

  new(this.labelKey);

  /// Translation key of the name.
  final String labelKey;

  /// Whether its box starts unticked (D08.1 c4: the local history is this
  /// device's own unless asked for).
  bool get optIn => this == localEvents;

  /// The sync part of a restore preview's [kind]; null for the parts device
  /// sync does not carry (search words, IPTV playlists, multi-view).
  static SyncPart? of(RestorePartKind kind) => switch (kind) {
    RestorePartKind.follows => follows,
    RestorePartKind.areas => areas,
    RestorePartKind.history => history,
    RestorePartKind.tags => tags,
    RestorePartKind.keywords => keywords,
    RestorePartKind.users => users,
    RestorePartKind.webdav => webdav,
    RestorePartKind.localEvents => localEvents,
    RestorePartKind.search || RestorePartKind.iptv || RestorePartKind.multiview => null,
  };
}

/// Keys of a backup that describe the file rather than hold data; a pick
/// keeps them.
const Set<String> _fileKeys = {'backupVersion', 'sensitiveDataIncluded', 'backupScope'};

/// Sections that are one part each.
const Map<String, SyncPart> _wholeSections = {
  'tags': SyncPart.tags,
  'webdav': SyncPart.webdav,
  'cookie': SyncPart.accounts,
  LocalEventStore.backupSection: SyncPart.localEvents,
};

/// Lists inside a section that are one part each; the rest of those
/// sections are settings (`hotAreasList`, `historyLimit`, …).
const Map<String, Map<String, SyncPart>> _listsIn = {
  'favorite': {
    'favoriteRooms': SyncPart.follows,
    'favoriteAreas': SyncPart.areas,
    'shieldList': SyncPart.keywords,
    'blockedDanmakuUsers': SyncPart.users,
  },
  'history': {'historyRooms': SyncPart.history},
};

SyncPart _partOf(String section, String key) => _wholeSections[section] ?? _listsIn[section]?[key] ?? SyncPart.settings;

/// Whether the parts of [data] can be picked apart: the sectioned backup
/// (`backupVersion` 2 and up), which 3.x and v4 both send; 3.x's old flat
/// file goes whole.
bool syncPartsSplittable(Map<String, Object?> data) => data['backupVersion'] != null;

/// The parts [data] (a sectioned backup) holds, in [SyncPart] order.
List<SyncPart> syncPartsIn(Map<String, Object?> data) {
  final found = <SyncPart>{};
  for (final MapEntry(key: section, :value) in data.entries) {
    if (_fileKeys.contains(section) || value is! Map) continue;
    if (_wholeSections[section] case final part?) {
      found.add(part);
      continue;
    }
    for (final key in value.keys) {
      found.add(_partOf(section, '$key'));
    }
  }
  return [
    for (final part in SyncPart.values)
      if (found.contains(part)) part,
  ];
}

/// Whether [parts] leave out something [data] holds (null leaves out
/// nothing; neither does a flat file).
bool syncPartsLeaveOut(Map<String, Object?> data, Set<SyncPart>? parts) =>
    parts != null && syncPartsSplittable(data) && !syncPartsIn(data).every(parts.contains);

/// [data] when [parts] leave nothing out of it, [pickSyncParts] otherwise.
Map<String, Object?> onlySyncParts(Map<String, Object?> data, Set<SyncPart>? parts) =>
    syncPartsLeaveOut(data, parts) ? pickSyncParts(data, parts!) : data;

/// [data] (a sectioned backup) with only the [parts] chosen: the other
/// lists and sections are left out, so a v4 restore leaves them as they are
/// (`BackupService.restoreAll` replaces only what the file has). Sections
/// left empty go too. A flat file ([syncPartsSplittable] false) comes back
/// as it is.
Map<String, Object?> pickSyncParts(Map<String, Object?> data, Set<SyncPart> parts) {
  if (!syncPartsSplittable(data)) return data;
  final picked = <String, Object?>{};
  for (final MapEntry(key: section, :value) in data.entries) {
    if (_fileKeys.contains(section)) {
      picked[section] = value;
    } else if (value is! Map) {
      // Not a section (an unknown value): it travels with the settings.
      if (parts.contains(SyncPart.settings)) picked[section] = value;
    } else if (_wholeSections[section] case final part?) {
      if (parts.contains(part)) picked[section] = value;
    } else {
      final kept = {
        for (final MapEntry(:key, value: field) in value.entries)
          if (parts.contains(_partOf(section, '$key'))) '$key': field,
      };
      if (kept.isNotEmpty) picked[section] = kept;
    }
  }
  if (picked.containsKey('sensitiveDataIncluded')) {
    picked['sensitiveDataIncluded'] = picked.containsKey('cookie') || picked.containsKey('webdav');
  }
  return picked;
}

/// The sections of [data] that hold data (what the packet's `sections`
/// lists, upstream pure_live `9483ccf03`'s meaning).
List<String> syncSectionsOf(Map<String, Object?> data) => [
  for (final key in data.keys)
    if (!_fileKeys.contains(key)) key,
];

/// [data] with only the [sections] a packet lists (and the file keys); all
/// of it when the packet lists none (3.x and older v4 senders, a whole
/// send).
Map<String, Object?> withinSyncSections(Map<String, Object?> data, List<String>? sections) {
  if (sections == null || sections.isEmpty) return data;
  final wanted = sections.toSet();
  return {
    for (final MapEntry(:key, :value) in data.entries)
      if (_fileKeys.contains(key) || wanted.contains(key)) key: value,
  };
}

/// How many entries each part of [data] has (settings, rooms, words,
/// servers, sign-ins), read the way a restore reads them; parts the file
/// does not have are left out.
Map<SyncPart, int> syncPartCounts(Map<String, Object?> data) {
  final snapshot = LegacySnapshot.fromBackup(data);
  final settings = snapshot.settings.length;
  return {
    if (settings > 0) SyncPart.settings: settings,
    if (snapshot.follows case final rooms?) SyncPart.follows: rooms.length,
    if (snapshot.followAreas case final areas?) SyncPart.areas: areas.length,
    if (snapshot.history case final rooms?) SyncPart.history: rooms.length,
    if (snapshot.tags != null || snapshot.roomTags != null) SyncPart.tags: snapshot.tags?.length ?? 0,
    if (snapshot.blockedKeywords case final words?) SyncPart.keywords: words.length,
    if (snapshot.blockedUsers case final users?) SyncPart.users: users.length,
    if (snapshot.webdav case final servers?) SyncPart.webdav: servers.length,
    if (snapshot.secrets != null || snapshot.savedAccounts != null) SyncPart.accounts: accountEntriesIn(snapshot),
    if (LocalEventStore.inBackup(data) case final events?) SyncPart.localEvents: events.length,
  };
}
