# RFC 0025: Scope — One Tree-Local State Primitive

**Status:** Implemented

**Date:** 2026-09-07
**Builds on:** RFC 0007 framework, RFC 0023 reactive-state exploration (spike branch)

## 1. Summary

Fleury answers the three state questions with one primitive each:

| Question | Answer |
|---|---|
| State one widget owns | `StatefulWidget` + `setState` (unchanged) |
| State a subtree shares | `Scope<T>` (this RFC) |
| State with an independent owner | `ChangeNotifier` / `ValueNotifier` + `ListenableBuilder` (unchanged) |

`Scope<T>` replaces `InheritedWidget`, `InheritedNotifier`, `InheritedElement`,
and the two `BuildContext` lookup methods. It is the same mechanism Flutter
calls an `InheritedWidget`, React a Context, SwiftUI the environment — with
the type argument as the key and the notifier subscription built in:

```dart
// Share an object its owner keeps alive:
Scope(value: chat, child: const ChatScreen())

// Let the scope own the object — created on mount, disposed on unmount:
Scope<ChatModel>.create(create: (context) => ChatModel(), child: const ChatScreen())

// Anywhere below, in build, initState, or a handler:
final chat = Scope.of<ChatModel>(context);
```

## 2. Why

The reactive-state exploration (RFC 0023 §7–§8, spike branch) ended with a
measurement: field-level reactivity saved 100–140 µs per frame at 60 rows —
about one percent of a frame at 100 tokens/s — and cost a second mental model
(signals, `.value` rules, implicit dependency tracking) on top of `setState`.
The decision was **no field-level reactivity**: notification stays coarse and
Flutter-shaped, and the framework earns simplicity elsewhere.

That left the tree-local story with two-and-a-half primitives (`InheritedWidget`,
`InheritedNotifier`, and a hand-written `.of` + `updateShouldNotify` +
`dependOnInheritedWidgetOfExactType` per scope). Every framework scope repeated
that boilerplate, and the focus manager needed a second widget to get
identity-only semantics. One primitive with the type as the key removes all of
it. (Under `Scope`, `TickerMode` and `DefaultTextStyle` instead need private
value types so a user `Scope<bool>` or `Scope<CellStyle>` cannot collide with
them — §3.3.)

## 3. Design

### 3.1 The widget

```dart
class Scope<T extends Object> extends ProxyWidget {
  const Scope({Key? key, required T value, required Widget child});
  const Scope.create({Key? key, required T Function(BuildContext) create,
                      void Function(T)? dispose, required Widget child});

  bool updateShouldNotify(covariant Scope<T> oldWidget); // default: value != old
  static T of<T extends Object>(BuildContext context);
  static T? maybeOf<T extends Object>(BuildContext context);
  @internal static T? maybeOfWithoutDependency<T extends Object>(BuildContext context);
}
```

- **Type-keyed, exact.** `Scope.of<T>` walks ancestors for the nearest
  `ScopeElement` whose type argument is exactly `T`. `Scope<Derived>` is not
  found for a `Scope<Base>` lookup, nor the reverse; nearest wins, so an inner
  scope shadows an outer one and tests override by wrapping. A missing type
  argument (`T == Object`) is an assertion.
- **Subscribing.** Reading registers the reader as a dependent, in `build`,
  `initState`, or a handler. An element in `dispose` has left the tree;
  `Scope.of` throws a pointed error there ("keep it in a field").
- **Listenable values.** When the value is a `Listenable` the element listens
  — attached before the child cascade mounts (a descendant's first build may
  notify), swapped on update with the replacement attached first, detached on
  unmount — and each notification marks every dependent dirty with
  `didChangeDependencies` (or `updateRenderObject`) running before the rebuild.
- **Plain values.** Readers rebuild when the scope is rebuilt with a value
  that is not `==` to the previous one; `updateShouldNotify` is overridable
  for a narrower comparison.
- **Owned values.** `Scope.create` runs `create` once at mount with the scope
  element as context (it can read scopes above). On unmount, after the
  children are gone, `dispose` runs; without one a `ChangeNotifier` is disposed
  and anything else is dropped. Rebuilding the widget does not recreate.
  Switching one tree position between the two constructors is handled: the
  owned object is released after the subtree has re-read the replacement.
- **No `read`, no `select`.** `Scope.of` is the only app-facing read. A
  non-subscribing lookup exists for framework plumbing (render objects
  registering with a service, actions from handlers) and is `@internal`.

### 3.2 Under the hood

`ScopeElement<T>` is the old `InheritedElement` plus the old
`_InheritedNotifierElement` plus value ownership: the dependents set,
`notifyDependents()`, `_markDependencyChanged`, the listener, and the
`_owned` flag. `Element` keeps a nullable `Set<ScopeElement>` of the scopes it
depends on; `_detachDependencies` clears it on unmount and deactivate exactly
as before. The lookup tests the element class first (a cheap class check on
every ancestor) and compares the `Type` key only at scope elements; measured
against `widget is Scope<T>` the `Type ==` compare was faster in both JIT
(82 vs 99–122 ns per six-scope walk) and AOT (32 vs 53 ns).

### 3.3 The framework's own scopes

Every internal scope became either a plain `Scope<T>` at its install site
(`Theme` → `Scope<ThemeData>`, the navigator's `Scope<NavigatorState>` and
`Scope<_Route>`, `FocusManagerScope` → `Scope<FocusManager>`, `Form` →
`Scope<FormController>`, `Toaster` → `Scope<_ToasterState>`, `FleuryApp` →
`Scope<StatusController>`) or a `Scope<T>` subclass that keeps its constructor
so the ~70 host and test install sites did not change (`MediaQuery`,
`ClipboardScope`, `KeyboardScope`, `PendingSequenceScope`, `TuiBindingScope`,
`TerminalSessionScope`, `LogBufferScope`, `FleuryAppScope`,
`CommandRegistryScope`, `FormControlScope`, `SelectionScope`,
`PointerRouterScope` with its element hook, `TickerMode`).

Three cases needed a value type of their own instead of a flag:

- `TickerMode` shares a private two-constant `_TickerModeData` rather than a
  `bool`, and `DefaultTextStyle` (now a `StatelessWidget`) shares a private
  `_DefaultTextStyleData` rather than a `CellStyle`, so no user scope of those
  common types can collide with them. `DefaultTextStyle` keeps a
  `StatelessWidget` layer (one extra element per instance) because a const
  constructor cannot build a wrapper from its `style` parameter in the
  initializer list; `TickerMode` avoids the layer only because its wrapper is
  one of two constants.
- The focus manager is shared twice: `Scope<FocusManager>` (notifying, what
  `FocusManager.of` reads) and `Scope<_FocusManagerIdentity>` (an equality-by-manager
  handle for boundaries that must rebind on replacement but not rebuild on
  every focus move).
- `SelectionScope(registrar: null)` shares a const no-op registrar so the
  value stays non-null; `SelectionScope.maybeOf` maps it back to `null`.

Two scopes changed behaviour on purpose: the status bar reads
`Scope.of<StatusController>` directly (the `StatusHost` bridge and its scope
are gone), and `Form.of` now subscribes its reader to the controller — the
`Scope` rule for a `Listenable` value — instead of notifying only on identity
change.

## 4. What was rejected

- **Field-level reactivity / signals** (RFC 0023): measured too small a win
  for the second mental model. Coarse notification; "one notifier per rate of
  change" is the rule to teach, `ListenableBuilder` the narrowing tool.
- **`Scope.read` / `Scope.select`**: dropped for simplicity. A handler that
  reads with `Scope.of` becomes a dependent; that is the accepted cost.
- **Keeping `InheritedWidget` under `Scope`**: two mechanisms for one job.
  `Scope` *is* the inherited primitive.
- **Covariant type matching** (`Scope.of<Base>` finding a `Scope<Derived>`):
  less predictable, and slower than the exact `Type` compare.
- **A `listen: false` flag**: the same concept as `read`, in flag form.

## 5. Validation

- `scope_test.dart` (26 cases): lookup and exact keying, plain-value
  replacement and `didChangeDependencies`, a narrowed `updateShouldNotify`,
  attach-before-mount, live replacement during a child rebuild, detach on
  replacement and on unmount, failed child update, non-subscribing read,
  `initState` read, `dispose` read error, `create` once with an upstream read,
  auto-dispose vs `dispose:`, children-before-dispose order, switching
  constructors at one position, and the two hand-off cases the review found
  (handing the owned object over as the shared value keeps it alive; a
  hand-off whose listener fails to attach leaves the object owned and
  disposed on unmount).
- The dependency-lifecycle and reparenting suites run against `Scope`
  unchanged in intent; the whole check is green and the perf gates pass (see
  the execution journal entry).
