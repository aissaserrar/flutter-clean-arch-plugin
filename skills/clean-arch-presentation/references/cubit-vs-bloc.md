# Cubit or Bloc?

| Need | Choose |
|---|---|
| Load data, submit a form, toggle something | **Cubit** |
| Debounce / throttle input (search as you type) | **Bloc** + transformer |
| Ignore repeated taps while working (`droppable`) | Cubit with a state guard is enough; Bloc if many triggers |
| Cancel an in-flight request when a new one starts | **Bloc** + `restartable()` |
| Event log / replay / analytics per event | **Bloc** |
| Several different triggers produce the same transition | **Bloc** |

Default: Cubit. Migrate to Bloc only when a concrete need above appears.

# State design cheat sheet

| Situation | Pattern |
|---|---|
| Screen has distinct phases | `sealed class` with Loading / Loaded / Failed |
| Many independent fields (form, filters) | one class with `copyWith` and a status enum |
| Refresh must keep showing old data | `Loaded(data, isRefreshing)` or `Failed(failure, lastData)` |
| Pagination | `Loaded(items, hasMore, isLoadingMore)` |

State must hold: entities or small presentation models, `AppFailure`, flags.
State must not hold: DTOs, localized strings, `BuildContext`, controllers, futures.

# Lifecycle

- Created by the page (`BlocProvider(create: ...)`), closed automatically with the route.
- Subscriptions inside a cubit are cancelled in `close()`:

```dart
@override
Future<void> close() {
  _subscription?.cancel();
  return super.close();
}
```
- Cubit-to-cubit communication: prefer a shared use case or stream from `core`; avoid cubits holding references to each other.
