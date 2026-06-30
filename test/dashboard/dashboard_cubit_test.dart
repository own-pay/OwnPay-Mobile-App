import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/error/failure.dart';
import 'package:ownpay_console/core/storage/secure_store.dart';
import 'package:ownpay_console/features/dashboard/domain/dashboard_repository.dart';
import 'package:ownpay_console/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:ownpay_console/features/dashboard/presentation/dashboard_cubit.dart';

class _FakeRepo implements DashboardRepository {
  _FakeRepo(this.result);
  DashboardResult result;

  @override
  Future<DashboardResult> load() async => result;
}

class _MockSecureStore extends Mock implements SecureStore {}

DashboardSnapshot snap() => DashboardSnapshot.fromApi(
      <String, dynamic>{'today': <String, dynamic>{'revenue': '10.00', 'total': 1, 'pending': 0}},
      fetchedAt: DateTime(2026, 6, 24),
    );

void main() {
  late _MockSecureStore store;

  setUp(() {
    store = _MockSecureStore();
    when(() => store.readServerUrl()).thenAnswer((_) async => 'https://srv.example');
  });

  test('load → loaded with fresh data (not offline)', () async {
    final DashboardCubit cubit = DashboardCubit(_FakeRepo(DashboardData(snap(), fromCache: false)), store);

    await cubit.load();

    expect(cubit.state.loading, isFalse);
    expect(cubit.state.hasData, isTrue);
    expect(cubit.state.offline, isFalse);
    expect(cubit.state.snapshot!.todayTotal, 1);
  });

  test('load → loaded from cache marks offline', () async {
    final DashboardCubit cubit = DashboardCubit(_FakeRepo(DashboardData(snap(), fromCache: true)), store);

    await cubit.load();

    expect(cubit.state.hasData, isTrue);
    expect(cubit.state.offline, isTrue);
  });

  test('load → error when unavailable (no snapshot, failure set)', () async {
    final DashboardCubit cubit =
        DashboardCubit(_FakeRepo(const DashboardUnavailable(NetworkFailure())), store);

    await cubit.load();

    expect(cubit.state.loading, isFalse);
    expect(cubit.state.hasData, isFalse);
    expect(cubit.state.failure, isA<NetworkFailure>());
  });
}
