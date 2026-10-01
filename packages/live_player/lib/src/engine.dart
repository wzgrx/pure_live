import 'dart:async';

import 'package:live_media/live_media.dart';
import 'package:meta/meta.dart';

/// What the session hands the engine for one open (3.x passed the URL,
/// headers and a private-input flag through separate adapter calls).
@immutable
final class EngineMedia {
  /// Creates the media.
  const new({
    required this.uri,
    this.headers = const {},
    this.proxyUrl = '',
    this.decoder = DecoderMode.hardware,
    this.audioOnly = false,
    this.onDemand = false,
    this.start,
  });

  /// The media of [input] with the session's decoder and audio mode.
  factory of(MediaInput input, {DecoderMode decoder = DecoderMode.hardware, bool audioOnly = false}) => EngineMedia(
    uri: input.uri,
    headers: input.headers,
    proxyUrl: input.proxyUrl,
    decoder: decoder,
    audioOnly: audioOnly,
    onDemand: input.onDemand,
    start: input.start,
  );

  /// The URL to open (a loopback URL for relayed inputs).
  final Uri uri;

  /// Request headers (User-Agent, Referer, Cookie).
  final Map<String, String> headers;

  /// mpv's `http-proxy` ('' for none; always '' for a loopback input).
  final String proxyUrl;

  /// Hardware or software decoding for this open.
  final DecoderMode decoder;

  /// Open without video output (the room's audio-only mode).
  final bool audioOnly;

  /// A recording: its end is normal and it seeks.
  final bool onDemand;

  /// Where to start an on-demand input.
  final Duration? start;

  @override
  String toString() => 'EngineMedia(${uri.scheme}://${uri.host}, ${decoder.name}${audioOnly ? ', audio only' : ''})';
}

/// One event of the engine, in arrival order.
@immutable
sealed class EngineEvent {
  const new();
}

/// The engine started or stopped advancing playback.
final class EnginePlaying extends EngineEvent {
  /// Creates the event.
  const new({required this.playing});

  /// Whether it plays.
  final bool playing;

  @override
  String toString() => 'EnginePlaying($playing)';
}

/// The engine waits for data (or stopped waiting).
final class EngineBuffering extends EngineEvent {
  /// Creates the event.
  const new({required this.buffering});

  /// Whether it waits.
  final bool buffering;

  @override
  String toString() => 'EngineBuffering($buffering)';
}

/// The source ended (mpv end-of-file).
final class EngineCompleted extends EngineEvent {
  /// Creates the event.
  const new();

  @override
  String toString() => 'EngineCompleted()';
}

/// The displayed video size changed (rotation applied).
final class EngineVideoSize extends EngineEvent {
  /// Creates the event.
  const new(this.width, this.height);

  /// Display width in pixels.
  final int width;

  /// Display height in pixels.
  final int height;

  @override
  String toString() => 'EngineVideoSize($width x $height)';
}

/// The playback position of an on-demand source.
final class EnginePosition extends EngineEvent {
  /// Creates the event.
  const new(this.position);

  /// The position.
  final Duration position;
}

/// The duration of an on-demand source.
final class EngineDuration extends EngineEvent {
  /// Creates the event.
  const new(this.duration);

  /// The duration.
  final Duration duration;
}

/// A presented video frame (Windows: the fork's `frameRevision`). Only a
/// heartbeat: it says nothing about the frame rate.
final class EngineFrame extends EngineEvent {
  /// Creates the event.
  const new();
}

/// A confirmed failure of the current source (the engine already gave
/// recoverable diagnostics their grace window).
final class EngineError extends EngineEvent {
  /// Creates the event.
  const new(this.error);

  /// The failure.
  final PlayerException error;

  @override
  String toString() => 'EngineError($error)';
}

/// The engine contract the session drives (3.x's `UnifiedPlayer`, reduced to
/// what the one mpv engine needs). Implementations: `MpvEngine`, and fakes in
/// tests.
abstract interface class PlayerEngine {
  /// Events of every source, in arrival order.
  Stream<EngineEvent> get events;

  /// Whether [EngineFrame]s are reported, so a frame watchdog applies.
  bool get reportsFrames;

  /// Opens [media] and starts playing. Throws when the open fails.
  Future<void> open(EngineMedia media);

  /// Resumes playback.
  Future<void> play();

  /// Pauses playback.
  Future<void> pause();

  /// Unloads the media but keeps the engine.
  Future<void> stop();

  /// Seeks an on-demand source.
  Future<void> seek(Duration position);

  /// Sets the volume, 0 to 1.
  Future<void> setVolume(double volume);

  /// Turns video output off or on without reopening the source.
  Future<void> setAudioOnly({required bool enabled});

  /// Releases the engine.
  Future<void> dispose();
}

/// Creates an engine on first need.
typedef EngineFactory = Future<PlayerEngine> Function();
