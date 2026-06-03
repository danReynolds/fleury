// TuiBinding: the per-runtime home for cross-cutting framework
// services that need to be reachable from any BuildContext.
//
// Holds the TickerScheduler today; will hold theme, navigation,
// gestures, app-lifecycle when those land. Designed as a small
// holder of references rather than a god object: each service is
// its own type, tested independently, and accessed via a property
// on the binding rather than via inheritance into the binding type.
//
// Modelled on Flutter's WidgetsBinding but per-runtime rather than
// process-global. runTui installs one binding per invocation;
// tests construct one explicitly.

import '../animation/animation_policy.dart';
import '../animation/ticker.dart';
import '../animation/ticker_scheduler.dart';
import 'framework.dart';
import 'navigator.dart' show NavigatorState;
import 'ticker_mode.dart';

/// Per-runtime registry of cross-cutting framework services.
/// Reachable from any descendant context via [TuiBinding.of].
class TuiBinding implements TickerProvider {
  /// Creates a binding. When [tickerScheduler] is null a default
  /// [TickerScheduler] is created with the [SystemClock]. Tests
  /// almost always pass an explicit [FakeTickerScheduler] backed by
  /// a [FakeClock].
  TuiBinding({
    TickerScheduler? tickerScheduler,
    AnimationPolicy animationPolicy = AnimationPolicy.enabled,
  }) : tickerScheduler = tickerScheduler ?? TickerScheduler(),
       _animationPolicy = animationPolicy {
    // Bridge the scheduler's "callback enqueued" signal up to the
    // runtime's `scheduleFrame`. Without this, a post-frame callback
    // added from an idle Timer.run (no setState, no event) would queue
    // forever — nothing would schedule the next frame.
    this.tickerScheduler.onPostFrameCallbackRegistered = () =>
        onPostFrameCallback?.call();
  }

  /// Hook the runtime installs to wire post-frame callback registration
  /// into frame scheduling. Null in tests by default — `FleuryTester.pump`
  /// drains synchronously after each pump, so no scheduling is needed.
  void Function()? onPostFrameCallback;

  /// The animation scheduler for this runtime. All [Ticker]s
  /// created via this binding (or via any
  /// `SingleTickerProviderStateMixin` in this runtime's tree)
  /// register with this scheduler.
  final TickerScheduler tickerScheduler;
  bool _disposed = false;

  /// The application's root navigator — the top-level [NavigatorState]
  /// with no enclosing navigator. A root-level `Navigator` registers
  /// itself here when it mounts and clears it on dispose. Lets
  /// non-widget code (a socket handler, a timer) drive top-level
  /// navigation without threading a [BuildContext]. Null until a
  /// root-level navigator mounts.
  NavigatorState? rootNavigator;

  /// Backing field for the [TickerProvider.animationPolicy]
  /// override below. Set at construction; runtime mutation lands
  /// later if a real use case appears (changing this mid-run would
  /// need to notify dependents).
  final AnimationPolicy _animationPolicy;

  /// Returns the [TuiBinding] enclosing [context]. Throws if no
  /// binding is installed — almost always means `runTui` wasn't
  /// used or the call site is outside the app's root.
  static TuiBinding of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TuiBindingScope>();
    if (scope == null) {
      throw StateError(
        'No TuiBinding above this BuildContext. runTui() installs '
        'one automatically; if you are constructing a tree manually '
        '(e.g. in a test), wrap it in TuiBindingScope(binding: ...).',
      );
    }
    return scope.binding;
  }

  /// Variant of [of] that returns null instead of throwing.
  static TuiBinding? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<TuiBindingScope>()
        ?.binding;
  }

  /// Creates a [Ticker] registered against this binding's
  /// scheduler. Implements [TickerProvider] for non-widget contexts
  /// that hold a binding reference directly.
  ///
  /// State classes inside a widget tree should prefer
  /// [SingleTickerProviderStateMixin], which manages disposal
  /// automatically.
  @override
  Ticker createTicker(TickerCallback onTick) {
    _checkNotDisposed();
    return Ticker(onTick, scheduler: tickerScheduler);
  }

  /// Queues [callback] to fire once after the next frame's bytes have
  /// been emitted. Use from `initState` (or anywhere) when a value is
  /// only available after layout — e.g. reading a render object's
  /// painted size with [BuildContext.findRenderObject].
  ///
  /// Flutter divergence: callbacks registered DURING a drain queue for
  /// the FOLLOWING frame, never re-entrantly within the same drain
  /// (Flutter runs them in the current frame). Exceptions in one
  /// callback do not abort the rest of the drain.
  void addPostFrameCallback(FrameCallback callback) {
    _checkNotDisposed();
    tickerScheduler.addPostFrameCallback(callback);
  }

  /// Drains the post-frame callback queue. Called by the runtime
  /// (native + web) after `renderer.renderDiff` and by
  /// [FleuryTester.pump] after the build flush. Idempotent — a no-op
  /// when no callbacks are queued.
  ///
  /// Driven by `TuiBinding` consumers (`run_tui`, `run_tui_web`,
  /// `FleuryTester.pump`); app code should use [addPostFrameCallback].
  void flushPostFrameCallbacks(Duration timeStamp) {
    if (_disposed) return;
    tickerScheduler.flushPostFrameCallbacks(timeStamp);
  }

  /// The currently-effective animation policy. Set at binding
  /// construction; runtime mutation lands later if a real use
  /// case appears.
  @override
  AnimationPolicy get animationPolicy => _animationPolicy;

  /// Releases the binding's resources. Idempotent. Tickers
  /// registered against the scheduler should be disposed first.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    tickerScheduler.dispose();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('TuiBinding has been disposed.');
    }
  }
}

/// Inherited widget that makes a [TuiBinding] reachable to its
/// descendants via [TuiBinding.of].
class TuiBindingScope extends InheritedWidget {
  const TuiBindingScope({
    super.key,
    required this.binding,
    required super.child,
  });

  final TuiBinding binding;

  @override
  bool updateShouldNotify(TuiBindingScope old) =>
      !identical(binding, old.binding);
}

/// `State` mixin that creates and owns one raw [Ticker], scoped to
/// the State's lifecycle and auto-muted per [TickerMode] +
/// [AnimationPolicy]. The Ticker is disposed automatically when the
/// State disposes.
///
/// This is a low-level escape hatch for custom per-frame logic.
/// Most animation needs are better served by `Animation` (continuous
/// values) or `FrameBuilder` (discrete frame stepping), neither of
/// which requires this mixin.
///
/// Asserts that only one Ticker is created per State instance. A
/// future `TickerProviderStateMixin` will lift this restriction.
///
/// ```dart
/// class _MyWidgetState extends State<MyWidget>
///     with SingleTickerProviderStateMixin {
///   late final Ticker _ticker = createTicker((elapsed) {
///     // called each frame with the time since the ticker started
///     setState(() { /* read elapsed */ });
///   })..start();
///
///   @override
///   void dispose() {
///     _ticker.dispose();
///     super.dispose();
///   }
/// }
/// ```
mixin SingleTickerProviderStateMixin<T extends StatefulWidget> on State<T>
    implements TickerProvider {
  Ticker? _ticker;

  @override
  Ticker createTicker(TickerCallback onTick) {
    assert(
      _ticker == null,
      'SingleTickerProviderStateMixin permits only one Ticker. '
      'When a widget needs multiple, switch to '
      'TickerProviderStateMixin (deferred to a future slice).',
    );
    final binding = TuiBinding.of(context);
    _ticker = Ticker(onTick, scheduler: binding.tickerScheduler);
    // Initialize mute state from the current TickerMode +
    // AnimationPolicy. didChangeDependencies will keep it in sync
    // afterwards.
    _ticker!.muted = _resolveMuted();
    return _ticker!;
  }

  bool _resolveMuted() {
    final modeEnabled = TickerMode.enabledOf(context);
    final binding = TuiBinding.of(context);
    final policyAllows = binding.animationPolicy != AnimationPolicy.disabled;
    return !(modeEnabled && policyAllows);
  }

  /// The animation policy of the enclosing [TuiBinding]. Read by
  /// `Animation` to decide whether to run an animation
  /// normally or snap to its end synchronously.
  @override
  AnimationPolicy get animationPolicy => TuiBinding.of(context).animationPolicy;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ticker = _ticker;
    if (ticker == null) return;
    ticker.muted = _resolveMuted();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}
