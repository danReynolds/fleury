import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _invalidControlColor = RgbColor(1, 2, 3);
const _invalidControlStyle = CellStyle.state(
  invalid: CellStyle(foreground: _invalidControlColor),
);

bool _hasForeground(FleuryTester tester, Color color) {
  const size = CellSize(80, 20);
  final buffer = tester.render(size: size);
  for (var row = 0; row < size.rows; row++) {
    for (var col = 0; col < size.cols; col++) {
      if (buffer.atColRow(col, row).style.foreground == color) return true;
    }
  }
  return false;
}

Widget _textForm({
  required FormController controller,
  required TextEditingController text,
  required FutureOr<void> Function() onSubmit,
  String? externalError,
  bool enabled = true,
  CellStyle? style,
}) {
  return Form(
    controller: controller,
    onSubmit: onSubmit,
    child: FormField(
      enabled: enabled,
      error: externalError,
      validator: () => text.text.trim().isEmpty ? 'Enter a name.' : null,
      child: TextInput(
        controller: text,
        semanticLabel: 'Name',
        style: style ?? CellStyle.none,
      ),
    ),
  );
}

final class _CaptureFormController extends StatelessWidget {
  const _CaptureFormController(this.onBuild);

  final void Function(FormController controller) onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(Form.of(context));
    return const Text('ready');
  }
}

final class _ServerErrorHarness extends StatefulWidget {
  const _ServerErrorHarness({
    super.key,
    required this.controller,
    required this.text,
  });

  final FormController controller;
  final TextEditingController text;

  @override
  State<_ServerErrorHarness> createState() => _ServerErrorHarnessState();
}

final class _ServerErrorHarnessState extends State<_ServerErrorHarness> {
  String? _error;

  Future<bool> reject() {
    setState(() => _error = 'Name already exists.');
    return widget.controller.validate();
  }

  @override
  Widget build(BuildContext context) => _textForm(
    controller: widget.controller,
    text: widget.text,
    externalError: _error,
    onSubmit: () {},
  );
}

Future<bool> _validate(FleuryTester tester, FormController controller) {
  final validation = controller.validate();
  tester.pump();
  return validation;
}

Future<bool> _submit(FleuryTester tester, FormController controller) {
  final submission = controller.submit();
  tester.pump();
  return submission;
}

void main() {
  group('FormController', () {
    test('rejects commands while unattached', () {
      final controller = FormController();

      expect(controller.validate, throwsStateError);
      expect(controller.clearErrors, throwsStateError);
      expect(controller.submit, throwsStateError);

      controller.dispose();
    });

    testWidgets('Form.of returns the private controller', (tester) {
      FormController? ambient;
      tester.pumpWidget(
        Form(
          onSubmit: () {},
          child: _CaptureFormController((value) => ambient = value),
        ),
      );

      expect(ambient, isNotNull);
      expect(ambient!.isAttached, isTrue);
    });

    testWidgets('invalid submit does not become a retained submission', (
      tester,
    ) async {
      final controller = FormController();
      final text = TextEditingController();
      var submits = 0;
      tester.pumpWidget(
        _textForm(
          controller: controller,
          text: text,
          onSubmit: () => submits++,
        ),
      );

      expect(await _submit(tester, controller), isFalse);
      expect(await _submit(tester, controller), isFalse);
      expect(submits, 0);

      tester.pumpWidget(const Text('gone'));
      controller.dispose();
      text.dispose();
    });

    testWidgets('coalesces concurrent valid submissions and reports progress', (
      tester,
    ) async {
      final controller = FormController();
      final text = TextEditingController(text: 'Atlas');
      final pending = Completer<void>();
      var submits = 0;
      tester.pumpWidget(
        _textForm(
          controller: controller,
          text: text,
          onSubmit: () {
            submits++;
            return pending.future;
          },
        ),
      );

      final first = controller.submit();
      final second = controller.submit();
      expect(identical(first, second), isTrue);
      tester.pump();
      await Future<void>.delayed(Duration.zero);
      expect(controller.isSubmitting, isTrue);
      expect(submits, 1);

      pending.complete();
      expect(await first, isTrue);
      expect(controller.isSubmitting, isFalse);

      tester.pumpWidget(const Text('gone'));
      controller.dispose();
      text.dispose();
    });

    testWidgets('detaching during submit leaves the returned future usable', (
      tester,
    ) async {
      final controller = FormController();
      final text = TextEditingController(text: 'Atlas');
      final pending = Completer<void>();
      tester.pumpWidget(
        _textForm(
          controller: controller,
          text: text,
          onSubmit: () => pending.future,
        ),
      );

      final submission = controller.submit();
      tester.pump();
      await Future<void>.delayed(Duration.zero);
      expect(controller.isSubmitting, isTrue);
      tester.pumpWidget(const Text('gone'));
      expect(controller.isAttached, isFalse);
      expect(controller.isSubmitting, isFalse);

      pending.complete();
      expect(await submission, isTrue);
      controller.dispose();
      text.dispose();
    });

    testWidgets('replacing a controller cancels pending validation safely', (
      tester,
    ) async {
      final first = FormController();
      final second = FormController();
      final text = TextEditingController(text: 'Atlas');
      var submits = 0;

      Widget build(FormController controller) => _textForm(
        controller: controller,
        text: text,
        onSubmit: () => submits++,
      );

      tester.pumpWidget(build(first));
      final pending = first.submit();

      // Retain the Form state but replace its externally-owned controller
      // before the post-frame validation phase runs.
      tester.pumpWidget(build(second));
      tester.pump();
      expect(await pending, isFalse);
      expect(submits, 0);
      expect(first.isAttached, isFalse);
      expect(second.isAttached, isTrue);

      expect(await _submit(tester, second), isTrue);
      expect(submits, 1);

      tester.pumpWidget(const Text('gone'));
      first.dispose();
      second.dispose();
      text.dispose();
    });
  });

  group('FormField', () {
    testWidgets('validation reveals an error and focuses the first field', (
      tester,
    ) async {
      final controller = FormController();
      final first = TextEditingController();
      final second = TextEditingController();
      tester.pumpWidget(
        Form(
          controller: controller,
          onSubmit: () {},
          child: Column(
            children: <Widget>[
              FormField(
                validator: () => first.text.isEmpty ? 'First required.' : null,
                child: TextInput(controller: first, semanticLabel: 'First'),
              ),
              FormField(
                validator: () =>
                    second.text.isEmpty ? 'Second required.' : null,
                child: TextInput(controller: second, semanticLabel: 'Second'),
              ),
            ],
          ),
        ),
      );

      expect(await _validate(tester, controller), isFalse);
      tester.pump();
      expect(
        tester.renderToString(size: const CellSize(40, 6)),
        contains('First required.'),
      );
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.textField, label: 'First')
            .focused,
        isTrue,
      );
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.textField, label: 'First')
            .validationError,
        'First required.',
      );

      tester.pumpWidget(const Text('gone'));
      controller.dispose();
      first.dispose();
      second.dispose();
    });

    testWidgets('editing clears a revealed validator error', (tester) async {
      final controller = FormController();
      final text = TextEditingController();
      tester.pumpWidget(
        _textForm(controller: controller, text: text, onSubmit: () {}),
      );

      expect(await _validate(tester, controller), isFalse);
      tester.pump();
      expect(
        tester.renderToString(size: const CellSize(30, 3)),
        contains('Enter a name.'),
      );

      tester.type('A');
      tester.pump();
      expect(
        tester.renderToString(size: const CellSize(30, 3)),
        isNot(contains('Enter a name.')),
      );
      expect(await _validate(tester, controller), isTrue);

      tester.pumpWidget(const Text('gone'));
      controller.dispose();
      text.dispose();
    });

    testWidgets('controlled errors block submit and survive clearErrors', (
      tester,
    ) async {
      final controller = FormController();
      final text = TextEditingController(text: 'atlas');
      var submits = 0;
      tester.pumpWidget(
        _textForm(
          controller: controller,
          text: text,
          externalError: 'Name already exists.',
          onSubmit: () => submits++,
        ),
      );

      expect(await _validate(tester, controller), isFalse);
      controller.clearErrors();
      tester.pump();
      expect(
        tester.renderToString(size: const CellSize(40, 3)),
        contains('Name already exists.'),
      );
      expect(await _submit(tester, controller), isFalse);
      expect(submits, 0);

      tester.pumpWidget(const Text('gone'));
      controller.dispose();
      text.dispose();
    });

    testWidgets(
      'validation observes a controlled error set immediately beforehand',
      (tester) async {
        final controller = FormController();
        final text = TextEditingController(text: 'atlas');
        final harnessKey = GlobalKey<_ServerErrorHarnessState>();
        tester.pumpWidget(
          _ServerErrorHarness(
            key: harnessKey,
            controller: controller,
            text: text,
          ),
        );

        final validation = harnessKey.currentState!.reject();
        tester.pump();
        expect(await validation, isFalse);
        tester.pump();
        expect(
          tester.renderToString(size: const CellSize(40, 3)),
          contains('Name already exists.'),
        );

        tester.pumpWidget(const Text('gone'));
        controller.dispose();
        text.dispose();
      },
    );

    testWidgets('disabled fields are skipped', (tester) async {
      final controller = FormController();
      final text = TextEditingController();
      var submits = 0;
      tester.pumpWidget(
        _textForm(
          controller: controller,
          text: text,
          enabled: false,
          onSubmit: () => submits++,
        ),
      );

      expect(await _validate(tester, controller), isTrue);
      expect(await _submit(tester, controller), isTrue);
      expect(submits, 1);

      tester.pumpWidget(const Text('gone'));
      controller.dispose();
      text.dispose();
    });

    testWidgets('style can suppress invalid chrome without semantics', (
      tester,
    ) async {
      final controller = FormController();
      final text = TextEditingController();
      tester.pumpWidget(
        _textForm(
          controller: controller,
          text: text,
          style: const CellStyle.state(invalid: CellStyle.none),
          onSubmit: () {},
        ),
      );

      await _validate(tester, controller);
      tester.pump();
      final node = tester.semantics().single(
        role: SemanticRole.textField,
        label: 'Name',
      );
      expect(node.validationError, 'Enter a name.');
      final cell = tester.render(size: const CellSize(20, 3)).atColRow(0, 0);
      expect(cell.style.foreground, isNot(Colors.red));

      tester.pumpWidget(const Text('gone'));
      controller.dispose();
      text.dispose();
    });

    testWidgets('builder supports a custom composite and explicit focus', (
      tester,
    ) async {
      final controller = FormController();
      final focus = FocusNode(debugLabel: 'custom-field');
      tester.pumpWidget(
        Form(
          controller: controller,
          onSubmit: () {},
          child: FormField.builder(
            focusNode: focus,
            validator: () => 'Choose a range.',
            builder: (context, field) => Focus(
              focusNode: focus,
              child: Text(
                field.error == null ? 'range' : 'range: ${field.error}',
              ),
            ),
          ),
        ),
      );

      expect(await _validate(tester, controller), isFalse);
      tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(
        tester.renderToString(size: const CellSize(40, 3)),
        contains('range: Choose a range.'),
      );

      tester.pumpWidget(const Text('gone'));
      controller.dispose();
      focus.dispose();
    });

    testWidgets('nested forms validate independently', (tester) async {
      final outer = FormController();
      final inner = FormController();
      final outerText = TextEditingController(text: 'valid');
      final innerText = TextEditingController();
      tester.pumpWidget(
        Form(
          controller: outer,
          onSubmit: () {},
          child: Column(
            children: <Widget>[
              FormField(
                validator: () => outerText.text.isEmpty ? 'outer' : null,
                child: TextInput(controller: outerText),
              ),
              Form(
                controller: inner,
                onSubmit: () {},
                child: FormField(
                  validator: () => innerText.text.isEmpty ? 'inner' : null,
                  child: TextInput(controller: innerText),
                ),
              ),
            ],
          ),
        ),
      );

      expect(await _validate(tester, outer), isTrue);
      expect(await _validate(tester, inner), isFalse);

      tester.pumpWidget(const Text('gone'));
      outer.dispose();
      inner.dispose();
      outerText.dispose();
      innerText.dispose();
    });

    testWidgets('selection controls participate without manual binding', (
      tester,
    ) async {
      final controller = FormController();
      tester.pumpWidget(
        Form(
          controller: controller,
          onSubmit: () {},
          child: Column(
            children: <Widget>[
              FormField(
                validator: () => 'Accept the terms.',
                child: Checkbox(
                  value: false,
                  label: 'Terms',
                  onChanged: (_) {},
                ),
              ),
              FormField(
                validator: () => 'Choose a region.',
                child: Select<String>(
                  value: null,
                  semanticLabel: 'Region',
                  options: const <SelectOption<String>>[
                    SelectOption(value: 'ca', label: 'Canada'),
                  ],
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
      );

      expect(await _validate(tester, controller), isFalse);
      tester.pump();
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.checkbox, label: 'Terms')
            .validationError,
        'Accept the terms.',
      );
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.button, label: 'Region')
            .validationError,
        'Choose a region.',
      );

      tester.pumpWidget(const Text('gone'));
      controller.dispose();
    });

    testWidgets('one field can replace its control during reconciliation', (
      tester,
    ) async {
      final controller = FormController();
      final text = TextEditingController();

      Widget build(Widget control) => Form(
        controller: controller,
        onSubmit: () {},
        child: FormField(child: SizedBox(width: 20, child: control)),
      );

      tester.pumpWidget(
        build(TextInput(controller: text, semanticLabel: 'Name')),
      );
      await Future<void>.delayed(Duration.zero);

      tester.pumpWidget(
        build(
          Select<String>(
            value: 'production',
            semanticLabel: 'Environment',
            options: const <SelectOption<String>>[
              SelectOption(value: 'production', label: 'Production'),
            ],
            onChanged: (_) {},
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      tester.pump();

      expect(
        tester
            .semantics()
            .single(role: SemanticRole.button, label: 'Environment')
            .value,
        'Production',
      );

      tester.pumpWidget(const Text('gone'));
      controller.dispose();
      text.dispose();
    });

    testWidgets('child rejects two simultaneously live controls', (
      tester,
    ) async {
      Object? captured;
      await runZonedGuarded<Future<void>>(() async {
        tester.pumpWidget(
          Form(
            onSubmit: () {},
            child: FormField(
              child: Row(
                children: <Widget>[
                  Checkbox(value: false, onChanged: (_) {}),
                  Checkbox(value: false, onChanged: (_) {}),
                ],
              ),
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }, (error, _) => captured = error);

      expect(captured, isA<StateError>());
      expect('$captured', contains('found more than one form-aware control'));
    });
  });

  group('automatic control participation', () {
    final cases = <(String, SemanticRole, Widget Function())>[
      (
        'TextInput',
        SemanticRole.textField,
        () => const TextInput(
          semanticLabel: 'Control',
          style: _invalidControlStyle,
        ),
      ),
      (
        'TextArea',
        SemanticRole.textArea,
        () => const TextArea(
          semanticLabel: 'Control',
          style: _invalidControlStyle,
        ),
      ),
      (
        'PasswordInput',
        SemanticRole.textField,
        () => const PasswordInput(
          semanticLabel: 'Control',
          style: _invalidControlStyle,
        ),
      ),
      (
        'NumberInput',
        SemanticRole.textField,
        () => const NumberInput(
          semanticLabel: 'Control',
          style: _invalidControlStyle,
        ),
      ),
      (
        'CompletionTextInput',
        SemanticRole.textField,
        () => CompletionTextInput(
          semanticLabel: 'Control',
          provider: (_) => const <TextCompletionOption>[],
          style: _invalidControlStyle,
        ),
      ),
      (
        'Autocomplete',
        SemanticRole.textField,
        () => Autocomplete<String>(
          options: const <String>['alpha'],
          fieldSemanticLabel: 'Control',
          style: _invalidControlStyle,
        ),
      ),
      (
        'Checkbox',
        SemanticRole.checkbox,
        () => Checkbox(
          value: false,
          label: 'Control',
          onChanged: (_) {},
          style: _invalidControlStyle,
        ),
      ),
      (
        'Toggle',
        SemanticRole.toggle,
        () => Toggle(
          value: false,
          label: 'Control',
          onChanged: (_) {},
          style: _invalidControlStyle,
        ),
      ),
      (
        'Switch',
        SemanticRole.toggle,
        () => Switch(
          value: false,
          label: 'Control',
          onChanged: (_) {},
          style: _invalidControlStyle,
        ),
      ),
      (
        'RadioGroup',
        SemanticRole.region,
        () => RadioGroup<String>(
          value: 'one',
          semanticLabel: 'Control',
          options: const <RadioOption<String>>[
            RadioOption(value: 'one', label: 'One'),
          ],
          onChanged: (_) {},
          style: _invalidControlStyle,
        ),
      ),
      (
        'Select',
        SemanticRole.button,
        () => Select<String>(
          value: 'one',
          semanticLabel: 'Control',
          options: const <SelectOption<String>>[
            SelectOption(value: 'one', label: 'One'),
          ],
          onChanged: (_) {},
          style: _invalidControlStyle,
        ),
      ),
      (
        'MultiSelect',
        SemanticRole.list,
        () => MultiSelect<String>(
          values: const <String>{'one'},
          semanticLabel: 'Control',
          options: const <SelectOption<String>>[
            SelectOption(value: 'one', label: 'One'),
          ],
          onChanged: (_) {},
          style: _invalidControlStyle,
        ),
      ),
      (
        'Stepper',
        SemanticRole.spinButton,
        () => Stepper(
          value: 1,
          label: 'Control',
          onChanged: (_) {},
          style: _invalidControlStyle,
        ),
      ),
      (
        'RangeSlider',
        SemanticRole.slider,
        () => RangeSlider(
          values: const (1, 2),
          min: 0,
          max: 3,
          label: 'Control',
          onChanged: (_) {},
          style: _invalidControlStyle,
        ),
      ),
      (
        'DatePicker',
        SemanticRole.datePicker,
        () => DatePicker(
          value: DateTime(2026, 8, 14),
          label: 'Control',
          onChanged: (_) {},
          style: _invalidControlStyle,
        ),
      ),
      (
        'ColorPicker',
        SemanticRole.list,
        () => ColorPicker(
          value: Colors.red,
          semanticLabel: 'Control',
          onChanged: (_) {},
          style: _invalidControlStyle,
        ),
      ),
    ];

    for (final (name, role, buildControl) in cases) {
      testWidgets('$name receives the enclosing field error', (tester) async {
        final controller = FormController();
        tester.pumpWidget(
          Form(
            controller: controller,
            onSubmit: () {},
            child: FormField(
              validator: () => 'Invalid value.',
              child: buildControl(),
            ),
          ),
        );

        expect(await _validate(tester, controller), isFalse);
        tester.pump();
        expect(
          tester
              .semantics()
              .single(role: role, label: 'Control')
              .validationError,
          'Invalid value.',
        );
        expect(
          _hasForeground(tester, _invalidControlColor),
          isTrue,
          reason: '$name must paint its invalid state as well as expose it',
        );

        tester.pumpWidget(const Text('gone'));
        controller.dispose();
      });
    }
  });
}
