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
}
