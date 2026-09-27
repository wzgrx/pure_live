import 'dart:async';

import 'package:meta/meta.dart';

/// What an engine plays for one source generation (spec/modules/playback.md §3).
@immutable
final class EngineMedia {
  /// Creates the media description.
  const new({
    required this.uri,
    this.headers = const {},
    this.local = false,
    this.softwareDecoding = false,
    this.audioOnly = false,
  });

  /// Media URI: the CDN URL for a direct line, a loopback URL for a relayed one.
  final Uri uri;

  /// Request headers (lower-case names); empty for a loopback input, whose
  /// relay sends the line's headers upstream itself.
  final Map<String, String> headers;

  /// A loopback relay input: the engine must not route it through an HTTP
  /// proxy (SRC-3).
  final bool local;

  /// Decode video in software for this open (REC-1 step 4).
  final bool softwareDecoding;

  /// Open with video output disabled (§7).
  final bool audioOnly;

  @override
  String toString() => 'EngineMedia($uri${local ? ', local' : ''}${softwareDecoding ? ', software' : ''})';
}

/// Optional abilities of an engine implementation.
@immutable
final class EngineCapabilities {
  /// Creates the capability set.
  const new({this.frameProgress = false});

  /// Emits [EngineFrame] when a new frame is presented (Windows texture,
  /// EVT-11). Without it, the first-frame fence uses "playing and a non-zero
  /// video size" (MON-5) and no frame-stall watchdog runs.
  final bool frameProgress;
}

/// One engine event. Engines emit them in the order the real library does
/// (spec §4); test doubles replay recorded traces instead of inventing orders.
@immutable
sealed class EngineEvent {
  const new();
}

/// The engine started or stopped advancing. `playing=true` right after open
/// only means "trying to play" (EVT-13); at end of stream `playing=false`
/// arrives before `completed=true` (EVT-1, EVT-14).
final class EnginePlaying extends EngineEvent {
  /// Creates the event.
  // A value event: the flag is the whole payload.
  // ignore: avoid_positional_boolean_parameters
  const new(this.playing);

  /// Whether the engine reports playing.
  final bool playing;

  @override
  String toString() => 'playing=$playing';
}

/// The media reached its end (for a live stream: the connection ended, EVT-15, EVT-16).
final class EngineCompleted extends EngineEvent {
  /// Creates the event.
  // A value event: the flag is the whole payload.
  // ignore: avoid_positional_boolean_parameters
  const new(this.completed);

  /// Whether the engine reports completed.
  final bool completed;

  @override
  String toString() => 'completed=$completed';
}

/// The engine waits for data.
final class EngineBuffering extends EngineEvent {
  /// Creates the event.
  // A value event: the flag is the whole payload.
  // ignore: avoid_positional_boolean_parameters
  const new(this.buffering);

  /// Whether the engine is buffering.
  final bool buffering;

  @override
  String toString() => 'buffering=$buffering';
}

/// Playback position.
final class EnginePosition extends EngineEvent {
  /// Creates the event.
  const new(this.position);

  /// Position.
  final Duration position;

  @override
  String toString() => 'position=${position.inMilliseconds}';
}

/// Reported duration; for a live stream without metadata this is the growing
/// buffered length, not zero (EVT-19).
final class EngineDuration extends EngineEvent {
  /// Creates the event.
  const new(this.duration);

  /// Duration.
  final Duration duration;

  @override
  String toString() => 'duration=${duration.inMilliseconds}';
}

/// Decoded video size; null or zero means no picture (EVT-8).
final class EngineVideoSize extends EngineEvent {
  /// Creates the event.
  const new(this.width, this.height);

  /// Width in pixels.
  final int? width;

  /// Height in pixels.
  final int? height;

  /// Whether both dimensions are positive.
  bool get hasPicture => (width ?? 0) > 0 && (height ?? 0) > 0;

  @override
  String toString() => 'size=${width}x$height';
}

/// Real tracks of the current media (without the engine's `auto`/`no`
/// pseudo tracks); both reset to zero at the end of a stream (EVT-14).
final class EngineTracks extends EngineEvent {
  /// Creates the event.
  const new({required this.video, required this.audio});

  /// Video track count.
  final int video;

  /// Audio track count.
  final int audio;

  @override
  String toString() => 'tracks=v$video/a$audio';
}

/// A new frame reached the screen ([EngineCapabilities.frameProgress]); at
/// most twice a second on Windows (EVT-11).
final class EngineFrame extends EngineEvent {
  /// Creates the event.
  const new(this.revision);

  /// Monotonic frame revision.
  final int revision;

  @override
  String toString() => 'frame=$revision';
}

/// An error-level native diagnostic that passed `isActionableDiagnostic`
/// (EVT-7). Open failures report only this, without resetting playing or
/// buffering (EVT-17).
final class EngineError extends EngineEvent {
  /// Creates the event.
  const new(this.message, {this.prefix});

  /// Diagnostic text.
  final String message;

  /// mpv log prefix (`cplayer`, `vd`, `ffmpeg/video`…), if known.
  final String? prefix;

  @override
  String toString() => 'error=${prefix == null ? '' : '[$prefix] '}$message';
}

/// The single player engine interface (ADR 0015). The only production
/// implementation is `MpvEngine` in live_player; tests use `FakeEngine`
/// from `package:live_media/testing.dart`.
///
/// Commands may be called only from one serial owner (the playback session,
/// SES-2); implementations do not need to be reentrant.
abstract interface class PlayerEngine {
  /// What this engine can report.
  EngineCapabilities get capabilities;

  /// Engine events in the library's own order. A broadcast stream.
  Stream<EngineEvent> get events;

  /// Opens [media] and starts playing it. Completes when the native open
  /// command returns, which says nothing about a picture (EVT-8); errors may
  /// arrive on [events] before it completes (EVT-5).
  Future<void> open(EngineMedia media);

  /// Resumes playback.
  Future<void> play();

  /// Pauses playback.
  Future<void> pause();

  /// Unloads the media but keeps the engine (soft stop, SES-7).
  Future<void> stop();

  /// Sets the output volume, 0 to 1.
  Future<void> setVolume(double volume);

  /// Turns video decoding off or on without reopening (AUD-1). Turning video
  /// back on completes once a new picture is ready or a bounded wait passed (AUD-2).
  Future<void> setAudioOnly({required bool enabled});

  /// Releases the engine; completes when the native release finished (SES-8).
  Future<void> dispose();
}

/// Creates an engine on first use (SES-1).
typedef EngineFactory = FutureOr<PlayerEngine> Function();
