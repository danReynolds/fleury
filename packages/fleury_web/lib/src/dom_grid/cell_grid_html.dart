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

import 'package:fleury/fleury_core.dart';

/// Default foreground/background used when a cell leaves them unset (and as
/// the swap targets for `inverse`). Match these to the host page's theme.
const RgbColor kDefaultForeground = RgbColor(208, 208, 208);
const RgbColor kDefaultBackground = RgbColor(30, 30, 30);

/// The stylesheet the emitted markup relies on. Inject once into the host
/// page (or a `<style>` in the standalone artifact).
const String cellGridCss = '''
.fleury-screen {
  font-family: 'JetBrains Mono', 'SFMono-Regular', 'Menlo', 'Consolas', monospace;
  font-size: 16px;
  line-height: 1.15;
  white-space: pre;
  background: rgb(30, 30, 30);
  color: rgb(208, 208, 208);
  display: inline-block;
  padding: 10px 12px;
  tab-size: 1;
}
.fleury-screen .r { display: block; }
.fleury-screen .w2 { display: inline-block; width: 2ch; overflow: hidden; }
.fleury-screen .proto { display: inline-block; opacity: .7; }
''';

/// Renders a whole [buffer] frame to an HTML string (a stack of row divs).
String renderFrameHtml(CellBuffer buffer) {
  final cols = buffer.size.cols;
  final rows = buffer.size.rows;
  final out = StringBuffer();
  for (var row = 0; row < rows; row++) {
    out.write('<div class="r">');
    _renderRow(buffer, row, cols, out);
    out.write('</div>');
  }
  return out.toString();
}

/// Wraps [renderFrameHtml] output in a `.fleury-screen` container.
String renderScreenHtml(CellBuffer buffer) =>
    '<div class="fleury-screen">${renderFrameHtml(buffer)}</div>';

void _renderRow(CellBuffer buffer, int row, int cols, StringBuffer out) {
  final runText = StringBuffer();
  CellStyle? runStyle;

  void flushRun() {
    if (runText.isEmpty) {
      runStyle = null;
      return;
    }
    final css = _styleToCss(runStyle ?? CellStyle.empty);
    if (css.isEmpty) {
      out
        ..write('<span>')
        ..write(runText)
        ..write('</span>');
    } else {
      out
        ..write('<span style="')
        ..write(css)
        ..write('">')
        ..write(runText)
        ..write('</span>');
    }
    runText.clear();
    runStyle = null;
  }

  var col = 0;
  while (col < cols) {
    final cell = buffer.atColRow(col, row);
    final role = cell.role;

    if (role == CellRole.empty) {
      // A blank cell is one space of the default style. Coalesce with a
      // running default-style span; otherwise flush first.
      if (runStyle != null && runStyle != CellStyle.empty) flushRun();
      runStyle = CellStyle.empty;
      runText.write(' ');
      col += 1;
    } else if (role == CellRole.continuation) {
      // The trailing half of a wide grapheme — already drawn by its leading
      // cell. Emit nothing.
      col += 1;
    } else if (role == CellRole.leading) {
      final wide =
          col + 1 < cols &&
          buffer.atColRow(col + 1, row).role == CellRole.continuation;
      if (wide) {
        flushRun();
        final css = _styleToCss(cell.style);
        out.write('<span class="w2"');
        if (css.isNotEmpty) {
          out
            ..write(' style="')
            ..write(css)
            ..write('"');
        }
        out
          ..write('>')
          ..write(_escape(cell.grapheme!))
          ..write('</span>');
        col += 1; // the continuation cell is skipped on the next iteration
      } else {
        if (runStyle != null && runStyle != cell.style) flushRun();
        runStyle = cell.style;
        runText.write(_escape(cell.grapheme!));
        col += 1;
      }
    } else if (role == CellRole.protocolAnchor) {
      // Inline-image protocol region (Kitty/Sixel/iTerm2). Not yet decoded
      // in the spike — emit a visible placeholder so the grid stays aligned.
      flushRun();
      out.write('<span class="proto" title="inline image">▩</span>');
      col += 1;
    } else {
      // protocolCovered — owned by its anchor, draw nothing.
      col += 1;
    }
  }
  flushRun();
}

String _styleToCss(CellStyle style) {
  Color? fg = style.foreground;
  Color? bg = style.background;
  if (style.inverse) {
    final swappedFg = bg ?? kDefaultBackground;
    final swappedBg = fg ?? kDefaultForeground;
    fg = swappedFg;
    bg = swappedBg;
  }

  final parts = <String>[];
  if (fg != null) parts.add('color:${_rgb(fg)}');
  if (bg != null) parts.add('background-color:${_rgb(bg)}');
  if (style.bold) parts.add('font-weight:700');
  if (style.dim) parts.add('opacity:.6');
  if (style.italic) parts.add('font-style:italic');
  final decorations = <String>[
    if (style.underline) 'underline',
    if (style.strikethrough) 'line-through',
  ];
  if (decorations.isNotEmpty) {
    parts.add('text-decoration:${decorations.join(' ')}');
  }
  return parts.join(';');
}

String _rgb(Color color) {
  final c = color.toRgb();
  return 'rgb(${c.r}, ${c.g}, ${c.b})';
}

String _escape(String s) {
  if (!s.contains('&') && !s.contains('<') && !s.contains('>')) return s;
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
