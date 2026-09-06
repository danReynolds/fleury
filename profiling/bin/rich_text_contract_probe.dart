// Differential receipt across revisions: layout, cell values and selected copy.
// Deliberately includes whitespace, zero-width clusters, styles and lowering.
import 'dart:convert';
import 'dart:math';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/widgets/rich_text.dart' show RenderRichText;

void main(List<String> args) {
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
  var layoutHash = 2166136261;
  var copyHash = 2166136261;
  var caseHash = 2166136261;
  void add(Object? value, {bool copy = false}) {
    for (final code in '$value;'.codeUnits) {
      hash = ((hash ^ code) * 16777619) & 0xffffffff;
      if (copy) {
        copyHash = ((copyHash ^ code) * 16777619) & 0xffffffff;
      } else {
        layoutHash = ((layoutHash ^ code) * 16777619) & 0xffffffff;
        caseHash = ((caseHash ^ code) * 16777619) & 0xffffffff;
      }
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
              caseHash = 2166136261;
              final render = RenderRichText(
                  span: span,
                  base: CellStyle.none,
                  softWrap: wrap,
                  textPolicy: policy,
                  maxLines: maxLines,
                  overflow: overflow);
              if (args.contains('--resize')) {
                for (final width in <int?>[12, 0, null, 1]) {
                  render.layout(CellConstraints(maxCols: width));
                  render.paint(CellBuffer(const CellSize(20, 12)),
                      const CellOffset(0, -1));
                  render.dispatchSelectionEvent(const SelectionEdgeUpdateEvent(
                      globalPosition: CellOffset(2, 1), isStart: true));
                  render.dispatchSelectionEvent(const SelectionEdgeUpdateEvent(
                      globalPosition: CellOffset(6, 3), isStart: false));
                }
                render.dispatchSelectionEvent(const SelectionClearEvent());
              }
              render.layout(CellConstraints(maxCols: cols));
              final buffer = CellBuffer(const CellSize(20, 12));
              render.paint(buffer, const CellOffset(0, -1));
              add(render.size);
              add(render.selectionLines);
              render.dispatchSelectionEvent(const SelectionGranularEvent(
                  granularity: SelectionGranularity.all));
              final copied = render.getSelectedContent()?.plainText;
              add(copied, copy: true);
              buffer.clear();
              render.paint(buffer, const CellOffset(0, -1));
              for (var row = 0; row < 12; row++) {
                for (var col = 0; col < 20; col++) {
                  final cell = buffer.atColRow(col, row);
                  add('${cell.role}|${cell.grapheme}|${cell.style}');
                }
              }
              if (args.contains('--details')) {
                print(jsonEncode({
                  'case': cases,
                  'fixture': fixture,
                  'columns': cols,
                  'wrap': wrap,
                  'policy': policy.toString(),
                  'maxLines': maxLines,
                  'overflow': overflow.name,
                  'layoutFingerprint': caseHash,
                  'copy': copied
                }));
              }
              cases++;
            }
          }
        }
      }
    }
  }
  print(jsonEncode({
    'cases': cases,
    'fingerprint': hash,
    'layoutFingerprint': layoutHash,
    'copyFingerprint': copyHash
  }));
}
