import 'package:equatable/equatable.dart';

/// Typed, user-presentable failure. Repositories return these instead of throwing, so Blocs can
/// render a message and the app can react (e.g. [AuthFailure] → re-pair flow).
sealed class Failure extends Equatable {
  const Failure({this.message = 'Something went wrong.', this.code});

  final String message;
  final String? code;

  @override
  List<Object?> get props => [message, code];

  @override
  String toString() => '$runtimeType(${code ?? '-'}): $message';
}

/// No connectivity / timeout / DNS — safe to retry later.
class NetworkFailure extends Failure {
  const NetworkFailure({super.message = 'No connection. Will retry when back online.', super.code});
}

/// 401 / revoked / fingerprint mismatch — the device must re-pair. Stop the sync worker.
class AuthFailure extends Failure {
  const AuthFailure({super.message = 'Device authorization expired. Please re-pair.', super.code});
}

/// 5xx or unexpected server state — retryable.
class ServerFailure extends Failure {
  const ServerFailure({super.message = 'The server had a problem. Will retry.', super.code});
}

/// 4xx (other than 401) / malformed payload — not retryable without a change.
class ValidationFailure extends Failure {
  const ValidationFailure({super.message = 'The request was rejected.', super.code});
}

class UnknownFailure extends Failure {
  const UnknownFailure({super.message = 'Something went wrong.', super.code});
}
