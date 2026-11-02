---
description: Scaffold and run Patrol end-to-end tests (LeanCode) for the app's critical flows, including native interactions such as permission dialogs and notifications. Checks setup, writes patrol_test/ files, and runs them on a connected device if you agree.
argument-hint: "[flow-name ...]"
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
---

# /e2e

Set up and run Patrol end-to-end tests. Follow `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-testing/references/patrol.md` and the Integration rules in `clean-arch-testing`: few, stable, independent tests, against a mock-backed app. Read them first.

`$ARGUMENTS` may name the flows to test (for example `login transfer`).

Gates that apply here (clean tree before editing native files or `pubspec.yaml`, confirmation before changes, real results only) and the order of the commands are in `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-overview/references/migration-workflow.md`. `/e2e` can run early, as a safety net before a migration, or at the end.

## Steps

1. **Scan** (read-only, does not run Flutter or Patrol):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-testing/scripts/e2e_scan.sh" "<project root>"
   ```

   Show a readiness table from the JSON: tools on this machine (`flutter`, `patrol_cli`, `adb`, `xcrun`), `patrol` in `pubspec` and its version, the `patrol:` config block, `patrol_test/`, Android native setup (`main_activity_test`, `instrumentation_runner`, `test_options_or_orchestrator`), iOS (`runner_ui_tests_dir`), whether the app can start in mock mode (`mock_flag_present`), widget keys and semantics available, features, and native-capability packages (notifications, permissions, biometrics...). Mark each item ready / missing.

2. **Dependencies and tools (the user installs them).** If `patrol` is missing from `dev_dependencies`, print `flutter pub add --dev patrol`; if `patrol_cli` is missing, print `dart pub global activate patrol_cli`, then `patrol doctor`. Do not run these yourself. Stop here until they exist, unless the user only wants the test files written.

3. **Mock mode gate.** If `mock_flag_present` is false, tell the user the tests would hit the real backend and be unstable; recommend `AppConfig.useMocks` fed by `--dart-define` (see `clean-arch-di-routing`) and ask whether to continue without it (default: stop).

4. **Pick the flows.** If `$ARGUMENTS` named none, propose 3 to 5 from `flows.features`, `route_paths` and `native_capability_packages` (login or start-up, the main user action, one permission/notification flow) and ask with AskUserQuestion which to scaffold. Keep the number small.

5. **Native setup.** For anything missing in the Android/iOS rows, explain what is needed. The native files change between Patrol majors: read the installed package (`pubspec.patrol_package_source` in the scan; its README, CHANGELOG and `example/`) and copy the shape from there, adapting the application id/bundle id. Ask before creating or editing any file under `android/` or `ios/`. The Xcode `RunnerUITests` target cannot be created reliably by editing files: give the exact steps from the installed Patrol docs and let the user do them. Add the `patrol:` block to `pubspec.yaml` (app name, `application_id`/`bundle_id` from the scan) after asking.

6. **Write the tests.** One file per flow in `patrol_test/<flow>_test.dart`, from `${CLAUDE_PLUGIN_ROOT}/skills/clean-arch-testing/templates/patrol_flow_test.dart.tpl` (and `patrol_permission_test.dart.tpl` for a native permission/notification flow). Fill `{{package}}`, `{{app_import}}`, `{{AppWidget}}` from the project (`app.root_widgets` is a hint; read `lib/main.dart`). Before using any Patrol method, grep the installed package source and use the names that exist. Fill the steps by reading the real screens: finders are keys or localized text, never positions. If a widget needs a key, add the smallest possible `Key` (list each addition) after asking. Keep each test independent and mock-backed.

7. **Run (ask first).** Check `flutter devices`. If a device or emulator is available, ask whether to run, then:

   ```bash
   patrol doctor
   patrol test --target patrol_test/<flow>_test.dart --dart-define=<mock flag>=true
   ```

   Report the real output. If no device is available, or the user declines, say the tests were written but **not run**. Never claim a pass that was not run. On failure, show the relevant output, fix test-side mistakes (a wrong finder, a missing wait) at most twice per test, and report app-side problems without changing app logic.

8. **Report.** Run `dart format` on the test files and any Dart file you changed. Flows scaffolded, files created or changed (including native ones and any added keys), setup items still missing, what ran and its real result, and how to run them in CI (`patrol test` on an emulator job).

## Rules

- Never edit `android/`, `ios/`, `pubspec.yaml` or app widgets without asking first, and list every change.
- Never run `flutter pub add`, `dart pub global activate` or `patrol bootstrap`-style installers yourself.
- Tests never use the real network, storage or clock; they start from a known mock state.
- Native automation only for native dialogs and notifications.
- Few tests; each must pass alone.
- Never edit files with the `DEPRECATED: migrated by /feature --migrate` header.
