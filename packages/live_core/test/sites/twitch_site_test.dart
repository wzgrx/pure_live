// TwitchSite over the recorded responses (ReplayHttp): the GraphQL transports
// and their fallbacks, the session on the access token, the catalog's page
// rounds, the list snapshots and the search cursor, detail, the
// token-then-usher stream, recovery, links and error mapping.
//
// GraphQL samples are matched by their JSON body. Some samples were recorded
// by the archived v4 or with an older query (S05-user-*), whose requests
// differ from the adapter's; those responses are replayed as answers to the
// adapter's request (see _answer). The response bodies are the recorded
// ones; a few error answers are synthetic.
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/twitch';
const _ignored = {'p', 'play_session_id', 'sig', 'token'};
final DateTime _now = DateTime.utc(2026, 9, 27, 18, 41, 44);

/// The recorded sample [name] as it is.
ReplaySample _recorded(String name) => ReplaySample.load('$_root/$name');

/// The GraphQL request [json] answered with sample [name]'s response, or
/// with [body] ([status]).
ReplaySample _answer(Object? json, {String? name, Object? body, int status = 200}) {
  final recorded = name == null ? null : _recorded(name);
  return ReplaySample(
    method: 'POST',
    url: TwitchApi.gqlUrl,
    status: recorded?.status ?? status,
    bytes: recorded?.bytes ?? utf8.encode(body is String ? body : jsonEncode(body)),
    json: jsonDecode(jsonEncode(json)),
  );
}

/// The usher playlist of [login] (3.x's parameters, the codecs of
/// [preferH264]) answered with sample [name]'s response.
ReplaySample _usher(String login, String name, {bool preferH264 = true}) {
  final recorded = _recorded(name);
  return ReplaySample(
    method: 'GET',
    url: TwitchApi.usherUrl(login, (value: '', signature: ''), Random(0), preferH264: preferH264),
    status: recorded.status,
    headers: recorded.headers,
    bytes: recorded.bytes,
  );
}

/// The site-wide streams without a language filter: S03-top, then its next
/// chunk (S03-top-cursor). Both were recorded with the query that declared
/// `$languages` as `[String!]` (before E03.17); their answers are replayed
/// as answers to the adapter's query.
List<ReplaySample> _top() => [
  _answer(TwitchApi.streamsOperation(limit: 30), name: 'S03-top'),
  _answer(
    TwitchApi.streamsOperation(limit: 30, cursor: 'eyJzIjo3NTQ3LjQ3NjY5MjE0OTI5NCwiZCI6ZmFsc2UsInQiOnRydWV9'),
    name: 'S03-top-cursor',
  ),
];

/// An integrity challenge for a batch of [count] operations (the shape of
/// S02-game-cursor).
List<Object?> _challenge(int count) => [
  for (var i = 0; i < count; i++)
    {
      'errors': [
        {
          'message': 'failed integrity check',
          'extensions': {'code': 'IntegrityCheckFailed'},
        },
      ],
      'data': null,
      'extensions': {
        'challenge': {'type': 'integrity'},
      },
    },
];

Map<String, Object?> _gqlBody(LiveRequest request) {
  final decoded = jsonDecode(utf8.decode(request.body!));
  return (decoded is List ? decoded.single : decoded) as Map<String, Object?>;
}

Map<String, Object?> _variables(LiveRequest request) => _gqlBody(request)['variables']! as Map<String, Object?>;

/// Scripted answers in order, then [inner].
final class _Script implements LiveHttp {
  new(this.steps, [this.inner]);

  /// A response, or a `TransportFailure` to throw.
  final List<Object> steps;
  final LiveHttp? inner;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    if (steps.isEmpty) return await inner!.send(request);
    final step = steps.removeAt(0);
    if (step is TransportFailure) throw step;
    final (status, body) = step as (int, Object);
    return LiveResponse(status: status, bytes: utf8.encode(body is String ? body : jsonEncode(body)), url: request.url);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnsupportedError('open');

  @override
  void close() {}
}

/// Answers the requests that ask for English with sample [name] (ReplayHttp
/// matches bodies, not headers, and the tags request is the same in both
/// languages); everything else goes to [inner].
final class _English implements LiveHttp {
  new(this.inner, this.name);

  final LiveHttp inner;
  final String name;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    if (!(request.headers['accept-language'] ?? '').startsWith('en')) return await inner.send(request);
    final recorded = _recorded(name);
    return LiveResponse(status: recorded.status, bytes: recorded.bytes, url: request.url);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnsupportedError('open');

  @override
  void close() {}
}

typedef _Setup = ({TwitchSite site, ReplayHttp http});

_Setup _setup(
  List<ReplaySample> samples, {
  CookieVault? cookies,
  List<LiveHttp> fallbacks = const [],
  List<String> Function()? languages,
  bool Function()? preferH264,
  DateTime Function()? now,
}) {
  final http = ReplayHttp(samples, ignoredQuery: _ignored);
  return (
    site: TwitchSite(
      http,
      cookies: cookies,
      gqlFallbacks: fallbacks,
      languages: languages,
      preferH264: preferH264,
      random: Random(1),
      now: now ?? () => _now,
    ),
    http: http,
  );
}

LiveRoom _live(String roomId, {LiveStatus status = LiveStatus.live, LiveRestriction? restriction}) =>
    LiveRoom(platform: 'twitch', roomId: roomId, liveStatus: status, restriction: restriction);

/// A forbidden playback token (the viewer may not watch).
Map<String, Object?> _forbidden(String reason) => {
  'data': {
    'streamPlaybackAccessToken': {
      'value': jsonEncode({
        'authorization': {'forbidden': true, 'reason': reason},
      }),
      'signature': 's',
    },
  },
};

void main() {
  group('GraphQL transports', () {
    const failure = TransportFailure('twitch', TransportReason.connect, 'reset after CONNECT');

    test("every request is POST gql with 3.x's identity in Chinese, site twitch, one Device-Id per adapter", () async {
      final setup = _setup([_recorded('S04-search-p1'), _recorded('S05-detail-live')]);
      await setup.site.searchRooms('minecraft');
      await setup.site.getRoomDetail(roomId: 'zarbex');
      final requests = setup.http.requests;
      expect(requests.map((request) => request.site).toSet(), {'twitch'});
      expect(requests.map((request) => request.method).toSet(), {'POST'});
      expect(requests.map((request) => request.url).toSet(), {TwitchApi.gqlUrl});
      final devices = {for (final request in requests) request.headers['device-id']};
      expect(devices, hasLength(1));
      expect(devices.single, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(requests.first.headers['client-id'], 'kimne78kx3ncx6brgo4mv6wki5h1ko');
      expect(requests.map((request) => request.headers['accept-language']).toSet(), {'zh-CN,zh;q=0.9,en;q=0.8'});
    });

    test('the first transport answers: no fallback is used', () async {
      final fallback = _Script([]);
      final setup = _setup([_recorded('S05-detail-live')], fallbacks: [fallback]);
      await setup.site.getRoomDetail(roomId: 'zarbex');
      expect(fallback.requests, isEmpty);
    });

    test('a transport failure sends the same request through the next transport (3.x: Android system TLS)', () async {
      final first = _Script([failure]);
      final second = ReplayHttp([_recorded('S05-detail-live')]);
      final site = TwitchSite(first, gqlFallbacks: [second], random: Random(1), now: () => _now);
      final room = await site.getRoomDetail(roomId: 'zarbex');
      expect(room.isLiveNow, isTrue);
      final sent = first.requests.single;
      final resent = second.requests.single;
      expect(resent.url, sent.url);
      expect(resent.site, sent.site);
      expect(resent.headers, sent.headers);
      expect(resent.body, sent.body);
    });

    test('an integrity challenge goes to the next transport; the last one is RiskControl', () async {
      final challenge = (
        200,
        {
          'errors': [
            {'message': 'failed integrity check'},
          ],
        },
      );
      final first = _Script([challenge]);
      final second = _Script([challenge]);
      final site = TwitchSite(first, gqlFallbacks: [second], random: Random(1));
      await expectLater(site.getRoomDetail(roomId: 'zarbex'), throwsA(isA<RiskControl>()));
      expect(first.requests, hasLength(1));
      expect(second.requests, hasLength(1));
      final answered = TwitchSite(
        _Script([challenge]),
        gqlFallbacks: [
          ReplayHttp([_recorded('S05-detail-live')]),
        ],
        random: Random(1),
      );
      expect((await answered.getRoomDetail(roomId: 'zarbex')).isLiveNow, isTrue);
    });

    test('HTTP 5xx goes to the next transport; 4xx does not', () async {
      final recovered = _Script([(503, '')], ReplayHttp([_recorded('S05-detail-live')]));
      final fallback = ReplayHttp([_recorded('S05-detail-live')]);
      final site = TwitchSite(recovered, gqlFallbacks: [fallback], random: Random(1));
      expect((await site.getRoomDetail(roomId: 'zarbex')).roomId, 'zarbex');
      expect(fallback.requests, hasLength(1));

      final unused = _Script([]);
      final limited = TwitchSite(_Script([(429, '')]), gqlFallbacks: [unused], random: Random(1));
      await expectLater(limited.getRoomDetail(roomId: 'zarbex'), throwsA(isA<RateLimited>()));
      expect(unused.requests, isEmpty);
    });

    test('every transport failing is NetworkFailure; cancellation passes through at once', () async {
      final site = TwitchSite(
        _Script([failure]),
        gqlFallbacks: [
          _Script([failure]),
        ],
        random: Random(1),
      );
      await expectLater(site.getRoomDetail(roomId: 'zarbex'), throwsA(isA<NetworkFailure>()));
      final unused = _Script([]);
      final cancelled = TwitchSite(
        _Script([const TransportFailure('twitch', TransportReason.cancelled)]),
        gqlFallbacks: [unused],
        random: Random(1),
      );
      await expectLater(
        cancelled.getRoomDetail(roomId: 'zarbex'),
        throwsA(isA<TransportFailure>().having((f) => f.reason, 'reason', TransportReason.cancelled)),
      );
      expect(unused.requests, isEmpty);
    });
  });

  group('catalog', () {
    // The tags of S01-tags and the directories of S01-dirs-1/2 (recorded
    // without the nameless tag; its page is answered empty here).
    final tags = TwitchApi.tags(TwitchApi.decode(Fixture.load('twitch', 'S01-tags').body, status: 200, what: 'tags'));
    Map<String, Object?> recordedPages() {
      final pages = <String, Object?>{};
      for (final name in ['S01-dirs-1', 'S01-dirs-2']) {
        final fixture = Fixture.load('twitch', name);
        final operations = (jsonDecode((fixture.meta['request'] as Map)['body'] as String) as List)
            .cast<Map<String, dynamic>>();
        final envelopes = jsonDecode(fixture.body) as List;
        for (final (index, operation) in operations.indexed) {
          final wanted = ((operation['variables'] as Map)['options'] as Map)['tags'] as List;
          if (wanted.isNotEmpty) pages[wanted.single as String] = envelopes[index];
        }
      }
      return pages;
    }

    const empty = {
      'data': {
        'directoriesWithTags': {
          'edges': <Object?>[],
          'pageInfo': {'hasNextPage': false},
        },
      },
    };

    List<ReplaySample> firstRound() {
      final pages = recordedPages();
      return [
        for (var start = 0; start < tags.length; start += TwitchApi.batchLimit)
          if (tags.sublist(start, min(start + TwitchApi.batchLimit, tags.length)) case final chunk)
            _answer(
              [for (final tag in chunk) TwitchApi.directoriesOperation(tag.id)],
              body: [for (final tag in chunk) pages[tag.id] ?? empty],
            ),
      ];
    }

    /// The second round: the tags whose first page was full, with its cursor.
    List<({String id, String cursor})> continued() {
      final pages = recordedPages();
      return [
        for (final tag in tags)
          if (pages[tag.id] case final page?)
            if (TwitchApi.directories(page, tag) case (:final areas, :final cursor?)
                when areas.length >= TwitchApi.tagDirectoryLimit)
              (id: tag.id, cursor: cursor),
      ];
    }

    List<ReplaySample> challengedSecondRound() {
      final second = continued();
      return [
        for (var start = 0; start < second.length; start += TwitchApi.batchLimit)
          if (second.sublist(start, min(start + TwitchApi.batchLimit, second.length)) case final chunk)
            _answer([
              for (final page in chunk) TwitchApi.directoriesOperation(page.id, cursor: page.cursor),
            ], body: _challenge(chunk.length)),
      ];
    }

    test('tags, then their directories in batches of at most 35 (REG-TWITCH-010); areas as 3.x', () async {
      final second = continued();
      final replay = ReplayHttp([
        _recorded('S01-tags'),
        ...firstRound(),
        ...challengedSecondRound(),
      ], ignoredQuery: _ignored);
      final http = _English(replay, 'S01-tags-en');
      final site = TwitchSite(http, random: Random(1), now: () => _now);
      final categories = await site.getCategories(1, 20);
      expect(categories.map((category) => category.id), tags.map((tag) => tag.id));
      final pages = recordedPages();
      for (final category in categories) {
        final recorded = pages[category.id];
        final expected = recorded == null
            ? 0
            : TwitchApi.directories(recorded, (id: category.id, name: category.name)).areas.length;
        expect(category.children, hasLength(expected), reason: category.name);
      }
      final batches = [
        for (final request in http.requests)
          if (jsonDecode(utf8.decode(request.body!)) case final List<Object?> batch) batch.length,
      ];
      expect(batches.every((size) => size <= TwitchApi.batchLimit), isTrue);
      expect(batches.take(2), [35, 6], reason: '41 tags in the first round');
      expect(
        http.requests,
        hasLength(2 + 2 + (second.length / TwitchApi.batchLimit).ceil()),
        reason: 'the tags twice (Chinese, then English for the nameless one), then the rounds',
      );
    });

    test('8-2: tag names are Chinese; the one Twitch has no Chinese name for takes its English name', () async {
      final http = _English(
        ReplayHttp([_recorded('S01-tags'), ...firstRound(), ...challengedSecondRound()], ignoredQuery: _ignored),
        'S01-tags-en',
      );
      final categories = await TwitchSite(http, random: Random(1), now: () => _now).getCategories(1, 20);
      expect(categories.first.name, '冒险游戏');
      expect(categories.where((category) => category.name.isEmpty), isEmpty);
      final gambling = categories.singleWhere((category) => category.id == '2cf37ad2-6700-4312-a114-27bb91800254');
      expect(gambling.name, 'Gambling');
      final english = http.requests.where((request) => request.headers['accept-language'] == 'en-US,en;q=0.9');
      expect(english, hasLength(1), reason: 'one more request, only for the names');
      final named = categories.firstWhere((category) => category.children.isNotEmpty);
      expect(named.children.first.typeName, named.name, reason: "areas carry their tag's name");
      expect(named.children.first.areaPic, startsWith('https://static-cdn.jtvnw.net/'), reason: '8-7');
    });

    test('when the English names cannot be had, the tag stays nameless and the catalog still loads', () async {
      final replay = ReplayHttp([
        _recorded('S01-tags'),
        ...firstRound(),
        ...challengedSecondRound(),
      ], ignoredQuery: _ignored);
      final categories = await TwitchSite(
        _EnglishFailure(replay),
        random: Random(1),
        now: () => _now,
      ).getCategories(1, 20);
      expect(categories, hasLength(tags.length));
      expect(categories.where((category) => category.name.isEmpty), hasLength(1));
    });

    test('a later page answered with an integrity challenge ends those tags quietly (REG-TWITCH-001)', () async {
      final second = continued();
      expect(second, isNotEmpty, reason: 'most tags have a full first page');
      final setup = _setup([_recorded('S01-tags'), ...firstRound(), ...challengedSecondRound()]);
      final categories = await setup.site.getCategories(1, 20);
      final full = categories.firstWhere((category) => category.id == second.first.id);
      expect(full.children, hasLength(TwitchApi.tagDirectoryLimit));
    });

    test('a later page that answers is added, and the tag goes on while pages are full', () async {
      final tag = tags.first;
      final first = recordedPages()[tag.id]! as Map;
      final cursor = TwitchApi.directories(first, tag).cursor!;
      Map<String, Object?> page(String id, {String? next}) => {
        'data': {
          'directoriesWithTags': {
            'edges': [
              {
                'cursor': 'x',
                'node': {'id': id, 'slug': 's$id', 'displayName': 'D$id'},
              },
            ],
            'pageInfo': {'hasNextPage': next != null},
          },
        },
      };
      final tagsOnly = {
        'data': {
          'searchCategoryTags': [
            {'id': tag.id, 'tagName': tag.name},
          ],
        },
      };
      final setup = _setup([
        _answer(TwitchApi.tagsOperation(), body: tagsOnly),
        _answer([TwitchApi.directoriesOperation(tag.id)], body: [first]),
        _answer(
          [TwitchApi.directoriesOperation(tag.id, cursor: cursor)],
          body: [page('1', next: 'y')],
        ),
      ]);
      final categories = await setup.site.getCategories(1, 20);
      expect(categories.single.children, hasLength(TwitchApi.tagDirectoryLimit + 1));
      expect(categories.single.children.last.areaId, '1');
      expect(setup.http.requests, hasLength(3), reason: 'every tag named: no English request; <30 ends the tag');
    });

    test('a failed first round fails the catalog (3.x showed empty tabs)', () async {
      final setup = _setup([
        _answer(
          TwitchApi.tagsOperation(),
          body: {
            'data': {
              'searchCategoryTags': [
                for (final tag in tags) {'id': tag.id, 'tagName': 'T'},
              ],
            },
          },
        ),
        for (var start = 0; start < tags.length; start += TwitchApi.batchLimit)
          if (tags.sublist(start, min(start + TwitchApi.batchLimit, tags.length)) case final chunk)
            _answer([for (final tag in chunk) TwitchApi.directoriesOperation(tag.id)], body: 'x', status: 502),
      ]);
      await expectLater(setup.site.getCategories(1, 20), throwsA(isA<NetworkFailure>()));
    });
  });

  group('areas (8-3 no language filter by default, 8-10 100 at a time, 8-6 unknown areas)', () {
    const area = LiveArea(platform: 'twitch', areaId: '509658', shortName: 'just-chatting');
    final lastCursor = TwitchApi.gameStreams(
      TwitchApi.decode(Fixture.load('twitch', 'S02-game').body, status: 200, what: 'game'),
      now: _now,
    ).cursor!;
    ReplaySample page(String slug, {String? cursor, List<String> languages = const [], String name = 'S02-game'}) =>
        _answer([TwitchApi.gameOperation(slug, limit: 100, cursor: cursor, languages: languages)], name: name);

    test(
      "one request of 100 in every language (S02-game, the recorded request); the cards' 8-2 and 8-7 fields",
      () async {
        final setup = _setup([_recorded('S02-game')]);
        final rooms = await setup.site.getCategoryRooms(area);
        expect(rooms, hasLength(30), reason: 'the page size asked');
        final variables = _variables(setup.http.requests.single);
        expect(variables['slug'], 'just-chatting');
        expect(variables['limit'], 100);
        expect((variables['options']! as Map)['broadcasterLanguages'], isEmpty);
        expect(setup.http.requests.single.headers.keys, isNot(contains('cookie')));
        expect(rooms.first.area, '谈天说地');
        expect(rooms.first.avatar, startsWith('https://static-cdn.jtvnw.net/'));
      },
    );

    test('pages are cut from the snapshot; the page past it follows the cursor, whose challenge ends the list '
        '(REG-TWITCH-001)', () async {
      final setup = _setup([_recorded('S02-game'), page('just-chatting', cursor: lastCursor, name: 'S02-game-cursor')]);
      final pages = [for (var number = 1; number <= 5; number++) await setup.site.getCategoryRooms(area, page: number)];
      expect(pages.map((rooms) => rooms.length), [30, 30, 27, 0, 0], reason: '87 streams in the first 100');
      final ids = [for (final rooms in pages) ...rooms.map((room) => room.roomId)];
      expect(ids.toSet(), hasLength(87), reason: 'no card twice, none skipped');
      expect(setup.http.requests, hasLength(2), reason: 'pages 2 and 3 from the snapshot; page 4 tried the cursor');
      expect(_variables(setup.http.requests.last)['cursor'], lastCursor);
      expect(_variables(setup.http.requests.last)['limit'], 100);
    });

    test("3.x's 100-card pages work too; a chunk that answers is added, without the cards already there", () async {
      final first = TwitchApi.gameStreams(
        TwitchApi.decode(Fixture.load('twitch', 'S02-game').body, status: 200, what: 'game'),
        now: _now,
      ).rooms;
      Map<String, Object?> edge(String login) => {
        'cursor': 'c-$login',
        'node': {
          'type': 'live',
          'broadcaster': {'login': login},
        },
      };
      final setup = _setup([
        _recorded('S02-game'),
        _answer(
          [TwitchApi.gameOperation('just-chatting', limit: 100, cursor: lastCursor)],
          body: [
            {
              'data': {
                'game': {
                  'streams': {
                    'edges': [edge(first.last.roomId), edge('newcomer_a'), edge('newcomer_b')],
                    'pageInfo': {'hasNextPage': false},
                  },
                },
              },
            },
          ],
        ),
      ]);
      expect(await setup.site.getCategoryRooms(area, pageSize: 100), hasLength(87));
      final second = await setup.site.getCategoryRooms(area, page: 2, pageSize: 100);
      expect(second.map((room) => room.roomId), ['newcomer_a', 'newcomer_b'], reason: 'a browser transport (M12)');
      expect(await setup.site.getCategoryRooms(area, page: 3, pageSize: 100), isEmpty);
      expect(setup.http.requests, hasLength(2), reason: 'no next page');
    });

    test('page 1 fetches anew; a later page after 30 s fetches a new snapshot', () async {
      var clock = _now;
      final setup = _setup([_recorded('S02-game')], now: () => clock);
      await setup.site.getCategoryRooms(area);
      await setup.site.getCategoryRooms(area);
      expect(setup.http.requests, hasLength(2), reason: 'a first page is a refresh');
      clock = clock.add(const Duration(seconds: 29));
      expect(await setup.site.getCategoryRooms(area, page: 2), hasLength(30));
      expect(setup.http.requests, hasLength(2));
      clock = clock.add(const Duration(seconds: 2));
      expect(await setup.site.getCategoryRooms(area, page: 3), hasLength(27));
      expect(setup.http.requests, hasLength(3), reason: 'the snapshot was 31 s old');
    });

    test('8-3: the language setting filters the list, read at each request; 3.x preset ZH + KO', () async {
      var languages = <String>['zh', 'ko'];
      final setup = _setup([
        page('just-chatting', languages: ['ZH', 'KO']),
        _recorded('S02-game'),
      ], languages: () => languages);
      await setup.site.getCategoryRooms(area);
      expect((_variables(setup.http.requests.last)['options']! as Map)['broadcasterLanguages'], ['ZH', 'KO']);
      expect(TwitchApi.legacyLanguages, ['ZH', 'KO']);
      languages = [];
      await setup.site.getCategoryRooms(area, page: 2);
      expect(setup.http.requests, hasLength(2), reason: 'another setting is another list');
      expect((_variables(setup.http.requests.last)['options']! as Map)['broadcasterLanguages'], isEmpty);
    });

    test('a first page answered with a challenge is RiskControl', () async {
      final setup = _setup([page('just-chatting', name: 'S02-game-cursor')]);
      await expectLater(setup.site.getCategoryRooms(area), throwsA(isA<RiskControl>()));
    });

    test('8-6: an unknown directory is NotFound; an area without a slug sends nothing', () async {
      final setup = _setup([page('zzz-not-a-directory', name: 'S02-game-missing')]);
      await expectLater(
        setup.site.getCategoryRooms(const LiveArea(shortName: 'zzz-not-a-directory')),
        throwsA(isA<NotFound>()),
      );
      expect(await setup.site.getCategoryRooms(const LiveArea(areaId: '1')), isEmpty);
      expect(setup.http.requests, hasLength(1));
    });

    test('other failures of a later chunk fail the page and keep the cursor', () async {
      final script = _Script([
        (200, jsonDecode(Fixture.load('twitch', 'S02-game').body) as Object),
        const TransportFailure('twitch', TransportReason.timeout),
        (200, jsonDecode(Fixture.load('twitch', 'S02-game-cursor').body) as Object),
      ]);
      final site = TwitchSite(script, random: Random(1), now: () => _now);
      await site.getCategoryRooms(area, pageSize: 100);
      await expectLater(site.getCategoryRooms(area, page: 2, pageSize: 100), throwsA(isA<NetworkFailure>()));
      expect(await site.getCategoryRooms(area, page: 2, pageSize: 100), isEmpty);
      expect(_variables(script.requests.last)['cursor'], lastCursor, reason: 'the retry used the same cursor');
    });
  });

  group('recommendations (8-3: the whole site)', () {
    test("the site's busiest streams, 30 asked (S03-top), with start times and restrictions; the next chunk's "
        'challenge ends the list', () async {
      final setup = _setup(_top());
      final first = await setup.site.getRecommendRooms();
      expect(first, hasLength(29));
      expect(first.every((room) => room.startedAt != null && room.restriction == LiveRestriction.none), isTrue);
      expect(_gqlBody(setup.http.requests.single)['query'], TwitchApi.streamsQuery);
      expect(_variables(setup.http.requests.single), {'first': 30}, reason: 'no language filter by default');
      expect(await setup.site.getRecommendRooms(page: 2), isEmpty);
      expect(setup.http.requests, hasLength(2), reason: 'page 2 tried the cursor once');
      expect(await setup.site.getRecommendRooms(page: 3), isEmpty);
      expect(setup.http.requests, hasLength(2));
    });

    test("3.x's popular page asks for 100: it gets the 29, in one request", () async {
      final setup = _setup(_top());
      expect(await setup.site.getRecommendRooms(pageSize: 100), hasLength(29));
      expect(setup.http.requests, hasLength(1));
    });

    test('small pages continue where the last one ended', () async {
      final setup = _setup(_top());
      final pages = [
        for (var number = 1; number <= 4; number++) await setup.site.getRecommendRooms(page: number, pageSize: 10),
      ];
      expect(pages.map((rooms) => rooms.length), [10, 10, 9, 0]);
      expect([for (final rooms in pages) ...rooms].map((room) => room.roomId).toSet(), hasLength(29));
    });

    test('the language setting (S03-top-zh-ko); recommendations and areas keep their own snapshots', () async {
      final setup = _setup([
        _recorded('S03-top-zh-ko-language'),
        _answer([
          TwitchApi.gameOperation('just-chatting', limit: 100, languages: ['ZH', 'KO']),
        ], name: 'S02-game'),
      ], languages: () => [' zh', 'KO', 'bad value']);
      final recommended = await setup.site.getRecommendRooms(pageSize: 10);
      expect(recommended, hasLength(10));
      expect(_variables(setup.http.requests.single)['languages'], ['ZH', 'KO']);
      await setup.site.getCategoryRooms(const LiveArea(shortName: 'just-chatting'));
      final again = await setup.site.getRecommendRooms(page: 2, pageSize: 10);
      expect(again, hasLength(10), reason: "the recommendations' own snapshot");
      expect(again.first.roomId, isNot(recommended.first.roomId));
      expect(setup.http.requests, hasLength(2));
    });

    test('the languages are declared as the Language enum (E03.17): the platform rejects [String!] '
        '(S03-top-string-rejected) whether or not any are sent', () async {
      expect(TwitchApi.streamsQuery, contains(r'$languages: [Language!]'));
      final setup = _setup([_answer(TwitchApi.streamsOperation(limit: 30), name: 'S03-top-string-rejected')]);
      await expectLater(
        setup.site.getRecommendRooms(),
        throwsA(isA<ApiChanged>().having((error) => error.detail, 'detail', contains('[Language!]'))),
      );
    });

    test('a first page answered with a challenge is RiskControl', () async {
      final setup = _setup([_answer(TwitchApi.streamsOperation(limit: 30), name: 'S03-top-cursor')]);
      await expectLater(setup.site.getRecommendRooms(), throwsA(isA<RiskControl>()));
    });
  });

  group('search (8-1: paged)', () {
    test('page 2 names the channel cursor in options.targets (REG-TWITCH-002); an empty page ends it', () async {
      final setup = _setup([
        _recorded('S04-search-p1'),
        _recorded('S04-search-p2'),
        _answer(TwitchApi.searchOperation('minecraft', cursor: 'MjU='), name: 'S04-search-empty'),
      ]);
      final first = await setup.site.searchRooms(' minecraft ');
      expect(first, hasLength(10));
      final second = await setup.site.searchRooms('minecraft', page: 2);
      expect(second, hasLength(15));
      expect(second.map((room) => room.roomId).toSet().intersection(first.map((room) => room.roomId).toSet()), isEmpty);
      final options = _variables(setup.http.requests[1])['options']! as Map;
      expect(options['targets'], [
        {'index': 'CHANNEL', 'cursor': 'MTA='},
      ]);
      expect(_variables(setup.http.requests[1]).keys, isNot(contains('cursor')));
      expect(await setup.site.searchRooms('minecraft', page: 3), isEmpty);
      expect(await setup.site.searchRooms('minecraft', page: 4), isEmpty);
      expect(setup.http.requests, hasLength(3), reason: 'an empty page has no cursor');
      expect(first.first.startedAt, isNotNull);
      expect(first.first.avatar, startsWith('https://static-cdn.jtvnw.net/'), reason: '8-7');
    });

    test('a blank keyword sends nothing; a page without its cursor sends nothing', () async {
      final setup = _setup([]);
      expect(await setup.site.searchRooms('  '), isEmpty);
      expect(await setup.site.searchRooms('minecraft', page: 2), isEmpty);
      expect(setup.http.requests, isEmpty);
    });

    test("a later page answered with a challenge ends the search; the first page's is RiskControl", () async {
      final setup = _setup([
        _recorded('S04-search-p1'),
        _answer(TwitchApi.searchOperation('minecraft', cursor: 'MTA='), body: _challenge(1).single),
      ]);
      await setup.site.searchRooms('minecraft');
      expect(await setup.site.searchRooms('minecraft', page: 2), isEmpty);
      final challenged = _setup([_answer(TwitchApi.searchOperation('x'), body: _challenge(1).single)]);
      await expectLater(challenged.site.searchRooms('x'), throwsA(isA<RiskControl>()));
    });
  });

  group('detail', () {
    test('one user query; the id stays as asked, the request names the login in lower case', () async {
      final setup = _setup([_recorded('S05-detail-live')]);
      final room = await setup.site.getRoomDetail(roomId: 'Zarbex');
      expect(room.roomId, 'Zarbex');
      expect(room.isLiveNow, isTrue);
      expect(room.onlineViewers, '18561');
      expect(_variables(setup.http.requests.single)['login'], 'zarbex');
      expect(_gqlBody(setup.http.requests.single)['query'], TwitchApi.userQuery);
    });

    test('the upgrades: description (8-4), live screenshot (8-5), Chinese area (8-2), start time, no restriction', () async {
      final setup = _setup([_recorded('S05-detail-live')]);
      final room = await setup.site.getRoomDetail(roomId: 'zarbex');
      expect(room.introduction, 'GEIL GEMACHT 🗣️');
      expect(
        room.cover,
        'https://static-cdn.jtvnw.net/previews-ttv/live_user_zarbex-640x360.jpg?&t=${_now.millisecondsSinceEpoch ~/ 1000}',
      );
      expect(room.avatar, isNot(room.cover));
      expect(room.area, '谈天说地');
      expect(room.startedAt, DateTime.utc(2026, 9, 28, 14, 2, 26));
      expect(room.restriction, LiveRestriction.none);
    });

    test('refresh and recording send the same single request', () async {
      final setup = _setup([_recorded('S05-detail-offline')]);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: 'minecraft');
      final recorded = await setup.site.getRoomDetailForRecording(roomId: 'minecraft');
      expect(refreshed.isExplicitlyOfflineNow, isTrue);
      expect(refreshed.introduction, isNotEmpty);
      expect(refreshed.startedAt, isNull);
      expect(recorded.title, refreshed.title);
      expect(setup.http.requests, hasLength(2));
      expect(await setup.site.getLiveStatus(roomId: 'minecraft'), isFalse);
    });

    test('an unknown channel is NotFound; not a login is NotFound without a request', () async {
      final setup = _setup([_answer(TwitchApi.userOperation('zzzznotachannelzzzz'), name: 'S05-user-missing')]);
      await expectLater(setup.site.getRoomDetail(roomId: 'zzzznotachannelzzzz'), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getRoomDetail(roomId: 'not a login!'), throwsA(isA<NotFound>()));
      expect(setup.http.requests, hasLength(1));
    });

    test('a failed request is an error, never "offline" (REG-TWITCH-007)', () async {
      final site = TwitchSite(_Script([const TransportFailure('twitch', TransportReason.timeout)]), random: Random(1));
      await expectLater(site.getLiveStatus(roomId: 'zarbex'), throwsA(isA<NetworkFailure>()));
    });

    test('danmaku: the channel, with the chat login of the stored cookie; the detail itself is anonymous '
        '(REG-TWITCH-006)', () async {
      final vault = MemoryCookieVault()..set('twitch', 'auth-token=abc; login=Me; persistent=1');
      addTearDown(vault.dispose);
      final setup = _setup([_recorded('S05-detail-live')], cookies: vault);
      final room = await setup.site.getRoomDetail(roomId: 'zarbex');
      final args = room.danmakuData! as TwitchDanmakuArgs;
      expect(args.channel, 'zarbex');
      expect(args.chat, (login: 'me', token: 'abc'));
      final headers = setup.http.requests.single.headers;
      expect(headers.keys, isNot(anyOf(contains('cookie'), contains('authorization'))));
    });
  });

  group('streams', () {
    test(
      "the access token, then usher (H.264 only): 3.x's qualities; lines with the codec, without the cookie",
      () async {
        final setup = _setup([_recorded('S06-pat-live'), _usher('zarbex', 'S06-usher-live')]);
        final qualities = await setup.site.getPlayQualities(detail: _live('zarbex'));
        expect(qualities.map((quality) => quality.quality), ['1080P50（原画）', '720P60', '480P', '360P', '160P']);
        final token = TwitchApi.accessToken(
          TwitchApi.decode(Fixture.load('twitch', 'S06-pat-live').body, status: 200, what: 'token'),
          login: 'zarbex',
        );
        final usher = setup.http.requests.last;
        expect(usher.url.queryParameters['sig'], token.signature);
        expect(usher.url.queryParameters['token'], token.value);
        expect(usher.url.queryParameters['player_version'], '1.28.0-rc.1');
        expect(usher.url.queryParameters['supported_codecs'], 'h264', reason: '8-8, "优先 H.264" on by default');
        expect(usher.headers['client-id'], TwitchApi.clientId);
        expect(usher.site, 'twitch');
        final resolution = await setup.site.resolvePlayUrls(detail: _live('zarbex'), quality: qualities[1]);
        expect(resolution.urls, qualities[1].data);
        expect(resolution.lines.single.headers['referer'], 'https://www.twitch.tv/zarbex');
        expect(resolution.lines.single.codec, 'avc');
        expect(resolution.appliedQualityData, qualities[1].id);
        expect(setup.http.requests, hasLength(2), reason: 'the quality already holds its URLs');
        expect(await setup.site.getPlayUrls(detail: _live('zarbex'), quality: qualities[1]), qualities[1].data);
      },
    );

    test('8-8: with "优先 H.264" off, usher is asked for HEVC and AV1 as well; the setting is read each time', () async {
      var h264 = false;
      final setup = _setup([
        _recorded('S06-pat-live'),
        _usher('zarbex', 'S06-usher-live', preferH264: false),
        _usher('zarbex', 'S06-usher-live'),
      ], preferH264: () => h264);
      await setup.site.getPlayQualities(detail: _live('zarbex'));
      expect(setup.http.requests.last.url.queryParameters['supported_codecs'], 'av1,h265,h264');
      h264 = true;
      await setup.site.getPlayQualities(detail: _live('zarbex'));
      expect(setup.http.requests.last.url.queryParameters['supported_codecs'], 'h264');
    });

    test('8-8: usher is asked only for the codecs the engine decodes, read each time', () async {
      Set<String>? decodable = {'avc', 'hevc'};
      final http = ReplayHttp([_recorded('S06-pat-live'), _usher('zarbex', 'S06-usher-live')], ignoredQuery: _ignored);
      final site = TwitchSite(
        http,
        preferH264: () => false,
        codecs: () => decodable,
        random: Random(1),
        now: () => _now,
      );
      final requests = <String>[];
      for (final engine in <Set<String>?>[
        {'avc', 'hevc'},
        {'avc'},
        null,
      ]) {
        decodable = engine;
        try {
          await site.getPlayQualities(detail: _live('zarbex'));
        } on Object {
          // The replay only answers the H.264 request; the request is what counts.
        }
        requests.add(
          http.requests
              .lastWhere((request) => request.url.host == 'usher.ttvnw.net')
              .url
              .queryParameters['supported_codecs']!,
        );
      }
      expect(requests, ['h265,h264', 'h264', 'av1,h265,h264']);
    });

    test('8-9: a rerun (replay) plays like a live stream', () async {
      final setup = _setup([_recorded('S06-pat-live'), _usher('zarbex', 'S06-usher-live')]);
      final qualities = await setup.site.getPlayQualities(detail: _live('zarbex', status: LiveStatus.replay));
      expect(qualities, hasLength(5));
    });

    test('a room the detail called offline has no stream: StreamUnavailable without a request', () async {
      final setup = _setup([]);
      await expectLater(
        setup.site.getPlayQualities(detail: _live('minecraft', status: LiveStatus.offline)),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests, isEmpty);
    });

    test(
      'a subscriber-only stream Twitch refuses is StreamUnavailable naming it; an unmarked one NeedsLogin',
      () async {
        final token = (200, _forbidden('UNAUTHORIZED_ENTITLEMENTS') as Object);
        final restricted = TwitchSite(_Script([token]), random: Random(1));
        await expectLater(
          restricted.getPlayQualities(detail: _live('zarbex', restriction: LiveRestriction.subscribersOnly)),
          throwsA(isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('subscribersOnly'))),
        );
        final forbidden = TwitchSite(_Script([token]), random: Random(1));
        await expectLater(
          forbidden.getPlayQualities(detail: _live('zarbex', restriction: LiveRestriction.none)),
          throwsA(isA<NeedsLogin>()),
        );
        final usher403 = TwitchSite(
          _Script([
            (200, jsonDecode(Fixture.load('twitch', 'S06-pat-live').body) as Object),
            (403, '[{"error_code":"unauthorized_entitlements"}]'),
          ]),
          random: Random(1),
        );
        await expectLater(
          usher403.getPlayQualities(detail: _live('zarbex', restriction: LiveRestriction.subscribersOnly)),
          throwsA(isA<StreamUnavailable>()),
        );
        final geo = TwitchSite(_Script([(200, _forbidden('GEOBLOCKED') as Object)]), random: Random(1));
        await expectLater(
          geo.getPlayQualities(detail: _live('zarbex', restriction: LiveRestriction.subscribersOnly)),
          throwsA(isA<RegionBlocked>()),
          reason: 'the region is about this viewer, not the stream',
        );
      },
    );

    test('a channel that went offline: usher 404 is StreamUnavailable', () async {
      final setup = _setup([_recorded('S06-pat-offline'), _usher('minecraft', 'S06-usher-offline')]);
      await expectLater(setup.site.getPlayQualities(detail: _live('minecraft')), throwsA(isA<StreamUnavailable>()));
    });

    test("an unknown channel's token is NotFound", () async {
      final setup = _setup([_recorded('S06-pat-missing')]);
      await expectLater(setup.site.getPlayQualities(detail: _live('zzzznotachannelzzzz')), throwsA(isA<NotFound>()));
    });

    test('recovery fetches a new token and playlist and keeps the variant (by VIDEO group)', () async {
      final setup = _setup([_recorded('S06-pat-live'), _usher('zarbex', 'S06-usher-live')]);
      const old = LivePlayQuality(
        quality: '1080P50（原画）',
        id: '1080:50:9000000:chunked',
        data: ['https://expired.test/a.m3u8'],
      );
      final resolution = await setup.site.resolvePlayUrlsForRecovery(detail: _live('zarbex'), quality: old);
      expect(resolution.urls.single, startsWith('https://use22.playlist.ttvnw.net/v1/playlist/'));
      expect(resolution.appliedQualityData, old.id);
      expect(resolution.lines.single.codec, 'avc');
      expect(setup.http.requests, hasLength(2));
    });

    test('a quality without URLs gets a fresh playlist; an unknown one falls back to the source', () async {
      final setup = _setup([_recorded('S06-pat-live'), _usher('zarbex', 'S06-usher-live')]);
      final resolution = await setup.site.resolvePlayUrls(
        detail: _live('zarbex'),
        quality: const LivePlayQuality(quality: '4K', id: 'x'),
      );
      expect(resolution.lines, hasLength(1));
      expect(resolution.appliedQualityData, '1080:50:9123163:chunked');
    });

    test('the token request carries the stored session; a 401 falls back to anonymous and the cookie is not '
        'sent again until it changes (REG-TWITCH-006)', () async {
      final vault = MemoryCookieVault()..set('twitch', 'auth-token=stale; persistent=1');
      addTearDown(vault.dispose);
      final replay = ReplayHttp([
        _recorded('S06-pat-live'),
        _usher('zarbex', 'S06-usher-live'),
      ], ignoredQuery: _ignored);
      final script = _Script([(401, '{"error":"Unauthorized","status":401}')], replay);
      final site = TwitchSite(script, cookies: vault, random: Random(1), now: () => _now);
      await site.getPlayQualities(detail: _live('zarbex'));
      final tokens = [
        for (final request in script.requests)
          if (request.url == TwitchApi.gqlUrl) request.headers['authorization'],
      ];
      expect(tokens, ['OAuth stale', null]);
      expect(script.requests.first.headers['cookie'], 'auth-token=stale; persistent=1');

      await site.getPlayQualities(detail: _live('zarbex'));
      expect(script.requests.where((request) => request.headers.containsKey('authorization')), hasLength(1));

      vault.set('twitch', 'auth-token=fresh');
      await site.getPlayQualities(detail: _live('zarbex'));
      expect(script.requests.last.url.host, 'usher.ttvnw.net');
      expect(
        script.requests.where((request) => request.headers['authorization'] == 'OAuth fresh'),
        hasLength(1),
        reason: 'a new cookie is tried again',
      );
      expect(
        script.requests.every((request) => request.url.host != 'usher.ttvnw.net' || request.headers['cookie'] == null),
        isTrue,
        reason: 'usher never gets the session',
      );
    });

    test('B-7: each refused cookie is reported once; an anonymous viewer never', () async {
      final vault = MemoryCookieVault()..set('twitch', 'auth-token=stale');
      addTearDown(vault.dispose);
      final replay = ReplayHttp([
        _recorded('S06-pat-live'),
        _usher('zarbex', 'S06-usher-live'),
      ], ignoredQuery: _ignored);
      const refused = (401, '{"error":"Unauthorized","status":401}');
      final script = _Script([refused], replay);
      final site = TwitchSite(script, cookies: vault, random: Random(1), now: () => _now);
      expect(site, isA<LiveSiteCookieRefusals>());
      var refusals = 0;
      final subscription = site.cookieRefusals.listen((_) => refusals++);
      addTearDown(subscription.cancel);
      await site.getPlayQualities(detail: _live('zarbex'));
      await site.getPlayQualities(detail: _live('zarbex'));
      await pumpEventQueue();
      expect(refusals, 1, reason: 'the same cookie is not sent again, so it is reported once');
      vault.set('twitch', 'auth-token=other');
      script.steps.add(refused);
      await site.getPlayQualities(detail: _live('zarbex'));
      await pumpEventQueue();
      expect(refusals, 2, reason: 'a new cookie refused is reported again');

      final anonymous = TwitchSite(
        ReplayHttp([_recorded('S06-pat-live'), _usher('zarbex', 'S06-usher-live')], ignoredQuery: _ignored),
        random: Random(1),
        now: () => _now,
      );
      var none = 0;
      final quiet = anonymous.cookieRefusals.listen((_) => none++);
      addTearDown(quiet.cancel);
      await anonymous.getPlayQualities(detail: _live('zarbex'));
      await pumpEventQueue();
      expect(none, 0);
    });

    test("an integrity challenge on the session's token also falls back to anonymous", () async {
      final vault = MemoryCookieVault()..set('twitch', 'auth-token=t');
      addTearDown(vault.dispose);
      final replay = ReplayHttp([
        _recorded('S06-pat-live'),
        _usher('zarbex', 'S06-usher-live'),
      ], ignoredQuery: _ignored);
      final script = _Script([
        (
          200,
          {
            'errors': [
              {'message': 'failed integrity check'},
            ],
          },
        ),
      ], replay);
      final site = TwitchSite(script, cookies: vault, random: Random(1));
      expect(await site.getPlayQualities(detail: _live('zarbex')), hasLength(5));
    });

    test('8-7: media lines never carry the login cookie (3.x sent it to the CDN)', () async {
      final vault = MemoryCookieVault()..set('twitch', 'auth-token=t');
      addTearDown(vault.dispose);
      final setup = _setup([], cookies: vault);
      final resolution = await setup.site.resolvePlayUrls(
        detail: _live('zarbex'),
        quality: const LivePlayQuality(quality: '720P', id: 'q', data: ['https://a.test/1.m3u8']),
      );
      expect(resolution.lines.single.headers.keys, isNot(contains('cookie')));
      expect(resolution.lines.single.codec, isNull, reason: 'a plain list says no codec');
    });

    test('usher transport failures are NetworkFailure; cancellation passes through', () async {
      final token = (200, jsonDecode(Fixture.load('twitch', 'S06-pat-live').body) as Object);
      final site = TwitchSite(
        _Script([token, const TransportFailure('twitch', TransportReason.timeout)]),
        random: Random(1),
      );
      await expectLater(site.getPlayQualities(detail: _live('zarbex')), throwsA(isA<NetworkFailure>()));
      final cancelled = TwitchSite(
        _Script([token, const TransportFailure('twitch', TransportReason.cancelled)]),
        random: Random(1),
      );
      await expectLater(
        cancelled.getPlayQualities(detail: _live('zarbex')),
        throwsA(isA<TransportFailure>().having((f) => f.reason, 'reason', TransportReason.cancelled)),
      );
    });
  });

  group('links', () {
    final site = _setup([]).site;

    // 3.x test/web_search_room_parser_test.dart, live_url_tool_parser_test.dart
    // and toolbox_link_detection_test.dart, Twitch cases.
    test("3.x's channel links; site pages are not channels", () {
      expect(site.roomIdFromUrl('https://www.twitch.tv/some_streamer'), 'some_streamer');
      expect(site.roomIdFromUrl('https://www.twitch.tv/fixture_channel#chat'), 'fixture_channel');
      expect(site.roomIdFromUrl('https://www.twitch.tv/fixture'), 'fixture');
      expect(site.roomIdFromUrl('https://www.twitch.tv/directory'), isNull);
      expect(site.roomIdFromUrl('https://m.twitch.tv/zarbex/home'), 'zarbex');
      expect(site.roomIdFromUrl('https://twitch.tv/zarbex?sr=a'), 'zarbex');
    });

    test("the case is kept, as 3.x kept it (a follow's identity)", () {
      expect(site.roomIdFromUrl('https://www.twitch.tv/Shroud'), 'Shroud');
    });

    test('pop-out chat and the embedded player name their channel', () {
      expect(site.roomIdFromUrl('https://www.twitch.tv/popout/zarbex/chat'), 'zarbex');
      expect(site.roomIdFromUrl('https://player.twitch.tv/?channel=zarbex&parent=x'), 'zarbex');
      expect(site.roomIdFromUrl('https://www.twitch.tv/popout'), isNull);
      expect(site.roomIdFromUrl('https://player.twitch.tv/?video=123'), isNull);
    });

    test("Twitch's own pages and other subdomains are not channels (3.x took their first segment)", () {
      for (final url in [
        'https://www.twitch.tv/drops/inventory',
        'https://www.twitch.tv/p/en/about',
        'https://www.twitch.tv/videos/123',
        'https://www.twitch.tv/search?term=x',
        'https://clips.twitch.tv/SullenDreamyLobster',
        'https://dev.twitch.tv/docs',
        'https://www.twitch.tv.evil.example/zarbex',
        'https://www.twitch.tv/',
        'https://www.twitch.tv/${'a' * 26}',
        'ftp://www.twitch.tv/zarbex',
      ]) {
        expect(site.roomIdFromUrl(url), isNull, reason: url);
      }
      expect(site.needsResolving('https://www.twitch.tv/zarbex'), isFalse);
    });

    test('share texts through the link parser', () async {
      final http = ReplayHttp([]);
      final registry = SiteRegistry({'twitch': () => TwitchSite(http)});
      final parser = LinkParser(registry, http);
      expect(await parser.parse('快来看 https://www.twitch.tv/zarbex。'), const RoomLink('twitch', 'zarbex'));
      expect(parser.containsSupportedLink('https://www.twitch.tv/directory'), isFalse);
      expect(parser.containsSupportedLink('www.twitch.tv/fixture'), isTrue);
      expect(http.requests, isEmpty);
    });
  });
}

/// Fails every request that asks for English (the tag names), passing the
/// rest to [inner].
final class _EnglishFailure implements LiveHttp {
  new(this.inner);

  final LiveHttp inner;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    if ((request.headers['accept-language'] ?? '').startsWith('en')) {
      return LiveResponse(status: 500, bytes: const [], url: request.url);
    }
    return await inner.send(request);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnsupportedError('open');

  @override
  void close() {}
}
