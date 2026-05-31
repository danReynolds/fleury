// Shared scaffolding for the fleury benchmark suite. Kept separate
// from the framework's public surface so benchmark code can build
// trees, fabricate widgets, and sink ANSI bytes into a no-op writer
// without depending on test-only APIs.

import 'package:fleury/fleury.dart';

/// Discards every byte written. Lets the diff renderer run to
/// completion without measuring sink-side cost (which depends on the
/// concrete sink — `StringAnsiSink` allocates, `IoSinkAnsiSink`
/// hits the OS).
final class NullAnsiSink implements AnsiSink {
  const NullAnsiSink();

  @override
  void write(String data) {}

  @override
  Future<void> flush() async {}
}

/// A buffer densely populated with a single grapheme. Used as the
/// `previous` for "everything differs" diff benchmarks.
CellBuffer denseBuffer(CellSize size, String grapheme) {
  final buf = CellBuffer(size);
  for (var row = 0; row < size.rows; row++) {
    for (var col = 0; col < size.cols; col++) {
      buf.writeGrapheme(CellOffset(col, row), grapheme);
    }
  }
  return buf;
}

/// Builds a buffer by painting `text` at row 0, then duplicating it
/// down the rest of the rows. Useful for "typical content" cases.
CellBuffer textBuffer(CellSize size, String text) {
  final buf = CellBuffer(size);
  for (var row = 0; row < size.rows; row++) {
    buf.writeText(CellOffset(0, row), text);
  }
  return buf;
}

/// Returns a CellBuffer that is a per-cell copy of [src]. Useful for
/// "identical buffers" tests where we don't want them to share state.
CellBuffer copyOf(CellBuffer src) {
  final out = CellBuffer(src.size);
  for (var row = 0; row < src.size.rows; row++) {
    for (var col = 0; col < src.size.cols; col++) {
      final cell = src.atColRow(col, row);
      if (cell.role == CellRole.leading) {
        out.writeGrapheme(
          CellOffset(col, row),
          cell.grapheme!,
          style: cell.style,
        );
      }
    }
  }
  return out;
}

/// Synthetic deeply-nested tree of [count] stateful counters,
/// arranged in a Column so each one renders on its own row.
class CounterColumn extends StatelessWidget {
  const CounterColumn({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(
        count,
        (i) => _BenchmarkCounter(key: ValueKey<int>(i), initial: i),
      ),
    );
  }
}

class _BenchmarkCounter extends StatefulWidget {
  const _BenchmarkCounter({super.key, required this.initial});
  final int initial;

  @override
  State<_BenchmarkCounter> createState() => BenchmarkCounterState();
}

/// Public so benchmarks can poke `setState` from outside.
class BenchmarkCounterState extends State<_BenchmarkCounter> {
  late int value = widget.initial;

  void poke(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) => Text('counter $value');
}

/// Collects every `BenchmarkCounterState` under [root] in tree order.
List<BenchmarkCounterState> collectCounters(Element root) {
  final out = <BenchmarkCounterState>[];
  void visit(Element e) {
    if (e is StatefulElement && e.state is BenchmarkCounterState) {
      out.add(e.state as BenchmarkCounterState);
    }
    e.visitChildren(visit);
  }

  visit(root);
  return out;
}
