import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

/// Answers GETs from [bodies] by URL; anything else is a 404.
final class _FakeHttp implements LiveHttp {
  final bodies = <String, List<int>>{};
  final requests = <LiveRequest>[];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    final body = bodies[request.url.toString()];
    return LiveResponse(status: body == null ? 404 : 200, bytes: body ?? const [], url: request.url);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();

  @override
  void close() {}
}

const _playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="cctv1" group-title="央视" tvg-logo="https://f/1.png" catchup="append" catchup-source="&s={utc}",CCTV-1
https://f/cctv1.m3u8|user-agent=TV
#EXTINF:-1 group-title="卫视",湖南卫视
https://f/hunan.m3u8
''';

const _guide = '''
<tv>
<channel id="cctv1"><display-name>CCTV-1 综合</display-name></channel>
<channel id="hunan"><display-name>湖南卫视</display-name></channel>
<programme channel="cctv1" start="20261001110000 +0000" stop="20261001130000 +0000"><title>新闻</title><desc>今日</desc></programme>
<programme channel="cctv1" start="20260920110000 +0000" stop="20260920130000 +0000"><title>Old</title></programme>
</tv>''';

void main() {
  late Directory directory;
  late MemoryIptvLibrary library;
  late _FakeHttp http;
  late IptvImporter importer;
  var selected = '';
  var clock = DateTime.utc(2026, 10, 1, 12);
  var ids = 0;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('live_iptv_test');
    library = MemoryIptvLibrary();
    http = _FakeHttp();
    selected = '';
    clock = DateTime.utc(2026, 10, 1, 12);
    ids = 0;
    importer = IptvImporter(
      library: library,
      http: http,
      playlistDirectory: directory,
      selectedGuideSourceId: () => selected,
      autoSyncEnabled: () => true,
      now: () => clock,
      newId: () => '00000000-0000-4000-8000-${(++ids).toString().padLeft(12, '0')}',
    );
  });

  tearDown(() => directory.deleteSync(recursive: true));

  IptvSite site() =>
      IptvSite(library: library, importer: importer, selectedGuideSourceId: () => selected, now: () => clock);

  test('URL import, guide import, mapping on sync and the platform view', () async {
    http.bodies['https://f/list/cn.m3u'] = utf8.encode(_playlist);
    http.bodies['https://f/epg.xml.gz'] = gzip.encode(utf8.encode(_guide));

    final imported = await importer.importPlaylistFromUrl('https://f/list/cn.m3u');
    expect(imported.status, IptvImportStatus.imported);
    final playlist = (await library.playlists()).single;
    expect((playlist.name, playlist.source, playlist.autoUpdate), ('cn', 'https://f/list/cn.m3u', true));
    expect(http.requests.first.site, 'iptv');

    final guide = await importer.importGuideFromUrl('https://f/epg.xml.gz');
    expect(guide.status, IptvImportStatus.imported);
    expect(http.requests.last.headers['user-agent'], IptvImporter.guideUserAgent);
    selected = guide.id!;
    final before = await library.channels(playlist.id);
    expect((await importer.syncPlaylist(playlist)).status, IptvImportStatus.imported);
    final after = await library.channels(playlist.id);
    expect(after.map((c) => c.id), before.map((c) => c.id), reason: 'ids survive a sync');
    expect((await library.mappings(playlist.id)).map((m) => m.channelId).toSet(), after.map((c) => c.id).toSet());

    final iptv = site();
    final categories = await iptv.getCategories(1, 30);
    expect(categories.single.name, 'cn');
    expect(categories.single.children.map((a) => (a.areaName, a.areaPic, a.platform)), [
      ('CCTV-1', 'https://f/1.png', 'iptv'),
      ('湖南卫视', '', 'iptv'),
    ]);
    final room = await iptv.getRoomDetail(roomId: after.first.id);
    expect((room.title, room.nick, room.area, room.liveStatus), ('CCTV-1', 'CCTV-1', '央视', LiveStatus.live));
    expect((room.currentProgramme, room.currentProgrammeDescription), ('新闻', '今日'));
    expect(room.epgId, epgChannelKey(selected, 'cctv1'));
    expect((room.catchUp.mode, room.catchUp.source), ('append', '&s={utc}'));
    expect(room.httpHeaders, {'user-agent': 'TV'});
    final qualities = await iptv.getPlayQualities(detail: room);
    expect(qualities.single.quality, '默认');
    expect(await iptv.getPlayUrls(detail: room, quality: qualities.single), ['https://f/cctv1.m3u8']);
    final area = await iptv.getCategoryRooms(categories.single.children.last);
    expect((area.single.title, area.single.nick), ('湖南卫视', '卫视'));
    expect(await iptv.getCategoryRooms(categories.single.children.last, page: 2), isEmpty);
    expect((await iptv.searchRooms('cctv')).single.roomId, after.first.id);
    expect(await iptv.searchRooms('  '), isEmpty);
    expect(
      await library.programmes(room.epgId!, from: DateTime.utc(2026, 9), to: DateTime.utc(2026, 11)),
      hasLength(1),
    );
  });

  test('unknown rooms: a stream URL plays as it is, anything else is NotFound', () async {
    final iptv = site();
    final room = await iptv.getRoomDetail(roomId: 'udp://239.0.0.1:1234');
    expect(await iptv.getPlayQualities(detail: room), hasLength(1));
    expect(() => iptv.getRoomDetail(roomId: 'gone'), throwsA(isA<NotFound>()));
    expect(await iptv.getPlayQualities(detail: LiveRoom(data: '   ')), isEmpty);
  });

  test('local import keeps a copy, asks before replacing, retires the old copy', () async {
    final first = await importer.importPlaylistText('央视,#genre#\nCCTV-1,http://f/1\n', 'list.txt');
    expect(first.status, IptvImportStatus.imported);
    final saved = (await library.playlists()).single;
    expect(saved.format, IptvPlaylistFormat.txt);
    expect(File(saved.source).existsSync(), isTrue);
    expect(p(saved.source), startsWith(directory.path));

    final declined = await importer.importPlaylistText(
      '#EXTM3U\n#EXTINF:-1,A\nhttp://f/a\n',
      'LIST',
      confirmReplace: (_) => false,
    );
    expect(declined.status, IptvImportStatus.cancelled);
    final replaced = await importer.importPlaylistText(
      '#EXTM3U\n#EXTINF:-1,A\nhttp://f/a\n',
      'LIST',
      confirmReplace: (_) => true,
    );
    expect(replaced.id, saved.id);
    final now = (await library.playlists()).single;
    expect(now.format, IptvPlaylistFormat.m3u);
    expect(File(saved.source).existsSync(), isFalse);
    expect((await importer.syncPlaylist(now)).status, IptvImportStatus.imported, reason: 'sync re-reads the copy');
    expect(await importer.deletePlaylist((await library.playlists()).single), isTrue);
    expect(directory.listSync(), isEmpty);
  });

  test('a cut-off download or an empty list keeps the saved playlist', () async {
    http.bodies['https://f/a.m3u'] = utf8.encode('#EXTM3U\n#EXTINF:-1,A\nhttp://f/a\n');
    final playlist = (await importer.importPlaylistFromUrl('https://f/a.m3u')).id!;
    http.bodies['https://f/a.m3u'] = utf8.encode('#EXTM3U\n#EXTINF:-1,A\nhttp://f/a\n#EXTINF:-1,B\n');
    final saved = (await library.playlist(playlist))!;
    expect((await importer.syncPlaylist(saved)).status, IptvImportStatus.invalid);
    http.bodies['https://f/a.m3u'] = utf8.encode('<html>');
    expect((await importer.syncPlaylist(saved)).status, IptvImportStatus.unsupportedFormat);
    http.bodies.remove('https://f/a.m3u');
    expect((await importer.syncPlaylist(saved)).status, IptvImportStatus.networkFailed);
    expect(await library.channels(playlist), hasLength(1));
    expect((await importer.importPlaylistFromUrl('https://f/page')).status, IptvImportStatus.networkFailed);
  });

  test('a list named "hot" stays a normal list; the hot list feeds recommendations', () async {
    http.bodies[IptvImporter.hotPlaylistUrl] = utf8.encode('#EXTM3U\n#EXTINF:-1,Hot\nhttp://f/hot\n');
    await importer.importPlaylistText('#EXTM3U\n#EXTINF:-1,Mine\nhttp://f/mine\n', 'hot');
    final rooms = await site().getRecommendRooms();
    expect(rooms.single.title, 'Hot');
    expect(rooms.single.introduction, 'Hot');
    expect((await site().getCategories(1, 30)).single.children.single.areaName, 'Mine');
    expect(await site().getRecommendRooms(page: 2), isEmpty);
  });

  test('automatic sync refreshes only due network sources with auto sync on', () async {
    http.bodies['https://f/a.m3u'] = utf8.encode('#EXTM3U\n#EXTINF:-1,A\nhttp://f/a\n');
    http.bodies['https://f/g.xml'] = utf8.encode(_guide);
    await importer.importPlaylistFromUrl('https://f/a.m3u');
    await importer.importGuideFromUrl('https://f/g.xml');
    await importer.importPlaylistText('#EXTM3U\n#EXTINF:-1,L\nhttp://f/l\n', 'local');
    expect(await importer.syncExpired(hours: 24), isEmpty);
    clock = clock.add(const Duration(hours: 25));
    final results = await importer.syncExpired(hours: 24);
    expect(results.map((r) => r.status), [IptvImportStatus.imported, IptvImportStatus.imported]);
    expect(IptvImporter.normalizeAutoSyncHours(1), 2);
    expect(IptvImporter.normalizeAutoSyncHours(500), 72);
  });

  test('guide replacement by name asks first; old programmes are pruned', () async {
    final bytes = utf8.encode(_guide);
    final first = await importer.importGuide(bytes: bytes, name: 'g', source: '/tmp/g.xml');
    final key = epgChannelKey(first.id!, 'cctv1');
    expect(await library.programmes(key, from: DateTime.utc(2026), to: DateTime.utc(2027)), hasLength(1));
    final declined = await importer.importGuide(
      bytes: bytes,
      name: 'G',
      source: '/tmp/g.xml',
      confirmReplace: (_) => false,
    );
    expect(declined.status, IptvImportStatus.cancelled);
    expect(
      (await importer.importGuide(bytes: utf8.encode('<tv><bad></tv>'), name: 'g', source: '')).status,
      IptvImportStatus.invalid,
    );
    expect(
      (await importer.importGuide(bytes: utf8.encode('<tv></tv>'), name: 'g', source: '')).status,
      IptvImportStatus.unsupportedFormat,
    );
    expect(await importer.deleteGuide((await library.guideSources()).single), isTrue);
  });
}

String p(String path) => File(path).absolute.path;
