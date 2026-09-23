import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/input/file_actions.dart';
import '../../lib/input/press_tile.dart';
import 'pointer_test_helpers.dart';

void main() {
  testWidgets(
    'the button opens by pointer and closes by keyboard in the guide viewport',
    (tester) {
      tester.pumpFleuryHome(
        const Padding(padding: EdgeInsets.all(1), child: FileActions()),
      );
      expect(tester.renderToString(), contains('Preview closed'));
      pointer(tester, MouseEventKind.down, 3, 1);
      expect(tester.render().atColRow(3, 1).style.inverse, isTrue);
      pointer(tester, MouseEventKind.up, 3, 1);
      expect(tester.renderToString(), contains('Bring the sketches.'));
      expect(tester.button('Close note'), isFocused);
      tester.press(KeySequence.enter);
      expect(tester.renderToString(), contains('Preview closed'));
      tester.press(KeySequence.space);
      expect(tester.renderToString(), contains('Bring the sketches.'));
      pointer(tester, MouseEventKind.down, 3, 1);
      pointer(tester, MouseEventKind.drag, 7, 1);
      pointer(tester, MouseEventKind.up, 7, 1);
      expect(tester.renderToString(), contains('Bring the sketches.'));
      expect(tester.render().atColRow(3, 1).style.inverse, isFalse);
    },
    viewportSize: const CellSize(38, 11),
  );

  testWidgets(
    'custom tile preview fits the guide and can be closed',
    (tester) {
      tester.pumpFleuryHome(
        const Padding(padding: EdgeInsets.all(1), child: PressTile()),
      );
      tester.press(KeySequence.enter);
      expect(tester.renderToString(), contains('Bring the sketches.'));
      tester.press(KeySequence.tab);
      tester.press(KeySequence.enter);
      expect(tester.renderToString(), contains('Location: /notes'));
      tester.press(KeySequence.tab);
      tester.press(KeySequence.enter);
      expect(tester.renderToString(), contains('Your note will appear here.'));
    },
    viewportSize: const CellSize(38, 19),
  );
}
