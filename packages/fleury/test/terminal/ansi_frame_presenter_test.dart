import 'package:fleury/src/debug/debug_state.dart';
import 'package:fleury/src/foundation/geometry.dart';
import 'package:fleury/src/rendering/ansi_render_target.dart';
import 'package:fleury/src/rendering/ansi_renderer.dart';
import 'package:fleury/src/rendering/render_layout_stats.dart';
import 'package:fleury/src/rendering/render_repaint_boundary.dart';
import 'package:fleury/src/runtime/frame_driver.dart';
import 'package:fleury/src/runtime/tui_frame_loop.dart';
import 'package:fleury/src/terminal/ansi_frame_presenter.dart';
import 'package:fleury/src/terminal/capabilities.dart';
import 'package:fleury/src/terminal/terminal_image_encoder.dart';
import 'package:test/test.dart';

void main() {
  const size = CellSize(5, 3);
  const info = FramePresentInfo(
    reason: 'test',
    plan: null,
    debugWatching: false,
    layoutStats: RenderLayoutFrameStats.empty,
    repaintBoundaryStats: RepaintBoundaryFrameStats.empty,
  );

  group('inline presentation', () {
    test('clear, text and clamped caret share the same row offset', () {
      final sink = StringAnsiSink();
      final presenter = AnsiFramePresenter(
        sink: sink,
        renderer: const AnsiRenderer(),
        debug: DebugController(const DebugConfig(enabled: false)),
        readTarget: () => const AnsiRenderTarget.inline(top: 6),
        readCaret: () => CellRect.fromLTWH(50, 50, 1, 1),
      );
      presenter.presentFrame(_frame(size), info);
      expect(sink.output, isNot(contains('\x1B[2J')));
      expect(sink.output, isNot(contains('\x1B[H')));
      expect(sink.output, contains('\x1B[7Hhello'));
      expect(sink.output, endsWith('\x1B[9;5H'));
      _expectOnlyRows(sink.output, top: 6, rows: 3);
    });

    test('a relocated region repaints even when the frame is unchanged', () {
      final sink = StringAnsiSink();
      var top = 2;
      var reads = 0;
      final presenter = AnsiFramePresenter(
        sink: sink,
        renderer: const AnsiRenderer(),
        debug: DebugController(const DebugConfig(enabled: false)),
        readTarget: () {
          reads++;
          return AnsiRenderTarget.inline(top: top);
        },
      );
      final loop = TuiFrameLoop();
      final first = _frameFrom(loop, size);
      presenter.presentFrame(first, info);
      loop.commit(first);
      sink.clear();
      top = 8;

      final relocated = _frameFrom(loop, size);
      expect(relocated.damage, isA<FrameUnchanged>());
      presenter.presentFrame(relocated, info);
      expect(reads, 2, reason: 'one target snapshot per frame');
      expect(sink.output, contains('\x1B[9Hhello'));
      _expectOnlyRows(sink.output, top: 8, rows: 3);
      expect(relocated.previous.atColRow(0, 0).grapheme, 'h');
      loop.commit(relocated);
      sink.clear();

      presenter.presentFrame(_frameFrom(loop, size), info);
      expect(sink.output, isEmpty);
    });

    test('FrameScrolled patches cells within the inline region', () {
      final sink = StringAnsiSink();
      final presenter = AnsiFramePresenter(
        sink: sink,
        renderer: const AnsiRenderer(),
        debug: DebugController(const DebugConfig(enabled: false)),
        readTarget: () => const AnsiRenderTarget.inline(top: 4),
      );
      final loop = TuiFrameLoop();
      TuiRenderedFrame paint(int start) => loop.render(
        size: const CellSize(20, 10),
        paint: (buffer) {
          for (var row = 0; row < 10; row++) {
            buffer.writeText(
              CellOffset(0, row),
              String.fromCharCode(65 + start + row) * 12,
            );
          }
        },
      )!;
      final first = paint(0);
      presenter.presentFrame(first, info);
      loop.commit(first);
      sink.clear();

      final scrolled = paint(1);
      expect(scrolled.damage, isA<FrameScrolled>());
      presenter.presentFrame(scrolled, info);
      expect(sink.output, isNot(matches(RegExp(r'\x1b\[\d*S'))));
      expect(sink.output, contains('BBBBBBBBBBBB'));
      _expectOnlyRows(sink.output, top: 4, rows: 10);
    });

    test('paint flash and removing its tint stay in the region', () {
      final sink = StringAnsiSink();
      final debug = DebugController(const DebugConfig(enabled: true));
      addTearDown(debug.dispose);
      debug.togglePaintFlash();
      final presenter = AnsiFramePresenter(
        sink: sink,
        renderer: const AnsiRenderer(),
        debug: debug,
        readTarget: () => const AnsiRenderTarget.inline(top: 4),
        readCaret: () => CellRect.fromLTWH(1, 1, 1, 1),
      );
      const watching = FramePresentInfo(
        reason: 'test',
        plan: null,
        debugWatching: true,
        layoutStats: RenderLayoutFrameStats.empty,
        repaintBoundaryStats: RepaintBoundaryFrameStats.empty,
      );
      final loop = TuiFrameLoop();
      final frame = _frameFrom(loop, size);
      presenter.presentFrame(frame, watching);
      loop.commit(frame);
      expect(sink.output, contains('\x1B[42m'));
      expect(sink.output, endsWith('\x1B[6;2H'));
      _expectOnlyRows(sink.output, top: 4, rows: 3);
      sink.clear();
      debug.togglePaintFlash();

      presenter.presentFrame(_frameFrom(loop, size), watching);
      expect(sink.output, isNot(contains('\x1B[42m')));
      expect(sink.output, contains('h'));
      expect(sink.output, endsWith('\x1B[6;2H'));
      _expectOnlyRows(sink.output, top: 4, rows: 3);
    });

    test('native image placement fails before any output', () {
      final sink = StringAnsiSink();
      final presenter = AnsiFramePresenter(
        sink: sink,
        renderer: const AnsiRenderer(),
        debug: DebugController(const DebugConfig(enabled: false)),
        readTarget: () => const AnsiRenderTarget.inline(top: 3),
        imageEncoder: TerminalImageEncoder(protocol: ImageProtocol.kitty),
      );
      expect(
        () => presenter.presentFrame(_frame(size), info),
        throwsUnsupportedError,
      );
      expect(sink.output, isEmpty);
    });
  });

  test('positions the hidden terminal cursor at the focused caret', () {
    final sink = StringAnsiSink();
    final presenter = AnsiFramePresenter(
      sink: sink,
      renderer: const AnsiRenderer(synchronizedOutput: false),
      debug: DebugController(const DebugConfig(enabled: false)),
      readCaret: () => CellRect.fromLTWH(2, 1, 1, 1),
    );
    final frame = _frame(size);

    presenter.presentFrame(frame, info);

    expect(
      sink.output,
      endsWith('\x1B[2;3H'),
      reason: 'the hidden hardware cursor is the native IME anchor',
    );
  });

  test('repositions the caret even when the cell buffers are unchanged', () {
    final sink = StringAnsiSink();
    final presenter = AnsiFramePresenter(
      sink: sink,
      renderer: const AnsiRenderer(synchronizedOutput: false),
      debug: DebugController(const DebugConfig(enabled: false)),
      readCaret: () => CellRect.fromLTWH(3, 2, 1, 1),
    );
    final loop = TuiFrameLoop();
    final first = _frameFrom(loop, size);
    presenter.presentFrame(first, info);
    loop.commit(first);
    sink.clear();

    presenter.presentFrame(_frameFrom(loop, size), info);

    expect(sink.output, '\x1B[3;4H');
  });

  test('clamps a stale caret to the current viewport', () {
    final sink = StringAnsiSink();
    final presenter = AnsiFramePresenter(
      sink: sink,
      renderer: const AnsiRenderer(synchronizedOutput: false),
      debug: DebugController(const DebugConfig(enabled: false)),
      readCaret: () => CellRect.fromLTWH(20, 10, 1, 1),
    );

    presenter.presentFrame(_frame(size), info);

    expect(sink.output, endsWith('\x1B[3;5H'));
  });

  test('emits no caret bytes when no editable owns focus', () {
    final noCaretSink = StringAnsiSink();
    final noCaretPresenter = AnsiFramePresenter(
      sink: noCaretSink,
      renderer: const AnsiRenderer(synchronizedOutput: false),
      debug: DebugController(const DebugConfig(enabled: false)),
      readCaret: () => null,
    );
    final baselineSink = StringAnsiSink();
    final baselinePresenter = AnsiFramePresenter(
      sink: baselineSink,
      renderer: const AnsiRenderer(synchronizedOutput: false),
      debug: DebugController(const DebugConfig(enabled: false)),
    );

    noCaretPresenter.presentFrame(_frame(size), info);
    baselinePresenter.presentFrame(_frame(size), info);

    expect(noCaretSink.output, baselineSink.output);
  });

  test('forwards the frame damage scroll decision to the renderer', () {
    // The seam round one's regressions hid behind: renderer- and loop-level
    // tests both passed while the presenter forwarded neither signal. Severing
    // the forwarding (scrollUpRows: null) turns this scroll frame into 5.5x
    // the bytes with no ESC[S — this test fails on exactly that mutation.
    const tall = CellSize(20, 10);
    final sink = StringAnsiSink();
    final presenter = AnsiFramePresenter(
      sink: sink,
      renderer: const AnsiRenderer(synchronizedOutput: false),
      debug: DebugController(const DebugConfig(enabled: false)),
    );
    final loop = TuiFrameLoop();
    // Rows of distinct repeated letters: a one-row shift dirties ~all cells,
    // comfortably past the loop's detection gate (a row's worth of change) —
    // digit-only content like 'entry N' -> 'entry N+1' dirties ~1 cell/row,
    // which the gate correctly deems not worth scrolling for.
    String rowText(int row) => String.fromCharCode(0x41 + row) * 12;
    final first = loop.render(
      size: tall,
      paint: (buffer) {
        for (var row = 0; row < 10; row++) {
          buffer.writeText(CellOffset(0, row), rowText(row));
        }
      },
    )!;
    presenter.presentFrame(first, info);
    loop.commit(first);
    sink.clear();

    final scrolled = loop.render(
      size: tall,
      paint: (buffer) {
        for (var row = 0; row < 10; row++) {
          buffer.writeText(CellOffset(0, row), rowText(row + 1));
        }
      },
    )!;
    presenter.presentFrame(scrolled, info);

    expect(
      sink.output,
      contains('\x1B[S'),
      reason: 'a beneficial scroll must reach the terminal as ESC[S',
    );
  });

  test('an identical repaint emits zero bytes end to end', () {
    // Byte-level pin only: with no caret and no images, an unchanged frame
    // must produce literally nothing. (The hasChanges forwarding itself is
    // not observable in bytes for identical frames — the unbounded fallback
    // also emits nothing, just after a wasted whole-screen scan — so the CPU
    // half of this seam is pinned at the renderer level instead.)
    final sink = StringAnsiSink();
    final presenter = AnsiFramePresenter(
      sink: sink,
      renderer: const AnsiRenderer(synchronizedOutput: false),
      debug: DebugController(const DebugConfig(enabled: false)),
    );
    final loop = TuiFrameLoop();
    final first = _frameFrom(loop, size);
    presenter.presentFrame(first, info);
    loop.commit(first);
    sink.clear();

    presenter.presentFrame(_frameFrom(loop, size), info);

    expect(sink.output, isEmpty);
  });
}

TuiRenderedFrame _frame(CellSize size) => _frameFrom(TuiFrameLoop(), size);

TuiRenderedFrame _frameFrom(TuiFrameLoop loop, CellSize size) {
  return loop.render(
    size: size,
    paint: (buffer) => buffer.writeText(CellOffset.zero, 'hello'),
  )!;
}

void _expectOnlyRows(String output, {required int top, required int rows}) {
  final positions = RegExp(r'\x1b\[(\d*)(?:;\d+)?H').allMatches(output);
  expect(positions, isNotEmpty);
  for (final position in positions) {
    final row = int.tryParse(position[1]!) ?? 1;
    expect(row, inInclusiveRange(top + 1, top + rows));
  }
}
