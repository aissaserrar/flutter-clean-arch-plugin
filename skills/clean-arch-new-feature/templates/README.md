# Feature file templates

Copy these skeletons and replace the placeholders:

| Placeholder | Meaning | Example |
|---|---|---|
| `{{feature}}` | snake_case feature folder | `payments` |
| `{{Feature}}` | PascalCase | `Payments` |
| `{{entity}}` / `{{Entity}}` | main entity | `payment` / `Payment` |
| `{{app}}` | package name from pubspec | `app` |

The routes template is written for auto_route. For go_router, expose `{{Feature}}Page` and define the route class in the app's navigation files (see `clean-arch-di-routing/references/go-router.md`).

Pick the feature shape first (see `clean-arch-overview`):

- **Full domain:** use every file below.
- **With repository:** keep the repository interface, `data/`, and wiring; `get_{{entity}}s.dart` is an optional pass-through use case. Keep it only if the project convention is "always use cases"; otherwise delete it and inject `{{Feature}}Repository` into the cubit.
- **Thin:** skip `domain/` and `data/`; the cubit takes the typed API client from `core/http`, and there is no `{{feature}}_providers.dart` unless the feature has its own dependencies.

Resulting layout:

```
features/{{feature}}/
├── domain/
│   ├── entities/{{entity}}.dart
│   ├── repositories/{{feature}}_repository.dart
│   └── use_cases/get_{{entity}}s.dart
├── data/
│   ├── dtos/{{entity}}_dto.dart
│   ├── mappers/{{entity}}_mapper.dart
│   ├── sources/remote_{{feature}}_data_source.dart
│   ├── {{feature}}_repository_impl.dart
│   └── mock_{{feature}}_repository.dart
├── presentation/
│   ├── cubit/{{feature}}_cubit.dart
│   └── ui/{{feature}}_page.dart
├── {{feature}}_ids.dart
├── {{feature}}_routes.dart
└── {{feature}}_providers.dart
```
