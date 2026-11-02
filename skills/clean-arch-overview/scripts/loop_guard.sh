#!/usr/bin/env bash
# Mechanical stop conditions for the batch loop (migration-workflow.md, conditions 4 and 5).
# Usage: loop_guard.sh <project_root> <allowed_paths_file> [--batch <batch_paths_file>] [--max-batch-files N]
#   allowed_paths_file  one path per line (relative to the root): every file the plan allows the loop to create or change
#   batch_paths_file    one path per line: the files the batch that just ended created or changed
#   --max-batch-files   default 15
# Prints one JSON document on stdout. Read-only: only runs `git status`, writes nothing.
# "stop" is true when: not a git repository, a dirty path is not in the allowed list (an outside edit, or a file the
# loop was not planned to touch), the batch touched a path that is not allowed, or the batch is larger than the limit.
# Exit code 0 = report produced, 2 = bad arguments.
set -u

ROOT="${1:-}"; ALLOWED="${2:-}"
[ -n "$ROOT" ] && [ -f "$ALLOWED" ] || { echo "Usage: loop_guard.sh <project_root> <allowed_paths_file> [--batch <file>] [--max-batch-files N]" >&2; exit 2; }
ALLOWED="$(cd "$(dirname "$ALLOWED")" && pwd)/$(basename "$ALLOWED")"
shift 2
BATCH=""; MAX=15
while [ $# -gt 0 ]; do
  case "$1" in
    --batch) BATCH="${2:-}"; [ -f "$BATCH" ] && BATCH="$(cd "$(dirname "$BATCH")" && pwd)/$(basename "$BATCH")"; shift 2 ;;
    --max-batch-files) MAX="${2:-15}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
cd "$ROOT" 2>/dev/null || { echo "Cannot enter $ROOT" >&2; exit 2; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t loopguard)"
trap 'rm -rf "$TMP"' EXIT
arr() { awk 'BEGIN{printf "["} NF {g=$0; gsub(/\\/,"/",g); gsub(/"/,"\047",g); printf "%s\"%s\"", (n++?",":""), g} END{printf "]"}' "$1"; }

in_git=false; git rev-parse --is-inside-work-tree >/dev/null 2>&1 && in_git=true
: > "$TMP/dirty"
if [ "$in_git" = true ]; then
  # porcelain: "XY path" or "XY old -> new"; keep the new path, and list untracked files individually
  git status --porcelain --untracked-files=all 2>/dev/null | sed -E 's/^...//; s/^.* -> //' | sed -E 's/^"(.*)"$/\1/' | sort -u > "$TMP/dirty"
fi
grep -v '^[[:space:]]*$' "$ALLOWED" | sed -E 's#^\./##' | sort -u > "$TMP/allowed"

comm -23 "$TMP/dirty" "$TMP/allowed" > "$TMP/unexpected"
: > "$TMP/batch"; : > "$TMP/outside"
if [ -n "$BATCH" ] && [ -f "$BATCH" ]; then
  grep -v '^[[:space:]]*$' "$BATCH" | sed -E 's#^\./##' | sort -u > "$TMP/batch"
  comm -23 "$TMP/batch" "$TMP/allowed" > "$TMP/outside"
fi
n_batch="$(wc -l < "$TMP/batch" | tr -d ' ')"
over=false; [ "$n_batch" -gt "$MAX" ] && over=true

reasons=""
add() { reasons="${reasons:+$reasons, }\"$1\""; }
[ "$in_git" = true ] || add "not a git repository"
[ -s "$TMP/unexpected" ] && add "files changed that the loop was not planned to touch (outside edit?)"
[ -s "$TMP/outside" ] && add "the batch touched files outside the allowed list"
[ "$over" = true ] && add "the batch changed $n_batch files (limit $MAX)"
stop=false; [ -n "$reasons" ] && stop=true

cat <<JSON
{
  "stop": $stop,
  "reasons": [${reasons}],
  "in_git": $in_git,
  "dirty_files": $(wc -l < "$TMP/dirty" | tr -d ' '),
  "unexpected_dirty": $(arr "$TMP/unexpected"),
  "batch": {"files": $n_batch, "limit": $MAX, "over_limit": $over, "outside_allowed": $(arr "$TMP/outside")}
}
JSON
