import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/error/failure.dart';
import 'package:ownpay_console/core/network/api_client.dart';
import 'package:ownpay_console/core/network/api_result.dart';
import 'package:ownpay_console/core/storage/secure_store.dart';
import 'package:ownpay_console/features/sync/data/sync_worker.dart';
import 'package:ownpay_console/features/sync/domain/queued_sms.dart';
import 'package:ownpay_console/features/sync/domain/sms_queue_store.dart';
import 'package:ownpay_console/features/sync/domain/sync_health.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockSecureStore extends Mock implements SecureStore {}

/// Faithful in-memory [SmsQueueStore] mirroring the Hive impl's contract (verified separately in
/// hive_sms_queue_store_test.dart), so the worker can be tested without Hive.
class _FakeQueue implements SmsQueueStore {
  final List<QueuedSms> rows = <QueuedSms>[];
  int _id = 0;

  QueuedSms seed({
    SyncStatus status = SyncStatus.pending,
    int retry = 0,
    String payload = 'ENC',
  }) {
    final QueuedSms q = QueuedSms(
      localId: ++_id,
      encryptedPayload: payload,
      sender: 'bKash',
      receivedAt: DateTime(2026, 6, 23, 10),
      createdAt: DateTime(2026, 6, 23, 10),
      status: status,
      retryCount: retry,
    );
    rows.add(q);
    return q;
  }

  QueuedSms _byId(int id) => rows.firstWhere((QueuedSms q) => q.localId == id);
  void _replace(QueuedSms q) => rows[rows.indexWhere((QueuedSms r) => r.localId == q.localId)] = q;

  @override
  Future<QueuedSms> enqueue({
    required String encryptedPayload,
    required String sender,
    required DateTime receivedAt,
  }) async =>
      seed(payload: encryptedPayload);

  @override
  Future<List<QueuedSms>> all() async => List<QueuedSms>.unmodifiable(rows);

  @override
  Future<List<QueuedSms>> syncable({required int maxRetries, int limit = 50}) async {
    final List<QueuedSms> f = rows
        .where((QueuedSms q) => q.isSyncable && q.retryCount < maxRetries)
        .toList()
      ..sort((QueuedSms a, QueuedSms b) => a.localId.compareTo(b.localId));
    return f.length > limit ? f.sublist(0, limit) : f;
  }

  @override
  Future<void> markApproved(int localId, String? serverRef) async =>
      _replace(_byId(localId).copyWith(status: SyncStatus.approved, serverRef: serverRef));

  @override
  Future<void> markFailed(int localId, String reason) async {
    final QueuedSms r = _byId(localId);
    _replace(r.copyWith(status: SyncStatus.failed, failureReason: reason, retryCount: r.retryCount + 1));
  }

  @override
  Future<void> markReceivedWithIssue(int localId, String? serverRef, String reason) async =>
      _replace(_byId(localId).copyWith(
        status: SyncStatus.receivedWithIssue,
        serverRef: serverRef,
        failureReason: reason,
      ));

  @override
  Future<int> purgeApproved(DateTime olderThan) async {
    final int before = rows.length;
    rows.removeWhere((QueuedSms q) =>
        (q.status == SyncStatus.approved || q.status == SyncStatus.receivedWithIssue) &&
        q.createdAt.isBefore(olderThan));
    return before - rows.length;
  }

  @override
  Future<int> deleteFailed() async {
    final int before = rows.length;
    rows.removeWhere((QueuedSms q) =>
        q.status == SyncStatus.failed || q.status == SyncStatus.receivedWithIssue);
    return before - rows.length;
  }

  @override
  Future<int> resetFailedForRetry() async {
    int n = 0;
    for (int i = 0; i < rows.length; i++) {
      if (rows[i].status == SyncStatus.failed) {
        rows[i] = rows[i].copyWith(status: SyncStatus.pending, retryCount: 0);
        n++;
      }
    }
    return n;
  }
}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late _MockApiClient api;
  late _MockSecureStore store;
  late _FakeQueue queue;

  setUp(() {
    api = _MockApiClient();
    store = _MockSecureStore();
    queue = _FakeQueue();
    when(() => store.readServerUrl()).thenAnswer((_) async => 'https://srv.example');
  });

  Map<String, dynamic> accepted(int id) =>
      <String, dynamic>{'local_id': id, 'status': 'accepted', 'server_ref': 'ref_$id'};
  Map<String, dynamic> rejected(int id) => <String, dynamic>{'local_id': id, 'status': 'rejected'};
  Map<String, dynamic> duplicate(int id) =>
      <String, dynamic>{'local_id': id, 'status': 'duplicate', 'server_ref': null};

  ApiResult<Map<String, dynamic>> okResults(List<Map<String, dynamic>> results) =>
      Ok<Map<String, dynamic>>(<String, dynamic>{'results': results});

  void stubPost(ApiResult<Map<String, dynamic>> result) {
    when(() => api.post(any(), body: any(named: 'body'))).thenAnswer((_) async => result);
  }

  test('accepted results approve rows and draining continues across batches', () async {
    final QueuedSms a = queue.seed();
    final QueuedSms b = queue.seed();
    stubPost(okResults(<Map<String, dynamic>>[accepted(a.localId), accepted(b.localId)]));

    await SyncWorker(api, store, queue, batchSize: 1).syncNow();

    final List<QueuedSms> rows = await queue.all();
    expect(rows.every((QueuedSms q) => q.status == SyncStatus.approved), isTrue);
    expect(rows.firstWhere((QueuedSms q) => q.localId == a.localId).serverRef, 'ref_${a.localId}');
    verify(() => api.post(any(), body: any(named: 'body'))).called(2); // one POST per batch
  });

  test('a rejected row is marked failed (retry++)', () async {
    final QueuedSms a = queue.seed();
    final QueuedSms b = queue.seed();
    stubPost(okResults(<Map<String, dynamic>>[accepted(a.localId), rejected(b.localId)]));

    await SyncWorker(api, store, queue).syncNow();

    final List<QueuedSms> rows = await queue.all();
    expect(rows.firstWhere((QueuedSms q) => q.localId == a.localId).status, SyncStatus.approved);
    final QueuedSms bRow = rows.firstWhere((QueuedSms q) => q.localId == b.localId);
    expect(bRow.status, SyncStatus.failed);
    expect(bRow.retryCount, 1);
  });

  test('a server error fails the whole batch (retry++) and stops', () async {
    queue.seed();
    queue.seed();
    stubPost(const Err<Map<String, dynamic>>(ServerFailure()));

    await SyncWorker(api, store, queue).syncNow();

    final List<QueuedSms> rows = await queue.all();
    expect(rows.every((QueuedSms q) => q.status == SyncStatus.failed && q.retryCount == 1), isTrue);
    verify(() => api.post(any(), body: any(named: 'body'))).called(1);
  });

  test('an auth failure triggers re-pair and does NOT bump retry', () async {
    queue.seed();
    queue.seed();
    int reauth = 0;
    stubPost(const Err<Map<String, dynamic>>(AuthFailure()));

    await SyncWorker(api, store, queue, onReauthRequired: () => reauth++).syncNow();

    expect(reauth, 1);
    final List<QueuedSms> rows = await queue.all();
    expect(rows.every((QueuedSms q) => q.status == SyncStatus.pending && q.retryCount == 0), isTrue);
  });

  test('does nothing when the device is not paired', () async {
    when(() => store.readServerUrl()).thenAnswer((_) async => null);
    queue.seed();

    await SyncWorker(api, store, queue).syncNow();

    verifyNever(() => api.post(any(), body: any(named: 'body')));
  });

  test('the posted batch carries only the encrypted payload (no plaintext)', () async {
    queue.seed(payload: 'ENVELOPE_B64');
    stubPost(okResults(<Map<String, dynamic>>[accepted(1)]));

    await SyncWorker(api, store, queue).syncNow();

    final Map<String, dynamic> body =
        verify(() => api.post(any(), body: captureAny(named: 'body'))).captured.single as Map<String, dynamic>;
    final List<dynamic> messages = body['messages'] as List<dynamic>;
    final Map<String, dynamic> first = messages.first as Map<String, dynamic>;
    expect(first['encrypted_payload'], 'ENVELOPE_B64');
    expect(first.containsKey('body'), isFalse);
  });

  test('rows that exhausted maxRetries are not posted', () async {
    queue.seed(status: SyncStatus.failed, retry: 5);

    await SyncWorker(api, store, queue).syncNow();

    verifyNever(() => api.post(any(), body: any(named: 'body')));
  });

  test('a duplicate verdict is treated as success (approved), not retried forever', () async {
    final QueuedSms a = queue.seed();
    final QueuedSms b = queue.seed();
    // The server already has both (e.g. a retry after a lost response) → both come back "duplicate".
    stubPost(okResults(<Map<String, dynamic>>[duplicate(a.localId), duplicate(b.localId)]));

    await SyncWorker(api, store, queue, batchSize: 1).syncNow();

    final List<QueuedSms> rows = await queue.all();
    expect(rows.every((QueuedSms q) => q.status == SyncStatus.approved), isTrue);
    expect(rows.every((QueuedSms q) => q.retryCount == 0), isTrue); // never marked failed
    verify(() => api.post(any(), body: any(named: 'body'))).called(2); // drains across batches
  });

  test('server rejection error codes are retained in the failed queue reason', () async {
    final QueuedSms row = queue.seed();
    stubPost(okResults(<Map<String, dynamic>>[
      <String, dynamic>{
        'local_id': row.localId,
        'status': 'rejected',
        'error': 'DEVICE_NOT_FOUND',
      },
    ]));

    await SyncWorker(api, store, queue).syncNow();

    expect((await queue.all()).single.failureReason, 'rejected: DEVICE_NOT_FOUND');
  });

  test('accepted processing errors become terminal review rows, not retries', () async {
    final QueuedSms row = queue.seed();
    stubPost(okResults(<Map<String, dynamic>>[
      <String, dynamic>{
        'local_id': row.localId,
        'status': 'accepted',
        'server_ref': 'sms_1',
        'error': 'DECRYPTION_FAILED',
      },
    ]));
    final SyncWorker worker = SyncWorker(api, store, queue);

    await worker.syncNow();

    final QueuedSms stored = (await queue.all()).single;
    expect(stored.status, SyncStatus.receivedWithIssue);
    expect(stored.retryCount, 0);
    expect(stored.serverRef, 'sms_1');
    expect(stored.failureReason, 'accepted: DECRYPTION_FAILED');
    expect(worker.health.value.status, SyncHealthStatus.receivedWithIssue);
    expect(worker.health.value.queuedCount, 0);
    verify(() => api.post(any(), body: any(named: 'body'))).called(1);
  });

  test('successful delivery publishes a confirmed health snapshot', () async {
    final QueuedSms row = queue.seed();
    stubPost(okResults(<Map<String, dynamic>>[accepted(row.localId)]));
    final SyncWorker worker = SyncWorker(api, store, queue);

    await worker.syncNow();

    expect(worker.health.value.status, SyncHealthStatus.synced);
    expect(worker.health.value.message, 'SMS delivery confirmed by OwnPay.');
  });

  test('health counts include pending rows outside the failed batch', () async {
    queue.seed();
    queue.seed();
    final SyncWorker worker = SyncWorker(api, store, queue, batchSize: 1);
    stubPost(const Err<Map<String, dynamic>>(ServerFailure()));

    await worker.syncNow();

    expect(worker.health.value.status, SyncHealthStatus.failed);
    expect(worker.health.value.queuedCount, 2);
    expect(worker.health.value.failedCount, 1);
  });

  test('after a retryable failure the worker backs off — an early retry is skipped, a later one runs', () async {
    queue.seed();
    DateTime now = DateTime(2026, 6, 28, 12, 0, 0);
    final SyncWorker worker = SyncWorker(api, store, queue, now: () => now);

    // First attempt fails → row failed (retry 1) and a ~10s backoff (backoffFor(1)) is armed.
    stubPost(const Err<Map<String, dynamic>>(ServerFailure()));
    await worker.syncNow();
    expect((await queue.all()).single.retryCount, 1);
    expect(worker.health.value.status, SyncHealthStatus.failed);
    expect(worker.health.value.queuedCount, 1);
    expect(worker.health.value.failedCount, 1);
    verify(() => api.post(any(), body: any(named: 'body'))).called(1);
    clearInteractions(api);

    // A trigger that fires inside the backoff window must NOT re-post.
    now = now.add(const Duration(seconds: 3));
    await worker.syncNow();
    verifyNever(() => api.post(any(), body: any(named: 'body')));
    clearInteractions(api);

    // Past the backoff, the next trigger retries — and this time the server accepts.
    now = now.add(const Duration(seconds: 30));
    stubPost(okResults(<Map<String, dynamic>>[accepted(1)]));
    await worker.syncNow();
    verify(() => api.post(any(), body: any(named: 'body'))).called(1);
    expect((await queue.all()).single.status, SyncStatus.approved);
  });
}
