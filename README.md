# flutter-clean-arch

Clean Architecture rules for Flutter apps that use Bloc/Cubit, packaged as Claude Code skills. When you ask Claude to add a feature, write a cubit, wire providers or write tests, it follows one consistent set of layer rules instead of guessing your structure each time.

It is based on [`docs/simplified-architecture-with-domain.md`](docs/simplified-architecture-with-domain.md), which is included in the plugin.

## What you get

- **Ten skills**, one per concern, that Claude loads automatically when your request matches.
- **An `/audit` command** that scans a project for layer violations and GetX leakage and opens the result as an HTML report.
- **A dependency checker** (`check_dependencies.sh`) that verifies the import rules in your `lib/` folder.
- **Feature templates** with placeholders for domain, data, presentation, wiring and analytics-id code.
- **Reference tables and checklists** that Claude reads only when it needs the detail.

## The architecture in one picture

Feature-first folders. Inside each feature the dependencies point inward:

```
presentation ──► domain ◄── data
 (cubit, ui)    (entities,   (repository impl,
                use cases,    DTOs, data sources)
                repo interfaces)
```

- `domain` is pure Dart: no Flutter, HTTP, JSON or storage packages.
- `data` implements the domain's repository interfaces.
- `presentation` talks to `domain` (or, in simpler features, to a repository interface or the typed API client), never to `data` internals.
- Only `<feature>_providers.dart` wires `domain` and `data` together.
- Features never import each other; shared code lives in `core/` and is extracted only after three reuses.

### Pick the smallest feature shape that fits

| Shape | Use when | Cubit depends on |
|---|---|---|
| **Thin** (presentation only) | Screen-ready data from a BFF | The typed API client |
| **With repository** | Caching, merged sources, complex mapping | The repository interface |
| **Full domain** | Business rules, shared logic, swappable implementation | Use cases |

## Requirements

The rules assume this stack. If yours differs, see [Customizing](#customizing).

| Concern | Package |
|---|---|
| State management | `flutter_bloc`, `bloc_presentation` (one-off side effects), `bloc_test` for tests |
| Navigation | `auto_route` or `go_router` (both documented) |
| Dependency injection | `provider` (`get_it` for large apps, or where already used) |
| Serialization | generated API contracts preferred, otherwise `json_serializable` |
| Generated `copyWith` | `copy_with_extension_gen` (only where needed) |
| Mocking | `mocktail` |

The plugin targets a **single Flutter app package** (one `pubspec.yaml`, feature-first folders under `lib/`). Monorepos with an app plus multiple packages are not covered.

The plugin itself needs only Claude Code. The optional dependency check needs `bash` and `grep`, both available on macOS and Linux.

## Install

From inside Claude Code:

```
/plugin marketplace add aissaserrar/flutter-clean-arch-plugin
/plugin install flutter-clean-arch@aissa-sr-plugins
```

To try it from a local clone without installing:

```
claude --plugin-dir ./flutter-clean-arch-plugin
```

After editing a skill, run `/reload-plugins` (or restart the session).

## Usage

You do not call the skills by name. Describe the task and Claude picks the matching skill.

| You say | Skill that applies |
|---|---|
| "Where should this code live?" / "Review this folder structure" | `clean-arch-overview` |
| "Add a transfers feature" | `clean-arch-new-feature`, which chains the layer skills below |
| "Create the `Account` entity and repository interface" | `clean-arch-domain` |
| "Write the DTO, mapper and repository implementation" | `clean-arch-data` |
| "Create a cubit for the transfer screen" | `clean-arch-presentation` |
| "Build the transfer page" | `clean-arch-ui` |
| "Add a form for this screen" | `clean-arch-forms` |
| "Register the providers and route for this feature" | `clean-arch-di-routing` |
| "Add logging / analytics ids" | `clean-arch-observability` |
| "Write tests for this use case / cubit" | `clean-arch-testing` |
| "Move the legacy cart files into a feature" / `/feature cart --migrate` | `feature_scan.sh` + `feature_apply.sh`, then `clean-arch-new-feature` for what is left |
| "Move navigation off GetX" / `/route` | `getx-routing-migration.md` + `go-router.md` or the auto_route rules, `route_scan.sh` |
| "Replace Get.put / Get.find" / `/di` | `getx-di-migration.md` + the DI rules in `clean-arch-di-routing`, `di_scan.sh` |
| "Add end-to-end tests" / `/e2e` | `patrol.md` + templates in `clean-arch-testing`, `e2e_scan.sh` |
| "Convert the cart controller to a cubit" / `/to-bloc cart` | `notifier-to-cubit.md` (in `clean-arch-presentation`) + `to_bloc_scan.sh`, then `clean-arch-testing` for the tests |
| "Remove GetX from the cart feature" / `/kill-getx cart` | `getx-migration.md` (in `clean-arch-presentation`) + `kill_getx_scan.sh` / `kill_getx_finish.sh` |
| "Is it safe to refactor X?" / `/pre-check` | `pre_check.sh` + `flutter analyze`, GO / NO-GO verdict |
| "Audit this project" / `/audit` | `clean-arch-overview` rules via `audit.sh`, rendered as an HTML report |

### Example: add a feature

```
> Add a "payments" feature that lists a user's payments from GET /payments
```

Claude follows `clean-arch-new-feature`: it first states the feature shape (here most likely a thin feature, since it only displays screen-ready data from one endpoint), then builds only the layers that shape needs, from the inside out (domain, data, presentation, UI, analytics ids, wiring), writes tests, and finishes by running `dart format`, `flutter analyze`, `flutter test` and the dependency check, reporting the real results.

### Example: review existing code

```
> Review lib/features/accounts for architecture violations
```

Claude checks imports against the dependency rules first, then each layer against its skill's checklist.

## Skills

| Skill | Purpose |
|---|---|
| `clean-arch-overview` | Feature shapes, layers, folder structure, dependency and shared-code rules, which skill to load |
| `clean-arch-domain` | Entities, repository interfaces, use cases, failures |
| `clean-arch-data` | DTOs, mappers, data sources, repository implementation, error mapping |
| `clean-arch-presentation` | Cubit/Bloc, state design and naming, presentation events, lifecycle |
| `clean-arch-ui` | Pages, widgets, error/loading patterns, l10n, design system |
| `clean-arch-forms` | Form cubits, naming, consistent form behavior |
| `clean-arch-di-routing` | Providers/`get_it`, `auto_route` and `go_router`, async startup, flavors and `AppConfig` |
| `clean-arch-observability` | Logging levels, what to log, analytics ids |
| `clean-arch-testing` | Tests per layer |
| `clean-arch-new-feature` | End-to-end workflow that chains the others |

Each skill keeps `SKILL.md` short (rules and a checklist) and moves detail into files Claude reads only when needed:

```
skills/clean-arch-<name>/
├── SKILL.md          # rules + checklist
├── references/       # decision tables and deeper explanations
└── (scripts/ or templates/ where useful)
```

## Commands

| Command | What it does |
|---|---|
| `/flutter-clean-arch:audit [path]` | Scans the project (file distribution per layer, GetX leakage such as `GetxController`, `Obx`, `.obs`, `Get.to`, import-rule violations, `part` misuse, widgets in `core/`, wiring outside `*_providers.dart`, BLoC presence, features without tests), writes `.clean-arch/audit-YYYY-MM-DD-HHMM.html` (plus a matching `.json`; every run is kept, and the report shows what changed since the previous audit). The report also draws the architecture **today** (your real folders with file, GetX and Cubit counts) next to the **target** structure from the skills (with your feature names). The trees are expandable: click a folder to open or close it, or use Expand all / Collapse all; small projects open fully, large ones start with the legacy folders open and crowded folders (more than 15 children) closed, and lists suggested next steps below it, ordered like the migration workflow and based on your actual numbers and opens it in your browser. If legacy state management is found with no BLoC, it asks whether you want to migrate to BLoC. |
| `/flutter-clean-arch:pre-check [feature \| path ...]` | Safety dry-run before a refactor. Runs `flutter analyze` (errors block), checks git (not a repo or uncommitted changes block; `main` branch, untracked files or being behind warn) and measures the targets: files, lines, GetX hits, Cubit/Bloc files, outside callers, files with tests. Prints GO / GO with cautions / NO-GO. Changes nothing. |
| `/flutter-clean-arch:feature <name> --migrate` | Finds the legacy files of one feature (controllers, views, models, services, repositories, bindings), proposes where each goes under `lib/features/<name>/{data,domain,presentation}`, and copies them only after you confirm. The originals stay in place, marked deprecated (a header comment and `@Deprecated` on each top-level declaration), every import elsewhere is rewritten to the new path, all imports are checked to still resolve, then the dependency checker runs. Files keep their names; converting to cubits is for later commands. |
| `/flutter-clean-arch:kill-getx [feature \| path ...]` | Removes GetX in confirmed batches (one feature at a time). First it checks that routing is already off GetX (if the app still uses `Get.to`/`GetPage`/`GetMaterialApp` and no `go_router`/`auto_route` is installed, it stops and asks you to run `/route` first), then a clean git tree and a `flutter analyze` baseline. It tells you how many files will change, warns that this is usually a lot and takes many batches, and asks for confirmation before the first batch and again before each next one (or once, with `--batches N`; see "Looping over batches"). Controllers become `ChangeNotifier`, `.obs` becomes private fields, `Obx`/`GetBuilder`/`GetView` become `ListenableBuilder` and plain widgets, so the app still compiles and behaves the same; `/to-bloc` then makes Cubits. Analyzer errors are compared with the baseline after every batch. `package:get` imports are removed only from files that no longer use anything from GetX. Navigation (`/route`), `Get.find`/bindings (`/di`) and snackbars/dialogs/`.tr` are reported, not rewritten. |
| `/flutter-clean-arch:to-bloc [feature \| path ...]` | Converts the state holders left by `/kill-getx` (`ChangeNotifier` / `ValueNotifier`) into Cubits, or Blocs only where event transformers are needed (debounced search, droppable submit). Generates one file per cubit in the plugin's order (cubit, events, state, presentation events) with sealed `Initial/Loading/Success/Failure` states, and updates the UI: the page provides the cubit with `BlocProvider`, `ListenableBuilder`/`Consumer` become `BlocBuilder`, effects use `BlocPresentationListener`. One class at a time with confirmation, an analyzer check against the baseline after each, and optional `bloc_test` tests. It stops and tells you the `flutter pub add` command if `flutter_bloc`/`equatable` are missing, and sends controllers that are still GetX back to `/kill-getx`. Supports `--batches N` and `--checkpoint` (see "Looping over batches"). |
| `/flutter-clean-arch:route [--go-router \| --auto-route] [feature ...]` | Replaces GetX routing with one centralized router. Asks **GoRouter or AutoRoute** unless you pass a flag or `pubspec.yaml` already has one. Creates a route per `GetPage` (paths in kebab-case, path parameters as ids, typed routes for go_router), turns `GetMiddleware` into a redirect/guard, rewrites `Get.to`/`Get.toNamed`/`Get.off*`/`Get.back`/`Get.arguments`, and converts `GetMaterialApp` to `MaterialApp.router` last. Navigation inside controllers is left with a TODO for a presentation event (`/to-bloc`). Confirmed in steps, analyzer-checked. |
| `/flutter-clean-arch:di [--get-it \| --provider] [feature ...]` | Sets up dependency injection without GetX lookups. Asks **GetIt (with injectable) or Provider** unless you pass a flag or `pubspec.yaml` already has one. Registers data sources, repositories (by interface), use cases and cubits per feature in one composition root (`MultiProvider`/`ProxyProvider` hierarchy, or injectable `@module` classes that keep `domain` free of annotations), and replaces `Get.put`/`Get.lazyPut`/`Get.find`/`Bindings`. Runs `build_runner` only after asking. |
| `/flutter-clean-arch:e2e [flow ...]` | Scaffolds and (if you agree) runs Patrol end-to-end tests. Checks the project and machine for readiness (patrol, patrol_cli, Android/iOS native setup, a mock-backed start, widget keys), proposes 3 to 5 flows including native ones (permission dialogs, notifications), writes `patrol_test/<flow>_test.dart` from templates after checking method names against the installed Patrol version, and runs `patrol test` on a connected device. Reports "not run" when no device is available. |

Findings are errors (import rules, GetX) or warnings (style: `part`, widgets in `core/`); warnings alone give `compliant_with_warnings`. The report lists what was checked and what was not, so `compliant` never claims more than the audit covers. The import rules come from `check_dependencies.sh`, the single source of truth. Generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, `app_localizations*.dart`) are ignored. The report is a single self-contained HTML file (no network, no CDN). Add `.clean-arch/` to your project's `.gitignore`. More commands for the GetX to BLoC migration are planned.

### Migrating a GetX app: the order

The commands are designed to run in this order (details and the shared safety gates are in `skills/clean-arch-overview/references/migration-workflow.md`). Each one ends by naming the next.

| # | Command | Purpose |
|---|---|---|
| 0 | `/audit` | Where the project stands; re-run after every step |
| 1 | `/pre-check` | Clean git tree, analyzer baseline, impact |
| 1b | `/e2e` (optional) | A few Patrol flows as a safety net |
| 2 | `/feature <name> --migrate` | Structure: files copied into `lib/features/<name>/`, originals marked deprecated |
| 3 | `/route` | go_router or auto_route replaces GetX navigation |
| 4 | `/di` | get_it (+ injectable) or provider replaces `Get.put`/`Get.find` |
| 5 | `/kill-getx` | GetX removed, plain Flutter interim form |
| 6 | `/to-bloc` | Cubit/Bloc with sealed states |
| 7 | tests, `/e2e` | `bloc_test`, widget tests, Patrol flows |

### Looping over batches (`/kill-getx` and `/to-bloc` only)

A real app needs dozens of batches. `--batches N` (1 to 10) runs up to N of them after **one** confirmation that states the expected file count and the stop conditions; without the flag nothing changes and you are asked before each batch. The loop stops by itself when: the analyzer reports more errors than the baseline; a file needed more than two fix attempts; a batch added a `TODO` that needs a human decision; a batch changed more than 15 files or touched files outside the plan; something outside the loop edited the project; a gate no longer holds; or N is reached. It never deletes old controllers or classes on its own, and each batch ends with a summary and a progress line (the audit delta). `--checkpoint` additionally asks once for permission to create a branch (when you are on `main`/`master`/`develop`) and to commit each batch's files, so every batch is a separate revertable commit. It never pushes, amends or stages anything it did not change.

Every editing command checks for a clean git tree and an analyzer baseline, asks you to confirm the scope (with a warning about how many files it will touch), works in small batches, formats only the files it touched, and reports real results. The commands apply the rules of the skills above; if a command and a skill ever disagree, the skill wins.

## Dependency checker

`check_dependencies.sh` verifies the import rules in a Flutter project: domain stays pure Dart, presentation never imports data, data never imports presentation, no feature imports another feature, and `core/` and `design_system/` never import features.

```bash
bash skills/clean-arch-overview/scripts/check_dependencies.sh lib
```

Exit code `0` means clean, `1` means violations (each one is printed), `2` means there is no `lib/features` directory. It also works in CI.

## Feature templates

`skills/clean-arch-new-feature/templates/*.tpl` hold skeletons for domain, data, presentation, wiring and analytics ids. Placeholders (`{{feature}}`, `{{Feature}}`, `{{entity}}`, `{{Entity}}`, `{{app}}`) are listed in `templates/README.md`. Claude fills them in when it creates a feature; you can also copy them by hand.

## What the plugin runs and accesses

The plugin is documentation for Claude plus twelve small scripts and eight commands (only the apply script, run after your confirmation, changes files).

- **Skills and references:** Markdown and templates that Claude reads. They change nothing by themselves.
- **`check_dependencies.sh`:** read-only. It runs `grep` over the `lib/` folder you point it at and prints the result. It does not write files, install packages or use the network.
- **Batch loop:** `loop_guard.sh` only runs `git status` and compares file lists. With `--checkpoint`, and only after you agree, `/kill-getx` and `/to-bloc` run `git switch -c` (on `main`/`master`/`develop`), `git add <the batch's files>` and `git commit`. They never push, amend, rebase, force, stash or reset.
- **`/route`, `/di`:** `route_scan.sh` and `di_scan.sh` only read. The edits are made by Claude in confirmed steps, one feature or step at a time, with `flutter analyze --no-pub` checks. They may ask to run `dart run build_runner build`; they never run `flutter pub add`/`remove` themselves.
- **`/e2e`:** `e2e_scan.sh` only reads (it checks that `flutter`, `patrol`, `adb` and `xcrun` exist, nothing else). Claude writes files under `patrol_test/` and, only after asking, native files and `pubspec.yaml`. Running the tests uses your device or emulator through `patrol test`, only after you agree. It never installs Patrol or the CLI for you.
- **`/to-bloc`:** `to_bloc_scan.sh` only reads. The new Cubit/Bloc files and the UI edits are made by Claude, one confirmed class at a time, following `notifier-to-cubit.md`; it runs `flutter analyze --no-pub` after each class and, if you ask, writes tests and runs `flutter test` on them. It never runs `flutter pub add`, never deletes the old class without asking, and skips deprecated originals.
- **`/kill-getx`:** `kill_getx_scan.sh` only reads. The edits to your Dart files are made by Claude, one confirmed batch at a time, following `getx-migration.md`; it runs `flutter analyze --no-pub` after each batch. `kill_getx_finish.sh --apply` deletes `package:get` import lines from files that no longer use GetX. It never edits `pubspec.yaml`, never runs `flutter pub remove`, and skips deprecated originals. Run it on a clean, committed tree.
- **`/feature --migrate`:** `feature_scan.sh` only reads. After you confirm, `feature_apply.sh --keep-deprecated` copies the files you approved into the feature, adds a deprecation header and `@Deprecated` to the originals, and edits the `import`/`export` lines elsewhere that referenced them. It deletes nothing. Run it on a clean, committed tree so the change is easy to review and undo.
- **`/pre-check`:** runs `flutter analyze --no-pub` and read-only `git` commands (`status`-style queries, `log`, `rev-list`), plus `pre_check.sh` (`grep`, `find`). It never stages, commits, stashes or edits files.
- **`audit.sh` and `/audit`:** `audit.sh` is read-only (`grep`, `find`, `awk`) and prints JSON. The `/audit` command saves that JSON and an HTML report to `.clean-arch/` in your project and opens the HTML with your OS's default opener (`open`, `xdg-open` or `start`). It never edits `lib/` or `test/`, and uses no network.
- **Network, hooks, MCP servers, credentials:** none. The plugin has no hooks, no MCP servers and asks for no secrets.
- **Data collection:** none. Nothing is sent anywhere by the plugin.

## Customizing

The rules assume the stack in [Requirements](#requirements). If yours differs, edit the matching `SKILL.md` files; the layer rules stay valid. Project conventions (for example "cubits may call repositories directly in simple features") belong in the relevant skill so Claude applies them consistently. Fork the repository, or edit the installed copy and run `/reload-plugins`.

## Maintaining the plugin

After editing a command or a skill, run `bash scripts/check_consistency.sh`. It is read-only and checks that every command has its frontmatter, every referenced path exists, scripts parse and are executable, editing commands point to `references/migration-workflow.md`, no stale wording remains, the README lists every command and skill, every slash command mentioned anywhere exists, and the order of the migration commands is unchanged. It is a maintainer tool: the plugin itself never runs it.

## Troubleshooting

- **A skill does not trigger:** mention the layer or the artifact in your request ("cubit", "repository", "mapper", "provider"). You can also name the skill directly, for example "use clean-arch-domain".
- **Changes to a skill do not show up:** run `/reload-plugins` or restart the session.
- **The checker prints `No lib/features directory found`:** run it from the project root, or pass the path to your `lib/` folder as the argument.
- **The checker reports a false positive:** it matches single-quoted `import '...'` lines only. Open an issue with the offending line.

## Changelog

- **0.3.0:** `/audit` report with a Today / Target architecture illustration and data-driven next steps; bounded batch loop (`--batches N`, `--checkpoint`) for `/kill-getx` and `/to-bloc` with mechanical stop conditions; `/audit` shows progress since the previous audit; shared migration workflow (`migration-workflow.md`) that every command follows, and a consistency checker for maintainers; `/route` (go_router or auto_route, asked), `/di` (get_it + injectable or provider, asked), `/e2e` (Patrol); `/to-bloc` (ChangeNotifier to Cubit/Bloc with sealed states, UI updated, per-class analyzer check); `/kill-getx` (batch GetX removal to a plain-Flutter interim form, import cleanup, analyzer checks); `/feature <name> --migrate` (scan, confirm, copy into the feature, mark originals deprecated, rewrite imports); `/pre-check` safety dry-run (analyze, git state, impact metrics, GO/NO-GO verdict); `/audit` command with an HTML report (file distribution, GetX leakage, layer violations, BLoC presence) and an offer to migrate legacy projects to BLoC.
- **0.2.0:** feature shapes (thin / with repository / full domain); state naming `Initial`/`Loading`/`Success`/`Failure` with presentation events; go_router documented alongside auto_route; provider tree-depth guidance and `get_it`; rule of three for shared code; new skills for forms and for logging/analytics; error, loading and connectivity patterns; guidance on when to use interfaces; testing additions.
- **0.1.1:** expanded README (usage, disclosure of what the plugin runs, troubleshooting); added the design doc and MIT license; marketplace manifest.
- **0.1.0:** initial release.

## Support

Questions and bug reports: [open an issue](https://github.com/aissaserrar/flutter-clean-arch-plugin/issues).

## Author

Aissa Serrar

- LinkedIn: https://www.linkedin.com/in/aissa-serrar/
- GitHub: https://github.com/aissaserrar
- Email: aissa.serrar95@gmail.com

## License

MIT, see [LICENSE](LICENSE).
