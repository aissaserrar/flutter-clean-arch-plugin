---
description: Scaffold Clean Architecture foundation — bootstrap/, core/error (Result + AppFailure), design_system/ (stub + optional migrate of widgets/themes), optional router/ stub.
argument-hint: "[--router none|go_router|auto_route] [--di get_it|provider] [--migrate-ds none|high|all|id,id]"
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# /foundation

Create the shared folders and stubs the template expects before mass `/feature --migrate`: `lib/bootstrap/`, `lib/core/error/` (`Result` + `AppFailure`), `lib/design_system/`, and optionally `lib/router/`. When the scan finds legacy shared UI (`lib/widgets/`, `lib/config/themes/`, …), it can **copy** them into `lib/design_system/` (originals kept deprecated, imports rewritten). This command does **not** migrate features, replace GetX, or run `flutter pub add`.

`$ARGUMENTS` may include `--router none|go_router|auto_route`, `--di get_it|provider`, and `--migrate-ds none|high|all|id,id`.

Shared gates (clean tree, analyzer baseline, confirmation) and the command order are in `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/references/migration-workflow.md`. Read it first.

## Steps

1. **Locate the project root** (current directory). Need `pubspec.yaml` and `lib/`.

2. **Safety.** `git status --porcelain` empty preferred. If dirty: recommend `/pre-check`, explain clean tree = easy undo, ask with AskUserQuestion whether to continue (default: stop). On `main`/`master`/`develop`, recommend a branch such as `chore/foundation` (suggest; do not create it). Design-system migrate rewrites many imports — prefer a clean tree.

3. **Scan** (read-only):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/scripts/foundation_scan.sh" "<project root>"
   ```

   Show `present`, `planned_creates`, `di`, `router_recommendation`, `missing_packages`, `design_system_candidates` (id, from → to, file count, confidence), and which audit blockers this run can clear without a router (`blockers_addressed_without_router`).

4. **Resolve options** (in order):
   - **DI:** `--di` if given; else scan `di` (`get_it` / `provider` / `ask`). If `ask`, AskUserQuestion: GetIt (default when neither package exists) vs Provider. Do not choose silently when both exist — ask.
   - **Router:** `--router` if given; else if `router_recommendation` is `none` (GetMaterialApp or scope=state), default **none** and say GetX navigation stays until `/route`. Else AskUserQuestion: **Skip router for now** (default) / **Stub go_router** / **Stub auto_route**. Creating `lib/router/` without installing the package still leaves `pkg_router` / `router_not_getx` blockers red until `/route` finishes.
   - **Design system migrate:** `--migrate-ds` if given; else if `design_system_candidates` is non-empty, AskUserQuestion:
     - **High confidence only** (`--migrate-ds high`) — default when high candidates exist (widgets + themes)
     - **Stub only** (`--migrate-ds none`) — create `design_system/` README, leave widgets/themes in place
     - **All listed** (`--migrate-ds all`) — includes low-confidence (e.g. modals)
     - **Pick ids** — pass comma list e.g. `widgets,themes`
     Summarize file counts before asking. Prefer **high**; warn that modals are often feature-coupled.

5. **Missing packages.** If `missing_packages` is non-empty, print the exact `flutter pub add …` lines (include `bloc_presentation` when missing). Do **not** run them. Ask whether to continue with stubs only (default: yes).

6. **Show the plan and confirm.** Table of stub paths to create + skip-if-exists, plus each DS candidate folder `from → to` and file count when migrating. Never overwrite destinations. Ask: **Apply** (default) / **Dry-run only** / **Cancel**.

7. **Apply:**

   ```bash
   S="${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/scripts/foundation_apply.sh"
   bash "$S" --dry-run --router <choice> --di <choice> --migrate-ds <choice> "<project root>"
   bash "$S" --router <choice> --di <choice> --migrate-ds <choice> "<project root>"
   ```

   Always dry-run first and show counts. DS migrate reuses `feature_apply.sh --keep-deprecated` (copy + deprecate originals + rewrite imports). Templates live under `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/templates/foundation/`.

8. **Wire note (do not auto-edit main unless trivial and confirmed).** Tell the user to call `AppConfig.init` and `configureDependencies()` / `withGlobalProviders` from `main`/`app` when ready — leave a `TODO(foundation)` if you do not wire it in this run. Prefer not editing `main.dart` unless the user asks in the confirmation. After DS migrate, note that old paths still exist deprecated until nothing imports them.

9. **Check.** `dart format` on created/copied files only. `flutter analyze --no-pub` if Flutter is available (report real errors; stubs may warn until wired). Re-run `foundation_scan.sh` and show remaining gaps (candidates should shrink after migrate). Suggest `/audit` to see blocker score move. Next from the order table: `/pre-check` then `/feature <name> --migrate`, or `/route` if a router stub was added.

## What this unblocks (audit)

| Created | Typical blockers cleared |
|---|---|
| `lib/bootstrap/` + `app_config` + injection/providers | `has_bootstrap` |
| `lib/core/error/result.dart` (or `common/`) | `has_result_type`, `has_app_failure` |
| `lib/design_system/` | `has_design_system` (major) |
| `--migrate-ds` widgets/themes into `design_system/` | same + fewer “widget in core/common” engineering hits over time |
| `lib/router/` stub only | `has_router_dir` — **not** `pkg_router` / `router_not_getx` until `/route` |

Does **not** clear: `feature_first`, `cubit_no_http`, custom cubit bases — those need `/feature` and `/to-bloc`.

## Rules

- Never overwrite an existing file.
- Never run `flutter pub add` / `git commit` / destructive git.
- Never migrate features or rewrite GetX here (DS folder copy is the only relocate).
- Prefer `--router none` when the project keeps GetX navigation.
- Prefer `--migrate-ds high` (or none) over `all`; do not silently migrate low-confidence folders.
- Templates are stubs with `TODO(foundation)` — behaviour of the running app must not change until the user wires them. DS migrate keeps deprecated originals so the app keeps compiling while imports flip to the new paths.
