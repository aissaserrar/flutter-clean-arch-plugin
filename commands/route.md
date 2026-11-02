---
description: Replace GetX routing with a centralized router (go_router or auto_route, you choose): routes for every page, path parameters, redirects for auth middleware, and Get.to/Get.toNamed calls rewritten. Confirmed in steps, analyzer-checked.
argument-hint: "[--go-router | --auto-route] [feature-name ...]"
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
---

# /route

Replace GetX navigation in the project with one centralized router. Follow `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-di-routing/references/getx-routing-migration.md` for the mapping, and for the target router the rules in `go-router.md` (go_router) or the `auto_route` section of `SKILL.md`. Read them before editing.

`$ARGUMENTS` may contain `--go-router` or `--auto-route` and feature names to restrict the work. Without feature names the whole app is migrated.

Shared gates (clean tree, analyzer baseline, scope confirmation, batches, format, report), conventions and the order of the commands are in `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/references/migration-workflow.md`. Read it first; the steps below only add what is specific to this command.

## Steps

1. **Preconditions.**
   - `pubspec.yaml` and `lib/` exist and `git status --porcelain` is empty. If not, recommend `/pre-check`, explain that a clean committed tree is the only easy undo, and ask whether to continue (default: stop).
   - Baseline: `flutter analyze --no-pub`, record the `error •` count. If Flutter is missing, say the analyzer check cannot run and ask whether to continue.

2. **Scan** (read-only):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-di-routing/scripts/route_scan.sh" "<project root>"
   ```

   Show: pages found (`pages`, with proposed path, route class and feature), navigation calls by kind, calls inside logic classes, `Get.arguments`/`Get.parameters` reads, middlewares, and the `GetMaterialApp` files. If there are no pages and no navigation calls, say GetX routing is not used and stop.

3. **Choose the router.** Decide in this order:
   - `--go-router` or `--auto-route` in `$ARGUMENTS`: use it.
   - Else, if `pubspec` lists exactly one of `go_router` / `auto_route`: use that one and tell the user why.
   - Else (neither, or both): **ask with AskUserQuestion: GoRouter or AutoRoute?** Do not pick one yourself. Briefly state the difference that matters here: go_router is configuration plus typed route classes; auto_route generates the route classes from `@RoutePage()` pages and provides cubits through `AutoRouteWrapper`. Both are supported by the plugin; they must not be mixed.
   - If both are in `pubspec`, say the project mixes them and ask which one to keep.

4. **Check the dependencies for the chosen router**, and stop with the exact commands if something is missing (never run `pub add` yourself):
   - go_router: `go_router`; for typed routes also `go_router_builder` and `build_runner` as dev dependencies. If the user does not want code generation, offer **plain routes** (`GoRoute` + `context.go('/path')`, path strings only inside `router/`) and say it loses type safety.
   - auto_route: `auto_route`, and `auto_route_generator` and `build_runner` as dev dependencies.

   API names differ between major versions: read the installed package's README/CHANGELOG in the pub cache (`$PUB_CACHE` or `~/.pub-cache/hosted/pub.dev/<package>-<version>/`) before writing router code.

5. **Show the plan and confirm.** Tell the user, with real numbers: routes to create, files with navigation calls to change, middlewares to turn into redirects/guards, items that stay manual or deferred (calls inside logic classes, `Get.snackbar`/dialogs, `GetConnect`), and that the app root (`GetMaterialApp`) is converted last. Warn that this touches many files and will be done in steps with an analyzer check after each step. Ask with AskUserQuestion: **Start** (default), **Adjust the route paths first**, **Cancel**.

6. **Step A: create the router.** Generate the route classes, the route tree (go_router) or route lists (auto_route), and `router/app_router.dart`. Where the route definitions live depends on the router: **go_router** keeps route classes and the tree in `router/` (`routes.dart`, or `router/<feature>_routes.dart` if it grows) and features only expose their page widgets; **auto_route** declares each feature's `AutoRoute` list in `features/<feature>/<feature>_routes.dart`, assembled in `router/app_router.dart`. One route per page; path parameters from the GetX path (`:productId`); paths kebab-case; parameters are ids. Pages provide their own cubit (leave the existing controller creation as it is, with a `// TODO(di)`, when no cubit exists yet). Turn each `GetMiddleware` into a `redirect` (go_router) or a guard (auto_route) that listens to the auth state. Ask the user to run `dart run build_runner build --delete-conflicting-outputs` (or run it after asking) and check the analyzer.

7. **Step B: rewrite the navigation calls** file by file with the mapping table. `Get.arguments` becomes a route/page parameter and the sender passes an id. Calls inside logic classes (`in_logic_class: true`) are not rewritten: leave them with `// TODO(route): presentation event (after /to-bloc)` and list them. Analyze after each feature.

8. **Step C: the app root.** Replace `GetMaterialApp` with `MaterialApp.router`, wiring the router (`initialLocation`/initial route, error page for `unknownRoute`). Say which `Get.snackbar`/`Get.dialog`/`Get.context` uses stop working and list them as manual.

9. **Final check and report.** Run `dart format` on every file you created or changed, then re-run `route_scan.sh` and show before/after counts, analyzer errors before/after, `bash "${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/scripts/check_dependencies.sh" lib`, and every `TODO(route)` by file. Next: `/di` (then `/kill-getx`); the `TODO(route)` calls inside logic classes are resolved by `/to-bloc` (order table in `migration-workflow.md`).

## Rules

- Never edit before the user confirms the plan; confirm again after Step A before rewriting calls.
- Do not mix the two routers; do not leave both `GetMaterialApp` and `MaterialApp.router`.
- No raw path strings in widgets when typed routes are used; no `BuildContext` in logic classes.
- Never edit files with the `DEPRECATED: migrated by /feature --migrate` header.
- Do not run `git` commands that change state, or `flutter pub add`/`remove`.
