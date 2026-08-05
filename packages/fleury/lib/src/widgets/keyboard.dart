// Keyboard + KeyDetector — RFC 0020 Part II's non-command surface.
//
// The documentation rule the whole design serves:
//
//   KeyBindings matches gestures; Keyboard reads keys.
//
// React to a press → a binding. Need "is it held right now" inside a tick →
// `Keyboard.of(context).snapshot`. Wait for exactly one key → `nextKey`.
// Widget-internal conditional key handling (the floor: library widgets,
// bridges, PTY panes) → `KeyDetector`.

import '../foundation/change_notifier.dart';
import '../input/events.dart';
import '../input/keyboard_layout.dart';
import '../input/keyboard_state.dart';
import '../runtime/input_dispatcher.dart';
import 'focus.dart';
import 'framework.dart';
import 'inherited_notifier.dart';

/// The surface's keyboard: what it guarantees, and what is held right now.
///
/// Obtained from the tree, but deliberately **not** a widget — continuous
/// input is a *state* question, sampled from the ticker you already have,
/// not a callback:
///
/// ```dart
/// late final _keyboard = Keyboard.of(context);   // safe to cache
///
/// void _tick(Duration elapsed) {
///   final keys = _keyboard.snapshot;             // stable for this frame
///   if (keys.isHeld(KeyPosition.w)) ship.thrust(dt);
///   if (keys.wasPressed(KeyCode.space)) ship.fire();
/// }
/// ```
///
/// **Reactivity is asymmetric, by design.** Obtaining the handle registers a
/// dependency on *capability and session* changes only — so a control scheme
/// branched on [capabilities] rebuilds when a terminal finishes negotiating,
/// a session reconnects, or a surface downgrades. Key transitions never
/// notify: an API that cannot notify on input cannot cause an input-rate
/// rebuild storm (RFC 0020 §15, §19).
final class Keyboard {
  const Keyboard._(this._session);

  final KeyboardSession _session;

  /// What this surface has been *confirmed* to guarantee. Legal to read in
  /// `build()`; reading it there is what subscribes the widget to
  /// negotiation and reconnect.
  KeyboardCapabilities get capabilities => _session.capabilities;

  /// What this keyboard's keys are capped with, for rendering a positional
  /// control honestly (RFC 0020 §9).
  ///
  /// `KeyPosition.w` is a SPOT; showing it as "W" to someone on AZERTY
  /// names a key that is not under that finger. Ask the layout instead:
  ///
  /// ```dart
  /// final label = Keyboard.of(context).layout.labelFor(KeyPosition.w);
  /// Text(label?.text ?? 'key at ${KeyPosition.w.name}');
  /// ```
  ///
  /// Null means genuinely unknown — render the position, never a guess.
  KeyboardLayout get layout => _session.layout;

  /// The frame-latched view of what is held (RFC 0020 §5.6): immutable for
  /// the whole frame, so every read within one tick agrees.
  ///
  /// Read from a ticker or a callback — **not** from `build()`, which is not
  /// re-run when a key changes. Debug builds assert on that misuse.
  ///
  /// Every query is empty or false where
  /// [KeyboardCapabilities.supportsHeldState] is false: an accumulating set
  /// with no release reporting is a lying set. Press-only input remains
  /// fully available through `KeyBindings`; branch on the capability and
  /// offer a different control scheme (§7.6).
  KeyboardSnapshot get snapshot {
    assert(() {
      // `Element.current` is non-null exactly while a build (or a
      // build-time callback) is running — the misuse this guards.
      if (Element.current != null) {
        throw StateError(
          'Keyboard.snapshot was read during build.\n'
          'Sampled key state is not reactive — build() is not re-run when a '
          'key goes down, so a value read here is stale by construction.\n'
          'Read it from a ticker callback (the frame that samples it is the '
          'frame that uses it), or, to branch a control scheme on what the '
          'surface supports, read Keyboard.of(context).capabilities instead '
          '— that IS reactive and legal here.',
        );
      }
      return true;
    }());
    return _session.snapshot;
  }

  /// Awaits exactly one key press — the rebind row, the press-any-key
  /// prompt, vim's `getchar()` for `m<letter>` and quoted-insert.
  ///
  /// ```dart
  /// final key = await Keyboard.nextKey(context);
  /// if (key != null && key.code != KeyCode.escape) rebind(key);
  /// ```
  ///
  /// Scope-tied **by signature**: [context]'s element unmounting completes
  /// the future with null, so a capture cannot outlive the UI that started
  /// it and quietly eat the app's input (the `showDialog` pop-returns-null
  /// contract; never mounted-check discipline).
  ///
  /// While pending it is exclusive over the *routed* lanes — bindings,
  /// detectors, text — so quoted-insert beats even the editor's own Escape
  /// binding and the awaiter decides. Session state and the observation lane
  /// are never starved, so a hold in flight still ends correctly.
  /// Recovery-synthesized events never complete it (a blur must not "choose"
  /// Ctrl for a rebind row).
  static Future<KeyEvent?> nextKey(BuildContext context) =>
      _dispatcherOf(context).captureNextKey(context);

  /// The keyboard of the surface [context] is mounted on.
  ///
  /// Stable for the lifetime of one `runApp`: a driver swap clears state and
  /// bumps [KeyboardSnapshot.sessionGeneration] on the same handle rather
  /// than replacing it, so caching the handle in a `State` field is safe.
  static Keyboard of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<KeyboardScope>();
    if (scope == null) {
      throw StateError(
        'Keyboard.of() found no KeyboardScope.\n'
        'The scope is installed by runApp (and by the browser embed host), '
        'so this usually means the widget is being built outside a running '
        'app — in a bare BuildOwner test, mount FleuryTester or wrap the '
        'tree in a KeyboardScope.',
      );
    }
    return Keyboard._(scope.notifier.session);
  }

  static InputDispatcher _dispatcherOf(BuildContext context) {
    // Non-subscribing: nextKey is normally called from a callback, where
    // establishing a build dependency would be wrong.
    final scope = context.getInheritedWidgetOfExactType<KeyboardScope>();
    if (scope == null) {
      throw StateError('Keyboard.nextKey() found no KeyboardScope.');
    }
    return scope.notifier.dispatcher;
  }
}

/// Publishes the session keyboard to the tree, notifying on capability and
/// session changes only — never on key transitions (see [Keyboard]).
final class KeyboardStateNotifier with ChangeNotifier {
  KeyboardStateNotifier(this.dispatcher);

  /// The dispatcher that owns the session and the capture gate.
  final InputDispatcher dispatcher;

  KeyboardSession get session => dispatcher.keyboardSession;

  /// Framework-only: the runtime calls this after applying confirmed
  /// capabilities or replacing the session.
  void notifyCapabilitiesChanged() => notifyListeners();
}

/// Shares the session keyboard with the widget tree. Installed by the host
/// composition root; depended on by [Keyboard.of].
final class KeyboardScope extends InheritedNotifier<KeyboardStateNotifier> {
  const KeyboardScope({
    super.key,
    required super.notifier,
    required super.child,
  });

  /// Framework-internal: the dispatcher owning this surface's input lanes,
  /// or null outside a running app. Non-subscribing — a widget reaching for
  /// the observation lane must not rebuild on capability changes.
  static InputDispatcher? maybeDispatcherOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<KeyboardScope>()
      ?.notifier
      .dispatcher;
}

/// Conditional, widget-internal key handling — the framework's floor.
///
/// A detector *peeks* at the key stream flowing through its subtree and
/// consumes only what it uses:
///
/// ```dart
/// KeyDetector(
///   onKey: (e) {
///     if (e.code == KeyCode.arrowDown && _canScroll(1)) {
///       _scrollBy(1);
///       e.consume();          // mine
///     }
///     // not consumed → propagates, no ceremony
///   },
///   child: Focus(child: view),
/// )
/// ```
///
/// **Propagate by default** — the inverse of a binding, and deliberately so
/// (RFC 0020 §16): a binding *declared* a match, so consumption is its
/// semantics; a detector is peeking, so observation is the base state. That
/// also inverts the failure mode of the `Focus.onKey` it replaces, where a
/// blanket `return handled` silently starved an ancestor's feature. Forget
/// to consume here and your key visibly does double duty while you test it —
/// loud and local beats silent and distant.
///
/// **Not the authoring surface.** Apps declare `KeyBindings`, which is data
/// the framework can read: the hint bar, which-key, and devtools render from
/// the binding list and cannot read a closure. Reach for a detector when the
/// handling is genuinely internal (a reusable scroll region, a bridge, a
/// terminal pane forwarding raw keys) — see §17.
///
/// Scope: active while focus is within the subtree, matched deepest-first
/// like any binding scope. It installs a marker in the focus chain, **not** a
/// focus node — adding a detector never changes traversal; compose `Focus`
/// explicitly. Down and repeat only: releases never enter the routed lanes,
/// because a consumable release would wedge an ancestor's pressed state.
final class KeyDetector extends StatefulWidget {
  const KeyDetector({super.key, required this.onKey, required this.child});

  /// Called for each key event routed through this subtree. Consume with
  /// [KeyEvent.consume]; do nothing to let it continue.
  final void Function(KeyEvent event) onKey;

  final Widget child;

  @override
  State<KeyDetector> createState() => _KeyDetectorState();
}

class _KeyDetectorState extends State<KeyDetector> {
  late final FocusNode _marker;

  @override
  void initState() {
    super.initState();
    // A chain participant, never a focus target: invisible to Tab
    // traversal, click-to-focus, and autofocus.
    _marker = FocusNode(debugLabel: 'KeyDetector')
      ..canRequestFocus = false
      ..skipTraversal = true
      ..keyDetector = _handle;
  }

  void _handle(KeyEvent event) => widget.onKey(event);

  @override
  void dispose() {
    _marker.keyDetector = null;
    _marker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: _marker, child: widget.child);
}
