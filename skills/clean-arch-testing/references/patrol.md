# Patrol end-to-end tests

Used by `/e2e`. Patrol (by LeanCode) drives the real app on a device or emulator and can also interact with the native layer: permission dialogs, notifications, the system UI, the home button. Use it for the few critical flows named in `SKILL.md` ("Integration"), not for logic that a unit or widget test covers.

## Rules

- **Few, stable, independent.** Three to six flows (login, the main transaction, a permission-gated feature). Each test sets up its own state and does not depend on another test running first.
- **Mock-backed.** No test hits the real network, real storage or the real clock. Run against the app's mock flavor/flag (`AppConfig.useMocks` fed by `--dart-define`), so the same flow gives the same result every run.
- **Stable finders.** Prefer widget keys (`Key('transfer_submit')`, found with `$(#transfer_submit)`) or text from the localized resources; avoid positional finders. Add keys in the widget only where a flow needs them, and keep design-system components free of test-only logic.
- **Native steps only where native things happen**: permission dialogs, notifications, system settings. Everything else uses Flutter finders.
- Tests live in `patrol_test/`, one file per flow, named `<flow>_test.dart`.

## What the project needs

The setup has a Dart side and a native side, and the native side changes between Patrol major versions. Do not copy it from memory: read the installed version's own material (the package in the pub cache has a README, CHANGELOG and, usually, an `example/` with the native files).

| Part | Check |
|---|---|
| `patrol` in `dev_dependencies` | `flutter pub add --dev patrol` (the user runs it) |
| `patrol_cli` on the machine | `dart pub global activate patrol_cli`; then `patrol doctor` |
| `patrol:` block in `pubspec.yaml` | app name, Android `package_name`, iOS `bundle_id` |
| Android | an instrumentation test class (`MainActivityTest`) under `android/app/src/androidTest/`, and the Gradle test runner/orchestrator options |
| iOS | a `RunnerUITests` target in the Xcode project |
| A way to start the app in mock mode | a `--dart-define` flag such as `useMocks` |

## Test shape (verify names against the installed version)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest('transfer: user completes a transfer', ($) async {
    await $.pumpWidgetAndSettle(const App());      // the app's root widget, started with mocks
    await $(#accountTile).tap();
    await $(#transferAmount).enterText('25');
    await $(#transferSubmit).tap();
    expect($('Transfer completed'), findsOneWidget);
  });
}
```

Native step, only where a permission dialog appears:

```dart
if (await $.native.isPermissionDialogVisible()) {
  await $.native.grantPermissionWhenInUse();       // or denyPermission(), grantPermissionOnlyThisTime()
}
```

Newer Patrol majors may expose the native automator under a different accessor (for example `$.platform.mobile`) and rename methods. Before writing a test, grep the installed package source for the method names you plan to use, and use what is there.

## Running

```bash
patrol doctor
patrol test --target patrol_test/transfer_test.dart --dart-define=useMocks=true
```

Needs a connected device or running emulator/simulator (`flutter devices`). In CI, run the same command on an emulator job. Report the real result; never claim a pass that was not run.

## Checklist

- [ ] Each test starts from a known mock state and passes alone
- [ ] No real network, storage or clock
- [ ] Finders are keys or localized text, not positions
- [ ] Native automation used only for native dialogs/notifications
- [ ] Method names verified against the installed `patrol` version
- [ ] The tests were actually run on a device, or the report says they were not
