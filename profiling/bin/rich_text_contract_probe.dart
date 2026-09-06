// Differential receipt across revisions: layout, cell values and selected copy.
// Deliberately includes whitespace, zero-width clusters, styles and lowering.
import 'dart:convert';
import 'dart:math';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/widgets/rich_text.dart' show RenderRichText;

void main() {
  final random = Random(73183);
  const atoms = [
    'a',
    'b',
    ' ',
    '  ',
    '\n',
    '\n\n',
    '漢',
    '─',
    '👩‍💻',
    '\u0301',
    'e\u0301',
    '\t',
    '\x1b'
  ];
  const styles = [
    CellStyle.none,
    CellStyle(bold: true),
    CellStyle(foreground: AnsiColor(2)),
    CellStyle(linkUri: 'https://example.com', underline: true)
  ];
  var hash = 2166136261;
  var cases = 0;
  void add(Object? value) {
    for (final code in '$value;'.codeUnits) {
      hash = ((hash ^ code) * 16777619) & 0xffffffff;
    }
  }

  for (var fixture = 0; fixture < 64; fixture++) {
    final span = TextSpan(children: [
      for (var run = 0; run < 4; run++)
        TextSpan(
          text: List.generate(8, (_) => atoms[random.nextInt(atoms.length)])
              .join(),
          style: styles[random.nextInt(styles.length)],
        ),
    ]);
    for (final cols in <int?>[0, 1, 5, 12, null]) {
      for (final wrap in [false, true]) {
        for (final policy in [
          TextPresentationPolicy.spec,
          const TextPresentationPolicy(widths: CellWidthPolicy.cjk),
          const TextPresentationPolicy(lowering: ClusterLowering.split)
        ]) {
          for (final maxLines in <int?>[null, 2]) {
            for (final overflow in TextOverflow.values) {
              final render = RenderRichText(
                  span: span,
                  base: CellStyle.none,
                  softWrap: wrap,
                  textPolicy: policy,
                  maxLines: maxLines,
                  overflow: overflow);
              render.layout(CellConstraints(maxCols: cols));
              final buffer = CellBuffer(const CellSize(20, 12));
              render.paint(buffer, const CellOffset(0, -1));
              add(render.size);
              add(render.selectionLines);
              render.dispatchSelectionEvent(const SelectionGranularEvent(
                  granularity: SelectionGranularity.all));
              add(render.getSelectedContent()?.plainText);
              buffer.clear();
              render.paint(buffer, const CellOffset(0, -1));
              for (var row = 0; row < 12; row++) {
                for (var col = 0; col < 20; col++) {
                  final cell = buffer.atColRow(col, row);
                  add('${cell.role}|${cell.grapheme}|${cell.style}');
                }
              }
              cases++;
            }
          }
        }
      }
    }
  }
  print(jsonEncode({'cases': cases, 'fingerprint': hash}));
}
