---
description: "Migrate scattered legacy files of a feature into lib/features/<name>/{data,domain,presentation}. Usage: /feature <name> --migrate. Shows a plan first and moves nothing until you confirm."
argument-hint: "<name> --migrate"
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# /feature `<name>` --migrate

Bring the files of one feature from a legacy layout (`lib/controllers`, `lib/models`, `lib/app/modules/<name>`, ...) into `lib/features/<name>/` following the plugin's folder structure.

Files are **copied, not moved**: each original stays at its old path, marked deprecated, and the copy goes into the feature. Every import elsewhere is rewritten to the new path, so the old copies end up unused. File and class names stay the same, so nothing breaks because of a rename. Converting controllers to cubits, splitting models into entity and DTO, and wiring are separate steps (see "After the move").

Shared gates (clean tree, analyzer baseline, scope confirmation, batches, format, report), conventions and the order of the commands are in `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/references/migration-workflow.md`. Read it first; the steps below only add what is specific to this command.

## Steps

1. **Parse `$ARGUMENTS`.** Expect `<name> --migrate`.
   - Convert the name to `snake_case` (`CartItems` -> `cart_items`) and tell the user if you changed it.
   - Without `--migrate`: this command only migrates. For a brand-new feature, follow the `clean-arch-new-feature` skill instead, and stop.
   - The project root is the current directory (`pubspec.yaml` and `lib/` must exist).

2. **Safety gate.** Run `git status --porcelain` and `git rev-parse --abbrev-ref HEAD`.
   - Not a git repository, or uncommitted changes: tell the user a clean, committed tree is what makes this reversible, recommend `/pre-check`, and ask with AskUserQuestion whether to continue or stop. Default: stop.
   - On `main`/`master`: recommend a branch such as `chore/migrate-<name>` (suggest the command; do not run it).

3. **Scan** (read-only):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-new-feature/scripts/feature_scan.sh" "<project root>" "<name>"
   ```

   Exit code `2` means a bad name or no `lib/`: report and stop. If `summary.moves` is `0`, say nothing matched (list `skipped` and `already_in_feature`) and stop.

4. **Show the plan.** A table grouped by destination layer: `from -> to`, confidence, why, and `dependents` (files outside the move that will get rewritten imports). Then list `skipped` with reasons (uses `part`, unclassified, destination exists) and say they will not be touched. Mention that `wiring` (GetX bindings) and `routes` files land in the feature root for review.

5. **Ask for confirmation** with AskUserQuestion:
   - **Apply all** moves.
   - **Apply high-confidence only**.
   - **Cancel** (default).

   The user may also answer with files to exclude; honor that. Say plainly that the originals will stay in place marked deprecated.

6. **Apply.** Write the confirmed copies as `from<TAB>to` lines to a temp file (use `mktemp`, not the project), then:

   ```bash
   S="${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-new-feature/scripts/feature_apply.sh"
   bash "$S" --dry-run --keep-deprecated "<project root>" "<plan file>"
   bash "$S" --keep-deprecated "<project root>" "<plan file>"
   ```

   Always pass `--keep-deprecated` and run the dry run first and show its counts. If either run is `REFUSED` (exit 2), report the reason and stop: nothing was changed. Exit `1` means the copies were made but some imports do not resolve: list the `UNRESOLVED` lines. Some may have been broken before the move.

7. **Check the result** and report real output:
   - `bash "${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/scripts/check_dependencies.sh" lib`
   - `flutter analyze --no-pub` if Flutter is installed (otherwise say it was not run).
   - `dart format` on the files that were created or modified (not the whole project).
   - `git status --short` (new files are untracked; the originals show as modified because of the deprecation marker).

   Remaining dependency violations are expected right after the copy (for example a model with `fromJson` now under `data/`, or a controller still extending `GetxController`). Say so; do not fix them here. Also explain that the deprecated originals still contain the old code (for example GetX), so `/audit` will keep counting it until they are deleted, and that `flutter analyze` may show `deprecated_member_use_from_same_package` infos wherever something still uses an old copy: that list is the to-do list for deleting them.

8. **After the move**, tell the user what is left and the next command from the order table in `migration-workflow.md`: `/route`, then `/di`, then `/kill-getx`, then `/to-bloc`, then tests. Re-running `/audit` shows the effect; the deprecated originals keep their old code (and its GetX) until deleted.

## Rules

- Never move anything before the user confirms the plan.
- Never delete files, rename classes, or edit file contents except what `feature_apply.sh` does: import rewrites, and the deprecation header and `@Deprecated` annotations on the originals.
- Never touch files that already carry the `DEPRECATED: migrated by /feature --migrate` header (the scan skips them).
- Do not delete the deprecated originals. Deleting them is a separate, explicit decision once nothing imports them.
- Do not touch `skipped` files, `core/`, `design_system/`, `l10n/`, `bootstrap/`, `router/`, or other features.
- Imports of migrated files become `package:` imports (the script does this); other imports are left as they are. The deprecated originals keep their old imports, so they stay a self-consistent frozen copy.
- To undo (when the tree was clean and committed before): suggest `git restore .` plus removing the new files (`git clean -fd lib/features/<name>`) for the user to run. Do not run them yourself.
