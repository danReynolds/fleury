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
//     builder: (context, v) => Text('$v'),
//   )
//
//   AnimationBuilder<double>(
//     selected ? 1.0 : 0.0,
//     spring: Spring.snappy,
//     builder: (context, t) => ...,              // derive many props from t
//   )
//
// AnimationBuilder is the declarative front for Animation — reach for it
// first. Drop to a raw Animation (held in a State) only when you need to
// drive the animation imperatively: sequences (run), loops (loop),
// event/gesture-driven retargets, or awaiting completion.
//
// Analogous to Flutter's TweenAnimationBuilder and Compose's
// animateXxxAsState — but spring-driven by default, so retargeting
// mid-flight is velocity-preserving for free.

import '../animation/curves.dart';
import '../animation/animation.dart';
import '../animation/spring.dart';
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
    super.key,
  });

  /// The target. The first build snaps here; later changes animate.
  final T value;

  /// Receives the current interpolated value each frame.
  final Widget Function(BuildContext context, T value) builder;

  /// Spring to use when [value] changes (defaults to [Spring.smooth]).
  /// Ignored when [curve] is set.
  final Spring? spring;

  /// Curve + [duration] for deterministic easing instead of a spring.
  final Curve? curve;
  final Duration? duration;

  /// Required only for non-built-in [T] (built-ins: double, int,
  /// RgbColor, CellOffset).
  final AnimationType<T>? type;

  @override
  State<AnimationBuilder<T>> createState() => _AnimationBuilderState<T>();
}

class _AnimationBuilderState<T> extends State<AnimationBuilder<T>> {
  late final Animation<T> _animation = Animation<T>(
    widget.value,
    type: widget.type,
  );

  @override
  void didUpdateWidget(AnimationBuilder<T> old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) {
      _animation.to(
        widget.value,
        spring: widget.spring,
        curve: widget.curve,
        duration: widget.duration,
      );
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reading _animation.value here subscribes this element to the
    // animation (implicit reactivity), so frame advances rebuild us.
    return widget.builder(context, _animation.value);
  }
}
