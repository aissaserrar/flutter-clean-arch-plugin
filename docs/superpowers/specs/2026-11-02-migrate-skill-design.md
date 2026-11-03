# Design: `clean-arch-migrate` skill and `/migrate` command

## Intent
The plugin exists to move Nology from its current architecture and GetX to Clean Architecture + BLoC. Today a person runs eight commands by hand in the right order. This adds one conductor that drives them feature by feature until the project is clean, so the migration needs few interruptions.

## Goals
- One command, `/flutter-clean-arch:migrate`, backed by a skill `clean-arch-migrate`, that runs the whole migration using the existing commands only.
- Feature by feature, in the audit plan's wave order (quick wins first, large shared units last).
- After each feature, ask whether to write and run an e2e test for it. Yes: run `/e2e` for that feature. No: continue. Declining never affects later features.
- Done means: GetX usages are zero, audit status is `compliant`, `flutter analyze` is no worse than the baseline, existing tests pass.
- Resumable: state is saved in `.clean-arch/progress.json`.

## Non-goals / anti-goals
- No new scanners, no new ways of editing code; it only sequences `/audit`, `/pre-check`, `/route`, `/di`, `/feature`, `/to-bloc`, `/kill-getx`, `/e2e`.
- Never weakens a gate: clean git tree, analyzer baseline, no `flutter pub add/remove`, no state-changing git except opt-in `--checkpoint`, never edits files marked DEPRECATED, never pushes.
- Not an unbounded loop: it stops on a mechanical condition (below), never "until it feels done".

## Decisions made with the user
- Full scope for Nology: `scope=full`, `structure=true`. This overrides the "state only, keep GetX navigation" assumption derived from Nology's CLAUDE.md; the run states this and saves it to `.clean-arch/config.json`.
- Per feature the e2e question is asked once, after that feature is migrated and verified.

## Decisions made by me (mark for review)
- Direct conversion (GetxController to Cubit, no ChangeNotifier) because Nology forbids ChangeNotifier; uses the project's base classes and state variants. This depends on `/to-bloc` direct mode, which is still pending (see "Dependencies").
- A feature that fails twice or needs a human decision is marked `blocked`, skipped, and listed at the end; the run continues. Re-running `/migrate` retries blocked features only if asked.
- Order: foundation once (audit, pre-check, baseline, `/route`, `/di`), then per feature: `/feature --migrate`, `/to-bloc`, `/kill-getx` for leftovers, analyze vs baseline, re-audit, e2e question. Final audit at the end.
- One upfront confirmation showing real file counts, the feature list, and the stop conditions. Per-batch limits reuse the shared batch rules (about 10 files, stop if over 15).

## Stop conditions (whole run)
Analyzer errors above baseline after a batch; a file needing more than two fix attempts (feature becomes `blocked`); a batch touching files outside the plan; the tree changed by something other than the run; a gate no longer holds; the user says stop; everything done. `loop_guard.sh` is reused where it applies.

## Progress file
`.clean-arch/progress.json`: features with status `pending|in_progress|done|blocked`, e2e answer (`done|declined|failed`), baseline error count, last audit file, timestamps. Written after each step, read on start to resume.

## Dependencies
Full-scope direct migration needs the pending work: `/to-bloc` direct mode and unit-name targets, `/kill-getx` redirect when ChangeNotifier is forbidden, config question in `/audit`. The skill must check these exist and stop with a clear message if a command cannot do a step.

## Left to the builder
Exact wording of prompts, JSON field names beyond those above, and how the skill is split between `SKILL.md` and `references/`. Follow existing plugin patterns: short `SKILL.md`, details in `references/`, command file with frontmatter, consistency checker and README updated.
