// SelectionArea: root of the text-selection subtree.
//
// One per app (or one per region that should have its own selection
// context — like a dialog and its background coexisting). Owns the
// SelectionContainerDelegate, publishes it via SelectionScope to the
// subtree, translates mouse-drag gestures into SelectionEvents.

import 'dart:async' show Timer, unawaited;

import '../../foundation/geometry.dart';
import '../../foundation/key.dart';
import '../clipboard_scope.dart';
import '../../input/events.dart' show KeyModifier;
import '../framework.dart';
import '../key_bindings.dart';
import '../pointer.dart';
import '../scroll_view.dart' show ScrollController;
import '../tui_binding.dart';
import 'selectable.dart';
import 'selection.dart';
import 'selection_container_delegate.dart';
import 'selection_event.dart';

/// Signature for [SelectionArea.onSelectionChanged] — fires whenever
/// the visible selection updates, with the currently-selected text
/// (or null when nothing is selected).
typedef SelectionChangedCallback = void Function(SelectedContent? content);

/// Enables app-wide text selection in its subtree.
///
/// Wraps a subtree in:
///   1. A [SelectionScope] that publishes a
///      [SelectionContainerDelegate], so descendant render objects
///      (e.g. [RenderText]) can register themselves as [Selectable].
///   2. A [GestureDetector] that turns mouse drag into
///      [SelectionEdgeUpdateEvent]s.
///   3. A [KeyBindings] block providing Ctrl+A (select all), Ctrl+C
///      (copy via the ambient [ClipboardScope]), and Esc (clear). Bindings
///      bubble when there's nothing to act on, so ancestors still
///      see the event.
///
/// **Mouse drag.** Press, drag, release. Every [Text] under the area
/// highlights its share of the selection automatically; the full
/// selected text crosses widget boundaries with newlines inserted at
/// row transitions.
///
/// **Keyboard.** Ctrl+A selects everything below the area; Ctrl+C
/// pushes the selection through the ambient clipboard's `write` (which
/// tries platform tools, OSC 52, and an in-process register in that
/// order); Esc clears.
///
/// **Auto-copy.** Set `copyOnRelease: true` to fire a clipboard
/// write on every mouse-release that completes a non-empty drag —
/// matches the "select to copy" idiom of native terminals.
///
/// ```dart
/// SelectionArea(
///   copyOnRelease: true,
///   onSelectionChanged: (sel) => statusBar.text = sel?.plainText ?? '',
///   child: Column(children: [
///     Text('First paragraph.'),
///     Text('Second paragraph.'),
///   ]),
/// )
/// ```
///
/// **Multi-click.** Double-click selects the word at the click
/// position (alphanumerics + Unicode letters/digits/underscore, with
/// the punctuation-or-whitespace at the click position falling back
/// to a single character). Triple-click selects the entire laid-out
/// line at the click point.
///
/// **Shift+Arrow.** Extends the moving edge of an existing selection
/// by one grapheme (left/right) or one row (up/down). Wide
/// characters (CJK, emoji, ZWJ sequences) are crossed in one step,
/// and vertical motion hops between Selectables so Shift+Down can
/// cross from one Text into another. When no selection is active
/// the Shift+Arrow event bubbles so a different consumer (focus
/// traversal, scroll) can claim it.
///
/// **Shift+Home / Shift+End.** Extends the moving edge to the start
/// or end of the cursor's current row (the Selectable it sits in),
/// keeping the anchor — so Shift+End selects through the last
/// character of the line. Like Shift+Arrow, this bubbles when no
/// selection is active.
///
/// **Shift+Click.** When a selection is active, holding Shift while
/// clicking moves the cursor to the click point without disturbing
/// the anchor — extends the selection to the click. Shift+Click
/// also breaks the double/triple-click streak so a Shift+Click
/// after a double-click starts a fresh single selection from the
/// anchor. With no active selection, Shift+Click falls through to
/// the normal "fresh anchor" path.
///
/// **Opt-out.** For a subtree that should NOT participate in any
/// ancestor `SelectionArea`'s selection, wrap it in
/// [SelectionArea.disabled]. For an individual widget, set
/// `allowSelect: false` — supported on `Text` and `RichText`.
///
/// **Selectable widgets.** `Text` and `RichText` are selectable today.
/// A mixed subtree (plain Text next to styled RichText next to more
/// plain Text) selects across all of them — the clipboard copy is
/// the plain text with `\n` between rows, never ANSI escape codes.
///
/// **Shift-bypass for native selection.** On terminals that support
/// it (xterm, GNOME Terminal/VTE, Konsole, Kitty, WezTerm, Ghostty,
/// Windows Terminal), holding Shift while clicking bypasses the
/// app's mouse reporting and uses the terminal's own native
/// selection. This requires no code on our side — the terminal
/// intercepts the event before it ever reaches the app. iTerm2 uses
/// Option instead. Alacritty historically didn't support this; check
/// per-terminal docs.
///
/// **macOS Terminal.app limitation.** Apple's Terminal.app does not
/// implement OSC 52, so payloads from the OSC 52 fallback path are
/// silently dropped there. The platform-tool path (pbcopy) is used
/// when not over SSH, but cross-machine clipboard from SSH on
/// Terminal.app does not work. Recommend iTerm2, Ghostty, or Kitty
/// for that platform.
class SelectionArea extends StatefulWidget {
  const SelectionArea({
    super.key,
    this.onSelectionChanged,
    this.copyOnRelease = false,
    this.scrollController,
    this.autoScrollEdgeRows = 1,
    this.autoScrollInterval = const Duration(milliseconds: 50),
    required this.child,
  });

  /// Wraps a subtree that should NOT participate in any ancestor
  /// [SelectionArea]'s selection — Selectables here see no ambient
  /// registrar and silently no-op. Useful for forms, modal dialogs,
  /// or interactive panels embedded inside a selectable region.
  ///
  /// ```dart
  /// SelectionArea(
  ///   child: Column(children: [
  ///     Text('Selectable content here'),
  ///     SelectionArea.disabled(
  ///       child: TextInput(...), // Not part of any selection
  ///     ),
  ///   ]),
  /// )
  /// ```
  static Widget disabled({Key? key, required Widget child}) =>
      _DisabledSelection(key: key, child: child);

  /// Called whenever the active selection changes. Receives a
  /// [SelectedContent] (whose `plainText` is the concatenated
  /// selection across all Selectables in reading order), or null
  /// when nothing is selected.
  final SelectionChangedCallback? onSelectionChanged;

  /// When true, the active selection is pushed to the ambient [ClipboardScope]
  /// on every mouse-release that completes a non-empty drag. Off by
  /// default — most apps want explicit Ctrl+C wiring or a different
  /// trigger.
  final bool copyOnRelease;

  /// Optional scroll controller for the scrollable below us. When set,
  /// dragging near the top/bottom edge of the selectable region
  /// auto-scrolls the viewport and extends the selection into the
  /// newly-visible content — the standard "drag-to-extend past the
  /// edge" interaction of every native text editor.
  ///
  /// When null, auto-scroll is disabled and dragging past the visible
  /// edge stops at the edge.
  final ScrollController? scrollController;

  /// How many rows from the top/bottom edge of the selectable region
  /// trigger auto-scroll. Defaults to 1 — auto-scroll engages the
  /// instant the cursor enters the first or last visible row.
  final int autoScrollEdgeRows;

  /// Interval between auto-scroll ticks while the cursor is in the
  /// edge zone. Defaults to 50ms (~20 rows per second). Used only
  /// when [scrollController] is set.
  final Duration autoScrollInterval;

  /// The subtree in which selection is enabled.
  final Widget child;

  @override
  State<SelectionArea> createState() => _SelectionAreaState();
}

class _SelectionAreaState extends State<SelectionArea> {
  late final SelectionContainerDelegate _delegate;
  String? _lastReportedText;

  // Auto-scroll state. Populated while a drag is in flight near a
  // viewport edge; cleared on drag end or when the cursor leaves
  // the edge zone. Holds the last drag position so each tick can
  // re-dispatch it as the viewport scrolls underneath.
  Timer? _autoScrollTimer;
  CellOffset? _autoScrollCursor;
  int _autoScrollDirection = 0; // -1 up, +1 down, 0 inactive
  // Guards the post-frame dispatch: when the timer fires multiple
  // times before a pump, only the FIRST tick queues a callback.
  // Avoids 10+ redundant dispatches per pump cycle.
  bool _autoScrollDispatchQueued = false;
  // Generation counter, bumped on every _stopAutoScroll. A queued
  // post-frame callback captures the generation at queue time and
  // checks it before dispatching — if the drag has ended (or the
  // cursor left the zone) between queue and fire, the captured
  // generation no longer matches and the dispatch is skipped. This
  // prevents a late-arriving callback from extending the selection
  // past what `copyOnRelease` already captured.
  int _autoScrollGeneration = 0;

  @override
  void initState() {
    super.initState();
    _delegate = SelectionContainerDelegate();
    _delegate.addListener(_handleSelectionChanged);
  }

  @override
  void dispose() {
    _cancelAutoScroll();
    _delegate.removeListener(_handleSelectionChanged);
    _delegate.dispose();
    super.dispose();
  }

  void _handleSelectionChanged() {
    final text = _delegate.getSelectedText();
    if (text == _lastReportedText) return;
    _lastReportedText = text;
    widget.onSelectionChanged?.call(
      text.isEmpty ? null : SelectedContent(plainText: text),
    );
  }

  // Multi-click tracking for word (2 clicks) / line (3 clicks) selection.
  static const _multiClickWindow = Duration(milliseconds: 500);
  static const _multiClickRadius = 2; // cells of slop allowed
  DateTime? _lastClickAt;
  CellOffset? _lastClickPos;
  int _clickCount = 0;

  void _onTapDown(int col, int row, Set<KeyModifier> modifiers) {
    final pos = CellOffset(col, row);

    // Shift+Click extends the existing selection to the click point
    // without disturbing the anchor — standard text-editor convention.
    // If no selection is active, fall through to the normal "fresh
    // anchor" path so Shift+Click can also start a selection.
    if (modifiers.contains(KeyModifier.shift) && _delegate.cursor != null) {
      // Reset the multi-click streak — a shift-click breaks the
      // double/triple-click sequence (matches Chrome / VS Code).
      _lastClickAt = null;
      _lastClickPos = null;
      _clickCount = 0;
      _delegate.moveCursorTo(pos);
      return;
    }

    final now = DateTime.now();
    final lastAt = _lastClickAt;
    final lastPos = _lastClickPos;
    final isSameSeries =
        lastAt != null &&
        lastPos != null &&
        now.difference(lastAt) <= _multiClickWindow &&
        (pos.col - lastPos.col).abs() <= _multiClickRadius &&
        pos.row == lastPos.row;
    _clickCount = isSameSeries ? _clickCount + 1 : 1;
    _lastClickAt = now;
    _lastClickPos = pos;

    switch (_clickCount) {
      case 2:
        // Double-click: select the word at this point.
        _delegate.dispatchSelectionEvent(
          SelectionGranularEvent(
            granularity: SelectionGranularity.word,
            globalPosition: pos,
          ),
        );
      case 3:
        // Triple-click: select the line at this point.
        _delegate.dispatchSelectionEvent(
          SelectionGranularEvent(
            granularity: SelectionGranularity.line,
            globalPosition: pos,
          ),
        );
      case _:
        // Single click (or 4+): clear and place a fresh anchor at the
        // press point. Both edges land here so a no-drag release
        // looks like a "click that cleared selection".
        _delegate.clear();
        _delegate.dispatchSelectionEvent(
          SelectionEdgeUpdateEvent(globalPosition: pos, isStart: true),
        );
        _delegate.dispatchSelectionEvent(
          SelectionEdgeUpdateEvent(globalPosition: pos, isStart: false),
        );
    }
  }

  void _onDragUpdate(int col, int row) {
    // Drag moves only the end (the cursor); the anchor stays put.
    // onTapDown always sets both edges to the press point before any
    // drag arrives, so we can dispatch unconditionally.
    final pos = CellOffset(col, row);
    _delegate.dispatchSelectionEvent(
      SelectionEdgeUpdateEvent(globalPosition: pos, isStart: false),
    );
    _maybeUpdateAutoScroll(pos);
  }

  void _onDragEnd() {
    // Drag end commits the selection — invalidate any pending
    // post-frame dispatch so a late tick can't extend past what
    // we're about to copy.
    _cancelAutoScroll();
    if (!widget.copyOnRelease) return;
    final text = _delegate.getSelectedText();
    if (text.isEmpty) return;
    // Fire-and-forget — apps that need to observe the result should
    // write to ClipboardScope.of(context) themselves.
    unawaited(ClipboardScope.of(context).write(text));
  }

  // ----- Auto-scroll -------------------------------------------------
  //
  // Driven entirely off the (visible) cellBounds the SelectableTextMixin
  // already publishes — we don't need to know about ScrollView's
  // internals or even where on screen it lives. The union of every
  // Selectable's visible rect IS the selection area's effective
  // viewport. When the drag cursor enters the top or bottom edge zone
  // of that union AND the supplied scrollController can still move in
  // that direction, we tick the controller and re-dispatch the cursor
  // so the selection extends into the newly-visible content.

  void _maybeUpdateAutoScroll(CellOffset cursor) {
    final controller = widget.scrollController;
    if (controller == null) {
      _stopAutoScroll();
      return;
    }
    final region = _visibleSelectableRegion();
    if (region == null) {
      _stopAutoScroll();
      return;
    }
    final edge = widget.autoScrollEdgeRows;
    // The bottom zone has no UPPER bound — a cursor dragged WAY past
    // the visible bottom (e.g. user yanks down hard) should keep
    // scrolling, not stop because it's "below the zone." Symmetric
    // for the top.
    final inTopZone = cursor.row < region.top + edge && !controller.atTop;
    final inBottomZone =
        cursor.row >= region.bottom - edge && !controller.atBottom;
    _autoScrollCursor = cursor;
    if (inTopZone) {
      _startAutoScroll(-1);
    } else if (inBottomZone) {
      _startAutoScroll(1);
    } else {
      _stopAutoScroll();
    }
  }

  void _startAutoScroll(int direction) {
    if (_autoScrollDirection == direction && _autoScrollTimer != null) return;
    _autoScrollTimer?.cancel();
    _autoScrollDirection = direction;
    _autoScrollTimer = Timer.periodic(widget.autoScrollInterval, (_) {
      _autoScrollTick();
    });
  }

  /// Stops the timer and clears in-flight state. Does NOT bump the
  /// generation counter — self-termination (reaching atTop/atBottom,
  /// cursor leaving the edge zone) leaves any queued post-frame
  /// dispatch valid, since it would correctly extend the selection
  /// to the final cursor position. Use [_cancelAutoScroll] when the
  /// user has actually ended the interaction (mouse up, dispose) to
  /// also invalidate queued dispatches.
  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollDirection = 0;
    _autoScrollCursor = null;
  }

  /// Stops auto-scroll AND invalidates any queued post-frame
  /// dispatches. Used on drag end / dispose — after the user has
  /// committed (e.g. via copyOnRelease), a late-firing post-frame
  /// would silently extend past what was captured.
  void _cancelAutoScroll() {
    _stopAutoScroll();
    _autoScrollGeneration++;
  }

  void _autoScrollTick() {
    final controller = widget.scrollController;
    final cursor = _autoScrollCursor;
    if (controller == null || cursor == null) {
      _stopAutoScroll();
      return;
    }
    if (_autoScrollDirection < 0 ? controller.atTop : controller.atBottom) {
      _stopAutoScroll();
      return;
    }
    controller.scrollBy(_autoScrollDirection);
    // Re-dispatch the cursor AFTER the next paint — Selectables only
    // refresh their bounds during paint, so an immediate dispatch
    // would hit-test against stale geometry and the selection would
    // fail to extend. Scheduling via the binding's post-frame queue
    // means we read the newly-visible row's bounds and route the
    // cursor to whatever content is now under the user's mouse.
    final binding = TuiBinding.maybeOf(context);
    if (binding == null) {
      // No binding (tests with no TuiBinding scope, etc.) — fall
      // back to a synchronous dispatch. Correctness suffers in the
      // sense that this tick won't extend, but the next tick or the
      // next user event will catch up.
      _delegate.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent(globalPosition: cursor, isStart: false),
      );
      return;
    }
    // Coalesce: only one post-frame dispatch per pump cycle. The
    // closure captures the cursor BY VALUE at queue time, so it
    // survives the timer self-stopping (which nulls
    // `_autoScrollCursor`). Subsequent ticks that fire before the
    // pump skip re-queueing — the in-flight callback already has a
    // cursor that's just as good.
    if (_autoScrollDispatchQueued) return;
    _autoScrollDispatchQueued = true;
    final pinnedCursor = cursor;
    final queuedGeneration = _autoScrollGeneration;
    binding.addPostFrameCallback((_) {
      _autoScrollDispatchQueued = false;
      // Guard against late-fire after dispose or after the drag
      // ended. If `_stopAutoScroll` ran between queue and fire, the
      // generation no longer matches and we MUST NOT dispatch — that
      // would extend the selection past what `copyOnRelease` already
      // captured.
      if (!mounted) return;
      if (_autoScrollGeneration != queuedGeneration) return;
      _delegate.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent(globalPosition: pinnedCursor, isStart: false),
      );
    });
  }

  /// Union of every VISIBLE Selectable's bounds — the effective
  /// "selection viewport" for edge-detection. Off-screen Selectables
  /// (visibleBounds == null) don't count; if they did, the union
  /// would stretch beyond what the user actually sees and the
  /// auto-scroll edge zone would land in the wrong place. Null when
  /// no Selectable is currently visible.
  CellRect? _visibleSelectableRegion() {
    CellRect? region;
    for (final s in _delegate.selectables) {
      final r = s.visibleBounds;
      if (r == null) continue;
      region = region == null ? r : region.union(r);
    }
    return region;
  }

  void _onSelectAll(KeyBindingEvent event) {
    _delegate.dispatchSelectionEvent(
      const SelectionGranularEvent(granularity: SelectionGranularity.all),
    );
  }

  void _extendCursor(int dCol, int dRow, KeyBindingEvent event) {
    final cursor = _delegate.cursor;
    if (cursor == null) {
      // No selection in flight — bubble so this Shift+Arrow can reach
      // a different consumer (focus traversal, scroll, etc.).
      event.bubble();
      return;
    }
    // Ask the Selectables where the next grapheme boundary lives.
    // This is what makes Shift+Arrow correct for wide characters
    // (CJK, emoji, ZWJ): we step one whole grapheme, not one cell.
    final next = _delegate.findNextGraphemeBoundary(cursor, dCol, dRow);
    if (next == null) return; // at edge of all selectable content
    _delegate.moveCursorTo(next);
  }

  /// Extends the moving edge to the start ([dir] < 0) or end ([dir] > 0) of
  /// the cursor's current row — the Shift+Home / Shift+End convention. The
  /// target is the left / right edge of the Selectable the cursor sits in;
  /// routing a point at the trailing edge through [moveCursorTo] maps it to
  /// the end-of-content offset (the same path a mouse-drag-past-the-end
  /// takes), so End reaches past the last character — which the
  /// grapheme-by-grapheme walk deliberately can't.
  void _extendToLineEdge(int dir, KeyBindingEvent event) {
    final cursor = _delegate.cursor;
    if (cursor == null) {
      // No selection in flight — bubble so Home/End can reach another
      // consumer (scroll-to-top/bottom, focus traversal).
      event.bubble();
      return;
    }
    for (final s in _delegate.selectables) {
      final b = s.cellBounds;
      if (b == null) continue;
      final withinRows =
          cursor.row >= b.offset.row && cursor.row < b.offset.row + b.size.rows;
      final withinCols =
          cursor.col >= b.offset.col &&
          cursor.col <= b.offset.col + b.size.cols;
      if (!withinRows || !withinCols) continue;
      final col = dir < 0 ? b.offset.col : b.offset.col + b.size.cols;
      final target = CellOffset(col, cursor.row);
      if (target != cursor) _delegate.moveCursorTo(target);
      return;
    }
  }

  void _onCopy(KeyBindingEvent event) {
    final text = _delegate.getSelectedText();
    if (text.isEmpty) {
      // Nothing to copy — let an ancestor binding handle Ctrl+C
      // (e.g. the framework-level exit guard in runApp).
      event.bubble();
      return;
    }
    unawaited(ClipboardScope.of(context).write(text));
  }

  void _onEscape(KeyBindingEvent event) {
    final hadSelection = _delegate.getSelectedText().isNotEmpty;
    if (!hadSelection) {
      event.bubble();
      return;
    }
    _delegate.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionScope(
      registrar: _delegate,
      child: KeyBindings(
        bindings: [
          KeyBinding.event(KeySequence.ctrl.a, onEvent: _onSelectAll),
          KeyBinding.event(KeySequence.ctrl.c, onEvent: _onCopy),
          KeyBinding.event(KeySequence.escape, onEvent: _onEscape),
          KeyBinding.event(
            KeySequence.shift.left,
            onEvent: (e) => _extendCursor(-1, 0, e),
          ),
          KeyBinding.event(
            KeySequence.shift.right,
            onEvent: (e) => _extendCursor(1, 0, e),
          ),
          KeyBinding.event(
            KeySequence.shift.up,
            onEvent: (e) => _extendCursor(0, -1, e),
          ),
          KeyBinding.event(
            KeySequence.shift.down,
            onEvent: (e) => _extendCursor(0, 1, e),
          ),
          KeyBinding.event(
            KeySequence.shift.home,
            onEvent: (e) => _extendToLineEdge(-1, e),
          ),
          KeyBinding.event(
            KeySequence.shift.end,
            onEvent: (e) => _extendToLineEdge(1, e),
          ),
        ],
        child: GestureDetector(
          onTapDownWithModifiers: _onTapDown,
          onDragStart: _onDragUpdate,
          onDragUpdate: _onDragUpdate,
          onDragEnd: _onDragEnd,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Implementation of [SelectionArea.disabled]: a [SelectionScope]
/// publishing a null registrar so Selectables see "no ambient area"
/// and their `attachToSelection` calls are no-ops.
class _DisabledSelection extends StatelessWidget {
  const _DisabledSelection({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SelectionScope(registrar: null, child: child);
  }
}

/// The host's app-wide default text selection, wrapped around every app root.
///
/// Text selection is *input infrastructure*, not app policy: like the
/// clipboard, pointer, and focus scopes the host installs, it turns rendered
/// [Text] into copyable content — which terminal users expect of everything on
/// screen (four decades of "drag to select, copy" on every character a
/// terminal draws). So the host enables it around every app root rather than
/// leaving each app to opt in. There is intentionally no global off switch:
/// the per-subtree escapes below cover the real cases, and idle selectables
/// are free (they cost an O(1) registration + one inherited lookup, with the
/// reading-order walk happening only on a selection event, not per frame).
///
/// Its chords defer to the app. Dispatch is deepest-first, so an app's own
/// Ctrl+A / Ctrl+C / Esc bindings sit deeper in the chain and win; this acts
/// only as the outermost fallback (just above the runApp exit guard), and its
/// Ctrl+C / Esc / Shift+Arrow bindings bubble when nothing is selected. An app
/// that wants different selection behavior (auto-copy, a scroll controller, a
/// change callback) nests its own [SelectionArea], which shadows this one for
/// its subtree; a subtree opts out entirely with [SelectionArea.disabled] or
/// `Text(allowSelect: false)`.
///
/// Deliberately scoped to the app root: floating host layers (the runtime
/// error overlay, the debug shell, toasts, menus) are separate overlay
/// entries and keep their own selection context.
class DefaultRootSelection extends StatelessWidget {
  const DefaultRootSelection({super.key, required this.child});

  /// The app root to make selectable.
  final Widget child;

  @override
  Widget build(BuildContext context) => SelectionArea(child: child);
}
