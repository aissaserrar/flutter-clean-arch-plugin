# ChangeNotifier (interim form) to Cubit / Bloc

Used by `/to-bloc`. The input is the interim form left by `/kill-getx` (a `ChangeNotifier` read through `ListenableBuilder`), or any hand-written `ChangeNotifier` / `ValueNotifier`. The output must follow `clean-arch-presentation` and `clean-arch-ui`; this file only adds the conversion mapping.

## What to convert, and what to leave alone

Convert state that is **shared, asynchronous or business-relevant**: loaded data, loading/error status, submitted forms, lists with filters, anything more than one widget reads.

Leave in the widget (local `StatefulWidget` state) the **ephemeral UI state**: animation controllers, text editing controllers, focus nodes, scroll controllers, the selected tab index, an expanded/collapsed toggle with no async work. Converting those adds boilerplate and no value. When a `StatefulWidget` only matches because it calls `setState` after an `await`, convert that part only if it loads data or reports errors.

## Cubit or Bloc

Default to **Cubit**. Pick **Bloc** only when the class needs an event transformer (debounced search, `droppable` submit, `restartable` refresh) or several triggers feed one state change. The scanner's `suggested: bloc` is a hint from `Timer`/`debounce`/`listen` in the file: confirm by reading the code. See `cubit-vs-bloc.md`.

## Designing the state from the notifier's fields

| The notifier has | State design |
|---|---|
| a loading flag, a data field and maybe an error | sealed `<Feature>State` with `Initial`, `Loading`, `Success(data)`, `Failure(failure)` (default) |
| several independent fields that change separately (form, filters, list plus selection) | one state class with a `status` enum (`initial`, `loading`, `success`, `failure`) and `copyWith` generated with `copy_with_extension_gen` |
| an error message `String` | the `AppFailure`/failure object instead; the UI maps it to localized text |
| a value shown while refreshing | keep it in `Success` (`isRefreshing`) or `Failure(lastData)` |

States extend `Equatable`, are `const`-constructible, and hold UI-ready data only. Use the variant names `Initial`, `Loading`, `Success`, `Failure`; never `Idle`, `Loaded`, `Error`.

## Class mapping

| ChangeNotifier | Cubit |
|---|---|
| `class X extends ChangeNotifier` | `class XCubit extends Cubit<XState>` (add `with BlocPresentationMixin<XState, XPresentationEvent>` only if there are one-off effects) |
| private fields `_items`, `_loading` | fields of the state (`Success.items`); the Cubit holds no mutable UI state |
| public getters | removed: the UI reads the state |
| `notifyListeners()` after a change | `emit(newState)` |
| `_loading = true; notifyListeners();` | `emit(const XStateLoading())` |
| `try { ... } catch (e) { _error = '$e'; }` | the repository/use case returns a `Result`; `switch` on it and emit `Failure(failure)`. Do not catch to hide bugs |
| every `await` in a method | `if (isClosed) return;` before the next `emit` |
| constructor dependencies | same constructor parameters (interfaces from `domain`, never `data/` internals) |
| `init()` / loading in the constructor | the page's `BlocProvider(create: (context) => XCubit(...)..load())` |
| `dispose()` | `close()` override that cancels subscriptions and timers, then `super.close()` |
| a callback that navigates or shows a snackbar | `emitPresentation(XPresentationEvent.completed)`; the UI handles it with `BlocPresentationListener` |
| `BuildContext` stored or passed in | remove it; move that logic to the widget |
| a double-submit risk | `if (state is XStateLoading) return;` |
| `addListener` between two notifiers | stream subscription cancelled in `close()`, or `BlocListener`; flag it, do not guess |

One public Cubit method per user intention (`load`, `submit`, `retry`). Business rules found in the notifier (limits, fee math) move to a use case, not into the Cubit.

## Widget mapping

| Before | After |
|---|---|
| `ChangeNotifierProvider(create: ...)` | `BlocProvider(create: ...)` in the **page**; the page provides its cubit |
| `ListenableBuilder(listenable: controller, ...)` | `BlocBuilder<XCubit, XState>` with an exhaustive `switch` over the sealed state; use `BlocSelector` or `buildWhen` to rebuild less |
| `Consumer<X>` / `context.watch<X>()` | `BlocBuilder` / `context.watch<XCubit>()` or `context.select` |
| `context.read<X>().method()` / `controller.method()` | `context.read<XCubit>().method()` in callbacks only |
| widget takes the controller as a constructor parameter | remove the parameter; read the cubit from context. Update every call site |
| listener that reacts to a one-off effect | `BlocPresentationListener<XCubit, XPresentationEvent>` |
| a listener on a state transition that is not an effect | `BlocListener` with `listenWhen`; `BlocConsumer` only when one widget needs both builder and listener |

Keep the existing layout and design system components; change only how state is read.

## One file

Cubit, then events (Bloc only), then state, then presentation events, all in `presentation/cubit/<feature>_cubit.dart` (or `presentation/bloc/<feature>_bloc.dart`). No `part` / `part of`.

## Worked example

Before (interim form):

```dart
class CartController extends ChangeNotifier {
  CartController(this._repo);
  final CartRepository _repo;
  List<CartItem> _items = [];
  bool _loading = false;
  Object? _error;
  List<CartItem> get items => _items;
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true; notifyListeners();
    try { _items = await _repo.all(); _error = null; }
    catch (e) { _error = e; }
    _loading = false; notifyListeners();
  }
}
```

After:

```dart
class CartCubit extends Cubit<CartState> {
  CartCubit(this._repo) : super(const CartStateInitial());
  final CartRepository _repo;

  Future<void> load() async {
    if (state is CartStateLoading) return;
    emit(const CartStateLoading());
    final result = await _repo.all();          // returns Result<List<CartItem>>
    if (isClosed) return;
    switch (result) {
      case Success(:final value):
        emit(CartStateSuccess(value));
      case Failure(:final failure):
        emit(CartStateFailure(failure));
    }
  }
}

sealed class CartState extends Equatable {
  const CartState();
  @override
  List<Object?> get props => const [];
}
final class CartStateInitial extends CartState { const CartStateInitial(); }
final class CartStateLoading extends CartState { const CartStateLoading(); }
final class CartStateSuccess extends CartState {
  const CartStateSuccess(this.items);
  final List<CartItem> items;
  @override
  List<Object?> get props => [items];
}
final class CartStateFailure extends CartState {
  const CartStateFailure(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}
```

If the repository still throws instead of returning a `Result`, do not change the repository in this step. Wrap the call in the cubit, map the exception to a failure object, and list it in the report as follow-up (`clean-arch-data` owns error mapping).

## Checklist per converted class

- [ ] One file, order: cubit, (events), state, presentation events; no `part`
- [ ] States sealed/equatable, `<Feature>State<Initial|Loading|Success|Failure>`, no strings
- [ ] No `BuildContext`, navigation, snackbar or widget types inside the cubit
- [ ] Every `await` followed by an `isClosed` check before `emit`
- [ ] Dependencies by constructor, interfaces from `domain` only
- [ ] The page provides the cubit; no widget creates it in `build`
- [ ] Every consumer updated, no remaining reference to the old class (or the old class is left and listed)
- [ ] `flutter analyze` errors not above the baseline; `check_dependencies.sh` run
- [ ] `bloc_test` cases for success and failure (see `clean-arch-testing`)
