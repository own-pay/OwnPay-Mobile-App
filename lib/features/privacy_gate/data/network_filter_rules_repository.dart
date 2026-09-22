import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_result.dart';
import '../../../core/storage/secure_store.dart';
import '../domain/filter_rules.dart';
import '../domain/filter_rules_health.dart';
import '../domain/filter_rules_repository.dart';
import 'filter_rules_cache.dart';

/// [FilterRulesRepository] that fetches `GET /api/mobile/v1/config/filter-rules` from the paired
/// server and caches it in Hive, refreshing on the `check_interval_hours` cadence.
///
/// Fail-closed by construction (see [effectiveRules]): a missing/expired cache that cannot be
/// refreshed yields `null`, and a stale cache is never served.
class NetworkFilterRulesRepository implements FilterRulesRepository, FilterRulesHealthSource {
  NetworkFilterRulesRepository(
    this._api,
    this._store,
    this._cache, [
    this._now = DateTime.now,
  ]);

  final ApiClient _api;
  final SecureStore _store;
  final FilterRulesCache _cache;
  final DateTime Function() _now;
  final ValueNotifier<FilterRulesHealthSnapshot> _health =
      ValueNotifier<FilterRulesHealthSnapshot>(const FilterRulesHealthSnapshot());

  @override
  ValueListenable<FilterRulesHealthSnapshot> get health => _health;

  @override
  Future<FilterRules?> effectiveRules() async {
    final DateTime now = _now();

    // A fresh, USABLE cache is authoritative — no network needed. An empty (fail-closed) cache is
    // deliberately NOT treated as authoritative: it means the whitelist was unconfigured/empty at the
    // last fetch, so we re-check now rather than staying dark for a whole interval after the server is
    // configured/fixed.
    final FilterRules? cached = await _cache.read();
    if (cached != null && !cached.isStale(now) && !cached.isFailClosed) {
      _setHealth(
        FilterRulesHealthStatus.ready,
        'SMS sources ready (${cached.allowedSenders.length}).',
      );
      return cached;
    }

    // Missing or expired → try to refresh.
    final FilterRules? fetched = await _fetch(now);
    if (fetched != null) {
      await _cache.write(fetched);
      return fetched;
    }

    // Unfetchable: fail-closed. Deliberately do NOT serve the stale cache — outdated rules could
    // forward an SMS the server no longer whitelists (or that it now blocks). Capturing nothing is
    // the safe failure mode (SECURITY.md §2).
    return null;
  }

  @override
  Future<FilterRules?> forceRefresh() async {
    // Always hit the network (ignore cache freshness). On success, refresh the cache; on failure, leave
    // the existing cache untouched so a transient outage doesn't wipe a good whitelist.
    final FilterRules? fetched = await _fetch(_now());
    if (fetched != null) {
      await _cache.write(fetched);
    }
    return fetched;
  }

  Future<FilterRules?> _fetch(DateTime now) async {
    final String? base = await _store.readServerUrl();
    if (base == null || base.isEmpty) {
      _setHealth(
        FilterRulesHealthStatus.unavailable,
        'No paired server URL. Re-pair this device.',
      );
      return null;
    }
    final ApiResult<Map<String, dynamic>> res =
        await _api.get('$base${AppConfig.apiPrefix}/config/filter-rules');
    return res.fold<FilterRules?>(
      (Failure failure) {
        _setHealth(_healthStatusForFailure(failure), _friendlyFailure(failure));
        return null;
      },
      (Map<String, dynamic> body) => _parse(body, now),
    );
  }

  /// [ApiClient] has already unwrapped the `{ "success": true, "data": { … } }` envelope, so [body] is
  /// the rules object itself. A response with no usable whitelist — `allowed_senders` absent OR empty —
  /// is treated as a fetch failure (→ fail-closed, NOT cached), rather than persisting a "fresh" empty
  /// whitelist that would suppress retries for a whole interval and keep the device dark after the
  /// server is configured/fixed. Once real senders arrive, the rules cache normally.
  FilterRules? _parse(Map<String, dynamic> body, DateTime now) {
    if (!body.containsKey('allowed_senders')) {
      _setHealth(
        FilterRulesHealthStatus.malformed,
        'The server returned no SMS-source configuration.',
      );
      return null;
    }
    final FilterRules rules = FilterRules.fromApi(body, fetchedAt: now);
    if (rules.isFailClosed) {
      _setHealth(
        FilterRulesHealthStatus.empty,
        'No SMS sources are configured on the OwnPay server.',
      );
      return null;
    }
    _setHealth(
      FilterRulesHealthStatus.ready,
      'SMS sources ready (${rules.allowedSenders.length}).',
    );
    return rules;
  }

  void _setHealth(FilterRulesHealthStatus status, String message) {
    _health.value = FilterRulesHealthSnapshot(
      status: status,
      message: message,
      updatedAt: _now(),
    );
  }

  FilterRulesHealthStatus _healthStatusForFailure(Failure failure) => switch (failure) {
        AuthFailure() => FilterRulesHealthStatus.authRequired,
        ValidationFailure() => FilterRulesHealthStatus.malformed,
        _ => FilterRulesHealthStatus.unavailable,
      };

  String _friendlyFailure(Failure failure) => switch (failure) {
        NetworkFailure() => 'OwnPay server is unreachable. SMS will stay queued and retry.',
        AuthFailure() => 'Device authorization expired. Re-pair this device.',
        ValidationFailure() => 'OwnPay rejected the SMS-source request.',
        ServerFailure() => 'OwnPay could not provide SMS sources. Try again later.',
        _ => 'Could not load SMS sources. Check the server connection.',
      };
}
