# Async startup dependencies

## Two cases

| Case | Where | Why |
|---|---|---|
| Quick and cannot fail (`SharedPreferences.getInstance`) | `main`, before `runApp` | Avoids a second loader after the splash screen. No error UI exists yet, so it must not fail, and it must be fast. |
| Can fail, is slow, or needs retry (force update, remote feature flags, session restore) | One wrapper widget inside `GlobalProviders` | Shows loading and error states and can retry. |

Define **just one** such wrapper and parallelize the loading as much as possible, to keep the wait short. Place it as low in the tree as it can go: it must be above anything that reads its values.

## The wrapper

```dart
class AsyncLoader extends StatelessWidget {
  const AsyncLoader({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => AsyncLoaderCubit()..fetch(),
        child: BlocBuilder<AsyncLoaderCubit, AsyncLoaderState>(
          builder: (context, state) => switch (state) {
            AsyncLoaderStateInitial() => const SizedBox(),
            AsyncLoaderStateLoading() => const AppSpinner(),
            AsyncLoaderStateFailure() => AppErrorView(
                message: context.l10n.startup_error,
                onRetry: context.read<AsyncLoaderCubit>().fetch,
              ),
            AsyncLoaderStateSuccess(:final a, :final c) => MultiProvider(
                providers: [Provider.value(value: a), Provider.value(value: c)],
                child: child,
              ),
          },
        ),
      );
}

class AsyncLoaderCubit extends Cubit<AsyncLoaderState> {
  AsyncLoaderCubit() : super(const AsyncLoaderStateInitial());

  Future<void> fetch() async {
    if (state is AsyncLoaderStateLoading) return;
    emit(const AsyncLoaderStateLoading());
    try {
      final (a, b) = await (loadA(), loadB()).wait;   // parallel
      final c = await loadC(a, b);                     // depends on the first two
      if (isClosed) return;
      emit(AsyncLoaderStateSuccess(a, c));             // only what you will provide
    } catch (_) {
      if (isClosed) return;
      emit(const AsyncLoaderStateFailure());
    }
  }
}

sealed class AsyncLoaderState { const AsyncLoaderState(); }
final class AsyncLoaderStateInitial extends AsyncLoaderState { const AsyncLoaderStateInitial(); }
final class AsyncLoaderStateLoading extends AsyncLoaderState { const AsyncLoaderStateLoading(); }
final class AsyncLoaderStateFailure extends AsyncLoaderState { const AsyncLoaderStateFailure(); }
final class AsyncLoaderStateSuccess extends AsyncLoaderState {
  const AsyncLoaderStateSuccess(this.a, this.c);
  final DepA a;
  final DepC c;
}
```

`Provider.value` is correct here: the values are created by the loader, not by the provider. The blanket `catch` is intentional at this boundary (it turns any startup failure into a retryable state); log the error before emitting the failure state.
