import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/app_log.dart';
import 'package:pure_live/app/bootstrap.dart';
import 'package:pure_live/app/data_root.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/fonts.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/plugins.dart';

Future<void> main(List<String> args) async {
  // Every framework error in full, not abbreviated after the first (3.x),
  // and into the app log with uncaught errors (M12.4).
  FlutterError.onError = (details) => FlutterError.dumpErrorToConsole(details, forceReport: true);
  AppLog.instance.install();

  final services = await AppBootstrap.start(args);
  installPluginHooks();
  final settings = services.store.settings;
  // Extra windows share the data folder (U.13 c14) but write their own log.
  final launch = services.launch;
  final logRoot = launch.isPrimary ? services.dataRoot : instanceFolder(services.dataRoot, launch.instanceId);
  await AppLog.instance.attach(settings, directory: Directory(p.join(logRoot.path, 'logs')));
  final language = AppLanguage.resolve(
    stored: settings.isSet(Settings.language) ? settings.get(Settings.language) : null,
    preferred: PlatformDispatcher.instance.locales,
  );
  final strings = await AppStrings.load(language, rootBundle);
  currentStrings = strings;
  // The chosen app and danmaku fonts before the first frame (3.x), taken
  // from 3.x's font folder when they are only there.
  final fonts = FontLibrary(
    root: Directory(p.join(services.dataRoot.path, 'fonts')),
    http: services.http,
    legacyRoots: launch.isPrimary ? legacyFontRoots(await legacyHiveFiles()) : const [],
  );
  await fonts.restore(settings);
  // The desktop window (title bar, size and place, tray, close, new windows
  // over the shared data, start-up).
  await DesktopShell.start(
    services.store,
    primary: launch.isPrimary,
    recording: services.recording,
    dataRoot: services.dataRoot,
    instanceId: launch.instanceId,
  );

  runApp(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        fontLibraryProvider.overrideWithValue(fonts),
        ...pluginOverrides(),
      ],
      child: PureLiveApp(strings: strings),
    ),
  );
}
