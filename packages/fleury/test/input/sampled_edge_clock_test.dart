// RFC 0020 §5.6 — WHICH clock expires sampled edges, and the harness parity
// that makes the answer observable from a widget test.
//
// Edges live for exactly one latch, so the publishing clock is the expiring
// clock. Publishing at render destroys a tap whenever an unrelated frame — a
// clock in the status bar, an arriving stream value — lands between the press
// and the tick that samples it. The consumer of edges is the ticker (§7.2's
// fixed-step simulation), so the ticker owns expiry whenever one is running;
// the frame clock is the fallback for an app with no tickers at all, without
// which `wasPressed` would report a stale tap forever.
//
// None of this was reachable from a widget test until the harness stopped
// publishing the latch through a seam of its own (`TickerScheduler
// .onFrameStart`, which production had removed): renders under FleuryTester
// did not latch, so the render clock could not be caught expiring anything.

import 'package:fleury/fleury.dart';
import 'package:fleury/src/input/keyboard_state.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

/// A game loop: samples `wasPressed` from its ticker, and (like a real one)
/// renders every tick.
class _GameLoop extends StatefulWidget {
  const _GameLoop(this.onSample);
  final void Function(KeyboardSnapshot) onSample;
  @override
  State<_GameLoop> createState() => _GameLoopState();
}

class _GameLoopState extends State<_GameLoop> {
  late Keyboard _keyboard;
  Ticker? _ticker;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboard = Keyboard.of(context);
    _ticker ??= TuiBinding.of(context).createTicker((_) {
      widget.onSample(_keyboard.snapshot);
    })..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const Focus(autofocus: true, child: Text('game'));
}

void main() {
  group('the edge clock (RFC 0020 §5.6)', () {
    testWidgets('a tap survives an unrelated render before the tick', (tester) {
      tester.keyboardCapabilities = KeyboardCapabilities.full;
      final sampled = <KeyboardSnapshot>[];
      tester.pumpWidget(_GameLoop(sampled.add));
      tester.render();
      sampled.clear();

      // The tap, and then the frames it and everything else in the app
      // schedule before the game's next tick comes round.
      tester.holdKey(KeyPosition.a);
      tester.render(); // the frame the press scheduled
      tester.render(); // an unrelated frame: the clock in the status bar
      tester.pump(tester.scheduler.frameInterval); // the game's next tick

      expect(
        sampled.any((s) => s.wasPressed(KeyPosition.a)),
        isTrue,
        reason:
            'the press was destroyed by a render that had nothing to do with '
            'it — edges must expire on the clock that reads them',
      );
    });

    testWidgets('releases survive an unrelated render too', (tester) {
      tester.keyboardCapabilities = KeyboardCapabilities.full;
      final sampled = <KeyboardSnapshot>[];
      tester.pumpWidget(_GameLoop(sampled.add));
      tester.pump(tester.scheduler.frameInterval);
      tester.holdKey(KeyPosition.space);
      tester.pump(tester.scheduler.frameInterval);
      sampled.clear();

      tester.releaseKey(KeyPosition.space);
      tester.render();
      tester.render();
      tester.pump(tester.scheduler.frameInterval);

      expect(
        sampled.any((s) => s.wasReleased(KeyPosition.space)),
        isTrue,
        reason: 'a charged-shot release is an edge like any other',
      );
    });

    testWidgets('a tick expires the previous tick\'s edges', (tester) {
      tester.keyboardCapabilities = KeyboardCapabilities.full;
      final sampled = <KeyboardSnapshot>[];
      tester.pumpWidget(_GameLoop(sampled.add));
      tester.pump(tester.scheduler.frameInterval);

      tester.holdKey(KeyPosition.a);
      tester.pump(tester.scheduler.frameInterval);
      expect(sampled.last.wasPressed(KeyPosition.a), isTrue);

      sampled.clear();
      tester.pump(tester.scheduler.frameInterval);
      expect(
        sampled.every((s) => !s.wasPressed(KeyPosition.a)),
        isTrue,
        reason: 'one latch is one edge lifetime; the ticker clock is a latch',
      );
      expect(
        sampled.last.isHeld(KeyPosition.a),
        isTrue,
        reason: 'held state is not an edge and does not expire',
      );
    });

    testWidgets('with no ticker running, renders expire edges', (tester) {
      // The fallback, and why it must exist: nothing else advances the latch
      // in a ticker-free app, so without it `wasPressed` would answer true
      // forever after one press.
      tester.keyboardCapabilities = KeyboardCapabilities.full;
      tester.pumpWidget(const Focus(autofocus: true, child: Text('static')));
      expect(tester.scheduler.isActive, isFalse);

      tester.holdKey(KeyPosition.a);
      tester.render();
      expect(
        tester.dispatcher.keyboardSession.snapshot.wasPressed(KeyPosition.a),
        isTrue,
      );

      tester.render();
      expect(
        tester.dispatcher.keyboardSession.snapshot.wasPressed(KeyPosition.a),
        isFalse,
        reason: 'a ticker-free app must not report a stale tap forever',
      );
    });

    testWidgets('the live clock follows ticker registration', (tester) {
      // The handover is the part that can silently rot: read live off the
      // scheduler, never mirrored into a flag.
      tester.keyboardCapabilities = KeyboardCapabilities.full;
      final sampled = <KeyboardSnapshot>[];
      final show = ValueNotifier(true);
      tester.pumpWidget(_ToggleHost(show: show, child: _GameLoop(sampled.add)));
      tester.pump(tester.scheduler.frameInterval);
      expect(tester.scheduler.isActive, isTrue);

      // Ticker gone: the frame clock takes back over on the very next render.
      show.value = false;
      tester.pump();
      expect(tester.scheduler.isActive, isFalse);
      tester.holdKey(KeyPosition.a);
      tester.render();
      expect(
        tester.dispatcher.keyboardSession.snapshot.wasPressed(KeyPosition.a),
        isTrue,
        reason: 'nothing else is left to publish the latch',
      );
    });
  });

  group('the session arbitrates between the two clocks', () {
    KeyboardSession sessionWithTickers(bool Function() active) =>
        KeyboardSession(capabilities: KeyboardCapabilities.full)
          ..hasActiveTickers = active;

    test('the frame clock is inert while a ticker runs', () {
      final session = sessionWithTickers(() => true);
      session.ingest(const KeyEvent(KeyCode.a, position: KeyPosition.a));

      final ignored = session.publishLatch(KeyboardLatchClock.frame);
      expect(ignored.wasPressed(KeyPosition.a), isFalse);
      expect(
        session
            .publishLatch(KeyboardLatchClock.ticker)
            .wasPressed(KeyPosition.a),
        isTrue,
        reason: 'the frame clock must not have drained the edge either',
      );
    });

    test('the ticker clock is inert while no ticker runs', () {
      final session = sessionWithTickers(() => false);
      session.ingest(const KeyEvent(KeyCode.a, position: KeyPosition.a));

      expect(
        session
            .publishLatch(KeyboardLatchClock.ticker)
            .wasPressed(KeyPosition.a),
        isFalse,
      );
      expect(
        session
            .publishLatch(KeyboardLatchClock.frame)
            .wasPressed(KeyPosition.a),
        isTrue,
      );
    });

    test('a session with no scheduler behind it latches on frames', () {
      final session = KeyboardSession(capabilities: KeyboardCapabilities.full);
      session.ingest(const KeyEvent(KeyCode.a, position: KeyPosition.a));
      expect(
        session
            .publishLatch(KeyboardLatchClock.frame)
            .wasPressed(KeyPosition.a),
        isTrue,
      );
    });
  });

  group('installKeyboardLatch is the only wiring', () {
    test('wires both clocks and hands back the frame publisher', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final session = KeyboardSession(capabilities: KeyboardCapabilities.full);
      final publishFrame = installKeyboardLatch(
        session: session,
        scheduler: scheduler,
      );

      // No ticker: the frame publisher is live.
      session.ingest(const KeyEvent(KeyCode.a, position: KeyPosition.a));
      publishFrame();
      expect(session.snapshot.wasPressed(KeyPosition.a), isTrue);

      // A ticker registers: frame-start publishes, the frame clock goes inert.
      scheduler.register((_) {});
      session.ingest(const KeyEvent(KeyCode.b, position: KeyPosition.b));
      publishFrame();
      expect(
        session.snapshot.wasPressed(KeyPosition.b),
        isFalse,
        reason: 'the frame clock published while a ticker was registered',
      );
      scheduler.advanceFrame();
      expect(session.snapshot.wasPressed(KeyPosition.b), isTrue);
    });
  });
}

/// Mounts (or unmounts) [child] on a notifier, so a test can retire the only
/// ticker in the tree mid-test.
class _ToggleHost extends StatefulWidget {
  const _ToggleHost({required this.show, required this.child});
  final ValueNotifier<bool> show;
  final Widget child;
  @override
  State<_ToggleHost> createState() => _ToggleHostState();
}

class _ToggleHostState extends State<_ToggleHost> {
  @override
  void initState() {
    super.initState();
    widget.show.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    widget.show.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.show.value
      ? widget.child
      : const Focus(autofocus: true, child: Text('static'));
}
