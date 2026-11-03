---
description: Audit a Flutter project for Clean Architecture compliance and GetX leakage; writes an HTML report and opens it in the browser
argument-hint: "[path]"
allowed-tools: Bash, Read, AskUserQuestion
---

# /audit

Audit the Flutter project in the current directory (or the path passed as `$ARGUMENTS`). The audit is read-only except for generated files under `.clean-arch/`: `audit-YYYY-MM-DD-HHMM.html`, `audit-YYYY-MM-DD-HHMM.json` (kept every run), and `feature-map.suggested.yaml` (overwritten each run — discovered candidate features from the legacy layout).

## Steps

1. **Locate the project root.** Use `$ARGUMENTS` if given, otherwise the current directory. It must contain `pubspec.yaml` and `lib/`. If not, say so and stop.

2. **Run the scanner** and keep the JSON in the report folder:

   ```bash
   ROOT="<project root>"; STAMP="$(date +%Y-%m-%d-%H%M)"
   echo "$STAMP"   # note this value: shell variables do not persist between commands, so reuse the literal value below
   PREV="$(ls -1 "$ROOT"/.clean-arch/audit-*.json 2>/dev/null | sort | tail -n 1)"   # newest earlier audit, if any
   mkdir -p "$ROOT/.clean-arch"
   bash "${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/scripts/audit.sh" "$ROOT" ${PREV:+"$PREV"} > "$ROOT/.clean-arch/audit-$STAMP.json"
   ```

   Exit code `2` means there is no `lib/` directory. Report that and stop.

3. **Build the HTML report** from the bundled template. Escape `</` so file names cannot close the script tag:

   ```bash
   STAMP="<same value as step 2>"   # do NOT call date again: a new minute would point to a different file
   ROOT="<project root>"
   sed 's#</#<\\/#g' "$ROOT/.clean-arch/audit-$STAMP.json" > "$ROOT/.clean-arch/audit-$STAMP.data.json"
   awk -v f="$ROOT/.clean-arch/audit-$STAMP.data.json" '/^__AUDIT_DATA__$/ { while ((getline l < f) > 0) print l; next } { print }' \
     "${CLAUDE_PLUGIN_ROOT}/commands/templates/audit-report.html" > "$ROOT/.clean-arch/audit-$STAMP.html"
   rm "$ROOT/.clean-arch/audit-$STAMP.data.json"
   ```

4. **Open it** in the default browser. Use the first that exists, and if none works print the full path instead:

   ```bash
   STAMP="<same value as step 2>"; ROOT="<project root>"
   open "$ROOT/.clean-arch/audit-$STAMP.html" 2>/dev/null \
     || xdg-open "$ROOT/.clean-arch/audit-$STAMP.html" 2>/dev/null \
     || cmd.exe /c start "" "$(wslpath -w "$ROOT/.clean-arch/audit-$STAMP.html" 2>/dev/null)" 2>/dev/null
   ```

5. **Print a short terminal summary** from `audit-$STAMP.json` (read it, do not re-scan). Lead with **Distance to Clean Architecture** (`template` in JSON): `distance`, `score`/100, blockers/majors/minors, and the first 5–8 `gaps` as `severity · area — label`. Then secondary signals briefly: Dart file count, real features vs `screens/` Dart, Cubit/Bloc count, GetX total. Then **suggested features**: shape counts + top 5–8 candidates; note `feature-map.suggested.yaml`. Then **next steps** (first four + remaining count). If `delta` is not null, prefer score/blocker changes. State plainly that **compliant means close to Clean Architecture**, not “GetX is gone.”

   End with the report path.

6. **Prompt to migrate.** If `migration_prompt` is `true` in the JSON, ask the user with AskUserQuestion, using this exact question text and Yes (default) / No options:

   > Legacy state management detected with no BLoC architecture found. Would you like to migrate this project to BLoC? (Y/n)

   - **Yes:** summarise the migration plan using the `clean-arch-*` skills (feature shapes from `clean-arch-overview`, state from `clean-arch-presentation`, routing/DI from `clean-arch-di-routing`). Then show the recommended order from `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/references/migration-workflow.md` (`/pre-check`, `/feature <name> --migrate`, `/route`, `/di`, `/kill-getx`, `/to-bloc`, tests and `/e2e`) and suggest starting with `/pre-check` on the first feature. Do not start any of them and do not edit any project file in this command.
   - **No:** stop.

7. **Confirm the migration settings once.** Read `migration_plan.settings` in the JSON. If `assumed` is `true` and BLoC infrastructure exists (`migration_plan` is not null), ask ONE `AskUserQuestion` with two questions: *scope* ("Migrate state management only (keep GetX navigation/DI), or remove GetX completely?") and *mode* ("Convert GetX controllers directly to Cubits (recommended), or go through a plain ChangeNotifier first (rewrites every controller twice)?"). Pre-select the plan's current values and say which project file each assumption came from (`settings.basis`). Then write `$ROOT/.clean-arch/config.json` with exactly `{"mode":"direct|interim","scope":"state|full","structure":true|false}` (`structure` is `true` when scope is `full`, otherwise keep the plan's value), re-run steps 2 to 4 so the report reflects the choice, and print the plan summary: number of waves and units, the first unit, and that the migration runs feature by feature (`/migrate` runs the whole plan). If `assumed` is `false`, skip this step. Writing `.clean-arch/config.json` is the only file this step changes.

8. **Mention** that `.clean-arch/` can be added to the project's `.gitignore`. Do not edit `.gitignore` unless asked.

## Rules

- Never modify files under `lib/` or `test/`. Generated under `.clean-arch/` only: audit HTML/JSON, `feature-map.suggested.yaml`, and (after step 7) `config.json`.
- Do not recompute numbers by hand; the script output is the source of truth.
- Report real results. If the script or the browser step fails, show the error.
