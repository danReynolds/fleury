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

    testWidgets(
      'a GestureDetector inside a cached boundary still fires on cache-hit',
      (tester) {
        // Pointer hit-testing is fed by paint-order registration, and a
        // cache-hit skips the subtree paint — so without the boundary
        // replaying its captured pointer regions, an interactive widget
        // inside a cached item (a button in a list row) would silently go
        // dead the moment the boundary stops repainting.
        var taps = 0;
        final sibling = GlobalKey<_CounterState>();
        tester.pumpWidget(
          Column(
            children: [
              RepaintBoundary(
                child: GestureDetector(
                  onTap: () => taps++,
                  child: const Text('tap me'),
                ),
              ),
              _Counter(key: sibling),
            ],
          ),
        );
        const size = CellSize(20, 2);
        tester.render(size: size); // frame 1: paints + registers the region

        // A sibling changes; the boundary's own content does not, so the next
        // frame is a cache-hit — the frame that drops the region without the
        // replay fix.
        sibling.currentState!.bump();
        tester.render(size: size);

        // Click the region that now exists only because the boundary replayed
        // it. down + up over the same cell = a tap.
        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: 2,
            row: 0,
          ),
        );
        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.up,
            button: MouseButton.left,
            col: 2,
            row: 0,
          ),
        );
        expect(
          taps,
          1,
          reason:
              'the boundary must replay pointer regions on cache-hit — '
              'without it the GestureDetector is dead once cached',
        );
      },
    );

    testWidgets('a change under an INNER boundary refreshes the OUTER cache', (
      tester,
    ) {
      // An outer boundary's cached blit embeds the inner boundary's painted
      // cells, so a change under the inner must dirty the outer too — else the
      // outer cache-hits and blits stale content (and, with pointer/semantic
      // replay, re-registers regions from a subtree that has since changed).
      final inner = GlobalKey<_CounterState>();
      tester.pumpWidget(
        RepaintBoundary(
          child: RepaintBoundary(child: _Counter(key: inner)),
        ),
      );
      const size = CellSize(12, 1);
      expect(tester.renderToString(size: size).trim(), 'count=0');

      inner.currentState!.bump();
      tester.pump();
      expect(
        tester.renderToString(size: size).trim(),
        'count=1',
        reason:
            'the inner change must reach the screen through the outer '
            'boundary — marking only the nearest boundary leaves it stale',
      );
    });

    testWidgets('a removed inner region does not keep firing via the outer', (
      tester,
    ) {
      // The input counterpart of the staleness bug: without dirtying the outer,
      // a GestureDetector removed inside an inner boundary would keep firing
      // its captured onTap when the outer replays its stale regions.
      var taps = 0;
      final toggle = GlobalKey<_ToggleState>();
      tester.pumpWidget(
        RepaintBoundary(
          child: RepaintBoundary(
            child: _Toggle(key: toggle, onTap: () => taps++),
          ),
        ),
      );
      const size = CellSize(12, 1);
      tester.render(size: size); // region present + captured

      toggle.currentState!.hide(); // remove the GestureDetector
      tester.render(size: size); // outer must refresh, dropping the region

      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: 1,
          row: 0,
        ),
      );
      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: 1,
          row: 0,
        ),
      );
      expect(
        taps,
        0,
        reason:
            'a removed region must not keep firing through a stale outer cache',
      );
    });
  });
}

class _Toggle extends StatefulWidget {
  const _Toggle({super.key, required this.onTap});
  final void Function() onTap;
  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool _shown = true;
  void hide() => setState(() => _shown = false);
  @override
  Widget build(BuildContext context) => _shown
      ? GestureDetector(onTap: widget.onTap, child: const Text('hit'))
      : const Text('gone');
}
