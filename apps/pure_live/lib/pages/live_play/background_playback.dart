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
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/live_play/room_controller.dart';

/// Android's system picture-in-picture (`pure_live/pip` in `MainActivity`;
/// 3.x used the floating plugin). [active] follows the activity.
abstract final class PictureInPicture {
  static const MethodChannel _channel = MethodChannel('pure_live/pip');
  static bool _listening = false;

  /// Whether the activity is in picture-in-picture now.
  static final ValueNotifier<bool> active = ValueNotifier(false);

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') active.value = call.arguments == true;
    });
  }

  /// Whether this device offers picture-in-picture.
  static Future<bool> supported() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    _listen();
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on Object {
      return false;
    }
  }

  /// Enters picture-in-picture with the picture's [width]:[height] (the
  /// system limits the ratio to 2.39:1).
  static Future<bool> enter({required int width, required int height}) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    _listen();
    try {
      return await _channel.invokeMethod<bool>('enter', {'width': width, 'height': height}) ?? false;
    } on Object {
      return false;
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
            controls: [if (playing) audio.MediaControl.pause else audio.MediaControl.play, audio.MediaControl.stop],
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
  }
}
