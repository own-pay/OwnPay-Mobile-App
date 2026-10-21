import 'filter_rules.dart';

/// Source of the on-device privacy-gate [FilterRules].
///
/// Implementations cache the server config locally and refresh it on the
/// `check_interval_hours` cadence. The contract is **fail-closed**: when rules are missing, expired
/// (stale), or unfetchable, [effectiveRules] returns `null` so the [PrivacyGate] drops every message.
/// A stale cache is never served — better to forward nothing than to filter with outdated rules.
abstract interface class FilterRulesRepository {
  /// The rules the gate should evaluate against right now, or `null` to fail closed.
  Future<FilterRules?> effectiveRules();

  /// Forces an immediate refetch from the server (ignoring cache freshness), updating the cache on
  /// success — the Settings screen's "sync from admin panel" action. Returns the freshly-fetched rules,
  /// or `null` if no usable rules were returned. Callers that want to use a fresh cache after a transient
  /// outage must inspect the paired `FilterRulesHealthSource` state; an explicit empty or malformed server
  /// response must not be masked by the old cache.
  Future<FilterRules?> forceRefresh();
}
