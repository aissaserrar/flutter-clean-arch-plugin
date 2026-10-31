---
name: clean-arch-overview
description: Use when starting work on, planning, or reviewing the structure of a Flutter app that uses Clean Architecture with Bloc/Cubit. Explains the layers, folder structure, dependency direction and which layer skill to load next. Use before creating features, moving files, or deciding where code belongs.
---

# Clean Architecture for Flutter + Bloc: overview

Feature-first, single package. Inside each feature: `presentation -> domain <- data`.

## Folder structure

```
lib/
├── main.dart / app.dart
├── bootstrap/            # app_config.dart, global_providers.dart (composition root)
├── router/               # app_router.dart, guards
├── core/                 # cross-feature code: auth, http, storage, logging, error (Failure, Result), utils
├── design_system/        # tokens, theme, generic widgets (no business logic)
├── l10n/
└── features/<feature>/
    ├── domain/           # entities/, repositories/ (abstract), use_cases/
    ├── data/             # dtos/, mappers/, sources/, <feature>_repository_impl.dart
    ├── presentation/     # cubit/ (or bloc/), ui/ (pages, widgets)
    ├── <feature>_routes.dart
    └── <feature>_providers.dart
test/                     # mirrors lib/
```

## Dependency rules (non-negotiable)

1. `domain` imports nothing from `data`, `presentation`, Flutter, HTTP, JSON or storage packages. Plain Dart (plus `equatable`/`meta` at most).
2. `data` imports `domain` and implements its interfaces.
3. `presentation` imports `domain` only. Never `data`.
4. Only `<feature>_providers.dart` and `bootstrap/` may import both `domain` and `data`.
5. A feature never imports another feature. Shared code goes to `core/`, or the other feature exposes a use case or interface in its barrel file.
6. `core/` and `design_system/` never import `features/`.

## Which skill to load

| Task | Skill |
|---|---|
| Entities, repository interfaces, use cases | `clean-arch-domain` |
| DTOs, mappers, data sources, repository impl, error mapping | `clean-arch-data` |
| Cubit/Bloc and state classes | `clean-arch-presentation` |
| Pages and widgets | `clean-arch-ui` |
| Provider wiring, routes, config/flavors | `clean-arch-di-routing` |
| Writing tests | `clean-arch-testing` |
| Building a whole feature end to end | `clean-arch-new-feature` |

## Quick decision: does this need a domain layer?

Use `domain/` for a feature when it has business rules, combines data sources, shares logic between cubits, or must be swappable/fakeable. For a pure display feature backed by a screen-ready backend (BFF), a thin feature without use cases is acceptable. Pick one convention per feature and state it. Do not mix inside one feature.

When reviewing code, flag any import that violates the rules above before anything else.

## Bundled files

- `references/folder-structure.md`: full tree, naming conventions, per-folder import map
- `scripts/check_dependencies.sh [lib_dir]`: verifies the import rules above (exit 1 on violations). Run it after creating or moving files and before finishing a review:
  `bash ${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/scripts/check_dependencies.sh lib`
