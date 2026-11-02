---
name: clean-arch-di-routing
description: Use when wiring a Flutter Clean Architecture feature into the app: writing <feature>_providers.dart, editing bootstrap/global_providers.dart, choosing provider vs get_it, async startup dependencies, registering routes and guards (auto_route or go_router), AppConfig flavors/feature flags, or choosing mock vs real repositories.
---

# DI, routing and configuration rules

## Dependency injection (provider)

- **One composition root**: `bootstrap/global_providers.dart` defines a `GlobalProviders` widget that builds shared services (HTTP client, storage, auth cubit, logger) and spreads each feature's provider list. Wrap the app core (`AppCore` / `MaterialApp.router`) in `GlobalProviders`, so it sits **above the navigator** and every route can read global dependencies.
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

- **Create the value inside `create:`.** Do not build it outside and pass it with `Provider.value` (not even from a value cached in the widget); `.value` is for values that already exist and are owned elsewhere (for example the result of async startup loading).
- Dependencies flow through **constructors**. `context.read` appears only in `create:` callbacks and page wrappers, never inside cubits, use cases or repositories.
- Order: sources, repositories, use cases. A thin feature registers nothing of its own (its cubit takes the typed API client from `core/`). Cubits are **not** registered globally; pages create them with `BlocProvider` so they close with the route. Only truly app-wide cubits (auth, settings, connectivity) are global.
- **Page-scoped dependencies are provided by the page.** The public `<Feature>Page` creates its cubit with `BlocProvider`; the private `_<Feature>Content` underneath reads it. This lets the content be tested with a mocked cubit. Never create a cubit inside `build`.
- Use `lazy: false` only for services that must start eagerly (listeners). Provide `dispose:` for anything with `close()`/`dispose()`.
- Do not use static singletons or service locators alongside provider.

### Provider and tree depth (large apps)

Every dependency provided with `provider` adds a widget to the tree. Flutter has an implicit tree-depth limit, so an app with a **very large number of global dependencies** can fail at runtime with a stack overflow. For small and medium apps this does not matter. For **large projects** (dozens of global dependencies) decide the DI mechanism case by case; there is no single battle-tested replacement. Typical choices:

- Keep `provider` for page-scoped things (cubits, form cubits) and move the many global services to a locator (`get_it`) in the composition root.
- Group related services into one object so one provider supplies several.

Start with `provider` and revisit when the global provider list grows large.

### If the app already uses get_it (or you move global services to it)

Do not introduce `get_it` into a small project that uses `provider`, and do not migrate a working `get_it` app just to follow this plugin. Where `get_it` is in use, keep the same rules:

- Register in the composition root only (`bootstrap/`, one `register<Feature>()` function per feature, called from there). It is the only place that may import both `domain` and `data`.
- Register repositories by **interface type** and pick mock or real with `AppConfig.useMocks`: `getIt.registerLazySingleton<AccountsRepository>(() => AccountsRepositoryImpl(getIt()))`.
- Use cases are factories or lazy singletons. Cubits are **factories** (`registerFactory`) so each page gets a fresh one; close them with the route (`BlocProvider(create: ...)`).
- Dependencies still flow through **constructors**. `getIt<X>()` never appears inside a cubit, use case, repository or widget `build`; it appears only in registration code and page `create:` callbacks.
- In tests, `getIt.reset()` in `setUp` and register fakes. Prefer passing fakes straight to constructors.
- Never use both `provider` and `get_it` for the same kind of dependency.

## Async startup

- **Quick, cannot fail** (for example `SharedPreferences.getInstance`): await it in `main` before `runApp`, then provide the instance. Keep this tiny: the splash screen stays up until it finishes, and there is no way to show an error before `runApp`.
- **Can fail, can be slow, needs retry** (force-update check, remote feature flags, session restore): load it in **one** wrapper widget inside `GlobalProviders` that shows loading and error (with retry) states and provides the results. Parallelize the loading and place the widget as low in the tree as possible. See `references/async-initialization.md`.

## Routing

Use the router the project already uses; the repository supports both. Do not mix them in one app.

Common rules (both routers):

- Each feature declares its routes in `<feature>_routes.dart`; the router assembles them.
- Route parameters are **primitives/ids**; load the data in the cubit. Do not pass entities through routes (data passed in `extra` is lost on reload; the exception is internal state that must not appear in the URL, such as auth information).
- Prefer **path parameters over query parameters**: query parameters are not tied to one route and are never cleared as the stack changes.
- **Guards** (auth redirect) live in `router/` and listen to the auth cubit.
- Features never import another feature's pages. For cross-feature navigation use a generated route from `router/`, or an abstract navigation interface declared in the feature and implemented in `router/`.
- Disabled features (flags) are excluded from both the route list and the provider list.
- Define **explicit deep-link paths** for URLs you send to users (emails, push notifications) and redirect them to the real locations, so you can restructure navigation without breaking old links.

### auto_route

- Pages are annotated `@RoutePage()` and provide their cubit via `AutoRouteWrapper`.
- Routes are `AutoRoute` lists in `<feature>_routes.dart`, assembled in `router/app_router.dart`.
- Navigate with the generated route (`context.router.push(TransferRoute(accountId: id))`).

### go_router

See `references/go-router.md`: type-safe routes, route tree in its own file, pages exposed by features and wired by the app, `go` over `push`, naming conventions.

## Configuration and flavors

- `bootstrap/app_config.dart` reads `String/bool.fromEnvironment` constants; keep them `const` so unused code is tree-shaken.
- One env file per flavor (`config/dev.env`, `qa.env`, `prod.env`), run with `--dart-define-from-file`.
- Typical keys: `environment`, `apiUrl`, `sentryDsn`, `useMocks`, `<feature>Enabled`.
- Never commit real secrets in env files; use CI secrets for production values.
- Runtime toggles (remote flags) are for behavior changes after release; compile-time flags are for including/excluding code per build.

## Checklist before finishing

- [ ] Feature providers registered by interface, spread in `global_providers.dart` (or registered in the `get_it` composition root)
- [ ] No `context.read` (or `getIt<X>()` in a `get_it` app) outside registration code and `create:` callbacks / page wrappers
- [ ] Values created in `create:`, not passed through `Provider.value`; no cubit created inside `build`
- [ ] Routes registered with the project's router; guard behavior verified for logged-out and logged-in
- [ ] Mock and real repository selectable via `AppConfig`

## Bundled files

- `references/go-router.md`: go_router rules and examples
- `references/async-initialization.md`: resilient startup loader pattern
- `references/cross-feature-navigation.md`: route-based vs interface-based navigation, sharing data between features
- `references/getx-routing-migration.md`: GetX navigation to go_router or auto_route mapping, used by `/route`
- `references/getx-di-migration.md`: GetX DI to get_it (+ injectable) or provider mapping, used by `/di`
- `scripts/route_scan.sh` and `scripts/di_scan.sh`: read-only inventories of GetX routing and of the classes to register
