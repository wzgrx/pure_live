import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/app_log.dart';
import 'package:pure_live/app/data_root.dart';
import 'package:pure_live/app/iptv_legacy.dart';
import 'package:pure_live/app/iptv_library.dart';
import 'package:pure_live/app/launch_args.dart';
import 'package:pure_live/app/platforms.dart';
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/startup.dart';
import 'package:pure_live/app/ui_mode.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/native_http.dart';
import 'package:pure_live/platform/platform_services.dart';
import 'package:pure_live/platform/recording_platform.dart';
import 'package:pure_live/platform/secret_cipher.dart';
import 'package:pure_live/platform/system_permissions.dart';
import 'package:pure_live/platform/twitch_webview_http.dart';
import 'package:pure_live/shared/permission_prompts.dart';

/// Keeps decoded covers and avatars bounded apart from the HTTP cache (3.x
/// `configureDecodedImageCache`), sized by [decodedImageBudget] for a device
/// with [totalMemoryBytes] of memory (null: unknown).
void configureDecodedImageCache({required bool desktop, int? totalMemoryBytes}) {
  final budget = decodedImageBudget(desktop: desktop, totalMemoryBytes: totalMemoryBytes);
  final cache = PaintingBinding.instance.imageCache
    ..maximumSize = budget.count
    ..maximumSizeBytes = budget.bytes;
  assert(cache.maximumSize > 0, 'image cache disabled');
}

/// Phones and tablets with more memory than this get the larger budget.
const int largeImageBudgetAbove = 4 * 1024 * 1024 * 1024;

/// How many decoded pictures and bytes the image cache keeps (P05, research
/// 2026-10-02 D2). A card's cover decodes at most 720 wide, about 1.1 MiB.
///
/// * Desktops: 3.x's 240 pictures and 72 MiB.
/// * Phones and tablets with 4 GiB or less, or unknown memory: 3.x's 160
///   pictures and 48 MiB, about 40 covers, so low-end devices use no more
///   than before.
/// * More memory: 320 pictures and 128 MiB, about 110 covers, so a hot list
///   scrolled back and forth decodes its covers again less often.
({int count, int bytes}) decodedImageBudget({required bool desktop, int? totalMemoryBytes}) {
  const mebibyte = 1024 * 1024;
  if (desktop) return (count: 240, bytes: 72 * mebibyte);
  if (totalMemoryBytes == null || totalMemoryBytes <= largeImageBudgetAbove) return (count: 160, bytes: 48 * mebibyte);
  return (count: 320, bytes: 128 * mebibyte);
}

/// The device's memory from Linux's `MemTotal` in [path] (Android lets apps
/// read /proc/meminfo); null when it cannot be read. The figure is a little
/// under the advertised size (the kernel keeps some), so a "4 GB" phone reads
/// about 3.6 GiB.
int? readTotalMemoryBytes({String path = '/proc/meminfo'}) {
  try {
    for (final line in File(path).readAsLinesSync()) {
      final match = RegExp(r'^MemTotal:\s+(\d+)\s*kB', caseSensitive: false).firstMatch(line);
      if (match != null) return int.parse(match.group(1)!) * 1024;
    }
  } on Object {
    // Unreadable: the small budget.
  }
  return null;
}

/// The `meta` key of the last 3.x import's summary (J06.2, JSON):
/// [legacyImportHeader] puts it at the top of exported logs.
const String legacyLastImportKey = 'legacy.lastImport';

/// The app log's tag of the 3.x import.
const String legacyLogTag = 'legacy';

/// Imports 3.x's settings box and IPTV databases into [store] (main window
/// only; read-only, recorded in ledgers), then clears 3.x's stand-in names
/// once ([LegacyMigration.clearPlaceholdersOnce]).
///
/// What happened goes to [appLog] (tag [legacyLogTag]), so release builds
/// show it on the log page: a run that read a source writes its report
/// (counts, failed sources, names of unreadable values and of sign-ins that
/// could not be encrypted, never a value), a warning when something was
/// left behind, and its summary to `meta` [legacyLastImportKey]. An
/// ordinary start writes nothing. [importHive] is
/// [LegacyMigration.importHiveFiles] (tests replace it).
Future<void> importLegacyData(
  LiveStore store,
  IptvLibrary iptvLibrary, {
  required Future<List<String>> Function() hiveFiles,
  required Directory playlistDirectory,
  List<String> Function(List<String> hiveFiles) iptvDatabases = legacyIptvDatabases,
  Future<LegacyImportReport> Function(LiveStore store, List<String> files) importHive = LegacyMigration.importHiveFiles,
  AppLog? appLog,
  DateTime Function() now = DateTime.now,
}) async {
  final logs = appLog ?? AppLog.instance;
  var files = const <String>[];
  LegacyImportReport? report;
  try {
    files = await hiveFiles();
    report = await importHive(store, files);
    log('3.x import: $report', name: 'AppBootstrap');
    await LegacyReloginNotice.record(store.meta, report);
  } on Object catch (error, stack) {
    log('3.x import failed', name: 'AppBootstrap', error: error, stackTrace: stack);
    logs.warning(legacyLogTag, '3.x import failed', error);
  }
  LegacyIptvReport? iptv;
  try {
    iptv = await LegacyIptvMigration.importDatabases(
      store,
      iptvLibrary,
      iptvDatabases(files),
      playlistDirectory: playlistDirectory,
    );
    log('3.x IPTV import: $iptv', name: 'AppBootstrap');
  } on Object catch (error, stack) {
    log('3.x IPTV import failed', name: 'AppBootstrap', error: error, stackTrace: stack);
    logs.warning(legacyLogTag, '3.x IPTV import failed', error);
  }

  final settingsRead = report != null && report.read;
  final iptvRead = iptv != null && (iptv.importedSources > 0 || iptv.failedSources.isNotEmpty);
  if (settingsRead) {
    logs.add(report.hasProblems ? LogLevel.warning : LogLevel.info, legacyLogTag, '3.x import: ${report.summary()}');
  }
  if (iptvRead) {
    final problems = iptv.failedSources.isNotEmpty || iptv.skipped.isNotEmpty;
    logs.add(problems ? LogLevel.warning : LogLevel.info, legacyLogTag, '3.x IPTV import: ${_iptvSummary(iptv)}');
  }
  if (settingsRead || iptvRead) {
    try {
      await store.meta.set(
        legacyLastImportKey,
        jsonEncode({
          'time': now().toIso8601String(),
          if (settingsRead)
            'settings': {
              'sources': report.importedSources,
              'before': report.alreadyImported,
              'failed': report.failedSources.length,
              'follows': report.follows,
              'history': report.history,
              'unreadable': report.skipped.length,
              'signInsNotStored': report.skippedSecrets.length,
            },
          if (iptvRead)
            'iptv': {
              'sources': iptv.importedSources,
              'before': iptv.alreadyImported,
              'failed': iptv.failedSources.length,
              'playlists': iptv.playlists,
              'channels': iptv.channels,
              'guides': iptv.guides,
              'skipped': iptv.skipped.length,
            },
        }),
      );
    } on Object catch (error) {
      logs.warning(legacyLogTag, '3.x import summary not stored', error);
    }
  }

  try {
    final cleared = await LegacyMigration.clearPlaceholdersOnce(store);
    if (cleared != null && cleared > 0) {
      logs.info(legacyLogTag, '3.x stand-in names (JD Live, Kugou Live, Baidu Live) cleared from $cleared rooms');
    }
  } on Object catch (error) {
    // Tried again next start.
    logs.warning(legacyLogTag, '3.x stand-in names not cleared', error);
  }
}

String _iptvSummary(LegacyIptvReport report) {
  final failed = report.failedSources;
  return 'sources ${report.importedSources}, before ${report.alreadyImported}, '
      'failed ${failed.isEmpty ? '0' : '${failed.length} (${failed.join(', ')})'}, '
      'playlists ${report.playlists}, channels ${report.channels}, guides ${report.guides}, '
      'skipped ${report.skipped.length}';
}

/// The first line of an exported log from the stored [summary]
/// ([legacyLastImportKey]): `3.x import (<time>): …`; null without one.
String? legacyImportHeader(String? summary) {
  if (summary == null || summary.isEmpty) return null;
  try {
    final json = jsonDecode(summary);
    if (json is! Map) return null;
    final time = DateTime.tryParse('${json['time']}')?.toLocal();
    final stamp = time == null ? '?' : time.toIso8601String().substring(0, 16).replaceFirst('T', ' ');
    String counts(Object? part, List<(String, String)> names) {
      if (part is! Map) return '';
      return [for (final (key, label) in names) '$label ${part[key] ?? 0}'].join(', ');
    }

    final parts = [
      if (json['settings'] case final Map<Object?, Object?> settings)
        counts(settings, const [
          ('sources', 'sources'),
          ('follows', 'follows'),
          ('history', 'history'),
          ('unreadable', 'unreadable'),
          ('signInsNotStored', 'sign-ins not stored'),
          ('failed', 'failed'),
        ]),
      if (json['iptv'] case final Map<Object?, Object?> iptv)
        'IPTV: ${counts(iptv, const [('sources', 'sources'), ('playlists', 'playlists'), ('channels', 'channels'), ('guides', 'guides'), ('skipped', 'skipped'), ('failed', 'failed')])}',
    ];
    return '3.x import ($stamp): ${parts.join('; ')}';
  } on FormatException {
    return null;
  }
}

/// The start of the app (3.x `AppInitializer.initialize`), in order:
///
/// 1. the command line (extra desktop windows) and the data folder, which
///    every window shares (docs/A-界面设计/A16-桌面界面/A16.1-桌面窗口 c14);
/// 2. storage with the platform cipher, opened for sharing with the other
///    windows' processes;
/// 3. the 3.x import (main window only; read-only, recorded in a ledger):
///    the settings box (M9), then the IPTV database (M12.1);
/// 4. the HTTP client, proxy rules, cookies, the platforms, IPTV and the
///    danmaku connections;
/// 5. in the background: Huya's play User-Agent, and in the main window the
///    move of per-broadcast follows ([AppServices.followsReady]) and the
///    IPTV auto-sync 3 s later.
///
/// Windows single-instance and the main-window mutex live in the runner
/// (`windows/runner/main.cpp`), before any Flutter engine starts.
abstract final class AppBootstrap {
  /// Delay of the IPTV auto-sync after start (3.x `AutoSyncScheduler`).
  static const Duration iptvSyncDelay = Duration(seconds: 3);

  /// Starts the services for [args].
  static Future<AppServices> start(List<String> args) async {
    // R04.1: each step's time (StartupTiming, `startupSteps`).
    final timing = StartupTiming.current;
    WidgetsFlutterBinding.ensureInitialized();
    timing
      ?..step('binding')
      ..askProcess();
    configureDecodedImageCache(
      desktop: Platform.isWindows,
      totalMemoryBytes: Platform.isAndroid ? readTotalMemoryBytes() : null,
    );
    timing?.step('imageCache');
    // Which interface `auto` picks (M14.1): asked before the first frame.
    await TvDevice.detect();
    timing?.step('tvDetect');
    final launch = LaunchArgs.parse(args);
    final dataRoot = await resolveDataRoot();
    final cipher = platformSecretCipher();
    timing?.step('dataRoot');
    // Shared: another desktop window's process may write at the same time
    // (a single process elsewhere, where it changes nothing).
    final store = await LiveStore.open(dataRoot, cipher: cipher, shared: true);
    timing?.step('store');
    final iptvLibrary = StoreIptvLibrary(store);

    // Every window's exported log starts with the last 3.x import (J06.2).
    AppLog.instance.header = () async => legacyImportHeader(await store.meta.get(legacyLastImportKey));
    if (launch.isPrimary) {
      await importLegacyData(
        store,
        iptvLibrary,
        hiveFiles: legacyHiveFiles,
        playlistDirectory: iptvPlaylistDirectory(dataRoot),
      );
    }
    timing?.step('legacy');
    final services = wire(store: store, cipher: cipher, launch: launch, dataRoot: dataRoot, iptvLibrary: iptvLibrary);
    timing?.step('wire');
    return services;
  }

  /// Builds the services over an open [store] and starts the background
  /// work (tests pass their own [http]). IPTV data lives in [store]'s
  /// database ([StoreIptvLibrary]) unless [iptvLibrary] is given.
  static AppServices wire({
    required LiveStore store,
    required SecretCipher cipher,
    required LaunchArgs launch,
    required Directory dataRoot,
    LiveHttp? http,
    IptvLibrary? iptvLibrary,
    bool background = true,
  }) {
    final proxy = SettingsProxyPolicy(store.settings);
    // Failed requests go to the app log as structure-only summaries (no
    // query strings, cookies or bodies; M12.4).
    final client =
        http ?? LoggingHttp(IoLiveHttp(proxy: proxy), onFailure: (summary) => AppLog.instance.warning('http', summary));
    final cookies = StoreCookieVault(store.secrets);
    final settings = store.settings;
    final library = iptvLibrary ?? StoreIptvLibrary(store);
    // Android's system TLS: Twitch's GraphQL fallback, Kick's API.
    final native = AndroidNativeHttp.isAvailable ? AndroidNativeHttp(proxy: proxy) : null;
    final importer = IptvImporter(
      library: library,
      http: client,
      playlistDirectory: iptvPlaylistDirectory(dataRoot),
      selectedGuideSourceId: () => settings.get(Settings.selectedSourceId),
      autoSyncEnabled: () => settings.get(Settings.isAutoSyncEnabled),
      legacyDecoder: platformGbkDecoder(),
    );
    final deps = PlatformDeps(
      http: client,
      proxy: proxy,
      cookies: cookies,
      store: store,
      // Twitch GraphQL: Android's system TLS, then the headless WebView (3.x).
      twitchFallbacks: [
        ?native,
        if (TwitchWebViewHttp.isAvailable) TwitchWebViewHttp(proxy: proxy),
      ],
      kickApi: native,
      iptv: IptvSite(
        library: library,
        importer: importer,
        selectedGuideSourceId: () => settings.get(Settings.selectedSourceId),
      ),
    );
    final sites = buildSiteRegistry(deps);
    final danmaku = buildDanmakuRegistry(deps, sites);
    // The once-only upkeep of the shared data is the main window's (U.13 c14).
    final followsReady = background && launch.isPrimary ? _moveFollows(store, sites) : Future<void>.value();
    // Recording (M13.15): FFmpeg, the foreground service and storage access
    // only in the running app; tests get the settings and the directory.
    // An extra window keeps its own task list beside the main window's in
    // the shared data (both lists are written whole).
    final tasksKey = recorderTasksKeyFor(launch.instanceId);
    // The notification permission once, all-files access explained first
    // (docs/A-界面设计/A14-系统界面/A14.1-系统界面 c14).
    final prompts = RecordingPermissionPrompts(permissions: const SystemPermissions(), meta: store.meta);
    final recording = background
        ? platformAppRecording(
            store: store,
            sites: sites,
            proxy: proxy,
            dataRoot: dataRoot,
            words: i18n,
            danmaku: danmaku,
            tasksKey: tasksKey,
            onServiceStart: () => unawaited(prompts.notificationsOnce()),
            explainStorage: prompts.explainStorage,
          )
        : buildAppRecording(store: store, sites: sites, proxy: proxy, dataRoot: dataRoot, tasksKey: tasksKey);
    if (background) {
      unawaited(_warmUp(sites));
      if (launch.isPrimary) unawaited(_iptvAutoSync(store, importer));
      unawaited(
        recording.start().catchError((Object error, StackTrace stack) {
          log('Recording start failed', name: 'AppBootstrap', error: error, stackTrace: stack);
        }),
      );
    }
    return AppServices(
      store: store,
      cipher: cipher,
      http: client,
      proxy: proxy,
      cookies: cookies,
      sites: sites,
      danmaku: danmaku,
      launch: launch,
      dataRoot: dataRoot,
      followsReady: followsReady,
      // The live room's streams take the playback proxy (3.x, F.0a).
      mediaOpener: MediaOpener(
        proxy: PlaybackProxyPolicy(settings),
        engine: mpvEngineProfile(),
        recipes: recipeOpeners(sites),
      ),
      iptvImporter: importer,
      recording: recording,
    );
  }

  static Future<void> _moveFollows(LiveStore store, SiteRegistry sites) async {
    try {
      final moved = await IdentityMigration.run(store, identityResolver(sites));
      if (moved > 0) log('Moved $moved follows to their streamer', name: 'AppBootstrap');
    } on Object catch (error, stack) {
      log('Identity migration failed', name: 'AppBootstrap', error: error, stackTrace: stack);
    }
  }

  /// Huya's play User-Agent from its config (3.x `startup_controller.dart`;
  /// playback never waits for it).
  static Future<void> _warmUp(SiteRegistry sites) async {
    try {
      await (sites.of(SiteIds.huya) as HuyaSite).loadPlayUserAgent();
    } on Object {
      // The built-in HYSDK User-Agent stays.
    }
  }

  static Future<void> _iptvAutoSync(LiveStore store, IptvImporter importer) async {
    await Future<void>.delayed(iptvSyncDelay);
    final settings = store.settings;
    if (!settings.get(Settings.hotAreasList).contains(SiteIds.iptv) || !settings.get(Settings.isAutoSyncEnabled)) {
      return;
    }
    try {
      await importer.syncExpired(hours: settings.get(Settings.autoSyncHoursInterval));
    } on Object catch (error, stack) {
      log('IPTV auto-sync failed', name: 'AppBootstrap', error: error, stackTrace: stack);
    }
  }
}
