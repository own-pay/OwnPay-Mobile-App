/// On-device SMS permission state, normalized away from `permission_handler`'s richer enum so the
/// rest of the app (and its tests) never depend on the plugin's types directly.
enum SmsPermission { granted, denied, permanentlyDenied }

/// Abstraction over the platform permission APIs.
///
/// The default [PlatformPermissionGate] talks to `permission_handler`; tests substitute a fake so the
/// consent logic is verifiable without a device.
abstract interface class PermissionGate {
  /// Current SMS (READ_SMS / RECEIVE_SMS) permission state, without prompting the user.
  Future<SmsPermission> smsStatus();

  /// Prompts for SMS access. MUST be called only AFTER the user has seen the prominent disclosure
  /// (Play policy + DESIGN §4.2) — never as the first thing the user sees.
  Future<SmsPermission> requestSms();

  /// Best-effort POST_NOTIFICATIONS request (Android 13+) so the monitoring foreground-service
  /// notification is visible. Returns whether it ended up granted; callers should not block on it.
  Future<bool> requestNotifications();

  /// Opens the OS app-settings page — the only route back once a permission is permanently denied.
  Future<void> openSettings();
}
