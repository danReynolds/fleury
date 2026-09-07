// Pointer hit-testing follows presented layout, clipping, and paint order.
import 'package:meta/meta.dart';

import '../foundation/geometry.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
import '../input/events.dart';
import 'framework.dart';
import 'focus.dart';
import '../semantics/semantics.dart';

/// Pointer shapes for hosts that can display them, such as the browser.
/// Terminal hosts keep their own pointer appearance.
enum MouseCursor { basic, pointer, text, resizeLeftRight, resizeUpDown }

typedef PointerTapCallback = void Function();
typedef PointerCallback = void Function(PointerDetails details);
typedef PointerDragCallback = void Function(PointerDragDetails details);
typedef PointerScrollCallback = bool Function(PointerScrollDetails details);

/// A pointer position in terminal cells. Local coordinates are relative to the
/// receiving region; global coordinates are relative to the application surface.
@immutable
class PointerDetails {
  PointerDetails({
    required this.localPosition,
    required this.globalPosition,
    required this.button,
    Set<KeyModifier> modifiers = const {},
  }) : modifiers = Set<KeyModifier>.unmodifiable(modifiers);

  final CellOffset localPosition;
  final CellOffset globalPosition;
  final MouseButton button;
  final Set<KeyModifier> modifiers;
  bool get hasCtrl => modifiers.contains(KeyModifier.ctrl);
  bool get hasAlt => modifiers.contains(KeyModifier.alt);
  bool get hasShift => modifiers.contains(KeyModifier.shift);
}

/// Captured primary-button motion, including the initial press and movement
/// since the previous report. Delta stays stable when the region itself moves.
@immutable
final class PointerDragDetails extends PointerDetails {
  PointerDragDetails({
    required super.localPosition,
    required super.globalPosition,
    required super.button,
    super.modifiers,
    required this.delta,
    required this.globalPressPosition,
  });
  final CellOffset delta;
  final CellOffset globalPressPosition;
}

/// One wheel step. Negative [delta.row] scrolls up, positive scrolls down.
@immutable
final class PointerScrollDetails extends PointerDetails {
  PointerScrollDetails({
    required super.localPosition,
    required super.globalPosition,
    required super.button,
    super.modifiers,
    required this.delta,
  });
  final CellOffset delta;
}

/// Routes pointer input against the presented render tree. Gesture capture lasts
/// until the matching release or cancellation; hover and wheel follow ancestors.
class PointerRouter {
  final Set<RenderObject> _inputExcludedSubtrees = {};
  final List<RenderObject> _hits = [];
  final Set<RenderPointerListener> _cursorRegions = {};
  bool _cursorRegionsChanged = false;
  List<RenderPointerListener> _hovered = [];
  final List<RenderPointerListener> _tapTargets = [];
  RenderPointerListener? _downTarget;
  RenderPointerListener? _dragTarget;
  MouseEvent? _press;
  CellOffset? _lastDragPosition;
  MouseEvent? _lastHoverEvent;
  bool _dragging = false;
  bool _disposed = false;
  bool _aborted = false;
  Element? _scope;

  void _attachScope(Element scope) => _scope ??= scope;
  void _detachScope(Element scope) {
    if (identical(_scope, scope)) _scope = null;
  }

  void beginFrame() {}

  /// Reconciles targets after layout. Hidden live controls receive cancellation;
  /// removed or error-excluded subtrees receive no callbacks.
  void endFrame() {
    if (_disposed) return;
    _aborted = false;
    _dropInactive();
    for (final region in _cursorRegions) {
      final bounds = region.screenGeometry()?.visible;
      if (region._cursorBounds != bounds) {
        region._cursorBounds = bounds;
        _cursorRegionsChanged = true;
      }
    }
    if (_cursorRegionsChanged) {
      _scope?.owner.semanticDirtyTracker.recordStructureDirty();
      _cursorRegionsChanged = false;
    }
    final event = _lastHoverEvent;
    if (event != null) _updateHover(event);
  }

  void _dropInactive() {
    final exits = _hovered.where((r) => !_isLive(r)).toList();
    final cancelled = _tapTargets.where((r) => !_isLive(r)).toList();
    _hovered.removeWhere(exits.contains);
    _tapTargets.removeWhere(cancelled.contains);
    if (_downTarget != null && !_isLive(_downTarget!)) _downTarget = null;
    final drag = _dragTarget;
    final cancelDrag = _dragging && drag != null && !_isLive(drag);
    if (drag != null && !_isLive(drag)) {
      _dragTarget = null;
      _dragging = false;
    }
    if (_downTarget == null && _dragTarget == null) _clearSequence();
    for (final target in exits.reversed) {
      if (_isAttached(target)) target.onExit?.call();
    }
    for (final target in cancelled) {
      if (_isAttached(target)) target.onTapCancel?.call();
    }
    if (cancelDrag && _isAttached(drag)) drag.onDragCancel?.call();
  }

  void abortFrame() {
    _aborted = true;
    _hovered.clear();
    _lastHoverEvent = null;
    _clearSequence();
  }

  /// Teardown is silent: the application tree may already be unmounted.
  void dispose() {
    _disposed = true;
    _scope = null;
    _hits.clear();
    _cursorRegions.clear();
    _inputExcludedSubtrees.clear();
    abortFrame();
  }

  @internal
  void setSubtreeInputExcluded(RenderObject subtree, bool excluded) {
    if (_disposed) return;
    if (excluded) {
      _inputExcludedSubtrees.add(subtree);
      _dropInactive();
    } else {
      _inputExcludedSubtrees.remove(subtree);
    }
  }

  static bool _under(RenderObject node, RenderObject root) {
    for (
      RenderObject? current = node;
      current != null;
      current = current.parent
    ) {
      if (identical(current, root)) return true;
    }
    return false;
  }

  bool _isAttached(RenderPointerListener region) =>
      identical(region._router, this) &&
      !_inputExcludedSubtrees.any((root) => _under(region, root));

  bool _isLive(RenderPointerListener region) =>
      _isAttached(region) && region.screenGeometry()?.visible != null;

  void _updateCursorRegion(RenderPointerListener region) {
    if (region.cursor == null) {
      _cursorRegions.remove(region);
    } else {
      _cursorRegions.add(region);
    }
    _cursorRegionsChanged = true;
  }

  void _remove(RenderPointerListener region) {
    if (_cursorRegions.remove(region)) _cursorRegionsChanged = true;
    _hovered.remove(region);
    _tapTargets.remove(region);
    if (identical(_downTarget, region)) _downTarget = null;
    if (identical(_dragTarget, region)) {
      _dragTarget = null;
      _dragging = false;
    }
  }

  void _collectHits(int col, int row) {
    _hits.clear();
    if (_aborted || _disposed) return;
    final start = _scope?.findRenderObject();
    if (start != null) _visitHits(start, col, row, null);
  }

  void _visitHits(RenderObject node, int col, int row, CellRect? clip) {
    if (!node.hasLayout || _inputExcludedSubtrees.contains(node)) return;
    final point = CellOffset(col, row);
    if (clip != null && !clip.contains(point)) return;
    final inside =
        col >= 0 && row >= 0 && col < node.size.cols && row < node.size.rows;
    if (!inside && !node.hitTestsBeyondBounds) return;
    if (inside) _hits.add(node);
    node.visitRenderChildren((child) {
      if (!node.presentsChild(child)) return;
      var childClip = clip;
      final ownClip = node.childClipOf(child);
      if (ownClip != null) {
        childClip = clip == null ? ownClip : clip.intersect(ownClip);
        if (childClip == null || !childClip.contains(point)) return;
      }
      final offset = node.childOffsetOf(child);
      _visitHits(
        child,
        col - offset.col,
        row - offset.row,
        childClip == null
            ? null
            : CellRect(offset: childClip.offset - offset, size: childClip.size),
      );
    });
  }

  RenderPointerListener? _topmost(
    int col,
    int row,
    bool Function(RenderPointerListener) test,
  ) {
    _collectHits(col, row);
    for (final hit in _hits.reversed) {
      if (hit is RenderPointerListener &&
          identical(hit._router, this) &&
          test(hit)) {
        return hit;
      }
    }
    return null;
  }

  /// Uses the same clipped, front-to-back hit order as gestures. A foreground
  /// gesture boundary cannot focus an unrelated sibling behind it.
  @internal
  FocusNode? focusTargetAt(int col, int row, FocusManager manager) {
    _collectHits(col, row);
    for (final hit in _hits.reversed) {
      final node = focusNodeForPointerHit(hit);
      if (node != null && manager.isClickable(node)) return node;
      if (hit is RenderPointerListener && (_hasTap(hit) || _hasDrag(hit))) {
        if (hit.absorbsFocus) return null;
        for (
          RenderObject? parent = hit.parent;
          parent != null;
          parent = parent.parent
        ) {
          final ancestor = focusNodeForPointerHit(parent);
          if (ancestor != null && manager.isClickable(ancestor)) {
            return ancestor;
          }
          if (parent is RenderPointerListener && parent.absorbsFocus) {
            return null;
          }
        }
        return null;
      }
    }
    return null;
  }

  bool focusAbsorbedAt(int col, int row) =>
      _topmost(col, row, (r) => _hasTap(r) || _hasDrag(r))?.absorbsFocus ??
      false;

  PointerDetails _details(RenderPointerListener target, MouseEvent event) {
    final global = CellOffset(event.col, event.row);
    return PointerDetails(
      localPosition:
          global - (target.screenGeometry()?.bounds.offset ?? CellOffset.zero),
      globalPosition: global,
      button: event.button,
      modifiers: event.modifiers,
    );
  }

  PointerDragDetails _dragDetails(
    RenderPointerListener target,
    MouseEvent event,
    CellOffset delta,
  ) {
    final details = _details(target, event);
    final press = _press!;
    return PointerDragDetails(
      localPosition: details.localPosition,
      globalPosition: details.globalPosition,
      button: press.button,
      modifiers: details.modifiers,
      delta: delta,
      globalPressPosition: CellOffset(press.col, press.row),
    );
  }

  void _clearSequence() {
    _downTarget = null;
    _dragTarget = null;
    _tapTargets.clear();
    _press = null;
    _lastDragPosition = null;
    _dragging = false;
  }

  void _cancelTaps() {
    final targets = List<RenderPointerListener>.of(_tapTargets);
    _tapTargets.clear();
    for (final target in targets) {
      if (_isLive(target)) target.onTapCancel?.call();
    }
  }

  /// Releases input authority (for example terminal focus loss or suspension).
  /// Live widgets receive cancellation and hover exit; disposed widgets do not.
  void cancel() {
    if (_disposed) return;
    final drag = _dragging ? _dragTarget : null;
    _cancelTaps();
    _clearSequence();
    if (drag != null && _isLive(drag)) drag.onDragCancel?.call();
    _leave();
  }

  void _leave() {
    _lastHoverEvent = null;
    final previous = _hovered;
    _hovered = [];
    for (final target in previous.reversed) {
      if (_isLive(target)) target.onExit?.call();
    }
  }

  bool route(MouseEvent event) {
    if (_disposed || _aborted) return false;
    if (event.kind == MouseEventKind.cancel) {
      cancel();
      return true;
    }
    if (event.kind == MouseEventKind.leave) {
      _leave();
      return true;
    }
    _updateHover(event);
    switch (event.kind) {
      case MouseEventKind.scrollUp:
      case MouseEventKind.scrollDown:
        final target = _topmost(
          event.col,
          event.row,
          (r) => r.onScroll != null || _hasTap(r) || _hasDrag(r),
        );
        for (RenderObject? node = target; node != null; node = node.parent) {
          if (node is! RenderPointerListener || !_isLive(node)) continue;
          final details = _details(node, event);
          if (node.onScroll?.call(
                PointerScrollDetails(
                  localPosition: details.localPosition,
                  globalPosition: details.globalPosition,
                  button: details.button,
                  modifiers: details.modifiers,
                  delta: CellOffset(
                    0,
                    event.kind == MouseEventKind.scrollUp ? -1 : 1,
                  ),
                ),
              ) ??
              false) {
            return true;
          }
        }
        return false;
      case MouseEventKind.down:
        if (_press != null) {
          _cancelTaps();
          final drag = _dragging ? _dragTarget : null;
          _clearSequence();
          if (drag != null && _isLive(drag)) drag.onDragCancel?.call();
        }
        _press = event;
        _lastDragPosition = CellOffset(event.col, event.row);
        _downTarget = _topmost(
          event.col,
          event.row,
          (r) => _hasTap(r) || _hasDrag(r),
        );
        // A parent selection region can claim motion that starts on a tap-only child.
        if (event.button == MouseButton.left) {
          for (
            RenderObject? node = _downTarget;
            node != null;
            node = node.parent
          ) {
            if (node is RenderPointerListener && _hasDrag(node)) {
              _dragTarget = node;
              break;
            }
          }
        }
        final targets = <RenderPointerListener>{?_downTarget, ?_dragTarget};
        for (final target in targets) {
          if (!_isLive(target)) continue;
          target.onPointerDown?.call(_details(target, event));
          if (event.button == MouseButton.left && _isLive(target)) {
            _tapTargets.add(target);
            target.onTapDown?.call(_details(target, event));
          }
        }
        return targets.isNotEmpty;
      case MouseEventKind.up:
        final press = _press;
        if (press == null) return false;
        if (event.button != press.button) {
          cancel();
          return true;
        }
        final target = _downTarget;
        final drag = _dragTarget;
        if (_dragging && drag != null) {
          final details = _dragDetails(
            drag,
            event,
            CellOffset(event.col, event.row) - _lastDragPosition!,
          );
          _clearSequence();
          if (_isLive(drag)) drag.onDragEnd?.call(details);
          return true;
        }
        final released = _topmost(
          event.col,
          event.row,
          (r) => _hasTap(r) || _hasDrag(r),
        );
        final inside = target != null && identical(target, released);
        final taps = List<RenderPointerListener>.of(_tapTargets);
        _clearSequence();
        for (final tap in taps) {
          if (!_isLive(tap)) continue;
          if (inside) {
            tap.onTapUp?.call(_details(tap, event));
          } else {
            tap.onTapCancel?.call();
          }
        }
        if (inside && _isLive(target)) {
          if (press.button == MouseButton.left && taps.isNotEmpty) {
            target.onTap?.call();
          }
          if (press.button == MouseButton.right) target.onSecondaryTap?.call();
        }
        return target != null;
      case MouseEventKind.drag:
        final press = _press;
        if (press == null) return false;
        if (event.button != press.button) {
          cancel();
          return true;
        }
        final position = CellOffset(event.col, event.row);
        final delta = position - _lastDragPosition!;
        if (delta == CellOffset.zero) return false;
        _lastDragPosition = position;
        final drag = _dragTarget;
        if (!_dragging) {
          _cancelTaps();
          if (drag == null) _downTarget = null;
          if (drag != null && _isLive(drag)) {
            _dragging = true;
            drag.onDragStart?.call(_dragDetails(drag, event, delta));
          }
        }
        if (drag != null && _isLive(drag) && _press != null) {
          drag.onDragUpdate?.call(_dragDetails(drag, event, delta));
        }
        return drag != null;
      case MouseEventKind.moved:
        for (final target in List<RenderPointerListener>.of(_hovered)) {
          if (_isLive(target)) target.onHover?.call(_details(target, event));
        }
        return _hovered.isNotEmpty;
      case MouseEventKind.cancel:
      case MouseEventKind.leave:
        return false;
    }
  }

  static bool _hasTap(RenderPointerListener r) =>
      r.onTap != null ||
      r.onTapDown != null ||
      r.onPointerDown != null ||
      r.onTapUp != null ||
      r.onTapCancel != null ||
      r.onSecondaryTap != null;
  static bool _hasDrag(RenderPointerListener r) =>
      r.onDragStart != null ||
      r.onDragUpdate != null ||
      r.onDragEnd != null ||
      r.onDragCancel != null;
  static bool _hasHover(RenderPointerListener r) =>
      r.onEnter != null || r.onExit != null || r.onHover != null;

  void _updateHover(MouseEvent event) {
    _lastHoverEvent = event;
    final top = _topmost(
      event.col,
      event.row,
      (r) => _hasHover(r) || _hasTap(r) || _hasDrag(r),
    );
    final next = <RenderPointerListener>[];
    for (RenderObject? node = top; node != null; node = node.parent) {
      if (node is RenderPointerListener && _isLive(node) && _hasHover(node)) {
        next.insert(0, node);
      }
    }
    final previous = _hovered;
    _hovered = next;
    for (final target in previous.reversed) {
      if (!next.contains(target) && _isLive(target)) target.onExit?.call();
    }
    for (final target in next) {
      if (!previous.contains(target) && _isLive(target)) target.onEnter?.call();
    }
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

  @override
  InheritedElement createElement() => _PointerRouterScopeElement(this);
}

/// Tells the router where its tree is: hit-testing starts at the render
/// object below this element, for as long as it is mounted.
class _PointerRouterScopeElement extends InheritedElement {
  _PointerRouterScopeElement(PointerRouterScope super.widget);

  @override
  PointerRouterScope get widget => super.widget as PointerRouterScope;

  @override
  void mount(Element? parent) {
    super.mount(parent);
    widget.router._attachScope(this);
  }

  @override
  void update(covariant PointerRouterScope newWidget) {
    final old = widget.router;
    super.update(newWidget);
    if (!identical(old, newWidget.router)) {
      old._detachScope(this);
      newWidget.router._attachScope(this);
    }
  }

  @override
  void unmount() {
    widget.router._detachScope(this);
    super.unmount();
  }
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
    this.onPointerDown,
    this.onTapUp,
    this.onTapCancel,
    this.onSecondaryTap,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
    required this.child,
  });

  /// Called after a left-button press and release complete in this region.
  final PointerTapCallback? onTap;

  /// Begins a primary-button press. Paired with [onTapUp] or [onTapCancel].
  final PointerCallback? onTapDown;

  /// Reports any button press. Use [onTapDown] for primary-button gestures.
  final PointerCallback? onPointerDown;

  /// Completes a primary press released inside the original region.
  final PointerCallback? onTapUp;

  /// The press was interrupted, dragged, or released outside its region.
  final PointerTapCallback? onTapCancel;

  /// Called after a right-button press and release complete in this region.
  final PointerTapCallback? onSecondaryTap;

  /// Drag: a left press, then motion (with the button held), then
  /// release. The region keeps receiving [onDragUpdate] even when the
  /// pointer leaves it (pointer capture), so sliders and splitters track
  /// smoothly. A drag suppresses [onTap].
  final PointerDragCallback? onDragStart;

  /// Called for every changed cell during capture, including the first movement.
  final PointerDragCallback? onDragUpdate;

  /// Called when the captured drag ends on button release.
  final PointerDragCallback? onDragEnd;

  /// The captured drag was interrupted before release.
  final PointerTapCallback? onDragCancel;

  /// Subtree whose painted bounds form the interactive region.
  final Widget child;

  @override
  Widget build(BuildContext context) => _PointerListener(
    router: PointerRouterScope.maybeOf(context),
    onTap: onTap,
    onTapDown: onTapDown,
    onPointerDown: onPointerDown,
    onTapUp: onTapUp,
    onTapCancel: onTapCancel,
    onSecondaryTap: onSecondaryTap,
    onDragStart: onDragStart,
    onDragUpdate: onDragUpdate,
    onDragEnd: onDragEnd,
    onDragCancel: onDragCancel,
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
    this.onScroll,
    this.cursor,
    required this.child,
  });

  /// Called when the pointer enters the child's painted bounds.
  final PointerTapCallback? onEnter;

  /// Called when the pointer leaves the child's painted bounds.
  final PointerTapCallback? onExit;

  /// Called on pointer motion with coordinates relative to this region and the surface.
  final PointerCallback? onHover;

  /// Return true to consume the wheel step, false to offer it to an ancestor.
  final PointerScrollCallback? onScroll;

  /// Overrides the host's pointer shape inside this region. Null lets the
  /// host use its ordinary control cursor. Descendant controls can override it.
  final MouseCursor? cursor;

  /// Subtree whose painted bounds define the hover region.
  final Widget child;

  @override
  Widget build(BuildContext context) => _PointerListener(
    router: PointerRouterScope.maybeOf(context),
    onEnter: onEnter,
    onExit: onExit,
    onHover: onHover,
    onScroll: onScroll,
    cursor: cursor,
    child: child,
  );
}

class _PointerListener extends SingleChildRenderObjectWidget {
  const _PointerListener({
    required this.router,
    this.onTap,
    this.onTapDown,
    this.onPointerDown,
    this.onTapUp,
    this.onTapCancel,
    this.onSecondaryTap,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
    this.onEnter,
    this.onExit,
    this.onHover,
    this.onScroll,
    this.cursor,
    required Widget super.child,
  });

  final PointerRouter? router;
  final MouseCursor? cursor;
  final PointerTapCallback? onTap;
  final PointerCallback? onTapDown;
  final PointerCallback? onPointerDown;
  final PointerCallback? onTapUp;
  final PointerTapCallback? onTapCancel;
  final PointerTapCallback? onSecondaryTap;
  final PointerDragCallback? onDragStart;
  final PointerDragCallback? onDragUpdate;
  final PointerDragCallback? onDragEnd;

  /// The captured drag was interrupted before release.
  final PointerTapCallback? onDragCancel;
  final PointerTapCallback? onEnter;
  final PointerTapCallback? onExit;
  final PointerCallback? onHover;

  /// Return true to consume the wheel step, false to offer it to an ancestor.
  final PointerScrollCallback? onScroll;

  @override
  SingleChildRenderObjectElement createElement() =>
      _PointerListenerElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPointerListener()
        ..router = router
        ..cursor = cursor
        ..onTap = onTap
        ..onTapDown = onTapDown
        ..onPointerDown = onPointerDown
        ..onTapUp = onTapUp
        ..onTapCancel = onTapCancel
        ..onSecondaryTap = onSecondaryTap
        ..onDragStart = onDragStart
        ..onDragUpdate = onDragUpdate
        ..onDragEnd = onDragEnd
        ..onDragCancel = onDragCancel
        ..onEnter = onEnter
        ..onExit = onExit
        ..onHover = onHover
        ..onScroll = onScroll;

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderPointerListener renderObject,
  ) {
    renderObject
      ..router = router
      ..cursor = cursor
      ..onTap = onTap
      ..onTapDown = onTapDown
      ..onPointerDown = onPointerDown
      ..onTapUp = onTapUp
      ..onTapCancel = onTapCancel
      ..onSecondaryTap = onSecondaryTap
      ..onDragStart = onDragStart
      ..onDragUpdate = onDragUpdate
      ..onDragEnd = onDragEnd
      ..onDragCancel = onDragCancel
      ..onEnter = onEnter
      ..onExit = onExit
      ..onHover = onHover
      ..onScroll = onScroll;
  }
}

/// A complete pointer boundary: the cells this widget covers consume every
/// pointer interaction — taps, secondary taps, drags, wheel scroll, hover —
/// and block the dispatcher's click-to-focus, so nothing painted underneath
/// can be invisibly activated, scrolled, hovered, or focused.
///
/// This is the input counterpart of painting an opaque overlay: an overlay
/// that covers cells visually must also cover them for input, or clicks fall
/// through to hidden widgets. The debug shell's floating panel uses this
/// boundary. Its descendant controls remain interactive: hit testing visits
/// them before the boundary and stops here before reaching content behind it.
class AbsorbPointer extends SingleChildRenderObjectWidget {
  const AbsorbPointer({super.key, this.onTap, required Widget super.child});

  /// Called when a left-button tap lands on this boundary.
  ///
  /// Descendant pointer regions are visited before the boundary. This is
  /// useful for a full-screen popup barrier: taps on the
  /// popup reach its controls, while taps anywhere else dismiss it without
  /// activating content underneath.
  final PointerTapCallback? onTap;

  static void _noop() {}
  static void _noopAt(PointerDetails details) {}
  static bool _consumeScroll(PointerScrollDetails details) => true;

  @override
  SingleChildRenderObjectElement createElement() =>
      _PointerListenerElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPointerListener()
        ..router = PointerRouterScope.maybeOf(context)
        ..onTap = onTap ?? _noop
        ..onSecondaryTap = _noop
        ..onDragStart = _noopAt
        ..onDragUpdate = _noopAt
        ..onDragEnd = _noopAt
        ..onEnter = _noop
        ..onExit = _noop
        ..onHover = _noopAt
        ..onScroll = _consumeScroll
        ..absorbsFocus = true;

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderPointerListener renderObject,
  ) {
    renderObject
      ..router = PointerRouterScope.maybeOf(context)
      ..onTap = onTap ?? _noop;
  }
}

/// Releases router registrations as soon as an element leaves the active tree
/// rather than waiting for the next paint pass. Hosts schedule frames
/// asynchronously, and a failed update can leave a subtree inactive, so input
/// must not reach it between reconciliation and the replacement frame.
final class _PointerListenerElement extends SingleChildRenderObjectElement
    implements OptionalSemanticContributor {
  _PointerListenerElement(super.widget);

  @override
  bool get contributesSemanticNode =>
      (renderObject as RenderPointerListener).cursor != null;

  @override
  SemanticNode buildSemanticNode(List<SemanticNode> children) => SemanticNode(
    id: SemanticNodeId(
      '${semanticAnchorOf(this) ?? 'element-$hashCode'}/pointerCursor',
    ),
    role: SemanticRole.region,
    bounds: renderObject.screenGeometry()?.visible,
    state: SemanticState({
      'mouseCursor': (renderObject as RenderPointerListener).cursor!.name,
    }),
    children: children,
  );

  @override
  void deactivate() {
    // `maybeRenderObject`: an element whose inflate threw never got a render
    // object, and the throwing getter would compound the original error.
    (maybeRenderObject as RenderPointerListener?)?.router = null;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    // A GlobalKey move can reactivate this element without delivering a new
    // widget, so update the existing render object explicitly to restore its
    // router (and any callbacks) from the new tree position.
    widget.updateRenderObject(this, renderObject);
  }

  @override
  void unmount() {
    (renderObject as RenderPointerListener).router = null;
    super.unmount();
  }
}

class RenderPointerListener extends RenderObject
    implements RenderObjectWithSingleChild {
  PointerRouter? _router;
  set router(PointerRouter? value) {
    if (identical(_router, value)) return;
    _router?._remove(this);
    _router = value;
    if (_cursor != null) _router?._updateCursorRegion(this);
    markNeedsPaintOnly();
  }

  MouseCursor? _cursor;
  CellRect? _cursorBounds;
  MouseCursor? get cursor => _cursor;
  set cursor(MouseCursor? value) {
    if (_cursor == value) return;
    _cursor = value;
    _router?._updateCursorRegion(this);
    markNeedsPaintOnly();
  }

  PointerTapCallback? onTap;
  PointerCallback? onTapDown;
  PointerCallback? onPointerDown;
  PointerCallback? onTapUp;
  PointerTapCallback? onTapCancel;
  PointerTapCallback? onSecondaryTap;
  PointerDragCallback? onDragStart;
  PointerDragCallback? onDragUpdate;
  PointerDragCallback? onDragEnd;
  PointerTapCallback? onDragCancel;
  PointerTapCallback? onEnter;
  PointerTapCallback? onExit;
  PointerCallback? onHover;
  PointerScrollCallback? onScroll;

  /// When true, cells this region covers also block the dispatcher's
  /// click-to-focus pass — a click here must not move app focus to a
  /// focusable painted underneath. Set by [AbsorbPointer]; plain listeners
  /// leave it false. See [PointerRouter.focusAbsorbedAt].
  bool absorbsFocus = false;

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
  void performPaint(CellBuffer buffer, CellOffset offset) {
    _child?.paint(buffer, offset);
  }
}
