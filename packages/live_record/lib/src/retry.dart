import 'package:live_record/src/settings.dart';

/// Retry bookkeeping of one session (spec §11.4–§11.7). Pure: the session asks
/// for the next delay and sleeps itself.
final class RetryPolicy {
  /// Creates the policy for [settings].
  new(this.settings, {this.fastStart = const Duration(seconds: 2), this.fastCap = const Duration(seconds: 15)});

  /// Settings in force.
  RecordSettings settings;

  /// First fast reconnect delay.
  final Duration fastStart;

  /// Largest fast reconnect delay.
  final Duration fastCap;

  /// Delays of the same-URL retries after 5xx.
  static const sameUrlDelays = [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4)];

  /// Consecutive 4xx answers after which re-resolving backs off regularly.
  static const max4xx = 3;

  var _regular = 0;
  var _fast = 0;
  var _http4xx = 0;
  var _sameUrl = 0;

  /// Regular failures since the last healthy stretch.
  int get regularFailures => _regular;

  /// Fast reconnects since the last healthy stretch.
  int get fastAttempts => _fast;

  /// Consecutive 4xx answers.
  int get consecutive4xx => _http4xx;

  /// The next regular delay (§11.5): `retryDelay`, doubled per failure when
  /// `backoff` is on, capped at `maxCheckInterval`; null once `maxRetries`
  /// regular failures happened.
  Duration? regular() {
    _regular++;
    if (_regular > settings.maxRetries) return null;
    return regularDelay(settings, _regular);
  }

  /// The regular delay after [failures] failures in a row (also the polling interval rule, §12).
  static Duration regularDelay(RecordSettings settings, int failures, {Duration? base}) {
    final start = base ?? settings.retryDelay;
    if (!settings.backoff || failures <= 1) return start;
    final cap = settings.maxCheckInterval;
    var delay = start;
    for (var i = 1; i < failures; i++) {
      delay *= 2;
      if (delay >= cap) return cap;
    }
    return delay;
  }

  /// The next fast reconnect delay (§11.4): 2 s doubling to 15 s, never exhausted.
  Duration fast() {
    _fast++;
    var delay = fastStart;
    for (var i = 1; i < _fast; i++) {
      delay *= 2;
      if (delay >= fastCap) return fastCap;
    }
    return delay;
  }

  /// Counts a 4xx answer (§11.7) and returns how many came in a row.
  int http4xx() => ++_http4xx;

  /// The next same-URL retry delay after a 5xx, or null after three.
  Duration? sameUrl() {
    if (_sameUrl >= sameUrlDelays.length) {
      _sameUrl = 0;
      return null;
    }
    return sameUrlDelays[_sameUrl++];
  }

  /// A connection delivered media: per-connection counters start over.
  void connected() {
    _http4xx = 0;
    _sameUrl = 0;
  }

  /// At least 10 s of continuous media: every counter starts over (§3).
  void healthy() {
    _regular = 0;
    _fast = 0;
    _http4xx = 0;
    _sameUrl = 0;
  }
}
