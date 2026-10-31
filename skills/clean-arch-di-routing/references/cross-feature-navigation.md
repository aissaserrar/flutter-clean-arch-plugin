# Cross-feature navigation and sharing

Features cannot import each other. Three ways to get what you need, from simplest to most decoupled.

## 1. Navigate by generated route (simplest)

Routes are generated into `router/app_router.gr.dart`, which any feature may import.

```dart
// auto_route
context.router.push(TransferRoute(accountId: account.id));
// go_router (type-safe routes)
TransferRoute(accountId: account.id).go(context);
```

The accounts feature references only the route class, not the transfers feature's code. Good default.

## 2. Navigation interface (strict decoupling)

The feature declares what it needs; `router/` implements it.

```dart
// features/accounts/accounts_navigation.dart
abstract interface class AccountsNavigation {
  void goToTransfer(String accountId);
}

// router/app_navigation.dart
class AppNavigation implements AccountsNavigation {
  AppNavigation(this._router);
  final AppRouter _router;
  @override
  void goToTransfer(String accountId) => _router.push(TransferRoute(accountId: accountId));
  // go_router: AppNavigation holds the GoRouter instance (no BuildContext available here):
  //   void goToTransfer(String accountId) => _router.go(TransferRoute(accountId: accountId).location);
}

// bootstrap/global_providers.dart
Provider<AccountsNavigation>(create: (c) => c.read<AppNavigation>()),
```

Use when the feature may later be extracted into a package, or tests need to verify navigation.

## 3. Sharing data

| Need | Solution |
|---|---|
| Both features use the same concept (`Money`, `User`) | Keep it in the owning feature and expose it from its barrel; move it to `core/domain/` only when a **third** feature needs it (rule of three) and it is not business-specific |
| Feature B needs a value only feature A can compute | A exposes a **use case** in its public barrel (`accounts.dart`); B depends on that class via DI |
| Both react to the same event (logout) | Shared stream/cubit in `core/` (`AuthCubit`) |

Never let B import A's repository or DTOs.
