import 'dart:async';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_store.dart';

/// Periodically pings `POST /devices/heartbeat` so the server — and its admin panel — sees this device
/// as connected. The server's "online" window is short (a few minutes), so a device that never beats is
/// shown as **Idle**. Beats only while paired; best-effort — a missed beat (offline / mid-refresh) is
/// harmless and the next beat restores the live status.
class DeviceHeartbeat {
  DeviceHeartbeat(this._api, this._store);

  final ApiClient _api;
  final SecureStore _store;

  Timer? _timer;

  /// Starts the periodic heartbeat (idempotent — keeps a single timer) and sends one immediately, so the
  /// device shows online right away on launch/resume instead of after the first interval.
  void start() {
    _timer ??= Timer.periodic(AppConfig.heartbeatInterval, (_) => unawaited(beat()));
    unawaited(beat());
  }

  /// Stops beating. Safe to call when not started.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Sends a single heartbeat when paired. No-ops when unpaired; the call returns a typed result rather
  /// than throwing, so the ignored result simply means a best-effort liveness ping.
  Future<void> beat() async {
    final String? base = await _store.readServerUrl();
    if (base == null || base.isEmpty) {
      return;
    }
    await _api.post('$base${AppConfig.apiPrefix}/devices/heartbeats', body: const <String, dynamic>{});
  }
}
