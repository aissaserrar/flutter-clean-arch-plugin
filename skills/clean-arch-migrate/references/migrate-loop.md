# The migrate loop

Paths use `${CLAUDE_PLUGIN_ROOT}`. `STATE` means `bash ${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-migrate/scripts/migrate_state.sh "<root>"`.

## 1. Preflight (stop with a clear message if any fails)

1. `pubspec.yaml` and `lib/` exist. `git status --porcelain` is empty (otherwise recommend `/pre-check`; default is to stop).
2. `.clean-arch/config.json` exists. If not, run `/audit` first: it asks the scope and mode once and saves them. Without it the plan is only assumed.
3. Run `bash ${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/scripts/migration_plan.sh "<root>"`. If `totals.controllers` is 0, there is nothing to migrate: say so and stop.
4. Required dependencies for the target (`flutter_bloc`, `equatable`, and `bloc_presentation` if needed) are in `pubspec`; if not, print the exact `flutter pub add` command and stop. Never run it.
5. Baseline: `flutter analyze --no-pub`; record the `error •` count in your notes and in `progress.json` (`baseline_errors`).
6. Progress: if `.clean-arch/progress.json` exists, resume (show `STATE summary`). Otherwise `STATE init "<root>/.clean-arch/audit-<latest>.json"` (or the plan JSON saved from step 3).

## 2. The one confirmation

Show: number of features, controllers and files expected to change (from the plan), the settings (`mode`, `scope`, `structure`), what the project's own rules override, the stop conditions below, that each feature is verified with the analyzer and that nothing is deleted. Warn that this is usually hundreds of files and that `--checkpoint` makes each feature a revertable commit. Ask: **Start** (default), **Dry run (show the order only)**, **Cancel**.

## 3. Foundation (once, only when `scope` is `full`)

Run `/route` then `/di` (they ask GoRouter vs AutoRoute and GetIt vs Provider when `pubspec` does not decide). When `scope` is `state` these are skipped, because the project keeps its navigation and DI.

## 4. Per feature (repeat while `STATE next` prints a name)

1. `STATE set <feature> in_progress`.
2. `/pre-check <feature>`: NO-GO blocks this feature (mark it `blocked`, continue).
3. **Load the rules.** Read the checklists of `clean-arch-presentation`, `clean-arch-domain`, `clean-arch-data` and `clean-arch-ui` (`SKILL.md`) and the Direct mode section of `clean-arch-presentation/references/getx-migration.md`. Do this for every feature, not once per run: they scroll out of context in a long run.
4. **Read the whole feature** (controllers, views, call sites, the repositories/services they use) and write a short design (shape, sealed states, dependencies, effects). Put it in the feature summary; it is not an extra question.
5. When `structure` is true: `/feature <feature> --migrate`.
6. `/to-bloc <feature>` converts the whole feature as one unit (direct mode is the default; only in interim mode run `/kill-getx <feature>` first), extracting data/domain into the feature layers. Then `/kill-getx <feature>` only for leftovers (`redirect` must be empty).
7. Verify: `flutter analyze --no-pub` at or below the baseline; `check_dependencies.sh lib` for the feature's files; `clean-arch-presentation` checklist (plain `Cubit`/`Bloc`, sealed states); re-run `/audit` and show the delta. Quality findings on the feature's new files (see `audit.sh` `design_quality`) count as a failed attempt: fix them, at most twice, otherwise mark the feature `blocked`.
6. `STATE set <feature> done`.
7. Ask with AskUserQuestion: **"Write and run an e2e test for <feature>?"** Options: Yes, No (default). Yes: `/e2e <feature>`, then `STATE set <feature> done done` (or `failed`: record it and continue; a failing e2e never blocks the next feature). No: `STATE set <feature> done declined`.
8. Next feature.

Inside `/migrate` the unit of work is one feature, even above 10 files, because splitting a feature across batches loses the design. The analyzer still runs after each controller. Run standalone, the commands keep their own batch limits.

## 5. Stop conditions (mechanical)

Stop the whole run when: the analyzer reports more errors than the baseline and two fix attempts did not restore it (mark the feature `blocked`, ask whether to continue with the next); something outside the loop changed the project (`git status` shows files the loop did not touch); a gate no longer holds; the user says stop; or there is nothing left. Per feature: more than two failed attempts on one file, or a `TODO(...)` that needs a human decision, marks that feature `blocked` and moves on. Use `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/scripts/loop_guard.sh` where `migration-workflow.md` says to.

## 6. Finish

Run `/audit` once more. Report: features done, blocked (with the reason and the command to retry each), e2e per feature (done, declined, failed), analyzer errors before and after, GetX usages before and after, every `TODO` by file, and the old controllers left for the user to delete. Say plainly whether the project is `compliant`; if not, what remains.
