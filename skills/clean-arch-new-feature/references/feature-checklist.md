# Feature definition of done

## Design
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
- [ ] Sealed state, cubit depends on use cases only
- [ ] `isClosed` check after every await before emit
- [ ] Page provides cubit via `AutoRouteWrapper`
- [ ] Loading / error+retry / empty states
- [ ] Strings in `.arb`, tokens for style

## Wiring
- [ ] Routes registered, guard behavior checked
- [ ] Providers spread in `global_providers.dart`
- [ ] Flag in `AppConfig` if switchable (routes + providers conditional)

## Verification (run and report output)
- [ ] `dart format --set-exit-if-changed .`
- [ ] `flutter analyze --fatal-infos`
- [ ] `flutter test`
- [ ] `scripts/check_dependencies.sh lib`
