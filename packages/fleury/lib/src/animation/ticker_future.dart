// TickerFuture: the result type for Animation.to / loop / run.
//
// Implements Future<void> directly so the common case reads
// naturally:
//
//   await animation.to(1.0);
//
// Adds an `orCancel` future that completes normally on natural
// animation completion AND rejects with TickerCanceled when the
// animation is cancelled mid-flight (a new retarget supersedes the
// current one, animation.stop(), or the animation is disposed).
//
// Two completers under the hood:
//
//   _primary:   completes (with no value) on EITHER natural end
//               OR cancel. Drives `await future`.
//   _secondary: completes normally on natural end, completes with
//               TickerCanceled on cancel. Drives
//               `await future.orCancel`. Lazily created on first
//               access of `orCancel`.

import 'dart:async';

/// Thrown by [TickerFuture.orCancel] when the animation it
/// represents is cancelled before reaching its natural end.
class TickerCanceled implements Exception {
  const TickerCanceled();

  @override
  String toString() => 'TickerCanceled';
}

/// The future returned by `Animation.to` / `loop` / `run`.
///
/// `await future` completes when the animation ends — regardless
/// of whether it ended naturally or was cancelled. To distinguish,
/// `await future.orCancel`: this completes normally on natural
/// end, throws [TickerCanceled] on cancel.
class TickerFuture implements Future<void> {
  /// Creates a not-yet-resolved future. Resolves via either
  /// [completeNaturally] or [cancel]. Apps don't construct
  /// [TickerFuture] directly — they receive one from `Animation.to` /
  /// `loop` / `run`.
  TickerFuture.pending() : _primary = Completer<void>();

  /// Creates an already-complete future. Used when a animation is asked
  /// to animate to its current value (zero distance, instant
  /// completion).
  factory TickerFuture.complete() {
    final f = TickerFuture.pending();
    f._completed = true;
    f._primary.complete();
    return f;
  }

  final Completer<void> _primary;
  Completer<void>? _secondary;

  /// null until resolution; true on natural complete; false on
  /// cancel.
  bool? _completed;

  /// A future that completes normally on natural animation end,
  /// and rejects with [TickerCanceled] on cancel. Accessing this
  /// is the opt-in path to seeing cancellations as errors.
  Future<void> get orCancel {
    final existing = _secondary;
    if (existing != null) return existing.future;
    final s = Completer<void>();
    _secondary = s;
    // If completion already happened before orCancel was accessed,
    // resolve synchronously now.
    final state = _completed;
    if (state == true) {
      s.complete();
    } else if (state == false) {
      s.completeError(const TickerCanceled());
    }
    return s.future;
  }

  /// Called by [Animation] on natural completion. Both
  /// the primary future and `orCancel` (if accessed) complete
  /// normally.
  void completeNaturally() {
    if (_completed != null) return;
    _completed = true;
    _primary.complete();
    _secondary?.complete();
  }

  /// Called by [Animation] on cancellation. The primary
  /// future completes normally (so `await future` doesn't throw);
  /// `orCancel` rejects with [TickerCanceled].
  void cancel() {
    if (_completed != null) return;
    _completed = false;
    _primary.complete();
    _secondary?.completeError(const TickerCanceled());
  }

  // ---------------------------------------------------------------
  // Future<void> forwarding
  // ---------------------------------------------------------------

  @override
  Stream<void> asStream() => _primary.future.asStream();

  @override
  Future<void> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) => _primary.future.catchError(onError, test: test);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(void value) onValue, {
    Function? onError,
  }) => _primary.future.then<R>(onValue, onError: onError);

  @override
  Future<void> timeout(
    Duration timeLimit, {
    FutureOr<void> Function()? onTimeout,
  }) => _primary.future.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<void> whenComplete(FutureOr<void> Function() action) =>
      _primary.future.whenComplete(action);
}
