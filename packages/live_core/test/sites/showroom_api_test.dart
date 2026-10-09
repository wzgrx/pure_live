// SHOWROOM parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/showroom/legacy_expected.dart from 3.x's ShowroomApi, ShowroomSite
// and ShowroomLink). Every intended difference is listed with its reason
// (`changed:`, with the upgrade row of docs/specs/UPGRADES.md); everything else
// must match. The M2.1 keys 3.x never wrote are checked apart (`added:`).
// The synthetic cases port 3.x's showroom_catalog_test.dart and pin 3.x's
// checks, as far as the upgrades kept them.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('showroom', name);

/// Keys 3.x never wrote (M2.1); [_expectParity] checks them apart.
const _v4Keys = ['startedAt', 'restriction'];

/// Asserts that [actual] (a `toJson`) equals 3.x's [legacy] map on every key
/// 3.x wrote, except [changed] (intended differences), and that the v4 keys
/// are exactly [added]. 3.x wrote null where the immutable model writes ''.
void _expectParity(
  Map<String, Object?> actual,
  Map<String, dynamic> legacy, {
  Set<String> changed = const {},
  Map<String, Object?> added = const {},
  String? reason,
}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (changed.contains(key)) continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
  for (final key in _v4Keys) {
    expect(actual[key], added[key], reason: '${reason ?? ''} $key (v4 key)');
  }
}

/// The live rows of S01 by room id, as answered.
final Map<String, Map<String, dynamic>> _rows = {
  for (final genre in (jsonDecode(_sample('S01-onlives').body) as Map<String, dynamic>)['onlives'] as List)
    for (final row in ((genre as Map<String, dynamic>)['lives'] as List).cast<Map<String, dynamic>>())
      if (row['room_id'] != null) '${row['room_id']}': row,
};

/// [seconds] since the epoch as `toJson` writes a start time.
String _iso(int seconds) => DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true).toIso8601String();

/// The v4 keys of the S01 card of [roomId]: the row's `started_at` and, for
/// its `premium_room_type` 0 (every S01 row), restriction none.
Map<String, Object?> _cardAdded(String roomId) {
  final row = _rows[roomId]!;
  expect(row['premium_room_type'], 0, reason: roomId);
  return {'startedAt': _iso(row['started_at'] as int), 'restriction': 'none'};
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
    // added: the row's start time and restriction (the unified rules).
    _expectParity(_projection(room), expected[index], added: _cardAdded(room.roomId), reason: '$reason[$index]');
  }
}

ShowroomSnapshot _snapshot() => ShowroomApi.snapshot(_sample('S01-onlives').body);

List<LiveRoom> _cards(Iterable<ShowroomLive> lives) => [for (final live in lives) ShowroomApi.card(live)];

const _mediaHeaders = {
  'referer': 'https://www.showroom-live.com/',
  'user-agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
};

/// 3.x's test live row (showroom_catalog_test.dart).
Map<String, Object?> _live(int roomId) => {
  'cell_type': 100,
  'room_id': roomId,
  'room_url_key': 'sample_$roomId',
  'main_name': 'Sample $roomId',
  'image': 'https://static.showroom-live.com/image/room/$roomId.png',
  'genre_id': 108,
  'follower_num': 516,
  'view_num': 78544,
  'telop': '',
  'started_at': 1790251202,
  'live_id': 23469535,
  'streaming_url_list': [
    {
      'is_default': true,
      'url': 'https://hls-css.live.showroom-live.com/live/$roomId.m3u8',
      'label': 'low quality',
      'type': 'hls',
      'id': 4,
      'quality': 100,
    },
  ],
};

/// 3.x's production shape (2026-09-25): a genre with nobody live carries a
/// message cell instead of an empty list.
const Map<String, Object?> _placeholder = {'cell_type': 7, 'message': 'Currently, there are no live performance.'};

String _onlives(List<Object?> lives, {Object genreId = 108, Object? genreName = 'Idol'}) => jsonEncode({
  'onlives': [
    {'genre_id': genreId, 'genre_name': genreName, 'lives': lives},
  ],
});

Map<String, Object?> _stream({
  Object? type = 'hls',
  Object? id = 2,
  Object? label = 'original quality',
  Object? quality = 1000,
  Object? url = 'https://shard902-cdn.showroom-txlive.com/live/x_ss.m3u8',
  Object? isDefault = false,
}) => {'type': type, 'id': id, 'label': label, 'quality': quality, 'url': url, 'is_default': isDefault};

Map<String, Object?> _profileBody() => jsonDecode(_sample('S03-profile-live').body) as Map<String, Object?>;

void main() {
  group('S01 snapshot', () {
    test('the catalog: one category SHOWROOM, every genre (empty ones too) in the site order, as 3.x', () {
      final categories = ShowroomApi.categories(_snapshot());
      final legacy = _maps(_result(_legacy('S01-onlives')['getCategores']));
      expect(categories.map((category) => (category.id, category.name)), [
        for (final category in legacy) (category['id'], category['name']),
      ]);
      final areas = _maps(legacy.single['children']);
      expect(categories.single.children, hasLength(areas.length));
      for (final (index, area) in categories.single.children.indexed) {
        // areaPic and shortName: 3.x wrote null, the model writes ''.
        _expectParity(area.toJson(), areas[index], reason: 'area $index');
      }
      expect(categories.single.children.map((area) => area.areaId), containsAllInOrder(['0', '758', '112', '110']));
    });

    test('every native directory page matches 3.x: 30 a page, Popularity for the recommendations', () {
      final snapshot = _snapshot();
      final pages = _legacy('S01-onlives')['getDirectoryPage'] as Map<String, dynamic>;
      var compared = 0;
      for (final MapEntry(:key, :value) in pages.entries) {
        final [genre, number] = key.split(':');
        final want = _result(value);
        if (want is! Map<String, dynamic> || !want.containsKey('rooms')) continue;
        final lives = genre == 'recommend' ? snapshot.popular : snapshot.genre(int.parse(genre))!;
        final page = ShowroomApi.directoryPage(lives, page: int.parse(number));
        expect((page.page, page.hasMore), (want['page'], want['hasMore']), reason: key);
        _expectRooms(page.rooms, want['rooms'], reason: key);
        compared++;
      }
      expect(compared, 4 + 18 * 2, reason: 'four recommendation pages and two pages of each of the 18 genres');
      expect(ShowroomApi.directoryPage(snapshot.popular, page: 3).rooms, hasLength(4), reason: '64 = 30 + 30 + 4');
    });

    test("3.x's slices of the recommendations and of a genre", () {
      final snapshot = _snapshot();
      final legacy = _legacy('S01-onlives');
      for (final MapEntry(:key, :value) in (legacy['getRecommendRooms'] as Map<String, dynamic>).entries) {
        final [_, page, _, size] = key.split(' ');
        final rooms = _cards(ShowroomApi.slice(snapshot.popular, page: int.parse(page), pageSize: int.parse(size)));
        _expectRooms(rooms, _result(value), reason: key);
      }
      for (final MapEntry(:key, :value) in (legacy['getCategoryRooms'] as Map<String, dynamic>).entries) {
        final [genre, _, page] = key.split(' ');
        final lives = snapshot.genre(int.parse(genre));
        final want = _result(value);
        if (want is Map) {
          // 3.x: ShowroomFailure.missing; the site reports NotFound.
          expect(want['message'], 'Showroom missing', reason: key);
          expect(lives, isNull, reason: key);
          continue;
        }
        _expectRooms(_cards(ShowroomApi.slice(lives!, page: int.parse(page), pageSize: 30)), want, reason: key);
      }
      expect(ShowroomApi.validSlice(page: 1, pageSize: 100), isTrue);
      for (final (page, size) in [(0, 30), (1, 0), (1, 101)]) {
        expect(ShowroomApi.validSlice(page: page, pageSize: size), isFalse);
        expect(ShowroomApi.slice([1, 2, 3], page: page, pageSize: size), isEmpty);
      }
    });

    test('search matches 3.x: id, key (case ignored), name, telop and the live genre name', () {
      final snapshot = _snapshot();
      final search = _legacy('S01-onlives')['searchRooms (pageSize 20)'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in search.entries) {
        if (key == 'blank' || key == 'link') continue;
        final keyword = key.substring(0, key.lastIndexOf(' page '));
        final page = int.parse(key.substring(key.lastIndexOf(' ') + 1));
        final rooms = _cards(ShowroomApi.slice(ShowroomApi.search(snapshot, keyword), page: page, pageSize: 20));
        _expectRooms(rooms, _result(value), reason: key);
      }
      expect(_maps(_result(search['link'])), isEmpty, reason: 'a link is a keyword like any other (3.x)');
      expect(ShowroomApi.search(snapshot, 'https://www.showroom-live.com/r/0c1c310117354'), isEmpty);
      expect(ShowroomApi.search(snapshot, '  '), isEmpty);
      expect(
        ShowroomApi.search(snapshot, '7779344804').single.roomId,
        386593,
        reason: 'an all-digit room key is found by its key',
      );
    });

    test('cards: telop or name as title, the square picture (else the other) as cover and avatar, media headers', () {
      final lives = _snapshot().popular;
      final king = ShowroomApi.card(lives.first);
      expect(king.title, '生誕！有難うございました🙇');
      expect(king.nick, startsWith('KING生誕祭'));
      expect(king.cover, contains('_square_s.png'));
      expect(king.avatar, king.cover);
      expect(king.link, 'https://www.showroom-live.com/r/0c1c310117354');
      expect(king.httpHeaders, _mediaHeaders);
      final withoutTelop = ShowroomApi.card(lives.firstWhere((live) => live.roomId == 373457));
      expect(withoutTelop.title, withoutTelop.nick);
      final withoutSquare = ShowroomApi.card(lives.firstWhere((live) => live.roomId == 238824));
      expect(withoutSquare.cover, endsWith('_s.jpeg?v=1790528827'));
    });

    test('view_num is total viewers, never an online count (REG-SHOWROOM-002)', () {
      for (final room in _cards(_snapshot().uniqueLives)) {
        expect(room.audienceMetricType, AudienceMetricType.totalViewers);
        expect(room.totalViewers, room.watching);
        expect(room.onlineViewers, isEmpty);
        expect(room.popularity, isEmpty);
      }
      final profile = ShowroomApi.profile(_sample('S03-profile-live').body, roomId: 577362);
      final room = ShowroomApi.room(profile, (live: true, restriction: null, danmaku: null));
      expect((room.totalViewers, room.onlineViewers), ('3941', ''));
    });

    test('Popularity falls back to every live once when the snapshot has no genre 0 (3.x)', () {
      final snapshot = ShowroomApi.snapshot(
        jsonEncode({
          'onlives': [
            {
              'genre_id': 112,
              'genre_name': 'Music',
              'lives': [_live(1), _live(2)],
            },
            {
              'genre_id': 102,
              'genre_name': 'Idol',
              'lives': [_live(2), _live(3)],
            },
          ],
        }),
      );
      expect(snapshot.popular.map((live) => live.roomId), [1, 2, 3]);
      expect(snapshot.genre(0), isNull);
    });
  });

  group("the snapshot's checks", () {
    test('a message cell is skipped instead of failing the snapshot (REG-SHOWROOM-001)', () {
      final snapshot = ShowroomApi.snapshot(
        jsonEncode({
          'onlives': [
            {
              'genre_id': 108,
              'genre_name': 'Idol',
              'lives': [_live(1001), _live(1002)],
            },
            {
              'genre_id': 758,
              'genre_name': 'Newcomer',
              'lives': [_placeholder],
            },
          ],
        }),
      );
      expect(snapshot.genres.map((genre) => genre.id), [108, 758]);
      expect(snapshot.genres.first.lives.map((live) => live.roomId), [1001, 1002]);
      expect(snapshot.genres.last.lives, isEmpty);
      final recorded = _snapshot();
      expect(recorded.genre(758), isEmpty, reason: 'S01: Newcomer is one message cell');
      expect(recorded.genre(110), isEmpty, reason: 'S01: Announcer is one message cell');
    });

    test('a malformed live row drops only itself; a snapshot of unreadable rows is still ApiChanged', () {
      // The unified rule on malformed rows: 3.x and M4.19 failed the whole
      // snapshot (3.x's showroom_catalog_test.dart fixed that).
      for (final (field, value) in [
        ('main_name', null),
        ('main_name', '  '),
        ('room_id', 0),
        ('room_id', 'x'),
        ('room_url_key', 'a b'),
        ('room_url_key', null),
        ('genre_id', -1),
        ('view_num', -3),
        ('follower_num', 'many'),
        ('telop', 7),
        ('genre_name', false),
      ]) {
        final row = _live(1003)..[field] = value;
        final snapshot = ShowroomApi.snapshot(_onlives([_live(1), row, _live(2), _placeholder]));
        expect(snapshot.genres.single.lives.map((live) => live.roomId), [1, 2], reason: '$field $value');
        expect(() => ShowroomApi.snapshot(_onlives([row])), throwsA(isA<ApiChanged>()), reason: '$field $value');
      }
      expect(ShowroomApi.snapshot(_onlives([_live(1), 'x'])).genres.single.lives.single.roomId, 1);
      expect(() => ShowroomApi.snapshot(_onlives(['x', 7])), throwsA(isA<ApiChanged>()));
      expect(
        ShowroomApi.snapshot(_onlives([_placeholder])).genres.single.lives,
        isEmpty,
        reason: 'message cells only: nobody is live, not a changed API',
      );
    });

    test('a malformed genre drops only itself; a snapshot without a genre is still ApiChanged', () {
      final good = {
        'genre_id': 112,
        'genre_name': 'Music',
        'lives': [_live(1)],
      };
      for (final bad in <Object?>[
        'x',
        {'genre_id': 'x', 'genre_name': 'A', 'lives': <Object?>[]},
        {'genre_id': 5, 'genre_name': '', 'lives': <Object?>[]},
        {'genre_id': 5, 'genre_name': 'A', 'lives': 'x'},
        {'genre_id': 5, 'genre_name': 'A', 'lives': List.generate(5001, (index) => _live(index + 1))},
      ]) {
        final snapshot = ShowroomApi.snapshot(
          jsonEncode({
            'onlives': [bad, good],
          }),
        );
        expect(snapshot.genres.map((genre) => genre.id), [112], reason: '$bad');
        expect(
          () => ShowroomApi.snapshot(
            jsonEncode({
              'onlives': [bad],
            }),
          ),
          throwsA(isA<ApiChanged>()),
          reason: '$bad',
        );
      }
      expect(() => ShowroomApi.snapshot(jsonEncode({'onlives': <Object?>[]})), throwsA(isA<ApiChanged>()));
      expect(() => ShowroomApi.snapshot(jsonEncode({'onlives': 'x'})), throwsA(isA<ApiChanged>()));
      expect(
        () => ShowroomApi.snapshot(jsonEncode({'onlives': List.generate(129, (_) => <String, Object?>{})})),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('cards: the start time of started_at and restriction none for premium_room_type 0 (unified rules)', () {
      final king = ShowroomApi.card(_snapshot().popular.first);
      expect(king.startedAt, DateTime.utc(2026, 9, 27, 13, 49, 2), reason: 'S01 started_at 1790516942');
      expect(king.restriction, LiveRestriction.none);
      expect(king.isLiveNow, isTrue);
      for (final (value, restriction) in [
        (0, LiveRestriction.none),
        ('0', LiveRestriction.none),
        (1, null),
        (2, null),
        (null, null),
        ('x', null),
      ]) {
        final live = ShowroomApi.snapshot(_onlives([_live(1)..['premium_room_type'] = value])).genres.single.lives;
        expect(ShowroomApi.card(live.single).restriction, restriction, reason: '$value');
      }
      for (final value in [0, -1, 946684799, 4102444801, '1790516942x', null, 1.5]) {
        final live = ShowroomApi.snapshot(_onlives([_live(1)..['started_at'] = value])).genres.single.lives;
        expect(ShowroomApi.card(live.single).startedAt, isNull, reason: '$value');
      }
      expect(ShowroomApi.startTime('1790516942'), DateTime.utc(2026, 9, 27, 13, 49, 2));
      expect(ShowroomApi.startTime(1790516942)!.isUtc, isTrue);
    });

    test('strings of digits count as numbers; optional counts may be missing or blank (3.x)', () {
      final row = _live(1)
        ..['room_id'] = '1'
        ..['view_num'] = ''
        ..['follower_num'] = null
        ..remove('telop');
      final live = ShowroomApi.snapshot(_onlives([row])).genres.single.lives.single;
      expect((live.roomId, live.views, live.followers, live.telop), (1, null, null, ''));
      final card = ShowroomApi.card(live);
      expect((card.watching, card.totalViewers, card.followers), ('', '', ''));
      expect(card.title, 'Sample 1');
    });

    test("the rows' own streams are not read: 3.x failed the whole snapshot on them but never used them", () {
      for (final streams in [
        null,
        'x',
        [_stream(url: 'http://shard902-cdn.showroom-txlive.com/live/x.m3u8')],
        [_stream(label: null)],
        [_stream(isDefault: 'yes')],
      ]) {
        final row = _live(1)..['streaming_url_list'] = streams;
        expect(ShowroomApi.snapshot(_onlives([row])).genres.single.lives.single.roomId, 1, reason: '$streams');
      }
    });

    test('a repeated genre is skipped (3.x)', () {
      final body = jsonEncode({
        'onlives': [
          {
            'genre_id': 1,
            'genre_name': 'A',
            'lives': [_live(1)],
          },
          {
            'genre_id': 1,
            'genre_name': 'B',
            'lives': [_live(2)],
          },
        ],
      });
      final genre = ShowroomApi.snapshot(body).genres.single;
      expect((genre.name, genre.lives.single.roomId), ('A', 1));
    });

    test('pictures: only https on a SHOWROOM host, as written; the square one wins even when rejected (3.x)', () {
      String cover(Map<String, Object?> row) =>
          ShowroomApi.snapshot(_onlives([_live(1)..addAll(row)])).genres.single.lives.single.cover;
      expect(
        cover({'image_square': 'https://static.showroom-live.com/a.png'}),
        'https://static.showroom-live.com/a.png',
      );
      expect(cover({'image_square': 'https://x.showroom-txlive.com/a.png'}), 'https://x.showroom-txlive.com/a.png');
      expect(cover({'image_square': 'http://static.showroom-live.com/a.png'}), '');
      expect(cover({'image_square': 'https://evilshowroom-live.com/a.png'}), '');
      expect(cover({'image_square': 'https://u@static.showroom-live.com/a.png'}), '');
      expect(cover({'image_square': '//static.showroom-live.com/a.png'}), '');
      expect(cover({}), 'https://static.showroom-live.com/image/room/1.png', reason: 'image when no square picture');
    });
  });

  group('S02/S03/S04 rooms', () {
    test('room/status gives the room id of a key; an unknown key is NotFound', () {
      final key = _sample('S02-status-key');
      expect(ShowroomApi.roomIdOfStatus(key.body, status: key.status), 577362);
      final legacy = (_legacy('S02-status-key')['resolveRoomId'] as Map<String, dynamic>)['0c1c310117354'];
      expect(_result(legacy), 577362);
      final missing = _sample('S02-status-notfound');
      expect(missing.status, 404);
      expect(() => ShowroomApi.roomIdOfStatus(missing.body, status: missing.status), throwsA(isA<NotFound>()));
      expect(() => ShowroomApi.roomIdOfStatus('{"room_id":0}'), throwsA(isA<ApiChanged>()));
    });

    test('room numbers: an integer above 0 (3.x); keys and anything else are not', () {
      expect(ShowroomApi.roomNumber('577362'), 577362);
      expect(ShowroomApi.roomNumber(' 577362 '), 577362);
      for (final text in ['0', '-5', '0c1c310117354', '48_Seina_Fukuoka', '', 'a b']) {
        expect(ShowroomApi.roomNumber(text), isNull, reason: text);
      }
    });

    for (final (sample, info, id, changed, added) in [
      // added: the start time (current_live_started_at) and restriction none
      // (premium_room_type 0) of a live room (the unified rules).
      (
        'S03-profile-live',
        'S04-live-info-live',
        '577362',
        const <String>{},
        {'startedAt': _iso(1790516942), 'restriction': 'none'},
      ),
      // changed: watching and totalViewers, 19-4 (an offline room shows no
      // audience; 3.x wrote the view_num of 0).
      (
        'S03-profile-offline',
        'S04-live-info-offline',
        '61576',
        const {'watching', 'totalViewers'},
        const <String, Object?>{},
      ),
    ]) {
      test('$sample with $info matches 3.x (entry, refresh and recording rooms)', () {
        final profile = ShowroomApi.profile(_sample(sample).body, roomId: int.parse(id));
        final state = ShowroomApi.liveInfo(_sample(info).body, roomId: int.parse(id));
        final room = ShowroomApi.room(profile, state);
        final legacy = _legacy(sample)[id] as Map<String, dynamic>;
        for (final entry in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
          final want = _result(legacy[entry])! as Map<String, dynamic>;
          _expectParity(_projection(room), want, changed: changed, added: added, reason: '$sample $entry');
          for (final key in changed) {
            expect((want[key], room.toJson()[key]), ('0', ''), reason: '$sample $entry $key');
          }
        }
        expect(_result(legacy['getLiveStatus']), state.live);
        expect(room.roomId, id);
        expect(room.httpHeaders, _mediaHeaders);
      });
    }

    test('live_info: a live room has its restriction and comment arguments; an offline one neither', () {
      final live = ShowroomApi.liveInfo(_sample('S04-live-info-live').body, roomId: 577362);
      expect((live.live, live.restriction), (true, LiveRestriction.none));
      final args = live.danmaku!;
      expect((args.roomId, args.host, args.key), ('577362', 'online.showroom-live.com', '6e6c686835796846:23483509'));
      expect('$args', isNot(contains(args.key)));
      final offline = ShowroomApi.liveInfo(_sample('S04-live-info-offline').body, roomId: 61576);
      expect(offline, (live: false, restriction: null, danmaku: null));
      final profile = ShowroomApi.profile(_sample('S03-profile-offline').body, roomId: 61576);
      final room = ShowroomApi.room(profile, offline);
      expect((room.title, room.area, room.followers), ('福岡 聖菜（AKB48）', 'idol', '24809'));
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.link, 'https://www.showroom-live.com/r/48_Seina_Fukuoka');
      expect(room.introduction, startsWith('おしゃべり好きなので'));
      expect(room.danmakuData, isNull, reason: 'the site adds the arguments on room entry');
    });

    test('19-4: an offline room has no audience, start time or restriction; followers stay', () {
      final body = _profileBody();
      final profile = ShowroomApi.profile(jsonEncode(body), roomId: 577362);
      expect(profile.liveStartedAt, DateTime.utc(2026, 9, 27, 13, 49, 2));
      final offline = ShowroomApi.room(profile, (live: false, restriction: null, danmaku: null));
      expect((offline.watching, offline.totalViewers, offline.onlineViewers), ('', '', ''));
      expect(offline.followers, '91');
      expect(offline.audienceMetricType, AudienceMetricType.totalViewers);
      expect((offline.startedAt, offline.restriction), (null, null));
      // An offline room's current_live_started_at is never used: S03 writes
      // 0, and the checks of 2026-09-28 found the scheduled start of a
      // coming broadcast there.
      final other = ShowroomApi.profile(_sample('S03-profile-offline').body, roomId: 61576);
      expect(other.liveStartedAt, isNull);
      final live = ShowroomApi.room(profile, (live: true, restriction: null, danmaku: null));
      expect((live.watching, live.totalViewers, live.startedAt), ('3941', '3941', profile.liveStartedAt));
      expect(live.restriction, isNull, reason: 'not known: premium_room_type other than 0');
      final missing = ShowroomApi.profile(jsonEncode({...body, 'current_live_started_at': 0}), roomId: 577362);
      expect(missing.liveStartedAt, isNull);
    });

    test('restrictions: premium_room_type 0 is none; anything else is not known (19-5 blocked)', () {
      String info(Object? premium) =>
          jsonEncode({...jsonDecode(_sample('S04-live-info-live').body) as Map, 'premium_room_type': premium});
      for (final (value, restriction) in [
        (0, LiveRestriction.none),
        (1, null),
        (3, null),
        (null, null),
        ('paid', null),
      ]) {
        expect(ShowroomApi.liveInfo(info(value), roomId: 577362).restriction, restriction, reason: '$value');
      }
      expect(ShowroomApi.restrictionOf('0'), LiveRestriction.none);
    });

    test('comment arguments: a host on showroom-live.com and a key without white space, else none', () {
      ShowroomDanmakuArgs? args(Object? host, Object? key) => ShowroomApi.danmakuArgs(roomId: 5, host: host, key: key);
      expect(args(' Online.SHOWROOM-live.com ', 'k:1')!.host, 'online.showroom-live.com');
      expect(args('showroom-live.com', 'k:1')!.key, 'k:1');
      for (final host in [
        null,
        '',
        7,
        'evilshowroom-live.com',
        'online.showroom-live.com.example',
        'online.showroom-live.com:8080',
        'wss://online.showroom-live.com',
        'online.showroom-live.com/x',
        'a..showroom-live.com',
      ]) {
        expect(args(host, 'k:1'), isNull, reason: '$host');
      }
      for (final key in [null, '', '  ', 5, 'a b', 'a\tb', 'a\nb', 'x' * 257]) {
        expect(args('online.showroom-live.com', key), isNull, reason: '$key');
      }
      String info(Map<String, Object?> change) =>
          jsonEncode({...jsonDecode(_sample('S04-live-info-live').body) as Map, ...change});
      expect(ShowroomApi.liveInfo(info({'bcsvr_host': 'evil.example.com'}), roomId: 577362).danmaku, isNull);
      expect(ShowroomApi.liveInfo(info({'bcsvr_key': ''}), roomId: 577362).danmaku, isNull);
      expect(
        ShowroomApi.liveInfo(info({'bcsvr_key': ''}), roomId: 577362).live,
        isTrue,
        reason: 'the room still opens',
      );
    });

    test("live_status: 2 is live, 0 and 1 offline, anything else ApiChanged; another room's answer is ApiChanged", () {
      String info(Object? status, {int room = 5}) => jsonEncode({'room_id': room, 'live_status': status});
      expect(ShowroomApi.liveInfo(info(2), roomId: 5).live, isTrue);
      expect(ShowroomApi.liveInfo(info('2'), roomId: 5).live, isTrue);
      expect(ShowroomApi.liveInfo(info(1), roomId: 5).live, isFalse);
      expect(ShowroomApi.liveInfo(info(0), roomId: 5).live, isFalse);
      for (final status in [3, -1, null, 'live']) {
        expect(() => ShowroomApi.liveInfo(info(status), roomId: 5), throwsA(isA<ApiChanged>()), reason: '$status');
      }
      expect(() => ShowroomApi.liveInfo(info(2, room: 6), roomId: 5), throwsA(isA<ApiChanged>()));
      final live = _sample('S04-live-info-live');
      expect(() => ShowroomApi.liveInfo(live.body, roomId: 61576), throwsA(isA<ApiChanged>()));
    });

    test("profile: 3.x's checks", () {
      final body = _profileBody();
      String edited(Map<String, Object?> change) => jsonEncode({...body, ...change});
      expect(() => ShowroomApi.profile(edited({}), roomId: 61576), throwsA(isA<ApiChanged>()), reason: 'other room');
      for (final (field, value) in [
        ('room_url_key', 'a/b'),
        ('room_url_key', null),
        ('is_onlive', 'true'),
        ('is_onlive', null),
        ('genre_id', null),
        ('view_num', -1),
        ('follower_num', 'x'),
        ('description', 5),
      ]) {
        expect(
          () => ShowroomApi.profile(edited({field: value}), roomId: 577362),
          throwsA(isA<ApiChanged>()),
          reason: '$field $value',
        );
      }
      final named = ShowroomApi.profile(edited({'main_name': null, 'room_name': 'Room'}), roomId: 577362);
      expect(named.name, 'Room', reason: 'room_name when there is no main_name (3.x)');
      expect(
        () => ShowroomApi.profile(edited({'main_name': null, 'room_name': null}), roomId: 577362),
        throwsA(isA<ApiChanged>()),
      );
      final missing = _sample('S03-profile-notfound');
      expect(() => ShowroomApi.profile(missing.body, roomId: 1, status: 404), throwsA(isA<NotFound>()));
      final legacy = _legacy('S03-profile-notfound')['1'] as Map<String, dynamic>;
      expect((_result(legacy['getRoomDetail'])! as Map)['message'], 'Showroom missing');
    });

    test("statuses: 3.x's mapping; the answer must be a JSON object", () {
      for (final (status, type) in [
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (500, isA<NetworkFailure>()),
        (503, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
        (204, isA<NetworkFailure>()),
        (400, isA<NetworkFailure>()),
      ]) {
        expect(() => ShowroomApi.roomIdOfStatus('{}', status: status), throwsA(type), reason: '$status');
      }
      expect(() => ShowroomApi.snapshot('<html>'), throwsA(isA<ApiChanged>()));
      expect(() => ShowroomApi.snapshot('[]'), throwsA(isA<ApiChanged>()));
      expect(() => ShowroomApi.streamRows('{"streaming_url_list": {}}'), throwsA(isA<ApiChanged>()));
      expect(
        () => ShowroomApi.streamRows(jsonEncode({'streaming_url_list': List.generate(65, (_) => _stream())})),
        throwsA(isA<ApiChanged>()),
      );
    });

    test("the external page is 3.x's profile link of a room id", () {
      final legacy = _legacy('S02-status-key')['ShowroomLink.roomUrl'] as Map<String, dynamic>;
      expect(ShowroomApi.roomUrl('577362'), legacy['577362']);
      expect(ShowroomApi.roomUrl('0c1c310117354'), isNull, reason: '3.x: FormatException');
    });
  });

  group('S05 streams', () {
    test('qualities, their URLs and the recovery match 3.x, except 自动 is last (19-2); WebRTC skipped', () {
      final rows = ShowroomApi.streamRows(_sample('S05-streaming-live').body);
      expect(rows, hasLength(8));
      final qualities = ShowroomApi.qualities(rows);
      final legacy = _legacy('S03-profile-live')['577362'] as Map<String, dynamic>;
      final want = _maps(_result(legacy['getPlayQualites']));
      // changed: order and the sort of 自动, 19-2 (原画 first and the default,
      // 自动 last; 3.x: 自动 first with sort 2000). Names, ids and URLs are
      // 3.x's, so stored preferences need no mapping.
      expect(want.first['quality'], '自动');
      expect(want.first['sort'], 2000);
      expect(
        [
          for (final quality in qualities)
            {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort, 'data': quality.data},
        ],
        [
          ...want.skip(1),
          {...want.first, 'sort': ShowroomApi.autoSort},
        ],
      );
      expect(qualities.map((quality) => quality.quality), ['原画', '中画质', '低画质', '自动']);
      final urls = legacy['getPlayUrls'] as Map<String, dynamic>;
      for (final quality in qualities) {
        final resolution = ShowroomApi.resolution(quality);
        expect(resolution.urls, _result(urls['${quality.id}']), reason: '${quality.id}');
        expect(resolution.appliedQualityData, quality.id, reason: '3.x confirmed the quality asked for');
        final line = resolution.lines.single;
        expect(line.headers, _mediaHeaders);
        expect(line.format, StreamFormat.hls);
        expect(line.lineId, 'shard902-cdn.showroom-txlive.com');
        expect(line.lease, isNull, reason: 'the URLs are neither signed nor expiring');
        expect(line.codec, isNull);
      }
      final recovery = _result(legacy['resolvePlayUrlsForRecoveryRaw(hls_all:100:0)'])! as Map<String, dynamic>;
      expect(ShowroomApi.resolution(qualities.last).urls, recovery['urls']);
      expect(recovery['appliedQualityData'], qualities.last.id);
    });

    test('an offline room has no stream: StreamUnavailable (3.x gave an empty quality list)', () {
      final rows = ShowroomApi.streamRows(_sample('S05-streaming-offline').body);
      expect(rows, isEmpty);
      expect(() => ShowroomApi.qualities(rows), throwsA(isA<StreamUnavailable>()));
      final legacy = _legacy('S03-profile-offline')['61576'] as Map<String, dynamic>;
      expect(_result(legacy['getPlayQualites']), isEmpty);
      expect(
        () => ShowroomApi.qualities([_stream(type: 'webrtc', url: 'webrtc://x.showroom-txlive.com/live/x')]),
        throwsA(isA<StreamUnavailable>()),
        reason: 'WebRTC only',
      );
    });

    test("labels and ranks: 3.x's thresholds; 自动 last (19-2)", () {
      final qualities = ShowroomApi.qualities([
        _stream(id: 1, quality: 150, url: 'https://a.showroom-txlive.com/150.m3u8'),
        _stream(quality: 200, url: 'https://a.showroom-txlive.com/200.m3u8'),
        _stream(id: 3, quality: 999, url: 'https://a.showroom-txlive.com/999.m3u8'),
        _stream(id: 4, quality: 1500, url: 'https://a.showroom-txlive.com/1500.m3u8'),
        _stream(type: 'hls_all', id: 5, quality: 0, url: 'https://a.showroom-txlive.com/abr.m3u8'),
        _stream(id: 6, quality: 200, url: 'https://a.showroom-txlive.com/200b.m3u8'),
      ]);
      expect(
        [for (final quality in qualities) '${quality.quality} ${quality.id} ${quality.sort}'],
        [
          '原画 hls:4:1500 1500',
          '中画质 hls:3:999 999',
          '中画质 hls:2:200 200',
          '中画质 hls:6:200 200',
          '低画质 hls:1:150 150',
          '自动 hls_all:5:0 -1',
        ],
      );
      final zero = ShowroomApi.qualities([
        _stream(type: 'hls_all', id: 5, quality: 0, url: 'https://a.showroom-txlive.com/abr.m3u8'),
        _stream(id: 1, quality: 0, url: 'https://a.showroom-txlive.com/0.m3u8'),
      ]);
      expect(zero.map((quality) => quality.quality), ['低画质', '自动'], reason: 'even below a tier of quality 0');
    });

    test('an irregular HLS row drops only its tier; HLS rows none of which can be read are ApiChanged', () {
      // The unified rule on bad addresses: 3.x failed every tier.
      for (final row in [
        _stream(url: 'http://a.showroom-txlive.com/x.m3u8'),
        _stream(url: 'https://a.example.com/x.m3u8'),
        _stream(url: 'https://evilshowroom-txlive.com/x.m3u8'),
        _stream(url: 'https://u@a.showroom-txlive.com/x.m3u8'),
        _stream(url: 'https://a.showroom-txlive.com/x.m3u8#f'),
        _stream(url: 'https://a.showroom-txlive.com/x y.m3u8'),
        _stream(url: null),
        _stream(label: ''),
        _stream(id: -1),
        _stream(quality: null),
        _stream(isDefault: 1),
        _stream(type: 5),
      ]) {
        final kept = ShowroomApi.qualities([_stream(url: 'https://a.showroom-txlive.com/first.m3u8'), row]);
        expect(kept.single.data, ['https://a.showroom-txlive.com/first.m3u8'], reason: '$row');
        expect(() => ShowroomApi.qualities([row]), throwsA(isA<ApiChanged>()), reason: '$row');
      }
      expect(() => ShowroomApi.qualities(['x']), throwsA(isA<ApiChanged>()));
      expect(ShowroomApi.qualities(['x', _stream()]).single.id, 'hls:2:1000');
      final repeated = ShowroomApi.qualities([_stream(), _stream(id: 9, label: null)]);
      expect(repeated.single.id, 'hls:2:1000');
      final second = ShowroomApi.qualities([_stream(id: 9, label: null), _stream()]);
      expect(second.single.id, 'hls:2:1000', reason: 'a broken row does not hide a good one with the same URL');
      final other = ShowroomApi.qualities([_stream(), _stream(type: 'dash', url: 'ftp://x')]);
      expect(other, hasLength(1), reason: 'other types are skipped before their URL is checked');
    });
  });

  group('S06 gift table (D07.7)', () {
    test('every gift of normal and enquete by id: name, point, free, picture', () {
      final sample = _sample('S06-gift-list');
      final catalog = ShowroomApi.giftList(sample.body);
      expect(catalog.length, 254);
      expect(
        catalog['3000421'],
        ShowroomGiftInfo(
          name: 'Twinkle star',
          point: 1,
          free: true,
          image: Uri.parse('https://static.showroom-live.com/image/gift/3000421_s.png?v=21'),
        ),
      );
      expect(
        [
          for (final id in ['3001833', '3001832', '3001577', '800094', '1601'])
            (catalog[id]!.name, catalog[id]!.point, catalog[id]!.free),
        ],
        [
          ('Cream soda(anime)', 500, false),
          ('Napolitan(anime)', 100, false),
          ('You got this!', 5, false),
          ('Twinkle Star (anime)', 2, false),
          ('RainbowStar', 100, true),
        ],
      );
      expect(catalog['10001']!.name, '1', reason: 'the vote gifts (enquete) are numbers');
      expect(ShowroomApi.giftListUrl(130997), sample.url);
    });

    test('rows that cannot be read are skipped; refusals throw as every answer does', () {
      final catalog = ShowroomApi.giftList(
        jsonEncode({
          'normal': [
            {'gift_id': 0, 'gift_name': 'zero'},
            {'gift_id': '7', 'gift_name': 'text id'},
            {'gift_id': 8, 'gift_name': ' 名前 ', 'point': -3, 'image': 'http://static.showroom-live.com/a.png'},
            {'gift_id': 9, 'image': 'https://example.com/a.png'},
            'row',
          ],
          'enquete': 'none',
        }),
      );
      expect(catalog.length, 2);
      expect(catalog['8'], const ShowroomGiftInfo(name: '名前', point: 0, free: false));
      expect(catalog['9'], const ShowroomGiftInfo(name: '', point: 0, free: false), reason: 'a picture off SHOWROOM');
      expect(ShowroomApi.giftList('{}').length, 0);
      expect(() => ShowroomApi.giftList('[]'), throwsA(isA<ApiChanged>()));
      expect(() => ShowroomApi.giftList('{}', status: 429), throwsA(isA<RateLimited>()));
    });
  });

  group('links', () {
    test("3.x's ShowroomLink.parse, except the site pages 3.x took for room keys", () {
      final legacy = _legacy('S02-status-key')['ShowroomLink.parse'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in legacy.entries) {
        final link = ShowroomApi.link(Uri.tryParse(key));
        final parsed = link?.roomId ?? link?.key;
        // `/onlive` (the directory page) and `/r`: 3.x read them as room keys
        // that room/status then did not know; they are site pages.
        if (key.endsWith('/onlive') || key.endsWith('/r')) {
          expect(value, isNotNull, reason: key);
          expect(parsed, isNull, reason: key);
          continue;
        }
        expect(parsed, value, reason: key);
      }
      expect(legacy, hasLength(20));
    });

    test('ids and keys', () {
      expect(ShowroomApi.link(Uri.parse('https://www.showroom-live.com/room/profile?room_id=61576')), (
        roomId: '61576',
        key: null,
      ));
      expect(ShowroomApi.link(Uri.parse('https://www.showroom-live.com/r/0c1c310117354?t=1')), (
        roomId: null,
        key: '0c1c310117354',
      ));
      expect(ShowroomApi.link(Uri.parse('https://www.showroom-live.com/48_Seina_Fukuoka')), (
        roomId: null,
        key: '48_Seina_Fukuoka',
      ));
      for (final page in ShowroomApi.reservedPaths) {
        expect(ShowroomApi.link(Uri.parse('https://www.showroom-live.com/$page')), isNull, reason: page);
        expect(ShowroomApi.link(Uri.parse('https://www.showroom-live.com/r/${page.toUpperCase()}')), isNull);
      }
      expect(ShowroomApi.link(null), isNull);
      expect(ShowroomApi.link(Uri.parse('https://www.showroom-live.com/r/%FF')), isNull, reason: 'not UTF-8');
    });
  });
}
