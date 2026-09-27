import 'package:meta/meta.dart';

/// CONN-3 reconnection: after failure number `n` (1-based, reset by any
/// received message) wait `base × (min(n ~/ endpoints, maxMultiplier − 1) + 1)`
/// and try the next endpoint; after [maxAttempts] retries give up.
///
/// With one endpoint the waits are 2, 3, 4, 5, 6, 6, 6, 6 s (Douyu §7.6);
/// with several, the next endpoint is tried after the base wait and the
/// wait grows once per full round.
@immutable
final class ReconnectPolicy {
  /// Creates the policy.
  const new({this.base = const Duration(seconds: 1), this.maxAttempts = 8, this.maxMultiplier = 6});

  /// Wait unit.
  final Duration base;

  /// Consecutive failed retries before the terminal state.
  final int maxAttempts;

  /// Largest multiple of [base].
  final int maxMultiplier;

  /// Wait before retry [failure] (1-based) over [endpoints] endpoints.
  Duration delay(int failure, int endpoints) {
    final rounds = failure ~/ (endpoints < 1 ? 1 : endpoints);
    final multiplier = (rounds < maxMultiplier - 1 ? rounds : maxMultiplier - 1) + 1;
    return base * multiplier;
  }

  /// Whether [failure] consecutive failures exhaust the retries.
  bool exhausted(int failure) => failure > maxAttempts;
}
