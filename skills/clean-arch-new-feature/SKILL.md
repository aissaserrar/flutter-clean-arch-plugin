---
name: clean-arch-new-feature
description: Use when asked to add a new feature, screen, or flow to a Flutter app using Clean Architecture with Bloc/Cubit. Chooses the feature shape (thin, with repository, full domain), then gives the ordered workflow across domain, data, presentation, UI, forms, analytics, DI/routing and tests, and tells which layer skill to apply at each step.
---

# New feature workflow

Build inside-out: domain first (if the feature has one), UI last. Load the named skill at each step and follow its rules.

## 0. Clarify (before writing code)

Decide and state, in a few lines:
- Feature name and what the user can do (the use cases).
- Data source: real API, mock only, or both.
- **Feature shape** (see `clean-arch-overview`):
  - **Thin** (presentation only): screen-ready data from a BFF; the cubit calls the typed API client. Skip steps 1 and 2.
  - **With repository**: caching, merging sources, or complex mapping. Do step 2 (and the repository interface from step 1); use cases are optional.
  - **Full domain**: business rules, logic reused by several cubits, a feature exposing data to others, or a swappable implementation. Do every step.
  Do not add a layer "just in case", and do not mix shapes inside one feature.
- Does it have forms? Which analytics ids does it need?
- Navigation entry and exit points, which router the app uses (auto_route or go_router), and any cross-feature interaction (use `core/` after the rule of three, the other feature's barrel, or an interface; never import another feature).
- Flag needed in `AppConfig`?

## 1. Domain, skill `clean-arch-domain`

(Skip for a thin feature.)

1. Entities (and value objects).
2. Abstract repository interface returning entities/`Result` (only if the feature has a repository).
3. Use cases, one per action (only where there is logic or reuse).
4. Domain failures (sealed, extending `AppFailure`).
5. Tests for entities and use cases.

## 2. Data, skill `clean-arch-data`

(Skip for a thin feature.)

1. Prefer generated contracts; otherwise DTOs with `json_serializable` (`dart run build_runner build --delete-conflicting-outputs`).
2. Mappers.
3. Data sources (remote/local) if needed.
4. `RepositoryImpl` with exception to `Failure` mapping.
5. `Mock<Feature>Repository`.
6. Tests for mappers and repository.

## 3. Presentation, skill `clean-arch-presentation`

1. Sealed state `<Feature>State` with `Initial`/`Loading`/`Success`/`Failure` variants (and events if Bloc, presentation events for side effects), all in one file.
2. Cubit/Bloc depending on use cases, the repository interface, or the API client, as decided in step 0.
3. `bloc_test` tests.

## 4. UI, skill `clean-arch-ui` (forms: `clean-arch-forms`)

1. Public `<Feature>Page` that provides the cubit, private `_<Feature>Content` underneath.
2. Exhaustive state switch, loading/error+retry/empty states from the shared patterns, presentation-event listener.
3. Form cubits and form widgets if the feature has forms.
4. L10n strings in `.arb` files; regenerate localizations.
5. Widget tests with a mocked cubit.

## 5. Analytics and logging, skill `clean-arch-observability`

1. `<feature>_ids.dart` with the page id(s) and an id for every button.
2. Log caught expected exceptions; no sensitive data in logs.

## 6. Wiring, skill `clean-arch-di-routing`

1. `<feature>_routes.dart` and registration in the router (auto_route or go_router, as the app uses).
2. `<feature>_providers.dart` (when the feature has data sources, repositories or use cases) spread into `bootstrap/global_providers.dart`.
3. `AppConfig` flag if the feature is switchable; exclude routes and providers when off.
4. Regenerate router code.

## 7. Verify, skill `clean-arch-testing`

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
- Do not modify other features. If shared code is needed, apply the rule of three, move it to `core/`, and say so.
- Summarize at the end: the feature shape chosen and why, files created, decisions made (use cases or not, mocks), what was verified, and anything left undone.

## Bundled files

- `templates/README.md`: placeholder table and resulting layout
- `templates/domain.dart.tpl`, `data.dart.tpl`, `presentation.dart.tpl`, `wiring.dart.tpl`, `ids.dart.tpl`: skeletons with `{{feature}}`, `{{Feature}}`, `{{entity}}`, `{{Entity}}`, `{{app}}` placeholders. Each file contains several `// ===== path =====` sections: split them into the files named in the headers.
- `references/feature-checklist.md`: definition of done
- Dependency check: `bash ${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/scripts/check_dependencies.sh lib`
