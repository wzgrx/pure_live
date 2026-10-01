import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:audio_service/audio_service.dart' as audio;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';

/// Whether this app may use picture-in-picture (U.2j c9).
enum PipAvailability {
  /// It may.
  allowed,

  /// The device offers it, but the system settings turned it off for this
  /// app ("无法打开画中画", "去设置").
  disabled,

  /// The device has none.
  unsupported,
}

/// How a request to enter picture-in-picture ended.
enum PipEntry {
  /// The window is entering it.
  entered,

  /// The system settings turned it off for this app.
  disabled,

  /// The system refused for another reason (3.x's "打开画中画失败，请重试").
  failed,
}

/// Android's system picture-in-picture (`pure_live/pip` in `MainActivity`;
/// 3.x used the floating plugin). [active] follows the activity.
abstract final class PictureInPicture {
  static const MethodChannel _channel = MethodChannel('pure_live/pip');
  static bool _listening = false;

  /// Whether the activity is in picture-in-picture now.
  static final ValueNotifier<bool> active = ValueNotifier(false);

  /// Whether to treat this as Android (tests); null asks the platform.
  @visibleForTesting
  static bool? debugAndroid;

  static bool get _android => debugAndroid ?? (!kIsWeb && Platform.isAndroid);

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') active.value = call.arguments == true;
      // The pause / play action of the system's picture-in-picture window
      // (docs/ui/compare/U.14 c7).
      if (call.method == 'togglePlay') await _toggle?.call();
    });
  }

  static Object? _owner;
  static bool? _playing;
  static Future<void> Function()? _toggle;

  /// Lets the picture-in-picture window of [owner] (the room playing) show
  /// a pause or play action (U.14 c7); sent to Android only on a change.
  static void bindPlayback({
    required Object owner,
    required bool playing,
    required Future<void> Function() play,
    required Future<void> Function() pause,
  }) {
    if (!_android) return;
    _owner = owner;
    _toggle = () => (_playing ?? false) ? pause() : play();
    if (_playing == playing) return;
    _playing = playing;
    _listen();
    unawaited(_setPlaying(playing));
  }

  /// Takes the action away when [owner] leaves.
  static void unbindPlayback(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _toggle = null;
    _playing = null;
    unawaited(_setPlaying(null));
  }

  static Future<void> _setPlaying(bool? playing) async {
    try {
      await _channel.invokeMethod<void>('setPlaying', {
        'playing': playing,
        'play': i18n('media_play'),
        'pause': i18n('media_pause'),
      });
    } on Object catch (error) {
      developer.log('Picture-in-picture action failed', name: 'LivePlay', error: error);
    }
  }

  /// Whether this device offers picture-in-picture.
  static Future<bool> supported() async {
    if (!_android) return false;
    _listen();
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on Object {
      return false;
    }
  }

  /// Whether this app may use picture-in-picture now (the system settings
  /// can turn it off per app).
  static Future<PipAvailability> availability() async {
    if (!_android) return PipAvailability.unsupported;
    _listen();
    try {
      return switch (await _channel.invokeMethod<String>('status')) {
        'allowed' => PipAvailability.allowed,
        'disabled' => PipAvailability.disabled,
        _ => PipAvailability.unsupported,
      };
    } on Object {
      return PipAvailability.unsupported;
    }
  }

  /// Enters picture-in-picture with the picture's [width]:[height] (the
  /// system limits the ratio to 2.39:1).
  static Future<PipEntry> enter({required int width, required int height}) async {
    if (!_android) return PipEntry.failed;
    _listen();
    try {
      return switch (await _channel.invokeMethod<Object>('enter', {'width': width, 'height': height})) {
        'entered' || true => PipEntry.entered,
        'disabled' => PipEntry.disabled,
        _ => PipEntry.failed,
      };
    } on Object {
      return PipEntry.failed;
    }
  }

  /// Opens this app's picture-in-picture page of the system settings (its
  /// details page where there is none). False when nothing opened.
  static Future<bool> openSettings() async {
    if (!_android) return false;
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on Object {
      return false;
    }
  }

  /// Lets leaving the app (home, recents) enter picture-in-picture by itself
  /// with the picture's [width]:[height] (J1: Android 12 and later animate
  /// it, 8-11 enter when the user leaves); [enabled] false stops that.
  static Future<void> setAutoEnter({required bool enabled, int width = 16, int height = 9}) async {
    if (!_android) return;
    _listen();
    try {
      await _channel.invokeMethod<void>('setAutoEnter', {'enabled': enabled, 'width': width, 'height': height});
    } on Object catch (error) {
      developer.log('Auto picture-in-picture failed', name: 'LivePlay', error: error);
    }
  }
}

/// The phone's media volume and the window's brightness
/// (`pure_live/device_controls` in `MainActivity`; 3.x used the
/// volume_controller and screen_brightness plugins). Null where there is
/// no such control (desktop, tests).
abstract final class DeviceControls {
  static const MethodChannel _channel = MethodChannel('pure_live/device_controls');

  /// Whether the controls exist on this platform.
  static bool get available => !kIsWeb && Platform.isAndroid;

  static Future<double?> _get(String method) async {
    if (!available) return null;
    try {
      return (await _channel.invokeMethod<num>(method))?.toDouble();
    } on Object {
      return null;
    }
  }

  static Future<void> _set(String method, double value) async {
    if (!available) return;
    try {
      await _channel.invokeMethod<void>(method, {'value': value.clamp(0.0, 1.0)});
    } on Object catch (error) {
      developer.log('$method failed', name: 'LivePlay', error: error);
    }
  }

  /// The media volume, 0 to 1.
  static Future<double?> volume() => _get('getVolume');

  /// Sets the media volume without the system's volume panel.
  static Future<void> setVolume(double value) => _set('setVolume', value);

  /// The window's brightness, 0 to 1 (the system's when not overridden).
  static Future<double?> brightness() => _get('getBrightness');

  /// Overrides the window's brightness.
  static Future<void> setBrightness(double value) => _set('setBrightness', value);

  /// Gives the brightness back to the system (leaving the room).
  static Future<void> resetBrightness() async {
    if (!available) return;
    try {
      await _channel.invokeMethod<void>('resetBrightness');
    } on Object {
      // The window is gone.
    }
  }
}

/// Android's wake and Wi-Fi locks while the room plays in the background
/// (`pure_live/background_playback`, 3.x `BackgroundPlaybackService`).
abstract final class BackgroundKeepAlive {
  static const MethodChannel _channel = MethodChannel('pure_live/background_playback');
  static bool? _applied;

  /// Holds or releases the locks.
  static Future<void> set({required bool enabled}) async {
    if (kIsWeb || !Platform.isAndroid || _applied == enabled) return;
    _applied = enabled;
    try {
      await _channel.invokeMethod<void>('setKeepAlive', {'enabled': enabled});
    } on Object catch (error) {
      developer.log('Keep-alive failed', name: 'LivePlay', error: error);
    }
  }
}

/// The handler behind the system media notification: its buttons call the
/// room's commands.
class _RoomAudioHandler extends audio.BaseAudioHandler {
  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function()? onStop;

  @override
  Future<void> play() async {
    await onPlay?.call();
  }

  @override
  Future<void> pause() async {
    await onPause?.call();
  }

  @override
  Future<void> stop() async {
    await onStop?.call();
    playbackState.add(playbackState.value.copyWith(playing: false, processingState: audio.AudioProcessingState.idle));
  }
}

/// The media notification's buttons with the app's words, so a screen
/// reader says "暂停" instead of audio_service's "Pause" (U.14 c6).
@visibleForTesting
List<audio.MediaControl> mediaControls({required bool playing}) => [
  if (playing)
    audio.MediaControl(
      androidIcon: audio.MediaControl.pause.androidIcon,
      label: i18n('media_pause'),
      action: audio.MediaAction.pause,
    )
  else
    audio.MediaControl(
      androidIcon: audio.MediaControl.play.androidIcon,
      label: i18n('media_play'),
      action: audio.MediaAction.play,
    ),
  audio.MediaControl(
    androidIcon: audio.MediaControl.stop.androidIcon,
    label: i18n('media_stop'),
    action: audio.MediaAction.stop,
  ),
];

/// The system media notification of the room playing (3.x
/// `LiveAudioService` + `LiveAudioHandler`, audio_service): title,
/// streamer, cover, play/pause and stop; on Android only.
abstract final class RoomMediaNotification {
  static Future<_RoomAudioHandler?>? _handler;
  static Object? _owner;

  /// Whether this platform shows it.
  static bool get available => !kIsWeb && Platform.isAndroid;

  static Future<_RoomAudioHandler?> _ensure() => _handler ??= () async {
    try {
      return await audio.AudioService.init(
        builder: _RoomAudioHandler.new,
        config: audio.AudioServiceConfig(
          androidNotificationChannelId: 'com.mystyle.purelive.audio',
          androidNotificationChannelName: i18n('audio_channel_name'),
          androidNotificationOngoing: true,
          // The one-colour television of the status bar (U.14 c2; 3.x used
          // the launcher icon, a white blob there).
          androidNotificationIcon: 'drawable/ic_stat_playback',
        ),
      );
    } on Object catch (error, stackTrace) {
      developer.log('Media notification failed', name: 'LivePlay', error: error, stackTrace: stackTrace);
      return null;
    }
  }();

  /// Shows [room] for [owner] (the room page) with its commands.
  static Future<void> show({
    required Object owner,
    required LiveRoom room,
    required bool playing,
    required Future<void> Function() play,
    required Future<void> Function() pause,
    required Future<void> Function() stop,
  }) async {
    if (!available) return;
    _owner = owner;
    final handler = await _ensure();
    if (handler == null || !identical(_owner, owner)) return;
    handler
      ..onPlay = play
      ..onPause = pause
      ..onStop = stop;
    final cover = Uri.tryParse(room.cover.trim());
    handler.mediaItem.add(
      audio.MediaItem(
        id: '${room.platform}/${room.roomId}',
        title: room.title.trim().isEmpty ? room.displayNick(room.platform) : room.title,
        artist: room.displayNick(room.platform),
        artUri: cover != null && cover.hasScheme && cover.scheme.startsWith('http') ? cover : null,
      ),
    );
    update(owner: owner, playing: playing);
  }

  /// Shows [playing] on the notification of [owner].
  static void update({required Object owner, required bool playing}) {
    if (!available || !identical(_owner, owner)) return;
    unawaited(
      _ensure().then((handler) {
        if (handler == null || !identical(_owner, owner)) return;
        handler.playbackState.add(
          audio.PlaybackState(
            controls: mediaControls(playing: playing),
            androidCompactActionIndices: const [0, 1],
            processingState: audio.AudioProcessingState.ready,
            playing: playing,
          ),
        );
      }),
    );
  }

  /// Removes the notification of [owner].
  static Future<void> hide(Object owner) async {
    if (!available || !identical(_owner, owner)) return;
    _owner = null;
    final handler = await _ensure();
    if (handler == null || _owner != null) return;
    handler
      ..onPlay = null
      ..onPause = null
      ..onStop = null
      ..playbackState.add(audio.PlaybackState());
  }
}

/// The room's background policy (3.x `PlaybackLifecycleCoordinator`):
/// leaving the app pauses after [hiddenPauseDelay] unless background play
/// is on or a sleep session runs (`shouldContinueInBackground`), and
/// coming back resumes what it paused. A picture nobody sees is not
/// judged stalled (`setPresentationVisible`); while it may play in the
/// background the wake/Wi-Fi locks are held and the media notification is
/// shown (from the foreground: Android refuses to start it later).
class RoomBackgroundPolicy with WidgetsBindingObserver {
  /// Creates the policy for [controller]; call [start].
  new({required this.controller, required this.settings, this.hiddenPauseDelay = const Duration(milliseconds: 1500)});

  /// The room.
  final LiveRoomController controller;

  /// `enableBackgroundPlay`.
  final SettingsStore settings;

  /// Android reports a short hidden/paused pair while rotating or entering
  /// picture-in-picture; only a longer stay counts (3.x 1.5 s).
  final Duration hiddenPauseDelay;

  Timer? _pauseTimer;
  bool _hidden = false;
  bool _pausedByUs = false;
  bool _started = false;
  StreamSubscription<PlaybackState>? _states;

  PlaybackSession get _session => controller.session;

  bool get _continues => shouldContinueInBackground(
    backgroundPlaybackEnabled: settings.get(Settings.enableBackgroundPlay),
    sleepSessionActive: controller.sleepSessionActive,
  );

  /// Starts following the app's lifecycle and the room's playback.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _states = _session.states.listen((_) => _syncNotification());
    controller.addListener(_syncNotification);
  }

  bool _notified = false;

  void _syncNotification() {
    final status = _session.state.status;
    final active = status == PlaybackStatus.playing || status == PlaybackStatus.buffering;
    PictureInPicture.bindPlayback(owner: this, playing: active, play: _session.resume, pause: _session.pause);
    final wanted = (active || status == PlaybackStatus.paused) && _continues;
    if (wanted && !_notified) {
      // Only shown from the foreground or while already shown.
      if (_hidden) return;
      _notified = true;
      unawaited(
        RoomMediaNotification.show(
          owner: this,
          room: controller.room,
          playing: active,
          play: _session.resume,
          pause: _session.pause,
          stop: _session.pause,
        ),
      );
    } else if (wanted) {
      RoomMediaNotification.update(owner: this, playing: active);
    } else if (!wanted && _notified && status != PlaybackStatus.opening) {
      _notified = false;
      unawaited(RoomMediaNotification.hide(this));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached:
        onHidden();
      case AppLifecycleState.resumed:
        onResumed();
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// The app left the screen.
  @visibleForTesting
  void onHidden() {
    if (_hidden) return;
    _hidden = true;
    _session.setPresentationVisible(visible: false);
    if (_continues) {
      unawaited(BackgroundKeepAlive.set(enabled: true));
      return;
    }
    _pauseTimer?.cancel();
    _pauseTimer = Timer(hiddenPauseDelay, () {
      _pauseTimer = null;
      if (!_hidden || _continues) return;
      final status = _session.state.status;
      if (status == PlaybackStatus.paused || status == PlaybackStatus.idle || status == PlaybackStatus.stopped) return;
      _pausedByUs = true;
      unawaited(_session.pause());
    });
  }

  /// The app is back on screen.
  @visibleForTesting
  void onResumed() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
    if (!_hidden) return;
    _hidden = false;
    _session.setPresentationVisible(visible: true);
    unawaited(BackgroundKeepAlive.set(enabled: false));
    if (_pausedByUs) {
      _pausedByUs = false;
      unawaited(_session.resume());
    }
    _syncNotification();
  }

  /// Stops following; releases the locks and the notification.
  void dispose() {
    _pauseTimer?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_syncNotification);
    unawaited(_states?.cancel());
    unawaited(BackgroundKeepAlive.set(enabled: false));
    unawaited(RoomMediaNotification.hide(this));
    PictureInPicture.unbindPlayback(this);
  }
}
