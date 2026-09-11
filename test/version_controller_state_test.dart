import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pure_live/common/utils/version_util.dart';
import 'package:pure_live/modules/version/version_controller.dart';

void main() {
  PackageInfo localPackage() =>
      PackageInfo(appName: 'Pure Live', packageName: 'com.example.pure_live', version: '3.1.8', buildNumber: '4121');

  setUp(() {
    VersionUtil.latestVersion = '';
    VersionUtil.latestBuildNumber = null;
    VersionUtil.latestUpdateLog = '';
    VersionUtil.latestAndroidAbis = const {};
    VersionUtil.latestWindowsMsixAvailable = false;
  });

  test('failed update check always leaves a retryable terminal state', () async {
    var packageCalls = 0;
    final controller = VersionController(
      updateChecker: () async => false,
      packageInfoLoader: () async {
        packageCalls++;
        return localPackage();
      },
    );

    await controller.checkNewVersion();

    expect(controller.loading.value, isFalse);
    expect(controller.error.value, isTrue);
    expect(packageCalls, 0);
    expect(controller.windowsSetupUrl.value, isEmpty);
    expect(controller.androidArm64Url.value, isEmpty);
  });

  test('package metadata failures clear every generated release URL', () async {
    final controller =
        VersionController(
            updateChecker: () async => true,
            packageInfoLoader: () async => throw StateError('fixture package metadata failure'),
          )
          ..windowsSetupUrl.value = 'stale setup'
          ..androidArm64Url.value = 'stale apk';

    await controller.checkNewVersion();

    expect(controller.loading.value, isFalse);
    expect(controller.error.value, isTrue);
    expect(controller.windowsSetupUrl.value, isEmpty);
    expect(controller.androidArm64Url.value, isEmpty);
  });

  test('missing feed build number is rejected instead of inventing asset names', () async {
    VersionUtil.latestVersion = '3.2.0';
    VersionUtil.latestBuildNumber = null;
    VersionUtil.latestAndroidAbis = const {'arm64-v8a'};
    final controller = VersionController(
      updateChecker: () async => true,
      packageInfoLoader: () async => localPackage(),
    );

    await controller.checkNewVersion();

    expect(controller.loading.value, isFalse);
    expect(controller.error.value, isTrue);
    expect(controller.hasNewVersion.value, isFalse);
    expect(controller.androidArm64Url.value, isEmpty);
    expect(controller.windowsSetupUrl.value, isEmpty);
  });

  test('valid update data compares against the package loaded by this controller', () async {
    VersionUtil.latestVersion = '3.2.0';
    VersionUtil.latestBuildNumber = 5000;
    VersionUtil.latestUpdateLog = '# Pure Live 3.2.0';
    VersionUtil.latestAndroidAbis = const {'arm64-v8a'};
    final controller = VersionController(
      updateChecker: () async => true,
      packageInfoLoader: () async => localPackage(),
    );

    await controller.checkNewVersion();

    expect(controller.loading.value, isFalse);
    expect(controller.error.value, isFalse);
    expect(controller.hasNewVersion.value, isTrue);
    expect(controller.updateLog.value, '# Pure Live 3.2.0');
    expect(controller.androidArm64Url.value, contains('/v3.2.0/PureLive-3.2.0-5000-android-arm64-v8a-release.apk'));
    expect(controller.androidArmeabiV7aUrl.value, isEmpty);
    expect(controller.windowsSetupUrl.value, contains('/v3.2.0/PureLive-3.2.0-5000-windows-x64-setup.exe'));
  });

  test('version comparison handles prefixes, build metadata and malformed values', () {
    expect(VersionUtil.isNewerVersion('v3.2.0+5000', '3.1.8+4121'), isTrue);
    expect(VersionUtil.isNewerVersion('3.1.8', 'v3.1.8+4121'), isFalse);
    expect(VersionUtil.isNewerVersion('3.1.7', '3.1.8'), isFalse);
    expect(VersionUtil.isNewerVersion('latest', '3.1.8'), isFalse);
  });
}
