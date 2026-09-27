import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/app/app.dart';
import 'package:pure_live_app/app/locale.dart';
import 'package:pure_live_app/app/version.dart';
import 'package:pure_live_app/core/app_prefs.dart';
import 'package:pure_live_app/core/data_root.dart';
import 'package:pure_live_app/core/desktop_window.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/secrets.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/core/tv.dart';
import 'package:pure_live_app/features/diagnostics/app_log.dart';
import 'package:pure_live_app/features/diagnostics/crash_handler.dart';
import 'package:pure_live_app/features/onboarding/startup.dart';
import 'package:pure_live_app/features/settings/platforms_page.dart';
import 'package:pure_live_app/features/system/launch_args.dart';
import 'package:pure_live_app/features/system/system_integration.dart';
import 'package:pure_live_app/features/system/windows_native.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Only the forms the new-window launcher writes are accepted (F-WIN-02).
  final launch = LaunchArgs.parse(args);
  // Listening before the first frame; forwarded launches queue in the runner
  // until the shell says it is ready (F-WIN-01).
  final windows = Platform.isWindows ? WindowsNative() : null;
  // F-WIN-06: beside the executable on Windows when writable.
  final root = await resolveDataRoot();
  // The local rolling log first, so start-up failures are recorded (F-BAK-02).
  final log = await AppLog.open(Directory('${root.path}${Platform.pathSeparator}logs'));
  AppLog.current = log;
  installCrashHandlers(log);
  log.info('app', 'start $appVersion ($appBuildNumber) on ${Platform.operatingSystem}');
  // Settings and secrets are in memory before the first frame (REG-STORE-001).
  // An extra window shares the data root and the encrypted secret store.
  final store = await LiveStore.open(root.path, log: StoreLog((message) => log.warning('store', message)));
  final secrets = await openSecretStore(root.path);
  // F-DSC-03: platforms this version added join the user's list.
  await appendNewPlatforms(store);
  final recordPaths = await RecordPaths.resolve(root.path);
  // The interface language before the first frame (F-APP-06).
  applyAppLocale(
    localeForSetting(store.settings.get(Settings.locale), WidgetsBinding.instance.platformDispatcher.locales),
  );
  final prefs = await AppPrefs.load(store.meta);
  // Known before the first frame, so a TV never flashes the phone layout.
  final tv = await TvDevice.detect();
  if (tv.isTv) log.info('app', 'television (ui mode ${tv.television}, leanback ${tv.leanback})');
  await initDesktopWindow(
    store.settings,
    secondary: launch.secondaryWindow,
    startMaximized: windows?.setStartMaximized,
  );
  runApp(
    ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        dataRootProvider.overrideWithValue(root),
        recordPathsProvider.overrideWithValue(recordPaths),
        secretStoreProvider.overrideWithValue(secrets),
        // Adapters read the user's platform cookies from the encrypted store.
        cookieVaultProvider.overrideWithValue(StoreCookieVault(secrets)),
        appPrefsProvider.overrideWith(() => AppPrefsNotifier(prefs)),
        launchArgsProvider.overrideWithValue(launch),
        if (windows != null) windowsNativeProvider.overrideWithValue(windows),
        tvDeviceProvider.overrideWithValue(tv),
      ],
      // First-run wizard, crash prompt, update check and clipboard check.
      child: const StartupTasks(child: PureLiveApp()),
    ),
  );
}
