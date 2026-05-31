// Widget-specific benchmarks for everything added after the baseline
// in baseline_results.md:
//
//   - Wrapping Text (word wrap + multi-line paint)
//   - ListView (build + layout for large lists; selection-change cost;
//     backward layout walk on jumpToIndex)
//   - Container + BoxBorder (paint cost of decorated panes)
//   - Focus bounds wrapper (per-Focus render-object overhead)
//
// Each setup mounts a representative tree, then `run()` measures the
// hot path the comment names. We never read into renderFrame's
// internals from here — these are end-to-end pipeline measurements.

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:fleury/fleury.dart';

const _size = CellSize(80, 24);

// ---------------------------------------------------------------------------
// Wrapping Text
// ---------------------------------------------------------------------------

/// A "chat message" sized for the typical wrap path: 240 chars of
/// plain ASCII that wraps to ~3-4 lines at 80 cols.
const _longMessage =
    "Look, the whole point of building this thing was to find out "
    "whether keyboard-first TUI affordances translate to Flutter's "
    "mental model without breaking. So far the wrap algorithm is "
    "the one piece I most want to actually measure rather than guess.";

/// 50+ lines of wrapped text, simulating a chat log paint.
final _hugeMessage = List<String>.generate(
  40,
  (i) => 'paragraph $i: $_longMessage',
).join('\n');

class WrapShortBenchmark extends BenchmarkBase {
  WrapShortBenchmark() : super('text_wrap_short[80x24]');
  late final BuildOwner owner;
  late final Element root;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    root = owner.mountRoot(const Text('hello terminal'));
    buffer = CellBuffer(_size);
  }

  @override
  void run() {
    buffer.clear();
    owner.renderFrame(root, buffer);
  }
}

class WrapMediumBenchmark extends BenchmarkBase {
  WrapMediumBenchmark() : super('text_wrap_medium_240ch[80x24]');
  late final BuildOwner owner;
  late final Element root;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    root = owner.mountRoot(const Text(_longMessage));
    buffer = CellBuffer(_size);
  }

  @override
  void run() {
    buffer.clear();
    owner.renderFrame(root, buffer);
  }
}

class WrapLongBenchmark extends BenchmarkBase {
  WrapLongBenchmark() : super('text_wrap_long_40paragraphs[80x60]');
  late final BuildOwner owner;
  late final Element root;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    root = owner.mountRoot(Text(_hugeMessage));
    buffer = CellBuffer(const CellSize(80, 60));
  }

  @override
  void run() {
    buffer.clear();
    owner.renderFrame(root, buffer);
  }
}

class WrapDisabledBaselineBenchmark extends BenchmarkBase {
  WrapDisabledBaselineBenchmark() : super('text_wrap_off_240ch[80x24]');
  late final BuildOwner owner;
  late final Element root;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    root = owner.mountRoot(const Text(_longMessage, softWrap: false));
    buffer = CellBuffer(_size);
  }

  @override
  void run() {
    buffer.clear();
    owner.renderFrame(root, buffer);
  }
}

// ---------------------------------------------------------------------------
// ListView
// ---------------------------------------------------------------------------

/// 100 items, ~22 visible. Exercises the eager-itemBuilder cost for
/// off-screen items.
class ListViewMediumBenchmark extends BenchmarkBase {
  ListViewMediumBenchmark() : super('listview_paint[100 items, 80x24]');
  late final BuildOwner owner;
  late final Element root;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    root = owner.mountRoot(
      ListView.builder(
        itemCount: 100,
        itemBuilder: (ctx, i, sel) => Text('Item $i'),
      ),
    );
    buffer = CellBuffer(_size);
  }

  @override
  void run() {
    buffer.clear();
    owner.renderFrame(root, buffer);
  }
}

class ListViewLargeBenchmark extends BenchmarkBase {
  ListViewLargeBenchmark() : super('listview_paint[1000 items, 80x24]');
  late final BuildOwner owner;
  late final Element root;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    root = owner.mountRoot(
      ListView.builder(
        itemCount: 1000,
        itemBuilder: (ctx, i, sel) => Text('Item $i'),
      ),
    );
    buffer = CellBuffer(_size);
  }

  @override
  void run() {
    buffer.clear();
    owner.renderFrame(root, buffer);
  }
}

/// Worst-case selection change on a large list: arrow-down on a
/// 1000-item list rebuilds every item because `selected` is part of
/// the builder closure inputs. This is the eager-build cost that
/// lazy mounting would erase.
class ListViewSelectionChangeBenchmark extends BenchmarkBase {
  ListViewSelectionChangeBenchmark()
    : super('listview_arrow_down[1000 items, 80x24]');
  late final BuildOwner owner;
  late final Element root;
  late final ListController controller;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    controller = ListController();
    root = owner.mountRoot(
      ListView.builder(
        controller: controller,
        itemCount: 1000,
        itemBuilder: (ctx, i, sel) => Text(
          'Item $i',
          style: sel ? const CellStyle(inverse: true) : CellStyle.empty,
        ),
      ),
    );
    buffer = CellBuffer(_size);
    // Prime: first frame so visibleRange is populated.
    owner.renderFrame(root, buffer);
  }

  var _next = 1;

  @override
  void run() {
    controller.selectedIndex = _next;
    _next = (_next + 1) % 1000;
    buffer.clear();
    owner.renderFrame(root, buffer);
  }
}

/// Jump from top to bottom on a 1000-item list. Exercises
/// `_anchorThatEndsAt` — the backward layout walk that lays children
/// out starting from the target. With uniform 1-row items the walk
/// terminates after `viewport.rows` items, not 1000, but it's worth
/// confirming.
class ListViewJumpToEndBenchmark extends BenchmarkBase {
  ListViewJumpToEndBenchmark() : super('listview_jumpToIndex[1000, 80x24]');
  late final BuildOwner owner;
  late final Element root;
  late final ListController controller;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    controller = ListController();
    root = owner.mountRoot(
      ListView.builder(
        controller: controller,
        itemCount: 1000,
        itemBuilder: (ctx, i, sel) => Text('Item $i'),
      ),
    );
    buffer = CellBuffer(_size);
    owner.renderFrame(root, buffer);
  }

  bool _atEnd = false;

  @override
  void run() {
    controller.jumpToIndex(_atEnd ? 0 : 999);
    _atEnd = !_atEnd;
    buffer.clear();
    owner.renderFrame(root, buffer);
  }
}

// ---------------------------------------------------------------------------
// Container + BoxBorder
// ---------------------------------------------------------------------------

class BorderedPaneBenchmark extends BenchmarkBase {
  BorderedPaneBenchmark() : super('container_border_paint[80x24]');
  late final BuildOwner owner;
  late final Element root;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    root = owner.mountRoot(
      Container(
        border: const BoxBorder(),
        padding: const EdgeInsets.all(1),
        child: const Text('hello terminal'),
      ),
    );
    buffer = CellBuffer(_size);
  }

  @override
  void run() {
    buffer.clear();
    owner.renderFrame(root, buffer);
  }
}

/// Six bordered panes in a Row — the typical "framed dashboard"
/// layout. Tests that border paint scales linearly.
class BorderedGridBenchmark extends BenchmarkBase {
  BorderedGridBenchmark() : super('container_border_grid[6 panes, 80x24]');
  late final BuildOwner owner;
  late final Element root;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    root = owner.mountRoot(
      Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List<Widget>.generate(
          6,
          (i) => Expanded(
            child: Container(
              border: const BoxBorder(),
              padding: const EdgeInsets.all(1),
              child: Text('pane $i'),
            ),
          ),
        ),
      ),
    );
    buffer = CellBuffer(_size);
  }

  @override
  void run() {
    buffer.clear();
    owner.renderFrame(root, buffer);
  }
}

// ---------------------------------------------------------------------------
// Focus bounds overhead
// ---------------------------------------------------------------------------

/// Layout/paint a Column of 20 Focus widgets each wrapping a Text.
/// Each Focus inserts a _RenderFocusBounds in the render tree —
/// measures how much that wrapper costs at scale. 20 is the cap so
/// the column fits inside the 24-row viewport (plus 4 rows of slack).
class ManyFocusWidgetsBenchmark extends BenchmarkBase {
  ManyFocusWidgetsBenchmark() : super('focus_bounds_overhead[20 widgets]');
  late final BuildOwner owner;
  late final Element root;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    root = owner.mountRoot(
      FocusManagerScope(
        manager: FocusManager(),
        child: Column(
          children: List<Widget>.generate(
            20,
            (i) => Focus(
              focusNode: FocusNode(debugLabel: 'f$i'),
              child: Text('focusable $i'),
            ),
          ),
        ),
      ),
    );
    buffer = CellBuffer(_size);
  }

  @override
  void run() {
    buffer.clear();
    owner.renderFrame(root, buffer);
  }
}

/// Baseline for the bounds-wrapper overhead: same column of 20 Text
/// widgets, no Focus widgets. The diff between this and
/// ManyFocusWidgetsBenchmark is roughly what _RenderFocusBounds adds.
class FocusBoundsBaselineBenchmark extends BenchmarkBase {
  FocusBoundsBaselineBenchmark() : super('focus_bounds_baseline[20 widgets]');
  late final BuildOwner owner;
  late final Element root;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    root = owner.mountRoot(
      Column(children: List<Widget>.generate(20, (i) => Text('plain $i'))),
    );
    buffer = CellBuffer(_size);
  }

  @override
  void run() {
    buffer.clear();
    owner.renderFrame(root, buffer);
  }
}

void main() {
  WrapShortBenchmark().report();
  WrapDisabledBaselineBenchmark().report();
  WrapMediumBenchmark().report();
  WrapLongBenchmark().report();
  ListViewMediumBenchmark().report();
  ListViewLargeBenchmark().report();
  ListViewSelectionChangeBenchmark().report();
  ListViewJumpToEndBenchmark().report();
  BorderedPaneBenchmark().report();
  BorderedGridBenchmark().report();
  FocusBoundsBaselineBenchmark().report();
  ManyFocusWidgetsBenchmark().report();
}
