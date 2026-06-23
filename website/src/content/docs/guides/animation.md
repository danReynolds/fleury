---
title: Animation
description: Animate values, compose entrance effects, and drop to a raw ticker only when you need to.
---

Most animation is *"a value follows some state"* — a highlight that slides in
when a row is selected, a bar that fills as a download progresses, a count that
ticks up. Fleury gives you that declaratively: hand a target to a widget and it
springs there on its own, with nothing to dispose.

Reach for these in order. Each rung down is more control and more bookkeeping;
you rarely need the bottom one.

| You want… | Use | 
|---|---|
| A drop-in entrance / emphasis / exit | [`.animate()` effects](#entrance-effects-animate) · `Reveal` |
| A value to follow state | [`AnimationBuilder`](#a-value-that-follows-state-animationbuilder) |
| To drive an animation yourself (events, loops, sequences) | [`Animation`](#driving-it-yourself-animation) |
| A spinner / blink / marquee — discrete frames | [`FrameBuilder`](#discrete-frames-framebuilder) |
| Raw frame time for something custom | [`Ticker`](#the-escape-hatch-a-raw-ticker) |

Everything bottoms out in one shared frame scheduler (one timer for the whole
app, ~30 Hz under `requestAnimationFrame` in the browser) and respects reduced-
motion automatically.

## A value that follows state: `AnimationBuilder`

This is the workhorse. Give it a target value; whenever that value changes
across a rebuild, it animates from the old value to the new one and rebuilds
`builder` with the interpolated value each frame. It owns the animation
internally — nothing to dispose.

```dart
// The count jumps when `unread` changes; the text counts up smoothly.
AnimationBuilder<int>(
  unread,
  builder: (context, n) => Text('$n unread'),
)

// A download bar that eases toward each new fraction.
AnimationBuilder<double>(
  downloaded / total,
  curve: Curves.easeOut,
  builder: (context, t) => ProgressBar(value: t),
)
```

It animates `double`, `int`, `RgbColor`, and `CellOffset` out of the box. For
any other type, pass an `AnimationType` that says how to break it into scalars.

The default engine is a **spring**, and that's the point: a spring carries
*velocity*, so if the target changes mid-flight it continues from the live
value and speed instead of snapping back to restart. Spam-toggling a panel just
feels right, with no special handling. Pass `spring:` to pick a feel, or
`curve:` + `duration:` for deterministic easing instead.

## Driving it yourself: `Animation`

When the animation is driven by events, gestures, loops, or sequences — not
just by a value changing across rebuilds — hold an `Animation` in your `State`.
You read `.value` directly (reading it inside `build` auto-subscribes that
widget to frame advances, so there's no `setState`), and retarget with one
verb.

```dart
class _PanelState extends State<Panel> {
  final _open = Animation(0.0); // 0 = closed, 1 = open

  void _toggle() =>
      _open.to(_isOpen ? 0.0 : 1.0, spring: Spring.smooth);

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _open.value; // reading value subscribes this build
    return SizedBox(width: (t * _maxWidth).round(), child: _contents());
  }
}
```

The verbs:

```dart
a.to(0.8);                                   // spring toward a target (default)
a.to(0.8, curve: Curves.easeOut, duration: Duration(milliseconds: 300));
a.snap(0.0);                                 // jump instantly, no animation
a.stop();                                    // freeze where it is

a.loop(between: (0.3, 1.0),                  // repeat forever (a pulse)
       period: Duration(milliseconds: 600));

a.run([                                      // a sequence, back-to-back
  AnimationStep.to(1.2, spring: Spring.snappy),
  AnimationStep.hold(Duration(milliseconds: 120)),
  AnimationStep.to(1.0),
]);
```

`to`, `loop`, and `run` return a `TickerFuture` — `await` it to know when the
motion settles, or `await .orCancel` to also hear about a mid-flight retarget.

> `Animation(0.0)..to(1.0)` is the *animate-on-appear* idiom: the retarget is
> deferred until the value first displays, then plays — so a freshly-mounted
> widget animates in rather than starting already-finished.

### Springs and curves

A `Spring` is parameterized by feel, not physics constants:

```dart
Spring.snappy   // 150 ms, no overshoot — taps, selections, focus
Spring.smooth   // 280 ms, no overshoot — layout shifts, panels  (the default)
Spring.gentle   // 450 ms, no overshoot — ambient / cosmetic motion
Spring(response: Duration(milliseconds: 200), bounce: 0.2) // custom + overshoot
```

When you'd rather have deterministic, frame-exact easing (and don't need the
interruption behavior), pass a `Curve` instead: `Curves.linear`, `easeIn`,
`easeOut`, `easeInOut`, `easeInCubic`, `easeOutCubic`, `bounceOut`,
`elasticOut`, or `Curves.steps(n)` for a hard-stepped value.

## Entrance effects: `.animate()`

For the common "play an entrance / emphasis / exit on this widget," skip the
plumbing entirely and chain effects onto any widget. Each effect maps progress
`0 → 1` onto a visual channel (color, position, reveal), and they compose in
parallel, so stacking them just works.

```dart
Text('Saved').animate().fadeIn().slideIn();   // entrance, on mount
loader.animate().shimmer();                    // continuous — auto-loops
field.animate(play: invalid).shake();          // plays when `play` flips true
```

The full set: `fadeIn` / `fadeOut`, `slideIn` / `slideOut`, `reveal` /
`conceal`, `expand` / `collapse`, `shimmer`, `pulse`, `shake`, `flash`. They all
run on `Animation` underneath, so they inherit the spring/curve, honor reduced-
motion, and stay deterministic under tests.

For something that has to **stay mounted until its exit finishes** — a detail
panel, a toast, a list row being removed — use `Reveal`. It plays an enter
effect on appear, an exit effect on disappear, and defers the unmount until the
exit completes:

```dart
Reveal(
  visible: showDetails,
  enter: Effects.expand() + Effects.fadeIn(),
  exit: Effects.collapse(),
  child: Details(),
)
```

## Discrete frames: `FrameBuilder`

Some motion isn't a tween toward a value — it's a frame counter advancing on a
cadence: a spinner cycling glyphs, a cursor blinking, a typing indicator, a
marquee. For those, `FrameBuilder` ticks a frame counter at a fixed interval
and rebuilds with it.

```dart
const frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

FrameBuilder(
  interval: const Duration(milliseconds: 80),
  builder: (context, frame, elapsed, delta) =>
      Text(frames[frame % frames.length]),
)
```

The built-in `Spinner`, `BlinkingCursor`, and the indeterminate `ProgressBar`
are all just `FrameBuilder`s — use them directly when they fit. Drop to a bare
`FrameTicker` (the notifier `FrameBuilder` wraps) only when you need the *phase*
as state rather than a built widget — for example, a text cursor that styles an
existing character cell instead of painting its own glyph.

## The escape hatch: a raw `Ticker`

Below all of the above is the `Ticker`: a callback invoked once per frame with
the elapsed time since it started. You almost never need it — reach for it only
when the timing is genuinely custom and none of the layers above fit. Two real
examples:

- **Variable-rate playback.** An animated GIF has a different duration *per
  frame* and must drop frames if the host stalls — not a fixed interval and not
  a continuous tween, so `Image` drives it with a raw ticker and a wall-clock
  accumulator.
- **Decoupled data cadences.** A streaming dashboard advances a smooth chart
  every frame but a heavy table only once a second. One ticker, different work
  on different intervals.

To get a ticker, your `State` has to be able to *provide* one — that's what the
mixin is for:

```dart
class _ClockState extends State<Clock>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick)..start();
  Duration _elapsed = Duration.zero;

  void _onTick(Duration elapsed) => setState(() => _elapsed = elapsed);

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('${_elapsed.inSeconds}s');
}
```

### Why the mixin?

A `Ticker` can't stand alone — it has to be wired into the runtime. Mixing in
`SingleTickerProviderStateMixin` makes your `State` a `TickerProvider`, and its
`createTicker` does three pieces of wiring you'd otherwise do by hand:

1. **Binds to the shared scheduler** — your ticker joins the app's single frame
   timer instead of spinning up its own.
2. **Syncs mute state** with `TickerMode` (scrolled off-screen → paused) and the
   `AnimationPolicy` (reduced-motion → disabled). Your callback simply stops
   firing when it shouldn't run; you don't check anything.
3. **Disposes the ticker** when the `State` is torn down.

"Single" means one ticker per `State` (it asserts if you ask for two — use
`TickerProviderStateMixin` when a widget needs several). The higher-level tools
all do this wiring internally, which is the whole reason you don't see a ticker
or this mixin when you use them.

### Smooth motion is a cadence concern, not a perf one

A frame is cheap — a busy dashboard renders one in well under a millisecond.
"Sluggish" animation is almost always about **how often you advance state**, not
the renderer. Advancing a model on a coarse interval makes motion lurch;
sampling continuous state as a function of `elapsed` every frame makes it glide.
When different things should move at different speeds, decouple them:

```dart
void _onTick(Duration elapsed) {
  final ms = elapsed.inMilliseconds;
  var changed = false;
  if (ms - _lastFast >= 90)   { _lastFast = ms; _advanceGraphs(); changed = true; }
  if (ms - _lastSlow >= 1100) { _lastSlow = ms; _advanceTable();  changed = true; }
  if (changed) setState(() {});
}
```

## In the browser and in tests

None of this changes across targets. `runTuiWebDom` installs the same binding,
so every layer here runs client-side under `requestAnimationFrame` with no code
change. In tests, `tester.pump(duration)` advances tickers, springs, and effects
deterministically — and because animation respects the `AnimationPolicy`, a
test tree with motion disabled snaps straight to final values.
