// Reveal: presence animation for a single child.
//
// Toggling [visible] plays an [enter] effect when the child appears
// and an [exit] effect when it leaves — and, crucially, keeps the
// child mounted until the exit finishes, then drops it. Because we
// own the element lifecycle we can defer unmount cleanly, sidestepping
// the fragility that plagues `AnimatePresence`-style APIs elsewhere.
//
//   Reveal(
//     visible: showDetails,
//     enter: Effects.expand() + Effects.fadeIn(),
//     exit: Effects.collapse(),
//     child: Details(),
//   );
//
// enter/exit are ordinary Effects (the reverse-able ones compose
// naturally). A null enter shows instantly; a null exit unmounts
// immediately.

import '../animation/animation.dart';
import '../animation/curves.dart';
import 'basic.dart' show EmptyBox;
import 'effects.dart';
import 'framework.dart';

/// Animates [child] in and out as [visible] toggles, deferring unmount
/// until the [exit] effect completes.
class Reveal extends StatefulWidget {
  const Reveal({
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
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> {
  // 1 = fully present, 0 = fully absent.
  late final Animation<double> _t = Animation(0.0);
  bool _present = false;
  bool _exiting = false;

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
  void didUpdateWidget(Reveal old) {
    super.didUpdateWidget(old);
    if (widget.visible == old.visible) return;
    if (widget.visible) {
      _appear();
    } else {
      _leave();
    }
  }

  void _appear() {
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
    if (widget.exit == null) {
      setState(() {
        _present = false;
        _exiting = false;
      });
      _t.snap(0.0);
      return;
    }
    setState(() => _exiting = true);
    _t.to(0.0, curve: _curve, duration: _duration).then((_) {
      // Fires on natural completion or cancel (a re-show supersedes
      // the exit). Only drop the child if we're still meant to be
      // gone.
      if (!mounted || widget.visible) return;
      setState(() {
        _present = false;
        _exiting = false;
      });
    });
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_present) return const EmptyBox();
    final t = _t.value; // subscribe to frame advances
    if (_exiting) {
      // exit effects map 0 = present → 1 = gone, so feed (1 - t).
      return widget.exit!.build(widget.child, (1 - t).clamp(0.0, 1.0));
    }
    final enter = widget.enter;
    if (enter == null) return widget.child;
    return enter.build(widget.child, t);
  }
}
