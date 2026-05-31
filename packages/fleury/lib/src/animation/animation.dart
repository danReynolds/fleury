// Animation<T>: a value that you read directly, retarget with one verb,
// and never have to dispose.
//
// Animation is the continuous-animation front door. It holds a current
// value (always readable via `value`), a target, and an engine that
// moves one toward the other every frame. The default engine is a
// spring (see spring.dart) chosen for its interruption behavior:
// retargeting mid-flight continues from the live value AND velocity,
// so redirects never snap-restart.
//
//   final fill = Animation(0.0);
//   fill.to(0.8);                       // spring (default)
//   fill.to(0.8, spring: Spring.snappy);
//   fill.to(0.8, curve: Curves.easeOut, duration: 300.ms);
//   fill.snap(0.0);                     // jump, no animation
//   fill.value                          // current interpolated value
//
// Animation runs on the existing TickerScheduler (one shared timer for
// the whole app) and respects AnimationPolicy + TickerMode through
// the Ticker it owns. It attaches to the runtime's TuiBinding the
// first time a widget displays it; retargeting before first display
// snaps (you can't animate something not yet on screen).
//
// Consumption: a widget reads `animation.value`. Today vian AnimationBuilder
// (animation_builder.dart); a later step makes reading `value` during a
// build auto-subscribe the element.

import 'package:meta/meta.dart';

import '../foundation/change_notifier.dart';
import '../foundation/geometry.dart';
import '../rendering/cell.dart';
import '../widgets/framework.dart';
import '../widgets/tui_binding.dart';
import 'animation_policy.dart';
import 'curves.dart';
import 'spring.dart';
import 'ticker.dart';
import 'ticker_future.dart';
import 'ticker_scheduler.dart';

/// Converts a value of type [T] to and from a vector of doubles so
/// the spring engine can integrate each component independently.
///
/// Built-in types ([double], [int], [RgbColor], [CellOffset]) are
/// resolved automatically by [Animation]. For a custom [T], pass a
/// [AnimationType] to the [Animation] constructor.
class AnimationType<T> {
  const AnimationType({
    required this.toVector,
    required this.fromVector,
    this.epsilon = 0.01,
  });

  /// Decomposes a value into its animatable scalar components.
  final List<double> Function(T value) toVector;

  /// Reassembles a value from scalar components.
  final T Function(List<double> v) fromVector;

  /// Settle threshold per component: when every component is within
  /// [epsilon] of its target (in both position and per-second
  /// velocity) the spring snaps to the exact target and stops.
  final double epsilon;

  static const AnimationType<double> forDouble = AnimationType<double>(
    toVector: _doubleToVec,
    fromVector: _doubleFromVec,
    epsilon: 0.001,
  );

  static const AnimationType<int> forInt = AnimationType<int>(
    toVector: _intToVec,
    fromVector: _intFromVec,
    epsilon: 0.4,
  );

  static const AnimationType<RgbColor> forRgbColor = AnimationType<RgbColor>(
    toVector: _rgbToVec,
    fromVector: _rgbFromVec,
    epsilon: 0.5,
  );

  static const AnimationType<CellOffset> forCellOffset =
      AnimationType<CellOffset>(
        toVector: _offsetToVec,
        fromVector: _offsetFromVec,
        epsilon: 0.4,
      );

  /// Resolves the built-in [AnimationType] for [T], or throws if [T]
  /// isn't a built-in (pass an explicit type to [Animation] instead).
  static AnimationType<T> of<T>() {
    if (T == double) return forDouble as AnimationType<T>;
    if (T == int) return forInt as AnimationType<T>;
    if (T == RgbColor) return forRgbColor as AnimationType<T>;
    if (T == CellOffset) return forCellOffset as AnimationType<T>;
    throw ArgumentError(
      'No built-in AnimationType for $T. Pass `type:` to the Animation '
      'constructor with toVector / fromVector for this type.',
    );
  }
}

List<double> _doubleToVec(double v) => [v];
double _doubleFromVec(List<double> v) => v[0];
List<double> _intToVec(int v) => [v.toDouble()];
int _intFromVec(List<double> v) => v[0].round();
List<double> _rgbToVec(RgbColor c) => [
  c.r.toDouble(),
  c.g.toDouble(),
  c.b.toDouble(),
];
RgbColor _rgbFromVec(List<double> v) => RgbColor(
  v[0].round().clamp(0, 255),
  v[1].round().clamp(0, 255),
  v[2].round().clamp(0, 255),
);
List<double> _offsetToVec(CellOffset o) => [o.col.toDouble(), o.row.toDouble()];
CellOffset _offsetFromVec(List<double> v) =>
    CellOffset(v[0].round(), v[1].round());

/// Largest per-frame timestep the integrator will take. A stalled
/// frame (SSH lag, GC pause) is clamped so the spring can't explode.
const Duration _maxStep = Duration(milliseconds: 66);

/// A value that animates toward whatever you retarget it to.
class Animation<T> extends ChangeNotifier implements ElementDependency {
  /// Creates a animation holding [value]. [type] is required only for
  /// non-built-in [T]; built-ins ([double], [int], [RgbColor],
  /// [CellOffset]) resolve automatically.
  Animation(T value, {AnimationType<T>? type})
    : _type = type ?? AnimationType.of<T>(),
      _value = value {
    _position = _type.toVector(value);
    _velocity = List<double>.filled(_position.length, 0.0);
    _target = List<double>.of(_position);
  }

  final AnimationType<T> _type;

  T _value;
  late List<double> _position;
  late List<double> _velocity;
  late List<double> _target;

  TickerScheduler? _scheduler;
  Ticker? _ticker;
  AnimationPolicy _policy = AnimationPolicy.enabled;
  bool _disposed = false;

  // Active-animation engine state.
  Spring? _spring; // non-null => spring engine
  Curve? _curve; // non-null => curve engine
  Duration _curveDuration = Duration.zero;
  Duration _curveStart = Duration.zero;
  List<double> _curveFrom = const [];
  Duration _lastElapsed = Duration.zero;
  TickerFuture? _active;

  // Loop state (set by loop()).
  bool _looping = false;
  bool _loopMirror = true;
  List<double> _loopA = const [];
  List<double> _loopB = const [];
  Curve _loopCurve = Curves.linear;
  Duration _loopPeriod = Duration.zero;

  // Sequence state (set by run()).
  List<AnimationStep<T>>? _queue;
  int _queueIndex = 0;

  // An animation requested before attach, replayed on attach.
  void Function()? _pendingOnAttach;

  /// Elements that read [value] during their build, auto-subscribed
  /// for rebuild on change. Distinct from [ChangeNotifier] listeners
  /// (which AnimationBuilder uses).
  final Set<Element> _dependents = <Element>{};

  /// The current interpolated value.
  ///
  /// Reading this during a widget's build auto-subscribes that widget:
  /// it rebuilds whenever the animation advances, and the animation attaches
  /// to the enclosing [TuiBinding] so it can animate. Reading outside
  /// a build is a plain value read with no subscription.
  T get value {
    final element = Element.current;
    if (element != null) {
      element.dependOnExternal(this);
      if (_scheduler == null) {
        final binding = TuiBinding.maybeOf(element);
        if (binding != null) attach(binding);
      }
    }
    return _value;
  }

  @override
  void addDependent(Element element) => _dependents.add(element);

  @override
  void removeDependent(Element element) => _dependents.remove(element);

  /// Notifies explicit listeners (AnimationBuilder) AND marks every
  /// implicitly-subscribed element dirty.
  void _notify() {
    notifyListeners();
    if (_dependents.isEmpty) return;
    for (final element in _dependents.toList(growable: false)) {
      element.markNeedsBuild();
    }
  }

  /// The value this animation is currently heading toward.
  T get target => _type.fromVector(_target);

  /// Whether an animation is in flight.
  bool get isMoving => _ticker?.isActive ?? false;

  /// Binds this animation to the runtime's scheduler + policy. Called by
  /// the consuming widget (e.g. AnimationBuilder) on first build.
  /// Idempotent.
  @internal
  void attach(TuiBinding binding) {
    if (_scheduler != null || _disposed) return;
    _scheduler = binding.tickerScheduler;
    _policy = binding.animationPolicy;
    _ticker = Ticker(_tick, scheduler: _scheduler!);
    _scheduler!.registerReassembleCallback(_onReassemble);
    // Run any animation requested before this animation was on screen
    // (the "animate on appear" idiom: `Animation(0)..to(1)`).
    final pending = _pendingOnAttach;
    _pendingOnAttach = null;
    pending?.call();
  }

  /// Jumps to [value] immediately, cancelling any animation. Use for
  /// initial state or hard resets.
  void snap(T value) {
    _stop(canceled: true);
    _value = value;
    _position = _type.toVector(value);
    _velocity = List<double>.filled(_position.length, 0.0);
    _target = List<double>.of(_position);
    _notify();
  }

  /// Retargets to [target]. With no [curve], uses the spring engine
  /// ([spring] or [Spring.smooth]) — interruption-friendly, picks up
  /// from the current value+velocity. With a [curve], uses
  /// deterministic easing over [duration] (defaults to 250ms);
  /// interrupting a curve restarts from the current value with zero
  /// velocity.
  ///
  /// Returns a [TickerFuture]: `await` it for settle;
  /// `await .orCancel` to see retargets/stops as [TickerCanceled].
  TickerFuture to(
    T target, {
    Spring? spring,
    Curve? curve,
    Duration? duration,
  }) {
    if (_disposed) {
      throw StateError('Animation.to() called after dispose.');
    }
    _target = _type.toVector(target);
    final future = _beginRequest();
    _runOrDefer(() {
      if (_snapIfNoAnimation()) return;
      _ensureTicking();
      _arm(spring: spring, curve: curve, duration: duration);
    });
    return future;
  }

  /// Repeats forever between [between]'s two values. With
  /// [mirror] (the default) the direction reverses each cycle
  /// (a→b→a→b…); without it, each cycle restarts from the first value
  /// (a→b, a→b…). [period] and [curve] control one leg of the cycle.
  ///
  /// The returned [TickerFuture] only completes if the loop is later
  /// superseded by [to] / [snap] / [stop] (as a cancel) — a loop has
  /// no natural end.
  TickerFuture loop({
    required (T, T) between,
    Duration period = const Duration(milliseconds: 600),
    Curve curve = Curves.linear,
    bool mirror = true,
  }) {
    if (_disposed) throw StateError('Animation.loop() called after dispose.');
    final a = _type.toVector(between.$1);
    final b = _type.toVector(between.$2);
    final future = _beginRequest();
    _runOrDefer(() {
      if (_policy == AnimationPolicy.disabled) {
        // No animation: rest at the first value, future stays open (a
        // loop has no natural completion to await).
        _position = List<double>.of(a);
        _target = List<double>.of(a);
        _value = _type.fromVector(_position);
        _notify();
        return;
      }
      _position = List<double>.of(a);
      _value = _type.fromVector(_position);
      _looping = true;
      _loopMirror = mirror;
      _loopA = a;
      _loopB = b;
      _loopCurve = curve;
      _loopPeriod = period;
      _ensureTicking();
      _curve = curve;
      _spring = null;
      _curveDuration = period;
      _curveFrom = List<double>.of(a);
      _target = List<double>.of(b);
      _curveStart = _lastElapsed;
      _notify();
    });
    return future;
  }

  /// Runs a sequence of [steps] back-to-back, each starting when the
  /// previous settles. Steps are [AnimationStep.to] (retarget) or
  /// [AnimationStep.hold] (wait, clock-driven so it's FakeClock-safe).
  /// The returned future completes when the last step settles.
  TickerFuture run(List<AnimationStep<T>> steps) {
    if (_disposed) throw StateError('Animation.run() called after dispose.');
    if (steps.isEmpty) return TickerFuture.complete();
    final future = _beginRequest();
    _runOrDefer(() {
      if (_policy == AnimationPolicy.disabled) {
        for (final s in steps) {
          if (!s._isHold) _target = _type.toVector(s._target as T);
        }
        _snapToTarget();
        _completeActive();
        return;
      }
      _queue = steps;
      _queueIndex = 0;
      _ensureTicking();
      _applyStep(steps[_queueIndex++]);
    });
    return future;
  }

  /// Stops the animation where it is, keeping the current value.
  void stop() {
    _looping = false;
    _queue = null;
    _stop(canceled: true);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _scheduler?.unregisterReassembleCallback(_onReassemble);
    _stop(canceled: true);
    _ticker?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------

  void _tick(Duration elapsed) {
    var dt = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    if (dt > _maxStep) dt = _maxStep;
    final dtSeconds = dt.inMicroseconds / 1e6;
    if (dtSeconds <= 0) return;

    final settled = _curve != null
        ? _stepCurve(elapsed)
        : _stepSpring(dtSeconds);

    _value = _type.fromVector(_position);
    _notify();

    if (!settled) return;

    // Loop: re-arm the next leg without stopping.
    if (_looping) {
      if (_loopMirror) {
        final from = _curveFrom;
        _curveFrom = List<double>.of(_target);
        _target = from;
      } else {
        _position = List<double>.of(_loopA);
        _curveFrom = List<double>.of(_loopA);
        _target = List<double>.of(_loopB);
      }
      _curve = _loopCurve;
      _curveDuration = _loopPeriod;
      _curveStart = elapsed;
      return;
    }

    // Sequence: advance to the next step without stopping.
    final queue = _queue;
    if (queue != null && _queueIndex < queue.length) {
      _applyStep(queue[_queueIndex++]);
      _curveStart = elapsed;
      return;
    }

    // Done.
    _queue = null;
    _snapToTarget();
    final f = _active;
    _active = null;
    _ticker!.stop();
    f?.completeNaturally();
  }

  bool _stepSpring(double dt) {
    final spring = _spring!;
    final eps = _type.epsilon;
    var allSettled = true;
    for (var i = 0; i < _position.length; i++) {
      final (p, v) = spring.step(
        position: _position[i],
        velocity: _velocity[i],
        target: _target[i],
        dt: dt,
      );
      _position[i] = p;
      _velocity[i] = v;
      if ((p - _target[i]).abs() >= eps || v.abs() >= eps) {
        allSettled = false;
      }
    }
    return allSettled;
  }

  bool _stepCurve(Duration elapsed) {
    final dur = _curveDuration.inMicroseconds;
    final since = (elapsed - _curveStart).inMicroseconds;
    final raw = dur <= 0 ? 1.0 : since / dur;
    final t = raw.clamp(0.0, 1.0);
    final eased = _curve!.transform(t);
    for (var i = 0; i < _position.length; i++) {
      _position[i] = _curveFrom[i] + (_target[i] - _curveFrom[i]) * eased;
    }
    return t >= 1.0;
  }

  void _snapToTarget() {
    _position = List<double>.of(_target);
    _velocity = List<double>.filled(_position.length, 0.0);
    _value = _type.fromVector(_position);
  }

  /// Cancels any in-flight animation, clears loop/sequence state, and
  /// installs a fresh completion future. Returns the new future.
  TickerFuture _beginRequest() {
    _stopFutureOnly(canceled: true);
    _looping = false;
    _queue = null;
    final future = TickerFuture.pending();
    _active = future;
    return future;
  }

  /// Runs [start] now if attached, else defers it until [attach].
  void _runOrDefer(void Function() start) {
    if (_scheduler == null) {
      _pendingOnAttach = start;
    } else {
      _pendingOnAttach = null;
      start();
    }
  }

  /// When the policy is [AnimationPolicy.disabled], snaps to the
  /// current target, completes the active future, and returns true.
  bool _snapIfNoAnimation() {
    if (_policy != AnimationPolicy.disabled) return false;
    _snapToTarget();
    _completeActive();
    return true;
  }

  void _completeActive() {
    final f = _active;
    _active = null;
    f?.completeNaturally();
  }

  /// Starts the ticker if idle and resets the elapsed anchor.
  void _ensureTicking() {
    if (!_ticker!.isActive) {
      _ticker!.start();
      _lastElapsed = Duration.zero;
    }
  }

  /// Configures the engine (spring or curve) for a retarget from the
  /// current position, applying the active [AnimationPolicy.reduced]
  /// shortening. [_target] must already be set.
  void _arm({Spring? spring, Curve? curve, Duration? duration}) {
    final reduced = _policy == AnimationPolicy.reduced;
    _curveFrom = List<double>.of(_position);
    _curveStart = _lastElapsed;
    if (curve != null) {
      _spring = null;
      _curve = curve;
      var d = duration ?? const Duration(milliseconds: 250);
      if (reduced) d = Duration(microseconds: d.inMicroseconds ~/ 2);
      _curveDuration = d;
    } else {
      _curve = null;
      var s = spring ?? Spring.smooth;
      if (reduced) {
        s = Spring(
          response: Duration(microseconds: s.response.inMicroseconds ~/ 2),
        );
      }
      _spring = s;
    }
  }

  /// Configures the engine for one [AnimationStep] of a sequence. A hold
  /// is a curve to the current value over its duration (clock-driven,
  /// so it advances under FakeClock).
  void _applyStep(AnimationStep<T> step) {
    if (step._isHold) {
      _target = List<double>.of(_position);
      _arm(curve: Curves.linear, duration: step.duration);
    } else {
      _target = _type.toVector(step._target as T);
      _arm(spring: step.spring, curve: step.curve, duration: step.duration);
    }
  }

  /// Stops the ticker and cancels/loses the in-flight future, but
  /// leaves the current value where it is.
  void _stop({required bool canceled}) {
    _pendingOnAttach = null;
    if (_ticker?.isActive ?? false) _ticker!.stop();
    _stopFutureOnly(canceled: canceled);
  }

  void _stopFutureOnly({required bool canceled}) {
    final f = _active;
    _active = null;
    if (f == null) return;
    canceled ? f.cancel() : f.completeNaturally();
  }

  void _onReassemble() {
    if (_disposed) return;
    // After hot reload, settle at the current target with no in-flight
    // animation so freshly-loaded code starts from a defined state.
    _looping = false;
    _queue = null;
    _stop(canceled: true);
    _snapToTarget();
    _notify();
  }
}

/// One step in a [Animation.run] sequence: either a retarget
/// ([AnimationStep.to]) or a clock-driven wait ([AnimationStep.hold]).
class AnimationStep<T> {
  /// Retarget to [target] (spring by default, or curve+duration).
  const AnimationStep.to(T target, {this.spring, this.curve, this.duration})
    : _target = target,
      _isHold = false;

  /// Wait [duration] before the next step, holding the current value.
  const AnimationStep.hold(this.duration)
    : _target = null,
      spring = null,
      curve = null,
      _isHold = true;

  final T? _target;
  final Spring? spring;
  final Curve? curve;
  final Duration? duration;
  final bool _isHold;
}
