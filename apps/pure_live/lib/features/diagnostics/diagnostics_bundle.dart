import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/app/version.dart';
import 'package:pure_live_app/features/diagnostics/app_log.dart';
import 'package:pure_live_app/features/diagnostics/log_scrubber.dart';

/// The diagnostics bundle the user exports and attaches to an issue (F-BAK-02,
/// F-SET-10): app version, what the runtime knows about the device, every
/// setting, data counts and the recent log. One JSON file, readable without
/// tools. Secrets are never included: settings hold none (they live in the
/// secret store), the log is scrubbed when written and again here.
abstract final class DiagnosticsBundle {
  /// `format` of the document.
  static const format = 'pure_live.diagnostics';

  /// Log lines kept in a bundle (newest).
  static const maxLogLines = 3000;

  /// Builds the document.
  static Future<Map<String, Object?>> build({required LiveStore store, required AppLog log, DateTime? now}) async {
    final time = (now ?? DateTime.now()).toUtc();
    final settings = store.settings;
    final changed = settings.export(SettingScope.values.toSet()).keys.toSet();
    final lines = await log.readAll();
    final recent = lines.length > maxLogLines ? lines.sublist(lines.length - maxLogLines) : lines;
    return {
      'format': format,
      'version': 1,
      'createdAt': time.toIso8601String(),
      'app': {
        'version': appVersion,
        'build': appBuildNumber,
        'mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
      },
      'device': deviceInfo(),
      'settings': {
        for (final setting in Settings.all)
          setting.id: {
            'value': setting.encode(settings.get(setting)),
            if (changed.contains(setting.id)) 'changed': true,
          },
      },
      'data': {
        'follows': await store.follows.count(),
        'followAreas': (await store.followAreas.all()).length,
        'tags': (await store.tags.all()).length,
        'history': (await store.history.all()).length,
        'blockRules': (await store.blockRules.all()).length,
      },
      'log': [for (final line in recent) LogScrubber.scrub(line)],
    };
  }

  /// What the runtime reports about the device, without platform plugins.
  /// The host name is left out: it often carries the owner's name.
  static Map<String, Object?> deviceInfo() {
    final views = PlatformDispatcher.instance.views;
    final view = views.isEmpty ? null : views.first;
    return {
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'dart': Platform.version,
      'processors': Platform.numberOfProcessors,
      'locale': Platform.localeName,
      if (view != null)
        'screen': {
          'width': view.physicalSize.width.round(),
          'height': view.physicalSize.height.round(),
          'devicePixelRatio': view.devicePixelRatio,
          'refreshRate': view.display.refreshRate,
        },
    };
  }

  /// `PureLive-diagnostics-<yyyyMMdd-HHmmss>.json`.
  static String fileName(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    final t = time.toLocal();
    return 'PureLive-diagnostics-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}.json';
  }
}
