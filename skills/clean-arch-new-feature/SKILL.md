---
name: clean-arch-new-feature
description: Use when asked to add a new feature, screen, or flow to a Flutter app using Clean Architecture with Bloc/Cubit. Gives the ordered workflow across domain, data, presentation, UI, DI/routing and tests, and tells which layer skill to apply at each step.
---

# New feature workflow

Build inside-out: domain first, UI last. Load the named skill at each step and follow its rules.

## 0. Clarify (before writing code)

Decide and state, in a few lines:
- Feature name and what the user can do (the use cases).
- Data source: real API, mock only, or both.
- Does it have business rules or combine data sources? If yes, use the full domain layer. If it is a pure display of screen-ready data, a thin feature may skip use cases; state that choice.
- Navigation entry and exit points; any cross-feature interaction (use `core/` or an interface, never import another feature).
- Flag needed in `AppConfig`?

## 1. Domain, skill `clean-arch-domain`

1. Entities (and value objects).
2. Abstract repository interface returning entities/`Result`.
3. Use cases, one per action.
4. Domain failures (sealed).
5. Tests for entities and use cases.

## 2. Data, skill `clean-arch-data`

1. DTOs with `json_serializable`; run `dart run build_runner build --delete-conflicting-outputs`.
2. Mappers.
3. Data sources (remote/local) if needed.
4. `RepositoryImpl` with exception to `Failure` mapping.
5. `Mock<Feature>Repository`.
6. Tests for mappers and repository.

## 3. Presentation, skill `clean-arch-presentation`

1. Sealed state class (and events if Bloc).
2. Cubit/Bloc depending on use cases only.
3. `bloc_test` tests.

## 4. UI, skill `clean-arch-ui`

1. Page with `@RoutePage()` and `AutoRouteWrapper` providing the cubit.
2. Private view widgets, exhaustive state switch, loading/error/empty states.
3. L10n strings in `.arb` files; regenerate localizations.
4. Widget tests with a mocked cubit.

## 5. Wiring, skill `clean-arch-di-routing`

1. `<feature>_routes.dart` and registration in `router/app_router.dart`.
2. `<feature>_providers.dart` and spread into `bootstrap/global_providers.dart`.
3. `AppConfig` flag if the feature is switchable; exclude routes and providers when off.
4. Regenerate router code.

## 6. Verify, skill `clean-arch-testing`

Run, and report real results:
```bash
dart format --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```
Then check dependency rules from `clean-arch-overview`: no `data/` import in presentation or domain, no cross-feature import, no Flutter import in domain. A quick check:
```bash
grep -rnE "import .*(flutter|/data/|/presentation/)" lib/features/<feature>/domain
grep -rn "import .*/data/" lib/features/<feature>/presentation
```

## Output expectations

- Create files in the structure from `clean-arch-overview`.
- Do not modify other features. If shared code is needed, move it to `core/` and say so.
- Summarize at the end: files created, decisions made (use cases or not, mocks), what was verified, and anything left undone.

## Bundled files

- `templates/README.md`: placeholder table and resulting layout
- `templates/domain.dart.tpl`, `data.dart.tpl`, `presentation.dart.tpl`, `wiring.dart.tpl`: skeletons with `{{feature}}`, `{{Feature}}`, `{{entity}}`, `{{Entity}}`, `{{app}}` placeholders. Each file contains several `// ===== path =====` sections: split them into the files named in the headers.
- `references/feature-checklist.md`: definition of done
- Dependency check: `bash ${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/scripts/check_dependencies.sh lib`
