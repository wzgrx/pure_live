// Inke parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/inke/legacy_expected.dart from 3.x's InkeApi and InkeSite). Every
// intended difference is listed with its reason; everything else must
// match. The synthetic cases port 3.x's inke_api_test.dart and
// inke_application_test.dart.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('inke', name);

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

String _web(Object? data, {int code = 0}) => jsonEncode({'error_code': code, 'message': 'ok', 'data': data});

String _app(Object? live, {int code = 0}) => jsonEncode({'dm_error': code, 'error_msg': '操作成功', 'live': live});

const _media = 'https://live-pull-ws.ikstatic.cn/live/200_t.flv?wsSecret=fixture%2Bonly&wsABStime=70000000';

/// 3.x's test showcase row.
Map<String, dynamic> _row({Object uid = 100, String liveId = '200', String url = _media, String nick = 'Fixture'}) => {
  'uid': uid,
  'live_id': liveId,
  'nick': nick,
  'level': 60,
  'gender': 0,
  'portrait': 'https://img.ikstatic.cn/fixture.jpg',
  'stream_addr': url,
};

/// 3.x's test room answer.
Map<String, dynamic> _info({String liveId = '200'}) => {
  'live_uid': '100',
  'liveid': liveId,
  'status': 1,
  'live_name': 'Music',
  'media_info': {'inke_id': 100, 'nick': 'Fixture', 'level': 60, 'portrait': 'https://img.ikstatic.cn/fixture.jpg'},
  'portrait': 'https://img.ikstatic.cn/fixture.jpg',
  'records': <Object?>[],
};

/// 3.x's test channel.
Map<String, dynamic> _group({String key = 'MUSIC', List<Object?>? rows}) => {
  'tab_key': key,
  'channel_name': 'Music',
  'list': rows ?? [_row()],
};

/// A `now_publish` broadcast of anchor 100.
Map<String, dynamic> _live({Object creator = 100, Object status = 1, String id = '200', String url = _media}) => {
  'creator': creator,
  'id': id,
  'status': status,
  'name': 'Music',
  'stream_addr': url,
  'stream_multi_addr': 'http://live-pull-zego.ikstatic.cn/inkemain/${id}_0_en.flv?codecInfo=8192&wsABStime=70000000',
};

void main() {
  group('S01 catalog and channels', () {
    for (final name in ['S01-channels', 'S05-unlisted-channels']) {
      test('$name: the catalog and every channel page match 3.x', () {
        final fixture = _sample(name);
        final legacy = _legacy(name);
        final category = InkeApi.categories(fixture.body, status: fixture.status).single;
        final known = _maps(legacy['getCategores']).single;
        expect((category.id, category.name), (known['id'], known['name']));
        final areas = _maps(known['children']);
        expect(category.children, hasLength(areas.length));
        for (final (index, area) in category.children.indexed) {
          _expectParity(area.toJson(), areas[index], reason: '$name area $index');
        }
        final pages = legacy['getDirectoryPage'] as Map<String, dynamic>;
        expect(pages.keys, category.children.map((area) => area.areaId));
        for (final MapEntry(:key, :value) in pages.entries) {
          final page = InkeApi.channelPage(fixture.body, tabKey: key);
          final want = _result(value)! as Map<String, dynamic>;
          expect((page.page, page.hasMore), (want['page'], want['hasMore']));
          _expectRooms(page.rooms, want['rooms'], reason: '$name $key');
          expect(page.rooms.every((room) => room.isLiveNow && room.data == null), isTrue);
        }
      });
    }

    test('S01-channels: the six channels of the site, in its order', () {
      final category = InkeApi.categories(_sample('S01-channels').body).single;
      expect(category.children.map((area) => area.areaName), ['音乐', '舞蹈', '新颜', '校园', '男神', '派对']);
      expect(category.children.first.areaType, 'showcase');
      expect(category.children.first.typeName, '映客官网精选');
    });

    test('channel keys pick the real group, whatever the order; an unknown one is NotFound (3.x)', () {
      final body = _web({
        'list': [
          _group(),
          _group(key: 'CHAT', rows: [_row(uid: 101)]),
        ],
      });
      expect(InkeApi.categories(body).single.children.map((area) => area.areaId), ['MUSIC', 'CHAT']);
      expect(InkeApi.channelPage(body, tabKey: 'CHAT').rooms.single.roomId, '101');
      expect(() => InkeApi.channelPage(body, tabKey: 'missing'), throwsA(isA<NotFound>()));
    });

    test('a repeated or unsafe key, a nameless channel or a bad list fails the whole catalog (3.x)', () {
      for (final groups in <Object?>[
        [_group(), _group()],
        [_group()..['list'] = <String, Object?>{}],
        [_group(key: '../path')],
        [_group()..['channel_name'] = ' '],
        [_group(key: 'x' * 65)],
        List.generate(101, (index) => _group(key: 'K$index')),
        {'MUSIC': _group()},
      ]) {
        expect(() => InkeApi.categories(_web({'list': groups})), throwsA(isA<ApiChanged>()), reason: '$groups');
        expect(() => InkeApi.channelRooms(_web({'list': groups})), throwsA(isA<ApiChanged>()), reason: '$groups');
      }
    });
  });

  group('S01 top list', () {
    for (final name in ['S01-top', 'S05-unlisted-top']) {
      test('$name: the recommendations match 3.x', () {
        final fixture = _sample(name);
        final page = InkeApi.topPage(fixture.body, status: fixture.status);
        final want = _result(_legacy(name)['getDirectoryPage'])! as Map<String, dynamic>;
        expect((page.page, page.hasMore), (want['page'], want['hasMore']));
        _expectRooms(page.rooms, want['rooms'], reason: name);
      });
    }

    test('one finite page, each uid once, no audience (3.x)', () {
      final page = InkeApi.topPage(
        _web({
          'list': [_row(), _row(), _row(uid: 101)],
        }),
      );
      expect(page.rooms.map((room) => room.roomId), ['100', '101']);
      final room = page.rooms.first;
      expect(room.watching, isEmpty);
      expect(room.audienceMetricType, AudienceMetricType.unknown);
      expect(room.supportsRealOnlineCount, isFalse);
      expect(room.audienceValue(preferRealOnline: false, platformEnabled: true), isEmpty);
      expect((room.title, room.nick, room.userId), ('Fixture', 'Fixture', '100'));
      expect((room.avatar, room.cover), ('https://img.ikstatic.cn/fixture.jpg', 'https://img.ikstatic.cn/fixture.jpg'));
      expect(room.link, 'https://www.inke.cn/liveroom/index.html?uid=100&id=200');
      expect(page.hasMore, isFalse);
      expect(() => page.rooms.add(room), throwsUnsupportedError);
    });

    test('a row without a uid, broadcast id or nickname fails the list (3.x)', () {
      for (final row in [
        _row(uid: '0100'),
        _row(uid: 1.5),
        _row(liveId: ''),
        _row(nick: ' '),
        _row()..remove('nick'),
      ]) {
        expect(
          () => InkeApi.topPage(
            _web({
              'list': [row],
            }),
          ),
          throwsA(isA<ApiChanged>()),
          reason: '$row',
        );
      }
      expect(() => InkeApi.topPage(_web({'list': 'rows'})), throwsA(isA<ApiChanged>()));
      expect(
        () => InkeApi.topPage(_web({'list': List.generate(1001, (index) => _row(uid: index + 1))})),
        throwsA(isA<ApiChanged>()),
      );
    });
  });

  group('search', () {
    final top = InkeApi.topPage(_sample('S01-top').body).rooms;
    final channels = InkeApi.channelRooms(_sample('S01-channels').body);
    final legacy = _legacy('S01-top')['searchRooms'] as Map<String, dynamic>;

    for (final keyword in ['糖果', '西', '欧阳', 'mee', '🎶', 'zxqvnoresultfixture']) {
      test('"$keyword" over the S01 showcases matches 3.x', () {
        final rooms = InkeApi.searchShowcases(keyword, [...top, ...channels]);
        _expectRooms(rooms, _result(legacy[keyword]), reason: keyword);
      });
    }

    test('pages of the matches match 3.x', () {
      for (final page in [1, 2, 3]) {
        final rooms = InkeApi.searchShowcases('🎶', [...top, ...channels], page: page, pageSize: 3);
        _expectRooms(rooms, _result(legacy['🎶 page $page, pageSize 3']), reason: 'page $page');
      }
    });

    test('a room in the top list and a channel is found once; case is ignored (3.x)', () {
      expect(InkeApi.searchShowcases(' 糖果 ', [...top, ...channels]).map((room) => room.roomId), [
        '757370483',
      ], reason: 'in the top list and 舞蹈');
      expect(InkeApi.searchShowcases('MEE', [...top, ...channels]).single.nick, 'Mee 蓝');
      expect(InkeApi.searchShowcases('  ', [...top, ...channels]), isEmpty);
    });
  });

  group('S03 detail', () {
    test('S03-share-live: the room matches 3.x at every depth; the broadcast id is kept aside', () {
      final fixture = _sample('S03-share-live');
      final legacy = _legacy('S03-share-live');
      final room = InkeApi.detail(fixture.body, uid: '771067357', status: fixture.status);
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        _expectParity(_projection(room), _result(legacy[key])! as Map<String, dynamic>, reason: key);
      }
      _expectParity(_projection(room), _maps(_result(legacy['searchRooms'])).single, reason: 'search');
      expect(room.roomId, '771067357', reason: 'the uid asked for (3.x)');
      expect((room.data! as InkeRoomData).liveId, '1790521153165881');
      expect(InkeApi.externalRoomUrl(room), legacy['externalRoomUrl']);
      expect(room.introduction, isNull, reason: '3.x set none; media_info.description is a placeholder');
    });

    test('S03-share-offline: code 1099999920 is offline with only the uid, as 3.x', () {
      final fixture = _sample('S03-share-offline');
      final legacy = _legacy('S03-share-offline');
      final room = InkeApi.detail(fixture.body, uid: '1', status: fixture.status);
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        _expectParity(_projection(room), _result(legacy[key])! as Map<String, dynamic>, reason: key);
      }
      expect(room.isExplicitlyOfflineNow, isTrue);
      expect(room.data, isNull);
      expect(room.link, 'https://www.inke.cn/liveroom/index.html?uid=1');
      expect(InkeApi.externalRoomUrl(room), legacy['externalRoomUrl'], reason: 'no broadcast: the home page');
      expect(legacy['getPlayQualites'], isEmpty);
    });

    test('S05-unlisted-share: 3.x failed the room it could not find a pull URL for; now it opens', () {
      final fixture = _sample('S05-unlisted-share');
      final legacy = _legacy('S05-unlisted-share');
      // changed: getRoomDetail and getRoomDetailForRecording. 3.x looked for the
      // broadcast in the showcases (four requests) and failed the whole room;
      // the room is now the refresh's, and the stream is resolved when played.
      for (final key in ['getRoomDetail', 'getRoomDetailForRecording']) {
        final result = _result(legacy[key])! as Map<String, dynamic>;
        expect(result['throws'], 'InkeException', reason: key);
        expect(result['message'], contains('官网精选未提供'), reason: key);
        expect((legacy[key] as Map<String, dynamic>)['requests'], hasLength(4));
      }
      final room = InkeApi.detail(fixture.body, uid: '778920027');
      _expectParity(_projection(room), _result(legacy['getRoomDetailForRefresh'])! as Map<String, dynamic>);
      expect(room.isLiveNow, isTrue);
      expect((room.data! as InkeRoomData).liveId, '1790588581683219');
    });

    test('an answer that is not the live room of that anchor is ApiChanged, never offline (3.x)', () {
      for (final edit in <void Function(Map<String, dynamic>)>[
        (info) => info['media_info'] = {'inke_id': 101, 'nick': 'Other'},
        (info) => info['media_info'] = {'inke_id': 100, 'nick': ' '},
        (info) => info['media_info'] = 'none',
        (info) => info['live_uid'] = '101',
        (info) => info['status'] = 2,
        (info) => info['liveid'] = '',
        (info) => info
          ..clear()
          ..['noCurrentBroadcast'] = true,
      ]) {
        final info = _info();
        edit(info);
        expect(() => InkeApi.detail(_web(info), uid: '100'), throwsA(isA<ApiChanged>()), reason: '$info');
      }
      for (final status in [1, '1', true]) {
        expect(InkeApi.detail(_web(_info()..['status'] = status), uid: '100').isLiveNow, isTrue, reason: '$status');
      }
      final untitled = InkeApi.detail(_web(_info()..['live_name'] = ''), uid: '100');
      expect(untitled.title, 'Fixture', reason: 'the nickname stands in');
    });

    test('only the room endpoint reads code 1099999920 as offline (3.x)', () {
      const offline = '{"error_code":1099999920,"data":null}';
      expect(InkeApi.detail(offline, uid: '100').isExplicitlyOfflineNow, isTrue);
      expect(() => InkeApi.topPage(offline), throwsA(isA<ApiChanged>()));
      expect(() => InkeApi.categories(offline), throwsA(isA<ApiChanged>()));
      expect(() => InkeApi.detail('{"error_code":12345,"data":null}', uid: '100'), throwsA(isA<ApiChanged>()));
    });
  });

  group('streams', () {
    test("S03-share-live: 3.x's quality; its showcase URL is found byte for byte by the fallback", () {
      final legacy = _legacy('S03-share-live');
      final quality = _maps(legacy['getPlayQualites']).single;
      expect(
        (InkeApi.flv.quality, InkeApi.flv.id, InkeApi.flv.sort),
        (quality['quality'], quality['id'], quality['sort']),
      );
      final urls = InkeApi.showcaseUrls(
        _sample('S01-top').body,
        path: 'Live_top_pc',
        uid: '771067357',
        liveId: '1790521153165881',
      );
      expect(urls, quality['getPlayUrls']);
      final recovery = _result(legacy['resolvePlayUrlsForRecoveryRaw'])! as Map<String, dynamic>;
      expect(urls, recovery['urls']);
      expect(InkeApi.flv.selectionId, recovery['appliedQualityData']);
    });

    test('S04-publish-live: the app names the same broadcast and the same Wangsu stream as 3.x (REG-INKE-001)', () {
      final fixture = _sample('S04-publish-live');
      final broadcast = InkeApi.broadcast(fixture.body, uid: '771067357', status: fixture.status)!;
      expect(broadcast.liveId, '1790521153165881', reason: "live_share_pc's liveid");
      final legacy = Uri.parse(
        (_maps(_legacy('S03-share-live')['getPlayQualites']).single['getPlayUrls'] as List).single as String,
      );
      final url = Uri.parse(broadcast.pullUrl!);
      // The same stream: host, path and stream_id as 3.x's.
      expect((url.scheme, url.host, url.path), (legacy.scheme, legacy.host, legacy.path));
      expect(url.queryParameters.keys, legacy.queryParameters.keys);
      _expectParity(
        url.queryParameters,
        legacy.queryParameters,
        // The signature and its expiry: the URL comes from another request
        // (now_publish, not the top list), signed separately.
        changed: {'wsSecret', 'wsABStime'},
        reason: 'pull URL',
      );
      expect(url.queryParameters['wsABStime'], isNot(legacy.queryParameters['wsABStime']));
      final live = (jsonDecode(fixture.body) as Map<String, dynamic>)['live'] as Map<String, dynamic>;
      final zego = live['stream_multi_addr'] as String;
      expect(InkeApi.plainFlv(zego, liveId: broadcast.liveId), isNull, reason: 'HEVC (REG-INKE-002)');
    });

    test('S05: a broadcast outside every showcase: 3.x found nothing, the app gives its URL (REG-INKE-001)', () {
      const uid = '778920027';
      const liveId = '1790588581683219';
      final requests = (_legacy('S05-unlisted-share')['getRoomDetail'] as Map<String, dynamic>)['requests'] as List;
      expect(requests.skip(1).map((url) => Uri.parse(url as String).path), [
        '/web/Live_top_pc',
        '/web/Live_hot_pc',
        '/web/Live_channel_pc',
      ]);
      for (final (name, path) in [
        ('S05-unlisted-top', 'Live_top_pc'),
        ('S05-unlisted-hot', 'Live_hot_pc'),
        ('S05-unlisted-channels', 'Live_channel_pc'),
      ]) {
        expect(
          InkeApi.showcaseUrls(_sample(name).body, path: path, uid: uid, liveId: liveId),
          isEmpty,
          reason: name,
        );
      }
      final broadcast = InkeApi.broadcast(_sample('S05-unlisted-publish').body, uid: uid)!;
      expect(broadcast.liveId, liveId);
      expect(broadcast.pullUrl, startsWith('https://live-pull-ws.ikstatic.cn/live/${liveId}_t.flv?'));
    });

    test("S05 showcases: the fallback finds what 3.x's lookup found for every row, in as many requests", () {
      final legacy = _legacy('S05-unlisted-hot');
      const paths = [
        ('S05-unlisted-top', 'Live_top_pc'),
        ('S05-unlisted-hot', 'Live_hot_pc'),
        ('S05-unlisted-channels', 'Live_channel_pc'),
      ];
      final bodies = [for (final (name, _) in paths) _sample(name).body];
      expect(legacy, hasLength(44));
      for (final MapEntry(:key, :value) in legacy.entries) {
        final [uid, liveId] = key.split('/');
        var asked = 0;
        var urls = const <String>[];
        for (final (index, (_, path)) in paths.indexed) {
          asked++;
          urls = InkeApi.showcaseUrls(bodies[index], path: path, uid: uid, liveId: liveId);
          if (urls.isNotEmpty) break;
        }
        final want = value as Map<String, dynamic>;
        expect(urls, want['result'], reason: key);
        expect(asked, (want['requests'] as List).length, reason: key);
      }
    });

    test('S04-publish-offline: no broadcast', () {
      final fixture = _sample('S04-publish-offline');
      expect(InkeApi.broadcast(fixture.body, uid: '1', status: fixture.status), isNull);
    });

    test('the line: media headers, FLV, H.264, the Wangsu line id and the wsABStime lease', () {
      final fixture = _sample('S04-publish-live');
      final url = InkeApi.broadcast(fixture.body, uid: '771067357')!.pullUrl!;
      final resolution = InkeApi.resolution([url], issuedAt: fixture.capturedAt);
      final line = resolution.lines.single;
      expect(line.url, url, reason: 'the signed query as written');
      expect(line.headers, {
        'referer': 'https://www.inke.cn/',
        'origin': 'https://www.inke.cn',
        'user-agent': 'Mozilla/5.0',
      });
      expect(line.headers.keys, isNot(contains('cookie')));
      expect((line.format, line.codec, line.lineId), (StreamFormat.flv, 'avc', 'ws'));
      final expiry = DateTime.fromMillisecondsSinceEpoch(0x6ab96f0b * 1000, isUtc: true);
      expect(line.lease!.expiresAt, expiry);
      expect(line.lease!.refreshAt, expiry.subtract(const Duration(minutes: 10)));
      expect(line.lease!.cutsConnection, isFalse, reason: 'Wangsu checks the signature when a connection opens');
      expect(expiry.difference(fixture.capturedAt), greaterThan(const Duration(minutes: 110)));
      expect(resolution.appliedQualityData, 'flv');
    });

    test('leases: a quarter of a short lifetime; none without one wsABStime or once expired', () {
      final issued = DateTime.fromMillisecondsSinceEpoch(0x70000000 * 1000 - 20 * 60 * 1000, isUtc: true);
      final lease = InkeApi.lease(_media, issuedAt: issued)!;
      expect(lease.expiresAt, DateTime.fromMillisecondsSinceEpoch(0x70000000 * 1000, isUtc: true));
      expect(lease.expiresAt!.difference(lease.refreshAt), const Duration(minutes: 5));
      expect(InkeApi.lease(_media, issuedAt: lease.expiresAt!), isNull);
      for (final url in [
        'https://live-pull-ws.ikstatic.cn/live/200_t.flv?wsSecret=x',
        '$_media&wsABStime=70000001',
        _media.replaceFirst('70000000', 'zz'),
        _media.replaceFirst('70000000', '0'),
      ]) {
        expect(InkeApi.lease(url, issuedAt: issued), isNull, reason: url);
      }
    });

    test("pull URLs: 3.x's check, the signed query as written, no other host, broadcast or protocol", () {
      expect(InkeApi.plainFlv(_media, liveId: '200'), _media);
      expect(InkeApi.plainFlv(_media.replaceFirst('https:', 'http:'), liveId: '200'), startsWith('http:'));
      expect(InkeApi.plainFlv(' $_media ', liveId: '200'), _media);
      for (final url in [
        _media.replaceAll('ikstatic.cn', 'ikstatic.cn.evil.test'),
        _media.replaceAll('200_t', '201_t'),
        _media.replaceAll('200_t', '200_0_en'),
        _media.replaceAll('https:', 'file:'),
        _media.replaceAll('https://', 'https://name@'),
        _media.replaceFirst('.cn/', '.cn:8443/'),
        '$_media#fragment',
        'http://live-pull-zego.ikstatic.cn/inkemain/200_0_en.flv?codecInfo=8192',
        '',
      ]) {
        expect(InkeApi.plainFlv(url, liveId: '200'), isNull, reason: url);
      }
      expect(InkeApi.plainFlv(_media, liveId: '../200'), isNull);
      expect(InkeApi.plainFlv(42, liveId: '200'), isNull);
    });

    test('now_publish: the anchor asked for, status 1 is live, anything else no broadcast', () {
      expect(InkeApi.broadcast(_app(_live()), uid: '100')!.pullUrl, _media);
      expect(InkeApi.broadcast(_app(_live(creator: '100')), uid: '100')!.liveId, '200');
      expect(InkeApi.broadcast(_app(_live(status: 0)), uid: '100'), isNull);
      expect(InkeApi.broadcast(_app(_live(status: '1')), uid: '100'), isNotNull);
      final zegoOnly = InkeApi.broadcast(_app(_live(url: '')), uid: '100')!;
      expect((zegoOnly.liveId, zegoOnly.pullUrl), ('200', null));
      expect(() => InkeApi.broadcast(_app(_live(creator: 101)), uid: '100'), throwsA(isA<ApiChanged>()));
      expect(() => InkeApi.broadcast(_app(_live(id: 'x')), uid: '100'), throwsA(isA<ApiChanged>()));
      expect(() => InkeApi.broadcast(_app('live'), uid: '100'), throwsA(isA<ApiChanged>()));
      expect(() => InkeApi.broadcast(_app(null, code: 499), uid: '100'), throwsA(isA<ApiChanged>()));
      expect(() => InkeApi.broadcast('{"live":null}', uid: '100'), throwsA(isA<ApiChanged>()));
    });

    test('the hot lists are a map of lists; each showcase only by its own shape', () {
      final hot = _web({
        'list': {
          'recommend': <Object?>[],
          'hot': [_row()],
        },
      });
      expect(InkeApi.showcaseUrls(hot, path: 'Live_hot_pc', uid: '100', liveId: '200'), [_media]);
      expect(
        () => InkeApi.showcaseUrls(hot, path: 'Live_top_pc', uid: '100', liveId: '200'),
        throwsA(isA<ApiChanged>()),
      );
      final channels = _web({
        'list': [_group()],
      });
      expect(InkeApi.showcaseUrls(channels, path: 'Live_channel_pc', uid: '100', liveId: '200'), [_media]);
      expect(InkeApi.showcaseUrls(channels, path: 'Live_channel_pc', uid: '100', liveId: '199'), isEmpty);
      final twice = _web({
        'list': [_row(), _row(), _row(uid: 101)],
      });
      expect(InkeApi.showcaseUrls(twice, path: 'Live_top_pc', uid: '100', liveId: '200'), [_media]);
    });
  });

  group('envelope', () {
    test('HTTP failures are typed and never look offline (3.x)', () {
      for (final (status, matcher) in [
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (500, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
        (204, isA<NetworkFailure>()),
      ]) {
        expect(
          () => InkeApi.detail('sensitive response must not appear', uid: '100', status: status),
          throwsA(matcher),
          reason: '$status',
        );
        expect(
          () => InkeApi.broadcast('x', uid: '100', status: status),
          throwsA(matcher),
          reason: '$status',
        );
      }
    });

    test('bodies that are not JSON objects, without a code or data, or over 1 MiB are ApiChanged (3.x)', () {
      for (final body in [
        'not json',
        '[]',
        '{"data":{}}',
        '{"error_code":"x","data":{}}',
        '{"error_code":0,"data":[]}',
        '{"error_code":0}',
        'x' * (InkeApi.responseLimit + 1),
        jsonEncode({
          'error_code': 0,
          'data': {'large': List.filled(400000, '映').join()},
        }),
      ]) {
        expect(
          () => InkeApi.detail(body, uid: '100'),
          throwsA(isA<ApiChanged>()),
          reason: body.length > 40 ? body.substring(0, 40) : body,
        );
      }
      expect(InkeApi.webData('{"error_code":"0","data":{"a":1}}', what: 'x'), {'a': 1});
    });
  });

  group('links', () {
    test('web room pages: the uid, whatever broadcast id they carry (3.x)', () {
      for (final host in ['inke.cn', 'www.inke.cn', 'inke.com', 'www.inke.com', 'WWW.INKE.CN']) {
        expect(
          InkeApi.roomIdFromUri(Uri.parse('https://$host/liveroom/index.html?uid=100&id=999')),
          '100',
          reason: host,
        );
      }
      expect(InkeApi.roomIdFromUri(Uri.parse('http://www.inke.cn:80/liveroom/index.html?uid=100')), '100');
      for (final url in [
        'https://www.inke.cn.evil.test/liveroom/index.html?uid=100',
        'https://name@www.inke.cn/liveroom/index.html?uid=100',
        'https://www.inke.cn:8787/liveroom/index.html?uid=100',
        'https://www.inke.cn/?uid=100',
        'https://www.inke.cn/liveroom/index.html?uid=100&uid=101',
        'https://www.inke.cn/liveroom/index.html?uid=0',
        'https://www.inke.cn/liveroom/index.html?uid=0100',
        'https://www.inke.cn/liveroom/index.html?id=100',
        'file:///liveroom/index.html?uid=100',
        'https://m.inke.cn/liveroom/index.html?uid=100',
      ]) {
        expect(InkeApi.roomIdFromUri(Uri.parse(url)), isNull, reason: url);
      }
      expect(InkeApi.roomIdFromUri(null), isNull);
    });

    test("app share pages (the app's share_addr, which 3.x did not know)", () {
      final live =
          (jsonDecode(_sample('S04-publish-live').body) as Map<String, dynamic>)['live'] as Map<String, dynamic>;
      final share = live['share_addr'] as String;
      expect(share, startsWith('https://mlive2.inke.cn/app/'));
      expect(InkeApi.roomIdFromUri(Uri.parse(share)), '771067357');
      expect(InkeApi.roomIdFromUri(Uri.parse('https://mlive.inke.cn/app/hot/live?uid=100')), '100');
      for (final url in [
        'https://mlive2.inke.cn/web/hot/live?uid=100',
        'https://mlive2.inke.cn.evil.test/app/hot/live?uid=100',
        'https://mliveX.inke.cn/app/hot/live?uid=100',
        'https://mlive2.inke.cn/app/hot/live?liveid=100',
        'https://mlive2.inke.cn:8443/app/hot/live?uid=100',
      ]) {
        expect(InkeApi.roomIdFromUri(Uri.parse(url)), isNull, reason: url);
      }
    });

    test('opening in the browser needs this uid and one numeric broadcast id, else the home page (3.x)', () {
      const valid = 'https://www.inke.cn/liveroom/index.html?uid=100&id=199';
      expect(InkeApi.externalRoomUrl(LiveRoom(platform: 'inke', roomId: '100', link: valid)), valid);
      expect(
        InkeApi.externalRoomUrl(LiveRoom(platform: 'inke', link: 'https://example.test/?id=199')),
        'https://www.inke.cn/',
      );
      for (final link in <String?>[
        null,
        '',
        '  ',
        valid.split('&id=').first,
        '$valid&id=200',
        valid.replaceFirst('uid=100', 'uid=101'),
        valid.replaceFirst('id=199', 'id=abc'),
        valid.replaceFirst('inke.cn', 'inke.cn.evil.test'),
        'https://www.inke.cn/liveroom/index.html?uid=100&id=%FF',
        'https://mlive2.inke.cn/app/hot/live?uid=100&liveid=199',
      ]) {
        expect(
          InkeApi.externalRoomUrl(LiveRoom(platform: 'inke', roomId: '100', link: link)),
          'https://www.inke.cn/',
          reason: '$link',
        );
      }
      expect(InkeApi.externalRoomUrl(LiveRoom(platform: 'other', roomId: '100', link: valid)), 'https://www.inke.cn/');
    });
  });
}
