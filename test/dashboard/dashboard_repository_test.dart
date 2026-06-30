import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/error/failure.dart';
import 'package:ownpay_console/core/network/api_client.dart';
import 'package:ownpay_console/core/network/api_result.dart';
import 'package:ownpay_console/core/storage/secure_store.dart';
import 'package:ownpay_console/features/dashboard/data/dashboard_cache.dart';
import 'package:ownpay_console/features/dashboard/data/network_dashboard_repository.dart';
import 'package:ownpay_console/features/dashboard/domain/dashboard_repository.dart';
import 'package:ownpay_console/features/dashboard/domain/dashboard_snapshot.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockSecureStore extends Mock implements SecureStore {}

class _FakeCache implements DashboardCache {
  DashboardSnapshot? stored;
  int writes = 0;

  @override
  Future<DashboardSnapshot?> read() async => stored;

  @override
  Future<void> write(DashboardSnapshot snapshot) async {
    stored = snapshot;
    writes++;
  }
}

void main() {
  late _MockApiClient api;
  late _MockSecureStore store;
  late _FakeCache cache;

  DateTime now() => DateTime(2026, 6, 24, 10);

  NetworkDashboardRepository build() => NetworkDashboardRepository(api, store, cache, now);

  Map<String, dynamic> dashboardBody() => <String, dynamic>{
        'today': <String, dynamic>{'revenue': '1500.50', 'total': 7, 'pending': 2},
        'recent_transactions': <Map<String, dynamic>>[
          <String, dynamic>{'trx_id': 'T1', 'amount': '1200.00', 'currency': 'BDT', 'status': 'completed', 'gateway': 'bkash', 'created_at': '2026-06-24T09:30:00+06:00'},
        ],
        'unread_notifications': 3,
        'server_time': '2026-06-24T10:00:00Z',
      };

  DashboardSnapshot cached() => DashboardSnapshot.fromApi(
        <String, dynamic>{'today': <String, dynamic>{'revenue': '99.00'}},
        fetchedAt: DateTime(2026, 6, 23),
      );

  setUp(() {
    api = _MockApiClient();
    store = _MockSecureStore();
    cache = _FakeCache();
    when(() => store.readServerUrl()).thenAnswer((_) async => 'https://srv.example');
  });

  test('online → fresh DashboardData (fromCache false) and writes the cache', () async {
    when(() => api.get(any())).thenAnswer((_) async => Ok<Map<String, dynamic>>(dashboardBody()));

    final DashboardResult result = await build().load();

    expect(result, isA<DashboardData>());
    final DashboardData data = result as DashboardData;
    expect(data.fromCache, isFalse);
    expect(data.snapshot.todayRevenue, Decimal.parse('1500.50'));
    expect(data.snapshot.fetchedAt, now());
    expect(cache.writes, 1);
  });

  test('offline with a cached snapshot → DashboardData(fromCache true)', () async {
    cache.stored = cached();
    when(() => api.get(any())).thenAnswer((_) async => const Err<Map<String, dynamic>>(NetworkFailure()));

    final DashboardResult result = await build().load();

    expect(result, isA<DashboardData>());
    final DashboardData data = result as DashboardData;
    expect(data.fromCache, isTrue);
    expect(data.snapshot.todayRevenue, Decimal.parse('99.00'));
    expect(cache.writes, 0); // a failed fetch must not overwrite the cache
  });

  test('offline with no cache → DashboardUnavailable carrying the failure', () async {
    when(() => api.get(any())).thenAnswer((_) async => const Err<Map<String, dynamic>>(NetworkFailure()));

    final DashboardResult result = await build().load();

    expect(result, isA<DashboardUnavailable>());
    expect((result as DashboardUnavailable).failure, isA<NetworkFailure>());
  });

  test('not paired (no server url) → serves cache if present, else unavailable', () async {
    when(() => store.readServerUrl()).thenAnswer((_) async => null);
    cache.stored = cached();

    final DashboardResult result = await build().load();

    expect(result, isA<DashboardData>());
    expect((result as DashboardData).fromCache, isTrue);
    verifyNever(() => api.get(any()));
  });
}
