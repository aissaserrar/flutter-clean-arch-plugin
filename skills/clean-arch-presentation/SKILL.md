---
name: clean-arch-presentation
description: Use when creating or editing Bloc or Cubit classes and their state, event and presentation-event classes in a Flutter feature (features/<feature>/presentation/cubit or bloc). Rules for Cubit vs Bloc, state design and naming, calling use cases/repositories/the API client, one-off side effects, error mapping, and lifecycle.
---

# Presentation layer rules: Cubit / Bloc

Cubits and Blocs hold screen state and translate user actions into calls to the layer below. They contain no business rules and no widgets.

## Hard rules

- Depend on what the feature shape provides (see `clean-arch-overview`): **use cases** (full feature), the **repository interface** (feature with a repository), or the **typed API client** from `core/` (thin feature). Never import `data/` internals (DTOs, data sources, repository implementations).
- No `BuildContext` in any form, no `Navigator`/router calls, no `ScaffoldMessenger`, no `Widget` types.
- One-off side effects (navigate, dialog, snackbar) use **`bloc_presentation`** presentation events, handled in the UI. State is for data the screen renders, not for events.
- No business rules (money limits, fee math): those belong in use cases.
- Dependencies come through the constructor. No service locators, no `context.read` inside a cubit.
- Create cubits with `BlocProvider` in the page. Never create a bloc or cubit inside `build`.
- Never emit after `close()`: guard async gaps with `if (isClosed) return;` or use `emit.forEach` / `restartable` handlers.

## One file per cubit/bloc

Keep all classes that belong to a cubit/bloc in **one file**, in this order: 1. Cubit/Bloc, 2. events (Bloc only), 3. state, 4. presentation events. Split only when the cubit is genuinely large, and consider splitting responsibilities first. Do not use `part`/`part of` (generated code is the only exception).

## Cubit vs Bloc

- **Default to Cubit**: simple methods, less boilerplate.
- Use **Bloc** only when you need event transformers (debounce search, `droppable` submit, `restartable` refresh), event logging/replay, or several triggers that map to one state change.

## State design

Two approaches (from the bloc library's "modeling state" guidance). Choose per screen:

| Approach | Use when |
|---|---|
| **Sealed class with subclasses** | Distinct, mutually exclusive phases. Type-safe and exhaustive. **Default.** |
| **One class with a status enum** (`initial`, `loading`, `success`, `failure`) plus `copyWith` | Many independent fields change separately (forms, lists with filters). |

Rules for both:

- **Naming:** base class `<Feature>State`; variants `<Feature>State<Variant>`. Use the standard variant names **`Initial`, `Loading`, `Success`, `Failure`** (status enum values: `initial`, `loading`, `success`, `failure`). Do not invent synonyms (`Idle`, `Fetching`, `Loaded`, `Done`, `Ok`, `Data`). Use `Failure` rather than `Error` so it never reads like `dart:core`'s `Error`. Add domain-specific variants only when needed (`Empty`).
- Extend `Equatable` (all states are `const`-constructible and implement `props`).
- Implement `copyWith` **only if it is needed**. Generate it with `copy_with_extension_gen` instead of writing it by hand.
- State holds **UI-ready data**: entities from domain or small presentation models. No hand-written DTOs. No localized strings: hold the `AppFailure` (or an error code); the UI picks the text.
- Keep the previous data on refresh/failure when the UI should keep showing it (`Success` with `isRefreshing`, or `Failure` carrying `lastData`).

```dart
sealed class TransferState extends Equatable {
  const TransferState();
  @override
  List<Object?> get props => const [];
}
final class TransferStateInitial extends TransferState { const TransferStateInitial(); }
final class TransferStateLoading extends TransferState { const TransferStateLoading(); }
final class TransferStateSuccess extends TransferState { const TransferStateSuccess(); }
final class TransferStateFailure extends TransferState {
  const TransferStateFailure(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

enum TransferPresentationEvent { completed }   // one-off effect, no fields -> enum
```

## Cubit pattern

```dart
class TransferCubit extends Cubit<TransferState>
    with BlocPresentationMixin<TransferState, TransferPresentationEvent> {
  TransferCubit(this._transferMoney) : super(const TransferStateInitial());
  final TransferMoney _transferMoney;

  Future<void> submit(Transfer transfer) async {
    if (state is TransferStateLoading) return;          // double-submit guard
    emit(const TransferStateLoading());
    final result = await _transferMoney(transfer);
    if (isClosed) return;
    switch (result) {
      case Success():
        emit(const TransferStateSuccess());
        emitPresentation(TransferPresentationEvent.completed);
      case Failure(:final failure):
        emit(TransferStateFailure(failure));
    }
  }
}
```

## Bloc pattern

- Events are `sealed`, named in the past tense for what happened (`SearchQueryChanged`, `RefreshRequested`). If **no event carries fields**, use an `enum` instead of a class hierarchy (same for presentation events).
- One `on<Event>` per event, with a transformer where needed (`debounce`, `droppable()`).
- Use `emit.forEach` / `emit.onEach` for streams so subscriptions are cancelled with the bloc.

## Rules of thumb

- A public cubit method = a user intention (`load`, `submit`, `retry`, `selectAccount`). Name it that way.
- Prevent double submits: ignore calls while `state is Loading`.
- One cubit per screen/feature flow. Do not share one giant cubit across unrelated screens. Share data via a use case or a provider-scoped cubit with a clear owner.
- Cubits that listen to streams cancel them in `close()`.
- Failures are returned as objects, not thrown (`Result`); do not catch to hide bugs.
- For a single-endpoint fetch with loading/error/retry and nothing else, a generic fetch-cubit helper (if the project has one) beats a hand-written cubit.

## Checklist before finishing

- [ ] No import of `data/` internals, Flutter widgets or `BuildContext`
- [ ] States are sealed/equatable, named `<Feature>State<Initial|Loading|Success|Failure>`, hold no strings
- [ ] Side effects use presentation events, not state
- [ ] Cubit, events, state and presentation events are in one file, in that order
- [ ] Every async path checks `isClosed` before `emit`
- [ ] `bloc_test` cases for success, failure and edge cases (see `clean-arch-testing`)

## Bundled files

- `references/cubit-vs-bloc.md`: decision table, state design cheat sheet, lifecycle
- `references/getx-migration.md`: GetX to interim form (ChangeNotifier + ListenableBuilder) to Cubit mapping, used by `/kill-getx` and `/to-bloc`
- `scripts/kill_getx_scan.sh [root] [target ...]` and `scripts/kill_getx_finish.sh [--apply] [root] [target ...]`: GetX inventory per file, and removal of `package:get` imports from files that no longer use it (dry run by default)
- `references/notifier-to-cubit.md`: ChangeNotifier to Cubit/Bloc and ListenableBuilder to BlocBuilder mapping, with a worked example; used by `/to-bloc`
- `scripts/to_bloc_scan.sh [root] [target ...]`: finds ChangeNotifier/ValueNotifier/GetxController holders and the widgets that consume them, with suggested Cubit/Bloc names and paths
