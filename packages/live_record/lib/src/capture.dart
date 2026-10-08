import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/src/diagnostics.dart';
import 'package:live_record/src/ffmpeg.dart';
import 'package:live_record/src/segments.dart';
import 'package:meta/meta.dart';

/// What happened to a capture (3.x `FFmpegEvent` with its map payload,
/// now typed).
@immutable
sealed class CaptureEvent {
  const new(this.session);

  /// The capture's session number.
  final int session;
}

/// FFmpeg was started.
final class CaptureAcknowledged extends CaptureEvent {
  /// Creates the event.
  const new(super.session);
}

/// The first media arrived.
final class CaptureStarted extends CaptureEvent {
  /// Creates the event.
  const new(super.session);
}

/// Progress of this attempt.
final class CaptureProgress extends CaptureEvent {
  /// Creates the event.
  const new(super.session, {required this.seconds, required this.bytes, required this.speed, required this.fps});

  /// Seconds recorded (wall-clock bounded).
  final int seconds;

  /// Bytes FFmpeg reports (0 for the segment muxer; files are measured).
  final int bytes;

  /// Speed.
  final double speed;

  /// Frames per second.
  final double fps;
}

/// FFmpeg reported skipped HLS segments: the recording has a gap.
final class CaptureCoverageGap extends CaptureEvent {
  /// Creates the event.
  const new(super.session);
}

/// The capture ended.
final class CaptureEnded extends CaptureEvent {
  /// Creates the event.
  const new(
    super.session, {
    required this.complete,
    required this.code,
    required this.manualStop,
    this.kind,
    this.retryable = false,
    this.silent = false,
    this.inputCoverageIncomplete = false,
    this.inputIntegrityError = false,
    this.inputTailDiscarded = false,
    this.diagnostic = '',
  });

  /// A normal end (a user stop for a live capture).
  final bool complete;

  /// FFmpeg's return code (-1 when it never ran).
  final int code;

  /// The user stopped it.
  final bool manualStop;

  /// Why it failed; null when [complete].
  final FfmpegFailureKind? kind;

  /// Whether a new attempt can recover.
  final bool retryable;

  /// An expected end (live EOF, lease boundary): retry without telling the
  /// user.
  final bool silent;

  /// FFmpeg reported skipped segments.
  final bool inputCoverageIncomplete;

  /// FFmpeg reported damaged packets while recording.
  final bool inputIntegrityError;

  /// FFmpeg dropped a packet cut off by the stop or lease end (the input
  /// ends mid-packet there): the recording lacks only that tail.
  final bool inputTailDiscarded;

  /// Sanitized log tail.
  final String diagnostic;

  /// Whether a fresh signed URL is the likely fix (3.x
  /// `refreshSignedStream`).
  bool get refreshesSignedStream =>
      kind == FfmpegFailureKind.leaseRefresh ||
      kind == FfmpegFailureKind.unexpectedEof ||
      kind == FfmpegFailureKind.httpAccess;
}

final _missingHlsSegment = RegExp(
  r'(?:^|\])\s*(?:skipping [1-9]\d* segments ahead, expired from playlists|segment \d+ of playlist \d+ failed too many times, skipping)(?:\s|$)',
  multiLine: true,
  caseSensitive: false,
);

/// One FFmpeg capture attempt of a live input (3.x `FFmpegService` with
/// `FFmpegRecordSession`).
///
/// A live capture has no successful end of its own: code 0 or EOF means the
/// CDN ended the response, and the attempt fails silently so the recorder
/// fetches a fresh URL; only a user stop completes it. Stopping first ends
/// the input (the relay closes it, FFmpeg drains and writes complete
/// segments) and cancels FFmpeg only when it does not finish in time.
final class RecordCapture {
  new _(this.session, this.input, this._reservation, this._onEvent);

  /// Starts FFmpeg with [arguments] on [input]. [reservation] is released
  /// when the capture ends; [onEvent] receives every event, the last one a
  /// [CaptureEnded].
  factory start({
    required FfmpegRunner runner,
    required MediaInput input,
    required List<String> arguments,
    required void Function(CaptureEvent event) onEvent,
    SegmentReservation? reservation,
  }) {
    final capture = RecordCapture._(++_sessions, input, reservation, onEvent);
    unawaited(capture._run(runner, arguments));
    return capture;
  }

  /// Drain budget after the input ends.
  static const drainTimeout = Duration(seconds: 5);

  static var _sessions = 0;

  /// Session number.
  final int session;

  /// The input FFmpeg reads.
  final MediaInput input;

  final SegmentReservation? _reservation;
  final void Function(CaptureEvent event) _onEvent;
  final _done = Completer<void>();
  final _lines = <String>[];
  var _characters = 0;
  final DateTime _startedAt = clock.now();
  FfmpegExecution? _execution;
  Future<void>? _stopping;
  var _manualStop = false;
  var _leaseRefresh = false;
  var _mediaStarted = false;
  var _packetError = false;
  var _tailDiscarded = false;
  // FFmpeg describes the input in pieces (one log call per part of a
  // "Stream #0:1[0x101]: Audio: aac" line); they are put together here
  // until the output is described.
  final _streamLine = StringBuffer();
  var _inputDescribed = false;
  final _audioStreams = <int>{};
  var _coverageGap = false;
  var _seconds = 0;

  /// Completes when the capture ended and its input is closed.
  Future<void> get done => _done.future;

  /// Whether the capture ended.
  bool get isDone => _done.isCompleted;

  /// Seconds recorded by FFmpeg's clock (bounded by wall time).
  int get recordedSeconds => _seconds;

  /// Whether media arrived.
  bool get mediaStarted => _mediaStarted;

  /// Stops at the user's request.
  Future<void> stop() {
    _manualStop = true;
    return _stop();
  }

  /// Ends the attempt at a lease boundary: the recorder resolves a fresh
  /// URL and starts the next attempt at once (silent, retryable).
  Future<void> refreshLease() {
    if (_manualStop || _leaseRefresh) return _stopping ?? Future.value();
    _leaseRefresh = true;
    return _stop();
  }

  Future<void> _stop() => _stopping ??= () async {
    // Only a relayed input can end cleanly; a direct one (RTMP, files) has
    // nothing to drain, so FFmpeg is cancelled at once.
    if (input.private) {
      unawaited(input.close());
      try {
        await _done.future.timeout(drainTimeout);
        return;
      } on TimeoutException {
        // Not drained in time.
      }
    }
    _execution?.cancel();
    await _done.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  }();

  bool get _stopRequested => _stopping != null;

  void _emit(CaptureEvent event) {
    try {
      _onEvent(event);
    } on Object {
      // A failing listener must not break the capture.
    }
  }

  void _log(String message) {
    _noteStreams(message);
    final text = sanitizeFfmpegLog(message).trim();
    if (text.isEmpty) return;
    // HLS live (YY's sslproxy playlists on the K90, H01.6) cuts an audio
    // packet at every segment boundary; FFmpeg drops it (`discardcorrupt`)
    // and the recording loses a few milliseconds of sound, nothing a player
    // notices: not damage.
    final dropped = FfmpegMediaIntegrity.corruptPacketStream(text);
    final audioDrop = dropped != null && _audioStreams.contains(dropped);
    if (!audioDrop && FfmpegMediaIntegrity.hasPacketError(text)) {
      // Ending the input at a stop or lease boundary can cut its last packet,
      // which FFmpeg reports as corrupt and drops (`discardcorrupt`): that
      // is the tail, not damage of what was recorded (3.x's relay finished
      // at a tag boundary instead).
      if (_stopRequested) {
        _tailDiscarded = true;
      } else {
        _packetError = true;
      }
    }
    if (!_stopRequested && !_coverageGap && _missingHlsSegment.hasMatch(text)) {
      _coverageGap = true;
      _emit(CaptureCoverageGap(session));
    }
    _lines.add(text);
    _characters += text.length;
    while (_lines.length > 120 || _characters > 12000) {
      _characters -= _lines.removeAt(0).length;
    }
  }

  void _statistics(FfmpegStatistics statistics) {
    final wall = clock.now().difference(_startedAt).inSeconds;
    final seconds = normalizeLiveRecordedSeconds(rawMilliseconds: statistics.time, wallSeconds: wall);
    _seconds = math.max(_seconds, seconds);
    if (!_mediaStarted && (statistics.time > 0 || statistics.size > 0 || statistics.videoFrame > 0)) {
      _mediaStarted = true;
      _emit(CaptureStarted(session));
    }
    _emit(
      CaptureProgress(
        session,
        seconds: seconds,
        bytes: statistics.size,
        speed: statistics.speed,
        fps: statistics.videoFps,
      ),
    );
  }

  Future<void> _run(FfmpegRunner runner, List<String> arguments) async {
    StreamSubscription<String>? logs;
    StreamSubscription<FfmpegStatistics>? statistics;
    try {
      final execution = await runner.start(arguments);
      _execution = execution;
      if (_stopRequested) execution.cancel();
      logs = execution.logs.listen(_log);
      statistics = execution.statistics.listen(_statistics);
      _emit(CaptureAcknowledged(session));
      final code = await execution.exitCode;
      await Future<void>.delayed(Duration.zero);
      _emit(_ended(code));
    } on Object catch (error) {
      final text = sanitizeFfmpegLog('$error').toLowerCase();
      final failure = classifyFfmpegFailure(text);
      _emit(
        CaptureEnded(
          session,
          complete: false,
          code: -1,
          manualStop: _manualStop,
          kind: failure.kind,
          retryable: failure.retryable,
          diagnostic: text,
        ),
      );
    } finally {
      await logs?.cancel();
      await statistics?.cancel();
      await input.close();
      _reservation?.release();
      _done.complete();
    }
  }

  void _noteStreams(String message) {
    if (_inputDescribed) return;
    _streamLine.write(message.toLowerCase());
    final text = _streamLine.toString();
    if (text.contains('output #0')) {
      _inputDescribed = true;
      _streamLine.clear();
      return;
    }
    final match = _audioStream.firstMatch(text);
    if (match != null) _audioStreams.add(int.parse(match.group(1)!));
    final end = text.lastIndexOf('\n');
    if (match != null || end >= 0 || text.length > 400) {
      _streamLine.clear();
      if (match == null && end >= 0) _streamLine.write(text.substring(end + 1));
    }
  }

  static final _audioStream = RegExp(r'stream #0:(\d+)[^:\n]*: audio');

  CaptureEnded _ended(int code) {
    final tail = _lines.join('\n');
    final diagnostic = tail.toLowerCase();
    final integrity = _packetError;
    if (_manualStop) {
      return CaptureEnded(
        session,
        complete: true,
        code: code,
        manualStop: true,
        inputCoverageIncomplete: _coverageGap,
        inputIntegrityError: integrity,
        inputTailDiscarded: _tailDiscarded,
      );
    }
    final eof = code == 0 || code == ffmpegEndOfFile;
    if (_leaseRefresh || eof) {
      return CaptureEnded(
        session,
        complete: false,
        code: code,
        manualStop: false,
        kind: _leaseRefresh ? FfmpegFailureKind.leaseRefresh : FfmpegFailureKind.unexpectedEof,
        retryable: true,
        silent: true,
        inputCoverageIncomplete: _coverageGap,
        inputIntegrityError: integrity,
        inputTailDiscarded: _tailDiscarded,
        diagnostic: diagnostic,
      );
    }
    final failure = classifyFfmpegFailure(diagnostic);
    return CaptureEnded(
      session,
      complete: false,
      code: code,
      manualStop: false,
      kind: failure.kind,
      retryable: failure.retryable,
      inputCoverageIncomplete: _coverageGap,
      inputIntegrityError: integrity,
      inputTailDiscarded: _tailDiscarded,
      diagnostic: diagnostic.length > 1600 ? diagnostic.substring(diagnostic.length - 1600) : diagnostic,
    );
  }
}
