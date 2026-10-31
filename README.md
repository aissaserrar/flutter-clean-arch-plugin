# flutter-clean-arch

A Claude Code plugin with Clean Architecture rules for Flutter apps using Bloc/Cubit. Based on [`docs/simplified-architecture-with-domain.md`](docs/simplified-architecture-with-domain.md), included in this plugin.

## Skills

| Skill | Purpose |
|---|---|
| `clean-arch-overview` | Layers, folder structure, dependency rules, which skill to load |
| `clean-arch-domain` | Entities, repository interfaces, use cases, failures |
| `clean-arch-data` | DTOs, mappers, data sources, repository impl, error mapping |
| `clean-arch-presentation` | Cubit/Bloc, state design, lifecycle |
| `clean-arch-ui` | Pages, widgets, BlocBuilder/Listener, l10n, design system |
| `clean-arch-di-routing` | Providers, auto_route, flavors and `AppConfig` |
| `clean-arch-testing` | Tests per layer |
| `clean-arch-new-feature` | End-to-end workflow that chains the others |

Claude loads a skill automatically when the task matches its description, so you can just say "add a transfers feature" or "review this cubit".

## Bundled files

Each skill keeps `SKILL.md` short (rules, checklist) and moves detail to files Claude reads only when needed:

```
skills/clean-arch-<name>/
├── SKILL.md          # rules + checklist
├── references/       # decision tables and deeper explanations
└── (scripts/ or templates/ where useful)
```

- `clean-arch-overview/scripts/check_dependencies.sh` enforces the import rules (also usable in CI).
- `clean-arch-new-feature/templates/*.tpl` are feature skeletons with placeholders.

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

## Customizing

The rules assume `flutter_bloc`, `auto_route`, `provider`, `json_serializable`, `bloc_test` and `mocktail`. If your stack differs, edit the matching `SKILL.md` files; the layer rules stay valid. Project-specific conventions (for example "cubits may call repositories directly in simple features") should be added to the relevant skill so Claude applies them consistently.

## Author

Aissa Serrar

- LinkedIn: https://www.linkedin.com/in/aissa-serrar/
- GitHub: https://github.com/aissaserrar
- Email: aissa.serrar95@gmail.com

## License

MIT, see [LICENSE](LICENSE).
