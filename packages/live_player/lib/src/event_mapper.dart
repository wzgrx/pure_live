import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:live_media/live_media.dart';
import 'package:media_kit/media_kit.dart';

/// The media_kit streams an engine maps; `PlayerStream` in production, fake
/// controllers in tests.
@immutable
final class MediaKitStreams {
  /// Creates the set.
  const new({
    required this.playing,
    required this.completed,
    required this.buffering,
    required this.position,
    required this.duration,
    required this.tracks,
    required this.videoParams,
    required this.log,
  });

  /// The streams of a real player.
  new of(PlayerStream stream)
    : playing = stream.playing,
      completed = stream.completed,
      buffering = stream.buffering,
      position = stream.position,
      duration = stream.duration,
      tracks = stream.tracks,
      videoParams = stream.videoParams,
      log = stream.log;

  /// `playing`.
  final Stream<bool> playing;

  /// `completed`.
  final Stream<bool> completed;

  /// `buffering`.
  final Stream<bool> buffering;

  /// `position`.
  final Stream<Duration> position;

  /// `duration`.
  final Stream<Duration> duration;

  /// `tracks`.
  final Stream<Tracks> tracks;

  /// `videoParams`.
  final Stream<VideoParams> videoParams;

  /// `log` (error level with the player's default log level).
  final Stream<PlayerLog> log;
}

/// Maps media_kit's separate streams onto one `EngineEvent` stream in
/// arrival order, which is the order the recorded traces show (spec §4).
///
/// - Track lists lose media_kit's `auto`/`no` pseudo tracks.
/// - The decoded size comes from `videoParams` (display size, else coded
///   size) and is emitted when it changes.
/// - Only error-level log lines that pass [isActionableDiagnostic] become
///   [EngineError] (EVT-7); media_kit's own `error` stream is not used, it
///   repeats a subset of the same lines.
/// - `frames` (the patched `VideoController.frameRevision`, Windows) becomes
///   [EngineFrame].
final class MediaKitEventMapper {
  /// Starts mapping.
  new(MediaKitStreams streams, {ValueListenable<int>? frames}) : _frames = frames {
    _subscriptions.addAll([
      streams.playing.listen((value) => _emit(EnginePlaying(value))),
      streams.completed.listen((value) => _emit(EngineCompleted(value))),
      streams.buffering.listen((value) => _emit(EngineBuffering(value))),
      streams.position.listen((value) => _emit(EnginePosition(value))),
      streams.duration.listen((value) => _emit(EngineDuration(value))),
      streams.tracks.listen((tracks) => _emit(EngineTracks(video: _real(tracks.video), audio: _real(tracks.audio)))),
      streams.videoParams.listen(_onVideoParams),
      streams.log.listen(_onLog),
    ]);
    frames?.addListener(_onFrame);
  }

  final ValueListenable<int>? _frames;
  final _controller = StreamController<EngineEvent>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  ({int? width, int? height})? _size;

  /// Mapped events.
  Stream<EngineEvent> get events => _controller.stream;

  static int _real(List<Object> tracks) => tracks.where((track) {
    final id = switch (track) {
      VideoTrack(:final id) => id,
      AudioTrack(:final id) => id,
      _ => '',
    };
    return id != 'auto' && id != 'no';
  }).length;

  void _emit(EngineEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  void _onVideoParams(VideoParams params) {
    final width = params.dw ?? params.w;
    final height = params.dh ?? params.h;
    final current = _size;
    if (current != null && current.width == width && current.height == height) return;
    _size = (width: width, height: height);
    _emit(EngineVideoSize(width, height));
  }

  void _onLog(PlayerLog log) {
    if (log.level != 'error' || !isActionableDiagnostic(log.prefix, log.text)) return;
    _emit(EngineError(log.text, prefix: log.prefix));
  }

  void _onFrame() {
    final frames = _frames;
    if (frames != null) _emit(EngineFrame(frames.value));
  }

  /// Stops mapping.
  Future<void> close() async {
    _frames?.removeListener(_onFrame);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    await _controller.close();
  }
}
