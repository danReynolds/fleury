// Ticker: lifecycle wrapper around a TickerScheduler callback.
//
// Holds a start-time anchor (captured from the scheduler's clock on
// each [start]) and a user-supplied callback. On each scheduler
// tick, the Ticker computes `elapsed = clock.now - startTime` and
// invokes the callback. Stopping the Ticker pauses callbacks; the
// start anchor resets on the next [start] so elapsed-time math
// resumes from zero.
//
// Created via [TickerProvider.createTicker]. Apps typically reach
// the provider via `SingleTickerProviderStateMixin` on a State (see
// lib/src/widgets/tui_binding.dart).
//
// TickerMode + AnimationPolicy support arrives in Phase 2; this
// file is the Phase 1 minimum.

import 'animation_policy.dart';
import 'ticker_scheduler.dart';

/// Signature for the per-tick callback supplied to a [Ticker].
/// Receives the elapsed time since the ticker most recently started.
typedef TickerCallback = void Function(Duration elapsed);

/// A scheduler-driven callback bound to a single object's lifecycle.
/// Apps don't construct [Ticker]s directly — they go through a
/// [TickerProvider] (typically via `SingleTickerProviderStateMixin`
/// on a `State`).
class Ticker {
  /// Creates a Ticker that invokes the supplied callback each time
  /// [scheduler] fires while this ticker is active. The Ticker is
  /// inactive until [start] is called.
  Ticker(this._onTick, {required TickerScheduler scheduler})
    : _scheduler = scheduler;

  final TickerCallback _onTick;
  final TickerScheduler _scheduler;

  /// The scheduler this ticker is bound to. Exposed so consumers
  /// (notably [Animation]) can register lifecycle hooks
  /// — e.g. reassemble callbacks — without having to be passed the
  /// scheduler separately.
  TickerScheduler get scheduler => _scheduler;

  /// Cached tear-off of [_handleSchedulerTick]. Cached because the
  /// scheduler uses an identity-based set; new tear-offs taken at
  /// `start()` and `stop()` may compare `==` but not `identical`,
  /// which would prevent unregistration.
  late final SchedulerTickCallback _schedulerCallback = _handleSchedulerTick;

  bool _active = false;
  bool _disposed = false;
  bool _muted = false;
  Duration? _startTime;
  Duration _lastElapsed = Duration.zero;

  /// Whether this Ticker is currently receiving scheduler callbacks.
  bool get isActive => _active;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// When true, the scheduler still calls this Ticker on every
  /// frame (so `lastElapsed` continues to advance), but the user
  /// callback is NOT invoked. Re-clearing `muted` resumes
  /// callbacks at the current clock-relative elapsed value — there
  /// is no replay of missed frames.
  ///
  /// Used by `TickerMode` to suspend animation in hidden subtrees
  /// (inactive tabs, modals covering content, offscreen list
  /// items), and by `AnimationPolicy.disabled` to globally suppress
  /// animation callbacks while preserving timing for any controller
  /// that snaps to its end state.
  bool get muted => _muted;
  set muted(bool value) {
    if (_disposed) {
      throw StateError(
        'Ticker.muted set after dispose. Tickers cannot be reused once '
        'disposed; create a new one via TickerProvider.createTicker.',
      );
    }
    if (_muted == value) return;
    _muted = value;
  }

  /// Most recent elapsed time recorded on a scheduler tick, or
  /// `Duration.zero` before the first tick. Updated regardless of
  /// [muted], so re-enabling resumes at the correct value rather
  /// than replaying frames that fired while muted.
  Duration get lastElapsed => _lastElapsed;

  /// Starts this Ticker. Subsequent scheduler ticks will invoke
  /// the callback with the elapsed time since this call. No-op when
  /// already active.
  void start() {
    _assertNotDisposed('start');
    if (_active) return;
    _active = true;
    _startTime = _scheduler.clock.now;
    _lastElapsed = Duration.zero;
    _scheduler.register(_schedulerCallback);
  }

  /// Stops this Ticker. Pauses callbacks without disposing — the
  /// Ticker can be restarted via [start]. The start-time anchor is
  /// reset on the next [start], so elapsed-time math resumes from
  /// zero.
  void stop() {
    _assertNotDisposed('stop');
    if (!_active) return;
    _active = false;
    _startTime = null;
    _scheduler.unregister(_schedulerCallback);
  }

  /// Releases this Ticker's resources. Stops the ticker if active,
  /// unregisters from the scheduler, and marks the Ticker as
  /// disposed. Further calls to [start] / [stop] throw.
  void dispose() {
    if (_disposed) return;
    if (_active) {
      _scheduler.unregister(_schedulerCallback);
    }
    _disposed = true;
    _active = false;
    _startTime = null;
  }

  void _handleSchedulerTick(Duration clockNow) {
    if (!_active) return; // defensive; shouldn't happen
    final start = _startTime!;
    final elapsed = clockNow - start;
    _lastElapsed = elapsed;
    // Muted tickers update _lastElapsed but skip the user callback.
    // This preserves elapsed-time math so re-enabling lands at the
    // current clock-relative value (no replay of missed frames).
    if (_muted) return;
    _onTick(elapsed);
  }

  void _assertNotDisposed(String operation) {
    if (_disposed) {
      throw StateError(
        'Ticker.$operation() called after dispose. Tickers cannot '
        'be reused once disposed; create a new one via '
        'TickerProvider.createTicker.',
      );
    }
  }
}

/// Source of [Ticker]s. Lifecycle owners (typically `State` classes
/// via mixins, but also `TuiBinding` directly) implement this so
/// downstream animation primitives can request a Ticker without
/// caring where it comes from.
///
/// Also exposes the current [AnimationPolicy] so consumers
/// (notably `Animation`) can switch to synchronous snap
/// behavior when the policy is [AnimationPolicy.disabled] without
/// needing direct access to the binding.
abstract interface class TickerProvider {
  /// Creates a new [Ticker] that invokes [onTick] each scheduler
  /// frame while active.
  Ticker createTicker(TickerCallback onTick);

  /// The currently-effective animation policy as seen by this
  /// provider. Used by controllers to decide whether to run an
  /// animation normally, shorten it, or snap to its end state
  /// synchronously.
  AnimationPolicy get animationPolicy;
}
