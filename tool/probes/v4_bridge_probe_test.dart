// Opt-in real-network check of the 3.3.x v4 bridge through the legacy site
// interface (docs/adr/0012-legacy-bridge.md). PURELIVE_V4_BRIDGE_PROBE=1.
//
// Entry points that are not wired (they stay on the legacy code) are called
// on the bridge directly and marked "v4 only", so their numbers are on record.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart' show NeedsLogin, RateLimited, RiskControl, SiteError;
import 'package:live_net/live_net.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/site/bilibili/bilibili_site.dart';
import 'package:pure_live/core/site/douyin/douyin_site.dart';
import 'package:pure_live/core/site/douyu/douyu_site.dart';
import 'package:pure_live/core/site/kuaishou/kuaishou_site.dart';
import 'package:pure_live/core/site/v4_bridge/v4_bridge.dart';

void main() {
  final enabled = Platform.environment['PURELIVE_V4_BRIDGE_PROBE'] == '1';
  final skip = enabled ? false : 'Set PURELIVE_V4_BRIDGE_PROBE=1';
  const timeout = Timeout(Duration(minutes: 3));

  // A probe is a test outside test/, which the analyzer does not know.
  // ignore: invalid_use_of_visible_for_testing_member
  setUpAll(() => V4Bridge.instance = V4Bridge.withHttp(IoLiveHttp()));
  // ignore: invalid_use_of_visible_for_testing_member
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
        'area ${lol.areaId}: page1 ${page1.length}, page2 ${page2.length}, overlap ${_overlap(page1, page2)}',
      );
      final recommend1 = await site.getRecommendRooms(page: 1);
      final recommend2 = await site.getRecommendRooms(page: 2);
      stdout.writeln('recommend page1 ${recommend1.length}, page2 ${recommend2.length}');
      final search = await site.searchRooms('英雄联盟', page: 1, pageSize: 20);
      stdout.writeln(
        'search ${search.length}: ${search.take(3).map((r) => '${r.roomId} ${r.nick} ${r.liveStatus?.name} ${r.watching}').join(' | ')}',
      );
      _card(page1.first);
      expect(page1, isNotEmpty);
      expect(recommend1, isNotEmpty);
      expect(search, isNotEmpty);
      expect(lol, isA<LiveArea>());
    },
    skip: skip,
    timeout: timeout,
  );

  test(
    'bilibili lists through the bridge',
    () async {
      final site = BiliBiliSite();
      final categories = await site.getCategores(1, 0);
      final areas = categories.expand((c) => c.children).toList();
      final lol = areas.firstWhere((a) => a.areaName == '英雄联盟');
      stdout.writeln('bilibili categories ${categories.length}, areas ${areas.length}');
      // Guests are refused area pages with -352 (DIAGNOSIS); either outcome is reported.
      final area1 = await _rooms(() => site.getCategoryRooms(lol, page: 1));
      final area2 = await _rooms(() => site.getCategoryRooms(lol, page: 2));
      stdout.writeln('bilibili area ${lol.areaType}/${lol.areaId}: page1 ${area1.text}, page2 ${area2.text}');
      if (area1.error != null) expect(area1.error, isA<RiskControl>().having((e) => '$e', 'text', contains('-352')));
      final recommend1 = await site.getRecommendRooms(page: 1);
      final recommend2 = await site.getRecommendRooms(page: 2);
      stdout.writeln(
        'bilibili recommend page1 ${recommend1.length}, page2 ${recommend2.length}, overlap ${_overlap(recommend1, recommend2)}',
      );
      final search = await _rooms(() => V4Bridge.instance.search('bilibili', '英雄联盟', 1));
      stdout.writeln('bilibili search (v4 only): ${search.text}');
      _card(recommend1.first);
      expect(areas, isNotEmpty);
      expect(recommend1, isNotEmpty);
    },
    skip: skip,
    timeout: timeout,
  );

  test(
    'douyin lists through the bridge',
    () async {
      final site = DouyinSite();
      final categories = await site.getCategores(1, 0);
      final areas = categories.expand((c) => c.children).toList();
      final shooter = areas.firstWhere((a) => a.areaName == '射击游戏', orElse: () => areas[1]);
      stdout.writeln('douyin categories ${categories.length}, areas ${areas.length}');
      final page1 = await site.getCategoryRooms(shooter, page: 1);
      final page2 = await site.getCategoryRooms(shooter, page: 2);
      stdout.writeln(
        'douyin area ${shooter.areaId}: page1 ${page1.length}, page2 ${page2.length}, overlap ${_overlap(page1, page2)}',
      );
      final recommend1 = await site.getRecommendRooms(page: 1);
      final recommend2 = await site.getRecommendRooms(page: 2);
      stdout.writeln('douyin recommend page1 ${recommend1.length}, page2 ${recommend2.length}');
      // Anonymous live search is refused (2483): NeedsLogin is the expected answer.
      final search = await _rooms(() => V4Bridge.instance.search('douyin', '和平精英', 1));
      stdout.writeln('douyin search (v4 only): ${search.text}');
      if (search.error != null) expect(search.error, isA<NeedsLogin>());
      _card(page1.first);
      expect(page1, isNotEmpty);
      expect(recommend1, isNotEmpty);
    },
    skip: skip,
    timeout: timeout,
  );

  test(
    'kuaishou categories through the bridge',
    () async {
      final site = KuaishowSite();
      final categories = await site.getCategores(1, 0);
      final areas = categories.expand((c) => c.children).toList();
      stdout.writeln(
        'kuaishou categories ${categories.length}, areas ${areas.length} '
        '(${[for (final c in categories) '${c.name} ${c.children.length}'].join(', ')})',
      );
      final wzry = areas.firstWhere((a) => a.areaId == '1001');
      final page1 = await V4Bridge.instance.areaRooms('kuaishou', wzry, 1);
      final page2 = await V4Bridge.instance.areaRooms('kuaishou', wzry, 2);
      stdout.writeln(
        'kuaishou area 1001 (v4 only): page1 ${page1.length}, page2 ${page2.length}, overlap ${_overlap(page1, page2)}',
      );
      final recommend = await V4Bridge.instance.recommended('kuaishou', 1);
      stdout.writeln('kuaishou recommend (v4 only): ${recommend.length}');
      // Author search is rate limited per endpoint: one request, RateLimited passes.
      final search = await _rooms(() => V4Bridge.instance.search('kuaishou', '王者荣耀', 1));
      stdout.writeln('kuaishou search (v4 only): ${search.text}');
      if (search.error != null) expect(search.error, isA<RateLimited>());
      expect(areas, isNotEmpty);
    },
    skip: skip,
    timeout: timeout,
  );
}

int _overlap(List<LiveRoom> a, List<LiveRoom> b) =>
    a.map((r) => r.roomId).toSet().intersection(b.map((r) => r.roomId).toSet()).length;

/// The rooms of [call], or the platform error it failed with.
Future<({List<LiveRoom> rooms, SiteError? error, String text})> _rooms(Future<List<LiveRoom>> Function() call) async {
  try {
    final rooms = await call();
    return (rooms: rooms, error: null, text: '${rooms.length} rooms');
  } on SiteError catch (error) {
    return (rooms: const <LiveRoom>[], error: error, text: '$error');
  }
}

void _card(LiveRoom room) => stdout.writeln(
  'card ${room.platform}/${room.roomId} "${room.title}" ${room.nick} avatar=${room.avatar!.isNotEmpty} '
  'cover=${room.cover!.isNotEmpty} area=${room.area} ${room.audienceMetricType?.name} ${room.watching} '
  'online=${room.onlineViewers} total=${room.totalViewers}',
);
