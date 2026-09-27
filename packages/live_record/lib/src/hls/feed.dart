import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/src/errors.dart';
import 'package:live_record/src/gaps.dart';
import 'package:live_record/src/hls/aes.dart';
import 'package:live_record/src/hls/client.dart';
import 'package:live_record/src/hls/playlist.dart';
import 'package:meta/meta.dart';

/// A downloaded, decrypted media segment for the writer.
@immutable
final class HlsMedia {
  /// Creates a segment.
  const new({
    required this.sequence,
    required this.durationMs,
    required this.data,
    this.init,
    this.discontinuity = false,
  });

  /// Media sequence number.
  final int sequence;

  /// `EXTINF` in milliseconds.
  final int durationMs;

  /// The segment's bytes (MPEG-TS packets, or an fMP4 fragment), decrypted.
  final Uint8List data;

  /// The fMP4 initialisation section in effect (decrypted); the same
  /// instance while it does not change. Null for MPEG-TS.
  final Uint8List? init;

  /// Preceded by `EXT-X-DISCONTINUITY`.
  final bool discontinuity;
}

/// Media the feed could not record (spec §7.4, §7.8), at the current position.
@immutable
final class HlsMissing {
  /// Creates a record.
  const new({required this.reason, required this.missingMs, this.fromSeq, this.toSeq, this.wallStart});

  /// Why.
  final GapReason reason;

  /// Estimated missing media.
  final int missingMs;

  /// First missing sequence number.
  final int? fromSeq;

  /// Last missing sequence number.
  final int? toSeq;

  /// When media stopped arriving, when known.
  final DateTime? wallStart;
}

/// Where a feed delivers: the session's HLS writer.
abstract interface class HlsSink {
  /// Completes when the writer can take more (backpressure, §6.8).
  Future<void> get ready;

  /// Writes [media]. Throws `RecordException(unsupportedProtocol)` for
  /// content that cannot be recorded (packed audio, for example).
  void addMedia(HlsMedia media);

  /// Records missing media at the current position.
  void addMissing(HlsMissing missing);
}

/// What one feed remembers across the connections of a session: the last
/// sequence number it consumed (written or given up), so a reconnection
/// continues without duplicates and a missed stretch becomes a gap (§7.4).
final class HlsFeedState {
  /// Last sequence number consumed, or null before the first.
  int? lastSequence;

  /// When [lastSequence] was consumed.
  DateTime? lastConsumedAt;

  /// Whether any media was written.
  bool wroteMedia = false;
}

/// Limits of the HLS feed; the defaults follow the spec.
@immutable
final class HlsTimings {
  /// Creates the limits.
  const new({
    this.segmentRetries = 2,
    this.retryDelay = const Duration(seconds: 1),
    this.playlistFailures = 3,
    this.segmentFailures = 3,
    this.liveStart = 3,
    this.concurrency = 2,
    this.stopWait = const Duration(seconds: 10),
    this.renewRetry = const Duration(seconds: 30),
    this.playlistBytes = 4 << 20,
    this.segmentBytes = 64 << 20,
    this.maxDiscontinuityStep = 512,
  });

  /// Retries of a failing segment before it becomes a gap (§7.4).
  final int segmentRetries;

  /// Wait before a segment retry.
  final Duration retryDelay;

  /// Playlist failures in a row that end the connection (§7.2).
  final int playlistFailures;

  /// Segments given up in a row that end the connection.
  final int segmentFailures;

  /// The first playlist of a feed starts this many segments from its end
  /// (like FFmpeg's `live_start_index -3`, RFC 8216 §6.3.3).
  final int liveStart;

  /// Segment downloads at once, counting downloaded ones waiting to be written (§7.3).
  final int concurrency;

  /// Longest wait for downloads in flight when stopping (§7.8), also capped at one target duration.
  final Duration stopWait;

  /// Wait before retrying a failed lease renewal.
  final Duration renewRetry;

  /// Largest playlist body (§7.2).
  final int playlistBytes;

  /// Largest segment body.
  final int segmentBytes;

  /// A larger jump of `EXT-X-DISCONTINUITY-SEQUENCE` marks a broken playlist (§7.4).
  final int maxDiscontinuityStep;
}

sealed class _Job {
  new();
}

final class _SegmentJob extends _Job {
  new(this.segment);

  final M3u8Segment segment;
  Future<_Result>? download;
}

final class _MissingJob extends _Job {
  new(this.missing, {this.rebase});

  final HlsMissing missing;

  /// Sequence number the feed continues after (a reset renumbers the feed).
  final int? rebase;
}

sealed class _Result {
  const new();
}

final class _Ok extends _Result {
  const new(this.media);

  final HlsMedia media;
}

final class _Failed extends _Result {
  const new(this.error);

  final Object error;
}

/// Records one HLS media playlist (a feed) for one connection of a session
/// (spec §7): polls the playlist at the RFC 8216 §6.3.4 pace (one target
/// duration after a changed playlist, half of one after an unchanged one,
/// measured from the request start, never two requests at once), downloads
/// whole segments (at most two at a time, delivered in sequence order),
/// decrypts AES-128, follows `EXT-X-MAP`, reads byte ranges as absolute
/// ranges, skips LL-HLS parts, numbers segments by media sequence, and
/// reports what it could not record as gaps.
///
/// [run] ends normally at `EXT-X-ENDLIST` (after writing everything) or
/// after [stop], and throws the error that ended the connection otherwise:
/// the playlist failing [HlsTimings.playlistFailures] times in a row, a 4xx
/// the renewal did not fix, segments failing
/// [HlsTimings.segmentFailures] times in a row, no new segment for the
/// stall time, or content that cannot be recorded
/// (`RecordException(unsupportedProtocol)`).
final class HlsFeed {
  /// Creates a feed for `line` delivering into `sink`. [state] carries the
  /// sequence position across connections. `renew` re-resolves the same
  /// quality and line (lease renewal §7.6, and a playlist 4xx); [readTimeout]
  /// is `record.readTimeout`: no new segment for it (or four target
  /// durations, whichever is longer) ends the connection.
  new({
    required this._line,
    required this._client,
    required this._sink,
    required this.state,
    this._renew,
    this._onLine,
    this.readTimeout = const Duration(seconds: 15),
    this.timings = const HlsTimings(),
  });

  final HlsClient _client;
  final HlsSink _sink;
  final Future<StreamLine> Function(StreamLine current)? _renew;
  final void Function(StreamLine line)? _onLine;

  /// Position kept across connections.
  final HlsFeedState state;

  /// `record.readTimeout`.
  final Duration readTimeout;

  /// Limits.
  final HlsTimings timings;

  StreamLine _line;
  Uri? _mediaUrl;
  StreamLine? _pendingLine;
  var _leaseSwitched = false;
  Timer? _leaseTimer;

  final _jobs = ListQueue<_Job>();
  int? _lastQueued;
  int _targetMs = 6000;
  String? _previousText;
  int? _previousDiscontinuity;
  int? _behindLast;
  var _behindRounds = 0;
  DateTime _lastNewAt = clock.now();

  final _cancel = Completer<void>();
  Completer<void>? _wake;
  Completer<void>? _publisherWake;
  var _started = false;
  var _frozen = false;
  var _closing = false;
  Object? _failed;
  var _segmentFailures = 0;

  final _keys = <Uri, Future<HlsAes128>>{};
  M3u8Map? _map;
  Future<Uint8List>? _init;

  /// Target duration of the last playlist.
  Duration get target => Duration(milliseconds: _targetMs);

  /// The line in use (changes on renewal).
  StreamLine get line => _line;

  /// Runs the connection; see the class comment for how it ends.
  Future<void> run() async {
    if (_started) throw StateError('A feed runs once');
    _started = true;
    _scheduleLease(_line);
    final publisher = _publishLoop().then<Object?>((_) => null, onError: (Object error) => error);
    Object? error;
    try {
      await _pollLoop();
      if (_failed == null) {
        _closing = true;
        _wakePublisher();
      }
      error = await publisher;
    } on Object catch (caught) {
      error = caught;
    } finally {
      _leaseTimer?.cancel();
    }
    error ??= _failed;
    if (error != null) {
      _cancelAll();
      if (error is! HlsCancelled) _throw(error);
    }
  }

  /// Stops as the user asked (§7.8): no more playlist requests or new
  /// segments; downloads in flight get one target duration (at most
  /// [HlsTimings.stopWait]) to finish and be written; what is left becomes a
  /// `stop` gap. Completes when the feed is done.
  Future<void> stop() async {
    if (_frozen && _closing) return;
    _frozen = true;
    _closing = true;
    _leaseTimer?.cancel();
    final dropped = <M3u8Segment>[];
    final kept = ListQueue<_Job>();
    for (final job in _jobs) {
      if (job is _SegmentJob && job.download == null) {
        dropped.add(job.segment);
      } else {
        kept.add(job);
      }
    }
    _jobs
      ..clear()
      ..addAll(kept);
    _wakePoll();
    _wakePublisher();
    final wait = target < timings.stopWait ? target : timings.stopWait;
    final done = Completer<void>();
    void check() {
      if (_jobs.isEmpty && !done.isCompleted) done.complete();
    }

    final timer = Timer.periodic(const Duration(milliseconds: 50), (_) => check());
    check();
    await done.future.timeout(wait, onTimeout: () {});
    timer.cancel();
    for (final job in _jobs) {
      if (job is _SegmentJob) dropped.add(job.segment);
    }
    _cancelAll();
    if (dropped.isNotEmpty && state.wroteMedia) {
      dropped.sort((a, b) => a.sequence.compareTo(b.sequence));
      _sink.addMissing(
        HlsMissing(
          reason: GapReason.stop,
          missingMs: dropped.fold(0, (sum, segment) => sum + segment.durationMs),
          fromSeq: dropped.first.sequence,
          toSeq: dropped.last.sequence,
          wallStart: clock.now(),
        ),
      );
    }
  }

  /// Drops the connection now.
  void cancel() {
    _frozen = true;
    _cancelAll();
  }

  void _cancelAll() {
    _frozen = true;
    _leaseTimer?.cancel();
    if (!_cancel.isCompleted) _cancel.complete();
    _wakePoll();
    _wakePublisher();
  }

  void _fail(Object error) {
    _failed ??= error;
    _cancelAll();
  }

  // Playlist polling (§7.2).

  Future<void> _pollLoop() async {
    var failures = 0;
    var renewedSinceSuccess = false;
    while (true) {
      if (_failed != null) _throw(_failed!);
      if (_frozen) return;
      final pending = _pendingLine;
      if (pending != null) {
        _pendingLine = null;
        _switchTo(pending);
      }
      final url = _mediaUrl ?? _line.url;
      final started = clock.now();
      M3u8Media playlist;
      String text;
      try {
        (playlist, text) = await _load(url, resolveMaster: _mediaUrl == null);
        _checkDiscontinuity(playlist);
      } on HlsCancelled {
        if (_failed != null) _throw(_failed!);
        return;
      } on Object catch (error) {
        if (_frozen) return;
        if (error is RecordException) rethrow;
        if (error is UpstreamStatusException && error.status >= 400 && error.status < 500) {
          // A refused playlist: renew once (§7.2, §11.7); the outer loop handles a second refusal.
          final renew = _renew;
          if (renew == null || renewedSinceSuccess) rethrow;
          renewedSinceSuccess = true;
          StreamLine next;
          try {
            next = await renew(_line);
          } on Object {
            throw error;
          }
          _switchTo(next);
          continue;
        }
        failures++;
        if (failures >= timings.playlistFailures) rethrow;
        await _sleepUntil(started.add(Duration(milliseconds: max(1000, _targetMs ~/ 2))));
        continue;
      }
      failures = 0;
      renewedSinceSuccess = false;
      if (_frozen) return;
      final changed = text != _previousText;
      _previousText = text;
      _targetMs = playlist.targetDuration * 1000;
      _schedule(playlist);
      if (playlist.endList) return;
      final stall = Duration(milliseconds: max(readTimeout.inMilliseconds, 4 * _targetMs));
      if (clock.now().difference(_lastNewAt) > stall) {
        throw TimeoutException('no new HLS segment for ${stall.inSeconds} s', stall);
      }
      // RFC 8216 §6.3.4: from the start of the last request.
      await _sleepUntil(started.add(Duration(milliseconds: changed ? _targetMs : _targetMs ~/ 2)));
    }
  }

  void _switchTo(StreamLine next) {
    final urlChanged = next.url != _line.url;
    _line = next;
    _onLine?.call(next);
    if (urlChanged) {
      _mediaUrl = null;
      _previousText = null;
      _previousDiscontinuity = null;
      _leaseSwitched = true;
      _map = null;
      _init = null;
    }
    _scheduleLease(next);
  }

  /// Fetches and parses [url]; a master playlist is followed to its best
  /// variant (§7.1) when [resolveMaster].
  Future<(M3u8Media, String)> _load(Uri url, {required bool resolveMaster}) async {
    final (playlist, text, _) = await _fetch(url);
    if (playlist is M3u8Master) {
      if (!resolveMaster) throw const FormatException('the media playlist turned into a master playlist');
      final variant = playlist.best!;
      if (playlist.separateAudio(variant).isNotEmpty) {
        throw RecordException(
          RecordErrorKind.unsupportedProtocol,
          RecordStage.stream,
          'HLS with a separate audio rendition is not recorded yet',
        );
      }
      final (media, mediaText, _) = await _fetch(variant.uri);
      if (media is! M3u8Media) throw const FormatException('a variant of the master is a master playlist');
      // Polled at the variant's own address; relative URIs resolve against the final one.
      _mediaUrl = variant.uri;
      return (media, mediaText);
    }
    _mediaUrl = url;
    return (playlist as M3u8Media, text);
  }

  /// A jump of more than [HlsTimings.maxDiscontinuityStep] marks a broken
  /// playlist (§7.4): it counts as a failed request.
  void _checkDiscontinuity(M3u8Media playlist) {
    final previous = _previousDiscontinuity;
    if (previous != null && (playlist.discontinuitySequence - previous).abs() > timings.maxDiscontinuityStep) {
      throw FormatException('EXT-X-DISCONTINUITY-SEQUENCE jumped from $previous to ${playlist.discontinuitySequence}');
    }
    _previousDiscontinuity = playlist.discontinuitySequence;
  }

  Future<(M3u8Playlist, String, Uri)> _fetch(Uri url) async {
    final response = await _client.get(
      HlsRequest(url: url, headers: _line.headers, maxBytes: timings.playlistBytes, cancel: _cancel.future),
    );
    final text = utf8.decode(response.body, allowMalformed: true);
    return (M3u8Playlist.parse(text, response.url), text, response.url);
  }

  void _scheduleLease(StreamLine line) {
    _leaseTimer?.cancel();
    final lease = line.lease;
    final renew = _renew;
    if (lease == null || renew == null || _frozen) return;
    var delay = lease.refreshAt.difference(clock.now());
    if (delay < Duration.zero) delay = Duration.zero;
    _leaseTimer = Timer(delay, () async {
      try {
        final next = await renew(_line);
        if (!_frozen) _pendingLine = next;
      } on Object {
        // The old address keeps working until it is refused (§7.6).
        if (!_frozen) {
          _leaseTimer = Timer(timings.renewRetry, () => _scheduleLease(_line));
        }
      }
    });
  }

  // Sequence bookkeeping (§7.4).

  int? get _cursor => _lastQueued ?? state.lastSequence;

  void _schedule(M3u8Media playlist) {
    final segments = playlist.segments;
    if (segments.isEmpty) return;
    final first = segments.first.sequence;
    final last = segments.last.sequence;
    final cursor = _cursor;
    final edge = max(first, last - timings.liveStart + 1);
    int from;
    if (cursor == null) {
      from = edge;
    } else if (last <= cursor) {
      if (!_isReset(last, cursor, segments.length)) return;
      _enqueueReset(from: edge);
      from = edge;
    } else if (first > cursor + 1) {
      final count = first - cursor - 1;
      final missingMs = count * _targetMs;
      final since = state.lastConsumedAt;
      final wall = since == null ? null : clock.now().difference(since).inMilliseconds;
      if (wall == null || missingMs <= 2 * wall + 3 * _targetMs + 60000) {
        _enqueue(
          _MissingJob(
            HlsMissing(
              reason: GapReason.sequenceJump,
              missingMs: missingMs,
              fromSeq: cursor + 1,
              toSeq: first - 1,
              wallStart: since,
            ),
          ),
        );
        from = first;
      } else {
        // Far more media missing than time passed: the numbering changed.
        _enqueueReset(from: edge);
        from = edge;
      }
    } else {
      from = cursor + 1;
    }
    _behindLast = null;
    _behindRounds = 0;
    _leaseSwitched = false;
    var added = false;
    for (final segment in segments) {
      if (segment.sequence < from) continue;
      if (segment.key.method == M3u8KeyMethod.unsupported) {
        throw RecordException(
          RecordErrorKind.unsupportedProtocol,
          RecordStage.stream,
          'HLS encryption ${segment.key.detail} is not supported',
        );
      }
      if (segment.gap) {
        _enqueue(
          _MissingJob(
            HlsMissing(
              reason: GapReason.sequenceJump,
              missingMs: segment.durationMs,
              fromSeq: segment.sequence,
              toSeq: segment.sequence,
            ),
          ),
        );
      } else {
        _enqueue(_SegmentJob(segment));
      }
      _lastQueued = segment.sequence;
      added = true;
    }
    if (added) _lastNewAt = clock.now();
  }

  /// Whether a playlist that ends at [last], not past [cursor], restarted
  /// its numbering: far behind, or growing twice while behind.
  bool _isReset(int last, int cursor, int length) {
    if (last < cursor - max(10, 3 * length)) return true;
    final previous = _behindLast;
    _behindLast = last;
    if (previous != null && last > previous) _behindRounds++;
    return _behindRounds >= 2;
  }

  void _enqueueReset({required int from}) {
    final since = state.lastConsumedAt;
    _enqueue(
      _MissingJob(
        HlsMissing(
          reason: _leaseSwitched ? GapReason.lease : GapReason.reset,
          missingMs: since == null ? 0 : clock.now().difference(since).inMilliseconds,
          wallStart: since,
        ),
        rebase: from - 1,
      ),
    );
    _lastQueued = from - 1;
  }

  void _enqueue(_Job job) {
    _jobs.add(job);
    _pump();
    _wakePublisher();
  }

  // Downloads and delivery (§7.3).

  void _pump() {
    var slots = timings.concurrency;
    for (final job in _jobs) {
      if (slots <= 0) break;
      if (job is! _SegmentJob) continue;
      slots--;
      job.download ??= _download(job.segment);
    }
  }

  Future<void> _publishLoop() async {
    while (true) {
      if (_cancel.isCompleted) return;
      if (_jobs.isEmpty) {
        if (_closing) return;
        await (_publisherWake ??= Completer<void>()).future;
        continue;
      }
      final job = _jobs.first;
      switch (job) {
        case _MissingJob(:final missing, :final rebase):
          if (state.wroteMedia) _sink.addMissing(missing);
          if (rebase != null) {
            state.lastSequence = rebase;
          } else if (missing.toSeq != null) {
            state.lastSequence = missing.toSeq;
          }
          state.lastConsumedAt = clock.now();
          _jobs.removeFirst();
        case _SegmentJob(:final segment):
          _pump();
          final result = await job.download!;
          if (_cancel.isCompleted) return;
          await _sink.ready;
          if (_cancel.isCompleted) return;
          if (_jobs.isEmpty || !identical(_jobs.first, job)) continue;
          switch (result) {
            case _Ok(:final media):
              try {
                _sink.addMedia(media);
              } on Object catch (error) {
                _fail(error);
                rethrow;
              }
              state.wroteMedia = true;
              _segmentFailures = 0;
            case _Failed(:final error):
              if (error is HlsCancelled) return;
              if (state.wroteMedia) {
                _sink.addMissing(
                  HlsMissing(
                    reason: _reasonOf(error),
                    missingMs: segment.durationMs,
                    fromSeq: segment.sequence,
                    toSeq: segment.sequence,
                    wallStart: clock.now(),
                  ),
                );
              }
              if (++_segmentFailures >= timings.segmentFailures) {
                _jobs.removeFirst();
                state
                  ..lastSequence = segment.sequence
                  ..lastConsumedAt = clock.now();
                _fail(error);
                _throw(error);
              }
          }
          state
            ..lastSequence = segment.sequence
            ..lastConsumedAt = clock.now();
          _jobs.removeFirst();
          _pump();
      }
    }
  }

  static GapReason _reasonOf(Object error) => switch (error) {
    UpstreamStatusException(:final status) when status >= 500 => GapReason.http5xx,
    UpstreamStatusException() => GapReason.http4xx,
    _ => GapReason.network,
  };

  Future<_Result> _download(M3u8Segment segment) async {
    Object error = const HlsCancelled();
    for (var attempt = 0; attempt <= timings.segmentRetries; attempt++) {
      if (_cancel.isCompleted) return const _Failed(HlsCancelled());
      if (attempt > 0) {
        await Future.any([Future<void>.delayed(timings.retryDelay), _cancel.future]);
        if (_cancel.isCompleted) return const _Failed(HlsCancelled());
      }
      try {
        final map = segment.map;
        final init = map == null ? null : await _initOf(map, segment.sequence);
        final response = await _client.get(
          HlsRequest(
            url: segment.uri,
            headers: _line.headers,
            range: segment.range,
            maxBytes: timings.segmentBytes,
            cancel: _cancel.future,
          ),
        );
        var data = response.body;
        final key = segment.key;
        if (key.method == M3u8KeyMethod.aes128) {
          final cipher = await _cipherOf(key);
          try {
            data = cipher.decrypt(data, key.iv ?? HlsAes128.sequenceIv(segment.sequence));
          } on FormatException {
            // A rotated key under the same URI: fetch it again next time.
            _keys.remove(key.uri)?.ignore();
            rethrow;
          }
        }
        return _Ok(
          HlsMedia(
            sequence: segment.sequence,
            durationMs: segment.durationMs,
            data: data,
            init: init,
            discontinuity: segment.discontinuity,
          ),
        );
      } on HlsCancelled {
        return const _Failed(HlsCancelled());
      } on Object catch (caught) {
        if (_cancel.isCompleted) return const _Failed(HlsCancelled());
        error = caught;
      }
    }
    return _Failed(error);
  }

  Future<HlsAes128> _cipherOf(M3u8Key key) {
    final uri = key.uri!;
    final cached = _keys[uri];
    if (cached != null) return cached;
    final future = () async {
      final response = await _client.get(
        HlsRequest(url: uri, headers: _line.headers, maxBytes: 1024, cancel: _cancel.future),
      );
      if (response.body.length != 16) throw FormatException('AES-128 key of ${response.body.length} bytes');
      return HlsAes128(response.body);
    }();
    _keys[uri] = future;
    future.ignore();
    unawaited(future.then((_) {}, onError: (Object _) => _keys.remove(uri)?.ignore()));
    while (_keys.length > 8) {
      _keys.remove(_keys.keys.first)?.ignore();
    }
    return future;
  }

  Future<Uint8List> _initOf(M3u8Map map, int sequence) {
    final current = _init;
    if (current != null && _map == map) return current;
    final future = () async {
      final response = await _client.get(
        HlsRequest(
          url: map.uri,
          headers: _line.headers,
          range: map.range,
          maxBytes: timings.playlistBytes,
          cancel: _cancel.future,
        ),
      );
      var data = response.body;
      if (map.key.method == M3u8KeyMethod.aes128) {
        data = (await _cipherOf(map.key)).decrypt(data, map.key.iv ?? HlsAes128.sequenceIv(sequence));
      }
      return data;
    }();
    _map = map;
    _init = future;
    future.ignore();
    unawaited(
      future.then(
        (_) {},
        onError: (Object _) {
          if (identical(_init, future)) {
            _init = null;
            _map = null;
          }
        },
      ),
    );
    return future;
  }

  // Waiting.

  Future<void> _sleepUntil(DateTime when) async {
    final delay = when.difference(clock.now());
    if (delay <= Duration.zero || _frozen) return;
    final wake = _wake = Completer<void>();
    final timer = Timer(delay, () {
      if (!wake.isCompleted) wake.complete();
    });
    await wake.future;
    timer.cancel();
  }

  void _wakePoll() {
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  void _wakePublisher() {
    final wake = _publisherWake;
    _publisherWake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }
}

/// Throws [error] (any object) with the current stack.
Never _throw(Object error) => Error.throwWithStackTrace(error, StackTrace.current);
