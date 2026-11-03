---
description: Run the whole GetX to Clean Architecture + Bloc migration feature by feature, following the audit plan; asks for an e2e test after each feature, saves progress so it can resume, and stops on analyzer regressions or decisions that need a human.
argument-hint: "[--checkpoint] [--resume] [feature ...]"
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
---

# /migrate

Migrate the Flutter project in the current directory from GetX to Clean Architecture + Bloc, one feature at a time. With feature names in `$ARGUMENTS` only those are migrated; otherwise every feature in the plan. `--resume` continues from `.clean-arch/progress.json`; it is also the default when that file exists. `--checkpoint` is passed through to the commands that support it.

Read `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-migrate/SKILL.md` and follow `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-migrate/references/migrate-loop.md` step by step. The shared gates and conventions of every command are in `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/references/migration-workflow.md`.

## Steps

1. Preflight, then the one confirmation (loop reference, sections 1 and 2).
2. Foundation once when `scope` is `full` (section 3).
3. Each feature: migrate, verify, ask about an e2e test, record progress (section 4).
4. Final audit and honest report (section 6).

## Rules

- Never edit before the single confirmation. After it, only ask the per-feature e2e question and what the individual commands must ask.
- Use the other commands exactly as documented; do not invent a faster path that skips their gates.
- Never run `flutter pub add`/`remove`, never push, change git state only with `--checkpoint` after consent, never edit `DEPRECATED: migrated by /feature --migrate` files, never delete old classes without asking.
- Report real numbers. If the project is not `compliant` at the end, say what remains.
