import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Non-sensitive status of the server-provided SMS whitelist.
///
/// This is intentionally separate from [FilterRulesRepository] so the privacy gate can remain
/// fail-closed while presentation can explain why forwarding is paused.
enum FilterRulesHealthStatus { unknown, ready, empty, unavailable, authRequired, malformed }

class FilterRulesHealthSnapshot extends Equatable {
  const FilterRulesHealthSnapshot({
    this.status = FilterRulesHealthStatus.unknown,
    this.message = 'Checking SMS sources…',
    this.updatedAt,
  });

  final FilterRulesHealthStatus status;
  final String message;
  final DateTime? updatedAt;

  @override
  List<Object?> get props => <Object?>[status, message, updatedAt];
}

/// Read-only health stream exposed by filter-rules implementations.
abstract interface class FilterRulesHealthSource {
  ValueListenable<FilterRulesHealthSnapshot> get health;
}
