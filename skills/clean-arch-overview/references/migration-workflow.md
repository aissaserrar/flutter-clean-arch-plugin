# Migrating a legacy GetX app: workflow shared by all commands

The migration commands (`/audit`, `/pre-check`, `/feature --migrate`, `/route`, `/di`, `/kill-getx`, `/to-bloc`, `/e2e`) follow the same conventions. This file is the single reference for them; each command points here for the shared parts and keeps only what is specific to it. The target architecture is always the one defined by the `clean-arch-*` skills.

## Order

| # | Command | Why here |
|---|---|---|
| 0 | `/audit` | See where the project stands; re-run after every later step |
| 1 | `/pre-check <target>` | Clean git tree, analyzer baseline, impact of the target |
| 1b | `/e2e` (optional, early) | A few Patrol flows as a safety net before the big changes |
| 2 | `/feature <name> --migrate` | Structure first: legacy files copied into `lib/features/<name>/`, originals marked deprecated |
| 3 | `/route` | `kill-getx` stops while GetX navigation is still the app's router |
| 4 | `/di` | Replaces `Get.put/find/Bindings`, so the `get` import can finally go |
| 5 | `/kill-getx` | Controllers, `.obs`, `Obx`/`GetBuilder`/`GetView` to plain Flutter (the interim form) |
| 6 | `/to-bloc` | The interim form to Cubit/Bloc with sealed states |
| 7 | Tests, `/e2e` | `bloc_test`/widget tests per `clean-arch-testing`, then Patrol flows |

Each command's final report names the next command from this table, not its own list. Commands may be skipped when they do not apply (a project already on go_router skips `/route`).

## Shared gates (mutating commands)

Every command that edits files (`/feature`, `/route`, `/di`, `/kill-getx`, `/to-bloc`, `/e2e`) applies these, in this order:

1. **Clean tree.** `git status --porcelain` is empty. If not, or if the project is not a git repository, recommend `/pre-check`, explain that a clean committed tree is the only easy undo, and ask whether to continue. Default: stop.
2. **Baseline.** `flutter analyze --no-pub`; record the `error •` count. Later checks compare against it; do not try to fix unrelated errors. If Flutter is missing, say the analyzer check cannot run and ask whether to continue.
3. **Scan, then plan.** Run the command's read-only scanner and show the plan with real numbers before touching anything.
4. **Scope confirmation with a size warning.** Say how many files will change, that it is usually many, that work happens in batches (one feature or class at a time, about 10 files), and that each batch should be reviewed with `git diff` and committed before the next. Ask with AskUserQuestion; default is the smallest first step or Cancel. Ask again before every further batch, showing how many remain.
5. **Edit.** Preserve behaviour. Do not rename public members, restructure or "improve". When something has no safe mapping, leave the code, add `// TODO(<command>): <what and why>` (`TODO(route)`, `TODO(di)`, `TODO(kill-getx)`, `TODO(to-bloc)`) and list it in the report.
6. **Check each batch.** `flutter analyze --no-pub` against the baseline: same or fewer errors to continue. More: fix your own errors (at most two attempts per file), otherwise stop and show them. Never revert with git commands.
7. **Format what you touched.** Run `dart format` on the files the command created or changed, not on the whole project: on a legacy codebase a project-wide format buries the real change in noise. (`clean-arch-new-feature` formats the whole project because it starts from formatted code.)
8. **Dependency check.** `bash ${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/scripts/check_dependencies.sh lib`. Violations that the migration has not reached yet are expected; report them, do not fix them in the wrong command.
9. **Report with real numbers.** Before and after counts from the command's scanner, analyzer errors before and after, every `TODO(<command>)` by file, what was left, and the next command from the table above. Never claim a pass that was not run.

## Batch loop (`--batches N`, `--checkpoint`)

Only `/kill-getx` and `/to-bloc` have it: their work is the same few steps repeated dozens of times. `/feature`, `/route`, `/di` and `/e2e` do not loop; their risk is in the plan, not in repetition.

**Without `--batches` nothing changes**: one batch, then ask before the next. With `--batches N` (1 to 10):

- **One confirmation up front**, with real numbers: N, the files expected to change, what will be done without asking, the stop conditions below, and whether checkpoint commits are on. It replaces the per-batch questions. Choices: run up to N batches (default), run one batch, cancel.
- **A batch** is one feature or folder of about 10 files (`/kill-getx`), or one class with its consumer files (`/to-bloc`).
- **Between batches there are no questions.** Each batch does edit, `dart format` on touched files, analyzer check, the command's cleanup step, then prints a **batch summary**: batch k of N, files changed, analyzer errors versus the baseline, `TODO`s added, the progress line (below), and the checkpoint commit if any.
- **Never automatic in loop mode:** deleting old controllers or `ChangeNotifier` classes (listed at the end and asked once), low-confidence `stateful` candidates and `getx` candidates in `/to-bloc`, switching a class between Cubit and Bloc (the plan's suggestion is used), `flutter pub add`/`remove`.
- Not a git repository: N is forced to 1, because the external-change check below needs git.

**Stop conditions.** After every batch, check these in order and stop at the first that applies, saying which one and what to do:

1. The analyzer reports more errors than the baseline (after the two fix attempts per file).
2. Any file hit the two-attempts-per-file limit.
3. The batch added a `TODO(<command>)`: finish that batch, show the new TODOs, do not start the next. The user decides, then resumes.
4. The batch changed more than 15 files, or touched a path outside the planned scope.
5. `git status --porcelain` lists a path the loop did not change in this run (someone edited something meanwhile). With checkpoints, paths already committed by the loop are expected.
6. A gate the command checks at the start no longer holds (for example `/kill-getx`'s routing gate, or a required package that was removed).
7. N batches done, or nothing left in the scope.

Conditions 4 and 5 are checked by a script, not by eye: write the paths the plan allows the loop to create or change (including the new files it will add) to a temp file, write the paths the batch just changed to another, and run `bash ${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/scripts/loop_guard.sh <root> <allowed_paths_file> --batch <batch_paths_file>`. Stop when `stop` is `true` and report its `reasons` and the listed paths.

**Progress line.** After each batch run `bash ${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/scripts/audit.sh <root> <newest .clean-arch/audit-*.json>` (stdout only; nothing is written) and report the non-zero `delta.metrics` changes. If no earlier audit exists, report the current counts and recommend running `/audit` once for a baseline.

**Checkpoints (`--checkpoint`).** The one place a command changes git state, so it needs its own consent: ask with AskUserQuestion, naming the branch and the commit message pattern, before the first batch. If accepted:

- If the current branch is `main`, `master` or `develop`, create `chore/<command>-<target or all>` first (`git switch -c`); otherwise stay on the current branch.
- After each successful batch, stage **only the files that batch created or changed**, listed by path (never `git add -A` or `.`), and commit with `<command>(<target>): batch k of N`. One commit per batch gives you one revertable unit per batch.
- Never push, amend, rebase, force, stash or reset. If a hook or the commit fails, stop (condition 1) and show the error.
- Without `--checkpoint` no command commits anything.

## Conventions

- **Frozen originals.** Files whose first lines contain `DEPRECATED: migrated by /feature --migrate` are never edited by any command and are skipped by every scanner. Deleting them is a separate, explicit decision once nothing imports them. Expect `/audit` to still count their old code until then.
- **Never run by the commands:** `flutter pub add`/`remove`, `dart pub global activate`, `git` commands that change state (`add`, `commit`, `stash`, `checkout`, `reset`, `clean`). Print the command for the user instead. The only exception is `--checkpoint` (see Batch loop), after explicit consent. `dart run build_runner build` and `patrol test` run only after asking.
- **Package choices are the user's.** When there are two supported options (`go_router` or `auto_route`; `get_it` or `provider`) and the user did not say, and `pubspec.yaml` does not already decide it, ask. Never mix the two options of a pair.
- **Read the installed package** (pub cache README/CHANGELOG) before writing code against a version-sensitive API (auto_route, injectable, Patrol).
- **Skills are the source of truth.** A command applies the rules of the skill that owns the topic: structure `clean-arch-overview`, domain `clean-arch-domain`, data `clean-arch-data`, state `clean-arch-presentation`, widgets `clean-arch-ui`, wiring and routing `clean-arch-di-routing`, tests `clean-arch-testing`, new code `clean-arch-new-feature`. If a command and a skill disagree, the skill wins and the command is fixed.
- **Test locations mirror `lib/`:** a cubit at `lib/features/x/presentation/cubit/x_cubit.dart` is tested at `test/features/x/presentation/cubit/x_cubit_test.dart`.

## Which command applies which skill

| Command | Skills it applies |
|---|---|
| `/audit` | `clean-arch-overview` (dependency rules, folder structure) |
| `/pre-check` | `clean-arch-overview` |
| `/feature --migrate` | `clean-arch-overview` (folders), `clean-arch-domain`, `clean-arch-data`, `clean-arch-presentation` (where each file goes) |
| `/route` | `clean-arch-di-routing` (`go-router.md`, auto_route section), `clean-arch-ui` (page provides its cubit) |
| `/di` | `clean-arch-di-routing` (provider and get_it rules), `clean-arch-domain` (domain stays pure) |
| `/kill-getx` | `clean-arch-presentation` (`getx-migration.md`) |
| `/to-bloc` | `clean-arch-presentation`, `clean-arch-ui`, `clean-arch-testing` |
| `/e2e` | `clean-arch-testing` (`patrol.md`) |
