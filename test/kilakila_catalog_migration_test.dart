import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/favorite_room_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/search/search_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  setUpAll(() async {
    folder = await Directory.systemTemp.createTemp('kilakila-catalog-migration-');
    Hive.init(folder.path);
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
    await folder.delete(recursive: true);
  });

  test('version seven adds Kilakila and later Huajiao and disabling survives disk reopen', () async {
    await HivePrefUtil.setInt('siteCatalogMigration', 7);
    await HivePrefUtil.setStringList('hotAreasList', ['huya', 'inke']);
    final settings = Get.put(FavoriteRoomController());
    expect(settings.hotAreasList, [
      'huya',
      'inke',
      'kilakila',
      'huajiao',
      'openrec',
      'ttinglive',
      'xiaohongshu',
      'niconico',
    ]);
    expect(settings.siteCatalogMigration.value, 13);
    settings.hotAreasList.remove('kilakila');
    settings.onInit();
    expect(settings.hotAreasList, ['huya', 'inke', 'huajiao', 'openrec', 'ttinglive', 'xiaohongshu', 'niconico']);
    await Hive.box<dynamic>('app_settings').flush();
    Get.reset();
    await Hive.close();
    await HivePrefUtil.init();
    final reopened = Get.put(FavoriteRoomController());
    expect(reopened.siteCatalogMigration.value, 13);
    expect(reopened.hotAreasList, ['huya', 'inke', 'huajiao', 'openrec', 'ttinglive', 'xiaohongshu', 'niconico']);
  });

  test('backup normalization retains Kilakila order and does not duplicate it', () async {
    final settings = Get.put(FavoriteRoomController());
    settings.fromJson({
      'hotAreasList': [' KILAKILA ', 'huya', 'kilakila'],
      'preferPlatform': ' KILAKILA ',
      'favoriteRooms': [],
      'favoriteAreas': [],
    });
    expect(settings.hotAreasList, ['kilakila', 'huya']);
    expect(settings.preferPlatform.value, 'kilakila');
    final json = settings.toJson();
    expect(json['hotAreasList'], ['kilakila', 'huya']);
  });

  test('actual search flow reports missing capability and does not fall back to web', () async {
    Get.put(SettingsService());
    final controller = SearchController();
    try {
      controller.index.value = controller.sites.indexWhere((site) => site.id == 'kilakila') + 1;
      expect(controller.index.value, greaterThan(0));
      expect(controller.canOpenWebSearch, isFalse);
      expect(controller.capabilityText, 'search_coverage_unavailable');
      expect(() => controller.buildSearchUrl('kilakila', 'example'), throwsStateError);
      controller.searchController.text = 'example';
      await controller.doSearch();
      expect(controller.errorMessage.value, 'search_coverage_unavailable');
      expect(controller.loading.value, isFalse);
      expect(controller.pendingSiteCount.value, 0);
      expect(controller.hasMore.value, isFalse);
    } finally {
      controller.onClose();
    }
  });
}
