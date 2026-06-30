/// Exponential-backoff retry policy for the sync worker.
///
/// A row is retried while `retryCount < maxRetries`; the delay before attempt N grows as
/// `baseDelay * 2^N`, capped at [maxDelay].
class RetryPolicy {
  const RetryPolicy({
    this.maxRetries = 5,
    this.baseDelay = const Duration(seconds: 5),
    this.maxDelay = const Duration(minutes: 30),
  });

  final int maxRetries;
  final Duration baseDelay;
  final Duration maxDelay;

  Duration backoffFor(int retryCount) {
    if (retryCount <= 0) return baseDelay;
    final int factor = 1 << retryCount; // 2^retryCount; bounded since retryCount <= maxRetries
    final int ms = baseDelay.inMilliseconds * factor;
    final int capped = ms > maxDelay.inMilliseconds ? maxDelay.inMilliseconds : ms;
    return Duration(milliseconds: capped);
  }
}
