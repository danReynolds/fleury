// The batched glyph-width probe: draw one representative glyph per known
// width-disagreement class, read back where the cursor actually landed.
//
// This exists because there is no protocol that answers "how wide will you
// draw this?" — DECRQM 2027 reports a capability that lies in both directions
// (kitty answers "no" and clusters correctly; WezTerm answers "permanently on"
// while ignoring VS16), and OSC 66 is implemented by two emulators. Measuring
// is what actually works, and it is what vim's `t_u7` has always done.

import 'package:fleury/src/terminal/terminal_probe.dart';
import 'package:test/test.dart';

class _FakeTransport implements TerminalProbeTransport {
  _FakeTransport(this.reply);
  final List<int> reply;
  String? sent;

  @override
  Future<List<int>> request(String bytes, {required Duration timeout}) async {
    sent = bytes;
    return reply;
  }
}

class _ThrowingTransport implements TerminalProbeTransport {
  @override
  Future<List<int>> request(String bytes, {required Duration timeout}) async {
    throw StateError('write failed');
  }
}

/// Builds a reply with one CPR per column, then the DA1 stop sentinel.
List<int> _reply(List<int> columns) =>
    '${columns.map((c) => '\x1B[1;${c}R').join()}\x1B[?62;4c'.codeUnits;

void main() {
  group('probeGlyphWidths', () {
    test('reads one width per class, in the order they were written', () async {
      // A modern, spec-following terminal: ambiguous narrow, VS16 honoured,
      // text-presentation dingbat narrow, ZWJ clustered.
      final measured = await probeGlyphWidths(
        _FakeTransport(_reply(<int>[2, 3, 2, 3])),
      );
      expect(measured.ambiguous, 1);
      expect(measured.emojiPresentation, 2);
      expect(measured.textPresentation, 1);
      expect(measured.graphemeCluster, 2);
      expect(measured.isComplete, isTrue);
    });

    test('captures a terminal that ignores VS16 and does not cluster', () async {
      // The other camp — roughly two thirds of the field. The ZWJ family is
      // summed per code point (6 cells) rather than clustered.
      final measured = await probeGlyphWidths(
        _FakeTransport(_reply(<int>[2, 2, 2, 7])),
      );
      expect(measured.emojiPresentation, 1, reason: 'VS16 ignored');
      expect(measured.graphemeCluster, 6, reason: 'summed, not clustered');
    });

    test('captures a CJK-configured terminal (ambiguous drawn wide)', () async {
      final measured = await probeGlyphWidths(
        _FakeTransport(_reply(<int>[3, 3, 2, 3])),
      );
      expect(measured.ambiguous, 2);
    });

    test('a partial reply fills only what arrived', () async {
      // The terminal answered the first two and stopped. The rest must stay
      // null so the caller keeps its default instead of inventing a width.
      final measured = await probeGlyphWidths(
        _FakeTransport(_reply(<int>[2, 3])),
      );
      expect(measured.ambiguous, 1);
      expect(measured.emojiPresentation, 2);
      expect(measured.textPresentation, isNull);
      expect(measured.graphemeCluster, isNull);
      expect(measured.isComplete, isFalse);
    });

    test('no CPR support yields all-null rather than zeros', () async {
      final measured = await probeGlyphWidths(
        _FakeTransport('\x1B[?62;4c'.codeUnits),
      );
      expect(measured.ambiguous, isNull);
      expect(measured.isComplete, isFalse);
    });

    test('an anomalous zero-advance report is discarded, not recorded', () async {
      // Column 1 means the cursor never moved. That is not a width of 0 — it
      // is a terminal we cannot measure, and must not be mistaken for data.
      final measured = await probeGlyphWidths(
        _FakeTransport(_reply(<int>[1, 3, 2, 3])),
      );
      expect(measured.ambiguous, isNull);
      expect(measured.emojiPresentation, 2);
    });

    test('a transport failure is swallowed', () async {
      final measured = await probeGlyphWidths(_ThrowingTransport());
      expect(measured.isComplete, isFalse);
      expect(measured.ambiguous, isNull);
    });

    test('stays on the current line and erases it afterwards', () async {
      final transport = _FakeTransport(_reply(<int>[2, 3, 2, 3]));
      await probeGlyphWidths(transport);
      final sent = transport.sent!;
      // Carriage return, never ESC[H: homing would overwrite whatever the user
      // already had on screen, which matters because `fleury diagnose --probe`
      // runs this on the NORMAL screen, not the alternate one.
      expect(sent, isNot(contains('\x1B[H')));
      // Each measurement returns to column 1 first, so a wide predecessor
      // cannot shift the next one, and the line is cleared at the end.
      expect('\r'.allMatches(sent).length, greaterThanOrEqualTo(5));
      expect(sent, contains('\x1B[K'));
      expect('\x1B[6n'.allMatches(sent).length, 4);
      expect(sent, contains('\u{2764}\u{FE0F}'), reason: 'VS16 probe glyph');
      expect(
        sent,
        contains('\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466}'),
        reason: 'ZWJ probe glyph',
      );
    });

    test('is a single round trip', () async {
      var requests = 0;
      final transport = _CountingTransport(
        _reply(<int>[2, 3, 2, 3]),
        () => requests++,
      );
      await probeGlyphWidths(transport);
      expect(requests, 1, reason: 'startup latency is the budget here');
    });
  });
}

class _CountingTransport implements TerminalProbeTransport {
  _CountingTransport(this.reply, this.onRequest);
  final List<int> reply;
  final void Function() onRequest;

  @override
  Future<List<int>> request(String bytes, {required Duration timeout}) async {
    onRequest();
    return reply;
  }
}
