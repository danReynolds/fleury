// Integration test for the selection container delegate.
// Uses a stub Selectable that hit-tests against a fixed rect and
// reports start/end character offsets. The point is to verify the
// boundary-handoff logic — that the delegate routes events to
// reading-order children, that selection state accumulates
// correctly, and that getSelectedText concatenates portions across
// boundaries.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// A minimal Selectable that maps screen-space columns to character
/// offsets one-to-one within its bounds. Multi-row content is treated
/// as one line per row. Good enough to validate the delegate without
/// pulling in RenderText.
///
/// Each leaf tracks the *relation* of each edge to itself, not just
/// the screen position: each edge is one of {before me, inside me at
/// offset N, after me}. The four cells of the cross-product describe
/// every possible local selection state — that's the algorithm we
/// need real Selectables (RenderText et al.) to implement, so we
/// exercise it here against the dispatcher.
class _StubSelectable extends ChangeNotifier implements Selectable {
  _StubSelectable({required this.bounds, required this.text});

  final CellRect bounds;
  final String text;

  SelectionGeometry _geometry = SelectionGeometry.empty;
  _EdgeRelation _startRel = const _EdgeRelation.none();
  _EdgeRelation _endRel = const _EdgeRelation.none();

  @override
  int get contentLength => text.length;

  @override
  CellRect? get cellBounds => bounds;

  @override
  CellRect? get visibleBounds => bounds;

  @override
  SelectionGeometry get geometry => _geometry;

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    switch (event) {
      case SelectionEdgeUpdateEvent(:final globalPosition, :final isStart):
        final rel = _relate(globalPosition);
        if (isStart) {
          _startRel = rel;
        } else {
          _endRel = rel;
        }
        _recompute();
        return rel.asSelectionResult();
      case SelectionClearEvent():
        _startRel = const _EdgeRelation.none();
        _endRel = const _EdgeRelation.none();
        _recompute();
        return SelectionResult.none;
      case SelectionGranularEvent(:final granularity):
        if (granularity == SelectionGranularity.all) {
          _startRel = _EdgeRelation.inside(0);
          _endRel = _EdgeRelation.inside(text.length);
          _recompute();
          return SelectionResult.end;
        }
        return SelectionResult.none;
    }
  }

  @override
  SelectedContent? getSelectedContent() {
    final range = getSelectionRange();
    if (range == null) return null;
    return SelectedContent(plainText: text.substring(range.start, range.end));
  }

  @override
  ({int end, int start})? getSelectionRange() {
    final s = _startRel;
    final e = _endRel;
    // No edges placed → no selection.
    if (s.kind == _EdgeKind.none && e.kind == _EdgeKind.none) return null;

    // Helper: resolve an edge to a character offset using the "this
    // edge fell on the OUTSIDE" rule that depends on which side the
    // OTHER edge is on.
    int resolve(_EdgeRelation here, _EdgeRelation other) {
      switch (here.kind) {
        case _EdgeKind.inside:
          return here.offset;
        case _EdgeKind.before:
          return 0;
        case _EdgeKind.after:
          return text.length;
        case _EdgeKind.none:
          // No event for this edge yet — collapse to the other one.
          return resolve(other, here);
      }
    }

    final sOff = resolve(s, e);
    final eOff = resolve(e, s);
    if (sOff == eOff) return null;
    return sOff < eOff ? (start: sOff, end: eOff) : (start: eOff, end: sOff);
  }

  _EdgeRelation _relate(CellOffset p) {
    final r = bounds;
    final endRow = r.offset.row + r.size.rows - 1;
    if (p.row < r.offset.row) return const _EdgeRelation.before();
    if (p.row > endRow) return const _EdgeRelation.after();
    if (p.col < r.offset.col) return const _EdgeRelation.before();
    if (p.col >= r.offset.col + text.length) {
      return const _EdgeRelation.after();
    }
    return _EdgeRelation.inside(p.col - r.offset.col);
  }

  @override
  CellOffset? nextGraphemeBoundary(CellOffset from, int dCol, int dRow) {
    // Stub: treat every cell as one grapheme.
    if (from.row != bounds.offset.row) return null;
    final col = from.col + dCol;
    final row = from.row + dRow;
    if (col < bounds.offset.col || col > bounds.offset.col + text.length) {
      return null;
    }
    return CellOffset(col, row);
  }

  void _recompute() {
    final range = getSelectionRange();
    final next = range == null
        ? SelectionGeometry.empty
        : SelectionGeometry(
            status: SelectionStatus.collapsed,
            startEdgeOffsetInContent: range.start,
            endEdgeOffsetInContent: range.end,
          );
    if (_geometry == next) return;
    _geometry = next;
    notifyListeners();
  }
}

enum _EdgeKind { none, before, inside, after }

class _EdgeRelation {
  const _EdgeRelation.none() : kind = _EdgeKind.none, offset = -1;
  const _EdgeRelation.before() : kind = _EdgeKind.before, offset = -1;
  const _EdgeRelation.after() : kind = _EdgeKind.after, offset = -1;
  const _EdgeRelation.inside(this.offset) : kind = _EdgeKind.inside;

  final _EdgeKind kind;
  final int offset;

  SelectionResult asSelectionResult() => switch (kind) {
    _EdgeKind.before => SelectionResult.previous,
    _EdgeKind.after => SelectionResult.next,
    _EdgeKind.inside => SelectionResult.end,
    _EdgeKind.none => SelectionResult.none,
  };
}

void main() {
  group('SelectionContainerDelegate — single Selectable', () {
    test('an edge update inside the leaf is delivered + classified end', () {
      final s = _StubSelectable(
        bounds: const CellRect(offset: CellOffset(0, 0), size: CellSize(10, 1)),
        text: 'hello world',
      );
      final delegate = SelectionContainerDelegate()..add(s);

      delegate.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent(
          globalPosition: CellOffset(2, 0),
          isStart: true,
        ),
      );
      delegate.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent(
          globalPosition: CellOffset(7, 0),
          isStart: false,
        ),
      );

      expect(delegate.getSelectedText(), 'llo w');
    });

    test('reverse selection (end before start) still yields ordered text', () {
      final s = _StubSelectable(
        bounds: const CellRect(offset: CellOffset(0, 0), size: CellSize(10, 1)),
        text: 'abcdefghij',
      );
      final delegate = SelectionContainerDelegate()..add(s);

      delegate.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent(
          globalPosition: CellOffset(7, 0),
          isStart: true,
        ),
      );
      delegate.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent(
          globalPosition: CellOffset(2, 0),
          isStart: false,
        ),
      );

      expect(delegate.getSelectedText(), 'cdefg');
    });

    test('clear drops the selection', () {
      final s = _StubSelectable(
        bounds: const CellRect(offset: CellOffset(0, 0), size: CellSize(5, 1)),
        text: 'hello',
      );
      final delegate = SelectionContainerDelegate()..add(s);

      delegate.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent(
          globalPosition: CellOffset(1, 0),
          isStart: true,
        ),
      );
      delegate.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent(
          globalPosition: CellOffset(4, 0),
          isStart: false,
        ),
      );
      expect(delegate.getSelectedText(), 'ell');

      delegate.clear();
      expect(delegate.getSelectedText(), isEmpty);
    });

    test('selectAll picks up the full content via granular event', () {
      final s = _StubSelectable(
        bounds: const CellRect(offset: CellOffset(0, 0), size: CellSize(5, 1)),
        text: 'hello',
      );
      final delegate = SelectionContainerDelegate()..add(s);

      delegate.dispatchSelectionEvent(
        const SelectionGranularEvent(granularity: SelectionGranularity.all),
      );

      expect(delegate.getSelectedText(), 'hello');
    });
  });

  group('SelectionContainerDelegate — boundary handoff', () {
    test(
      'selection across two leaves concatenates portions in reading order',
      () {
        // Two single-line Selectables stacked vertically.
        final a = _StubSelectable(
          bounds: const CellRect(
            offset: CellOffset(0, 0),
            size: CellSize(5, 1),
          ),
          text: 'hello',
        );
        final b = _StubSelectable(
          bounds: const CellRect(
            offset: CellOffset(0, 1),
            size: CellSize(5, 1),
          ),
          text: 'world',
        );
        final delegate = SelectionContainerDelegate()
          ..add(a)
          ..add(b);

        // Drag from col 2 row 0 ("llo") to col 3 row 1 ("wor").
        delegate.dispatchSelectionEvent(
          const SelectionEdgeUpdateEvent(
            globalPosition: CellOffset(2, 0),
            isStart: true,
          ),
        );
        delegate.dispatchSelectionEvent(
          const SelectionEdgeUpdateEvent(
            globalPosition: CellOffset(3, 1),
            isStart: false,
          ),
        );

        expect(delegate.getSelectedText(), 'llo\nwor');
      },
    );

    test(
      'selection wholly inside the second leaf still hands off — first stays empty',
      () {
        final a = _StubSelectable(
          bounds: const CellRect(
            offset: CellOffset(0, 0),
            size: CellSize(5, 1),
          ),
          text: 'first',
        );
        final b = _StubSelectable(
          bounds: const CellRect(
            offset: CellOffset(0, 1),
            size: CellSize(6, 1),
          ),
          text: 'second',
        );
        final delegate = SelectionContainerDelegate()
          ..add(a)
          ..add(b);

        delegate.dispatchSelectionEvent(
          const SelectionEdgeUpdateEvent(
            globalPosition: CellOffset(1, 1),
            isStart: true,
          ),
        );
        delegate.dispatchSelectionEvent(
          const SelectionEdgeUpdateEvent(
            globalPosition: CellOffset(4, 1),
            isStart: false,
          ),
        );

        expect(delegate.getSelectedText(), 'eco');
      },
    );

    test('reading-order sort: leaves at lower rows come first', () {
      final lower = _StubSelectable(
        bounds: const CellRect(offset: CellOffset(0, 2), size: CellSize(5, 1)),
        text: 'lower',
      );
      final upper = _StubSelectable(
        bounds: const CellRect(offset: CellOffset(0, 0), size: CellSize(5, 1)),
        text: 'upper',
      );
      // Add out of order; delegate should still walk top-down.
      final delegate = SelectionContainerDelegate()
        ..add(lower)
        ..add(upper);

      // Drag from inside `upper` to inside `lower`.
      delegate.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent(
          globalPosition: CellOffset(2, 0),
          isStart: true,
        ),
      );
      delegate.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent(
          globalPosition: CellOffset(3, 2),
          isStart: false,
        ),
      );

      expect(delegate.getSelectedText(), 'per\nlow');
    });
  });

  group('SelectionContainerDelegate — registrar lifecycle', () {
    test('removing a Selectable drops it from getSelectedText', () {
      final a = _StubSelectable(
        bounds: const CellRect(offset: CellOffset(0, 0), size: CellSize(5, 1)),
        text: 'hello',
      );
      final b = _StubSelectable(
        bounds: const CellRect(offset: CellOffset(0, 1), size: CellSize(5, 1)),
        text: 'world',
      );
      final delegate = SelectionContainerDelegate()
        ..add(a)
        ..add(b);

      delegate.dispatchSelectionEvent(
        const SelectionGranularEvent(granularity: SelectionGranularity.all),
      );
      expect(delegate.getSelectedText(), 'hello\nworld');

      delegate.remove(b);
      expect(delegate.getSelectedText(), 'hello');
    });

    test('a newly-added Selectable picks up the in-flight selection', () {
      final a = _StubSelectable(
        bounds: const CellRect(offset: CellOffset(0, 0), size: CellSize(5, 1)),
        text: 'hello',
      );
      final delegate = SelectionContainerDelegate()..add(a);

      delegate.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent(
          globalPosition: CellOffset(1, 0),
          isStart: true,
        ),
      );
      delegate.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent(
          globalPosition: CellOffset(7, 1),
          isStart: false,
        ),
      );
      // 'a' alone reports 'ello' (truncated to its 5 cols by hit-test).
      expect(delegate.getSelectedText(), 'ello');

      // A second leaf mounts mid-selection. The delegate replays the
      // pending edges into it.
      final b = _StubSelectable(
        bounds: const CellRect(offset: CellOffset(0, 1), size: CellSize(7, 1)),
        text: 'goodbye',
      );
      delegate.add(b);
      expect(delegate.getSelectedText(), 'ello\ngoodbye');
    });
  });

  group('SelectionContainerDelegate — change notification', () {
    test('listeners fire on dispatch', () {
      var notifications = 0;
      final delegate = SelectionContainerDelegate()
        ..add(
          _StubSelectable(
            bounds: const CellRect(
              offset: CellOffset(0, 0),
              size: CellSize(5, 1),
            ),
            text: 'hello',
          ),
        )
        ..addListener(() => notifications++);

      delegate.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent(
          globalPosition: CellOffset(2, 0),
          isStart: true,
        ),
      );
      delegate.dispatchSelectionEvent(
        const SelectionEdgeUpdateEvent(
          globalPosition: CellOffset(4, 0),
          isStart: false,
        ),
      );

      expect(notifications, greaterThanOrEqualTo(2));
    });
  });
}
