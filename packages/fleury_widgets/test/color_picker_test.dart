import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  group('ColorPicker', () {
    testWidgets('renders one swatch per palette color', (tester) {
      tester.pumpWidget(
        ColorPicker(value: const AnsiColor(0), onChanged: (_) {}),
      );
      // 16 colors × (1 sep + 3 swatch + 1 sep) = 80 cols wide naturally.
      // Default columns = 8, swatchWidth = 3.
      final buf = tester.render(size: const CellSize(80, 2));
      // The selected cell at index 0 is bracketed; the swatch sits at
      // cols 1..3 in focused style (the foreground color).
      expect(buf.atColRow(0, 0).grapheme, '[');
      expect(buf.atColRow(4, 0).grapheme, ']');
    });

    testWidgets('the selected swatch is bracketed', (tester) {
      tester.pumpWidget(
        ColorPicker(value: const AnsiColor(2), onChanged: (_) {}),
      );
      final buf = tester.render(size: const CellSize(80, 2));
      // Color index 2: each cell is 5 wide (1 bracket + 3 swatch + 1
      // bracket OR 1 sep + 3 swatch + 1 sep). The selected swatch (col
      // group at 2*5 = 10) should have brackets.
      expect(buf.atColRow(10, 0).grapheme, '[');
      expect(buf.atColRow(14, 0).grapheme, ']');
    });

    testWidgets('arrow right moves selection to the next color', (tester) {
      Color? received;
      tester.pumpWidget(
        ColorPicker(
          value: const AnsiColor(0),
          autofocus: true,
          onChanged: (c) => received = c,
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
      expect(received, const AnsiColor(1));
    });

    testWidgets('arrow down moves selection by one row', (tester) {
      Color? received;
      tester.pumpWidget(
        ColorPicker(
          value: const AnsiColor(0),
          autofocus: true,
          onChanged: (c) => received = c,
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      // Default columns = 8, so down from 0 lands on 8.
      expect(received, const AnsiColor(8));
    });

    testWidgets('arrow right at row edge is a no-op', (tester) {
      Color? received;
      // AnsiColor(7) is the last column of row 0 (indices 0-7).
      tester.pumpWidget(
        ColorPicker(
          value: const AnsiColor(7),
          autofocus: true,
          onChanged: (c) => received = c,
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
      expect(received, isNull);
    });

    testWidgets('Home jumps to the first color', (tester) {
      Color? received;
      tester.pumpWidget(
        ColorPicker(
          value: const AnsiColor(11),
          autofocus: true,
          onChanged: (c) => received = c,
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.home));
      expect(received, const AnsiColor(0));
    });

    testWidgets('End jumps to the last color in the palette', (tester) {
      Color? received;
      tester.pumpWidget(
        ColorPicker(
          value: const AnsiColor(0),
          autofocus: true,
          onChanged: (c) => received = c,
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.end));
      expect(received, const AnsiColor(15));
    });

    testWidgets('custom palette is honored', (tester) {
      Color? received;
      tester.pumpWidget(
        ColorPicker(
          value: const AnsiColor(1),
          colors: const [AnsiColor(1), AnsiColor(5), AnsiColor(9)],
          columns: 3,
          autofocus: true,
          onChanged: (c) => received = c,
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
      expect(received, const AnsiColor(5));
    });
  });
}
