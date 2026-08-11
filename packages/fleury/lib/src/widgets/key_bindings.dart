// KeyBinding, KeyBindings: the declarative input authoring surface.
//
// The pattern types a binding matches — [KeySequence], [KeyCode],
// [PendingKeySequence], and the dot-chain DSL (`.ctrl.s`, `.g.g`) — live in
// `lib/src/input/events.dart`, co-located with [KeyCode] and [KeyEvent].
// This file is the widget-layer binding: what fires when a sequence matches,
// how the hint bar reads it, and the [KeyBindings] widget that scopes it to a
// subtree. Sequence-pending state lives in the [InputDispatcher]
// (`lib/src/runtime/input_dispatcher.dart`).
//
// Authoring at a glance:
//
//   KeyBinding(.ctrl.s, onTrigger: (_) => save(), label: 'Save')
//   KeyBinding(.j, aliases: [.down], onTrigger: (_) => next(), label: 'Next')
//   KeyBinding(.escape, onTrigger: (e) { if (!close()) e.bubble(); })
//
// One constructor: `onTrigger` always receives the [KeyBindingEvent].
// Ignore it (`(_) => save()`) in the common case; read it to control
// propagation via `event.bubble()` or to see which alias fired via
// `event.match`.

import 'package:meta/meta.dart';

import '../foundation/change_notifier.dart';
import '../foundation/collections.dart';
import '../input/events.dart';
import '../input/keyboard_layout.dart';
import '../runtime/input_dispatcher.dart';
import 'focus.dart';
import 'framework.dart';
import 'keyboard.dart';
import 'inherited_notifier.dart';

// The pattern vocabulary a binding is written in lives in events.dart
// (co-located with KeyCode/KeyEvent). Re-export it so importing this binding
// surface is enough to author `.ctrl.s` / `.g.g` sequences.
export '../input/events.dart'
    show
        KeyCode,
        KeySequence,
        KeySequenceChain,
        PendingKeySequence,
        PendingKeySequenceChain;

// ===========================================================================
// KeySequenceMatch + KeyBindingEvent — what a handler receives.
// ===========================================================================

/// What a [KeyBinding] matched: the specific [sequence] (alias) that fired and
/// every [KeyEvent] it consumed.
///
/// For a single-step binding, [events] has one entry. For a multi-step
/// sequence (`.ctrl.x.ctrl.s`), it has one entry per step, in order, so
/// `events.length == sequence.stepCount`. For a binding with [KeyBinding.aliases],
/// [sequence] tells the handler which alias the user actually pressed.
@immutable
final class KeySequenceMatch {
  KeySequenceMatch(this.sequence, List<KeyEvent> events)
    : events = List<KeyEvent>.unmodifiable(events);

  /// The sequence (one of the binding's aliases) that matched.
  final KeySequence sequence;

  /// Every event consumed by the match, in order. Length equals
  /// [KeySequence.stepCount].
  final List<KeyEvent> events;
}

/// A snapshot of a sequence the user is partway through typing — the leader
/// (`Space`, `Ctrl+X`) has landed and the dispatcher is holding for the next
/// step. Read via [KeyBindings.pendingOf]; the value a which-key popup renders.
///
/// This is the *runtime* pending state (a match still being typed), distinct
/// from [PendingKeySequence] (an *authoring* expression still being written).
@immutable
final class PendingKeySequenceMatch {
  PendingKeySequenceMatch({
    required this.prefix,
    required List<KeyCompletion> completions,
  }) : completions = List<KeyCompletion>.unmodifiable(completions);

  /// The steps typed so far, as a complete [KeySequence] (e.g. `Space`,
  /// `Ctrl+X`). `prefix.hintLabel` renders it; `prefix == KeySequence.space`
  /// lets a popup pick a per-leader layout.
  final KeySequence prefix;

  /// The ways this pending match can complete — one per live next step.
  final List<KeyCompletion> completions;
}

/// One way a [PendingKeySequenceMatch] can continue: the label of the next
/// key ([next], e.g. `f`, `Ctrl+S`) and the [binding] it would fire.
@immutable
final class KeyCompletion {
  const KeyCompletion({required this.next, required this.binding});

  /// The remaining-step label — what to press next.
  final String next;

  /// The binding that completes on this step. Its [KeyBinding.displayLabel]
  /// names the action; an unlabeled binding is typically hidden from the popup.
  final KeyBinding binding;
}

/// Reactive holder for the dispatcher's current [PendingKeySequenceMatch].
///
/// One per `runApp`, owned by the `InputDispatcher` and shared with the widget
/// tree by [PendingSequenceScope]. Framework-internal: apps read the value via
/// [KeyBindings.pendingOf], never touch this directly.
final class PendingSequenceNotifier with ChangeNotifier {
  PendingKeySequenceMatch? _value;

  /// The current pending match, or null when no sequence is in flight.
  PendingKeySequenceMatch? get value => _value;

  /// Framework-only: the dispatcher publishes each pending-state change here.
  /// Skips notifying when the value is unchanged (the null→null clears).
  set value(PendingKeySequenceMatch? next) {
    if (identical(_value, next)) return;
    _value = next;
    notifyListeners();
  }

  /// Framework-only: the dispatcher installs its pending-cancel here so a
  /// which-key popup's close control can abandon the in-flight sequence from
  /// the widget tree (the value flows dispatcher→tree; this flows the cancel
  /// request tree→dispatcher). Apps go through [KeyBindings.cancelPending].
  VoidCallback? onCancel;

  /// Requests cancellation of the in-flight sequence, as if the user pressed
  /// Esc. No-op when nothing is pending or the dispatcher hasn't wired a
  /// handler.
  void cancel() => onCancel?.call();
}

/// Shares the runtime [PendingSequenceNotifier] with the widget tree.
/// Installed by `runApp`; depended on by [KeyBindings.pendingOf] so a
/// which-key widget rebuilds as a sequence is pressed, advanced, or cleared.
final class PendingSequenceScope
    extends InheritedNotifier<PendingSequenceNotifier> {
  const PendingSequenceScope({
    super.key,
    required super.notifier,
    required super.child,
  });
}

/// Passed to every [KeyBinding.onTrigger] handler. Exposes what matched
/// ([match]), the raw event(s), and per-dispatch propagation control
/// ([bubble]).
///
/// **Consume (default):** ignore the event; it is claimed.
///
/// ```dart
/// KeyBinding(.ctrl.s, onTrigger: (_) => save())
/// ```
///
/// **Conditionally propagate:** call [bubble] to let the event continue to
/// ancestor bindings, [KeyDetector]s, or globals instead of being consumed:
///
/// ```dart
/// KeyBinding(.tab, onTrigger: (event) {
///   if (!Focus.of(context).focusNext()) event.bubble();
/// })
/// ```
///
/// [bubble] is only honoured during synchronous handler execution — a call
/// after an `await` has no effect, since the propagation decision is already
/// made.
class KeyBindingEvent {
  /// Framework-only. The dispatcher builds one per fired binding; exposed so
  /// tests can invoke a handler without standing up a dispatcher.
  KeyBindingEvent(this.match);

  /// What matched — the alias that fired and the events it consumed.
  final KeySequenceMatch match;

  bool _shouldBubble = false;

  /// The final raw [KeyEvent] of the match (the last step). Sugar for
  /// `match.events.last`.
  KeyEvent get raw => match.events.last;

  /// Whether [bubble] has been called for this dispatch.
  bool get isBubbling => _shouldBubble;

  // Forwarding getters for the final event, so handlers can read it directly.
  KeyCode get code => raw.code;
  Set<KeyModifier> get modifiers => raw.modifiers;
  bool get hasCtrl => raw.hasCtrl;
  bool get hasAlt => raw.hasAlt;
  bool get hasShift => raw.hasShift;
  KeyEventType get type => raw.type;

  /// Let this event continue propagating instead of being consumed (the
  /// default). Must be called synchronously; see the class doc.
  void bubble() => _shouldBubble = true;
}

/// A binding action, invoked when the binding matches. The event is
/// consumed unless the handler calls [KeyBindingEvent.bubble].
///
/// Handlers always receive the event (RFC 0020 §14.1) — one signature for
/// every binding, with propagation control always to hand. Tear-offs
/// declare the parameter: `onTrigger: (_) => save()`.
///
/// Synchronous with respect to the dispatch decision: async work scheduled
/// inside runs after it, so propagation must be expressed synchronously.
typedef KeyBindingHandler = void Function(KeyBindingEvent event);

// ===========================================================================
// KeyBinding
// ===========================================================================

/// One key binding: a [KeySequence] (plus optional [aliases] that fire the
/// same action), a handler, an optional hint-bar label, and an enabled flag.
///
/// ```dart
/// KeyBinding(.ctrl.s, onTrigger: (_) => save(), label: 'Save')
/// KeyBinding(.g.g, onTrigger: (_) => top(), label: 'Top')
/// ```
///
/// **Aliases** — several spellings, one action, one hint entry. The primary
/// sequence is canonical for the hint bar:
///
/// ```dart
/// KeyBinding(.j, aliases: [.down], onTrigger: (_) => next(), label: 'Next')
/// ```
///
/// **Auto-repeat** — a binding fires once per physical press by default;
/// holding `Ctrl+S` must not re-save. Movement-style bindings opt in:
///
/// ```dart
/// KeyBinding(.j, includeRepeats: true, onTrigger: (_) => next())
/// ```
///
/// Where the surface cannot distinguish auto-repeat from a fresh press
/// (legacy terminals, plain printables outside lifecycle mode) suppression
/// is best-effort — the event simply arrives untagged and fires.
///
/// **Propagation** — a match consumes; [KeyBindingEvent.bubble] opts out:
///
/// ```dart
/// KeyBinding(.escape, onTrigger: (e) { if (!close()) e.bubble(); })
/// ```
final class KeyBinding {
  /// Bind a sequence (plus any [aliases]) to an action.
  KeyBinding(
    KeySequence sequence, {
    required this.onTrigger,
    List<KeySequence> aliases = const <KeySequence>[],
    this.includeRepeats = false,
    this.label,
    this.enabled = true,
    this.hideFromHintBar = false,
  }) : sequences = [sequence, ...aliases],
       onHoldStart = null,
       onHoldEnd = null;

  /// Bind a key to the *duration* of a press: [onHoldStart] on the down,
  /// [onHoldEnd] on its release — push-to-talk, hold-to-peek.
  ///
  /// Not a long-press: there is no threshold and no latency. Every keyboard
  /// press is a hold of some duration, so the start fires immediately and a
  /// brief tap is simply a brief hold (RFC 0020 §14.5).
  ///
  /// Exactly one end per start, always: the pairing rides the observation
  /// lane, so it survives command-lane consumption, and the end is
  /// synthesized on scope exit or authority loss (modal open, blur,
  /// disconnect). Inert where the surface reports no held state — never
  /// silently a toggle; branch on
  /// `Keyboard.of(context).capabilities.supportsHeldState` for a fallback.
  KeyBinding.hold(
    KeySequence key, {
    required KeyBindingHandler this.onHoldStart,
    required KeyBindingHandler this.onHoldEnd,
    this.label,
    this.enabled = true,
    this.hideFromHintBar = false,
  }) : assert(
         key.stepCount == 1,
         'a hold brackets one key press, not a multi-step sequence',
       ),
       sequences = [key],
       onTrigger = null,
       includeRepeats = false;

  /// The sequence(s) this binding matches. Any firing triggers [onTrigger].
  /// The first is always canonical for hint-bar display.
  final List<KeySequence> sequences;

  /// Handler invoked when the binding matches; null for a hold binding.
  final KeyBindingHandler? onTrigger;

  /// Press-duration handlers, non-null exactly for [KeyBinding.hold].
  final KeyBindingHandler? onHoldStart;
  final KeyBindingHandler? onHoldEnd;

  /// Whether this binding also fires on keyboard auto-repeat.
  final bool includeRepeats;

  /// Whether this binding brackets a press rather than firing on it.
  bool get isHold => onHoldStart != null;

  /// Short label shown by `KeyHintBar`. When null, the bar synthesises one
  /// from the primary sequence's [KeySequence.hintLabel]. A binding with
  /// `label == null` and `hideFromHintBar == false` is hidden from the bar —
  /// descriptive opt-in is required.
  final String? label;

  /// When false, the binding doesn't match and doesn't appear in the hint
  /// bar. Useful for context-sensitive shortcuts.
  final bool enabled;

  /// When true, the binding still fires but is hidden from `KeyHintBar`.
  /// Useful for ubiquitous bindings like Ctrl+C.
  final bool hideFromHintBar;

  /// The hint string to render — the explicit [label] if supplied, else the
  /// canonical sequence's auto-generated label.
  String get displayLabel => label ?? sequences.first.hintLabel;
}

/// A user-visible key binding resolved against the current focus context.
///
/// [sequences] contains only the aliases this binding can actually fire on
/// and owns at its position in the active focus chain. For example, while a
/// text input is focused, a `[j, ↓]` binding resolves to just `↓`; if a
/// deeper binding owns `↓`, the shallower binding resolves to just `j`.
///
/// Instances are produced by [resolveActiveKeyBindings]. The result and its
/// [sequences] list are immutable so help, hint, and inspection surfaces can
/// safely retain a resolution for the frame in which it was computed.
final class ActiveKeyBinding {
  ActiveKeyBinding._(this.binding, List<KeySequence> sequences)
    : sequences = List<KeySequence>.unmodifiable(sequences);

  /// The declarative binding that owns these effective [sequences].
  final KeyBinding binding;

  /// The binding aliases that are live and unshadowed in this focus context.
  final List<KeySequence> sequences;

  /// A combined label for all effective aliases, such as `↑↓`.
  ///
  /// Positional aliases render their US-QWERTY twin here, because a bare
  /// value type has no keyboard to ask. Surfaces that CAN ask — anything with
  /// a `BuildContext` — should call [labelWith] instead, so a `KeyPosition.w`
  /// control reads `Z` on AZERTY rather than lying (RFC 0020 §9).
  String get sequenceLabel => sequences.map((s) => s.hintLabel).join();

  /// [sequenceLabel] with each positional alias resolved against the caps
  /// this keyboard actually has.
  ///
  /// ```dart
  /// final layout = Keyboard.of(context).layout;
  /// Text('[${hint.labelWith(layout)}] ${hint.binding.displayLabel}');
  /// ```
  ///
  /// Identical to [sequenceLabel] for logical bindings, which is every
  /// binding that does not name a physical spot.
  String labelWith(KeyboardLayout layout) =>
      sequences.map(layout.labelForSequence).join();
}

/// Resolves the discoverable key bindings active in [manager]'s focus context.
///
/// Resolution follows the same precedence as key dispatch: the deepest local
/// binding wins each sequence. It also applies the framework's user-facing
/// discovery rules:
///
///  * bindings need an explicit [KeyBinding.label];
///  * disabled and [KeyBinding.hideFromHintBar] bindings are omitted;
///  * bare printable sequences swallowed by a focused text input are omitted;
///  * multi-alias bindings remain visible through any alias that can fire;
///  * duplicate and shadowed aliases are removed using canonical sequence
///    identity, not their rendered label.
///
/// The returned list is deepest-first and immutable. This is the canonical
/// resolution API for hint bars, help overlays, and keymap inspection; those
/// surfaces should not independently walk [FocusManager.activeChain].
List<ActiveKeyBinding> resolveActiveKeyBindings(FocusManager manager) {
  final result = <ActiveKeyBinding>[];
  // Canonical sequence identity mirrors dispatch. Differently spelled aliases
  // for the same firing event must not evade deeper-binding precedence.
  final seenSequences = <KeySequence>{};
  final textFocused = manager.focusedNodeClaimsText;

  void consider(KeyBinding binding) {
    if (binding.label == null) return;
    if (binding.hideFromHintBar) return;
    if (!binding.enabled) return;

    final firable = [
      for (final sequence in binding.sequences)
        if (!textFocused || !sequence.isShadowedByTextInput) sequence,
    ];
    if (firable.isEmpty) return;

    final owned = <KeySequence>[];
    for (final sequence in firable) {
      if (seenSequences.contains(sequence)) continue;
      if (!owned.contains(sequence)) owned.add(sequence);
    }
    if (owned.isEmpty) return;

    // Claim every firable alias, including aliases already represented by a
    // sibling alias in [owned]. Shallower bindings cannot fire those.
    seenSequences.addAll(firable);
    result.add(ActiveKeyBinding._(binding, owned));
  }

  for (final node in manager.activeChain()) {
    final source = node.bindingSource;
    if (source == null) continue;
    for (final binding in source.activeBindings) {
      consider(binding);
    }
  }
  return List<ActiveKeyBinding>.unmodifiable(result);
}

// ===========================================================================
// KeyBindings widget
// ===========================================================================

/// Declarative key bindings for a subtree.
///
/// ```dart
/// KeyBindings(
///   bindings: [
///     KeyBinding(.ctrl.s, onTrigger: _save, label: 'Save'),
///     KeyBinding(.escape, onTrigger: _cancel, label: 'Cancel'),
///   ],
///   child: app,
/// )
/// ```
///
/// `KeyBindings` wraps its child in a non-focusable `Focus` node (so it
/// appears in the focus chain but never becomes the focused node itself). The
/// bindings it carries are consulted by the `InputDispatcher` when a
/// `KeyEvent` reaches this node's spot in the chain.
class KeyBindings extends StatefulWidget {
  const KeyBindings({
    super.key,
    required this.bindings,
    this.modal = false,
    required this.child,
  });

  /// The shortcuts this scope declares. Each pairs a gesture with a handler
  /// and a label; the label is what [activeOf] surfaces (hint bars, help
  /// overlays) render, so a labelled binding documents itself.
  ///
  /// Keys match deepest-first, so an inner scope shadows an outer one without
  /// either side knowing about the other.
  final List<KeyBinding> bindings;

  /// Whether unmatched keys stop at this scope (RFC 0020 §14.3).
  ///
  /// A dialog binds y/n/Esc; a fat-fingered `j` matches nothing, and with
  /// `modal: false` it would sail past into the app behind. There is no
  /// handler in which to intercept that — the whole problem is that no
  /// handler runs — so the policy belongs to the scope, not to a row.
  ///
  /// `modal: true` blocks ancestor scopes, extending the focus system's
  /// existing modality to the key lane. Routed dialogs write nothing — not
  /// because Navigator sets this flag (it does not), but because a modal
  /// route's `FocusScope(modal: true)` already truncates the focus chain at
  /// the scope boundary. This flag exists for modal UI that is NOT a route:
  /// an inline command palette, a capture overlay. Per-key passthrough is a
  /// binding at THIS scope that matches and calls [KeyBindingEvent.bubble].
  final bool modal;

  /// The subtree these bindings cover. A key fires them when focus is on this
  /// subtree — the scope is where the widget sits, not the whole app.
  final Widget child;

  /// The discoverable bindings active in [context]'s focus context — hint
  /// bars, help overlays, and command palettes read this instead of walking
  /// the focus tree. Rebuilds when focus moves or the active bindings change.
  static List<ActiveKeyBinding> activeOf(BuildContext context) {
    final manager = Focus.maybeOf(context);
    if (manager == null) return const <ActiveKeyBinding>[];
    return resolveActiveKeyBindings(manager);
  }

  /// The sequence the user is partway through typing, or null when none is in
  /// flight. Rebuilds when a leader is pressed, advanced, completed, or
  /// cancelled — a which-key popup depends on this. Null unless `runApp`
  /// installed a [PendingSequenceScope] (it does by default).
  static PendingKeySequenceMatch? pendingOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PendingSequenceScope>()
      ?.notifier
      .value;

  /// Cancels the in-flight sequence [pendingOf] reports, as if the user
  /// pressed Esc — for a which-key popup's close control or any custom
  /// dismiss affordance. No-op when nothing is pending or no
  /// [PendingSequenceScope] is installed. Reads the scope WITHOUT a rebuild
  /// dependency (it's an action, not a value read).
  static void cancelPending(BuildContext context) => context
      .getInheritedWidgetOfExactType<PendingSequenceScope>()
      ?.notifier
      .cancel();

  @override
  State<KeyBindings> createState() => _KeyBindingsState();
}

class _KeyBindingsState extends State<KeyBindings> implements KeyBindingSource {
  late final FocusNode _node;

  /// Observation-lane registration, present only while this scope declares
  /// at least one [KeyBinding.hold] (RFC 0020 §14.5).
  ///
  /// Holds live on the observation lane rather than the command lane so
  /// their pairing survives everything that can eat a command: a descendant
  /// consuming the key, a modal boundary, an armed capture. That is what
  /// makes "exactly one end per start" hold — including the synthesized end
  /// the projector delivers when this scope leaves the active chain
  /// (modal-open) or the session loses authority (blur, disconnect).
  KeyPhaseObserverRegistration? _holdObserver;

  /// Keys currently held open by this scope's hold bindings, mapped to the
  /// binding that opened them, so an end pairs to the binding that saw the
  /// down even if the widget rebuilt in between.
  final Map<KeyCode, KeyBinding> _openHolds = {};

  @override
  List<KeyBinding> get activeBindings => widget.bindings;

  @override
  bool get isModalScope => widget.modal;

  @override
  void initState() {
    super.initState();
    _node = FocusNode(
      canRequestFocus: false,
      skipTraversal: true,
      debugLabel: 'KeyBindings',
    )..bindingSource = this;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncHoldObserver();
  }

  bool get _hasHolds => widget.bindings.any((b) => b.isHold);

  void _syncHoldObserver() {
    final dispatcher = KeyboardScope.maybeDispatcherOf(context);
    if (dispatcher == null) return;
    // Inert where the surface cannot report releases: registering would
    // fire starts that could never be paired with an end (§14.5).
    final supported = dispatcher.keyboardSession.capabilities.supportsHeldState;
    if (_hasHolds && supported && _holdObserver == null) {
      _holdObserver = dispatcher.addKeyObserver(_observeHold, anchor: _node);
    } else if ((!_hasHolds || !supported) && _holdObserver != null) {
      _holdObserver!.remove();
      _holdObserver = null;
      _openHolds.clear();
    }
  }

  /// The observation-lane callback: opens a hold on a matching down and
  /// closes it on the paired up (physical or synthesized). Repeats are
  /// meaningless to a hold — the key is already down.
  void _observeHold(KeyEvent event) {
    switch (event.type) {
      case KeyEventType.down:
        if (_openHolds.containsKey(event.code)) return;
        for (final binding in widget.bindings) {
          if (!binding.isHold || !binding.enabled) continue;
          if (!binding.sequences.first.matches(event)) continue;
          _openHolds[event.code] = binding;
          binding.onHoldStart!(
            KeyBindingEvent(KeySequenceMatch(binding.sequences.first, [event])),
          );
          return;
        }
      case KeyEventType.repeat:
        return;
      case KeyEventType.up:
        final binding = _openHolds.remove(event.code);
        if (binding == null) return;
        binding.onHoldEnd!(
          KeyBindingEvent(KeySequenceMatch(binding.sequences.first, [event])),
        );
    }
  }

  @override
  void didUpdateWidget(KeyBindings oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Labels/enabled/sequences may have changed without any focus movement —
    // tell the manager so listeners keyed to the *content* of the active
    // bindings (the hint bar) repaint. Compared by hint-relevant CONTENT, not
    // list identity: rebuilds routinely construct a fresh `bindings: [...]`
    // list with identical content (the navigator's route chrome does, on
    // every rebuild), and identity alone would notify → dependents rebuild →
    // fresh list → notify — a self-sustaining loop, since the Navigator itself
    // depends on the manager. Callbacks are deliberately ignored: the bar
    // renders sequences + labels, not handlers. The notify is
    // microtask-deferred by the manager (we're mid-build here).
    if (_hintContentChanged(oldWidget.bindings, widget.bindings)) {
      Focus.maybeOf(context)?.notifyBindingsChanged();
    }
    _syncHoldObserver();
  }

  static bool _hintContentChanged(List<KeyBinding> a, List<KeyBinding> b) {
    if (identical(a, b)) return false;
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.label != y.label ||
          x.enabled != y.enabled ||
          x.hideFromHintBar != y.hideFromHintBar) {
        return true;
      }
      if (!listEquals(x.sequences, y.sequences)) return true;
    }
    return false;
  }

  @override
  void dispose() {
    // Removing the registration synthesizes an end for anything still open
    // (the projector's scope-exit path), so a hold can never outlive its
    // scope with the action left running.
    _holdObserver?.remove();
    _openHolds.clear();
    _node.bindingSource = null;
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Modality is enforced by the dispatcher (via [isModalScope]), NOT by
    // wrapping in a modal FocusScope: that would truncate the focus chain
    // at this node, leaving a boundary binding that calls `bubble()` with
    // no ancestors to reach — and that bubble is exactly §14.3's per-key
    // passthrough.
    return Focus(focusNode: _node, child: widget.child);
  }
}
