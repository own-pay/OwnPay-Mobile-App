import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/error/failure.dart';
import 'package:ownpay_console/core/network/api_result.dart';
import 'package:ownpay_console/core/storage/local_wipe.dart';
import 'package:ownpay_console/core/storage/secure_store.dart';
import 'package:ownpay_console/features/pairing/data/device_repository.dart';
import 'package:ownpay_console/features/privacy_gate/data/sender_overrides.dart';
import 'package:ownpay_console/features/privacy_gate/domain/filter_rules.dart';
import 'package:ownpay_console/features/privacy_gate/domain/filter_rules_health.dart';
import 'package:ownpay_console/features/privacy_gate/domain/filter_rules_repository.dart';
import 'package:ownpay_console/features/settings/presentation/settings_cubit.dart';

class _MockSecureStore extends Mock implements SecureStore {}

class _MockDeviceRepository extends Mock implements DeviceRepository {}

class _MockLocalWipe extends Mock implements LocalWipe {}

class _MockRules extends Mock implements FilterRulesRepository {}

class _MockOverrides extends Mock implements SenderOverrides {}

class _FakeRulesWithHealth implements FilterRulesRepository, FilterRulesHealthSource {
  _FakeRulesWithHealth({
    required this.forceResult,
    required FilterRulesHealthStatus forceStatus,
    this.effectiveResult,
    this.throwOnForce = false,
  }) : _health = ValueNotifier<FilterRulesHealthSnapshot>(
          FilterRulesHealthSnapshot(status: forceStatus, message: forceStatus.name),
        );

  final FilterRules? forceResult;
  final FilterRules? effectiveResult;
  final bool throwOnForce;
  final ValueNotifier<FilterRulesHealthSnapshot> _health;
  int effectiveCalls = 0;

  @override
  ValueListenable<FilterRulesHealthSnapshot> get health => _health;

  @override
  Future<FilterRules?> effectiveRules() async {
    effectiveCalls++;
    return effectiveResult;
  }

  @override
  Future<FilterRules?> forceRefresh() async {
    if (throwOnForce) throw StateError('refresh failed');
    return forceResult;
  }
}

FilterRules usableRules() => FilterRules(
      version: 1,
      allowedSenders: const <String>['bKash'],
      positiveKeywords: const <String>[],
      negativeKeywords: const <String>[],
      checkIntervalHours: 24,
      fetchedAt: DateTime(2026, 6, 23),
    );

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
    when(() => wipe.wipe()).thenAnswer((_) async {});
    when(() => rules.effectiveRules()).thenAnswer((_) async => null);
    when(() => overrides.disabled()).thenAnswer((_) async => <String>{});
  });

  SettingsCubit build() => SettingsCubit(store, devices, wipe, rules, overrides);

  test('load reads device info from secure storage', () async {
    when(() => store.readServerUrl()).thenAnswer((_) async => 'https://srv');
    when(() => store.readDeviceUuid()).thenAnswer((_) async => 'uuid-1');

    final SettingsCubit cubit = build();
    await cubit.load();

    expect(cubit.state.serverUrl, 'https://srv');
    expect(cubit.state.deviceUuid, 'uuid-1');
  });

  test('revokeAndWipe revokes then wipes, ending in wiped', () async {
    when(() => devices.revoke()).thenAnswer((_) async => const Ok<void>(null));

    final SettingsCubit cubit = build();
    await cubit.revokeAndWipe();

    verify(() => devices.revoke()).called(1);
    verify(() => wipe.wipe()).called(1);
    expect(cubit.state.status, SettingsStatus.wiped);
  });

  test('revokeAndWipe wipes even when the server revoke fails (best-effort)', () async {
    when(() => devices.revoke()).thenAnswer((_) async => const Err<void>(NetworkFailure()));

    final SettingsCubit cubit = build();
    await cubit.revokeAndWipe();

    verify(() => wipe.wipe()).called(1); // local wipe must happen regardless
    expect(cubit.state.status, SettingsStatus.wiped);
  });

  test('does not fall back to an old whitelist after an explicit empty refresh', () async {
    final _FakeRulesWithHealth fake = _FakeRulesWithHealth(
      forceResult: null,
      forceStatus: FilterRulesHealthStatus.empty,
      effectiveResult: usableRules(),
    );
    final SettingsCubit cubit = SettingsCubit(
      store,
      devices,
      wipe,
      fake,
      overrides,
      rulesHealth: fake,
    );

    await cubit.syncFromAdmin();

    expect(fake.effectiveCalls, 0);
    expect(cubit.state.senders, isEmpty);
    expect(cubit.state.rulesHealth.status, FilterRulesHealthStatus.empty);
    expect(cubit.state.syncing, isFalse);
  });

  test('clears syncing state when refresh throws', () async {
    final _FakeRulesWithHealth fake = _FakeRulesWithHealth(
      forceResult: null,
      forceStatus: FilterRulesHealthStatus.unavailable,
      throwOnForce: true,
    );
    final SettingsCubit cubit = SettingsCubit(
      store,
      devices,
      wipe,
      fake,
      overrides,
      rulesHealth: fake,
    );

    await expectLater(cubit.syncFromAdmin(), throwsStateError);
    expect(cubit.state.syncing, isFalse);
  });

  test('health listeners update state and are removed when the Cubit closes', () async {
    final _FakeRulesWithHealth fake = _FakeRulesWithHealth(
      forceResult: null,
      forceStatus: FilterRulesHealthStatus.empty,
    );
    final SettingsCubit cubit = SettingsCubit(
      store,
      devices,
      wipe,
      fake,
      overrides,
      rulesHealth: fake,
    );

    fake._health.value = const FilterRulesHealthSnapshot(
      status: FilterRulesHealthStatus.ready,
      message: 'ready',
    );
    expect(cubit.state.rulesHealth.status, FilterRulesHealthStatus.ready);

    await cubit.close();
    fake._health.value = const FilterRulesHealthSnapshot(
      status: FilterRulesHealthStatus.empty,
      message: 'empty',
    );
    expect(cubit.state.rulesHealth.status, FilterRulesHealthStatus.ready);
  });
}
