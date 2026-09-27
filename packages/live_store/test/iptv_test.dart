import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

IptvEntryRecord entry(String name, String url, {String group = '', String? tvgId, Map<String, String>? headers}) =>
    IptvEntryRecord(name: name, url: url, group: group, tvgId: tvgId, headers: headers ?? const {});

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late LiveStore store;
  late IptvStore iptv;
  final synced = DateTime.utc(2026, 9, 27, 4);

  setUp(() async {
    store = await LiveStore.inMemory();
    iptv = store.iptv;
  });

  tearDown(() => store.close());

  Future<(int, int)> seed() async {
    final first = await iptv.addPlaylist(name: ' 央视源 ', source: 'https://fixture/a.m3u', userAgent: 'UA/1');
    final second = await iptv.addPlaylist(name: '本地', source: '/data/IPTV/playlists/b.txt');
    await iptv.replaceEntries(
      first,
      [
        entry('CCTV-1 综合', 'https://a/1.m3u8', group: '央视', tvgId: 'CCTV1', headers: {'referer': 'https://a/'}),
        entry('CCTV-2', 'https://a/2.m3u8', group: '央视'),
        entry('CCTV-1 综合', 'https://a/1b.flv', group: '央视'),
        entry('100%_真', 'https://a/pct.m3u8'),
        entry('湖南卫视', 'https://a/hn.m3u8', group: '卫视'),
      ],
      syncedAt: synced,
      guideUrl: 'https://epg/e.xml',
    );
    await iptv.replaceEntries(second, [
      entry('湖南卫视', 'rtmp://b/hn', group: '卫视'),
      entry('CCTV-1 综合', 'udp://239.1.1.1:5000'),
    ], syncedAt: synced);
    return (first, second);
  }

  group('playlists', () {
    test('add, list with counts, rename, user agent, auto sync, reorder, delete', () async {
      final (first, second) = await seed();
      var list = await iptv.playlists();
      expect(
        [for (final p in list) (p.id, p.name, p.order, p.entryCount, p.channelCount)],
        [(first, '央视源', 0, 5, 4), (second, '本地', 1, 2, 2)],
      );
      expect(list.first.isRemote, isTrue);
      expect(list.last.isRemote, isFalse);
      expect(list.first.userAgent, 'UA/1');
      expect(list.first.guideUrl, 'https://epg/e.xml');
      expect(list.first.lastSyncAt, synced);
      expect(list.first.lastError, isNull);

      await iptv.renamePlaylist(first, '新名字');
      await iptv.setPlaylistUserAgent(first, '  ');
      await iptv.setPlaylistAutoSync(first, enabled: false);
      await iptv.reorderPlaylists([second]);
      list = await iptv.playlists();
      expect(list.map((p) => p.id), [second, first]);
      expect(list.last.name, '新名字');
      expect(list.last.userAgent, isNull);
      expect(list.last.autoSync, isFalse);

      await iptv.deletePlaylist(second);
      expect((await iptv.playlists()).single.id, first);
      expect(await iptv.sources('CCTV-1 综合'), hasLength(2), reason: 'entries went with the playlist');
    });

    test('a failed sync keeps the entries; replacing a deleted playlist does nothing', () async {
      final (first, _) = await seed();
      final later = synced.add(const Duration(hours: 1));
      await iptv.recordPlaylistFailure(first, 'NetworkFailure', at: later);
      final playlist = (await iptv.playlist(first))!;
      expect(playlist.lastError, 'NetworkFailure');
      expect(playlist.lastAttemptAt, later);
      expect(playlist.lastSyncAt, synced);
      expect(playlist.entryCount, 5);
      await iptv.deletePlaylist(first);
      await iptv.replaceEntries(first, [entry('X', 'https://x')], syncedAt: later);
      expect(await iptv.sources('X'), isEmpty);
    });

    test('watchPlaylists emits after changes', () async {
      final emissions = <int>[];
      final subscription = iptv.watchPlaylists().listen((list) => emissions.add(list.length));
      await pumpEventQueue();
      await iptv.addPlaylist(name: 'A', source: 'https://a');
      await pumpEventQueue();
      await subscription.cancel();
      expect(emissions, [0, 1]);
    });
  });

  group('channels', () {
    test('groups in first-appearance order', () async {
      final (first, second) = await seed();
      expect(await iptv.groups(first), ['央视', '', '卫视']);
      expect(await iptv.groups(second), ['卫视', '']);
    });

    test('distinct names in playlist then file order, with their first entry', () async {
      final (first, second) = await seed();
      final all = await iptv.channels(offset: 0, limit: 10);
      expect(all.map((c) => c.name), ['CCTV-1 综合', 'CCTV-2', '100%_真', '湖南卫视']);
      expect(all.first.url, 'https://a/1.m3u8');
      expect(all.first.tvgId, 'CCTV1');
      expect(all.first.headers, {'referer': 'https://a/'});
      expect((await iptv.channels(offset: 1, limit: 2)).map((c) => c.name), ['CCTV-2', '100%_真']);
      expect((await iptv.channels(offset: 0, limit: 10, playlistId: first, group: '央视')).map((c) => c.name), [
        'CCTV-1 综合',
        'CCTV-2',
      ]);
      expect((await iptv.channels(offset: 0, limit: 10, playlistId: second)).map((c) => c.url), [
        'rtmp://b/hn',
        'udp://239.1.1.1:5000',
      ]);
      await iptv.reorderPlaylists([second, first]);
      expect((await iptv.channels(offset: 0, limit: 10)).map((c) => c.name).take(2), ['湖南卫视', 'CCTV-1 综合']);
    });

    test('search is case-insensitive for ASCII and treats % and _ literally', () async {
      await seed();
      expect((await iptv.channels(offset: 0, limit: 10, search: 'cctv')).map((c) => c.name), ['CCTV-1 综合', 'CCTV-2']);
      expect((await iptv.channels(offset: 0, limit: 10, search: '%_')).map((c) => c.name), ['100%_真']);
      expect(await iptv.channels(offset: 0, limit: 10, search: '_x'), isEmpty);
    });

    test('sources of a name across playlists carry the playlist user agent', () async {
      final (first, second) = await seed();
      final sources = await iptv.sources('CCTV-1 综合');
      expect(
        [for (final s in sources) (s.playlistId, s.entry.url, s.userAgent)],
        [
          (first, 'https://a/1.m3u8', 'UA/1'),
          (first, 'https://a/1b.flv', 'UA/1'),
          (second, 'udp://239.1.1.1:5000', null),
        ],
      );
    });
  });

  group('guides', () {
    Future<int> guide() async {
      final id = await iptv.addGuideSource(name: 'EPG', source: 'https://epg/e.xml.gz');
      await iptv.replaceGuide(
        id,
        const [
          IptvGuideChannelRecord(channelId: 'CCTV1', names: ['CCTV-1 综合', 'CCTV1'], icon: 'https://i/1.png'),
          IptvGuideChannelRecord(channelId: 'hunan'),
        ],
        [
          IptvProgrammeRecord(
            channelId: 'CCTV1',
            start: DateTime.utc(2026, 9, 27),
            stop: DateTime.utc(2026, 9, 27, 1),
            title: '朝闻天下',
            catchupId: 'x',
          ),
          IptvProgrammeRecord(
            channelId: 'CCTV1',
            start: DateTime.utc(2026, 9, 27, 3, 30),
            stop: DateTime.utc(2026, 9, 27, 4, 30),
            title: '新闻30分',
            description: '午间',
          ),
          IptvProgrammeRecord(
            channelId: 'hunan',
            start: DateTime.utc(2026, 9, 25),
            stop: DateTime.utc(2026, 9, 25, 1),
            title: '旧节目',
          ),
        ],
        syncedAt: synced,
      );
      return id;
    }

    test('the first source is selected; selecting and deleting move the selection', () async {
      final a = await guide();
      final b = await iptv.addGuideSource(name: 'B', source: 'https://epg/b.json');
      expect((await iptv.selectedGuideSource())!.id, a);
      await iptv.selectGuideSource(b);
      expect((await iptv.guideSources()).map((g) => g.selected), [false, true]);
      await iptv.deleteGuideSource(b);
      expect((await iptv.selectedGuideSource())!.id, a);
      await iptv.selectGuideSource(null);
      expect(await iptv.selectedGuideSource(), isNull);
    });

    test('channels, programmes in a window, programmes on air, pruning', () async {
      final id = await guide();
      final source = (await iptv.guideSources()).single;
      expect(source.channelCount, 2);
      expect(source.lastSyncAt, synced);
      final channels = await iptv.guideChannels(id);
      expect(channels.first.names, ['CCTV-1 综合', 'CCTV1']);
      expect(channels.first.icon, 'https://i/1.png');
      expect(channels.last.names, isEmpty);
      final window = await iptv.programmes(
        id,
        'CCTV1',
        from: DateTime.utc(2026, 9, 27, 0, 30),
        to: DateTime.utc(2026, 9, 27, 5),
      );
      expect(window.map((p) => p.title), ['朝闻天下', '新闻30分']);
      expect(window.first.catchupId, 'x');
      final onAir = await iptv.programmesAt(id, {'CCTV1', 'hunan'}, DateTime.utc(2026, 9, 27, 4));
      expect(onAir.keys, ['CCTV1']);
      expect(onAir['CCTV1']!.description, '午间');
      expect(
        await iptv.programmesAt(id, {'CCTV1'}, DateTime.utc(2026, 9, 27, 1)),
        isEmpty,
        reason: 'stop is exclusive',
      );
      expect(await iptv.pruneProgrammes(DateTime.utc(2026, 9, 26)), 1);
      await iptv.recordGuideFailure(id, 'ApiChanged', at: synced.add(const Duration(days: 1)));
      expect((await iptv.guideSources()).single.lastError, 'ApiChanged');
      await iptv.deleteGuideSource(id);
      expect(await iptv.programmesAt(id, {'CCTV1'}, DateTime.utc(2026, 9, 27, 4)), isEmpty);
    });
  });

  group('backup', () {
    test('exports URL playlists and guides; restore replaces them and keeps local files', () async {
      await seed();
      final guideId = await iptv.addGuideSource(name: 'EPG', source: 'https://epg/e.xml');
      await iptv.addGuideSource(name: '本地 EPG', source: '/data/e.xml');
      await iptv.selectGuideSource(guideId);
      final document = await BackupService(store, platform: 'android').export(now: synced);
      final section = (document['sections']! as Map)['iptv'];
      expect(section, {
        'playlists': [
          {'name': '央视源', 'url': 'https://fixture/a.m3u', 'userAgent': 'UA/1', 'autoSync': true, 'order': 0},
        ],
        'epgSources': [
          {'name': 'EPG', 'url': 'https://epg/e.xml', 'autoSync': true, 'selected': true, 'order': 0},
        ],
      });

      final target = await LiveStore.inMemory();
      addTearDown(target.close);
      await target.iptv.addPlaylist(name: '旧网址', source: 'https://old/list.m3u');
      await target.iptv.addPlaylist(name: '本机文件', source: '/data/local.m3u');
      await target.iptv.addGuideSource(name: '本机 EPG', source: '/data/local.xml');
      final report = await BackupService(target, platform: 'android').restore(document);
      final playlists = await target.iptv.playlists();
      expect(
        [for (final p in playlists) (p.name, p.source, p.userAgent, p.lastSyncAt)],
        [('本机文件', '/data/local.m3u', null, null), ('央视源', 'https://fixture/a.m3u', 'UA/1', null)],
      );
      final guides = await target.iptv.guideSources();
      expect([for (final g in guides) (g.name, g.selected)], [('本机 EPG', false), ('EPG', true)]);
      expect(report.counts['iptvPlaylists']!.written, 1);
      expect(report.counts['iptvGuides']!.written, 1);
    });

    test('the section is validated; follows-only restores ignore it', () async {
      final target = await LiveStore.inMemory();
      addTearDown(target.close);
      Map<String, Object?> document(Object iptvSection) => {
        'format': 'pure_live.backup',
        'version': 4,
        'createdAt': '2026-09-27T02:00:00Z',
        'app': {'version': '4.0.0', 'platform': 'android'},
        'scope': 'full',
        'sections': {'iptv': iptvSection},
        'secrets': null,
      };
      final report = await BackupService(target, platform: 'android').restore(
        document({
          'providers': [
            {'name': 'B', 'url': 'https://b', 'order': 1},
            {'name': 'A', 'url': 'https://a', 'order': 0, 'autoSync': false},
            {'name': 'dup', 'url': 'https://a'},
            {'name': 'file', 'url': '/sdcard/x.m3u'},
            'junk',
          ],
        }),
      );
      expect([for (final p in await target.iptv.playlists()) (p.name, p.autoSync)], [('A', false), ('B', true)]);
      expect(report.counts['iptvPlaylists']!.dropped, 3);
      expect(
        () => BackupService(target, platform: 'android').plan(document(['not', 'an', 'object'])),
        throwsFormatException,
      );
      final followsOnly = await BackupService(
        target,
        platform: 'android',
      ).plan(document(const {'playlists': <Object?>[]}), mode: RestoreMode.follows);
      await BackupService(target, platform: 'android').apply(followsOnly);
      expect(await target.iptv.playlists(), hasLength(2));
    });

    test('3.x iptv settings import into the registry', () async {
      final target = await LiveStore.inMemory();
      addTearDown(target.close);
      await BackupService(target, platform: 'android').restore({
        'backupVersion': 3,
        'iptv': {
          'selectedSourceId': 'old',
          'isAutoSyncEnabled': true,
          'autoSyncHoursInterval': 12,
          'customIptvUserAgent': 'okhttp/4.12',
        },
      });
      expect(target.settings.get(Settings.iptvAutoSync), isTrue);
      expect(target.settings.get(Settings.iptvAutoSyncHours), 12);
      expect(target.settings.get(Settings.iptvUserAgent), 'okhttp/4.12');
      expect(store.settings.get(Settings.iptvAutoSync), isFalse, reason: 'default off (F-IPTV-03)');
      expect(store.settings.get(Settings.iptvAutoSyncHours), 24);
    });
  });
}
