// InputDispatcher: the central key router.
//
// Owns pending-sequence state, sequence timeouts, focus-chain walking,
// and global-bindings fallback. Per RFC 0008 §7, dispatch precedence is:
//
//   1. PENDING SEQUENCE: complete or cancel-and-redispatch.
//   2. FOCUS CHAIN, deepest first:
//      a. Direct match on a KeyBindings binding (binding wins).
//      b. Sequence-start match on a KeyBindings binding (begin pending).
//      c. Focus.onKey fallback (returns handled? consumed).
//      Modal FocusScope boundaries stop the walk.
//   3. GLOBALS (skipped if a modal scope set suppressGlobals).
//   4. IGNORED.

import 'dart:async';

import 'package:characters/characters.dart';

import '../input/events.dart';
import '../widgets/focus.dart';
import '../widgets/key_bindings.dart';
import '../widgets/pointer.dart';

/// Owns the runtime input pipeline. One instance per [runApp]. Tests
/// can construct one against a hand-built [FocusManager].
class InputDispatcher {
  InputDispatcher({
    required this.focusManager,
    this.pointerRouter,
    this.sequenceTimeout = const Duration(milliseconds: 500),
    List<KeyBinding> globalBindings = const [],
  }) : _globalBindings = globalBindings;

  /// The focus manager whose chain this dispatcher walks.
  final FocusManager focusManager;

  /// Routes mouse events to widget pointer regions (taps, hover, scroll).
  /// Null when pointer routing isn't installed.
  final PointerRouter? pointerRouter;

  /// How long to wait for a second key after a sequence's first chord
  /// matches before redispatching the first key as a normal event.
  final Duration sequenceTimeout;

  /// Bindings to consult after the focus chain ignores an event.
  /// Mutable so consumers can update it dynamically.
  List<KeyBinding> _globalBindings;

  List<KeyBinding> get globalBindings => _globalBindings;

  set globalBindings(List<KeyBinding> value) {
    _checkNotDisposed();
    _globalBindings = value;
  }

  _PendingSequence? _pending;
  Timer? _timer;
  bool _disposed = false;

  /// Whether a sequence is currently pending. Useful for tests.
  bool get hasPendingSequence => _pending != null;

  /// Routes [event] through the dispatch algorithm.
  ///
  /// Accepts the union of [KeyEvent] (chord-style routing through
  /// the focus chain + globals), [TextInputEvent] (insertable text
  /// routed to the nearest [TextInputClaimant]), [TextCompositionEvent]
  /// (IME lifecycle routed to the nearest [TextCompositionClaimant]),
  /// paste, and mouse. Other event types are ignored — the framework
  /// handles them outside the dispatcher.
  KeyEventResult dispatch(TuiEvent event) {
    _checkNotDisposed();
    if (event is TextInputEvent) {
      return _dispatchText(event);
    }
    if (event is TextCompositionEvent) {
      return _dispatchComposition(event);
    }
    if (event is PasteEvent) {
      return _dispatchPaste(event);
    }
    if (event is MouseEvent) {
      return _dispatchMouse(event);
    }
    if (event is KeyEvent) {
      return _dispatchKeyEvent(event);
    }
    return KeyEventResult.ignored;
  }

  /// Click-to-focus: a left-button press moves focus to the smallest
  /// (innermost) traversable focus node whose painted rect contains the
  /// pointer. Runs alongside [PointerRouter] (which handles taps, hover,
  /// and scroll) — clicking a focusable both activates and focuses it.
  ///
  /// While a modal scope is open, only nodes inside it are clickable —
  /// a stray click on a focusable behind a modal dialog must not change
  /// focus and slip past the modal boundary. Mouse-modal filtering is
  /// applied here (rather than via `traversalCandidates`) so a node
  /// that opted out of Tab traversal (`skipTraversal: true` — e.g. a
  /// Button) can still receive focus via click.
  KeyEventResult _dispatchMouse(MouseEvent event) {
    pointerRouter?.route(event);
    if (event.kind != MouseEventKind.down || event.button != MouseButton.left) {
      return KeyEventResult.ignored;
    }
    // An AbsorbPointer overlay (e.g. the floating debug panel) covering the
    // click blocks click-to-focus: focus rects carry no z-order against
    // overlays, so without this a click on the overlay would move focus to
    // whatever focusable is painted invisibly underneath it.
    if (pointerRouter?.focusAbsorbedAt(event.col, event.row) ?? false) {
      return KeyEventResult.handled;
    }
    FocusNode? best;
    var bestArea = 1 << 62;
    for (final node in focusManager.attachedNodes) {
      // Mouse-clickable: can request focus AND lives outside any
      // ExcludeFocus. We use `isClickable` (not `isTraversable`) so a
      // node that opted out of Tab (skipTraversal: true — e.g. Button)
      // still responds to a click.
      if (!focusManager.isClickable(node)) continue;
      if (!focusManager.isUnderActiveModal(node)) continue;
      final r = node.rect;
      if (r == null) continue;
      if (event.col < r.left ||
          event.col >= r.right ||
          event.row < r.top ||
          event.row >= r.bottom) {
        continue;
      }
      final area = (r.right - r.left) * (r.bottom - r.top);
      if (area < bestArea) {
        bestArea = area;
        best = node;
      }
    }
    if (best != null) {
      best.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _dispatchKeyEvent(KeyEvent event, {String? textOrigin}) {
    // Releases are transparent to bindings (RFC 0018 §5): a binding fires on
    // down/repeat only. Guarding here keeps a release from disturbing a
    // pending sequence, and means enabling Kitty event-type reporting can't
    // double-fire bindings. (Only reachable when that reporting is on;
    // otherwise every event arrives as `down`.)
    if (event.type == KeyEventType.up) return KeyEventResult.ignored;
    // 1. Pending sequence handling.
    if (_pending != null) {
      final result = _tryPendingSequence(event, textOrigin: textOrigin);
      if (result != null) return result;
      // Sequence cancelled; the held events were replayed. The current
      // event runs through full dispatch so it can start a fresh
      // sequence if applicable.
    }
    return _dispatchPlain(event, textOrigin: textOrigin);
  }

  /// Runs the pending-sequence machinery for [event]: completes or
  /// advances the sequence (non-null result), or cancels it — replaying
  /// every held event direct-only — and returns null so the caller
  /// dispatches [event] through its own normal path.
  KeyEventResult? _tryPendingSequence(KeyEvent event, {String? textOrigin}) {
    var pending = _pending;
    if (pending == null) return null;
    final activeCandidates = pending.candidates
        .where(_isBindingCurrentlyActive)
        .toList(growable: false);
    if (activeCandidates.length != pending.candidates.length) {
      if (activeCandidates.isEmpty) {
        // Input topology changed while the leader was held (for example an
        // ErrorBoundary contained the focused subtree). Never invoke a
        // captured handler directly after its source left the active chain.
        _cancelPendingAndRedispatchHeld();
        return null;
      }
      pending = _PendingSequence(
        events: pending.events,
        candidates: activeCandidates,
        texts: pending.texts,
      );
      _pending = pending;
    }
    final completed = pending.tryComplete(event);
    if (completed != null) {
      _clearPending();
      return _fire(completed.binding, completed.sequence, [
        ...pending.events,
        event,
      ]);
    }
    // Could the event extend the sequence by one more step?
    final survivors = pending.surviveOneMoreStep(event);
    if (survivors.isNotEmpty) {
      _pending = pending.advance(event, survivors, textOrigin);
      _timer?.cancel();
      _timer = Timer(sequenceTimeout, _onTimeout);
      return KeyEventResult.handled;
    }
    // Sequence didn't complete and didn't continue: cancel and
    // redispatch every event that was held; the caller dispatches the
    // current one.
    //
    // Replays go through direct-match-only — we just CANCELLED a
    // sequence, so re-arming pending on the same prefix (e.g.
    // replaying Space and immediately re-entering the Space-leader
    // sequence) would trap the dispatcher in a stale-pending loop.
    _cancelPendingAndRedispatchHeld();
    return null;
  }

  bool _isBindingCurrentlyActive(KeyBinding binding) {
    if (!binding.enabled) return false;
    for (final node in focusManager.activeChain()) {
      final source = node.bindingSource;
      if (source != null &&
          source.activeBindings.any((entry) => identical(entry, binding))) {
        return true;
      }
    }
    return !focusManager.suppressGlobals &&
        _globalBindings.any((entry) => identical(entry, binding));
  }

  /// Runs [binding]'s handler for a match of [sequence] that consumed
  /// [events], and returns the propagation decision. The handler may call
  /// `event.bubble()` to let the event continue propagating; otherwise it's
  /// consumed.
  static KeyEventResult _fire(
    KeyBinding binding,
    KeySequence sequence,
    List<KeyEvent> events,
  ) {
    final wrapped = KeyBindingEvent(KeySequenceMatch(sequence, events));
    binding.onEvent(wrapped);
    return wrapped.isBubbling ? KeyEventResult.ignored : KeyEventResult.handled;
  }

  /// Delivers [event] to the nearest [TextInputClaimant] in the focus
  /// chain. Per RFC 0008 §6.7, text input claims insertable
  /// characters before any ancestor `KeyBindings` can see them.
  /// Modifier chords arrive as `KeyEvent`s, not `TextInputEvent`s,
  /// so they bypass this path entirely.
  ///
  /// A pending sequence is consulted FIRST (dispatch precedence rule 1):
  /// the parser emits bare printables as `TextInputEvent`s, so a chord
  /// whose continuation step is a printable (`.ctrl.x.b`) completes here
  /// even while a text field is focused. Text that instead breaks the
  /// sequence cancels it — replaying the held keys direct-only — and is
  /// then delivered as ordinary text.
  KeyEventResult _dispatchText(TextInputEvent event) {
    if (_pending != null) {
      final keyEvent = _keyEventForText(event.text);
      if (keyEvent != null) {
        final result = _tryPendingSequence(keyEvent, textOrigin: event.text);
        if (result != null) return result;
      } else {
        // Multi-grapheme text (an input burst) can't be a sequence step.
        _cancelPendingAndRedispatchHeld();
      }
    }

    final textResult = _deliverText(event.text);
    if (textResult == KeyEventResult.handled) {
      return textResult;
    }

    final keyEvent = _keyEventForText(event.text);
    if (keyEvent != null) {
      return _dispatchKeyEvent(keyEvent, textOrigin: event.text);
    }

    return KeyEventResult.ignored;
  }

  /// Delivers a bracketed paste as bulk content to the nearest claimant.
  ///
  /// Paste is not equivalent to typed text: a focused text field should record
  /// one paste transaction, while non-text controls that claim single typed
  /// trigger characters should ignore pasted blobs.
  KeyEventResult _dispatchPaste(PasteEvent event) {
    if (_pending != null) {
      _cancelPendingAndRedispatchHeld();
    }
    return _deliverPaste(event);
  }

  /// Delivers IME composition lifecycle events to the nearest claimant.
  ///
  /// Composition is not ordinary printable text, so unclaimed composition
  /// events do not fall through to key bindings. Any pending leader sequence is
  /// canceled first because the user's text-editing interaction broke it.
  KeyEventResult _dispatchComposition(TextCompositionEvent event) {
    if (_pending != null) {
      _cancelPendingAndRedispatchHeld();
    }
    return _deliverComposition(event);
  }

  void _cancelPendingAndRedispatchHeld() {
    final pending = _pending;
    if (pending == null) return;
    _clearPending();
    _replayHeld(pending);
  }

  /// Replays events held by a cancelled/timed-out sequence. Text-origin
  /// steps are owed to the focused text claimant first — replaying them
  /// direct-only would silently eat the typed character; only unclaimed
  /// ones fall through to direct key dispatch. Key-origin steps replay
  /// direct-only so the same prefix cannot immediately re-arm pending.
  void _replayHeld(_PendingSequence pending) {
    for (var i = 0; i < pending.events.length; i++) {
      final text = pending.texts[i];
      if (text != null && _deliverText(text) == KeyEventResult.handled) {
        continue;
      }
      _dispatchPlain(pending.events[i], allowSequenceStart: false);
    }
  }

  /// Offers [text] to each [TextInputClaimant] up the focus chain until
  /// one consumes it.
  KeyEventResult _deliverText(String text) {
    for (final node in focusManager.activeChain()) {
      final claimant = node.textInputClaimant;
      if (claimant != null &&
          claimant.onTextInput(text) == KeyEventResult.handled) {
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Offers bracketed paste content to each [TextInputClaimant] up the focus
  /// chain until one consumes it.
  KeyEventResult _deliverPaste(PasteEvent event) {
    for (final node in focusManager.activeChain()) {
      final claimant = node.textInputClaimant;
      if (claimant == null) continue;
      final result = claimant is PasteEventClaimant
          ? (claimant as PasteEventClaimant).onPasteEvent(event)
          : claimant.onPaste(event.text);
      if (result == KeyEventResult.handled) {
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Offers IME composition content to each [TextCompositionClaimant] up the
  /// focus chain until one consumes it.
  KeyEventResult _deliverComposition(TextCompositionEvent event) {
    for (final node in focusManager.activeChain()) {
      final claimant = node.textCompositionClaimant;
      if (claimant == null) continue;
      final result = switch (event.kind) {
        TextCompositionEventKind.update => claimant.onTextCompositionUpdate(
          event.text ?? '',
        ),
        TextCompositionEventKind.commit => claimant.onTextCompositionCommit(
          event.text,
        ),
        TextCompositionEventKind.cancel => claimant.onTextCompositionCancel(),
      };
      if (result == KeyEventResult.handled) return result;
    }
    return KeyEventResult.ignored;
  }

  static KeyEvent? _keyEventForText(String text) {
    final iterator = text.characters.iterator;
    if (!iterator.moveNext()) return null;
    final grapheme = iterator.current;
    if (iterator.moveNext()) return null;
    return KeyEvent(KeyCode.char(grapheme));
  }

  KeyEventResult _dispatchPlain(
    KeyEvent event, {
    bool allowSequenceStart = true,
    String? textOrigin,
  }) {
    // Precedence (vim-style):
    //
    //   - At each node, *if any sequence-start candidate is present
    //     anywhere we'll consider* (this node or a deeper node we've
    //     already visited), a direct match here does NOT fire
    //     immediately. It's held; the timeout / cancel path replays
    //     it as a direct-only dispatch, finding the same match.
    //   - If no sequences are involved, direct fires immediately on
    //     the first (deepest) hit. Original behaviour preserved.
    //   - Replay dispatches (`allowSequenceStart: false`) skip the
    //     sequence-collection step entirely and use the older
    //     "direct wins immediately" semantics — that's why the
    //     replay path correctly finds the deferred direct.
    final sequenceCandidates = <KeyBinding>[];

    for (final node in focusManager.activeChain()) {
      final source = node.bindingSource;
      if (source != null) {
        if (allowSequenceStart) {
          final seqsHere = <KeyBinding>[];
          _collectSequenceStarts(source.activeBindings, event, seqsHere);
          sequenceCandidates.addAll(seqsHere);
          // Defer direct firing while any sequence is still on the
          // table (here or accumulated from a deeper node).
          if (sequenceCandidates.isEmpty) {
            final hit = _findDirectMatch(source.activeBindings, event);
            if (hit != null) {
              final result = _fire(hit.binding, hit.sequence, [event]);
              // Bindings that call event.bubble() return
              // KeyEventResult.ignored — continue walking ancestors so
              // an outer binding for the same sequence gets a chance.
              if (result == KeyEventResult.handled) return result;
            }
          }
        } else {
          // Replay mode: pre-sequence-rule semantics.
          final hit = _findDirectMatch(source.activeBindings, event);
          if (hit != null) {
            final result = _fire(hit.binding, hit.sequence, [event]);
            if (result == KeyEventResult.handled) return result;
          }
        }
      }

      // Focus.onKey fallback. Skip when this node belongs to a
      // KeyBindings (its onKey is null) — only direct Focus widgets
      // populate onKey.
      final handler = node.onKey;
      if (handler != null && handler(event) == KeyEventResult.handled) {
        return KeyEventResult.handled;
      }
    }

    // Sequence start, if any candidates emerged from the chain.
    if (allowSequenceStart && sequenceCandidates.isNotEmpty) {
      _startPending(event, sequenceCandidates, textOrigin);
      return KeyEventResult.handled;
    }

    // 3. Globals (when no modal scope suppresses them). Same
    // precedence rule as the focus chain: sequence-start defers
    // direct firing.
    if (!focusManager.suppressGlobals) {
      if (allowSequenceStart) {
        final globalSeqs = <KeyBinding>[];
        _collectSequenceStarts(_globalBindings, event, globalSeqs);
        if (globalSeqs.isNotEmpty) {
          _startPending(event, globalSeqs, textOrigin);
          return KeyEventResult.handled;
        }
      }
      final hit = _findDirectMatch(_globalBindings, event);
      if (hit != null) {
        final result = _fire(hit.binding, hit.sequence, [event]);
        if (result == KeyEventResult.handled) return result;
      }
    }

    return KeyEventResult.ignored;
  }

  /// Scans [bindings] for an enabled, single-step sequence that matches
  /// [event] directly. Returns the first hit (binding + the specific alias
  /// that matched), or null.
  static ({KeyBinding binding, KeySequence sequence})? _findDirectMatch(
    Iterable<KeyBinding> bindings,
    KeyEvent event,
  ) {
    for (final binding in bindings) {
      if (!binding.enabled) continue;
      for (final sequence in binding.sequences) {
        if (sequence.isSequence) continue;
        if (sequence.matches(event)) {
          return (binding: binding, sequence: sequence);
        }
      }
    }
    return null;
  }

  /// Appends each enabled binding whose multi-step sequence matches [event]
  /// at step 0 to [out].
  static void _collectSequenceStarts(
    Iterable<KeyBinding> bindings,
    KeyEvent event,
    List<KeyBinding> out,
  ) {
    for (final binding in bindings) {
      if (!binding.enabled) continue;
      for (final sequence in binding.sequences) {
        if (!sequence.isSequence) continue;
        if (sequence.matchesStepAt(0, event)) {
          out.add(binding);
          break;
        }
      }
    }
  }

  void _startPending(
    KeyEvent firstEvent,
    List<KeyBinding> candidates,
    String? textOrigin,
  ) {
    _clearPending();
    _pending = _PendingSequence(
      events: [firstEvent],
      candidates: candidates,
      texts: [textOrigin],
    );
    _timer = Timer(sequenceTimeout, _onTimeout);
  }

  void _onTimeout() {
    final pending = _pending;
    if (pending == null) return;
    _clearPending();
    _replayHeld(pending);
  }

  void _clearPending() {
    _pending = null;
    _timer?.cancel();
    _timer = null;
  }

  /// Releases pending-sequence resources. Idempotent. Called by
  /// `runApp` during teardown.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clearPending();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('InputDispatcher has been disposed.');
    }
  }
}

class _PendingSequence {
  _PendingSequence({
    required this.events,
    required this.candidates,
    required this.texts,
  });

  /// The events held by the dispatcher so far. `events[0]` is the
  /// first event that opened the sequence; subsequent events are
  /// continuations that survived [surviveOneMoreStep]. The number of
  /// held events equals the number of steps matched so far.
  final List<KeyEvent> events;

  /// Bindings whose sequence still has events held matched as a prefix.
  final List<KeyBinding> candidates;

  /// Per-held-event text origin: `texts[i]` is the original typed text
  /// when `events[i]` was synthesized from a [TextInputEvent], null for a
  /// real key event. On cancel/timeout a text-origin step is owed to the
  /// focused text claimant, not just direct key dispatch.
  final List<String?> texts;

  /// Tries to complete a candidate sequence with [event] as its final
  /// step. Returns the binding to fire and the specific alias that
  /// completed, or null if none completes here.
  ({KeyBinding binding, KeySequence sequence})? tryComplete(KeyEvent event) {
    final matchedSoFar = events.length;
    for (final binding in candidates) {
      for (final sequence in binding.sequences) {
        if (!sequence.isSequence) continue;
        if (sequence.stepCount != matchedSoFar + 1) continue;
        if (_prefixMatches(sequence, events) &&
            sequence.matchesStepAt(matchedSoFar, event)) {
          return (binding: binding, sequence: sequence);
        }
      }
    }
    return null;
  }

  /// Returns the subset of [candidates] whose sequence still has events
  /// matched as a strict prefix after appending [event] (i.e. still
  /// has at least one more step to go). Empty list means the pending
  /// state must be cancelled.
  List<KeyBinding> surviveOneMoreStep(KeyEvent event) {
    final matchedSoFar = events.length;
    final out = <KeyBinding>[];
    for (final binding in candidates) {
      for (final sequence in binding.sequences) {
        if (!sequence.isSequence) continue;
        if (sequence.stepCount <= matchedSoFar + 1) continue;
        if (_prefixMatches(sequence, events) &&
            sequence.matchesStepAt(matchedSoFar, event)) {
          out.add(binding);
          break;
        }
      }
    }
    return out;
  }

  /// Returns a new _PendingSequence with [event] appended and the
  /// survivor candidate list.
  _PendingSequence advance(
    KeyEvent event,
    List<KeyBinding> survivors,
    String? textOrigin,
  ) {
    return _PendingSequence(
      events: [...events, event],
      candidates: survivors,
      texts: [...texts, textOrigin],
    );
  }
}

bool _prefixMatches(KeySequence sequence, List<KeyEvent> events) {
  for (var i = 0; i < events.length; i++) {
    if (!sequence.matchesStepAt(i, events[i])) return false;
  }
  return true;
}
