import 'package:ownpay_console/features/audit/data/sms_body_revealer.dart';
import 'package:ownpay_console/features/sync/domain/queued_sms.dart';
import 'package:ownpay_console/features/sync/domain/sms_queue_store.dart';
import 'package:ownpay_console/features/sync/domain/syncer.dart';

/// In-memory [SmsQueueStore] for audit tests — faithful to the contract (mirrors the Hive impl, which
/// is tested separately), with a `seed` helper for arranging rows.
class FakeSmsQueueStore implements SmsQueueStore {
  final List<QueuedSms> rows = <QueuedSms>[];
  int _id = 0;

  QueuedSms seed({
    SyncStatus status = SyncStatus.pending,
    String sender = 'bKash',
    String? failureReason,
    String? serverRef,
    int retry = 0,
    String payload = 'ENC',
  }) {
    final QueuedSms q = QueuedSms(
      localId: ++_id,
      encryptedPayload: payload,
      sender: sender,
      receivedAt: DateTime(2026, 6, 23, 10, _id),
      createdAt: DateTime(2026, 6, 23, 10),
      status: status,
      failureReason: failureReason,
      serverRef: serverRef,
      retryCount: retry,
    );
    rows.add(q);
    return q;
  }

  @override
  Future<QueuedSms> enqueue({
    required String encryptedPayload,
    required String sender,
    required DateTime receivedAt,
  }) async =>
      seed(payload: encryptedPayload, sender: sender);

  @override
  Future<List<QueuedSms>> all() async => List<QueuedSms>.unmodifiable(rows);

  @override
  Future<List<QueuedSms>> syncable({required int maxRetries, int limit = 50}) async =>
      rows.where((QueuedSms q) => q.isSyncable && q.retryCount < maxRetries).toList();

  @override
  Future<void> markApproved(int localId, String? serverRef) async => _replace(
        rows.firstWhere((QueuedSms q) => q.localId == localId).copyWith(
              status: SyncStatus.approved,
              serverRef: serverRef,
            ),
      );

  @override
  Future<void> markFailed(int localId, String reason) async {
    final QueuedSms r = rows.firstWhere((QueuedSms q) => q.localId == localId);
    _replace(r.copyWith(status: SyncStatus.failed, failureReason: reason, retryCount: r.retryCount + 1));
  }

  @override
  Future<int> purgeApproved(DateTime olderThan) async {
    final int before = rows.length;
    rows.removeWhere((QueuedSms q) => q.status == SyncStatus.approved && q.createdAt.isBefore(olderThan));
    return before - rows.length;
  }

  @override
  Future<int> deleteFailed() async {
    final int before = rows.length;
    rows.removeWhere((QueuedSms q) => q.status == SyncStatus.failed);
    return before - rows.length;
  }

  @override
  Future<int> resetFailedForRetry() async {
    int n = 0;
    for (int i = 0; i < rows.length; i++) {
      if (rows[i].status == SyncStatus.failed) {
        rows[i] = QueuedSms(
          localId: rows[i].localId,
          encryptedPayload: rows[i].encryptedPayload,
          sender: rows[i].sender,
          receivedAt: rows[i].receivedAt,
          createdAt: rows[i].createdAt,
        );
        n++;
      }
    }
    return n;
  }

  void _replace(QueuedSms q) => rows[rows.indexWhere((QueuedSms r) => r.localId == q.localId)] = q;
}

/// Test double for [SmsBodyRevealer] — returns a canned body (or null) without touching crypto.
class FakeSmsBodyRevealer implements SmsBodyRevealer {
  FakeSmsBodyRevealer([this.result]);

  final String? result;

  @override
  Future<String?> reveal(int localId) async => result;
}

/// Records calls to [syncNow] so tests can assert "retry now" wired through.
class FakeSyncer implements Syncer {
  int syncCalls = 0;
  bool lastForce = false;

  @override
  Future<void> syncNow({bool force = false}) async {
    lastForce = force;
    syncCalls++;
  }
}
