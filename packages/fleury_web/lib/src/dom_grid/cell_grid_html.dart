/// Pure `CellBuffer` → HTML span-grid translation.
///
/// This is the *reference* translation for the DOM rendering backend — the
/// alternative to driving xterm.js with ANSI. It deliberately has **no**
/// `dart:js_interop` / `package:web` dependency, so it runs in the plain VM
/// test suite: fidelity (wide graphemes, ZWJ emoji, combining marks, styles)
/// can be asserted deterministically without a browser. The live browser
/// presenter applies this exact same model to real DOM nodes.
///
/// Rendering is driven entirely by [CellRole], so the renderer never re-runs
/// width resolution or grapheme segmentation — the [CellBuffer] already
/// resolved both. Each row becomes a `<div class="r">`; runs of same-style
/// single-width cells coalesce into one `<span>`; a wide (2-column) grapheme
/// becomes its own `class="w2"` span whose width is pinned to `2ch` so the
/// grid can never drift even if the font's natural advance disagrees.
library;

import 'package:fleury/fleury_host.dart';

import 'cell_style_css.dart';

export 'cell_style_css.dart' show kDefaultBackground, kDefaultForeground;

/// The stylesheet the emitted markup relies on. Inject once into the host
/// page (or a `<style>` in the standalone artifact).
const String cellGridCss = '''
.fleury-screen {
  font-family: 'JetBrains Mono', 'SFMono-Regular', 'Menlo', 'Consolas', monospace;
  font-size: 16px;
  line-height: 1.15;
  white-space: pre;
  tab-size: 1;
  font-kerning: none;
  font-variant-ligatures: none;
  font-feature-settings: "liga" 0, "clig" 0;
  letter-spacing: 0;
  background: rgb(30, 30, 30);
  color: rgb(208, 208, 208);
  display: inline-block;
  padding: 10px 12px;
}
.fleury-screen .r { display: block; }
.fleury-screen .w2 { display: inline-block; width: 2ch; overflow: hidden; }
.fleury-screen .proto { display: inline-block; opacity: .7; }
''';

/// Renders a whole [buffer] frame to an HTML string (a stack of row divs).
String renderFrameHtml(CellBuffer buffer) {
  const builder = CellSpanBuilder();
  final out = StringBuffer();
  for (final row in builder.buildFrame(buffer)) {
    out.write('<div class="r">');
    renderRowHtml(row, out);
    out.write('</div>');
  }
  return out.toString();
}

/// Wraps [renderFrameHtml] output in a `.fleury-screen` container.
String renderScreenHtml(CellBuffer buffer) =>
    '<div class="fleury-screen">${renderFrameHtml(buffer)}</div>';

/// Renders a [RowSpanModel] to HTML.
void renderRowHtml(RowSpanModel row, StringBuffer out) {
  for (final run in row.runs) {
    switch (run.kind) {
      case CellRunKind.text:
      case CellRunKind.emptyText:
        _writeTextSpan(run, out);
      case CellRunKind.boxDrawing:
        _writeBoxDrawingSpan(run, out);
      case CellRunKind.wideText:
        _writeWideSpan(run, out);
      case CellRunKind.protocolPlaceholder:
        out
          ..write('<span class="proto" title="')
          ..write(protocolPlaceholderTitle)
          ..write('" ')
          ..write(protocolPlaceholderKindAttribute)
          ..write('="')
          ..write(protocolPlaceholderKind)
          ..write('" ')
          ..write(protocolPlaceholderUnsupportedAttribute)
          ..write('="')
          ..write(protocolPlaceholderUnsupported)
          ..write('">')
          ..write(protocolPlaceholderGlyph)
          ..write('</span>');
    }
  }
}

void _writeTextSpan(CellSpanRun run, StringBuffer out) {
  final css = cellStyleToCss(run.style);
  if (css.isEmpty) {
    out
      ..write('<span>')
      ..write(_escape(run.text))
      ..write('</span>');
  } else {
    out
      ..write('<span style="')
      ..write(css)
      ..write('">')
      ..write(_escape(run.text))
      ..write('</span>');
  }
}

void _writeBoxDrawingSpan(CellSpanRun run, StringBuffer out) {
  final mask = boxDrawingMask(run.text);
  if (mask == null) {
    _writeTextSpan(run, out);
    return;
  }
  // Spaces hold the cells; the line is painted with CSS gradients so the
  // border tiles crisply instead of relying on the (non-tiling) font glyph.
  out
    ..write('<span style="')
    ..write(boxDrawingCss(run.style, mask))
    ..write('">')
    ..write(''.padRight(run.widthCols, ' '))
    ..write('</span>');
}

void _writeWideSpan(CellSpanRun run, StringBuffer out) {
  final css = cellStyleToCss(run.style);
  out.write('<span class="w2"');
  if (css.isNotEmpty) {
    out
      ..write(' style="')
      ..write(css)
      ..write('"');
  }
  out
    ..write('>')
    ..write(_escape(run.text))
    ..write('</span>');
}

String _escape(String s) {
  if (!s.contains('&') && !s.contains('<') && !s.contains('>')) return s;
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
