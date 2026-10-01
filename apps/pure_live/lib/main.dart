import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/bootstrap.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/plugins.dart';

Future<void> main(List<String> args) async {
  // Every framework error in full, not abbreviated after the first (3.x).
  FlutterError.onError = (details) => FlutterError.dumpErrorToConsole(details, forceReport: true);

  final services = await AppBootstrap.start(args);
  installPluginHooks();
  final settings = services.store.settings;
  final language = AppLanguage.resolve(
    stored: settings.isSet(Settings.language) ? settings.get(Settings.language) : null,
    preferred: PlatformDispatcher.instance.locales,
  );
  final strings = await AppStrings.load(language, rootBundle);
  currentStrings = strings;
  // The Windows window (title bar, size and place, tray, close, start-up).
  await DesktopShell.start(services.store, primary: services.launch.isPrimary);

  runApp(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services), ...pluginOverrides()],
      child: PureLiveApp(strings: strings),
    ),
  );
}
