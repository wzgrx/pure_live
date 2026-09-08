import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/core/site/kilakila/kilakila_api.dart';
import 'package:pure_live/core/site/kilakila/kilakila_site.dart';

// Shape observed on official type=107 pages 1/2 (2026-09-08 02:07 UTC).
// UID, broadcast ID and display values are synthetic; media is not retained.
Map<String, dynamic> row({int dataType = 2, String owner = '100'}) => {
  'dataType': dataType,
  'roomResq': {
    'roomIdStr': '9007199254740993123',
    'uid': '100',
    'title': 'Fixture live',
    'status': 4,
    'goldPrice': 0,
    'watchNumber': 1234,
  },
  'userResp': {'id': owner, 'nickname': 'Fixture'},
};
KilakilaApi api(List<Map<String, dynamic>> rows) => KilakilaApi(
  request: (uri, cancel) async => (
    status: 200,
    body: jsonEncode({
      'code': 200,
      'data': {
        'body': {
          'h': {'code': 200, 'success': true},
          'b': {
            'pageNo': int.parse(uri.queryParameters['pageNo']!),
            'pageSize': int.parse(uri.queryParameters['pageSize']!),
            'isLastPage': false,
            'data': rows,
          },
        },
      },
    }),
  ),
);
void main() {
  test('rising-star type=107 accepts real dataType=2 live rows', () async {
    final page = await api([row()]).directory(type: 107);
    expect(page.rooms, hasLength(1));
    expect(page.rooms.single.userId, '100');
    expect(page.rooms.single.roomId, '9007199254740993123');
    expect(page.rooms.single.media, isEmpty);
    expect(page.hasMore, isTrue);
  });
  test('rising-star app category displays stable UID instead of silently empty cards', () async {
    final site = KilakilaSite(api: api([row()]));
    final page = await site.getDirectoryPage(
      page: 2,
      category: LiveArea(platform: 'kilakila', areaType: 'timeline', areaId: '107'),
    );
    expect(page.page, 2);
    expect(page.hasMore, isTrue);
    expect(page.rooms.map((r) => r.roomId), ['100']);
    expect(page.rooms.single.isLiveNow, isTrue);
    expect(page.rooms.single.data, isNull);
  });
  test('new accepted row type still requires matching room and owner', () async {
    await expectLater(
      api([row(owner: '101')]).directory(type: 107),
      throwsA(isA<KilakilaException>().having((e) => e.kind, 'kind', KilakilaFailure.schema)),
    );
  });
  test('row type 2 does not widen the unrelated hot timeline contract', () async {
    final page = await api([row(), row(dataType: 8)]).directory(type: 0);
    expect(page.rooms, hasLength(1));
  });
  test('unrecognized rows remain excluded and known room rows remain supported', () async {
    final page = await api([row(dataType: 3), row(dataType: 8)]).directory(type: 107);
    expect(page.rooms, hasLength(1));
  });
  test('category labels match the official rising-star rather than a guessed newcomer title', () {
    final zh = jsonDecode(File('assets/translations/zh.json').readAsStringSync()) as Map;
    final en = jsonDecode(File('assets/translations/en.json').readAsStringSync()) as Map;
    expect(zh['kilakila_newcomers'], '萌星推荐');
    expect(en['kilakila_newcomers'], 'Rising stars');
  });
}
