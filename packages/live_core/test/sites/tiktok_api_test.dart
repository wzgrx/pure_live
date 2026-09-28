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

/// Keys that differ from 3.x's frozen output on every sample card:
/// - httpHeaders: 3.x also wrote the media headers into the room, which
///   only IPTV's player path read (playback_header_resolver.dart:143-147);
///   they now travel with every line (asserted in "lines");
/// - notice: 3.x's `tiktok_chat_notice` said for viewers (the unified rule
///   on notices, M4.U.22; asserted in "card fields").
const _headersMoved = {'httpHeaders', 'notice'};

/// avatar, cover: the samples' pictures are on the regional CDN
/// tiktokcdn-us.com, which 3.x did not trust (it showed none).
const Set<String> _picturesTrusted = {'avatar', 'cover', ..._headersMoved};

/// S01-user-live's `liveRoom.startTime` (1790532724).
final DateTime _started = DateTime.utc(2026, 9, 27, 18, 12, 4);

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
      expect((data.state, data.status, data.restriction), (TikTokState.live, 2, LiveRestriction.none));
      expect(data.secUid, startsWith('MS4wLjABAAAA'));
      expect(data.streams, hasLength(7), reason: "3.x's 14 qualities, FLV and HLS now one quality each (22-2)");
      expect(data.skipped, isEmpty);
      expect(data.issuedAt, _issued);
      expect(TikTokApi.unplayable(data), isNull);
    });

    test('S01-user-live: the start and who may watch (M4.U.22, new keys; 3.x had neither)', () {
      final body = _sample('S01-user-live').body;
      for (final media in [true, false]) {
        final room = _room(body, 'qvc', media: media);
        expect((room.startedAt, room.restriction), (_started, LiveRestriction.none));
        final json = room.toJson();
        expect((json['startedAt'], json['restriction']), ('2026-09-27T18:12:04.000Z', 'none'));
        final legacy = _result(_legacy('S01-user-live')['getRoomDetailForRefresh(qvc)'])! as Map<String, dynamic>;
        expect(legacy.keys, isNot(anyOf(contains('startedAt'), contains('restriction'))));
      }
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
      final legacy = _result(_legacy('S01-user-live')['getRoomDetailForRefresh(qvc)'])! as Map<String, dynamic>;
      expect(legacy['notice'], 'TikTok LIVE 远端聊天尚待接入；当前观看与累计进房分别展示。');
      expect(room.notice, 'TikTok 直播的评论暂时不能在这里显示。在线人数是正在看的人数，累计是进过直播间的人数。');
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
      expect((data.state, data.status, data.restriction), (TikTokState.offline, 4, null));
      expect(data.streams, isEmpty);
      expect(fixture.body, contains('stream_data'));
      expect(fixture.body, contains('"startTime":'), reason: "the last LIVE's start, not filled while offline");
      expect((room.startedAt, room.restriction), (null, null));
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

    // With "优先 H.264" on (the default, 22-3): H.264 first, then H.265.
    const preferred = [
      ('原画', 'h264:origin', 10100),
      ('720p', 'h264:hd', 6100),
      ('1080p60 · H.265', 'h265:uhd_60', 9000),
      ('720p60 · H.265', 'h265:hd_60', 8000),
      ('720p · H.265', 'h265:hd', 6000),
      ('540p · H.265', 'h265:sd', 5000),
      ('360p · H.265', 'h265:ld', 4000),
    ];

    List<(String, Object?, int)> project(List<LivePlayQuality> qualities) => [
      for (final quality in qualities) (quality.quality, quality.id, quality.sort),
    ];

    test('changed: one quality per tier and codec (22-2), named as the site does (22-4), H.264 first (22-3)', () {
      for (final body in [_trusted(_sample('S01-user-live').body), _sample('S01-user-live').body]) {
        final data = _data(_room(body, 'qvc'));
        expect(project(TikTokApi.qualities(data)), preferred);
        // Off: 3.x's order, best tier first, H.264 before H.265 within a tier.
        expect(project(TikTokApi.qualities(data, preferH264: false)), [
          preferred[0],
          preferred[2],
          preferred[3],
          preferred[1],
          preferred[4],
          preferred[5],
          preferred[6],
        ]);
      }
      expect(wanted, hasLength(14), reason: '3.x: one quality per protocol');
      expect(
        wanted.first['quality'],
        '原始画质 · 1080x1920 · H264 · FLV',
        reason: 'hevcStreamData carries the H.264 origin',
      );
    });

    test("every 3.x quality id maps to one now (for M9), in 3.x's relative order", () {
      final data = _data(_room(_sample('S01-user-live').body, 'qvc'));
      final mapped = [for (final quality in wanted) TikTokApi.qualityIdFromLegacy(quality['id'] as String)];
      expect(mapped.toSet().toList(), [for (final quality in TikTokApi.qualities(data, preferH264: false)) quality.id]);
      expect(TikTokApi.qualityIdFromLegacy('h264:origin:flv'), 'h264:origin');
      expect(TikTokApi.qualityIdFromLegacy(' H265:UHD_60:HLS '), 'h265:uhd_60');
      for (final id in ['h264:origin', 'h264:origin:dash', 'origin', 'flv', '']) {
        expect(TikTokApi.qualityIdFromLegacy(id), id, reason: 'not a 3.x id: kept');
      }
    });

    test("changed: 3.x's two qualities of a tier are its FLV then HLS lines (22-2); a 3.x id plays its quality", () {
      final trusted = _data(_room(_trusted(_sample('S01-user-live').body), 'qvc'));
      final recorded = _data(_room(_sample('S01-user-live').body, 'qvc'));
      final urls = legacy['resolvePlayUrlsRaw'] as Map<String, dynamic>;
      List<Object?> legacyUrls(String id) => (_result(urls[id])! as Map<String, dynamic>)['urls'] as List<Object?>;
      for (final quality in TikTokApi.qualities(trusted)) {
        final resolution = TikTokApi.resolution(trusted, quality);
        expect(resolution.urls, [...legacyUrls('${quality.id}:flv'), ...legacyUrls('${quality.id}:hls')]);
        expect(resolution.appliedQualityData, quality.id);
        expect(TikTokApi.resolution(recorded, quality).urls, [
          for (final url in resolution.urls) url.replaceAll('tiktokcdn.com', 'tiktokcdn-us.com'),
        ]);
      }
      for (final old in wanted) {
        final id = old['id'] as String;
        final resolution = TikTokApi.resolution(trusted, LivePlayQuality(quality: '', id: id));
        expect(resolution.appliedQualityData, TikTokApi.qualityIdFromLegacy(id));
        expect(resolution.urls, containsAll(legacyUrls(id)));
      }
    });

    test("lines: 3.x's media headers, FLV then HLS, the codec, the protocol as line id, the lease of `expire`", () {
      final data = _data(_room(_sample('S01-user-live').body, 'qvc'));
      final headers =
          (_result(legacy['getRoomDetail'])! as Map<String, dynamic>)['httpHeaders'] as Map<String, dynamic>;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(1791749747 * 1000, isUtc: true);
      for (final quality in TikTokApi.qualities(data)) {
        final lines = TikTokApi.resolution(data, quality).lines;
        expect(lines.map((line) => (line.format, line.lineId)), [(StreamFormat.flv, 'flv'), (StreamFormat.hls, 'hls')]);
        expect(Uri.parse(lines.first.url).host, 'pull-f5-tt01.tiktokcdn-us.com');
        expect(Uri.parse(lines.last.url).host, 'pull-hls-f16-tt01.tiktokcdn-us.com');
        for (final line in lines) {
          expect(line.headers, headers, reason: 'PlaybackHeaderResolver sent TikTokApi.mediaHeaders');
          expect(line.headers, TikTokApi.mediaHeaders('qvc'));
          expect(line.codec, '${quality.id}'.startsWith('h264') ? 'avc' : 'hevc');
          expect(line.lease!.expiresAt, expiresAt, reason: 'signed for about 14 days');
          expect(line.lease!.refreshAt, expiresAt.subtract(const Duration(hours: 1)));
          expect(line.lease!.cutsConnection, isFalse);
        }
      }
    });

    test('a quality the LIVE does not offer is StreamUnavailable (3.x: mediaUnavailable)', () {
      final data = _data(_room(_sample('S01-user-live').body, 'qvc'));
      for (final id in ['h264:uhd', 'h264:uhd:flv', 'h265:origin']) {
        expect(
          () => TikTokApi.resolution(data, LivePlayQuality(quality: 'x', id: id)),
          throwsA(isA<StreamUnavailable>()),
          reason: id,
        );
      }
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
    test('22-1: a private account, subscribers only, paid, in that order: live and marked; no streams read', () {
      for (final (edit, restriction) in <(void Function(Map<String, dynamic>), LiveRestriction)>[
        ((json) => _user(json)['secret'] = true, LiveRestriction.private),
        ((json) => _live(json)['liveSubOnly'] = 1, LiveRestriction.subscribersOnly),
        ((json) => _live(json)['liveSubOnly'] = '1', LiveRestriction.subscribersOnly),
        ((json) => (_live(json)['paidEvent'] as Map)['paid_type'] = 2, LiveRestriction.paid),
        (
          (json) {
            _user(json)['secret'] = true;
            _live(json)['liveSubOnly'] = 1;
          },
          LiveRestriction.private,
        ),
      ]) {
        final json = _liveJson();
        edit(json);
        final room = _room(jsonEncode(json), 'qvc');
        final data = _data(room);
        // 3.x: banned, "server error" at entry, recordings stopped as banned.
        expect((room.liveStatus, room.restriction, room.followGroup), (LiveStatus.live, restriction, FollowGroup.live));
        expect((data.state, data.restriction), (TikTokState.live, restriction));
        expect((room.isLiveNow, room.isRestricted, room.startedAt), (true, true, _started));
        expect(data.streams, isEmpty);
        expect((room.onlineViewers, room.totalViewers), ('203', '9492'), reason: 'a live LIVE, restricted or not');
        expect(TikTokApi.unplayable(data), isA<StreamUnavailable>(), reason: 'no TikTok login would help');
        expect(_room(jsonEncode(json), 'qvc', media: false).restriction, restriction, reason: 'refreshes mark it too');
      }
    });

    test('22-1: a restriction is kept only while live; the reasons name who may watch', () {
      final json = _liveJson();
      _user(json)['secret'] = true;
      _live(json)['status'] = 4;
      final offline = _room(jsonEncode(json), 'qvc');
      expect((offline.liveStatus, offline.restriction, offline.startedAt), (LiveStatus.offline, null, null));
      _live(json)['status'] = 3;
      expect(_room(jsonEncode(json), 'qvc').restriction, isNull);
      for (final (restriction, words) in [
        (LiveRestriction.private, 'followers only'),
        (LiveRestriction.subscribersOnly, 'subscribers only'),
        (LiveRestriction.paid, 'a paid LIVE'),
      ]) {
        final data = TikTokRoomData(
          username: 'qvc',
          userId: '',
          state: TikTokState.live,
          restriction: restriction,
          issuedAt: _issued,
        );
        expect(
          TikTokApi.unplayable(data),
          isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains(words)),
        );
      }
    });

    test('startTime: Unix seconds from 2000 to 2100, else none', () {
      expect(TikTokApi.startTime(1790532724), _started);
      expect(TikTokApi.startTime('1790532724'), _started);
      for (final value in [null, 0, -1, 'x', 946684799, 4102444801, 1790532724000]) {
        expect(TikTokApi.startTime(value), isNull, reason: '$value');
      }
      final json = _liveJson();
      _live(json)['startTime'] = 0;
      expect(_room(jsonEncode(json), 'qvc').startedAt, isNull);
      _live(json).remove('startTime');
      expect(_room(jsonEncode(json), 'qvc').startedAt, isNull);
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

    test("the identity, the state and who may watch keep 3.x's checks (ApiChanged: schema, identity)", () {
      for (final edit in <void Function(Map<String, dynamic>)>[
        (json) => json['data'] = null,
        (json) => (json['data'] as Map).remove('user'),
        (json) => (json['data'] as Map).remove('liveRoom'),
        (json) => _user(json)['uniqueId'] = 'cnn',
        (json) => _user(json)['uniqueId'] = 42,
        (json) => _user(json)['uniqueId'] = 'q v c',
        (json) => _user(json)['secret'] = 'no',
        (json) => _live(json)['paidEvent'] = 'free',
      ]) {
        final json = _liveJson();
        edit(json);
        expect(() => _room(jsonEncode(json), 'qvc'), throwsA(isA<ApiChanged>()), reason: '$edit');
      }
    });

    test('changed: a malformed field that only fills the card is left empty (22-6; 3.x failed the whole room)', () {
      for (final (edit, check) in <(void Function(Map<String, dynamic>), void Function(LiveRoom))>[
        ((json) => (json['data'] as Map)['stats'] = 'x', (room) => expect(room.followers, '')),
        ((json) => (json['data'] as Map)['stats'] = {'followerCount': -5}, (room) => expect(room.followers, '')),
        ((json) => _user(json)['nickname'] = ' ', (room) => expect((room.nick, room.hasNick), ('', false))),
        ((json) => _user(json)['nickname'] = 7, (room) => expect(room.nick, '')),
        ((json) => _user(json)['id'] = '123', (room) => expect(room.userId, '')),
        ((json) => _user(json).remove('id'), (room) => expect(_data(room).userId, '')),
        ((json) => _user(json)['roomId'] = 'abc', (room) => expect(_data(room).liveRoomId, '')),
        ((json) => _user(json)['verified'] = 1, (room) => expect(room.nick, 'QVC, Inc')),
        ((json) => _user(json)['signature'] = 5, (room) => expect(room.introduction, '')),
        ((json) => _user(json)['secUid'] = false, (room) => expect(_data(room).secUid, '')),
        ((json) => _live(json)['streamId'] = '12', (room) => expect(_data(room).streamId, '')),
        ((json) => _live(json)['title'] = 3, (room) => expect(room.title, 'QVC, Inc')),
        ((json) => _live(json)['liveRoomStats'] = <Object?>[], (room) => expect(room.onlineViewers, '')),
        (
          (json) => (_live(json)['liveRoomStats'] as Map)['userCount'] = -1,
          (room) => expect((room.onlineViewers, room.totalViewers), ('', '9492')),
        ),
        (
          (json) => (_live(json)['liveRoomStats'] as Map)['enterCount'] = 'many',
          (room) => expect((room.onlineViewers, room.totalViewers), ('203', '')),
        ),
      ]) {
        final json = _liveJson();
        edit(json);
        final room = _room(jsonEncode(json), 'qvc');
        expect((room.roomId, room.liveStatus), ('qvc', LiveStatus.live), reason: '$edit');
        expect(_data(room).streams, hasLength(7), reason: '$edit');
        check(room);
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
    test('both containers are read, merged by codec and tier (22-2); ao is left out; each URL once', () {
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
            'HD': _tier(flv: '$_cdn/b_hd.flv', hls: '$_cdn/a_hd.m3u8', sdk: {'VCodec': 'h264', 'vbitrate': 1800000}),
            'sd': _tier(flv: '$_cdn/a_sd.flv'),
          }),
        ),
      );
      expect(streams.map((stream) => stream.id), ['h264:hd', 'h265:sd']);
      final hd = streams.first;
      expect(hd.flvUrls.map((url) => '$url'), ['$_cdn/a_hd.flv', '$_cdn/b_hd.flv']);
      expect(hd.hlsUrls.map((url) => '$url'), ['$_cdn/a_hd.m3u8']);
      expect(hd.urls, [...hd.flvUrls, ...hd.hlsUrls]);
      expect((hd.resolution, hd.bitrate), ('720x1280', 1800000), reason: 'filled from the second container');
      expect(streams.last.codec, 'h265', reason: 'hevcStreamData without VCodec is H.265');
      final data = _data(_room(_withStreams(_container({'hd': _tier(flv: '$_cdn/a.flv', hls: '$_cdn/b.flv')})), 'qvc'));
      final lines = TikTokApi.resolution(data, TikTokApi.qualities(data).single).lines;
      expect(lines.map((line) => line.lineId), ['flv', 'hls']);
      final twice = _data(
        _room(
          _withStreams(
            _container({'hd': _tier(flv: '$_cdn/a.flv')}),
            _container({
              'hd': _tier(flv: '$_cdn/b.flv', sdk: {'VCodec': 'avc'}),
            }),
          ),
          'qvc',
        ),
      );
      expect(TikTokApi.resolution(twice, TikTokApi.qualities(twice).single).lines.map((line) => line.lineId), [
        'flv',
        'flv#2',
      ]);
    });

    test("22-4: the site's names from options.qualities, the source as 原画, H.265 marked; fallbacks", () {
      Map<String, dynamic> named(Map<String, Object?> tiers, List<Object?> qualities) {
        final container = _container(tiers);
        ((container['pull_data'] as Map)['options'] as Map)['qualities'] = qualities;
        return container;
      }

      final body = _withStreams(
        named(
          {
            'hd': _tier(flv: '$_cdn/1.flv', sdk: {'VCodec': 'h264', 'resolution': '720x1280'}),
          },
          [
            {'sdk_key': 'hd', 'name': 'HD 720'},
          ],
        ),
        named(
          {
            'origin': _tier(flv: '$_cdn/2.flv', sdk: {'VCodec': 'h265'}),
            'hd': _tier(flv: '$_cdn/3.flv', sdk: {'resolution': '720x1280'}),
            'uhd_60': _tier(flv: '$_cdn/4.flv', sdk: {'resolution': '1920x1080'}),
            'sd': _tier(flv: '$_cdn/5.flv', sdk: {'resolution': '540p'}),
            'auto': _tier(flv: '$_cdn/6.flv'),
            'md': _tier(flv: '$_cdn/7.flv'),
          },
          [
            {'sdk_key': 'origin', 'name': 'Original'},
            {'sdk_key': 'HD', 'name': ' 720p '},
            {'sdk_key': 'sd', 'name': ''},
            {'sdk_key': 'md', 'name': 'x' * 33},
            'bad',
            {'sdk_key': 5, 'name': 'five'},
          ],
        ),
      );
      final qualities = TikTokApi.qualities(_data(_room(body, 'qvc')));
      expect(
        [for (final quality in qualities) (quality.quality, quality.id)],
        [
          ('HD 720', 'h264:hd'),
          ('原画 · H.265', 'h265:origin'),
          ('1080p60 · H.265', 'h265:uhd_60'),
          ('720p · H.265', 'h265:hd'),
          ('540p · H.265', 'h265:sd'),
          ('自动 · H.265', 'h265:auto'),
          ('MD · H.265', 'h265:md'),
        ],
      );
      final twins = _withStreams(
        _container({
          'hd': _tier(flv: '$_cdn/1.flv', sdk: {'resolution': '720p'}),
          'uhd': _tier(flv: '$_cdn/2.flv', sdk: {'resolution': '720x1280'}),
        }),
      );
      expect(TikTokApi.qualities(_data(_room(twins, 'qvc'))).map((quality) => quality.quality), [
        '720p (uhd)',
        '720p (hd)',
      ]);
    });

    test("codec names: 3.x's (avc, hevc, h264, h265, any case, v_codec) and bytevc1; any other loses its tier", () {
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
        final data = _data(
          _room(
            _withStreams(_container({'hd': _tier(flv: '$_cdn/x.flv', sdk: sdk), 'sd': _tier(flv: '$_cdn/y.flv')})),
            'qvc',
          ),
        );
        expect(data.streams.map((stream) => stream.id), ['h264:sd'], reason: '$sdk');
        expect(data.skipped.single, contains('streamData.hd'));
      }
    });

    test('resolutions 3.x accepted (720x1280, 720p) and blanks for others; unknown tiers rank 1000', () {
      final streams = _streams(
        _withStreams(
          _container({
            'hd': _tier(flv: '$_cdn/hd.flv', sdk: {'resolution': '720p'}),
            'md': _tier(hls: '$_cdn/md.m3u8', sdk: {'resolution': 'big'}),
            'ld': _tier(hls: '$_cdn/ld.m3u8', sdk: {'resolution': 360}),
          }),
        ),
      );
      expect(streams.map((stream) => stream.resolution), ['720p', '', '']);
      expect(streams.map(TikTokApi.qualityName), ['720p', 'MD', '流畅']);
      expect(streams.map(TikTokApi.qualitySort), [6100, 1100, 4100]);
    });

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
        // Changed (the unified rule on bad data): only this line is lost.
        final streams = _streams(_withStreams(_container({'hd': _tier(flv: url, hls: '$_cdn/hd.m3u8')})));
        expect(streams.single.flvUrls, isEmpty, reason: url);
        expect(streams.single.hlsUrls.single, Uri.parse('$_cdn/hd.m3u8'), reason: url);
        final alone = _data(_room(_withStreams(_container({'hd': _tier(flv: url)})), 'qvc'));
        expect(alone.streams, isEmpty, reason: url);
        expect(alone.skipped.single, contains('streamData.hd.flv'), reason: url);
        expect(TikTokApi.unplayable(alone), isA<ApiChanged>(), reason: url);
      }
    });

    test('changed: a bad container or tier only loses itself; with nothing left, playing is ApiChanged', () {
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
      final good = _container({
        'hd': _tier(flv: '$_cdn/good.flv', sdk: {'VCodec': 'h265'}),
      });
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
        {
          'pull_data': {'stream_data': 5},
        },
        _container(tooMany),
        _container({'h-d': _tier(flv: '$_cdn/x.flv')}),
        _container({'hd': 'x'}),
        _container({
          'hd': {'main': null},
        }),
        _container({'hd': _tier(flv: '$_cdn/x.flv', sdk: 'not json')}),
        _container({
          'hd': {
            'main': {'flv': 5},
          },
        }),
      ]) {
        final json = _liveJson();
        _live(json)
          ..['streamData'] = container
          ..['hevcStreamData'] = good;
        final data = _data(_room(jsonEncode(json), 'qvc'));
        expect(data.streams.map((stream) => stream.id), ['h265:hd'], reason: '$container');
        expect(data.skipped, hasLength(1), reason: '$container');
        expect(TikTokApi.unplayable(data), isNull);
        _live(json).remove('hevcStreamData');
        final nothing = _data(_room(jsonEncode(json), 'qvc'));
        expect(nothing.streams, isEmpty);
        expect(TikTokApi.unplayable(nothing), isA<ApiChanged>(), reason: '$container');
      }
      // 3.x's negative bitrate failed the room; it is only left out now.
      final bitrate = _streams(
        _withStreams(
          _container({
            'hd': _tier(flv: '$_cdn/x.flv', sdk: {'vbitrate': -1}),
          }),
        ),
      );
      expect(bitrate.single.bitrate, isNull);
    });

    test('streams are not read without media, or when the LIVE is not live (3.x)', () {
      final json = _liveJson();
      _live(json)['streamData'] = _container({'hd': _tier(flv: 'http://evil.test/x.flv')});
      _live(json).remove('hevcStreamData');
      final body = jsonEncode(json);
      expect(_room(body, 'qvc', media: false).liveStatus, LiveStatus.live);
      expect(_data(_room(body, 'qvc')).skipped, isNotEmpty, reason: 'read at room entry');
      _live(json)['status'] = 4;
      final offline = _data(_room(jsonEncode(json), 'qvc'));
      expect([...offline.streams, ...offline.skipped], isEmpty);
    });

    test('live without a stream is StreamUnavailable to play (3.x refused the whole room)', () {
      final data = _data(_room(_withStreams(null), 'qvc'));
      expect(data.state, TikTokState.live);
      expect(TikTokApi.unplayable(data), isA<StreamUnavailable>());
      expect(TikTokApi.qualities(data), isEmpty);
    });
  });
}
