import 'package:ownpay_console/features/permissions/data/consent_store.dart';
import 'package:ownpay_console/features/permissions/domain/sms_permission.dart';
import 'package:ownpay_console/features/sms_capture/domain/sms_capture.dart';
import 'package:ownpay_console/shared/models/raw_sms.dart';

/// In-memory [PermissionGate] for tests: returns a scripted result and records interactions, so the
/// disclosure flow can be verified without a device or the `permission_handler` plugin.
class FakePermissionGate implements PermissionGate {
  FakePermissionGate({
    this.requestResult = SmsPermission.denied,
    this.statusResult = SmsPermission.denied,
  });

  final SmsPermission requestResult;
  final SmsPermission statusResult;

  int notificationRequests = 0;
  int settingsOpens = 0;
  int smsRequests = 0;

  @override
  Future<SmsPermission> smsStatus() async => statusResult;

  @override
  Future<SmsPermission> requestSms() async {
    smsRequests++;
    return requestResult;
  }

  @override
  Future<bool> requestNotifications() async {
    notificationRequests++;
    return true;
  }

  @override
  Future<void> openSettings() async {
    settingsOpens++;
  }
}

/// In-memory [ConsentStore] for tests.
class FakeConsentStore implements ConsentStore {
  bool completed = false;

  @override
  Future<bool> isDisclosureCompleted() async => completed;

  @override
  Future<void> markDisclosureCompleted() async {
    completed = true;
  }
}

/// In-memory [SmsCapture] for tests: records control calls without touching platform channels.
class FakeSmsCapture implements SmsCapture {
  bool monitoring = false;
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<void> startMonitoring() async {
    startCalls++;
    monitoring = true;
  }

  @override
  Future<void> stopMonitoring() async {
    stopCalls++;
    monitoring = false;
  }

  @override
  Future<bool> isMonitoring() async => monitoring;

  @override
  Future<List<RawSms>> peekPending() async => const <RawSms>[];

  @override
  Future<void> ackProcessed(int count) async {}

  @override
  Stream<void> get onPending => const Stream<void>.empty();
}
