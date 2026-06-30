import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ownpay_console/features/dashboard/domain/dashboard_snapshot.dart';

void main() {
  Map<String, dynamic> body() => <String, dynamic>{
        'today': <String, dynamic>{'revenue': '1500.50', 'total': 7, 'pending': 2},
        'recent_transactions': <Map<String, dynamic>>[
          <String, dynamic>{
            'trx_id': 'TRX1',
            'amount': '1200.00',
            'currency': 'BDT',
            'status': 'completed',
            'gateway': 'bkash',
            'created_at': '2026-06-24T09:30:00+06:00',
          },
        ],
        'unread_notifications': 3,
        'server_time': '2026-06-24T10:00:00Z',
      };

  final DateTime fetchedAt = DateTime(2026, 6, 24, 10);

  test('fromApi parses money as Decimal (never double) and the stats/counts', () {
    final DashboardSnapshot snap = DashboardSnapshot.fromApi(body(), fetchedAt: fetchedAt);

    expect(snap.todayRevenue, Decimal.parse('1500.50'));
    expect(snap.todayTotal, 7);
    expect(snap.todayPending, 2);
    expect(snap.unreadNotifications, 3);
    expect(snap.fetchedAt, fetchedAt);
    expect(snap.recent, hasLength(1));
    final DashboardTransaction tx = snap.recent.single;
    expect(tx.trxId, 'TRX1');
    expect(tx.amount, Decimal.parse('1200.00'));
    expect(tx.currency, 'BDT');
    expect(tx.status, 'completed');
    expect(tx.gateway, 'bkash');
  });

  test('fromApi is tolerant of missing/garbled money (fails to Decimal.zero, not a throw)', () {
    final DashboardSnapshot snap = DashboardSnapshot.fromApi(
      <String, dynamic>{'today': <String, dynamic>{'revenue': 'oops'}},
      fetchedAt: fetchedAt,
    );
    expect(snap.todayRevenue, Decimal.zero);
    expect(snap.todayTotal, 0);
    expect(snap.recent, isEmpty);
  });

  test('cache round-trip preserves Decimal money and fields', () {
    final DashboardSnapshot original = DashboardSnapshot.fromApi(body(), fetchedAt: fetchedAt);

    final DashboardSnapshot back = DashboardSnapshot.fromCache(original.toCache());

    expect(back.todayRevenue, original.todayRevenue);
    expect(back.recent.single.amount, Decimal.parse('1200.00'));
    expect(back.unreadNotifications, 3);
    expect(back.fetchedAt, fetchedAt);
  });
}
