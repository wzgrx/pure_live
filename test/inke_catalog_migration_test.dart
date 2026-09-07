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
    folder = await Directory.systemTemp.createTemp('inke-catalog-migration-');
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

  test('version six adds only Inke and disabling survives disk reopen', () async {
    await HivePrefUtil.setInt('siteCatalogMigration', 6);
    await HivePrefUtil.setStringList('hotAreasList', ['huya', 'missevan']);
    final settings = Get.put(FavoriteRoomController());
    expect(settings.hotAreasList, ['huya', 'missevan', 'inke']);
    expect(settings.siteCatalogMigration.value, 7);
    settings.hotAreasList.remove('inke');
    settings.onInit();
    expect(settings.hotAreasList, ['huya', 'missevan']);
    await Hive.box<dynamic>('app_settings').flush();
    Get.reset();
    await Hive.close();
    await HivePrefUtil.init();
    final reopened = Get.put(FavoriteRoomController());
    expect(reopened.siteCatalogMigration.value, 7);
    expect(reopened.hotAreasList, ['huya', 'missevan']);
  });

  test('backup normalization retains Inke order and does not duplicate it', () async {
    final settings = Get.put(FavoriteRoomController());
    settings.fromJson({
      'hotAreasList': [' INKE ', 'huya', 'inke'],
      'preferPlatform': ' INKE ',
      'favoriteRooms': [],
      'favoriteAreas': [],
    });
    expect(settings.hotAreasList, ['inke', 'huya']);
    expect(settings.preferPlatform.value, 'inke');
    final json = settings.toJson();
    expect(json['hotAreasList'], ['inke', 'huya']);
  });

  test('actual search flow reports missing capability and does not fall back to web', () async {
    Get.put(SettingsService());
    final controller = SearchController();
    try {
      controller.index.value = controller.sites.indexWhere((site) => site.id == 'inke') + 1;
      expect(controller.index.value, greaterThan(0));
      expect(controller.canOpenWebSearch, isFalse);
      expect(controller.capabilityText, 'search_coverage_unavailable');
      expect(() => controller.buildSearchUrl('inke', 'example'), throwsStateError);
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
