#!/usr/bin/env bash
# Maintainer check: are the commands and the skills of this plugin consistent with each other?
# Usage: bash scripts/check_consistency.sh        (run from anywhere; it finds the plugin root itself)
# Read-only. Exit code 0 = consistent, 1 = problems found (each one printed).
#
# Checks:
#   1  every command has description, argument-hint and allowed-tools in its frontmatter
#   2  every ${CLAUDE_PLUGIN_ROOT}/... path used by a command or skill exists
#   3  every file listed under "Bundled files" in a SKILL.md exists
#   4  every script parses (bash -n) and is executable
#   5  every command that edits files points to references/migration-workflow.md
#   6  no stale wording ("not available yet", "may not exist", "if available")
#   7  every command and every skill appears in the README tables
#   8  every `/command` mentioned in commands, skills and README exists
#   9  every SKILL.md `name` matches its folder
#  10  the order of next steps in commands matches migration-workflow.md
#  11  the batch loop exists only in /kill-getx and /to-bloc, is defined once, and keeps its git exception explicit
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
problems=0
bad() { echo "PROBLEM: $*"; problems=$((problems + 1)); }

COMMANDS="audit pre-check feature route di kill-getx to-bloc e2e"
MUTATING="feature route di kill-getx to-bloc e2e"

# 1. frontmatter
for f in commands/*.md; do
  fm="$(awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} NR>1 {print}' "$f")"
  [ -n "$fm" ] || { bad "$f: no frontmatter"; continue; }
  for k in description argument-hint allowed-tools; do
    printf '%s\n' "$fm" | grep -qE "^$k:" || bad "$f: frontmatter lacks '$k'"
  done
done
for c in $COMMANDS; do [ -f "commands/$c.md" ] || bad "commands/$c.md is missing"; done

# 2. ${CLAUDE_PLUGIN_ROOT} paths
grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' commands skills README.md 2>/dev/null | sed -E 's/[.,;:]+$//' | sort -u | while IFS= read -r ref; do
  p="${ref#\$\{CLAUDE_PLUGIN_ROOT\}/}"
  [ -e "$p" ] || echo "PROBLEM: referenced path does not exist: $p"
done > /tmp/cc_paths.$$
if [ -s /tmp/cc_paths.$$ ]; then cat /tmp/cc_paths.$$; problems=$((problems + $(wc -l < /tmp/cc_paths.$$))); fi
rm -f /tmp/cc_paths.$$

# 3. Bundled files in SKILL.md
for skill in skills/*/; do
  s="$skill/SKILL.md"; [ -f "$s" ] || { bad "$skill has no SKILL.md"; continue; }
  sed -n '/^## Bundled files/,$p' "$s" | grep -oE '`(\.\./[a-z-]+/)?(references|scripts|templates)/[A-Za-z0-9_./*-]+' | tr -d '`' | sed -E 's/[.,;:]+$//' | sort -u | while IFS= read -r rel; do
    case "$rel" in *'*'*) continue ;; esac
    [ -e "$skill/$rel" ] || echo "PROBLEM: $s lists a missing file: $rel"
  done
done > /tmp/cc_bundled.$$
if [ -s /tmp/cc_bundled.$$ ]; then cat /tmp/cc_bundled.$$; problems=$((problems + $(wc -l < /tmp/cc_bundled.$$))); fi
rm -f /tmp/cc_bundled.$$

# 4. scripts
for sh in skills/*/scripts/*.sh scripts/*.sh; do
  [ -f "$sh" ] || continue
  bash -n "$sh" 2>/dev/null || bad "$sh: syntax error"
  [ -x "$sh" ] || bad "$sh: not executable"
done

# 5. migration-workflow pointer
for c in $MUTATING; do
  grep -q "migration-workflow.md" "commands/$c.md" 2>/dev/null || bad "commands/$c.md does not point to references/migration-workflow.md"
done
[ -f skills/clean-arch-overview/references/migration-workflow.md ] || bad "migration-workflow.md is missing"

# 6. stale wording
grep -inE "not available yet|may not exist|if available|do not invent ones|exist in this plugin" commands/*.md skills/*/references/*.md 2>/dev/null | while IFS= read -r l; do echo "PROBLEM: stale wording: $l"; done > /tmp/cc_stale.$$
if [ -s /tmp/cc_stale.$$ ]; then cat /tmp/cc_stale.$$; problems=$((problems + $(wc -l < /tmp/cc_stale.$$))); fi
rm -f /tmp/cc_stale.$$

# 7. README coverage
for c in $COMMANDS; do grep -q "/flutter-clean-arch:$c" README.md || bad "README has no row for /$c"; done
for skill in skills/*/; do n="$(basename "$skill")"; grep -q "\`$n\`" README.md || bad "README does not mention skill $n"; done

# 8. unknown /commands
KNOWN="audit pre-check feature route di kill-getx to-bloc e2e plugin reload-plugins"
grep -rhoE '(^|[ (|])`/[a-z][a-z0-9-]*[ `:]' commands skills README.md docs 2>/dev/null | sed -E 's/^[ (|]?`\///; s/[ `:]$//' | sort -u | while IFS= read -r w; do
  [ "$w" = "flutter-clean-arch" ] && continue     # namespace prefix: the command after the colon is checked in 7
  case " $KNOWN " in *" $w "*) ;; *) echo "PROBLEM: unknown command mentioned: /$w" ;; esac
done > /tmp/cc_cmds.$$
if [ -s /tmp/cc_cmds.$$ ]; then cat /tmp/cc_cmds.$$; problems=$((problems + $(wc -l < /tmp/cc_cmds.$$))); fi
rm -f /tmp/cc_cmds.$$

# 9. skill names
for skill in skills/*/; do
  n="$(basename "$skill")"; fn="$(sed -n 's/^name: *//p' "$skill/SKILL.md" | head -n1 | tr -d '\r')"
  [ "$fn" = "$n" ] || bad "$skill/SKILL.md: name '$fn' does not match the folder"
done

# 10. next-step order: the order table in migration-workflow.md is the reference
order="$(awk -F'|' '/^\| [0-9]b? \|/ {gsub(/[ `]/,"",$3); print $3}' skills/clean-arch-overview/references/migration-workflow.md | sed -E 's#<[^>]*>##g; s#--migrate##; s#\(.*##' | tr '\n' ' ')"
for want in "/audit" "/pre-check" "/feature" "/route" "/di" "/kill-getx" "/to-bloc"; do
  case "$order" in *"$want"*) ;; *) bad "migration-workflow.md order table lacks $want" ;; esac
done
pos() { printf '%s' "$order" | awk -v w="$1" '{ for (i = 1; i <= NF; i++) if ($i == w) { print i; exit } }'; }
for pair in "/route:/di" "/di:/kill-getx" "/kill-getx:/to-bloc" "/feature:/route"; do
  a="${pair%%:*}"; b="${pair##*:}"; pa="$(pos "$a")"; pb="$(pos "$b")"
  [ -n "$pa" ] && [ -n "$pb" ] && [ "$pa" -lt "$pb" ] || bad "order table: $a should come before $b"
done
# routing gate and its target must stay aligned
grep -q "run \`/route\` first" commands/kill-getx.md || bad "kill-getx.md lost its 'run /route first' gate"
grep -q "kill-getx" commands/to-bloc.md || bad "to-bloc.md does not send GetX controllers to /kill-getx"

# 11. batch loop: only /kill-getx and /to-bloc, defined once in migration-workflow.md
grep -q "^## Batch loop" skills/clean-arch-overview/references/migration-workflow.md 2>/dev/null || bad "migration-workflow.md has no 'Batch loop' section"
grep -q "loop_guard.sh" skills/clean-arch-overview/references/migration-workflow.md 2>/dev/null || bad "migration-workflow.md does not use loop_guard.sh"
for c in $COMMANDS; do
  hint="$(sed -n 's/^argument-hint: *//p' "commands/$c.md" | head -n1)"
  case "$c" in
    kill-getx|to-bloc)
      case "$hint" in *--batches*--checkpoint*) ;; *) bad "commands/$c.md: argument-hint must offer --batches N and --checkpoint" ;; esac
      grep -q "Batch loop" "commands/$c.md" || bad "commands/$c.md does not point to the Batch loop section"
      grep -q -- "--checkpoint" "commands/$c.md" && grep -q "only exception is the \`--checkpoint\`" "commands/$c.md" || bad "commands/$c.md: its git rule must name the --checkpoint exception"
      ;;
    *) case "$hint" in *--batches*|*--checkpoint*) bad "commands/$c.md: only /kill-getx and /to-bloc have a batch loop" ;; esac ;;
  esac
done
grep -q "audit.sh" commands/audit.md && grep -q 'PREV' commands/audit.md || bad "audit.md does not pass the previous audit for the delta"
grep -q "next_steps" commands/audit.md || bad "audit.md does not print next_steps in the terminal summary"
grep -q "d.next_steps" commands/templates/audit-report.html || bad "the report template does not render next_steps"
grep -q "d.structure" commands/templates/audit-report.html || bad "the report template does not draw the architecture illustration"
grep -q "<details" commands/templates/audit-report.html && grep -q "data-act" commands/templates/audit-report.html || bad "the report trees are not expandable (details / Expand all / Collapse all)"
# every command the audit can recommend must exist
for c in $(grep -oE 'add_step [a-z-]+ "/[a-z-]+' skills/clean-arch-overview/scripts/audit.sh | sed -E 's/.*"\///' | sort -u); do [ -f "commands/$c.md" ] || bad "audit.sh recommends /$c but commands/$c.md does not exist"; done

if [ "$problems" -eq 0 ]; then echo "OK: commands and skills are consistent"; exit 0; fi
echo; echo "$problems problem(s) found."; exit 1
