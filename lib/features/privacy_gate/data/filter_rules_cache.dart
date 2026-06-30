import 'package:hive/hive.dart';

import '../../../core/config/app_config.dart';
import '../domain/filter_rules.dart';

/// Local cache for the privacy-gate [FilterRules]. Non-secret data, so it lives in Hive (never in the
/// secure keystore). Abstracted behind an interface so the repository is unit-testable without Hive.
abstract interface class FilterRulesCache {
  /// The last successfully-fetched rules, or `null` if nothing has been cached yet.
  Future<FilterRules?> read();

  /// Persists the latest rules (already stamped with their fetch time).
  Future<void> write(FilterRules rules);
}

/// Hive-backed [FilterRulesCache]. The box is opened lazily and cached; `Hive.initFlutter()` must have
/// run first (done in `main`). A single record is kept under [_key].
class HiveFilterRulesCache implements FilterRulesCache {
  HiveFilterRulesCache();

  static const String _key = 'rules';

  Box<Object>? _cached;

  Future<Box<Object>> _openBox() async =>
      _cached ??= await Hive.openBox<Object>(AppConfig.boxFilterRules);

  @override
  Future<FilterRules?> read() async {
    final Object? raw = (await _openBox()).get(_key);
    if (raw is Map<Object?, Object?>) {
      return FilterRules.fromCache(_stringKeyed(raw));
    }
    return null;
  }

  @override
  Future<void> write(FilterRules rules) async {
    await (await _openBox()).put(_key, rules.toCache());
  }

  /// Hive returns maps as `Map<dynamic, dynamic>`; normalize to the `Map<String, dynamic>` the
  /// domain parser expects.
  Map<String, dynamic> _stringKeyed(Map<Object?, Object?> raw) =>
      raw.map((Object? k, Object? v) => MapEntry<String, dynamic>('$k', v));
}
