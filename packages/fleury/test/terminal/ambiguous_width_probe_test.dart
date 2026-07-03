import 'package:fleury/src/terminal/capabilities.dart';
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

void main() {
  group('probeAmbiguousWidth', () {
    test('reports narrow when the cursor advanced one column', () async {
      // Glyph written at home (col 1); the cursor now rests at col 2 → the
      // terminal drew the ambiguous glyph one column wide. CPR then DA1.
      final reply = '\x1B[1;2R\x1B[?62;4c'.codeUnits;
      final transport = _FakeTransport(reply);
      expect(await probeAmbiguousWidth(transport), AmbiguousCharWidth.narrow);
      expect(
        transport.sent,
        allOf(contains('─'), contains('\x1B[6n')),
        reason: 'wrote an ambiguous glyph and a Cursor Position Report query',
      );
    });

    test('reports wide when the cursor advanced two columns', () async {
      // Cursor at col 3 → the glyph rendered two columns wide.
      final reply = '\x1B[1;3R\x1B[?62;4c'.codeUnits;
      expect(
        await probeAmbiguousWidth(_FakeTransport(reply)),
        AmbiguousCharWidth.wide,
      );
    });

    test('returns null when only a DA reply lands (no CPR)', () async {
      // No Cursor Position Report to measure → caller keeps its safe default.
      final reply = '\x1B[?62;4c'.codeUnits;
      expect(await probeAmbiguousWidth(_FakeTransport(reply)), isNull);
    });

    test('finds a valid CPR even when an aborted CSI abuts it', () async {
      // A malformed CSI whose parameter run is terminated by the NEXT escape
      // (`ESC[9` then a real `ESC[1;2R`): the parser must not step over that
      // second ESC. Guards the `_cursorReportColumn` `i = j - 1` resume fix —
      // with the old `i = j` this returned null (→ conservative wide default).
      final reply = '\x1B[9\x1B[1;2R\x1B[?62;4c'.codeUnits;
      expect(
        await probeAmbiguousWidth(_FakeTransport(reply)),
        AmbiguousCharWidth.narrow,
      );
    });

    test('returns null on no reply (timeout)', () async {
      expect(
        await probeAmbiguousWidth(_FakeTransport(const <int>[])),
        isNull,
      );
    });

    test('swallows a transport failure and reports null', () async {
      expect(await probeAmbiguousWidth(_ThrowingTransport()), isNull);
    });
  });

  group('detectAmbiguousCharWidthFromEnvironment', () {
    AmbiguousCharWidth? detect(String? value) =>
        detectAmbiguousCharWidthFromEnvironment(
          value == null ? const {} : {'FLEURY_AMBIGUOUS_WIDTH': value},
        );

    test('reads narrow|wide (case/space-insensitive), else null', () {
      expect(detect('narrow'), AmbiguousCharWidth.narrow);
      expect(detect('wide'), AmbiguousCharWidth.wide);
      expect(detect(' WIDE '), AmbiguousCharWidth.wide);
      expect(detect(null), isNull, reason: 'unset → probe/default decides');
      expect(detect('0'), isNull, reason: 'probe-disable is not a value');
      expect(detect('bogus'), isNull);
    });

    test('flows through detectTerminalCapabilitiesFromEnvironment', () {
      expect(
        detectTerminalCapabilitiesFromEnvironment(
          const {'FLEURY_AMBIGUOUS_WIDTH': 'narrow'},
        ).ambiguousCharWidth,
        AmbiguousCharWidth.narrow,
      );
      expect(
        detectTerminalCapabilitiesFromEnvironment(const {}).ambiguousCharWidth,
        AmbiguousCharWidth.wide,
        reason: 'safe default when unset',
      );
    });
  });
}
