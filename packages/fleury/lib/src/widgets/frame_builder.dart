// FrameBuilder: consumption widget for the discrete animation lane.
//
// Drives a child widget built from (frame, elapsed, delta) updated
// at the given interval. Use for spinners, cursor blink, typing
// indicators, marquees — anything that advances by a frame counter
// rather than along a continuous tween.
//
// Internally owns a FrameTicker whose lifecycle follows this
// widget's State. Subscribes via the FrameTicker's ChangeNotifier
// surface so multiple FrameBuilders with the same interval cost
// nothing extra on the scheduler.

import '../animation/animation_policy.dart';
import '../animation/frame_ticker.dart';
import 'framework.dart';
import 'ticker_mode.dart';
import 'tui_binding.dart';

/// Builds [builder]'s widget once per frame as a [FrameTicker]
/// driven at [interval] advances.
///
/// [enabled] is a per-widget switch that pauses the underlying
/// ticker; orthogonal to [TickerMode] which mutes ticker callbacks
/// while keeping the ticker registered (used for whole-subtree
/// muting, e.g. hidden tabs).
class FrameBuilder extends StatefulWidget {
  const FrameBuilder({
    super.key,
    required this.interval,
    required this.builder,
    this.enabled = true,
  });

  /// How often [builder] should be invoked with an incremented
  /// frame counter. Typical values: 80 ms (spinner), 500 ms (cursor
  /// blink), 400 ms (typing indicator).
  final Duration interval;

  /// When false the underlying ticker is stopped — no frames
  /// advance, no rebuilds occur. Reset to true to resume; the
  /// frame counter restarts at zero (this is by design: a paused
  /// spinner restarting at frame 0 looks intentional, not stale).
  final bool enabled;

  /// Widget builder receiving the current frame counter, elapsed
  /// time since start, and delta since last advance.
  final Widget Function(
    BuildContext context,
    int frame,
    Duration elapsed,
    Duration delta,
  )
  builder;

  @override
  State<FrameBuilder> createState() => _FrameBuilderState();
}

class _FrameBuilderState extends State<FrameBuilder> {
  FrameTicker? _ticker;

  void _onFrame() {
    if (!mounted) return;
    setState(() {});
  }

  void _ensureTicker() {
    if (_ticker != null) return;
    final binding = TuiBinding.of(context);
    _ticker = FrameTicker(
      interval: widget.interval,
      scheduler: binding.tickerScheduler,
    )..addListener(_onFrame);
    if (widget.enabled) _ticker!.start();
  }

  void _disposeTicker() {
    final t = _ticker;
    if (t == null) return;
    t.removeListener(_onFrame);
    t.dispose();
    _ticker = null;
  }

  @override
  void didUpdateWidget(FrameBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.interval != oldWidget.interval) {
      // Interval change: re-create the underlying ticker so the new
      // cadence takes effect immediately.
      _disposeTicker();
      _ensureTicker();
      return;
    }
    if (widget.enabled != oldWidget.enabled) {
      final t = _ticker;
      if (t == null) return;
      if (widget.enabled) {
        if (!t.isActive) t.start();
      } else {
        if (t.isActive) t.stop();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // didChangeDependencies fires before the first build, so this
    // is the right place to create the ticker — context is wired
    // up and the binding lookup will succeed.
    _ensureTicker();
    _ticker!.muted =
        !TickerMode.enabledOf(context) ||
        TuiBinding.of(context).animationPolicy == AnimationPolicy.disabled;
  }

  @override
  void dispose() {
    _disposeTicker();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _ticker!;
    return widget.builder(context, t.frame, t.elapsed, t.delta);
  }
}
