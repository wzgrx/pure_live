import 'dart:async';
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
import 'package:pure_live/app/ui_mode.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/native_http.dart';
import 'package:pure_live/platform/platform_services.dart';
import 'package:pure_live/platform/recording_platform.dart';
import 'package:pure_live/platform/secret_cipher.dart';

/// Keeps decoded covers and avatars bounded apart from the HTTP cache (3.x
/// `configureDecodedImageCache`): a 960x540 cover is about 2 MiB decoded.
void configureDecodedImageCache({required bool desktop}) {
  final cache = PaintingBinding.instance.imageCache
    ..maximumSize = desktop ? 240 : 160
    ..maximumSizeBytes = (desktop ? 72 : 48) * 1024 * 1024;
  assert(cache.maximumSize > 0, 'image cache disabled');
}

/// The start of the app (3.x `AppInitializer.initialize`), in order:
///
/// 1. the command line (extra Windows windows) and the data folder;
/// 2. storage with the platform cipher;
/// 3. the 3.x import (main window only; read-only, recorded in a ledger):
///    the settings box (M9), then the IPTV database (M12.1);
/// 4. a new window's hand-over through `restoreAll`;
/// 5. the HTTP client, proxy rules, cookies, the platforms, IPTV and the
///    danmaku connections;
/// 6. in the background: Huya's play User-Agent, the move of per-broadcast
///    follows ([AppServices.followsReady]) and the IPTV auto-sync 3 s later.
///
/// Windows single-instance and the main-window mutex live in the runner
/// (`windows/runner/main.cpp`), before any Flutter engine starts.
abstract final class AppBootstrap {
  /// Delay of the IPTV auto-sync after start (3.x `AutoSyncScheduler`).
  static const Duration iptvSyncDelay = Duration(seconds: 3);

  /// Starts the services for [args].
  static Future<AppServices> start(List<String> args) async {
    WidgetsFlutterBinding.ensureInitialized();
    configureDecodedImageCache(desktop: Platform.isWindows);
    // Which interface `auto` picks (M14.1): asked before the first frame.
    await TvDevice.detect();
    final launch = LaunchArgs.parse(args);
    final dataRoot = await resolveDataRoot(instanceId: launch.instanceId);
    final cipher = platformSecretCipher();
    final store = await LiveStore.open(dataRoot, cipher: cipher);
    final iptvLibrary = StoreIptvLibrary(store);

    if (launch.isPrimary) {
      var hiveFiles = const <String>[];
      try {
        hiveFiles = await legacyHiveFiles();
        final report = await LegacyMigration.importHiveFiles(store, hiveFiles);
        log('3.x import: $report', name: 'AppBootstrap');
      } on Object catch (error, stack) {
        log('3.x import failed', name: 'AppBootstrap', error: error, stackTrace: stack);
      }
      try {
        final report = await LegacyIptvMigration.importDatabases(
          store,
          iptvLibrary,
          legacyIptvDatabases(hiveFiles),
          playlistDirectory: iptvPlaylistDirectory(dataRoot),
        );
        log('3.x IPTV import: $report', name: 'AppBootstrap');
      } on Object catch (error, stack) {
        log('3.x IPTV import failed', name: 'AppBootstrap', error: error, stackTrace: stack);
      }
    }
    if (launch.configFile case final path?) {
      final restored = await NewWindowHandoff.restore(store, cipher, File(path));
      log('New window hand-over ${restored ? 'restored' : 'failed'}', name: 'AppBootstrap');
    }
    return wire(store: store, cipher: cipher, launch: launch, dataRoot: dataRoot, iptvLibrary: iptvLibrary);
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
      twitchFallbacks: [if (AndroidNativeHttp.isAvailable) AndroidNativeHttp(proxy: proxy)],
      iptv: IptvSite(
        library: library,
        importer: importer,
        selectedGuideSourceId: () => settings.get(Settings.selectedSourceId),
      ),
    );
    final sites = buildSiteRegistry(deps);
    final danmaku = buildDanmakuRegistry(deps, sites);
    final followsReady = background ? _moveFollows(store, sites) : Future<void>.value();
    // Recording (M13.15): FFmpeg, the foreground service and storage access
    // only in the running app; tests get the settings and the directory.
    final recording = background
        ? platformAppRecording(
            store: store,
            sites: sites,
            proxy: proxy,
            dataRoot: dataRoot,
            words: i18n,
            danmaku: danmaku,
          )
        : buildAppRecording(store: store, sites: sites, proxy: proxy, dataRoot: dataRoot);
    if (background) {
      unawaited(_warmUp(sites));
      unawaited(_iptvAutoSync(store, importer));
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
      mediaOpener: MediaOpener(proxy: proxy, engine: mpvEngineProfile(), recipes: recipeOpeners(sites)),
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
