import 'package:fleury/fleury.dart';
import 'package:fleury/src/widgets/rich_text.dart' show RenderRichText;
import 'package:test/test.dart';

String row(CellBuffer buf, int r) {
  final sb = StringBuffer();
  for (var c = 0; c < buf.size.cols; c++) {
    final cell = buf.atColRow(c, r);
    sb.write(switch (cell.role) {
      CellRole.leading => cell.grapheme,
      CellRole.continuation => '>',
      CellRole.empty => '.',
      CellRole.overlay => '#',
    });
  }
  return sb.toString();
}

void main() {
  test('lowered ZWJ family does not tear across wrap lines', () {
    // 👨 = 2, 👩 = 2, 👦 = 2 under typical emoji width; three components = 6.
    // Wrap at 4 cols should keep a logical cluster together or at least not
    // split mid-group without marking — today wrap treats atoms as a word and
    // breaks between components when ww > maxCols.
    const family = '\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466}';
    final render = RenderRichText(
      span: const TextSpan(text: family),
      base: CellStyle.none,
      softWrap: true,
      textPolicy: const TextPresentationPolicy(lowering: ClusterLowering.split),
    )..layout(const CellConstraints(maxCols: 4));
    final buf = CellBuffer(const CellSize(4, 4));
    render.paint(buf, CellOffset.zero);
    final lines = [for (var r = 0; r < 4; r++) row(buf, r)];
    // If torn across lines, more than one non-empty row appears for a single
    // cluster with no spaces — document the actual behavior.
    final nonEmpty = lines.where((l) => l.contains(RegExp(r'[^\.]'))).toList();
    // A "tear" means components of one groupId landed on different rows.
    // We assert the preferred contract: single-cluster content stays on one
    // line when the full cluster fits after lowering... but 6 > 4 so it must
    // either overflow-clip as a unit or wrap as a unit (not mid-cluster).
    // Mid-cluster wrap is the bug (4.b).
    expect(
      nonEmpty.length,
      1,
      reason: 'lowered ZWJ cluster must not tear across lines; got $nonEmpty',
    );
  });
}
