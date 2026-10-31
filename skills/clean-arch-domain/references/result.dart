// Shared in core/error/result.dart. Pure Dart, usable from every layer.

/// Base type for every expected failure. Domain features extend it.
abstract base class AppFailure {
  const AppFailure();
}

sealed class Result<T> {
  const Result();
}

final class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

final class Failure<T> extends Result<T> {
  const Failure(this.failure);
  final AppFailure failure;
}

// Common failures live in core/error; feature-specific ones in the feature's domain.
final class NetworkFailure extends AppFailure {
  const NetworkFailure();
}

final class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure();
}

final class ServerFailure extends AppFailure {
  const ServerFailure({this.statusCode});
  final int? statusCode;
}
