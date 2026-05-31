// Widget-level pointer routing. Mouse events arrive from the driver as
// absolute cell coordinates; this layer maps them to the widgets under
// the pointer and fires their tap / hover / scroll callbacks.
//
// Rather than retrofit a `hitTest` onto every render object, regions
// register their painted rect into a [PointerRouter] during paint — the
// same paint-time-rect idiom the focus system and Anchor already use, and
// exactly right for a transform-free cell grid where paint order is z
// order. The router is cleared each frame and repopulated on paint, so
// only what's currently on screen is hit-testable.

import '../foundation/geometry.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
import '../terminal/events.dart';
import 'framework.dart';

typedef PointerTapCallback = void Function();
typedef PointerPositionCallback = void Function(int col, int row);

/// Like [PointerPositionCallback] but also exposes the keyboard
/// modifiers the terminal reported on the originating mouse event.
/// Used by gestures that distinguish plain click from Shift / Ctrl /
/// Alt-click — e.g. Shift+Click in a [SelectionArea] extends the
/// selection to the click point instead of starting a new one.
typedef PointerModifiedTapCallback =
    void Function(int col, int row, Set<KeyModifier> modifiers);

/// Per-frame registry of pointer-listening regions plus hover state.
/// One instance per runtime; [beginFrame] clears it before each paint and
/// regions re-register as they paint.
class PointerRouter {
  final List<RenderPointerListener> _regions = <RenderPointerListener>[];
  RenderPointerListener? _hovered;
  RenderPointerListener? _downTarget;
  MouseButton _downButton = MouseButton.none;

  // Drag capture: once a drag begins over a region it keeps receiving the
  // motion until release, even when the pointer leaves its bounds.
  RenderPointerListener? _dragTarget;
  bool _dragging = false;

  /// Clears the registry at the start of a paint pass.
  void beginFrame() => _regions.clear();

  // Registers a region in paint order (later = on top). Called by the
  // region's render object during paint.
  void _register(RenderPointerListener region) => _regions.add(region);

  void _remove(RenderPointerListener region) {
    _regions.remove(region);
    if (identical(_hovered, region)) _hovered = null;
    if (identical(_downTarget, region)) _downTarget = null;
    if (identical(_dragTarget, region)) {
      _dragTarget = null;
      _dragging = false;
    }
  }

  /// Topmost region containing ([col], [row]) for which [pred] holds.
  RenderPointerListener? _topmost(
    int col,
    int row,
    bool Function(RenderPointerListener) pred,
  ) {
    for (var i = _regions.length - 1; i >= 0; i--) {
      final r = _regions[i];
      final rect = r._rect;
      if (rect == null || !pred(r)) continue;
      if (col >= rect.left &&
          col < rect.right &&
          row >= rect.top &&
          row < rect.bottom) {
        return r;
      }
    }
    return null;
  }

  /// Routes [event] to the matching region(s). Returns whether any
  /// handler fired (the dispatcher still runs click-to-focus regardless).
  bool route(MouseEvent event) {
    _updateHover(event);
    switch (event.kind) {
      case MouseEventKind.scrollUp:
        final t = _topmost(event.col, event.row, (r) => r.onScrollUp != null);
        t?.onScrollUp?.call();
        return t != null;
      case MouseEventKind.scrollDown:
        final t = _topmost(event.col, event.row, (r) => r.onScrollDown != null);
        t?.onScrollDown?.call();
        return t != null;
      case MouseEventKind.down:
        _downTarget = _topmost(event.col, event.row, _hasTap);
        _downButton = event.button;
        _downTarget?.onTapDown?.call(event.col, event.row);
        _downTarget?.onTapDownWithModifiers?.call(
          event.col,
          event.row,
          event.modifiers,
        );
        // Arm (but don't start) a drag from the region under the press.
        _dragTarget = event.button == MouseButton.left
            ? _topmost(event.col, event.row, _hasDrag)
            : null;
        _dragging = false;
        return _downTarget != null || _dragTarget != null;
      case MouseEventKind.up:
        // A completed drag consumes the release — no tap fires.
        if (_dragging) {
          _dragTarget?.onDragEnd?.call();
          _dragTarget = null;
          _dragging = false;
          _downTarget = null;
          return true;
        }
        final t = _topmost(event.col, event.row, _hasTap);
        t?.onTapUp?.call(event.col, event.row);
        var fired = false;
        if (t != null && identical(t, _downTarget)) {
          if (_downButton == MouseButton.left && t.onTap != null) {
            t.onTap!();
            fired = true;
          } else if (_downButton == MouseButton.right &&
              t.onSecondaryTap != null) {
            t.onSecondaryTap!();
            fired = true;
          }
        }
        _downTarget = null;
        _dragTarget = null;
        _downButton = MouseButton.none;
        return fired || t != null;
      case MouseEventKind.drag:
        // Captured drag: route to the armed target regardless of position.
        if (_dragTarget != null) {
          if (!_dragging) {
            _dragging = true;
            _dragTarget!.onDragStart?.call(event.col, event.row);
          } else {
            _dragTarget!.onDragUpdate?.call(event.col, event.row);
          }
          return true;
        }
        _hovered?.onHover?.call(event.col, event.row);
        return _hovered != null;
      case MouseEventKind.moved:
        _hovered?.onHover?.call(event.col, event.row);
        return _hovered != null;
    }
  }

  static bool _hasTap(RenderPointerListener r) =>
      r.onTap != null ||
      r.onTapDown != null ||
      r.onTapDownWithModifiers != null ||
      r.onTapUp != null ||
      r.onSecondaryTap != null;

  static bool _hasDrag(RenderPointerListener r) =>
      r.onDragStart != null || r.onDragUpdate != null || r.onDragEnd != null;

  static bool _hasHover(RenderPointerListener r) =>
      r.onEnter != null || r.onExit != null || r.onHover != null;

  void _updateHover(MouseEvent event) {
    final next = _topmost(event.col, event.row, _hasHover);
    if (identical(next, _hovered)) return;
    _hovered?.onExit?.call();
    _hovered = next;
    next?.onEnter?.call();
  }
}

/// Shares a [PointerRouter] with its subtree. Read by pointer widgets so
/// their render objects can register. Provided once near the root.
class PointerRouterScope extends InheritedWidget {
  const PointerRouterScope({
    super.key,
    required this.router,
    required super.child,
  });

  final PointerRouter router;

  static PointerRouter? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PointerRouterScope>()?.router;

  @override
  bool updateShouldNotify(PointerRouterScope oldWidget) =>
      !identical(router, oldWidget.router);
}

/// Reports taps (and right-clicks) on its [child]. A tap is a press and
/// release within the same region — the terminal analogue of a button
/// press. Pair with a `Focus` if the target should also take keyboard
/// focus (click-to-focus handles that automatically for focusables).
class GestureDetector extends StatelessWidget {
  const GestureDetector({
    super.key,
    this.onTap,
    this.onTapDown,
    this.onTapDownWithModifiers,
    this.onTapUp,
    this.onSecondaryTap,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    required this.child,
  });

  final PointerTapCallback? onTap;
  final PointerPositionCallback? onTapDown;

  /// Fires on a left-button press alongside [onTapDown], with the
  /// terminal-reported modifier set. Use when you need to distinguish
  /// plain click from Shift / Ctrl / Alt-click. Both callbacks fire
  /// on every press — register only the one you care about.
  final PointerModifiedTapCallback? onTapDownWithModifiers;
  final PointerPositionCallback? onTapUp;
  final PointerTapCallback? onSecondaryTap;

  /// Drag: a left press, then motion (with the button held), then
  /// release. The region keeps receiving [onDragUpdate] even when the
  /// pointer leaves it (pointer capture), so sliders and splitters track
  /// smoothly. A drag suppresses [onTap].
  final PointerPositionCallback? onDragStart;
  final PointerPositionCallback? onDragUpdate;
  final PointerTapCallback? onDragEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) => _PointerListener(
    router: PointerRouterScope.maybeOf(context),
    onTap: onTap,
    onTapDown: onTapDown,
    onTapDownWithModifiers: onTapDownWithModifiers,
    onTapUp: onTapUp,
    onSecondaryTap: onSecondaryTap,
    onDragStart: onDragStart,
    onDragUpdate: onDragUpdate,
    onDragEnd: onDragEnd,
    child: child,
  );
}

/// Reports the pointer entering, moving within, and leaving its [child].
/// Hover requires motion tracking (`TerminalMode.mouseMotion`); without
/// it, enter/exit still fire on clicks.
class MouseRegion extends StatelessWidget {
  const MouseRegion({
    super.key,
    this.onEnter,
    this.onExit,
    this.onHover,
    required this.child,
  });

  final PointerTapCallback? onEnter;
  final PointerTapCallback? onExit;
  final PointerPositionCallback? onHover;
  final Widget child;

  @override
  Widget build(BuildContext context) => _PointerListener(
    router: PointerRouterScope.maybeOf(context),
    onEnter: onEnter,
    onExit: onExit,
    onHover: onHover,
    child: child,
  );
}

class _PointerListener extends SingleChildRenderObjectWidget {
  const _PointerListener({
    required this.router,
    this.onTap,
    this.onTapDown,
    this.onTapDownWithModifiers,
    this.onTapUp,
    this.onSecondaryTap,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onEnter,
    this.onExit,
    this.onHover,
    required Widget super.child,
  });

  final PointerRouter? router;
  final PointerTapCallback? onTap;
  final PointerPositionCallback? onTapDown;
  final PointerModifiedTapCallback? onTapDownWithModifiers;
  final PointerPositionCallback? onTapUp;
  final PointerTapCallback? onSecondaryTap;
  final PointerPositionCallback? onDragStart;
  final PointerPositionCallback? onDragUpdate;
  final PointerTapCallback? onDragEnd;
  final PointerTapCallback? onEnter;
  final PointerTapCallback? onExit;
  final PointerPositionCallback? onHover;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPointerListener()
        ..router = router
        ..onTap = onTap
        ..onTapDown = onTapDown
        ..onTapDownWithModifiers = onTapDownWithModifiers
        ..onTapUp = onTapUp
        ..onSecondaryTap = onSecondaryTap
        ..onDragStart = onDragStart
        ..onDragUpdate = onDragUpdate
        ..onDragEnd = onDragEnd
        ..onEnter = onEnter
        ..onExit = onExit
        ..onHover = onHover;

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderPointerListener renderObject,
  ) {
    renderObject
      ..router = router
      ..onTap = onTap
      ..onTapDown = onTapDown
      ..onTapDownWithModifiers = onTapDownWithModifiers
      ..onTapUp = onTapUp
      ..onSecondaryTap = onSecondaryTap
      ..onDragStart = onDragStart
      ..onDragUpdate = onDragUpdate
      ..onDragEnd = onDragEnd
      ..onEnter = onEnter
      ..onExit = onExit
      ..onHover = onHover;
  }
}

/// A scroll-only pointer region (no public widget) used by core scrollables
/// to claim wheel events under the pointer. Exposed for ListView /
/// ScrollView to wrap their viewports.
class PointerScrollListener extends SingleChildRenderObjectWidget {
  const PointerScrollListener({
    super.key,
    required this.router,
    this.onScrollUp,
    this.onScrollDown,
    required Widget super.child,
  });

  final PointerRouter? router;
  final PointerTapCallback? onScrollUp;
  final PointerTapCallback? onScrollDown;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPointerListener()
        ..router = router
        ..onScrollUp = onScrollUp
        ..onScrollDown = onScrollDown;

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderPointerListener renderObject,
  ) {
    renderObject
      ..router = router
      ..onScrollUp = onScrollUp
      ..onScrollDown = onScrollDown;
  }
}

class RenderPointerListener extends RenderObject
    implements RenderObjectWithSingleChild {
  PointerRouter? _router;
  set router(PointerRouter? value) {
    if (identical(_router, value)) return;
    _router?._remove(this);
    _router = value;
  }

  PointerTapCallback? onTap;
  PointerPositionCallback? onTapDown;
  PointerModifiedTapCallback? onTapDownWithModifiers;
  PointerPositionCallback? onTapUp;
  PointerTapCallback? onSecondaryTap;
  PointerPositionCallback? onDragStart;
  PointerPositionCallback? onDragUpdate;
  PointerTapCallback? onDragEnd;
  PointerTapCallback? onEnter;
  PointerTapCallback? onExit;
  PointerPositionCallback? onHover;
  PointerTapCallback? onScrollUp;
  PointerTapCallback? onScrollDown;

  CellRect? _rect;

  RenderObject? _child;
  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) dropChild(_child!);
    _child = value;
    if (value != null) adoptChild(value);
  }

  @override
  CellSize performLayout(CellConstraints constraints) =>
      _child?.layout(constraints) ?? constraints.constrain(CellSize.zero);

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    _rect = CellRect(offset: offset, size: size);
    _router?._register(this);
    _child?.paint(
      buffer,
      offset,
      screenOffset: screenOffset ?? offset,
      clipRect: clipRect,
    );
  }
}
