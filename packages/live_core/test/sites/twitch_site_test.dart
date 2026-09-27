// TwitchSite end to end over the recorded Twitch responses (ReplayHttp). The
// usher query carries the scrubbed token and signature and a random nonce,
// left out of matching.
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

const _ignored = {'sig', 'token', 'p'};

TwitchSite _site(List<String> samples, {CookieVault? cookies}) => TwitchSite(
  ReplayHttp.fixtures('../../fixtures/twitch', samples, ignoredQuery: _ignored),
  cookies: cookies,
  random: Random(4),
);

RoomDetail _room(String login) => RoomDetail(
  card: RoomCard(ref: RoomRef('twitch', login), title: '', anchorName: '', state: LiveState.live),
  link: Uri.parse('https://www.twitch.tv/$login'),
);

void main() {
  test('catalog: the top directories, then one category per tag, in two batches', () async {
    final http = ReplayHttp.fixtures('../../fixtures/twitch', ['S01-tags', 'S01-dirs-1', 'S01-dirs-2']);
    final categories = await TwitchSite(http, random: Random(4)).categories();
    expect(categories, hasLength(41));
    expect((categories.first.id, categories.first.name, categories.first.areas.length), ('top', '热门', 100));
    expect(categories[1].name, '冒险游戏');
    expect(categories[1].areas, hasLength(30));
    expect(http.requests, hasLength(3));
    final batch = jsonDecode(utf8.decode(http.requests[1].body!)) as List;
    expect(batch, hasLength(35));
    final headers = http.requests.first.headers;
    expect(headers['client-id'], twitchClientId);
    expect(headers['device-id'], matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(headers['accept-language'], startsWith('zh-CN'));
    expect(headers.containsKey('authorization'), isFalse);
  });

  test('lists: one page each; a cursor gives nothing (integrity, §8)', () async {
    final site = _site(['S02-game', 'S03-streams', 'S02-game-missing']);
    const chatting = Area(id: 'just-chatting', name: '谈天说地', categoryId: 'top');
    final page = await site.areaRooms(chatting);
    expect(page.items, hasLength(87));
    expect(page.isLast, isTrue);
    expect((await site.areaRooms(chatting, cursor: const PageCursor('x'))).items, isEmpty);
    expect((await site.recommended()).items, hasLength(30));
    expect((await site.recommended(cursor: const PageCursor('x'))).items, isEmpty);
    await expectLater(
      site.areaRooms(const Area(id: 'zzz-not-a-directory', name: '', categoryId: 'top')),
      throwsA(isA<NotFound>()),
    );
  });

  test('search pages by cursor', () async {
    final site = _site(['S04-search-p1', 'S04-search-p2', 'S04-search-empty']);
    final first = await site.search('minecraft');
    expect(first.items, hasLength(10));
    final second = await site.search('minecraft', cursor: first.next);
    expect(second.items, hasLength(15));
    expect((await site.search('qqzzxxyyqqzzxxyy')).isLast, isTrue);
    expect((await site.search('  ')).items, isEmpty);
  });

  test('detail', () async {
    final site = _site(['S05-user-live', 'S05-user-offline', 'S05-user-missing']);
    expect((await site.detail(RoomRef('twitch', 'zarbex'))).state, LiveState.live);
    expect((await site.detail(RoomRef('twitch', 'Minecraft'))).state, LiveState.offline);
    await expectLater(site.detail(RoomRef('twitch', 'zzzznotachannelzzzz')), throwsA(isA<NotFound>()));
    await expectLater(site.detail(RoomRef('twitch', 'not a login')), throwsA(isA<NotFound>()));
  });

  test('streams: token, usher, one HLS line per quality without a lease', () async {
    final site = _site(['S06-pat-live', 'S06-usher-live']);
    final set = await site.streams(_room('zarbex'));
    expect(set.qualities.map((q) => q.id), ['chunked', '720p60', '480p30', '360p30', '160p30']);
    expect(set.selected.label, '1080p50 (source)');
    final line = set.lines.single;
    expect(line.format, StreamFormat.hls);
    expect(line.lease, isNull);
    expect(line.codec, 'avc');
    expect(line.effective.id, 'chunked');
    expect(line.lineId, endsWith('.playlist.ttvnw.net'));
    final low = await site.streams(
      _room('zarbex'),
      quality: const Quality(id: '360p30', label: '360p', rank: 2),
    );
    expect(low.lines.single.requested.id, '360p30');
    expect(low.lines.single.url, isNot(line.url));
  });

  test('streams of an offline channel and an unknown one', () async {
    final site = _site(['S06-pat-offline', 'S06-usher-offline', 'S06-pat-missing']);
    await expectLater(site.streams(_room('minecraft')), throwsA(isA<StreamUnavailable>()));
    await expectLater(site.streams(_room('zzzznotachannelzzzz')), throwsA(isA<NotFound>()));
  });

  test("the user's token goes with the playback token only; a refused one falls back to anonymous", () async {
    final cookies = MemoryCookieVault()..set('twitch', 'login=me; auth-token=oauthsecret123; persistent=x');
    final http = _Refusing(
      ReplayHttp.fixtures('../../fixtures/twitch', ['S06-pat-live', 'S06-usher-live'], ignoredQuery: _ignored),
    );
    final set = await TwitchSite(http, cookies: cookies, random: Random(4)).streams(_room('zarbex'));
    expect(set.lines, hasLength(1));
    expect(http.seen.first.headers['authorization'], 'OAuth oauthsecret123');
    expect(http.seen[1].headers.containsKey('authorization'), isFalse);
  });

  test('links', () async {
    final site = _site(const []);
    expect(await site.resolve('Shroud'), RoomRef('twitch', 'shroud'));
    expect(await site.resolve('https://www.twitch.tv/shroud?sr=a'), RoomRef('twitch', 'shroud'));
    expect(await site.resolve('看这个 https://m.twitch.tv/zarbex/home'), RoomRef('twitch', 'zarbex'));
    expect(await site.resolve('twitch.tv/zarbex'), RoomRef('twitch', 'zarbex'));
    expect(await site.resolve('https://www.twitch.tv/popout/zarbex/chat'), RoomRef('twitch', 'zarbex'));
    expect(await site.resolve('https://player.twitch.tv/?channel=zarbex&parent=x'), RoomRef('twitch', 'zarbex'));
    expect(await site.resolve('https://www.twitch.tv/directory/category/minecraft'), isNull);
    expect(await site.resolve('https://www.youtube.com/shroud'), isNull);
  });
}

/// Answers a request carrying the user's token with 401 (a stale token),
/// everything else from [inner].
final class _Refusing implements LiveHttp {
  new(this.inner);

  final LiveHttp inner;
  final List<LiveRequest> seen = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    seen.add(request);
    if (request.headers.containsKey('authorization')) {
      return LiveResponse(status: 401, url: request.url, bytes: utf8.encode('{"error":"Unauthorized"}'));
    }
    return await inner.send(request);
  }

  @override
  void close() {}
}
