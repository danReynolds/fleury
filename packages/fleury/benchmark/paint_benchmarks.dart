// Build + layout + paint pipeline benchmarks. Measures
// `BuildOwner.renderFrame` end-to-end: build dirty subtrees, run
// layout against constraints, walk render tree painting cells.
//
// Per the perf RFC, this is where Cell allocations live; these
// numbers drive the H1 (packed-cell) decision.

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:fleury/fleury.dart';

const _size = CellSize(80, 24);

class PaintSingleTextBenchmark extends BenchmarkBase {
  PaintSingleTextBenchmark() : super('paint_single_text[80x24]');
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

class PaintDenseTextBenchmark extends BenchmarkBase {
  PaintDenseTextBenchmark() : super('paint_dense_text[24 rows of text, 80x24]');
  late final BuildOwner owner;
  late final Element root;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    root = owner.mountRoot(
      Column(
        children: List<Widget>.generate(
          24,
          (i) =>
              Text('row $i: this is a line of plain ascii text for the bench'),
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

class PaintTypicalChatBenchmark extends BenchmarkBase {
  PaintTypicalChatBenchmark() : super('paint_typical_chat[80x24]');
  late final BuildOwner owner;
  late final Element root;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    root = owner.mountRoot(_ChatSurface());
    buffer = CellBuffer(_size);
  }

  @override
  void run() {
    buffer.clear();
    owner.renderFrame(root, buffer);
  }
}

class _ChatSurface extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        SizedBox(
          width: 20,
          child: Column(
            children: [
              Text(
                ' Conversations',
                style: CellStyle(bold: true, foreground: AnsiColor(14)),
              ),
              Text(''),
              Text(
                ' Family            3',
                style: CellStyle(foreground: AnsiColor(2)),
              ),
              Text(' Work'),
              Text(
                ' Climbing crew    12',
                style: CellStyle(foreground: AnsiColor(2)),
              ),
              Text(' Old roommates'),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Text(' Climbing crew', style: CellStyle(bold: true)),
              Text(''),
              Text(
                ' jess   14:02   should we go saturday?',
                style: CellStyle(foreground: AnsiColor(6)),
              ),
              Text(
                ' dan    14:03   yeah, weather looks good',
                style: CellStyle(foreground: AnsiColor(6)),
              ),
              Text(' you    14:05   ill bring the rope'),
              Text(''),
              Text(' > _', style: CellStyle(foreground: AnsiColor(11))),
            ],
          ),
        ),
      ],
    );
  }
}

class PaintLargeChatBenchmark extends BenchmarkBase {
  PaintLargeChatBenchmark() : super('paint_typical_chat[200x60]');
  late final BuildOwner owner;
  late final Element root;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    root = owner.mountRoot(_ChatSurface());
    buffer = CellBuffer(const CellSize(200, 60));
  }

  @override
  void run() {
    buffer.clear();
    owner.renderFrame(root, buffer);
  }
}

/// Same content as [PaintDenseTextBenchmark], wrapped in a `RepaintBoundary`.
/// First `run()` populates the boundary's cache; subsequent runs blit it
/// instead of walking the 24-row paint chain. The averaged µs/run reported
/// by the harness is steady-state — what a real app would see frame to
/// frame on a subtree that doesn't change.
class PaintDenseTextWithBoundaryBenchmark extends BenchmarkBase {
  PaintDenseTextWithBoundaryBenchmark()
    : super('paint_dense_text+RepaintBoundary[80x24]');
  late final BuildOwner owner;
  late final Element root;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    root = owner.mountRoot(
      RepaintBoundary(
        child: Column(
          children: List<Widget>.generate(
            24,
            (i) => Text(
              'row $i: this is a line of plain ascii text for the bench',
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

/// Same content as [PaintLargeChatBenchmark] but the whole tree is behind a
/// `RepaintBoundary` — shows the blit win on a larger viewport.
class PaintLargeChatWithBoundaryBenchmark extends BenchmarkBase {
  PaintLargeChatWithBoundaryBenchmark()
    : super('paint_typical_chat+RepaintBoundary[200x60]');
  late final BuildOwner owner;
  late final Element root;
  late final CellBuffer buffer;

  @override
  void setup() {
    owner = BuildOwner();
    root = owner.mountRoot(RepaintBoundary(child: _ChatSurface()));
    buffer = CellBuffer(const CellSize(200, 60));
  }

  @override
  void run() {
    buffer.clear();
    owner.renderFrame(root, buffer);
  }
}

void main() {
  PaintSingleTextBenchmark().report();
  PaintDenseTextBenchmark().report();
  PaintDenseTextWithBoundaryBenchmark().report();
  PaintTypicalChatBenchmark().report();
  PaintLargeChatBenchmark().report();
  PaintLargeChatWithBoundaryBenchmark().report();
}
