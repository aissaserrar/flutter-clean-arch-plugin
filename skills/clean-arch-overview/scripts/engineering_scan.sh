#!/usr/bin/env bash
# Software-engineering heuristics for /audit (layer leaks, size, hygiene).
# Usage: engineering_scan.sh <lib_dir> [max_file_loc_warn] [max_file_loc_error]
# Prints one JSON object on stdout: { total, errors, warnings, checks: [...] }
# Read-only. Exit 0 always when lib exists; exit 2 if lib_dir is missing.
set -u

LIB="${1:-lib}"
MAX_WARN="${2:-400}"
MAX_ERR="${3:-800}"
[ -d "$LIB" ] || { echo "No lib directory: $LIB" >&2; exit 2; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t engscan)"
trap 'rm -rf "$TMP"' EXIT

GREP_DART=(-rnE --include='*.dart' --exclude='*.g.dart' --exclude='*.freezed.dart' --exclude='*.gr.dart' --exclude='*.config.dart' --exclude='app_localizations*.dart')

jstr() { printf '%s' "$1" | tr -d '\000-\037' | sed -e 's/\\/\//g' -e 's/"/'"'"'/g'; }

hits_stdin() {
  head -n 200 | awk -F: '
    BEGIN { printf "[" }
    { f = $1; gsub(/\\/, "/", f); gsub(/"/, "\047", f)
      printf "%s{\"file\":\"%s\",\"line\":%d}", (NR > 1 ? "," : ""), f, $2 }
    END { printf "]" }'
}

# Collect non-generated dart files under lib/
find "$LIB" -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.gr.dart' ! -name '*.config.dart' ! -name 'app_localizations*.dart' 2>/dev/null | sort > "$TMP/files"

: > "$TMP/checks"
eng_errors=0
eng_warnings=0

emit_check() { # id label severity count hits_json category
  local id="$1" label="$2" sev="$3" count="$4" hits="$5" cat="$6"
  [ "$count" -eq 0 ] && hits='[]'
  printf '%s\n' "{\"id\":\"$(jstr "$id")\",\"label\":\"$(jstr "$label")\",\"severity\":\"$sev\",\"category\":\"$cat\",\"count\":$count,\"hits\":$hits}" >> "$TMP/checks"
  if [ "$count" -gt 0 ]; then
    case "$sev" in
      error) eng_errors=$((eng_errors + count)) ;;
      warning) eng_warnings=$((eng_warnings + count)) ;;
    esac
  fi
}

grep_hits() { # ERE [path...] -> writes file:line lines to stdout
  local ere="$1"; shift
  if [ "$#" -eq 0 ]; then
    grep "${GREP_DART[@]}" -e "$ere" "$LIB" 2>/dev/null || true
  else
    local p
    for p in "$@"; do
      [ -e "$p" ] || continue
      grep "${GREP_DART[@]}" -e "$ere" "$p" 2>/dev/null || true
    done
  fi
}

count_lines() { wc -l | tr -d ' '; }

# ---- A. Layer leaks (errors) ----

# Domain entities/value objects must not know JSON
dom_json="$(grep_hits 'fromJson|toJson|@JsonSerializable|json_annotation' "$LIB/features" 2>/dev/null | grep '/domain/' || true)"
n="$(printf '%s\n' "$dom_json" | sed '/^$/d' | count_lines)"
emit_check "entity_has_from_json" \
  "Domain file uses fromJson/toJson/JsonSerializable (wire format belongs in data/)" \
  error "$n" "$(printf '%s\n' "$dom_json" | sed '/^$/d' | hits_stdin)" "layer"

# DTO imports/types outside data/ (do not match slang/json *.g.dart — too noisy)
dto_out="$(grep "${GREP_DART[@]}" -e "import .*/(dto|dtos)/|import ['\"].*_dto\\.dart['\"]" "$LIB" 2>/dev/null \
  | grep -vE '/data/' || true)"
dto_ref="$(grep_hits '\\b[A-Z][A-Za-z0-9_]*Dto\\b' "$LIB" 2>/dev/null \
  | grep -E '/(presentation|domain)/|_cubit\\.dart|_bloc\\.dart' | grep -vE '/data/' || true)"
dto_all="$(printf '%s\n%s\n' "$dto_out" "$dto_ref" | sed '/^$/d' | sort -u)"
n="$(printf '%s\n' "$dto_all" | sed '/^$/d' | count_lines)"
emit_check "dto_outside_data" \
  "DTO type or dto/ import used outside data/ (presentation/domain must use entities)" \
  error "$n" "$(printf '%s\n' "$dto_all" | sed '/^$/d' | hits_stdin)" "layer"

# Presentation / cubits depending on repository implementations or data sources
impl_hits="$(grep_hits 'RepositoryImpl|DataSource|Remote[A-Z][A-Za-z0-9_]*Source|Local[A-Z][A-Za-z0-9_]*Source' "$LIB" 2>/dev/null \
  | grep -E '/presentation/|_cubit\\.dart|_bloc\\.dart' | grep -vE '/data/' || true)"
n="$(printf '%s\n' "$impl_hits" | sed '/^$/d' | count_lines)"
emit_check "presentation_depends_on_impl" \
  "Presentation/Cubit references RepositoryImpl or a DataSource (depend on the domain interface)" \
  error "$n" "$(printf '%s\n' "$impl_hits" | sed '/^$/d' | hits_stdin)" "layer"

# DioException / SocketException leaking outside data and core/http
dio_hits="$(grep_hits '\\b(DioException|DioError|SocketException)\\b' "$LIB" 2>/dev/null \
  | grep -vE '/data/|/core/http/|/core/api/|/common/api/|/common/http/|/providers/' || true)"
n="$(printf '%s\n' "$dio_hits" | sed '/^$/d' | count_lines)"
emit_check "transport_exception_leak" \
  "DioException/SocketException outside data/ or http layer (map to AppFailure in data)" \
  error "$n" "$(printf '%s\n' "$dio_hits" | sed '/^$/d' | hits_stdin)" "layer"

# Repository impl without a matching domain interface file (heuristic by stem)
: > "$TMP/impl_missing"
if [ -d "$LIB/features" ]; then
  find "$LIB/features" -name '*_repository_impl.dart' 2>/dev/null | while IFS= read -r f; do
    base="$(basename "$f" _repository_impl.dart)"
    feat="$(echo "$f" | sed -E 's#.*/features/([^/]+)/.*#\1#')"
    iface="$LIB/features/$feat/domain/repositories/${base}_repository.dart"
    alt="$(find "$LIB/features/$feat/domain" -name "${base}_repository.dart" 2>/dev/null | head -n1)"
    if [ ! -f "$iface" ] && [ -z "$alt" ]; then
      echo "${f}:1:missing domain interface ${base}_repository.dart" >> "$TMP/impl_missing"
    fi
  done
fi
n="$(count_lines < "$TMP/impl_missing")"
emit_check "repository_impl_without_interface" \
  "RepositoryImpl has no matching domain repository interface" \
  error "$n" "$(hits_stdin < "$TMP/impl_missing")" "layer"

# God use case: many public methods on one use-case class
: > "$TMP/god_uc"
if [ -d "$LIB/features" ]; then
  find "$LIB/features" -path '*/use_cases/*.dart' ! -name '*.g.dart' 2>/dev/null | while IFS= read -r f; do
    methods="$(grep -cE '^[[:space:]]*(Future<[^>]+>|void|Stream<[^>]+>|[A-Z][A-Za-z0-9_<>, ?]*)[[:space:]]+[a-z][A-Za-z0-9_]*[[:space:]]*\(' "$f" 2>/dev/null || echo 0)"
    methods="$(echo "$methods" | tr -d ' ')"
    if [ "${methods:-0}" -ge 4 ]; then
      echo "${f}:1:${methods} public methods (prefer one action per use case)" >> "$TMP/god_uc"
    fi
  done
fi
n="$(count_lines < "$TMP/god_uc")"
emit_check "use_case_god_class" \
  "Use case class with 4+ methods (one business action per class)" \
  warning "$n" "$(hits_stdin < "$TMP/god_uc")" "layer"

# ---- State management: prefer Cubit/Bloc from the architecture docs ----
# Flag subclasses of DataCubit / BaseCubit / PaginatedCubit, and those helper definitions.
# Skip type-parameter bounds (e.g. DataBuilder<C extends DataCubit<T>, …>).
custom_base_hits="$(grep "${GREP_DART[@]}" -e 'class[[:space:]].*extends[[:space:]]+(DataCubit|BaseCubit|PaginatedCubit)\b' "$LIB" 2>/dev/null \
  | grep -vE '<[^>]*extends[[:space:]]+(DataCubit|BaseCubit|PaginatedCubit)' \
  | grep -vE 'extends[[:space:]]+(StatelessWidget|StatefulWidget|HookWidget)\b' || true)"
custom_base_defs="$(grep "${GREP_DART[@]}" -e '^[[:space:]]*(abstract[[:space:]]+)?(base[[:space:]]+)?class[[:space:]]+(DataCubit|BaseCubit|PaginatedCubit)\b' "$LIB" 2>/dev/null || true)"
custom_base_all="$(printf '%s\n%s\n' "$custom_base_hits" "$custom_base_defs" | sed '/^$/d' | sort -u)"
n="$(printf '%s\n' "$custom_base_all" | sed '/^$/d' | count_lines)"
emit_check "custom_cubit_base" \
  "Uses DataCubit/BaseCubit/PaginatedCubit (prefer Cubit or Bloc with sealed Initial/Loading/Success/Failure state per clean-arch-presentation)" \
  warning "$n" "$(printf '%s\n' "$custom_base_all" | sed '/^$/d' | hits_stdin)" "state"

# ---- B. Size / complexity (warnings) ----

: > "$TMP/large_warn"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  loc="$(wc -l < "$f" | tr -d ' ')"
  if [ "$loc" -ge "$MAX_WARN" ]; then
    tag=""; [ "$loc" -ge "$MAX_ERR" ] && tag=" (critical ≥${MAX_ERR})"
    echo "${f}:1:${loc} lines${tag}" >> "$TMP/large_warn"
  fi
done < "$TMP/files"
n="$(count_lines < "$TMP/large_warn")"
emit_check "file_too_large" \
  "Dart file ≥ ${MAX_WARN} lines (split by responsibility; ≥${MAX_ERR} is critical)" \
  warning "$n" "$(hits_stdin < "$TMP/large_warn")" "size"

build_helpers="$(grep_hits 'Widget[[:space:]]+_build[A-Z][A-Za-z0-9_]*[[:space:]]*\(' "$LIB" 2>/dev/null || true)"
n="$(printf '%s\n' "$build_helpers" | sed '/^$/d' | count_lines)"
emit_check "widget_build_helpers" \
  "Private Widget _buildX() helpers (prefer small private widget classes)" \
  warning "$n" "$(printf '%s\n' "$build_helpers" | sed '/^$/d' | hits_stdin)" "size"

# ---- C. Error handling & observability ----

empty_catch="$(grep "${GREP_DART[@]}" -e 'catch[[:space:]]*\([^)]*\)[[:space:]]*\{[[:space:]]*\}' "$LIB" 2>/dev/null || true)"
n="$(printf '%s\n' "$empty_catch" | sed '/^$/d' | count_lines)"
emit_check "empty_or_print_catch" \
  "Empty catch block (log with context or map to a Failure)" \
  warning "$n" "$(printf '%s\n' "$empty_catch" | sed '/^$/d' | hits_stdin)" "errors"

raw_print="$(grep_hits '(^|[^A-Za-z0-9_])(print|debugPrint)[[:space:]]*\(' "$LIB" 2>/dev/null \
  | grep -vE 'printDebug|loggerService|/core/logging/|/common/logging/' || true)"
n="$(printf '%s\n' "$raw_print" | sed '/^$/d' | count_lines)"
emit_check "raw_print" \
  "print/debugPrint in app code (use the project logger)" \
  warning "$n" "$(printf '%s\n' "$raw_print" | sed '/^$/d' | hits_stdin)" "errors"

string_err="$(grep_hits 'final[[:space:]]+String(\?)?[[:space:]]+(error|errorMessage|message)[[:space:]]*[;=]' "$LIB" 2>/dev/null \
  | grep -E '_cubit\\.dart|_bloc\\.dart|_state\\.dart|/presentation/' || true)"
n="$(printf '%s\n' "$string_err" | sed '/^$/d' | count_lines)"
emit_check "string_error_in_state" \
  "Error held as String in cubit/state (prefer a Failure/error code; UI localizes)" \
  warning "$n" "$(printf '%s\n' "$string_err" | sed '/^$/d' | hits_stdin)" "errors"

# ---- D. UI hygiene (warnings) ----

lit_color="$(grep_hits 'Color[[:space:]]*\(0x|Colors\\.[a-zA-Z]' "$LIB" 2>/dev/null \
  | grep -vE '/design_system/|/config/themes/|/themes/|ColorScheme|ThemeData' || true)"
n="$(printf '%s\n' "$lit_color" | sed '/^$/d' | count_lines)"
emit_check "literal_color" \
  "Literal Color(0x…)/Colors.* outside design_system/themes (use tokens)" \
  warning "$n" "$(printf '%s\n' "$lit_color" | sed '/^$/d' | hits_stdin)" "ui"

# ---- E. Test mirror (info via warning severity for visibility) ----

: > "$TMP/no_test"
while IFS= read -r f; do
  case "$f" in
    *_cubit.dart|*_bloc.dart|*_use_case.dart|*/use_cases/*.dart) ;;
    *) continue ;;
  esac
  base="$(basename "$f" .dart)"
  # mirror under test/: strip leading lib/
  rel="${f#lib/}"
  dir="$(dirname "$rel")"
  if ! find test -name "${base}_test.dart" 2>/dev/null | grep -q .; then
    if [ ! -f "test/${dir}/${base}_test.dart" ]; then
      echo "${f}:1:no test/${dir}/${base}_test.dart" >> "$TMP/no_test"
    fi
  fi
done < "$TMP/files"
# Cap noise: only report when test/ exists at all
if [ -d test ]; then
  n="$(count_lines < "$TMP/no_test")"
  # Cap hit list; count can be large
  emit_check "test_mirror_missing" \
    "Cubit/Bloc/use case without a mirrored *_test.dart under test/" \
    warning "$n" "$(hits_stdin < "$TMP/no_test")" "tests"
else
  emit_check "test_mirror_missing" \
    "Cubit/Bloc/use case without a mirrored *_test.dart under test/" \
    warning 0 '[]' "tests"
fi

# ---- Assemble ----
checks_json="$(paste -sd, "$TMP/checks" 2>/dev/null)"
total=$((eng_errors + eng_warnings))

cat <<JSON
{
  "total": $total,
  "errors": $eng_errors,
  "warnings": $eng_warnings,
  "thresholds": {"file_loc_warn": $MAX_WARN, "file_loc_error": $MAX_ERR},
  "checks": [${checks_json}]
}
JSON
