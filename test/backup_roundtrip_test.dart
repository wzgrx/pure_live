import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/services/settings/iptv_settings_controller.dart';
import 'package:pure_live/common/services/settings/backup_controller.dart';

Map<String, dynamic> detached(Map<String, dynamic> data) => jsonDecode(jsonEncode(data)) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('backup-roundtrip-');
    Hive.init(directory.path);
    await HivePrefUtil.init();
  });
  tearDown(() async {
    Get.deleteAll(force: true);
    Get.reset();
    await Hive.box('app_settings').clear();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<SettingsService> initialize() async {
    Get.testMode = true;
    Get.put(IptvSettingsController(), permanent: true);
    final settings = Get.put(SettingsService());
    await settings.font.ensureInitialized();
    return settings;
  }

  for (final version in [2, 3]) {
    test('v$version complete backup roundtrip preserves omitted credentials', () async {
      final settings = await initialize();
      final backup = settings.backup;
      final source = detached(backup.exportAllSettings());
      source['backupVersion'] = version;
      source['app']['enableBackgroundPlay'] = true;
      source['volume']['roomVolumes'] = {'bilibili:123': 0.7};
      source['tags'] = {
        'tags': [
          {'id': 'kept', 'name': 'Roundtrip', 'order': 0},
        ],
        'roomTagsMap': {
          'bilibili:123': ['kept'],
        },
      };
      source['history']['historyRooms'] = [
        {'roomId': '123', 'platform': 'bilibili', 'title': 'Roundtrip'},
      ];
      backup.importAllSettings(source);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final expected = detached(backup.exportAllSettings());
      settings.app.enableBackgroundPlay.value = false;
      settings.vol.roomVolumes = {};
      settings.tagManagement.tags.clear();
      settings.cookieManager.twitchCookie.value = 'local-fixture-cookie';
      settings.webdav.currentWebDavConfig.value = 'local-fixture-config';
      final file = File('${directory.path}/v$version.json')..writeAsStringSync(jsonEncode(source));
      expect(backup.recover(file), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(detached(backup.exportAllSettings()), expected);
      expect(settings.cookieManager.twitchCookie.value, 'local-fixture-cookie');
      expect(settings.webdav.currentWebDavConfig.value, 'local-fixture-config');
      await Hive.box('app_settings').flush();
      expect(HivePrefUtil.getBool('enableBackgroundPlay'), isTrue);
      expect(jsonDecode(HivePrefUtil.getString('roomVolumes')!), {'bilibili:123': 0.7});
    });
  }

  test('complete legacy backup restores all settings and known export keys are recognizable', () async {
    final settings = await initialize();
    final backup = settings.backup;
    final source = detached(backup.exportAllSettings(includeSensitiveData: true));
    final legacy = <String, dynamic>{};
    for (final entry in source.entries) {
      if (entry.value is! Map) continue;
      if (entry.key == 'tags') {
        legacy['custom_tags_data'] = entry.value;
      } else {
        legacy.addAll(Map<String, dynamic>.from(entry.value));
      }
      for (final field in (entry.value as Map).entries) {
        expect(
          () => BackupController.validateBackupIdentity({
            'backupVersion': 3,
            entry.key: {field.key: field.value},
          }),
          returnsNormally,
          reason: '${entry.key}.${field.key}',
        );
      }
    }
    legacy['enableBackgroundPlay'] = true;
    legacy['twitchCookie'] = 'legacy-fixture-cookie';
    backup.importAllSettings(legacy);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final expected = detached(backup.exportAllSettings(includeSensitiveData: true));
    settings.app.enableBackgroundPlay.value = false;
    settings.cookieManager.twitchCookie.value = '';
    backup.importAllSettings(legacy);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(detached(backup.exportAllSettings(includeSensitiveData: true)), expected);
    expect(settings.cookieManager.twitchCookie.value, 'legacy-fixture-cookie');
  });

  test('late invalid backup field preserves every registered section', () async {
    final settings = await initialize();
    final backup = settings.backup;
    final before = detached(backup.exportAllSettings(includeSensitiveData: true));
    final invalid = detached(before);
    invalid['app']['enableBackgroundPlay'] = !settings.app.enableBackgroundPlay.value;
    invalid['tags'] = {
      'roomTagsMap': {
        'room': [42],
      },
    };
    final file = File('${directory.path}/invalid.json')..writeAsStringSync(jsonEncode(invalid));
    expect(backup.recover(file), isFalse);
    expect(detached(backup.exportAllSettings(includeSensitiveData: true)), before);
  });
}
