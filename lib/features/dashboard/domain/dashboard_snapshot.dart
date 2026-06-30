import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

/// Parses money to an exact [Decimal] — **never a double** (CLAUDE.md §5; mirrors the server's
/// `DECIMAL(20,6)`). Tolerant of strings, ints, or garbage (→ [Decimal.zero]) so a malformed field can't
/// crash the dashboard.
Decimal _money(Object? v) {
  if (v is String) return Decimal.tryParse(v) ?? Decimal.zero;
  if (v is int) return Decimal.fromInt(v);
  if (v is double) return Decimal.tryParse(v.toString()) ?? Decimal.zero;
  return Decimal.zero;
}

int _int(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

String _str(Object? v) => v is String ? v : (v?.toString() ?? '');

/// One recent transaction shown on the dashboard.
class DashboardTransaction extends Equatable {
  const DashboardTransaction({
    required this.trxId,
    required this.amount,
    required this.currency,
    required this.status,
    required this.gateway,
    required this.createdAt,
  });

  factory DashboardTransaction.fromMap(Map<String, dynamic> m) => DashboardTransaction(
        trxId: _str(m['trx_id']),
        amount: _money(m['amount']),
        currency: _str(m['currency']),
        status: _str(m['status']),
        gateway: _str(m['gateway']),
        createdAt: DateTime.tryParse(_str(m['created_at'])) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  final String trxId;
  final Decimal amount;
  final String currency;
  final String status;
  final String gateway;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'trx_id': trxId,
        'amount': amount.toString(),
        'currency': currency,
        'status': status,
        'gateway': gateway,
        'created_at': createdAt.toIso8601String(),
      };

  @override
  List<Object?> get props => <Object?>[trxId, amount, currency, status, gateway, createdAt];
}

/// Snapshot from `GET /api/mobile/v1/dashboard`, cached for offline display. [fetchedAt] is the device
/// clock at fetch — surfaced as the "as of …" timestamp when cached (offline) data is shown.
class DashboardSnapshot extends Equatable {
  const DashboardSnapshot({
    required this.todayRevenue,
    required this.todayTotal,
    required this.todayPending,
    required this.recent,
    required this.unreadNotifications,
    required this.fetchedAt,
  });

  factory DashboardSnapshot.fromApi(Map<String, dynamic> json, {required DateTime fetchedAt}) {
    final Object? today = json['today'];
    final Map<String, dynamic> todayMap = today is Map<String, dynamic> ? today : <String, dynamic>{};
    return DashboardSnapshot(
      todayRevenue: _money(todayMap['revenue']),
      todayTotal: _int(todayMap['total']),
      todayPending: _int(todayMap['pending']),
      recent: _transactions(json['recent_transactions']),
      unreadNotifications: _int(json['unread_notifications']),
      fetchedAt: fetchedAt,
    );
  }

  factory DashboardSnapshot.fromCache(Map<String, dynamic> json) => DashboardSnapshot(
        todayRevenue: _money(json['today_revenue']),
        todayTotal: _int(json['today_total']),
        todayPending: _int(json['today_pending']),
        recent: _transactions(json['recent']),
        unreadNotifications: _int(json['unread_notifications']),
        fetchedAt: DateTime.tryParse(_str(json['fetched_at'])) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  final Decimal todayRevenue;
  final int todayTotal;
  final int todayPending;
  final List<DashboardTransaction> recent;
  final int unreadNotifications;
  final DateTime fetchedAt;

  Map<String, dynamic> toCache() => <String, dynamic>{
        'today_revenue': todayRevenue.toString(),
        'today_total': todayTotal,
        'today_pending': todayPending,
        'recent': recent.map((DashboardTransaction t) => t.toMap()).toList(),
        'unread_notifications': unreadNotifications,
        'fetched_at': fetchedAt.toIso8601String(),
      };

  static List<DashboardTransaction> _transactions(Object? v) {
    if (v is List) {
      return v
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> m) => DashboardTransaction.fromMap(
                m.map((Object? k, Object? val) => MapEntry<String, dynamic>('$k', val)),
              ))
          .toList();
    }
    return const <DashboardTransaction>[];
  }

  @override
  List<Object?> get props =>
      <Object?>[todayRevenue, todayTotal, todayPending, recent, unreadNotifications, fetchedAt];
}
