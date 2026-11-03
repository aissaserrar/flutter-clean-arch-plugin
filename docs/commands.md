# Commands

Nine commands help move a legacy GetX app onto the architecture the skills describe. They apply the rules of the `clean-arch-*` skills; if a command and a skill ever disagree, the skill wins. The order they are designed to run in, and the safety gates they share, are defined once in [`skills/clean-arch-overview/references/migration-workflow.md`](../skills/clean-arch-overview/references/migration-workflow.md).

In Claude Code the commands are namespaced: `/flutter-clean-arch:audit`, `/flutter-clean-arch:pre-check`, and so on.

## Shared behaviour

Every command that edits files:

- requires a clean, committed git tree (otherwise it recommends `/pre-check` and asks; the default is to stop);
- records a `flutter analyze` baseline and compares against it after every batch;
- shows a plan with real numbers and asks you to confirm the scope, with a warning about how many files it will touch;
- works in small batches (one feature or one class), formats only the files it touched, and reports real results;
- marks what it cannot map safely with a `TODO(<command>)` comment instead of guessing;
- never edits files that carry the `DEPRECATED: migrated by /feature --migrate` header;
- never runs `flutter pub add`/`remove`, and never changes git state (the one exception is `--checkpoint`, below).

When there are two supported options (`go_router` or `auto_route`; `get_it` or `provider`) and `pubspec.yaml` does not already decide, the command asks you.

## `/audit [path]`

Read-only scan of the project. Writes `.clean-arch/audit-YYYY-MM-DD-HHMM.html` and a matching `.json` (every run is kept) and opens the report in your browser.

The report contains:

- **Primary signal — template distance:** score vs `docs/simplified-architecture-with-domain.md` (structure, stack, presentation, domain/data, errors, boundaries, composition). Headline is `very_far` / `far` / `approaching` / `compliant` and score/100, not GetX volume.
- **Secondary:** GetX inventory, import-rule violations, engineering heuristics (custom cubit bases, BondFire-in-cubit is also a template blocker, file size, etc.).
- Status values still `compliant` / `compliant_with_warnings` / `needs_migration` / `non_compliant`, but they follow **template distance**, not “GetX is zero.”
- **Architecture, today and target:** your real folders (file, GetX and Cubit/Bloc counts) next to the structure the skills prescribe, filled with your feature names. Both trees are expandable; small projects open fully, large ones open the legacy folders and keep crowded folders closed.
- **Migration plan, feature by feature** (when GetX controllers exist): feature units grouped by the code's own structure, rated low / medium / high risk by how many other features use their controllers, size, forms and navigation inside controllers, and ordered into waves from isolated quick wins to the large shared ones. Each unit lists its controllers in conversion order, what each becomes, and the commands to run. The plan follows your project's own decisions (see below).
- **Suggested next steps** computed from your numbers, in migration-workflow order.
- **Progress since the previous audit**, the GetX breakdown by area, layer violations, features, packages, and what the audit covers and does not.

How it counts:

- Cubits, Blocs and GetX controllers are found through your own base classes (`DataCubit` → `BaseCubit` → `Cubit`, `GetxFormController` → `GetxController`), also when a class header spans several lines.
- "GetX" means the whole package API (state, navigation, DI, UI helpers, translations, network, workers, extensions), taken from the package's API reference. The catalog lives in one place (`skills/clean-arch-overview/scripts/detect.sh`).
- Generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, `app_localizations*.dart`) are ignored.

**Project conventions.** `conventions_scan.sh` reads `CLAUDE.md`, `AGENTS.md`, `.claude/skills/*` and `.clean-arch/config.json` and infers the project's own decisions (for example: ChangeNotifier forbidden, navigation stays on GetX, tests only on request), each with the line it came from. Three settings drive the plan:

| Setting | Values | Meaning |
|---|---|---|
| `mode` | `direct` / `interim` | `direct` (default): GetX controller straight to Cubit. `interim`: via ChangeNotifier first (rewrites each controller twice) |
| `scope` | `state` / `full` | `state`: migrate state management only. `full`: remove GetX completely |
| `structure` | `true` / `false` | also move files into `lib/features/<name>/` |

When they are assumed rather than saved in `.clean-arch/config.json`, the report says so and `/audit` asks once and saves the answer.

## `/foundation [--router none|go_router|auto_route] [--di get_it|provider]`

Scaffolds the shared foundation: `lib/bootstrap/` (`app_config` + get_it `injection` or provider `global_providers`), `lib/core/error/result.dart` (`Result` + `AppFailure`), `lib/design_system/` (README). Optional `--migrate-ds high|all|id,…` copies legacy `lib/widgets/`, `lib/config/themes/`, etc. into `design_system/` via `feature_apply --keep-deprecated`. Optional `lib/router/` stub. Never overwrites, never `pub add`. Default `--router none` when GetX navigation is kept. Clears audit blockers `has_bootstrap`, `has_result_type`, `has_app_failure` (and design_system major). Scripts: `foundation_scan.sh`, `foundation_apply.sh`.

## `/pre-check [feature | path ...]`

Safety dry-run before a refactor. Runs `flutter analyze` (errors block), checks git (not a repository or uncommitted changes block; being on `main`, untracked files or being behind only warn) and measures the targets: files, lines, GetX hits, Cubit/Bloc files, outside callers, which files have tests. Prints GO, GO with cautions or NO-GO. Changes nothing.

## `/feature <name> --migrate`

Brings the scattered legacy files of one feature (controllers, views, models, services, repositories, bindings) into `lib/features/<name>/{data,domain,presentation}`.

1. Scans and proposes where each file goes, with a confidence level.
2. After you confirm, **copies** the files. The originals stay in place, marked deprecated (a header comment plus `@Deprecated` on each top-level declaration).
3. Rewrites every import elsewhere to the new path, checks that all imports still resolve, then runs the dependency checker.

File and class names stay the same. Nothing is deleted.

## `/route [--go-router | --auto-route] [feature ...]`

Replaces GetX routing with one centralized router. Asks **GoRouter or AutoRoute** unless you pass a flag or `pubspec.yaml` already has one. Creates a route per `GetPage` (kebab-case paths, ids as path parameters, typed routes for go_router), turns `GetMiddleware` into a redirect or guard, rewrites `Get.to` / `toNamed` / `off*` / `back` / `arguments`, and converts `GetMaterialApp` to `MaterialApp.router` last. Navigation inside controllers is left with a TODO for a presentation event (`/to-bloc`).

## `/di [--get-it | --provider] [feature ...]`

Dependency injection without GetX lookups. Asks **GetIt (with injectable) or Provider** unless decided. Registers data sources, repositories (by interface), use cases and cubits per feature in one composition root: a `MultiProvider` (with `ProxyProvider` only where a dependency changes over time), or injectable `@module` classes that keep `domain` free of annotations. Replaces `Get.put` / `lazyPut` / `find` and `Bindings`. Runs `build_runner` only after asking.

## `/kill-getx [feature | path ...]`

Removes GetX in confirmed batches, to a plain-Flutter **interim form** (`ChangeNotifier` + `ListenableBuilder`) that compiles and behaves the same; `/to-bloc` then makes the Cubits.

- Stops first if the app still navigates with GetX and no router package is installed, and asks you to run `/route`.
- `package:get` imports are removed only from files that no longer use anything from GetX (including GetX extensions such as `2.seconds`).
- Navigation, `Get.find`/bindings and snackbars/dialogs/`.tr` are reported, not rewritten.

## `/to-bloc [feature | path ...]`

Converts state holders into Cubits, or Blocs only where event transformers are needed (debounced search, droppable submit). One file per cubit in the plugin's order (cubit, events, state, presentation events) with sealed `Initial/Loading/Success/Failure` states. Updates the UI: the page provides the cubit with `BlocProvider`, `ListenableBuilder` / `Consumer` become `BlocBuilder`, one-off effects use `BlocPresentationListener`. One class at a time, an analyzer check after each, optional `bloc_test` tests. Stops with the `flutter pub add` command if `flutter_bloc` or `equatable` are missing.

## `/e2e [flow ...]`

Scaffolds and, if you agree, runs Patrol end-to-end tests. Checks readiness (patrol, patrol_cli, Android/iOS native setup, a mock-backed start, widget keys), proposes three to five flows including native ones (permission dialogs, notifications), writes `patrol_test/<flow>_test.dart` from templates after checking method names against the installed Patrol version, and runs `patrol test` on a connected device. Reports "not run" when no device is available.

## Batch loop: `--batches N` and `--checkpoint` (`/kill-getx` and `/to-bloc` only)

A real app needs dozens of batches. `--batches N` (1 to 10) runs up to N after **one** confirmation that states the expected file count and the stop conditions. Without the flag you are asked before each batch.

The loop stops by itself when: the analyzer reports more errors than the baseline; a file needed more than two fix attempts; a batch added a `TODO` that needs a human decision; a batch changed more than 15 files or touched files outside the plan; something outside the loop edited the project; a gate no longer holds; or N is reached. It never deletes old controllers or classes on its own. Each batch ends with a summary and a progress line (the audit delta).

`--checkpoint` asks once for permission to create a branch (when you are on `main`, `master` or `develop`) and to commit each batch's files, so every batch is one revertable commit. It never pushes, amends, rebases, forces, stashes or resets, and stages only files that batch changed.

## `/migrate [--checkpoint] [--resume] [feature ...]`

Runs the whole migration through the other commands, feature by feature, in the audit plan's wave order. It checks the prerequisites, asks once for confirmation (real file counts and stop conditions), does `/route` and `/di` once when the scope is full, then for each feature: `/pre-check`, `/feature --migrate` (when files move), `/to-bloc`, `/kill-getx` for leftovers, an analyzer check against the baseline and a fresh audit. After each feature it asks whether to write and run an e2e test for it; declining moves on to the next feature. Progress is saved in `.clean-arch/progress.json`, so a stopped run resumes where it left off. A feature that fails twice or needs a human decision is marked blocked, skipped and listed at the end. Details: `skills/clean-arch-migrate/references/migrate-loop.md`.

## What each command runs

| Command | Read-only scanner | Edits files | Other things it may run |
|---|---|---|---|
| `/audit` | `audit.sh`, `migration_plan.sh`, `conventions_scan.sh` | writes `.clean-arch/` only | opens the report with `open` / `xdg-open` / `start` |
| `/foundation` | `foundation_scan.sh` | `foundation_apply.sh` after confirm | `dart format` on created files |
| `/pre-check` | `pre_check.sh` | no | `flutter analyze --no-pub`, read-only `git` queries |
| `/feature` | `feature_scan.sh` | `feature_apply.sh` after you confirm | dependency checker |
| `/route` | `route_scan.sh` | Claude, in confirmed steps | `flutter analyze`; `build_runner` after asking |
| `/di` | `di_scan.sh` | Claude, in confirmed steps | `flutter analyze`; `build_runner` after asking |
| `/kill-getx` | `kill_getx_scan.sh` | Claude, in confirmed batches; `kill_getx_finish.sh --apply` removes unused imports | `flutter analyze` |
| `/to-bloc` | `to_bloc_scan.sh` | Claude, one confirmed class at a time | `flutter analyze`; `flutter test` on tests you asked for |
| `/migrate` | `migration_plan.sh`, `migrate_state.sh` | `.clean-arch/progress.json`; the other commands edit the project | the commands it drives |
| `/e2e` | `e2e_scan.sh` | test files; native files and `pubspec.yaml` only after asking | `patrol test` after you agree |

No command uses the network, installs packages, or edits `pubspec.yaml` on its own.
