/// Compile-time/app-wide constants. No secrets here — the server URL and credentials are set at
/// pairing and live in secure storage.
class AppConfig {
  const AppConfig._();

  /// Mobile API path prefix (joined onto the paired server origin).
  static const String apiPrefix = '/api/mobile/v1';

  /// App version reported at pairing (keep in sync with pubspec `version`).
  static const String appVersion = '1.0.0';

  /// Notification poll cadence (server may override via dashboard config).
  static const Duration notificationPollInterval = Duration(seconds: 12);

  /// Default privacy-rules refresh cadence (server value in `check_interval_hours` wins).
  static const Duration defaultFilterRulesRefresh = Duration(hours: 24);

  /// HTTP timeouts.
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// Offline-queue retention for successfully-synced rows.
  static const Duration syncedRetention = Duration(days: 30);

  /// Hive box names.
  static const String boxSmsQueue = 'sms_queue';
  static const String boxFilterRules = 'filter_rules';
  static const String boxDashboardCache = 'dashboard_cache';
  static const String boxAuditLog = 'audit_log';

  /// Non-secret app settings / onboarding flags (e.g. disclosure-completed).
  static const String boxSettings = 'app_settings';

  /// Secure-storage keys.
  static const String ssAccessToken = 'access_token';
  static const String ssRefreshToken = 'refresh_token';
  static const String ssAesKey = 'aes_key';
  static const String ssServerUrl = 'server_url';
  static const String ssDeviceUuid = 'device_uuid';
  static const String ssDeviceId = 'device_id_local';
}
