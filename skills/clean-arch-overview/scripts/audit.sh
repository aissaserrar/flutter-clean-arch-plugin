#!/usr/bin/env bash
# Audits a Flutter project for Clean Architecture compliance and GetX leakage.
# Usage: audit.sh [project_root] [previous_audit.json]   (default root: current directory)
# Prints a single JSON document on stdout. No network.
# Side effect: when .clean-arch/ exists (or CLEAN_ARCH_DIR is set), writes feature-map.suggested.yaml
# there from legacy discovery (overwritten each run). Everything else is read-only.
# With a previous audit JSON (same format, older schemas are fine) the output has a "delta" object
# (what changed since then); without it, "delta" is null.
# Exit code 0 = audit completed (see "status" in the JSON), 2 = no lib/ directory.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-.}"
PREV="${2:-}"
if [ -n "$PREV" ] && [ -f "$PREV" ]; then PREV="$(cd "$(dirname "$PREV")" && pwd)/$(basename "$PREV")"; else PREV=""; fi
cd "$ROOT" 2>/dev/null || { echo "Cannot enter $ROOT" >&2; exit 2; }
LIB="lib"
[ -d "$LIB" ] || { echo "No lib/ directory found in $ROOT" >&2; exit 2; }
FEATURES="$LIB/features"

. "$SCRIPT_DIR/detect.sh"
detect_bases   # follows custom base classes: BaseCubit -> Cubit, GetxFormController -> GetxController

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t cleanarch)"
trap 'rm -rf "$TMP"' EXIT

GREP_DART=(-rnE --include='*.dart' --exclude='*.g.dart' --exclude='*.freezed.dart' --exclude='*.gr.dart' --exclude='*.config.dart' --exclude='app_localizations*.dart')

jstr() { printf '%s' "$1" | tr -d '\000-\037' | sed -e 's/\\/\//g' -e 's/"/'"'"'/g'; }

count_hits() { # <ERE> [dir]
  grep "${GREP_DART[@]}" -e "$1" "${2:-$LIB}" 2>/dev/null | wc -l | tr -d ' '
}

hits_json() { # <ERE> [dir]  -> JSON array of {file,line}, capped at 200
  grep "${GREP_DART[@]}" -e "$1" "${2:-$LIB}" 2>/dev/null | head -n 200 | awk -F: '
    BEGIN { printf "[" }
    { f = $1; gsub(/\\/, "/", f); gsub(/"/, "\047", f)
      printf "%s{\"file\":\"%s\",\"line\":%d}", (NR > 1 ? "," : ""), f, $2 }
    END { printf "]" }'
}

# ---- GetX usage by area. The catalog (what "GetX" means) lives in detect.sh, built from the package's API reference ----
NB="$GX_NB"
P_IMPORT="$RE_GX_IMPORT"
P_CONTROLLER="$RE_GETX"
P_OBX="$RE_GX_WIDGETS"
P_REACTIVE="$RE_GX_REACTIVE"
P_NAV="$RE_GX_NAV"
P_LOOKUP="$RE_GX_DI"
P_UI="$RE_GX_UI"
P_NET="$RE_GX_NET"
P_WORKERS="$RE_GX_WORKERS"
P_TRANSL="$RE_GX_TRANSLATIONS"
P_ALL="$RE_GX_PREFILTER|$RE_GETX"

# ONE pass over lib/ finds every line that touches GetX; each category below is then a cheap filter of that small result
grep "${GREP_DART[@]}" -e "$P_ALL" "$LIB" 2>/dev/null > "$TMP/gx_all"
gx_count() { grep -cE -e "$1" "$TMP/gx_all" 2>/dev/null || true; }
gx_hits()  { grep -E -e "$1" "$TMP/gx_all" 2>/dev/null | hits_stdin; }

# hits_stdin: "file:line:text" lines -> JSON array of {file,line}, capped at 200
hits_stdin() {
  head -n 200 | awk -F: '
    BEGIN { printf "[" }
    { f = $1; gsub(/\\/, "/", f); gsub(/"/, "\047", f)
      printf "%s{\"file\":\"%s\",\"line\":%d}", (NR > 1 ? "," : ""), f, $2 }
    END { printf "]" }'
}

n_import="$(gx_count "$P_IMPORT")"
n_controller="$(gx_count "$P_CONTROLLER")"
n_obx="$(gx_count "$P_OBX")"
n_obs="$(gx_count "$P_REACTIVE")"
n_nav="$(gx_count "$P_NAV")"
n_lookup="$(gx_count "$P_LOOKUP")"
n_ui="$(gx_count "$P_UI")"
n_net="$(gx_count "$P_NET")"
n_workers="$(gx_count "$P_WORKERS")"
n_transl="$(gx_count "$P_TRANSL")"
# Get.<member> that is none of navigation / DI / UI (a member added by a newer GetX, or one the catalog lacks)
grep -E -e "$RE_GX_OTHER_GET" "$TMP/gx_all" 2>/dev/null | grep -vE "$P_NAV|$P_LOOKUP|$P_UI" > "$TMP/other_get"
n_other="$(wc -l < "$TMP/other_get" | tr -d ' ')"
# extension utilities (.tr, 2.seconds, 'a'.capitalizeFirst, widget.paddingAll(8), context.width ...): only in files that import get
gx_import_files > "$TMP/gx_files"
: > "$TMP/ext_hits"
[ -s "$TMP/gx_files" ] && xargs grep -nE "$RE_GX_EXT" < "$TMP/gx_files" 2>/dev/null > "$TMP/ext_hits"
n_utils="$(wc -l < "$TMP/ext_hits" | tr -d ' ')"
getx_total=$((n_import + n_controller + n_obx + n_obs + n_nav + n_lookup + n_ui + n_net + n_workers + n_transl + n_other + n_utils))

files_with_getx="$(wc -l < "$TMP/gx_files" | tr -d ' ')"
getx_pkgs="$(gx_related_packages)"

# ---- Other state management ----
bloc_files="$(grep "${GREP_DART[@]}" -l -E "$RE_CUBIT" "$LIB" 2>/dev/null | wc -l | tr -d ' ')"
stateful="$(count_hits "extends +StatefulWidget")"
setstate="$(count_hits "${NB}setState\\(")"
provider_notifier="$(count_hits "extends +(ChangeNotifier|ValueNotifier)")"

pub_has() { [ -f pubspec.yaml ] && grep -qE "^[[:space:]]*$1:" pubspec.yaml && echo true || echo false; }
has_get="$(pub_has get)"
has_flutter_bloc="$(pub_has flutter_bloc)"
has_get_it="$(pub_has get_it)"
has_provider="$(pub_has provider)"
has_go_router="$(pub_has go_router)"
has_auto_route="$(pub_has auto_route)"
has_patrol="$(pub_has patrol)"

# ---- File distribution ----
find "$LIB" -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.gr.dart' ! -name '*.config.dart' ! -name 'app_localizations*.dart' 2>/dev/null | sort > "$TMP/files"
total_files="$(wc -l < "$TMP/files" | tr -d ' ')"
test_files="$( [ -d test ] && find test -name '*_test.dart' 2>/dev/null | wc -l | tr -d ' ' || echo 0 )"

layers_json="$(awk -F/ '
  { layer = "other"
    if ($2 == "features") {
      layer = (NF >= 5 && ($4 == "domain" || $4 == "data" || $4 == "presentation")) ? $4 : "feature_root"
    } else if ($2 == "core" || $2 == "common" || $2 == "design_system" || $2 == "l10n" || $2 == "bootstrap" || $2 == "router") {
      layer = $2
    } else if (NF == 2) { layer = "root" }
    c[layer]++
    if (layer == "other") top[$2]++ }
  END {
    n = split("domain data presentation feature_root core common design_system l10n bootstrap router root other", k, " ")
    printf "{"
    for (i = 1; i <= n; i++) printf "%s\"%s\":%d", (i > 1 ? "," : ""), k[i], c[k[i]] + 0
    printf "}\t["
    j = 0
    for (d in top) { gsub(/"/, "\047", d); printf "%s{\"dir\":\"%s\",\"files\":%d}", (j++ ? "," : ""), d, top[d] }
    printf "]"
  }' "$TMP/files")"
layers="${layers_json%%$'\t'*}"
legacy_dirs="${layers_json#*$'\t'}"

# ---- Violations (same rules as check_dependencies.sh) ----
: > "$TMP/viol"
add_viol() { # <rule> <feature> <grep -n output>
  [ -n "$3" ] || return 0
  printf '%s\n' "$3" | head -n 50 | awk -F: -v rule="$1" -v feat="$2" '
    function clean(s) { gsub(/\\/, "/", s); gsub(/"/, "\047", s); gsub(/\/\/+/, "/", s); return s }
    { printf "{\"rule\":\"%s\",\"feature\":\"%s\",\"file\":\"%s\",\"line\":%d}\n", clean(rule), clean(feat), clean($1), $2 }' >> "$TMP/viol"
}

features_json=""
untested_list=""
if [ -d "$FEATURES" ]; then
  for feature_dir in "$FEATURES"/*/; do
    [ -d "$feature_dir" ] || continue
    feature="$(basename "$feature_dir")"
    fd="${feature_dir%/}"


    fcount() { find "$1" -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.gr.dart' ! -name '*.config.dart' 2>/dev/null | wc -l | tr -d ' '; }
    f_total="$(fcount "$fd")"
    f_domain="$([ -d "$fd/domain" ] && fcount "$fd/domain" || echo 0)"
    f_data="$([ -d "$fd/data" ] && fcount "$fd/data" || echo 0)"
    f_pres="$([ -d "$fd/presentation" ] && fcount "$fd/presentation" || echo 0)"
    f_getx="$(grep -rE --include='*.dart' -e "$P_ALL" "$fd" 2>/dev/null | wc -l | tr -d ' ')"
    f_tests=false; [ -d "test/features/$feature" ] && f_tests=true
    [ "$f_tests" = false ] && untested_list="${untested_list:+$untested_list, }$feature"
    f_bloc="$(grep -rlE --include='*.dart' "$RE_CUBIT" "$fd" 2>/dev/null | wc -l | tr -d ' ')"
    item="{\"name\":\"$(jstr "$feature")\",\"files\":$f_total,\"domain\":$f_domain,\"data\":$f_data,\"presentation\":$f_pres,\"getx_hits\":$f_getx,\"blocs\":$f_bloc,\"has_tests\":$f_tests}"
    features_json="${features_json:+$features_json,}$item"
  done
  structure_ok=true
else
  structure_ok=false
fi



# ---- Import rules: single source of truth is check_dependencies.sh ----
bash "$SCRIPT_DIR/check_dependencies.sh" "$LIB" 2>/dev/null | awk '
  function clean(s) { gsub(/\\/, "/", s); gsub(/"/, "\047", s); gsub(/\/\/+/, "/", s); return s }
  /^VIOLATION: / { r = substr($0, 12); scope = ""; if (match(r, /^\[[^]]+\]/)) { scope = substr(r, 2, RLENGTH - 2); r = substr(r, RLENGTH + 2) }; n = 0; next }
  /^  / && r != "" { if (++n > 50) next; line = substr($0, 3); split(line, a, ":")
    printf "{\"rule\":\"%s\",\"feature\":\"%s\",\"file\":\"%s\",\"line\":%d,\"severity\":\"error\"}\n", clean(r), clean(scope), clean(a[1]), a[2] }
' >> "$TMP/viol"

# ---- Extra checks (not covered by the import checker) ----
add_hits() { # <rule> <scope> <grep -n output> [severity: error|warning]
  [ -n "$3" ] || return 0
  printf '%s\n' "$3" | head -n 50 | awk -F: -v rule="$1" -v scope="$2" -v sev="${4:-error}" '
    function clean(s) { gsub(/\\/, "/", s); gsub(/"/, "\047", s); gsub(/\/\/+/, "/", s); return s }
    { printf "{\"rule\":\"%s\",\"feature\":\"%s\",\"file\":\"%s\",\"line\":%d,\"severity\":\"%s\"}\n", clean(rule), clean(scope), clean($1), $2, sev }' >> "$TMP/viol"
}
# 'part' only for generated code
out="$(grep "${GREP_DART[@]}" -e "^part +of +|^part +'[^']*'" "$LIB" 2>/dev/null | grep -vE "^part +'[^']*\.(g|freezed|gr|config)\.dart'" | grep -vE ":part +'[^']*\.(g|freezed|gr|config)\.dart'")"
add_hits "part / part of used outside generated code" "style" "$out" warning
# reusable UI does not belong in core/ or common/
[ -d "$LIB/core" ] && out="$(grep "${GREP_DART[@]}" -e "extends +(StatelessWidget|StatefulWidget|HookWidget)" "$LIB/core" 2>/dev/null)" || out=""
add_hits "widget in core/ (reusable UI belongs in design_system/)" "core" "$out" warning
[ -d "$LIB/common" ] && out="$(grep "${GREP_DART[@]}" -e "extends +(StatelessWidget|StatefulWidget|HookWidget)" "$LIB/common" 2>/dev/null)" || out=""
add_hits "widget in common/ (reusable UI belongs in design_system/)" "common" "$out" warning
# only <feature>_providers.dart and bootstrap/ wire data into the rest of a feature
if [ -d "$FEATURES" ]; then
  for fd in "$FEATURES"/*/; do
    fd="${fd%/}"; feat="$(basename "$fd")"
    out="$(find "$fd" -maxdepth 1 -name '*.dart' ! -name '*_providers.dart' ! -name '*_di.dart' ! -name "$feat.dart" 2>/dev/null | xargs grep -HnE "^import '.*/data/" 2>/dev/null | grep -v '^$')"
    add_hits "feature file other than *_providers.dart / *_di.dart imports data" "$feat" "$out"
  done
fi

violations_json="$(paste -sd, "$TMP/viol" 2>/dev/null)"
violation_count="$(wc -l < "$TMP/viol" | tr -d ' ')"
error_count="$(grep -c '"severity":"error"' "$TMP/viol" || true)"
warning_count="$(grep -c '"severity":"warning"' "$TMP/viol" || true)"

# ---- Engineering quality (layer leaks, size, hygiene) ----
# Optional thresholds from .clean-arch/config.json: engineering.max_file_loc / max_file_loc_error
eng_warn_lim=400; eng_err_lim=800
if [ -f .clean-arch/config.json ]; then
  v="$(sed -nE 's/.*"max_file_loc" *: *([0-9]+).*/\1/p' .clean-arch/config.json | head -n1)"
  [ -n "$v" ] && eng_warn_lim="$v"
  v="$(sed -nE 's/.*"max_file_loc_error" *: *([0-9]+).*/\1/p' .clean-arch/config.json | head -n1)"
  [ -n "$v" ] && eng_err_lim="$v"
fi
engineering_json="$(bash "$SCRIPT_DIR/engineering_scan.sh" "$LIB" "$eng_warn_lim" "$eng_err_lim" 2>/dev/null)" || engineering_json=""
[ -n "$engineering_json" ] || engineering_json='{"total":0,"errors":0,"warnings":0,"thresholds":{},"checks":[]}'
eng_errors="$(printf '%s' "$engineering_json" | grep -oE '"errors": *[0-9]+' | head -n1 | grep -oE '[0-9]+$')"
eng_warnings="$(printf '%s' "$engineering_json" | grep -oE '"warnings": *[0-9]+' | head -n1 | grep -oE '[0-9]+$')"
eng_errors="${eng_errors:-0}"; eng_warnings="${eng_warnings:-0}"
top_eng="$(printf '%s' "$engineering_json" | tr -d '\n' | grep -oE '"id":"[^"]+","label":"[^"]+","severity":"error","category":"[^"]+","count":[1-9][0-9]*' | head -n1 | sed -E 's/.*"label":"([^"]+)".*/\1/')"

# ---- Template distance (simplified-architecture-with-domain.md) — primary signal ----
template_json="$(bash "$SCRIPT_DIR/template_compliance_scan.sh" . 2>/dev/null)" || template_json=""
[ -n "$template_json" ] || template_json='{"target":"simplified-architecture-with-domain","score":0,"distance":"very_far","blockers":0,"majors":0,"minors":0,"gaps":[],"checks":[]}'
tmpl_score="$(printf '%s' "$template_json" | grep -oE '"score": *[0-9]+' | head -n1 | grep -oE '[0-9]+$')"
tmpl_distance="$(printf '%s' "$template_json" | sed -nE 's/.*"distance": *"([a-z_]+)".*/\1/p' | head -n1)"
tmpl_blockers="$(printf '%s' "$template_json" | grep -oE '"blockers": *[0-9]+' | head -n1 | grep -oE '[0-9]+$')"
tmpl_majors="$(printf '%s' "$template_json" | grep -oE '"majors": *[0-9]+' | head -n1 | grep -oE '[0-9]+$')"
tmpl_score="${tmpl_score:-0}"; tmpl_distance="${tmpl_distance:-very_far}"
tmpl_blockers="${tmpl_blockers:-0}"; tmpl_majors="${tmpl_majors:-0}"

# ---- Status (driven by template distance, not GetX volume) ----
legacy=false
if [ "$getx_total" -gt 0 ] || { [ "$stateful" -gt 0 ] && [ "$bloc_files" -eq 0 ]; }; then legacy=true; fi
bloc_present=false
{ [ "$bloc_files" -gt 0 ] || [ "$has_flutter_bloc" = true ]; } && bloc_present=true

migration_prompt=false
if [ "$legacy" = true ] && [ "$bloc_files" -eq 0 ]; then migration_prompt=true; fi

case "$tmpl_distance" in
  compliant)
    if [ "$error_count" -eq 0 ] && [ "$eng_errors" -eq 0 ]; then
      if [ "$warning_count" -gt 0 ] || [ "$eng_warnings" -gt 0 ] || [ "$tmpl_majors" -gt 0 ]; then status="compliant_with_warnings"
      else status="compliant"; fi
    else status="non_compliant"; fi
    ;;
  approaching) status="compliant_with_warnings" ;;
  far|very_far)
    if [ "$migration_prompt" = true ]; then status="needs_migration"; else status="non_compliant"; fi
    ;;
  *) status="non_compliant" ;;
esac

# ---- Delta against a previous audit ----
delta_json=null
if [ -n "$PREV" ]; then
  pv() { grep -oE "\"$1\": *[0-9]+" "$PREV" | head -n1 | grep -oE '[0-9]+$'; }
  pstatus="$(sed -nE 's/^ *"status": *"([a-z_]+)".*/\1/p' "$PREV" | head -n1)"
  pgen="$(sed -nE 's/^ *"generated_at": *"([^"]+)".*/\1/p' "$PREV" | head -n1)"
  items=""
  for spec in "dart_files:dart_files:$total_files" "test_files:test_files:$test_files" \
              "template_score:score:$tmpl_score" "template_blockers:blockers:$tmpl_blockers" \
              "getx_usages:total:$getx_total" "files_importing_get:files_importing_get:$files_with_getx" \
              "violation_errors:errors:$error_count" "violation_warnings:warnings:$warning_count" \
              "engineering_errors:errors:$eng_errors" "engineering_warnings:warnings:$eng_warnings" \
              "bloc_files:bloc_files:$bloc_files" "stateful_widgets:stateful_widgets:$stateful"; do
    name="${spec%%:*}"; rest="${spec#*:}"; key="${rest%%:*}"; cur="${rest#*:}"
    # Prefer the metric under its section when ambiguous (errors/warnings appear twice)
    case "$name" in
      template_score) old="$(grep -A8 '"template"' "$PREV" | grep -oE '"score": *[0-9]+' | head -n1 | grep -oE '[0-9]+$')" ;;
      template_blockers) old="$(grep -A8 '"template"' "$PREV" | grep -oE '"blockers": *[0-9]+' | head -n1 | grep -oE '[0-9]+$')" ;;
      violation_errors) old="$(grep -A2 '"violations"' "$PREV" | grep -oE '"errors": *[0-9]+' | head -n1 | grep -oE '[0-9]+$')" ;;
      violation_warnings) old="$(grep -A2 '"violations"' "$PREV" | grep -oE '"warnings": *[0-9]+' | head -n1 | grep -oE '[0-9]+$')" ;;
      engineering_errors) old="$(grep -A5 '"engineering"' "$PREV" | grep -oE '"errors": *[0-9]+' | head -n1 | grep -oE '[0-9]+$')" ;;
      engineering_warnings) old="$(grep -A5 '"engineering"' "$PREV" | grep -oE '"warnings": *[0-9]+' | head -n1 | grep -oE '[0-9]+$')" ;;
      *) old="$(pv "$key")" ;;
    esac
    if [ -n "$old" ]; then item="{\"name\":\"$name\",\"from\":$old,\"to\":$cur,\"change\":$((cur - old))}"
    else item="{\"name\":\"$name\",\"from\":null,\"to\":$cur,\"change\":null}"; fi
    items="${items:+$items,}$item"
  done
  delta_json="{\"previous_generated_at\":\"$(jstr "$pgen")\",\"status\":{\"from\":\"$(jstr "$pstatus")\",\"to\":\"$status\"},\"metrics\":[$items]}"
fi

# ---- Directory structure (for the report illustration) ----
awk -F: '{ c[$1]++ } END { for (f in c) printf "%s\t%d\n", f, c[f] }' "$TMP/gx_all" > "$TMP/getx_by_file"
grep "${GREP_DART[@]}" -l -E "$RE_CUBIT" "$LIB" 2>/dev/null > "$TMP/bloc_list"
awk -F'\t' -v g="$TMP/getx_by_file" -v b="$TMP/bloc_list" '
  BEGIN { while ((getline l < g) > 0) { split(l, x, "\t"); cnt[x[1]] = x[2] + 0 }
          while ((getline l < b) > 0) bl[l] = 1 }
  { path = $0; n = split(path, a, "/"); pre = "lib"
    for (i = 2; i <= n - 1 && i <= 5; i++) { pre = pre "/" a[i]; tot[pre]++; gx[pre] += cnt[path]; if (path in bl) bc[pre]++; if (i == n - 1) direct[pre]++ } }
  END { for (k in tot) printf "%s\t%d\t%d\t%d\t%d\n", k, tot[k], gx[k] + 0, bc[k] + 0, direct[k] + 0 }
' "$TMP/files" | sort > "$TMP/structure_all"
structure_total="$(wc -l < "$TMP/structure_all" | tr -d ' ')"
head -n 800 "$TMP/structure_all" > "$TMP/structure"
structure_dirs="$(awk -F'\t' 'function q(s){gsub(/\\/,"/",s);gsub(/"/,"\047",s);return s}
  { printf "%s{\"path\":\"%s\",\"files\":%d,\"getx\":%d,\"blocs\":%d,\"direct\":%d}", (NR>1?",":""), q($1), $2, $3, $4, $5 }' "$TMP/structure")"
root_files="$(find "$LIB" -maxdepth 1 -name '*.dart' ! -name '*.g.dart' ! -name '*.gr.dart' ! -name '*.config.dart' ! -name 'app_localizations*.dart' 2>/dev/null | sort | sed 's#.*/##' | awk '{printf "%s\"%s\"", (NR>1?",":""), $0}')"

# ---- Feature candidates: discover legacy clusters → suggest lib/features/<name> ----
feat_write=""
outdir="${CLEAN_ARCH_DIR:-}"
[ -z "$outdir" ] && [ -d .clean-arch ] && outdir=".clean-arch"
[ -n "$outdir" ] && mkdir -p "$outdir" && feat_write="$outdir/feature-map.suggested.yaml"
export CA_GX_ALL="$TMP/gx_all" CA_BLOC_LIST="$TMP/bloc_list"
feat_raw="$(bash "$SCRIPT_DIR/feature_candidates_scan.sh" . ${feat_write:+--write "$feat_write"} 2>/dev/null)"
printf '%s' "$feat_raw" | python3 -c '
import json,sys
raw=sys.stdin.read().strip() or "{}"
try: d=json.loads(raw)
except Exception: d={}
cands=d.get("candidates") or []
out=sys.argv[1]
shapes=d.get("shapes") or {}
compact=json.dumps({
  "generated_at": d.get("generated_at",""),
  "candidates": cands,
  "order": d.get("order") or [],
  "new_count": int(d.get("new_count") or 0),
  "first_new": d.get("first_new") or "",
  "new_summary": d.get("new_summary") or "",
  "shapes": {
    "thin": int(shapes.get("thin") or 0),
    "repository": int(shapes.get("repository") or 0),
    "full": int(shapes.get("full") or 0),
  },
  "written": d.get("written") or "",
}, separators=(",",":"))
open(out+"/feat_disc.json","w").write(compact)
open(out+"/feat_meta.tsv","w").write("\t".join([
  str(int(d.get("new_count") or 0)),
  (d.get("first_new") or "").replace("\t"," "),
  (d.get("new_summary") or "").replace("\t"," "),
  (d.get("written") or "").replace("\t"," "),
]))
open(out+"/feat_suggested.json","w").write(",".join(json.dumps(c,separators=(",",":")) for c in cands))
' "$TMP" 2>/dev/null || true
feat_disc_json="$(cat "$TMP/feat_disc.json" 2>/dev/null || echo '{"candidates":[],"order":[],"new_count":0,"first_new":"","new_summary":"","written":""}')"
suggested_json="$(cat "$TMP/feat_suggested.json" 2>/dev/null || true)"
IFS="$(printf '\t')" read -r n_new first_new new_feats feat_map_written < "$TMP/feat_meta.tsv" 2>/dev/null || true
n_new="${n_new:-0}"; first_new="${first_new:-}"; new_feats="${new_feats:-}"; feat_map_written="${feat_map_written:-}"
unset IFS

# ---- Migration plan: feature by feature (only when there are GetX controllers to convert) ----
plan_json=null; plan_scope=""; plan_first=""; plan_units=0; plan_ctrls=0; tests_ok=true
if [ "$n_controller" -gt 0 ]; then
  # hand the plan what was already computed, so it does not scan the project again
  export CUBIT_BASES GETX_BASES CA_GX_ALL="$TMP/gx_all" CA_BLOC_LIST="$TMP/bloc_list"
  plan_json="$(bash "$SCRIPT_DIR/migration_plan.sh" . 2>/dev/null)"
  [ -n "$plan_json" ] || plan_json=null
  if [ "$plan_json" != null ]; then
    plan_scope="$(printf '%s' "$plan_json" | grep -oE '"scope": "[a-z]+"' | head -n1 | sed -E 's/.*: "([a-z]+)"/\1/')"
    plan_first="$(printf '%s' "$plan_json" | grep -oE '"waves": \[\{[^]]*\]' | head -n1 | sed -E 's/.*"units":\[//' | grep -oE '"[A-Za-z0-9_]+"' | head -n1 | tr -d '"')"
    printf '%s' "$plan_json" | grep -q '"tests_allowed": false' && tests_ok=false
    plan_units="$(printf '%s' "$plan_json" | grep -oE '"units": [0-9]+' | head -n1 | grep -oE '[0-9]+')"
    plan_ctrls="$(printf '%s' "$plan_json" | grep -oE '"controllers": [0-9]+' | head -n1 | grep -oE '[0-9]+')"
  fi
fi
plan_state=false; [ "$plan_scope" = state ] && plan_state=true

# ---- Next steps (one source of truth for the report and the terminal summary) ----
steps=""; step_n=0
add_step() { # id command title why
  step_n=$((step_n + 1))
  steps="${steps:+$steps,}{\"order\":$step_n,\"id\":\"$1\",\"command\":\"$(jstr "$2")\",\"title\":\"$(jstr "$3")\",\"why\":\"$(jstr "$4")\"}"
}
integ_files="$([ -d integration_test ] && find integration_test -name '*.dart' 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
integ_note=""; [ "${integ_files:-0}" -gt 0 ] && integ_note=" (integration_test/ has $integ_files file(s); Patrol adds native steps such as permission dialogs)"
top_rule="$(grep -o '"rule":"[^"]*"' "$TMP/viol" 2>/dev/null | sort | uniq -c | sort -rn | head -n1 | sed -E 's/^ *[0-9]+ "rule":"(.*)"$/\1/')"
router_state="no router package is installed yet"; { [ "$has_go_router" = true ] && router_state="go_router is installed"; } || { [ "$has_auto_route" = true ] && router_state="auto_route is installed"; }
di_state="no DI package is installed yet"; [ "$has_get_it" = true ] && di_state="get_it is installed"; [ "$has_provider" = true ] && di_state="provider is installed"

# Template gaps drive next steps (destination = simplified-architecture-with-domain.md)
if [ "$tmpl_blockers" -gt 0 ] || [ "$tmpl_majors" -gt 0 ]; then
  add_step template "(see report)" "Close the distance to Clean Architecture" "Score ${tmpl_score}/100 (${tmpl_distance}): ${tmpl_blockers} blocker(s), ${tmpl_majors} major(s). Fix blockers first (folders, router, Result/AppFailure, no HTTP in cubits, real features/)."
fi
if [ "$error_count" -gt 0 ]; then
  add_step fix-violations "check_dependencies.sh lib" "Fix the import-rule violations" "$error_count rule violation(s), most common: $top_rule. Fix them before moving more code, otherwise migration copies the problem."
fi
if [ "$eng_errors" -gt 0 ]; then
  add_step fix-engineering "(review)" "Fix software-engineering errors" "$eng_errors engineering error hit(s)${top_eng:+, e.g. $top_eng}. Layer leaks should be fixed before /feature --migrate copies them."
fi
# Foundation before feature moves when still far from the template
if [ "$tmpl_distance" = very_far ] || [ "$tmpl_score" -lt 40 ]; then
  add_step foundation "/foundation" "Scaffold Clean Architecture foundation" "Add bootstrap/, core/error (Result + AppFailure), design_system/; optional --router. Clears structure/error blockers before mass /feature --migrate. Keeps GetX nav unless you pass --router go_router|auto_route."
fi
if [ "$legacy" = true ] || [ "$tmpl_distance" != compliant ]; then
  add_step pre-check "/pre-check ${plan_first:-${first_new:-<feature>}}" "Check it is safe to start" "Clean git tree, a flutter analyze baseline and the impact of the first target."
  if [ "$has_patrol" = false ] && [ "$tmpl_distance" != very_far ]; then
    add_step e2e "/e2e" "Optional: protect the critical flows first" "No Patrol tests yet$integ_note."
  fi
  if [ "$n_new" -gt 0 ]; then
    add_step feature "/feature ${first_new} --migrate" "Move a feature into lib/features/<name>/" "$n_new candidate group(s): $new_feats. Prefer after foundation exists; pick thin/repo/full shape per the template."
  fi
  if [ "$n_nav" -gt 0 ] && [ "$plan_state" = false ]; then
    add_step route "/route" "Replace GetX navigation with go_router or auto_route" "$n_nav GetX navigation usage(s); $router_state. Required for template compliance."
  fi
  if [ "$n_lookup" -gt 0 ] && [ "$plan_state" = false ]; then
    if [ "$has_get_it" = true ] && [ "$has_provider" = false ]; then di_choice="get_it is already installed"
    elif [ "$has_provider" = true ] && [ "$has_get_it" = false ]; then di_choice="provider is already installed"
    else di_choice="$di_state"; fi
    add_step di "/di" "Wire composition root (get_it or provider), drop Get.put" "$n_lookup GetX lookup(s); $di_choice."
  fi
  if [ "$plan_state" = true ] && [ -n "$plan_first" ]; then
    add_step plan "/to-bloc $plan_first" "Convert a feature to Cubit/Bloc per the template" "Start with $plan_first. Plain Cubit/Bloc + sealed states only — no DataCubit; extract BondFire out of cubits."
  elif [ "$n_controller" -gt 0 ] || [ "$provider_notifier" -gt 0 ]; then
    add_step to-bloc "/to-bloc" "Convert state holders to Cubit/Bloc (template presentation)" "$n_controller GetX controller(s), $bloc_files existing cubit file(s). Destination: plain Cubit/Bloc + sealed Initial/Loading/Success/Failure — never DataCubit/BaseCubit/PaginatedCubit."
  fi
fi
# Custom cubit helpers are debt, not a migration destination
tmpl_custom_bases="$(printf '%s' "$template_json" | grep -oE '"custom_cubit_bases": *[0-9]+' | head -n1 | grep -oE '[0-9]+$' || echo 0)"
if [ "${tmpl_custom_bases:-0}" -gt 0 ]; then
  add_step drop-custom-bases "/to-bloc" "Replace DataCubit/BaseCubit/PaginatedCubit with Cubit/Bloc" "$tmpl_custom_bases custom cubit-base hit(s). Do not extend those helpers; fold loading/pagination into sealed state."
fi
if [ "$tests_ok" = true ] && { [ -n "$untested_list" ] || [ "$test_files" -eq 0 ]; }; then
  if [ "$test_files" -eq 0 ]; then add_step tests "clean-arch-testing" "Add tests" "No test files found. Start with use cases and cubits (bloc_test)."
  else add_step tests "clean-arch-testing" "Add tests for features without a test folder" "No test/features/<name> folder for: $untested_list."; fi
fi
if [ "$warning_count" -gt 0 ] || [ "$eng_warnings" -gt 0 ]; then
  add_step warnings "(review)" "Review the style and engineering warnings" "$warning_count import/style warning(s), $eng_warnings engineering warning(s) (file size, _buildX helpers, print, missing tests, literal colors)."
fi
if [ "$legacy" = false ] && [ "$has_patrol" = false ]; then
  add_step e2e "/e2e" "Protect the critical flows" "No Patrol tests yet$integ_note: add a few mock-backed end-to-end flows, including native permission and notification steps."
fi
if [ "$legacy" = false ] && [ "$error_count" -eq 0 ]; then
  add_step ci "check_dependencies.sh lib" "Keep it compliant" "Run the dependency checker in CI so new code cannot break the layer rules."
fi
add_step reaudit "/audit" "Re-run the audit after each step" "The report shows the change since the previous audit, so you can see the migration progress."

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
project="$(basename "$(pwd)")"

# ---- Design quality of Cubit/Bloc files (heuristic, catches a Cubit that is only a controller in disguise) ----
find "$LIB" \( -name '*_cubit.dart' -o -name '*_bloc.dart' \) ! -name '*.g.dart' 2>/dev/null > "$TMP/cubit_files"
find "$LIB" \( -name '*_cubit.dart' -o -name '*_bloc.dart' -o -name '*_state.dart' \) ! -name '*.g.dart' ! -name '*.freezed.dart' 2>/dev/null > "$TMP/state_files"
dq_hits() { # <ERE> <filelist>  -> JSON array of {file,line}
  if [ -s "$2" ]; then xargs grep -HnE -e "$1" < "$2" 2>/dev/null | hits_stdin; else printf '[]'; fi
}
dq_count() { if [ -s "$2" ]; then xargs grep -hcE -e "$1" < "$2" 2>/dev/null | awk '{s+=$1} END {print s+0}'; else echo 0; fi; }
Q_INFRA="^import 'package:(dio|http|shared_preferences|cloud_firestore|firebase_[a-z_]+|hive|hive_flutter|sqflite|get_storage|drift)/|^import '.*/data/(datasources|models|dto)/"
Q_GETX="\\bGet\\.[a-zA-Z]+|package:get/"
Q_CTX="\\bBuildContext\\b"
Q_NAMES="class [A-Za-z]*State(Loaded|Idle|Fetching|Done|Ok|Data|Error)\\b"
Q_MUTABLE="^  (List|Map|Set|bool|int|double|String|num)(<[^>]*>)?\\?? [a-z][A-Za-z0-9]*( =[^;]*)?;"
q_infra=$(dq_count "$Q_INFRA" "$TMP/cubit_files"); q_getx=$(dq_count "$Q_GETX" "$TMP/cubit_files")
q_ctx=$(dq_count "$Q_CTX" "$TMP/cubit_files"); q_names=$(dq_count "$Q_NAMES" "$TMP/state_files")
q_mut=$(dq_count "$Q_MUTABLE" "$TMP/state_files")
: > "$TMP/custom_base_hits"
grep "${GREP_DART[@]}" -e 'class[[:space:]].*extends[[:space:]]+(DataCubit|BaseCubit|PaginatedCubit)\b' "$LIB" 2>/dev/null \
  | grep -vE '<[^>]*extends[[:space:]]+(DataCubit|BaseCubit|PaginatedCubit)' \
  | grep -vE 'extends[[:space:]]+(StatelessWidget|StatefulWidget|HookWidget)\b' > "$TMP/custom_base_hits" || true
grep "${GREP_DART[@]}" -e '^[[:space:]]*(abstract[[:space:]]+)?(base[[:space:]]+)?class[[:space:]]+(DataCubit|BaseCubit|PaginatedCubit)\b' "$LIB" 2>/dev/null >> "$TMP/custom_base_hits" || true
sort -u "$TMP/custom_base_hits" -o "$TMP/custom_base_hits"
q_custom="$(wc -l < "$TMP/custom_base_hits" | tr -d ' ')"
q_custom_hits="$(hits_stdin < "$TMP/custom_base_hits")"
q_nonseal=0; q_nonseal_json="["
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if grep -qE "^(abstract )?class [A-Za-z]+State\\b" "$f" 2>/dev/null && ! grep -qE "sealed class|enum [A-Za-z]+Status|Equatable|equatable|freezed|@immutable" "$f" 2>/dev/null; then
    q_nonseal_json="$q_nonseal_json$([ "$q_nonseal" -gt 0 ] && echo ,){\"file\":\"$(jstr "$f")\",\"line\":1}"; q_nonseal=$((q_nonseal+1))
  fi
done < "$TMP/state_files"
q_nonseal_json="$q_nonseal_json]"
design_quality_total=$((q_infra+q_getx+q_ctx+q_names+q_mut+q_nonseal+q_custom))
design_quality_json="{\"total\": $design_quality_total, \"checks\": [
    {\"id\": \"cubit_imports_infrastructure\", \"label\": \"Cubit/Bloc imports Dio/http/storage/Firebase or data internals (call a repository or use case)\", \"count\": $q_infra, \"hits\": $(dq_hits "$Q_INFRA" "$TMP/cubit_files")},
    {\"id\": \"cubit_uses_getx\", \"label\": \"Cubit/Bloc still uses GetX\", \"count\": $q_getx, \"hits\": $(dq_hits "$Q_GETX" "$TMP/cubit_files")},
    {\"id\": \"cubit_uses_build_context\", \"label\": \"Cubit/Bloc references BuildContext (use a presentation event)\", \"count\": $q_ctx, \"hits\": $(dq_hits "$Q_CTX" "$TMP/cubit_files")},
    {\"id\": \"custom_cubit_base\", \"label\": \"Extends DataCubit/BaseCubit/PaginatedCubit (prefer Cubit or Bloc with sealed Initial/Loading/Success/Failure)\", \"count\": $q_custom, \"hits\": $q_custom_hits},
    {\"id\": \"state_names_nonstandard\", \"label\": \"State variants named Loaded/Idle/Fetching/Done/Ok/Data/Error instead of Initial/Loading/Success/Failure\", \"count\": $q_names, \"hits\": $(dq_hits "$Q_NAMES" "$TMP/state_files")},
    {\"id\": \"state_mutable_fields\", \"label\": \"State class with non-final fields (states must be immutable)\", \"count\": $q_mut, \"hits\": $(dq_hits "$Q_MUTABLE" "$TMP/state_files")},
    {\"id\": \"state_not_sealed_or_equatable\", \"label\": \"State file without sealed/enum status/Equatable\", \"count\": $q_nonseal, \"hits\": $q_nonseal_json}
  ]}"

cat <<JSON
{
  "project": "$(jstr "$project")",
  "generated_at": "$now",
  "status": "$status",
  "delta": $delta_json,
  "migration_prompt": $migration_prompt,
  "structure_ok": $structure_ok,
  "totals": {"dart_files": $total_files, "test_files": $test_files, "features": $(printf '%s' "$features_json" | grep -o '"name"' | wc -l | tr -d ' ')},
  "layers": $layers,
  "legacy_top_dirs": $legacy_dirs,
  "packages": {"get": $has_get, "flutter_bloc": $has_flutter_bloc, "get_it": $has_get_it, "provider": $has_provider, "go_router": $has_go_router, "auto_route": $has_auto_route, "patrol": $has_patrol},
  "state_management": {"bloc_files": $bloc_files, "bloc_present": $bloc_present, "stateful_widgets": $stateful, "set_state_calls": $setstate, "change_notifiers": $provider_notifier, "legacy": $legacy},
  "getx": {
    "total": $getx_total,
    "files_importing_get": $files_with_getx,
    "categories": [
      {"id": "import", "label": "package:get imports", "count": $n_import, "hits": $(gx_hits "$P_IMPORT")},
      {"id": "controller", "label": "GetX controllers (GetxController, GetxService, SuperController, subclasses)", "count": $n_controller, "hits": $(gx_hits "$P_CONTROLLER")},
      {"id": "widgets", "label": "Obx / GetX / GetBuilder / GetView / GetWidget / ValueBuilder", "count": $n_obx, "hits": $(gx_hits "$P_OBX")},
      {"id": "obs", "label": "Reactive state: .obs, Rx types, StateMixin, RxStatus, .obx", "count": $n_obs, "hits": $(gx_hits "$P_REACTIVE")},
      {"id": "navigation", "label": "Navigation: Get.to / toNamed / back, GetPage, GetMaterialApp, middlewares", "count": $n_nav, "hits": $(gx_hits "$P_NAV")},
      {"id": "lookup", "label": "Dependency injection: Get.find / put / lazyPut, Bindings", "count": $n_lookup, "hits": $(gx_hits "$P_LOOKUP")},
      {"id": "ui_helpers", "label": "UI helpers: Get.snackbar / dialog / bottomSheet / context / theme / locale, GetPlatform, GetUtils", "count": $n_ui, "hits": $(gx_hits "$P_UI")},
      {"id": "translations", "label": "Translations", "count": $n_transl, "hits": $(gx_hits "$P_TRANSL")},
      {"id": "network", "label": "GetConnect / GetHttpClient / GetSocket", "count": $n_net, "hits": $(gx_hits "$P_NET")},
      {"id": "workers", "label": "Workers: ever / once / debounce / interval", "count": $n_workers, "hits": $(gx_hits "$P_WORKERS")},
      {"id": "utils", "label": "Extensions: .tr, 2.seconds, capitalizeFirst, padding*/margin*, context.width ...", "count": $n_utils, "hits": $(head -n 200 "$TMP/ext_hits" | hits_stdin)},
      {"id": "other", "label": "Other Get.<member> calls", "count": $n_other, "hits": $(hits_stdin < "$TMP/other_get")}
    ]
  },
  "getx_packages": "$(jstr "$getx_pkgs")",
  "features": [${features_json}],
  "structure": {"root_files": [${root_files}], "total_dirs": ${structure_total:-0}, "truncated": $([ "${structure_total:-0}" -gt 800 ] && echo true || echo false), "dirs": [${structure_dirs}]},
  "suggested_features": [${suggested_json}],
  "feature_discovery": $feat_disc_json,
  "feature_map_suggested": "$(jstr "$feat_map_written")",
  "template": $template_json,
  "design_quality": $design_quality_json,
  "engineering": $engineering_json,
  "migration_plan": $plan_json,
  "next_steps": [${steps}],
  "coverage": {
    "checked": ["template distance vs simplified-architecture-with-domain.md (structure, stack, presentation, domain/data, errors, boundaries, composition)", "domain purity / import rules", "GetX inventory (secondary)", "Cubit design quality", "engineering heuristics", "feature candidates + suggested shape (thin/repository/full) and when repository interfaces / domain / use cases apply"],
    "not_checked": ["rule of three for shared code", "UI error/loading patterns", "test assertion quality", "cyclomatic complexity", "human confirmation of feature-map merges"]
  },
  "violations": {"count": $violation_count, "errors": $error_count, "warnings": $warning_count, "items": [${violations_json}]}
}
JSON
