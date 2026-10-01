// KickSite over the recorded answers (ReplayHttp): the requests (paths,
// queries, headers, which transport), the catalog, lists, search, room
// depths and their request counts, streams from room entry and recovery,
// links and error mapping.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/kick';

ReplaySample _sample(String name) => ReplaySample.load('$_root/$name');

ReplaySample _synthetic(String url, Object body, {int status = 200}) => ReplaySample(
  method: 'GET',
  url: Uri.parse(url),
  status: status,
  bytes: utf8.encode(body is String ? body : jsonEncode(body)),
);

/// The API samples go to `api`, the master playlist to `media`, as the app
/// splits them (Android's system TLS for kick.com).
({KickSite site, ReplayHttp api, ReplayHttp media}) _setup(List<String> api, {List<String> media = const []}) {
  final apiHttp = ReplayHttp([for (final name in api) _sample(name)]);
  final mediaHttp = ReplayHttp([for (final name in media) _sample(name)]);
  return (site: KickSite(mediaHttp, apiHttp: apiHttp), api: apiHttp, media: mediaHttp);
}

const _subcategories = [
  'S01-subcategories-games',
  'S01-subcategories-irl',
  'S01-subcategories-music',
  'S01-subcategories-gambling',
  'S01-subcategories-creative',
  'S01-subcategories-alternative',
];

void main() {
  test('identity', () {
    final site = KickSite(ReplayHttp(const []));
    expect(site.id, 'kick');
    expect(site.name, 'Kick');
    expect(SiteIds.isSupported('kick'), isTrue);
    expect(SiteIds.isRetired('kick'), isFalse);
    expect(SiteIds.ignoresRoomIdCase('kick'), isTrue);
  });

  group('catalog', () {
    test('six categories with their subcategories, seven requests', () async {
      final setup = _setup(['S01-categories', ..._subcategories]);
      final categories = await setup.site.getCategories(1, 30);
      expect(categories.map((c) => c.id), ['games', 'irl', 'music', 'gambling', 'creative', 'alternative']);
      expect(categories.first.name, '游戏');
      expect(categories.first.children, hasLength(32));
      expect(setup.api.requests, hasLength(7));
      final request = setup.api.requests.first;
      expect(request.site, 'kick');
      expect(request.headers, KickApi.headers);
      expect(setup.media.requests, isEmpty);
      expect(await setup.site.getCategories(2, 30), isEmpty);
    });

    test('a failing category is left out; all failing throws', () async {
      final api = ReplayHttp([
        _sample('S01-categories'),
        _sample('S01-subcategories-games'),
        for (final slug in ['irl', 'music', 'gambling', 'creative', 'alternative'])
          _synthetic('https://kick.com/api/v1/subcategories?category=$slug&limit=32&page=1', '', status: 500),
      ]);
      final categories = await KickSite(ReplayHttp(const []), apiHttp: api).getCategories(1, 30);
      expect(categories.map((c) => c.id), ['games']);
      final failing = ReplayHttp([
        _sample('S01-categories'),
        for (final slug in ['games', 'irl', 'music', 'gambling', 'creative', 'alternative'])
          _synthetic('https://kick.com/api/v1/subcategories?category=$slug&limit=32&page=1', '', status: 503),
      ]);
      await expectLater(
        KickSite(ReplayHttp(const []), apiHttp: failing).getCategories(1, 30),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('Cloudflare refusing dart:io is RiskControl', () async {
      final api = ReplayHttp([
        _synthetic(
          'https://kick.com/api/v1/categories',
          '{"error": "Request blocked by security policy.", "reference": "dda9bc1f"}',
          status: 403,
        ),
      ]);
      await expectLater(KickSite(api).getCategories(1, 30), throwsA(isA<RiskControl>()));
    });
  });

  group('lists', () {
    test('recommendations by viewers, page by page', () async {
      final setup = _setup(['S03-recommend-p1', 'S03-recommend-p2']);
      final first = await setup.site.getDirectoryPage();
      expect(first.rooms.first.roomId, 'lonche');
      expect(first.hasMore, isTrue);
      final second = await setup.site.getRecommendRooms(page: 2);
      expect(second, isNotEmpty);
      expect(setup.api.requests.first.url.queryParameters, {'page': '1', 'limit': '30', 'sort': 'desc'});
    });

    test('a subcategory area', () async {
      final setup = _setup(['S02-category-p1', 'S02-category-last']);
      const area = LiveArea(
        platform: 'kick',
        areaType: 'subcategory',
        areaId: 'just-chatting',
        areaName: 'Just Chatting',
      );
      final rooms = await setup.site.getCategoryRooms(area);
      expect(rooms, hasLength(30));
      expect(setup.api.requests.single.url.queryParameters['subcategory'], 'just-chatting');
      const chess = LiveArea(platform: 'kick', areaType: 'subcategory', areaId: 'chess');
      final last = await setup.site.getDirectoryPage(page: 2, category: chess);
      expect(last.rooms, isEmpty);
      expect(last.hasMore, isFalse);
    });

    test('an unknown subcategory is NotFound; a foreign area a caller error', () async {
      final setup = _setup(['S02-category-missing']);
      const missing = LiveArea(platform: 'kick', areaType: 'subcategory', areaId: 'no-such-category-zz');
      await expectLater(setup.site.getCategoryRooms(missing), throwsA(isA<NotFound>()));
      const foreign = LiveArea(platform: 'twitch', areaType: 'subcategory', areaId: 'x');
      expect(() => setup.site.getCategoryRooms(foreign), throwsArgumentError);
    });
  });

  group('search', () {
    test('one page; blank keywords and later pages ask nothing', () async {
      final setup = _setup(['S04-search']);
      final rooms = await setup.site.searchRooms(' xqc ');
      expect(rooms.first.roomId, 'xqc');
      expect(setup.api.requests.single.url.queryParameters, {'searched_word': 'xqc'});
      expect(await setup.site.searchRooms('xqc', page: 2), isEmpty);
      expect(await setup.site.searchRooms('  '), isEmpty);
      expect(setup.api.requests, hasLength(1));
    });
  });

  group('rooms', () {
    test('room entry: channel, master playlist, danmaku arguments', () async {
      final setup = _setup(['S05-channel-live'], media: ['S06-master']);
      final room = await setup.site.getRoomDetail(roomId: 'XQC');
      expect(room.roomId, 'xqc');
      expect(room.isLiveNow, isTrue);
      expect(room.danmakuData, const KickDanmakuArgs(chatroomId: 668, channelId: 668, slug: 'xqc'));
      final data = room.data! as KickRoomData;
      expect(data.qualities.first.id, '1080p60');
      expect(setup.api.requests.single.url.path, '/api/v2/channels/xqc');
      final master = setup.media.requests.single;
      expect(master.url.host, 'fa723fc1b171.us-west-2.playback.live-video.net');
      expect(master.headers['origin'], 'https://kick.com');
      expect(master.headers['referer'], 'https://kick.com/xqc/');
    });

    test('follow refresh: the channel only', () async {
      final setup = _setup(['S05-channel-live', 'S05-channel-offline']);
      final live = await setup.site.getRoomDetailForRefresh(roomId: 'xqc');
      expect(live.isLiveNow, isTrue);
      expect(live.data, isNull);
      expect(live.danmakuData, isNull);
      expect(await setup.site.getLiveStatus(roomId: 'xqcisoffline'), isFalse);
      expect(setup.api.requests, hasLength(2));
      expect(setup.media.requests, isEmpty);
    });

    test('an offline room has no stream, without a request', () async {
      final setup = _setup(['S05-channel-offline']);
      final room = await setup.site.getRoomDetail(roomId: 'xqcisoffline');
      expect(room.liveStatus, LiveStatus.offline);
      expect(room.data, isNull);
      expect(room.danmakuData, isA<KickDanmakuArgs>());
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      expect(setup.api.requests, hasLength(1));
    });

    test('a missing channel is NotFound; a room id that is no slug without a request', () async {
      final setup = _setup(['S05-channel-missing']);
      await expectLater(setup.site.getRoomDetail(roomId: 'zzqqxxnotachannel'), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getRoomDetail(roomId: 'a b'), throwsA(isA<NotFound>()));
      expect(setup.api.requests, hasLength(1));
    });
  });

  group('streams', () {
    test('lines of the entered room; a card is entered first', () async {
      final setup = _setup(['S05-channel-live'], media: ['S06-master']);
      final card = LiveRoom(platform: 'kick', roomId: 'xqc', liveStatus: LiveStatus.live);
      final qualities = await setup.site.getPlayQualities(detail: card);
      expect(qualities, hasLength(5));
      final room = await setup.site.getRoomDetail(roomId: 'xqc');
      final resolution = await setup.site.resolvePlayUrls(detail: room, quality: qualities[2]);
      expect(resolution.lines.single.format, StreamFormat.hls);
      expect(resolution.appliedQualityData, '480p');
      expect(await setup.site.getPlayUrls(detail: room, quality: qualities[2]), [resolution.lines.single.url]);
    });

    test('recovery reads a new master; a quality it lost falls back to the best', () async {
      final setup = _setup(['S05-channel-live'], media: ['S06-master']);
      final room = await setup.site.getRoomDetail(roomId: 'xqc');
      final again = await setup.site.resolvePlayUrlsForRecovery(
        detail: room,
        quality: const LivePlayQuality(id: '720p60', quality: '720p60'),
      );
      expect(again.appliedQualityData, '720p60');
      final gone = await setup.site.resolvePlayUrlsForRecovery(
        detail: room,
        quality: const LivePlayQuality(id: '4k', quality: '4k'),
      );
      expect(gone.appliedQualityData, '1080p60');
      expect(setup.api.requests, hasLength(3));
      expect(setup.media.requests, hasLength(3));
    });

    test('an ended broadcast between channel and master is StreamUnavailable', () async {
      final api = ReplayHttp([_sample('S05-channel-live')]);
      final master = _sample('S06-master');
      final media = ReplayHttp([_synthetic(master.url.toString(), '[{"error":"gone"}]', status: 404)]);
      await expectLater(KickSite(media, apiHttp: api).getRoomDetail(roomId: 'xqc'), throwsA(isA<StreamUnavailable>()));
    });
  });

  test('transport failures are NetworkFailure; cancellation passes through', () async {
    final failing = KickSite(_Failing(TransportReason.connect));
    await expectLater(failing.getRoomDetailForRefresh(roomId: 'xqc'), throwsA(isA<NetworkFailure>()));
    final cancelled = KickSite(_Failing(TransportReason.cancelled));
    await expectLater(cancelled.searchRooms('xqc'), throwsA(isA<TransportFailure>()));
  });

  test('links', () {
    final site = KickSite(ReplayHttp(const []));
    expect(site.roomIdFromUrl('https://kick.com/XQC'), 'xqc');
    expect(site.roomIdFromUrl('https://kick.com/browse'), isNull);
    expect(SiteIds.isRetiredLink('https://kick.com/xqc'), isFalse);
  });
}

final class _Failing implements LiveHttp {
  new(this.reason);

  final TransportReason reason;

  @override
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('kick', reason, 'scripted');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();

  @override
  void close() {}
}
