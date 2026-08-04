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

  // ---- RFC 0020: the complete Kitty functional vocabulary -----------------
  //
  // Everything below is reported only under the Kitty keyboard protocol
  // (PUA codepoints 57358–57454; the exact mapping lives in
  // `key_tables.dart` and is pinned by tests against the spec table).
  // APPEND-ONLY: `SpecialKey.index` is a wire value in the remote codec.

  // Extended function keys.
  f13,
  f14,
  f15,
  f16,
  f17,
  f18,
  f19,
  f20,
  f21,
  f22,
  f23,
  f24,
  f25,
  f26,
  f27,
  f28,
  f29,
  f30,
  f31,
  f32,
  f33,
  f34,
  f35,

  // Locks and system keys.
  capsLock,
  scrollLock,
  numLock,
  printScreen,
  pause,
  menu,

  // Keypad. Distinct from the main-cluster keys with the same meanings —
  // the protocol reports them separately and so does Fleury; nothing is
  // silently folded.
  keypad0,
  keypad1,
  keypad2,
  keypad3,
  keypad4,
  keypad5,
  keypad6,
  keypad7,
  keypad8,
  keypad9,
  keypadDecimal,
  keypadDivide,
  keypadMultiply,
  keypadSubtract,
  keypadAdd,
  keypadEnter,
  keypadEqual,
  keypadSeparator,
  keypadLeft,
  keypadRight,
  keypadUp,
  keypadDown,
  keypadPageUp,
  keypadPageDown,
  keypadHome,
  keypadEnd,
  keypadInsert,
  keypadDelete,
  keypadBegin,

  // Media and volume.
  mediaPlay,
  mediaPause,
  mediaPlayPause,
  mediaReverse,
  mediaStop,
  mediaFastForward,
  mediaRewind,
  mediaTrackNext,
  mediaTrackPrevious,
  mediaRecord,
  volumeDown,
  volumeUp,
  volumeMute,

  // Lone modifier keys, sided. These are *keys* (a Kitty flag-8 / DOM
  // surface reports their own down/up); the `KeyModifier` set on other
  // events remains the modifier-state vocabulary.
  leftShift,
  leftControl,
  leftAlt,
  leftSuper,
  leftHyper,
  leftMeta,
  rightShift,
  rightControl,
  rightAlt,
  rightSuper,
  rightHyper,
  rightMeta,
  isoLevel3Shift,
  isoLevel5Shift,
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
final class KeyCode extends KeySequence implements KeySelector {
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

  // RFC 0020 vocabulary (see the SpecialKey block for grouping).
  static const KeyCode f13 = KeyCode._special(SpecialKey.f13);
  static const KeyCode f14 = KeyCode._special(SpecialKey.f14);
  static const KeyCode f15 = KeyCode._special(SpecialKey.f15);
  static const KeyCode f16 = KeyCode._special(SpecialKey.f16);
  static const KeyCode f17 = KeyCode._special(SpecialKey.f17);
  static const KeyCode f18 = KeyCode._special(SpecialKey.f18);
  static const KeyCode f19 = KeyCode._special(SpecialKey.f19);
  static const KeyCode f20 = KeyCode._special(SpecialKey.f20);
  static const KeyCode f21 = KeyCode._special(SpecialKey.f21);
  static const KeyCode f22 = KeyCode._special(SpecialKey.f22);
  static const KeyCode f23 = KeyCode._special(SpecialKey.f23);
  static const KeyCode f24 = KeyCode._special(SpecialKey.f24);
  static const KeyCode f25 = KeyCode._special(SpecialKey.f25);
  static const KeyCode f26 = KeyCode._special(SpecialKey.f26);
  static const KeyCode f27 = KeyCode._special(SpecialKey.f27);
  static const KeyCode f28 = KeyCode._special(SpecialKey.f28);
  static const KeyCode f29 = KeyCode._special(SpecialKey.f29);
  static const KeyCode f30 = KeyCode._special(SpecialKey.f30);
  static const KeyCode f31 = KeyCode._special(SpecialKey.f31);
  static const KeyCode f32 = KeyCode._special(SpecialKey.f32);
  static const KeyCode f33 = KeyCode._special(SpecialKey.f33);
  static const KeyCode f34 = KeyCode._special(SpecialKey.f34);
  static const KeyCode f35 = KeyCode._special(SpecialKey.f35);
  static const KeyCode capsLock = KeyCode._special(SpecialKey.capsLock);
  static const KeyCode scrollLock = KeyCode._special(SpecialKey.scrollLock);
  static const KeyCode numLock = KeyCode._special(SpecialKey.numLock);
  static const KeyCode printScreen = KeyCode._special(SpecialKey.printScreen);
  static const KeyCode pause = KeyCode._special(SpecialKey.pause);
  static const KeyCode menu = KeyCode._special(SpecialKey.menu);
  static const KeyCode keypad0 = KeyCode._special(SpecialKey.keypad0);
  static const KeyCode keypad1 = KeyCode._special(SpecialKey.keypad1);
  static const KeyCode keypad2 = KeyCode._special(SpecialKey.keypad2);
  static const KeyCode keypad3 = KeyCode._special(SpecialKey.keypad3);
  static const KeyCode keypad4 = KeyCode._special(SpecialKey.keypad4);
  static const KeyCode keypad5 = KeyCode._special(SpecialKey.keypad5);
  static const KeyCode keypad6 = KeyCode._special(SpecialKey.keypad6);
  static const KeyCode keypad7 = KeyCode._special(SpecialKey.keypad7);
  static const KeyCode keypad8 = KeyCode._special(SpecialKey.keypad8);
  static const KeyCode keypad9 = KeyCode._special(SpecialKey.keypad9);
  static const KeyCode keypadDecimal = KeyCode._special(
    SpecialKey.keypadDecimal,
  );
  static const KeyCode keypadDivide = KeyCode._special(SpecialKey.keypadDivide);
  static const KeyCode keypadMultiply = KeyCode._special(
    SpecialKey.keypadMultiply,
  );
  static const KeyCode keypadSubtract = KeyCode._special(
    SpecialKey.keypadSubtract,
  );
  static const KeyCode keypadAdd = KeyCode._special(SpecialKey.keypadAdd);
  static const KeyCode keypadEnter = KeyCode._special(SpecialKey.keypadEnter);
  static const KeyCode keypadEqual = KeyCode._special(SpecialKey.keypadEqual);
  static const KeyCode keypadSeparator = KeyCode._special(
    SpecialKey.keypadSeparator,
  );
  static const KeyCode keypadLeft = KeyCode._special(SpecialKey.keypadLeft);
  static const KeyCode keypadRight = KeyCode._special(SpecialKey.keypadRight);
  static const KeyCode keypadUp = KeyCode._special(SpecialKey.keypadUp);
  static const KeyCode keypadDown = KeyCode._special(SpecialKey.keypadDown);
  static const KeyCode keypadPageUp = KeyCode._special(SpecialKey.keypadPageUp);
  static const KeyCode keypadPageDown = KeyCode._special(
    SpecialKey.keypadPageDown,
  );
  static const KeyCode keypadHome = KeyCode._special(SpecialKey.keypadHome);
  static const KeyCode keypadEnd = KeyCode._special(SpecialKey.keypadEnd);
  static const KeyCode keypadInsert = KeyCode._special(SpecialKey.keypadInsert);
  static const KeyCode keypadDelete = KeyCode._special(SpecialKey.keypadDelete);
  static const KeyCode keypadBegin = KeyCode._special(SpecialKey.keypadBegin);
  static const KeyCode mediaPlay = KeyCode._special(SpecialKey.mediaPlay);
  static const KeyCode mediaPause = KeyCode._special(SpecialKey.mediaPause);
  static const KeyCode mediaPlayPause = KeyCode._special(
    SpecialKey.mediaPlayPause,
  );
  static const KeyCode mediaReverse = KeyCode._special(SpecialKey.mediaReverse);
  static const KeyCode mediaStop = KeyCode._special(SpecialKey.mediaStop);
  static const KeyCode mediaFastForward = KeyCode._special(
    SpecialKey.mediaFastForward,
  );
  static const KeyCode mediaRewind = KeyCode._special(SpecialKey.mediaRewind);
  static const KeyCode mediaTrackNext = KeyCode._special(
    SpecialKey.mediaTrackNext,
  );
  static const KeyCode mediaTrackPrevious = KeyCode._special(
    SpecialKey.mediaTrackPrevious,
  );
  static const KeyCode mediaRecord = KeyCode._special(SpecialKey.mediaRecord);
  static const KeyCode volumeDown = KeyCode._special(SpecialKey.volumeDown);
  static const KeyCode volumeUp = KeyCode._special(SpecialKey.volumeUp);
  static const KeyCode volumeMute = KeyCode._special(SpecialKey.volumeMute);
  static const KeyCode leftShift = KeyCode._special(SpecialKey.leftShift);
  static const KeyCode leftControl = KeyCode._special(SpecialKey.leftControl);
  static const KeyCode leftAlt = KeyCode._special(SpecialKey.leftAlt);
  static const KeyCode leftSuper = KeyCode._special(SpecialKey.leftSuper);
  static const KeyCode leftHyper = KeyCode._special(SpecialKey.leftHyper);
  static const KeyCode leftMeta = KeyCode._special(SpecialKey.leftMeta);
  static const KeyCode rightShift = KeyCode._special(SpecialKey.rightShift);
  static const KeyCode rightControl = KeyCode._special(SpecialKey.rightControl);
  static const KeyCode rightAlt = KeyCode._special(SpecialKey.rightAlt);
  static const KeyCode rightSuper = KeyCode._special(SpecialKey.rightSuper);
  static const KeyCode rightHyper = KeyCode._special(SpecialKey.rightHyper);
  static const KeyCode rightMeta = KeyCode._special(SpecialKey.rightMeta);
  static const KeyCode isoLevel3Shift = KeyCode._special(
    SpecialKey.isoLevel3Shift,
  );
  static const KeyCode isoLevel5Shift = KeyCode._special(
    SpecialKey.isoLevel5Shift,
  );

  /// Canonical instances indexed by [SpecialKey.index] for [forSpecial].
  static const List<KeyCode> _bySpecial = [
    enter, tab, backspace, escape, //
    arrowUp, arrowDown, arrowLeft, arrowRight, //
    home, end, pageUp, pageDown, insert, delete, //
    f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, //
    f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, //
    f25, f26, f27, f28, f29, f30, f31, f32, f33, f34, f35, //
    capsLock, scrollLock, numLock, printScreen, pause, menu, //
    keypad0, keypad1, keypad2, keypad3, keypad4, //
    keypad5, keypad6, keypad7, keypad8, keypad9, //
    keypadDecimal, keypadDivide, keypadMultiply, keypadSubtract, keypadAdd, //
    keypadEnter, keypadEqual, keypadSeparator, //
    keypadLeft, keypadRight, keypadUp, keypadDown, //
    keypadPageUp, keypadPageDown, keypadHome, keypadEnd, //
    keypadInsert, keypadDelete, keypadBegin, //
    mediaPlay, mediaPause, mediaPlayPause, mediaReverse, mediaStop, //
    mediaFastForward, mediaRewind, mediaTrackNext, mediaTrackPrevious, //
    mediaRecord, volumeDown, volumeUp, volumeMute, //
    leftShift, leftControl, leftAlt, leftSuper, leftHyper, leftMeta, //
    rightShift, rightControl, rightAlt, rightSuper, rightHyper, rightMeta, //
    isoLevel3Shift, isoLevel5Shift,
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
  String get selectorId =>
      special != null ? 'key:${special!.name}' : 'chr:$character';

  @override
  _KeyStep _stepAt(int index) {
    assert(index == 0, 'a KeyCode is a single step');
    return _KeyStep(this);
  }
}

// ===========================================================================
// KeySelector + KeyPosition — RFC 0020 §13.
// ===========================================================================

/// One key identity, of either kind: a logical [KeyCode] (what the cap says)
/// or a physical [KeyPosition] (where the key sits).
///
/// This is the type of data boundaries that must hold either kind — a
/// rebindable-controls map, a sampled-controls list, a saved config entry.
/// Application code never constructs a `KeySelector`; values come from the
/// two implementing vocabularies or from [parse].
///
/// Deliberately *not* sealed: exhaustive switches over selectors would break
/// when a future RFC (the input-map layer) adds selector kinds, so external
/// switches always need a default — the same closure trick [KeySequence]
/// uses.
abstract final class KeySelector {
  /// Stable, kind-prefixed identity for persistence: `chr:a` / `key:enter`
  /// for [KeyCode], `pos:w` for [KeyPosition]. Round-trips through [parse].
  String get selectorId;

  /// Parses a [selectorId]. Throws [FormatException] on unknown kinds or
  /// names — unknown kinds may be valid ids written by a future Fleury, so
  /// callers persisting configs should catch and drop rather than crash.
  static KeySelector parse(String id) {
    if (id.startsWith('chr:')) {
      final char = id.substring(4);
      if (char.isEmpty) {
        throw const FormatException('chr: selector needs a character');
      }
      return KeyCode.char(char);
    }
    if (id.startsWith('key:')) {
      final name = id.substring(4);
      for (final key in SpecialKey.values) {
        if (key.name == name) return KeyCode.forSpecial(key);
      }
      throw FormatException('unknown special key "$name"');
    }
    if (id.startsWith('pos:')) {
      final name = id.substring(4);
      for (final position in KeyPosition.values) {
        if (position.name == name) return position;
      }
      throw FormatException('unknown key position "$name"');
    }
    throw FormatException('unknown selector kind in "$id"');
  }
}

/// One physical key position, named after the standard US-QWERTY layout.
///
/// QWERTY is the *naming grid*, not an assumption about the user's layout —
/// the way "the C key" names a piano key. `KeyPosition.w` is the key at W's
/// QWERTY spot: the Z-cap key on French AZERTY, the comma key on Dvorak.
/// Positions are for **spatial** controls (movement clusters, the digit row
/// as weapon-select); mnemonic commands the user reads by name always want
/// [KeyCode].
///
/// Fed by the Kitty protocol's base-layout alternate key (flag 4) and the
/// DOM's `KeyboardEvent.code`; both define themselves against the same US
/// grid, so one vocabulary serves both surfaces. Positional identity is
/// optional **per event** even on capable surfaces ([KeyEvent.position]).
///
/// Each member is one row of RFC 0020 §8.7's specification table: the DOM
/// `code` string, plus exactly one of the unshifted US character (letter /
/// digit / punctuation cluster) or the [SpecialKey] the position produces on
/// a US layout. [intlBackslash] carries neither — the ISO extra key has no
/// US-101 twin. Lookup maps are derived in `key_tables.dart`.
///
/// APPEND-ONLY: `KeyPosition.index` is a wire value in the remote codec.
enum KeyPosition implements KeySelector {
  // Letter cluster.
  a('KeyA', 'a'),
  b('KeyB', 'b'),
  c('KeyC', 'c'),
  d('KeyD', 'd'),
  e('KeyE', 'e'),
  f('KeyF', 'f'),
  g('KeyG', 'g'),
  h('KeyH', 'h'),
  i('KeyI', 'i'),
  j('KeyJ', 'j'),
  k('KeyK', 'k'),
  l('KeyL', 'l'),
  m('KeyM', 'm'),
  n('KeyN', 'n'),
  o('KeyO', 'o'),
  p('KeyP', 'p'),
  q('KeyQ', 'q'),
  r('KeyR', 'r'),
  s('KeyS', 's'),
  t('KeyT', 't'),
  u('KeyU', 'u'),
  v('KeyV', 'v'),
  w('KeyW', 'w'),
  x('KeyX', 'x'),
  y('KeyY', 'y'),
  z('KeyZ', 'z'),

  // Number row. Positional digits are unshifted on every layout — the reason
  // spatial digit controls (weapon rows) must be positions, not codes:
  // logical '1' on AZERTY requires Shift.
  digit0('Digit0', '0'),
  digit1('Digit1', '1'),
  digit2('Digit2', '2'),
  digit3('Digit3', '3'),
  digit4('Digit4', '4'),
  digit5('Digit5', '5'),
  digit6('Digit6', '6'),
  digit7('Digit7', '7'),
  digit8('Digit8', '8'),
  digit9('Digit9', '9'),

  // Punctuation cluster (unshifted US caps).
  backquote('Backquote', '`'),
  minus('Minus', '-'),
  equal('Equal', '='),
  bracketLeft('BracketLeft', '['),
  bracketRight('BracketRight', ']'),
  backslash('Backslash', r'\'),
  semicolon('Semicolon', ';'),
  quote('Quote', "'"),
  comma('Comma', ','),
  period('Period', '.'),
  slash('Slash', '/'),

  /// The ISO extra key between left Shift and Z. No US-101 twin: on a
  /// surface without positional reporting this position can never match.
  intlBackslash('IntlBackslash'),

  space('Space', ' '),

  // Editing / navigation cluster.
  enter('Enter', null, SpecialKey.enter),
  tab('Tab', null, SpecialKey.tab),
  backspace('Backspace', null, SpecialKey.backspace),
  escape('Escape', null, SpecialKey.escape),
  insert('Insert', null, SpecialKey.insert),
  delete('Delete', null, SpecialKey.delete),
  home('Home', null, SpecialKey.home),
  end('End', null, SpecialKey.end),
  pageUp('PageUp', null, SpecialKey.pageUp),
  pageDown('PageDown', null, SpecialKey.pageDown),
  arrowUp('ArrowUp', null, SpecialKey.arrowUp),
  arrowDown('ArrowDown', null, SpecialKey.arrowDown),
  arrowLeft('ArrowLeft', null, SpecialKey.arrowLeft),
  arrowRight('ArrowRight', null, SpecialKey.arrowRight),

  // Function row.
  f1('F1', null, SpecialKey.f1),
  f2('F2', null, SpecialKey.f2),
  f3('F3', null, SpecialKey.f3),
  f4('F4', null, SpecialKey.f4),
  f5('F5', null, SpecialKey.f5),
  f6('F6', null, SpecialKey.f6),
  f7('F7', null, SpecialKey.f7),
  f8('F8', null, SpecialKey.f8),
  f9('F9', null, SpecialKey.f9),
  f10('F10', null, SpecialKey.f10),
  f11('F11', null, SpecialKey.f11),
  f12('F12', null, SpecialKey.f12),
  f13('F13', null, SpecialKey.f13),
  f14('F14', null, SpecialKey.f14),
  f15('F15', null, SpecialKey.f15),
  f16('F16', null, SpecialKey.f16),
  f17('F17', null, SpecialKey.f17),
  f18('F18', null, SpecialKey.f18),
  f19('F19', null, SpecialKey.f19),
  f20('F20', null, SpecialKey.f20),
  f21('F21', null, SpecialKey.f21),
  f22('F22', null, SpecialKey.f22),
  f23('F23', null, SpecialKey.f23),
  f24('F24', null, SpecialKey.f24),

  // Locks and system keys.
  capsLock('CapsLock', null, SpecialKey.capsLock),
  numLock('NumLock', null, SpecialKey.numLock),
  scrollLock('ScrollLock', null, SpecialKey.scrollLock),
  printScreen('PrintScreen', null, SpecialKey.printScreen),
  pause('Pause', null, SpecialKey.pause),
  contextMenu('ContextMenu', null, SpecialKey.menu),

  // Keypad.
  numpad0('Numpad0', null, SpecialKey.keypad0),
  numpad1('Numpad1', null, SpecialKey.keypad1),
  numpad2('Numpad2', null, SpecialKey.keypad2),
  numpad3('Numpad3', null, SpecialKey.keypad3),
  numpad4('Numpad4', null, SpecialKey.keypad4),
  numpad5('Numpad5', null, SpecialKey.keypad5),
  numpad6('Numpad6', null, SpecialKey.keypad6),
  numpad7('Numpad7', null, SpecialKey.keypad7),
  numpad8('Numpad8', null, SpecialKey.keypad8),
  numpad9('Numpad9', null, SpecialKey.keypad9),
  numpadDecimal('NumpadDecimal', null, SpecialKey.keypadDecimal),
  numpadDivide('NumpadDivide', null, SpecialKey.keypadDivide),
  numpadMultiply('NumpadMultiply', null, SpecialKey.keypadMultiply),
  numpadSubtract('NumpadSubtract', null, SpecialKey.keypadSubtract),
  numpadAdd('NumpadAdd', null, SpecialKey.keypadAdd),
  numpadEnter('NumpadEnter', null, SpecialKey.keypadEnter),
  numpadEqual('NumpadEqual', null, SpecialKey.keypadEqual),
  numpadComma('NumpadComma', null, SpecialKey.keypadSeparator),

  // Sided modifier keys. DOM "Meta" is the Command/Windows key — the Kitty
  // vocabulary calls the same physical keys "super".
  shiftLeft('ShiftLeft', null, SpecialKey.leftShift),
  shiftRight('ShiftRight', null, SpecialKey.rightShift),
  controlLeft('ControlLeft', null, SpecialKey.leftControl),
  controlRight('ControlRight', null, SpecialKey.rightControl),
  altLeft('AltLeft', null, SpecialKey.leftAlt),
  altRight('AltRight', null, SpecialKey.rightAlt),
  metaLeft('MetaLeft', null, SpecialKey.leftSuper),
  metaRight('MetaRight', null, SpecialKey.rightSuper);

  const KeyPosition(this.domCode, [this.usCharacter, this.special])
    : assert(
        usCharacter == null || special == null,
        'a position produces a character or a special on the US layout, '
        'never both',
      );

  /// The DOM `KeyboardEvent.code` value for this position.
  final String domCode;

  /// The unshifted character this position produces on a US layout, for
  /// character-cluster positions; null otherwise. Kitty's base-layout
  /// alternate codes are the codepoints of these characters.
  final String? usCharacter;

  /// The [SpecialKey] this position produces on a US layout, for functional
  /// positions; null otherwise.
  final SpecialKey? special;

  /// The logical key this position produces on a US layout — the one-way
  /// degradation target: a positional query against a press whose position
  /// is unknown matches this twin instead (RFC 0020 §13.3). Null only for
  /// positions with no US-101 twin ([intlBackslash]).
  KeyCode? get usTwin {
    final s = special;
    if (s != null) return KeyCode.forSpecial(s);
    final c = usCharacter;
    if (c != null) return KeyCode.char(c);
    return null;
  }

  @override
  String get selectorId => 'pos:$name';
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

  // RFC 0020 vocabulary forwards, so `.f13` / `.mediaPlay` resolve in a
  // KeySequence context like every other atom. (Sided modifier *keys* and
  // keypad keys are bindable via their KeyCode statics; they are omitted
  // here because bare `.leftShift` in a binding position is more often the
  // start of a mistyped chord than an intended lone-modifier binding.)
  static const KeyCode f13 = KeyCode.f13;
  static const KeyCode f14 = KeyCode.f14;
  static const KeyCode f15 = KeyCode.f15;
  static const KeyCode f16 = KeyCode.f16;
  static const KeyCode f17 = KeyCode.f17;
  static const KeyCode f18 = KeyCode.f18;
  static const KeyCode f19 = KeyCode.f19;
  static const KeyCode f20 = KeyCode.f20;
  static const KeyCode f21 = KeyCode.f21;
  static const KeyCode f22 = KeyCode.f22;
  static const KeyCode f23 = KeyCode.f23;
  static const KeyCode f24 = KeyCode.f24;
  static const KeyCode f25 = KeyCode.f25;
  static const KeyCode f26 = KeyCode.f26;
  static const KeyCode f27 = KeyCode.f27;
  static const KeyCode f28 = KeyCode.f28;
  static const KeyCode f29 = KeyCode.f29;
  static const KeyCode f30 = KeyCode.f30;
  static const KeyCode f31 = KeyCode.f31;
  static const KeyCode f32 = KeyCode.f32;
  static const KeyCode f33 = KeyCode.f33;
  static const KeyCode f34 = KeyCode.f34;
  static const KeyCode f35 = KeyCode.f35;
  static const KeyCode printScreen = KeyCode.printScreen;
  static const KeyCode pause = KeyCode.pause;
  static const KeyCode menu = KeyCode.menu;
  static const KeyCode mediaPlay = KeyCode.mediaPlay;
  static const KeyCode mediaPause = KeyCode.mediaPause;
  static const KeyCode mediaPlayPause = KeyCode.mediaPlayPause;
  static const KeyCode mediaStop = KeyCode.mediaStop;
  static const KeyCode mediaTrackNext = KeyCode.mediaTrackNext;
  static const KeyCode mediaTrackPrevious = KeyCode.mediaTrackPrevious;
  static const KeyCode volumeDown = KeyCode.volumeDown;
  static const KeyCode volumeUp = KeyCode.volumeUp;
  static const KeyCode volumeMute = KeyCode.volumeMute;

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
  /// as [TextInputEvent], otherwise a [KeyEvent] carrying the code and
  /// modifiers. Shift on a cased letter was folded into the character's case
  /// by [build] (so `Shift+G` is the bare printable `G`); a Shift that
  /// survived — a non-cased printable like `Shift+1` or `Shift+Space` — keeps
  /// the modifier and so takes the [KeyEvent] branch, matching what enhanced
  /// terminal reporting delivers (a bare `TextInputEvent` would drop it and
  /// fail to match a shifted binding).
  TuiEvent asInputEvent() {
    final character = code.character;
    final bare =
        character != null && !ctrl && !alt && !shift && !superKey && !meta;
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
  // RFC 0020 vocabulary. Labels are space-free (multi-step hint labels join
  // steps with spaces) and every label round-trips through
  // [KeySequence.parse] via [_specialByName].
  SpecialKey.f13 => 'F13',
  SpecialKey.f14 => 'F14',
  SpecialKey.f15 => 'F15',
  SpecialKey.f16 => 'F16',
  SpecialKey.f17 => 'F17',
  SpecialKey.f18 => 'F18',
  SpecialKey.f19 => 'F19',
  SpecialKey.f20 => 'F20',
  SpecialKey.f21 => 'F21',
  SpecialKey.f22 => 'F22',
  SpecialKey.f23 => 'F23',
  SpecialKey.f24 => 'F24',
  SpecialKey.f25 => 'F25',
  SpecialKey.f26 => 'F26',
  SpecialKey.f27 => 'F27',
  SpecialKey.f28 => 'F28',
  SpecialKey.f29 => 'F29',
  SpecialKey.f30 => 'F30',
  SpecialKey.f31 => 'F31',
  SpecialKey.f32 => 'F32',
  SpecialKey.f33 => 'F33',
  SpecialKey.f34 => 'F34',
  SpecialKey.f35 => 'F35',
  SpecialKey.capsLock => 'CapsLock',
  SpecialKey.scrollLock => 'ScrollLock',
  SpecialKey.numLock => 'NumLock',
  SpecialKey.printScreen => 'PrintScreen',
  SpecialKey.pause => 'Pause',
  SpecialKey.menu => 'Menu',
  SpecialKey.keypad0 => 'KP0',
  SpecialKey.keypad1 => 'KP1',
  SpecialKey.keypad2 => 'KP2',
  SpecialKey.keypad3 => 'KP3',
  SpecialKey.keypad4 => 'KP4',
  SpecialKey.keypad5 => 'KP5',
  SpecialKey.keypad6 => 'KP6',
  SpecialKey.keypad7 => 'KP7',
  SpecialKey.keypad8 => 'KP8',
  SpecialKey.keypad9 => 'KP9',
  SpecialKey.keypadDecimal => 'KPDecimal',
  SpecialKey.keypadDivide => 'KPDivide',
  SpecialKey.keypadMultiply => 'KPMultiply',
  SpecialKey.keypadSubtract => 'KPSubtract',
  SpecialKey.keypadAdd => 'KPAdd',
  SpecialKey.keypadEnter => 'KPEnter',
  SpecialKey.keypadEqual => 'KPEqual',
  SpecialKey.keypadSeparator => 'KPSeparator',
  SpecialKey.keypadLeft => 'KPLeft',
  SpecialKey.keypadRight => 'KPRight',
  SpecialKey.keypadUp => 'KPUp',
  SpecialKey.keypadDown => 'KPDown',
  SpecialKey.keypadPageUp => 'KPPgUp',
  SpecialKey.keypadPageDown => 'KPPgDn',
  SpecialKey.keypadHome => 'KPHome',
  SpecialKey.keypadEnd => 'KPEnd',
  SpecialKey.keypadInsert => 'KPIns',
  SpecialKey.keypadDelete => 'KPDel',
  SpecialKey.keypadBegin => 'KPBegin',
  SpecialKey.mediaPlay => 'MediaPlay',
  SpecialKey.mediaPause => 'MediaPause',
  SpecialKey.mediaPlayPause => 'MediaPlayPause',
  SpecialKey.mediaReverse => 'MediaReverse',
  SpecialKey.mediaStop => 'MediaStop',
  SpecialKey.mediaFastForward => 'MediaFastForward',
  SpecialKey.mediaRewind => 'MediaRewind',
  SpecialKey.mediaTrackNext => 'MediaNext',
  SpecialKey.mediaTrackPrevious => 'MediaPrev',
  SpecialKey.mediaRecord => 'MediaRecord',
  SpecialKey.volumeDown => 'VolumeDown',
  SpecialKey.volumeUp => 'VolumeUp',
  SpecialKey.volumeMute => 'Mute',
  SpecialKey.leftShift => 'LShift',
  SpecialKey.leftControl => 'LCtrl',
  SpecialKey.leftAlt => 'LAlt',
  SpecialKey.leftSuper => 'LSuper',
  SpecialKey.leftHyper => 'LHyper',
  SpecialKey.leftMeta => 'LMeta',
  SpecialKey.rightShift => 'RShift',
  SpecialKey.rightControl => 'RCtrl',
  SpecialKey.rightAlt => 'RAlt',
  SpecialKey.rightSuper => 'RSuper',
  SpecialKey.rightHyper => 'RHyper',
  SpecialKey.rightMeta => 'RMeta',
  SpecialKey.isoLevel3Shift => 'ISOLevel3',
  SpecialKey.isoLevel5Shift => 'ISOLevel5',
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
  // RFC 0020 vocabulary — every [_specialLabel] form lowercased, plus
  // long-form aliases.
  'f13': SpecialKey.f13,
  'f14': SpecialKey.f14,
  'f15': SpecialKey.f15,
  'f16': SpecialKey.f16,
  'f17': SpecialKey.f17,
  'f18': SpecialKey.f18,
  'f19': SpecialKey.f19,
  'f20': SpecialKey.f20,
  'f21': SpecialKey.f21,
  'f22': SpecialKey.f22,
  'f23': SpecialKey.f23,
  'f24': SpecialKey.f24,
  'f25': SpecialKey.f25,
  'f26': SpecialKey.f26,
  'f27': SpecialKey.f27,
  'f28': SpecialKey.f28,
  'f29': SpecialKey.f29,
  'f30': SpecialKey.f30,
  'f31': SpecialKey.f31,
  'f32': SpecialKey.f32,
  'f33': SpecialKey.f33,
  'f34': SpecialKey.f34,
  'f35': SpecialKey.f35,
  'capslock': SpecialKey.capsLock,
  'scrolllock': SpecialKey.scrollLock,
  'numlock': SpecialKey.numLock,
  'printscreen': SpecialKey.printScreen,
  'prtsc': SpecialKey.printScreen,
  'pause': SpecialKey.pause,
  'menu': SpecialKey.menu,
  'kp0': SpecialKey.keypad0,
  'kp1': SpecialKey.keypad1,
  'kp2': SpecialKey.keypad2,
  'kp3': SpecialKey.keypad3,
  'kp4': SpecialKey.keypad4,
  'kp5': SpecialKey.keypad5,
  'kp6': SpecialKey.keypad6,
  'kp7': SpecialKey.keypad7,
  'kp8': SpecialKey.keypad8,
  'kp9': SpecialKey.keypad9,
  'kpdecimal': SpecialKey.keypadDecimal,
  'kpdivide': SpecialKey.keypadDivide,
  'kpmultiply': SpecialKey.keypadMultiply,
  'kpsubtract': SpecialKey.keypadSubtract,
  'kpadd': SpecialKey.keypadAdd,
  'kpenter': SpecialKey.keypadEnter,
  'kpequal': SpecialKey.keypadEqual,
  'kpseparator': SpecialKey.keypadSeparator,
  'kpleft': SpecialKey.keypadLeft,
  'kpright': SpecialKey.keypadRight,
  'kpup': SpecialKey.keypadUp,
  'kpdown': SpecialKey.keypadDown,
  'kppgup': SpecialKey.keypadPageUp,
  'kppgdn': SpecialKey.keypadPageDown,
  'kphome': SpecialKey.keypadHome,
  'kpend': SpecialKey.keypadEnd,
  'kpins': SpecialKey.keypadInsert,
  'kpdel': SpecialKey.keypadDelete,
  'kpbegin': SpecialKey.keypadBegin,
  'mediaplay': SpecialKey.mediaPlay,
  'mediapause': SpecialKey.mediaPause,
  'mediaplaypause': SpecialKey.mediaPlayPause,
  'mediareverse': SpecialKey.mediaReverse,
  'mediastop': SpecialKey.mediaStop,
  'mediafastforward': SpecialKey.mediaFastForward,
  'mediarewind': SpecialKey.mediaRewind,
  'medianext': SpecialKey.mediaTrackNext,
  'mediaprev': SpecialKey.mediaTrackPrevious,
  'mediarecord': SpecialKey.mediaRecord,
  'volumedown': SpecialKey.volumeDown,
  'volumeup': SpecialKey.volumeUp,
  'mute': SpecialKey.volumeMute,
  'volumemute': SpecialKey.volumeMute,
  'lshift': SpecialKey.leftShift,
  'leftshift': SpecialKey.leftShift,
  'lctrl': SpecialKey.leftControl,
  'leftctrl': SpecialKey.leftControl,
  'leftcontrol': SpecialKey.leftControl,
  'lalt': SpecialKey.leftAlt,
  'leftalt': SpecialKey.leftAlt,
  'lsuper': SpecialKey.leftSuper,
  'leftsuper': SpecialKey.leftSuper,
  'lhyper': SpecialKey.leftHyper,
  'lefthyper': SpecialKey.leftHyper,
  'lmeta': SpecialKey.leftMeta,
  'leftmeta': SpecialKey.leftMeta,
  'rshift': SpecialKey.rightShift,
  'rightshift': SpecialKey.rightShift,
  'rctrl': SpecialKey.rightControl,
  'rightctrl': SpecialKey.rightControl,
  'rightcontrol': SpecialKey.rightControl,
  'ralt': SpecialKey.rightAlt,
  'rightalt': SpecialKey.rightAlt,
  'rsuper': SpecialKey.rightSuper,
  'rightsuper': SpecialKey.rightSuper,
  'rhyper': SpecialKey.rightHyper,
  'righthyper': SpecialKey.rightHyper,
  'rmeta': SpecialKey.rightMeta,
  'rightmeta': SpecialKey.rightMeta,
  'isolevel3': SpecialKey.isoLevel3Shift,
  'isolevel5': SpecialKey.isoLevel5Shift,
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
    this.position,
    this.synthesized = false,
  });

  /// The logical key this event reports.
  final KeyCode code;

  /// The physical position, when the backend knew it **for this event** —
  /// Kitty's base-layout alternate (flag 4) or the DOM's `code`. Null means
  /// unknown for this press, not unsupported by the surface: even capable
  /// backends omit it per event (DOM `Unidentified`, a terminal skipping
  /// the alternate field). Never silently substituted; [matches] applies
  /// the one-way degradation rule instead.
  final KeyPosition? position;

  final Set<KeyModifier> modifiers;

  /// Whether this is a press, auto-repeat, or release. Always
  /// [KeyEventType.down] unless the Kitty protocol's event-type reporting
  /// is enabled.
  final KeyEventType type;

  /// True when Fleury generated this event to repair or recover backend
  /// state (RFC 0020 §6's synthesis taxonomy) rather than receiving the
  /// phase from the source. Provenance for diagnostics; the dispatch rules
  /// for each synthesis origin are the taxonomy table's, not the flag's.
  final bool synthesized;

  /// Whether this event is [selector]'s key, by identity alone.
  ///
  /// Modifiers are deliberately ignored — this answers "is it that key",
  /// not "is it that gesture" (a Ctrl+W event matches both `KeyCode.w` and
  /// `KeyPosition.w`). For a [KeyPosition], the one-way degradation rule
  /// applies per press: a known position matches by position only; an
  /// unknown one falls back to the selector's [KeyPosition.usTwin]. A
  /// [KeyCode] selector never upgrades to positional matching.
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
      other.position == position &&
      other.synthesized == synthesized &&
      _setEquals(other.modifiers, modifiers);

  @override
  int get hashCode => Object.hash(
    code,
    type,
    position,
    synthesized,
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
    final suffix = [
      if (type != KeyEventType.down) ' ${type.name}',
      if (position != null) ' @${position!.name}',
      if (synthesized) ' synth',
    ].join();
    return 'KeyEvent(${parts.join('+')}$suffix)';
  }
}

/// One normalized input packet: a key event, committed text, or both —
/// RFC 0020 §5's batch model.
///
/// A batch exists wherever key identity and produced text arrive as one
/// physical report and their correlation must survive transport: a Kitty
/// lifecycle-mode printable (`CSI 97;1;97 u` is the A key *and* the text
/// "a"), a DOM keydown paired with its input event, the wire, and the test
/// driver. Bare [KeyEvent]/[TextInputEvent] values remain valid stream
/// elements — a bare event is semantically a one-payload batch; the
/// dispatcher normalizes at entry.
///
/// [timeStamp] is monotonic receipt time at the source; [sequence] is a
/// per-source counter. Both are diagnostics/timing data, deliberately
/// excluded from [==] — batch identity is its payload, and timing in
/// equality would poison test assertions and event dedup (RFC 0020 §23,
/// the timestamp deferral).
@immutable
final class InputBatch extends TuiEvent {
  const InputBatch({
    this.key,
    this.committedText,
    this.timeStamp = Duration.zero,
    this.sequence = 0,
  }) : assert(
         key != null || committedText != null,
         'a batch carries a key, text, or both — never neither',
       );

  /// The key half, when the report carried key identity.
  final KeyEvent? key;

  /// The committed text half, when the report produced text.
  final String? committedText;

  /// Monotonic receipt time at the emitting source.
  final Duration timeStamp;

  /// Per-source ordering counter.
  final int sequence;

  @override
  bool operator ==(Object other) =>
      other is InputBatch &&
      other.key == key &&
      other.committedText == committedText;

  @override
  int get hashCode => Object.hash(InputBatch, key, committedText);

  @override
  String toString() =>
      'InputBatch(${key ?? ''}${key != null && committedText != null ? ' + ' : ''}'
      '${committedText != null ? '"$committedText"' : ''})';
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
