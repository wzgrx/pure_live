// PandaTV parsing and the adapter over the recorded samples
// (spec/sites/pandalive.md). Legacy no longer runs (ADR 0016), so the
// expectations come from the sample bodies and the spec.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _live = 'daisy00';
const _offline = 'flffl369';

PandaliveSite _site(List<String> samples) =>
    PandaliveSite(ReplayHttp.fixtures('../../fixtures/pandalive', samples, ignoredQuery: {'token'}));

Map<String, dynamic> _body(String sample) => jsonDecode(Fixture.load('pandalive', sample).body) as Map<String, dynamic>;

void main() {
  group('§2 directory', () {
    test('live/index rows are live cards with online and cumulative audience in Korean time', () {
      final page = PandaliveParse.indexPage(Fixture.load('pandalive', 'S01-index-hot').body, offset: 0);
      final rows = (_body('S01-index-hot')['list'] as List).cast<Map<String, dynamic>>();
      expect(page.items.map((c) => c.ref.roomId), rows.map((r) => r['userId']));
      expect(page.next, const PageCursor('30'));
      final first = rows.first;
      final card = page.items.first;
      expect(card.state, LiveState.live);
      expect(card.title, (first['title'] as String).trim());
      expect(card.anchorName, first['userNick']);
      expect(card.audience, Audience(online: first['user'] as int, cumulative: first['playCnt'] as int));
      expect(card.cover, Uri.parse(first['thumbUrl'] as String));
      expect(card.avatar, Uri.parse(first['userImg'] as String));
      expect(card.liveSince, PandaliveParse.koreanTime(first['startTime']));
    });

    test('Korean time is UTC+9; the zero date is none', () {
      expect(PandaliveParse.koreanTime('2026-09-28 02:00:35'), DateTime.utc(2026, 9, 27, 17, 0, 35));
      expect(PandaliveParse.koreanTime('0000-00-00 00:00:00'), isNull);
      expect(PandaliveParse.koreanTime(null), isNull);
    });

    test('the last page ends the directory; a wrong offset is an API change', () {
      final last = PandaliveParse.indexPage(Fixture.load('pandalive', 'S01-index-hot-last').body, offset: 120);
      expect(last.items, isNotEmpty);
      expect(last.isLast, isTrue);
      expect(
        () => PandaliveParse.indexPage(Fixture.load('pandalive', 'S01-index-hot').body, offset: 30),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('new broadcasters fit on one page', () {
      final page = PandaliveParse.indexPage(Fixture.load('pandalive', 'S02-index-newbj').body, offset: 0);
      expect(page.items, hasLength((_body('S02-index-newbj')['page'] as Map)['total']));
      expect(page.isLast, isTrue);
    });
  });

  group('§3 search', () {
    test('broadcasters: live ones from their media, offline ones as profiles', () {
      final page = PandaliveParse.broadcasterPage(Fixture.load('pandalive', 'S03-search-bj').body, offset: 0);
      expect(page.items.map((c) => c.ref.roomId), [_live, _offline, 'hhd006', 'candygirl35']);
      expect(page.items.first.state, LiveState.live);
      expect(page.items.first.audience.online, isNotNull);
      expect(page.items[1].state, LiveState.offline);
      expect(page.items[1].audience, Audience.none);
      expect(page.isLast, isTrue);
    });
  });

  group('§4 detail', () {
    test('a live broadcaster', () {
      final detail = PandaliveParse.detail(Fixture.load('pandalive', 'S04-member-live').body, userId: _live);
      final media = _body('S04-member-live')['media'] as Map<String, dynamic>;
      expect(detail.ref, RoomRef('pandalive', _live));
      expect(detail.state, LiveState.live);
      expect(detail.card.title, media['title']);
      expect(detail.card.audience.online, media['user']);
      expect(detail.card.liveSince, DateTime.utc(2026, 9, 27, 17, 0, 35));
      expect(detail.link, Uri.parse('https://www.pandalive.co.kr/play/daisy00'));
      expect(detail.introduction, isNotEmpty);
      expect(detail.danmakuKeys, {'userId': _live, 'channel': '24133575'});
    });

    test('an offline broadcaster uses the channel title; unknown ids are NotFound', () {
      final offline = PandaliveParse.detail(Fixture.load('pandalive', 'S04-member-offline').body, userId: _offline);
      expect(offline.state, LiveState.offline);
      expect(offline.card.title, '데이지ෆ님의 방송국');
      expect(offline.danmakuKeys, isEmpty);
      final missing = Fixture.load('pandalive', 'S04-member-notfound');
      expect(missing.status, 400);
      expect(
        () => PandaliveParse.detail(missing.body, userId: 'zxqvnouserfix', status: missing.status),
        throwsA(isA<NotFound>()),
      );
      expect(
        () => PandaliveParse.detail(Fixture.load('pandalive', 'S04-member-live').body, userId: _offline),
        throwsA(isA<ApiChanged>()),
      );
    });
  });

  group('§6 play', () {
    test('a public live broadcast: chat channel and token, the IVS master', () {
      final play = PandaliveParse.play(Fixture.load('pandalive', 'S05-play-live').body, userId: _live);
      expect(play.channel, '24133575');
      expect(play.chatToken, isNotEmpty);
      expect(play.master.host, endsWith('.playback.live-video.net'));
      expect(play.master.queryParameters['token'], isNotEmpty);
    });

    test('refusals: ended is StreamUnavailable, 19+ needs a login', () {
      for (final (sample, type) in [
        ('S05-play-castend', isA<StreamUnavailable>()),
        ('S05-play-needlogin', isA<NeedsLogin>()),
      ]) {
        final fixture = Fixture.load('pandalive', sample);
        expect(fixture.status, 400);
        expect(() => PandaliveParse.play(fixture.body, userId: 'x', status: fixture.status), throwsA(type));
      }
      for (final (code, type) in [
        ('needLogin', isA<NeedsLogin>()),
        ('needPassword', isA<StreamUnavailable>()),
        ('somethingNew', isA<StreamUnavailable>()),
      ]) {
        final body = jsonEncode({
          'result': false,
          'message': 'x',
          'errorData': {'code': code},
        });
        expect(() => PandaliveParse.play(body, userId: 'x', status: 400), throwsA(type), reason: code);
      }
      expect(() => PandaliveParse.root('{}', what: 'x', status: 429), throwsA(isA<RateLimited>()));
      expect(() => PandaliveParse.root('{}', what: 'x', status: 502), throwsA(isA<NetworkFailure>()));
      expect(() => PandaliveParse.root('<html>', what: 'x'), throwsA(isA<ApiChanged>()));
    });
  });

  test('§5 streams: IVS variants best first, the source marked, lines are variant playlists', () {
    final master = Uri.parse('https://x.us-west-2.playback.live-video.net/api/video/v1/c.m3u8?token=t');
    final set = PandaliveParse.streams(
      Fixture.load('pandalive', 'S06-master').body,
      master: master,
      headers: PandaliveSite.mediaHeaders,
    );
    expect(set.qualities.map((q) => q.id), ['1080p', '720p', '480p', '360p', '160p']);
    expect(set.qualities.first.label, '1080p 原画');
    expect(set.selected.id, '1080p');
    final line = set.lines.single;
    expect(line.url.host, endsWith('.playlist.live-video.net'));
    expect(line.url.path, startsWith('/v1/playlist/'));
    expect(line.codec, 'avc');
    expect(line.headers['origin'], 'https://www.pandalive.co.kr');
    expect(line.lease, isNull);
    final low = PandaliveParse.streams(
      Fixture.load('pandalive', 'S06-master').body,
      master: master,
      headers: const {},
      wanted: '360p',
    );
    expect(low.lines.single.confirmed?.id, '360p');
  });

  test('§1 links', () {
    for (final link in [
      'https://www.pandalive.co.kr/play/daisy00',
      'https://m.pandalive.co.kr/play/daisy00',
      'https://www.pandalive.co.kr/live/play/daisy00',
      'https://www.pandalive.co.kr/channel/daisy00/home/member',
      '보러 와 https://www.pandalive.co.kr/play/daisy00 !',
    ]) {
      expect(PandaliveParse.userIdOf(link), _live, reason: link);
    }
    expect(PandaliveParse.userIdOf('https://www.pandalive.co.kr/play/1506087545@ka'), '1506087545@ka');
    expect(PandaliveParse.userIdOf('https://www.pandalive.co.kr/live'), isNull);
    expect(PandaliveParse.userIdOf('https://example.test/play/daisy00'), isNull);
    expect(PandaliveParse.userIdOf('daisy00'), isNull);
  });

  group('adapter over ReplayHttp', () {
    test('catalog: two areas, the hot directory pages, new broadcasters', () async {
      final site = _site(['S01-index-hot', 'S01-index-hot-last', 'S02-index-newbj']);
      final areas = (await site.categories()).single.areas;
      expect(areas.map((a) => a.id), ['hot', 'newbj']);
      final first = await site.recommended();
      expect(first.items, hasLength(30));
      final last = await site.areaRooms(areas.first, cursor: const PageCursor('120'));
      expect(last.isLast, isTrue);
      expect((await site.areaRooms(areas.last)).items, isNotEmpty);
    });

    test('search: live matches first, then broadcasters without duplicates', () async {
      final site = _site(['S03-search-live', 'S03-search-bj']);
      final page = await site.search('데이지');
      expect(page.items.map((c) => c.ref.roomId), [_live, 'chirch', _offline, 'hhd006', 'candygirl35']);
      expect(page.isLast, isTrue);
    });

    test('detail and streams: live/play, then the single-use master read once', () async {
      final site = _site(['S04-member-live', 'S05-play-live', 'S06-master']);
      final detail = await site.detail(RoomRef('pandalive', _live));
      final set = await site.streams(detail);
      expect(set.qualities, hasLength(5));
      expect(set.lines.single.headers, PandaliveSite.mediaHeaders);
    });

    test('links resolve without a request', () async {
      final site = _site(const []);
      expect(await site.resolve('https://www.pandalive.co.kr/play/daisy00'), RoomRef('pandalive', _live));
      expect(await site.resolve('https://www.showroom-live.com/r/x'), isNull);
      await expectLater(site.detail(RoomRef('pandalive', 'bad id')), throwsA(isA<NotFound>()));
    });
  });
}
