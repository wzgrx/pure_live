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

/// [_row] of another channel [channel] (movie [movie]).
Map<String, Object?> _rowOf(String channel, {int movie = 43}) => {
  ..._row,
  'id': '$movie',
  'user_id': channel,
  'live_url': '/$channel/movie/$movie',
};

TwitcastingChannelPage _parsed(String html, {String channel = 'fixture_artist'}) =>
    TwitcastingApi.channelPage(html, roomId: channel, channel: channel);

LiveRoom _page(String html, {String channel = 'fixture_artist'}) => _parsed(html, channel: channel).room;

TwitcastingRoomData _stream(Map<String, Object?> json) => TwitcastingApi.streamServer(jsonEncode(json));

/// [_roomHtml] showing a live broadcast [movie] with [telop] under its
/// title (the live page's markup, sample S04-page-live).
String _livePage({String telop = '', int movie = 42, int startedAt = 1790519194000}) =>
    _roomHtml.replaceFirst('</body>', '''
<span id="updatetimer" class="tw-player-duration-time" aria-label="Duration:" data-live-type="live"
  data-started-at="$startedAt" data-duration="12942000">00:00</span>
<h2 id="player-title">Drawing &amp; music</h2>
<span class="tw-player-page-title-description">
  $telop <span class="tw-player-page-title-description-text"></span>
  <a href="/search/tag/art" class="tag tag-info">art</a>
</span>
<div id="comment-list-app" data-movie-id="$movie" data-passcode=""></div></body>''');

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

    test('group, deleted, ended and repeated broadcasts are not cards (3.x)', () {
      final rows = [
        _row,
        _row,
        {..._rowOf('group'), 'is_group': true, 'current_viewer_count': null},
        {..._rowOf('deleted'), 'is_deleted': true},
        {..._rowOf('ended'), 'is_live': false},
      ];
      expect(TwitcastingApi.directory(_movies(rows), offset: 0, pageSize: 60).map((room) => room.roomId), [
        'fixture_artist',
      ]);
    });

    test('a locked broadcast is a live card marked password-protected; the others have no restriction', () {
      // Unified rule for restricted rooms: 3.x left locked broadcasts out.
      final rooms = TwitcastingApi.directory(
        _movies([
          _row,
          {..._rowOf('locked'), 'is_locked': true},
        ]),
        offset: 0,
        pageSize: 60,
      );
      expect(rooms.map((room) => (room.roomId, room.restriction, room.isLiveNow)), [
        ('fixture_artist', LiveRestriction.none, true),
        ('locked', LiveRestriction.password, true),
      ]);
      expect(rooms.last.followGroup, FollowGroup.live);
      for (final name in ['S02-top-all', 'S02-top-game']) {
        final sample = TwitcastingApi.directory(_sample(name).body, offset: 0, pageSize: 60);
        expect(sample.map((room) => room.restriction).toSet(), {LiveRestriction.none}, reason: name);
      }
    });

    test('the start time is the answer time less elapsed_time, to the second', () {
      final fixture = _sample('S02-top-all');
      final rooms = {
        for (final room in TwitcastingApi.directory(fixture.body, offset: 0, pageSize: 60, now: fixture.capturedAt))
          room.roomId: room,
      };
      expect(fixture.capturedAt, DateTime.utc(2026, 9, 27, 18, 1, 57, 219, 2));
      // 12923 s before 18:01:57: the channel page's data-started-at (S04).
      expect(rooms['nabo66game']!.startedAt, DateTime.utc(2026, 9, 27, 14, 26, 34));
      expect(
        rooms['nabo66game']!.startedAt,
        TwitcastingApi.channelPage(
          _sample('S04-page-live').body,
          roomId: 'nabo66game',
          channel: 'nabo66game',
        ).liveStartedAt,
      );
      expect(rooms.values.every((room) => room.startedAt!.isBefore(fixture.capturedAt)), isTrue);
      expect(TwitcastingApi.directory(fixture.body, offset: 0, pageSize: 60).first.startedAt, isNull);
      final now = DateTime.utc(2026, 9, 29, 12, 0, 0, 900);
      for (final (elapsed, started) in [
        (6584, DateTime.utc(2026, 9, 29, 10, 10, 16)),
        (0, DateTime.utc(2026, 9, 29, 12)),
        (-1, null),
        ('60', DateTime.utc(2026, 9, 29, 11, 59)),
        ('x', null),
        (null, null),
      ]) {
        final room = TwitcastingApi.directory(
          _movies([
            {..._row, 'elapsed_time': elapsed},
          ]),
          offset: 0,
          pageSize: 1,
          now: now,
        ).single;
        expect(room.startedAt, started, reason: '$elapsed');
      }
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
      test('a row without $field is skipped; a window of only such rows is ApiChanged', () {
        // Unified fault-tolerance rule: 3.x failed the whole list.
        final row = Map<String, Object?>.of(_row)..remove(field);
        expect(
          TwitcastingApi.directory(_movies([row, _rowOf('good')]), offset: 0, pageSize: 30).map((room) => room.roomId),
          ['good'],
        );
        expect(TwitcastingApi.directoryRows(_movies([row, _rowOf('good')])), [isNull, isNotNull]);
        expect(() => TwitcastingApi.directory(_movies([row]), offset: 0, pageSize: 30), throwsA(isA<ApiChanged>()));
      });
    }

    test('a malformed row among good ones only drops itself; left-out rows alone are an empty list', () {
      final rows = [
        {..._row, 'live_url': '/other/movie/42'},
        {..._row, 'current_viewer_count': -1},
        {..._row, 'is_live': 'yes'},
        'not a row',
        _rowOf('good'),
      ];
      expect(TwitcastingApi.directory(jsonEncode({'movies': rows}), offset: 0, pageSize: 60), hasLength(1));
      expect(
        TwitcastingApi.directory(
          _movies([
            {..._row, 'is_live': false},
          ]),
          offset: 0,
          pageSize: 60,
        ),
        isEmpty,
      );
      expect(TwitcastingApi.directory(_movies([]), offset: 0, pageSize: 60), isEmpty);
    });

    test('rows that are all malformed, over 60 rows, no rows or not JSON are ApiChanged', () {
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
    test('a private broadcast is a live card marked private (12-5), where 3.x failed the whole page', () {
      final fixture = _sample('S03-search');
      final legacy = _legacy('S03-search');
      expect(legacy['page1'], {'throws': 'TwitcastingException', 'message': 'TwitCasting schema'});
      final rooms = TwitcastingApi.searchRooms(fixture.body, page: 1, pageSize: 20, status: fixture.status);
      expect(rooms, hasLength(15));
      final private = rooms[2];
      expect(private.roomId, 'g:107135074068699391720');
      expect(private.restriction, LiveRestriction.private);
      expect(private.isLiveNow, isTrue, reason: 'restricted broadcasts are still live (unified rule)');
      expect(private.followGroup, FollowGroup.live);
      expect(private.title, isEmpty);
      expect(private.startedAt, DateTime.utc(2026, 9, 27, 14, 2, 4));
      // withoutPrivateRow: 3.x's answer to the same page without the private
      // row (fixtures/twitcasting/legacy_expected.dart), for every other row.
      final others = [...rooms]..removeAt(2);
      final reference = _legacyRooms(legacy['withoutPrivateRow']);
      expect(others.map((room) => room.roomId), reference.map((room) => room['roomId']));
      for (final (index, room) in others.indexed) {
        _expectParity(_projection(room), reference[index], reason: 'S03[$index]');
        expect(room.restriction, LiveRestriction.none);
      }
      expect(rooms.first.title, 'クラッシュバンディクー３');
      expect(rooms.first.watching, isEmpty, reason: 'the page shows viewers only on private rows');
      for (final page in [2, 3, 4]) {
        expect(TwitcastingApi.searchRooms(fixture.body, page: page, pageSize: 20), legacy['page$page']);
      }
    });

    test("the start time is each row's datetime (Japan time), the channel page's for the same broadcast", () {
      final rooms = TwitcastingApi.searchRooms(_sample('S03-search').body, page: 1, pageSize: 50);
      expect(rooms.first.roomId, 'nabo66game');
      expect(rooms.first.startedAt, DateTime.utc(2026, 9, 27, 14, 26, 34));
      expect(rooms.every((room) => room.startedAt != null), isTrue);
      expect(rooms.every((room) => room.startedAt!.isBefore(_sample('S03-search').capturedAt)), isTrue);
      expect(TwitcastingApi.pageDate('Sun, 27 Sep 2026 23:26:34 +0900'), DateTime.utc(2026, 9, 27, 14, 26, 34));
      expect(TwitcastingApi.pageDate('Mon, 1 Jun 2026 01:02:03 -0130'), DateTime.utc(2026, 6, 1, 2, 32, 3));
      expect(TwitcastingApi.pageDate(' Thu, 24 Sep 2026 13:33:45 +0000 '), DateTime.utc(2026, 9, 24, 13, 33, 45));
      for (final text in [
        '',
        '2026/09/27 23:26:34',
        'Sun, 31 Feb 2026 23:26:34 +0900',
        'Sun, 27 Sep 2026 24:00:00 +0900',
        'Sun, 27 Sop 2026 23:26:34 +0900',
        'Thu, 01 Jan 1970 09:00:00 +0900',
      ]) {
        expect(TwitcastingApi.pageDate(text), isNull, reason: text);
      }
    });

    test('a private row seen now: the card is private, the channel page and streamserver.php say offline', () {
      // S03-search-private, S04-page-private and S05-stream-private were
      // recorded within 5 s: to an anonymous client a private broadcast is
      // live only in search.
      final rooms = TwitcastingApi.searchRooms(_sample('S03-search-private').body, page: 1, pageSize: 50);
      expect(rooms, hasLength(23));
      final private = rooms.where((room) => room.isRestricted).single;
      expect(private.roomId, 'g:117931547061051040135');
      expect(private.restriction, LiveRestriction.private);
      expect(private.startedAt, DateTime.utc(2026, 9, 28, 17, 3, 42));
      expect(rooms.where((room) => room.restriction == LiveRestriction.none), hasLength(22));
      final page = TwitcastingApi.channelPage(
        _sample('S04-page-private').body,
        roomId: private.roomId,
        channel: private.roomId,
      );
      final stream = TwitcastingApi.streamServer(_sample('S05-stream-private').body);
      expect(page.movieId, 841576546, reason: 'the private broadcast');
      expect(stream.movieId, 841576546);
      expect(stream.live, isFalse);
      expect(page.liveStartedAt, isNull, reason: 'the page shows it as a recording');
      final room = TwitcastingApi.roomDetail(page, stream);
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.restriction, isNull);
      expect(room.startedAt, isNull);
      expect(room.danmakuData, isNull);
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

    test('a playable row without the LIVE badge is left out (3.x); one the site will not play is marked', () {
      expect(TwitcastingApi.searchRooms(_searchHtml(1, liveBadge: false), page: 1, pageSize: 20), isEmpty);
      final notPlayable = _searchHtml(1).replaceFirst('data-can-play="true"', 'data-can-play="false"');
      expect(
        TwitcastingApi.searchRooms(notPlayable, page: 1, pageSize: 20).single.restriction,
        LiveRestriction.unplayable,
        reason: 'not private: the kind is unknown (M2.1)',
      );
      final private = _searchHtml(1, liveBadge: false)
          .replaceFirst('data-can-play="true"', 'data-can-play="false"')
          .replaceFirst('</div><span class="tw-movie-thumbnail-title">', '''
<span class="tw-movie-thumbnail2-badge" data-status="">
  Private </span></div><span class="tw-movie-thumbnail-title">''');
      final room = TwitcastingApi.searchRooms(private, page: 1, pageSize: 20).single;
      expect((room.restriction, room.effectiveLiveStatus), (LiveRestriction.private, LiveStatus.live));
    });

    test('a malformed live row only drops itself (unified fault tolerance; 3.x failed the page)', () {
      final body = _searchHtml(3).replaceFirst('/c:artist1/movie/2', '/c:other/movie/2');
      expect(TwitcastingApi.searchRooms(body, page: 1, pageSize: 20).map((room) => room.roomId), [
        'c:artist0',
        'c:artist2',
      ]);
      expect(TwitcastingApi.searchRows(body), [isNotNull, isNull, isNotNull]);
    });

    test('a challenge page or live rows that are all malformed are ApiChanged', () {
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

    test("a live channel: 3.x's room but the telop as title, the channel as it was asked for", () {
      final room = detail('S04-page-live', 'S05-stream-live', 'nabo66game');
      final legacy = _legacy('S04-page-live');
      // title: the broadcast's telop, 3.x showed twitter:title "Live #841525457" (12-1).
      _expectParity(_projection(room), legacy['getRoomDetail'] as Map<String, dynamic>, changed: {'title'});
      _expectParity(
        _projection(room),
        _legacyRooms(legacy['searchRooms(link)']).single,
        changed: {'title'},
        reason: 'link search',
      );
      expect((legacy['getRoomDetail'] as Map)['title'], 'Live #841525457');
      expect(room.title, 'クラッシュバンディクー３', reason: '12-1, REG-TWITCASTING-004');
      final data = room.data! as TwitcastingRoomData;
      expect(data.movieId, 841525457);
      expect(data.live, isTrue);
      expect(data.secretWord, isFalse);
    });

    test('a live channel has its start time, no restriction and the comment arguments (M2.1, 12-3)', () {
      final room = detail('S04-page-live', 'S05-stream-live', 'nabo66game');
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 14, 26, 34), reason: 'data-started-at 1790519194000');
      expect(room.startedAt!.isBefore(_sample('S04-page-live').capturedAt), isTrue);
      expect(room.restriction, LiveRestriction.none, reason: 'a private broadcast is never live to this client');
      final args = room.danmakuData! as TwitcastingDanmakuArgs;
      expect((args.channel, args.movieId), ('nabo66game', 841525457));
      expect('$args', 'TwitcastingDanmakuArgs(nabo66game, 841525457)');
      expect(room.toJson()['startedAt'], '2026-09-27T14:26:34.000Z');
      expect(room.toJson()['restriction'], 'none');
    });

    test('a start time of another broadcast than streamserver.php names is dropped', () {
      final page = _parsed(_livePage(movie: 41));
      expect(page.liveStartedAt, DateTime.utc(2026, 9, 27, 14, 26, 34));
      final room = TwitcastingApi.roomDetail(page, _stream(_liveStream()));
      expect(room.startedAt, isNull, reason: 'the page showed movie 41, the channel is live with 42');
      expect(TwitcastingApi.roomDetail(_parsed(_livePage()), _stream(_liveStream())).startedAt, isNotNull);
      final recording = _parsed(_livePage().replaceFirst('data-live-type="live"', 'data-live-type="movie"'));
      expect(recording.liveStartedAt, isNull, reason: 'a recording');
      expect(_parsed(_livePage(startedAt: 0)).liveStartedAt, isNull);
    });

    test('a follow refresh from streamserver.php alone: the state, no names (12-2)', () {
      final legacy = _legacy('S04-page-live')['getRoomDetailForRefresh'] as Map<String, dynamic>;
      final refresh = TwitcastingApi.refreshRoom(
        TwitcastingApi.streamServer(_sample('S05-stream-live').body),
        roomId: 'nabo66game',
        channel: 'nabo66game',
      );
      // title, nick, avatar, cover: empty, a follow keeps the stored ones
      // (3.x read the channel page again, 12-2).
      _expectParity(_projection(refresh), legacy, changed: {'title', 'nick', 'avatar', 'cover'});
      expect([refresh.title, refresh.nick, refresh.avatar, refresh.cover], everyElement(isEmpty));
      expect(refresh.startedAt, isNull);
      expect(refresh.restriction, isNull, reason: 'streamserver.php does not say');
      expect(refresh.danmakuData, isNull);
      expect((refresh.data! as TwitcastingRoomData).movieId, 841525457);
      final stored = detail('S04-page-live', 'S05-stream-live', 'nabo66game');
      final merged = stored.mergeFrom(refresh);
      _expectParity(_projection(merged), legacy, changed: {'title'}, reason: 'merged');
      expect(merged.title, stored.title);
      expect(merged.startedAt, stored.startedAt, reason: 'the same broadcast keeps its start time (M2.1)');
      final offline = TwitcastingApi.refreshRoom(
        TwitcastingApi.streamServer(_sample('S05-stream-offline').body),
        roomId: 'nabo66game',
        channel: 'nabo66game',
      );
      final ended = stored.mergeFrom(offline);
      expect(ended.effectiveLiveStatus, LiveStatus.offline);
      expect(ended.startedAt, isNull, reason: 'the state changed');
      expect(ended.restriction, isNull);
      expect(ended.nick, '山本');
    });

    test('an offline channel keeps none of the stale URLs of another broadcast (REG-TWITCASTING-001)', () {
      final room = detail('S04-page-offline', 'S05-stream-offline', 'twitcasting_jp');
      final legacy = _legacy('S04-page-offline');
      _expectParity(_projection(room), legacy['getRoomDetail'] as Map<String, dynamic>);
      final refresh = TwitcastingApi.refreshRoom(
        TwitcastingApi.streamServer(_sample('S05-stream-offline').body),
        roomId: 'twitcasting_jp',
        channel: 'twitcasting_jp',
      );
      _expectParity(
        _projection(refresh),
        legacy['getRoomDetailForRefresh'] as Map<String, dynamic>,
        changed: {'title', 'nick', 'avatar', 'cover'}, // 12-2
      );
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.startedAt, isNull);
      expect(room.restriction, isNull);
      expect(room.danmakuData, isNull);
      expect(room.title, startsWith('映画'), reason: 'no telop on the page: twitter:title, as 3.x');
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
      final requested = TwitcastingApi.channelPage(_roomHtml, roomId: 'Fixture_Artist', channel: 'fixture_artist').room;
      expect(requested.roomId, 'Fixture_Artist', reason: 'a follow keeps the id it was made with');
      expect(requested.userId, 'fixture_artist');
    });

    test('the title is the telop under the player title, without its hashtags; else twitter:title (12-1)', () {
      expect(_page(_livePage(telop: 'Tonight &amp; later')).title, 'Tonight & later');
      expect(_page(_livePage()).title, 'Drawing & music', reason: 'hashtags only: no telop');
      expect(_page(_livePage(telop: '<!-- x -->  ')).title, 'Drawing & music');
      final blank = _livePage().replaceFirst('content="Drawing &amp; music">', 'content="　">');
      expect(_page(blank).title, isEmpty, reason: 'no stand-in title (M2.1); twitter:description is not a title');
      final withProfile = _livePage().replaceFirst(
        '</head>',
        '<meta name="twitter:description" content="My profile"></head>',
      );
      expect(_page(withProfile).title, 'Drawing & music');
    });

    test('S04-page-live-tags: hashtags without a telop; twitter:description is the profile text', () {
      final page = TwitcastingApi.channelPage(
        _sample('S04-page-live-tags').body,
        roomId: 'c:gooniegoogoogaga',
        channel: 'c:gooniegoogoogaga',
      );
      final body = _sample('S04-page-live-tags').body;
      expect(body, contains('<meta name="twitter:description" content="Rock;Star">'));
      expect(body, contains('olivernorthCampaign!'));
      expect(page.room.title, 'Goo Goo GaGa', reason: 'twitter:title, not the profile text');
      expect(page.room.nick, isNotEmpty);
      final room = TwitcastingApi.roomDetail(page, TwitcastingApi.streamServer(_sample('S05-stream-live-tags').body));
      expect(room.isLiveNow, isTrue);
      expect(room.startedAt, DateTime.utc(2026, 9, 28, 17, 22, 20), reason: 'data-started-at 1790616140000');
      expect(room.startedAt!.isBefore(_sample('S04-page-live-tags').capturedAt), isTrue);
      expect((room.danmakuData! as TwitcastingDanmakuArgs).movieId, 841577030);
      expect(TwitcastingApi.qualities(room.data! as TwitcastingRoomData), isNotEmpty);
    });

    test('a secret word: a live room marked password-protected, not played (unified rule; 3.x NeedsLogin)', () {
      final page = _parsed('<html>Enter the secret word to access</html>');
      expect(page.secretWord, isTrue);
      expect([page.room.title, page.room.nick, page.room.avatar, page.room.cover], everyElement(isEmpty));
      expect(page.room.link, 'https://twitcasting.tv/fixture_artist');
      final room = TwitcastingApi.roomDetail(page, _stream(_liveStream()));
      expect((room.effectiveLiveStatus, room.restriction), (LiveStatus.live, LiveRestriction.password));
      final data = room.data! as TwitcastingRoomData;
      expect(data.secretWord, isTrue);
      expect(
        () => TwitcastingApi.qualities(data),
        throwsA(isA<StreamUnavailable>().having((error) => '$error', 'text', contains('password-protected'))),
      );
      final offline = TwitcastingApi.roomDetail(
        page,
        _stream({
          'movie': {'id': 42, 'live': false},
        }),
      );
      expect((offline.effectiveLiveStatus, offline.restriction), (LiveStatus.offline, null));
    });

    test('another creator or header is ApiChanged (3.x)', () {
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

    test('tiers are checked when played: no tier, a broken tc-hls or no valid URL is ApiChanged (3.x)', () {
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

    test('a bad tier URL only drops that tier (unified fault tolerance; 3.x rejected the answer)', () {
      final json = _liveStream();
      ((json['tc-hls']! as Map)['streams']! as Map)['high'] =
          'https://edge.twitcasting.tv/tc.livehls/v1/streams/999/hls/672.96/media.m3u8';
      final data = _stream(json);
      final qualities = TwitcastingApi.qualities(data);
      expect(qualities.map((quality) => (quality.id, quality.quality, quality.sort)), [
        ('medium', 'HLS medium', 3),
        ('low', 'HLS low', 2),
      ]);
      expect(
        () => TwitcastingApi.resolution(data, const LivePlayQuality(quality: 'HLS high', id: 'high')),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('a card known to be restricted is not played, with the reason', () {
      LiveRoom card(LiveRestriction? restriction) =>
          LiveRoom(roomId: 'a', platform: 'twitcasting', liveStatus: LiveStatus.live, restriction: restriction);
      expect(TwitcastingApi.restricted(card(null)), isNull);
      expect(TwitcastingApi.restricted(card(LiveRestriction.none)), isNull);
      for (final (restriction, reason) in [
        (LiveRestriction.private, 'private broadcast'),
        (LiveRestriction.password, 'password-protected'),
        (LiveRestriction.unplayable, 'unplayable'),
      ]) {
        expect(
          TwitcastingApi.restricted(card(restriction)),
          isA<StreamUnavailable>().having((error) => '$error', 'text', contains(reason)),
        );
      }
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
