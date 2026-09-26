import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/utils/version_util.dart';
import 'package:pure_live/common/utils/release_asset_urls.dart';
import 'package:pure_live/modules/version/version_page.dart';

void main() {
  test('maintained build reads updates and release assets from the same repository', () {
    expect(VersionUtil.projectUrl, 'https://github.com/wzgrx/pure_live');
    expect(VersionUtil.issuesUrl, '${VersionUtil.projectUrl}/issues');
    expect(VersionUtil.releaseUrl, contains('/repos/wzgrx/pure_live/releases'));
  });

  Map<String, dynamic> asset(String name, {String? url}) => {
    'name': name,
    'browser_download_url': url ?? 'https://github.com/wzgrx/pure_live/releases/download/v3.2.9/$name',
  };

  test('release assets are found by platform keywords in this repository\'s own file names', () {
    final urls = ReleaseAssetUrls(
      assets: [
        asset('BUILD_METADATA.json'),
        asset('SHA256SUMS.txt'),
        asset('PureLive-3.2.9-4132-debug-signed-android-arm64-v8a-release.apk'),
        asset('PureLive-3.2.9-4132-linux-x64.tar.gz'),
        asset('PureLive-3.2.9-4132-windows-x64-portable.zip'),
        asset('PureLive-3.2.9-4132-windows-x64-setup.exe'),
      ],
    );

    expect(urls.androidArm64, endsWith('/PureLive-3.2.9-4132-debug-signed-android-arm64-v8a-release.apk'));
    expect(urls.windowsSetup, endsWith('/PureLive-3.2.9-4132-windows-x64-setup.exe'));
    expect(urls.windowsPortable, endsWith('/PureLive-3.2.9-4132-windows-x64-portable.zip'));
    expect(urls.linuxX64, endsWith('/PureLive-3.2.9-4132-linux-x64.tar.gz'));
    // Artifacts this release does not publish are absent, never guessed.
    expect(urls.androidArmeabiV7a, isNull);
    expect(urls.windowsMsix, isNull);
    expect(urls.macosUrl, isNull);
    expect(urls.all.keys, [
      'android-arm64-v8a',
      'windows-x64-setup.exe',
      'windows-x64-portable.zip',
      'linux-x64.tar.gz',
    ]);
  });

  test('upstream-style names, release preference and unsafe links', () {
    final urls = ReleaseAssetUrls(
      assets: [
        asset('PureLive-3.1.5-4104-android-arm64-v8a-debug.apk'),
        asset('PureLive-3.1.5-4104-android-arm64-v8a-release.apk'),
        asset('PureLive-3.1.5-4104-android-x86_64-release.apk', url: 'http://example.test/x86.apk'),
        asset('PureLive-3.1.5-4104-android-armeabi-v7a-release.apk', url: 'file:///tmp/v7a.apk'),
        asset('', url: 'https://example.test/nameless.apk'),
      ],
    );

    expect(urls.androidArm64, endsWith('-android-arm64-v8a-release.apk'));
    expect(urls.androidX8664, isNull, reason: 'plain HTTP is refused');
    expect(urls.androidArmeabiV7a, isNull, reason: 'only HTTPS URLs are used');
    expect(const ReleaseAssetUrls(assets: []).all, isEmpty);
  });

  test('download actions accept only absolute web URLs', () {
    expect(versionDownloadUri('https://example.test/release.apk'), isNotNull);
    expect(versionDownloadUri('http://127.0.0.1/release.apk'), isNotNull);
    expect(versionDownloadUri('release.apk'), isNull);
    expect(versionDownloadUri('file:///tmp/release.apk'), isNull);
    expect(versionDownloadUri('javascript:alert(1)'), isNull);
  });

  test('update failure and download feedback are translated in both locales', () {
    final english = jsonDecode(File('assets/translations/en.json').readAsStringSync()) as Map<String, dynamic>;
    final chinese = jsonDecode(File('assets/translations/zh.json').readAsStringSync()) as Map<String, dynamic>;
    const keys = {'version_update_download_failed', 'version_update_failed_subtitle', 'version_update_failed_title'};

    for (final key in keys) {
      expect(english[key], isA<String>().having((value) => value.trim(), key, isNotEmpty));
      expect(chinese[key], isA<String>().having((value) => value.trim(), key, isNotEmpty));
    }
  });

  test('Android update links are limited to APK variants declared by the feed', () {
    expect(
      VersionUtil.selectAndroidAbis({
        'android_abis': ['arm64-v8a'],
      }),
      {'arm64-v8a'},
    );
    expect(
      VersionUtil.selectAndroidAbis({
        'android_abis': ['armeabi-v7a', 'arm64-v8a', 'x86_64', 'unsupported'],
      }),
      {'armeabi-v7a', 'arm64-v8a', 'x86_64'},
    );
    expect(VersionUtil.selectAndroidAbis({}), {'arm64-v8a'});
    expect(VersionUtil.selectAndroidAbis({'android_abis': []}), isEmpty);
    expect(
      VersionUtil.selectAndroidAbis({
        'android_abis': ['unsupported'],
      }),
      isEmpty,
    );
  });

  test('platform update feed does not announce an unpublished artifact to other platforms', () {
    final feed = <String, dynamic>{
      'version': '2.1.1',
      'build_number': 49,
      'platforms': {
        'windows': {'version': '2.1.2', 'build_number': 50, 'windows_msix_available': false},
      },
    };

    expect(VersionUtil.selectPlatformVersionData(feed, platform: 'windows')['version'], '2.1.2');
    expect(VersionUtil.selectPlatformVersionData(feed, platform: 'windows')['windows_msix_available'], isFalse);
    expect(VersionUtil.selectPlatformVersionData(feed, platform: 'android')['version'], '2.1.1');
  });
}
