import 'dart:convert';
import 'dart:io';

import 'package:pure_live/common/services/settings/volume_settings_controller.dart';

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

  test('a malformed later section does not mutate earlier app settings', () async {
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
    expect(await BackupController().recover(file), isFalse);
    expect(app.toJson(), before);
  });
  test('volume parser retains object and legacy JSON forms', () {
    for (final value in [
      <String, dynamic>{'room': 1},
      '{"room":1}',
    ]) {
      expect(VolumeSettingsController.parseRoomVolumes(value), {'room': 1.0});
    }
    expect(VolumeSettingsController.parseRoomVolumes(null), isEmpty);
  });

  test('malformed volume data preserves all volume settings', () {
    final volume = Get.put(VolumeSettingsController());
    volume.roomVolumes = {'kept': 0.6};
    volume.defaultMobileVolume.value = 0.7;
    for (final invalid in [
      42,
      [],
      'broken',
      {'room': 'bad'},
      {1: 0.3},
      {'room': double.nan},
    ]) {
      expect(() => volume.fromJson({'defaultMobileVolume': 0.2, 'roomVolumes': invalid}), throwsFormatException);
      expect(volume.defaultMobileVolume.value, 0.7);
      expect(volume.roomVolumes, {'kept': 0.6});
    }
  });

  test('bad late volume is rejected before any app import in current and legacy backups', () {
    final app = Get.put(AppSettingsController());
    app.enableBackgroundPlay.value = true;
    final before = app.toJson();
    for (final data in <Map<String, dynamic>>[
      {
        'backupVersion': 3,
        'app': {'enableBackgroundPlay': false},
        'volume': {'roomVolumes': []},
      },
      {'enableBackgroundPlay': false, 'roomVolumes': []},
    ]) {
      expect(() => BackupController().importAllSettings(data), throwsFormatException);
      expect(app.toJson(), before);
    }
  });
  test('all simple sections preflight before app writes in legacy and versioned backups', () {
    final app = Get.put(AppSettingsController());
    app.enableBackgroundPlay.value = true;
    final before = app.toJson();
    final fields = <String, Map<String, dynamic>>{
      'theme': {'enableDynamicTheme': 'bad'},
      'font': {'fontSizeBodySmall': 'bad'},
      'exit': {'autoShutDownTime': 'bad'},
      'iptv': {'autoSyncHoursInterval': 'bad'},
      'startup': {'enableStartUp': 'bad'},
      'proxy': {'proxyPort': 'bad'},
      'refresh': {'autoRefreshInterval': 'bad'},
      'cookie': {'bilibiliUid': 'bad'},
    };
    for (final entry in fields.entries) {
      for (final data in <Map<String, dynamic>>[
        {
          'backupVersion': 3,
          'app': {'enableBackgroundPlay': false},
          entry.key: entry.value,
        },
        {'enableBackgroundPlay': false, ...entry.value},
      ]) {
        expect(() => BackupController().importAllSettings(data), throwsA(isA<TypeError>()), reason: entry.key);
        expect(app.toJson(), before, reason: entry.key);
      }
    }
  });

  test('direct theme import parses late fields before modifying early values', () {
    final theme = Get.put(ThemeSettingsController());
    theme.enableDynamicTheme.value = true;
    final before = theme.toJson();
    expect(() => theme.fromJson({'enableDynamicTheme': false, 'mainAxisSpacing': 'bad'}), throwsA(isA<TypeError>()));
    expect(theme.toJson(), before);
    final parsed = ThemeSettingsController.parseConfig({'mainAxisSpacing': 8, 'enableDynamicTheme': true});
    expect(parsed['mainAxisSpacing'], 8.0);
    expect(parsed['enableDynamicTheme'], true);
    expect(parsed['languageName'], '简体中文');
  });
  test('playback sections preflight malformed late values before any app writes', () {
    final app = Get.put(AppSettingsController());
    app.enableBackgroundPlay.value = true;
    final before = app.toJson();
    for (final entry in <String, Map<String, dynamic>>{
      'app': {
        'enableBackgroundPlay': false,
        'savedMenuIds': [42],
      },
      'danmaku': {'pipDanmakuNoEmojiMode': 'bad'},
      'player': {'portraitRoomOverrides': []},
      'windowSize': {'storedWidth': 900, 'windowsPip': 'bad'},
    }.entries) {
      final error = ['player', 'windowSize'].contains(entry.key) ? isA<FormatException>() : isA<TypeError>();
      for (final data in <Map<String, dynamic>>[
        {
          'backupVersion': 3,
          'app': {'enableBackgroundPlay': false},
          entry.key: entry.value,
        },
        {'enableBackgroundPlay': false, ...entry.value},
      ]) {
        expect(() => BackupController().importAllSettings(data), throwsA(error), reason: entry.key);
        expect(app.toJson(), before, reason: entry.key);
      }
    }
  });

  test('direct app import rejects invalid menu before changing background playback', () {
    final app = Get.put(AppSettingsController());
    app.enableBackgroundPlay.value = true;
    final before = app.toJson();
    expect(
      () => app.fromJson({
        'enableBackgroundPlay': false,
        'savedMenuIds': [42],
      }),
      throwsA(isA<TypeError>()),
    );
    expect(app.toJson(), before);
  });
  test('empty and unrelated JSON reject without resetting current settings', () {
    final app = Get.put(AppSettingsController());
    app.enableBackgroundPlay.value = true;
    final before = app.toJson();
    for (final data in <Map<String, dynamic>>[
      {},
      {'unrelated': 'document'},
      {'backupVersion': 3},
      {'backupVersion': 3, 'app': {}},
      {
        'backupVersion': 3,
        'app': {'unrelated': true},
      },
      {'backupVersion': 3, 'app': null},
      {'custom_tags_data': null},
      {'custom_tags_data': {}},
      {
        'backupVersion': '3',
        'app': {'enableBackgroundPlay': false},
      },
      {
        'backupVersion': -1,
        'app': {'enableBackgroundPlay': false},
      },
    ]) {
      expect(() => BackupController().importAllSettings(data), throwsFormatException, reason: '$data');
      expect(app.toJson(), before, reason: '$data');
    }
  });

  test('identity recognition preserves current, legacy and forward-compatible settings', () {
    for (final data in <Map<String, dynamic>>[
      {'enableBackgroundPlay': false},
      {'themeMode': 'Dark'},
      {
        'custom_tags_data': {'tags': []},
      },
      {'pipDanmaNoEmojiMode': true},
      {
        'backupVersion': 2,
        'windowSize': {'windowsPipX': 12},
      },
      {
        'backupVersion': 3,
        'danmaku': {'pipDanmaNoEmojiMode': true},
      },
      {
        'backupVersion': 3,
        'app': {'enableBackgroundPlay': null},
      },
      {
        'backupVersion': 99,
        'theme': {'language': '简体中文'},
        'futureSection': {'newFlag': 42},
      },
    ]) {
      expect(() => BackupController.validateBackupIdentity(data), returnsNormally, reason: '$data');
    }
  });
}
