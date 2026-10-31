# flutter-clean-arch

Clean Architecture rules for Flutter apps that use Bloc/Cubit, packaged as Claude Code skills. When you ask Claude to add a feature, write a cubit, wire providers or write tests, it follows one consistent set of layer rules instead of guessing your structure each time.

It is based on [`docs/simplified-architecture-with-domain.md`](docs/simplified-architecture-with-domain.md), which is included in the plugin.

## What you get

- **Ten skills**, one per concern, that Claude loads automatically when your request matches (no slash commands to remember).
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

## Dependency checker

`check_dependencies.sh` verifies the import rules in a Flutter project: domain stays pure Dart, presentation never imports data, data never imports presentation, no feature imports another feature, and `core/` and `design_system/` never import features.

```bash
bash skills/clean-arch-overview/scripts/check_dependencies.sh lib
```

Exit code `0` means clean, `1` means violations (each one is printed), `2` means there is no `lib/features` directory. It also works in CI.

## Feature templates

`skills/clean-arch-new-feature/templates/*.tpl` hold skeletons for domain, data, presentation, wiring and analytics ids. Placeholders (`{{feature}}`, `{{Feature}}`, `{{entity}}`, `{{Entity}}`, `{{app}}`) are listed in `templates/README.md`. Claude fills them in when it creates a feature; you can also copy them by hand.

## What the plugin runs and accesses

The plugin is documentation for Claude plus one small script.

- **Skills and references:** Markdown and templates that Claude reads. They change nothing by themselves.
- **`check_dependencies.sh`:** read-only. It runs `grep` over the `lib/` folder you point it at and prints the result. It does not write files, install packages or use the network.
- **Network, hooks, MCP servers, credentials:** none. The plugin has no hooks, no MCP servers and asks for no secrets.
- **Data collection:** none. Nothing is sent anywhere by the plugin.

## Customizing

The rules assume the stack in [Requirements](#requirements). If yours differs, edit the matching `SKILL.md` files; the layer rules stay valid. Project conventions (for example "cubits may call repositories directly in simple features") belong in the relevant skill so Claude applies them consistently. Fork the repository, or edit the installed copy and run `/reload-plugins`.

## Troubleshooting

- **A skill does not trigger:** mention the layer or the artifact in your request ("cubit", "repository", "mapper", "provider"). You can also name the skill directly, for example "use clean-arch-domain".
- **Changes to a skill do not show up:** run `/reload-plugins` or restart the session.
- **The checker prints `No lib/features directory found`:** run it from the project root, or pass the path to your `lib/` folder as the argument.
- **The checker reports a false positive:** it matches single-quoted `import '...'` lines only. Open an issue with the offending line.

## Changelog

- **0.2.0:** feature shapes (thin / with repository / full domain); state naming `Initial`/`Loading`/`Success`/`Failure` with presentation events; go_router documented alongside auto_route; provider tree-depth guidance and `get_it`; rule of three for shared code; new skills for forms and for logging/analytics; error, loading and connectivity patterns; multi-package layout; guidance on when to use interfaces; testing additions.
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
