# RFC 0010: Animation infrastructure for fleury

**Status:** Proposal (revision 3)
**Date:** 2026-05-19 (revised 2026-05-21)
**Decision point for:** the shape and scope of a terminal-native
  animation system for fleury — what to ship, what to defer,
  and what conventions to lock in.

This document proposes adding time-based animation primitives to
fleury. The framework today only renders in response to input
events or `setState` calls. Anything "alive" on screen — a cursor
blink, a network-request spinner, a progress bar that smoothly
fills — requires the application to wake the build loop manually
on a timer, which defeats the framework's reactivity model and
forces every feature to reinvent the same scheduler.

## Revision history

**Revision 3 (2026-05-21)** — Removes v0 shortcuts in favor of
the right architectural foundations:

- `TuiBinding` introduced now as the home for the scheduler (and
  the eventual home for theme / navigation / gestures), rather
  than attaching to `BuildOwner` as an interim. The "design for
  later migration" wart from revision 2 is gone.
- Implementation explicitly phased into six self-contained
  slices that each leave the suite green. Total scope is
  unchanged; the phasing makes the breadth tractable to review
  and land incrementally.
- A small handful of curves added (the common ones: ease curves
  + bounce + elastic) — they're function code, not
  architecture, and shipping a sparse Curves library forces
  apps to roll their own.
- Hot reload behavior for tickers specified.

**Revision 2 (2026-05-21)** — Incorporates peer review feedback.
The original proposal was a faithful Flutter port; the revision
restructures around two coordinated lanes — continuous tweens
(Flutter-shaped) and discrete frame animation (terminal-native)
— and adds the scheduling, lifecycle, and policy machinery
needed to make the first slice robust rather than minimal.

Material additions vs revision 1:

- Two animation lanes: continuous (`AnimationController` /
  `Animation<T>`) and discrete (`FrameTicker` / `FrameBuilder`).
- Scheduler owned by a binding type rather than process-global,
  for test isolation and clean teardown.
- Elapsed time derived from a monotonic clock, not accumulated
  frame intervals (correct behavior under stall / SSH lag).
- `TickerMode`-style subtree muting for hidden panes / tabs /
  modals.
- `AnimationPolicy` (`enabled` / `reduced` / `disabled`).
- `Ticker` has no per-instance interval; scheduler owns cadence.
- `StepTween<T>` renamed to `DiscreteTween<T>` to disambiguate
  from `Curves.steps`.
- `ColorTween` rejects indexed colors with no debug/release
  behavior divergence.
- Reference affordance widgets (`Spinner`, `BlinkingCursor`,
  `TypingIndicator`, `AnimatedProgressBar`) included to
  pressure-test the primitives.
- Revised LoC and time estimates.

## 1. Motivation

### 1.1 Use cases blocked today

Concrete things we can't express cleanly without time-based frames:

- **Cursor blink.** Universal TUI affordance. `TextInput` paints a
  static block cursor; making it blink requires a timer-driven
  rebuild we don't have.
- **Spinners.** Loading states during a network request, file IO,
  or any async operation. The conventional braille-frame spinner
  (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`) cycles at ~12 fps.
- **Progress bars with smooth value changes.** An indeterminate
  marquee bar that loops; a determinate bar that interpolates
  between values rather than snapping.
- **Typing indicators.** A `…` that cycles `   ` / `.  ` / `.. ` /
  `...` in a chat surface.
- **Toast / notification slide-in.** Optional, but common in modern
  TUIs (slide a notification in from the top of the screen across
  a few frames before settling).
- **Modal entry transitions** (also optional). Today modals appear
  instantly. A 100ms easing in feels more polished.

### 1.2 Current workaround and its cost

An app today can fake this by:

```dart
Timer.periodic(Duration(milliseconds: 100), (_) {
  setState(() { _frame++; });
});
```

This works but has real downsides:

- Every animated widget reinvents this. No coalescing across
  multiple concurrent animations: two spinners on screen mean two
  timers and two extra `setState`s per tick.
- No lifecycle integration. The timer must be cancelled in
  `dispose` or it leaks.
- No abstraction for "value over time." Tweening, easing, and
  end-of-animation detection are all hand-rolled.
- No frame-rate budget. Each timer fires independently regardless
  of whether anything else is animating.
- No subtree muting. A spinner in a hidden tab still ticks.
- No accessibility policy. There's no global lever for "reduce
  motion" or "disable decorative animation."

### 1.3 Why now

The modal slice shipped without entry transitions because we had
no animation. The chat MVP wants a "typing…" indicator and a
spinner during connection. The library is otherwise complete
enough that the "nothing time-based" gap is the next real blocker.

## 2. Positioning

The framing matters. This is **not** "port Flutter animations to
the terminal." It's:

> fleury adopts Flutter's animation architecture where it
> improves Dart developer ergonomics and lifecycle correctness,
> while adapting timing, scheduling, quantization, and discrete
> frame animation to the terminal.

Same principle as the rest of the framework: **Flutter ergonomics
above, terminal truth below.** Application authors should
recognize the model if they know Flutter. Internally the runtime
should behave like a serious terminal UI system — cell-quantized,
scheduler-consolidated, idle-efficient, deterministic under test,
robust over SSH / tmux, safe under teardown.

## 3. Background

### 3.1 Flutter

Flutter's animation layer is the best reference for the
continuous lane: `Ticker` emits frame callbacks, `TickerProvider`
ties them to widget lifecycle, `AnimationController` drives a
double over a duration, `Animation<T>` is observable state,
`Tween<T>` maps normalized progress to typed values, `Curve`
applies easing, `AnimatedBuilder` rebuilds on listenable
notifications, `TickerMode` mutes tickers in subtrees.

What to borrow:
- Lifecycle model.
- Controller / tween / curve decomposition.
- `AnimatedBuilder` consumption widget.
- `TickerProvider` and `SingleTickerProviderStateMixin`.
- Deterministic tests via fake time / fake scheduler.
- `TickerMode` subtree muting.

What not to copy blindly:
- 60 Hz assumptions.
- Pixel-smooth motion assumptions.
- Physics simulations.
- Route / hero transition machinery.
- Full implicit-animation widget stack.

### 3.2 Textual

Validates that terminal UI frameworks can and should own animation
infrastructure (`widget.animate(...)` with duration + easing,
single coordinated driver loop).

Borrow: animation as a framework responsibility, duration/easing
as first-class. Skip: CSS-like property animation as the first
slice; Python-specific implementation details.

### 3.3 ink

A production-oriented component TUI. Multiple animations
consolidate onto one timer internally; the public API exposes
frame/time/delta to consumers.

Borrow: discrete frame-counter primitive; shared-scheduler
recognition; the insight that spinners and cursors are
frame-indexed, not necessarily continuous tweens. Skip: React
hooks as the public surface.

### 3.4 ratatui

Validates the lower-level rendering model: paint into an
intermediate cell buffer, diff vs previous, flush changed cells.
Animation sits above all that.

Borrow: animation never writes directly to stdout; full-frame
cell-buffer rendering. Skip: immediate-mode as the authoring
model.

### 3.5 Bubble Tea

Time as explicit events entering the app/runtime via a `Tick`
message.

Borrow: time-as-explicit-event-in-the-loop model; the importance
of coalescing. Skip: requiring every widget to reschedule
manually.

## 4. Goals and non-goals

### 4.1 Goals

- Familiar Flutter-shaped API for Dart/Flutter developers.
- No manual `Timer.periodic` in normal widget code.
- Lifecycle-managed tickers disposed with widget state.
- **One consolidated scheduler** for all active animations.
- **Zero idle work** when no animations are active.
- Deterministic fake-time tests.
- Continuous interpolation for values that benefit from it.
- **Discrete frame animation** for terminal-native affordances.
- Cell-quantized tweens for positions and progress bars.
- **Reduced/disabled animation policy** (accessibility, CI, SSH).
- **Subtree muting** for hidden panes / tabs / modals.
- **Frame skipping / backpressure** when rendering falls behind.
- **Built-in or reference implementations** for common TUI
  animations.

### 4.2 Non-goals for the first slice

- Physics simulations (springs, friction, fling, overscroll).
- Hero animations.
- Route transition systems (we don't have a router).
- Full implicit-animation widget stack (`AnimatedContainer` etc.).
- Rich transition DSLs.
- Mouse-hover animations (folded into the mouse slice when it
  lands).
- Per-widget custom clocks (scheduler owns the cadence).
- GPU/pixel-style animation concepts.

## 5. Two animation lanes

The biggest correction vs revision 1 is recognizing that
terminal animations divide into two categories with different
profiles:

### 5.1 Continuous lane

Smooth interpolation of a value over time. Use case examples:
toast slide-in (5 cells in 200 ms), progress bar fill (0..1 in
500 ms), modal entry chrome fade.

Sampled at 30 Hz (≈33 ms/frame), driven by an
`AnimationController` with a `Curve`, consumed via
`AnimatedBuilder` reading a `Tween`.

### 5.2 Discrete lane

Low-frequency frame cycling. Use case examples: spinner (≈80–100
ms per frame), cursor blink (≈500 ms on/off), typing indicator
(≈300–500 ms per state), marquee tick.

Driven by a `FrameTicker` at its own cadence, consumed via
`FrameBuilder`. The `Ticker` underneath is the same primitive as
the continuous lane; it just registers with the scheduler at a
different interval.

### 5.3 Why split

Forcing spinners through `AnimationController` at 30 Hz means
~3× more ticks than needed (a 100 ms spinner only changes every
~3 frames). The discrete lane is the right primitive for
frame-indexed UI; the continuous lane is the right primitive for
smooth interpolation. Both share the same scheduler so there's
still exactly one timer in the runtime.

## 6. Scheduler architecture

### 6.1 `TuiBinding`

The scheduler is owned by a new `TuiBinding` type — the
fleury equivalent of Flutter's `WidgetsBinding`.

```dart
final class TuiBinding {
  TuiBinding({
    TickerScheduler? tickerScheduler,
    AnimationPolicy animationPolicy = AnimationPolicy.enabled,
    Clock clock = const SystemClock(),
  })  : _animationPolicy = animationPolicy,
        tickerScheduler =
            tickerScheduler ?? TickerScheduler(clock: clock);

  /// One scheduler per binding. Per-binding test isolation falls
  /// out automatically; no global singleton.
  final TickerScheduler tickerScheduler;

  AnimationPolicy _animationPolicy;
  AnimationPolicy get animationPolicy => _animationPolicy;
  set animationPolicy(AnimationPolicy value) { ... }

  /// Inherited lookup from any descendant context.
  static TuiBinding of(BuildContext context);
  static TuiBinding? maybeOf(BuildContext context);

  void dispose();
}
```

The binding is reachable from any `BuildContext` via a
`_TuiBindingScope` `InheritedWidget` that `runTui` installs as a
sibling of `FocusManagerScope` and `Overlay`. Tests construct a
binding directly and wrap their tree in `TuiBindingScope` — no
global state.

This is the right architectural home for several pending concerns
that share the same "per-runtime, reachable from any context,
must teardown cleanly" shape:

| Future concern | Lives on `TuiBinding` as |
| --- | --- |
| Animation scheduler (this RFC) | `tickerScheduler` |
| Animation policy (this RFC) | `animationPolicy` |
| Theme (future RFC) | `themeData` |
| Navigation / router (future RFC) | `navigator` |
| Gesture / mouse routing (future RFC) | `gestures` |
| App lifecycle / focus loss (future RFC) | `lifecycle` |

Adding `TuiBinding` now means each of these slides in without a
disruptive refactor of every call site that needs them.

Rationale for not waiting:

- Avoids the "BuildOwner.tickerScheduler" layering wart from
  revision 2.
- Tests already construct their own owner; constructing a
  binding alongside is a one-line addition to existing harnesses.
- The interface is small (constructor + scheduler + policy +
  `of`/`maybeOf`); the work is the InheritedWidget plumbing,
  which we have a clean precedent for (`FocusManagerScope`).
- The migration cost of "promote later" was real (every
  TickerProvider call site would change).

`runTui` is updated to construct a `TuiBinding` and install
`TuiBindingScope` in the root tree (alongside the existing
`FocusManagerScope` and root `Overlay`).

### 6.2 Scheduler owns frame cadence

```dart
final class TickerScheduler {
  TickerScheduler({
    Duration frameInterval = const Duration(milliseconds: 33),
    Clock clock = const SystemClock(),
  });

  void registerTicker(Ticker ticker);
  void unregisterTicker(Ticker ticker);
  bool get isActive;
}
```

Default frame interval is **30 Hz / 33 ms** for the continuous
lane. The discrete lane registers tickers with their own logical
cadence (80 ms for spinner etc.) but still tied to the
scheduler's underlying `Timer.periodic` — each `FrameTicker`
simply tracks whether enough time has elapsed since its last
emit.

Three plausible default rates:

| Rate | Pros | Cons |
| --- | --- | --- |
| 60 Hz (16 ms) | Matches Flutter | Wasteful for cell-quantized output |
| **30 Hz (33 ms)** | Smooth-enough; visually identical to 60 Hz | None significant for TUI |
| 15 Hz (66 ms) | Lowest power | Noticeable judder on continuous transitions |

**30 Hz** is the default. Discrete tickers use their own
intervals.

### 6.3 Elapsed time from monotonic clock

Animation state must be derived from elapsed monotonic time, not
accumulated frame counts.

```text
correct:   animation_value = curve(actual_elapsed / duration)
incorrect: animation_value = curve((frame_count × interval) / duration)
```

If rendering or terminal I/O is slow, the next frame samples
**current** elapsed time and skips missed visual frames. The
scheduler never queues a backlog of stale animation frames. This
matters over SSH, tmux, slow terminals, and any CPU stall.

A `Clock` interface (with `SystemClock` default and `FakeClock`
for tests) provides the monotonic time source, so tests can
advance time deterministically.

### 6.4 Zero idle work

When there are no active tickers:

```text
no Timer.periodic running
no ticker callbacks firing
no animation-scheduled frames
```

A test asserts the structural property: after stopping the last
ticker, the scheduler's internal timer is null. (Asserting
"zero CPU" is noisy and unreliable; asserting "no timer
registered" is precise.)

When the first ticker registers, the timer starts. When the last
ticker unregisters, the timer stops.

### 6.5 Test affordance

`FakeTickerScheduler` + `FakeClock` for deterministic tests. No
wall-clock dependency:

```dart
final clock = FakeClock();
final scheduler = TickerScheduler(clock: clock);
final controller = AnimationController(
  duration: const Duration(milliseconds: 100),
  vsync: TestTickerProvider(scheduler),
);
controller.forward();
clock.advance(const Duration(milliseconds: 50));
scheduler.advanceFrame();   // emits one tick
expect(controller.value, closeTo(0.5, 0.001));
```

## 7. Continuous lane

### 7.1 `Animation<T>`

```dart
abstract class Animation<T> extends Listenable {
  T get value;
  AnimationStatus get status;

  void addStatusListener(AnimationStatusListener listener);
  void removeStatusListener(AnimationStatusListener listener);
}

typedef AnimationStatusListener = void Function(AnimationStatus status);

enum AnimationStatus { dismissed, forward, reverse, completed }
```

If `status` is public, `addStatusListener` is public too —
otherwise consumers have to poll.

### 7.2 `AnimationController`

```dart
final class AnimationController extends Animation<double> {
  AnimationController({
    required Duration duration,
    required TickerProvider vsync,
    double lowerBound = 0.0,
    double upperBound = 1.0,
    Duration? reverseDuration,
    double? initialValue,
  });

  Duration duration;
  Duration? reverseDuration;

  double get value;
  set value(double v);
  AnimationStatus get status;

  TickerFuture forward({double? from});
  TickerFuture reverse({double? from});
  TickerFuture repeat({bool reverse = false, Duration? period});
  void stop({bool canceled = true});
  void reset();
  void dispose();
}
```

Behaviors to specify explicitly before implementation:

- **Bounds clamping** — `value` is always within
  `[lowerBound, upperBound]`; the setter clamps.
- **Status transition order** — `dismissed → forward → completed`
  or `completed → reverse → dismissed`; listeners fire once per
  transition.
- **Disposal** — cancels any outstanding `TickerFuture` with
  `TickerCanceled`; further calls throw.
- **`stop(canceled: true)`** — current `TickerFuture` completes
  with `TickerCanceled`. `stop(canceled: false)` — future
  completes normally.
- **`forward()` while already animating** — cancels the prior
  future, starts a new one from current `value`.
- **`duration: Duration.zero`** — synchronously snaps to
  `upperBound` and completes; listeners fire as if normal.
- **Under `AnimationPolicy.disabled`** — `forward` / `reverse` /
  `repeat` snap to their end value synchronously and complete;
  status transitions still fire.

### 7.3 `TickerFuture`

```dart
final class TickerFuture implements Future<void> {
  Future<void> get orCancel;
}

final class TickerCanceled implements Exception {
  const TickerCanceled();
  @override
  String toString() => 'TickerCanceled';
}
```

- The base future completes normally when the animation reaches
  its natural end.
- `orCancel` completes with `TickerCanceled` if the animation is
  cancelled / disposed before reaching the end.
- Starting a new animation (e.g. `forward()` mid-`reverse()`)
  cancels the prior future.

### 7.4 Curves

```dart
abstract class Curve {
  const Curve();
  double transform(double t);  // [0..1] → [0..1]
}

final class Curves {
  static const Curve linear     = LinearCurve();
  static const Curve easeIn     = EaseInCurve();
  static const Curve easeOut    = EaseOutCurve();
  static const Curve easeInOut  = EaseInOutCurve();
  static Curve steps(int count);  // for cell-quantized output
}
```

`Curves.steps(int)` snaps to one of N discrete values. Useful
when the animated value lands in integer cells and smooth
intermediate values round-trip back to a step anyway.

A `CurvedAnimation` widget composes:

```dart
CurvedAnimation(parent: controller, curve: Curves.easeOut)
```

produces a new `Animation<double>` applying the curve.

### 7.5 Tweens

```dart
abstract class Tween<T> {
  Tween({this.begin, this.end});
  T? begin;
  T? end;
  T lerp(double t);
  Animation<T> animate(Animation<double> parent);
}

class DoubleTween extends Tween<double>;
class IntTween extends Tween<int>;          // smooth-then-round
class DiscreteTween<T> extends Tween<T>;    // swap at t = 0.5
class RgbColorTween extends Tween<RgbColor>;
```

`DiscreteTween<T>` replaces revision 1's `StepTween<T>` — the
old name conflicted with `Curves.steps`.

### 7.6 Indexed colors

`AnsiColor(14)` and `AnsiColor(8)` aren't on a meaningful number
line. `RgbColorTween` only accepts `RgbColor` endpoints, enforced
by the type — `RgbColorTween({required RgbColor begin, required
RgbColor end})` simply can't accept an `AnsiColor`. No debug /
release behavior split; the type system rules it out.

For indexed-color "fade" effects, callers use `DiscreteTween`
explicitly:

```dart
DiscreteTween<Color>(
  begin: const AnsiColor(8),
  end:   const AnsiColor(14),
).animate(controller);   // swaps at t = 0.5
```

### 7.7 `AnimatedBuilder`

```dart
final class AnimatedBuilder extends StatefulWidget {
  const AnimatedBuilder({
    super.key,
    required this.animation,
    required this.builder,
    this.child,
  });

  final Listenable animation;
  final Widget Function(BuildContext, Widget? child) builder;
  final Widget? child;
}
```

Implementation requirements (small but easy to get subtly
wrong):

- Subscribe in `initState`.
- Resubscribe in `didUpdateWidget` if `animation` changes.
- Unsubscribe in `dispose`.
- The optional `child` is reused unchanged across rebuilds —
  performance escape hatch for subtrees that don't depend on
  the animation.

## 8. Discrete lane

### 8.1 `FrameTicker`

Lower-level primitive — emits a `frame` counter at a logical
cadence while active.

```dart
final class FrameTicker extends Listenable {
  FrameTicker({
    required Duration interval,
    required TickerScheduler scheduler,
  });

  int get frame;
  Duration get elapsed;
  Duration get delta;       // time since last emit

  void start();
  void stop();
  void dispose();
}
```

Unlike `Ticker`, `FrameTicker` owns its own cadence. The shared
scheduler is still used (no independent `Timer.periodic`); the
`FrameTicker` decides whether enough time has passed since its
last emit to advance its frame counter.

### 8.2 `FrameBuilder`

```dart
final class FrameBuilder extends StatefulWidget {
  const FrameBuilder({
    super.key,
    required this.interval,
    required this.builder,
    this.enabled = true,
  });

  final Duration interval;
  final bool enabled;
  final Widget Function(
    BuildContext context,
    int frame,
    Duration elapsed,
    Duration delta,
  ) builder;
}

const spinnerFrames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

FrameBuilder(
  interval: const Duration(milliseconds: 80),
  builder: (ctx, frame, elapsed, delta) =>
      Text(spinnerFrames[frame % spinnerFrames.length]),
);
```

## 9. Lifecycle: `TickerProvider` and `TickerMode`

### 9.1 `TickerProvider` + mixin

```dart
abstract interface class TickerProvider {
  Ticker createTicker(void Function(Duration elapsed) onTick);
}

mixin SingleTickerProviderStateMixin<T extends StatefulWidget>
    on State<T> implements TickerProvider {
  Ticker? _ticker;

  @override
  Ticker createTicker(void Function(Duration elapsed) onTick) {
    assert(_ticker == null,
        'SingleTickerProviderStateMixin permits only one Ticker. '
        'Use TickerProviderStateMixin for multiple.');
    return _ticker = Ticker(
      onTick,
      scheduler: TuiBinding.of(context).tickerScheduler,
    );
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }
}
```

`TickerProviderStateMixin` (multi-ticker) is deferred — added
when a real widget needs it.

### 9.2 `TickerMode`

```dart
TickerMode(
  enabled: false,
  child: HiddenPane(),
)
```

Inherited; tickers in a disabled subtree skip their callbacks
while still tracking elapsed time. Re-enabling resumes from the
correct current value (not by replaying missed frames). Use
cases: hidden tabs, modals covering content, offscreen list
items, the entire app under `AnimationPolicy.disabled`.

## 10. `AnimationPolicy`

```dart
enum AnimationPolicy {
  enabled,    // normal
  reduced,    // decorative transitions shortened or skipped;
              // functional affordances (cursor, spinner) keep running
  disabled,   // nonessential animations snap to end state;
              // repeating decorative animations don't run
}
```

Source for v0: an explicit parameter on `runTui` or settable on
`BuildOwner`. Environment-variable / accessibility-integration
sources can layer in later.

Important: the policy lever pulls through `TickerMode`; existing
animations continue from their correct elapsed-time value when
the policy changes, rather than restarting.

## 11. Built-in / reference animated affordances

To pressure-test the primitives, the first slice includes:

```dart
Spinner({String? label, SpinnerStyle style});
BlinkingCursor({CursorStyle style});
TypingIndicator();
AnimatedProgressBar({required double value, Duration duration});
```

`Spinner` and `BlinkingCursor` are public widgets (they're
universally needed); `TypingIndicator` and `AnimatedProgressBar`
land as example widgets in `example/` until we have a reason to
promote them.

Each implementation exercises a different corner:

- **Spinner** — discrete lane, shared scheduler, stops on unmount,
  respects `TickerMode`, respects `AnimationPolicy`.
- **BlinkingCursor** — discrete lane at slow cadence (~500 ms);
  proves the discrete lane doesn't force 30 Hz rebuilds.
- **TypingIndicator** — discrete state cycling, pauses when
  hidden via `TickerMode`.
- **AnimatedProgressBar** — continuous lane, `IntTween` for
  integer cell quantization, doesn't repaint more often than the
  cell value changes.

## 12. Rendering integration

Animation does not introduce a new rendering path:

```text
animation tick / frame tick
  → controller / FrameTicker advances
  → listeners notify
  → AnimatedBuilder / FrameBuilder calls setState
  → existing markNeedsBuild → onScheduleBuild → flushBuild → renderFrame
  → existing CellBuffer paint + ANSI diff render
```

Integration requirements (most fall out of the existing
pipeline; flagged because they're load-bearing):

- Multiple animation listeners in one scheduler tick coalesce
  into one render frame.
- Input events and animation ticks share the same frame pipeline.
- Input latency is not blocked behind queued stale animation
  frames (because there are no queued stale frames — see §6.3).
- Slow rendering skips visual frames rather than queueing them.
- No widget writes directly to stdout.

## 13. Acceptance tests

Grouped by area; this is the test catalogue, not the test file
list.

**Scheduler**
- No active animations → no active periodic timer.
- No active animations → no ticker callbacks.
- Starting first ticker starts the scheduler.
- Stopping last ticker stops the scheduler.
- Multiple active tickers share one scheduler tick.
- Late frames compute elapsed time from the clock.
- No stale-frame backlog when rendering falls behind.
- Scheduler tears down cleanly at app exit.

**Ticker**
- Doesn't tick before `start()`.
- Ticks after `start()`.
- Stops after `stop()`.
- Doesn't tick after `dispose()`.
- `SingleTickerProviderStateMixin` rejects a second ticker.

**TickerMode**
- Disabled subtree mutes ticker callbacks.
- Re-enabling resumes from correct elapsed time.
- Nested `TickerMode` resolves correctly.
- `AnimationPolicy` plumbs through to the same mute path.

**FrameBuilder / FrameTicker**
- Frame increments only at the requested interval.
- Multiple frame tickers share the scheduler.
- Stops cleanly on dispose.
- Spinner frame advances deterministically under fake time.
- Cursor blink does not rebuild at 30 Hz.

**AnimationController**
- `forward()` reaches `upperBound`.
- `reverse()` reaches `lowerBound`.
- `repeat()` loops; `repeat(reverse: true)` alternates.
- `stop(canceled: true)` raises `TickerCanceled` on `orCancel`.
- `reset()` returns to dismissed.
- Bounds clamping.
- Status transitions occur in the expected order; listeners
  fire once per transition.
- Disposal cancels outstanding futures.
- `duration: Duration.zero` snaps and completes synchronously.
- `AnimationPolicy.disabled` snaps to end state.

**Curves and tweens**
- Curves preserve 0 and 1 boundaries.
- Each ease curve produces the expected midpoint.
- `IntTween` quantizes deterministically.
- `DiscreteTween<T>` swaps at threshold.
- `RgbColorTween` interpolates channels linearly.
- Type system rules out `RgbColorTween` with indexed endpoints.

**AnimatedBuilder**
- Subscribes in `initState`.
- Rebuilds on notification.
- Resubscribes in `didUpdateWidget` when animation changes.
- Unsubscribes in `dispose`.
- `child` reused across rebuilds.

**Integration**
- Ten concurrent spinners share one scheduler tick.
- Ten spinners do not create ten timers.
- Animation frames coalesce into one render frame.
- Input event during animation handled without waiting for stale
  animation frames.
- Hidden pane animations muted via `TickerMode`.
- App exits without leaked scheduler/ticker state.

## 14. Benchmarks

```text
Idle app:
  - no active timer
  - no ticker callbacks
  - no animation-scheduled frames

One spinner (discrete):
  - frames/sec at the configured cadence
  - render µs/frame
  - total CPU vs steady-state input cost

Ten spinners:
  - scheduler coalescing efficacy
  - render frames/sec
  - timer count = 1 (not 10)

One continuous slide animation:
  - 30 Hz sampling
  - cell-quantized movement

Mixed input + animation:
  - keypress latency while animations are active

Slow terminal simulation (artificial paint delay):
  - no stale frame backlog
  - value samples current elapsed time
```

Assertions are structural where possible (timer count, frame
coalescing) rather than absolute µs — the existing benchmark
harness machine has ~10-15% noise.

## 15. Scope

### 15.1 In v0

Core scheduling:
- `TuiBinding` + `TuiBindingScope` (InheritedWidget) +
  `TuiBinding.of(context)` / `maybeOf(context)`
- `runTui` change: construct and install the root binding
- `TickerScheduler` owned by `TuiBinding`
- `FakeTickerScheduler` + `FakeClock`
- `Ticker`, `TickerProvider`, `SingleTickerProviderStateMixin`
- `TickerMode`
- `AnimationPolicy`

Continuous lane:
- `Animation<T>`, `AnimationStatus`, status listeners
- `AnimationController`
- `TickerFuture` + `TickerCanceled`
- `Curve`, `Curves` (linear / easeIn / easeOut / easeInOut /
  `steps(int)`)
- `CurvedAnimation`
- `DoubleTween`, `IntTween`, `DiscreteTween<T>`, `RgbColorTween`
- `AnimatedBuilder`

Discrete lane:
- `FrameTicker`
- `FrameBuilder`

Reference affordances:
- `Spinner` (public)
- `BlinkingCursor` (public)
- `TypingIndicator` (example)
- `AnimatedProgressBar` (example)

Documentation:
- README animation section
- Continuous-vs-discrete guide
- `AnimationPolicy` and `TickerMode` docs
- Spinner / cursor / typing / progress examples

Tests + benchmarks per §13 and §14.

### 15.2 Deferred

- `AnimatedContainer`, `AnimatedPositioned`, etc. — implicit
  animation widget family.
- `TickerProviderStateMixin` (multi-ticker).
- `IntervalCurve` (stagger / delay within parent timeline).
- Physics simulations.
- Hero / route transitions (no router).
- Mouse-hover animations.
- Rich transition DSLs.
- Environment-variable / accessibility-API integration for
  `AnimationPolicy`.

## 16. Implementation plan

The scope is large enough that it lands as **six self-contained
phases**, each leaving the suite green and merging independently.
Order matters: phase 1 validates the hardest design decisions
(binding ownership, monotonic clock, scheduler coalescing, zero
idle work) before any of the higher-level abstractions are built
on top.

Each phase has a clear "done" criterion and a small number of
public exports. The user-visible animation API doesn't appear
until phase 4 (discrete lane) and phase 5 (continuous lane); phases
1–3 are pure infrastructure.

### Phase 1: Binding + scheduler foundation

Lands `TuiBinding`, `TickerScheduler`, `Ticker`, and the
`TickerProvider` lifecycle without exposing any user-visible
animation API. Validates the monotonic-clock model, the zero-idle
guarantee, and the binding-via-InheritedWidget access pattern.

| File | LoC est. |
| --- | ---: |
| `lib/src/animation/clock.dart` (Clock + SystemClock + FakeClock) | ~70 |
| `lib/src/animation/ticker_scheduler.dart` (+ FakeTickerScheduler) | ~250 |
| `lib/src/animation/ticker.dart` (Ticker + TickerProvider + SingleTickerProviderStateMixin) | ~180 |
| `lib/src/animation/tui_binding.dart` (TuiBinding + TuiBindingScope + of/maybeOf) | ~150 |
| `lib/src/runtime/run_tui.dart` — install root TuiBindingScope | ~30 |
| Public exports | small |
| Tests: §13 Scheduler + Ticker groups + binding lookup | ~280 |

Done when: a test harness can create a `TuiBinding`, register a
`Ticker` via `SingleTickerProviderStateMixin`, advance the
`FakeClock`, and assert exactly one scheduler frame fired. Zero
idle when no tickers are registered (structural: `_timer == null`).

### Phase 2: Lifecycle and policy

Adds the `TickerMode` subtree muting and `AnimationPolicy`
machinery, plumbed through the binding and respected by `Ticker`.
Still no user-visible animation API.

| File | LoC est. |
| --- | ---: |
| `lib/src/widgets/ticker_mode.dart` | ~80 |
| `lib/src/animation/animation_policy.dart` | ~50 |
| Integration: Ticker honors muted subtree, policy disabled/reduced | ~50 |
| Tests: §13 TickerMode group | ~150 |

Done when: a `Ticker` in a `TickerMode(enabled: false)` subtree
doesn't invoke its callback, but `elapsed` continues to advance
so re-enabling resumes at the correct value (not by replaying
missed frames). Policy.disabled cleanly snaps animations to their
end state once Phase 5 lands.

### Phase 3: Discrete lane + first public widgets

First user-visible animation API. The discrete lane is shipped
before the continuous lane because it's simpler (no curves, no
tweens, no controller state machine) and validates the
scheduler-coalescing story under multiple concurrent registrants.

| File | LoC est. |
| --- | ---: |
| `lib/src/animation/frame_ticker.dart` | ~120 |
| `lib/src/widgets/frame_builder.dart` | ~80 |
| `lib/src/widgets/spinner.dart` | ~100 |
| `lib/src/widgets/blinking_cursor.dart` (`TextInput` integration optional) | ~80 |
| Tests: §13 FrameBuilder/FrameTicker groups + Spinner/BlinkingCursor | ~250 |

Done when: a `Spinner` and `BlinkingCursor` work end-to-end in
the chat demo (no real-time wallclock assertions; FakeClock +
FakeTickerScheduler drive deterministic tests), and ten concurrent
spinners share one underlying timer (asserted structurally).

### Phase 4: Continuous lane — observable state

Adds `Animation<T>`, `AnimationStatus`, status listeners. No
controller yet; this phase makes the observation surface clean
before we land the state machine that drives it.

| File | LoC est. |
| --- | ---: |
| `lib/src/animation/animation.dart` (base + status + listeners) | ~120 |
| Tests: status enum, listener lifecycle, Listenable contract | ~120 |

Done when: a manual `Animation<T>` implementation passes
listener-lifecycle tests; status listeners are publicly callable.

### Phase 5: Continuous lane — controller, curves, tweens, builder

The largest phase. Lands `AnimationController`, the `TickerFuture`
semantics, the curves library, the tween family, and
`AnimatedBuilder`.

| File | LoC est. |
| --- | ---: |
| `lib/src/animation/ticker_future.dart` (TickerFuture + TickerCanceled) | ~100 |
| `lib/src/animation/animation_controller.dart` | ~350 |
| `lib/src/animation/curves.dart` (Curve + Curves + CurvedAnimation) | ~200 |
| `lib/src/animation/tween.dart` (Tween + DoubleTween + IntTween + DiscreteTween + RgbColorTween) | ~180 |
| `lib/src/widgets/animated_builder.dart` | ~80 |
| Tests: §13 AnimationController + Curves + Tweens + AnimatedBuilder | ~400 |

Done when: an `AnimationController` driven by a `FakeClock`
produces exact tween values at exact times for every curve;
`forward()` / `reverse()` / `repeat()` / `stop()` produce
specified status transitions; cancellation completes
`TickerFuture.orCancel` with `TickerCanceled`; `AnimatedBuilder`
rebuilds on notification and reuses its `child` subtree.

### Phase 6: Examples, integration, benchmarks, docs

Pressure-tests the API end-to-end and provides the materials a
new user needs.

| Item | LoC est. |
| --- | ---: |
| `example/typing_indicator.dart` (lives in chat_demo) | ~60 |
| `example/animated_progress_bar.dart` (or in chat_demo) | ~90 |
| `chat_demo` updates: spinner during connect, blinking composer cursor, typing indicator | ~80 |
| Benchmarks per §14 | ~200 |
| README animation section + cross-references | (docs) |

Done when: chat_demo shows a blinking composer cursor (discrete
lane, 500 ms), a spinner during simulated connect (discrete lane,
80 ms), and a typing indicator (discrete lane, 400 ms). Benchmark
suite asserts the zero-idle-work and one-timer-for-N-tickers
properties. `AnimatedProgressBar` example exercises the
continuous lane with `IntTween`.

### Total

| Phase | LoC (incl. tests) |
| --- | ---: |
| 1: Binding + scheduler | ~960 |
| 2: Lifecycle and policy | ~330 |
| 3: Discrete lane | ~630 |
| 4: Continuous lane — observable | ~240 |
| 5: Continuous lane — controller etc. | ~1,310 |
| 6: Examples + benchmarks + docs | ~430 |
| **Total** | **~3,900** |

Larger than revision 2's ~2,930 because of:
- `TuiBinding` + `TuiBindingScope` (~180 LoC + integration).
- More extensive Curves library (per §7.4) (~80 LoC extra).
- Slightly expanded tests (binding lookup, hot reload).

Time estimate at this scope, with the phasing above:
**1.5–2.5 weeks** for the whole thing, **2–3 days per phase**
for phases 1, 3, and 5; **half-day to a day** for phases 2, 4,
and 6.

The phasing means review can happen per-phase rather than over a
single 3,900-line PR.

## 17. Risks and alternatives

### 17.1 Risk: idle-CPU regression

If the scheduler doesn't fully stop when no animations are
active, the app burns CPU at rest. Mitigation: structural
assertion in tests — after stopping the last ticker,
`scheduler._timer` is null. Treat any non-null state as a
regression.

### 17.2 Risk: layout cost dominates at 30 Hz

Layout currently re-runs every frame regardless of whether
constraints changed. At 30 Hz of continuous animation, that's
30 layouts/sec for a tree that may not need any of them. RFC
0009 §5.2 (layout caching) is the right mitigation if
measurements show this matters; for now we accept it because
RFC 0009 §4 measurements show typical layout is <500 µs.

### 17.3 Risk: animation interferes with input latency

If a long animation hogs frame budget, input might queue behind
it. Mitigation: input events trigger their own `setState`; the
next frame batches their build with any pending animation tick.
Same path as today. The "no stale frame backlog" design (§6.3)
prevents the worst case where rendering falls behind and queues
old animation frames.

### 17.4 Risk: `TuiBinding` becomes a kitchen-sink

If every cross-cutting concern (theme, navigation, gestures,
lifecycle) ends up bolted onto `TuiBinding` without discipline,
it becomes the same hard-to-reason-about god object Flutter's
`WidgetsBinding` is criticized for. Mitigation: keep the binding
*small* — it holds references to other systems, doesn't implement
them. Each system is its own type (the binding holds a
`TickerScheduler`, a future `ThemeData`, etc.), tested
independently, and reachable as a property of the binding rather
than via inheritance into the binding type.

### 17.5 Alternative: skip animations entirely

We could declare animation out of scope and tell apps to use
`Timer.periodic`. Saves ~2,930 LoC; costs us cursor blink,
spinners, and the chat MVP's typing indicator; forces every
animated widget to reinvent the same scheduler with the same
lifecycle pitfalls.

Rejected — the chat MVP genuinely needs this.

### 17.6 Alternative: external `fleury_animation` package

Keeps the core small. Costs: divergent docs, separate release
cadence, the `TickerScheduler` integration with `BuildOwner` /
`runTui` wants to live in the core anyway.

Rejected — the core is the right home.

### 17.7 Alternative: continuous lane only (no discrete lane)

Force spinners through `AnimationController` at 30 Hz. Saves
~450 LoC. Cost: 3-5× more ticks than needed for the most common
TUI animation pattern (frame-indexed cycling at 80-500 ms), and
no way to express "this animation has its own cadence
unrelated to smooth interpolation."

Rejected — the discrete lane is the most insightful piece of the
revised proposal. Most TUI animations belong in it, and pretending
otherwise wastes scheduler ticks and obscures intent.

## 18. Open questions

Resolved in revision 3:

- ~~Scheduler ownership~~ — `TuiBinding` (§6.1).
- ~~`StepTween<T>` naming~~ — `DiscreteTween<T>`.
- ~~Debug/release behavior for indexed-color tweens~~ — ruled
  out by the type system (`RgbColorTween` only accepts
  `RgbColor`).
- ~~Status listeners~~ — public on `Animation<T>`.
- ~~`TickerFuture` rigor~~ — full semantics (`orCancel` +
  `TickerCanceled`).

Still open:

1. **Default frame rate.** Proposing 30 Hz for the continuous
   lane. Discrete lane is per-ticker (typically 80-500 ms).
   Happy to defend 60 Hz if a use case shows up (text editors
   often want it for cursor-blink parity with native editors —
   but discrete lane gives us cursor blink at 500 ms anyway).

2. **`vsync` mixin vs explicit parameter.** Proposing the mixin
   (`with SingleTickerProviderStateMixin`) to match Flutter's
   familiar idiom. Alternative: explicit
   `AnimationController(ticker: someTicker)` is more general but
   less discoverable.

3. **`Curves` library size.** Proposing ~10 for v0: linear, the
   four ease curves (`easeIn`/`easeOut`/`easeInOut`/`easeInQuad`/
   `easeOutQuad`), `bounceIn`/`bounceOut`, `elasticIn`/
   `elasticOut`, and the cell-quantized `steps(int)`. Each
   curve is small (<30 LoC); shipping a sparse library forces
   apps to roll their own.

4. **Implicit-animation widgets** (`AnimatedContainer` etc.) —
   adding new widgets later is not a refactor of existing API;
   defer per-widget as demand surfaces.

5. **Public reference affordances.** Proposing `Spinner` and
   `BlinkingCursor` public, `TypingIndicator` and
   `AnimatedProgressBar` as examples. Reasonable to argue all
   four should be public.

6. **`AnimationPolicy` source.** Proposing API-only for v0
   (`runTui(animationPolicy: ...)` and
   `TuiBinding.animationPolicy = ...`). Environment variable /
   system accessibility integration can land later without
   refactoring existing code.

7. **Hot reload behavior for tickers.** Proposed: on
   `reassembleApplication`, the scheduler keeps running but each
   `AnimationController` calls `reset()` to return to its
   dismissed state. `FrameTicker`s reset their frame counter to
   0 but continue emitting from `elapsed = 0`. Rationale:
   tween endpoints may have changed in the reloaded code; the
   previous mid-animation value is meaningless. Less disruptive
   alternative: preserve state across reload, accept that
   in-flight animations may produce momentarily wrong values
   until they complete. Open for decision.

8. **`TickerProviderStateMixin` (multi-ticker).** Proposing
   defer; adding it later is not a refactor of existing API.
   The `Single` mixin covers the dominant case.

## 19. Recommendation

Approve the scope in §15 and the six-phase plan in §16, treated
as **core engine infrastructure**. The Flutter-shaped continuous
lane plus the terminal-native discrete lane plus `TuiBinding` +
`TickerMode` + `AnimationPolicy` + reference affordances together
make the difference between "a basic animation API" and "a robust
terminal animation foundation that doesn't need refactoring once
adoption begins."

Honest estimates:
- Phase 1 (binding + scheduler foundation) — 2-3 days. Validates
  the hardest design decisions (monotonic clock, scheduler
  ownership, zero idle work, `TuiBinding` access) before
  anything user-visible is built on top.
- Phases 2-6 in sequence — 1-1.5 weeks. Each phase is review-
  sized (200-1,500 LoC), each leaves the suite green, each
  produces something the chat demo can consume.
- Total — **1.5-2.5 weeks** end-to-end.

Phasing means review can happen per-phase rather than over a
single 3,900-line PR.

If approved, the first commit lands phase 1 (`TuiBinding`,
`TickerScheduler`, `FakeClock`, `Ticker`,
`SingleTickerProviderStateMixin`) plus the `runTui` integration.
The user-visible animation API doesn't appear until phase 3, but
the suite is green and the foundation is right at every step.

## 20. References

- Flutter `Ticker`: https://api.flutter.dev/flutter/scheduler/Ticker-class.html
- Flutter `AnimationController`: https://api.flutter.dev/flutter/animation/AnimationController-class.html
- Flutter `AnimatedBuilder`: https://api.flutter.dev/flutter/widgets/AnimatedBuilder-class.html
- Flutter `TickerMode`: https://api.flutter.dev/flutter/widgets/TickerMode-class.html
- Textual animation guide: https://textual.textualize.io/guide/animation/
- ink (readme): https://github.com/vadimdemedes/ink/blob/master/readme.md
- ratatui rendering: https://ratatui.rs/concepts/rendering/under-the-hood/
- Bubble Tea `Tick`: https://pkg.go.dev/charm.land/bubbletea/v2

## 21. Testing strategy and feedback mechanisms

Section 13 catalogues *what* to test. This section describes
*how* the testing is structured, what feedback signals tell us
something's wrong, and what gates each phase merge.

### 21.1 Testing pyramid

**Layer 1 — Unit tests, FakeClock-driven.** The bulk of the work.
Every primitive tested in isolation with no wall-clock dependency.
**Discipline rule:** zero `Future.delayed`, zero `Timer`, zero
`await Future<void>.delayed(Duration.zero)` in animation tests. If
a test reaches for one of those, the test is wrong or the
abstraction is leaking real time. Coverage target: 100% line
coverage on `lib/src/animation/**`. Animation primitives are
foundational; uncovered branches will bite.

**Layer 2 — Integration tests.** Multi-primitive interactions:
animation + `TickerMode`, animation + `AnimationPolicy`, multiple
animations sharing one scheduler tick, animation + input event,
animation + hot reload, animation + modal stacking. Still
FakeClock-driven; deterministic.

**Layer 3 — Golden / snapshot tests.** Render specific animation
states at known FakeClock times and snapshot the resulting
`CellBuffer` (as an ASCII grid string). Commit snapshots. For
each of `Spinner`, `BlinkingCursor`, `TypingIndicator`,
`AnimatedProgressBar`: 5–10 frames across the animation
lifecycle. Detects: glyph-table changes, frame-rate changes,
unintended curve tweaks that visually drift.

**Layer 4 — Property-based / stress tests.** "After N random
start/stop/dispose sequences across M tickers, scheduler is in
the documented idle state." "For any sequence of clock advances,
elapsed time is monotonically non-decreasing." "Across 1000
random animations, no ticker leaks."

**Layer 5 — Performance benchmarks.** Run per phase; record in
`benchmark/baseline_results.md`. Structural assertions where
possible (timer count, frame coalescing) rather than absolute µs
(harness has 10–15% noise).

**Layer 6 — Manual smoke per phase.** Documented checklist
embedded in the phase's exit criteria. Cross-terminal verification
(iTerm2, WezTerm, kitty, alacritty, tmux, real SSH) for phase 6.

### 21.2 Per-phase exit criteria

A phase merges only when all of its criteria are green:

**Phase 1 (binding + scheduler):**
- All scheduler unit tests pass.
- Idle assertion: stopping the last ticker leaves
  `scheduler.isActive == false` (and for the real backend,
  `_timer == null`).
- 10 concurrent tickers in a stress test produce exactly 1
  underlying timer.
- A `FakeClock` advance of N ms with one registered ticker
  produces exactly `⌊N/33⌋` ticks (or whatever the configured
  interval is).
- `TuiBinding.of(context)` works from any descendant; throws
  cleanly when called outside a binding.

**Phase 2 (TickerMode + AnimationPolicy):**
- Ticker callbacks suppressed in `TickerMode(enabled: false)`
  subtree.
- `elapsed` continues to advance in muted subtree; re-enabling
  resumes at correct value (key correctness property).
- `AnimationPolicy.disabled` plumbed through.

**Phase 3 (discrete lane + Spinner/BlinkingCursor):**
- `FrameTicker` fires at requested cadence under FakeClock
  within documented jitter bound.
- Golden snapshots committed for 10 frames of `Spinner`,
  on/off pair for `BlinkingCursor`.
- chat_demo manual check: spinner animates during simulated
  connect; doesn't leak when modal closes mid-animation.

**Phase 4 (Animation<T> observable):**
- Manual `Animation<int>` implementation passes the listener
  contract.
- Status listener fires exactly once per transition.
- No memory leak from add-then-discard listeners.

**Phase 5 (controller + curves + tweens + AnimatedBuilder):**
- Each curve passes boundary tests (`transform(0) == 0`,
  `transform(1) == 1`, midpoint matches documented value).
- Controller `forward()` reaches `upperBound`; status sequence
  is `dismissed → forward → completed`.
- `TickerFuture.orCancel` rejects with `TickerCanceled` on
  `stop(canceled: true)`.
- Slow-render simulation: controller `value` at sample point
  equals `curve(clock_elapsed / duration)` not
  `curve(tick_count × interval / duration)`.
- `AnimationPolicy.disabled` causes `forward()` to complete
  synchronously at `upperBound`.
- `AnimatedBuilder` rebuilds on notify; child subtree identity
  preserved across rebuilds.

**Phase 6 (examples + chat_demo + benchmarks + docs):**
- Cross-terminal manual smoke passes on iTerm2 + WezTerm +
  tmux + real SSH.
- Benchmark suite results checked in.
- README animation section published.

### 21.3 Feedback mechanisms

**During development:**

- **Determinism check.** Any test that uses `await` of a real
  future, or `Timer`, or `Future.delayed` in
  `test/animation/**` fails review. Animation tests must be
  FakeClock-driven. If a test can't be made deterministic, the
  abstraction is leaking real time and needs redesign.
- **Golden drift signal.** Snapshot tests are the visual
  canary. Any unintended visual change shows up as a snapshot
  diff in code review; intentional changes update the snapshot
  deliberately.
- **Benchmark regression script.** A short tool
  (`tool/check_benchmark_regressions.dart`) compares current
  `baseline_results.md` to the last committed version; flags
  any benchmark moving >25%.

**At each phase merge:**

- **Phase exit criteria.** No merge without all criteria green.
- **Adversarial test pass.** A stress test exercising the
  phase's hardest invariants. E.g., phase 1: "register/
  unregister 1000 tickers in random order, assert zero leaks."
  Phase 5: "create/dispose 100 controllers concurrently, assert
  no orphan `TickerFuture`s."

**After all phases:**

- **chat_demo dogfooding.** ≥5 minutes of varied interaction;
  observe nothing flickers, leaks, or stalls. Qualitative but
  essential.
- **SSH/tmux validation.** Run chat_demo over real SSH with
  artificial latency (e.g. `tc qdisc add dev eth0 root netem
  delay 100ms`). The "no stale backlog" claim is meaningless
  if the demo strobes under lag.

### 21.4 Risk-to-test mapping

For each risk the RFC identifies, the specific test that catches
it:

| Risk | Catch |
| --- | --- |
| Memory leak (ticker not cleaned up) | Property-based stress: 100 random start/stop/dispose, `scheduler.activeTickerCount == 0` |
| CPU leak (timer running with no work) | Structural: `scheduler.isActive == false` after last unregister |
| Flicker (paint emits redundant bytes) | Diff-renderer benchmark + chat_demo manual eye |
| Frame timing jitter | Test asserting actual fire times against FakeClock within documented bound |
| Race in scheduler / disposal | Property-based stress with random ordering |
| Hot reload breakage | Explicit `owner.reassembleApplication()` test; assert controller `dismissed`, no exception |
| Slow-render stale backlog | Simulated slow render in test; assert controller value tracks clock not ticks |
| Input lag during animation | Mixed test: dispatch key event during active animation, assert event reaches handler within 1 frame |

### 21.5 Out of scope for testing

To be honest about what we're not doing:

- **No real-time wallclock tests.** Flaky and slow.
- **No "does it feel right" automated metric.** That's a human
  eye task on the chat_demo.
- **No 60 fps target.** 30 Hz is the design point.
- **No physics simulation tests.** No physics in scope.

### 21.6 Cadence

- **Per commit:** unit + integration + snapshot tests run via
  `dart test`. Full suite stays green.
- **Per phase merge:** benchmarks run, exit criteria verified,
  manual smoke on at least one terminal.
- **Before phase 6 merge:** full cross-terminal manual check,
  SSH/tmux validation, soak test.
