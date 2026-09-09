import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/favorite_room_controller.dart';
import 'package:pure_live/common/services/settings/app_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/search/search_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('missevan-integration-');
    Hive.init(directory.path);
    await HivePrefUtil.init();
  });
  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
  });
  tearDown(Get.reset);
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('migration appends Missevan and subsequent platforms, retains hidden choices and persists disabling', () async {
    await HivePrefUtil.setInt('siteCatalogMigration', 5);
    await HivePrefUtil.setStringList('hotAreasList', ['huya', 'twitcasting']);
    final controller = Get.put(FavoriteRoomController());
    expect(controller.hotAreasList, [
      'huya',
      'twitcasting',
      'missevan',
      'inke',
      'kilakila',
      'huajiao',
      'openrec',
      'ttinglive',
      'xiaohongshu',
    ]);
    expect(controller.siteCatalogMigration.value, 12);
    controller.hotAreasList.remove('missevan');
    controller.onInit();
    expect(controller.hotAreasList, [
      'huya',
      'twitcasting',
      'inke',
      'kilakila',
      'huajiao',
      'openrec',
      'ttinglive',
      'xiaohongshu',
    ]);
    await Hive.box<dynamic>('app_settings').flush();
    Get.reset();
    expect(Get.put(FavoriteRoomController()).hotAreasList, [
      'huya',
      'twitcasting',
      'inke',
      'kilakila',
      'huajiao',
      'openrec',
      'ttinglive',
      'xiaohongshu',
    ]);
  });

  test('heat-only platform never becomes a concurrent-viewer setting', () async {
    await HivePrefUtil.setInt('audienceMetricMigration', 5);
    await HivePrefUtil.setStringList('realOnlinePlatforms', ['twitch']);
    final controller = Get.put(AppSettingsController());
    expect(controller.realOnlinePlatforms, ['twitch', 'openrec', 'ttinglive']);
    expect(AppSettingsController.normalizeRealOnlinePlatforms(['missevan', 'twitch']), ['twitch']);
  });

  test('search selection explains missing capability and ends without requests or web fallback', () async {
    Get.put(SettingsService());
    final controller = SearchController();
    try {
      controller.index.value = controller.sites.indexWhere((s) => s.id == 'missevan') + 1;
      expect(controller.index.value, greaterThan(0));
      expect(controller.canOpenWebSearch, isFalse);
      expect(controller.capabilityText, 'search_coverage_unavailable');
      expect(() => controller.buildSearchUrl('missevan', 'example'), throwsStateError);
      controller.searchController.text = 'example';
      await controller.doSearch();
      expect(controller.errorMessage.value, 'search_coverage_unavailable');
      expect(controller.hasMore.value, isFalse);
      expect(controller.loading.value, isFalse);
      expect(controller.pendingSiteCount.value, 0);
    } finally {
      controller.onClose();
    }
  });
}
