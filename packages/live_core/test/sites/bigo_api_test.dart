// Bigo Live parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/bigo/legacy_expected.dart from 3.x's BigoApi, BigoSite, BigoLink,
// BigoTokenCodec and BigoHlsProtection). Every intended difference is listed
// with its reason (M4.24 differences, M4.U items 24-1…24-7 and the unified
// rules of docs/specs/UPGRADES.md); everything else must match. The synthetic cases
// port 3.x's bigo_api_test.dart, bigo_media_test.dart and bigo_site_test.dart
// (link rules) and pin 3.x's checks where they still hold. The samples
// S03-studio-reused, S03-studio-offline and S03-studio-unknown were recorded
// for M4.U.24 and have no 3.x output.
import 'dart:convert';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('bigo', name);

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

/// Keys every card differs in from 3.x: the notice, said for viewers (the
/// unified rule on notices; M5.20 drops "chat pending" from it).
const Set<String> _cardChanges = {'notice'};

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {String reason = '', Set<String> changed = _cardChanges}) {
  final expected = _maps(legacy);
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(_projection(room), expected[index], changed: changed, reason: '$reason[$index]');
  }
}

List<LiveRoom> _cards() => BigoApi.directory(_sample('S01-list').body);

/// The live studio answer as recorded, and with its avatar made https (the
/// only form 3.x could read).
String _studioBody() => _sample('S03-studio-live').body;

String _avatarHttps() => _studioBody().replaceFirst('"avatar": "http://', '"avatar": "https://');

/// A studio answer: the recorded live one with [data] fields replaced
/// (null removes the field).
String _studio(Map<String, Object?> data, {Object? code = 0}) {
  final root = jsonDecode(_studioBody()) as Map<String, dynamic>;
  final fields = root['data'] as Map<String, dynamic>;
  for (final MapEntry(:key, :value) in data.entries) {
    if (value == null) {
      fields.remove(key);
    } else {
      fields[key] = value;
    }
  }
  root['code'] = code;
  return jsonEncode(root);
}

/// The gated fields of 3.x's `studio-login.json` fixture on the live answer.
const Map<String, Object?> _gate = {
  'needLogin': true,
  'alive': 0,
  'roomId': '0',
  'hls_src': '',
  'avatar': '',
  'nick_name': '',
};

/// A list answer: the recorded one with its first row's fields replaced.
Map<String, dynamic> _list() => jsonDecode(_sample('S01-list').body) as Map<String, dynamic>;

Map<String, dynamic> _row(Map<String, dynamic> list, [int index = 0]) =>
    ((list['data'] as Map<String, dynamic>)['data'] as List)[index] as Map<String, dynamic>;

List<int> _hex(String hex) => [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];

String _toHex(List<int> bytes) => [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();

final Uint8List _salt = Uint8List.fromList(const [0, 1, 2, 3, 4, 5, 6, 7]);
const _nonce = '0123456789abcdef0123456789abcdef';

void main() {
  group('S01 public list', () {
    test('the one category and its area match 3.x', () {
      final legacy = _result(_legacy('S01-list')['getCategores'])! as List;
      final categories = BigoApi.categories();
      expect(categories, hasLength(1));
      final expected = legacy.single as Map<String, dynamic>;
      expect(categories.single.id, expected['id']);
      expect(categories.single.name, expected['name']);
      final areas = _maps(expected['children']);
      expect(categories.single.children, hasLength(1));
      _expectParity(categories.single.children.single.toJson(), areas.single);
      expect(BigoApi.isArea(categories.single.children.single), isTrue);
      expect(BigoApi.isArea(const LiveArea(platform: 'bigo', areaType: 'public', areaId: '73')), isFalse);
      expect(BigoApi.isArea(const LiveArea(platform: 'bilibili', areaType: 'public', areaId: '72')), isFalse);
    });

    test('the 20 cards: ids, owners, topics or names, covers as avatars, viewers and headers match 3.x', () {
      final pages = _legacy('S01-list')['getDirectoryPage'] as Map<String, dynamic>;
      final cards = _cards();
      expect(cards, hasLength(20));
      for (final page in [1, 2, 3]) {
        final legacy = _result(pages['recommend:$page'])! as Map<String, dynamic>;
        final directory = BigoApi.directoryPage(cards, page: page);
        // notice: said for viewers (unified rule; M5.20 drops "chat pending").
        _expectRooms(directory.rooms, legacy['rooms'], reason: 'page $page');
        expect(directory.page, legacy['page']);
        expect(directory.hasMore, legacy['hasMore']);
      }
      final qashia = cards.firstWhere((card) => card.roomId == '414439909');
      expect(qashia.title, 'qashia', reason: 'an empty topic shows the name (3.x)');
      expect(qashia.avatar, qashia.cover, reason: 'the list has no avatar; 3.x used the cover');
      expect(qashia.effectiveOnlineViewers, '246');
      expect(qashia.data, isNull);
      expect(qashia.httpHeaders, BigoApi.headers);
      expect(qashia.notice, BigoApi.chatNotice);
      expect(qashia.notice, isNot(contains('user_count')), reason: 'no developer words');
    });

    test('added: every card has its start time (time_stamp) and restriction none (unified rules)', () {
      final rows = ((jsonDecode(_sample('S01-list').body) as Map)['data'] as Map)['data'] as List;
      final cards = _cards();
      for (final (index, card) in cards.indexed) {
        final seconds = (rows[index] as Map)['time_stamp'] as int;
        expect(card.startedAt, DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true), reason: card.roomId);
        expect(card.restriction, LiveRestriction.none, reason: 'is_locked 0');
        expect(card.toJson(), containsPair('restriction', 'none'));
        expect(card.startedAt!.isBefore(_sample('S01-list').capturedAt), isTrue);
      }
      final qashia = cards.firstWhere((card) => card.roomId == '414439909');
      expect(qashia.startedAt, DateTime.utc(2026, 9, 27, 16, 42, 31));
      expect(qashia.toJson()['startedAt'], '2026-09-27T16:42:31.000Z');
    });

    test('the start time: Unix seconds from 2000 to 2100; anything else drops only the start time', () {
      expect(BigoApi.startedAt(1790527351), DateTime.utc(2026, 9, 27, 16, 42, 31));
      for (final value in [null, 0, -1, 946684799, 4102444801, 1790527351000, 1790527351.5, '1790527351', true]) {
        expect(BigoApi.startedAt(value), isNull, reason: '$value');
      }
      final list = _list();
      _row(list)['time_stamp'] = 'soon';
      final cards = BigoApi.directory(jsonEncode(list));
      expect(cards, hasLength(20));
      expect(cards.first.startedAt, isNull);
      expect(cards[1].startedAt, isNotNull);
    });

    test("3.x's slices: a page or size below 1, a size over 100 or a page past the end give nothing", () {
      final legacy = _legacy('S01-list')['getRecommendRooms'] as Map<String, dynamic>;
      final cards = _cards();
      for (final (page, size) in [
        (1, 30),
        (1, 20),
        (2, 20),
        (1, 8),
        (3, 8),
        (4, 8),
        (1, 100),
        (1, 101),
        (0, 30),
        (1, 0),
      ]) {
        _expectRooms(
          BigoApi.slice(cards, page: page, pageSize: size),
          _result(legacy['page $page size $size']),
          reason: 'page $page size $size',
        );
      }
    });

    test('the snapshot filter: name or topic, any case, once per id (the S01 searches of 3.x)', () {
      final search = _legacy('S01-list')['searchRooms (pageSize 20)'] as Map<String, dynamic>;
      final cards = _cards();
      for (final keyword in ['Pk', 'pk CHALLENGE', 'qashia', 'MR', '赚钱', 'nickname words']) {
        _expectRooms(BigoApi.filter(cards, keyword), _result(search['$keyword page 1']), reason: keyword);
      }
      final twice = [
        LiveRoom(platform: 'bigo', roomId: 'Fixture_A', title: 'Pk one'),
        LiveRoom(platform: 'bigo', roomId: 'fixture_a', nick: 'pk two'),
      ];
      expect(BigoApi.filter(twice, 'PK').map((room) => room.roomId), ['Fixture_A']);
    });

    test('24-2: a locked room stays listed, live and marked password (3.x listed it unmarked); missing viewers '
        'stay unknown (3.x)', () {
      final list = _list();
      _row(list)
        ..['is_locked'] = 1
        ..['user_count'] = null;
      final card = BigoApi.directory(jsonEncode(list)).first;
      expect(card.roomId, '858683693');
      expect(card.watching, '');
      expect(card.onlineViewers, '');
      expect(card.isLiveNow, isTrue);
      expect(card.restriction, LiveRestriction.password);
      expect(card.isRestricted, isTrue);
      expect(card.followGroup, FollowGroup.live, reason: 'a restricted live room is live (M2.1)');
      expect(card.toJson(), containsPair('restriction', 'password'));
    });

    test('a null cover is no image; 24-6: a cover that is not text drops only its row (3.x: the whole list)', () {
      final list = _list();
      _row(list)['cover_m'] = null;
      final card = BigoApi.directory(jsonEncode(list)).first;
      expect(card.cover, isEmpty);
      expect(card.avatar, isEmpty);
      _row(list)['cover_m'] = 42;
      final cards = BigoApi.directory(jsonEncode(list));
      expect(cards.map((card) => card.roomId), _cards().skip(1).map((card) => card.roomId));
    });

    for (final broken in ['wrong-wrapper', 'bad-resCode', 'missing-resCode', 'code', 'too-many']) {
      test('a list with $broken still fails as a whole (3.x): the envelope, not a row', () {
        final list = _list();
        final rows = (list['data'] as Map<String, dynamic>)['data'] as List;
        final row = _row(list);
        switch (broken) {
          case 'wrong-wrapper':
            list['data'] = <Object?>[];
          case 'bad-resCode':
            (list['data'] as Map<String, dynamic>)['resCode'] = '123';
          case 'missing-resCode':
            (list['data'] as Map<String, dynamic>).remove('resCode');
          case 'code':
            list['code'] = 1;
          case 'too-many':
            rows.addAll(List.filled(500, row));
        }
        expect(() => BigoApi.directory(jsonEncode(list)), throwsA(isA<ApiChanged>()));
      });
    }

    for (final broken in [
      'fractional-broadcast',
      'negative-viewers',
      'string-lock',
      'bad-id',
      'no-owner',
      'topic-number',
      'not-an-object',
      'bad-flag',
      'no-sid',
    ]) {
      test('24-6: a row with $broken is left out on its own (3.x failed the whole list)', () {
        final list = _list();
        final rows = (list['data'] as Map<String, dynamic>)['data'] as List;
        final row = _row(list, 3);
        switch (broken) {
          case 'fractional-broadcast':
            row['room_id'] = 1.5;
          case 'negative-viewers':
            row['user_count'] = -1;
          case 'string-lock':
            row['is_locked'] = '0';
          case 'bad-id':
            row['bigo_id'] = '../x';
          case 'no-owner':
            row.remove('owner');
          case 'topic-number':
            row['room_topic'] = 7;
          case 'not-an-object':
            rows[3] = 'row';
          case 'bad-flag':
            row['room_flag'] = -2;
          case 'no-sid':
            row.remove('sid');
        }
        final expected = [
          for (final (index, card) in _cards().indexed)
            if (index != 3) card.roomId,
        ];
        expect(BigoApi.directory(jsonEncode(list)).map((card) => card.roomId), expected);
      });
    }

    test('24-6: a repeated id or owner leaves out the later row (3.x failed the whole list)', () {
      final list = _list();
      final rows = (list['data'] as Map<String, dynamic>)['data'] as List;
      final row = _row(list);
      rows
        ..add({...row, 'owner': 1})
        ..add({...row, 'bigo_id': 'another'})
        ..add({..._row(list, 1), 'bigo_id': 'fresh_one', 'owner': 2});
      final cards = BigoApi.directory(jsonEncode(list));
      expect(cards, hasLength(21));
      expect(cards.first.roomId, '858683693');
      expect(cards.last.roomId, 'fresh_one');
      expect(cards.where((card) => card.roomId == '858683693'), hasLength(1));
      expect(cards.where((card) => card.roomId == 'another'), isEmpty, reason: 'the owner of the first row');
    });

    test('rows none of which can be read are ApiChanged, never an empty list; no rows is an empty list', () {
      final list = _list();
      for (final row in (list['data'] as Map<String, dynamic>)['data'] as List) {
        (row as Map)['bigo_id'] = '../x';
      }
      expect(() => BigoApi.directory(jsonEncode(list)), throwsA(isA<ApiChanged>()));
      (list['data'] as Map<String, dynamic>)['data'] = <Object?>[];
      expect(BigoApi.directory(jsonEncode(list)), isEmpty);
    });
  });

  group('S02 web token', () {
    test('the server time and the token from the recorded JSONP answers (3.x)', () {
      final time = _sample('S02-time-live');
      final status = _sample('S02-status-live');
      final legacyTime = _legacy('S02-time-live')['jsonp_purelive_t'] as Map<String, dynamic>;
      final legacyToken = _legacy('S02-status-live')['jsonp_purelive_s'] as Map<String, dynamic>;
      expect(BigoApi.serverTime(time.body, callback: 'jsonp_purelive_t', status: time.status), legacyTime['time']);
      expect(BigoApi.token(status.body, callback: 'jsonp_purelive_s', status: status.status), legacyToken['token']);
    });

    test("an answer for another callback is ApiChanged (3.x's exact check)", () {
      expect(_legacy('S02-time-live')['jsonp_other'], containsPair('message', 'Bigo schema'));
      expect(
        () => BigoApi.serverTime(_sample('S02-time-live').body, callback: 'jsonp_other'),
        throwsA(isA<ApiChanged>()),
      );
      for (final body in [
        'jsonp_t({"code":0,"time":"1"})',
        'jsonp_t({"code":"0","time":"1"});',
        'jsonp_t({"code":0,"time":1});',
        'jsonp_t({"code":0,"time":"12a"});',
        'jsonp_t({"code":0,"time":"123456789012345678901"});',
        'jsonp_t([]);',
        '<html>',
      ]) {
        expect(() => BigoApi.serverTime(body, callback: 'jsonp_t'), throwsA(isA<ApiChanged>()), reason: body);
      }
      expect(BigoApi.serverTime(' jsonp_t({"code":7,"time":"12"}); ', callback: 'jsonp_t'), '12');
      for (final token in ['', ' x', 'a b', 'x' * 4097, 7]) {
        expect(
          () => BigoApi.token('jsonp_s(${jsonEncode({'token': token})});', callback: 'jsonp_s'),
          throwsA(isA<ApiChanged>()),
          reason: '$token',
        );
      }
    });

    test('the callback name and its check (3.x)', () {
      final name = BigoApi.callbackName(DateTime.fromMicrosecondsSinceEpoch(1790000000123456));
      expect(name, 'jsonpcallback_1790000000123_123456');
      expect(BigoApi.isCallbackName(name), isTrue);
      expect(BigoApi.isCallbackName('jsonp_purelive_t'), isTrue);
      expect(BigoApi.isCallbackName('callback_1'), isFalse);
      expect(BigoApi.isCallbackName('jsonp'), isFalse);
      expect(BigoApi.isCallbackName('jsonp-x'), isFalse);
    });

    test("the request data is 3.x's codec: OpenSSL Salted__ AES-256-CBC with EVP md5 keys", () {
      final legacy = _legacy('S02-status-live');
      final vectors = legacy['tokenData'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in vectors.entries) {
        expect(
          BigoApi.tokenData(key, salt: _salt, nonce: _nonce),
          value,
          reason: key,
        );
      }
      expect(
        BigoApi.tokenData('1790000000', salt: const [1, 2, 3, 4, 5, 6, 7, 8], nonce: _nonce),
        legacy['tokenData(1790000000, salt 1..8)'],
      );
      // 3.x's own test vector (bigo_media_test.dart).
      expect(
        BigoApi.tokenData('1723456789', salt: _salt, nonce: _nonce),
        'U2FsdGVkX18AAQIDBAUGBw9CExflNpp/+hw4FEvQ48pkY9f2hYxzYBNOjHbCB45L1kMM+njoY+ywzq8/nIukZdvMK///nfADHW0eTrVT7LFdOB'
        'DiydMHD1bQXb8LIIH6FSRtElvqM7EhdCvLpZW9RzGf9qNU4yDT2LciUoRF/Dz6pDiEIxTYPaEri+1At/i8',
      );
      final random = base64Decode(BigoApi.tokenData('1'));
      expect(random.sublist(0, 8), ascii.encode('Salted__'));
      expect((random.length - 16) % 16, 0);
    });

    test('bad token arguments are caller errors (3.x: FormatException)', () {
      expect(
        (_legacy('S02-status-live')['tokenData errors'] as Map).values.map((error) => (error as Map)['throws']),
        everyElement('FormatException'),
      );
      expect(() => BigoApi.tokenData('12a', salt: _salt, nonce: _nonce), throwsArgumentError);
      expect(() => BigoApi.tokenData('1', salt: Uint8List(7), nonce: _nonce), throwsArgumentError);
      expect(() => BigoApi.tokenData('1', salt: _salt, nonce: 'XYZ'), throwsArgumentError);
    });
  });

  group('S03 studio', () {
    Map<String, dynamic> legacyCalls(String key) =>
        ((_legacy('S03-studio-live')[key] as Map<String, dynamic>)['414439909']) as Map<String, dynamic>;

    test('3.x failed the recorded live room on its http avatar; it is read now, the avatar kept as given', () {
      for (final call in legacyCalls('recorded').values) {
        expect(_result(call), containsPair('message', 'Bigo schema'));
      }
      final studio = BigoApi.studio(_studioBody(), requestedSiteId: '414439909');
      expect(studio.avatar, startsWith('http://esx.bigo.sg/'));
      final https = BigoApi.studio(_avatarHttps(), requestedSiteId: '414439909');
      expect(studio.avatar, https.avatar.replaceFirst('https://', 'http://'));
    });

    test('the studio as 3.x read it (the avatar made https)', () {
      final legacy = _result(legacyCalls('avatarHttps')['studioRoom'])! as Map<String, dynamic>;
      final studio = BigoApi.studio(_avatarHttps(), requestedSiteId: '414439909');
      expect({
        'requestedSiteId': studio.requestedSiteId,
        'canonicalSiteId': studio.siteId,
        'ownerId': studio.ownerId,
        'access': studio.access.name,
        'reportedAlive': studio.alive,
        'roomStatus': studio.roomStatus,
        'roomType': studio.roomType,
        'roomId': studio.broadcastId,
        'nickname': studio.nickname,
        'title': studio.title,
        'category': studio.category,
        'avatar': studio.avatar,
        'hls': studio.hls.toString(),
      }, legacy);
      expect(studio.liveStatus, LiveStatus.live);
    });

    test("the room: every field as 3.x's, the id the site's spelling; the cover is the snapshot (24-1)", () {
      final calls = legacyCalls('avatarHttps');
      for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        final legacy = _result(calls[depth])! as Map<String, dynamic>;
        final https = BigoApi.room(BigoApi.studio(_avatarHttps(), requestedSiteId: '414439909'));
        // cover: the snapshot (24-1); notice: said for viewers (unified rule; M5.20 drops "chat pending").
        _expectParity(_projection(https), legacy, changed: {'cover', 'notice'}, reason: depth);
        expect(https.avatar, legacy['avatar'], reason: 'the avatar stays the avatar');
        expect(legacy['cover'], legacy['avatar'], reason: '3.x used the avatar as cover');
        // avatar: the recorded http avatar, which 3.x rejected.
        final recorded = BigoApi.room(BigoApi.studio(_studioBody(), requestedSiteId: '414439909'));
        _expectParity(_projection(recorded), legacy, changed: {'avatar', 'cover', 'notice'}, reason: depth);
      }
      final room = BigoApi.room(BigoApi.studio(_studioBody(), requestedSiteId: '414439909'));
      expect(room.roomId, 'qashia305', reason: '3.x: clientBigoId, whatever id was asked');
      expect(room.link, 'https://www.bigo.tv/qashia305');
      expect(room.title, 'qashia');
      expect(room.area, 'Bigo Live');
      expect(room.cover, startsWith('http://esx.bigo.sg/na/live_pic/luy/1wgYlS00y4dZTiM2B5Tdq_2.jpg?type=20'));
      expect(room.avatar, startsWith('http://esx.bigo.sg/na/live_pic/luy/1wgYlS00y4dZTiM2B5Tdq_4.jpg?type=20'));
      expect(room.notice, BigoApi.chatNotice);
      expect(room.restriction, LiveRestriction.none, reason: 'added: a complete live answer with a playlist');
      expect(room.startedAt, isNull, reason: 'the studio has no start time');
      expect(room.effectiveAudienceMetricType, AudienceMetricType.unknown);
      expect(room.audienceValue(preferRealOnline: false, platformEnabled: false), isEmpty);
      final data = room.data! as BigoRoomData;
      expect(data.siteId, 'qashia305');
      expect(data.ownerId, 409742853);
      expect(data.broadcastId, '6812312308570332324');
      expect(data.access, BigoAccess.public);
      expect(data.alive, isTrue);
      expect(data.hasStream, isTrue);
      expect(data.complete, isTrue);
      expect(data.restriction, LiveRestriction.none);
      expect(data.streamError, isNull);
      expect(jsonEncode(room.toJson()), isNot(contains('cubetecn')), reason: 'no media address stored (REG-LEASE-017)');
    });

    test(
      '24-1: without a snapshot the cover is the avatar (3.x); the snapshot is taken as leniently as the avatar',
      () {
        for (final snapshot in <Object?>[null, '', 'ftp://a.example/x.jpg', 42]) {
          final room = BigoApi.room(BigoApi.studio(_studio({'snapshot': snapshot}), requestedSiteId: 'x'));
          expect(room.cover, room.avatar, reason: '$snapshot');
          expect(room.cover, isNotEmpty);
        }
        final https = BigoApi.room(
          BigoApi.studio(_studio({'snapshot': 'https://a.example/s.jpg'}), requestedSiteId: 'x'),
        );
        expect(https.cover, 'https://a.example/s.jpg');
        expect(https.avatar, isNot(https.cover));
      },
    );

    test('S03-studio-offline: the snapshot is the last broadcast; no name, avatar or title (left empty, X-2)', () {
      final studio = BigoApi.studio(_sample('S03-studio-offline').body, requestedSiteId: 'qashia305');
      expect(studio.access, BigoAccess.public);
      expect(studio.complete, isTrue);
      expect(studio.liveStatus, LiveStatus.offline);
      expect(studio.restriction, isNull, reason: 'offline: not filled (M2.1)');
      final room = BigoApi.room(studio);
      expect(room.roomId, 'qashia305');
      expect(room.nick, isEmpty);
      expect(room.title, isEmpty);
      expect(room.avatar, isEmpty);
      expect(room.cover, startsWith('http://esx.bigo.sg/na/live_pic/luy/1wgYlS00y4dZTiM2B5Tdq_2.jpg'));
      expect(room.isExplicitlyOfflineNow, isTrue);
      expect(room.restriction, isNull);
      final stored = BigoApi.room(BigoApi.studio(_studioBody(), requestedSiteId: '414439909'));
      final merged = stored.mergeFrom(room);
      expect(merged.nick, 'qashia', reason: 'the empty name keeps the stored one');
      expect(merged.title, 'qashia');
      expect(merged.avatar, stored.avatar);
      expect(merged.cover, room.cover, reason: 'the last snapshot');
      expect(merged.isLiveNow, isFalse);
      expect(merged.restriction, isNull, reason: 'the broadcast ended (M2.1)');
      expect((room.data! as BigoRoomData).streamError, isA<StreamUnavailable>());
    });

    test('24-4, S03-studio-reused: a used token gives the state and names, no playlist and no password flag', () {
      final studio = BigoApi.studio(_sample('S03-studio-reused').body, requestedSiteId: '1005503375');
      expect(studio.complete, isFalse);
      expect(studio.password, isNull);
      expect(studio.hls, isNull);
      expect(studio.access, BigoAccess.public);
      expect(studio.liveStatus, LiveStatus.live, reason: 'alive 1');
      expect(studio.restriction, isNull, reason: 'the lock is not said');
      expect(studio.nickname, 'Lyrics');
      final room = BigoApi.room(studio);
      expect(room.isLiveNow, isTrue);
      expect(room.restriction, isNull);
      expect(room.cover, startsWith('https://esx.bigo.sg/as/live-enhancer/ls3/01vNrpWC8iiA.jpg'));
      final data = room.data! as BigoRoomData;
      expect(data.complete, isFalse);
      expect(data.hasStream, isFalse);
      expect(data.streamError, isNull, reason: 'the input asks again; a used token never has the playlist');
      expect(data.broadcastId, '7367135243595402902');
      // A used token of a paid show still says it is paid.
      final paid = BigoApi.studio(
        _sample('S03-studio-reused').body.replaceFirst('"isPaidShow": ""', '"isPaidShow": "1"'),
        requestedSiteId: '1005503375',
      );
      expect(paid.restriction, LiveRestriction.paid);
      expect(paid.liveStatus, LiveStatus.live);
    });

    test('S03-studio-unknown: an id the site does not know is NotFound (3.x failed it as schema)', () {
      expect(
        () => BigoApi.studio(_sample('S03-studio-unknown').body, requestedSiteId: 'zzqxnomatch'),
        throwsA(isA<NotFound>()),
      );
      expect(() => BigoApi.studio(_studio({'uid': null}), requestedSiteId: 'x'), throwsA(isA<ApiChanged>()));
      expect(() => BigoApi.studio(_studio({'clientBigoId': null}), requestedSiteId: 'x'), throwsA(isA<ApiChanged>()));
    });

    test("a login gate completed by a later answer: the gate stays, the state is the later answer's (24-4)", () {
      final later = BigoApi.studio(_sample('S03-studio-reused').body, requestedSiteId: '1005503375');
      final gated = later.gated();
      expect(gated.access, BigoAccess.loginRequired);
      expect(gated.liveStatus, LiveStatus.live);
      expect(gated.restriction, LiveRestriction.needsLogin);
      expect(gated.complete, isFalse);
      final room = BigoApi.room(gated);
      expect(room.isLiveNow, isTrue);
      expect(room.followGroup, FollowGroup.live);
      expect(room.notice, BigoApi.loginNotice);
      expect(room.nick, 'Lyrics');
      expect((room.data! as BigoRoomData).streamError, isA<NeedsLogin>());
      final offline = BigoApi.studio(_sample('S03-studio-offline').body, requestedSiteId: 'qashia305').gated();
      expect(offline.liveStatus, LiveStatus.offline);
    });

    test("S03 without a token: needLogin, as 3.x read it; the room's state stays unknown", () {
      final legacy = _legacy('S03-studio-notoken');
      final body = _sample('S03-studio-notoken').body;
      final studio = BigoApi.studio(body, requestedSiteId: '414439909');
      expect({
        'requestedSiteId': studio.requestedSiteId,
        'canonicalSiteId': studio.siteId,
        'ownerId': studio.ownerId,
        'access': studio.access.name,
        'reportedAlive': studio.alive,
        'roomStatus': studio.roomStatus,
        'roomType': studio.roomType,
        'roomId': studio.broadcastId,
        'nickname': studio.nickname,
        'title': studio.title,
        'category': studio.category,
        'avatar': studio.avatar.isEmpty ? null : studio.avatar,
        'hls': studio.hls?.toString(),
      }, legacy['parseStudioRoom']);
      final calls = (legacy['asTokenAnswer'] as Map<String, dynamic>)['414439909'] as Map<String, dynamic>;
      final room = BigoApi.room(studio);
      for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        // cover: the snapshot (24-1; 3.x's cover was the empty avatar);
        // notice: said for viewers (unified rule; M5.20 drops "chat pending").
        _expectParity(
          _projection(room),
          _result(calls[depth])! as Map<String, dynamic>,
          changed: {'cover', 'notice'},
          reason: depth,
        );
        expect((_result(calls[depth])! as Map)['cover'] ?? '', isEmpty);
      }
      expect(room.effectiveLiveStatus, LiveStatus.unknown);
      expect(room.notice, BigoApi.loginNotice);
      expect(room.restriction, LiveRestriction.needsLogin, reason: 'added');
      expect(room.cover, startsWith('http://esx.bigo.sg/'));
      expect((room.data! as BigoRoomData).streamError, isA<NeedsLogin>());
    });

    test('states and restrictions: a restricted live room is live and marked (24-2, M2.1; 3.x: unknown)', () {
      (LiveStatus, LiveRestriction?) state(Map<String, Object?> data) {
        final studio = BigoApi.studio(_studio(data), requestedSiteId: 'x');
        expect(BigoApi.room(studio).restriction, studio.restriction);
        return (studio.liveStatus, studio.restriction);
      }

      expect(state(const {}), (LiveStatus.live, LiveRestriction.none));
      expect(state(const {'alive': 0, 'hls_src': ''}), (LiveStatus.offline, null));
      expect(state(const {'hls_src': ''}), (
        LiveStatus.live,
        LiveRestriction.unplayable,
      ), reason: 'live without a playlist (3.x: unknown)');
      expect(state(_gate), (LiveStatus.unknown, LiveRestriction.needsLogin), reason: 'the gate hides alive');
      expect(state(const {'passRoom': true, 'hls_src': ''}), (LiveStatus.live, LiveRestriction.password));
      expect(state(const {'isPaidShow': '1', 'hls_src': ''}), (LiveStatus.live, LiveRestriction.paid));
      expect(state(const {'passRoom': true, 'isPaidShow': '1', 'hls_src': ''}), (
        LiveStatus.live,
        LiveRestriction.password,
      ));
      expect(state(const {'passRoom': true, 'alive': 0, 'hls_src': ''}), (
        LiveStatus.unknown,
        LiveRestriction.password,
      ), reason: "a restricted room's alive 0 is no offline observation (3.x)");
      expect(state(const {'passRoom': null, 'hls_src': ''}), (LiveStatus.live, null), reason: 'a used token');
      expect(state(const {'passRoom': null, 'alive': 0, 'hls_src': ''}), (LiveStatus.offline, null));
      final room = BigoApi.room(BigoApi.studio(_studio(const {'passRoom': true, 'hls_src': ''}), requestedSiteId: 'x'));
      expect(room.notice, BigoApi.restrictedNotice);
      expect(room.followGroup, FollowGroup.live);
      expect(room.isPlayableNow, isTrue, reason: 'playback explains the restriction');
    });

    test('the login gate comes before password and paid flags and hides alive (3.x)', () {
      final studio = BigoApi.studio(
        _studio({..._gate, 'alive': 1, 'passRoom': true, 'isPaidShow': '1'}),
        requestedSiteId: 'x',
      );
      expect(studio.access, BigoAccess.loginRequired);
      expect(studio.alive, isNull);
      for (final (gate, name) in [
        ({'passRoom': true}, 'password room'),
        ({'isPaidShow': '1'}, 'paid show'),
      ]) {
        final restricted = BigoApi.studio(_studio({...gate, 'hls_src': ''}), requestedSiteId: 'x');
        expect(restricted.access, BigoAccess.restricted, reason: '$gate');
        expect(restricted.alive, isTrue, reason: 'a restricted live room is live (M2.1; 3.x hid alive)');
        expect(
          restricted.data.streamError,
          isA<StreamUnavailable>().having((error) => '$error', 'reason', contains(name)),
          reason: 'playback says why',
        );
        final notAlive = BigoApi.studio(_studio({...gate, 'alive': 0, 'hls_src': ''}), requestedSiteId: 'x');
        expect(notAlive.alive, isNull, reason: 'never shown as offline (3.x)');
      }
      final offline = BigoApi.studio(_studio(const {'alive': 0, 'hls_src': ''}), requestedSiteId: 'x');
      expect(offline.alive, isFalse);
      expect(offline.data.streamError, isA<StreamUnavailable>());
      final bare = BigoApi.studio(_studio(const {'hls_src': ''}), requestedSiteId: 'x');
      expect(bare.data.streamError, isA<StreamUnavailable>());
    });

    for (final field in ['needLogin', 'isPaidShow', 'alive', 'clientBigoId', 'roomStatus', 'roomType', 'uid']) {
      test('a missing $field is ApiChanged, never taken as false or offline (3.x)', () {
        expect(() => BigoApi.studio(_studio({field: null}), requestedSiteId: 'x'), throwsA(isA<ApiChanged>()));
      });
    }

    test('irregular studio answers are ApiChanged (3.x)', () {
      for (final data in <Map<String, Object?>>[
        {'alive': 2},
        {'alive': true},
        {'isPaidShow': '2'},
        {'isPaidShow': 0},
        {'needLogin': 'false'},
        {'uid': 0},
        {'uid': '409742853'},
        {'clientBigoId': '../x'},
        {'roomStatus': -1},
        {'roomType': 0},
        {'roomId': '012'},
        {'roomId': 681231230857},
        {'nick_name': 7},
        {'roomTopic': false},
        {'hls_src': 'http://h.example/list.m3u8'},
        {'hls_src': 'https://h.example/list.flv'},
        {'hls_src': 'https://user@h.example/list.m3u8'},
        {'hls_src': 'https://h.example/list.m3u8#x'},
        {'hls_src': 7},
        {..._gate, 'hls_src': 'https://h.example/list.m3u8'},
        {'alive': 0},
        {'passRoom': true},
        {'passRoom': 'false'},
        {'passRoom': 0},
      ]) {
        expect(() => BigoApi.studio(_studio(data), requestedSiteId: 'x'), throwsA(isA<ApiChanged>()), reason: '$data');
      }
      for (final code in [404, 700001, 810021, 810022, '0']) {
        expect(
          () => BigoApi.studio(_studio(const {}, code: code), requestedSiteId: 'x'),
          throwsA(isA<ApiChanged>()),
          reason: '$code',
        );
      }
      expect(() => BigoApi.studio('{"code":0,"data":null}', requestedSiteId: 'x'), throwsA(isA<ApiChanged>()));
      expect(() => BigoApi.studio('[]', requestedSiteId: 'x'), throwsA(isA<ApiChanged>()));
      expect(() => BigoApi.studio('private invalid body', requestedSiteId: 'x'), throwsA(isA<ApiChanged>()));
    });

    test('an avatar or snapshot never fails the room: http(s) kept, anything else left out', () {
      String avatar(Object? value) => BigoApi.studio(_studio({'avatar': value}), requestedSiteId: 'x').avatar;
      String snapshot(Object? value) => BigoApi.studio(_studio({'snapshot': value}), requestedSiteId: 'x').snapshot;
      expect(avatar('https://a.example/x.jpg'), 'https://a.example/x.jpg');
      expect(avatar('http://a.example/x.jpg'), 'http://a.example/x.jpg');
      expect(snapshot('http://a.example/s.jpg'), 'http://a.example/s.jpg');
      for (final value in [
        'ftp://a.example/x',
        '//a.example/x.jpg',
        'x',
        42,
        'https://u@a.example/x',
        'https://a.example/#x',
      ]) {
        expect(avatar(value), isEmpty, reason: '$value');
        expect(snapshot(value), isEmpty, reason: '$value');
      }
      final studio = BigoApi.studio(
        _studio(const {'gameTitle': 'Music', 'roomTopic': 'Fixture live'}),
        requestedSiteId: 'x',
      );
      final room = BigoApi.room(studio);
      expect(room.title, 'Fixture live');
      expect(room.area, 'Music');
    });

    test('statuses as 3.x mapped them; a body over 1 MiB is ApiChanged', () {
      for (final (status, kind) in [
        (400, NetworkFailure),
        (302, NetworkFailure),
        (401, RiskControl),
        (403, RiskControl),
        (404, NotFound),
        (429, RateLimited),
        (503, NetworkFailure),
      ]) {
        expect(
          () => BigoApi.studio(_studioBody(), requestedSiteId: 'x', status: status),
          throwsA(isA<SiteError>().having((error) => error.runtimeType, 'kind', kind)),
          reason: '$status',
        );
      }
      final large = '{"code":0,"data":{"x":"${'一' * (BigoApi.responseLimit ~/ 3)}"}}';
      expect(() => BigoApi.directory(large), throwsA(isA<ApiChanged>()));
    });

    test('M5.20: the chat arguments of a studio the website opens its chat for', () {
      BigoDanmakuArgs? args(Map<String, Object?> data) =>
          BigoApi.danmakuArgs(BigoApi.studio(_studio(data), requestedSiteId: '414439909'));
      final live = args(const {})!;
      expect((live.siteId, live.ownerId, live.roomId), ('qashia305', 409742853, '6812312308570332324'));
      expect('$live', 'BigoDanmakuArgs(qashia305, 409742853, 6812312308570332324)');
      expect(args(const {'isPaidShow': '1', 'hls_src': ''}), isNotNull, reason: "the page opens a paid show's chat");
      expect(args(const {'passRoom': null, 'hls_src': ''}), isNotNull, reason: "a used token's answer");
      for (final (label, data) in <(String, Map<String, Object?>)>[
        ('offline', {'alive': 0, 'hls_src': ''}),
        ('login gate', _gate),
        ('login gate while live', {'needLogin': true, 'hls_src': ''}),
        ('password', {'passRoom': true, 'hls_src': ''}),
        ('roomType 1', {'roomType': '1'}),
        ('no room id', {'roomId': '0'}),
        ('empty room id', {'roomId': ''}),
      ]) {
        expect(args(data), isNull, reason: label);
      }
      final studio = BigoApi.studio(_studioBody(), requestedSiteId: '414439909');
      expect(BigoApi.room(studio).danmakuData, isNull, reason: 'a room carries them only when asked (entries)');
      final entry = BigoApi.room(studio, danmaku: true);
      expect(entry.danmakuData, isA<BigoDanmakuArgs>());
      expect(entry.toJson().keys, isNot(contains('danmakuData')), reason: 'never stored');
      expect(
        BigoApi.room(
          BigoApi.studio(_studio(const {'alive': 0, 'hls_src': ''}), requestedSiteId: 'x'),
          danmaku: true,
        ).danmakuData,
        isNull,
      );
    });
  });

  group('streams', () {
    test('the playlist line: 3.x headers, HLS, the CDN host as line id, no lease', () {
      final studio = BigoApi.studio(_studioBody(), requestedSiteId: '414439909');
      final line = BigoApi.line(studio.hls!);
      expect(line.url, 'https://47a788a9.cubetecn.com:1451/list_3453520891_2472221860_0.m3u8');
      expect(line.headers, {
        'origin': 'https://www.bigo.tv',
        'referer': 'https://www.bigo.tv/',
        'user-agent': 'Mozilla/5.0',
      });
      expect(line.format, StreamFormat.hls);
      expect(line.lineId, '47a788a9.cubetecn.com');
      expect(line.lease, isNull);
    });

    test('the recipe: the Bigo id, 3.x identity, no URL', () {
      final recipe = BigoInputRecipe('qashia305');
      expect(recipe.identity, 'bigo:qashia305:live');
      expect(recipe, BigoInputRecipe('qashia305'));
      expect(recipe, isNot(BigoInputRecipe('414439909')));
      expect(() => BigoInputRecipe('../x'), throwsArgumentError);
      final resolution = LivePlayUrlResolution.owned(input: recipe, appliedQualityData: BigoApi.qualityId);
      expect(resolution.urls, isEmpty);
      expect(resolution.lineCount, 1);
    });

    test("the one quality is 3.x's", () {
      final calls = (_legacy('S03-studio-live')['avatarHttps'] as Map<String, dynamic>)['414439909'] as Map;
      final legacy = _result(calls['getRoomDetail → getPlayQualites']);
      expect([
        {
          'quality': BigoApi.quality.quality,
          'id': BigoApi.quality.id,
          'sort': BigoApi.quality.sort,
          'data': BigoApi.quality.data,
        },
      ], legacy);
    });
  });

  group('S04 HLS protection', () {
    test("today's tag VERSION=1,SEED=… gives the seed (3.x found none and left the segments scrambled)", () {
      final legacy = _legacy('S04-playlist');
      expect(legacy['seedFromManifest'], isNull);
      expect(BigoHlsProtection.seed(_sample('S04-playlist').body), 807018584);
      expect(
        BigoHlsProtection.seed('#EXTM3U\n#EXT-X-BIGO-WEB-PROTECTION:SEED=807018584\n'),
        legacy['seedFromManifest(3.x tag)'],
      );
      expect(BigoHlsProtection.seed('#ext-x-bigo-web-protection:seed=12, VERSION=1\n'), 12);
      expect(BigoHlsProtection.seed('#EXTM3U\n#EXT-X-VERSION:3\n'), isNull);
    });

    test('a seed out of range or a tag without one is a FormatException', () {
      expect(_legacy('S04-playlist')['seedFromManifest(too large)'], containsPair('throws', 'FormatException'));
      for (final playlist in [
        '#EXT-X-BIGO-WEB-PROTECTION:SEED=4294967296\n',
        '#EXT-X-BIGO-WEB-PROTECTION:SEED=999999999999999999999\n',
        '#EXT-X-BIGO-WEB-PROTECTION:VERSION=1\n',
        '#EXT-X-BIGO-WEB-PROTECTION:SEED=12x\n',
      ]) {
        expect(() => BigoHlsProtection.seed(playlist), throwsFormatException, reason: playlist);
      }
    });

    test("the transform is 3.x's: a recorded scrambled packet turns back into the PAT", () {
      final legacy = _legacy('S04-playlist');
      final recorded = Uint8List(376)..setAll(0, _hex('3853197ab543cc34d1eb3b1446042e58'));
      final plain = BigoHlsProtection.transform(recorded, 2020359253);
      expect(_toHex(plain.sublist(0, 16)), legacy['transformSegment(recorded packet, 2020359253)']);
      expect(plain[0], 0x47);
      final counting = Uint8List.fromList(List.generate(188 * 3, (index) => index & 0xff));
      final scrambled = BigoHlsProtection.transform(counting, 807018584);
      expect(_toHex(scrambled), legacy['transformSegment(counting, 807018584)']);
      expect(BigoHlsProtection.transform(scrambled, 807018584), counting, reason: 'applying twice restores');
      expect(scrambled.sublist(BigoHlsProtection.prefixBytes), counting.sublist(BigoHlsProtection.prefixBytes));
    });

    test("3.x's browser vector; a short segment or a bad seed is a FormatException", () {
      const seed = 1234567890;
      final plain = Uint8List(376)
        ..[0] = 0x47
        ..[188] = 0x47;
      final scrambled = BigoHlsProtection.transform(plain, seed);
      expect(scrambled.sublist(0, 16), [234, 135, 48, 195, 159, 46, 166, 121, 202, 86, 133, 106, 116, 255, 43, 34]);
      expect(scrambled.sublist(188, 204), [193, 228, 20, 96, 237, 165, 183, 210, 218, 210, 88, 211, 198, 10, 131, 204]);
      expect(BigoHlsProtection.transform(scrambled, seed), plain);
      final legacy = _legacy('S04-playlist');
      expect(legacy['transformSegment(375 bytes)'], containsPair('throws', 'FormatException'));
      expect(() => BigoHlsProtection.transform(Uint8List(375), 1), throwsFormatException);
      expect(legacy['transformSegment(seed 2^32)'], containsPair('throws', 'FormatException'));
      expect(() => BigoHlsProtection.transform(Uint8List(376), 4294967296), throwsFormatException);
      expect(() => BigoHlsProtection.transform(Uint8List(376), -1), throwsFormatException);
    });
  });

  group('links', () {
    test("room links, reserved pages and malformed links as 3.x's BigoLink.parse; 24-7: fragments and subdomains", () {
      final legacy = _legacy('S01-list')['BigoLink.parse'] as Map<String, dynamic>;
      expect(legacy, hasLength(23));
      // 24-7: a fragment is ignored and any subdomain of bigo.tv is taken
      // (3.x refused both).
      const changed = {'https://www.bigo.tv/qashia305#x': 'qashia305', 'https://m.bigo.tv/qashia305': 'qashia305'};
      for (final MapEntry(:key, :value) in legacy.entries) {
        if (changed.containsKey(key)) {
          expect(value, isNull, reason: '3.x: $key');
          expect(BigoApi.siteIdFromUrl(key), changed[key], reason: key);
        } else {
          expect(BigoApi.siteIdFromUrl(key), value, reason: key);
        }
      }
      for (final (link, id) in [
        ('https://m.bigo.tv/en/ChrisPCritter78', 'ChrisPCritter78'),
        ('http://BIGO.TV/qashia305#/live', 'qashia305'),
        ('https://www.bigo.tv/cn/qashia305?from=share#top', 'qashia305'),
        ('https://live.bigo.tv/414439909#', '414439909'),
      ]) {
        expect(BigoApi.siteIdFromUrl(link), id, reason: link);
      }
      for (final invalid in [
        'https://mbigo.tv/qashia305',
        'https://bigo.tv.m.example/qashia305',
        'https://m.bigo.tv:8443/qashia305',
        'https://www.bigo.tv/#qashia305',
        'https://m.bigo.tv/search',
      ]) {
        expect(BigoApi.siteIdFromUrl(invalid), isNull, reason: invalid);
      }
      // 3.x's bigo_site_test.dart.
      expect(BigoApi.siteIdFromUrl('https://www.bigo.tv/fixture_101'), 'fixture_101');
      expect(BigoApi.siteIdFromUrl('https://www.bigo.tv/cn/fixture_101'), 'fixture_101');
      for (final invalid in [
        'https://www.bigo.tv/',
        'https://www.bigo.tv/search',
        'https://www.bigo.tv/search/fixture_101/more',
        'https://www.bigo.tv.evil.test/fixture_101',
        'https://www.bigo.tv:444/fixture_101',
        'https://www.bigo.tv/%FF',
        'https://www.bigo.tv/a b',
      ]) {
        expect(BigoApi.siteIdFromUrl(invalid), isNull, reason: invalid);
      }
    });

    test("ids or links (3.x's parseOrSiteId), the room page and the id rule", () {
      final legacy = _legacy('S01-list');
      for (final MapEntry(:key, :value) in (legacy['BigoLink.parseOrSiteId'] as Map<String, dynamic>).entries) {
        expect(BigoApi.siteIdOf(key), value, reason: key);
      }
      expect(BigoApi.link('qashia305'), (legacy['BigoLink.url'] as Map)['qashia305']);
      for (final id in ['', '../file', 'a/b', 'a?b', 'a%2Fb', 'a\r\nX:y', 'a' * 65, '.x', '-x']) {
        expect(BigoApi.isSiteId(id), isFalse, reason: id);
      }
      for (final id in ['414439909', 'qashia305', '_x', 'a.b-c_d', 'a' * 64]) {
        expect(BigoApi.isSiteId(id), isTrue, reason: id);
      }
    });

    test("the search's routing: searchable text and what looks like an id (3.x)", () {
      for (final query in ['', 'a' * 101, 'a\u0001b', 'http://example.com/x', 'bigo://x']) {
        expect(BigoApi.isSearchable(query), isFalse, reason: query);
      }
      for (final query in ['Pk', 'nickname words', '赚钱', 'a' * 100]) {
        expect(BigoApi.isSearchable(query), isTrue, reason: query);
      }
      expect(BigoApi.looksLikeId('414439909'), isTrue);
      expect(BigoApi.looksLikeId('qashia305'), isTrue);
      expect(BigoApi.looksLikeId('q.a'), isTrue);
      expect(BigoApi.looksLikeId('qashia'), isFalse, reason: 'a word of letters is a name first');
      expect(BigoApi.looksLikeId('nickname words'), isFalse);
    });
  });
}
