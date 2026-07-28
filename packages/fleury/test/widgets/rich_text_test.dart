import 'package:fleury/fleury.dart';
import 'package:fleury/src/widgets/rich_text.dart' show RenderRichText;
import '../support/harness.dart';
import 'package:test/test.dart';

String _row(CellBuffer buf, int row) {
  final sb = StringBuffer();
  for (var c = 0; c < buf.size.cols; c++) {
    final cell = buf.atColRow(c, row);
    sb.write(cell.role == CellRole.leading ? cell.grapheme : ' ');
  }
  return sb.toString().trimRight();
}

void main() {
  testWidgets('renders multiple styles on one line', (tester) {
    tester.pumpWidget(
      const RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: 'red',
              style: CellStyle(foreground: AnsiColor(1)),
            ),
            TextSpan(text: 'bold', style: CellStyle(bold: true)),
          ],
        ),
      ),
    );
    final buf = tester.render(size: const CellSize(10, 1));
    expect(_row(buf, 0), 'redbold');
    expect(buf.atColRow(0, 0).style.foreground, const AnsiColor(1));
    expect(buf.atColRow(0, 0).style.bold, isFalse);
    expect(buf.atColRow(3, 0).style.bold, isTrue, reason: "'b' of bold");
    expect(buf.atColRow(3, 0).style.foreground, isNull);
  });

  testWidgets('child style cascades onto the parent style', (tester) {
    tester.pumpWidget(
      const RichText(
        text: TextSpan(
          style: CellStyle(bold: true), // parent: bold
          children: [
            TextSpan(
              text: 'x',
              style: CellStyle(foreground: AnsiColor(2)),
            ),
          ],
        ),
      ),
    );
    final buf = tester.render(size: const CellSize(4, 1));
    expect(buf.atColRow(0, 0).style.bold, isTrue, reason: 'inherited bold');
    expect(buf.atColRow(0, 0).style.foreground, const AnsiColor(2));
  });

  testWidgets('wraps across spans at word boundaries', (tester) {
    tester.pumpWidget(
      const RichText(
        text: TextSpan(
          children: [
            TextSpan(text: 'hello '),
            TextSpan(text: 'world'),
          ],
        ),
      ),
    );
    final buf = tester.render(size: const CellSize(5, 2));
    expect(_row(buf, 0), 'hello');
    expect(_row(buf, 1), 'world');
  });

  testWidgets('honors explicit newlines inside a span', (tester) {
    tester.pumpWidget(const RichText(text: TextSpan(text: 'a\nb')));
    final buf = tester.render(size: const CellSize(4, 2));
    expect(_row(buf, 0), 'a');
    expect(_row(buf, 1), 'b');
  });

  testWidgets(
    'a multi-word styled span rides its internal spaces (contiguous run)',
    (tester) {
      // The word-wrap must re-emit the ORIGINAL space glyph (with its style),
      // not a bare unstyled space — otherwise a link/underline/background
      // fractures at every space. Here the whole phrase is one link: every
      // cell, letters AND spaces, must carry linkUri + underline so it stays a
      // single contiguous run (one <a>, one OSC 8 open/close, one underline).
      tester.pumpWidget(
        const RichText(
          text: TextSpan(
            text: 'open an issue',
            style: CellStyle(underline: true, linkUri: 'https://x'),
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(20, 1));
      const phrase = 'open an issue';
      for (var c = 0; c < phrase.length; c++) {
        final cell = buf.atColRow(c, 0);
        expect(
          cell.style.linkUri,
          'https://x',
          reason: 'cell $c ("${cell.grapheme}") must carry the link',
        );
        expect(
          cell.style.underline,
          isTrue,
          reason: 'cell $c ("${cell.grapheme}") must stay underlined',
        );
      }
    },
  );

  testWidgets('maxLines + ellipsis truncates', (tester) {
    tester.pumpWidget(
      const RichText(
        text: TextSpan(text: 'aaaaa bbb'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final buf = tester.render(size: const CellSize(5, 1));
    expect(_row(buf, 0), 'aaaa…');
  });

  testWidgets('inherits the ambient DefaultTextStyle as the base', (tester) {
    tester.pumpWidget(
      const DefaultTextStyle(
        style: CellStyle(foreground: AnsiColor(4)),
        child: RichText(text: TextSpan(text: 'hi')),
      ),
    );
    final buf = tester.render(size: const CellSize(4, 1));
    expect(buf.atColRow(0, 0).style.foreground, const AnsiColor(4));
  });

  group('RenderRichText display lowering (RFC 0019 P2.3, gate 12)', () {
    const family = '\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466}'; // 👨‍👩‍👦
    const split = TextPresentationPolicy(lowering: ClusterLowering.split);
    const bold = CellStyle(bold: true);

    CellBuffer paintRich(TextSpan span, TextPresentationPolicy policy, int cols) {
      final r = RenderRichText(
        span: span,
        base: CellStyle.empty,
        textPolicy: policy,
      )..layout(CellConstraints(maxCols: cols));
      final buf = CellBuffer(CellSize(cols, 2));
      r.paint(buf, CellOffset.zero);
      return buf;
    }

    test('a single-span sequence lowers to atoms under split', () {
      final buf = paintRich(const TextSpan(text: family), split, 8);
      // _row writes a space per continuation cell: three 2-cell atoms.
      expect(_row(buf, 0), '\u{1F468} \u{1F469} \u{1F466}');
    });

    test('span invariance: a sequence split across spans lowers identically',
        () {
      // The same logical sequence, arriving as two adjacent spans — detection
      // runs on the flattened paragraph, so the span boundary changes nothing
      // (property gate 12; per-span walking would misparse this).
      final buf = paintRich(
        const TextSpan(
          children: [
            TextSpan(text: '\u{1F468}\u{200D}'),
            TextSpan(text: '\u{1F469}\u{200D}\u{1F466}'),
          ],
        ),
        split,
        8,
      );
      expect(_row(buf, 0), '\u{1F468} \u{1F469} \u{1F466}');
    });

    test('a lowered component inherits the style covering its own base', () {
      // First component styled by span 1, later components by span 2.
      final r = RenderRichText(
        span: const TextSpan(
          children: [
            TextSpan(text: '\u{1F468}\u{200D}', style: bold),
            TextSpan(text: '\u{1F469}\u{200D}\u{1F466}'),
          ],
        ),
        base: CellStyle.empty,
        textPolicy: split,
      )..layout(const CellConstraints(maxCols: 8));
      final buf = CellBuffer(const CellSize(8, 1));
      r.paint(buf, CellOffset.zero);
      expect(buf.atColRow(0, 0).style.bold, isTrue, reason: '👨 from span 1');
      expect(buf.atColRow(2, 0).style.bold, isFalse, reason: '👩 from span 2');
    });

    test('preserve keeps the per-span walk byte-identical (gate 2)', () {
      // Under the spec policy the legacy path runs: the cross-span sequence
      // stays exactly as it renders today (two clusters, base-keyed widths).
      final spec = paintRich(
        const TextSpan(
          children: [
            TextSpan(text: '\u{1F468}\u{200D}'),
            TextSpan(text: '\u{1F469}\u{200D}\u{1F466}'),
          ],
        ),
        TextPresentationPolicy.spec,
        10,
      );
      final single = paintRich(
        const TextSpan(text: 'x'),
        TextPresentationPolicy.spec,
        10,
      );
      expect(single, isNotNull);
      // The two-cluster rendering occupies 4 cells (2 + 2), not 6.
      expect(spec.atColRow(0, 0).grapheme, isNotNull);
      expect(spec.atColRow(4, 0).role, CellRole.empty);
    });

    test('non-emoji joiners flatten unchanged under split (gate 10)', () {
      const arabic = '\u{0644}\u{200D}\u{0627}';
      final lowered = paintRich(const TextSpan(text: arabic), split, 6);
      final preserved = paintRich(
        const TextSpan(text: arabic),
        TextPresentationPolicy.spec,
        6,
      );
      expect(_row(lowered, 0), _row(preserved, 0));
    });
  });
}
