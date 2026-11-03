#!/usr/bin/env bash
# What has this project already decided? Finds the project's own conventions, which override the generic rules.
# Usage: conventions_scan.sh [project_root]
# Prints one JSON document on stdout. Read-only: writes nothing, no network.
#
# Sources: CLAUDE.md / AGENTS.md / similar agent docs, .claude/skills/*, .clean-arch/config.json, pubspec.yaml and the code.
# The "rules" are keyword heuristics over those docs: each comes with the line it was inferred from so a human can check it.
# The derived "migration" block (mode / scope / structure) uses .clean-arch/config.json when present, otherwise it is
# marked assumed:true and the /audit command asks the user and saves the answer.
#   mode       direct  = GetxController -> Cubit in one step (no ChangeNotifier in between)
#              interim = via ChangeNotifier + ListenableBuilder, then /to-bloc
#   scope      state   = migrate state management only; navigation and DI stay as the project has them
#              full    = remove GetX completely (state, routing, DI)
#   structure  true    = also move files into lib/features/<name>/
# Exit code 0 = ok, 2 = no lib/ directory.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "Cannot enter $ROOT" >&2; exit 2; }
[ -d lib ] || { echo "No lib/ directory found in $ROOT" >&2; exit 2; }
. "$SCRIPT_DIR/detect.sh"
detect_bases

jstr() { printf '%s' "$1" | tr -d '\000-\037' | sed -e 's/\\/\//g' -e 's/"/'"'"'/g' | cut -c1-200; }
pub() { [ -f pubspec.yaml ] && grep -qE "^[[:space:]]*$1:" pubspec.yaml && echo true || echo false; }
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t conv)"
trap 'rm -rf "$TMP"' EXIT

# ---- Agent docs and project skills ----
: > "$TMP/docs"
for f in CLAUDE.md AGENTS.md GEMINI.md CONVENTIONS.md .cursorrules .github/copilot-instructions.md; do [ -f "$f" ] && echo "$f" >> "$TMP/docs"; done
: > "$TMP/skills"; : > "$TMP/skillfiles"
for sf in .claude/skills/*/SKILL.md; do
  [ -f "$sf" ] || continue
  nm="$(sed -n 's/^name: *//p' "$sf" | head -n1 | tr -d '\r')"
  ds="$(sed -n 's/^description: *//p' "$sf" | head -n1 | tr -d '\r' | cut -c1-160)"
  printf '%s\t%s\t%s\n' "$nm" "$sf" "$ds" >> "$TMP/skills"; echo "$sf" >> "$TMP/skillfiles"
done
grep -iE "bloc|cubit|migrat" "$TMP/skills" > "$TMP/migskills" 2>/dev/null || : > "$TMP/migskills"
cat "$TMP/docs" "$TMP/skillfiles" > "$TMP/allfiles"

# ---- Rules inferred from the docs (heuristic; each carries its evidence line) ----
rule() { # <name> <ERE>  -> prints  name<TAB>true|false<TAB>evidence
  local ev=""
  [ -s "$TMP/allfiles" ] && ev="$(xargs grep -hiE "$2" < "$TMP/allfiles" 2>/dev/null | head -n1 | sed -E 's/^[[:space:]*>-]+//' | cut -c1-170)"
  if [ -n "$ev" ]; then printf '%s\ttrue\t%s\n' "$1" "$ev"; else printf '%s\tfalse\t\n' "$1"; fi
}
{
  rule change_notifier_forbidden "(do not|don't|never|avoid|no )[^.]*(ChangeNotifier|ValueNotifier)"
  rule provider_forbidden "(do not|don't|never|avoid)[^.]*(introduce|use|add)[^.]*\\bprovider\\b"
  rule keeps_getx_navigation "(navigation remains getx|keep getx (nav|navigat)|go_router[^.]*(not adopted|out of scope|rejects?|are \\*\\*not\\*\\*)|rejects go_router)"
  rule no_tests "(do not|don't|never)[^.]*(add|write)[^.]*tests|do-not-write-tests"
  rule no_commits "(no commits unless|never run .git commit|do not commit unless)"
  rule strangler_prs "(strangler|one pr per feature|each phase = its own pr|own pr, shippable)"
  rule deprecate_not_delete "(marked .@Deprecated.|mark.*@Deprecated|not deleted, until)"
} > "$TMP/rules"

# ---- The project's own Cubit base classes and their state variants ----
# One pass: how many classes extend each non-framework Cubit base?
custom="$(printf '%s' "$CUBIT_BASES" | tr '|' '\n' | grep -vxE 'Cubit|Bloc|HydratedCubit|HydratedBloc|ReplayCubit|ReplayBloc|BlocBase' | paste -sd'|' -)"
: > "$TMP/bases"
if [ -n "$custom" ]; then
  grep -rhoE --include='*.dart' "class +[A-Za-z0-9_]+( *<[^>{]*>)? +extends +($custom)( *<|[ {]|\$)" lib 2>/dev/null \
    | sed -E 's/.*extends +([A-Za-z0-9_]+).*/\1/' | sort | uniq -c | awk '{ print $2 "\t" $1 }' > "$TMP/base_counts"
  # a base class is one that several classes extend, or that is declared abstract (DataCubit, PaginatedCubit...)
  : > "$TMP/base_counts_kept"
  while IFS="$(printf '\t')" read -r nm n; do
    if [ "$n" -ge 2 ] || grep -rqE --include='*.dart' "abstract +(base +)?class +$nm( *<|[ {])" lib 2>/dev/null; then printf '%s\t%s\n' "$nm" "$n" >> "$TMP/base_counts_kept"; fi
  done < "$TMP/base_counts"
  while IFS="$(printf '\t')" read -r nm n; do
    f="$(grep -rlE --include='*.dart' "class +$nm( *<|[ {])" lib 2>/dev/null | head -n1)"
    printf '%s\t%s\t%s\n' "$nm" "$f" "$n" >> "$TMP/bases"
  done < "$TMP/base_counts_kept"
fi
sort -t"$(printf '\t')" -k3,3nr "$TMP/bases" -o "$TMP/bases"
state_variants="$(cut -f2 "$TMP/bases" | while IFS= read -r f; do d="$(dirname "$f")"; ls "$d"/*state*.dart 2>/dev/null; done | sort -u | xargs grep -hoE "(sealed |final |abstract )*class +[A-Za-z0-9_]*(Initial|Loading|LoadingMore|Success|Error|Failure|LoadMoreError)[A-Za-z0-9_]*" 2>/dev/null | sed -E 's/.*class +//' | sort -u | paste -sd, -)"

# ---- DI / navigation / forms facts ----
sl_calls="$(grep -rE --include='*.dart' '(^|[^A-Za-z0-9_])(sl|getIt|locator)<' lib 2>/dev/null | wc -l | tr -d ' ')"
getit_pkg="$(pub get_it)"
getx_nav="$(grep -rlE --include='*.dart' 'GetMaterialApp|GetPage[<(]|Get\.(toNamed|to|offNamed|offAll)' lib 2>/dev/null | wc -l | tr -d ' ')"
router_pkg=false; { [ "$(pub go_router)" = true ] || [ "$(pub auto_route)" = true ]; } && router_pkg=true
# a package X together with its X_getx sibling: the _getx one is the GetX flavour of the same library
getx_siblings="$(grep -oE "^[[:space:]]+[a-z0-9_]+_getx:" pubspec.yaml 2>/dev/null | tr -d ' :' | while IFS= read -r g; do b="${g%_getx}"; grep -qE "^[[:space:]]+$b:" pubspec.yaml && echo "$g -> $b"; done | paste -sd, -)"

# ---- Explicit decisions saved by /audit ----
cfg=.clean-arch/config.json; cfg_present=false; c_mode=""; c_scope=""; c_struct=""
if [ -f "$cfg" ]; then
  cfg_present=true
  c_mode="$(sed -nE 's/.*"mode" *: *"([a-z]+)".*/\1/p' "$cfg" | head -n1)"
  c_scope="$(sed -nE 's/.*"scope" *: *"([a-z]+)".*/\1/p' "$cfg" | head -n1)"
  c_struct="$(sed -nE 's/.*"structure" *: *(true|false).*/\1/p' "$cfg" | head -n1)"
fi
rv() { awk -F'\t' -v k="$1" '$1==k {print $2}' "$TMP/rules"; }
has_infra=false; [ -s "$TMP/bases" ] && has_infra=true
basis=""
badd() { basis="${basis:+$basis; }$1"; }

mode="$c_mode"; scope="$c_scope"; structure="$c_struct"; assumed=false
if [ -z "$mode" ]; then
  assumed=true
  if [ "$(rv change_notifier_forbidden)" = true ]; then mode=direct; badd "the project docs forbid ChangeNotifier/ValueNotifier"
  elif [ "$has_infra" = true ]; then mode=direct; badd "the project already has its own Cubit base classes"
  else mode=direct; badd "default: GetxController straight to Cubit (the ChangeNotifier interim form only on request)"; fi
fi
if [ -z "$scope" ]; then
  assumed=true
  if [ "$(rv keeps_getx_navigation)" = true ]; then scope=state; badd "the project docs keep GetX navigation"
  elif [ "$has_infra" = true ] && { [ "$sl_calls" -gt 0 ] || [ "$getit_pkg" = true ]; }; then scope=state; badd "BLoC infrastructure and GetIt are already in place"
  else scope=full; badd "no decision found: full GetX removal"; fi
fi
if [ -z "$structure" ]; then
  assumed=true
  if [ "$scope" = state ]; then structure=false; badd "state-only scope: files stay where they are"; else structure=true; fi
fi

# ---- Shell-friendly output for the other scripts:  eval "$(conventions_scan.sh <root> --env)" ----
if [ "${2:-}" = "--env" ]; then
  q() { printf '%s' "$1" | tr -d "'" ; }
  printf "CONV_MODE='%s'\nCONV_SCOPE='%s'\nCONV_STRUCTURE='%s'\nCONV_ASSUMED='%s'\n" "$mode" "$scope" "$structure" "$assumed"
  printf "CONV_NO_TESTS='%s'\nCONV_NO_COMMITS='%s'\nCONV_CN_FORBIDDEN='%s'\nCONV_HAS_INFRA='%s'\n" "$(rv no_tests)" "$(rv no_commits)" "$(rv change_notifier_forbidden)" "$has_infra"
  printf "CONV_GETX_SIBLINGS='%s'\nCONV_BASIS='%s'\nCONV_BASES='%s'\n" "$(q "$getx_siblings")" "$(q "$basis")" "$(cut -f1 "$TMP/bases" | paste -sd, -)"
  exit 0
fi

# ---- JSON ----
rules_json="$(awk -F'\t' 'function q(s){gsub(/\\/,"/",s);gsub(/"/,"\047",s);return s} { printf "%s\"%s\":{\"value\":%s,\"evidence\":\"%s\"}", (NR>1?",":""), $1, $2, q($3) }' "$TMP/rules")"
docs_json="$(awk '{printf "%s\"%s\"", (NR>1?",":""), $0}' "$TMP/docs")"
skills_json="$(awk -F'\t' 'function q(s){gsub(/\\/,"/",s);gsub(/"/,"\047",s);return s} { printf "%s{\"name\":\"%s\",\"file\":\"%s\",\"description\":\"%s\"}", (NR>1?",":""), q($1), q($2), q($3) }' "$TMP/skills")"
mig_json="$(awk -F'\t' 'function q(s){gsub(/\\/,"/",s);gsub(/"/,"\047",s);return s} { printf "%s{\"name\":\"%s\",\"file\":\"%s\"}", (NR>1?",":""), q($1), q($2) }' "$TMP/migskills")"
bases_json="$(awk -F'\t' 'function q(s){gsub(/\\/,"/",s);gsub(/"/,"\047",s);return s} { printf "%s{\"name\":\"%s\",\"file\":\"%s\",\"subclasses\":%d}", (NR>1?",":""), q($1), q($2), $3 }' "$TMP/bases")"
variants_json="$(printf '%s' "$state_variants" | tr ',' '\n' | awk 'NF {printf "%s\"%s\"", (n++?",":""), $0}')"

cat <<JSON
{
  "project": "$(jstr "$(basename "$(pwd)")")",
  "agent_docs": [${docs_json}],
  "project_skills": [${skills_json}],
  "migration_skills": [${mig_json}],
  "rules": {${rules_json}},
  "cubit_base_classes": [${bases_json}],
  "state_variants": [${variants_json}],
  "facts": {"sl_or_getit_calls": ${sl_calls:-0}, "get_it_package": $getit_pkg, "getx_navigation_files": ${getx_nav:-0}, "router_package": $router_pkg, "getx_flavour_packages": "$(jstr "$getx_siblings")"},
  "config": {"present": $cfg_present, "file": ".clean-arch/config.json"},
  "migration": {"mode": "$mode", "scope": "$scope", "structure": $structure, "assumed": $assumed, "basis": "$(jstr "$basis")"}
}
JSON
