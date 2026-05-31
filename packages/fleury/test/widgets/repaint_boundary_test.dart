import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

class _Counter extends StatefulWidget {
  const _Counter({super.key});
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  void bump() => setState(() => count++);
  @override
  Widget build(BuildContext context) => Text('count=$count');
}

void main() {
  group('RepaintBoundary', () {
    testWidgets('produces identical rendered output to its child', (tester) {
      const size = CellSize(40, 3);
      tester.pumpWidget(
        const Column(children: [Text('alpha'), Text('beta'), Text('gamma')]),
      );
      final without = tester.renderToString(size: size);

      tester.pumpWidget(
        const RepaintBoundary(
          child: Column(children: [Text('alpha'), Text('beta'), Text('gamma')]),
        ),
      );
      final wrapped = tester.renderToString(size: size);

      expect(
        wrapped,
        without,
        reason: 'a boundary must be transparent to its viewer',
      );
    });

    testWidgets('invalidates its cache when a wrapped widget rebuilds', (
      tester,
    ) {
      final key = GlobalKey<_CounterState>();
      tester.pumpWidget(RepaintBoundary(child: _Counter(key: key)));
      expect(
        tester.renderToString(size: const CellSize(12, 1)).trim(),
        'count=0',
      );

      key.currentState!.bump();
      tester.pump();
      expect(
        tester.renderToString(size: const CellSize(12, 1)).trim(),
        'count=1',
        reason: 'setState inside the boundary must invalidate the cache',
      );
    });

    testWidgets(
      'holds its cached output stable when a sibling outside it rebuilds',
      (tester) {
        final sibling = GlobalKey<_CounterState>();
        tester.pumpWidget(
          Column(
            children: [
              const RepaintBoundary(child: Text('static')),
              _Counter(key: sibling),
            ],
          ),
        );
        const size = CellSize(12, 2);
        expect(
          tester.renderToString(size: size),
          tester.renderToString(size: size),
          reason: 'initial output is deterministic',
        );

        // Sibling changes, boundary's contents do not.
        sibling.currentState!.bump();
        tester.pump();
        final out = tester.renderToString(size: size);
        expect(out.contains('static'), isTrue);
        expect(out.contains('count=1'), isTrue);
      },
    );
  });
}
