# What belongs in the domain layer

Use this when unsure where a piece of code goes.

| Code | Layer | Why |
|---|---|---|
| "Transfer must not exceed daily limit" | domain (use case) | Business rule |
| "Balance below zero is overdrawn" | domain (entity getter) | Rule on own data |
| "Total balance across accounts" | domain (use case) | Combines data |
| Parse `"2024-05-01"` to `DateTime` | data (mapper) | Wire format |
| Retry on 503, map 401 to `UnauthorizedFailure` | data (repository impl) | Transport concern |
| Format money as `€1,234.50` | presentation/UI | Display concern, locale dependent |
| Show snackbar on failure | UI | Side effect |
| Debounce search typing | presentation (Bloc transformer) | Interaction timing |
| Field is required / looks like an email | UI form or domain value object | Prefer a value object if it recurs |

## Test: is it domain?

1. Would it still be true if the app had a different UI? If yes, domain.
2. Would it still be true if the API used GraphQL instead of REST? If yes, domain.
3. Can it be tested with plain `dart test` and fake repositories? If yes, domain.

## Value objects worth creating

`Money`, `Iban`, `PhoneNumber`, `Email`, `AccountNumber`, `DateRange`. Create one when the concept has validation or operations that would otherwise be repeated in several places.

## When a feature may skip use cases

The feature only displays server-shaped data (BFF) and has no rules. Cubits then call the repository interface directly. Keep the interface in `domain/repositories/` so the data layer stays swappable, and write down the choice in the feature README.
