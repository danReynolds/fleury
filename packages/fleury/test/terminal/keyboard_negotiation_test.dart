// RFC 0020 §8: the Kitty keyboard tier, its transactional negotiation, and
// the restoration hygiene that keeps a pushed mode from leaking.

import 'package:fleury/fleury.dart';
import 'package:fleury/src/terminal/terminal_probe.dart';
import 'package:fleury/src/terminal/terminal_sequences.dart';
import 'package:test/test.dart';

TerminalMode _mode(KeyboardProtocolMode protocol) =>
    TerminalMode(keyboardProtocol: protocol);

void main() {
  group('protocol tiers', () {
    test('the default tier requests disambiguation AND event types', () {
      // Flag 2 is what makes a binding fire once per physical press instead
      // of once per auto-repeat, for every key the terminal already
      // escape-codes (chords, arrows, function keys). It costs nothing on
      // the text path: printable presses and repeats still arrive as
      // ordinary bytes.
      expect(KeyboardProtocolMode.disambiguated.requestedFlags, 1 | 2);
      expect(
        const TerminalMode().keyboardProtocol,
        KeyboardProtocolMode.disambiguated,
      );
    });

    test('lifecycle requests all five progressive flags', () {
      expect(KeyboardProtocolMode.lifecycle.requestedFlags, 31);
    });

    test('legacy pushes nothing at all', () {
      expect(KeyboardProtocolMode.legacy.requestedFlags, 0);
      final enter = buildTerminalEnterSequences(
        _mode(KeyboardProtocolMode.legacy),
      );
      expect(enter, isNot(contains('u')));
      expect(
        buildTerminalExitSequences(_mode(KeyboardProtocolMode.legacy)),
        isNot(contains('\x1B[<')),
      );
    });
  });

  group('escape-sequence ordering (§8.1)', () {
    test('the push lands AFTER entering the alternate screen', () {
      // The protocol mandates a separate flag stack per screen buffer, so
      // pushing before `?1049h` pushes onto the MAIN screen's stack and the
      // session runs unenhanced — the failure Bubble Tea filed as #1383.
      final enter = buildTerminalEnterSequences(
        _mode(KeyboardProtocolMode.disambiguated),
      );
      final altScreen = enter.indexOf('\x1B[?1049h');
      final push = enter.indexOf('\x1B[>3u');
      expect(altScreen, isNonNegative);
      expect(push, isNonNegative);
      expect(push, greaterThan(altScreen));
    });

    test('the pop lands BEFORE leaving the alternate screen', () {
      final exit = buildTerminalExitSequences(
        _mode(KeyboardProtocolMode.disambiguated),
      );
      final pop = exit.indexOf('\x1B[<1u');
      final leave = exit.indexOf('\x1B[?1049l');
      expect(pop, isNonNegative);
      expect(leave, isNonNegative);
      expect(pop, lessThan(leave));
    });

    test('the pop carries an explicit count', () {
      // A bare `CSI < u` is `CSI u` to a parser that drops the private
      // marker, and Windows consoles define that as ANSISYSRC (restore
      // cursor) — a stray cursor jump on exit.
      final exit = buildTerminalExitSequences(
        _mode(KeyboardProtocolMode.disambiguated),
      );
      expect(exit, contains('\x1B[<1u'));
      expect(exit, isNot(contains('\x1B[<u')));
    });

    test('a session with no alt screen still brackets its flags', () {
      const inline = TerminalMode(alternateScreen: false);
      expect(buildTerminalEnterSequences(inline), contains('\x1B[>3u'));
      expect(buildTerminalExitSequences(inline), contains('\x1B[<1u'));
    });
  });

  group('focus reporting (§8.6)', () {
    test('DECSET 1004 is enabled on entry and disabled on exit', () {
      const mode = TerminalMode();
      expect(buildTerminalEnterSequences(mode), contains('\x1B[?1004h'));
      expect(buildTerminalExitSequences(mode), contains('\x1B[?1004l'));
    });

    test('it can be turned off', () {
      const mode = TerminalMode(focusReporting: false);
      expect(buildTerminalEnterSequences(mode), isNot(contains('1004')));
    });
  });

  group('lifecycle commit safety (§8.3)', () {
    // Flag 8 stops the terminal sending text; flag 16 is what re-supplies
    // it. Honouring one without the other leaves the session unable to type
    // at all — which conservative capability reporting cannot fix, because
    // the terminal is ALREADY in that mode. Only rolling back can.
    bool safe(int flags) =>
        flags & 0x02 != 0 && flags & 0x08 != 0 && flags & 0x10 != 0;

    test('the full request commits', () {
      expect(safe(31), isTrue);
    });

    test('flag 8 without 16 is unsafe — text would disappear', () {
      expect(safe(1 | 2 | 8), isFalse);
    });

    test('flag 4 is optional: positions are an enhancement, not safety', () {
      expect(safe(1 | 2 | 8 | 16), isTrue);
    });

    test('a terminal that honoured only disambiguation is unsafe for '
        'lifecycle', () {
      expect(safe(1), isFalse);
    });
  });

  group('the support probe measures SUPPORT, not current state (§8.2)', () {
    // A terminal at a shell prompt has pushed nothing, so a bare `CSI ? u`
    // answers 0 on EVERY emulator. Reading that as support says Kitty does
    // not implement the protocol it invented — and a support matrix built
    // from it would be uniformly, confidently wrong.
    test('the diagnostic pushes every flag before reading back', () {
      expect(kittyKeyboardSupportQuery, contains('\x1B[>31u'));
      final push = kittyKeyboardSupportQuery.indexOf('\x1B[>31u');
      final query = kittyKeyboardSupportQuery.indexOf('\x1B[?u');
      expect(push, isNonNegative);
      expect(query, greaterThan(push));
    });

    test('it pops, so the terminal is left exactly as found', () {
      final query = kittyKeyboardSupportQuery.indexOf('\x1B[?u');
      final pop = kittyKeyboardSupportQuery.indexOf('\x1B[<1u');
      expect(pop, greaterThan(query));
      // An explicit count: a bare `CSI < u` reads as ANSISYSRC on Windows
      // consoles that drop the private marker.
      expect(kittyKeyboardSupportQuery, isNot(contains('\x1B[<u')));
    });

    test('the restore completes before the bracketing DA1', () {
      // The probe resolves on DA1. A pop after it would leave the terminal in
      // all-keys mode for however long the caller takes to react.
      final pop = kittyKeyboardSupportQuery.indexOf('\x1B[<1u');
      final da1 = kittyKeyboardSupportQuery.indexOf('\x1B[c');
      expect(da1, greaterThan(pop));
    });

    test('runtime negotiation does NOT re-push — enter already did', () {
      // Pushing again there would stack a second entry that the single pop
      // in the exit sequences could never fully unwind.
      expect(kittyKeyboardRuntimeQuery, isNot(contains('>')));
      expect(kittyKeyboardRuntimeQuery, startsWith('\x1B[?u'));
    });
  });
}
