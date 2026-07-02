// Effects: fluent, composable entrance / emphasis / exit animations.
//
//   const Text('saved').animate(Effects.fadeIn() + Effects.slideIn());
//   errorText.animate(Effects.flash(), play: hasError);
//
// An Effect maps a single progress value (0..1) to a wrapped widget,
// compositing the child's painted cells via RenderCellEffect. Effects
// run in parallel — `a + b` applies both at the same progress — and
// each targets a different visual channel (color, position) so they
// stack cleanly. Everything bottoms out in Animation, so effects
// inherit spring/curve, AnimationPolicy (disabled → instant), and
// FakeClock determinism.
//
// Effects are for entrance/emphasis/exit. For "a value follows
// state," use AnimationBuilder; to drive imperatively, hold an
// Animation.

import 'dart:math' as math;

import '../animation/animation.dart';
import '../animation/curves.dart';
import '../animation/lerp.dart';
import '../foundation/geometry.dart' show CellSize;
import '../rendering/cell.dart';
import '../rendering/render_effect.dart';
import '../rendering/render_flex.dart' show Axis;
import '../rendering/render_object.dart';
import 'framework.dart';

/// A screen edge an effect moves toward / from.
enum Edge { top, bottom, left, right }

/// A composable visual effect. Maps progress `t` in `[0, 1]` to a
/// widget that wraps [child]. Combine with `+` to run in parallel.
abstract class Effect {
  const Effect();

  /// Wraps [child], applying this effect at progress [t].
  Widget build(Widget child, double t);

  /// Wraps [child] in this effect's AT-REST form: the same widget tree
  /// shape as [build] (so the element — and the subtree's State — survives
  /// the animating→settled switch), but painting delegates straight to the
  /// child. Used by the navigator for settled routes: keeping the live
  /// composite at full progress would pay a scratch-buffer double paint
  /// every frame, drop protocol (image) cells, and record scratch-local
  /// focus/pointer geometry. Override alongside [build] if an effect wraps
  /// in something other than a single cell-effect widget.
  Widget buildSettled(Widget child) =>
      _CellEffectWidget(composite: _identityComposite, passthrough: true, child: child);

  static CellPlacement? _identityComposite(
    int col,
    int row,
    Cell cell,
    CellSize size,
  ) => CellPlacement(col, row, cell.style);

  /// Whether this effect runs continuously (shimmer, pulse). When
  /// true, [Animate] loops the progress instead of playing once.
  bool get loops => false;

  /// Runs this effect and [other] together at the same progress.
  Effect operator +(Effect other) => _CombinedEffect(<Effect>[this, other]);
}

class _CombinedEffect extends Effect {
  const _CombinedEffect(this._effects);
  final List<Effect> _effects;

  @override
  Widget build(Widget child, double t) {
    var result = child;
    for (final effect in _effects) {
      result = effect.build(result, t);
    }
    return result;
  }

  @override
  Widget buildSettled(Widget child) {
    // Mirror [build]'s nesting exactly so the element tree keeps its shape
    // (one wrapper per effect) across the animating→settled switch.
    var result = child;
    for (final effect in _effects) {
      result = effect.buildSettled(result);
    }
    return result;
  }

  @override
  bool get loops => _effects.any((e) => e.loops);

  @override
  Effect operator +(Effect other) =>
      _CombinedEffect(<Effect>[..._effects, other]);
}

/// Bridges an Effect's per-cell composite to the render layer.
class _CellEffectWidget extends SingleChildRenderObjectWidget {
  const _CellEffectWidget({
    required this.composite,
    this.passthrough = false,
    required Widget super.child,
  });

  final CellComposite composite;

  /// When true the render object paints the child directly (no composite):
  /// the at-rest form produced by [Effect.buildSettled].
  final bool passthrough;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderCellEffect(composite, passthrough: passthrough);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderCellEffect renderObject,
  ) {
    renderObject
      ..composite = composite
      ..passthrough = passthrough;
  }
}

/// Bridges an expand/collapse clip to the render layer.
class _ClipWidget extends SingleChildRenderObjectWidget {
  const _ClipWidget({
    required this.widthFactor,
    required this.heightFactor,
    required Widget super.child,
  });

  final double widthFactor;
  final double heightFactor;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderClip(widthFactor: widthFactor, heightFactor: heightFactor);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderClip renderObject,
  ) {
    renderObject
      ..widthFactor = widthFactor
      ..heightFactor = heightFactor;
  }
}

// ---------------------------------------------------------------------------
// Concrete effects
// ---------------------------------------------------------------------------

RgbColor? _asRgb(Color? c) => c is RgbColor ? c : null;

class _FadeEffect extends Effect {
  const _FadeEffect({required this.out, required this.surface});
  final bool out;
  final RgbColor surface;

  @override
  Widget build(Widget child, double t) => _CellEffectWidget(
    composite: (col, row, cell, size) {
      // p: 1 = fully visible, 0 = fully faded into the surface.
      final p = (out ? (1 - t) : t).clamp(0.0, 1.0);
      final style = cell.style;
      final fg = _asRgb(style.foreground);
      if (fg != null) {
        var s = style.copyWith(foreground: rgbColorLerp(surface, fg, p));
        final bg = _asRgb(style.background);
        if (bg != null) {
          s = s.copyWith(background: rgbColorLerp(surface, bg, p));
        }
        return CellPlacement(col, row, s);
      }
      // No RGB foreground to lerp: coarse 3-step fade via `dim`.
      if (p < 0.34) return null; // invisible
      if (p < 0.67) return CellPlacement(col, row, style.copyWith(dim: true));
      return CellPlacement(col, row, style);
    },
    child: child,
  );
}

class _SlideEffect extends Effect {
  const _SlideEffect({
    required this.edge,
    required this.distance,
    required this.out,
  });
  final Edge edge;
  final int distance;
  final bool out;

  @override
  Widget build(Widget child, double t) => _CellEffectWidget(
    composite: (col, row, cell, size) {
      // Displacement fraction: in → starts displaced, ends 0;
      // out → starts 0, ends displaced.
      final amt = (out ? t : (1 - t)).clamp(0.0, 1.0);
      final d = (distance * amt).round();
      final (dx, dy) = switch (edge) {
        Edge.top => (0, -d),
        Edge.bottom => (0, d),
        Edge.left => (-d, 0),
        Edge.right => (d, 0),
      };
      return CellPlacement(col + dx, row + dy, cell.style);
    },
    child: child,
  );
}

class _FlashEffect extends Effect {
  const _FlashEffect({required this.color});
  final RgbColor color;

  @override
  Widget build(Widget child, double t) => _CellEffectWidget(
    composite: (col, row, cell, size) {
      // Triangle: 0 → 1 → 0 across t, so it peaks mid-animation
      // and returns, using a single forward progress.
      final tri = math.sin(t * math.pi).clamp(0.0, 1.0);
      final style = cell.style;
      final fg = _asRgb(style.foreground);
      if (fg != null) {
        return CellPlacement(
          col,
          row,
          style.copyWith(foreground: rgbColorLerp(fg, color, tri)),
        );
      }
      return CellPlacement(col, row, style.copyWith(inverse: tri > 0.5));
    },
    child: child,
  );
}

class _RevealEffect extends Effect {
  const _RevealEffect({required this.edge, required this.conceal});
  final Edge edge; // direction the wipe travels from
  final bool conceal;

  @override
  Widget build(Widget child, double t) => _CellEffectWidget(
    composite: (col, row, cell, size) {
      final p = (conceal ? (1 - t) : t).clamp(0.0, 1.0);
      final visible = switch (edge) {
        Edge.left => col < (size.cols * p).round(),
        Edge.right => col >= size.cols - (size.cols * p).round(),
        Edge.top => row < (size.rows * p).round(),
        Edge.bottom => row >= size.rows - (size.rows * p).round(),
      };
      return visible ? CellPlacement(col, row, cell.style) : null;
    },
    child: child,
  );
}

class _ExpandEffect extends Effect {
  const _ExpandEffect({required this.axis, required this.collapse});
  final Axis axis;
  final bool collapse;

  @override
  Widget build(Widget child, double t) {
    final p = (collapse ? (1 - t) : t).clamp(0.0, 1.0);
    return _ClipWidget(
      widthFactor: axis == Axis.horizontal ? p : 1.0,
      heightFactor: axis == Axis.vertical ? p : 1.0,
      child: child,
    );
  }
}

class _ShimmerEffect extends Effect {
  const _ShimmerEffect({required this.highlight, required this.band});
  final RgbColor highlight;
  final int band;

  @override
  bool get loops => true;

  @override
  Widget build(Widget child, double t) => _CellEffectWidget(
    composite: (col, row, cell, size) {
      // Band center sweeps left→right, entering and exiting fully.
      final center = t * (size.cols + 2 * band) - band;
      final dist = (col - center).abs();
      final intensity = (1 - dist / band).clamp(0.0, 1.0);
      final style = cell.style;
      final fg = _asRgb(style.foreground);
      if (fg != null) {
        return CellPlacement(
          col,
          row,
          style.copyWith(foreground: rgbColorLerp(fg, highlight, intensity)),
        );
      }
      return CellPlacement(col, row, style.copyWith(bold: intensity > 0.5));
    },
    child: child,
  );
}

class _PulseEffect extends Effect {
  const _PulseEffect({required this.to});
  final RgbColor to;

  @override
  bool get loops => true;

  @override
  Widget build(Widget child, double t) => _CellEffectWidget(
    composite: (col, row, cell, size) {
      // 0 → 1 → 0 across one cycle, continuous at the loop seam.
      final intensity = (1 - math.cos(t * 2 * math.pi)) / 2;
      final style = cell.style;
      final fg = _asRgb(style.foreground);
      if (fg != null) {
        return CellPlacement(
          col,
          row,
          style.copyWith(foreground: rgbColorLerp(fg, to, intensity)),
        );
      }
      return CellPlacement(col, row, style.copyWith(bold: intensity > 0.5));
    },
    child: child,
  );
}

class _ShakeEffect extends Effect {
  const _ShakeEffect({required this.axis, required this.amplitude});
  final Axis axis;
  final int amplitude;

  @override
  Widget build(Widget child, double t) => _CellEffectWidget(
    composite: (col, row, cell, size) {
      // Damped oscillation that settles to 0 at t = 1.
      final wobble = math.sin(t * math.pi * 6) * (1 - t);
      final d = (amplitude * wobble).round();
      final dx = axis == Axis.horizontal ? d : 0;
      final dy = axis == Axis.vertical ? d : 0;
      return CellPlacement(col + dx, row + dy, cell.style);
    },
    child: child,
  );
}

/// Factory for the built-in effects. Compose with `+`:
///
///     Effects.fadeIn() + Effects.slideIn(from: Edge.left)
abstract final class Effects {
  /// Fades the child in from [surface] (default black). Smoothest on
  /// RGB-colored text; falls back to a coarse `dim` fade otherwise.
  static Effect fadeIn({RgbColor surface = const RgbColor(0, 0, 0)}) =>
      _FadeEffect(out: false, surface: surface);

  /// Fades the child out toward [surface].
  static Effect fadeOut({RgbColor surface = const RgbColor(0, 0, 0)}) =>
      _FadeEffect(out: true, surface: surface);

  /// Slides the child in from [from], [distance] cells away.
  static Effect slideIn({Edge from = Edge.bottom, int distance = 1}) =>
      _SlideEffect(edge: from, distance: distance, out: false);

  /// Slides the child out toward [to].
  static Effect slideOut({Edge to = Edge.bottom, int distance = 1}) =>
      _SlideEffect(edge: to, distance: distance, out: true);

  /// One pulse of [color] (or inverse, for non-RGB text), peaking
  /// mid-animation and returning. Emphasis / "this just changed."
  static Effect flash({RgbColor color = const RgbColor(255, 220, 90)}) =>
      _FlashEffect(color: color);

  /// Typewriter / wipe: reveals the child progressively from [from].
  /// In-place (layout unchanged) — content appears, the box stays.
  static Effect reveal({Edge from = Edge.left}) =>
      _RevealEffect(edge: from, conceal: false);

  /// Reverse of [reveal] — wipes the child away toward [to].
  static Effect conceal({Edge to = Edge.left}) =>
      _RevealEffect(edge: to, conceal: true);

  /// Grows the box from zero along [axis], clipping content and
  /// reflowing siblings. The accordion / cell analog of scale-up.
  static Effect expand({Axis axis = Axis.vertical}) =>
      _ExpandEffect(axis: axis, collapse: false);

  /// Shrinks the box to zero along [axis] (reverse of [expand]).
  static Effect collapse({Axis axis = Axis.vertical}) =>
      _ExpandEffect(axis: axis, collapse: true);

  /// A bright highlight band sweeps across the child — the skeleton-
  /// loader effect. Loops automatically.
  static Effect shimmer({
    RgbColor highlight = const RgbColor(255, 255, 255),
    int band = 3,
  }) => _ShimmerEffect(highlight: highlight, band: band);

  /// Gentle looping "breathing" toward [to] and back — a live/active
  /// indicator. Loops automatically.
  static Effect pulse({RgbColor to = const RgbColor(255, 255, 255)}) =>
      _PulseEffect(to: to);

  /// Damped jitter along [axis] that settles to rest — error feedback.
  static Effect shake({Axis axis = Axis.horizontal, int amplitude = 1}) =>
      _ShakeEffect(axis: axis, amplitude: amplitude);
}

// ---------------------------------------------------------------------------
// Animate widget + .animate() chain
// ---------------------------------------------------------------------------

/// Plays a stack of effects over [child], driving a 0→1 progress with
/// the shared animation engine. Build it fluently from a widget:
///
///     const Text('Hi').animate().fadeIn().slideIn(from: Edge.left);
///
/// Each effect method appends to the stack and returns a new [Animate],
/// so the chain reads top-to-bottom as the effects applied. Effects run
/// in parallel (each targets a different channel). With [play] true (the
/// default) the chain runs forward on mount — an entrance.
class Animate extends StatefulWidget {
  const Animate({
    required this.child,
    this.effects = const <Effect>[],
    this.duration,
    this.curve,
    this.play = true,
    this.repeat = false,
    super.key,
  });

  final Widget child;
  final List<Effect> effects;
  final Duration? duration;
  final Curve? curve;
  final bool play;

  /// Loops the progress forever (also implied by a looping effect
  /// like shimmer / pulse).
  final bool repeat;

  Animate _add(Effect effect) => Animate(
    effects: <Effect>[...effects, effect],
    duration: duration,
    curve: curve,
    play: play,
    repeat: repeat,
    key: key,
    child: child,
  );

  /// Appends a pre-built [effect] (e.g. a shared/reusable one).
  Animate effect(Effect effect) => _add(effect);

  // -- Chainable effect methods (mirror the `Effects` factory) --------

  Animate fadeIn({RgbColor surface = const RgbColor(0, 0, 0)}) =>
      _add(Effects.fadeIn(surface: surface));

  Animate fadeOut({RgbColor surface = const RgbColor(0, 0, 0)}) =>
      _add(Effects.fadeOut(surface: surface));

  Animate slideIn({Edge from = Edge.bottom, int distance = 1}) =>
      _add(Effects.slideIn(from: from, distance: distance));

  Animate slideOut({Edge to = Edge.bottom, int distance = 1}) =>
      _add(Effects.slideOut(to: to, distance: distance));

  Animate reveal({Edge from = Edge.left}) => _add(Effects.reveal(from: from));

  Animate conceal({Edge to = Edge.left}) => _add(Effects.conceal(to: to));

  Animate expand({Axis axis = Axis.vertical}) =>
      _add(Effects.expand(axis: axis));

  Animate collapse({Axis axis = Axis.vertical}) =>
      _add(Effects.collapse(axis: axis));

  Animate shimmer({
    RgbColor highlight = const RgbColor(255, 255, 255),
    int band = 3,
  }) => _add(Effects.shimmer(highlight: highlight, band: band));

  Animate pulse({RgbColor to = const RgbColor(255, 255, 255)}) =>
      _add(Effects.pulse(to: to));

  Animate shake({Axis axis = Axis.horizontal, int amplitude = 1}) =>
      _add(Effects.shake(axis: axis, amplitude: amplitude));

  Animate flash({RgbColor color = const RgbColor(255, 220, 90)}) =>
      _add(Effects.flash(color: color));

  @override
  State<Animate> createState() => _AnimateState();
}

class _AnimateState extends State<Animate> {
  late final Animation<double> _t = Animation(widget.play ? 0.0 : 1.0);

  Duration get _duration =>
      widget.duration ?? const Duration(milliseconds: 300);
  Curve get _curve => widget.curve ?? Curves.easeOut;

  bool get _loops => widget.repeat || widget.effects.any((e) => e.loops);

  @override
  void initState() {
    super.initState();
    if (_loops) {
      _t.loop(between: (0.0, 1.0), period: _duration, mirror: false);
    } else if (widget.play) {
      _t.to(1.0, curve: _curve, duration: _duration);
    }
  }

  @override
  void didUpdateWidget(Animate old) {
    super.didUpdateWidget(old);
    if (widget.play != old.play && !_loops) {
      _t.to(widget.play ? 1.0 : 0.0, curve: _curve, duration: _duration);
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t.value;
    var result = widget.child;
    for (final effect in widget.effects) {
      result = effect.build(result, t);
    }
    return result;
  }
}

/// `widget.animate()` — the fluent entry point. Chain effect methods:
///
///     text.animate().fadeIn().slideIn();
///     loader.animate().shimmer();          // auto-loops
///     field.animate(play: invalid).shake();
extension AnimateExtension on Widget {
  /// Starts an [Animate] chain over this widget. [duration] / [curve]
  /// apply to the whole chain; [play] runs it forward on mount.
  Animate animate({
    Duration? duration,
    Curve? curve,
    bool play = true,
    bool repeat = false,
  }) => Animate(
    duration: duration,
    curve: curve,
    play: play,
    repeat: repeat,
    child: this,
  );
}
