# Full folder structure with explanations

```
lib/
├── main.dart                        # init Sentry/Firebase, runApp(GlobalProviders(App()))
├── app.dart                         # MaterialApp.router, theme, localization delegates
│
├── bootstrap/
│   ├── app_config.dart              # --dart-define values (const)
│   └── global_providers.dart        # composition root
│
├── router/
│   ├── app_router.dart              # assembles feature routes, guards
│   └── app_router.gr.dart           # generated
│
├── core/                            # shared across features, extracted by the rule of three. NEVER imports features/
│   ├── auth/                        # AuthCubit / session
│   ├── error/                       # Result, Success, Failure, AppFailure, shared failures
│   ├── http/                        # client, interceptors, ApiException
│   ├── storage/                     # key-value wrapper, typed keys
│   ├── logging/ analytics/ connectivity/ feature_flags/
│   ├── domain/                      # entities shared by several features (Money, User)
│   └── utils/
│
├── design_system/                   # tokens, theme, generic widgets. No business logic
├── l10n/                            # .arb + generated localizations
│
└── features/
    └── <feature>/
        ├── <feature>.dart           # optional barrel: public API for other layers (routes, exposed use cases)
        ├── <feature>_ids.dart       # analytics ids (<Feature>AnalyticsId)
        ├── <feature>_routes.dart
        ├── <feature>_providers.dart # only file that sees domain AND data
        ├── domain/                  # pure Dart
        ├── data/
        └── presentation/{cubit|bloc, ui}
```

## Naming

| Thing | Convention | Example |
|---|---|---|
| Entity | noun, no suffix | `Account` |
| DTO | `<Name>Dto` | `AccountDto` |
| Repository interface | `<Feature>Repository` | `AccountsRepository` |
| Repository impl | `<Feature>RepositoryImpl`; mock: `Mock<Feature>Repository` | |
| Use case | verb phrase | `TransferMoney` |
| Data source | `Remote<..>DataSource` / `Local<..>DataSource` | |
| Cubit / Bloc | `<Feature>Cubit` / `<Feature>Bloc` | |
| State | `<Feature>State` + `<Feature>State<Initial\|Loading\|Success\|Failure>` | `TransferStateLoading` |
| Page (public, provides its cubit) / content (private) | `<Feature>Page` / `_<Feature>Content` | `TransferPage` / `_TransferContent` |
| Other private widgets | `_<Thing>Tile`, `_<Thing>Form` | |
| Analytics ids | `<feature>_ids.dart` → `<Feature>AnalyticsId` | |

## Import map

| From | May import |
|---|---|
| `features/x/domain` | `core/error`, `core/domain`, `dart:*`, `equatable`, `meta` |
| `features/x/data` | own `domain`, `core/*`, `json_annotation`, HTTP and storage packages |
| `features/x/presentation` | own `domain`, `core/*`, `design_system`, `l10n`, `flutter_bloc`, `auto_route` |
| `features/x/*_providers.dart` | own `domain` and `data`, `core/*`, `bootstrap/app_config` |
| `core/*`, `design_system` | each other as needed, never `features/` |
| `router/`, `bootstrap/` | everything |
