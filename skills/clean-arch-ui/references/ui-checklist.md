# UI review checklist

## Structure
- [ ] Public `<Feature>Page` provides the cubit (`wrappedRoute` for auto_route, `BlocProvider` for go_router); content is private `_<Feature>Content`
- [ ] `build` methods are short; sub-widgets are classes, not `Widget _buildX()` methods
- [ ] Reusable widgets take plain parameters and callbacks (no cubit inside design_system or shared widgets)

## State
- [ ] Sealed state handled with an exhaustive `switch`
- [ ] `BlocSelector` / `context.select` where only part of the state is used
- [ ] `listenWhen` set so listeners fire on transitions, not on every rebuild
- [ ] No navigation or snackbar inside `build`; one-off effects use `BlocPresentationListener`

## Content
- [ ] No hard-coded strings: `context.l10n`
- [ ] No literal colors, paddings or text styles: design tokens
- [ ] No direct `material`/`cupertino` widgets: design system components
- [ ] Loading, error with retry, empty states present
- [ ] Failure to text via the shared extension; precise message when it helps the user
- [ ] Network errors shown as no-connection feedback; retry after reconnect
- [ ] Analytics ids on page and buttons (`clean-arch-observability`)

## Robustness
- [ ] Controllers, focus nodes and animation controllers created in `State` and disposed
- [ ] Submit disabled while loading
- [ ] Text scales: no fixed heights around text
- [ ] Icon-only buttons have a tooltip or semantic label

## Imports (must be absent)
- `/data/` anything
- Another feature's folder
- `dio`, `http`, `shared_preferences`
