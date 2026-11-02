#!/usr/bin/env bash
# Audits a Flutter project for Clean Architecture compliance and GetX leakage.
# Usage: audit.sh [project_root] [previous_audit.json]   (default root: current directory)
# Prints a single JSON document on stdout. Read-only: writes nothing, no network.
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

# ---- GetX leakage patterns (BSD/GNU grep -E compatible, no \b) ----
NB='(^|[^A-Za-z0-9_])'
P_IMPORT="import +['\"]package:get/"
P_CONTROLLER="${NB}(GetxController|GetxService|GetLifeCycle)([^A-Za-z0-9_]|\$)"
P_OBX="${NB}(Obx|ObxValue|GetX|GetBuilder)(<[^>]*>)?\\("
P_NAV="${NB}Get\\.(to|toNamed|off|offNamed|offAll|offAllNamed|back|dialog|defaultDialog|snackbar|bottomSheet|context|width|height)([^A-Za-z0-9_]|\$)|${NB}GetMaterialApp|${NB}GetPage[<(]|${NB}Get\\.(rawSnackbar)"
P_LOOKUP="${NB}Get\\.(find|put|lazyPut|putAsync|delete|isRegistered)([^A-Za-z0-9_]|\$)|${NB}(Bindings|Binding)([^A-Za-z0-9_]|\$)"
P_ALL="$P_IMPORT|$P_CONTROLLER|$P_OBX|\\.obs([^A-Za-z0-9_]|\$)|${NB}Get\\.[a-zA-Z]+|${NB}GetMaterialApp"

n_import="$(count_hits "$P_IMPORT")"
n_controller="$(count_hits "$P_CONTROLLER")"
n_obx="$(count_hits "$P_OBX")"
n_obs="$(count_hits "\\.obs([^A-Za-z0-9_]|\$)")"
n_nav="$(count_hits "$P_NAV")"
n_lookup="$(count_hits "$P_LOOKUP")"
getx_total=$((n_import + n_controller + n_obx + n_obs + n_nav + n_lookup))

files_with_getx="$(grep "${GREP_DART[@]}" -l -e "$P_IMPORT" "$LIB" 2>/dev/null | wc -l | tr -d ' ')"

# ---- Other state management ----
bloc_files="$(grep "${GREP_DART[@]}" -l -E "extends +(Hydrated)?(Cubit|Bloc)<" "$LIB" 2>/dev/null | wc -l | tr -d ' ')"
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
    } else if ($2 == "core" || $2 == "design_system" || $2 == "l10n" || $2 == "bootstrap" || $2 == "router") {
      layer = $2
    } else if (NF == 2) { layer = "root" }
    c[layer]++
    if (layer == "other") top[$2]++ }
  END {
    n = split("domain data presentation feature_root core design_system l10n bootstrap router root other", k, " ")
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
    f_bloc="$(grep -rlE --include='*.dart' "extends +(Hydrated)?(Cubit|Bloc)<" "$fd" 2>/dev/null | wc -l | tr -d ' ')"
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
# reusable UI does not belong in core/
[ -d "$LIB/core" ] && out="$(grep "${GREP_DART[@]}" -e "extends +(StatelessWidget|StatefulWidget|HookWidget)" "$LIB/core" 2>/dev/null)" || out=""
add_hits "widget in core/ (reusable UI belongs in design_system/)" "core" "$out" warning
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

# ---- Status ----
legacy=false
if [ "$getx_total" -gt 0 ] || { [ "$stateful" -gt 0 ] && [ "$bloc_files" -eq 0 ]; }; then legacy=true; fi
bloc_present=false
{ [ "$bloc_files" -gt 0 ] || [ "$has_flutter_bloc" = true ]; } && bloc_present=true

migration_prompt=false
if [ "$legacy" = true ] && [ "$bloc_files" -eq 0 ]; then migration_prompt=true; fi

if [ "$getx_total" -eq 0 ] && [ "$error_count" -eq 0 ] && [ "$structure_ok" = true ] && [ "$bloc_files" -gt 0 ]; then
  if [ "$warning_count" -gt 0 ]; then status="compliant_with_warnings"; else status="compliant"; fi
elif [ "$migration_prompt" = true ]; then
  status="needs_migration"
else
  status="non_compliant"
fi

# ---- Delta against a previous audit ----
delta_json=null
if [ -n "$PREV" ]; then
  pv() { grep -oE "\"$1\": *[0-9]+" "$PREV" | head -n1 | grep -oE '[0-9]+$'; }
  pstatus="$(sed -nE 's/^ *"status": *"([a-z_]+)".*/\1/p' "$PREV" | head -n1)"
  pgen="$(sed -nE 's/^ *"generated_at": *"([^"]+)".*/\1/p' "$PREV" | head -n1)"
  items=""
  for spec in "dart_files:dart_files:$total_files" "test_files:test_files:$test_files" "getx_usages:total:$getx_total" "files_importing_get:files_importing_get:$files_with_getx" \
              "violation_errors:errors:$error_count" "violation_warnings:warnings:$warning_count" "bloc_files:bloc_files:$bloc_files" "stateful_widgets:stateful_widgets:$stateful"; do
    name="${spec%%:*}"; rest="${spec#*:}"; key="${rest%%:*}"; cur="${rest#*:}"
    old="$(pv "$key")"
    if [ -n "$old" ]; then item="{\"name\":\"$name\",\"from\":$old,\"to\":$cur,\"change\":$((cur - old))}"
    else item="{\"name\":\"$name\",\"from\":null,\"to\":$cur,\"change\":null}"; fi
    items="${items:+$items,}$item"
  done
  delta_json="{\"previous_generated_at\":\"$(jstr "$pgen")\",\"status\":{\"from\":\"$(jstr "$pstatus")\",\"to\":\"$status\"},\"metrics\":[$items]}"
fi

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
project="$(basename "$(pwd)")"

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
      {"id": "import", "label": "package:get imports", "count": $n_import, "hits": $(hits_json "$P_IMPORT")},
      {"id": "controller", "label": "GetxController / GetxService", "count": $n_controller, "hits": $(hits_json "$P_CONTROLLER")},
      {"id": "widgets", "label": "Obx / GetX / GetBuilder", "count": $n_obx, "hits": $(hits_json "$P_OBX")},
      {"id": "obs", "label": ".obs reactive vars", "count": $n_obs, "hits": $(hits_json "\\.obs([^A-Za-z0-9_]|\$)")},
      {"id": "navigation", "label": "Get.to / Get.toNamed / dialogs / GetMaterialApp", "count": $n_nav, "hits": $(hits_json "$P_NAV")},
      {"id": "lookup", "label": "Get.find / Get.put / Bindings", "count": $n_lookup, "hits": $(hits_json "$P_LOOKUP")}
    ]
  },
  "features": [${features_json}],
  "coverage": {
    "checked": ["domain purity", "presentation does not import data", "data does not import presentation", "no cross-feature imports", "core/design_system do not import features", "wiring only in *_providers.dart / *_di.dart", "no part/part of outside generated code", "no widgets in core/", "GetX usage", "BLoC/Cubit presence", "feature tests folder exists"],
    "not_checked": ["state class naming (Initial/Loading/Success/Failure)", "use case / repository shape per feature", "rule of three for core/", "UI error and loading patterns", "test quality and coverage"]
  },
  "violations": {"count": $violation_count, "errors": $error_count, "warnings": $warning_count, "items": [${violations_json}]}
}
JSON
