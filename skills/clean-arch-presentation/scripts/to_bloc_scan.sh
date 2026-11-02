#!/usr/bin/env bash
# Finds state holders that /to-bloc can convert and the widgets that consume them.
# Usage: to_bloc_scan.sh [project_root] [target ...]   (target = feature name, path, or empty for all of lib/)
# Prints one JSON document on stdout. Read-only: writes nothing, no network.
# Candidates:
#   notifier  class X extends ChangeNotifier / ValueNotifier<T>   (the interim form left by /kill-getx)
#   getx      class X extends GetxController                       (blocked: run /kill-getx first)
#   stateful  StatefulWidget whose State mixes setState with async work (low confidence, review by hand)
# Metrics are per file, not per class, so they are approximate when a file declares several classes.
# Skips frozen originals (header "DEPRECATED: migrated by /feature --migrate").
# Exit code 0 = ok, 2 = no lib/ directory.
set -u

ROOT="${1:-.}"; [ $# -gt 0 ] && shift
cd "$ROOT" 2>/dev/null || { echo "Cannot enter $ROOT" >&2; exit 2; }
[ -d lib ] || { echo "No lib/ directory found in $ROOT" >&2; exit 2; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t tobloc)"
trap 'rm -rf "$TMP"' EXIT
jstr() { printf '%s' "$1" | tr -d '\000-\037' | sed -e 's/\\/\//g' -e 's/"/'"'"'/g'; }
arr() { awk 'BEGIN{printf "["} {g=$0; gsub(/\\/,"/",g); gsub(/"/,"\047",g); printf "%s\"%s\"", (NR>1?",":""), g} END{printf "]"}' "$1"; }
frozen() { head -n 3 "$1" 2>/dev/null | grep -q "DEPRECATED: migrated by /feature --migrate"; }

# ---- Targets ----
: > "$TMP/files"; : > "$TMP/unresolved"
if [ $# -eq 0 ]; then set -- lib; fi
for t in "$@"; do
  if [ -d "lib/features/$t" ]; then p="lib/features/$t"
  elif [ -e "$t" ]; then p="$t"
  elif [ -e "lib/$t" ]; then p="lib/$t"
  else echo "$t" >> "$TMP/unresolved"; continue; fi
  if [ -d "$p" ]; then find "$p" -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.gr.dart' ! -name '*.config.dart' ! -name 'app_localizations*.dart' 2>/dev/null >> "$TMP/files"
  else printf '%s\n' "$p" >> "$TMP/files"; fi
done
sort -u "$TMP/files" -o "$TMP/files"

snake() { printf '%s' "$1" | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' | tr 'A-Z' 'a-z'; }
base_name() { # strip a state-holder suffix from a class name
  printf '%s' "$1" | sed -E 's/(Controller|Notifier|ViewModel|Model|Provider|Store|Manager|State)$//'
}
count() { grep -cE "$1" "$2" 2>/dev/null || true; }

: > "$TMP/cands"; skipped_frozen=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if frozen "$f"; then skipped_frozen=$((skipped_frozen + 1)); continue; fi

  # --- class based candidates ---
  grep -nE "^[[:space:]]*(abstract +|base +|final +)*class +[A-Za-z0-9_]+( *<[^>]*>)? +extends +(ChangeNotifier|ValueNotifier<|GetxController)" "$f" 2>/dev/null | while IFS= read -r hit; do
    ln="${hit%%:*}"
    cls="$(printf '%s' "$hit" | sed -E 's/^[0-9]+:[[:space:]]*(abstract +|base +|final +)*class +([A-Za-z0-9_]+).*/\2/')"
    sup="$(printf '%s' "$hit" | sed -E 's/.*extends +([A-Za-z]+).*/\1/')"
    case "$sup" in GetxController) kind="getx" ;; *) kind="notifier" ;; esac
    notify="$(count 'notifyListeners\(' "$f")"; asyncm="$(count '(Future<|async[ ({])' "$f")"
    pubm="$(count '^[[:space:]]+(Future<[^>]*>|void|bool|int|String|double|Stream<[^>]*>)[[:space:]]+[a-z][A-Za-z0-9_]*\(' "$f")"
    fields="$(count '^[[:space:]]+(final |late )?[A-Za-z<>?, ]+[[:space:]]+_[a-z][A-Za-z0-9_]*[[:space:]]*(=|;)' "$f")"
    disp="$(count 'void +dispose\(' "$f")"
    ontransf="$(count '(debounce|Timer\(|Timer\.periodic|restartable|droppable|StreamSubscription|\.listen\()' "$f")"
    if [ "${ontransf:-0}" -gt 0 ]; then sugg="bloc"; else sugg="cubit"; fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$f" "$ln" "$cls" "$kind" "$notify" "$asyncm" "$pubm" "$fields" "$disp" "$ontransf" "$sugg" >> "$TMP/cands"
  done

  # --- StatefulWidget screens that mix setState with async work ---
  if grep -qE "extends +State<" "$f" 2>/dev/null; then
    ss="$(count 'setState\(' "$f")"; aw="$(count '(await |\.then\()' "$f")"
    if [ "${ss:-0}" -gt 0 ] && [ "${aw:-0}" -gt 0 ]; then
      cls="$(grep -E "class +[A-Za-z0-9_]+ +extends +State<" "$f" | head -n1 | sed -E 's/.*class +([A-Za-z0-9_]+).*/\1/')"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$f" "0" "$cls" "stateful" "$ss" "$aw" "0" "0" "0" "0" "cubit" >> "$TMP/cands"
    fi
  fi
done < "$TMP/files"

# ---- Consumers and suggested names ----
: > "$TMP/out"
while IFS="$(printf '\t')" read -r f ln cls kind notify asyncm pubm fields disp ontransf sugg; do
  [ -n "$f" ] || continue
  core="$(base_name "$cls")"; [ -n "$core" ] || core="$cls"
  core="${core#_}"
  cubit="${core}Cubit"; bloc="${core}Bloc"; stem="$(snake "$core")"
  feat=""; case "$f" in lib/features/*) feat="$(printf '%s' "$f" | cut -d/ -f3)" ;; esac
  if [ -n "$feat" ]; then tdir="lib/features/$feat/presentation/cubit"; else tdir="$(dirname "$f")"; fi
  : > "$TMP/cons"
  if [ "$kind" != "stateful" ]; then
    grep -rlw --include='*.dart' "$cls" lib 2>/dev/null | while IFS= read -r c; do
      [ "$c" = "$f" ] && continue
      frozen "$c" && continue
      echo "$c"
    done | sort -u > "$TMP/cons"
  fi
  n_cons="$(wc -l < "$TMP/cons" | tr -d ' ')"
  provider_use=0
  [ "$n_cons" -gt 0 ] && provider_use="$(xargs grep -lE "ChangeNotifierProvider|context\.(watch|read|select)<$cls>|Consumer<$cls>|Provider\.of<$cls>" < "$TMP/cons" 2>/dev/null | wc -l | tr -d ' ')"
  listener_use=0
  [ "$n_cons" -gt 0 ] && listener_use="$(xargs grep -lE "ListenableBuilder|AnimatedBuilder|ValueListenableBuilder|addListener" < "$TMP/cons" 2>/dev/null | wc -l | tr -d ' ')"
  fcount="$(basename "$f")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$f" "$ln" "$cls" "$kind" "$notify" "$asyncm" "$pubm" "$fields" "$disp" "$ontransf" "$sugg" \
    "$cubit" "$bloc" "$stem" "$tdir" "$n_cons" "$provider_use" "$listener_use" "$(paste -sd, "$TMP/cons")" >> "$TMP/out"
done < "$TMP/cands"

cands_json="$(awk -F'\t' 'function c(s){gsub(/\\/,"/",s);gsub(/"/,"\047",s);return s}
  { n = split($19, cs, ","); list = ""; for (i = 1; i <= n && i <= 25; i++) if (cs[i] != "") list = list (list == "" ? "" : ",") "\"" c(cs[i]) "\""
    printf "%s{\"file\":\"%s\",\"line\":%d,\"class\":\"%s\",\"kind\":\"%s\",\"metrics\":{\"notify_listeners\":%d,\"async_markers\":%d,\"public_methods\":%d,\"private_fields\":%d,\"has_dispose\":%d,\"transformer_signals\":%d},\"suggested\":\"%s\",\"names\":{\"cubit\":\"%s\",\"bloc\":\"%s\",\"file_stem\":\"%s\",\"dir\":\"%s\"},\"consumers\":{\"count\":%d,\"provider_users\":%d,\"listenable_users\":%d,\"files\":[%s]}}", (NR>1?",":""), c($1), $2, $3, $4, $5, $6, $7, $8, ($9>0?1:0), $10, $11, $12, $13, $14, c($15), $16, $17, $18, list }' "$TMP/out")"

n_notifier="$(awk -F'\t' '$4=="notifier"' "$TMP/out" | wc -l | tr -d ' ')"
n_getx="$(awk -F'\t' '$4=="getx"' "$TMP/out" | wc -l | tr -d ' ')"
n_stateful="$(awk -F'\t' '$4=="stateful"' "$TMP/out" | wc -l | tr -d ' ')"

# ---- Project facts ----
NB='(^|[^A-Za-z0-9_])'
getx_left="$(grep -rEl --include='*.dart' "import +['\"]package:get/|${NB}Get\\.[a-z]|GetxController|${NB}Obx\\(" lib 2>/dev/null | while IFS= read -r g; do frozen "$g" || echo "$g"; done | wc -l | tr -d ' ')"
pub() { [ -f pubspec.yaml ] && grep -qE "^[[:space:]]*$1:" pubspec.yaml && echo true || echo false; }
cubits_existing="$(grep -rlE --include='*.dart' "extends +(Hydrated)?(Cubit|Bloc)<" lib 2>/dev/null | wc -l | tr -d ' ')"

cat <<JSON
{
  "project": "$(jstr "$(basename "$(pwd)")")",
  "unresolved_targets": $(arr "$TMP/unresolved"),
  "skipped_deprecated_copies": $skipped_frozen,
  "pubspec": {"flutter_bloc": $(pub flutter_bloc), "bloc": $(pub bloc), "equatable": $(pub equatable), "bloc_presentation": $(pub bloc_presentation), "bloc_test": $(pub bloc_test), "mocktail": $(pub mocktail), "provider": $(pub provider), "get": $(pub get)},
  "existing_cubit_or_bloc_files": $cubits_existing,
  "files_still_using_getx": $getx_left,
  "totals": {"candidates": $((n_notifier + n_getx + n_stateful)), "notifier": $n_notifier, "getx": $n_getx, "stateful": $n_stateful},
  "candidates": [${cands_json}]
}
JSON
