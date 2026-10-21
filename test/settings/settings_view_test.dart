import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/network/api_result.dart';
import 'package:ownpay_console/core/storage/local_wipe.dart';
import 'package:ownpay_console/core/storage/secure_store.dart';
import 'package:ownpay_console/features/pairing/data/device_repository.dart';
import 'package:ownpay_console/features/privacy_gate/data/sender_overrides.dart';
import 'package:ownpay_console/features/privacy_gate/domain/filter_rules_repository.dart';
import 'package:ownpay_console/features/settings/presentation/settings_cubit.dart';
import 'package:ownpay_console/features/settings/presentation/settings_screen.dart';

class _MockSecureStore extends Mock implements SecureStore {}

class _MockDeviceRepository extends Mock implements DeviceRepository {}

class _MockLocalWipe extends Mock implements LocalWipe {}

class _MockRules extends Mock implements FilterRulesRepository {}

class _MockOverrides extends Mock implements SenderOverrides {}

Widget _host(SettingsCubit cubit) {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            BlocProvider<SettingsCubit>.value(value: cubit, child: const SettingsView()),
      ),
      GoRoute(
        path: '/pair',
        builder: (BuildContext context, GoRouterState state) =>
            const Scaffold(body: Center(child: Text('PAIR SCREEN'))),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  late _MockSecureStore store;
  late _MockDeviceRepository devices;
  late _MockLocalWipe wipe;
  late _MockRules rules;
  late _MockOverrides overrides;

  setUp(() {
    store = _MockSecureStore();
    devices = _MockDeviceRepository();
    wipe = _MockLocalWipe();
    rules = _MockRules();
    overrides = _MockOverrides();
    when(() => store.readServerUrl()).thenAnswer((_) async => 'https://srv.example');
    when(() => store.readDeviceUuid()).thenAnswer((_) async => 'uuid-1');
    when(() => devices.revoke()).thenAnswer((_) async => const Ok<void>(null));
    when(() => wipe.wipe()).thenAnswer((_) async {});
    when(() => rules.effectiveRules()).thenAnswer((_) async => null);
    when(() => overrides.disabled()).thenAnswer((_) async => <String>{});
  });

  SettingsCubit cubit() => SettingsCubit(store, devices, wipe, rules, overrides)..load();

  testWidgets('renders device info and the actions', (WidgetTester tester) async {
    await tester.pumpWidget(_host(cubit()));
    await tester.pumpAndSettle();

    expect(find.text('https://srv.example'), findsOneWidget);
    expect(find.text('uuid-1'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Re-pair device'), 300);
    expect(find.text('Re-pair device'), findsOneWidget);
    expect(find.text('Revoke & wipe this device'), findsOneWidget);
    expect(find.text('SMS DELIVERY'), findsOneWidget);
    expect(find.textContaining('Checking SMS sources'), findsOneWidget);
  });

  testWidgets('revoke & wipe → confirm → wipes locally and navigates to /pair', (WidgetTester tester) async {
    await tester.pumpWidget(_host(cubit()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Revoke & wipe this device'), 300);
    await tester.tap(find.text('Revoke & wipe this device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase')); // confirm in the dialog
    await tester.pumpAndSettle();

    verify(() => devices.revoke()).called(1);
    verify(() => wipe.wipe()).called(1);
    expect(find.text('PAIR SCREEN'), findsOneWidget); // redirected after wipe
  });
}
