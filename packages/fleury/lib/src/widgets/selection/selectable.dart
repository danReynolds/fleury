// Selectable mixin + SelectionRegistrar + SelectionScope + Registrant.
//
// The contract a render object opts into so it can participate in
// app-wide text selection. Mirrors Flutter's `Selectable` mixin plus
// `SelectionRegistrar` interface, adapted to cell-grid geometry: no
// `Matrix4 getTransformTo()`, no `Size` in pixels, no `Rect`s — just
// `CellRect` and `CellOffset`.

import '../../foundation/change_notifier.dart';
import '../../foundation/geometry.dart';
import '../framework.dart';
import 'selection.dart';
import 'selection_event.dart';

/// A render object that participates in selection.
///
/// A `Selectable` reports its on-screen bounds via [cellBounds]
/// (captured at paint time) and responds to selection events
/// dispatched by an ancestor [SelectionRegistrar]. Its current
/// selection state is published as a [Listenable] [geometry] so the
/// owning container repaints whenever the selection touching this
/// leaf changes.
///
/// A Selectable's lifecycle:
///   1. Mount → call [SelectionRegistrar.add] (typically via
///      [SelectionRegistrant]).
///   2. Paint → record current global bounds.
///   3. Event arrives → [dispatch] mutates internal state and
///      notifies [geometry] listeners.
///   4. Container reads [geometry] and triggers a repaint, OR
///      [getSelectedContent] for copy.
///   5. Unmount → call [SelectionRegistrar.remove].
abstract interface class Selectable implements Listenable {
  /// Number of cells of selectable content this leaf holds. Used by
  /// the registrar to bound granular events ("select word at offset 5
  /// out of 30") and to validate selection ranges.
  int get contentLength;

  /// The leaf's full painted rect in screen coordinates, including
  /// any portion currently scrolled off (or otherwise clipped). The
  /// registrar uses this for reading-order sort — content that's
  /// scrolled out of view still sorts at its logical position so
  /// the joined clipboard text comes out in the right order.
  ///
  /// Returns null only before the first paint.
  CellRect? get cellBounds;

  /// The currently-visible portion of [cellBounds] — the
  /// intersection with all ancestor clip rects. Null when the
  /// Selectable is fully clipped (e.g. scrolled off-screen) OR when
  /// it hasn't painted yet. Used by visibility-aware code paths
  /// like auto-scroll edge detection; consumers that just want
  /// "where does this content belong in the document?" should use
  /// [cellBounds].
  CellRect? get visibleBounds;

  /// Live geometry — what portion of this leaf is currently
  /// selected. Implementations should `notifyListeners()` whenever
  /// this value changes.
  SelectionGeometry get geometry;

  /// Processes a [SelectionEvent], updating internal state. Returns a
  /// [SelectionResult] telling the parent container where the event's
  /// target sits relative to this leaf (used to walk to the next or
  /// previous Selectable when the live edge crosses a boundary).
  SelectionResult dispatchSelectionEvent(SelectionEvent event);

  /// Returns the currently-selected portion of this leaf's content,
  /// or null if [geometry] reports nothing selected.
  SelectedContent? getSelectedContent();

  /// Returns the absolute (start, end) range of the live selection as
  /// it sits inside this leaf's content (character offsets), or null
  /// when nothing is selected.
  ({int start, int end})? getSelectionRange();

  /// Returns the screen-space cell position of the grapheme boundary
  /// nearest [from], moved one grapheme in the given direction:
  ///
  ///   - `dCol > 0` → the boundary one grapheme to the right.
  ///   - `dCol < 0` → one grapheme to the left.
  ///   - `dRow > 0` → one row down at roughly the same column.
  ///   - `dRow < 0` → one row up at roughly the same column.
  ///
  /// Returns null when [from] isn't inside this Selectable's content
  /// OR when the move would land outside it (the caller should try
  /// the next Selectable in reading order). The cursor system uses
  /// this to advance Shift+Arrow by full graphemes — so wide
  /// characters and ZWJ sequences are crossed in one keystroke
  /// instead of leaving the cursor stranded on a continuation cell.
  CellOffset? nextGraphemeBoundary(CellOffset from, int dCol, int dRow);
}

/// Registrar interface — the API a [Selectable] uses to make itself
/// known to (and forgotten by) the ambient [SelectionArea].
///
/// Looked up via [SelectionScope.maybeOf]. Most leaves never call
/// these methods directly; they mix in [SelectionRegistrant] and
/// register/deregister gets handled by the mount/dispose lifecycle.
abstract interface class SelectionRegistrar {
  /// Registers a [Selectable]. Idempotent — re-adding the same
  /// Selectable is a no-op.
  void add(Selectable selectable);

  /// Deregisters a [Selectable]. Safe to call on a Selectable that
  /// was never added.
  void remove(Selectable selectable);
}

/// InheritedWidget that publishes the ambient [SelectionRegistrar] to
/// the subtree.
///
/// Used by Selectable widgets at mount time to find the area they
/// belong to. The registrar reference is stable for the lifetime of
/// the surrounding `SelectionArea`, so plain
/// `getInheritedWidgetOfExactType` (no `dependOn…`) is sufficient
/// when callers only need to register / deregister and don't want to
/// rebuild on registrar identity changes.
///
/// Pass `registrar: null` to mask a deeper subtree from any
/// ancestor `SelectionArea` — useful for forms or interactive panels
/// embedded inside a selectable region that shouldn't themselves
/// participate in selection.
class SelectionScope extends InheritedWidget {
  const SelectionScope({
    super.key,
    required this.registrar,
    required super.child,
  });

  /// The registrar that ought to own Selectables in this subtree, or
  /// `null` to disable selection for the subtree (Selectables there
  /// see no ambient registrar and silently no-op).
  final SelectionRegistrar? registrar;

  /// Looks up the ambient registrar without subscribing to changes.
  /// Returns null when no [SelectionScope] is in scope OR when the
  /// nearest scope's registrar is null — Selectables under either
  /// condition silently no-op their registration.
  static SelectionRegistrar? maybeOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<SelectionScope>();
    return scope?.registrar;
  }

  @override
  bool updateShouldNotify(SelectionScope old) =>
      !identical(old.registrar, registrar);
}

/// Mixin a render object can apply to handle [SelectionRegistrar]
/// add/remove around the framework lifecycle.
///
/// Subclasses still need to implement the [Selectable] contract
/// itself — this mixin only provides the bookkeeping for
/// `attach`/`detach` against the ambient registrar.
///
/// Typical use:
///
///     class RenderText extends RenderObject
///         with SelectionRegistrant
///         implements Selectable { ... }
///
/// Then in the widget that wraps the render object:
///
///     @override
///     void updateRenderObject(BuildContext context, RenderText r) {
///       r.attachToSelection(SelectionScope.maybeOf(context));
///     }
///
/// Calling [attachToSelection] is idempotent: if the registrar
/// hasn't changed, no add/remove happens.
mixin SelectionRegistrant on Object implements Selectable {
  SelectionRegistrar? _registrar;

  /// Wires this Selectable to a (possibly null) registrar — pulling
  /// it from a previous registrar if one was attached. The owning
  /// widget should call this from `updateRenderObject` so the
  /// Selectable always follows whichever `SelectionScope` is
  /// currently in context.
  void attachToSelection(SelectionRegistrar? registrar) {
    if (identical(_registrar, registrar)) return;
    _registrar?.remove(this);
    _registrar = registrar;
    _registrar?.add(this);
  }

  /// Called by the owning widget at dispose time. Cleans up the
  /// registration so the area doesn't hold a dangling reference.
  void detachFromSelection() {
    _registrar?.remove(this);
    _registrar = null;
  }
}
