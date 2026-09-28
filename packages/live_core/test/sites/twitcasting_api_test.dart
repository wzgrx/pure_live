// TwitCasting parsing against the recorded samples, compared field by field
// with 3.x's frozen output (expected.json, written by
// fixtures/twitcasting/legacy_expected.dart from 3.x's parsers). Every
// intended difference is listed with its reason; everything else must match.
// The rules without a sample are ported from 3.x's
// test/twitcasting_adapter_test.dart, over its synthetic contract fixtures
// (test/fixtures/twitcasting/, inlined below).
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('twitcasting', name);

/// Asserts that [actual] (a `toJson`) equals 3.x's [legacy] map on every key
/// 3.x wrote, except [changed] (intended differences). 3.x wrote null where
/// the immutable model writes ''.
void _expectParity(
  Map<String, Object?> actual,
  Map<String, dynamic> legacy, {
  Set<String> changed = const {},
  String? reason,
}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (changed.contains(key)) continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
}

/// 3.x's room projection: toJson plus `link`.
Map<String, Object?> _projection(LiveRoom room) => {...room.toJson(), 'link': room.link};

Map<String, dynamic> _legacy(String sample) => _sample(sample).legacy as Map<String, dynamic>;

List<Map<String, dynamic>> _legacyRooms(Object? value) => (value! as List).cast<Map<String, dynamic>>();

// 3.x's contract fixtures (legacy/test/fixtures/twitcasting/) ---------------

/// directory.json's row: movie 42 of `fixture_artist`.
const Map<String, Object?> _row = {
  'id': '42',
  'title': 'Drawing',
  'telop': 'Public live',
  'live_url': '/fixture_artist/movie/42',
  'comment_count': 5752,
  'current_viewer_count': 2260,
  'total_viewer_count': null,
  'thumbnail_url': '//images.twitcasting.tv/cover.jpg',
  'user_name': 'Fixture Artist',
  'elapsed_time': 6584,
  'is_live': true,
  'is_locked': false,
  'is_group': false,
  'is_deleted': false,
  'user_icon_url': 'https://images.twitcasting.tv/avatar.jpg',
  'user_screen_name': 'fixture_artist',
  'user_id': 'fixture_artist',
};

/// room.html: the selectors 3.x read.
const _roomHtml = '''
<!doctype html><html><head><meta name="twitter:creator" content="fixture_artist">
<meta name="twitter:title" content="Drawing &amp; music">
<meta property="og:image" content="https://images.twitcasting.tv/cover.jpg"></head>
<body><div class="tw-user-header" data-user-id="fixture_artist"></div><nav class="tw-user-nav2">
<div class="tw-user-nav2-icon"><img src="https://images.twitcasting.tv/avatar.jpg"></div>
<span class="tw-user-nav2-name">Fixture Artist</span></nav></body></html>''';

/// categories.html.
const _categoriesHtml = '''
<html><body><a class="tw-top-tab-item" data-channel="_system_channel_popular"
href="/?genre=_system_channel_popular">Popular Lives</a><a class="tw-top-tab-item"
data-channel="_system_games_only" href="/?genre=_system_games_only">Twitcast Games</a></body></html>''';

/// live-stream.json: movie 42 with its three tiers.
Map<String, Object?> _liveStream() => {
  'movie': {'id': 42, 'live': true},
  'tc-hls': {
    'streams': {
      'high': 'https://edge.twitcasting.tv/tc.livehls/v1/streams/42/hls/672.96/media.m3u8',
      'medium': 'https://edge.twitcasting.tv/tc.livehls/v1/streams/42/hls/671.96/media.m3u8',
      'low': 'https://edge.twitcasting.tv/tc.livehls/v1/streams/42/hls/480.64/media.m3u8',
    },
  },
};

/// 3.x's `searchHtml`: [count] live rows of `c:artist{i}` and the other
/// sections.
String _searchHtml(int count, {bool liveBadge = true}) =>
    '''
<html><body><div id="tw-search-result-live">
${List.generate(count, (i) => '''
<div class="tw-search-result-row">
  <a class="tw-movie-thumbnail2" href="/c:artist$i/movie/${i + 1}">
    <div class="tw-movie-thumbnail2-image-wrapper" data-can-play="true">
      <img class="tw-movie-thumbnail2-image" src="https://images.twitcasting.tv/cover$i.jpg">
      ${liveBadge ? '<span class="tw-movie-thumbnail2-badge" data-status="live">LIVE</span>' : ''}
    </div><span class="tw-movie-thumbnail-title">Stream $i</span>
  </a>
  <div class="tw-search-result-row-user-name"><div class="userimage32">
    <img src="https://images.twitcasting.tv/avatar$i.jpg">
  </div><div class="usertext"><a href="/c:artist$i"><span class="username">Artist $i</span></a></div></div>
</div>''').join()}
</div><div id="tw-search-result-movie"><div class="tw-search-result-row">old recording</div></div>
<div id="tw-search-result-user"><div class="tw-search-result-row">offline profile</div></div>
</body></html>
''';

String _movies(List<Map<String, Object?>> rows) => jsonEncode({'movies': rows});

LiveRoom _page(String html, {String channel = 'fixture_artist'}) =>
    TwitcastingApi.channelPage(html, roomId: channel, channel: channel);

TwitcastingRoomData _stream(Map<String, Object?> json) => TwitcastingApi.streamServer(jsonEncode(json));

void main() {
  group('S01 catalog', () {
    test('the homepage tabs: one category, its areas in page order, as 3.x', () {
      final fixture = _sample('S01-home');
      final categories = TwitcastingApi.categories(fixture.body, status: fixture.status);
      final legacy = (_legacy('S01-home')['page1'] as List).cast<Map<String, dynamic>>();
      expect(categories.map((category) => (category.id, category.name)), [
        for (final category in legacy) (category['id'], category['name']),
      ]);
      final areas = (legacy.single['children'] as List).cast<Map<String, dynamic>>();
      expect(categories.single.children, hasLength(18));
      expect(categories.single.children, hasLength(areas.length));
      for (final (index, area) in categories.single.children.indexed) {
        _expectParity(area.toJson(), areas[index], reason: 'S01[$index]');
      }
      expect(categories.single.children.first.areaName, 'Popular', reason: 'English without Accept-Language');
    });

    test("3.x's keys and labels; a tab without a key is not an area", () {
      final group = TwitcastingApi.categories(_categoriesHtml).single;
      expect(group.children.map((area) => area.areaId), ['_system_channel_popular', '_system_games_only']);
      expect(group.children.first.areaName, 'Popular Lives');
      expect(group.children.first.areaType, 'directory');
      final forYou = TwitcastingApi.categories(
        [
          '<a class="tw-top-tab-item" href="/?ch0">For You</a>',
          '<a class="x tw-top-tab-item" data-channel="k">A &amp; B</a>',
          '<a class="tw-top-tab-item" data-channel="k">C</a>',
          '<script>document.write(\'<a class="tw-top-tab-item" data-channel="s">S</a>\')</script>',
        ].join(),
      ).single;
      expect(forYou.children.map((area) => (area.areaId, area.areaName)), [('k', 'A & B')]);
    });

    test('a bad tab, no tab or over 100 fail the catalog instead of emptying it (3.x)', () {
      for (final html in [
        '<a class="tw-top-tab-item" data-channel="../x">X</a>',
        '<a class="tw-top-tab-item" data-channel="k">  </a>',
        '<html>challenge</html>',
        [for (var i = 0; i < 101; i++) '<a class="tw-top-tab-item" data-channel="k$i">$i</a>'].join(),
      ]) {
        expect(() => TwitcastingApi.categories(html), throwsA(isA<ApiChanged>()), reason: html);
      }
      expect(() => TwitcastingApi.categories('', status: 403), throwsA(isA<RiskControl>()));
      expect(() => TwitcastingApi.categories('', status: 503), throwsA(isA<NetworkFailure>()));
    });
  });

  group('S02 lists', () {
    for (final name in ['S02-top-all', 'S02-top-game']) {
      test('$name: the window 3.x asked for, room by room', () {
        final fixture = _sample(name);
        final rooms = TwitcastingApi.directory(fixture.body, offset: 0, pageSize: 60, status: fixture.status);
        final legacy = _legacyRooms(_legacy(name)['page1size60']);
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        for (final (index, room) in rooms.indexed) {
          _expectParity(_projection(room), legacy[index], reason: '$name[$index]');
          expect(room.onlineViewers, room.watching, reason: 'current_viewer_count is a head count');
        }
        expect(_legacy(name)['page2size60'], isEmpty, reason: 'one window, no second page');
      });
    }

    test("slices of 20 are 3.x's slices of the raw window", () {
      final fixture = _sample('S02-top-all');
      final legacy = (_legacy('S02-top-all')['size20'] as List).cast<List<Object?>>();
      for (final page in [1, 2, 3, 4]) {
        expect(
          TwitcastingApi.directory(fixture.body, offset: (page - 1) * 20, pageSize: 20).map((room) => room.roomId),
          legacy[page - 1],
          reason: 'page $page',
        );
      }
    });

    test('the telop is the title; without one the default title, trimmed', () {
      final rooms = {
        for (final room in TwitcastingApi.directory(_sample('S02-top-all').body, offset: 0, pageSize: 60))
          room.roomId: room,
      };
      expect(rooms['c:abzou_sub']!.title, '殺〇予告された！？');
      expect(rooms['nabo66game']!.title, "Nabo66game's Live");
      expect(rooms['c:97_a']!.title, '', reason: 'an ideographic space only');
    });

    test('online counts, the channel as identity (not the movie), https covers (3.x)', () {
      final room = TwitcastingApi.directory(_movies([_row]), offset: 0, pageSize: 30).single;
      expect(room.roomId, 'fixture_artist');
      expect(room.userId, 'fixture_artist');
      expect(room.link, 'https://twitcasting.tv/fixture_artist');
      expect(room.title, 'Public live');
      expect(room.onlineViewers, '2260');
      expect(room.watching, '2260');
      expect(room.effectiveAudienceMetricType, AudienceMetricType.onlineViewers);
      expect(room.totalViewers, isEmpty);
      expect(room.cover, 'https://images.twitcasting.tv/cover.jpg');
      expect(room.avatar, 'https://images.twitcasting.tv/avatar.jpg');
      expect(room.nick, 'Fixture Artist');
      expect(room.effectiveLiveStatus, LiveStatus.live);
    });

    test('locked, group, deleted, ended and repeated broadcasts are not cards (3.x)', () {
      final rows = [
        _row,
        _row,
        {..._row, 'is_locked': true},
        {..._row, 'is_group': true, 'current_viewer_count': null},
        {..._row, 'is_deleted': true},
        {..._row, 'is_live': false},
      ];
      expect(TwitcastingApi.directory(_movies(rows), offset: 0, pageSize: 60), hasLength(1));
    });

    test('rows are sliced before they are filtered, as 3.x did', () {
      // 3.x test/twitcasting_directory_paging_test.dart: 60 rows, the first a
      // group broadcast without a viewer count.
      final rows = [
        for (var i = 0; i < 60; i++)
          {
            ..._row,
            'id': '${i + 1}',
            'user_id': 'artist$i',
            'live_url': '/artist$i/movie/${i + 1}',
            'current_viewer_count': i == 0 ? null : 1000 - i,
            'is_group': i == 0,
          },
      ];
      final body = _movies(rows);
      final window = TwitcastingApi.directory(body, offset: 0, pageSize: 60);
      expect(window, hasLength(59));
      expect(window.map((room) => room.roomId), contains('artist59'));
      expect(TwitcastingApi.directory(body, offset: 0, pageSize: 20), hasLength(19));
      expect(TwitcastingApi.directory(body, offset: 30, pageSize: 30).first.roomId, 'artist30');
    });

    for (final field in [
      'is_live',
      'is_locked',
      'is_group',
      'is_deleted',
      'current_viewer_count',
      'live_url',
      'id',
      'user_id',
    ]) {
      test('a row without $field is ApiChanged, not an empty list (3.x)', () {
        final row = Map<String, Object?>.of(_row)..remove(field);
        expect(() => TwitcastingApi.directory(_movies([row]), offset: 0, pageSize: 30), throwsA(isA<ApiChanged>()));
      });
    }

    test('a movie link of another channel, over 60 rows, no rows or not JSON are ApiChanged', () {
      for (final body in [
        _movies([
          {..._row, 'live_url': '/other/movie/42'},
        ]),
        _movies([for (var i = 0; i < 61; i++) _row]),
        '{}',
        '<html>',
      ]) {
        expect(
          () => TwitcastingApi.directory(body, offset: 0, pageSize: 30),
          throwsA(isA<ApiChanged>()),
          reason: body.length > 40 ? body.substring(0, 40) : body,
        );
      }
    });
  });

  group('S03 search', () {
    test('a private broadcast is left out where 3.x failed the whole page', () {
      final fixture = _sample('S03-search');
      final legacy = _legacy('S03-search');
      expect(legacy['page1'], {'throws': 'TwitcastingException', 'message': 'TwitCasting schema'});
      final rooms = TwitcastingApi.searchRooms(fixture.body, page: 1, pageSize: 20, status: fixture.status);
      // withoutPrivateRow: 3.x's answer to the same page without the private
      // row (fixtures/twitcasting/legacy_expected.dart).
      final reference = _legacyRooms(legacy['withoutPrivateRow']);
      expect(rooms.map((room) => room.roomId), reference.map((room) => room['roomId']));
      for (final (index, room) in rooms.indexed) {
        _expectParity(_projection(room), reference[index], reason: 'S03[$index]');
      }
      expect(rooms, hasLength(14));
      expect(rooms.map((room) => room.roomId), isNot(contains('g:107135074068699391720')));
      expect(rooms.first.title, 'クラッシュバンディクー３');
      expect(rooms.first.watching, isEmpty, reason: 'the page shows comments, not viewers');
      for (final page in [2, 3, 4]) {
        expect(TwitcastingApi.searchRooms(fixture.body, page: page, pageSize: 20), legacy['page$page']);
      }
    });

    test('live rows only, with no audience (3.x)', () {
      final rooms = TwitcastingApi.searchRooms(_searchHtml(2), page: 1, pageSize: 20);
      expect(rooms.map((room) => room.roomId), ['c:artist0', 'c:artist1']);
      expect(rooms.first.link, 'https://twitcasting.tv/c:artist0');
      expect(rooms.first.nick, 'Artist 0');
      expect(rooms.first.title, 'Stream 0');
      expect(rooms.first.cover, 'https://images.twitcasting.tv/cover0.jpg');
      expect(rooms.first.avatar, 'https://images.twitcasting.tv/avatar0.jpg');
      expect(rooms.first.isLiveNow, isTrue);
      expect(rooms.first.watching, isEmpty);
      expect(rooms.first.onlineViewers, isEmpty);
      expect(rooms.first.effectiveAudienceMetricType, AudienceMetricType.unknown);
    });

    test('pages are cut from the 50-row window (3.x)', () {
      final body = _searchHtml(50);
      expect(TwitcastingApi.searchRooms(body, page: 2, pageSize: 20).first.roomId, 'c:artist20');
      expect(TwitcastingApi.searchRooms(body, page: 3, pageSize: 20), hasLength(10));
      expect(() => TwitcastingApi.searchRooms(_searchHtml(51), page: 1, pageSize: 20), throwsA(isA<ApiChanged>()));
    });

    test('rows that are not live and playable are left out (3.x failed the page)', () {
      expect(TwitcastingApi.searchRooms(_searchHtml(1, liveBadge: false), page: 1, pageSize: 20), isEmpty);
      expect(
        TwitcastingApi.searchRooms(
          _searchHtml(1).replaceFirst('data-can-play="true"', 'data-can-play="false"'),
          page: 1,
          pageSize: 20,
        ),
        isEmpty,
      );
    });

    test('a challenge page or a malformed live row is ApiChanged (3.x)', () {
      for (final body in [
        '<html>challenge</html>',
        _searchHtml(1).replaceFirst('/c:artist0/movie/1', '/c:other/movie/1'),
        _searchHtml(1).replaceFirst('/c:artist0/movie/1', '/c:artist0/movie/x'),
        _searchHtml(1).replaceFirst('href="/c:artist0"', 'href="https://evil.test/c:artist0"'),
        _searchHtml(1).replaceFirst('href="/c:artist0"', 'href="/search"'),
      ]) {
        expect(
          () => TwitcastingApi.searchRooms(body, page: 1, pageSize: 20),
          throwsA(isA<ApiChanged>()),
          reason: body.length > 60 ? body.substring(0, 60) : body,
        );
      }
      expect(() => TwitcastingApi.searchRooms('', page: 1, pageSize: 20, status: 429), throwsA(isA<RateLimited>()));
    });
  });

  group('S04/S05 rooms', () {
    LiveRoom detail(String page, String stream, String channel) => TwitcastingApi.roomDetail(
      TwitcastingApi.channelPage(_sample(page).body, roomId: channel, channel: channel),
      TwitcastingApi.streamServer(_sample(stream).body),
    );

    test("a live channel: 3.x's room, the channel as it was asked for", () {
      final room = detail('S04-page-live', 'S05-stream-live', 'nabo66game');
      final legacy = _legacy('S04-page-live');
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh']) {
        _expectParity(_projection(room), legacy[key] as Map<String, dynamic>, reason: key);
      }
      _expectParity(_projection(room), _legacyRooms(legacy['searchRooms(link)']).single, reason: 'link search');
      expect(room.title, 'Live #841525457', reason: "3.x's twitter:title, not the telop (REG-TWITCASTING-004 kept)");
      final data = room.data! as TwitcastingRoomData;
      expect(data.movieId, 841525457);
      expect(data.live, isTrue);
    });

    test('an offline channel keeps none of the stale URLs of another broadcast (REG-TWITCASTING-001)', () {
      final room = detail('S04-page-offline', 'S05-stream-offline', 'twitcasting_jp');
      final legacy = _legacy('S04-page-offline');
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh']) {
        _expectParity(_projection(room), legacy[key] as Map<String, dynamic>, reason: key);
      }
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      final data = room.data! as TwitcastingRoomData;
      expect(data.live, isFalse);
      expect(data.streams, isEmpty);
      expect(_sample('S05-stream-offline').body, contains('/streams/841532464/'), reason: 'the stale broadcast');
      // getPlayQualites: 3.x gave an empty list; not broadcasting is
      // StreamUnavailable now.
      expect(legacy['getPlayQualites'], isEmpty);
      expect(() => TwitcastingApi.qualities(data), throwsA(isA<StreamUnavailable>()));
    });

    test('an unknown channel is NotFound (3.x followed the redirect home and failed as schema)', () {
      final legacy = _legacy('S04-page-notfound');
      expect(legacy['getRoomDetail'], {'throws': 'TwitcastingException', 'message': 'TwitCasting schema'});
      final page = _sample('S04-page-notfound');
      expect(
        () => TwitcastingApi.channelPage(page.body, roomId: 'x', channel: 'zxqvnochannelfixture', status: page.status),
        throwsA(isA<NotFound>()),
      );
      expect(() => TwitcastingApi.streamServer(_sample('S05-stream-notfound').body), throwsA(isA<NotFound>()));
    });

    test("the live tiers: 3.x's names, ids, order and URLs", () {
      final data = detail('S04-page-live', 'S05-stream-live', 'nabo66game').data! as TwitcastingRoomData;
      final qualities = TwitcastingApi.qualities(data);
      final legacy = (_legacy('S04-page-live')['getPlayQualites'] as List).cast<Map<String, dynamic>>();
      expect(qualities.map((quality) => (quality.quality, quality.id, quality.sort)), [
        for (final quality in legacy) (quality['quality'], quality['id'], quality['sort']),
      ]);
      for (final (index, quality) in qualities.indexed) {
        expect(TwitcastingApi.resolution(data, quality).urls, legacy[index]['getPlayUrls']);
      }
      expect(qualities.clear, throwsUnsupportedError);
    });

    test("a line carries 3.x's media headers, HLS and its host; no cookie and no lease", () {
      final data = _stream(_liveStream());
      final resolution = TwitcastingApi.resolution(data, TwitcastingApi.qualities(data)[1]);
      final line = resolution.lines.single;
      expect(line.url, contains('/671.96/'));
      expect(line.headers, {
        'referer': 'https://twitcasting.tv/',
        'origin': 'https://twitcasting.tv',
        'user-agent': 'Mozilla/5.0',
      });
      expect(line.headers.keys, isNot(contains('cookie')));
      expect(line.format, StreamFormat.hls);
      expect(line.lineId, 'edge.twitcasting.tv');
      expect(line.lease, isNull, reason: 'the playlist URL has no signature or expiry');
      expect(resolution.appliedQualityData, 'medium');
      expect(
        () => TwitcastingApi.resolution(data, const LivePlayQuality(quality: 'ultra', id: 'ultra')),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test("3.x's page selectors, with character references decoded", () {
      final room = _page(_roomHtml);
      expect(room.title, 'Drawing & music');
      expect(room.nick, 'Fixture Artist');
      expect(room.avatar, 'https://images.twitcasting.tv/avatar.jpg');
      expect(room.cover, 'https://images.twitcasting.tv/cover.jpg');
      expect(room.link, 'https://twitcasting.tv/fixture_artist');
      expect(room.watching, isEmpty);
      expect(room.liveStatus, isNull, reason: 'the state is streamserver.php');
      final requested = TwitcastingApi.channelPage(_roomHtml, roomId: 'Fixture_Artist', channel: 'fixture_artist');
      expect(requested.roomId, 'Fixture_Artist', reason: 'a follow keeps the id it was made with');
      expect(requested.userId, 'fixture_artist');
    });

    test('the telop only fills an empty twitter:title', () {
      final html = _roomHtml.replaceFirst(
        'content="Drawing &amp; music">',
        'content=" "><meta name="twitter:description" content="Tonight\'s telop">',
      );
      expect(_page(html).title, "Tonight's telop");
      expect(_page(_sample('S04-page-offline').body, channel: 'twitcasting_jp').title, startsWith('映画'));
    });

    test('a secret word is NeedsLogin; another creator or header is ApiChanged (3.x)', () {
      expect(() => _page('Enter the secret word to access'), throwsA(isA<NeedsLogin>()));
      for (final html in [
        _roomHtml.replaceFirst('content="fixture_artist"', 'content="other"'),
        _roomHtml.replaceFirst('data-user-id="fixture_artist"', 'data-user-id="other"'),
        _roomHtml.replaceFirst('<div class="tw-user-header" data-user-id="fixture_artist"></div>', ''),
        '$_roomHtml<meta name="twitter:creator" content="fixture_artist">',
        _sample('S01-home').body,
      ]) {
        expect(() => _page(html), throwsA(isA<ApiChanged>()));
      }
      for (final (status, type) in [
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (503, isA<NetworkFailure>()),
        (302, isA<NotFound>()),
        (301, isA<NotFound>()),
        (204, isA<NetworkFailure>()),
      ]) {
        expect(
          () => TwitcastingApi.channelPage('credential=do-not-expose', roomId: 'a', channel: 'a', status: status),
          throwsA(type.having((error) => '$error', 'text', isNot(contains('do-not-expose')))),
          reason: '$status',
        );
      }
    });

    test('streamserver: {} is NotFound; no boolean movie.live is ApiChanged', () {
      expect(() => TwitcastingApi.streamServer('{}'), throwsA(isA<NotFound>()));
      for (final body in ['{"movie":{"id":42,"live":null}}', '{"movie":null}', '{"tc-hls":{}}', '[]', 'x']) {
        expect(() => TwitcastingApi.streamServer(body), throwsA(isA<ApiChanged>()), reason: body);
      }
      expect(() => TwitcastingApi.streamServer('', status: 404), throwsA(isA<NotFound>()));
    });

    test('tiers are checked when played: no tier, a broken tc-hls or another URL is ApiChanged (3.x)', () {
      final stale = _stream({
        'movie': {'id': 42, 'live': true},
        'tc-hls': 'stale',
      });
      expect(stale.live, isTrue, reason: 'the room still loads (3.x link search did too)');
      expect(() => TwitcastingApi.qualities(stale), throwsA(isA<ApiChanged>()));
      expect(
        () => TwitcastingApi.qualities(
          _stream({
            'movie': {'id': 42, 'live': true},
            'tc-hls': {'streams': <String, Object?>{}},
          }),
        ),
        throwsA(isA<ApiChanged>()),
      );
      for (final url in [
        'https://edge.twitcasting.tv/tc.livehls/v1/streams/999/hls/672.96/media.m3u8',
        'https://evil.test/tc.livehls/v1/streams/42/hls/672.96/media.m3u8',
        'http://edge.twitcasting.tv/tc.livehls/v1/streams/42/hls/672.96/media.m3u8',
        'https://user@edge.twitcasting.tv/tc.livehls/v1/streams/42/hls/672.96/media.m3u8',
        'https://edge.twitcasting.tv/tc.livehls/v1/streams/42/hls/../media.m3u8',
        'https://edge.twitcasting.tv:8443/tc.livehls/v1/streams/42/hls/672.96/media.m3u8',
      ]) {
        final json = _liveStream();
        json['tc-hls'] = {
          'streams': {'high': url},
        };
        expect(() => TwitcastingApi.qualities(_stream(json)), throwsA(isA<ApiChanged>()), reason: url);
      }
      final withoutId = _liveStream()..['movie'] = {'live': true};
      expect(() => TwitcastingApi.qualities(_stream(withoutId)), throwsA(isA<ApiChanged>()));
    });

    test('a missing tier is left out; the rest keep their order', () {
      final json = _liveStream();
      ((json['tc-hls']! as Map)['streams']! as Map).remove('high');
      final qualities = TwitcastingApi.qualities(_stream(json));
      expect(qualities.map((quality) => (quality.id, quality.quality, quality.sort)), [
        ('medium', 'HLS medium', 3),
        ('low', 'HLS low', 2),
      ]);
    });
  });

  group('channels', () {
    test('ids keep their social prefix and are lower case; site pages are not channels', () {
      for (final (input, channel) in [
        ('fixture_artist', 'fixture_artist'),
        ('c:fixture', 'c:fixture'),
        ('g:113775126361409198504', 'g:113775126361409198504'),
        (' Fixture_Artist ', 'fixture_artist'),
        ('IG:Name_1', 'ig:name_1'),
      ]) {
        expect(TwitcastingApi.channelName(input), channel);
      }
      for (final input in ['', 'search', 'categories', 'x:abc', 'a-b', 'a/b', 'a' * 65, 'c:']) {
        expect(TwitcastingApi.channelName(input), isNull, reason: input);
      }
    });
  });
}
