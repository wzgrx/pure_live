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
    directory = await Directory.systemTemp.createTemp('twitcasting-migration-');
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
      expect(controller.sites.map((s) => s.id), contains('twitcasting'));
      expect(
        controller.buildSearchUrl('twitcasting', 'a & b'),
        'https://twitcasting.tv/search/text/?tw_search_query=a%20%26%20b',
      );
    } finally {
      controller.onClose();
    }
  });

  test('catalog upgrade appends TwitCasting once and preserves disabled platforms and order', () async {
    await HivePrefUtil.setInt('siteCatalogMigration', 4);
    await HivePrefUtil.setStringList('hotAreasList', ['huya', 'acfun']);
    final settings = Get.put(FavoriteRoomController());
    expect(settings.hotAreasList, [
      'huya',
      'acfun',
      'twitcasting',
      'missevan',
      'inke',
      'kilakila',
      'huajiao',
      'openrec',
      'ttinglive',
      'xiaohongshu',
    ]);
    expect(settings.siteCatalogMigration.value, 12);
    settings.hotAreasList.remove('twitcasting');
    settings.onInit();
    expect(settings.hotAreasList, [
      'huya',
      'acfun',
      'missevan',
      'inke',
      'kilakila',
      'huajiao',
      'openrec',
      'ttinglive',
      'xiaohongshu',
    ]);
    await Hive.box<dynamic>('app_settings').flush();
    expect(HivePrefUtil.getStringList('hotAreasList'), [
      'huya',
      'acfun',
      'missevan',
      'inke',
      'kilakila',
      'huajiao',
      'openrec',
      'ttinglive',
      'xiaohongshu',
    ]);
  });

  test('audience upgrade adds only TwitCasting and respects subsequent disabling', () async {
    await HivePrefUtil.setInt('audienceMetricMigration', 4);
    await HivePrefUtil.setStringList('realOnlinePlatforms', ['twitch']);
    final settings = Get.put(AppSettingsController());
    expect(settings.realOnlinePlatforms, ['twitch', 'twitcasting', 'openrec', 'ttinglive']);
    expect(settings.audienceMetricMigration.value, 7);
    settings.setRealOnlineEnabledFor('twitcasting', false);
    settings.onInit();
    expect(settings.realOnlinePlatforms, ['twitch', 'openrec', 'ttinglive']);
    expect(AppSettingsController.normalizeRealOnlinePlatforms([' TWITCASTING ', 'huya']), ['twitcasting']);
  });
}
