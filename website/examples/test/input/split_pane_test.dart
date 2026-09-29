import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/input/split_pane.dart';
import 'pointer_test_helpers.dart';

void main() {
  testWidgets(
    'splitter cancels, shows focus and supports held arrows and reset',
    (tester) async {
      tester.pumpFleuryHome(const SizedBox(width: 36, child: SplitPane()));
      expect(tester.render().atColRow(14, 2).style.inverse, isTrue);
      tester.press(KeySequence.tab);
      expect(tester.render().atColRow(14, 2).style.inverse, isFalse);
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.button, label: 'Reset width')
            .focused,
        isTrue,
      );
      tester.press(KeySequence.shift.tab);
      tester.sendKey(
        const KeyEvent(KeyCode.arrowRight, type: KeyEventType.down),
      );
      tester.sendKey(
        const KeyEvent(KeyCode.arrowRight, type: KeyEventType.repeat),
      );
      tester.sendKey(const KeyEvent(KeyCode.arrowRight, type: KeyEventType.up));
      tester.pump();
      expect(tester.semantics().single(role: SemanticRole.slider).value, 16);
      pointer(tester, MouseEventKind.down, 16, 2);
      pointer(tester, MouseEventKind.drag, 20, 2);
      expect(tester.exists(text('Resizing…')), isTrue);
      pointer(tester, MouseEventKind.cancel, 0, 0);
      pointer(tester, MouseEventKind.drag, 24, 2);
      pointer(tester, MouseEventKind.up, 24, 2);
      expect(tester.exists(text('Width: 20 · ← → resize')), isTrue);
      final handle = tester.semantics().single(
        role: SemanticRole.slider,
        label: 'File pane width',
      );
      await tester.invokeSemanticAction(SemanticAction.decrement, node: handle);
      tester.pump();
      expect(tester.semantics().single(role: SemanticRole.slider).value, 19);
      tester.press(KeySequence.tab);
      tester.press(KeySequence.enter);
      expect(tester.exists(text('Width: 14 · ← → resize')), isTrue);
    },
  );

  testWidgets('one movement resizes; release outside ends the drag', (tester) {
    tester.pumpWidget(const SizedBox(width: 36, child: SplitPane()));
    pointer(tester, MouseEventKind.down, 14, 2);
    pointer(tester, MouseEventKind.drag, 18, 2);
    expect(tester.exists(text('Resizing…')), isTrue);
    pointer(tester, MouseEventKind.up, 40, 8);
    expect(tester.exists(text('Width: 18 · ← → resize')), isTrue);
    tester.press(KeySequence.left);
    expect(tester.exists(text('Width: 17 · ← → resize')), isTrue);
  });
}
