// FC2 Live parsing against the recorded samples, compared field by field
// with 3.x's frozen output (expected.json, written by
// fixtures/fc2live/legacy_expected.dart from 3.x's Fc2Api, Fc2Link, Fc2Site
// and Fc2ControlSession). Every intended difference is listed with its
// reason (`changed:`, with the 差异 of the M4.26 record or the upgrade row of
// docs/specs/UPGRADES.md); everything else must match. The M2.1 keys 3.x never
// wrote are checked apart (`added:`). The synthetic cases port the payloads
// of 3.x's fc2live_site_test.dart and pin 3.x's checks, as far as the
// upgrades kept them.
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('fc2live', name);

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

/// The `result` of a traced legacy call.
Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

/// 3.x wrote its media headers into every room; that field is IPTV's, and
/// the headers now travel with the control session (差异 7).
const _headers = {'httpHeaders'};

/// Keys 3.x never wrote (M2.1); [_expectParity] checks them apart.
const _v4Keys = ['startedAt', 'restriction'];

/// Asserts that [actual] (a `toJson`) equals 3.x's [legacy] map on every key
/// 3.x wrote, except [changed] (intended differences) and the projection's
/// `data` (checked apart: 3.x kept its `Fc2Room` only in live entry
/// details), and that the v4 keys are exactly [added]. 3.x wrote null where
/// the immutable model writes ''.
void _expectParity(
  Map<String, Object?> actual,
  Map<String, dynamic> legacy, {
  Set<String> changed = _headers,
  Map<String, Object?> added = const {},
  String? reason,
}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (changed.contains(key) || key == 'data') continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
  for (final key in _v4Keys) {
    expect(actual[key], added[key], reason: '${reason ?? ''} $key (v4 key)');
  }
}

/// 3.x's room projection: toJson plus `link`.
Map<String, Object?> _projection(LiveRoom room) => {...room.toJson(), 'link': room.link};

/// Unix milliseconds as `toJson` writes a start time.
String _iso(int milliseconds) => DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true).toIso8601String();

/// The S01 rows by channel id, as answered.
final Map<String, Map<String, dynamic>> _rows = {
  for (final row
      in ((jsonDecode(_sample('S01-directory').body) as Map<String, dynamic>)['channel'] as List)
          .cast<Map<String, dynamic>>())
    '${row['id']}': row,
};

/// The restriction the S01 row of [roomId] shows (26-9): `login` 1 or 2 is
/// needsLogin (the five restricted rows of S01), else none.
String _rowRestriction(String roomId) => switch (_rows[roomId]!) {
  {'pay': 0, 'tid': 0, 'login': 0} => 'none',
  {'pay': 0, 'tid': 0, 'login': 1 || 2} => 'needsLogin',
  final row => fail('S01 has no row like $row'),
};

/// 3.x gave every room that is neither restricted nor adult its chat
/// notice ([Fc2LiveApi.legacyChatNotice]: comments not connected yet, and a
/// note for developers); comments are connected since M5.22 and those rooms
/// have no notice. [_expectNoChatNotice] checks both sides.
const _notice = {'notice'};

/// [room] has no notice where 3.x's [legacy] room had the chat notice
/// (M5.22).
void _expectNoChatNotice(LiveRoom room, Map<String, dynamic> legacy, {String? reason}) {
  expect(legacy['notice'], Fc2LiveApi.legacyChatNotice, reason: reason);
  expect(room.notice, isNull, reason: reason);
}

/// What changed from 3.x on the card of [legacy] (3.x's room map), by row:
/// - `area`: every card is named in the catalog's Chinese (26-6);
/// - `liveStatus`, `status`: a restricted room is live (26-9); the other
///   rooms had the chat notice and now have none ([_notice], M5.22);
/// - `title`, `nick`: HTML entities decoded (26-4); a missing name stays
///   empty instead of the channel number (placeholder rule, M2.1 X-2).
Set<String> _cardChanged(Map<String, dynamic> legacy) {
  final row = _rows[legacy['roomId']]!;
  return {
    ..._headers,
    'area',
    if (legacy['liveStatus'] == LiveStatus.unknown.index) ...{'liveStatus', 'status'} else ..._notice,
    if ('${row['title']}'.contains('&')) 'title',
    if ('${row['name']}'.contains('&') || '${row['name']}'.isEmpty) 'nick',
  };
}

/// The v4 keys of the S01 card of [roomId]: the row's `start_time` and its
/// restriction (the unified rules).
Map<String, Object?> _cardAdded(String roomId) => {
  'startedAt': _iso(_rows[roomId]!['start_time'] as int),
  'restriction': _rowRestriction(roomId),
};

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {String reason = ''}) {
  final expected = _maps(legacy);
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(
      _projection(room),
      expected[index],
      changed: _cardChanged(expected[index]),
      added: _cardAdded(room.roomId),
      reason: '$reason[$index]',
    );
    if (_cardChanged(expected[index]).contains('notice')) {
      _expectNoChatNotice(room, expected[index], reason: '$reason[$index]');
    }
  }
}

/// 3.x's error of a traced call.
void _expectLegacyError(Object? traced, String kind, {String? reason}) =>
    expect(_result(traced), {'throws': 'Fc2Exception', 'message': 'FC2 Live $kind'}, reason: reason);

List<Fc2LiveChannel> _snapshot() => Fc2LiveApi.directory(_sample('S01-directory').body);

Fc2LiveMember _member(String sample, String channelId) => Fc2LiveApi.member(_sample(sample).body, channelId: channelId);

LiveArea _area(String id) => Fc2LiveApi.category().children.singleWhere((area) => area.areaId == id);

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

// 3.x's test payloads (test/fc2live_site_test.dart) --------------------------

Map<String, Object?> _directoryRow(
  String id, {
  Object? type = 1,
  Object? category = 1,
  Object? name = 'Fixture owner',
  Object? title = 'Fixture game stream',
  Object? image = 'https://live-storage.fc2.com/thumb/10608314/thumb.jpg?fixture=1',
  Object? pay = 0,
  Object? login = 0,
  Object? tid = 0,
  Object? count = 61,
  Object? total = 1727,
  Object? startTime = 1789885361806,
}) => {
  'id': id,
  'type': type,
  'category': category,
  'name': name,
  'title': title,
  'image': image,
  'start_time': startTime,
  'pay': pay,
  'login': login,
  'tid': tid,
  'count': count,
  'total': total,
};

Map<String, Object?> _directoryPayload() => {
  'time': 1789980977,
  'channel': [
    _directoryRow('10608314'),
    _directoryRow(
      '11916060',
      category: 9,
      name: 'Kitten radio',
      title: '24/7 Kitten audio',
      image: 'https://live-storage.fc2.com/thumb/11916060/thumb.png',
      count: 3,
      total: 1279,
    ),
    _directoryRow('12000001', category: 5, name: 'Ticket room', title: 'Ticket room', image: '', tid: 7),
    _directoryRow('1', type: 0, title: '', image: ''),
  ],
};

Map<String, Object?> _channelData({Map<String, Object?> set = const {}, Set<String> remove = const {}}) {
  final data = <String, Object?>{
    'channelid': '10608314',
    'adult': 0,
    'title': 'Fixture game stream',
    'info': 'Fixture description',
    'image': 'https://live-storage.fc2.com/thumb/10608314/thumb.jpg',
    'login_only': 0,
    'fee': 0,
    'ticketid': 0,
    'ticket_only': 0,
    'is_limited': 0,
    'category': 1,
    'category_name': 'Idle Chat',
    'count': 61,
    'total': 1727,
    'is_publish': 1,
    'start': 1789885361806,
    'version': 'fixture-version',
    'tname': '',
    ...set,
  };
  remove.forEach(data.remove);
  return data;
}

String _memberPayload({
  Map<String, Object?> set = const {},
  Set<String> remove = const {},
  Object? profile = const {'userid': 10608314, 'name': 'Fixture owner'},
  Object? status = 1,
}) => jsonEncode({
  'status': status,
  'data': {'channel_data': _channelData(set: set, remove: remove), 'profile_data': profile},
});

Map<String, Object?> _controlPayload({Map<String, Object?> set = const {}}) => {
  'url': 'wss://us-west-1-media-worker1077.live.fc2.com/control/channels/10608314',
  'orz_raw': 'fixture_orz-token',
  'control_token': 'fixture-control-token',
  'status': 0,
  ...set,
};

const _master =
    'https://us-west-1-media.live.fc2.com/a/stream/10608314/0/master_playlist?targets=10,20,30,90&c=cc&d=dd';

/// The variant of [mode] of the synthetic answer.
String _variant(int mode) => 'https://us-west-1-media.live.fc2.com/a/stream/10608314/$mode/playlist?c=cc&d=dd';

Map<String, dynamic> _hlsAnswer({Object? status = 0, Object? playlists, Map<String, Object?> more = const {}}) => {
  'name': '_response_',
  'id': 1,
  'arguments': {
    'status': status,
    'playlists':
        playlists ??
        [
          {'mode': 0, 'status': 0, 'url': _master},
          {'mode': 10, 'status': 0, 'url': _variant(10)},
        ],
    ...more,
  },
};

/// The recorded HLS answer of [sample]: S04 (62996200, tiers 10–30) or S07
/// (10200498, a 1080p broadcast with tiers 10–50).
Map<String, dynamic> _recordedAnswer([String sample = 'control/S04-control']) =>
    _sample(sample).frames
        .map((frame) => jsonDecode(frame) as Map<String, dynamic>)
        .firstWhere((message) => message['name'] == '_response_');

void main() {
  group('S01 directory', () {
    test('the catalog: one category FC2 Live with 3.x six areas (Chinese names)', () {
      final category = Fc2LiveApi.category();
      final legacy = _maps(_result(_legacy('S01-directory')['getCategores'])).single;
      expect((category.id, category.name), (legacy['id'], legacy['name']));
      final areas = _maps(legacy['children']);
      expect(category.children, hasLength(areas.length));
      for (final (index, area) in category.children.indexed) {
        // areaPic and shortName: 3.x wrote null, the model writes ''.
        _expectParity(area.toJson(), areas[index], changed: const {}, reason: 'area $index');
      }
      expect(category.children.map((area) => area.areaId), ['all', '1', '2', '4', '9', '5']);
    });

    test('every native directory page matches 3.x: 20 a page, restricted rooms kept, other rows skipped', () {
      final channels = _snapshot();
      final pages = _legacy('S01-directory')['getDirectoryPage'] as Map<String, dynamic>;
      var compared = 0;
      for (final MapEntry(:key, :value) in pages.entries) {
        final want = _result(value);
        if (want is! Map<String, dynamic> || !want.containsKey('rooms')) continue;
        final [area, number] = key.split(':');
        final filter = area == 'recommend' ? null : Fc2LiveApi.areaFilter(_area(area));
        final page = Fc2LiveApi.directoryPage([
          for (final channel in channels)
            if (Fc2LiveApi.inArea(channel, filter)) channel,
        ], page: int.parse(number));
        expect((page.page, page.hasMore), (want['page'], want['hasMore']), reason: key);
        _expectRooms(page.rooms, want['rooms'], reason: key);
        compared++;
      }
      expect(compared, 4 + 6 * 2, reason: 'four pages of every channel and two pages of each of the six areas');
      expect(channels, hasLength(61), reason: '63 rows, two of them two-shot rooms (type 2)');
      expect(channels.where((channel) => channel.state == Fc2LiveState.restricted), hasLength(5));
      // A page below 1 (3.x: schema) and an unknown area (3.x: identity) are
      // caller errors now; the site tests them without a request.
      _expectLegacyError(pages['recommend:0'], 'schema');
      _expectLegacyError(pages['3:1'], 'identity');
      _expectLegacyError(pages['otherPlatform:1'], 'identity');
    });

    test("3.x's slices of every channel and of an area", () {
      final channels = _snapshot();
      final legacy = _legacy('S01-directory');
      for (final MapEntry(:key, :value) in (legacy['getRecommendRooms'] as Map<String, dynamic>).entries) {
        final [_, page, _, size] = key.split(' ');
        final rooms = [
          for (final channel in Fc2LiveApi.slice(channels, page: int.parse(page), pageSize: int.parse(size)))
            Fc2LiveApi.room(channel),
        ];
        _expectRooms(rooms, _result(value), reason: key);
      }
      for (final MapEntry(:key, :value) in (legacy['getCategoryRooms'] as Map<String, dynamic>).entries) {
        final [id, _, page, _, size] = key.split(' ');
        if (id == '3') {
          _expectLegacyError(value, 'identity', reason: key);
          expect(() => Fc2LiveApi.areaFilter(_area('2').copyWithId('3')), throwsArgumentError);
          continue;
        }
        final filter = Fc2LiveApi.areaFilter(_area(id));
        final rooms = [
          for (final channel in Fc2LiveApi.slice(
            [
              for (final channel in channels)
                if (Fc2LiveApi.inArea(channel, filter)) channel,
            ],
            page: int.parse(page),
            pageSize: int.parse(size),
          ))
            Fc2LiveApi.room(channel),
        ];
        _expectRooms(rooms, _result(value), reason: key);
      }
      expect(Fc2LiveApi.validSlice(page: 1, pageSize: 100), isTrue);
      for (final (page, size) in [(0, 30), (1, 0), (1, 101)]) {
        expect(Fc2LiveApi.validSlice(page: page, pageSize: size), isFalse);
        expect(Fc2LiveApi.slice([1, 2, 3], page: page, pageSize: size), isEmpty);
      }
    });

    test("the keyword search over the snapshot matches 3.x: number, name, title and 3.x's area name", () {
      final channels = _snapshot();
      final search = _legacy('S01-directory')['searchRooms (pageSize 20)'] as Map<String, dynamic>;
      var compared = 0;
      for (final MapEntry(:key, :value) in search.entries) {
        final match = RegExp(r'^(.+) page (\d+)(?: size (\d+))?$').firstMatch(key);
        if (match == null || key.startsWith('exact ')) continue;
        final keyword = match.group(1)!;
        final page = int.parse(match.group(2)!);
        final size = int.parse(match.group(3) ?? '20');
        final rooms = [
          for (final channel in Fc2LiveApi.slice(Fc2LiveApi.search(channels, keyword), page: page, pageSize: size))
            Fc2LiveApi.room(channel),
        ];
        _expectRooms(rooms, _result(value), reason: key);
        compared++;
      }
      expect(compared, 6 + 3);
      expect(Fc2LiveApi.search(channels, '0200').single.channelId, '10200498', reason: 'a number with a leading 0');
      final chat = channels.where((channel) => channel.categoryId == 1).length;
      expect(Fc2LiveApi.search(channels, 'IDLE CHAT'), hasLength(chat), reason: "3.x's English names still match");
      expect(Fc2LiveApi.search(channels, '闲聊'), hasLength(chat), reason: 'the area name shown (26-6)');
      expect(
        Fc2LiveApi.search(channels, 'Events & Festivals').single.channelId,
        '3024638',
        reason: 'titles as shown (26-4)',
      );
      expect(Fc2LiveApi.search(channels, '&amp;'), isEmpty);
      expect(
        Fc2LiveApi.search(channels, 'FC2 Live').map((channel) => channel.categoryId),
        isNot(contains(0)),
        reason: "category 0 has no area name any more (3.x: 'FC2 Live')",
      );
      expect(Fc2LiveApi.search(channels, '  '), isEmpty);
    });

    test('cards: what changed from 3.x (26-4, 26-6, 26-9, placeholders) and the start time', () {
      final rooms = [for (final channel in _snapshot()) Fc2LiveApi.room(channel)];
      final first = rooms.first;
      expect(first.roomId, '10200498');
      expect(first.title, '猫の居る風景♪');
      expect(first.nick, 'ちゅうや');
      expect(first.area, '闲聊', reason: "the catalog's name (26-6; 3.x: 'Idle Chat')");
      expect(first.avatar, first.cover, reason: 'the directory has no owner picture: the cover (26-5)');
      expect(first.cover, 'https://live-storage.fc2.com/thumb/10200498/thumb.gif?1377734751');
      expect(first.link, 'https://live.fc2.com/10200498/');
      expect((first.onlineViewers, first.totalViewers, first.watching), ('3', '232', '3'));
      expect(first.audienceMetricType, AudienceMetricType.onlineViewers);
      expect(first.notice, isNull, reason: "3.x's chat notice is gone: comments are connected (M5.22)");
      expect(first.introduction, isNull);
      expect(first.httpHeaders, isEmpty);
      expect(first.startedAt, DateTime.utc(2026, 9, 27, 4, 51, 54, 285), reason: 'start_time (JST 13:51:54)');
      expect(first.restriction, LiveRestriction.none);
      expect(first.danmakuData, isNull, reason: 'cards carry no comment arguments');
      expect(
        first.data,
        isA<Fc2LiveRoomData>()
            .having((data) => data.state, 'state', Fc2LiveState.live)
            .having((data) => data.categoryId, 'categoryId', 1)
            .having((data) => data.restriction, 'restriction', LiveRestriction.none),
      );

      final restricted = rooms.where((room) => room.isRestricted).toList();
      expect(restricted.map((room) => room.roomId), ['3024638', '38085836', '41168365', '5185474', '57332960']);
      for (final room in restricted) {
        expect(room.liveStatus, LiveStatus.live, reason: '${room.roomId}: live and marked (26-9; 3.x: unknown)');
        expect(room.followGroup, FollowGroup.live);
        expect(
          room.restriction,
          LiveRestriction.needsLogin,
          reason: '${room.roomId}: login ${_rows[room.roomId]!['login']}',
        );
        expect(room.notice, Fc2LiveApi.noticeText['fc2live_access_restricted']);
        expect(room.watching, isNotEmpty);
        expect(room.startedAt, isNotNull);
      }
      final festival = rooms.singleWhere((room) => room.roomId == '3024638');
      expect(festival.title, contains('Events & Festivals'), reason: 'entities decoded (26-4)');

      final nameless = rooms.singleWhere((room) => room.roomId == '5185474');
      expect(nameless.nick, isEmpty, reason: 'no name stays empty (placeholder rule; 3.x: the channel number)');
      expect(nameless.hasNick, isFalse);
      final untitled = rooms.singleWhere((room) => room.roomId == '62996200');
      expect(untitled.title, untitled.nick, reason: 'no title: the name');
      for (final (category, name) in [
        (0, ''),
        (1, '闲聊'),
        (2, '游戏 / 作业'),
        (3, '游戏 / 作业'),
        (4, '视频'),
        (5, '其他'),
        (9, '音频'),
      ]) {
        final some = rooms.where((room) => (room.data! as Fc2LiveRoomData).categoryId == category);
        expect(some, isNotEmpty, reason: 'S01 has category $category');
        expect(some.map((room) => room.area), everyElement(name), reason: 'category $category');
      }
      expect(rooms.where((room) => room.cover.isEmpty), hasLength(5), reason: 'blank images stay blank');
      expect(rooms.map((room) => room.roomId), isNot(contains(startsWith('2_'))));
      expect(rooms.map((room) => room.startedAt), everyElement(isNotNull));
    });
  });

  group('S02 member', () {
    test('a live channel at every depth matches 3.x, with its start time and restriction none', () {
      final member = _member('S02-member-live', '62996200');
      final room = Fc2LiveApi.room(member.channel);
      final legacy = _legacy('S02-member-live');
      for (final call in [
        'getRoomDetail',
        'getRoomDetailForRefresh',
        'getRoomDetailForRecording',
        'getRoomDetail(link)',
      ]) {
        _expectParity(
          _projection(room),
          _result(legacy[call])! as Map<String, dynamic>,
          // area: the catalog's Chinese, not the site's その他 (26-6).
          changed: {..._headers, ..._notice, 'area'},
          added: {'startedAt': _iso(1790407066410), 'restriction': 'none'},
          reason: call,
        );
        _expectNoChatNotice(room, _result(legacy[call])! as Map<String, dynamic>, reason: call);
      }
      expect(room.area, '其他');
      expect(room.title, 'FC2USER475160OCC', reason: 'no title: the owner name');
      expect(room.avatar, room.cover, reason: 'no icon or image in the profile: the cover (26-5)');
      expect(room.introduction, isNull, reason: 'blank info');
      expect(member.version, 'AJQc7CD37hTVGbhUsPL6I');
      expect(room.data, isA<Fc2LiveRoomData>().having((data) => data.state, 'state', Fc2LiveState.live));
      expect(_result(legacy['getLiveStatus']), isTrue);
      expect(Fc2LiveApi.room(member.channel, danmaku: true).danmakuData, const Fc2LiveDanmakuArgs('62996200'));
    });

    test('a restricted channel is live and marked needsLogin (3.x: unknown), with the owner picture', () {
      final member = _member('S02-member-restricted', '3024638');
      final room = Fc2LiveApi.room(member.channel);
      final legacy = _legacy('S02-member-restricted');
      for (final call in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        _expectParity(
          _projection(room),
          _result(legacy[call])! as Map<String, dynamic>,
          changed: {
            ..._headers,
            'introduction', // 3.x parsed `info` but left it out (差异 3)
            'area', // 26-6
            'avatar', // the owner's picture (26-5)
            'title', // &amp; decoded (26-4)
            'liveStatus', 'status', // live and marked (26-9)
          },
          added: {'startedAt': _iso(1790161279247), 'restriction': 'needsLogin'},
          reason: call,
        );
      }
      expect(room.introduction, 'live @ HotBeats.TV');
      expect(room.liveStatus, LiveStatus.live);
      expect(room.restriction, LiveRestriction.needsLogin, reason: 'login_only 1');
      expect(room.title, '[EN - 24/7] Electronica directly from Clubs, Events & Festivals # Regular Live Sessions.');
      expect(room.avatar, 'https://live-storage.fc2.com/thumb/3024638/smallicon.png?1648755797', reason: 'icon');
      expect(room.area, '其他');
      expect((room.watching, room.totalViewers), ('1', '326'));
      expect(member.version, 'P4xXGxUm9kF6HMImKQdQd');
      expect(
        room.data,
        isA<Fc2LiveRoomData>()
            .having((data) => data.state, 'state', Fc2LiveState.restricted)
            .having((data) => data.restriction, 'restriction', LiveRestriction.needsLogin),
      );
      // 3.x refused the status and the stream with `access` and `schema`;
      // the site now says live, and refuses the stream with NeedsLogin.
      _expectLegacyError(legacy['getLiveStatus'], 'access');
      _expectLegacyError(legacy['getPlayQualites'], 'schema');
      _expectLegacyError(legacy['Fc2Api.controlGrant'], 'access');
    });

    test('a points-only channel (login_only 2, recorded for M4.U) is live, needsLogin, nameless', () {
      final member = _member('S02-member-points', '5185474');
      final room = Fc2LiveApi.room(member.channel);
      expect(room.liveStatus, LiveStatus.live);
      expect(room.restriction, LiveRestriction.needsLogin, reason: 'for signed-in viewers holding points');
      expect(room.nick, isEmpty, reason: 'no name or tname: empty, the interface shows the platform name');
      expect(room.title, '＝＝＝＝＝＝テスト');
      expect(room.startedAt, DateTime.utc(2026, 8, 31, 7, 4, 57, 831));
      expect(room.avatar, room.cover, reason: 'no icon or image');
      expect(room.area, '其他');
      expect(room.introduction, startsWith('ここ https://live.fc2.com/17305211/'));
      expect(member.version, isNotNull);
      expect(Fc2LiveApi.refusal(room.restriction, room.roomId), isA<NeedsLogin>());
    });

    test("an offline channel is offline without viewers (3.x failed on its empty version: 'schema')", () {
      final legacy = _legacy('S02-member-offline');
      for (final call in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording', 'getLiveStatus']) {
        _expectLegacyError(legacy[call], 'schema', reason: call);
      }
      final member = _member('S02-member-offline', '10608314');
      expect(member.version, isNull);
      final room = Fc2LiveApi.room(member.channel);
      expect(_projection(room), {
        ..._projection(room),
        'roomId': '10608314',
        'userId': '10608314',
        'title': '適当ゲーム配信',
        'nick': '８リメイク',
        'avatar': 'https://live-storage.fc2.com/thumb/10608314/thumb.jpg?1784857583',
        'cover': 'https://live-storage.fc2.com/thumb/10608314/thumb.jpg?1784857583',
        'area': '闲聊',
        // No viewers while offline (26-8; the answer says 0 and 0).
        'watching': '',
        'onlineViewers': '',
        'totalViewers': '',
        'audienceMetricType': 'onlineViewers',
        'liveStatus': LiveStatus.offline.index,
        'status': false,
        'notice': null, // 3.x's chat notice is gone (M5.22)
        'introduction': '今日はマイクオフ @sangokusi999',
        'link': 'https://live.fc2.com/10608314/',
      });
      expect((room.startedAt, room.restriction), (null, null), reason: 'offline: no start time or restriction');
      expect(
        room.data,
        isA<Fc2LiveRoomData>()
            .having((data) => data.state, 'state', Fc2LiveState.offline)
            .having((data) => data.restriction, 'restriction', isNull),
        reason: 'offline before restricted: is_limited is 1 here',
      );
    });

    test("a channel that never existed is NotFound (3.x: 'schema', from its empty version)", () {
      final legacy = _legacy('S02-member-missing');
      for (final call in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording', 'getLiveStatus']) {
        _expectLegacyError(legacy[call], 'schema', reason: call);
      }
      expect(() => _member('S02-member-missing', '99999999'), throwsA(isA<NotFound>()));
    });

    test('exact lookups of the search are the member rooms (3.x: the same room, or its failure)', () {
      final search = _legacy('S01-directory')['searchRooms (pageSize 20)'] as Map<String, dynamic>;
      final live = Fc2LiveApi.room(_member('S02-member-live', '62996200').channel);
      final liveAdded = {'startedAt': _iso(1790407066410), 'restriction': 'none'};
      for (final key in ['exact 62996200', 'exact https://live.fc2.com/ja/62996200/']) {
        _expectParity(
          _projection(live),
          _maps(_result(search[key])).single,
          changed: {..._headers, ..._notice, 'area'}, // M5.22; 26-6
          added: liveAdded,
          reason: key,
        );
        _expectNoChatNotice(live, _maps(_result(search[key])).single, reason: key);
      }
      final restricted = Fc2LiveApi.room(_member('S02-member-restricted', '3024638').channel);
      _expectParity(
        _projection(restricted),
        _maps(_result(search['exact 3024638'])).single,
        // 差异 3; 26-6; 26-5; 26-4; 26-9.
        changed: {..._headers, 'introduction', 'area', 'avatar', 'title', 'liveStatus', 'status'},
        added: {'startedAt': _iso(1790161279247), 'restriction': 'needsLogin'},
      );
      // 3.x's search failed on these (its `missing` never matched them); the
      // site now finds nothing and the offline channel.
      _expectLegacyError(search['exact 99999999'], 'schema');
      _expectLegacyError(search['exact 10608314'], 'schema');
      expect(_maps(_result(search['exact 62996200 page 2'])), isEmpty);
    });
  });

  group('streams', () {
    test("the tiers, then 3.x's auto unchanged; recipes per quality (26-2)", () {
      final legacy = _legacy('S02-member-live');
      final quality = _maps(_result(legacy['getPlayQualites'])).single;
      const auto = Fc2LiveApi.autoQuality;
      expect((auto.quality, auto.id, auto.sort, auto.data), (quality['quality'], quality['id'], quality['sort'], null));
      // 3.x offered auto alone; now the tiers come first (26-2).
      expect(
        [for (final quality in Fc2LiveApi.qualities) (quality.id, quality.quality)],
        [('50', '超清 3M（β）'), ('40', '超清 2M'), ('30', '高清'), ('20', '标清'), ('10', '流畅'), ('auto', '自适应 HLS')],
      );
      expect(Fc2LiveApi.qualities.map((quality) => quality.sort), [
        50,
        40,
        30,
        20,
        10,
        0,
      ], reason: 'best first, auto last');
      expect(Fc2LiveApi.qualityIds, {for (final quality in Fc2LiveApi.qualities) quality.id});
      expect(Fc2LiveApi.qualityIds, contains(quality['id']), reason: "3.x's stored id needs no mapping (M9)");
      final resolved = _result(legacy['resolvePlayUrlsRaw(auto)'])! as Map<String, dynamic>;
      expect(resolved, {'urls': <String>[], 'appliedQualityData': 'auto', 'inputRecipe': 'fc2live:62996200:auto'});
      expect(Fc2LiveInputRecipe('62996200').identity, legacy['Fc2InputRecipe.identity']);
      expect(Fc2LiveInputRecipe('62996200', quality: '30').identity, 'fc2live:62996200:30');
      expect(Fc2LiveInputRecipe('62996200', quality: '30'), isNot(Fc2LiveInputRecipe('62996200')));
      expect(_result(legacy['resolvePlayUrlsForRecoveryRaw(auto)']), resolved);
      // A refreshed room had no entry data in 3.x, so it could not be
      // played without entering it again; it can now (差异 5).
      _expectLegacyError(legacy['getPlayQualites(refresh detail)'], 'schema');
      _expectLegacyError(legacy['resolvePlayUrlsRaw(original)'], 'schema');
    });

    test("3.x's media headers, lower-cased", () {
      final legacy = (_legacy('S02-member-live')['Fc2Api.mediaHeaders'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key.toLowerCase(), value),
      );
      expect(Fc2LiveApi.mediaHeaders('62996200'), legacy);
      expect(Fc2LiveApi.mediaHeaders('62996200'), {
        'user-agent': _userAgent,
        'origin': 'https://live.fc2.com',
        'referer': 'https://live.fc2.com/62996200/',
      });
    });

    test('S03 the control grant matches 3.x; another channel is refused', () {
      final legacy = _legacy('S03-control');
      final grant = Fc2LiveApi.grant(_sample('S03-control').body, channelId: '62996200');
      expect({
        'channelId': grant.channelId,
        'webSocket': '${grant.socket}',
        'controlToken': grant.controlToken,
        'orz': grant.orz,
      }, legacy['62996200']);
      expect(_legacy('S02-member-live')['Fc2Api.controlGrant'], containsPair('result', legacy['62996200']));
      expect(legacy['10608314'], {'throws': 'Fc2Exception', 'message': 'FC2 Live schema'});
      expect(() => Fc2LiveApi.grant(_sample('S03-control').body, channelId: '10608314'), throwsA(isA<ApiChanged>()));
      expect(grant.endpoint.queryParameters, {'control_token': grant.controlToken});
      expect(grant.endpoint.path, '/control/channels/62996200');
      expect(grant.handshakeHeaders, {
        'origin': 'https://live.fc2.com',
        'user-agent': _userAgent,
        'cookie': 'l_ortkn=e2bcebc208d2741cdb70b92ecec38ed8936c921c',
      });
    });

    test("S04 the HLS answer names 3.x's master and every playlist; another channel is refused", () {
      final legacy = _legacy('control/S04-control');
      final answer = _recordedAnswer();
      expect('${Fc2LiveApi.hlsMaster(answer, channelId: '62996200')}', legacy['62996200']);
      final playlists = Fc2LiveApi.hlsPlaylists(answer, channelId: '62996200');
      expect(playlists.keys.toList()..sort(), [0, 1, 2, 10, 11, 12, 20, 21, 22, 30, 31, 32, 90, 91, 92]);
      expect('${playlists[0]}', legacy['62996200'], reason: "mode 0 is 3.x's master");
      for (final MapEntry(key: mode, value: url) in playlists.entries) {
        expect(url.path, '/a/stream/62996200/$mode/${mode < 10 ? 'master_playlist' : 'playlist'}');
      }
      expect(legacy['10608314'], {'throws': 'Fc2Exception', 'message': 'FC2 Live schema'});
      expect(() => Fc2LiveApi.hlsMaster(answer, channelId: '10608314'), throwsA(isA<ApiChanged>()));
      expect(() => Fc2LiveApi.hlsPlaylists(answer, channelId: '10608314'), throwsA(isA<ApiChanged>()));
      expect(legacy['sent'], [Fc2LiveControl.hlsRequest]);
      expect(Fc2LiveApi.qualitiesOf(playlists).map((quality) => quality.id), [
        '30',
        '20',
        '10',
        'auto',
      ], reason: 'no 50 or 40 for this channel: not listed');
    });

    test("S04 a tier plays its high-latency variant; auto plays 3.x's master (26-2)", () {
      final playlists = Fc2LiveApi.hlsPlaylists(_recordedAnswer(), channelId: '62996200');
      for (final (quality, mode) in [('30', 31), ('20', 21), ('10', 11), ('auto', 0)]) {
        final chosen = Fc2LiveApi.playlistFor(playlists, quality)!;
        expect(chosen.quality, quality);
        expect(chosen.url, playlists[mode], reason: quality);
      }
      for (final (quality, playing) in [('50', '30'), ('40', '30')]) {
        expect(Fc2LiveApi.playlistFor(playlists, quality)?.quality, playing, reason: '$quality: the next lower tier');
      }
      for (final quality in ['', 'original', '60', '31', '030']) {
        expect(Fc2LiveApi.playlistFor(playlists, quality), isNull, reason: quality);
      }
    });

    test('S07 (recorded for M4.U): a 1080p broadcast offers 50 and 40 too, each on its high-latency variant', () {
      final frames = _sample('control/S07-control-hd').frames.map((frame) => jsonDecode(frame) as Map);
      expect(frames.singleWhere((message) => message['name'] == 'video_information')['arguments'], {
        'type': 'publish',
        'width': 1920,
        'height': 1080,
      });
      final answer = _recordedAnswer('control/S07-control-hd');
      final playlists = Fc2LiveApi.hlsPlaylists(answer, channelId: '10200498');
      expect(playlists.keys.toList()..sort(), [
        for (final mode in [0, 10, 20, 30, 40, 50, 90]) ...[mode, mode + 1, mode + 2],
      ]);
      expect(playlists[0]?.queryParameters['targets'], '10,20,30,40,50,90');
      expect(
        [for (final quality in Fc2LiveApi.qualitiesOf(playlists)) (quality.id, quality.quality)],
        [('50', '超清 3M（β）'), ('40', '超清 2M'), ('30', '高清'), ('20', '标清'), ('10', '流畅'), ('auto', '自适应 HLS')],
      );
      for (final (quality, mode) in [('50', 51), ('40', 41), ('30', 31), ('auto', 0)]) {
        final chosen = Fc2LiveApi.playlistFor(playlists, quality)!;
        expect((chosen.quality, chosen.url), (quality, playlists[mode]), reason: quality);
        expect(chosen.url.path, '/a/stream/10200498/$mode/${mode == 0 ? 'master_playlist' : 'playlist'}');
      }
    });

    test('the qualities a channel offers: tiers with a variant in any family, auto with a master', () {
      List<Object?> ids(List<int> modes) => [
        for (final quality in Fc2LiveApi.qualitiesOf({for (final mode in modes) mode: Uri.parse(_variant(mode))}))
          quality.id,
      ];
      expect(ids([0, 10, 20, 30]), ['30', '20', '10', 'auto']);
      expect(ids([41, 52, 12]), ['50', '40', '10'], reason: 'any family; no master, no auto');
      expect(ids([1]), ['auto']);
      expect(ids([90, 91, 92]), isEmpty, reason: 'sound only');
    });

    test('a missing tier falls back to the next lower, then higher, then a master; auto to the best tier', () {
      Map<int, Uri> only(List<int> modes) => {
        for (final mode in modes) mode: Uri.parse(mode < 10 ? _master.replaceFirst('/0/', '/$mode/') : _variant(mode)),
      };
      (String, int)? play(List<int> modes, String quality) => switch (Fc2LiveApi.playlistFor(only(modes), quality)) {
        final chosen? => (chosen.quality, int.parse(chosen.url.pathSegments[3])),
        null => null,
      };
      expect(play([10, 20, 30], '30'), ('30', 30), reason: 'only low latency: the low-latency variant');
      expect(play([10, 21, 31, 0], '50'), ('30', 31), reason: 'no 50 or 40: the next lower tier');
      expect(play([10, 51], '40'), ('10', 10), reason: 'lower tiers before higher ones');
      expect(play([22, 32], '30'), ('30', 32), reason: 'only middle latency');
      expect(play([10, 11, 21, 0], '30'), ('20', 21), reason: 'no 30: the next lower tier');
      expect(play([30, 31, 0], '10'), ('30', 31), reason: 'no 10 or 20: the next higher tier');
      expect(play([0, 90], '20'), ('auto', 0), reason: 'no tier at all: the master');
      expect(play([1, 2], 'auto'), ('auto', 1), reason: 'no low-latency master: the high-latency one');
      expect(play([11, 21, 31], 'auto'), ('30', 31), reason: 'no master: the best tier');
      expect(play([90, 91], 'auto'), isNull, reason: 'sound only is no quality');
    });
  });

  group('links', () {
    test("3.x's channel rules: numbers and channel links, with a language prefix or a query", () {
      final legacy = _legacy('S02-member-live');
      final table = legacy['Fc2Link.parseChannelId'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in table.entries) {
        expect(Fc2LiveApi.channelId(key), value, reason: key);
        final isLink = key.contains('://');
        expect(Fc2LiveApi.channelIdFromUrl(key), isLink ? value : null, reason: key);
      }
      expect(table, hasLength(22));
      expect(Fc2LiveApi.channelUrl('62996200'), legacy['Fc2Link.channelUrl']);
    });
  });

  group("3.x's checks (synthetic)", () {
    test("3.x's directory payload: open chats skipped, ticket rooms restricted, both audiences", () {
      final channels = Fc2LiveApi.directory(jsonEncode(_directoryPayload()));
      expect(channels.map((channel) => channel.channelId), ['10608314', '11916060', '12000001']);
      final public = channels.first;
      expect((public.currentViewers, public.totalViewers), (61, 1727));
      expect(public.categoryName, '闲聊');
      expect(public.state, Fc2LiveState.live);
      expect(public.startedAt, DateTime.utc(2026, 9, 20, 6, 22, 41, 806));
      expect(channels.last.state, Fc2LiveState.restricted);
      expect(channels.last.restriction, LiveRestriction.paid, reason: 'a ticket (tid 7)');
      final audio = [
        for (final channel in channels)
          if (Fc2LiveApi.inArea(channel, 9)) channel.channelId,
      ];
      expect(audio, ['11916060']);
      expect(Fc2LiveApi.search(channels, 'kitten').single.channelId, '11916060');
    });

    test('directory rows: a row that cannot be read is skipped alone (26-7); the envelope still fails', () {
      String body(List<Object?> rows, {Object? time = 1789980977}) => jsonEncode({'time': time, 'channel': rows});
      for (final (reason, text) in [
        ('no time', body([], time: null)),
        ('time 0', body([], time: 0)),
        ('time text', body([], time: 'soon')),
        ('no channel list', jsonEncode({'time': 1})),
        ('1001 rows', body(List.filled(1001, _directoryRow('1', type: 2)))),
      ]) {
        expect(() => Fc2LiveApi.directory(text), throwsA(isA<ApiChanged>()), reason: reason);
      }
      final good = _directoryRow('11916060', title: 'good');
      for (final (reason, bad) in <(String, Object?)>[
        ('row not an object', '10608314'),
        ('type missing', _directoryRow('10608314', type: null)),
        ('id 0', _directoryRow('0')),
        ('id text', _directoryRow('abc')),
        ('pay missing', _directoryRow('10608314', pay: null)),
        ('login text', _directoryRow('10608314', login: 'no')),
        ('category 100', _directoryRow('10608314', category: 100)),
        ('category -1', _directoryRow('10608314', category: -1)),
        ('name not text', _directoryRow('10608314', name: 7)),
        ('count text', _directoryRow('10608314', count: 'many')),
      ]) {
        // 3.x failed the whole directory on any of these.
        final channels = Fc2LiveApi.directory(body([bad, good, bad]));
        expect(channels.map((channel) => channel.title), ['good'], reason: reason);
        expect(() => Fc2LiveApi.directory(body([bad])), throwsA(isA<ApiChanged>()), reason: '$reason alone');
      }
      expect(Fc2LiveApi.directory(body([_directoryRow('2_5258776', type: 2)])), isEmpty, reason: 'nobody public');
      expect(Fc2LiveApi.directory(body([])), isEmpty);

      Fc2LiveChannel one(Map<String, Object?> row) => Fc2LiveApi.directory(body([row])).single;
      for (final image in [
        'http://live-storage.fc2.com/a.png',
        'https://evil.test/a.png',
        'https://evilfc2.com/a.png',
        'https://u@live-storage.fc2.com/a.png',
        'https://live-storage.fc2.com/a.png#x',
        '//live-storage.fc2.com/a.png',
      ]) {
        expect(one(_directoryRow('10608314', image: image)).cover, isEmpty, reason: image);
      }
      expect(one(_directoryRow('10608314', image: 'https://fc2.com/a.png')).cover, 'https://fc2.com/a.png');
      final counted = one(_directoryRow('10608314', count: '-1', total: null));
      expect((counted.currentViewers, counted.totalViewers), (null, null));
      expect(Fc2LiveApi.room(counted).audienceMetricType, AudienceMetricType.unknown);
      expect((Fc2LiveApi.room(counted).watching, Fc2LiveApi.room(counted).onlineViewers), ('', ''));
      expect(one(_directoryRow('10608314', count: '5', category: '3')).categoryName, '游戏 / 作业');
      expect(
        one(_directoryRow('10608314', name: '  a   b ', title: '')).title,
        'a b',
        reason: 'whitespace collapsed',
      );
      expect(one(_directoryRow('10608314', count: 2.9)).currentViewers, 2, reason: '3.x truncated numbers');
      final twice = Fc2LiveApi.directory(body([_directoryRow('10608314'), _directoryRow('10608314', title: 'again')]));
      expect(twice.single.title, 'Fixture game stream', reason: 'the first row of a channel wins');
      expect(Fc2LiveApi.directory(body([_directoryRow('2_5258776', type: 2)])), isEmpty);
    });

    test('directory rows: restrictions (26-9), entities (26-4), placeholders and start times', () {
      Fc2LiveChannel one(Map<String, Object?> row) => Fc2LiveApi.directory(
        jsonEncode({
          'time': 1,
          'channel': [row],
        }),
      ).single;
      for (final (reason, row, restriction) in [
        ('open', _directoryRow('1'), LiveRestriction.none),
        ('pay per minute', _directoryRow('1', pay: 1), LiveRestriction.paid),
        ('ticket', _directoryRow('1', tid: 3), LiveRestriction.paid),
        ('signed-in viewers', _directoryRow('1', login: 1), LiveRestriction.needsLogin),
        ('points holders', _directoryRow('1', login: 2), LiveRestriction.needsLogin),
        ('pay before login', _directoryRow('1', pay: 1, login: 1), LiveRestriction.paid),
      ]) {
        final channel = one(row);
        expect(channel.restriction, restriction, reason: reason);
        expect(channel.state, restriction == LiveRestriction.none ? Fc2LiveState.live : Fc2LiveState.restricted);
        expect(Fc2LiveApi.room(channel).liveStatus, LiveStatus.live, reason: reason);
      }
      final decoded = one(
        _directoryRow('1', name: 'A &amp; B&#39;s', title: '&lt;b&gt;Q&amp;A&nbsp;&nbsp;night&lt;/b&gt;'),
      );
      expect((decoded.userName, decoded.title), ("A & B's", '<b>Q&A night</b>'));
      final blank = one(_directoryRow('1', name: '', title: ''));
      expect((blank.userName, blank.title), ('', ''), reason: '3.x wrote the channel number for both');
      expect(Fc2LiveApi.room(blank).nick, isEmpty);
      for (final (value, expected) in <(Object?, DateTime?)>[
        (1789885361806, DateTime.utc(2026, 9, 20, 6, 22, 41, 806)),
        ('1789885361806', DateTime.utc(2026, 9, 20, 6, 22, 41, 806)),
        (0, null),
        (null, null),
        (1789885361, null),
        (4102444800001, null),
        ('soon', null),
      ]) {
        expect(one(_directoryRow('1', startTime: value)).startedAt, expected, reason: '$value');
      }
    });

    test("3.x's member payload and its checks", () {
      final member = Fc2LiveApi.member(_memberPayload(), channelId: '10608314');
      expect(member.channel.userName, 'Fixture owner');
      expect(member.channel.state, Fc2LiveState.live);
      expect(member.channel.restriction, LiveRestriction.none);
      expect(member.channel.startedAt, DateTime.utc(2026, 9, 20, 6, 22, 41, 806));
      expect(member.channel.currentViewers, 61);
      expect(member.version, 'fixture-version');
      expect(Fc2LiveApi.room(member.channel).introduction, 'Fixture description');

      Fc2LiveChannel channel({
        Map<String, Object?> set = const {},
        Object? profile = const {'userid': 10608314, 'name': 'Fixture owner'},
      }) => Fc2LiveApi.member(
        _memberPayload(set: set, profile: profile),
        channelId: '10608314',
      ).channel;
      for (final (flag, value, restriction) in [
        ('fee', 1, LiveRestriction.paid),
        ('ticketid', 12, LiveRestriction.paid),
        ('ticket_only', 1, LiveRestriction.paid),
        ('login_only', 1, LiveRestriction.needsLogin),
        ('login_only', 2, LiveRestriction.needsLogin),
        ('is_limited', 1, LiveRestriction.unplayable),
      ]) {
        final restricted = channel(set: {flag: value});
        expect(restricted.state, Fc2LiveState.restricted, reason: flag);
        expect(restricted.restriction, restriction, reason: '$flag $value');
        final offline = channel(set: {flag: value, 'is_publish': 0});
        expect((offline.state, offline.restriction, offline.startedAt), (Fc2LiveState.offline, null, null));
      }
      expect(channel(set: {'is_limited': 1, 'fee': 1}).restriction, LiveRestriction.unplayable, reason: 'FC2 first');
      expect(channel(set: {'fee': 1, 'login_only': 1}).restriction, LiveRestriction.paid, reason: 'paid first');
      expect(channel(set: {'is_publish': 2}).state, Fc2LiveState.offline, reason: 'only 1 is live (3.x)');
      expect(channel(set: {'is_publish': '1'}).state, Fc2LiveState.live);
      expect(channel(profile: null).userName, isEmpty, reason: 'no profile, no tname: empty (3.x: the number)');
      expect(channel(profile: null, set: {'tname': 'Owner'}).userName, 'Owner');
      expect(channel(profile: null, set: {'tname': 'Owner', 'title': ''}).title, 'Owner');
      expect(channel(profile: null, set: {'title': ''}).title, isEmpty, reason: '3.x: the number');
      expect(channel(set: {'title': ''}).title, 'Fixture owner');
      expect(channel(set: {'category': '0', 'category_name': 'ライブ配信'}).categoryName, isEmpty, reason: 'unknown');
      expect(channel(set: {'category_name': 5}).categoryName, '闲聊', reason: 'the site name is not read (26-6)');
      expect(channel(set: {'info': ' two\n\nlines '}).description, 'two lines');
      expect(channel(set: {'info': 'clubs &amp; festivals&ensp;#1'}).description, 'clubs & festivals #1');
      expect(
        channel(set: {'title': 'Q&amp;A'}, profile: {'userid': 1, 'name': 'A&amp;B'}).title,
        'Q&A',
        reason: '26-4',
      );
      expect(channel(profile: {'userid': 1, 'name': 'A&amp;B'}).userName, 'A&B');
      expect(channel(set: {'adult': 1}).isAdult, isTrue);
      expect(Fc2LiveApi.room(channel(set: {'adult': 1})).restriction, LiveRestriction.none, reason: 'a notice only');
      expect(Fc2LiveApi.room(channel(set: {'adult': 1})).notice, Fc2LiveApi.noticeText['fc2live_adult_notice']);
      expect(
        Fc2LiveApi.room(channel(set: {'adult': 1, 'fee': 1})).notice,
        Fc2LiveApi.noticeText['fc2live_access_restricted'],
        reason: 'the restriction first (3.x)',
      );
      expect(Fc2LiveApi.member(_memberPayload(set: {'version': ''}), channelId: '10608314').version, isNull);
      for (final (value, expected) in <(Object?, DateTime?)>[
        (0, null),
        ('1789885361806', DateTime.utc(2026, 9, 20, 6, 22, 41, 806)),
        (-1, null),
        ('soon', null),
        (<int>[], null),
      ]) {
        expect(channel(set: {'start': value}).startedAt, expected, reason: '$value, never a failure');
      }

      expect(() => Fc2LiveApi.member(_memberPayload(status: 0), channelId: '10608314'), throwsA(isA<NotFound>()));
      expect(
        () => Fc2LiveApi.member(_memberPayload(profile: {'userid': '', 'name': ''}), channelId: '10608314'),
        throwsA(isA<NotFound>()),
      );
      for (final (reason, text) in [
        ('another channel', _memberPayload(set: {'channelid': '10608315'})),
        ('no status', _memberPayload(status: null)),
        ('no channel_data', jsonEncode({'status': 1, 'data': <String, Object?>{}})),
        ('data not an object', jsonEncode({'status': 1, 'data': <Object?>[]})),
        ('profile not an object', _memberPayload(profile: 'owner')),
        ('is_publish missing', _memberPayload(remove: {'is_publish'})),
        ('fee missing', _memberPayload(remove: {'fee'})),
        ('adult missing', _memberPayload(remove: {'adult'})),
        ('category 100', _memberPayload(set: {'category': 100})),
        ('title not text', _memberPayload(set: {'title': 5})),
        ('version too long', _memberPayload(set: {'version': 'v' * 257})),
        ('channelid a number', _memberPayload(set: {'channelid': 10608314})),
      ]) {
        expect(() => Fc2LiveApi.member(text, channelId: '10608314'), throwsA(isA<ApiChanged>()), reason: reason);
      }
    });

    test("the owner's picture: icon, else image, else the cover; never a failure (26-5)", () {
      String avatar(Object? profile) =>
          Fc2LiveApi.room(Fc2LiveApi.member(_memberPayload(profile: profile), channelId: '10608314').channel).avatar;
      const cover = 'https://live-storage.fc2.com/thumb/10608314/thumb.jpg';
      const icon = 'https://live-storage.fc2.com/thumb/10608314/smallicon.png?1';
      const image = 'https://live-storage.fc2.com/thumb/10608314/largeicon.jpg?1';
      expect(avatar({'userid': 1, 'icon': icon, 'image': image}), icon);
      expect(avatar({'userid': 1, 'icon': '', 'image': image}), image);
      expect(avatar({'userid': 1, 'icon': 'https://evil.test/a.png', 'image': ''}), cover);
      expect(avatar({'userid': 1, 'icon': 7, 'image': <String>[]}), cover, reason: 'wrong types only drop the picture');
      expect(avatar({'userid': 1, 'icon': 'x' * 70000}), cover);
      expect(avatar({'userid': 1}), cover);
    });

    test('refusals by restriction: NeedsLogin for signed-in viewers, StreamUnavailable with the reason', () {
      expect(Fc2LiveApi.refusal(null, '1'), isNull);
      expect(Fc2LiveApi.refusal(LiveRestriction.none, '1'), isNull);
      expect(Fc2LiveApi.refusal(LiveRestriction.needsLogin, '1'), isA<NeedsLogin>());
      for (final kind in [LiveRestriction.paid, LiveRestriction.unplayable, LiveRestriction.private]) {
        expect(
          Fc2LiveApi.refusal(kind, '1'),
          isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('channel 1')),
          reason: kind.name,
        );
      }
      expect(Fc2LiveApi.refusal(LiveRestriction.unplayable, '1')?.detail, contains('配信規制中'));
      expect(Fc2LiveApi.refusal(LiveRestriction.paid, '1')?.detail, contains('paid'));
    });

    test("3.x's control payload and the grant's checks", () {
      final grant = Fc2LiveApi.grant(jsonEncode(_controlPayload()), channelId: '10608314');
      expect(grant.socket.host, 'us-west-1-media-worker1077.live.fc2.com');
      expect(grant.socket.path, '/control/channels/10608314');
      expect(grant.controlToken, 'fixture-control-token');
      expect(grant.orz, 'fixture_orz-token');
      expect(
        () => Fc2LiveApi.grant(jsonEncode(_controlPayload(set: {'status': 1})), channelId: '10608314'),
        throwsA(isA<StreamUnavailable>()),
      );
      for (final (reason, set) in <(String, Map<String, Object?>)>[
        ('https', {'url': 'https://live.fc2.com/control/channels/10608314'}),
        ('other host', {'url': 'wss://fc2.com/control/channels/10608314'}),
        ('look-alike host', {'url': 'wss://live.fc2.com.evil.test/control/channels/10608314'}),
        ('user info', {'url': 'wss://u@live.fc2.com/control/channels/10608314'}),
        ('other channel', {'url': 'wss://live.fc2.com/control/channels/1'}),
        ('query', {'url': 'wss://live.fc2.com/control/channels/10608314?x=1'}),
        ('fragment', {'url': 'wss://live.fc2.com/control/channels/10608314#x'}),
        ('url too long', {'url': 'wss://live.fc2.com/control/channels/10608314/${'x' * 2048}'}),
        ('no token', {'control_token': ''}),
        ('token too long', {'control_token': 't' * 4097}),
        ('orz with a separator', {'orz_raw': 'a;b'}),
        ('orz too long', {'orz_raw': 'o' * 257}),
        ('no status', {'status': null}),
      ]) {
        expect(
          () => Fc2LiveApi.grant(jsonEncode(_controlPayload(set: set)), channelId: '10608314'),
          throwsA(isA<ApiChanged>()),
          reason: reason,
        );
      }
      expect(Fc2LiveApi.grant(jsonEncode(_controlPayload(set: {'status': '0'})), channelId: '10608314'), isNotNull);
    });

    test("the HLS answer's checks: a malformed playlist is skipped alone; none usable is ApiChanged", () {
      expect('${Fc2LiveApi.hlsMaster(_hlsAnswer(), channelId: '10608314')}', _master);
      final skipped = _hlsAnswer(
        playlists: [
          {'mode': 0, 'status': 1, 'url': 'broken'},
          {'mode': '0', 'status': '0', 'url': _master},
        ],
      );
      expect('${Fc2LiveApi.hlsMaster(skipped, channelId: '10608314')}', _master, reason: 'unavailable rows skipped');
      expect(
        () => Fc2LiveApi.hlsMaster(_hlsAnswer(status: 1), channelId: '10608314'),
        throwsA(isA<StreamUnavailable>()),
      );
      Map<String, dynamic> withMaster(String url) => _hlsAnswer(
        playlists: [
          {'mode': 0, 'status': 0, 'url': url},
        ],
      );
      // 3.x's checks: each of these was ApiChanged for the whole answer;
      // alone in the answer it still is (no usable playlist).
      final malformed = [
        ('no master', {'mode': 10, 'status': 0, 'url': _master}),
        ('mode missing', {'status': 0, 'url': _master}),
        ('url missing', {'mode': 0, 'status': 0}),
        ('http', {'mode': 0, 'status': 0, 'url': _master.replaceFirst('https', 'http')}),
        (
          'other host',
          {'mode': 0, 'status': 0, 'url': _master.replaceFirst('us-west-1-media.live.fc2.com', 'media.example')},
        ),
        ('user info', {'mode': 0, 'status': 0, 'url': _master.replaceFirst('https://', 'https://u@')}),
        ('other channel', {'mode': 0, 'status': 0, 'url': _master.replaceFirst('10608314', '1')}),
        ('a variant', {'mode': 0, 'status': 0, 'url': _master.replaceFirst('/0/master_playlist', '/30/playlist')}),
        ('fragment', {'mode': 0, 'status': 0, 'url': '$_master#x'}),
        ('extra parameter', {'mode': 0, 'status': 0, 'url': '$_master&e=1'}),
        ('no c', {'mode': 0, 'status': 0, 'url': _master.replaceFirst('c=cc&', '')}),
        ('long d', {'mode': 0, 'status': 0, 'url': _master.replaceFirst('d=dd', 'd=${'d' * 1025}')}),
        ('targets not numbers', {'mode': 0, 'status': 0, 'url': _master.replaceFirst('10,20,30,90', 'all')}),
        (
          '17 targets',
          {'mode': 0, 'status': 0, 'url': _master.replaceFirst('10,20,30,90', List.filled(17, '10').join(','))},
        ),
        ('variant with targets', {'mode': 10, 'status': 0, 'url': '${_variant(10)}&targets=10'}),
        ('variant of another mode', {'mode': 10, 'status': 0, 'url': _variant(20)}),
        ('not an object', 'row'),
      ];
      for (final (reason, row) in malformed) {
        expect(
          () => Fc2LiveApi.hlsPlaylists(_hlsAnswer(playlists: [row]), channelId: '10608314'),
          throwsA(isA<ApiChanged>()),
          reason: reason,
        );
        // Beside a good playlist, only the malformed one is missing (26-7's
        // rule for playlists: one bad address only loses its own quality).
        final playlists = Fc2LiveApi.hlsPlaylists(
          _hlsAnswer(
            playlists: [
              row,
              {'mode': 20, 'status': 0, 'url': _variant(20)},
            ],
          ),
          channelId: '10608314',
        );
        expect(playlists.keys, [20], reason: reason);
      }
      for (final (reason, answer) in [
        ('not the answer', {..._hlsAnswer(), 'name': 'user_count'}),
        ('another id', {..._hlsAnswer(), 'id': 2}),
        ('no arguments', {'name': '_response_', 'id': 1}),
        ('no status', _hlsAnswer(status: null)),
        ('no playlists', _hlsAnswer(playlists: 'none')),
        ('33 playlists', _hlsAnswer(playlists: List.filled(33, {'mode': 10, 'status': 0, 'url': _variant(10)}))),
        ('a master in the wrong row', withMaster(_master.replaceFirst('/0/', '/1/'))),
      ]) {
        expect(() => Fc2LiveApi.hlsMaster(answer, channelId: '10608314'), throwsA(isA<ApiChanged>()), reason: reason);
      }
      // A family that breaks the rules is skipped; the others still count.
      final families = Fc2LiveApi.hlsPlaylists(
        _hlsAnswer(
          playlists: List.filled(33, {'mode': 10, 'status': 0, 'url': _variant(10)}),
          more: {
            'playlists_high_latency': [
              {'mode': 31, 'status': 0, 'url': _variant(31)},
            ],
            'playlists_middle_latency': 'none',
          },
        ),
        channelId: '10608314',
      );
      expect(families.keys, [31]);
      final twice = Fc2LiveApi.hlsPlaylists(
        _hlsAnswer(
          playlists: [
            {'mode': 10, 'status': 0, 'url': _variant(10)},
            {'mode': 10, 'status': 0, 'url': '${_variant(10)}x'},
          ],
        ),
        channelId: '10608314',
      );
      expect('${twice[10]}', _variant(10), reason: 'the first row of a mode wins');
    });

    test("3.x's status mapping, body limit and JSON checks", () {
      for (final (status, matcher) in [
        (400, isA<ApiChanged>()),
        (422, isA<ApiChanged>()),
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (500, isA<NetworkFailure>()),
        (503, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
        (204, isA<NetworkFailure>()),
      ]) {
        expect(
          () => Fc2LiveApi.directory(jsonEncode(_directoryPayload()), status: status),
          throwsA(matcher),
          reason: '$status',
        );
        expect(() => Fc2LiveApi.member(_memberPayload(), channelId: '10608314', status: status), throwsA(matcher));
        expect(
          () => Fc2LiveApi.grant(jsonEncode(_controlPayload()), channelId: '10608314', status: status),
          throwsA(matcher),
        );
      }
      for (final body in ['<html>', '[]', '"text"', '']) {
        expect(() => Fc2LiveApi.directory(body), throwsA(isA<ApiChanged>()), reason: body);
      }
      final large = jsonEncode({..._directoryPayload(), 'padding': 'あ' * (Fc2LiveApi.responseLimit ~/ 3 + 1)});
      expect(() => Fc2LiveApi.directory(large), throwsA(isA<ApiChanged>()), reason: 'over 4 MiB in UTF-8');
    });

    test('recipes are the channel and the quality; rooms carry no media headers', () {
      expect(Fc2LiveInputRecipe('10608314'), Fc2LiveInputRecipe('10608314'));
      expect(Fc2LiveInputRecipe('10608314').identity, 'fc2live:10608314:auto');
      expect(Fc2LiveInputRecipe('10608314').quality, 'auto');
      for (final quality in Fc2LiveApi.qualityIds) {
        expect(Fc2LiveInputRecipe('10608314', quality: quality).identity, 'fc2live:10608314:$quality');
      }
      for (final bad in ['', '0', 'abc', 'https://live.fc2.com/10608314/']) {
        expect(() => Fc2LiveInputRecipe(bad), throwsArgumentError, reason: bad);
      }
      for (final quality in ['', '60', 'original', 'AUTO']) {
        expect(() => Fc2LiveInputRecipe('10608314', quality: quality), throwsArgumentError, reason: quality);
      }
      final room = Fc2LiveApi.room(Fc2LiveApi.member(_memberPayload(), channelId: '10608314').channel);
      expect(room.httpHeaders, isEmpty);
      expect(room.toJson()['httpHeaders'], isEmpty);
      expect(room.toJson().keys, containsAll(['startedAt', 'restriction']));
      expect(
        room.toJson().toString(),
        isNot(contains('Fc2LiveDanmakuArgs')),
        reason: 'comment arguments are not stored',
      );
    });
  });
}

extension on LiveArea {
  LiveArea copyWithId(String id) =>
      LiveArea(platform: platform, areaType: areaType, typeName: typeName, areaId: id, areaName: areaName);
}

extension on Fixture {
  /// The text frames the server sent, in order (a `frames.jsonl` sample).
  List<String> get frames => [
    for (final line in File('${directory.path}/frames.jsonl').readAsLinesSync())
      if (line.trim().isNotEmpty)
        if (jsonDecode(line) case {'dir': 'in', 'text': final String text}) text,
  ];
}
