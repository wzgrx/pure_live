import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio;
import 'package:flutter/services.dart';
import 'package:pure_live_app/features/system/media_controls.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// The Android media session, notification and foreground service through
/// audio_service (F-BG-01): play/pause/close in the notification, lock
/// screen and headset buttons. audio_service also holds the partial wake lock
/// while playing; the Wi-Fi lock is [WifiLock].
///
/// The service starts the first time the controls show, which happens while
/// a room plays in the foreground, so the Android 12+ background start limits
/// do not apply. It stays in the foreground while paused
/// (`androidStopForegroundOnPause: false`), so resuming after an audio
/// interruption in the background needs no new foreground start.
final class AndroidMediaControls implements MediaControls {
  /// Creates the controls; audio_service initialises on first [show].
  new();

  final _commands = StreamController<MediaCommand>.broadcast();
  Future<_LiveAudioHandler>? _handler;

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  Future<_LiveAudioHandler> _init() => _handler ??= audio.AudioService.init(
    builder: () => _LiveAudioHandler(_commands.add),
    config: audio.AudioServiceConfig(
      androidNotificationChannelId: 'com.mystyle.purelive.playback',
      androidNotificationChannelName: t.settings.playback.background,
      androidNotificationChannelDescription: t.system.backgroundChannelDescription,
      androidNotificationIcon: 'drawable/ic_launcher_monochrome',
      androidStopForegroundOnPause: false,
    ),
  );

  @override
  Future<void> show(MediaInfo info, {required bool playing}) async {
    final handler = await _init();
    handler.mediaItem.add(
      audio.MediaItem(
        id: info.id,
        title: info.title,
        artist: info.artist,
        album: info.album,
        artUri: info.artwork,
        isLive: true,
      ),
    );
    handler.playbackState.add(
      audio.PlaybackState(
        processingState: audio.AudioProcessingState.ready,
        playing: playing,
        controls: [if (playing) audio.MediaControl.pause else audio.MediaControl.play, audio.MediaControl.stop],
        androidCompactActionIndices: const [0, 1],
        systemActions: const {audio.MediaAction.play, audio.MediaAction.pause, audio.MediaAction.playPause},
      ),
    );
  }

  @override
  Future<void> hide() async {
    final pending = _handler;
    if (pending == null) return;
    final handler = await pending;
    // An idle processing state stops the service and removes the notification.
    handler.playbackState.add(audio.PlaybackState());
    handler.mediaItem.add(null);
  }
}

final class _LiveAudioHandler extends audio.BaseAudioHandler {
  new(this._command);

  final void Function(MediaCommand command) _command;

  @override
  Future<void> play() async => _command(MediaCommand.play);

  @override
  Future<void> pause() async => _command(MediaCommand.pause);

  @override
  Future<void> stop() async => _command(MediaCommand.stop);

  @override
  Future<void> onTaskRemoved() async {
    // Swiping the app away while paused ends the notification; while playing,
    // background play continues until "close".
    if (!playbackState.value.playing) _command(MediaCommand.stop);
  }
}

/// The Wi-Fi lock for background playback (PERF-2), held by
/// `PlaybackLocks.kt` on channel `purelive/playback`.
final class WifiLock {
  /// Creates the lock client.
  new([MethodChannel? channel]) : _channel = channel ?? const MethodChannel('purelive/playback');

  final MethodChannel _channel;
  bool? _held;

  /// Holds or releases the lock; repeated values are not sent again.
  Future<void> set({required bool held}) async {
    if (_held == held) return;
    _held = held;
    try {
      await _channel.invokeMethod<void>('setWifiLock', {'held': held});
    } on PlatformException {
      _held = null;
    } on MissingPluginException {
      _held = null;
    }
  }
}
