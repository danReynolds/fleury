// Tests for TuiBinding, TuiBindingScope, and
// SingleTickerProviderStateMixin. FakeClock-driven.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

Matcher _stateError(String message) => throwsA(
  isA<StateError>().having((error) => error.message, 'message', message),
);

/// Walks the subtree under [root] looking for the first State whose
/// runtimeType matches [T]. Returned for tests that need to poke a
/// State after mount.
T _findState<T extends State>(Element root) {
  T? found;
  void visit(Element e) {
    if (found != null) return;
    if (e is StatefulElement && e.state is T) {
      found = e.state as T;
      return;
    }
    e.visitChildren(visit);
  }

  visit(root);
  if (found == null) {
    throw StateError('No $T below this element.');
  }
  return found!;
}

class _AnimatedDot extends StatefulWidget {
  const _AnimatedDot();

  @override
  State<_AnimatedDot> createState() => AnimatedDotState();
}

class AnimatedDotState extends State<_AnimatedDot>
    with SingleTickerProviderStateMixin {
  Ticker? exposedTicker;
  int tickCount = 0;
  Duration lastElapsed = Duration.zero;

  @override
  Widget build(BuildContext context) {
    exposedTicker ??= createTicker((elapsed) {
      tickCount += 1;
      lastElapsed = elapsed;
      setState(() {});
    })..start();
    return Text('tick=$tickCount');
  }
}

void main() {
  group('TuiBinding', () {
    test('TuiBinding() creates its own scheduler', () {
      final binding = TuiBinding();
      expect(binding.tickerScheduler, isNotNull);
      binding.dispose();
    });

    test('TuiBinding(tickerScheduler:) uses the supplied scheduler', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final binding = TuiBinding(tickerScheduler: scheduler);
      expect(identical(binding.tickerScheduler, scheduler), isTrue);
      binding.dispose();
    });

    test('createTicker hands back a Ticker bound to the scheduler', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final binding = TuiBinding(tickerScheduler: scheduler);
      final ticker = binding.createTicker((_) {});
      ticker.start();
      expect(scheduler.activeTickerCount, 1);
      ticker.dispose();
      expect(scheduler.activeTickerCount, 0);
      binding.dispose();
    });

    test('dispose disposes the underlying scheduler', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final binding = TuiBinding(tickerScheduler: scheduler);
      // Register a ticker before disposing.
      scheduler.register((_) {});
      binding.dispose();
      expect(scheduler.activeTickerCount, 0);
      expect(scheduler.isActive, isFalse);
    });

    test('dispose is idempotent and blocks new binding work', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final binding = TuiBinding(tickerScheduler: scheduler);

      binding.dispose();
      binding.dispose();

      expect(() => binding.flushPostFrameCallbacks(clock.now), returnsNormally);
      expect(
        () => binding.createTicker((_) {}),
        _stateError('TuiBinding has been disposed.'),
      );
      expect(
        () => binding.addPostFrameCallback((_) {}),
        _stateError('TuiBinding has been disposed.'),
      );
      expect(
        () => scheduler.register((_) {}),
        _stateError('TickerScheduler has been disposed.'),
      );
    });
  });

  group('TuiBinding.of', () {
    test('finds the binding from a descendant context', () {
      final binding = TuiBinding();
      TuiBinding? found;
      final owner = BuildOwner();
      owner.mountRoot(
        TuiBindingScope(
          binding: binding,
          child: Builder(
            builder: (ctx) {
              found = TuiBinding.of(ctx);
              return const Text('hi');
            },
          ),
        ),
      );
      expect(identical(found, binding), isTrue);
      binding.dispose();
    });

    test('throws when no binding is installed', () {
      final owner = BuildOwner();
      Object? caught;
      owner.mountRoot(
        Builder(
          builder: (ctx) {
            try {
              TuiBinding.of(ctx);
            } catch (e) {
              caught = e;
            }
            return const Text('hi');
          },
        ),
      );
      expect(caught, isA<StateError>());
    });

    test('maybeOf returns null when no binding is installed', () {
      final owner = BuildOwner();
      TuiBinding? observed = TuiBinding(); // sentinel
      owner.mountRoot(
        Builder(
          builder: (ctx) {
            observed = TuiBinding.maybeOf(ctx);
            return const Text('hi');
          },
        ),
      );
      expect(observed, isNull);
    });
  });

  group('SingleTickerProviderStateMixin', () {
    test('createTicker uses the binding scheduler from the inherited '
        'scope', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final binding = TuiBinding(tickerScheduler: scheduler);
      final owner = BuildOwner();
      final root = owner.mountRoot(
        TuiBindingScope(binding: binding, child: const _AnimatedDot()),
      );
      final state = _findState<AnimatedDotState>(root);
      // build() created the ticker on first build.
      expect(state.exposedTicker, isNotNull);
      expect(scheduler.activeTickerCount, 1);

      scheduler.advance(const Duration(milliseconds: 33));
      owner.flushBuild();
      expect(state.tickCount, 1);
      binding.dispose();
    });

    test('Ticker is disposed when the State disposes', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final binding = TuiBinding(tickerScheduler: scheduler);
      final owner = BuildOwner();
      final root = owner.mountRoot(
        TuiBindingScope(binding: binding, child: const _AnimatedDot()),
      );
      expect(scheduler.activeTickerCount, 1);

      root.unmount();
      expect(
        scheduler.activeTickerCount,
        0,
        reason: 'unmounting the State should dispose its ticker',
      );
      binding.dispose();
    });

    test('a second createTicker call asserts', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final binding = TuiBinding(tickerScheduler: scheduler);
      final owner = BuildOwner();
      final root = owner.mountRoot(
        TuiBindingScope(binding: binding, child: const _AnimatedDot()),
      );
      final state = _findState<AnimatedDotState>(root);
      expect(() => state.createTicker((_) {}), throwsA(isA<AssertionError>()));
      binding.dispose();
    });
  });
}

/// Small inline Builder convenience for tests — calls `builder`
/// from inside its own build so the closure sees its own
/// BuildContext.
class Builder extends StatelessWidget {
  const Builder({super.key, required this.builder});
  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) => builder(context);
}
