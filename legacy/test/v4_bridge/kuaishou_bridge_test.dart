// The 3.3.x bridge must reproduce the legacy output for Kuaishou lists
// (docs/adr/0012-legacy-bridge.md, rule 3). Only the categories are bridged.
//
// Area rooms and recommendations stay on the legacy code: their legacy cards
// carry the broadcast's liveStreamId (`link`, `danmakuData`) and its signed
// `playUrls` (`data`), which a v4 RoomCard does not have. The legacy room
// entry reads them from the opened card (kuaishou_site.dart:394-400,
// 433-441: an offline room page with a card that still has streams plays
// the card as a recording). Search stays too: its cards carry `followers`
// (`counts.fan`) and the banned state, which a RoomCard does not have.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/testing.dart';
import 'package:pure_live/core/site/v4_bridge/v4_bridge.dart';

const _root = '../fixtures/kuaishou';

/// Recorded `category/data` pages by first-level category, in page order.
const _recorded = {
  '1': ['S01-category-type1-p1', 'S01-category-type1-p2'],
  '2': ['S01-category-type2-p1'],
  '3': ['S01-category-type3-p1'],
  '4': ['S01-category-type4-p1'],
  '5': ['S01-category-type5-p1', 'S01-category-type5-p2'],
  '6': ['S01-category-type6-p1'],
  '7': ['S01-category-type7-p1'],
  '8': ['S01-category-type8-p1'],
};

/// The frozen legacy output (`expected.json` → `value`).
Map<String, dynamic> _legacy(String sample) =>
    (jsonDecode(File('$_root/$sample/expected.json').readAsStringSync()) as Map<String, dynamic>)['value']
        as Map<String, dynamic>;

/// An empty last page: categories 1-4 go on past their recorded pages, so
/// their walks end on this synthetic answer (legacy stopped on it too: fewer
/// than `size` areas).
ReplaySample _end(String type, int page) => ReplaySample(
  method: 'GET',
  url: Uri.https('live.kuaishou.com', '/live_api/category/data', {'type': type, 'page': '$page', 'size': '30'}),
  status: 200,
  bytes: utf8.encode('{"data":{"list":[],"hasMore":false}}'),
);

void main() {
  test('categories: the eight fixed categories with the legacy areas, ids and posters', () async {
    final http = ReplayHttp([
      for (final pages in _recorded.values)
        for (final sample in pages) ReplaySample.load('$_root/$sample'),
      for (final type in ['1', '2', '3', '4']) _end(type, _recorded[type]!.length + 1),
    ]);
    final categories = await V4Bridge.withHttp(http).categories('kuaishou');
    // Legacy site:54-63.
    expect(
      {for (final category in categories) category.id: category.name},
      {'1': '热门', '2': '网游', '3': '单机', '4': '手游', '5': '棋牌', '6': '娱乐', '7': '综合', '8': '文化'},
    );
    for (final category in categories) {
      final pages = _recorded[category.id]!;
      expect(
        [for (final area in category.children) area.toJson()],
        [for (final sample in pages) ...(_legacy(sample)['getSubCategores'] as List).cast<Map<String, dynamic>>()],
        reason: 'category ${category.id}',
      );
      // Categories 5-8 end on recorded pages: the legacy traversal is recorded.
      final traversal = _legacy(pages.last)['getAllSubCategores'] as Map<String, dynamic>?;
      if (traversal != null) {
        expect([for (final area in category.children) area.areaId], traversal['areaIds']);
      }
    }
    // Each category walks its pages in order and stops at `hasMore: false`
    // (spec §2; legacy continued while a page had >= 30 areas, which asked
    // for the same pages here).
    expect(
      [
        for (final request in http.requests)
          '${request.url.queryParameters['type']}/${request.url.queryParameters['page']}',
      ],
      [
        for (final MapEntry(key: type, value: pages) in _recorded.entries) ...[
          for (var page = 1; page <= pages.length; page++) '$type/$page',
          if (int.parse(type) <= 4) '$type/${pages.length + 1}',
        ],
      ],
    );
  });
}
