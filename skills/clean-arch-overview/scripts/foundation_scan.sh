#!/usr/bin/env bash
# Detects what Clean Architecture foundation pieces are missing.
# Usage: foundation_scan.sh [project_root]
# Prints one JSON document. Read-only. Exit 0 = ok, 2 = no lib/.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "Cannot enter $ROOT" >&2; exit 2; }
[ -d lib ] || { echo "No lib/ directory found in $ROOT" >&2; exit 2; }

. "$SCRIPT_DIR/detect.sh" 2>/dev/null || true
eval "$(bash "$SCRIPT_DIR/conventions_scan.sh" . --env 2>/dev/null)" || true

jstr() { printf '%s' "$1" | tr -d '\000-\037' | sed -e 's/\\/\//g' -e 's/"/'"'"'/g'; }
exists_dir() { [ -d "$1" ] && echo true || echo false; }
exists_file() { [ -f "$1" ] && echo true || echo false; }

has_bootstrap="$(exists_dir lib/bootstrap)"
has_router="$(exists_dir lib/router)"
has_design="$(exists_dir lib/design_system)"
has_core="$(exists_dir lib/core)"
has_common="$(exists_dir lib/common)"
shared=core
[ "$has_common" = true ] && [ "$has_core" = false ] && shared=common
[ "$has_core" = true ] && shared=core

has_error_dir="$(exists_dir "lib/$shared/error")"
has_result=false
has_app_failure=false
if [ -d "lib/$shared" ]; then
  grep -rlE --include='*.dart' 'sealed class Result|class Result<' "lib/$shared" 2>/dev/null | grep -q . && has_result=true
  grep -rlE --include='*.dart' 'class AppFailure|abstract .*AppFailure' "lib/$shared" 2>/dev/null | grep -q . && has_app_failure=true
fi

has_app_config="$(exists_file lib/bootstrap/app_config.dart)"
has_injection="$(exists_file lib/bootstrap/injection.dart)"
has_global_providers="$(exists_file lib/bootstrap/global_providers.dart)"

pub_has() { [ -f pubspec.yaml ] && grep -qE "^[[:space:]]*$1:" pubspec.yaml && echo true || echo false; }
has_get_it="$(pub_has get_it)"
has_provider="$(pub_has provider)"
has_go_router="$(pub_has go_router)"
has_auto_route="$(pub_has auto_route)"
has_bloc_presentation="$(pub_has bloc_presentation)"
has_get="$(pub_has get)"

uses_get_material=false
grep -rqE --include='*.dart' '\bGetMaterialApp\b' lib 2>/dev/null && uses_get_material=true

# DI preference for bootstrap stub
di=get_it
[ "$has_get_it" = true ] && [ "$has_provider" = false ] && di=get_it
[ "$has_provider" = true ] && [ "$has_get_it" = false ] && di=provider
[ "$has_get_it" = true ] && [ "$has_provider" = true ] && di=get_it
[ "$has_get_it" = false ] && [ "$has_provider" = false ] && di=ask

# Router recommendation: skip when GetX nav is project convention or GetMaterialApp present without router pkg
router_rec=ask
if [ "$has_go_router" = true ]; then router_rec=go_router
elif [ "$has_auto_route" = true ]; then router_rec=auto_route
elif [ "${CONV_SCOPE:-}" = state ] || [ "$uses_get_material" = true ]; then router_rec=none
fi

# Planned creates (missing only)
planned=""
add_plan() { # path reason
  planned="${planned:+$planned,}{\"path\":\"$(jstr "$1")\",\"reason\":\"$(jstr "$2")\",\"exists\":false}"
}
[ "$has_bootstrap" = false ] && add_plan "lib/bootstrap/" "composition root folder"
[ "$has_app_config" = false ] && add_plan "lib/bootstrap/app_config.dart" "AppConfig stub"
if [ "$di" = get_it ] || [ "$di" = ask ]; then
  [ "$has_injection" = false ] && add_plan "lib/bootstrap/injection.dart" "get_it composition root stub"
fi
if [ "$di" = provider ]; then
  [ "$has_global_providers" = false ] && add_plan "lib/bootstrap/global_providers.dart" "provider composition root stub"
fi
[ "$has_core" = false ] && [ "$has_common" = false ] && add_plan "lib/core/" "shared infrastructure folder"
[ "$has_error_dir" = false ] && add_plan "lib/$shared/error/" "error types folder"
if [ "$has_result" = false ] || [ "$has_app_failure" = false ]; then
  add_plan "lib/$shared/error/result.dart" "Result + AppFailure"
fi
[ "$has_design" = false ] && add_plan "lib/design_system/" "design system folder (README placeholder)"

# Missing packages (advisory — command does not pub add)
missing_pkgs=""
add_pkg() { missing_pkgs="${missing_pkgs:+$missing_pkgs,}\"$1\""; }
[ "$has_bloc_presentation" = false ] && add_pkg "bloc_presentation"
[ "$di" = get_it ] && [ "$has_get_it" = false ] && add_pkg "get_it"
[ "$di" = provider ] && [ "$has_provider" = false ] && add_pkg "provider"

# ---- Design system candidates (legacy shared UI / theme outside design_system/) ----
# high: lib/widgets/, lib/config/themes/ (and figma tokens under themes)
# low: lib/modals/ (often feature-coupled — list only; migrate only with --migrate-ds modals|all)
ds_candidates=""
add_ds() { # id from_root to_root confidence
  local id="$1" from="$2" to="$3" conf="$4"
  [ -d "$from" ] || return 0
  # already under design_system — nothing to do
  case "$from" in lib/design_system/*|lib/design_system) return 0 ;; esac
  local n sample
  # Already migrated: destination has dart files and sources look deprecated
  if [ -d "$to" ] && find "$to" -name '*.dart' 2>/dev/null | grep -q .; then
    local deprecated
    deprecated="$(find "$from" -name '*.dart' 2>/dev/null | head -n 3 | while read -r f; do
      head -n 2 "$f" 2>/dev/null | grep -q "DEPRECATED: migrated by /feature" && echo 1
    done | head -n 1)"
    [ -n "$deprecated" ] && return 0
  fi
  n="$(find "$from" -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' 2>/dev/null | wc -l | tr -d ' ')"
  [ "${n:-0}" -gt 0 ] || return 0
  sample="$(find "$from" -name '*.dart' ! -name '*.g.dart' 2>/dev/null | sort | head -n 5 | awk '{printf "%s\"%s\"", (NR>1?",":""), $0}')"
  ds_candidates="${ds_candidates:+$ds_candidates,}{\"id\":\"$(jstr "$id")\",\"from\":\"$(jstr "$from")\",\"to\":\"$(jstr "$to")\",\"files\":$n,\"confidence\":\"$conf\",\"sample\":[${sample}],\"action\":\"copy_keep_deprecated\"}"
}
add_ds widgets "lib/widgets" "lib/design_system/widgets" high
add_ds themes "lib/config/themes" "lib/design_system/theme" high
# alternate theme locations
add_ds theme_root "lib/theme" "lib/design_system/theme" high
add_ds themes_alt "lib/themes" "lib/design_system/theme" high
add_ds ui_kit "lib/ui_kit" "lib/design_system/widgets" high
add_ds components "lib/components" "lib/design_system/widgets" medium
add_ds modals "lib/modals" "lib/design_system/modals" low

blockers_addressed='["has_bootstrap","has_app_failure","has_result_type"]'
[ "$has_design" = false ] && blockers_addressed='["has_bootstrap","has_app_failure","has_result_type","has_design_system"]'

cat <<JSON
{
  "project": "$(jstr "$(basename "$(pwd)")")",
  "shared_folder": "$shared",
  "di": "$di",
  "router_recommendation": "$router_rec",
  "conventions": {
    "scope": "$(jstr "${CONV_SCOPE:-}")",
    "mode": "$(jstr "${CONV_MODE:-}")",
    "basis": "$(jstr "${CONV_BASIS:-}")"
  },
  "present": {
    "bootstrap": $has_bootstrap,
    "bootstrap_app_config": $has_app_config,
    "bootstrap_injection": $has_injection,
    "bootstrap_global_providers": $has_global_providers,
    "router": $has_router,
    "design_system": $has_design,
    "core": $has_core,
    "common": $has_common,
    "error_dir": $has_error_dir,
    "result": $has_result,
    "app_failure": $has_app_failure,
    "get_material_app": $uses_get_material
  },
  "packages": {
    "get_it": $has_get_it,
    "provider": $has_provider,
    "go_router": $has_go_router,
    "auto_route": $has_auto_route,
    "bloc_presentation": $has_bloc_presentation,
    "get": $has_get
  },
  "missing_packages": [${missing_pkgs}],
  "planned_creates": [${planned}],
  "design_system_candidates": [${ds_candidates}],
  "design_system_note": "High-confidence folders (widgets/, themes/) can be copied into lib/design_system/ with --migrate-ds. Originals stay deprecated; imports are rewritten. Prefer high only; modals are low confidence (feature-coupled).",
  "blockers_addressed_without_router": $blockers_addressed,
  "router_note": "Creating lib/router/ and installing go_router|auto_route is opt-in (--router). Projects that keep GetX navigation (scope=state or GetMaterialApp) should pass --router none."
}
JSON
