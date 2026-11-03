#!/usr/bin/env bash
# Removes `import 'package:get/...'` lines from files that no longer use anything from GetX.
# Usage: kill_getx_finish.sh [--apply] [project_root] [target ...]
#   Default is a dry run (lists what would change). --apply edits the files.
# Conservative: if any GetX symbol or GetX extension (.tr, 2.seconds, .capitalizeFirst, ...) remains in a file,
# its import is kept and the file is listed under "still_uses".
# Skips frozen originals (header "DEPRECATED: migrated by /feature --migrate").
# Never edits pubspec.yaml: when no import is left it tells you to run `flutter pub remove get`.
# Exit code 0 = ok, 2 = bad arguments / no lib/.
set -u

APPLY=0
if [ "${1:-}" = "--apply" ]; then APPLY=1; shift; fi
ROOT="${1:-.}"; [ $# -gt 0 ] && shift
cd "$ROOT" 2>/dev/null || { echo "Cannot enter $ROOT" >&2; exit 2; }
[ -d lib ] || { echo "No lib/ directory found in $ROOT" >&2; exit 2; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t killfin)"
trap 'rm -rf "$TMP"' EXIT

: > "$TMP/files"
if [ $# -eq 0 ]; then set -- lib; fi
for t in "$@"; do
  if [ -d "lib/features/$t" ]; then p="lib/features/$t"
  elif [ -e "$t" ]; then p="$t"
  elif [ -e "lib/$t" ]; then p="lib/$t"
  else echo "Unknown target: $t" >&2; exit 2; fi
  if [ -d "$p" ]; then find "$p" -name '*.dart' 2>/dev/null >> "$TMP/files"; else printf '%s\n' "$p" >> "$TMP/files"; fi
done
sort -u "$TMP/files" -o "$TMP/files"

NB='(^|[^A-Za-z0-9_])'
IMPORT_LINE="^[[:space:]]*(import|export)[[:space:]]+['\"]package:get/[^'\"]*['\"][^;]*;[[:space:]]*\$"
SYMS="$RE_GX_PREFILTER|$RE_GX_EXT_BROAD|$RE_GETX|$RE_GX_NAV|$RE_GX_DI|$RE_GX_UI|$RE_GX_WIDGETS|$RE_GX_REACTIVE|$RE_GX_WORKERS"   # from the GetX catalog in detect.sh

: > "$TMP/removable"; : > "$TMP/still"; skipped=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  grep -qE "$IMPORT_LINE" "$f" 2>/dev/null || continue
  if head -n 3 "$f" | grep -q "DEPRECATED: migrated by /feature --migrate"; then skipped=$((skipped + 1)); continue; fi
  rest="$(grep -vE "$IMPORT_LINE" "$f" | grep -vE '^[[:space:]]*//' )"
  hits="$(printf '%s\n' "$rest" | grep -cE "$SYMS" || true)"
  if [ "${hits:-0}" -eq 0 ]; then echo "$f" >> "$TMP/removable"; else printf '%s\t%s\n' "$f" "$hits" >> "$TMP/still"; fi
done < "$TMP/files"

removed=0
if [ "$APPLY" -eq 1 ] && [ -s "$TMP/removable" ]; then
  while IFS= read -r f; do
    grep -vE "$IMPORT_LINE" "$f" > "$TMP/out" && cat "$TMP/out" > "$f" && removed=$((removed + 1))
  done < "$TMP/removable"
fi

# Any import left anywhere in lib/ (outside frozen originals)?
left="$(grep -rlE "$IMPORT_LINE" lib --include='*.dart' 2>/dev/null | while IFS= read -r f; do head -n 3 "$f" | grep -q "DEPRECATED: migrated by /feature --migrate" || echo "$f"; done | wc -l | tr -d ' ')"
pub_get=false; [ -f pubspec.yaml ] && grep -qE "^[[:space:]]*get:" pubspec.yaml && pub_get=true

n_rem="$(wc -l < "$TMP/removable" | tr -d ' ')"
if [ "$APPLY" -eq 1 ]; then echo "APPLIED: removed the package:get import from $removed file(s)"; else echo "DRY RUN: would remove the package:get import from $n_rem file(s). Nothing was changed."; fi
sed 's/^/  removable  /' "$TMP/removable"
awk -F'\t' '{ printf "  still uses GetX (%d line(s)): %s\n", $2, $1 }' "$TMP/still"
[ "$skipped" -eq 0 ] || echo "  skipped $skipped deprecated original(s)"
echo "Files still importing package:get in lib/: $left"
if [ "$left" -eq 0 ] && [ "$pub_get" = true ]; then
  echo "NEXT: no file imports package:get any more. pubspec.yaml still lists it: run \`flutter pub remove get\` yourself."
fi
