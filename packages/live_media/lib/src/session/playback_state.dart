import 'package:live_core/live_core.dart';
import 'package:meta/meta.dart';

/// Where a session is (spec/modules/playback.md §1, §5, §6).
enum PlaybackPhase {
  /// No room open.
  idle,

  /// Asking the platform for stream URLs.
  resolving,

  /// Opening a source; no playback yet in this source generation.
  connecting,

  /// Playing.
  playing,

  /// The user wants to play but the engine is buffering or not advancing
  /// (INT-1: shown as buffering, never as paused).
  stalled,

  /// The recovery chain is working (REC-5: buffering/reconnecting, no error).
  recovering,

  /// Paused by the user.
  paused,

  /// Paused for a non-user reason (background, audio interruption, INT-2).
  suspended,

  /// Terminal failure; the user can retry (REC-1 step 6).
  error,

  /// A non-live source (replay) reached its end (SES-11).
  ended,
}

/// The class of a playback failure, for the recovery chain (REC-1).
enum FailureKind {
  /// DNS, TCP, TLS, 5xx, or the open or refresh timed out.
  network(transport: true),

  /// 4xx, unrecognised data, no streams, or resolving the streams failed.
  source(transport: true),

  /// Buffering lasted 12 s (inferred).
  bufferingStall(transport: true, stall: true, inferred: true),

  /// A live stream reported completed (EVT-1, EVT-15, EVT-16).
  liveCompleted(transport: true, stall: true),

  /// playing=false without buffering that play() did not resolve (inferred).
  unexpectedPause(stall: true, inferred: true),

  /// The picture stopped advancing for 10 s (inferred).
  frameStall(stall: true, inferred: true),

  /// A video decoder failed.
  videoDecode,

  /// An audio decoder failed.
  audioDecode,

  /// The engine could not be created, or its output or lifecycle failed.
  engine(stall: true),

  /// The room has no stream (offline, region, login): not retried.
  unavailable,

  /// Recovery gave up: too many rounds in the window (REC-2).
  exhausted;

  new({this.transport = false, this.stall = false, this.inferred = false});

  /// Network or source class: signature refresh, line switch and backoff apply.
  final bool transport;

  /// Stall class: a same-engine rebuild applies.
  final bool stall;

  /// Inferred by a watchdog; later progress overturns it (MON-1).
  final bool inferred;
}

/// A playback failure.
@immutable
final class PlaybackFailure {
  /// Creates a failure.
  const new(this.kind, this.code, [this.message]);

  /// Class.
  final FailureKind kind;

  /// Stable code (`buffering_stall_timeout`, `source_open`…).
  final String code;

  /// Diagnostic text, if any.
  final String? message;

  @override
  bool operator ==(Object other) =>
      other is PlaybackFailure && other.kind == kind && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(kind, code, message);

  @override
  String toString() => 'PlaybackFailure(${kind.name}, $code${message == null ? '' : ': $message'})';
}

/// Orientation of the picture (§8).
enum VideoOrientation {
  /// Not decided yet in this source generation.
  unknown,

  /// Aspect ≤ 0.90.
  portrait,

  /// Aspect ≥ 1.10.
  landscape,

  /// In between.
  square,
}

/// Committed picture geometry (§8).
@immutable
final class VideoGeometry {
  /// Creates a geometry.
  const new({this.orientation = VideoOrientation.unknown, this.width, this.height});

  /// Nothing known.
  static const unknown = VideoGeometry();

  /// Orientation.
  final VideoOrientation orientation;

  /// Width the decision was based on.
  final int? width;

  /// Height the decision was based on.
  final int? height;

  /// Width / height, when known.
  double? get aspectRatio {
    final w = width;
    final h = height;
    return w == null || h == null || w <= 0 || h <= 0 ? null : w / h;
  }

  @override
  bool operator ==(Object other) =>
      other is VideoGeometry && other.orientation == orientation && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(orientation, width, height);

  @override
  String toString() => 'VideoGeometry(${orientation.name}, ${width}x$height)';
}

/// The snapshot published after a successful open (§0 源提交). Other modules
/// trust only the current commit.
@immutable
final class SourceCommit {
  /// Creates a commit.
  const new({
    required this.session,
    required this.intentRevision,
    required this.roomKey,
    required this.quality,
    required this.line,
    required this.audioOnly,
  });

  /// Session number.
  final int session;

  /// Intent revision at the commit.
  final int intentRevision;

  /// Room key (`douyu:9999`).
  final String roomKey;

  /// Quality selection.
  final Quality quality;

  /// Line playing.
  final StreamLine line;

  /// Whether video was off.
  final bool audioOnly;
}

/// Everything the UI renders about a session.
@immutable
final class PlaybackState {
  /// Creates a state.
  const new({
    this.phase = PlaybackPhase.idle,
    this.wantsPlay = false,
    this.roomKey,
    this.qualities = const [],
    this.quality,
    this.lines = const [],
    this.line,
    this.failure,
    this.audioOnly = false,
    this.hasPicture = false,
    this.videoWidth,
    this.videoHeight,
    this.geometry = VideoGeometry.unknown,
    this.engineRevision = 0,
    this.commit,
    this.notice,
  });

  /// Phase.
  final PlaybackPhase phase;

  /// The user's play intent (INT-1).
  final bool wantsPlay;

  /// Open room.
  final String? roomKey;

  /// Qualities offered.
  final List<Quality> qualities;

  /// Selected quality.
  final Quality? quality;

  /// Lines at the selected quality.
  final List<StreamLine> lines;

  /// Line playing or being opened.
  final StreamLine? line;

  /// Terminal failure, in [PlaybackPhase.error] only (REC-5).
  final PlaybackFailure? failure;

  /// Video off (§7).
  final bool audioOnly;

  /// A picture was decoded in this source generation (EVT-8); the app shows
  /// the mini window only with a picture (PIP-4).
  final bool hasPicture;

  /// Decoded width.
  final int? videoWidth;

  /// Decoded height.
  final int? videoHeight;

  /// Committed geometry (§8).
  final VideoGeometry geometry;

  /// Changes whenever the engine instance is created or released; the view
  /// rebinds its surface on change.
  final int engineRevision;

  /// Current source commit.
  final SourceCommit? commit;

  /// A non-terminal problem to mention once (an audio-mode switch that
  /// timed out and was rolled back, AUD-4).
  final String? notice;

  /// The UI shows a buffering or reconnecting indicator.
  bool get showsBuffering =>
      wantsPlay &&
      const {
        PlaybackPhase.resolving,
        PlaybackPhase.connecting,
        PlaybackPhase.stalled,
        PlaybackPhase.recovering,
      }.contains(phase);

  /// The UI shows "paused" (only after an explicit user pause, INT-1).
  bool get showsPaused => phase == PlaybackPhase.paused;

  @override
  bool operator ==(Object other) =>
      other is PlaybackState &&
      other.phase == phase &&
      other.wantsPlay == wantsPlay &&
      other.roomKey == roomKey &&
      identical(other.qualities, qualities) &&
      other.quality == quality &&
      identical(other.lines, lines) &&
      identical(other.line, line) &&
      other.failure == failure &&
      other.audioOnly == audioOnly &&
      other.hasPicture == hasPicture &&
      other.videoWidth == videoWidth &&
      other.videoHeight == videoHeight &&
      other.geometry == geometry &&
      other.engineRevision == engineRevision &&
      identical(other.commit, commit) &&
      other.notice == notice;

  @override
  int get hashCode => Object.hash(
    phase,
    wantsPlay,
    roomKey,
    quality,
    line,
    failure,
    audioOnly,
    hasPicture,
    videoWidth,
    videoHeight,
    geometry,
    engineRevision,
    commit,
    notice,
  );

  @override
  String toString() =>
      'PlaybackState(${phase.name}, wants=$wantsPlay, line=${line?.lineId}, quality=${quality?.id}'
      '${failure == null ? '' : ', $failure'}${audioOnly ? ', audio' : ''})';
}

/// Why playback is suspended (INT-2).
enum SuspendReason {
  /// The app went to the background (INT-3).
  background,

  /// Another app took audio focus (INT-4).
  audioFocus,
}

/// Returned by a suspension; resuming requires the same session and intent (INT-2).
@immutable
final class SuspendToken {
  /// Creates a token.
  const new(this.session, this.intentRevision, this.reason);

  /// Session number.
  final int session;

  /// Intent revision.
  final int intentRevision;

  /// Reason.
  final SuspendReason reason;
}

/// Resolves the stream set of the open room at [quality] (null: best).
typedef StreamResolver = Future<StreamSet> Function(Quality? quality);

/// What to play.
@immutable
final class PlaybackRequest {
  /// Creates a request for the room [roomKey] of platform [site].
  const new({
    required this.site,
    required this.roomKey,
    required this.resolve,
    this.initial,
    this.quality,
    this.lineId,
    this.continuousLive = true,
  });

  /// A live room through its platform adapter.
  new room(StreamSource source, RoomDetail room, {this.initial, this.quality, this.lineId})
    : site = room.ref.platform,
      roomKey = room.ref.key,
      resolve = ((quality) => source.streams(room, quality: quality)),
      continuousLive = true;

  /// Platform id (proxy route key for the relay).
  final String site;

  /// Room identity; opening another key clears recovery history (SES-3, REC-7).
  final String roomKey;

  /// Resolves stream sets for signature refresh, quality changes and lease renewals.
  final StreamResolver resolve;

  /// An already resolved set, so opening skips the first resolve.
  final StreamSet? initial;

  /// Quality to request; null for the best or [initial]'s selection.
  final Quality? quality;

  /// Preferred line; the first line otherwise.
  final String? lineId;

  /// A continuous live stream; replays and catch-up disable the live-only
  /// checks (SES-11).
  final bool continuousLive;
}

/// Watchdog and retry limits (spec §5, §6). Defaults follow the spec.
@immutable
final class PlaybackTimings {
  /// Creates the limits.
  const new({
    this.openTimeout = const Duration(seconds: 18),
    this.refreshTimeout = const Duration(seconds: 12),
    this.bufferingStall = const Duration(seconds: 12),
    this.pauseGrace = const Duration(milliseconds: 350),
    this.pauseResumeTimeout = const Duration(seconds: 5),
    this.pauseConfirm = const Duration(seconds: 5),
    this.frameStall = const Duration(seconds: 10),
    this.diagnosticObservation = const Duration(milliseconds: 1200),
    this.diagnosticDedupe = const Duration(seconds: 2),
    this.healthyPlay = const Duration(seconds: 30),
    this.roundWindow = const Duration(minutes: 3),
    this.maxRoundsPerWindow = 2,
    this.backoff = const [Duration(milliseconds: 750), Duration(seconds: 2)],
    this.audioSwitchTimeout = const Duration(seconds: 5),
    this.idleRelease = const Duration(seconds: 45),
    this.prefetchRetry = const Duration(seconds: 10),
    this.minimumLeaseDelay = const Duration(seconds: 1),
  });

  /// Engine open does not return (初始化类).
  final Duration openTimeout;

  /// Signature refresh resolve (source_refresh_timeout).
  final Duration refreshTimeout;

  /// Continuous buffering (buffering_stall_timeout).
  final Duration bufferingStall;

  /// playing=false without buffering before play() is tried.
  final Duration pauseGrace;

  /// Limit for that play().
  final Duration pauseResumeTimeout;

  /// Wait for playing=true after it.
  final Duration pauseConfirm;

  /// Time since the last frame (video_frame_stall_timeout).
  final Duration frameStall;

  /// Watch time for a recoverable diagnostic (EVT-7).
  final Duration diagnosticObservation;

  /// Same diagnostic text within one generation is reported once per this (EVT-6).
  final Duration diagnosticDedupe;

  /// Continuous healthy play that ends a recovery round (REC-2).
  final Duration healthyPlay;

  /// Window for counting recovery rounds (REC-2).
  final Duration roundWindow;

  /// Rounds allowed to start within [roundWindow] (REC-2).
  final int maxRoundsPerWindow;

  /// Backoff rounds (REC-1 step 5).
  final List<Duration> backoff;

  /// Audio-mode switch limit (AUD-4).
  final Duration audioSwitchTimeout;

  /// Engine kept after a soft stop (SES-7).
  final Duration idleRelease;

  /// Prefetch retry after a failure (SRC-6).
  final Duration prefetchRetry;

  /// Shortest delay before a lease action whose time has passed (SRC-6).
  final Duration minimumLeaseDelay;
}
