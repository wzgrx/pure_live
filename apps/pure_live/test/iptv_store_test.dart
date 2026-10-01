import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/iptv_legacy.dart';
import 'package:pure_live/app/iptv_library.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support.dart';

const _playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="cctv1" group-title="央视" catchup="append" catchup-source="&s={utc}",CCTV-1
https://f/cctv1.m3u8|user-agent=TV
#EXTINF:-1 group-title="卫视",湖南卫视
https://f/hunan.m3u8
''';

const _reordered = '''
#EXTM3U
#EXTINF:-1 group-title="卫视",湖南卫视
https://f/hunan.m3u8
#EXTINF:-1 tvg-id="cctv1" group-title="央视" catchup="append" catchup-source="&s={utc}",CCTV-1
https://f/cctv1.m3u8|user-agent=TV
''';

const _guide = '''
<tv>
<channel id="cctv1"><display-name>CCTV-1 综合</display-name></channel>
<channel id="hunan"><display-name>湖南卫视</display-name></channel>
<programme channel="cctv1" start="20261001110000 +0000" stop="20261001130000 +0000"><title>新闻</title></programme>
</tv>''';

/// 3.x's drift tables at schema 9 (`lib/core/iptv/local/tables.dart`), as
/// drift created them: snake_case columns, Unix seconds, 0/1 flags.
const _v3Schema = '''
CREATE TABLE "providers" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "type" TEXT NOT NULL, "url" TEXT NULL, "username" TEXT NULL, "password" TEXT NULL, "sort_order" INTEGER NOT NULL DEFAULT 0, "enabled" INTEGER NOT NULL DEFAULT 1, "last_refresh" INTEGER NULL, "created_at" INTEGER NOT NULL, "is_auto_update" INTEGER NOT NULL DEFAULT 1, PRIMARY KEY ("id"));
CREATE TABLE "channels" ("id" TEXT NOT NULL, "provider_id" TEXT NOT NULL REFERENCES providers (id), "name" TEXT NOT NULL, "tvg_id" TEXT NULL, "tvg_name" TEXT NULL, "tvg_logo" TEXT NULL, "group_title" TEXT NULL, "channel_number" INTEGER NULL, "stream_url" TEXT NOT NULL, "stream_type" TEXT NOT NULL DEFAULT 'live', "favorite" INTEGER NOT NULL DEFAULT 0, "hidden" INTEGER NOT NULL DEFAULT 0, "sort_order" INTEGER NOT NULL DEFAULT 0, "is_auto_update" INTEGER NOT NULL DEFAULT 1, "catchup_mode" TEXT NULL, "catchup_source" TEXT NULL, "catchup_days" REAL NULL, "catchup_correction_hours" REAL NULL, "http_headers_json" TEXT NULL, PRIMARY KEY ("id"));
CREATE TABLE "epg_sources" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "url" TEXT NOT NULL, "enabled" INTEGER NOT NULL DEFAULT 1, "refresh_interval_hours" INTEGER NOT NULL DEFAULT 12, "last_refresh" INTEGER NULL, "created_at" INTEGER NOT NULL, "is_auto_update" INTEGER NOT NULL DEFAULT 1, PRIMARY KEY ("id"));
CREATE TABLE "epg_channels" ("id" TEXT NOT NULL, "source_id" TEXT NOT NULL, "channel_id" TEXT NOT NULL, "display_name" TEXT NOT NULL, "icon_url" TEXT NULL, PRIMARY KEY ("id"));
CREATE TABLE "epg_programmes" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "epg_channel_id" TEXT NOT NULL, "source_id" TEXT NOT NULL, "title" TEXT NOT NULL, "description" TEXT NULL, "start" INTEGER NOT NULL, "stop" INTEGER NOT NULL, "subtitle" TEXT NULL, "episode_num" TEXT NULL, "category" TEXT NULL, "catchup_id" TEXT NULL);
CREATE TABLE "epg_mappings" ("channel_id" TEXT NOT NULL, "provider_id" TEXT NOT NULL, "epg_channel_id" TEXT NOT NULL, "epg_source_id" TEXT NOT NULL, "confidence" REAL NOT NULL DEFAULT 0.0, "source" TEXT NOT NULL DEFAULT 'auto', "locked" INTEGER NOT NULL DEFAULT 0, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("channel_id", "provider_id"));
CREATE TABLE "favorite_lists" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, PRIMARY KEY ("id"));
PRAGMA user_version = 9;
''';

int _seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

/// Writes a 3.x data root (`PURE_LIVE` with `HIVE_DB` and `IPTV_CACHE`) under
/// [parent]; returns the settings box path.
String _write3x(Directory parent) {
  final root = p.join(parent.path, 'PURE_LIVE');
  final hive = File(p.join(root, 'HIVE_DB', 'app_settings.hive'))..createSync(recursive: true);
  final local = File(p.join(root, 'IPTV_CACHE', 'playlist_local.txt'))
    ..createSync(recursive: true)
    ..writeAsStringSync('本地,#genre#\n凤凰,https://f/fh.m3u8\n');
  final path = p.join(root, 'IPTV_CACHE', 'pure_live_tv', 'pure_live_tv.db');
  Directory(p.dirname(path)).createSync(recursive: true);
  final db = sqlite3.open(path)..execute(_v3Schema);
  final refreshed = _seconds(DateTime.utc(2026, 9, 30, 8));
  final key = epgChannelKey('g1', 'cctv1');
  void insert(String table, Map<String, Object?> row) => db.execute(
    'INSERT INTO $table (${row.keys.join(', ')}) VALUES (${List.filled(row.length, '?').join(', ')})',
    row.values.toList(),
  );
  insert('providers', {
    'id': 'p-remote',
    'name': 'CN',
    'type': 'm3u',
    'url': 'https://f/cn.m3u',
    'last_refresh': refreshed,
    'created_at': refreshed,
  });
  insert('providers', {
    'id': 'p-local',
    'name': '本地',
    'type': 'txt',
    'url': local.path,
    'created_at': refreshed,
    'is_auto_update': 0,
  });
  insert('providers', {'id': '88888', 'name': 'hot', 'type': 'm3u', 'url': 'https://f/hot.m3u', 'created_at': 0});
  insert('providers', {'id': 'x-1', 'name': 'Xtream', 'type': 'xtream', 'url': 'https://x', 'created_at': 0});
  insert('channels', {
    'id': 'c2',
    'provider_id': 'p-remote',
    'name': '湖南卫视',
    'group_title': '卫视',
    'stream_url': 'https://f/hunan.m3u8',
  });
  insert('channels', {
    'id': 'c1',
    'provider_id': 'p-remote',
    'name': 'CCTV-1',
    'tvg_id': 'cctv1',
    'group_title': '央视',
    'stream_url': 'https://f/cctv1.m3u8',
    'catchup_mode': 'append',
    'catchup_source': '&s={utc}',
    'catchup_days': 7.0,
    'http_headers_json': '{"user-agent":"TV"}',
    'is_auto_update': 0,
  });
  insert('channels', {'id': 'c3', 'provider_id': 'p-local', 'name': '凤凰', 'stream_url': 'https://f/fh.m3u8'});
  insert('channels', {'id': 'c4', 'provider_id': '88888', 'name': 'Hot 1', 'stream_url': 'https://f/h1.m3u8'});
  insert('channels', {'id': 'c5', 'provider_id': 'x-1', 'name': 'X', 'stream_url': 'https://x/1'});
  insert('epg_sources', {
    'id': 'g1',
    'name': 'zsdc',
    'url': 'https://f/epg.xml.gz',
    'last_refresh': refreshed,
    'created_at': refreshed,
  });
  insert('epg_channels', {'id': key, 'source_id': 'g1', 'channel_id': 'cctv1', 'display_name': 'CCTV-1 综合'});
  insert('epg_programmes', {
    'epg_channel_id': key,
    'source_id': 'g1',
    'title': '新闻',
    'start': _seconds(DateTime.utc(2026, 10, 1, 11)),
    'stop': _seconds(DateTime.utc(2026, 10, 1, 13)),
  });
  insert('epg_programmes', {
    'epg_channel_id': key,
    'source_id': 'g1',
    'title': 'Old',
    'start': _seconds(DateTime.utc(2026, 9, 20, 11)),
    'stop': _seconds(DateTime.utc(2026, 9, 20, 13)),
  });
  insert('epg_mappings', {
    'channel_id': 'c1',
    'provider_id': 'p-remote',
    'epg_channel_id': key,
    'epg_source_id': 'g1',
    'source': 'manual',
    'locked': 1,
    'updated_at': refreshed,
  });
  db.close();
  return hive.path;
}

/// Every file under [directory] with its bytes.
Map<String, List<int>> _files(Directory directory) => {
  for (final entity in directory.listSync(recursive: true))
    if (entity is File) entity.path: entity.readAsBytesSync(),
};

void main() {
  final clock = DateTime.utc(2026, 10, 1, 12);
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('pure_live_iptv_store'));
  tearDown(() => directory.deleteSync(recursive: true));

  test('playlists, channels, mappings and guides are written to pure_live.db and read back after a reopen', () async {
    var selected = '';
    var ids = 0;
    IptvImporter importerOver(IptvLibrary library) => IptvImporter(
      library: library,
      http: NoNetworkHttp(),
      playlistDirectory: iptvPlaylistDirectory(directory),
      selectedGuideSourceId: () => selected,
      now: () => clock,
      newId: () => 'id-${++ids}',
    );

    var store = await LiveStore.open(directory, cipher: FakeCipher());
    var library = StoreIptvLibrary(store);
    var importer = importerOver(library);
    final guide = await importer.importGuide(bytes: utf8.encode(_guide), name: 'zsdc', source: 'https://f/epg.xml');
    expect(guide.status, IptvImportStatus.imported);
    selected = guide.id!;
    expect((await importer.importPlaylistText(_playlist, 'cn.m3u')).status, IptvImportStatus.imported);
    final playlist = (await library.playlists()).single;
    final channels = await library.channels(playlist.id);
    final mappings = await library.mappings(playlist.id);
    expect(mappings, isNotEmpty);
    await store.close();
    expect(File(p.join(directory.path, LiveStore.fileName)).existsSync(), isTrue);

    store = await LiveStore.open(directory, cipher: FakeCipher());
    library = StoreIptvLibrary(store);
    expect(await library.playlists(), [playlist]);
    final reopened = await library.channels(playlist.id);
    expect([for (final channel in reopened) channel.id], [for (final channel in channels) channel.id]);
    expect(
      [for (final channel in reopened) channel.entry.contentKey],
      [for (final channel in channels) channel.entry.contentKey],
    );
    expect(reopened.first.entry.httpHeaders, {'user-agent': 'TV'});
    expect(reopened.first.entry.catchupMode, 'append');
    expect(await library.mappings(playlist.id), mappings);
    final source = (await library.guideSources()).single;
    final key = epgChannelKey(source.id, 'cctv1');
    expect([for (final channel in await library.guideChannels(source.id)) channel.key], contains(key));
    final onAir = (await library.programmesAt({key}, clock)).single;
    expect(onAir.title, '新闻');
    expect(onAir.start.isAtSameMomentAs(DateTime.utc(2026, 10, 1, 11)), isTrue);
    expect(onAir.channelKey, key);
    expect(await library.programmes(key, from: clock.subtract(const Duration(days: 1)), to: clock), isEmpty);
    expect([for (final channel in await library.searchChannels('cctv')) channel.name], ['CCTV-1']);

    // A sync after the reopen keeps the ids and follows the file order.
    importer = importerOver(library);
    expect((await importer.importPlaylistText(_reordered, 'cn.m3u', force: true)).status, IptvImportStatus.imported);
    final current = (await library.playlists()).single;
    expect(
      [for (final channel in await library.channels(current.id)) channel.id],
      [for (final channel in channels.reversed) channel.id],
    );

    // A stale snapshot writes nothing.
    await expectLater(
      library.savePlaylist(current.copyWith(name: 'other'), const [], expected: playlist),
      throwsA(isA<StaleIptvSnapshot>()),
    );
    expect((await library.playlists()).single.name, 'cn');
    expect(await library.channels(current.id), hasLength(2));

    // Deleting the guide drops the mappings to it; deleting the playlist its channels.
    expect(await library.deleteGuideSource(source), isTrue);
    expect(await library.mappings(current.id), isEmpty);
    expect(await importer.deletePlaylist(current), isTrue);
    expect(await library.channels(current.id), isEmpty);
    expect(await store.meta.get(StoreIptvLibrary.schemaKey), '${StoreIptvLibrary.schemaVersion}');
    await store.close();
  });

  test("3.x's pure_live_tv.db is imported once, read-only, with its channel ids", () async {
    final hive = _write3x(directory);
    final databases = legacyIptvDatabases([hive]);
    expect(databases, [p.join(directory.path, 'PURE_LIVE', 'IPTV_CACHE', 'pure_live_tv', 'pure_live_tv.db')]);
    final before = _files(directory);

    final data = Directory(p.join(directory.path, 'v4'));
    final store = await LiveStore.open(data, cipher: FakeCipher());
    final library = StoreIptvLibrary(store);
    final report = await LegacyIptvMigration.importDatabases(
      store,
      library,
      databases,
      playlistDirectory: iptvPlaylistDirectory(data),
      now: () => clock,
    );
    expect(report.importedSources, 1);
    expect(report.playlists, 3);
    expect(report.channels, 4);
    expect(report.guides, 1);
    expect(report.skipped, contains(startsWith('playlist x-1')));

    final playlists = await library.playlists();
    expect([for (final playlist in playlists) playlist.id], ['p-remote', 'p-local', IptvPlaylist.hotId]);
    final remote = playlists.first;
    expect(remote.source, 'https://f/cn.m3u');
    expect(remote.lastRefresh!.isAtSameMomentAs(DateTime.utc(2026, 9, 30, 8)), isTrue);
    final channels = await library.channels('p-remote');
    expect([for (final channel in channels) channel.id], ['c2', 'c1']);
    final cctv = channels.last;
    expect(cctv.entry.httpHeaders, {'user-agent': 'TV'});
    expect(cctv.entry.catchupDays, 7.0);
    expect(cctv.autoUpdate, isFalse);
    expect(await library.mappings('p-remote'), [
      EpgMapping(
        channelId: 'c1',
        playlistId: 'p-remote',
        epgChannelKey: epgChannelKey('g1', 'cctv1'),
        epgSourceId: 'g1',
        origin: 'manual',
        locked: true,
      ),
    ]);
    // The local playlist now syncs from the app's own copy.
    final local = playlists[1];
    expect(local.autoUpdate, isFalse);
    expect(p.isWithin(iptvPlaylistDirectory(data).path, local.source), isTrue);
    expect(File(local.source).readAsStringSync(), contains('凤凰'));
    // Programmes still within the importer's two days only.
    final programmes = await library.programmesAt({epgChannelKey('g1', 'cctv1')}, clock);
    expect([for (final programme in programmes) programme.title], ['新闻']);
    expect(await library.programmes(epgChannelKey('g1', 'cctv1'), from: DateTime.utc(2026), to: clock), isEmpty);

    // 3.x's folder is untouched: same files, same bytes, no journal or lock files.
    expect(_files(Directory(p.join(directory.path, 'PURE_LIVE'))), {
      for (final entry in before.entries)
        if (p.isWithin(p.join(directory.path, 'PURE_LIVE'), entry.key)) entry.key: entry.value,
    });

    // Recorded in the ledger: the next start skips it.
    final again = await LegacyIptvMigration.importDatabases(
      store,
      library,
      databases,
      playlistDirectory: iptvPlaylistDirectory(data),
      now: () => clock,
    );
    expect(again.alreadyImported, 1);
    expect(again.playlists, 0);
    expect(await library.playlists(), hasLength(3));
    await store.close();

    // What the library already has wins (same name, case-insensitive).
    final other = await LiveStore.memory(cipher: FakeCipher());
    final otherLibrary = StoreIptvLibrary(other);
    await otherLibrary.savePlaylist(
      const IptvPlaylist(id: 'mine', name: 'cn', format: IptvPlaylistFormat.m3u, source: 'https://mine'),
      const [],
      expected: null,
    );
    final merged = await LegacyIptvMigration.importDatabases(
      other,
      otherLibrary,
      databases,
      playlistDirectory: iptvPlaylistDirectory(data),
      now: () => clock,
    );
    expect(merged.playlists, 2);
    expect([for (final playlist in await otherLibrary.playlists()) playlist.id], ['mine', 'p-local', '88888']);
    expect(await otherLibrary.channel('c1'), isNull);
    await other.close();
  });
}
