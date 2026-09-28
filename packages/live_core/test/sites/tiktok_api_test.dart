// TikTok parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/tiktok/legacy_expected.dart from 3.x's TikTokApi, TikTokLink and
// TikTokSite). Every intended difference is listed with its reason;
// everything else must match. 3.x had no TikTok tests; the synthetic cases
// cover the checks of its tiktok_api.dart line by line.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('tiktok', name);

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

/// The `result` of a traced legacy call.
Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

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

/// httpHeaders: 3.x also wrote the media headers into the room, which only
/// IPTV's player path read (playback_header_resolver.dart:143-147); they now
/// travel with every line (asserted in "lines").
const _headersMoved = {'httpHeaders'};

/// avatar, cover: the samples' pictures are on the regional CDN
/// tiktokcdn-us.com, which 3.x did not trust (it showed none).
const _picturesTrusted = {'avatar', 'cover', 'httpHeaders'};

/// The answer as 3.x's `trustedHosts` run saw it: tiktokcdn-us.com spelled
/// tiktokcdn.com, nothing else changed.
String _trusted(String body) => body.replaceAll('tiktokcdn-us.com', 'tiktokcdn.com');

final DateTime _issued = _sample('S01-user-live').capturedAt;

LiveRoom _room(String body, String user, {bool media = true, int status = 200}) =>
    TikTokApi.room(body, username: user, includeMedia: media, issuedAt: _issued, status: status);

TikTokRoomData _data(LiveRoom room) => room.data! as TikTokRoomData;

/// [json] as decoded JSON: maps and lists of `dynamic`, so tests can edit
/// them freely.
Map<String, dynamic> _mutable(Object? json) => jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

/// The live sample decoded, to edit.
Map<String, dynamic> _liveJson() => _mutable(jsonDecode(_sample('S01-user-live').body));

Map<String, dynamic> _user(Map<String, dynamic> json) =>
    (json['data'] as Map<String, dynamic>)['user'] as Map<String, dynamic>;

Map<String, dynamic> _live(Map<String, dynamic> json) =>
    (json['data'] as Map<String, dynamic>)['liveRoom'] as Map<String, dynamic>;

const _cdn = 'https://pull-f5-tt01.tiktokcdn-us.com/game';

/// A `pull_data` container whose `stream_data` holds [tiers].
Map<String, dynamic> _container(Map<String, Object?> tiers) => {
  'pull_data': {
    'stream_data': jsonEncode({
      'common': {'session_id': 'x'},
      'data': tiers,
    }),
    'options': <String, dynamic>{},
  },
};

/// One tier's `main`.
Map<String, Object?> _tier({String flv = '', String hls = '', Object? sdk}) => {
  'main': {'flv': flv, 'hls': hls, 'cmaf': '', 'sdk_params': sdk is Map ? jsonEncode(sdk) : (sdk ?? '')},
};

/// The live sample with [streamData] and [hevcStreamData] as its containers
/// (null removes one).
String _withStreams(Map<String, dynamic>? streamData, [Map<String, dynamic>? hevcStreamData]) {
  final json = _liveJson();
  _live(json)
    ..['streamData'] = streamData
    ..['hevcStreamData'] = hevcStreamData;
  return jsonEncode(json);
}

List<TikTokStream> _streams(String body) => _data(_room(body, 'qvc')).streams;

void main() {
  group('user/room against 3.x', () {
    for (final (name, user) in [('S01-user-live', 'qvc'), ('S01-user-offline', 'cnn')]) {
      test("$name: the follow refresh is 3.x's card, with the pictures 3.x dropped", () {
        final fixture = _sample(name);
        final legacy = _legacy(name);
        for (final asked in [user, user.toUpperCase()]) {
          final want = _result(legacy['getRoomDetailForRefresh($asked)'])! as Map<String, dynamic>;
          final room = _room(fixture.body, user, media: false);
          _expectParity(_projection(room), want, changed: _picturesTrusted, reason: '$name $asked');
          expect(want['avatar'], isEmpty, reason: '3.x refused tiktokcdn-us.com');
          expect(room.avatar, startsWith('https://p16-common-sign.tiktokcdn-us.com/'));
          expect(room.cover, startsWith('https://p1'));
          expect(room.data, isNull, reason: 'refreshes read no streams (3.x)');
          expect(room.httpHeaders, isEmpty);
        }
      });

      test("$name: with 3.x's trusted hosts every depth is 3.x's room", () {
        final body = _trusted(_sample(name).body);
        final legacy = _legacy(name)['trustedHosts'] as Map<String, dynamic>;
        for (final (key, media) in [
          ('getRoomDetailForRefresh($user)', false),
          ('getRoomDetail', true),
          ('getRoomDetailForRecording', true),
        ]) {
          final want = _result(legacy[key])! as Map<String, dynamic>;
          _expectParity(
            _projection(_room(body, user, media: media)),
            want,
            changed: _headersMoved,
            reason: key,
          );
        }
      });
    }

    test('S01-user-live: 3.x refused the regional CDN at room entry (schema); now the room and its streams', () {
      final legacy = _legacy('S01-user-live');
      for (final key in ['getRoomDetail', 'getRoomDetailForRecording']) {
        expect(_result(legacy[key]), {'throws': 'TikTokException', 'message': 'TikTok schema'}, reason: key);
      }
      final room = _room(_sample('S01-user-live').body, 'qvc');
      final want = _result((legacy['trustedHosts'] as Map<String, dynamic>)['getRoomDetail'])! as Map<String, dynamic>;
      _expectParity(_projection(room), want, changed: _picturesTrusted);
      final data = _data(room);
      expect(
        (data.username, data.userId, data.liveRoomId, data.streamId),
        ('qvc', '6768510980420043782', '7690279124098681614', '3578925130487169980'),
      );
      expect((data.state, data.status, data.restriction), (TikTokState.live, 2, null));
      expect(data.secUid, startsWith('MS4wLjABAAAA'));
      expect(data.streams, hasLength(14));
      expect(data.issuedAt, _issued);
      expect(TikTokApi.unplayable(data), isNull);
    });

    test("S01-user-live: 3.x's card fields, audience and notice", () {
      final room = _room(_sample('S01-user-live').body, 'qvc');
      expect(
        (room.roomId, room.userId, room.nick, room.title),
        ('qvc', '6768510980420043782', 'QVC, Inc', 'Pumpkin Spice Season'),
      );
      expect((room.area, room.link), ('TikTok LIVE', 'https://www.tiktok.com/@qvc/live'));
      expect((room.watching, room.onlineViewers, room.totalViewers, room.followers), ('203', '203', '9492', '1597439'));
      expect(room.audienceMetricType, AudienceMetricType.onlineViewers);
      expect(room.supportsRealOnlineCount, isTrue);
      expect(room.notice, TikTokApi.chatNotice);
      expect(room.introduction, startsWith('This is shopping brought to life'));
      expect(room.cover, contains('cropcenter:720:720'), reason: '`coverUrl` before `squareCoverImg` (3.x)');
      expect(room.avatar, contains('cropcenter:1080:1080'), reason: '`avatarLarger` first (3.x)');
    });

    test("S01-user-offline: 3.x's state; no audience; the stream_data an offline answer carries is not read", () {
      final fixture = _sample('S01-user-offline');
      final room = _room(fixture.body, 'cnn');
      expect(room.liveStatus, LiveStatus.offline);
      expect((room.watching, room.onlineViewers, room.totalViewers), ('', '', ''));
      expect(room.title, 'Fans pay tribute to Dolly Parton', reason: "the last LIVE's title, as the site sends it");
      final data = _data(room);
      expect((data.state, data.status), (TikTokState.offline, 4));
      expect(data.streams, isEmpty);
      expect(fixture.body, contains('stream_data'));
      // 3.x listed no qualities (an empty list); now the reason.
      expect(_result(_legacy('S01-user-offline')['getPlayQualites']), isEmpty);
      expect(TikTokApi.unplayable(data), isA<StreamUnavailable>());
    });

    test('S01-user-missing: statusCode 19881007 is NotFound (3.x: missing)', () {
      final fixture = _sample('S01-user-missing');
      expect(_result(_legacy('S01-user-missing')['getRoomDetail']), containsPair('message', 'TikTok missing'));
      for (final media in [true, false]) {
        expect(() => _room(fixture.body, 'nasa', media: media), throwsA(isA<NotFound>()));
      }
    });

    test("S02-room-live: room/info's owner is 3.x's username", () {
      final fixture = _sample('S02-room-live');
      final legacy = _legacy('S02-room-live');
      expect(
        TikTokApi.owner(fixture.body, liveRoomId: '7690279124098681614'),
        _result(legacy['TikTokApi.resolveReference']),
      );
      expect(() => TikTokApi.owner(fixture.body, liveRoomId: '7690279124098681615'), throwsA(isA<ApiChanged>()));
    });
  });

  group('qualities and lines against 3.x', () {
    final legacy = _legacy('S01-user-live')['trustedHosts'] as Map<String, dynamic>;
    final wanted = (_result(legacy['getPlayQualites'])! as List).cast<Map<String, dynamic>>();

    test("3.x's qualities (names, ids, ranks, order), also over the recorded regional hosts", () {
      for (final body in [_trusted(_sample('S01-user-live').body), _sample('S01-user-live').body]) {
        final qualities = TikTokApi.qualities(_data(_room(body, 'qvc')));
        expect([
          for (final quality in qualities) {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort},
        ], wanted);
      }
      expect(
        wanted.first['quality'],
        '原始画质 · 1080x1920 · H264 · FLV',
        reason: 'hevcStreamData carries the H.264 origin',
      );
    });

    test("3.x's URLs for every quality, applied as asked; the recording's hosts are the regional CDN", () {
      final trusted = _data(_room(_trusted(_sample('S01-user-live').body), 'qvc'));
      final recorded = _data(_room(_sample('S01-user-live').body, 'qvc'));
      final urls = legacy['resolvePlayUrlsRaw'] as Map<String, dynamic>;
      for (final quality in TikTokApi.qualities(trusted)) {
        final want = _result(urls['${quality.id}'])! as Map<String, dynamic>;
        final resolution = TikTokApi.resolution(trusted, quality);
        expect(resolution.urls, want['urls'], reason: '${quality.id}');
        expect(resolution.appliedQualityData, want['appliedQualityData']);
        expect(TikTokApi.resolution(recorded, quality).urls, [
          for (final url in want['urls'] as List) (url as String).replaceAll('tiktokcdn.com', 'tiktokcdn-us.com'),
        ]);
      }
    });

    test("lines: 3.x's media headers, the protocol's format, the codec, the CDN host, the lease of `expire`", () {
      final data = _data(_room(_sample('S01-user-live').body, 'qvc'));
      final headers =
          (_result(legacy['getRoomDetail'])! as Map<String, dynamic>)['httpHeaders'] as Map<String, dynamic>;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(1791749747 * 1000, isUtc: true);
      for (final quality in TikTokApi.qualities(data)) {
        final line = TikTokApi.resolution(data, quality).lines.single;
        final id = '${quality.id}';
        expect(line.headers, headers, reason: 'PlaybackHeaderResolver sent TikTokApi.mediaHeaders');
        expect(line.headers, TikTokApi.mediaHeaders('qvc'));
        expect(line.format, id.endsWith(':flv') ? StreamFormat.flv : StreamFormat.hls);
        expect(line.codec, id.startsWith('h264') ? 'avc' : 'hevc');
        expect(
          line.lineId,
          id.endsWith(':flv') ? 'pull-f5-tt01.tiktokcdn-us.com' : 'pull-hls-f16-tt01.tiktokcdn-us.com',
        );
        expect(line.lease!.expiresAt, expiresAt, reason: 'signed for about 14 days');
        expect(line.lease!.refreshAt, expiresAt.subtract(const Duration(hours: 1)));
        expect(line.lease!.cutsConnection, isFalse);
      }
    });

    test('a quality the LIVE does not offer is StreamUnavailable (3.x: mediaUnavailable)', () {
      final data = _data(_room(_sample('S01-user-live').body, 'qvc'));
      expect(
        () => TikTokApi.resolution(data, const LivePlayQuality(quality: 'x', id: 'h264:uhd:flv')),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('the lease: none without `expire` or once past; a short lifetime renews at three quarters', () {
      final issued = DateTime.utc(2026);
      expect(TikTokApi.lease(Uri.parse('https://a.tiktokcdn.com/x.flv'), issued), isNull);
      expect(TikTokApi.lease(Uri.parse('https://a.tiktokcdn.com/x.flv?expire=abc'), issued), isNull);
      final past = issued.millisecondsSinceEpoch ~/ 1000 - 1;
      expect(TikTokApi.lease(Uri.parse('https://a.tiktokcdn.com/x.flv?expire=$past'), issued), isNull);
      final soon = issued.millisecondsSinceEpoch ~/ 1000 + 400;
      final lease = TikTokApi.lease(Uri.parse('https://a.tiktokcdn.com/x.flv?expire=$soon'), issued)!;
      expect(lease.refreshAt, issued.add(const Duration(seconds: 300)));
    });
  });

  group('links against 3.x (TikTokLink)', () {
    for (final name in ['S01-user-live', 'S01-user-offline', 'S01-user-missing']) {
      test('$name: parse, lookup (parseOrUsername), user links and usernames as 3.x', () {
        final links = _legacy(name)['links'] as Map<String, dynamic>;
        Object? project(TikTokLink? link) =>
            link == null ? null : {'kind': link.kind == TikTokLinkKind.username ? 'username' : 'roomId', 'id': link.id};
        for (final MapEntry(key: input, value: want as Map<String, dynamic>) in links.entries) {
          expect(project(TikTokLink.parse(input)), want['TikTokLink.parse'], reason: input);
          expect(project(TikTokLink.lookup(input)), want['TikTokLink.parseOrUsername'], reason: input);
          expect(TikTokLink.normalizeUsername(input), want['TikTokLink.normalizeUsername'], reason: input);
          final user = TikTokLink.parse(input);
          expect(user?.kind == TikTokLinkKind.username ? user!.id : null, want['TikTokLink.parseDurableUsername']);
        }
        expect(
          TikTokApi.roomUrl(
            name == 'S01-user-live'
                ? 'qvc'
                : name == 'S01-user-offline'
                ? 'cnn'
                : 'nasa',
          ),
          _legacy(name)['TikTokLink.url'],
        );
      });
    }

    test('short links: vm/vt with a code (3.x) and www.tiktok.com/t/<code> (the newer form 3.x missed)', () {
      for (final url in [
        'https://vm.tiktok.com/ZMabcdef/',
        'http://vt.tiktok.com/ZSxyz',
        'https://www.tiktok.com/t/ZTabcdef/',
        'https://tiktok.com/t/ZT1',
      ]) {
        expect(TikTokLink.shortLink(url), Uri.parse(url), reason: url);
      }
      for (final url in [
        'https://vm.tiktok.com/',
        'https://www.tiktok.com/t/',
        'https://www.tiktok.com/t/a/b',
        'https://www.tiktok.com/@qvc/live',
        'https://user@vm.tiktok.com/ZMabc/',
        'ftp://vm.tiktok.com/ZMabc/',
        'https://vm.tiktok.com.evil/ZMabc/',
        'vm.tiktok.com/ZMabc',
      ]) {
        expect(TikTokLink.shortLink(url), isNull, reason: url);
      }
    });

    test('a path that does not decode is no link (3.x threw FormatException)', () {
      expect(TikTokLink.parse('https://www.tiktok.com/@qvc%FF/live'), isNull);
      expect(TikTokLink.shortLink('https://vm.tiktok.com/%FF'), isNull);
    });

    test('"open in browser": the web page of a username, null for anything else', () {
      expect(TikTokApi.externalRoomUrl(' QVC '), 'https://www.tiktok.com/@qvc/live');
      expect(TikTokApi.externalRoomUrl('@qvc'), isNull);
      expect(TikTokApi.externalRoomUrl('.qvc'), isNull);
    });
  });

  group("answers (3.x's checks)", () {
    test('restricted: a private account, subscribers only, paid, in that order; banned, NeedsLogin, no streams', () {
      for (final (edit, restriction) in <(void Function(Map<String, dynamic>), TikTokRestriction)>[
        ((json) => _user(json)['secret'] = true, TikTokRestriction.privateAccount),
        ((json) => _live(json)['liveSubOnly'] = 1, TikTokRestriction.subscriberOnly),
        ((json) => _live(json)['liveSubOnly'] = '1', TikTokRestriction.subscriberOnly),
        ((json) => (_live(json)['paidEvent'] as Map)['paid_type'] = 2, TikTokRestriction.paid),
        (
          (json) {
            _user(json)['secret'] = true;
            _live(json)['liveSubOnly'] = 1;
          },
          TikTokRestriction.privateAccount,
        ),
      ]) {
        final json = _liveJson();
        edit(json);
        final room = _room(jsonEncode(json), 'qvc');
        final data = _data(room);
        expect(
          (room.liveStatus, data.state, data.restriction),
          (LiveStatus.banned, TikTokState.restricted, restriction),
        );
        expect(data.streams, isEmpty);
        expect((room.onlineViewers, room.totalViewers), ('', ''), reason: 'counts only while live (3.x)');
        expect(TikTokApi.unplayable(data), isA<NeedsLogin>());
      }
    });

    test('paidEvent may be missing, null or an empty list; paid_type 0 is free', () {
      for (final paid in [
        null,
        <Object?>[],
        {'paid_type': 0},
        <String, Object?>{},
      ]) {
        final json = _liveJson();
        _live(json)['paidEvent'] = paid;
        expect(_room(jsonEncode(json), 'qvc').liveStatus, LiveStatus.live, reason: '$paid');
      }
      final json = _liveJson();
      _live(json).remove('paidEvent');
      expect(_room(jsonEncode(json), 'qvc').liveStatus, LiveStatus.live);
    });

    test('the state: 2 live, 4 offline, anything else unknown; user.status when liveRoom.status is missing', () {
      for (final (status, state) in [
        (2, LiveStatus.live),
        (4, LiveStatus.offline),
        (3, LiveStatus.unknown),
        ('2', LiveStatus.live),
      ]) {
        final json = _liveJson();
        _live(json)['status'] = status;
        expect(_room(jsonEncode(json), 'qvc').liveStatus, state, reason: '$status');
      }
      final json = _liveJson();
      _live(json).remove('status');
      _user(json)['status'] = 4;
      expect(_room(jsonEncode(json), 'qvc').liveStatus, LiveStatus.offline);
      _user(json).remove('status');
      final unknown = _room(jsonEncode(json), 'qvc');
      expect(unknown.liveStatus, LiveStatus.unknown);
      expect(TikTokApi.unplayable(_data(unknown)), isA<StreamUnavailable>());
    });

    test('an empty title is the nickname; text is trimmed; a missing stats object has no followers', () {
      final json = _liveJson();
      _live(json)['title'] = '  ';
      _user(json)['nickname'] = '  QVC  ';
      (json['data'] as Map).remove('stats');
      final room = _room(jsonEncode(json), 'qvc');
      expect((room.title, room.nick, room.followers), ('QVC', 'QVC', ''));
    });

    test(
      'pictures: the first trusted https one of avatarLarger, avatarMedium, avatarThumb (3.x took the first present)',
      () {
        final json = _liveJson();
        _user(json)
          ..['avatarLarger'] = ''
          ..['avatarMedium'] = 'https://evil.example.test/a.webp'
          ..['avatarThumb'] = '//p16-sign-va.tiktokcdn.com/thumb.webp';
        _live(json)
          ..['coverUrl'] = 'http://p16-sign-va.tiktokcdn.com/cover.webp'
          ..['squareCoverImg'] = 'https://p16-webcast.tiktokcdn-eu.com/square.webp';
        final room = _room(jsonEncode(json), 'qvc');
        expect(room.avatar, 'https://p16-sign-va.tiktokcdn.com/thumb.webp');
        expect(room.cover, 'https://p16-webcast.tiktokcdn-eu.com/square.webp');
        _user(json)['avatarThumb'] = 'https://p16-sign-va.tiktokcdn.com/x.webp#frag';
        _live(json).remove('squareCoverImg');
        final bare = _room(jsonEncode(json), 'qvc');
        expect((bare.avatar, bare.cover), ('', ''));
      },
    );

    test('a field of the wrong shape fails the answer (ApiChanged), as 3.x (schema, identity)', () {
      for (final edit in <void Function(Map<String, dynamic>)>[
        (json) => json['data'] = null,
        (json) => (json['data'] as Map).remove('user'),
        (json) => (json['data'] as Map).remove('liveRoom'),
        (json) => (json['data'] as Map)['stats'] = 'x',
        (json) => _user(json)['uniqueId'] = 'cnn',
        (json) => _user(json)['uniqueId'] = 42,
        (json) => _user(json)['uniqueId'] = 'q v c',
        (json) => _user(json)['nickname'] = ' ',
        (json) => _user(json)['nickname'] = 7,
        (json) => _user(json)['id'] = '123',
        (json) => _user(json).remove('id'),
        (json) => _user(json)['roomId'] = 'abc',
        (json) => _user(json)['secret'] = 'no',
        (json) => _user(json)['verified'] = 1,
        (json) => _user(json)['signature'] = 5,
        (json) => _user(json)['secUid'] = false,
        (json) => _live(json)['streamId'] = '12',
        (json) => _live(json)['title'] = 3,
        (json) => _live(json)['paidEvent'] = 'free',
        (json) => _live(json)['liveRoomStats'] = <Object?>[],
        (json) => (_live(json)['liveRoomStats'] as Map)['userCount'] = -1,
        (json) => (_live(json)['liveRoomStats'] as Map)['enterCount'] = 'many',
        (json) => (json['data'] as Map)['stats'] = {'followerCount': -5},
      ]) {
        final json = _liveJson();
        edit(json);
        expect(() => _room(jsonEncode(json), 'qvc'), throwsA(isA<ApiChanged>()), reason: '$edit');
      }
    });

    test('ids may be numbers; the user may answer in capitals; roomId and streamId may be empty', () {
      final json = _liveJson();
      _user(json)
        ..['id'] = int.parse('6768510980420043782')
        ..['uniqueId'] = 'QVC'
        ..['roomId'] = '';
      _live(json)['streamId'] = null;
      final data = _data(_room(jsonEncode(json), 'qvc'));
      expect((data.userId, data.liveRoomId, data.streamId), ('6768510980420043782', '', ''));
    });

    test('statusCode: 19881007 or a "not exist"/"not_found" message is NotFound; any other code ApiChanged', () {
      String answer(Object? code, Object? message) =>
          jsonEncode({'statusCode': code, 'message': message, 'data': null});
      for (final (code, message) in [
        (19881007, ''),
        (1, 'User does not exist'),
        (2, 'user_not_found'),
        ('19881007', null),
      ]) {
        expect(() => _room(answer(code, message), 'qvc'), throwsA(isA<NotFound>()), reason: '$code $message');
      }
      for (final (code, message) in [(10000, 'busy'), (null, null), ('x', '')]) {
        expect(() => _room(answer(code, message), 'qvc'), throwsA(isA<ApiChanged>()), reason: '$code $message');
      }
      expect(() => _room(answer(1, 42), 'qvc'), throwsA(isA<ApiChanged>()), reason: 'a message that is no string');
    });

    test('HTTP status, empty, non-JSON and oversized answers', () {
      final body = _sample('S01-user-live').body;
      for (final (status, type) in [
        (400, isA<ApiChanged>()),
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (420, isA<RateLimited>()),
        (429, isA<RateLimited>()),
        (500, isA<NetworkFailure>()),
        (503, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
        (204, isA<NetworkFailure>()),
      ]) {
        expect(() => _room(body, 'qvc', status: status), throwsA(type), reason: '$status');
        expect(() => TikTokApi.owner(body, liveRoomId: '7690279124098681614', status: status), throwsA(type));
      }
      expect(() => _room('', 'qvc'), throwsA(isA<RiskControl>()), reason: "the site's anonymous refusal");
      for (final text in ['<html></html>', '[]', ' ', 'null']) {
        expect(() => _room(text, 'qvc'), throwsA(isA<ApiChanged>()), reason: text);
      }
      final large = jsonEncode({'statusCode': 0, 'pad': 'x' * TikTokApi.responseLimit});
      expect(() => _room(large, 'qvc'), throwsA(isA<ApiChanged>()));
      final wide = jsonEncode({'statusCode': 0, 'pad': '语' * (TikTokApi.responseLimit ~/ 3 + 1)});
      expect(() => _room(wide, 'qvc'), throwsA(isA<ApiChanged>()), reason: 'counted in UTF-8 bytes');
    });

    test('room/info: a status_code other than 0 is NotFound; no data, another LIVE room or no username ApiChanged', () {
      final json = _mutable(jsonDecode(_sample('S02-room-live').body));
      String edited(void Function(Map<String, dynamic> data) edit) {
        final copy = _mutable(json);
        edit(copy);
        return jsonEncode(copy);
      }

      const id = '7690279124098681614';
      expect(
        () => TikTokApi.owner(edited((json) => json['status_code'] = 4003110), liveRoomId: id),
        throwsA(isA<NotFound>()),
      );
      expect(
        () => TikTokApi.owner(edited((json) => json.remove('status_code')), liveRoomId: id),
        throwsA(isA<NotFound>()),
      );
      for (final edit in <void Function(Map<String, dynamic>)>[
        (json) => json['data'] = null,
        (json) => (json['data'] as Map)['id'] = int.parse('7690279124098681615'),
        (json) => ((json['data'] as Map)['owner'] as Map)['display_id'] = '',
        (json) => (json['data'] as Map).remove('owner'),
      ]) {
        expect(() => TikTokApi.owner(edited(edit), liveRoomId: id), throwsA(isA<ApiChanged>()), reason: '$edit');
      }
      expect(
        TikTokApi.owner(
          edited((json) => ((json['data'] as Map)['owner'] as Map)['display_id'] = 'QVC'),
          liveRoomId: id,
        ),
        'qvc',
      );
    });
  });

  group("streams (3.x's reading of both containers)", () {
    test('both containers are read, merged by codec, tier and protocol; ao is left out; each URL once', () {
      final streams = _streams(
        _withStreams(
          _container({
            'hd': _tier(
              flv: '$_cdn/a_hd.flv',
              hls: '$_cdn/a_hd.m3u8',
              sdk: {'VCodec': 'h264', 'resolution': '720x1280'},
            ),
            'ao': _tier(flv: '$_cdn/a.flv?only_audio=1'),
          }),
          _container({
            'HD': _tier(flv: '$_cdn/b_hd.flv', sdk: {'VCodec': 'h264', 'vbitrate': 1800000}),
            'sd': _tier(flv: '$_cdn/a_sd.flv'),
          }),
        ),
      );
      expect(streams.map((stream) => stream.id), ['h264:hd:flv', 'h264:hd:hls', 'h265:sd:flv']);
      final hd = streams.first;
      expect(hd.urls.map((url) => '$url'), ['$_cdn/a_hd.flv', '$_cdn/b_hd.flv']);
      expect((hd.resolution, hd.bitrate), ('720x1280', 1800000), reason: 'filled from the second container');
      expect(streams.last.codec, 'h265', reason: 'hevcStreamData without VCodec is H.265');
    });

    test("codec names: 3.x's (avc, hevc, h264, h265, any case, v_codec) and bytevc1; anything else fails", () {
      for (final (sdk, codec) in [
        ({'VCodec': 'avc'}, 'h264'),
        ({'VCodec': 'HEVC'}, 'h265'),
        ({'VCodec': 'H264'}, 'h264'),
        ({'v_codec': 'h265'}, 'h265'),
        ({'VCodec': 'bytevc1'}, 'h265'),
        (<String, Object?>{}, 'h264'),
      ]) {
        final streams = _streams(_withStreams(_container({'hd': _tier(flv: '$_cdn/x.flv', sdk: sdk)})));
        expect(streams.single.codec, codec, reason: '$sdk');
      }
      for (final sdk in [
        {'VCodec': 'vp9'},
        {'VCodec': 264},
      ]) {
        expect(
          () => _streams(_withStreams(_container({'hd': _tier(flv: '$_cdn/x.flv', sdk: sdk)}))),
          throwsA(isA<ApiChanged>()),
          reason: '$sdk',
        );
      }
    });

    test(
      'resolutions 3.x accepted (720x1280, 720p) and blanks for others; unknown tiers are upper case, ranked 1000',
      () {
        final streams = _streams(
          _withStreams(
            _container({
              'hd': _tier(flv: '$_cdn/hd.flv', sdk: {'resolution': '720p'}),
              'md': _tier(hls: '$_cdn/md.m3u8', sdk: {'resolution': 'big'}),
            }),
          ),
        );
        expect(streams.map(TikTokApi.qualityName), ['高清 · 720p · H264 · FLV', 'MD · H264 · HLS']);
        expect(streams.map(TikTokApi.qualitySort), [6120, 1110]);
      },
    );

    test("URLs must be https on a trusted host without fragment or spaces (3.x's rule, regional CDNs added)", () {
      for (final url in [
        'https://pull-f5-tt01.tiktokcdn.com/x.flv',
        'https://pull-f5-tt01.tiktokcdn-us.com/x.flv',
        'https://pull-f5.tiktokcdn-eu.com/x.flv',
        'https://pull.tiktokv.com/x.flv',
        'https://pull.byteoversea.com/x.flv',
      ]) {
        expect(_streams(_withStreams(_container({'hd': _tier(flv: url)}))).single.urls.single, Uri.parse(url));
      }
      for (final url in [
        'http://pull-f5-tt01.tiktokcdn.com/x.flv',
        'https://pull.example.test/x.flv',
        'https://tiktokcdn.com.evil.test/x.flv',
        'https://pull.tiktokcdn.com/x.flv#t',
        'https://user@pull.tiktokcdn.com/x.flv',
        'https://pull.tiktokcdn.com/x y.flv',
      ]) {
        expect(
          () => _streams(_withStreams(_container({'hd': _tier(flv: url)}))),
          throwsA(isA<ApiChanged>()),
          reason: url,
        );
      }
    });

    test('bad containers fail the answer; an empty stream_data or a missing container is skipped', () {
      expect(_streams(_withStreams(null)), isEmpty);
      expect(
        _streams(
          _withStreams({
            'pull_data': {'stream_data': ''},
          }),
        ),
        isEmpty,
      );
      final tooMany = {for (var index = 0; index < 33; index++) 't$index': _tier(flv: '$_cdn/$index.flv')};
      for (final container in <Object?>[
        'x',
        {'pull_data': null},
        {
          'pull_data': {'stream_data': 'not json'},
        },
        {
          'pull_data': {'stream_data': '[]'},
        },
        {
          'pull_data': {
            'stream_data': jsonEncode({'data': 'x'}),
          },
        },
        _container(tooMany),
        _container({'h-d': _tier(flv: '$_cdn/x.flv')}),
        _container({'hd': 'x'}),
        _container({
          'hd': {'main': null},
        }),
        _container({'hd': _tier(flv: '$_cdn/x.flv', sdk: 'not json')}),
        _container({
          'hd': _tier(flv: '$_cdn/x.flv', sdk: {'vbitrate': -1}),
        }),
        _container({
          'hd': {
            'main': {'flv': 5},
          },
        }),
      ]) {
        final json = _liveJson();
        _live(json)['streamData'] = container;
        expect(() => _room(jsonEncode(json), 'qvc'), throwsA(isA<ApiChanged>()), reason: '$container');
      }
    });

    test('streams are not read without media, or when the LIVE is not live, even when they are broken (3.x)', () {
      final json = _liveJson();
      _live(json)['streamData'] = _container({'hd': _tier(flv: 'http://evil.test/x.flv')});
      final body = jsonEncode(json);
      expect(_room(body, 'qvc', media: false).liveStatus, LiveStatus.live);
      _live(json)['status'] = 4;
      expect(_data(_room(jsonEncode(json), 'qvc')).streams, isEmpty);
      expect(() => _room(body, 'qvc'), throwsA(isA<ApiChanged>()));
    });

    test('live without a stream is StreamUnavailable to play (3.x refused the whole room)', () {
      final data = _data(_room(_withStreams(null), 'qvc'));
      expect(data.state, TikTokState.live);
      expect(TikTokApi.unplayable(data), isA<StreamUnavailable>());
      expect(TikTokApi.qualities(data), isEmpty);
    });
  });
}
