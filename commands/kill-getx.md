---
description: Remove GetX controllers, .obs, Obx/GetBuilder/GetView and package:get imports in confirmed batches, moving code to plain Flutter (ChangeNotifier + ListenableBuilder) that /to-bloc later turns into Cubits. Checks flutter analyze after every batch.
argument-hint: "[--batches N] [--checkpoint] [feature-name | path ...]"
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
---

# /kill-getx

Remove GetX from `$ARGUMENTS` (feature names, paths, or nothing for all of `lib/`). The mapping from GetX to the interim form is in `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-presentation/references/getx-migration.md`: read it before editing anything.

The result is **not** Cubits. It is plain Flutter that compiles and behaves the same, with no GetX. `/to-bloc` converts it afterwards. Doing both at once makes regressions impossible to localize.

Shared gates (clean tree, analyzer baseline, scope confirmation, batches, format, report), conventions and the order of the commands are in `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/references/migration-workflow.md`. Read it first; the steps below only add what is specific to this command.

## Steps

1. **Preconditions.**
   - `pubspec.yaml` and `lib/` exist.
   - `git status --porcelain` is empty. If not (or not a repository), recommend `/pre-check`, explain that a clean committed tree is the only easy undo, and ask with AskUserQuestion whether to continue. Default: stop.
   - **Baseline:** run `flutter analyze --no-pub` and record the number of `error •` lines. If Flutter is missing, say the per-batch analyzer check cannot run and ask whether to continue anyway. If the baseline already has errors, say so: you can only judge regressions against it, so report the number and do not try to fix unrelated errors.

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

3. **Confirm the scope, and warn about its size.** Before touching anything, tell the user in plain words, with the real numbers from the scan:
   - how many files this command will change (`totals.files` that have something handled here: controllers, views, other), and how many import lines may be removed;
   - that this is usually a lot of files, that it will be done feature by feature in batches of about 10 files with a `flutter analyze` check after each batch, and that it can take many rounds and a lot of review time;
   - that each batch edits real code by hand-written transformation, so every batch should be reviewed (`git diff`) and committed before the next;
   - what is deferred or manual and will remain.

   Then ask with AskUserQuestion: **Start with the first batch** (default for a small project), **Choose which feature/folder to start with**, or **Cancel**. Do not continue without an explicit answer. A batch is one feature (or at most about 10 files). Never run the whole project in one go. After each batch, ask again before the next one, showing how many files remain.

   **Loop mode.** If `$ARGUMENTS` has `--batches N` (and optionally `--checkpoint`), follow "Batch loop" in `migration-workflow.md`. This confirmation is then the only one: state N, the files expected to change, the stop conditions and, with `--checkpoint`, the branch and commit pattern, and ask: **Run up to N batches** (default), **Run one batch only**, **Cancel**. Without `--batches`, ask before every batch as above.

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

7. **Next batch.** Without `--batches`: offer the next batch and ask. In loop mode: print the batch summary (with the progress line), check the stop conditions from `migration-workflow.md`, and start the next batch only if none applies and batches remain. When the loop ends, say which condition ended it. When no file imports `package:get`, tell the user to run `flutter pub remove get` themselves (the script prints this). When no file imports `package:get`, tell the user to run `flutter pub remove get` themselves (the script prints this).

8. **Final report.** Real numbers only: files changed, GetX usages before and after (re-run the scan), analyzer errors before and after, deferred and manual leftovers by file, and what to run next. Next: `/route` or `/di` first if anything is still deferred to them, otherwise `/to-bloc` (order table in `migration-workflow.md`). Suggest committing after each successful batch.

## Rules

- Never start without the preconditions, the routing gate and the user's confirmation of the scope; ask again before every further batch, unless the user chose loop mode at the single confirmation, and then only within its stop conditions.
- Behaviour must not change. If in doubt, leave the code and flag it.
- Do not run `git` commands that change state (the only exception is the `--checkpoint` commits, after explicit consent), and do not run `flutter pub remove get` yourself.
- In loop mode never delete a controller on your own: list candidates and ask once at the end.
- Do not convert to Cubit/Bloc here.
