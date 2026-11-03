---
name: clean-arch-migrate
description: Use when the user wants to run the whole GetX to Clean Architecture + Bloc migration of an app, feature by feature, in one go ("migrate the whole app", "run the full migration", "keep going until GetX is gone"). Conducts the other migration commands in order, asks about an e2e test after each feature, saves progress so it can resume, and stops on mechanical conditions.
---

# Running the whole migration

This skill adds no new way of editing code. It sequences the existing commands (`/audit`, `/pre-check`, `/route`, `/di`, `/feature --migrate`, `/to-bloc`, `/kill-getx`, `/e2e`) over the audit's migration plan, one feature at a time, and keeps going until the project is clean or a stop condition applies. The started command is `/flutter-clean-arch:migrate`.

Follow `references/migrate-loop.md` for the steps, prompts and stop conditions. The shared gates, `TODO(<command>)` tags and conventions of every command are in `../clean-arch-overview/references/migration-workflow.md`; they all still apply inside the loop.

## Rules

- **The plan decides the order.** Features come from `migration_plan.waves` (quick wins first, large shared units last). Do not reorder without telling the user.
- **Project conventions win** over generic plugin rules (base classes, state names, DI, tests, commits). Say which rules you override.
- **One confirmation up front**, with real counts and the stop conditions. After that, ask only the per-feature e2e question and anything a command itself must ask (for example forms, deleting old classes).
- **After each feature**: analyzer no worse than the baseline, a fresh audit, then ask whether to write and run an e2e test for that feature. Yes: `/e2e <feature>`. No: next feature. Declining never affects other features.
- **A feature that fails twice, or needs a human decision, is `blocked`**: skip it, keep going, list it at the end.
- **Resumable**: progress lives in `.clean-arch/progress.json`, managed only by `scripts/migrate_state.sh`.
- **Done** means GetX usages are zero, audit status `compliant`, analyzer errors at or below the baseline, existing tests passing. Report anything short of that honestly.
- Never run `flutter pub add`/`remove`, never push, change git state only with the user's opt-in `--checkpoint`, never edit files marked `DEPRECATED: migrated by /feature --migrate`, never delete old classes without asking.

## Checklist

- [ ] Prerequisites checked (commands present, `.clean-arch/config.json` saved, clean tree, baseline recorded)
- [ ] One confirmation given
- [ ] Foundation done once (`/route`, `/di` when the scope is `full`)
- [ ] Each feature migrated, verified, e2e question asked
- [ ] Final audit and report (done, blocked, declined e2e)
