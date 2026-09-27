import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/iptv/iptv_page.dart';
import 'package:pure_live_app/features/iptv/iptv_repository.dart';
import 'package:pure_live_app/features/iptv/iptv_room.dart';
import 'package:pure_live_app/features/iptv/iptv_sync.dart';
import 'package:pure_live_app/features/iptv/iptv_widgets.dart';

// Plain tests with real async (drift, files); the widget tests are in
// iptv_page_test.dart.

const _m3u = '''
#EXTM3U x-tvg-url="https://epg.fixture/e.xml"
#EXTINF:-1 tvg-id="CCTV1" group-title="央视",CCTV-1 综合
https://a.fixture/cctv1.m3u8
#EXTINF:-1 group-title="央视",CCTV-1 综合
https://b.fixture/cctv1.flv
#EXTINF:-1 group-title="卫视",湖南卫视
https://a.fixture/hunan.m3u8
''';

const _xmltv = '''
<tv>
  <channel id="CCTV1"><display-name>CCTV1</display-name></channel>
  <programme start="20260927080000 +0800" stop="20260927090000 +0800" channel="CCTV1"><title>朝闻天下</title></programme>
</tv>
''';

/// Serves canned bodies by URL and records the requests.
final class _Http implements LiveHttp {
  final bodies = <String, List<int>>{};
  final requests = <LiveRequest>[];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    final body = bodies['${request.url}'];
    return LiveResponse(status: body == null ? 404 : 200, bytes: body ?? const [], url: request.url);
  }

  @override
  void close() {}
}

void main() {
  group('IptvSync', () {
    late LiveStore store;
    late _Http http;
    late Directory directory;
    late IptvSync sync;
    var now = DateTime.utc(2026, 9, 27, 4);
    var changes = 0;

    setUp(() async {
      store = await LiveStore.inMemory();
      http = _Http()
        ..bodies['https://lists.fixture/tv.m3u'] = utf8.encode(_m3u)
        ..bodies['https://epg.fixture/e.xml'] = gzip.encode(utf8.encode(_xmltv));
      directory = await Directory.systemTemp.createTemp('iptv-test-');
      changes = 0;
      now = DateTime.utc(2026, 9, 27, 4);
      sync = IptvSync(
        store: store.iptv,
        fetcher: IptvFetcher(http),
        settings: store.settings,
        directory: () async => directory,
        onChanged: () => changes++,
        now: () => now,
        compute: <R>(R Function() task) async => task(),
      );
    });

    tearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });

    test('a URL import stores entries, adopts the named guide and names the playlist after the URL', () async {
      await store.settings.set(Settings.iptvUserAgent, 'Global/1.0');
      final result = await sync.importUrl('https://lists.fixture/tv.m3u');
      expect((result.items, result.channels, result.issues), (3, 2, 0));
      final playlist = (await store.iptv.playlists()).single;
      expect(playlist.name, 'tv');
      expect(playlist.guideUrl, 'https://epg.fixture/e.xml');
      expect(http.requests.first.headers['user-agent'], 'Global/1.0');
      final guide = (await store.iptv.guideSources()).single;
      expect(guide.selected, isTrue);
      expect(guide.channelCount, 1);
      expect(changes, greaterThanOrEqualTo(2));

      // The same URL again syncs instead of adding a second playlist.
      await sync.importUrl('https://lists.fixture/tv.m3u', name: 'ignored');
      expect(await store.iptv.playlists(), hasLength(1));

      // The site sees both sources of CCTV-1 as lines and the programme.
      final site = IptvSite(StoreIptvRepository(store.iptv), now: () => now);
      final channel = await site.channel(IptvSite.refOf('CCTV-1 综合'));
      expect(channel.sources, hasLength(2));
      expect(channel.guideChannelId, 'CCTV1');
      expect((await site.guide(channel)).single.title, '朝闻天下');
    });

    test('a file import keeps a copy that later syncs read; deleting removes it', () async {
      final result = await sync.importFile(fileName: '我的列表.txt', bytes: utf8.encode('卫视,#genre#\n湖南卫视,rtmp://x/y\n'));
      final playlist = (await store.iptv.playlist(result.id))!;
      expect(playlist.name, '我的列表');
      expect(playlist.isRemote, isFalse);
      expect(File(playlist.source).existsSync(), isTrue);
      expect(playlist.source, startsWith(directory.path));
      await sync.syncPlaylist(playlist);
      expect((await store.iptv.playlist(result.id))!.channelCount, 1);
      await sync.deletePlaylist(playlist);
      expect(File(playlist.source).existsSync(), isFalse);
    });

    test('failures keep the old data and are recorded; empty input is not a playlist', () async {
      await expectLater(sync.importUrl('ftp://x'), throwsA(isA<IptvBadUrlError>()));
      await expectLater(sync.importUrl('https://lists.fixture/missing.m3u'), throwsA(isA<Object>()));
      await expectLater(
        sync.importFile(fileName: 'a.m3u', bytes: utf8.encode('hello')),
        throwsA(isA<IptvEmptyError>()),
      );
      expect(await store.iptv.playlists(), isEmpty);

      final result = await sync.importUrl('https://lists.fixture/tv.m3u');
      http.bodies.remove('https://lists.fixture/tv.m3u');
      final playlist = (await store.iptv.playlist(result.id))!;
      await expectLater(sync.syncPlaylist(playlist), throwsA(isA<Object>()));
      final after = (await store.iptv.playlist(result.id))!;
      expect(after.entryCount, 3);
      expect(after.lastError, '地址不存在（404），检查网址是否还有效');
      expect(after.lastSyncAt, isNotNull);
    });

    test('automatic sync only takes due URL sources', () async {
      await sync.importUrl('https://lists.fixture/tv.m3u');
      await sync.importFile(fileName: 'local.m3u', bytes: utf8.encode(_m3u));
      http.requests.clear();
      now = now.add(const Duration(hours: 1));
      expect(await sync.syncDue(), 0);
      expect(http.requests, isEmpty, reason: 'synced an hour ago, interval 24 h');
      now = now.add(const Duration(hours: 24));
      expect(await sync.syncDue(), 0);
      expect(http.requests.map((r) => '${r.url}'), ['https://lists.fixture/tv.m3u', 'https://epg.fixture/e.xml']);
      final remote = (await store.iptv.playlists()).firstWhere((p) => p.isRemote);
      await store.iptv.setPlaylistAutoSync(remote.id, enabled: false);
      http.requests.clear();
      now = now.add(const Duration(days: 2));
      await sync.syncDue();
      expect(http.requests.map((r) => '${r.url}'), ['https://epg.fixture/e.xml']);
    });
  });

  group('helpers', () {
    test('share detection', () {
      expect(iptvShareRequest('https://lists.fixture/tv.m3u')?.url, 'https://lists.fixture/tv.m3u');
      expect(iptvShareRequest(' https://lists.fixture/list.TXT ')?.url, 'https://lists.fixture/list.TXT');
      expect(iptvShareRequest(_m3u)?.bytes, isNotNull);
      expect(iptvShareRequest('https://www.douyu.com/288016'), isNull);
      expect(iptvShareRequest('看这个 https://lists.fixture/tv.m3u'), isNull);
      expect(iptvShareRequest('ftp://lists.fixture/tv.m3u'), isNull);
    });

    test('the session room key tells live from catch-up', () {
      final room = IptvSite.refOf('CCTV-1 综合');
      final programme = IptvProgramme(
        channelId: 'CCTV1',
        start: DateTime.utc(2026, 9, 27),
        stop: DateTime.utc(2026, 9, 27, 1),
        title: '朝闻天下',
      );
      final key = catchupRoomKey(room, programme);
      expect(catchupStartOf(key, room), programme.start);
      expect(catchupStartOf(room.key, room), isNull, reason: 'live');
      expect(catchupStartOf(key, IptvSite.refOf('CCTV-2')), isNull, reason: 'another room');
      expect(catchupStartOf(null, room), isNull);
    });

    test('sync time text', () {
      final now = DateTime.utc(2026, 9, 27, 12);
      expect(syncedText(null), '未同步');
      expect(syncedText(now.subtract(const Duration(seconds: 5)), now: now), '刚刚同步');
      expect(syncedText(now.subtract(const Duration(minutes: 5)), now: now), '5 分钟前同步');
      expect(syncedText(now.subtract(const Duration(hours: 3)), now: now), '3 小时前同步');
      expect(syncedText(now.subtract(const Duration(days: 3)), now: now), endsWith('同步'));
    });
  });
}
