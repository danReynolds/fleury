// TickerMode: muting lever for an entire subtree of animations.
//
// `TickerMode(enabled: false, child: ...)` instructs every
// SingleTickerProviderStateMixin descendant to mute its Ticker —
// elapsed time continues to track the clock (so re-enabling lands
// at the correct value, not by replaying missed frames), but user
// callbacks don't fire while muted.
//
// Typical use cases:
//   - Hidden tab or pane: wrap its content in
//     `TickerMode(enabled: false, child: hiddenPane)` so spinners
//     etc. don't burn CPU in the background.
//   - Modal covering content behind it: wrap the background in
//     `TickerMode(enabled: false, child: appBehindModal)`.
//   - Offscreen list items: wrap each item's animation in a
//     `TickerMode` whose `enabled` follows the item's visibility.
//
// The default is `enabled: true`. A subtree with no enclosing
// TickerMode behaves as if enabled.

import '../foundation/key.dart';
import 'focus.dart';
import 'framework.dart';

/// Inherited muting lever for tickers in this subtree.
class TickerMode extends InheritedWidget {
  const TickerMode({super.key, required this.enabled, required super.child});

  /// When true, descendant tickers fire their callbacks normally.
  /// When false, descendant tickers continue to advance their
  /// internal elapsed time but skip their user callbacks. Callbacks
  /// resume the next scheduler tick after this flips back to true,
  /// at the current clock-relative elapsed value (no replay).
  final bool enabled;

  /// Returns the [enabled] value of the nearest ancestor
  /// [TickerMode], or `true` if no ancestor exists.
  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TickerMode>();
    return scope?.enabled ?? true;
  }

  /// A [TickerMode] whose [enabled] follows keyboard focus: descendant
  /// tickers run only while focus is inside [child].
  ///
  /// Sampled key state is surface-wide — `Keyboard.snapshot` reports what is
  /// physically down, not what is down *for you* — so a scene that keeps
  /// ticking while focus is elsewhere will act on keys meant for whatever
  /// took focus. A game left running under a command palette steers itself
  /// as the user types. The fix is to stop the SIMULATION, not to blind it:
  /// a paused scene neither thrusts nor drifts into an asteroid.
  ///
  /// ```dart
  /// TickerMode.whileFocused(
  ///   child: Focus(autofocus: true, child: playfield),
  /// )
  /// ```
  ///
  /// Composes with ordinary gating rather than replacing it: nested under a
  /// route's [TickerMode], a hidden OR unfocused scene is muted. Muting (not
  /// stopping) means the ticker's clock keeps advancing, so a consumer
  /// computing frame deltas should re-anchor when it resumes — see
  /// [Ticker.muted].
  static Widget whileFocused({Key? key, required Widget child}) =>
      _FocusGatedTickerMode(key: key, child: child);

  @override
  bool updateShouldNotify(TickerMode old) => enabled != old.enabled;
}

class _FocusGatedTickerMode extends StatefulWidget {
  const _FocusGatedTickerMode({super.key, required this.child});

  final Widget child;

  @override
  State<_FocusGatedTickerMode> createState() => _FocusGatedTickerModeState();
}

class _FocusGatedTickerModeState extends State<_FocusGatedTickerMode> {
  // Starts inactive and is corrected on mount by FocusDetector's initial
  // sync, so a scene that never receives focus never ticks.
  bool _focused = false;

  @override
  Widget build(BuildContext context) => FocusDetector(
    onFocusChange: (focused) {
      if (focused == _focused) return;
      setState(() => _focused = focused);
    },
    child: TickerMode(enabled: _focused, child: widget.child),
  );
}
