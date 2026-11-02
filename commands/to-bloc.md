---
description: Convert ChangeNotifier-style state holders (the interim form left by /kill-getx) into Cubits, or Blocs where event transformers are needed, with sealed states, and update the UI to BlocBuilder / BlocListener. One class at a time, confirmed, with flutter analyze checks.
argument-hint: "[--batches N] [--checkpoint] [feature-name | path ...]"
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
---

# /to-bloc

Replace the state holders in `$ARGUMENTS` (feature names, paths, or nothing for all of `lib/`) with Cubit/Bloc classes and update the widgets that read them. Follow `clean-arch-presentation` and `clean-arch-ui` for every rule, and `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-presentation/references/notifier-to-cubit.md` for the mapping and a worked example. Read those before editing.

Input is normally what `/kill-getx` produced. This command does not remove GetX itself.

Shared gates (clean tree, analyzer baseline, scope confirmation, batches, format, report), conventions and the order of the commands are in `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/references/migration-workflow.md`. Read it first; the steps below only add what is specific to this command.

## Steps

1. **Preconditions.**
   - `pubspec.yaml` and `lib/` exist, and `git status --porcelain` is empty. If not, recommend `/pre-check`, explain that a clean committed tree is the only easy undo, and ask with AskUserQuestion whether to continue (default: stop).
   - Baseline: `flutter analyze --no-pub`, record the `error •` count. If Flutter is missing, say the per-class check cannot run and ask whether to continue.

2. **Scan** (read-only):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-presentation/scripts/to_bloc_scan.sh" "<project root>" $ARGUMENTS
   ```

   Gates, in this order:
   - **Dependencies.** From `pubspec`: `flutter_bloc` and `equatable` are required; `bloc_presentation` is required if any class needs a one-off effect; `bloc_test` and `mocktail` for tests. If something required is missing, tell the user the exact command to run (for example `flutter pub add flutter_bloc equatable bloc_presentation`) and stop. Do not run it yourself.
   - **GetX still present.** Candidates with `kind: getx` are not converted: tell the user to run `/kill-getx` first for those, and list them. If `files_still_using_getx` is above zero, say how many and recommend finishing `/kill-getx` first; ask whether to continue with the `notifier` candidates only (default: stop).
   - `skipped_deprecated_copies` are frozen originals from `/feature --migrate`: never touch them.

   If no `notifier` or `stateful` candidates remain, say so and stop.

3. **Show the plan.** A table: class, file, suggested `Cubit`/`Bloc` with the reason (`transformer_signals`), proposed file path (`names.dir` + `file_stem`), number of consumer files and how many use `provider`/`ListenableBuilder`. For `stateful` candidates say they are low confidence: only convert one if its state is shared, loaded asynchronously or reports errors, and leave ephemeral UI state (animations, text controllers, focus, tab index) alone. For stateful rows `notify_listeners` is the number of `setState` calls and `async_markers` the number of `await`/`.then`.

4. **Confirm scope and warn about its size.** Say how many classes and consumer files will change, that each class is converted one at a time with an analyzer check, that every conversion should be reviewed with `git diff` and committed before the next, and that default is Cubit (Bloc only where the plan says so). Ask with AskUserQuestion: **Start with the first class** (default), **Choose a class**, **Cancel**. Ask again before each further class, showing how many remain. The user may switch a class between Cubit and Bloc.

   **Loop mode.** If `$ARGUMENTS` has `--batches N` (and optionally `--checkpoint`), follow "Batch loop" in `migration-workflow.md`: a batch is one class with its consumer files. This confirmation is then the only one: state N, the classes and files expected to change, the stop conditions and, with `--checkpoint`, the branch and commit pattern, and ask once whether to generate `bloc_test` tests for every class. Only `notifier` candidates are converted automatically, using the plan's Cubit/Bloc suggestion; `stateful` and `getx` candidates and old-class deletions are never automatic. Ask: **Run up to N batches** (default), **Run one batch only**, **Cancel**.

5. **Convert one class** (read the class and every file in `consumers.files` first):
   1. Design the state from the notifier's fields (sealed `Initial/Loading/Success/Failure` by default, or a status-enum class when many independent fields change separately). Names, `Equatable`, no strings, as in the reference.
   2. Write **one file** at `names.dir/<file_stem>_cubit.dart` (or `_bloc.dart`), in the order cubit, events (Bloc only), state, presentation events. No `part`. Constructor dependencies stay as they were, but they must be interfaces from `domain`: if the notifier imports `data/` internals, keep the dependency, add a `// TODO(to-bloc): depends on data internals` and list it.
   3. One-off effects (navigation, snackbar, dialog) become presentation events with `BlocPresentationMixin`; remove any `BuildContext` use from the logic.
   4. Update the UI: the page provides the cubit with `BlocProvider`; `ListenableBuilder`/`Consumer`/`context.watch` become `BlocBuilder` (exhaustive `switch`), `BlocSelector`, `BlocListener` or `BlocConsumer` per the reference; widgets that took the controller as a parameter now read the cubit from context, and every call site is updated. Keep layout and design-system components unchanged.
   5. Do not guess: constructs without a clean mapping (`addListener` between notifiers, `onReady`-style timing, `ever`/`debounce` leftovers) stay as they are with `// TODO(to-bloc): <what and why>` and go into the report.
   6. Delete the old `ChangeNotifier` class only when nothing references it any more; list the file and get explicit confirmation first. Otherwise leave it and say why.

6. **Check the class.** `dart format` on the files you created or changed, then `flutter analyze --no-pub` against the baseline: same or fewer errors to continue; if more, fix your own errors (at most two attempts per file), otherwise stop and show them. Never revert with git commands.

7. **Offer tests.** (In loop mode use the answer given once at the start.) Ask whether to generate `bloc_test` cases for the new cubit (success, failure, edge cases) following `clean-arch-testing`, in `test/features/<feature>/presentation/cubit/` (the test tree mirrors `lib/`). Only if `bloc_test` and `mocktail` are in `pubspec`; otherwise print the `flutter pub add --dev` command. Run `flutter test` on the new file when Flutter is available and report the real result.

8. **Next class.** Without `--batches`: offer the next class and ask. In loop mode: print the batch summary (with the progress line), check the stop conditions from `migration-workflow.md`, continue only if none applies and batches remain, and say which condition ended the loop. Finish with the report: classes converted, files changed, analyzer errors before and after, `bash "${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/scripts/check_dependencies.sh" lib` output, every `TODO(to-bloc)` by file, the classes left (getx, stateful, ephemeral), and the next step: the remaining tests per `clean-arch-testing`, `/e2e` for the critical flows, deleting the deprecated originals once nothing imports them, and a fresh `/audit`.

## Rules

- Never edit before the user confirms the class; ask again before every further class, unless the user chose loop mode at the single confirmation, and then only within its stop conditions.
- Default to Cubit; Bloc only for event transformers or multiple triggers per state change.
- Behaviour must not change. If in doubt, leave the code and flag it.
- Never edit files with the `DEPRECATED: migrated by /feature --migrate` header.
- Do not run `git` commands that change state (the only exception is the `--checkpoint` commits, after explicit consent) or `flutter pub add`/`remove` yourself.
- In loop mode never delete an old class on your own: list candidates and ask once at the end.
- No business rules in a cubit: if the notifier has them, move them to a use case or flag them.
