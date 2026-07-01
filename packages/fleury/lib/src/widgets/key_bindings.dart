// KeyChord, KeyBinding, KeyBindings: the declarative input authoring
// surface. Matching logic and the primary widget live here;
// sequence-pending state lives in InputDispatcher (the central
// dispatcher in lib/src/runtime/input_dispatcher.dart).
//
// ===========================================================================
// Migration from pre-2.0
// ===========================================================================
//
// KeyChord — factories collapse into the dot-shorthand chain:
//
//     OLD                                  NEW
//     KeyChord.ctrl('s')                   KeyChord.ctrl.s
//     KeyChord.alt('x')                    KeyChord.alt.x
//     KeyChord.alt('${i + 1}')             KeyChord.alt.char('${i + 1}')
//     KeyChord.sequence(.space, .q)        KeyChord.space.q
//     KeyChord.space.ctrl   (mod-fold)     KeyChord.ctrl.space
//
// `KeyChord.char(c, {ctrl, alt, shift})` and `KeyChord.key(KeyCode,
// {ctrl, alt, shift})` stay as const-eligible escape hatches.
//
// KeyBinding — handler is now void; propagation is event-driven:
//
//     OLD                                  NEW
//     KeyBinding.action(                   KeyBinding(
//       onTrigger: () => save(),             onEvent: (_) => save(),
//       description: 'Save',                 label: 'Save',
//       hint: 'Ctrl+S',                      // gone — KeyChord.hintLabel
//     )                                    )
//
//     KeyBinding(                          KeyBinding(
//       onEvent: (e) =>                        onEvent: (event) {
//         result(e) ? handled : ignored,       if (!doIt()) event.bubble();
//     )                                      },
//                                          )
//
//   * Handler signature: `KeyEventResult Function(KeyEvent)` →
//     `void Function(KeyBindingEvent)`. The wrapper exposes the
//     underlying [KeyEvent]'s fields plus a [bubble] method for
//     per-dispatch propagation control. Bindings always fire when
//     their chord matches; the handler decides whether to claim the
//     event by either doing nothing (default — consumed) or calling
//     `event.bubble()` (continues propagating).
//   * `description` → `label`; `hint` is dropped (the chord's
//     auto-generated `hintLabel` is what the bar shows when there's
//     no label).
//   * `hideFromHint` → `hideFromHintBar`.
//   * `KeyBinding.action` factory is removed — the bare constructor
//     covers the common case at the cost of `(_) =>` per entry.
//
// Two behavioural changes worth knowing about:
//
//   * Sequence precedence is now vim-style. When a node binds both a
//     direct chord (`.d`) and a sequence starting with it (`.d.k`),
//     pressing `d` no longer fires the direct binding immediately —
//     the dispatcher waits up to `sequenceTimeout` (default 500ms)
//     for the follow-up. Pre-2.0 the direct fired immediately and
//     the sequence was unreachable.
//   * Modifier matching is strict. `KeyChord.ctrl.s` matches Ctrl+S
//     only — Ctrl+Shift+S no longer matches it. Bind both via a
//     two-entry alias if you want the old permissive behaviour.

import 'package:meta/meta.dart';

import '../input/events.dart';
import 'focus.dart';
import 'framework.dart';

// ===========================================================================
// KeyChord / PendingKeyChord — declarative chord/sequence patterns.
// ===========================================================================

/// A pattern that matches one or more [KeyEvent]s.
///
/// A `KeyChord` is a *sequence* of one or more *steps*. Each step is a
/// single key (printable character or [KeyCode]) plus a strict set of
/// modifiers; the dispatcher consumes one [KeyEvent] per step.
///
/// **Single-step chords** look like one keystroke:
///
/// ```dart
/// KeyBindings(
///   bindings: [
///     KeyBinding(.enter,         onEvent: (_) => submit()),
///     KeyBinding(.escape,        onEvent: (_) => cancel()),
///     KeyBinding(.f1,            onEvent: (_) => help()),
///     KeyBinding(.ctrl.s,        onEvent: (_) => save()),
///     KeyBinding(.ctrl.shift.p,  onEvent: (_) => palette()),
///   ],
///   child: app,
/// )
/// ```
///
/// **Multi-step chords** (sequences) chain steps with the same dot syntax:
///
/// ```dart
/// KeyBindings(
///   bindings: [
///     KeyBinding(.d.d,           onEvent: (_) => deleteLine()),
///     KeyBinding(.g.g,           onEvent: (_) => goToTop()),
///     KeyBinding(.ctrl.x.ctrl.s, onEvent: (_) => save()),
///     KeyBinding(.ctrl.x.b,      onEvent: (_) => switchBuffer()),
///   ],
///   child: app,
/// )
/// ```
///
/// The chain is order-agnostic between modifiers: `.ctrl.shift.d` and
/// `.shift.ctrl.d` produce equal chords. Modifiers fold into the next
/// non-modifier atom; key atoms (`.d`, `.enter`, `.f1`, …) close the step.
///
/// **Incomplete chords are rejected at compile time.** Expressions ending
/// in a modifier (`.ctrl`, `.ctrl.shift`, `.d.ctrl`) have type
/// [PendingKeyChord], not [KeyChord], so they're a type error wherever a
/// `KeyChord` is expected — including inside a `keys: [...]` list on
/// [KeyBinding].
///
/// ### Atoms not in the static list
///
/// The named statics cover letters (`a`–`z`), function chords (`f1`–`f12`),
/// arrows, common specials (`enter`, `escape`, `space`, …) and the
/// three modifiers. For atoms outside that list — digits, punctuation,
/// arbitrary Unicode — reach for [KeyChord.char] or its chain
/// counterpart [PendingKeyChordChain.char]:
///
/// ```dart
/// KeyBinding(KeyChord.char('?'),     onEvent: (_) => help())
/// KeyBinding(.ctrl.char('/'),         onEvent: (_) => searchMode())
/// KeyBinding(.alt.char('1'),          onEvent: (_) => selectTab1())
/// KeyBinding(.shift.key(KeyCode.tab), onEvent: (_) => prevField())
/// ```
///
/// The [KeyChord.char] form is `const`-eligible, so it composes with
/// const-list bindings the same way the named statics do.
@immutable
final class KeyChord {
  /// Internal — flat representation of one step. Multi-step chords link
  /// further steps via [_next]. All fields directly initialised so const
  /// construction is allowed.
  final String? _char;
  final KeyCode? _keyCode;
  final bool _ctrl;
  final bool _alt;
  final bool _shift;
  final KeyChord? _next;

  /// Cached step count. The dispatcher hits this on every keystroke
  /// inside the sequence-pending loops, so we precompute at
  /// construction rather than walk the linked list each time.
  /// Const constructors can't read `_next._stepCount` in their
  /// initializer list (Dart forbids field-access on a const arg), so
  /// the count is passed in: all the const escape-hatches and atoms
  /// are single-step (count = 1), and `_appendStep` computes the
  /// total when extending a chain.
  final int _stepCount;

  const KeyChord._({
    String? char,
    KeyCode? keyCode,
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    KeyChord? next,
    int stepCount = 1,
  }) : assert(
         (char == null) != (keyCode == null),
         'exactly one of char or keyCode must be set',
       ),
       _char = char,
       _keyCode = keyCode,
       _ctrl = ctrl,
       _alt = alt,
       _shift = shift,
       _next = next,
       _stepCount = stepCount;

  // ---- Const escape-hatch constructors ------------------------------------

  /// A printable character with strict modifier match.
  ///
  /// Use this for atoms not covered by the named statics (digits,
  /// punctuation, arbitrary Unicode). For letters, F-chords, arrows, and
  /// other common chords, the named statics (`.s`, `.f1`, `.up`, …) and
  /// the chain form (`.ctrl.s`) are preferred.
  ///
  /// The modifier flags participate in strict matching: `.char('p',
  /// ctrl: true, shift: true)` matches *exactly* Ctrl+Shift+P, not
  /// plain Ctrl+P.
  const KeyChord.char(
    String char, {
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
  }) : assert(char.length > 0, 'char must be non-empty'),
       _char = char,
       _keyCode = null,
       _ctrl = ctrl,
       _alt = alt,
       _shift = shift,
       _next = null,
       _stepCount = 1;

  /// A special key (arrows, function chords, enter, escape, …) with
  /// optional modifiers.
  ///
  /// Most callers should prefer the named statics (`.escape`, `.up`,
  /// `.f1`, …) and the chain form (`.ctrl.escape`). This factory is
  /// available for cases where the `KeyCode` is held in a variable.
  const KeyChord.key(
    KeyCode keyCode, {
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
  }) : _char = null,
       _keyCode = keyCode,
       _ctrl = ctrl,
       _alt = alt,
       _shift = shift,
       _next = null,
       _stepCount = 1;

  // ---- Named statics for dot-shorthand ------------------------------------
  //
  // Atoms that resolve via Dart 3.10+ dot-shorthand:
  //
  //   Map<KeyChord, _> { .s: save, .ctrl.shift.p: palette, .f1: help }
  //
  // Letters land on `KeyChord.<letter>` as the bare character; modifier
  // atoms (`.ctrl`, `.alt`, `.shift`) land on PendingKeyChord and only
  // become KeyChords once a key atom closes them.

  // Modifier entry-points (typed PendingKeyChord — refuses to be a map key).
  static const PendingKeyChord ctrl = PendingKeyChord._(ctrl: true);
  static const PendingKeyChord alt = PendingKeyChord._(alt: true);
  static const PendingKeyChord shift = PendingKeyChord._(shift: true);

  // Letters: a–z. Uppercase letters are written as `.shift.<letter>`.
  static const KeyChord a = KeyChord._(char: 'a');
  static const KeyChord b = KeyChord._(char: 'b');
  static const KeyChord c = KeyChord._(char: 'c');
  static const KeyChord d = KeyChord._(char: 'd');
  static const KeyChord e = KeyChord._(char: 'e');
  static const KeyChord f = KeyChord._(char: 'f');
  static const KeyChord g = KeyChord._(char: 'g');
  static const KeyChord h = KeyChord._(char: 'h');
  static const KeyChord i = KeyChord._(char: 'i');
  static const KeyChord j = KeyChord._(char: 'j');
  static const KeyChord k = KeyChord._(char: 'k');
  static const KeyChord l = KeyChord._(char: 'l');
  static const KeyChord m = KeyChord._(char: 'm');
  static const KeyChord n = KeyChord._(char: 'n');
  static const KeyChord o = KeyChord._(char: 'o');
  static const KeyChord p = KeyChord._(char: 'p');
  static const KeyChord q = KeyChord._(char: 'q');
  static const KeyChord r = KeyChord._(char: 'r');
  static const KeyChord s = KeyChord._(char: 's');
  static const KeyChord t = KeyChord._(char: 't');
  static const KeyChord u = KeyChord._(char: 'u');
  static const KeyChord v = KeyChord._(char: 'v');
  static const KeyChord w = KeyChord._(char: 'w');
  static const KeyChord x = KeyChord._(char: 'x');
  static const KeyChord y = KeyChord._(char: 'y');
  static const KeyChord z = KeyChord._(char: 'z');

  // Common-but-not-letter atoms.
  static const KeyChord space = KeyChord._(char: ' ');
  static const KeyChord enter = KeyChord._(keyCode: KeyCode.enter);
  static const KeyChord tab = KeyChord._(keyCode: KeyCode.tab);
  static const KeyChord backspace = KeyChord._(keyCode: KeyCode.backspace);
  static const KeyChord escape = KeyChord._(keyCode: KeyCode.escape);
  static const KeyChord delete = KeyChord._(keyCode: KeyCode.delete);
  static const KeyChord insert = KeyChord._(keyCode: KeyCode.insert);

  static const KeyChord up = KeyChord._(keyCode: KeyCode.arrowUp);
  static const KeyChord down = KeyChord._(keyCode: KeyCode.arrowDown);
  static const KeyChord left = KeyChord._(keyCode: KeyCode.arrowLeft);
  static const KeyChord right = KeyChord._(keyCode: KeyCode.arrowRight);

  static const KeyChord home = KeyChord._(keyCode: KeyCode.home);
  static const KeyChord end = KeyChord._(keyCode: KeyCode.end);
  static const KeyChord pageUp = KeyChord._(keyCode: KeyCode.pageUp);
  static const KeyChord pageDown = KeyChord._(keyCode: KeyCode.pageDown);

  static const KeyChord f1 = KeyChord._(keyCode: KeyCode.f1);
  static const KeyChord f2 = KeyChord._(keyCode: KeyCode.f2);
  static const KeyChord f3 = KeyChord._(keyCode: KeyCode.f3);
  static const KeyChord f4 = KeyChord._(keyCode: KeyCode.f4);
  static const KeyChord f5 = KeyChord._(keyCode: KeyCode.f5);
  static const KeyChord f6 = KeyChord._(keyCode: KeyCode.f6);
  static const KeyChord f7 = KeyChord._(keyCode: KeyCode.f7);
  static const KeyChord f8 = KeyChord._(keyCode: KeyCode.f8);
  static const KeyChord f9 = KeyChord._(keyCode: KeyCode.f9);
  static const KeyChord f10 = KeyChord._(keyCode: KeyCode.f10);
  static const KeyChord f11 = KeyChord._(keyCode: KeyCode.f11);
  static const KeyChord f12 = KeyChord._(keyCode: KeyCode.f12);

  /// Shift+Tab — reads better than `.shift.tab` for the common
  /// back-traverse case (and matches how terminals encode it as a
  /// distinct sequence).
  static const KeyChord shiftTab = KeyChord._(
    keyCode: KeyCode.tab,
    shift: true,
  );

  // ---- Matching, equality, display ----------------------------------------

  /// Whether this chord's *first step* matches [event]. Multi-step
  /// chords have their continuation matched by [InputDispatcher] via
  /// [KeyChordInternals.matchesStepAt].
  bool matches(KeyEvent event) => _matchStep(this, event);

  /// Short human-readable label for hint bars: `j` / `Ctrl+S` / `↑` /
  /// `Ctrl+X Ctrl+S`.
  String get hintLabel {
    final buf = StringBuffer(_stepLabel(this));
    var step = _next;
    while (step != null) {
      buf
        ..write(' ')
        ..write(_stepLabel(step));
      step = step._next;
    }
    return buf.toString();
  }

  // Equality and hashing canonicalise uppercase letters into
  // lowercase + shift, so the syntactic variants
  // `KeyChord.char('S')`, `KeyChord.char('s', shift: true)` and
  // `KeyChord.shift.s` all hash and compare equal — they fire on the
  // same events, and treating them as different chords in a
  // `Map<KeyChord, _>` is a footgun nobody wants. The same applies
  // step-by-step in a sequence.
  @override
  bool operator ==(Object other) {
    if (other is! KeyChord) return false;
    KeyChord? a = this;
    KeyChord? b = other;
    while (a != null && b != null) {
      if (a._keyCode != b._keyCode ||
          a._ctrl != b._ctrl ||
          a._alt != b._alt ||
          _canonChar(a) != _canonChar(b) ||
          _canonShift(a) != _canonShift(b)) {
        return false;
      }
      a = a._next;
      b = b._next;
    }
    return a == null && b == null;
  }

  @override
  int get hashCode {
    var h = 17;
    KeyChord? step = this;
    while (step != null) {
      h = Object.hash(
        h,
        _canonChar(step),
        step._keyCode,
        step._ctrl,
        step._alt,
        _canonShift(step),
      );
      step = step._next;
    }
    return h;
  }

  /// Lowercase form of `_char`, or null if the step is keyCode-based.
  static String? _canonChar(KeyChord step) => step._char?.toLowerCase();

  /// Whether shift is asserted at this step, either by the modifier
  /// flag or by an uppercase character (implicit shift).
  static bool _canonShift(KeyChord step) {
    if (step._shift) return true;
    final c = step._char;
    return c != null && c != c.toLowerCase();
  }

  @override
  String toString() => 'KeyChord($hintLabel)';
}

// ---------------------------------------------------------------------------
// PendingKeyChord — intermediate type held when modifiers are pending.
// ---------------------------------------------------------------------------

/// A chord under construction whose pending modifiers have no key yet.
///
/// `PendingKeyChord` is what you get from `KeyChord.ctrl`, `KeyChord.shift`,
/// `KeyChord.ctrl.shift`, or after a non-final step in a sequence like
/// `KeyChord.d.ctrl`. Adding a key atom (`.s`, `.enter`, …) closes the
/// pending modifiers and returns a [KeyChord].
///
/// This type cannot appear inside a `keys: List<KeyChord>` list (or as
/// the key in any `Map<KeyChord, _>`), which is what makes incomplete
/// chords a compile error — `keys: [.ctrl]` fails to type-check.
@immutable
final class PendingKeyChord {
  /// Pending modifiers, holding for the next step.
  final bool _ctrl;
  final bool _alt;
  final bool _shift;

  /// Completed prefix steps preceding the pending modifiers.
  /// `null` if the pending modifiers are the very first thing.
  final KeyChord? _completed;

  const PendingKeyChord._({
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    KeyChord? completed,
  }) : _ctrl = ctrl,
       _alt = alt,
       _shift = shift,
       _completed = completed;

  @override
  String toString() {
    final pending = <String>[
      if (_ctrl) 'Ctrl',
      if (_alt) 'Alt',
      if (_shift) 'Shift',
    ].join('+');
    final c = _completed;
    if (c == null) return 'PendingKeyChord($pending+…)';
    return 'PendingKeyChord(${c.hintLabel} $pending+…)';
  }
}

// ---------------------------------------------------------------------------
// Chain extensions — the dot-syntax that makes everything compose.
// ---------------------------------------------------------------------------

/// Chain getters on [KeyChord]. After a complete step, modifiers
/// (`.ctrl`/`.alt`/`.shift`) start a new pending-modifier phase, and
/// key atoms (`.a`–`.z`, `.enter`, `.f1`, …) start *and* close a new
/// step in one go (forming a sequence with the prior chord).
extension KeyChordChain on KeyChord {
  // Modifier continuations: return PendingKeyChord (mods pending for
  // the next step).
  PendingKeyChord get ctrl => PendingKeyChord._(ctrl: true, completed: this);
  PendingKeyChord get alt => PendingKeyChord._(alt: true, completed: this);
  PendingKeyChord get shift => PendingKeyChord._(shift: true, completed: this);

  // Letter continuations (sequence step).
  KeyChord get a => _appendStep(this, KeyChord.a);
  KeyChord get b => _appendStep(this, KeyChord.b);
  KeyChord get c => _appendStep(this, KeyChord.c);
  KeyChord get d => _appendStep(this, KeyChord.d);
  KeyChord get e => _appendStep(this, KeyChord.e);
  KeyChord get f => _appendStep(this, KeyChord.f);
  KeyChord get g => _appendStep(this, KeyChord.g);
  KeyChord get h => _appendStep(this, KeyChord.h);
  KeyChord get i => _appendStep(this, KeyChord.i);
  KeyChord get j => _appendStep(this, KeyChord.j);
  KeyChord get k => _appendStep(this, KeyChord.k);
  KeyChord get l => _appendStep(this, KeyChord.l);
  KeyChord get m => _appendStep(this, KeyChord.m);
  KeyChord get n => _appendStep(this, KeyChord.n);
  KeyChord get o => _appendStep(this, KeyChord.o);
  KeyChord get p => _appendStep(this, KeyChord.p);
  KeyChord get q => _appendStep(this, KeyChord.q);
  KeyChord get r => _appendStep(this, KeyChord.r);
  KeyChord get s => _appendStep(this, KeyChord.s);
  KeyChord get t => _appendStep(this, KeyChord.t);
  KeyChord get u => _appendStep(this, KeyChord.u);
  KeyChord get v => _appendStep(this, KeyChord.v);
  KeyChord get w => _appendStep(this, KeyChord.w);
  KeyChord get x => _appendStep(this, KeyChord.x);
  KeyChord get y => _appendStep(this, KeyChord.y);
  KeyChord get z => _appendStep(this, KeyChord.z);

  // Specials.
  KeyChord get space => _appendStep(this, KeyChord.space);
  KeyChord get enter => _appendStep(this, KeyChord.enter);
  KeyChord get tab => _appendStep(this, KeyChord.tab);
  KeyChord get backspace => _appendStep(this, KeyChord.backspace);
  KeyChord get escape => _appendStep(this, KeyChord.escape);
  KeyChord get delete => _appendStep(this, KeyChord.delete);
  KeyChord get insert => _appendStep(this, KeyChord.insert);
  KeyChord get up => _appendStep(this, KeyChord.up);
  KeyChord get down => _appendStep(this, KeyChord.down);
  KeyChord get left => _appendStep(this, KeyChord.left);
  KeyChord get right => _appendStep(this, KeyChord.right);
  KeyChord get home => _appendStep(this, KeyChord.home);
  KeyChord get end => _appendStep(this, KeyChord.end);
  KeyChord get pageUp => _appendStep(this, KeyChord.pageUp);
  KeyChord get pageDown => _appendStep(this, KeyChord.pageDown);
  KeyChord get f1 => _appendStep(this, KeyChord.f1);
  KeyChord get f2 => _appendStep(this, KeyChord.f2);
  KeyChord get f3 => _appendStep(this, KeyChord.f3);
  KeyChord get f4 => _appendStep(this, KeyChord.f4);
  KeyChord get f5 => _appendStep(this, KeyChord.f5);
  KeyChord get f6 => _appendStep(this, KeyChord.f6);
  KeyChord get f7 => _appendStep(this, KeyChord.f7);
  KeyChord get f8 => _appendStep(this, KeyChord.f8);
  KeyChord get f9 => _appendStep(this, KeyChord.f9);
  KeyChord get f10 => _appendStep(this, KeyChord.f10);
  KeyChord get f11 => _appendStep(this, KeyChord.f11);
  KeyChord get f12 => _appendStep(this, KeyChord.f12);
}

/// Chain getters on [PendingKeyChord]. Modifier atoms accumulate
/// (still pending); key atoms consume the pending modifiers and return
/// a [KeyChord].
extension PendingKeyChordChain on PendingKeyChord {
  // Stack more modifiers.
  PendingKeyChord get ctrl => _addMod(addCtrl: true);
  PendingKeyChord get alt => _addMod(addAlt: true);
  PendingKeyChord get shift => _addMod(addShift: true);

  PendingKeyChord _addMod({
    bool addCtrl = false,
    bool addAlt = false,
    bool addShift = false,
  }) => PendingKeyChord._(
    ctrl: _ctrl || addCtrl,
    alt: _alt || addAlt,
    shift: _shift || addShift,
    completed: _completed,
  );

  // Letters consume the pending mods.
  KeyChord get a => char('a');
  KeyChord get b => char('b');
  KeyChord get c => char('c');
  KeyChord get d => char('d');
  KeyChord get e => char('e');
  KeyChord get f => char('f');
  KeyChord get g => char('g');
  KeyChord get h => char('h');
  KeyChord get i => char('i');
  KeyChord get j => char('j');
  KeyChord get k => char('k');
  KeyChord get l => char('l');
  KeyChord get m => char('m');
  KeyChord get n => char('n');
  KeyChord get o => char('o');
  KeyChord get p => char('p');
  KeyChord get q => char('q');
  KeyChord get r => char('r');
  KeyChord get s => char('s');
  KeyChord get t => char('t');
  KeyChord get u => char('u');
  KeyChord get v => char('v');
  KeyChord get w => char('w');
  KeyChord get x => char('x');
  KeyChord get y => char('y');
  KeyChord get z => char('z');

  KeyChord get space => char(' ');
  KeyChord get enter => key(KeyCode.enter);
  KeyChord get tab => key(KeyCode.tab);
  KeyChord get backspace => key(KeyCode.backspace);
  KeyChord get escape => key(KeyCode.escape);
  KeyChord get delete => key(KeyCode.delete);
  KeyChord get insert => key(KeyCode.insert);
  KeyChord get up => key(KeyCode.arrowUp);
  KeyChord get down => key(KeyCode.arrowDown);
  KeyChord get left => key(KeyCode.arrowLeft);
  KeyChord get right => key(KeyCode.arrowRight);
  KeyChord get home => key(KeyCode.home);
  KeyChord get end => key(KeyCode.end);
  KeyChord get pageUp => key(KeyCode.pageUp);
  KeyChord get pageDown => key(KeyCode.pageDown);
  KeyChord get f1 => key(KeyCode.f1);
  KeyChord get f2 => key(KeyCode.f2);
  KeyChord get f3 => key(KeyCode.f3);
  KeyChord get f4 => key(KeyCode.f4);
  KeyChord get f5 => key(KeyCode.f5);
  KeyChord get f6 => key(KeyCode.f6);
  KeyChord get f7 => key(KeyCode.f7);
  KeyChord get f8 => key(KeyCode.f8);
  KeyChord get f9 => key(KeyCode.f9);
  KeyChord get f10 => key(KeyCode.f10);
  KeyChord get f11 => key(KeyCode.f11);
  KeyChord get f12 => key(KeyCode.f12);

  /// Escape-hatch: consume the pending modifiers with an arbitrary
  /// character atom. Use for digits / punctuation not covered by the
  /// named statics.
  KeyChord char(String char) {
    final newStep = KeyChord._(
      char: char,
      ctrl: _ctrl,
      alt: _alt,
      shift: _shift,
    );
    final prefix = _completed;
    return prefix == null ? newStep : _appendStep(prefix, newStep);
  }

  /// Escape-hatch: consume the pending modifiers with an arbitrary
  /// [KeyCode] atom.
  KeyChord key(KeyCode keyCode) {
    final newStep = KeyChord._(
      keyCode: keyCode,
      ctrl: _ctrl,
      alt: _alt,
      shift: _shift,
    );
    final prefix = _completed;
    return prefix == null ? newStep : _appendStep(prefix, newStep);
  }
}

// ---------------------------------------------------------------------------
// Internals consumed by [InputDispatcher].
// ---------------------------------------------------------------------------

/// **Framework-internal.** Do not use outside `fleury`. The
/// `$`-prefix and the `Internal` suffix are both intentional — these
/// hooks let the [InputDispatcher] inspect a chord's step structure
/// without exposing the field layout, but they are *not* a stable
/// public API. They may change without notice; app code should treat
/// them as if they were private.
extension $KeyChordInternal on KeyChord {
  /// Number of steps in the chord (`1` for single-keystroke chords).
  /// O(1) — cached at construction.
  int get stepCount => _stepCount;

  /// Whether this chord has more than one step (a sequence).
  bool get isSequence => _next != null;

  /// Matches the step at [index] against [event]. The dispatcher uses
  /// this to walk a chord step-by-step as events arrive.
  bool matchesStepAt(int index, KeyEvent event) {
    final step = _stepAt(index);
    if (step == null) return false;
    return _matchStep(step, event);
  }

  KeyChord? _stepAt(int index) {
    KeyChord? step = this;
    var i = index;
    while (step != null && i > 0) {
      step = step._next;
      i--;
    }
    return step;
  }
}

// ---------------------------------------------------------------------------
// Helpers (private).
// ---------------------------------------------------------------------------

/// Appends [step] (a single-step chord) to the end of [chain]'s step
/// list, returning a new chord. Allocates fresh nodes — chord values
/// are immutable.
KeyChord _appendStep(KeyChord chain, KeyChord step) {
  final n = chain._next;
  return KeyChord._(
    char: chain._char,
    keyCode: chain._keyCode,
    ctrl: chain._ctrl,
    alt: chain._alt,
    shift: chain._shift,
    next: n == null ? step : _appendStep(n, step),
    stepCount: chain._stepCount + step._stepCount,
  );
}

/// Strict per-step matcher. Modifier flags compare equality; for
/// character chords, shift is canonicalised so `.shift.d` matches both
/// `{shift, 'd'}` and `{'D'}` (terminals vary in how they report
/// Shift+letter).
bool _matchStep(KeyChord step, KeyEvent event) {
  // Modifiers.
  if (step._ctrl != event.hasCtrl) return false;
  if (step._alt != event.hasAlt) return false;

  // KeyCode path — strict shift match (special chords never have
  // "implicit shift" the way characters do).
  if (step._keyCode != null) {
    if (event.keyCode != step._keyCode) return false;
    if (step._shift != event.hasShift) return false;
    return true;
  }

  // Character path with shift-canonicalisation.
  final stepChar = step._char;
  final eventChar = event.char;
  if (stepChar == null || eventChar == null) return false;

  final stepLower = stepChar.toLowerCase();
  final eventLower = eventChar.toLowerCase();
  if (stepLower != eventLower) return false;

  // The step asserts shift if EITHER the explicit flag is set OR the
  // declared char is uppercase. The event asserts shift if EITHER the
  // modifier is set OR the reported char is uppercase. Match those.
  final stepWantsShift = step._shift || stepChar != stepLower;
  final eventHasShift = event.hasShift || eventChar != eventLower;
  return stepWantsShift == eventHasShift;
}

/// Per-step label for [hintLabel]: `Ctrl+S`, `↑`, `D`, `Space`.
String _stepLabel(KeyChord step) {
  final mods = <String>[
    if (step._ctrl) 'Ctrl',
    if (step._alt) 'Alt',
    if (step._shift) 'Shift',
  ];
  final kc = step._keyCode;
  final ch = step._char;
  // Bare letters render lowercase ('q'); modifier-prefixed letters
  // render uppercase ('Ctrl+S'). Space is always 'Space'.
  final base = kc != null
      ? _keyCodeLabel(kc)
      : (ch == ' ' ? 'Space' : (mods.isEmpty ? ch! : ch!.toUpperCase()));
  if (mods.isEmpty) return base;
  return '${mods.join('+')}+$base';
}

String _keyCodeLabel(KeyCode k) => switch (k) {
  KeyCode.enter => 'Enter',
  KeyCode.tab => 'Tab',
  KeyCode.backspace => 'Backspace',
  KeyCode.escape => 'Esc',
  KeyCode.arrowUp => '↑',
  KeyCode.arrowDown => '↓',
  KeyCode.arrowLeft => '←',
  KeyCode.arrowRight => '→',
  KeyCode.home => 'Home',
  KeyCode.end => 'End',
  KeyCode.pageUp => 'PgUp',
  KeyCode.pageDown => 'PgDn',
  KeyCode.insert => 'Ins',
  KeyCode.delete => 'Del',
  KeyCode.f1 => 'F1',
  KeyCode.f2 => 'F2',
  KeyCode.f3 => 'F3',
  KeyCode.f4 => 'F4',
  KeyCode.f5 => 'F5',
  KeyCode.f6 => 'F6',
  KeyCode.f7 => 'F7',
  KeyCode.f8 => 'F8',
  KeyCode.f9 => 'F9',
  KeyCode.f10 => 'F10',
  KeyCode.f11 => 'F11',
  KeyCode.f12 => 'F12',
};

// ===========================================================================
// KeyBinding
// ===========================================================================

/// Passed to a [KeyBinding.onEvent] handler. Wraps the [KeyEvent] for
/// the current dispatch and exposes a per-dispatch propagation
/// control ([bubble]).
///
/// **Common case:** ignore everything except the event fields you
/// need. The handler runs, the event is consumed, you write nothing
/// extra:
///
/// ```dart
/// KeyBinding(
///   KeyChord.ctrl.s,
///   onEvent: (_) => save(),
/// )
/// ```
///
/// **Conditional case:** call [bubble] from inside the handler to
/// let the event continue propagating instead of being consumed.
/// Useful for handlers that always *attempt* an action but only
/// *claim* the event when the attempt succeeds:
///
/// ```dart
/// KeyBinding(
///   KeyChord.tab,
///   onEvent: (event) {
///     if (!Focus.of(context).focusNext()) {
///       event.bubble();   // no next focusable — let an outer group try
///     }
///   },
/// )
/// ```
///
/// **Observer case:** call [bubble] unconditionally — the handler
/// runs, and the event propagates to whatever's behind:
///
/// ```dart
/// KeyBinding(
///   KeyChord.ctrl.s,
///   onEvent: (event) { log('save'); event.bubble(); },
/// )
/// ```
///
/// The [bubble] flag is only honoured while the handler is running
/// synchronously. Async work scheduled by the handler may still run
/// after dispatch returns, but a call to `event.bubble()` from after
/// an `await` has no effect — the propagation decision has already
/// been made.
class KeyBindingEvent {
  /// Framework-only constructor. Apps don't construct these directly;
  /// the dispatcher wraps each [KeyEvent] before invoking the
  /// handler. Exposed for tests that want to invoke a [KeyBinding]'s
  /// `onEvent` without standing up a dispatcher.
  KeyBindingEvent(this._raw);

  final KeyEvent _raw;
  bool _shouldBubble = false;

  /// The underlying raw [KeyEvent].
  KeyEvent get raw => _raw;

  /// Whether [bubble] has been called for this dispatch.
  bool get isBubbling => _shouldBubble;

  // Forwarding getters so handlers can read the event directly,
  // without `.raw.` indirection.
  KeyCode? get keyCode => _raw.keyCode;
  String? get char => _raw.char;
  Set<KeyModifier> get modifiers => _raw.modifiers;
  bool get hasCtrl => _raw.hasCtrl;
  bool get hasAlt => _raw.hasAlt;
  bool get hasShift => _raw.hasShift;
  KeyEventType get type => _raw.type;

  /// Let this event continue propagating to ancestor bindings,
  /// `Focus.onKey` handlers, or globals after this binding's handler
  /// returns, instead of being consumed (the default).
  ///
  /// Must be called *during* synchronous execution of the handler.
  /// Calls scheduled via `await` or `Future` have no effect — by the
  /// time they run, the dispatcher has already decided.
  void bubble() => _shouldBubble = true;
}

/// Signature for a key-binding handler. Synchronous; async work
/// scheduled inside the handler runs after the dispatch decision is
/// made, so the propagation choice must be expressed sync (via
/// [KeyBindingEvent.bubble]).
typedef KeyBindingHandler = void Function(KeyBindingEvent event);

/// One key binding: a chord (or several aliases that all fire the
/// same action), a handler, a hint-bar label, and an enabled flag.
/// Propagation is controlled per-dispatch by the handler — see
/// [KeyBindingEvent].
///
/// **Single chord** — positional first argument:
///
/// ```dart
/// KeyBinding(.ctrl.s, onEvent: (_) => save(), label: 'Save')
/// ```
///
/// **Multiple chord aliases** — [KeyBinding.list] takes a list
/// where every entry fires the same handler. The first chord is the
/// canonical one used for the hint bar:
///
/// ```dart
/// KeyBinding.list(
///   [.j, .down],
///   onEvent: (_) => cursorDown(),
///   label: 'Next',
/// )
/// ```
final class KeyBinding {
  /// Bind a single chord.
  KeyBinding(
    KeyChord chord, {
    required this.onEvent,
    this.label,
    this.enabled = true,
    this.hideFromHintBar = false,
  }) : chords = [chord];

  /// Bind multiple chord aliases — every chord in [chords] fires the
  /// same handler. Useful for "any of these keystrokes does X"
  /// (e.g. `j` and `arrowDown` for "next item"). The first chord is
  /// the canonical one shown in the hint bar.
  KeyBinding.list(
    this.chords, {
    required this.onEvent,
    this.label,
    this.enabled = true,
    this.hideFromHintBar = false,
  }) : assert(chords.isNotEmpty, 'aliases list must be non-empty');

  /// The chord(s) this binding matches. Any of them firing triggers
  /// [onEvent]. For single-chord bindings the list has one entry; for
  /// [KeyBinding.list] it has the full alias set in the order
  /// given. The first chord is always the canonical one for hint-bar
  /// display.
  final List<KeyChord> chords;

  /// Handler invoked when this binding matches. Receives a
  /// [KeyBindingEvent] that wraps the raw [KeyEvent] and exposes
  /// per-dispatch propagation control.
  final KeyBindingHandler onEvent;

  /// Short label shown by `KeyHintBar`. When null, the bar
  /// synthesises one from the primary chord's [KeyChord.hintLabel]
  /// (`'Ctrl+S'`, `'↑'`, etc.). A binding with `label == null` AND
  /// `hideFromHintBar == false` is hidden from the bar — descriptive
  /// opt-in is required.
  final String? label;

  /// When false, the binding doesn't match and doesn't appear in the
  /// hint bar. Useful for context-sensitive shortcuts.
  final bool enabled;

  /// When true, the binding still fires but is hidden from
  /// `KeyHintBar`. Useful for ubiquitous bindings like Ctrl+C.
  final bool hideFromHintBar;

  /// The hint string to render in the hint bar — the explicit [label]
  /// if one was supplied, otherwise the canonical chord's
  /// auto-generated label.
  String get displayLabel => label ?? chords.first.hintLabel;
}

// ===========================================================================
// KeyBindings widget
// ===========================================================================

/// Declarative key bindings for a subtree.
///
/// The canonical authoring path is a list of [KeyBinding] objects,
/// each with a chord (or chord aliases), a void handler, an optional
/// hint-bar label, and a `passthrough` flag controlling whether the
/// event bubbles after firing:
///
/// ```dart
/// KeyBindings(
///   bindings: [
///     KeyBinding(
///       KeyChord.ctrl.s,
///       onEvent: (_) => _save(),
///       label: 'Save',
///     ),
///     KeyBinding(
///       KeyChord.escape,
///       onEvent: (_) => _cancel(),
///       label: 'Cancel',
///     ),
///   ],
///   child: app,
/// )
/// ```
///
/// `KeyBindings` wraps its child in a non-focusable `Focus` node
/// (so it appears in the focus chain but never becomes the focused
/// node itself). The bindings it carries are consulted by the
/// `InputDispatcher` when a `KeyEvent` reaches this node's spot in
/// the chain.
class KeyBindings extends StatefulWidget {
  const KeyBindings({super.key, required this.bindings, required this.child});

  final List<KeyBinding> bindings;
  final Widget child;

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
