// RFC 0019 §6.2/§6.4 — measurements + environment → one derived policy.
//
// The rules pinned here: an axis adapts only on agreeing evidence
// (agreement-or-unknown); `unknown` keeps the spec default and is visible as
// WidthDecisionSource.spec; summing is established by the measured inequality
// per sequence; `split` additionally requires the width policy to predict
// every measured component; environment overrides beat probes, probes beat
// defaults. Fixtures for the two live-probed terminals (2026-07-27) and the
// research corpus's families.

import 'package:fleury/src/rendering/width_policy.dart';
import 'package:fleury/src/terminal/capabilities.dart';
import 'package:fleury/src/terminal/terminal_probe.dart';
import 'package:test/test.dart';

/// A full-battery measurement fixture from glyph id → width; unmentioned ids
/// default to [fallback].
WidthMeasurements _measure(Map<String, int> byId, {int fallback = 1}) =>
    WidthMeasurements.of({
      for (final glyph in widthProbeBattery)
        glyph.id: byId[glyph.id] ?? fallback,
    });

/// kitty/Ghostty-family: ambiguous narrow, emoji wide, VS16 honoured, ZWJ
/// clustered.
final _joining = _measure(const {
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
});

/// Warp / Apple Terminal family (measured live): wide emoji, VS16 honoured,
/// summed with paid joiners — family 2+2+2 + 2 joiners = 8.
final _warp = _measure(const {
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
});

/// Terminal A (measured live): everything emoji-ish narrow, summed, free
/// joiners — family 1+1+1 = 3.
final _terminalA = _measure(const {'familyZwj': 3, 'healthWorkerZwj': 2});

/// VS Code / VTE family: wide emoji, VS16 ignored (sequences measure 1),
/// summed with free joiners — family 2+2+2 = 6; profession = woman 2 +
/// medical sequence drawn 1 = 3.
final _vscode = _measure(const {
  'slightSmile': 2,
  'grinningFace': 2,
  'man': 2,
  'woman': 2,
  'boy': 2,
  'familyZwj': 6,
  'healthWorkerZwj': 3,
});

void main() {
  group('deriveTextPresentationPolicy — width axes', () {
    test('empty measurements keep the spec policy, every axis unevidenced', () {
      final resolved = deriveTextPresentationPolicy();
      expect(resolved.policy, TextPresentationPolicy.spec);
      for (final axis in WidthAxis.values) {
        expect(resolved.sourceOf(axis), WidthDecisionSource.spec);
        expect(resolved.isEvidenced(axis), isFalse);
      }
    });

    test('joining terminal: spec widths, evidenced by probe', () {
      final resolved = deriveTextPresentationPolicy(measurements: _joining);
      expect(resolved.policy.widths, CellWidthPolicy.spec);
      expect(
        resolved.sourceOf(WidthAxis.emojiPresentation),
        WidthDecisionSource.probe,
        reason:
            'same value as spec, but now measured — evidence matters to '
            'conservative gates even when the number does not change',
      );
    });

    test('terminal A: every emoji axis narrows on agreement', () {
      final resolved = deriveTextPresentationPolicy(measurements: _terminalA);
      final widths = resolved.policy.widths;
      expect(widths.ambiguous, CellWidth.one);
      expect(widths.emojiPresentation, CellWidth.one);
      expect(widths.emojiVariationSequence, CellWidth.one);
      expect(
        resolved.sourceOf(WidthAxis.emojiPresentation),
        WidthDecisionSource.probe,
      );
    });

    test('VS Code family: bare emoji wide, variation sequence narrow', () {
      // The common combination — the axes must stay independent.
      final resolved = deriveTextPresentationPolicy(measurements: _vscode);
      final widths = resolved.policy.widths;
      expect(widths.emojiPresentation, CellWidth.two);
      expect(widths.emojiVariationSequence, CellWidth.one);
    });

    test('disagreement within a class leaves that axis at spec/unknown', () {
      // The §6.1 fixture: box drawing narrow, α and ° wide — a terminal that
      // special-cases box drawing. No adaptation, visible as unevidenced.
      final resolved = deriveTextPresentationPolicy(
        measurements: _measure(const {'greekAlpha': 2, 'degreeSign': 2}),
      );
      expect(resolved.policy.widths.ambiguous, CellWidth.one);
      expect(resolved.isEvidenced(WidthAxis.ambiguous), isFalse);
    });

    test('a wide ambiguous agreement flips layout to two cells', () {
      final resolved = deriveTextPresentationPolicy(
        measurements: _measure(const {
          'boxDrawing': 2,
          'greekAlpha': 2,
          'degreeSign': 2,
        }),
      );
      expect(resolved.policy.widths.ambiguous, CellWidth.two);
      expect(resolved.sourceOf(WidthAxis.ambiguous), WidthDecisionSource.probe);
    });
  });

  group('the renderer pin gate reads the resolved axis (decision 9)', () {
    // `pinsAmbiguousWidth` IS what runApp passes as
    // `AnsiRenderer.ambiguousCharsAreWide`. It used to be derived from the
    // legacy `capabilities.ambiguousCharWidth` boolean instead, which meant
    // the renderer's answer and layout's answer came from two rules that
    // merely happened to agree in all four states. These pin the one rule.

    test('an evidenced narrow ambiguous axis disengages the pin', () {
      expect(
        deriveTextPresentationPolicy(
          measurements: _joining,
        ).pinsAmbiguousWidth,
        isFalse,
        reason: 'probe agreement on 1 cell is evidence',
      );
      expect(
        deriveTextPresentationPolicy(
          environment: const {'FLEURY_AMBIGUOUS_WIDTH': 'narrow'},
        ).pinsAmbiguousWidth,
        isFalse,
        reason: 'an explicit override is evidence',
      );
    });

    test('a wide ambiguous axis keeps the pin engaged', () {
      expect(
        deriveTextPresentationPolicy(
          measurements: _measure(const {
            'boxDrawing': 2,
            'greekAlpha': 2,
            'degreeSign': 2,
          }),
        ).pinsAmbiguousWidth,
        isTrue,
      );
      expect(
        deriveTextPresentationPolicy(
          environment: const {'FLEURY_AMBIGUOUS_WIDTH': 'wide'},
        ).pinsAmbiguousWidth,
        isTrue,
      );
    });

    test('unknown keeps the pin engaged — a default is not evidence', () {
      // The state the old boolean got right only by accident: it defaulted to
      // `wide`, while the policy's ambiguous axis defaults to `one`. Reading
      // the width alone would have DISENGAGED the pin on every unprobed
      // terminal, which is the "Warp garble" this net exists for.
      expect(
        deriveTextPresentationPolicy().pinsAmbiguousWidth,
        isTrue,
        reason: 'nothing was measured or declared',
      );
      final disagreeing = deriveTextPresentationPolicy(
        measurements: _measure(const {'greekAlpha': 2, 'degreeSign': 2}),
      );
      expect(disagreeing.policy.widths.ambiguous, CellWidth.one);
      expect(
        disagreeing.pinsAmbiguousWidth,
        isTrue,
        reason: 'disagreement resolves narrow for LAYOUT but is not evidence',
      );
    });

    test('the reported capability is read out of the same policy', () {
      // `evidencedAmbiguousCharWidth` and `pinsAmbiguousWidth` are two views
      // of one derivation, so `fleury diagnose` cannot print a width the
      // renderer contradicts.
      for (final resolved in <ResolvedTextPresentationPolicy>[
        deriveTextPresentationPolicy(),
        deriveTextPresentationPolicy(measurements: _joining),
        deriveTextPresentationPolicy(
          measurements: _measure(const {
            'boxDrawing': 2,
            'greekAlpha': 2,
            'degreeSign': 2,
          }),
        ),
        deriveTextPresentationPolicy(
          environment: const {'FLEURY_AMBIGUOUS_WIDTH': 'narrow'},
        ),
        deriveTextPresentationPolicy(
          environment: const {'FLEURY_AMBIGUOUS_WIDTH': 'wide'},
        ),
      ]) {
        final reported = evidencedAmbiguousCharWidth(resolved);
        expect(
          resolved.pinsAmbiguousWidth,
          reported != AmbiguousCharWidth.narrow,
          reason: 'pin engaged exactly when the report is not a proven narrow',
        );
      }
    });
  });

  group('deriveTextPresentationPolicy — lowering', () {
    test('joining terminal: preserve, evidenced', () {
      final resolved = deriveTextPresentationPolicy(measurements: _joining);
      expect(resolved.policy.lowering, ClusterLowering.preserve);
      expect(
        resolved.sourceOf(WidthAxis.lowering),
        WidthDecisionSource.probe,
        reason: '"this terminal clusters" is evidence, not a default',
      );
    });

    test('Warp: summed with paid joiners, components predicted → split', () {
      final resolved = deriveTextPresentationPolicy(measurements: _warp);
      expect(resolved.policy.lowering, ClusterLowering.split);
      expect(resolved.sourceOf(WidthAxis.lowering), WidthDecisionSource.probe);
    });

    test('terminal A: summed narrow components → split', () {
      final resolved = deriveTextPresentationPolicy(measurements: _terminalA);
      expect(resolved.policy.lowering, ClusterLowering.split);
    });

    test(
      'VS Code family: summed, mixed component widths predicted → split',
      () {
        // woman measures 2 (predicted by emojiPresentation: two); the medical
        // sequence measures 1 (predicted by emojiVariationSequence: one). The
        // per-class prediction is what authorizes the split.
        final resolved = deriveTextPresentationPolicy(measurements: _vscode);
        expect(resolved.policy.lowering, ClusterLowering.split);
      },
    );

    test(
      'mixed joining across sequences is unknown → preserve, unevidenced',
      () {
        // Joins the profession but sums the family — neither purely joined nor
        // purely summed. RFC 0019 §6.1: unknown, no adaptation.
        final resolved = deriveTextPresentationPolicy(
          measurements: _measure(const {
            'slightSmile': 2,
            'grinningFace': 2,
            'man': 2,
            'woman': 2,
            'boy': 2,
            'heartVs16': 2,
            'warningVs16': 2,
            'medicalVs16': 2,
            'familyZwj': 6,
            'healthWorkerZwj': 2,
          }),
        );
        expect(resolved.policy.lowering, ClusterLowering.preserve);
        expect(resolved.isEvidenced(WidthAxis.lowering), isFalse);
      },
    );

    test('summed but unpredicted components → preserve (split soundness)', () {
      // The reviewer counterexample: components 1,2,2 sum to 5 — genuinely
      // summed — but the emoji-presentation axis cannot predict a mixed set
      // (agreement fails → axis stays spec two). Splitting would model 6
      // against a drawn 5, so it is not authorized.
      final resolved = deriveTextPresentationPolicy(
        measurements: _measure(const {
          'slightSmile': 2,
          'grinningFace': 2,
          'man': 1,
          'woman': 2,
          'boy': 2,
          'heartVs16': 2,
          'warningVs16': 2,
          'medicalVs16': 2,
          'familyZwj': 5,
          'healthWorkerZwj': 5,
        }),
      );
      expect(resolved.policy.lowering, ClusterLowering.preserve);
      expect(resolved.isEvidenced(WidthAxis.lowering), isFalse);
    });

    test('empty measurements: preserve, unevidenced', () {
      final resolved = deriveTextPresentationPolicy();
      expect(resolved.policy.lowering, ClusterLowering.preserve);
      expect(resolved.isEvidenced(WidthAxis.lowering), isFalse);
    });
  });

  group('deriveTextPresentationPolicy — environment overrides', () {
    test('each axis has an independent override that beats the probe', () {
      final resolved = deriveTextPresentationPolicy(
        measurements: _joining, // probe says spec widths + preserve
        environment: const {
          'FLEURY_AMBIGUOUS_WIDTH': 'wide',
          'FLEURY_EMOJI_WIDTH': 'narrow',
          'FLEURY_VS16_WIDTH': 'narrow',
          'FLEURY_CLUSTER_MODE': 'split',
        },
      );
      final widths = resolved.policy.widths;
      expect(widths.ambiguous, CellWidth.two);
      expect(widths.emojiPresentation, CellWidth.one);
      expect(widths.emojiVariationSequence, CellWidth.one);
      expect(resolved.policy.lowering, ClusterLowering.split);
      for (final axis in WidthAxis.values) {
        expect(resolved.sourceOf(axis), WidthDecisionSource.environment);
      }
    });

    test('FLEURY_CLUSTER_MODE=split may force lowering past confidence', () {
      final resolved = deriveTextPresentationPolicy(
        environment: const {'FLEURY_CLUSTER_MODE': 'split'},
      );
      expect(resolved.policy.lowering, ClusterLowering.split);
      expect(
        resolved.sourceOf(WidthAxis.lowering),
        WidthDecisionSource.environment,
      );
    });

    test('unrecognized values are ignored, not errors', () {
      final resolved = deriveTextPresentationPolicy(
        environment: const {
          'FLEURY_EMOJI_WIDTH': 'bogus',
          'FLEURY_CLUSTER_MODE': '2',
        },
      );
      expect(resolved.policy, TextPresentationPolicy.spec);
    });
  });

  group('policy value semantics', () {
    test('equality is operational; provenance never participates', () {
      final probed = deriveTextPresentationPolicy(measurements: _joining);
      final defaulted = deriveTextPresentationPolicy();
      // Same geometry (spec widths, preserve): the POLICIES compare equal even
      // though one is evidenced and one is not — caches and layout
      // invalidation must never see provenance.
      expect(probed.policy, defaulted.policy);
      expect(
        probed.isEvidenced(WidthAxis.emojiPresentation),
        isNot(defaulted.isEvidenced(WidthAxis.emojiPresentation)),
      );
    });

    test('toJson carries values and provenance for diagnose', () {
      final json = deriveTextPresentationPolicy(
        measurements: _terminalA,
      ).toJson();
      final policy = json['policy']! as Map<String, Object?>;
      final decisions = json['decisions']! as Map<String, Object?>;
      expect(policy['emojiPresentation'], 'one');
      expect(policy['lowering'], 'split');
      expect(decisions['emojiPresentation'], 'probe');
    });
  });
}
