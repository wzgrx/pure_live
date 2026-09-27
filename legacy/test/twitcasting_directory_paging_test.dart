import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/base/base_page_scroll_bone.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/site/twitcasting/twitcasting_api.dart';
import 'package:pure_live/core/site/twitcasting/twitcasting_site.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/area_rooms/area_rooms_controller.dart';
import 'package:pure_live/modules/popular/popular_controller.dart';
import 'package:pure_live/modules/popular/popular_grid_controller.dart';

class _Window {
  final calls = <Uri>[];
  var generation = 0;
  late final site = Site(
    id: Sites.twitcastingSite,
    name: 'TwitCasting',
    logo: '',
    liveSite: TwitcastingSite(
      api: TwitcastingApi(
        request: (uri, _) async {
          calls.add(uri);
          final template =
              (jsonDecode(File('test/fixtures/twitcasting/directory.json').readAsStringSync())['movies'] as List).single
                  as Map;
          return (
            status: 200,
            body: jsonEncode({
              'movies': List.generate(
                60,
                (i) => {
                  ...template,
                  'id': '${i + 1}',
                  'user_id': 'artist${generation}_$i',
                  'live_url': '/artist${generation}_$i/movie/${i + 1}',
                  'current_viewer_count': i == 0 ? null : 1000 - i,
                  'is_group': i == 0,
                },
              ),
            }),
          );
        },
      ),
    ),
  );
}

class _MobilePopular extends PopularServerFixedController {
  _MobilePopular(super.site) : super(fixedSize: 60);
  @override
  bool get usesDesktopPagination => false;
}

class _MobileArea extends AreaServerFixedController {
  _MobileArea(super.site, super.subCategory) : super(fixedSize: 60);
  @override
  bool get usesDesktopPagination => false;
}

class _DesktopPopular extends PopularServerFixedController {
  _DesktopPopular(super.site) : super(fixedSize: 60);
  @override
  bool get usesDesktopPagination => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('twitcasting-paging-');
    Hive.init(directory.path);
    await HivePrefUtil.init();
  });
  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    Get.put(SettingsService());
  });
  tearDown(Get.reset);
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('actual popular route uses a fixed window even for an 80-card client page', () async {
    final source = _Window();
    final owner = PopularController();
    addTearDown(owner.onClose);
    owner.initControllers([source.site]);
    final controller = Get.find<BasePageScrollAndStateBone<LiveRoom>>(tag: Sites.twitcastingSite);
    expect(controller, isA<PopularServerFixedController>());
    controller.pageSize.value = 80;
    await controller.loadData();
    expect(controller.pageError.value, false);
    expect(controller.list, hasLength(59));
    expect(controller.canLoadMore.value, false);
    expect(source.calls, hasLength(1));
    expect(source.calls.single.queryParameters['count'], '60');
  });

  test('mobile pages retain every eligible card from one snapshot and refresh replaces it', () async {
    final source = _Window();
    final controller = _MobilePopular(source.site)..pageSize.value = 20;
    addTearDown(controller.onClose);
    await controller.loadData();
    expect(controller.list, hasLength(20));
    await controller.loadMoreData();
    expect(controller.list, hasLength(40));
    await controller.loadMoreData();
    expect(controller.list, hasLength(59));
    expect(controller.list.map((r) => r.roomId).toSet(), hasLength(59));
    expect(controller.list.map((r) => r.roomId), contains('artist0_59'));
    expect(controller.canLoadMore.value, false);
    expect(source.calls, hasLength(1));
    source.generation++;
    await controller.refreshData();
    expect(source.calls, hasLength(2));
    expect(controller.list, hasLength(20));
    expect(controller.list.every((r) => r.roomId!.startsWith('artist1_')), true);
  });

  test('category paging forwards the full window and retains the category identity', () async {
    final source = _Window();
    final area = LiveArea(
      platform: Sites.twitcastingSite,
      areaId: '_system_channel_popular',
      areaType: 'directory',
      areaName: 'Popular',
    );
    final controller = _MobileArea(source.site, area)..pageSize.value = 20;
    addTearDown(controller.onClose);
    await controller.loadData();
    await controller.loadMoreData();
    await controller.loadMoreData();
    expect(controller.list, hasLength(59));
    expect(controller.list.every((r) => r.area == 'Popular'), true);
    expect(source.calls, hasLength(1));
    expect(source.calls.single.queryParameters, {'id': '_system_channel_popular', 'count': '60'});
    expect(controller.canLoadMore.value, false);
  });

  test('desktop pages and page-size changes use the same filtered window', () async {
    final source = _Window();
    final controller = _DesktopPopular(source.site)..pageSize.value = 20;
    addTearDown(controller.onClose);
    await controller.loadData();
    await controller.goToPage(3);
    expect(controller.list, hasLength(19));
    expect(controller.canLoadMore.value, false);
    controller.setPageSize(80);
    await controller.loadData();
    expect(controller.list, hasLength(59));
    expect(controller.canLoadMore.value, false);
    expect(source.calls, hasLength(1));
  });
}
