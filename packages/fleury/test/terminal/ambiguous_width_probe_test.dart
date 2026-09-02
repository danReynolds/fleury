import 'package:fleury/src/rendering/width_policy.dart';
import 'package:fleury/src/terminal/capabilities.dart';
import 'package:fleury/src/terminal/terminal_probe.dart';
import 'package:test/test.dart';

void main() {
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

  group('the probe battery gate (audit 4.e)', () {
    test('an ambiguous-width override does not silence the other axes', () {
      // FLEURY_AMBIGUOUS_WIDTH pins ONE axis of the policy (RFC 0019 6.6).
      // The battery measures four classes in a single round trip; emoji
      // presentation, variation sequences and ZWJ clustering are knowable
      // only by measuring, and no environment variable answered them.
      expect(
        widthProbeIsPermittedByEnvironment(const {
          'FLEURY_AMBIGUOUS_WIDTH': 'narrow',
        }),
        isTrue,
      );
      expect(
        widthProbeIsPermittedByEnvironment(const {
          'FLEURY_AMBIGUOUS_WIDTH': 'wide',
        }),
        isTrue,
      );
    });

    test('the pinned axis still comes from the environment, not the probe', () {
      // The probe runs and measures ambiguous as WIDE; the override says
      // narrow and wins, while the emoji axis takes the measured value.
      final resolved = deriveTextPresentationPolicy(
        measurements: WidthMeasurements.of(const {
          'boxDrawing': 2,
          'greekAlpha': 2,
          'degreeSign': 2,
          'slightSmile': 1,
          'grinningFace': 1,
          'man': 1,
          'woman': 1,
          'boy': 1,
        }),
        environment: const {'FLEURY_AMBIGUOUS_WIDTH': 'narrow'},
      );
      expect(resolved.policy.widths.ambiguous, CellWidth.one);
      expect(
        resolved.sourceOf(WidthAxis.ambiguous),
        WidthDecisionSource.environment,
      );
      expect(resolved.policy.widths.emojiPresentation, CellWidth.one);
      expect(
        resolved.sourceOf(WidthAxis.emojiPresentation),
        WidthDecisionSource.probe,
      );
    });

    test('the kill switch is its own variable, not an axis value', () {
      for (final off in const ['0', 'off', 'false', 'no', 'OFF']) {
        expect(
          widthProbeIsPermittedByEnvironment({'FLEURY_WIDTH_PROBE': off}),
          isFalse,
          reason: 'FLEURY_WIDTH_PROBE=$off stops the whole round trip',
        );
      }
      expect(
        widthProbeIsPermittedByEnvironment(const {'FLEURY_WIDTH_PROBE': '1'}),
        isTrue,
      );
    });

    test('an ASCII glyph tier emits no ambiguous glyphs, so it skips', () {
      expect(
        widthProbeIsPermittedByEnvironment(const {
          'FLEURY_GLYPH_TIER': 'ascii',
        }),
        isFalse,
      );
    });

    test('an unconstrained environment probes', () {
      expect(widthProbeIsPermittedByEnvironment(const {}), isTrue);
    });
  });
}
