import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pure_live_app/app/app.dart';
import 'package:pure_live_app/app/version.dart';
import 'package:pure_live_app/core/app_prefs.dart';
import 'package:pure_live_app/core/desktop_window.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/secrets.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/diagnostics/app_log.dart';
import 'package:pure_live_app/features/diagnostics/crash_handler.dart';
import 'package:pure_live_app/features/onboarding/startup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = await getApplicationSupportDirectory();
  // The local rolling log first, so start-up failures are recorded (F-BAK-02).
  final log = await AppLog.open(Directory('${root.path}${Platform.pathSeparator}logs'));
  AppLog.current = log;
  installCrashHandlers(log);
  log.info('app', 'start $appVersion ($appBuildNumber) on ${Platform.operatingSystem}');
  // Settings and secrets are in memory before the first frame (REG-STORE-001).
  final store = await LiveStore.open(root.path, log: StoreLog((message) => log.warning('store', message)));
  final secrets = await openSecretStore(root.path);
  final recordPaths = await RecordPaths.resolve(root.path);
  final prefs = await AppPrefs.load(store.meta);
  await initDesktopWindow(store.settings);
  runApp(
    ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        recordPathsProvider.overrideWithValue(recordPaths),
        secretStoreProvider.overrideWithValue(secrets),
        // Adapters read the user's platform cookies from the encrypted store.
        cookieVaultProvider.overrideWithValue(StoreCookieVault(secrets)),
        appPrefsProvider.overrideWith(() => AppPrefsNotifier(prefs)),
      ],
      // First-run wizard, crash prompt, update check and clipboard check.
      child: const StartupTasks(child: PureLiveApp()),
    ),
  );
}
