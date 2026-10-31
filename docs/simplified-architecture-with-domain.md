# Simplified Flutter Architecture with a Domain Layer (reusable template)

A variant of `simplified-architecture.md` that adds a **domain layer** (entities, repository contracts, use cases). Use it when the app contains real business logic. Everything not described here (DI, navigation, flavors, testing, CI) works the same as in the base template.

**Stack:** `flutter_bloc`, `auto_route`, `provider`, `--dart-define` flavors. Replace `<feature>` and `<Feature>` with your own names.

## 1. When to use this version

Choose it when at least one of these is true:

| Situation | Example |
|---|---|
| The app holds business rules, not only displays server data | Transfer limits, fee calculation, loan eligibility, multi-field validation |
| Several data sources are combined into one result | Accounts + cards + exchange rates -> total balance |
| The same logic is needed by more than one cubit | "Can the user pay?" used by the pay, scheduled-payment and QR screens |
| Wire format and app model differ a lot, or the backend may change | Migrating from REST to GraphQL, or replacing a vendor |
| The data layer must be swapped or faked in tests | Offline mode, mock backend |
| A feature must expose data to others without exposing its repository | Accounts exposes `GetTotalBalance` to the dashboard |

Stay with the base template (no domain layer) when:

- The backend is a BFF and returns data already shaped for each screen.
- Cubits would only forward calls (`cubit -> useCase -> repository.get()`).
- It is a prototype or a showcase.

A domain layer for pure pass-through code adds files and no value. Add it per feature, only where there is logic to put in it.

## 2. Principles

1. Feature-first folders, with `presentation -> domain <- data` inside each feature.
2. **The domain layer depends on nothing.** No Flutter, no HTTP, no JSON, no storage packages. Plain Dart only.
3. **Data implements domain.** The domain defines repository interfaces and the data layer implements them (dependency inversion).
4. The presentation layer (cubits, pages) talks only to use cases, not to repositories.
5. Features never import other features. Shared code lives in `core/`.
6. One composition root in `bootstrap/`.

## 3. Folder structure

```
lib/
├── main.dart
├── app.dart
├── bootstrap/
│   ├── app_config.dart
│   └── global_providers.dart
├── router/
├── core/                         # same as the base template
│   ├── auth/ http/ storage/ logging/ analytics/ utils/
│   └── error/                    # Failure types, Result
├── design_system/
├── l10n/
└── features/
    └── <feature>/
        ├── domain/               # pure Dart
        │   ├── entities/         # <feature>.dart
        │   ├── repositories/     # <feature>_repository.dart (abstract interface)
        │   └── use_cases/        # get_<feature>.dart, pay_invoice.dart, ...
        ├── data/
        │   ├── dtos/             # JSON models
        │   ├── mappers/          # dto <-> entity
        │   ├── sources/          # remote_data_source.dart, local_data_source.dart
        │   └── <feature>_repository_impl.dart
        ├── presentation/
        │   ├── cubit/
        │   └── ui/
        ├── <feature>_routes.dart
        └── <feature>_providers.dart
```

## 4. Dependency direction

```
presentation ──► domain ◄── data
   (cubit, ui)   (entities,   (repository impl,
                  use cases,   DTOs, data sources)
                  repo interfaces)
```

- `domain` imports nothing from `presentation` or `data`.
- `data` imports `domain` to implement its interfaces.
- `presentation` imports `domain` only (never `data`).
- Only the composition root (`<feature>_providers.dart`) knows both `domain` and `data`.

## 5. Layers

### Domain

**Entity:** a business object, independent of JSON and UI.

```dart
class Account extends Equatable {
  const Account({required this.id, required this.balance, required this.currency});
  final String id;
  final Money balance;
  final Currency currency;

  bool get isOverdrawn => balance.amount < 0;   // business rule on the entity

  @override
  List<Object?> get props => [id, balance, currency];
}
```

**Repository interface:** what the app needs, not how it is fetched.

```dart
abstract interface class AccountsRepository {
  Future<Result<List<Account>>> getAccounts();
  Future<Result<void>> transfer(Transfer transfer);
}
```

**Use case:** one business action. Name it as a verb. Call it with `call()`.

```dart
class TransferMoney {
  const TransferMoney(this._accounts, this._limits);
  final AccountsRepository _accounts;
  final LimitsRepository _limits;

  Future<Result<void>> call(Transfer transfer) async {
    final limit = await _limits.getDailyLimit();
    if (transfer.amount > limit.remaining) {
      return Failure(TransferLimitExceeded(limit.remaining));
    }
    return _accounts.transfer(transfer);
  }
}
```

### Data

- **DTO:** mirrors the API (`@JsonSerializable`). Never leaves the data layer.
- **Mapper:** `AccountDto.toEntity()` and `Account.toDto()`. All wire-format knowledge lives here.
- **Data sources:** `RemoteAccountsDataSource` (HTTP), `LocalAccountsDataSource` (storage). Optional; use them when you cache or support offline.
- **Repository implementation:** `AccountsRepositoryImpl implements AccountsRepository`. It picks the source, maps DTOs to entities, and turns exceptions into `Failure`s.

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

### Presentation

- **Cubit:** calls use cases, maps results to a UI state. No business rules.
- **UI:** unchanged from the base template.

```dart
class TransferCubit extends Cubit<TransferState> {
  TransferCubit(this._transferMoney) : super(const TransferInitial());
  final TransferMoney _transferMoney;

  Future<void> submit(Transfer transfer) async {
    emit(const TransferLoading());
    final result = await _transferMoney(transfer);
    emit(switch (result) {
      Success() => const TransferDone(),
      Failure(:final failure) => TransferFailed(failure),
    });
  }
}
```

## 6. Error handling

- `core/error` defines `Failure` (a sealed class: `NetworkFailure`, `ValidationFailure`, `UnauthorizedFailure`, and so on) and `Result<T>` (`Success` or `Failure`).
- The data layer catches exceptions and returns `Failure`s. It never lets raw `DioException` or `SocketException` types reach the domain.
- Use cases add domain failures (`TransferLimitExceeded`).
- Cubits map failures to messages and states.

## 7. Dependency injection

The feature's providers file is the only place that wires data to domain to presentation:

```dart
final accountsProviders = <SingleChildWidget>[
  Provider<RemoteAccountsDataSource>(create: (c) => RemoteAccountsDataSource(c.read())),
  Provider<AccountsRepository>(
    create: (c) => AppConfig.useMocks
        ? MockAccountsRepository()
        : AccountsRepositoryImpl(c.read()),
  ),
  Provider(create: (c) => GetAccounts(c.read())),
  Provider(create: (c) => TransferMoney(c.read(), c.read())),
];
```

Pages create their cubit with `BlocProvider(create: (c) => TransferCubit(c.read()))`.

## 8. Cross-feature sharing

Features can't import each other. When feature B needs data from feature A:

1. Put the shared **entity or contract** in `core/` (for example `core/domain/money.dart`), or
2. Have feature A expose a **use case or small interface** in its public barrel (`features/a/a.dart`) and register it in DI, so B depends on the interface and never on A's repository.

Add the matching import lint rules:

- `features/*/domain/**` must not import Flutter, `data/` or `presentation/`.
- `features/*/presentation/**` must not import `data/`.
- `features/a/**` must not import `features/b/**`.

## 9. Testing

| What | How |
|---|---|
| Entities and use cases | Plain `dart test`; fake repositories. This is where most business tests go. |
| Mappers | Unit tests: DTO <-> entity round trips |
| Repository impl | Fake data sources / HTTP client |
| Cubits | `bloc_test` with mocked use cases |
| Widgets | Providers overridden with mocked use cases |

Use cases make business logic testable without Flutter, a mock HTTP client or a widget tree.

## 10. How to add a feature (checklist)

1. Define **entities** and the **repository interface** in `domain/`.
2. Write **use cases** only for actions with logic or reuse. For a plain read with nothing in between, call the repository through one thin use case, or skip the use case for that screen (see section 11).
3. Create **DTOs, mappers, data sources** and `RepositoryImpl` in `data/`. Add a mock implementation.
4. Write the **cubit** against use cases, plus a sealed state.
5. Build the **page** with an `AutoRouteWrapper` that provides the cubit.
6. Register routes and providers (section 7).
7. Add l10n strings, analytics ids and a flag in `AppConfig` if needed.
8. Write tests bottom-up: use cases, mappers, cubit.

## 11. Pitfalls

- **Pass-through use cases.** If a use case is `=> repository.getX()` and will stay that way, it is ceremony. Allow cubits in simple features to depend on the repository interface, and say so in your conventions. Pick one rule and stay with it.
- **God use cases.** One class per business action. Don't create `AccountsUseCase` with ten methods.
- **Entities that mirror DTOs one to one.** If they stay identical, you may not need a domain layer yet.
- **Leaking layers.** No `fromJson` on entities, no `BuildContext` in use cases, no DTOs in cubits.
- **Domain layer for every feature at once.** Add it feature by feature, starting where the logic is.

## 12. Choosing between the two templates

| Question | Base template | With domain |
|---|---|---|
| Is the backend a BFF returning screen-ready data? | Yes | No |
| Are there business rules in the app? | No | Yes |
| Does logic repeat across screens? | No | Yes |
| Team size / project lifetime | Small / short | Larger / long |
| Files per feature | Fewer | More, with clearer places for logic |

You can also mix the two: use the base layers in simple features and add `domain/` only to the features that need it. Keep each feature internally consistent.
