// Deterministic tests for FrameScheduler: coalescing + the opt-in frame-rate
// cap. A fake clock and a fake flush scheduler drive timing synchronously.

import '../support/harness.dart' show FakeClock;
import 'package:fleury/fleury_host.dart' show FrameScheduler;
import 'package:test/test.dart';

/// Captures the single pending (delay, flush) and lets the test fire it.
class _FakeFlush {
  Duration? delay;
  void Function()? _cb;

  void Function() schedule(Duration d, void Function() cb) {
    delay = d;
    _cb = cb;
    return () {
      if (!identical(_cb, cb)) return;
      _cb = null;
      delay = null;
    };
  }

  bool get pending => _cb != null;

  void fire() {
    final cb = _cb!;
    _cb = null;
    delay = null;
    cb();
  }
}

void main() {
  group(
    'FrameScheduler — uncapped (Duration.zero) preserves current behavior',
    () {
      test('a single request flushes once, asap', () {
        final clock = FakeClock();
        final flush = _FakeFlush();
        final reasons = <String>[];
        final s = FrameScheduler(
          clock: clock,
          onRender: reasons.add,
          flushScheduler: flush.schedule,
        );

        s.requestFrame('build');
        expect(flush.delay, Duration.zero, reason: 'no cap → asap');
        expect(s.hasPendingFrame, isTrue);
        flush.fire();
        expect(reasons, ['build']);
        expect(s.hasPendingFrame, isFalse);
      });

      test('requests before the flush coalesce into one, merging reasons', () {
        final clock = FakeClock();
        final flush = _FakeFlush();
        final reasons = <String>[];
        final s = FrameScheduler(
          clock: clock,
          onRender: reasons.add,
          flushScheduler: flush.schedule,
        );

        s.requestFrame('build');
        s.requestFrame('post-frame');
        s.requestFrame('build'); // dedup
        flush.fire();
        expect(reasons, ['build+post-frame']);
      });
    },
  );

  group('FrameScheduler — capped at 16ms coalesces bursts', () {
    FrameScheduler make(FakeClock clock, _FakeFlush flush, List<String> out) =>
        FrameScheduler(
          clock: clock,
          onRender: out.add,
          minFrameInterval: const Duration(milliseconds: 16),
          flushScheduler: flush.schedule,
        );

    test('first frame renders immediately; one render per interval after', () {
      final clock = FakeClock();
      final flush = _FakeFlush();
      final out = <String>[];
      final s = make(clock, flush, out);

      // First frame: never rendered → asap.
      s.requestFrame('initial');
      expect(flush.delay, Duration.zero);
      flush.fire();
      expect(out, ['initial']);

      // A burst 4ms later: 10 updates within the interval window.
      clock.advance(const Duration(milliseconds: 4));
      for (var i = 0; i < 10; i++) {
        s.requestFrame('build');
      }
      // Deferred to the trailing edge: 16 - 4 = 12ms, and only ONE flush is
      // pending for the whole burst.
      expect(flush.delay, const Duration(milliseconds: 12));
      expect(s.hasPendingFrame, isTrue);

      clock.advance(const Duration(milliseconds: 12));
      flush.fire();
      expect(out, [
        'initial',
        'build',
      ], reason: '10 updates coalesced into a single render');
    });

    test('a request after the interval has elapsed renders immediately', () {
      final clock = FakeClock();
      final flush = _FakeFlush();
      final out = <String>[];
      final s = make(clock, flush, out);

      s.requestFrame('a');
      flush.fire();

      clock.advance(const Duration(milliseconds: 20)); // > interval
      s.requestFrame('b');
      expect(flush.delay, Duration.zero, reason: 'enough time elapsed');
      flush.fire();
      expect(out, ['a', 'b']);
    });
  });

  test('dispose makes further requests no-ops', () {
    final clock = FakeClock();
    final flush = _FakeFlush();
    final out = <String>[];
    final s = FrameScheduler(
      clock: clock,
      onRender: out.add,
      flushScheduler: flush.schedule,
    );
    s.dispose();
    s.requestFrame('build');
    expect(flush.pending, isFalse);
    expect(out, isEmpty);
  });

  test('dispose cancels an already scheduled delayed flush', () {
    final clock = FakeClock();
    final flush = _FakeFlush();
    final s = FrameScheduler(
      clock: clock,
      onRender: (_) {},
      minFrameInterval: const Duration(seconds: 1),
      flushScheduler: flush.schedule,
    );

    s.requestFrame('first');
    flush.fire();
    clock.advance(const Duration(milliseconds: 1));
    s.requestFrame('delayed');
    expect(flush.pending, isTrue);

    s.dispose();
    expect(flush.pending, isFalse, reason: 'the scheduler releases its timer');
    expect(s.hasPendingFrame, isFalse);
  });
}
