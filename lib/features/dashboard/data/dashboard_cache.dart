import 'package:hive/hive.dart';

import '../../../core/config/app_config.dart';
import '../domain/dashboard_snapshot.dart';

/// Local cache of the last dashboard snapshot (non-secret) for offline display.
abstract interface class DashboardCache {
  Future<DashboardSnapshot?> read();
  Future<void> write(DashboardSnapshot snapshot);
}

/// Hive-backed [DashboardCache] (box `AppConfig.boxDashboardCache`). Box opened lazily and cached;
/// `Hive.initFlutter()` must have run first (done in `main`).
class HiveDashboardCache implements DashboardCache {
  HiveDashboardCache();

  static const String _key = 'snapshot';

  Box<Object>? _cached;

  Future<Box<Object>> _openBox() async =>
      _cached ??= await Hive.openBox<Object>(AppConfig.boxDashboardCache);

  @override
  Future<DashboardSnapshot?> read() async {
    final Object? raw = (await _openBox()).get(_key);
    if (raw is Map<Object?, Object?>) {
      return DashboardSnapshot.fromCache(
        raw.map((Object? k, Object? v) => MapEntry<String, dynamic>('$k', v)),
      );
    }
    return null;
  }

  @override
  Future<void> write(DashboardSnapshot snapshot) async {
    await (await _openBox()).put(_key, snapshot.toCache());
  }
}
