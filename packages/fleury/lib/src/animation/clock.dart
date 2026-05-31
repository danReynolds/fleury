// Clock: monotonic time source for the animation system.
//
// All elapsed-time math in the animation layer reads from a Clock
// rather than `DateTime.now()` or `Stopwatch` directly. This makes
// every layer above (Ticker, TickerScheduler, Animation)
// deterministically testable via FakeClock — animation tests never
// touch real wallclock.
//
// Two implementations:
//
//   - SystemClock: backed by a process-wide Stopwatch (monotonic;
//     unaffected by system clock changes).
//   - FakeClock: caller-driven via advance() / set(), for tests.

import 'package:meta/meta.dart';

/// Abstract source of monotonic elapsed time.
///
/// "Now" is a `Duration` since some implementation-defined epoch.
/// The epoch is not meaningful — only differences between two
/// readings are. Implementations must guarantee monotonic non-
/// decrease: a later call to [now] must return a value >= the
/// value returned by an earlier call.
abstract interface class Clock {
  Duration get now;
}

/// The default real-time [Clock] used outside of tests. Backed by a
/// single process-wide [Stopwatch] started lazily on first read.
///
/// Multiple [SystemClock] instances share the same underlying
/// Stopwatch — only the delta between readings matters in
/// animation math, so a shared epoch is correct.
@immutable
final class SystemClock implements Clock {
  const SystemClock();

  static final Stopwatch _stopwatch = Stopwatch()..start();

  @override
  Duration get now => _stopwatch.elapsed;
}

/// A [Clock] whose value is advanced by the caller. Used everywhere
/// in animation tests; never use [SystemClock] in tests.
///
/// ```dart
/// final clock = FakeClock();
/// // ... wire clock into a TickerScheduler / Ticker / etc.
/// clock.advance(const Duration(milliseconds: 100));
/// // any ticker is now 100ms further along its timeline.
/// ```
final class FakeClock implements Clock {
  FakeClock([Duration initial = Duration.zero]) : _now = initial;

  Duration _now;

  @override
  Duration get now => _now;

  /// Advances the clock by [delta]. Asserts [delta] is non-negative
  /// to preserve the monotonic-time invariant.
  void advance(Duration delta) {
    assert(
      !delta.isNegative,
      'FakeClock.advance requires a non-negative delta; '
      'monotonic time cannot move backwards.',
    );
    _now += delta;
  }

  /// Sets the clock to [time]. Asserts that the new value is at
  /// least as large as the current value.
  void set(Duration time) {
    assert(
      time >= _now,
      'FakeClock.set requires the new time to be >= current; '
      'monotonic time cannot move backwards.',
    );
    _now = time;
  }
}
