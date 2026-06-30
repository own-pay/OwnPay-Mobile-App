import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_result.dart';
import '../../../core/storage/secure_store.dart';
import '../domain/queued_sms.dart';
import '../domain/retry_policy.dart';
import '../domain/sms_queue_store.dart';
import '../domain/syncer.dart';

/// Drains the encrypted offline queue to `POST /api/mobile/v1/sms` and reflects the server's verdict
/// back onto each row. Only the AES-GCM envelope leaves the device (never plaintext — [QueuedSms.toApi]).
///
/// One attempt = batches of [batchSize] `syncable` rows, posted oldest-first. Per the result:
///   - `accepted` / `duplicate` → `markApproved` (+ server ref) — a `duplicate` is a server-side
///                                success (the message is already stored), so it must not be re-posted
///   - any other / missing      → `markFailed` (retryCount++ — surfaces in the audit UI, retried later)
///
/// Draining keeps going only while a whole batch is accepted; the run stops on the first failure and
/// arms an exponential backoff window ([RetryPolicy.backoffFor]) so a flapping connection or rapid
/// triggers (connectivity-up / resume / post-enqueue kick) can't hammer the server. An `AuthFailure`
/// (a 401 the interceptor could not refresh) fires [onReauthRequired] and stops **without** bumping
/// retry or backing off — the rows are fine, authorization is not; they sync once the device re-pairs.
/// Calls are serialized.
class SyncWorker implements Syncer {
  SyncWorker(
    this._api,
    this._store,
    this._queue, {
    this.policy = const RetryPolicy(),
    this.onReauthRequired,
    this.batchSize = 50,
    this.now = DateTime.now,
  });

  final ApiClient _api;
  final SecureStore _store;
  final SmsQueueStore _queue;
  final RetryPolicy policy;
  final void Function()? onReauthRequired;
  final int batchSize;

  /// Injectable clock (defaults to [DateTime.now]) — overridden in tests to exercise backoff timing.
  final DateTime Function() now;

  bool _syncing = false;
  bool _rerun = false;
  // After a retryable failure, the worker backs off until this time; triggers that fire earlier no-op.
  DateTime? _retryNotBefore;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  /// Begins syncing whenever the device comes back online. Idempotent — keeps a single subscription.
  /// Pair with a cold-start/resume [syncNow] and the coordinator's post-enqueue kick.
  void start() {
    _connSub ??= Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> status) {
      final bool online = status.any((ConnectivityResult r) => r != ConnectivityResult.none);
      if (online) {
        unawaited(syncNow());
      }
    });
  }

  /// Stops reacting to connectivity changes. The queue is left intact.
  Future<void> dispose() async {
    await _connSub?.cancel();
    _connSub = null;
  }

  /// Attempts to sync the queue now. Safe to call concurrently — an in-flight run absorbs the request
  /// and re-runs once on completion (so a row enqueued mid-sync isn't missed).
  @override
  Future<void> syncNow({bool force = false}) async {
    if (force) {
      _retryNotBefore = null; // user-initiated retry ignores the backoff window
    }
    if (_syncing) {
      _rerun = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _rerun = false;
        await _syncOnce();
      } while (_rerun);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncOnce() async {
    final String? base = await _store.readServerUrl();
    if (base == null || base.isEmpty) {
      return; // not paired — nothing to sync to
    }

    // Honor the backoff window: after a retryable failure the worker waits before re-posting, so a
    // flapping connection or rapid triggers can't hammer the server.
    final DateTime? notBefore = _retryNotBefore;
    if (notBefore != null && now().isBefore(notBefore)) {
      return;
    }

    while (true) {
      final List<QueuedSms> batch =
          await _queue.syncable(maxRetries: policy.maxRetries, limit: batchSize);
      if (batch.isEmpty) {
        _retryNotBefore = null; // queue drained (or all exhausted) — clear any pending backoff
        return;
      }

      final ApiResult<Map<String, dynamic>> res = await _api.post(
        '$base${AppConfig.apiPrefix}/sms',
        body: <String, dynamic>{
          'messages': batch.map((QueuedSms r) => r.toApi()).toList(growable: false),
        },
      );

      final bool keepDraining = await _apply(res, batch);
      if (!keepDraining) {
        return;
      }
    }
  }

  /// Applies one batch's outcome. Returns true to keep draining (the whole batch was accepted).
  Future<bool> _apply(ApiResult<Map<String, dynamic>> res, List<QueuedSms> batch) async {
    switch (res) {
      case Err<Map<String, dynamic>>(:final Failure failure):
        if (failure is AuthFailure) {
          onReauthRequired?.call();
          return false; // re-pair needed; leave rows untouched (no retry bump)
        }
        // Transport/server error — the whole batch failed this attempt; back off and retry later.
        for (final QueuedSms row in batch) {
          await _queue.markFailed(row.localId, failure.message);
        }
        _backOff(batch);
        return false;
      case Ok<Map<String, dynamic>>(:final Map<String, dynamic> value):
        final Map<int, _SmsResult> results = _parseResults(value);
        bool allAccepted = true;
        final List<QueuedSms> failed = <QueuedSms>[];
        for (final QueuedSms row in batch) {
          final _SmsResult? result = results[row.localId];
          if (result != null && result.accepted) {
            await _queue.markApproved(row.localId, result.serverRef);
          } else {
            allAccepted = false;
            failed.add(row);
            await _queue.markFailed(row.localId, result?.status ?? 'no server result');
          }
        }
        if (!allAccepted) {
          _backOff(failed);
        }
        return allAccepted;
    }
  }

  /// Arms the backoff window after a retryable failure. The delay grows with the least-retried failed
  /// row's (post-increment) attempt count, so persistent failures wait progressively longer while a
  /// freshly-failed row isn't over-delayed.
  void _backOff(List<QueuedSms> failed) {
    int minRetry = policy.maxRetries;
    for (final QueuedSms row in failed) {
      if (row.retryCount < minRetry) {
        minRetry = row.retryCount;
      }
    }
    _retryNotBefore = now().add(policy.backoffFor(minRetry + 1));
  }

  /// Indexes the response `results` array by `local_id`.
  Map<int, _SmsResult> _parseResults(Map<String, dynamic> body) {
    final Object? results = body['results'];
    final Map<int, _SmsResult> out = <int, _SmsResult>{};
    if (results is List) {
      for (final Object? item in results) {
        if (item is Map<Object?, Object?>) {
          final Object? rawId = item['local_id'];
          final int? localId = rawId is int ? rawId : int.tryParse('$rawId');
          if (localId != null) {
            final Object? status = item['status'];
            final Object? ref = item['server_ref'];
            out[localId] = _SmsResult(
              status: status is String ? status : '',
              serverRef: ref is String ? ref : null,
            );
          }
        }
      }
    }
    return out;
  }
}

/// One server verdict for a queued message.
class _SmsResult {
  const _SmsResult({required this.status, required this.serverRef});

  final String status;
  final String? serverRef;

  /// The server treats a `duplicate` as a success — the message is already stored (its dedupe is on
  /// device + sender + received_at, so a retry after a lost response legitimately returns `duplicate`).
  /// Mirroring that here is essential: otherwise duplicates are re-posted up to maxRetries and then
  /// stick forever as audit "issues", despite having been delivered.
  bool get accepted => status == 'accepted' || status == 'duplicate';
}
