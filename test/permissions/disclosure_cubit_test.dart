import 'package:flutter_test/flutter_test.dart';
import 'package:ownpay_console/features/permissions/domain/sms_permission.dart';
import 'package:ownpay_console/features/permissions/presentation/disclosure_cubit.dart';

import 'permission_fakes.dart';

void main() {
  group('DisclosureCubit', () {
    test('allow() granted → granted, consent marked, notifications + capture started', () async {
      final FakePermissionGate gate = FakePermissionGate(requestResult: SmsPermission.granted);
      final FakeConsentStore consent = FakeConsentStore();
      final FakeSmsCapture capture = FakeSmsCapture();
      final DisclosureCubit cubit = DisclosureCubit(gate, consent, capture);

      await cubit.allow();

      expect(cubit.state.phase, DisclosurePhase.granted);
      expect(cubit.state.isResolved, isTrue);
      expect(consent.completed, isTrue);
      expect(gate.smsRequests, 1);
      expect(gate.notificationRequests, 1);
      expect(capture.startCalls, 1);
    });

    test('allow() denied → denied, consent NOT marked, capture NOT started', () async {
      final FakePermissionGate gate = FakePermissionGate(requestResult: SmsPermission.denied);
      final FakeConsentStore consent = FakeConsentStore();
      final FakeSmsCapture capture = FakeSmsCapture();
      final DisclosureCubit cubit = DisclosureCubit(gate, consent, capture);

      await cubit.allow();

      expect(cubit.state.phase, DisclosurePhase.denied);
      expect(cubit.state.isResolved, isFalse);
      expect(consent.completed, isFalse);
      expect(gate.notificationRequests, 0);
      expect(capture.startCalls, 0);
    });

    test('allow() permanentlyDenied → permanentlyDenied, consent NOT marked, capture NOT started', () async {
      final FakePermissionGate gate =
          FakePermissionGate(requestResult: SmsPermission.permanentlyDenied);
      final FakeConsentStore consent = FakeConsentStore();
      final FakeSmsCapture capture = FakeSmsCapture();
      final DisclosureCubit cubit = DisclosureCubit(gate, consent, capture);

      await cubit.allow();

      expect(cubit.state.phase, DisclosurePhase.permanentlyDenied);
      expect(consent.completed, isFalse);
      expect(capture.startCalls, 0);
    });

    test('declineForNow() → declined, consent marked, capture NOT started (manual mode)', () async {
      final FakePermissionGate gate = FakePermissionGate();
      final FakeConsentStore consent = FakeConsentStore();
      final FakeSmsCapture capture = FakeSmsCapture();
      final DisclosureCubit cubit = DisclosureCubit(gate, consent, capture);

      await cubit.declineForNow();

      expect(cubit.state.phase, DisclosurePhase.declined);
      expect(cubit.state.isResolved, isTrue);
      expect(consent.completed, isTrue);
      expect(gate.smsRequests, 0);
      expect(capture.startCalls, 0);
    });

    test('openSettings() delegates to the gate', () async {
      final FakePermissionGate gate =
          FakePermissionGate(requestResult: SmsPermission.permanentlyDenied);
      final DisclosureCubit cubit = DisclosureCubit(gate, FakeConsentStore(), FakeSmsCapture());

      await cubit.openSettings();

      expect(gate.settingsOpens, 1);
    });

    test('emits requesting before settling', () async {
      final FakePermissionGate gate = FakePermissionGate(requestResult: SmsPermission.granted);
      final DisclosureCubit cubit = DisclosureCubit(gate, FakeConsentStore(), FakeSmsCapture());
      final List<DisclosurePhase> seen = <DisclosurePhase>[];
      cubit.stream.listen((DisclosureState s) => seen.add(s.phase));

      await cubit.allow();
      await Future<void>.delayed(Duration.zero);

      expect(seen, <DisclosurePhase>[DisclosurePhase.requesting, DisclosurePhase.granted]);
    });
  });
}
