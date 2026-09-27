// Opt-in real-network check of the 3.3.x v4 bridge through the legacy site
// interface (docs/adr/0012-legacy-bridge.md). PURELIVE_V4_BRIDGE_PROBE=1.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/core/site/douyu/douyu_site.dart';
import 'package:pure_live/core/site/v4_bridge/v4_bridge.dart';

void main() {
  final enabled = Platform.environment['PURELIVE_V4_BRIDGE_PROBE'] == '1';

  setUpAll(() => V4Bridge.instance = V4Bridge.withHttp(IoLiveHttp()));
  tearDownAll(() => V4Bridge.instance = null);

  test(
    'douyu lists and search through the bridge',
    () async {
      final site = DouyuSite();
      final categories = await site.getCategores(1, 0);
      final lol = categories.expand((c) => c.children).firstWhere((a) => a.areaName == '英雄联盟');
      stdout.writeln('categories ${categories.length}, areas ${categories.expand((c) => c.children).length}');
      final page1 = await site.getCategoryRooms(lol, page: 1);
      final page2 = await site.getCategoryRooms(lol, page: 2);
      stdout.writeln(
        'area ${lol.areaId}: page1 ${page1.length}, page2 ${page2.length}, overlap ${page1.map((r) => r.roomId).toSet().intersection(page2.map((r) => r.roomId).toSet()).length}',
      );
      final recommend1 = await site.getRecommendRooms(page: 1);
      final recommend2 = await site.getRecommendRooms(page: 2);
      stdout.writeln('recommend page1 ${recommend1.length}, page2 ${recommend2.length}');
      final search = await site.searchRooms('英雄联盟', page: 1, pageSize: 20);
      stdout.writeln(
        'search ${search.length}: ${search.take(3).map((r) => '${r.roomId} ${r.nick} ${r.liveStatus?.name} ${r.watching}').join(' | ')}',
      );
      final sample = page1.first;
      stdout.writeln(
        'card ${sample.roomId} "${sample.title}" ${sample.nick} avatar=${sample.avatar!.isNotEmpty} cover=${sample.cover!.isNotEmpty} ${sample.audienceMetricType?.name} ${sample.watching}',
      );
      expect(page1, isNotEmpty);
      expect(recommend1, isNotEmpty);
      expect(search, isNotEmpty);
      expect(lol, isA<LiveArea>());
    },
    skip: enabled ? false : 'Set PURELIVE_V4_BRIDGE_PROBE=1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
