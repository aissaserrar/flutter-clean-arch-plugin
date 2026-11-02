// ===== patrol_test/{{flow}}_permission_test.dart =====
// Template for /e2e: a flow that triggers a native permission dialog.
// Native method names (and the accessor, e.g. $.native vs $.platform.mobile) depend on the installed
// patrol version: grep the package source and adjust before use.
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:{{package}}/{{app_import}}';

void main() {
  patrolTest(
    '{{flow}}: allowing the permission enables the feature',
    ($) async {
      await $.pumpWidgetAndSettle(const {{AppWidget}}());

      // Trigger the request from the UI.
      // await $(#enableNotifications).tap();

      // Handle the system dialog only if it appears (it does not on a second run).
      if (await $.native.isPermissionDialogVisible()) {
        await $.native.grantPermissionWhenInUse();
      }

      // expect($('Notifications enabled'), findsOneWidget);
    },
  );

  patrolTest(
    '{{flow}}: denying the permission shows the fallback',
    ($) async {
      await $.pumpWidgetAndSettle(const {{AppWidget}}());

      // await $(#enableNotifications).tap();
      if (await $.native.isPermissionDialogVisible()) {
        await $.native.denyPermission();
      }

      // expect($('Permission needed'), findsOneWidget);
    },
  );
}
