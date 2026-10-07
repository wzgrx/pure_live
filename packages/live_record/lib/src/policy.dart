/// Retry, polling and lease timing of the recorder (3.x
/// `RecorderContinuationPolicy`, unchanged rules).
abstract final class RecordPolicy {
  /// Delay of the next live check: [baseSeconds], doubled per failure up to
  /// [maximumSeconds] with [enableBackoff].
  static Duration pollingDelay({
    required int failureCount,
    required int baseSeconds,
    required int maximumSeconds,
    required bool enableBackoff,
  }) {
    final base = baseSeconds.clamp(1, 86400);
    final maximum = maximumSeconds.clamp(base, 86400);
    if (!enableBackoff || failureCount <= 0) return Duration(seconds: base);
    final exponent = failureCount.clamp(0, 20);
    return Duration(seconds: (base * (1 << exponent)).clamp(base, maximum));
  }

  /// Delay of a reconnect. A live EOF or an expired URL ([unexpectedEof])
  /// retries after 2 s (at most 15 s with backoff) instead of the configured
  /// delay: the room is likely still live and only needs a fresh URL.
  static Duration reconnectDelay({
    required int failureCount,
    required int configuredBaseSeconds,
    required int configuredMaximumSeconds,
    required bool enableBackoff,
    required bool unexpectedEof,
  }) => pollingDelay(
    failureCount: failureCount,
    baseSeconds: unexpectedEof ? 2 : configuredBaseSeconds,
    maximumSeconds: unexpectedEof ? 15 : configuredMaximumSeconds,
    enableBackoff: enableBackoff,
  );

  /// Whether retries are used up and the task should wait for the room
  /// again. A live EOF (or 403/404) is retried quickly, but a streamer who
  /// ended the broadcast keeps causing them: they get twice the budget
  /// (upstream pure_live 2b9ffc7a3) instead of an unlimited one.
  static bool shouldEnterPollingAfterRetryLimit({
    required int retryCount,
    required int maximumRetries,
    required bool unexpectedEof,
  }) {
    final limit = maximumRetries.clamp(1, 100);
    return retryCount >= (unexpectedEof ? limit * 2 : limit);
  }

  /// When to fetch the next URL before a lease's [refreshAt]: [lead]
  /// earlier, immediately when already late (after sleep or resume).
  static Duration leasePrefetchDelay({
    required DateTime now,
    required DateTime refreshAt,
    Duration lead = const Duration(seconds: 5),
  }) {
    final remaining = refreshAt.toUtc().difference(now.toUtc()) - lead;
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  /// When to keep the next URL ready again: the next lease's prefetch time,
  /// at least 30 s (failed or stale metadata is rate limited).
  static Duration leaseMaintenanceDelay({required DateTime now, required DateTime? refreshAt}) {
    const minimum = Duration(seconds: 30);
    final remaining = refreshAt == null ? minimum : leasePrefetchDelay(now: now, refreshAt: refreshAt);
    return remaining > minimum ? remaining : minimum;
  }
}
