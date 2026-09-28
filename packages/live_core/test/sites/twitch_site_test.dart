// TwitchSite over the recorded responses (ReplayHttp): the GraphQL transports
// and their fallbacks, the session on the access token, the catalog's page
// rounds, directory and search cursors, detail, the token-then-usher stream,
// recovery, links and error mapping.
//
// GraphQL samples are matched by their JSON body. Some samples were recorded
// by the archived v4, whose requests differ from 3.x's (no language filter,
// other page sizes, a "top" directory list, usher without 3.x's player
// parameters); the adapter sends 3.x's requests, so those responses are
// replayed as answers to 3.x's request (see _answer). The response bodies are
// the recorded ones; a few error answers are synthetic.
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

/// The usher playlist of [login] (3.x's parameters) answered with sample
/// [name]'s response.
ReplaySample _usher(String login, String name) {
  final recorded = _recorded(name);
  return ReplaySample(
    method: 'GET',
    url: TwitchApi.usherUrl(login, (value: '', signature: ''), Random(0)),
    status: recorded.status,
    headers: recorded.headers,
    bytes: recorded.bytes,
  );
}

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

typedef _Setup = ({TwitchSite site, ReplayHttp http});

_Setup _setup(
  List<ReplaySample> samples, {
  CookieVault? cookies,
  List<LiveHttp> fallbacks = const [],
  bool searchPaging = false,
}) {
  final http = ReplayHttp(samples, ignoredQuery: _ignored);
  return (
    site: TwitchSite(
      http,
      cookies: cookies,
      gqlFallbacks: fallbacks,
      searchPaging: searchPaging,
      random: Random(1),
      now: () => _now,
    ),
    http: http,
  );
}

LiveRoom _live(String roomId) => LiveRoom(platform: 'twitch', roomId: roomId, liveStatus: LiveStatus.live);

void main() {
  group('GraphQL transports', () {
    const failure = TransportFailure('twitch', TransportReason.connect, 'reset after CONNECT');

    test("every request is POST gql with 3.x's identity, site twitch, one Device-Id per adapter", () async {
      final setup = _setup([_recorded('S04-search-p1'), _recorded('S05-user-live')]);
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
    });

    test('the first transport answers: no fallback is used', () async {
      final fallback = _Script([]);
      final setup = _setup([_recorded('S05-user-live')], fallbacks: [fallback]);
      await setup.site.getRoomDetail(roomId: 'zarbex');
      expect(fallback.requests, isEmpty);
    });

    test('a transport failure sends the same request through the next transport (3.x: Android system TLS)', () async {
      final first = _Script([failure]);
      final second = ReplayHttp([_recorded('S05-user-live')]);
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
          ReplayHttp([_recorded('S05-user-live')]),
        ],
        random: Random(1),
      );
      expect((await answered.getRoomDetail(roomId: 'zarbex')).isLiveNow, isTrue);
    });

    test('HTTP 5xx goes to the next transport; 4xx does not', () async {
      final recovered = _Script([(503, '')], ReplayHttp([_recorded('S05-user-live')]));
      final fallback = ReplayHttp([_recorded('S05-user-live')]);
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

    test('tags, then their directories in batches of at most 35 (REG-TWITCH-010); areas as 3.x', () async {
      final second = continued();
      final setup = _setup([
        _recorded('S01-tags'),
        ...firstRound(),
        for (var start = 0; start < second.length; start += TwitchApi.batchLimit)
          if (second.sublist(start, min(start + TwitchApi.batchLimit, second.length)) case final chunk)
            _answer([
              for (final page in chunk) TwitchApi.directoriesOperation(page.id, cursor: page.cursor),
            ], body: _challenge(chunk.length)),
      ]);
      final categories = await setup.site.getCategories(1, 20);
      expect(categories.map((category) => category.id), tags.map((tag) => tag.id));
      expect(categories.map((category) => category.name), tags.map((tag) => tag.name));
      final pages = recordedPages();
      for (final category in categories) {
        final recorded = pages[category.id];
        final expected = recorded == null
            ? 0
            : TwitchApi.directories(recorded, (id: category.id, name: category.name)).areas.length;
        expect(category.children, hasLength(expected), reason: category.name);
      }
      final batches = [
        for (final request in setup.http.requests)
          if (jsonDecode(utf8.decode(request.body!)) case final List<Object?> batch) batch.length,
      ];
      expect(batches.every((size) => size <= TwitchApi.batchLimit), isTrue);
      expect(batches.take(2), [35, 6], reason: '41 tags in the first round');
      expect(setup.http.requests, hasLength(1 + 2 + (second.length / TwitchApi.batchLimit).ceil()));
    });

    test('a later page answered with an integrity challenge ends those tags quietly (REG-TWITCH-001)', () async {
      final second = continued();
      expect(second, isNotEmpty, reason: 'most tags have a full first page');
      final setup = _setup([
        _recorded('S01-tags'),
        ...firstRound(),
        for (var start = 0; start < second.length; start += TwitchApi.batchLimit)
          if (second.sublist(start, min(start + TwitchApi.batchLimit, second.length)) case final chunk)
            _answer([
              for (final page in chunk) TwitchApi.directoriesOperation(page.id, cursor: page.cursor),
            ], body: _challenge(chunk.length)),
      ]);
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
      expect(setup.http.requests, hasLength(3), reason: 'a page with fewer than 30 ends the tag');
    });

    test('a failed first round fails the catalog (3.x showed empty tabs)', () async {
      final setup = _setup([
        _recorded('S01-tags'),
        for (var start = 0; start < tags.length; start += TwitchApi.batchLimit)
          if (tags.sublist(start, min(start + TwitchApi.batchLimit, tags.length)) case final chunk)
            _answer([for (final tag in chunk) TwitchApi.directoriesOperation(tag.id)], body: 'x', status: 502),
      ]);
      await expectLater(setup.site.getCategories(1, 20), throwsA(isA<NetworkFailure>()));
    });
  });

  group('directories', () {
    ReplaySample page(String slug, int limit, {String? cursor, String name = 'S02-game'}) =>
        _answer([TwitchApi.gameOperation(slug, limit: limit, cursor: cursor)], name: name);

    final lastCursor = TwitchApi.gameStreams(
      TwitchApi.decode(Fixture.load('twitch', 'S02-game').body, status: 200, what: 'game'),
      now: _now,
    ).cursor!;

    test("recommend: Just Chatting in Chinese and Korean, the page size asked (3.x's popular page: 100)", () async {
      final setup = _setup([page('just-chatting', 100)]);
      final rooms = await setup.site.getRecommendRooms(pageSize: 100);
      expect(rooms, hasLength(87));
      final variables = _variables(setup.http.requests.single);
      expect(variables['slug'], 'just-chatting');
      expect(variables['limit'], 100);
      expect((variables['options']! as Map)['broadcasterLanguages'], ['ZH', 'KO']);
      expect(setup.http.requests.single.headers.keys, isNot(contains('cookie')));
    });

    test('area pages: the slug, 30 by default; page 2 follows the cursor; its challenge ends the list '
        '(REG-TWITCH-001)', () async {
      const area = LiveArea(platform: 'twitch', areaId: '509658', shortName: 'just-chatting');
      final setup = _setup([
        page('just-chatting', 30),
        page('just-chatting', 30, cursor: lastCursor, name: 'S02-game-cursor'),
      ]);
      expect(await setup.site.getCategoryRooms(area), hasLength(87));
      expect(await setup.site.getCategoryRooms(area, page: 2), isEmpty);
      expect(_variables(setup.http.requests.last)['cursor'], lastCursor);
      expect(await setup.site.getCategoryRooms(area, page: 3), isEmpty);
      expect(setup.http.requests, hasLength(2), reason: 'no cursor, no request');
    });

    test('a first page answered with a challenge is RiskControl', () async {
      final setup = _setup([page('just-chatting', 30, name: 'S02-game-cursor')]);
      await expectLater(setup.site.getRecommendRooms(), throwsA(isA<RiskControl>()));
    });

    test('recommend and the Just Chatting area keep their own cursors (3.x shared them)', () async {
      const area = LiveArea(platform: 'twitch', shortName: 'just-chatting');
      final setup = _setup([
        page('just-chatting', 100),
        _answer(
          [TwitchApi.gameOperation('just-chatting', limit: 30)],
          body: [
            {
              'data': {
                'game': {
                  'streams': {
                    'edges': [
                      {
                        'cursor': 'area-cursor',
                        'node': {
                          'broadcaster': {'login': 'a'},
                        },
                      },
                    ],
                    'pageInfo': {'hasNextPage': true},
                  },
                },
              },
            },
          ],
        ),
        page('just-chatting', 100, cursor: lastCursor),
        _answer([TwitchApi.gameOperation('just-chatting', limit: 30, cursor: 'area-cursor')], name: 'S02-game-missing'),
      ]);
      await setup.site.getRecommendRooms(pageSize: 100);
      await setup.site.getCategoryRooms(area);
      await setup.site.getRecommendRooms(page: 2, pageSize: 100);
      expect(_variables(setup.http.requests.last)['cursor'], lastCursor);
      await setup.site.getCategoryRooms(area, page: 2);
      expect(_variables(setup.http.requests.last)['cursor'], 'area-cursor');
    });

    test('an unknown directory has no streams (3.x); an area without a slug sends nothing', () async {
      final setup = _setup([page('zzz-not-a-directory', 30, name: 'S02-game-missing')]);
      expect(await setup.site.getCategoryRooms(const LiveArea(shortName: 'zzz-not-a-directory')), isEmpty);
      expect(await setup.site.getCategoryRooms(const LiveArea(areaId: '1')), isEmpty);
      expect(setup.http.requests, hasLength(1));
    });
  });

  group('search', () {
    test("the first page; later pages are empty without a request, as users saw 3.x's", () async {
      final setup = _setup([_recorded('S04-search-p1')]);
      expect(await setup.site.searchRooms('minecraft', pageSize: 20), hasLength(10));
      expect(await setup.site.searchRooms('minecraft', page: 2), isEmpty);
      expect(setup.http.requests, hasLength(1));
      expect(await setup.site.searchRooms('  '), isEmpty);
      expect(setup.http.requests, hasLength(1), reason: 'a blank keyword sends nothing');
    });

    test('with searchPaging, page 2 names the channel cursor in options.targets (REG-TWITCH-002)', () async {
      final setup = _setup([
        _recorded('S04-search-p1'),
        _recorded('S04-search-p2'),
        _answer(TwitchApi.searchOperation('minecraft', cursor: 'MjU='), name: 'S04-search-empty'),
      ], searchPaging: true);
      final first = await setup.site.searchRooms(' minecraft ');
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
    });
  });

  group('detail', () {
    test('one user query; the id stays as asked, the request names the login in lower case', () async {
      final setup = _setup([_recorded('S05-user-live')]);
      final room = await setup.site.getRoomDetail(roomId: 'Zarbex');
      expect(room.roomId, 'Zarbex');
      expect(room.isLiveNow, isTrue);
      expect(room.onlineViewers, '23169');
      expect(_variables(setup.http.requests.single)['login'], 'zarbex');
    });

    test('refresh and recording send the same single request', () async {
      final setup = _setup([_recorded('S05-user-offline')]);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: 'minecraft');
      final recorded = await setup.site.getRoomDetailForRecording(roomId: 'minecraft');
      expect(refreshed.isExplicitlyOfflineNow, isTrue);
      expect(recorded.title, refreshed.title);
      expect(setup.http.requests, hasLength(2));
      expect(await setup.site.getLiveStatus(roomId: 'minecraft'), isFalse);
    });

    test('an unknown channel is NotFound; not a login is NotFound without a request', () async {
      final setup = _setup([_recorded('S05-user-missing')]);
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
      final setup = _setup([_recorded('S05-user-live')], cookies: vault);
      final room = await setup.site.getRoomDetail(roomId: 'zarbex');
      final args = room.danmakuData! as TwitchDanmakuArgs;
      expect(args.channel, 'zarbex');
      expect(args.chat, (login: 'me', token: 'abc'));
      final headers = setup.http.requests.single.headers;
      expect(headers.keys, isNot(anyOf(contains('cookie'), contains('authorization'))));
    });
  });

  group('streams', () {
    test("the access token, then usher: 3.x's qualities; lines from the quality with media headers", () async {
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
      expect(usher.headers['client-id'], TwitchApi.clientId);
      expect(usher.site, 'twitch');
      final resolution = await setup.site.resolvePlayUrls(detail: _live('zarbex'), quality: qualities[1]);
      expect(resolution.urls, qualities[1].data);
      expect(resolution.lines.single.headers['referer'], 'https://www.twitch.tv/zarbex');
      expect(resolution.appliedQualityData, qualities[1].id);
      expect(setup.http.requests, hasLength(2), reason: 'the quality already holds its URLs');
      expect(await setup.site.getPlayUrls(detail: _live('zarbex'), quality: qualities[1]), qualities[1].data);
    });

    test('a room the detail did not call live has no stream: StreamUnavailable without a request', () async {
      final setup = _setup([]);
      await expectLater(
        setup.site.getPlayQualities(
          detail: LiveRoom(platform: 'twitch', roomId: 'minecraft', liveStatus: LiveStatus.offline),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests, isEmpty);
    });

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

    test("media lines carry the stored cookie, as 3.x's PlaybackHeaderResolver did", () async {
      final vault = MemoryCookieVault()..set('twitch', 'auth-token=t');
      addTearDown(vault.dispose);
      final setup = _setup([], cookies: vault);
      final resolution = await setup.site.resolvePlayUrls(
        detail: _live('zarbex'),
        quality: const LivePlayQuality(quality: '720P', id: 'q', data: ['https://a.test/1.m3u8']),
      );
      expect(resolution.lines.single.headers['cookie'], 'auth-token=t');
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
