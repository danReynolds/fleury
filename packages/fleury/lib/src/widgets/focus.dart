// Focus tree: FocusNode + FocusManager + Focus + FocusScope.
//
// The focus tree is the routing primitive for input. It mirrors
// Flutter's API:
//   - FocusNode is a long-lived object held by a widget's State.
//   - Focus is the widget that wires a FocusNode into the tree.
//   - FocusScope groups focusable children for traversal; with
//     modal: true it stops events from reaching ancestor widgets.
//   - FocusManager is the singleton (one per BuildOwner / runTui)
//     that holds which node is focused, the broadcast for changes,
//     and the dispatch entry point.
//
// In this slice the dispatch is intentionally simple: events walk the
// focused node's element-tree ancestor chain calling each Focus's
// onKey, stopping at the first node that returns
// KeyEventResult.handled or at a modal FocusScope boundary. The richer
// dispatcher (sequence matching, KeyBindings, KeyHintBar) lands in
// the next slice and replaces the direct Focus.onKey path with a
// proper InputDispatcher.

import 'dart:async';

import 'package:meta/meta.dart';

import '../foundation/change_notifier.dart';
import '../foundation/geometry.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
import '../terminal/events.dart';
import 'framework.dart';
import 'inherited_notifier.dart';
import 'key_bindings.dart' show KeyBinding;

/// The result of handling a key event.
enum KeyEventResult {
  /// The handler consumed the event; the framework should not pass
  /// it to any other handler.
  handled,

  /// The handler did not consume the event; the framework should
  /// continue bubbling.
  ignored,
}

/// Signature for a key-event handler on a [Focus] or [FocusNode].
typedef FocusOnKeyCallback = KeyEventResult Function(KeyEvent event);

/// Marker interface for objects that contribute key bindings to the
/// active focus chain.
///
/// `KeyBindings` widgets implement this and attach themselves to a
/// `FocusNode.bindingSource`. The `InputDispatcher` and `KeyHintBar`
/// walk the focus chain and read `activeBindings` from each
/// non-null source.
///
/// The interface lives here (rather than in `key_bindings.dart`) so
/// that `FocusNode` can typed-reference it without creating a
/// circular import between the focus and bindings libraries.
abstract interface class KeyBindingSource {
  /// The bindings this source currently contributes. May change over
  /// time as the source rebuilds.
  List<KeyBinding> get activeBindings;
}

/// Marker interface for widgets that consume insertable text input
/// (e.g. `TextInput`).
///
/// The `InputDispatcher` walks the focus chain looking for the
/// nearest claimant; insertable events (`TextInputEvent` from the
/// parser) are delivered to it before any ancestor `KeyBindings`
/// gets a chance to see them. Modifier chords (`Ctrl+S`, `Alt+X`)
/// arrive as `KeyEvent`s instead and bypass the claimant entirely,
/// so they reach `KeyBindings` normally.
///
/// See RFC 0008 §6.7.
abstract interface class TextInputClaimant {
  /// Invoked by the dispatcher with insertable text. Return
  /// [KeyEventResult.handled] to consume it (the usual case — a text
  /// field appends it), or [KeyEventResult.ignored] to decline so the
  /// dispatcher offers it to the next claimant up the chain. Declining
  /// lets a non-text control claim just a single character (e.g. Space
  /// to toggle) while letting everything else pass.
  KeyEventResult onTextInput(String text);

  /// Invoked by the dispatcher with bracketed paste content. Paste is
  /// separated from typed text so editable fields can record one paste
  /// transaction, while controls that claim single typed trigger characters
  /// do not activate from pasted blobs.
  KeyEventResult onPaste(String text);
}

/// A long-lived focus identity. One per [Focus] widget; consumers can
/// also create their own and pass it into a `Focus` to keep focus
/// state stable across reparenting.
class FocusNode {
  FocusNode({
    bool canRequestFocus = true,
    bool skipTraversal = false,
    this.debugLabel,
  }) : _canRequestFocus = canRequestFocus,
       _skipTraversal = skipTraversal;

  bool _canRequestFocus;
  bool _skipTraversal;

  /// Optional human-readable label. Only surfaces in `toString`.
  final String? debugLabel;

  /// The currently registered key handler. Set by [Focus] when its
  /// `onKey` callback changes.
  FocusOnKeyCallback? onKey;

  FocusManager? _manager;
  Element? _element;
  FocusScopeRef? _enclosingScope;

  /// Optional source of `KeyBinding`s contributed by a `KeyBindings`
  /// widget. The `InputDispatcher` reads this to find bindings on each
  /// node of the focus chain. Null for `Focus` widgets that use
  /// `onKey` directly.
  KeyBindingSource? bindingSource;

  /// Optional consumer of insertable text input (a `TextInput`
  /// widget). The dispatcher delivers `TextInputEvent`s to the
  /// nearest claimant in the focus chain before any ancestor
  /// `KeyBindings` sees them.
  TextInputClaimant? textInputClaimant;

  /// Bounding rectangle of the focusable region in absolute cell
  /// coordinates, populated by the framework on every paint pass.
  /// Null until the node's owning `Focus` widget has been painted at
  /// least once.
  ///
  /// Used by `FocusTraversalGroup` to do directional traversal
  /// (left/right/up/down arrows move focus to the spatially nearest
  /// focusable). Don't write to this from app code.
  CellRect? rect;

  /// Whether this node can currently take focus.
  bool get canRequestFocus => _canRequestFocus;
  set canRequestFocus(bool value) {
    if (_canRequestFocus == value) return;
    _canRequestFocus = value;
    if (!value && hasFocus) _manager?.requestFocus(null);
  }

  /// Whether traversal (Tab cycling, etc.) should skip this node.
  // ignore: unnecessary_getters_setters
  bool get skipTraversal => _skipTraversal;
  // ignore: unnecessary_getters_setters
  set skipTraversal(bool value) => _skipTraversal = value;

  /// Whether this node is currently the focused node in its manager.
  bool get hasFocus => _manager?.focusedNode == this;

  /// Whether this node is attached to a [FocusManager].
  bool get isAttached => _manager != null;

  /// The [BuildContext] of the `Focus` that owns this node, or null when
  /// the node isn't attached. Mirrors Flutter's `FocusNode.context`; lets
  /// a widget ask whether focus sits within its subtree — see
  /// [FocusWithin].
  BuildContext? get context => _element;

  /// The nearest enclosing [FocusScope]'s reference, if any.
  FocusScopeRef? get enclosingScope => _enclosingScope;

  /// Asks the manager to make this node the focused node. No-op when
  /// [canRequestFocus] is false or this node is not attached.
  void requestFocus() {
    if (!_canRequestFocus) return;
    _manager?.requestFocus(this);
  }

  /// Removes focus from this node if it currently has focus.
  void unfocus() {
    if (hasFocus) _manager?.requestFocus(null);
  }

  /// Releases manager bookkeeping for this node. Call from
  /// `State.dispose` when you created the node manually.
  void dispose() {
    _manager?._unregister(this);
    _manager = null;
    _element = null;
    _enclosingScope = null;
    onKey = null;
    bindingSource = null;
    textInputClaimant = null;
    rect = null;
  }

  @override
  String toString() {
    final label = debugLabel ?? '#${identityHashCode(this).toRadixString(16)}';
    return 'FocusNode($label, focus=$hasFocus)';
  }
}

/// Identity object for a [FocusScope]. The scope itself stays out of
/// the public API; consumers interact with [FocusScope] the widget.
@immutable
class FocusScopeRef {
  const FocusScopeRef._(this.id, this.modal, this.suppressGlobals);
  final Object id;
  final bool modal;
  final bool suppressGlobals;

  @override
  String toString() =>
      'FocusScopeRef(id=$id, modal=$modal, suppressGlobals=$suppressGlobals)';
}

// ---------------------------------------------------------------------------
// FocusManager
// ---------------------------------------------------------------------------

/// Manages which [FocusNode] is currently focused for one runtime
/// (one [BuildOwner] / one [runTui]).
///
/// Listeners are notified when the focused node changes or when the
/// active focus chain composition shifts (e.g. modal scope opens /
/// closes above the focused node).
class FocusManager extends ChangeNotifier {
  FocusManager();

  FocusNode? _focusedNode;
  bool _disposed = false;

  /// The currently focused node, or null when nothing is focused.
  FocusNode? get focusedNode => _focusedNode;

  /// All currently attached nodes, in attachment order. Used by the
  /// dispatcher to find the autofocus candidate, etc.
  final List<FocusNode> _attachedNodes = <FocusNode>[];

  /// Currently mounted modal [_FocusScopeMarkerElement]s. Lets us name the
  /// active modal scope even when the focused node has detached (its widget
  /// rebuilt away) — without this set, traversal called against a null
  /// `_focusedNode` would treat the entire tree as in-scope and escape any
  /// open modal.
  ///
  /// Markers add themselves here only while their element-snapshotted
  /// `_capturedModal` is true, so the set is precisely the active modal
  /// frontier — never widget-level state that may be stale across a rebuild.
  final Set<_FocusScopeMarkerElement> _activeModalScopes =
      <_FocusScopeMarkerElement>{};
  final Set<_ExcludeFocusMarkerElement> _activeExcludeFocusMarkers =
      <_ExcludeFocusMarkerElement>{};

  void _registerModalScope(_FocusScopeMarkerElement element) {
    _checkNotDisposed();
    if (_activeModalScopes.add(element)) _notifyManagerScopeChanged();
  }

  void _unregisterModalScope(_FocusScopeMarkerElement element) {
    if (_disposed) return;
    if (_activeModalScopes.remove(element)) _notifyManagerScopeChanged();
  }

  void _registerExcludeFocus(_ExcludeFocusMarkerElement element) {
    _checkNotDisposed();
    if (_activeExcludeFocusMarkers.add(element)) _notifyManagerScopeChanged();
  }

  void _unregisterExcludeFocus(_ExcludeFocusMarkerElement element) {
    if (_disposed) return;
    if (_activeExcludeFocusMarkers.remove(element)) {
      _notifyManagerScopeChanged();
    }
  }

  /// Notifies listeners that the modal frontier (or a `suppressGlobals`
  /// flag on it) has changed. Deferred to a microtask so the notification
  /// never lands mid-build — a marker's `mount` / `update` runs inside a
  /// build phase, and `notifyListeners` there would re-enter `setState`
  /// on a dependent.
  void _notifyManagerScopeChanged() {
    if (_disposed) return;
    scheduleMicrotask(notifyListeners);
  }

  /// Read-only view of every node currently attached to this manager,
  /// in attachment order. `FocusTraversalGroup` uses this to find
  /// candidates for directional focus.
  Iterable<FocusNode> get attachedNodes => _attachedNodes;

  /// Whether [node] is currently traversable: it can take focus, isn't
  /// flagged `skipTraversal`, and sits under no active [ExcludeFocus].
  /// Both the Tab and the arrow-key policies consult this.
  bool isTraversable(FocusNode node) {
    if (node.skipTraversal) return false;
    return isClickable(node);
  }

  /// Whether [node] can take focus via mouse click: it can request focus
  /// and sits under no active [ExcludeFocus]. Wider than [isTraversable]
  /// — a node with `skipTraversal: true` (e.g. a Button) is still
  /// click-focusable but excluded from Tab/arrow cycling.
  @internal
  bool isClickable(FocusNode node) {
    if (!node.canRequestFocus) return false;
    if (_activeExcludeFocusMarkers.isEmpty) return true;
    Element? e = node._element?.elementParent;
    while (e != null) {
      if (e is _ExcludeFocusMarkerElement && e.excluding) return false;
      e = e.elementParent;
    }
    return true;
  }

  /// Attaches [node] to this manager. Idempotent.
  void _register(FocusNode node, Element element) {
    _checkNotDisposed();
    if (identical(node._manager, this)) return;
    node._manager = this;
    node._element = element;
    _attachedNodes.add(node);
  }

  /// Detaches [node] from this manager. Safe if not attached.
  void _unregister(FocusNode node) {
    if (!identical(node._manager, this)) return;
    if (_disposed) {
      node._manager = null;
      node._element = null;
      node._enclosingScope = null;
      return;
    }
    if (identical(_focusedNode, node)) {
      _focusedNode = null;
      notifyListeners();
    }
    _attachedNodes.remove(node);
  }

  /// Requests that [node] become the focused node (null to clear
  /// focus). Returns whether focus actually moved.
  bool requestFocus(FocusNode? node) {
    _checkNotDisposed();
    if (node != null && !node.canRequestFocus) return false;
    if (identical(_focusedNode, node)) return false;
    _focusedNode = node;
    notifyListeners();
    return true;
  }

  /// Moves focus to the next focusable node in reading order
  /// (top-to-bottom, then left-to-right), cycling at the end. Skips
  /// nodes that can't take focus or are flagged `skipTraversal`. Returns
  /// whether focus moved. This is the mechanism behind Tab traversal;
  /// the key bindings live in [FocusTraversalGroup].
  ///
  /// Reading order is derived from each node's painted `rect`, so it
  /// matches what the user sees regardless of mount order. When a modal
  /// [FocusScope] is active, traversal is confined to nodes inside it.
  bool focusNext() => _cycleFocus(forward: true);

  /// Moves focus to the previous focusable node in reading order,
  /// cycling at the start.
  bool focusPrevious() => _cycleFocus(forward: false);

  bool _cycleFocus({required bool forward}) {
    _checkNotDisposed();
    final order = _traversalOrder();
    if (order.isEmpty) return false;
    final current = _focusedNode;
    final i = current == null ? -1 : order.indexOf(current);
    final int next;
    if (i == -1) {
      next = forward ? 0 : order.length - 1;
    } else {
      next = (i + (forward ? 1 : -1)) % order.length;
    }
    return requestFocus(order[next]);
  }

  /// Focusable nodes in reading order (row, then column), with
  /// attachment order as a stable tiebreak and not-yet-painted nodes
  /// last. Filtered to the active modal scope when one is open — Tab
  /// inside a modal dialog cannot escape it.
  List<FocusNode> _traversalOrder() {
    final attachIndex = <FocusNode, int>{};
    for (var i = 0; i < _attachedNodes.length; i++) {
      attachIndex[_attachedNodes[i]] = i;
    }
    final modal = _innermostModalScopeElement(_focusedNode);
    final nodes = _attachedNodes
        .where(isTraversable)
        .where((n) => modal == null || _isUnderScopeMarker(n, modal))
        .toList();
    nodes.sort((a, b) {
      final ra = a.rect;
      final rb = b.rect;
      if (ra != null && rb != null) {
        if (ra.top != rb.top) return ra.top - rb.top;
        if (ra.left != rb.left) return ra.left - rb.left;
      } else if (ra == null && rb != null) {
        return 1;
      } else if (ra != null && rb == null) {
        return -1;
      }
      return attachIndex[a]! - attachIndex[b]!;
    });
    return nodes;
  }

  /// The innermost enclosing modal marker element of [node], or null
  /// when no modal scope is open above it. Mirrors the walk in
  /// [activeChain] but returns the modal anchor instead of stopping at it.
  /// `suppressGlobals` is deliberately ignored here — it gates global
  /// key bindings during dispatch, not traversal.
  ///
  /// Anchoring on the marker ELEMENT (rather than its widget-level
  /// [FocusScopeRef]) keeps identity stable across rebuilds: each
  /// `FocusScope.build` allocates a fresh `FocusScopeRef`, but the
  /// underlying `_FocusScopeMarkerElement` survives `update()`. Using
  /// scope-ref identity would silently treat every rebuild as a different
  /// modal and break `_isUnderScope`/`_activeModalScopes` invariants.
  ///
  /// When [node] is null, falls back to the deepest mounted modal scope
  /// in [_activeModalScopes] — programmatic `focusNext()` after a focused
  /// node detached must still respect any open modal.
  ///
  /// When [node] is non-null but its ancestor walk doesn't cross a modal
  /// marker (e.g. the focused node sits outside an opened modal because
  /// it was focused before the modal mounted), still fall back to the
  /// deepest active modal — the open modal should bound traversal even
  /// for stale focus.
  _FocusScopeMarkerElement? _innermostModalScopeElement(FocusNode? node) {
    if (node == null) return _deepestActiveModalScope();
    Element? element = node._element;
    while (element != null) {
      if (element is _FocusScopeMarkerElement && element._capturedModal) {
        return element;
      }
      element = element.elementParent;
    }
    // The node sits outside every modal. If one is open elsewhere in the
    // tree, traversal should still be confined to it.
    return _deepestActiveModalScope();
  }

  /// Deepest (by element depth) modal marker currently mounted, or null
  /// when no modal is open. Ties on depth are broken by `_mountSeq` —
  /// the later-mounted marker wins, mirroring "innermost / most recent
  /// modal owns input" without relying on Set iteration order.
  _FocusScopeMarkerElement? _deepestActiveModalScope() {
    if (_activeModalScopes.isEmpty) return null;
    _FocusScopeMarkerElement? best;
    for (final marker in _activeModalScopes) {
      if (best == null) {
        best = marker;
        continue;
      }
      if (marker.depth > best.depth) {
        best = marker;
      } else if (marker.depth == best.depth &&
          marker._mountSeq > best._mountSeq) {
        best = marker;
      }
    }
    return best;
  }

  /// Whether [node]'s element-tree ancestor chain crosses [marker]
  /// before reaching the root. Used to filter traversal candidates to
  /// those inside the currently-active modal. Compared by ELEMENT
  /// identity — `FocusScopeRef` is rebuilt on every `FocusScope.build`,
  /// the marker element is not.
  bool _isUnderScopeMarker(FocusNode node, _FocusScopeMarkerElement marker) {
    Element? element = node._element;
    while (element != null) {
      if (identical(element, marker)) return true;
      element = element.elementParent;
    }
    return false;
  }

  /// Whether [node] sits under the currently-active modal (when one is
  /// open) or always, when no modal is open. Used by the input
  /// dispatcher to scope click-to-focus to the modal frontier.
  @internal
  bool isUnderActiveModal(FocusNode node) {
    if (_activeModalScopes.isEmpty) return true;
    final modal = _deepestActiveModalScope();
    if (modal == null) return true;
    return _isUnderScopeMarker(node, modal);
  }

  /// Returns the candidate set [FocusTraversalGroup] should consider
  /// for directional (arrow) traversal: traversable, attached, under
  /// [scopeContext] when provided, and — when a modal scope is open —
  /// inside that scope.
  @internal
  Iterable<FocusNode> traversalCandidates({BuildContext? scopeContext}) {
    final modal = _innermostModalScopeElement(_focusedNode);
    final scopeElement = scopeContext is Element ? scopeContext : null;
    var base = _attachedNodes.where(isTraversable);
    if (modal != null) {
      base = base.where((n) => _isUnderScopeMarker(n, modal));
    }
    if (scopeElement != null) {
      base = base.where((n) => _isUnderElement(n, scopeElement));
    }
    return base;
  }

  bool _isUnderElement(FocusNode node, Element ancestor) {
    Element? element = node._element;
    while (element != null) {
      if (identical(element, ancestor)) return true;
      element = element.elementParent;
    }
    return false;
  }

  /// Returns the focus chain from [focusedNode] up to the root, in
  /// deepest-first order, by walking element parents.
  ///
  /// A modal [FocusScope] boundary stops the walk *as the walker
  /// crosses out of the scope*. Focus nodes *inside* the same modal
  /// scope as the focused node are included; focus nodes outside it
  /// are not. Without a modal scope, the walk continues to the
  /// element tree root.
  List<FocusNode> activeChain() {
    final focused = _focusedNode;
    if (focused == null) return _rootActiveChain();
    final chain = <FocusNode>[focused];
    var element = focused._element?.elementParent;
    while (element != null) {
      if (element is _FocusScopeMarkerElement && element.scope.modal) {
        // We're about to exit a modal scope. Stop — anything above
        // this marker is outside the modal.
        break;
      }
      if (element is _FocusElement) {
        chain.add(element.node);
      }
      element = element.elementParent;
    }
    return chain;
  }

  /// The key-dispatch chain to use when NOTHING is focused.
  ///
  /// A terminal is keyboard-primary, so key handling must work before
  /// anything claims focus — otherwise tree-level [KeyBindings] never
  /// fire and, worse, the very `FocusTraversalGroup` Tab binding that
  /// would let the user acquire focus is itself unreachable (a
  /// chicken-and-egg deadlock). Unlike a pointer-primary GUI, we can't
  /// just wait for a focusable to be clicked.
  ///
  /// So with no focused node we treat the ambient binding hosts in
  /// scope as active, ordered deepest-first to preserve the usual
  /// "innermost wins" dispatch precedence. When a modal scope is open,
  /// the chain is confined to it — an unfocused modal still traps input
  /// the same way a focused one would.
  ///
  /// Crucially this is limited to *non-focusable* nodes
  /// (`canRequestFocus == false`): ambient `KeyBindings` and the
  /// `FocusTraversalGroup` Tab host, whose chords are meant to be live
  /// whenever their subtree is in scope. Focusable interactive widgets
  /// (a `Checkbox`'s `Focus(onKey:)`, a `Button`, a text field) are
  /// deliberately excluded — their key handling is gated on holding
  /// focus, so an unfocused Checkbox must NOT toggle on Space. This is
  /// the line between "app/tree-level shortcut" and "this widget is the
  /// active control."
  List<FocusNode> _rootActiveChain() {
    final modal = _deepestActiveModalScope();
    final attachIndex = <FocusNode, int>{};
    for (var i = 0; i < _attachedNodes.length; i++) {
      attachIndex[_attachedNodes[i]] = i;
    }
    final nodes = _attachedNodes
        .where((n) => !n.canRequestFocus)
        .where((n) => n.bindingSource != null || n.onKey != null)
        .where((n) => modal == null || _isUnderScopeMarker(n, modal))
        .toList();
    // Deepest element first; attach order as a stable tiebreak. Mirrors
    // the focused-chain ordering, where the node nearest the focused
    // leaf is consulted before its ancestors.
    nodes.sort((a, b) {
      final da = a._element?.depth ?? -1;
      final db = b._element?.depth ?? -1;
      if (da != db) return db - da;
      return attachIndex[a]! - attachIndex[b]!;
    });
    return nodes;
  }

  /// Returns true if the currently active focus chain crosses a
  /// [FocusScope] whose `suppressGlobals` is true.
  ///
  /// When a modal is active, the value comes from the element-snapshotted
  /// `_capturedSuppressGlobals` on the deepest active modal marker — never
  /// from a live widget-level read. The marker captures the flag at
  /// `mount`/`update` time so a rebuild that flips `suppressGlobals` is
  /// observed without re-attaching anything.
  ///
  /// When no modal is active, falls back to the enclosing scope of the
  /// currently focused node — a non-modal `FocusScope(suppressGlobals: true)`
  /// (e.g. wrapping a text field that wants to swallow chord-like
  /// `KeyEvent`s) must still gate globals.
  bool get suppressGlobals {
    if (_activeModalScopes.isNotEmpty) {
      final modal = _deepestActiveModalScope();
      if (modal != null) return modal._capturedSuppressGlobals;
    }
    return _focusedNode?._enclosingScope?.suppressGlobals ?? false;
  }

  /// Delivers [event] to the active focus chain, calling each node's
  /// `onKey` in deepest-first order. Stops at the first handler that
  /// returns [KeyEventResult.handled] or at the chain's end.
  KeyEventResult dispatchKey(KeyEvent event) {
    _checkNotDisposed();
    for (final node in activeChain()) {
      final handler = node.onKey;
      if (handler == null) continue;
      final result = handler(event);
      if (result == KeyEventResult.handled) return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _focusedNode = null;
    for (final node in List<FocusNode>.of(_attachedNodes)) {
      if (identical(node._manager, this)) {
        node._manager = null;
        node._element = null;
        node._enclosingScope = null;
      }
    }
    _attachedNodes.clear();
    _activeModalScopes.clear();
    _activeExcludeFocusMarkers.clear();
    super.dispose();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('FocusManager has been disposed.');
    }
  }
}

/// Inherited handle that lets descendants reach the surrounding
/// [FocusManager] without threading it through constructors.
class _FocusManagerProvider extends InheritedNotifier<FocusManager> {
  const _FocusManagerProvider({
    required FocusManager manager,
    required super.child,
  }) : super(notifier: manager);

  static FocusManager of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<_FocusManagerProvider>();
    if (provider == null) {
      throw StateError(
        'No FocusManager found in this context. Did you call '
        'runTui (which installs one)?',
      );
    }
    return provider.notifier;
  }

  static FocusManager? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_FocusManagerProvider>()
        ?.notifier;
  }
}

/// Root of the focus tree. Installed by `runTui` so application widget
/// code can always reach a `FocusManager` via [Focus.of].
class FocusManagerScope extends StatelessWidget {
  const FocusManagerScope({
    super.key,
    required this.manager,
    required this.child,
  });

  final FocusManager manager;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _FocusManagerProvider(manager: manager, child: child);
  }
}

// ---------------------------------------------------------------------------
// Focus widget
// ---------------------------------------------------------------------------

/// A widget that wires a [FocusNode] into the tree.
///
/// In its simplest form: `Focus(autofocus: true, child: ...)`. Most
/// apps will move to `KeyBindings` (next slice) for the actual key
/// handling, but `Focus(onKey: ...)` is the supported low-level
/// escape hatch.
class Focus extends StatefulWidget {
  const Focus({
    super.key,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.skipTraversal = false,
    this.onKey,
    this.debugLabel,
    required this.child,
  });

  /// Optional caller-provided node. Useful for preserving focus state
  /// across rebuilds via a `State<T>` that holds the node.
  final FocusNode? focusNode;

  /// If true, this node requests focus on first mount when no node is
  /// currently focused.
  final bool autofocus;

  final bool canRequestFocus;
  final bool skipTraversal;
  final FocusOnKeyCallback? onKey;
  final String? debugLabel;
  final Widget child;

  @override
  State<Focus> createState() => _FocusState();

  /// Returns the surrounding [FocusManager]. Throws if not present.
  static FocusManager of(BuildContext context) =>
      _FocusManagerProvider.of(context);

  /// Returns the surrounding [FocusManager], or null if there isn't
  /// one.
  static FocusManager? maybeOf(BuildContext context) =>
      _FocusManagerProvider.maybeOf(context);

  @override
  StatefulElement createElement() => _FocusElement(this);
}

class _FocusElement extends StatefulElement {
  _FocusElement(Focus super.widget);

  /// The node this element is wiring up. Exposed so the manager can
  /// build the focus chain by walking element parents.
  FocusNode get node => (state as _FocusState)._node;
}

class _FocusState extends State<Focus> {
  FocusNode? _internalNode;
  FocusNode? _attachedNode;
  FocusManager? _manager;

  FocusNode get _node => widget.focusNode ?? _internalNode!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _internalNode = FocusNode(
        canRequestFocus: widget.canRequestFocus,
        skipTraversal: widget.skipTraversal,
        debugLabel: widget.debugLabel,
      );
    } else {
      // The user-provided node carries its own canRequestFocus and
      // skipTraversal — we don't override.
    }
    _node.onKey = widget.onKey;
  }

  @override
  void didUpdateWidget(Focus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _detach();
      _internalNode?.dispose();
      _internalNode = widget.focusNode == null
          ? FocusNode(
              canRequestFocus: widget.canRequestFocus,
              skipTraversal: widget.skipTraversal,
              debugLabel: widget.debugLabel,
            )
          : null;
      _node.onKey = widget.onKey;
      _attach();
    } else {
      _node.onKey = widget.onKey;
      if (widget.focusNode == null) {
        _node.canRequestFocus = widget.canRequestFocus;
        _node.skipTraversal = widget.skipTraversal;
      }
    }
  }

  @override
  void deactivate() {
    // Drop the manager registration while detached from the tree. If this is
    // a reparent (global key) the next build re-attaches at the new position
    // via the `_manager == null` check; if it's a permanent removal, dispose
    // follows and finds nothing left to detach. Unregistering here (rather
    // than waiting for dispose) keeps the focused-node bookkeeping correct
    // when an old subtree lingers in the inactive set while a replacement
    // mounts.
    _detach();
    super.deactivate();
  }

  @override
  void dispose() {
    _detach();
    _internalNode?.dispose();
    super.dispose();
  }

  void _attach() {
    final manager = Focus.maybeOf(context);
    if (manager == null) return;
    _manager = manager;
    _attachedNode = _node;
    manager._register(_node, context as Element);
    // Carry the nearest enclosing scope down.
    _node._enclosingScope = FocusScope._enclosingOf(context as Element);

    if (widget.autofocus &&
        manager.focusedNode == null &&
        manager.isTraversable(_node)) {
      _node.requestFocus();
    }
  }

  void _detach() {
    final node = _attachedNode;
    if (node != null) _manager?._unregister(node);
    _attachedNode = null;
    _manager = null;
  }

  @override
  Widget build(BuildContext context) {
    // Idempotent attach on first build — later than didChangeDependencies
    // so an ancestor FocusScope inserted between mount and build still
    // resolves into the freshly-walked `_enclosingScope`.
    if (_manager == null) _attach();
    return _FocusBounds(node: _node, child: widget.child);
  }
}

/// Wraps a child render subtree so its absolute paint position is
/// recorded on the associated [FocusNode] — required by
/// [FocusTraversalGroup] to do directional traversal.
class _FocusBounds extends SingleChildRenderObjectWidget {
  const _FocusBounds({required this.node, required Widget super.child});

  final FocusNode node;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderFocusBounds(node: node);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderFocusBounds renderObject,
  ) {
    renderObject.node = node;
  }
}

class _RenderFocusBounds extends RenderObject
    implements RenderObjectWithSingleChild {
  _RenderFocusBounds({required FocusNode node}) : _node = node;

  FocusNode _node;
  FocusNode get node => _node;
  set node(FocusNode value) {
    if (identical(_node, value)) return;
    // Releasing the old node — clear any rect we'd recorded so a
    // stale bounding box doesn't drive directional traversal.
    _node.rect = null;
    _node = value;
    markNeedsPaintOnly();
  }

  RenderObject? _child;
  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) {
      dropChild(_child!);
    }
    _child = value;
    if (value != null) {
      adoptChild(value);
    }
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final c = _child;
    if (c == null) return constraints.constrain(CellSize.zero);
    return c.layout(constraints);
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    _node.rect = CellRect(offset: offset, size: size);
    _child?.paint(
      buffer,
      offset,
      screenOffset: screenOffset ?? offset,
      clipRect: clipRect,
    );
  }
}

// ---------------------------------------------------------------------------
// FocusScope
// ---------------------------------------------------------------------------

/// A scope for focus operations. Children inside a `FocusScope` form
/// a traversal group; with `modal: true` the scope also stops events
/// from reaching `KeyBindings` (or `Focus.onKey`) above it.
///
/// Flutter divergence: `modal` is a first-class flag here that scopes
/// BOTH key dispatch AND Tab/arrow traversal in one place. Flutter
/// handles modal-like behaviour indirectly — via Navigator routes that
/// stack focus scopes, or via a custom `FocusTraversalPolicy`.
class FocusScope extends StatelessWidget {
  const FocusScope({
    super.key,
    this.modal = false,
    this.suppressGlobals = false,
    required this.child,
  });

  final bool modal;
  final bool suppressGlobals;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ref = FocusScopeRef._(this, modal, suppressGlobals);
    return _FocusScopeMarker(scope: ref, child: child);
  }

  /// Returns the nearest enclosing [FocusScopeRef] by walking the
  /// element tree. Used internally by [Focus] when it mounts.
  static FocusScopeRef? _enclosingOf(Element from) {
    Element? element = from.elementParent;
    while (element != null) {
      if (element is _FocusScopeMarkerElement) {
        return element.scope;
      }
      element = element.elementParent;
    }
    return null;
  }
}

class _FocusScopeMarker extends Widget {
  const _FocusScopeMarker({required this.scope, required this.child});
  final FocusScopeRef scope;
  final Widget child;

  @override
  Element createElement() => _FocusScopeMarkerElement(this);
}

class _FocusScopeMarkerElement extends ComponentElement {
  _FocusScopeMarkerElement(_FocusScopeMarker super.widget);

  /// Process-wide monotonic counter used as the modal tiebreaker — the
  /// later-mounted marker wins among equal-depth modals. Stable across
  /// rebuilds (mountSeq is set once, in `mount`).
  static int _nextMountSeq = 0;

  FocusScopeRef get scope => (widget as _FocusScopeMarker).scope;
  FocusManager? _registeredManager;

  /// Snapshot of `scope.modal` taken at mount and refreshed in `update`.
  /// We read this — not the live widget — to decide what's modal because
  /// `FocusScope.build` constructs a fresh `FocusScopeRef` on every
  /// rebuild; comparing widget identity across rebuilds would falsely
  /// claim the modal had changed.
  bool _capturedModal = false;

  /// Same idea as `_capturedModal` for `suppressGlobals` — refreshed on
  /// `update` so the dispatcher reads the new value on the next event,
  /// without the marker re-registering anything.
  bool _capturedSuppressGlobals = false;

  late final int _mountSeq;

  @override
  Widget buildChild() => (widget as _FocusScopeMarker).child;

  // Track modal markers on the manager so `_innermostModalScope` can name
  // the active modal even when no node holds focus. Idempotent on rebuild;
  // tied to lifecycle (mount/activate/deactivate/unmount) rather than
  // build so a temporarily-inactive subtree doesn't appear active.
  void _registerIfModal() {
    if (!_capturedModal) return;
    if (_registeredManager != null) return;
    // No dependency: this marker doesn't rebuild on manager changes — we
    // just need a reference to register against.
    final manager =
        getInheritedWidgetOfExactType<_FocusManagerProvider>()?.notifier;
    if (manager == null) return;
    manager._registerModalScope(this);
    _registeredManager = manager;
  }

  void _unregisterIfRegistered() {
    final manager = _registeredManager;
    if (manager == null) return;
    manager._unregisterModalScope(this);
    _registeredManager = null;
  }

  @override
  void mount(Element? parent) {
    // Capture BEFORE super.mount so `_registerIfModal` (called below) and
    // any same-frame queries see the snapshotted flags rather than racing
    // through `widget`.
    _mountSeq = _nextMountSeq++;
    _capturedModal = (widget as _FocusScopeMarker).scope.modal;
    _capturedSuppressGlobals =
        (widget as _FocusScopeMarker).scope.suppressGlobals;
    super.mount(parent);
    _registerIfModal();
  }

  @override
  void update(Widget newWidget) {
    super.update(newWidget);
    // Refresh the snapshotted flags. Identity on the underlying widget
    // changes every rebuild (FocusScope.build allocates a fresh
    // FocusScopeRef), so we can't compare widgets — we compare the
    // captured booleans.
    final newMarker = newWidget as _FocusScopeMarker;
    final newModal = newMarker.scope.modal;
    final newSuppress = newMarker.scope.suppressGlobals;
    if (newModal != _capturedModal) {
      _capturedModal = newModal;
      if (newModal) {
        _registerIfModal();
      } else {
        _unregisterIfRegistered();
      }
    }
    if (newSuppress != _capturedSuppressGlobals) {
      _capturedSuppressGlobals = newSuppress;
      // Manager iterates `_activeModalScopes` to compute `suppressGlobals`;
      // notify dependents so any cached value (e.g. a debug overlay) syncs.
      _registeredManager?._notifyManagerScopeChanged();
    }
  }

  @override
  void activate() {
    super.activate();
    _registerIfModal();
  }

  @override
  void deactivate() {
    _unregisterIfRegistered();
    super.deactivate();
  }

  @override
  void unmount() {
    _unregisterIfRegistered();
    super.unmount();
  }
}

// ---------------------------------------------------------------------------
// ExcludeFocus
// ---------------------------------------------------------------------------

/// Removes its subtree from focus traversal while [excluding] is true.
///
/// Descendant [Focus] nodes stay mounted — so their [State] (text,
/// scroll position, selection…) is preserved — but Tab/Shift+Tab and the
/// arrow-key policies skip them, and they won't claim autofocus. Toggling
/// [excluding] keeps the same subtree in place, so flipping it on and off
/// (as a tab is hidden and re-shown) never resets that state.
///
/// This is what lets an [IndexedStack] of pages keep every page alive
/// without letting the keyboard wander into the hidden ones.
class ExcludeFocus extends StatelessWidget {
  const ExcludeFocus({super.key, this.excluding = true, required this.child});

  /// Whether the subtree is currently excluded from traversal.
  final bool excluding;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      _ExcludeFocusMarker(excluding: excluding, child: child);
}

class _ExcludeFocusMarker extends Widget {
  const _ExcludeFocusMarker({required this.excluding, required this.child});
  final bool excluding;
  final Widget child;

  @override
  Element createElement() => _ExcludeFocusMarkerElement(this);
}

class _ExcludeFocusMarkerElement extends ComponentElement {
  _ExcludeFocusMarkerElement(_ExcludeFocusMarker super.widget);

  bool get excluding => (widget as _ExcludeFocusMarker).excluding;
  bool _capturedExcluding = false;
  FocusManager? _registeredManager;

  @override
  Widget buildChild() {
    _registerIfExcluding();
    return (widget as _ExcludeFocusMarker).child;
  }

  void _registerIfExcluding() {
    if (!_capturedExcluding) return;
    if (_registeredManager != null) return;
    final manager =
        getInheritedWidgetOfExactType<_FocusManagerProvider>()?.notifier;
    if (manager == null) return;
    manager._registerExcludeFocus(this);
    _registeredManager = manager;
  }

  void _unregisterIfRegistered() {
    final manager = _registeredManager;
    if (manager == null) return;
    manager._unregisterExcludeFocus(this);
    _registeredManager = null;
  }

  @override
  void mount(Element? parent) {
    _capturedExcluding = (widget as _ExcludeFocusMarker).excluding;
    super.mount(parent);
    _registerIfExcluding();
  }

  @override
  void update(Widget newWidget) {
    super.update(newWidget);
    final newExcluding = (newWidget as _ExcludeFocusMarker).excluding;
    if (newExcluding == _capturedExcluding) return;
    _capturedExcluding = newExcluding;
    if (newExcluding) {
      _registerIfExcluding();
    } else {
      _unregisterIfRegistered();
    }
  }

  @override
  void activate() {
    super.activate();
    _registerIfExcluding();
  }

  @override
  void deactivate() {
    _unregisterIfRegistered();
    super.deactivate();
  }

  @override
  void unmount() {
    _unregisterIfRegistered();
    super.unmount();
  }
}

// ---------------------------------------------------------------------------
// FocusWithin
// ---------------------------------------------------------------------------

/// Reports when keyboard focus enters or leaves its subtree.
///
/// [onFocusChange] fires with `true` when the focused node becomes this
/// subtree (or any descendant), and `false` when it leaves — the
/// descendant-inclusive focus signal that powers focus-reactive chrome:
/// a tooltip that appears while its target is focused, an active-pane
/// highlight, a section that styles itself when something inside has
/// focus. (For a rebuild, call `setState` from the callback.)
class FocusWithin extends StatefulWidget {
  const FocusWithin({
    super.key,
    required this.onFocusChange,
    required this.child,
  });

  final void Function(bool hasFocus) onFocusChange;
  final Widget child;

  @override
  State<FocusWithin> createState() => _FocusWithinState();
}

class _FocusWithinState extends State<FocusWithin> {
  FocusManager? _manager;
  bool _within = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final manager = Focus.maybeOf(context);
    if (!identical(manager, _manager)) {
      _manager?.removeListener(_onFocusChange);
      _manager = manager;
      _manager?.addListener(_onFocusChange);
    }
  }

  void _onFocusChange() {
    final within = _computeWithin();
    if (within == _within) return;
    _within = within;
    widget.onFocusChange(within);
  }

  /// Walks up from the focused node's context; focus is within us when
  /// our state is its nearest enclosing [FocusWithin] (so for nested
  /// FocusWithins the innermost one owns the focus).
  bool _computeWithin() {
    final ctx = _manager?.focusedNode?.context;
    if (ctx == null) return false;
    return identical(ctx.findAncestorStateOfType<_FocusWithinState>(), this);
  }

  @override
  void dispose() {
    _manager?.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
