# `/migrate` conductor and its prerequisites: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `clean-arch-migrate` skill and `/flutter-clean-arch:migrate` command that migrate a GetX app (Nology) to Clean Architecture + BLoC feature by feature, asking for an e2e test after each feature, resumable, and stopping on mechanical conditions.

**Architecture:** Tasks 1-4 finish the prerequisites the conductor needs (config question in `/audit`, direct GetxController-to-Cubit mode in `/to-bloc`, `/kill-getx` redirect, unit-name targets). Task 5 adds a small bash state helper (`migrate_state.sh`) so progress handling is testable. Tasks 6-7 add the skill/command and wire docs and checker. No new scanners; the conductor only sequences existing commands.

**Tech Stack:** bash + awk + grep (macOS bash 3.2 and BSD grep compatible, no Python), Markdown command/skill files, JSON output.

**Spec:** `docs/superpowers/specs/2026-11-02-migrate-skill-design.md`

## Global Constraints

- Commands never run `flutter pub add`/`remove`; no state-changing git except opt-in `--checkpoint`; nothing is pushed.
- Commits: NO `Co-Authored-By` line (user instruction, overrides any attribution reminder). Commit only when the user asks.
- Files whose header contains `DEPRECATED: migrated by /feature --migrate` are never edited.
- Scripts must run on macOS bash 3.2 (no `${var^}`, no associative arrays) and BSD grep (keep alternations short; no `\b`).
- Project conventions (CLAUDE.md/AGENTS.md/project skills) override generic plugin rules; the run states any override and saves it to `.clean-arch/config.json`.
- Done = GetX usages 0, audit status `compliant`, analyzer errors <= baseline, existing tests pass.
- Skill name `clean-arch-migrate`; command file `commands/migrate.md`; state file `.clean-arch/progress.json`.
- Every change must keep `bash scripts/check_consistency.sh` and `bash scripts/check_getx_coverage.sh` passing.

## Review Focus

- Resuming with a `progress.json` that lists a feature no longer in the audit plan: it is kept as `done`/`blocked`, not silently dropped.
- A corrupt or hand-edited `progress.json`: the helper refuses and says why; it never overwrites.
- Project forbids ChangeNotifier but a feature has no GetX controller (only widgets): `/kill-getx` redirect must not trigger a pointless stop.
- Unit name that matches no files, or two units with a common prefix (`home` vs `home_tab`): resolver returns the exact unit only.
- User declines every e2e question: the run still completes and the final report shows `declined` per feature.

---

### Task 1: `/audit` asks the scope question and saves config

**Files:**
- Modify: `commands/audit.md`
- Modify: `commands/templates/audit-report.html` (hide `/feature X --migrate` tags in the Target tree when plan `settings.structure` is false; show a muted "later" tag)

**Interfaces:**
- Consumes: `migration_plan.sh` output `settings {mode, scope, structure, assumed}`; `conventions_scan.sh`.
- Produces: `.clean-arch/config.json` with keys `mode` (`direct|interim`), `scope` (`state|full`), `structure` (`true|false`), no `assumed` flag once written.

- [ ] **Step 1:** In `commands/audit.md`, after the report opens, add a step: when `settings.assumed` is true and BLoC infrastructure exists, ask ONE `AskUserQuestion` (scope: state only vs full removal; mode: direct vs interim), write the answers to `.clean-arch/config.json`, re-run the audit, and print the plan summary (waves, first unit).
- [ ] **Step 2:** Edit the template so the Target tree tag respects `settings.structure`.
- [ ] **Step 3:** Verify: run `bash skills/clean-arch-overview/scripts/migration_plan.sh <nology>` before and after writing a config file by hand (`{"mode":"direct","scope":"full","structure":true}`); expected `assumed:false` and steps that include `/route`, `/di`, `/feature`.
- [ ] **Step 4:** `bash scripts/check_consistency.sh` prints OK.

### Task 2: Shared unit-name resolution

**Files:**
- Modify: `skills/clean-arch-overview/scripts/detect.sh` (add `resolve_target <name>` printing files of that exact feature unit, one per line, using `unit_files`)
- Modify: `skills/clean-arch-overview/scripts/pre_check.sh`, `skills/clean-arch-presentation/scripts/to_bloc_scan.sh`, `skills/clean-arch-presentation/scripts/kill_getx_scan.sh` to accept a unit name via `resolve_target` before treating the argument as a path.

**Interfaces:**
- Produces: `resolve_target <name>` returns exit 1 and no output when the name is not a unit; `home` never returns `home_tab` files unless they belong to unit `home`.

- [ ] **Step 1:** Add fixture under the scratchpad: `lib/home/home_tab.dart`, `lib/home/home_screen.dart`, `lib/home_tab_extra/x.dart` (distinct unit).
- [ ] **Step 2:** Run `resolve_target home`, expect exactly the two `home` files; `resolve_target nope`, expect exit 1.
- [ ] **Step 3:** Implement in `detect.sh` and wire the three scanners.
- [ ] **Step 4:** Re-run Step 2; run `pre_check.sh home` on the fixture and expect it to report 2 files. `check_consistency.sh` OK.

### Task 3: `/to-bloc` direct mode

**Files:**
- Direct GetX→Cubit rules live in `skills/clean-arch-presentation/references/getx-migration.md` (Direct mode section); do not recreate `getx-to-cubit-direct.md`
- Modify: `commands/to-bloc.md`, `skills/clean-arch-presentation/scripts/to_bloc_scan.sh`

**Interfaces:**
- Consumes: `conventions_scan.sh` (`cubit_base_classes`, `state_variants`, `rules`, `migration.mode`) and `migration_plan.sh` controller `kind` per unit.
- Produces: `to_bloc_scan.sh` JSON gains `mode`, `conventions` (base classes, state variants, rules with evidence), per-controller `kind`, `consumers`, `mixins`.

- [ ] **Step 1:** Write the reference: direct mapping GetxController to Cubit by kind (data, paginated, form, plain, service, lifecycle, animation); two phases (controller to cubit, then UI rewiring and DI registration); mark the old controller `@Deprecated`, never delete; use project base classes and state variants; no tests unless the project allows; ask before converting forms (`clean-arch-forms`).
- [ ] **Step 2:** Update `commands/to-bloc.md`: read project conventions first and state which generic rules they override; choose direct mode when `mode=direct`; accept unit names; one class at a time with analyzer check.
- [ ] **Step 3:** Extend `to_bloc_scan.sh` output as above. Verify on Nology: `bash ...to_bloc_scan.sh <nology> <unit>` prints `"mode":"direct"` and lists `DataCubit`/`BaseCubit` as bases; `python3 -m json.tool` accepts the output.
- [ ] **Step 4:** `check_consistency.sh` OK.

### Task 4: `/kill-getx` redirect when ChangeNotifier is forbidden

**Files:**
- Modify: `commands/kill-getx.md`, `skills/clean-arch-presentation/scripts/kill_getx_scan.sh`

**Interfaces:**
- Produces: `kill_getx_scan.sh` JSON field `conventions.change_notifier_forbidden` (bool) and `redirect` (`"to-bloc"` or empty). Redirect is set only when the targets contain GetX controllers.

- [ ] **Step 1:** Add the fields from `conventions_scan.sh` rules; set `redirect` only when ChangeNotifier is forbidden AND controllers exist in the targets.
- [ ] **Step 2:** In `kill-getx.md`: if `redirect` is `to-bloc`, stop and tell the user to run `/to-bloc` (use `/kill-getx` only for leftovers: widgets, extensions, imports).
- [ ] **Step 3:** Verify: on Nology a controller unit gives `redirect:"to-bloc"`; on a widgets-only fixture gives empty. `check_consistency.sh` OK.

### Task 5: Progress state helper

**Files:**
- Create: `skills/clean-arch-migrate/scripts/migrate_state.sh`

**Interfaces:**
- Produces (all take the project root as first argument, store in `<root>/.clean-arch/progress.json`):
  - `migrate_state.sh <root> init <audit-json>`: creates features from `migration_plan.waves[].units[]` order with status `pending`; refuses if the file exists.
  - `migrate_state.sh <root> next`: prints the next feature name that is `pending` or `in_progress`, empty when none.
  - `migrate_state.sh <root> set <feature> <status> [e2e]`: status `pending|in_progress|done|blocked`; e2e `done|declined|failed`.
  - `migrate_state.sh <root> summary`: prints counts and the blocked list.
  - Exit 2 and a message on malformed JSON; never overwrites.

- [ ] **Step 1:** Write a bash test script `skills/clean-arch-migrate/scripts/test_migrate_state.sh` using a temp dir and a fake audit JSON: init creates 3 features in order; `next` returns the first; after `set a done declined`, `next` returns the second; `set b blocked` then `next` returns the third; `summary` lists `b`; corrupt file gives exit 2 and file unchanged; second `init` refuses.
- [ ] **Step 2:** Run it; expect failure (script missing).
- [ ] **Step 3:** Implement with awk/sed only; keep JSON one feature per line so edits are line-based.
- [ ] **Step 4:** Run the test script; expect `OK`.

### Task 6: The skill and the command

**Files:**
- Create: `skills/clean-arch-migrate/SKILL.md` (short: rules and checklist), `skills/clean-arch-migrate/references/migrate-loop.md` (steps, stop conditions, prompts), `commands/migrate.md`

**Interfaces:**
- Consumes: Task 1 config, Task 2 unit names, Task 3 direct mode, Task 4 redirect, Task 5 state helper, `loop_guard.sh`.
- Produces: command `/flutter-clean-arch:migrate [--checkpoint] [--resume] [feature ...]`.

- [ ] **Step 1:** Write `migrate-loop.md` from the spec: preflight (all prerequisite commands exist, config saved, clean tree, baseline); foundation once (`/audit`, `/pre-check`, `/route`, `/di`); per feature `/feature --migrate`, `/to-bloc`, `/kill-getx` leftovers, analyze vs baseline, re-audit, ask "Write and run an e2e test for <feature>?" (yes runs `/e2e <feature>`, no continues); blocked after two failed attempts or a human-decision `TODO`; stop conditions from the spec; final audit and report with blocked and declined lists.
- [ ] **Step 2:** Write `SKILL.md` (frontmatter name `clean-arch-migrate`, a description that triggers on "migrate the whole app / run the full migration") pointing to the reference and the migration-workflow gates; write `commands/migrate.md` with frontmatter (description, argument-hint, `allowed-tools: Bash, Read, Edit, Write, AskUserQuestion`) and the one upfront confirmation showing real counts.
- [ ] **Step 3:** Run `test_migrate_state.sh` again and `check_consistency.sh`; expect OK (the checker must now know the new skill and command, see Task 7).

### Task 7: Docs, workflow and checker

**Files:**
- Modify: `skills/clean-arch-overview/references/migration-workflow.md` (two paths interim vs direct; config file; "project conventions override"; the conductor), `scripts/check_consistency.sh` (add `migrate` and `clean-arch-migrate` to its lists; check `migrate_state.sh` parses and its test passes; check `conventions_scan.sh` and `migration_plan.sh` parse), `README.md` and `docs/commands.md` (ninth command, eleventh skill, counts), `.claude-plugin/plugin.json` (version `0.4.0`), changelog entry.

- [ ] **Step 1:** Update the checker first; run it and expect failures naming the missing README/docs entries.
- [ ] **Step 2:** Update docs and version until `bash scripts/check_consistency.sh` and `bash scripts/check_getx_coverage.sh` both print OK.
- [ ] **Step 3:** End-to-end dry run on Nology: `/audit` then `migrate_state.sh <nology> init <audit.json>`; expect 18 units in wave order and `next` equal to the plan's first unit. Delete the generated progress file afterwards.

---

## Self-review notes

- Spec coverage: full scope and config (Task 1), direct mode (3), blocked-and-continue and resume (5, 6), per-feature e2e question (6), stop conditions and baseline (6), dependency check on prerequisites (6 preflight), docs and checker (7). Scanner speed is out of scope here (tracked separately).
- Types: statuses `pending|in_progress|done|blocked`, e2e `done|declined|failed`, and file `progress.json` are used identically in Tasks 5 and 6.
- Task 2 precedes 3 and 4 because both use `resolve_target`.
