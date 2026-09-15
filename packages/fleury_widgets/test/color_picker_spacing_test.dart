import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('spaced rows preserve keyboard and pointer grid selection', (
    tester,
  ) {
    Color? selected;
    tester.pumpWidget(
      ColorPicker(
        value: const AnsiColor(0),
        onChanged: (value) => selected = value,
        autofocus: true,
        swatchWidth: 1,
        rowSpacing: 1,
        showHelp: false,
      ),
    );
    final frame = tester.render(size: const CellSize(30, 6));
    expect(frame.atColRow(1, 0).grapheme, '█');
    expect(frame.atColRow(1, 1).grapheme ?? ' ', ' ');
    expect(frame.atColRow(1, 2).grapheme, '█');
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    expect(selected, isNull);
    tester.sendKey(const KeyEvent(KeyCode.enter));
    expect(selected, const AnsiColor(8));
    tester.render();
    for (final kind in [MouseEventKind.down, MouseEventKind.up]) {
      tester.sendMouse(
        MouseEvent(kind: kind, button: MouseButton.left, col: 4, row: 2),
      );
      tester.render();
    }
    expect(selected, const AnsiColor(9));
    expect(tester.renderToString(), isNot(contains('preview')));
  });
}
