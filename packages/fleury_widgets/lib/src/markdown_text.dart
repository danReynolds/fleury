// MarkdownText — renders a subset of Markdown to a styled cell block.
//
// Scope is deliberately small: the things users want for help screens,
// chat bubbles, agentic-LLM responses, and `--help` output. No HTML
// passthrough, no tables, no images, no nested blockquotes, no MathML.
// Reach for a full Markdown engine (the `markdown` package) when you
// need that — this widget exists so the common case doesn't drag a
// 400 KB parser into your binary for a paragraph of italics + a
// bullet list.
//
// Supported inline syntax:
//   **bold**          bold
//   *italic*  _it_    italic
//   ~~strike~~        strikethrough
//   `code`            monospace + dim background tone
//   [text](url)       underlined; url is shown in dim text afterwards
//
// Supported block syntax:
//   # H1, ## H2, ### H3   bold headings (sized by underline density)
//   - / * bullet           "• " prefix at indent depth
//   1. 2. 3.               "N. " prefix
//   > blockquote           "│ " prefix, dim
//   ```code fence```       monospace block, no inline parsing inside
//   ---                    horizontal rule (dim ─)
//   blank line             paragraph break
//
// Everything else falls through as plain text. The parser is a single
// pass: line-mode for blocks, regex-driven for inline spans. Fast
// enough to render fresh on every frame for short content (the
// common case); for long markdown documents, render once + cache.

import 'package:fleury/fleury.dart';

/// A widget that renders a [data] string of light Markdown as styled
/// terminal cells.
///
/// Use [baseStyle] to set the default cell style for the block
/// (e.g. dim for help text). Inline overrides cascade on top.
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.data, {super.key, this.baseStyle});

  final String data;
  final CellStyle? baseStyle;

  @override
  Widget build(BuildContext context) {
    final lines = _renderBlocks(data, baseStyle ?? CellStyle.empty);
    if (lines.isEmpty) return const EmptyBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }
}

// ---- Block-level pass -----------------------------------------------------

List<Widget> _renderBlocks(String data, CellStyle base) {
  final out = <Widget>[];
  final lines = data.split('\n');
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (line.trim().isEmpty) {
      out.add(const Text(''));
      i++;
      continue;
    }
    // Fenced code block — consume until matching ```.
    if (line.trimLeft().startsWith('```')) {
      i++;
      final codeLines = <String>[];
      while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
        codeLines.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++; // skip closing fence
      for (final c in codeLines) {
        out.add(
          Text(
            c,
            style: base.merge(
              const CellStyle(background: RgbColor(40, 40, 50)),
            ),
          ),
        );
      }
      continue;
    }
    // Horizontal rule.
    if (RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$').hasMatch(line)) {
      out.add(Text('─' * 40, style: base.merge(const CellStyle(dim: true))));
      i++;
      continue;
    }
    // Heading.
    final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line);
    if (heading != null) {
      final level = heading.group(1)!.length;
      final body = heading.group(2)!;
      final hStyle = base.merge(
        CellStyle(
          bold: true,
          // H1 inverts for emphasis; H2/H3 just bold + underline.
          underline: level > 1,
          inverse: level == 1,
        ),
      );
      out.add(RichText(text: _inline(body, hStyle)));
      i++;
      continue;
    }
    // Blockquote.
    if (line.trimLeft().startsWith('> ')) {
      final body = line.trimLeft().substring(2);
      final qStyle = base.merge(const CellStyle(dim: true));
      out.add(
        RichText(
          text: TextSpan(
            style: qStyle,
            children: [
              const TextSpan(text: '│ '),
              _inline(body, qStyle),
            ],
          ),
        ),
      );
      i++;
      continue;
    }
    // Bullet list.
    final bullet = RegExp(r'^(\s*)[-*]\s+(.*)$').firstMatch(line);
    if (bullet != null) {
      final indent = ' ' * bullet.group(1)!.length;
      final body = bullet.group(2)!;
      out.add(
        RichText(
          text: TextSpan(
            style: base,
            children: [
              TextSpan(text: '$indent• '),
              _inline(body, base),
            ],
          ),
        ),
      );
      i++;
      continue;
    }
    // Ordered list.
    final ordered = RegExp(r'^(\s*)(\d+)\.\s+(.*)$').firstMatch(line);
    if (ordered != null) {
      final indent = ' ' * ordered.group(1)!.length;
      final num = ordered.group(2)!;
      final body = ordered.group(3)!;
      out.add(
        RichText(
          text: TextSpan(
            style: base,
            children: [
              TextSpan(text: '$indent$num. '),
              _inline(body, base),
            ],
          ),
        ),
      );
      i++;
      continue;
    }
    // Plain paragraph line.
    out.add(RichText(text: _inline(line, base)));
    i++;
  }
  return out;
}

// ---- Inline pass ----------------------------------------------------------

/// Walks [src] left-to-right, splitting at markup tokens, and emits a
/// [TextSpan] tree under [base]. Greedy: longest tokens win at each
/// position. Unbalanced markup is left as literal text (no escape
/// sequences corrupt the render).
TextSpan _inline(String src, CellStyle base) {
  final children = <TextSpan>[];
  var i = 0;
  final buf = StringBuffer();

  void flushText() {
    if (buf.isEmpty) return;
    children.add(TextSpan(text: buf.toString()));
    buf.clear();
  }

  while (i < src.length) {
    final ch = src[i];

    // Inline code: `…`
    if (ch == '`') {
      final end = src.indexOf('`', i + 1);
      if (end > i) {
        flushText();
        children.add(
          TextSpan(
            text: src.substring(i + 1, end),
            style: base.merge(
              const CellStyle(background: RgbColor(45, 45, 55)),
            ),
          ),
        );
        i = end + 1;
        continue;
      }
    }
    // Bold: **…**
    if (ch == '*' && i + 1 < src.length && src[i + 1] == '*') {
      final end = src.indexOf('**', i + 2);
      if (end > i) {
        flushText();
        children.add(
          TextSpan(
            text: src.substring(i + 2, end),
            style: base.merge(const CellStyle(bold: true)),
          ),
        );
        i = end + 2;
        continue;
      }
    }
    // Strikethrough: ~~…~~
    if (ch == '~' && i + 1 < src.length && src[i + 1] == '~') {
      final end = src.indexOf('~~', i + 2);
      if (end > i) {
        flushText();
        children.add(
          TextSpan(
            text: src.substring(i + 2, end),
            style: base.merge(const CellStyle(strikethrough: true)),
          ),
        );
        i = end + 2;
        continue;
      }
    }
    // Italic: *…* OR _…_ (single delimiter; greedy until matching one).
    if (ch == '*' || ch == '_') {
      // Avoid double-* here (handled above).
      final end = src.indexOf(ch, i + 1);
      if (end > i) {
        flushText();
        children.add(
          TextSpan(
            text: src.substring(i + 1, end),
            style: base.merge(const CellStyle(italic: true)),
          ),
        );
        i = end + 1;
        continue;
      }
    }
    // Link: [text](url) — render text underlined, then "(url)" dim.
    if (ch == '[') {
      final closeBracket = src.indexOf(']', i + 1);
      if (closeBracket > i &&
          closeBracket + 1 < src.length &&
          src[closeBracket + 1] == '(') {
        final closeParen = src.indexOf(')', closeBracket + 2);
        if (closeParen > closeBracket) {
          flushText();
          final text = src.substring(i + 1, closeBracket);
          final url = src.substring(closeBracket + 2, closeParen);
          children.add(
            TextSpan(
              text: text,
              style: base.merge(const CellStyle(underline: true)),
            ),
          );
          children.add(
            TextSpan(
              text: ' ($url)',
              style: base.merge(const CellStyle(dim: true)),
            ),
          );
          i = closeParen + 1;
          continue;
        }
      }
    }
    buf.write(ch);
    i++;
  }
  flushText();
  if (children.length == 1) {
    return TextSpan(text: children.first.text, style: base);
  }
  return TextSpan(style: base, children: children);
}
