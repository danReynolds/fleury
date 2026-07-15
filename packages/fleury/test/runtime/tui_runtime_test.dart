import 'package:fleury/fleury_host.dart';
import 'package:test/test.dart';

import '../support/render_fixtures.dart';

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

    test('dispose severs host callbacks before State.dispose runs', () {
      final runtime = TuiRuntime();
      addTearDown(runtime.dispose);
      final siblingKey = GlobalKey<_CounterState>();
      final hostSignals = <String>[];

      runtime.mountRoot(
        Column(
          children: [
            _DisposeCallbackProbe(
              onDispose: () {
                // The sibling is still active while the first child disposes,
                // so this would normally transition the dirty queue from empty
                // and invoke BuildOwner.onScheduleBuild.
                siblingKey.currentState!.increment();
                runtime.binding.addPostFrameCallback((_) {});
              },
            ),
            _Counter(key: siblingKey),
          ],
        ),
      );
      runtime.owner.onScheduleBuild = () => hostSignals.add('build');
      runtime.owner.onBuildError = (_, _) => hostSignals.add('build-error');
      runtime.owner.onContainedRenderError = (_) =>
          hostSignals.add('render-error');
      runtime.binding.onPostFrameCallback = () => hostSignals.add('post-frame');

      runtime.dispose();

      expect(hostSignals, isEmpty);
      expect(runtime.owner.onScheduleBuild, isNull);
      expect(runtime.owner.onBuildError, isNull);
      expect(runtime.owner.onContainedRenderError, isNull);
      expect(runtime.binding.onPostFrameCallback, isNull);
    });

    test('dispose detaches retained elements from their BuildOwner', () {
      final runtime = TuiRuntime();
      final root = runtime.mountRoot(const Text('root'));

      runtime.dispose();

      expect(root.mounted, isFalse);
      expect(
        () => root.owner,
        throwsStateError,
        reason: 'a retained defunct BuildContext must not retain its owner',
      );
    });

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

    test('a painted frame prunes captures from removed pointer widgets', () {
      final log = <String>[];
      final runtime = TuiRuntime();
      addTearDown(runtime.dispose);
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

      runtime.updateRoot(
        PointerRouterScope(
          router: router,
          child: const SizedBox(width: 5, height: 1, child: Text('gone')),
        ),
      );

      expect(
        router.route(
          const MouseEvent(
            kind: MouseEventKind.drag,
            button: MouseButton.left,
            col: 2,
            row: 0,
          ),
        ),
        isFalse,
        reason:
            'unmount must release capture before the asynchronously scheduled '
            'replacement frame paints',
      );
      expect(log, ['enter', 'hover:1,0']);

      runtime.renderFrame(CellBuffer(const CellSize(5, 1)));

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
      expect(log, [
        'enter',
        'hover:1,0',
      ], reason: 'removed pointer widgets must not receive stale callbacks');
    });

    test('a failed update immediately detaches inactive pointer listeners', () {
      final log = <String>[];
      final runtime = TuiRuntime();
      addTearDown(runtime.dispose);
      final router = runtime.pointerRouter;
      runtime.mountRoot(
        PointerRouterScope(
          router: router,
          child: Column(
            children: [
              MouseRegion(
                onHover: (col, row) => log.add('hover:$col,$row'),
                child: const SizedBox(width: 5, height: 1, child: Text('hit')),
              ),
            ],
          ),
        ),
      );
      runtime.renderFrame(CellBuffer(const CellSize(5, 2)));

      expect(
        () => runtime.updateRoot(
          PointerRouterScope(
            router: router,
            child: Column(
              children: [
                const Text('gone'),
                _ThrowingInitProbe(log: log, beforeThrow: () {}),
              ],
            ),
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

      expect(
        router.route(
          const MouseEvent(
            kind: MouseEventKind.moved,
            button: MouseButton.none,
            col: 1,
            row: 0,
          ),
        ),
        isFalse,
      );
      expect(log, ['throwing-init']);
    });

    test('a failed paint leaves no partial pointer regions', () {
      final runtime = TuiRuntime();
      addTearDown(runtime.dispose);
      final router = runtime.pointerRouter;
      var taps = 0;
      runtime.mountRoot(
        PointerRouterScope(
          router: router,
          child: GestureDetector(
            onTap: () => taps += 1,
            child: const Boom(mode: BoomMode.paint, size: CellSize(5, 1)),
          ),
        ),
      );

      expect(
        () => runtime.renderFrame(CellBuffer(const CellSize(5, 1))),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('paint-boom'),
          ),
        ),
      );

      for (final event in const [
        MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: 1,
          row: 0,
        ),
        MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: 1,
          row: 0,
        ),
      ]) {
        expect(router.route(event), isFalse);
      }
      expect(taps, 0);
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

    test('failed child update keeps a reachable partial tree and recovers', () {
      final log = <String>[];
      final newKey = GlobalKey<_DisposeProbeState>();
      final failedKey = GlobalKey<State>();
      _DisposeProbeState? newState;
      final runtime = TuiRuntime();
      addTearDown(runtime.dispose);

      runtime.mountRoot(Column(children: const [Text('old')]));

      expect(
        () => runtime.updateRoot(
          Column(
            children: [
              _DisposeProbe(key: newKey, label: 'new', log: log),
              _ThrowingInitProbe(
                key: failedKey,
                log: log,
                beforeThrow: () => newState = newKey.currentState,
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

      expect(newState, isNotNull);
      expect(newState!.mounted, isTrue);
      expect(newKey.currentState, same(newState));
      expect(failedKey.currentState, isNull);
      expect(log, ['throwing-init']);

      // The failed attempt's GlobalKey claim must not poison this immediate
      // retry, and the successfully mounted prefix keeps its State.
      runtime.updateRoot(
        Column(
          children: [
            _DisposeProbe(key: newKey, label: 'kept', log: log),
            _DisposeProbe(key: failedKey, label: 'retry', log: log),
          ],
        ),
      );
      expect(newKey.currentState, same(newState));
      expect(failedKey.currentState, isA<_DisposeProbeState>());
      final buffer = CellBuffer(const CellSize(8, 2));
      runtime.renderFrame(buffer);
      expect(_flatten(buffer), 'kept····\nretry···');

      runtime.dispose();
      expect(log, ['throwing-init', 'kept', 'retry']);
    });

    test('throwing deactivate fails closed and leaves a recoverable tree', () {
      final log = <String>[];
      final key = GlobalKey<_ThrowingDeactivateProbeState>();
      final runtime = TuiRuntime();
      addTearDown(runtime.dispose);

      runtime.mountRoot(
        Column(
          children: [_ThrowingDeactivateProbe(key: key, log: log)],
        ),
      );
      final state = key.currentState!;

      expect(
        () => runtime.updateRoot(Column(children: const [Text('replacement')])),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('deactivate-boom'),
          ),
        ),
      );

      expect(log, ['deactivate', 'descendant', 'parent-dispose']);
      expect(state.mounted, isFalse);
      expect(key.currentState, isNull);

      runtime.updateRoot(Column(children: const [Text('recovered')]));
      final buffer = CellBuffer(const CellSize(10, 1));
      runtime.renderFrame(buffer);
      expect(_flatten(buffer), 'recovered·');
    });

    test('failed GlobalKey move preserves State for a safe retry', () {
      final log = <String>[];
      final key = GlobalKey<_ThrowingUpdateProbeState>();
      final runtime = TuiRuntime();
      addTearDown(runtime.dispose);

      runtime.mountRoot(
        Row(
          children: [
            Center(
              child: _ThrowingUpdateProbe(key: key, label: 'initial', log: log),
            ),
            const Center(child: SizedBox.shrink()),
          ],
        ),
      );
      final state = key.currentState!;

      expect(
        () => runtime.updateRoot(
          Row(
            children: [
              const Center(child: SizedBox.shrink()),
              Center(
                child: _ThrowingUpdateProbe(
                  key: key,
                  label: 'boom',
                  log: log,
                  throwOnUpdate: true,
                ),
              ),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('update-boom'),
          ),
        ),
      );

      expect(key.currentState, same(state));
      expect(key.currentContext!.mounted, isFalse);
      expect(log, ['update:boom']);

      runtime.updateRoot(
        Row(
          children: [
            Center(
              child: _ThrowingUpdateProbe(
                key: key,
                label: 'recovered',
                log: log,
              ),
            ),
            const Center(child: SizedBox.shrink()),
          ],
        ),
      );
      expect(key.currentState, same(state));
      expect(key.currentContext!.mounted, isTrue);
      final buffer = CellBuffer(const CellSize(10, 1));
      runtime.renderFrame(buffer);
      expect(_flatten(buffer), 'recovered·');
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

final class _DisposeCallbackProbe extends StatefulWidget {
  const _DisposeCallbackProbe({required this.onDispose});

  final void Function() onDispose;

  @override
  State<_DisposeCallbackProbe> createState() => _DisposeCallbackProbeState();
}

final class _DisposeCallbackProbeState extends State<_DisposeCallbackProbe> {
  @override
  Widget build(BuildContext context) => const Text('dispose-callback');

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}

final class _ThrowingInitProbe extends StatefulWidget {
  const _ThrowingInitProbe({
    super.key,
    required this.log,
    required this.beforeThrow,
  });

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

final class _ThrowingDeactivateProbe extends StatefulWidget {
  const _ThrowingDeactivateProbe({super.key, required this.log});

  final List<String> log;

  @override
  State<_ThrowingDeactivateProbe> createState() =>
      _ThrowingDeactivateProbeState();
}

final class _ThrowingDeactivateProbeState
    extends State<_ThrowingDeactivateProbe> {
  @override
  Widget build(BuildContext context) =>
      _DisposeProbe(label: 'descendant', log: widget.log);

  @override
  void deactivate() {
    widget.log.add('deactivate');
    super.deactivate();
    throw StateError('deactivate-boom');
  }

  @override
  void dispose() {
    widget.log.add('parent-dispose');
    super.dispose();
  }
}

final class _ThrowingUpdateProbe extends StatefulWidget {
  const _ThrowingUpdateProbe({
    super.key,
    required this.label,
    required this.log,
    this.throwOnUpdate = false,
  });

  final String label;
  final List<String> log;
  final bool throwOnUpdate;

  @override
  State<_ThrowingUpdateProbe> createState() => _ThrowingUpdateProbeState();
}

final class _ThrowingUpdateProbeState extends State<_ThrowingUpdateProbe> {
  @override
  void didUpdateWidget(covariant _ThrowingUpdateProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.log.add('update:${widget.label}');
    if (widget.throwOnUpdate) throw StateError('update-boom');
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
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
