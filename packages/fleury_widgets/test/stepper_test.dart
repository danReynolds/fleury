import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  group('Stepper', () {
    testWidgets('renders the value between − and + chrome', (tester) {
      tester.pumpWidget(Stepper(value: 42, onChanged: (_) {}));
      final out = tester
          .renderToString(size: const CellSize(20, 1), emptyMark: ' ')
          .trimRight();
      expect(out.contains('[ − 42 + ]'), isTrue);
    });

    testWidgets('Arrow Up increments by step when focused', (tester) {
      num received = -1;
      tester.pumpWidget(
        Stepper(
          value: 10,
          step: 3,
          autofocus: true,
          onChanged: (v) => received = v,
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
      expect(received, 13);
    });

    testWidgets('Arrow Down decrements by step', (tester) {
      num received = -1;
      tester.pumpWidget(
        Stepper(
          value: 10,
          step: 2,
          autofocus: true,
          onChanged: (v) => received = v,
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      expect(received, 8);
    });

    testWidgets('PageUp/PageDown move by largeStep', (tester) {
      final calls = <num>[];
      tester.pumpWidget(
        Stepper(
          value: 50,
          step: 1,
          largeStep: 25,
          autofocus: true,
          onChanged: calls.add,
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.pageUp));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.pageDown));
      expect(calls, [75, 25]);
    });

    testWidgets('Home/End jump to min/max', (tester) {
      final calls = <num>[];
      tester.pumpWidget(
        Stepper(
          value: 50,
          min: 0,
          max: 100,
          autofocus: true,
          onChanged: calls.add,
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.home));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.end));
      expect(calls, [0, 100]);
    });

    testWidgets('clamps to max — no callback when already at limit', (tester) {
      var count = 0;
      tester.pumpWidget(
        Stepper(value: 10, max: 10, autofocus: true, onChanged: (_) => count++),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
      expect(count, 0, reason: 'already at max, no change');
    });

    testWidgets('+ and − text input also nudge', (tester) {
      // Controlled widget — without updating the prop, each press
      // nudges from the original value, so '+' fires +1 and '-' fires
      // -1 (both deltas relative to the original 5).
      final calls = <num>[];
      tester.pumpWidget(
        Stepper(value: 5, autofocus: true, onChanged: calls.add),
      );
      tester.type('+');
      tester.type('-');
      expect(calls, [6, 4]);
    });

    testWidgets('shows a label when provided', (tester) {
      tester.pumpWidget(Stepper(value: 7, label: 'qty', onChanged: (_) {}));
      final out = tester.renderToString(size: const CellSize(16, 1));
      expect(out.contains('qty'), isTrue);
    });

    testWidgets('null onChanged disables the stepper', (tester) async {
      tester.pumpWidget(
        const Stepper(value: 7, label: 'qty', autofocus: true, onChanged: null),
      );

      final node = tester.semantics().single(
        role: SemanticRole.spinButton,
        label: 'qty',
        enabled: false,
      );
      expect(node.actions, isEmpty);
      expect(node.value, 7);
      expect(node.state['canIncrement'], isFalse);
      expect(node.state['canDecrement'], isFalse);
      expect(
        tester.render(size: const CellSize(16, 1)).atColRow(0, 0).style.dim,
        isTrue,
      );

      final result = await tester.invokeSemanticAction(
        SemanticAction.increment,
        node: node,
      );
      expect(result.status, SemanticActionInvocationStatus.disabled);
    });

    testWidgets(
      'exposes spin button semantics and increment/decrement actions',
      (tester) async {
        final calls = <num>[];
        tester.pumpWidget(
          Stepper(
            value: 7,
            min: 0,
            max: 10,
            step: 2,
            largeStep: 5,
            label: 'qty',
            onChanged: calls.add,
          ),
        );

        final node = tester.semantics().single(
          role: SemanticRole.spinButton,
          label: 'qty',
          value: 7,
          action: SemanticAction.increment,
        );
        expect(node.actions, contains(SemanticAction.decrement));
        expect(node.state['numericValue'], 7);
        expect(node.state['min'], 0);
        expect(node.state['max'], 10);
        expect(node.state['step'], 2);
        expect(
          tester
              .accessibilitySnapshot()
              .single(role: SemanticRole.spinButton, label: 'qty')
              .states,
          contains('value 7, min 0, max 10, step 2, large step 5'),
        );

        final increment = await tester.invokeSemanticAction(
          SemanticAction.increment,
          role: SemanticRole.spinButton,
          label: 'qty',
        );
        final decrement = await tester.invokeSemanticAction(
          SemanticAction.decrement,
          role: SemanticRole.spinButton,
          label: 'qty',
        );

        expect(increment.completed, isTrue);
        expect(decrement.completed, isTrue);
        expect(calls, [9, 5]);
        expect(
          tester
              .semantics()
              .single(role: SemanticRole.spinButton, label: 'qty')
              .focused,
          isTrue,
        );
      },
    );

    testWidgets('omits bounded spin button semantic actions at limits', (
      tester,
    ) {
      tester.pumpWidget(
        Stepper(value: 10, min: 0, max: 10, label: 'qty', onChanged: (_) {}),
      );

      final node = tester.semantics().single(
        role: SemanticRole.spinButton,
        label: 'qty',
      );

      expect(node.actions, isNot(contains(SemanticAction.increment)));
      expect(node.actions, contains(SemanticAction.decrement));
      expect(node.state['canIncrement'], isFalse);
      expect(node.state['canDecrement'], isTrue);
    });
  });
}
