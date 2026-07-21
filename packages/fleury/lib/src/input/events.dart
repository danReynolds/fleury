import 'package:meta/meta.dart';

import '../foundation/geometry.dart';

/// The non-character keys a terminal can report, as an enumerable set.
///
/// This is the *implementation vocabulary* behind the special-key half of
/// [KeyCode]; application code compares codes directly
/// (`event.code == KeyCode.enter`) and rarely needs to name this type.
enum SpecialKey {
  enter,
  tab,
  backspace,
  escape,
  arrowUp,
  arrowDown,
  arrowLeft,
  arrowRight,
  home,
  end,
  pageUp,
  pageDown,
  insert,
  delete,
  f1,
  f2,
  f3,
  f4,
  f5,
  f6,
  f7,
  f8,
  f9,
  f10,
  f11,
  f12,
}

/// One logical key: a printable character or a special key.
///
/// `KeyCode` unifies the two vocabularies a terminal reports — characters
/// (`KeyCode.char('a')`, `KeyCode.char('?')`) and specials
/// ([KeyCode.enter], [KeyCode.f1], …) — into a single value type with
/// structural equality, so `KeyCode.a == KeyCode.char('a')` and codes work
/// as map keys and in `case` patterns.
///
/// A `KeyCode` names the key itself, never its modifiers: Ctrl+C is a
/// [KeyEvent] carrying `KeyCode.c` plus `{KeyModifier.ctrl}`. Committed
/// text (IME composition, paste, multi-grapheme input) is not a keypress
/// and arrives as [TextInputEvent], never as a code.
///
/// Per RFC 0018, `KeyCode` is the one-step, unmodified form of a
/// [KeySequence]: every `KeyCode` is a valid single-key sequence, so `.enter`
/// and `.char('?')` bind directly, while `.ctrl.s` and `.g.g` are the
/// modified/multi-step sequences.
@immutable
final class KeyCode extends KeySequence {
  /// A printable-character key.
  ///
  /// [character] must be a single grapheme cluster (one user-perceived
  /// character); the parsers, dispatcher, and codec only construct such
  /// values. Matching against events uses the character exactly as given.
  const KeyCode.char(String this.character)
    : special = null,
      assert(character.length > 0, 'character must be non-empty'),
      super._();

  const KeyCode._special(this.special) : character = null, super._();

  /// Looks up the canonical const instance for [key].
  ///
  /// For construction from a [SpecialKey] held in a variable (parsers, the
  /// wire codec). With a known key, prefer the named static
  /// (`KeyCode.enter`).
  static KeyCode forSpecial(SpecialKey key) {
    final code = _bySpecial[key.index];
    assert(code.special == key, 'canonical-instance table out of order');
    return code;
  }

  /// The printable character, or null for a special key.
  final String? character;

  /// The special key, or null for a printable character.
  final SpecialKey? special;

  /// Whether this code is a printable character (as opposed to a special
  /// key).
  bool get isCharacter => character != null;

  // Letters. Uppercase letters are the shifted *characters* ('A'), not
  // distinct codes: `KeyCode.char('A')` is what Shift+A produces.
  static const KeyCode a = KeyCode.char('a');
  static const KeyCode b = KeyCode.char('b');
  static const KeyCode c = KeyCode.char('c');
  static const KeyCode d = KeyCode.char('d');
  static const KeyCode e = KeyCode.char('e');
  static const KeyCode f = KeyCode.char('f');
  static const KeyCode g = KeyCode.char('g');
  static const KeyCode h = KeyCode.char('h');
  static const KeyCode i = KeyCode.char('i');
  static const KeyCode j = KeyCode.char('j');
  static const KeyCode k = KeyCode.char('k');
  static const KeyCode l = KeyCode.char('l');
  static const KeyCode m = KeyCode.char('m');
  static const KeyCode n = KeyCode.char('n');
  static const KeyCode o = KeyCode.char('o');
  static const KeyCode p = KeyCode.char('p');
  static const KeyCode q = KeyCode.char('q');
  static const KeyCode r = KeyCode.char('r');
  static const KeyCode s = KeyCode.char('s');
  static const KeyCode t = KeyCode.char('t');
  static const KeyCode u = KeyCode.char('u');
  static const KeyCode v = KeyCode.char('v');
  static const KeyCode w = KeyCode.char('w');
  static const KeyCode x = KeyCode.char('x');
  static const KeyCode y = KeyCode.char('y');
  static const KeyCode z = KeyCode.char('z');

  static const KeyCode space = KeyCode.char(' ');

  // Specials.
  static const KeyCode enter = KeyCode._special(SpecialKey.enter);
  static const KeyCode tab = KeyCode._special(SpecialKey.tab);
  static const KeyCode backspace = KeyCode._special(SpecialKey.backspace);
  static const KeyCode escape = KeyCode._special(SpecialKey.escape);
  static const KeyCode arrowUp = KeyCode._special(SpecialKey.arrowUp);
  static const KeyCode arrowDown = KeyCode._special(SpecialKey.arrowDown);
  static const KeyCode arrowLeft = KeyCode._special(SpecialKey.arrowLeft);
  static const KeyCode arrowRight = KeyCode._special(SpecialKey.arrowRight);
  static const KeyCode home = KeyCode._special(SpecialKey.home);
  static const KeyCode end = KeyCode._special(SpecialKey.end);
  static const KeyCode pageUp = KeyCode._special(SpecialKey.pageUp);
  static const KeyCode pageDown = KeyCode._special(SpecialKey.pageDown);
  static const KeyCode insert = KeyCode._special(SpecialKey.insert);
  static const KeyCode delete = KeyCode._special(SpecialKey.delete);
  static const KeyCode f1 = KeyCode._special(SpecialKey.f1);
  static const KeyCode f2 = KeyCode._special(SpecialKey.f2);
  static const KeyCode f3 = KeyCode._special(SpecialKey.f3);
  static const KeyCode f4 = KeyCode._special(SpecialKey.f4);
  static const KeyCode f5 = KeyCode._special(SpecialKey.f5);
  static const KeyCode f6 = KeyCode._special(SpecialKey.f6);
  static const KeyCode f7 = KeyCode._special(SpecialKey.f7);
  static const KeyCode f8 = KeyCode._special(SpecialKey.f8);
  static const KeyCode f9 = KeyCode._special(SpecialKey.f9);
  static const KeyCode f10 = KeyCode._special(SpecialKey.f10);
  static const KeyCode f11 = KeyCode._special(SpecialKey.f11);
  static const KeyCode f12 = KeyCode._special(SpecialKey.f12);

  /// Canonical instances indexed by [SpecialKey.index] for [forSpecial].
  static const List<KeyCode> _bySpecial = [
    enter, tab, backspace, escape, //
    arrowUp, arrowDown, arrowLeft, arrowRight, //
    home, end, pageUp, pageDown, insert, delete, //
    f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12,
  ];

  @override
  bool operator ==(Object other) =>
      other is KeyCode &&
      other.character == character &&
      other.special == special;

  @override
  int get hashCode => Object.hash(KeyCode, character, special);

  @override
  String toString() {
    final s = special;
    return s != null ? 'KeyCode.${s.name}' : "KeyCode.char('$character')";
  }

  @override
  int get stepCount => 1;

  @override
  _KeyStep _stepAt(int index) {
    assert(index == 0, 'a KeyCode is a single step');
    return _KeyStep(this);
  }
}

/// A pattern that matches one or more keypresses — the value a [KeyBinding]
/// binds and the [InputDispatcher] matches events against.
///
/// A sequence is one or more *steps*; each step is one [KeyCode] plus a
/// strict set of modifiers, and the dispatcher consumes one [KeyEvent] per
/// step. [KeyCode] is the one-step, unmodified subtype — `.enter` and
/// `.char('?')` are sequences directly — while modified or multi-step
/// patterns are built with the dot chain:
///
/// ```dart
/// .enter                 // a KeyCode — one unmodified key
/// .ctrl.s                // one modified step
/// .ctrl.shift.p          // stacked modifiers (order-agnostic)
/// .superKey.k            // super/meta are first-class
/// .g.g                   // a two-step sequence
/// .ctrl.x.ctrl.s         // emacs-style multi-step
/// .space.f               // leader style
/// .alt.char('${1 + 1}')  // dynamic atoms via char()
/// ```
///
/// Modifiers fold into the *next* key atom; an expression ending in a
/// modifier has type [PendingKeySequence], not `KeySequence`, so
/// `KeyBinding(.ctrl)` is a compile error.
///
/// Sequences are values: structural, canonicalised equality (`.shift.g`,
/// `.char('G')`, and `.char('g', …)` are one value) makes them safe as
/// `Map<KeySequence, _>` keys and for [KeyBinding] alias dedup.
///
/// `sealed` rather than `final`: the only non-[KeyCode] subtype is private,
/// so external code can't exhaustively switch anyway (it always needs a
/// default), and sealing lets the two subtypes share one step interface.
sealed class KeySequence {
  const KeySequence._();

  // ---- Atom statics (forward to KeyCode, the canonical home) --------------
  //
  // These let the dot-shorthand resolve in a `KeySequence` context —
  // `KeyBinding(.enter, …)` picks up `KeySequence.enter`. Each is a
  // [KeyCode], since an unmodified key IS a one-step sequence.

  static const KeyCode a = KeyCode.a;
  static const KeyCode b = KeyCode.b;
  static const KeyCode c = KeyCode.c;
  static const KeyCode d = KeyCode.d;
  static const KeyCode e = KeyCode.e;
  static const KeyCode f = KeyCode.f;
  static const KeyCode g = KeyCode.g;
  static const KeyCode h = KeyCode.h;
  static const KeyCode i = KeyCode.i;
  static const KeyCode j = KeyCode.j;
  static const KeyCode k = KeyCode.k;
  static const KeyCode l = KeyCode.l;
  static const KeyCode m = KeyCode.m;
  static const KeyCode n = KeyCode.n;
  static const KeyCode o = KeyCode.o;
  static const KeyCode p = KeyCode.p;
  static const KeyCode q = KeyCode.q;
  static const KeyCode r = KeyCode.r;
  static const KeyCode s = KeyCode.s;
  static const KeyCode t = KeyCode.t;
  static const KeyCode u = KeyCode.u;
  static const KeyCode v = KeyCode.v;
  static const KeyCode w = KeyCode.w;
  static const KeyCode x = KeyCode.x;
  static const KeyCode y = KeyCode.y;
  static const KeyCode z = KeyCode.z;

  static const KeyCode space = KeyCode.space;
  static const KeyCode enter = KeyCode.enter;
  static const KeyCode tab = KeyCode.tab;
  static const KeyCode backspace = KeyCode.backspace;
  static const KeyCode escape = KeyCode.escape;
  static const KeyCode delete = KeyCode.delete;
  static const KeyCode insert = KeyCode.insert;
  static const KeyCode up = KeyCode.arrowUp;
  static const KeyCode down = KeyCode.arrowDown;
  static const KeyCode left = KeyCode.arrowLeft;
  static const KeyCode right = KeyCode.arrowRight;
  static const KeyCode home = KeyCode.home;
  static const KeyCode end = KeyCode.end;
  static const KeyCode pageUp = KeyCode.pageUp;
  static const KeyCode pageDown = KeyCode.pageDown;
  static const KeyCode f1 = KeyCode.f1;
  static const KeyCode f2 = KeyCode.f2;
  static const KeyCode f3 = KeyCode.f3;
  static const KeyCode f4 = KeyCode.f4;
  static const KeyCode f5 = KeyCode.f5;
  static const KeyCode f6 = KeyCode.f6;
  static const KeyCode f7 = KeyCode.f7;
  static const KeyCode f8 = KeyCode.f8;
  static const KeyCode f9 = KeyCode.f9;
  static const KeyCode f10 = KeyCode.f10;
  static const KeyCode f11 = KeyCode.f11;
  static const KeyCode f12 = KeyCode.f12;

  /// Shift+Tab — the common back-traverse chord, spelled as a named atom
  /// because terminals encode it as one distinct sequence.
  static const KeySequence shiftTab = _ModifiedSequence([
    _KeyStep(KeyCode.tab, shift: true),
  ]);

  // ---- Modifier entry-points (typed PendingKeySequence) -------------------

  static const PendingKeySequence ctrl = PendingKeySequence._(ctrl: true);
  static const PendingKeySequence alt = PendingKeySequence._(alt: true);
  static const PendingKeySequence shift = PendingKeySequence._(shift: true);
  static const PendingKeySequence superKey = PendingKeySequence._(
    superKey: true,
  );
  static const PendingKeySequence meta = PendingKeySequence._(meta: true);

  /// A printable-character key with no modifiers — the entry point for
  /// atoms outside the named statics (digits, punctuation, Unicode).
  static KeyCode char(String character) => KeyCode.char(character);

  /// This event's key and modifiers as a one-step sequence (see
  /// [KeyEvent.toSequence]).
  static KeySequence fromEvent(KeyEvent event) => fromEvents([event]);

  /// A multi-step sequence from the events that produced it, one step per
  /// event, in order — used to render the prefix of a pending match.
  static KeySequence fromEvents(List<KeyEvent> events) {
    assert(events.isNotEmpty, 'a sequence has at least one step');
    return _sequenceFromSteps([
      for (final event in events)
        _KeyStep.build(
          event.code,
          ctrl: event.hasCtrl,
          alt: event.hasAlt,
          shift: event.hasShift,
          superKey: event.hasSuper,
          meta: event.hasMeta,
        ),
    ]);
  }

  /// Parses a human-readable sequence such as `ctrl+x ctrl+s`, `g g`,
  /// `super+k`, or `?`. Throws [FormatException] on malformed input; see
  /// [tryParse] for the non-throwing form. `parse(x.hintLabel) == x` for
  /// every sequence.
  static KeySequence parse(String source) {
    final parsed = tryParse(source);
    if (parsed == null) {
      throw FormatException('not a key sequence', source);
    }
    return parsed;
  }

  /// Parses a human-readable sequence, or returns null if [source] is not a
  /// valid one. See [parse] for the grammar.
  static KeySequence? tryParse(String source) {
    final stepTokens = source.trim().split(RegExp(r'\s+'));
    if (stepTokens.isEmpty ||
        (stepTokens.length == 1 && stepTokens[0].isEmpty)) {
      return null;
    }
    final steps = <_KeyStep>[];
    for (final token in stepTokens) {
      final step = _parseStep(token);
      if (step == null) return null;
      steps.add(step);
    }
    return _sequenceFromSteps(steps);
  }

  // ---- Instance API -------------------------------------------------------

  /// Number of steps (`1` for a single-keystroke sequence).
  int get stepCount;

  /// Whether this sequence's *first step* matches [event]. Multi-step
  /// sequences have their continuation matched step-by-step by the
  /// [InputDispatcher].
  bool matches(KeyEvent event) => _stepAt(0).matches(event);

  /// Whether every step of this sequence is a prefix of [other] — used to
  /// warn about remap conflicts where one binding delays another
  /// (e.g. `g` delays `g g`).
  bool isPrefixOf(KeySequence other) {
    if (stepCount > other.stepCount) return false;
    for (var index = 0; index < stepCount; index++) {
      if (_stepAt(index) != other._stepAt(index)) return false;
    }
    return true;
  }

  /// Short human-readable label: `j` / `Ctrl+S` / `↑` / `Ctrl+X Ctrl+S`.
  /// Round-trips through [parse].
  String get hintLabel {
    final buffer = StringBuffer();
    for (var index = 0; index < stepCount; index++) {
      if (index > 0) buffer.write(' ');
      buffer.write(_stepAt(index).label);
    }
    return buffer.toString();
  }

  /// The step at [index]. Subtypes provide the storage; index is in
  /// `[0, stepCount)`.
  _KeyStep _stepAt(int index);

  @override
  bool operator ==(Object other) {
    if (other is! KeySequence) return false;
    if (other.stepCount != stepCount) return false;
    for (var index = 0; index < stepCount; index++) {
      if (_stepAt(index) != other._stepAt(index)) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = 17;
    for (var index = 0; index < stepCount; index++) {
      hash = Object.hash(hash, _stepAt(index));
    }
    return hash;
  }

  @override
  String toString() => 'KeySequence($hintLabel)';
}

/// A sequence under construction whose pending modifiers have no key yet.
///
/// You get one from `.ctrl`, `.superKey`, `.ctrl.shift`, or a mid-sequence
/// modifier like `.d.ctrl`. Adding a key atom (`.s`, `.enter`, `.char('/')`,
/// `.code(kc)`) closes the pending modifiers into a [KeySequence].
///
/// Because this is *not* a `KeySequence`, an incomplete expression can't be
/// bound: `KeyBinding(.ctrl)` and `[.ctrl.shift]` are compile errors. The
/// analyzer names this type in that error, which is why it stays exported.
@immutable
final class PendingKeySequence {
  const PendingKeySequence._({
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    bool superKey = false,
    bool meta = false,
    List<_KeyStep> completed = const [],
  }) : _ctrl = ctrl,
       _alt = alt,
       _shift = shift,
       _superKey = superKey,
       _meta = meta,
       _completed = completed;

  final bool _ctrl;
  final bool _alt;
  final bool _shift;
  final bool _superKey;
  final bool _meta;

  /// Completed prefix steps preceding the pending modifiers (empty when the
  /// pending modifiers are the very first thing).
  final List<_KeyStep> _completed;

  @override
  String toString() {
    final pending = <String>[
      if (_ctrl) 'Ctrl',
      if (_alt) 'Alt',
      if (_shift) 'Shift',
      if (_superKey) 'Super',
      if (_meta) 'Meta',
    ].join('+');
    return _completed.isEmpty
        ? 'PendingKeySequence($pending+…)'
        : 'PendingKeySequence(${_labelSteps(_completed)} $pending+…)';
  }
}

// ---------------------------------------------------------------------------
// Chain extensions — the dot-syntax that makes sequences compose.
// ---------------------------------------------------------------------------

/// Chain getters on a complete [KeySequence]. After a step, modifiers start
/// a new pending step, and key atoms append a whole new step (forming a
/// multi-step sequence).
extension KeySequenceChain on KeySequence {
  PendingKeySequence get ctrl => _pendingAfter(ctrl: true);
  PendingKeySequence get alt => _pendingAfter(alt: true);
  PendingKeySequence get shift => _pendingAfter(shift: true);
  PendingKeySequence get superKey => _pendingAfter(superKey: true);
  PendingKeySequence get meta => _pendingAfter(meta: true);

  PendingKeySequence _pendingAfter({
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    bool superKey = false,
    bool meta = false,
  }) => PendingKeySequence._(
    ctrl: ctrl,
    alt: alt,
    shift: shift,
    superKey: superKey,
    meta: meta,
    completed: _collectSteps(this),
  );

  KeySequence get a => _appendAtom(this, KeyCode.a);
  KeySequence get b => _appendAtom(this, KeyCode.b);
  KeySequence get c => _appendAtom(this, KeyCode.c);
  KeySequence get d => _appendAtom(this, KeyCode.d);
  KeySequence get e => _appendAtom(this, KeyCode.e);
  KeySequence get f => _appendAtom(this, KeyCode.f);
  KeySequence get g => _appendAtom(this, KeyCode.g);
  KeySequence get h => _appendAtom(this, KeyCode.h);
  KeySequence get i => _appendAtom(this, KeyCode.i);
  KeySequence get j => _appendAtom(this, KeyCode.j);
  KeySequence get k => _appendAtom(this, KeyCode.k);
  KeySequence get l => _appendAtom(this, KeyCode.l);
  KeySequence get m => _appendAtom(this, KeyCode.m);
  KeySequence get n => _appendAtom(this, KeyCode.n);
  KeySequence get o => _appendAtom(this, KeyCode.o);
  KeySequence get p => _appendAtom(this, KeyCode.p);
  KeySequence get q => _appendAtom(this, KeyCode.q);
  KeySequence get r => _appendAtom(this, KeyCode.r);
  KeySequence get s => _appendAtom(this, KeyCode.s);
  KeySequence get t => _appendAtom(this, KeyCode.t);
  KeySequence get u => _appendAtom(this, KeyCode.u);
  KeySequence get v => _appendAtom(this, KeyCode.v);
  KeySequence get w => _appendAtom(this, KeyCode.w);
  KeySequence get x => _appendAtom(this, KeyCode.x);
  KeySequence get y => _appendAtom(this, KeyCode.y);
  KeySequence get z => _appendAtom(this, KeyCode.z);

  KeySequence get space => _appendAtom(this, KeyCode.space);
  KeySequence get enter => _appendAtom(this, KeyCode.enter);
  KeySequence get tab => _appendAtom(this, KeyCode.tab);
  KeySequence get backspace => _appendAtom(this, KeyCode.backspace);
  KeySequence get escape => _appendAtom(this, KeyCode.escape);
  KeySequence get delete => _appendAtom(this, KeyCode.delete);
  KeySequence get insert => _appendAtom(this, KeyCode.insert);
  KeySequence get up => _appendAtom(this, KeyCode.arrowUp);
  KeySequence get down => _appendAtom(this, KeyCode.arrowDown);
  KeySequence get left => _appendAtom(this, KeyCode.arrowLeft);
  KeySequence get right => _appendAtom(this, KeyCode.arrowRight);
  KeySequence get home => _appendAtom(this, KeyCode.home);
  KeySequence get end => _appendAtom(this, KeyCode.end);
  KeySequence get pageUp => _appendAtom(this, KeyCode.pageUp);
  KeySequence get pageDown => _appendAtom(this, KeyCode.pageDown);
  KeySequence get f1 => _appendAtom(this, KeyCode.f1);
  KeySequence get f2 => _appendAtom(this, KeyCode.f2);
  KeySequence get f3 => _appendAtom(this, KeyCode.f3);
  KeySequence get f4 => _appendAtom(this, KeyCode.f4);
  KeySequence get f5 => _appendAtom(this, KeyCode.f5);
  KeySequence get f6 => _appendAtom(this, KeyCode.f6);
  KeySequence get f7 => _appendAtom(this, KeyCode.f7);
  KeySequence get f8 => _appendAtom(this, KeyCode.f8);
  KeySequence get f9 => _appendAtom(this, KeyCode.f9);
  KeySequence get f10 => _appendAtom(this, KeyCode.f10);
  KeySequence get f11 => _appendAtom(this, KeyCode.f11);
  KeySequence get f12 => _appendAtom(this, KeyCode.f12);

  /// Append a dynamic character atom (digits, punctuation, Unicode).
  KeySequence char(String character) =>
      _appendAtom(this, KeyCode.char(character));

  /// Append a [KeyCode] held in a variable.
  KeySequence code(KeyCode keyCode) => _appendAtom(this, keyCode);
}

/// Chain getters on a [PendingKeySequence]. Modifier atoms accumulate (still
/// pending); key atoms consume the pending modifiers and return a
/// [KeySequence].
extension PendingKeySequenceChain on PendingKeySequence {
  PendingKeySequence get ctrl => _addMod(ctrl: true);
  PendingKeySequence get alt => _addMod(alt: true);
  PendingKeySequence get shift => _addMod(shift: true);
  PendingKeySequence get superKey => _addMod(superKey: true);
  PendingKeySequence get meta => _addMod(meta: true);

  PendingKeySequence _addMod({
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    bool superKey = false,
    bool meta = false,
  }) => PendingKeySequence._(
    ctrl: _ctrl || ctrl,
    alt: _alt || alt,
    shift: _shift || shift,
    superKey: _superKey || superKey,
    meta: _meta || meta,
    completed: _completed,
  );

  KeySequence get a => char('a');
  KeySequence get b => char('b');
  KeySequence get c => char('c');
  KeySequence get d => char('d');
  KeySequence get e => char('e');
  KeySequence get f => char('f');
  KeySequence get g => char('g');
  KeySequence get h => char('h');
  KeySequence get i => char('i');
  KeySequence get j => char('j');
  KeySequence get k => char('k');
  KeySequence get l => char('l');
  KeySequence get m => char('m');
  KeySequence get n => char('n');
  KeySequence get o => char('o');
  KeySequence get p => char('p');
  KeySequence get q => char('q');
  KeySequence get r => char('r');
  KeySequence get s => char('s');
  KeySequence get t => char('t');
  KeySequence get u => char('u');
  KeySequence get v => char('v');
  KeySequence get w => char('w');
  KeySequence get x => char('x');
  KeySequence get y => char('y');
  KeySequence get z => char('z');

  KeySequence get space => char(' ');
  KeySequence get enter => code(KeyCode.enter);
  KeySequence get tab => code(KeyCode.tab);
  KeySequence get backspace => code(KeyCode.backspace);
  KeySequence get escape => code(KeyCode.escape);
  KeySequence get delete => code(KeyCode.delete);
  KeySequence get insert => code(KeyCode.insert);
  KeySequence get up => code(KeyCode.arrowUp);
  KeySequence get down => code(KeyCode.arrowDown);
  KeySequence get left => code(KeyCode.arrowLeft);
  KeySequence get right => code(KeyCode.arrowRight);
  KeySequence get home => code(KeyCode.home);
  KeySequence get end => code(KeyCode.end);
  KeySequence get pageUp => code(KeyCode.pageUp);
  KeySequence get pageDown => code(KeyCode.pageDown);
  KeySequence get f1 => code(KeyCode.f1);
  KeySequence get f2 => code(KeyCode.f2);
  KeySequence get f3 => code(KeyCode.f3);
  KeySequence get f4 => code(KeyCode.f4);
  KeySequence get f5 => code(KeyCode.f5);
  KeySequence get f6 => code(KeyCode.f6);
  KeySequence get f7 => code(KeyCode.f7);
  KeySequence get f8 => code(KeyCode.f8);
  KeySequence get f9 => code(KeyCode.f9);
  KeySequence get f10 => code(KeyCode.f10);
  KeySequence get f11 => code(KeyCode.f11);
  KeySequence get f12 => code(KeyCode.f12);

  /// Close the pending modifiers with a dynamic character atom.
  KeySequence char(String character) => code(KeyCode.char(character));

  /// Close the pending modifiers with a [KeyCode] held in a variable.
  KeySequence code(KeyCode keyCode) {
    final step = _KeyStep.build(
      keyCode,
      ctrl: _ctrl,
      alt: _alt,
      shift: _shift,
      superKey: _superKey,
      meta: _meta,
    );
    return _sequenceFromSteps([..._completed, step]);
  }
}

// ---------------------------------------------------------------------------
// Framework-internal step access consumed by [InputDispatcher].
// ---------------------------------------------------------------------------

/// **Framework-internal.** Lets the [InputDispatcher] walk a sequence
/// step-by-step without exposing the step layout. Not a stable public API —
/// app code should treat these as private.
extension $KeySequenceInternal on KeySequence {
  /// Whether this sequence has more than one step.
  bool get isSequence => stepCount > 1;

  /// Matches the step at [index] against [event]; false when out of range.
  bool matchesStepAt(int index, KeyEvent event) {
    if (index < 0 || index >= stepCount) return false;
    return _stepAt(index).matches(event);
  }

  /// The [hintLabel]-style label of the step at [index] (`Ctrl+S`, `↑`, `d`),
  /// or null when out of range. Used to render which-key completions.
  String? stepLabelAt(int index) {
    if (index < 0 || index >= stepCount) return null;
    return _stepAt(index).label;
  }

  /// The events a terminal would emit for this sequence: a bare printable
  /// step arrives as a [TextInputEvent] (shift folded into the character's
  /// case), any modified or special step as a [KeyEvent]. Test harnesses use
  /// this so `press(sequence)` exercises the real text-vs-key routing.
  List<TuiEvent> asInputEvents() => [
    for (var i = 0; i < stepCount; i++) _stepAt(i).asInputEvent(),
  ];

  /// Whether a focused text field swallows this sequence before matching:
  /// its first step is a bare printable (a character with no
  /// Ctrl/Alt/Super/Meta — Shift is allowed, since shifted printables arrive
  /// as text). Such a sequence can never fire while an editable holds focus,
  /// so the hint bar stops advertising it. Super/Meta chords are *not*
  /// shadowed — they arrive as key events, not text.
  bool get isShadowedByTextInput {
    final step = _stepAt(0);
    return step.code.isCharacter &&
        !step.ctrl &&
        !step.alt &&
        !step.superKey &&
        !step.meta;
  }
}

// ---------------------------------------------------------------------------
// Private: the modified/multi-step sequence, a step, and helpers.
// ---------------------------------------------------------------------------

/// A sequence with at least one modifier or more than one step. Single
/// unmodified steps are represented directly by [KeyCode] (see
/// [_sequenceFromSteps]), so this always has a modifier somewhere or
/// `steps.length > 1`.
@immutable
final class _ModifiedSequence extends KeySequence {
  const _ModifiedSequence(this._steps) : super._();

  final List<_KeyStep> _steps;

  @override
  int get stepCount => _steps.length;

  @override
  _KeyStep _stepAt(int index) => _steps[index];
}

/// One step of a sequence: a [KeyCode] plus a strict modifier set.
///
/// Shift on a cased letter is folded into the character's case ([build]), so
/// a letter step never carries a separate shift flag — `.shift.g` and
/// `.char('G')` reduce to the same step (code `G`, no shift).
@immutable
final class _KeyStep {
  const _KeyStep(
    this.code, {
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.superKey = false,
    this.meta = false,
  });

  /// Builds a step, folding Shift on a cased letter into the character's
  /// case so the representation is canonical.
  factory _KeyStep.build(
    KeyCode code, {
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    bool superKey = false,
    bool meta = false,
  }) {
    final ch = code.character;
    if (ch != null && ch.toLowerCase() != ch.toUpperCase()) {
      // A cased letter: encode Shift as case, never as a flag.
      final shifted = shift || ch != ch.toLowerCase();
      return _KeyStep(
        KeyCode.char(shifted ? ch.toUpperCase() : ch.toLowerCase()),
        ctrl: ctrl,
        alt: alt,
        superKey: superKey,
        meta: meta,
      );
    }
    return _KeyStep(
      code,
      ctrl: ctrl,
      alt: alt,
      shift: shift,
      superKey: superKey,
      meta: meta,
    );
  }

  final KeyCode code;
  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool superKey;
  final bool meta;

  bool get _hasModifiers => ctrl || alt || shift || superKey || meta;

  /// Strict per-step match. All five modifiers compare by equality; for a
  /// character code, shift is folded through case so `.shift.g` matches an
  /// event reporting either base-`g`+Shift or an upper-`G`.
  bool matches(KeyEvent event) {
    if (ctrl != event.hasCtrl) return false;
    if (alt != event.hasAlt) return false;
    if (superKey != event.hasSuper) return false;
    if (meta != event.hasMeta) return false;

    final special = code.special;
    if (special != null) {
      if (event.code.special != special) return false;
      return shift == event.hasShift;
    }

    final stepChar = code.character!;
    final eventChar = event.code.character;
    if (eventChar == null) return false;
    if (stepChar.toLowerCase() != eventChar.toLowerCase()) return false;

    final stepWantsShift = shift || stepChar != stepChar.toLowerCase();
    final eventHasShift =
        event.hasShift || eventChar != eventChar.toLowerCase();
    return stepWantsShift == eventHasShift;
  }

  /// The single event a terminal would emit for this step: a bare printable
  /// as [TextInputEvent] (shift is in the character's case), otherwise a
  /// [KeyEvent] carrying the code and modifiers.
  TuiEvent asInputEvent() {
    final character = code.character;
    final bare = character != null && !ctrl && !alt && !superKey && !meta;
    if (bare) return TextInputEvent(character);
    return KeyEvent(
      code,
      modifiers: {
        if (ctrl) KeyModifier.ctrl,
        if (alt) KeyModifier.alt,
        if (shift) KeyModifier.shift,
        if (superKey) KeyModifier.superKey,
        if (meta) KeyModifier.meta,
      },
    );
  }

  /// Per-step label: `Ctrl+S`, `↑`, `d`, `Space`, `Shift+G`.
  String get label {
    final ch = code.character;
    final isUpperLetter = ch != null && ch != ch.toLowerCase();
    final mods = <String>[
      if (ctrl) 'Ctrl',
      if (alt) 'Alt',
      if (shift || isUpperLetter) 'Shift',
      if (superKey) 'Super',
      if (meta) 'Meta',
    ];
    final special = code.special;
    final String base;
    if (special != null) {
      base = _specialLabel(special);
    } else if (ch == ' ') {
      base = 'Space';
    } else {
      base = mods.isEmpty ? ch! : ch!.toUpperCase();
    }
    return mods.isEmpty ? base : '${mods.join('+')}+$base';
  }

  @override
  bool operator ==(Object other) =>
      other is _KeyStep &&
      other.code == code &&
      other.ctrl == ctrl &&
      other.alt == alt &&
      other.shift == shift &&
      other.superKey == superKey &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(code, ctrl, alt, shift, superKey, meta);
}

/// Reduces built steps to the tightest representation: a lone unmodified
/// step is just its [KeyCode]; anything else is a [_ModifiedSequence].
KeySequence _sequenceFromSteps(List<_KeyStep> steps) {
  if (steps.length == 1 && !steps.first._hasModifiers) return steps.first.code;
  return _ModifiedSequence(List<_KeyStep>.unmodifiable(steps));
}

/// Appends [atom] as a fresh step to [chain]'s steps.
KeySequence _appendAtom(KeySequence chain, KeyCode atom) =>
    _sequenceFromSteps([..._collectSteps(chain), _KeyStep.build(atom)]);

/// Materialises a sequence's steps (construction-time only, not hot).
List<_KeyStep> _collectSteps(KeySequence sequence) => [
  for (var i = 0; i < sequence.stepCount; i++) sequence._stepAt(i),
];

String _labelSteps(List<_KeyStep> steps) => steps.map((s) => s.label).join(' ');

/// The canonical display label for a special key.
String _specialLabel(SpecialKey key) => switch (key) {
  SpecialKey.enter => 'Enter',
  SpecialKey.tab => 'Tab',
  SpecialKey.backspace => 'Backspace',
  SpecialKey.escape => 'Esc',
  SpecialKey.arrowUp => '↑',
  SpecialKey.arrowDown => '↓',
  SpecialKey.arrowLeft => '←',
  SpecialKey.arrowRight => '→',
  SpecialKey.home => 'Home',
  SpecialKey.end => 'End',
  SpecialKey.pageUp => 'PgUp',
  SpecialKey.pageDown => 'PgDn',
  SpecialKey.insert => 'Ins',
  SpecialKey.delete => 'Del',
  SpecialKey.f1 => 'F1',
  SpecialKey.f2 => 'F2',
  SpecialKey.f3 => 'F3',
  SpecialKey.f4 => 'F4',
  SpecialKey.f5 => 'F5',
  SpecialKey.f6 => 'F6',
  SpecialKey.f7 => 'F7',
  SpecialKey.f8 => 'F8',
  SpecialKey.f9 => 'F9',
  SpecialKey.f10 => 'F10',
  SpecialKey.f11 => 'F11',
  SpecialKey.f12 => 'F12',
};

/// Parses one step token (`ctrl+x`, `Shift+G`, `esc`, `?`, `ctrl++`) into a
/// [_KeyStep], or null if malformed. Modifier and key names are
/// case-insensitive.
///
/// Modifiers are stripped as `name+` prefixes rather than by splitting on
/// `+`, so the `+` key itself parses as an atom (`ctrl++` → Ctrl and the `+`
/// key), keeping `parse(x.hintLabel) == x` for `+`-bearing sequences.
_KeyStep? _parseStep(String token) {
  if (token.isEmpty) return null;

  var rest = token;
  var ctrl = false, alt = false, shift = false, superKey = false, meta = false;
  while (true) {
    final plus = rest.indexOf('+');
    // No separator, or a leading `+` (the atom is `+` itself) → done.
    if (plus <= 0) break;
    final modifier = _modifierByName(rest.substring(0, plus).toLowerCase());
    if (modifier == null) break; // not a modifier — the rest is the atom
    switch (modifier) {
      case KeyModifier.ctrl:
        ctrl = true;
      case KeyModifier.alt:
        alt = true;
      case KeyModifier.shift:
        shift = true;
      case KeyModifier.superKey:
        superKey = true;
      case KeyModifier.meta:
        meta = true;
    }
    rest = rest.substring(plus + 1);
    if (rest.isEmpty) return null; // trailing modifier with no key (`ctrl+`)
  }

  var atom = _parseAtom(rest);
  if (atom == null) return null;

  // Reverse the display convention: [label] renders a modified letter in
  // uppercase for readability (`Ctrl+S`), so an uppercase letter alongside a
  // non-shift modifier and no explicit `Shift+` is styling, not Shift. A bare
  // uppercase letter (or an explicit `Shift+`) still means Shift.
  final ch = atom.character;
  if (ch != null && ch.toLowerCase() != ch.toUpperCase()) {
    final hasOtherModifier = ctrl || alt || superKey || meta;
    if (!shift && hasOtherModifier && ch != ch.toLowerCase()) {
      atom = KeyCode.char(ch.toLowerCase());
    }
  }

  return _KeyStep.build(
    atom,
    ctrl: ctrl,
    alt: alt,
    shift: shift,
    superKey: superKey,
    meta: meta,
  );
}

/// Maps a modifier name (with aliases) to its [KeyModifier], or null.
KeyModifier? _modifierByName(String name) => switch (name) {
  'ctrl' || 'control' => KeyModifier.ctrl,
  'alt' || 'opt' || 'option' => KeyModifier.alt,
  'shift' => KeyModifier.shift,
  'super' || 'cmd' || 'command' || 'win' => KeyModifier.superKey,
  'meta' => KeyModifier.meta,
  _ => null,
};

/// Parses one key atom into a [KeyCode]: a special-key name/glyph, or a
/// single-character literal. Case-insensitive for named keys.
KeyCode? _parseAtom(String atom) {
  if (atom.isEmpty) return null;
  // 'Space' (the hintLabel form) is the space character, not a special key.
  if (atom.toLowerCase() == 'space') return const KeyCode.char(' ');
  final special = _specialByName[atom.toLowerCase()];
  if (special != null) return KeyCode.forSpecial(special);
  if (atom == '↑') return KeyCode.arrowUp;
  if (atom == '↓') return KeyCode.arrowDown;
  if (atom == '←') return KeyCode.arrowLeft;
  if (atom == '→') return KeyCode.arrowRight;
  if (atom.runes.length == 1) return KeyCode.char(atom);
  return null;
}

/// Special-key names accepted by [parse], including the [hintLabel] forms
/// and common aliases. Keyed lowercase.
const Map<String, SpecialKey> _specialByName = {
  'enter': SpecialKey.enter,
  'return': SpecialKey.enter,
  'tab': SpecialKey.tab,
  'backspace': SpecialKey.backspace,
  'esc': SpecialKey.escape,
  'escape': SpecialKey.escape,
  'up': SpecialKey.arrowUp,
  'arrowup': SpecialKey.arrowUp,
  'down': SpecialKey.arrowDown,
  'arrowdown': SpecialKey.arrowDown,
  'left': SpecialKey.arrowLeft,
  'arrowleft': SpecialKey.arrowLeft,
  'right': SpecialKey.arrowRight,
  'arrowright': SpecialKey.arrowRight,
  'home': SpecialKey.home,
  'end': SpecialKey.end,
  'pgup': SpecialKey.pageUp,
  'pageup': SpecialKey.pageUp,
  'pgdn': SpecialKey.pageDown,
  'pagedown': SpecialKey.pageDown,
  'ins': SpecialKey.insert,
  'insert': SpecialKey.insert,
  'del': SpecialKey.delete,
  'delete': SpecialKey.delete,
  'f1': SpecialKey.f1,
  'f2': SpecialKey.f2,
  'f3': SpecialKey.f3,
  'f4': SpecialKey.f4,
  'f5': SpecialKey.f5,
  'f6': SpecialKey.f6,
  'f7': SpecialKey.f7,
  'f8': SpecialKey.f8,
  'f9': SpecialKey.f9,
  'f10': SpecialKey.f10,
  'f11': SpecialKey.f11,
  'f12': SpecialKey.f12,
};

/// Keyboard modifier flags.
///
/// With the Kitty keyboard protocol (CSI-u) negotiated, all of these are
/// resolved reliably and on every key — including the otherwise-ambiguous
/// cases (Ctrl+I vs Tab, Ctrl+M vs Enter) and the [superKey] / [meta] chords
/// that legacy encodings can't express. On terminals without the protocol,
/// [ctrl] and the cursor/function-key modifiers still resolve via the
/// classic xterm encoding; bare modified letters degrade to their control
/// bytes.
enum KeyModifier {
  shift,
  ctrl,
  alt,

  /// The "super" key — Command on macOS, Windows/Meta key elsewhere. Only
  /// reported under the Kitty protocol.
  superKey,

  /// The "meta" key as distinct from [alt]. Only reported under the Kitty
  /// protocol; most terminals fold Meta into [alt].
  meta,
}

/// Whether a [KeyEvent] is an initial press, an auto-repeat, or a release.
///
/// Only the Kitty keyboard protocol distinguishes these, and only when
/// event-type reporting is requested. Without it — the default — every
/// key arrives as [down], so consumers that ignore this field behave
/// exactly as before.
enum KeyEventType { down, repeat, up }

/// Base for all events flowing out of [TerminalDriver.events].
@immutable
sealed class TuiEvent {
  const TuiEvent();
}

/// A non-text key press: exactly one [KeyCode] plus its modifiers.
///
/// Ctrl+C reports `KeyCode.c` with `modifiers: {KeyModifier.ctrl}`; Enter
/// reports [KeyCode.enter]. On terminals, *unmodified* printables arrive
/// as [TextInputEvent] rather than key events; character-coded `KeyEvent`s
/// carry the base character of a modified key.
@immutable
final class KeyEvent extends TuiEvent {
  const KeyEvent(
    this.code, {
    this.modifiers = const <KeyModifier>{},
    this.type = KeyEventType.down,
  });

  /// The logical key this event reports.
  final KeyCode code;

  final Set<KeyModifier> modifiers;

  /// Whether this is a press, auto-repeat, or release. Always
  /// [KeyEventType.down] unless the Kitty protocol's event-type reporting
  /// is enabled.
  final KeyEventType type;

  bool get hasCtrl => modifiers.contains(KeyModifier.ctrl);
  bool get hasAlt => modifiers.contains(KeyModifier.alt);
  bool get hasShift => modifiers.contains(KeyModifier.shift);
  bool get hasSuper => modifiers.contains(KeyModifier.superKey);
  bool get hasMeta => modifiers.contains(KeyModifier.meta);

  /// This event's key and modifiers as a one-step [KeySequence].
  ///
  /// Useful for "press a key to rebind" capture UIs — `event.toSequence()`
  /// yields the value a matching [KeyBinding] would carry, and
  /// `toSequence().hintLabel` renders it. [KeyEventType] is dropped: a
  /// sequence describes which keys, not press vs release.
  KeySequence toSequence() => KeySequence.fromEvent(this);

  @override
  bool operator ==(Object other) =>
      other is KeyEvent &&
      other.code == code &&
      other.type == type &&
      _setEquals(other.modifiers, modifiers);

  @override
  int get hashCode => Object.hash(
    code,
    type,
    modifiers.fold<int>(0, (acc, m) => acc ^ m.hashCode),
  );

  @override
  String toString() {
    final parts = <String>[
      if (modifiers.contains(KeyModifier.ctrl)) 'ctrl',
      if (modifiers.contains(KeyModifier.alt)) 'alt',
      if (modifiers.contains(KeyModifier.shift)) 'shift',
      if (modifiers.contains(KeyModifier.superKey)) 'super',
      if (modifiers.contains(KeyModifier.meta)) 'meta',
      code.special?.name ?? code.character ?? '',
    ];
    final suffix = type == KeyEventType.down ? '' : ' ${type.name}';
    return 'KeyEvent(${parts.join('+')}$suffix)';
  }
}

/// One or more graphemes of typed text. The driver accumulates UTF-8
/// continuation bytes before emitting so consumers always get a
/// valid string.
@immutable
final class TextInputEvent extends TuiEvent {
  const TextInputEvent(this.text);
  final String text;

  @override
  bool operator ==(Object other) =>
      other is TextInputEvent && other.text == text;
  @override
  int get hashCode => Object.hash(TextInputEvent, text);
  @override
  String toString() => 'TextInputEvent(${_quote(text)})';
}

/// Browser/native IME composition lifecycle event.
///
/// Composition is distinct from ordinary text input: an update replaces the
/// active composing range without committing an undo transaction, commit
/// finalizes it, and cancel restores the pre-composition editing value.
enum TextCompositionEventKind { update, commit, cancel }

/// A text composition lifecycle event emitted by hosts with IME support.
@immutable
final class TextCompositionEvent extends TuiEvent {
  const TextCompositionEvent.update(String text)
    : this._(kind: TextCompositionEventKind.update, text: text);

  const TextCompositionEvent.commit([String? text])
    : this._(kind: TextCompositionEventKind.commit, text: text);

  const TextCompositionEvent.cancel()
    : this._(kind: TextCompositionEventKind.cancel);

  const TextCompositionEvent._({required this.kind, this.text});

  final TextCompositionEventKind kind;

  /// Current composing text for [TextCompositionEventKind.update], optional
  /// final committed text for [TextCompositionEventKind.commit], and null for
  /// [TextCompositionEventKind.cancel].
  final String? text;

  @override
  bool operator ==(Object other) =>
      other is TextCompositionEvent && other.kind == kind && other.text == text;
  @override
  int get hashCode => Object.hash(TextCompositionEvent, kind, text);
  @override
  String toString() {
    final value = text;
    return value == null
        ? 'TextCompositionEvent(${kind.name})'
        : 'TextCompositionEvent(${kind.name}, ${_quote(value)})';
  }
}

/// Which mouse button an event concerns ([none] for wheel/motion).
enum MouseButton { left, middle, right, none }

/// What a [MouseEvent] reports.
enum MouseEventKind { down, up, drag, moved, scrollUp, scrollDown }

/// A mouse report (SGR 1006). [col]/[row] are 0-based cell coordinates.
/// Only delivered when the app enabled `TerminalMode.mouse`.
@immutable
final class MouseEvent extends TuiEvent {
  const MouseEvent({
    required this.kind,
    required this.button,
    required this.col,
    required this.row,
    this.modifiers = const <KeyModifier>{},
  });

  final MouseEventKind kind;
  final MouseButton button;
  final int col;
  final int row;
  final Set<KeyModifier> modifiers;

  bool get hasCtrl => modifiers.contains(KeyModifier.ctrl);
  bool get hasAlt => modifiers.contains(KeyModifier.alt);
  bool get hasShift => modifiers.contains(KeyModifier.shift);

  @override
  bool operator ==(Object other) =>
      other is MouseEvent &&
      other.kind == kind &&
      other.button == button &&
      other.col == col &&
      other.row == row &&
      _setEquals(other.modifiers, modifiers);

  @override
  int get hashCode => Object.hash(
    kind,
    button,
    col,
    row,
    modifiers.fold<int>(0, (acc, m) => acc ^ m.hashCode),
  );

  @override
  String toString() => 'MouseEvent(${kind.name} ${button.name} @$col,$row)';
}

/// The position of one [PasteEvent] in a bracketed-paste transaction.
enum PasteEventPhase {
  /// A complete paste carried by one event.
  single,

  /// The first event of a parser-segmented paste.
  start,

  /// A non-final event after [start].
  continuation,

  /// The final event of a parser-segmented paste.
  end,
}

/// Clipboard text delivered by bracketed paste.
///
/// A normal paste arrives as one event. To bound live parser memory, a large
/// bracketed paste may arrive as consecutive events with a shared [pasteId]
/// and explicit [phase]. That identity lets editable widgets keep all segments
/// in one undo transaction even when reads are separated in time. Embedded
/// newlines still arrive as text rather than individual Enter chords, so a
/// multi-line paste inserts instead of submitting line by line.
@immutable
final class PasteEvent extends TuiEvent {
  /// Creates a complete, unsegmented paste.
  const PasteEvent(this.text) : pasteId = null, phase = PasteEventPhase.single;

  /// Creates one segment of a larger bracketed paste.
  const PasteEvent.segment(
    this.text, {
    required int this.pasteId,
    required this.phase,
  }) : assert(phase != PasteEventPhase.single),
       assert(pasteId >= 0);

  final String text;

  /// Parser-local identity shared by every event in a segmented paste.
  ///
  /// Null only for an unsegmented [PasteEventPhase.single] event.
  final int? pasteId;

  /// This event's position in its paste transaction.
  final PasteEventPhase phase;

  bool get isFirst =>
      phase == PasteEventPhase.single || phase == PasteEventPhase.start;

  bool get isFinal =>
      phase == PasteEventPhase.single || phase == PasteEventPhase.end;

  @override
  bool operator ==(Object other) =>
      other is PasteEvent &&
      other.text == text &&
      other.pasteId == pasteId &&
      other.phase == phase;
  @override
  int get hashCode => Object.hash(PasteEvent, text, pasteId, phase);
  @override
  String toString() => switch (phase) {
    PasteEventPhase.single => 'PasteEvent(${_quote(text)})',
    _ => 'PasteEvent.${phase.name}($pasteId, ${_quote(text)})',
  };
}

/// Terminal viewport size changed (e.g. from SIGWINCH on POSIX).
@immutable
final class ResizeEvent extends TuiEvent {
  const ResizeEvent(this.size);
  final CellSize size;

  @override
  bool operator ==(Object other) => other is ResizeEvent && other.size == size;
  @override
  int get hashCode => Object.hash(ResizeEvent, size);
  @override
  String toString() => 'ResizeEvent($size)';
}

/// A termination request delivered to the app, in platform-neutral terms.
///
/// On POSIX these map from SIGINT / SIGTERM; a remote host may synthesize
/// them (e.g. a server shutting a session down). Kept free of `dart:io`
/// types so non-POSIX drivers can emit them too.
enum AppSignal {
  /// Interactive interrupt — SIGINT (`kill -INT`). Note the in-terminal
  /// Ctrl+C keypress arrives as a [KeyEvent] in raw mode, not as a signal.
  interrupt,

  /// Termination request — SIGTERM (supervisors, `kill`, service managers).
  terminate,
}

/// The process received a termination request ([AppSignal]).
///
/// Delivered through the normal event stream so the app can run its own
/// shutdown: `runApp`'s `onEvent` sees it first — returning `EventHandled`
/// claims the signal (the app then finishes via `requestExit()`); any
/// unclaimed [SignalEvent] keeps its POSIX meaning and terminates the app
/// (`runApp` resolves with `AppExit.signal`). The driver arms a grace
/// deadline at delivery, so a hung app still dies.
@immutable
final class SignalEvent extends TuiEvent {
  const SignalEvent(this.signal);
  final AppSignal signal;

  @override
  bool operator ==(Object other) =>
      other is SignalEvent && other.signal == signal;
  @override
  int get hashCode => Object.hash(SignalEvent, signal);
  @override
  String toString() => 'SignalEvent(${signal.name})';
}

// ---- helpers ---------------------------------------------------------------

bool _setEquals(Set<KeyModifier> a, Set<KeyModifier> b) {
  if (a.length != b.length) return false;
  for (final v in a) {
    if (!b.contains(v)) return false;
  }
  return true;
}

String _quote(String s) {
  final escaped = s
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
  return '"$escaped"';
}
