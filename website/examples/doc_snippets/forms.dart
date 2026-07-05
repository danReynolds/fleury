// Backs website/src/content/docs/guides/forms.md — a multi-field form with
// live validation, a submit gated on validity, and a Ctrl+S action. Kept as a
// real, analyzed program so the guide can't drift from the API.
//
// Run it:  dart run doc_snippets/forms.dart

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

void main() => runApp(const SignupForm());

class SignupForm extends StatefulWidget {
  const SignupForm({super.key});

  @override
  State<SignupForm> createState() => _SignupFormState();
}

class _SignupFormState extends State<SignupForm> {
  // One controller per text field. Owned by the State: created here,
  // disposed in dispose().
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

  // Validators return null when valid, or the error to show. Pure functions
  // of the current values — call them from build, not just on submit, so the
  // UI reflects validity live.
  String? get _nameError =>
      _name.text.trim().isEmpty ? 'Name is required' : null;

  String? get _emailError {
    final v = _email.text.trim();
    if (v.isEmpty) return 'Email is required';
    if (!v.contains('@')) return 'Enter a valid email';
    return null;
  }

  bool get _isValid => _nameError == null && _emailError == null && _agree;

  void _submit() {
    setState(() => _submitted = true);
    if (!_isValid) return;
    // …persist / navigate…
  }

  @override
  Widget build(BuildContext context) {
    // Show an error once the user has tried to submit (or you could track
    // per-field "touched" state for earlier feedback).
    final showErrors = _submitted;
    return KeyBindings(
      bindings: [
        KeyBinding(const KeyChord.char('s', ctrl: true), onEvent: (_) => _submit()),
      ],
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sign up'),
            const SizedBox(height: 1),
            const Text('Name'),
            TextInput(
              controller: _name,
              autofocus: true,
              // onChanged rebuilds so validation + submit-enabled track edits.
              onChanged: (_) => setState(() {}),
              validationError: showErrors ? _nameError : null,
            ),
            const SizedBox(height: 1),
            const Text('Email'),
            TextInput(
              controller: _email,
              onChanged: (_) => setState(() {}),
              validationError: showErrors ? _emailError : null,
            ),
            const SizedBox(height: 1),
            Checkbox(
              value: _agree,
              onChanged: (v) => setState(() => _agree = v),
              label: 'I agree to the terms',
            ),
            const SizedBox(height: 1),
            Button(
              label: 'Create account  (Ctrl+S)',
              variant: ButtonVariant.primary,
              // Nullable onPressed disables the button — gate it on validity.
              onPressed: _isValid ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }
}
