import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/app_log.dart';
import 'package:pure_live/app/bootstrap.dart';
import 'package:pure_live/app/data_root.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/fonts.dart';
import 'package:pure_live/app/intake/system_intake.dart';
import 'package:pure_live/app/launch_failure.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/startup.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/plugins.dart';

Future<void> main(List<String> args) async {
  // R04.1: the start-up's timing, from here (docs/R-性能和流畅度/R04-启动速度/R04.1-启动速度).
  StartupTiming.begin();
  // Every framework error in full, not abbreviated after the first (3.x),
  // and into the app log with uncaught errors (M12.4).
  FlutterError.onError = (details) => FlutterError.dumpErrorToConsole(details, forceReport: true);
  AppLog.instance.install();
  await _launch(args);
}

/// Starts the app; a failure before the first frame shows why, with "重试"
/// and "导出日志", instead of the splash screen forever (release fixes,
/// item 7).
Future<void> _launch(List<String> args) async {
  final ready = await launchOrExplain(
    () => _prepare(args),
    show: runApp,
    retry: () => _launch(args),
    exportLog: _exportLog,
  );
  final timing = StartupTiming.current;
  if (ready == null) {
    timing?.abandon();
    return;
  }
  final (:services, :strings, :fonts) = ready;
  timing
    ?..splash = services.store.settings.get(Settings.showSplashPage)
    ..mark('runApp');
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
  if (timing != null) {
    unawaited(WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) => timing.mark('firstFrame')));
  }
  // Shares, shortcuts and share codes on the clipboard (F.0a).
  SystemIntake.start(services);
}

/// The log of a failed start: the share sheet on a phone, else a file in
/// the temporary folder (its path is the message).
Future<String?> _exportLog() async {
  final file = await AppLog.instance.export(await getTemporaryDirectory());
  if (Platform.isAndroid || Platform.isIOS) {
    await shareFile(file);
    return null;
  }
  return i18n('launch_failed_log_saved', args: {'path': file.path});
}

/// The services, the words and the fonts before the first frame; what was
/// opened is closed again when a later step throws.
Future<({AppServices services, AppStrings strings, FontLibrary fonts})> _prepare(List<String> args) async {
  final services = await AppBootstrap.start(args);
  try {
    return await _finish(services);
  } on Object {
    try {
      await services.close();
    } on Object {
      // Already failing.
    }
    rethrow;
  }
}

Future<({AppServices services, AppStrings strings, FontLibrary fonts})> _finish(AppServices services) async {
  final timing = StartupTiming.current;
  installPluginHooks(services);
  final settings = services.store.settings;
  // Extra windows share the data folder (U.13 c14) but write their own log.
  final launch = services.launch;
  final logRoot = launch.isPrimary ? services.dataRoot : instanceFolder(services.dataRoot, launch.instanceId);
  await AppLog.instance.attach(settings, directory: Directory(p.join(logRoot.path, 'logs')));
  timing?.step('log');
  final language = AppLanguage.resolve(
    stored: settings.isSet(Settings.language) ? settings.get(Settings.language) : null,
    preferred: PlatformDispatcher.instance.locales,
  );
  final strings = await AppStrings.load(language, rootBundle);
  currentStrings = strings;
  timing?.step('strings');
  // The chosen app and danmaku fonts before the first frame (3.x), taken
  // from 3.x's font folder when they are only there.
  final fonts = FontLibrary(
    root: Directory(p.join(services.dataRoot.path, 'fonts')),
    http: services.http,
    legacyRoots: launch.isPrimary ? legacyFontRoots(await legacyHiveFiles()) : const [],
  );
  await fonts.restore(settings);
  timing?.step('fonts');
  // The desktop window (title bar, size and place, tray, close, new windows
  // over the shared data, start-up).
  await DesktopShell.start(
    services.store,
    primary: launch.isPrimary,
    recording: services.recording,
    dataRoot: services.dataRoot,
    instanceId: launch.instanceId,
  );
  timing?.step('desktop');
  return (services: services, strings: strings, fonts: fonts);
}
