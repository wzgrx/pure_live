import 'dart:async';

import 'package:live_net/src/live_http.dart';
import 'package:live_net/src/request.dart';
import 'package:live_net/src/response.dart';

/// Serialises requests per platform with a minimum interval between starts
/// (ADR 0011, rule 6); platforms without an interval pass straight through.
final class ThrottledHttp implements LiveHttp {
  /// Wraps [inner]; [now] and [sleep] are injectable for tests.
  new(this.inner, {required this.minIntervals, DateTime Function()? now, Future<void> Function(Duration)? sleep})
    : _now = now ?? DateTime.now,
      _sleep = sleep ?? Future<void>.delayed;

  /// The transport doing the work.
  final LiveHttp inner;

  /// Minimum gap between request starts, by platform id.
  final Map<String, Duration> minIntervals;

  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;
  final Map<String, Future<void>> _tails = {};
  final Map<String, DateTime> _lastStart = {};

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    final interval = minIntervals[request.site];
    if (interval == null) return await inner.send(request);
    final previous = _tails[request.site] ?? Future<void>.value();
    final turn = Completer<void>();
    _tails[request.site] = turn.future;
    try {
      await previous;
      final last = _lastStart[request.site];
      if (last != null) {
        final wait = last.add(interval).difference(_now());
        if (wait > Duration.zero) await _sleep(wait);
      }
      _lastStart[request.site] = _now();
    } finally {
      turn.complete();
    }
    return await inner.send(request);
  }

  @override
  void close() => inner.close();
}
