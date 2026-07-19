---
title: Forms & validation
description: Build a multi-field form with live validation and a submit gated on validity, using ordinary controllers and setState.
---

Fleury has no special "form framework" you have to learn — a form is just
stateful widgets and the same `setState` loop you already use. A text field
holds its value in a [`TextEditingController`](/fleury/widgets/textinput/); a
validator is a plain function of the current values; and a disabled `Button` is
one whose `onPressed` is `null`. Put those together and you get live validation
for free.

Here's the shape of a two-field sign-up form. The full, runnable program is in
[`doc_snippets/forms.dart`](https://github.com/danReynolds/fleury/blob/main/website/examples/doc_snippets/forms.dart).

## One controller per field, owned by the State

```dart
class _SignupFormState extends State<SignupForm> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  bool _agree = false;
  bool _submitted = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }
```

Create controllers as fields (or in `initState`) and dispose them in
`dispose` — the same discipline as any Flutter form.

## Validators are functions of the current values

A validator returns `null` when the input is valid, or the message to show.
Because they read the controllers directly, you can call them from `build` —
so the UI reflects validity *live*, not only on submit.

```dart
String? get _nameError =>
    _name.text.trim().isEmpty ? 'Name is required' : null;

String? get _emailError {
  final v = _email.text.trim();
  if (v.isEmpty) return 'Email is required';
  if (!v.contains('@')) return 'Enter a valid email';
  return null;
}

bool get _isValid => _nameError == null && _emailError == null && _agree;
```

## Wire edits → validation → submit-enabled

`TextInput.onChanged` fires on every edit; call `setState` so validity and the
submit button re-evaluate as the user types. Feed each field its error through
`validationError`, and gate the button by making `onPressed` null when invalid.

```dart
TextInput(
  controller: _name,
  onChanged: (_) => setState(() {}),
  validationError: _submitted ? _nameError : null,
),
// …
Button(
  label: 'Create account',
  variant: ButtonVariant.primary,
  onPressed: _isValid ? _submit : null, // null disables it
),
```

Showing errors only after the first submit attempt (`_submitted`) keeps a fresh
form from screaming red before the user has done anything — a common nicety.
Track a per-field "touched" flag instead if you want errors as soon as a field
is left.

## Keyboard-first submit

Terminals are keyboard-native, so bind submit to a chord as well as the button:

```dart
KeyBindings(
  bindings: [
    KeyBinding(KeyChord.ctrl.s, onEvent: (_) => _submit()),
  ],
  child: /* the form */,
)
```

That's the whole pattern: controllers for values, functions for validation,
`setState` to connect them, and nullable `onPressed` to gate submit. It scales
to as many fields as you need without a form-specific API.

> **Higher-level shortcut:** `fleury_widgets` also ships a `FormPanel` driven by
> a list of `FormFieldSpec`s (text, number, date, path, select…) with built-in
> validation. It runs on all three surfaces — terminal, served, and embedded
> browser — the one platform-specific bit, a path field's `mustExist`
> filesystem check, simply no-ops in the browser (which has no filesystem to
> check). Reach for it for quick declarative forms; hand-build with the pattern
> above when you want full control over layout and interleaved widgets.
