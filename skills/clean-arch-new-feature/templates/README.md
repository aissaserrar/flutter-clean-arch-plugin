# Feature file templates

Copy these skeletons and replace the placeholders:

| Placeholder | Meaning | Example |
|---|---|---|
| `{{feature}}` | snake_case feature folder | `payments` |
| `{{Feature}}` | PascalCase | `Payments` |
| `{{entity}}` / `{{Entity}}` | main entity | `payment` / `Payment` |
| `{{app}}` | package name from pubspec | `app` |

`get_{{entity}}s.dart` is a pass-through use case. Keep it when the project convention is "always use cases"; for a thin display-only feature, delete it and inject the repository into the cubit (see `clean-arch-domain`).

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
├── {{feature}}_routes.dart
└── {{feature}}_providers.dart
```
