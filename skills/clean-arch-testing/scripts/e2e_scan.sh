#!/usr/bin/env bash
# Reports how ready a Flutter project is for Patrol end-to-end tests, and what flows and native features it has.
# Usage: e2e_scan.sh [project_root]
# Prints one JSON document on stdout. Read-only: writes nothing, no network, does not run flutter or patrol
# (it only checks whether the executables exist and reads files).
# Exit code 0 = ok, 2 = not a Flutter project root.
set -u

ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "Cannot enter $ROOT" >&2; exit 2; }
[ -f pubspec.yaml ] && [ -d lib ] || { echo "Run against a Flutter project root (pubspec.yaml + lib/)" >&2; exit 2; }

jstr() { printf '%s' "$1" | tr -d '\000-\037' | sed -e 's/\\/\//g' -e 's/"/'"'"'/g'; }
pub() { grep -qE "^[[:space:]]*$1:" pubspec.yaml && echo true || echo false; }
arr() { awk 'BEGIN{printf "["} NF {g=$0; gsub(/\\/,"/",g); gsub(/"/,"\047",g); printf "%s\"%s\"", (n++?",":""), g} END{printf "]"}'; }

# ---- Tooling on this machine ----
have_flutter=false; command -v flutter >/dev/null 2>&1 && have_flutter=true
have_patrol_cli=false; command -v patrol >/dev/null 2>&1 && have_patrol_cli=true
have_adb=false; command -v adb >/dev/null 2>&1 && have_adb=true
have_xcrun=false; command -v xcrun >/dev/null 2>&1 && have_xcrun=true

# ---- Patrol in the project ----
patrol_dep="$(pub patrol)"; patrol_finders="$(pub patrol_finders)"; integration_test="$(grep -qE "^[[:space:]]*integration_test:" pubspec.yaml && echo true || echo false)"
patrol_version=""
[ -f pubspec.lock ] && patrol_version="$(awk '/^  patrol:$/ {f=1} f && /version:/ {gsub(/"/,"",$2); print $2; exit}' pubspec.lock)"
cache="${PUB_CACHE:-$HOME/.pub-cache}"; patrol_src=""
[ -n "$patrol_version" ] && [ -d "$cache/hosted/pub.dev/patrol-$patrol_version" ] && patrol_src="$cache/hosted/pub.dev/patrol-$patrol_version"
patrol_cfg=false; grep -qE "^patrol:" pubspec.yaml && patrol_cfg=true
cfg_app_name="$(awk '/^patrol:/ {f=1; next} f && /^[^ ]/ {f=0} f && /app_name:/ {sub(/.*app_name:[ ]*/,""); gsub(/["\r]/,""); print; exit}' pubspec.yaml)"
cfg_pkg="$(awk '/^patrol:/ {f=1; next} f && /^[^ ]/ {f=0} f && /package_name:/ {sub(/.*package_name:[ ]*/,""); gsub(/["\r]/,""); print; exit}' pubspec.yaml)"
cfg_bundle="$(awk '/^patrol:/ {f=1; next} f && /^[^ ]/ {f=0} f && /bundle_id:/ {sub(/.*bundle_id:[ ]*/,""); gsub(/["\r]/,""); print; exit}' pubspec.yaml)"

# ---- Test folders and existing tests ----
patrol_dir=false; [ -d patrol_test ] && patrol_dir=true
integ_dir=false; [ -d integration_test ] && integ_dir=true
existing_tests="$(find patrol_test integration_test -name '*_test.dart' 2>/dev/null | sort)"

# ---- Native setup (Android / iOS) ----
android_dir=false; [ -d android ] && android_dir=true
ios_dir=false; [ -d ios ] && ios_dir=true
android_test_file="$(find android/app/src/androidTest -name 'MainActivityTest.*' 2>/dev/null | head -n1)"
gradle_file=""; [ -f android/app/build.gradle ] && gradle_file=android/app/build.gradle; [ -f android/app/build.gradle.kts ] && gradle_file=android/app/build.gradle.kts
g_runner=false; g_orch=false; app_id=""
if [ -n "$gradle_file" ]; then
  grep -qE "testInstrumentationRunner" "$gradle_file" && g_runner=true
  grep -qE "ANDROIDX_TEST_ORCHESTRATOR|testOptions" "$gradle_file" && g_orch=true
  app_id="$(sed -nE "s/.*applicationId *=? *['\"]([^'\"]+)['\"].*/\1/p" "$gradle_file" | head -n1)"
fi
ios_uitests=false; [ -d ios/RunnerUITests ] && ios_uitests=true
bundle_id="$(grep -hE "PRODUCT_BUNDLE_IDENTIFIER" ios/Runner.xcodeproj/project.pbxproj 2>/dev/null | grep -v RunnerTests | grep -v UITests | head -n1 | sed -E 's/.*= *([^;]+);.*/\1/' | tr -d ' ')"
flavors=false; [ -n "$gradle_file" ] && grep -qE "flavorDimensions|productFlavors" "$gradle_file" && flavors=true

# ---- App readiness for stable e2e ----
mock_flag="$(grep -rhoE --include='*.dart' "(bool|String)\.fromEnvironment\('[A-Za-z_]*[Mm]ock[A-Za-z_]*'" lib 2>/dev/null | head -n1)"
use_mocks_ref="$(grep -rlE --include='*.dart' "useMocks" lib 2>/dev/null | wc -l | tr -d ' ')"
keys_used="$(grep -rhoE --include='*.dart' "Key\('[^']+'\)" lib 2>/dev/null | wc -l | tr -d ' ')"
semantics_labels="$(grep -rhoE --include='*.dart' "semanticsLabel|Semantics\(" lib 2>/dev/null | wc -l | tr -d ' ')"
app_widget="$(grep -rhE --include='*.dart' "^class +[A-Za-z0-9_]+ +extends +(StatelessWidget|StatefulWidget)" lib/app.dart lib/main.dart 2>/dev/null | head -n3 | sed -E 's/class +([A-Za-z0-9_]+).*/\1/' | paste -sd, -)"
main_has_run="$(grep -cE "runApp\(" lib/main.dart 2>/dev/null || true)"

# ---- Flows and native features worth testing ----
features="$(ls lib/features 2>/dev/null | sort)"
native_hits=""
for p in permission_handler firebase_messaging flutter_local_notifications awesome_notifications geolocator location image_picker camera local_auth url_launcher share_plus contacts_service flutter_contacts record speech_to_text bluetooth flutter_blue_plus; do
  grep -qE "^[[:space:]]*$p:" pubspec.yaml && native_hits="$native_hits$p
"
done
n_tests_unit="$(find test -name '*_test.dart' 2>/dev/null | wc -l | tr -d ' ')"
routes="$(grep -rhoE --include='*.dart' "path: *['\"][^'\"]+['\"]" lib 2>/dev/null | sed -E "s/path: *['\"]([^'\"]+)['\"]/\1/" | sort -u | head -n 40)"

cat <<JSON
{
  "project": "$(jstr "$(basename "$(pwd)")")",
  "tools": {"flutter": $have_flutter, "patrol_cli": $have_patrol_cli, "adb": $have_adb, "xcrun": $have_xcrun},
  "pubspec": {"patrol": $patrol_dep, "patrol_finders": $patrol_finders, "integration_test": $integration_test, "patrol_version": "$(jstr "$patrol_version")", "patrol_package_source": "$(jstr "$patrol_src")", "patrol_config_block": $patrol_cfg, "config": {"app_name": "$(jstr "$cfg_app_name")", "android_package_name": "$(jstr "$cfg_pkg")", "ios_bundle_id": "$(jstr "$cfg_bundle")"}},
  "tests": {"patrol_test_dir": $patrol_dir, "integration_test_dir": $integ_dir, "existing": $(printf '%s\n' "$existing_tests" | arr), "unit_and_widget_test_files": $n_tests_unit},
  "native": {
    "android": {"dir": $android_dir, "main_activity_test": $([ -n "$android_test_file" ] && echo true || echo false), "main_activity_test_file": "$(jstr "$android_test_file")", "gradle_file": "$(jstr "$gradle_file")", "instrumentation_runner": $g_runner, "test_options_or_orchestrator": $g_orch, "application_id": "$(jstr "$app_id")", "flavors": $flavors},
    "ios": {"dir": $ios_dir, "runner_ui_tests_dir": $ios_uitests, "bundle_id": "$(jstr "$bundle_id")"}
  },
  "app": {"main_dart_calls_run_app": $([ "${main_has_run:-0}" -gt 0 ] && echo true || echo false), "root_widgets": "$(jstr "$app_widget")", "mock_flag_present": $([ -n "$mock_flag" ] || [ "${use_mocks_ref:-0}" -gt 0 ] && echo true || echo false), "mock_flag": "$(jstr "$mock_flag")", "widget_keys": ${keys_used:-0}, "semantics_markers": ${semantics_labels:-0}},
  "flows": {"features": $(printf '%s\n' "$features" | arr), "route_paths": $(printf '%s\n' "$routes" | arr), "native_capability_packages": $(printf '%s' "$native_hits" | arr)}
}
JSON
