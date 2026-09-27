// The 3.3.x bridge must reproduce the legacy output for Bilibili lists
// (docs/adr/0012-legacy-bridge.md, rule 3); the only allowed differences are
// the ones the spec requires, listed per field below.
//
// Search stays on the legacy code: its cards carry `followers` (live_room
// `attentions`, used by the search page's follower ranking), which a v4
// RoomCard does not have.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart' show RiskControl, decodeHtmlEntities;
import 'package:live_net/testing.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/core/site/v4_bridge/v4_bridge.dart';

import '../fixtures_expected/support.dart';

const _root = '../fixtures/bilibili';

/// The guest session every flow may need: finger/spi, nav, /lol.
const _session = ['S10-guest', 'S11-guest', 'S12-guest'];

/// WBI signature and access id, scrubbed in the samples.
const _ignored = {'wts', 'w_rid', 'w_webid'};

({V4Bridge bridge, ReplayHttp http}) _replay(List<Object> samples) {
  final http = ReplayHttp([
    for (final sample in samples) sample is String ? ReplaySample.load('$_root/$sample') : sample as ReplaySample,
    for (final sample in _session) ReplaySample.load('$_root/$sample'),
  ], ignoredQuery: _ignored);
  return (bridge: V4Bridge.withHttp(http), http: http);
}

/// The frozen legacy output (`expected.json` → `value`).
Object? _legacy(String sample) =>
    (jsonDecode(File('$_root/$sample/expected.json').readAsStringSync()) as Map<String, dynamic>)['value'];

/// The raw recommendation list of [sample] (`data`, or the feed's
/// `data.recommend_room_list`), by room id.
Map<String, Map<String, dynamic>> _raw(String sample) {
  final data = (jsonDecode(File('$_root/$sample/body.json').readAsStringSync()) as Map<String, dynamic>)['data'];
  final list = (data is Map ? data['recommend_room_list'] : data) as List;
  return {for (final item in list.cast<Map<String, dynamic>>()) '${item['roomid']}': item};
}

/// Legacy card with the spec-mandated differences applied.
Map<String, dynamic> _expected(Map<String, dynamic> legacy, Map<String, dynamic> raw) {
  final watched = raw['watched_show'] as Map<String, dynamic>;
  return {
    ...legacy,
    // v4 decodes HTML entities in titles (RoomCard.title, ADR 0010).
    'title': decodeHtmlEntities(legacy['title'] as String),
    // spec §4.4: `watched_show` with `switch: true` ("N人看过") is the
    // broadcast's cumulative count; legacy dropped it (totalViewers ''),
    // ADR 0010 rule 3 keeps the measure. `switch: false` only repeats the
    // popularity ("N人气") and adds nothing.
    if (watched['switch'] == true) 'totalViewers': '${watched['num']}',
  };
}

void main() {
  test('categories keep the legacy ids (area 0 "全部…" included), names and icons', () async {
    final categories = await _replay(['S01-guest']).bridge.categories('bilibili');
    final legacy = _legacy('S01-guest') as List;
    expect([
      for (final category in categories)
        {
          'id': category.id,
          'name': category.name,
          'children': [for (final area in category.children) area.toJson()],
        },
    ], legacy);
    // The platform's own "全部网游" entry (id 0) heads its category, as in legacy.
    expect(categories.first.children.first.areaId, '0');
  });

  test('area rooms: guests get -352 on every page; the error keeps "-352" for the legacy login prompt', () async {
    // No successful sample exists (DIAGNOSIS: guest area pages are all -352),
    // so only the error path is compared. Legacy threw
    // `Exception: Exception: {code: -352, …}`; v4 retries once with renewed
    // WBI keys, buvid and access id (spec §9) and then throws RiskControl.
    // The legacy area page keys its login prompt on "-352" in the error text
    // (area_rooms_controller.dart:25), which the RiskControl detail carries.
    final legacy = _legacy('S02-signed-risk352') as Map<String, dynamic>;
    expect((legacy['throws'] as Map)['message'], contains('-352'));
    final (:bridge, :http) = _replay(['S02-signed-risk352']);
    final area = LiveArea(platform: 'bilibili', areaType: '2', areaId: '86', areaName: '英雄联盟');
    Object? error;
    try {
      await bridge.areaRooms('bilibili', area, 1);
    } on Object catch (caught) {
      error = caught;
    }
    expect(error, isA<RiskControl>());
    expect(error.toString(), contains('-352'));
    final pages = [
      for (final request in http.requests)
        if (request.url.path.endsWith('/second/getList')) request.url.queryParameters,
    ];
    expect(pages, hasLength(2), reason: 'one retry after renewing the session (spec §9)');
    for (final query in pages) {
      expect(query, containsPair('parent_area_id', '2'));
      expect(query, containsPair('area_id', '86'));
      expect(query, containsPair('page', '1'));
      expect(query['w_webid'], isNotEmpty);
    }
  });

  test('recommend (ranked list) matches legacy', () async {
    final rooms = await _replay(['S03-page1']).bridge.recommended('bilibili', 1);
    final raw = _raw('S03-page1');
    final legacy = (_legacy('S03-page1') as List).cast<Map<String, dynamic>>();
    expect(
      [for (final room in rooms) roomProjection(room)],
      [for (final room in legacy) _expected(room, raw[room['roomId']]!)],
    );
  });

  test('recommend falls back to the feed after the ranked list fails twice, and matches legacy', () async {
    // The ranked list has no failure sample; a platform error answer stands in.
    final failing = ReplaySample(
      method: 'GET',
      url: Uri.parse(
        'https://api.live.bilibili.com/room/v1/Area/getListByAreaID?areaId=0&parent_area_id=0&sort=online&pageSize=30&page=1',
      ),
      status: 200,
      bytes: utf8.encode('{"code":-400,"message":"fixture failure","data":null}'),
    );
    final (:bridge, :http) = _replay([failing, 'S04-page1']);
    final rooms = await bridge.recommended('bilibili', 1);
    expect([for (final request in http.requests) request.url.path].where((p) => p.endsWith('getListByAreaID')), [
      '/room/v1/Area/getListByAreaID',
      '/room/v1/Area/getListByAreaID',
    ]);
    final raw = _raw('S04-page1');
    final legacy = (_legacy('S04-page1') as List).cast<Map<String, dynamic>>();
    expect(
      [for (final room in rooms) roomProjection(room)],
      [for (final room in legacy) _expected(room, raw[room['roomId']]!)],
    );
  });

  test('recommend page 2 asks for page=2 after page 1 (legacy page numbers)', () async {
    final (:bridge, :http) = _replay(['S03-page1']);
    // Page 2 has no sample: the bridge walks page 1, then requests page 2.
    await expectLater(bridge.recommended('bilibili', 2), throwsA(isA<StateError>()));
    final pages = [
      for (final request in http.requests)
        if (request.url.path.endsWith('getListByAreaID')) request.url.queryParameters['page'],
    ];
    expect(pages, ['1', '2']);
  });
}
