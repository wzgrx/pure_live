// 17LIVE parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/17live/legacy_expected.dart from 3.x's SeventeenLiveApi,
// SeventeenLiveLink and SeventeenLiveSite). Every intended difference is
// listed with its reason; everything else must match. The synthetic cases
// port 3.x's seventeenlive_public_catalog_test.dart and cover the regression
// entries of the archived spec (REG-17LIVE-001–004) and the shapes 3.x
// refused.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('17live', name);

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

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

/// The outcome of a legacy call (`{requests, value}`).
Object? _value(String name, String key) => (_legacy(name)[key] as Map<String, dynamic>)['value'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

/// 3.x put the media headers on every card (`httpHeaders`), where only
/// IPTV's are read (3.x's PlaybackHeaderResolver built 17LIVE's itself);
/// they now travel on every line.
const _headersMoved = {'httpHeaders'};

const _live = '27484154';
const _offline = '28371376';

LiveRoom _entered(String sample, String roomId) {
  final fixture = _sample(sample);
  return SeventeenLiveApi.enteredRoom(fixture.body, roomId: roomId, status: fixture.status);
}

SeventeenLiveRoomData _data(LiveRoom room) => room.data! as SeventeenLiveRoomData;

/// A stream object as the samples have it (3.x's test fixture).
Map<String, Object?> _stream(
  int roomId, {
  int status = 2,
  Object? ownerRoomId,
  String name = 'Fixture',
  String? userId,
  Map<String, Object?> changes = const {},
  Map<String, Object?> userChanges = const {},
}) {
  final uid = userId ?? 'user-$roomId';
  return {
    'liveStreamID': roomId,
    'userID': uid,
    'status': status,
    'caption': 'Current broadcast',
    'liveViewerCount': 12,
    'viewerCount': 90,
    'coverPhoto': 'http://cdn.17app.co/snapshot/$uid.jpg',
    'userInfo': {
      'roomID': ownerRoomId,
      'userID': uid,
      'displayName': name,
      'picture': 'avatar.jpg',
      'followerCount': 80,
      ...userChanges,
    },
    ...changes,
  };
}

String _sections(List<Object?> sections, {Object? cursor = ''}) => jsonEncode({'cursor': cursor, 'sections': sections});

Map<String, Object?> _section(String id, List<Object?> streams) => {
  'id': id,
  'grids': [
    for (final stream in streams) {'type': 1, 'stream': stream},
  ],
};

List<String> _ids(Iterable<LiveRoom> rooms) => [for (final room in rooms) room.roomId];

/// A provider of `pullURLsInfo.rtmpURLs` (the Tencent CDN, as recorded).
Map<String, Object?> _provider(String host, String uid, {Map<String, Object?> changes = const {}}) => {
  'provider': 17,
  'url': 'http://$host/live/${uid}_enhance003.flv',
  'urlLowQuality': 'http://$host/live/$uid.flv',
  'webUrl': 'http://$host/live/${uid}_enhance003.flv',
  'webUrlLowQuality': 'http://$host/live/$uid.flv',
  'urlHighQuality': 'http://$host/live/$uid.flv',
  'url264': 'http://$host/live/${uid}_h264.flv',
  'urlLowBitrateHD': 'http://$host/live/${uid}_enhance003.flv',
  'urlQualityEnhancedHD': 'http://$host/live/${uid}_enhance002.flv',
  ...changes,
};

String _room(Map<String, Object?> stream) => jsonEncode(stream);

void main() {
  group('S01 sections (JP)', () {
    test('page 1: same rooms, cursor and end as 3.x', () {
      final fixture = _sample('S01-sections-jp');
      final legacy = _value('S01-sections-jp', 'getDirectoryPageAtCursor(1)')! as Map<String, dynamic>;
      final page = SeventeenLiveApi.sectionsPage(fixture.body, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      expect(_ids(page.rooms), rooms.map((room) => room['roomId']));
      expect(page.rooms, hasLength(30));
      for (final (index, room) in page.rooms.indexed) {
        _expectParity(_projection(room), rooms[index], changed: _headersMoved, reason: 'p1[$index]');
        expect(room.httpHeaders, isEmpty);
        expect(room.data, isNull, reason: 'list cards carry no playback (3.x)');
      }
      expect(page.nextCursor, legacy['nextCursor']);
      expect(page.hasMore, legacy['hasMore']);
      expect(
        _ids(page.rooms),
        _maps((_value('S01-sections-jp', 'getDirectoryPage(1)')! as Map)['rooms']).map((room) => room['roomId']),
      );
    });

    test('page 2 after the cursor: same rooms and end as 3.x (the group call section counts)', () {
      final fixture = _sample('S01-sections-jp-p2');
      final cursor = _legacy('S01-sections-jp-p2')['cursor'] as String;
      expect(fixture.url.queryParameters['cursor'], cursor);
      final legacy = _value('S01-sections-jp-p2', 'getDirectoryPageAtCursor(2)')! as Map<String, dynamic>;
      final page = SeventeenLiveApi.sectionsPage(fixture.body, cursor: cursor, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      expect(_ids(page.rooms), ['28571668']);
      for (final (index, room) in page.rooms.indexed) {
        _expectParity(_projection(room), rooms[index], changed: _headersMoved, reason: 'p2[$index]');
      }
      expect(page.nextCursor, isNull);
      expect(page.hasMore, isFalse);
      expect(legacy['hasMore'], isFalse);
    });

    test('the TW page through the same rules: same rooms and cursor as 3.x', () {
      final fixture = _sample('S02-sections-tw');
      final legacy = _value('S02-sections-tw', 'getDirectoryPageAtCursor(1)')! as Map<String, dynamic>;
      final page = SeventeenLiveApi.sectionsPage(fixture.body, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      expect(_ids(page.rooms), rooms.map((room) => room['roomId']));
      expect(page.rooms, hasLength(20));
      for (final (index, room) in page.rooms.indexed) {
        _expectParity(_projection(room), rooms[index], changed: _headersMoved, reason: 'tw[$index]');
      }
      expect(page.nextCursor, legacy['nextCursor']);
    });

    test("cards as 3.x's _card: age notice, no owner roomID needed, current viewers only", () {
      final fixture = _sample('S01-sections-jp');
      final room = SeventeenLiveApi.sectionsPage(fixture.body).rooms.first;
      expect(room.platform, '17live');
      expect(room.roomId, '29759207');
      expect(room.userId, 'e5317d38-5be7-4a16-864d-73503090c5f7');
      expect(room.link, 'https://17.live/en/live/29759207');
      expect(room.notice, '17LIVE 要求观看者年满 18 周岁。');
      expect(room.liveStatus, LiveStatus.live);
      expect(room.audienceMetricType, AudienceMetricType.onlineViewers);
      expect(room.onlineViewers, '5');
      expect(room.totalViewers, '', reason: 'the rows have no viewerCount');
      expect(room.followers, '', reason: 'the rows have no followerCount');
      expect(room.watching, '');
      expect(room.area, '');
      expect(room.cover, startsWith('https://cdn.17app.co/snapshot/'));
      expect(room.avatar, startsWith('https://cdn.17app.co/'));
    });

    test("3.x's catalog test: banners skipped, live rows once, a row of another owner dropped", () {
      final body = _sections([
        _section('TopBanner', [_stream(1)]),
        _section('Label', [
          _stream(2),
          _stream(2),
          _stream(3, status: 0),
          _stream(3),
          _stream(4, userId: 'owner')..['userID'] = 'other',
        ]),
      ], cursor: 'opaque:cursor/one=');
      final page = SeventeenLiveApi.sectionsPage(body);
      expect(_ids(page.rooms), ['2', '3']);
      expect(page.rooms.first.onlineViewers, '12');
      expect(page.rooms.first.totalViewers, '90');
      expect(page.rooms.first.followers, '80');
      expect(page.rooms.first.cover, 'https://cdn.17app.co/snapshot/user-2.jpg');
      expect(page.nextCursor, 'opaque:cursor/one=');
      expect(page.hasMore, isTrue);
      final last = SeventeenLiveApi.sectionsPage(
        _sections([
          _section('Latest', [_stream(5)]),
        ]),
      );
      expect(_ids(last.rooms), ['5']);
      expect(last.hasMore, isFalse);
    });

    test('archive and VOD sections are skipped, others (group call, PK) are read (3.x)', () {
      final body = _sections([
        _section('ArchiveVideo', [_stream(1)]),
        _section('Vod', [_stream(2)]),
        _section('ArchiveClip', [_stream(3)]),
        _section('GroupCall', [_stream(4)]),
        _section('PK', [_stream(5)]),
      ]);
      expect(_ids(SeventeenLiveApi.sectionsPage(body).rooms), ['3', '4', '5']);
      expect(SeventeenLiveApi.skippedSections, {'TopBanner', 'ArchiveVideo', 'Vod'});
    });

    test("a row is dropped for anything 3.x's _room refused (list content as 3.x)", () {
      final rows = [
        _stream(10),
        _stream(11, ownerRoomId: 99),
        _stream(12, ownerRoomId: 'x'),
        _stream(13, userChanges: {'displayName': '', 'openID': ''}),
        _stream(14, userChanges: {'displayName': 7}),
        _stream(15, userChanges: {'followerCount': -1}),
        _stream(16, changes: {'caption': 5}),
        _stream(17, changes: {'liveViewerCount': 'many'}),
        _stream(18, userChanges: {'bio': false}),
        _stream(19, changes: {'userID': ' '}),
        _stream(20, changes: {'userInfo': null}),
        _stream(21, changes: {'status': 1}),
        _stream(22, changes: {'liveStreamID': 0}),
        _stream(23, userChanges: {'displayName': '', 'openID': 'open-23'}),
        _stream(24, ownerRoomId: 24),
      ];
      final page = SeventeenLiveApi.sectionsPage(_sections([_section('Label', rows)]));
      expect(_ids(page.rooms), ['10', '23', '24']);
      expect(page.rooms[1].nick, 'open-23');
    });

    test('unlike 3.x, a section or grid that is not an object is skipped, not the page', () {
      final body = jsonEncode({
        'cursor': null,
        'sections': [
          'banner',
          {'id': 'Label', 'grids': 'none'},
          {
            'id': 'Label',
            'grids': [
              3,
              {'stream': null},
              {'stream': 'x'},
              {'stream': _stream(7)},
            ],
          },
          {'id': 'Latest'},
        ],
      });
      final page = SeventeenLiveApi.sectionsPage(body);
      expect(_ids(page.rooms), ['7']);
      expect(page.hasMore, isFalse);
    });

    test('the cursor: repeated or empty ends; not text, too long or with a control character is ApiChanged', () {
      expect(SeventeenLiveApi.sectionsPage(_sections(const [], cursor: 'a'), cursor: 'a').nextCursor, isNull);
      expect(SeventeenLiveApi.sectionsPage(_sections(const [])).hasMore, isFalse);
      for (final cursor in [12, 'x' * 513, 'a\nb']) {
        expect(
          () => SeventeenLiveApi.sectionsPage(_sections(const [], cursor: cursor)),
          throwsA(isA<ApiChanged>()),
          reason: '$cursor',
        );
      }
      expect(() => SeventeenLiveApi.sectionsPage('[]'), throwsA(isA<ApiChanged>()));
      expect(() => SeventeenLiveApi.sectionsPage('{"sections":{}}'), throwsA(isA<ApiChanged>()));
    });

    test("checkCursor and sectionsQuery: 3.x's request", () {
      expect(SeventeenLiveApi.sectionsQuery(null), {'count': '20', 'typeTab': '2', 'region': 'JP', 'cursor': ''});
      expect(SeventeenLiveApi.sectionsQuery('c')['cursor'], 'c');
      SeventeenLiveApi.checkCursor(null);
      SeventeenLiveApi.checkCursor('x' * 512);
      for (final cursor in ['', 'x' * 513, 'a\u0000b']) {
        expect(() => SeventeenLiveApi.checkCursor(cursor), throwsArgumentError, reason: cursor);
      }
    });
  });

  group('S03 search', () {
    test('same cards as 3.x', () {
      final fixture = _sample('S03-search');
      final legacy = _maps(_value('S03-search', 'searchRooms'));
      final rooms = SeventeenLiveApi.searchRooms(fixture.body, status: fixture.status);
      expect(_ids(rooms), legacy.map((room) => room['roomId']));
      for (final (index, room) in rooms.indexed) {
        _expectParity(_projection(room), legacy[index], changed: _headersMoved, reason: 'search[$index]');
      }
      expect(rooms.single.totalViewers, '1138');
      expect(rooms.single.followers, '2775');
      final none = _sample('S03-search-none');
      expect(SeventeenLiveApi.searchRooms(none.body), isEmpty);
      expect(_value('S03-search-none', 'searchRooms'), isEmpty);
    });

    test("3.x's search test: live rows named by their owner, once", () {
      final rooms = SeventeenLiveApi.searchRooms(
        jsonEncode([
          _stream(123, ownerRoomId: 123, name: 'あかり'),
          _stream(123, ownerRoomId: 123),
          _stream(124, status: 0, ownerRoomId: 124),
          _stream(125, ownerRoomId: 999),
          _stream(125, ownerRoomId: 125),
          _stream(126, ownerRoomId: 126, userId: 'valid')..['userID'] = 'other',
          _stream(127),
          'row',
        ]),
      );
      expect(_ids(rooms), ['123', '125']);
      expect(rooms.first.nick, 'あかり');
      expect(rooms.first.onlineViewers, '12');
      expect(rooms.first.totalViewers, '90');
      expect(rooms.first.data, isNull);
      expect(() => rooms.add(rooms.first), throwsUnsupportedError);
    });

    test('an answer that is not a list is ApiChanged', () {
      expect(() => SeventeenLiveApi.searchRooms('{}'), throwsA(isA<ApiChanged>()));
      expect(() => SeventeenLiveApi.searchRooms('<html>'), throwsA(isA<ApiChanged>()));
    });
  });

  group('S04 rooms', () {
    test('live: entry, refresh and recording rooms as 3.x', () {
      final fixture = _sample('S04-live-live');
      for (final key in ['getRoomDetail', 'getRoomDetailForRecording']) {
        _expectParity(
          _projection(_entered('S04-live-live', _live)),
          _value('S04-live-live', key)! as Map<String, dynamic>,
          changed: _headersMoved,
          reason: key,
        );
      }
      final refreshed = SeventeenLiveApi.refreshRoom(fixture.body, roomId: _live);
      _expectParity(
        _projection(refreshed),
        _value('S04-live-live', 'getRoomDetailForRefresh')! as Map<String, dynamic>,
        changed: _headersMoved,
      );
      expect(refreshed.data, isNull);
      expect(refreshed.onlineViewers, '108');
      expect(refreshed.totalViewers, '1138');
      expect(refreshed.followers, '2775');
      expect(refreshed.introduction, startsWith('皆さんのお力で'));
      expect(_value('S04-live-live', 'getLiveStatus'), isTrue);
    });

    test('live: the qualities, their names, order and every URL as 3.x', () {
      final data = _data(_entered('S04-live-live', _live));
      expect(data.roomId, _live);
      expect(data.userId, '20015b43-ab03-43d8-a37e-32250131d6bc');
      expect(data.unavailable, isNull);
      final legacy = _maps(_value('S04-live-live', 'getPlayQualites'));
      expect(data.qualities.map((q) => q.quality), legacy.map((q) => q['quality']));
      expect(data.qualities.map((q) => q.id), legacy.map((q) => q['id']));
      expect(data.qualities.map((q) => q.sort), legacy.map((q) => q['sort']));
      expect(data.qualities.map((q) => q.quality), ['增强高清 · FLV', '高清 · FLV', 'H.264 · FLV', '标准 · FLV']);
      final urls = _legacy('S04-live-live')['getPlayUrls'] as Map<String, dynamic>;
      final resolved = _legacy('S04-live-live')['resolvePlayUrlsRaw'] as Map<String, dynamic>;
      for (final quality in data.qualities) {
        final resolution = SeventeenLiveApi.resolution(data, quality);
        expect(resolution.urls, (urls['${quality.id}'] as Map)['value'], reason: '${quality.id}');
        final applied = (resolved['${quality.id}'] as Map)['value'] as Map;
        expect(resolution.appliedQualityData, applied['appliedQualityData']);
        expect(resolution.urls, applied['urls']);
      }
    });

    test('lines: media headers, FLV, one per CDN in the answer order, no lease (REG-17LIVE-002, 003)', () {
      final data = _data(_entered('S04-live-live', _live));
      final legacyHeaders = {
        for (final MapEntry(:key, :value) in (_legacy('S04-live-live')['mediaHeaders'] as Map).entries)
          '$key'.toLowerCase(): value,
      };
      for (final quality in data.qualities) {
        final lines = quality.data! as List<LivePlayLine>;
        expect(lines.map((line) => line.lineId), ['tencent', 'wansu'], reason: 'the first CDN serves');
        for (final line in lines) {
          expect(line.headers, legacyHeaders);
          expect(line.headers['referer'], 'https://17.live/en/live/$_live');
          expect(line.format, StreamFormat.flv);
          expect(line.lease, isNull);
          expect(line.codec, quality.id == 'h264' ? 'avc' : isNull, reason: 'REG-17LIVE-001');
        }
      }
      final tencent = (data.qualities.first.data! as List<LivePlayLine>).first.url;
      expect(tencent, startsWith('http://'), reason: '3.x played the Tencent CDN as given');
    });

    test('offline: rooms as 3.x; no stream (3.x gave an empty quality list)', () {
      final fixture = _sample('S04-live-offline');
      final entered = _entered('S04-live-offline', _offline);
      _expectParity(
        _projection(entered),
        _value('S04-live-offline', 'getRoomDetail')! as Map<String, dynamic>,
        changed: _headersMoved,
      );
      _expectParity(
        _projection(SeventeenLiveApi.refreshRoom(fixture.body, roomId: _offline)),
        _value('S04-live-offline', 'getRoomDetailForRefresh')! as Map<String, dynamic>,
        changed: _headersMoved,
      );
      expect(entered.liveStatus, LiveStatus.offline);
      expect(entered.onlineViewers, '', reason: "the last broadcast's counts are not shown");
      expect(entered.totalViewers, '');
      expect(_value('S04-live-offline', 'getPlayQualites'), isEmpty);
      expect(() => SeventeenLiveApi.playQualities(_data(entered)), throwsA(isA<StreamUnavailable>()));
      expect(_value('S04-live-offline', 'getLiveStatus'), isFalse);
    });

    test('an unknown room (HTTP 520 stream not found) is NotFound (REG-17LIVE-004; 3.x said service)', () {
      final fixture = _sample('S04-live-notfound');
      expect(fixture.status, 520);
      expect(
        () => SeventeenLiveApi.refreshRoom(fixture.body, roomId: '999999999', status: fixture.status),
        throwsA(isA<NotFound>()),
      );
      expect(
        () => SeventeenLiveApi.enteredRoom(fixture.body, roomId: '999999999', status: fixture.status),
        throwsA(isA<NotFound>()),
      );
      expect((_value('S04-live-notfound', 'getRoomDetail')! as Map)['message'], '17LIVE service');
    });

    test("3.x's identity rules: the owner's roomID is required, the room and user must match", () {
      String answer(Map<String, Object?> stream) => _room(stream);
      expect(
        () => SeventeenLiveApi.refreshRoom(answer(_stream(123)), roomId: '123'),
        throwsA(isA<ApiChanged>()),
        reason: '3.x: strict owner room identity even when directory summaries omit it',
      );
      for (final stream in [
        _stream(124, ownerRoomId: 124),
        _stream(123, ownerRoomId: 124),
        _stream(123, ownerRoomId: 123)..['userID'] = 'other',
        _stream(123, ownerRoomId: 123, changes: {'userInfo': 'x'}),
        _stream(123, ownerRoomId: 123, changes: {'userID': null}),
      ]) {
        expect(
          () => SeventeenLiveApi.enteredRoom(answer(stream), roomId: '123'),
          throwsA(isA<ApiChanged>()),
          reason: '$stream',
        );
      }
      final room = SeventeenLiveApi.refreshRoom(answer(_stream(123, ownerRoomId: '123')), roomId: '123');
      expect(room.roomId, '123');
      expect(() => SeventeenLiveApi.refreshRoom('[]', roomId: '123'), throwsA(isA<ApiChanged>()));
    });

    test('a status other than live or offline is an unknown state (3.x), with no stream', () {
      final room = SeventeenLiveApi.enteredRoom(_room(_stream(123, ownerRoomId: 123, status: 1)), roomId: '123');
      expect(room.liveStatus, LiveStatus.unknown);
      expect(room.onlineViewers, '');
      expect(() => SeventeenLiveApi.playQualities(_data(room)), throwsA(isA<ApiChanged>()));
    });

    test('unlike 3.x, a room field that is not as expected is left empty instead of failing the room', () {
      final room = SeventeenLiveApi.refreshRoom(
        _room(
          _stream(
            123,
            ownerRoomId: 123,
            changes: {'caption': 5, 'liveViewerCount': -1, 'viewerCount': 'x'},
            userChanges: {'displayName': 7, 'openID': 'open', 'followerCount': -3, 'bio': false},
          ),
        ),
        roomId: '123',
      );
      expect(room.nick, 'open');
      expect(room.title, 'open');
      expect(room.onlineViewers, '');
      expect(room.totalViewers, '');
      expect(room.followers, '');
      expect(room.introduction, '');
      final nameless = SeventeenLiveApi.refreshRoom(
        _room(_stream(123, ownerRoomId: 123, userChanges: {'displayName': null})),
        roomId: '123',
      );
      expect(nameless.nick, '');
      expect(nameless.title, 'Current broadcast');
    });

    test('audio rooms: the area 3.x showed', () {
      final room = SeventeenLiveApi.refreshRoom(
        _room(_stream(123, ownerRoomId: 123, changes: {'audioOnly': 1})),
        roomId: '123',
      );
      expect(room.area, '音频直播');
      expect(
        SeventeenLiveApi.refreshRoom(
          _room(_stream(123, ownerRoomId: 123, changes: {'audioOnly': '0'})),
          roomId: '123',
        ).area,
        '',
      );
    });
  });

  group('streams', () {
    Map<String, Object?> live({Object? providers, Object? fallback, bool withPull = true}) => _stream(
      123,
      ownerRoomId: 123,
      userId: 'uid',
      changes: {
        'pullURLsInfo': ?(withPull ? {'rtmpURLs': providers} : null),
        'rtmpUrls': fallback,
      },
    );

    const tencent = 'tencent-global-pull-rtmp.17app.co';
    const wansu = 'wansu-global-pull-rtmp-latency.17app.co';

    List<LivePlayQuality> offered(Map<String, Object?> answer) =>
        _data(SeventeenLiveApi.enteredRoom(_room(answer), roomId: '123')).qualities;

    test('a live room without any pull URL is entered; its stream says why (3.x failed the entry)', () {
      for (final answer in [
        live(providers: const []),
        live(withPull: false),
        live(
          providers: [
            {'url': 'rtmp://x/live/a.flv', 'url264': ''},
          ],
        ),
      ]) {
        final room = SeventeenLiveApi.enteredRoom(_room(answer), roomId: '123');
        expect(room.isLiveNow, isTrue);
        expect(() => SeventeenLiveApi.playQualities(_data(room)), throwsA(isA<StreamUnavailable>()));
      }
    });

    test('pull data 3.x could not read fails the entry, as in 3.x; the refresh is not affected', () {
      for (final answer in [
        live(providers: 'x'),
        live(providers: List.filled(17, _provider(tencent, 'uid'))),
        live(providers: ['x']),
        live(
          providers: [
            _provider(tencent, 'uid', changes: {'url264': 5}),
          ],
        ),
      ]) {
        expect(() => SeventeenLiveApi.enteredRoom(_room(answer), roomId: '123'), throwsA(isA<ApiChanged>()));
        expect(SeventeenLiveApi.refreshRoom(_room(answer), roomId: '123').isLiveNow, isTrue);
      }
    });

    test('rtmpUrls when there is no pullURLsInfo; an empty rtmpURLs list is not replaced (3.x)', () {
      final fallback = offered(live(withPull: false, fallback: [_provider(tencent, 'uid')]));
      expect(fallback.map((q) => q.id), ['enhanced', 'hd', 'h264', 'standard']);
      expect(() => offered(live(providers: const [], fallback: [_provider(tencent, 'uid')])), returnsNormally);
      expect(offered(live(providers: const [], fallback: [_provider(tencent, 'uid')])), isEmpty);
    });

    test("every field of every provider is a line, each URL once (3.x's _streams)", () {
      final qualities = offered(
        live(
          providers: [
            _provider(
              tencent,
              'uid',
              changes: {'url': 'http://$tencent/live/uid_other.flv', 'urlLowBitrateHD': null, 'urlHighQuality': ''},
            ),
            _provider(wansu, 'uid'),
            _provider(wansu, 'uid'),
          ],
        ),
      );
      final hd = qualities.firstWhere((q) => q.id == 'hd').data! as List<LivePlayLine>;
      expect(hd.map((line) => line.url), [
        'http://$tencent/live/uid_enhance003.flv',
        'http://$tencent/live/uid_other.flv',
        'http://$wansu/live/uid_enhance003.flv',
      ]);
      final standard = qualities.firstWhere((q) => q.id == 'standard').data! as List<LivePlayLine>;
      expect(standard.map((line) => line.lineId), ['tencent', 'wansu']);
    });

    test("a quality with no URL is left out, 3.x's order kept", () {
      final qualities = offered(
        live(
          providers: [
            _provider(tencent, 'uid', changes: {'urlQualityEnhancedHD': null, 'url264': ''}),
          ],
        ),
      );
      expect(qualities.map((q) => q.id), ['hd', 'standard']);
      expect(qualities.map((q) => q.sort), [300, 100]);
    });

    test("pullUrl: an .flv on a *pull-rtmp*.17app.co host, kept as given (3.x's _mediaUri)", () {
      for (final url in [
        'http://tencent-global-pull-rtmp.17app.co/live/a.flv',
        'https://wansu-global-pull-rtmp-latency.17app.co/vod/a.FLV',
        'https://pull-rtmp.17app.co/a.flv?t=1',
      ]) {
        expect(SeventeenLiveApi.pullUrl(url).toString(), url);
      }
      for (final url in [
        '',
        'rtmp://tencent-global-pull-rtmp.17app.co/live/a.flv',
        'https://tencent-global-pull-rtmp.17app.co/live/a.m3u8',
        'https://cdn.17app.co/live/a.flv',
        'https://pull-rtmp.17app.co.evil.test/a.flv',
        'https://user@pull-rtmp.17app.co/a.flv',
        'https://pull-rtmp.17app.co/a.flv#x',
        'https://pull-rtmp.17app.co/a b.flv',
        'https://pull-rtmp.17app.co/a.flv\n',
      ]) {
        expect(SeventeenLiveApi.pullUrl(url), isNull, reason: url);
      }
    });

    test('resolution: the asked quality applied; another is StreamUnavailable (3.x mediaUnavailable)', () {
      final data = _data(_entered('S04-live-live', _live));
      final h264 = data.qualities.firstWhere((q) => q.id == 'h264');
      final resolution = SeventeenLiveApi.resolution(data, h264);
      expect(resolution.appliedQualityData, 'h264');
      expect(resolution.lines.every((line) => line.codec == 'avc'), isTrue);
      expect(
        () => SeventeenLiveApi.resolution(data, const LivePlayQuality(quality: 'x', id: 'source')),
        throwsA(isA<StreamUnavailable>()),
      );
      expect((_value('S04-live-live', 'getPlayUrls(unknown quality)')! as Map)['message'], '17LIVE mediaUnavailable');
      final byName = SeventeenLiveApi.resolution(data, const LivePlayQuality(quality: 'hd', id: 'hd'));
      expect(byName.urls, hasLength(2));
    });
  });

  group('answers', () {
    test("statuses as 3.x's _fetch classed them, except 520 stream not found and 420", () {
      expect(SeventeenLiveApi.statusError(200, '', 'x'), isNull);
      for (final (status, matcher) in [
        (400, isA<ApiChanged>()),
        (420, isA<ApiChanged>()),
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (500, isA<NetworkFailure>()),
        (520, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
        (204, isA<NetworkFailure>()),
      ]) {
        expect(SeventeenLiveApi.statusError(status, '', 'x'), matcher, reason: '$status');
      }
      const notFound = '{"errorCode":0,"errorMessage":"stream not found"}';
      expect(SeventeenLiveApi.statusError(520, notFound, 'x'), isA<NotFound>());
      expect(
        SeventeenLiveApi.statusError(420, '{"errorCode":7,"errorMessage":"no such section"}', 'x'),
        isA<ApiChanged>(),
        reason: 'a refused parameter, not throttling (3.x took 420 for RateLimited)',
      );
      expect(SeventeenLiveApi.statusError(520, '{"errorMessage":"busy"}', 'x'), isA<NetworkFailure>());
    });

    test('an answer over 4 MiB or not JSON is ApiChanged', () {
      expect(() => SeventeenLiveApi.decode('x' * (4 * 1024 * 1024 + 1), what: 'x'), throwsA(isA<ApiChanged>()));
      expect(() => SeventeenLiveApi.decode('<html>', what: 'x'), throwsA(isA<ApiChanged>()));
      expect(SeventeenLiveApi.decode('[]', what: 'x'), isEmpty);
    });

    test("image: the two 17LIVE hosts or a bare file name, always https (3.x's _image)", () {
      expect(SeventeenLiveApi.image('avatar.jpg'), 'https://cdn.17app.co/avatar.jpg');
      expect(SeventeenLiveApi.image('/a/b.png'), 'https://cdn.17app.co/a/b.png');
      expect(SeventeenLiveApi.image('http://cdn.17app.co/snapshot/u?t=1'), 'https://cdn.17app.co/snapshot/u?t=1');
      expect(
        SeventeenLiveApi.image('https://assets-17app.akamaized.net/a.png'),
        'https://assets-17app.akamaized.net/a.png',
      );
      for (final value in [
        null,
        '',
        3,
        'https://evil.test/a.png',
        'https://user@cdn.17app.co/a.png',
        'https://cdn.17app.co/a.png#x',
        '../a.png',
        'a b.png',
        'ftp://cdn.17app.co/a.png',
      ]) {
        expect(SeventeenLiveApi.image(value), '', reason: '$value');
      }
    });
  });

  group('links and headers', () {
    test("roomIdFromUrl: 3.x's SeventeenLiveLink.parse on every recorded vector", () {
      final links = _legacy('S04-live-live')['links'] as Map<String, dynamic>;
      expect(links, hasLength(28));
      for (final MapEntry(key: link, value: legacy as Map<String, dynamic>) in links.entries) {
        final parse = legacy['parse'];
        if (parse is Map) {
          // 3.x threw on a path it could not decode; it is no link now.
          expect(SeventeenLiveApi.roomIdFromUrl(link), isNull, reason: link);
          continue;
        }
        expect(SeventeenLiveApi.roomIdFromUrl(link), parse, reason: link);
        expect(SeventeenLiveApi.normalizeRoomId(link), legacy['normalizeRoomId'], reason: link);
        expect(
          SeventeenLiveApi.roomIdFromUrl(link) ?? SeventeenLiveApi.normalizeRoomId(link),
          legacy['parseOrId'],
          reason: link,
        );
      }
    });

    test("headers and the room page as 3.x's", () {
      Map<String, String> lower(Object? headers) => {
        for (final MapEntry(:key, :value) in (headers! as Map).entries) '$key'.toLowerCase(): '$value',
      };
      final legacy = _legacy('S04-live-live');
      expect(SeventeenLiveApi.requestHeaders(_live), lower(legacy['requestHeaders']));
      expect(SeventeenLiveApi.catalogHeaders, lower(legacy['catalogHeaders']));
      expect(SeventeenLiveApi.mediaHeaders(_live), lower(legacy['mediaHeaders']));
      expect(SeventeenLiveApi.roomUrl(_live), 'https://17.live/en/live/$_live');
      expect((_value('S04-live-live', 'getRoomDetail')! as Map)['link'], SeventeenLiveApi.roomUrl(_live));
    });
  });
}
