import 'package:flutter_test/flutter_test.dart';
import 'package:ownpay_console/features/audit/domain/audit_entry.dart';
import 'package:ownpay_console/features/audit/presentation/audit_cubit.dart';
import 'package:ownpay_console/features/sync/domain/queued_sms.dart';

import 'audit_fakes.dart';

void main() {
  late FakeSmsQueueStore queue;
  late FakeSyncer sync;

  setUp(() {
    queue = FakeSmsQueueStore();
    sync = FakeSyncer();
  });

  AuditCubit build() => AuditCubit(queue, sync, FakeSmsBodyRevealer());

  test('load maps rows to entries (newest first) and clears loading', () async {
    queue.seed(sender: 'bKash', status: SyncStatus.approved); // id 1
    queue.seed(sender: 'Nagad', status: SyncStatus.failed, failureReason: 'timeout'); // id 2
    final AuditCubit cubit = build();

    await cubit.load();

    expect(cubit.state.loading, isFalse);
    expect(cubit.state.entries.map((AuditEntry e) => e.localId), <int>[2, 1]);
    expect(cubit.state.entries.first.sender, 'Nagad');
  });

  test('visible filters by All / Synced / Issues', () async {
    queue.seed(status: SyncStatus.approved);
    queue.seed(status: SyncStatus.failed);
    queue.seed(status: SyncStatus.receivedWithIssue);
    queue.seed(status: SyncStatus.pending);
    final AuditCubit cubit = build();
    await cubit.load();

    expect(cubit.state.visible, hasLength(4)); // All (default)

    cubit.setFilter(AuditFilter.synced);
    expect(cubit.state.visible, hasLength(1));
    expect(cubit.state.visible.single.isSynced, isTrue);

    cubit.setFilter(AuditFilter.issues);
    expect(cubit.state.visible.single.isIssue, isTrue);
  });

  test('failedCount counts retryable failures and received-with-issue entries', () async {
    queue.seed(status: SyncStatus.failed);
    queue.seed(status: SyncStatus.failed);
    queue.seed(status: SyncStatus.receivedWithIssue);
    queue.seed(status: SyncStatus.approved);
    final AuditCubit cubit = build();

    await cubit.load();

    expect(cubit.state.failedCount, 3);
  });

  test('clearFailed removes failed and received-with-issue rows and reloads', () async {
    queue.seed(status: SyncStatus.approved);
    queue.seed(status: SyncStatus.failed);
    queue.seed(status: SyncStatus.receivedWithIssue);
    final AuditCubit cubit = build();
    await cubit.load();

    await cubit.clearFailed();

    expect(cubit.state.entries.any((AuditEntry e) => e.isIssue), isFalse);
    expect(cubit.state.entries, hasLength(1)); // the synced row remains
  });

  test('retryNow triggers a sync then reloads', () async {
    queue.seed(status: SyncStatus.failed);
    final AuditCubit cubit = build();
    await cubit.load();

    await cubit.retryNow();

    expect(sync.syncCalls, 1);
  });

  test('retryNow revives an exhausted failed row (reset to pending) so it can sync again', () async {
    final QueuedSms failed = queue.seed(status: SyncStatus.failed, retry: 5); // had exhausted auto-retries
    final AuditCubit cubit = build();
    await cubit.load();

    await cubit.retryNow();

    expect(sync.syncCalls, 1);
    expect(sync.lastForce, isTrue); // user-initiated retry bypasses the backoff window
    final QueuedSms row = queue.rows.firstWhere((QueuedSms q) => q.localId == failed.localId);
    expect(row.status, SyncStatus.pending);
    expect(row.retryCount, 0);
  });
}
