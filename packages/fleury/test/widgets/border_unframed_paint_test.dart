// RenderBorder decided "no room for a frame" at layout (handing the child
// the full width) but re-derived that decision at paint with a threshold one
// cell lower, so a 2-wide box got a frame painted over its content.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('a box too narrow to frame is painted unframed, as laid out', (
    tester,
  ) {
    tester.pumpWidget(
      const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 2,
          height: 3,
          child: Container.framed(child: Text('ab')),
        ),
      ),
    );
    final buf = tester.render(size: const CellSize(6, 4));
    expect(buf.atColRow(0, 0).grapheme, 'a', reason: 'no frame over content');
    expect(buf.atColRow(1, 0).grapheme, 'b');
  });
}
