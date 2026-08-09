// The RFC 0020 §8.7 specification table: protocol identities for the key
// vocabulary, in one place.
//
// Sources of truth this file transcribes:
//   - Kitty keyboard protocol, "Functional key definitions"
//     (https://sw.kovidgoyal.net/kitty/keyboard-protocol/): the PUA
//     codepoints 57358–57454 for keys with no legacy escape encoding.
//   - The per-member DOM `code` strings and US characters live ON the
//     [KeyPosition] members themselves (events.dart) — one row per key.
//
// Tests pin every value against the spec ranges
// (test/input/key_vocabulary_test.dart). Hand-maintained switch fragments
// over key identities are forbidden elsewhere in the tree; consumers use
// these maps.

import 'events.dart';

/// Kitty functional-key PUA codepoint → [SpecialKey].
///
/// Keys with legacy escape encodings (Enter 13, Tab 9, Backspace 127,
/// Escape 27, and the CSI `~`/letter-final family: arrows, Home/End,
/// PgUp/PgDn, Insert/Delete, F1–F12) are parsed from those encodings and do
/// not appear here — except [SpecialKey.keypadBegin], which the protocol
/// gives both a legacy form (`CSI 1 E`) and a PUA value.
const Map<int, SpecialKey> kittyFunctionalKeys = {
  57358: SpecialKey.capsLock,
  57359: SpecialKey.scrollLock,
  57360: SpecialKey.numLock,
  57361: SpecialKey.printScreen,
  57362: SpecialKey.pause,
  57363: SpecialKey.menu,
  57376: SpecialKey.f13,
  57377: SpecialKey.f14,
  57378: SpecialKey.f15,
  57379: SpecialKey.f16,
  57380: SpecialKey.f17,
  57381: SpecialKey.f18,
  57382: SpecialKey.f19,
  57383: SpecialKey.f20,
  57384: SpecialKey.f21,
  57385: SpecialKey.f22,
  57386: SpecialKey.f23,
  57387: SpecialKey.f24,
  57388: SpecialKey.f25,
  57389: SpecialKey.f26,
  57390: SpecialKey.f27,
  57391: SpecialKey.f28,
  57392: SpecialKey.f29,
  57393: SpecialKey.f30,
  57394: SpecialKey.f31,
  57395: SpecialKey.f32,
  57396: SpecialKey.f33,
  57397: SpecialKey.f34,
  57398: SpecialKey.f35,
  57399: SpecialKey.keypad0,
  57400: SpecialKey.keypad1,
  57401: SpecialKey.keypad2,
  57402: SpecialKey.keypad3,
  57403: SpecialKey.keypad4,
  57404: SpecialKey.keypad5,
  57405: SpecialKey.keypad6,
  57406: SpecialKey.keypad7,
  57407: SpecialKey.keypad8,
  57408: SpecialKey.keypad9,
  57409: SpecialKey.keypadDecimal,
  57410: SpecialKey.keypadDivide,
  57411: SpecialKey.keypadMultiply,
  57412: SpecialKey.keypadSubtract,
  57413: SpecialKey.keypadAdd,
  57414: SpecialKey.keypadEnter,
  57415: SpecialKey.keypadEqual,
  57416: SpecialKey.keypadSeparator,
  57417: SpecialKey.keypadLeft,
  57418: SpecialKey.keypadRight,
  57419: SpecialKey.keypadUp,
  57420: SpecialKey.keypadDown,
  57421: SpecialKey.keypadPageUp,
  57422: SpecialKey.keypadPageDown,
  57423: SpecialKey.keypadHome,
  57424: SpecialKey.keypadEnd,
  57425: SpecialKey.keypadInsert,
  57426: SpecialKey.keypadDelete,
  57427: SpecialKey.keypadBegin,
  57428: SpecialKey.mediaPlay,
  57429: SpecialKey.mediaPause,
  57430: SpecialKey.mediaPlayPause,
  57431: SpecialKey.mediaReverse,
  57432: SpecialKey.mediaStop,
  57433: SpecialKey.mediaFastForward,
  57434: SpecialKey.mediaRewind,
  57435: SpecialKey.mediaTrackNext,
  57436: SpecialKey.mediaTrackPrevious,
  57437: SpecialKey.mediaRecord,
  57438: SpecialKey.volumeDown,
  57439: SpecialKey.volumeUp,
  57440: SpecialKey.volumeMute,
  57441: SpecialKey.leftShift,
  57442: SpecialKey.leftControl,
  57443: SpecialKey.leftAlt,
  57444: SpecialKey.leftSuper,
  57445: SpecialKey.leftHyper,
  57446: SpecialKey.leftMeta,
  57447: SpecialKey.rightShift,
  57448: SpecialKey.rightControl,
  57449: SpecialKey.rightAlt,
  57450: SpecialKey.rightSuper,
  57451: SpecialKey.rightHyper,
  57452: SpecialKey.rightMeta,
  57453: SpecialKey.isoLevel3Shift,
  57454: SpecialKey.isoLevel5Shift,
};

/// Reverse of [kittyFunctionalKeys], built once. Unmodifiable: these tables
/// are process-global resolution state — a writable handle would let any
/// consumer silently corrupt key identity for the whole runtime.
final Map<SpecialKey, int> kittyCodepointOf = Map.unmodifiable({
  for (final MapEntry(:key, :value) in kittyFunctionalKeys.entries) value: key,
});

/// US-layout codepoint → position, for the character cluster. This is the
/// map Kitty's flag-4 *base layout key* resolves through: an AZERTY
/// terminal reporting base 0x77 ('w') means the physical key at QWERTY-W.
final Map<int, KeyPosition> positionByUsCodepoint = Map.unmodifiable({
  for (final position in KeyPosition.values)
    if (position.usCharacter != null)
      position.usCharacter!.codeUnitAt(0): position,
});

/// DOM `KeyboardEvent.code` → position (total over the vocabulary).
final Map<String, KeyPosition> positionByDomCode = Map.unmodifiable({
  for (final position in KeyPosition.values) position.domCode: position,
});

/// [SpecialKey] → the position producing it on a US layout, where one
/// exists. Functional keys are layout-independent, so a parsed special
/// implies its position without flag-4 data — this is how arrows and
/// F-keys get positions on every tier that reports them as keys.
/// Partial: the keypad *navigation* specials (KP_LEFT…KP_BEGIN) have no
/// DOM position (browsers report `Numpad4` etc. regardless of NumLock) and
/// hyper/ISO-level modifiers have no standard DOM code.
final Map<SpecialKey, KeyPosition> positionBySpecial = Map.unmodifiable({
  for (final position in KeyPosition.values)
    if (position.special != null) position.special!: position,
});
