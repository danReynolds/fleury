import 'package:fleury/fleury.dart';
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
}
