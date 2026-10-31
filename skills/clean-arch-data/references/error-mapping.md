# Error mapping

Goal: nothing below the repository boundary leaks upward. The domain sees `Failure(AppFailure)`.

## Layers of errors

| Raised by | Type | Mapped by |
|---|---|---|
| HTTP client / socket | `SocketException`, `TimeoutException` | `core/http` wrapper into `ApiException.network` |
| Non-2xx response | `ApiException(statusCode, body)` | `ApiException.toFailure()` |
| JSON parsing | `FormatException`, `TypeError` | repository: treat as `ServerFailure` (contract broken) and log |
| Storage | plugin exceptions | local source wraps into `StorageException` |

## ApiException.toFailure()

```dart
AppFailure toFailure() => switch (statusCode) {
      401 || 403 => const UnauthorizedFailure(),
      0 => const NetworkFailure(),            // no connection / timeout
      _ => ServerFailure(statusCode: statusCode),   // 5xx and any other unmapped status
    };
```

Business errors returned by the API (for example `{"code":"LIMIT_EXCEEDED"}`) are mapped in the **repository impl** to the feature's domain failure, not in the generic mapper.

## Rules

- Catch specific exception types. Never `catch (e)` around code that can contain bugs.
- Log the technical detail (status, path, correlation id) with the shared logger; the failure carries only what the UI needs.
- Parsing failures are bugs or contract changes: report them to Sentry, return a generic failure.
- Retries and token refresh belong in an HTTP interceptor in `core/http`, not in repositories.

## Caching pattern (when needed)

```dart
Future<Result<List<Account>>> getAccounts() async {
  final cached = _local.readAccounts();
  if (cached != null && !_isStale(cached)) return Success(cached.toEntities());
  try {
    final dtos = await _remote.fetchAccounts();
    await _local.saveAccounts(dtos);
    return Success(dtos.map((d) => d.toEntity()).toList());
  } on ApiException catch (e) {
    if (cached != null) return Success(cached.toEntities()); // stale is better than nothing
    return Failure(e.toFailure());
  }
}
```
