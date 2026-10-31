---
name: clean-arch-data
description: Use when creating or editing the data layer of a Flutter feature (features/<feature>/data): DTOs, mappers, remote/local data sources, repository implementations, caching, and converting exceptions to failures.
---

# Data layer rules

The data layer implements the domain's repository interfaces and owns everything about the outside world: API shape, JSON, storage, caching.

## Contents

```
data/
├── dtos/                       # wire/storage models
├── mappers/                    # dto <-> entity
├── sources/                    # remote_*_data_source.dart, local_*_data_source.dart
└── <feature>_repository_impl.dart
```

## Hard rules

- Imports `domain` (entities, repository interfaces, failures). Never imports `presentation`.
- **DTOs never leave `data/`.** Repository methods return domain entities.
- Exceptions never leave `data/`. Catch them and return `Failure`.
- No business rules here (limits, eligibility, calculations). That is domain.
- No Flutter widgets or `BuildContext`.

## DTOs

- Named `<Thing>Dto`, mirror the API/storage shape exactly (field names, nullability).
- Use `json_serializable` (`@JsonSerializable`) with generated `fromJson`/`toJson`. No hand-written parsing unless unavoidable.
- Immutable, `final` fields.

## Mappers

- Extension methods or small classes: `extension AccountDtoX on AccountDto { Account toEntity() => ... }` and `Account.toDto()` where writes are needed.
- All parsing of formats (dates, money strings, enums from strings) happens here. Unknown enum values map to a safe default or a failure, never a crash.
- Pure functions, unit-tested with round trips.

## Data sources

- Remote source: wraps the HTTP/API client. Returns DTOs, throws typed `ApiException`s.
- Local source: wraps storage (`SharedPreferences`, secure storage, DB) using typed keys. Returns DTOs or primitives.
- Use sources when you cache or support offline. For a trivial single-call repository you may call the client directly; stay consistent within the feature.
- Depend on `core` abstractions (`HttpClient`, `KeyValueStorage`), not on a concrete plugin type scattered through code.

## Repository implementation

- `class <Feature>RepositoryImpl implements <Feature>Repository`.
- Receives sources through the constructor.
- Responsibilities: choose source (cache vs network), map DTO to entity, map exceptions to `Failure`.

```dart
class AccountsRepositoryImpl implements AccountsRepository {
  AccountsRepositoryImpl(this._remote);
  final RemoteAccountsDataSource _remote;

  @override
  Future<Result<List<Account>>> getAccounts() async {
    try {
      final dtos = await _remote.fetchAccounts();
      return Success(dtos.map((d) => d.toEntity()).toList());
    } on ApiException catch (e) {
      return Failure(e.toFailure());
    }
  }
}
```

## Error mapping

- One place (`ApiException.toFailure()` in `core/error`) maps status codes/exceptions to `NetworkFailure`, `UnauthorizedFailure`, `ServerFailure`, etc.
- Only catch what you can map. Do not use bare `catch (e)` that swallows programming errors; let unexpected errors surface to the global error handler/Sentry.
- Log with the shared logger; never `print`.

## Mock implementation

- Provide `Mock<Feature>Repository implements <Feature>Repository` for dev flavors and demos, returning entities directly. Selected in DI via `AppConfig.useMocks` (see `clean-arch-di-routing`).

## Checklist before finishing

- [ ] No DTO or exception type appears in any domain or presentation signature
- [ ] Mapper tests cover null/unknown values
- [ ] Repository impl tested with fake sources, covering success and each failure branch
- [ ] No business rule inside data

## Bundled files

- `references/error-mapping.md`: exception to failure table, `toFailure()`, caching pattern
