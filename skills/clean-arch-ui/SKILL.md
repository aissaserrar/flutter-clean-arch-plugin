---
name: clean-arch-ui
description: Use when creating or editing Flutter pages and widgets in a feature (features/<feature>/presentation/ui): connecting widgets to Cubit/Bloc state with BlocBuilder/BlocListener/BlocSelector, providing cubits per page, handling presentation events, error and loading UI, localization, flutter_hooks for controllers, and design system usage.
---

# UI rules: pages and widgets

The UI renders state and forwards user intent. It contains no business logic and no data access.

## Hard rules

- Imports: Flutter, `flutter_bloc`, the feature's own cubit/state, `domain` entities (for display), `design_system`, `l10n`, `core`. **Never `data/`.**
- No HTTP, storage, repository or use-case calls in widgets. Call cubit methods only.
- No business rules or formatting logic that has meaning beyond display. Put it in a use case or entity.
- Strings come from `context.l10n`. No hard-coded user-facing text. Localization stays in the presentation layer: other layers return failures or message models, and the UI maps them to localized text.
- Use **design system components** (`AppButton`, `AppScaffold`, `AppSpinner`, ...). Do not use `material`/`cupertino` widgets directly in feature code. Colors, spacing, text styles come from tokens: no literal colors or magic numbers.

## Page structure

- The public **`<Feature>Page`** is the route entry. It **provides its cubit** and builds the private **`_<Feature>Content`** underneath, so the content can be tested with a mocked cubit.

```dart
// auto_route
@RoutePage()
class TransferPage extends StatelessWidget implements AutoRouteWrapper {
  const TransferPage({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
        create: (context) => TransferCubit(context.read()),
        child: this,
      );

  @override
  Widget build(BuildContext context) => const _TransferContent();
}
```

```dart
// go_router (or any router that builds the page widget): the page provides the cubit itself.
// A page that takes a route parameter passes it on to its cubit.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key, required this.accountId});
  final String accountId;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => AccountCubit(context.read(), accountId),
        child: const _AccountContent(),
      );
}
```

- Keep `build` small. Split into private widget classes (`_TransferForm`, `_SubmitButton`), not helper methods returning `Widget`.
- Reusable widgets without cubit knowledge take plain parameters and callbacks. Only page-level or feature-level widgets read the cubit. Reusable UI components belong in `design_system`, not in shared code.
- Form cubits are provided with `BlocProvider` and read from context when the feature cubit is created (see `clean-arch-forms`).

## Reading state

- `BlocBuilder` for rendering; use `buildWhen` or `BlocSelector` to rebuild only what changed.
- **Switch exhaustively over sealed states**; no `if (state is X) ... else ...` chains with a catch-all.
- **One-off effects** (navigate, dialog, snackbar) come from presentation events: use `BlocPresentationListener`. Never do these in `build`. Use `BlocListener` with `listenWhen` only for reacting to state transitions that are not events.
- `context.read<Cubit>()` in callbacks, `context.watch`/`select` in build. Never `read` in `build` to get values you display.

```dart
BlocPresentationListener<TransferCubit, TransferPresentationEvent>(
  listener: (context, event) => switch (event) {
    TransferPresentationEvent.completed => context.router.maybePop(),   // or the go_router equivalent
  },
  child: BlocBuilder<TransferCubit, TransferState>(
    builder: (context, state) => switch (state) {
      TransferStateInitial() => const _TransferForm(),
      TransferStateFailure(:final failure) => _TransferForm(failure: failure),
      TransferStateLoading() => const AppSpinner(),
      TransferStateSuccess() => const SizedBox.shrink(),
    },
  ),
)
```

## Errors, loading and empty states

- Define error and loading patterns **once, globally**, and reuse them on every screen (see `references/error-and-loading-patterns.md`): full-screen, part of a screen, next page of a list, and user actions.
- Map `AppFailure` to a user message in the UI layer (one shared helper in `core` or `design_system`), using l10n. Show a **precise** message when it helps the user fix the problem; a generic one only when extra detail would not help.
- Every failure gives the user a way to **retry** (a cubit method). Never leave a screen the user can only escape by going back and navigating again.
- Network errors are handled differently from other errors, with clear feedback and automatic retry when the connection returns (details in the reference).

## Forms and input

- Controllers, focus nodes, animation controllers and global keys are presentation state: manage them with `flutter_hooks` (or a `StatefulWidget`) and dispose them properly.
- Forms follow `clean-arch-forms`. Validation rules that are business rules call a use case via the cubit; simple format checks may stay in the form.
- Disable submit while loading; the cubit also guards against double submit.

## Navigation

- Navigate through the router from presentation-event listeners or callbacks. With go_router use the route extensions (`MyRoute(...).go(context)`), not raw paths. Cross-feature navigation uses a route from `router/` or an injected navigation interface, never an import of another feature's page. See `clean-arch-di-routing`.

## Analytics and accessibility

- Pages and tappable widgets carry analytics ids following `clean-arch-observability`.
- Provide `Semantics`/tooltips for icon-only controls; respect text scaling (no fixed heights on text).

## Checklist before finishing

- [ ] No `data/` import, no repository/use-case access in widgets
- [ ] Page provides its cubit; content is a private `_<Feature>Content`
- [ ] Exhaustive `switch` on state; presentation events for side effects
- [ ] All strings from l10n, all styles from design system, no direct `material`/`cupertino` widgets
- [ ] Loading / error+retry / empty states present, using the shared patterns
- [ ] Controllers via hooks and disposed
- [ ] Widget test with a mocked cubit (see `clean-arch-testing`)

## Bundled files

- `references/ui-checklist.md`: review checklist
- `references/error-and-loading-patterns.md`: reusable error, loading and connectivity patterns
