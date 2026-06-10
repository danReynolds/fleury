import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _line(FleuryTester tester, {int cols = 16}) {
  final buf = tester.render(size: CellSize(cols, 1));
  final sb = StringBuffer();
  for (var c = 0; c < cols; c++) {
    final cell = buf.atColRow(c, 0);
    sb.write(cell.role == CellRole.leading ? cell.grapheme! : ' ');
  }
  return sb.toString().trimRight();
}

void main() {
  group('Checkbox', () {
    testWidgets('renders state and label', (tester) {
      tester.pumpWidget(
        Checkbox(value: false, label: 'Wrap', onChanged: (_) {}),
      );
      expect(_line(tester), '[ ] Wrap');
      tester.pumpWidget(
        Checkbox(value: true, label: 'Wrap', onChanged: (_) {}),
      );
      expect(_line(tester), '[x] Wrap');
    });

    testWidgets('Enter toggles when focused', (tester) {
      bool? changed;
      tester.pumpWidget(
        Checkbox(value: false, autofocus: true, onChanged: (v) => changed = v),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(changed, isTrue);
    });

    testWidgets('does not toggle when unfocused', (tester) {
      var calls = 0;
      tester.pumpWidget(Checkbox(value: false, onChanged: (_) => calls++));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(calls, 0);
    });

    testWidgets('Space toggles when focused', (tester) {
      bool? changed;
      tester.pumpWidget(
        Checkbox(value: false, autofocus: true, onChanged: (v) => changed = v),
      );
      tester.type(' '); // Space arrives as inserted text
      expect(changed, isTrue);
    });

    testWidgets('pasted space does not toggle when focused', (tester) {
      var calls = 0;
      tester.pumpWidget(
        Checkbox(value: false, autofocus: true, onChanged: (_) => calls++),
      );
      tester.paste(' ');
      expect(calls, 0);
    });

    testWidgets('exposes semantic state', (tester) {
      tester.pumpWidget(
        Checkbox(
          value: true,
          label: 'Wrap',
          autofocus: true,
          onChanged: (_) {},
        ),
      );

      final node = tester.semantics().single(
        role: SemanticRole.checkbox,
        label: 'Wrap',
        focused: true,
        action: SemanticAction.activate,
      );

      expect(node.checked, isTrue);
      expect(node.value, isTrue);
      expect(node.actions, contains(SemanticAction.focus));
    });

    testWidgets('semantic activate toggles and focuses checkbox', (
      tester,
    ) async {
      bool? changed;
      tester.pumpWidget(
        Checkbox(value: false, label: 'Wrap', onChanged: (v) => changed = v),
      );

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.checkbox,
        label: 'Wrap',
      );

      expect(result.completed, isTrue);
      expect(changed, isTrue);
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.checkbox, label: 'Wrap')
            .focused,
        isTrue,
      );
    });

    testWidgets('null onChanged disables checkbox', (tester) async {
      tester.pumpWidget(
        const Checkbox(value: false, label: 'Wrap', onChanged: null),
      );

      final node = tester.semantics().single(
        role: SemanticRole.checkbox,
        label: 'Wrap',
        enabled: false,
      );
      expect(node.actions, isEmpty);
      expect(
        tester.render(size: const CellSize(8, 1)).atColRow(0, 0).style.dim,
        isTrue,
      );

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        node: node,
      );
      expect(result.status, SemanticActionInvocationStatus.disabled);
    });
  });

  group('Toggle', () {
    testWidgets('renders the knob position', (tester) {
      tester.pumpWidget(Toggle(value: false, onChanged: (_) {}));
      expect(_line(tester), '[o ]');
      tester.pumpWidget(Toggle(value: true, onChanged: (_) {}));
      expect(_line(tester), '[ o]');
    });

    testWidgets('exposes toggle semantics', (tester) {
      tester.pumpWidget(
        Toggle(value: true, label: 'Feature', onChanged: (_) {}),
      );

      final node = tester.semantics().single(
        role: SemanticRole.toggle,
        label: 'Feature',
      );

      expect(node.checked, isTrue);
      expect(node.value, isTrue);
      expect(node.actions, contains(SemanticAction.activate));
    });

    testWidgets('semantic activate toggles value', (tester) async {
      bool? changed;
      tester.pumpWidget(
        Toggle(value: true, label: 'Feature', onChanged: (v) => changed = v),
      );

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.toggle,
        label: 'Feature',
      );

      expect(result.completed, isTrue);
      expect(changed, isFalse);
    });

    testWidgets('null onChanged disables toggle', (tester) {
      tester.pumpWidget(
        const Toggle(value: true, label: 'Feature', onChanged: null),
      );

      final node = tester.semantics().single(
        role: SemanticRole.toggle,
        label: 'Feature',
        enabled: false,
      );

      expect(node.actions, isEmpty);
      expect(node.checked, isTrue);
    });
  });

  group('Radio', () {
    testWidgets('selected when value == groupValue', (tester) {
      tester.pumpWidget(
        Radio<int>(value: 1, groupValue: 2, label: 'One', onChanged: (_) {}),
      );
      expect(_line(tester), '( ) One');
      tester.pumpWidget(
        Radio<int>(value: 1, groupValue: 1, label: 'One', onChanged: (_) {}),
      );
      expect(_line(tester), '(o) One');
    });

    testWidgets('Enter selects this radio value', (tester) {
      int? picked;
      tester.pumpWidget(
        Radio<int>(
          value: 3,
          groupValue: 1,
          autofocus: true,
          onChanged: (v) => picked = v,
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(picked, 3);
    });

    testWidgets('Space selects this radio value', (tester) {
      int? picked;
      tester.pumpWidget(
        Radio<int>(
          value: 3,
          groupValue: 1,
          autofocus: true,
          onChanged: (v) => picked = v,
        ),
      );
      tester.type(' ');
      expect(picked, 3);
    });

    testWidgets('exposes radio selection semantics', (tester) {
      tester.pumpWidget(
        Radio<int>(value: 1, groupValue: 1, label: 'One', onChanged: (_) {}),
      );

      final node = tester.semantics().single(
        role: SemanticRole.radio,
        label: 'One',
        selected: true,
      );

      expect(node.checked, isTrue);
      expect(node.value, 1);
    });

    testWidgets('semantic activate selects radio value', (tester) async {
      int? picked;
      tester.pumpWidget(
        Radio<int>(
          value: 3,
          groupValue: 1,
          label: 'Three',
          onChanged: (v) => picked = v,
        ),
      );

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.radio,
        label: 'Three',
      );

      expect(result.completed, isTrue);
      expect(picked, 3);
    });

    testWidgets('null onChanged disables radio', (tester) {
      tester.pumpWidget(
        const Radio<int>(
          value: 1,
          groupValue: 2,
          label: 'One',
          onChanged: null,
        ),
      );

      final node = tester.semantics().single(
        role: SemanticRole.radio,
        label: 'One',
        enabled: false,
      );

      expect(node.actions, isEmpty);
      expect(node.selected, isFalse);
    });
  });

  testWidgets('focused control shows a bold cue', (tester) {
    tester.pumpWidget(
      Checkbox(value: false, autofocus: true, onChanged: (_) {}),
    );
    final buf = tester.render(size: const CellSize(4, 1));
    expect(buf.atColRow(0, 0).style.bold, isTrue);
  });
}
