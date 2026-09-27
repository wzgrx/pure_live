import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:live_record/src/errors.dart';
import 'package:live_record/src/files.dart';
import 'package:live_record/src/naming.dart';
import 'package:live_record/src/writer.dart';

/// Limits of the session writers (spec §6.8). Defaults follow the spec.
final class FlvWriterLimits {
  /// Creates the limits.
  const new({
    this.queueBytes = 8 * 1024 * 1024,
    this.flushInterval = const Duration(seconds: 1),
    this.flushBytes = 1024 * 1024,
    this.stallTimeout = const Duration(seconds: 30),
    this.alignmentWindow = const Duration(seconds: 60),
    this.audioOnlyAfter = 200,
  });

  /// Queued bytes above which the writer's `ready` makes the reader wait.
  final int queueBytes;

  /// Longest time between flushes while data arrives.
  final Duration flushInterval;

  /// Unflushed bytes that trigger a flush.
  final int flushBytes;

  /// A write or flush slower than this is a fatal disk stall.
  final Duration stallTimeout;

  /// A new FLV connection whose first timestamp lies ahead of the written
  /// position by at most this much keeps its timeline (spec §6.3).
  final Duration alignmentWindow;

  /// FLV audio tags without any video tag after which a stream announcing
  /// video is recorded as audio only.
  final int audioOnlyAfter;
}

sealed class _Op {
  const new();
}

final class _Open extends _Op {
  const new(this.segment);
  final RecordedSegment segment;
}

final class _Write extends _Op {
  const new(this.bytes);
  final Uint8List bytes;
}

final class _Flush extends _Op {
  const new();
}

final class _Close extends _Op {
  const new(this.segment);
  final RecordedSegment segment;
}

final class _Barrier extends _Op {
  new();
  final done = Completer<void>();
}

/// The file side of a session writer (spec §6.1, §6.8, §6.9): operations run
/// in order in the background. A segment is created exclusively as
/// `<name>.part` under the first free name and renamed when closed. Writes
/// are flushed at least every second or MiB. [ready] holds the reader back
/// while more than `queueBytes` wait; a write or flush that fails, or
/// takes longer than `stallTimeout`, is fatal.
final class SegmentFiles {
  /// Creates the queue; `onClosed` runs when a segment's file is complete.
  new(this._files, this.limits, {this._onClosed}) {
    _flushTimer = Timer.periodic(limits.flushInterval, (_) => _periodicFlush());
  }

  final RecordFiles _files;
  final void Function(RecordedSegment segment)? _onClosed;

  /// Limits.
  final FlvWriterLimits limits;

  final _ops = ListQueue<_Op>();
  var _queued = 0;
  var _pumping = false;
  RecordSink? _sink;
  var _unflushed = 0;
  DateTime _lastFlush = clock.now();
  late final Timer _flushTimer;
  Completer<void>? _readyWaiter;
  final _failure = Completer<RecordFailure>();
  RecordFailure? _failed;
  var _stopped = false;

  /// Completes with the fatal error, if one happens.
  Future<RecordFailure> get failure => _failure.future;

  /// The fatal error, once there is one.
  RecordFailure? get failed => _failed;

  /// Completes when the queue is below its limit.
  Future<void> get ready {
    if (_queued < limits.queueBytes || _failed != null || _stopped) return Future.value();
    return (_readyWaiter ??= Completer<void>()).future;
  }

  /// Creates the file of [segment] (under a free name) as the current file.
  void open(RecordedSegment segment) => _enqueue(_Open(segment));

  /// Appends [bytes] to the current file.
  void write(Uint8List bytes) => _enqueue(_Write(bytes));

  /// Closes the current file and renames it to [segment]'s path.
  void close(RecordedSegment segment) => _enqueue(_Close(segment));

  /// Completes when everything queued so far ran (or writing failed).
  Future<void> drain() {
    if (_failed != null) return Future.value();
    final barrier = _Barrier();
    _enqueue(barrier);
    return barrier.done.future;
  }

  /// Stops writing with [failure] (a fatal error found by the writer itself).
  void fail(RecordFailure failure) {
    if (_failed != null) return;
    _failed = failure;
    for (final op in _ops) {
      if (op is _Barrier && !op.done.isCompleted) op.done.complete();
    }
    _ops.clear();
    _queued = 0;
    _wakeReady();
    _failure.complete(failure);
  }

  /// After a fatal error: closes the open file and renames [segment]'s
  /// `.part` to its final name, giving up after [giveUpAfter] (crash
  /// recovery finishes a file left behind at the next start).
  Future<void> salvage(RecordedSegment? segment, Duration giveUpAfter) async {
    if (segment == null || segment.closed) return;
    try {
      await Future(() async {
        final sink = _sink;
        _sink = null;
        await sink?.close();
        if (await _files.exists('${segment.path}$partSuffix')) {
          await _files.rename('${segment.path}$partSuffix', segment.path);
          segment.closed = true;
        }
      }).timeout(giveUpAfter);
    } on Object {
      // Left as .part; crash recovery finishes it at the next start.
    }
  }

  /// Stops the flush timer and releases a waiting reader.
  void stop() {
    _stopped = true;
    _flushTimer.cancel();
    _wakeReady();
  }

  void _enqueue(_Op op) {
    if (_failed != null) {
      if (op is _Barrier && !op.done.isCompleted) op.done.complete();
      return;
    }
    _ops.add(op);
    if (op is _Write) _queued += op.bytes.length;
    if (!_pumping) unawaited(_pump());
  }

  void _periodicFlush() {
    if (_unflushed > 0 && _ops.isEmpty && !_pumping && _sink != null) _enqueue(const _Flush());
  }

  Future<void> _pump() async {
    _pumping = true;
    try {
      while (_ops.isNotEmpty && _failed == null) {
        final op = _ops.removeFirst();
        final stall = Timer(limits.stallTimeout, () {
          fail(RecordFailure(RecordErrorKind.diskStalled, RecordStage.writer, 'write stalled'));
        });
        try {
          await _run(op);
        } on RecordFileExists catch (error) {
          fail(RecordFailure(RecordErrorKind.pathInvalid, RecordStage.writer, error.toString()));
        } on FileSystemException catch (error) {
          fail(classifyFileError(error));
        } on Object catch (error) {
          fail(RecordFailure(RecordErrorKind.pathInvalid, RecordStage.writer, error.toString()));
        } finally {
          stall.cancel();
          if (op is _Write && _failed == null) {
            _queued -= op.bytes.length;
            if (_queued < limits.queueBytes) _wakeReady();
          }
        }
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _run(_Op op) async {
    switch (op) {
      case _Open(:final segment):
        final path = await uniquePath(_files, segment.plannedPath);
        segment.finalPath = path;
        _sink = await _files.create('$path$partSuffix');
        _unflushed = 0;
        _lastFlush = clock.now();
      case _Write(:final bytes):
        final sink = _sink;
        if (sink == null) return;
        await sink.write(bytes);
        _unflushed += bytes.length;
        if (_unflushed >= limits.flushBytes || clock.now().difference(_lastFlush) >= limits.flushInterval) {
          await sink.flush();
          _unflushed = 0;
          _lastFlush = clock.now();
        }
      case _Flush():
        final sink = _sink;
        if (sink == null || _unflushed == 0) return;
        await sink.flush();
        _unflushed = 0;
        _lastFlush = clock.now();
      case _Close(:final segment):
        final sink = _sink;
        _sink = null;
        if (sink != null) {
          await sink.flush();
          await sink.close();
          await _files.rename('${segment.path}$partSuffix', segment.path);
        }
        segment.closed = true;
        _onClosed?.call(segment);
      case _Barrier(:final done):
        done.complete();
    }
  }

  void _wakeReady() {
    final waiter = _readyWaiter;
    _readyWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }
}
