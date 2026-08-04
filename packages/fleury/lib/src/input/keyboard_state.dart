// RFC 0020 Part I — the session keyboard model: semantic capabilities, the
// canonical press-record regularizer, and the frame-latched snapshot.
//
// This layer is the "honest physical record" (§6): it is fed the normalized
// key stream, repairs impossible phase sequences, maintains active press
// records, accumulates frame edges, and synthesizes releases ONLY on
// authority loss (blur/suspend/disconnect/restore/downgrade/replacement).
// Focus transitions never touch it — per-observer scope projection is the
// dispatcher's job, layered above.

import 'package:meta/meta.dart';

import 'events.dart';

/// What a keyboard surface has been *confirmed* to guarantee (RFC 0020
/// §5.7): semantic capabilities, never raw protocol flags, projected from
/// what negotiation confirmed — not what was requested.
@immutable
final class KeyboardCapabilities {
  const KeyboardCapabilities({
    this.supportsHeldState = false,
    this.distinguishesRepeats = false,
    this.supportsPositions = false,
    this.reportsPrintableKeys = false,
  });

  /// Reliable down/up for all ordinary keys — the gate for every sampled
  /// query. Kitty: flags 2∧8 confirmed. Web: true. Legacy: false.
  final bool supportsHeldState;

  /// Auto-repeat carries an event-type tag (for printables only where
  /// [reportsPrintableKeys] also holds). Informational — repeat policy is
  /// evaluated per event on [KeyEventType], never through this bit.
  final bool distinguishesRepeats;

  /// Positional identity is generally available. Still optional per event
  /// ([KeyEvent.position] stays nullable on every surface).
  final bool supportsPositions;

  /// Every printable arrives as a key event (kitty flag 8 / the DOM). The
  /// floor's tier requirement: raw-key consumers of printables (§17.4).
  final bool reportsPrintableKeys;

  /// The conservative default: press-only, best-effort input.
  static const KeyboardCapabilities legacy = KeyboardCapabilities();

  /// Everything confirmed — the DOM surface, and kitty lifecycle mode with
  /// flag 4 honored.
  static const KeyboardCapabilities full = KeyboardCapabilities(
    supportsHeldState: true,
    distinguishesRepeats: true,
    supportsPositions: true,
    reportsPrintableKeys: true,
  );

  @override
  bool operator ==(Object other) =>
      other is KeyboardCapabilities &&
      other.supportsHeldState == supportsHeldState &&
      other.distinguishesRepeats == distinguishesRepeats &&
      other.supportsPositions == supportsPositions &&
      other.reportsPrintableKeys == reportsPrintableKeys;

  @override
  int get hashCode => Object.hash(
    supportsHeldState,
    distinguishesRepeats,
    supportsPositions,
    reportsPrintableKeys,
  );

  @override
  String toString() =>
      'KeyboardCapabilities('
      '${[if (supportsHeldState) 'heldState', if (distinguishesRepeats) 'repeats', if (supportsPositions) 'positions', if (reportsPrintableKeys) 'printableKeys'].join(', ')}'
      ')';
}

/// One physically-held key as the session recorded it: the logical identity
/// captured at down, the positional identity when that press carried one.
@immutable
final class _PressRecord {
  const _PressRecord(this.code, this.position);

  final KeyCode code;
  final KeyPosition? position;

  /// §13.3 identity matching, per press: a known position matches by
  /// position only; an unknown one degrades one-way to the selector's US
  /// twin. Mirrors [KeyEvent.matches].
  bool matches(KeySelector selector) {
    if (selector is KeyCode) return code == selector;
    if (selector is KeyPosition) {
      final p = position;
      if (p != null) return p == selector;
      final twin = selector.usTwin;
      return twin != null && code == twin;
    }
    return false;
  }

  /// Map key: physical position when known (unique per physical key), else
  /// the logical code.
  Object get identity => position ?? code;
}

/// An immutable, frame-latched view of the session keyboard (RFC 0020
/// §5.6/§7): what is held, and which identities transitioned since the
/// previous latch. Edges are non-consuming and expire at the next latch
/// whether or not anyone read them; a paused consumer gets no backlog.
final class KeyboardSnapshot {
  KeyboardSnapshot._(
    List<_PressRecord> held,
    List<_PressRecord> downEdges,
    List<_PressRecord> upEdges,
    this.sessionGeneration,
    this.frameNumber,
  ) : _held = held,
      _downEdges = downEdges,
      _upEdges = upEdges;

  static final KeyboardSnapshot _empty = KeyboardSnapshot._(
    const [],
    const [],
    const [],
    0,
    0,
  );

  final List<_PressRecord> _held;
  final List<_PressRecord> _downEdges;
  final List<_PressRecord> _upEdges;

  /// Bumped when the input session is replaced (driver swap, reconnect);
  /// all prior state and edges are invalidated with it.
  final int sessionGeneration;

  /// The latch ordinal of the last input change this snapshot reflects.
  final int frameNumber;

  /// Logical identities currently down.
  Set<KeyCode> get pressed => {for (final r in _held) r.code};

  /// Positional identities currently down (presses that carried one).
  Set<KeyPosition> get positionsPressed => {
    for (final r in _held)
      if (r.position != null) r.position!,
  };

  /// Whether [selector]'s key is down right now (per-press §13.3 matching:
  /// positional when the press carried a position, else US-twin logical).
  bool isHeld(KeySelector selector) => _held.any((r) => r.matches(selector));

  /// Whether [selector]'s key transitioned down since the previous latch.
  /// Non-consuming; survives a press+release that lands entirely between
  /// two frames (the fixed-step-simulation contract, §7.2).
  bool wasPressed(KeySelector selector) =>
      _downEdges.any((r) => r.matches(selector));

  /// Whether [selector]'s key transitioned up since the previous latch.
  bool wasReleased(KeySelector selector) =>
      _upEdges.any((r) => r.matches(selector));

  @override
  String toString() =>
      'KeyboardSnapshot(held: ${_held.length}, +${_downEdges.length} '
      '-${_upEdges.length}, gen $sessionGeneration, frame $frameNumber)';
}

/// The outcome of regularizing one key event: the event stream downstream
/// lanes observe (possibly with a repair event prepended), preserving the
/// per-key one-down/n-repeats/one-up contract.
final class RegularizedKey {
  const RegularizedKey._(this.events);

  /// In order. One element in the common case; two when a repair event was
  /// synthesized (repeat-without-down → synthesized down + the repeat).
  final List<KeyEvent> events;
}

/// The canonical session keyboard: press records, phase repair, edge
/// accumulation, and snapshot publication. Owned by the input dispatcher;
/// one per running app.
final class KeyboardSession {
  KeyboardSession({
    KeyboardCapabilities capabilities = KeyboardCapabilities.legacy,
  }) : _capabilities = capabilities;

  KeyboardCapabilities _capabilities;
  KeyboardCapabilities get capabilities => _capabilities;

  /// Live press records, keyed by physical identity (position when known,
  /// else logical code).
  final Map<Object, _PressRecord> _held = {};

  /// Edge accumulators since the last latch.
  List<_PressRecord> _pendingDowns = [];
  List<_PressRecord> _pendingUps = [];

  int _sessionGeneration = 0;
  int _frameNumber = 0;
  bool _dirtySinceLatch = false;
  KeyboardSnapshot _latched = KeyboardSnapshot._empty;

  int get sessionGeneration => _sessionGeneration;

  /// The most recently published latch. Allocation-free when no input
  /// changed since the last publish (§19): the cached instance is returned.
  KeyboardSnapshot get snapshot => _latched;

  /// Replaces the effective capabilities (negotiation completing, a
  /// downgrade, a driver swap). Losing held-state support is authority
  /// loss: records are recovered per [loseAuthority].
  List<KeyEvent> updateCapabilities(KeyboardCapabilities next) {
    if (next == _capabilities) return const [];
    final losingState =
        _capabilities.supportsHeldState && !next.supportsHeldState;
    _capabilities = next;
    return losingState ? loseAuthority() : const [];
  }

  /// Ingests one key event from the normalized stream, updating records and
  /// edges, and returns the regularized event list downstream lanes must
  /// observe in order (§6's repair table):
  ///
  /// - duplicate down while held → demoted to a repeat;
  /// - repeat without a preceding down → synthesized down (command-eligible;
  ///   it stands in for a press that physically happened) + the repeat;
  /// - up for an unheld key → delivered for observability, records intact.
  ///
  /// On a surface without [KeyboardCapabilities.supportsHeldState] the
  /// session tracks nothing and repairs nothing — a release-less source's
  /// fresh downs are fresh presses, never "duplicates" (the test-harness
  /// and legacy-terminal profile).
  /// The map key of the held record [event] refers to, or null when nothing
  /// matching is held.
  ///
  /// Positional identity is optional **per event** even on a confirmed
  /// surface (RFC 0020 §4: flag 4 is "can send"; the DOM reports
  /// `Unidentified`), so the same physical key can arrive with a position
  /// once and without it the next time. Exact keying alone would then open
  /// a second record for a key already held and leave the first one
  /// unclosable — a silent stuck key. Fall back to §13.3's degradation so a
  /// mismatched pair still closes the press it opened.
  Object? _lookupHeld(KeyEvent event) {
    final exact = event.position ?? event.code;
    if (_held.containsKey(exact)) return exact;
    for (final MapEntry(key: id, value: record) in _held.entries) {
      if (record.matches(event.position ?? event.code)) return id;
      if (record.code == event.code) return id;
    }
    return null;
  }

  RegularizedKey ingest(KeyEvent event) {
    if (!_capabilities.supportsHeldState) {
      return RegularizedKey._([event]);
    }
    final record = _PressRecord(event.code, event.position);
    final id = record.identity;
    final heldId = _lookupHeld(event);
    switch (event.type) {
      case KeyEventType.down:
        if (heldId != null) {
          // Duplicate down while held: demote. State already says held.
          final demoted = KeyEvent(
            event.code,
            modifiers: event.modifiers,
            type: KeyEventType.repeat,
            position: event.position,
            synthesized: event.synthesized,
          );
          return RegularizedKey._([demoted]);
        }
        _held[id] = record;
        _pendingDowns.add(record);
        _dirtySinceLatch = true;
        return RegularizedKey._([event]);
      case KeyEventType.repeat:
        if (heldId == null) {
          // Repeat without down: the down physically happened and was
          // missed. Repair with a synthesized, command-eligible down.
          _held[id] = record;
          _pendingDowns.add(record);
          _dirtySinceLatch = true;
          final repair = KeyEvent(
            event.code,
            modifiers: event.modifiers,
            type: KeyEventType.down,
            position: event.position,
            synthesized: true,
          );
          return RegularizedKey._([repair, event]);
        }
        return RegularizedKey._([event]);
      case KeyEventType.up:
        // Close the record this release refers to, by ITS identity — which
        // may differ from this event's when position reporting is uneven.
        final held = heldId == null ? null : _held.remove(heldId);
        if (held != null) {
          _pendingUps.add(held);
          _dirtySinceLatch = true;
        }
        // Unheld up: observable, but corrupts nothing.
        return RegularizedKey._([event]);
    }
  }

  /// Synthesizes a release for every held key — the authority-loss triggers
  /// of §6 (blur, suspend, disconnect, terminal restore, protocol
  /// downgrade, session replacement). Returned events are observation-lane
  /// data; they never enter command dispatch and never complete a capture.
  List<KeyEvent> loseAuthority() {
    if (_held.isEmpty) return const [];
    final releases = <KeyEvent>[
      for (final record in _held.values)
        KeyEvent(
          record.code,
          type: KeyEventType.up,
          position: record.position,
          synthesized: true,
        ),
    ];
    _pendingUps.addAll(_held.values);
    _held.clear();
    _dirtySinceLatch = true;
    return releases;
  }

  /// Replaces the session (driver swap/reconnect): recovers held keys,
  /// drops pending edges, and bumps [sessionGeneration].
  List<KeyEvent> replaceSession() {
    final releases = loseAuthority();
    _pendingDowns = [];
    _pendingUps = [];
    _sessionGeneration++;
    _dirtySinceLatch = true;
    return releases;
  }

  /// Publishes the frame latch (§5.6 step 2): called once at frame start
  /// after input drains. Drains the edge accumulators into an immutable
  /// snapshot; allocation-free when nothing changed since the last publish
  /// AND the cached snapshot carries no edges (edges live for exactly one
  /// latch — a quiet frame after an edgeful one must expire them, or
  /// `wasPressed` would report a stale tap forever).
  KeyboardSnapshot publishLatch() {
    if (!_dirtySinceLatch) {
      if (_latched._downEdges.isEmpty && _latched._upEdges.isEmpty) {
        return _latched;
      }
      // Quiet frame after an edgeful one: same held state, edges expired.
      // A distinct ordinal, because the CONTENT differs — a consumer
      // memoizing "already handled ordinal N" must not confuse the edgeful
      // snapshot with its expired successor.
      _frameNumber++;
      _latched = KeyboardSnapshot._(
        _latched._held,
        const [],
        const [],
        _sessionGeneration,
        _frameNumber,
      );
      return _latched;
    }
    _frameNumber++;
    _latched = KeyboardSnapshot._(
      List.unmodifiable(_held.values),
      List.unmodifiable(_pendingDowns),
      List.unmodifiable(_pendingUps),
      _sessionGeneration,
      _frameNumber,
    );
    _pendingDowns = [];
    _pendingUps = [];
    _dirtySinceLatch = false;
    return _latched;
  }
}
