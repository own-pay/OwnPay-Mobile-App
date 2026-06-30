import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/crypto/aes_gcm_cipher.dart';
import 'package:ownpay_console/core/storage/secure_store.dart';
import 'package:ownpay_console/features/privacy_gate/data/sender_overrides.dart';
import 'package:ownpay_console/features/privacy_gate/domain/filter_rules.dart';
import 'package:ownpay_console/features/privacy_gate/domain/filter_rules_repository.dart';
import 'package:ownpay_console/features/privacy_gate/domain/privacy_gate.dart';
import 'package:ownpay_console/features/sms_capture/data/sms_ingest_coordinator.dart';
import 'package:ownpay_console/features/sms_capture/domain/sms_capture.dart';
import 'package:ownpay_console/features/sync/domain/queued_sms.dart';
import 'package:ownpay_console/features/sync/domain/sms_queue_store.dart';
import 'package:ownpay_console/shared/models/raw_sms.dart';

class _MockSecureStore extends Mock implements SecureStore {}

/// 32-byte AES key as hex-64 (matches what pairing issues).
const String _keyHex = '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20';

/// In-memory [SmsCapture] modelling the native durable buffer: [peekPending] reads it WITHOUT
/// clearing, [ackProcessed] removes the leading `count` Dart confirms it handled. Records peek/ack
/// activity so tests can assert the buffer is consumed exactly once — and left intact when it must be.
class _FakeCapture implements SmsCapture {
  _FakeCapture(List<RawSms> initial) : _buffer = List<RawSms>.of(initial);

  final List<RawSms> _buffer;
  final StreamController<void> _pending = StreamController<void>.broadcast();
  int peekCalls = 0;
  int ackedTotal = 0;
  bool monitoring = false;

  List<RawSms> get buffer => List<RawSms>.unmodifiable(_buffer);

  void nudge() => _pending.add(null);

  @override
  Future<List<RawSms>> peekPending() async {
    peekCalls++;
    return List<RawSms>.unmodifiable(_buffer);
  }

  @override
  Future<void> ackProcessed(int count) async {
    if (count <= 0) {
      return;
    }
    ackedTotal += count;
    _buffer.removeRange(0, count > _buffer.length ? _buffer.length : count);
  }

  @override
  Stream<void> get onPending => _pending.stream;

  @override
  Future<void> startMonitoring() async => monitoring = true;

  @override
  Future<void> stopMonitoring() async => monitoring = false;

  @override
  Future<bool> isMonitoring() async => monitoring;
}

class _FakeRules implements FilterRulesRepository {
  _FakeRules(this.rules);
  FilterRules? rules;

  @override
  Future<FilterRules?> effectiveRules() async => rules;

  @override
  Future<FilterRules?> forceRefresh() async => rules;
}

class _FakeOverrides implements SenderOverrides {
  _FakeOverrides([Set<String>? disabled]) : _disabled = disabled ?? <String>{};

  final Set<String> _disabled;

  @override
  Future<Set<String>> disabled() async => _disabled;

  @override
  Future<void> setDisabled(String sender, bool disabled) async {
    final String k = sender.trim().toLowerCase();
    if (disabled) {
      _disabled.add(k);
    } else {
      _disabled.remove(k);
    }
  }
}

class _FakeQueue implements SmsQueueStore {
  final List<QueuedSms> items = <QueuedSms>[];

  @override
  Future<QueuedSms> enqueue({
    required String encryptedPayload,
    required String sender,
    required DateTime receivedAt,
  }) async {
    final QueuedSms item = QueuedSms(
      localId: items.length + 1,
      encryptedPayload: encryptedPayload,
      sender: sender,
      receivedAt: receivedAt,
      createdAt: DateTime(2026, 6, 23, 12),
    );
    items.add(item);
    return item;
  }

  @override
  Future<List<QueuedSms>> all() async => List<QueuedSms>.unmodifiable(items);

  @override
  Future<List<QueuedSms>> syncable({required int maxRetries, int limit = 50}) async {
    final List<QueuedSms> f = items
        .where((QueuedSms q) => q.isSyncable && q.retryCount < maxRetries)
        .toList()
      ..sort((QueuedSms a, QueuedSms b) => a.localId.compareTo(b.localId));
    return f.length > limit ? f.sublist(0, limit) : f;
  }

  @override
  Future<void> markApproved(int localId, String? serverRef) async {
    final int i = items.indexWhere((QueuedSms q) => q.localId == localId);
    if (i >= 0) {
      items[i] = items[i].copyWith(status: SyncStatus.approved, serverRef: serverRef);
    }
  }

  @override
  Future<void> markFailed(int localId, String reason) async {
    final int i = items.indexWhere((QueuedSms q) => q.localId == localId);
    if (i >= 0) {
      items[i] = items[i]
          .copyWith(status: SyncStatus.failed, failureReason: reason, retryCount: items[i].retryCount + 1);
    }
  }

  @override
  Future<int> purgeApproved(DateTime olderThan) async {
    final int before = items.length;
    items.removeWhere((QueuedSms q) => q.status == SyncStatus.approved && q.createdAt.isBefore(olderThan));
    return before - items.length;
  }

  @override
  Future<int> deleteFailed() async {
    final int before = items.length;
    items.removeWhere((QueuedSms q) => q.status == SyncStatus.failed);
    return before - items.length;
  }

  @override
  Future<int> resetFailedForRetry() async {
    int n = 0;
    for (int i = 0; i < items.length; i++) {
      if (items[i].status == SyncStatus.failed) {
        items[i] = items[i].copyWith(status: SyncStatus.pending, retryCount: 0);
        n++;
      }
    }
    return n;
  }
}

/// A queue whose Nth [enqueue] throws, to prove the coordinator never loses an un-persisted message.
class _ThrowOnNthEnqueue implements SmsQueueStore {
  _ThrowOnNthEnqueue({required this.failOnCall});

  final int failOnCall;
  int calls = 0;
  int enqueued = 0;

  @override
  Future<QueuedSms> enqueue({
    required String encryptedPayload,
    required String sender,
    required DateTime receivedAt,
  }) async {
    calls++;
    if (calls == failOnCall) {
      throw StateError('simulated enqueue failure');
    }
    enqueued++;
    return QueuedSms(
      localId: enqueued,
      encryptedPayload: encryptedPayload,
      sender: sender,
      receivedAt: receivedAt,
      createdAt: DateTime(2026, 6, 23, 12),
    );
  }

  @override
  Future<List<QueuedSms>> all() async => const <QueuedSms>[];

  @override
  Future<List<QueuedSms>> syncable({required int maxRetries, int limit = 50}) async => const <QueuedSms>[];

  @override
  Future<void> markApproved(int localId, String? serverRef) async {}

  @override
  Future<void> markFailed(int localId, String reason) async {}

  @override
  Future<int> purgeApproved(DateTime olderThan) async => 0;

  @override
  Future<int> deleteFailed() async => 0;

  @override
  Future<int> resetFailedForRetry() async => 0;
}

void main() {
  late _MockSecureStore store;
  final AesGcmCipher cipher = AesGcmCipher();

  FilterRules openRules() => FilterRules(
        version: 1,
        allowedSenders: const <String>['bKash', '16247'],
        positiveKeywords: const <String>['received', 'TrxID'],
        negativeKeywords: const <String>['OTP', 'PIN', 'verify', 'code'],
        checkIntervalHours: 24,
        fetchedAt: DateTime(2026, 6, 23),
      );

  RawSms sms(String sender, String body) =>
      RawSms(sender: sender, body: body, receivedAt: DateTime(2026, 6, 23, 10, 30));

  // One passer + three drops (negative keyword / sender / no-positive).
  const String passBody = 'You have received Tk 1,500.00. TrxID 9F2K7Q1';
  List<RawSms> mixedBatch() => <RawSms>[
        sms('bKash', passBody),
        sms('bKash', 'Your OTP is 123456'),
        sms('SPAM-CO', 'received Tk 100 TrxID X'),
        sms('16247', 'Welcome to our service'),
      ];

  SmsIngestCoordinator build(_FakeCapture capture, _FakeRules rules, SmsQueueStore queue) =>
      SmsIngestCoordinator(capture, rules, queue, cipher, store, _FakeOverrides());

  setUp(() {
    store = _MockSecureStore();
    when(() => store.readAesKey()).thenAnswer((_) async => _keyHex);
  });

  test('drops non-passers and encrypts + enqueues only passers, then acks the whole batch', () async {
    final _FakeCapture capture = _FakeCapture(mixedBatch());
    final _FakeQueue queue = _FakeQueue();

    await build(capture, _FakeRules(openRules()), queue).drainNow();

    expect(queue.items, hasLength(1));
    final QueuedSms only = queue.items.single;
    expect(only.sender, 'bKash');
    expect(only.status, SyncStatus.pending);
    // All four were handled (1 enqueued + 3 dropped) → buffer fully acked.
    expect(capture.ackedTotal, 4);
    expect(capture.buffer, isEmpty);

    // Round-trip proves the encrypted payload is the real body and nothing else leaked.
    final String decrypted = await cipher.decryptFromEnvelope(
      envelopeBase64: only.encryptedPayload,
      keyBytes: AesGcmCipher.keyFromHex(_keyHex),
    );
    expect(decrypted, passBody);
  });

  test('a locally-disabled sender is dropped even though the server whitelists it', () async {
    final _FakeCapture capture = _FakeCapture(<RawSms>[sms('bKash', passBody)]);
    final _FakeQueue queue = _FakeQueue();

    // bKash is whitelisted by the server rules, but the user disabled it on this device → the subtractive
    // override removes it from the effective whitelist, so the gate drops it. It is still CONSUMED (a
    // deliberate drop), not buffered.
    await SmsIngestCoordinator(
      capture,
      _FakeRules(openRules()),
      queue,
      cipher,
      store,
      _FakeOverrides(<String>{'bkash'}),
    ).drainNow();

    expect(queue.items, isEmpty);
    expect(capture.ackedTotal, 1);
    expect(capture.buffer, isEmpty);
  });

  test('fail-closed (rules unavailable): nothing enqueued AND the buffer is left intact (not lost)', () async {
    final _FakeCapture capture = _FakeCapture(mixedBatch());
    final _FakeQueue queue = _FakeQueue();

    await build(capture, _FakeRules(null), queue).drainNow();

    expect(queue.items, isEmpty);
    // F10: while rules can't be loaded, messages must NOT be consumed — they wait for rules to return.
    expect(capture.peekCalls, 0);
    expect(capture.ackedTotal, 0);
    expect(capture.buffer, hasLength(4));
  });

  test('drain is idempotent — draining twice enqueues the passer once (buffer acked once)', () async {
    final _FakeCapture capture = _FakeCapture(mixedBatch());
    final _FakeQueue queue = _FakeQueue();
    final SmsIngestCoordinator coordinator = build(capture, _FakeRules(openRules()), queue);

    await coordinator.drainNow();
    await coordinator.drainNow();

    expect(queue.items, hasLength(1));
    expect(capture.buffer, isEmpty);
  });

  test('concurrent drains coalesce — the passer is still enqueued once', () async {
    final _FakeCapture capture = _FakeCapture(mixedBatch());
    final _FakeQueue queue = _FakeQueue();
    final SmsIngestCoordinator coordinator = build(capture, _FakeRules(openRules()), queue);

    await Future.wait<void>(<Future<void>>[coordinator.drainNow(), coordinator.drainNow()]);

    expect(queue.items, hasLength(1));
  });

  test('queued rows carry no plaintext', () async {
    final _FakeCapture capture = _FakeCapture(mixedBatch());
    final _FakeQueue queue = _FakeQueue();

    await build(capture, _FakeRules(openRules()), queue).drainNow();

    final QueuedSms only = queue.items.single;
    expect(only.encryptedPayload, isNot(contains(passBody)));
    final Map<String, dynamic> map = only.toMap();
    expect(map.containsKey('body'), isFalse);
    // No serialized value carries the plaintext body.
    for (final Object? value in map.values) {
      expect('$value', isNot(contains(passBody)));
    }
  });

  test('no AES key (unpaired) → enqueues nothing AND leaves the native buffer intact', () async {
    when(() => store.readAesKey()).thenAnswer((_) async => null);
    final _FakeCapture capture = _FakeCapture(mixedBatch());
    final _FakeQueue queue = _FakeQueue();

    await build(capture, _FakeRules(openRules()), queue).drainNow();

    expect(queue.items, isEmpty);
    // The durable buffer must NOT be consumed when we cannot process it.
    expect(capture.peekCalls, 0);
    expect(capture.buffer, hasLength(4));
  });

  test('a mid-batch enqueue failure acks only the processed prefix; the rest stay buffered (no loss)', () async {
    // Buffer: [drop(OTP), passer (enqueues OK), passer (enqueue throws)].
    final _FakeCapture capture = _FakeCapture(<RawSms>[
      sms('bKash', 'Your OTP is 123456'),
      sms('bKash', passBody),
      sms('bKash', passBody),
    ]);
    final _ThrowOnNthEnqueue queue = _ThrowOnNthEnqueue(failOnCall: 2);

    await expectLater(
      build(capture, _FakeRules(openRules()), queue).drainNow(),
      throwsA(isA<StateError>()),
    );

    // The drop + the first passer were durably handled (acked); the failing passer is NOT lost.
    expect(queue.enqueued, 1);
    expect(capture.ackedTotal, 2);
    expect(capture.buffer, hasLength(1));
  });

  test('onPending nudge triggers a drain', () async {
    final _FakeCapture capture = _FakeCapture(mixedBatch());
    final _FakeQueue queue = _FakeQueue();
    final SmsIngestCoordinator coordinator = build(capture, _FakeRules(openRules()), queue)..start();

    capture.nudge();
    await pumpEventQueue();

    expect(queue.items, hasLength(1));
    await coordinator.dispose();
  });

  test('onEnqueued kicks the sync worker after a drain that enqueued, but not when nothing passes', () async {
    int kicks = 0;

    await SmsIngestCoordinator(
      _FakeCapture(mixedBatch()),
      _FakeRules(openRules()),
      _FakeQueue(),
      cipher,
      store,
      _FakeOverrides(),
      const PrivacyGate(),
      () => kicks++,
    ).drainNow();
    expect(kicks, 1); // a passer was enqueued

    await SmsIngestCoordinator(
      _FakeCapture(mixedBatch()),
      _FakeRules(null), // fail-closed → nothing enqueued
      _FakeQueue(),
      cipher,
      store,
      _FakeOverrides(),
      const PrivacyGate(),
      () => kicks++,
    ).drainNow();
    expect(kicks, 1); // unchanged — no kick when nothing was enqueued
  });
}
