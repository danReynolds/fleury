import 'package:fleury/src/debug/debug_state.dart';
import 'package:fleury/src/foundation/geometry.dart';
import 'package:fleury/src/rendering/ansi_renderer.dart';
import 'package:fleury/src/rendering/render_layout_stats.dart';
import 'package:fleury/src/rendering/render_repaint_boundary.dart';
import 'package:fleury/src/runtime/frame_driver.dart';
import 'package:fleury/src/runtime/tui_frame_loop.dart';
import 'package:fleury/src/terminal/ansi_frame_presenter.dart';
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
