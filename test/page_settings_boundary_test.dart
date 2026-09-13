import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/page_settings_controller.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pure-live-page-boundary-');
    Hive.init(directory.path);
    await HivePrefUtil.init();
  });

  setUp(() async {
    Get.testMode = true;
    await HivePrefUtil.clear();
  });

  tearDown(() async {
    Get.reset();
    await HivePrefUtil.flush();
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('page-size values share one sorted unique bounded contract', () {
    expect(PageSettingsController.minPageSize, 1);
    expect(PageSettingsController.maxPageSize, 100);
    expect(PageSettingsController.normalizePageSizeOptions([80, 12, 12, 0, 101, -1]), [12, 80]);
    expect(PageSettingsController.normalizePageSizeOptions([0, 101]), PageSettingsController.getInitPageSizeOptions());
    expect(PageSettingsController.normalizeDefaultPageSize(24, [12, 24]), 24);
    expect(PageSettingsController.normalizeDefaultPageSize(13, [12, 24]), 12);
  });

  test('persisted options and default are repaired before observers use them', () async {
    await HivePrefUtil.setString('page_size_options_raw', '[80,0,12,12,101]');
    await HivePrefUtil.setInt('page_default_size', 101);

    final page = Get.put(PageSettingsController());

    expect(page.pageSizeOptions, [12, 80]);
    expect(page.defaultPageSize.value, 12);
    await Future<void>.delayed(Duration.zero);
    await HivePrefUtil.flush();
    expect(HivePrefUtil.getString('page_size_options_raw'), '[12,80]');
    expect(HivePrefUtil.getInt('page_default_size'), 12);
  });

  test('backup parsing normalizes values and preserves strict collection types', () {
    final parsed = PageSettingsController.parseConfig({
      'pageSizeOptions': [80, 0, 12, 12, 101],
      'defaultPageSize': 101,
    });
    expect(parsed['showPageSizeSelector'], isTrue);
    expect(parsed['showGotoButton'], isTrue);
    expect(parsed['pageSizeOptions'], [12, 80]);
    expect(parsed['defaultPageSize'], 12);
    expect(parsed['pageSizeOptionsRaw'], '[12,80]');

    final extracted = PageSettingsController.extractConfig({
      'page': {
        'pageSizeOptions': [100, -1, 40, 40],
        'defaultPageSize': 40,
      },
    });
    expect(extracted['pageSizeOptions'], [40, 100]);
    expect(extracted['defaultPageSize'], 40);

    expect(
      () => PageSettingsController.parseConfig({
        'pageSizeOptions': [12, '24'],
      }),
      throwsA(isA<TypeError>()),
    );
    expect(() => PageSettingsController.parseConfig({'defaultPageSize': '12'}), throwsA(isA<TypeError>()));
  });

  test('save and export do not mutate callers or leak invalid direct writes', () {
    final page = Get.put(PageSettingsController());
    final caller = [80, 12, 12, 0, 101];

    page.saveAllPageSizeOptions(caller);

    expect(caller, [80, 12, 12, 0, 101]);
    expect(page.pageSizeOptions, [12, 80]);
    expect(page.defaultPageSize.value, 12);

    page.pageSizeOptions.assignAll([0, 101]);
    page.defaultPageSize.value = 999;
    final exported = page.toJson();
    expect(exported['pageSizeOptions'], PageSettingsController.getInitPageSizeOptions());
    expect(exported['defaultPageSize'], PageSettingsController.getInitPageSizeOptions().first);
  });
}
