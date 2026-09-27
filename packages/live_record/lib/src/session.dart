import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/src/chat.dart';
import 'package:live_record/src/errors.dart';
import 'package:live_record/src/files.dart';
import 'package:live_record/src/flv/flv_writer.dart';
import 'package:live_record/src/gaps.dart';
import 'package:live_record/src/hls/client.dart';
import 'package:live_record/src/hls/feed.dart';
import 'package:live_record/src/hls/hls_writer.dart';
import 'package:live_record/src/naming.dart';
import 'package:live_record/src/quality.dart';
import 'package:live_record/src/retry.dart';
import 'package:live_record/src/rooms.dart';
import 'package:live_record/src/segment_files.dart';
import 'package:live_record/src/settings.dart';
import 'package:live_record/src/writer.dart';
import 'package:meta/meta.dart';

/// What a running session is doing (spec §3; the task adds queued, finalizing
/// and the terminal states).
enum SessionPhase {
  /// Strict room check and first resolve.
  resolving,

  /// Media is being written.
  recording,

  /// The connection was lost; waiting to reconnect or re-resolving.
  reconnecting,

  /// Closing files.
  finalizing,
}

/// How a session ended.
enum SessionEnd {
  /// The strict check says the room is offline.
  offline,

  /// The user stopped it.
  stopped,

  /// A fatal error.
  failed,

  /// Regular retries reached `maxRetries`.
  exhausted,

  /// The upstream ended and automatic reconnection is off (§11.6).
  ended,
}

/// Result of [RecordSession.run].
@immutable
final class SessionResult {
  /// Creates a result.
  const new({required this.end, required this.segments, required this.gaps, this.failure, this.cursor});

  /// How it ended.
  final SessionEnd end;

  /// Why, for [SessionEnd.failed] and [SessionEnd.exhausted] (the last error).
  final RecordFailure? failure;

  /// Closed segments with media.
  final List<RecordedSegment> segments;

  /// Gaps recorded.
  final List<RecordGap> gaps;

  /// Last quality and line position.
  final RecordCursor? cursor;
}

/// Live metrics of a session (spec §19).
@immutable
final class SessionProgress {
  /// Creates a snapshot.
  const new({
    required this.bytes,
    required this.media,
    required this.segments,
    required this.connections,
    required this.splices,
    required this.gaps,
    required this.bitsPerSecond,
    this.lastGapMs,
    this.line,
    this.quality,
  });

  /// Bytes written to segment files.
  final int bytes;

  /// Media duration written (summed over segments, capped by wall time).
  final Duration media;

  /// Segment count.
  final int segments;

  /// Upstream connections opened by the outer loop.
  final int connections;

  /// Renewals spliced in.
  final int splices;

  /// Gaps recorded.
  final int gaps;

  /// Missing time of the last gap.
  final int? lastGapMs;

  /// Bit rate over the last 10 s of wall time.
  final int bitsPerSecond;

  /// Line id in use.
  final String? line;

  /// Quality in use (the confirmed one when known).
  final Quality? quality;
}

final class _Stopped implements Exception {
  const new();
}

final class _Paced implements FlvPacketSource {
  new(this._inner, this._writer);

  final FlvPacketSource _inner;
  final SessionWriter _writer;

  @override
  Future<Uint8List?> next() async {
    await _writer.ready;
    return await _inner.next();
  }

  @override
  Future<void> cancel() => _inner.cancel();
}

/// Delivers an HLS feed into the writer and tells the session about media.
final class _HlsTap implements HlsSink {
  new(this._writer, this._onMedia);

  final HlsSessionWriter _writer;
  final void Function() _onMedia;

  @override
  Future<void> get ready => _writer.ready;

  @override
  void addMedia(HlsMedia media) {
    _writer.addMedia(media);
    _onMedia();
  }

  @override
  void addMissing(HlsMissing missing) => _writer.addMissing(missing);
}

/// One recording session (spec §5.4): from start until the user stops it,
/// the strict check confirms the room is offline, retries run out or a fatal
/// error happens. It writes through one writer at a time: reconnections
/// continue the same files; a switch between an FLV and an HLS line closes
/// the file and continues the numbering.
///
/// Every FLV connection runs through `FlvSplicer`: a lease that cuts the
/// connection (Douyu `expire`) is renewed and spliced in without a gap; for
/// other lines the splicer renews at once when the old connection ends, using
/// a prefetched line when one is valid (§5.2). An HLS connection runs an
/// [HlsFeed] (§7): it follows the playlist by sequence number, so a
/// reconnection continues without duplicates or gaps while the playlist
/// still holds the next segment. When a connection gives up the outer loop
/// reconnects after a strict room check. Lines are tried FLV first, then HLS.
final class RecordSession {
  /// Creates a session for [room] writing into [layout].
  new({
    required this.room,
    required this._rooms,
    required this.layout,
    required this._files,
    required RecordSettings settings,
    required this._opener,
    this._hls,
    RecordQuality? quality,
    RecordCursor? cursor,
    bool? autoReconnect,
    this.spliceTimings = const SpliceTimings(),
    this.writerLimits = const FlvWriterLimits(),
    this.hlsTimings = const HlsTimings(),
    this.requestTimeout = const Duration(seconds: 20),
    this.stopPictureWait = const Duration(seconds: 3),
    this.healthyMedia = const Duration(seconds: 10),
    this._onPhase,
    this._onDetail,
    this._onRetry,
    this._onSplice,
  }) : _settings = settings,
       _quality = quality ?? settings.defaultQuality,
       _startCursor = cursor,
       _autoReconnect = autoReconnect ?? settings.autoReconnect,
       _policy = RetryPolicy(settings);

  /// Room being recorded.
  final RoomRef room;

  /// Output location.
  final SessionLayout layout;

  /// Splice limits.
  final SpliceTimings spliceTimings;

  /// Writer limits.
  final FlvWriterLimits writerLimits;

  /// HLS feed limits.
  final HlsTimings hlsTimings;

  /// Limit of a strict room check or resolve.
  final Duration requestTimeout;

  /// How long a stop waits for a picture after held SEI/SPS/PPS tags (§6.7).
  final Duration stopPictureWait;

  /// Continuous media after which retry counters start over (§3).
  final Duration healthyMedia;

  final RecordRooms _rooms;
  final RecordFiles _files;
  final RecordSettings _settings;
  final FlvSourceOpener _opener;
  final HlsClient? _hls;
  final RecordQuality _quality;
  final RecordCursor? _startCursor;
  final bool _autoReconnect;
  final void Function(SessionPhase phase)? _onPhase;
  final void Function(RoomDetail detail)? _onDetail;
  final void Function(RecordFailure failure, Duration delay)? _onRetry;
  final void Function(SpliceEvent event)? _onSplice;
  final RetryPolicy _policy;

  late final GapLedger _gaps = GapLedger(files: _files, path: layout.gaps, room: room.key, session: layout.prefix);
  final _retired = <SessionWriter>[];
  SessionWriter? _writer;
  final _hlsState = HlsFeedState();
  HlsFeed? _feed;
  ChatXmlWriter? _chat;

  LineCursor? _cursor;
  StreamLine? _line;
  Quality? _confirmed;
  FlvSplicer? _splicer;
  var _detached = false;
  var _stopping = false;
  var _started = false;
  Completer<void>? _sleep;
  Timer? _sleepTimer;
  SessionPhase? _phase;
  var _connections = 0;
  var _splices = 0;
  DateTime? _spliceLostAt;

  Timer? _prefetchTimer;
  ({Uri forUrl, StreamLine line})? _prefetched;
  var _prefetching = false;

  final _samples = ListQueue<({DateTime at, int bytes})>();

  /// The phase last reported.
  SessionPhase? get phase => _phase;

  /// Current metrics.
  SessionProgress get progress {
    final now = clock.now();
    final bytes = _sum((writer) => writer.bytesWritten);
    _samples.add((at: now, bytes: bytes));
    while (_samples.length > 2 && now.difference(_samples.first.at) > const Duration(seconds: 10)) {
      _samples.removeFirst();
    }
    final first = _samples.first;
    final span = now.difference(first.at).inMilliseconds;
    final rate = span <= 0 ? 0 : ((bytes - first.bytes) * 8000 / span).round();
    final wall = now.difference(layout.startedAt);
    final media = _mediaDuration;
    final gaps = _gaps.gaps;
    return SessionProgress(
      bytes: bytes,
      media: media > wall ? wall : media,
      segments: segments.length,
      connections: _connections,
      splices: _splices,
      gaps: gaps.length,
      lastGapMs: gaps.isEmpty ? null : gaps.last.missingMs,
      bitsPerSecond: rate,
      line: _line?.lineId,
      quality: _confirmed,
    );
  }

  /// Segments so far.
  List<RecordedSegment> get segments => [
    for (final writer in [..._retired, ?_writer]) ...writer.segments,
  ];

  int _sum(int Function(SessionWriter writer) value) =>
      [..._retired, ?_writer].fold(0, (sum, writer) => sum + value(writer));

  /// Media units written by every writer of the session.
  int get _mediaTags => _sum((writer) => writer.mediaTags);

  Duration get _mediaDuration => Duration(milliseconds: _sum((writer) => writer.mediaDuration.inMilliseconds));

  /// The writer for [format]: the current one, or a new one after closing it
  /// (numbering continues).
  Future<SessionWriter> _use(StreamFormat format) async {
    final current = _writer;
    final wanted = format == StreamFormat.hls ? HlsSessionWriter : FlvSessionWriter;
    if (current != null && current.runtimeType == wanted) return current;
    if (current != null) {
      await current.close();
      _writer = null;
      _retired.add(current);
    }
    final first = segments.length + 1;
    final writer = format == StreamFormat.hls
        ? HlsSessionWriter(
            files: _files,
            layout: layout,
            gaps: _gaps,
            splitDuration: _settings.splitDuration,
            splitBytes: _settings.splitBytes,
            limits: writerLimits,
            firstIndex: first,
            onSegment: _onSegment,
          )
        : FlvSessionWriter(
            files: _files,
            layout: layout,
            gaps: _gaps,
            splitDuration: _settings.splitDuration,
            splitBytes: _settings.splitBytes,
            limits: writerLimits,
            firstIndex: first,
            onSegment: _onSegment,
          );
    _writer = writer;
    unawaited(writer.failure.then((_) => _interrupt()));
    return writer;
  }

  /// Records chat into the segment XML when chat recording is on (spec §17).
  void addChat(RecordChatMessage message) => _chat?.add(message);

  /// Changed retry settings (`maxRetries`, `retryDelay`, `backoff`,
  /// `maxCheckInterval`) for the running session.
  set retrySettings(RecordSettings settings) => _policy.settings = settings;

  /// Retry settings in force.
  RecordSettings get retrySettings => _policy.settings;

  /// Runs the session to its end, then closes its files.
  Future<SessionResult> run() async {
    if (_started) throw StateError('A session runs once');
    _started = true;
    if (_settings.danmaku) _chat = ChatXmlWriter(_files, (wall) => _writer?.fileTimeAt(wall));
    await _gaps.write();
    SessionEnd end;
    RecordFailure? failure;
    try {
      (end, failure) = await _loop();
    } on Object catch (error) {
      (end, failure) = (SessionEnd.failed, classifyError(error, RecordStage.status));
    }
    _setPhase(SessionPhase.finalizing);
    _prefetchTimer?.cancel();
    await _writer?.close();
    final segments = this.segments;
    await _chat?.close();
    await _gaps.write();
    final writerFailure = [..._retired, ?_writer].map((writer) => writer.failed).nonNulls.firstOrNull;
    if (writerFailure != null && end != SessionEnd.failed) {
      end = SessionEnd.failed;
      failure = writerFailure;
    }
    return SessionResult(
      end: end,
      failure: failure,
      segments: [
        for (final segment in segments)
          if (segment.closed) segment,
      ],
      gaps: _gaps.gaps,
      cursor: _cursor?.position ?? _startCursor,
    );
  }

  /// Stops the session as the user asked (spec §6.7, §7.8): waits up to 3 s
  /// for a picture after held prefix-only FLV tags, or lets HLS downloads in
  /// flight finish (one target duration, at most 10 s); then stops feeding
  /// the writer and drops the upstream. [run] completes after the files are closed.
  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    await _writer?.waitForPicture(stopPictureWait);
    await _feed?.stop();
    _interrupt();
  }

  void _interrupt() {
    _stopping = true;
    _detached = true;
    if (!_stopSignal.isCompleted) _stopSignal.complete();
    _prefetchTimer?.cancel();
    _sleepTimer?.cancel();
    final sleep = _sleep;
    _sleep = null;
    if (sleep != null && !sleep.isCompleted) sleep.complete();
    unawaited(_splicer?.cancel());
    _feed?.cancel();
  }

  final _stopSignal = Completer<void>();

  /// [future], or a [_Stopped] error as soon as the session is interrupted,
  /// so a stop never waits for a slow request or connect.
  Future<T> _orStop<T>(Future<T> future) {
    if (_stopSignal.isCompleted) {
      future.ignore();
      return Future.error(const _Stopped());
    }
    return Future.any([future, _stopSignal.future.then<T>((_) => throw const _Stopped())]);
  }

  void _setPhase(SessionPhase phase) {
    if (_phase == phase) return;
    _phase = phase;
    _onPhase?.call(phase);
  }

  void _onSegment(SegmentEvent event) {
    final chat = _chat;
    if (chat == null) return;
    switch (event) {
      case SegmentOpened(:final segment):
        unawaited(chat.openFor(segment.plannedPath));
      case SegmentClosed():
        break;
    }
  }

  Future<void> _wait(Duration delay) async {
    if (_stopping || delay <= Duration.zero) return;
    final sleep = _sleep = Completer<void>();
    _sleepTimer = Timer(delay, () {
      if (!sleep.isCompleted) sleep.complete();
    });
    await sleep.future;
    _sleepTimer?.cancel();
  }

  /// Regular backoff; returns false when retries are exhausted.
  Future<bool> _backoff(RecordFailure failure) async {
    final delay = _policy.regular();
    if (delay == null) return false;
    _onRetry?.call(failure, delay);
    await _wait(delay);
    return true;
  }

  Future<(SessionEnd, RecordFailure?)> _loop() async {
    StreamLine? reuse;
    DateTime? lostAt;
    var lostReason = GapReason.eof;
    while (!_stopping) {
      _setPhase(_mediaTags == 0 && _connections == 0 ? SessionPhase.resolving : SessionPhase.reconnecting);
      StreamLine target;
      if (reuse != null) {
        target = reuse;
        reuse = null;
      } else {
        final RoomDetail detail;
        var stage = RecordStage.room;
        try {
          detail = await _orStop(_rooms.detail(room).timeout(requestTimeout));
          if (_stopping) break;
          // A replay is not recorded (§4.1): it ends the session like going offline.
          if (detail.state != LiveState.live) return (SessionEnd.offline, null);
          _detail = detail;
          _onDetail?.call(detail);
          stage = RecordStage.stream;
          target = await _orStop(_resolve(detail));
        } on Object catch (error) {
          if (_stopping) break;
          final failure = classifyError(error, stage);
          if (failure.kind == RecordErrorKind.roomOffline) return (SessionEnd.offline, null);
          if (failure.kind.fatal) return (SessionEnd.failed, failure);
          if (!await _backoff(failure)) return (SessionEnd.exhausted, failure);
          continue;
        }
      }
      if (_stopping) break;

      final writer = await _use(target.format);
      if (_stopping) break;
      writer.beginConnection(lostAt: lostAt, reason: lostReason);
      _mediaAtConnect = _mediaTags;
      final durationBefore = _mediaDuration;
      _connections++;
      final error = target.format == StreamFormat.hls
          ? await _connectHls(target, writer as HlsSessionWriter)
          : await _connect(target, writer as FlvSessionWriter);
      if (_stopping) break;
      final gotMedia = _mediaTags > _mediaAtConnect;
      lostAt = clock.now();
      if (gotMedia) {
        _cursor?.succeed();
        _policy.connected();
        _cycleFailures = 0;
        _cycleUnsupported = 0;
        if (_mediaDuration - durationBefore >= healthyMedia) _policy.healthy();
      }
      final failure = error == null || gotMedia
          ? RecordFailure(RecordErrorKind.upstreamEof, RecordStage.network, error?.toString())
          : classifyError(error, RecordStage.network);
      if (failure.kind == RecordErrorKind.unsupportedProtocol) {
        // This line cannot be recorded (SAMPLE-AES, separate audio…): the
        // next line at once; only when every line of every quality is like
        // that does the session fail (§21).
        _cycleFailures++;
        _cycleUnsupported++;
        if (_advanceCursor()) continue;
        final allUnsupported = _cycleUnsupported == _cycleFailures;
        _cycleFailures = 0;
        _cycleUnsupported = 0;
        if (allUnsupported) return (SessionEnd.failed, failure);
        final all = RecordFailure(RecordErrorKind.allLinesFailed, RecordStage.stream, failure.message);
        if (!await _backoff(all)) return (SessionEnd.exhausted, all);
        continue;
      }
      if (failure.kind.fatal) return (SessionEnd.failed, failure);
      if (!_autoReconnect) return (SessionEnd.ended, null);
      switch (failure.kind.retry) {
        case RetryClass.fast when gotMedia:
          // The stream ended after media: reconnect fast, after a strict check (§11.4).
          lostReason = GapReason.eof;
          final delay = _policy.fast();
          _onRetry?.call(failure, delay);
          await _wait(delay);
        case RetryClass.reResolve:
          // 4xx: never retry the old signature (§11.7). First: renew the same
          // line at once; second: the next line; from the third: back off.
          lostReason = GapReason.http4xx;
          final count = _policy.http4xx();
          if (count >= 2 && !_advanceCursor() || count >= RetryPolicy.max4xx) {
            if (!await _backoff(failure)) return (SessionEnd.exhausted, failure);
          }
        case RetryClass.sameUrl:
          // 5xx: the same URL after 1, 2 and 4 s, then regular backoff (§5.4).
          lostReason = GapReason.http5xx;
          final delay = _policy.sameUrl();
          if (delay != null) {
            reuse = target;
            _onRetry?.call(failure, delay);
            await _wait(delay);
          } else if (!await _backoff(failure)) {
            return (SessionEnd.exhausted, failure);
          }
        case RetryClass.end:
          return (SessionEnd.offline, null);
        case RetryClass.fast || RetryClass.regular || RetryClass.none:
          // The line failed before delivering media: the next line at once;
          // once every line failed, regular backoff (§4.3).
          lostReason = GapReason.network;
          _cycleFailures++;
          if (!_advanceCursor()) {
            _cycleFailures = 0;
            _cycleUnsupported = 0;
            final all = RecordFailure(RecordErrorKind.allLinesFailed, RecordStage.stream, failure.message);
            if (!await _backoff(all)) return (SessionEnd.exhausted, all);
          }
      }
    }
    return (SessionEnd.stopped, null);
  }

  RoomDetail? _detail;
  var _mediaAtConnect = 0;
  List<StreamLine> _lastLines = const [];

  /// Line failures since the cursor last wrapped, and how many of them were
  /// unsupported content.
  var _cycleFailures = 0;
  var _cycleUnsupported = 0;

  /// Moves the cursor past the failed line; false once every line failed.
  bool _advanceCursor() {
    final cursor = _cursor;
    if (cursor == null) return false;
    return cursor.fail(linesInQuality: _recordable(_lastLines).length);
  }

  /// Lines the recorder can write, FLV first (spliced without gaps, §5.5),
  /// then HLS (§7) when the session has an HLS client.
  List<StreamLine> _recordable(List<StreamLine> lines) {
    bool http(StreamLine line) => line.url.isScheme('http') || line.url.isScheme('https');
    return [
      for (final line in lines)
        if (line.format == StreamFormat.flv && http(line)) line,
      if (_hls != null)
        for (final line in lines)
          if (line.format == StreamFormat.hls && http(line)) line,
    ];
  }

  /// Resolves the line at the cursor. Only the cursor's quality is requested
  /// (§4.3); a quality without a recordable line is skipped.
  Future<StreamLine> _resolve(RoomDetail detail) async {
    var cursor = _cursor;
    if (cursor == null) {
      final first = await _rooms.streams(detail).timeout(requestTimeout);
      final ordered = orderQualities(first.qualities.isEmpty ? [first.selected] : first.qualities, _quality);
      cursor = _cursor = LineCursor(ordered, start: _startCursor);
      if (cursor.quality?.id == first.selected.id) {
        final line = _pick(first, cursor);
        if (line != null) return line;
      }
    }
    var skipped = 0;
    while (true) {
      final quality = cursor.quality;
      if (quality == null) throw RecordException(RecordErrorKind.noQuality, RecordStage.quality, 'no quality offered');
      final set = await _rooms.streams(detail, quality: quality).timeout(requestTimeout);
      final line = _pick(set, cursor);
      if (line != null) return line;
      skipped++;
      if (!cursor.skipQuality() || skipped > cursor.qualities.length) {
        throw RecordException(
          RecordErrorKind.unsupportedProtocol,
          RecordStage.stream,
          'no line in a protocol the recorder writes (HTTP-FLV, HLS)',
        );
      }
    }
  }

  StreamLine? _pick(StreamSet set, LineCursor cursor) {
    final lines = _recordable(set.lines);
    _lastLines = set.lines;
    if (lines.isEmpty) return null;
    final index = cursor.lineIndex < lines.length ? cursor.lineIndex : 0;
    final line = lines[index];
    _confirmed = line.confirmed ?? set.selected;
    return line;
  }

  /// Runs one spliced connection; returns the error that ended it, or null
  /// when the upstream ended normally.
  Future<Object?> _connect(StreamLine line, FlvSessionWriter writer) async {
    _line = line;
    final splicer = FlvSplicer(
      line: line,
      open: (line) async => _Paced(await _opener(line), writer),
      renew: _renew,
      emit: (packet) {
        if (_detached) return;
        writer.add(packet);
        if (_phase != SessionPhase.recording && _mediaTags > _mediaAtConnect) {
          _setPhase(SessionPhase.recording);
        }
      },
      onEvent: _onSpliceEvent,
      timings: spliceTimings,
    );
    _splicer = splicer;
    _schedulePrefetch(line);
    try {
      await _orStop(splicer.run());
      return null;
    } on _Stopped {
      return null;
    } on Object catch (error) {
      return error;
    } finally {
      _prefetchTimer?.cancel();
      _prefetched = null;
      _splicer = null;
      await splicer.cancel();
    }
  }

  /// Runs one HLS connection (§7); returns the error that ended it, or null
  /// when the playlist ended (`EXT-X-ENDLIST`) or the session stopped.
  Future<Object?> _connectHls(StreamLine line, HlsSessionWriter writer) async {
    _line = line;
    final feed = HlsFeed(
      line: line,
      client: _hls!,
      sink: _HlsTap(writer, () {
        if (!_detached && _phase != SessionPhase.recording) _setPhase(SessionPhase.recording);
      }),
      state: _hlsState,
      renew: _renew,
      onLine: (next) => _line = next,
      readTimeout: _settings.readTimeout,
      timings: hlsTimings,
    );
    _feed = feed;
    try {
      await _orStop(feed.run());
      return null;
    } on _Stopped {
      return null;
    } on Object catch (error) {
      return error;
    } finally {
      _feed = null;
      feed.cancel();
    }
  }

  void _onSpliceEvent(SpliceEvent event) {
    switch (event) {
      case SpliceRenewing(oldEnded: true):
        _spliceLostAt = clock.now();
      case SpliceSwitched():
        _splices++;
        _line = event.line;
        final writer = _writer;
        if (event.oldEnded && writer is FlvSessionWriter) {
          writer.noteSplice(switchAt: event.switchAt, lostAt: _spliceLostAt ?? clock.now(), shifted: event.shifted);
        }
        _spliceLostAt = null;
        _schedulePrefetch(event.line);
      default:
        break;
    }
    _onSplice?.call(event);
  }

  /// A fresh URL for the same quality and line (splice renewals, §5.1), or the
  /// prefetched one while it is valid (§5.2).
  Future<StreamLine> _renew(StreamLine current) async {
    final prefetched = _prefetched;
    if (prefetched != null && prefetched.forUrl == current.url) {
      final expiresAt = prefetched.line.lease?.expiresAt;
      if (expiresAt == null || expiresAt.isAfter(clock.now())) {
        _prefetched = null;
        return prefetched.line;
      }
    }
    final detail = _detail;
    if (detail == null) throw StateError('No room detail');
    final set = await _rooms.streams(detail, quality: current.requested).timeout(requestTimeout);
    // The same line, or another of the same format: an HLS feed cannot read FLV.
    final lines = [
      for (final line in _recordable(set.lines))
        if (line.format == current.format) line,
    ];
    if (lines.isEmpty) throw RecordException(RecordErrorKind.noQuality, RecordStage.stream, 'no line on renewal');
    return lines.firstWhere((line) => sameLine(line, current), orElse: () => lines.first);
  }

  /// Prefetches the next URL of a line whose lease does not cut the
  /// connection, 5 s before `refreshAt` and then at each new `refreshAt`, at
  /// most every 30 s (§5.2). Failures leave the connection alone.
  void _schedulePrefetch(StreamLine line) {
    _prefetchTimer?.cancel();
    final lease = line.lease;
    // HLS feeds renew their playlist address themselves (§7.6).
    if (lease == null || lease.cutsConnection || line.format != StreamFormat.flv) return;
    var delay = lease.refreshAt.subtract(const Duration(seconds: 5)).difference(clock.now());
    if (delay < Duration.zero) delay = Duration.zero;
    if (_prefetched != null && delay < const Duration(seconds: 30)) delay = const Duration(seconds: 30);
    _prefetchTimer = Timer(delay, () => unawaited(_prefetch(line)));
  }

  Future<void> _prefetch(StreamLine line) async {
    if (_prefetching || _stopping) return;
    _prefetching = true;
    try {
      final detail = _detail;
      if (detail == null) return;
      final set = await _rooms.streams(detail, quality: line.requested).timeout(requestTimeout);
      final lines = _recordable(set.lines);
      final next = lines.where((candidate) => sameLine(candidate, line)).firstOrNull;
      if (next == null || _stopping) return;
      _prefetched = (forUrl: (_line ?? line).url, line: next);
      final lease = next.lease;
      if (lease != null && !lease.cutsConnection) {
        var delay = lease.refreshAt.subtract(const Duration(seconds: 5)).difference(clock.now());
        if (delay < const Duration(seconds: 30)) delay = const Duration(seconds: 30);
        _prefetchTimer = Timer(delay, () => unawaited(_prefetch(line)));
      }
    } on Object {
      if (!_stopping) _prefetchTimer = Timer(const Duration(seconds: 30), () => unawaited(_prefetch(line)));
    } finally {
      _prefetching = false;
    }
  }
}
