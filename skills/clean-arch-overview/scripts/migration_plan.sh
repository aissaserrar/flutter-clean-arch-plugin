#!/usr/bin/env bash
# Feature-by-feature plan for migrating GetX controllers to Cubits.
# Usage: migration_plan.sh [project_root]
# Prints one JSON document on stdout. Read-only: writes nothing, no network.
#
# What it does
#   1. finds every GetX controller class (also through custom bases such as GetxFormController), with its mixins,
#      size, .obs / navigation / Get.find usage and whether it is already @Deprecated (= migrated)
#   2. groups them into feature units (see UNIT_AWK in detect.sh: home_tab and home_screen are both "home")
#   3. measures coupling: how many OTHER units use each controller (shared controllers are the risky ones)
#   4. rates risk (low / medium / high) and orders units into waves: isolated quick wins first, shared and large last
#   5. writes the steps per unit and the project-level foundation and finish steps, following the project's
#      conventions (conventions_scan.sh): direct vs interim mode, state-only vs full scope, tests allowed or not
# Controller kinds:  data (StateBox-like) | paginated (Paginable-like) | form | plain | service | lifecycle | animation
# The numbers are line-based and approximate; the commands re-read every file before editing.
# Skips frozen originals (header "DEPRECATED: migrated by /feature --migrate"). Exit code 0 = ok, 2 = no lib/.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "Cannot enter $ROOT" >&2; exit 2; }
[ -d lib ] || { echo "No lib/ directory found in $ROOT" >&2; exit 2; }
. "$SCRIPT_DIR/detect.sh"
detect_bases
eval "$(bash "$SCRIPT_DIR/conventions_scan.sh" . --env)"

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t migplan)"
trap 'rm -rf "$TMP"' EXIT
T="$(printf '\t')"
jstr() { printf '%s' "$1" | tr -d '\000-\037' | sed -e 's/\\/\//g' -e 's/"/'"'"'/g'; }
frozen() { head -n 3 "$1" 2>/dev/null | grep -q "DEPRECATED: migrated by /feature --migrate"; }

grep -rl --include='*.dart' "DEPRECATED: migrated by /feature --migrate" lib 2>/dev/null > "$TMP/frozenlist" || : > "$TMP/frozenlist"
find lib -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.gr.dart' ! -name '*.config.dart' ! -name 'app_localizations*.dart' 2>/dev/null | sort \
  | grep -vxFf "$TMP/frozenlist" > "$TMP/files"

# ---- 1. controller classes (multi-line headers allowed) ----
: > "$TMP/ctrl_raw"
grep -lE "$RE_GETX" $(cat "$TMP/files") 2>/dev/null | while IFS= read -r f; do
  awk -v f="$f" -v bases="$GETX_BASES" '
    { L[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (L[i] !~ /class +[A-Za-z0-9_]+/) continue
        hdr = L[i]; j = i
        while (hdr !~ /\{/ && j < NR && j < i + 4) { j++; hdr = hdr " " L[j] }
        if (hdr !~ ("extends +(" bases ")( *<|[ {])")) continue
        t = hdr; sub(/.*class +/, "", t); name = t; sub(/[^A-Za-z0-9_].*/, "", name)
        t = hdr; sub(/.*extends +/, "", t); base = t; sub(/[^A-Za-z0-9_].*/, "", base)
        mix = ""
        if (hdr ~ / with /) { m = hdr; sub(/.* with +/, "", m); sub(/\{.*/, "", m); sub(/ implements.*/, "", m); while (gsub(/<[^<>]*>/, "", m)) ; gsub(/ /, "", m); gsub(/,/, "+", m); mix = m }
        dep = 0; for (k = i - 1; k >= 1 && k >= i - 4; k--) if (L[k] ~ /@Deprecated/) dep = 1
        printf "%s\t%s\t%s\t%s\t%d\n", f, name, base, (mix == "" ? "-" : mix), dep
      }
    }' "$f" >> "$TMP/ctrl_raw"
done

# ---- 2. enrich: size, usage, kind, consumers, unit ----
# One pass finds every file that mentions any controller name:  <file><TAB><name>
names_alt="$(cut -f2 "$TMP/ctrl_raw" | sort -u | paste -sd'|' -)"
: > "$TMP/refs"
if [ -n "$names_alt" ]; then
  grep -rwoE --include='*.dart' "($names_alt)" lib 2>/dev/null | sed -E 's/:([A-Za-z0-9_]+)$/\t\1/' | grep -vE '\.(g|freezed|gr|config)\.dart' | sort -u > "$TMP/refs"
fi
awk -F'\t' 'NR==FNR { ok[$0] = 1; next } ($1 in ok)' "$TMP/files" "$TMP/refs" > "$TMP/refs_ok" 2>/dev/null; mv "$TMP/refs_ok" "$TMP/refs"
: > "$TMP/ctrl"
while IFS="$T" read -r f name base mix dep; do
  loc="$(wc -l < "$f" | tr -d ' ')"
  obs="$(grep -cE '\.obs([^A-Za-z0-9_]|$)|(^|[^A-Za-z0-9_])Rx[A-Za-z]*[<(]' "$f" 2>/dev/null || true)"
  nav="$(grep -cE 'Get\.(to|toNamed|off|offNamed|offAll|offAllNamed|back|dialog|defaultDialog|snackbar|bottomSheet)' "$f" 2>/dev/null || true)"
  find_="$(grep -cE 'Get\.(find|put|lazyPut)' "$f" 2>/dev/null || true)"
  kind=plain
  case "$base" in *Form*) kind=form ;; GetxService) kind=service ;; SuperController) kind=lifecycle ;; esac
  case "$mix" in *BodyConvertible*|*FormMixin*) kind=form ;; esac
  if [ "$kind" = plain ]; then
    case "$mix" in
      *Paginable*|*Paginat*) kind=paginated ;;
      *StateBox*|*DataBox*) kind=data ;;
      *WidgetsBindingObserver*) kind=lifecycle ;;
      *Ticker*) kind=animation ;;
    esac
  fi
  awk -F'\t' -v n="$name" -v self="$f" '$2 == n && $1 != self { print $1 }' "$TMP/refs" > "$TMP/cons"
  ncons="$(wc -l < "$TMP/cons" | tr -d ' ')"
  own="$(echo "$f" | awk "$UNIT_AWK"' { print unit_of($0) }')"
  inb="$(awk "$UNIT_AWK"' { u = unit_of($0); if (u != "'"$own"'") print u }' "$TMP/cons" | sort -u)"
  ninb="$(printf '%s' "$inb" | grep -c . || true)"
  inbl="$(printf '%s' "$inb" | head -n 8 | paste -sd, -)"
  printf '%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s\n' "$own" "$name" "$base" "$mix" "$kind" "$dep" "$loc" "${obs:-0}" "${nav:-0}" "${find_:-0}" "$ncons" "${ninb:-0}" "$inbl" "$f" >> "$TMP/ctrl"
done < "$TMP/ctrl_raw"
# columns: 1 unit 2 name 3 base 4 mixins 5 kind 6 deprecated 7 loc 8 obs 9 nav 10 find 11 consumers 12 inbound_units 13 inbound_list 14 file

# ---- 3. per-file facts for unit totals ----
if [ -n "${CA_GX_ALL:-}" ] && [ -f "$CA_GX_ALL" ]; then GXSRC="$CA_GX_ALL"; else grep -rnE --include='*.dart' "$RE_GX_PREFILTER|$RE_GETX" lib 2>/dev/null > "$TMP/gx_all"; GXSRC="$TMP/gx_all"; fi
awk -F: '{ c[$1]++ } END { for (f in c) printf "%s\t%d\n", f, c[f] }' "$GXSRC" > "$TMP/getxcount"
if [ -n "${CA_BLOC_LIST:-}" ] && [ -f "$CA_BLOC_LIST" ]; then cp "$CA_BLOC_LIST" "$TMP/cubitfiles"; else grep -rlE --include='*.dart' "$RE_CUBIT" lib 2>/dev/null > "$TMP/cubitfiles"; fi
grep -rlE --include='*.dart' 'extends +StatefulWidget' lib 2>/dev/null > "$TMP/statefulfiles"
awk -F'\t' -v cf="$TMP/cubitfiles" -v sf="$TMP/statefulfiles" -v gc="$TMP/getxcount" "$UNIT_AWK"'
  BEGIN { while ((getline l < cf) > 0) cub[l] = 1; while ((getline l < sf) > 0) sta[l] = 1; while ((getline l < gc) > 0) { split(l, x, "\t"); gx[x[1]] = x[2] + 0 } }
  { u = unit_of($0); files[u]++; hits[u] += gx[$0]; if ($0 in cub) cubits[u]++; if ($0 in sta) stateful[u]++ }
  END { for (u in files) printf "%s\t%d\t%d\t%d\t%d\n", u, files[u], hits[u], cubits[u] + 0, stateful[u] + 0 }' "$TMP/files" > "$TMP/unitfacts"

# ---- 4. units: aggregate, rate risk, order ----
awk -F'\t' -v facts="$TMP/unitfacts" '
  BEGIN { while ((getline l < facts) > 0) { split(l, x, "\t"); uf[x[1]] = x[2]; ug[x[1]] = x[3]; uc[x[1]] = x[4]; us[x[1]] = x[5] } }
  { u = $1; n[u]++; loc[u] += $7; if ($7 > lmax[u]) lmax[u] = $7; obs[u] += $8; nav[u] += $9; if ($12 > inb[u]) inb[u] = $12; dep[u] += $6; k[u, $5]++
    if ($5 == "form") form[u]++ }
  END {
    for (u in n) {
      risk = "low"; why = ""
      if (inb[u] >= 6 || lmax[u] >= 500) risk = "high"
      else if (inb[u] >= 3 || nav[u] >= 3 || form[u] > 0 || lmax[u] >= 250 || obs[u] >= 15) risk = "medium"
      rank = (risk == "low" ? 1 : (risk == "medium" ? 2 : 3))
      status = (dep[u] == n[u]) ? "migrated" : ((dep[u] > 0) ? "partial" : "todo")
      printf "%d\t%d\t%d\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n", rank, inb[u], loc[u], u, risk, status, n[u], loc[u], lmax[u], obs[u], nav[u], inb[u], dep[u], uf[u] + 0, ug[u] + 0, uc[u] + 0, us[u] + 0, k[u, "data"] + 0, k[u, "paginated"] + 0, k[u, "form"] + 0, k[u, "plain"] + k[u, "service"] + k[u, "lifecycle"] + k[u, "animation"]
    }
  }' "$TMP/ctrl" | sort -t"$T" -k1,1n -k2,2n -k3,3n | cut -f4- > "$TMP/units"
# columns: 1 unit 2 risk 3 status 4 controllers 5 loc 6 loc_max 7 obs 8 nav 9 inbound 10 deprecated 11 files 12 getx_hits 13 cubits 14 stateful 15 data 16 paginated 17 form 18 other

cut -f1 "$TMP/units" > "$TMP/units_names"

# ---- 5. JSON ----
unit_json() { # builds the JSON object of one unit (reads the unit row fields)
  :
}
ctrl_json="$(awk -F'\t' 'function q(s){gsub(/\\/,"/",s);gsub(/"/,"\047",s);return s}
  { printf "%s{\"unit\":\"%s\",\"name\":\"%s\",\"base\":\"%s\",\"mixins\":\"%s\",\"kind\":\"%s\",\"migrated\":%s,\"loc\":%d,\"obs\":%d,\"navigation_calls\":%d,\"get_find_calls\":%d,\"consumer_files\":%d,\"inbound_units\":%d,\"inbound_unit_names\":\"%s\",\"file\":\"%s\"}", (NR>1?",":""), q($1), q($2), q($3), q($4), $5, ($6==1?"true":"false"), $7, $8, $9, $10, $11, $12, q($13), q($14) }' "$TMP/ctrl")"

# controllers of a unit in the order they should be converted: least used by other features first, then smallest
sort -t"$T" -k1,1 -k12,12n -k7,7n "$TMP/ctrl" > "$TMP/ctrl_sorted"
units_json="$(awk -F'\t' -v ctrl="$TMP/ctrl_sorted" -v structure="$CONV_STRUCTURE" -v notests="$CONV_NO_TESTS" '
  function q(s){gsub(/\\/,"/",s);gsub(/"/,"\047",s);return s}
  BEGIN { while ((getline l < ctrl) > 0) { split(l, c, "\t"); names[c[1]] = names[c[1]] (names[c[1]] == "" ? "" : ",") "\"" q(c[2]) "\"" } }
  { u = $1; risk = $2; status = $3
    steps = ""
    if (structure == "true") steps = steps "{\"command\":\"/feature " u " --migrate\",\"title\":\"Move the unit files into lib/features/" u "/ (originals stay, marked deprecated)\"},"
    steps = steps "{\"command\":\"/pre-check " u "\",\"title\":\"Check it is safe: clean tree, analyzer baseline, impact\"},"
    steps = steps "{\"command\":\"/to-bloc " u "\",\"title\":\"Convert the " $4 " controller(s) to cubits (phase 1) and rewire their screens (phase 2)\"},"
    if (notests != "true") steps = steps "{\"command\":\"clean-arch-testing\",\"title\":\"Add bloc_test cases for the new cubits\"},"
    steps = steps "{\"command\":\"/audit\",\"title\":\"Re-run the audit and review the diff before the next unit\"}"
    note = ""
    if ($17 > 0) note = $17 " form controller(s): confirm the form approach first (clean-arch-forms)."
    printf "%s{\"name\":\"%s\",\"risk\":\"%s\",\"status\":\"%s\",\"controllers\":%d,\"controller_names\":[%s],\"loc\":%d,\"largest_controller_loc\":%d,\"obs\":%d,\"navigation_calls\":%d,\"inbound_units\":%d,\"already_deprecated\":%d,\"files\":%d,\"getx_hits\":%d,\"existing_cubits\":%d,\"stateful_widgets\":%d,\"kinds\":{\"data\":%d,\"paginated\":%d,\"form\":%d,\"other\":%d},\"note\":\"%s\",\"steps\":[%s]}", (NR>1?",":""), q(u), risk, status, $4, names[u], $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, q(note), steps }' "$TMP/units")"

waves_json="$(awk -F'\t' '
  { r = $2; w = (r == "low" ? 1 : (r == "medium" ? 2 : 3)); if ($3 == "migrated") next; list[w] = list[w] (list[w] == "" ? "" : ",") "\"" $1 "\""; cnt[w]++; ctr[w] += $4 }
  END { first = 1
    t[1] = "Quick wins: small and isolated"; y[1] = "Few or no other features use these controllers, so a mistake stays local. Start here to learn the project'"'"'s conventions."
    t[2] = "Medium: forms, navigation inside controllers, larger files"; y[2] = "More coupling or more behaviour to preserve. Review each unit carefully."
    t[3] = "Shared and large: last, one controller per PR"; y[3] = "Used by many features or very large. Migrate after the features that consume them, one controller at a time."
    for (w = 1; w <= 3; w++) if (cnt[w] > 0) { printf "%s{\"wave\":%d,\"title\":\"%s\",\"why\":\"%s\",\"units\":[%s],\"controllers\":%d}", (first ? "" : ","), w, t[w], y[w], list[w], ctr[w]; first = 0 } }' "$TMP/units")"

# ---- 6. foundation and finish ----
n_ctrl="$(wc -l < "$TMP/ctrl" | tr -d ' ')"
n_dep="$(awk -F'\t' '$6==1' "$TMP/ctrl" | wc -l | tr -d ' ')"
n_form="$(awk -F'\t' '$5=="form"' "$TMP/ctrl" | wc -l | tr -d ' ')"
n_units="$(wc -l < "$TMP/units" | tr -d ' ')"
n_done="$(awk -F'\t' '$3=="migrated"' "$TMP/units" | wc -l | tr -d ' ')"
mixin_list="$(awk -F'\t' '$4!="-" {n=split($4, m, "+"); for (i=1;i<=n;i++) c[m[i]]++} END {for (k in c) printf "%s (%d)\n", k, c[k]}' "$TMP/ctrl" | sort -t'(' -k2,2nr | head -n 6 | paste -sd, - | sed 's/,/, /g')"
kinds_json="$(awk -F'\t' '{c[$5]++} END {first=1; for (k in c) { printf "%s\"%s\":%d", (first?"":","), k, c[k]; first=0 }}' "$TMP/ctrl")"

foundation=""
fadd() { foundation="${foundation:+$foundation,}{\"id\":\"$1\",\"command\":\"$(jstr "$2")\",\"title\":\"$(jstr "$3")\",\"why\":\"$(jstr "$4")\"}"; }
fadd pre-check "/pre-check" "Clean git tree and analyzer baseline" "Every editing command needs a clean committed tree and a flutter analyze baseline to compare against."
if [ "$CONV_ASSUMED" = true ]; then
  fadd scope "/audit" "Confirm the migration scope" "Assumed from the project: $CONV_BASIS. /audit asks once and saves the answer in .clean-arch/config.json."
fi
if [ "$CONV_HAS_INFRA" != true ]; then
  fadd infra "(you run)" "Add the BLoC infrastructure" "No project Cubit base classes found. Add flutter_bloc and equatable (flutter pub add ...) and decide the state base classes before the first unit."
fi
if [ "$n_form" -gt 0 ]; then
  fadd forms "clean-arch-forms" "Decide the form approach once" "$n_form form controller(s)${CONV_GETX_SIBLINGS:+ ($CONV_GETX_SIBLINGS)}. Agree how they become form cubits before the units that contain them."
fi

finish=""
gadd() { finish="${finish:+$finish,}{\"id\":\"$1\",\"command\":\"$(jstr "$2")\",\"title\":\"$(jstr "$3")\",\"why\":\"$(jstr "$4")\"}"; }
gadd delete "(you decide)" "Delete the deprecated controllers" "Once nothing references a controller marked @Deprecated, delete it. The commands never delete them."
[ -n "$mixin_list" ] && gadd mixins "(you decide)" "Remove helper mixins nobody uses any more" "Controller mixins in use today: $mixin_list. When the last controller using one is gone, delete the mixin."
if [ "$CONV_SCOPE" = state ]; then
  gadd verify "/audit" "Check what GetX is left" "Expected leftovers by decision: navigation and anything the project keeps on purpose. Everything else should be gone."
else
  gadd route "/route" "Replace GetX navigation" "Full scope: navigation moves to go_router or auto_route (asked)."
  gadd di "/di" "Replace Get.put / Get.find / Bindings" "Full scope: dependency injection moves to get_it or provider (asked)."
  gadd kill "/kill-getx" "Remove the last GetX imports and widgets" "Run after /route and /di; removes the package:get imports that are no longer used."
fi

other_json="$(awk -F'\t' 'NR==FNR { has[$1] = 1; next } !($1 in has) && $3 > 0 { printf "%d\t%s\t%d\t%d\n", $3, $1, $2, $5 }' "$TMP/units_names" "$TMP/unitfacts" | sort -rn | head -n 12 | awk -F'\t' '{ printf "%s{\"name\":\"%s\",\"files\":%d,\"getx_hits\":%d,\"stateful_widgets\":%d}", (NR>1?",":""), $2, $3, $1, $4 }')"

cat <<JSON
{
  "project": "$(jstr "$(basename "$(pwd)")")",
  "settings": {"mode": "$CONV_MODE", "scope": "$CONV_SCOPE", "structure": $CONV_STRUCTURE, "assumed": $CONV_ASSUMED, "basis": "$(jstr "$CONV_BASIS")", "tests_allowed": $([ "$CONV_NO_TESTS" = true ] && echo false || echo true), "destination": "Cubit|Bloc", "forbidden_bases": "DataCubit,BaseCubit,PaginatedCubit", "legacy_project_bases": "$(jstr "$CONV_BASES")"},
  "totals": {"controllers": $n_ctrl, "already_deprecated": $n_dep, "units": $n_units, "units_migrated": $n_done, "form_controllers": $n_form, "by_kind": {${kinds_json}}},
  "foundation": [${foundation}],
  "waves": [${waves_json}],
  "units": [${units_json}],
  "other_getx_units": [${other_json}],
  "finish": [${finish}],
  "controllers": [${ctrl_json}]
}
JSON
