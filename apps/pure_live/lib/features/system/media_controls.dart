import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:live_media/live_media.dart';
import 'package:pure_live_app/features/system/now_playing.dart';

/// A command from the media notification, lock screen, headset buttons,
/// media keys or SMTC.
enum MediaCommand {
  /// Play.
  play,

  /// Pause.
  pause,

  /// Stop: pause and remove the controls until the user plays again.
  stop,
}

/// What the system media controls show.
@immutable
final class MediaInfo {
  /// Creates the information.
  const new({required this.id, required this.title, required this.artist, this.album, this.artwork});

  /// The information of [playing].
  factory of(NowPlaying playing) => MediaInfo(
    id: playing.room.key,
    title: playing.title,
    artist: playing.anchor,
    album: playing.platformName,
    artwork: playing.cover,
  );

  /// Room key.
  final String id;

  /// Room title.
  final String title;

  /// Streamer.
  final String artist;

  /// Platform name.
  final String? album;

  /// Cover image.
  final Uri? artwork;

  @override
  bool operator ==(Object other) =>
      other is MediaInfo &&
      other.id == id &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.artwork == artwork;

  @override
  int get hashCode => Object.hash(id, title, artist, album, artwork);
}

/// System media controls: the Android media session and notification, or the
/// Windows System Media Transport Controls.
abstract interface class MediaControls {
  /// Commands from the controls.
  Stream<MediaCommand> get commands;

  /// Shows [info] as playing or paused.
  Future<void> show(MediaInfo info, {required bool playing});

  /// Removes the controls.
  Future<void> hide();
}

/// Controls on platforms without system media controls.
final class NoMediaControls implements MediaControls {
  /// Creates the no-op controls.
  const new();

  @override
  Stream<MediaCommand> get commands => const Stream.empty();

  @override
  Future<void> show(MediaInfo info, {required bool playing}) async {}

  @override
  Future<void> hide() async {}
}

/// Mirrors [NowPlaying] on [controls] and routes their commands to the
/// session (F-BG-01, F-NEW-12).
///
/// Updates go out on their own path with only the latest one pending, so a
/// slow platform never delays or rolls back playback (AUD-5). The controls
/// show while [enabled] holds and the session has a room open; "stop" pauses
/// and hides them until the user plays again.
final class MediaControlsBridge {
  /// Creates the bridge and listens to [controls].
  new({required this.controls, required this.enabled}) {
    _commands = controls.commands.listen(_onCommand);
  }

  /// The platform controls.
  final MediaControls controls;

  /// Whether the controls may show (Android: the "后台播放" setting).
  final bool Function() enabled;

  late final StreamSubscription<MediaCommand> _commands;
  StreamSubscription<PlaybackState>? _states;
  NowPlaying? _playing;
  var _dismissed = false;

  // Latest-only delivery; null means hidden.
  (MediaInfo, bool)? _shown;
  (MediaInfo, bool)? _next;
  var _hasNext = false;
  var _sending = false;

  /// Follows [playing] (null when nothing plays).
  void attach(NowPlaying? playing) {
    if (identical(playing, _playing)) return;
    final sameSession = identical(playing?.session, _playing?.session);
    _playing = playing;
    if (!sameSession) {
      unawaited(_states?.cancel());
      _states = playing?.session.states.listen((_) => refresh());
      _dismissed = false;
    }
    refresh();
  }

  /// Re-evaluates after a state or setting change.
  void refresh() {
    final playing = _playing;
    final state = playing?.session.state;
    if (state != null && state.wantsPlay) _dismissed = false;
    final visible = playing != null && state != null && !_dismissed && enabled() && state.phase != PlaybackPhase.idle;
    _send(visible ? (MediaInfo.of(playing), showsPlaying(state)) : null);
  }

  /// Whether the controls show "playing" for [state]: the user wants to play
  /// and no suspension holds it.
  static bool showsPlaying(PlaybackState state) => state.wantsPlay && state.phase != PlaybackPhase.suspended;

  void _onCommand(MediaCommand command) {
    final session = _playing?.session;
    if (session == null) return;
    switch (command) {
      case MediaCommand.play:
        _dismissed = false;
        runSessionCommand(session.play);
      case MediaCommand.pause:
        runSessionCommand(session.pause);
      case MediaCommand.stop:
        _dismissed = true;
        runSessionCommand(session.pause);
        refresh();
    }
  }

  void _send((MediaInfo, bool)? next) {
    if (next == _shown && !_hasNext) return;
    _next = next;
    _hasNext = true;
    if (!_sending) unawaited(_drain());
  }

  Future<void> _drain() async {
    _sending = true;
    while (_hasNext) {
      final next = _next;
      _hasNext = false;
      if (next == _shown) continue;
      _shown = next;
      try {
        if (next == null) {
          await controls.hide();
        } else {
          await controls.show(next.$1, playing: next.$2);
        }
      } on Object {
        // The controls are best effort; playback does not depend on them.
      }
    }
    _sending = false;
  }

  /// Stops following and hides the controls.
  Future<void> dispose() async {
    await _commands.cancel();
    await _states?.cancel();
    _playing = null;
    _send(null);
  }
}
