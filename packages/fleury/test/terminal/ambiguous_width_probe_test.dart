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

/// A full-battery reply: [ambiguous] columns for the three ambiguous-class
/// glyphs (in battery order), width 1 for everything else, then the DA1 stop
/// sentinel.
List<int> _batteryReply(List<int> ambiguous) {
  var ambiguousIndex = 0;
  final columns = <int>[
    for (final glyph in widthProbeBattery)
      glyph.probeClass == WidthProbeClass.ambiguous
          ? ambiguous[ambiguousIndex++]
          : 2,
  ];
  return '${columns.map((c) => '\x1B[1;${c}R').join()}\x1B[?62;4c'.codeUnits;
}

void main() {
  group('probeAmbiguousWidth', () {
    test(
      'reports narrow when every representative advanced one column',
      () async {
        final transport = _FakeTransport(_batteryReply(<int>[2, 2, 2]));
        expect(await probeAmbiguousWidth(transport), AmbiguousCharWidth.narrow);
        expect(
          transport.sent,
          allOf(
            contains('─'),
            contains('α'),
            contains('°'),
            contains('\x1B[6n'),
          ),
          reason:
              'ambiguous agreement spans three blocks — box drawing alone '
              'is the glyph most likely to be special-cased narrow',
        );
      },
    );

    test(
      'reports wide when every representative advanced two columns',
      () async {
        expect(
          await probeAmbiguousWidth(
            _FakeTransport(_batteryReply(<int>[3, 3, 3])),
          ),
          AmbiguousCharWidth.wide,
        );
      },
    );

    test(
      'disagreement across representatives yields null, not a guess',
      () async {
        // The RFC 0019 §6.1 fixture: ─ narrow while α and ° measure wide — a
        // terminal that special-cases box drawing. Agreement fails; the caller
        // keeps the conservative default (wide → the renderer pin stays on).
        expect(
          await probeAmbiguousWidth(
            _FakeTransport(_batteryReply(<int>[2, 3, 3])),
          ),
          isNull,
        );
      },
    );

    test('an anomalous zero advance fails agreement', () async {
      expect(
        await probeAmbiguousWidth(
          _FakeTransport(_batteryReply(<int>[1, 2, 2])),
        ),
        isNull,
        reason: 'a zero-advance measurement is recorded raw and rejected here',
      );
    });

    test('returns null when only a DA reply lands (no CPR)', () async {
      final reply = '\x1B[?62;4c'.codeUnits;
      expect(await probeAmbiguousWidth(_FakeTransport(reply)), isNull);
    });

    test('a truncated batch yields null (atomicity)', () async {
      // One CPR for a battery of many: unattributable, discarded whole.
      final reply = '\x1B[1;2R\x1B[?62;4c'.codeUnits;
      expect(await probeAmbiguousWidth(_FakeTransport(reply)), isNull);
    });

    test('finds valid CPRs even when an aborted CSI abuts them', () async {
      // A malformed CSI whose parameter run is terminated by the NEXT escape:
      // the parser must not step over that second ESC. Guards the
      // `_cursorReportColumns` `i = j - 1` resume fix.
      final reply = <int>[
        ...'\x1B[9'.codeUnits,
        ..._batteryReply(<int>[2, 2, 2]),
      ];
      expect(
        await probeAmbiguousWidth(_FakeTransport(reply)),
        AmbiguousCharWidth.narrow,
      );
    });

    test('returns null on no reply (timeout)', () async {
      expect(await probeAmbiguousWidth(_FakeTransport(const <int>[])), isNull);
    });

    test('swallows a transport failure and reports null', () async {
      expect(await probeAmbiguousWidth(_ThrowingTransport()), isNull);
    });
  });

  group('evidencedAmbiguousCharWidth', () {
    // The agreement rule has exactly one implementation
    // (deriveTextPresentationPolicy); this reads its verdict back out as the
    // legacy two-state capability. `ambiguousWidthFromMeasurements` used to
    // re-derive the same rule beside it, which is how the renderer's pin gate
    // and the reported width could have drifted apart.
    AmbiguousCharWidth? forWidths(Map<String, int> widths) =>
        evidencedAmbiguousCharWidth(
          deriveTextPresentationPolicy(
            measurements: WidthMeasurements.of(widths),
          ),
        );

    test('derives from measurements without a transport', () {
      expect(
        forWidths(const {'boxDrawing': 1, 'greekAlpha': 1, 'degreeSign': 1}),
        AmbiguousCharWidth.narrow,
      );
      expect(
        forWidths(const {'boxDrawing': 2, 'greekAlpha': 2, 'degreeSign': 2}),
        AmbiguousCharWidth.wide,
      );
      expect(
        evidencedAmbiguousCharWidth(deriveTextPresentationPolicy()),
        isNull,
        reason: 'the spec default is not evidence',
      );
      expect(
        forWidths(const {'boxDrawing': 1}),
        isNull,
        reason: 'missing representatives block agreement',
      );
      expect(
        forWidths(const {'boxDrawing': 1, 'greekAlpha': 2, 'degreeSign': 1}),
        isNull,
        reason: 'disagreement is unknown, never a guess',
      );
    });

    test('an environment override is evidence too', () {
      expect(
        evidencedAmbiguousCharWidth(
          deriveTextPresentationPolicy(
            environment: const {'FLEURY_AMBIGUOUS_WIDTH': 'narrow'},
          ),
        ),
        AmbiguousCharWidth.narrow,
      );
      expect(
        evidencedAmbiguousCharWidth(
          deriveTextPresentationPolicy(
            environment: const {'FLEURY_AMBIGUOUS_WIDTH': 'wide'},
          ),
        ),
        AmbiguousCharWidth.wide,
      );
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
        detectTerminalCapabilitiesFromEnvironment(const {
          'FLEURY_AMBIGUOUS_WIDTH': 'narrow',
        }).ambiguousCharWidth,
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
