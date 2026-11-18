import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/storage/local_wipe.dart';
import '../../../core/storage/secure_store.dart';
import '../../pairing/data/device_repository.dart';
import '../../privacy_gate/data/sender_overrides.dart';
import '../../privacy_gate/domain/filter_rules.dart';
import '../../privacy_gate/domain/filter_rules_repository.dart';
import '../../sms_capture/domain/sms_capture.dart';

enum SettingsStatus { idle, wiping, wiped }

class SettingsState extends Equatable {
  const SettingsState({
    this.serverUrl,
    this.deviceUuid,
    this.status = SettingsStatus.idle,
    this.senders = const <String>[],
    this.disabledSenders = const <String>{},
    this.rulesLoaded = false,
    this.syncing = false,
    this.droppedCount = 0,
  });

  final String? serverUrl;
  final String? deviceUuid;
  final SettingsStatus status;

  /// The server-whitelisted senders (from the privacy-gate rules) shown as toggles.
  final List<String> senders;

  /// Locally-disabled senders (lowercased) — a subtractive on-device override.
  final Set<String> disabledSenders;

  /// True once the sender list has been loaded at least once (distinguishes "none configured" from
  /// "not loaded yet").
  final bool rulesLoaded;

  /// True while a "sync from admin panel" force-refresh is in flight.
  final bool syncing;

  /// Lifetime count of SMS the native layer dropped (overflow + not-in-whitelist). Surfaced as a
  /// visible warning on this screen and recomputed on every load.
  final int droppedCount;

  /// Whether [sender] is currently active on this device (server-whitelisted AND not locally disabled).
  bool isEnabled(String sender) => !disabledSenders.contains(sender.trim().toLowerCase());

  SettingsState copyWith({
    String? serverUrl,
    String? deviceUuid,
    SettingsStatus? status,
    List<String>? senders,
    Set<String>? disabledSenders,
    bool? rulesLoaded,
    bool? syncing,
    int? droppedCount,
  }) =>
      SettingsState(
        serverUrl: serverUrl ?? this.serverUrl,
        deviceUuid: deviceUuid ?? this.deviceUuid,
        status: status ?? this.status,
        senders: senders ?? this.senders,
        disabledSenders: disabledSenders ?? this.disabledSenders,
        rulesLoaded: rulesLoaded ?? this.rulesLoaded,
        syncing: syncing ?? this.syncing,
        droppedCount: droppedCount ?? this.droppedCount,
      );

  @override
  List<Object?> get props =>
      <Object?>[serverUrl, deviceUuid, status, senders, disabledSenders, rulesLoaded, syncing, droppedCount];
}

/// Drives the settings screen: device info, the SMS-source whitelist (with per-sender on-device
/// disable + "sync from admin panel"), and the "revoke & wipe" — revoke this device on the server
/// (best-effort) then clear ALL local data so nothing recoverable remains.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._store, this._devices, this._wipe, this._rules, this._overrides, this._capture)
      : super(const SettingsState());

  final SecureStore _store;
  final DeviceRepository _devices;
  final LocalWipe _wipe;
  final FilterRulesRepository _rules;
  final SenderOverrides _overrides;
  final SmsCapture _capture;

  Future<void> load() async {
    emit(state.copyWith(
      serverUrl: await _store.readServerUrl(),
      deviceUuid: await _store.readDeviceUuid(),
      droppedCount: await _readDroppedCount(),
    ));
    await _loadSenders();
  }

  Future<int> _readDroppedCount() async {
    try {
      final int overflow = await _capture.getDroppedOverflowCount();
      final int filtered = await _capture.getDroppedFilteredCount();
      return overflow + filtered;
    } catch (_) {
      // Platform channel unavailable (e.g. tests or an unsupported platform) — keep 0.
      return 0;
    }
  }

  Future<void> _loadSenders() async {
    final FilterRules? rules = await _rules.effectiveRules();
    final Set<String> disabled = await _overrides.disabled();
    emit(state.copyWith(
      senders: rules?.allowedSenders ?? const <String>[],
      disabledSenders: disabled,
      rulesLoaded: true,
    ));
  }

  /// Toggles a sender on/off on this device (off = locally disabled; the gate then drops it).
  Future<void> toggleSender(String sender, bool enabled) async {
    await _overrides.setDisabled(sender, !enabled);
    emit(state.copyWith(disabledSenders: await _overrides.disabled()));
  }

  /// Force-refetches the whitelist from the paired server ("sync from admin panel"). Keeps the current
  /// list if the server is unreachable.
  Future<void> syncFromAdmin() async {
    emit(state.copyWith(syncing: true));
    final FilterRules? rules = await _rules.forceRefresh();
    emit(state.copyWith(
      senders: rules?.allowedSenders ?? state.senders,
      disabledSenders: await _overrides.disabled(),
      rulesLoaded: true,
      syncing: false,
    ));
  }

  /// Connection-only reset: clears server URL/credentials/pin via the wipe service's
  /// connection-only path (not a full wipe). Navigates the UI back to the pairing screen.
  Future<void> resetConnection() async {
    emit(state.copyWith(status: SettingsStatus.idle));
    await _wipe.resetConnection();
    // Force the router-visible "unpaired" state too.
  }

  Future<void> revokeAndWipe() async {
    emit(state.copyWith(status: SettingsStatus.wiping));
    // Best-effort server revoke — even if it fails (offline/revoked), we still wipe locally so this
    // device holds no secret material afterwards.
    await _devices.revoke();
    await _wipe.wipe();
    emit(state.copyWith(status: SettingsStatus.wiped));
  }
}
