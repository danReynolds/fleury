import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

/// Returns a single-row string of the cells in [row] of [buffer], using
/// ASCII for grapheme content, '·' for empty cells, and '+' for any
/// orphaned continuation cells (which should never appear in valid
/// output).
String _rowContent(CellBuffer buffer, int row) {
  final buf = StringBuffer();
  for (var col = 0; col < buffer.size.cols; col++) {
    final cell = buffer.atColRow(col, row);
    switch (cell.role) {
      case CellRole.empty:
        buf.write('·');
      case CellRole.leading:
        buf.write(cell.grapheme);
      case CellRole.continuation:
      case CellRole.overlay:
        // Continuation cells contribute no character of their own; the
        // leading cell's grapheme already accounts for both columns.
        break;
    }
  }
  return buf.toString();
}

void main() {
  group('RenderText layout', () {
    test('intrinsic width matches widthResolver for ASCII', () {
      final t = RenderText(text: 'hello');
      expect(t.intrinsicWidth, 5);
    });

    test('intrinsic width measures wide graphemes as 2 columns', () {
      final t = RenderText(text: 'hi 中文');
      // h(1) + i(1) + ' '(1) + 中(2) + 文(2) = 7
      expect(t.intrinsicWidth, 7);
    });

    test('layout returns size at intrinsic width when unbounded', () {
      final t = RenderText(text: 'abc');
      final size = t.layout(const CellConstraints());
      expect(size, const CellSize(3, 1));
    });

    test('layout clips to maxCols when softWrap is off', () {
      final t = RenderText(text: 'hello world', softWrap: false);
      final size = t.layout(const CellConstraints(maxCols: 5));
      expect(size, const CellSize(5, 1));
    });

    test('layout reports zero size for empty text', () {
      final t = RenderText(text: '');
      final size = t.layout(const CellConstraints(maxCols: 10, maxRows: 5));
      expect(size, const CellSize(0, 0));
    });
  });

  group('RenderText paint', () {
    test('writes ASCII into buffer at the given offset', () {
      final t = RenderText(text: 'abc')..layout(const CellConstraints());
      final buf = CellBuffer(const CellSize(5, 1));
      t.paint(buf, const CellOffset(1, 0));
      expect(_rowContent(buf, 0), '·abc·');
    });

    test('writes wide graphemes as leading + continuation', () {
      final t = RenderText(text: '中文')..layout(const CellConstraints());
      final buf = CellBuffer(const CellSize(5, 1));
      t.paint(buf, CellOffset.zero);
      // '中' leading at 0, continuation at 1, '文' leading at 2,
      // continuation at 3, empty at 4.
      expect(buf.atColRow(0, 0).grapheme, '中');
      expect(buf.atColRow(1, 0).role, CellRole.continuation);
      expect(buf.atColRow(2, 0).grapheme, '文');
      expect(buf.atColRow(3, 0).role, CellRole.continuation);
      expect(buf.atColRow(4, 0).role, CellRole.empty);
    });

    test('sanitizes ESC and other control bytes before painting', () {
      // Classic terminal hijack attempt: ESC + clear-screen sequence.
      final t = RenderText(text: 'a\x1B[2Jb')..layout(const CellConstraints());
      final buf = CellBuffer(const CellSize(10, 1));
      t.paint(buf, CellOffset.zero);
      // The string is sanitized once at construction; the full CSI sequence
      // collapses to U+FFFD so active terminal parameters are not displayed.
      final cells = <String>[];
      for (var col = 0; col < buf.size.cols; col++) {
        final c = buf.atColRow(col, 0);
        if (c.role == CellRole.leading) cells.add(c.grapheme!);
      }
      expect(cells.length, 3);
      expect(cells[0], 'a');
      expect(cells[1], replacementCharacter);
      expect(cells[2], 'b');
    });

    test('respects layout width when content overflows (no wrap)', () {
      final t = RenderText(text: 'abcdef', softWrap: false)
        ..layout(const CellConstraints(maxCols: 3));
      final buf = CellBuffer(const CellSize(6, 1));
      t.paint(buf, CellOffset.zero);
      expect(_rowContent(buf, 0), 'abc···');
    });
  });

  group('RenderText soft wrap', () {
    test('breaks on word boundary when text exceeds maxCols', () {
      final t = RenderText(text: 'hello world');
      final size = t.layout(const CellConstraints(maxCols: 5));
      expect(size, const CellSize(5, 2));
    });

    test('paints each wrapped line on its own row', () {
      final t = RenderText(text: 'hello world')
        ..layout(const CellConstraints(maxCols: 5));
      final buf = CellBuffer(const CellSize(5, 2));
      t.paint(buf, CellOffset.zero);
      expect(_rowContent(buf, 0), 'hello');
      expect(_rowContent(buf, 1), 'world');
    });

    test('hard-breaks a word longer than maxCols', () {
      final t = RenderText(text: 'abcdefghij');
      final size = t.layout(const CellConstraints(maxCols: 4));
      expect(size.cols, 4);
      expect(size.rows, 3); // abcd / efgh / ij
    });

    test('honors explicit newlines as forced breaks', () {
      final t = RenderText(text: 'foo\nbar');
      final size = t.layout(const CellConstraints(maxCols: 10));
      expect(size, const CellSize(3, 2));
    });

    test('preserves the wider line when wrapping yields uneven widths', () {
      // "hi there" with maxCols=5 wraps to "hi" / "there"; the wider
      // line is "there" at 5, so the box is 5x2.
      final t = RenderText(text: 'hi there');
      final size = t.layout(const CellConstraints(maxCols: 5));
      expect(size, const CellSize(5, 2));
    });

    test('no-op when intrinsic width fits in maxCols', () {
      final t = RenderText(text: 'hi');
      final size = t.layout(const CellConstraints(maxCols: 10));
      expect(size, const CellSize(2, 1));
    });
  });

  group('RenderText updates', () {
    test('setting text re-sanitizes and recomputes intrinsic width', () {
      final t = RenderText(text: 'a');
      expect(t.intrinsicWidth, 1);
      t.text = 'hello';
      expect(t.intrinsicWidth, 5);
      t.text = 'hello'; // identity should be cheap (no work).
      expect(t.intrinsicWidth, 5);
    });

    test('setting style does not change intrinsic width', () {
      final t = RenderText(text: 'abc');
      final beforeWidth = t.intrinsicWidth;
      t.style = const CellStyle(bold: true);
      expect(t.intrinsicWidth, beforeWidth);
    });

    test('setting style reuses same-constraint layout cache', () {
      final t = RenderText(text: 'abc')
        ..layout(const CellConstraints(maxCols: 10));

      RenderLayoutDebugStats.beginFrame(enabled: true);
      t.style = const CellStyle(bold: true);
      expect(
        t.layout(const CellConstraints(maxCols: 10)),
        const CellSize(3, 1),
      );
      final stats = RenderLayoutDebugStats.takeFrameStats();

      expect(stats.performedCount, 0);
      expect(stats.skippedCount, 1);
    });

    test('widget style update preserves same-constraint layout cache', () {
      final tester = FleuryTester(viewportSize: const CellSize(20, 3));
      addTearDown(tester.dispose);

      tester.pumpWidget(const Text('abc'));
      tester.render();

      tester.pumpWidget(const Text('abc', style: CellStyle(bold: true)));
      RenderLayoutDebugStats.beginFrame(enabled: true);
      tester.render();
      final stats = RenderLayoutDebugStats.takeFrameStats();

      expect(stats.performedCount, 0);
      expect(stats.skippedCount, greaterThan(0));
    });

    test('same-width no-wrap text update preserves layout cache', () {
      final t = RenderText(text: 'abc', softWrap: false)
        ..layout(const CellConstraints(maxCols: 3));

      RenderLayoutDebugStats.beginFrame(enabled: true);
      t.text = 'xyz';
      expect(t.layout(const CellConstraints(maxCols: 3)), const CellSize(3, 1));
      final stats = RenderLayoutDebugStats.takeFrameStats();

      final buf = CellBuffer(const CellSize(3, 1));
      t.paint(buf, CellOffset.zero);
      expect(_rowContent(buf, 0), 'xyz');
      expect(stats.performedCount, 0);
      expect(stats.skippedCount, 1);
    });

    test('same-width soft-wrap text update preserves cache when it fits', () {
      final t = RenderText(text: 'abc')
        ..layout(const CellConstraints(maxCols: 5));

      RenderLayoutDebugStats.beginFrame(enabled: true);
      t.text = 'xyz';
      expect(t.layout(const CellConstraints(maxCols: 5)), const CellSize(3, 1));
      final stats = RenderLayoutDebugStats.takeFrameStats();

      expect(stats.performedCount, 0);
      expect(stats.skippedCount, 1);
    });

    test('same-width wrapping text update still relayouts', () {
      final t = RenderText(text: 'aa aa')
        ..layout(const CellConstraints(maxCols: 2));

      RenderLayoutDebugStats.beginFrame(enabled: true);
      t.text = 'bb bb';
      expect(t.layout(const CellConstraints(maxCols: 2)), const CellSize(2, 2));
      final stats = RenderLayoutDebugStats.takeFrameStats();

      expect(stats.performedCount, 1);
      expect(stats.skippedCount, 0);
    });

    test('style update under multi-child rebuild preserves layout cache', () {
      final tester = FleuryTester(viewportSize: const CellSize(20, 3));
      final model = _StyleToggleModel();
      addTearDown(tester.dispose);
      addTearDown(model.dispose);

      tester.pumpWidget(
        ListenableBuilder(
          listenable: model,
          builder: (context, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'abc',
                  style: model.accent
                      ? const CellStyle(bold: true)
                      : CellStyle.empty,
                ),
                const Text('steady'),
              ],
            );
          },
        ),
      );
      tester.render();

      model.toggle();
      RenderLayoutDebugStats.beginFrame(enabled: true);
      tester.render();
      final stats = RenderLayoutDebugStats.takeFrameStats();

      expect(stats.performedCount, 0);
      expect(stats.skippedCount, greaterThan(0));
    });

    test('setting profile re-measures', () {
      final t = RenderText(text: '─');
      // Default profile: box-drawing is ambiguous → narrow.
      expect(t.intrinsicWidth, 1);
      t.profile = TerminalProfile.cjk;
      expect(t.intrinsicWidth, 2);
    });
  });

  group('RenderText layout cache invalidation', () {
    test('layout result reflects text change', () {
      final t = RenderText(text: 'hello world');
      final size1 = t.layout(const CellConstraints(maxCols: 5));
      expect(size1, const CellSize(5, 2));
      t.text = 'hi';
      final size2 = t.layout(const CellConstraints(maxCols: 5));
      expect(size2, const CellSize(2, 1));
    });

    test('layout result reflects constraint change', () {
      final t = RenderText(text: 'hello world');
      final wide = t.layout(const CellConstraints(maxCols: 100));
      expect(wide, const CellSize(11, 1));
      final narrow = t.layout(const CellConstraints(maxCols: 5));
      expect(narrow, const CellSize(5, 2));
    });

    test('layout result reflects softWrap change', () {
      final t = RenderText(text: 'hello world');
      final wrapped = t.layout(const CellConstraints(maxCols: 5));
      expect(wrapped, const CellSize(5, 2));
      t.softWrap = false;
      final clipped = t.layout(const CellConstraints(maxCols: 5));
      expect(clipped, const CellSize(5, 1));
    });
  });

  group('maxLines + overflow', () {
    test('maxLines caps the laid-out height', () {
      final t = RenderText(text: 'one two three four five', maxLines: 2);
      final size = t.layout(const CellConstraints(maxCols: 5));
      expect(size.rows, 2);
    });

    test('ellipsis truncates a too-wide single line', () {
      final t = RenderText(
        text: 'abcdefgh',
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );
      t.layout(const CellConstraints(maxCols: 5));
      final buf = CellBuffer(const CellSize(5, 1));
      t.paint(buf, CellOffset.zero);
      expect(_rowContent(buf, 0), 'abcd…');
    });

    test('clip (default) leaves no ellipsis', () {
      final t = RenderText(text: 'abcdefgh', softWrap: false);
      t.layout(const CellConstraints(maxCols: 5));
      final buf = CellBuffer(const CellSize(5, 1));
      t.paint(buf, CellOffset.zero);
      expect(_rowContent(buf, 0), 'abcde');
    });

    test('ellipsis marks the last line when maxLines drops content', () {
      final t = RenderText(
        text: 'aaaaa bbb', // 'aaaaa' fills a 5-wide line; 'bbb' wraps below
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      t.layout(const CellConstraints(maxCols: 5));
      final buf = CellBuffer(const CellSize(5, 1));
      t.paint(buf, CellOffset.zero);
      // Content remains below the single kept line, so it ellipsizes.
      expect(_rowContent(buf, 0), 'aaaa…');
    });
  });
}

final class _StyleToggleModel extends ChangeNotifier {
  var _accent = false;

  bool get accent => _accent;

  void toggle() {
    _accent = !_accent;
    notifyListeners();
  }
}
