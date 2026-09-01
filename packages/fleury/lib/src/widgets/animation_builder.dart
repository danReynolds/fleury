// AnimationBuilder<T>: the declarative "this value tracks state" widget.
//
// The dominant animation case is "I have a value derived from state,
// and I want it to animate when the state changes." Done by hand that
// is a StatefulWidget with an Animation field, a didUpdateWidget that
// retargets, and a dispose — ~10 lines of identical skeleton every
// time. AnimationBuilder collapses it to one inline widget that owns the
// Animation, retargets whenever [value] changes across a rebuild, and
// disposes automatically.
//
//   AnimationBuilder<int>(
//     counter,                                   // retargets on change
//     builder: (context, v, child) => Text('$v'),
//   )
//
//   AnimationBuilder<double>(
//     selected ? 1.0 : 0.0,
//     spring: Spring.snappy,
//     builder: (context, t, child) => ...,       // derive many props from t
//   )
//
// AnimationBuilder is the declarative front for Animation — reach for it
// first. Drop to a raw Animation (held in a State) only when you need to
// drive the animation imperatively: chained targets and delays, loops,
// event/gesture-driven retargets, or awaiting completion.
//
// It is spring-driven by default, so retargeting mid-flight preserves
// velocity without any additional coordination.

import '../animation/curves.dart';
import '../animation/animation.dart';
import '../animation/spring.dart';
import '../animation/ticker_future.dart';
import 'framework.dart';

/// Animates toward [value] whenever it changes across a rebuild,
/// rebuilding [builder] with the current interpolated value each
/// frame. Owns its [Animation] internally — nothing to dispose.
class AnimationBuilder<T> extends StatefulWidget {
  const AnimationBuilder(
    this.value, {
    required this.builder,
    this.spring,
    this.curve,
    this.duration,
    this.type,
    this.child,
    this.onEnd,
    this.debugLabel,
    super.key,
  }) : assert(
         spring == null || curve == null,
         'spring and curve are mutually exclusive',
       ),
       assert(
         duration == null || curve != null,
         'duration requires a curve; configure spring timing on Spring',
       );

  /// The target. The first build snaps here; later changes animate.
  final T value;

  /// Receives the current interpolated value and the unchanged [child] each
  /// frame.
  final Widget Function(BuildContext context, T value, Widget? child) builder;

  /// Spring to use when [value] changes (defaults to [Spring.smooth]).
  /// Mutually exclusive with [curve].
  final Spring? spring;

  /// Curve + [duration] for deterministic easing instead of a spring.
  final Curve? curve;
  final Duration? duration;

  /// Required only for non-built-in [T] (built-ins: double, int,
  /// RgbColor, CellOffset).
  final AnimationType<T>? type;

  /// A subtree that does not depend on the animated value. It is passed back
  /// to [builder] unchanged so callers can avoid rebuilding static content on
  /// every animation frame.
  final Widget? child;

  /// Called when the latest target change reaches its destination naturally.
  /// Superseded animations and disposal do not call this callback.
  final VoidCallback? onEnd;

  /// A label included in diagnostics for the internally-owned [Animation].
  final String? debugLabel;

  @override
  State<AnimationBuilder<T>> createState() => _AnimationBuilderState<T>();
}

class _AnimationBuilderState<T> extends State<AnimationBuilder<T>> {
  late final Animation<T> _animation = Animation<T>(
    widget.value,
    type: widget.type,
    debugLabel: widget.debugLabel,
  );

  var _targetGeneration = 0;

  @override
  void initState() {
    super.initState();
    _validateWidgetTiming();
  }

  @override
  void didUpdateWidget(AnimationBuilder<T> old) {
    super.didUpdateWidget(old);
    _validateWidgetTiming();
    if (widget.value != old.value) {
      _animateToLatestTarget();
    }
  }

  void _validateWidgetTiming() {
    final spring = widget.spring;
    final curve = widget.curve;
    final duration = widget.duration;
    if (spring != null && curve != null) {
      throw ArgumentError('spring and curve are mutually exclusive');
    }
    if (duration != null && curve == null) {
      throw ArgumentError.value(
        duration,
        'duration',
        'requires a curve; configure spring timing on Spring',
      );
    }
    if (duration?.isNegative ?? false) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }
    if (spring != null && spring.response <= Duration.zero) {
      throw ArgumentError.value(
        spring.response,
        'spring.response',
        'must be greater than zero',
      );
    }
    if (spring != null && (spring.bounce < 0 || spring.bounce >= 1)) {
      throw ArgumentError.value(
        spring.bounce,
        'spring.bounce',
        'must be in [0, 1)',
      );
    }
  }

  void _animateToLatestTarget() async {
    final generation = ++_targetGeneration;
    try {
      await _animation
          .to(
            widget.value,
            spring: widget.spring,
            curve: widget.curve,
            duration: widget.duration,
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || generation != _targetGeneration) return;
    widget.onEnd?.call();
  }

  @override
  void dispose() {
    _targetGeneration++;
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reading _animation.value here subscribes this element to the
    // animation (implicit reactivity), so frame advances rebuild us.
    return widget.builder(context, _animation.value, widget.child);
  }
}
