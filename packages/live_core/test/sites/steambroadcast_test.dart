// Steam broadcasts: parsing and the adapter over the recorded samples
// (spec/sites/steambroadcast.md). No legacy expected values (ADR 0016).
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _live = '76561199485215572';
const _offline = '76561197960287930';

SteamBroadcastSite _site(List<String> samples) =>
    SteamBroadcastSite(ReplayHttp.fixtures('../../fixtures/steambroadcast', samples));

Map<String, dynamic> _json(String sample) =>
    jsonDecode(Fixture.load('steambroadcast', sample).body) as Map<String, dynamic>;

void main() {
  group('§2.2 trending broadcasts (HTML)', () {
    test('S01 page 1: ten live cards with game, viewers, cover, author and avatar', () {
      final html = Fixture.load('steambroadcast', 'S01-directory-p1').body;
      final page = SteamBroadcastParse.directory(html, page: 1);
      final ids = RegExp(r'broadcast/watch/(\d{17})').allMatches(html).map((m) => m.group(1)).toSet();
      expect(page.items.map((c) => c.ref.roomId).toSet(), ids);
      expect(page.items, hasLength(10));
      final first = page.items.first;
      expect(first.ref.roomId, _live);
      expect(first.title, 'NTE: Neverness to Everness');
      expect(first.area, 'NTE: Neverness to Everness');
      expect(first.anchorName, 'PWM Game Manager');
      final viewers = RegExp(r'CardContentViewers ellipsis">([\d,]+) viewers').firstMatch(html)!.group(1)!;
      expect(first.audience.online, int.parse(viewers.replaceAll(',', '')));
      expect(first.cover!.host, 'steambroadcast.akamaized.net');
      expect(first.avatar!.host, 'avatars.fastly.steamstatic.com');
      expect(page.items.every((c) => c.state == LiveState.live), isTrue);
      expect(page.next, const PageCursor('2'));
    });

    test('S01 page 2 continues with other broadcasters', () {
      final p1 = SteamBroadcastParse.directory(Fixture.load('steambroadcast', 'S01-directory-p1').body, page: 1);
      final p2 = SteamBroadcastParse.directory(Fixture.load('steambroadcast', 'S01-directory-p2').body, page: 2);
      expect(p2.items, isNotEmpty);
      expect(p2.next, const PageCursor('3'));
      expect(p2.items.map((c) => c.ref).toSet().intersection(p1.items.map((c) => c.ref).toSet()), isEmpty);
    });

    test('viewer counts', () {
      expect(SteamBroadcastParse.viewerCount('4,927 viewers '), 4927);
      expect(SteamBroadcastParse.viewerCount('1 viewer'), 1);
      expect(SteamBroadcastParse.viewerCount('soon'), isNull);
    });
  });

  group('§4 detail', () {
    test('S02-info-live + S03-profile', () {
      final info = _json('S02-info-live');
      final profile = SteamBroadcastParse.profile(Fixture.load('steambroadcast', 'S03-profile').body);
      final detail = SteamBroadcastParse.detail(
        Fixture.load('steambroadcast', 'S02-info-live').body,
        steamId: _live,
        name: profile.name,
        avatar: profile.avatar,
      );
      expect(detail.state, LiveState.live);
      expect(detail.card.anchorName, 'PWM Game Manager');
      expect(detail.card.title, info['app_title'], reason: 'empty broadcast title falls back to the game');
      expect(detail.card.audience.online, info['viewer_count']);
      expect(detail.card.cover.toString(), info['thumbnail_url']);
      expect(detail.danmakuKeys, {'steamid': _live});
      expect(detail.link, Uri.parse('https://steamcommunity.com/broadcast/watch/$_live'));
    });

    test('S02-info-offline: success 42 is offline', () {
      final detail = SteamBroadcastParse.detail(
        Fixture.load('steambroadcast', 'S02-info-offline').body,
        steamId: _offline,
        name: 'x',
      );
      expect(detail.state, LiveState.offline);
      expect(detail.card.audience.isEmpty, isTrue);
      expect(
        () => SteamBroadcastParse.detail('{"success":2}', steamId: _offline, name: 'x'),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('mini profile account id', () {
      expect(SteamBroadcastParse.accountId(_live), '1524949844');
    });
  });

  group('§6 streams', () {
    test('S04-mpd-live: the HLS master; offline and restricted are typed', () {
      final master = SteamBroadcastParse.master(Fixture.load('steambroadcast', 'S04-mpd-live').body);
      expect(master.toString(), _json('S04-mpd-live')['hls_url']);
      expect(
        () => SteamBroadcastParse.master(Fixture.load('steambroadcast', 'S04-mpd-offline').body),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(() => SteamBroadcastParse.master('{"success":"user_restricted"}'), throwsA(isA<NeedsLogin>()));
      final withAuth = SteamBroadcastParse.master(
        '{"success":"ready","hls_url":"https://a.test/b/master.m3u8?broadcast_origin=o","cdn_auth_url_parameters":"&x=1"}',
      );
      expect(withAuth.queryParameters, {'broadcast_origin': 'o', 'x': '1'});
    });
  });

  group('adapter', () {
    test('catalog, detail and streams', () async {
      final site = _site(['S01-directory-p1', 'S02-info-live', 'S03-profile', 'S04-mpd-live']);
      expect(await site.categories(), isEmpty);
      expect((await site.recommended()).items, hasLength(10));
      final detail = await site.detail(RoomRef('steambroadcast', _live));
      expect(detail.state, LiveState.live);
      final set = await site.streams(detail);
      expect(set.lines.single.format, StreamFormat.hls);
      expect(set.lines.single.headers['referer'], detail.link.toString());
    });

    test('links: ids, watch pages and profiles', () async {
      final site = _site(const []);
      expect(await site.resolve(_live), RoomRef('steambroadcast', _live));
      expect(await site.resolve('https://steamcommunity.com/broadcast/watch/$_live'), RoomRef('steambroadcast', _live));
      expect(await site.resolve('来看 https://steamcommunity.com/profiles/$_live/ 吧'), RoomRef('steambroadcast', _live));
      expect(await site.resolve('https://steamcommunity.com/id/someone'), isNull);
      expect(await site.resolve('https://store.steampowered.com/app/1'), isNull);
    });
  });
}
