# Multi-package layout (large projects)

Use this when several teams work on the app. A single team can stay with one package and the `features/` folder.

## Layout

```
app                 # main app package (composition root, router, bootstrap)
app2                # optional: more apps in a multi-app project
packages/
  common/           # shared code, extracted from app/lib/common (core/)
  design_system/
  accounts/         # one feature package per team (or per feature group)
  transfers/
  some_plugin/      # custom plugin with native code
```

- Main app package(s) sit directly in the repository root. Every other package is in a flat `packages/` directory.
- Feature packages keep the usual feature structure under `lib/src/features/<feature>/` and export only what other packages may use (pages as widgets, exposed use cases).
- Every package has an **owner team**; a team can own several packages. A `CODEOWNERS` file records it.
- Use Pub workspaces to keep resolution fast with many packages.
- Package boundaries make dependencies explicit and add visibility control. Feature packages never depend on each other (they cannot import each other; see cross-feature rules).

## Common package

- `common` never depends on feature packages and contains nothing business-specific.
- Apply the rule of three before moving anything into it, and fully test everything in it.
- Reusable UI components live in the design system package, not in `common`.

## Plugins

- Custom plugins (native code) are separate packages. Feature packages have no native implementation.
- Do not use the federated plugin pattern for them: it requires at least three packages and adds extensibility that custom plugins do not need.

## Routing and localization

- Routes are defined in the main app package, in `lib/router/`, one file per package: `<package-name>_routes.dart`. Features expose page widgets; the app wires them to routes.
- Each package that has UI owns its own `.arb` files to avoid merge conflicts between teams.

## Dependency injection at this size

`provider` increases widget-tree depth with every dependency; apps with many global dependencies can hit Flutter's tree-depth limit at runtime. For large projects choose the mechanism case by case (see `clean-arch-di-routing`).
