// Selection / SelectionGeometry / SelectedContent: the data shapes
// that selection state flows through.
//
// Cell-coordinate analogue of Flutter's text selection. The big
// simplification over Flutter: we have integer cell positions, not
// Matrix4 transforms and pixel-precise TextLayoutResults — `start`
// and `end` are just `CellOffset`s in screen space.

import 'package:meta/meta.dart';

import '../../foundation/geometry.dart';

/// An active selection, expressed as a pair of cell positions.
///
/// **Anchor + moving edge.** Per the model Textual settled on (and
/// Flutter implements via separate start/end edge updates): [start]
/// is the immovable anchor, set when the selection begins. [end] is
/// the moving edge, advanced by mouse drag or `Shift+Arrow`. The
/// "cursor" is always [end].
///
/// **Reverse selections are legal.** Dragging right-to-left or
/// `Shift+LeftArrow` from anchor puts [end] *before* [start] in
/// screen-reading order. Consumers that need a screen-order pair
/// should call [normalized].
@immutable
final class Selection {
  const Selection({required this.start, required this.end});

  /// Anchor — set once when the selection begins.
  final CellOffset start;

  /// Moving edge / cursor — advances with each
  /// [SelectionEdgeUpdateEvent] whose `isStart` is false.
  final CellOffset end;

  /// Returns a copy whose `start` is the screen-earlier of the two
  /// points and whose `end` is the screen-later. Useful when consumers
  /// want screen-order without caring which one the user anchored.
  Selection get normalized {
    if (_before(start, end)) return this;
    return Selection(start: end, end: start);
  }

  /// Whether [start] and [end] reference the same cell — i.e. the
  /// selection is empty (a caret, not a highlight).
  bool get isCollapsed => start == end;

  @override
  bool operator ==(Object other) =>
      other is Selection && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'Selection($start → $end)';

  static bool _before(CellOffset a, CellOffset b) {
    if (a.row != b.row) return a.row < b.row;
    return a.col < b.col;
  }
}

/// A snapshot of how much of one [Selectable]'s content is currently
/// selected. Published as a `ValueListenable` so the rendering tree
/// repaints automatically when a leaf's selection changes.
@immutable
final class SelectionGeometry {
  const SelectionGeometry({
    required this.status,
    this.startEdgeOffsetInContent = -1,
    this.endEdgeOffsetInContent = -1,
  });

  /// Convenience: nothing selected.
  static const SelectionGeometry empty = SelectionGeometry(
    status: SelectionStatus.none,
  );

  /// How the live selection touches this Selectable.
  final SelectionStatus status;

  /// Where the start edge lands inside this leaf's content, as a
  /// character offset. `-1` when the start edge is not inside this
  /// leaf (i.e. selection runs through us from outside).
  final int startEdgeOffsetInContent;

  /// Where the end edge lands inside this leaf's content. Same
  /// `-1` sentinel as [startEdgeOffsetInContent].
  final int endEdgeOffsetInContent;

  /// Whether the leaf currently displays any selected glyphs.
  bool get hasContent => status != SelectionStatus.none;

  @override
  bool operator ==(Object other) =>
      other is SelectionGeometry &&
      other.status == status &&
      other.startEdgeOffsetInContent == startEdgeOffsetInContent &&
      other.endEdgeOffsetInContent == endEdgeOffsetInContent;

  @override
  int get hashCode =>
      Object.hash(status, startEdgeOffsetInContent, endEdgeOffsetInContent);

  @override
  String toString() =>
      'SelectionGeometry($status, '
      'start: $startEdgeOffsetInContent, end: $endEdgeOffsetInContent)';
}

/// How a single [Selectable] relates to the live selection on its
/// last update.
enum SelectionStatus {
  /// This leaf is not touched by the current selection.
  none,

  /// The selection enters AND exits this leaf — every glyph between
  /// the start and end offset is selected; nothing outside.
  collapsed,

  /// The leaf is fully selected. Either:
  ///   - the start edge is at our first character and the end edge
  ///     is at our last (an explicit "select me"); or
  ///   - the selection runs through us from a leaf before to a leaf
  ///     after, with no edge inside us at all.
  uncollapsed,
}

/// Selected text contributed by a single [Selectable]. The root
/// `SelectionArea` concatenates these (in reading order) to produce
/// the final user-facing selection string.
@immutable
final class SelectedContent {
  const SelectedContent({required this.plainText});

  /// The selected portion of the leaf's content as a plain string,
  /// already adjusted for selection geometry (e.g. when only the
  /// middle 4 cells of a 20-character text are selected, this is just
  /// those 4 characters).
  final String plainText;

  @override
  String toString() => 'SelectedContent(${plainText.length} chars)';
}
