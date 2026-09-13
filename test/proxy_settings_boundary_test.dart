import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/proxy_settings_controller.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pure-live-proxy-boundary-');
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

  test('current and legacy proxy sections share one strict endpoint contract', () {
    final parsed = ProxySettingsController.parseConfig({
      'proxyHost': ' 127。0．0。1 ',
      'proxyPort': 0,
      'appProxyHost': ' ［::1］ ',
      'appProxyPort': 65536,
    });
    expect(parsed['proxyHost'], '127.0.0.1');
    expect(parsed['proxyPort'], ProxySettingsController.defaultProxyPort);
    expect(parsed['appProxyHost'], '[::1]');
    expect(parsed['appProxyPort'], ProxySettingsController.defaultProxyPort);

    final extracted = ProxySettingsController.extractConfig({
      'proxy': {'proxyHost': ' localhost ', 'proxyPort': -3, 'appProxyHost': ' proxy.example ', 'appProxyPort': 65535},
    });
    expect(extracted['proxyHost'], 'localhost');
    expect(extracted['proxyPort'], ProxySettingsController.defaultProxyPort);
    expect(extracted['appProxyHost'], 'proxy.example');
    expect(extracted['appProxyPort'], 65535);

    for (final field in ['proxyHost', 'appProxyHost']) {
      expect(() => ProxySettingsController.parseConfig({field: 42}), throwsA(isA<TypeError>()));
    }
    for (final field in ['proxyPort', 'appProxyPort']) {
      expect(() => ProxySettingsController.parseConfig({field: '7897'}), throwsA(isA<TypeError>()));
    }
  });

  test('persisted endpoints are repaired before any proxy observer is installed', () async {
    await HivePrefUtil.setString('proxyHost', ' 127。0．0。1 ');
    await HivePrefUtil.setInt('proxyPort', -1);
    await HivePrefUtil.setString('appProxyHost', ' ［::1］ ');
    await HivePrefUtil.setInt('appProxyPort', 90000);

    final proxy = Get.put(ProxySettingsController());

    expect(proxy.proxyHost.value, '127.0.0.1');
    expect(proxy.proxyPort.value, ProxySettingsController.defaultProxyPort);
    expect(proxy.appProxyHost.value, '[::1]');
    expect(proxy.appProxyPort.value, ProxySettingsController.defaultProxyPort);
    await Future<void>.delayed(Duration.zero);
    await HivePrefUtil.flush();
    expect(HivePrefUtil.getString('proxyHost'), '127.0.0.1');
    expect(HivePrefUtil.getInt('proxyPort'), ProxySettingsController.defaultProxyPort);
    expect(HivePrefUtil.getString('appProxyHost'), '[::1]');
    expect(HivePrefUtil.getInt('appProxyPort'), ProxySettingsController.defaultProxyPort);
  });

  test('export cannot leak direct invalid endpoint writes into a backup', () {
    final proxy = Get.put(ProxySettingsController());
    proxy.proxyHost.value = ' localhost ';
    proxy.proxyPort.value = 0;
    proxy.appProxyHost.value = ' 127。0．0。1 ';
    proxy.appProxyPort.value = 70000;

    expect(proxy.toJson(), {
      'enableProxy': false,
      'proxyHost': 'localhost',
      'proxyPort': ProxySettingsController.defaultProxyPort,
      'enableAppProxy': false,
      'appProxyHost': '127.0.0.1',
      'appProxyPort': ProxySettingsController.defaultProxyPort,
    });
  });
}
