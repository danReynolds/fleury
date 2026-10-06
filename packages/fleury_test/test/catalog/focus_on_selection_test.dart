// A focused control's focus cue lands on an item that also wears the
// selection style. Under a theme whose focus color is its selection fill, the
// cue's color would paint that item's text in its own background color; the
// cue must keep the selection's colors and add only its attributes.

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

const _ink = RgbColor(0x0B, 0x0F, 0x14);
const _accent = RgbColor(0x3D, 0xDC, 0x97);

Widget _themed(Widget child) => Theme(
  data: const ThemeData(
    selectionStyle: CellStyle(foreground: _ink, background: _accent),
    focusedStyle: CellStyle(foreground: _accent, bold: true),
  ),
  child: child,
);

/// The glyph cells painted on the selection fill.
List<Cell> _onSelection(FleuryTester tester, CellSize size) {
  final buffer = tester.render(size: size);
  return [
    for (var row = 0; row < size.rows; row++)
      for (var col = 0; col < size.cols; col++)
        if (buffer.atColRow(col, row) case final cell
            when cell.style.background == _accent &&
                (cell.grapheme?.trim().isNotEmpty ?? false))
          cell,
  ];
}

void main() {
  testWidgets('a focused DatePicker keeps its selected day readable', (tester) {
    tester.pumpWidget(
      _themed(
        DatePicker(
          value: DateTime(2024, 3, 15),
          autofocus: true,
          onChanged: (_) {},
        ),
      ),
    );
    final cells = _onSelection(tester, const CellSize(24, 9));
    expect(cells.map((c) => c.grapheme).join(), '15');
    for (final cell in cells) {
      expect(cell.style.foreground, _ink);
      expect(cell.style.bold, isTrue, reason: 'the focus cue still shows');
    }
  });

  testWidgets('a focused ColorPicker keeps its cursor marks readable', (
    tester,
  ) {
    tester.pumpWidget(
      _themed(
        ColorPicker(
          value: const AnsiColor(2),
          autofocus: true,
          onChanged: (_) {},
        ),
      ),
    );
    final cells = _onSelection(tester, const CellSize(80, 2));
    expect(cells.map((c) => c.grapheme).join(), '[]');
    for (final cell in cells) {
      expect(cell.style.foreground, _ink);
      expect(cell.style.bold, isTrue, reason: 'the focus cue still shows');
    }
  });
}
