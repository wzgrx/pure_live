// Weibo parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/weibo/legacy_expected.dart from 3.x's WeiboApi, WeiboLink and
// WeiboSite). Every intended difference is listed with its reason (the
// upgrade ids of docs/specs/UPGRADES.md for M4.U); everything else must match.
// The synthetic cases port 3.x's weibo_api_test.dart, the link cases of
// weibo_site_test.dart and weibo_application_test.dart. The S04 samples
// (2026-09-28) have no 3.x output.
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

/// Keys of a snapshot card that differ from 3.x on purpose:
/// - `liveStatus`, `status`: 18-2, the snapshot lists live broadcasts only
///   (3.x: unknown, false);
/// - `notice`: the unified rule on explanations, reworded for users (3.x's
///   `weibo_room_scope`).
const _cardChanges = {'liveStatus', 'status', 'notice'};

/// 3.x's room notice (zh.json `weibo_room_scope`) and restriction line
/// (`weibo_restricted`).
const _legacyScope = '收藏跟踪当前直播场次，不是主播账号；新场次需重新导入直播链接。';
const _legacyRestricted = '当前场次存在访问限制或播放已关闭；公开直播源不可用。';

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {String reason = ''}) {
  final expected = _maps(legacy);
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(_projection(room), expected[index], changed: _cardChanges, reason: '$reason[$index]');
    final card = expected[index];
    expect((card['liveStatus'], card['status'], card['notice']), (LiveStatus.unknown.index, false, _legacyScope));
    expect((room.liveStatus, room.toJson()['status'], room.notice), (LiveStatus.live, true, WeiboApi.roomScopeNotice));
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

/// S04-shortlink-room: where the short link of S04-shortlink leads.
const _shortLinkRoom = '1022:2321325347771573207158';

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

    test('18-1: the snapshot asks count=100 (S01-recommend: 51 rows); 3.x asked count=10 (S03-recommend: 9)', () {
      expect(WeiboApi.recommendUrl.queryParameters, {'count': '100', 'uid': ''});
      expect(_sample('S01-recommend').url, WeiboApi.recommendUrl);
      expect(WeiboApi.recommendations(_sample('S01-recommend').body).rooms, hasLength(51));
      expect(_sample('S03-recommend').url.queryParameters, {'count': '${WeiboApi.legacyRecommendCount}', 'uid': ''});
      expect(WeiboApi.recommendations(_sample('S03-recommend').body).rooms, hasLength(9));
    });

    test("3.x's cards: the broadcast is the room, the uid apart; live (18-2), no audience, the scope notice", () {
      final page = WeiboApi.recommendations(jsonEncode(_recommend()));
      expect(page.rooms.map((room) => room.userId), ['101', '102']);
      final card = page.rooms.first;
      expect((card.roomId, card.nick, card.title), (_id, '样本 0', '样本 0'));
      expect(card.liveStatus, LiveStatus.live, reason: '18-2: the snapshot lists live broadcasts only');
      expect(card.followGroup, FollowGroup.live);
      expect((card.restriction, card.startedAt), (null, null), reason: 'the snapshot tells neither');
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

    test('a missing cover stays empty; 18-8: a row without a broadcast id or listed before is skipped', () {
      final json = _recommend();
      final rows = _row(json)['data'] as List;
      (rows[0] as Map)['cover'] = null;
      expect(WeiboApi.recommendations(jsonEncode(json)).rooms.first.cover, isEmpty);
      // 3.x failed the whole list on each of these rows.
      for (final edit in <void Function(Map<String, dynamic> row)>[
        (row) => row['liveid'] = '101',
        (row) => row['liveid'] = 1022,
        (row) => row.remove('liveid'),
        (row) => row['liveid'] = '1042152:wrong',
      ]) {
        final bad = _recommend();
        edit((_row(bad)['data'] as List).first as Map<String, dynamic>);
        final rooms = WeiboApi.recommendations(jsonEncode(bad)).rooms;
        expect(rooms.map((room) => room.roomId), ['1022:2321325000000000000001'], reason: '$bad');
      }
      final twice = _recommend();
      final twiceRows = _row(twice)['data'] as List;
      twiceRows.insert(1, {...twiceRows.first as Map<String, dynamic>, 'nickname': 'again'});
      final rooms = WeiboApi.recommendations(jsonEncode(twice)).rooms;
      expect(rooms.map((room) => (room.roomId, room.nick)), [(_id, '样本 0'), ('1022:2321325000000000000001', '样本 1')]);
      final mixed = _recommend();
      (_row(mixed)['data'] as List).insertAll(0, <Object?>['row', null, 7, <Object?>[]]);
      expect(WeiboApi.recommendations(jsonEncode(mixed)).rooms, hasLength(2), reason: 'rows that are no objects');
    });

    test('18-8: a bad uid or nickname only leaves that field empty; 3.x failed the list', () {
      for (final (edit, userId, nick) in <(void Function(Map<String, dynamic> row), String?, String)>[
        ((row) => row['uid'] = 0, null, '样本 0'),
        ((row) => row['uid'] = '101', null, '样本 0'),
        ((row) => row['uid'] = 9007199254740992, null, '样本 0'),
        ((row) => row.remove('uid'), null, '样本 0'),
        ((row) => row['nickname'] = null, '101', ''),
        ((row) => row['nickname'] = 7, '101', ''),
      ]) {
        final json = _recommend();
        edit((_row(json)['data'] as List).first as Map<String, dynamic>);
        final card = WeiboApi.recommendations(jsonEncode(json)).rooms.first;
        expect((card.roomId, card.userId, card.nick, card.title), (_id, userId, nick, nick), reason: '$json');
      }
    });

    test('18-8: a list of only bad rows, no list or over 500 rows is ApiChanged; an empty list is empty', () {
      final row = (_row(_recommend())['data'] as List).first as Map<String, dynamic>;
      for (final data in <Object?>[
        {'data': 'rows'},
        {'data': List.generate(501, (index) => row)},
        {
          'data': [
            {...row, 'liveid': '101'},
            'row',
          ],
        },
        [],
      ]) {
        expect(
          () => WeiboApi.recommendations(jsonEncode({'code': 100000, 'error_code': 0, 'data': data})),
          throwsA(isA<ApiChanged>()),
          reason: '$data',
        );
      }
      final empty = WeiboApi.recommendations(
        jsonEncode({
          'code': 100000,
          'error_code': 0,
          'data': {'data': <Object?>[]},
        }),
      );
      expect(empty.rooms, isEmpty);
      expect(empty.hasMore, isFalse);
    });

    test('18-7: nicknames decode HTML character references, and the search filters the decoded name', () {
      final json = _recommend();
      ((_row(json)['data'] as List).first as Map)['nickname'] = 'Tom &amp; Jerry&#39;s &lt;live&gt;';
      final rooms = WeiboApi.recommendations(jsonEncode(json)).rooms;
      expect((rooms.first.nick, rooms.first.title), ("Tom & Jerry's <live>", "Tom & Jerry's <live>"));
      expect(WeiboApi.searchSnapshot('& jerry', rooms, pageSize: 20).single.roomId, _id);
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
        final restrictedLive = room.isRestricted && room.isLiveNow;
        // - isRecord: a replay (status 3). 3.x set liveStatus replay but left
        //   its separate isRecord flag false; the model derives the flag from
        //   the one state (M2), so it now says true.
        // - avatar: 18-6, the 1024 px `avatar` (3.x: the 50 px
        //   `profileImageUrl`).
        // - notice: the unified rule on explanations (reworded).
        // - liveStatus, status: 18-4, a restricted broadcast on air is live
        //   (3.x: unknown, false).
        final changed = {
          if (room.isRecord) 'isRecord',
          'avatar',
          'notice',
          if (restrictedLive) ...{'liveStatus', 'status'},
        };
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
        final was = _result(legacy['getRoomDetail'])! as Map<String, dynamic>;
        final user = ((jsonDecode(fixture.body) as Map)['data'] as Map)['user'] as Map;
        expect((was['avatar'], room.avatar), (user['profileImageUrl'], user['avatar']));
        expect(was['avatar'], contains('.50/'));
        expect(room.avatar, contains('.1024/'));
        expect(was['notice'], [if (restrictedLive) _legacyRestricted, _legacyScope].join('\n'));
        expect(room.notice, [if (restrictedLive) WeiboApi.restrictedNotice, WeiboApi.roomScopeNotice].join('\n'));
        if (restrictedLive) {
          expect((was['liveStatus'], was['status']), (LiveStatus.unknown.index, false));
          expect((room.liveStatus, room.toJson()['status']), (LiveStatus.live, true));
        }
      });
    }

    for (final (name, id, started) in [('S02-live', _live, 1790527792000), ('S03-live', _s03Live, 1790595363000)]) {
      test('$name: public and live; the HLS field repeats the FLV, kept once (3.x); start and no restriction', () {
        final room = WeiboApi.detail(_sample(name).body, liveId: id);
        expect(room.isLiveNow, isTrue);
        final data = _data(room);
        expect((data.status, data.watchLimit, data.access), (1, 0, WeiboAccess.public));
        expect((data.replayUrl, data.tip), (null, null));
        expect(data.mediaUrls.single, endsWith('_wb720avc.flv'));
        expect(WeiboApi.unplayable(data), isNull);
        expect(WeiboApi.qualityOf(data), WeiboApi.original);
        expect(room.restriction, LiveRestriction.none);
        expect(room.startedAt, DateTime.fromMillisecondsSinceEpoch(started, isUtc: true));
        expect(room.toJson()['startedAt'], room.startedAt!.toIso8601String());
        expect(room.introduction, isNull);
      });
    }

    test('S02-watch-limit (18-4): friends only is live and private; the restriction line; nothing plays', () {
      final legacy = _legacy('S02-watch-limit');
      final room = WeiboApi.detail(_sample('S02-watch-limit').body, liveId: _watchLimit);
      expect((room.liveStatus, room.restriction), (LiveStatus.live, LiveRestriction.private));
      expect(room.followGroup, FollowGroup.live);
      expect(room.startedAt, DateTime.fromMillisecondsSinceEpoch(1790523264000, isUtc: true));
      expect(room.notice, '${WeiboApi.restrictedNotice}\n${WeiboApi.roomScopeNotice}');
      final data = _data(room);
      expect((data.status, data.watchLimit, data.access), (1, 10, WeiboAccess.restricted));
      expect(data.tip, '本场直播只有主播的好友可观看');
      expect(data.mediaUrls, isEmpty);
      expect(WeiboApi.qualityOf(data), isNull);
      // changed: 3.x's access failure (NeedsLogin in M4.18) is now
      // StreamUnavailable with the kind and the platform's text (M2.1's
      // table; the app has no Weibo account to log in with).
      expect(_result(legacy['getLiveStatus']), {'throws': 'WeiboException', 'message': 'Weibo access'});
      expect(legacy['getPlayQualites'], {'throws': 'WeiboException', 'message': 'Weibo access'});
      expect(
        WeiboApi.unplayable(data),
        isA<StreamUnavailable>().having((error) => error.detail, 'detail', allOf(contains('private'), contains('好友'))),
      );
    });

    test('S02-ended-replay (18-5): status 3 stays a replay (3.x) and plays its recording over https', () {
      final legacy = _legacy('S02-ended-replay');
      final room = WeiboApi.detail(_sample('S02-ended-replay').body, liveId: _endedReplay);
      expect((room.liveStatus, room.restriction), (LiveStatus.replay, LiveRestriction.none));
      expect(room.followGroup, FollowGroup.replay);
      expect(room.startedAt, isNull, reason: 'only while live');
      final data = _data(room);
      expect(data.mediaUrls, isEmpty);
      expect(data.replayUrl, 'https://live.video.weibocdn.com/5269875505238409_wb1080avc_index.m3u8');
      expect(
        ((jsonDecode(_sample('S02-ended-replay').body) as Map)['data'] as Map)['replay_origin_url'],
        'http://live.video.weibocdn.com/5269875505238409_wb1080avc_index.m3u8',
      );
      expect(WeiboApi.unplayable(data), isNull);
      expect(WeiboApi.qualityOf(data), WeiboApi.replay);
      // changed: 3.x returned no qualities (the player got no reason) and
      // refused the URLs; the replay now plays (18-5).
      expect(legacy['getPlayQualites'], isEmpty);
      expect(_result(legacy['getPlayUrls']), {'throws': 'WeiboException', 'message': 'Weibo notLive'});
      expect(_result(legacy['getLiveStatus']), isFalse);
    });

    test('S04-self-only-replay (new): an ended broadcast only the anchor may watch is a private replay', () {
      final room = WeiboApi.detail(_sample('S04-self-only-replay').body, liveId: _watchLimit);
      expect((room.liveStatus, room.restriction), (LiveStatus.replay, LiveRestriction.private));
      expect(room.followGroup, FollowGroup.replay, reason: 'a restriction keeps the group; the card marks it');
      final data = _data(room);
      expect((data.status, data.watchLimit, data.access, data.replayUrl), (3, 11, WeiboAccess.restricted, null));
      expect(data.tip, '本场直播只有主播自己可观看');
      expect(
        WeiboApi.unplayable(data),
        isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('主播自己')),
      );
      expect(room.notice, '${WeiboApi.restrictedNotice}\n${WeiboApi.roomScopeNotice}');
      expect(room.startedAt, isNull);
    });

    test('S02-watch-limit and S04-self-only-replay are one broadcast, recorded live and ended', () {
      final live = WeiboApi.detail(_sample('S02-watch-limit').body, liveId: _watchLimit);
      final ended = WeiboApi.detail(_sample('S04-self-only-replay').body, liveId: _watchLimit);
      expect((live.userId, live.nick), (ended.userId, ended.nick));
      final merged = live.mergeFrom(ended);
      expect((merged.liveStatus, merged.restriction), (LiveStatus.replay, LiveRestriction.private));
      expect(merged.startedAt, isNull, reason: 'the state changed and the answer has no start (M2.1)');
    });

    test('S04-shortlink-room (new): a broadcast ended the day before (status 5) is offline too (18-3)', () {
      final room = WeiboApi.detail(_sample('S04-shortlink-room').body, liveId: _shortLinkRoom);
      expect((room.liveStatus, room.restriction, room.startedAt), (LiveStatus.offline, null, null));
      expect((room.nick, room.title, room.userId), ('候鸟书', '候鸟书的微博直播', '5943017518'));
      expect(room.avatar, contains('.1024/'));
      expect(WeiboApi.unplayable(_data(room)), isA<StreamUnavailable>());
      expect(room.notice, WeiboApi.roomScopeNotice);
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

    test('S02-ended: an older id 3.x refused before asking now opens: status 5 is offline (18-3)', () {
      final legacy = _legacy('S02-ended');
      // changed: 3.x refused the id shape (`identity`, no request) and its
      // search fell back to the nickname filter; the id pattern is wider.
      expect(_result(legacy['getRoomDetail']), {'throws': 'WeiboException', 'message': 'Weibo identity'});
      expect((legacy['getRoomDetail'] as Map<String, dynamic>)['requests'], isEmpty);
      expect((legacy['WeiboLink.parse'] as Map<String, dynamic>).values, everyElement(isNull));
      final room = WeiboApi.detail(_sample('S02-ended').body, liveId: _ended);
      // changed: 3.x mapped any status but 1 and 3 to unknown.
      expect((room.liveStatus, room.followGroup), (LiveStatus.offline, FollowGroup.offline));
      expect(room.isExplicitlyOfflineNow, isTrue);
      expect((room.restriction, room.startedAt), (null, null), reason: 'offline: neither');
      expect((room.title, room.nick, room.userId), ('泸县地震救援现场', '央视新闻', '2656274875'));
      final data = _data(room);
      expect((data.status, data.access, data.replayUrl), (5, WeiboAccess.public, null));
      expect(data.mediaUrls, isEmpty);
      expect(WeiboApi.unplayable(data), isA<StreamUnavailable>());
      expect(WeiboApi.qualityOf(data), isNull);
    });

    test("3.x's captured live answer: the FLV behind the HLS field once; the owner apart", () {
      final room = _detail(_liveDetail());
      expect(room.isLiveNow, isTrue);
      expect(_data(room).mediaUrls, [_media]);
      expect((room.userId, room.roomId, room.nick), ('101', _id, '样本 0'));
      expect(() => _data(room).mediaUrls.clear(), throwsUnsupportedError);
    });

    test('18-6: the 1024 px avatar first, the small profile picture when it is missing or no image', () {
      expect(_detail(_liveDetail()).avatar, 'https://img.example.test/avatar-large.jpg');
      for (final large in <Object?>[null, '', 'not an image', 7]) {
        final json = _liveDetail();
        (_row(json)['user'] as Map)['avatar'] = large;
        expect(_detail(json).avatar, 'https://img.example.test/avatar.jpg', reason: '$large');
      }
      final json = _liveDetail();
      (_row(json)['user'] as Map)
        ..remove('avatar')
        ..remove('profileImageUrl');
      expect(_detail(json).avatar, isEmpty);
    });

    test('18-7: title and nickname decode HTML character references', () {
      final json = _liveDetail();
      _row(json)['title'] = '唱歌&amp;聊天 &quot;晚安&quot;&#x1F319;';
      (_row(json)['user'] as Map)['screenName'] = 'A&lt;B&gt;&nbsp;C';
      final room = _detail(json);
      expect((room.title, room.nick), ('唱歌&聊天 "晚安"🌙', 'A<B> C'));
    });

    test('the start: epoch milliseconds while live; 0, a string or an absurd value is none', () {
      expect(_detail(_liveDetail()).startedAt, DateTime.fromMillisecondsSinceEpoch(1789038303000, isUtc: true));
      for (final value in <Object?>[0, null, '1789038303000', 1789038303, 1.5e12, 99999999999999]) {
        final json = _liveDetail();
        _row(json)['startTime'] = value;
        expect(_detail(json).startedAt, isNull, reason: '$value');
      }
      final replay = _liveDetail();
      _row(replay)['status'] = 3;
      expect(_detail(replay).startedAt, isNull, reason: 'a replay: the start of an ended broadcast');
    });

    test("3.x's missing-user answer (error_code 20003) is ApiChanged, not offline", () {
      const body = '{"code":999999,"msg":"User does not exists!","error_code":20003,"data":[]}';
      expect(() => WeiboApi.detail(body, liveId: _id), throwsA(isA<ApiChanged>()));
    });

    for (final (mode, state, restriction, line) in <(String, LiveStatus, LiveRestriction?, String?)>[
      ('replay', LiveStatus.replay, LiveRestriction.none, null),
      ('replay-restricted', LiveStatus.replay, LiveRestriction.private, WeiboApi.restrictedNotice),
      ('replay-disabled', LiveStatus.replay, LiveRestriction.unplayable, WeiboApi.disabledNotice),
      ('unknown', LiveStatus.unknown, null, null),
      ('announced', LiveStatus.unknown, null, null),
      ('disabled', LiveStatus.live, LiveRestriction.unplayable, WeiboApi.disabledNotice),
      ('restricted', LiveStatus.live, LiveRestriction.unplayable, WeiboApi.restrictedNotice),
      ('trial', LiveStatus.live, LiveRestriction.unplayable, WeiboApi.restrictedNotice),
      ('paid-restricted', LiveStatus.live, LiveRestriction.unplayable, WeiboApi.restrictedNotice),
      ('app-only', LiveStatus.live, LiveRestriction.appOnly, WeiboApi.restrictedNotice),
      ('friends-only', LiveStatus.live, LiveRestriction.private, WeiboApi.restrictedNotice),
      ('self-only', LiveStatus.live, LiveRestriction.private, WeiboApi.restrictedNotice),
      ('paid', LiveStatus.live, LiveRestriction.paid, WeiboApi.restrictedNotice),
    ]) {
      test('$mode exports no live URL (3.x); its state and restriction (18-4, 18-5)', () {
        final json = _liveDetail();
        final row = _row(json);
        switch (mode) {
          case 'replay':
            row['status'] = 3;
            row['replay_origin_url'] = 'https://media.example.test/replay.m3u8';
          case 'replay-restricted':
            row['status'] = 3;
            row['watch_limit'] = 10;
            row['replay_origin_url'] = 'https://media.example.test/replay.m3u8';
          case 'replay-disabled':
            row['status'] = 3;
            row['play_switch'] = 0;
            row['replay_origin_url'] = 'https://media.example.test/replay.m3u8';
          case 'unknown':
            row['status'] = 99;
          case 'announced':
            row['status'] = 0;
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
          case 'friends-only':
            row['watch_limit'] = 10;
          case 'self-only':
            row['watch_limit'] = 11;
          case 'paid':
            row['watch_limit'] = 12;
        }
        final room = _detail(json);
        final data = _data(room);
        expect(data.mediaUrls, isEmpty);
        expect(data.replayUrl, mode == 'replay' ? 'https://media.example.test/replay.m3u8' : isNull);
        expect((room.liveStatus, room.restriction), (state, restriction));
        expect(WeiboApi.unplayable(data), mode == 'replay' ? isNull : isA<StreamUnavailable>());
        expect(room.startedAt, state == LiveStatus.live ? isNotNull : isNull);
        expect(room.notice, [?line, WeiboApi.roomScopeNotice].join('\n'));
      });
    }

    test('the kinds of watch_limit; the reason names the kind, the value and the platform text', () {
      expect(
        [
          for (final limit in [1, 8, 9, 10, 11, 12, 13]) WeiboApi.restrictionOfLimit(limit),
        ],
        [
          LiveRestriction.unplayable,
          LiveRestriction.appOnly,
          LiveRestriction.unplayable,
          LiveRestriction.private,
          LiveRestriction.private,
          LiveRestriction.paid,
          LiveRestriction.unplayable,
        ],
      );
      const data = WeiboRoomData(ownerId: 1, status: 1, watchLimit: 12, access: WeiboAccess.restricted, tip: '付费');
      expect(WeiboApi.unplayable(data)!.detail, 'restricted broadcast (paid, watch_limit 12): 付费');
      const bare = WeiboRoomData(ownerId: 1, status: 1, watchLimit: 9, access: WeiboAccess.restricted);
      expect(WeiboApi.unplayable(bare)!.detail, 'restricted broadcast (unplayable, watch_limit 9)');
      final json = _liveDetail();
      _row(json)
        ..['watch_limit'] = 10
        ..['pay_dialog_info'] = 'text';
      expect(_data(_detail(json)).tip, isNull, reason: 'no dialog object');
      final public = _liveDetail();
      _row(public)['pay_dialog_info'] = {'buy_tip': 'ignored'};
      expect(_data(_detail(public)).tip, isNull, reason: 'only a restriction reads it');
    });

    test('a public replay without a usable recording is an unplayable replay, grouped offline (18-5)', () {
      for (final url in <Object?>['', null, 'file:///replay.m3u8', 'https://user@media.example.test/a.m3u8', 3]) {
        final json = _liveDetail();
        _row(json)
          ..['status'] = 3
          ..['replay_origin_url'] = url;
        final room = _detail(json);
        expect((room.liveStatus, room.restriction), (LiveStatus.replay, LiveRestriction.unplayable), reason: '$url');
        expect(room.followGroup, FollowGroup.offline);
        expect(_data(room).replayUrl, isNull);
        expect(WeiboApi.unplayable(_data(room)), isA<StreamUnavailable>());
      }
      final json = _liveDetail();
      _row(json)
        ..['status'] = 3
        ..remove('replay_origin_url');
      expect(_detail(json).restriction, LiveRestriction.unplayable);
    });

    for (final bad in [
      'wrong-id',
      'wrong-owner',
      'missing-status',
      'string-status',
      'missing-limit',
      'missing-switch',
      'switch-two',
      'missing-user',
      'bad-envelope',
      'missing-error',
      'wrong-success',
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
          case 'missing-switch':
            row.remove('play_switch');
          case 'switch-two':
            row['play_switch'] = 2;
          case 'missing-user':
            row.remove('user');
          case 'bad-envelope':
            json['data'] = <Object?>[];
          case 'missing-error':
            json.remove('error_code');
          case 'wrong-success':
            json['code'] = 0;
        }
        expect(() => _detail(json), throwsA(isA<ApiChanged>()));
      });
    }

    // 18-8: 3.x rejected each of these answers as a whole.
    for (final (relaxed, mediaUrls, title) in <(String, List<String>, String)>[
      ('invalid-pay', [_media], '公开直播样本'),
      ('missing-pay', [_media], '公开直播样本'),
      ('bad-width', [_media], '公开直播样本'),
      ('missing-height', [_media], '公开直播样本'),
      ('bad-title', [_media], ''),
      ('bad-nickname', [_media], '公开直播样本'),
      ('missing-hls', [_media], '公开直播样本'),
      ('url-userinfo', [], '公开直播样本'),
      ('url-newline', [], '公开直播样本'),
      ('url-scheme', [], '公开直播样本'),
      ('url-number', [], '公开直播样本'),
      ('flv-bad-hls-good', ['https://media.example.test/live/playlist.m3u8'], '公开直播样本'),
    ]) {
      test('18-8: $relaxed no longer fails the room; only an unusable address is dropped', () {
        final json = _liveDetail();
        final row = _row(json);
        switch (relaxed) {
          case 'invalid-pay':
            row['pay_live_status'] = 2;
          case 'missing-pay':
            row.remove('pay_live_status');
          case 'bad-width':
            row['width'] = -1;
          case 'missing-height':
            row.remove('height');
          case 'bad-title':
            row['title'] = null;
          case 'bad-nickname':
            (row['user'] as Map)['screenName'] = 7;
          case 'missing-hls':
            row.remove('live_origin_hls_url');
          case 'url-userinfo':
            row['live_origin_flv_url'] = row['live_origin_hls_url'] = 'https://user:secret@media.example.test/a.flv';
          case 'url-newline':
            row['live_origin_flv_url'] = row['live_origin_hls_url'] = 'https://media.example.test/\na.flv';
          case 'url-scheme':
            row['live_origin_flv_url'] = row['live_origin_hls_url'] = 'file:///private/a.flv';
          case 'url-number':
            row['live_origin_flv_url'] = row['live_origin_hls_url'] = 7;
          case 'flv-bad-hls-good':
            row['live_origin_flv_url'] = 'file:///private/a.flv';
            row['live_origin_hls_url'] = 'https://media.example.test/live/playlist.m3u8';
        }
        final room = _detail(json);
        expect(room.isLiveNow, isTrue);
        expect(_data(room).mediaUrls, mediaUrls);
        expect(room.title, title);
        expect(room.nick, relaxed == 'bad-nickname' ? isEmpty : '样本 0');
        expect(room.restriction, mediaUrls.isEmpty ? LiveRestriction.unplayable : LiveRestriction.none);
        expect(WeiboApi.unplayable(_data(room)), mediaUrls.isEmpty ? isA<StreamUnavailable>() : isNull);
      });
    }

    test('without an expected owner any anchor is taken; the broadcast must still be the one asked for', () {
      final json = _liveDetail();
      (_row(json)['user'] as Map)['uid'] = 999;
      expect(_detail(json, ownerId: null).userId, '999');
      expect(() => WeiboApi.detail(jsonEncode(_liveDetail()), liveId: _live), throwsA(isA<ApiChanged>()));
    });

    test('an empty live answer is live but has nothing to play (3.x): unplayable', () {
      final json = _liveDetail();
      _row(json)
        ..['live_origin_hls_url'] = ''
        ..['live_origin_flv_url'] = '';
      final room = _detail(json);
      expect(room.isLiveNow, isTrue);
      expect((room.restriction, room.followGroup), (LiveRestriction.unplayable, FollowGroup.live));
      expect(_data(room).mediaUrls, isEmpty);
      expect(WeiboApi.unplayable(_data(room)), isA<StreamUnavailable>());
    });

    test('the explanations are reworded for users (unified rule); 3.x said them in developer terms', () {
      expect(WeiboApi.roomScopeNotice, isNot(_legacyScope));
      expect(WeiboApi.restrictedNotice, isNot(_legacyRestricted));
      for (final text in [
        WeiboApi.roomScopeNotice,
        WeiboApi.restrictedNotice,
        WeiboApi.disabledNotice,
        WeiboApi.directoryScope,
      ]) {
        for (final jargon in ['直播源', '快照', '元数据', '待核验', '场次号']) {
          expect(text, isNot(contains(jargon)), reason: text);
        }
      }
      // 3.x's directory note said the cards had no state; they are live now
      // (18-2), and t.cn links are found (18-9).
      expect(WeiboApi.directoryScope, allOf(contains('正在直播'), contains('t.cn')));
    });

    test('checkStatus: 200 passes; the other statuses are typed', () {
      WeiboApi.checkStatus(200, 'x');
      for (final (status, matcher) in [
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (500, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
      ]) {
        expect(() => WeiboApi.checkStatus(status, 't.cn'), throwsA(matcher), reason: '$status');
      }
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

    test('S02-ended-replay (18-5): the recording is one HLS line, https, without headers or lease', () {
      final room = WeiboApi.detail(_sample('S02-ended-replay').body, liveId: _endedReplay);
      final resolution = WeiboApi.replayResolution(_data(room).replayUrl!);
      expect(resolution.appliedQualityData, 'replay');
      final line = resolution.lines.single;
      expect(line.url, 'https://live.video.weibocdn.com/5269875505238409_wb1080avc_index.m3u8');
      expect((line.format, line.codec, line.lineId), (StreamFormat.hls, 'avc', 'live.video.weibocdn.com'));
      expect(line.headers, isEmpty);
      expect(line.lease, isNull);
      expect((WeiboApi.replay.quality, WeiboApi.replay.id), ('原画', 'replay'));
      expect((WeiboApi.original.quality, WeiboApi.original.id), ('原始流', 'original'), reason: 'no rename row');
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

    test('18-9: t.cn short links are requested over https, without query or fragment', () {
      for (final (input, request) in [
        ('http://t.cn/AXWbinBd', 'https://t.cn/AXWbinBd'),
        ('https://t.cn/AXWbinBd', 'https://t.cn/AXWbinBd'),
        ('  https://T.CN/AXWbinBd/  ', 'https://t.cn/AXWbinBd'),
        ('https://t.cn:443/A6abcd?from=share#x', 'https://t.cn/A6abcd'),
        ('http://t.cn:80/zYx8', 'https://t.cn/zYx8'),
      ]) {
        expect(WeiboApi.shortLink(input), Uri.parse(request), reason: input);
        expect(WeiboApi.exactRoom(input), isNull, reason: 'a request is needed');
      }
      for (final input in [
        't.cn/AXWbinBd',
        'ftp://t.cn/AXWbinBd',
        'https://t.cn/',
        'https://t.cn/abc',
        'https://t.cn/${'a' * 17}',
        'https://t.cn/AXWb-nBd',
        'https://t.cn/AXWbinBd/extra',
        'https://user@t.cn/AXWbinBd',
        'https://t.cn:8443/AXWbinBd',
        'https://t.cn.evil.test/AXWbinBd',
        'https://sub.t.cn/AXWbinBd',
        'https://t.cn/AXW binBd',
        'https://weibo.com/l/wblive/p/show/$_id',
      ]) {
        expect(WeiboApi.shortLink(input), isNull, reason: input);
      }
    });
  });
}
