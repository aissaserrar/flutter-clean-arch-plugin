# Feature definition of done

## Design
- [ ] Feature shape stated (thin / with repository / full domain) and layers match it
- [ ] Use cases listed (verbs), or documented decision to skip them for this feature
- [ ] Entities and failures named in business language
- [ ] Cross-feature needs resolved without importing another feature

## Domain
- [ ] No forbidden imports (`scripts/check_dependencies.sh` passes)
- [ ] Repository interface returns entities / `Result`
- [ ] Use case tests: every rule branch

## Data
- [ ] DTO + generated `.g.dart` (`dart run build_runner build --delete-conflicting-outputs`)
- [ ] Mapper tests incl. edge cases
- [ ] Repository maps every exception to a failure
- [ ] Mock repository available

## Presentation / UI
- [ ] Sealed state named `<Feature>State<Initial|Loading|Success|Failure>`; cubit, state and presentation events in one file
- [ ] Cubit depends on use cases / repository / API client as the shape requires; side effects use presentation events
- [ ] `isClosed` check after every await before emit
- [ ] Public Page provides the cubit; private `_<Feature>Content` renders it
- [ ] Loading / error+retry / empty states
- [ ] Strings in `.arb`, design system components and tokens for style
- [ ] Forms follow `clean-arch-forms`
- [ ] `<feature>_ids.dart` with page and button analytics ids; no sensitive data in logs

## Wiring
- [ ] Routes registered (auto_route or go_router), guard behavior checked
- [ ] Providers spread in `global_providers.dart`
- [ ] Flag in `AppConfig` if switchable (routes + providers conditional)

## Verification (run and report output)
- [ ] `dart format --set-exit-if-changed .`
- [ ] `flutter analyze --fatal-infos`
- [ ] `flutter test`
- [ ] `scripts/check_dependencies.sh lib`
