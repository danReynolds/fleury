// dart format width=60
import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

class RelatedFields extends StatefulWidget {
  const RelatedFields({super.key});

  @override
  State<RelatedFields> createState() =>
      _RelatedFieldsState();
}

class _RelatedFieldsState extends State<RelatedFields> {
  final form = FormController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  String status = 'Use made-up values in this demo';

  Future<void> check() async {
    final valid = await form.validate(autofocus: false);
    if (!mounted) return;
    setState(
      () => status = valid
          ? 'Values match'
          : 'Check the errors',
    );
  }

  @override
  void dispose() {
    form.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Form(
      controller: form,
      onSubmit: () => setState(() => status = 'Confirmed'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Password'),
          FormField(
            validator: () => password.text.isEmpty
                ? 'Enter a password.'
                : null,
            child: PasswordInput(
              controller: password,
              semanticLabel: 'Password',
              autofocus: true,
            ),
          ),
          const SizedBox(height: 1),
          const Text('Confirm password'),
          FormField(
            validator: () => confirmation.text.isEmpty
                ? 'Repeat the password.'
                : confirmation.text != password.text
                ? 'Passwords must match.'
                : null,
            child: PasswordInput(
              controller: confirmation,
              semanticLabel: 'Confirm password',
              onSubmit: (_) => form.submit(),
            ),
          ),
          const SizedBox(height: 1),
          Wrap(
            spacing: 1,
            children: [
              Button(text: 'Check', onPressed: check),
              Button(
                text: 'Confirm',
                onPressed: form.submit,
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(status),
        ],
      ),
    ),
  );
}
