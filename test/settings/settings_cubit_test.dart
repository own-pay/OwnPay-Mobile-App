import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/error/failure.dart';
import 'package:ownpay_console/core/network/api_result.dart';
import 'package:ownpay_console/core/storage/local_wipe.dart';
import 'package:ownpay_console/core/storage/secure_store.dart';
import 'package:ownpay_console/features/pairing/data/device_repository.dart';
import 'package:ownpay_console/features/privacy_gate/data/sender_overrides.dart';
import 'package:ownpay_console/features/privacy_gate/domain/filter_rules_repository.dart';
import 'package:ownpay_console/features/settings/presentation/settings_cubit.dart';

class _MockSecureStore extends Mock implements SecureStore {}

class _MockDeviceRepository extends Mock implements DeviceRepository {}

class _MockLocalWipe extends Mock implements LocalWipe {}

class _MockRules extends Mock implements FilterRulesRepository {}

class _MockOverrides extends Mock implements SenderOverrides {}

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
}
