---
name: clean-arch-ui
description: Use when creating or editing Flutter pages and widgets in a feature (features/<feature>/presentation/ui): connecting widgets to Cubit/Bloc state with BlocBuilder/BlocListener/BlocSelector, providing cubits per route, handling one-off effects, localization and design system usage.
---

# UI rules: pages and widgets

The UI renders state and forwards user intent. It contains no business logic and no data access.

## Hard rules

- Imports: Flutter, `flutter_bloc`, the feature's own cubit/state, `domain` entities (for display), `design_system`, `l10n`, `core`. **Never `data/`.**
- No HTTP, storage, repository or use-case calls in widgets. Call cubit methods only.
- No business rules or formatting logic that has meaning beyond display. Put it in a use case or entity.
- Strings come from `context.l10n`. No hard-coded user-facing text.
- Colors, spacing, text styles come from design system tokens. No literal colors or magic numbers.

## Page structure

- A page = route entry. It provides its cubit and builds the screen:

```dart
@RoutePage()
class TransferPage extends StatelessWidget implements AutoRouteWrapper {
  const TransferPage({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
        create: (context) => TransferCubit(context.read()),
        child: this,
      );

  @override
  Widget build(BuildContext context) => const _TransferView();
}
```

- Keep `build` small. Split into private widget classes (`_TransferForm`, `_SubmitButton`), not helper methods returning `Widget`.
- Reusable widgets without cubit knowledge take plain parameters and callbacks. Only page-level or feature-level widgets read the cubit.

## Reading state

- `BlocBuilder` for rendering; use `buildWhen` or `BlocSelector` to rebuild only what changed.
- **Switch exhaustively over sealed states**; no `if (state is X) ... else ...` chains with a catch-all.
- `BlocListener` for one-off effects (navigate, snackbar, dialog): never do these in `build`. Use `listenWhen` to react to transitions only.
- `context.read<Cubit>()` in callbacks, `context.watch`/`select` in build. Never `read` in `build` to get values you display.

```dart
BlocConsumer<TransferCubit, TransferState>(
  listener: (context, state) {
    if (state is TransferDone) context.router.maybePop();
  },
  builder: (context, state) => switch (state) {
    TransferInitial() || TransferFailed() => _TransferForm(error: state.failureOrNull),
    TransferLoading() => const AppSpinner(),
    TransferDone() => const SizedBox.shrink(),
  },
)
```

## Errors and empty states

- Map `AppFailure` to a user message in the UI layer (one shared helper in `core` or `design_system`), using l10n.
- Provide loading, error with retry, and empty states for every data screen. Retry calls a cubit method.

## Forms and input

- Controllers and focus nodes live in the widget (hooks or `StatefulWidget`), disposed properly. Validation rules that are business rules call a use case via the cubit; simple format checks may stay in the form.
- Disable submit while loading; the cubit also guards against double submit.

## Navigation

- Navigate through the router (`context.router.push(...)`) from listeners or callbacks. Cross-feature navigation uses a route from `router/` or an injected navigation interface, never an import of another feature's page.

## Analytics and accessibility

- Tappable widgets carry an analytics id if the project uses that convention.
- Provide `Semantics`/tooltips for icon-only controls; respect text scaling (no fixed heights on text).

## Checklist before finishing

- [ ] No `data/` import, no repository/use-case access in widgets
- [ ] Exhaustive `switch` on state; listeners for side effects
- [ ] All strings from l10n, all styles from design system
- [ ] Loading / error+retry / empty states present
- [ ] Widget test with a mocked cubit (see `clean-arch-testing`)

## Bundled files

- `references/ui-checklist.md`: review checklist
