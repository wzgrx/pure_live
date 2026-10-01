// KickApi over the recorded answers (fixtures/kick, 2026-10-01, anonymous,
// curl: dart:io is refused by Kick's Cloudflare) and synthetic edge cases.
// Kick was retired in 3.x 3.2.11 and has no v3 output to compare with; the
// cases follow pure_live_TV's KickApi (e1cca224) and the recorded shapes.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

String _body(String sample) => Fixture.load('kick', sample).body;

Map<String, Object?> _json(String sample) => jsonDecode(_body(sample)) as Map<String, Object?>;

String _encode(Object value) => jsonEncode(value);

void main() {
  group('catalog', () {
    test('main categories in Kick order, named in Chinese', () {
      final list = KickApi.mainCategories(_body('S01-categories'));
      expect(list.map((c) => c.slug), ['games', 'irl', 'music', 'gambling', 'creative', 'alternative']);
      expect(list.map((c) => c.name), ['游戏', '生活', '音乐', '博彩', '创作', '其他']);
    });

    test('subcategories: areas of their parent, by viewers, with the banner', () {
      final areas = KickApi.subcategories(_body('S01-subcategories-games'), parent: (slug: 'games', name: '游戏'));
      expect(areas, hasLength(32));
      expect(areas.first.areaId, 'ea-sports-fc-27');
      expect(areas.first.areaName, 'EA Sports FC 27');
      expect(areas.first.areaType, 'subcategory');
      expect(areas.first.typeName, '游戏');
      expect(areas.first.platform, 'kick');
      expect(areas.first.areaPic, startsWith('https://files.kick.com/images/subcategories/14353/banner/'));
      expect(
        KickApi.subcategories(_body('S01-subcategories-music'), parent: (slug: 'music', name: '音乐')),
        hasLength(6),
      );
    });

    test('a subcategory of another parent is left out; no usable row fails', () {
      final body = _encode({
        'data': [
          {
            'slug': 'slots',
            'name': 'Slots',
            'category': {'slug': 'gambling'},
          },
        ],
      });
      expect(() => KickApi.subcategories(body, parent: (slug: 'games', name: '游戏')), throwsA(isA<ApiChanged>()));
      expect(KickApi.subcategories(_encode({'data': <Object>[]}), parent: (slug: 'games', name: '游戏')), isEmpty);
    });

    test('Cloudflare refusal is RiskControl, other statuses typed', () {
      const refused = '{"error": "Request blocked by security policy.", "reference": "dda9bc1f"}';
      expect(
        () => KickApi.mainCategories(refused, status: 403),
        throwsA(isA<RiskControl>().having((e) => e.detail, 'detail', contains('Cloudflare'))),
      );
      expect(() => KickApi.mainCategories('', status: 429), throwsA(isA<RateLimited>()));
      expect(() => KickApi.mainCategories('', status: 502), throwsA(isA<NetworkFailure>()));
      expect(() => KickApi.mainCategories('<html>'), throwsA(isA<ApiChanged>()));
    });
  });

  group('lists', () {
    test('recommendations: live cards by viewers', () {
      final page = KickApi.directoryPage(_body('S03-recommend-p1'), page: 1, pageSize: 30);
      expect(page.rooms, hasLength(30));
      expect(page.hasMore, isTrue);
      final first = page.rooms.first;
      expect(first.roomId, 'lonche');
      expect(first.userId, '3862536');
      expect(first.nick, 'Lonche');
      expect(first.title, startsWith('CARNITA ASADA'));
      expect(first.onlineViewers, '43022');
      expect(first.watching, '43022');
      expect(first.audienceMetricType, AudienceMetricType.onlineViewers);
      expect(first.area, 'IRL');
      expect(first.liveStatus, LiveStatus.live);
      expect(first.startedAt, DateTime.utc(2026, 9, 30, 20, 27, 38));
      expect(first.link, 'https://kick.com/lonche');
      expect(first.cover, startsWith('https://images.kick.com/video_thumbnails/'));
      expect(first.avatar, startsWith('https://files.kick.com/images/user/'));
      expect(first.httpHeaders['referer'], 'https://kick.com/lonche/');
      expect(first.notice, '');
    });

    test('a hidden viewer count stays unknown; a mature broadcast has a notice', () {
      final rooms = {
        for (final room in KickApi.directoryPage(_body('S03-recommend-p1'), page: 1, pageSize: 30).rooms)
          room.roomId: room,
      };
      expect(rooms['aquino']!.onlineViewers, '');
      expect(rooms['aquino']!.watching, '');
      expect(rooms['xqc']!.notice, KickApi.matureNotice);
      expect(rooms['xqc']!.restriction, LiveRestriction.none);
    });

    test('a subcategory page keeps only its rows; an unknown one is NotFound', () {
      final page = KickApi.directoryPage(_body('S02-category-p1'), page: 1, pageSize: 30, subcategory: 'just-chatting');
      expect(page.rooms, hasLength(30));
      expect(page.rooms.every((room) => room.area == 'Just Chatting'), isTrue);
      // Kick ignores a subcategory it does not know and answers everything.
      expect(
        () => KickApi.directoryPage(
          _body('S02-category-missing'),
          page: 1,
          pageSize: 30,
          subcategory: 'no-such-category-zz',
        ),
        throwsA(isA<NotFound>()),
      );
    });

    test('the end of a list', () {
      final page = KickApi.directoryPage(_body('S02-category-last'), page: 2, pageSize: 30, subcategory: 'chess');
      expect(page.rooms, isEmpty);
      expect(page.hasMore, isFalse);
      expect(
        () => KickApi.directoryPage(_body('S02-category-last'), page: 3, pageSize: 30),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('banned, ended and slug-less rows are left out', () {
      Map<String, Object?> row(String slug, {bool banned = false, bool live = true}) => {
        'is_live': live,
        'session_title': 't',
        'channel': {
          'id': 1,
          'slug': slug,
          'is_banned': banned,
          'user': {'username': slug},
        },
      };
      final page = KickApi.directoryPage(
        _encode({
          'current_page': 1,
          'next_page_url': null,
          'data': [row('ok'), row('gone', banned: true), row('ended', live: false), row('')],
        }),
        page: 1,
        pageSize: 30,
      );
      expect(page.rooms.map((room) => room.roomId), ['ok']);
    });
  });

  group('search', () {
    test('channels first (live or not, followers), then tagged broadcasts', () {
      final rooms = KickApi.searchRooms(_body('S04-search'));
      expect(rooms.first.roomId, 'xqc');
      expect(rooms.first.nick, 'xQc');
      expect(rooms.first.liveStatus, LiveStatus.live);
      expect(rooms.first.followers, '1117677');
      expect(rooms.first.cover, '');
      expect(rooms[1].roomId, 'xqcisoffline');
      expect(rooms[1].liveStatus, LiveStatus.offline);
      expect(rooms.map((room) => room.roomId).toSet(), hasLength(rooms.length));
      expect(KickApi.searchRooms(_body('S04-search-empty')), isEmpty);
    });
  });

  group('rooms', () {
    test('a live channel: the room, the signed master and the chatroom', () {
      final channel = KickApi.channel(_body('S05-channel-live'), requestedSlug: 'XQC');
      final room = channel.room;
      expect(room.roomId, 'xqc');
      expect(room.userId, '668');
      expect(room.nick, 'xQc');
      expect(room.title, contains('LOCK IN'));
      expect(room.liveStatus, LiveStatus.live);
      expect(room.onlineViewers, '7375');
      expect(room.followers, '1117677');
      expect(room.area, 'Just Chatting');
      expect(room.startedAt, DateTime.utc(2026, 9, 30, 19, 24, 14));
      expect(room.cover, startsWith('https://stream.kick.com/thumbnails/livestream/129925755/'));
      expect(room.introduction, startsWith('THE BEST AT ABSOLUTELY EVERYTHING'));
      expect(room.notice, KickApi.matureNotice);
      expect(channel.master!.host, 'fa723fc1b171.us-west-2.playback.live-video.net');
      expect(KickApi.tokenExpiry(channel.master!), DateTime.fromMillisecondsSinceEpoch(1790833860000, isUtc: true));
      expect(KickApi.danmakuArgs(channel), const KickDanmakuArgs(chatroomId: 668, channelId: 668, slug: 'xqc'));
    });

    test('an offline channel: no stream, its own chatroom id', () {
      final channel = KickApi.channel(_body('S05-channel-offline'), requestedSlug: 'xqcisoffline');
      expect(channel.room.liveStatus, LiveStatus.offline);
      expect(channel.room.title, '');
      expect(channel.room.followers, '904');
      expect(channel.master, isNull);
      // The chatroom id is not the channel id.
      expect(
        KickApi.danmakuArgs(channel),
        const KickDanmakuArgs(chatroomId: 101689, channelId: 101691, slug: 'xqcisoffline'),
      );
    });

    test('a missing channel is NotFound; another channel ApiChanged', () {
      final missing = Fixture.load('kick', 'S05-channel-missing');
      expect(
        () => KickApi.channel(missing.body, requestedSlug: 'zzqqxxnotachannel', status: missing.status),
        throwsA(isA<NotFound>()),
      );
      expect(() => KickApi.channel(_body('S05-channel-live'), requestedSlug: 'other'), throwsA(isA<ApiChanged>()));
    });

    test('a banned channel', () {
      final json = _json('S05-channel-live')..['is_banned'] = true;
      final channel = KickApi.channel(_encode(json), requestedSlug: 'xqc');
      expect(channel.room.liveStatus, LiveStatus.banned);
      expect(channel.master, isNull);
    });
  });

  group('streams', () {
    final master = Fixture.load('kick', 'S06-master');

    test('qualities by rendition name, best first, with codecs', () {
      final data = KickApi.roomData(master.body, slug: 'xqc', master: master.url, status: master.status);
      expect(data.qualities.map((q) => q.id), ['1080p60', '720p60', '480p', '360p', '160p']);
      expect(data.qualities.map((q) => q.quality), ['1080p60', '720p60', '480p', '360p', '160p']);
      expect(data.qualities.first.data, [
        startsWith('https://fa723fc1b171.use22.playlist.live-video.net/v1/playlist/'),
      ]);
      expect(data.codecs['1080p60'], 'avc');
      expect(data.tokenExpiresAt, DateTime.fromMillisecondsSinceEpoch(1790833860000, isUtc: true));
    });

    test('a line: variant playlist, media headers, HLS, codec, no lease', () {
      final data = KickApi.roomData(master.body, slug: 'xqc', master: master.url);
      final resolution = KickApi.resolution(data, data.qualities[1]);
      final line = resolution.lines.single;
      expect(line.url, data.qualities[1].data is List ? (data.qualities[1].data! as List).single : null);
      expect(line.format, StreamFormat.hls);
      expect(line.codec, 'avc');
      expect(line.headers, {
        'user-agent': KickApi.userAgent,
        'origin': 'https://kick.com',
        'referer': 'https://kick.com/xqc/',
      });
      expect(line.lineId, master.url.host);
      expect(line.lease, isNull);
      expect(resolution.appliedQualityData, '720p60');
    });

    test('a refused or gone master is StreamUnavailable; a playlist without variants too', () {
      expect(() => KickApi.qualities('', master: master.url, status: 403), throwsA(isA<StreamUnavailable>()));
      expect(() => KickApi.qualities('', master: master.url, status: 404), throwsA(isA<StreamUnavailable>()));
      expect(() => KickApi.qualities('#EXTM3U\n', master: master.url), throwsA(isA<StreamUnavailable>()));
      expect(() => KickApi.qualities('nope', master: master.url), throwsA(isA<ApiChanged>()));
    });

    test('without a rendition name: height and frame rate', () {
      const text =
          '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=9000000,RESOLUTION=1920x1080,FRAME-RATE=60.000,CODECS="hvc1.1.6.L120"\n'
          'a.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=852x480,FRAME-RATE=30.000\n'
          'b.m3u8\n';
      final data = KickApi.roomData(text, slug: 'x', master: Uri.parse('https://x.live-video.net/m.m3u8'));
      expect(data.qualities.map((q) => q.id), ['1080p60', '480p']);
      expect(data.qualities.first.data, ['https://x.live-video.net/a.m3u8']);
      expect(data.codecs, {'1080p60': 'hevc'});
    });
  });

  group('links', () {
    test('channel pages', () {
      expect(KickApi.slugFromUrl(Uri.parse('https://kick.com/xqc')), 'xqc');
      expect(KickApi.slugFromUrl(Uri.parse('https://www.kick.com/XQC/')), 'xqc');
      expect(KickApi.slugFromUrl(Uri.parse('http://kick.com/some_one-2?ref=x')), 'some_one-2');
      expect(KickApi.slugFromUrl(Uri.parse('https://kick.com/categories')), isNull);
      expect(KickApi.slugFromUrl(Uri.parse('https://kick.com/xqc/videos/1')), isNull);
      expect(KickApi.slugFromUrl(Uri.parse('https://notkick.com/xqc')), isNull);
      expect(KickApi.slugFromUrl(Uri.parse('https://kick.com/')), isNull);
    });

    test('slugs', () {
      expect(KickApi.normalizeSlug(' XQC '), 'xqc');
      expect(KickApi.normalizeSlug('a b'), isNull);
      expect(KickApi.normalizeSlug('search'), isNull);
      expect(KickApi.normalizeSlug(''), isNull);
    });
  });
}
