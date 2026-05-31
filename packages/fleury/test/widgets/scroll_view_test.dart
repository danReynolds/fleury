// ScrollView: windowed viewport onto a tall child — scroll chords,
// clamping, clipping, and edge bubbling.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

/// A tall column of single-row labels r0..r{n-1}.
Widget _rows(int n) =>
    Column(children: [for (var i = 0; i < n; i++) Text('r$i')]);

/// Renders [rows] rows of the first column as one string per line.
List<String> _lines(FleuryTester tester, {int cols = 6, required int rows}) {
  final buf = tester.render(size: CellSize(cols, rows));
  final out = <String>[];
  for (var r = 0; r < rows; r++) {
    final sb = StringBuffer();
    for (var c = 0; c < cols; c++) {
      final cell = buf.atColRow(c, r);
      sb.write(cell.role == CellRole.leading ? cell.grapheme : ' ');
    }
    out.add(sb.toString().trimRight());
  }
  return out;
}

void main() {
  testWidgets('shows the top of the content by default', (tester) {
    tester.pumpWidget(ScrollView(child: _rows(10)));
    expect(_lines(tester, rows: 3), ['r0', 'r1', 'r2']);
  });

  testWidgets('scrollBy reveals lower content; metrics are reported', (tester) {
    final ctl = ScrollController();
    tester.pumpWidget(ScrollView(controller: ctl, child: _rows(10)));
    // First render populates metrics (content 10, viewport 3 → max 7).
    expect(_lines(tester, rows: 3), ['r0', 'r1', 'r2']);
    expect(ctl.contentExtent, 10);
    expect(ctl.viewportExtent, 3);
    expect(ctl.maxOffset, 7);

    ctl.scrollBy(2);
    expect(_lines(tester, rows: 3), ['r2', 'r3', 'r4']);
  });

  testWidgets('clamps at the bottom and reports atBottom', (tester) {
    final ctl = ScrollController();
    tester.pumpWidget(ScrollView(controller: ctl, child: _rows(10)));
    _lines(tester, rows: 3); // populate metrics

    ctl.scrollToBottom();
    expect(ctl.offset, 7, reason: 'maxOffset = 10 - 3');
    expect(ctl.atBottom, isTrue);
    expect(_lines(tester, rows: 3), ['r7', 'r8', 'r9']);

    ctl.scrollBy(100); // over-scroll is clamped
    expect(ctl.offset, 7);
  });

  testWidgets('clips content outside the viewport — no bleed below', (tester) {
    // Header sits above a 2-row scroll window over 10 rows; the content
    // below the window must not paint into the header or past the slot.
    tester.pumpWidget(
      Column(
        children: [
          const Text('top'),
          SizedBox(height: 2, child: ScrollView(child: _rows(10))),
          const Text('bot'),
        ],
      ),
    );
    // Rows: top / r0 / r1 / bot — the scroll window is exactly 2 rows.
    expect(_lines(tester, rows: 4), ['top', 'r0', 'r1', 'bot']);
  });

  testWidgets('arrow + page + home/end chords scroll when focused', (tester) {
    final ctl = ScrollController();
    tester.pumpWidget(
      ScrollView(controller: ctl, autofocus: true, child: _rows(20)),
    );
    _lines(tester, rows: 4); // populate metrics (viewport 4 → page 4)

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
    expect(ctl.offset, 1);

    tester.sendKey(const KeyEvent(keyCode: KeyCode.pageDown));
    _lines(tester, rows: 4);
    expect(ctl.offset, 5, reason: '1 + one viewport (4)');

    tester.sendKey(const KeyEvent(keyCode: KeyCode.end));
    expect(ctl.offset, 16, reason: 'maxOffset = 20 - 4');

    tester.sendKey(const KeyEvent(keyCode: KeyCode.home));
    expect(ctl.offset, 0);
  });

  testWidgets('edgeBehavior.bubble lets an ancestor act at the edge', (tester) {
    var bubbled = 0;
    final ctl = ScrollController();
    tester.pumpWidget(
      KeyBindings(
        bindings: [
          KeyBinding(KeyChord.key(KeyCode.arrowUp), onEvent: (_) => bubbled++),
        ],
        child: ScrollView(
          controller: ctl,
          autofocus: true,
          edgeBehavior: EdgeBehavior.bubble,
          child: _rows(10),
        ),
      ),
    );
    _lines(tester, rows: 3);

    // At the top, Up bubbles to the ancestor binding.
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
    expect(bubbled, 1);
    expect(ctl.offset, 0);
  });
}
