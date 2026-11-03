#!/usr/bin/env bash
# Safety dry-run data for a refactor: git state and impact metrics for the target files.
# Usage: pre_check.sh [project_root] [target ...]
#   target = a feature name (lib/features/<name>), a path (file or dir), or empty for all of lib/.
# Prints one JSON document on stdout. Read-only: no writes, no network, does not run flutter.
# Exit code 0 = data produced, 2 = no lib/ directory.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT="${1:-.}"; [ $# -gt 0 ] && shift
cd "$ROOT" 2>/dev/null || { echo "Cannot enter $ROOT" >&2; exit 2; }
[ -d lib ] || { echo "No lib/ directory found in $ROOT" >&2; exit 2; }
. "$SCRIPT_DIR/../../clean-arch-overview/scripts/detect.sh"
detect_bases

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t precheck)"
trap 'rm -rf "$TMP"' EXIT

jstr() { printf '%s' "$1" | tr -d '\000-\037' | sed -e 's/\\/\//g' -e 's/"/'"'"'/g'; }
GEN=(! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.gr.dart' ! -name '*.config.dart' ! -name 'app_localizations*.dart')

# ---- Resolve targets ----
: > "$TMP/targets"; : > "$TMP/unresolved"
if [ $# -eq 0 ]; then set -- lib; fi
for t in "$@"; do
  case "$t" in */*|*.dart) ;; *) if u="$(resolve_target "$t")"; then printf '%s\n' "$u" >> "$TMP/targets"; continue; fi ;; esac
  if [ -d "lib/features/$t" ]; then p="lib/features/$t"
  elif [ -e "$t" ]; then p="$t"
  elif [ -e "lib/$t" ]; then p="lib/$t"
  else echo "$t" >> "$TMP/unresolved"; continue; fi
  if [ -d "$p" ]; then find "$p" -name '*.dart' "${GEN[@]}" 2>/dev/null >> "$TMP/targets"
  else printf '%s\n' "$p" >> "$TMP/targets"; fi
done
sort -u "$TMP/targets" -o "$TMP/targets"
n_targets="$(wc -l < "$TMP/targets" | tr -d ' ')"

# ---- Git ----
git_repo=false; branch=""; staged=0; unstaged=0; untracked=0; ahead=0; behind=0; last_commit=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git_repo=true
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  staged="$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')"
  unstaged="$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')"
  untracked="$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')"
  last_commit="$(git log -1 --format='%h %s' 2>/dev/null)"
  if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    read -r behind ahead < <(git rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)
  fi
fi
git status --porcelain 2>/dev/null | head -n 30 | sed 's/^...//' > "$TMP/dirty"
dirty_in_targets=0
if [ -s "$TMP/dirty" ] && [ -s "$TMP/targets" ]; then
  dirty_in_targets="$(grep -cFxf "$TMP/targets" "$TMP/dirty" || true)"
fi

# ---- Impact metrics ----
loc=0; [ -s "$TMP/targets" ] && loc="$(xargs cat < "$TMP/targets" 2>/dev/null | wc -l | tr -d ' ')"

NB='(^|[^A-Za-z0-9_])'
P_GETX="$RE_GX_PREFILTER|$RE_GETX"
getx_hits=0; bloc_files=0; stateful=0
if [ -s "$TMP/targets" ]; then
  getx_hits="$(xargs grep -hE "$P_GETX" < "$TMP/targets" 2>/dev/null | wc -l | tr -d ' ')"
  bloc_files="$(xargs grep -lE "$RE_CUBIT" < "$TMP/targets" 2>/dev/null | wc -l | tr -d ' ')"
  stateful="$(xargs grep -hE "extends +StatefulWidget" < "$TMP/targets" 2>/dev/null | wc -l | tr -d ' ')"
fi

# dependents: files outside the targets that import a target (package path exact; relative imports by file name, approximate)
: > "$TMP/pairs"
if [ -s "$TMP/targets" ]; then
  find lib test -name '*.dart' 2>/dev/null | sort > "$TMP/all"
  comm -23 "$TMP/all" "$TMP/targets" > "$TMP/others"
  while IFS= read -r f; do
    rel="${f#lib/}"; base="$(basename "$f")"
    xargs grep -lE "import +['\"](package:[^/]+/${rel}|[^'\"]*/${base}|${base})['\"]" < "$TMP/others" 2>/dev/null | sed "s#^#$f\t#"
  done < "$TMP/targets" > "$TMP/pairs"
fi
cut -f2 "$TMP/pairs" | sort -u > "$TMP/deps_all"
grep -v '^test/' "$TMP/deps_all" > "$TMP/deps" || true
grep '^test/' "$TMP/deps_all" > "$TMP/deps_tests" || true
n_deps="$(wc -l < "$TMP/deps" | tr -d ' ')"
n_dep_tests="$(wc -l < "$TMP/deps_tests" | tr -d ' ')"

# tests: a lib target is covered if test/<rel>_test.dart exists OR some test file imports it
tests_covered=0; tests_uncovered=0
: > "$TMP/missing"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in lib/*) ;; *) continue ;; esac
  rel="${f#lib/}"; t="test/${rel%.dart}_test.dart"
  if [ -f "$t" ] || awk -F'\t' -v f="$f" '$1==f && $2 ~ /^test\// {found=1} END{exit !found}' "$TMP/pairs"; then
    tests_covered=$((tests_covered + 1))
  else
    tests_uncovered=$((tests_uncovered + 1)); echo "$f" >> "$TMP/missing"
  fi
done < "$TMP/targets"
feature_tests=0
for t in "$@"; do [ -d "test/features/$t" ] && feature_tests="$(find "test/features/$t" -name '*_test.dart' | wc -l | tr -d ' ')"; done

# ---- Output ----
arr() { # file -> JSON string array (max 25)
  head -n 25 "$1" | awk 'BEGIN{printf "["} {g=$0; gsub(/\\/,"/",g); gsub(/"/,"\047",g); printf "%s\"%s\"", (NR>1?",":""), g} END{printf "]"}'
}

cat <<JSON
{
  "project": "$(jstr "$(basename "$(pwd)")")",
  "targets": {"requested": "$(jstr "$*")", "files": $n_targets, "loc": $loc, "unresolved": $(arr "$TMP/unresolved"), "list": $(arr "$TMP/targets")},
  "git": {"is_repo": $git_repo, "branch": "$(jstr "$branch")", "last_commit": "$(jstr "$last_commit")", "staged": $staged, "unstaged": $unstaged, "untracked": $untracked, "ahead": ${ahead:-0}, "behind": ${behind:-0}, "dirty_in_targets": $dirty_in_targets, "dirty_files": $(arr "$TMP/dirty")},
  "impact": {"getx_hits": $getx_hits, "bloc_files": $bloc_files, "stateful_widgets": $stateful, "dependents": $n_deps, "dependent_files": $(arr "$TMP/deps"), "dependent_test_files": $n_dep_tests, "dependents_note": "relative imports matched by file name (approximate)"},
  "tests": {"covered": $tests_covered, "uncovered": $tests_uncovered, "feature_test_files": $feature_tests, "uncovered_files": $(arr "$TMP/missing"), "note": "covered = mirrored test file exists or a test imports the file; says nothing about test quality"}
}
JSON
