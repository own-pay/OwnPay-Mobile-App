import 'package:flutter_test/flutter_test.dart';
import 'package:ownpay_console/features/sync/domain/queued_sms.dart';
import 'package:ownpay_console/features/sync/domain/retry_policy.dart';

void main() {
  QueuedSms item({SyncStatus status = SyncStatus.pending, int retry = 0}) => QueuedSms(
        localId: 1,
        encryptedPayload: 'ZW5j',
        sender: 'bKash',
        receivedAt: DateTime(2026, 6, 23, 10),
        createdAt: DateTime(2026, 6, 23, 10),
        status: status,
        retryCount: retry,
      );

  group('QueuedSms', () {
    test('isSyncable for pending and failed only', () {
      expect(item(status: SyncStatus.pending).isSyncable, isTrue);
      expect(item(status: SyncStatus.failed).isSyncable, isTrue);
      expect(item(status: SyncStatus.syncing).isSyncable, isFalse);
      expect(item(status: SyncStatus.approved).isSyncable, isFalse);
    });

    test('copyWith updates status/serverRef and bumps retry', () {
      final updated = item().copyWith(status: SyncStatus.approved, serverRef: 'sms_abc');
      expect(updated.status, SyncStatus.approved);
      expect(updated.serverRef, 'sms_abc');
      expect(updated.localId, 1);
    });

    test('map round-trip preserves fields', () {
      final original = item(status: SyncStatus.failed, retry: 2).copyWith(failureReason: 'timeout');
      final back = QueuedSms.fromMap(original.toMap());
      expect(back.status, SyncStatus.failed);
      expect(back.retryCount, 2);
      expect(back.failureReason, 'timeout');
      expect(back.encryptedPayload, 'ZW5j');
    });

    test('toApi sends only the wire fields (no plaintext, no local status)', () {
      final api = item().toApi();
      expect(api.keys, containsAll(<String>['local_id', 'encrypted_payload', 'sender', 'received_at']));
      expect(api.containsKey('status'), isFalse);
      expect(api.containsKey('body'), isFalse);
    });
  });

  group('RetryPolicy', () {
    const policy = RetryPolicy();

    test('canRetry until maxRetries', () {
      expect(policy.canRetry(0), isTrue);
      expect(policy.canRetry(4), isTrue);
      expect(policy.canRetry(5), isFalse);
      expect(policy.canRetry(6), isFalse);
    });

    test('backoff grows exponentially and is capped', () {
      expect(policy.backoffFor(0), const Duration(seconds: 5));
      expect(policy.backoffFor(1), const Duration(seconds: 10));
      expect(policy.backoffFor(2), const Duration(seconds: 20));
      expect(policy.backoffFor(3), const Duration(seconds: 40));
      // 5s * 2^10 = 5120s, capped to 30 min.
      expect(policy.backoffFor(10), const Duration(minutes: 30));
    });
  });
}
