// TikTok LIVE: the user room answer, room owners and the link-only adapter
// over the recorded samples (spec/sites/tiktok.md). No legacy expected values (ADR 0016).
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

TikTokSite _site(List<String> samples) => TikTokSite(ReplayHttp.fixtures('../../fixtures/tiktok', samples));

/// Answers every request with a redirect to [location], and records the requests.
final class _Redirect implements LiveHttp {
  new(this.location);

  final String location;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    return LiveResponse(
      status: 301,
      bytes: const [],
      url: request.url,
      headers: {
        'location': [location],
      },
    );
  }

  @override
  void close() {}
}

void main() {
  group('§4 user room', () {
    test('S01 live: name, title, viewers, the pull data', () {
      final room = TikTokParse.userRoom(Fixture.load('tiktok', 'S01-user-live').body, roomId: 'qvc');
      expect(room.detail.state, LiveState.live);
      expect(room.detail.card.anchorName, 'QVC, Inc');
      expect(room.detail.card.title, 'Pumpkin Spice Season');
      expect(room.detail.card.audience.online, greaterThan(0));
      expect(room.detail.danmakuKeys['roomId'], '7690279124098681614');
      expect(room.restricted, isFalse);
      expect(room.pull, isNotEmpty);
    });

    test('S01 offline keeps the last title but no audience or streams; a missing user is NotFound', () {
      final room = TikTokParse.userRoom(Fixture.load('tiktok', 'S01-user-offline').body, roomId: 'cnn');
      expect(room.detail.state, LiveState.offline);
      expect(room.detail.card.anchorName, 'CNN');
      expect(room.detail.card.audience, Audience.none);
      expect(room.pull, isEmpty);
      expect(
        () => TikTokParse.userRoom(Fixture.load('tiktok', 'S01-user-missing').body, roomId: 'nasa'),
        throwsA(isA<NotFound>()),
      );
      expect(
        () => TikTokParse.userRoom(Fixture.load('tiktok', 'S01-user-live').body, roomId: 'cnn'),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('subscriber-only rooms are restricted', () {
      final body = Fixture.load('tiktok', 'S01-user-live').body;
      final root = jsonDecode(body) as Map<String, dynamic>;
      ((root['data'] as Map<String, dynamic>)['liveRoom'] as Map<String, dynamic>)['liveSubOnly'] = 1;
      expect(TikTokParse.userRoom(jsonEncode(root), roomId: 'qvc').restricted, isTrue);
    });
  });

  group('§5 qualities and lines', () {
    test('S01 720p from the options; audio-only left out; FLV then HLS with the expire lease', () {
      final room = TikTokParse.userRoom(Fixture.load('tiktok', 'S01-user-live').body, roomId: 'qvc');
      final qualities = TikTokParse.qualities(room.pull, options: room.options);
      expect(qualities.map((q) => (q.id, q.label)), [('hd', '720p')]);
      final lines = TikTokParse.lines(room.pull, qualities.single, headers: const {});
      expect(lines.map((l) => l.format), [StreamFormat.flv, StreamFormat.hls]);
      expect(lines.first.codec, 'avc');
      final lease = lines.first.lease!;
      expect(lease.expiresAt!.difference(lease.refreshAt), const Duration(hours: 1));
      expect(lines.first.url.queryParameters['expire'], isNotNull);
    });
  });

  group('adapter', () {
    test('detail and streams', () async {
      final site = _site(['S01-user-live']);
      final detail = await site.detail(RoomRef('tiktok', 'qvc'));
      final set = await site.streams(detail);
      expect(set.selected.id, 'hd');
      expect(set.lines, hasLength(2));
      expect(set.lines.first.headers['referer'], 'https://www.tiktok.com/@qvc/live');
    });

    test('an offline room has no streams', () async {
      final site = _site(['S01-user-offline']);
      final detail = await site.detail(RoomRef('tiktok', 'cnn'));
      expect(() => site.streams(detail), throwsA(isA<StreamUnavailable>()));
    });

    test('links: @user, profile and LIVE pages; a share link names its owner', () async {
      final site = _site(['S02-room-live']);
      expect(await site.resolve('@QVC'), RoomRef('tiktok', 'qvc'));
      expect(await site.resolve('https://www.tiktok.com/@qvc/live?lang=en'), RoomRef('tiktok', 'qvc'));
      expect(await site.resolve('看 https://m.tiktok.com/@qvc 吧'), RoomRef('tiktok', 'qvc'));
      expect(
        await site.resolve('https://www.tiktok.com/share/live/7690279124098681614?u_code=x'),
        RoomRef('tiktok', 'qvc'),
      );
      expect(await site.resolve('https://www.tiktok.com/@qvc/video/7690000000000000000'), isNull);
      expect(await site.resolve('qvc'), isNull, reason: 'a bare word is not a TikTok room');
      expect(await site.resolve('https://www.douyu.com/9999'), isNull);
    });

    test('a short link follows one redirect on TikTok only', () async {
      final ok = _Redirect('https://www.tiktok.com/@qvc/live?_r=1');
      expect(await TikTokSite(ok).resolve('https://vm.tiktok.com/ZMabcdef/'), RoomRef('tiktok', 'qvc'));
      expect(ok.requests.single.followRedirects, isFalse);
      final away = _Redirect('https://example.com/@qvc/live');
      expect(await TikTokSite(away).resolve('https://vt.tiktok.com/ZSabcdef/'), isNull);
    });
  });
}
