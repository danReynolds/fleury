// FocusTraversalGroup: arrow-driven directional focus traversal.
//
// Wraps a subtree. When an arrow key bubbles out of the focused
// widget (because it didn't consume it — e.g., a vertical ListView
// returns `ignored` for left/right, or a ListView with
// `EdgeBehavior.bubble` ignores up at the first item), this group
// picks the nearest focusable widget in that direction and gives it
// focus. Each [FocusNode]'s painted rect is recorded by the
// framework (see `_RenderFocusBounds` in `focus.dart`), so the
// algorithm has integer cell coordinates to work with — no
// floating-point math, no spatial estimates.
//
// What "nearest in direction" means here:
//
//   1. Filter to focusable, attached, non-skip-traversal candidates
//      whose center lies strictly past the current node's center in
//      the pressed direction. Ignore the currently-focused node.
//   2. Score each candidate by `perpendicular * 4 + parallel`:
//      perpendicular distance (axis-orthogonal offset) dominates so
//      the user moves toward what they're "looking at," with
//      parallel distance breaking ties.
//   3. Pick the lowest score.
//
// If no candidate fits, the key is returned ignored so an ancestor
// can still react (or it drops on the floor).
//
// Tab / Shift+Tab cycle focus in reading order (top-to-bottom, then
// left-to-right) via FocusManager.focusNext / focusPrevious — a separate
// ordering policy from the spatial arrow traversal, bundled here so one
// widget gives you full keyboard traversal.
//
// What this widget is NOT:
//
//   - It does not consume arrow / Tab chords when the focused widget
//     already handled them (e.g., up/down inside a ListView moves the
//     selection, and a TextInput that wants Tab for completion consumes
//     it first — bindings here sit at the top of the chain and only fire
//     when nothing deeper did).

import '../foundation/geometry.dart';
import 'focus.dart';
import 'framework.dart';
import 'key_bindings.dart';

/// A direction for arrow-key focus traversal.
enum TraversalDirection { left, right, up, down }

/// Catches arrow chords that bubble out of the focused widget and
/// moves focus to the spatially nearest focusable in that direction.
///
/// Place one near the root of your app — it wraps a `KeyBindings`
/// internally, so the four arrow bindings are visible to the input
/// dispatcher and consume chords whenever a target exists.
class FocusTraversalGroup extends StatelessWidget {
  const FocusTraversalGroup({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Each binding runs its action and calls `event.bubble()` when
    // the action didn't claim the keystroke — that lets an outer
    // traversal group (or any ancestor) have a chance at it.
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyChord.left,
          onEvent: (event) {
            if (_navigate(context, TraversalDirection.left) ==
                KeyEventResult.ignored) {
              event.bubble();
            }
          },
          hideFromHintBar: true,
        ),
        KeyBinding(
          KeyChord.right,
          onEvent: (event) {
            if (_navigate(context, TraversalDirection.right) ==
                KeyEventResult.ignored) {
              event.bubble();
            }
          },
          hideFromHintBar: true,
        ),
        KeyBinding(
          KeyChord.up,
          onEvent: (event) {
            if (_navigate(context, TraversalDirection.up) ==
                KeyEventResult.ignored) {
              event.bubble();
            }
          },
          hideFromHintBar: true,
        ),
        KeyBinding(
          KeyChord.down,
          onEvent: (event) {
            if (_navigate(context, TraversalDirection.down) ==
                KeyEventResult.ignored) {
              event.bubble();
            }
          },
          hideFromHintBar: true,
        ),
        KeyBinding(
          KeyChord.tab,
          onEvent: (event) {
            if (!Focus.of(context).focusNext()) event.bubble();
          },
          hideFromHintBar: true,
        ),
        KeyBinding(
          KeyChord.shiftTab,
          onEvent: (event) {
            if (!Focus.of(context).focusPrevious()) event.bubble();
          },
          hideFromHintBar: true,
        ),
      ],
      child: child,
    );
  }

  KeyEventResult _navigate(BuildContext context, TraversalDirection direction) {
    final manager = Focus.of(context);
    final current = manager.focusedNode;
    if (current == null) return KeyEventResult.ignored;
    final currentRect = current.rect;
    if (currentRect == null) return KeyEventResult.ignored;

    final target = nearestFocusableInDirection(
      from: currentRect,
      // Confine directional moves to the active modal scope; without
      // this, an arrow press inside a modal could land on a focusable
      // spatially adjacent to but outside the dialog.
      candidates: manager.traversalCandidates(),
      excluding: current,
      direction: direction,
    );
    if (target == null) return KeyEventResult.ignored;
    target.requestFocus();
    return KeyEventResult.handled;
  }
}

/// Picks the focusable node nearest to [from] in the given
/// [direction]. Visible for testing; app code should rely on
/// [FocusTraversalGroup].
///
/// Candidates that are not focusable, are flagged `skipTraversal`,
/// have no recorded `rect`, are identical to [excluding], or lie
/// behind [from] in the pressed direction are filtered out.
FocusNode? nearestFocusableInDirection({
  required CellRect from,
  required Iterable<FocusNode> candidates,
  required FocusNode excluding,
  required TraversalDirection direction,
}) {
  final fromCx = (from.left + from.right) ~/ 2;
  final fromCy = (from.top + from.bottom) ~/ 2;

  FocusNode? best;
  int? bestScore;

  for (final node in candidates) {
    if (identical(node, excluding)) continue;
    if (!node.canRequestFocus || node.skipTraversal) continue;
    final rect = node.rect;
    if (rect == null) continue;

    final cx = (rect.left + rect.right) ~/ 2;
    final cy = (rect.top + rect.bottom) ~/ 2;

    final int parallel;
    final int perpendicular;
    switch (direction) {
      case TraversalDirection.left:
        if (cx >= fromCx) continue;
        parallel = fromCx - cx;
        perpendicular = (cy - fromCy).abs();
      case TraversalDirection.right:
        if (cx <= fromCx) continue;
        parallel = cx - fromCx;
        perpendicular = (cy - fromCy).abs();
      case TraversalDirection.up:
        if (cy >= fromCy) continue;
        parallel = fromCy - cy;
        perpendicular = (cx - fromCx).abs();
      case TraversalDirection.down:
        if (cy <= fromCy) continue;
        parallel = cy - fromCy;
        perpendicular = (cx - fromCx).abs();
    }

    // Heavy weight on perpendicular distance: moving "left" should
    // prefer the widget directly to the left over one that's left-and-
    // far-down, even if the latter has a smaller raw distance.
    final score = perpendicular * 4 + parallel;
    if (bestScore == null || score < bestScore) {
      bestScore = score;
      best = node;
    }
  }

  return best;
}
