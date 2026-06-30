import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/error/failure.dart';
import 'package:ownpay_console/core/storage/secure_store.dart';
import 'package:ownpay_console/features/dashboard/domain/dashboard_repository.dart';
import 'package:ownpay_console/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:ownpay_console/features/dashboard/presentation/dashboard_cubit.dart';
import 'package:ownpay_console/features/dashboard/presentation/dashboard_screen.dart';

class _FakeRepo implements DashboardRepository {
  _FakeRepo(this.result);
  final DashboardResult result;

  @override
  Future<DashboardResult> load() async => result;
}

class _MockSecureStore extends Mock implements SecureStore {}

DashboardSnapshot fullSnap() => DashboardSnapshot.fromApi(
      <String, dynamic>{
        'today': <String, dynamic>{'revenue': '1500.50', 'total': 7, 'pending': 2},
        'recent_transactions': <Map<String, dynamic>>[
          <String, dynamic>{'trx_id': 'T1', 'amount': '1200.00', 'currency': 'BDT', 'status': 'completed', 'gateway': 'bkash', 'created_at': '2026-06-24T09:30:00+06:00'},
        ],
        'unread_notifications': 3,
      },
      fetchedAt: DateTime(2026, 6, 24, 10),
    );

Widget _host(DashboardCubit cubit) =>
    MaterialApp(home: BlocProvider<DashboardCubit>.value(value: cubit, child: const DashboardView()));

void main() {
  late _MockSecureStore store;

  setUp(() {
    store = _MockSecureStore();
    when(() => store.readServerUrl()).thenAnswer((_) async => 'https://pay.example.com');
  });

  testWidgets('renders today revenue (2dp) and a recent transaction', (WidgetTester tester) async {
    final DashboardCubit cubit = DashboardCubit(_FakeRepo(DashboardData(fullSnap(), fromCache: false)), store);
    await cubit.load();

    await tester.pumpWidget(_host(cubit));

    expect(find.textContaining('1500.50'), findsOneWidget); // revenue formatted to 2 decimals
    // The most-recent amount appears both in the "Last payment" tile and the recent-payments row.
    expect(find.textContaining('1200.00'), findsWidgets); // txn amount
    expect(find.textContaining('BKASH'), findsWidgets); // gateway badge (uppercased)
    expect(find.textContaining('Linked'), findsOneWidget); // host node pill = online
  });

  testWidgets('offline data shows the saved-data banner and an Offline pill', (WidgetTester tester) async {
    final DashboardCubit cubit = DashboardCubit(_FakeRepo(DashboardData(fullSnap(), fromCache: true)), store);
    await cubit.load();

    await tester.pumpWidget(_host(cubit));

    expect(find.textContaining('saved data as of'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget); // host node pill = offline
  });

  testWidgets('no data → error message with a Retry action', (WidgetTester tester) async {
    final DashboardCubit cubit = DashboardCubit(_FakeRepo(const DashboardUnavailable(NetworkFailure())), store);
    await cubit.load();

    await tester.pumpWidget(_host(cubit));

    expect(find.text('Retry'), findsOneWidget);
  });
}
