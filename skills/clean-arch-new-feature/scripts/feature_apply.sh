#!/usr/bin/env bash
# Applies a confirmed move plan: relocates files and rewrites every import that pointed at them.
# Usage: feature_apply.sh [--dry-run] [--keep-deprecated] <project_root> <plan.tsv>
#   --keep-deprecated  copy instead of move: the original stays at its old path, marked deprecated
#                      (header comment + @Deprecated on its top-level declarations), and the copy is
#                      created at the new path. Importers are still rewritten to the new path.
#   plan.tsv = one move per line: <from><TAB><to>, both relative to the project root (lib/...).
# Prints a summary on stdout. Exit codes: 0 ok, 1 moves done but imports left unresolved, 2 refused (bad plan or bad arguments).
#
# Safety: refuses if a source is missing, a destination exists, or a file uses part/part of.
# Default: `git mv` inside a git repo (history is kept), plain mv otherwise. Never deletes files; only removes
# directories that became empty (move mode only). Imports of moved files become package imports; other imports are untouched.
set -u

DRY=0; KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --keep-deprecated) KEEP=1; shift ;;
    *) break ;;
  esac
done
ROOT="${1:-.}"; PLAN="${2:-}"
[ -f "$PLAN" ] || { echo "Plan file not found: $PLAN" >&2; exit 2; }
PLAN="$(cd "$(dirname "$PLAN")" && pwd)/$(basename "$PLAN")"
cd "$ROOT" 2>/dev/null || { echo "Cannot enter $ROOT" >&2; exit 2; }
[ -d lib ] && [ -f pubspec.yaml ] || { echo "Run against a Flutter project root (pubspec.yaml + lib/)" >&2; exit 2; }
PKG="$(sed -n 's/^name:[[:space:]]*//p' pubspec.yaml | head -n1 | tr -d ' \r')"
[ -n "$PKG" ] || { echo "Cannot read package name from pubspec.yaml" >&2; exit 2; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t featapply)"
trap 'rm -rf "$TMP"' EXIT
TAB="$(printf '\t')"

# ---- Validate plan ----
grep -v '^[[:space:]]*$' "$PLAN" | grep -v '^#' > "$TMP/plan"
[ -s "$TMP/plan" ] || { echo "Plan is empty" >&2; exit 2; }
bad=0
while IFS="$TAB" read -r from to; do
  case "$from" in lib/*.dart) ;; *) echo "REFUSED: source must be lib/...dart: $from" >&2; bad=1; continue ;; esac
  case "$to" in lib/*.dart) ;; *) echo "REFUSED: destination must be lib/...dart: $to" >&2; bad=1; continue ;; esac
  [ -f "$from" ] || { echo "REFUSED: source missing: $from" >&2; bad=1; }
  [ -e "$to" ] && { echo "REFUSED: destination exists: $to" >&2; bad=1; }
  grep -qE "^part( of)? " "$from" 2>/dev/null && { echo "REFUSED: uses part/part of: $from" >&2; bad=1; }
  head -n 3 "$from" 2>/dev/null | grep -q "DEPRECATED: migrated by /feature --migrate" && { echo "REFUSED: already a deprecated copy: $from" >&2; bad=1; }
done < "$TMP/plan"
[ "$(cut -f2 "$TMP/plan" | sort | uniq -d | wc -l | tr -d ' ')" -eq 0 ] || { echo "REFUSED: two files map to the same destination" >&2; bad=1; }
[ "$bad" -eq 0 ] || exit 2

# ---- Rewrite imports (pass 1: compute new content for every file that changes) ----
find lib test -name '*.dart' 2>/dev/null | sort > "$TMP/all"
mkdir -p "$TMP/new"
changed=0
while IFS= read -r f; do
  newpath="$f"
  m="$(awk -F'\t' -v f="$f" '$1==f {print $2}' "$TMP/plan")"
  [ -n "$m" ] && newpath="$m"
  out="$TMP/new/$(printf '%s' "$f" | tr '/' '%')"
  awk -v pkg="$PKG" -v plan="$TMP/plan" -v oldfile="$f" '
    function norm(p,  n,a,i,k,o,r) { n = split(p, a, "/"); k = 0
      for (i = 1; i <= n; i++) { if (a[i] == "" || a[i] == ".") continue; if (a[i] == "..") { if (k > 0) k--; continue } o[++k] = a[i] }
      r = ""; for (i = 1; i <= k; i++) r = r (i > 1 ? "/" : "") o[i]; return r }
    function dir(p) { sub(/\/[^\/]*$/, "", p); return p }
    BEGIN { FS = "\t"; while ((getline l < plan) > 0) { split(l, a, "\t"); map[a[1]] = a[2] } ; FS = " "
            moved = (oldfile in map) }
    {
      line = $0
      if (match(line, /^[ \t]*(import|export)[ \t]+["\x27][^"\x27]+["\x27]/)) {
        seg = substr(line, RSTART, RLENGTH); q = seg; sub(/^[^"\x27]*/, "", q); qc = substr(q, 1, 1); spec = substr(q, 2, length(q) - 2)
        rel = ""
        if (spec ~ /^dart:/) rel = ""
        else if (spec ~ ("^package:" pkg "/")) rel = "lib/" substr(spec, length("package:" pkg "/") + 1)
        else if (spec ~ /^package:/) rel = ""
        else rel = norm(dir(oldfile) "/" spec)
        if (rel ~ /^lib\//) {
          nrel = (rel in map) ? map[rel] : rel
          if (nrel != rel || (moved && spec !~ /^package:/)) {
            newspec = "package:" pkg "/" substr(nrel, 5)
            pre = substr(line, 1, RSTART - 1); head = seg; sub(/["\x27][^"\x27]+["\x27]$/, qc newspec qc, head)
            line = pre head substr(line, RSTART + RLENGTH)
          }
        }
      }
      print line
    }' "$f" > "$out"
  if [ "$KEEP" -eq 1 ] && [ -n "$m" ]; then continue; fi
  if ! cmp -s "$f" "$out"; then changed=$((changed + 1)); printf '%s\t%s\n' "$f" "$newpath" >> "$TMP/changed"; fi
done < "$TMP/all"
n_moves="$(wc -l < "$TMP/plan" | tr -d ' ')"

if [ "$DRY" -eq 1 ]; then
  if [ "$KEEP" -eq 1 ]; then verb="copy"; extra=" and mark the originals deprecated"; else verb="move"; extra=""; fi
  echo "DRY RUN: would $verb $n_moves file(s)$extra and rewrite imports in $changed other file(s). Nothing was changed."
  exit 0
fi

# ---- Move (or copy + deprecate) ----
in_git=0; git rev-parse --is-inside-work-tree >/dev/null 2>&1 && in_git=1
TODAY="$(date +%Y-%m-%d)"
while IFS="$TAB" read -r from to; do
  mkdir -p "$(dirname "$to")"
  if [ "$KEEP" -eq 1 ]; then
    cp "$TMP/new/$(printf '%s' "$from" | tr '/' '%')" "$to"
    target="package:$PKG/${to#lib/}"
    awk -v to="$target" -v d="$TODAY" '
      BEGIN { print "// DEPRECATED: migrated by /feature --migrate on " d " to " to
              print "// Do not edit this copy. Delete it once nothing imports it any more." }
      { if ($0 ~ /^(abstract |sealed |base |final |interface )*(mixin class|mixin|class|enum|extension type|extension|typedef)[ \t<]/ && prev !~ /@Deprecated/)
          print "@Deprecated(\x27Migrated to " to "\x27)"
        print; prev = $0 }' "$from" > "$TMP/mark" && cp "$TMP/mark" "$from"
    echo "COPIED $from -> $to (original marked deprecated)"
  else
    if [ "$in_git" -eq 1 ] && git ls-files --error-unmatch "$from" >/dev/null 2>&1; then git mv "$from" "$to"; else mv "$from" "$to"; fi
    echo "MOVED  $from -> $to"
  fi
done < "$TMP/plan"

# ---- Write rewritten content to the (new) locations ----
if [ -s "$TMP/changed" ]; then
  while IFS="$TAB" read -r old newp; do
    cp "$TMP/new/$(printf '%s' "$old" | tr '/' '%')" "$newp"
  done < "$TMP/changed"
fi
echo "REWROTE imports in $changed file(s)"

# ---- Remove directories left empty by the moves (move mode only) ----
if [ "$KEEP" -eq 0 ]; then
  cut -f1 "$TMP/plan" | while IFS= read -r from; do
    d="$(dirname "$from")"
    while [ "$d" != "lib" ] && [ "$d" != "." ] && rmdir "$d" 2>/dev/null; do d="$(dirname "$d")"; done
  done
fi

# ---- Verify: every relative / package import in lib and test must resolve ----
unres=0
find lib test -name '*.dart' 2>/dev/null | while IFS= read -r f; do
  grep -nE "^[[:space:]]*(import|export)[[:space:]]+['\"][^'\"]+['\"]" "$f" 2>/dev/null | while IFS= read -r hit; do
    ln="${hit%%:*}"; spec="$(printf '%s' "$hit" | sed -E "s/^[0-9]+:[[:space:]]*(import|export)[[:space:]]+['\"]([^'\"]+)['\"].*/\2/")"
    case "$spec" in
      dart:*) continue ;;
      package:"$PKG"/*) target="lib/${spec#package:$PKG/}" ;;
      package:*) continue ;;
      *) target="$(cd "$(dirname "$f")" 2>/dev/null && cd "$(dirname "$spec")" 2>/dev/null && pwd)/$(basename "$spec")"; target="${target#$(pwd)/}" ;;
    esac
    [ -f "$target" ] || echo "UNRESOLVED  $f:$ln  $spec"
  done
done > "$TMP/unresolved"
unres="$(wc -l < "$TMP/unresolved" | tr -d ' ')"
cat "$TMP/unresolved"
echo "DONE: $([ "$KEEP" -eq 1 ] && echo copied || echo moved) $n_moves, rewrote $changed, unresolved imports: $unres"
[ "$unres" -eq 0 ] || exit 1
