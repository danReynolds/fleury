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
//   2. Prefer candidates that share deeper widget-tree ancestry with
//      the current node, so pane siblings beat far-away app chrome.
//   3. Prefer a focusable descendant over a focusable viewport/shell
//      ancestor when both are eligible in the same direction.
//   4. Use weighted spatial distance: cross-axis distance is expensive,
//      but not an absolute winner over a much nearer pane.
//   5. Break ties by major-axis distance, minor-axis distance, then
//      stable traversal order.
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
/// [runApp] installs one at the app root automatically, so arrow keys move
/// focus between an app's focusable widgets out of the box — no app shell or
/// manual group required. Add explicit groups only to *scope* traversal: a
/// modal or pane that should trap focus, an embedded surface, or a
/// framework-level test that mounts a widget without going through [runApp].
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
      // Confine directional moves to this traversal group and the active
      // modal scope; without this, an arrow press in one pane can jump to
      // a visually-near control in a sibling chrome/header area.
      candidates: manager.traversalCandidates(scopeContext: context),
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

  var traversalOrder = 0;
  final ancestry = _SourceAncestry.from(excluding);
  final eligible = <_TraversalCandidate>[];
  var minElementDepth = 1 << 30;
  var maxElementDepth = -1;

  for (final node in candidates) {
    traversalOrder++;
    if (identical(node, excluding)) continue;
    if (!node.canRequestFocus || node.skipTraversal) continue;
    final rect = node.rect;
    if (rect == null) continue;

    final cx = (rect.left + rect.right) ~/ 2;
    final cy = (rect.top + rect.bottom) ~/ 2;

    final int majorDistance;
    final int minorDistance;
    switch (direction) {
      case TraversalDirection.left:
        if (cx >= fromCx) continue;
        majorDistance = _rangeGap(rect.right, rect.right, from.left, from.left);
        minorDistance = _rangeGap(from.top, from.bottom, rect.top, rect.bottom);
      case TraversalDirection.right:
        if (cx <= fromCx) continue;
        majorDistance = _rangeGap(from.right, from.right, rect.left, rect.left);
        minorDistance = _rangeGap(from.top, from.bottom, rect.top, rect.bottom);
      case TraversalDirection.up:
        if (cy >= fromCy) continue;
        majorDistance = _rangeGap(rect.bottom, rect.bottom, from.top, from.top);
        minorDistance = _rangeGap(from.left, from.right, rect.left, rect.right);
      case TraversalDirection.down:
        if (cy <= fromCy) continue;
        majorDistance = _rangeGap(from.bottom, from.bottom, rect.top, rect.top);
        minorDistance = _rangeGap(from.left, from.right, rect.left, rect.right);
    }

    final context = node.context;
    final element = context is Element ? context : null;
    final elementDepth = element?.depth;
    if (elementDepth != null) {
      if (elementDepth < minElementDepth) minElementDepth = elementDepth;
      if (elementDepth > maxElementDepth) maxElementDepth = elementDepth;
    }

    eligible.add(
      _TraversalCandidate(
        node: node,
        element: element,
        structuralPenalty: ancestry.climbDistanceToCommonAncestor(node),
        majorDistance: majorDistance,
        minorDistance: minorDistance,
        traversalOrder: traversalOrder,
      ),
    );
  }

  Set<Element>? shellAncestors;
  if (maxElementDepth > minElementDepth) {
    shellAncestors = <Element>{};
    for (final candidate in eligible) {
      Element? element = candidate.element?.elementParent;
      while (element != null) {
        shellAncestors.add(element);
        element = element.elementParent;
      }
    }
  }

  FocusNode? best;
  _TraversalScore? bestScore;
  for (final candidate in eligible) {
    final score = _TraversalScore(
      structuralPenalty: candidate.structuralPenalty,
      shellPenalty:
          candidate.element != null &&
              (shellAncestors?.contains(candidate.element) ?? false)
          ? 1
          : 0,
      spatialDistance: candidate.minorDistance * 4 + candidate.majorDistance,
      majorDistance: candidate.majorDistance,
      minorDistance: candidate.minorDistance,
      traversalOrder: candidate.traversalOrder,
    );
    if (bestScore == null || score.compareTo(bestScore) < 0) {
      bestScore = score;
      best = candidate.node;
    }
  }

  return best;
}

int _rangeGap(int aStart, int aEnd, int bStart, int bEnd) {
  if (aEnd < bStart) return bStart - aEnd;
  if (bEnd < aStart) return aStart - bEnd;
  return 0;
}

final class _TraversalScore implements Comparable<_TraversalScore> {
  const _TraversalScore({
    required this.structuralPenalty,
    required this.shellPenalty,
    required this.spatialDistance,
    required this.majorDistance,
    required this.minorDistance,
    required this.traversalOrder,
  });

  final int structuralPenalty;
  final int shellPenalty;
  final int spatialDistance;
  final int majorDistance;
  final int minorDistance;
  final int traversalOrder;

  @override
  int compareTo(_TraversalScore other) {
    var result = structuralPenalty.compareTo(other.structuralPenalty);
    if (result != 0) return result;
    result = shellPenalty.compareTo(other.shellPenalty);
    if (result != 0) return result;
    result = spatialDistance.compareTo(other.spatialDistance);
    if (result != 0) return result;
    result = majorDistance.compareTo(other.majorDistance);
    if (result != 0) return result;
    result = minorDistance.compareTo(other.minorDistance);
    if (result != 0) return result;
    return traversalOrder.compareTo(other.traversalOrder);
  }
}

final class _TraversalCandidate {
  const _TraversalCandidate({
    required this.node,
    required this.element,
    required this.structuralPenalty,
    required this.majorDistance,
    required this.minorDistance,
    required this.traversalOrder,
  });

  final FocusNode node;
  final Element? element;
  final int structuralPenalty;
  final int majorDistance;
  final int minorDistance;
  final int traversalOrder;
}

final class _SourceAncestry {
  const _SourceAncestry(this._climbDistanceByElement);

  factory _SourceAncestry.from(FocusNode node) {
    final context = node.context;
    if (context is! Element) return const _SourceAncestry(null);
    final distances = <Element, int>{};
    var distance = 0;
    Element? element = context;
    while (element != null) {
      distances[element] = distance;
      distance++;
      element = element.elementParent;
    }
    return _SourceAncestry(distances);
  }

  final Map<Element, int>? _climbDistanceByElement;

  int climbDistanceToCommonAncestor(FocusNode candidate) {
    final sourceDistances = _climbDistanceByElement;
    if (sourceDistances == null) return 0;
    final context = candidate.context;
    if (context is! Element) return 1 << 30;
    Element? element = context;
    while (element != null) {
      final distance = sourceDistances[element];
      if (distance != null) return distance;
      element = element.elementParent;
    }
    return 1 << 30;
  }
}
