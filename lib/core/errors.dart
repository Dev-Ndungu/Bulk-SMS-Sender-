/// Application error hierarchy.
library;

sealed class AppError {
  final String message;
  const AppError(this.message);
}

final class NetworkError extends AppError {
  const NetworkError([super.message = 'No network connection']);
}

final class GatewayError extends AppError {
  final int? statusCode;
  const GatewayError(super.message, {this.statusCode});
}

final class PermissionError extends AppError {
  const PermissionError([super.message = 'Permission denied']);
}

final class StorageError extends AppError {
  const StorageError(super.message);
}

final class ValidationError extends AppError {
  const ValidationError(super.message);
}
