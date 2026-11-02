---
description: Safety dry-run before a refactor or migration: flutter analyze must be error-free, git state is checked, and the impact of the target files is measured. Changes nothing.
argument-hint: "[feature-name | path ...]"
allowed-tools: Bash, Read
---

# /pre-check

Decide whether it is safe to start refactoring `$ARGUMENTS` (feature names such as `fasting`, paths, or nothing for the whole of `lib/`). This command is a dry run: it never edits, stages, commits, stashes or formats anything.

The gates this command checks (clean tree, analyzer baseline) are defined in `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/references/migration-workflow.md`, which also holds the conventions and the order of the commands are in `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/references/migration-workflow.md`.

## Steps

1. **Locate the project root** (current directory). It must contain `pubspec.yaml` and `lib/`; otherwise say so and stop.

2. **Run `flutter analyze`** and keep the output:

   ```bash
   flutter analyze --no-pub 2>&1 | tail -n 200
   ```

   - If `flutter` is not installed, say so, mark the analyze check as **not run** (not as passed), and continue.
   - Count lines containing `error •`. Also count `warning •` and `info •`.
   - If the output suggests missing packages (`Target of URI doesn't exist`, `uri_does_not_exist`), tell the user to run `flutter pub get` and do not run it yourself.

3. **Collect git state and impact metrics** (read-only):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/scripts/pre_check.sh" "<project root>" $ARGUMENTS
   ```

   The JSON has `targets` (resolved files, LOC, anything in `unresolved`), `git`, `impact` (GetX hits, Cubit/Bloc files, StatefulWidgets, dependents outside the targets, `dependent_test_files`) and `tests`. Exit code `2` means no `lib/`.

4. **Decide the verdict** from these rules, and show each as pass / warn / block:

   | Check | Block (NO-GO) | Warn |
   | --- | --- | --- |
   | `flutter analyze` | any `error •` | `warning •` present, or not run |
   | Git | not a repository, or `staged + unstaged > 0` | `untracked > 0`, `behind > 0`, branch is `main`/`master`/`develop` |
   | Targets | `unresolved` not empty, or 0 files resolved | |
   | Tests | | `uncovered > 0` (no test mirrors or imports those files) |
   | Dependents | | `dependents > 0` (callers outside the target will need updating) |

   Verdict: **GO** (no blocks, no warns), **GO with cautions** (warns only), **NO-GO** (any block).

5. **Print the report** in this order, compactly:
   - Verdict line first.
   - The checks table above with real numbers (error/warning counts, changed-file counts, branch).
   - Impact: target file count and LOC, GetX hits, Cubit/Bloc files, StatefulWidgets, `dependents` (non-test files outside the targets; list up to 10 and note they are matched approximately for relative imports), tests: `covered` vs `uncovered` target files (a file is covered when a mirrored test exists or any test imports it; this says nothing about test quality), and list up to 10 `uncovered_files`.
   - End with the next command from the order table in `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/references/migration-workflow.md` (usually `/feature <name> --migrate` for a legacy layout, or `/route` when the layout is already feature-first).
   - If NO-GO or cautions, the concrete next step for each (for example: commit or stash the listed changes, create a branch such as `chore/migrate-<target>`, fix the analyzer errors listed). Suggest the commands; do not run them.

## Rules

- Never modify the working tree or run `git` commands that change state (`add`, `commit`, `stash`, `checkout`, `reset`, `clean`).
- Report real analyzer output. Do not claim a clean analyze if it was not run.
- This command only reports. Refactoring commands are separate.
