import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  group('NumberInput', () {
    testWidgets('accepts digits and emits parsed values', (tester) {
      num? value;
      tester.pumpWidget(
        NumberInput(autofocus: true, onChanged: (v) => value = v),
      );
      tester.type('4');
      tester.type('2');
      expect(value, 42);
    });

    testWidgets('cursor and selection changes do not repeat onChanged', (
      tester,
    ) {
      final controller = TextEditingController();
      final calls = <num?>[];
      tester.pumpWidget(
        NumberInput(
          controller: controller,
          autofocus: true,
          onChanged: calls.add,
        ),
      );
      tester.type('12');

      controller.caretOffset = 1;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 2,
      );

      expect(calls, [12]);
    });

    test('integer mode rejects fractional values and bounds', () {
      expect(
        () => NumberInput(initialValue: 1.5),
        throwsA(isA<AssertionError>()),
      );
      expect(() => NumberInput(min: 0.5), throwsA(isA<AssertionError>()));
      expect(() => NumberInput(max: 1.5), throwsA(isA<AssertionError>()));
      expect(() => NumberInput(min: 2, max: 1), throwsA(isA<AssertionError>()));
      expect(
        () => NumberInput(allowDecimal: true, min: 0.5, max: 1.5),
        returnsNormally,
      );
      expect(
        () =>
            NumberInput(controller: TextEditingController(), initialValue: 1.5),
        returnsNormally,
      );
    });

    testWidgets('rejects non-digit characters (reverts the text)', (tester) {
      final calls = <num?>[];
      tester.pumpWidget(NumberInput(autofocus: true, onChanged: calls.add));
      tester.type('1');
      tester.type('a'); // rejected
      tester.type('2');
      // Only valid digits land — no onChanged for 'a'.
      expect(calls, [1, 12]);
    });

    testWidgets('keeps the caret in place when a character is rejected', (
      tester,
    ) {
      final ctrl = TextEditingController(text: '12');
      tester.pumpWidget(
        NumberInput(controller: ctrl, autofocus: true, onChanged: (_) {}),
      );
      ctrl.caretOffset = 1; // caret between '1' and '2'
      tester.type('a'); // rejected: "1a2" reverts to "12"
      expect(ctrl.text, '12');
      expect(
        ctrl.caretOffset,
        1,
        reason: 'caret stays where the bad char would have gone, not the end',
      );
    });

    testWidgets('accepts a leading - when allowNegative is true', (tester) {
      final calls = <num?>[];
      tester.pumpWidget(NumberInput(autofocus: true, onChanged: calls.add));
      tester.type('-');
      tester.type('5');
      expect(calls, [
        null,
        -5,
      ], reason: '"-" alone is in-progress (null); "-5" parses');
    });

    testWidgets('rejects - when allowNegative is false', (tester) {
      final calls = <num?>[];
      tester.pumpWidget(
        NumberInput(
          autofocus: true,
          allowNegative: false,
          onChanged: calls.add,
        ),
      );
      tester.type('-');
      tester.type('7');
      expect(calls, [7], reason: '- ignored, then 7 lands as a single change');
    });

    testWidgets('allowDecimal: accepts one .', (tester) {
      final calls = <num?>[];
      tester.pumpWidget(
        NumberInput(autofocus: true, allowDecimal: true, onChanged: calls.add),
      );
      tester.type('1');
      tester.type('.');
      tester.type('5');
      tester.type('.'); // second . rejected
      expect(calls, [1, null, 1.5]);
    });

    testWidgets('rejects . when allowDecimal is false', (tester) {
      final calls = <num?>[];
      tester.pumpWidget(NumberInput(autofocus: true, onChanged: calls.add));
      tester.type('1');
      tester.type('.');
      tester.type('5');
      expect(calls, [1, 15]);
    });

    testWidgets('initialValue seeds the field', (tester) {
      tester.pumpWidget(const NumberInput(initialValue: 99));
      final out = tester.renderToString(size: const CellSize(4, 1));
      expect(out.contains('99'), isTrue);
    });

    testWidgets('onSubmit fires the parsed value on Enter', (tester) {
      num? submitted;
      tester.pumpWidget(
        NumberInput(autofocus: true, onSubmit: (v) => submitted = v),
      );
      tester.type('123');
      tester.sendKey(const KeyEvent(KeyCode.enter));
      expect(submitted, 123);
    });

    testWidgets('submit emits a clamped change before the clamped value', (
      tester,
    ) {
      final controller = TextEditingController();
      final changed = <num?>[];
      final events = <String>[];
      tester.pumpWidget(
        NumberInput(
          controller: controller,
          autofocus: true,
          min: 0,
          max: 100,
          onChanged: (value) {
            changed.add(value);
            events.add('changed:$value');
          },
          onSubmit: (value) => events.add('submitted:$value'),
        ),
      );
      tester.type('250');
      expect(changed, [250]);

      tester.sendKey(const KeyEvent(KeyCode.enter));

      expect(changed, [250, 100]);
      expect(events, ['changed:250', 'changed:100', 'submitted:100']);
      expect(controller.text, '100');
      expect(controller.caretOffset, 3);
    });

    testWidgets('submit does not repeat onChanged for an in-range value', (
      tester,
    ) {
      final controller = TextEditingController();
      final events = <String>[];
      tester.pumpWidget(
        NumberInput(
          controller: controller,
          autofocus: true,
          min: 0,
          max: 100,
          onChanged: (value) => events.add('changed:$value'),
          onSubmit: (value) => events.add('submitted:$value'),
        ),
      );
      tester.type('50');

      tester.sendKey(const KeyEvent(KeyCode.enter));

      expect(events, ['changed:50', 'submitted:50']);
      expect(controller.text, '50');
      expect(controller.caretOffset, 2);
    });

    testWidgets('empty submit remains null without an onChanged callback', (
      tester,
    ) {
      final controller = TextEditingController();
      final events = <String>[];
      tester.pumpWidget(
        NumberInput(
          controller: controller,
          autofocus: true,
          min: 0,
          max: 100,
          onChanged: (value) => events.add('changed:$value'),
          onSubmit: (value) => events.add('submitted:$value'),
        ),
      );

      tester.sendKey(const KeyEvent(KeyCode.enter));

      expect(events, ['submitted:null']);
      expect(controller.text, isEmpty);
      expect(controller.caretOffset, 0);
    });

    testWidgets('in-progress submit remains null without a duplicate change', (
      tester,
    ) {
      final controller = TextEditingController();
      final events = <String>[];
      tester.pumpWidget(
        NumberInput(
          controller: controller,
          autofocus: true,
          min: 0,
          max: 100,
          onChanged: (value) => events.add('changed:$value'),
          onSubmit: (value) => events.add('submitted:$value'),
        ),
      );
      tester.type('-');

      tester.sendKey(const KeyEvent(KeyCode.enter));

      expect(events, ['changed:null', 'submitted:null']);
      expect(controller.text, '-');
      expect(controller.caretOffset, 1);
    });

    testWidgets('exposes constrained numeric text-field semantics', (tester) {
      tester.pumpWidget(
        const NumberInput(
          initialValue: 2,
          min: 0,
          max: 5,
          allowNegative: false,
          placeholder: 'Visible example',
          semanticLabel: 'Retry count',
        ),
      );

      final field = tester.semantics().single(
        role: SemanticRole.textField,
        label: 'Retry count',
        value: '2',
      );
      expect(field.actions, contains(SemanticAction.focus));
      expect(field.actions, contains(SemanticAction.clear));
      expect(field.actions, contains(SemanticAction.submit));
      expect(field.state['fieldType'], 'number');
      expect(field.state['numericValue'], 2);
      expect(field.state['min'], 0);
      expect(field.state['max'], 5);
      expect(field.state['allowNegative'], isFalse);
      expect(field.state['allowDecimal'], isFalse);
      expect(field.state['numberFormat'], 'integer');
      expect(field.state['clampOnSubmit'], isTrue);

      final states = tester
          .accessibilitySnapshot()
          .single(role: SemanticRole.textField, label: 'Retry count')
          .states;
      expect(states, contains('field type number'));
      expect(states, contains('value 2, min 0, max 5'));
    });

    testWidgets('semantic submit clamps through the existing submit path', (
      tester,
    ) async {
      final controller = TextEditingController(text: '9');
      num? submitted;
      tester.pumpWidget(
        NumberInput(
          controller: controller,
          min: 0,
          max: 5,
          semanticLabel: 'Retry count',
          onSubmit: (value) => submitted = value,
        ),
      );

      final result = await tester.invokeSemanticAction(
        SemanticAction.submit,
        role: SemanticRole.textField,
        label: 'Retry count',
      );

      expect(result.completed, isTrue);
      expect(submitted, 5);
      expect(controller.text, '5');
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.textField, label: 'Retry count')
            .state['numericValue'],
        5,
      );
    });
  });
}
