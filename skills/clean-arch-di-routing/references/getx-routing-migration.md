# GetX routing to go_router or auto_route

Used by `/route`. The plugin supports **both** routers (never mixed in one app). If the user did not say which one, ask; if `pubspec.yaml` already lists one, keep it. The target-specific rules live in `go-router.md` and in the `auto_route` section of `SKILL.md`; this file only adds the migration mapping.

## Common to both

- Features expose **page widgets**; the app owns the routes. Features never import each other's pages.
- Route parameters are **ids/primitives** (path parameters preferred over query parameters). `Get.arguments` carrying an object becomes an id the page's cubit uses to load the data; do not pass entities through routes (`extra` is lost on reload).
- A page provides its own cubit (`BlocProvider`) and builds a private `_<Feature>Content`. Where GetX used a `Binding` to create the controller, that creation moves to the page's `BlocProvider(create: ...)` (wiring itself is `/di`).
- Navigation from a cubit/bloc is not allowed. A `Get.to` inside a controller becomes a **presentation event** handled in the UI (`BlocPresentationListener`). While the class is still a `ChangeNotifier`/`GetxController`, do not invent a `BuildContext` there: leave the call, add `// TODO(route): presentation event (after /to-bloc)`, and list it.
- Deep links: define explicit paths for URLs sent to users (emails, push) and redirect them to the real locations.
- `GetMaterialApp` is converted **last**, after pages and calls. Once it is gone, `Get.snackbar`, `Get.dialog` and `Get.context` stop working: they are manual items (`ScaffoldMessenger`, `showDialog` with a `BuildContext`).

## Call mapping

| GetX | go_router (typed routes) | auto_route |
|---|---|---|
| `Get.to(() => XPage())`, `Get.toNamed('/x')` | `XRoute(...).push(context)` | `context.router.push(XRoute(...))` |
| `Get.off`, `Get.offNamed` | `XRoute(...).pushReplacement(context)` | `context.router.replace(XRoute(...))` |
| `Get.offAll`, `Get.offAllNamed` | `XRoute(...).go(context)` | `context.router.replaceAll([XRoute(...)])` |
| `Get.offUntil(...)` | `go` to the canonical location of that screen | `context.router.popUntil(...)` / `pushAndPopUntil` |
| `Get.back()` | `context.pop()` | `context.router.maybePop()` |
| `Get.arguments`, `Get.parameters['id']` | a constructor field of the route class (`:id` path parameter) read by the page | `@PathParam('id')` / `@QueryParam` constructor parameter on the page |
| `Get.currentRoute` | `GoRouterState.of(context).uri` | `context.router.current.name` |
| `GetMiddleware` (auth) | `GoRouter(redirect: ...)` listening to the auth cubit (`refreshListenable`) | `AutoRouteGuard` (`onNavigation`) |
| `unknownRoute` | `errorBuilder` | a catch-all route / `RedirectRoute` |
| `initialRoute` | `initialLocation` | the route with `initial: true` |
| `GetMaterialApp(getPages: ...)` | `MaterialApp.router(routerConfig: router)` | `MaterialApp.router(routerConfig: appRouter.config())` |
| custom `transition:` | `CustomTransitionPage` in `buildPage` | `CustomRoute(transitionsBuilder: ...)` |

Prefer `go` over `push` for go_router, except for pages reachable from several places. Do not write `context.go('/path')` with raw strings in widgets when typed routes are used.

## go_router layout (typed routes)

- `router/route_tree.dart`: the `TypedGoRoute` / `TypedShellRoute` declarations, in their own file.
- `router/routes.dart`: one `GoRouteData` class per route (`XRoute extends GoRouteData`, fields = path parameters), `build` returns the feature's page.
- `router/app_router.dart`: builds the `GoRouter` (`routes: $appRoutes`, `redirect`, `refreshListenable`, `errorBuilder`, `initialLocation`).
- Needs `go_router_builder` and `build_runner` as dev dependencies; generated `*.g.dart` parts are the only allowed `part` use.
- Naming: path segments kebab-case (`account-details`), path parameters camelCase (`:accountId`), `TransferRoute` matches `path: 'transfer'`.
- Without code generation (user declined `go_router_builder`): plain `GoRoute(path:, builder:)` and `context.go('/x')` / `context.push('/x')`, with path strings only in `router/`. Say plainly that this loses type safety.

## auto_route layout

- Pages annotated `@RoutePage()`; the page provides its cubit (`AutoRouteWrapper` with `BlocProvider`).
- `features/<f>/<f>_routes.dart` declares the feature's `AutoRoute` list; `router/app_router.dart` has an `@AutoRouterConfig()` class that spreads them; guards live in `router/`.
- Needs `auto_route_generator` and `build_runner` as dev dependencies. Generated `app_router.gr.dart` is not hand-edited.
- API names differ between auto_route major versions (`RootStackRouter` vs the older generated base class, `AutoRouteGuard`, `reevaluateListenable`): read the installed version's README/CHANGELOG in the pub cache before writing code.

## Verification checklist

- [ ] Every `GetPage` has a route; paths follow the naming rules; parameters are ids
- [ ] No `Get.to*`, `Get.off*`, `Get.back`, `Get.arguments`, `GetPage`, `GetMiddleware` left (or listed with a reason)
- [ ] Guard behaviour checked for logged-out and logged-in
- [ ] `GetMaterialApp` replaced last; snackbar/dialog uses listed as manual
- [ ] `build_runner` output is up to date and `flutter analyze` is not worse than the baseline
