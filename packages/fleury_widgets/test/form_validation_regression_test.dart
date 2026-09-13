import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

Future<bool> validate(FleuryTester tester, FormController form) {
  final result = form.validate();
  tester.pump();
  return result;
}

void main() {
  testWidgets(
    'cached fields revalidate applied values, not requested changes',
    (tester) async {
      final form = FormController();
      final control = GlobalKey<_LocalChoiceState>();
      var calls = 0;
      tester.pumpWidget(
        Form(
          controller: form,
          onSubmit: () {},
          child: FormField(
            validator: () {
              calls++;
              return control.currentState!.value ? null : 'Required';
            },
            child: _LocalChoice(key: control),
          ),
        ),
      );
      await tester.settle();
      expect(calls, 0, reason: 'Do not validate before feedback is requested.');
      expect(await validate(tester, form), isFalse);
      await tester.settle();
      await tester.checkbox('Choice').focus();
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      expect(control.currentState!.requests, 1);
      expect(tester.checkbox('Choice'), isUnchecked);
      expect(tester.renderToString(), contains('Required'));

      // The owner accepts the request later; only the control rebuilds. No new
      // FormField widget or validator closure is supplied.
      control.currentState!.apply(true);
      await tester.settle();
      expect(tester.checkbox('Choice'), isChecked);
      expect(tester.renderToString(), isNot(contains('Required')));
      expect(control.currentState!.requests, 1);

      form.clearErrors();
      await tester.settle();
      calls = 0;
      control.currentState!.apply(false);
      await tester.settle();
      expect(calls, 0);
      expect(tester.renderToString(), isNot(contains('Required')));
      tester.pumpWidget(const Text('gone'));
      form.dispose();
    },
  );

  testWidgets('registered dependent values refresh without a parent rebuild', (
    tester,
  ) async {
    final form = FormController();
    final first = TextEditingController(text: 'first');
    final second = TextEditingController(text: 'second');
    tester.pumpWidget(
      Form(
        controller: form,
        onSubmit: () {},
        child: Column(
          children: [
            FormField(
              child: TextInput(controller: first, semanticLabel: 'First'),
            ),
            FormField(
              validator: () => first.text == second.text ? null : 'Mismatch',
              child: TextInput(controller: second, semanticLabel: 'Second'),
            ),
          ],
        ),
      ),
    );
    expect(await validate(tester, form), isFalse);
    await tester.settle();
    first.text = 'second';
    await tester.settle();
    expect(tester.renderToString(), isNot(contains('Mismatch')));
    first.text = 'different';
    await tester.settle();
    expect(tester.renderToString(), contains('Mismatch'));
    tester.pumpWidget(const Text('gone'));
    form.dispose();
    first.dispose();
    second.dispose();
  });

  testWidgets('standalone fields refresh their revealed validation', (
    tester,
  ) async {
    final field = GlobalKey<FormFieldState>();
    final text = TextEditingController(text: 'valid');
    tester.pumpWidget(
      FormField(
        key: field,
        validator: () => text.text.isEmpty ? 'Required' : null,
        child: TextInput(controller: text),
      ),
    );
    expect(field.currentState!.validate(), isTrue);
    text.text = '';
    await tester.settle();
    expect(tester.renderToString(), contains('Required'));
    tester.pumpWidget(const Text('gone'));
    text.dispose();
  });

  testWidgets('revalidation respects nested forms and disabled controls', (
    tester,
  ) async {
    final outer = FormController();
    final inner = FormController();
    final text = TextEditingController();
    var innerCalls = 0;
    var disabledCalls = 0;
    tester.pumpWidget(
      Form(
        controller: outer,
        onSubmit: () {},
        child: Column(
          children: [
            FormField(
              validator: () => text.text.isEmpty ? 'Outer required' : null,
              child: TextInput(controller: text),
            ),
            FormField(
              validator: () {
                disabledCalls++;
                return 'Disabled error';
              },
              child: const Checkbox(
                value: false,
                label: 'Disabled',
                onChanged: null,
              ),
            ),
            Form(
              controller: inner,
              onSubmit: () {},
              child: FormField(
                validator: () {
                  innerCalls++;
                  return 'Inner required';
                },
                child: const TextInput(),
              ),
            ),
          ],
        ),
      ),
    );
    expect(await validate(tester, outer), isFalse);
    expect(await validate(tester, inner), isFalse);
    await tester.settle();
    innerCalls = 0;
    text.text = 'valid';
    await tester.settle();
    expect(innerCalls, 0);
    expect(disabledCalls, 0);
    expect(tester.renderToString(), contains('Inner required'));
    expect(tester.renderToString(), isNot(contains('Outer required')));
    tester.pumpWidget(const Text('gone'));
    inner.dispose();
    outer.dispose();
    text.dispose();
  });

  testWidgets(
    'offscreen invalid field and its error are revealed after layout',
    (tester) async {
      final form = FormController();
      final scroll = ScrollController();
      final focus = FocusNode();
      tester.viewportSize = const CellSize(32, 6);
      tester.pumpWidget(
        Form(
          controller: form,
          onSubmit: () {},
          child: SizedBox(
            width: 30,
            height: 4,
            child: ScrollView(
              controller: scroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TOP OF FORM'),
                  const SizedBox(height: 8),
                  FormField(
                    validator: () => 'Name required.',
                    child: TextInput(focusNode: focus, semanticLabel: 'Name'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      tester.render();
      expect(await validate(tester, form), isFalse);
      await tester.settle();
      final screen = tester.renderToString(emptyMark: ' ');
      expect(focus.hasFocus, isTrue);
      expect(scroll.offset, greaterThan(0));
      expect(screen, isNot(contains('TOP OF FORM')));
      expect(screen, contains('Name required.'));
      tester.pumpWidget(const Text('gone'));
      form.dispose();
      scroll.dispose();
      focus.dispose();
    },
  );

  for (final boundary in ['moved', 'excluded', 'removed']) {
    testWidgets('pending reveal respects $boundary focus', (tester) async {
      final form = FormController();
      final scroll = ScrollController();
      final invalid = FocusNode();
      final other = FocusNode();
      tester.pumpWidget(
        Form(
          controller: form,
          onSubmit: () {},
          child: Column(
            children: [
              SizedBox(
                height: 4,
                child: ScrollView(
                  controller: scroll,
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      ExcludeFocus(
                        excluding: boundary == 'excluded',
                        child: FormField(
                          validator: () => 'Required',
                          child: TextInput(focusNode: invalid),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              TextInput(focusNode: other, autofocus: true),
            ],
          ),
        ),
      );
      tester.render();
      expect(await validate(tester, form), isFalse);
      if (boundary == 'moved') other.requestFocus();
      if (boundary == 'removed') tester.pumpWidget(const Text('gone'));
      await tester.settle();
      expect(scroll.offset, 0);
      if (boundary != 'removed') expect(other.hasFocus, isTrue);
      tester.pumpWidget(const Text('gone'));
      form.dispose();
      scroll.dispose();
      invalid.dispose();
      other.dispose();
    });
  }

  for (final inline in [false, true]) {
    testWidgets('programmatic Select update, inline validator: $inline', (
      tester,
    ) async {
      final key = GlobalKey<_ChoicesState>();
      final form = FormController();
      tester.pumpWidget(
        _Choices(key: key, form: form, inline: inline, dropdown: true),
      );
      expect(await validate(tester, form), isFalse);
      tester.pump();
      key.currentState!.acceptFromApplication();
      await tester.settle();
      expect(tester.renderToString(), contains('Accepted'));
      final error = tester
          .semantics()
          .single(role: SemanticRole.button, label: 'Accept')
          .validationError;
      expect(error, isNull);
      expect(await validate(tester, form), isTrue);
      tester.pumpWidget(const Text('gone'));
      form.dispose();
    });

    testWidgets('programmatic checkbox update, inline validator: $inline', (
      tester,
    ) async {
      final key = GlobalKey<_ChoicesState>();
      final form = FormController();
      tester.pumpWidget(_Choices(key: key, form: form, inline: inline));
      expect(await validate(tester, form), isFalse);
      tester.pump();
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.checkbox, label: 'Accept')
            .validationError,
        'Accept required.',
      );
      key.currentState!.acceptFromApplication();
      await tester.settle();
      expect(tester.checkbox('Accept'), isChecked);
      final error = tester
          .semantics()
          .single(role: SemanticRole.checkbox, label: 'Accept')
          .validationError;
      expect(error, isNull);
      expect(await validate(tester, form), isTrue);
      tester.pumpWidget(const Text('gone'));
      form.dispose();
    });

    testWidgets('dependent field update, inline validator: $inline', (
      tester,
    ) async {
      final key = GlobalKey<_PasswordsState>();
      final form = FormController();
      tester.pumpWidget(_Passwords(key: key, form: form, inline: inline));
      expect(await validate(tester, form), isFalse);
      tester.pump();
      key.currentState!.makePasswordsMatch();
      tester.pump();
      final error = tester
          .semantics()
          .single(role: SemanticRole.textField, label: 'Confirm')
          .validationError;
      expect(error, isNull);
      expect(await validate(tester, form), isTrue);
      tester.pumpWidget(const Text('gone'));
      form.dispose();
    });
  }

  testWidgets('programmatic text edits revalidate a stable validator', (
    tester,
  ) async {
    final form = FormController();
    final text = TextEditingController();
    String? check() => text.text.isEmpty ? 'Name required.' : null;
    tester.pumpWidget(
      Form(
        controller: form,
        onSubmit: () {},
        child: FormField(
          validator: check,
          child: TextInput(controller: text, semanticLabel: 'Name'),
        ),
      ),
    );
    expect(await validate(tester, form), isFalse);
    tester.pump();
    text.text = 'Ada';
    tester.pump();
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.textField, label: 'Name')
          .validationError,
      isNull,
    );
    tester.pumpWidget(const Text('gone'));
    form.dispose();
    text.dispose();
  });

  for (final attachOwned in [true, false]) {
    testWidgets('builder focus diagnostic, attach owned node: $attachOwned', (
      tester,
    ) async {
      final form = FormController();
      final unused = FocusNode();
      FocusNode? destination;
      Object? captured;
      await runZonedGuarded<Future<void>>(() async {
        tester.pumpWidget(
          Form(
            controller: form,
            onSubmit: () {},
            child: FormField.builder(
              focusNode: attachOwned ? null : unused,
              validator: () => 'Choose a range.',
              builder: (context, field) {
                destination = field.focusNode;
                return attachOwned
                    ? Focus(
                        focusNode: field.focusNode,
                        child: const Text('Range'),
                      )
                    : const Text('Range');
              },
            ),
          ),
        );
        expect(await validate(tester, form), isFalse);
        await Future<void>.delayed(Duration.zero);
      }, (error, _) => captured = error);
      expect(destination!.hasFocus, attachOwned);
      // Current diagnostic rejects the working owned node but accepts an
      // explicit node that was never attached to any control.
      expect(captured, attachOwned ? isNull : isA<StateError>());
      tester.pumpWidget(const Text('gone'));
      form.dispose();
      unused.dispose();
    });
  }
}

class _LocalChoice extends StatefulWidget {
  const _LocalChoice({super.key});
  @override
  State<_LocalChoice> createState() => _LocalChoiceState();
}

class _LocalChoiceState extends State<_LocalChoice> {
  bool value = false;
  int requests = 0;
  void apply(bool next) => setState(() => value = next);
  @override
  Widget build(BuildContext context) =>
      Checkbox(value: value, label: 'Choice', onChanged: (_) => requests++);
}

class _Choices extends StatefulWidget {
  const _Choices({
    super.key,
    required this.form,
    required this.inline,
    this.dropdown = false,
  });
  final FormController form;
  final bool inline;
  final bool dropdown;
  @override
  State<_Choices> createState() => _ChoicesState();
}

class _ChoicesState extends State<_Choices> {
  bool accepted = false;
  String? check() => accepted ? null : 'Accept required.';
  void acceptFromApplication() => setState(() => accepted = true);
  @override
  Widget build(BuildContext context) => Form(
    controller: widget.form,
    onSubmit: () {},
    child: FormField(
      validator: widget.inline ? () => check() : check,
      child: widget.dropdown
          ? Select<bool>(
              options: const [SelectOption(value: true, label: 'Accepted')],
              value: accepted ? true : null,
              semanticLabel: 'Accept',
              onChanged: (value) => setState(() => accepted = value),
            )
          : Checkbox(
              value: accepted,
              label: 'Accept',
              onChanged: (value) => setState(() => accepted = value),
            ),
    ),
  );
}

class _Passwords extends StatefulWidget {
  const _Passwords({super.key, required this.form, required this.inline});
  final FormController form;
  final bool inline;
  @override
  State<_Passwords> createState() => _PasswordsState();
}

class _PasswordsState extends State<_Passwords> {
  final password = TextEditingController(text: 'first');
  final confirmation = TextEditingController(text: 'second');
  String? check() =>
      password.text == confirmation.text ? null : 'Passwords differ.';
  void makePasswordsMatch() => setState(() => password.text = 'second');
  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
    controller: widget.form,
    onSubmit: () {},
    child: Column(
      children: [
        TextInput(controller: password, semanticLabel: 'Password'),
        FormField(
          validator: widget.inline ? () => check() : check,
          child: TextInput(controller: confirmation, semanticLabel: 'Confirm'),
        ),
      ],
    ),
  );
}
