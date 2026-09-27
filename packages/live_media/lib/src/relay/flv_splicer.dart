import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/src/relay/flv.dart';
import 'package:live_media/src/relay/upstream.dart';
import 'package:meta/meta.dart';

/// Resolves a fresh URL for the same room, quality and line as [current].
typedef LineRenewer = Future<StreamLine> Function(StreamLine current);

/// Limits of one splice (SRC-5).
@immutable
final class SpliceTimings {
  /// Creates the limits; defaults follow the spec.
  const new({
    this.renewTimeout = const Duration(seconds: 12),
    this.connectTimeout = const Duration(seconds: 15),
    this.keyframeSearch = const Duration(seconds: 15),
    this.handoverWait = const Duration(seconds: 10),
    this.retryDelay = const Duration(seconds: 10),
    this.alignmentWindow = const Duration(seconds: 60),
    this.shiftGap = const Duration(milliseconds: 40),
  });

  /// Longest wait for the renewal callback (the refresh timeout of §5).
  final Duration renewTimeout;

  /// Longest wait for the new connection's header.
  final Duration connectTimeout;

  /// Longest search for a usable keyframe on the new connection.
  final Duration keyframeSearch;

  /// Longest wait for the old stream to reach the new keyframe.
  final Duration handoverWait;

  /// Wait before another renewal attempt while the old connection still streams.
  final Duration retryDelay;

  /// A new connection whose first video timestamp is further than this from
  /// the delivered position is on another timeline and gets shifted.
  final Duration alignmentWindow;

  /// Step between the last delivered video tag and a shifted keyframe.
  final Duration shiftGap;
}

/// Something the splicer did, for logs and the `live_cli lease` report.
@immutable
sealed class SpliceEvent {
  const new();
}

/// A renewal started ([SpliceSwitched] or [SpliceRenewFailed] follows).
final class SpliceRenewing extends SpliceEvent {
  /// Creates the event.
  const new({required this.oldEnded});

  /// Whether the old connection had already ended.
  final bool oldEnded;

  @override
  String toString() => 'renewing${oldEnded ? ' after the old connection ended' : ''}';
}

/// The output continued on a new connection.
final class SpliceSwitched extends SpliceEvent {
  /// Creates the event.
  const new({
    required this.line,
    required this.switchAt,
    required this.shifted,
    required this.oldEnded,
    required this.waitedForOld,
  });

  /// The new line.
  final StreamLine line;

  /// Output timestamp of the first new keyframe, in ms.
  final int switchAt;

  /// Whether the new connection was on another timeline and was shifted.
  final bool shifted;

  /// Whether the old connection had ended before the switch.
  final bool oldEnded;

  /// How long the old stream was forwarded after the new keyframe was found.
  final Duration waitedForOld;

  @override
  String toString() =>
      'switched to ${line.lineId} at ${switchAt}ms${shifted ? ' (shifted)' : ''}'
      '${oldEnded ? ' after the old connection ended' : ''}, waited ${waitedForOld.inMilliseconds}ms';
}

/// A renewal attempt failed; the old connection keeps streaming.
final class SpliceRenewFailed extends SpliceEvent {
  /// Creates the event.
  const new(this.error);

  /// What failed.
  final Object error;

  @override
  String toString() => 'renewal failed: $error';
}

/// The spliced output ended.
final class SpliceEnded extends SpliceEvent {
  /// Creates the event.
  const new(this.reason);

  /// Why.
  final String reason;

  @override
  String toString() => 'ended: $reason';
}

final class _Candidate {
  new(this.line, this.source, this.keyframe, {required this.aligned});

  final StreamLine line;
  final FlvPacketSource source;
  final Uint8List keyframe;

  /// Same timeline as the delivered output: switch where the old stream
  /// reaches [switchAt]. Otherwise switch at once and shift.
  final bool aligned;
  int offset = 0;
  Uint8List? videoConfig;
  Uint8List? audioConfig;
  final audioBefore = ListQueue<Uint8List>();
  DateTime? readyAt;

  int get switchAt => FlvTag.timestamp(keyframe) + offset;
}

/// Streams one continuous FLV from a line whose lease cuts the connection
/// (Douyu `expire`), replacing the upstream URL underneath the player (SRC-5).
///
/// At the lease's `refreshAt` the renewed line is connected while the old
/// connection keeps being forwarded. The switch happens at the first keyframe
/// of the new connection that the old one has not delivered: the old stream
/// is forwarded up to that timestamp, then the new one from its keyframe on,
/// so the player sees one timestamp timeline without gap or repeat. A new
/// connection on another timeline (more than 60 s away) is shifted to
/// continue the delivered one. Script tags are not repeated after a switch;
/// codec configurations are re-sent when they change. When the old connection
/// ends before a successor is ready, at most one GOP is skipped; when no
/// successor can be opened, the output ends and the player's recovery takes over.
final class FlvSplicer {
  /// Creates a splicer starting at [line].
  new({
    required this._line,
    required this._open,
    required this._renew,
    required this._emit,
    this._onEvent,
    this.timings = const SpliceTimings(),
  });

  final FlvSourceOpener _open;
  final LineRenewer _renew;
  final void Function(Uint8List packet) _emit;
  final void Function(SpliceEvent event)? _onEvent;

  /// Limits.
  final SpliceTimings timings;

  StreamLine _line;
  FlvPacketSource? _source;
  Future<Uint8List?>? _pending;
  var _offset = 0;
  int? _lastVideo;
  int? _lastAudio;
  Uint8List? _videoConfig;
  Uint8List? _audioConfig;
  var _switches = 0;
  var _cancelled = false;
  var _oldEnded = false;

  Timer? _renewTimer;
  Future<_Candidate?>? _preparing;
  _Candidate? _ready;
  var _scanning = false;
  var _holdUsed = false;
  Uint8List? _held;
  DateTime? _holdUntil;
  Timer? _holdTimer;

  bool get _holdExpired {
    final until = _holdUntil;
    return until == null || !clock.now().isBefore(until);
  }

  Completer<void>? _wake;
  Timer? _handoverTimer;

  /// The line currently streaming.
  StreamLine get line => _line;

  /// Completed switches.
  int get switches => _switches;

  /// Last delivered video timestamp (output timeline), if any.
  int? get lastVideoTimestamp => _lastVideo;

  /// Runs until the output ends; throws when the first connection cannot be
  /// opened or is not FLV.
  Future<void> run() async {
    final first = await _open(_line);
    if (_cancelled) {
      await first.cancel();
      return;
    }
    _source = first;
    final header = await first.next();
    if (header == null) throw const FormatException('Empty FLV upstream');
    _emit(header);
    _scheduleRenewal();
    try {
      while (!_cancelled) {
        final ready = _ready;
        if (ready != null && (!ready.aligned || _handoverExpired(ready))) {
          await _switchTo(ready);
          continue;
        }
        final Uint8List tag;
        final held = _held;
        if (held != null) {
          if (ready == null && _preparing != null && !_holdExpired) {
            await (_wake ??= Completer<void>()).future;
            continue;
          }
          _held = null;
          _holdTimer?.cancel();
          tag = held;
        } else {
          final packet = await _nextOrWake();
          if (_cancelled) break;
          if (identical(packet, _woken)) continue;
          if (packet == null) {
            final next = await _afterOldEnded();
            if (next == null) {
              _onEvent?.call(const SpliceEnded('upstream ended without a successor'));
              break;
            }
            await _switchTo(next);
            continue;
          }
          tag = packet as Uint8List;
          if (_ready == null && _scanning && !_holdUsed && FlvTag.isKeyframe(tag)) {
            // Both connections sit at the live edge, so the old one would
            // usually deliver the shared keyframe first and push the switch
            // to a later GOP (or past the cut). Hold the old stream just
            // before its keyframe until the new connection reaches it.
            _held = tag;
            _holdUsed = true;
            _holdUntil = clock.now().add(timings.handoverWait);
            _holdTimer = Timer(timings.handoverWait, _signal);
            continue;
          }
        }
        final current = _ready;
        if (current != null && current.aligned) {
          final type = FlvTag.type(tag);
          final ts = FlvTag.timestamp(tag) + _offset;
          if (type == FlvTag.video && !FlvTag.isVideoConfig(tag) && ts >= current.switchAt) {
            await _switchTo(current);
            continue;
          }
          if (type == FlvTag.audio && !FlvTag.isAudioConfig(tag) && ts >= current.switchAt) continue;
        }
        _forward(tag, _offset);
      }
    } finally {
      await _teardown();
    }
  }

  /// Stops the output and drops every connection.
  Future<void> cancel() async {
    _cancelled = true;
    _signal();
    await _teardown();
  }

  static final Object _woken = Object();

  bool _handoverExpired(_Candidate candidate) {
    final readyAt = candidate.readyAt;
    return readyAt != null && clock.now().difference(readyAt) >= timings.handoverWait;
  }

  void _signal() {
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  Future<Object?> _nextOrWake() async {
    final source = _source!;
    final pending = _pending ??= source.next();
    final wake = _wake ??= Completer<void>();
    final result = await Future.any<Object?>([pending, wake.future.then((_) => _woken)]);
    if (!identical(result, _woken)) {
      _pending = null;
      if (identical(_wake, wake)) _wake = null;
    }
    return result;
  }

  void _scheduleRenewal() {
    _renewTimer?.cancel();
    final lease = _line.lease;
    if (lease == null || !lease.cutsConnection) return;
    var delay = lease.refreshAt.difference(clock.now());
    if (delay < Duration.zero) delay = Duration.zero;
    _renewTimer = Timer(delay, _startPreparing);
  }

  void _startPreparing() {
    if (_cancelled || _preparing != null || _ready != null) return;
    _holdUsed = false;
    _onEvent?.call(SpliceRenewing(oldEnded: _oldEnded));
    final attempt = _prepare();
    _preparing = attempt;
    unawaited(
      attempt.then((candidate) {
        if (!identical(_preparing, attempt)) return;
        _preparing = null;
        _scanning = false;
        if (_cancelled) {
          if (candidate != null) unawaited(candidate.source.cancel());
          return;
        }
        if (candidate != null) {
          candidate.readyAt = clock.now();
          _ready = candidate;
          if (candidate.aligned) {
            _handoverTimer?.cancel();
            _handoverTimer = Timer(timings.handoverWait, _signal);
          }
        } else if (!_oldEnded) {
          _renewTimer?.cancel();
          _renewTimer = Timer(timings.retryDelay, _startPreparing);
        }
        _signal();
      }),
    );
  }

  Future<_Candidate?> _afterOldEnded() async {
    _oldEnded = true;
    final ready = _ready;
    if (ready != null) return ready;
    var preparing = _preparing;
    if (preparing == null) {
      _renewTimer?.cancel();
      _startPreparing();
      preparing = _preparing;
    }
    if (preparing == null) return null;
    await preparing;
    return _ready;
  }

  Future<_Candidate?> _prepare() async {
    FlvPacketSource? source;
    try {
      final next = await _renew(_line).timeout(timings.renewTimeout);
      if (_cancelled) return null;
      source = await _open(next).timeout(timings.connectTimeout);
      if (_cancelled) {
        await source.cancel();
        return null;
      }
      if (await source.next().timeout(timings.connectTimeout) == null) {
        throw const FormatException('Empty FLV upstream');
      }
      _scanning = true;
      final searchEnd = clock.now().add(timings.keyframeSearch);
      Uint8List? videoConfig;
      Uint8List? audioConfig;
      final audioBefore = ListQueue<Uint8List>();
      bool? aligned;
      int? alignedOffset;
      while (true) {
        final remaining = searchEnd.difference(clock.now());
        if (remaining <= Duration.zero) throw TimeoutException('No keyframe on the new connection');
        final tag = await source.next().timeout(remaining);
        if (_cancelled) {
          await source.cancel();
          return null;
        }
        if (tag == null) throw const FormatException('New connection ended before a keyframe');
        final type = FlvTag.type(tag);
        if (FlvTag.isVideoConfig(tag)) {
          videoConfig = tag;
          continue;
        }
        if (FlvTag.isAudioConfig(tag)) {
          audioConfig = tag;
          continue;
        }
        if (type == FlvTag.audio) {
          audioBefore.add(tag);
          if (audioBefore.length > 256) audioBefore.removeFirst();
          continue;
        }
        if (type != FlvTag.video) continue;
        final raw = FlvTag.timestamp(tag);
        if (aligned == null) {
          final delivered = _lastVideo;
          aligned = delivered == null || (raw - (delivered - _offset)).abs() <= timings.alignmentWindow.inMilliseconds;
          if (aligned) alignedOffset = _offset;
        }
        if (!FlvTag.isKeyframe(tag)) continue;
        if (aligned) {
          final delivered = _lastVideo;
          if (delivered != null && raw + alignedOffset! <= delivered) continue;
        }
        final candidate = _Candidate(next, source, tag, aligned: aligned)
          ..offset = alignedOffset ?? 0
          ..videoConfig = videoConfig
          ..audioConfig = audioConfig;
        candidate.audioBefore.addAll(audioBefore);
        return candidate;
      }
    } on Object catch (error) {
      if (source != null) unawaited(source.cancel());
      if (!_cancelled) _onEvent?.call(SpliceRenewFailed(error));
      return null;
    }
  }

  Future<void> _switchTo(_Candidate candidate) async {
    _ready = null;
    _handoverTimer?.cancel();
    final waited = candidate.readyAt == null ? Duration.zero : clock.now().difference(candidate.readyAt!);
    final old = _source;
    final pending = _pending;
    _pending = null;
    pending?.ignore();
    _source = candidate.source;
    if (old != null) unawaited(old.cancel());
    final oldEnded = _oldEnded;
    _oldEnded = false;

    final keyRaw = FlvTag.timestamp(candidate.keyframe);
    if (!candidate.aligned) {
      final delivered = _lastVideo;
      candidate.offset = delivered == null ? 0 : delivered + timings.shiftGap.inMilliseconds - keyRaw;
    }
    final offset = candidate.offset;
    _offset = offset;
    _line = candidate.line;
    _switches++;

    final lastAudio = _lastAudio;
    final audio = [
      for (final tag in candidate.audioBefore)
        if (lastAudio == null || FlvTag.timestamp(tag) + offset > lastAudio) tag,
    ];
    final firstTs = audio.isEmpty ? keyRaw : FlvTag.timestamp(audio.first);
    final videoConfig = candidate.videoConfig;
    if (videoConfig != null && (_videoConfig == null || !FlvTag.samePayload(videoConfig, _videoConfig!))) {
      _forward(FlvTag.withTimestamp(videoConfig, keyRaw), offset);
    }
    final audioConfig = candidate.audioConfig;
    if (audioConfig != null && (_audioConfig == null || !FlvTag.samePayload(audioConfig, _audioConfig!))) {
      _forward(FlvTag.withTimestamp(audioConfig, firstTs), offset);
    }
    for (final tag in audio) {
      _forward(tag, offset);
    }
    _forward(candidate.keyframe, offset);
    _onEvent?.call(
      SpliceSwitched(
        line: candidate.line,
        switchAt: keyRaw + offset,
        shifted: !candidate.aligned,
        oldEnded: oldEnded,
        waitedForOld: waited,
      ),
    );
    _scheduleRenewal();
  }

  void _forward(Uint8List tag, int offset) {
    final type = FlvTag.type(tag);
    if (type == FlvTag.script) {
      if (_switches == 0) _emit(tag);
      return;
    }
    final ts = FlvTag.timestamp(tag) + offset;
    if (ts < 0) return;
    if (FlvTag.isVideoConfig(tag)) {
      _videoConfig = tag;
    } else if (FlvTag.isAudioConfig(tag)) {
      _audioConfig = tag;
    } else if (type == FlvTag.video) {
      final last = _lastVideo;
      if (last != null && ts < last) return;
      _lastVideo = ts;
    } else if (type == FlvTag.audio) {
      final last = _lastAudio;
      if (last != null && ts <= last) return;
      _lastAudio = ts;
    }
    _emit(offset == 0 ? tag : FlvTag.withTimestamp(tag, ts));
  }

  Future<void> _teardown() async {
    _renewTimer?.cancel();
    _handoverTimer?.cancel();
    _holdTimer?.cancel();
    _held = null;
    final ready = _ready;
    _ready = null;
    final source = _source;
    _source = null;
    _pending?.ignore();
    _pending = null;
    _signal();
    await Future.wait([?ready?.source.cancel(), ?source?.cancel()]);
  }
}
