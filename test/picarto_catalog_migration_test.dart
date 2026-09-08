import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/app_settings_controller.dart';
import 'package:pure_live/common/services/settings/favorite_room_controller.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/modules/search/search_controller.dart';
import 'package:pure_live/get/get.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('picarto-migration-');
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

  test('search uses the verified website route and encodes free-form input', () {
    Get.put(SettingsService());
    final controller = SearchController();
    try {
      expect(controller.sites.map((s) => s.id), contains('picarto'));
      expect(controller.buildSearchUrl('picarto', 'a & b'), 'https://picarto.tv/search?q=a%20%26%20b');
    } finally {
      controller.onClose();
    }
  });

  test('catalog upgrade appends Picarto once and preserves disabled platforms and order', () async {
    await HivePrefUtil.setInt('siteCatalogMigration', 3);
    await HivePrefUtil.setStringList('hotAreasList', ['huya', 'acfun']);
    final settings = Get.put(FavoriteRoomController());
    expect(settings.hotAreasList, [
      'huya',
      'acfun',
      'picarto',
      'twitcasting',
      'missevan',
      'inke',
      'kilakila',
      'huajiao',
    ]);
    expect(settings.siteCatalogMigration.value, 9);
    settings.hotAreasList.remove('picarto');
    settings.onInit();
    expect(settings.hotAreasList, ['huya', 'acfun', 'twitcasting', 'missevan', 'inke', 'kilakila', 'huajiao']);
    await Hive.box<dynamic>('app_settings').flush();
    expect(HivePrefUtil.getStringList('hotAreasList'), [
      'huya',
      'acfun',
      'twitcasting',
      'missevan',
      'inke',
      'kilakila',
      'huajiao',
    ]);
  });

  test('audience upgrade adds Picarto and later catalog entries and respects subsequent disabling', () async {
    await HivePrefUtil.setInt('audienceMetricMigration', 3);
    await HivePrefUtil.setStringList('realOnlinePlatforms', ['twitch']);
    final settings = Get.put(AppSettingsController());
    expect(settings.realOnlinePlatforms, ['twitch', 'picarto', 'twitcasting']);
    expect(settings.audienceMetricMigration.value, 5);
    settings.setRealOnlineEnabledFor('picarto', false);
    settings.onInit();
    expect(settings.realOnlinePlatforms, ['twitch', 'twitcasting']);
    expect(AppSettingsController.normalizeRealOnlinePlatforms([' PICARTO ', 'huya']), ['picarto']);
  });
}
