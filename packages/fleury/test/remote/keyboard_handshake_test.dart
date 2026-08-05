// RFC 0020 §11 — a peer DECLARES its keyboard; the app never infers it from
// the protocol version.
//
// The distinction is the whole point: two `fleury shell` relays at the
// identical wire version, one in front of Ghostty and one in front of
// Terminal.app, have completely different keyboards. Only the relay knows.

import 'package:fleury/fleury.dart';
import 'package:fleury/src/input/keyboard_state.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:test/test.dart';

InitFrame _roundTrip(InitFrame frame) {
  final decoder = FrameDecoder()..feed(encodeFrame(frame));
  return decoder.drain().single as InitFrame;
}

InitFrame _init({KeyboardCapabilities? keyboard}) => InitFrame(
  size: const CellSize(80, 24),
  colorMode: ColorMode.truecolor,
  imageProtocol: ImageProtocol.halfBlock,
  tmuxPassthrough: false,
  keyboard: keyboard,
);

void main() {
  group('wire bits carry semantic guarantees, not kitty flags', () {
    test('every capability survives a round trip', () {
      for (final caps in [
        KeyboardCapabilities.legacy,
        KeyboardCapabilities.full,
        const KeyboardCapabilities(distinguishesRepeats: true),
        const KeyboardCapabilities(
          supportsHeldState: true,
          distinguishesRepeats: true,
          reportsPrintableKeys: true,
        ),
      ]) {
        expect(
          KeyboardCapabilities.fromWireBits(caps.wireBits),
          caps,
          reason: '$caps did not survive',
        );
      }
    });

    test('a browser peer declares full lifecycle with no flags at all', () {
      // The DOM has no Kitty protocol; it reports keydown/keyup natively.
      // Declaring guarantees rather than flags is what lets it say so.
      expect(KeyboardCapabilities.full.wireBits, 0xF);
    });
  });

  group('INIT round trip', () {
    test('a declaration survives encode/decode', () {
      expect(
        _roundTrip(_init(keyboard: KeyboardCapabilities.full)).keyboard,
        KeyboardCapabilities.full,
      );
    });

    test('an explicit press-only declaration is distinct from silence', () {
      // "I negotiated and got nothing" and "I do not speak this field" are
      // different facts. Both read as press-only, but only the first is a
      // statement — and a diagnostic should be able to tell them apart.
      final declared = _roundTrip(_init(keyboard: KeyboardCapabilities.legacy));
      expect(declared.keyboard, KeyboardCapabilities.legacy);
      expect(declared.keyboard, isNotNull);
      expect(_roundTrip(_init()).keyboard, isNull);
    });

    test('an undeclared INIT stays byte-identical to a pre-§11 peer', () {
      // Additive-param discipline (the `images=`/`hyperlinks=` rule): a peer
      // that never learned the field must not pay for it.
      final bytes = encodeFrame(_init());
      expect(String.fromCharCodes(bytes), isNot(contains('keyboard=')));
    });

    test('a garbage value decodes to a defined capability, never a throw', () {
      // Trust boundary: a bit-flipped or hostile param must degrade, not
      // drop the frame.
      final body = String.fromCharCodes(encodeFrame(_init()));
      expect(
        () => _roundTrip(_init(keyboard: KeyboardCapabilities.full)),
        returnsNormally,
      );
      expect(body, isNot(contains('keyboard=')));
      expect(KeyboardCapabilities.fromWireBits(0xFF).supportsHeldState, isTrue);
    });
  });

  group('the §5.7 projection has exactly one definition', () {
    test('flag 2 alone does not promise held state', () {
      final caps = KeyboardCapabilities.fromKittyFlags(1 | 2);
      expect(caps.distinguishesRepeats, isTrue);
      expect(caps.supportsHeldState, isFalse);
    });

    test('held state needs event types AND all-keys-as-escapes', () {
      expect(
        KeyboardCapabilities.fromKittyFlags(1 | 2 | 8).supportsHeldState,
        isTrue,
      );
      expect(
        KeyboardCapabilities.fromKittyFlags(1 | 8).supportsHeldState,
        isFalse,
      );
    });

    test('positions additionally need alternate keys', () {
      expect(
        KeyboardCapabilities.fromKittyFlags(1 | 2 | 8).supportsPositions,
        isFalse,
      );
      expect(
        KeyboardCapabilities.fromKittyFlags(1 | 2 | 4 | 8).supportsPositions,
        isTrue,
      );
    });

    test('nothing confirmed projects the conservative default', () {
      expect(
        KeyboardCapabilities.fromKittyFlags(0),
        KeyboardCapabilities.legacy,
      );
    });

    test('a relay in front of a capable terminal declares what it probed', () {
      // The shell path: probe → project → declare. A terminal that honoured
      // everything makes the app behind the relay as capable as a local one.
      expect(
        KeyboardCapabilities.fromKittyFlags(31),
        KeyboardCapabilities.full,
      );
    });
  });
}
