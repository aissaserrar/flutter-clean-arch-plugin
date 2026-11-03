#!/usr/bin/env bash
# Distance from docs/simplified-architecture-with-domain.md (not GetX volume).
# Usage: template_compliance_scan.sh [project_root]
# Prints one JSON object. Read-only. Exit 0; exit 2 if no lib/.
set -u

ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "Cannot enter $ROOT" >&2; exit 2; }
LIB=lib
[ -d "$LIB" ] || { echo "No lib/" >&2; exit 2; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t tmpl)"
trap 'rm -rf "$TMP"' EXIT

jstr() { printf '%s' "$1" | tr -d '\000-\037' | sed -e 's/\\/\//g' -e 's/"/'"'"'/g' | cut -c1-240; }
pub() { [ -f pubspec.yaml ] && grep -qE "^[[:space:]]*$1:" pubspec.yaml && echo true || echo false; }
count_dart() { # dir
  [ -d "$1" ] || { echo 0; return; }
  find "$1" -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.gr.dart' ! -name '*.config.dart' 2>/dev/null | wc -l | tr -d ' '
}

: > "$TMP/checks"
pass_w=0; total_w=0; blockers=0; majors=0; minors=0

# id area severity weight pass detail label
emit() {
  local id="$1" area="$2" sev="$3" weight="$4" pass="$5" detail="$6" label="$7"
  total_w=$((total_w + weight))
  if [ "$pass" = true ]; then
    pass_w=$((pass_w + weight))
  else
    case "$sev" in
      blocker) blockers=$((blockers + 1)) ;;
      major) majors=$((majors + 1)) ;;
      minor) minors=$((minors + 1)) ;;
    esac
  fi
  printf '%s\n' "{\"id\":\"$(jstr "$id")\",\"area\":\"$area\",\"severity\":\"$sev\",\"weight\":$weight,\"pass\":$pass,\"label\":\"$(jstr "$label")\",\"detail\":\"$(jstr "$detail")\"}" >> "$TMP/checks"
}

# ---- Structure ----
n_screens="$(count_dart "$LIB/screens")"
n_features_src=0
n_real_features=0
if [ -d "$LIB/features" ]; then
  for fd in "$LIB/features"/*/; do
    [ -d "$fd" ] || continue
    src="$(find "$fd" -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' 2>/dev/null | wc -l | tr -d ' ')"
    n_features_src=$((n_features_src + src))
    # real feature: has presentation/ or (domain|data) with non-generated dart, or page/cubit at root
    if [ -d "${fd}presentation" ] || [ -d "${fd}domain" ] || find "$fd" -maxdepth 1 -name '*_page.dart' -o -name '*_cubit.dart' 2>/dev/null | grep -q .; then
      # exclude dto-only trees (only under data/dtos *.g.dart leftovers with no presentation)
      if [ "$(find "$fd" -name '*.dart' ! -name '*.g.dart' 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ]; then
        n_real_features=$((n_real_features + 1))
      elif [ -d "${fd}presentation" ] || [ -d "${fd}domain" ]; then
        n_real_features=$((n_real_features + 1))
      fi
    fi
  done
fi
# Fix real feature count more carefully
n_real_features=0
if [ -d "$LIB/features" ]; then
  for fd in "$LIB/features"/*/; do
    [ -d "$fd" ] || continue
    non_gen="$(find "$fd" -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' 2>/dev/null | wc -l | tr -d ' ')"
    [ "$non_gen" -gt 0 ] || continue
    n_real_features=$((n_real_features + 1))
  done
fi

emit "has_bootstrap" "structure" blocker 8 \
  "$([ -d "$LIB/bootstrap" ] && echo true || echo false)" \
  "$([ -d "$LIB/bootstrap" ] && echo present || echo missing)" \
  "lib/bootstrap/ (app_config + composition root)"

emit "has_router_dir" "structure" blocker 6 \
  "$([ -d "$LIB/router" ] && echo true || echo false)" \
  "$([ -d "$LIB/router" ] && echo present || echo missing)" \
  "lib/router/ (centralized routes)"

has_ds=false; [ -d "$LIB/design_system" ] && has_ds=true
emit "has_design_system" "structure" major 4 "$has_ds" \
  "$([ "$has_ds" = true ] && echo present || echo missing — UI still in widgets/modals)" \
  "lib/design_system/"

has_shared=false; { [ -d "$LIB/core" ] || [ -d "$LIB/common" ]; } && has_shared=true
emit "has_core_or_common" "structure" major 4 "$has_shared" \
  "$([ -d "$LIB/core" ] && echo lib/core || ([ -d "$LIB/common" ] && echo lib/common || echo missing))" \
  "lib/core/ or lib/common/ for shared infrastructure"

has_l10n=false; { [ -d "$LIB/l10n" ] || [ -d "$LIB/gen" ] || [ -d assets/i18n ]; } && has_l10n=true
emit "has_l10n" "structure" minor 2 "$has_l10n" \
  "$([ -d "$LIB/l10n" ] && echo l10n || ([ -d "$LIB/gen" ] && echo gen/slang || echo missing))" \
  "Localization folder (l10n/ or slang gen/)"

feat_first=false
if [ "$n_real_features" -gt 0 ] && [ "$n_features_src" -ge $((n_screens / 4 + 1)) ]; then feat_first=true; fi
# if screens still dominate heavily, fail
if [ "$n_screens" -gt 50 ] && [ "$n_features_src" -lt 20 ]; then feat_first=false; fi
emit "feature_first" "structure" blocker 12 "$feat_first" \
  "real_features=$n_real_features feature_src=$n_features_src screens_src=$n_screens" \
  "Feature-first: real features/<name>/ with source, not screens/-first"

# ---- Stack ----
has_fb="$(pub flutter_bloc)"
emit "pkg_flutter_bloc" "stack" blocker 6 "$has_fb" "$has_fb" "Package flutter_bloc"

has_bp="$(pub bloc_presentation)"
emit "pkg_bloc_presentation" "stack" major 5 "$has_bp" "$has_bp" "Package bloc_presentation (one-off effects)"

has_router_pkg=false
{ [ "$(pub go_router)" = true ] || [ "$(pub auto_route)" = true ]; } && has_router_pkg=true
emit "pkg_router" "stack" blocker 8 "$has_router_pkg" \
  "go_router=$(pub go_router) auto_route=$(pub auto_route)" \
  "Package go_router or auto_route"

get_material=false
grep -rqE --include='*.dart' 'GetMaterialApp' "$LIB" 2>/dev/null && get_material=true
router_ok=false
[ "$has_router_pkg" = true ] && [ "$get_material" = false ] && router_ok=true
# also pass if MaterialApp.router without GetMaterialApp
if [ "$get_material" = false ] && grep -rqE --include='*.dart' 'MaterialApp\.router' "$LIB" 2>/dev/null; then router_ok=true; fi
emit "router_not_getx" "stack" blocker 8 "$router_ok" \
  "GetMaterialApp=$get_material router_pkg=$has_router_pkg" \
  "App uses go_router/auto_route, not GetMaterialApp"

has_di=false
{ [ "$(pub get_it)" = true ] || [ "$(pub provider)" = true ]; } && has_di=true
emit "pkg_di" "stack" major 3 "$has_di" \
  "get_it=$(pub get_it) provider=$(pub provider)" \
  "Package get_it or provider"

# ---- Presentation ----
custom_bases="$(grep -rE --include='*.dart' 'class[[:space:]].*extends[[:space:]]+(DataCubit|BaseCubit|PaginatedCubit)\b' "$LIB" 2>/dev/null \
  | grep -vE '<[^>]*extends[[:space:]]+(DataCubit|BaseCubit|PaginatedCubit)' \
  | grep -vE 'extends[[:space:]]+(StatelessWidget|StatefulWidget)' | wc -l | tr -d ' ')"
no_custom=false; [ "$custom_bases" -eq 0 ] && no_custom=true
emit "plain_cubit_bloc" "presentation" major 8 "$no_custom" \
  "custom_base_subclasses=$custom_bases" \
  "Cubits extend Cubit/Bloc only (not DataCubit/BaseCubit/PaginatedCubit)"

# Skip frozen /feature --migrate copies (DEPRECATED header) — they are dead code.
bond_in_cubit="$(grep -rE --include='*_cubit.dart' --include='*_bloc.dart' 'BondFire|package:dio/|\bDio\b' "$LIB" 2>/dev/null \
  | while IFS= read -r line; do
      f="${line%%:*}"
      head -n 3 "$f" 2>/dev/null | grep -q "DEPRECATED: migrated by /feature --migrate" && continue
      echo "$line"
    done | wc -l | tr -d ' ')"
no_http_cubit=false; [ "$bond_in_cubit" -eq 0 ] && no_http_cubit=true
emit "cubit_no_http" "presentation" blocker 10 "$no_http_cubit" \
  "http_refs_in_cubit_files=$bond_in_cubit" \
  "Presentation does not call BondFire/Dio (use case, repository, or typed API client)"

bp_usage=false
grep -rqE --include='*.dart' 'BlocPresentationMixin|emitPresentation|bloc_presentation' "$LIB" 2>/dev/null && bp_usage=true
# pass if package absent is already major; usage is minor when package present
if [ "$has_bp" = true ]; then
  emit "uses_presentation_events" "presentation" minor 2 "$bp_usage" "$bp_usage" "One-off effects via bloc_presentation"
else
  emit "uses_presentation_events" "presentation" minor 2 false "bloc_presentation not installed" "One-off effects via bloc_presentation"
fi

# ---- Domain / data ----
n_use_cases="$(find "$LIB" -type d -name use_cases 2>/dev/null | wc -l | tr -d ' ')"
n_repo_ifaces="$(find "$LIB" -path '*/domain/repositories/*.dart' 2>/dev/null | wc -l | tr -d ' ')"
n_repo_impl="$(find "$LIB" -name '*_repository_impl.dart' 2>/dev/null | wc -l | tr -d ' ')"
# Domain layer present when at least one feature has domain/ with source — not required for pure thin apps,
# but Nology-scale apps need it somewhere. Score as major gap if zero.
n_entities="$(find "$LIB" -path '*/domain/entities/*.dart' 2>/dev/null | wc -l | tr -d ' ')"
has_domain=false
{ [ "$n_repo_ifaces" -gt 0 ] || [ "$n_use_cases" -gt 0 ] || [ "$n_entities" -gt 0 ]; } && has_domain=true
emit "has_domain_layer" "domain_data" major 8 "$has_domain" \
  "use_case_dirs=$n_use_cases repo_interfaces=$n_repo_ifaces entities=$n_entities" \
  "Domain layer exists (entities and/or repository interfaces and/or use cases)"

has_repo_impl=false; [ "$n_repo_impl" -gt 0 ] && has_repo_impl=true
emit "has_repository_impl" "domain_data" major 4 "$has_repo_impl" \
  "repository_impls=$n_repo_impl" \
  "Data layer repository implementations (*_repository_impl.dart)"

# Global models used as DTOs from cubits/screens
models_from_pres="$(grep -rE --include='*_cubit.dart' --include='*_bloc.dart' "import .*/models/" "$LIB" 2>/dev/null | wc -l | tr -d ' ')"
models_ok=false; [ "$models_from_pres" -eq 0 ] && models_ok=true
emit "dtos_not_in_presentation" "domain_data" major 6 "$models_ok" \
  "model_imports_in_cubits=$models_from_pres" \
  "DTOs/models stay in data/ (cubits do not import lib/models wire types)"

# ---- Errors ----
has_result=false
grep -rqE --include='*.dart' 'class Result\b|sealed class Result\b|typedef Result' "$LIB" 2>/dev/null && has_result=true
grep -rqE --include='*.dart' 'Success\(|Failure\(' "$LIB/core/error" "$LIB/common/error" 2>/dev/null && has_result=true
emit "has_result_type" "errors" blocker 8 "$has_result" "$has_result" "core/error Result (Success | Failure)"

has_app_failure=false
grep -rqE --include='*.dart' 'class AppFailure\b|sealed class AppFailure\b|abstract class AppFailure\b' "$LIB" 2>/dev/null && has_app_failure=true
emit "has_app_failure" "errors" blocker 6 "$has_app_failure" "$has_app_failure" "AppFailure hierarchy (not raw ApiError/DioException in domain)"

# ---- Boundaries ----
shared_leak=0
for shared in core common design_system; do
  [ -d "$LIB/$shared" ] || continue
  shared_leak=$((shared_leak + $(grep -rE --include='*.dart' "import .*/(screens|features)/" "$LIB/$shared" 2>/dev/null | wc -l | tr -d ' ')))
done
bound_ok=false; [ "$shared_leak" -eq 0 ] && bound_ok=true
emit "shared_no_features" "boundaries" major 6 "$bound_ok" \
  "shared_imports_of_screens_or_features=$shared_leak" \
  "core/common/design_system do not import screens/ or features/"

# ---- Composition ----
has_composition=false
{ [ -f "$LIB/bootstrap/global_providers.dart" ] || [ -f "$LIB/bootstrap/injection.dart" ] || ls "$LIB"/bootstrap/*provider* "$LIB"/bootstrap/*injection* 2>/dev/null | grep -q .; } && has_composition=true
emit "has_composition_root" "composition" major 5 "$has_composition" \
  "$([ "$has_composition" = true ] && echo bootstrap composition file || echo missing — DI likely in AppRunTasks/Get.put)" \
  "Composition root under bootstrap/"

n_feat_providers="$(find "$LIB/features" -maxdepth 2 \( -name '*_providers.dart' -o -name '*_di.dart' \) 2>/dev/null | wc -l | tr -d ' ')"
feat_prov_ok=false
# only require when real features exist
if [ "$n_real_features" -eq 0 ]; then feat_prov_ok=false
elif [ "$n_feat_providers" -gt 0 ]; then feat_prov_ok=true
fi
emit "feature_providers" "composition" minor 3 "$feat_prov_ok" \
  "feature_provider_files=$n_feat_providers real_features=$n_real_features" \
  "Feature *_providers.dart / *_di.dart wiring files"

get_put="$(grep -rE --include='*.dart' 'Get\.(put|lazyPut)\(' "$LIB" 2>/dev/null | wc -l | tr -d ' ')"
di_clean=false; [ "$get_put" -eq 0 ] && di_clean=true
emit "no_getx_di" "composition" major 5 "$di_clean" \
  "Get.put_lazyPut=$get_put" \
  "No Get.put/lazyPut (DI via get_it/provider composition root)"

# ---- Score ----
score=0
[ "$total_w" -gt 0 ] && score=$((pass_w * 100 / total_w))
distance=very_far
if [ "$blockers" -eq 0 ] && [ "$score" -ge 85 ]; then distance=compliant
elif [ "$blockers" -eq 0 ] && [ "$score" -ge 60 ]; then distance=approaching
elif [ "$score" -ge 35 ]; then distance=far
else distance=very_far
fi

checks_json="$(paste -sd, "$TMP/checks" 2>/dev/null)"

# Ordered gaps (failed checks, blockers first) — parse with python if available, else sed
gaps_json="[]"
if command -v python3 >/dev/null 2>&1; then
  gaps_json="$(python3 -c '
import json,sys
checks=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
failed=[c for c in checks if not c.get("pass")]
ord={"blocker":0,"major":1,"minor":2}
area_ord={"structure":0,"stack":1,"errors":2,"presentation":3,"domain_data":4,"boundaries":5,"composition":6}
failed.sort(key=lambda c:(ord.get(c.get("severity",""),9), area_ord.get(c.get("area",""),9), c.get("id","")))
print(json.dumps([{"severity":c["severity"],"area":c["area"],"id":c["id"],"label":c["label"]} for c in failed[:20]]))
' "$TMP/checks")"
else
  gaps_json="[]"
fi

cat <<JSON
{
  "target": "simplified-architecture-with-domain",
  "score": $score,
  "max_score": 100,
  "passed_weight": $pass_w,
  "total_weight": $total_w,
  "distance": "$distance",
  "blockers": $blockers,
  "majors": $majors,
  "minors": $minors,
  "stats": {
    "screens_dart": $n_screens,
    "features_dart": $n_features_src,
    "real_features": $n_real_features,
    "custom_cubit_bases": $custom_bases,
    "http_in_cubits": $bond_in_cubit
  },
  "gaps": $gaps_json,
  "checks": [${checks_json}]
}
JSON
