// Douyu parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json). Every intended difference is listed
// with its reason; everything else must match.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('douyu', name);

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

Map<String, dynamic> _vectors(String name) =>
    jsonDecode(File('../../fixtures/douyu/$name/vectors.json').readAsStringSync()) as Map<String, dynamic>;

String _jwt(Map<String, Object?> payload) =>
    'eyJhbGciOiJIUzI1NiJ9.${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.sig';

DateTime _seconds(int value) => DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);

void main() {
  test('S01 categories: ids, names and areas match 3.x', () {
    final fixture = _sample('S01-cate-list');
    final categories = DouyuApi.categories(fixture.body, status: fixture.status);
    final legacy = (fixture.legacy as List).cast<Map<String, dynamic>>();
    expect(categories.map((category) => category.id), legacy.map((category) => category['id']));
    expect(categories.map((category) => category.name), legacy.map((category) => category['name']));
    for (final (index, category) in categories.indexed) {
      final areas = (legacy[index]['children'] as List).cast<Map<String, dynamic>>();
      expect(category.children, hasLength(areas.length));
      for (final (position, area) in category.children.indexed) {
        // areaPic: an empty `icon` falls back to `smallIcon` (M4.D); 3.x
        // showed no picture.
        final fallback = areas[position]['areaPic'] == '';
        _expectParity(
          area.toJson(),
          areas[position],
          changed: {if (fallback) 'areaPic'},
          reason: 'S01[$index][$position]',
        );
        if (fallback) expect(area.areaPic, startsWith('https://'));
      }
    }
  });

  test('S01 2026-10: an area with an empty icon takes its smallIcon (M4.D)', () {
    final fixture = _sample('S01-cate-list-2026-10');
    final categories = DouyuApi.categories(fixture.body, status: fixture.status);
    final areas = categories.expand((category) => category.children).toList();
    expect(categories, hasLength(10));
    expect(areas, hasLength(485));
    final fallout = areas.singleWhere((area) => area.areaId == '918');
    expect(fallout.areaName, '辐射：避难所Online');
    expect(fallout.areaPic, 'https://sta-op.douyucdn.cn/dycatr/8ae25a2f8d3e0e987a3ef889f6e7eb56.png');
    expect(areas.where((area) => area.areaPic.isEmpty), isEmpty);
  });

  group('S02/S03 room lists', () {
    for (final (name, page, more) in [
      ('S02-mixlist-page1', 1, true),
      ('S02-mixlist-last', 6, false),
      ('S02-mixlist-beyond', 7, false),
      ('S03-allpage-page1', 1, true),
      ('S03-allpage-last', 218, true),
      ('S03-allpage-beyond', 1000, false),
    ]) {
      test('$name: same rooms in the same order as 3.x; the end comes from the server', () {
        final fixture = _sample(name);
        final result = DouyuApi.roomList(fixture.body, page: page, status: fixture.status);
        final legacy = (fixture.legacy as List).cast<Map<String, dynamic>>();
        expect(result.rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        for (final (index, room) in result.rooms.indexed) {
          // title: HTML entities decoded (3.x showed `&nbsp;`; its v4 bridge
          // decoded them too).
          _expectParity(room.toJson(), legacy[index], changed: {'title'}, reason: '$name[$index]');
          expect(room.title, decodeHtmlEntities(legacy[index]['title'] as String));
          expect(room.onlineViewers, isEmpty, reason: '`ol` is heat, never a head count (REG-DOUYU-026)');
        }
        // mixList stops at pgcnt (6 pages of 120); allpage only on an empty
        // page (pgcnt is always 0, 40 a page).
        expect(result.hasMore, more);
      });
    }

    test('list avatars: mixList paths are completed, allpage URLs kept, a missing one is empty', () {
      final mix = DouyuApi.roomList(_sample('S02-mixlist-page1').body, page: 1).rooms;
      expect(mix.first.avatar, startsWith('https://apic.douyucdn.cn/upload/avatar_v3/'));
      expect(mix.first.avatar, endsWith('_middle.jpg'));
      final body = jsonEncode({
        'code': 0,
        'data': {
          'rl': [
            {'type': 1, 'rid': 1, 'rn': 'a', 'nn': 'b', 'ol': 5},
            {'type': 1, 'rid': 2, 'av': 'https://apic.douyucdn.cn/upload/x_middle.jpg'},
            {'type': 2, 'rid': 3},
            {'type': '1', 'rid': 4},
          ],
          'pgcnt': 0,
        },
      });
      final rooms = DouyuApi.roomList(body, page: 1).rooms;
      expect(rooms.map((room) => room.roomId), ['1', '2', '4'], reason: 'only type 1, as a number or a string');
      expect(rooms[0].avatar, isEmpty, reason: '3.x wrote …/upload/null_middle.jpg');
      expect(rooms[1].avatar, 'https://apic.douyucdn.cn/upload/x_middle.jpg');
      expect(rooms[0].watching, '5');
    });
  });

  group('S04 search', () {
    for (final name in ['S04-search-page1', 'S04-search-page2', 'S04-search-mixed', 'S04-search-empty']) {
      test('$name matches 3.x', () {
        final fixture = _sample(name);
        final rooms = DouyuApi.searchRooms(fixture.body, status: fixture.status);
        final legacy = (fixture.legacy as List).cast<Map<String, dynamic>>();
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        for (final (index, room) in rooms.indexed) {
          // title: see the lists (S04-search-page2 has `&nbsp;`).
          // liveStatus, isRecord: a loop room (roomType 3) is a replay, as
          // the same room's betard says (videoLoop 1) and 3.x's v4 bridge
          // showed it; 3.x's own search parser called it offline.
          final loop = room.isRecord;
          _expectParity(
            room.toJson(),
            legacy[index],
            changed: {
              'title',
              if (loop) ...{'liveStatus', 'isRecord'},
            },
            reason: '$name[$index]',
          );
          expect(room.title, decodeHtmlEntities(legacy[index]['title'] as String));
          if (loop) expect(legacy[index]['liveStatus'], LiveStatus.offline.index);
        }
      });
    }

    test('entities in titles are decoded; heat stays the platform text', () {
      final rooms = DouyuApi.searchRooms(_sample('S04-search-page2').body);
      expect(rooms.first.title, '【CSTG】今天休 陪家人过节');
      final heat = DouyuApi.searchRooms(_sample('S04-search-page1').body).first;
      expect(heat.popularity, '353.9万');
      expect(heat.audienceMetricType, AudienceMetricType.popularity);
    });

    test('loop rooms are replays, live rooms live', () {
      final states = DouyuApi.searchRooms(_sample('S04-search-mixed').body).map((room) => room.liveStatus).toSet();
      expect(states, containsAll([LiveStatus.live, LiveStatus.replay]));
      final offline = DouyuApi.searchRooms(
        jsonEncode({
          'error': 0,
          'data': {
            'relateShow': [
              {'rid': 1, 'isLive': 0, 'roomType': 0},
              {'rid': 2, 'isLive': '1'},
            ],
          },
        }),
      );
      expect(offline.map((room) => room.liveStatus), [LiveStatus.offline, LiveStatus.live]);
    });

    test('an error answer is ApiChanged with the platform message (3.x threw a bare Exception)', () {
      for (final name in ['S04-search-error-kw', 'S04-search-error-blank']) {
        final fixture = _sample(name);
        expect(((fixture.legacy as Map)['throws'] as Map)['type'], 'Exception');
        expect(
          () => DouyuApi.searchRooms(fixture.body, status: fixture.status),
          throwsA(isA<ApiChanged>().having((error) => error.detail, 'detail', contains('kw不能为空'))),
          reason: name,
        );
      }
    });

    test('streamers: live only with roomType 0', () {
      final anchors = DouyuApi.searchAnchors(
        jsonEncode({
          'error': 0,
          'data': {
            'relateUser': [
              {
                'anchorInfo': {'rid': 9, 'avatar': '//apic.douyucdn.cn/a.jpg', 'nickName': 'A&amp;B', 'isLive': 1},
              },
              {
                'anchorInfo': {'rid': '10', 'isLive': 1, 'roomType': 3},
              },
              {'anchorInfo': null},
            ],
          },
        }),
      );
      expect(anchors.map((anchor) => anchor.roomId), ['9', '10']);
      expect(anchors.first.userName, 'A&B');
      expect(anchors.first.avatar, 'https://apic.douyucdn.cn/a.jpg');
      expect(anchors.map((anchor) => anchor.liveStatus), [isTrue, isFalse]);
      expect(() => DouyuApi.searchAnchors('{"error":1,"msg":"x","data":{}}'), throwsA(isA<ApiChanged>()));
    });
  });

  group('S05 room detail', () {
    for (final name in ['S05-live', 'S05-offline', 'S05-replay-videoloop']) {
      test('$name matches 3.x', () {
        final fixture = _sample(name);
        final requested = fixture.url.pathSegments.last;
        final detail = DouyuApi.roomDetail(fixture.body, requestedId: requested, status: fixture.status);
        final legacy = fixture.legacy as Map<String, dynamic>;
        final room = legacy['room'] as Map<String, dynamic>;
        // introduction: entities decoded (3.x showed `&mdash;`).
        // danmakuData: 3.x stored the rid string; the rid now travels in
        // DouyuDanmakuArgs, compared below.
        // startedAt: a key 3.x never wrote (unified principle 开播时间,
        // M2.1): `show_time` of a live room, nothing otherwise.
        _expectParity(detail.room.toJson(), room, changed: {'introduction', 'danmakuData', 'startedAt'}, reason: name);
        expect(detail.room.introduction, decodeHtmlEntities(room['introduction'] as String));
        expect(detail.rid, room['danmakuData']);
        expect(detail.room.roomId, requested, reason: 'a follow keeps the id it was made with');
        expect(detail.room.isLiveNow, legacy['isLiveRoomPayload']);
        expect(room.containsKey('startedAt'), isFalse);
        expect(detail.room.toJson().containsKey('startedAt'), detail.room.isLiveNow, reason: name);
      });
    }

    test('开播时间: a live room starts at show_time; offline and loop rooms have none (M2.1 startedAt)', () {
      LiveRoom detail(String name) => DouyuApi.roomDetail(_sample(name).body, requestedId: '1').room;
      final live = detail('S05-live');
      expect(live.startedAt, DateTime.utc(2026, 9, 26, 11, 0, 29), reason: 'show_time 1790420429');
      expect(live.toJson()['startedAt'], '2026-09-26T11:00:29.000Z');
      expect(detail('S05-offline').startedAt, isNull, reason: 'show_time is the last show');
      expect(detail('S05-replay-videoloop').startedAt, isNull, reason: 'a loop is not a broadcast start');
      DateTime? startedAt(Object? showTime) => DouyuApi.roomDetail(
        jsonEncode({
          'room': {'room_id': 1, 'room_name': 't', 'show_status': 1, 'show_time': ?showTime},
        }),
        requestedId: '1',
      ).room.startedAt;
      expect(startedAt('1790420429'), DateTime.utc(2026, 9, 26, 11, 0, 29), reason: 'a numeric string counts');
      expect(startedAt(0), isNull);
      expect(startedAt(''), isNull);
      expect(startedAt(null), isNull);
    });

    test('the requested address stays the identity; the rid comes back separately', () {
      final detail = DouyuApi.roomDetail(_sample('S05-live').body, requestedId: ' 123455 ');
      expect(detail.room.roomId, '123455');
      expect(detail.room.link, 'https://www.douyu.com/123455');
      expect(detail.rid, '5526219');
    });

    test('state: numeric strings count, a loop is a replay, a 【回放】 title is offline as in 3.x', () {
      String body(Map<String, Object?> room) => jsonEncode({
        'room': {'room_id': 1, 'room_name': '直播中', ...room},
      });
      LiveStatus? state(Map<String, Object?> room) => DouyuApi.roomDetail(body(room), requestedId: '1').room.liveStatus;
      expect(state({'show_status': '1', 'videoLoop': '0'}), LiveStatus.live);
      expect(state({'show_status': 1, 'videoLoop': 1}), LiveStatus.replay);
      expect(state({'show_status': 1, 'room_name': '【回放】上一场'}), LiveStatus.offline);
      expect(state({'show_status': 2}), LiveStatus.offline);
    });

    test('a JSON-encoded string body is decoded', () {
      final inner = jsonEncode({
        'room': {'room_id': 7, 'room_name': 't', 'show_status': 1},
      });
      expect(DouyuApi.roomDetail(jsonEncode(inner), requestedId: '7').room.isLiveNow, isTrue);
    });

    test('a missing room (200 HTML) is NotFound; 3.x threw FormatException', () {
      final fixture = _sample('S05-not-found');
      expect(((fixture.legacy as Map)['throws'] as Map)['type'], 'FormatException');
      expect(
        () => DouyuApi.roomDetail(fixture.body, requestedId: '999999999', status: fixture.status),
        throwsA(isA<NotFound>().having((error) => error.detail, 'detail', contains('该房间目前没有开放'))),
      );
    });

    test('an alias sent to betard is refused with 403: RiskControl', () {
      final fixture = _sample('S05-alias-betard');
      expect(
        () => DouyuApi.roomDetail(fixture.body, requestedId: 'lpl', status: fixture.status),
        throwsA(isA<RiskControl>()),
      );
      expect(() => DouyuApi.roomDetail('{"x":1}', requestedId: '1'), throwsA(isA<ApiChanged>()));
    });

    test('a 靓号 room page names the rid; an alias redirect points at it', () {
      expect(DouyuApi.roomIdInPage('<script>window.room_id = 5526219;</script>'), '5526219');
      expect(DouyuApi.roomIdInPage(r'{\"roomInfo\":{\"room\":{\"room_id\":5526219,\"vipId\":123455}}}'), '5526219');
      expect(DouyuApi.roomIdInPage(r'var $ROOM = {"room_id":"288016"};'), '288016');
      expect(DouyuApi.roomIdInPage('<html>home</html>'), isNull);
      final alias = _sample('S05-alias-redirect');
      final location = (alias.legacy as Map)['location'] as String;
      expect(DouyuApi.roomIdAt(Uri.parse(location)), '288016');
      expect(DouyuApi.roomIdAt(Uri.parse('https://www.douyu.com/g_LOL')), isNull);
      expect(DouyuApi.roomIdAt(Uri.parse('https://example.com/1')), isNull);
    });
  });

  group('gift catalogue (D07.3)', () {
    test('S05-offline betard: 13 room gifts with price in fen, picture under gfs-op, effect; 鱼丸 gifts free', () {
      final gifts = DouyuApi.roomGifts(_sample('S05-offline').body);
      expect(gifts, hasLength(13));
      expect(
        gifts['196'],
        DouyuGiftInfo(
          id: '196',
          name: '火箭',
          price: 50000,
          iconUrl: Uri.parse('https://gfs-op.douyucdn.cn/dygift/1609/8fdc7b6395b93729eed49429d2776a73.png'),
          effect: '143',
        ),
      );
      expect(gifts['1005']?.price, 200000);
      // unit 1 is 鱼丸: free, no price.
      expect((gifts['191']?.free, gifts['191']?.price), (true, null));
      expect((gifts['1571']?.name, gifts['1571']?.free), ('超大丸星', true));
      expect(gifts.ids.where((id) => !gifts[id]!.free).every((id) => gifts[id]!.price! > 0), isTrue);
      // The same answer through roomDetail.
      final detail = DouyuApi.roomDetail(_sample('S05-offline').body, requestedId: '71415');
      expect(detail.gifts.ids.toSet(), gifts.ids.toSet());
      expect(DouyuApi.roomDetail(_sample('S05-live').body, requestedId: '5526219').gifts, hasLength(12));
    });

    test('betard without room_gift (S05-replay-videoloop) or with odd entries: what it can read', () {
      expect(DouyuApi.roomGifts(_sample('S05-replay-videoloop').body).isEmpty, isTrue);
      expect(DouyuApi.roomGifts('not json').isEmpty, isTrue);
      final odd = DouyuApi.roomGifts(
        jsonEncode({
          'room_gift': {
            'gift': {
              'a': {'id': '1', 'name': '甲', 'price': '100', 'unit': '2', 'pc_icon': 'https://x.example/a.png'},
              'b': {'id': '0', 'name': '乙'},
              'c': {'id': '3', 'name': ''},
              'd': {'id': '4', 'name': '丁', 'price': '0', 'unit': '2', 'pc_icon': 'javascript:alert(1)'},
              'e': 'text',
              'f': {'id': '6', 'name': '己', 'pc_icon': 'https://gfs-test-op.douyucdn.cn/dygift/x.png'},
            },
          },
        }),
      );
      expect(odd.ids.toList(), ['1', '4', '6']);
      expect(odd['1']?.iconUrl, Uri.parse('https://x.example/a.png'));
      expect((odd['4']?.price, odd['4']?.iconUrl), (null, null));
      expect(odd['6']?.iconUrl, isNull, reason: 'the test host answers 404');
    });

    test('S17 gift list: price in fen for 鱼翅, 鱼丸 free, picture from picUrlPrefix', () {
      final gifts = DouyuApi.giftList(_sample('S17-gift-list').body);
      expect(gifts, hasLength(10));
      expect(
        gifts['20004'],
        DouyuGiftInfo(
          id: '20004',
          name: '火箭',
          price: 50000,
          iconUrl: Uri.parse('https://gfs-op.douyucdn.cn/dygift/2019/02/18/8bab2f98ab4d3429ffe00472a1a817e5.png'),
        ),
      );
      expect((gifts['24644']?.name, gifts['24644']?.price), ('国庆快乐', 10));
      expect((gifts['20000']?.free, gifts['20000']?.price), (true, null), reason: '100鱼丸 is paid in 鱼丸');
      expect(gifts['20008']?.free, isTrue);
    });

    test('a gift list that is not one: ApiChanged; a refusal: RiskControl', () {
      expect(() => DouyuApi.giftList('{"error":1,"msg":"x"}'), throwsA(isA<ApiChanged>()));
      expect(() => DouyuApi.giftList('{"error":0,"data":{}}'), throwsA(isA<ApiChanged>()));
      expect(() => DouyuApi.giftList('<html>', status: 403), throwsA(isA<RiskControl>()));
      expect(DouyuApi.giftList('{"error":0,"data":{"giftList":[{"id":0},{"name":"x"}]}}').isEmpty, isTrue);
    });

    test('S18 prop table (JSONP): props by gift id, all free, static picture first', () {
      final props = DouyuApi.propGifts(_sample('S18-prop-config').body);
      expect(props, hasLength(4));
      expect(
        props['824'],
        DouyuGiftInfo(
          id: '824',
          name: '粉丝荧光棒',
          free: true,
          iconUrl: Uri.parse('https://gfs-op.douyucdn.cn/dygift/1705/7d724fb3d7e7d4a463a3e74e9929b919.png'),
        ),
      );
      expect(props['520']?.name, '稳');
      // 22037's bimg is on the test host: the full picture instead.
      expect(props['22037']?.iconUrl?.host, 'gfs-op.douyucdn.cn');
      expect(props['22037']?.iconUrl?.path, isNot(contains('318ed7ac571edc441c74d8f57e0a4119')));
      expect(() => DouyuApi.propGifts('DYConfigCallback({"error":0});'), throwsA(isA<ApiChanged>()));
      expect(() => DouyuApi.propGifts('', status: 502), throwsA(isA<NetworkFailure>()));
    });

    test('merging: the later catalogue wins an id both have; empty merges are the same catalogue', () {
      final room = DouyuApi.roomGifts(_sample('S05-offline').body);
      final list = DouyuApi.giftList(_sample('S17-gift-list').body);
      final merged = room.merge(list);
      expect(merged, hasLength(room.length + list.length), reason: 'betard and the list share no id');
      expect(identical(room.merge(DouyuGiftCatalog.empty), room), isTrue);
      expect(identical(DouyuGiftCatalog.empty.merge(list), list), isTrue);
      final renamed = DouyuGiftCatalog(const {'196': DouyuGiftInfo(id: '196', name: '新火箭')});
      expect(room.merge(renamed)['196']?.name, '新火箭');
    });
  });

  group('S06/S07 signing', () {
    test('S06 descriptor: usable at capture and 31 s before expiry, not 30 s before; the form matches 3.x', () {
      final fixture = _sample('S06-encryption');
      final legacy = fixture.legacy as Map<String, dynamic>;
      final descriptor = DouyuApi.descriptor(fixture.body, now: fixture.capturedAt, status: fixture.status);
      expect(descriptor.usableAt(fixture.capturedAt), legacy['usableAtCapture']);
      expect(
        descriptor.usableAt(descriptor.expireAt.subtract(const Duration(seconds: 31))),
        legacy['usable31sBeforeExpiry'],
      );
      expect(
        descriptor.usableAt(descriptor.expireAt.subtract(const Duration(seconds: 30))),
        legacy['usable30sBeforeExpiry'],
      );
      final signed = (legacy['signedAtCapture'] as Map).cast<String, String>();
      expect(
        DouyuApi.signedForm(descriptor, roomId: '4489985', tt: int.parse(signed['tt']!), did: signed['did']!),
        signed,
      );
      expect(
        () => DouyuApi.descriptor(fixture.body, now: descriptor.expireAt),
        throwsA(isA<ApiChanged>()),
        reason: 'an expired descriptor is never used (REG-DOUYU-015)',
      );
    });

    test('S07 vectors: auth, form fields and usability match 3.x', () {
      for (final vector in (_vectors('S07-vectors')['vectors'] as List).cast<Map<String, dynamic>>()) {
        final input = vector['input'] as Map<String, dynamic>;
        final output = vector['output'] as Map<String, dynamic>;
        final tt = input['timestampSeconds'] as int;
        final descriptor = DouyuDescriptor.fromJson(input['encryptionKey']);
        final name = vector['name'];
        expect(
          descriptor != null && descriptor.usableAt(_seconds(tt)),
          output['isEncryptionKeyUsable'],
          reason: '$name',
        );
        if (output['throws'] != null) {
          expect(descriptor == null || !descriptor.expireAt.isAfter(_seconds(tt)), isTrue, reason: '$name');
          continue;
        }
        expect(
          DouyuApi.signedForm(
            descriptor!,
            roomId: input['roomId'] as String,
            tt: tt,
            did: input['deviceId'] as String,
            rate: input['rate'] as int,
            cdn: input['cdn'] as String,
          ),
          (output['fields'] as Map).cast<String, String>(),
          reason: '$name',
        );
      }
    });
  });

  group('S08/S09/S10 play answers', () {
    test('S08-meta-9263298-nostream (E01.7): a live room whose metadata says streamStatus 0 has no stream: '
        'StreamUnavailable, not its URL that answers 404', () {
      final fixture = _sample('S08-meta-9263298-nostream');
      final data = DouyuApi.playData(fixture.body, status: fixture.status);
      expect(data['streamStatus'], 0);
      expect(DouyuApi.mediaUrl(data), isNotNull, reason: 'the answer still carries a URL (404 when tried)');
      expect(() => DouyuApi.qualities(data), throwsA(isA<StreamUnavailable>()));
      // Recorded metadata of rooms that play say 1.
      for (final name in ['S08-meta-24422', 'S08-meta-4489985']) {
        expect(DouyuApi.playData(_sample(name).body)['streamStatus'], 1, reason: name);
      }
      // Without the field (older answers, synthetic ones) nothing changes.
      expect(DouyuApi.qualities({'rate': 2}), hasLength(1));
      expect(DouyuApi.qualities({'rate': 2, 'streamStatus': '1'}), hasLength(1));
      expect(() => DouyuApi.qualities({'rate': 2, 'streamStatus': '0'}), throwsA(isA<StreamUnavailable>()));
    });

    test('E01.7: streamStatus 0 on the answer for one rate is not judged (S09-24422-r2-hw-h5 of a room that '
        'played); only the metadata answer is', () {
      final fixture = _sample('S09-24422-r2-hw-h5');
      final data = DouyuApi.playData(fixture.body);
      expect(data['streamStatus'], 0);
      final answer = DouyuApi.answer(data, roomId: '24422', cdn: 'hw-h5', cookie: '', issuedAt: fixture.capturedAt);
      expect(answer.line.url, isNotEmpty);
    });

    for (final name in ['S08-meta-24422', 'S08-meta-4489985']) {
      test('$name: qualities in platform order, CDNs and the URL match 3.x', () {
        final fixture = _sample(name);
        final legacy = fixture.legacy as Map<String, dynamic>;
        final data = DouyuApi.playData(fixture.body, status: fixture.status);
        final qualities = DouyuApi.qualities(data);
        expect([
          for (final quality in qualities)
            {
              'quality': quality.quality,
              'id': quality.id,
              'sort': quality.sort,
              'rate': (quality.data! as DouyuPlayData).rate,
              'cdns': (quality.data! as DouyuPlayData).cdns,
            },
        ], legacy['parsePlayQualities']);
        expect(DouyuApi.cdns(data), legacy['parseCdnCodes']);
        expect(DouyuApi.mediaUrl(data), legacy['parsePlayUrl']);
      });
    }

    for (final name in [
      'S09-4489985-r0-hw-h5',
      'S09-24422-r0-hw-h5',
      'S09-24422-r0-hs-h5',
      'S09-24422-r2-hw-h5',
      'S09-24422-r0-tct-h5',
    ]) {
      test('$name: URL and confirmed rate match 3.x; the line carries headers and lease', () {
        final fixture = _sample(name);
        final legacy = fixture.legacy as Map<String, dynamic>;
        final resolved = legacy['resolvePlayUrl'] as Map<String, dynamic>;
        final data = DouyuApi.playData(fixture.body, status: fixture.status);
        final cdn = name.split('-').sublist(3).join('-');
        final answer = DouyuApi.answer(
          data,
          roomId: '24422',
          cdn: cdn,
          cookie: 'dy_did=d; acf_did=d',
          issuedAt: fixture.capturedAt,
        );
        expect(answer.line.url, legacy['parsePlayUrl']);
        final resolution = DouyuApi.resolution([answer], requestedRate: int.parse(name.split('-')[2].substring(1)));
        expect(resolution.urls, resolved['urls']);
        expect(resolution.appliedQualityData, resolved['appliedQualityData']);
        expect(resolution.qualityUnconfirmed, resolved['qualityUnconfirmed']);
        final line = resolution.lines.single;
        expect(line.format, StreamFormat.flv);
        expect(line.lineId, cdn, reason: 'the line is its CDN code, never an index');
        expect(line.headers, {
          'origin': 'https://www.douyu.com',
          'referer': 'https://www.douyu.com/24422',
          'user-agent': DouyuApi.userAgent,
          'cookie': 'dy_did=d; acf_did=d',
        });
        final expire = int.parse(Uri.parse(line.url).queryParameters['expire']!);
        if (expire > 0) {
          final lease = line.lease!;
          expect(lease.cutsConnection, isTrue, reason: 'the CDN closes the open connection (REG-DOUYU-001)');
          expect(lease.expiresAt, fixture.capturedAt.toUtc().add(Duration(seconds: expire)));
          expect(lease.expiresAt!.difference(lease.refreshAt), DouyuApi.leaseLead);
        } else {
          expect(line.lease, isNull, reason: 'expire=0 states no lease');
        }
      });
    }

    test('S09 anonymous 原画 is served as 4 and says so (REG-DOUYU-027)', () {
      final data = DouyuApi.playData(_sample('S09-24422-r0-hw-h5').body);
      final meta = DouyuApi.qualities(DouyuApi.playData(_sample('S08-meta-24422').body));
      final answer = DouyuApi.answer(data, roomId: '24422', cdn: 'hw-h5', cookie: '', issuedAt: DateTime.utc(2026));
      final resolution = DouyuApi.resolution([answer], requestedRate: 0);
      final shown = resolveAppliedPlayQuality(qualities: meta, requested: meta.first, resolution: resolution);
      expect(shown.quality, '蓝光4M');
      expect(shown.isPlaybackUnconfirmed, isFalse);
    });

    test('S10 an offline room is StreamUnavailable; the device mismatch 403 is RiskControl', () {
      final offline = _sample('S10-offline');
      expect(
        () => DouyuApi.playData(offline.body, status: offline.status),
        throwsA(isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('-5'))),
      );
      final wrongDid = _sample('S10-wrong-did');
      expect(
        () => DouyuApi.playData(wrongDid.body, status: wrongDid.status),
        throwsA(isA<RiskControl>().having((error) => error.detail, 'detail', contains('鉴权失败'))),
      );
    });
  });

  group('play rules without samples (3.x tests)', () {
    test('success is error 0 as a number or string; no data or no code is ApiChanged', () {
      expect(DouyuApi.playData('{"error":"0","data":{"rtmp_url":"https://example.test/live"}}')['rtmp_url'], isNotNull);
      expect(() => DouyuApi.playData('{"error":102,"msg":"expired"}'), throwsA(isA<StreamUnavailable>()));
      expect(() => DouyuApi.playData('{"error":0}'), throwsA(isA<ApiChanged>()));
      expect(() => DouyuApi.playData('{"data":{}}'), throwsA(isA<ApiChanged>()));
      expect(() => DouyuApi.playData('', status: 502), throwsA(isA<NetworkFailure>()));
    });

    test('qualities keep the platform order and the first of a rate (REG-DOUYU-005)', () {
      final qualities = DouyuApi.qualities({
        'multirates': [
          {'name': '蓝光8M', 'rate': 0},
          {'name': '蓝光4M', 'rate': 1},
          {'name': '流畅', 'rate': 3},
          {'name': '重复流畅', 'rate': 3},
        ],
        'rtmp_cdn': 'main',
        'cdnsWithName': [
          {'cdn': 'main'},
          {'cdn': 'backup'},
        ],
      });
      expect(qualities.map((quality) => quality.quality), ['蓝光8M', '蓝光4M', '流畅']);
      expect(qualities.map((quality) => quality.selectionId), [0, 1, 3]);
      expect((qualities.first.data! as DouyuPlayData).cdns, ['main', 'backup']);
      final fallback = DouyuApi.qualities({'rate': 2}).single;
      expect(fallback.quality, '默认');
      expect(fallback.id, 2);
    });

    test('CDNs: deduplicated, the answering CDN first, scdn last, empty means the server picks', () {
      expect(
        DouyuApi.cdns({
          'rtmp_cdn': 'ws-h5',
          'cdnsWithName': [
            {'cdn': 'scdnctshh'},
            {'cdn': 'tct-h5'},
            {'cdn': 'tct-h5'},
          ],
        }),
        ['ws-h5', 'tct-h5', 'scdnctshh'],
      );
      expect(DouyuApi.cdns(const {}), ['']);
    });

    test('media URL: entities decoded, absolute rtmp_live wins, a bare CDN base is never media', () {
      expect(
        DouyuApi.mediaUrl({
          'rtmp_url': 'https://cdn.example.test/live/',
          'rtmp_live': '/stream.flv?wsAuth=a&amp;token=b',
        }),
        'https://cdn.example.test/live/stream.flv?wsAuth=a&token=b',
        reason: 'REG-DOUYU-010',
      );
      expect(
        DouyuApi.mediaUrl({
          'rtmp_url': 'https://cdn.example.test/live',
          'flv_url': 'https://backup.example.test/live',
          'rtmp_live': 'https://signed.example.test/room.flv?wsAuth=a&amp;token=b',
        }),
        'https://signed.example.test/room.flv?wsAuth=a&token=b',
        reason: 'REG-DOUYU-009',
      );
      expect(
        DouyuApi.mediaUrl({'flv_url': 'https://cdn.example.test/live', 'rtmp_live': 'room_123.flv?wsAuth=signed'}),
        'https://cdn.example.test/live/room_123.flv?wsAuth=signed',
      );
      expect(DouyuApi.mediaUrl({'flv_url': 'https://cdn.example.test/live'}), isNull, reason: 'REG-DOUYU-008');
      expect(DouyuApi.mediaUrl({'rtmp_live': 'relative.flv'}), isNull);
      expect(
        DouyuApi.mediaUrl({'flv_url': 'https://cdn.example.test/live/room.flv'}),
        'https://cdn.example.test/live/room.flv',
      );
      expect(DouyuApi.mediaUrl({'player_1': 'https://p.example.test/x.m3u8'}), 'https://p.example.test/x.m3u8');
      expect(
        () => DouyuApi.answer(const {}, roomId: '1', cdn: '', cookie: '', issuedAt: DateTime.utc(2026)),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('a missing, negative, fractional or text rate is unconfirmed; "0" is source (REG-DOUYU-007)', () {
      for (final value in [null, -1, 1.5, 'bad', '']) {
        expect(DouyuApi.confirmedRate({'rate': value}), isNull, reason: '$value');
      }
      expect(DouyuApi.confirmedRate({'rate': '0'}), 0);
      expect(DouyuApi.confirmedRate({'rate': 4.0}), 4);
    });

    ({LivePlayLine line, int? rate}) answer(String cdn, int? rate) =>
        (line: LivePlayLine('https://$cdn.example.test/live/stream.flv'), rate: rate);

    test('lines of one confirmed rate only: the requested one, else the first confirmed (REG-DOUYU-006)', () {
      final downgraded = DouyuApi.resolution([answer('main', 2), answer('backup', 2)], requestedRate: 0);
      expect(downgraded.appliedQualityData, 2);
      expect(downgraded.urls, hasLength(2));
      final preferred = DouyuApi.resolution([answer('main', 2), answer('backup', 0)], requestedRate: 0);
      expect(preferred.appliedQualityData, 0);
      expect(preferred.urls, ['https://backup.example.test/live/stream.flv']);
      final first = DouyuApi.resolution([answer('main', 3), answer('backup', 2), answer('third', 3)], requestedRate: 0);
      expect(first.appliedQualityData, 3);
      expect(first.urls, ['https://main.example.test/live/stream.flv', 'https://third.example.test/live/stream.flv']);
      final known = DouyuApi.resolution([answer('main', null), answer('backup', 2)], requestedRate: 0);
      expect(known.urls, ['https://backup.example.test/live/stream.flv'], reason: 'never mixed with unconfirmed');
      final unknown = DouyuApi.resolution([answer('main', null), answer('backup', null)], requestedRate: 0);
      expect(unknown.appliedQualityData, isNull);
      expect(unknown.qualityUnconfirmed, isTrue);
      expect(unknown.urls, hasLength(2));
      expect(DouyuApi.resolution(const [], requestedRate: 0).hasSources, isFalse);
    });

    test('leases: only expire > 0; the lead is 45 s or a quarter of a short lifetime', () {
      final issued = DateTime.utc(2026, 9, 27, 10);
      final lease = DouyuApi.lease('https://a.test/r.flv?wsAuth=x&expire=300&did=d', issued)!;
      expect(lease.expiresAt, issued.add(const Duration(seconds: 300)));
      expect(lease.refreshAt, issued.add(const Duration(seconds: 255)));
      expect(lease.cutsConnection, isTrue);
      final short = DouyuApi.lease('https://a.test/r.flv?expire=100', issued)!;
      expect(short.expiresAt!.difference(short.refreshAt), const Duration(seconds: 25));
      expect(DouyuApi.lease('https://a.test/r.flv?expire=0', issued), isNull);
      expect(DouyuApi.lease('https://a.test/r.flv', issued), isNull);
      expect(DouyuApi.lease('https://a.test/r.flv?noexpire=300', issued), isNull);
      expect(DouyuApi.statedLifetime('https://a.test/r.flv?wsAuth=x&expire=300'), const Duration(seconds: 300));
      expect(DouyuApi.statedLifetime('https://a.test/r.flv?expire=0'), isNull);
      expect(DouyuApi.statedLifetime('https://a.test/r.flv'), isNull);
      // E01.8: the CDN signs the first `expire` and still cuts at 300 s when
      // `&expire=0` is appended (upstream a858550bb), so the lease keeps it.
      expect(
        DouyuApi.statedLifetime('https://a.test/r.flv?wsAuth=x&expire=300&fcdn=ws&expire=0'),
        const Duration(seconds: 300),
      );
    });

    test('forced renewal (2-1): a FLV URL stating no lease gets five minutes; stated leases and HLS are unchanged', () {
      final issued = DateTime.utc(2026, 9, 27, 10);
      for (final url in [
        'https://a.test/r.flv?expire=0&wsAuth=x',
        'https://a.test/r.flv',
        'https://a.test/live/R.FLV?noexpire=300',
      ]) {
        expect(DouyuApi.lease(url, issued), isNull, reason: 'off by default: $url');
        final forced = DouyuApi.lease(url, issued, forceRenewal: true)!;
        expect(forced.expiresAt, issued.add(DouyuApi.forcedLeaseLifetime), reason: url);
        expect(forced.refreshAt, issued.add(const Duration(minutes: 4, seconds: 15)), reason: '45 s early: $url');
        expect(forced.cutsConnection, isTrue, reason: 'spliced in like a stated lease (M7): $url');
      }
      expect(DouyuApi.forcedLeaseLifetime, const Duration(minutes: 5));
      final stated = DouyuApi.lease('https://a.test/r.flv?expire=100', issued, forceRenewal: true)!;
      expect(stated.expiresAt, issued.add(const Duration(seconds: 100)), reason: 'a stated lease wins');
      expect(DouyuApi.lease('https://a.test/r.m3u8?expire=0', issued, forceRenewal: true), isNull);
      expect(DouyuApi.lease('not a url', issued, forceRenewal: true), isNull);
    });

    test('forced renewal (2-1) on the samples: expire=0 (S09 rate 2) gets five minutes, expire=300 keeps 300 s', () {
      ({LivePlayLine line, int? rate}) answer(String name, {required bool force}) {
        final fixture = _sample(name);
        return DouyuApi.answer(
          DouyuApi.playData(fixture.body),
          roomId: '24422',
          cdn: 'hw-h5',
          cookie: '',
          issuedAt: fixture.capturedAt,
          forceRenewal: force,
        );
      }

      const zero = 'S09-24422-r2-hw-h5';
      final zeroAt = _sample(zero).capturedAt.toUtc();
      expect(Uri.parse(answer(zero, force: false).line.url).queryParameters['expire'], '0');
      expect(answer(zero, force: false).line.lease, isNull);
      expect(answer(zero, force: true).line.lease!.expiresAt, zeroAt.add(DouyuApi.forcedLeaseLifetime));
      const source = 'S09-24422-r0-hw-h5';
      expect(
        answer(source, force: true).line.lease!.expiresAt,
        _sample(source).capturedAt.toUtc().add(const Duration(seconds: 300)),
      );
    });
  });

  group('cookie and device id (3.x tests)', () {
    test('the account cookie device id heads requests; duplicates, bad names and LTP0 are dropped', () {
      const account = 'Cookie: dy_did=other; acf_did=other2; acf_auth=secret; token=a=b; bad name=no; LTP0=l\r\n';
      final did = DouyuApi.deviceId(DouyuApi.normalizeCookie(account), 'process');
      expect(did, 'other', reason: 'the login belongs to its dy_did (REG-DOUYU-004)');
      final header = DouyuApi.cookieHeader(account: account, did: did);
      expect(header, 'dy_did=other; acf_did=other; acf_auth=secret; token=a=b');
      expect(header, isNot(contains('LTP0')), reason: 'LTP0 only goes to the passport (REG-DOUYU-003)');
      expect(DouyuApi.cookieHeader(account: 'acf_auth=x', did: 'p'), 'dy_did=p; acf_did=p; acf_auth=x');
      expect(DouyuApi.deviceId('acf_auth=x', 'p'), 'p');
      expect(DouyuApi.cookieHeader(account: '', did: 'p'), 'dy_did=p; acf_did=p');
    });

    test('values are forwarded verbatim', () {
      expect(DouyuApi.cookieHeader(account: 'dy_auth=a%2Bb', did: 'p'), contains('dy_auth=a%2Bb'));
    });

    test('a process device id is 32 lower-case hex digits', () {
      expect(DouyuApi.generateDeviceId(Random(1)), matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('media headers: origin, the room referer, UA and cookie', () {
      expect(DouyuApi.mediaHeaders('12345', cookie: 'dy_did=d'), {
        'origin': 'https://www.douyu.com',
        'referer': 'https://www.douyu.com/12345',
        'user-agent': DouyuApi.userAgent,
        'cookie': 'dy_did=d',
      });
    });
  });

  group('login session', () {
    final now = DateTime.utc(2026, 9, 28, 12);
    int secondsFromNow(Duration offset) => now.add(offset).millisecondsSinceEpoch ~/ 1000;

    test('S12 renewal vectors: merge, expiry, state and request cookie match 3.x', () {
      for (final vector in (_vectors('S12-synthetic')['cases'] as List).cast<Map<String, dynamic>>()) {
        final input = vector['input'] as Map<String, dynamic>;
        final output = vector['output'] as Map<String, dynamic>;
        final stored = input['stored'] as String;
        final at = _seconds(input['nowSeconds'] as int);
        final savedAt = switch (input['savedAtSeconds']) {
          final int value => _seconds(value),
          _ => null,
        };
        final name = vector['name'];
        final credentials = DouyuApi.renewalCredentials(stored);
        final before = output['before'] as Map<String, dynamic>;
        expect(DouyuApi.sessionExpiry(stored, savedAt: savedAt), DateTime.parse(before['sessionExpiry'] as String));
        expect(
          DouyuApi.sessionState(stored, now: at, savedAt: savedAt, ltp0: credentials.ltp0, did: credentials.did).name,
          before['sessionState'],
          reason: '$name',
        );
        final renewed = DouyuApi.renewedCookie(stored, (input['setCookie'] as List).cast<String>());
        expect(renewed, output['merged'], reason: '$name');
        final current = renewed ?? stored;
        if (output['after'] case final Map<String, dynamic> after) {
          expect(DouyuApi.sessionExpiry(current), DateTime.parse(after['sessionExpiry'] as String));
          expect(DouyuApi.sessionState(current, now: at).name, after['sessionState'], reason: '$name');
        }
        expect(
          DouyuApi.cookieHeader(account: current, did: DouyuApi.deviceId(current, 'process')),
          output['cookieHeader'],
          reason: '$name',
        );
      }
    });

    test('the token is acf_jwt_token, else acf_auth, else dy_auth; a blank one is absent', () {
      expect(DouyuApi.sessionToken('dy_auth=w; acf_auth=a; acf_jwt_token=j'), 'j');
      expect(DouyuApi.sessionToken('dy_auth=w; ACF_AUTH=a'), 'a');
      expect(DouyuApi.sessionToken('Cookie: dy_did=1; dy_auth=w'), 'w');
      expect(DouyuApi.sessionToken('dy_did=1; acf_did=1'), isNull);
      expect(DouyuApi.sessionToken('dy_auth='), isNull, reason: '3.x counted an emptied token as a login');
    });

    test('expiry: the JWT exp, else seven days after the save of a web cookie, else unknown (REG-DOUYU-022)', () {
      final jwt = 'acf_jwt_token=${_jwt({'exp': secondsFromNow(const Duration(days: 2))})}';
      expect(DouyuApi.sessionExpiry(jwt), _seconds(secondsFromNow(const Duration(days: 2))));
      expect(DouyuApi.sessionExpiry('dy_auth=w', savedAt: now), now.add(const Duration(days: 7)));
      expect(DouyuApi.sessionExpiry('dy_auth=w'), isNull, reason: 'no save time: not guessed');
      expect(DouyuApi.sessionExpiry('acf_auth=not.a.jwt'), isNull);
      expect(DouyuApi.jwtPayload('a.!!!.c'), isNull);
    });

    test('five states', () {
      final expired = 'dy_did=d; acf_jwt_token=${_jwt({'exp': secondsFromNow(const Duration(hours: -1))})}';
      expect(DouyuApi.sessionState('', now: now), DouyuSessionState.none);
      expect(DouyuApi.sessionState('dy_did=d', now: now), DouyuSessionState.guest);
      expect(DouyuApi.sessionState('dy_auth=w', now: now), DouyuSessionState.valid, reason: 'unknown end');
      expect(DouyuApi.sessionState(expired, now: now), DouyuSessionState.expired);
      expect(DouyuApi.sessionState(expired, now: now, ltp0: 'l', did: 'd'), DouyuSessionState.expiredRefreshable);
      final saved = now.subtract(const Duration(days: 8));
      expect(DouyuApi.sessionState('dy_auth=w', now: now, savedAt: saved), DouyuSessionState.expired);
    });

    test('renew without a token or within the last day; an unknown end is left alone', () {
      DateTime daysAgo(double days) => now.subtract(Duration(minutes: (days * 24 * 60).round()));
      expect(DouyuApi.shouldRenew('dy_did=d', now: now), isTrue);
      expect(DouyuApi.shouldRenew('dy_auth=w', now: now), isFalse);
      expect(DouyuApi.shouldRenew('dy_auth=w', now: now, savedAt: daysAgo(1)), isFalse);
      expect(DouyuApi.shouldRenew('dy_auth=w', now: now, savedAt: daysAgo(6.5)), isTrue);
      final h5 = 'acf_jwt_token=${_jwt({'exp': secondsFromNow(const Duration(days: 3))})}';
      expect(
        DouyuApi.shouldRenew(h5, now: now, savedAt: daysAgo(8)),
        isFalse,
        reason: 'the JWT wins',
      );
      final soon = 'acf_jwt_token=${_jwt({'exp': secondsFromNow(const Duration(hours: 5))})}';
      expect(DouyuApi.shouldRenew(soon, now: now), isTrue);
    });

    test('credentials: typed, else the cookie, else stored; the device id never comes from elsewhere', () {
      expect(DouyuApi.renewalCredentials('LTP0=c; dy_did=cd', typedLtp0: ' t ', storedLtp0: 's', storedDid: 'sd'), (
        ltp0: 't',
        did: 'cd',
      ));
      expect(DouyuApi.renewalCredentials('dy_auth=w', storedLtp0: 's', storedDid: 'sd'), (ltp0: 's', did: 'sd'));
      expect(DouyuApi.renewalCredentials('dy_auth=w', storedLtp0: 's'), (ltp0: 's', did: null));
      expect(DouyuApi.renewalCredentials('dy_auth=w', typedLtp0: '  ', typedDid: '  '), (ltp0: null, did: null));
    });

    test('a passport cookie has renewal fields and no session (REG-DOUYU-025)', () {
      expect(DouyuApi.isPassportCookie('LTP0=l; dy_did=d; acf_ssid=x'), isTrue);
      expect(DouyuApi.isPassportCookie('acf_stk=s'), isTrue);
      expect(DouyuApi.isPassportCookie('LTP0=l; dy_auth=w'), isFalse);
      expect(DouyuApi.isPassportCookie('dy_did=d'), isFalse);
    });

    test('merging keeps unmentioned fields, drops emptied ones, ignores attributes (REG-DOUYU-023)', () {
      final merged = DouyuApi.mergeSetCookie('Cookie: dy_did=d; LTP0=l; acf_auth=old; acf_stk=s', [
        'acf_auth=new; Path=/; Domain=.douyu.com; HttpOnly',
        'acf_stk=; Max-Age=0',
        'Path=/',
        '=novalue',
        'acf_uid=7; Expires=Wed, 01 Oct 2026 00:00:00 GMT',
      ]);
      expect(merged, 'dy_did=d; LTP0=l; acf_auth=new; acf_uid=7');
      expect(
        DouyuApi.renewedCookie('acf_auth=a', const []),
        isNull,
        reason: 'no Set-Cookie, no renewal (REG-DOUYU-024)',
      );
      expect(DouyuApi.renewedCookie('acf_auth=a', ['acf_auth=; Max-Age=0']), isNull, reason: 'a downgrade to guest');
    });
  });

  test('envelope errors are typed', () {
    expect(() => DouyuApi.categories('{"code":0,"data":{}}', status: 403), throwsA(isA<RiskControl>()));
    expect(() => DouyuApi.categories('', status: 503), throwsA(isA<NetworkFailure>()));
    expect(() => DouyuApi.categories('', status: 429), throwsA(isA<RateLimited>()));
    expect(() => DouyuApi.categories('<html>'), throwsA(isA<ApiChanged>()));
    expect(() => DouyuApi.categories('{"code":1,"msg":"x"}'), throwsA(isA<ApiChanged>()));
    expect(() => DouyuApi.categories('{"code":0,"data":{}}'), throwsA(isA<ApiChanged>()));
    expect(() => DouyuApi.roomList('{"error":0,"data":{"rl":{}}}', page: 1), throwsA(isA<ApiChanged>()));
    expect(() => DouyuApi.descriptor('{"error":0,"data":{}}', now: DateTime.utc(2026)), throwsA(isA<ApiChanged>()));
  });
}
