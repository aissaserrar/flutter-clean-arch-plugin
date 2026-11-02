# GetX to plain Flutter (interim form) to Cubit/Bloc

`/kill-getx` removes GetX but does not invent a new architecture: it moves code to an **interim form** that compiles, keeps behaviour and has no GetX. `/to-bloc` then turns the interim form into Cubits. Do not skip straight to Cubits in the same step: two changes at once make regressions hard to find.

Interim form = `ChangeNotifier` + `ListenableBuilder`. Both are in Flutter itself (`ListenableBuilder` needs Flutter 3.10+).

## Controllers and state

| GetX | Interim form |
|---|---|
| `class X extends GetxController` | `class X extends ChangeNotifier` |
| `class X extends GetxService` with no observable state | plain class |
| `final count = 0.obs;` / `Rx<int>(0)` | private field `int _count = 0;` plus getter `int get count => _count;` |
| `count.value` (read) | `count` |
| `count.value = v;`, `count(v)`, `count.value++` | `_count = v;` then `notifyListeners();` |
| `RxList` / `<T>[].obs` and `add`, `remove`, `assignAll` | private list; prefer replacing it (`_items = [..._items, v]`), then `notifyListeners()`; expose `List<T> get items => List.unmodifiable(_items)` |
| `update()`, `update(['id'])` | `notifyListeners()` (ids are dropped; say so in the report) |
| `onInit()` | constructor body, or an explicit `init()` that the owner calls |
| `onReady()` | explicit method called after the first frame; flag it, do not guess |
| `onClose()` | `@override void dispose() { ...; super.dispose(); }` |
| `ever`, `once`, `debounce`, `interval` | no clean equivalent: leave a `// TODO(to-bloc)` and list the file in the report |

Several mutations in one method: call `notifyListeners()` once at the end, not after each assignment.

## Widgets

| GetX | Interim form |
|---|---|
| `Obx(() => w)` | `ListenableBuilder(listenable: controller, builder: (context, _) => w)`; keep it around the smallest subtree that reads the state; several controllers: `Listenable.merge([a, b])` |
| `GetBuilder<C>(builder: (c) => w)` | `ListenableBuilder(listenable: c, builder: (context, _) => w)` |
| `class V extends GetView<C>` | `StatelessWidget` with `final C controller;` as a required constructor parameter |
| `GetWidget<C>` | same as `GetView` |
| `Get.find<C>()` inside a widget | constructor parameter for now; the real wiring is `/di` |

The controller must be created and disposed by something. If a screen used `Get.put` or a binding, that creation is `/di`'s job; until then create it in the nearest `StatefulWidget` state (`initState` / `dispose`) or pass it in.

## Not handled by `/kill-getx`

| GetX | Owner |
|---|---|
| `Get.to`, `Get.toNamed`, `Get.off*`, `Get.back`, `GetPage`, `Get.arguments` | `/route` |
| `Get.find`, `Get.put`, `Get.lazyPut`, `Bindings`, `GetMaterialApp` | `/di` (and `/route` for the app root) |
| `Get.snackbar`, `Get.dialog`, `Get.bottomSheet`, `Get.context`, `Get.width`, `.tr`, `GetConnect`, `GetUtils` | manual: needs a `BuildContext`, l10n or an HTTP decision |

A file that still has one of these keeps its `package:get` import. `kill_getx_finish.sh` only removes the import when nothing from GetX is left, including GetX extensions such as `2.seconds`, `.capitalizeFirst`, `.isBlank`.

## After the interim form

`/to-bloc` (details and a worked example in `notifier-to-cubit.md`): `ChangeNotifier` becomes `Cubit<State>` with sealed `Initial/Loading/Success/Failure` states (see `cubit-vs-bloc.md`), `ListenableBuilder` becomes `BlocBuilder`, and `notifyListeners()` becomes `emit(...)`.
