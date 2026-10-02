// Picarto parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json: 3.x's picarto adapter run verbatim over
// the same samples, docs/T02/T02c/T02c.3/record.md). Every intended difference
// is listed with its reason (an upgrade number of docs/specs/UPGRADES.md for the
// M4.U changes); everything else must match. The synthetic cases are 3.x's
// own (legacy test/picarto_adapter_test.dart and
// platform_response_lifecycle_test.dart), with its error kinds mapped to
// SiteErrors.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('picarto', name);

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

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

/// Cards against 3.x's: the same rooms in the same order, every field equal
/// except those [changed] names for a card.
void _expectRooms(
  List<LiveRoom> rooms,
  Object? legacy, {
  required String reason,
  Set<String> Function(Map<String, dynamic> legacy)? changed,
}) {
  final expected = (legacy! as List).cast<Map<String, dynamic>>();
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(
      room.toJson(),
      expected[index],
      changed: changed?.call(expected[index]) ?? const {},
      reason: '$reason[$index]',
    );
  }
}

/// X-2 (unified rule on placeholders): 3.x showed Picarto's default title;
/// it is left empty now.
Set<String> _placeholderTitle(Map<String, dynamic> legacy) =>
    legacy['title'] == PicartoApi.placeholderTitle ? const {'title'} : const {};

/// Qualities against 3.x's: label, id and playlist URLs; the order value
/// changed (11-4: the height first, then the bandwidth).
void _expectQualities(List<LivePlayQuality> qualities, Object? legacy) {
  final expected = (legacy! as List).cast<Map<String, dynamic>>();
  expect(qualities, hasLength(expected.length));
  for (final (index, quality) in qualities.indexed) {
    _expectParity(_quality(quality), expected[index], changed: const {'sort'}, reason: 'quality[$index]');
    final height = int.parse(RegExp(r'x(\d+)').firstMatch('${quality.id}')!.group(1)!);
    expect(quality.sort, height * PicartoApi.heightWeight + (expected[index]['sort'] as int), reason: '11-4');
  }
}

Map<String, Object?> _quality(LivePlayQuality quality) => {
  'quality': quality.quality,
  'id': quality.id,
  'sort': quality.sort,
  'data': quality.data,
};

// 3.x's synthetic answers (legacy test/picarto_adapter_test.dart).

const _masterText =
    '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=3661056,RESOLUTION=1280x720,FRAME-RATE=60,CODECS="avc1.640020,mp4a.40.2"\n'
    'variant.m3u8\n';
final Uri _masterUri = Uri.parse('https://edge1-eu-west.picarto.tv/stream/hls/golive+Artist/index.m3u8');

Map<String, dynamic> _channel({String name = 'Artist', bool online = true}) => {
  'id': 15237,
  'name': name,
  'title': 'Drawing',
  'online': online,
  'private': false,
  'adult': false,
  'viewers': 15,
  'total_views': 95434,
  'avatar': 'https://images.picarto.tv/avatar.jpg',
  'categories': [
    {'id': 10, 'name': 'Comic'},
  ],
};

Map<String, dynamic> _detail({String name = 'Artist', bool online = true, String origin = 'edge1-eu-west'}) => {
  'channel': _channel(name: name, online: online),
  'getLoadBalancerUrl': {'origin': origin},
  'getMultiStreams': {
    'streams': [
      {'channelId': 999, 'stream_name': 'golive+Other'},
      {'channelId': 15237, 'stream_name': 'golive+$name', 'thumbnail_image': 'https://thumb.picarto.tv/$name.jpg'},
    ],
  },
};

Map<String, dynamic> _directory({int page = 1, int count = 30, List<Object?>? rows}) => {
  'current_page': page,
  'last_page': 2,
  'per_page': count,
  'total': 40,
  'next_page_url': 'https://untrusted.example/ignored',
  'data': rows ?? [_channel()],
};

Map<String, dynamic> _profileSearch({List<Object?>? rows, int count = 2}) => {
  'searchProfiles': {
    'count': count,
    'data':
        rows ??
        [
          {
            'id': 15237,
            'name': 'Artist',
            'online': true,
            'follower_count': 915,
            'avatar': 'https://images.picarto.tv/a.jpg',
          },
          {'id': 24680, 'name': 'OfflineArtist', 'online': false, 'follower_count': 24, 'avatar': null},
        ],
  },
};

PicartoChannel _roomDetail(Object body, {String requestedId = 'Artist'}) =>
    PicartoApi.roomDetail(body is String ? body : jsonEncode(body), requestedId: requestedId);

void main() {
  group('S01 catalog', () {
    test('the categories 3.x listed, in answer order', () {
      final fixture = _sample('S01-categories');
      final areas = PicartoApi.categories(fixture.body, status: fixture.status);
      final legacy = (_legacy('S01-categories')['areas'] as List).cast<Map<String, dynamic>>();
      expect(areas.map((area) => area.areaId), legacy.map((area) => area['areaId']));
      for (final (index, area) in areas.indexed) {
        // 3.x wrote areaPic and shortName null, the model ''; 3.x reads both
        // the same.
        _expectParity(area.toJson(), legacy[index], reason: 'S01[$index]');
      }
      expect(areas, hasLength(26));
    });

    test("3.x's catalog: one category, the public directory first", () {
      final fixture = _sample('S01-categories');
      final catalog = PicartoApi.catalog(fixture.body, status: fixture.status);
      final legacy = ((_legacy('S01-categories')['getCategores'] as List).single as Map).cast<String, dynamic>();
      expect((catalog.id, catalog.name), (legacy['id'], legacy['name']));
      final children = (legacy['children'] as List).cast<Map<String, dynamic>>();
      expect(catalog.children, hasLength(children.length));
      for (final (index, area) in catalog.children.indexed) {
        _expectParity(area.toJson(), children[index], reason: 'catalog[$index]');
      }
      expect(catalog.children.first, PicartoApi.publicDirectory);
      expect(catalog.children.first.areaName, '公开直播（不含成人内容）', reason: "3.x's zh text");
    });

    test('official category metadata has stable ids and no invented audience (3.x)', () {
      final areas = PicartoApi.categories(
        jsonEncode({
          'categories': [
            {'id': 10, 'label': 'Comic', 'online_channels': 3},
            {'id': 33, 'label': 'Drawing', 'online_channels': 2},
          ],
          'languages': <Object>[],
          'video_categories': <Object>[],
        }),
      );
      expect(areas.map((area) => [area.platform, area.areaType, area.areaId, area.areaName]), [
        ['picarto', 'category', '10', 'Comic'],
        ['picarto', 'category', '33', 'Drawing'],
      ]);
    });

    test('malformed category metadata is surfaced rather than an empty catalog (3.x)', () {
      for (final data in [
        <String, dynamic>{},
        {'categories': <Object>[]},
        {
          'categories': [
            {'id': 10, 'label': ''},
          ],
        },
        {
          'categories': [
            {'id': 0, 'label': 'Zero'},
            'not an object',
          ],
        },
      ]) {
        expect(() => PicartoApi.categories(jsonEncode(data)), throwsA(isA<ApiChanged>()), reason: '$data');
      }
    });

    test('a bad or repeated category is left out, the others stay (11-3; 3.x failed the catalog)', () {
      final areas = PicartoApi.categories(
        jsonEncode({
          'categories': [
            {'id': 10, 'label': 'Comic'},
            {'id': 10, 'label': 'Comic again'},
            {'id': 11, 'label': ''},
            {'id': -1, 'label': 'Negative'},
            null,
            {'id': 33, 'label': 'Drawing'},
          ],
        }),
      );
      expect(areas.map((area) => (area.areaId, area.areaName)), [('10', 'Comic'), ('33', 'Drawing')]);
    });
  });

  group('S02 directory', () {
    for (final (name, page, more) in [
      ('S02-explore-p1', 1, true),
      ('S02-explore-last', 3, false),
      ('S02-explore-beyond', 4, false),
    ]) {
      test('$name: the channels 3.x listed, more pages while below last_page', () {
        final fixture = _sample(name);
        final legacy = _legacy(name);
        final result = PicartoApi.directoryPage(fixture.body, page: page, pageSize: 30, status: fixture.status);
        _expectRooms(result.rooms, legacy['rooms'], reason: name, changed: _placeholderTitle);
        expect((result.page, result.hasMore), (legacy['page'], legacy['hasMore']));
        expect(result.hasMore, more);
        expect(result.rooms.every((room) => room.isLiveNow), isTrue);
      });
    }

    test('S02 category: the Furry channels 3.x listed', () {
      final fixture = _sample('S02-explore-category');
      final legacy = _legacy('S02-explore-category');
      final result = PicartoApi.directoryPage(
        fixture.body,
        page: 1,
        pageSize: 30,
        categoryId: 8,
        status: fixture.status,
      );
      _expectRooms(result.rooms, legacy['rooms'], reason: 'category');
      expect(result.hasMore, isFalse);
    });

    test("Picarto's default title is a placeholder, left empty (X-2)", () {
      final rooms = PicartoApi.directoryPage(_sample('S02-explore-p1').body, page: 1, pageSize: 30).rooms;
      final legacy = (_legacy('S02-explore-p1')['rooms'] as List).cast<Map<String, dynamic>>();
      final placeholders = [
        for (final (index, room) in legacy.indexed)
          if (room['title'] == PicartoApi.placeholderTitle) rooms[index],
      ];
      expect(placeholders, hasLength(4), reason: '4 of 30 live channels never set a title');
      expect(placeholders.every((room) => room.title.isEmpty && room.nick.isNotEmpty), isTrue);
      expect(rooms.where((room) => room.title.isNotEmpty), hasLength(26));
    });

    test('list rows say nothing of private channels or start times: both unknown', () {
      final rooms = PicartoApi.directoryPage(_sample('S02-explore-p1').body, page: 1, pageSize: 30).rooms;
      expect(rooms.every((room) => room.restriction == null && room.startedAt == null), isTrue);
      final private = PicartoApi.directoryPage(
        jsonEncode(
          _directory(
            rows: [
              {..._channel(), 'private': true},
            ],
          ),
        ),
        page: 1,
        pageSize: 30,
      ).rooms.single;
      expect(private.restriction, LiveRestriction.private, reason: 'a row that says so is marked, not dropped');
      expect(private.isLiveNow, isTrue);
    });

    test('viewers are concurrent; a list row has no cumulative count', () {
      final rooms = PicartoApi.directoryPage(_sample('S02-explore-p1').body, page: 1, pageSize: 30).rooms;
      final raw = ((jsonDecode(_sample('S02-explore-p1').body) as Map)['data'] as List).cast<Map<String, dynamic>>();
      for (final (index, room) in rooms.indexed) {
        expect(room.onlineViewers, '${raw[index]['viewers']}');
        expect(room.watching, room.onlineViewers);
        expect(room.totalViewers, '');
        expect(room.effectiveAudienceMetricType, AudienceMetricType.onlineViewers);
      }
      final capability = AudiencePlatformCapability.of('picarto');
      expect(capability.hasTotalViewers, isTrue);
      expect(capability.hasPopularity, isFalse);
      expect(capability.onlineAvailability, AudienceOnlineAvailability.roomList);
    });

    test('a row with total_views has both counts, kept apart (3.x)', () {
      final room = PicartoApi.directoryPage(
        jsonEncode(_directory(page: 2, count: 10)),
        page: 2,
        pageSize: 10,
      ).rooms.single;
      expect(room.roomId, 'Artist');
      expect(room.userId, '15237');
      expect(room.onlineViewers, '15');
      expect(room.totalViewers, '95434');
      expect(room.area, 'Comic');
      expect(room.liveStatus, LiveStatus.live);
    });

    test('rows are one per name; adult and offline rows are left out (3.x)', () {
      final result = PicartoApi.directoryPage(
        jsonEncode(
          _directory(
            rows: [
              _channel(),
              _channel(),
              {..._channel(name: 'Adult'), 'adult': true},
              _channel(name: 'Offline', online: false),
            ],
          ),
        ),
        page: 1,
        pageSize: 30,
      );
      expect(result.rooms.map((room) => room.roomId), ['Artist']);
      expect(result.hasMore, isTrue, reason: 'page 1 of 2 whatever the row count');
    });

    test('schema drift, mismatched pages and overfull pages are not empty success (3.x)', () {
      for (final data in [
        <String, dynamic>{},
        {..._directory(), 'current_page': 2},
        {..._directory(), 'per_page': 10},
        {..._directory(), 'total': null},
        {..._directory(), 'data': <String, Object>{}},
        _directory(rows: List.generate(31, (_) => _channel())),
        _directory(
          rows: [
            {..._channel(), 'adult': null},
          ],
        ),
        _directory(
          rows: [
            {..._channel(), 'name': 'bad-name'},
          ],
        ),
        {..._directory(), 'current_page': 3, 'last_page': 2},
      ]) {
        expect(
          () => PicartoApi.directoryPage(jsonEncode(data), page: 1, pageSize: 30),
          throwsA(isA<ApiChanged>()),
          reason: jsonEncode(data),
        );
      }
      expect(
        () => PicartoApi.directoryPage(jsonEncode({..._directory(page: 3)}), page: 3, pageSize: 30),
        throwsA(isA<ApiChanged>()),
        reason: 'rows past the last page',
      );
    });

    test('a category page with only rows of another category is ApiChanged, not a false match (3.x)', () {
      expect(
        () => PicartoApi.directoryPage(jsonEncode(_directory()), page: 1, pageSize: 30, categoryId: 33),
        throwsA(isA<ApiChanged>()),
      );
      expect(PicartoApi.directoryPage(jsonEncode(_directory()), page: 1, pageSize: 30, categoryId: 10).rooms, [
        isA<LiveRoom>(),
      ]);
    });

    test('a bad row, or one of another category, is left out; the page stays (11-3; 3.x failed it)', () {
      final rows = [
        _channel(),
        {..._channel(name: 'NoAdultFlag'), 'adult': null},
        {..._channel(), 'name': 'bad-name'},
        {..._channel(name: 'NoId'), 'id': null},
        {..._channel(name: 'NoState'), 'online': 'yes'},
        'not an object',
        {
          ..._channel(name: 'Elsewhere'),
          'categories': [
            {'id': 33, 'name': 'Drawing'},
          ],
        },
        _channel(name: 'Second'),
      ];
      final page = PicartoApi.directoryPage(jsonEncode(_directory(rows: rows)), page: 1, pageSize: 30);
      expect(page.rooms.map((room) => room.roomId), ['Artist', 'Elsewhere', 'Second']);
      expect(page.hasMore, isTrue);
      final category = PicartoApi.directoryPage(
        jsonEncode(_directory(rows: rows)),
        page: 1,
        pageSize: 30,
        categoryId: 10,
      );
      expect(category.rooms.map((room) => room.roomId), [
        'Artist',
        'Second',
      ], reason: 'Elsewhere is not of category 10');
      // Page checks are not rows: they still fail the page.
      expect(
        () => PicartoApi.directoryPage(jsonEncode({..._directory(rows: rows), 'per_page': 10}), page: 1, pageSize: 30),
        throwsA(isA<ApiChanged>()),
      );
    });
  });

  group('S03 search', () {
    test('profiles 3.x found, live and offline, with followers and no audience', () {
      final fixture = _sample('S03-search');
      final rooms = PicartoApi.searchRooms(fixture.body, pageSize: 20, status: fixture.status);
      // title: the channel name (11-5; 3.x had none).
      _expectRooms(rooms, _legacy('S03-search')['rooms'], reason: 'S03', changed: (_) => const {'title'});
      expect(rooms.where((room) => room.isLiveNow), hasLength(15));
      expect(rooms.where((room) => room.isExplicitlyOfflineNow), hasLength(5));
      expect(rooms.every((room) => room.onlineViewers.isEmpty && room.cover.isEmpty), isTrue);
      expect(rooms.every((room) => room.restriction == null && room.startedAt == null), isTrue);
    });

    test('a card is titled with the channel name and introduced with the bio (11-5)', () {
      final fixture = _sample('S03-search');
      final rooms = PicartoApi.searchRooms(fixture.body, pageSize: 20, status: fixture.status);
      final profiles = (((jsonDecode(fixture.body) as Map)['searchProfiles'] as Map)['data'] as List)
          .cast<Map<String, dynamic>>();
      for (final (index, room) in rooms.indexed) {
        expect(room.title, room.nick);
        expect(room.title, profiles[index]['name']);
        final bio = (profiles[index]['bio'] as String).trim();
        expect(room.introduction, bio.isEmpty ? isNull : bio, reason: room.roomId);
      }
      expect(rooms.where((room) => room.introduction != null), hasLength(8), reason: '8 of 20 profiles have a bio');
      expect(rooms.firstWhere((room) => room.roomId == 'ShiverCritter').introduction, startsWith('K / Shiver'));
      final decoded = PicartoApi.searchRooms(
        jsonEncode(
          _profileSearch(
            rows: [
              {'id': 1, 'name': 'Artist', 'online': false, 'bio': '  Comics &amp; more &lt;3\n'},
            ],
          ),
        ),
        pageSize: 20,
      ).single;
      expect(decoded.introduction, 'Comics & more <3', reason: 'entities decoded, as the detail panels');
    });

    test('an empty page ends the results; count is not read (REG-PICARTO-002)', () {
      final fixture = _sample('S03-search-empty');
      expect(PicartoApi.searchRooms(fixture.body, pageSize: 20, status: fixture.status), isEmpty);
      expect(_legacy('S03-search-empty')['rooms'], isEmpty);
      // `count` on the first page of S03 is the site total, not this page's.
      final count = ((jsonDecode(_sample('S03-search').body) as Map)['searchProfiles'] as Map)['count'];
      expect(count, greaterThan(20));
    });

    test('offline identities without an invented audience (3.x)', () {
      final rooms = PicartoApi.searchRooms(jsonEncode(_profileSearch(count: 0)), pageSize: 20);
      expect(rooms.map((room) => room.roomId), ['Artist', 'OfflineArtist']);
      expect(rooms.first.isLiveNow, isTrue);
      expect(rooms.last.isExplicitlyOfflineNow, isTrue);
      expect(rooms.first.followers, '915');
      expect(rooms.first.onlineViewers, isEmpty);
      expect(rooms.first.watching, isEmpty);
      expect(rooms.first.audienceMetricType, AudienceMetricType.unknown);
      expect(rooms.last.link, 'https://picarto.tv/OfflineArtist');
      expect(rooms.last.avatar, '');
    });

    test('a bad profile is left out, the page stays (11-3; 3.x failed it)', () {
      final rooms = PicartoApi.searchRooms(
        jsonEncode(
          _profileSearch(
            rows: [
              {'id': 1, 'name': 'Artist', 'online': true},
              {'id': 2, 'name': 'NoState', 'online': null},
              {'id': 3, 'name': 'Negative', 'online': true, 'follower_count': -1},
              {'id': 4, 'name': 'explore', 'online': true},
              {'id': null, 'name': 'NoId', 'online': true},
              {'id': 6, 'name': 'Offline', 'online': false},
            ],
          ),
        ),
        pageSize: 20,
      );
      expect(rooms.map((room) => room.roomId), ['Artist', 'Offline']);
    });

    test('a page without a usable profile fails (3.x)', () {
      for (final body in [
        <String, dynamic>{},
        {
          'searchProfiles': {'data': <String, Object>{}},
        },
        _profileSearch(
          rows: [
            {'id': 1, 'name': 'Artist', 'online': null},
          ],
        ),
        _profileSearch(
          rows: [
            {'id': 1, 'name': 'Artist', 'online': true, 'follower_count': -1},
          ],
        ),
        _profileSearch(
          rows: [
            {'id': 1, 'name': 'explore', 'online': true},
          ],
        ),
      ]) {
        expect(() => PicartoApi.searchRooms(jsonEncode(body), pageSize: 20), throwsA(isA<ApiChanged>()));
      }
      expect(
        () => PicartoApi.searchRooms(jsonEncode(_profileSearch()), pageSize: 1),
        throwsA(isA<ApiChanged>()),
        reason: 'more rows than asked for',
      );
    });
  });

  group('S04 room', () {
    test('live: the room 3.x built, with the master of its own multistream entry (REG-PICARTO-001)', () {
      final fixture = _sample('S04-detail-live');
      final legacy = _legacy('S04-detail-live');
      final channel = PicartoApi.roomDetail(fixture.body, requestedId: 'allatir', status: fixture.status);
      // followers: followers_count, which 3.x did not read; introduction
      // (not in 3.x's output) is checked below.
      for (final depth in ['getRoomDetailForRefresh', 'getRoomDetail', 'getRoomDetailForRecording']) {
        _expectParity(
          channel.room.toJson(),
          legacy[depth] as Map<String, dynamic>,
          changed: {'followers'},
          reason: depth,
        );
      }
      expect(channel.room.followers, '653');
      expect(channel.room.cover, 'https://thumb-eu-west1.picarto.tv/thumbnail/allatir.jpg', reason: 'own stream');
      expect(channel.room.onlineViewers, '52');
      expect(channel.room.totalViewers, '61071');
      expect(channel.master, Uri.parse((_legacy('S05-master')['request'] as Map)['url'] as String));
      expect(legacy['roomEntryRequests'], [
        'https://ptvintern.picarto.tv/api/channel/detail/allatir',
        channel.master.toString(),
      ]);
      expect((channel.name, channel.channelId), ('allatir', 942670));
      final streams = ((jsonDecode(fixture.body) as Map)['getMultiStreams'] as Map)['streams'] as List;
      expect(streams, hasLength(4), reason: 'a multistream group of four; the own stream is the last');
      // The unified rules: the answer says whether the channel is private
      // (it is not), and nothing of the broadcast's start.
      expect(channel.room.restriction, LiveRestriction.none);
      expect(channel.room.startedAt, isNull);
    });

    test('the description panels are the introduction, entities decoded (3.x had none)', () {
      final channel = PicartoApi.roomDetail(_sample('S04-detail-live').body, requestedId: 'allatir');
      final introduction = channel.room.introduction!;
      expect(introduction, startsWith("Hi!\nI'm Allatir"));
      expect(introduction, contains('ART here! <3'));
      expect(introduction, contains('\n\nYOU CAN SUPPORT AND DONATE ME HERE!'));
      expect(_roomDetail(_detail()).room.introduction, isNull);
    });

    test('offline: the room 3.x built, no master', () {
      final fixture = _sample('S04-detail-offline');
      final legacy = _legacy('S04-detail-offline');
      final channel = PicartoApi.roomDetail(fixture.body, requestedId: 'Kaiyote', status: fixture.status);
      for (final depth in ['getRoomDetailForRefresh', 'getRoomDetail', 'getRoomDetailForRecording']) {
        // cover: the last broadcast's thumbnail (11-6); title: Picarto's
        // default title is a placeholder (X-2).
        _expectParity(
          channel.room.toJson(),
          legacy[depth] as Map<String, dynamic>,
          changed: {'followers', 'cover', 'title'},
          reason: depth,
        );
      }
      expect(channel.master, isNull);
      expect(channel.room.effectiveLiveStatus, LiveStatus.offline);
      expect(channel.room.restriction, LiveRestriction.none);
      expect(channel.room.title, '', reason: 'X-2');
      expect((_legacy('S04-detail-offline')['getRoomDetail'] as Map)['title'], PicartoApi.placeholderTitle);
      expect((channel.room.onlineViewers, channel.room.totalViewers), ('0', '18'));
      expect(legacy['getPlayQualites'], isEmpty);
      expect(legacy['roomEntryRequests'], hasLength(1), reason: 'no master for an offline channel');
    });

    test("the platform's spelling is the room id whatever the spelling asked for, as in 3.x", () {
      // 3.x's follows were stored under the platform's spelling: a room
      // opened from a lower-case link must be the followed one.
      for (final (name, requested) in [
        ('S04-detail-offline', 'kaiyote'),
        ('S04-detail-offline', 'KAIYOTE'),
        ('S04-detail-live', 'ALLATIR'),
      ]) {
        final channel = PicartoApi.roomDetail(_sample(name).body, requestedId: requested);
        final legacy = _legacy(name);
        for (final depth in ['getRoomDetailForRefresh', 'getRoomDetail', 'getRoomDetailForRecording']) {
          _expectParity(
            channel.room.toJson(),
            legacy[depth] as Map<String, dynamic>,
            // Offline: cover 11-6, placeholder title X-2 (see above).
            changed: {
              'followers',
              if (name == 'S04-detail-offline') ...{'cover', 'title'},
            },
            reason: '$requested $depth',
          );
        }
        expect(channel.room.roomId, (legacy['getRoomDetail'] as Map)['roomId'], reason: requested);
        expect(channel.room.roomId, isNot(requested));
        expect(channel.name, channel.room.roomId);
        expect(channel.requestedId, requested);
      }
      expect(() => _roomDetail(_detail(name: 'Other')), throwsA(isA<ApiChanged>()), reason: 'another channel');
    });

    test('channel: null is NotFound (3.x: a schema error)', () {
      final fixture = _sample('S04-detail-notfound');
      expect(
        () => PicartoApi.roomDetail(fixture.body, requestedId: 'zxqvnochannelfixture', status: fixture.status),
        throwsA(isA<NotFound>()),
      );
      for (final depth in ['getRoomDetailForRefresh', 'getRoomDetail', 'getRoomDetailForRecording']) {
        expect(_legacy('S04-detail-notfound')[depth], {'throws': 'Picarto schema'});
      }
      expect(() => _roomDetail(<String, Object>{}), throwsA(isA<ApiChanged>()), reason: 'no channel key at all');
    });

    test('the multistream entry of the channel id is the stream; the cover is its thumbnail (3.x)', () {
      final channel = _roomDetail(_detail(), requestedId: 'artist');
      expect(channel.master, _masterUri);
      expect(channel.room.cover, 'https://thumb.picarto.tv/Artist.jpg');
      expect(channel.room.roomId, 'Artist');
      final noThumbnail = _roomDetail({
        ..._detail(),
        'channel': {..._channel(), 'image_thumbnail': 'https://thumb.picarto.tv/channel.jpg'},
        'getMultiStreams': {
          'streams': [
            {'channelId': 15237, 'stream_name': 'golive+Artist'},
          ],
        },
      });
      expect(noThumbnail.room.cover, 'https://thumb.picarto.tv/channel.jpg', reason: "the channel's is the fallback");
    });

    test('an offline channel needs no load balancer (3.x)', () {
      final channel = _roomDetail({'channel': _channel(online: false)});
      expect(channel.room.isExplicitlyOfflineNow, isTrue);
      expect(channel.master, isNull);
      expect(channel.room.cover, '', reason: 'no stream entry, no channel thumbnail');
    });

    test("offline, the cover is the last broadcast's thumbnail (11-6; 3.x had none)", () {
      final fixture = _sample('S04-detail-offline');
      final channel = PicartoApi.roomDetail(fixture.body, requestedId: 'Kaiyote');
      final streams = ((jsonDecode(fixture.body) as Map)['getMultiStreams'] as Map)['streams'] as List;
      expect(channel.room.cover, (streams.single as Map)['thumbnail_image']);
      expect(channel.room.cover, 'https://thumb.picarto.tv/thumbnail/Kaiyote.jpg');
      expect((_legacy('S04-detail-offline')['getRoomDetail'] as Map)['cover'], '');
      final offline = {
        ..._detail(online: false),
        'getMultiStreams': {
          'streams': [
            {'channelId': 999, 'stream_name': 'golive+Other', 'thumbnail_image': 'https://thumb.picarto.tv/o.jpg'},
            {'channelId': 15237, 'stream_name': 'golive+Artist', 'thumbnail_image': 'https://thumb.picarto.tv/a.jpg'},
          ],
        },
      };
      expect(_roomDetail(offline).room.cover, 'https://thumb.picarto.tv/a.jpg', reason: 'its own entry');
      expect(
        _roomDetail({
          ...offline,
          'channel': {..._channel(online: false), 'image_thumbnail': 'https://thumb.picarto.tv/channel.jpg'},
          'getMultiStreams': {'streams': 'broken'},
        }).room.cover,
        'https://thumb.picarto.tv/channel.jpg',
        reason: "without its entry the channel's thumbnail, and no failure offline",
      );
    });

    test('a private channel is shown, live or offline, marked private and without a stream (11-9)', () {
      for (final online in [true, false]) {
        final channel = _roomDetail({
          ..._detail(online: online),
          'channel': {..._channel(online: online), 'private': true},
        });
        expect(channel.room.restriction, LiveRestriction.private, reason: 'online $online');
        expect(channel.room.isLiveNow, online, reason: 'a private broadcast is live (3.x: access denied)');
        expect(channel.room.followGroup, online ? FollowGroup.live : FollowGroup.offline);
        expect(channel.master, isNull, reason: 'it needs the private key; not asked for');
        expect((channel.room.roomId, channel.room.title), ('Artist', 'Drawing'));
      }
      // Its stream fields are not needed, so their absence is no error.
      final bare = _roomDetail({
        'channel': {..._channel(), 'private': true},
      });
      expect((bare.room.isLiveNow, bare.room.restriction, bare.master), (true, LiveRestriction.private, null));
      expect(_roomDetail(_detail()).room.restriction, LiveRestriction.none);
    });

    test('adult channels are not restricted: they play without an account', () {
      final channel = _roomDetail({
        ..._detail(),
        'channel': {..._channel(), 'adult': true},
      });
      expect(channel.room.restriction, LiveRestriction.none);
      expect(channel.master, _masterUri);
    });

    test('the follow refresh does not check the stream fields (11-2; 3.x failed it)', () {
      for (final data in [
        {..._detail(), 'getLoadBalancerUrl': null},
        {
          ..._detail(),
          'getMultiStreams': {'streams': <Object>[]},
        },
        _detail(origin: 'edge.evil'),
        {
          ..._detail(),
          'getMultiStreams': {
            'streams': [
              {'channelId': 15237, 'stream_name': 'golive+Artist'},
              {'channelId': 15237, 'stream_name': 'golive+Artist2'},
            ],
          },
        },
      ]) {
        expect(() => _roomDetail(data), throwsA(isA<ApiChanged>()), reason: 'room entry: ${jsonEncode(data)}');
        final refreshed = PicartoApi.roomDetail(jsonEncode(data), requestedId: 'Artist', stream: false);
        expect(refreshed.master, isNull);
        expect(refreshed.room.isLiveNow, isTrue);
        expect((refreshed.room.title, refreshed.room.onlineViewers), ('Drawing', '15'));
      }
      // The same room as room entry when the fields are there.
      final fixture = _sample('S04-detail-live');
      final entered = PicartoApi.roomDetail(fixture.body, requestedId: 'allatir');
      final refreshed = PicartoApi.roomDetail(fixture.body, requestedId: 'allatir', stream: false);
      expect(refreshed.room.toJson(), entered.room.toJson());
      expect(refreshed.master, isNull);
      // The channel itself is still checked.
      expect(
        () => PicartoApi.roomDetail(jsonEncode(_detail(name: 'Other')), requestedId: 'Artist', stream: false),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('missing identity, ambiguous state, missing stream and origin injection stay errors (3.x)', () {
      for (final data in [
        <String, dynamic>{'channel': <String, Object>{}},
        {
          ..._detail(),
          'channel': {..._channel(), 'online': null},
        },
        _detail(name: 'Other'),
        {
          ..._detail(),
          'channel': {..._channel(), 'private': null},
        },
        {..._detail(), 'getLoadBalancerUrl': null},
        {
          ..._detail(),
          'getMultiStreams': {'streams': <Object>[]},
        },
        _detail(origin: 'edge/../../other'),
        _detail(origin: 'edge.evil'),
        {
          ..._detail(),
          'getMultiStreams': {
            'streams': [
              {'channelId': 15237, 'stream_name': '../secret'},
            ],
          },
        },
        {
          ..._detail(),
          'getMultiStreams': {
            'streams': [
              {'channelId': 15237, 'stream_name': 'golive+Artist'},
              {'channelId': 15237, 'stream_name': 'golive+Artist2'},
            ],
          },
        },
      ]) {
        expect(() => _roomDetail(data), throwsA(isA<ApiChanged>()), reason: jsonEncode(data));
      }
    });

    for (final (status, kind) in [
      (401, isA<RiskControl>()),
      (403, isA<RiskControl>()),
      (404, isA<NotFound>()),
      (429, isA<RateLimited>()),
      (503, isA<NetworkFailure>()),
      (302, isA<NetworkFailure>()),
      (400, isA<NetworkFailure>()),
    ]) {
      test('HTTP $status is a typed error, never an offline card or the leaked body (3.x)', () {
        expect(
          () => PicartoApi.roomDetail('secret-cookie', requestedId: 'Artist', status: status),
          throwsA(kind.having((error) => '$error', 'text', isNot(contains('secret-cookie')))),
        );
      });
    }

    test('answers over 1 MiB of UTF-8 are ApiChanged, however short in characters (3.x)', () {
      final wide = jsonEncode({'fixture': '中' * 360000});
      expect(wide.length, lessThan(PicartoApi.responseLimit));
      expect(() => _roomDetail(wide), throwsA(isA<ApiChanged>()));
      expect(() => PicartoApi.categories('x' * (PicartoApi.responseLimit + 1)), throwsA(isA<ApiChanged>()));
      expect(() => PicartoApi.categories('not json'), throwsA(isA<ApiChanged>()));
    });

    test('danmaku arguments: the channel name as the platform writes it and the channel id', () {
      final args = PicartoApi.danmakuArgs(
        PicartoApi.roomDetail(_sample('S04-detail-live').body, requestedId: 'ALLATIR'),
      );
      expect((args.channelName, args.channelId), ('allatir', 942670));
      // The JWT request the chat needs (M5) was recorded with this name.
      expect((jsonDecode((_sample('S06-chat-token').meta['request'] as Map)['body'] as String) as Map)['variables'], {
        'name': 'allatir',
      });
    });
  });

  group('S05 qualities', () {
    test("the master's qualities as 3.x parsed them", () {
      final fixture = _sample('S05-master');
      final qualities = PicartoApi.qualities(fixture.body, master: fixture.url, status: fixture.status);
      _expectQualities(qualities, _legacy('S05-master')['qualities']);
      _expectQualities(qualities, _legacy('S04-detail-live')['getPlayQualites']);
      expect(qualities.single.quality, '720p 60fps');
    });

    test('quoted attributes and a relative URI with the declared resolution and fps (3.x)', () {
      final quality = PicartoApi.qualities(_masterText, master: _masterUri).single;
      expect(quality.quality, '720p 60fps');
      expect(quality.data, [_masterUri.resolve('variant.m3u8').toString()]);
      expect(quality.sort, 720 * PicartoApi.heightWeight + 3661056, reason: '11-4; 3.x: the bandwidth alone');
      expect(quality.selectionId.toString(), contains('avc1.640020,mp4a.40.2'));
    });

    test('the id survives bandwidth and edge renewal; one profile groups its URLs (3.x)', () {
      final one = PicartoApi.qualities(_masterText, master: _masterUri).single;
      final renewed = PicartoApi.qualities(
        _masterText.replaceAll('3661056', '4000000'),
        master: Uri.parse('https://edge2.picarto.tv/new/master.m3u8'),
      ).single;
      expect(renewed.selectionId, one.selectionId);
      expect(renewed.data, ['https://edge2.picarto.tv/new/variant.m3u8']);
      final multiple = PicartoApi.qualities(
        '$_masterText${_masterText.substring(8).replaceAll('variant.m3u8', 'other.m3u8')}\n',
        master: _masterUri,
      );
      expect(multiple, hasLength(1));
      expect(multiple.single.data, hasLength(2));
    });

    test('separate audio keeps the master instead of silently dropping the sound (3.x)', () {
      final qualities = PicartoApi.qualities(
        '#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",URI="audio.m3u8"\n${_masterText.substring(8)}',
        master: _masterUri,
      );
      expect(qualities.single.quality, '自动', reason: '11-4; 3.x: HLS Auto');
      expect(qualities.single.id, PicartoApi.autoQualityId, reason: "3.x's id");
      expect(PicartoApi.autoQualityId, 'master');
      expect(qualities.single.data, [_masterUri.toString()]);
    });

    test('HTML, empty, dangling variants, invalid numbers and non-HTTP URIs are ApiChanged (3.x)', () {
      for (final raw in [
        '',
        '<html>error</html>',
        '#EXTM3U',
        '#EXTM3Ugarbage\n$_masterText',
        '#EXTM3U\n#EXTINF:2,\n',
        _masterText.replaceAll('variant.m3u8', ''),
        _masterText.replaceAll('3661056', '0'),
        _masterText.replaceAll('60,CODECS', 'NaN,CODECS'),
        _masterText.replaceAll('1280x720', 'abc'),
        _masterText.replaceAll('variant.m3u8', 'file:///secret'),
        _masterText.replaceAll('variant.m3u8', 'https://user@host/media.m3u8'),
      ]) {
        expect(() => PicartoApi.qualities(raw, master: _masterUri), throwsA(isA<ApiChanged>()), reason: raw);
      }
    });

    test('a media playlist is one auto source; profiles without a resolution stay apart (3.x)', () {
      final auto = PicartoApi.qualities(
        '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\nchunk.ts\n',
        master: _masterUri,
      ).single;
      expect(auto.data, [_masterUri.toString()]);
      expect((auto.id, auto.quality), (PicartoApi.autoQualityId, '自动'));
      final noResolution = _masterText.replaceAll('RESOLUTION=1280x720,', '');
      final two = PicartoApi.qualities(
        '$noResolution${noResolution.substring(8).replaceAll('3661056', '1000000')}',
        master: _masterUri,
      );
      expect(two.map((quality) => quality.quality), ['HLS 3.7 Mbps', 'HLS 1.0 Mbps']);
    });

    test('the tallest first, then the highest bandwidth (11-4; 3.x: the bandwidth alone)', () {
      final qualities = PicartoApi.qualities(
        '#EXTM3U\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=854x480,FRAME-RATE=30\nlow.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1280x720,FRAME-RATE=60\nfast.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080,FRAME-RATE=30\ntall.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=7000000,RESOLUTION=1280x720,FRAME-RATE=30,CODECS="hvc1.1.6.L120"\nhevc.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=9000000\nnosize.m3u8\n',
        master: _masterUri,
      );
      // 3.x put 720p above 1080p here (6 Mbps > 4 Mbps).
      expect(qualities.map((quality) => quality.quality), [
        '1080p 30fps',
        '720p 30fps',
        '720p 60fps',
        '480p 30fps',
        'HLS 9.0 Mbps',
      ]);
      expect(qualities.map((quality) => quality.sort), [
        1080 * PicartoApi.heightWeight + 4000000,
        720 * PicartoApi.heightWeight + 7000000,
        720 * PicartoApi.heightWeight + 6000000,
        480 * PicartoApi.heightWeight + 1000000,
        9000000,
      ]);
      final sorted = [...qualities]..sort((a, b) => b.sort.compareTo(a.sort));
      expect(sorted, qualities, reason: 'sort gives the same order');
    });

    test('a master that is gone is StreamUnavailable; other statuses as the API', () {
      expect(() => PicartoApi.qualities('', master: _masterUri, status: 404), throwsA(isA<StreamUnavailable>()));
      expect(() => PicartoApi.qualities('', master: _masterUri, status: 403), throwsA(isA<RiskControl>()));
      expect(() => PicartoApi.qualities('', master: _masterUri, status: 502), throwsA(isA<NetworkFailure>()));
    });
  });

  group('S08 start of the broadcast (the public API)', () {
    test('live: last_live is the UTC start of the broadcast on air', () {
      final fixture = _sample('S08-channel-live');
      final started = PicartoApi.liveSince(fixture.body, name: 'allatir', status: fixture.status);
      expect(started, DateTime.utc(2026, 9, 28, 16, 12, 10));
      expect(started!.isUtc, isTrue);
      expect(started.isBefore(fixture.capturedAt), isTrue);
      expect(fixture.capturedAt.difference(started), lessThan(const Duration(hours: 2)));
      expect(PicartoApi.liveSince(fixture.body, name: 'ALLATIR'), started, reason: 'names compare ignoring case');
      expect(fixture.url.host, PicartoApi.publicApiHost);
    });

    test("offline: last_live is the previous broadcast's, not a start", () {
      final fixture = _sample('S08-channel-offline');
      expect((jsonDecode(fixture.body) as Map)['last_live'], isNotNull);
      expect(PicartoApi.liveSince(fixture.body, name: 'TheBaker', status: fixture.status), isNull);
    });

    test('an unknown channel is NotFound (the caller keeps the room)', () {
      final fixture = _sample('S08-channel-notfound');
      expect(fixture.status, 404);
      expect(
        () => PicartoApi.liveSince(fixture.body, name: 'zxqvnochannelfixture', status: fixture.status),
        throwsA(isA<NotFound>()),
      );
    });

    test('another channel, a missing or malformed time is no start', () {
      String answer(Object? lastLive, {String name = 'Artist', Object? online = true}) =>
          jsonEncode({'name': name, 'online': online, 'last_live': lastLive});
      expect(
        PicartoApi.liveSince(answer('2026-09-28 16:12:10'), name: 'Artist'),
        DateTime.utc(2026, 9, 28, 16, 12, 10),
      );
      for (final body in [
        answer('2026-09-28 16:12:10', name: 'Other'),
        answer('2026-09-28 16:12:10', online: 'true'),
        answer(null),
        answer(''),
        answer(0),
        answer('2026-09-28T16:12:10Z'),
        answer('2026-02-30 16:12:10'),
        answer('2026-09-28 24:00:00'),
        answer('1970-01-01 00:00:00'),
        '"Channel does not exist"',
      ]) {
        expect(
          () => PicartoApi.liveSince(body, name: 'Artist'),
          body.startsWith('"') ? throwsA(isA<ApiChanged>()) : returnsNormally,
          reason: body,
        );
        if (!body.startsWith('"')) expect(PicartoApi.liveSince(body, name: 'Artist'), isNull, reason: body);
      }
    });
  });

  group('lines', () {
    test("one HLS line per URL with 3.x's media headers, the edge as line id, no lease", () {
      final fixture = _sample('S05-master');
      final quality = PicartoApi.qualities(fixture.body, master: fixture.url).single;
      final resolution = PicartoApi.resolution(quality, master: fixture.url);
      final line = resolution.lines.single;
      expect(line.url, ((_legacy('S04-detail-live')['getPlayUrls'] as Map).values.single as List).single);
      // 3.x's PlaybackHeaderResolver: PicartoApi.playHeaders plus the
      // desktop UA, names in lower case.
      expect(line.headers, {
        'referer': 'https://picarto.tv/',
        'origin': 'https://picarto.tv',
        'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/140.0.0.0 Safari/537.36',
      });
      expect(line.headers.containsKey('cookie'), isFalse);
      expect(line.format, StreamFormat.hls);
      expect(line.codec, 'avc');
      expect(line.lineId, 'edge1-eu-west.picarto.tv');
      expect(line.lease, isNull, reason: 'unsigned URLs');
      expect(resolution.appliedQualityData, quality.selectionId);
      expect(resolution.qualityUnconfirmed, isFalse);
    });

    test('a profile with several URLs has several lines; HLS Auto has no codec', () {
      final grouped = PicartoApi.qualities(
        '$_masterText${_masterText.substring(8).replaceAll('variant.m3u8', 'other.m3u8')}\n',
        master: _masterUri,
      ).single;
      expect(PicartoApi.resolution(grouped, master: _masterUri).urls, hasLength(2));
      const auto = LivePlayQuality(quality: 'HLS Auto', id: PicartoApi.autoQualityId, data: ['https://e/x.m3u8']);
      expect(PicartoApi.codecOf(auto), isNull);
      expect(PicartoApi.resolution(auto, master: _masterUri).lines.single.codec, isNull);
      expect(
        PicartoApi.codecOf(
          const LivePlayQuality(quality: 'x', id: '["1920x1080",60.0,"hvc1.1.6.L120,mp4a",null,null]'),
        ),
        'hevc',
      );
      expect(
        () => PicartoApi.resolution(const LivePlayQuality(quality: 'x'), master: _masterUri),
        throwsA(isA<StreamUnavailable>()),
      );
    });
  });

  group('links', () {
    test("3.x's channel pages: exact hosts and one decoded channel segment", () {
      for (final url in ['https://picarto.tv/Artist', 'http://www.picarto.tv/Artist/?ref=share']) {
        expect(PicartoApi.channelFromUrl(Uri.parse(url)), 'Artist', reason: url);
      }
      for (final url in [
        'https://picarto.tv.exampler.org/Artist',
        'https://evil.picarto.tv/Artist',
        'https://user@picarto.tv/Artist',
        'https://picarto.tv:123/Artist',
        'ftp://picarto.tv/Artist',
        'https://picarto.tv/search?q=Artist',
        'https://picarto.tv/explore',
        'https://picarto.tv/Artist/videos',
        'https://picarto.tv//Artist',
        'https://picarto.tv/Artist%2Fvideos',
        'https://picarto.tv/%GG',
      ]) {
        expect(PicartoApi.channelFromUrl(Uri.parse(url)), isNull, reason: url);
      }
    });

    test('site pages that 3.x read as channels are not', () {
      for (final page in ['videos', 'communities', 'subscriptions', 'following', 'shop', 'commissions', 'About']) {
        expect(PicartoApi.channelFromUrl(Uri.parse('https://picarto.tv/$page')), isNull, reason: page);
      }
      expect(PicartoApi.channelFromUrl(Uri.parse('https://picarto.tv:443/Artist')), 'Artist');
      expect(PicartoApi.isChannelName('Shop'), isTrue, reason: 'an answer may still name such a channel');
      expect(PicartoApi.isChannelName('a' * 51), isFalse);
      expect(PicartoApi.roomPageUrl('Artist'), 'https://picarto.tv/Artist');
    });
  });
}
