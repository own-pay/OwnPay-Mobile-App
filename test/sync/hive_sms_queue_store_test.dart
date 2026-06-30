import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ownpay_console/core/config/app_config.dart';
import 'package:ownpay_console/features/sync/data/hive_sms_queue_store.dart';
import 'package:ownpay_console/features/sync/domain/queued_sms.dart';

/// Exercises the real Hive-backed store (the inc-6 status/retry/purge logic) against a temporary box.
/// Uses `Hive.init(<temp dir>)` (not `initFlutter`) so it runs on the Dart VM without platform plugins.
void main() {
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('ownpay_hive_queue');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    final Box<Object> box = await Hive.openBox<Object>(AppConfig.boxSmsQueue);
    await box.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // Best-effort temp cleanup; a lingering handle on Windows must not fail the suite.
    }
  });

  Future<QueuedSms> enqueue(HiveSmsQueueStore store, {String payload = 'enc', String sender = 'bKash'}) =>
      store.enqueue(encryptedPayload: payload, sender: sender, receivedAt: DateTime(2026, 6, 23, 10));

  test('enqueue assigns sequential ids and stores rows as pending', () async {
    final HiveSmsQueueStore store = HiveSmsQueueStore();

    final QueuedSms a = await enqueue(store, payload: 'e1');
    final QueuedSms b = await enqueue(store, payload: 'e2');

    expect(a.localId, 1);
    expect(b.localId, 2);
    expect(a.status, SyncStatus.pending);
    expect((await store.all()), hasLength(2));
  });

  test('syncable returns pending + retryable-failed, oldest first, excluding approved', () async {
    final HiveSmsQueueStore store = HiveSmsQueueStore();
    final QueuedSms a = await enqueue(store); // pending
    final QueuedSms b = await enqueue(store); // → approved (excluded)
    final QueuedSms c = await enqueue(store); // → failed, retry 1 (included)
    await store.markApproved(b.localId, 'ref');
    await store.markFailed(c.localId, 'timeout');

    final List<QueuedSms> rows = await store.syncable(maxRetries: 5, limit: 50);

    expect(rows.map((QueuedSms q) => q.localId), <int>[a.localId, c.localId]);
  });

  test('syncable honours the limit', () async {
    final HiveSmsQueueStore store = HiveSmsQueueStore();
    await enqueue(store);
    await enqueue(store);
    await enqueue(store);

    expect(await store.syncable(maxRetries: 5, limit: 2), hasLength(2));
  });

  test('markApproved sets status + serverRef', () async {
    final HiveSmsQueueStore store = HiveSmsQueueStore();
    final QueuedSms a = await enqueue(store);

    await store.markApproved(a.localId, 'sms_ref_1');

    final QueuedSms row = (await store.all()).single;
    expect(row.status, SyncStatus.approved);
    expect(row.serverRef, 'sms_ref_1');
  });

  test('markFailed flips to failed and increments retry each time', () async {
    final HiveSmsQueueStore store = HiveSmsQueueStore();
    final QueuedSms a = await enqueue(store);

    await store.markFailed(a.localId, 'server 500');
    QueuedSms row = (await store.all()).single;
    expect(row.status, SyncStatus.failed);
    expect(row.retryCount, 1);
    expect(row.failureReason, 'server 500');

    await store.markFailed(a.localId, 'again');
    row = (await store.all()).single;
    expect(row.retryCount, 2);
  });

  test('a row that exhausted maxRetries is no longer syncable', () async {
    final HiveSmsQueueStore store = HiveSmsQueueStore();
    final QueuedSms a = await enqueue(store);
    for (int i = 0; i < 5; i++) {
      await store.markFailed(a.localId, 'x');
    }

    expect(await store.syncable(maxRetries: 5, limit: 50), isEmpty);
  });

  test('purgeApproved deletes only approved rows older than the cutoff', () async {
    DateTime clock = DateTime(2026, 6, 1);
    final HiveSmsQueueStore store = HiveSmsQueueStore(() => clock);

    final QueuedSms old = await enqueue(store); // createdAt 2026-06-01
    clock = DateTime(2026, 6, 10);
    final QueuedSms recent = await enqueue(store); // createdAt 2026-06-10
    final QueuedSms pending = await enqueue(store); // createdAt 2026-06-10, stays pending
    await store.markApproved(old.localId, null);
    await store.markApproved(recent.localId, null);

    final int removed = await store.purgeApproved(DateTime(2026, 6, 5));

    expect(removed, 1); // only the old approved row
    final List<int> remaining = (await store.all()).map((QueuedSms q) => q.localId).toList()..sort();
    expect(remaining, <int>[recent.localId, pending.localId]);
  });

  test('deleteFailed removes only failed rows', () async {
    final HiveSmsQueueStore store = HiveSmsQueueStore();
    final QueuedSms a = await enqueue(store);
    final QueuedSms b = await enqueue(store);
    await store.markFailed(a.localId, 'timeout');
    await store.markApproved(b.localId, 'ref');

    final int removed = await store.deleteFailed();

    expect(removed, 1);
    expect((await store.all()).map((QueuedSms q) => q.localId), <int>[b.localId]);
  });

  test('resetFailedForRetry revives failed rows to pending (retry 0); leaves others untouched', () async {
    final HiveSmsQueueStore store = HiveSmsQueueStore();
    final QueuedSms a = await enqueue(store); // → failed twice (exhausted-ish)
    final QueuedSms b = await enqueue(store); // stays pending
    final QueuedSms c = await enqueue(store); // → approved (untouched)
    await store.markFailed(a.localId, 'server 500');
    await store.markFailed(a.localId, 'server 500');
    await store.markApproved(c.localId, 'ref');

    final int reset = await store.resetFailedForRetry();

    expect(reset, 1);
    final Map<int, QueuedSms> byId = <int, QueuedSms>{
      for (final QueuedSms q in await store.all()) q.localId: q,
    };
    expect(byId[a.localId]!.status, SyncStatus.pending);
    expect(byId[a.localId]!.retryCount, 0);
    expect(byId[a.localId]!.failureReason, isNull);
    expect(byId[b.localId]!.status, SyncStatus.pending); // unchanged
    expect(byId[c.localId]!.status, SyncStatus.approved); // unchanged
    // The revived row is syncable again even though it had failed.
    expect(
      (await store.syncable(maxRetries: 5, limit: 50)).map((QueuedSms q) => q.localId),
      containsAll(<int>[a.localId, b.localId]),
    );
  });

  test('rows persist across store instances and ids continue from the max', () async {
    await enqueue(HiveSmsQueueStore(), payload: 'e1');

    final HiveSmsQueueStore reopened = HiveSmsQueueStore();
    expect(await reopened.all(), hasLength(1));
    final QueuedSms next = await enqueue(reopened, payload: 'e2');
    expect(next.localId, 2);
  });
}
