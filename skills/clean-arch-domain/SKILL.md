---
name: clean-arch-domain
description: Use when creating or editing the domain layer of a Flutter feature (features/<feature>/domain): entities, abstract repository interfaces, use cases, domain failures. Rules for what belongs in domain, naming, and what it must never import.
---

# Domain layer rules

The domain is the business core. It is pure Dart and knows nothing about Flutter, Bloc, HTTP, JSON or storage.

A feature only gets a `domain/` folder when it needs one (see the feature shapes in `clean-arch-overview`): business rules, logic reused by several cubits, a feature exposing data to others, or a swappable implementation. A thin feature that only displays screen-ready data has no domain layer and its cubit calls the typed API client.

## Contents

```
domain/
├── entities/        # business objects
├── repositories/    # abstract interface classes
└── use_cases/       # one business action each
```

## Hard rules

- **No imports** from `flutter`, `flutter_bloc`, `http`/`dio`, `json_annotation`, `shared_preferences`, `data/` or `presentation/`. Allowed: `dart:*`, `equatable`, `meta`, and `core/error` (Failure, Result), `core/domain` shared types.
- No `fromJson` / `toJson` on entities. Serialization belongs to DTOs in `data/`.
- No `BuildContext`, no `Widget`, no localized strings. Return typed failures; presentation maps them to text.
- All classes are immutable (`final` fields, `const` constructors).

## Entities

- Model business concepts, not API responses. Name them in the business language (`Account`, `Transfer`, `Money`), no `Dto`/`Model`/`Entity` suffix.
- Extend `Equatable` (or use `==`/`hashCode`) so state comparisons work.
- Put rules that depend only on the entity's own data on the entity (`bool get isOverdrawn`).
- Use value objects (`Money`, `Iban`) instead of raw `String`/`double` for concepts with rules.
- Use `sealed class` or enums for closed sets (`TransferStatus`).

## Repository interfaces

- Declared as `abstract interface class <Feature>Repository`.
- Describe what the app needs, not how it is fetched. No pagination tokens or HTTP vocabulary unless it is a real domain concept.
- Return entities or `Result<T>`, never DTOs. Prefer `Future<Result<T>>` over throwing. Use `Stream<T>` only for genuinely live data.
- One repository per aggregate/bounded concept, not one per screen.
- Add a repository only when there is caching, several sources to merge (remote + local), or complex mapping. When there is one, it is **always an interface** here, implemented in `data/`. Other things (use cases, mappers, DTOs, cubits) are concrete classes: see `references/when-to-use-interfaces.md` before adding any other interface.

## Use cases

- One class per business action, named as a verb phrase: `GetAccounts`, `TransferMoney`, `ValidateIban`. Never `AccountsUseCase`.
- Constructor takes repository interfaces (and other use cases); one public method `call(...)`.
- Contains logic that is not UI and not I/O: validation, rules, combining repositories, mapping between entities.
- Returns `Result<T>`. Expected failures are values (`Failure(TransferLimitExceeded(...))`), not exceptions.
- Stateless. No caches, no streams held in fields.
- **Do not create pass-through use cases** (`=> _repo.getX()`) unless the project convention says cubits only talk to use cases. If the convention is "always use cases", keep them thin and consistent; otherwise let the cubit call the repository (or, in a thin feature, the API client) for plain reads.

```dart
class TransferMoney {
  const TransferMoney(this._accounts, this._limits);
  final AccountsRepository _accounts;
  final LimitsRepository _limits;

  Future<Result<void>> call(Transfer transfer) async {
    final limit = await _limits.getDailyLimit();
    if (limit case Success(:final value) when transfer.amount > value.remaining) {
      return Failure(TransferLimitExceeded(value.remaining));
    }
    return _accounts.transfer(transfer);
  }
}
```

## Failures

- Group a feature's failures under a `sealed class` that extends the shared `AppFailure` in `core/error`, with one `final class` per case. `Result<T>` has two cases, `Success(value)` and `Failure(failure)`; the `Failure` case wraps an `AppFailure`.

```dart
sealed class TransferFailure extends AppFailure {
  const TransferFailure();
}
final class TransferLimitExceeded extends TransferFailure {
  const TransferLimitExceeded(this.remaining);
  final Money remaining;
}
final class InsufficientFunds extends TransferFailure {
  const InsufficientFunds();
}
```
- Failures are **dedicated classes**, never subclasses of `Exception`/`Error`. Returning them (`Result`) forces callers to handle or consciously discard them.
- Failures carry data needed to explain the problem, not messages. If another layer needs a message, the UI maps the failure to localized text (see `clean-arch-ui`).

## Checklist before finishing

- [ ] No forbidden import in any domain file
- [ ] Entities are immutable and compare by value
- [ ] Repository interface returns entities/`Result`, no DTOs
- [ ] Each use case is one action with a unit test (see `clean-arch-testing`)

## Bundled files

- `references/what-belongs-in-domain.md`: decision table for where a piece of logic goes, and when a feature may skip use cases
- `references/when-to-use-interfaces.md`: when an interface is justified and when it is ceremony; interface vs sealed class
- `references/result.dart`: `Result`, `Success`, `Failure`, `AppFailure` and common failures (goes in `core/error`)
