# Error and loading patterns

Decide these once at project level, implement them as design-system components, and reuse them everywhere.

## Errors

| Scenario | Pattern |
|---|---|
| Error while loading a screen | Full-screen message/illustration with a **retry** button |
| Part of a screen fails to load (a screen backed by several calls) | Show the rest of the content; show a small inline error with a retry button where the part failed |
| Next page of a paginated list fails | Error row at the bottom of the list with a retry; items already loaded stay visible |
| Error on a user action (form submit, button) | Contextual message near the action instead of a new full-screen error, so the user keeps the context and can retry |

Rules:

- Every failure has a **retry** path. Do not strand the user on a screen they can only leave by going back.
- Prefer **precise** messages when they help the user resolve the problem; a generic message only when extra detail is not useful.
- Map `AppFailure` to text in one place (a shared extension/helper, using l10n). Cubits hold the failure, never the string.

## Connectivity

- Treat network errors differently from other failures: say clearly that there is no connection.
- When the connection returns, **retry the failed network requests automatically**.
- A reliable way to monitor connectivity is to call the backend's health endpoint at short intervals (platform "is connected" signals can report connectivity that does not reach your API). Expose the result from one app-wide place (`core/connectivity`) rather than per screen.

## Loading

| Scenario | Pattern |
|---|---|
| Loading a whole screen | Full-screen loading |
| Loading part of a screen | Local placeholder/spinner for that part |
| Loading the next page of a list | Spinner row at the bottom |
| Loading on a user action (submit) | Disable the action and show progress on it |

Define each as a reusable design-system widget and decide the exact look once per project.
