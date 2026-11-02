#!/usr/bin/env bash
# Checks the Clean Architecture import rules in a Flutter project.
# Usage: check_dependencies.sh [lib_dir]   (default: lib)
# Exit code 0 = clean, 1 = violations found.
set -u

LIB="${1:-lib}"
FEATURES="$LIB/features"
violations=0

report() { # <rule> <grep output>
  if [ -n "$2" ]; then
    echo "VIOLATION: $1"
    echo "$2" | sed 's/^/  /'
    violations=$((violations + 1))
  fi
}

[ -d "$FEATURES" ] || { echo "No $FEATURES directory found."; exit 2; }

for feature_dir in "$FEATURES"/*/; do
  feature="$(basename "$feature_dir")"

  # 1. domain must be pure Dart
  if [ -d "$feature_dir/domain" ]; then
    out="$(grep -rnE "^import 'package:(flutter|flutter_bloc|bloc|dio|http|json_annotation|shared_preferences|auto_route|go_router|provider|get)[/:]|^import '.*/(data|presentation)/" "$feature_dir/domain" 2>/dev/null)"
    report "[$feature] domain imports Flutter/IO packages or data/presentation" "$out"
  fi

  # 2. presentation must not import data
  if [ -d "$feature_dir/presentation" ]; then
    out="$(grep -rnE "^import '.*/data/" "$feature_dir/presentation" 2>/dev/null)"
    report "[$feature] presentation imports data" "$out"
  fi

  # 3. data must not import presentation
  if [ -d "$feature_dir/data" ]; then
    out="$(grep -rnE "^import '.*/presentation/" "$feature_dir/data" 2>/dev/null)"
    report "[$feature] data imports presentation" "$out"
  fi

  # 4. no imports of other features
  out="$(grep -rnE "^import '.*/features/[a-z0-9_]+/" "$feature_dir" 2>/dev/null \
        | grep -vE "import '[^']*/features/$feature/" )"
  report "[$feature] imports another feature" "$out"
done

# 5. core and design_system must not import features
for shared in core design_system; do
  if [ -d "$LIB/$shared" ]; then
    out="$(grep -rnE "^import '.*/features/" "$LIB/$shared" 2>/dev/null)"
    report "[$shared] imports features" "$out"
  fi
done

if [ "$violations" -eq 0 ]; then
  echo "OK: no dependency violations in $LIB"
  exit 0
fi
echo
echo "$violations rule(s) violated."
exit 1
