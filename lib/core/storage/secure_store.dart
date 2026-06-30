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

  /// TOFU-pinned server certificate fingerprint (release cert pinning). Cleared by [clear] on wipe, so a
  /// re-pair re-pins (the documented re-pin path for server cert rotation).
  Future<String?> readCertPin() => _storage.read(key: AppConfig.ssCertPin);
  Future<void> setCertPin(String value) => _storage.write(key: AppConfig.ssCertPin, value: value);

  /// True once a device has paired (has both a server and an access token).
  Future<bool> isPaired() async {
    final String? server = await readServerUrl();
    final String? token = await readAccessToken();
    return server != null && server.isNotEmpty && token != null && token.isNotEmpty;
  }

  Future<String>? _deviceIdInFlight;

  /// Returns a stable, locally-generated device id (persisted on first use). Sent at pairing so the
  /// server can pin this device. A future native enhancement can augment it with the signing-cert
  /// hash; this CSPRNG id is sufficient as a stable per-install identifier.
  ///
  /// Single-flight: concurrent first-callers share one in-flight read/create, so two simultaneous
  /// callers can never mint and persist two different ids.
  Future<String> getOrCreateDeviceId() => _deviceIdInFlight ??= _readOrCreateDeviceId();

  Future<String> _readOrCreateDeviceId() async {
    final String? existing = await _storage.read(key: AppConfig.ssDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final Random rng = Random.secure();
    final String id = List<String>.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
    await _storage.write(key: AppConfig.ssDeviceId, value: id);
    return id;
  }

  /// Secure-wipe everything (used on revoke / re-pair). Also drops the cached device-id future so a
  /// subsequent pair mints a fresh id (the documented re-pair behavior).
  Future<void> clear() async {
    _deviceIdInFlight = null;
    await _storage.deleteAll();
  }
}
