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
//   KeyBinding(.ctrl.s, onTrigger: save, label: 'Save')
//   KeyBinding.any([.j, .down], onTrigger: next, label: 'Next')
//   KeyBinding.event(.escape, onEvent: (e) { if (!close()) e.bubble(); })
//
// The common case is `onTrigger` (a zero-argument callback); reach for
// `KeyBinding.event` only when the handler needs the event — to control
// propagation via `event.bubble()` or to read which alias fired via
// `event.match`.

import 'package:meta/meta.dart';

import '../foundation/change_notifier.dart';
import '../foundation/collections.dart';
import '../input/events.dart';
import 'focus.dart';
import 'framework.dart';
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
/// `events.length == sequence.stepCount`. For a [KeyBinding.any], [sequence]
/// tells the handler which alias the user actually pressed.
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
  void set(PendingKeySequenceMatch? value) {
    if (identical(_value, value)) return;
    _value = value;
    notifyListeners();
  }
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

/// Passed to a [KeyBinding.event] handler. Exposes what matched ([match]),
/// the raw event(s), and per-dispatch propagation control ([bubble]).
///
/// **Consume (default):** do nothing; the event is claimed.
///
/// ```dart
/// KeyBinding.event(.ctrl.s, onEvent: (_) => save())
/// ```
///
/// **Conditionally propagate:** call [bubble] to let the event continue to
/// ancestor bindings, `Focus.onKey`, or globals instead of being consumed:
///
/// ```dart
/// KeyBinding.event(.tab, onEvent: (event) {
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

/// A zero-argument binding action — the common case, invoked when the
/// binding matches. The event is consumed. For propagation control or to
/// read the match, use [KeyBinding.event] with a [KeyBindingHandler].
typedef KeyBindingTrigger = void Function();

/// An event-aware binding handler. Synchronous; async work scheduled inside
/// runs after the dispatch decision, so propagation must be expressed
/// synchronously via [KeyBindingEvent.bubble].
typedef KeyBindingHandler = void Function(KeyBindingEvent event);

// ===========================================================================
// KeyBinding
// ===========================================================================

/// One key binding: a [KeySequence] (or several aliases that all fire the
/// same action), a handler, an optional hint-bar label, and an enabled flag.
///
/// **Common case** — a zero-argument [onTrigger]:
///
/// ```dart
/// KeyBinding(.ctrl.s, onTrigger: save, label: 'Save')
/// ```
///
/// **Event-aware** — [KeyBinding.event] for propagation control or reading
/// the match:
///
/// ```dart
/// KeyBinding.event(.escape, onEvent: (e) { if (!close()) e.bubble(); })
/// ```
///
/// **Aliases** — [KeyBinding.any]: several spellings, one action, one hint
/// entry. The first sequence is canonical for the hint bar:
///
/// ```dart
/// KeyBinding.any([.j, .down], onTrigger: next, label: 'Next')
/// ```
final class KeyBinding {
  /// Bind a single sequence to a zero-argument action.
  KeyBinding(
    KeySequence sequence, {
    required KeyBindingTrigger onTrigger,
    this.label,
    this.enabled = true,
    this.hideFromHintBar = false,
  }) : sequences = [sequence],
       onEvent = _triggerHandler(onTrigger);

  /// Bind a single sequence to an event-aware handler.
  KeyBinding.event(
    KeySequence sequence, {
    required this.onEvent,
    this.label,
    this.enabled = true,
    this.hideFromHintBar = false,
  }) : sequences = [sequence];

  /// Bind several alias sequences that all fire the same action. Provide
  /// exactly one of [onTrigger] or [onEvent]. The first sequence is the
  /// canonical one shown in the hint bar.
  KeyBinding.any(
    this.sequences, {
    KeyBindingTrigger? onTrigger,
    KeyBindingHandler? onEvent,
    this.label,
    this.enabled = true,
    this.hideFromHintBar = false,
  }) : assert(sequences.isNotEmpty, 'aliases list must be non-empty'),
       assert(
         (onTrigger == null) != (onEvent == null),
         'provide exactly one of onTrigger / onEvent',
       ),
       onEvent = onEvent ?? _triggerHandler(onTrigger!);

  static KeyBindingHandler _triggerHandler(KeyBindingTrigger onTrigger) =>
      (_) => onTrigger();

  /// The sequence(s) this binding matches. Any firing triggers [onEvent].
  /// The first is always canonical for hint-bar display.
  final List<KeySequence> sequences;

  /// Handler invoked when the binding matches. `onTrigger` bindings wrap
  /// their callback here; the dispatcher always calls this.
  final KeyBindingHandler onEvent;

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
  String get sequenceLabel => sequences.map((s) => s.hintLabel).join();
}

/// Resolves the discoverable key bindings active in [manager]'s focus context.
///
/// Resolution follows the same precedence as key dispatch: the deepest local
/// binding wins each sequence, with [globalBindings] considered last unless the
/// active focus scope suppresses globals. It also applies the framework's
/// user-facing discovery rules:
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
List<ActiveKeyBinding> resolveActiveKeyBindings(
  FocusManager manager, {
  List<KeyBinding> globalBindings = const <KeyBinding>[],
}) {
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
  if (!manager.suppressGlobals) {
    for (final binding in globalBindings) {
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
  const KeyBindings({super.key, required this.bindings, required this.child});

  final List<KeyBinding> bindings;
  final Widget child;

  /// The discoverable bindings active in [context]'s focus context — hint
  /// bars, help overlays, and command palettes read this instead of walking
  /// the focus tree. Rebuilds when focus moves or the active bindings change.
  ///
  /// `runApp`'s global bindings aren't in the tree, so pass them via
  /// [globalBindings] (as `KeyHintBar` does) to have them included.
  static List<ActiveKeyBinding> activeOf(
    BuildContext context, {
    List<KeyBinding> globalBindings = const <KeyBinding>[],
  }) {
    final manager = Focus.maybeOf(context);
    if (manager == null) return const <ActiveKeyBinding>[];
    return resolveActiveKeyBindings(manager, globalBindings: globalBindings);
  }

  /// The sequence the user is partway through typing, or null when none is in
  /// flight. Rebuilds when a leader is pressed, advanced, completed, or
  /// cancelled — a which-key popup depends on this. Null unless `runApp`
  /// installed a [PendingSequenceScope] (it does by default).
  static PendingKeySequenceMatch? pendingOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PendingSequenceScope>()
      ?.notifier
      .value;

  @override
  State<KeyBindings> createState() => _KeyBindingsState();
}

class _KeyBindingsState extends State<KeyBindings> implements KeyBindingSource {
  late final FocusNode _node;

  @override
  List<KeyBinding> get activeBindings => widget.bindings;

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
    _node.bindingSource = null;
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(focusNode: _node, child: widget.child);
  }
}
