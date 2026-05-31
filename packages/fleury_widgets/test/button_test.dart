import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _text(FleuryTester tester, {int cols = 20}) =>
    tester.renderToString(size: CellSize(cols, 1), emptyMark: ' ').trimRight();

void main() {
  group('Button', () {
    testWidgets('renders the label inside brackets', (tester) {
      tester.pumpWidget(Button(label: 'Save', onPressed: () {}));
      expect(_text(tester), '[ Save ]');
    });

    testWidgets('Enter activates when focused', (tester) {
      var presses = 0;
      tester.pumpWidget(
        Button(label: 'Save', autofocus: true, onPressed: () => presses++),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(presses, 1);
    });

    testWidgets('Space activates when focused', (tester) {
      var presses = 0;
      tester.pumpWidget(
        Button(label: 'Save', autofocus: true, onPressed: () => presses++),
      );
      tester.type(' ');
      expect(presses, 1);
    });

    testWidgets('a click activates', (tester) {
      var presses = 0;
      tester.pumpWidget(Button(label: 'Save', onPressed: () => presses++));
      tester.render(size: const CellSize(20, 1)); // register the tap region
      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: 3,
          row: 0,
        ),
      );
      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: 3,
          row: 0,
        ),
      );
      expect(presses, 1);
    });

    testWidgets('does not activate when unfocused', (tester) {
      var presses = 0;
      tester.pumpWidget(Button(label: 'Save', onPressed: () => presses++));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(presses, 0);
    });

    testWidgets('focused button shows the selection highlight', (tester) {
      tester.pumpWidget(Button(label: 'Go', autofocus: true, onPressed: () {}));
      final buf = tester.render(size: const CellSize(10, 1));
      // The default selectionStyle is inverse.
      expect(buf.atColRow(0, 0).style.inverse, isTrue);
    });

    testWidgets('variant tints the label from the color scheme', (tester) {
      tester.pumpWidget(
        const Theme(
          data: ThemeData(),
          child: Button(
            label: 'Go',
            variant: ButtonVariant.primary,
            onPressed: _noop,
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(10, 1));
      expect(buf.atColRow(0, 0).style.foreground, ColorScheme.standard.primary);
    });

    group('disabled (null onPressed)', () {
      testWidgets('renders muted and does not autofocus or activate', (tester) {
        var presses = 0;
        tester.pumpWidget(
          const Button(label: 'Save', autofocus: true, onPressed: null),
        );
        expect(_text(tester), '[ Save ]');
        final buf = tester.render(size: const CellSize(10, 1));
        expect(buf.atColRow(0, 0).style.dim, isTrue, reason: 'muted = dim');
        // Nothing claimed focus, so Enter reaches nothing.
        tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
        expect(presses, 0);
      });
    });
  });
}

void _noop() {}
