// SelectionEvent + SelectionResult: the sealed event vocabulary that
// the SelectionArea root and individual Selectables speak.
//
// Mirrors Flutter's selection.dart event types, recast as a Dart 3
// sealed class so handlers exhaustively cover all cases at compile
// time. The handful of cases (8 events × 5 result states) is small
// enough that exhaustiveness is a real correctness win — a future
// new event type adds a missing-case warning at every Selectable.

import 'package:meta/meta.dart';

import '../../foundation/geometry.dart';

/// One discrete action against the selection state. Dispatched by the
/// root `SelectionArea` to its registered [Selectable]s via a
/// [SelectionRegistrar].
///
/// Three flavours, expressed via the sealed hierarchy:
///
///   - [SelectionEdgeUpdateEvent] — "move the start or end edge to
///     this screen point." The bread-and-butter event for mouse drag
///     and Shift+arrow keyboard extension.
///   - [SelectionGranularEvent] — "select a unit at this point":
///     word, line, paragraph, or all. Maps to double-click,
///     triple-click, and Ctrl+A.
///   - [SelectionClearEvent] — "drop the selection completely."
///
/// Why sealed: the dispatcher's switch must cover every event type
/// exhaustively. Adding a 4th event class (e.g. a future "block
/// selection toggle") becomes a compile-time prompt at every
/// `Selectable` implementation, not a runtime "unknown event" crash.
@immutable
sealed class SelectionEvent {
  const SelectionEvent();
}

/// Move the start or end edge of the selection toward [globalPosition]
/// (screen-space cell coordinates). The receiving [Selectable]
/// computes the cell index nearest that point within its own bounds
/// and clamps as appropriate.
///
/// [isStart] distinguishes the anchor (start, set once at the
/// beginning of a drag) from the moving edge (end, advanced as the
/// user drags or holds Shift+arrow). Most mouse drags emit
/// `isStart: true` on `mouseDown` and `isStart: false` on every
/// subsequent `drag`.
final class SelectionEdgeUpdateEvent extends SelectionEvent {
  const SelectionEdgeUpdateEvent({
    required this.globalPosition,
    required this.isStart,
  });

  /// Screen-space cell position the edge is moving toward.
  final CellOffset globalPosition;

  /// True for the anchor edge (start), false for the moving edge (end).
  final bool isStart;

  @override
  String toString() =>
      'SelectionEdgeUpdate(at $globalPosition, isStart: $isStart)';
}

/// Select a granular unit (word, line, all) without explicit
/// start/end coordinates. The receiving [Selectable] interprets the
/// granularity against its own content.
final class SelectionGranularEvent extends SelectionEvent {
  const SelectionGranularEvent({
    required this.granularity,
    this.globalPosition,
  });

  /// Which unit of content to select.
  final SelectionGranularity granularity;

  /// Screen-space cell anchor point. Required for [SelectionGranularity.word]
  /// and [SelectionGranularity.line] (the unit at this point); null and ignored
  /// for [SelectionGranularity.all].
  final CellOffset? globalPosition;

  @override
  String toString() =>
      'SelectionGranular(${granularity.name}'
      '${globalPosition != null ? ', at $globalPosition' : ''})';
}

/// Clear the current selection.
final class SelectionClearEvent extends SelectionEvent {
  const SelectionClearEvent();

  @override
  String toString() => 'SelectionClear()';
}

/// Which unit of content a [SelectionGranularEvent] picks.
enum SelectionGranularity {
  /// One Unicode word (UAX #29 boundary). Triggered by double-click
  /// and `Ctrl+Shift+Arrow` extensions.
  word,

  /// One line of laid-out content. Triggered by triple-click and
  /// `Shift+Home`/`Shift+End` extensions.
  line,

  /// Everything the Selectable holds. Triggered by `Ctrl+A`.
  all,
}

/// Reply from a [Selectable] to a dispatched [SelectionEvent]. Tells
/// the parent container where the live edge ended up relative to this
/// child's bounds, which is how cross-widget selection boundaries
/// resolve.
///
/// The dispatcher walks its children in screen-reading order and
/// hands each one the same event; the returned [SelectionResult]
/// drives the cross-widget handoff:
///
///   - [previous] — "the event's target is before me." Container
///     keeps walking earlier children.
///   - [next] — "the event's target is past me." Container keeps
///     walking later children, and (for an end-edge update) considers
///     me fully selected through my last character.
///   - [end] — "the event landed inside me." This child now owns the
///     live edge; the container stops walking.
///   - [pending] — "I can't answer yet — I'm scrolling/laying out.
///     Ask me again after the next frame." The container schedules a
///     re-dispatch.
///   - [none] — "the event doesn't apply to me at all" (e.g. a
///     SelectionClear when I had no selection). Container moves on
///     without state changes.
enum SelectionResult { previous, next, end, pending, none }
