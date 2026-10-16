sealed class AppFailure {
  const AppFailure(this.message);
  final String message;
}

class NetworkFailure extends AppFailure {
  const NetworkFailure([
    super.message = 'Network error. Check your connection.',
  ]);
}

class StorageFailure extends AppFailure {
  const StorageFailure([super.message = 'Could not save data.']);
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message);
}

class NotFoundFailure extends AppFailure {
  const NotFoundFailure([super.message = 'Item not found.']);
}

class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure([
    super.message = 'Token rejected. Check it in Settings.',
  ]);
}

class RateLimitedFailure extends AppFailure {
  const RateLimitedFailure([
    super.message = 'Too many requests. Try again shortly.',
  ]);
}

class ServerFailure extends AppFailure {
  const ServerFailure([super.message = 'The server had a problem. Try again.']);
}
