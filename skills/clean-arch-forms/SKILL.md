---
name: clean-arch-forms
description: Use when creating or editing forms in a Flutter feature that uses Cubit/Bloc: form cubits and field cubits, validation timing, submit button behavior, submit errors, and how form cubits are provided to the feature cubit. Naming for form classes.
---

# Form rules

These rules are independent of the form library. They assume the project uses a field-cubit based form library (a form is a cubit that owns field cubits); if it uses another approach, keep the same behavior rules and naming where they apply.

## Structure

- One **form cubit** per form, one **field cubit** per field that needs its own state.
- The form is provided with `BlocProvider` and **read from context when the feature cubit is created**. The feature cubit receives the form cubit through its constructor and reads values from it on submit.
- Form state is presentation state. Business rules (limits, eligibility, cross-field rules that mean something to the business) are checked by a **use case** called from the feature cubit; simple format checks stay in the form.

The feature cubit from `clean-arch-presentation` gains a form-cubit constructor parameter (`TransferCubit(this._transferMoney, this._form)`):

```dart
BlocProvider(
  create: (context) => TransferFormCubit(),
  child: BlocProvider(
    create: (context) => TransferCubit(context.read(), context.read<TransferFormCubit>()),
    child: const _TransferContent(),
  ),
)
```

## Naming

| Class | Suffix |
|---|---|
| Form cubit | `<Something>FormCubit` |
| Field cubit | `<Something>FieldCubit` |
| Form widget | `<Something>Form` |
| Field widget | `<Something>Field` |

## Behavior: decide once per app, apply everywhere

Define a consistent behavior for:

- **When validation first runs:** on first interaction, on blur, or on submit. Pick one.
- **Submit button:** disabled until the form is valid, or enabled and showing errors on press. Pick one.
- **Where errors appear:** per field (validation) vs near the submit action (server/business errors).

Put the choice in the project's conventions so every form behaves the same.

## Rules

- Keep controllers and focus nodes in the widget's `State` and dispose them.
- Disable submit while the request runs; the feature cubit also ignores a second submit.
- A failed submit shows a contextual error near the action and keeps the user's input (see `clean-arch-ui`).
- No `BuildContext` in form cubits.
- Validation messages are failures or codes mapped to localized text in the UI.

## Checklist before finishing

- [ ] Form cubit provided with `BlocProvider`; feature cubit gets it through its constructor
- [ ] Names use the `FormCubit` / `FieldCubit` / `Form` / `Field` suffixes
- [ ] Validation timing and submit behavior match the rest of the app
- [ ] Business rules are in a use case, not in the form
- [ ] Widget test covers validation errors and a successful submit (see `clean-arch-testing`)
