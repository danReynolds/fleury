---
title: Animation & tickers
description: Drive frame-by-frame updates with a Ticker, and keep motion smooth.
---

For anything that changes over time — a clock, a streaming chart, a progress
animation — drive it with a **Ticker**. A ticker calls you back once per frame
with the elapsed time; you update state and `setState`, and the framework
repaints only what changed.

## A ticking widget

Mix in `SingleTickerProviderStateMixin` (or `TickerProviderStateMixin` for
several tickers), create the ticker, and dispose is handled for you:

```dart
class _ClockState extends State<Clock>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The ticker needs the TuiBinding that runTui (and runTuiWebDom) install;
    // a headless test tree has none, so guard and simply skip animating there.
    if (_ticker == null && TuiBinding.maybeOf(context) != null) {
      _ticker = createTicker(_onTick)..start();
    }
  }

  void _onTick(Duration elapsed) => setState(() => _elapsed = elapsed);

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text('${_elapsed.inSeconds}s');
}
```

`Ticker` has `start()`, `stop()`, and `isActive` if you want to pause and resume
(for example, behind a play/pause control).

## Smooth motion is a cadence concern, not a perf one

A frame is cheap — a busy dashboard renders one in well under a millisecond,
dozens of times under a 30 Hz budget. So "sluggish" animation is almost always
about **how often you advance state**, not the renderer.

The ticker fires every frame (~30 Hz), but you choose when to do work. Advancing
a model on a coarse interval makes motion lurch; advancing it on a fine interval
makes it glide. When different things should move at different speeds, decouple
them — sample the smooth parts often and the heavy parts rarely:

```dart
void _onTick(Duration elapsed) {
  final ms = elapsed.inMilliseconds;
  var changed = false;
  if (ms - _lastFast >= 90)   { _lastFast = ms;  _advanceGraphs(); changed = true; }
  if (ms - _lastSlow >= 1100) { _lastSlow = ms;  _advanceTable();  changed = true; }
  if (changed) setState(() {});
}
```

For the smoothest result, sample continuous state as a function of `elapsed`
every frame rather than quantising it to a low step rate.

## It works in the browser too

`runTuiWebDom` installs the same binding, so tickers run client-side under
`requestAnimationFrame` with no code change. In tests, `tester.pump(duration)`
advances tickers deterministically.
