// niconico parsing against the recorded samples, compared field by field
// with 3.x's frozen output (expected.json), and 3.x's parser tests
// (test/niconico_api_test.dart, niconico_directory_test.dart,
// niconico_stream_test.dart, niconico_quality_catalog_test.dart and the link
// cases of niconico_application_test.dart; their small JSON fixtures are
// inline here). Every intended difference is listed with its reason (an
// M4.U item number for the upgrades: 17-1 broadcaster rooms, 17-2 links,
// 17-3 comment arguments, 17-4 bad rows, 17-5 introductions, and the M2.1
// start and restriction); everything else must match.
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('niconico', name);

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

/// A watch page carrying [data] the way the site writes it (an HTML-escaped
/// attribute; `HtmlEscape` also escapes `'` and `/`).
String _page(Map<String, dynamic> data) {
  final props = const HtmlEscape().convert(jsonEncode(data));
  return '<html><body><script id="embedded-data" data-props="$props"></script></body></html>';
}

/// 3.x's test/fixtures/niconico/live.json and its siblings, as maps.
Map<String, dynamic> _watchFixture({
  String status = 'ON_AIR',
  bool canWatch = true,
  bool region = false,
  Object? watchCount = 25,
  String socket = 'wss://a.live2.nicovideo.jp/unama/wsapi/v2/watch/123?audience_token=fixture',
}) => _mutable({
  'program': {
    'nicoliveProgramId': 'lv100',
    'title': 'Fixture 配信',
    'status': status,
    'supplier': {'name': 'Fixture broadcaster'},
    'statistics': {'watchCount': watchCount},
  },
  'programWatch': {
    'condition': {'needLogin': false},
  },
  'userProgramWatch': {'canWatch': canWatch, 'isCountryRestrictionTarget': region},
  'site': {
    'relive': {'webSocketUrl': socket},
    'frontendId': 9,
  },
});

/// [value] with every nested map and list mutable and loosely typed, as
/// `jsonDecode` gives them.
Map<String, dynamic> _mutable(Map<String, Object?> value) => jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

/// A list row as 3.x's directory test wrote it.
Map<String, dynamic> _row({bool search = false, int id = 100}) => _mutable({
  search ? 'nicoliveProgramId' : 'id': 'lv$id',
  search ? 'status' : 'liveCycle': 'ON_AIR',
  'title': '公開ライブ & game',
  'providerType': 'community',
  'watchPageUrl': 'https://live.nicovideo.jp/watch/lv$id?ref=fixture',
  'listingThumbnail': 'https://listing-thumbnail.live.nicovideo.jp?image=fixture',
  'flippedListingThumbnail': 'https://asset2.dlive.nicovideo.jp/screenshot.jpg',
  if (search)
    'supplier': {
      'name': 'Broadcaster',
      'icons': {'uri150x150': 'https://secure-dcdn.cdn.nimg.jp/icon.jpg'},
    },
  if (!search)
    'programProvider': {'id': '1', 'name': 'Broadcaster', 'icon': 'https://secure-dcdn.cdn.nimg.jp/icon.jpg'},
  'statistics': {'watchCount': 12, 'commentCount': 99},
});

Map<String, dynamic> _envelope({bool search = false, List<Object?>? rows, Object? total = 1}) => _mutable({
  'meta': {'statusCode': 200, 'errorCode': 'OK', if (!search) 'totalCount': total},
  'data': search
      ? {
          'programs': rows ?? [_row(search: true)],
          'totalCount': total,
        }
      : rows ?? [_row()],
});

/// 3.x's test/fixtures/niconico/stream.json: six qualities, thirteen
/// cookies (one name on several paths), one expiring in 2099.
Map<String, dynamic> _stream() => _mutable({
  'uri': 'https://livedelivery.dlive.nicovideo.jp/hls/playlists/fixture-program/fixture-session/master.m3u8',
  'quality': 'abr',
  'availableQualities': ['abr', 'super_high', '1.5Mbps480p30fps', '480kbps288p30fps', 'audio_high', 'audio_only'],
  'protocol': 'hls',
  'cookies': [
    {
      'name': 'session',
      'value': 'fixture-0',
      'expires': 'Thu, 01 Jan 2099 00:00:00 GMT',
      'domain': 'nicovideo.jp',
      'path': '/hls/keys/fixture-program',
      'secure': true,
    },
    for (final (index, path) in [
      '/hls/playlists/fixture-program/fixture-session',
      '/hls/segments/fixture-program/video',
      '/hls/segments/fixture-program/audio',
      '/hls/keys/fixture-program/fixture-session',
    ].indexed)
      for (final (offset, name) in ['CloudFront-Policy', 'CloudFront-Signature', 'CloudFront-Key-Pair-Id'].indexed)
        {
          'name': name,
          'value': 'fixture-${index * 3 + offset + 1}',
          'expires': null,
          'domain': 'nicovideo.jp',
          'path': path,
          'secure': true,
        },
  ],
});

/// 3.x's zh.json `niconico_program_scope`, which its frozen details end
/// with; M5.14 dropped its closing "；弹幕暂未接入" (comments not connected).
const _v3ProgramScope = '收藏对应本次节目，主播的新节目需重新添加；弹幕暂未接入。';

/// Observed official-program master attributes with synthetic media paths
/// (3.x's `officialMaster`).
const _officialMaster = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="trial-audio-192Kbps",NAME="Main Audio",DEFAULT=YES,URI="audio192.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="trial-audio-96Kbps",NAME="Main Audio",DEFAULT=YES,URI="audio96.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1080800,AVERAGE-BANDWIDTH=1000000,CODECS="avc1.4D401F,mp4a.40.2",RESOLUTION=800x450,FRAME-RATE=30.000,AUDIO="trial-audio-192Kbps"
normal.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=412800,AVERAGE-BANDWIDTH=384000,CODECS="avc1.4D4015,mp4a.40.2",RESOLUTION=512x288,FRAME-RATE=30.000,AUDIO="trial-audio-96Kbps"
low.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=201600,AVERAGE-BANDWIDTH=192000,CODECS="avc1.4D4015,mp4a.40.2",RESOLUTION=512x288,FRAME-RATE=30.000,AUDIO="trial-audio-96Kbps"
super-low.m3u8
''';

final Uri _media = Uri.parse('https://livedelivery.dlive.nicovideo.jp');

/// The `stream` message data of the recorded seat.
Map<String, dynamic> _recordedStream() {
  for (final line in File('../../fixtures/niconico/seat/S04-seat/frames.jsonl').readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final frame = jsonDecode(line) as Map<String, dynamic>;
    final message = jsonDecode(frame['text'] as String) as Map<String, dynamic>;
    if (frame['dir'] == 'in' && message['type'] == 'stream') return message['data'] as Map<String, dynamic>;
  }
  throw StateError('no stream frame');
}

void main() {
  group('S01 catalog and recent programs', () {
    test("one category with the seven tabs, in 3.x's order and names", () {
      final legacy = (((_sample('S01-recent-common-p1').legacy as Map)['getCategores'] as Map)['page1'] as List)
          .cast<Map<String, dynamic>>()
          .single;
      final category = NiconicoApi.category();
      expect(category.id, legacy['id']);
      expect(category.name, legacy['name']);
      final areas = (legacy['children'] as List).cast<Map<String, dynamic>>();
      expect(category.children, hasLength(7));
      for (final (index, area) in category.children.indexed) {
        _expectParity(area.toJson(), areas[index], reason: 'area $index');
      }
      expect(NiconicoApi.tabs, ['common', 'try', 'live', 'req', 'face', 'totu', 'vtuber']);
    });

    for (final name in ['S01-recent-common-p1', 'S01-recent-req-p1', 'S01-recent-face-p1']) {
      test('$name: the same programs, order, fields and paging as 3.x; broadcasters as rooms', () {
        final fixture = _sample(name);
        final legacy = (fixture.legacy as Map<String, dynamic>)['getDirectoryPage'] as Map<String, dynamic>;
        final page = NiconicoApi.directoryPage(fixture.body, page: 1, search: false, status: fixture.status);
        final rooms = (legacy['rooms'] as List).cast<Map<String, dynamic>>();
        final rows = ((jsonDecode(fixture.body) as Map)['data'] as List).cast<Map<String, dynamic>>();
        expect(page.rooms, hasLength(rooms.length));
        expect(page.hasMore, legacy['hasMore']);
        expect(page.page, legacy['page']);
        for (final (index, room) in page.rooms.indexed) {
          final row = rows[index];
          // roomId, link (17-1): the card is the broadcaster; 3.x's card was
          // the program, which is still the row at the same place.
          expect(rooms[index]['roomId'], row['id'], reason: 'the same program, in the same order');
          final provider = row['programProvider'] as Map;
          final expected = row['providerType'] == 'channel'
              ? (row['socialGroup'] as Map)['id']
              : 'user/${provider['id']}';
          expect(room.roomId, expected, reason: '$name[$index]');
          expect(room.link, 'https://live.nicovideo.jp/watch/$expected');
          // avatar: a channel's program provider has an empty icon; 3.x only
          // fell back to the social group's icon for a missing one, so the
          // card had none (see "有意差异").
          final emptyIcon = provider['icon'] == '';
          _expectParity(
            room.toJson(),
            rooms[index],
            changed: {'roomId', 'link', if (emptyIcon) 'avatar'},
            reason: '$name[$index]',
          );
          if (emptyIcon) {
            expect(rooms[index]['avatar'], '');
            expect(room.avatar, (row['socialGroup'] as Map)['thumbnailUrl']);
          }
          // M2.1: the start is beginAt (milliseconds); the restriction is
          // the row's flags.
          expect(room.startedAt, DateTime.fromMillisecondsSinceEpoch(row['beginAt'] as int, isUtc: true));
          expect(
            room.restriction,
            row['isPayProgram'] == true ? LiveRestriction.paid : LiveRestriction.none,
            reason: '$name[$index]',
          );
          expect(room.data, isNull, reason: 'list cards carry no bootstrap');
          expect(room.onlineViewers, isEmpty, reason: 'watchCount is cumulative, never concurrent');
        }
        final list = fixture.legacy as Map<String, dynamic>;
        expect(list['getRecommendRooms'] ?? list['getCategoryRooms'], [for (final row in rows) row['id']]);
      });
    }

    test('S01 face: the one channel program is the channel, paid, with its icon', () {
      final fixture = _sample('S01-recent-face-p1');
      final page = NiconicoApi.directoryPage(fixture.body, page: 1, search: false);
      final channel = page.rooms.singleWhere((room) => room.roomId == 'ch2640864');
      expect(channel.nick, 'くるる!!', reason: 'the program provider name, as in 3.x');
      expect(channel.avatar, 'https://secure-dcdn.cdn.nimg.jp/comch/channel-icon/128x128/ch2640864.jpg?1785535320');
      expect(channel.link, 'https://live.nicovideo.jp/watch/ch2640864');
      expect(channel.restriction, LiveRestriction.paid, reason: 'isPayProgram (its watch page has a free part)');
      expect(channel.startedAt, DateTime.utc(2026, 9, 27, 13, 30));
      expect(page.rooms.where((room) => room.roomId.startsWith('lv')), isEmpty, reason: 'no official program here');
    });
  });

  test('S02 search: the same programs as 3.x, with more pages; broadcasters as rooms', () {
    final fixture = _sample('S02-search');
    final legacy = fixture.legacy as Map<String, dynamic>;
    final page = NiconicoApi.directoryPage(fixture.body, page: 1, search: true, status: fixture.status);
    final rooms = (legacy['searchRooms'] as List).cast<Map<String, dynamic>>();
    final rows = (((jsonDecode(fixture.body) as Map)['data'] as Map)['programs'] as List).cast<Map<String, dynamic>>();
    expect(page.rooms, hasLength(40));
    for (final (index, room) in page.rooms.indexed) {
      final row = rows[index];
      expect(rooms[index]['roomId'], row['nicoliveProgramId'], reason: 'the same program, in the same order');
      // roomId, link (17-1): every S02 row is a user's program.
      expect(room.roomId, 'user/${(row['supplier'] as Map)['programProviderId']}');
      _expectParity(room.toJson(), rooms[index], changed: {'roomId', 'link'}, reason: 'S02[$index]');
      expect(room.startedAt, DateTime.fromMillisecondsSinceEpoch((row['beginTime'] as int) * 1000, isUtc: true));
      expect(room.restriction, LiveRestriction.none, reason: 'payment and isFollowerOnly are false');
    }
    expect(page.hasMore, legacy['hasMore']);
    expect(page.hasMore, isTrue, reason: 'totalCount 156 > 40');
  });

  test('S02 search with channel and official programs (new sample): each by its own rule', () {
    final page = NiconicoApi.directoryPage(_sample('S02-search-channel').body, page: 1, search: true);
    expect(page.rooms.map((room) => room.roomId), [
      'user/125403101',
      'user/120250928',
      'ch2611887',
      'ch2598539',
      'user/97422761',
      'user/2911071',
      'user/142379596',
      'ch2648540',
      'user/23062978',
      'user/347170',
      'user/127680016',
      'lv351362447',
    ]);
    expect(page.hasMore, isFalse, reason: 'totalCount 12');
    final byId = {for (final room in page.rooms) room.roomId: room};
    // Two channels of one provider stay two rooms; the name is 3.x's
    // provider name, the icon the channel's.
    expect(byId['ch2611887']!.nick, '有限会社阿部珈琲館');
    expect(byId['ch2598539']!.nick, '有限会社阿部珈琲館');
    expect(byId['ch2611887']!.avatar, endsWith('/channel-icon/128x128/ch2611887.jpg?1700056814'));
    // An official program has no supplier: the social group names it (3.x)
    // and it stays one program (watch/ch2525 is a 404).
    final official = byId['lv351362447']!;
    expect(official.nick, 'ニコニコニュース');
    expect(official.link, 'https://live.nicovideo.jp/watch/lv351362447');
    expect(official.restriction, LiveRestriction.none);
    expect(official.startedAt, DateTime.utc(2026, 9, 27, 15));
  });

  group('S03 watch pages', () {
    for (final (name, program, broadcaster) in [
      ('S03-watch-user-live', 'lv351482868', 'user/144846457'),
      ('S03-watch-program-live', 'lv351482868', 'user/144846457'),
      ('S03-watch-user-ended', 'lv351482791', 'user/138383030'),
      ('S03-watch-channel', 'lv351292489', 'ch2640864'),
    ]) {
      test('$name ($program) matches 3.x at every depth, as $broadcaster', () {
        final fixture = _sample(name);
        final legacy = fixture.legacy as Map<String, dynamic>;
        final watch = NiconicoApi.watch(fixture.body, roomId: program, status: fixture.status);
        final room = NiconicoApi.room(watch);
        final channel = broadcaster.startsWith('ch');
        for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
          final expected = legacy[depth] as Map<String, dynamic>;
          _expectParity(
            room.toJson()..['link'] = room.link,
            expected,
            // roomId, link (17-1): the broadcaster's room; notice (17-1): a
            // broadcaster's room has no "this program only" sentence;
            // avatar (17-1): a channel's room shows the channel's icon.
            changed: {'roomId', 'link', 'notice', if (channel) 'avatar'},
            reason: depth,
          );
          expect(expected['roomId'], program);
          expect(expected['notice'], endsWith(_v3ProgramScope));
          if (channel) expect(expected['avatar'], '');
        }
        expect(watch.programId, program);
        expect(watch.roomId, broadcaster);
        expect(room.roomId, broadcaster);
        expect(room.link, 'https://live.nicovideo.jp/watch/$broadcaster');
        expect(room.notice ?? '', isNot(contains('收藏对应本次节目')));
        expect(room.isLiveNow, legacy['getLiveStatus']);
        final seat = legacy['watch'] as Map<String, dynamic>;
        expect(watch.status.name, seat['status']);
        expect(watch.access.name, seat['access']);
        expect(watch.watchCount, seat['reportedWatchCount']);
        expect(watch.socket?.toString(), seat['webSocketUri']);
        expect(
          room.data,
          isA<NiconicoRoomData>()
              .having((data) => data.access, 'access', watch.access)
              .having((data) => data.programId, 'programId', program),
        );
        expect(jsonEncode(room.toJson()), isNot(contains('audience_token')), reason: 'the bootstrap is never stored');
      });
    }

    test('S03 user live, asked as the broadcaster (the page it was recorded from): the same room', () {
      final fixture = _sample('S03-watch-user-live');
      expect(fixture.url.path, '/watch/user/144846457');
      final byProgram = NiconicoApi.room(NiconicoApi.watch(fixture.body, roomId: 'lv351482868'));
      final byUser = NiconicoApi.room(NiconicoApi.watch(fixture.body, roomId: 'user/144846457'));
      expect(byUser.toJson(), byProgram.toJson());
      // M2.1 and 17-3, 17-5 on air.
      expect(byUser.startedAt, DateTime.utc(2026, 9, 27, 17, 42, 14), reason: 'program.beginTime');
      expect(byUser.restriction, LiveRestriction.none);
      expect(byUser.introduction, 'ニコニコ生放送アプリから番組放送中です');
      expect(byUser.danmakuData, const NiconicoDanmakuArgs(roomId: 'user/144846457', programId: 'lv351482868'));
      expect(byUser.notice, isNull, reason: 'on air, watchable, a broadcaster: nothing to say');
    });

    test("the list card's start is the watch page's (same program, milliseconds and seconds)", () {
      final cards = [
        ...NiconicoApi.directoryPage(_sample('S01-recent-common-p1').body, page: 1, search: false).rooms,
        ...NiconicoApi.directoryPage(_sample('S01-recent-face-p1').body, page: 1, search: false).rooms,
      ];
      for (final (sample, program) in [('S03-watch-user-live', 'lv351482868'), ('S03-watch-channel', 'lv351292489')]) {
        final detail = NiconicoApi.room(NiconicoApi.watch(_sample(sample).body, roomId: program));
        final card = cards.singleWhere((room) => room.roomId == detail.roomId);
        expect(card.startedAt, detail.startedAt, reason: sample);
        expect(card.startedAt, isNotNull);
      }
    });

    test('S03 channel: a paid program with a trial is watchable, not restricted; the channel icon', () {
      final watch = NiconicoApi.watch(_sample('S03-watch-channel').body, roomId: 'lv351292489');
      expect(watch.access, NiconicoAccess.allowed);
      expect(watch.paid, isTrue, reason: 'condition.payment "Ticket", program.payment');
      expect(watch.restriction, LiveRestriction.none, reason: 'the anonymous viewer watches its free part');
      expect(watch.streamError, isNull);
      expect(watch.socket!.queryParameters['frontend_id'], '9');
      expect(
        watch.avatar,
        'https://secure-dcdn.cdn.nimg.jp/comch/channel-icon/128x128/ch2640864.jpg?1785535320',
        reason: 'the channel supplier has no icons: the channel room shows the channel icon (17-1)',
      );
      expect(watch.cover, contains('w=640'), reason: 'no screenshot: the 640x360 thumbnail');
      final room = NiconicoApi.room(watch);
      expect((room.data! as NiconicoRoomData).paid, isTrue);
      expect(room.introduction, startsWith('差し入れでもらった味噌と自作バーニャカウダで野菜をたくさんたべるぞ！\n\n誕生日グッズ販売開始しました！\n'));
      expect(room.introduction, contains('https://krrnbot.booth.pm/items/8902754'), reason: 'the link text is kept');
      expect(room.introduction, isNot(contains('<')), reason: 'no tags');
      expect(room.introduction, isNot(contains('\n\n\n')));
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 13, 30));
    });

    test('S03 ended: offline, no seat, no start, restriction or comments; StreamUnavailable', () {
      final watch = NiconicoApi.watch(_sample('S03-watch-user-ended').body, roomId: 'lv351482791');
      expect(watch.status, NiconicoProgramStatus.ended);
      expect(watch.access, NiconicoAccess.denied, reason: 'canWatch false');
      expect(watch.socket, isNull);
      expect(watch.streamError, isA<StreamUnavailable>(), reason: 'the state is checked before the access');
      final room = NiconicoApi.room(watch);
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.startedAt, isNull);
      expect(room.restriction, isNull);
      expect(room.danmakuData, isNull);
      expect(room.introduction, '自己啓発、スキルアップ枠。ニコニコ生放送アプリから番組放送中です', reason: 'the last program');
    });

    test('S03 official (new sample): an official program stays its program', () {
      final fixture = _sample('S03-watch-official');
      final watch = NiconicoApi.watch(fixture.body, roomId: 'lv351173882');
      expect(watch.roomId, 'lv351173882', reason: 'providerType official, although the supplier is a channel');
      final room = NiconicoApi.room(watch);
      expect(room.roomId, 'lv351173882');
      expect(room.isLiveNow, isTrue);
      expect(room.nick, '株式会社ドワンゴ');
      expect(room.avatar, isEmpty, reason: 'as 3.x: the room is the program, not the channel');
      expect(room.notice, NiconicoApi.noticeText['niconico_program_scope'], reason: 'still this one program');
      expect(room.startedAt, DateTime.utc(2026, 9, 28, 1));
      expect(room.restriction, LiveRestriction.none);
      expect(room.introduction, startsWith('ニコニコユーザーみんなで競走馬を育成！レースデビューを目指します！\n『リアルダービースタリオン』\n'));
      expect(room.danmakuData, const NiconicoDanmakuArgs(roomId: 'lv351173882', programId: 'lv351173882'));
      expect(watch.socket!.path, '/wsapi/v2/watch/100332996381', reason: "an official program's seat path");
    });

    test("S03 official's channel (new sample): watch/ch shows the channel's own last program", () {
      // Recorded a minute after S03-watch-official: its social group's page
      // shows a 2025 channel program, not the official one on air, so an
      // official program cannot be followed as that channel.
      final watch = NiconicoApi.watch(_sample('S03-watch-official-channel').body, roomId: 'ch2627923');
      expect(watch.programId, 'lv348051859');
      expect(watch.roomId, 'ch2627923');
      expect(watch.status, NiconicoProgramStatus.ended);
      expect(NiconicoApi.room(watch).startedAt, isNull);
    });

    test('S03 channel ended (new sample): offline, paid, no seat, no restriction', () {
      final watch = NiconicoApi.watch(_sample('S03-watch-channel-ended').body, roomId: 'ch2640864');
      expect(watch.programId, 'lv351292489');
      expect(watch.status, NiconicoProgramStatus.ended);
      expect(watch.socket, isNull, reason: 'the page offers a time-shift seat; only a program on air is read');
      final room = NiconicoApi.room(watch);
      expect(room.roomId, 'ch2640864');
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.restriction, isNull);
      expect(room.danmakuData, isNull);
      expect(room.notice, isNull, reason: 'ended, and a broadcaster');
      expect((room.data! as NiconicoRoomData).paid, isTrue);
    });

    test('S03 not found: HTTP 404 is NotFound (3.x "missing")', () {
      final fixture = _sample('S03-watch-notfound');
      expect((fixture.legacy as Map)['getRoomDetail'], {'throws': 'NiconicoException', 'message': 'Niconico missing'});
      expect(() => NiconicoApi.watch('', roomId: 'lv1', status: fixture.status), throwsA(isA<NotFound>()));
      expect(() => NiconicoApi.watch('', roomId: 'user/1', status: fixture.status), throwsA(isA<NotFound>()));
    });

    test('asking one program and getting another is ApiChanged (3.x "identity")', () {
      expect(
        () => NiconicoApi.watch(_sample('S03-watch-user-live').body, roomId: 'lv351482869'),
        throwsA(isA<ApiChanged>()),
      );
    });

    for (final (sample, asked) in [
      ('S03-watch-user-live', 'user/144846458'),
      ('S03-watch-user-live', 'ch144846457'),
      ('S03-watch-channel', 'ch2640865'),
      ('S03-watch-channel', 'user/2640864'),
      ('S03-watch-official', 'user/2627923'),
      ('S03-watch-official-channel', 'ch2640864'),
    ]) {
      test("asking $asked and getting $sample's broadcaster is ApiChanged (17-1 identity)", () {
        expect(() => NiconicoApi.watch(_sample(sample).body, roomId: asked), throwsA(isA<ApiChanged>()));
      });
    }
  });

  group('room identity (17-1)', () {
    test('user, channel and program room ids', () {
      for (final id in ['user/1', 'user/${'9' * 19}', 'ch1', 'ch2640864', 'lv1']) {
        expect(NiconicoApi.isRoomId(id), isTrue, reason: id);
      }
      for (final id in [
        'user/0',
        'user/01',
        'user/',
        'user/1/2',
        'User/1',
        'ch0',
        'CH1',
        'ch',
        'co1',
        'lv0',
        '1',
        '',
      ]) {
        expect(NiconicoApi.isRoomId(id), isFalse, reason: id);
      }
      expect(NiconicoApi.isBroadcasterRoomId('user/1'), isTrue);
      expect(NiconicoApi.isBroadcasterRoomId('ch1'), isTrue);
      expect(NiconicoApi.isBroadcasterRoomId('lv1'), isFalse);
      expect(NiconicoApi.watchUrl('user/1'), 'https://live.nicovideo.jp/watch/user/1');
      expect(NiconicoApi.watchUrl('ch1'), 'https://live.nicovideo.jp/watch/ch1');
    });

    test('a program becomes its user, its channel, or stays itself', () {
      expect(NiconicoApi.roomIdOf(programId: 'lv1', providerType: 'community', userId: '144846457'), 'user/144846457');
      expect(NiconicoApi.roomIdOf(programId: 'lv1', providerType: 'community', userId: 144846457), 'user/144846457');
      expect(NiconicoApi.roomIdOf(programId: 'lv1', providerType: 'user', userId: '7'), 'user/7');
      expect(NiconicoApi.roomIdOf(programId: 'lv1', providerType: 'channel', channelId: 'ch2640864'), 'ch2640864');
      for (final (type, user, channel) in <(Object?, Object?, Object?)>[
        ('official', '7', 'ch2525'),
        ('community', null, null),
        ('community', '', null),
        ('community', '0', null),
        ('community', 'x7', null),
        ('channel', '7', null),
        ('channel', null, 'co7'),
        ('channel', null, 'ch0'),
        (null, '7', 'ch7'),
        ('unknown', '7', 'ch7'),
      ]) {
        expect(
          NiconicoApi.roomIdOf(programId: 'lv1', providerType: type, userId: user, channelId: channel),
          'lv1',
          reason: '$type $user $channel',
        );
      }
    });
  });

  test('S04 the recorded grant: qualities and the cookies of each path match 3.x', () {
    final legacy = Fixture.load('niconico', 'seat/S04-seat');
    final expected = legacy.legacy as Map<String, dynamic>;
    // The recorded session cookie expired at 2026-09-28 18:41 UTC: every
    // cookie lookup happens at the recording time, not now.
    final at = DateTime.parse(legacy.meta['capturedAt'] as String);
    final grant = NiconicoApi.grant(_recordedStream(), now: at);
    expect(grant.uri.toString(), expected['uri']);
    expect(grant.quality, expected['quality']);
    expect(grant.availableQualities, expected['availableQualities']);
    expect(grant.cookieCount, expected['retainedCookieCount']);
    final program = grant.uri.pathSegments[2];
    final headers = expected['cookieHeaderFor'] as Map<String, dynamic>;
    expect(grant.cookieHeaderFor(grant.uri, now: at), headers['master']);
    expect(grant.cookieHeaderFor(_media.resolve('/hls/segments/$program/video/1.cmfv'), now: at), headers['video']);
    expect(grant.cookieHeaderFor(_media.resolve('/hls/segments/$program/audio/1.cmfa'), now: at), headers['audio']);
    expect(
      grant.cookieHeaderFor(_media.resolve('/hls/keys/$program/${grant.uri.pathSegments[3]}/1.key'), now: at),
      headers['key'],
    );
    expect(grant.cookieHeaderFor(_media.resolve('/hls/keys/$program/1.key'), now: at), headers['sessionKey']);
    expect(
      grant.cookieHeaderFor(grant.uri, now: at)!.split('; '),
      hasLength(3),
      reason: 'one set per request (403 otherwise)',
    );
  });

  group("3.x's watch parser", () {
    test("an official program's socket path without `unama` is kept", () {
      final data = _watchFixture(
        socket: 'wss://a.live2.nicovideo.jp/wsapi/v2/watch/124619065117?audience_token=fixture',
      );
      final watch = NiconicoApi.watch(_page(data), roomId: 'lv100');
      expect(watch.socket!.path, '/wsapi/v2/watch/124619065117');
      expect(watch.socket!.queryParameters, {'audience_token': 'fixture', 'frontend_id': '9'});
    });

    test('attribute decoding keeps the identity, the text and the bootstrap', () {
      final data = _watchFixture();
      (data['program'] as Map)['title'] = '配信 "quoted" & <tag> \'it\'s\' a/b';
      final watch = NiconicoApi.watch(_page(data), roomId: 'lv100');
      expect(watch.programId, 'lv100');
      expect(watch.title, '配信 "quoted" & <tag> \'it\'s\' a/b');
      expect(watch.broadcaster, 'Fixture broadcaster');
      expect(watch.status, NiconicoProgramStatus.onAir);
      expect(watch.access, NiconicoAccess.allowed);
      expect(watch.socket!.queryParameters, {'audience_token': 'fixture', 'frontend_id': '9'});
      expect(watch.toString(), isNot(contains('audience_token')));
      expect(watch.streamError, isNull);
    });

    for (final (status, canWatch, region, state, access) in [
      ('ON_AIR', false, true, NiconicoProgramStatus.onAir, NiconicoAccess.regionRestricted),
      ('RELEASED', false, true, NiconicoProgramStatus.scheduled, NiconicoAccess.regionRestricted),
      ('ENDED', false, false, NiconicoProgramStatus.ended, NiconicoAccess.denied),
    ]) {
      test('$status keeps the broadcast state apart from the access', () {
        final watch = NiconicoApi.watch(
          _page(_watchFixture(status: status, canWatch: canWatch, region: region, socket: '')),
          roomId: 'lv100',
        );
        expect(watch.status, state);
        expect(watch.access, access);
        expect(watch.socket, isNull);
      });
    }

    test('a login requirement wins over canWatch and drops any offered socket', () {
      final data = _watchFixture(socket: 'wss://elsewhere.invalid/token');
      ((data['programWatch'] as Map)['condition'] as Map)['needLogin'] = true;
      final watch = NiconicoApi.watchData(data, roomId: 'lv100');
      expect(watch.access, NiconicoAccess.loginRequired);
      expect(watch.socket, isNull);
      expect(watch.streamError, isA<NeedsLogin>());
    });

    test('stream errors: region RegionBlocked, login and denied NeedsLogin, not on air StreamUnavailable', () {
      NiconicoWatch watch(NiconicoProgramStatus status, NiconicoAccess access) =>
          NiconicoWatch(programId: 'lv100', title: '', broadcaster: '', status: status, access: access);
      expect(watch(NiconicoProgramStatus.onAir, NiconicoAccess.regionRestricted).streamError, isA<RegionBlocked>());
      expect(watch(NiconicoProgramStatus.onAir, NiconicoAccess.loginRequired).streamError, isA<NeedsLogin>());
      expect(watch(NiconicoProgramStatus.onAir, NiconicoAccess.denied).streamError, isA<NeedsLogin>());
      expect(watch(NiconicoProgramStatus.scheduled, NiconicoAccess.allowed).streamError, isA<StreamUnavailable>());
      expect(watch(NiconicoProgramStatus.ended, NiconicoAccess.regionRestricted).streamError, isA<StreamUnavailable>());
    });

    test('the program identity is checked before the access gates', () {
      final data = _watchFixture(canWatch: false, region: true, socket: '');
      expect(() => NiconicoApi.watchData(data, roomId: 'lv101'), throwsA(isA<ApiChanged>()));
    });

    for (final (name, body) in [
      ('missing data', '<script>{"programId":"lv100"}</script>'),
      ('duplicate', _page(_watchFixture()) + _page(_watchFixture())),
      ('bad JSON', '<script id="embedded-data" data-props="bad"></script>'),
      ('oversized', 'x' * (NiconicoApi.responseLimit + 1)),
      ('oversized in UTF-8', '配' * (NiconicoApi.responseLimit ~/ 2)),
    ]) {
      test('$name HTML is ApiChanged, never a substituted program', () {
        expect(() => NiconicoApi.watch(body, roomId: 'lv100'), throwsA(isA<ApiChanged>()));
      });
    }

    test("the script's attributes may come in any order and quoting", () {
      final encoded = const HtmlEscape().convert(jsonEncode(_watchFixture()));
      final body =
          "<script data-props='${encoded.replaceAll('&#39;', '&apos;')}' type=\"application/json\" id=embedded-data>";
      expect(NiconicoApi.watch(body, roomId: 'lv100').title, 'Fixture 配信');
    });

    final mutations = <String, void Function(Map<String, dynamic>)>{
      'status': (data) => (data['program'] as Map)['status'] = 'MAYBE',
      'count': (data) => ((data['program'] as Map)['statistics'] as Map)['watchCount'] = -1,
      'count type': (data) => ((data['program'] as Map)['statistics'] as Map)['watchCount'] = '25',
      'canWatch': (data) => (data['userProgramWatch'] as Map).remove('canWatch'),
      'needLogin': (data) => ((data['programWatch'] as Map)['condition'] as Map)['needLogin'] = 0,
      'region': (data) => (data['userProgramWatch'] as Map).remove('isCountryRestrictionTarget'),
      'frontend': (data) => (data['site'] as Map)['frontendId'] = '9',
      'supplier': (data) => (data['program'] as Map).remove('supplier'),
      'title': (data) => (data['program'] as Map)['title'] = 42,
    };
    for (final MapEntry(:key, :value) in mutations.entries) {
      test('an unexpected $key is ApiChanged (3.x "schema")', () {
        final data = _watchFixture();
        value(data);
        expect(() => NiconicoApi.watchData(data, roomId: 'lv100'), throwsA(isA<ApiChanged>()));
      });
    }

    for (final socket in [
      'wss://a.live2.nicovideo.jp/other/wsapi/v2/watch/123?t=x',
      'wss://a.live2.nicovideo.jp/wsapi/v2/watch/123/../124?t=x',
      'wss://a.live2.nicovideo.jp/wsapi/v2/watch/123?t=x&t=y',
      'wss://a.live2.nicovideo.jp:443/wsapi/v2/watch/123?t=x',
      '',
      'https://a.live2.nicovideo.jp/unama/wsapi/v2/watch/123?t=x',
      'wss://a.live2.nicovideo.jp.evil.test/unama/wsapi/v2/watch/123?t=x',
      'wss://user@a.live2.nicovideo.jp/unama/wsapi/v2/watch/123?t=x',
      'wss://a.live2.nicovideo.jp/unama/wsapi/v2/watch/123?t=x&t=y',
      'wss://a.live2.nicovideo.jp/unama/wsapi/v2/watch/123/../124?t=x',
      'wss://a.live2.nicovideo.jp/unama/wsapi/v2/watch/123?t=x#fragment',
      'wss://a.live2.nicovideo.jp/unama/wsapi/v2/watch/123',
    ]) {
      test('an unverified socket "$socket" is ApiChanged', () {
        expect(() => NiconicoApi.watchData(_watchFixture(socket: socket), roomId: 'lv100'), throwsA(isA<ApiChanged>()));
      });
    }

    test('a null watch count stays unknown', () {
      final watch = NiconicoApi.watchData(_watchFixture(watchCount: null), roomId: 'lv100');
      expect(watch.watchCount, isNull);
      expect(NiconicoApi.room(watch).totalViewers, isEmpty);
    });

    for (final (status, error) in [
      (403, isA<RiskControl>()),
      (401, isA<RiskControl>()),
      (406, isA<RiskControl>()),
      (404, isA<NotFound>()),
      (429, isA<RateLimited>()),
      (503, isA<NetworkFailure>()),
      (302, isA<NetworkFailure>()),
      (400, isA<NetworkFailure>()),
    ]) {
      test('HTTP $status is an error, never an offline program', () {
        expect(
          () => NiconicoApi.watch(
            _page(_watchFixture(status: 'ENDED')),
            roomId: 'lv100',
            status: status,
          ),
          throwsA(error),
        );
      });
    }
  });

  group('artwork (3.x)', () {
    test('the live screenshot wins over the thumbnail; bad links fall back or drop', () {
      final data = _watchFixture();
      final program = data['program'] as Map<String, dynamic>;
      program['thumbnail'] = {
        'small': 'https://nicolive.cdn.nimg.jp/small.jpg',
        'huge': {'s640x360': 'https://listing-thumbnail.live.nicovideo.jp?image=fixture&w=640'},
      };
      (program['supplier'] as Map)['icons'] = {'uri150x150': 'https://secure-dcdn.cdn.nimg.jp/avatar.jpg'};
      var room = NiconicoApi.room(NiconicoApi.watchData(data, roomId: 'lv100'));
      expect(room.cover, contains('w=640'));
      expect(room.avatar, endsWith('/avatar.jpg'));
      program['screenshot'] = {
        'urlSet': {'middle': 'https://asset2.dlive.nicovideo.jp/fixture/thumbnail-640x360/screenshot.jpg'},
      };
      room = NiconicoApi.room(NiconicoApi.watchData(data, roomId: 'lv100'));
      expect(room.cover, contains('/thumbnail-640x360/screenshot.jpg'));
      program['screenshot'] = {
        'urlSet': {'middle': 'https://unrelated.example/image.jpg'},
      };
      program['thumbnail'] = {'large': 'https://nicolive.cdn.nimg.jp/cover.jpg'};
      room = NiconicoApi.room(NiconicoApi.watchData(data, roomId: 'lv100'));
      expect(room.cover, 'https://nicolive.cdn.nimg.jp/cover.jpg');
    });

    for (final bad in [
      null,
      42,
      'http://cdn.nimg.jp/a',
      'https://cdn.nimg.jp.evil.example/a',
      'https://name@cdn.nimg.jp/a',
      'https://cdn.nimg.jp:443/a',
      'https://cdn.nimg.jp/a#frag',
    ]) {
      test('a malformed image $bad drops the picture, not the live program', () {
        final data = _watchFixture();
        final program = data['program'] as Map<String, dynamic>;
        program['thumbnail'] = {'large': bad};
        (program['supplier'] as Map)['icons'] = {'uri150x150': bad};
        final room = NiconicoApi.room(NiconicoApi.watchData(data, roomId: 'lv100'));
        expect(room.isLiveNow, isTrue);
        expect(room.cover, isEmpty);
        expect(room.avatar, isEmpty);
      });
    }
  });

  group('room and notice', () {
    test("3.x's detail fields: cumulative visits, the program link, live only on air", () {
      final room = NiconicoApi.room(NiconicoApi.watchData(_watchFixture(), roomId: 'lv100'));
      expect(room.roomId, 'lv100');
      expect(room.platform, 'niconico');
      expect(room.totalViewers, '25');
      expect(room.onlineViewers, isEmpty);
      expect(room.audienceMetricType, AudienceMetricType.totalViewers);
      expect(room.link, 'https://live.nicovideo.jp/watch/lv100');
      expect(room.isLiveNow, isTrue);
      expect(jsonEncode(room.toJson()), isNot(contains('webSocket')));
    });

    test("the notice is 3.x's zh.json text for the state and the access, comments connected (M5.14)", () {
      const scope = '收藏对应本次节目，主播的新节目需重新添加。';
      expect(NiconicoApi.noticeText['niconico_program_scope'], scope);
      expect(_v3ProgramScope, startsWith(scope.substring(0, scope.length - 1)), reason: '3.x also said so');
      expect(NiconicoApi.noticeText.values.join(), isNot(contains('弹幕')), reason: 'no "comments not connected" left');
      expect(NiconicoApi.notice(NiconicoProgramStatus.onAir, NiconicoAccess.allowed), scope);
      expect(NiconicoApi.notice(NiconicoProgramStatus.scheduled, NiconicoAccess.regionRestricted), '节目尚未开始。 $scope');
      expect(NiconicoApi.notice(NiconicoProgramStatus.onAir, NiconicoAccess.regionRestricted), '此节目设有地区访问限制。 $scope');
      expect(NiconicoApi.notice(NiconicoProgramStatus.onAir, NiconicoAccess.loginRequired), '此节目要求登录官方站点。 $scope');
      expect(NiconicoApi.notice(NiconicoProgramStatus.onAir, NiconicoAccess.denied), '此节目的当前观看权限受限。 $scope');
      expect(NiconicoApi.notice(NiconicoProgramStatus.ended, NiconicoAccess.denied), scope);
    });

    test('a region-restricted program on air stays live with the notice (3.x)', () {
      final watch = NiconicoApi.watchData(_watchFixture(canWatch: false, region: true, socket: ''), roomId: 'lv100');
      final room = NiconicoApi.room(watch);
      expect(room.isLiveNow, isTrue);
      expect(room.notice, startsWith('此节目设有地区访问限制。'));
      expect((room.data! as NiconicoRoomData).access, NiconicoAccess.regionRestricted);
    });

    test("a broadcaster's room has no \"this program only\" sentence (17-1)", () {
      expect(NiconicoApi.notice(NiconicoProgramStatus.onAir, NiconicoAccess.allowed, program: false), isEmpty);
      expect(NiconicoApi.notice(NiconicoProgramStatus.ended, NiconicoAccess.denied, program: false), isEmpty);
      expect(NiconicoApi.notice(NiconicoProgramStatus.scheduled, NiconicoAccess.allowed, program: false), '节目尚未开始。');
      expect(
        NiconicoApi.notice(NiconicoProgramStatus.onAir, NiconicoAccess.loginRequired, program: false),
        '此节目要求登录官方站点。',
      );
    });
  });

  group('restrictions, start and comments (M2.1, 17-3)', () {
    /// A user's program on air, as the site writes it.
    Map<String, dynamic> userProgram() {
      final data = _watchFixture();
      final program = data['program'] as Map<String, dynamic>;
      program['providerType'] = 'community';
      program['beginTime'] = 1790530934;
      program['supplier'] = {'supplierType': 'user', 'name': 'Fixture broadcaster', 'programProviderId': '7'};
      return data;
    }

    test('a program on air an anonymous viewer may watch: none, its start and the comment arguments', () {
      final room = NiconicoApi.room(NiconicoApi.watchData(userProgram(), roomId: 'lv100'));
      expect(room.roomId, 'user/7');
      expect(room.restriction, LiveRestriction.none);
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 17, 42, 14));
      expect(room.danmakuData, const NiconicoDanmakuArgs(roomId: 'user/7', programId: 'lv100'));
      expect(const NiconicoDanmakuArgs(roomId: 'user/7', programId: 'lv100').toString(), contains('user/7'));
      expect(room.toJson()['restriction'], 'none');
      expect(room.toJson()['startedAt'], '2026-09-27T17:42:14.000Z');
    });

    for (final (name, change, restriction, error) in [
      (
        'region',
        (Map<String, dynamic> data) => (data['userProgramWatch'] as Map)['isCountryRestrictionTarget'] = true,
        LiveRestriction.regionBlocked,
        isA<RegionBlocked>(),
      ),
      (
        'login',
        (Map<String, dynamic> data) => ((data['programWatch'] as Map)['condition'] as Map)['needLogin'] = true,
        LiveRestriction.needsLogin,
        isA<NeedsLogin>(),
      ),
      (
        'denied',
        (Map<String, dynamic> data) => (data['userProgramWatch'] as Map)['canWatch'] = false,
        LiveRestriction.needsLogin,
        isA<NeedsLogin>(),
      ),
      (
        'private',
        (Map<String, dynamic> data) {
          (data['userProgramWatch'] as Map)['canWatch'] = false;
          (data['program'] as Map)['isPrivate'] = true;
        },
        LiveRestriction.private,
        isA<StreamUnavailable>().having((e) => e.detail, 'detail', contains('private')),
      ),
      (
        'paid (ticket)',
        (Map<String, dynamic> data) {
          (data['userProgramWatch'] as Map)['canWatch'] = false;
          ((data['programWatch'] as Map)['condition'] as Map)['payment'] = 'Ticket';
        },
        LiveRestriction.paid,
        isA<StreamUnavailable>().having((e) => e.detail, 'detail', contains('paid')),
      ),
      (
        'paid (membership)',
        (Map<String, dynamic> data) {
          (data['userProgramWatch'] as Map)['canWatch'] = false;
          (data['program'] as Map)['payment'] = {'ticketAgencyPageUrl': 'https://ch.nicovideo.jp/ch1/live/lv100'};
        },
        LiveRestriction.paid,
        isA<StreamUnavailable>().having((e) => e.detail, 'detail', contains('paid')),
      ),
      (
        'followers only',
        (Map<String, dynamic> data) {
          (data['userProgramWatch'] as Map)['canWatch'] = false;
          (data['program'] as Map)['isFollowerOnly'] = true;
        },
        LiveRestriction.subscribersOnly,
        isA<StreamUnavailable>().having((e) => e.detail, 'detail', contains('followers')),
      ),
    ]) {
      test('a $name program on air is live, marked, and its stream says why', () {
        final data = userProgram();
        change(data);
        final watch = NiconicoApi.watchData(data, roomId: 'user/7');
        final room = NiconicoApi.room(watch);
        expect(room.isLiveNow, isTrue);
        expect(room.followGroup, FollowGroup.live);
        expect(room.restriction, restriction);
        expect(watch.streamError, error);
        expect(watch.socket, isNull, reason: 'no seat bootstrap is read for a restricted program');
        expect(room.danmakuData, isNull, reason: 'no seat can be opened');
        expect(room.startedAt, isNotNull);
      });
    }

    test('offline programs have no start or restriction, whatever the page says', () {
      for (final status in ['ENDED', 'RELEASED']) {
        final data = userProgram();
        (data['program'] as Map)['status'] = status;
        (data['userProgramWatch'] as Map)['canWatch'] = false;
        (data['program'] as Map)['isPrivate'] = true;
        final room = NiconicoApi.room(NiconicoApi.watchData(data, roomId: 'lv100'));
        expect(room.isLiveNow, isFalse);
        expect(room.startedAt, isNull, reason: status);
        expect(room.restriction, isNull, reason: status);
        expect(room.toJson().containsKey('restriction'), isFalse);
      }
    });

    test('starts: milliseconds and seconds within 2001–2286, anything else unknown', () {
      expect(NiconicoApi.startedAtMilliseconds(1790515800000), DateTime.utc(2026, 9, 27, 13, 30));
      expect(NiconicoApi.startedAtSeconds(1790515800), DateTime.utc(2026, 9, 27, 13, 30));
      for (final bad in [null, 0, -1, '1790515800000', 1790515800.5, 1790515800]) {
        expect(NiconicoApi.startedAtMilliseconds(bad), isNull, reason: '$bad');
      }
      for (final bad in [null, 0, -1, '1790515800', 1790515800000]) {
        expect(NiconicoApi.startedAtSeconds(bad), isNull, reason: '$bad');
      }
      final data = userProgram();
      (data['program'] as Map)['beginTime'] = 0;
      expect(NiconicoApi.room(NiconicoApi.watchData(data, roomId: 'lv100')).startedAt, isNull);
    });

    test('list rows: paid, followers only, none, or unknown without the flags', () {
      Map<String, dynamic> page(Map<String, dynamic> row, {bool search = false}) =>
          _envelope(search: search, rows: [row]);
      LiveRestriction? restrictionOf(Map<String, dynamic> row, {bool search = false}) => NiconicoApi.directoryPage(
        jsonEncode(page(row, search: search)),
        page: 1,
        search: search,
      ).rooms.single.restriction;
      expect(restrictionOf(_row()), isNull, reason: "3.x's test row has no flags");
      expect(
        restrictionOf(
          _row()
            ..['isPayProgram'] = false
            ..['isFollowerOnly'] = false,
        ),
        LiveRestriction.none,
      );
      expect(
        restrictionOf(
          _row()
            ..['isPayProgram'] = true
            ..['isFollowerOnly'] = false,
        ),
        LiveRestriction.paid,
      );
      expect(
        restrictionOf(
          _row()
            ..['isPayProgram'] = false
            ..['isFollowerOnly'] = true,
        ),
        LiveRestriction.subscribersOnly,
      );
      expect(
        restrictionOf(
          _row(search: true)
            ..['payment'] = true
            ..['isFollowerOnly'] = false,
          search: true,
        ),
        LiveRestriction.paid,
      );
      expect(
        restrictionOf(
          _row(search: true)
            ..['payment'] = false
            ..['isFollowerOnly'] = false,
          search: true,
        ),
        LiveRestriction.none,
      );
    });
  });

  group('introduction (17-5)', () {
    for (final (html, text) in [
      ('ニコニコ生放送アプリから番組放送中です', 'ニコニコ生放送アプリから番組放送中です'),
      ('plain\ntext\n\n\n\nkept', 'plain\ntext\n\nkept'),
      ('a<br>b<br />c<BR/>d', 'a\nb\nc\nd'),
      ('source\nlayout<br>only', 'source layout\nonly'),
      ('<b>bold</b> &amp; <a href="https://x.test">link</a>', 'bold & link'),
      ('<p>one</p><p>two</p>', 'one\ntwo'),
      ('x<br><br><br><br>y', 'x\n\ny'),
      ('   ', null),
      ('<br />', null),
    ]) {
      test('"$html" as text', () => expect(NiconicoApi.plainText(html), text));
    }

    test('a missing or non-string description is none', () {
      expect(NiconicoApi.plainText(null), isNull);
      expect(NiconicoApi.plainText(42), isNull);
      final room = NiconicoApi.room(NiconicoApi.watchData(_watchFixture(), roomId: 'lv100'));
      expect(room.introduction, isNull, reason: "3.x's fixture has no description");
    });
  });

  group("3.x's directory parser", () {
    for (final search in [false, true]) {
      test('${search ? 'search' : 'recent'} keeps identities, artwork and cumulative audience only', () {
        final page = NiconicoApi.directoryPage(jsonEncode(_envelope(search: search)), page: 1, search: search);
        final room = page.rooms.single;
        // 3.x's recent row names its provider (a user): the user's room
        // (17-1); its search row does not, so it stays the program.
        final id = search ? 'lv100' : 'user/1';
        expect(room.roomId, id);
        expect(room.liveStatus, LiveStatus.live);
        expect(room.title, '公開ライブ & game');
        expect(room.totalViewers, '12');
        expect(room.onlineViewers, isEmpty);
        expect(room.audienceMetricType, AudienceMetricType.totalViewers);
        expect(room.cover, 'https://asset2.dlive.nicovideo.jp/screenshot.jpg');
        expect(room.avatar, 'https://secure-dcdn.cdn.nimg.jp/icon.jpg');
        expect(room.link, 'https://live.nicovideo.jp/watch/$id');
        expect(page.hasMore, isFalse);
        expect(page.rooms.clear, throwsUnsupportedError);
        expect(jsonEncode(room.toJson()), isNot(contains('commentCount')));
      });
    }

    test('paging follows totalCount, not the number of rows', () {
      expect(
        NiconicoApi.directoryPage(jsonEncode(_envelope(rows: [], total: 71)), page: 1, search: false).hasMore,
        isTrue,
      );
      expect(NiconicoApi.directoryPage(jsonEncode(_envelope(total: 140)), page: 2, search: false).hasMore, isFalse);
      expect(
        NiconicoApi.directoryPage(jsonEncode(_envelope(search: true, total: 81)), page: 2, search: true).hasMore,
        isTrue,
      );
    });

    test('a bad optional picture or an unknown audience keeps the card', () {
      final row = _row()
        ..['statistics'] = {'watchCount': null}
        ..['flippedListingThumbnail'] = 'https://evil.invalid/a';
      final room = NiconicoApi.directoryPage(jsonEncode(_envelope(rows: [row])), page: 1, search: false).rooms.single;
      expect(room.cover, startsWith('https://listing-thumbnail.live.nicovideo.jp'));
      expect(room.totalViewers, isEmpty);
    });

    test('without a supplier the social group names the card (3.x)', () {
      final row = _row(search: true)
        ..remove('supplier')
        ..['providerType'] = 'official'
        ..['socialGroup'] = {'name': 'Channel', 'thumbnailUrl': 'https://secure-dcdn.cdn.nimg.jp/channel.jpg'};
      final room = NiconicoApi.directoryPage(
        jsonEncode(_envelope(search: true, rows: [row])),
        page: 1,
        search: true,
      ).rooms.single;
      expect(room.nick, 'Channel');
      expect(room.avatar, endsWith('/channel.jpg'));
    });

    test('an empty provider icon falls back to the social group (3.x left the card without one)', () {
      final row = _row()
        ..['providerType'] = 'channel'
        ..['programProvider'] = {'name': 'くるる!!', 'icon': ''}
        ..['socialGroup'] = {'id': 'ch1', 'name': 'くるる幼稚園', 'thumbnailUrl': 'https://secure-dcdn.cdn.nimg.jp/ch1.jpg'};
      final room = NiconicoApi.directoryPage(jsonEncode(_envelope(rows: [row])), page: 1, search: false).rooms.single;
      expect(room.nick, 'くるる!!');
      expect(room.avatar, 'https://secure-dcdn.cdn.nimg.jp/ch1.jpg');
    });

    final mutations = <String, void Function(Map<String, dynamic>)>{
      'missing envelope': (data) => data.remove('meta'),
      'bad total': (data) => (data['meta'] as Map)['totalCount'] = '1',
      'missing total': (data) => (data['meta'] as Map).remove('totalCount'),
      'negative count': (data) => (((data['data'] as List)[0] as Map)['statistics'] as Map)['watchCount'] = -1,
      'wrong status': (data) => ((data['data'] as List)[0] as Map)['liveCycle'] = 'ENDED',
      'wrong provider': (data) => ((data['data'] as List)[0] as Map)['providerType'] = 'unknown',
      'missing title': (data) => ((data['data'] as List)[0] as Map).remove('title'),
      'blank title': (data) => ((data['data'] as List)[0] as Map)['title'] = '  ',
      'missing attribution': (data) => ((data['data'] as List)[0] as Map).remove('programProvider'),
      'bad program id': (data) => ((data['data'] as List)[0] as Map)['id'] = 'lv0',
      'too many rows': (data) {
        (data['meta'] as Map)['totalCount'] = 71;
        data['data'] = [for (var i = 0; i < 71; i++) _row(id: i + 1)];
      },
      'total smaller than rows': (data) => (data['meta'] as Map)['totalCount'] = 0,
    };
    for (final MapEntry(:key, :value) in mutations.entries) {
      test('a malformed page ($key) is ApiChanged as a whole (3.x "schema")', () {
        final data = _envelope();
        value(data);
        expect(() => NiconicoApi.directoryPage(jsonEncode(data), page: 1, search: false), throwsA(isA<ApiChanged>()));
      });
    }

    for (final link in [
      'https://live.nicovideo.jp/watch/lv101',
      'https://live.nicovideo.jp.evil.invalid/watch/lv100',
    ]) {
      test('a row linking elsewhere ($link) is ApiChanged (3.x "identity")', () {
        final row = _row()..['watchPageUrl'] = link;
        expect(
          () => NiconicoApi.directoryPage(jsonEncode(_envelope(rows: [row])), page: 1, search: false),
          throwsA(isA<ApiChanged>()),
        );
      });
    }

    test('a bare program id as the watch link is accepted (3.x parseInput)', () {
      final row = _row()..['watchPageUrl'] = 'lv100';
      expect(NiconicoApi.directoryPage(jsonEncode(_envelope(rows: [row])), page: 1, search: false).rooms, hasLength(1));
    });

    test('one card per room: a second program of the same broadcaster is left out (17-1)', () {
      final second = _row(id: 101)..['title'] = 'second';
      final page = NiconicoApi.directoryPage(
        jsonEncode(_envelope(rows: [_row(), second, _row()], total: 3)),
        page: 1,
        search: false,
      );
      expect(page.rooms.map((room) => room.roomId), ['user/1']);
      expect(page.rooms.single.title, '公開ライブ & game', reason: 'the first one stays');
    });

    test('a bad row only drops itself; the page fails only when every row is bad (17-4)', () {
      Map<String, dynamic> user(int id) => _row(id: id)..['programProvider'] = {'id': '$id', 'name': 'U$id'};
      final rows = [
        user(1),
        user(2)..remove('title'),
        user(3)..['liveCycle'] = 'ENDED',
        user(4)..['providerType'] = 'unknown',
        user(5)..['watchPageUrl'] = 'https://live.nicovideo.jp/watch/lv6',
        user(6)..['id'] = 'lv0',
        user(7)..['statistics'] = {'watchCount': -1},
        'not a row',
        user(8)..['programProvider'] = {'id': '8'},
        user(9),
      ];
      final page = NiconicoApi.directoryPage(jsonEncode(_envelope(rows: rows, total: 10)), page: 1, search: false);
      expect(page.rooms.map((room) => room.roomId), ['user/1', 'user/9']);
      expect(
        () => NiconicoApi.directoryPage(
          jsonEncode(_envelope(rows: [rows[1], rows[2], rows[7]], total: 3)),
          page: 1,
          search: false,
        ),
        throwsA(isA<ApiChanged>().having((error) => error.detail, 'detail', contains('every recent row'))),
      );
      final search = _row(search: true)..remove('title');
      expect(
        NiconicoApi.directoryPage(
          jsonEncode(_envelope(search: true, rows: [search, _row(search: true, id: 101)], total: 2)),
          page: 1,
          search: true,
        ).rooms.map((room) => room.roomId),
        ['lv101'],
      );
      expect(
        NiconicoApi.directoryPage(jsonEncode(_envelope(rows: [], total: 0)), page: 1, search: false).rooms,
        isEmpty,
        reason: 'an empty page is no malformed page',
      );
    });

    test('an error envelope is a failed service, not an empty directory', () {
      final data = _envelope();
      (data['meta'] as Map)['errorCode'] = 'FAILED';
      expect(() => NiconicoApi.directoryPage(jsonEncode(data), page: 1, search: false), throwsA(isA<NetworkFailure>()));
    });

    for (final body in ['not-json', '[]', ' ' * (NiconicoApi.responseLimit + 1)]) {
      test('an invalid body of ${body.length} characters is ApiChanged', () {
        expect(() => NiconicoApi.directoryPage(body, page: 1, search: false), throwsA(isA<ApiChanged>()));
      });
    }

    for (final (status, error) in [
      (403, isA<RiskControl>()),
      (429, isA<RateLimited>()),
      (503, isA<NetworkFailure>()),
      (400, isA<NetworkFailure>()),
      (404, isA<ApiChanged>()),
    ]) {
      test('HTTP $status is an error, never an empty page', () {
        expect(
          () => NiconicoApi.directoryPage(jsonEncode(_envelope()), page: 1, search: false, status: status),
          throwsA(error),
        );
      });
    }
  });

  group("3.x's stream grant", () {
    test('six declared qualities and thirteen path cookies stay separate', () {
      final at = DateTime.utc(2026, 9, 10);
      final grant = NiconicoApi.grant(_stream(), now: at);
      expect(grant.availableQualities, [
        'abr',
        'super_high',
        '1.5Mbps480p30fps',
        '480kbps288p30fps',
        'audio_high',
        'audio_only',
      ]);
      expect(grant.cookieCount, 13);
      expect(
        grant.cookieHeaderFor(grant.uri, now: at),
        'CloudFront-Policy=fixture-1; CloudFront-Signature=fixture-2; CloudFront-Key-Pair-Id=fixture-3',
      );
      expect(
        grant.cookieHeaderFor(_media.resolve('/hls/segments/fixture-program/video/a.ts'), now: at),
        contains('fixture-4'),
      );
      expect(
        grant.cookieHeaderFor(_media.resolve('/hls/segments/fixture-program/audio/a.ts'), now: at),
        contains('fixture-7'),
      );
      final key = _media.resolve('/hls/keys/fixture-program/fixture-session/key');
      expect(grant.cookieHeaderFor(key, now: at), startsWith('CloudFront-Policy=fixture-10'));
      expect(grant.cookieHeaderFor(key, now: at), endsWith('session=fixture-0'), reason: 'longest path first');
      expect(grant.availableQualities.clear, throwsUnsupportedError);
    });

    test('cookies stay on the exact https media origin and whole path segments', () {
      final grant = NiconicoApi.grant(_stream());
      for (final target in [
        'http://livedelivery.dlive.nicovideo.jp/hls/keys/fixture-program/key',
        'https://livedelivery.dlive.nicovideo.jp:8443/hls/keys/fixture-program/key',
        'https://other.nicovideo.jp/hls/keys/fixture-program/key',
        'https://child.livedelivery.dlive.nicovideo.jp/hls/keys/fixture-program/key',
        'https://livedelivery.dlive.nicovideo.jp/hls/keys/fixture-program-extra/key',
        'https://livedelivery.dlive.nicovideo.jp/HLS/keys/fixture-program/key',
        'https://user@livedelivery.dlive.nicovideo.jp/hls/keys/fixture-program/key',
        'https://livedelivery.dlive.nicovideo.jp/hls/keys/fixture-program/key#fragment',
        'wss://livedelivery.dlive.nicovideo.jp/hls/keys/fixture-program/key',
      ]) {
        expect(grant.cookieHeaderFor(Uri.parse(target)), isNull, reason: target);
      }
    });

    test('an HTTP-date expiry is honoured; revoking drops the cookies', () {
      final now = DateTime.utc(2026, 9, 10);
      final data = _stream();
      ((data['cookies'] as List)[0] as Map)['expires'] = 'Thu, 10 Sep 2026 00:00:01 GMT';
      final grant = NiconicoApi.grant(data, now: now);
      final key = _media.resolve('/hls/keys/fixture-program/key');
      expect(grant.cookieHeaderFor(key, now: now), 'session=fixture-0');
      expect(grant.cookieHeaderFor(key, now: now.add(const Duration(seconds: 1))), isNull);
      expect(NiconicoApi.grant(data, now: now.add(const Duration(seconds: 1))).cookieCount, 12);
      grant.revoke();
      expect(grant.cookieCount, 0);
      expect(grant.isActive, isFalse);
      expect(() => grant.cookieHeaderFor(grant.uri), throwsA(isA<StreamUnavailable>()));
      expect(grant.toString(), isNot(contains('fixture-')));
    });

    final mutations = <String, void Function(Map<String, dynamic>)>{
      'protocol': (data) => data['protocol'] = 'dash',
      'quality': (data) => data['quality'] = 'unknown',
      'qualities': (data) => data['availableQualities'] = [42],
      'duplicate quality': (data) => data['availableQualities'] = ['abr', 'abr'],
      'missing cookies': (data) => data.remove('cookies'),
      'cookie count': (data) => data['cookies'] = List.filled(65, (data['cookies'] as List)[0]),
      'cookie size': (data) => ((data['cookies'] as List)[0] as Map)['value'] = 'x' * 5000,
      'aggregate size': (data) {
        for (final cookie in (data['cookies'] as List).cast<Map<String, dynamic>>()) {
          cookie['value'] = 'x' * 2000;
        }
      },
      'duplicate cookie': (data) =>
          (data['cookies'] as List).add(<String, dynamic>{...(data['cookies'] as List)[0] as Map<String, dynamic>}),
    };
    for (final MapEntry(:key, :value) in mutations.entries) {
      test('a malformed or over-budget $key is ApiChanged as a whole', () {
        final data = _stream();
        value(data);
        expect(() => NiconicoApi.grant(data), throwsA(isA<ApiChanged>()));
      });
    }

    for (final (field, value) in [
      ('domain', 'evil.test'),
      ('secure', false),
      ('path', '/'),
      ('path', '/hls/key;inject=x'),
      ('name', 'bad name'),
      ('name', '__Host-domain-not-allowed'),
      ('value', 'v; injected=x'),
      ('value', 'v\r\nHeader: x'),
      ('expires', 'bad-date'),
      ('expires', 42),
    ]) {
      test('a cookie with $field=$value is ApiChanged', () {
        final data = _stream();
        ((data['cookies'] as List).last as Map)[field] = value;
        expect(() => NiconicoApi.grant(data), throwsA(isA<ApiChanged>()));
      });
    }

    for (final uri in [
      'http://livedelivery.dlive.nicovideo.jp/hls/playlists/a/master.m3u8',
      'https://evil.test/hls/playlists/a/master.m3u8',
      'https://user@livedelivery.dlive.nicovideo.jp/hls/playlists/a/master.m3u8',
      'https://livedelivery.dlive.nicovideo.jp:8443/hls/playlists/a/master.m3u8',
      'https://livedelivery.dlive.nicovideo.jp/hls/playlists/a/../master.m3u8',
      'https://livedelivery.dlive.nicovideo.jp/hls/playlists/a/master.m3u8#token',
      'https://livedelivery.dlive.nicovideo.jp/hls/segments/a/master.m3u8',
    ]) {
      test('an unverified media target $uri is ApiChanged', () {
        expect(() => NiconicoApi.grant(_stream()..['uri'] = uri), throwsA(isA<ApiChanged>()));
      });
    }

    test('HTTP dates: RFC 1123 only, real days only', () {
      expect(NiconicoApi.parseHttpDate('Mon, 28 Sep 2026 18:41:00 GMT'), DateTime.utc(2026, 9, 28, 18, 41));
      expect(NiconicoApi.parseHttpDate('Mon, 30 Feb 2026 18:41:00 GMT'), isNull);
      expect(NiconicoApi.parseHttpDate('Mon, 28 Foo 2026 18:41:00 GMT'), isNull);
      expect(NiconicoApi.parseHttpDate('2026-09-28T18:41:00Z'), isNull);
    });
  });

  group('seat messages', () {
    test('keepIntervalSec is 1–300 seconds', () {
      expect(NiconicoApi.seatInterval({'keepIntervalSec': 30}), 30);
      for (final bad in [0, -1, 301, '30', null]) {
        expect(() => NiconicoApi.seatInterval({'keepIntervalSec': bad}), throwsA(isA<ApiChanged>()), reason: '$bad');
      }
    });

    test('error codes become typed errors (3.x only knew "session error")', () {
      expect(NiconicoApi.seatError({'code': 'NO_PERMISSION'}), isA<NeedsLogin>());
      expect(NiconicoApi.seatError({'code': 'TICKET_REQUIRED'}), isA<NeedsLogin>());
      expect(NiconicoApi.seatError({'code': 'TOO_MANY_CONNECTIONS'}), isA<RateLimited>());
      expect(NiconicoApi.seatError({'code': 'INVALID_MESSAGE'}), isA<ApiChanged>());
      expect(NiconicoApi.seatError({'code': 'unknown'}), isA<StreamUnavailable>());
      expect(NiconicoApi.seatError(null), isA<StreamUnavailable>());
      expect(NiconicoApi.seatDisconnect({'reason': 'END_PROGRAM'}).detail, contains('END_PROGRAM'));
    });

    test("a seat that ended with its program (M5.F): END_PROGRAM's disconnect only", () {
      expect(NiconicoApi.isProgramEnd(NiconicoApi.seatDisconnect({'reason': 'END_PROGRAM'})), isTrue);
      for (final other in [
        NiconicoApi.seatDisconnect({'reason': 'TAKEOVER'}),
        NiconicoApi.seatDisconnect({'reason': 'END_PROGRAMME'}),
        NiconicoApi.seatDisconnect(null),
        NiconicoApi.seatError({'code': 'END_PROGRAM'}),
        const StreamUnavailable('twitch', 'seat disconnect END_PROGRAM'),
        const NetworkFailure('niconico', 'seat disconnect END_PROGRAM'),
        'seat disconnect END_PROGRAM',
        null,
      ]) {
        expect(NiconicoApi.isProgramEnd(other), isFalse, reason: '$other');
      }
    });
  });

  group("3.x's quality catalog", () {
    final source = _media.resolve('/hls/playlists/fixture-program/fixture-session/master.m3u8');

    test("the actual size and bitrate pairs, highest first, with 3.x's labels", () {
      final qualities = NiconicoApi.qualities(_officialMaster, source: source, programId: 'lv100');
      expect(qualities.map((quality) => quality.selectionId), ['800x450@1080800', '512x288@412800', '512x288@201600']);
      expect(qualities.map((quality) => quality.quality), [
        '800×450 · 1080800 bps',
        '512×288 · 412800 bps',
        '512×288 · 201600 bps',
      ]);
      final choice = qualities.last.data! as NiconicoQuality;
      expect(choice.programId, 'lv100');
      expect(choice.resolution, '512x288');
      expect(choice.bandwidth, 201600);
      expect(jsonEncode([for (final quality in qualities) quality.toString()]), isNot(contains('https://')));
      expect(qualities.clear, throwsUnsupportedError);
      expect(choice.roomId, 'lv100', reason: 'a program room by default');
    });

    test("a broadcaster's qualities are bound to the room and the program on air (17-1); ids unchanged", () {
      final qualities = NiconicoApi.qualities(_officialMaster, source: source, programId: 'lv100', roomId: 'user/7');
      expect(qualities.map((quality) => quality.selectionId), ['800x450@1080800', '512x288@412800', '512x288@201600']);
      final choice = qualities.first.data! as NiconicoQuality;
      expect(choice.roomId, 'user/7');
      expect(choice.programId, 'lv100');
      expect(
        choice,
        isNot(const NiconicoQuality(programId: 'lv100', width: 800, height: 450, bandwidth: 1080800)),
        reason: 'another room',
      );
      expect(
        choice,
        const NiconicoQuality(programId: 'lv100', roomId: 'user/7', width: 800, height: 450, bandwidth: 1080800),
      );
    });

    for (final (name, master) in [
      ('missing resolution', _officialMaster.replaceFirst('RESOLUTION=800x450,', '')),
      ('duplicate selector', _officialMaster.replaceFirst('BANDWIDTH=201600', 'BANDWIDTH=412800')),
      (
        'several audio choices',
        _officialMaster.replaceFirst(
          '#EXT-X-STREAM-INF:',
          '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="trial-audio-192Kbps",NAME="Other",URI="other.m3u8"\n#EXT-X-STREAM-INF:',
        ),
      ),
      ('empty response', ''),
    ]) {
      test('$name is ApiChanged (3.x "schema"), never an unplayable row', () {
        expect(() => NiconicoApi.qualities(master, source: source, programId: 'lv100'), throwsA(isA<ApiChanged>()));
      });
    }

    for (final (status, error) in [
      (403, isA<RiskControl>()),
      (404, isA<StreamUnavailable>()),
      (429, isA<RateLimited>()),
      (502, isA<NetworkFailure>()),
      (302, isA<ApiChanged>()),
    ]) {
      test('a master answered with HTTP $status is an error', () {
        expect(
          () => NiconicoApi.qualities(_officialMaster, source: source, programId: 'lv100', status: status),
          throwsA(error),
        );
      });
    }
  });

  group('recipe', () {
    test("3.x's identity; a bandwidth needs a resolution", () {
      expect(
        NiconicoInputRecipe(programId: 'lv100', resolution: '512x288', bandwidth: 201600).identity,
        'niconico:lv100:512x288:201600',
      );
      expect(NiconicoInputRecipe(programId: 'lv100', resolution: null).identity, 'niconico:lv100:auto:auto');
      expect(() => NiconicoInputRecipe(programId: 'lv100', resolution: null, bandwidth: 1), throwsArgumentError);
      expect(() => NiconicoInputRecipe(programId: 'lv100', resolution: '1x1', bandwidth: 0), throwsArgumentError);
      expect(() => NiconicoInputRecipe(programId: '100', resolution: null), throwsArgumentError);
    });
  });

  group("links (3.x's, and 17-2)", () {
    for (final url in [
      'https://live.nicovideo.jp/watch/lv100',
      'https://live.nicovideo.jp/watch/lv100?ref=share#player',
      '  https://live.nicovideo.jp/watch/lv100  ',
      'https://live.nicovideo.jp/watch/lv100?ref=top',
      // 17-2: http, the old mobile site and the app's share link.
      'http://live.nicovideo.jp/watch/lv100',
      'https://sp.live.nicovideo.jp/watch/lv100',
      'https://sp.live.nicovideo.jp/watch/lv100?ref=sp_share',
      'https://nico.ms/lv100',
      'http://nico.ms/lv100?ref=app#x',
    ]) {
      test('a program link "$url" is the program', () {
        expect(NiconicoApi.programIdFromUrl(url), 'lv100');
        expect(NiconicoApi.broadcasterRoomIdFromUrl(url), isNull);
      });
    }

    for (final (url, room) in [
      ('https://live.nicovideo.jp/watch/user/144846457', 'user/144846457'),
      ('http://live.nicovideo.jp/watch/user/144846457?ref=x#y', 'user/144846457'),
      ('https://sp.live.nicovideo.jp/watch/user/144846457', 'user/144846457'),
      ('https://live.nicovideo.jp/watch/ch2640864', 'ch2640864'),
      ('https://www.nicovideo.jp/user/144846457', 'user/144846457'),
      ('http://www.nicovideo.jp/user/144846457', 'user/144846457'),
      ('https://nicovideo.jp/user/144846457/live_programs', 'user/144846457'),
      ('https://sp.nicovideo.jp/user/144846457', 'user/144846457'),
      ('https://ch.nicovideo.jp/ch2640864', 'ch2640864'),
      ('https://ch.nicovideo.jp/ch2640864/live', 'ch2640864'),
      ('https://ch.nicovideo.jp/channel/ch2640864', 'ch2640864'),
    ]) {
      test('a broadcaster link "$url" is $room (17-2)', () {
        expect(NiconicoApi.broadcasterRoomIdFromUrl(url), room);
        expect(NiconicoApi.programIdFromUrl(url), isNull);
      });
    }

    for (final url in [
      'lv100',
      'user/1',
      'https://live.nicovideo.jp.evil.invalid/watch/lv100',
      'https://evil@live.nicovideo.jp/watch/lv100',
      'https://live.nicovideo.jp:443/watch/lv100',
      'https://live.nicovideo.jp/watch/%6cv100',
      'https://live.nicovideo.jp/watch/other/../lv100',
      'https://live.nicovideo.jp/watch/lv100/..',
      'https://live.nicovideo.jp/watch/lv0',
      'https://live.nicovideo.jp/watch/lv100/',
      'https://live.nicovideo.jp/user/100',
      'https://live.nicovideo.jp/watch/user/0',
      'https://live.nicovideo.jp/watch/user/1/2',
      'https://live.nicovideo.jp/watch/co100',
      'https://live.nicovideo.jp/watch/CH100',
      'https://live.nicovideo.jp/search?keyword=lv100',
      'https://asset2.dlive.nicovideo.jp/master.m3u8',
      'https://nico.ms/sm9',
      'https://nico.ms/lv100/x',
      'https://nico.ms.evil.invalid/lv100',
      'https://ch.nicovideo.jp/kurunn',
      'https://ch.nicovideo.jp/ch2640864/live/lv351292489/x',
      'https://www.nicovideo.jp/watch/sm9',
      'https://www.nicovideo.jp/user/0',
      'https://evil.nicovideo.jp/user/1',
      'ftp://live.nicovideo.jp/watch/lv100',
    ]) {
      test('"$url" is not salvaged into a room', () {
        expect(NiconicoApi.programIdFromUrl(url), isNull);
        expect(NiconicoApi.broadcasterRoomIdFromUrl(url), isNull);
      });
    }

    test('program ids are lv and up to 18 digits without a leading zero', () {
      expect(NiconicoApi.isProgramId('lv1'), isTrue);
      expect(NiconicoApi.isProgramId('lv${'9' * 18}'), isTrue);
      for (final bad in ['lv0', 'lv01', 'lv${'9' * 19}', 'LV1', 'lv1 ', '1', 'user/1', 'ch1']) {
        expect(NiconicoApi.isProgramId(bad), isFalse, reason: bad);
      }
    });
  });
}
