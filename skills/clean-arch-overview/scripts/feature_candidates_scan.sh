#!/usr/bin/env bash
# Discover candidate features from a legacy Flutter layout (screens/, controllers/, …).
# Usage: feature_candidates_scan.sh [project_root] [--write path/to/feature-map.suggested.yaml]
# Prints one JSON object on stdout. Read-only unless --write is given.
# Exit 0 = ok, 2 = no lib/.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
WRITE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --write) WRITE="${2:-}"; shift 2 || true ;;
    *) ROOT="$1"; shift ;;
  esac
done
cd "$ROOT" 2>/dev/null || { echo "Cannot enter $ROOT" >&2; exit 2; }
[ -d lib ] || { echo "No lib/ directory found in $ROOT" >&2; exit 2; }

. "$SCRIPT_DIR/detect.sh"
detect_bases

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t featcand)"
trap 'rm -rf "$TMP"' EXIT
jstr() { printf '%s' "$1" | tr -d '\000-\037' | sed -e 's/\\/\//g' -e 's/"/'"'"'/g'; }

# Top-level dirs that are shared infrastructure / not feature boundaries (bare alternation)
SKIP='features|core|common|design_system|l10n|bootstrap|router|gen|config|app|providers|channels|utility|utils|widgets|modals|models|main'
GENERIC='tabs|tab|common|shared|components|widgets|base|utils|helpers|mixins|screens|pages|views|modules|core|app|main|my'

find lib -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.gr.dart' ! -name '*.config.dart' ! -name 'app_localizations*.dart' 2>/dev/null | sort > "$TMP/files"

# Existing feature folder names
: > "$TMP/have"
[ -d lib/features ] && ls lib/features 2>/dev/null | while IFS= read -r n; do [ -n "$n" ] && printf '%s\n' "$n"; done > "$TMP/have"

# GetX hit counts per file (reuse parent audit list when present)
if [ -n "${CA_GX_ALL:-}" ] && [ -f "$CA_GX_ALL" ]; then
  awk -F: '{ c[$1]++ } END { for (f in c) printf "%s\t%d\n", f, c[f] }' "$CA_GX_ALL" > "$TMP/gx"
else
  grep -rnE --include='*.dart' --exclude='*.g.dart' --exclude='*.freezed.dart' -e "$RE_GETX_USAGE" lib 2>/dev/null \
    | awk -F: '{ c[$1]++ } END { for (f in c) printf "%s\t%d\n", f, c[f] }' > "$TMP/gx"
fi

# Cubit/Bloc file list
if [ -n "${CA_BLOC_LIST:-}" ] && [ -f "$CA_BLOC_LIST" ]; then
  cp "$CA_BLOC_LIST" "$TMP/bloc"
else
  grep -rlE --include='*.dart' -e "$RE_CUBIT" lib 2>/dev/null > "$TMP/bloc" || : > "$TMP/bloc"
fi

# Assign each non-shared file to a unit; collect kinds + parent dirs
awk -F'\t' -v skip="$SKIP" -v generic="$GENERIC" "$UNIT_AWK"'
  BEGIN {
    while ((getline h < "'"$TMP/have"'") > 0) have[h] = 1
    while ((getline l < "'"$TMP/gx"'") > 0) { split(l, x, "\t"); gx[x[1]] = x[2] + 0 }
    while ((getline b < "'"$TMP/bloc"'") > 0) bloc[b] = 1
  }
  function kind_of(path, base,   k) {
    base = path; sub(/.*\//, "", base)
    if (match(base, /_(controller|view|page|screen|binding|bindings|bloc|cubit|repository|service|model|provider|state|widget|widgets|viewmodel|tab)\.dart$/))
      return substr(base, RSTART + 1, RLENGTH - 6)
    if (path ~ /\/controllers\//) return "controller"
    if (path ~ /\/cubits\//) return "cubit"
    if (path ~ /\/services\//) return "service"
    if (path ~ /\/models\//) return "model"
    if (path ~ /\/(screens|pages|views)\//) return "screen"
    if (path ~ /\/modals\//) return "modal"
    return "file"
  }
  function parent_dir(path,   n, a, i, p) {
    n = split(path, a, "/")
    if (n < 2) return path
    p = a[1]
    for (i = 2; i < n; i++) p = p "/" a[i]
    return p
  }
  {
    path = $0
    nseg = split(path, a, "/")
    top = (nseg >= 2 ? a[2] : "")
    if (top ~ ("^(" skip ")$")) next
    if (path ~ /^lib\/(main|app)\.dart$/) next
    u = unit_of(path)
    if (u == "" || length(u) < 3 || u ~ ("^(" generic ")$")) next
    if (!((u SUBSEP path) in seenf)) {
      seenf[u SUBSEP path] = 1
      cnt[u]++
      gx_u[u] += gx[path] + 0
      if (path in bloc) bloc_u[u]++
      k = kind_of(path)
      if (!((u SUBSEP k) in seenk)) { seenk[u SUBSEP k] = 1; kinds[u] = kinds[u] (kinds[u] == "" ? "" : "|") k }
      if (k ~ /^(screen|page|view|tab)$/) has_ui[u] = 1
      if (k ~ /^(controller|cubit|bloc|binding)$/) has_state[u] = 1
      d = parent_dir(path)
      if (!((u SUBSEP d) in seend)) {
        seend[u SUBSEP d] = 1
        ndir[u]++
        if (ndir[u] <= 12) dirs[u] = dirs[u] (dirs[u] == "" ? "" : "|") d
      }
      if (npath[u] < 6) { npath[u]++; sample[u] = sample[u] (sample[u] == "" ? "" : "|") path }
      if (top != "" && !((u SUBSEP top) in seent)) {
        seent[u SUBSEP top] = 1
        roots[u] = roots[u] (roots[u] == "" ? "" : "|") top
      }
    }
  }
  END {
    for (u in cnt) {
      if (cnt[u] < 2 && !(u in have)) continue
      score = cnt[u] * 10 + gx_u[u] * 2
      if (has_ui[u]) score += 50
      if (has_state[u]) score += 50
      if (bloc_u[u] > 0) score += 20
      # Prefer migrating net-new units first in suggested order
      order_key = (u in have) ? 0 : 1
      # Leaf-ish (fewer dirs) slightly ahead of hubs when scores tie
      printf "%d\t%d\t%d\t%s\t%s\t%d\t%d\t%d\t%s\t%s\t%s\n", \
        order_key, score, -ndir[u]+0, u, kinds[u], cnt[u], gx_u[u]+0, bloc_u[u]+0, \
        (u in have ? 1 : 0), dirs[u], roots[u]
    }
  }
' "$TMP/files" | sort -t"$(printf '\t')" -k1,1nr -k2,2nr -k3,3nr -k4,4 > "$TMP/ranked"

# Cap at 40 candidates for the report / yaml
head -n 40 "$TMP/ranked" > "$TMP/top"

# ---- Shape / domain / interfaces (clean-arch-overview + when-to-use-interfaces) ----
# thin = cubit → typed API client; repository = caching/merge/mapping → repo interface in domain/;
# full = business rules → use cases (+ repo interface). Never interface for use cases/cubits/DTOs.
RE_CACHE='package:(hive|hive_flutter|shared_preferences|flutter_secure_storage|get_storage|sqflite|drift|isar)([^a-zA-Z0-9_]|$)|Caches\.|bond_cache|SharedPreferences|FlutterSecureStorage|Hive\.(box|open)|RemoteConfig'
RE_MERGE='loadFromCache|saveToCache|fromCache|toCache|cacheThen|cacheFirst|offlineFirst|mergeWith|syncLocal|localDataSource|remoteDataSource|LocalSource|RemoteSource'
RE_MAP='toEntity\(|fromDto\(|toDto\(|fromModel\(|toModel\(|[A-Za-z]+Mapper\b|mapDto|DtoMapper'
RE_API='BondFire|\.get<|\.post<|\.put<|\.patch<|\.delete<|package:dio/|Dio\(|sl<BondFire>|ApiClient|HttpClient'
RE_RULES='\b(eligib|dailyLimit|overdrawn|threshold|isAllowed|mustNot|businessRule|calculate[A-Z]|compute[A-Z]|can[A-Z][a-zA-Z]{2,}\(|validate[A-Z][a-zA-Z]+)'
RE_REPO_TYPE='[A-Za-z0-9_]*Repository\b|abstract +interface +class|abstract +class +[A-Za-z0-9_]*Repository'

count_in_list() { # <ERE> <filelist> -> int
  if [ ! -s "$2" ]; then echo 0; return; fi
  xargs grep -hcE -e "$1" < "$2" 2>/dev/null | awk '{s+=$1} END {print s+0}'
}

# analyze_shape <unit> <files_count> -> writes $TMP/shape_<unit>.json fields via stdout TSV:
# shape\tdomain\trepo_iface\tuse_cases\tdata_source_iface\tcache\tmerge\tmap\tapi\trules\trepo\treasons
analyze_shape() {
  local unit="$1" nfiles="${2:-0}"
  unit_files "$unit" > "$TMP/uf_$unit" 2>/dev/null || : > "$TMP/uf_$unit"
  local cache merge map api rules repo
  cache="$(count_in_list "$RE_CACHE" "$TMP/uf_$unit")"
  merge="$(count_in_list "$RE_MERGE" "$TMP/uf_$unit")"
  map="$(count_in_list "$RE_MAP" "$TMP/uf_$unit")"
  api="$(count_in_list "$RE_API" "$TMP/uf_$unit")"
  rules="$(count_in_list "$RE_RULES" "$TMP/uf_$unit")"
  repo="$(count_in_list "$RE_REPO_TYPE" "$TMP/uf_$unit")"
  local shape=thin domain=false repo_iface=false use_cases=false ds_iface=false reasons=""
  if [ "$rules" -ge 2 ] || { [ "$rules" -ge 1 ] && [ "$nfiles" -ge 20 ]; }; then
    shape=full; domain=true; repo_iface=true; use_cases=true
    reasons="business-rule signals ($rules) → full domain with use cases"
  elif [ "$cache" -ge 1 ] || [ "$merge" -ge 1 ] || [ "$map" -ge 2 ] || [ "$repo" -ge 1 ] \
    || { [ "$api" -ge 5 ] && [ "$nfiles" -ge 15 ]; }; then
    shape=repository; domain=true; repo_iface=true
    [ "$cache" -ge 1 ] && reasons="${reasons:+$reasons|}caching/storage ($cache)"
    [ "$merge" -ge 1 ] && reasons="${reasons:+$reasons|}multi-source/merge ($merge)"
    [ "$map" -ge 2 ] && reasons="${reasons:+$reasons|}complex mapping ($map)"
    [ "$repo" -ge 1 ] && reasons="${reasons:+$reasons|}existing Repository type ($repo)"
    [ "$api" -ge 5 ] && [ "$nfiles" -ge 15 ] && reasons="${reasons:+$reasons|}many API calls ($api) in a large unit"
    reasons="${reasons:+$reasons|}→ repository interface in domain/, impl in data/; no use cases unless rules appear"
  else
    shape=thin; domain=false; repo_iface=false; use_cases=false
    reasons="display/API-only signals → thin (cubit calls typed API client; no domain/, no data/)"
    [ "$api" -gt 0 ] && reasons="${reasons}|API call hits=$api"
  fi
  if [ "$cache" -ge 1 ] && [ "$api" -ge 1 ]; then
    ds_iface=false
    reasons="${reasons}|remote+local: one repository interface (skip data-source interface unless two impls are swapped)"
  fi
  reasons="${reasons}|no interface for use cases/cubits/DTOs/mappers"
  printf '%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%s\n' \
    "$shape" "$domain" "$repo_iface" "$use_cases" "$ds_iface" \
    "$cache" "$merge" "$map" "$api" "$rules" "$repo" "$reasons"
}

# Build JSON candidates + order arrays
candidates_json=""
order_json=""
n_new=0
prio=0
n_thin=0; n_repo=0; n_full=0
first_new=""
list_new=""
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
: > "$TMP/yaml_body"

while IFS="$(printf '\t')" read -r _okey score _ndir name kinds files getx blocs exists dirs roots; do
  [ -n "$name" ] || continue
  kinds_json=""; oldifs="$IFS"; IFS='|'
  for k in $kinds; do [ -n "$k" ] || continue; kinds_json="${kinds_json}${kinds_json:+,}\"$k\""; done
  dirs_json=""
  for d in $dirs; do [ -n "$d" ] || continue; dirs_json="${dirs_json}${dirs_json:+,}\"$(jstr "$d")\""; done
  roots_json=""
  for r in $roots; do [ -n "$r" ] || continue; roots_json="${roots_json}${roots_json:+,}\"$(jstr "$r")\""; done
  IFS="$oldifs"
  ex_bool=false; [ "$exists" = 1 ] && ex_bool=true
  why="clustered from legacy paths"
  [ "$exists" = 1 ] && why="already under lib/features/$name"

  IFS="$(printf '\t')" read -r shape domain repo_iface use_cases ds_iface \
    sig_cache sig_merge sig_map sig_api sig_rules sig_repo reasons < <(analyze_shape "$name" "$files")
  case "$shape" in thin) n_thin=$((n_thin+1)) ;; repository) n_repo=$((n_repo+1)) ;; full) n_full=$((n_full+1)) ;; esac
  reasons_json=""; oldifs="$IFS"; IFS='|'
  for rr in $reasons; do [ -n "$rr" ] || continue; reasons_json="${reasons_json}${reasons_json:+,}\"$(jstr "$rr")\""; done
  IFS="$oldifs"

  item="{\"name\":\"$(jstr "$name")\",\"files\":$files,\"getx\":$getx,\"blocs\":$blocs,\"score\":$score,\"kinds\":[${kinds_json}],\"legacy_roots\":[${roots_json}],\"include\":[${dirs_json}],\"exists\":$ex_bool,\"target\":\"lib/features/$(jstr "$name")\",\"why\":\"$(jstr "$why")\",\"shape\":\"$shape\",\"domain\":$domain,\"interfaces\":{\"repository\":$repo_iface,\"use_cases\":$use_cases,\"data_source\":$ds_iface},\"signals\":{\"cache\":$sig_cache,\"merge\":$sig_merge,\"mapping\":$sig_map,\"api\":$sig_api,\"rules\":$sig_rules,\"repository_types\":$sig_repo},\"reasons\":[${reasons_json}]}"
  candidates_json="${candidates_json:+$candidates_json,}$item"
  order_json="${order_json:+$order_json,}\"$(jstr "$name")\""
  if [ "$exists" != 1 ]; then
    n_new=$((n_new + 1))
    prio=$((prio + 1))
    [ -z "$first_new" ] && first_new="$name"
    list_new="${list_new:+$list_new, }$name ($files files, $shape)"
    y_prio=$prio
    y_status=pending
  else
    y_prio=99
    y_status=done
  fi
  {
    echo "  - name: $name"
    echo "    target: lib/features/$name"
    echo "    priority: $y_prio"
    echo "    status: $y_status"
    echo "    shape: $shape"
    echo "    domain: $domain"
    echo "    interfaces:"
    echo "      repository: $repo_iface"
    echo "      use_cases: $use_cases"
    echo "      data_source: $ds_iface"
    echo "    files: $files"
    echo "    getx: $getx"
    echo "    blocs: $blocs"
    echo "    score: $score"
    echo "    kinds: [${kinds//|/, }]"
    echo "    signals: {cache: $sig_cache, merge: $sig_merge, mapping: $sig_map, api: $sig_api, rules: $sig_rules, repository_types: $sig_repo}"
    echo "    include:"
    oldifs="$IFS"; IFS='|'
    for d in $dirs; do [ -n "$d" ] || continue; echo "      - $d/**"; done
    IFS="$oldifs"
  } >> "$TMP/yaml_body"
done < "$TMP/top"

written=""
if [ -n "$WRITE" ]; then
  mkdir -p "$(dirname "$WRITE")"
  {
    echo "# Generated by /audit feature discovery — overwritten each run."
    echo "# Copy to feature-map.yaml and edit to confirm names, merges, and excludes."
    echo "generated_at: $now"
    echo "source: feature_candidates_scan"
    echo "candidates:"
    cat "$TMP/yaml_body"
  } > "$WRITE"
  written="$WRITE"
fi

cat <<JSON
{
  "generated_at": "$(jstr "$now")",
  "candidates": [${candidates_json}],
  "order": [${order_json}],
  "new_count": $n_new,
  "first_new": "$(jstr "$first_new")",
  "new_summary": "$(jstr "$list_new")",
  "shapes": {"thin": $n_thin, "repository": $n_repo, "full": $n_full},
  "written": "$(jstr "$written")"
}
JSON
