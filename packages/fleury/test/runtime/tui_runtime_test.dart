import 'package:fleury/fleury_host.dart';
import 'package:test/test.dart';

void main() {
  group('TuiRuntime', () {
    test('mounts, renders, and updates the root element', () {
      final runtime = TuiRuntime();
      addTearDown(runtime.dispose);

      runtime.mountRoot(const Text('one'));
      final first = CellBuffer(const CellSize(5, 1));
      runtime.renderFrame(first);

      expect(_flatten(first), 'one··');

      runtime.updateRoot(const Text('two'));
      final second = CellBuffer(const CellSize(5, 1));
      runtime.renderFrame(second);

      expect(_flatten(second), 'two··');
    });

    test('flushes post-frame callbacks using the runtime binding clock', () {
      final runtime = TuiRuntime();
      addTearDown(runtime.dispose);
      var fired = 0;

      runtime.mountRoot(
        TuiBindingScope(
          binding: runtime.binding,
          child: _PostFrameWidget(onFire: () => fired += 1),
        ),
      );

      final buffer = CellBuffer(const CellSize(5, 1));
      runtime.renderFrame(buffer);
      expect(fired, 0);

      runtime.flushPostFrameCallbacks();
      expect(fired, 1);
    });

    test('reports build flush stats for rendered frames', () {
      final runtime = TuiRuntime();
      addTearDown(runtime.dispose);
      final key = GlobalKey<_CounterState>();

      runtime.mountRoot(_Counter(key: key));
      runtime.renderFrame(CellBuffer(const CellSize(5, 1)));

      key.currentState!.increment();
      BuildFlushStats? stats;
      runtime.renderFrame(
        CellBuffer(const CellSize(5, 1)),
        onBuildStats: (value) => stats = value,
      );

      final captured = stats;
      expect(captured, isNotNull);
      expect(captured!.passCount, 1);
      expect(captured.rebuiltElementCount, 1);
      expect(captured.maxDirtyElementCount, 1);
    });

    test('guards invalid lifecycle calls', () {
      final runtime = TuiRuntime();

      expect(() => runtime.updateRoot(const Text('x')), throwsStateError);
      runtime.mountRoot(const Text('x'));
      expect(() => runtime.mountRoot(const Text('y')), throwsStateError);

      runtime.dispose();
      expect(
        () => runtime.renderFrame(CellBuffer(const CellSize(1, 1))),
        throwsStateError,
      );
    });
  });
}

final class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

final class _CounterState extends State<_Counter> {
  var count = 0;

  void increment() => setState(() => count += 1);

  @override
  Widget build(BuildContext context) => Text('$count');
}

final class _PostFrameWidget extends StatelessWidget {
  const _PostFrameWidget({required this.onFire});

  final void Function() onFire;

  @override
  Widget build(BuildContext context) {
    TuiBinding.of(context).addPostFrameCallback((_) => onFire());
    return const Text('tick');
  }
}

String _flatten(CellBuffer buffer) {
  final out = StringBuffer();
  for (var row = 0; row < buffer.size.rows; row++) {
    if (row > 0) out.writeln();
    for (var col = 0; col < buffer.size.cols; col++) {
      final cell = buffer.atColRow(col, row);
      final grapheme = cell.grapheme;
      out.write(grapheme == null || grapheme.isEmpty ? '·' : grapheme);
    }
  }
  return out.toString();
}
