---
name: clean-arch-testing
description: Use when writing or reviewing tests for a Flutter Clean Architecture + Bloc app: unit tests for use cases and entities, mapper and repository tests, bloc_test for cubits/blocs, widget tests with mocked cubits, golden tests. Test file layout and what to mock at each layer.
---

# Testing rules by layer

`test/` mirrors `lib/`: `lib/features/accounts/domain/use_cases/get_accounts.dart` is tested in `test/features/accounts/domain/use_cases/get_accounts_test.dart`.

Libraries: `flutter_test`, `bloc_test`, `mocktail`. Prefer small hand-written fakes for repositories when behavior matters; use `mocktail` mocks for simple stubbing.

## Domain (most business tests live here)

- Plain `test`, no Flutter binding. **Test business logic by default**: most of it lives in use cases, entities and cubits.
- Entities: equality, derived getters, value-object validation.
- Use cases: fake/mock repository interfaces. Cover the happy path, **each business rule branch**, and each failure returned.
- No mocking of the thing under test. Assert on the returned `Result`, not on internal calls, unless the call is the behavior (for example "does not call transfer when over the limit").

## Data

- **Mappers**: DTO to entity and back, with null, empty and unknown-enum cases. JSON fixtures in `test/fixtures/`.
- **Repository impl**: fake data sources. One test per outcome: success mapped to entities, each exception type mapped to the right `Failure`, cache hit/miss if applicable.
- **Data sources**: fake HTTP client; verify request path/body and parsing of real sample responses.

## Presentation (cubits and blocs)

- Use `blocTest`; mock what the cubit depends on with `mocktail`: **use cases** in a full feature, the repository interface in a feature with a repository, the API client in a thin feature.
- If a cubit extends a base cubit that already has tests for its generic logic, test only the behavior the subclass adds (do not duplicate the base tests).
- Assert the full emitted state sequence: `[LoadingState, SuccessState(...)]`, `[LoadingState, FailureState(...)]`, and presentation events by listening to the cubit's `presentation` stream (for example `expectLater(cubit.presentation, emits(TransferPresentationEvent.completed))`).
- Cover: initial state, success, each failure, retry, double-submit guard, and no emission after `close()`.
- Blocs with transformers: use `wait:` / fake async to verify debounce and `droppable` behavior.

```dart
blocTest<TransferCubit, TransferState>(
  'emits Failure when limit exceeded',
  setUp: () => registerFallbackValue(_aTransfer()),   // required by mocktail for any() on a custom type
  build: () {
    when(() => transferMoney(any()))
        .thenAnswer((_) async => Failure(TransferLimitExceeded(Money(100))));
    return TransferCubit(transferMoney);
  },
  act: (c) => c.submit(transfer),
  expect: () => [const TransferStateLoading(), isA<TransferStateFailure>()],
);
```

## UI

- Widget tests with a mocked cubit (`MockCubit<State>` from `bloc_test`) provided via `BlocProvider.value`. Wrap with the app theme and localization delegates (a shared `pumpApp` helper).
- Test one behavior per state: loading shows spinner, failure shows message and retry, tapping a button calls the right cubit method (`verify`).
- Use widget tests for UI-heavy screens and forms: correct cubit states do not prove the UI reacts correctly to input.
- **Golden tests** for design-system widgets and key screens. Keep one helper that runs a golden test of a single screen across the project's scenarios (phone, tablet, dark mode, larger font) and accepts provider overrides for the screen's dependencies, for example `screenGoldenTest(name, screen: ..., providers: [...])`. Regenerate deliberately and review the diff.

## Integration

- `integration_test` / Patrol against a mock-backed flavor for critical flows (login, transfer). Keep few, stable and independent.

## Rules

- Tests do not hit the network, real storage or the clock. Inject them (`clock` package, fake storage).
- One reason to fail per test; descriptive names that state the behavior.
- **All shared code (`core/`/common) is fully tested.**
- Do not test generated code, trivial getters or the framework.
- A bug fix starts with a failing test at the lowest layer where the bug lives.

## Checklist before finishing

- [ ] Every use case and mapper has a test
- [ ] Cubits tested with mocked dependencies (use cases/repository/API client), all failure paths covered
- [ ] Shared code fully tested
- [ ] Widgets tested with mocked cubits, not real data
- [ ] `flutter test` and `flutter analyze --fatal-infos` pass

## Bundled files

- `references/test-checklist-by-layer.md`: what to cover per layer, conventions, commands
