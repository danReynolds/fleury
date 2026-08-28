// AnimatedVisibility: presence animation for a single child.
//
// Toggling [visible] plays an [enter] effect when the child appears
// and an [exit] effect when it leaves — and, crucially, keeps the
// child mounted until the exit finishes, then drops it.
//
//   AnimatedVisibility(
//     visible: showDetails,
//     enter: Effects.expand() + Effects.fadeIn(),
//     exit: Effects.shrink(),
//     child: Details(),
//   );
//
// enter/exit are ordinary Effects (the reverse-able ones compose
// naturally). A null enter shows instantly; a null exit unmounts
// immediately.

import '../animation/animation.dart';
import '../animation/curves.dart';
import '../animation/ticker_future.dart';
import 'basic.dart' show EmptyBox;
import 'effects.dart';
import 'framework.dart';

/// Animates [child] in and out as [visible] toggles, deferring unmount
/// until the [exit] effect completes.
class AnimatedVisibility extends StatefulWidget {
  const AnimatedVisibility({
    required this.visible,
    required this.child,
    this.enter,
    this.exit,
    this.duration,
    this.curve,
    super.key,
  });

  final bool visible;
  final Widget child;

  /// Effect played as the child appears (0 → 1). Null = appear
  /// instantly.
  final Effect? enter;

  /// Effect played as the child leaves. Null = unmount immediately,
  /// no exit animation.
  final Effect? exit;

  final Duration? duration;
  final Curve? curve;

  @override
  State<AnimatedVisibility> createState() => _AnimatedVisibilityState();
}

class _AnimatedVisibilityState extends State<AnimatedVisibility> {
  // 1 = fully present, 0 = fully absent.
  late final Animation<double> _t = Animation(0.0);
  bool _present = false;
  bool _exiting = false;
  var _transitionGeneration = 0;

  Duration get _duration =>
      widget.duration ?? const Duration(milliseconds: 250);
  Curve get _curve => widget.curve ?? Curves.easeOut;

  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      _present = true;
      if (widget.enter == null) {
        _t.snap(1.0);
      } else {
        _t.to(1.0, curve: _curve, duration: _duration); // entrance on appear
      }
    }
  }

  @override
  void didUpdateWidget(AnimatedVisibility old) {
    super.didUpdateWidget(old);
    if (widget.visible == old.visible) return;
    if (widget.visible) {
      _appear();
    } else {
      _leave();
    }
  }

  void _appear() {
    _transitionGeneration++;
    setState(() {
      _present = true;
      _exiting = false;
    });
    if (widget.enter == null) {
      _t.snap(1.0);
    } else {
      _t.to(1.0, curve: _curve, duration: _duration);
    }
  }

  void _leave() {
    final generation = ++_transitionGeneration;
    if (widget.exit == null) {
      setState(() {
        _present = false;
        _exiting = false;
      });
      _t.snap(0.0);
      return;
    }
    setState(() => _exiting = true);
    _finishExit(generation);
  }

  Future<void> _finishExit(int generation) async {
    try {
      await _t.to(0.0, curve: _curve, duration: _duration).orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || generation != _transitionGeneration || widget.visible) {
      return;
    }
    setState(() {
      _present = false;
      _exiting = false;
    });
  }

  @override
  void dispose() {
    _transitionGeneration++;
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_present) return const EmptyBox();
    final t = _t.value; // subscribe to frame advances
    var result = widget.child;

    // Keep both effect trees mounted while the child is present. Enter and
    // exit effects can use different wrapper types; swapping between those
    // roots when visibility changes would otherwise remount a stateful child.
    // The inactive effect receives its identity endpoint.
    final enter = widget.enter;
    if (enter != null) {
      result = enter.build(result, _exiting ? 1.0 : t);
    }
    final exit = widget.exit;
    if (exit != null) {
      final progress = _exiting ? (1 - t).clamp(0.0, 1.0) : 0.0;
      result = exit.build(result, progress);
    }
    return result;
  }
}
