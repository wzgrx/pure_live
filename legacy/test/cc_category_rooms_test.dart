import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/site/cc/cc_site.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);
  final ResponseBody Function(RequestOptions) reply;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream, Future<void>? cancel) async =>
      reply(options);
  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _room(String id, {Object? status = 1}) => {
  'cuteid': id,
  'title': 'Room $id',
  'nickname': 'Fixture',
  'gametype': 3,
  'gamename': 'Game',
  'status': status,
  'webcc_visitor': 800,
  'vision_visitor': 7,
  'purl': 'https://example.test/avatar.png',
  'cover': 'https://example.test/cover.png',
};

void main() {
  late Dio previous;
  late Dio dio;
  late List<RequestOptions> requests;
  Object? payload;
  var status = 200;
  setUp(() {
    previous = HttpClient.instance.dio;
    requests = [];
    payload = null;
    status = 200;
    dio = Dio()
      ..httpClientAdapter = _Adapter((request) {
        requests.add(request);
        final offset = request.queryParameters['start'] ?? 0;
        final rows = [_room(offset == 0 ? '101' : '202')];
        // Both actual wire shapes are represented so the red test pinpoints the
        // old repeated SSR seed, rather than just failing from a missing fixture.
        final body =
            payload ??
            (request.path.contains('/_next/')
                ? {
                    'pageProps': {
                      'gametypeData': {'lives': rows},
                    },
                  }
                : {'gametype': 3, 'name': 'Game', 'lives': rows, 'videos': []});
        return ResponseBody.fromString(
          jsonEncode(body),
          status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    HttpClient.instance.dio = dio;
  });
  tearDown(() {
    HttpClient.instance.dio = previous;
    dio.close(force: true);
  });

  LiveArea area({String? id = '3', String? platform = 'cc'}) => LiveArea(areaId: id, platform: platform, areaType: '2');

  test('category pages use server offsets instead of replaying the SSR seed', () async {
    final site = CCSite();
    final first = await site.getCategoryRooms(area(), page: 1, pageSize: 2);
    final second = await site.getCategoryRooms(area(), page: 2, pageSize: 2);
    expect(first.single.roomId, '101');
    expect(second.single.roomId, '202');
    expect(requests.map((r) => r.uri.path), ['/api/category/3/', '/api/category/3/']);
    expect(requests.last.queryParameters, {'format': 'json', 'tag_id': 0, 'start': 2, 'size': 2});
  });

  test('legacy favorite JSON keeps numeric category identity regardless of parent', () async {
    final old = LiveArea.fromJson({'platform': 'cc', 'areaId': '3', 'areaType': '2', 'areaName': 'Old label'});
    expect((await CCSite().getCategoryRooms(old)).single.roomId, '101');
    expect(old.areaType, '2');
    expect(old.areaName, 'Old label');
    expect(requests.single.uri.path, '/api/category/3/');
  });

  test('live cards keep audience semantics, status and optional metadata separate', () async {
    payload = {
      'gametype': '3',
      'lives': [_room('101'), _room('102', status: 0), _room('103', status: 99)],
    };
    final rows = await CCSite().getCategoryRooms(area());
    expect(rows.map((r) => r.liveStatus), [LiveStatus.live, LiveStatus.offline, LiveStatus.unknown]);
    expect(rows.first.popularity, '800');
    expect(rows.first.onlineViewers, '7');
    expect(rows.first.area, 'Game');
    expect(rows.first.data, isNull);
  });

  test('videos are not promoted to live cards and a valid empty feed is empty', () async {
    payload = {
      'gametype': 3,
      'lives': [],
      'videos': [
        {'cuteid': '999', 'type': 'video'},
      ],
    };
    expect(await CCSite().getCategoryRooms(area()), isEmpty);
  });

  for (final bad in <Object?>[
    '<!DOCTYPE html>',
    {'error': 'fixture'},
    {'gametype': 4, 'lives': []},
    {'gametype': 3, 'lives': {}},
    {
      'gametype': 3,
      'lives': [null],
    },
    {
      'gametype': 3,
      'lives': [
        {'cuteid': null},
      ],
    },
  ]) {
    test('a failed or mismatched payload is an error, not an empty successful page: $bad', () async {
      payload = bad;
      await expectLater(CCSite().getCategoryRooms(area()), throwsA(isA<FormatException>()));
    });
  }

  test('HTTP failure propagates instead of clearing the old directory', () async {
    status = 503;
    await expectLater(CCSite().getCategoryRooms(area()), throwsA(anything));
  });

  test('invalid IDs, foreign categories and invalid pagination never send a request', () async {
    for (final id in <String?>[null, '', '0', '../3', '3?x=y']) {
      await expectLater(CCSite().getCategoryRooms(area(id: id)), throwsArgumentError);
    }
    await expectLater(CCSite().getCategoryRooms(area(platform: 'huya')), throwsArgumentError);
    for (final bounds in [(0, 30), (1, 0), (-1, 30), (1, 1001), (100001, 30)]) {
      await expectLater(CCSite().getCategoryRooms(area(), page: bounds.$1, pageSize: bounds.$2), throwsArgumentError);
    }
    expect(requests, isEmpty);
  });
}
