# What to test, by layer

| Layer | Unit under test | Fake / mock | Must cover |
|---|---|---|---|
| Domain entity | getters, equality, value objects | none | edge values (0, negative, empty) |
| Use case | `call()` | repository interfaces | each business rule branch, each returned failure, "does not call X when Y" |
| Mapper | extension/function | none | null, empty, unknown enum, negative, locale-specific formats |
| Data source | request building + parsing | fake `http.Client` | path, headers, body, sample real responses |
| Repository impl | success + failures | data sources | DTO to entity, every exception to failure, cache hit/miss |
| Cubit / Bloc | state sequence | **use cases** | success, each failure, retry, guard against double submit, refresh keeps data |
| Widget | one behavior per state | mocked cubit | loading, error + retry, empty, content, taps call cubit methods |
| Golden | design-system widgets, key screens | none | light/dark, text scale if relevant |
| Integration | critical flows | mock-backed flavor | login, main transaction |

## Conventions

- File name = source file name + `_test.dart`, same relative path under `test/`.
- Group by class and method: `group('TransferMoney', () { test('returns ... when ...') })`.
- Arrange builders at the bottom of the file (`_aTransfer()`), not shared mutable fixtures.
- JSON fixtures in `test/fixtures/*.json`, loaded by a helper.
- Inject `Clock` (the `clock` package) instead of calling `DateTime.now()` in code under test.

## Commands

```bash
flutter test                                  # all
flutter test test/features/accounts           # one feature
flutter test --coverage                       # lcov in coverage/
flutter test --update-goldens                 # only when the UI change is intended
```
