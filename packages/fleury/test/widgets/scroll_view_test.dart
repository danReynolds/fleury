// ScrollView: windowed viewport onto a tall child — scroll chords,
// clamping, clipping, and edge bubbling.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

import '../support/render_fixtures.dart';

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

/// A tall column of single-row labels r0..r{n-1}.
Widget _rows(int n) =>
    Column(children: [for (var i = 0; i < n; i++) Text('r$i')]);

/// Renders [rows] rows of the first column as one string per line.
List<String> _lines(FleuryTester tester, {int cols = 6, required int rows}) {
  final buf = tester.render(size: CellSize(cols, rows));
  final out = <String>[];
  for (var r = 0; r < rows; r++) {
    final sb = StringBuffer();
    for (var c = 0; c < cols; c++) {
      final cell = buf.atColRow(c, r);
      sb.write(cell.role == CellRole.leading ? cell.grapheme : ' ');
    }
    out.add(sb.toString().trimRight());
  }
  return out;
}

class _PaintProbe {
  CellSize? bufferSize;
  CellOffset? offset;
  CellOffset? screenOffset;
  CellRect? clipRect;
}

class _PaintProbeWidget extends LeafRenderObjectWidget {
  const _PaintProbeWidget({required this.probe, required this.desiredSize});

  final _PaintProbe probe;
  final CellSize desiredSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PaintProbeRender(probe: probe, desiredSize: desiredSize);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _PaintProbeRender renderObject,
  ) {
    renderObject
      ..probe = probe
      ..desiredSize = desiredSize;
  }
}

class _PaintProbeRender extends RenderObject {
  _PaintProbeRender({required _PaintProbe probe, required CellSize desiredSize})
    : _probe = probe,
      _desiredSize = desiredSize;

  _PaintProbe _probe;
  _PaintProbe get probe => _probe;
  set probe(_PaintProbe value) {
    if (identical(_probe, value)) return;
    _probe = value;
    markNeedsPaintOnly();
  }

  CellSize _desiredSize;
  CellSize get desiredSize => _desiredSize;
  set desiredSize(CellSize value) {
    if (_desiredSize == value) return;
    _desiredSize = value;
    markNeedsLayout();
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    return constraints.constrain(_desiredSize);
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    _probe
      ..bufferSize = buffer.size
      ..offset = offset
      ..screenOffset = screenOffset
      ..clipRect = clipRect;

    for (var r = 0; r < _desiredSize.rows; r++) {
      buffer.writeGrapheme(CellOffset(offset.col, offset.row + r), 'x');
    }
  }
}

void main() {
  testWidgets('shows the top of the content by default', (tester) {
    tester.pumpWidget(ScrollView(child: _rows(10)));
    expect(_lines(tester, rows: 3), ['r0', 'r1', 'r2']);
  });

  testWidgets('carries a visible inline image through the scratch composite', (
    tester,
  ) {
    // An Image inside a ScrollView paints into the scroll's scratch buffer;
    // its placement must be carried back or a true-pixel surface renders a
    // blank box. (Regression: the cell composite copies only leading cells.)
    final ctl = ScrollController();
    tester.pumpWidget(
      ScrollView(
        controller: ctl,
        child: Column(children: [const ImageLeaf(), _rows(20)]),
      ),
    );
    final buf = tester.render(size: const CellSize(6, 5));
    final placement = buf.imagePlacements.single;
    expect(placement.col, 0);
    expect(placement.row, 0, reason: 'image sits at the top of the viewport');
    expect(placement.cols, 4);
    expect(buf.images, isNotEmpty);
    // The region is overlay (the encoder/overlay renders the pixels).
    expect(buf.atColRow(0, 0).role, CellRole.overlay);

    // A leading-edge clip keeps the lower row without recomputing fit against
    // a one-row box.
    ctl.scrollBy(1);
    final partial = tester.render(size: const CellSize(6, 5));
    final clipped = partial.imagePlacements.single;
    expect(
      [clipped.col, clipped.row, clipped.cols, clipped.rows],
      [0, 0, 4, 1],
    );
    expect([clipped.boxCols, clipped.boxRows], [4, 2]);
    expect([clipped.boxOffsetCol, clipped.boxOffsetRow], [0, 1]);
    expect(partial.atColRow(0, 0).role, CellRole.overlay);

    // Scroll the image out of view → the placement is no longer carried
    // (the scratch drops it, so nothing lingers on the surface).
    ctl.scrollBy(6);
    final scrolled = tester.render(size: const CellSize(6, 5));
    expect(
      scrolled.imagePlacements,
      isEmpty,
      reason: 'a scrolled-away image contributes no placement',
    );
  });

  testWidgets('scrollBy reveals lower content; metrics are reported', (tester) {
    final ctl = ScrollController();
    tester.pumpWidget(ScrollView(controller: ctl, child: _rows(10)));
    // First render populates metrics (content 10, viewport 3 → max 7).
    expect(_lines(tester, rows: 3), ['r0', 'r1', 'r2']);
    expect(ctl.contentExtent, 10);
    expect(ctl.viewportExtent, 3);
    expect(ctl.maxOffset, 7);

    ctl.scrollBy(2);
    expect(_lines(tester, rows: 3), ['r2', 'r3', 'r4']);
  });

  testWidgets('Ctrl+D / Ctrl+U scroll a half page', (tester) {
    final ctl = ScrollController();
    tester.pumpWidget(
      ScrollView(controller: ctl, autofocus: true, child: _rows(20)),
    );
    _lines(tester, rows: 4); // viewport 4, content 20 → half page = 2
    expect(ctl.offset, 0);
    tester.sendKey(
      const KeyEvent(KeyCode.char('d'), modifiers: {KeyModifier.ctrl}),
    );
    expect(ctl.offset, 2);
    tester.sendKey(
      const KeyEvent(KeyCode.char('u'), modifiers: {KeyModifier.ctrl}),
    );
    expect(ctl.offset, 0);
  });

  testWidgets('paints the child into a viewport-sized scratch buffer', (
    tester,
  ) {
    final ctl = ScrollController(offset: 10);
    final probe = _PaintProbe();
    tester.pumpWidget(
      SizedBox(
        width: 6,
        height: 4,
        child: ScrollView(
          controller: ctl,
          child: _PaintProbeWidget(
            probe: probe,
            desiredSize: const CellSize(6, 40),
          ),
        ),
      ),
    );

    expect(_lines(tester, rows: 4), ['x', 'x', 'x', 'x']);
    expect(ctl.maxOffset, 36);
    expect(probe.bufferSize, const CellSize(6, 4));
    expect(probe.offset, const CellOffset(0, -10));
    expect(probe.screenOffset, const CellOffset(0, -10));
    expect(
      probe.clipRect,
      const CellRect(offset: CellOffset.zero, size: CellSize(6, 4)),
    );
  });

  testWidgets('clamps at the bottom and reports atBottom', (tester) {
    final ctl = ScrollController();
    tester.pumpWidget(ScrollView(controller: ctl, child: _rows(10)));
    _lines(tester, rows: 3); // populate metrics

    ctl.scrollToBottom();
    expect(ctl.offset, 7, reason: 'maxOffset = 10 - 3');
    expect(ctl.atBottom, isTrue);
    expect(_lines(tester, rows: 3), ['r7', 'r8', 'r9']);

    ctl.scrollBy(100); // over-scroll is clamped
    expect(ctl.offset, 7);
  });

  testWidgets('clips content outside the viewport — no bleed below', (tester) {
    // Header sits above a 2-row scroll window over 10 rows; the content
    // below the window must not paint into the header or past the slot.
    tester.pumpWidget(
      Column(
        children: [
          const Text('top'),
          SizedBox(height: 2, child: ScrollView(child: _rows(10))),
          const Text('bot'),
        ],
      ),
    );
    // Rows: top / r0 / r1 / bot — the scroll window is exactly 2 rows.
    expect(_lines(tester, rows: 4), ['top', 'r0', 'r1', 'bot']);
  });

  testWidgets('arrow + page + home/end chords scroll when focused', (tester) {
    final ctl = ScrollController();
    tester.pumpWidget(
      ScrollView(controller: ctl, autofocus: true, child: _rows(20)),
    );
    _lines(tester, rows: 4); // populate metrics (viewport 4 → page 4)

    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    expect(ctl.offset, 1);

    tester.sendKey(const KeyEvent(KeyCode.pageDown));
    _lines(tester, rows: 4);
    expect(ctl.offset, 5, reason: '1 + one viewport (4)');

    tester.sendKey(const KeyEvent(KeyCode.end));
    expect(ctl.offset, 16, reason: 'maxOffset = 20 - 4');

    tester.sendKey(const KeyEvent(KeyCode.home));
    expect(ctl.offset, 0);
  });

  testWidgets('edgeBehavior.bubble lets an ancestor act at the edge', (tester) {
    var bubbled = 0;
    final ctl = ScrollController();
    tester.pumpWidget(
      KeyBindings(
        bindings: [KeyBinding(KeyCode.arrowUp, onTrigger: () => bubbled++)],
        child: ScrollView(
          controller: ctl,
          autofocus: true,
          edgeBehavior: EdgeBehavior.bubble,
          child: _rows(10),
        ),
      ),
    );
    _lines(tester, rows: 3);

    // At the top, Up bubbles to the ancestor binding.
    tester.sendKey(const KeyEvent(KeyCode.arrowUp));
    expect(bubbled, 1);
    expect(ctl.offset, 0);
  });

  testWidgets(
    'controller dispose keeps metrics readable and rejects mutation',
    (tester) {
      final ctl = ScrollController(offset: 2);
      tester.pumpWidget(ScrollView(controller: ctl, child: _rows(10)));
      expect(_lines(tester, rows: 3), ['r2', 'r3', 'r4']);
      expect(ctl.contentExtent, 10);
      expect(ctl.viewportExtent, 3);
      expect(ctl.maxOffset, 7);

      ctl.dispose();
      ctl.dispose();

      expect(ctl.offset, 2);
      expect(ctl.contentExtent, 10);
      expect(ctl.viewportExtent, 3);
      expect(ctl.maxOffset, 7);
      expect(ctl.atTop, isFalse);
      expect(ctl.atBottom, isFalse);

      const message = 'ScrollController has been disposed.';
      expect(() => ctl.offset = 0, _stateError(message));
      expect(() => ctl.scrollBy(1), _stateError(message));
      expect(() => ctl.jumpTo(0), _stateError(message));
      expect(() => ctl.scrollToTop(), _stateError(message));
      expect(() => ctl.scrollToBottom(), _stateError(message));
    },
  );
}
