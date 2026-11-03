# flutter-clean-arch

Clean Architecture rules for Flutter apps that use Bloc/Cubit, packaged as Claude Code skills, plus commands that help move a legacy GetX app onto that architecture. When you ask Claude to add a feature, write a cubit, wire providers or write tests, it follows one consistent set of layer rules instead of guessing your structure each time.

It is based on [`docs/simplified-architecture-with-domain.md`](docs/simplified-architecture-with-domain.md), which is included in the plugin.

## What you get

- **Eleven skills**, one per concern, that Claude loads automatically when your request matches.
- **Nine commands** to audit a project and migrate it from GetX to Bloc/Cubit, feature by feature, or in one go with `/migrate` (see [Commands](#commands)).
- **A dependency checker** (`check_dependencies.sh`) for the import rules.
- **Feature templates** for domain, data, presentation, wiring and analytics-id code.
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

Pick the smallest feature shape that fits:

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

The plugin targets a **single Flutter app package** (one `pubspec.yaml`, feature-first folders under `lib/`). Monorepos are not covered. It needs only Claude Code; the scripts need `bash`, `grep`, `awk` and `sed`, available on macOS and Linux.

## Install

From inside Claude Code:

```text
/plugin marketplace add aissaserrar/flutter-clean-arch-plugin
/plugin install flutter-clean-arch@aissa-sr-plugins
```

To try it from a local clone without installing: `claude --plugin-dir ./flutter-clean-arch-plugin`. After editing a skill, run `/reload-plugins` (or restart the session).

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

**Add a feature:** `> Add a "payments" feature that lists a user's payments from GET /payments`. Claude follows `clean-arch-new-feature`: it states the feature shape, builds only the layers that shape needs from the inside out, writes tests, and finishes with `dart format`, `flutter analyze`, `flutter test` and the dependency check, reporting the real results.

**Review code:** `> Review lib/features/accounts for architecture violations`. Claude checks imports against the dependency rules first, then each layer against its skill's checklist.

## Skills

| Skill | Purpose |
|---|---|
| `clean-arch-overview` | Feature shapes, layers, folder structure, dependency and shared-code rules, migration workflow |
| `clean-arch-domain` | Entities, repository interfaces, use cases, failures |
| `clean-arch-data` | DTOs, mappers, data sources, repository implementation, error mapping |
| `clean-arch-presentation` | Cubit/Bloc, state design and naming, presentation events, lifecycle, GetX to Cubit mappings |
| `clean-arch-ui` | Pages, widgets, error/loading patterns, l10n, design system |
| `clean-arch-forms` | Form cubits, naming, consistent form behavior |
| `clean-arch-di-routing` | Providers/`get_it`, `auto_route` and `go_router`, async startup, flavors and `AppConfig` |
| `clean-arch-observability` | Logging levels, what to log, analytics ids |
| `clean-arch-testing` | Tests per layer, Patrol end-to-end tests |
| `clean-arch-new-feature` | End-to-end workflow that chains the others |
| `clean-arch-migrate` | Runs the whole GetX migration feature by feature, with an e2e question after each |

Each skill keeps `SKILL.md` short (rules and a checklist) and moves detail into `references/`, with `scripts/` or `templates/` where useful.

## Commands

| Command | What it does |
|---|---|
| `/flutter-clean-arch:audit [path]` | Scans the project and opens an HTML report: compliance status, GetX usage, software-engineering checks (layer leaks, file size, `_buildX`, empty catch, print, colors, test mirrors), today vs target structure (expandable trees), a feature-by-feature migration plan, suggested next steps, progress since the last audit |
| `/flutter-clean-arch:foundation [--router …] [--di …] [--migrate-ds …]` | Scaffolds `bootstrap/`, `core/error` (`Result` + `AppFailure`), `design_system/`; optional copy of widgets/themes into `design_system/`; optional router stub. Clears structure/error audit blockers |
| `/flutter-clean-arch:pre-check [feature \| path ...]` | Safety dry-run before a refactor: analyzer, git state, impact. Prints GO / GO with cautions / NO-GO |
| `/flutter-clean-arch:feature <name> --migrate` | Copies a feature's scattered legacy files into `lib/features/<name>/`; originals stay, marked deprecated; imports rewritten |
| `/flutter-clean-arch:route [--go-router \| --auto-route]` | Replaces GetX routing with go_router or auto_route (it asks which, unless decided) |
| `/flutter-clean-arch:di [--get-it \| --provider]` | Replaces `Get.put` / `Get.find` with get_it (+ injectable) or provider (it asks which, unless decided) |
| `/flutter-clean-arch:kill-getx [feature \| path ...]` | Removes GetX controllers and widgets in confirmed batches, to a plain-Flutter interim form |
| `/flutter-clean-arch:to-bloc [feature \| path ...]` | Converts state holders to Cubit/Bloc with sealed states and updates the UI |
| `/flutter-clean-arch:e2e [flow ...]` | Scaffolds and runs Patrol end-to-end tests, including native steps |
| `/flutter-clean-arch:migrate [--checkpoint] [feature ...]` | Runs the whole migration feature by feature from the audit plan, asks about an e2e test after each, saves progress, skips and lists features it cannot finish |

Every command that edits files requires a clean git tree, compares `flutter analyze` against a baseline, asks you to confirm the scope, works in small batches and never runs `flutter pub add`. Details for each command, the batch loop (`--batches N`, `--checkpoint`) and what each one runs are in [`docs/commands.md`](docs/commands.md).

### The order for migrating a GetX app

Defined in [`skills/clean-arch-overview/references/migration-workflow.md`](skills/clean-arch-overview/references/migration-workflow.md); each command ends by naming the next one.

| # | Command | Purpose |
|---|---|---|
| 0 | `/audit` | Where the project stands; re-run after every step |
| 1 | `/foundation` | `bootstrap/`, `Result`/`AppFailure`, `design_system/`; optional router |
| 2 | `/pre-check` | Clean git tree, analyzer baseline, impact |
| 2b | `/e2e` (optional) | A few Patrol flows as a safety net |
| 3 | `/feature <name> --migrate` | Files copied into `lib/features/<name>/` |
| 4 | `/route` | go_router or auto_route (skip if GetX nav kept) |
| 5 | `/di` | get_it or provider replaces `Get.put` / `Get.find` |
| 6 | `/kill-getx` | GetX removed, plain-Flutter interim form |
| 7 | `/to-bloc` | Cubit/Bloc with sealed states |
| 8 | tests, `/e2e` | `bloc_test`, widget tests, Patrol flows |

The audit's plan adapts this to your project's own decisions (for example "keep GetX navigation" or "no ChangeNotifier"), which it reads from `CLAUDE.md`, `AGENTS.md`, `.claude/skills/` and `.clean-arch/config.json`, and it asks before saving them. Add `.clean-arch/` to your project's `.gitignore`.

## Dependency checker

`check_dependencies.sh` verifies the import rules: domain stays pure Dart, presentation never imports data, data never imports presentation, no feature imports another feature, and `core/` and `design_system/` never import features.

```bash
bash skills/clean-arch-overview/scripts/check_dependencies.sh lib
```

Exit code `0` means clean, `1` means violations (each one is printed), `2` means there is no `lib/features` directory. It also works in CI.

## Feature templates

`skills/clean-arch-new-feature/templates/*.tpl` hold skeletons for domain, data, presentation, wiring and analytics ids. Placeholders (`{{feature}}`, `{{Feature}}`, `{{entity}}`, `{{Entity}}`, `{{app}}`) are listed in `templates/README.md`. Claude fills them in when it creates a feature; you can also copy them by hand.

## What the plugin runs and accesses

- **Skills and references:** Markdown and templates that Claude reads. They change nothing by themselves.
- **Scanners:** read-only scripts (`grep`, `find`, `awk`, `git status`-style queries) that print JSON or text. `/audit` also writes its report to `.clean-arch/` in your project and opens it with your OS's default opener.
- **Editing commands:** Claude edits your Dart files only after you confirm a plan, in small batches, and runs `flutter analyze --no-pub` after each. `feature_apply.sh` and `kill_getx_finish.sh --apply` are the only scripts that change files, and only after you confirm.
- **Git:** commands only read it. The one exception is `--checkpoint` on `/kill-getx` and `/to-bloc`: after you agree, it runs `git switch -c`, `git add <that batch's files>` and `git commit`. Nothing is ever pushed, amended, rebased, forced, stashed or reset.
- **Other tools:** `flutter analyze`, and only after asking `dart run build_runner build`, `flutter test` and `patrol test`. Nothing is installed, and `pubspec.yaml` is not edited by the plugin.
- **Network, hooks, MCP servers, credentials, data collection:** none.

The full table of what each command runs is in [`docs/commands.md`](docs/commands.md#what-each-command-runs).

## Customizing

The rules assume the stack in [Requirements](#requirements). If yours differs, edit the matching `SKILL.md` files; the layer rules stay valid. Project conventions (for example "cubits may call repositories directly in simple features") belong in the relevant skill so Claude applies them consistently. Fork the repository, or edit the installed copy and run `/reload-plugins`.

## Maintaining the plugin

Two read-only checks, for maintainers (the plugin itself never runs them):

- `bash scripts/check_consistency.sh`: commands and skills agree (frontmatter, referenced paths, scripts parse, README and docs list every command and skill, the command order is intact, no hard-coded class names where the shared detector must be used).
- `bash scripts/check_getx_coverage.sh`: every GetX API in the catalog (`skills/clean-arch-overview/scripts/detect.sh`) is recognised by the scanners. Run it after adding to the catalog.

## Troubleshooting

- **A skill does not trigger:** mention the layer or the artifact in your request ("cubit", "repository", "mapper", "provider"), or name the skill, for example "use clean-arch-domain".
- **Changes to a skill do not show up:** run `/reload-plugins` or restart the session.
- **The checker prints `No lib/features directory found`:** run it from the project root, or pass the path to your `lib/` folder.
- **The checker reports a false positive:** it matches single-quoted `import '...'` lines only. Open an issue with the offending line.
- **`/audit` is slow on a large project:** it scans every Dart file. Expect several seconds for around 700 files.

## Changelog

- **0.4.1**
  - `/audit` **template distance** vs `simplified-architecture-with-domain.md` (primary scorecard). GetX inventory is secondary. Also: engineering checks, `DataCubit`/`BaseCubit`/`PaginatedCubit` warnings, `common/` like `core/`. `/to-bloc` maps to plain `Cubit`/`Bloc`.
- **0.4.0**
  - `/migrate` and the `clean-arch-migrate` skill: the whole migration, feature by feature, resumable (`.clean-arch/progress.json`), with an e2e question after each feature.
  - `/audit` asks the scope and mode once and saves `.clean-arch/config.json`.
  - `/to-bloc` converts GetX controllers directly to Cubits (project base classes and rules respected) and accepts feature unit names; `/kill-getx` redirects to `/to-bloc` when the project forbids ChangeNotifier.
- **0.3.0**
  - Migration commands: `/audit`, `/foundation`, `/pre-check`, `/feature --migrate`, `/route`, `/di`, `/kill-getx`, `/to-bloc`, `/e2e`.
  - `/audit` report: today vs target architecture as expandable trees, a feature-by-feature migration plan, data-driven next steps, progress since the previous audit.
  - Detection through custom base classes (`BaseCubit`, `GetxFormController`...) and a GetX catalog built from the package's API reference, with a coverage check.
  - Project conventions and decisions read from `CLAUDE.md`, `AGENTS.md`, `.claude/skills/` and `.clean-arch/config.json`.
  - Bounded batch loop (`--batches N`, `--checkpoint`) with mechanical stop conditions.
  - A shared migration workflow every command follows, and a consistency checker for maintainers.
- **0.2.0:** feature shapes (thin / with repository / full domain); state naming `Initial`/`Loading`/`Success`/`Failure` with presentation events; go_router documented alongside auto_route; provider tree-depth guidance and `get_it`; rule of three for shared code; new skills for forms and for logging/analytics; error, loading and connectivity patterns; guidance on when to use interfaces; testing additions.
- **0.1.1:** expanded README (usage, disclosure of what the plugin runs, troubleshooting); design doc and MIT license; marketplace manifest.
- **0.1.0:** initial release.

## Support

Questions and bug reports: [open an issue](https://github.com/aissaserrar/flutter-clean-arch-plugin/issues).

## Author

Aissa Serrar

- LinkedIn: <https://www.linkedin.com/in/aissa-serrar/>
- GitHub: <https://github.com/aissaserrar>
- Email: <aissa.serrar95@gmail.com>

## License

MIT, see [LICENSE](LICENSE).
