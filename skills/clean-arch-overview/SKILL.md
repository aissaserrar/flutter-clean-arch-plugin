---
name: clean-arch-overview
description: Use when starting work on, planning, or reviewing the structure of a Flutter app that uses Clean Architecture with Bloc/Cubit. Explains the feature shapes (thin, with repository, full domain), layers, folder structure, dependency direction, rules for shared code, and which skill to load next. Use before creating features, moving files, or deciding where code belongs.
---

# Clean Architecture for Flutter + Bloc: overview

Feature-first. Inside each feature that has layers: `presentation -> domain <- data`. Not every feature needs every layer (see "Feature shapes").

## Folder structure

Scope: a **single Flutter app package**. `core/` and `design_system/` are folders inside `lib/`, not separate packages. Monorepos (an app plus several packages) are out of scope.

```
lib/
├── main.dart / app.dart
├── bootstrap/            # app_config.dart, global_providers.dart (composition root)
├── router/               # routes, guards (auto_route or go_router)
├── core/                 # cross-feature code, grouped by function: auth, http (typed API client), storage, logging, analytics, error (AppFailure, Result), utils
├── design_system/        # tokens, theme, ALL reusable UI components (no business logic)
├── l10n/
└── features/<feature>/
    ├── <feature>_ids.dart        # analytics ids (see clean-arch-observability)
    ├── domain/           # entities/, repositories/ (abstract), use_cases/    (when the feature needs it)
    ├── data/             # dtos/, mappers/, sources/, <feature>_repository_impl.dart, mock_<feature>_repository.dart
    ├── presentation/     # cubit/ (or bloc/), ui/ (pages, widgets)
    ├── <feature>_routes.dart
    └── <feature>_providers.dart
test/                     # mirrors lib/
```

Single-page feature with no layers: files may sit flat in the feature folder (`<feature>_page.dart`, `<feature>_cubit.dart`, `<feature>_ids.dart`). Multi-page features get one subfolder per page plus a shared `widgets/`.

## Feature shapes: pick the smallest that fits, state the choice

| Shape | Use when | Cubit depends on |
|---|---|---|
| **Thin** (presentation only) | The backend is a BFF returning screen-ready data, and a call to the typed API client is all that happens | The strongly typed **API client** in `core/http` (generated contracts preferred) |
| **With repository** | There is caching, several sources to merge (remote + local), or complex mapping because the API was not designed for this app | The **repository interface** |
| **Full domain** | Business rules, logic reused by several cubits, a feature exposing data to others, or an implementation that must be swappable/fakeable | **Use cases** |

- Do not add a repository layer "just in case"; do not call the API client from a cubit once there is caching, merging or non-trivial mapping.
- Pick one shape per feature and state it. Do not mix shapes inside one feature. Different features may use different shapes.
- A repository, when present, is always an interface declared in `domain/repositories/` (or in a small `domain/` that holds only that interface), implemented in `data/`.

## Dependency rules (non-negotiable)

1. `domain` imports nothing from `data`, `presentation`, Flutter, HTTP, JSON or storage packages. Plain Dart (plus `equatable`/`meta` at most).
2. `data` imports `domain` and implements its interfaces.
3. `presentation` imports `domain` only. Never `data`.
4. Only `<feature>_providers.dart` and `bootstrap/` may import both `domain` and `data`.
5. A feature never imports another feature. Shared code goes to `core/`, or the other feature exposes a use case or interface in its barrel file.
6. `core/` and `design_system/` never import `features/`.

## Shared code (`core/`): avoid it until it is needed

- **Rule of three:** start in the feature that owns the code. Extract to `core/` only when at least **three** places reuse it. Shared code is costly to maintain and often is not as universal as it looks; accept some duplication before that.
- `core/` holds **behavior and infrastructure** (`FeatureFlagBuilder`, formatters, http client, logging), never business-specific code.
- **No reusable UI components in `core/`**: they go in `design_system/`.
- Group files by function (`formatters/`, `widgets/`), not by feature.
- **All shared code is fully tested.** (This also discourages extracting it prematurely.)

## Code style

- No `part` / `part of`, except for generated code (`*.g.dart`, `copy_with_extension_gen`).
- Generate `copyWith` with `copy_with_extension_gen`, and only where a class needs it.
- Prefer returning failure objects over throwing (see `clean-arch-domain`).

## Which skill to load

| Task | Skill |
|---|---|
| Entities, repository interfaces, use cases, failures | `clean-arch-domain` |
| DTOs, mappers, data sources, repository impl, API client, error mapping | `clean-arch-data` |
| Cubit/Bloc, state classes, presentation events | `clean-arch-presentation` |
| Pages, widgets, error/loading UI, localization | `clean-arch-ui` |
| Forms | `clean-arch-forms` |
| Provider/get_it wiring, routes (auto_route or go_router), config/flavors, async startup | `clean-arch-di-routing` |
| Logging and analytics | `clean-arch-observability` |
| Writing tests | `clean-arch-testing` |
| Building a whole feature end to end | `clean-arch-new-feature` |

When reviewing code, flag any import that violates the rules above before anything else.

## Bundled files

- `references/folder-structure.md`: full tree, naming conventions, per-folder import map
- `../clean-arch-domain/references/when-to-use-interfaces.md`: rule of thumb for interfaces vs concrete classes
- `scripts/check_dependencies.sh [lib_dir]`: verifies the import rules above (exit 1 on violations). Run it after creating or moving files and before finishing a review:
  `bash ${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/scripts/check_dependencies.sh lib`
