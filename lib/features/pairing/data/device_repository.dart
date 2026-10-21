import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_result.dart';
import '../../../core/storage/secure_store.dart';

/// Device pairing + token refresh against the bootstrap endpoints (`auth: false`).
class DeviceRepository {
  DeviceRepository(this._api, this._store, {bool Function()? isReleaseMode})
      : _isReleaseMode = isReleaseMode ?? (() => kReleaseMode);

  final ApiClient _api;
  final SecureStore _store;
  final bool Function() _isReleaseMode;

  /// Pairs with the scanned/entered server using the one-time OTP. On success, persists the issued
  /// credentials (tokens, AES key, server URL, device uuid) to secure storage.
  Future<ApiResult<void>> pair({
    required String serverUrl,
    required String otp,
    required String deviceName,
  }) async {
    final String base = _normalizeBase(serverUrl);
    if (base.isEmpty) {
      return const Err<void>(ValidationFailure(message: 'Enter a valid server URL.'));
    }
    if (_isReleaseMode() && !base.startsWith('https://')) {
      return const Err<void>(ValidationFailure(message: 'Production pairing requires an HTTPS server URL.'));
    }

    final String deviceId = await _store.getOrCreateDeviceId();
    final ApiResult<Map<String, dynamic>> res = await _api.post(
      '$base${AppConfig.apiPrefix}/devices',
      auth: false,
      body: <String, dynamic>{
        'pairing_code': otp,
        'device_name': deviceName,
        'device_id': deviceId,
        'app_version': AppConfig.appVersion,
        'platform': 'android',
      },
    );

    switch (res) {
      case Err<Map<String, dynamic>>(:final Failure failure):
        return Err<void>(failure);
      case Ok<Map<String, dynamic>>(:final Map<String, dynamic> value):
        final String accessToken = _str(value, 'access_token');
        final String refreshToken = _str(value, 'refresh_token');
        final String aesKey = _str(value, 'aes_key');
        final String deviceUuid = _str(value, 'device_uuid');
        if (accessToken.isEmpty || refreshToken.isEmpty || aesKey.isEmpty) {
          return const Err<void>(ValidationFailure(message: 'The pairing response was incomplete.'));
        }
        await _store.saveCredentials(
          accessToken: accessToken,
          refreshToken: refreshToken,
          aesKey: aesKey,
          serverUrl: base,
          deviceUuid: deviceUuid,
        );
        return const Ok<void>(null);
    }
  }

  /// Rotates the access token using the stored refresh token. Used by the AuthInterceptor on 401.
  /// Returns false on any failure (caller surfaces re-pair).
  Future<bool> refresh() async {
    final String? base = await _store.readServerUrl();
    final String? refreshToken = await _store.readRefreshToken();
    if (base == null || base.isEmpty || refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    // The server re-checks the device fingerprint it bound at pairing (sha256 of the device id). Send
    // the same stable id we paired with, or refresh is rejected (FINGERPRINT_REQUIRED/MISMATCH → 422).
    final String deviceId = await _store.getOrCreateDeviceId();
    final ApiResult<Map<String, dynamic>> res = await _api.post(
      '$base${AppConfig.apiPrefix}/devices/token-refreshes',
      auth: false,
      body: <String, dynamic>{'refresh_token': refreshToken, 'fingerprint': deviceId},
    );

    switch (res) {
      case Err<Map<String, dynamic>>():
        return false;
      case Ok<Map<String, dynamic>>(:final Map<String, dynamic> value):
        final String access = _str(value, 'access_token');
        if (access.isEmpty) return false;
        await _store.setAccessToken(access);
        final String rotated = _str(value, 'refresh_token');
        if (rotated.isNotEmpty) await _store.setRefreshToken(rotated);
        return true;
    }
  }

  /// Self-revokes this device on the server (authenticated `DELETE /devices/{id}`). The server identifies
  /// the device from the JWT, so `{id}` carries our stored uuid for clarity. Best-effort: the settings
  /// "revoke & wipe" flow clears local data regardless of the result.
  Future<ApiResult<void>> revoke() async {
    final String? base = await _store.readServerUrl();
    if (base == null || base.isEmpty) {
      return const Err<void>(ValidationFailure(message: 'This device is not paired.'));
    }
    final String? uuid = await _store.readDeviceUuid();
    final String id = (uuid != null && uuid.isNotEmpty) ? uuid : 'self';
    final ApiResult<Map<String, dynamic>> res =
        await _api.delete('$base${AppConfig.apiPrefix}/devices/$id');
    return res.fold<ApiResult<void>>(
      (Failure failure) => Err<void>(failure),
      (Map<String, dynamic> _) => const Ok<void>(null),
    );
  }

  /// Normalizes a user-entered/scanned origin: adds https:// if no scheme, strips trailing slashes,
  /// and validates it parses to a real host. Returns '' if invalid.
  String _normalizeBase(String input) {
    String s = input.trim();
    if (s.isEmpty) return '';
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    final Uri? uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return '';
    return s;
  }

  String _str(Map<String, dynamic> m, String key) {
    final Object? v = m[key];
    if (v is String) return v;
    return v == null ? '' : '$v';
  }
}
