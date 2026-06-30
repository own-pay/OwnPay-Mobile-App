import '../../../core/config/app_config.dart';
import '../../../core/error/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_result.dart';
import '../../../core/storage/secure_store.dart';
import '../domain/dashboard_repository.dart';
import '../domain/dashboard_snapshot.dart';
import 'dashboard_cache.dart';

/// [DashboardRepository] over `GET /api/mobile/v1/dashboard`. Online → parse + cache + return fresh;
/// offline/unreachable → serve the last cached snapshot (marked `fromCache`); never cached → unavailable.
/// A failed fetch never overwrites a good cache.
class NetworkDashboardRepository implements DashboardRepository {
  NetworkDashboardRepository(
    this._api,
    this._store,
    this._cache, [
    this._now = DateTime.now,
  ]);

  final ApiClient _api;
  final SecureStore _store;
  final DashboardCache _cache;
  final DateTime Function() _now;

  @override
  Future<DashboardResult> load() async {
    final String? base = await _store.readServerUrl();
    Failure? lastFailure;

    if (base != null && base.isNotEmpty) {
      final ApiResult<Map<String, dynamic>> res =
          await _api.get('$base${AppConfig.apiPrefix}/dashboard');
      switch (res) {
        case Ok<Map<String, dynamic>>(:final Map<String, dynamic> value):
          final DashboardSnapshot snapshot = DashboardSnapshot.fromApi(value, fetchedAt: _now());
          await _cache.write(snapshot);
          return DashboardData(snapshot, fromCache: false);
        case Err<Map<String, dynamic>>(:final Failure failure):
          lastFailure = failure;
      }
    }

    final DashboardSnapshot? cached = await _cache.read();
    if (cached != null) {
      return DashboardData(cached, fromCache: true);
    }
    return DashboardUnavailable(lastFailure ?? const NetworkFailure());
  }
}
