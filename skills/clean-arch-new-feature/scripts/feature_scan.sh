#!/usr/bin/env bash
# Finds legacy files that belong to a feature and proposes where to move them.
# Usage: feature_scan.sh <project_root> <feature_name>     (feature_name in snake_case)
# Prints one JSON document on stdout. Read-only: moves nothing, writes nothing, no network.
# Exit code 0 = plan produced, 2 = bad arguments or no lib/ directory.
#
# Moves are pure relocations: file names are kept so class references do not break.
# Converting controllers to cubits, renaming classes etc. is done by other commands.
set -u

ROOT="${1:-.}"; NAME="${2:-}"
[ -n "$NAME" ] || { echo "Usage: feature_scan.sh <project_root> <feature_name>" >&2; exit 2; }
case "$NAME" in *[!a-z0-9_]*|"") echo "Feature name must be snake_case (a-z, 0-9, _)" >&2; exit 2 ;; esac
cd "$ROOT" 2>/dev/null || { echo "Cannot enter $ROOT" >&2; exit 2; }
[ -d lib ] || { echo "No lib/ directory found in $ROOT" >&2; exit 2; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t featscan)"
trap 'rm -rf "$TMP"' EXIT
DEST="lib/features/$NAME"

jstr() { printf '%s' "$1" | tr -d '\000-\037' | sed -e 's/\\/\//g' -e 's/"/'"'"'/g'; }

# Candidates: Dart files outside the shared/infra folders and outside lib/features/ whose path or file name mentions the feature.
find lib -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.gr.dart' ! -name '*.config.dart' ! -name 'app_localizations*.dart' 2>/dev/null \
  | grep -vE '^lib/(core|design_system|l10n|bootstrap|router|features)/|^lib/(main|app)\.dart$' \
  | awk -v n="$NAME" '{
      p = $0; b = p; sub(/.*\//, "", b)
      if (index(p, "/" n "/") > 0 || b == n ".dart" || index(b, n "_") == 1 || index(b, "_" n "_") > 0 || (length(b) > length(n) + 6 && substr(b, length(b) - length(n) - 4) == "_" n ".dart")) print p
    }' | sort > "$TMP/candidates"

already=0
[ -d "$DEST" ] && already="$(find "$DEST" -name '*.dart' 2>/dev/null | wc -l | tr -d ' ')"

: > "$TMP/moves"; : > "$TMP/skipped"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  base="$(basename "$f")"
  if head -n 3 "$f" 2>/dev/null | grep -q "DEPRECATED: migrated by /feature --migrate"; then
    printf '%s\t%s\n' "$f" "already migrated: deprecated copy kept for now, delete it when nothing imports it" >> "$TMP/skipped"; continue
  fi
  if grep -qE "^part( of)? " "$f" 2>/dev/null; then
    printf '%s\t%s\n' "$f" "uses part / part of: move by hand together with its library file" >> "$TMP/skipped"; continue
  fi

  layer=""; sub=""; conf="medium"; why=""
  if grep -qE "extends +(GetxController|GetxService|Cubit<|Bloc<|HydratedCubit<|HydratedBloc<|ChangeNotifier)" "$f"; then
    layer="presentation"; sub="presentation/cubit"; conf="high"; why="state holder (controller / cubit / bloc / notifier)"
  elif grep -qE "extends +(StatelessWidget|StatefulWidget|GetView<|GetWidget<|ConsumerWidget)" "$f" || echo "$base" | grep -qE "_(page|view|screen|widget|widgets|dialog|sheet)\.dart$"; then
    layer="presentation"; sub="presentation/ui"; conf="high"; why="widget / page"
  elif echo "$base" | grep -qE "_(binding|bindings)\.dart$" || grep -qE "extends +Bindings" "$f"; then
    layer="wiring"; sub=""; conf="medium"; why="GetX binding: becomes <feature>_providers.dart later (/di); review"
  elif echo "$base" | grep -qE "_(routes?|pages)\.dart$" || grep -qE "GetPage[<(]" "$f"; then
    layer="routes"; sub=""; conf="medium"; why="route definitions: becomes <feature>_routes.dart (/route)"
  elif grep -qE "^abstract +(interface +)?class +[A-Za-z0-9_]*Repository" "$f"; then
    layer="domain"; sub="domain/repositories"; conf="high"; why="abstract repository"
  elif echo "$base" | grep -qE "_repository(_impl)?\.dart$" || grep -qE "class +[A-Za-z0-9_]*Repository(Impl)?( |<|\{)" "$f"; then
    layer="data"; sub="data"; conf="medium"; why="concrete repository"
  elif echo "$base" | grep -qE "_(use_case|usecase)\.dart$" || grep -qE "class +[A-Za-z0-9_]*UseCase" "$f"; then
    layer="domain"; sub="domain/use_cases"; conf="high"; why="use case"
  elif echo "$base" | grep -qE "_(service|api|datasource|data_source|client|provider)\.dart$" || grep -qE "extends +GetConnect|Dio\(|http\.(get|post)" "$f"; then
    layer="data"; sub="data/sources"; conf="medium"; why="remote / local data access"
  elif grep -qE "fromJson|toJson|fromMap|toMap" "$f"; then
    layer="data"; sub="data/dtos"; conf="medium"; why="model with serialization: DTO (split entity vs DTO later)"
  elif echo "$base" | grep -qE "_(model|entity)\.dart$" || echo "$f" | grep -qE "/(models|entities)/"; then
    layer="domain"; sub="domain/entities"; conf="medium"; why="plain model: entity"
  else
    printf '%s\t%s\n' "$f" "could not classify (no layer rule matched): decide by hand" >> "$TMP/skipped"; continue
  fi

  case "$layer" in
    wiring|routes) to="$DEST/$base" ;;
    *) to="$DEST/$sub/$base" ;;
  esac
  if [ -e "$to" ]; then
    printf '%s\t%s\n' "$f" "destination already exists: $to" >> "$TMP/skipped"; continue
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$to" "$layer" "$conf" "$why" >> "$TMP/moves"
done < "$TMP/candidates"

# Dependents outside the moved set (how many files will have imports rewritten)
cut -f1 "$TMP/moves" | sort -u > "$TMP/moved_set"
find lib test -name '*.dart' 2>/dev/null | sort > "$TMP/all"
comm -23 "$TMP/all" "$TMP/moved_set" > "$TMP/others"
: > "$TMP/deps"
while IFS="$(printf '\t')" read -r from to layer conf why; do
  [ -n "$from" ] || continue
  rel="${from#lib/}"; base="$(basename "$from")"
  n=0; [ -s "$TMP/others" ] && n="$(xargs grep -lE "(import|export) +['\"](package:[^/]+/${rel}|[^'\"]*/${base}|${base})['\"]" < "$TMP/others" 2>/dev/null | wc -l | tr -d ' ')"
  printf '%s\t%s\n' "$from" "$n" >> "$TMP/deps"
done < "$TMP/moves"

moves_json="$(awk -F'\t' 'function c(s){gsub(/\\/,"/",s);gsub(/"/,"\047",s);return s}
  NR==FNR { d[$1]=$2; next }
  { printf "%s{\"from\":\"%s\",\"to\":\"%s\",\"layer\":\"%s\",\"confidence\":\"%s\",\"reason\":\"%s\",\"dependents\":%d}", (n++?",":""), c($1), c($2), $3, $4, c($5), d[$1]+0 }' "$TMP/deps" "$TMP/moves")"
skipped_json="$(awk -F'\t' 'function c(s){gsub(/\\/,"/",s);gsub(/"/,"\047",s);return s}
  { printf "%s{\"file\":\"%s\",\"reason\":\"%s\"}", (n++?",":""), c($1), c($2) }' "$TMP/skipped")"
n_moves="$(wc -l < "$TMP/moves" | tr -d ' ')"
n_skipped="$(wc -l < "$TMP/skipped" | tr -d ' ')"
total_deps="$(awk -F'\t' '{s+=$2} END{print s+0}' "$TMP/deps")"
pkg="$(sed -n 's/^name:[[:space:]]*//p' pubspec.yaml 2>/dev/null | head -n1 | tr -d ' \r')"

cat <<JSON
{
  "project": "$(jstr "$(basename "$(pwd)")")",
  "package": "$(jstr "$pkg")",
  "feature": "$NAME",
  "destination": "$DEST",
  "already_in_feature": $already,
  "summary": {"moves": $n_moves, "skipped": $n_skipped, "import_dependents": $total_deps},
  "moves": [${moves_json}],
  "skipped": [${skipped_json}]
}
JSON
