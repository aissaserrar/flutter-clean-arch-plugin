---
name: clean-arch-observability
description: Use when adding or reviewing logging or analytics in a Flutter feature: log levels, what to log and not to log, global uncaught-exception logging, which levels to upload per environment, and analytics ids for pages and buttons (<feature>_ids.dart, <Feature>AnalyticsId).
---

# Logging and analytics rules

## Logging

Use the shared logger from `core/logging`. Never `print`.

### What to log

- **Expected exceptions, when you catch them** (for example an external library that throws instead of returning errors): log in the `catch` block.
- **Unexpected uncaught exceptions:** one global mechanism logs them all (`FlutterError.onError`, `PlatformDispatcher.instance.onError`, and a guarded zone). Do not rely on each feature to do it.
- **Traces that let you follow what the user did:** every navigation, and the lifecycle of business processes (start and end of a tracked activity, for example).

### What never to log

- Personal information (an email address is the one allowed exception).
- Secrets: passwords, keys, tokens, and so on.

### Levels

| Level | Use for |
|---|---|
| **Fine** | Normal situation, used for debugging on a test environment |
| **Info** | Normal situation, used to follow user actions in production |
| **Warning** | Abnormal but expected situation (network error, validation error) |
| **Severe** | Unexpected situation (unknown server error, unexpected exception) |

### What to upload

| Environment | Upload |
|---|---|
| Test | Fine, Info, Warning, Severe |
| Production | Info, Warning, Severe |

### Avoid noise

Do not log actions that are automatic and frequent (a timer every 5 seconds) each time: it makes logs unreadable and exhausts logging quotas. Temporary Fine logs for debugging one feature are fine.

## Analytics

### Ids live with the feature

Define ids per feature in `<feature_name>_ids.dart`, in the feature's root folder, as a `<FeatureName>AnalyticsId` class.

### Pages

Assign an id to every page. Define them as static strings at the top of the class:

- `page = '<FeatureName>Page'`
- `<pageName>Page = '<FeatureName><PageName>Page'`

### Buttons and other clickable elements

Assign an id to every button and clickable element. Define them below the page ids, as static fields or methods, as `AnalyticsId` instances:

- `<action>Button = AnalyticsId('<Action>Button', page)`
- `<action>Button(String page) => AnalyticsId('<Action>Button', page)` when a multi-page feature has name conflicts

```dart
// features/transfers/transfers_ids.dart
abstract final class TransfersAnalyticsId {
  static const page = 'TransfersPage';
  static const detailsPage = 'TransfersDetailsPage';

  static const submitButton = AnalyticsId('SubmitButton', page);
  static AnalyticsId cancelButton(String page) => AnalyticsId('CancelButton', page);
}
```

## Checklist before finishing

- [ ] Caught expected exceptions are logged; none are swallowed silently
- [ ] No sensitive data in log messages
- [ ] Correct level per message; levels uploaded per environment
- [ ] Navigation traces exist
- [ ] `<feature>_ids.dart` has the page ids and an id for every button
