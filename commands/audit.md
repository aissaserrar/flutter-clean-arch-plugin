---
description: Audit a Flutter project for Clean Architecture compliance and GetX leakage; writes an HTML report and opens it in the browser
argument-hint: "[path]"
allowed-tools: Bash, Read, AskUserQuestion
---

# /audit

Audit the Flutter project in the current directory (or the path passed as `$ARGUMENTS`). The audit is read-only except for two generated files per run, `.clean-arch/audit-YYYY-MM-DD-HHMM.html` and `.clean-arch/audit-YYYY-MM-DD-HHMM.json` (local time). Every run is kept; nothing is overwritten.

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

5. **Print a short terminal summary** from `audit-$STAMP.json` (read it, do not re-scan): status, Dart file count, per-layer counts, GetX usage total with the top three files, violations count with the top three, Cubit/Bloc file count, features without a `test/features/<name>` folder. Then add the **next steps** straight from `next_steps` in the JSON (the report shows the same list under its architecture illustration): the first four as `order. command - title`, and the number of remaining ones. Mention `suggested_features` (legacy groups that could become features) when there are any, and that the report has a Today / Target illustration of the folder structure. Do not invent steps that are not in `next_steps`. If `delta` is not null, add the progress since the previous audit: the status change and every metric whose `change` is non-zero (`getx_usages 212 -> 187 (-25)`); say a `null` change means the older audit did not record that metric. If `delta` is null, say this is the first audit. Say that `coverage.not_checked` was not audited, so "compliant" means the listed checks passed, not a full review. State the compliance status plainly:
   - `compliant`: no GetX, no errors or warnings, features structure present, BLoC/Cubit in use.
   - `compliant_with_warnings`: as above but with style warnings only (`part`/`part of`, widgets in `core/`). Errors are import-rule and GetX findings.
   - `needs_migration`: legacy state management (GetX, or StatefulWidget with no BLoC) and no BLoC found.
   - `non_compliant`: anything else (violations, leftover GetX alongside BLoC, or no `lib/features/`).

   End with the report path.

6. **Prompt to migrate.** If `migration_prompt` is `true` in the JSON, ask the user with AskUserQuestion, using this exact question text and Yes (default) / No options:

   > Legacy state management detected with no BLoC architecture found. Would you like to migrate this project to BLoC? (Y/n)

   - **Yes:** summarise the migration plan using the `clean-arch-*` skills (feature shapes from `clean-arch-overview`, state from `clean-arch-presentation`, routing/DI from `clean-arch-di-routing`). Then show the recommended order from `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/references/migration-workflow.md` (`/pre-check`, `/feature <name> --migrate`, `/route`, `/di`, `/kill-getx`, `/to-bloc`, tests and `/e2e`) and suggest starting with `/pre-check` on the first feature. Do not start any of them and do not edit any project file in this command.
   - **No:** stop.

7. **Mention** that `.clean-arch/` can be added to the project's `.gitignore`. Do not edit `.gitignore` unless asked.

## Rules

- Never modify files under `lib/` or `test/`.
- Do not recompute numbers by hand; the script output is the source of truth.
- Report real results. If the script or the browser step fails, show the error.
