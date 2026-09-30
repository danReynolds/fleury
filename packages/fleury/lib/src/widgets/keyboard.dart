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
import 'package:meta/meta.dart';

import '../input/keyboard_state.dart';
import '../runtime/input_dispatcher.dart';
import 'focus.dart';
import 'framework.dart';

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
///   final keys = _keyboard.snapshot;             // stable for this tick
///   if (keys.isHeld(KeyPosition.w)) ship.thrust(dt);
///   if (keys.wasPressed(KeyCode.space)) ship.fire();
/// }
/// ```
///
/// Edges (`wasPressed`/`wasReleased`) live for exactly one latch, and while a
/// ticker is running the tick IS the latch — so a tap survives whatever else
/// the app renders between the press and this callback. With no ticker
/// registered the snapshot advances once per rendered frame instead, so a
/// ticker-free app never reports a stale tap forever (RFC 0020 §5.6).
///
/// **Reactivity is asymmetric, by design.** Obtaining the handle registers a
/// dependency on changes to what the keyboard IS — capabilities, session
/// identity, and newly learned [layout] caps — so a control scheme branched on
/// [capabilities] rebuilds when a terminal finishes negotiating, and a hint bar
/// re-renders when a position's real cap becomes known. Key transitions never
/// notify: an API that cannot notify on input cannot cause an input-rate
/// rebuild storm (RFC 0020 §15, §19). Layout learning is bounded by the
/// physical key count, not the keystroke rate.
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
    final notifier = dependOnScope<KeyboardStateNotifier>(context);
    if (notifier == null) {
      throw StateError(
        'Keyboard.of() found no KeyboardScope.\n'
        'The scope is installed by runApp (and by the browser embed host), '
        'so this usually means the widget is being built outside a running '
        'app — in a bare BuildOwner test, mount FleuryTester or wrap the '
        'tree in a KeyboardScope.',
      );
    }
    return Keyboard._(notifier.session);
  }

  static InputDispatcher _dispatcherOf(BuildContext context) {
    // Non-subscribing: nextKey is normally called from a callback, where
    // establishing a build dependency would be wrong.
    final notifier = readScope<KeyboardStateNotifier>(context);
    if (notifier == null) {
      throw StateError('Keyboard.nextKey() found no KeyboardScope.');
    }
    return notifier.dispatcher;
  }
}

/// Publishes the session keyboard to the tree, notifying on capability and
/// session changes only — never on key transitions (see [Keyboard]).
final class KeyboardStateNotifier with Notifier {
  KeyboardStateNotifier(this.dispatcher) {
    // Layout learning republishes through the same channel capabilities do:
    // both answer "what is this keyboard", both are build-legal reads, and a
    // hint bar that asked the layout must hear when the answer improves.
    dispatcher.keyboardSession.onDescriptionChanged = notify;
  }

  /// The dispatcher that owns the session and the capture gate.
  final InputDispatcher dispatcher;

  /// Framework-internal: [KeyboardSession] is not part of the public API
  /// surface (external code reads [Keyboard]); annotated so the leak of an
  /// unexported type through an exported one is analyzer-visible outside
  /// this package.
  @internal
  KeyboardSession get session => dispatcher.keyboardSession;

  /// Framework-only: the runtime calls this after applying confirmed
  /// capabilities or replacing the session.
  void notifyCapabilitiesChanged() => notify();
}

/// Shares the session keyboard with the widget tree — a
/// `Scope<KeyboardStateNotifier>`. Installed by the host composition root;
/// depended on by [Keyboard.of].
final class KeyboardScope extends Scope<KeyboardStateNotifier> {
  const KeyboardScope({
    super.key,
    required KeyboardStateNotifier notifier,
    required super.child,
  }) : super(notifier);

  /// Framework-internal: the dispatcher owning this surface's input lanes,
  /// or null outside a running app. Non-subscribing — a widget reaching for
  /// the observation lane must not rebuild on capability changes.
  static InputDispatcher? maybeDispatcherOf(BuildContext context) =>
      readScope<KeyboardStateNotifier>(context)?.dispatcher;
}

/// Low-level key handling inside a widget: sees each key that reaches its
/// subtree and consumes only the ones it handles.
///
/// ```dart
/// KeyDetector(
///   onKey: (e) {
///     if (e.code == KeyCode.arrowDown && _canScroll(1)) {
///       _scrollBy(1);
///       e.consume(); // handled here
///     }
///     // Not consumed: the key keeps propagating to ancestors.
///   },
///   child: Focus(child: view),
/// )
/// ```
///
/// **Keys propagate unless consumed** — the reverse of a key binding, which
/// consumes the key it matches. A detector observes by default, so a key it
/// forgets to consume does visible double duty while you test it, instead of
/// silently starving an ancestor's shortcut.
///
/// **Prefer `KeyBindings` for app shortcuts.** Bindings are data the
/// framework can read: the hint bar, which-key, and devtools list them, and
/// none of them can read a closure. Use a detector when the handling belongs
/// inside a reusable control, such as a scroll region or a terminal pane that
/// forwards raw keys.
///
/// A detector is active while focus is within its subtree and is matched
/// deepest-first, like a binding scope. It is **not** a focus node: adding
/// one never changes traversal, so wrap the focusable part in `Focus`
/// yourself. It sees key presses and repeats, never releases.
final class KeyDetector extends StatefulWidget {
  const KeyDetector({super.key, required this.onKey, required this.child});

  /// Called for each key event routed through this subtree. Consume with
  /// [KeyEvent.consume]; do nothing to let it continue.
  final void Function(KeyEvent event) onKey;

  /// The subtree whose keys [onKey] sees. The detector only fires while this
  /// subtree holds focus — it is scoped, not ambient.
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
      InputScope(node: _marker, child: widget.child);
}
