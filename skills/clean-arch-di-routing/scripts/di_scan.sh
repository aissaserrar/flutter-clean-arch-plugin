#!/usr/bin/env bash
# Inventory for /di: what exists to be registered (per feature), likely dependencies, and how DI is done today.
# Usage: di_scan.sh [project_root]
# Prints one JSON document on stdout. Read-only: writes nothing, no network.
# Roles are detected from names and declarations; dependencies are the types of `final` fields (approximate).
# The command re-reads every file before generating registrations.
# Skips frozen originals (header "DEPRECATED: migrated by /feature --migrate").
# Exit code 0 = ok, 2 = no lib/ directory.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "Cannot enter $ROOT" >&2; exit 2; }
[ -d lib ] || { echo "No lib/ directory found in $ROOT" >&2; exit 2; }
. "$SCRIPT_DIR/../../clean-arch-overview/scripts/detect.sh"
detect_bases

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t discan)"
trap 'rm -rf "$TMP"' EXIT
jstr() { printf '%s' "$1" | tr -d '\000-\037' | sed -e 's/\\/\//g' -e 's/"/'"'"'/g'; }
frozen() { head -n 3 "$1" 2>/dev/null | grep -q "DEPRECATED: migrated by /feature --migrate"; }
pub() { [ -f pubspec.yaml ] && grep -qE "^[[:space:]]*$1:" pubspec.yaml && echo true || echo false; }

find lib -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.gr.dart' ! -name '*.config.dart' ! -name 'app_localizations*.dart' 2>/dev/null | sort \
  | while IFS= read -r f; do frozen "$f" || echo "$f"; done > "$TMP/files"

cnt() { xargs grep -hE "$1" < "$TMP/files" 2>/dev/null | wc -l | tr -d ' '; }
fcnt() { xargs grep -lE "$1" < "$TMP/files" 2>/dev/null | wc -l | tr -d ' '; }
NB='(^|[^A-Za-z0-9_])'

# ---- How DI is done today ----
getx_hits="$(cnt "$RE_GX_DI")"
getx_files="$(fcnt "$RE_GX_DI")"
getit_hits="$(cnt "${NB}(getIt|GetIt\\.I|GetIt\\.instance|locator|sl)(<|\\()|registerFactory|registerLazySingleton|registerSingleton")"
provider_hits="$(cnt "${NB}(MultiProvider|ProxyProvider|ChangeNotifierProxyProvider|Provider<|Provider\\()|context\\.(read|watch)<")"
injectable_hits="$(cnt "@(injectable|lazySingleton|singleton|LazySingleton|Singleton|module|InjectableInit|factoryMethod)")"
getit_in_logic="$(xargs grep -lE "${NB}(getIt|GetIt\\.I|GetIt\\.instance|locator)(<|\\()|${NB}Get\\.find" < "$TMP/files" 2>/dev/null | while IFS= read -r f; do
  grep -qE "extends +($CUBIT_BASES|ChangeNotifier|$GETX_BASES)( *<|[ {]|\$)|abstract +class|class +[A-Za-z0-9_]*(Repository|DataSource|UseCase)" "$f" && echo "$f"; done | wc -l | tr -d ' ')"
existing_wiring="$(find lib -name '*_providers.dart' -o -name '*_di.dart' -o -name 'global_providers.dart' -o -name 'injection*.dart' -o -name 'locator*.dart' -o -name 'service_locator*.dart' 2>/dev/null | sort | paste -sd, -)"

# ---- Classes by role ----
: > "$TMP/nodes"
while IFS= read -r f; do
  feat="app"; case "$f" in lib/features/*) feat="$(printf '%s' "$f" | cut -d/ -f3)" ;; lib/core/*) feat="core" ;; esac
  grep -nE "^[[:space:]]*(abstract +(interface +)?|base +|final +|sealed +)*class +[A-Za-z0-9_]+" "$f" 2>/dev/null | while IFS= read -r hit; do
    ln="${hit%%:*}"; decl="${hit#*:}"
    cls="$(printf '%s' "$decl" | sed -E 's/^[[:space:]]*(abstract +(interface +)?|base +|final +|sealed +)*class +([A-Za-z0-9_]+).*/\3/')"
    case "$cls" in _*) continue ;; esac
    abs=0; printf '%s' "$decl" | grep -qE "abstract +(interface +)?class" && abs=1
    impl="$(printf '%s' "$decl" | sed -nE 's/.*implements +([A-Za-z0-9_, <>]+).*/\1/p' | sed -E 's/ *\{.*//' | tr -d ' ')"
    ext="$(printf '%s' "$decl" | sed -nE 's/.*extends +([A-Za-z0-9_]+).*/\1/p')"
    role=""
    case "$f" in
      */domain/use_cases/*) role="use_case" ;;
      */domain/repositories/*) [ "$abs" = 1 ] && role="repository_interface" ;;
    esac
    if [ -z "$role" ]; then
      case "$cls" in
        *Repository|*RepositoryImpl) if [ "$abs" = 1 ]; then role="repository_interface"; else role="repository_impl"; fi ;;
        Mock*Repository) role="repository_mock" ;;
        *DataSource) if [ "$abs" = 1 ]; then role="data_source_interface"; else role="data_source"; fi ;;
        *UseCase) role="use_case" ;;
        *Service|*Client|*Api) role="service" ;;
      esac
    fi
    if [ -n "$ext" ]; then
      if printf '%s' "$ext" | grep -qxE "$CUBIT_BASES"; then role="cubit_or_bloc"
      elif printf '%s' "$ext" | grep -qxE "ChangeNotifier|ValueNotifier|$GETX_BASES"; then role="state_holder"; fi
    fi
    [ -n "$role" ] || continue
    [ "$abs" = 1 ] && [ "$role" != "repository_interface" ] && [ "$role" != "data_source_interface" ] && continue
    deps="$(grep -E "^[[:space:]]+(final|late +final) +[A-Z][A-Za-z0-9_]*(<[^>]*>)?[?]? +_?[a-z][A-Za-z0-9_]*;" "$f" 2>/dev/null \
      | sed -E 's/^[[:space:]]+(final|late +final) +([A-Z][A-Za-z0-9_]*)(<[^>]*>)?[?]? +.*/\2/' \
      | grep -vE "^(String|Duration|DateTime|List|Map|Set|Uri|Future|Stream|Key|Color|Widget|ValueNotifier|StreamSubscription|Timer)$" | sort -u | paste -sd, -)"
    inlogic=0; grep -qE "${NB}(getIt|GetIt\\.I|GetIt\\.instance|locator)(<|\\()|${NB}Get\\.find" "$f" && inlogic=1
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$feat" "$role" "$cls" "$f" "$ln" "$impl" "$ext" "$deps" "$inlogic" >> "$TMP/nodes"
  done
done < "$TMP/files"

nodes_json="$(awk -F'\t' 'function q(s){gsub(/\\/,"/",s);gsub(/"/,"\047",s);return s}
  { printf "%s{\"feature\":\"%s\",\"role\":\"%s\",\"class\":\"%s\",\"file\":\"%s\",\"line\":%d,\"implements\":\"%s\",\"extends\":\"%s\",\"likely_dependencies\":\"%s\",\"uses_locator_inside\":%s}", (NR>1?",":""), q($1), $2, q($3), q($4), $5, q($6), q($7), q($8), ($9==1?"true":"false") }' "$TMP/nodes")"
feats_json="$(cut -f1 "$TMP/nodes" | sort -u | awk '{printf "%s\"%s\"", (NR>1?",":""), $0}')"
roles="$(cut -f2 "$TMP/nodes" | sort | uniq -c | awk '{printf "%s\"%s\":%d", (NR>1?",":""), $2, $1}')"

cat <<JSON
{
  "project": "$(jstr "$(basename "$(pwd)")")",
  "pubspec": {"get": $(pub get), "get_it": $(pub get_it), "injectable": $(pub injectable), "injectable_generator": $(pub injectable_generator), "build_runner": $(pub build_runner), "provider": $(pub provider), "flutter_bloc": $(pub flutter_bloc)},
  "today": {
    "getx_di_hits": $getx_hits, "getx_di_files": $getx_files,
    "get_it_hits": $getit_hits, "provider_hits": $provider_hits, "injectable_annotation_hits": $injectable_hits,
    "locator_calls_inside_cubits_repos_or_use_cases": $getit_in_logic,
    "existing_wiring_files": "$(jstr "$existing_wiring")",
    "has_bootstrap_dir": $([ -d lib/bootstrap ] && echo true || echo false)
  },
  "features": [${feats_json}],
  "totals_by_role": {${roles}},
  "classes": [${nodes_json}]
}
JSON
