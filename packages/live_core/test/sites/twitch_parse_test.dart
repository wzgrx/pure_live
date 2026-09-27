// v4 Twitch parsing against the recorded samples (spec/sites/twitch.md §11);
// the legacy parser no longer runs (ADR 0016), expected values are here.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _load(String sample) => Fixture.load('twitch', sample);

void main() {
  group('S01 catalog', () {
    test('category tags in Chinese; a tag without a name is left out', () {
      final tags = TwitchParse.tags(_load('S01-tags').body);
      expect(tags, hasLength(40));
      expect(tags.first.name, '冒险游戏');
      expect(tags.first.id, '80427d95-bb46-42d3-bf4d-408e9bdca49a');
    });

    test('a batched directory answer: one envelope per operation, slugs as area ids', () {
      final envelopes = TwitchParse.batch(_load('S01-dirs-1').body, expected: 35);
      final top = TwitchParse.directories(envelopes.first, categoryId: 'top');
      expect(top, hasLength(100));
      expect((top.first.id, top.first.name, top.first.categoryId), ('fortnite', 'Fortnite', 'top'));
      expect(top.first.icon?.host, 'static-cdn.jtvnw.net');
      expect(top.map((a) => a.name), contains('谈天说地'), reason: 'names follow Accept-Language');
      expect(TwitchParse.directories(envelopes[1], categoryId: 'x'), hasLength(30));
      expect(() => TwitchParse.batch(_load('S01-dirs-2').body, expected: 7), throwsA(isA<ApiChanged>()));
    });
  });

  group('S02/S03 stream lists', () {
    test('a directory: one page of live streams, no next page', () {
      final page = TwitchParse.gameStreams(_load('S02-game').body, slug: 'just-chatting');
      expect(page.items, hasLength(87));
      expect(page.isLast, isTrue);
      final first = page.items.first;
      expect(first.ref, RoomRef('twitch', 'zackrawrr'));
      expect(first.state, LiveState.live);
      expect(first.area, '谈天说地');
      expect(first.audience.online, greaterThan(1000));
      expect(first.cover?.path, endsWith('-440x248.jpg'));
    });

    test('an unknown directory is NotFound; a later page needs integrity (RiskControl)', () {
      expect(
        () => TwitchParse.gameStreams(_load('S02-game-missing').body, slug: 'zzz-not-a-directory'),
        throwsA(isA<NotFound>()),
      );
      expect(
        () => TwitchParse.gameStreams(_load('S02-game-cursor').body, slug: 'just-chatting'),
        throwsA(isA<RiskControl>().having((e) => e.detail, 'detail', contains('integrity'))),
      );
    });

    test('the site-wide list: 30 streams with their start time', () {
      final page = TwitchParse.streams(_load('S03-streams').body);
      expect(page.items, hasLength(30));
      expect(page.items.first.ref, RoomRef('twitch', 'auronplay'));
      expect(page.items.first.liveSince, DateTime.utc(2026, 9, 27, 16, 28, 19));
      expect(page.isLast, isTrue);
    });
  });

  group('S04 search', () {
    test('channels live or not; the cursor pages on; an empty cursor ends', () {
      final first = TwitchParse.searchPage(_load('S04-search-p1').body);
      expect(first.items, hasLength(10));
      expect(first.next, const PageCursor('MTA='));
      expect(first.items.map((r) => (r.ref.roomId, r.state)).take(2), [
        ('feinberg', LiveState.live),
        ('minecraft', LiveState.offline),
      ]);
      expect(first.items[1].audience, Audience.none);
      expect(first.items.first.cover?.path, endsWith('-440x248.jpg'));
      final second = TwitchParse.searchPage(_load('S04-search-p2').body);
      expect(second.items, hasLength(15));
      expect(second.next, const PageCursor('MjU='));
      final empty = TwitchParse.searchPage(_load('S04-search-empty').body);
      expect(empty.items, isEmpty);
      expect(empty.isLast, isTrue);
    });
  });

  group('S05 detail', () {
    test('live, offline (last broadcast title), unknown', () {
      final live = TwitchParse.detail(_load('S05-user-live').body, login: 'zarbex');
      expect(live.state, LiveState.live);
      expect(live.card.anchorName, 'zarbex');
      expect(live.card.liveSince, DateTime.utc(2026, 9, 27, 12, 49, 35));
      expect(live.card.audience.online, 23169);
      expect(live.danmakuKeys, {'login': 'zarbex', 'channelId': '403594122'});
      expect(live.link, Uri.parse('https://www.twitch.tv/zarbex'));
      final offline = TwitchParse.detail(_load('S05-user-offline').body, login: 'minecraft');
      expect(offline.state, LiveState.offline);
      expect(offline.card.title, 'Minecraft LIVE - September 2026');
      expect(offline.card.area, 'Minecraft');
      expect(offline.introduction, startsWith('Survive the night'));
      expect(
        () => TwitchParse.detail(_load('S05-user-missing').body, login: 'zzzznotachannelzzzz'),
        throwsA(isA<NotFound>()),
      );
      expect(() => TwitchParse.detail(_load('S05-user-live').body, login: 'other'), throwsA(isA<ApiChanged>()));
    });
  });

  group('S06 playback', () {
    test('the access token; an unknown login is NotFound; a forbidden token names why', () {
      final token = TwitchParse.accessToken(_load('S06-pat-live').body, login: 'zarbex');
      expect(token.value, contains('"channel":"zarbex"'));
      expect(token.signature, hasLength(40));
      expect(
        () => TwitchParse.accessToken(_load('S06-pat-missing').body, login: 'zzzznotachannelzzzz'),
        throwsA(isA<NotFound>()),
      );
      String forbidden(String reason) => jsonEncode({
        'data': {
          'streamPlaybackAccessToken': {
            'value': jsonEncode({
              'authorization': {'forbidden': true, 'reason': reason},
            }),
            'signature': 's',
          },
        },
      });
      expect(() => TwitchParse.accessToken(forbidden('geoblock'), login: 'x'), throwsA(isA<RegionBlocked>()));
      expect(() => TwitchParse.accessToken(forbidden('subs only'), login: 'x'), throwsA(isA<NeedsLogin>()));
    });

    test('the usher URL carries the token; its answer: 404 offline, 403 by reason', () {
      final url = TwitchParse.usherUrl('zarbex', (value: '{"a":1}', signature: 'abc'), nonce: 7);
      expect(url.host, 'usher.ttvnw.net');
      expect(url.path, '/api/channel/hls/zarbex.m3u8');
      expect(url.queryParameters['token'], '{"a":1}');
      expect(url.queryParameters['sig'], 'abc');
      expect(url.queryParameters['supported_codecs'], 'avc1');
      final offline = _load('S06-usher-offline');
      expect(() => TwitchParse.usherStatus(offline.status, offline.body), throwsA(isA<StreamUnavailable>()));
      expect(
        () => TwitchParse.usherStatus(403, '[{"error":"Content is geoblocked","error_code":"content_geoblocked"}]'),
        throwsA(isA<RegionBlocked>()),
      );
      expect(
        () => TwitchParse.usherStatus(403, '[{"error":"x","error_code":"unauthorized_entitlements"}]'),
        throwsA(isA<NeedsLogin>()),
      );
      expect(() => TwitchParse.usherStatus(502, ''), throwsA(isA<NetworkFailure>()));
      TwitchParse.usherStatus(200, '#EXTM3U');
    });

    test('the master playlist: the source first, named by EXT-X-MEDIA, avc', () {
      final master = _load('S06-usher-live');
      final variants = TwitchParse.master(master.body, base: Uri.parse('https://usher.ttvnw.net/x.m3u8'));
      expect(variants.map((v) => v.quality.id), ['chunked', '720p60', '480p30', '360p30', '160p30']);
      expect(variants.first.quality.label, '1080p50 (source)');
      expect(variants.first.quality.rank, 5);
      expect(variants.every((v) => v.codec == 'avc' && v.url.path.startsWith('/v1/playlist/')), isTrue);
      expect(() => TwitchParse.master('<html>', base: Uri.parse('https://x/')), throwsA(isA<ApiChanged>()));
      expect(() => TwitchParse.master('#EXTM3U\n', base: Uri.parse('https://x/')), throwsA(isA<StreamUnavailable>()));
    });
  });
}
