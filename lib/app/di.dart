import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import '../core/config/app_config.dart';
import '../core/crypto/aes_gcm_cipher.dart';
import '../core/network/api_client.dart';
import '../core/network/auth_interceptor.dart';
import '../core/storage/secure_store.dart';
import '../features/pairing/data/device_repository.dart';
import '../features/permissions/data/consent_store.dart';
import '../features/permissions/data/platform_permission_gate.dart';
import '../features/permissions/domain/sms_permission.dart';

/// Service locator. Registration is manual (no codegen) and ordered so the AuthInterceptor can be
/// wired with a lazy reference to DeviceRepository.refresh without a construction cycle.
final GetIt sl = GetIt.instance;

Future<void> configureDependencies() async {
  if (sl.isRegistered<SecureStore>()) return;

  sl
    ..registerLazySingleton<FlutterSecureStorage>(() => const FlutterSecureStorage())
    ..registerLazySingleton<SecureStore>(() => SecureStore(sl<FlutterSecureStorage>()))
    ..registerLazySingleton<AesGcmCipher>(AesGcmCipher.new)
    ..registerLazySingleton<PermissionGate>(PlatformPermissionGate.new)
    ..registerLazySingleton<ConsentStore>(HiveConsentStore.new);

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

  // Interceptor refreshes via DeviceRepository, resolved lazily to avoid a construction cycle.
  dio.interceptors.add(
    AuthInterceptor(
      sl<SecureStore>(),
      dio,
      () => sl<DeviceRepository>().refresh(),
    ),
  );
}
