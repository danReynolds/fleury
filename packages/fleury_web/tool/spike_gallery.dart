// Spike artifact generator: paints a few representative frames into real
// CellBuffers and emits a self-contained `spike.html` you can open in any
// browser. This is pure Dart (no browser needed to GENERATE it); opening the
// result shows exactly what the live DOM presenter will paint, since it uses
// the same markup + CSS.
//
//   dart run tool/spike_gallery.dart
//   open spike.html

import 'dart:io';

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/dom_grid/cell_grid_html.dart';

void box(
  CellBuffer b,
  int x,
  int y,
  int w,
  int h, {
  CellStyle style = CellStyle.empty,
}) {
  b.writeText(CellOffset(x, y), '┌${'─' * (w - 2)}┐', style: style);
  for (var r = 1; r < h - 1; r++) {
    b.writeText(CellOffset(x, y + r), '│', style: style);
    b.writeText(CellOffset(x + w - 1, y + r), '│', style: style);
  }
  b.writeText(CellOffset(x, y + h - 1), '└${'─' * (w - 2)}┘', style: style);
}

CellBuffer dashboard() {
  final b = CellBuffer(const CellSize(46, 15));
  const accent = CellStyle(foreground: Colors.azure);
  box(b, 0, 0, 46, 15, style: accent);

  b.writeText(
    const CellOffset(2, 1),
    ' Fleury ',
    style: const CellStyle(
      foreground: Colors.pureWhite,
      background: Colors.azure,
      bold: true,
    ),
  );
  b.writeText(
    const CellOffset(11, 1),
    'native web render — no xterm.js',
    style: const CellStyle(foreground: Colors.slate, italic: true),
  );

  b.writeText(
    const CellOffset(2, 3),
    'Wide (CJK):',
    style: const CellStyle(foreground: Colors.slate),
  );
  b.writeText(
    const CellOffset(15, 3),
    '状態 良好  ｜  日本語',
    style: const CellStyle(foreground: Colors.lime),
  );

  b.writeText(
    const CellOffset(2, 5),
    'Emoji (ZWJ):',
    style: const CellStyle(foreground: Colors.slate),
  );
  b.writeText(
    const CellOffset(15, 5),
    '\u{1F468}‍\u{1F469}‍\u{1F467}‍\u{1F466} build ✅  fire \u{1F525}',
  );

  b.writeText(
    const CellOffset(2, 7),
    'Combining:',
    style: const CellStyle(foreground: Colors.slate),
  );
  b.writeText(const CellOffset(15, 7), 'café  naïve  résumé  añejo');

  b.writeText(
    const CellOffset(2, 9),
    'Styles:',
    style: const CellStyle(foreground: Colors.slate),
  );
  b.writeText(
    const CellOffset(15, 9),
    'bold',
    style: const CellStyle(foreground: Colors.amber, bold: true),
  );
  b.writeText(
    const CellOffset(20, 9),
    'italic',
    style: const CellStyle(foreground: Colors.violet, italic: true),
  );
  b.writeText(
    const CellOffset(27, 9),
    'under',
    style: const CellStyle(foreground: Colors.teal, underline: true),
  );
  b.writeText(
    const CellOffset(33, 9),
    'strike',
    style: const CellStyle(foreground: Colors.crimson, strikethrough: true),
  );
  b.writeText(
    const CellOffset(40, 9),
    'dim',
    style: const CellStyle(foreground: Colors.white, dim: true),
  );

  b.writeText(
    const CellOffset(2, 11),
    'Selected:',
    style: const CellStyle(foreground: Colors.slate),
  );
  b.writeText(
    const CellOffset(15, 11),
    ' highlighted row (inverse) ',
    style: const CellStyle(foreground: Colors.amber, inverse: true),
  );

  // A truecolor gradient swatch row.
  for (var i = 0; i < 24; i++) {
    final t = i / 23;
    final color = RgbColor(
      (40 + t * 200).round(),
      (120 + t * 80).round(),
      (220 - t * 120).round(),
    );
    b.writeText(
      CellOffset(15 + i, 13),
      '█',
      style: CellStyle(foreground: color),
    );
  }
  b.writeText(
    const CellOffset(2, 13),
    'Truecolor:',
    style: const CellStyle(foreground: Colors.slate),
  );

  return b;
}

void main() {
  final buffer = dashboard();
  final doc = StringBuffer()
    ..writeln('<!doctype html><html><head><meta charset="utf-8">')
    ..writeln('<title>Fleury — CellBuffer DOM render spike</title>')
    ..writeln('<style>')
    ..writeln(
      'body { background:#0d0d0d; margin:0; padding:40px; '
      'font-family:system-ui,sans-serif; color:#999; }',
    )
    ..writeln(
      'h1 { font-size:15px; font-weight:600; color:#bbb; margin:0 0 4px; }',
    )
    ..writeln('p  { font-size:13px; margin:0 0 24px; }')
    ..writeln(cellGridCss)
    ..writeln('</style></head><body>')
    ..writeln(
      '<h1>Fleury native web render — CellBuffer → DOM, no terminal emulator</h1>',
    )
    ..writeln(
      '<p>Every glyph below was painted from a real CellBuffer frame. '
      'Selectable text, real fonts, no xterm.js.</p>',
    )
    ..writeln(renderScreenHtml(buffer))
    ..writeln('</body></html>');

  final file = File('spike.html')..writeAsStringSync(doc.toString());
  stdout.writeln('Wrote ${file.absolute.path}');
}
