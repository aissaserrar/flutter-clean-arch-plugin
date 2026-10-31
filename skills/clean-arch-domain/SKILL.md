---
name: clean-arch-domain
description: Use when creating or editing the domain layer of a Flutter feature (features/<feature>/domain): entities, abstract repository interfaces, use cases, domain failures. Rules for what belongs in domain, naming, and what it must never import.
---

# Domain layer rules

The domain is the business core. It is pure Dart and knows nothing about Flutter, Bloc, HTTP, JSON or storage.

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

## Use cases

- One class per business action, named as a verb phrase: `GetAccounts`, `TransferMoney`, `ValidateIban`. Never `AccountsUseCase`.
- Constructor takes repository interfaces (and other use cases); one public method `call(...)`.
- Contains logic that is not UI and not I/O: validation, rules, combining repositories, mapping between entities.
- Returns `Result<T>`. Expected failures are values (`Failure(TransferLimitExceeded(...))`), not exceptions.
- Stateless. No caches, no streams held in fields.
- **Do not create pass-through use cases** (`=> _repo.getX()`) unless the project convention says cubits only talk to use cases. If the convention is "always use cases", keep them thin and consistent; otherwise skip them for plain reads.

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

- Define domain failures as a `sealed class` (`TransferLimitExceeded`, `InsufficientFunds`) extending the shared `AppFailure` in `core/error`. `Result<T>` has two cases, `Success(value)` and `Failure(failure)`; the `Failure` case wraps an `AppFailure`.
- Failures carry data needed to explain the problem, not messages.

## Checklist before finishing

- [ ] No forbidden import in any domain file
- [ ] Entities are immutable and compare by value
- [ ] Repository interface returns entities/`Result`, no DTOs
- [ ] Each use case is one action with a unit test (see `clean-arch-testing`)

## Bundled files

- `references/what-belongs-in-domain.md`: decision table for where a piece of logic goes, and when a feature may skip use cases
- `references/result.dart`: `Result`, `Success`, `Failure`, `AppFailure` and common failures (goes in `core/error`)
