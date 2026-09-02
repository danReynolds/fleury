// CodeView/JsonView fill a bounded parent; maxVisible caps only the
// unbounded case.
//
// The viewers bounded their own height unconditionally, so a viewer under a
// loose BOUNDED parent (Center, Align, a Container, a Stack layer) shrank to
// 12 rows where it used to fill — a silent shrink for existing apps. The cap
// is for parents that give no height (a Column), where the lazy list would
// otherwise throw.

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _screen(FleuryTester tester) =>
    tester.renderToString(size: const CellSize(40, 40), emptyMark: ' ');

void main() {
  final source = List.generate(30, (i) => 'line ${i + 1}').join('\n');

  testWidgets('under a bounded parent the viewer fills the height', (tester) {
    tester.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: CodeView(source: source),
      ),
    );
    final out = _screen(tester);
    expect(out, contains('line 20'), reason: 'not capped at 12 rows');
    expect(out, contains('line 30'));
  });

  testWidgets('under an unbounded parent maxVisible still bounds it', (tester) {
    tester.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CodeView(source: source),
          const Text('AFTER'),
        ],
      ),
    );
    final out = _screen(tester);
    expect(out, contains('line 1'));
    expect(out, isNot(contains('line 20')), reason: 'capped (12 rows)');
    expect(out, contains('AFTER'), reason: 'the column continues below');
  });
}
