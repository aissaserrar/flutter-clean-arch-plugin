# When to use an interface (and when not to)

Rule of thumb: use an interface when the code that needs something should not know which concrete class provides it. Otherwise use a plain class.

## Use an interface when

| Situation | Example | Why |
|---|---|---|
| **The dependency would point the wrong way across a layer or feature boundary** | `AccountsRepository` declared in `domain/`, implemented in `data/`. `AccountsNavigation` declared in a feature, implemented in `router/`. | The inner layer (or the feature) defines the contract; the outer one fulfils it. |
| **Several implementations behind one consumer** | HTTP `RequestInterceptor`s plugged into one client; a family of serializers; context-menu actions implemented by different widgets | One consumer, interchangeable implementations (plain polymorphism). The boundary is not the reason here. |
| **Swapping an implementation for tests or environments** | `MockAccountsRepository` vs `AccountsRepositoryImpl`, chosen in `<feature>_providers.dart` by `AppConfig.useMocks` | Keeps mock-versus-real switching out of the repository code. |

## Do not use an interface for

| Thing | Why not |
|---|---|
| **Use cases** | One class per action, one implementation. Mock the concrete class in cubit tests (`mocktail` can mock any class). |
| **Entities, value objects, DTOs, mappers** | Data and pure functions. Nothing to swap. |
| **Cubits / Blocs** | The UI depends on the concrete cubit; tests use `MockCubit`. |
| **Data sources** | Usually one implementation. Add an interface only if you need two (remote and local behind one consumer) or a fake that a plain mock cannot cover. |
| **"Just in case"** | An interface with one implementation, no boundary and no need to swap is ceremony. Introducing one later is cheap when callers already take the type through their constructor, so wait until a situation above appears. |

## Repositories: only when needed, but then always an interface

A repository exists only when there is caching, several sources to merge, or complex mapping. A thin feature calling the typed API client has none. When a repository does exist, declare `<Feature>Repository` as an interface in `domain/repositories/`: it is the boundary between domain and data, and it is what makes mock/real switching and fake-based tests possible. Skipping use cases is allowed; skipping the interface on an existing repository is not.

## Wrap third-party and platform types

Do not scatter `SharedPreferences`, a feature-flag SDK or a raw HTTP package through the code. Put your own small type in `core/` (`KeyValueStorage`, `HttpClient`, `FeatureFlags`) and depend on that. It is an interface (or a thin class) you own, so the rest of the app does not change when the plugin does.

## Interface or sealed class?

| Need | Choose |
|---|---|
| A **closed** set of variants you switch over exhaustively (states, failures, storage keys, domain statuses) | `sealed class` |
| An **open** set of implementations that others can add (repositories, interceptors, navigation contracts) | `abstract interface class` |

## Checklist

- [ ] Every repository (when the feature has one) is an interface in `domain/`
- [ ] No interface for use cases, entities, DTOs, mappers or cubits
- [ ] Any other interface can name its second implementation, its boundary, or its test/environment swap
- [ ] Third-party and platform packages sit behind a `core/` type
