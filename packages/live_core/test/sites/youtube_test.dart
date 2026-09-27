// YouTube: InnerTube parsing and the adapter over the recorded samples
// (spec/sites/youtube.md). No legacy expected values (ADR 0016).
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _lofi = 'UCSJ4gkVC6NrvII8umztf0Ow';
const _live = 'nI725iVsyoQ';
const _mrBeast = 'UCX6OQ3DkcsbYNE6H8uQQuVA';

YouTubeSite _site(List<String> samples) => YouTubeSite(ReplayHttp.fixtures('../../fixtures/youtube', samples));

void main() {
  group('§2/§3 lists', () {
    test('S01 the Live destination keeps only live broadcasts', () {
      final body = Fixture.load('youtube', 'S01-browse-live').body;
      final all = YouTubeParse.find(jsonDecode(body), 'videoRenderer');
      final page = YouTubeParse.destination(body);
      expect(page.items, isNotEmpty);
      expect(page.items.length, lessThan(all.length), reason: 'past broadcasts are dropped');
      expect(page.items.every((c) => c.state == LiveState.live && c.audience.online != null), isTrue);
      expect(page.isLast, isTrue);
    });

    test('S02 live search: watching counts, owners, a continuation cursor', () {
      final page = YouTubeParse.search(Fixture.load('youtube', 'S02-search-p1').body);
      expect(page.items, isNotEmpty);
      expect(page.items.first.anchorName, isNotEmpty);
      expect(page.next, isNotNull);
      final p2 = YouTubeParse.search(Fixture.load('youtube', 'S02-search-p2').body);
      expect(p2.items, isNotEmpty);
      expect(p2.items.map((c) => c.ref).toSet().intersection(page.items.map((c) => c.ref).toSet()), isEmpty);
    });

    test('watching counts', () {
      expect(
        YouTubeParse.watching({
          'runs': [
            {'text': '11,001'},
            {'text': ' watching'},
          ],
        }),
        11001,
      );
      expect(YouTubeParse.watching({'simpleText': '3,923,621 views'}), isNull);
    });
  });

  group('§1/§4 resolve_url and player', () {
    test('S03 live channel page names a video; offline names the channel; a handle names the channel', () {
      expect(YouTubeParse.resolved(Fixture.load('youtube', 'S03-resolve-channel-live').body).video, _live);
      final offline = YouTubeParse.resolved(Fixture.load('youtube', 'S03-resolve-channel-offline').body);
      expect(offline.video, isNull);
      expect(offline.channel, _mrBeast);
      expect(YouTubeParse.resolved(Fixture.load('youtube', 'S03-resolve-handle').body).channel, _lofi);
    });

    test('S04 live player: details, HLS with the expire lease; missing video', () {
      final player = YouTubeParse.player(Fixture.load('youtube', 'S04-player-live').body, roomId: _live);
      expect(player.detail.state, LiveState.live);
      expect(player.channelId, _lofi);
      expect(player.detail.card.anchorName, 'Lofi Girl');
      final line = YouTubeParse.line(player.hls!, headers: const {});
      expect(line.url.path, endsWith('/file/index.m3u8'));
      expect(line.url.pathSegments, contains('203.0.113.7'), reason: 'the requester IP was scrubbed');
      expect(line.lease!.expiresAt!.difference(line.lease!.refreshAt), const Duration(minutes: 30));
      expect(
        () => YouTubeParse.player(Fixture.load('youtube', 'S04-player-missing').body, roomId: 'aaaaaaaaaaa'),
        throwsA(isA<NotFound>()),
      );
    });

    test('a broadcast that is not live is offline without HLS', () {
      final body = Fixture.load('youtube', 'S04-player-live').body.replaceFirst('"isLive": true', '"isLive": false');
      final player = YouTubeParse.player(body, roomId: _live);
      expect(player.detail.state, LiveState.offline);
      expect(player.hls, isNull);
    });
  });

  group('adapter', () {
    test('a channel room: live page → player → HLS', () async {
      final site = _site(['S03-resolve-channel-live', 'S04-player-live']);
      final detail = await site.detail(RoomRef('youtube', _lofi));
      expect(detail.ref.roomId, _lofi);
      expect(detail.state, LiveState.live);
      final set = await site.streams(detail);
      expect(set.lines.single.format, StreamFormat.hls);
    });

    test('an offline channel is named by its feed', () async {
      final site = _site(['S03-resolve-channel-offline', 'S05-feed-offline']);
      final detail = await site.detail(RoomRef('youtube', _mrBeast));
      expect(detail.state, LiveState.offline);
      expect(detail.card.anchorName, 'MrBeast');
    });

    test('catalog and search', () async {
      final site = _site(['S01-browse-live', 'S02-search-p1', 'S02-search-p2']);
      expect(await site.categories(), isEmpty);
      expect((await site.recommended()).items, isNotEmpty);
      final p1 = await site.search('lofi');
      expect((await site.search('lofi', cursor: p1.next)).items, isNotEmpty);
    });

    test('links: videos, channels, handles', () async {
      final site = _site(['S03-resolve-handle']);
      expect(await site.resolve('https://www.youtube.com/watch?v=$_live&t=1'), RoomRef('youtube', _live));
      expect(await site.resolve('https://youtu.be/$_live?si=x'), RoomRef('youtube', _live));
      expect(await site.resolve('https://www.youtube.com/live/$_live'), RoomRef('youtube', _live));
      expect(await site.resolve('https://m.youtube.com/channel/$_lofi/live'), RoomRef('youtube', _lofi));
      expect(await site.resolve('看 https://www.youtube.com/@LofiGirl 吧'), RoomRef('youtube', _lofi));
      expect(await site.resolve('https://www.youtube.com/embed/live_stream?channel=$_lofi'), RoomRef('youtube', _lofi));
      expect(await site.resolve('https://www.douyu.com/9999'), isNull);
    });
  });
}
