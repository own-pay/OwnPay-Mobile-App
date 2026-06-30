import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import '../core/config/app_config.dart';
import '../core/crypto/aes_gcm_cipher.dart';
import '../core/network/api_client.dart';
import '../core/network/auth_interceptor.dart';
import '../core/network/certificate_pinner.dart';
import '../core/services/app_refresh_signal.dart';
import '../core/services/session_status.dart';
import '../core/storage/local_wipe.dart';
import '../core/storage/secure_store.dart';
import '../features/audit/data/sms_body_revealer.dart';
import '../features/dashboard/data/dashboard_cache.dart';
import '../features/dashboard/data/network_dashboard_repository.dart';
import '../features/dashboard/domain/dashboard_repository.dart';
import '../features/pairing/data/device_heartbeat.dart';
import '../features/pairing/data/device_repository.dart';
import '../features/permissions/data/consent_store.dart';
import '../features/permissions/data/platform_permission_gate.dart';
import '../features/notifications/data/local_notifier.dart';
import '../features/notifications/data/network_notification_repository.dart';
import '../features/notifications/data/notification_poller.dart';
import '../features/notifications/domain/notification_repository.dart';
import '../features/notifications/domain/notifier.dart';
import '../features/permissions/domain/sms_permission.dart';
import '../features/privacy_gate/data/filter_rules_cache.dart';
import '../features/privacy_gate/data/network_filter_rules_repository.dart';
import '../features/privacy_gate/data/sender_overrides.dart';
import '../features/privacy_gate/domain/filter_rules_repository.dart';
import '../features/privacy_gate/domain/privacy_gate.dart';
import '../features/sms_capture/data/platform_sms_capture.dart';
import '../features/sms_capture/data/sms_ingest_coordinator.dart';
import '../features/sms_capture/domain/sms_capture.dart';
import '../features/sync/data/hive_sms_queue_store.dart';
import '../features/sync/data/sync_worker.dart';
import '../features/sync/domain/sms_queue_store.dart';
import '../features/sync/domain/syncer.dart';

/// Service locator. Registration is manual (no codegen) and ordered so the AuthInterceptor can be
/// wired with a lazy reference to DeviceRepository.refresh without a construction cycle.
final GetIt sl = GetIt.instance;

Future<void> configureDependencies() async {
  if (sl.isRegistered<SecureStore>()) return;

  sl
    ..registerLazySingleton<FlutterSecureStorage>(() => const FlutterSecureStorage())
    ..registerLazySingleton<SecureStore>(() => SecureStore(sl<FlutterSecureStorage>()))
    ..registerLazySingleton<LocalWipe>(() => LocalWipe(sl<SecureStore>()))
    ..registerLazySingleton<CertificatePinner>(() => CertificatePinner(sl<SecureStore>()))
    ..registerLazySingleton<AesGcmCipher>(AesGcmCipher.new)
    ..registerLazySingleton<SessionStatus>(SessionStatus.new)
    ..registerLazySingleton<AppRefreshSignal>(AppRefreshSignal.new)
    ..registerLazySingleton<PermissionGate>(PlatformPermissionGate.new)
    ..registerLazySingleton<ConsentStore>(HiveConsentStore.new)
    ..registerLazySingleton<SmsCapture>(PlatformSmsCapture.new);

  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
    ),
  );
  sl
    ..registerSingleton<Dio>(dio)
    ..registerLazySingleton<ApiClient>(() => ApiClient(sl<Dio>()))
    ..registerLazySingleton<DeviceRepository>(() => DeviceRepository(sl<ApiClient>(), sl<SecureStore>()));

  // Capture-consumer pipeline (increment 5): rules source → gate → encrypt → queue.
  sl
    ..registerLazySingleton<PrivacyGate>(() => const PrivacyGate())
    ..registerLazySingleton<FilterRulesCache>(HiveFilterRulesCache.new)
    ..registerLazySingleton<SenderOverrides>(HiveSenderOverrides.new)
    ..registerLazySingleton<FilterRulesRepository>(
      () => NetworkFilterRulesRepository(
        sl<ApiClient>(),
        sl<SecureStore>(),
        sl<FilterRulesCache>(),
      ),
    )
    ..registerLazySingleton<SmsQueueStore>(HiveSmsQueueStore.new)
    ..registerLazySingleton<SmsBodyRevealer>(
      () => SmsBodyRevealer(sl<SmsQueueStore>(), sl<SecureStore>(), sl<AesGcmCipher>()),
    )
    ..registerLazySingleton<NotificationRepository>(
      () => NetworkNotificationRepository(sl<ApiClient>(), sl<SecureStore>()),
    )
    ..registerLazySingleton<Notifier>(LocalNotifier.new)
    ..registerLazySingleton<NotificationPoller>(
      () => NotificationPoller(sl<NotificationRepository>(), sl<Notifier>()),
    )
    ..registerLazySingleton<DeviceHeartbeat>(
      () => DeviceHeartbeat(sl<ApiClient>(), sl<SecureStore>()),
    )
    ..registerLazySingleton<SyncWorker>(
      () => SyncWorker(
        sl<ApiClient>(),
        sl<SecureStore>(),
        sl<SmsQueueStore>(),
        // A 401 the interceptor can't refresh → flag re-auth so the router redirects to /pair.
        onReauthRequired: () => sl<SessionStatus>().requireReauth(),
      ),
    )
    ..registerLazySingleton<Syncer>(() => sl<SyncWorker>()) // same instance, exposed to presentation
    ..registerLazySingleton<DashboardCache>(HiveDashboardCache.new)
    ..registerLazySingleton<DashboardRepository>(
      () => NetworkDashboardRepository(sl<ApiClient>(), sl<SecureStore>(), sl<DashboardCache>()),
    )
    ..registerLazySingleton<SmsIngestCoordinator>(
      () => SmsIngestCoordinator(
        sl<SmsCapture>(),
        sl<FilterRulesRepository>(),
        sl<SmsQueueStore>(),
        sl<AesGcmCipher>(),
        sl<SecureStore>(),
        sl<SenderOverrides>(),
        sl<PrivacyGate>(),
        // Post-enqueue kick: a freshly captured + queued SMS triggers a sync immediately.
        () => unawaited(sl<SyncWorker>().syncNow()),
      ),
    );

  // Interceptor refreshes via DeviceRepository, resolved lazily to avoid a construction cycle.
  dio.interceptors.add(
    AuthInterceptor(
      sl<SecureStore>(),
      dio,
      () => sl<DeviceRepository>().refresh(),
    ),
  );

  // Release-only TLS certificate pinning (TOFU): trust only the leaf cert pinned on first connection.
  // Debug keeps normal CA validation so a local/self-hosted dev server works. (SECURITY.md §5.)
  if (kReleaseMode) {
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final HttpClient client = HttpClient(context: SecurityContext(withTrustedRoots: false));
        client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
        return client;
      },
      validateCertificate: (X509Certificate? cert, String host, int port) =>
          sl<CertificatePinner>().allows(cert),
    );
  }
}
