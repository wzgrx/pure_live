import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:live_player/live_player.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/launch_args.dart';
import 'package:pure_live/app/recording.dart';

/// Everything the pages use, made once at start (3.x registered these as
/// GetX services and singletons: `SettingsService.to`, `Sites.of`,
/// `site.getDanmaku()`; here they are one object handed down through
/// [appServicesProvider], the danmaku in [DanmakuRegistry]).
final class AppServices {
  /// Creates the services.
  new({
    required this.store,
    required this.cipher,
    required this.http,
    required this.proxy,
    required this.cookies,
    required this.sites,
    required this.danmaku,
    required this.launch,
    required this.dataRoot,
    required this.followsReady,
    required this.mediaOpener,
    this.iptvImporter,
    this.recording,
  });

  /// Storage and settings (3.x `SettingsService.to`).
  final LiveStore store;

  /// The platform cipher of the secrets (new-window hand-over).
  final SecretCipher cipher;

  /// The HTTP client of the adapters.
  final LiveHttp http;

  /// The app proxy rules.
  final ProxyPolicy proxy;

  /// The user's cookies.
  final CookieVault cookies;

  /// The platforms (3.x `Sites.of(id)`).
  final SiteRegistry sites;

  /// The danmaku connections per platform (3.x asked the site with
  /// `getDanmaku()`; 4.x adapters have no danmaku).
  final DanmakuRegistry danmaku;

  /// The command line of this window.
  final LaunchArgs launch;

  /// The data folder.
  final Directory dataRoot;

  /// Completes when 3.x's per-broadcast follows have moved to their
  /// streamer (M9 `IdentityMigration`). The follow refresh (M13) waits for
  /// it: a refresh answers with the new identity, which a merge ignores.
  final Future<void> followsReady;

  /// The stream opener every player shares (one loopback relay, the
  /// recipe platforms' openers, the native mpv profile; M7.2).
  final MediaOpener mediaOpener;

  /// A new playback session (3.x `GlobalPlayerService.instance.playerManager`;
  /// the live room uses one, multi-view one per cell). [config] carries the
  /// player settings (decoder, output, M9/M13).
  PlaybackSession newPlaybackSession({MpvEngineConfig? config}) => PlaybackSession(
    engine: () => MpvEngine.create(config: config),
    opener: mediaOpener,
  );

  /// IPTV imports and syncs; null when IPTV is not set up.
  final IptvImporter? iptvImporter;

  /// Recording (M8 and M13.15): settings, the managed directory and the
  /// recorder (`buildAppRecording` in `recording.dart`); null in tests that
  /// do not need it.
  final AppRecording? recording;

  /// The recorder (M8); null where this build has no FFmpeg.
  Recorder? get recorder => recording?.recorder;

  /// Releases recording, the store and the HTTP client.
  Future<void> close() async {
    await recording?.dispose();
    await mediaOpener.close();
    http.close();
    await store.close();
  }
}

/// The services; `main` overrides it with the started ones.
final Provider<AppServices> appServicesProvider = Provider<AppServices>(
  (ref) => throw StateError('AppServices are created in main() and passed as an override'),
);

/// Storage and settings (3.x `SettingsService.to`).
final Provider<LiveStore> storeProvider = Provider((ref) => ref.watch(appServicesProvider).store);

/// The platforms (3.x `Sites.of(id)`: `ref.read(sitesProvider).of(id)`).
final Provider<SiteRegistry> sitesProvider = Provider((ref) => ref.watch(appServicesProvider).sites);

/// The danmaku connections, `ref.read(danmakuProvider).connectionFor(platform)`
/// (3.x asked the site with `getDanmaku()`).
final Provider<DanmakuRegistry> danmakuProvider = Provider((ref) => ref.watch(appServicesProvider).danmaku);

/// Makes playback sessions (`ref.read(playbackSessionFactoryProvider)()`);
/// the page owns and disposes the session it made.
final Provider<PlaybackSession Function({MpvEngineConfig? config})> playbackSessionFactoryProvider = Provider(
  (ref) => ref.watch(appServicesProvider).newPlaybackSession,
);

/// The recorder; null where this build has no FFmpeg (see
/// [AppServices.recorder]).
final Provider<Recorder?> recorderProvider = Provider((ref) => ref.watch(appServicesProvider).recorder);

/// Recording: settings, directory, recorder and the user actions of the
/// live room's record button (see [AppRecording]).
final Provider<AppRecording?> recordingProvider = Provider((ref) => ref.watch(appServicesProvider).recording);

/// The value of a setting, updated when it changes (3.x read
/// `SettingsService.to.<group>.<field>.v` inside `Obx`).
final StreamProviderFamily<Object, Setting<Object>> settingProvider = StreamProvider.family<Object, Setting<Object>>((
  ref,
  setting,
) {
  final settings = ref.watch(appServicesProvider).store.settings;
  return settings.watch(setting);
});

/// Reads `setting` in a widget and rebuilds when it changes.
T watchSetting<T extends Object>(WidgetRef ref, Setting<T> setting) {
  final value = ref.watch(settingProvider(setting)).value;
  return value is T ? value : ref.read(appServicesProvider).store.settings.get(setting);
}
