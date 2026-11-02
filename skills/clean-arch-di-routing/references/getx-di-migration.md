# GetX dependency injection to get_it (+ injectable) or provider

Used by `/di`. Two targets; ask the user if they did not say which, and keep the one already in `pubspec.yaml` if there is one. Never use both for the same kind of dependency. The base rules are in `SKILL.md` (provider, get_it section); this file adds the GetX mapping and the `injectable` variant.

## Common rules

- **One composition root**: `bootstrap/` (and each feature's wiring file) is the only code that may import both `domain` and `data`.
- Register by **interface type**; the implementation is chosen in the root, mock or real via `AppConfig.useMocks`.
- Order: data sources, repositories, use cases. Thin features register nothing of their own.
- **Constructors only.** No `Get.find`, `getIt<X>()` or `context.read` inside a cubit, use case, repository or a widget `build`. The only places: registration code and the page's `BlocProvider(create: ...)`.
- Cubits are **not** global: pages create them (`BlocProvider`) so they close with the route. Only app-wide ones (auth, settings, connectivity) are registered globally.
- The domain stays pure Dart: **no `injectable` annotations on domain or data classes**. Use module classes in the wiring file instead.

## GetX to registrations

| GetX | Replace with |
|---|---|
| `Get.put(X())` in `main` / a `Binding` | eager registration in the root |
| `Get.lazyPut(() => X())` | lazy registration (`registerLazySingleton` / `@lazySingleton` / a lazy `Provider`) |
| `Get.lazyPut(..., fenix: true)` | lazy registration; if it must be rebuilt after disposal, a factory |
| `Get.put(X(), permanent: true)` | singleton |
| `Get.create(() => X())` | factory |
| `Get.find<X>()` inside a class | constructor parameter of type `X` (interface when it exists) |
| `Get.find<X>()` in a widget | the page reads it in `BlocProvider(create: ...)`; deeper widgets receive the cubit from context |
| `class XBinding extends Bindings` | the feature's `register<Feature>()` / module / providers list |
| `GetxService` | singleton with explicit `dispose`/`close` if it holds resources |
| `Get.isRegistered<X>()` | remove; fix the ownership instead |
| `tag:` | named registration (`instanceName`) only if truly needed; otherwise two distinct types |

A `Get.find` that cannot become a constructor parameter (a class created by the framework, a static helper) is listed in the report, not guessed.

## Target A: get_it + injectable

Dependencies: `get_it`, `injectable`; dev: `injectable_generator`, `build_runner`.

`bootstrap/injection.dart`:

```dart
final getIt = GetIt.instance;

@InjectableInit()
Future<void> configureDependencies() => getIt.init();   // init() comes from the generated injection.config.dart
```

`main`: `await configureDependencies();` before `runApp`.

Per feature, one module in `features/<feature>/<feature>_di.dart` (the only file that sees `domain` and `data`):

```dart
@module
abstract class AccountsModule {
  @lazySingleton
  RemoteAccountsDataSource dataSource(ApiClient client) => RemoteAccountsDataSource(client);

  @lazySingleton
  AccountsRepository repository(RemoteAccountsDataSource source) =>
      AppConfig.useMocks ? MockAccountsRepository() : AccountsRepositoryImpl(source);

  @injectable
  GetAccounts getAccounts(AccountsRepository repository) => GetAccounts(repository);

  @injectable      // a factory: each page gets a fresh cubit
  AccountsCubit cubit(GetAccounts getAccounts) => AccountsCubit(getAccounts);
}
```

Page: `BlocProvider(create: (_) => getIt<AccountsCubit>(), child: ...)`. Tests: `getIt.reset()` in `setUp`, or pass fakes to constructors.

Then the user (or the command after asking) runs `dart run build_runner build --delete-conflicting-outputs`. Annotation names and the `init()` shape depend on the installed `injectable` major version: read its README/CHANGELOG in the pub cache and match it.

Without `injectable` (plain get_it): the same module becomes `void register<Feature>(GetIt getIt)` calling `registerLazySingleton<Interface>(() => Impl(getIt()))` and `registerFactory(() => XCubit(getIt()))`, called from `bootstrap/`.

## Target B: provider

Dependencies: `provider`. Cubits come from `flutter_bloc`.

`features/<feature>/<feature>_providers.dart`:

```dart
final accountsProviders = <SingleChildWidget>[
  Provider<RemoteAccountsDataSource>(create: (c) => RemoteAccountsDataSource(c.read())),
  Provider<AccountsRepository>(
    create: (c) => AppConfig.useMocks
        ? MockAccountsRepository()
        : AccountsRepositoryImpl(c.read<RemoteAccountsDataSource>()),
  ),
  Provider(create: (c) => GetAccounts(c.read())),
];
```

`bootstrap/global_providers.dart`: a `GlobalProviders` widget with `MultiProvider(providers: [...coreProviders, ...accountsProviders], child: child)`, placed **above** `MaterialApp.router`, so every route can read it.

- Create values inside `create:`; `Provider.value` only for values owned elsewhere (async startup results).
- Use **`ProxyProvider`** only when a dependency must be rebuilt when an upstream value changes over time (for example an `ApiClient` that depends on the current auth token): `ProxyProvider<AuthCubit, ApiClient>(update: (_, auth, previous) => ...)`. For everything else a plain `Provider` with `context.read` in `create:` is simpler.
- Provide `dispose:` for anything with `close()`/`dispose()`; `lazy: false` only for eager services.
- Large apps (dozens of global dependencies) can hit tree-depth limits: group related services, or keep page-scoped things in provider and move global services to get_it (see `SKILL.md`).

## Verification checklist

- [ ] No `Get.put/lazyPut/find`, `Bindings` or `GetxService` left (or listed with a reason)
- [ ] Every repository registered by interface; mock/real selected by `AppConfig`
- [ ] No locator or `context.read` inside cubits, use cases, repositories or `build`
- [ ] Cubits created by pages, not registered globally (unless app-wide)
- [ ] injectable: modules only, generated file present, `configureDependencies()` awaited in `main`
- [ ] `check_dependencies.sh` and `flutter analyze` not worse than before
