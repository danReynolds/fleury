// InputDispatcher: the central key router.
//
// Owns pending-sequence state, sequence timeouts, focus-chain walking,
// and global-bindings fallback. Per RFC 0008 §7, dispatch precedence is:
//
//   1. PENDING SEQUENCE: complete or cancel-and-redispatch.
//   2. FOCUS CHAIN, deepest first:
//      a. Direct match on a KeyBindings binding (binding wins).
//      b. Sequence-start match on a KeyBindings binding (begin pending).
//      c. KeyDetector floor (consumes via KeyEvent.consume()).
//      Modal FocusScope boundaries stop the walk.
//   3. IGNORED.

import 'dart:async';

import 'package:characters/characters.dart';

import '../foundation/fleury_error.dart';
import '../input/events.dart';
import '../input/keyboard_state.dart';
import '../input/key_dispatch.dart';
import '../widgets/focus.dart';
import '../widgets/framework.dart';
import '../widgets/key_bindings.dart';
import '../widgets/pointer.dart';

/// Which view of one physical input step is being routed to bindings.
///
/// A capable source can report both a key (identity, position, modifiers) and
/// committed text. Those are alternatives for one sequence step, never two
/// consecutive steps: key-driven gestures get the former and logical
/// character gestures get the latter.
enum _BindingLane { all, key, text }

/// Owns the runtime input pipeline. One instance per [runApp]. Tests
/// can construct one against a hand-built [FocusManager].
class InputDispatcher {
  InputDispatcher({
    required this.focusManager,
    this.pointerRouter,
    this.sequenceTimeout = const Duration(milliseconds: 500),
  }) {
    // Let the widget tree abandon a pending sequence (a which-key popup's
    // close control) by routing the notifier's cancel back to us.
    pendingSequenceNotifier.onCancel = cancelPending;
    focusManager.addListener(_onFocusChanged);
  }

  /// The focus manager whose chain this dispatcher walks.
  final FocusManager focusManager;

  /// The canonical session keyboard (RFC 0020 §6): press records, phase
  /// repair, frame edges, capabilities. Fed by [dispatch]; latched once per
  /// frame by the frame driver; read by the sampling surface (P4's
  /// `Keyboard`) and this dispatcher's observation lane.
  late final KeyboardSession keyboardSession = KeyboardSession()
    // A surface caught not honouring the phases it claimed demotes itself to
    // press-only; the tree has to hear about it, or an app keeps offering a
    // hold-to-thrust control that can never end (§5.7).
    ..onCapabilitiesDemoted = _onCapabilitiesDemoted;

  void _onCapabilitiesDemoted(KeyboardCapabilities capabilities) {
    // Everything the session believed was held is gone; anything downstream
    // holding a press (a KeyBinding.hold, a game's own latch) must end it.
    for (final release in keyboardSession.drainDemotionReleases()) {
      _notifyKeyObservers(release);
    }
    onKeyboardCapabilitiesChanged?.call();
  }

  /// Framework-internal observation-lane registrations (RFC 0020 §5.5's
  /// internal lane; `KeyBinding.hold` and the keyboard inspector consume
  /// it). Empty for ordinary apps — the zero-observer path is one check.
  final List<KeyPhaseObserverRegistration> _keyObservers = [];

  /// Registers [observer] on the observation lane, scoped to the active
  /// focus subtree of [anchor] (null = app-wide). Framework-internal.
  KeyPhaseObserverRegistration addKeyObserver(
    void Function(KeyEvent event) observer, {
    FocusNode? anchor,
  }) {
    _checkNotDisposed();
    final registration = KeyPhaseObserverRegistration._(this, observer, anchor);
    _keyObservers.add(registration);
    return registration;
  }

  /// Routes mouse events to widget pointer regions (taps, hover, scroll).
  /// Null when pointer routing isn't installed.
  final PointerRouter? pointerRouter;

  /// How long to wait, after a sequence's prefix matches, before committing it
  /// as-is (vim's `timeoutlen`). This only bites an AMBIGUOUS prefix — one
  /// where a shorter binding also completes here (`g` vs `gg`) or a held
  /// printable is owed to a focused text field: on expiry that shorter binding
  /// fires / the char is delivered. A PURE prefix (nothing completes on the
  /// held keys — vim operator-pending `d`, a `Space` leader) has nothing to
  /// commit, so it does NOT time out: it stays pending until the next key or
  /// Esc, keeping a which-key popup on screen. See [_onTimeout].
  final Duration sequenceTimeout;

  _PendingSequence? _pendingSequence;
  Timer? _timer;
  bool _disposed = false;

  /// Reactive view of the current pending sequence, shared with the widget
  /// tree by `runApp` (via `PendingSequenceScope`) so a which-key widget can
  /// read it through `KeyBindings.pendingOf`. Updated whenever the pending
  /// state changes.
  final PendingSequenceNotifier pendingSequenceNotifier =
      PendingSequenceNotifier();

  // All pending-state transitions assign through this setter, so publishing
  // the reactive snapshot happens in exactly one place. Dispatch runs outside
  // the build phase, so notifying synchronously just marks which-key
  // dependents dirty for the next frame — no re-entrancy, no coalescing.
  _PendingSequence? get _pending => _pendingSequence;
  set _pending(_PendingSequence? value) {
    _pendingSequence = value;
    pendingSequenceNotifier.value = value == null ? null : _snapshotFor(value);
  }

  /// True while [_onTimeout] commits a held prefix: the state is still set but
  /// is being torn down.
  bool _committingPending = false;

  /// How many binding handlers this dispatcher has invoked. Only differences
  /// are meaningful (see [_fire] / [_replayHeld]); it may wrap in a very
  /// long-lived session, which is harmless for that use.
  int _firedCount = 0;

  /// The pending sequence a NEW input event may match against — null while a
  /// commit is in flight, so a binding that dispatches input from its handler
  /// cannot re-complete or re-replay the sequence being torn down.
  _PendingSequence? get _matchablePending =>
      _committingPending ? null : _pending;

  /// Whether a sequence is currently pending. Useful for tests.
  bool get hasPendingSequence => _pending != null;

  /// The insertion a consumed printable key half owes suppression to
  /// (§11): on surfaces that report printables as keys AND deliver their
  /// text separately, consuming the key must drop the matching text — and
  /// only that one. A non-matching insertion clears it rather than
  /// swallowing unrelated input.
  String? _suppressNextText;

  /// Abandons an in-flight sequence as if the user pressed Esc: held events
  /// replay (a shorter binding fires, a text-owed char reaches the field) and
  /// the pending state clears, dropping any which-key popup. No-op when
  /// nothing is pending. The widget tree reaches this via
  /// [KeyBindings.cancelPending] → [PendingSequenceNotifier.cancel].
  void cancelPending() {
    _checkNotDisposed();
    _cancelPendingAndRedispatchHeld();
  }

  /// Builds the public snapshot: the held prefix plus every live next step
  /// (the completions a which-key popup lists).
  PendingKeySequenceMatch _snapshotFor(_PendingSequence pending) {
    final completions = <KeyCompletion>[];
    for (final binding in pending.candidates) {
      if (!binding.enabled) continue;
      for (final sequence in binding.sequences) {
        if (sequence.stepCount <= pending.events.length) continue;
        if (!_prefixMatches(
          sequence,
          pending.events,
          pending.lanes,
          pending.texts,
        )) {
          continue;
        }
        final label = sequence.stepLabelAt(pending.events.length);
        if (label == null) continue;
        completions.add(KeyCompletion(next: label, binding: binding));
      }
    }
    return PendingKeySequenceMatch(
      prefix: KeySequence.fromEvents(pending.events),
      completions: completions,
    );
  }

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
    assert(() {
      _reportDeadControls();
      return true;
    }());
    if (event is InputBatch) {
      // A correlated key+text report (RFC 0020 §5). The key half feeds the
      // session/observation lanes and key-driven commands (positions, special
      // keys, actionable modifier chords); the text half drives text claimants
      // and produced-character commands. They are two views of one physical
      // step, so a consuming key view suppresses text and an ignored key view
      // cannot cancel a sequence before its text view is considered.
      final key = event.key;
      if (key != null) _regularizeAndObserve(key);
      // Stage 4: an armed capture takes the whole batch — key AND text —
      // ahead of every routed lane, but only AFTER the session and the
      // observation lane have seen it (a hold in flight must still end).
      if (key != null && _tryCapture(key)) return KeyEventResult.handled;
      // Stage 5 BEFORE stage 6 (§6): the key walk runs first, so a binding
      // can match identity the text half cannot carry — a positional
      // gesture has no text equivalent. A consumed key suppresses the
      // batch's text, which is what keeps a character binding from firing
      // twice for one press.
      final text = event.committedText;
      if (key != null && key.type != KeyEventType.up) {
        // A text-bearing key has two views of ONE physical step. Offer the
        // identity/position view first; if it cannot advance a pending
        // sequence, preserve that prefix for the committed-text view below.
        // This is what makes `.char(r'$')` layout-independent while still
        // giving positional and modified gestures precedence.
        if (_dispatchKeyEvent(
              key,
              lane: text == null ? _BindingLane.all : _BindingLane.key,
              preservePendingOnMiss:
                  text != null || _isLoneModifierKey(key.code),
            ) ==
            KeyEventResult.handled) {
          return KeyEventResult.handled;
        }
      }
      if (text != null) {
        // The key half already walked the routed lanes above.
        return _dispatchText(
          TextInputEvent(text),
          keyAlreadyWalked: key != null && key.type != KeyEventType.up,
          keyView: key != null && key.type != KeyEventType.up ? key : null,
        );
      }
      return KeyEventResult.ignored;
    }
    if (event is TextInputEvent) {
      final suppressed = _suppressNextText;
      if (suppressed != null) {
        _suppressNextText = null;
        if (event.text == suppressed) return KeyEventResult.handled;
      }
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
      _regularizeAndObserve(event);
      if (_tryCapture(event)) return KeyEventResult.handled;
      // Stage 5 (§6): the key walk runs before text. Where printables
      // arrive as key events (reportsPrintableKeys — the DOM source), the
      // committed text follows as a SEPARATE event, so a key consumed here
      // must suppress it (§11's keydown/input pairing) — otherwise one
      // press fires a character binding twice. The walk has to run first
      // regardless: a positional gesture matches an identity the text half
      // cannot carry.
      final splitText =
          keyboardSession.capabilities.reportsPrintableKeys &&
          event.code.isCharacter &&
          event.type != KeyEventType.up &&
          event.modifiers.every((m) => m == KeyModifier.shift);
      final result = _dispatchKeyEvent(
        event,
        lane: splitText ? _BindingLane.key : _BindingLane.all,
        // The DOM sends a printable keydown before its authoritative `input`
        // event. Lone modifiers likewise compose the next gesture instead of
        // being gesture steps themselves. Neither may break a prefix merely
        // because its other half has not arrived yet.
        preservePendingOnMiss: splitText || _isLoneModifierKey(event.code),
      );
      if (splitText) {
        if (result == KeyEventResult.handled) {
          // Drop the paired insertion, and only that one.
          _suppressNextText = event.code.character;
        }
        // Unconsumed: the text half still owns it, exactly as before.
        return KeyEventResult.ignored;
      }
      return result;
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

  /// Stage 2-3 of the batch pipeline (RFC 0020 §6): feed the session
  /// regularizer, then project the regularized stream to active observers.
  ///
  /// The command lane deliberately still receives the RAW event during this
  /// interim (repair-downs would double-fire with today's fire-on-repeat
  /// binding default; §12's `includeRepeats` flip in P4 makes the
  /// regularized stream safe for commands, and dispatch switches then).
  /// Under the legacy capability profile the regularizer is a passthrough,
  /// so this is a no-op cost on the typing path with no observers.
  void _regularizeAndObserve(KeyEvent event) {
    // Genuinely zero-cost when unused: a release-less source tracks no
    // press records, so with nobody observing there is nothing to compute
    // and nothing to allocate on the typing path (RFC 0020 §19).
    //
    // A positional report is the exception, because position reporting and
    // release reporting are INDEPENDENT capabilities — a surface can have one
    // without the other. Skipping those would mean the layout never learns on
    // exactly the terminals where a hint bar is otherwise stuck showing US
    // twins. Costs nothing on the surfaces this fast path was written for:
    // they carry no position, so they still short-circuit here.
    if (!keyboardSession.capabilities.supportsHeldState &&
        _keyObservers.isEmpty &&
        event.position == null) {
      return;
    }
    final regularized = keyboardSession.ingest(event);
    if (_keyObservers.isEmpty) return;
    for (final e in regularized.events) {
      _notifyKeyObservers(e);
    }
  }

  /// Applies confirmed keyboard capabilities, routing any recovery releases
  /// a downgrade produces to the observation lane.
  ///
  /// The seam exists so callers never reach into [keyboardSession] directly
  /// and drop those releases: losing held-state support mid-session clears
  /// the press records, and every open observer press must be closed with
  /// it or `KeyBinding.hold`'s one-end-per-start contract breaks (§10).
  /// Notified when the session catches a surface not honouring the phase
  /// reporting it claimed, so the host can republish `Keyboard.capabilities`
  /// and let apps re-branch their control schemes. Wired by `runApp`.
  /// Sink for developer warnings — problems in the APP rather than failures
  /// in the framework, which must be loud without killing the session. The
  /// runtime wires this to the same reporter uncaught errors use, so a
  /// warning gets stderr, the on-screen banner, and the debug shell's history
  /// instead of being written over the next frame.
  void Function(FleuryError warning)? onDeveloperWarning;

  /// Selectors already reported, so a control sampled every frame warns once.
  final Set<KeySelector> _deadControlsReported = <KeySelector>{};
  final Set<KeySelector> _deadControlSuspects = <KeySelector>{};
  KeyboardCapabilities? _deadControlsCapsSeen;

  /// Debug-only: catch a control that CANNOT work.
  ///
  /// Sampling a key (`keys.isHeld(...)`) on a surface that reports no held
  /// state returns false forever. That is fine when a [KeyBinding] carries
  /// the same key — the press-driven fallback every capability branch is
  /// supposed to have. With no binding, the control is simply dead, and the
  /// app looks broken with nothing anywhere saying why.
  ///
  /// The framework knows both halves: the capability, and every registered
  /// binding. It had simply never compared them. Shipped Asteroids sampling
  /// four movement controls behind a fallback that covered exactly one, and
  /// nothing said a word on any of the four terminals it was tested on.
  void _reportDeadControls() {
    final caps = keyboardSession.capabilities;
    if (!identical(caps, _deadControlsCapsSeen)) {
      // Capability transition: startup, negotiation, or a mid-session
      // demotion. Samples taken under the OLD capabilities describe the old
      // control scheme, and the app has not necessarily rebuilt for the new
      // one yet — capabilities are reactive, so its fallback bindings arrive
      // a render AFTER the flip, while (on the demotion path specifically)
      // the next auto-repeat arrives sooner. Reporting here fired a false
      // warning at exactly the app that branches correctly. Discard and
      // start clean; a genuinely dead control is re-sampled within a frame.
      _deadControlsCapsSeen = caps;
      _deadControlSuspects.clear();
      KeyboardSnapshot.debugTakeSampledSelectors();
      return;
    }
    if (caps.supportsHeldState) return;
    final sampled = KeyboardSnapshot.debugTakeSampledSelectors();
    if (sampled.isEmpty) return;
    // Both sides of the comparison lower to the LOGICAL key. KeyPosition
    // implements KeySequence, so positional bindings arrive here as
    // KeyPosition values — an `is KeyCode` filter alone silently dropped
    // them, and the warning fired on apps whose positional fallbacks were
    // exactly right. Chords and modified sequences stay excluded on purpose:
    // a `.ctrl.x` binding does not make a bare `x` sample live.
    KeyCode? lower(KeySequence sequence) => switch (sequence) {
      KeyCode() => sequence,
      KeyPosition() => sequence.usTwin,
      _ => null,
    };
    final covered = <KeyCode>{
      for (final active in resolveActiveKeyBindings(focusManager))
        for (final sequence in active.sequences)
          if (lower(sequence) case final code?) code,
    };
    for (final selector in sampled) {
      // Compare on the logical key: a positional sample is satisfied by a
      // binding on its US twin, which is exactly how the two degrade into
      // each other everywhere else (§13.3).
      final logical = switch (selector) {
        KeyCode() => selector,
        KeyPosition() => selector.usTwin,
        _ => null,
      };
      if (logical == null || covered.contains(logical)) {
        // Covered now. A suspect from an earlier check was a rebuild still
        // in flight, not a dead control — retire the suspicion.
        _deadControlSuspects.remove(selector);
        continue;
      }
      // Two sightings, not one: warn only when the selector was sampled and
      // uncovered on a PREVIOUS check too. One sighting can be a reactive
      // rebuild that has not rendered yet; a control that is still uncovered
      // when freshly-taken samples arrive at a later dispatch has had its
      // chance. Real consumers sample every frame, so a genuinely dead
      // control reaches its second sighting within one input event.
      if (_deadControlSuspects.add(selector)) continue;
      if (!_deadControlsReported.add(selector)) continue;
      onDeveloperWarning?.call(
        FleuryError(
          summary: 'Dead control: isHeld($selector) can never be true here.',
          details:
              'This app samples $selector, but this surface does not report '
              'held keys — so the read is false on every frame — and no '
              'KeyBinding covers $selector to carry it instead. The control '
              'does nothing on this terminal.',
          hint:
              'Add a KeyBinding for $selector (includeRepeats: true keeps it '
              'usable under auto-repeat, which arrives even where held state '
              'does not), or gate the sampled read behind '
              'Keyboard.of(context).capabilities.supportsHeldState.',
        ),
      );
    }
  }

  void Function()? onKeyboardCapabilitiesChanged;

  void updateKeyboardCapabilities(KeyboardCapabilities capabilities) {
    _checkNotDisposed();
    final releases = keyboardSession.updateCapabilities(capabilities);
    for (final release in releases) {
      _notifyKeyObservers(release);
    }
  }

  /// Releases every held key through the observation lane — the
  /// authority-loss path (§10) for a surface that will never report the
  /// real releases: terminal focus loss, suspend, disconnect.
  ///
  /// Unlike [replaceKeyboardSession] this keeps the session identity: the
  /// input source is the same one, it just stopped being able to see the
  /// keyboard for a while.
  void recoverHeldKeys() {
    _checkNotDisposed();
    for (final release in keyboardSession.loseAuthority()) {
      _notifyKeyObservers(release);
    }
  }

  /// Replaces the input session (driver swap, reconnect): recovers held
  /// keys through the observation lane, drops pending edges, and bumps
  /// `sessionGeneration` so sampled consumers can invalidate.
  void replaceKeyboardSession() {
    _checkNotDisposed();
    final releases = keyboardSession.replaceSession();
    for (final release in releases) {
      _notifyKeyObservers(release);
    }
  }

  // --- The capture gate (RFC 0020 §6 stage 4, §15) ------------------------

  Completer<KeyEvent?>? _capture;
  Element? _captureContext;

  /// Whether a `Keyboard.nextKey` capture is armed.
  bool get hasPendingCapture => _capture != null;

  /// Arms a one-shot capture, completing with the next user-originated key
  /// press — or null if [context] unmounts first.
  ///
  /// Scope-tied by signature: the caller cannot forget to cancel, and a
  /// capture can never outlive the UI that started it and silently eat the
  /// app's input.
  Future<KeyEvent?> captureNextKey(BuildContext context) {
    _checkNotDisposed();
    assert(
      _capture == null,
      'A Keyboard.nextKey() capture is already pending. Exactly one awaiter '
      'at a time: a second would race the first for the same keypress.',
    );
    final completer = Completer<KeyEvent?>();
    _capture = completer;
    _captureContext = context is Element ? context : null;
    return completer.future;
  }

  /// Completes an armed capture, or reports that this event isn't one it
  /// can take. Returns true when the batch's routed lanes must be skipped.
  bool _tryCapture(KeyEvent event) {
    final completer = _capture;
    if (completer == null) return false;
    // The context that armed it is gone: the UI moved on, so the capture
    // does too rather than eating this key (§15's null contract).
    final origin = _captureContext;
    if (origin != null && !origin.mounted) {
      _capture = null;
      _captureContext = null;
      completer.complete(null);
      return false;
    }
    // Recovery events are Fleury's, not the user's: a blur that closes a
    // held Ctrl must not "choose" Ctrl for a rebind row.
    if (event.synthesized) return false;
    if (event.type == KeyEventType.up) {
      // A lone modifier's release completes the capture (so sprint-on-Shift
      // stays bindable); every other release is just the tail of a press
      // the awaiter already saw or didn't want.
      if (!_isLoneModifierKey(event.code)) return false;
    } else if (event.type == KeyEventType.repeat) {
      return false; // one press, not its auto-repeat
    } else if (_isLoneModifierKey(event.code)) {
      // Wait for the chord: a modifier DOWN may still be joined by a key.
      return false;
    }
    _capture = null;
    _captureContext = null;
    completer.complete(event);
    return true;
  }

  static bool _isLoneModifierKey(KeyCode code) => switch (code.special) {
    SpecialKey.leftShift ||
    SpecialKey.rightShift ||
    SpecialKey.leftControl ||
    SpecialKey.rightControl ||
    SpecialKey.leftAlt ||
    SpecialKey.rightAlt ||
    SpecialKey.leftSuper ||
    SpecialKey.rightSuper ||
    SpecialKey.leftHyper ||
    SpecialKey.rightHyper ||
    SpecialKey.leftMeta ||
    SpecialKey.rightMeta ||
    SpecialKey.isoLevel3Shift ||
    SpecialKey.isoLevel5Shift => true,
    _ => false,
  };

  /// Focus moved: an observer whose anchor just left the active chain must
  /// close its open presses NOW, not whenever the next key happens to
  /// arrive. Push-to-talk over a modal is the case that makes the
  /// difference user-visible (§10, §14.5).
  void _onFocusChanged() {
    if (_keyObservers.isEmpty || _disposed) return;
    final chain = focusManager.activeChain();
    for (final registration in List.of(_keyObservers)) {
      if (registration._removed) continue;
      registration._projectScopeChange(chain);
    }
  }

  /// Delivers [event] to every scope-active observer, applying each
  /// registration's projection (RFC 0020 §10's observer-level contract):
  /// entering scope mid-press yields no phantom up; leaving scope while a
  /// seen key is held yields exactly one observer-local synthesized up;
  /// phases for downs an observer never saw are suppressed.
  void _notifyKeyObservers(KeyEvent event) {
    // Routing snapshot: registrations captured before callbacks run.
    final registrations = List.of(_keyObservers);
    final chain = focusManager.activeChain();
    for (final registration in registrations) {
      if (registration._removed) continue;
      registration._project(event, chain);
    }
  }

  KeyEventResult _dispatchKeyEvent(
    KeyEvent event, {
    String? textOrigin,
    _BindingLane lane = _BindingLane.all,
    bool preservePendingOnMiss = false,
  }) {
    // Releases are transparent to bindings (RFC 0018 §5): a binding fires on
    // down/repeat only. Guarding here keeps a release from disturbing a
    // pending sequence, and means enabling Kitty event-type reporting can't
    // double-fire bindings. (Only reachable when that reporting is on;
    // otherwise every event arrives as `down`.)
    if (event.type == KeyEventType.up) return KeyEventResult.ignored;
    // 1. Pending sequence handling.
    if (_matchablePending != null) {
      final result = _tryPendingSequence(
        event,
        textOrigin: textOrigin,
        lane: lane,
        preserveOnMiss: preservePendingOnMiss,
      );
      if (result != null) return result;
      // Sequence cancelled; the held events were replayed. The current
      // event runs through full dispatch so it can start a fresh
      // sequence if applicable.
    }
    return _dispatchPlain(event, textOrigin: textOrigin, lane: lane);
  }

  /// Runs the pending-sequence machinery for [event]. A non-null result means
  /// the sequence completed, advanced, or deliberately held its prefix for
  /// another view of the same physical step. Otherwise it cancels the
  /// sequence, replays every held event direct-only, and returns null so the
  /// caller dispatches [event] through its own normal path.
  KeyEventResult? _tryPendingSequence(
    KeyEvent event, {
    String? textOrigin,
    _BindingLane lane = _BindingLane.all,
    bool preserveOnMiss = false,
  }) {
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
        lanes: pending.lanes,
      );
      _pending = pending;
    }
    final completed = pending.tryComplete(event, lane, textOrigin);
    if (completed != null) {
      _clearPending();
      return _fire(completed.binding, completed.sequence, [
        ...pending.events,
        event,
      ]);
    }
    // Could the event extend the sequence by one more step?
    final survivors = pending.surviveOneMoreStep(event, lane, textOrigin);
    if (survivors.isNotEmpty) {
      _pending = pending.advance(event, survivors, textOrigin, lane);
      _timer?.cancel();
      _timer = Timer(sequenceTimeout, _onTimeout);
      return KeyEventResult.handled;
    }
    if (preserveOnMiss) {
      // This event is only a partial view of the user's next input step (a
      // modifier transition, or a printable key half whose committed text will
      // follow). Observation already saw it; the command lane waits without
      // advancing, cancelling, or extending the original timeout.
      return KeyEventResult.ignored;
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
    return false;
  }

  /// Runs [binding]'s handler for a match of [sequence] that consumed
  /// [events], and returns the propagation decision. The handler may call
  /// `event.bubble()` to let the event continue propagating; otherwise it's
  /// consumed.
  KeyEventResult _fire(
    KeyBinding binding,
    KeySequence sequence,
    List<KeyEvent> events,
  ) {
    final wrapped = KeyBindingEvent(KeySequenceMatch(sequence, events));
    // Count the INVOCATION, not the result: a handler that runs and then
    // calls `bubble()` reports `ignored` so ancestors get a turn, but its
    // action already happened. [_onTimeout] needs "did anything run", so a
    // bubbling shorter binding can't leave a prefix held open after it fired.
    _firedCount++;
    binding.onTrigger!(wrapped);
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
  KeyEventResult _dispatchText(
    TextInputEvent event, {
    bool keyAlreadyWalked = false,
    KeyEvent? keyView,
  }) {
    // A correlated batch already owns a truthful physical event. Reuse it for
    // the binding receipt while matching the authoritative committed text;
    // legacy and split DOM text still synthesize the compatibility event.
    final keyEvent = keyView ?? _keyEventForText(event.text);
    // An armed capture outranks every routed lane — including this one
    // (§17.2, "text-derived on legacy").
    //
    // Where the terminal reports printables only as bytes, a letter reaches
    // the dispatcher as text and never as a key event. Consulting the capture
    // gate only on the key path would mean `nextKey` silently ignores exactly
    // the keys it is usually waiting FOR: vim's `m<letter>`, a rebind row's
    // chosen character, quoted-insert. Worse than ignoring — the letter would
    // fall through and fire whatever ordinary binding owns it, so pressing
    // `a` at a mark prompt would open INSERT.
    //
    // Ahead of the pending-sequence check too: a capture is sequence-
    // bypassing by design, so an awaiter beats a half-typed chord.
    if (!keyAlreadyWalked && _capture != null) {
      if (keyEvent != null && _tryCapture(keyEvent)) {
        return KeyEventResult.handled;
      }
    }
    if (_matchablePending != null) {
      if (keyEvent != null) {
        final result = _tryPendingSequence(
          keyEvent,
          textOrigin: event.text,
          lane: _BindingLane.text,
        );
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

    // Character bindings are text-driven on every surface. On legacy input
    // this reconstruction is the only view of the press, so it also remains
    // the compatibility bridge to detectors (Tree/DataTable typeahead). On
    // correlated and DOM input the key view already visited detectors, so the
    // text view visits binding scopes only. That gives each binding one
    // eligible stage and each detector one physical delivery.
    if (keyEvent != null) {
      return _dispatchPlain(
        keyEvent,
        textOrigin: event.text,
        lane: _BindingLane.text,
        visitDetectors: !keyAlreadyWalked,
      );
    }

    return KeyEventResult.ignored;
  }

  /// Delivers a bracketed paste as bulk content to the nearest claimant.
  ///
  /// Paste is not equivalent to typed text: a focused text field should record
  /// one paste transaction, while non-text controls that claim single typed
  /// trigger characters should ignore pasted blobs.
  KeyEventResult _dispatchPaste(PasteEvent event) {
    if (_matchablePending != null) {
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
    if (_matchablePending != null) {
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

  /// Replays events held by a cancelled/timed-out sequence, and reports
  /// whether replaying committed anything. Text-origin steps are owed to the
  /// focused text claimant first — replaying them direct-only would silently
  /// eat the typed character; only unclaimed ones fall through to direct key
  /// dispatch. Key-origin steps replay direct-only so the same prefix cannot
  /// immediately re-arm pending.
  ///
  /// The return value is what lets [_onTimeout] tell an ambiguous prefix (a
  /// shorter binding or a held char owed to a field commits here) from a PURE
  /// prefix (nothing commits) without predicting it: it just tries, and a
  /// `false` means the held events landed nowhere.
  ///
  /// "Landed" means a handler RAN or text was DELIVERED — not that the result
  /// was `handled`. A binding that fires and then calls `bubble()` reports
  /// `ignored`, but its action already happened; treating that as "nothing
  /// committed" would hold the prefix open past an action the user already
  /// got, and let the next key fire the longer binding too.
  bool _replayHeld(_PendingSequence pending) {
    final firedBefore = _firedCount;
    var delivered = false;
    for (var i = 0; i < pending.events.length; i++) {
      final text = pending.texts[i];
      if (text != null && _deliverText(text) == KeyEventResult.handled) {
        delivered = true;
        continue;
      }
      _dispatchPlain(
        pending.events[i],
        allowSequenceStart: false,
        textOrigin: pending.texts[i],
        lane: pending.lanes[i],
        visitDetectors: true,
      );
    }
    return delivered || _firedCount != firedBefore;
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
    return KeyEvent(KeyCode.forCharacter(grapheme));
  }

  KeyEventResult _dispatchPlain(
    KeyEvent event, {
    bool allowSequenceStart = true,
    String? textOrigin,
    _BindingLane lane = _BindingLane.all,
    bool visitDetectors = true,
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
      // Whether a binding AT this node fired and chose to bubble — the
      // deliberate per-key passthrough that a modal boundary must honour.
      var bubbledHere = false;
      if (source != null) {
        if (allowSequenceStart) {
          final seqsHere = <KeyBinding>[];
          _collectSequenceStarts(
            source.activeBindings,
            event,
            seqsHere,
            lane,
            textOrigin,
          );
          sequenceCandidates.addAll(seqsHere);
          // Defer direct firing while any sequence is still on the
          // table (here or accumulated from a deeper node).
          if (sequenceCandidates.isEmpty) {
            final hit = _findDirectMatch(
              source.activeBindings,
              event,
              lane,
              textOrigin,
            );
            if (hit != null) {
              final result = _fire(hit.binding, hit.sequence, [event]);
              // Bindings that call event.bubble() return
              // KeyEventResult.ignored — continue walking ancestors so
              // an outer binding for the same sequence gets a chance.
              if (result == KeyEventResult.handled) return result;
              bubbledHere = true;
            }
          }
        } else {
          // Replay mode: pre-sequence-rule semantics.
          final hit = _findDirectMatch(
            source.activeBindings,
            event,
            lane,
            textOrigin,
          );
          if (hit != null) {
            final result = _fire(hit.binding, hit.sequence, [event]);
            if (result == KeyEventResult.handled) return result;
            bubbledHere = true;
          }
        }
      }

      // KeyDetector floor (RFC 0020 §17): a detector on this node peeks at
      // the event and consumes only what it uses. Propagate-by-default, so
      // an unconsumed key continues up the chain.
      final detector = visitDetectors ? node.keyDetector : null;
      if (detector != null &&
          KeyDispatchContext.run(() => detector(event), entitled: true)) {
        return KeyEventResult.handled;
      }

      // Modal boundary (§14.3): nothing at this scope claimed the key, so
      // the unmatched remainder stops here — ancestors and globals never
      // see it. Reaching this point means no binding here matched, OR one
      // matched and bubbled; a bubble is the deliberate per-key
      // passthrough, so it must NOT be trapped.
      if (source != null && source.isModalScope && !bubbledHere) {
        // Globals are suppressed with everything else: a modal surface
        // traps the unmatched remainder completely.
        return KeyEventResult.ignored;
      }
    }

    // Sequence start, if any candidates emerged from the chain.
    if (allowSequenceStart && sequenceCandidates.isNotEmpty) {
      _startPending(event, sequenceCandidates, textOrigin, lane);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Whether [binding] is eligible for [event]'s phase (RFC 0020 §14.2).
  ///
  /// Repeat policy is evaluated PER EVENT on the phase tag, never through a
  /// capability bit — which is what makes it honest per key class. Where a
  /// surface tags repeats (chords and functional keys at the default kitty
  /// tier; everything under lifecycle mode / the DOM) a default binding
  /// skips them, so holding Ctrl+S saves once. Where it cannot tag them the
  /// event simply arrives as a fresh `down` and fires, exactly as before.
  static bool _phaseEligible(KeyBinding binding, KeyEvent event) =>
      event.type != KeyEventType.repeat || binding.includeRepeats;

  /// Scans [bindings] for an enabled, single-step sequence that matches
  /// [event] directly. Returns the first hit (binding + the specific alias
  /// that matched), or null.
  static ({KeyBinding binding, KeySequence sequence})? _findDirectMatch(
    Iterable<KeyBinding> bindings,
    KeyEvent event,
    _BindingLane lane,
    String? textOrigin,
  ) {
    for (final binding in bindings) {
      if (!binding.enabled) continue;
      if (binding.isHold) continue; // holds ride the observation lane
      if (!_phaseEligible(binding, event)) continue;
      for (final sequence in binding.sequences) {
        if (sequence.isSequence) continue;
        if (_matchesStepInLane(sequence, 0, event, lane, textOrigin)) {
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
    _BindingLane lane,
    String? textOrigin,
  ) {
    for (final binding in bindings) {
      if (!binding.enabled) continue;
      if (binding.isHold) continue;
      // A repeat never ADVANCES or starts a sequence (§14.4): holding `g`
      // must not arm `gg`.
      if (event.type == KeyEventType.repeat) continue;
      for (final sequence in binding.sequences) {
        if (!sequence.isSequence) continue;
        if (_matchesStepInLane(sequence, 0, event, lane, textOrigin)) {
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
    _BindingLane lane,
  ) {
    _clearPending();
    _pending = _PendingSequence(
      events: [firstEvent],
      candidates: candidates,
      texts: [textOrigin],
      lanes: [lane],
    );
    _timer = Timer(sequenceTimeout, _onTimeout);
  }

  /// The sequence-timeout timer fired. `sequenceTimeout` exists to resolve the
  /// vim `timeoutlen` ambiguity — a shorter binding that completes on the held
  /// prefix (`g`) versus a longer one still being typed (`gg`) — so on expiry
  /// we try to commit the held prefix as if the sequence ended here. If that
  /// commits something (a deferred shorter binding fires, or a held printable
  /// owed to a focused text field is delivered), the sequence is resolved.
  ///
  /// If nothing commits, this is a PURE prefix — vim operator-pending `d`, a
  /// `Space` leader — with nothing to fall back to. It must NOT self-destruct
  /// on a timer: we keep it pending (with no timer re-armed) so a which-key
  /// popup stays on screen while the user reads it and can still complete it —
  /// or Esc / any other key cancels it. This matches which-key.nvim / emacs.
  /// The pending state is left untouched in that case (not cleared and
  /// restored), so the pending-sequence notifier never round-trips through
  /// null and the popup doesn't flicker.
  void _onTimeout() {
    final pending = _pending;
    if (pending == null) return;
    // The one-shot timer has fired; drop the handle before replaying so a
    // committing handler sees a clean timer slot.
    _timer = null;
    // Replay with the pending state still set — the replay path
    // (_deliverText / direct-only _dispatchPlain) never reads _pending, so a
    // pure prefix that commits nothing can stay held without a null blip.
    //
    // But a binding the replay FIRES may synchronously dispatch more input,
    // and that nested dispatch must not match against the sequence we are
    // tearing down (it would re-complete or re-replay it). Hold the state
    // inert for the duration — the moral equivalent of the clear-then-replay
    // this replaced, without the notifier round-trip through null.
    _committingPending = true;
    final bool committed;
    try {
      committed = _replayHeld(pending);
    } finally {
      _committingPending = false;
    }
    // Clear only what we actually committed: a handler that dispatched during
    // the replay may have legitimately opened a NEW sequence, and that one is
    // not ours to discard.
    if (committed && identical(_pending, pending)) _clearPending();
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
    focusManager.removeListener(_onFocusChanged);
    // An armed capture cannot outlive the dispatcher: complete it with the
    // documented null rather than leaving an awaiter hanging forever.
    _capture?.complete(null);
    _capture = null;
    _captureContext = null;
    _disposed = true;
    // Teardown is authority loss (RFC 0020 §6): recover held keys so every
    // observer's stream closes its open presses (one up per down, always).
    final releases = keyboardSession.loseAuthority();
    for (final release in releases) {
      _notifyKeyObservers(release);
    }
    for (final registration in List.of(_keyObservers)) {
      registration._exitScope();
    }
    _keyObservers.clear();
    _clearPending();
    // Unhook before disposing: this both drops the notifier's reference back
    // to us and makes a late `cancel()` (a click racing teardown) a silent
    // no-op instead of a disposed-dispatcher throw.
    pendingSequenceNotifier.onCancel = null;
    pendingSequenceNotifier.dispose();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('InputDispatcher has been disposed.');
    }
  }
}

/// One observation-lane registration and its scope projection (RFC 0020
/// §10's observer-level stream contract). Framework-internal: created via
/// [InputDispatcher.addKeyObserver], consumed by `KeyBinding.hold` and the
/// keyboard inspector.
///
/// The projector guarantees, per registration: every observed `up` was
/// preceded by this observer's own observed `down`, and every observed
/// `down` is followed by exactly one `up` — physical, or synthesized when
/// the observer leaves scope (or is removed) while a seen key is held. It
/// never mutates session state: the session stays the honest physical
/// record while each observer gets a scope-consistent projection.
final class KeyPhaseObserverRegistration {
  KeyPhaseObserverRegistration._(
    this._dispatcher,
    this._observer,
    this._anchor,
  );

  final InputDispatcher _dispatcher;
  final void Function(KeyEvent event) _observer;
  final FocusNode? _anchor;

  /// Presses this observer has seen the down for, by physical identity.
  final Map<Object, KeyEvent> _seen = {};
  bool _removed = false;

  void _project(KeyEvent event, List<FocusNode> chain) {
    final anchor = _anchor;
    final active = anchor == null || chain.contains(anchor);
    if (!active) {
      // Scope exit: close open presses with observer-local synthesized
      // releases; the current event is not observed (its down, if any,
      // belongs to whoever is in scope now).
      _exitScope();
      return;
    }
    final id = event.position ?? event.code;
    switch (event.type) {
      case KeyEventType.down:
        _seen[id] = event;
        _observer(event);
      case KeyEventType.repeat:
        // Repeats for downs never seen are suppressed — an observer that
        // entered scope mid-press hears nothing until a fresh press.
        if (_seen.containsKey(id)) _observer(event);
      case KeyEventType.up:
        if (_seen.remove(id) != null) _observer(event);
    }
  }

  /// Focus changed: close open presses if this registration's anchor is no
  /// longer in the active chain. An app-wide observer (null anchor) never
  /// leaves scope.
  void _projectScopeChange(List<FocusNode> chain) {
    final anchor = _anchor;
    if (anchor == null) return;
    if (!chain.contains(anchor)) _exitScope();
  }

  void _exitScope() {
    if (_seen.isEmpty) return;
    final open = List.of(_seen.values);
    _seen.clear();
    for (final down in open) {
      _observer(
        KeyEvent(
          down.code,
          type: KeyEventType.up,
          position: down.position,
          synthesized: true,
        ),
      );
    }
  }

  /// Unregisters. Open presses are closed first (synthesized releases) so
  /// the one-up-per-down contract holds through removal — a disposing hold
  /// widget receives its end callback before detaching.
  void remove() {
    if (_removed) return;
    _removed = true;
    _exitScope();
    _dispatcher._keyObservers.remove(this);
  }
}

class _PendingSequence {
  _PendingSequence({
    required this.events,
    required this.candidates,
    required this.texts,
    required this.lanes,
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

  /// Which command view matched each held event. This keeps aliases honest:
  /// a physical match cannot later masquerade as a logical-text prefix merely
  /// because both views happen to share a codepoint on one layout.
  final List<_BindingLane> lanes;

  /// Tries to complete a candidate sequence with [event] as its final
  /// step. Returns the binding to fire and the specific alias that
  /// completed, or null if none completes here.
  ({KeyBinding binding, KeySequence sequence})? tryComplete(
    KeyEvent event,
    _BindingLane lane,
    String? textOrigin,
  ) {
    final matchedSoFar = events.length;
    for (final binding in candidates) {
      for (final sequence in binding.sequences) {
        if (!sequence.isSequence) continue;
        if (sequence.stepCount != matchedSoFar + 1) continue;
        if (_prefixMatches(sequence, events, lanes, texts) &&
            _matchesStepInLane(
              sequence,
              matchedSoFar,
              event,
              lane,
              textOrigin,
            )) {
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
  List<KeyBinding> surviveOneMoreStep(
    KeyEvent event,
    _BindingLane lane,
    String? textOrigin,
  ) {
    final matchedSoFar = events.length;
    final out = <KeyBinding>[];
    for (final binding in candidates) {
      for (final sequence in binding.sequences) {
        if (!sequence.isSequence) continue;
        if (sequence.stepCount <= matchedSoFar + 1) continue;
        if (_prefixMatches(sequence, events, lanes, texts) &&
            _matchesStepInLane(
              sequence,
              matchedSoFar,
              event,
              lane,
              textOrigin,
            )) {
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
    _BindingLane lane,
  ) {
    return _PendingSequence(
      events: [...events, event],
      candidates: survivors,
      texts: [...texts, textOrigin],
      lanes: [...lanes, lane],
    );
  }
}

bool _prefixMatches(
  KeySequence sequence,
  List<KeyEvent> events,
  List<_BindingLane> lanes,
  List<String?> texts,
) {
  for (var i = 0; i < events.length; i++) {
    if (!_matchesStepInLane(sequence, i, events[i], lanes[i], texts[i])) {
      return false;
    }
  }
  return true;
}

bool _matchesStepInLane(
  KeySequence sequence,
  int index,
  KeyEvent event,
  _BindingLane lane,
  String? textOrigin,
) {
  return sequence.matchesStepAt(
    index,
    event,
    textDriven: switch (lane) {
      _BindingLane.all => null,
      _BindingLane.key => false,
      _BindingLane.text => true,
    },
    committedText: lane == _BindingLane.text ? textOrigin : null,
  );
}
