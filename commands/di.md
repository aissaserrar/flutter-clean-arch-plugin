---
description: Set up dependency injection without GetX lookups: GetIt (with injectable code generation) or Provider (MultiProvider / ProxyProvider hierarchy), you choose. Registers data sources, repositories, use cases and cubits per feature, and replaces Get.put/Get.find.
argument-hint: "[--get-it | --provider] [feature-name ...]"
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
---

# /di

Wire the app's dependencies (data sources, repositories, use cases, cubits/blocs) through one composition root and replace GetX lookups. Follow `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-di-routing/references/getx-di-migration.md` and the DI rules in `SKILL.md`. Read them before editing.

`$ARGUMENTS` may contain `--get-it` or `--provider` and feature names to restrict the work.

Shared gates (clean tree, analyzer baseline, scope confirmation, batches, format, report), conventions and the order of the commands are in `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/references/migration-workflow.md`. Read it first; the steps below only add what is specific to this command.

## Steps

1. **Preconditions.** `pubspec.yaml` and `lib/` exist and `git status --porcelain` is empty (otherwise recommend `/pre-check` and ask whether to continue; default: stop). Baseline `flutter analyze --no-pub` error count (if Flutter is missing, say the check cannot run and ask).

2. **Scan** (read-only):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-di-routing/scripts/di_scan.sh" "<project root>"
   ```

   Show how DI is done today (`today`: GetX `Get.put/find`, get_it, provider, existing wiring files), the classes per feature and role, their likely dependencies, and `locator_calls_inside_cubits_repos_or_use_cases`.

3. **Choose the mechanism.** In this order:
   - `--get-it` or `--provider` in `$ARGUMENTS`: use it.
   - Else if `pubspec` has `get_it` but not `provider`, or the reverse: use the one present and say so.
   - Else (neither, or both): **ask with AskUserQuestion: GetIt (with injectable) or Provider?** State the trade-off briefly: provider is the plugin's default and is enough for small and medium apps; get_it (with injectable code generation) suits large apps with many global dependencies, at the cost of build_runner. Do not choose for the user. Never use both for the same kind of dependency.
   - If GetIt: ask whether to use `injectable` code generation or hand-written `register<Feature>` functions (default: injectable, as requested for this command).

4. **Check dependencies** for the choice and stop with the exact commands if missing (never run `pub add` yourself): get_it needs `get_it`; injectable adds `injectable` plus `injectable_generator` and `build_runner` (dev); provider needs `provider`. Read the installed injectable/get_it/provider README/CHANGELOG in the pub cache and match its API (annotation names and the generated `init()` differ between majors).

5. **Show the plan and confirm.** Per feature: what will be registered (in order: sources, repositories by interface, use cases, cubits), what is global (HTTP client, storage, auth cubit), where the files go (`bootstrap/`, `<feature>_providers.dart` or `<feature>_di.dart`), and how many `Get.put/lazyPut/find` and `Bindings` will be replaced. Warn that this can touch many files, is done feature by feature, and is analyzer-checked after each. Ask: **Start with the first feature** (default), **Choose the order**, **Cancel**; ask again before each further feature.

6. **Build the root first.** Create or update `bootstrap/` (`global_providers.dart` with `MultiProvider`, or `injection.dart` with `configureDependencies`), then wire it into `main`/`app` above the router. The domain stays pure: with injectable use `@module` classes in the feature wiring file, never annotations on domain or data classes.

7. **Per feature:** write the wiring file (`<feature>_providers.dart` list of providers, or `<feature>_di.dart` module / `register<Feature>`), register by interface, choose mock or real with `AppConfig.useMocks`, make cubits factories (get_it) or page-scoped `BlocProvider` (provider), and rewrite the old GetX lookups:
   - `Get.find<X>()` inside a class becomes a constructor parameter (update the call sites);
   - `Get.find` in a widget becomes the page's `BlocProvider(create: ...)` read;
   - `Bindings` classes are replaced by the feature wiring and removed only after listing them and getting confirmation.
   `ProxyProvider` only where a dependency must rebuild when an upstream value changes (for example a token); plain `Provider` otherwise.

8. **Generate and check.** For injectable, ask whether to run `dart run build_runner build --delete-conflicting-outputs` (default: yes) and report its real output. Run `flutter analyze --no-pub` against the baseline after each feature; fix your own errors (two attempts per file), otherwise stop and show them. Never revert with git commands.

9. **Final report.** Run `dart format` on every file you created or changed, then re-run `di_scan.sh`: before/after counts, leftover `Get.find/put`, locator calls inside cubits/repositories, analyzer errors before/after, `check_dependencies.sh` output, every `TODO(di)` by file. Next: `/route` first if the app still navigates with GetX, otherwise `/kill-getx` (order table in `migration-workflow.md`).

## Rules

- Never edit before the user confirms the plan; ask again before every further feature.
- Constructor injection only: no locator or `context.read` inside cubits, use cases, repositories or `build`.
- No injectable annotations in `domain/` or `data/`; wiring files are the only place that sees both layers.
- Cubits are page-scoped (factory / `BlocProvider`), not global, unless app-wide.
- Never edit files with the `DEPRECATED: migrated by /feature --migrate` header.
- Do not run `git` commands that change state, or `flutter pub add`/`remove`.
