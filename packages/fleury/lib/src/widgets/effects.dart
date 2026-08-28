// Effects: fluent, composable entrance / emphasis / exit animations.
//
//   const Text('saved').animate().fadeIn().slideIn();
//   errorText.animate(trigger: errorRevision).flash();
//
// An Effect maps a single progress value (0..1) to a wrapped widget. Color and
// reveal effects composite painted cells; spatial effects use dedicated
// translation and aligned-clip render objects. Effects
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
import '../foundation/geometry.dart' show CellOffset, CellSize;
import '../rendering/cell.dart';
import '../rendering/render_effect.dart';
import '../rendering/render_flex.dart' show Axis;
import '../rendering/render_object.dart';
import 'align.dart' show Alignment;
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
  Widget buildSettled(Widget child) => _CellEffectWidget(
    composite: _identityComposite,
    passthrough: true,
    child: child,
  );

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

/// An effect that never animates — [build] at any progress delegates straight
/// to the child (via [buildSettled]). Used as the inert sentinel effect for a
/// no-transition route ([RouteTransition.none]) so that even code which plays
/// the effect directly, rather than honoring an isInstant flag, produces no
/// animation.
class NoopEffect extends Effect {
  const NoopEffect();
  @override
  Widget build(Widget child, double t) => buildSettled(child);
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

/// Bridges an expand/shrink clip to the render layer.
class _ClipWidget extends SingleChildRenderObjectWidget {
  const _ClipWidget({
    required this.widthFactor,
    required this.heightFactor,
    required this.alignment,
    required Widget super.child,
  });

  final double widthFactor;
  final double heightFactor;
  final Alignment alignment;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderClip(
    widthFactor: widthFactor,
    heightFactor: heightFactor,
    horizontalAlignment: _horizontalAlignment(alignment),
    verticalAlignment: _verticalAlignment(alignment),
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderClip renderObject,
  ) {
    renderObject
      ..widthFactor = widthFactor
      ..heightFactor = heightFactor
      ..horizontalAlignment = _horizontalAlignment(alignment)
      ..verticalAlignment = _verticalAlignment(alignment);
  }
}

class _TranslateWidget extends SingleChildRenderObjectWidget {
  const _TranslateWidget({
    this.horizontalFraction = 0,
    this.verticalFraction = 0,
    this.cellOffset = CellOffset.zero,
    required Widget super.child,
  });

  final double horizontalFraction;
  final double verticalFraction;
  final CellOffset cellOffset;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderCellTranslation(
        horizontalFraction: horizontalFraction,
        verticalFraction: verticalFraction,
        cellOffset: cellOffset,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderCellTranslation renderObject,
  ) {
    renderObject
      ..horizontalFraction = horizontalFraction
      ..verticalFraction = verticalFraction
      ..cellOffset = cellOffset;
  }
}

int _horizontalAlignment(Alignment alignment) => switch (alignment) {
  Alignment.topLeft || Alignment.centerLeft || Alignment.bottomLeft => -1,
  Alignment.topCenter || Alignment.center || Alignment.bottomCenter => 0,
  Alignment.topRight || Alignment.centerRight || Alignment.bottomRight => 1,
};

int _verticalAlignment(Alignment alignment) => switch (alignment) {
  Alignment.topLeft || Alignment.topCenter || Alignment.topRight => -1,
  Alignment.centerLeft || Alignment.center || Alignment.centerRight => 0,
  Alignment.bottomLeft || Alignment.bottomCenter || Alignment.bottomRight => 1,
};

// ---------------------------------------------------------------------------
// Concrete effects
// ---------------------------------------------------------------------------

RgbColor? _asRgb(Color? c) => c is RgbColor ? c : null;

class _FadeEffect extends Effect {
  const _FadeEffect({
    required this.out,
    required this.surface,
    required this.transparent,
  });
  final bool out;
  final RgbColor surface;
  final bool transparent;

  @override
  Widget build(Widget child, double t) => _CellEffectWidget(
    composite: (col, row, cell, size) {
      // p: 1 = fully visible, 0 = fully faded into the surface.
      final p = (out ? (1 - t) : t).clamp(0.0, 1.0);
      // A terminal cell has no alpha channel. In a cross-fade, continuing to
      // paint a dim cell below half visibility would still overwrite the more
      // visible route beneath it, and cells unique to an outgoing route would
      // linger until its final frame. Treat the less-visible half as
      // transparent so both directions hand each cell to the dominant route.
      if (transparent && p < 0.5) return null;
      final style = cell.style;
      final fg = _asRgb(style.foreground);
      final bg = _asRgb(style.background);
      if (fg != null) {
        var s = style.copyWith(foreground: rgbColorLerp(surface, fg, p));
        if (bg != null) {
          s = s.copyWith(background: rgbColorLerp(surface, bg, p));
        }
        return CellPlacement(col, row, s);
      }
      // A painted background is coverage, even when the foreground uses the
      // terminal default or the existing coarse ANSI/indexed fade path. Keep
      // writing the cell throughout the fade so opaque blank space does not
      // reveal content underneath, and fade the RGB background independently
      // of the foreground's coarse steps.
      if (bg != null) {
        // Fully faded: paint nothing. Coverage exists so a fade-in-progress
        // does not reveal content underneath a still-opaque panel — but once
        // the fade completes there is nothing left to hide, and continuing to
        // write the cell would leave the child's glyphs in the buffer behind
        // a surface-coloured block (invisible, yet still "on screen" to
        // anything reading text — e.g. a dismissed modal route).
        if (p <= 0) return null;
        final fadedBackground = rgbColorLerp(surface, bg, p);
        if (p < 0.34) {
          return CellPlacement(
            col,
            row,
            style.copyWith(
              foreground: fadedBackground,
              background: fadedBackground,
            ),
          );
        }
        if (p < 0.67) {
          return CellPlacement(
            col,
            row,
            style.copyWith(background: fadedBackground, dim: true),
          );
        }
        return CellPlacement(
          col,
          row,
          style.copyWith(background: fadedBackground),
        );
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
  final int? distance;
  final bool out;

  @override
  Widget build(Widget child, double t) {
    // Displacement fraction: in → starts displaced, ends 0;
    // out → starts 0, ends displaced.
    final amount = (out ? t : (1 - t)).clamp(0.0, 1.0);
    final fixedDistance = distance;
    if (fixedDistance != null) {
      final d = (fixedDistance * amount).round();
      final offset = switch (edge) {
        Edge.top => CellOffset(0, -d),
        Edge.bottom => CellOffset(0, d),
        Edge.left => CellOffset(-d, 0),
        Edge.right => CellOffset(d, 0),
      };
      return _TranslateWidget(cellOffset: offset, child: child);
    }
    final (horizontal, vertical) = switch (edge) {
      Edge.top => (0.0, -amount),
      Edge.bottom => (0.0, amount),
      Edge.left => (-amount, 0.0),
      Edge.right => (amount, 0.0),
    };
    return _TranslateWidget(
      horizontalFraction: horizontal,
      verticalFraction: vertical,
      child: child,
    );
  }

  @override
  Widget buildSettled(Widget child) => _TranslateWidget(child: child);
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

class _WipeEffect extends Effect {
  const _WipeEffect({required this.edge, required this.out});
  final Edge edge; // direction the wipe travels from
  final bool out;

  @override
  Widget build(Widget child, double t) => _CellEffectWidget(
    composite: (col, row, cell, size) {
      final p = (out ? (1 - t) : t).clamp(0.0, 1.0);
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
  const _ExpandEffect({
    required this.axis,
    required this.alignment,
    required this.shrink,
  });
  final Axis axis;
  final Alignment alignment;
  final bool shrink;

  @override
  Widget build(Widget child, double t) {
    final p = (shrink ? (1 - t) : t).clamp(0.0, 1.0);
    return _ClipWidget(
      widthFactor: axis == Axis.horizontal ? p : 1.0,
      heightFactor: axis == Axis.vertical ? p : 1.0,
      alignment: alignment,
      child: child,
    );
  }

  @override
  Widget buildSettled(Widget child) => _ClipWidget(
    widthFactor: 1,
    heightFactor: 1,
    alignment: alignment,
    child: child,
  );
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
  Widget build(Widget child, double t) {
    // Damped oscillation that settles to 0 at t = 1.
    final wobble = math.sin(t * math.pi * 6) * (1 - t);
    final d = (amplitude * wobble).round();
    return _TranslateWidget(
      cellOffset: axis == Axis.horizontal ? CellOffset(d, 0) : CellOffset(0, d),
      child: child,
    );
  }

  @override
  Widget buildSettled(Widget child) => _TranslateWidget(child: child);
}

/// Factory for the built-in effects. Compose with `+`:
///
///     Effects.fadeIn() + Effects.slideIn(from: Edge.left)
abstract final class Effects {
  /// Fades the child in from [surface] (default black). Smoothest on
  /// RGB-colored text; falls back to a coarse `dim` fade otherwise. RGB
  /// backgrounds always interpolate independently so filled cells retain
  /// their coverage throughout the fade. Set [transparent] for a cross-fade:
  /// cells below half visibility stop covering the layer underneath.
  static Effect fadeIn({
    RgbColor surface = const RgbColor(0, 0, 0),
    bool transparent = false,
  }) => _FadeEffect(out: false, surface: surface, transparent: transparent);

  /// Fades the child out toward [surface]. Set [transparent] when another
  /// layer should show through the less-visible half of the fade.
  static Effect fadeOut({
    RgbColor surface = const RgbColor(0, 0, 0),
    bool transparent = false,
  }) => _FadeEffect(out: true, surface: surface, transparent: transparent);

  /// Slides the child in from [from]. By default it begins one whole child
  /// extent away; pass [distance] to use a fixed number of cells instead.
  static Effect slideIn({Edge from = Edge.bottom, int? distance}) =>
      _SlideEffect(edge: from, distance: distance, out: false);

  /// Slides the child out toward [to]. By default it travels one whole child
  /// extent; pass [distance] to use a fixed number of cells instead.
  static Effect slideOut({Edge to = Edge.bottom, int? distance}) =>
      _SlideEffect(edge: to, distance: distance, out: true);

  /// Wipes the child progressively into view from [from].
  /// In-place (layout unchanged) — content appears, the box stays.
  static Effect wipeIn({Edge from = Edge.left}) =>
      _WipeEffect(edge: from, out: false);

  /// Wipes the child out of view toward [to] without changing layout.
  static Effect wipeOut({Edge to = Edge.left}) =>
      _WipeEffect(edge: to, out: true);

  /// Grows the box from zero along [axis], revealing content from [alignment]
  /// and reflowing siblings. The accordion / cell analog of scale-up.
  static Effect expand({
    Axis axis = Axis.vertical,
    Alignment alignment = Alignment.topLeft,
  }) => _ExpandEffect(axis: axis, alignment: alignment, shrink: false);

  /// Shrinks the box toward [alignment] (reverse of [expand]).
  static Effect shrink({
    Axis axis = Axis.vertical,
    Alignment alignment = Alignment.topLeft,
  }) => _ExpandEffect(axis: axis, alignment: alignment, shrink: true);

  /// One pulse of [color] (or reverse, for non-RGB text), peaking
  /// mid-animation and returning. Emphasis / "this just changed."
  static Effect flash({RgbColor color = const RgbColor(255, 220, 90)}) =>
      _FlashEffect(color: color);

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
/// in parallel (each targets a different channel).
///
/// With no [trigger], the chain runs once on mount — an entrance. Pass a
/// non-null event revision or token to [trigger] for replayable emphasis:
/// the first build rests at the finished state, then each changed token
/// restarts the effect from the beginning.
class Animate extends StatefulWidget {
  const Animate({
    required this.child,
    this.effects = const <Effect>[],
    this.duration,
    this.curve,
    this.trigger,
    this.repeat = false,
    super.key,
  });

  final Widget child;
  final List<Effect> effects;
  final Duration? duration;
  final Curve? curve;

  /// Replays the effect when this non-null token changes.
  ///
  /// Leave null for the default mount-time entrance. A trigger is usually an
  /// incrementing revision (`saveRevision++`) rather than a boolean: every
  /// distinct value represents a new event, including consecutive events of
  /// the same kind.
  final Object? trigger;

  /// Loops the progress forever (also implied by a looping effect
  /// like shimmer / pulse).
  final bool repeat;

  Animate _add(Effect effect) => Animate(
    effects: <Effect>[...effects, effect],
    duration: duration,
    curve: curve,
    trigger: trigger,
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

  Animate slideIn({Edge from = Edge.bottom, int? distance}) =>
      _add(Effects.slideIn(from: from, distance: distance));

  Animate slideOut({Edge to = Edge.bottom, int? distance}) =>
      _add(Effects.slideOut(to: to, distance: distance));

  Animate wipeIn({Edge from = Edge.left}) => _add(Effects.wipeIn(from: from));

  Animate wipeOut({Edge to = Edge.left}) => _add(Effects.wipeOut(to: to));

  Animate expand({
    Axis axis = Axis.vertical,
    Alignment alignment = Alignment.topLeft,
  }) => _add(Effects.expand(axis: axis, alignment: alignment));

  Animate shrink({
    Axis axis = Axis.vertical,
    Alignment alignment = Alignment.topLeft,
  }) => _add(Effects.shrink(axis: axis, alignment: alignment));

  Animate flash({RgbColor color = const RgbColor(255, 220, 90)}) =>
      _add(Effects.flash(color: color));

  Animate shimmer({
    RgbColor highlight = const RgbColor(255, 255, 255),
    int band = 3,
  }) => _add(Effects.shimmer(highlight: highlight, band: band));

  Animate pulse({RgbColor to = const RgbColor(255, 255, 255)}) =>
      _add(Effects.pulse(to: to));

  Animate shake({Axis axis = Axis.horizontal, int amplitude = 1}) =>
      _add(Effects.shake(axis: axis, amplitude: amplitude));

  @override
  State<Animate> createState() => _AnimateState();
}

class _AnimateState extends State<Animate> {
  late final Animation<double> _t = Animation(
    widget.trigger == null ? 0.0 : 1.0,
  );

  Duration get _duration =>
      widget.duration ?? const Duration(milliseconds: 300);
  Curve get _curve => widget.curve ?? Curves.easeOut;

  bool get _loops => widget.repeat || widget.effects.any((e) => e.loops);

  bool _loopsFor(Animate candidate) =>
      candidate.repeat || candidate.effects.any((effect) => effect.loops);

  @override
  void initState() {
    super.initState();
    if (_loops) {
      _t.loop(between: (0.0, 1.0), period: _duration, mirror: false);
    } else if (widget.trigger == null) {
      _t.to(1.0, curve: _curve, duration: _duration);
    }
  }

  @override
  void didUpdateWidget(Animate old) {
    super.didUpdateWidget(old);
    final wasLooping = _loopsFor(old);
    if (_loops != wasLooping) {
      if (_loops) {
        _t.loop(between: (0.0, 1.0), period: _duration, mirror: false);
      } else {
        _t.snap(1.0);
      }
      return;
    }
    if (_loops) {
      if (widget.duration != old.duration || widget.curve != old.curve) {
        _t.loop(between: (0.0, 1.0), period: _duration, mirror: false);
      }
      return;
    }
    if (widget.trigger != null && widget.trigger != old.trigger) {
      _t.snap(0.0);
      _t.to(1.0, curve: _curve, duration: _duration);
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
///     field.animate(trigger: errorRevision).shake();
extension AnimateExtension on Widget {
  /// Starts an [Animate] chain over this widget. [duration] / [curve]
  /// apply to the whole chain. With no [trigger] it plays on mount; with a
  /// non-null trigger it rests on mount and replays whenever the token changes.
  Animate animate({
    Duration? duration,
    Curve? curve,
    Object? trigger,
    bool repeat = false,
  }) => Animate(
    duration: duration,
    curve: curve,
    trigger: trigger,
    repeat: repeat,
    child: this,
  );
}
