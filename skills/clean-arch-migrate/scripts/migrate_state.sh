#!/usr/bin/env bash
# Progress file for /migrate: which feature is done, blocked or next. Read-only except <root>/.clean-arch/progress.json.
# Usage:
#   migrate_state.sh <root> init <audit-or-plan.json>   create the file from the plan's unit order (refuses if it exists: exit 1)
#   migrate_state.sh <root> next                        print the next feature that is pending or in_progress (nothing when finished)
#   migrate_state.sh <root> set <feature> <status> [e2e] status: pending|in_progress|done|blocked   e2e: done|declined|failed
#   migrate_state.sh <root> summary                     counts and the blocked / e2e lists
# Exit: 0 ok, 1 refused (bad input, exists, unknown feature), 2 progress file is malformed (it is never overwritten).
# One feature per line, so every edit is a line replacement and the file stays diff-friendly.
set -u
ROOT="${1:-.}"; CMD="${2:-}"; shift 2 2>/dev/null || true
F="$ROOT/.clean-arch/progress.json"

valid() { [ -f "$F" ] && head -n 1 "$F" | grep -q '^{$' && grep -q '^"features": \[$' "$F" && tail -n 1 "$F" | grep -q '^}$'; }
need_valid() { valid || { echo "progress.json is malformed or missing: $F (left untouched)" >&2; exit 2; }; }
rows() { grep '^{"name":' "$F" | sed 's/,$//'; }
field() { printf '%s' "$1" | sed -nE "s/.*\"$2\":\"([^\"]*)\".*/\1/p"; }

case "$CMD" in
  init)
    SRC="${1:-}"; [ -f "$SRC" ] || { echo "usage: init <audit-or-plan.json>" >&2; exit 1; }
    [ -e "$F" ] && { echo "progress.json already exists: $F (resume with 'next', or delete it to start over)" >&2; exit 1; }
    names="$(grep -o '"units": *\[ *"[^]]*\]' "$SRC" | grep -o '"[A-Za-z0-9_./-]*"' | grep -v '^"units"$' | tr -d '"' | awk '!seen[$0]++')"
    [ -n "$names" ] || { echo "no migration units found in $SRC" >&2; exit 1; }
    mkdir -p "$ROOT/.clean-arch"
    { echo '{'; echo "\"plan\": \"$(printf '%s' "$SRC" | sed 's/["\\]/_/g')\","; echo '"baseline_errors": -1,'; echo '"features": ['
      printf '%s\n' "$names" | awk '{ printf "%s{\"name\":\"%s\",\"status\":\"pending\",\"e2e\":\"\"}", (NR>1?",\n":""), $0 } END { print "" }'
      echo ']'; echo '}'; } > "$F"
    echo "created $F with $(printf '%s\n' "$names" | wc -l | tr -d ' ') features" ;;
  next)
    need_valid
    rows | while IFS= read -r r; do s="$(field "$r" status)"; if [ "$s" = pending ] || [ "$s" = in_progress ]; then echo "$(field "$r" name)"; break; fi; done ;;
  set)
    need_valid
    name="${1:-}"; st="${2:-}"; e2e="${3:-}"
    case "$st" in pending|in_progress|done|blocked) ;; *) echo "status must be pending|in_progress|done|blocked" >&2; exit 1 ;; esac
    case "$e2e" in ""|done|declined|failed) ;; *) echo "e2e must be done|declined|failed" >&2; exit 1 ;; esac
    grep -q "^{\"name\":\"$name\"," "$F" || { echo "unknown feature: $name" >&2; exit 1; }
    old="$(grep "^{\"name\":\"$name\"," "$F" | sed 's/,$//')"; [ -n "$e2e" ] || e2e="$(field "$old" e2e)"
    tmp="$F.tmp.$$"
    awk -v n="$name" -v s="$st" -v e="$e2e" '
      index($0, "{\"name\":\"" n "\",") == 1 { comma = ($0 ~ /,$/) ? "," : ""; print "{\"name\":\"" n "\",\"status\":\"" s "\",\"e2e\":\"" e "\"}" comma; next } { print }' "$F" > "$tmp" && mv "$tmp" "$F" ;;
  summary)
    need_valid
    t=0; for s in pending in_progress done blocked; do eval "c_$s=0"; done
    while IFS= read -r r; do s="$(field "$r" status)"; t=$((t+1)); eval "c_$s=\$((c_$s+1))"; done <<EOT
$(rows)
EOT
    echo "features: $t  done: $c_done  in_progress: $c_in_progress  pending: $c_pending  blocked: $c_blocked"
    rows | while IFS= read -r r; do [ "$(field "$r" status)" = blocked ] && echo "blocked: $(field "$r" name)"; done
    rows | while IFS= read -r r; do e="$(field "$r" e2e)"; [ -n "$e" ] && echo "e2e $e: $(field "$r" name)"; done
    exit 0 ;;
  *) echo "usage: migrate_state.sh <root> init|next|set|summary ..." >&2; exit 1 ;;
esac
