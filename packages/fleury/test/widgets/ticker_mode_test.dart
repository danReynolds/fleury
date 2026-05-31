// Tests for TickerMode + AnimationPolicy + Ticker.muted
// integration. FakeClock-driven per RFC §21.1.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

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

class _Bouncing extends StatefulWidget {
  const _Bouncing();

  @override
  State<_Bouncing> createState() => BouncingState();
}

class BouncingState extends State<_Bouncing>
    with SingleTickerProviderStateMixin {
  int tickCount = 0;
  Duration lastElapsed = Duration.zero;
  Ticker? exposedTicker;

  @override
  Widget build(BuildContext context) {
    exposedTicker ??= createTicker((elapsed) {
      tickCount += 1;
      lastElapsed = elapsed;
    })..start();
    return const Text('bounce');
  }
}

void main() {
  group('Ticker.muted', () {
    test('muted ticker still gets scheduler ticks but skips callback', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      var fires = 0;
      Duration? observed;
      final ticker = Ticker((e) {
        fires += 1;
        observed = e;
      }, scheduler: scheduler)..start();

      ticker.muted = true;
      scheduler.advance(const Duration(milliseconds: 100));
      expect(fires, 0, reason: 'muted: user callback suppressed');
      expect(
        ticker.lastElapsed,
        const Duration(milliseconds: 100),
        reason: 'muted: elapsed time still advances',
      );

      ticker.muted = false;
      scheduler.advance(const Duration(milliseconds: 50));
      expect(fires, 1, reason: 'unmuted: callback fires next tick');
      expect(
        observed,
        const Duration(milliseconds: 150),
        reason:
            'unmuted: lands at current clock-relative value, '
            'not at where it was when muted',
      );
    });

    test('muting partway through preserves elapsed-time history', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final samples = <Duration>[];
      final ticker = Ticker((e) => samples.add(e), scheduler: scheduler)
        ..start();

      scheduler.advance(const Duration(milliseconds: 33));
      scheduler.advance(const Duration(milliseconds: 33));
      expect(samples.length, 2);

      ticker.muted = true;
      scheduler.advance(const Duration(milliseconds: 33));
      expect(samples.length, 2, reason: 'no callback during mute');

      ticker.muted = false;
      scheduler.advance(const Duration(milliseconds: 33));
      expect(samples.length, 3);
      expect(
        samples.last,
        const Duration(milliseconds: 132),
        reason: 'elapsed continues to track total clock time',
      );
    });
  });

  group('TickerMode widget', () {
    test('default (no enclosing TickerMode) is enabled', () {
      final owner = BuildOwner();
      bool? observed;
      owner.mountRoot(
        _Builder(
          builder: (ctx) {
            observed = TickerMode.enabledOf(ctx);
            return const Text('t');
          },
        ),
      );
      expect(observed, isTrue);
    });

    test('enabledOf reflects the nearest ancestor', () {
      final owner = BuildOwner();
      bool? observed;
      owner.mountRoot(
        TickerMode(
          enabled: false,
          child: _Builder(
            builder: (ctx) {
              observed = TickerMode.enabledOf(ctx);
              return const Text('t');
            },
          ),
        ),
      );
      expect(observed, isFalse);
    });
  });

  group('SingleTickerProviderStateMixin + TickerMode', () {
    test('mute propagates from TickerMode to the Ticker on first build', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final binding = TuiBinding(tickerScheduler: scheduler);
      final owner = BuildOwner();
      final root = owner.mountRoot(
        TuiBindingScope(
          binding: binding,
          child: const TickerMode(enabled: false, child: _Bouncing()),
        ),
      );
      final state = _findState<BouncingState>(root);
      expect(
        state.exposedTicker!.muted,
        isTrue,
        reason: 'enclosed in TickerMode(enabled: false)',
      );

      scheduler.advance(const Duration(milliseconds: 100));
      expect(
        state.tickCount,
        0,
        reason: 'muted ticker should not fire its callback',
      );
      binding.dispose();
    });

    test('flipping TickerMode triggers didChangeDependencies and '
        'unmutes the ticker', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final binding = TuiBinding(tickerScheduler: scheduler);
      final owner = BuildOwner();
      final root = owner.mountRoot(
        TuiBindingScope(
          binding: binding,
          child: const TickerMode(enabled: true, child: _Bouncing()),
        ),
      );
      final state = _findState<BouncingState>(root);
      expect(state.exposedTicker!.muted, isFalse);

      // Tick once unmuted to establish the elapsed-time baseline.
      scheduler.advance(const Duration(milliseconds: 33));
      expect(state.tickCount, 1);

      // Swap to a muted TickerMode by rebuilding the root.
      owner.updateRoot(
        root,
        TuiBindingScope(
          binding: binding,
          child: const TickerMode(enabled: false, child: _Bouncing()),
        ),
      );
      expect(
        state.exposedTicker!.muted,
        isTrue,
        reason: 'didChangeDependencies should re-read TickerMode',
      );

      scheduler.advance(const Duration(milliseconds: 100));
      expect(state.tickCount, 1, reason: 'muted: no callback');

      // Re-enable.
      owner.updateRoot(
        root,
        TuiBindingScope(
          binding: binding,
          child: const TickerMode(enabled: true, child: _Bouncing()),
        ),
      );
      expect(state.exposedTicker!.muted, isFalse);
      scheduler.advance(const Duration(milliseconds: 33));
      expect(state.tickCount, 2, reason: 'unmute: callback resumes');
      expect(
        state.lastElapsed,
        const Duration(milliseconds: 33 + 100 + 33),
        reason:
            'elapsed lands at total clock-relative time, '
            'not the value when muted',
      );
      binding.dispose();
    });
  });

  group('AnimationPolicy plumbing', () {
    test('AnimationPolicy.disabled mutes all created tickers', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final binding = TuiBinding(
        tickerScheduler: scheduler,
        animationPolicy: AnimationPolicy.disabled,
      );
      final owner = BuildOwner();
      final root = owner.mountRoot(
        TuiBindingScope(binding: binding, child: const _Bouncing()),
      );
      final state = _findState<BouncingState>(root);
      expect(
        state.exposedTicker!.muted,
        isTrue,
        reason: 'AnimationPolicy.disabled mutes new tickers',
      );
      scheduler.advance(const Duration(milliseconds: 100));
      expect(state.tickCount, 0);
      binding.dispose();
    });

    test('AnimationPolicy.enabled is the default', () {
      final binding = TuiBinding();
      expect(binding.animationPolicy, AnimationPolicy.enabled);
      binding.dispose();
    });

    test('AnimationPolicy.reduced does NOT mute (functional '
        'affordances continue)', () {
      // Reduced is a hint for individual widgets to shorten or skip
      // decorative transitions; it doesn't suppress callbacks at
      // the Ticker level. (Honored by Animation: reduced shortens
      // spring response / curve duration.)
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final binding = TuiBinding(
        tickerScheduler: scheduler,
        animationPolicy: AnimationPolicy.reduced,
      );
      final owner = BuildOwner();
      final root = owner.mountRoot(
        TuiBindingScope(binding: binding, child: const _Bouncing()),
      );
      final state = _findState<BouncingState>(root);
      expect(state.exposedTicker!.muted, isFalse);
      scheduler.advance(const Duration(milliseconds: 33));
      expect(state.tickCount, 1);
      binding.dispose();
    });
  });
}

class _Builder extends StatelessWidget {
  const _Builder({required this.builder});
  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) => builder(context);
}
