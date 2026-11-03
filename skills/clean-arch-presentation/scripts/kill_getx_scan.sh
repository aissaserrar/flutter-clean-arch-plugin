#!/usr/bin/env bash
# Inventory of GetX usage per file, split into what /kill-getx handles and what other commands own.
# Usage: kill_getx_scan.sh [project_root] [target ...]   (target = feature name, path, or empty for all of lib/)
# Prints one JSON document on stdout. Read-only: writes nothing, no network.
# Files carrying the "DEPRECATED: migrated by /feature --migrate" header are skipped (frozen originals).
# Exit code 0 = ok, 2 = no lib/ directory.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT="${1:-.}"; [ $# -gt 0 ] && shift
cd "$ROOT" 2>/dev/null || { echo "Cannot enter $ROOT" >&2; exit 2; }
[ -d lib ] || { echo "No lib/ directory found in $ROOT" >&2; exit 2; }
. "$SCRIPT_DIR/../../clean-arch-overview/scripts/detect.sh"
eval "$(bash "$SCRIPT_DIR/../../clean-arch-overview/scripts/conventions_scan.sh" "$PWD" --env 2>/dev/null)"
: "${CONV_MODE:=direct}" "${CONV_CN_FORBIDDEN:=false}"
detect_bases

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t killgetx)"
trap 'rm -rf "$TMP"' EXIT
jstr() { printf '%s' "$1" | tr -d '\000-\037' | sed -e 's/\\/\//g' -e 's/"/'"'"'/g'; }

# ---- Targets ----
: > "$TMP/files"; : > "$TMP/unresolved"
if [ $# -eq 0 ]; then set -- lib; fi
for t in "$@"; do
  case "$t" in */*|*.dart) ;; *) if u="$(resolve_target "$t")"; then printf '%s\n' "$u" >> "$TMP/files"; continue; fi ;; esac
  if [ -d "lib/features/$t" ]; then p="lib/features/$t"
  elif [ -e "$t" ]; then p="$t"
  elif [ -e "lib/$t" ]; then p="lib/$t"
  else echo "$t" >> "$TMP/unresolved"; continue; fi
  if [ -d "$p" ]; then find "$p" -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.gr.dart' ! -name '*.config.dart' ! -name 'app_localizations*.dart' 2>/dev/null >> "$TMP/files"
  else printf '%s\n' "$p" >> "$TMP/files"; fi
done
sort -u "$TMP/files" -o "$TMP/files"

# Every pattern comes from the GetX catalog in detect.sh (built from the package's API reference)
P_IMPORT="$RE_GX_IMPORT"
P_CONTROLLER="$RE_GETX"
P_WIDGETS="${GX_NB}(Obx|ObxValue|ObxWidget|GetX|GetBuilder|MixinBuilder|SimpleBuilder|ValueBuilder)(<[^>]*>)?[(]"
P_VIEW="extends +(GetView|GetWidget|GetResponsiveView|GetResponsiveWidget)${GX_END}"
P_OBS="$RE_GX_REACTIVE"
P_LIFE="void +(onInit|onReady|onClose|onStart|onDelete)[(]|$RE_GX_WORKERS"
P_ROUTE="$RE_GX_NAV"
P_DI="$RE_GX_DI"
P_MANUAL="$RE_GX_UI|$RE_GX_TRANSLATIONS|$RE_GX_NET|$RE_GX_STREAMS"

c() { grep -cE "$1" "$2" 2>/dev/null || true; }

# Only files that can contain GetX are inspected (one fast pass), instead of ten greps on every file
xargs grep -lE "$RE_GX_PREFILTER|$RE_GETX" < "$TMP/files" 2>/dev/null > "$TMP/cand" || : > "$TMP/cand"
: > "$TMP/rows"; skipped_deprecated=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if head -n 3 "$f" 2>/dev/null | grep -q "DEPRECATED: migrated by /feature --migrate"; then skipped_deprecated=$((skipped_deprecated + 1)); continue; fi
  n_imp="$(c "$P_IMPORT" "$f")"; n_ctl="$(c "$P_CONTROLLER" "$f")"; n_wid="$(c "$P_WIDGETS" "$f")"; n_view="$(c "$P_VIEW" "$f")"
  n_obs="$(c "$P_OBS" "$f")"; n_life="$(c "$P_LIFE" "$f")"; n_route="$(c "$P_ROUTE" "$f")"; n_di="$(c "$P_DI" "$f")"; n_man="$(c "$P_MANUAL" "$f")"
  # extension utilities (.tr, 2.seconds, padding*, context.width ...) count only where package:get is imported
  if [ "$n_imp" -gt 0 ]; then n_man=$((n_man + $(c "$RE_GX_EXT" "$f"))); fi
  # Get.<member> that is not navigation, DI or UI (a member the catalog does not know yet)
  n_man=$((n_man + $(grep -E "$RE_GX_OTHER_GET" "$f" 2>/dev/null | grep -cvE "$RE_GX_NAV|$RE_GX_DI|$RE_GX_UI" || true)))
  total=$((n_imp + n_ctl + n_wid + n_view + n_obs + n_life + n_route + n_di + n_man))
  [ "$total" -gt 0 ] || continue
  if [ "$n_ctl" -gt 0 ]; then kind="controller"; elif [ "$n_wid" -gt 0 ] || [ "$n_view" -gt 0 ]; then kind="view"; else kind="other"; fi
  printf '%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n' "$f" "$kind" "$n_imp" "$n_ctl" "$n_wid" "$n_view" "$n_obs" "$n_life" "$n_route" "$n_di" "$n_man" >> "$TMP/rows"
done < "$TMP/cand"

# Work order: controllers first (state before the UI that reads it), then views, then the rest.
awk -F'\t' '{ o = ($2=="controller") ? 1 : (($2=="view") ? 2 : 3); print o "\t" $0 }' "$TMP/rows" | sort -k1,1n -k2,2 | cut -f2- > "$TMP/sorted"

files_json="$(awk -F'\t' 'function c(s){gsub(/\\/,"/",s);gsub(/"/,"\047",s);return s}
  { handled = $4 + $5 + $6 + $7 + $8; deferred = $9 + $10; manual = $11
    printf "%s{\"file\":\"%s\",\"kind\":\"%s\",\"counts\":{\"import\":%d,\"controller\":%d,\"widgets\":%d,\"view\":%d,\"obs\":%d,\"lifecycle\":%d,\"route\":%d,\"di\":%d,\"manual\":%d},\"handled_here\":%d,\"deferred\":%d,\"manual\":%d}", (n++?",":""), c($1), $2, $3,$4,$5,$6,$7,$8,$9,$10,$11, handled, deferred, manual }' "$TMP/sorted")"
totals="$(awk -F'\t' '{ for (i = 3; i <= 11; i++) t[i] += $i; if ($2=="controller") k1++; else if ($2=="view") k2++; else k3++ }
  END { printf "{\"files\":%d,\"controllers\":%d,\"views\":%d,\"other\":%d,\"import\":%d,\"controller\":%d,\"widgets\":%d,\"view\":%d,\"obs\":%d,\"lifecycle\":%d,\"route\":%d,\"di\":%d,\"manual\":%d}", NR, k1+0, k2+0, k3+0, t[3]+0, t[4]+0, t[5]+0, t[6]+0, t[7]+0, t[8]+0, t[9]+0, t[10]+0, t[11]+0 }' "$TMP/rows")"
arr() { awk 'BEGIN{printf "["} {g=$0; gsub(/\\/,"/",g); gsub(/"/,"\047",g); printf "%s\"%s\"", (NR>1?",":""), g} END{printf "]"}' "$1"; }
pkg_get=false; [ -f pubspec.yaml ] && grep -qE "^[[:space:]]*get:" pubspec.yaml && pkg_get=true
has_bloc=false; [ -f pubspec.yaml ] && grep -qE "^[[:space:]]*flutter_bloc:" pubspec.yaml && has_bloc=true
has_go_router=false; [ -f pubspec.yaml ] && grep -qE "^[[:space:]]*go_router:" pubspec.yaml && has_go_router=true
has_auto_route=false; [ -f pubspec.yaml ] && grep -qE "^[[:space:]]*auto_route:" pubspec.yaml && has_auto_route=true
other_router=false; { [ "$has_go_router" = true ] || [ "$has_auto_route" = true ]; } && other_router=true

# Routing state of the whole project (not only the targets): GetX navigation or a GetX app root still present?
route_hits="$(grep -rEh --include='*.dart' "$P_ROUTE" lib 2>/dev/null | wc -l | tr -d ' ')"
route_files="$(grep -rlE --include='*.dart' "$P_ROUTE" lib 2>/dev/null | wc -l | tr -d ' ')"
app_root="$(grep -rlE --include='*.dart' "${GX_NB}(GetMaterialApp|GetCupertinoApp)" lib 2>/dev/null | wc -l | tr -d ' ')"
needs_route_first=false
if { [ "${route_hits:-0}" -gt 0 ] || [ "${app_root:-0}" -gt 0 ]; } && [ "$other_router" = false ]; then needs_route_first=true; fi
route_incomplete=false
if { [ "${route_hits:-0}" -gt 0 ] || [ "${app_root:-0}" -gt 0 ]; } && [ "$other_router" = true ]; then route_incomplete=true; fi

# Controllers in the targets + direct mode (the default, or a project that forbids ChangeNotifier): /to-bloc converts them straight to Cubits
n_ctl_files="$(awk -F'\t' '$2=="controller"' "$TMP/sorted" | wc -l | tr -d ' ')"
redirect=""; if { [ "$CONV_CN_FORBIDDEN" = true ] || [ "$CONV_MODE" = direct ]; } && [ "${n_ctl_files:-0}" -gt 0 ]; then redirect="to-bloc"; fi

cat <<JSON
{
  "project": "$(jstr "$(basename "$(pwd)")")",
  "conventions": {"change_notifier_forbidden": $CONV_CN_FORBIDDEN, "mode": "$CONV_MODE", "controller_files": ${n_ctl_files:-0}},
  "redirect": "$redirect",
  "unresolved_targets": $(arr "$TMP/unresolved"),
  "skipped_deprecated_copies": $skipped_deprecated,
  "pubspec": {"get": $pkg_get, "flutter_bloc": $has_bloc, "go_router": $has_go_router, "auto_route": $has_auto_route},
  "routing": {"getx_navigation_hits": ${route_hits:-0}, "getx_navigation_files": ${route_files:-0}, "getx_app_root_files": ${app_root:-0}, "other_router_installed": $other_router, "needs_route_first": $needs_route_first, "route_migration_incomplete": $route_incomplete},
  "totals": $totals,
  "ownership": {
    "this_command": ["import", "controller", "widgets", "view", "obs", "lifecycle"],
    "route_command": ["route"],
    "di_command": ["di"],
    "manual": ["manual"]
  },
  "files": [${files_json}]
}
JSON
