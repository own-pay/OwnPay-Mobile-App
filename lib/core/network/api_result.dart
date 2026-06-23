import '../error/failure.dart';

/// A minimal `Result` type so repositories can return success/failure without throwing.
/// Use `switch` to handle both arms exhaustively.
sealed class ApiResult<T> {
  const ApiResult();

  bool get isOk => this is Ok<T>;

  /// Returns the value on [Ok], or null on [Err].
  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  R fold<R>(R Function(Failure failure) onErr, R Function(T value) onOk) => switch (this) {
        Ok<T>(:final value) => onOk(value),
        Err<T>(:final failure) => onErr(failure),
      };
}

class Ok<T> extends ApiResult<T> {
  const Ok(this.value);
  final T value;
}

class Err<T> extends ApiResult<T> {
  const Err(this.failure);
  final Failure failure;
}
