---
description: Remove GetX controllers, .obs, Obx/GetBuilder/GetView and package:get imports in confirmed batches, moving code to plain Flutter (ChangeNotifier + ListenableBuilder) that /to-bloc later turns into Cubits. Checks flutter analyze after every batch.
argument-hint: "[--batches N] [--checkpoint] [feature-name | path ...]"
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
---

# /kill-getx

Remove GetX from `$ARGUMENTS` (feature names, paths, or nothing for all of `lib/`). The mapping from GetX to the interim form is in `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-presentation/references/getx-migration.md`: read it before editing anything.

The result is **not** Cubits. It is plain Flutter that compiles and behaves the same, with no GetX. `/to-bloc` converts it afterwards. Doing both at once makes regressions impossible to localize.

Shared gates (clean tree, analyzer baseline, scope confirmation, batches, format, report), conventions and the order of the commands are in `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/references/migration-workflow.md`. Read it first; the steps below only add what is specific to this command.

**Redirect.** The default mode is `direct`: the scan returns `"redirect": "to-bloc"` when the targets contain GetX controllers and the mode is `direct` (the default) or the project forbids `ChangeNotifier`/`ValueNotifier`. Stop, say why, and tell the user to run `/to-bloc` for the controllers: it converts them straight to Cubits, designed from the controller's intent, so each file is rewritten once. `/kill-getx` is then only for what is left afterwards (widgets, extensions, leftover imports). Only with `mode: interim` in `.clean-arch/config.json` (the user chose it in `/audit`) is the redirect empty and the interim form below used.

## Steps

1. **Preconditions.** Shared gates 1 and 2 (clean tree, analyzer baseline) from `migration-workflow.md`. If the baseline already has errors, report the number and do not fix unrelated ones.

2. **Inventory and routing check** (read-only):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-presentation/scripts/kill_getx_scan.sh" "<project root>" $ARGUMENTS
   ```

   **Routing gate (do this before anything else).** Read `routing` in the JSON:
   - `needs_route_first` is `true`: the app still navigates with GetX (`Get.to`, `GetPage`, `GetMaterialApp`) and no other router (`go_router`, `auto_route`) is installed. Do not start. Tell the user plainly: GetX navigation must be replaced first, because removing the `package:get` import is impossible while it is still used for routing, and the files that navigate would stay half-migrated. Ask them to run `/route` first (it asks whether to use go_router or auto_route) and stop. Only if the user insists, offer with AskUserQuestion to continue with just the controllers and widgets (navigation files keep their `get` import); default is to stop.
   - `route_migration_incomplete` is `true`: a router is installed but `getx_navigation_hits` / `getx_app_root_files` are still above zero. Say so with the numbers, recommend finishing `/route` first, and ask whether to continue anyway (default: stop).
   - Both `false`: routing is already off GetX, continue.

   **DI check.** Read `totals.di`: if above zero, say that these `Get.find/put/Bindings` keep their `package:get` import until `/di` has run, recommend `/di` first, and ask whether to continue anyway (default: continue with controllers and widgets).

   Show `totals` and the file list in work order (controllers, then views, then the rest). Separate three groups:
   - **Handled here:** `import`, `controller`, `widgets` (Obx/GetBuilder/GetX), `view` (GetView/GetWidget), `obs`, `lifecycle`.
   - **Deferred:** `route` (-> `/route`), `di` (-> `/di`).
   - **Manual:** snackbar, dialog, `.tr`, `Get.context`, `GetConnect`, ...

   `skipped_deprecated_copies` are frozen originals from `/feature --migrate`: mention the count and never touch them. If nothing is handled here, say so and stop.

3. **Confirm the scope.** Shared gate 4: give the real numbers (files to change from `totals.files`, import lines to remove, what stays deferred or manual), then ask **Start with the first batch** (default), **Choose which feature/folder**, or **Cancel**. A batch is one feature or about 10 files; ask again before each next batch.

   **Loop mode.** With `--batches N` (and optionally `--checkpoint`) follow "Batch loop" in `migration-workflow.md`; this confirmation is then the only one.

4. **Refactor the batch, controllers first.** For each file, follow `getx-migration.md` exactly:
   - Controller: `ChangeNotifier`, `.obs` -> private field + getter, mutations call `notifyListeners()`, `update()` -> `notifyListeners()`, `onClose` -> `dispose`.
   - Views that read it: `Obx`/`GetBuilder` -> `ListenableBuilder`, `GetView<C>` -> `StatelessWidget` with a `controller` constructor parameter. Update every call site of that widget in the batch to pass the controller.
   - Read the whole file and its direct users first. Keep behaviour identical; do not rename public members, restructure, or "improve" anything.
   - A controller that nothing references any more may be deleted, but only after listing it and getting explicit confirmation.
   - Constructs you cannot map safely (`ever`/`debounce` workers, `onReady`, `Get.find`, anything in the Deferred or Manual groups): leave the code and its `package:get` import, add a `// TODO(kill-getx): <what and why>` comment, and list it in the report.
   - Never edit files carrying the `DEPRECATED: migrated by /feature --migrate` header.

5. **Check the batch.** Run `dart format` on the files you changed, then `flutter analyze --no-pub` and compare `error •` with the baseline.
   - Same or fewer: continue.
   - More: fix your own errors (at most two attempts per file). If still failing, stop, show the errors and the files touched, and let the user decide. Do not move on to the next batch with new errors, and do not revert with git commands.

6. **Remove leftover imports.** Dry run first, show it, then apply (in loop mode apply directly and list the files in the batch summary):

   ```bash
   F="${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-presentation/scripts/kill_getx_finish.sh"
   bash "$F" "<project root>" $ARGUMENTS
   bash "$F" --apply "<project root>" $ARGUMENTS
   ```

   It removes `package:get` imports only from files with no GetX symbol left and never edits `pubspec.yaml`. Run the analyzer once more after `--apply`. If it now reports a missing member, the file was using a GetX extension: restore the import line in that file and list it.

7. **Next batch.** Without `--batches`: offer the next batch and ask. In loop mode: print the batch summary (with the progress line), check the stop conditions from `migration-workflow.md`, and start the next batch only if none applies and batches remain. When the loop ends, say which condition ended it. When no file imports `package:get`, tell the user to run `flutter pub remove get` themselves (the script prints this).

8. **Final report.** Real numbers only: files changed, GetX usages before and after (re-run the scan), analyzer errors before and after, deferred and manual leftovers by file, and what to run next. Next: `/route` or `/di` first if anything is still deferred to them, otherwise `/to-bloc` (order table in `migration-workflow.md`). Suggest committing after each successful batch.

## Rules

- Never start without the preconditions, the routing gate and the user's confirmation of the scope; ask again before every further batch, unless the user chose loop mode at the single confirmation, and then only within its stop conditions.
- Behaviour must not change. If in doubt, leave the code and flag it.
- Do not run `git` commands that change state (the only exception is the `--checkpoint` commits, after explicit consent), and do not run `flutter pub remove get` yourself.
- In loop mode never delete a controller on your own: list candidates and ask once at the end.
- Do not convert to Cubit/Bloc here.
