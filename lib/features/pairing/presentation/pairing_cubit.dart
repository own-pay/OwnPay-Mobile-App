import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failure.dart';
import '../../../core/network/api_result.dart';
import '../data/device_repository.dart';

enum PairingStatus { idle, submitting, success, failure }

class PairingState extends Equatable {
  const PairingState({this.status = PairingStatus.idle, this.error});

  final PairingStatus status;
  final String? error;

  @override
  List<Object?> get props => <Object?>[status, error];
}

class PairingCubit extends Cubit<PairingState> {
  PairingCubit(this._devices) : super(const PairingState());

  final DeviceRepository _devices;

  Future<void> pair({
    required String serverUrl,
    required String otp,
    required String deviceName,
  }) async {
    if (serverUrl.trim().isEmpty || otp.trim().isEmpty) {
      emit(const PairingState(
        status: PairingStatus.failure,
        error: 'Server URL and pairing code are required.',
      ));
      return;
    }

    emit(const PairingState(status: PairingStatus.submitting));

    final ApiResult<void> result = await _devices.pair(
      serverUrl: serverUrl,
      otp: otp.trim(),
      deviceName: deviceName.trim().isEmpty ? 'Android device' : deviceName.trim(),
    );

    switch (result) {
      case Ok<void>():
        emit(const PairingState(status: PairingStatus.success));
      case Err<void>(:final Failure failure):
        emit(PairingState(status: PairingStatus.failure, error: failure.message));
    }
  }
}
