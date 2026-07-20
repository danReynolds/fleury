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
/// Per RFC 0018, `KeyCode` is the one-step form of a key sequence; the
/// sequence supertype lands with the binding-surface rework.
@immutable
final class KeyCode {
  /// A printable-character key.
  ///
  /// [character] must be a single grapheme cluster (one user-perceived
  /// character); the parsers, dispatcher, and codec only construct such
  /// values. Matching against events uses the character exactly as given.
  const KeyCode.char(String this.character)
    : special = null,
      assert(character.length > 0, 'character must be non-empty');

  const KeyCode._special(this.special) : character = null;

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
}

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
