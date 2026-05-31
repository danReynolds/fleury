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
  static bool enabledOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TickerMode>();
    return scope?.enabled ?? true;
  }

  @override
  bool updateShouldNotify(TickerMode old) => enabled != old.enabled;
}
