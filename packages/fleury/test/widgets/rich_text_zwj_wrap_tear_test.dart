// Lock test (audit 4.b): wrapping must not tear a lowered ZWJ cluster.
//
// Two halves, and the second is why this is not just "keep the group whole":
//   * A cluster that FITS on a line is never split across rows.
//   * A cluster too wide for ANY line splits into its atoms, because keeping
//     it whole cannot make it fit — it only pushes the tail past the box for
//     paint to clip, and those components are then gone with no ellipsis.
//
// RenderText already resolves it that way (`_breakUnits` falls back to
// `displayAtomRanges` when a group exceeds maxWidth), and `Text` and
// `RichText` disagreeing about the same string is itself a bug, so the
// assertion below is parity between the two renderers.
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

const _family = '\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466}';
const _split = TextPresentationPolicy(lowering: ClusterLowering.split);

List<String> _paintRich(String text, int cols, int rows) {
  final render = RenderRichText(
    span: TextSpan(text: text),
    base: CellStyle.none,
    softWrap: true,
    textPolicy: _split,
  )..layout(CellConstraints(maxCols: cols));
  final buf = CellBuffer(CellSize(cols, rows));
  render.paint(buf, CellOffset.zero);
  return [for (var r = 0; r < rows; r++) row(buf, r)];
}

List<String> _paintPlain(String text, int cols, int rows) {
  final render = RenderText(text: text, softWrap: true, textPolicy: _split)
    ..layout(CellConstraints(maxCols: cols));
  final buf = CellBuffer(CellSize(cols, rows));
  render.paint(buf, CellOffset.zero);
  return [for (var r = 0; r < rows; r++) row(buf, r)];
}

void main() {
  test('a cluster that fits a line is never torn mid-word', () {
    // The case that actually exercises the wrap change: the WORD is 11 cells
    // and does not fit in 8, so it takes the hard-break path — but the
    // cluster itself is only 6 and does fit, so it must move to the next line
    // whole rather than being split at the break point.
    final rich = _paintRich('abcde$_family', 8, 3);
    final plain = _paintPlain('abcde$_family', 8, 3);

    expect(
      rich,
      plain,
      reason:
          'Text and RichText must break the same way; before the fix '
          'RichText tore the cluster (abcde+man / woman+child) while '
          'RenderText moved it whole',
    );
    final clusterRow = rich.indexWhere((l) => l.contains('\u{1F468}'));
    expect(
      rich[clusterRow],
      contains('\u{1F466}'),
      reason: 'all three components land on the same row',
    );
  });

  test('a cluster too wide for any line splits, and matches RenderText', () {
    // 6 cells of family, 4 cells of room: it cannot fit on one row either way.
    final rich = _paintRich(_family, 4, 4);
    final plain = _paintPlain(_family, 4, 4);

    expect(
      rich,
      plain,
      reason: 'Text and RichText must render the same string the same way',
    );
    final richCells = rich.join().replaceAll(RegExp(r'[\.]'), '');
    expect(
      richCells,
      contains('\u{1F466}'),
      reason:
          'the third component must still be painted somewhere — keeping the '
          'group whole clipped it away entirely',
    );
  });
}
