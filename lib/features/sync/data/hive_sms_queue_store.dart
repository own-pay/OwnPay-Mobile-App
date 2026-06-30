import 'package:hive/hive.dart';

import '../../../core/config/app_config.dart';
import '../domain/queued_sms.dart';
import '../domain/sms_queue_store.dart';

/// Hive-backed [SmsQueueStore] (box `AppConfig.boxSmsQueue`).
///
/// Each row is keyed by its `localId` (a monotonic int) and stored as a primitives-only map
/// ([QueuedSms.toMap]) — no codegen/type adapters, and **encrypted payload only** (never plaintext).
/// The box is opened lazily and cached; `Hive.initFlutter()` must have run first (done in `main`).
class HiveSmsQueueStore implements SmsQueueStore {
  HiveSmsQueueStore([this._now = DateTime.now]);

  final DateTime Function() _now;

  Box<Object>? _cached;
  int? _nextId;

  Future<Box<Object>> _openBox() async =>
      _cached ??= await Hive.openBox<Object>(AppConfig.boxSmsQueue);

  /// Allocates the next local id. Seeded from the highest existing key so ids stay unique across app
  /// restarts; advanced in memory thereafter. Enqueue is serialized by the single ingest coordinator,
  /// so this needs no cross-isolate locking.
  int _allocId(Box<Object> box) {
    if (_nextId == null) {
      int maxId = 0;
      for (final Object? key in box.keys) {
        if (key is int && key > maxId) {
          maxId = key;
        }
      }
      _nextId = maxId + 1;
    }
    final int id = _nextId!;
    _nextId = id + 1;
    return id;
  }

  @override
  Future<QueuedSms> enqueue({
    required String encryptedPayload,
    required String sender,
    required DateTime receivedAt,
  }) async {
    final Box<Object> box = await _openBox();
    final int id = _allocId(box);
    final QueuedSms item = QueuedSms(
      localId: id,
      encryptedPayload: encryptedPayload,
      sender: sender,
      receivedAt: receivedAt,
      createdAt: _now(),
    );
    await box.put(id, item.toMap());
    return item;
  }

  @override
  Future<List<QueuedSms>> all() async {
    final Box<Object> box = await _openBox();
    final List<QueuedSms> out = <QueuedSms>[];
    for (final Object? value in box.values) {
      final QueuedSms? row = _decode(value);
      if (row != null) {
        out.add(row);
      }
    }
    return out;
  }

  @override
  Future<List<QueuedSms>> syncable({required int maxRetries, int limit = 50}) async {
    final List<QueuedSms> rows = (await all())
        .where((QueuedSms q) => q.isSyncable && q.retryCount < maxRetries)
        .toList()
      ..sort((QueuedSms a, QueuedSms b) => a.localId.compareTo(b.localId)); // oldest first
    return rows.length > limit ? rows.sublist(0, limit) : rows;
  }

  @override
  Future<void> markApproved(int localId, String? serverRef) async {
    await _update(localId, (QueuedSms row) =>
        row.copyWith(status: SyncStatus.approved, serverRef: serverRef));
  }

  @override
  Future<void> markFailed(int localId, String reason) async {
    await _update(localId, (QueuedSms row) => row.copyWith(
          status: SyncStatus.failed,
          failureReason: reason,
          retryCount: row.retryCount + 1,
        ));
  }

  @override
  Future<int> purgeApproved(DateTime olderThan) async {
    final Box<Object> box = await _openBox();
    final List<int> stale = <int>[];
    for (final Object? key in box.keys) {
      final QueuedSms? row = _decode(box.get(key));
      if (key is int && row != null && row.status == SyncStatus.approved && row.createdAt.isBefore(olderThan)) {
        stale.add(key);
      }
    }
    await box.deleteAll(stale);
    return stale.length;
  }

  @override
  Future<int> deleteFailed() async {
    final Box<Object> box = await _openBox();
    final List<int> failed = <int>[];
    for (final Object? key in box.keys) {
      final QueuedSms? row = _decode(box.get(key));
      if (key is int && row != null && row.status == SyncStatus.failed) {
        failed.add(key);
      }
    }
    await box.deleteAll(failed);
    return failed.length;
  }

  @override
  Future<int> resetFailedForRetry() async {
    final Box<Object> box = await _openBox();
    int reset = 0;
    for (final Object? key in box.keys.toList()) {
      final QueuedSms? row = _decode(box.get(key));
      if (key is int && row != null && row.status == SyncStatus.failed) {
        // Rebuild as a fresh pending row (retryCount 0, no failure reason) keeping the identity, payload,
        // sender, and timestamps — so the next syncable() pass picks it up again.
        final QueuedSms revived = QueuedSms(
          localId: row.localId,
          encryptedPayload: row.encryptedPayload,
          sender: row.sender,
          receivedAt: row.receivedAt,
          createdAt: row.createdAt,
        );
        await box.put(key, revived.toMap());
        reset++;
      }
    }
    return reset;
  }

  /// Read-modify-write a single row by its [localId] key. No-op if the row is gone.
  Future<void> _update(int localId, QueuedSms Function(QueuedSms) change) async {
    final Box<Object> box = await _openBox();
    final QueuedSms? current = _decode(box.get(localId));
    if (current == null) {
      return;
    }
    await box.put(localId, change(current).toMap());
  }

  QueuedSms? _decode(Object? value) {
    if (value is Map<Object?, Object?>) {
      return QueuedSms.fromMap(value.map((Object? k, Object? v) => MapEntry<String, dynamic>('$k', v)));
    }
    return null;
  }
}
