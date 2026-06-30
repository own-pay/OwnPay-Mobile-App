/// Triggers a sync of the offline queue to the server. Implemented by the data-layer `SyncWorker`;
/// depended on by presentation (the audit screen's "retry now") so it stays off the concrete worker.
abstract interface class Syncer {
  /// Triggers a sync of the offline queue. [force] clears any active backoff window, so a user-initiated
  /// "retry now" runs immediately even right after a failure (automatic triggers leave [force] false and
  /// continue to honor the backoff).
  Future<void> syncNow({bool force = false});
}
