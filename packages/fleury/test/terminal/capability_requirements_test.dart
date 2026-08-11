import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

const _probeEvidence = <CapabilityEvidence>[
  CapabilityEvidence(
    source: CapabilityEvidenceSource.activeProbe,
    detail: 'The protocol query received a positive reply.',
  ),
];

const _operationEvidence = <CapabilityEvidence>[
  CapabilityEvidence(
    source: CapabilityEvidenceSource.operationResult,
    detail: 'The destination acknowledged the operation.',
  ),
];

void main() {
  group('resolveCapabilityRequirement', () {
    test('blocks a required feature with unsupported evidence', () {
      final resolution = resolveCapabilityRequirement(
        const CapabilityRequirement(
          feature: TerminalFeature.imageKitty,
          level: CapabilityLevel.required,
          reason: 'Native image preview',
          fallback: CapabilityFallback(label: 'cell art'),
        ),
        const CapabilityTruth(
          feature: TerminalFeature.imageKitty,
          support: CapabilitySupport.unsupported,
          enablement: CapabilityEnablement.notApplicable,
          delivery: CapabilityDelivery.notApplicable,
          evidence: _probeEvidence,
        ),
      );

      expect(resolution.state, CapabilityResolutionState.unsupported);
      expect(resolution.fallbackLabel, 'cell art');
      expect(resolution.isBlocking, isTrue);
      expect(resolution.isSatisfied, isFalse);
      expect(resolution.warning, contains('required but unavailable'));
    });

    test('degrades a failed preferred feature to its fallback', () {
      final resolution = resolveCapabilityRequirement(
        const CapabilityRequirement(
          feature: TerminalFeature.clipboardWrite,
          level: CapabilityLevel.preferred,
          fallback: CapabilityFallback(label: 'in-process register'),
        ),
        const CapabilityTruth(
          feature: TerminalFeature.clipboardWrite,
          support: CapabilitySupport.supported,
          enablement: CapabilityEnablement.notApplicable,
          delivery: CapabilityDelivery.failed,
          evidence: _operationEvidence,
        ),
      );

      expect(resolution.state, CapabilityResolutionState.degraded);
      expect(resolution.fallbackLabel, 'in-process register');
      expect(resolution.isBlocking, isFalse);
    });

    test('distinguishes emitted bytes from verified delivery', () {
      final resolution = resolveCapabilityRequirement(
        const CapabilityRequirement(
          feature: TerminalFeature.osc52Clipboard,
          level: CapabilityLevel.preferred,
          fallback: CapabilityFallback(label: 'in-process register'),
        ),
        const CapabilityTruth(
          feature: TerminalFeature.osc52Clipboard,
          support: CapabilitySupport.unknown,
          enablement: CapabilityEnablement.enabled,
          delivery: CapabilityDelivery.unverified,
          evidence: <CapabilityEvidence>[
            CapabilityEvidence(
              source: CapabilityEvidenceSource.operationResult,
              detail: 'OSC 52 bytes were emitted without an acknowledgement.',
            ),
          ],
        ),
      );

      expect(resolution.state, CapabilityResolutionState.unverified);
      expect(resolution.delivery, CapabilityDelivery.unverified);
      expect(resolution.fallbackLabel, 'in-process register');
    });

    test('marks acknowledged operations available', () {
      final resolution = resolveCapabilityRequirement(
        const CapabilityRequirement(
          feature: TerminalFeature.clipboardWrite,
          level: CapabilityLevel.preferred,
        ),
        const CapabilityTruth(
          feature: TerminalFeature.clipboardWrite,
          support: CapabilitySupport.supported,
          enablement: CapabilityEnablement.notApplicable,
          delivery: CapabilityDelivery.delivered,
          evidence: _operationEvidence,
        ),
      );

      expect(resolution.state, CapabilityResolutionState.available);
      expect(resolution.evidence, _operationEvidence);
    });

    test('preserves policy truth independently of support', () {
      final resolution = resolveCapabilityRequirement(
        const CapabilityRequirement(
          feature: TerminalFeature.osc52Clipboard,
          level: CapabilityLevel.required,
          fallback: CapabilityFallback(label: 'in-process register'),
        ),
        const CapabilityTruth(
          feature: TerminalFeature.osc52Clipboard,
          support: CapabilitySupport.unknown,
          enablement: CapabilityEnablement.disabled,
          delivery: CapabilityDelivery.notApplicable,
          policyBlocked: true,
          evidence: <CapabilityEvidence>[
            CapabilityEvidence(
              source: CapabilityEvidenceSource.policy,
              detail: 'This content cannot leave the process.',
            ),
          ],
        ),
      );

      expect(resolution.state, CapabilityResolutionState.disabledByPolicy);
      expect(resolution.policyBlocked, isTrue);
      expect(resolution.isBlocking, isTrue);
    });

    test('keeps the fallback visible when the primary path is unsafe', () {
      final resolution = resolveCapabilityRequirement(
        const CapabilityRequirement(
          feature: TerminalFeature.clipboardWrite,
          level: CapabilityLevel.preferred,
          fallback: CapabilityFallback(label: 'in-process register'),
        ),
        const CapabilityTruth(
          feature: TerminalFeature.clipboardWrite,
          support: CapabilitySupport.unknown,
          enablement: CapabilityEnablement.disabled,
          delivery: CapabilityDelivery.notApplicable,
          unsafe: true,
          evidence: <CapabilityEvidence>[
            CapabilityEvidence(
              source: CapabilityEvidenceSource.policy,
              detail: 'The browser context is not secure.',
            ),
          ],
        ),
      );

      expect(resolution.state, CapabilityResolutionState.unsafe);
      expect(resolution.fallbackLabel, 'in-process register');
    });

    test('exports truth and provenance for inspectors and tests', () {
      final resolution = resolveCapabilityRequirement(
        const CapabilityRequirement(
          feature: TerminalFeature.imageKitty,
          level: CapabilityLevel.preferred,
        ),
        const CapabilityTruth(
          feature: TerminalFeature.imageKitty,
          support: CapabilitySupport.supported,
          enablement: CapabilityEnablement.notApplicable,
          delivery: CapabilityDelivery.notApplicable,
          evidence: _probeEvidence,
        ),
      );
      final state = resolution.toSemanticState();
      final json = resolution.toJson();

      expect(state.terminalCapability, 'imageKitty');
      expect(state.capabilityResolution, 'available');
      expect(state.values['capabilitySupport'], 'supported');
      expect(state.values['capabilityDelivery'], 'notApplicable');
      expect((json['truth'] as Map<String, Object?>)['evidence'], isNotEmpty);
    });

    test('resolves requirement lists from explicit truth in order', () {
      final resolutions = resolveCapabilityRequirements(
        const <CapabilityRequirement>[
          CapabilityRequirement(
            feature: TerminalFeature.colorAnsi16,
            level: CapabilityLevel.required,
          ),
          CapabilityRequirement(
            feature: TerminalFeature.imageKitty,
            level: CapabilityLevel.optional,
          ),
        ],
        const <TerminalFeature, CapabilityTruth>{
          TerminalFeature.colorAnsi16: CapabilityTruth(
            feature: TerminalFeature.colorAnsi16,
            support: CapabilitySupport.supported,
            enablement: CapabilityEnablement.notApplicable,
            delivery: CapabilityDelivery.notApplicable,
            evidence: _probeEvidence,
          ),
          TerminalFeature.imageKitty: CapabilityTruth(
            feature: TerminalFeature.imageKitty,
            support: CapabilitySupport.unsupported,
            enablement: CapabilityEnablement.notApplicable,
            delivery: CapabilityDelivery.notApplicable,
            evidence: _probeEvidence,
          ),
        },
      );

      expect(resolutions, hasLength(2));
      expect(resolutions[0].state, CapabilityResolutionState.available);
      expect(resolutions[1].state, CapabilityResolutionState.unsupported);
      expect(resolutions[1].isSatisfied, isTrue);
    });

    test('rejects truth for a different feature', () {
      expect(
        () => resolveCapabilityRequirement(
          const CapabilityRequirement(
            feature: TerminalFeature.imageKitty,
            level: CapabilityLevel.optional,
          ),
          const CapabilityTruth(
            feature: TerminalFeature.osc52Clipboard,
            support: CapabilitySupport.unknown,
            enablement: CapabilityEnablement.unknown,
            delivery: CapabilityDelivery.unverified,
            evidence: _probeEvidence,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('rejects truth without provenance', () {
      expect(
        () => resolveCapabilityRequirement(
          const CapabilityRequirement(
            feature: TerminalFeature.imageKitty,
            level: CapabilityLevel.optional,
          ),
          const CapabilityTruth(
            feature: TerminalFeature.imageKitty,
            support: CapabilitySupport.unknown,
            enablement: CapabilityEnablement.unknown,
            delivery: CapabilityDelivery.unverified,
            evidence: <CapabilityEvidence>[],
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
