// Weibo parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/weibo/legacy_expected.dart from 3.x's WeiboApi, WeiboLink and
// WeiboSite). Every intended difference is listed with its reason;
// everything else must match. The synthetic cases port 3.x's
// weibo_api_test.dart, the link cases of weibo_site_test.dart and
// weibo_application_test.dart.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('weibo', name);

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

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

/// The `result` of a traced legacy call.
Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {String reason = ''}) {
  final expected = _maps(legacy);
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(_projection(room), expected[index], reason: '$reason[$index]');
  }
}

/// 3.x's test broadcast.
const _id = '1022:2321325000000000000000';

const _media = 'https://media.example.test/stream_wb720avc.flv?token=fixture';

/// [json] as decoded JSON: maps and lists of `dynamic`, so tests can edit
/// them freely.
Map<String, dynamic> _mutable(Map<String, Object?> json) => jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

/// 3.x's test room answer (legacy/test/fixtures/weibo/live-detail.json).
Map<String, dynamic> _liveDetail() => _mutable({
  'code': 100000,
  'msg': 'success',
  'error_code': 0,
  'data': {
    'liveId': _id,
    'status': 1,
    'cover': 'https://img.example.test/cover.jpg',
    'startTime': 1789038303000,
    'endTime': 0,
    'width': 1280,
    'height': 720,
    'mid': '5000000000000000',
    'createType': 2,
    'createSource': 1,
    'title': '公开直播样本',
    'watch_limit': 0,
    'user': {
      'uid': 101,
      'screenName': '样本 0',
      'profileImageUrl': 'https://img.example.test/avatar.jpg',
      'verified': 1,
      'avatar': 'https://img.example.test/avatar-large.jpg',
      'gender': 'm',
    },
    'following': 0,
    'live_origin_hls_url': _media,
    'live_origin_flv_url': _media,
    'replay_origin_url': '',
    'pay_live_status': 1,
    'play_switch': 1,
  },
});

/// 3.x's test snapshot (legacy/test/fixtures/weibo/recommend.json).
Map<String, dynamic> _recommend() => _mutable({
  'code': 100000,
  'msg': 'success',
  'error_code': 0,
  'data': {
    'data': [
      {'nickname': '样本 0', 'cover': 'https://img.example.test/cover.jpg', 'liveid': _id, 'uid': 101},
      {
        'nickname': '样本 1',
        'cover': 'https://img.example.test/cover.jpg',
        'liveid': '1022:2321325000000000000001',
        'uid': 102,
      },
    ],
  },
});

Map<String, dynamic> _row(Map<String, dynamic> json) => json['data'] as Map<String, dynamic>;

LiveRoom _detail(Map<String, dynamic> json, {int? ownerId = 101}) =>
    WeiboApi.detail(jsonEncode(json), liveId: _id, ownerId: ownerId);

WeiboRoomData _data(LiveRoom room) => room.data! as WeiboRoomData;

/// The samples' broadcasts.
const _live = '1022:2321325347923495092258';
const _watchLimit = '1022:2321325347904448757771';
const _endedReplay = '1022:2321325269875509035102';
const _notFound = '1022:2321320000000000000001';
const _ended = '1022:2320508a306db1bc389510651e77d5feb4f90d';
const _s03Live = '1022:2321325348206094712906';

void main() {
  group('snapshot', () {
    for (final name in ['S01-recommend', 'S03-recommend']) {
      test('$name: the catalog and the snapshot match 3.x', () {
        final fixture = _sample(name);
        final legacy = _legacy(name);
        final categories = WeiboApi.categories();
        final known = _maps(legacy['getCategores']).single;
        expect((categories.single.id, categories.single.name), (known['id'], known['name']));
        _expectParity(categories.single.children.single.toJson(), _maps(known['children']).single);
        final page = WeiboApi.recommendations(fixture.body, status: fixture.status);
        for (final key in ['getDirectoryPage', 'getDirectoryPage(category)']) {
          final want = _result(legacy[key])! as Map<String, dynamic>;
          expect((page.page, page.hasMore), (want['page'], want['hasMore']), reason: key);
          _expectRooms(page.rooms, want['rooms'], reason: '$name $key');
        }
      });

      test('$name: the nickname search matches 3.x', () {
        final rooms = WeiboApi.recommendations(_sample(name).body).rooms;
        final legacy = _legacy(name)['searchRooms'] as Map<String, dynamic>;
        for (final keyword in ['卫视', '学长', '发布', 'vortex', 'bang', '_', '小', ' 卫视 ', 'zxqvnoresultfixture']) {
          _expectRooms(
            WeiboApi.searchSnapshot(keyword, rooms, pageSize: 20),
            _result(legacy[keyword]),
            reason: keyword,
          );
        }
        _expectRooms(WeiboApi.searchSnapshot('_', rooms, pageSize: 3), _result(legacy['_ pageSize 3']));
        expect(WeiboApi.searchSnapshot('  ', rooms, pageSize: 20), isEmpty);
      });
    }

    test('S01-recommend: 51 rows (count=100); S03-recommend: 9 rows for the count=10 3.x asks', () {
      expect(WeiboApi.recommendations(_sample('S01-recommend').body).rooms, hasLength(51));
      expect(_sample('S03-recommend').url.queryParameters, {'count': '10', 'uid': ''});
      expect(WeiboApi.recommendations(_sample('S03-recommend').body).rooms, hasLength(9));
    });

    test("3.x's cards: the broadcast is the room, the uid apart; no state, no audience, the scope notice", () {
      final page = WeiboApi.recommendations(jsonEncode(_recommend()));
      expect(page.rooms.map((room) => room.userId), ['101', '102']);
      final card = page.rooms.first;
      expect((card.roomId, card.nick, card.title), (_id, '样本 0', '样本 0'));
      expect(card.liveStatus, LiveStatus.unknown, reason: 'the snapshot does not say');
      expect(card.link, 'https://weibo.com/l/wblive/p/show/$_id');
      expect(card.notice, WeiboApi.roomScopeNotice);
      expect((card.avatar, card.cover), ('', 'https://img.example.test/cover.jpg'));
      expect(card.watching, isEmpty);
      expect(card.audienceMetricType, AudienceMetricType.unknown);
      expect(card.onlineViewers, isEmpty);
      expect(card.supportsRealOnlineCount, isFalse);
      expect(card.audienceValue(preferRealOnline: false, platformEnabled: false), isEmpty);
      expect(card.data, isNull);
      expect(page.hasMore, isFalse);
      expect(() => page.rooms.add(card), throwsUnsupportedError);
    });

    test('a missing cover stays empty; a repeated broadcast or a bad row fails the list (3.x)', () {
      final json = _recommend();
      final rows = _row(json)['data'] as List;
      (rows[0] as Map)['cover'] = null;
      expect(WeiboApi.recommendations(jsonEncode(json)).rooms.first.cover, isEmpty);
      for (final edit in <void Function(Map<String, dynamic> row)>[
        (row) => row['liveid'] = '101',
        (row) => row['liveid'] = 1022,
        (row) => row['uid'] = 0,
        (row) => row['uid'] = '101',
        (row) => row['uid'] = 9007199254740992,
        (row) => row['nickname'] = null,
      ]) {
        final bad = _recommend();
        edit((_row(bad)['data'] as List).first as Map<String, dynamic>);
        expect(() => WeiboApi.recommendations(jsonEncode(bad)), throwsA(isA<ApiChanged>()), reason: '$bad');
      }
      rows.add(rows[0]);
      expect(() => WeiboApi.recommendations(jsonEncode(json)), throwsA(isA<ApiChanged>()), reason: 'twice');
      for (final data in <Object?>[
        {'data': 'rows'},
        {'data': List.generate(501, (index) => (rows[0] as Map).cast<String, Object?>())},
        [],
      ]) {
        expect(
          () => WeiboApi.recommendations(jsonEncode({'code': 100000, 'error_code': 0, 'data': data})),
          throwsA(isA<ApiChanged>()),
        );
      }
    });
  });

  group('detail', () {
    for (final (name, id) in [
      ('S02-live', _live),
      ('S02-watch-limit', _watchLimit),
      ('S02-ended-replay', _endedReplay),
      ('S03-live', _s03Live),
    ]) {
      test('$name: the room matches 3.x at every depth, under the broadcast asked for', () {
        final fixture = _sample(name);
        final legacy = _legacy(name);
        final room = WeiboApi.detail(fixture.body, liveId: id, status: fixture.status);
        // isRecord: a replay (status 3). 3.x set liveStatus replay but left
        // its separate isRecord flag false; the model derives the flag from
        // the one state (M2), so it now says true.
        final changed = {if (room.isRecord) 'isRecord'};
        for (final key in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
          _expectParity(
            _projection(room),
            _result(legacy[key])! as Map<String, dynamic>,
            changed: changed,
            reason: key,
          );
        }
        for (final key in ['searchRooms', 'searchRooms(link)', 'searchRooms(mobile link)']) {
          _expectParity(_projection(room), _maps(_result(legacy[key])).single, changed: changed, reason: key);
        }
        expect(room.roomId, id);
        expect(WeiboApi.externalRoomUrl(id), legacy['WeiboLink.url']);
        expect(_data(room).ownerId, int.parse(room.userId!));
      });
    }

    test('S02-live: public and live; the HLS field repeats the FLV, kept once (3.x)', () {
      final room = WeiboApi.detail(_sample('S02-live').body, liveId: _live);
      expect(room.isLiveNow, isTrue);
      final data = _data(room);
      expect((data.status, data.watchLimit, data.access), (1, 0, WeiboAccess.public));
      expect(data.mediaUrls, ['https://plwb01.live.weibo.com/alicdn/5347923496010310_wb720avc.flv']);
      expect(WeiboApi.unplayable(data), isNull);
      expect(room.avatar, contains('.50/'), reason: "3.x's small profileImageUrl, not the 1024 px avatar");
      expect(room.introduction, isNull);
    });

    test('S02-watch-limit: friends only; state unknown with the restriction notice, NeedsLogin to play (3.x)', () {
      final legacy = _legacy('S02-watch-limit');
      final room = WeiboApi.detail(_sample('S02-watch-limit').body, liveId: _watchLimit);
      expect(room.liveStatus, LiveStatus.unknown);
      expect(room.notice, '${WeiboApi.restrictedNotice}\n${WeiboApi.roomScopeNotice}');
      final data = _data(room);
      expect((data.status, data.watchLimit, data.access), (1, 10, WeiboAccess.restricted));
      expect(data.mediaUrls, isEmpty);
      expect(WeiboApi.unplayable(data), isA<NeedsLogin>());
      // 3.x's access failure, for the live status and the stream alike.
      expect(_result(legacy['getLiveStatus']), {'throws': 'WeiboException', 'message': 'Weibo access'});
      expect(legacy['getPlayQualites'], {'throws': 'WeiboException', 'message': 'Weibo access'});
    });

    test('S02-ended-replay: status 3 stays a replay (3.x); it does not play and its replay URL is not read', () {
      final legacy = _legacy('S02-ended-replay');
      final room = WeiboApi.detail(_sample('S02-ended-replay').body, liveId: _endedReplay);
      expect(room.liveStatus, LiveStatus.replay);
      expect(_data(room).mediaUrls, isEmpty);
      expect(WeiboApi.unplayable(_data(room)), isA<StreamUnavailable>());
      // changed: 3.x returned no qualities (the player got no reason); the
      // adapter now reports StreamUnavailable.
      expect(legacy['getPlayQualites'], isEmpty);
      expect(_result(legacy['getPlayUrls']), {'throws': 'WeiboException', 'message': 'Weibo notLive'});
      expect(_result(legacy['getLiveStatus']), isFalse);
    });

    test('S02-notfound: error_code 27401 is NotFound; 3.x called it an API error', () {
      final legacy = _legacy('S02-notfound');
      // changed: every depth. 3.x's generic `api` failure also made the exact
      // search fail, where it meant to answer nothing for a missing broadcast
      // (it did so for HTTP 404 only).
      for (final key in ['getRoomDetail', 'searchRooms']) {
        expect(_result(legacy[key]), {'throws': 'WeiboException', 'message': 'Weibo api'}, reason: key);
      }
      expect(() => WeiboApi.detail(_sample('S02-notfound').body, liveId: _notFound), throwsA(isA<NotFound>()));
    });

    test('S02-ended: an older id 3.x refused before asking now opens: status 5 is unknown, as 3.x mapped it', () {
      final legacy = _legacy('S02-ended');
      // changed: 3.x refused the id shape (`identity`, no request) and its
      // search fell back to the nickname filter; the id pattern is wider.
      expect(_result(legacy['getRoomDetail']), {'throws': 'WeiboException', 'message': 'Weibo identity'});
      expect((legacy['getRoomDetail'] as Map<String, dynamic>)['requests'], isEmpty);
      expect((legacy['WeiboLink.parse'] as Map<String, dynamic>).values, everyElement(isNull));
      final room = WeiboApi.detail(_sample('S02-ended').body, liveId: _ended);
      expect(room.liveStatus, LiveStatus.unknown, reason: "3.x's state for a status other than 1 and 3");
      expect((room.title, room.nick, room.userId), ('泸县地震救援现场', '央视新闻', '2656274875'));
      final data = _data(room);
      expect((data.status, data.access), (5, WeiboAccess.public));
      expect(data.mediaUrls, isEmpty);
      expect(WeiboApi.unplayable(data), isA<StreamUnavailable>());
    });

    test("3.x's captured live answer: the FLV behind the HLS field once; the owner apart", () {
      final room = _detail(_liveDetail());
      expect(room.isLiveNow, isTrue);
      expect(_data(room).mediaUrls, [_media]);
      expect((room.userId, room.roomId, room.nick), ('101', _id, '样本 0'));
      expect(() => _data(room).mediaUrls.clear(), throwsUnsupportedError);
    });

    test("3.x's missing-user answer (error_code 20003) is ApiChanged, not offline", () {
      const body = '{"code":999999,"msg":"User does not exists!","error_code":20003,"data":[]}';
      expect(() => WeiboApi.detail(body, liveId: _id), throwsA(isA<ApiChanged>()));
    });

    for (final mode in ['replay', 'unknown', 'disabled', 'restricted', 'trial', 'paid-restricted', 'app-only']) {
      test('$mode exports no live or replay URL (3.x)', () {
        final json = _liveDetail();
        final row = _row(json);
        switch (mode) {
          case 'replay':
            row['status'] = 3;
            row['replay_origin_url'] = 'https://media.example.test/replay.m3u8';
          case 'unknown':
            row['status'] = 99;
          case 'disabled':
            row['play_switch'] = 0;
          case 'restricted':
            row['watch_limit'] = 1;
            row['pay_live_status'] = 0;
          case 'trial':
            row['watch_limit'] = 1;
            row['pay_live_status'] = 0;
            row['free_watch_seconds'] = 60;
          case 'paid-restricted':
            row['watch_limit'] = 1;
            row['pay_live_status'] = 1;
          case 'app-only':
            row['watch_limit'] = 8;
        }
        final room = _detail(json);
        expect(_data(room).mediaUrls, isEmpty);
        expect(room.liveStatus, mode == 'replay' ? LiveStatus.replay : LiveStatus.unknown);
        expect(
          WeiboApi.unplayable(_data(room)),
          mode.contains('restricted') || mode == 'trial' || mode == 'app-only'
              ? isA<NeedsLogin>()
              : isA<StreamUnavailable>(),
        );
        expect(room.notice!.startsWith(WeiboApi.restrictedNotice), mode != 'replay' && mode != 'unknown');
      });
    }

    for (final bad in [
      'wrong-id',
      'wrong-owner',
      'missing-status',
      'string-status',
      'missing-limit',
      'invalid-pay',
      'missing-switch',
      'bad-width',
      'bad-title',
      'url-userinfo',
      'url-newline',
      'url-scheme',
      'bad-envelope',
      'missing-error',
      'wrong-success',
      'missing-hls',
    ]) {
      test('rejects $bad without a partial live result (3.x)', () {
        final json = _liveDetail();
        final row = _row(json);
        switch (bad) {
          case 'wrong-id':
            row['liveId'] = '1022:2321325000000000000001';
            row['watch_limit'] = 8;
          case 'wrong-owner':
            (row['user'] as Map)['uid'] = 999;
            row['watch_limit'] = 8;
          case 'missing-status':
            row.remove('status');
          case 'string-status':
            row['status'] = '1';
          case 'missing-limit':
            row.remove('watch_limit');
          case 'invalid-pay':
            row['pay_live_status'] = 2;
          case 'missing-switch':
            row.remove('play_switch');
          case 'bad-width':
            row['width'] = -1;
          case 'bad-title':
            row['title'] = null;
          case 'url-userinfo':
            row['live_origin_flv_url'] = 'https://user:secret@media.example.test/a.flv';
          case 'url-newline':
            row['live_origin_flv_url'] = 'https://media.example.test/\na.flv';
          case 'url-scheme':
            row['live_origin_flv_url'] = 'file:///private/a.flv';
          case 'bad-envelope':
            json['data'] = <Object?>[];
          case 'missing-error':
            json.remove('error_code');
          case 'wrong-success':
            json['code'] = 0;
          case 'missing-hls':
            row.remove('live_origin_hls_url');
        }
        expect(() => _detail(json), throwsA(isA<ApiChanged>()));
      });
    }

    test('without an expected owner any anchor is taken; the broadcast must still be the one asked for', () {
      final json = _liveDetail();
      (_row(json)['user'] as Map)['uid'] = 999;
      expect(_detail(json, ownerId: null).userId, '999');
      expect(() => WeiboApi.detail(jsonEncode(_liveDetail()), liveId: _live), throwsA(isA<ApiChanged>()));
    });

    test('an empty live answer is live but has nothing to play (3.x)', () {
      final json = _liveDetail();
      _row(json)
        ..['live_origin_hls_url'] = ''
        ..['live_origin_flv_url'] = '';
      final room = _detail(json);
      expect(room.isLiveNow, isTrue);
      expect(_data(room).mediaUrls, isEmpty);
      expect(WeiboApi.unplayable(_data(room)), isA<StreamUnavailable>());
    });

    test('27401 is NotFound for the detail only; HTTP errors are typed and never offline', () {
      const missing = '{"code":999999,"msg":"LiveRoom does not exists!","error_code":27401,"data":[]}';
      expect(() => WeiboApi.detail(missing, liveId: _id), throwsA(isA<NotFound>()));
      expect(() => WeiboApi.recommendations(missing), throwsA(isA<ApiChanged>()));
      for (final (status, matcher) in [
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (503, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
      ]) {
        expect(() => WeiboApi.recommendations('private raw body', status: status), throwsA(matcher), reason: '$status');
        expect(
          () => WeiboApi.detail('', liveId: _id, status: status),
          throwsA(matcher),
          reason: '$status',
        );
      }
    });

    test('an oversized or malformed answer is ApiChanged (3.x)', () {
      for (final text in ['x' * (WeiboApi.responseLimit + 1), '<html>failure</html>', '[]', '"text"']) {
        expect(() => WeiboApi.recommendations(text), throwsA(isA<ApiChanged>()));
        expect(() => WeiboApi.detail(text, liveId: _id), throwsA(isA<ApiChanged>()));
      }
      final wide = jsonEncode({..._recommend(), 'pad': '微' * (WeiboApi.responseLimit ~/ 3)});
      expect(wide.length, lessThan(WeiboApi.responseLimit));
      expect(() => WeiboApi.recommendations(wide), throwsA(isA<ApiChanged>()), reason: 'counted in UTF-8 bytes');
    });
  });

  group('streams', () {
    for (final (name, id) in [('S02-live', _live), ('S03-live', _s03Live)]) {
      test("$name: 3.x's quality and URLs, as one self-describing line", () {
        final legacy = _legacy(name);
        final quality = _maps(legacy['getPlayQualites']).single;
        expect(
          (WeiboApi.original.quality, WeiboApi.original.id, WeiboApi.original.sort),
          (quality['quality'], quality['id'], quality['sort']),
        );
        final room = WeiboApi.detail(_sample(name).body, liveId: id);
        final resolution = WeiboApi.resolution(_data(room).mediaUrls);
        expect(resolution.urls, _result(legacy['getPlayUrls']));
        final raw = _result(legacy['resolvePlayUrlsRaw'])! as Map<String, dynamic>;
        expect(resolution.urls, raw['urls']);
        expect(resolution.appliedQualityData, raw['appliedQualityData']);
        final line = resolution.lines.single;
        expect(line.headers, isEmpty, reason: "3.x's PlaybackHeaderResolver had no Weibo branch");
        expect((line.format, line.codec, line.lineId, line.lease), (StreamFormat.flv, 'avc', 'alicdn', null));
      });
    }

    test('a real HLS playlist in the HLS field is a second line (3.x kept both, unrewritten)', () {
      final json = _liveDetail();
      _row(json)['live_origin_hls_url'] = 'https://media.example.test/live/playlist.m3u8?token=x';
      final lines = WeiboApi.resolution(_data(_detail(json)).mediaUrls).lines;
      expect(lines.map((line) => line.url), [_media, 'https://media.example.test/live/playlist.m3u8?token=x']);
      expect(lines.map((line) => line.format), [StreamFormat.flv, StreamFormat.hls]);
      expect(lines.map((line) => line.lineId), ['media.example.test', 'live']);
      expect(lines.last.codec, isNull);
    });

    test("the stream name's codec, and no format for an unknown extension", () {
      final hevc = WeiboApi.line('https://cdn.test/alicdn/1_wb1080hevc.flv');
      expect((hevc.codec, hevc.format), ('hevc', StreamFormat.flv));
      final other = WeiboApi.line('https://cdn.test/a/stream');
      expect((other.codec, other.format), (null, null));
    });
  });

  group('links', () {
    for (final input in [
      'https://weibo.com/l/wblive/p/show/$_id',
      'http://www.weibo.com/l/wblive/m/show/$_id/',
      'https://WEIBO.COM:443/l/wblive/p/show/${_id.replaceAll(':', '%3A')}?from=share#live',
      'https://weibo.com/l/wblive/m/show/1042152%3a8e4d2f2900a81be5a8ece15da4dd443a',
      '  https://weibo.com/l/wblive/p/show/$_id  ',
    ]) {
      test('an official watch link: ${jsonEncode(input)} (3.x)', () {
        final id = WeiboApi.liveIdFromUrl(input);
        expect(id, isNotNull);
        expect(WeiboApi.exactRoom(input), id);
        expect(WeiboApi.liveIdFromUrl(WeiboApi.roomUrl(id!)), id);
      });
    }

    test('a bare broadcast id is an exact search, not a link (3.x)', () {
      for (final id in [_id, ' $_id ', '1042152:8e4d2f2900a81be5a8ece15da4dd443a']) {
        expect(WeiboApi.exactRoom(id), id.trim());
        expect(WeiboApi.liveIdFromUrl(id), isNull);
      }
      expect(
        WeiboApi.exactRoom('1042152:8e4d2f2900a81be5a8ece15da4dd443a'),
        '1042152:8e4d2f2900a81be5a8ece15da4dd443a',
      );
    });

    for (final input in [
      '101',
      'nickname',
      '样本 1',
      'https://weibo.com/u/101',
      'https://weibo.com/123/post',
      'https://weibo.com.evil.test/l/wblive/p/show/$_id',
      'https://weibo.com@evil.test/l/wblive/p/show/$_id',
      'https://user@weibo.com/l/wblive/p/show/$_id',
      'https://weibo.com:444/l/wblive/p/show/$_id',
      'file:///l/wblive/p/show/$_id',
      'ftp://weibo.com/l/wblive/p/show/$_id',
      'https://weibo.com/l/wblive/p/show/$_id/extra',
      'https://weibo.com/l/wblive/p/./show/$_id',
      'https://weibo.com/l/wblive/p/x/../show/$_id',
      'https://weibo.com/l/wblive/p/show/${_id.replaceAll(':', '%253A')}',
      'https://weibo.com/l/wblive/p/show/${_id.replaceAll(':', '%3A')}%2F',
      'https://weibo.com/l/wblive/p/show/$_id/.',
      'https://weibo.com/l/wblive/p/show/$_id/..',
      'https://weibo.com/l/wblive/p/show/$_id/..)',
      'https://weibo.com/l/wblive/p/show/$_id/%2e',
      'https://t.cn/fixture',
      'https://weibo.com/l/wblive/app/h5_compatible?live_id=$_id',
      'https://weibo.com/l/wblive/p/show/1022:23',
      'https://weibo.com/l/wblive/p/show/10 22:2321325000000000000000',
      '$_id/x',
      '$_id?x=1',
      '1042152:wrong',
    ]) {
      test('not a room: ${jsonEncode(input)} (3.x)', () {
        expect(WeiboApi.liveIdFromUrl(input), isNull);
        expect(WeiboApi.exactRoom(input), isNull);
      });
    }

    test('the wider id pattern takes the older ids 3.x refused; 3.x-valid ids stay valid', () {
      expect(WeiboApi.isLiveId(_ended), isTrue);
      expect(WeiboApi.liveIdFromUrl('https://weibo.com/l/wblive/p/show/$_ended'), _ended);
      for (final id in [_id, '1042152:8e4d2f2900a81be5a8ece15da4dd443a', _live, _watchLimit]) {
        expect(WeiboApi.isLiveId(id), isTrue, reason: id);
      }
      for (final id in ['$_id\n', '12:2321325000000000000000', '123456789:2321325000000000000000', '1022:abc']) {
        expect(WeiboApi.isLiveId(id), isFalse, reason: id);
      }
    });

    test("the media centre's links (the site redirects them to the watch page)", () {
      expect(WeiboApi.liveIdFromUrl('https://live.media.weibo.com/live/show?id=$_live'), _live);
      expect(WeiboApi.liveIdFromUrl('http://live.media.weibo.com/live/show?id=${_live.replaceAll(':', '%3A')}'), _live);
      for (final invalid in [
        'https://live.media.weibo.com/live/show?id=$_live&id=$_id',
        'https://live.media.weibo.com/live/show',
        'https://live.media.weibo.com/live/other?id=$_live',
        'https://live.media.weibo.com/live/show?id=101',
        'https://live.media.weibo.com.evil.test/live/show?id=$_live',
      ]) {
        expect(WeiboApi.liveIdFromUrl(invalid), isNull, reason: invalid);
      }
    });

    test('opening in the browser uses the canonical page of a broadcast id, never the stored link (3.x)', () {
      expect(WeiboApi.externalRoomUrl(' $_id '), 'https://weibo.com/l/wblive/p/show/$_id');
      expect(WeiboApi.externalRoomUrl('101'), isNull);
      expect(WeiboApi.externalRoomUrl(''), isNull);
    });
  });
}
