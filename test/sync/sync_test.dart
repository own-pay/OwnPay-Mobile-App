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
      expect(item(status: SyncStatus.approved).isSyncable, isFalse);
    });

    test('status serializes by name (order-independent), not by index', () {
      expect(item(status: SyncStatus.failed).toMap()['status'], 'failed');
      expect(item(status: SyncStatus.approved).toMap()['status'], 'approved');
      expect(QueuedSms.fromMap(item(status: SyncStatus.approved).toMap()).status, SyncStatus.approved);
      // Unknown/garbled stored status falls back to pending (re-synced, never lost).
      final Map<String, dynamic> corrupt = item().toMap()..['status'] = 'bogus';
      expect(QueuedSms.fromMap(corrupt).status, SyncStatus.pending);
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

    test('toApi serializes received_at as UTC (unambiguous Z) for the wire', () {
      final api = item().toApi();
      expect(api['received_at'], endsWith('Z'));
      // Same instant, just unambiguous — the server gets a timezone, not a naive local time.
      expect(DateTime.parse(api['received_at'] as String), DateTime(2026, 6, 23, 10).toUtc());
    });
  });

  group('RetryPolicy', () {
    const policy = RetryPolicy();

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
