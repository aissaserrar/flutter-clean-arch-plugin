#!/usr/bin/env bash
# Maintainer test for migrate_state.sh. Usage: bash skills/clean-arch-migrate/scripts/test_migrate_state.sh   (prints OK or FAIL lines)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; S="$HERE/migrate_state.sh"
T="$(mktemp -d 2>/dev/null || mktemp -d -t mst)"; trap 'rm -rf "$T"' EXIT
fail=0; check() { if [ "$2" = "$3" ]; then :; else echo "FAIL: $1 (expected '$3', got '$2')"; fail=1; fi; }
mkdir -p "$T/p/.clean-arch"
cat > "$T/audit.json" <<'J'
{"project":"x","migration_plan":{"waves":[{"wave": 1, "units": ["a", "b"], "controllers": 2},{"wave": 2, "units": ["c"], "controllers": 1}],"units":[{"name":"a"}]}}
J
bash "$S" "$T/p" init "$T/audit.json" >/dev/null; check "init exit" "$?" "0"
check "next after init" "$(bash "$S" "$T/p" next)" "a"
bash "$S" "$T/p" init "$T/audit.json" >/dev/null 2>&1; check "second init refuses" "$?" "1"
bash "$S" "$T/p" set a done declined; check "set exit" "$?" "0"
check "next after a done" "$(bash "$S" "$T/p" next)" "b"
bash "$S" "$T/p" set b blocked; check "next after b blocked" "$(bash "$S" "$T/p" next)" "c"
check "summary lists blocked" "$(bash "$S" "$T/p" summary | grep -c 'blocked.*b')" "1"
bash "$S" "$T/p" set c in_progress; check "in_progress is still next" "$(bash "$S" "$T/p" next)" "c"
bash "$S" "$T/p" set zzz done >/dev/null 2>&1; check "unknown feature rejected" "$?" "1"
bash "$S" "$T/p" set a bogus >/dev/null 2>&1; check "bad status rejected" "$?" "1"
bash "$S" "$T/p" set a done bogus >/dev/null 2>&1; check "bad e2e rejected" "$?" "1"
echo 'garbage' > "$T/p/.clean-arch/progress.json"
bash "$S" "$T/p" next >/dev/null 2>&1; check "corrupt file exit" "$?" "2"
check "corrupt file untouched" "$(cat "$T/p/.clean-arch/progress.json")" "garbage"
[ "$fail" -eq 0 ] && echo "OK: migrate_state.sh" || exit 1
