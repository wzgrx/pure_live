// Steam broadcast parsing against the recorded samples, compared field by
// field with 3.x's frozen output (expected.json, written by
// fixtures/steambroadcast/legacy_expected.dart from 3.x's SteamBroadcastApi,
// SteamBroadcastLink and SteamBroadcastSite). Every intended difference is
// listed with its reason (`changed`, with the upgrade item: docs/specs/UPGRADES.md
// 27-x, X-2 placeholders, "说明文字" notices); everything else must match.
// The synthetic cases port 3.x's steam_broadcast_site_test.dart and pin 3.x's
// checks. No test compares a sample's time with the clock.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('steambroadcast', name);

const _live = '76561199485215572';
const _offline = '76561197960287930';
const _scs = '76561198843011284';
const _unknown = '76561199999999990';

/// 3.x's notice ([SteamBroadcastApi.legacyChatNotice]), rewritten for viewers
/// ("说明文字"), without its chat sentence since the chat is shown (M5.23).
const _notice = {'notice'};

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

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {Set<String> changed = const {}, String reason = ''}) {
  final expected = _maps(legacy);
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(_projection(room), expected[index], changed: changed, reason: '$reason[$index]');
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
    SteamBroadcastApi.broadcast(body, steamId: steamId, profile: (name: 'X', avatar: ''));

SteamBroadcastProfile _profileOf(String sample, String steamId) =>
    SteamBroadcastApi.profile(_sample(sample).body, steamId: steamId);

SteamBroadcast _infoOf(String sample, String steamId, {SteamBroadcastProfile profile = (name: '', avatar: '')}) =>
    SteamBroadcastApi.info(_sample(sample).body, steamId: steamId, profile: profile);

/// S05's live room as room entry reads it now: the mini profile (S03, the
/// same broadcaster a day earlier), `getbroadcastmpd`, `getbroadcastinfo`
/// (S02) and the checked master.
SteamBroadcast _enteredLive() {
  final broadcast = SteamBroadcastApi.broadcast(
    _sample('S05-mpd-live').body,
    steamId: _live,
    profile: _profileOf('S03-profile', _live),
  ).withInfo(_infoOf('S02-info-live', _live));
  final master = _sample('S05-master-live').body;
  return broadcast.withMaster(
    codec: SteamBroadcastApi.checkMaster(master, master: broadcast.master!, steamId: _live),
    variants: SteamBroadcastApi.variants(master, master: broadcast.master!),
  );
}

/// S09's live room as room entry reads it: its profile, `getbroadcastmpd`,
/// `getbroadcastinfo` and checked master, recorded in the same minute.
SteamBroadcast _enteredScs() {
  final broadcast = SteamBroadcastApi.broadcast(
    _sample('S09-mpd-live').body,
    steamId: _scs,
    profile: _profileOf('S09-profile-live', _scs),
  ).withInfo(_infoOf('S09-info-live', _scs));
  final master = _sample('S09-master-live').body;
  return broadcast.withMaster(
    codec: SteamBroadcastApi.checkMaster(master, master: broadcast.master!, steamId: _scs),
    variants: SteamBroadcastApi.variants(master, master: broadcast.master!),
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

    test(
      "changed: both pages match 3.x but the avatar, now the broadcaster's own at 184 px (27-1), and the notice",
      () {
        final body = _sample('S01-directory-p1').body + _sample('S01-directory-p2').body;
        const defaultAvatar = 'https://avatars.fastly.steamstatic.com/fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb.jpg';
        expect(defaultAvatar.allMatches(body), hasLength(4), reason: "four broadcasters show Steam's default avatar");
        var none = 0;
        for (final (sample, page, key) in [('S01-directory-p1', 1, 'recommend:1'), ('S01-directory-p2', 2, null)]) {
          final legacy = _legacy(sample);
          final traced = key == null ? legacy['getDirectoryPage'] : (legacy['getDirectoryPage'] as Map)[key];
          final expected = _result(traced)! as Map<String, dynamic>;
          final parsed = _page(sample, page);
          // 27-1: 3.x showed the cover in the avatar's place.
          _expectRooms(_cards(parsed), expected['rooms'], changed: const {'avatar', ..._notice}, reason: sample);
          expect(parsed.hasMore, expected['hasMore'], reason: sample);
          final broadcasts = _maps((legacy['parseDirectoryHtml'] as Map)['rooms']);
          for (final (index, broadcast) in parsed.broadcasts.indexed) {
            // 3.x dropped every avatar: it kept only avatars.akamai.steamstatic.com
            // and Steam serves them from avatars.fastly.steamstatic.com.
            _expectBroadcast(broadcast, broadcasts[index], changed: {'avatar'});
            expect(broadcasts[index]['avatar'], '');
            if (broadcast.avatar.isEmpty) {
              none++;
            } else {
              expect(
                broadcast.avatar,
                matches(RegExp(r'^https://avatars\.fastly\.steamstatic\.com/[0-9a-f]{40}_full\.jpg$')),
              );
            }
            final room = SteamBroadcastApi.room(broadcast);
            expect(room.avatar, broadcast.avatar);
            expect(room.avatar, isNot(room.cover));
            expect(room.toJson().containsKey('restriction'), isFalse, reason: 'a card does not say who may watch');
            expect(room.startedAt, isNull, reason: 'Steam gives no start time');
          }
        }
        expect(none, 4, reason: "Steam's default avatar is no avatar: the interface shows its own");
        final first = _cards(_page('S01-directory-p1', 1)).first;
        expect(first.title, 'NTE: Neverness to Everness', reason: 'the type without ": Broadcast"');
        expect(first.nick, 'PWM Game Manager', reason: 'the author link inside the card link (nested anchors)');
        expect(
          first.avatar,
          _profileOf('S03-profile', _live).avatar,
          reason: "the card's 32 px avatar at the size the mini profile names",
        );
        expect(first.effectiveOnlineViewers, '6763');
        expect(first.effectiveLiveStatus, LiveStatus.live);
        expect(first.data, isNull, reason: 'a card has no room answer (3.x)');
        expect(first.httpHeaders, SteamBroadcastApi.mediaHeaders(_live));
      },
    );

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
      for (final keyword in ['NTE', 'neverness', 'pwm game', 'ARTDOCK', '7656119948521', 'zzqxnomatch']) {
        final rooms = [
          for (final broadcast in SteamBroadcastApi.filter(broadcasts, keyword.trim().toLowerCase()))
            SteamBroadcastApi.room(broadcast),
        ];
        _expectRooms(rooms, _result(search['$keyword page 1']), changed: const {'avatar', ..._notice}, reason: keyword);
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
      expect(room.avatar, 'https://avatars.akamai.steamstatic.com/fixture.jpg', reason: 'not a hash name: as given');
      expect(room.effectiveOnlineViewers, '3758');
    });

    test("cards: 3.x's thumbnail rule, avatars (27-1), duplicates, names (X-2), an unreadable card skipped", () {
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
      const hash = 'ba2a49b5180c4f3449245bab40ea2a064898a013';
      const defaultHash = 'fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb';
      final page = SteamBroadcastApi.directory(
        [
          card(
            id,
            cover: 'https://steambroadcast.akamaized.net/broadcast/$other/1/thumbnail/',
            author: ' A  <b>B</b> ',
            avatar: 'https://avatars.fastly.steamstatic.com/${hash}_medium.jpg',
          ),
          card(id, cover: 'https://steambroadcast.akamaized.net/broadcast/$id/1/thumbnail/'),
          card(
            other,
            cover: 'http://steambroadcast.akamaized.net/broadcast/$other/1/thumbnail/',
            avatar: 'https://x.test/a.jpg',
          ),
          '<div class="Broadcast_Card"><a href="https://steamcommunity.com/profiles/$id">no watch link</a></div>',
          card(
            '76561198373527748',
            cover: 'https://cdn.test/broadcast/76561198373527748/t.jpg',
            type: 'Other Type',
            avatar: 'https://avatars.akamai.steamstatic.com/$defaultHash.jpg',
          ),
          card('76561198373527749', type: 'x' * 70000),
          card('76561198373527749', author: '76561198373527749'),
        ].join(),
        page: 1,
      );
      expect(page.broadcasts.map((broadcast) => broadcast.steamId), [
        id,
        other,
        '76561198373527748',
        '76561198373527749',
      ], reason: 'the card with a 70000-character type only loses itself; the next card of its broadcaster counts');
      final [first, second, third, fourth] = page.broadcasts;
      expect(first.cover, '', reason: "another broadcaster's thumbnail (3.x)");
      expect(first.broadcaster, 'A B');
      expect(first.title, 'Game', reason: 'no content type: the game (3.x)');
      expect(first.avatar, 'https://avatars.fastly.steamstatic.com/${hash}_full.jpg', reason: '27-1: the 184 px size');
      expect(second.cover, '', reason: 'http (3.x)');
      expect(second.broadcaster, '', reason: 'changed (X-2): no author is no name (3.x wrote the id)');
      expect(SteamBroadcastApi.room(second).avatar, 'https://x.test/a.jpg', reason: 'another host: as given');
      expect(third.cover, '', reason: 'another host (3.x)');
      expect(third.title, 'Other Type');
      expect(third.avatar, '', reason: "Steam's default avatar is none");
      expect(SteamBroadcastApi.room(third).avatar, '');
      expect(fourth.broadcaster, '', reason: 'a name that is only the id is none (X-2)');
    });
  });

  group('links', () {
    test("changed: steamIdOf matches 3.x's parseSteamId, and a profile link is the account's room (27-4)", () {
      final legacy = _legacy('S01-directory-p1');
      for (final MapEntry(:key, :value)
          in (legacy['SteamBroadcastLink.parseSteamId'] as Map<String, dynamic>).entries) {
        if (key == 'https://steamcommunity.com/profiles/76561198373527746') {
          // 27-4: 3.x only knew watch links.
          expect(value, isNull);
          expect(SteamBroadcastApi.steamIdOf(key), '76561198373527746', reason: key);
          continue;
        }
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
      for (final link in [
        'https://steamcommunity.com/profiles/$_live/',
        'http://steamcommunity.com/profiles/$_live?l=english',
        'https://STEAMCOMMUNITY.com//profiles//$_live',
      ]) {
        expect(SteamBroadcastApi.steamIdOf(link), _live, reason: link);
      }
      for (final link in [
        'https://steamcommunity.com/profiles/7656119948521557',
        'https://steamcommunity.com/profiles/$_live/broadcasts',
        'https://www.steamcommunity.com/profiles/$_live',
        'https://steamcommunity.com/profiles/$_live#x',
        'https://steamcommunity.com/id/gabelogannewell',
      ]) {
        expect(SteamBroadcastApi.steamIdOf(link), isNull, reason: link);
      }
      expect(SteamBroadcastApi.isSteamId('76561198373527746'), isTrue);
      expect(SteamBroadcastApi.isSteamId('7656119837352774'), isFalse);
    });

    test('a custom address /id/<name> is recognized for one request (27-4)', () {
      expect(
        (_legacy('S01-directory-p1')['SteamBroadcastLink.parseSteamId']
            as Map)['https://steamcommunity.com/id/probrawlhallastream/'],
        isNull,
        reason: '3.x did not know it',
      );
      for (final (link, vanity) in [
        ('https://steamcommunity.com/id/probrawlhallastream/', 'probrawlhallastream'),
        ('http://steamcommunity.com/id/gabelogannewell', 'gabelogannewell'),
        ('https://steamcommunity.com/id/A_b-9?l=english', 'A_b-9'),
      ]) {
        expect(SteamBroadcastApi.vanityOf(link), vanity, reason: link);
        expect(SteamBroadcastApi.steamIdOf(link), isNull, reason: 'needs a request');
      }
      for (final link in [
        'https://steamcommunity.com/id/',
        'https://steamcommunity.com/id/a.b',
        'https://steamcommunity.com/id/${'a' * 65}',
        'https://steamcommunity.com/id/name/broadcasts',
        'https://store.steampowered.com/id/name',
        'https://www.steamcommunity.com/id/name',
        'gabelogannewell',
      ]) {
        expect(SteamBroadcastApi.vanityOf(link), isNull, reason: link);
      }
      expect(SteamBroadcastApi.vanityUrl('gabelogannewell'), _sample('S10-vanity').url);
    });

    test("the new answers' addresses are the recorded ones; the mini profile's account id is the id's offset", () {
      expect(SteamBroadcastApi.profileUrl(_live), _sample('S03-profile').url, reason: 'account 1524949844');
      expect(SteamBroadcastApi.profileUrl(_offline), _sample('S08-profile-offline').url, reason: 'account 22202');
      expect(SteamBroadcastApi.profileUrl(_scs), _sample('S09-profile-live').url);
      expect(SteamBroadcastApi.profileUrl(_unknown), _sample('S08-profile-unknown').url);
      expect(SteamBroadcastApi.infoUrl(_live).queryParameters, _sample('S02-info-live').url.queryParameters);
      expect(SteamBroadcastApi.infoUrl(_scs).queryParameters, _sample('S09-info-live').url.queryParameters);
      expect(SteamBroadcastApi.infoUrl(_scs).path, _sample('S09-info-live').url.path);
    });
  });

  group('S04, S05, S09 getbroadcastmpd', () {
    test('changed: the recorded answers match 3.x but the placeholder title (X-2); ready says none (M2.1)', () {
      for (final (sample, steamId) in [
        ('S04-mpd-live', _live),
        ('S04-mpd-offline', _offline),
        ('S05-mpd-live', _live),
      ]) {
        final legacy = _legacy(sample)['recorded'] as Map<String, dynamic>;
        final broadcast = _broadcast(_sample(sample).body, steamId: steamId);
        expect(legacy['title'], SteamBroadcastApi.legacyTitle);
        _expectBroadcast(broadcast, legacy, changed: {'title'});
        expect(broadcast.title, '', reason: 'X-2: Steam leaves the title empty; no placeholder');
        expect(broadcast.mediaError, isNull);
        expect(broadcast.masterChecked, isFalse, reason: 'checked on room entry only');
      }
      final offline = _broadcast(_sample('S04-mpd-offline').body, steamId: _offline);
      expect(offline.state, SteamBroadcastState.offline);
      expect(offline.viewers, isNull);
      expect(offline.master, isNull);
      expect(offline.restriction, isNull);
      expect(offline.broadcastId, isNull, reason: 'broadcastid 0');
      final live = _broadcast(_sample('S05-mpd-live').body);
      expect(live.restriction, LiveRestriction.none);
      expect(live.broadcastId, '4005242549293303728');
      final scs = _broadcast(_sample('S09-mpd-live').body, steamId: _scs);
      expect((scs.state, scs.viewers, scs.broadcastId), (SteamBroadcastState.live, 2490, '7677968762198629065'));
      expect(scs.master?.host, 'cache3-lax2.steamcontent.com');
    });

    test('changed: every success, title and viewer value 3.x named reads as 3.x read it, but user_restricted', () {
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
        for (final input in inputs) {
          final expected = values['$input'] as Map<String, dynamic>;
          final body = _mpdBody({group: input});
          if (expected.containsKey('throws')) {
            expect(() => _broadcast(body), _throwsA<ApiChanged>(), reason: '$group $input');
            continue;
          }
          final broadcast = _broadcast(body);
          final changed = {
            // X-2: 3.x wrote the placeholder for an empty title.
            if (expected['title'] == SteamBroadcastApi.legacyTitle) 'title',
            // Steam's watch page: the broadcaster's account may not broadcast
            // (3.x: a restricted, unknown broadcast).
            if (input == 'user_restricted') 'state',
          };
          _expectBroadcast(broadcast, expected, changed: changed);
          if (changed.contains('title')) expect(broadcast.title, '');
          if (input == 'user_restricted') {
            expect(expected['state'], 'restricted');
            expect(broadcast.state, SteamBroadcastState.accountRestricted);
          }
        }
      }
    });

    test('missing_subscription is a live for subscribers only; ready with is_replay a replay with its master', () {
      final subscribers = _broadcast(_mpdBody({'success': 'missing_subscription'}));
      expect(subscribers.state, SteamBroadcastState.live);
      expect(subscribers.restriction, LiveRestriction.subscribersOnly);
      expect(subscribers.master, isNull, reason: 'no stream for this client');
      for (final flag in <Object>[1, true]) {
        final replay = _broadcast(_mpdBody({'is_replay': flag}));
        expect(replay.state, SteamBroadcastState.replay, reason: '$flag');
        expect(replay.restriction, LiveRestriction.none);
        expect(replay.master, isNotNull);
      }
      expect(_broadcast(_mpdBody({'is_replay': 0})).state, SteamBroadcastState.live);
      expect(_broadcast(_mpdBody({'broadcastid': 'x'})).broadcastId, isNull);
      expect(_broadcast(_mpdBody({'broadcastid': 12})).broadcastId, '12');
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
          _expectBroadcast(broadcast, expected, changed: {'title'});
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
        profile: (name: 'ProBrawlhalla', avatar: ''),
      );
      expect(broadcast.state, SteamBroadcastState.live);
      expect(broadcast.viewers, 3797);
      expect(broadcast.master?.host, 'cache9-lax2.steamcontent.com');
      expect(broadcast.title, '', reason: 'X-2 (3.x: Steam Broadcast)');
      expect(broadcast.broadcaster, 'ProBrawlhalla');
    });
  });

  group('S02, S09 getbroadcastinfo (27-2)', () {
    test('the recorded answers: title and game, thumbnail, viewers while online; success 42 is offline', () {
      final live = _infoOf('S02-info-live', _live, profile: (name: 'N', avatar: 'https://a.test/a.jpg'));
      expect(live.state, SteamBroadcastState.live);
      expect(live.title, 'NTE: Neverness to Everness', reason: 'no title: the game, as on the cards');
      expect(live.game, 'NTE: Neverness to Everness');
      expect(live.cover, startsWith('https://steambroadcast.akamaized.net/broadcast/$_live/4005242549293303728/'));
      expect(live.viewers, 6862);
      expect((live.broadcaster, live.avatar), ('N', 'https://a.test/a.jpg'));
      expect(live.restriction, isNull, reason: 'the answer does not say who may watch');
      expect(live.master, isNull);
      final offline = _infoOf('S02-info-offline', _offline);
      expect(offline.state, SteamBroadcastState.offline);
      expect((offline.title, offline.game, offline.cover, offline.viewers), ('', '', '', null));
      final scs = _infoOf('S09-info-live', _scs);
      expect(
        (scs.state, scs.title, scs.game, scs.viewers),
        (SteamBroadcastState.live, 'Euro Truck Simulator 2', 'Euro Truck Simulator 2', 2483),
      );
      expect(scs.cover, contains('/broadcast/$_scs/7677968762198629065/thumbnail/'));
    });

    test('its title before the game, replays, lenient card fields; another success is ApiChanged', () {
      String body(Map<String, Object?> changes) {
        final root = jsonDecode(_sample('S02-info-live').body) as Map<String, dynamic>;
        for (final MapEntry(:key, :value) in changes.entries) {
          root[key] = value;
        }
        return jsonEncode(root);
      }

      SteamBroadcast info(Map<String, Object?> changes) => SteamBroadcastApi.info(body(changes), steamId: _live);
      expect(info({'title': ' Speed &amp; run '}).title, 'Speed & run');
      expect(info({'app_title': 'A &lt;B&gt;'}).game, 'A <B>');
      expect(info({'is_replay': 1}).state, SteamBroadcastState.replay);
      expect(info({'is_replay': true}).state, SteamBroadcastState.replay);
      expect(info({'is_online': false}).state, SteamBroadcastState.offline);
      expect(info({'is_online': false}).viewers, isNull);
      expect(info({'is_online': null}).state, SteamBroadcastState.offline);
      final malformed = info({
        'app_title': 7,
        'title': ['x'],
        'thumbnail_url': 5,
        'viewer_count': 'many',
      });
      expect(
        (malformed.state, malformed.title, malformed.game, malformed.cover, malformed.viewers),
        (SteamBroadcastState.live, '', '', '', null),
      );
      expect(info({'thumbnail_url': 'https://steambroadcast.akamaized.net/broadcast/$_offline/1/'}).cover, '');
      expect(SteamBroadcastApi.info('{"success":"42"}', steamId: _live).state, SteamBroadcastState.offline);
      for (final answer in ['{"success":2}', '{}', '[]', 'x', '{"success":"x"}']) {
        expect(() => SteamBroadcastApi.info(answer, steamId: _live), _throwsA<ApiChanged>(), reason: answer);
      }
    });

    test('with getbroadcastmpd on room entry: its title, game and cover; the viewers only when missing', () {
      final mpd = _broadcast(_sample('S05-mpd-live').body);
      final info = _infoOf('S02-info-live', _live);
      final merged = mpd.withInfo(info);
      expect((merged.title, merged.game, merged.cover), (info.title, info.game, info.cover));
      expect(merged.viewers, 7994, reason: "getbroadcastmpd's are fresher (the info is cached for a minute)");
      expect((merged.state, merged.restriction, merged.master), (mpd.state, mpd.restriction, mpd.master));
      final withoutViewers = _broadcast(_mpdBody({'num_viewers': null})).withInfo(info);
      expect(withoutViewers.viewers, 6862);
      final kept = mpd.withInfo(_infoOf('S02-info-offline', _live));
      expect((kept.title, kept.cover, kept.viewers), ('', '', 7994));
    });
  });

  group('S03, S08, S09 mini profile (27-1, 27-2)', () {
    test("the broadcaster's name and 184 px avatar; Steam's placeholders for an account that does not exist", () {
      expect(_profileOf('S03-profile', _live), (
        name: 'PWM Game Manager',
        avatar: 'https://avatars.fastly.steamstatic.com/ba2a49b5180c4f3449245bab40ea2a064898a013_full.jpg',
      ));
      expect(_profileOf('S08-profile-offline', _offline).name, 'Rabscuttle');
      expect(
        _profileOf('S08-profile-offline', _offline).avatar,
        endsWith('c5d56249ee5d28a07db4ac9f7f60af961fab5426_full.jpg'),
      );
      expect(_profileOf('S09-profile-live', _scs).name, 'SCS Software');
      // An account that does not exist: its name is its id and its avatar
      // Steam's default (2026-09-29: its profile page is an error page).
      expect(_sample('S08-profile-unknown').body, contains('"persona_name": "$_unknown"'));
      expect(_profileOf('S08-profile-unknown', _unknown), (name: '', avatar: ''));
    });

    test('HTML characters decoded; a malformed avatar is none; a missing name or not an object is ApiChanged', () {
      expect(
        SteamBroadcastApi.profile('{"persona_name":" A &amp; B ","avatar_url":"http://x.test/a.jpg"}', steamId: _live),
        (name: 'A & B', avatar: ''),
      );
      expect(SteamBroadcastApi.profile('{"persona_name":"A","avatar_url":7}', steamId: _live), (name: 'A', avatar: ''));
      for (final answer in ['{}', '{"persona_name":null}', '[]', '<html>']) {
        expect(() => SteamBroadcastApi.profile(answer, steamId: _live), _throwsA<ApiChanged>(), reason: answer);
      }
    });
  });

  group('S10 profile XML (27-4)', () {
    test("a custom address's Steam id; none when Steam has no such profile; anything else is ApiChanged", () {
      expect(SteamBroadcastApi.steamIdOfProfileXml(_sample('S10-vanity').body), _offline);
      expect(SteamBroadcastApi.steamIdOfProfileXml(_sample('S10-vanity-missing').body), isNull);
      expect(() => SteamBroadcastApi.steamIdOfProfileXml('<html></html>'), _throwsA<ApiChanged>());
      expect(
        () => SteamBroadcastApi.steamIdOfProfileXml('<profile><steamID64>123</steamID64></profile>'),
        _throwsA<ApiChanged>(),
      );
      expect(() => SteamBroadcastApi.steamIdOfProfileXml('', status: 403), _throwsA<RiskControl>());
    });
  });

  group('S05 watch page', () {
    test("changed: the broadcaster's name and the page checks match 3.x, but placeholders are no name (X-2)", () {
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
      // X-2: 3.x wrote its placeholder, or the id of an account that does not
      // exist.
      expect(legacy['noTitle'], SteamBroadcastApi.legacyBroadcaster);
      expect(name(withoutMeta.replaceFirst(RegExp('<title>[^<]*</title>'), '')), '');
      expect(legacy['unknownAccount'], _live);
      expect(name(watch.replaceAll('PWM Game Manager', _live)), '');
      expect(legacy['emptyName'], SteamBroadcastApi.legacyBroadcaster);
      expect(name(watch.replaceAll('PWM Game Manager', '')), '');
      expect(
        name(_sample('S05-watch-offline').body, steamId: _offline),
        _legacy('S05-watch-offline')['parseWatchHtml'],
      );
      expect(SteamBroadcastApi.broadcaster(_legacyWatchHtml, steamId: '76561198373527746'), 'ProBrawlhalla');
    });
  });

  group('S05, S09 HLS master', () {
    test("3.x's check: the recorded masters pass and name AVC; every altered one fails", () {
      final legacy = _legacy('S05-master-live');
      final master = _sample('S05-master-live').body;
      final url = _broadcast(_sample('S05-mpd-live').body).master!;
      String? check(String text, {String steamId = _live, Uri? at}) =>
          SteamBroadcastApi.checkMaster(text, master: at ?? url, steamId: steamId);
      expect(legacy['recorded'], 'valid');
      expect(check(master), 'avc');
      final scs = _broadcast(_sample('S09-mpd-live').body, steamId: _scs).master!;
      expect(SteamBroadcastApi.checkMaster(_sample('S09-master-live').body, master: scs, steamId: _scs), 'avc');
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

    test("the variants (27-7): S09's four, named as Steam's player names them, best first", () {
      final url = _broadcast(_sample('S09-mpd-live').body, steamId: _scs).master!;
      final variants = SteamBroadcastApi.variants(_sample('S09-master-live').body, master: url);
      expect(variants.map((variant) => variant.id), ['1080p60', '720p', '480p', '360p']);
      expect(
        variants.first,
        const SteamBroadcastVariant(
          id: '1080p60',
          width: 1920,
          height: 1080,
          frameRate: 60,
          bandwidth: 7160000,
          codec: 'avc',
        ),
      );
      expect(variants.map((variant) => variant.bandwidth), [7160000, 3660000, 1660000, 660000]);
      final s05 = _broadcast(_sample('S05-mpd-live').body).master!;
      expect(
        SteamBroadcastApi.variants(_sample('S05-master-live').body, master: s05),
        isEmpty,
        reason: 'one variant is the adaptive quality itself (Steam offers no choice then)',
      );
      final legacyMaster = Uri.parse(_legacyBroadcastJson['hls_url']! as String);
      expect(SteamBroadcastApi.variants(_legacyMaster, master: legacyMaster), isEmpty);
    });

    test('a variant selects itself and its audio in any fresh copy of the master (M7)', () {
      final url = _broadcast(_sample('S09-mpd-live').body, steamId: _scs).master!;
      final text = _sample('S09-master-live').body;
      final variants = SteamBroadcastApi.variants(text, master: url);
      final selection = variants[1].selectIn(text, source: url);
      expect(selection.video.path, endsWith('/3500000/video.m3u8'));
      expect(
        selection.audio?.path,
        endsWith('/160000/audio.m3u8'),
        reason: "Steam's variants have no audio of their own",
      );
      final reduced = selection.rewrite(url, text);
      expect(reduced, contains('RESOLUTION=1280x720'));
      expect(reduced, isNot(contains('RESOLUTION=1920x1080')));
      // Another answer: another CDN host, the same ladder.
      final moved = url.replace(host: 'cache9-lax1.steamcontent.com');
      final fresh = text.replaceAll(url.host, moved.host);
      expect(variants.first.selectIn(fresh, source: moved).video.host, moved.host);
      expect(
        () => variants.first.selectIn(fresh.replaceAll('FRAME-RATE=60', 'FRAME-RATE=30'), source: moved),
        throwsFormatException,
      );
      expect(() => variants.first.selectIn('<html>', source: moved), throwsFormatException);
    });

    test('variant ids; one per id at its highest bandwidth; unusable variants and masters are left out', () {
      expect(SteamBroadcastApi.variantId(1080, 60), '1080p60');
      expect(SteamBroadcastApi.variantId(720, 59.94), '720p60');
      expect(SteamBroadcastApi.variantId(720, 30), '720p', reason: "Steam's player: fps shown above 30");
      expect(SteamBroadcastApi.variantId(480, 0), '480p');
      for (final id in ['720p', '1080p60', 'auto', 'source', '720', 'p60', '0p']) {
        expect(SteamBroadcastApi.isVariantId(id), ['720p', '1080p60'].contains(id), reason: id);
      }
      final url = _broadcast(_sample('S09-mpd-live').body, steamId: _scs).master!;
      final text = _sample('S09-master-live').body;
      final lines = const LineSplitter().convert(text);
      String variantLine(int index) => lines.where((line) => line.startsWith('#EXT-X-STREAM-INF')).elementAt(index);
      final duplicated = text.replaceFirst(variantLine(3), variantLine(3).replaceFirst('640x360', '854x480'));
      expect(SteamBroadcastApi.variants(duplicated, master: url).map((variant) => (variant.id, variant.bandwidth)), [
        ('1080p60', 7160000),
        ('720p', 3660000),
        ('480p', 1660000),
      ]);
      final unsized = text.replaceFirst(',RESOLUTION=1920x1080', '');
      expect(SteamBroadcastApi.variants(unsized, master: url).map((variant) => variant.id), ['720p', '480p', '360p']);
      expect(
        SteamBroadcastApi.variants(
          text.replaceFirst('#EXT-X-VERSION:7', '#EXT-X-SESSION-KEY:METHOD=NONE'),
          master: url,
        ),
        isEmpty,
        reason: 'the shared parser refuses it: the adaptive quality alone',
      );
    });
  });

  group('rooms', () {
    test("changed: S05 entered room: 3.x's getRoomDetail with the detail answers (27-1, 27-2), with its data", () {
      final legacy = _result(_legacy('S05-watch-live')['getRoomDetail'])! as Map<String, dynamic>;
      final broadcast = _enteredLive();
      final data = SteamBroadcastApi.roomData(broadcast);
      final room = SteamBroadcastApi.room(broadcast, data: data);
      _expectParity(
        _projection(room),
        legacy,
        // 27-2: title, area and cover from getbroadcastinfo; 27-1: the mini
        // profile's avatar; the notice rewritten.
        changed: {'title', 'area', 'cover', 'avatar', ..._notice},
      );
      expect(
        (legacy['title'], legacy['area'], legacy['avatar'], legacy['cover']),
        ('Steam Broadcast', 'Steam Community', '', ''),
      );
      expect(room.title, 'NTE: Neverness to Everness');
      expect(room.area, 'NTE: Neverness to Everness');
      expect(room.cover, startsWith('https://steambroadcast.akamaized.net/broadcast/$_live/'));
      expect(room.avatar, endsWith('ba2a49b5180c4f3449245bab40ea2a064898a013_full.jpg'));
      expect(room.nick, 'PWM Game Manager', reason: 'the mini profile names the same broadcaster');
      expect(room.notice, SteamBroadcastApi.chatNotice);
      expect(room.effectiveOnlineViewers, '7994');
      expect(room.restriction, LiveRestriction.none, reason: 'new key: ready is for everyone');
      expect(room.toJson()['restriction'], 'none');
      expect(room.startedAt, isNull);
      final legacyData = legacy['data'] as Map<String, dynamic>;
      expect(data.master.toString(), legacyData['master']);
      expect(data.state, SteamBroadcastState.live);
      expect(data.codec, 'avc');
      expect(data.streamError, isNull);
      expect(data.qualities, [SteamBroadcastApi.quality], reason: 'one variant: the adaptive quality alone');
      _expectBroadcast(broadcast, legacyData, changed: {'title', 'game', 'cover', 'avatar'});
    });

    test("changed: S05 offline room: 3.x's getRoomDetail, with the broadcaster's avatar (27-1)", () {
      final legacy = _result(_legacy('S05-watch-offline')['getRoomDetail'])! as Map<String, dynamic>;
      final broadcast = SteamBroadcastApi.broadcast(
        _sample('S04-mpd-offline').body,
        steamId: _offline,
        profile: _profileOf('S08-profile-offline', _offline),
      );
      final room = SteamBroadcastApi.room(broadcast, data: SteamBroadcastApi.roomData(broadcast));
      _expectParity(_projection(room), legacy, changed: {'avatar', 'title', 'area', ..._notice});
      expect((legacy['title'], legacy['area']), ('Steam Broadcast', 'Steam Community'));
      expect((room.title, room.area), ('', ''), reason: 'X-2: no placeholders; a follow keeps its stored ones');
      expect(room.avatar, endsWith('_full.jpg'));
      expect(room.nick, 'Rabscuttle');
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.onlineViewers, '', reason: '3.x wrote null');
      expect(room.restriction, isNull);
      expect((room.data! as SteamBroadcastRoomData).streamError, isA<StreamUnavailable>());
    });

    test('a refreshed room from getbroadcastinfo: live with its title and cover, no restriction, no master', () {
      final broadcast = _infoOf('S02-info-live', _live, profile: _profileOf('S03-profile', _live));
      final room = SteamBroadcastApi.room(broadcast, data: SteamBroadcastApi.roomData(broadcast));
      expect(room.effectiveLiveStatus, LiveStatus.live);
      expect(
        (room.title, room.nick, room.effectiveOnlineViewers),
        ('NTE: Neverness to Everness', 'PWM Game Manager', '6862'),
      );
      expect(room.restriction, isNull, reason: 'a light refresh does not say (M2.1)');
      expect((room.data! as SteamBroadcastRoomData).streamError, isA<StreamUnavailable>(), reason: 'enter the room');
    });

    test('changed: a restricted account is banned (3.x unknown); subscribers only is live; waiting unknown', () {
      final restricted = _broadcast(_mpdBody({'success': 'user_restricted'}));
      final room = SteamBroadcastApi.room(restricted, data: SteamBroadcastApi.roomData(restricted));
      expect(room.effectiveLiveStatus, LiveStatus.banned);
      expect(room.followGroup, FollowGroup.offline);
      expect(room.notice, SteamBroadcastApi.restrictedNotice);
      expect((room.data! as SteamBroadcastRoomData).streamError, isA<StreamUnavailable>());
      final subscribers = _broadcast(_mpdBody({'success': 'missing_subscription'}));
      final live = SteamBroadcastApi.room(subscribers, data: SteamBroadcastApi.roomData(subscribers));
      expect(live.effectiveLiveStatus, LiveStatus.live);
      expect(live.restriction, LiveRestriction.subscribersOnly);
      expect(live.isRestricted, isTrue);
      expect(live.followGroup, FollowGroup.live);
      expect(
        (live.data! as SteamBroadcastRoomData).streamError,
        isA<StreamUnavailable>().having((error) => '$error', 'reason', contains('subscribers only')),
      );
      final waiting = _broadcast(_mpdBody({'success': 'waiting_for_start'}));
      expect(SteamBroadcastApi.room(waiting).effectiveLiveStatus, LiveStatus.unknown);
      expect(SteamBroadcastApi.room(waiting).notice, SteamBroadcastApi.chatNotice);
      final replay = _broadcast(_mpdBody({'is_replay': 1}));
      expect(SteamBroadcastApi.room(replay).effectiveLiveStatus, LiveStatus.replay);
      expect(SteamBroadcastApi.room(replay).isPlayableNow, isTrue);
    });

    test("changed: 3.x's enrich fills what a room lacks from the card, but not the viewers after it ended (27-5)", () {
      final card = _page('S01-directory-p1', 1).broadcasts.first;
      final legacy = _maps(_result(_legacy('S05-watch-live')['after the directory']));
      final plain = SteamBroadcastApi.broadcast(
        _sample('S05-mpd-live').body,
        steamId: _live,
        profile: (name: 'PWM Game Manager', avatar: ''),
      );
      final entered = plain.enrich(card);
      // 27-1: 3.x showed the cover as avatar.
      _expectParity(_projection(SteamBroadcastApi.room(entered)), legacy.first, changed: {'avatar', ..._notice});
      expect(entered.title, 'NTE: Neverness to Everness');
      expect(entered.avatar, card.avatar);
      expect(entered.viewers, 7994, reason: "the room's own viewers win");
      final ended = SteamBroadcast(steamId: _live, state: SteamBroadcastState.offline, title: 'Own title').enrich(card);
      expect(ended.broadcaster, 'PWM Game Manager', reason: 'no name: the card');
      expect(ended.title, 'Own title');
      expect(ended.viewers, isNull, reason: '27-5: 3.x kept the last card viewers (6763) after the broadcast ended');
      expect(ended.state, SteamBroadcastState.offline);
      final stillLive = SteamBroadcast(steamId: _live, state: SteamBroadcastState.live).enrich(card);
      expect(stillLive.viewers, 6763, reason: 'still live without a count of its own: the card');
      final unknown = SteamBroadcast(steamId: _live, state: SteamBroadcastState.unknown).enrich(card);
      expect(unknown.viewers, isNull);
    });

    test('room data: why a room cannot be played; its qualities', () {
      final master = Uri.parse('https://cache1.steamcontent.com/broadcast/$_live/1/hls_manifest/0/x/master.m3u8');
      SiteError? error(SteamBroadcastState state, {Uri? at, SiteError? media, LiveRestriction? restriction}) =>
          SteamBroadcastRoomData(
            steamId: _live,
            state: state,
            master: at,
            mediaError: media,
            restriction: restriction,
          ).streamError;
      expect(error(SteamBroadcastState.live, at: master), isNull);
      expect(error(SteamBroadcastState.replay, at: master), isNull);
      expect(error(SteamBroadcastState.live), isA<StreamUnavailable>(), reason: 'refresh: no checked master');
      expect(error(SteamBroadcastState.live, media: const NotFound('steambroadcast')), isA<NotFound>());
      expect(
        error(SteamBroadcastState.live, at: master, restriction: LiveRestriction.subscribersOnly),
        isA<StreamUnavailable>(),
      );
      for (final state in [
        SteamBroadcastState.offline,
        SteamBroadcastState.accountRestricted,
        SteamBroadcastState.unknown,
      ]) {
        expect(error(state, at: master), isA<StreamUnavailable>(), reason: state.name);
      }
      final refreshed = _broadcast(_sample('S05-mpd-live').body);
      expect(SteamBroadcastApi.roomData(refreshed).master, isNull, reason: 'not checked');
      final scs = SteamBroadcastApi.roomData(_enteredScs());
      expect(scs.qualities.map((quality) => (quality.quality, quality.id)), [
        ('自适应 HLS', 'auto'),
        ('1080p60', '1080p60'),
        ('720p', '720p'),
        ('480p', '480p'),
        ('360p', '360p'),
      ]);
      expect(scs.qualities.first, same(SteamBroadcastApi.quality), reason: "3.x's quality first, its id unchanged");
      expect(scs.qualities[2].data, scs.variants[1]);
      expect(scs.qualities.map((quality) => quality.sort).toSet(), {0}, reason: 'the list order is the order');
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

    test('S09 entered room: everything from its own answers, recorded in one minute', () {
      final broadcast = _enteredScs();
      final room = SteamBroadcastApi.room(broadcast, data: SteamBroadcastApi.roomData(broadcast));
      expect(room.nick, 'SCS Software');
      expect(room.avatar, 'https://avatars.fastly.steamstatic.com/ea764a9a9aa36897901e5a2cb1fe951fde29462e_full.jpg');
      expect((room.title, room.area), ('Euro Truck Simulator 2', 'Euro Truck Simulator 2'));
      expect(room.cover, contains('/broadcast/$_scs/'));
      expect(room.effectiveOnlineViewers, '2490');
      expect(room.restriction, LiveRestriction.none);
      expect(broadcast.broadcastId, '7677968762198629065');
    });

    test('danmaku arguments are the Steam id and the current broadcast (27-6)', () {
      const args = SteamBroadcastDanmakuArgs(_live, broadcastId: '4005242549293303728');
      expect(args.toString(), _live);
      expect(args, const SteamBroadcastDanmakuArgs(_live, broadcastId: '4005242549293303728'));
      expect(args, isNot(const SteamBroadcastDanmakuArgs(_live)));
    });

    test('changed: the notice only explains the viewers since the chat is shown (M5.23)', () {
      expect(SteamBroadcastApi.chatNotice, '人数是正在观看的人数。');
      expect(SteamBroadcastApi.chatNotice, isNot(contains('聊天')), reason: 'no "chat cannot be shown" left');
      final notices = <Object?>[];
      void collect(Object? value) {
        if (value is Map) {
          value.forEach((key, item) => key == 'notice' ? notices.add(item) : collect(item));
        } else if (value is List) {
          value.forEach(collect);
        }
      }

      for (final sample in ['S01-directory-p1', 'S01-directory-p2', 'S05-watch-live', 'S05-watch-offline']) {
        collect(_legacy(sample));
      }
      expect(notices, isNotEmpty);
      expect(notices.toSet(), {SteamBroadcastApi.legacyChatNotice}, reason: "every 3.x room carried 3.x's text");
    });
  });

  group('errors', () {
    test("statuses map as 3.x's did, by type, for every answer", () {
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
        expect(() => SteamBroadcastApi.broadcast('{}', steamId: _live, status: status), throwsA(matcher));
        expect(() => SteamBroadcastApi.info('{}', steamId: _live, status: status), throwsA(matcher));
        expect(() => SteamBroadcastApi.profile('{}', steamId: _live, status: status), throwsA(matcher));
        expect(() => SteamBroadcastApi.steamIdOfProfileXml('', status: status), throwsA(matcher));
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
