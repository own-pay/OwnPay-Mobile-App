import 'package:equatable/equatable.dart';

/// The on-device privacy-gate configuration served by
/// `GET /api/mobile/v1/config/filter-rules`, cached locally and refreshed on an interval.
///
/// An empty whitelist is the **fail-closed** state ([isFailClosed]) — when rules are missing,
/// unfetchable, or empty, the gate captures nothing.
class FilterRules extends Equatable {
  const FilterRules({
    required this.version,
    required this.allowedSenders,
    required this.positiveKeywords,
    required this.negativeKeywords,
    required this.checkIntervalHours,
    required this.fetchedAt,
  });

  final int version;
  final List<String> allowedSenders;
  final List<String> positiveKeywords;
  final List<String> negativeKeywords;
  final int checkIntervalHours;
  final DateTime fetchedAt;

  /// Fail-closed sentinel: an empty whitelist means "send nothing".
  factory FilterRules.empty() => FilterRules(
        version: 0,
        allowedSenders: const <String>[],
        positiveKeywords: const <String>[],
        negativeKeywords: const <String>[],
        checkIntervalHours: 24,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// True when there is no usable whitelist — the gate must drop everything.
  bool get isFailClosed => allowedSenders.isEmpty;

  /// Returns a copy with a different sender whitelist, keeping every other field. Used to apply the
  /// on-device sender overrides (a user may locally DISABLE a server-whitelisted sender — a strictly
  /// subtractive change, so it can only narrow what the gate forwards, never widen it).
  FilterRules withAllowedSenders(List<String> senders) => FilterRules(
        version: version,
        allowedSenders: senders,
        positiveKeywords: positiveKeywords,
        negativeKeywords: negativeKeywords,
        checkIntervalHours: checkIntervalHours,
        fetchedAt: fetchedAt,
      );

  /// Whether the cached rules are older than their refresh cadence. A non-positive
  /// `check_interval_hours` (a misconfigured/garbled server value) would make every check "stale" —
  /// forcing a refetch on every drain and a fail-closed drop on every drain while offline — so it
  /// falls back to the 24h default.
  bool isStale(DateTime now) {
    final int hours = checkIntervalHours < 1 ? 24 : checkIntervalHours;
    return now.difference(fetchedAt) >= Duration(hours: hours);
  }

  /// Parses the server response. [fetchedAt] is stamped by the caller (the device clock at fetch).
  factory FilterRules.fromApi(Map<String, dynamic> json, {required DateTime fetchedAt}) => FilterRules(
        version: _asInt(json['version'], 0),
        allowedSenders: _strList(json['allowed_senders']),
        positiveKeywords: _strList(json['positive_keywords']),
        negativeKeywords: _strList(json['negative_keywords']),
        checkIntervalHours: _asInt(json['check_interval_hours'], 24),
        fetchedAt: fetchedAt,
      );

  /// Serializes for the local Hive cache.
  Map<String, dynamic> toCache() => <String, dynamic>{
        'version': version,
        'allowed_senders': allowedSenders,
        'positive_keywords': positiveKeywords,
        'negative_keywords': negativeKeywords,
        'check_interval_hours': checkIntervalHours,
        'fetched_at': fetchedAt.toIso8601String(),
      };

  factory FilterRules.fromCache(Map<String, dynamic> json) => FilterRules(
        version: _asInt(json['version'], 0),
        allowedSenders: _strList(json['allowed_senders']),
        positiveKeywords: _strList(json['positive_keywords']),
        negativeKeywords: _strList(json['negative_keywords']),
        checkIntervalHours: _asInt(json['check_interval_hours'], 24),
        fetchedAt: DateTime.tryParse('${json['fetched_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  static int _asInt(Object? v, int fallback) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static List<String> _strList(Object? v) {
    if (v is List) {
      return v.map((Object? e) => e?.toString() ?? '').where((String s) => s.isNotEmpty).toList();
    }
    return const <String>[];
  }

  @override
  List<Object?> get props =>
      [version, allowedSenders, positiveKeywords, negativeKeywords, checkIntervalHours, fetchedAt];
}
