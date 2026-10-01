// BilibiliVodClient and the APIs over recorded samples (ReplayHttp) and
// small synthetic answers: which cookie goes where, WBI signing and its
// -352 renewal, writes needing a login, comment offsets.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:live_vod/live_vod.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _spi = '{"code":0,"data":{"b_3":"GUEST3-infoc","b_4":"GUEST4"}}';
const _nav =
    '{"code":-101,"data":{"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png",'
    '"sub_url":"https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png"}}}';

/// Answers by path: a queue of bodies per path, then [inner].
final class _Scripted implements LiveHttp {
  new(this.script, {this.inner});

  final Map<String, List<String>> script;
  final ReplayHttp? inner;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    final queue = script[request.url.path];
    if (queue != null && queue.isNotEmpty) {
      final body = queue.length == 1 ? queue.first : queue.removeAt(0);
      return LiveResponse(status: 200, bytes: utf8.encode(body), url: request.url);
    }
    if (inner != null) return await inner!.send(request);
    throw StateError('unscripted ${request.url}');
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();

  @override
  void close() {}
}

void main() {
  group('cookies', () {
    test('streams carry no guest buvid (it makes playurl answer 412); API calls do', () async {
      final replay = ReplayHttp.fixtures(fixtureRoot, ['V08-playurl-dash', 'V05-view']);
      final http = _Scripted({
        '/x/frontend/finger/spi': [_spi],
      }, inner: replay);
      final ugc = BilibiliUgcApi(BilibiliVodClient(http));
      final streams = await ugc.streams(bvid: 'BV1zKZrYAEi8', cid: 29153362694);
      expect(streams.videos, isNotEmpty);
      final playurl = http.requests.singleWhere((r) => r.url.path == '/x/player/playurl');
      expect(playurl.headers.containsKey('cookie'), isFalse);
      expect(playurl.headers['referer'], 'https://www.bilibili.com/video/BV1zKZrYAEi8/');
      expect(streams.headers.containsKey('cookie'), isFalse);
      await ugc.detail('BV1zKZrYAEi8');
      final view = http.requests.singleWhere((r) => r.url.path == '/x/web-interface/view');
      expect(view.headers['cookie'], 'buvid3=GUEST3-infoc;buvid4=GUEST4;');
    });

    test('signed in: the login cookie goes everywhere, media headers included', () async {
      final vault = MemoryCookieVault()..set('bilibili', 'SESSDATA=s; bili_jct=CSRF; DedeUserID=42; buvid3=OWN');
      final replay = ReplayHttp.fixtures(fixtureRoot, ['V09-playurl-mp4']);
      final http = _Scripted({}, inner: replay);
      final client = BilibiliVodClient(http, cookies: vault);
      expect(client.myMid, 42);
      expect(client.csrf, 'CSRF');
      final streams = await BilibiliUgcApi(client).streams(bvid: 'BV1zKZrYAEi8', cid: 29153362694, mp4: true);
      expect(http.requests.single.headers['cookie'], contains('SESSDATA=s'));
      expect(streams.headers['cookie'], contains('SESSDATA=s'));
      expect(http.requests.where((r) => r.url.path.contains('finger')), isEmpty, reason: 'the cookie has buvid3');
    });
  });

  group('WBI', () {
    test('signed requests carry wts and w_rid; -352 renews the keys and retries once', () async {
      final http = _Scripted({
        '/x/frontend/finger/spi': [_spi],
        '/x/web-interface/nav': [_nav],
        '/x/player/wbi/v2': ['{"code":-352,"message":"风控校验失败"}', Fixture.load('V10-player-v2').body],
      });
      final ugc = BilibiliUgcApi(BilibiliVodClient(http, now: () => DateTime.utc(2026, 10, 1, 5, 37)));
      final info = await ugc.playerInfo(bvid: 'BV1zKZrYAEi8', cid: 29153362694, aid: 114251901441504);
      expect(info.bgmMusicId, 'MA409252858597271902');
      final signed = http.requests.where((r) => r.url.path == '/x/player/wbi/v2').toList();
      expect(signed, hasLength(2));
      expect(
        signed.first.url.queryParameters['wts'],
        '${DateTime.utc(2026, 10, 1, 5, 37).millisecondsSinceEpoch ~/ 1000}',
      );
      expect(signed.first.url.queryParameters['w_rid'], matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(http.requests.where((r) => r.url.path == '/x/web-interface/nav'), hasLength(2), reason: 'keys renewed');
    });

    test('a second -352 is RiskControl', () async {
      final http = _Scripted({
        '/x/frontend/finger/spi': [_spi],
        '/x/web-interface/nav': [_nav],
        '/x/space/wbi/arc/search': [Fixture.load('V17-space-arc-352').body],
      });
      final ugc = BilibiliUgcApi(BilibiliVodClient(http));
      await expectLater(ugc.uploads(28454359), throwsA(isA<RiskControl>()));
      expect(http.requests.where((r) => r.url.path == '/x/space/wbi/arc/search'), hasLength(2));
    });
  });

  group('login', () {
    test('writes and personal lists need a cookie and send nothing without one', () async {
      final http = _Scripted({});
      final ugc = BilibiliUgcApi(BilibiliVodClient(http));
      await expectLater(ugc.setLike(1, like: true), throwsA(isA<NeedsLogin>()));
      await expectLater(ugc.history(), throwsA(isA<NeedsLogin>()));
      await expectLater(ugc.dynamics(), throwsA(isA<NeedsLogin>()));
      await expectLater(
        ugc.reportProgress(aid: 1, cid: 2, progress: const Duration(seconds: 30)),
        throwsA(isA<NeedsLogin>()),
      );
      await expectLater(BilibiliPgcApi(ugc.client).followed(), throwsA(isA<NeedsLogin>()));
      expect(http.requests, isEmpty);
    });

    test('a progress report posts the form with csrf', () async {
      final vault = MemoryCookieVault()..set('bilibili', 'SESSDATA=s; bili_jct=CSRF; DedeUserID=42; buvid3=OWN');
      final http = _Scripted({
        '/x/v2/history/report': ['{"code":0,"data":null}'],
      });
      final ugc = BilibiliUgcApi(BilibiliVodClient(http, cookies: vault));
      await ugc.reportProgress(aid: 114251901441504, cid: 29153362694, progress: const Duration(seconds: 31));
      final request = http.requests.single;
      expect(request.method, 'POST');
      final form = Uri.splitQueryString(utf8.decode(request.body!));
      expect(form, containsPair('csrf', 'CSRF'));
      expect(form, containsPair('progress', '31'));
      expect(form, containsPair('cid', '29153362694'));
    });
  });

  group('paging', () {
    test('comments send the previous next_offset in pagination_str', () async {
      final http = _Scripted({
        '/x/frontend/finger/spi': [_spi],
        '/x/web-interface/nav': [_nav],
        '/x/v2/reply/wbi/main': [Fixture.load('V12-reply-p1').body],
      });
      final ugc = BilibiliUgcApi(BilibiliVodClient(http));
      await ugc.comments(oid: 114251901441504);
      await ugc.comments(oid: 114251901441504, offset: '{"type":1,"data":{"cursor":42}}');
      final sent = [
        for (final r in http.requests.where((r) => r.url.path == '/x/v2/reply/wbi/main'))
          r.url.queryParameters['pagination_str'],
      ];
      expect(sent, ['{"offset":""}', r'{"offset":"{\"type\":1,\"data\":{\"cursor\":42}}"}']);
    });

    test('PGC timeline, index and season over the samples', () async {
      final replay = ReplayHttp.fixtures(fixtureRoot, ['P01-timeline', 'P04-season']);
      final pgc = BilibiliPgcApi(
        BilibiliVodClient(
          _Scripted({
            '/x/frontend/finger/spi': [_spi],
          }, inner: replay),
        ),
      );
      expect(await pgc.timeline(), hasLength(13));
      expect((await pgc.season(seasonId: 47836)).episodes, hasLength(8));
    });
  });

  group('music', () {
    test('a track without a cid is resolved from view, then its best audio picked', () async {
      final replay = ReplayHttp.fixtures(fixtureRoot, ['V05-view']);
      final dash = Fixture.load('V08-playurl-dash').body;
      final http = _Scripted({
        '/x/frontend/finger/spi': [_spi],
        '/x/player/playurl': [dash],
      }, inner: replay);
      final music = BilibiliMusicApi(BilibiliUgcApi(BilibiliVodClient(http)));
      const row = MusicTrack(
        archive: VodArchive(bvid: 'BV1zKZrYAEi8', title: 'x'),
        part: VodPart(cid: 0),
      );
      final result = await music.audio(row);
      expect(result.audio.id, 30232);
      final playurl = http.requests.singleWhere((r) => r.url.path == '/x/player/playurl');
      expect(playurl.url.queryParameters['cid'], '29153362694');
      expect(playurl.url.queryParameters['qn'], '16');
    });

    test('the BGM lyric follows mv_lyric to the LRC file', () async {
      final http = _Scripted({
        '/x/frontend/finger/spi': [_spi],
        '/x/web-interface/nav': [_nav],
        '/x/player/wbi/v2': [Fixture.load('V10-player-v2').body],
        '/x/copyright-music-publicity/bgm/detail': [Fixture.load('M01-bgm-detail').body],
        '/bfs/station_src/music_metadata/2ed6a6e10d73af7e84ede6113b1d5885': [Fixture.load('M02-bgm-lyric').body],
      });
      final music = BilibiliMusicApi(BilibiliUgcApi(BilibiliVodClient(http)));
      final lyric = await music.bgmLyric(bvid: 'BV1zKZrYAEi8', cid: 29153362694);
      expect(lyric?.title, '阳光彩虹小白马');
      expect(Lrc.parse(lyric!.lrc).title, '阳光彩虹小白马');
      final file = http.requests.last;
      expect(file.url.scheme, 'https');
      expect(file.headers.containsKey('cookie'), isFalse);
    });
  });
}
