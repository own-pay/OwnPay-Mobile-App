import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ownpay_console/core/error/failure.dart';
import 'package:ownpay_console/core/network/api_result.dart';
import 'package:ownpay_console/core/services/session_status.dart';
import 'package:ownpay_console/features/pairing/data/device_repository.dart';
import 'package:ownpay_console/features/pairing/presentation/pairing_cubit.dart';

class _MockDeviceRepository extends Mock implements DeviceRepository {}

void main() {
  late _MockDeviceRepository devices;
  late SessionStatus session;

  setUp(() {
    devices = _MockDeviceRepository();
    session = SessionStatus()..requireReauth(); // pretend a re-auth was pending
  });

  PairingCubit build() => PairingCubit(devices, session);

  void stubPair(ApiResult<void> result) {
    when(() => devices.pair(
          serverUrl: any(named: 'serverUrl'),
          otp: any(named: 'otp'),
          deviceName: any(named: 'deviceName'),
        )).thenAnswer((_) async => result);
  }

  test('successful pair → success state and clears the re-auth flag', () async {
    stubPair(const Ok<void>(null));

    final PairingCubit cubit = build();
    await cubit.pair(serverUrl: 'https://srv', otp: '482910', deviceName: 'Pixel');

    expect(cubit.state.status, PairingStatus.success);
    expect(session.reauthRequired.value, isFalse);
  });

  test('failed pair → failure state and leaves the re-auth flag set', () async {
    stubPair(const Err<void>(ValidationFailure(message: 'bad otp')));

    final PairingCubit cubit = build();
    await cubit.pair(serverUrl: 'https://srv', otp: 'bad', deviceName: 'Pixel');

    expect(cubit.state.status, PairingStatus.failure);
    expect(cubit.state.error, 'bad otp');
    expect(session.reauthRequired.value, isTrue);
  });

  test('empty inputs → failure without calling the repository', () async {
    final PairingCubit cubit = build();

    await cubit.pair(serverUrl: '', otp: '', deviceName: 'X');

    expect(cubit.state.status, PairingStatus.failure);
    verifyNever(() => devices.pair(
          serverUrl: any(named: 'serverUrl'),
          otp: any(named: 'otp'),
          deviceName: any(named: 'deviceName'),
        ));
  });
}
