import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:meta/meta.dart';

/// Where the session is (3.x's `PlayerState`, without the adapter-only
/// steps `initializing`, `initialized`, `ready` and `disposed`).
enum PlaybackStatus {
  /// Nothing opened.
  idle,

  /// Opening a source (resolving the input, loading it into the engine).
  opening,

  /// Opened and waiting for data, or recovering from a failure.
  buffering,

  /// Playing.
  playing,

  /// Paused by the user.
  paused,

  /// An on-demand source played to its end (not a failure).
  completed,

  /// Recovery is exhausted or the stream cannot be played; see the error.
  error,

  /// Stopped by the caller.
  stopped,
}

/// One snapshot of the session for the interface.
@immutable
final class PlaybackState {
  /// Creates a snapshot.
  const new({
    this.status = PlaybackStatus.idle,
    this.error,
    this.failure,
    this.source,
    this.line,
    this.lineIndex = 0,
    this.lineCount = 0,
    this.decoder = DecoderMode.hardware,
    this.audioOnly = false,
    this.volume = 1,
    this.videoWidth,
    this.videoHeight,
    this.frameRate,
    this.onDemand = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.appliedQualityData,
    this.recovery = 0,
  });

  /// Where the session is.
  final PlaybackStatus status;

  /// The failure behind [PlaybackStatus.error].
  final Object? error;

  /// What the failure means ([SourceFailureKind.terminal]: the platform said
  /// the stream cannot be played now, so retrying is pointless).
  final SourceFailureKind? failure;

  /// The source the engine plays or opens.
  final PlaybackSource? source;

  /// The line the engine plays (after renewals, the renewed line).
  final LivePlayLine? line;

  /// Index of [source] in the plan (3.x's `currentLineIndex`).
  final int lineIndex;

  /// Number of sources in the plan (3.x's `lineCount`).
  final int lineCount;

  /// The decoder of the current open.
  final DecoderMode decoder;

  /// Whether video output is off.
  final bool audioOnly;

  /// The volume, 0 to 1.
  final double volume;

  /// Display width of the video, when known.
  final int? videoWidth;

  /// Display height of the video, when known.
  final int? videoHeight;

  /// Frames a second of the video, when known (U.2i).
  final double? frameRate;

  /// A recording: it seeks and its end is [PlaybackStatus.completed].
  final bool onDemand;

  /// Position of an on-demand source.
  final Duration position;

  /// Duration of an on-demand source.
  final Duration duration;

  /// The quality the platform applied (Picarto 11-1: after a refresh that
  /// lost the old tier, the interface shows what actually plays).
  final Object? appliedQualityData;

  /// The session's attempt, counting from 1, at bringing back a stream that
  /// failed on its own (a refreshed address, the next line, a new engine,
  /// software decoding, a retry round, a look at a network that is gone);
  /// 0 while nothing is being recovered. A live stream that stopped moving
  /// for `SessionTimings.stallNotice` is the first attempt already (G02.3);
  /// a reopened one ends its recovery once it moves again.
  /// The count runs on over drops in a row and starts again once the
  /// stream has played long enough to restore the session's recovery
  /// budgets (30 s by default). Buffering of a stream that has not failed,
  /// a resume and the user's own reopenings (a new open, another line,
  /// retry) are no recovery.
  final int recovery;

  /// Whether the session is bringing a failed stream back ([recovery]).
  bool get recovering => recovery > 0;

  /// Whether the session is playing or about to (3.x's `isPlayingNow`
  /// plus loading).
  bool get isActive => switch (status) {
    PlaybackStatus.opening || PlaybackStatus.buffering || PlaybackStatus.playing => true,
    _ => false,
  };

  /// Width over height of the video, when known.
  double? get aspectRatio {
    final width = videoWidth;
    final height = videoHeight;
    if (width == null || height == null || width <= 0 || height <= 0) return null;
    return width / height;
  }

  /// Whether the video is taller than wide (3.x's `isVerticalVideo`).
  bool get isPortrait => (aspectRatio ?? 16 / 9) < 1;

  /// Width over height the platform declared for the line being opened or
  /// played ([LivePlayLine.declaredAspectRatio], 3.x's
  /// `LiveStreamGeometryHint`); null when it declared none and once the
  /// session is idle or stopped.
  double? get declaredAspectRatio {
    if (status == PlaybackStatus.idle || status == PlaybackStatus.stopped) return null;
    return switch (source) {
      LineSource() => line?.declaredAspectRatio,
      _ => null,
    };
  }

  /// Width over height to lay the picture out by: the decoded video's, and
  /// before the first frame the platform's [declaredAspectRatio] (3.x kept
  /// the hint provisional until the decoder spoke).
  double? get expectedAspectRatio => aspectRatio ?? declaredAspectRatio;

  /// [isPortrait] by [expectedAspectRatio]: a portrait stream is laid out
  /// as portrait before its first frame when the platform said so (F.1b).
  bool get expectsPortrait => (expectedAspectRatio ?? 16 / 9) < 1;

  /// A copy with the given fields replaced; [error] and [failure] are kept
  /// only while the status stays [PlaybackStatus.error]; [clearVideoSize]
  /// also forgets the frame rate.
  PlaybackState copyWith({
    PlaybackStatus? status,
    Object? error,
    SourceFailureKind? failure,
    PlaybackSource? source,
    LivePlayLine? line,
    int? lineIndex,
    int? lineCount,
    DecoderMode? decoder,
    bool? audioOnly,
    double? volume,
    int? videoWidth,
    int? videoHeight,
    double? frameRate,
    bool clearVideoSize = false,
    bool? onDemand,
    Duration? position,
    Duration? duration,
    Object? appliedQualityData,
    int? recovery,
  }) {
    final next = status ?? this.status;
    final keepError = next == PlaybackStatus.error;
    return PlaybackState(
      status: next,
      error: keepError ? error ?? this.error : null,
      failure: keepError ? failure ?? this.failure : null,
      source: source ?? this.source,
      line: line ?? this.line,
      lineIndex: lineIndex ?? this.lineIndex,
      lineCount: lineCount ?? this.lineCount,
      decoder: decoder ?? this.decoder,
      audioOnly: audioOnly ?? this.audioOnly,
      volume: volume ?? this.volume,
      videoWidth: clearVideoSize ? null : videoWidth ?? this.videoWidth,
      videoHeight: clearVideoSize ? null : videoHeight ?? this.videoHeight,
      // The frame rate goes with the size: both belong to the stream.
      frameRate: clearVideoSize ? null : frameRate ?? this.frameRate,
      onDemand: onDemand ?? this.onDemand,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      appliedQualityData: appliedQualityData ?? this.appliedQualityData,
      recovery: recovery ?? this.recovery,
    );
  }

  @override
  String toString() => 'PlaybackState(${status.name}, line ${lineIndex + 1}/$lineCount, ${decoder.name})';
}
