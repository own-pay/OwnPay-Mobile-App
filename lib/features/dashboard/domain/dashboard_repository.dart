import '../../../core/error/failure.dart';
import 'dashboard_snapshot.dart';

/// Outcome of loading the dashboard.
sealed class DashboardResult {
  const DashboardResult();
}

/// A snapshot to render. [fromCache] true means it is stale offline data (show an "as of …" banner).
class DashboardData extends DashboardResult {
  const DashboardData(this.snapshot, {required this.fromCache});

  final DashboardSnapshot snapshot;
  final bool fromCache;
}

/// No data available (offline before anything was ever cached).
class DashboardUnavailable extends DashboardResult {
  const DashboardUnavailable(this.failure);

  final Failure failure;
}

/// Loads the dashboard: fetches when online (caching the result), and falls back to the last cached
/// snapshot when offline.
abstract interface class DashboardRepository {
  Future<DashboardResult> load();
}
