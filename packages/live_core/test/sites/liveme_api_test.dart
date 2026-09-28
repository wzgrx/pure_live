// LiveMe parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/liveme/legacy_expected.dart from 3.x's LiveMeApi, LiveMeLink,
// LiveMeSigner and LiveMeSite). Every intended difference is listed with its
// reason; everything else must match. The synthetic cases port 3.x's
// liveme_directory_test.dart and pin the rest of 3.x's parsing rules.
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('liveme', name);

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

/// Intended differences on every room: 3.x also wrote its media headers into
/// the room (`httpHeaders`, read back only by the IPTV branch of its header
/// resolver); they now travel with each play line.
const _changed = {'httpHeaders'};

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

/// The outcome of a counted legacy call (`{value, requests}`).
Object? _value(String name, String key) => (_legacy(name)[key] as Map<String, dynamic>)['value'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

const _shortId = '209683072';
const _userId = '932385543319330816';
const _videoId = '17904580585651396476';
const _offlineShortId = '17709377';
const _offlineUserId = '560875115161059328';
final _issuedAt = DateTime.utc(2026, 9, 27, 17, 25, 44);

LiveMeProfile _liveProfile() => LiveMeApi.profile(_sample('S04-profile-live').body, userId: _userId);

LiveMeSnapshot _liveVideo({bool media = true}) =>
    LiveMeApi.video(_sample('S05-query-live').body, videoId: _videoId, shortId: _shortId, media: media);

/// Room entry of the live sample, as the site builds it.
LiveRoom _liveRoom({bool media = true}) {
  final snapshot = LiveMeApi.withProfile(_liveVideo(media: media), _liveProfile());
  return LiveMeApi.room(snapshot, data: media ? LiveMeApi.roomData(snapshot, issuedAt: _issuedAt) : null);
}

LiveMeRoomData _liveData() => _liveRoom().data! as LiveMeRoomData;

Map<String, dynamic> _video([Map<String, Object?> changes = const {}]) => {
  'ushortid': '12345678',
  'userid': '1234567890123456789',
  'vid': _videoId,
  'uname': 'Anchor',
  'title': '',
  'online': 1,
  'status': 0,
  'roomstate': 0,
  'playnumber': 120,
  'countryCode': 'US',
  ...changes,
};

String _envelope(Object? data, {Object status = '200', String message = ''}) =>
    jsonEncode({'status': status, 'msg': message, 'data': data});

String _featured(List<Object?> rows, {Object nextPage = 0}) => _envelope({'video_info': rows, 'next_page': nextPage});

String _search(List<Object?> rows) => _envelope({'data_info': rows});

Map<String, Object?> _row([Map<String, Object?> changes = const {}]) => {
  'short_id': '12345678',
  'user_id': '1234567890123456789',
  'nickname': 'Row',
  'face': 'https://esx.esxscloud.com/face.jpg',
  'is_live': '1',
  'project': 'liveme',
  'countryCode': 'us',
  'fans_num': '12',
  ...changes,
};

String _query(Map<String, Object?> video, {Map<String, Object?>? user}) =>
    _envelope({'video_info': video, 'user_info': ?user});

LiveMeSnapshot _snapshot(Map<String, Object?> changes, {bool media = true}) =>
    LiveMeApi.video(_query(_video(changes)), videoId: _videoId, media: media);

void main() {
  group('S01 featured list', () {
    for (final (name, page) in [('S01-featurelist-p1', 1), ('S01-featurelist-p2', 2)]) {
      test('$name matches 3.x', () {
        final result = LiveMeApi.featuredPage(_sample(name).body, page: page);
        final legacy = _value(name, 'getDirectoryPage')! as Map<String, dynamic>;
        expect((result.page, result.hasMore), (legacy['page'], legacy['hasMore']));
        final rooms = _maps(legacy['rooms']);
        expect(result.rooms.map((room) => room.roomId), rooms.map((room) => room['roomId']));
        for (final (index, room) in result.rooms.indexed) {
          _expectParity(_projection(room), rooms[index], changed: _changed, reason: '$name[$index]');
          expect(room.data, isNull, reason: 'list cards carry no stream data');
          expect(room.isLiveNow, isTrue);
        }
        expect(_value(name, 'getRecommendRooms'), legacy['rooms'], reason: 'the same page');
      });
    }

    test("the room is the short id, 3.x's link and audience", () {
      final first = LiveMeApi.featuredPage(_sample('S01-featurelist-p1').body, page: 1).rooms.first;
      expect((first.roomId, first.userId), (_shortId, _userId));
      expect(first.link, 'https://www.liveme.com/livehot/streaming/$_shortId');
      expect(jsonEncode(first.toJson()), isNot(contains(_videoId)), reason: 'the broadcast is no identity');
      expect(
        (first.popularity, first.watching, first.onlineViewers, first.totalViewers),
        ('882', '882', '202', '8670'),
      );
      expect(first.audienceMetricType, AudienceMetricType.popularity);
      expect(first.notice, LiveMeApi.chatNotice);
      expect(first.httpHeaders, isEmpty);
      final legacy = _legacy('S01-featurelist-p1');
      expect(legacy['directoryNoticeKey'], 'liveme_directory_scope');
      expect(
        (legacy['getPlayQualites(card)']! as Map)['message'],
        'LiveMe identity',
        reason: '3.x could not give a list card qualities; the site now asks for its broadcast',
      );
    });

    test('a card without a short id is skipped; a malformed one fails the page (3.x)', () {
      final union = _video({'ushortid': null, 'union_room_id': 'fixture'})..remove('ushortid');
      final page = LiveMeApi.featuredPage(
        _featured([
          _video(),
          union,
          _video({'ushortid': '23456789', 'userid': '2234567890123456789'}),
        ]),
        page: 1,
      );
      expect(page.rooms.map((room) => room.roomId), ['12345678', '23456789']);
      expect(page.hasMore, isFalse);
      for (final bad in [
        _video({'ushortid': '12'}),
        _video({'ushortid': '0123456'}),
        _video({'userid': '12'}),
        _video({'uname': '', 'title': 'x'}),
        _video({'title': 7}),
        _video({'playnumber': -1}),
        _video({'playnumber': '1.5'}),
        'not an object',
      ]) {
        expect(() => LiveMeApi.featuredPage(_featured([bad]), page: 1), throwsA(isA<ApiChanged>()), reason: '$bad');
      }
      expect(
        () => LiveMeApi.featuredPage(_featured(List.filled(101, _video())), page: 1),
        throwsA(isA<ApiChanged>()),
        reason: "3.x's limit of 100 rows",
      );
      expect(
        () => LiveMeApi.featuredPage(_envelope({'video_info': <String, Object?>{}}), page: 1),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('private and paid broadcasts are left out; each room once; next_page 1 means more (3.x)', () {
      final page = LiveMeApi.featuredPage(
        _featured([
          _video(),
          _video({'userid': '2234567890123456789'}),
          _video({'ushortid': '20000', 'ispvt': '1'}),
          _video({'ushortid': '20001', 'livebptype': '7'}),
          _video({
            'ushortid': '20002',
            'hot_label_v2': {'text': 'Paid Broadcast'},
          }),
          _video({'ushortid': '20003', 'hot_label_v2': '{"text":"Paid broadcast"}'}),
        ], nextPage: '1'),
        page: 3,
      );
      expect(page.rooms.map((room) => room.roomId), [
        '12345678',
        '20003',
      ], reason: '3.x read the label only as an object; the site sends it as JSON text, so it never fired');
      expect((page.page, page.hasMore), (3, true));
    });
  });

  group('S02 search', () {
    for (final name in ['S02-search-p1', 'S02-search-p2', 'S02-search-empty']) {
      test('$name matches 3.x', () {
        final rooms = LiveMeApi.searchPage(_sample(name).body);
        final legacy = _maps(_value(name, 'searchRooms'));
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        for (final (index, room) in rooms.indexed) {
          _expectParity(_projection(room), legacy[index], changed: _changed, reason: '$name[$index]');
        }
        // 3.x's `hasMore` (rows >= pageSize) was false for every page of 20
        // but its site never passed it on: the search page kept paging
        // while pages brought new rooms.
        expect(_legacy(name)['LiveMeApi.search.hasMore'], isFalse);
      });
    }

    test('the site answers 20 a page and pages do not overlap', () {
      final first = LiveMeApi.searchPage(_sample('S02-search-p1').body);
      final second = LiveMeApi.searchPage(_sample('S02-search-p2').body);
      expect((first.length, second.length), (20, 20));
      expect(first.map((room) => room.roomId).toSet().intersection(second.map((room) => room.roomId).toSet()), isEmpty);
    });

    test('states: is_live 1 live; 0 offline only for the liveme project; else unknown (3.x)', () {
      final rooms = LiveMeApi.searchPage(
        _search([
          _row(),
          _row({'short_id': '20000', 'is_live': '0'}),
          _row({'short_id': '20001', 'is_live': 0, 'project': 'emolm'}),
          _row({'short_id': '20002', 'is_live': null, 'project': 'LiveMe'}),
          _row({'short_id': '20003', 'is_live': '2'}),
        ]),
      );
      expect(rooms.map((room) => room.effectiveLiveStatus), [
        LiveStatus.live,
        LiveStatus.offline,
        LiveStatus.unknown,
        LiveStatus.unknown,
        LiveStatus.unknown,
      ]);
      final first = rooms.first;
      expect((first.title, first.nick, first.area, first.followers, first.cover), ('Row', 'Row', 'US', '12', ''));
      expect(first.audienceMetricType, AudienceMetricType.onlineViewers, reason: '3.x: no heat, so viewers');
      expect((first.watching, first.popularity, first.onlineViewers), ('', '', ''));
    });

    test('rows: uname when no nickname, follower_count when no fans_num, each room once (3.x)', () {
      final rooms = LiveMeApi.searchPage(
        _search([
          _row({'nickname': ' ', 'uname': 'Other', 'fans_num': null, 'follower_count': '5'}),
          _row({'nickname': 'Again'}),
        ]),
      );
      expect(rooms.single.nick, 'Other');
      expect(rooms.single.followers, '5');
    });

    test('a malformed row fails the page (3.x)', () {
      for (final bad in [
        _row({'short_id': '1234'}),
        _row({'user_id': null}),
        _row({'nickname': null, 'uname': ''}),
        _row({'fans_num': '-3'}),
        _row({'project': 1}),
      ]) {
        expect(() => LiveMeApi.searchPage(_search([bad])), throwsA(isA<ApiChanged>()), reason: '$bad');
      }
    });
  });

  group('S03–S05 rooms', () {
    test('S03 mapping: the user and the broadcast; none when not broadcasting', () {
      expect(LiveMeApi.mapping(_sample('S03-mapping-live').body), (userId: _userId, videoId: _videoId));
      expect(LiveMeApi.mapping(_sample('S03-mapping-offline').body), (userId: _offlineUserId, videoId: ''));
      expect(() => LiveMeApi.mapping(_sample('S03-mapping-notfound').body), throwsA(isA<NotFound>()));
      expect(
        (_value('S03-mapping-notfound', 'getRoomDetail')! as Map)['message'],
        'LiveMe missing',
        reason: '3.x: missing too',
      );
      for (final data in [
        {'uid': '12', 'vid': ''},
        {'uid': _userId, 'vid': '99'},
        {'uid': _userId, 'vid': 1790458058565139},
        {'vid': ''},
      ]) {
        expect(() => LiveMeApi.mapping(_envelope(data)), throwsA(isA<ApiChanged>()), reason: '$data');
      }
    });

    test('S04 profile: the anchor asked for; "user not exist" is NotFound (3.x: service)', () {
      final profile = _liveProfile();
      expect(
        (profile.shortId, profile.userId, profile.followers, profile.countryCode),
        (_shortId, _userId, 33933, 'US'),
      );
      expect(profile.avatar, contains('/540x540/'), reason: 'big_face first');
      expect(
        () => LiveMeApi.profile(_sample('S04-profile-live').body, userId: _offlineUserId),
        throwsA(isA<ApiChanged>()),
      );
      expect(
        () => LiveMeApi.profile(_sample('S04-profile-notfound').body, userId: '1000000000000000001'),
        throwsA(isA<NotFound>()),
      );
      expect((_value('S04-profile-notfound', 'shareImport')! as Map)['message'], 'LiveMe service');
      final noCounts = _envelope({
        'user': {
          'user_info': {'uid': _userId, 'short_id': _shortId, 'nickname': 'x'},
        },
      });
      expect(
        () => LiveMeApi.profile(noCounts, userId: _userId),
        throwsA(isA<ApiChanged>()),
        reason: '3.x required count_info',
      );
    });

    test('S03+S04+S05 live room entry matches 3.x', () {
      final room = _liveRoom();
      for (final key in ['getRoomDetail', 'getRoomDetailForRecording', 'searchRooms(shortId)', 'searchRooms(link)']) {
        final legacy = _value('S03-mapping-live', key);
        _expectParity(
          _projection(room),
          legacy is List ? _maps(legacy).single : legacy! as Map<String, dynamic>,
          changed: _changed,
          reason: key,
        );
      }
      _expectParity(
        _projection(_liveRoom(media: false)),
        _value('S03-mapping-live', 'getRoomDetailForRefresh')! as Map<String, dynamic>,
        changed: _changed,
      );
      expect(_value('S03-mapping-live', 'getLiveStatus'), isTrue);
      expect(room.isLiveNow, isTrue);
      expect(
        room.introduction,
        'LIVEME-NIGHTCLUB 🔆⃤',
        reason: "3.x: the broadcast's user_info.desc (here the name) comes before the profile's usign",
      );
      expect(room.followers, '33933');
      expect(_liveRoom(media: false).data, isNull, reason: 'a refresh carries no stream data');
    });

    test('S03+S04 offline room matches 3.x', () {
      final profile = LiveMeApi.profile(_sample('S04-profile-offline').body, userId: _offlineUserId);
      final room = LiveMeApi.room(LiveMeApi.offline(profile));
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        _expectParity(
          _projection(room),
          _value('S03-mapping-offline', key)! as Map<String, dynamic>,
          changed: _changed,
          reason: key,
        );
      }
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect((room.title, room.cover, room.introduction), (profile.nickname, '', '👑 🐰 🇺🇦'));
      expect(room.audienceMetricType, AudienceMetricType.onlineViewers);
      expect(_value('S03-mapping-offline', 'getLiveStatus'), isFalse);
    });

    test('S05 broadcast: ids checked, completed by user_info, counts only while live (3.x)', () {
      final video = _liveVideo();
      expect(
        (video.shortId, video.userId, video.videoId, video.state),
        (_shortId, _userId, _videoId, LiveMeState.live),
      );
      expect((video.currentViewers, video.totalViewers, video.heat, video.likes), (201, 8681, 885, 773));
      expect(
        () => LiveMeApi.video(_sample('S05-query-live').body, videoId: _videoId, shortId: _offlineShortId),
        throwsA(isA<ApiChanged>()),
      );
      expect(
        () => LiveMeApi.video(_sample('S05-query-live').body, videoId: '17904580585651396477'),
        throwsA(isA<ApiChanged>()),
      );
      final fromUser = LiveMeApi.video(
        _query(
          _video({'ushortid': null, 'userid': null, 'uname': '', 'uface': null}),
          user: {
            'short_id': '54321',
            'userid': '2234567890123456789',
            'uname': 'User',
            'face': 'https://esx.esxscloud.com/u.jpg',
            'usign': 'bio',
          },
        ),
        videoId: _videoId,
      );
      expect(
        (fromUser.shortId, fromUser.userId, fromUser.nickname, fromUser.title),
        ('54321', '2234567890123456789', 'User', 'User'),
      );
      expect((fromUser.avatar, fromUser.bio), ('https://esx.esxscloud.com/u.jpg', 'bio'));
      final offline = _snapshot({'online': 0, 'playnumber': 5, 'heat': 9, 'likenum': 3});
      expect(
        (offline.state, offline.currentViewers, offline.heat, offline.likes),
        (LiveMeState.offline, null, null, 3),
      );
      expect(offline.streams, isEmpty);
    });

    test('states: live, offline, restricted, unknown (3.x)', () {
      expect(_snapshot({}).state, LiveMeState.live);
      expect(_snapshot({'online': '0'}).state, LiveMeState.offline);
      expect(_snapshot({'status': 1}).state, LiveMeState.offline);
      expect(_snapshot({'roomstate': '2'}).state, LiveMeState.offline);
      expect(_snapshot({'online': null, 'status': null, 'roomstate': null}).state, LiveMeState.unknown);
      expect(_snapshot({'online': 2}).state, LiveMeState.unknown);
      expect(_snapshot({'ispvt': 1}).state, LiveMeState.restricted);
      expect(_snapshot({'livebptype': '7', 'online': 0}).state, LiveMeState.restricted);
      final restricted = LiveMeApi.room(_snapshot({'ispvt': 1}));
      expect(
        restricted.effectiveLiveStatus,
        LiveStatus.banned,
        reason: '3.x showed private and paid broadcasts as banned',
      );
      expect(
        LiveMeApi.room(_snapshot({'online': null, 'status': null, 'roomstate': null})).isLiveStatusPending,
        isTrue,
      );
    });

    test('the cover and avatar fall back only when missing, as 3.x', () {
      final missing = _snapshot({'videocapture': null, 'smallcover': 'https://esx.esxscloud.com/small.jpg'});
      expect(missing.cover, 'https://esx.esxscloud.com/small.jpg');
      final empty = _snapshot({'videocapture': '', 'smallcover': 'https://esx.esxscloud.com/small.jpg'});
      expect(empty.cover, '', reason: '3.x used ?? (null only); an empty videocapture meant no cover');
      const profile = LiveMeProfile(
        shortId: '12345678',
        userId: '1234567890123456789',
        nickname: 'Profile',
        cover: 'https://esx.esxscloud.com/profile.jpg',
      );
      expect(
        LiveMeApi.withProfile(empty, profile).cover,
        profile.cover,
        reason: 'room entry filled it from the profile',
      );
    });

    test('images: the CDN hosts only, made https; protocol-relative addresses read', () {
      expect(LiveMeApi.image('http://esx.esxscloud.com/a.jpg'), 'https://esx.esxscloud.com/a.jpg');
      expect(LiveMeApi.image('//img.liveme.com/a.jpg'), 'https://img.liveme.com/a.jpg', reason: '3.x dropped it');
      expect(LiveMeApi.image('https://linkv.fun/a.jpg'), 'https://linkv.fun/a.jpg');
      for (final bad in [
        'https://example.com/a.jpg',
        'https://evil-esxscloud.com/a.jpg',
        'https://user@esx.esxscloud.com/a.jpg',
        'https://esx.esxscloud.com/a.jpg#x',
        'ftp://esx.esxscloud.com/a.jpg',
        '',
        7,
        null,
      ]) {
        expect(LiveMeApi.image(bad), '', reason: '$bad');
      }
    });
  });

  group('streams', () {
    test('S05 qualities, URLs and applied quality match 3.x', () {
      final data = _liveData();
      final qualities = LiveMeApi.qualities(data);
      final legacy = _maps(_legacy('S03-mapping-live')['getPlayQualites']);
      expect(qualities, hasLength(legacy.length));
      for (final (index, quality) in qualities.indexed) {
        final expected = legacy[index];
        expect((quality.quality, quality.id, quality.sort), (expected['quality'], expected['id'], expected['sort']));
        final resolution = LiveMeApi.resolution(data, quality);
        expect(resolution.urls, expected['getPlayUrls']);
        final raw = expected['resolvePlayUrlsRaw'] as Map<String, dynamic>;
        expect(resolution.urls, raw['urls']);
        expect(resolution.appliedQualityData, raw['appliedQualityData']);
      }
      expect(qualities.map((quality) => quality.quality), ['原始画质 · FLV', '流畅画质 · FLV', 'HLS 自动 · HLS']);
    });

    test('lines carry the media headers, format, line id and the wsABStime lease', () {
      final data = _liveData();
      final lines = [for (final quality in LiveMeApi.qualities(data)) ...LiveMeApi.resolution(data, quality).lines];
      expect(lines.map((line) => (line.format, line.lineId)), [
        (StreamFormat.flv, 'source-flv'),
        (StreamFormat.flv, 'smooth-flv'),
        (StreamFormat.hls, 'hls'),
      ]);
      final expires = DateTime.fromMillisecondsSinceEpoch(0x6ab98a4a * 1000, isUtc: true);
      expect(expires, DateTime.utc(2026, 9, 27, 21, 27, 38));
      for (final line in lines) {
        expect(line.headers, {
          'user-agent': LiveMeApi.userAgent,
          'origin': 'https://www.liveme.com',
          'referer': 'https://www.liveme.com/livehot/streaming/$_shortId',
        }, reason: "3.x's PlaybackHeaderResolver for LiveMe");
        expect(line.codec, isNull, reason: 'the platform does not say');
        expect(line.lease!.expiresAt, expires);
        expect(line.lease!.refreshAt, expires.subtract(const Duration(minutes: 10)));
        expect(line.lease!.cutsConnection, isFalse);
      }
    });

    test('the lease: a quarter of a short lifetime, none when missing, past or malformed', () {
      final expiry = DateTime.utc(2026, 9, 27, 18);
      final hex = (expiry.millisecondsSinceEpoch ~/ 1000).toRadixString(16);
      final url = 'https://game.live11.linkv.fun/yolo/1.flv?wsSecret=x&wsABStime=$hex';
      final short = LiveMeApi.lease(url, issuedAt: expiry.subtract(const Duration(minutes: 20)))!;
      expect(short.refreshAt, expiry.subtract(const Duration(minutes: 5)));
      expect(LiveMeApi.lease(url, issuedAt: expiry), isNull);
      for (final bad in ['wsABStime=zz', 'wsABStime=', 'wsABStime=fffffffffff', 'wsSecret=x']) {
        expect(LiveMeApi.lease('https://linkv.fun/1.flv?$bad', issuedAt: expiry), isNull, reason: bad);
      }
    });

    test("media: 3.x's hosts and suffixes, made https, *more alternatives flattened once", () {
      const flv = 'http://a.linkv.fun/yolo/1.flv?k=1';
      const other = 'http://b.liveme.com/yolo/1.flv?k=2';
      final streams = LiveMeApi.streams({
        'videosource': flv,
        'videosourcemore': jsonEncode([flv, other, 'https://example.com/1.flv', 'http://c.emolm.com/1.m3u8']),
        'smallsource': {'a': 'http://a.linkv.fun/yolo/1_360.flv', 'b': ' '},
        'smallsourcemore': ['http://a.linkv.fun/yolo/1_360.flv#x', 'http://u@a.linkv.fun/yolo/1_360.flv'],
        'hlsvideosource': 'http://hls.linkv.fun/yolo/1/playlist.m3u8 ',
      });
      expect(
        [for (final stream in streams) (stream.qualityId, stream.format)],
        [('source-flv', StreamFormat.flv), ('smooth-flv', StreamFormat.flv), ('hls', StreamFormat.hls)],
      );
      expect(
        [for (final stream in streams) stream.urls],
        [
          ['https://a.linkv.fun/yolo/1.flv?k=1', 'https://b.liveme.com/yolo/1.flv?k=2'],
          ['https://a.linkv.fun/yolo/1_360.flv'],
          ['https://hls.linkv.fun/yolo/1/playlist.m3u8'],
        ],
      );
      expect(LiveMeApi.streams({'hlsvideosource': 'https://a.linkv.fun/1.flv', 'videosource': ''}), isEmpty);
      expect(LiveMeApi.mediaUrl('https://a.linkv.fun/1 2.flv', StreamFormat.flv), isNull);
      final data = LiveMeRoomData(
        shortId: '12345678',
        userId: '1234567890123456789',
        state: LiveMeState.live,
        issuedAt: _issuedAt,
        streams: streams,
      );
      final lines = LiveMeApi.resolution(data, LiveMeApi.qualities(data).first).lines;
      expect(lines.map((line) => line.lineId), ['source-flv', 'source-flv#2']);
      expect(lines.map((line) => line.lease), everyElement(isNull), reason: 'no wsABStime');
    });

    test('a broadcast that cannot play says why; an unknown quality is unavailable', () {
      LiveMeRoomData data(LiveMeState state, [List<LiveMeStream> streams = const []]) =>
          LiveMeRoomData(shortId: '12345678', userId: '1', state: state, issuedAt: _issuedAt, streams: streams);
      for (final state in LiveMeState.values) {
        expect(() => LiveMeApi.qualities(data(state)), throwsA(isA<StreamUnavailable>()), reason: state.name);
      }
      const other = LivePlayQuality(quality: 'x', id: 'uhd');
      expect(() => LiveMeApi.resolution(_liveData(), other), throwsA(isA<StreamUnavailable>()));
      expect(_snapshot({}, media: false).streams, isEmpty, reason: 'media only when asked');
      expect(_snapshot({'ispvt': 1, 'videosource': 'http://a.linkv.fun/1.flv'}).streams, isEmpty);
    });
  });

  group('links', () {
    test('S05 vectors match 3.x; an undecodable path is no link (3.x threw)', () {
      Object? project(LiveMeLink? link) => link == null ? null : {'kind': link.kind.name, 'id': link.id};
      for (final vector in _maps(_legacy('S05-query-live')['vectors'])) {
        final input = vector['input'] as String;
        if (input.contains('%FF')) {
          expect((vector['parse'] as Map)['throws'], 'FormatException');
          expect(LiveMeLink.parse(input), isNull);
          expect(LiveMeLink.parseOrShortId(input), isNull);
          continue;
        }
        expect(project(LiveMeLink.parse(input)), vector['parse'], reason: input);
        expect(project(LiveMeLink.parseOrShortId(input)), vector['parseOrShortId'], reason: input);
      }
    });

    test('the share URL the broadcast hands out is a video link', () {
      final root = jsonDecode(_sample('S05-query-live').body) as Map<String, dynamic>;
      final video = (root['data'] as Map<String, dynamic>)['video_info'] as Map<String, dynamic>;
      final shareUrl = video['shareurl'] as String;
      expect(LiveMeLink.parse(shareUrl), const LiveMeLink(LiveMeLinkKind.videoId, _videoId));
      expect(LiveMeLink.url(_shortId), 'https://www.liveme.com/livehot/streaming/$_shortId');
    });
  });

  group('signature', () {
    test("reproduces the recorded request's lm-s-sign", () {
      final request = _sample('S05-query-live').meta['request'] as Map<String, dynamic>;
      final form = Uri.splitQueryString(request['body'] as String);
      final signed = LiveMeSigner.signAt(
        query: LiveMeApi.videoQuery,
        form: {
          for (final key in ['_time', 'thirdchannel', 'videoid', 'area', 'vali']) key: form[key]!,
        },
        timestamp: form['lm_s_ts']!,
      );
      expect(signed.fields, form);
      expect(signed.signature, (request['headers'] as Map)['lm-s-sign']);
    });

    test('an independent vector (Python hashlib, archive v4)', () {
      final signed = LiveMeSigner.signAt(
        query: LiveMeApi.videoQuery,
        form: const {
          '_time': '1790529930544',
          'thirdchannel': '6',
          'videoid': _videoId,
          'area': 'en',
          'vali': 'ABCDlEFGHmJKMNP',
        },
        timestamp: '17905299305440',
      );
      expect(signed.fields['lm_s_str'], '4c71dbf9913b0b4ad7099adfb411b750');
      expect(signed.signature, 'aaa4b40cb4ab6fa268ab712f39f93b6e');
    });

    test("timestamps are the millisecond and one counter digit, the web client's 14 digits", () {
      final signer = LiveMeSigner(random: Random(1));
      final now = DateTime.utc(2026, 9, 27, 17, 25, 41, 900);
      final stamps = [
        for (var i = 0; i < 12; i++) signer.sign(query: const {}, form: const {}, now: now).fields['lm_s_ts']!,
      ];
      expect(stamps.first, '${now.millisecondsSinceEpoch}0');
      expect(stamps.map((stamp) => stamp.length).toSet(), {14}, reason: "3.x's counter grew to 4 digits");
      expect(stamps[10], stamps[0], reason: 'the digit wraps after 9');
      expect(
        signer.vali(),
        matches(
          RegExp(
            r'^[A-HJKMNP-TW-Za-fh-kmnprstw-z2-8]{4}l[A-HJKMNP-TW-Za-fh-kmnprstw-z2-8]{4}m[A-HJKMNP-TW-Za-fh-kmnprstw-z2-8]{5}$',
          ),
        ),
      );
    });
  });

  group('errors', () {
    test('HTTP statuses as 3.x read them', () {
      for (final (status, matcher) in [
        (400, isA<ApiChanged>()),
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (420, isA<RateLimited>()),
        (429, isA<RateLimited>()),
        (500, isA<NetworkFailure>()),
        (503, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
      ]) {
        expect(() => LiveMeApi.mapping('', status: status), throwsA(matcher), reason: '$status');
      }
    });

    test('business statuses as 3.x read them; "not exist" is NotFound', () {
      for (final (status, message, matcher) in [
        ('400', 'params error', isA<NotFound>()),
        (404, '', isA<NotFound>()),
        ('401', '', isA<RiskControl>()),
        ('403', '', isA<RiskControl>()),
        ('420', '', isA<RateLimited>()),
        ('429', '', isA<RateLimited>()),
        ('500', 'user not exist', isA<NotFound>()),
        ('500', 'busy', isA<NetworkFailure>()),
        ('502', '', isA<NetworkFailure>()),
        ('201', '', isA<ApiChanged>()),
        ('ok', '', isA<ApiChanged>()),
      ]) {
        expect(
          () => LiveMeApi.searchPage(_envelope({'data_info': <Object?>[]}, status: status, message: message)),
          throwsA(matcher),
          reason: '$status $message',
        );
      }
      for (final body in [
        'not json',
        '[]',
        jsonEncode({'data': <String, Object?>{}}),
        _envelope(null),
        'x' * (8 * 1024 * 1024 + 1),
      ]) {
        expect(
          () => LiveMeApi.searchPage(body),
          throwsA(isA<ApiChanged>()),
          reason: body.length > 99 ? 'oversize' : body,
        );
      }
    });
  });
}
