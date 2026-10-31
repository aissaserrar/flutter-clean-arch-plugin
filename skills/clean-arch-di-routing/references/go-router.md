# go_router rules

Applies when the app uses `go_router`. (For `auto_route`, see `SKILL.md`.) Examples use the same accounts/transfers features as the rest of the plugin.

## Use type-safe routes

Use go_router's type-safe routes: strongly typed route objects instead of raw path strings, so invalid paths cannot be built.

## Where routes live

- Routes are defined in `lib/router/` (the `router/` folder from `clean-arch-overview`).
- One `routes.dart`, or one `<feature>_routes.dart` per feature if the file grows.
- Define the **navigation tree** (the `TypedGoRoute` / `TypedShellRoute` declarations) in a **separate file** from the route classes.

```dart
// router/route_tree.dart
const root = TypedShellRoute<RootRoute>(
  routes: [
    TypedGoRoute<AccountRoute>(path: 'account/:accountId', routes: [
      TypedGoRoute<TransferRoute>(path: 'transfer'),
    ]),
  ],
);
```

```dart
// router/routes.dart
@root
class RootRoute extends ShellRouteData {
  // ...
}
```

Avoid putting the whole tree inside the annotation on the route class.

## Features expose pages, the app owns routes

Features expose **page widgets**; the global routing code consumes them. Defining routes is the app's responsibility, and features never import each other. A page provides its own cubit and passes route parameters to it (the page and content pattern from `clean-arch-ui`):

```dart
// features/accounts/presentation/ui/account_page.dart
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

```dart
// router/routes.dart
class AccountRoute extends GoRouteData {
  const AccountRoute({required this.accountId});
  final String accountId;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      AccountPage(accountId: accountId);
}
```

If the project uses route-based analytics, record the page id in the route class (see `clean-arch-observability`, for example `AccountsAnalyticsId.page`), because feature pages do not know their route.

## Parameters

- **Path parameters over query parameters.** Query parameters are not tied to one route and are never cleared as the stack changes.
- **Avoid `extra`.** Data in `extra` is lost on reload. Pass ids (`accountId`) and let the page's cubit fetch what it needs, preferably from a cache. Exception: internal state that must not be visible or editable from the URL or deep links (auth information).

## `go` over `push`

Prefer `go`, so the navigation stack is rebuilt correctly (for example after a web reload). For a page reachable from several places, `push` is fine, but the page still needs a canonical position in the navigation tree for deep links (for example `TransferRoute` lives under `AccountRoute`).

## Deep links

Define explicit deep-link paths for URLs sent to users (emails, push notifications) and redirect them to the real locations. Changing the navigation tree then does not break links in old emails. Links users copied from a web app can still break, so change the tree with that in mind.

## Naming

| Thing | Convention | Example |
|---|---|---|
| Path segments | kebab-case | `path: 'account-details'` (not `'accountDetails'`) |
| Path parameters | camelCase (they map to route class fields) | `path: 'account/:accountId'` (not `':account-id'` or `':AccountId'`) |
| Route class and path | match each other | `TransferRoute` ↔ `path: 'transfer'` (not `TransfersRoute`) |

## Navigate with the route extensions

```dart
context.pop();
AccountRoute(accountId: id).go(context);
TransferRoute(accountId: id).push<bool>(context);
```

In widgets, do not use `Navigator.of(context).pop()`, `context.go(AccountRoute(...).location)` or `context.push<bool>(TransferRoute(...).location)`. The one place raw `.location` is acceptable is inside `router/` (for example a navigation-interface implementation), where only a `GoRouter` instance is available, not a `BuildContext`.

## Side effects and navigation

Navigate from a presentation-event listener or a callback, never from `build`:

```dart
BlocPresentationListener<TransferCubit, TransferPresentationEvent>(
  listener: (context, event) => switch (event) {
    TransferPresentationEvent.completed => context.pop(),
  },
  child: const _TransferForm(),
)
```

## Cross-feature navigation

Because features only expose pages and the app owns the routes, a feature that needs to open another feature's screen either calls the generated route class from `router/` or uses a navigation interface (see `cross-feature-navigation.md`, where `AccountsNavigation.goToTransfer` is implemented with `TransferRoute`).
