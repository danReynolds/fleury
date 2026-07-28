// The batched glyph-width probe: several representatives per known
// width-disagreement class, written in one round trip, read back as where the
// cursor actually landed.
//
// This exists because there is no protocol that answers "how wide will you
// draw this?" — DECRQM 2027 reports a capability that lies in both directions
// (kitty answers "no" and clusters correctly; WezTerm answers "permanently on"
// while ignoring VS16), and OSC 66 is implemented by two emulators. Measuring
// is what actually works, and it is what vim's `t_u7` has always done.
//
// RFC 0019 §6.1 rules pinned here: the battery is ATOMIC (CPR replies are
// unlabeled, so a wrong count discards everything), raw measurements stay
// truthful (a zero advance is recorded, not repaired — derivation judges),
// and representatives exist for every class including the bare ZWJ
// components that evidence the summing equation.

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

/// Builds a reply with one CPR per column, then the DA1 stop sentinel.
List<int> _reply(List<int> columns) =>
    '${columns.map((c) => '\x1B[1;${c}R').join()}\x1B[?62;4c'.codeUnits;

/// Battery-order reply columns (width + 1) from glyph id → width. Ids not
/// mentioned default to width 1.
List<int> _columnsFor(Map<String, int> byId) => [
  for (final glyph in widthProbeBattery) (byId[glyph.id] ?? 1) + 1,
];

void main() {
  group('widthProbeBattery', () {
    test('ids are unique and every class has representatives', () {
      final ids = widthProbeBattery.map((g) => g.id).toSet();
      expect(ids.length, widthProbeBattery.length, reason: 'ids collide');
      for (final probeClass in WidthProbeClass.values) {
        expect(
          widthProbeBattery.where((g) => g.probeClass == probeClass),
          isNotEmpty,
          reason: 'no representative for $probeClass',
        );
      }
      // Agreement needs plurality wherever the axis adapts behaviour, and
      // summing must be established across different sequence families.
      expect(
        widthProbeBattery
            .where((g) => g.probeClass == WidthProbeClass.ambiguous)
            .length,
        greaterThanOrEqualTo(3),
      );
      expect(
        widthProbeBattery
            .where((g) => g.probeClass == WidthProbeClass.zwjSequence)
            .length,
        greaterThanOrEqualTo(2),
      );
    });

    test('the ZWJ components are probed bare, for the summing equation', () {
      // 👨‍👩‍👦 = man + woman + boy; 👩‍⚕️ = woman + the medical VS16 sequence.
      // Every component needs its own measurement so `summed` can be
      // evidenced by `componentSum <= advance <= componentSum + zwjCount`
      // rather than inferred.
      for (final id in ['man', 'woman', 'boy', 'medicalVs16']) {
        expect(
          widthProbeBattery.any((g) => g.id == id),
          isTrue,
          reason: 'missing component measurement: $id',
        );
      }
    });
  });

  group('probeGlyphWidths', () {
    test('reads one width per battery glyph, in write order', () async {
      // A modern, spec-following terminal: ambiguous narrow, emoji wide,
      // VS16 honoured, ZWJ clustered.
      final measured = await probeGlyphWidths(
        _FakeTransport(
          _reply(
            _columnsFor({
              'slightSmile': 2,
              'grinningFace': 2,
              'man': 2,
              'woman': 2,
              'boy': 2,
              'heartVs16': 2,
              'warningVs16': 2,
              'medicalVs16': 2,
              'familyZwj': 2,
              'healthWorkerZwj': 2,
            }),
          ),
        ),
      );
      expect(measured.isEmpty, isFalse);
      expect(measured.widthOf('boxDrawing'), 1);
      expect(measured.widthOf('slightSmile'), 2);
      expect(measured.widthOf('familyZwj'), 2);
      expect(measured.widthOf('checkMark'), 1);
      expect(measured.widthsIn(WidthProbeClass.ambiguous), <int?>[1, 1, 1]);
    });

    test(
      'terminal A fixture: narrow emoji, free joiners, no clustering',
      () async {
        // Measured live 2026-07-27: every emoji 1 cell, VS16 ignored, family
        // summed to 3. The profession sequence sums to 2 (1 + 1, joiners free).
        final measured = await probeGlyphWidths(
          _FakeTransport(
            _reply(_columnsFor({'familyZwj': 3, 'healthWorkerZwj': 2})),
          ),
        );
        expect(measured.widthOf('slightSmile'), 1);
        expect(measured.widthOf('heartVs16'), 1);
        expect(measured.widthsIn(WidthProbeClass.zwjSequence), <int?>[3, 2]);
      },
    );

    test('Warp fixture: wide emoji, paid joiners, no clustering', () async {
      // Measured live 2026-07-27: family = 8 — 2+2+2 plus one column per ZWJ.
      final measured = await probeGlyphWidths(
        _FakeTransport(
          _reply(
            _columnsFor({
              'slightSmile': 2,
              'grinningFace': 2,
              'man': 2,
              'woman': 2,
              'boy': 2,
              'heartVs16': 2,
              'warningVs16': 2,
              'medicalVs16': 2,
              'familyZwj': 8,
              'healthWorkerZwj': 5,
            }),
          ),
        ),
      );
      expect(measured.widthOf('familyZwj'), 8);
      expect(measured.widthOf('healthWorkerZwj'), 5);
    });

    test('the batch is atomic: a missing reply discards everything', () async {
      final columns = _columnsFor(const {})..removeLast();
      final measured = await probeGlyphWidths(_FakeTransport(_reply(columns)));
      expect(
        measured.isEmpty,
        isTrue,
        reason:
            'CPR replies are unlabeled — with one missing, later replies '
            'cannot be attributed safely, so nothing may be salvaged',
      );
      expect(measured.widthOf('boxDrawing'), isNull);
      expect(measured.widthsIn(WidthProbeClass.ambiguous), isEmpty);
    });

    test('extra replies also discard the batch', () async {
      final columns = _columnsFor(const {})..add(2);
      final measured = await probeGlyphWidths(_FakeTransport(_reply(columns)));
      expect(measured.isEmpty, isTrue);
    });

    test('a zero advance is recorded raw, not repaired', () async {
      // Column 1 after writing = zero advance. Anomalous — but the probe
      // records what it measured; the derivation's agreement rules are what
      // reject it (see the disagreement case in ambiguous_width_probe_test).
      final columns = _columnsFor(const {});
      columns[0] = 1; // boxDrawing: advance 0
      final measured = await probeGlyphWidths(_FakeTransport(_reply(columns)));
      expect(measured.widthOf('boxDrawing'), 0);
    });

    test('no CPR support yields empty measurements, not zeros', () async {
      final measured = await probeGlyphWidths(
        _FakeTransport('\x1B[?62;4c'.codeUnits),
      );
      expect(measured.isEmpty, isTrue);
    });

    test('a transport failure is swallowed', () async {
      final measured = await probeGlyphWidths(_ThrowingTransport());
      expect(measured.isEmpty, isTrue);
    });

    test(
      'stays on the current line, CR-anchored per glyph, and erases it',
      () async {
        final transport = _FakeTransport(_reply(_columnsFor(const {})));
        await probeGlyphWidths(transport);
        final sent = transport.sent!;
        // Carriage return, never ESC[H: homing would overwrite whatever the
        // user already had on screen, which matters because `fleury diagnose
        // --probe` runs this on the NORMAL screen, not the alternate one.
        expect(sent, isNot(contains('\x1B[H')));
        // Every glyph returns to column 1 first — widths never accumulate, so
        // a narrow viewport can't wrap mid-battery — and the line is cleared.
        for (final glyph in widthProbeBattery) {
          expect(sent, contains('\r${glyph.glyph}\x1B[6n'));
        }
        expect(sent, contains('\x1B[K'));
        expect('\x1B[6n'.allMatches(sent).length, widthProbeBattery.length);
      },
    );

    test('is a single round trip', () async {
      var requests = 0;
      final transport = _CountingTransport(
        _reply(_columnsFor(const {})),
        () => requests++,
      );
      await probeGlyphWidths(transport);
      expect(requests, 1, reason: 'startup latency is the budget here');
    });
  });

  group('WidthMeasurements.of', () {
    test('builds battery-parallel measurements from ids', () {
      final measured = WidthMeasurements.of(const {
        'boxDrawing': 1,
        'greekAlpha': 2,
      });
      expect(measured.widthOf('boxDrawing'), 1);
      expect(measured.widthOf('greekAlpha'), 2);
      expect(measured.widthOf('degreeSign'), isNull);
      expect(measured.widthsIn(WidthProbeClass.ambiguous), <int?>[1, 2, null]);
    });
  });
}
