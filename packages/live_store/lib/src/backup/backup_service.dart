import 'dart:convert';
import 'dart:io';

import 'package:live_store/src/block_lists.dart';
import 'package:live_store/src/legacy/legacy_snapshot.dart';
import 'package:live_store/src/live_store.dart';
import 'package:live_store/src/local_events.dart';
import 'package:live_store/src/secrets.dart';
import 'package:live_store/src/settings/setting.dart';
import 'package:live_store/src/settings/settings.dart';
import 'package:live_store/src/webdav.dart';

/// Backups in 3.x's file layout (backup_controller.dart at v3.2.11), so
/// files move both ways between 3.x and v4.
///
/// - Written with `backupVersion: 4` and 3.x's sections; 3.x reads any
///   version above 3 as "latest compatible" and ignores the keys it does
///   not know (v4's new settings, `startedAt`, the local interaction's
///   history in `localEvents`, D08.1).
/// - Read: the flat format without a version, versions 2..4, and the
///   follows-only file (`backupScope: favorites`).
/// - Accounts (`cookie`, `webdav` with passwords) only when asked, as in
///   3.x; the remembered sign-ins (V01.2) travel in `cookie` as
///   `<site>Accounts`.
final class BackupService {
  /// Creates the service for `store`.
  new(this._store);

  final LiveStore _store;
  bool _restoring = false;

  /// The version written.
  static const int version = 4;

  /// Everything as 3.x's full backup; [includeSensitiveData] adds cookies
  /// and WebDAV passwords (3.x `exportAllSettings`).
  Future<Map<String, Object?>> exportAll({bool includeSensitiveData = false}) async {
    final sections = <String, Map<String, Object?>>{};
    for (final setting in Settings.all) {
      if (setting.scope == SettingScope.internal) continue;
      final value = _store.settings.get(setting);
      sections.putIfAbsent(setting.section, () => {})[setting.backupKey] = setting == Settings.pageSizeOptions
          ? [for (final part in (value as String).split(',')) ?int.tryParse(part.trim())]
          : setting.encode(value);
    }
    sections.putIfAbsent('favorite', () => {}).addAll({
      'shieldList': await _store.blockLists.list(BlockKind.keyword),
      'blockedDanmakuUsers': await _store.blockLists.list(BlockKind.user),
      'favoriteRooms': [for (final room in await _store.follows.all()) room.toJson()],
      'favoriteAreas': [for (final area in await _store.followAreas.all()) area.toJson()],
    });
    sections.putIfAbsent('history', () => {})['historyRooms'] = [
      for (final room in await _store.history.all()) room.toJson(),
    ];
    final tags = await _store.tags.all();
    sections['tags'] = {
      'tags': [for (var i = 0; i < tags.length; i++) tags[i].toJson(i)],
      'roomTagsMap': await _store.tags.assignments(),
    };
    // D08.1: the local interaction's history, when there is any (3.x
    // ignores the section; a file without it leaves the history as it is).
    final events = await _store.localEvents.all();
    if (events.isNotEmpty) {
      sections[LocalEventStore.backupSection] = {
        'events': [for (final event in events) event.toJson()],
      };
    }
    if (includeSensitiveData) {
      final current = await _store.webdav.current();
      sections['webdav'] = {
        'currentWebDavConfig': current == null ? '' : jsonEncode(current.toJson()),
        'webDavConfigs': [for (final config in await _store.webdav.all()) config.toJson()],
      };
      final secrets = _store.secrets;
      sections['cookie'] = {
        for (final site in secrets.cookieSites) '${site}Cookie': secrets.cookieFor(site),
        'douyuLtp0': secrets.read(SecretRefs.douyuLtp0) ?? '',
        'douyuDid': secrets.read(SecretRefs.douyuDid) ?? '',
        'bilibiliUid': _store.settings.get(Settings.bilibiliUid),
        'douyuCookieSavedAt': _store.settings.get(Settings.douyuCookieSavedAt),
        // The remembered sign-ins (V01.2) go where the cookies go; 3.x
        // ignores the key.
        for (final site in _store.accounts.sites)
          '$site${LegacySnapshot.accountsSuffix}': [for (final account in _store.accounts.of(site)) account.toJson()],
      };
    }
    return {'backupVersion': version, 'sensitiveDataIncluded': includeSensitiveData, ...sections};
  }

  /// The follows-only file: followed rooms and areas, nothing else (3.x
  /// `exportFavoriteSettings`).
  Future<Map<String, Object?>> exportFollows() async => {
    'backupVersion': version,
    'backupScope': 'favorites',
    'favorite': {
      'favoriteRooms': [for (final room in await _store.follows.all()) room.toJson()],
      'favoriteAreas': [for (final area in await _store.followAreas.all()) area.toJson()],
    },
  };

  /// Restores a full backup. The whole file is read and checked first
  /// ([FormatException] before anything is written); then each part the
  /// file has replaces the stored one. Parts the file does not have stay as
  /// they are (3.x reset them to defaults). A follows-only file is refused
  /// here, as in 3.x. One restore at a time ([StateError]).
  Future<void> restoreAll(Map<String, Object?> json) => _exclusive(() async {
    if (json['backupScope'] == 'favorites') {
      throw const FormatException('Favorites-only backup requires favorites restore');
    }
    final snapshot = LegacySnapshot.fromBackup(json);
    final store = _store;
    await store.settings.setAll(snapshot.settings);
    if (snapshot.follows case final rooms?) await store.follows.replaceAll(rooms);
    if (snapshot.followAreas case final areas?) await store.followAreas.replaceAll(areas);
    if (snapshot.history case final rooms?) await store.history.replaceAll(rooms);
    if (snapshot.blockedKeywords case final values?) await store.blockLists.replaceAll(BlockKind.keyword, values);
    if (snapshot.blockedUsers case final values?) await store.blockLists.replaceAll(BlockKind.user, values);
    if (snapshot.tags != null || snapshot.roomTags != null) {
      await store.tags.replaceAll(snapshot.tags ?? await store.tags.all(), snapshot.roomTags ?? const {});
    }
    if (snapshot.webdav case final configs?) {
      await store.webdav.replaceAll(
        configs,
        current: snapshot.currentWebDav == null ? null : WebDavConfig(name: snapshot.currentWebDav!, address: ''),
      );
    }
    if (snapshot.secrets case final secrets?) await store.secrets.writeAll(secrets);
    if (LocalEventStore.inBackup(json) case final events?) await store.localEvents.replaceAll(events);
    // Added to the remembered sign-ins, never replacing them: the file's
    // current cookie is the current one, the others stay switchable.
    for (final MapEntry(key: site, value: accounts) in (snapshot.savedAccounts ?? const {}).entries) {
      await store.accounts.merge(site, accounts);
    }
  });

  /// Restores only the followed rooms and areas the file has; everything
  /// else stays (3.x `restoreFavoriteSettings`). Accepts full and
  /// follows-only files.
  Future<void> restoreFollows(Map<String, Object?> json) => _exclusive(() async {
    final version = json['backupVersion'];
    if (version != null && (version is! int || version < 1)) throw const FormatException('Invalid backup version');
    final favorite = version == null ? json : json['favorite'];
    if (favorite is! Map) throw const FormatException('Invalid backup section: favorite');
    if (!favorite.containsKey('favoriteRooms') && !favorite.containsKey('favoriteAreas')) {
      throw const FormatException('No favorite lists in backup');
    }
    final snapshot = LegacySnapshot.fromBackup({
      'backupVersion': 3,
      'favorite': {
        if (favorite.containsKey('favoriteRooms')) 'favoriteRooms': favorite['favoriteRooms'],
        if (favorite.containsKey('favoriteAreas')) 'favoriteAreas': favorite['favoriteAreas'],
      },
    });
    if (snapshot.follows case final rooms?) await _store.follows.replaceAll(rooms);
    if (snapshot.followAreas case final areas?) await _store.followAreas.replaceAll(areas);
  });

  Future<void> _exclusive(Future<void> Function() action) async {
    if (_restoring) throw StateError('A settings restore is already running');
    _restoring = true;
    try {
      await action();
    } finally {
      _restoring = false;
    }
  }

  /// Writes [data] to [file] safely: a `.part` file first, the old file kept
  /// as `.previous` until the new one is in place, an interrupted earlier
  /// replacement recovered first (3.x `_writeBackup`).
  static Future<void> writeFile(File file, Map<String, Object?> data) async {
    final staged = File('${file.path}.part');
    final previous = File('${file.path}.previous');
    await file.parent.create(recursive: true);
    if (previous.existsSync()) {
      if (file.existsSync()) {
        await previous.delete();
      } else {
        await previous.rename(file.path);
      }
    }
    if (staged.existsSync()) await staged.delete();
    try {
      await staged.writeAsString(const JsonEncoder.withIndent('  ').convert(data), flush: true);
      final hadPrevious = file.existsSync();
      if (hadPrevious) await file.rename(previous.path);
      try {
        await staged.rename(file.path);
      } on FileSystemException {
        if (hadPrevious && previous.existsSync() && !file.existsSync()) await previous.rename(file.path);
        rethrow;
      }
      if (previous.existsSync()) {
        try {
          await previous.delete();
        } on FileSystemException {
          // The new backup is in place; the next write cleans up.
        }
      }
    } on Object {
      if (staged.existsSync()) await staged.delete();
      rethrow;
    }
  }

  /// Reads a backup file; [FormatException] when it is not a JSON object.
  static Future<Map<String, Object?>> readFile(File file) async {
    final data = jsonDecode(await file.readAsString());
    if (data is! Map<String, Object?>) throw const FormatException('Not a backup file');
    return data;
  }
}
