// CHZZK parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/chzzk/legacy_expected.dart from 3.x's ChzzkApi, ChzzkLink and
// ChzzkSite). Every intended difference is listed with its reason;
// everything else must match. The synthetic cases port 3.x's
// chzzk_live_detail_test.dart and cover the regression entries of the
// archived spec (REG-CHZZK-001–004) and the shapes 3.x refused.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('chzzk', name);

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

/// The outcome of a counted legacy call (`{requests, value}`).
Object? _value(String name, String key) => (_legacy(name)[key] as Map<String, dynamic>)['value'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

/// 3.x put the media headers on live cards (`httpHeaders`), where only
/// IPTV's are read (3.x's PlaybackHeaderResolver ignored them for CHZZK);
/// they now travel on every line.
const _headersMoved = {'httpHeaders'};

const _live = 'af3323d30e11ae42c39d7203c7e07fa2';
const _offline = '12bba8d480ba0ffaf85656afd76fa792';
const _region = '75cbf189b3bb8f9f687d2aca0d0a382b';
const _adult = '7ce8032370ac5121dcabce7bad375ced';
const _missing = '00000000000000000000000000000000';

ChzzkChannel _owner(String sample, String id) {
  final fixture = _sample(sample);
  return ChzzkApi.channel(fixture.body, channelId: id, status: fixture.status);
}

/// The channel of a live-detail sample recorded without its channel answer
/// (region, adult): the live's own `channel` object, as the harness answered.
ChzzkChannel _ownerFromLive(String sample, String id) {
  final live = (jsonDecode(_sample(sample).body) as Map<String, dynamic>)['content'] as Map<String, dynamic>;
  return ChzzkApi.channel(jsonEncode({'code': 200, 'content': live['channel']}), channelId: id);
}

ChzzkLive? _liveOf(String sample, ChzzkChannel owner) {
  final fixture = _sample(sample);
  return ChzzkApi.liveDetail(fixture.body, owner: owner, status: fixture.status);
}

String _api(Object? content, {int code = 200}) => jsonEncode({'code': code, 'message': null, 'content': content});

/// A `v1/lives` row.
Map<String, dynamic> _row(
  int liveId, {
  String channelId = _live,
  int viewers = 100,
  Map<String, dynamic> changes = const {},
}) => {
  'liveId': liveId,
  'liveTitle': 'Live $liveId',
  'liveImageUrl': 'https://livecloud-thumb.akamaized.net/chzzk/$liveId/image_{type}.jpg',
  'defaultThumbnailImageUrl': null,
  'concurrentUserCount': viewers,
  'cvExposure': true,
  'adult': false,
  'liveCategoryValue': 'Talk',
  'channel': {
    'channelId': channelId,
    'channelName': 'Streamer $liveId',
    'channelImageUrl': 'https://nng-phinf.pstatic.net/$liveId.png',
  },
  ...changes,
};

String _page(List<Object?> rows, {Object? next}) => _api({
  'size': rows.length,
  'page': next == null ? null : {'next': next, 'prev': null},
  'data': rows,
});

String _hex(int index) => index.toRadixString(16).padLeft(32, '0');

/// A `v3.1 live-detail` answer.
String _detail({
  String status = 'OPEN',
  Object? playback,
  Map<String, dynamic> changes = const {},
  String channelId = _live,
}) => _api({
  'liveId': 1,
  'liveTitle': 'Title',
  'status': status,
  'liveImageUrl': null,
  'defaultThumbnailImageUrl': null,
  'concurrentUserCount': 5,
  'cvExposure': true,
  'adult': false,
  'krOnlyViewing': false,
  'timeMachineActive': false,
  'chatChannelId': 'Chat01',
  'liveCategoryValue': 'Talk',
  'livePlaybackJson': playback,
  'channel': {
    'channelId': channelId,
    'channelName': 'Live name',
    'channelImageUrl': 'https://nng-phinf.pstatic.net/live.png',
  },
  ...changes,
});

const _hlsMaster = 'https://livecloud.akamaized.net/chzzk/a/b_hls_playlist.m3u8?hdnts=st=1~exp=1900000000~acl=*';
const _llhlsMaster = 'https://livecloud.akamaized.net/chzzk/a/b_playlist.m3u8?hdnts=st=1~exp=1900000000~acl=*';

String _playback(List<Map<String, Object?>> media) => jsonEncode({'meta': <String, Object?>{}, 'media': media});

List<Map<String, Object?>> get _twoMedia => [
  {'mediaId': 'HLS', 'protocol': 'HLS', 'path': _hlsMaster},
  {'mediaId': 'LLHLS', 'protocol': 'HLS', 'path': _llhlsMaster, 'latency': 'lowLatency'},
];

const _channelOwner = ChzzkChannel(
  id: _live,
  name: 'Owner',
  avatar: 'https://nng-phinf.pstatic.net/owner.png',
  description: 'About',
  followers: 12,
  isLive: true,
);

String _masterText(List<String> variants) => ['#EXTM3U', '#EXT-X-VERSION:7', ...variants, ''].join('\n');

void main() {
  group('catalog', () {
    test('3.x fixed catalog: one category, the popular area (REG-CHZZK-004 not adopted)', () {
      final legacy = _maps(_value('S03-lives-p1', 'getCategores(1)'));
      final categories = ChzzkApi.categories();
      expect(categories.map((category) => category.id), legacy.map((category) => category['id']));
      expect(categories.map((category) => category.name), legacy.map((category) => category['name']));
      final areas = _maps(legacy.single['children']);
      expect(categories.single.children, hasLength(areas.length));
      _expectParity(categories.single.children.single.toJson(), areas.single);
      expect(categories.single.children.single.areaName, '公开热门直播');
      expect(_value('S03-lives-p1', 'getCategores(2)'), 0);
      expect(_legacy('S03-lives-p1')['directoryNoticeKey'], 'chzzk_directory_scope');
    });

    test('checkArea: null or the popular area; anything else is a caller error', () {
      ChzzkApi.checkArea(null);
      ChzzkApi.checkArea(ChzzkApi.categories().single.children.single);
      for (final area in [
        const LiveArea(platform: 'chzzk', areaType: 'directory', areaId: 'League_of_Legends'),
        const LiveArea(platform: 'chzzk', areaType: 'GAME', areaId: 'popular'),
        const LiveArea(platform: 'soop', areaType: 'directory', areaId: 'popular'),
      ]) {
        expect(() => ChzzkApi.checkArea(area), throwsArgumentError, reason: '$area');
      }
    });
  });

  group('S03 popular directory', () {
    test('page 1: same rooms, cursor and end as 3.x', () {
      final fixture = _sample('S03-lives-p1');
      final legacy = _value('S03-lives-p1', 'getDirectoryPage(1)')! as Map<String, dynamic>;
      final page = ChzzkApi.lives(fixture.body, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      expect(page.rooms.map((room) => room.roomId), rooms.map((room) => room['roomId']));
      for (final (index, room) in page.rooms.indexed) {
        _expectParity(_projection(room), rooms[index], changed: _headersMoved, reason: 'p1[$index]');
        expect(room.httpHeaders, isEmpty);
      }
      expect(page.nextCursor, legacy['nextCursor']);
      expect(page.hasMore, legacy['hasMore']);
      for (final key in ['getRecommendRooms(1)', 'getCategoryRooms(1)']) {
        expect(_maps(_value('S03-lives-p1', key)).map((room) => room['roomId']), rooms.map((room) => room['roomId']));
      }
    });

    test('page 2 after the cursor: same rooms, cursor and end as 3.x', () {
      final fixture = _sample('S03-lives-p2');
      final cursor = _legacy('S03-lives-p2')['cursor'] as String;
      final legacy = _value('S03-lives-p2', 'getDirectoryPageAtCursor(2)')! as Map<String, dynamic>;
      final page = ChzzkApi.lives(fixture.body, cursor: cursor, status: fixture.status);
      final rooms = _maps(legacy['rooms']);
      expect(page.rooms.map((room) => room.roomId), rooms.map((room) => room['roomId']));
      for (final (index, room) in page.rooms.indexed) {
        _expectParity(_projection(room), rooms[index], changed: _headersMoved, reason: 'p2[$index]');
      }
      expect(page.nextCursor, legacy['nextCursor']);
      expect(page.hasMore, isTrue);
      expect(_value('S03-lives-p2', 'getDirectoryPage(2)'), legacy, reason: 'replay gives the same page');
    });

    test('adult rows carry the adult notice; region-locked rows are plain live cards (3.x)', () {
      final fixture = _sample('S03-lives-p1');
      final raw = ((jsonDecode(fixture.body) as Map)['content'] as Map)['data'] as List;
      final rooms = ChzzkApi.lives(fixture.body).rooms;
      for (final (index, row) in raw.cast<Map<String, dynamic>>().indexed) {
        expect(rooms[index].notice, row['adult'] == true ? ChzzkApi.adultNotice : isNull, reason: '$index');
        expect(rooms[index].isLiveNow, isTrue);
        expect(rooms[index].audienceMetricType, AudienceMetricType.onlineViewers);
      }
      expect(raw.where((row) => (row as Map)['blindType'] == 'ABROAD'), isNotEmpty);
    });

    test('the cursor is the last row sent (exclusive): S03 p1 ends where p2 starts', () {
      final p1 = ((jsonDecode(_sample('S03-lives-p1').body) as Map)['content'] as Map)['data'] as List;
      final p2 = ((jsonDecode(_sample('S03-lives-p2').body) as Map)['content'] as Map)['data'] as List;
      final next = ChzzkApi.decodeCursor(ChzzkApi.lives(_sample('S03-lives-p1').body).nextCursor!);
      expect(next.liveId, (p1.last as Map)['liveId']);
      expect(next.viewers, (p1.last as Map)['concurrentUserCount']);
      expect(
        {for (final row in p1) (row as Map)['liveId']}.intersection({for (final row in p2) (row as Map)['liveId']}),
        isEmpty,
      );
    });

    test('3.x query: 30 rows, then 31 after a cursor with its two fields', () {
      expect(ChzzkApi.livesQuery(null), {'size': '30'});
      expect(ChzzkApi.livesQuery(ChzzkApi.encodeCursor(2187, 21334270)), {
        'size': '31',
        'concurrentUserCount': '2187',
        'liveId': '21334270',
      });
      expect(ChzzkApi.encodeCursor(2187, 21334270), '{"v":2187,"l":21334270}');
    });

    test('a first row that is the cursor row is dropped (3.x read the cursor as inclusive)', () {
      final cursor = ChzzkApi.encodeCursor(100, 900);
      final page = ChzzkApi.lives(
        _page(
          [_row(900, channelId: _hex(1)), _row(899, channelId: _hex(2))],
          next: {'concurrentUserCount': 90, 'liveId': 899},
        ),
        cursor: cursor,
      );
      expect(page.rooms.map((room) => room.roomId), [_hex(2)]);
    });

    test('31 rows after a cursor: the 31st is cut and the next page starts right after the 30th', () {
      // 3.x kept `page.next` (the 31st row), so the cut row was never shown.
      final rows = [
        for (var index = 0; index < 31; index++) _row(1000 - index, channelId: _hex(index + 1), viewers: 500 - index),
      ];
      final cursor = ChzzkApi.encodeCursor(600, 2000);
      final page = ChzzkApi.lives(_page(rows, next: {'concurrentUserCount': 470, 'liveId': 970}), cursor: cursor);
      expect(page.rooms, hasLength(30));
      expect(page.rooms.last.roomId, _hex(30));
      expect(ChzzkApi.decodeCursor(page.nextCursor!), (viewers: 471, liveId: 971));
      expect(page.hasMore, isTrue);
      // The same page with the cursor row repeated first (an inclusive
      // server) keeps 30 rows and 3.x's next cursor.
      final inclusive = ChzzkApi.lives(
        _page(
          [_row(2000, channelId: _hex(99), viewers: 600), ...rows.take(30)],
          next: {'concurrentUserCount': 471, 'liveId': 971},
        ),
        cursor: cursor,
      );
      expect(inclusive.rooms.map((room) => room.roomId), page.rooms.map((room) => room.roomId));
      expect(inclusive.nextCursor, page.nextCursor);
    });

    test('a cut row without a viewer count falls back to page.next', () {
      final rows = [
        for (var index = 0; index < 31; index++)
          _row(
            1000 - index,
            channelId: _hex(index + 1),
            changes: index == 29 ? const {'concurrentUserCount': null} : const {},
          ),
      ];
      final page = ChzzkApi.lives(
        _page(rows, next: {'concurrentUserCount': 7, 'liveId': 970}),
        cursor: ChzzkApi.encodeCursor(600, 2000),
      );
      expect(page.rooms, hasLength(30));
      expect(ChzzkApi.decodeCursor(page.nextCursor!), (viewers: 7, liveId: 970));
    });

    test('the end: no page.next, a repeated cursor, or an empty page', () {
      expect(ChzzkApi.lives(_page([_row(1)])).hasMore, isFalse);
      final cursor = ChzzkApi.encodeCursor(1, 5);
      final repeated = ChzzkApi.lives(_page([_row(4)], next: {'concurrentUserCount': 1, 'liveId': 5}), cursor: cursor);
      expect(repeated.nextCursor, isNull);
      final empty = ChzzkApi.lives(_page([], next: {'concurrentUserCount': 1, 'liveId': 4}), cursor: cursor);
      expect(empty.rooms, isEmpty);
      expect(empty.hasMore, isFalse, reason: '3.x: a cursor and a non-empty page');
      expect(ChzzkApi.lives(_api({'size': 0, 'page': null, 'data': <Object?>[]})).hasMore, isFalse);
    });

    test('a channel appears once per page', () {
      final page = ChzzkApi.lives(_page([_row(3), _row(2), _row(1, channelId: _hex(7))]));
      expect(page.rooms.map((room) => room.roomId), [_live, _hex(7)]);
      expect(page.rooms.first.title, 'Live 3');
    });

    test('rows 3.x refused are skipped or filled in, not the page failed', () {
      final page = ChzzkApi.lives(
        _page([
          _row(9, changes: const {'channel': null}),
          _row(8, channelId: 'NOT-A-CHANNEL'),
          _row(7, channelId: _hex(3), changes: const {'liveId': 0}),
          'not a row',
          _row(6, channelId: _hex(4), changes: const {'liveTitle': '  ', 'adult': 'yes', 'liveCategoryValue': 5}),
          _row(5, channelId: _hex(5), changes: const {'concurrentUserCount': -3}),
        ]),
      );
      expect(page.rooms.map((room) => room.roomId), [_hex(4), _hex(5)]);
      expect(page.rooms.first.title, 'Streamer 6', reason: 'an empty title is the channel name, as in the detail');
      expect(page.rooms.first.notice, isNull);
      expect(page.rooms.first.area, '');
      expect(page.rooms.last.onlineViewers, '');
    });

    test('REG-CHZZK-002: viewers only when cvExposure is true', () {
      final page = ChzzkApi.lives(
        _page([
          _row(3, channelId: _hex(1), viewers: 42),
          _row(2, channelId: _hex(2), viewers: 42, changes: const {'cvExposure': false}),
          _row(1, channelId: _hex(3), viewers: 42, changes: const {'cvExposure': null}),
        ]),
      );
      expect(page.rooms.map((room) => room.onlineViewers), ['42', '', '']);
    });

    test('REG-CHZZK-003: the cover template is 480 wide; else the default thumbnail; else none', () {
      final page = ChzzkApi.lives(
        _page([
          _row(3, channelId: _hex(1)),
          _row(
            2,
            channelId: _hex(2),
            changes: const {'liveImageUrl': null, 'defaultThumbnailImageUrl': 'https://ssl.pstatic.net/default.png'},
          ),
          _row(1, channelId: _hex(3), changes: const {'liveImageUrl': null}),
        ]),
      );
      expect(page.rooms[0].cover, 'https://livecloud-thumb.akamaized.net/chzzk/3/image_480.jpg');
      expect(page.rooms[1].cover, 'https://ssl.pstatic.net/default.png');
      expect(page.rooms[2].cover, '');
      final sample = ChzzkApi.lives(_sample('S03-lives-p1').body).rooms;
      expect(sample.where((room) => room.cover.contains('{type}')), isEmpty);
      expect(sample.where((room) => room.cover.endsWith('image_480.jpg')), isNotEmpty);
    });

    test('images: https on NAVER CDNs only (3.x)', () {
      expect(ChzzkApi.image('https://nng-phinf.pstatic.net/a.png'), 'https://nng-phinf.pstatic.net/a.png');
      expect(ChzzkApi.image('https://livecloud-thumb.akamaized.net/a.jpg'), isNotEmpty);
      for (final url in [
        'http://nng-phinf.pstatic.net/a.png',
        'https://example.com/a.png',
        'https://pstatic.net.example.com/a.png',
        'https://user@nng-phinf.pstatic.net/a.png',
        'https://nng-phinf.pstatic.net/a.png#x',
        null,
        42,
      ]) {
        expect(ChzzkApi.image(url), '', reason: '$url');
      }
    });

    test('malformed pages are ApiChanged; the cursor must be ours', () {
      expect(() => ChzzkApi.lives(_api(null)), throwsA(isA<ApiChanged>()));
      expect(() => ChzzkApi.lives(_api({'data': 'x'})), throwsA(isA<ApiChanged>()));
      expect(
        () => ChzzkApi.lives(_page([_row(1)], next: {'concurrentUserCount': -1, 'liveId': 1})),
        throwsA(isA<ApiChanged>()),
      );
      for (final cursor in [
        '',
        'x',
        '{"v":1}',
        '{"v":1,"l":0}',
        '{"v":-1,"l":2}',
        '{"v":1,"l":2,"x":3}',
        '[1,2]',
        'x' * 200,
      ]) {
        expect(() => ChzzkApi.decodeCursor(cursor), throwsArgumentError, reason: cursor);
      }
      expect(ChzzkApi.decodeCursor('{"v":0,"l":2}'), (viewers: 0, liveId: 2));
    });
  });

  group('S04 channel search', () {
    for (final name in ['S04-search-channels', 'S04-search-empty']) {
      test('$name: same cards as 3.x', () {
        final fixture = _sample(name);
        final rooms = ChzzkApi.searchRooms(fixture.body, status: fixture.status);
        final legacy = _maps(_value(name, 'searchRooms'));
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        for (final (index, room) in rooms.indexed) {
          _expectParity(_projection(room), legacy[index], reason: '$name[$index]');
        }
      });
    }

    test('live and offline channels; the title is the name, the cover the avatar', () {
      final rooms = ChzzkApi.searchRooms(_sample('S04-search-channels').body);
      expect(rooms.where((room) => room.isLiveNow), isNotEmpty);
      expect(rooms.where((room) => room.effectiveLiveStatus == LiveStatus.offline), isNotEmpty);
      for (final room in rooms) {
        expect(room.title, room.nick);
        expect(room.cover, room.avatar);
        expect(room.link, 'https://chzzk.naver.com/live/${room.roomId}');
      }
    });

    test('a result without a channel id is skipped (3.x failed the page)', () {
      final rooms = ChzzkApi.searchRooms(
        _api({
          'data': [
            {'channel': null},
            {
              'channel': {'channelId': null, 'channelName': 'x'},
            },
            {
              'channel': {'channelId': _live, 'channelName': '', 'followerCount': 'many', 'openLive': 'true'},
            },
          ],
        }),
      );
      expect(rooms.single.roomId, _live);
      expect(rooms.single.title, '');
      expect(rooms.single.followers, '');
      expect(rooms.single.isLiveNow, isFalse, reason: 'openLive must be true');
      expect(() => ChzzkApi.searchRooms(_api({'data': null})), throwsA(isA<ApiChanged>()));
    });
  });

  group('S05 channel', () {
    for (final (name, id) in [('S05-channel-live', _live), ('S05-channel-offline', _offline)]) {
      test('$name: same channel as 3.x', () {
        final legacy = _value(name, 'channel')! as Map<String, dynamic>;
        final channel = _owner(name, id);
        expect(channel.id, legacy['id']);
        expect(channel.name, legacy['name']);
        expect(channel.avatar, legacy['avatar']);
        expect(channel.description, legacy['description']);
        expect(channel.followers, legacy['followers']);
        expect(channel.isLive, legacy['isLive']);
      });
    }

    test('S05-channel-notfound: an unknown id is NotFound (3.x: identity)', () {
      expect((_value('S05-channel-notfound', 'channel')! as Map)['message'], 'CHZZK identity');
      final fixture = _sample('S05-channel-notfound');
      expect(
        () => ChzzkApi.channel(fixture.body, channelId: _missing, status: fixture.status),
        throwsA(isA<NotFound>()),
      );
      expect(() => ChzzkApi.channel(_api(null), channelId: _live), throwsA(isA<NotFound>()));
    });

    test('another channel is ApiChanged', () {
      expect(
        () => ChzzkApi.channel(_api({'channelId': _offline, 'channelName': 'x'}), channelId: _live),
        throwsA(isA<ApiChanged>()),
      );
      expect(
        () => ChzzkApi.channel(_api({'channelId': 'AF3323D30E11AE42C39D7203C7E07FA2'}), channelId: _live),
        throwsA(isA<ApiChanged>()),
      );
    });
  });

  group('S06 room detail', () {
    for (final (name, owner) in [
      ('S06-live-detail-live', () => _owner('S05-channel-live', _live)),
      ('S06-live-detail-offline', () => _owner('S05-channel-offline', _offline)),
      ('S06-live-detail-region', () => _ownerFromLive('S06-live-detail-region', _region)),
      ('S06-live-detail-adult', () => _ownerFromLive('S06-live-detail-adult', _adult)),
    ]) {
      test('$name: same room as 3.x', () {
        final channel = owner();
        final room = ChzzkApi.room(channel, _liveOf(name, channel));
        for (final key in ['getRoomDetailForRefresh', 'getRoomDetail', 'getRoomDetailForRecording']) {
          _expectParity(
            _projection(room),
            _value(name, key)! as Map<String, dynamic>,
            changed: _headersMoved,
            reason: '$name $key',
          );
        }
        expect(room.httpHeaders, isEmpty);
      });
    }

    test('the open live: its card with the channel followers, introduction and the rewind notice', () {
      final owner = _owner('S05-channel-live', _live);
      final live = _liveOf('S06-live-detail-live', owner)!;
      expect(live.isLive, isTrue);
      expect(live.media.map((media) => media.id), ['HLS', 'LLHLS']);
      expect(live.chatChannelId, 'N2lpu9');
      final room = ChzzkApi.room(owner, live);
      expect(room.followers, '106641');
      expect(room.introduction, owner.description);
      expect(room.onlineViewers, '11370');
      expect(room.notice, ChzzkApi.timeMachineNotice);
      expect(room.area, 'Grand Theft Auto V');
    });

    test('a closed live is the channel card, live by openLive (3.x)', () {
      final owner = _owner('S05-channel-offline', _offline);
      final live = _liveOf('S06-live-detail-offline', owner)!;
      expect(live.isLive, isFalse);
      expect(live.media, isEmpty);
      final room = ChzzkApi.room(owner, live);
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.title, owner.name);
      expect(room.cover, owner.avatar);
      final racing = ChzzkApi.room(
        ChzzkChannel(id: owner.id, name: owner.name, avatar: owner.avatar, isLive: true),
        live,
      );
      expect(racing.isLiveNow, isTrue, reason: '3.x took the state of a closed live from openLive');
      expect(ChzzkApi.room(owner, null).effectiveLiveStatus, LiveStatus.offline, reason: 'never broadcast');
      expect(ChzzkApi.liveDetail(_api(null), owner: owner), isNull);
    });

    test('REG-CHZZK-001: a region-locked live opens with its notice; its stream is RegionBlocked', () {
      final owner = _ownerFromLive('S06-live-detail-region', _region);
      final live = _liveOf('S06-live-detail-region', owner)!;
      expect(live.isLive, isTrue);
      expect(live.krOnly, isTrue);
      expect(live.abroadBlind, isTrue);
      expect(live.media, isEmpty);
      final room = ChzzkApi.room(owner, live);
      expect(room.isLiveNow, isTrue);
      expect(room.notice, ChzzkApi.regionNotice);
      expect(ChzzkApi.unavailable(live), isA<RegionBlocked>());
      // 3.x's chzzk_live_detail_test.dart: v3.1 fields with krOnlyViewing and
      // no playback, the title kept.
      final ported = ChzzkApi.liveDetail(
        _detail(
          changes: {
            'liveId': 21307904,
            'liveTitle': 'Asian Games marathon',
            'krOnlyViewing': true,
            'concurrentUserCount': 1200,
            'chatChannelId': null,
          },
        ),
        owner: _channelOwner,
      )!;
      expect(ChzzkApi.room(_channelOwner, ported).title, 'Asian Games marathon');
      expect(ChzzkApi.room(_channelOwner, ported).notice, isNotEmpty);
      expect(ChzzkApi.unavailable(ported), isA<RegionBlocked>());
      final hiddenAbroad = ChzzkApi.liveDetail(_detail(changes: {'blindType': 'ABROAD'}), owner: _channelOwner)!;
      expect(ChzzkApi.room(_channelOwner, hiddenAbroad).notice, isNull, reason: '3.x noticed krOnlyViewing only');
      expect(ChzzkApi.unavailable(hiddenAbroad), isA<RegionBlocked>());
    });

    test('an adult live opens with its notice; its stream needs a login', () {
      final owner = _ownerFromLive('S06-live-detail-adult', _adult);
      final live = _liveOf('S06-live-detail-adult', owner)!;
      expect(live.adult, isTrue);
      final room = ChzzkApi.room(owner, live);
      expect(room.notice, ChzzkApi.adultNotice);
      expect(room.cover, '');
      expect(ChzzkApi.unavailable(live), isA<NeedsLogin>());
    });

    test("3.x's notice order: region, adult without playback, rewind, adult", () {
      String? notice(Map<String, dynamic> changes, {bool media = false}) => ChzzkApi.room(
        _channelOwner,
        ChzzkApi.liveDetail(
          _detail(playback: media ? _playback(_twoMedia) : null, changes: changes),
          owner: _channelOwner,
        ),
      ).notice;
      expect(notice({'krOnlyViewing': true, 'adult': true, 'timeMachineActive': true}), ChzzkApi.regionNotice);
      expect(notice({'adult': true, 'timeMachineActive': true}), ChzzkApi.adultNotice);
      expect(notice({'adult': true, 'timeMachineActive': true}, media: true), ChzzkApi.timeMachineNotice);
      expect(notice({'adult': true}, media: true), ChzzkApi.adultNotice);
      expect(notice({}, media: true), isNull);
    });

    test('S06-live-detail-notfound: HTTP 404 is NotFound (3.x: missing)', () {
      expect((_value('S06-live-detail-notfound', 'liveDetail')! as Map)['message'], 'CHZZK missing');
      final fixture = _sample('S06-live-detail-notfound');
      expect(
        () => ChzzkApi.liveDetail(
          fixture.body,
          owner: const ChzzkChannel(id: _missing, name: '', avatar: ''),
          status: fixture.status,
        ),
        throwsA(isA<NotFound>()),
      );
    });

    test('CLOSED is offline too; any other status is ApiChanged, never offline', () {
      expect(ChzzkApi.liveDetail(_detail(status: 'CLOSED'), owner: _channelOwner)!.isLive, isFalse);
      for (final status in ['READY', '', null]) {
        expect(
          () => ChzzkApi.liveDetail(_detail(changes: {'status': status}), owner: _channelOwner),
          throwsA(isA<ApiChanged>()),
          reason: '$status',
        );
      }
    });

    test("a live of another channel is ApiChanged; a live without its channel uses the owner's", () {
      expect(() => ChzzkApi.liveDetail(_detail(channelId: _offline), owner: _channelOwner), throwsA(isA<ApiChanged>()));
      final bare = ChzzkApi.liveDetail(_detail(changes: {'channel': null, 'liveTitle': ''}), owner: _channelOwner)!;
      expect(bare.nick, 'Owner');
      expect(bare.avatar, _channelOwner.avatar);
      expect(bare.title, 'Owner', reason: "3.x: an empty title is the channel's name");
    });

    test('REG-CHZZK-002 in the detail: viewers only when cvExposure is true', () {
      final hidden = ChzzkApi.liveDetail(_detail(changes: {'cvExposure': false}), owner: _channelOwner);
      expect(ChzzkApi.room(_channelOwner, hidden).onlineViewers, '');
      final shown = ChzzkApi.liveDetail(_detail(), owner: _channelOwner);
      expect(ChzzkApi.room(_channelOwner, shown).onlineViewers, '5');
    });

    test('an unusable livePlaybackJson keeps the room; the entry reports it', () {
      for (final playback in [
        '{',
        42,
        _playback([
          {'mediaId': 'HLS', 'path': _hlsMaster},
        ]),
        _playback([
          {'mediaId': 'HLS', 'protocol': 'HLS', 'path': 'https://example.com/a.m3u8'},
        ]),
        jsonEncode({'media': null}),
      ]) {
        final live = ChzzkApi.liveDetail(_detail(playback: playback), owner: _channelOwner)!;
        expect(live.media, isEmpty, reason: '$playback');
        expect(live.mediaError, isA<ApiChanged>(), reason: '$playback');
        expect(ChzzkApi.room(_channelOwner, live).isLiveNow, isTrue);
        expect(ChzzkApi.unavailable(live), same(live.mediaError));
      }
      final closed = ChzzkApi.liveDetail(
        _detail(status: 'CLOSE', playback: '{'),
        owner: _channelOwner,
      )!;
      expect(closed.mediaError, isNull, reason: 'read only for an open live');
      expect(ChzzkApi.unavailable(closed), isA<StreamUnavailable>());
    });

    test('a live without playback that is neither region-locked nor adult is StreamUnavailable', () {
      final live = ChzzkApi.liveDetail(_detail(), owner: _channelOwner);
      expect(ChzzkApi.unavailable(live), isA<StreamUnavailable>());
      expect(ChzzkApi.unavailable(null), isA<StreamUnavailable>());
    });
  });

  group('livePlaybackJson', () {
    test('HLS and LLHLS of protocol HLS, in order, each master once', () {
      final media = ChzzkApi.media(
        _playback([
          {'mediaId': 'DASH', 'protocol': 'DASH', 'path': 'https://livecloud.akamaized.net/a.mpd'},
          ..._twoMedia,
          {'mediaId': 'HLS', 'protocol': 'HLS', 'path': _hlsMaster},
          {'mediaId': 'LOW', 'protocol': 'HLS', 'path': 'https://livecloud.akamaized.net/low.m3u8'},
        ]),
      );
      expect(media.map((item) => item.id), ['HLS', 'LLHLS']);
      expect(media.first.url, Uri.parse(_hlsMaster));
      expect(ChzzkApi.media(null), isEmpty);
      expect(ChzzkApi.media(''), isEmpty);
    });

    test('the recorded playback has the two masters of S07', () {
      final live = (jsonDecode(_sample('S06-live-detail-live').body) as Map)['content'] as Map;
      final media = ChzzkApi.media(live['livePlaybackJson']);
      expect(media.map((item) => item.url.path), [
        _sample('S07-master-hls').url.path,
        _sample('S07-master-llhls').url.path,
      ]);
    });

    test('masters must be plain https URLs on akamaized.net', () {
      for (final path in [
        'http://livecloud.akamaized.net/a.m3u8',
        'https://akamaized.net.example.com/a.m3u8',
        'https://user@livecloud.akamaized.net/a.m3u8',
        'https://livecloud.akamaized.net/a.m3u8#x',
        'https://livecloud.akamaized.net/a b.m3u8',
        '',
        null,
      ]) {
        expect(
          () => ChzzkApi.media(
            _playback([
              {'mediaId': 'HLS', 'protocol': 'HLS', 'path': path},
            ]),
          ),
          throwsA(isA<ApiChanged>()),
          reason: '$path',
        );
      }
      expect(
        () => ChzzkApi.media(_playback([for (var index = 0; index < 17; index++) _twoMedia.first])),
        throwsA(isA<ApiChanged>()),
      );
    });
  });

  group('S07 qualities and lines', () {
    for (final (name, mediaId) in [('S07-master-hls', 'HLS'), ('S07-master-llhls', 'LLHLS')]) {
      test('$name: same qualities and URLs as 3.x', () {
        final fixture = _sample(name);
        final qualities = ChzzkApi.qualities([
          (media: ChzzkMedia(mediaId, fixture.url), body: fixture.body),
        ], issuedAt: fixture.capturedAt);
        final legacy = _maps(_value(name, 'qualities'));
        expect(qualities.map((quality) => quality.quality), legacy.map((quality) => quality['quality']));
        expect(qualities.map((quality) => quality.id), legacy.map((quality) => quality['id']));
        expect(qualities.map((quality) => quality.sort), legacy.map((quality) => quality['sort']));
        for (final (index, quality) in qualities.indexed) {
          final lines = quality.data! as List<LivePlayLine>;
          expect(lines.map((line) => line.url), legacy[index]['data'], reason: '${quality.id}');
          expect(lines.map((line) => line.lineId), everyElement(mediaId));
        }
      });
    }

    test('S06-live-detail-live: both masters make one quality list, HLS line first (3.x)', () {
      final live = (jsonDecode(_sample('S06-live-detail-live').body) as Map)['content'] as Map;
      final media = ChzzkApi.media(live['livePlaybackJson']);
      final hls = _sample('S07-master-hls');
      final qualities = ChzzkApi.qualities([
        (media: media[0], body: hls.body),
        (media: media[1], body: _sample('S07-master-llhls').body),
      ], issuedAt: hls.capturedAt);
      final legacy = _maps(_value('S06-live-detail-live', 'getPlayQualites'));
      expect(qualities.map((quality) => quality.quality), legacy.map((quality) => quality['quality']));
      expect(qualities.map((quality) => quality.id), ['1080p60', '720p60', '480p', '360p', '144p']);
      expect(qualities.map((quality) => quality.sort), legacy.map((quality) => quality['sort']));
      final urls = (_legacy('S06-live-detail-live')['getPlayUrls'] as Map).cast<String, dynamic>();
      for (final (index, quality) in qualities.indexed) {
        final lines = quality.data! as List<LivePlayLine>;
        expect(lines.map((line) => line.url), legacy[index]['data']);
        expect(lines.map((line) => line.url), urls[quality.id]);
        expect(lines.map((line) => line.lineId), ['HLS', 'LLHLS']);
      }
    });

    test('lines carry the media headers, HLS, the codec and the token lease', () {
      final fixture = _sample('S07-master-hls');
      final best = ChzzkApi.qualities([
        (media: ChzzkMedia('HLS', fixture.url), body: fixture.body),
      ], issuedAt: fixture.capturedAt).first;
      final line = (best.data! as List<LivePlayLine>).single;
      expect(line.headers, {
        'user-agent': ChzzkApi.userAgent,
        'referer': 'https://chzzk.naver.com/',
      }, reason: "3.x's PlaybackHeaderResolver branch for CHZZK");
      expect(line.format, StreamFormat.hls);
      expect(line.codec, 'avc');
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(1790586285 * 1000, isUtc: true);
      expect(line.lease!.expiresAt, expiresAt, reason: "the variant's hdntl exp");
      expect(line.lease!.refreshAt, expiresAt.subtract(const Duration(minutes: 10)));
      expect(line.lease!.cutsConnection, isTrue);
      expect(expiresAt.difference(fixture.capturedAt), greaterThan(const Duration(hours: 16)));
    });

    test("a variant without hdntl takes the master's hdnts; short lifetimes renew at a quarter", () {
      final issuedAt = DateTime.utc(2030);
      final seconds = issuedAt.millisecondsSinceEpoch ~/ 1000;
      final master = Uri.parse('https://livecloud.akamaized.net/a/m.m3u8?hdnts=st=1~exp=${seconds + 400}~acl=*~hmac=x');
      final lease = ChzzkApi.lease(master.resolve('720p/c.m3u8'), master: master, issuedAt: issuedAt)!;
      expect(lease.expiresAt, issuedAt.add(const Duration(seconds: 400)));
      expect(lease.refreshAt, issuedAt.add(const Duration(seconds: 300)));
      expect(
        ChzzkApi.lease(master.resolve('c.m3u8'), master: master, issuedAt: issuedAt.add(const Duration(hours: 1))),
        isNull,
      );
      expect(
        ChzzkApi.lease(
          Uri.parse('https://livecloud.akamaized.net/c.m3u8'),
          master: Uri.parse('https://livecloud.akamaized.net/m.m3u8'),
          issuedAt: issuedAt,
        ),
        isNull,
      );
    });

    test('ranked by height then bandwidth; 60 at 50 fps or more; same URL once', () {
      final master = Uri.parse(_hlsMaster);
      final qualities = ChzzkApi.qualities([
        (
          media: ChzzkMedia('HLS', master),
          body: _masterText([
            '#EXT-X-STREAM-INF:BANDWIDTH=900,RESOLUTION=1280x720,FRAME-RATE=30.000',
            '720a.m3u8',
            '#EXT-X-STREAM-INF:BANDWIDTH=2000,RESOLUTION=1280x720,FRAME-RATE=50.000',
            '720b.m3u8',
            '#EXT-X-STREAM-INF:BANDWIDTH=1000,RESOLUTION=1280x720,FRAME-RATE=29.970',
            '720c.m3u8',
            '#EXT-X-STREAM-INF:BANDWIDTH=5000,RESOLUTION=640x360',
            '360.m3u8',
            '#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"',
            'audio.m3u8',
          ]),
        ),
        (
          media: ChzzkMedia('LLHLS', Uri.parse(_llhlsMaster)),
          body: _masterText([
            '#EXT-X-STREAM-INF:BANDWIDTH=900,RESOLUTION=1280x720,CODECS="hvc1.1.6.L93.B0"',
            '720a.m3u8',
          ]),
        ),
      ], issuedAt: DateTime.utc(2030));
      expect(qualities.map((quality) => quality.id), ['720p60', '720p', '360p'], reason: 'audio only left out');
      expect(qualities.map((quality) => quality.quality), ['720p60 · HLS', '720p · HLS', '360p · HLS']);
      expect(qualities[1].sort, 720 * 10000000 + 900, reason: 'the first variant of the quality');
      final lines = qualities[1].data! as List<LivePlayLine>;
      expect(lines.map((line) => line.url), [
        'https://livecloud.akamaized.net/chzzk/a/720a.m3u8',
        'https://livecloud.akamaized.net/chzzk/a/720c.m3u8',
      ], reason: 'the LLHLS 720a has the same URL');
      expect(lines.map((line) => line.codec), [null, null]);
    });

    test('an unreadable master is ApiChanged; no video variant is StreamUnavailable', () {
      final media = ChzzkMedia('HLS', Uri.parse(_hlsMaster));
      for (final body in [
        'not a playlist',
        _masterText(['#EXT-X-SESSION-KEY:METHOD=AES-128', '#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1x1', 'a.m3u8']),
        _masterText(['#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1x1', 'http://livecloud.akamaized.net/a.m3u8']),
      ]) {
        expect(
          () => ChzzkApi.qualities([(media: media, body: body)], issuedAt: DateTime.utc(2030)),
          throwsA(isA<ApiChanged>()),
          reason: body,
        );
      }
      expect(
        () => ChzzkApi.qualities([
          (media: media, body: _masterText(['#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"', 'audio.m3u8'])),
        ], issuedAt: DateTime.utc(2030)),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(() => ChzzkApi.qualities(const [], issuedAt: DateTime.utc(2030)), throwsA(isA<StreamUnavailable>()));
    });

    test('codecs', () {
      expect(ChzzkApi.codecOf('avc1.640028,mp4a.40.2'), 'avc');
      expect(ChzzkApi.codecOf('mp4a.40.2, avc3.4D001F'), 'avc');
      expect(ChzzkApi.codecOf('hev1.1.6.L93.B0,mp4a.40.2'), 'hevc');
      expect(ChzzkApi.codecOf('HVC1.1.6'), 'hevc');
      expect(ChzzkApi.codecOf('mp4a.40.2'), isNull);
      expect(ChzzkApi.codecOf(null), isNull);
    });

    test('the resolution of a quality: its lines, applied as asked; else why not', () {
      final fixture = _sample('S07-master-hls');
      final qualities = ChzzkApi.qualities([
        (media: ChzzkMedia('HLS', fixture.url), body: fixture.body),
      ], issuedAt: fixture.capturedAt);
      final data = ChzzkRoomData(channelId: _live, qualities: qualities);
      final resolution = ChzzkApi.resolution(data, const LivePlayQuality(quality: 'any', id: '480p'));
      expect(resolution.appliedQualityData, '480p');
      expect(resolution.lines.single.url, contains('/480p/'));
      expect(
        () => ChzzkApi.resolution(data, const LivePlayQuality(quality: '4K', id: '2160p')),
        throwsA(isA<StreamUnavailable>()),
      );
      final region = ChzzkRoomData(channelId: _live, unavailable: const RegionBlocked('chzzk'));
      expect(() => ChzzkApi.playQualities(region), throwsA(isA<RegionBlocked>()));
      expect(() => ChzzkApi.resolution(region, qualities.first), throwsA(isA<RegionBlocked>()));
    });
  });

  group('answers', () {
    test("statuses as 3.x's _read classed them", () {
      expect(ChzzkApi.statusError(200, 'x'), isNull);
      expect(ChzzkApi.statusError(400, 'x'), isA<ApiChanged>());
      expect(ChzzkApi.statusError(401, 'x'), isA<RiskControl>());
      expect(ChzzkApi.statusError(403, 'x'), isA<RiskControl>());
      expect(ChzzkApi.statusError(404, 'x'), isA<NotFound>());
      expect(ChzzkApi.statusError(429, 'x'), isA<RateLimited>());
      for (final status in [500, 503, 302, 204, 0]) {
        expect(ChzzkApi.statusError(status, 'x'), isA<NetworkFailure>(), reason: '$status');
      }
    });

    test('code other than 200, not JSON, too long: ApiChanged', () {
      expect(() => ChzzkApi.content(_api({}, code: 9004), what: 'x'), throwsA(isA<ApiChanged>()));
      expect(() => ChzzkApi.content('<html>', what: 'x'), throwsA(isA<ApiChanged>()));
      expect(() => ChzzkApi.content('[]', what: 'x'), throwsA(isA<ApiChanged>()));
      expect(() => ChzzkApi.content(' ' * (ChzzkApi.responseLimit + 1), what: 'x'), throwsA(isA<ApiChanged>()));
      expect(ChzzkApi.content(_api({'a': 1}), what: 'x'), {'a': 1});
    });

    test('a master: 404 means the stream is gone; others as the API', () {
      expect(() => ChzzkApi.master('', what: 'HLS master', status: 404), throwsA(isA<StreamUnavailable>()));
      expect(() => ChzzkApi.master('', what: 'HLS master', status: 403), throwsA(isA<RiskControl>()));
      expect(() => ChzzkApi.master('', what: 'HLS master', status: 502), throwsA(isA<NetworkFailure>()));
      expect(ChzzkApi.master('#EXTM3U', what: 'HLS master'), '#EXTM3U');
    });
  });

  group('links', () {
    test("3.x's ChzzkLink: the live page, any case, returned in lower case", () {
      for (final (url, id) in [
        ('https://chzzk.naver.com/live/$_live', _live),
        ('http://chzzk.naver.com/live/$_live/', _live),
        ('https://CHZZK.naver.com/live/${_live.toUpperCase()}', _live),
        ('https://chzzk.naver.com//live//$_live?from=share#t', _live),
        ('  https://chzzk.naver.com/live/$_live  ', _live),
      ]) {
        expect(ChzzkApi.roomIdFromUrl(url), id, reason: url);
      }
    });

    test('not rooms: the channel page, other hosts, other paths, user info, other schemes', () {
      for (final url in [
        'https://chzzk.naver.com/$_live',
        'https://m.chzzk.naver.com/live/$_live',
        'https://game.naver.com/live/$_live',
        'https://chzzk.naver.com/live/${_live.substring(1)}',
        'https://chzzk.naver.com/live/$_live/extra',
        'https://chzzk.naver.com/video/123',
        'https://user@chzzk.naver.com/live/$_live',
        'ftp://chzzk.naver.com/live/$_live',
        'https://chzzk.naver.com/live/%FF',
        '',
      ]) {
        expect(ChzzkApi.roomIdFromUrl(url), isNull, reason: url);
      }
    });

    test('the room link is the live page', () {
      expect(ChzzkApi.roomUrl(_live), 'https://chzzk.naver.com/live/$_live');
      expect(ChzzkApi.isChannelId(_live), isTrue);
      expect(ChzzkApi.isChannelId(_live.toUpperCase()), isFalse, reason: '3.x checked lower case');
    });
  });
}
