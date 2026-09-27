import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

/// An in-memory repository with the documented ordering rules.
final class MemoryRepository implements IptvRepository {
  final playlists_ = <(IptvPlaylistInfo, String?, List<IptvEntry>)>[];
  IptvGuideInfo? guide;
  List<IptvGuideChannel> guideChannels_ = const [];
  List<IptvProgramme> programmes_ = const [];
  int guideChannelReads = 0;

  @override
  Future<List<IptvPlaylistInfo>> playlists() async => [for (final (info, _, _) in playlists_) info];

  @override
  Future<List<String>> groups(String playlistId) async => {
    for (final (info, _, entries) in playlists_)
      if (info.id == playlistId)
        for (final entry in entries) entry.group,
  }.toList();

  @override
  Future<List<IptvChannelInfo>> channels({
    required int offset,
    required int limit,
    String? playlistId,
    String? group,
    String? search,
  }) async {
    final seen = <String, IptvChannelInfo>{};
    for (final (info, _, entries) in playlists_) {
      if (playlistId != null && info.id != playlistId) continue;
      for (final entry in entries) {
        if (group != null && entry.group != group) continue;
        if (search != null && !entry.name.toLowerCase().contains(search.toLowerCase())) continue;
        seen.putIfAbsent(
          entry.name,
          () => IptvChannelInfo(
            name: entry.name,
            group: entry.group,
            logo: entry.logo,
            tvgId: entry.tvgId,
            tvgName: entry.tvgName,
          ),
        );
      }
    }
    return seen.values.skip(offset).take(limit).toList();
  }

  @override
  Future<List<IptvSource>> sources(String name) async => [
    for (final (info, agent, entries) in playlists_)
      for (final entry in entries)
        if (entry.name == name) IptvSource(entry: entry, playlistId: info.id, userAgent: agent),
  ];

  @override
  Future<IptvGuideInfo?> selectedGuide() async => guide;

  @override
  Future<List<IptvGuideChannel>> guideChannels(String guideId) async {
    guideChannelReads++;
    return guideChannels_;
  }

  @override
  Future<List<IptvProgramme>> programmes(
    String guideId,
    String channelId, {
    required DateTime from,
    required DateTime to,
  }) async => [
    for (final p in programmes_)
      if (p.channelId == channelId && p.stop.isAfter(from) && p.start.isBefore(to)) p,
  ];

  @override
  Future<Map<String, IptvProgramme>> programmesAt(String guideId, Set<String> channelIds, DateTime at) async => {
    for (final p in programmes_)
      if (channelIds.contains(p.channelId) && p.covers(at)) p.channelId: p,
  };
}

void main() {
  final now = DateTime.utc(2026, 9, 27, 4);
  late MemoryRepository repository;
  late IptvSite site;

  setUp(() {
    repository = MemoryRepository()
      ..playlists_.addAll([
        (
          const IptvPlaylistInfo(id: '1', name: '央视源'),
          'Playlist/1.0',
          parsePlaylist('''
#EXTM3U
#EXTINF:-1 tvg-id="CCTV1" tvg-logo="https://logo.fixture/cctv1.png" group-title="央视",CCTV-1 综合
http://a.fixture/cctv1/index.m3u8
#EXTINF:-1 group-title="央视" catchup="disabled",CCTV-1 综合
http://b.fixture/cctv1.flv|user-agent=Entry%2F2.0
#EXTINF:-1 group-title="央视",CCTV-2 财经
http://a.fixture/cctv2/index.m3u8
#EXTINF:-1,无分组
http://a.fixture/misc.ts
''').entries,
        ),
        (
          const IptvPlaylistInfo(id: '2', name: '备用'),
          null,
          parsePlaylist('卫视,#genre#\n湖南卫视,rtmp://c.fixture/hunan\nCCTV-1 综合,udp://@239.1.1.1:5000\n').entries,
        ),
      ])
      ..guide = const IptvGuideInfo(id: 'g', revision: 1)
      ..guideChannels_ = const [
        IptvGuideChannel(id: 'CCTV1', names: ['CCTV1']),
        IptvGuideChannel(id: 'hunan', names: ['湖南卫视']),
      ]
      ..programmes_ = [
        IptvProgramme(
          channelId: 'CCTV1',
          start: DateTime.utc(2026, 9, 27),
          stop: DateTime.utc(2026, 9, 27, 1),
          title: '朝闻天下',
        ),
        IptvProgramme(
          channelId: 'CCTV1',
          start: DateTime.utc(2026, 9, 27, 3, 30),
          stop: DateTime.utc(2026, 9, 27, 4, 30),
          title: '新闻30分',
          description: '午间新闻',
        ),
        IptvProgramme(
          channelId: 'CCTV1',
          start: DateTime.utc(2026, 9, 29),
          stop: DateTime.utc(2026, 9, 29, 1),
          title: '太远的节目',
        ),
      ];
    site = IptvSite(repository, userAgent: () => 'Global/3.0', now: () => now, pageSize: 2);
  });

  test('identity', () {
    expect(site.id, 'iptv');
    expect(site.name, '网络电视');
    expect(IptvSite.refOf('CCTV-1 综合'), RoomRef('iptv', 'CCTV-1 综合'));
    final placeholder = IptvSite.refOf('0');
    expect(placeholder.roomId, '#0');
    expect(IptvSite.nameOf(placeholder), '0');
    expect(IptvSite.nameOf(IptvSite.refOf('#1 频道')), '#1 频道');
  });

  test('categories are playlists and areas their groups', () async {
    final categories = await site.categories();
    expect([for (final c in categories) (c.id, c.name)], [('1', '央视源'), ('2', '备用')]);
    expect([for (final a in categories.first.areas) (a.id, a.name)], [('1/央视', '央视'), ('1/', '未分组')]);
    final rooms = await site.areaRooms(categories.first.areas.first);
    expect(rooms.items.map((card) => card.anchorName), ['CCTV-1 综合', 'CCTV-2 财经']);
    expect(rooms.isLast, isTrue);
  });

  test('recommended pages through every distinct channel with the programme on air', () async {
    final first = await site.recommended();
    expect(first.items.map((card) => card.anchorName), ['CCTV-1 综合', 'CCTV-2 财经']);
    final cctv1 = first.items.first;
    expect(cctv1.ref, RoomRef('iptv', 'CCTV-1 综合'));
    expect(cctv1.title, '新闻30分');
    expect(cctv1.state, LiveState.live);
    expect(cctv1.cover, Uri.parse('https://logo.fixture/cctv1.png'));
    expect(first.items.last.title, 'CCTV-2 财经');
    final second = await site.recommended(cursor: first.next);
    expect(second.items.map((card) => card.anchorName), ['无分组', '湖南卫视']);
    expect(second.isLast, isTrue);
    expect(repository.guideChannelReads, 1, reason: 'the matcher is cached per guide revision');
  });

  test('search matches names; a blank keyword costs nothing', () async {
    expect((await site.search('cctv')).items.map((c) => c.anchorName), ['CCTV-1 综合', 'CCTV-2 财经']);
    expect((await site.search('  ')).items, isEmpty);
  });

  test('detail and streams: one line per source across playlists, headers by precedence', () async {
    final ref = RoomRef('iptv', 'CCTV-1 综合');
    final detail = await site.detail(ref);
    expect(detail.card.title, '新闻30分');
    expect(detail.introduction, '午间新闻');
    expect(detail.link, Uri.parse('http://a.fixture/cctv1/index.m3u8'));
    final set = await site.streams(detail);
    expect(set.qualities, [IptvSite.original]);
    expect(set.selected.label, '原画');
    expect(
      [for (final line in set.lines) (line.lineId, line.url.toString(), line.format, line.headers['user-agent'])],
      [
        ('line1', 'http://a.fixture/cctv1/index.m3u8', StreamFormat.hls, 'Playlist/1.0'),
        ('line2', 'http://b.fixture/cctv1.flv', StreamFormat.flv, 'Entry/2.0'),
        // Uri drops the empty user info of VLC's `udp://@group:port`; FFmpeg
        // reads both spellings the same way.
        ('line3', 'udp://239.1.1.1:5000', StreamFormat.flv, 'Global/3.0'),
      ],
    );
    await expectLater(site.detail(RoomRef('iptv', '不存在')), throwsA(isA<NotFound>()));
    expect(await site.resolve('https://www.douyu.com/1'), isNull);
  });

  test('line formats: HLS and FLV by path, other http(s) addresses are single streams (§5)', () async {
    final misc = await site.streams(await site.detail(RoomRef('iptv', '无分组')));
    expect(misc.lines.single.format, StreamFormat.other, reason: 'a .ts line is recorded by its bytes');
    StreamFormat of(String url) => IptvSite.formatOf(Uri.parse(url));
    expect(of('http://a.fixture/live/INDEX.M3U8?token=1'), StreamFormat.hls);
    expect(of('https://a.fixture/list.m3u'), StreamFormat.hls);
    expect(of('http://b.fixture/live/cctv1.FLV?wsSecret=x'), StreamFormat.flv);
    expect(of('http://b.fixture/live.flv.ts'), StreamFormat.other);
    expect(of('http://192.168.1.1:4022/udp/239.3.1.1:8000'), StreamFormat.other, reason: 'udpxy');
    expect(of('http://192.168.1.1:4022/rtp/239.3.1.1:8000'), StreamFormat.other);
    expect(of('http://c.fixture/live/1?type=m3u8'), StreamFormat.other, reason: 'the query is not the path');
    expect(of('https://c.fixture/play/cctv1'), StreamFormat.other);
    expect(of('http://xc.fixture/live/user/pass/1.ts'), StreamFormat.other);
    for (final url in [
      'rtmp://d.fixture/live/1',
      'rtsp://e.fixture/1.sdp',
      'udp://239.1.1.1:5000',
      'rtp://@239.1.1.1:5000',
    ]) {
      expect(of(url), StreamFormat.flv, reason: '$url: not HTTP, opened directly and not recorded');
    }
  });

  test('guide window, availability and catch-up lines', () async {
    final channel = await site.channel(RoomRef('iptv', 'CCTV-1 综合'));
    expect(channel.guideChannelId, 'CCTV1');
    final guide = await site.guide(channel);
    expect(guide.map((p) => p.title), ['朝闻天下', '新闻30分']);
    final past = guide.first;
    expect(site.availability(channel, past), CatchupAvailability.available);
    final replay = site.catchupStreams(channel, past, utcOffset: const Duration(hours: 8));
    // The second source turned catch-up off; the UDP multicast source gets
    // the playseek rule too (it will fail to play, which the player reports).
    expect(replay.lines.map((line) => line.lineId), ['line1', 'line3']);
    expect(
      replay.lines.first.url.toString(),
      'http://a.fixture/cctv1/index.m3u8?playseek=20260927080000-20260927090000',
    );
    final other = await site.channel(RoomRef('iptv', '无分组'));
    expect(other.guideChannelId, isNull);
    expect(await site.guide(other), isEmpty);
    expect(await site.nowPlaying(other), isNull);
  });

  test('without a selected guide there are no programmes', () async {
    repository.guide = null;
    final page = await site.recommended();
    expect(page.items.first.title, 'CCTV-1 综合');
    final channel = await site.channel(RoomRef('iptv', 'CCTV-1 综合'));
    expect(channel.guideId, isNull);
  });

  group('fetcher', () {
    Future<Object> fail(int status) async {
      final fetcher = IptvFetcher(_StatusHttp(status));
      try {
        await fetcher.download(Uri.parse('https://fixture/list.m3u'));
      } on Object catch (error) {
        return error;
      }
      return 'no error';
    }

    test('maps statuses and sends the custom UA', () async {
      final http = _StatusHttp(200);
      final bytes = await IptvFetcher(http).download(Uri.parse('https://fixture/list.m3u'), userAgent: ' UA/1 ');
      expect(bytes, [35]);
      expect(http.requests.single.headers['user-agent'], 'UA/1');
      expect(http.requests.single.site, 'iptv');
      expect(await fail(404), isA<NotFound>());
      expect(await fail(503), isA<NetworkFailure>());
      expect(await fail(-1), isA<NetworkFailure>());
    });
  });
}

final class _StatusHttp implements LiveHttp {
  new(this.status);

  final int status;
  final requests = <LiveRequest>[];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    if (status < 0) throw TransportFailure(request.site, TransportReason.connect);
    return LiveResponse(status: status, bytes: const [35], url: request.url);
  }

  @override
  void close() {}
}
