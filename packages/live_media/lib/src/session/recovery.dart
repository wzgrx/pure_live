import 'package:live_media/src/session/playback_state.dart';
import 'package:meta/meta.dart';

/// One step of the recovery chain (REC-1).
@immutable
sealed class RecoveryStep {
  const new();
}

/// Resolve fresh URLs and reopen (REC-1 step 1): the first attempt keeps the
/// line and may use an unexpired prefetch, the second moves to the next line.
final class RefreshStep extends RecoveryStep {
  /// Creates the step.
  const new({required this.nextLine, required this.usePrefetch});

  /// Move to the next line.
  final bool nextLine;

  /// Prefer the prefetched line.
  final bool usePrefetch;

  @override
  String toString() => 'refresh${nextLine ? ' next line' : ''}${usePrefetch ? ' (prefetch)' : ''}';
}

/// Mark the current line failed and open the next one (REC-1 step 2).
final class SwitchLineStep extends RecoveryStep {
  /// Creates the step.
  const new();

  @override
  String toString() => 'switch line';
}

/// Reopen the same source on the same engine (REC-1 step 3).
final class RebuildStep extends RecoveryStep {
  /// Creates the step.
  const new();

  @override
  String toString() => 'rebuild';
}

/// Reopen the same URL with software video decoding (REC-1 step 4).
final class SoftwareDecodeStep extends RecoveryStep {
  /// Creates the step.
  const new();

  @override
  String toString() => 'software decode';
}

/// Wait, then refresh and reopen (REC-1 step 5).
final class BackoffStep extends RecoveryStep {
  /// Creates the step.
  const new(this.delay);

  /// Wait.
  final Duration delay;

  @override
  String toString() => 'backoff ${delay.inMilliseconds}ms';
}

/// Give up and show the error (REC-1 step 6).
final class GiveUpStep extends RecoveryStep {
  /// Creates the step.
  const new();

  @override
  String toString() => 'give up';
}

/// Attempt counts of the current recovery round and the round history (REC-2).
///
/// A round starts at the first failure and ends after continuous healthy
/// play ([endRound]); at most `maxRounds` rounds may start in any window.
final class RecoveryLedger {
  /// Refreshes in this round (at most 2).
  int refreshes = 0;

  /// Rebuilds in this round (at most 1).
  int rebuilds = 0;

  /// Backoff rounds used in this round.
  int backoffs = 0;

  /// URLs already retried with software decoding (once per URL).
  final Set<Uri> softwareTried = {};

  final List<DateTime> _roundStarts = [];
  DateTime? _roundStartedAt;

  /// Whether a round is open.
  bool get inRound => _roundStartedAt != null;

  /// Round start times still inside the window, oldest first.
  List<DateTime> get roundStarts => List.unmodifiable(_roundStarts);

  /// Opens a round at [now] unless [maxRounds] already started within
  /// [window]; returns false when recovery must give up.
  bool startRound(DateTime now, {required Duration window, required int maxRounds}) {
    _roundStarts.removeWhere((start) => now.difference(start) >= window);
    if (_roundStarts.length >= maxRounds) return false;
    _roundStarts.add(now);
    _roundStartedAt = now;
    return true;
  }

  /// Ends the round after healthy play: counts reset, history stays.
  void endRound() {
    refreshes = 0;
    rebuilds = 0;
    backoffs = 0;
    softwareTried.clear();
    _roundStartedAt = null;
  }

  /// A backoff round resets the refresh and rebuild counts (REC-1 step 5).
  void startBackoff() {
    backoffs++;
    refreshes = 0;
    rebuilds = 0;
  }

  /// Clears everything (manual retry REC-6, room change REC-7).
  void clear() {
    endRound();
    _roundStarts.clear();
  }
}

/// The next step for [failure] (REC-1), given what this round already tried.
///
/// - [canRefresh]: the platform can resolve fresh URLs.
/// - [hasSpareLine]: another line at this quality has not failed this round.
/// - [softwareTried]: the current URL already had its software-decoding retry.
/// - [continuousLive]: backoff only applies to live streams (SES-11).
RecoveryStep nextRecoveryStep(
  PlaybackFailure failure,
  RecoveryLedger ledger, {
  required bool canRefresh,
  required bool hasSpareLine,
  required bool softwareTried,
  required bool continuousLive,
  required List<Duration> backoff,
}) {
  final kind = failure.kind;
  if (kind == FailureKind.unavailable || kind == FailureKind.exhausted) return const GiveUpStep();
  if (kind.transport && canRefresh && ledger.refreshes < 2) {
    return RefreshStep(nextLine: ledger.refreshes == 1 && hasSpareLine, usePrefetch: ledger.refreshes == 0);
  }
  if ((kind.transport || kind == FailureKind.frameStall) && hasSpareLine) return const SwitchLineStep();
  if (kind.stall && ledger.rebuilds < 1) return const RebuildStep();
  if (kind == FailureKind.videoDecode && !softwareTried) return const SoftwareDecodeStep();
  if (kind.transport && continuousLive && ledger.backoffs < backoff.length) {
    return BackoffStep(backoff[ledger.backoffs]);
  }
  return const GiveUpStep();
}
