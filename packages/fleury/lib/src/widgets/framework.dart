// Core widget framework: Widget, Element, State, BuildContext, BuildOwner.
//
// These classes are tightly coupled and share private state, so they live in
// a single file rather than being split into separate libraries with `part of`
// directives. The shape mirrors Flutter where it usefully can; the goal is
// "Flutter ergonomics, terminal truth," not a Flutter source-compatible port.
//
// What is in scope for this revision:
//   - Widget / StatelessWidget / StatefulWidget / State
//   - Element / ComponentElement / StatelessElement / StatefulElement
//   - RenderObjectWidget hierarchy (leaf + single-child + multi-child)
//   - ProxyWidget + InheritedWidget + InheritedElement
//   - Key-based reconciliation via Widget.canUpdate, plus GlobalKey
//   - setState() + didChangeDependencies + a synchronous-flush BuildOwner
//     + reassembleApplication
//
// What is not yet in scope:
//   - Frame scheduling beyond BuildOwner.flushBuild + onScheduleBuild

import 'package:meta/meta.dart';

import '../debug/debug_invalidation.dart';
import '../foundation/fleury_error.dart';
import '../foundation/geometry.dart';
import '../foundation/key.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_error_boundary.dart';
import '../rendering/render_object.dart';

/// Signature for `setState` and similar one-shot mutators.
typedef VoidCallback = void Function();

// ---------------------------------------------------------------------------
// Widget hierarchy
// ---------------------------------------------------------------------------

/// Immutable description of part of the terminal UI.
///
/// A widget never holds mutable runtime state. State lives on the
/// corresponding [Element] (and, for [StatefulWidget], on [State]).
@immutable
abstract class Widget {
  const Widget({this.key});

  final Key? key;

  /// Creates the [Element] that will mount this widget into the tree.
  Element createElement();

  /// Returns true if [newWidget] can replace [oldWidget] without rebuilding
  /// the underlying element. The framework calls this during reconciliation:
  /// matching `runtimeType` + `Key` means "reuse the element and its state";
  /// anything else means "unmount the old element and mount a fresh one."
  static bool canUpdate(Widget oldWidget, Widget newWidget) {
    return oldWidget.runtimeType == newWidget.runtimeType &&
        oldWidget.key == newWidget.key;
  }

  @override
  String toString() => key == null ? '$runtimeType' : '$runtimeType(key: $key)';
}

/// Internal opt-in for immutable widgets that can prove a new widget instance
/// would leave the mounted subtree unchanged.
///
/// The reconciler still requires [Widget.canUpdate] before consulting this
/// hook. Stateful widgets should not implement it unless they can also prove
/// skipping `didUpdateWidget` is correct.
@internal
abstract interface class WidgetUpdatePruner {
  bool hasEquivalentWidgetConfiguration(Widget other);
}

@internal
bool canSkipWidgetUpdate(Widget oldWidget, Widget newWidget) {
  if (identical(oldWidget, newWidget)) return true;
  if (!Widget.canUpdate(oldWidget, newWidget)) return false;
  final pruner = oldWidget;
  if (pruner is! WidgetUpdatePruner) return false;
  return (pruner as WidgetUpdatePruner).hasEquivalentWidgetConfiguration(
    newWidget,
  );
}

@internal
bool canSkipNullableWidgetUpdate(Widget? oldWidget, Widget? newWidget) {
  if (oldWidget == null || newWidget == null) return oldWidget == newWidget;
  return canSkipWidgetUpdate(oldWidget, newWidget);
}

/// A [Key] unique across the whole tree, indexing the element that
/// currently carries it. Use it to reach a mounted widget's state or
/// context imperatively from outside the build — e.g. to call a method on
/// a `State`, or to capture a `BuildContext` for an overlay:
///
/// ```dart
/// final formKey = GlobalKey<MyFormState>();
/// ...
/// MyForm(key: formKey);
/// // elsewhere:
/// formKey.currentState?.submit();
/// ```
///
/// Equality is identity, so each instance is its own key. A global-keyed
/// widget that moves to a different parent in the same build is *reparented*
/// — its [Element], [State], and render subtree are relocated intact rather
/// than torn down and rebuilt — so its state survives the move. The same key
/// must identify at most one widget mounted at a time.
class GlobalKey<T extends State<StatefulWidget>> extends Key {
  GlobalKey() : super.empty();

  static final Map<GlobalKey, Element> _registry = <GlobalKey, Element>{};

  Element? get _element => _registry[this];

  /// The [BuildContext] of the element carrying this key, or null if it
  /// isn't currently mounted.
  BuildContext? get currentContext => _element;

  /// The widget at this key, or null if not mounted.
  Widget? get currentWidget => _element?._widget;

  /// The [State] of the (stateful) element at this key, cast to [T], or
  /// null if not mounted or the state isn't a [T].
  T? get currentState {
    final element = _element;
    if (element is StatefulElement) {
      final state = element.state;
      if (state is T) return state;
    }
    return null;
  }

  void _register(Element element) {
    assert(() {
      final existing = _registry[this];
      if (existing != null &&
          !identical(existing, element) &&
          existing._lifecycle == _ElementLifecycle.active) {
        throw StateError(
          'Duplicate GlobalKey detected: the same $runtimeType is attached to '
          'two simultaneously-mounted widgets '
          '(${existing.toStringShallow()} and ${element.toStringShallow()}). '
          'Each GlobalKey instance may identify at most one widget at a time.',
        );
      }
      return true;
    }());
    _registry[this] = element;
  }

  void _deregister(Element element) {
    if (identical(_registry[this], element)) _registry.remove(this);
  }
}

/// A widget whose appearance depends only on its configuration.
abstract class StatelessWidget extends Widget {
  const StatelessWidget({super.key});

  @override
  StatelessElement createElement() => StatelessElement(this);

  /// Describes the part of the user interface represented by this widget.
  Widget build(BuildContext context);
}

/// A widget whose appearance depends on configuration plus retained
/// mutable state held by a separate [State] object.
abstract class StatefulWidget extends Widget {
  const StatefulWidget({super.key});

  @override
  StatefulElement createElement() => StatefulElement(this);

  /// Creates the mutable state for this widget at the current location in
  /// the tree. Called exactly once per [StatefulElement] instance.
  State createState();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Mutable state for a [StatefulWidget].
///
/// The framework owns the [State]'s lifecycle: [initState] runs when the
/// state is first mounted, [didUpdateWidget] runs when the framework
/// re-renders the parent and the matching widget instance changes,
/// [dispose] runs when the state is unmounted for good.
abstract class State<T extends StatefulWidget> {
  StatefulElement? _element;
  StatefulWidget? _widget;

  /// The current widget configuration for this state.
  T get widget {
    final w = _widget;
    if (w == null) {
      throw StateError(
        'State.widget accessed before initState or after dispose.',
      );
    }
    return w as T;
  }

  /// The build context for this state.
  BuildContext get context {
    final e = _element;
    if (e == null) {
      throw StateError(
        'State.context accessed before initState or after dispose.',
      );
    }
    return e;
  }

  /// Whether this state object is currently in a tree.
  bool get mounted => _element != null;

  /// Called when the framework first inserts this state into the tree.
  @protected
  @mustCallSuper
  void initState() {}

  /// Called when the framework replaces the widget configuration with a
  /// new instance of the same `runtimeType` and `Key`.
  @protected
  @mustCallSuper
  void didUpdateWidget(covariant T oldWidget) {}

  /// Tracks whether any inherited dependency (or `initState`) has
  /// invalidated the dependency snapshot since the last
  /// [didChangeDependencies] call. The framework uses this to decide
  /// whether [didChangeDependencies] needs to fire before the next
  /// build. Starts true so the very first build after `initState` is
  /// preceded by a `didChangeDependencies` call.
  bool _dependenciesChanged = true;

  /// Called before [build] when one of three things is true:
  ///
  ///   - This is the first build after [initState].
  ///   - An [InheritedWidget] this state depends on (via
  ///     `context.dependOnInheritedWidgetOfExactType`) just notified
  ///     dependents (via swap or `notifyDependents`).
  ///
  /// State subclasses override this to re-read inherited values and
  /// update derived state. Notable example:
  /// `SingleTickerProviderStateMixin` overrides this to sync its
  /// `Ticker.muted` against the enclosing `TickerMode`.
  ///
  /// Does NOT fire after a plain `setState` — only after dependency
  /// changes. This is the same contract as Flutter's
  /// `didChangeDependencies`.
  @protected
  @mustCallSuper
  void didChangeDependencies() {}

  /// Schedules a rebuild for this state's element.
  ///
  /// The callback runs synchronously so callers can mutate state inside it
  /// before the rebuild is enqueued.
  @protected
  void setState(VoidCallback fn) {
    final element = _element;
    if (element == null) {
      throw StateError(
        'setState called on $runtimeType after the state was disposed.',
      );
    }
    fn();
    element.markNeedsBuild();
  }

  /// Called when this state's element is removed from the tree, either
  /// permanently (followed by [dispose]) or temporarily — when a widget
  /// with a [GlobalKey] is moved to a new parent in the same build, the
  /// element is deactivated here and reactivated via [activate] once the
  /// new parent claims it.
  ///
  /// Override to release resources that must not outlive the element's
  /// current tree position (e.g. unregister from a service), pairing the
  /// teardown with [activate]. The default is a no-op.
  @protected
  @mustCallSuper
  void deactivate() {}

  /// Called when this state's element is reinserted into the tree after a
  /// [deactivate] — i.e. a global-keyed widget was reparented rather than
  /// destroyed. The framework rebuilds the element after this returns, so
  /// there is no need to call [setState]. The default is a no-op.
  @protected
  @mustCallSuper
  void activate() {}

  /// Called when the framework removes this state from the tree.
  @protected
  @mustCallSuper
  void dispose() {}

  /// Called by [BuildOwner.reassembleApplication] when the application is
  /// being reassembled (e.g. after a successful VM hot reload).
  ///
  /// The default is a no-op. Subclasses override to clear caches, reset
  /// derived state, or reinitialize anything that should re-derive from
  /// freshly-reloaded code. The framework will mark this element dirty
  /// and rebuild it after this method returns, so there is no need to
  /// call `setState` from here.
  @protected
  void reassemble() {}

  /// Describes the part of the user interface represented by this state.
  Widget build(BuildContext context);

  // ---- Internal bridges ---------------------------------------------------

  /// Bridges between an [Element]'s untyped update path and the
  /// [didUpdateWidget] hook, which is `covariant T`. Called by
  /// [StatefulElement.update].
  void _bridgeDidUpdateWidget(StatefulWidget oldWidget) {
    // The reconciler only calls update() when runtimeType matches, so the
    // cast is safe by construction.
    didUpdateWidget(oldWidget as T);
  }
}

// ---------------------------------------------------------------------------
// BuildContext
// ---------------------------------------------------------------------------

/// A handle to the location of a widget in the element tree.
abstract interface class BuildContext {
  /// The widget currently mounted at this location.
  Widget get widget;

  /// True while the underlying element is in the tree.
  bool get mounted;

  /// Registers this context as a dependent of the nearest ancestor
  /// `InheritedWidget` of type [T] and returns that widget. The
  /// element will rebuild whenever that ancestor's
  /// [InheritedWidget.updateShouldNotify] returns true.
  ///
  /// Returns null if no matching ancestor exists.
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>();

  /// Like [dependOnInheritedWidgetOfExactType] but does not establish
  /// a dependency. Use this when reading the widget for the lifetime
  /// of one build call only and not caring about future updates.
  T? getInheritedWidgetOfExactType<T extends InheritedWidget>();

  /// Walks ancestors looking for an [Element] whose state is of type
  /// [T]. Does not establish a dependency.
  T? findAncestorStateOfType<T extends State>();

  /// Walks down through component elements until a render-object
  /// element is found, returning that render object (or null when this
  /// context isn't mounted or has no render-object descendant). Does
  /// not establish a dependency.
  ///
  /// May return null or stale geometry if called mid-build; use after
  /// layout (e.g. from a [TuiBinding.addPostFrameCallback]) to read the
  /// painted `size`/`offset` the user just saw.
  RenderObject? findRenderObject();
}

// ---------------------------------------------------------------------------
// Element hierarchy
// ---------------------------------------------------------------------------

enum _ElementLifecycle { initial, active, inactive, defunct }

/// A non-widget source of rebuilds an [Element] can depend on.
///
/// Implemented by things outside the widget tree that an element's
/// `build` reads and should rebuild on — notably `Animation`, whose
/// `value` getter registers the building element here. The framework
/// stays decoupled from the animation layer: it only knows it has
/// some dependencies to detach on unmount.
abstract interface class ElementDependency {
  /// Records [element] as depending on this source.
  void addDependent(Element element);

  /// Drops a previously-recorded dependent.
  void removeDependent(Element element);
}

/// Mounted instance of a [Widget] with stable identity across rebuilds.
abstract class Element implements BuildContext {
  Element(Widget widget) : _widget = widget;

  /// The element whose `build` is currently running, or null when no
  /// build is in progress. Read by [ElementDependency] sources (e.g.
  /// `Animation.value`) to auto-subscribe the building element. Maintained
  /// as a stack via [runWithBuildTarget] so nested builds attribute
  /// correctly.
  static Element? get current => _current;
  static Element? _current;

  /// Runs [fn] with this element as the active build target ([current]),
  /// so [ElementDependency] sources read inside auto-subscribe it. Restores
  /// the previous target on the way out (stack discipline for nested
  /// builds). For any element that invokes a build callback — including
  /// outside the build phase (e.g. a layout-time builder).
  @protected
  T runWithBuildTarget<T>(T Function() fn) {
    final previous = _current;
    _current = this;
    try {
      return fn();
    } finally {
      _current = previous;
    }
  }

  // Error-boundary hooks (errorBuilder / onBuildError) live on BuildOwner,
  // not as Element statics — installed per-runtime so a test harness and a
  // production host don't share a global. See BuildOwner.

  Widget _widget;
  @override
  Widget get widget => _widget;

  Element? _parent;
  BuildOwner? _owner;
  int _depth = 0;
  _ElementLifecycle _lifecycle = _ElementLifecycle.initial;
  bool _dirty = true;

  /// The element this one was mounted under, or null for the root.
  Element? get elementParent => _parent;

  BuildOwner get owner {
    final o = _owner;
    if (o == null) {
      throw StateError('Element has no owner (not yet mounted).');
    }
    return o;
  }

  int get depth => _depth;
  bool get dirty => _dirty;

  @override
  bool get mounted => _lifecycle == _ElementLifecycle.active;

  /// Inserts this element into the tree at the given parent.
  @mustCallSuper
  void mount(Element? parent) {
    assert(_lifecycle == _ElementLifecycle.initial, 'mount called twice.');
    _parent = parent;
    _depth = parent == null ? 0 : parent._depth + 1;
    _owner ??= parent?._owner;
    _lifecycle = _ElementLifecycle.active;
    final key = _widget.key;
    if (key is GlobalKey) key._register(this);
  }

  /// Removes this element from the tree permanently.
  @mustCallSuper
  void unmount() {
    final key = _widget.key;
    if (key is GlobalKey) key._deregister(this);
    visitChildren(_unmountRecursively);
    _detachDependencies();
    _lifecycle = _ElementLifecycle.defunct;
    _owner?._dirtyElements.remove(this);
    _parent = null;
  }

  /// Drops every dependency edge this element holds — both inherited
  /// ([dependOnInheritedWidgetOfExactType]) and external (e.g. `Animation`).
  /// Shared by [unmount] (permanent) and [deactivate] (temporary; the next
  /// rebuild re-establishes whatever the new tree position warrants).
  void _detachDependencies() {
    for (final ancestor in _inheritedDependencies) {
      ancestor._dependents.remove(this);
    }
    _inheritedDependencies.clear();
    for (final dep in _externalDependencies) {
      dep.removeDependent(this);
    }
    _externalDependencies.clear();
  }

  /// Detaches this element from its current parent without destroying it,
  /// holding the (now inactive) subtree in [BuildOwner._inactiveElements].
  ///
  /// Render objects of the subtree are detached from the ancestor render
  /// object as a unit (the subtree's internal render links stay intact, so
  /// it can be reattached elsewhere wholesale). Dependency edges are
  /// dropped; the dirty bit is preserved so a pending rebuild survives the
  /// move. If the element is reclaimed by a new parent before the end of
  /// the build (see [inflateWidget]) it is reactivated; otherwise
  /// [BuildOwner._finalizeInactiveElements] unmounts it for good.
  void _deactivateChild(Element child) {
    // Detach render objects first: detachRenderObject re-walks the parent
    // chain to find the ancestor render object, so the link must still be
    // intact when it runs.
    child.detachRenderObject();
    child._parent = null;
    child._deactivateRecursively();
    _owner?._inactiveElements.add(child);
  }

  void _deactivateRecursively() {
    _deactivate();
    visitChildren((c) => c._deactivateRecursively());
  }

  /// Whether the element held dependency edges when it was deactivated.
  /// Consumed by [_activate]: those edges were dropped on the OLD tree
  /// position and only a rebuild re-registers them — see [_detachDependencies].
  bool _hadDependenciesWhenDeactivated = false;

  @mustCallSuper
  void _deactivate() {
    assert(_lifecycle == _ElementLifecycle.active);
    _hadDependenciesWhenDeactivated =
        _inheritedDependencies.isNotEmpty || _externalDependencies.isNotEmpty;
    _detachDependencies();
    _owner?._dirtyElements.remove(this);
    _lifecycle = _ElementLifecycle.inactive;
    deactivate();
  }

  /// Reinserts a previously [_deactivateChild]'d element under [this] at the
  /// given new tree position: re-parents it, recomputes depths, flips the
  /// subtree back to active, and reattaches its render objects to the new
  /// ancestor render object.
  void _activateWithParent(Element parent) {
    _parent = parent;
    _owner = parent._owner;
    _updateDepthRecursively(parent._depth + 1);
    _activateRecursively();
    attachRenderObject();
  }

  void _updateDepthRecursively(int newDepth) {
    _depth = newDepth;
    visitChildren((c) => c._updateDepthRecursively(newDepth + 1));
  }

  void _activateRecursively() {
    _activate();
    visitChildren((c) => c._activateRecursively());
  }

  @mustCallSuper
  void _activate() {
    assert(_lifecycle == _ElementLifecycle.inactive);
    _lifecycle = _ElementLifecycle.active;
    // A rebuild that was pending when the subtree was deactivated still
    // needs to run; re-enqueue it. The element's own `update` (driven by
    // the reclaiming parent) handles the move-induced rebuild.
    if (_dirty) _owner?.scheduleBuildFor(this);
    // Deactivation dropped this element's dependency edges; only a rebuild
    // re-registers them against the NEW tree position. When the reclaiming
    // parent delivers an IDENTICAL widget, update() skips that rebuild —
    // force it, or the element stays permanently deaf to the inherited /
    // external values it reads (Flutter's activate() likewise calls
    // didChangeDependencies()).
    if (_hadDependenciesWhenDeactivated) {
      _hadDependenciesWhenDeactivated = false;
      markNeedsBuild();
    }
    activate();
  }

  /// Subclass hook mirroring [State.deactivate]; the default is a no-op.
  @protected
  @mustCallSuper
  void deactivate() {}

  /// Subclass hook mirroring [State.activate]; the default is a no-op.
  @protected
  @mustCallSuper
  void activate() {}

  /// Detaches the render objects at the top of this subtree from the
  /// ancestor render object. The default walks down through child elements;
  /// [RenderObjectElement] overrides it to detach its own render object and
  /// stop (the subtree below that render object travels with it).
  void detachRenderObject() {
    visitChildren((c) => c.detachRenderObject());
  }

  /// Reattaches the render objects at the top of this subtree to the
  /// nearest ancestor render object. Inverse of [detachRenderObject].
  void attachRenderObject() {
    visitChildren((c) => c.attachRenderObject());
  }

  /// Called on this element's current parent when the element is being
  /// reclaimed by a different parent (via a [GlobalKey] move) while still
  /// active. The parent drops its reference so it won't later try to update
  /// or unmount a child that has moved away. The default is a no-op (leaf
  /// elements hold no children); container elements override it.
  @protected
  void forgetChild(Element child) {}

  // Ancestors this element has registered with via
  // [dependOnInheritedWidgetOfExactType]. Cleared on unmount.
  final Set<InheritedElement> _inheritedDependencies = <InheritedElement>{};

  // Non-widget dependencies (e.g. Animation) read during build. Detached
  // on unmount so the source stops marking this element dirty.
  final Set<ElementDependency> _externalDependencies = <ElementDependency>{};

  /// Registers [dependency] as something this element's build read,
  /// so it rebuilds when the dependency changes and detaches on
  /// unmount. Idempotent. Called by [ElementDependency] sources.
  void dependOnExternal(ElementDependency dependency) {
    if (_externalDependencies.add(dependency)) {
      dependency.addDependent(this);
    }
  }

  @override
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>() {
    final ancestor = _findInheritedElementOfExactType<T>();
    if (ancestor == null) return null;
    ancestor._dependents.add(this);
    _inheritedDependencies.add(ancestor);
    return ancestor.widget as T;
  }

  @override
  T? getInheritedWidgetOfExactType<T extends InheritedWidget>() {
    return _findInheritedElementOfExactType<T>()?.widget as T?;
  }

  @override
  T? findAncestorStateOfType<T extends State>() {
    var element = _parent;
    while (element != null) {
      if (element is StatefulElement && element._state is T) {
        return element._state as T?;
      }
      element = element._parent;
    }
    return null;
  }

  @override
  RenderObject? findRenderObject() {
    // A deactivated / unmounted element points at render objects whose
    // geometry is either stale or about to be torn down — surface null
    // instead of leaking a dangling reference.
    if (_lifecycle != _ElementLifecycle.active) return null;
    return _owner?.findRootRenderObject(this);
  }

  InheritedElement?
  _findInheritedElementOfExactType<T extends InheritedWidget>() {
    var element = _parent;
    while (element != null) {
      if (element is InheritedElement && element.widget is T) {
        return element;
      }
      element = element._parent;
    }
    return null;
  }

  static void _unmountRecursively(Element child) {
    child.unmount();
  }

  /// Replaces the widget configuration backing this element.
  ///
  /// Only called by the framework after [Widget.canUpdate] returned true.
  @mustCallSuper
  void update(covariant Widget newWidget) {
    assert(
      Widget.canUpdate(_widget, newWidget),
      'Element.update called with an incompatible widget.',
    );
    _widget = newWidget;
  }

  /// Marks this element as needing a rebuild on the next flush.
  void markNeedsBuild() {
    if (_lifecycle != _ElementLifecycle.active) return;
    if (_dirty) return;
    _dirty = true;
    DebugInvalidations.recordBuild(_debugInvalidationLabel);
    _owner?.scheduleBuildFor(this);
  }

  /// Performs a rebuild if the element is dirty.
  ///
  /// The dirty bit is cleared BEFORE [performRebuild] runs, not
  /// after. This matters when the rebuild itself triggers a
  /// `markNeedsBuild` on this element (e.g. a descendant widget
  /// mounts and an inherited dependency fires a notification that
  /// targets this element). Clearing before performRebuild ensures
  /// the markNeedsBuild correctly re-adds this element to the dirty
  /// queue rather than short-circuiting on the still-set flag —
  /// matches Flutter's contract for setState-during-build.
  void rebuild({bool force = false}) {
    if (_lifecycle != _ElementLifecycle.active) return;
    if (!force && !_dirty) return;
    _dirty = false;
    _owner?._dirtyElements.remove(this);
    performRebuild();
  }

  /// Subclasses do the actual rebuild work here. The framework clears the
  /// dirty bit BEFORE calling this method.
  @protected
  void performRebuild();

  /// Visits each direct child element.
  void visitChildren(void Function(Element child) visitor);

  /// One-line description of this element. Includes runtime type, the
  /// widget runtime type, and the key when present.
  String toStringShallow() {
    final widget = _widget;
    final keyPart = widget.key != null ? ', key: ${widget.key}' : '';
    return '$runtimeType(widget: ${widget.runtimeType}$keyPart)';
  }

  String get _debugInvalidationLabel {
    if (this is StatefulElement) {
      final state = (this as StatefulElement).state;
      return '${_widget.runtimeType}/${state.runtimeType}';
    }
    return _widget.runtimeType.toString();
  }

  /// Multi-line indented dump of this subtree, one element per line.
  /// Intended for test failure messages — not for runtime logging.
  String toStringDeep([String prefix = '']) {
    final out = StringBuffer()
      ..write(prefix)
      ..writeln(toStringShallow());
    visitChildren((child) {
      out.write(child.toStringDeep('$prefix  '));
    });
    return out.toString();
  }

  /// Reconciles a single child slot.
  ///
  /// - Null new widget + null existing child: no-op.
  /// - Null new widget + existing child: deactivate child, return null.
  /// - New widget + no existing child: inflate new element.
  /// - New widget + existing child of compatible type+key: update in place.
  /// - New widget + existing child of different type/key: deactivate old,
  ///   inflate new.
  @protected
  Element? updateChild(Element? child, Widget? newWidget) {
    if (newWidget == null) {
      if (child != null) {
        _deactivateChild(child);
      }
      return null;
    }
    if (child != null) {
      if (canSkipWidgetUpdate(child._widget, newWidget)) {
        return child;
      }
      if (Widget.canUpdate(child._widget, newWidget)) {
        child.update(newWidget);
        return child;
      }
      _deactivateChild(child);
    }
    return inflateWidget(newWidget);
  }

  /// Creates an element for [newWidget] and mounts it under [this].
  ///
  /// If [newWidget] carries a [GlobalKey] whose element is available for
  /// reuse — either deactivated this build pass or still active under
  /// another parent — that element is reclaimed (preserving its [State]
  /// and render subtree) and reactivated here instead of being rebuilt
  /// from scratch. This is what makes a global-keyed widget *move* between
  /// parents rather than rebuild.
  @protected
  Element inflateWidget(Widget newWidget) {
    final key = newWidget.key;
    if (key is GlobalKey) {
      assert(_owner?._debugClaimGlobalKey(key, this) ?? true);
      final retaken = _retakeInactiveElement(key, newWidget);
      if (retaken != null) {
        _activateChild(retaken, newWidget);
        return retaken;
      }
    }
    final newChild = newWidget.createElement();
    newChild._owner = _owner;
    newChild.mount(this);
    return newChild;
  }

  void _activateChild(Element child, Widget newWidget) {
    child._activateWithParent(this);
    child.update(newWidget);
  }

  /// Looks up the element registered for [key] and, if it can host
  /// [newWidget], readies it for reuse under a new parent. If the element
  /// is still active under its old parent, that parent is told to forget
  /// it and to deactivate it first. Returns null when there is no reusable
  /// element (none registered, or the widget can't update it).
  Element? _retakeInactiveElement(GlobalKey key, Widget newWidget) {
    final element = key._element;
    if (element == null) return null;
    if (!Widget.canUpdate(element._widget, newWidget)) return null;
    final parent = element._parent;
    if (parent != null) {
      parent.forgetChild(element);
      parent._deactivateChild(element);
    }
    _owner?._inactiveElements.remove(element);
    return element;
  }

  @override
  String toString() => '${_widget.runtimeType}#$hashCode';
}

/// Base for elements that produce a single child by invoking some `build`
/// callback. Used by [StatelessElement] and [StatefulElement].
abstract class ComponentElement extends Element {
  ComponentElement(super.widget);

  Element? _child;

  /// The element below this one in the tree, if any.
  Element? get child => _child;

  @override
  void mount(Element? parent) {
    super.mount(parent);
    _firstBuild();
  }

  void _firstBuild() {
    // Route through rebuild() so the dirty bit is cleared and the element is
    // removed from any owner queue. Calling performRebuild directly here
    // would leave _dirty == true after mount, and the next markNeedsBuild
    // would short-circuit on the "already dirty" guard.
    rebuild();
  }

  @override
  void performRebuild() {
    // Build with this element as the active target so ElementDependency
    // sources (e.g. Animation.value) read during buildChild auto-subscribe
    // it; runWithBuildTarget restores before the catch/updateChild so the
    // error builder and children attribute their own reads.
    Widget? built;
    try {
      built = runWithBuildTarget(buildChild);
    } catch (error, stack) {
      // runWithBuildTarget already restored [current] on its way out of the
      // throw; report + substitute through the per-owner error hooks.
      final owner = _owner;
      owner?.onBuildError?.call(error, stack);
      final builder = owner?.errorBuilder;
      if (builder == null) rethrow; // no boundary installed → propagate
      built = builder(error, stack);
    }
    _child = updateChild(_child, built);
  }

  /// Subclasses produce the child widget here.
  @protected
  Widget buildChild();

  @override
  void visitChildren(void Function(Element child) visitor) {
    final c = _child;
    if (c != null) visitor(c);
  }

  @override
  void forgetChild(Element child) {
    assert(identical(child, _child));
    _child = null;
  }
}

/// Element for a [StatelessWidget].
class StatelessElement extends ComponentElement {
  StatelessElement(StatelessWidget super.widget);

  @override
  StatelessWidget get widget => super.widget as StatelessWidget;

  @override
  void update(covariant StatelessWidget newWidget) {
    super.update(newWidget);
    rebuild(force: true);
  }

  @override
  Widget buildChild() => widget.build(this);
}

/// Element for a [StatefulWidget].
class StatefulElement extends ComponentElement {
  StatefulElement(StatefulWidget widget)
    : _state = widget.createState(),
      super(widget) {
    _state._element = this;
    _state._widget = widget;
  }

  final State _state;

  /// The state object backing this element.
  State get state => _state;

  @override
  StatefulWidget get widget => super.widget as StatefulWidget;

  @override
  void _firstBuild() {
    _state.initState();
    super._firstBuild();
  }

  @override
  void update(covariant StatefulWidget newWidget) {
    final oldWidget = widget;
    super.update(newWidget);
    _state._widget = newWidget;
    _state._bridgeDidUpdateWidget(oldWidget);
    rebuild(force: true);
  }

  @override
  Widget buildChild() {
    // Fire didChangeDependencies before the first build of any
    // rebuild cycle where dependencies changed (initState start
    // case, or an inherited dependency notified). NOT fired for
    // plain setState rebuilds — that contract matches Flutter and
    // lets State subclasses do expensive dependency-change work
    // without paying for every setState.
    if (_state._dependenciesChanged) {
      _state.didChangeDependencies();
      _state._dependenciesChanged = false;
    }
    return _state.build(this);
  }

  @override
  void deactivate() {
    _state.deactivate();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _state.activate();
    // The subtree moved; inherited values may differ at the new position.
    // Force a didChangeDependencies before the post-move rebuild, matching
    // the contract on first mount.
    _state._dependenciesChanged = true;
  }

  @override
  void unmount() {
    super.unmount();
    _state.dispose();
    _state._element = null;
    _state._widget = null;
  }
}

// ---------------------------------------------------------------------------
// BuildOwner
// ---------------------------------------------------------------------------

/// Counts produced by one [BuildOwner.flushBuild] call.
final class BuildFlushStats {
  const BuildFlushStats({
    required this.passCount,
    required this.rebuiltElementCount,
    required this.maxDirtyElementCount,
  });

  static const zero = BuildFlushStats(
    passCount: 0,
    rebuiltElementCount: 0,
    maxDirtyElementCount: 0,
  );

  /// Number of dirty-queue passes needed to settle the build.
  final int passCount;

  /// Number of dirty element entries processed across all passes.
  final int rebuiltElementCount;

  /// Largest dirty-queue snapshot processed in any pass.
  final int maxDirtyElementCount;
}

/// Drives the build pipeline. Holds the set of dirty elements and flushes
/// them in shallow-first order.
/// Convergence cap for [BuildOwner.flushBuild]: legitimate cascades settle
/// in a handful of passes; hundreds means a self-dirtying loop.
const int _maxBuildPasses = 512;

class BuildOwner {
  BuildOwner({this.errorBuilder, this.onBuildError});

  /// Builds the widget shown in place of a subtree whose `build` threw, so
  /// the catch in [ComponentElement.performRebuild] renders an error panel
  /// instead of crashing. Null means "no boundary" — errors propagate (the
  /// raw-owner default; [TuiRuntime] and the test harness install
  /// `ErrorWidget.builder`). Per-owner, not process-global: two runtimes in
  /// one isolate never share a boundary, and a host cannot forget to
  /// install one.
  Widget Function(Object error, StackTrace stack)? errorBuilder;

  /// Optional sink for build errors (logging/telemetry). Called before the
  /// error widget is substituted.
  void Function(Object error, StackTrace stack)? onBuildError;

  /// Containment policy for layout/paint exceptions absorbed by
  /// [ErrorBoundary] render objects (explicit or the implicit route/
  /// overlay boundaries). False in production hosts — contain and render
  /// the error presentation; FleuryTester sets true so a widget test with
  /// a layout bug fails the test instead of silently rendering a panel.
  bool rethrowContainedRenderErrors = false;

  /// Sink for newly contained layout/paint failures (once per error-state
  /// entry). Hosts wire this to their error reporter so a contained panel
  /// still lands in stderr/the debug banner.
  void Function(FrameContainmentError error)? onContainedRenderError;

  /// Per-runtime frame damage signal for this owner's render tree.
  ///
  /// [renderFrame] attaches it at the root render object, where layout and
  /// conservative-paint invalidation walks publish. Owning it here (rather
  /// than as global static state) keeps two Fleury runtimes in one isolate
  /// fully isolated and lets deferred consumers accumulate damage across
  /// frames until they take it.
  final RenderDamageTracker renderDamageTracker = RenderDamageTracker();

  final Set<Element> _dirtyElements = <Element>{};

  /// Roots of subtrees detached this build pass (via [Element._deactivateChild])
  /// but not yet permanently removed. Each either gets reclaimed by a new
  /// parent during the same [flushBuild] (a global-keyed move) or is
  /// unmounted by [_finalizeInactiveElements] once the pass settles.
  final Set<Element> _inactiveElements = <Element>{};

  /// Debug-only: the parent that first inflated each [GlobalKey] during the
  /// current build pass, used to detect a key reused on two widgets at once.
  /// Reset at the start of every [flushBuild]; populated solely from asserts,
  /// so it stays empty in release builds.
  final Map<GlobalKey, Element> _debugGlobalKeyClaims = <GlobalKey, Element>{};

  bool _debugClaimGlobalKey(GlobalKey key, Element parent) {
    final existing = _debugGlobalKeyClaims[key];
    if (existing != null) {
      throw StateError(
        'Duplicate GlobalKey detected in the widget tree.\n'
        'The same $key was used to inflate two widgets in one build pass '
        '(under ${existing.toStringShallow()} and '
        '${parent.toStringShallow()}). A GlobalKey instance may identify at '
        'most one widget at a time; give the second widget its own key.',
      );
    }
    _debugGlobalKeyClaims[key] = parent;
    return true;
  }

  Element? _root;

  /// Invoked by [scheduleBuildFor] when the dirty queue transitions from
  /// empty to non-empty. Runtimes (e.g. `runApp`) set this so they can
  /// schedule a render after `setState` without polling.
  void Function()? onScheduleBuild;

  /// The root element this owner manages, if [mountRoot] has been called.
  Element? get root => _root;

  /// Mounts [widget] as the root of the tree managed by this owner and
  /// flushes any rebuilds it triggers.
  Element mountRoot(Widget widget) {
    final element = widget.createElement();
    element._owner = this;
    element.mount(null);
    _root = element;
    flushBuild();
    return element;
  }

  /// Replaces the root widget while preserving the [Element] subtree when
  /// `runtimeType` + `Key` match. Returns the current root element, which is
  /// either [root] for a compatible update or a freshly mounted element after
  /// an incompatible root replacement.
  Element updateRoot(Element root, Widget newRoot) {
    if (!identical(root, _root)) {
      throw StateError(
        'BuildOwner.updateRoot called with an element that is not the current '
        'root.',
      );
    }
    if (Widget.canUpdate(root.widget, newRoot)) {
      root.update(newRoot);
      flushBuild();
      return root;
    }
    root.unmount();
    _root = null;
    return mountRoot(newRoot);
  }

  /// Whether any element is waiting to rebuild.
  bool get hasScheduledBuilds => _dirtyElements.isNotEmpty;

  void scheduleBuildFor(Element element) {
    final wasEmpty = _dirtyElements.isEmpty;
    _dirtyElements.add(element);
    if (wasEmpty) onScheduleBuild?.call();
  }

  /// Rebuilds every dirty element. Shallowest elements are processed first
  /// so a parent rebuild that re-mounts children doesn't trigger redundant
  /// work on those (now-discarded) children.
  ///
  /// Implementation: snapshot the dirty set, sort by depth (ascending),
  /// then iterate. If new dirty elements appear during iteration (e.g.
  /// a rebuild calls setState on a sibling), the outer while loop picks
  /// them up on the next pass. This is O(n log n) per pass vs. the
  /// previous O(n²) find-min scan; matters when n is large
  /// (`reassembleApplication`, dense state updates). For typical
  /// `setState` with n=1–5 the difference is below measurement noise.
  ///
  /// See RFC 0009 §5.6 H6.
  BuildFlushStats flushBuild() {
    assert(() {
      _debugGlobalKeyClaims.clear();
      return true;
    }());
    var passCount = 0;
    var rebuiltElementCount = 0;
    var maxDirtyElementCount = 0;
    while (_dirtyElements.isNotEmpty) {
      if (passCount >= _maxBuildPasses) {
        // A rebuild storm: some widget re-dirties itself (or a partner)
        // every pass, so the flush would never converge. Fail loudly and
        // name the culprits — a silent hang is the one outcome worse than
        // a crash here. The throw surfaces through the frame program's
        // containment like any other render-phase failure.
        final culprits =
            (_dirtyElements.toList()..sort((a, b) => a._depth - b._depth))
                .take(8)
                .map((e) => e.widget.runtimeType.toString())
                .join(', ');
        _dirtyElements.clear();
        throw FleuryError(
          summary: 'flushBuild did not converge after $_maxBuildPasses passes.',
          details:
              'Every pass produced newly dirty elements, so the build would '
              'loop forever. Still dirty (shallowest first): $culprits.',
          hint:
              'Look for setState called unconditionally during build, or '
              'two widgets that mark each other dirty every frame.',
        );
      }
      final snapshot = _dirtyElements.toList()
        ..sort((a, b) => a._depth - b._depth);
      _dirtyElements.clear();
      passCount += 1;
      rebuiltElementCount += snapshot.length;
      if (snapshot.length > maxDirtyElementCount) {
        maxDirtyElementCount = snapshot.length;
      }
      for (final element in snapshot) {
        element.rebuild();
      }
    }
    _finalizeInactiveElements();
    if (passCount == 0) return BuildFlushStats.zero;
    return BuildFlushStats(
      passCount: passCount,
      rebuiltElementCount: rebuiltElementCount,
      maxDirtyElementCount: maxDirtyElementCount,
    );
  }

  /// Permanently unmounts every subtree that was deactivated during the
  /// build pass and not reclaimed by a new parent. Reclaimed elements were
  /// pulled from [_inactiveElements] by [Element._retakeInactiveElement], so
  /// whatever remains is genuinely gone.
  void _finalizeInactiveElements() {
    if (_inactiveElements.isEmpty) return;
    final toUnmount = _inactiveElements.toList();
    _inactiveElements.clear();
    for (final element in toUnmount) {
      element.unmount();
    }
  }

  /// Reassembles the entire element tree, calling [State.reassemble] on
  /// every [StatefulElement]'s state and marking every element dirty so
  /// the next [flushBuild] re-invokes every `build` method.
  ///
  /// Designed to be called from a hot-reload handler. The Dart VM
  /// preserves the heap across `reloadSources`, so existing [Element]
  /// and [State] instances survive — what changes is the *code* their
  /// `build`, `initState`, etc. methods dispatch to. Walking the tree
  /// and rebuilding every element invokes the freshly-loaded code while
  /// preserving the state object identities and field values.
  ///
  /// The walk also marks every element dirty (not just the root) so
  /// subtrees that would otherwise be skipped by the parent's
  /// identity-check short-circuit during reconciliation still get
  /// rebuilt and pick up the new code.
  void reassembleApplication() {
    final root = _root;
    if (root == null) {
      throw StateError(
        'BuildOwner.reassembleApplication called before mountRoot.',
      );
    }
    _walkAndReassemble(root);
    flushBuild();
  }

  void _walkAndReassemble(Element element) {
    if (element is StatefulElement) {
      element.state.reassemble();
    }
    element.markNeedsBuild();
    element.visitChildren(_walkAndReassemble);
  }

  /// Returns the root [RenderObject] of [element]'s subtree.
  ///
  /// Walks down through `ComponentElement`s (Stateless/Stateful) until a
  /// `RenderObjectElement` is found. The root widget tree must contain at
  /// least one render object somewhere or this returns null.
  ///
  /// Skips defunct descendants — an unmounted element holds no live
  /// render object and would assert if probed. Inactive (mid-activate)
  /// elements are still walked: a global-keyed widget moving between
  /// parents is briefly inactive but legitimately findable.
  RenderObject? findRootRenderObject(Element element) {
    if (element is RenderObjectElement) return element.renderObject;
    RenderObject? result;
    element.visitChildren((child) {
      if (child._lifecycle == _ElementLifecycle.defunct) return;
      result ??= findRootRenderObject(child);
    });
    return result;
  }

  /// Drives a single frame end-to-end: flushes pending builds, runs the
  /// layout pass against [size], and paints into [buffer]. Returns the
  /// root render object for inspection in tests.
  ///
  /// [onPhaseTiming] is invoked once with the build / layout / paint
  /// durations when supplied. Used by `runApp` to feed the debug
  /// overlay's frame timeline; tests / `FleuryTester` omit it.
  RenderObject renderFrame(
    Element root,
    CellBuffer buffer, {
    void Function(Duration build, Duration layout, Duration paint)?
    onPhaseTiming,
    void Function(BuildFlushStats stats)? onBuildStats,
  }) {
    final sw = onPhaseTiming != null ? (Stopwatch()..start()) : null;
    final buildStats = flushBuild();
    final buildElapsed = sw?.elapsed ?? Duration.zero;
    onBuildStats?.call(buildStats);

    final rootRender = findRootRenderObject(root);
    if (rootRender == null) {
      throw StateError(
        'BuildOwner.renderFrame: root element ${root.widget.runtimeType} '
        'produced no render object.',
      );
    }
    if (rootRender.attachFrameDamageTracker(renderDamageTracker)) {
      // A root this owner has not driven before: invalidations recorded while
      // its subtree was built detached never reached the tracker, so start
      // the frame with conservative damage.
      renderDamageTracker.recordLayoutOrConservativePaint();
    }
    // Loose constraints at root: the root widget chooses its own size up
    // to the buffer's dimensions. Anything it doesn't claim stays empty.
    // (Flutter passes tight constraints to the root because Scaffold/
    // MaterialApp expands to fill; we don't have that wrapper yet and
    // forcing it would break the "small widget at root" common case.)
    sw?.reset();
    rootRender.layout(CellConstraints.loose(buffer.size));
    final layoutElapsed = sw?.elapsed ?? Duration.zero;

    sw?.reset();
    // Root paint: buffer IS the screen, so screenOffset == offset.
    // clipRect == the full screen rect — anything outside is off-screen.
    rootRender.paint(
      buffer,
      CellOffset.zero,
      screenOffset: CellOffset.zero,
      clipRect: CellRect(offset: CellOffset.zero, size: buffer.size),
    );
    final paintElapsed = sw?.elapsed ?? Duration.zero;

    onPhaseTiming?.call(buildElapsed, layoutElapsed, paintElapsed);
    return rootRender;
  }
}

// ---------------------------------------------------------------------------
// RenderObjectWidget hierarchy
// ---------------------------------------------------------------------------

/// Base for widgets that produce a [RenderObject] and participate in the
/// layout / paint passes.
abstract class RenderObjectWidget extends Widget {
  const RenderObjectWidget({super.key});

  /// Creates the render object backing this widget. Called once when the
  /// element first mounts.
  RenderObject createRenderObject(BuildContext context);

  /// Applies any changes from a new widget instance to the existing
  /// render object. Default is a no-op; subclasses override when the
  /// widget carries layout/paint configuration.
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {}
}

/// A render-object widget with no children.
abstract class LeafRenderObjectWidget extends RenderObjectWidget {
  const LeafRenderObjectWidget({super.key});

  @override
  LeafRenderObjectElement createElement() => LeafRenderObjectElement(this);
}

/// A render-object widget that wraps exactly one child.
abstract class SingleChildRenderObjectWidget extends RenderObjectWidget {
  const SingleChildRenderObjectWidget({super.key, this.child});

  final Widget? child;

  @override
  SingleChildRenderObjectElement createElement() =>
      SingleChildRenderObjectElement(this);
}

/// A render-object widget that holds an ordered list of children.
abstract class MultiChildRenderObjectWidget extends RenderObjectWidget {
  const MultiChildRenderObjectWidget({super.key, this.children = const []});

  final List<Widget> children;

  @override
  MultiChildRenderObjectElement createElement() =>
      MultiChildRenderObjectElement(this);
}

// ---------------------------------------------------------------------------
// RenderObjectElement hierarchy
// ---------------------------------------------------------------------------

/// Base for elements that own a [RenderObject].
abstract class RenderObjectElement extends Element {
  RenderObjectElement(RenderObjectWidget super.widget);

  RenderObject? _renderObject;

  /// The render object created by this element.
  RenderObject get renderObject {
    final r = _renderObject;
    if (r == null) {
      throw StateError('$runtimeType has no render object (not mounted).');
    }
    return r;
  }

  @override
  RenderObjectWidget get widget => super.widget as RenderObjectWidget;

  @override
  void mount(Element? parent) {
    super.mount(parent);
    _renderObject = widget.createRenderObject(this);
    _attachRenderObjectToAncestor();
    // Route the first build through rebuild() so the dirty bit is cleared
    // and so subclasses with widget children (Single/MultiChild) actually
    // get a chance to mount them. Leaf subclasses no-op in performRebuild.
    rebuild();
  }

  @override
  void update(covariant RenderObjectWidget newWidget) {
    super.update(newWidget);
    newWidget.updateRenderObject(this, _renderObject!);
    // Render-object setters own their invalidation. Keeping that decision at
    // the setter is what lets audited paint-only updates avoid relayout while
    // layout-affecting setters still call markNeedsLayout or the conservative
    // markNeedsPaint compatibility path.
    rebuild(force: true);
  }

  @override
  void unmount() {
    _detachRenderObjectFromAncestor();
    super.unmount();
    _renderObject = null;
  }

  // A render object element's render object is the boundary of a movable
  // subtree: detaching/attaching the top render object relocates everything
  // below it as a unit, so neither override recurses into child elements.
  @override
  void detachRenderObject() {
    _detachRenderObjectFromAncestor();
  }

  @override
  void attachRenderObject() {
    _attachRenderObjectToAncestor();
  }

  /// Walks up the element tree looking for the nearest ancestor that owns
  /// a render object and asks it to adopt this element's render object.
  void _attachRenderObjectToAncestor() {
    final ancestor = _findAncestorRenderObjectElement();
    if (ancestor != null) {
      ancestor.insertChildRenderObject(_renderObject!, this);
    }
  }

  void _detachRenderObjectFromAncestor() {
    final ancestor = _findAncestorRenderObjectElement();
    if (ancestor != null) {
      ancestor.removeChildRenderObject(_renderObject!);
    }
  }

  RenderObjectElement? _findAncestorRenderObjectElement() {
    Element? e = _parent;
    while (e != null && e is! RenderObjectElement) {
      e = e._parent;
    }
    return e as RenderObjectElement?;
  }

  /// Subclasses that hold children override this to install [child] into
  /// their own render object. Default throws; leaves don't hold children.
  @protected
  void insertChildRenderObject(
    RenderObject child,
    RenderObjectElement element,
  ) {
    throw UnsupportedError('$runtimeType cannot hold a child render object.');
  }

  @protected
  void removeChildRenderObject(RenderObject child) {
    throw UnsupportedError('$runtimeType cannot remove a child render object.');
  }
}

/// Element for a [LeafRenderObjectWidget].
class LeafRenderObjectElement extends RenderObjectElement {
  LeafRenderObjectElement(LeafRenderObjectWidget super.widget);

  @override
  void performRebuild() {
    // Leaf render objects have no widget children to reconcile.
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
    // Leaf.
  }
}

/// Element for a [MultiChildRenderObjectWidget].
///
/// Owns an ordered list of child elements and reconciles them on every
/// rebuild. Reconciliation strategy:
///
/// 1. Build a map of `Key -> old element` for keyed olds.
/// 2. Maintain a queue of unkeyed olds in their original order.
/// 3. For each new widget at position `i`:
///    - If the widget has a key, look it up in the map. If found and
///      compatible (`Widget.canUpdate`), reuse and update in place. The
///      keyed old's state survives a reorder.
///    - Otherwise, take the next unkeyed old from the queue. If
///      compatible, reuse and update. If not, unmount it and try the
///      next. If the queue empties, inflate a fresh element.
/// 4. Unmount any remaining keyed olds (in the map) and any leftover
///    unkeyed olds in the queue.
/// 5. Sync the render-object children list to match the new element
///    order.
///
/// This is the simpler form of the Flutter reconciliation algorithm —
/// it's O(n) and correct. The forward/backward stable-prefix walks that
/// optimize Flutter's algorithm for "only the middle changed" patterns
/// can be added later if profiling demands it.
class MultiChildRenderObjectElement extends RenderObjectElement {
  MultiChildRenderObjectElement(MultiChildRenderObjectWidget super.widget);

  List<Element> _children = const <Element>[];

  /// The current ordered list of mounted child elements.
  List<Element> get childElements => List.unmodifiable(_children);

  @override
  MultiChildRenderObjectWidget get widget =>
      super.widget as MultiChildRenderObjectWidget;

  @override
  void performRebuild() {
    _children = _reconcileChildren(_children, widget.children);
    _syncChildRenderObjects();
  }

  List<Element> _reconcileChildren(
    List<Element> oldChildren,
    List<Widget> newWidgets,
  ) {
    final stableUnkeyed = _reconcileStableUnkeyedChildren(
      oldChildren,
      newWidgets,
    );
    if (stableUnkeyed != null) return stableUnkeyed;

    final result = List<Element?>.filled(newWidgets.length, null);

    // Partition the old children into keyed (by-key) and unkeyed (queue).
    final keyedOlds = <Key, Element>{};
    final unkeyedOlds = <Element>[];
    for (final old in oldChildren) {
      final k = old.widget.key;
      if (k != null) {
        keyedOlds[k] = old;
      } else {
        unkeyedOlds.add(old);
      }
    }

    var unkeyedIndex = 0;
    for (var i = 0; i < newWidgets.length; i++) {
      final newWidget = newWidgets[i];
      final newKey = newWidget.key;
      Element? matched;

      if (newKey != null) {
        final candidate = keyedOlds.remove(newKey);
        if (candidate != null) {
          if (Widget.canUpdate(candidate.widget, newWidget)) {
            matched = candidate;
          } else {
            _deactivateChild(candidate);
          }
        }
      } else {
        // Walk the unkeyed queue until we find a compatible old.
        while (unkeyedIndex < unkeyedOlds.length) {
          final candidate = unkeyedOlds[unkeyedIndex];
          unkeyedIndex += 1;
          if (Widget.canUpdate(candidate.widget, newWidget)) {
            matched = candidate;
            break;
          } else {
            _deactivateChild(candidate);
          }
        }
      }

      if (matched != null) {
        // Same identical-instance skip updateChild and the stable-unkeyed
        // fast path apply: without it, a keyed child whose widget instance
        // didn't change deep-rebuilds anyway — and its State receives a
        // didUpdateWidget where oldWidget is IDENTICAL to widget (a contract
        // violation) — on every pass that reaches this path (e.g. the
        // re-reconcile scheduled by insertChildRenderObject after a mount).
        if (!canSkipWidgetUpdate(matched.widget, newWidget)) {
          matched.update(newWidget);
        }
        result[i] = matched;
      } else {
        result[i] = inflateWidget(newWidget);
      }
    }

    // Deactivate leftover olds (finalized at the end of the build pass
    // unless a global-keyed one is reclaimed elsewhere first).
    for (final el in keyedOlds.values) {
      _deactivateChild(el);
    }
    while (unkeyedIndex < unkeyedOlds.length) {
      _deactivateChild(unkeyedOlds[unkeyedIndex]);
      unkeyedIndex += 1;
    }

    return result.cast<Element>();
  }

  List<Element>? _reconcileStableUnkeyedChildren(
    List<Element> oldChildren,
    List<Widget> newWidgets,
  ) {
    if (oldChildren.length != newWidgets.length) return null;
    if (oldChildren.isEmpty) return oldChildren;

    for (var index = 0; index < oldChildren.length; index++) {
      final oldChild = oldChildren[index];
      final newWidget = newWidgets[index];
      if (oldChild.widget.key != null || newWidget.key != null) return null;
      if (!Widget.canUpdate(oldChild.widget, newWidget)) return null;
    }

    // Common steady-state path for dense rows/grids: all children are
    // unkeyed, positional, and compatible. Avoid building keyed maps and
    // unkeyed queues; render-object order is still checked by the caller
    // because component children can change their internal render root.
    for (var index = 0; index < oldChildren.length; index++) {
      final child = oldChildren[index];
      final newWidget = newWidgets[index];
      if (!canSkipWidgetUpdate(child.widget, newWidget)) {
        child.update(newWidget);
      }
    }
    return oldChildren;
  }

  /// Walks each child element looking for its first descendant render
  /// object and assembles the list to install on this element's render
  /// object via [RenderObjectWithChildren.replaceAllChildren].
  void _syncChildRenderObjects() {
    final desired = <RenderObject>[];
    for (final c in _children) {
      final r = _findFirstRenderObject(c);
      if (r != null) desired.add(r);
    }
    final owner = renderObject as RenderObjectWithChildren;
    // `replaceAllChildren` already no-ops when the child order is unchanged —
    // it runs `hasSameRenderChildrenInOrder` against its own internal list,
    // with no copy. An element-level pre-check here would only duplicate that
    // scan and, because the `children` getter returns `List.unmodifiable`
    // (which copies the whole child list), pay an O(children) copy on every
    // rebuild of every multi-child element. Call through directly instead.
    owner.replaceAllChildren(desired);
  }

  static RenderObject? _findFirstRenderObject(Element element) {
    if (element is RenderObjectElement) return element.renderObject;
    RenderObject? found;
    element.visitChildren((child) {
      found ??= _findFirstRenderObject(child);
    });
    return found;
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
    for (final c in _children) {
      visitor(c);
    }
  }

  @override
  void forgetChild(Element child) {
    _children = _children.where((c) => !identical(c, child)).toList();
  }

  @override
  void insertChildRenderObject(
    RenderObject child,
    RenderObjectElement element,
  ) {
    // When THIS element rebuilds, performRebuild installs children in order
    // via _syncChildRenderObjects and this hook fires for already-installed
    // render objects (the identical-guard below no-ops). But an attach can
    // also arrive from a DESCENDANT rebuilding alone — a leaf dependent
    // (notifyDependents / setState below) swapping its subtree's render
    // object while this element never rebuilds. Ignoring that attach
    // silently dropped the new render object: the old one was eagerly
    // removed by removeChildRenderObject and nothing ever installed the
    // replacement, so the child simply vanished from the screen.
    //
    // Append eagerly so the render object is attached within this frame,
    // then mark this element dirty: our own performRebuild re-syncs the
    // order from the (by then updated) element children in the SAME
    // flushBuild pass loop, correcting the append position if the child
    // belongs between existing siblings. Sibling widgets are identical
    // instances (this element's widget didn't change), so the re-run is
    // skip-cheap.
    final ro = renderObject as RenderObjectWithChildren;
    if (ro.children.any((c) => identical(c, child))) return;
    ro.replaceAllChildren([...ro.children, child]);
    markNeedsBuild();
  }

  @override
  void removeChildRenderObject(RenderObject child) {
    // Drop the render object eagerly rather than waiting for the next
    // _syncChildRenderObjects. This matters when a global-keyed child is
    // reparented and the *new* parent reattaches (adopts) the render object
    // before this (old) parent gets a chance to re-sync — the adopt would
    // otherwise assert on a still-parented render object.
    final ro = renderObject as RenderObjectWithChildren;
    if (ro.children.any((c) => identical(c, child))) {
      ro.replaceAllChildren(
        ro.children.where((c) => !identical(c, child)).toList(),
      );
    }
  }
}

/// Element for a [SingleChildRenderObjectWidget].
class SingleChildRenderObjectElement extends RenderObjectElement {
  SingleChildRenderObjectElement(SingleChildRenderObjectWidget super.widget);

  Element? _child;

  /// The single child element below this one.
  Element? get child => _child;

  @override
  SingleChildRenderObjectWidget get widget =>
      super.widget as SingleChildRenderObjectWidget;

  @override
  void performRebuild() {
    _child = updateChild(_child, widget.child);
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
    final c = _child;
    if (c != null) visitor(c);
  }

  @override
  void forgetChild(Element child) {
    assert(identical(child, _child));
    _child = null;
  }

  @override
  void insertChildRenderObject(
    RenderObject child,
    RenderObjectElement element,
  ) {
    (renderObject as RenderObjectWithSingleChild).child = child;
  }

  @override
  void removeChildRenderObject(RenderObject child) {
    final r = renderObject as RenderObjectWithSingleChild;
    if (identical(r.child, child)) {
      r.child = null;
    }
  }
}

// ---------------------------------------------------------------------------
// ProxyWidget + InheritedWidget
// ---------------------------------------------------------------------------

/// A widget that proxies a single child without affecting layout or
/// painting. Used as the base for widgets whose only purpose is to
/// inject something into the tree (`InheritedWidget` data, future
/// notifier propagation, etc.).
abstract class ProxyWidget extends Widget {
  const ProxyWidget({super.key, required this.child});

  final Widget child;
}

/// Base class for widgets that expose data to descendants without that
/// data being passed down through constructors.
///
/// Descendants that read this widget via
/// `BuildContext.dependOnInheritedWidgetOfExactType<T>()` are
/// rebuilt whenever the framework swaps this widget for a new
/// instance whose [updateShouldNotify] returns true.
abstract class InheritedWidget extends ProxyWidget {
  const InheritedWidget({super.key, required super.child});

  /// Returns true if a dependent should rebuild when this widget
  /// replaces [oldWidget]. Compare the data fields that consumers
  /// actually depend on.
  bool updateShouldNotify(covariant InheritedWidget oldWidget);

  @override
  InheritedElement createElement() => InheritedElement(this);
}

/// Element for an [InheritedWidget].
///
/// Tracks the set of dependent elements that have registered via
/// `dependOnInheritedWidgetOfExactType`. On update, if
/// [InheritedWidget.updateShouldNotify] returns true, every dependent
/// is marked dirty.
class InheritedElement extends ComponentElement {
  InheritedElement(InheritedWidget super.widget);

  final Set<Element> _dependents = <Element>{};

  @override
  InheritedWidget get widget => super.widget as InheritedWidget;

  @override
  Widget buildChild() => widget.child;

  @override
  void update(covariant InheritedWidget newWidget) {
    final oldWidget = widget;
    super.update(newWidget);
    if (newWidget.updateShouldNotify(oldWidget)) {
      for (final dependent in _dependents) {
        _markDependencyChanged(dependent);
        dependent.markNeedsBuild();
      }
    }
    rebuild(force: true);
  }

  /// Notifies all dependents that this inherited element's effective
  /// state has changed. Used by `InheritedNotifier` to broadcast a
  /// listener notification without swapping widget instances.
  void notifyDependents() {
    for (final dependent in _dependents) {
      _markDependencyChanged(dependent);
      dependent.markNeedsBuild();
    }
  }

  /// Sets `_dependenciesChanged` on the dependent's State (if any)
  /// so `didChangeDependencies` fires before its next build. No-op
  /// for non-stateful dependents — they don't have the hook.
  static void _markDependencyChanged(Element dependent) {
    if (dependent is StatefulElement) {
      dependent._state._dependenciesChanged = true;
    }
  }
}
