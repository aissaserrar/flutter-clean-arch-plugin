#!/usr/bin/env bash
# Maintainer check: does the plugin recognise EVERY GetX API listed in the catalog (skills/clean-arch-overview/scripts/detect.sh)?
# Usage: bash scripts/check_getx_coverage.sh        Read-only (works in a temp folder). Exit 0 = all covered, 1 = gaps.
#
# For every class, mixin, enum, top-level function, Get.<member> and extension member of the catalog it builds a one-line
# sample of real code, then verifies two things:
#   1. the cheap prefilter used for the whole-project scan matches it (otherwise the audit would never see it)
#   2. the precise pattern of its area matches it (otherwise it would be counted in the wrong area or not at all)
# Finally it runs audit.sh and kill_getx_scan.sh on a generated project containing all samples.
# When GetX adds API: add the names to the catalog in detect.sh, run this, and it tells you what else to wire.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCR="$ROOT/skills/clean-arch-overview/scripts"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t gxcov)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/lib/s"; cd "$TMP/p" || exit 1
printf 'name: cov\ndependencies:\n  get: any\n' > pubspec.yaml
. "$SCR/detect.sh"

: > "$TMP/samples"   # area<TAB>name<TAB>code
add() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$TMP/samples"; }
each() { printf '%s' "$1" | tr '|' '\n' | grep -v '^$'; }

for n in $(each "$GX_STATE_WIDGETS"); do add widgets "$n" "final w = $n(child);"; done
for n in GetxController GetxService SuperController GetLifeCycle FullLifeCycleController DisposableInterface RxController GetNotifier GetMaterialController; do add controller "$n" "class A$n extends $n {}"; done
for n in $(each "$GX_MIXINS"); do add reactive "$n" "class M$n with $n {}"; done
for n in $(each "$GX_RX"); do add reactive "$n" "final r = $n(0);"; done
add reactive ".obs" "final c = 0.obs;"
add reactive ".obx" "return controller.obx((s) => w);"
for n in $(each "$GX_ROUTING"); do add nav "$n" "final r = $n(x);"; done
for n in $(each "$GX_DI_CLASSES"); do add di "$n" "final b = $n();"; done
add di "extends Binding" "class B extends Binding {}"
for n in $(each "$GX_UI_CLASSES"); do add ui "$n" "final u = $n.x;"; done
for n in $(each "$GX_NET"); do add net "$n" "class N$n extends $n {}"; done
for n in $(each "$GX_STREAMS"); do add streams "$n" "final s = $n();"; done
for n in $(each "$GX_WORKER_FUNCS"); do add workers "$n" "$n(x, (_) {});"; done
add translations "Translations" "class T extends Translations {}"
for n in $(each "$GX_NAV_MEMBERS"); do add nav "Get.$n" "Get.$n(x);"; done
for n in $(each "$GX_DI_MEMBERS"); do add di "Get.$n" "Get.$n(x);"; done
for n in $(each "$GX_UI_MEMBERS"); do add ui "Get.$n" "Get.$n(x);"; done
for n in $(each "$GX_EXT_DISTINCT"); do add ext ".$n" "final v = x.$n;"; done
for n in seconds milliseconds microseconds minutes hours days; do add ext "2.$n" "final d = 2.$n;"; done
for n in $(each "$GX_CONTEXT_EXT"); do add ext "context.$n" "final v = context.$n;"; done
for n in $(each "$GX_AMBIGUOUS"); do add ext "$n" "final v = $n.fade;"; done
add import "package:get/get.dart" "import 'package:get/get.dart';"
add import "package:get/get_core/get_core.dart" "import 'package:get/get_core/get_core.dart';"
add import "package:get/get_navigation/get_navigation.dart" "export 'package:get/get_navigation/get_navigation.dart';"

re_for() { # area -> precise ERE
  case "$1" in
    widgets) echo "$RE_GX_WIDGETS" ;; controller) echo "extends +($GX_CONTROLLER_BASES)([^A-Za-z0-9_]|\$)" ;; reactive) echo "$RE_GX_REACTIVE" ;;
    nav) echo "$RE_GX_NAV" ;; di) echo "$RE_GX_DI" ;; ui) echo "$RE_GX_UI" ;; net) echo "$RE_GX_NET" ;; streams) echo "$RE_GX_STREAMS" ;;
    workers) echo "$RE_GX_WORKERS" ;; translations) echo "$RE_GX_TRANSLATIONS" ;; ext) echo "$RE_GX_EXT" ;; import) echo "$RE_GX_IMPORT" ;;
  esac
}

miss=0; total=0
while IFS="$(printf '\t')" read -r area name code; do
  total=$((total + 1))
  # 1. the cheap prefilter (not needed for extension members: those are counted only inside files that import get)
  if [ "$area" != ext ] && ! printf '%s\n' "$code" | grep -qE "$RE_GX_PREFILTER"; then echo "GAP  [$area] $name: the whole-project prefilter does not match:  $code"; miss=$((miss + 1)); fi
  # 2. its own area
  if ! printf '%s\n' "$code" | grep -qE "$(re_for "$area")"; then echo "GAP  [$area] $name: the $area pattern does not match:  $code"; miss=$((miss + 1)); fi
done < "$TMP/samples"

# 3. end to end: one file per sample, every file importing get
i=0
while IFS="$(printf '\t')" read -r area name code; do
  i=$((i + 1))
  { echo "import 'package:get/get.dart';"; echo "$code"; } > "lib/s/s$i.dart"
done < "$TMP/samples"
bash "$SCR/audit.sh" . > "$TMP/audit.json" 2>/dev/null
if [ -s "$TMP/audit.json" ]; then
  tot="$(sed -nE 's/^ *"total": *([0-9]+),.*/\1/p' "$TMP/audit.json" | head -n1)"
  imp="$(grep -oE '"files_importing_get": *[0-9]+' "$TMP/audit.json" | head -n1 | grep -oE '[0-9]+$')"
  echo "end to end: $i sample files, audit counts $imp importing get, GetX usages total ${tot:-?}"
  [ "${imp:-0}" -eq "$i" ] || { echo "GAP  audit saw $imp of $i files that import get"; miss=$((miss + 1)); }
  [ "${tot:-0}" -ge "$i" ] || { echo "GAP  audit total ($tot) is lower than the number of sample files ($i): some samples are not counted"; miss=$((miss + 1)); }
else
  echo "GAP  audit.sh produced no output on the sample project"; miss=$((miss + 1))
fi
if ! bash "$SCR/../../clean-arch-presentation/scripts/kill_getx_scan.sh" . 2>/dev/null | grep -q '"files"'; then echo "GAP  kill_getx_scan.sh failed on the sample project"; miss=$((miss + 1)); fi

echo "checked $total catalog samples"
if [ "$miss" -eq 0 ]; then echo "OK: every GetX API in the catalog is recognised"; exit 0; fi
echo; echo "$miss gap(s) found."; exit 1
