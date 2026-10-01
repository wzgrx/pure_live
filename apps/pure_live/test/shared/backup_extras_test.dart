// F.5a item 5: full backups carry the IPTV playlists and the multi-view's
// last arrangement besides the search words; 3.x's files leave them alone.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/iptv_library.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/multiview/logic/multiview_session.dart';
import 'package:pure_live/shared/backup/backup_data.dart';
import 'package:pure_live/shared/backup/backup_iptv.dart';

import '../support.dart';

final DateTime _at = DateTime(2026, 10, 1, 20);

IptvPlaylist _playlist(String id, {String name = '', String source = 'https://lists.example/tv.m3u'}) => IptvPlaylist(
  id: id,
  name: name.isEmpty ? 'List $id' : name,
  format: IptvPlaylistFormat.m3u,
  source: source,
  lastRefresh: _at,
  createdAt: _at,
);

IptvChannel _channel(String id, String playlist, {bool favorite = false}) => IptvChannel(
  id: id,
  playlistId: playlist,
  entry: IptvEntry(
    name: 'Channel $id',
    streamUrl: 'https://streams.example/$id.m3u8',
    tvgId: 'tvg-$id',
    groupTitle: 'News',
    channelNumber: 7,
    catchupMode: 'append',
    catchupDays: 3,
    httpHeaders: const {'Referer': 'https://lists.example/'},
  ),
  favorite: favorite,
  sortOrder: 2,
);

const EpgSource _guide = EpgSource(id: 'g1', name: 'Guide', source: 'https://epg.example/t.xml.gz');

/// A file as it comes back from disk: through JSON text.
Map<String, Object?> _roundTrip(Map<String, Object?> json) => jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  setUpAll(loadStrings);

  late AppServices source;
  late AppServices target;
  setUp(() async {
    source = await testServices();
    target = await testServices();
  });
  tearDown(() async {
    await source.close();
    await target.close();
  });

  Future<IptvLibrary> fill(LiveStore store) async {
    final library = StoreIptvLibrary(store);
    await library.saveGuide(_guide, const [], const [], expected: null);
    await library.savePlaylist(_playlist(IptvPlaylist.hotId, name: 'hot'), [
      _channel('hot-1', IptvPlaylist.hotId),
    ], expected: null);
    await library.savePlaylist(
      _playlist('p1'),
      [_channel('c1', 'p1', favorite: true), _channel('c2', 'p1')],
      expected: null,
      mappings: (
        upserts: [
          EpgMapping(
            channelId: 'c1',
            playlistId: 'p1',
            epgChannelKey: epgChannelKey('g1', 'one'),
            epgSourceId: 'g1',
            origin: 'manual',
            locked: true,
          ),
        ],
        deletes: const [],
      ),
    );
    await writeMultiviewSession(store.meta, {
      'layout': 'quad',
      'smallCellsLowQuality': true,
      'danmaku': false,
      'rooms': [
        LiveRoom(platform: 'douyu', roomId: '1', nick: 'a').toJson(),
        null,
        LiveRoom(platform: 'bilibili', roomId: '2', nick: 'b').toJson(),
      ],
    });
    return library;
  }

  test('c1, c2: a full backup has the playlists (not the built-in one), the guides and the arrangement', () async {
    final store = source.store;
    await fill(store);
    final file = await exportBackup(BackupService(store), store, BackupScope.all);
    final iptv = file[iptvLibrarySection]! as Map<String, Object?>;
    final playlists = iptv['playlists']! as List<Object?>;
    expect(playlists, hasLength(1), reason: 'the hot playlist is built in');
    final playlist = playlists.single! as Map<String, Object?>;
    expect(playlist['id'], 'p1');
    expect([for (final channel in playlist['channels']! as List<Object?>) (channel! as Map)['id']], ['c1', 'c2']);
    expect((playlist['mappings']! as List<Object?>).single, containsPair('locked', true));
    expect((iptv['guides']! as List<Object?>).single, containsPair('source', 'https://epg.example/t.xml.gz'));
    expect((file[multiviewSection]! as Map)['session'], containsPair('layout', 'quad'));
    // 3.x's own IPTV section (the settings) is still there.
    expect(file['iptv'], isA<Map<String, Object?>>());
    // A follows-only file has neither.
    final follows = await exportBackup(BackupService(store), store, BackupScope.follows);
    expect(follows.keys, isNot(contains(iptvLibrarySection)));
    expect(follows.keys, isNot(contains(multiviewSection)));
  });

  test('c1, c2: restoring shows the change, replaces the playlists, adds the guide and the arrangement', () async {
    await fill(source.store);
    final file = _roundTrip(await exportBackup(BackupService(source.store), source.store, BackupScope.all));

    final store = target.store;
    final library = StoreIptvLibrary(store);
    await library.savePlaylist(_playlist(IptvPlaylist.hotId, name: 'hot'), [
      _channel('mine-hot', IptvPlaylist.hotId),
    ], expected: null);
    await library.savePlaylist(_playlist('old'), [_channel('o1', 'old')], expected: null);

    final preview = await previewRestore(store, file, BackupScope.all);
    final iptv = preview.parts.firstWhere((part) => part.kind == RestorePartKind.iptv);
    expect((iptv.current, iptv.incoming, iptv.added, iptv.removed), (1, 1, 1, 1));
    final multiview = preview.parts.firstWhere((part) => part.kind == RestorePartKind.multiview);
    expect((multiview.current, multiview.incoming, multiview.added), (0, 2, 2));

    await restoreBackup(BackupService(store), store, file, BackupScope.all);
    expect([
      for (final playlist in await library.playlists()) playlist.id,
    ], unorderedEquals([IptvPlaylist.hotId, 'p1']));
    expect((await library.playlist('p1'))!.lastRefresh, _at);
    final channels = await library.channels('p1');
    expect([for (final channel in channels) channel.id], ['c1', 'c2'], reason: 'ids kept: followed channels match');
    final first = channels.first;
    expect((first.favorite, first.sortOrder, first.entry.tvgId, first.entry.channelNumber), (true, 2, 'tvg-c1', 7));
    expect(first.entry.httpHeaders, isNotEmpty);
    expect(first.entry.catchupDays, 3);
    expect((await library.mappings('p1')).single.locked, isTrue);
    expect([for (final channel in await library.channels(IptvPlaylist.hotId)) channel.id], ['mine-hot']);
    expect((await library.guideSources()).single.source, _guide.source);
    final session = await readMultiviewSession(store.meta);
    expect(session!['layout'], 'quad');
    expect((session['rooms']! as List).whereType<Map<String, Object?>>(), hasLength(2));
  });

  test('a 3.x backup has neither: the playlists and the arrangement stay', () async {
    final store = target.store;
    final library = await fill(store);
    final legacy = {
      'backupVersion': 3,
      'favorite': {'favoriteRooms': <Object?>[], 'favoriteAreas': <Object?>[]},
      'iptv': {'isAutoSyncEnabled': true},
    };
    final preview = await previewRestore(store, legacy, BackupScope.all);
    expect(preview.kept, containsAll([RestorePartKind.iptv, RestorePartKind.multiview]));
    await restoreBackup(BackupService(store), store, legacy, BackupScope.all);
    expect([
      for (final playlist in await library.playlists()) playlist.id,
    ], unorderedEquals([IptvPlaylist.hotId, 'p1']));
    expect((await readMultiviewSession(store.meta))!['layout'], 'quad');
  });

  test('unreadable entries and repeated ids are left out; an arrangement that is not one is ignored', () {
    final backup = iptvBackupIn({
      iptvLibrarySection: {
        'playlists': [
          {'id': '', 'name': 'x', 'format': 'm3u'},
          {'id': 'p', 'name': 'P', 'format': 'zip'},
          {
            'id': 'q',
            'name': 'Q',
            'format': 'txt',
            'channels': [
              {'id': 'c', 'url': ''},
              {'id': 'd', 'url': 'https://x.example/d'},
              'nonsense',
            ],
          },
          // The same id again: the first one counts.
          {'id': 'q', 'name': 'Q2', 'format': 'm3u'},
        ],
        'guides': [
          {'id': 'g', 'name': 'G', 'source': ''},
        ],
      },
    })!;
    expect([for (final entry in backup.playlists) entry.playlist.id], ['q']);
    expect([for (final channel in backup.playlists.single.channels) channel.id], ['d']);
    expect(backup.guides, isEmpty);
    expect(iptvBackupIn({'iptv': <String, Object?>{}}), isNull);
    expect(
      multiviewSessionIn({
        multiviewSection: {
          'session': {'rooms': 'x'},
        },
      }),
      isNull,
    );
    expect(multiviewSessionOf({'layout': 'single', 'extra': 1}), {
      'layout': 'single',
      'smallCellsLowQuality': false,
      'danmaku': false,
      'rooms': <Object?>[],
    });
  });
}
