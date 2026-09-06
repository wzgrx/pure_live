import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/common/services/settings/app_settings_controller.dart';
import 'package:pure_live/common/services/settings/backup_controller.dart';
import 'package:pure_live/common/services/settings/theme_settings_controller.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('backup-validation-');
    Hive.init(directory.path);
    await HivePrefUtil.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  tearDown(Get.reset);

  test('section validation preserves null, omitted and forward-compatible fields', () {
    final data = <String, dynamic>{'app': null, 'theme': <String, dynamic>{}, 'futureSection': 42};
    expect(() => BackupController.validateSectionStructure(data), returnsNormally);
    expect(data['futureSection'], 42);
  });

  test('late optional sections and non-string keys are validated before import', () {
    for (final name in ['cookie', 'webdav', 'tags', 'page', 'refresh']) {
      expect(() => BackupController.validateSectionStructure({name: []}), throwsFormatException);
      expect(
        () => BackupController.validateSectionStructure({
          name: {1: true},
        }),
        throwsFormatException,
      );
    }
  });

  test('a malformed later section does not mutate earlier app settings', () {
    final app = Get.put(AppSettingsController());
    Get.put(ThemeSettingsController());
    app.enableBackgroundPlay.value = true;
    final before = app.toJson();
    final file = File('${directory.path}/malformed.json')
      ..writeAsStringSync(
        jsonEncode({
          'backupVersion': 3,
          'app': {'enableBackgroundPlay': false},
          'theme': 'invalid section',
        }),
      );
    expect(BackupController().recover(file), isFalse);
    expect(app.toJson(), before);
  });
}
