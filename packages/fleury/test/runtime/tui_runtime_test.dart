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

    test('does not retake a GlobalKey from another runtime', () {
      final key = GlobalKey<_CounterState>();
      final first = TuiRuntime();
      final second = TuiRuntime();

      first.mountRoot(Column(children: [_Counter(key: key)]));
      final firstState = key.currentState!;
      firstState.increment();

      expect(
        () => second.mountRoot(Column(children: [_Counter(key: key)])),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('cannot cross BuildOwner boundaries'),
          ),
        ),
      );

      expect(
        key.currentState,
        same(firstState),
        reason: 'the failed second mount must not steal the first State',
      );
      first.renderFrame(CellBuffer(const CellSize(5, 1)));
      expect(firstState.count, 1);

      // A failed mount never becomes the second runtime's root, and both
      // runtimes remain independently disposable.
      expect(second.rootElement, isNull);
      second.dispose();
      first.dispose();
      expect(key.currentState, isNull);
    });

    test(
      'dispose finishes siblings and services after State.dispose throws',
      () {
        final log = <String>[];
        final throwingKey = GlobalKey<_DisposeProbeState>();
        final siblingKey = GlobalKey<_DisposeProbeState>();
        final pointerRouter = _TrackingPointerRouter();
        final focusManager = _TrackingFocusManager();
        final binding = _TrackingBinding();
        final runtime = TuiRuntime(
          pointerRouter: pointerRouter,
          focusManager: focusManager,
          binding: binding,
        );

        runtime.mountRoot(
          Column(
            children: [
              _DisposeProbe(
                key: throwingKey,
                label: 'throwing',
                log: log,
                throwOnDispose: true,
              ),
              _DisposeProbe(key: siblingKey, label: 'sibling', log: log),
            ],
          ),
        );
        final throwingState = throwingKey.currentState!;
        final siblingState = siblingKey.currentState!;

        expect(
          runtime.dispose,
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'message',
              contains('dispose-throwing'),
            ),
          ),
        );

        expect(log, ['throwing', 'sibling']);
        expect(throwingState.mounted, isFalse);
        expect(siblingState.mounted, isFalse);
        expect(throwingKey.currentState, isNull);
        expect(siblingKey.currentState, isNull);
        expect(runtime.rootElement, isNull);
        expect(runtime.owner.root, isNull);
        expect(pointerRouter.wasDisposed, isTrue);
        expect(focusManager.wasDisposed, isTrue);
        expect(binding.wasDisposed, isTrue);

        // Idempotence is preserved: the already-surfaced user error does not
        // leave a half-live runtime that throws again on host cleanup.
        expect(runtime.dispose, returnsNormally);
      },
    );

    test('dispose releases pointer regions and captured targets', () {
      final log = <String>[];
      final runtime = TuiRuntime();
      final router = runtime.pointerRouter;
      runtime.mountRoot(
        PointerRouterScope(
          router: router,
          child: MouseRegion(
            onEnter: () => log.add('enter'),
            onExit: () => log.add('exit'),
            onHover: (col, row) => log.add('hover:$col,$row'),
            child: GestureDetector(
              onTap: () => log.add('tap'),
              onDragStart: (col, row) => log.add('drag-start'),
              onDragEnd: () => log.add('drag-end'),
              child: const SizedBox(width: 5, height: 1, child: Text('hit')),
            ),
          ),
        ),
      );
      runtime.renderFrame(CellBuffer(const CellSize(5, 1)));

      expect(
        router.route(
          const MouseEvent(
            kind: MouseEventKind.moved,
            button: MouseButton.none,
            col: 1,
            row: 0,
          ),
        ),
        isTrue,
      );
      // Arm both the tap and drag targets without completing either gesture.
      expect(
        router.route(
          const MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: 1,
            row: 0,
          ),
        ),
        isTrue,
      );
      expect(log, ['enter', 'hover:1,0']);

      runtime.dispose();

      for (final event in const [
        MouseEvent(
          kind: MouseEventKind.drag,
          button: MouseButton.left,
          col: 2,
          row: 0,
        ),
        MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: 2,
          row: 0,
        ),
        MouseEvent(
          kind: MouseEventKind.moved,
          button: MouseButton.none,
          col: 4,
          row: 0,
        ),
      ]) {
        expect(router.route(event), isFalse);
      }
      expect(router.focusAbsorbedAt(1, 0), isFalse);
      expect(log, [
        'enter',
        'hover:1,0',
      ], reason: 'dispose must not call stale hover/tap/drag callbacks');
      expect(runtime.dispose, returnsNormally);
    });

    test('dispose surfaces every independent State.dispose failure', () {
      final log = <String>[];
      final firstKey = GlobalKey<_DisposeProbeState>();
      final secondKey = GlobalKey<_DisposeProbeState>();
      final runtime = TuiRuntime();
      runtime.mountRoot(
        Column(
          children: [
            _DisposeProbe(
              key: firstKey,
              label: 'first',
              log: log,
              throwOnDispose: true,
            ),
            _DisposeProbe(
              key: secondKey,
              label: 'second',
              log: log,
              throwOnDispose: true,
            ),
          ],
        ),
      );

      expect(
        runtime.dispose,
        throwsA(
          predicate<Object>((error) {
            final message = error.toString();
            return message.contains('dispose-first') &&
                message.contains('dispose-second');
          }, 'an aggregate containing both dispose failures'),
        ),
      );
      expect(log, ['first', 'second']);
      expect(firstKey.currentState, isNull);
      expect(secondKey.currentState, isNull);
      expect(runtime.owner.root, isNull);
    });

    test('failed incompatible root replacement clears both root pointers', () {
      final log = <String>[];
      final key = GlobalKey<_DisposeProbeState>();
      final runtime = TuiRuntime();
      runtime.mountRoot(
        _DisposeProbe(
          key: key,
          label: 'old-root',
          log: log,
          throwOnDispose: true,
        ),
      );
      final oldState = key.currentState!;

      expect(
        () => runtime.updateRoot(const Text('replacement')),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('dispose-old-root'),
          ),
        ),
      );

      expect(log, ['old-root']);
      expect(oldState.mounted, isFalse);
      expect(key.currentState, isNull);
      expect(runtime.rootElement, isNull);
      expect(runtime.owner.root, isNull);
      expect(
        () => runtime.renderFrame(CellBuffer(const CellSize(5, 1))),
        throwsStateError,
        reason: 'the runtime must not try to render the defunct old root',
      );

      // With both pointers coherent, the host can recover by mounting a fresh
      // root instead of being wedged between "already mounted" states.
      runtime.mountRoot(const Text('fresh'));
      final buffer = CellBuffer(const CellSize(5, 1));
      runtime.renderFrame(buffer);
      expect(_flatten(buffer), 'fresh');
      runtime.dispose();
    });

    test('failed initial mount rolls back earlier siblings and recovers', () {
      final log = <String>[];
      final earlyKey = GlobalKey<_DisposeProbeState>();
      _DisposeProbeState? earlyState;
      final runtime = TuiRuntime();

      expect(
        () => runtime.mountRoot(
          Column(
            children: [
              _DisposeProbe(key: earlyKey, label: 'early', log: log),
              _ThrowingInitProbe(
                log: log,
                beforeThrow: () => earlyState = earlyKey.currentState,
              ),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('init-boom'),
          ),
        ),
      );

      expect(log, ['throwing-init', 'early']);
      expect(earlyState, isNotNull);
      expect(earlyState!.mounted, isFalse);
      expect(earlyKey.currentState, isNull);
      expect(runtime.rootElement, isNull);
      expect(runtime.owner.root, isNull);
      expect(runtime.owner.hasScheduledBuilds, isFalse);
      expect(runtime.owner.drainInactiveElements, returnsNormally);
      expect(log, ['throwing-init', 'early']);

      // Reusing the same GlobalKey proves the failed tree deregistered it, and
      // a fresh render proves neither owner nor runtime stayed wedged.
      runtime.mountRoot(
        _DisposeProbe(key: earlyKey, label: 'recovered', log: log),
      );
      expect(earlyKey.currentState, isNot(same(earlyState)));
      final buffer = CellBuffer(const CellSize(10, 1));
      runtime.renderFrame(buffer);
      expect(_flatten(buffer), 'recovered·');
      runtime.dispose();
      expect(log, ['throwing-init', 'early', 'recovered']);
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

final class _DisposeProbe extends StatefulWidget {
  const _DisposeProbe({
    super.key,
    required this.label,
    required this.log,
    this.throwOnDispose = false,
  });

  final String label;
  final List<String> log;
  final bool throwOnDispose;

  @override
  State<_DisposeProbe> createState() => _DisposeProbeState();
}

final class _DisposeProbeState extends State<_DisposeProbe> {
  @override
  Widget build(BuildContext context) => Text(widget.label);

  @override
  void dispose() {
    widget.log.add(widget.label);
    super.dispose();
    if (widget.throwOnDispose) throw StateError('dispose-${widget.label}');
  }
}

final class _ThrowingInitProbe extends StatefulWidget {
  const _ThrowingInitProbe({required this.log, required this.beforeThrow});

  final List<String> log;
  final void Function() beforeThrow;

  @override
  State<_ThrowingInitProbe> createState() => _ThrowingInitProbeState();
}

final class _ThrowingInitProbeState extends State<_ThrowingInitProbe> {
  @override
  void initState() {
    super.initState();
    widget.beforeThrow();
    throw StateError('init-boom');
  }

  @override
  Widget build(BuildContext context) => const Text('unreachable');

  @override
  void dispose() {
    widget.log.add('throwing-init');
    super.dispose();
  }
}

final class _TrackingPointerRouter extends PointerRouter {
  var wasDisposed = false;

  @override
  void dispose() {
    wasDisposed = true;
    super.dispose();
  }
}

final class _TrackingFocusManager extends FocusManager {
  var wasDisposed = false;

  @override
  void dispose() {
    wasDisposed = true;
    super.dispose();
  }
}

final class _TrackingBinding extends TuiBinding {
  var wasDisposed = false;

  @override
  void dispose() {
    wasDisposed = true;
    super.dispose();
  }
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
