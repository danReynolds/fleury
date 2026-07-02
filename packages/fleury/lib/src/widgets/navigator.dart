// Navigator: an imperative, type-safe screen stack — a first-class part
// of the framework, not a wrapper over the ambient Overlay.
//
//   final picked = await context.push<File>(FilePicker(dir: d));
//   context.pop(chosenFile);     // completes the push future
//   context.maybePop();          // Esc/back pops if not at the root
//
// Architecture
//
//   - Self-contained layout. A Navigator renders its OWN stack of routes
//     into its OWN layout slot via [RenderNavigatorStack] — it does not
//     borrow the app's root Overlay. That makes a Navigator embeddable
//     anywhere: at the app root (filling the terminal) or nested inside
//     a panel/split/box, scoped to whatever constraints its parent gives
//     it. Nested navigators "just work."
//
//   - Nesting + context scoping. Each Navigator wraps its routes in a
//     [_NavigatorScope] inherited widget. `Navigator.of(context)` finds
//     the nearest enclosing navigator (the one whose region the calling
//     widget lives in); `Navigator.of(context, rootNavigator: true)`
//     reaches the app's top-level navigator. The two resolve different
//     navigators for the same context when navigators are nested — the
//     whole point of nested navigation.
//
//   - Global root. The top-level Navigator (the one with no enclosing
//     navigator) registers itself on the [TuiBinding] as
//     [TuiBinding.rootNavigator], so non-widget code — a socket handler,
//     a timer — can drive top-level navigation without threading a
//     BuildContext and without a GlobalKey hack.
//
//   - State preservation + occlusion. Lower routes stay mounted (their
//     State survives back-navigation) but are paint-gated: once the top
//     route settles opaque, the routes beneath are skipped at paint time.
//     During a transition both the moving route and the screen beneath
//     it are painted, so a slide/fade reveals the lower screen.
//
//   - Type-safe with no codegen, no strings. Arguments ride the screen's
//     constructor; the result rides `push<T>()` / `present<T>() ->
//     Future<T?>`. Focus traps to the top route (modal FocusScope) and is
//     restored to the route beneath on pop.
//   - One presentation system: `push` for pages, `present` for modals
//     (dialogs/sheets — non-opaque routes over the screen beneath), `pop`
//     dismisses either.

import 'dart:async';

import '../animation/animation.dart';
import '../animation/curves.dart';
import '../foundation/key.dart';
import '../rendering/cell.dart' show Color;
import '../rendering/render_navigator.dart';
import '../rendering/render_object.dart';
import '../semantics/semantics.dart';
import '../terminal/events.dart';
import 'align.dart' show Align, Alignment;
import 'basic.dart' show Container, Surface;
import 'effects.dart';
import 'focus.dart';
import 'framework.dart';
import 'key_bindings.dart';
import 'tui_binding.dart';

/// The enter/exit effects (and timing) a route animates with.
class RouteTransition {
  const RouteTransition({
    required this.enter,
    required this.exit,
    this.duration,
    this.curve,
  }) : isInstant = false;

  RouteTransition._instant()
      : enter = Effects.fadeIn(),
        exit = Effects.fadeOut(),
        duration = Duration.zero,
        curve = null,
        isInstant = true;

  final Effect enter;
  final Effect exit;

  /// True only for [none]: the route settles in a single frame with no
  /// enter/exit effect. The navigator maps this to its internal no-transition
  /// path (so [enter]/[exit] are never played).
  final bool isInstant;

  /// How long the enter/exit plays. When null, the navigator falls back
  /// to [defaultDuration].
  final Duration? duration;
  final Curve? curve;

  /// The duration a transition plays when none is specified — also the
  /// duration of the built-in presets. One source of truth so a custom
  /// transition with no [duration] matches the presets' feel.
  static const Duration defaultDuration = Duration(milliseconds: 220);

  /// Cross-fade (the default).
  static RouteTransition get fade => RouteTransition(
    enter: Effects.fadeIn(),
    exit: Effects.fadeOut(),
    curve: Curves.easeInOut,
    duration: defaultDuration,
  );

  /// The canonical stack slide: a push enters from the right edge, a pop
  /// slides back out the same way. Distance is large so the screen starts
  /// fully off-screen.
  static RouteTransition get slide => RouteTransition(
    enter: Effects.slideIn(from: Edge.right, distance: 256),
    exit: Effects.slideOut(to: Edge.right, distance: 256),
    curve: Curves.easeOut,
    duration: defaultDuration,
  );

  /// Instant — the route settles in a single frame with no enter/exit
  /// animation. The reachable opt-out from the animated default: [push] and
  /// [NavigatorState.present] detect it and skip transition building entirely.
  /// Pass per-push (`push(screen, transition: RouteTransition.none)`) or as a
  /// Navigator-wide default (`Navigator(transition: RouteTransition.none)`).
  static final RouteTransition none = RouteTransition._instant();
}

class _Route {
  _Route(
    this.screen,
    RouteTransition? transition, {
    this.presentAlignment,
    this.barrierColor,
    this.barrierDismissible = true,
  }) : transition = (transition == null || transition.isInstant)
           ? null
           : transition;

  final Widget screen;

  /// null = instant. Normalized in the constructor: [RouteTransition.none]
  /// maps to null here so EVERY construction site inherits the instant path
  /// (no per-call-site mapping to forget).
  final RouteTransition? transition;
  final Completer<Object?> completer = Completer<Object?>();
  final Animation<double> presence = Animation(0.0); // 0 absent, 1 present

  /// Stable identity so the route's host element (and its State) survives
  /// reordering as the stack grows and shrinks.
  final Key key = UniqueKey();

  /// Anchors [FocusManager.restoreFocusInScope] inside this route's chrome:
  /// the route's FocusScope remembers the node last focused within it, and a
  /// pop that reveals this route restores through this key. Scope memory is
  /// the primary restore path — recorded where the focus actually lives, so
  /// it survives pushReplacement and popUntil (whose intermediate routes are
  /// gone by restore time).
  final GlobalKey restoreKey = GlobalKey();

  /// Fallback restore target: whatever held focus when this route was
  /// pushed. Covers focus that lived OUTSIDE this navigator's route scopes
  /// (a sidebar pane, app chrome) — no route's FocusScope ever recorded it,
  /// so scope memory alone would strand the keyboard on pop.
  FocusNode? priorFocus;
  bool leaving = false;

  /// True once the route has settled fully present with no in-flight
  /// transition — it then occludes everything beneath it. Modal routes
  /// never flip opaque, so the screen behind them keeps painting.
  bool opaque = false;

  /// Set (to the alignment of the presented content) for a modal route
  /// shown via [NavigatorState.present]; null for an ordinary page. Its
  /// non-null-ness is what marks a route as a non-opaque modal.
  final Alignment? presentAlignment;

  /// For a modal ([presentAlignment] != null): a fill painted over the screen
  /// behind, around the presented content. null leaves the surround composited
  /// with the route beneath. (The content itself always sits on an opaque
  /// [Surface], so it never shows through regardless of this.)
  final Color? barrierColor;

  /// For a modal: whether Esc / a dismiss action pops it. Default true; set
  /// false for a modal that must be answered deliberately (e.g. a confirmation
  /// the user can't skip past). Page routes ignore this — Esc is always back.
  final bool barrierDismissible;

  /// A route this one replaces: removed once this route settles over it
  /// (set by [NavigatorState.pushReplacement]). [replacingResult] is the
  /// value handed to the replaced route's awaiter.
  _Route? replacing;
  Object? replacingResult;

  /// Routes this one clears: all removed (with a null result) once this
  /// route settles, for [NavigatorState.pushAndClear].
  List<_Route>? clearing;

  /// Pop guards registered by [PopScope]s in this route's subtree. A
  /// back/Esc (maybePop) is vetoed while any guard disallows it.
  final Set<_PopScopeState> guards = <_PopScopeState>{};
}

/// Hosts a screen stack. Install one at the app root for a full-screen
/// navigator, or nest one inside any layout slot for scoped, embedded
/// navigation. Single-screen apps don't need it.
class Navigator extends StatefulWidget {
  const Navigator({required this.home, this.transition, super.key});

  /// The initial (root) screen.
  final Widget home;

  /// Default transition for pushes that don't specify one.
  final RouteTransition? transition;

  /// The nearest enclosing [NavigatorState], or — with
  /// [rootNavigator] — the app's top-level navigator. Throws if none
  /// is found.
  static NavigatorState of(BuildContext context, {bool rootNavigator = false}) {
    final state = maybeOf(context, rootNavigator: rootNavigator);
    if (state != null) return state;
    throw StateError(
      rootNavigator
          ? 'No root Navigator for this BuildContext. Wrap your app in a '
                'Navigator(home: ...) and run it with runApp (which installs '
                'a TuiBinding).'
          : 'No Navigator above this BuildContext. Wrap the relevant '
                'subtree in a Navigator(home: ...).',
    );
  }

  /// Like [of] but returns null instead of throwing.
  static NavigatorState? maybeOf(
    BuildContext context, {
    bool rootNavigator = false,
  }) {
    if (rootNavigator) {
      return TuiBinding.maybeOf(context)?.rootNavigator;
    }
    // The nearest scope wraps the routes of the navigator whose region
    // this context lives in; fall back to an ancestor-state walk for a
    // context sitting between a Navigator and its first _NavigatorScope.
    final scope = context.getInheritedWidgetOfExactType<_NavigatorScope>();
    if (scope != null) return scope.navigator;
    return context.findAncestorStateOfType<NavigatorState>();
  }

  @override
  NavigatorState createState() => NavigatorState();
}

class NavigatorState extends State<Navigator> {
  // Routes in paint order, root-first. Includes routes that are leaving
  // (animating out) until their exit completes.
  final List<_Route> _routes = <_Route>[];

  TuiBinding? _binding;
  bool _installed = false;
  bool _isRoot = false;

  /// The number of live routes (excludes routes animating out). The root
  /// counts as one, so `depth == 1` means "at the root."
  int get depth {
    var n = 0;
    for (final r in _routes) {
      if (!r.leaving) n++;
    }
    return n;
  }

  /// Whether there's more than the root route (so a pop is possible).
  bool get canPop => depth > 1;

  /// The topmost live (non-leaving) route — the one that receives input.
  _Route? get _topLive {
    for (var i = _routes.length - 1; i >= 0; i--) {
      if (!_routes[i].leaving) return _routes[i];
    }
    return null;
  }

  FocusManager? get _manager => Focus.maybeOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _binding ??= TuiBinding.maybeOf(context);
    if (_installed) return;
    _installed = true;

    // Register as the application root iff no navigator encloses us.
    if (context.findAncestorStateOfType<NavigatorState>() == null) {
      _isRoot = true;
      _binding?.rootNavigator = this;
    }

    final root = _Route(widget.home, null)..opaque = true;
    if (_binding != null) root.presence.attach(_binding!);
    root.presence.snap(1.0);
    _routes.add(root);
  }

  /// Pushes [screen] and returns a future that completes with the value
  /// passed to [pop] (or null if dismissed).
  Future<T?> push<T>(Widget screen, {RouteTransition? transition}) {
    final route = _newRoute(screen, transition);
    _pushRoute(route);
    return route.completer.future.then((v) => v as T?);
  }

  /// Pushes [screen] in place of the current top route. The new screen
  /// animates in; once it settles, the route it replaced is removed and
  /// its push future completes with [result]. At the root this swaps the
  /// home screen — leaving nothing to pop back to (the login → home idiom).
  Future<T?> pushReplacement<T>(
    Widget screen, {
    RouteTransition? transition,
    Object? result,
  }) {
    final replaced = _topLive;
    final route = _newRoute(screen, transition)
      ..replacing = replaced
      ..replacingResult = result;
    _pushRoute(route);
    // Scope memory needs no inheritance (the covered route's own FocusScope
    // remembers), but the outside-navigator FALLBACK does: the replaced
    // route's snapshot is the pre-push focus; the replacement's own snapshot
    // saw only the replaced route's state.
    if (replaced != null) route.priorFocus = replaced.priorFocus;
    return route.completer.future.then((v) => v as T?);
  }

  /// Pushes [screen] and clears the entire stack beneath it once it
  /// settles — the new screen becomes the sole (root) route. The reset
  /// idiom: log in → home, or log out → login, with no way back into the
  /// flow that was cleared. Cleared routes' futures complete with null.
  Future<T?> pushAndClear<T>(Widget screen, {RouteTransition? transition}) {
    final route = _newRoute(screen, transition)..clearing = _liveRoutes;
    _pushRoute(route);
    return route.completer.future.then((v) => v as T?);
  }

  /// Presents [screen] as a modal over the current screen, positioned by
  /// [alignment] (centered by default). Unlike [push] (a new page in the
  /// journey), the screen beneath stays painted behind it. Returns the
  /// value passed to [pop] (null when dismissed).
  ///
  /// It's an ordinary route: `pop` and Esc dismiss it, and it lives on
  /// the stack of the navigator it's presented on — present on a nested
  /// navigator for a pane-scoped modal, or the root for an app-wide one.
  ///
  /// The presented [screen] is placed on an opaque [Surface] automatically, so
  /// nothing painted beneath shows through it — a modal is never see-through.
  /// [barrierColor] optionally fills the surround (over the screen behind);
  /// null leaves it composited. [barrierDismissible] (default true) controls
  /// whether Esc dismisses it.
  ///
  /// Framing (a border, padding, an edge for a sheet) is just widgets — wrap
  /// [screen] — and [alignment] is the only placement knob you usually need.
  Future<T?> present<T>(
    Widget screen, {
    Alignment alignment = Alignment.center,
    RouteTransition? transition,
    Color? barrierColor,
    bool barrierDismissible = true,
  }) {
    final route = _Route(
      screen,
      // Same resolution chain as push (_newRoute): per-call override, then
      // the Navigator-wide default, then fade. Modals previously skipped
      // widget.transition, so Navigator(transition: RouteTransition.none)
      // silently animated every present().
      transition ?? widget.transition ?? RouteTransition.fade,
      presentAlignment: alignment,
      barrierColor: barrierColor,
      barrierDismissible: barrierDismissible,
    );
    _pushRoute(route);
    return route.completer.future.then((v) => v as T?);
  }

  /// Pops every route above the root in a single transition.
  void popToRoot() {
    if (depth <= 1) return;
    _popAboveTarget(_liveRoutes, 0);
  }

  /// Pops routes until the top screen is a [T] — the type-safe,
  /// string-free analog of `popUntil(name)`. Intermediate routes are
  /// removed instantly; only the final transition animates. No-op if the
  /// top is already a [T] or no [T] sits below it.
  void popUntil<T extends Widget>() {
    if (depth <= 1) return;
    final live = _liveRoutes;
    if (live.last.screen is T) return;
    for (var i = live.length - 1; i >= 0; i--) {
      if (live[i].screen is T) {
        _popAboveTarget(live, i);
        return;
      }
    }
  }

  /// Pops the top route (no-op at the root), completing its future
  /// with [result].
  void pop([Object? result]) {
    if (depth <= 1) return;
    final route = _topLive;
    if (route == null) return;

    route.leaving = true;
    route.opaque = false; // reveal the route beneath during the exit
    if (!route.completer.isCompleted) route.completer.complete(result);

    // Restore focus to the revealed screen immediately — not after the
    // exit animation — so input lands on it right away. The revealed route's
    // FocusScope memory is the primary path (correct even for popUntil,
    // where the routes between are already gone); the push-time snapshot is
    // the fallback for focus that lived OUTSIDE this navigator's routes (a
    // sidebar pane, app chrome), which no route scope ever recorded.
    _manager?.requestFocus(null);
    final revealed = _topLive;
    var restored = false;
    if (revealed != null) {
      restored =
          _manager?.restoreFocusInScope(revealed.restoreKey.currentContext) ??
          false;
    }
    if (!restored) {
      final prior = route.priorFocus;
      if (prior != null && prior.isAttached) prior.requestFocus();
    }

    final transition = route.transition;
    if (transition == null) {
      _remove(route);
      _rebuild();
      return;
    }
    // Reflect the new active route + occlusion now; finish the exit
    // animation, then unmount the route.
    _rebuild();
    route.presence
        .to(
          0.0,
          curve: transition.curve ?? Curves.easeInOut,
          duration: transition.duration ?? RouteTransition.defaultDuration,
        )
        .then((_) {
          if (!mounted) return;
          _remove(route);
          _rebuild();
        });
  }

  /// Back/Esc: pops the top route unless a [PopScope] in it vetoes the
  /// attempt (in which case its `onBlocked` fires and this returns
  /// false). Returns whether a pop happened. Unlike [pop], this consults
  /// pop guards — including at the root, so a screen can intercept a
  /// would-be app exit. [pop] itself is unconditional (programmatic).
  bool maybePop() {
    final top = _topLive;
    if (top != null && top.guards.isNotEmpty) {
      final blockers = top.guards.where((g) => !g.allowsPop).toList();
      if (blockers.isNotEmpty) {
        for (final g in blockers) {
          g.notifyBlocked();
        }
        return false;
      }
    }
    // A non-dismissible modal refuses semantic/back dismissal on EVERY
    // consult path — the route-level Esc binding alone isn't enough, since
    // app back bindings and semantics drivers route through maybePop.
    // Programmatic pop() stays unconditional.
    if (top != null && !top.barrierDismissible) return false;
    if (!canPop) return false;
    pop();
    return true;
  }

  // ---------------------------------------------------------------

  _Route _newRoute(Widget screen, RouteTransition? transition) =>
      _Route(screen, transition ?? widget.transition ?? RouteTransition.fade);

  void _pushRoute(_Route route) {
    // Snapshot BEFORE clearing: the covered route's FocusScope memory is the
    // primary restore path, but focus held outside this navigator's routes
    // (a sibling pane) is only reachable through this fallback.
    route.priorFocus = _manager?.focusedNode;
    // Clear focus so the new route's content autofocuses.
    _manager?.requestFocus(null);
    _routes.add(route);
    _animateIn(route);
    _rebuild();
  }

  void _animateIn(_Route route) {
    final transition = route.transition;
    if (_binding != null) route.presence.attach(_binding!);
    if (transition == null) {
      route.presence.snap(1.0);
      // Modal routes stay non-opaque so the screen behind keeps painting.
      if (route.presentAlignment == null) route.opaque = true;
      _onEntered(route);
      return;
    }
    route.presence
        .to(
          1.0,
          curve: transition.curve ?? Curves.easeInOut,
          duration: transition.duration ?? RouteTransition.defaultDuration,
        )
        .then((_) {
          // Guard against cancellation: a pop mid-entrance supersedes this
          // to(1.0) but still completes it. We must NOT flip a now-leaving
          // route opaque (it would cover the screen beneath during its exit),
          // nor a modal route (the screen behind must stay visible).
          if (mounted && !route.leaving) {
            if (route.presentAlignment == null) route.opaque = true;
            _onEntered(route);
            _rebuild();
          }
        });
  }

  /// Once [route] has settled fully present, drop the route(s) it
  /// superseded — now safely occluded — and deliver their results.
  void _onEntered(_Route route) {
    final replaced = route.replacing;
    if (replaced != null) {
      route.replacing = null;
      if (!replaced.completer.isCompleted) {
        replaced.completer.complete(route.replacingResult);
      }
      _remove(replaced);
    }
    final cleared = route.clearing;
    if (cleared != null) {
      route.clearing = null;
      for (final r in cleared) {
        if (identical(r, route)) continue;
        if (!r.completer.isCompleted) r.completer.complete(null);
        _remove(r);
      }
    }
  }

  /// Removes the occluded routes above [targetIndex] (in [live]) instantly,
  /// then animates the current top out to reveal the target.
  void _popAboveTarget(List<_Route> live, int targetIndex) {
    for (var i = live.length - 2; i > targetIndex; i--) {
      final r = live[i];
      if (!r.completer.isCompleted) r.completer.complete(null);
      _remove(r);
    }
    pop();
  }

  List<_Route> get _liveRoutes => <_Route>[
    for (final r in _routes)
      if (!r.leaving) r,
  ];

  void _remove(_Route route) {
    _routes.remove(route);
    route.presence.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  bool _isActive(_Route route) => !route.leaving && identical(route, _topLive);

  /// Index of the first route to paint: the topmost settled opaque
  /// route. Routes below it are occluded and skipped at paint time.
  int _firstPainted() {
    for (var i = _routes.length - 1; i >= 0; i--) {
      if (_routes[i].opaque) return i;
    }
    return 0;
  }

  @override
  void dispose() {
    if (_isRoot && identical(_binding?.rootNavigator, this)) {
      _binding!.rootNavigator = null;
    }
    for (final route in _routes) {
      // Don't leave callers awaiting push() futures hung on teardown.
      if (!route.completer.isCompleted) route.completer.complete(null);
      route.presence.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Expose this navigator to its routes' subtrees so `context.push` /
    // `context.pop` resolve to it, then lay the routes out in our own
    // slot via RenderNavigatorStack.
    return Semantics(
      role: SemanticRole.navigation,
      label: _isRoot ? 'root navigator' : 'navigator',
      value: depth,
      actions: <SemanticAction>{
        SemanticAction.navigate,
        if (canPop) SemanticAction.close,
      },
      state: SemanticState({
        'routeDepth': depth,
        'canPop': canPop,
        'root': _isRoot,
      }),
      onAction: _handleNavigatorAction,
      child: _NavigatorScope(
        navigator: this,
        child: _RouteStack(
          firstPainted: _firstPainted(),
          children: <Widget>[
            for (var i = 0; i < _routes.length; i++)
              _RouteHost(
                key: _routes[i].key,
                navigator: this,
                route: _routes[i],
                routeIndex: i,
              ),
          ],
        ),
      ),
    );
  }

  void _handleNavigatorAction(SemanticAction action) {
    switch (action) {
      case SemanticAction.close:
      case SemanticAction.dismiss:
        maybePop();
        return;
      case SemanticAction.navigate:
        return;
      case _:
        return;
    }
  }
}

/// Builds one route: focus trap + Esc binding + transition + screen.
/// Subscribes to the route's presence so only this host rebuilds per
/// transition frame (not the whole navigator).
class _RouteHost extends StatelessWidget {
  const _RouteHost({
    required super.key,
    required this.navigator,
    required this.route,
    required this.routeIndex,
  });

  final NavigatorState navigator;
  final _Route route;
  final int routeIndex;

  @override
  Widget build(BuildContext context) {
    final active = navigator._isActive(route);
    final t = route.presence.value; // subscribe → drives transition frames

    // A page fills its slot; a modal is positioned by its alignment over
    // the screen behind it (which keeps painting since the route is
    // non-opaque). Any framing — a border, padding — is the caller's
    // widgets, not baked in here.
    final align = route.presentAlignment;
    final Widget screen;
    if (align == null) {
      screen = route.screen;
    } else {
      // Modal: the presented content sits on an opaque Surface so nothing
      // painted beneath shows through it (closes the bleed-through leak). A
      // barrierColor, when set, fills the surround over the screen behind;
      // null leaves the surround composited with the route beneath.
      Widget content = Align(
        alignment: align,
        child: Surface(child: route.screen),
      );
      final barrier = route.barrierColor;
      if (barrier != null) {
        content = Container(color: barrier, child: content);
      }
      screen = content;
    }

    // Presented routes trap focus like modals. Normal page routes still let
    // ancestor app-level bindings participate, which keeps global commands
    // such as "open command palette" available while a page has focus.
    //
    // The chrome does NOT claim focus itself — the screen's own content
    // (e.g. a TextInput) autofocuses. Focus is restored to the route beneath
    // on pop.
    final modal = active && align != null;
    // Esc dismisses an active route — always for a page (back navigation), and
    // for a modal only when it's barrierDismissible.
    final dismissible = align == null || route.barrierDismissible;
    Widget content = FocusScope(
      modal: modal,
      suppressGlobals: modal,
      // The restoreKey anchors focus restoration: it sits INSIDE the route's
      // FocusScope, so restoreFocusInScope(key.currentContext) resolves this
      // route's scope memory when a pop reveals the route again.
      child: KeyBindings(
        key: route.restoreKey,
        bindings: active && dismissible
            ? [
                KeyBinding(
                  KeyChord.key(KeyCode.escape),
                  onEvent: (_) => navigator.maybePop(),
                  hideFromHintBar: true,
                ),
              ]
            : const <KeyBinding>[],
        // Expose this route to its subtree so a PopScope can register
        // its veto with the right route. Covered routes are focus-inert
        // (ExcludeFocus): they stay mounted and keep building, so without
        // this a late-mounting autofocus in an occluded route would steal
        // focus from the active route — even out of a modal, leaving it
        // keyboard-undismissable. Exclusion also keeps Tab traversal from
        // wandering into invisible screens.
        child: ExcludeFocus(
          excluding: !active,
          child: _RouteScope(route: route, child: screen),
        ),
      ),
    );

    final transition = route.transition;
    if (transition != null) {
      // Always wrap when a transition exists — even when settled (enter at full
      // progress) — so the effect wrapper is a STABLE element. Wrapping only
      // while animating would add/remove the wrapper on every transition-state
      // change (enter -> settled -> leaving), remounting the route's content
      // and losing its State (scroll position, text, focus) — and re-firing
      // autofocus, which could steal focus a pop just restored.
      //
      // Settled routes use the effect's AT-REST form (same element shape,
      // passthrough paint): the live composite at full progress would pay a
      // scratch-buffer double paint every frame, drop protocol (image) cells,
      // and record scratch-local focus/pointer geometry.
      content = route.leaving
          ? transition.exit.build(content, (1 - t).clamp(0.0, 1.0))
          : (t >= 1.0
                ? transition.enter.buildSettled(content)
                : transition.enter.build(content, t.clamp(0.0, 1.0)));
    }
    final routeName = route.screen.runtimeType.toString();
    return Semantics(
      role: SemanticRole.route,
      label: routeName,
      selected: active,
      enabled: !route.leaving,
      includeChildren: active,
      actions: active
          ? <SemanticAction>{
              SemanticAction.navigate,
              if (navigator.canPop && dismissible)
                route.presentAlignment == null
                    ? SemanticAction.close
                    : SemanticAction.dismiss,
            }
          : const <SemanticAction>{},
      state: SemanticState({
        'routeName': routeName,
        'routeIndex': routeIndex,
        'routeDepth': navigator.depth,
        'active': active,
        'leaving': route.leaving,
        'modal': route.presentAlignment != null,
        'opaque': route.opaque,
      }),
      onAction: active
          ? (action) {
              switch (action) {
                case SemanticAction.close:
                case SemanticAction.dismiss:
                  navigator.maybePop();
                  return;
                case SemanticAction.navigate:
                  return;
                case _:
                  return;
              }
            }
          : null,
      child: content,
    );
  }
}

/// Multi-child render-object widget hosting the navigator's routes.
class _RouteStack extends MultiChildRenderObjectWidget {
  const _RouteStack({required this.firstPainted, required super.children});

  final int firstPainted;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderNavigatorStack(firstPainted: firstPainted);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderNavigatorStack renderObject,
  ) {
    renderObject.firstPainted = firstPainted;
  }
}

/// Inherited handle exposing the [NavigatorState] to its routes.
class _NavigatorScope extends InheritedWidget {
  const _NavigatorScope({required this.navigator, required super.child});

  final NavigatorState navigator;

  @override
  bool updateShouldNotify(_NavigatorScope old) =>
      !identical(navigator, old.navigator);
}

/// Inherited handle exposing the enclosing [_Route] to its subtree, so a
/// [PopScope] can register its veto with the right route.
class _RouteScope extends InheritedWidget {
  const _RouteScope({required this.route, required super.child});

  final _Route route;

  @override
  bool updateShouldNotify(_RouteScope old) => !identical(route, old.route);
}

/// Intercepts a back/Esc (maybePop) for the route it sits in.
///
/// While [canPop] is false, a back/Esc on this route is vetoed and
/// [onBlocked] fires instead — the place to confirm "discard changes?"
/// or to gate an app exit at the root. A programmatic
/// [NavigatorState.pop] is NOT intercepted; only [NavigatorState.maybePop]
/// (Esc/back) is. Multiple PopScopes in one route compose: any with
/// `canPop == false` blocks.
///
/// ```dart
/// PopScope(
///   canPop: !hasUnsavedChanges,
///   onBlocked: () => context.push<void>(const DiscardChangesDialog()),
///   child: editor,
/// );
/// ```
class PopScope extends StatefulWidget {
  const PopScope({
    required this.child,
    this.canPop = true,
    this.onBlocked,
    super.key,
  });

  /// Whether a back/Esc may pop this route. When false the attempt is
  /// vetoed and [onBlocked] fires.
  final bool canPop;

  /// Called when a back/Esc was vetoed (because [canPop] was false).
  final VoidCallback? onBlocked;

  final Widget child;

  @override
  State<PopScope> createState() => _PopScopeState();
}

class _PopScopeState extends State<PopScope> {
  _Route? _route;

  bool get allowsPop => widget.canPop;
  void notifyBlocked() => widget.onBlocked?.call();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = context.getInheritedWidgetOfExactType<_RouteScope>()?.route;
    if (!identical(route, _route)) {
      _route?.guards.remove(this);
      _route = route;
      _route?.guards.add(this);
    }
  }

  @override
  void dispose() {
    _route?.guards.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// `context.push(...)` / `context.pop()` — the terse fluent entry.
extension NavigatorContext on BuildContext {
  /// The nearest [NavigatorState].
  NavigatorState get navigator => Navigator.of(this);

  /// The app's root [NavigatorState].
  NavigatorState get rootNavigator => Navigator.of(this, rootNavigator: true);

  /// Pushes [screen]; awaits its [pop] result.
  Future<T?> push<T>(Widget screen, {RouteTransition? transition}) =>
      Navigator.of(this).push<T>(screen, transition: transition);

  /// Replaces the current screen with [screen] (the login → home idiom).
  Future<T?> pushReplacement<T>(
    Widget screen, {
    RouteTransition? transition,
    Object? result,
  }) => Navigator.of(
    this,
  ).pushReplacement<T>(screen, transition: transition, result: result);

  /// Pushes [screen] and clears the stack beneath it (the reset idiom).
  Future<T?> pushAndClear<T>(Widget screen, {RouteTransition? transition}) =>
      Navigator.of(this).pushAndClear<T>(screen, transition: transition);

  /// Presents [screen] as a modal over the current screen (centered by
  /// default), on an opaque [Surface]. Dismiss with [pop]. [barrierColor]
  /// fills the surround; [barrierDismissible] (default true) controls Esc.
  Future<T?> present<T>(
    Widget screen, {
    Alignment alignment = Alignment.center,
    RouteTransition? transition,
    Color? barrierColor,
    bool barrierDismissible = true,
  }) => Navigator.of(this).present<T>(
    screen,
    alignment: alignment,
    transition: transition,
    barrierColor: barrierColor,
    barrierDismissible: barrierDismissible,
  );

  /// Pops the current screen with an optional [result].
  void pop([Object? result]) => Navigator.of(this).pop(result);

  /// Pops until the top screen is a [T].
  void popUntil<T extends Widget>() => Navigator.of(this).popUntil<T>();

  /// Pops every screen above the root.
  void popToRoot() => Navigator.of(this).popToRoot();
}
