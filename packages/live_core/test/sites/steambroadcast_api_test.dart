// Steam broadcast parsing against the recorded samples, compared field by
// field with 3.x's frozen output (expected.json, written by
// fixtures/steambroadcast/legacy_expected.dart from 3.x's SteamBroadcastApi,
// SteamBroadcastLink and SteamBroadcastSite). Every intended difference is
// listed with its reason; everything else must match. The synthetic cases
// port 3.x's steam_broadcast_site_test.dart and pin 3.x's checks.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('steambroadcast', name);

const _live = '76561199485215572';
const _offline = '76561197960287930';

/// Asserts that [actual] (a `toJson` plus `link`) equals 3.x's [legacy] map
/// on every key 3.x wrote, except [changed] (intended differences) and
/// `data` (3.x's `SteamBroadcastRoom`, compared on its own). 3.x wrote null
/// where the immutable model writes ''.
void _expectParity(
  Map<String, Object?> actual,
  Map<String, dynamic> legacy, {
  Set<String> changed = const {},
  String? reason,
}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (changed.contains(key) || key == 'data') continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
}

/// 3.x's room projection: toJson plus `link`.
Map<String, Object?> _projection(LiveRoom room) => {...room.toJson(), 'link': room.link};

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

/// The `result` of a traced legacy call.
Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {String reason = ''}) {
  final expected = _maps(legacy);
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(_projection(room), expected[index], reason: '$reason[$index]');
  }
}

/// 3.x's `SteamBroadcastRoom` projection of [broadcast], for the fields both
/// have.
void _expectBroadcast(SteamBroadcast broadcast, Map<String, dynamic> legacy, {Set<String> changed = const {}}) {
  final actual = <String, Object?>{
    'steamId': broadcast.steamId,
    'broadcaster': broadcast.broadcaster,
    'title': broadcast.title,
    'game': broadcast.game,
    'cover': broadcast.cover,
    'avatar': broadcast.avatar,
    'currentViewers': broadcast.viewers,
    'state': broadcast.state.name,
    'master': broadcast.master?.toString(),
  };
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (changed.contains(key)) continue;
    expect(actual[key], value, reason: '${broadcast.steamId} $key');
  }
}

SteamBroadcastPage _page(String sample, int page) =>
    SteamBroadcastApi.directory(_sample(sample).body, page: page, status: _sample(sample).status);

List<LiveRoom> _cards(SteamBroadcastPage page) => [
  for (final broadcast in page.broadcasts) SteamBroadcastApi.room(broadcast),
];

String _mpdBody(Map<String, Object?> changes, {String sample = 'S04-mpd-live'}) {
  final root = jsonDecode(_sample(sample).body) as Map<String, dynamic>;
  for (final MapEntry(:key, :value) in changes.entries) {
    root[key] = value;
  }
  return jsonEncode(root);
}

SteamBroadcast _broadcast(String body, {String steamId = _live}) =>
    SteamBroadcastApi.broadcast(body, steamId: steamId, broadcaster: 'X');

/// S05's live room as 3.x's `getRoomDetail` built it: the watch page's name,
/// `getbroadcastmpd` and the checked master.
SteamBroadcast _enteredLive() {
  final name = SteamBroadcastApi.broadcaster(_sample('S05-watch-live').body, steamId: _live);
  final broadcast = SteamBroadcastApi.broadcast(_sample('S05-mpd-live').body, steamId: _live, broadcaster: name);
  return broadcast.withMaster(
    codec: SteamBroadcastApi.checkMaster(_sample('S05-master-live').body, master: broadcast.master!, steamId: _live),
  );
}

Matcher _throwsA<T>() => throwsA(isA<T>());

// 3.x's own fixtures (steam_broadcast_site_test.dart).
const _legacyDirectoryHtml = '''
<div id="page1">
  <div class="Broadcast_Card apphub_Card interactable">
    <a href="https://steamcommunity.com/broadcast/watch/76561198373527746">
      <div class="apphub_CardContentType">Brawlhalla: Broadcast</div>
      <img class="apphub_CardContentPreviewImage" src="https://steambroadcast.akamaized.net/broadcast/76561198373527746/2748973143798613994/thumbnail/?broadcast_origin=ext2-ord1.steamserver.net">
      <div class="apphub_CardContentViewers ellipsis">3,758 viewers&nbsp;</div>
      <div class="apphub_CardContentTitle ellipsis">Brawlhalla</div>
      <div class="apphub_CardContentAuthorName"><a href="https://steamcommunity.com/id/probrawlhallastream/">ProBrawlhalla</a></div>
      <div class="appHubIconHolder"><img src="https://avatars.akamai.steamstatic.com/fixture.jpg"></div>
    </a>
  </div>
  <form><input name="broadcastsoffset" value="10"><input name="p" value="2"></form>
</div>
''';

const _legacyWatchHtml = '''
<html><head><meta property="og:title" content="Steam Community :: ProBrawlhalla :: Broadcast"></head>
<body><div id="application_config" data-broadcastsinfo="{&quot;steamid&quot;:&quot;76561198373527746&quot;}"></div></body></html>
''';

const Map<String, Object?> _legacyBroadcastJson = {
  'success': 'ready',
  'retry': 0,
  'broadcastid': '2748973143798613994',
  'hls_url': 'https://cache9-lax2.steamcontent.com/broadcast/76561198373527746/7299796105176582514/hls_manifest/0/cache9-lax2.steamcontent.com/master.m3u8?broadcast_origin=ext2-ord1.steamserver.net',
  'title': '',
  'num_viewers': 3797,
  'cdn_auth_url_parameters': null,
};

const _legacyMaster = '''
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",NAME="Default",URI="https://cache9-lax2.steamcontent.com/broadcast/76561198373527746/7299796105176582514/hls_manifest/0/cache9-lax2.steamcontent.com/187000/audio.m3u8?broadcast_origin=ext2-ord1.steamserver.net"
#EXT-X-STREAM-INF:BANDWIDTH=7187000,RESOLUTION=1920x1080,AUDIO="aac"
https://cache9-lax2.steamcontent.com/broadcast/76561198373527746/7299796105176582514/hls_manifest/0/cache9-lax2.steamcontent.com/7000000/video.m3u8?broadcast_origin=ext2-ord1.steamserver.net
''';

void main() {
  group('S01 trending broadcasts', () {
    test('the one category and its area match 3.x', () {
      final legacy = _result(_legacy('S01-directory-p1')['getCategores'])! as List;
      final categories = SteamBroadcastApi.categories();
      final expected = legacy.single as Map<String, dynamic>;
      expect(categories.single.id, expected['id']);
      expect(categories.single.name, expected['name']);
      _expectParity(categories.single.children.single.toJson(), _maps(expected['children']).single);
      expect(SteamBroadcastApi.isArea(categories.single.children.single), isTrue);
      expect(
        SteamBroadcastApi.isArea(const LiveArea(platform: 'steambroadcast', areaType: 'community', areaId: 'x')),
        isFalse,
      );
      expect(
        SteamBroadcastApi.isArea(const LiveArea(platform: 'bilibili', areaType: 'community', areaId: 'trending')),
        isFalse,
      );
    });

    test('both pages: ids, names, games as titles, covers as avatars, viewers, notice, headers match 3.x', () {
      for (final (sample, page, key) in [('S01-directory-p1', 1, 'recommend:1'), ('S01-directory-p2', 2, null)]) {
        final legacy = _legacy(sample);
        final traced = key == null ? legacy['getDirectoryPage'] : (legacy['getDirectoryPage'] as Map)[key];
        final expected = _result(traced)! as Map<String, dynamic>;
        final parsed = _page(sample, page);
        _expectRooms(_cards(parsed), expected['rooms'], reason: sample);
        expect(parsed.hasMore, expected['hasMore'], reason: sample);
        final broadcasts = _maps((legacy['parseDirectoryHtml'] as Map)['rooms']);
        for (final (index, broadcast) in parsed.broadcasts.indexed) {
          // 3.x dropped every avatar: it kept only avatars.akamai.steamstatic.com
          // and Steam serves them from avatars.fastly.steamstatic.com.
          _expectBroadcast(broadcast, broadcasts[index], changed: {'avatar'});
          expect(broadcasts[index]['avatar'], '');
          expect(broadcast.avatar, startsWith('https://avatars.fastly.steamstatic.com/'));
        }
      }
      final first = _cards(_page('S01-directory-p1', 1)).first;
      expect(first.title, 'NTE: Neverness to Everness', reason: 'the type without ": Broadcast"');
      expect(first.nick, 'PWM Game Manager', reason: 'the author link inside the card link (nested anchors)');
      expect(first.avatar, first.cover, reason: 'what 3.x showed: the cover, not the dropped avatar');
      expect(first.effectiveOnlineViewers, '6763');
      expect(first.effectiveLiveStatus, LiveStatus.live);
      expect(first.data, isNull, reason: 'a card has no room answer (3.x)');
      expect(first.httpHeaders, SteamBroadcastApi.mediaHeaders(_live));
    });

    test('the hidden form says whether a next page exists', () {
      final legacy = _legacy('S01-directory-p1')['parseDirectoryHtml(page: 2)'] as Map<String, dynamic>;
      expect(legacy['hasMore'], isFalse);
      expect(_page('S01-directory-p1', 2).hasMore, isFalse, reason: 'p1 announces page 2, not 3');
      expect(_page('S01-directory-p1', 1).hasMore, isTrue);
      expect(SteamBroadcastApi.directory('<div></div>', page: 1).hasMore, isFalse);
      expect(
        SteamBroadcastApi.directory(
          '<form><input name="broadcastsoffset" value="10"><input name="p" value="2"></form>',
          page: 1,
        ).hasMore,
        isFalse,
        reason: 'no cards',
      );
    });

    test("the search filter matches 3.x's on page 1: id part, name, title, game, case ignored", () {
      final search = _legacy('S01-directory-p1')['searchRooms'] as Map<String, dynamic>;
      final broadcasts = _page('S01-directory-p1', 1).broadcasts;
      for (final keyword in [
        'NTE',
        'neverness',
        'pwm game',
        'ARTDOCK',
        '7656119948521',
        'zzqxnomatch',
        'https://steamcommunity.com/profiles/$_live',
      ]) {
        final rooms = [
          for (final broadcast in SteamBroadcastApi.filter(broadcasts, keyword.trim().toLowerCase()))
            SteamBroadcastApi.room(broadcast),
        ];
        _expectRooms(rooms, _result(search['$keyword page 1']), reason: keyword);
      }
      expect(SteamBroadcastApi.filter(broadcasts, 'nte').map((broadcast) => broadcast.steamId), [
        _live,
        '76561199683996121',
      ], reason: 'livecoNTEntsteam12 contains the word too (3.x)');
    });

    test("viewer counts match 3.x's parseViewerCount", () {
      final legacy = _legacy('S01-directory-p1')['parseViewerCount'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in legacy.entries) {
        expect(SteamBroadcastApi.viewerCount(key), value, reason: key);
      }
    });

    test("3.x's directory fixture: an akamai avatar is kept, the cover checked, the next offset read", () {
      final page = SteamBroadcastApi.directory(_legacyDirectoryHtml, page: 1);
      expect(page.hasMore, isTrue);
      final broadcast = page.broadcasts.single;
      expect(broadcast.steamId, '76561198373527746');
      expect(broadcast.broadcaster, 'ProBrawlhalla');
      expect(broadcast.title, 'Brawlhalla');
      expect(broadcast.game, 'Brawlhalla');
      expect(broadcast.viewers, 3758);
      expect(broadcast.cover, startsWith('https://steambroadcast.akamaized.net/broadcast/76561198373527746/'));
      final room = SteamBroadcastApi.room(broadcast);
      expect(room.avatar, startsWith('https://avatars.akamai.steamstatic.com/'), reason: 'an avatar 3.x kept');
      expect(room.effectiveOnlineViewers, '3758');
    });

    test("cards: 3.x's thumbnail rule, avatars, duplicates, names, missing links", () {
      String card(String id, {String cover = '', String avatar = '', String author = '', String type = ''}) =>
          '''
<div class="Broadcast_Card"><a href="https://steamcommunity.com/broadcast/watch/$id">
<div class="apphub_CardContentType">$type</div>
<img class="apphub_CardContentPreviewImage" src="$cover">
<div class="apphub_CardContentTitle">Game</div>
<div class="apphub_CardContentAuthorName">$author</div>
<div class="appHubIconHolder"><img src="$avatar"></div>
</a></div>''';
      const id = '76561198373527746';
      const other = '76561198373527747';
      final page = SteamBroadcastApi.directory(
        [
          card(
            id,
            cover: 'https://steambroadcast.akamaized.net/broadcast/$other/1/thumbnail/',
            author: ' A  <b>B</b> ',
          ),
          card(id, cover: 'https://steambroadcast.akamaized.net/broadcast/$id/1/thumbnail/'),
          card(
            other,
            cover: 'http://steambroadcast.akamaized.net/broadcast/$other/1/thumbnail/',
            avatar: 'https://x.test/a.jpg',
          ),
          '<div class="Broadcast_Card"><a href="https://steamcommunity.com/profiles/$id">no watch link</a></div>',
          card('76561198373527748', cover: 'https://cdn.test/broadcast/76561198373527748/t.jpg', type: 'Other Type'),
        ].join(),
        page: 1,
      );
      expect(page.broadcasts.map((broadcast) => broadcast.steamId), [id, other, '76561198373527748']);
      final [first, second, third] = page.broadcasts;
      expect(first.cover, '', reason: "another broadcaster's thumbnail (3.x)");
      expect(first.broadcaster, 'A B');
      expect(first.title, 'Game', reason: 'no content type: the game (3.x)');
      expect(second.cover, '', reason: 'http (3.x)');
      expect(second.broadcaster, other, reason: 'no author: the id (3.x)');
      final shown = SteamBroadcastApi.room(second);
      expect(shown.avatar, 'https://x.test/a.jpg', reason: 'no cover to show: the avatar (the fixed part as fallback)');
      expect(third.cover, '', reason: 'another host (3.x)');
      expect(third.title, 'Other Type');
      expect(SteamBroadcastApi.room(third).avatar, '');
    });
  });

  group('links', () {
    test("steamIdOf matches 3.x's parseSteamId; the link is the watch page", () {
      final legacy = _legacy('S01-directory-p1');
      for (final MapEntry(:key, :value)
          in (legacy['SteamBroadcastLink.parseSteamId'] as Map<String, dynamic>).entries) {
        expect(SteamBroadcastApi.steamIdOf(key), value, reason: key);
      }
      for (final MapEntry(:key, :value) in (legacy['SteamBroadcastLink.watchUrl'] as Map<String, dynamic>).entries) {
        final steamId = SteamBroadcastApi.steamIdOf(key);
        if (value is String) {
          expect(SteamBroadcastApi.link(steamId!), value, reason: key);
        } else {
          expect(steamId, isNull, reason: key);
        }
      }
      expect(SteamBroadcastApi.isSteamId('76561198373527746'), isTrue);
      expect(SteamBroadcastApi.isSteamId('7656119837352774'), isFalse);
    });
  });

  group('S04, S05 getbroadcastmpd', () {
    test('the recorded answers match 3.x: live with its master, offline without viewers', () {
      for (final (sample, steamId) in [
        ('S04-mpd-live', _live),
        ('S04-mpd-offline', _offline),
        ('S05-mpd-live', _live),
      ]) {
        final legacy = _legacy(sample)['recorded'] as Map<String, dynamic>;
        final broadcast = _broadcast(_sample(sample).body, steamId: steamId);
        _expectBroadcast(broadcast, legacy);
        expect(broadcast.mediaError, isNull);
        expect(broadcast.masterChecked, isFalse, reason: 'checked on room entry only');
      }
      final offline = _broadcast(_sample('S04-mpd-offline').body, steamId: _offline);
      expect(offline.state, SteamBroadcastState.offline);
      expect(offline.viewers, isNull);
      expect(offline.master, isNull);
    });

    test('every success, title and viewer value 3.x named reads as 3.x read it', () {
      final legacy = _legacy('S04-mpd-live');
      for (final group in ['success', 'title', 'num_viewers']) {
        final values = legacy[group] as Map<String, dynamic>;
        final inputs = switch (group) {
          'success' => <Object?>[
            'ready',
            'READY',
            'unavailable',
            'offline',
            'not_live',
            'no_broadcast',
            'user_restricted',
            'waiting',
            'waiting_to_start',
            'waiting_for_start',
            'something_new',
            '',
            42,
            null,
          ],
          'title' => <Object?>['A title', '  spaced   title ', '', null, 7],
          _ => <Object?>[0, 12, -1, 3.7, '15', ' 16 ', 'x', null, true],
        };
        final field = group == 'success' ? 'success' : group;
        for (final input in inputs) {
          final expected = values['$input'] as Map<String, dynamic>;
          final body = _mpdBody({field: input});
          if (expected.containsKey('throws')) {
            expect(() => _broadcast(body), _throwsA<ApiChanged>(), reason: '$group $input');
          } else {
            _expectBroadcast(_broadcast(body), expected);
          }
        }
      }
    });

    test("a live answer whose hls_url or CDN parameters break 3.x's rules stays live with a media error", () {
      final legacy = _legacy('S04-mpd-live');
      final cdn = legacy['cdn_auth_url_parameters'] as Map<String, dynamic>;
      for (final input in <Object?>[
        null,
        '',
        '  ',
        '&token=abc',
        '?token=abc&exp=1',
        '&&a=1',
        'a=1&a=2',
        'broadcast_origin=x',
        'a b=1',
        'a=1#x',
        '&',
        'a',
        7,
      ]) {
        final expected = cdn['$input'] as Map<String, dynamic>;
        final broadcast = _broadcast(_mpdBody({'cdn_auth_url_parameters': input}));
        if (expected.containsKey('throws')) {
          // 3.x failed the whole room (refresh included); the room now keeps
          // its state and the stream reports the problem.
          expect(broadcast.state, SteamBroadcastState.live, reason: '$input');
          expect(broadcast.master, isNull);
          expect(broadcast.mediaError, isA<ApiChanged>(), reason: '$input');
        } else {
          _expectBroadcast(broadcast, expected);
          expect(broadcast.mediaError, isNull);
        }
      }
      final urls = legacy['hls_url'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in urls.entries) {
        expect((value as Map)['throws'], 'SteamBroadcastException.schema', reason: key);
        final broadcast = _broadcast(_mpdBody({'hls_url': key == 'null' ? null : key}));
        expect(broadcast.state, SteamBroadcastState.live, reason: key);
        expect(broadcast.master, isNull, reason: key);
        expect(broadcast.mediaError, isA<ApiChanged>(), reason: key);
        expect(broadcast.viewers, 6862);
      }
    });

    test('not an object, not JSON, or a missing success is ApiChanged (3.x: schema)', () {
      expect(_legacy('S04-mpd-live')['notAnObject'], containsPair('throws', 'SteamBroadcastException.schema'));
      expect(() => _broadcast('["ready"]'), _throwsA<ApiChanged>());
      expect(() => _broadcast('<html>'), _throwsA<ApiChanged>());
      expect(() => _broadcast('{}'), _throwsA<ApiChanged>());
    });

    test("3.x's broadcast fixture: live, its viewers, the master on cache9-lax2", () {
      final broadcast = SteamBroadcastApi.broadcast(
        jsonEncode(_legacyBroadcastJson),
        steamId: '76561198373527746',
        broadcaster: 'ProBrawlhalla',
      );
      expect(broadcast.state, SteamBroadcastState.live);
      expect(broadcast.viewers, 3797);
      expect(broadcast.master?.host, 'cache9-lax2.steamcontent.com');
      expect(broadcast.title, 'Steam Broadcast');
    });
  });

  group('S05 watch page', () {
    test("the broadcaster's name and the page checks match 3.x", () {
      final legacy = _legacy('S05-watch-live')['parseWatchHtml'] as Map<String, dynamic>;
      final watch = _sample('S05-watch-live').body;
      String name(String body, {String steamId = _live}) => SteamBroadcastApi.broadcaster(body, steamId: steamId);
      expect(name(watch), legacy['recorded']);
      expect(legacy['otherSteamId'], containsPair('throws', 'SteamBroadcastException.identity'));
      expect(() => name(watch, steamId: _offline), _throwsA<ApiChanged>());
      expect(legacy['withoutConfig'], containsPair('throws', 'SteamBroadcastException.missing'));
      expect(() => name(watch.replaceFirst('data-broadcastsinfo=', 'data-other=')), _throwsA<NotFound>());
      expect(legacy['badConfig'], containsPair('throws', 'SteamBroadcastException.schema'));
      expect(
        () => name(watch.replaceFirst('data-broadcastsinfo="{', 'data-broadcastsinfo="{x')),
        _throwsA<ApiChanged>(),
      );
      final withoutMeta = watch.replaceFirst(RegExp('<meta property="og:title"[^>]*>'), '');
      expect(name(withoutMeta), legacy['titleOnly']);
      expect(name(withoutMeta.replaceFirst(RegExp('<title>[^<]*</title>'), '')), legacy['noTitle']);
      expect(name(watch.replaceAll('PWM Game Manager', _live)), legacy['unknownAccount']);
      expect(name(watch.replaceAll('PWM Game Manager', '')), legacy['emptyName']);
      expect(
        name(_sample('S05-watch-offline').body, steamId: _offline),
        _legacy('S05-watch-offline')['parseWatchHtml'],
      );
      expect(SteamBroadcastApi.broadcaster(_legacyWatchHtml, steamId: '76561198373527746'), 'ProBrawlhalla');
    });
  });

  group('S05 HLS master', () {
    test("3.x's check: the recorded master passes and names AVC; every altered one fails", () {
      final legacy = _legacy('S05-master-live');
      final master = _sample('S05-master-live').body;
      final url = _broadcast(_sample('S05-mpd-live').body).master!;
      String? check(String text, {String steamId = _live, Uri? at}) =>
          SteamBroadcastApi.checkMaster(text, master: at ?? url, steamId: steamId);
      expect(legacy['recorded'], 'valid');
      expect(check(master), 'avc');
      final lines = const LineSplitter().convert(master);
      final variant = lines.firstWhere((line) => line.startsWith('https://'));
      final altered = <String, String? Function()>{
        'otherSteamId': () => check(master, steamId: _offline),
        'otherHost': () => check(master, at: url.replace(host: 'cache1-lax1.steamcontent.com')),
        'variantOnOtherHost': () => check(master.replaceFirst(variant, variant.replaceFirst(url.host, 'example.com'))),
        'audioOnOtherHost': () => check(master.replaceFirst('URI="https://${url.host}', 'URI="https://example.com')),
        'variantWithoutOrigin': () => check(master.replaceFirst(variant, variant.split('?').first)),
        'noVariant': () =>
            check(lines.where((line) => !line.startsWith('#EXT-X-STREAM-INF') && line != variant).join('\n')),
        'notHls': () => check('<html></html>'),
        'relativeVariant': () => check(master.replaceFirst(variant, '6000000/video.m3u8')),
        'seventeenVariants': () => check(
          [
            '#EXTM3U',
            for (var index = 0; index < 17; index++) ...['#EXT-X-STREAM-INF:BANDWIDTH=${index + 1}', variant],
          ].join('\n'),
        ),
      };
      for (final MapEntry(:key, :value) in altered.entries) {
        expect(legacy[key], containsPair('throws', 'SteamBroadcastException.schema'), reason: key);
        expect(value, _throwsA<ApiChanged>(), reason: key);
      }
      final legacyMaster = Uri.parse(_legacyBroadcastJson['hls_url']! as String);
      expect(
        SteamBroadcastApi.checkMaster(_legacyMaster, master: legacyMaster, steamId: '76561198373527746'),
        isNull,
        reason: "3.x's fixture names no codec",
      );
      expect(
        () => SteamBroadcastApi.checkMaster(
          _legacyMaster.replaceAll('76561198373527746', '76561199485215572'),
          master: legacyMaster,
          steamId: '76561198373527746',
        ),
        _throwsA<ApiChanged>(),
      );
      expect(check(master.replaceFirst('avc1.64001f', 'hvc1.1.6.L93.B0')), 'hevc');
    });
  });

  group('rooms', () {
    test("S05 entered room: 3.x's getRoomDetail, with its data", () {
      final legacy = _result(_legacy('S05-watch-live')['getRoomDetail'])! as Map<String, dynamic>;
      final broadcast = _enteredLive();
      final data = SteamBroadcastApi.roomData(broadcast);
      final room = SteamBroadcastApi.room(broadcast, data: data);
      _expectParity(_projection(room), legacy);
      expect(room.title, 'Steam Broadcast', reason: 'Steam leaves the title empty (3.x)');
      expect(room.area, 'Steam Community');
      expect(room.avatar, '');
      expect(room.effectiveOnlineViewers, '7994');
      final legacyData = legacy['data'] as Map<String, dynamic>;
      expect(data.master.toString(), legacyData['master']);
      expect(data.state, SteamBroadcastState.live);
      expect(data.codec, 'avc');
      expect(data.streamError, isNull);
      _expectBroadcast(broadcast, legacyData);
    });

    test("S05 offline room: 3.x's getRoomDetail", () {
      final legacy = _result(_legacy('S05-watch-offline')['getRoomDetail'])! as Map<String, dynamic>;
      final name = SteamBroadcastApi.broadcaster(_sample('S05-watch-offline').body, steamId: _offline);
      final broadcast = SteamBroadcastApi.broadcast(
        _sample('S04-mpd-offline').body,
        steamId: _offline,
        broadcaster: name,
      );
      final room = SteamBroadcastApi.room(broadcast, data: SteamBroadcastApi.roomData(broadcast));
      _expectParity(_projection(room), legacy);
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.onlineViewers, '', reason: '3.x wrote null');
      expect((room.data! as SteamBroadcastRoomData).streamError, isA<StreamUnavailable>());
    });

    test('restricted and unknown broadcasts are unknown, never offline; restricted has its notice', () {
      final restricted = _broadcast(_mpdBody({'success': 'user_restricted'}));
      final room = SteamBroadcastApi.room(restricted, data: SteamBroadcastApi.roomData(restricted));
      expect(room.effectiveLiveStatus, LiveStatus.unknown);
      expect(room.notice, SteamBroadcastApi.restrictedNotice);
      expect((room.data! as SteamBroadcastRoomData).streamError, isA<StreamUnavailable>());
      final waiting = _broadcast(_mpdBody({'success': 'waiting_for_start'}));
      expect(SteamBroadcastApi.room(waiting).effectiveLiveStatus, LiveStatus.unknown);
      expect(SteamBroadcastApi.room(waiting).notice, SteamBroadcastApi.chatNotice);
    });

    test("3.x's enrich: a room takes the card's name, title, game, cover, avatar and viewers where it has none", () {
      final card = _page('S01-directory-p1', 1).broadcasts.first;
      final legacy = _maps(_result(_legacy('S05-watch-live')['after the directory']));
      final entered = _enteredLive().enrich(card);
      _expectParity(_projection(SteamBroadcastApi.room(entered)), legacy.first);
      expect(entered.title, 'NTE: Neverness to Everness');
      expect(entered.viewers, 7994, reason: "the room's own viewers win");
      expect(entered.masterChecked, isTrue);
      final named = const SteamBroadcast(
        steamId: _live,
        broadcaster: _live,
        title: 'Own title',
        state: SteamBroadcastState.offline,
      ).enrich(card);
      expect(named.broadcaster, 'PWM Game Manager', reason: 'a name that is the id is no name');
      expect(named.title, 'Own title');
      expect(named.viewers, 6763, reason: '3.x kept the last known viewers');
      expect(named.state, SteamBroadcastState.offline);
    });

    test('room data: why a room cannot be played', () {
      final master = Uri.parse('https://cache1.steamcontent.com/broadcast/$_live/1/hls_manifest/0/x/master.m3u8');
      SiteError? error(SteamBroadcastState state, {Uri? at, SiteError? media}) =>
          SteamBroadcastRoomData(steamId: _live, state: state, master: at, mediaError: media).streamError;
      expect(error(SteamBroadcastState.live, at: master), isNull);
      expect(error(SteamBroadcastState.live), isA<StreamUnavailable>(), reason: 'refresh: no checked master');
      expect(error(SteamBroadcastState.live, media: const NotFound('steambroadcast')), isA<NotFound>());
      for (final state in [SteamBroadcastState.offline, SteamBroadcastState.restricted, SteamBroadcastState.unknown]) {
        expect(error(state, at: master), isA<StreamUnavailable>(), reason: state.name);
      }
      final refreshed = _broadcast(_sample('S05-mpd-live').body);
      expect(SteamBroadcastApi.roomData(refreshed).master, isNull, reason: 'not checked');
    });

    test('the line: the checked master, HLS, its codec, no headers (3.x sent none), no lease', () {
      final broadcast = _enteredLive();
      final line = SteamBroadcastApi.line(broadcast.master!, codec: broadcast.codec);
      expect(line.url, broadcast.master.toString());
      expect(line.format, StreamFormat.hls);
      expect(line.codec, 'avc');
      expect(line.lineId, 'steamcontent');
      expect(line.headers, isEmpty);
      expect(line.lease, isNull);
    });

    test('danmaku arguments are the Steam id', () {
      expect(const SteamBroadcastDanmakuArgs(_live).toString(), _live);
    });
  });

  group('errors', () {
    test("statuses map as 3.x's did, by type", () {
      for (final (status, matcher) in [
        (400, isA<ApiChanged>()),
        (422, isA<ApiChanged>()),
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (500, isA<NetworkFailure>()),
        (503, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
        (204, isA<NetworkFailure>()),
      ]) {
        expect(() => SteamBroadcastApi.directory('', page: 1, status: status), throwsA(matcher), reason: '$status');
        expect(
          () => SteamBroadcastApi.broadcaster('', steamId: _live, status: status),
          throwsA(matcher),
          reason: '$status',
        );
        expect(
          () => SteamBroadcastApi.broadcast('{}', steamId: _live, broadcaster: 'X', status: status),
          throwsA(matcher),
        );
        expect(
          () => SteamBroadcastApi.checkMaster(
            '#EXTM3U',
            master: Uri.parse('https://x.test/'),
            steamId: _live,
            status: status,
          ),
          throwsA(matcher),
        );
      }
    });

    test('an answer over 4 MiB is ApiChanged; a master over 1 MiB too', () {
      expect(() => SteamBroadcastApi.directory('x' * (4 * 1024 * 1024 + 1), page: 1), _throwsA<ApiChanged>());
      expect(
        () => SteamBroadcastApi.directory('é' * (2 * 1024 * 1024 + 1), page: 1),
        _throwsA<ApiChanged>(),
        reason: 'counted in UTF-8 bytes',
      );
      expect(
        () => SteamBroadcastApi.checkMaster(
          '#EXTM3U\n${'#' * (1024 * 1024)}',
          master: Uri.parse('https://x.test/'),
          steamId: _live,
        ),
        _throwsA<ApiChanged>(),
      );
    });
  });
}
