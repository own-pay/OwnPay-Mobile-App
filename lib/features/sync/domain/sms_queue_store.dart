import 'queued_sms.dart';

/// Durable outbound queue of gate-passed, **encrypted** SMS awaiting sync to the server.
///
/// Only the AES-GCM envelope is stored — never the plaintext body (see [QueuedSms]). The sync worker
/// (increment 6) consumes these rows; this increment only needs to enqueue them.
abstract interface class SmsQueueStore {
  /// Persists a new gate-passed message with `status = pending`, assigning a unique local id, and
  /// returns the stored row.
  Future<QueuedSms> enqueue({
    required String encryptedPayload,
    required String sender,
    required DateTime receivedAt,
  });

  /// All queued rows (any status). Primarily for inspection/audit; the sync worker selects by status.
  Future<List<QueuedSms>> all();

  /// Rows eligible for a sync attempt — status `pending`/`failed` AND `retryCount < maxRetries` —
  /// oldest first (ascending local id), capped at [limit].
  Future<List<QueuedSms>> syncable({required int maxRetries, int limit});

  /// Marks the row accepted by the server (`approved`, recording the optional server reference).
  Future<void> markApproved(int localId, String? serverRef);

  /// Records a failed sync attempt: `status = failed`, `retryCount++`, and the non-sensitive [reason].
  Future<void> markFailed(int localId, String reason);

  /// Records that OwnPay received and persisted the SMS but reported a processing warning. This is
  /// terminal for mobile delivery: it must not be retried or counted as a transport failure.
  Future<void> markReceivedWithIssue(int localId, String? serverRef, String reason);

  /// Deletes `approved` and `receivedWithIssue` rows created before [olderThan] (retention cleanup).
  /// Returns the count removed.
  Future<int> purgeApproved(DateTime olderThan);

  /// Deletes every row currently in the `failed` or `receivedWithIssue` state (the user's "clear issues"
  /// action). Returns count.
  Future<int> deleteFailed();

  /// Resets every `failed` row back to `pending` with `retryCount = 0` (and clears its failure reason),
  /// so a user-initiated "retry now" re-attempts even rows that had exhausted their automatic retries.
  /// Returns the number of rows reset. Auto-retry stays bounded by `maxRetries`; only this explicit user
  /// action revives an exhausted row (the server dedupes already-delivered messages, so this is safe).
  Future<int> resetFailedForRetry();
}
