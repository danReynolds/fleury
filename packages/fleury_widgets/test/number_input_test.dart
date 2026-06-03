import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
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

    testWidgets('rejects non-digit characters (reverts the text)', (tester) {
      final calls = <num?>[];
      tester.pumpWidget(NumberInput(autofocus: true, onChanged: calls.add));
      tester.type('1');
      tester.type('a'); // rejected
      tester.type('2');
      // Only valid digits land — no onChanged for 'a'.
      expect(calls, [1, 12]);
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
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(submitted, 123);
    });

    testWidgets('onSubmit clamps to min/max', (tester) {
      num? submitted;
      tester.pumpWidget(
        NumberInput(
          autofocus: true,
          min: 0,
          max: 100,
          onSubmit: (v) => submitted = v,
        ),
      );
      tester.type('250');
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(submitted, 100);
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
