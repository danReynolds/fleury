import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

LogBuffer _buffer(List<String> lines, {LogSource source = LogSource.stdout}) {
  final b = LogBuffer();
  for (final l in lines) {
    b.add(LogLine(l, source));
  }
  return b;
}

void main() {
  group('LogView', () {
    testWidgets('tails to the most recent lines that fit', (tester) {
      final b = _buffer(['one', 'two', 'three', 'four']);
      tester.pumpWidget(
        SizedBox(width: 10, height: 2, child: LogView(buffer: b)),
      );
      final out = tester.renderToString(size: const CellSize(10, 2));
      expect(out.contains('three'), isTrue);
      expect(out.contains('four'), isTrue);
      expect(out.contains('one'), isFalse, reason: 'scrolled off the top');
    });

    testWidgets('renders nothing when empty', (tester) {
      tester.pumpWidget(
        SizedBox(width: 10, height: 2, child: LogView(buffer: LogBuffer())),
      );
      expect(tester.renderToString(size: const CellSize(10, 2)).trim(), '');
    });

    testWidgets('rebuilds as new lines arrive', (tester) {
      final b = LogBuffer();
      tester.pumpWidget(
        SizedBox(width: 10, height: 2, child: LogView(buffer: b)),
      );
      b.add(const LogLine('live', LogSource.stdout));
      tester.pump();
      expect(
        tester.renderToString(size: const CellSize(10, 2)).contains('live'),
        isTrue,
      );
    });

    testWidgets('stderr lines take the error color', (tester) {
      final b = _buffer(['boom'], source: LogSource.stderr);
      tester.pumpWidget(
        Theme(
          data: const ThemeData(),
          child: SizedBox(width: 10, height: 1, child: LogView(buffer: b)),
        ),
      );
      final buf = tester.render(size: const CellSize(10, 1));
      expect(buf.atColRow(0, 0).style.foreground, ColorScheme.standard.error);
    });

    testWidgets('reads its buffer from a LogBufferScope', (tester) {
      final b = _buffer(['scoped']);
      tester.pumpWidget(
        LogBufferScope(
          buffer: b,
          child: const SizedBox(width: 10, height: 1, child: LogView()),
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(10, 1)).contains('scoped'),
        isTrue,
      );
    });
  });

  group('LogConsole', () {
    testWidgets('shows recent lines in a panel pinned to the bottom', (tester) {
      final b = _buffer(['hello-log']);
      tester.pumpWidget(
        LogBufferScope(
          buffer: b,
          child: const LogConsole(height: 6, toggleHint: 'F12'),
        ),
      );
      final out = tester.renderToString(size: const CellSize(24, 10));
      expect(out.contains('hello-log'), isTrue);
      expect(out.contains('console'), isTrue, reason: 'header title');
      expect(out.contains('F12 to hide'), isTrue, reason: 'footer hint');
      final rows = out.split('\n');
      expect(rows.first.trim(), isEmpty, reason: 'panel hugs the bottom');
    });

    testWidgets('is opaque — content beneath does not bleed through', (tester) {
      final b = _buffer(['x']);
      tester.pumpWidget(
        LogBufferScope(
          buffer: b,
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (c, cc) => Column(
                  children: [
                    for (var i = 0; i < (cc.maxRows ?? 0); i++)
                      Text('#' * (cc.maxCols ?? 0)),
                  ],
                ),
              ),
              const LogConsole(height: 6),
            ],
          ),
        ),
      );
      final rows = tester
          .renderToString(size: const CellSize(20, 10))
          .split('\n');
      final panelInterior = rows.where((r) => r.contains('│')).toList();
      expect(panelInterior, isNotEmpty);
      expect(
        panelInterior.every((r) => !r.contains('#')),
        isTrue,
        reason: 'the panel paints every cell — nothing bleeds through',
      );
    });

    testWidgets('shows an empty state', (tester) {
      tester.pumpWidget(
        LogBufferScope(buffer: LogBuffer(), child: const LogConsole(height: 6)),
      );
      expect(
        tester
            .renderToString(size: const CellSize(24, 10))
            .contains('no output yet'),
        isTrue,
      );
    });

    testWidgets('stderr lines are tagged and colored', (tester) {
      final b = _buffer(['boom'], source: LogSource.stderr);
      tester.pumpWidget(
        Theme(
          data: const ThemeData(),
          child: LogBufferScope(buffer: b, child: const LogConsole(height: 6)),
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(24, 10)).contains('● boom'),
        isTrue,
        reason: 'stderr gets a distinct gutter glyph',
      );
      final buf = tester.render(size: const CellSize(24, 10));
      Color? gutterColor;
      for (var r = 0; r < 10 && gutterColor == null; r++) {
        for (var c = 0; c < 24; c++) {
          if (buf.atColRow(c, r).grapheme == '●') {
            gutterColor = buf.atColRow(c, r).style.foreground;
            break;
          }
        }
      }
      expect(gutterColor, ColorScheme.standard.error);
    });
  });
}
