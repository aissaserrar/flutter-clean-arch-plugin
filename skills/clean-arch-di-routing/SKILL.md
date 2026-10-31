---
name: clean-arch-di-routing
description: Use when wiring a Flutter Clean Architecture feature into the app: writing <feature>_providers.dart, editing bootstrap/global_providers.dart, registering routes and guards (auto_route), AppConfig flavors/feature flags, or choosing mock vs real repositories.
---

# DI, routing and configuration rules

## Dependency injection (provider)

- **One composition root**: `bootstrap/global_providers.dart` builds shared services (HTTP client, storage, auth cubit, logger) and spreads each feature's provider list.
- Each feature exposes `final <feature>Providers = <SingleChildWidget>[...]` in `<feature>_providers.dart`. This is the **only** feature file allowed to import both `domain` and `data`.
- Register by **interface type**, create the implementation:

```dart
final accountsProviders = <SingleChildWidget>[
  Provider<RemoteAccountsDataSource>(
    create: (c) => RemoteAccountsDataSource(c.read()),
  ),
  Provider<AccountsRepository>(
    create: (c) => AppConfig.useMocks
        ? MockAccountsRepository()
        : AccountsRepositoryImpl(c.read()),
  ),
  Provider(create: (c) => GetAccounts(c.read())),
  Provider(create: (c) => TransferMoney(c.read(), c.read())),
];
```

- Dependencies flow through **constructors**. `context.read` appears only in `create:` callbacks and page wrappers, never inside cubits, use cases or repositories.
- Order: sources, repositories, use cases. Cubits are **not** registered globally; pages create them with `BlocProvider` so they close with the route. Only truly app-wide cubits (auth, settings, connectivity) are global.
- Use `lazy: false` only for services that must start eagerly (listeners). Provide `dispose:` for anything with `close()`/`dispose()`.
- Do not use static singletons or service locators alongside provider.

## Routing (auto_route)

- Each feature declares its routes in `<feature>_routes.dart` (a list of `AutoRoute`). `router/app_router.dart` assembles them.
- Pages are annotated `@RoutePage()` and provide their cubit via `AutoRouteWrapper`.
- Route parameters are primitives/ids; load the data in the cubit. Do not pass entities through routes unless they are tiny and immutable.
- **Guards** (auth redirect) live in `router/`, listen to the auth cubit via `reevaluateListenable`.
- Features never import another feature's pages. For cross-feature navigation, use either:
  - a generated route from `router/` (simple), or
  - an abstract navigation interface declared in the feature and implemented in `router/` (when you want hard decoupling).
- Disabled features (flags) are excluded from both the route list and the provider list.

## Configuration and flavors

- `bootstrap/app_config.dart` reads `String/bool.fromEnvironment` constants; keep them `const` so unused code is tree-shaken.
- One env file per flavor (`config/dev.env`, `qa.env`, `prod.env`), run with `--dart-define-from-file`.
- Typical keys: `environment`, `apiUrl`, `sentryDsn`, `useMocks`, `<feature>Enabled`.
- Never commit real secrets in env files; use CI secrets for production values.
- Runtime toggles (remote flags) are for behavior changes after release; compile-time flags are for including/excluding code per build.

## Checklist before finishing

- [ ] Feature providers registered by interface, spread in `global_providers.dart`
- [ ] No `context.read` outside `create:` callbacks / page wrappers
- [ ] Routes registered; guard behavior verified for logged-out and logged-in
- [ ] Mock and real repository selectable via `AppConfig`

## Bundled files

- `references/cross-feature-navigation.md`: route-based vs interface-based navigation, sharing data between features
