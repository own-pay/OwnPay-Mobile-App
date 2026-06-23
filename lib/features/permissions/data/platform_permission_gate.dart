import 'package:permission_handler/permission_handler.dart';

import '../domain/sms_permission.dart';

/// [PermissionGate] backed by `permission_handler`.
///
/// `Permission.sms` is the Android SMS permission *group*; granting it covers the manifest's
/// `READ_SMS` + `RECEIVE_SMS` (both live in that group), so a single request is sufficient.
class PlatformPermissionGate implements PermissionGate {
  const PlatformPermissionGate();

  @override
  Future<SmsPermission> smsStatus() async => _map(await Permission.sms.status);

  @override
  Future<SmsPermission> requestSms() async => _map(await Permission.sms.request());

  @override
  Future<bool> requestNotifications() async => (await Permission.notification.request()).isGranted;

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }

  /// Collapse the plugin's status into our three-state model. `restricted` (OS-level block, e.g.
  /// parental controls) is treated like a permanent denial because the in-app request cannot resolve
  /// it — only a settings/OS change can.
  SmsPermission _map(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return SmsPermission.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return SmsPermission.permanentlyDenied;
    }
    return SmsPermission.denied;
  }
}
