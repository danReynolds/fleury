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
  });
}
