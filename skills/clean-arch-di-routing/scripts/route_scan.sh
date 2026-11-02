#!/usr/bin/env bash
# Inventory of GetX routing: pages, navigation calls, middlewares and the app root, with a proposed go_router route per page.
# Usage: route_scan.sh [project_root]
# Prints one JSON document on stdout. Read-only: writes nothing, no network.
# Parsing is line based and approximate (GetPage blocks are read for up to 14 lines); the command re-reads each file before editing.
# Skips frozen originals (header "DEPRECATED: migrated by /feature --migrate").
# Exit code 0 = ok, 2 = no lib/ directory.
set -u

ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "Cannot enter $ROOT" >&2; exit 2; }
[ -d lib ] || { echo "No lib/ directory found in $ROOT" >&2; exit 2; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t routescan)"
trap 'rm -rf "$TMP"' EXIT
jstr() { printf '%s' "$1" | tr -d '\000-\037' | sed -e 's/\\/\//g' -e 's/"/'"'"'/g'; }
frozen() { head -n 3 "$1" 2>/dev/null | grep -q "DEPRECATED: migrated by /feature --migrate"; }
pub() { [ -f pubspec.yaml ] && grep -qE "^[[:space:]]*$1:" pubspec.yaml && echo true || echo false; }
snake() { printf '%s' "$1" | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' | tr 'A-Z' 'a-z'; }

find lib -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.gr.dart' ! -name '*.config.dart' ! -name 'app_localizations*.dart' 2>/dev/null | sort \
  | while IFS= read -r f; do frozen "$f" || echo "$f"; done > "$TMP/files"

# ---- Route name constants:  static const HOME = '/home';  ->  HOME<TAB>/home ----
xargs grep -hoE "static +(const|final) +[A-Za-z_][A-Za-z0-9_]* *= *['\"][^'\"]*['\"]" < "$TMP/files" 2>/dev/null \
  | sed -E "s/static +(const|final) +([A-Za-z_][A-Za-z0-9_]*) *= *['\"]([^'\"]*)['\"]/\2\t\3/" | sort -u > "$TMP/consts"

# ---- GetPage blocks ----
: > "$TMP/pages"
while IFS= read -r f; do
  grep -qE "GetPage[<(]" "$f" 2>/dev/null || continue
  awk -v file="$f" '
    function flush(   nm, pg, mw, bd) {
      nm = ""; pg = ""; mw = ""; bd = ""
      if (match(buf, /name: *[^,]+/)) { nm = substr(buf, RSTART + 5, RLENGTH - 5); gsub(/^ +| +$/, "", nm); gsub(/[\x27"]/, "", nm) }
      if (match(buf, /page: *\(\) *=> *(const +)?[A-Z][A-Za-z0-9_]*/)) { pg = substr(buf, RSTART, RLENGTH); sub(/.*=> *(const +)?/, "", pg) }
      else if (match(buf, /page: *\(\) *\{[^}]*return *(const +)?[A-Z][A-Za-z0-9_]*/)) { pg = substr(buf, RSTART, RLENGTH); sub(/.*return *(const +)?/, "", pg) }
      if (match(buf, /middlewares: *\[[^]]*\]/)) { mw = substr(buf, RSTART + 13, RLENGTH - 13); gsub(/[\[\] ]/, "", mw) }
      if (match(buf, /binding: *[A-Z][A-Za-z0-9_]*/)) { bd = substr(buf, RSTART + 8, RLENGTH - 8); gsub(/ /, "", bd) }
      printf "%s\t%d\t%s\t%s\t%s\t%s\n", file, start, nm, pg, mw, bd
    }
    { if (!cap && $0 ~ /GetPage[<(]/) { cap = 1; buf = ""; depth = 0; start = NR; seen = 0 }
      if (cap) { buf = buf " " $0; n = gsub(/\(/, "(", $0); m = gsub(/\)/, ")", $0); depth += n - m; if (n > 0) seen = 1
        lines++; if ((seen && depth <= 0) || lines > 14) { flush(); cap = 0; lines = 0 } } }
  ' "$f" >> "$TMP/pages"
done < "$TMP/files"

# resolve constants in page names
awk -F'\t' 'NR==FNR { c[$1] = $2; next }
  { nm = $3; id = nm; sub(/.*\./, "", id); if (nm in c) nm = c[nm]; else if (id in c) nm = c[id]
    print $1 "\t" $2 "\t" (nm == "" ? "-" : nm) "\t" ($4 == "" ? "-" : $4) "\t" ($5 == "" ? "-" : $5) "\t" ($6 == "" ? "-" : $6) }' "$TMP/consts" "$TMP/pages" > "$TMP/pages_resolved"

# ---- Navigation calls (every call, also several on one line) ----
: > "$TMP/calls_raw"
while IFS= read -r f; do
  grep -qE "(^|[^A-Za-z0-9_])Get\.(to|toNamed|off|offNamed|offAll|offAllNamed|offUntil|back|arguments|parameters|currentRoute)" "$f" 2>/dev/null || continue
  il=0; grep -qE "extends +(ChangeNotifier|ValueNotifier|GetxController|GetxService|Cubit<|Bloc<)" "$f" && il=1
  awk -v file="$f" -v il="$il" '
    { line = $0
      while (match(line, /Get\.(toNamed|to|offAllNamed|offAll|offNamed|offUntil|off|back|arguments|parameters|currentRoute)/)) {
        kind = substr(line, RSTART + 4, RLENGTH - 4); rest = substr(line, RSTART + RLENGTH)
        pre = (RSTART > 1) ? substr(line, RSTART - 1, 1) : ""
        nxt = substr(rest, 1, 1)
        if (pre !~ /[A-Za-z0-9_]/ && nxt !~ /[A-Za-z0-9_]/) {
          arg = rest; sub(/^[ (]+/, "", arg); sub(/[,)].*/, "", arg); gsub(/\t/, " ", arg)
          if (kind ~ /^(back|arguments|parameters|currentRoute)$/) arg = ""
          printf "%s\t%d\t%s\t%s\t%d\n", file, NR, kind, substr(arg, 1, 70), il
        }
        line = rest
      } }' "$f" >> "$TMP/calls_raw"
done < "$TMP/files"
awk -F'\t' 'NR==FNR { c[$1] = $2; next }
  { arg = $4; id = arg; sub(/.*\./, "", id); r = ""
    if (arg in c) r = c[arg]; else if (id in c) r = c[id]; else if (arg ~ /^[\x27"]/) { r = arg; gsub(/[\x27"]/, "", r) }
    printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, arg, r, $5 }' "$TMP/consts" "$TMP/calls_raw" > "$TMP/calls"

# ---- Middlewares, app root, router folder ----
xargs grep -nE "extends +GetMiddleware" < "$TMP/files" 2>/dev/null | sed -E 's/^([^:]+):([0-9]+):.*class +([A-Za-z0-9_]+).*/\1\t\2\t\3/' > "$TMP/mw"
xargs grep -lE "(^|[^A-Za-z0-9_])(GetMaterialApp|GetCupertinoApp)" < "$TMP/files" 2>/dev/null > "$TMP/roots"
initial="$(xargs grep -hE "initialRoute *:" < "$TMP/roots" 2>/dev/null | head -n1 | sed -E "s/.*initialRoute *: *([^,]+),?.*/\1/" | tr -d ' ')"
has_unknown="$(xargs grep -cE "unknownRoute *:" < "$TMP/roots" 2>/dev/null | awk '{s+=$1} END{print s+0}')"
router_files="$(find lib/router -name '*.dart' 2>/dev/null | wc -l | tr -d ' ')"

# ---- Proposed go_router routes (one per page) ----
# widget -> file / feature
: > "$TMP/routes"
while IFS="$(printf '\t')" read -r pf pl pname pwidget pmw pbind; do
  [ "$pwidget" != "-" ] || continue
  [ "$pname" = "-" ] && pname=""
  [ "$pmw" = "-" ] && pmw=""
  [ "$pbind" = "-" ] && pbind=""
  wfile="$(xargs grep -lE "class +$pwidget( |<|\{)" < "$TMP/files" 2>/dev/null | head -n1)"
  feat=""; case "$wfile" in lib/features/*) feat="$(printf '%s' "$wfile" | cut -d/ -f3)" ;; esac
  stem="$(printf '%s' "$pwidget" | sed -E 's/(Page|View|Screen)$//')"
  rclass="${stem}Route"
  path="$pname"
  if [ -z "$path" ]; then path="/$(snake "$stem" | tr '_' '-')"; fi
  # kebab-case suggestion for static segments, keep :params as they are
  kebab="$(printf '%s' "$path" | awk -F/ '{ out=""; for (i=1;i<=NF;i++) { s=$i; if (s !~ /^:/) { gsub(/_/, "-", s); s=tolower(s) } ; out = out (i>1?"/":"") s } print out }')"
  params="$(printf '%s' "$path" | grep -oE ':[A-Za-z0-9_]+' | tr -d ':' | paste -sd, -)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$pname" "$kebab" "$pwidget" "$wfile" "$feat" "$rclass" "$params" "$pmw" "$pf:$pl" >> "$TMP/routes"
done < "$TMP/pages_resolved"

# ---- JSON ----
pages_json="$(awk -F'\t' 'function q(s){gsub(/\\/,"/",s);gsub(/"/,"\047",s);return s}
  { printf "%s{\"declared_in\":\"%s\",\"getx_name\":\"%s\",\"suggested_path\":\"%s\",\"widget\":\"%s\",\"widget_file\":\"%s\",\"feature\":\"%s\",\"route_class\":\"%s\",\"path_params\":\"%s\",\"middlewares\":\"%s\"}", (NR>1?",":""), q($9), q($1), q($2), q($3), q($4), q($5), q($6), q($7), q($8) }' "$TMP/routes")"
calls_json="$(awk -F'\t' 'function q(s){gsub(/\\/,"/",s);gsub(/"/,"\047",s);return s}
  { printf "%s{\"file\":\"%s\",\"line\":%d,\"kind\":\"%s\",\"target\":\"%s\",\"resolved_path\":\"%s\",\"in_logic_class\":%s}", (NR>1?",":""), q($1), $2, $3, q($4), q($5), ($6==1?"true":"false") }' "$TMP/calls")"
mw_json="$(awk -F'\t' 'function q(s){gsub(/\\/,"/",s);gsub(/"/,"\047",s);return s} { printf "%s{\"file\":\"%s\",\"line\":%d,\"class\":\"%s\"}", (NR>1?",":""), q($1), $2, q($3) }' "$TMP/mw")"
roots_json="$(awk 'function q(s){gsub(/\\/,"/",s);gsub(/"/,"\047",s);return s} { printf "%s\"%s\"", (NR>1?",":""), q($0) }' "$TMP/roots")"
n_calls="$(wc -l < "$TMP/calls" | tr -d ' ')"; n_logic="$(awk -F'\t' '$6==1' "$TMP/calls" | wc -l | tr -d ' ')"
n_files="$(cut -f1 "$TMP/calls" | sort -u | wc -l | tr -d ' ')"
n_pages="$(wc -l < "$TMP/routes" | tr -d ' ')"
n_args="$(awk -F'\t' '$3=="arguments" || $3=="parameters"' "$TMP/calls" | wc -l | tr -d ' ')"
kinds="$(cut -f3 "$TMP/calls" | sort | uniq -c | awk '{printf "%s\"%s\":%d", (NR>1?",":""), $2, $1}')"
nav_by_kind="{${kinds}}"

cat <<JSON
{
  "project": "$(jstr "$(basename "$(pwd)")")",
  "pubspec": {"get": $(pub get), "go_router": $(pub go_router), "go_router_builder": $(pub go_router_builder), "build_runner": $(pub build_runner), "auto_route": $(pub auto_route), "flutter_bloc": $(pub flutter_bloc)},
  "app_root": {"files": [${roots_json}], "initial_route": "$(jstr "$initial")", "has_unknown_route": $([ "${has_unknown:-0}" -gt 0 ] && echo true || echo false)},
  "existing_router_files": ${router_files:-0},
  "totals": {"pages": $n_pages, "navigation_calls": $n_calls, "navigation_files": $n_files, "calls_inside_logic_classes": $n_logic, "arguments_or_parameters_reads": $n_args, "middlewares": $(wc -l < "$TMP/mw" | tr -d ' '), "by_kind": $nav_by_kind},
  "pages": [${pages_json}],
  "navigation_calls": [${calls_json}],
  "middlewares": [${mw_json}]
}
JSON
