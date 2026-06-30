import 'dart:async';

import '../../../core/crypto/aes_gcm_cipher.dart';
import '../../../core/storage/secure_store.dart';
import '../../privacy_gate/data/sender_overrides.dart';
import '../../privacy_gate/domain/filter_rules.dart';
import '../../privacy_gate/domain/filter_rules_repository.dart';
import '../../privacy_gate/domain/gate_decision.dart';
import '../../privacy_gate/domain/privacy_gate.dart';
import '../../../shared/models/raw_sms.dart';
import '../../sync/domain/sms_queue_store.dart';
import '../domain/sms_capture.dart';

/// Consumes captured SMS through the full on-device pipeline:
///
///   drain native buffer → privacy gate → (drop | AES-256-GCM encrypt) → enqueue
///
/// Drops never touch disk: a message the gate rejects is never persisted, encrypted, or logged. Only
/// a gate-passed message is encrypted (with the per-device key from [SecureStore]) and enqueued as a
/// [QueuedSms] holding the ciphertext envelope only.
///
/// Draining is serialized and re-entrant-safe: overlapping triggers (app start, resume, and the
/// [SmsCapture.onPending] nudge) collapse into a single in-flight drain, with one guaranteed re-drain
/// if a trigger arrives mid-flight — so a nudge is never missed and the buffer is consumed exactly once.
class SmsIngestCoordinator {
  SmsIngestCoordinator(
    this._capture,
    this._rules,
    this._queue,
    this._cipher,
    this._store,
    this._overrides, [
    this._gate = const PrivacyGate(),
    this.onEnqueued,
  ]);

  final SmsCapture _capture;
  final FilterRulesRepository _rules;
  final SmsQueueStore _queue;
  final AesGcmCipher _cipher;
  final SecureStore _store;
  final SenderOverrides _overrides;
  final PrivacyGate _gate;

  /// Fired once after a drain that enqueued at least one message — a kick for the sync worker so a
  /// captured SMS is forwarded promptly (without waiting for connectivity/resume). Optional.
  final void Function()? onEnqueued;

  StreamSubscription<void>? _sub;
  bool _draining = false;
  bool _rerun = false;

  /// Begins reacting to native "items pending" nudges. Idempotent — calling twice keeps one
  /// subscription. Pair with an initial [drainNow] (cold start) and a resume-driven [drainNow].
  void start() {
    _sub ??= _capture.onPending.listen((void _) => unawaited(drainNow()));
  }

  /// Drains and processes the native buffer now. Safe to call concurrently: a drain already in
  /// flight absorbs the request and re-drains once on completion.
  Future<void> drainNow() async {
    if (_draining) {
      _rerun = true;
      return;
    }
    _draining = true;
    try {
      do {
        _rerun = false;
        await _drainOnce();
      } while (_rerun);
    } finally {
      _draining = false;
    }
  }

  Future<void> _drainOnce() async {
    // Read prerequisites BEFORE consuming the durable native buffer. We only ever ack (clear) the
    // messages we have actually processed, so every early return below leaves the buffer fully intact
    // for a later drain.
    final String? aesKeyHex = await _store.readAesKey();
    if (aesKeyHex == null || aesKeyHex.isEmpty) {
      return; // not paired yet — leave messages buffered until we have a key
    }

    // Fail-closed: when rules cannot be loaded (offline + stale/first-run), DO NOT consume the buffer.
    // Leaving messages buffered — rather than draining and dropping them — means a payment SMS that
    // arrives during a rules-unavailable window is evaluated for real once rules return, instead of
    // being lost forever. The native 500-cap still bounds storage. (The gate still treats null rules as
    // a drop for direct callers; the coordinator just never reaches that path.)
    final FilterRules? rules = await _rules.effectiveRules();
    if (rules == null) {
      return;
    }

    // Apply the user's on-device sender overrides: a locally-disabled sender is removed from the
    // effective whitelist (strictly subtractive — never widens it). If the user has disabled every
    // source, the effective whitelist is empty and the gate fail-closes (drops, not buffers) — which is
    // exactly the intent of "stop capturing from all sources". Server rules being unavailable is handled
    // above (buffer); local disabling is a deliberate drop.
    final Set<String> disabledSenders = await _overrides.disabled();
    final FilterRules effectiveRules = disabledSenders.isEmpty
        ? rules
        : rules.withAllowedSenders(
            rules.allowedSenders
                .where((String s) => !disabledSenders.contains(s.trim().toLowerCase()))
                .toList(),
          );

    // A corrupt stored key would throw for every passing message; decode it once, up front, and bail
    // (leaving the buffer intact) so a re-pair can fix it rather than the batch being lost. The key is
    // held in memory only for the encrypt calls below and is never logged or persisted.
    final List<int> keyBytes;
    try {
      keyBytes = AesGcmCipher.keyFromHex(aesKeyHex);
    } on ArgumentError {
      return;
    }

    final List<RawSms> messages = await _capture.peekPending();
    if (messages.isEmpty) {
      return;
    }

    // Process oldest-first. `processed` counts the leading run we have durably handled — a gate drop,
    // OR a successful encrypt + enqueue. The `finally` acks exactly that prefix, so if encrypt/enqueue
    // throws, the failing message and everything after it stay buffered for the next drain (never
    // silently dropped — CLAUDE.md §5).
    int processed = 0;
    bool enqueuedAny = false;
    try {
      for (final RawSms sms in messages) {
        final GateDecision decision = _gate.evaluate(sms, effectiveRules);
        if (decision.passed) {
          final String envelope = await _cipher.encryptToEnvelope(
            plaintext: sms.body,
            keyBytes: keyBytes,
          );
          await _queue.enqueue(
            encryptedPayload: envelope,
            sender: sms.sender,
            receivedAt: sms.receivedAt,
          );
          enqueuedAny = true;
        }
        // Dropped (never persisted/encrypted/logged) or enqueued — either way, durably handled.
        processed++;
      }
    } finally {
      await _capture.ackProcessed(processed);
    }
    if (enqueuedAny) {
      onEnqueued?.call();
    }
  }

  /// Stops reacting to nudges. The native buffer and queue are left intact.
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
