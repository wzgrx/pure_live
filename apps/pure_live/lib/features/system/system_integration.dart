import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/desktop_window.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/system/android_media.dart';
import 'package:pure_live_app/features/system/audio_focus.dart';
import 'package:pure_live_app/features/system/background_playback.dart';
import 'package:pure_live_app/features/system/close_behaviour.dart';
import 'package:pure_live_app/features/system/desktop_shell.dart';
import 'package:pure_live_app/features/system/launch_args.dart';
import 'package:pure_live_app/features/system/media_controls.dart';
import 'package:pure_live_app/features/system/mini_player.dart';
import 'package:pure_live_app/features/system/now_playing.dart';
import 'package:pure_live_app/features/system/pip.dart';
import 'package:pure_live_app/features/system/windows_native.dart';
import 'package:window_manager/window_manager.dart';

/// The Windows runner channel; main() overrides it with the instance it
/// already used before the first frame.
final windowsNativeProvider = Provider<WindowsNative>((ref) => WindowsNative());

/// The system media controls of this platform.
final mediaControlsProvider = Provider<MediaControls>((ref) {
  if (Platform.isAndroid) return AndroidMediaControls();
  if (Platform.isWindows) return WindowsMediaControls(ref.watch(windowsNativeProvider));
  return const NoMediaControls();
});

/// Audio focus (Android only).
final audioFocusPortProvider = Provider<AudioFocusPort?>((ref) => Platform.isAndroid ? AudioSessionFocusPort() : null);

/// The Wi-Fi lock for background playback (Android only).
final wifiLockProvider = Provider<WifiLock?>((ref) => Platform.isAndroid ? WifiLock() : null);

/// Whether this platform runs the Windows shell (tray, close behaviour,
/// autostart, title bar, forwarded launches).
final windowsShellEnabledProvider = Provider<bool>((ref) => Platform.isWindows);

/// Wires the system integration once the app runs; `PureLiveApp` watches it.
///
/// - Background policy and Wi-Fi lock (INT-3, PERF-2, F-BG-01).
/// - Audio focus (INT-4).
/// - Media notification / SMTC (F-BG-01, F-NEW-12).
/// - Picture-in-picture parameters and actions (§9).
/// - Windows: tray, close behaviour, autostart, title bar, forwarded launches
///   (F-WIN-01 to F-WIN-05) and the room of the launch arguments (F-APP-04).
final systemIntegrationProvider = Provider<void>((ref) {
  final settings = ref.watch(storeProvider).settings;
  final subscriptions = <StreamSubscription<Object?>>[];
  ref.onDispose(() {
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
  });

  NowPlaying? current() => ref.read(nowPlayingProvider);

  // Background policy (INT-3).
  final background = BackgroundPlayback(
    allowBackground: () => settings.get(Settings.backgroundPlay),
    pipActive: () => ref.read(pipProvider).mode == PipMode.active,
    miniWindowShowing: () => ref.read(miniPlayerProvider.notifier).holding,
  );
  ref.onDispose(background.dispose);

  // Wi-Fi lock (PERF-2).
  final wifi = ref.watch(wifiLockProvider);
  void syncWifi() {
    if (wifi == null) return;
    unawaited(
      wifi.set(
        held: wantsWifiLock(hidden: background.hidden, state: current()?.session.state),
      ),
    );
  }

  final lifecycle = AppLifecycleListener(
    onStateChange: (state) {
      background.lifecycleChanged(state);
      syncWifi();
    },
  );
  ref.onDispose(lifecycle.dispose);

  // Audio focus (INT-4).
  final focusPort = ref.watch(audioFocusPortProvider);
  final focus = focusPort == null ? null : AudioFocusCoordinator(focusPort);
  if (focus != null) ref.onDispose(() => unawaited(focus.dispose()));

  // Media notification / SMTC.
  final media = MediaControlsBridge(
    controls: ref.watch(mediaControlsProvider),
    // Android shows the notification only with background play on (F-BG-01);
    // SMTC follows every playing room (F-NEW-12).
    enabled: () => !Platform.isAndroid || settings.get(Settings.backgroundPlay),
  );
  ref.onDispose(() => unawaited(media.dispose()));
  subscriptions.add(settings.watch(Settings.backgroundPlay).skip(1).listen((_) => media.refresh()));

  // Picture-in-picture parameters (PIP-2): after the new layout, so the
  // ratio matches what is on screen.
  final pip = ref.read(pipProvider.notifier);
  var pipQueued = false;
  void syncPip() {
    if (pipQueued) return;
    pipQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      pipQueued = false;
      if (!ref.mounted) return;
      final playing = current();
      if (playing == null) {
        unawaited(pip.update(aspect: 16 / 9, playing: false, autoEnter: false));
        return;
      }
      final state = playing.session.state;
      final inRoom = !ref.read(miniPlayerProvider.notifier).owns(playing.session);
      unawaited(
        pip.update(
          aspect: pipAspect(state),
          playing: state.wantsPlay,
          autoEnter:
              Platform.isAndroid &&
              settings.get(Settings.autoPip) &&
              inRoom &&
              state.wantsPlay &&
              state.phase == PlaybackPhase.playing &&
              state.hasPicture,
        ),
      );
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  subscriptions
    ..add(settings.watch(Settings.autoPip).skip(1).listen((_) => syncPip()))
    ..add(
      pip.playToggles.listen((play) {
        final session = current()?.session;
        if (session != null) runSessionCommand(play ? session.play : session.pause);
      }),
    );

  // Follow the current playback.
  StreamSubscription<PlaybackState>? states;
  ref
    ..onDispose(() => unawaited(states?.cancel()))
    ..listen<NowPlaying?>(nowPlayingProvider, (previous, next) {
      final session = next?.session;
      if (!identical(previous?.session, session)) {
        unawaited(states?.cancel());
        states = session?.states.listen((state) {
          syncWifi();
          syncPip();
          // SES-6: the Windows PiP window goes back to normal when playback ends.
          if (state.phase == PlaybackPhase.idle && Platform.isWindows) unawaited(pip.exit());
        });
        pip.cancel();
        if (session == null && Platform.isWindows) unawaited(pip.exit());
      }
      background.attach(session);
      focus?.attach(session);
      media.attach(next);
      syncWifi();
      syncPip();
    }, fireImmediately: true);

  // Windows shell.
  final launch = ref.watch(launchArgsProvider);
  void openRoom(RoomRef room) => unawaited(ref.read(routerProvider).push(roomLocation(room)));
  if (ref.watch(windowsShellEnabledProvider)) {
    final native = ref.watch(windowsNativeProvider);
    final shell = WindowsShell(
      native: native,
      window: ref.watch(desktopWindowProvider),
      settings: settings,
      secondaryWindow: launch.secondaryWindow,
      askClose: () async {
        final context = ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;
        if (context == null || !context.mounted) return (action: CloseAction.exit, remember: false);
        return await showCloseDialog(context);
      },
      openRoom: openRoom,
      beforeExit: () => releasePlaybackForExit(ref),
    );
    windowManager.addListener(shell);
    unawaited(shell.start());
    ref.onDispose(() {
      windowManager.removeListener(shell);
      unawaited(shell.dispose());
    });

    final titleBar = TitleBarSync(native, () {
      return switch (ref.read(themeModeSetting)) {
        AppThemeMode.dark => true,
        AppThemeMode.light => false,
        AppThemeMode.system => null,
      };
    });
    WidgetsBinding.instance.addObserver(titleBar);
    ref
      ..onDispose(() => WidgetsBinding.instance.removeObserver(titleBar))
      ..listen(themeModeSetting, (_, _) => titleBar.update());
    titleBar.update();
  }

  // The room of the launch arguments opens after the first frame (F-APP-04).
  if (launch.openRoom case final room?) {
    unawaited(WidgetsBinding.instance.endOfFrame.then((_) => ref.mounted ? openRoom(room) : null));
  }
});

/// Closes the mini window and hard-releases the current playback before the
/// app quits, so the player tears down in its own order (SURF-2) instead of
/// with the process.
Future<void> releasePlaybackForExit(Ref ref) async {
  await ref.read(miniPlayerProvider.notifier).close();
  final playing = ref.read(nowPlayingProvider);
  await playing?.session.close(release: true);
}
