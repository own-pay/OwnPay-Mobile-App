import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';

/// Typed wrapper over the platform secure keystore (Android Keystore / iOS Keychain) for the only
/// secrets the app holds. Nothing here is ever written to Hive, logs, or backups.
class SecureStore {
  SecureStore(this._storage);

  final FlutterSecureStorage _storage;

  Future<void> saveCredentials({
    required String accessToken,
    required String refreshToken,
    required String aesKey,
    required String serverUrl,
    required String deviceUuid,
  }) async {
    await _storage.write(key: AppConfig.ssAccessToken, value: accessToken);
    await _storage.write(key: AppConfig.ssRefreshToken, value: refreshToken);
    await _storage.write(key: AppConfig.ssAesKey, value: aesKey);
    await _storage.write(key: AppConfig.ssServerUrl, value: serverUrl);
    await _storage.write(key: AppConfig.ssDeviceUuid, value: deviceUuid);
  }

  Future<String?> readAccessToken() => _storage.read(key: AppConfig.ssAccessToken);
  Future<String?> readRefreshToken() => _storage.read(key: AppConfig.ssRefreshToken);
  Future<String?> readAesKey() => _storage.read(key: AppConfig.ssAesKey);
  Future<String?> readServerUrl() => _storage.read(key: AppConfig.ssServerUrl);
  Future<String?> readDeviceUuid() => _storage.read(key: AppConfig.ssDeviceUuid);

  Future<void> setAccessToken(String value) => _storage.write(key: AppConfig.ssAccessToken, value: value);
  Future<void> setRefreshToken(String value) => _storage.write(key: AppConfig.ssRefreshToken, value: value);

  /// True once a device has paired (has both a server and an access token).
  Future<bool> isPaired() async {
    final String? server = await readServerUrl();
    final String? token = await readAccessToken();
    return server != null && server.isNotEmpty && token != null && token.isNotEmpty;
  }

  /// Returns a stable, locally-generated device id (persisted on first use). Sent at pairing so the
  /// server can pin this device. A future native enhancement can augment it with the signing-cert
  /// hash; this CSPRNG id is sufficient as a stable per-install identifier.
  Future<String> getOrCreateDeviceId() async {
    final String? existing = await _storage.read(key: AppConfig.ssDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final Random rng = Random.secure();
    final String id = List<String>.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
    await _storage.write(key: AppConfig.ssDeviceId, value: id);
    return id;
  }

  /// Secure-wipe everything (used on revoke / re-pair).
  Future<void> clear() => _storage.deleteAll();
}
