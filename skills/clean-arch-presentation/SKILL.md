---
name: clean-arch-presentation
description: Use when creating or editing Bloc or Cubit classes and their state/event classes in a Flutter feature (features/<feature>/presentation/cubit or bloc). Rules for choosing Cubit vs Bloc, state design, calling use cases, error mapping, and lifecycle.
---

# Presentation layer rules: Cubit / Bloc

Cubits and Blocs hold screen state and translate user actions into use-case calls. They contain no business rules and no widgets.

## Hard rules

- Depend on **use cases** from `domain` (or the repository interface if the feature has no use cases, per project convention). **Never import `data/`.**
- No `BuildContext`, no `Navigator`/router calls, no `ScaffoldMessenger`, no `Widget` types. One-off effects (navigate, snackbar) are signalled through state or `bloc_presentation` events and handled in the UI.
- No business rules: validation of money limits, fee math etc. belong in use cases.
- Dependencies come through the constructor. No service locators, no `context.read` inside a cubit.
- Never emit after `close()`: guard async gaps with `if (isClosed) return;` or use `emit.forEach`/`restartable` handlers.

## Cubit vs Bloc

- **Default to Cubit**: simple methods, less boilerplate.
- Use **Bloc** only when you need event transformers (debounce search, `droppable` submit, `restartable` refresh), event logging/replay, or several triggers that map to one state change.

## State design

- `sealed class <Feature>State extends Equatable` for screens with distinct phases (initial, loading, loaded, failure).
- Use a single immutable class with `copyWith` when many fields change independently (forms, lists with filters).
- State holds **UI-ready data**: entities from domain or small presentation models. No DTOs. No localized strings; hold the `Failure` or an error code, the UI picks the text.
- All state classes are `const`-constructible and implement `props`.
- Keep the previous data on refresh/failure when the UI should keep showing it (`loaded` with `isRefreshing`, or `failure` carrying `lastData`).

```dart
sealed class TransferState extends Equatable {
  const TransferState();
  @override
  List<Object?> get props => const [];
}
final class TransferInitial extends TransferState { const TransferInitial(); }
final class TransferLoading extends TransferState { const TransferLoading(); }
final class TransferDone extends TransferState { const TransferDone(); }
final class TransferFailed extends TransferState {
  const TransferFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}
```

## Cubit pattern

```dart
class TransferCubit extends Cubit<TransferState> {
  TransferCubit(this._transferMoney) : super(const TransferInitial());
  final TransferMoney _transferMoney;

  Future<void> submit(Transfer transfer) async {
    emit(const TransferLoading());
    final result = await _transferMoney(transfer);
    if (isClosed) return;
    emit(switch (result) {
      Success() => const TransferDone(),
      Failure(:final failure) => TransferFailed(failure),
    });
  }
}
```

## Bloc pattern

- Events are `sealed`, named in the past tense for what happened (`SearchQueryChanged`, `RefreshRequested`).
- One `on<Event>` per event, with a transformer where needed (`debounce`, `droppable()`).
- Use `emit.forEach` / `emit.onEach` for streams so subscriptions are cancelled with the bloc.

## Rules of thumb

- A public cubit method = a user intention (`load`, `submit`, `retry`, `selectAccount`). Name it that way.
- Prevent double submits: ignore calls while `state is Loading`.
- One cubit per screen/feature flow. Do not share one giant cubit across unrelated screens. Share data via a use case or a provider-scoped cubit with a clear owner.
- Cubits that listen to streams cancel them in `close()`.

## Checklist before finishing

- [ ] No import of `data/`, Flutter widgets or `BuildContext`
- [ ] States are sealed/equatable and hold no DTOs or strings
- [ ] Every async path checks `isClosed` before `emit`
- [ ] `bloc_test` cases for success, failure and edge cases (see `clean-arch-testing`)

## Bundled files

- `references/cubit-vs-bloc.md`: decision table, state design cheat sheet, lifecycle
