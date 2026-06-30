import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../sms_capture/domain/sms_capture.dart';
import '../data/consent_store.dart';
import '../domain/sms_permission.dart';

/// Lifecycle of the disclosure step. `granted`/`declined` are terminal "move on to home" outcomes;
/// `denied`/`permanentlyDenied` keep the user on the screen to retry or open settings.
enum DisclosurePhase { reviewing, requesting, granted, denied, permanentlyDenied, declined }

class DisclosureState extends Equatable {
  const DisclosureState(this.phase);

  final DisclosurePhase phase;

  /// True once the disclosure step is settled and the app should proceed to home.
  bool get isResolved =>
      phase == DisclosurePhase.granted || phase == DisclosurePhase.declined;

  @override
  List<Object?> get props => <Object?>[phase];
}

/// Drives the prominent-disclosure → runtime-request flow and records that onboarding completed.
///
/// Consent is marked complete on a definitive outcome only: SMS granted, or the user explicitly
/// choosing "Not now". A plain denial leaves it unmarked so the user can retry without nagging being
/// suppressed prematurely.
class DisclosureCubit extends Cubit<DisclosureState> {
  DisclosureCubit(this._gate, this._consent, this._capture)
      : super(const DisclosureState(DisclosurePhase.reviewing));

  final PermissionGate _gate;
  final ConsentStore _consent;
  final SmsCapture _capture;

  /// Invoked by the "Allow SMS access" button — fires the OS request after the disclosure was shown.
  Future<void> allow() async {
    emit(const DisclosureState(DisclosurePhase.requesting));
    final SmsPermission result = await _gate.requestSms();
    switch (result) {
      case SmsPermission.granted:
        // Best-effort: make sure the monitoring notification can show (Android 13+). Result ignored
        // by design — denied notifications degrade UX but must not block capture.
        await _gate.requestNotifications();
        await _consent.markDisclosureCompleted();
        // Capture starts the moment access is granted, so monitoring is active on first run.
        await _capture.startMonitoring();
        emit(const DisclosureState(DisclosurePhase.granted));
      case SmsPermission.permanentlyDenied:
        emit(const DisclosureState(DisclosurePhase.permanentlyDenied));
      case SmsPermission.denied:
        emit(const DisclosureState(DisclosurePhase.denied));
    }
  }

  /// Invoked by "Not now" — proceed in manual/confirm-only mode; capture stays off until the user
  /// enables it later from home.
  Future<void> declineForNow() async {
    await _consent.markDisclosureCompleted();
    emit(const DisclosureState(DisclosurePhase.declined));
  }

  Future<void> openSettings() => _gate.openSettings();
}
