// ===== patrol_test/{{flow}}_test.dart =====
// Template for /e2e. Placeholders: {{package}}, {{app_import}}, {{AppWidget}}, {{flow}}.
// Verify every Patrol method name against the installed patrol version before using it.
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:{{package}}/{{app_import}}';

void main() {
  patrolTest(
    '{{flow}}: <what the user achieves>',
    ($) async {
      // The app must start in mock mode: run with --dart-define=useMocks=true
      // (the flag name comes from bootstrap/app_config.dart).
      await $.pumpWidgetAndSettle(const {{AppWidget}}());

      // 1. Arrive at the start of the flow (keys or localized text, never positions).
      // await $(#someKey).tap();

      // 2. Perform the user actions.
      // await $(#amountField).enterText('25');
      // await $(#submitButton).tap();

      // 3. Assert the visible outcome.
      // expect($('Expected text'), findsOneWidget);
    },
  );
}
