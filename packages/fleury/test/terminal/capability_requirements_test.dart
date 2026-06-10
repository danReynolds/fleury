import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('terminalFeatureAvailable', () {
    test('resolves color fidelity by capability level', () {
      const none = TerminalCapabilities(colorMode: ColorMode.none);
      const indexed = TerminalCapabilities(colorMode: ColorMode.indexed256);
      const truecolor = TerminalCapabilities(colorMode: ColorMode.truecolor);

      expect(
        terminalFeatureAvailable(TerminalFeature.colorAnsi16, none),
        isFalse,
      );
      expect(
        terminalFeatureAvailable(TerminalFeature.colorAnsi16, indexed),
        isTrue,
      );
      expect(
        terminalFeatureAvailable(TerminalFeature.colorIndexed256, indexed),
        isTrue,
      );
      expect(
        terminalFeatureAvailable(TerminalFeature.colorIndexed256, truecolor),
        isTrue,
      );
      expect(
        terminalFeatureAvailable(TerminalFeature.colorTruecolor, indexed),
        isFalse,
      );
      expect(
        terminalFeatureAvailable(TerminalFeature.colorTruecolor, truecolor),
        isTrue,
      );
    });

    test('resolves image protocols and explicit session features', () {
      const halfBlock = TerminalCapabilities(
        imageProtocol: ImageProtocol.halfBlock,
      );
      const kitty = TerminalCapabilities(imageProtocol: ImageProtocol.kitty);

      expect(
        terminalFeatureAvailable(TerminalFeature.inlineImages, halfBlock),
        isFalse,
      );
      expect(
        terminalFeatureAvailable(TerminalFeature.imageGlyphFallback, halfBlock),
        isTrue,
      );
      expect(
        terminalFeatureAvailable(TerminalFeature.imageKitty, kitty),
        isTrue,
      );
      expect(
        terminalFeatureAvailable(
          TerminalFeature.sshSession,
          halfBlock,
          additionalAvailableFeatures: const <TerminalFeature>{
            TerminalFeature.sshSession,
          },
        ),
        isTrue,
      );
    });
  });

  group('resolveCapabilityRequirement', () {
    test('blocks required unsupported features', () {
      final resolution = resolveCapabilityRequirement(
        const CapabilityRequirement(
          feature: TerminalFeature.imageKitty,
          level: CapabilityLevel.required,
          reason: 'Native image preview',
          fallback: CapabilityFallback(label: 'cell art'),
        ),
        const TerminalCapabilities(imageProtocol: ImageProtocol.halfBlock),
      );

      expect(resolution.state, CapabilityResolutionState.unsupported);
      expect(resolution.fallbackLabel, 'cell art');
      expect(resolution.isBlocking, isTrue);
      expect(resolution.isSatisfied, isFalse);
      expect(resolution.warning, contains('required but unavailable'));
    });

    test('degrades preferred unsupported features with a fallback', () {
      final resolution = resolveCapabilityRequirement(
        const CapabilityRequirement(
          feature: TerminalFeature.imageKitty,
          level: CapabilityLevel.preferred,
          fallback: CapabilityFallback(
            label: 'half-block image',
            description: 'Render the image as ANSI cell art.',
          ),
        ),
        const TerminalCapabilities(imageProtocol: ImageProtocol.halfBlock),
      );

      expect(resolution.state, CapabilityResolutionState.degraded);
      expect(resolution.fallbackLabel, 'half-block image');
      expect(resolution.isBlocking, isFalse);
      expect(resolution.isSatisfied, isTrue);
    });

    test('disables prohibited available features by policy', () {
      final resolution = resolveCapabilityRequirement(
        const CapabilityRequirement(
          feature: TerminalFeature.osc8Hyperlinks,
          level: CapabilityLevel.prohibited,
          reason: 'Untrusted markdown',
        ),
        TerminalCapabilities.defaultCapabilities,
        additionalAvailableFeatures: const <TerminalFeature>{
          TerminalFeature.osc8Hyperlinks,
        },
      );

      expect(resolution.state, CapabilityResolutionState.disabledByPolicy);
      expect(resolution.isBlocking, isFalse);
      expect(resolution.warning, contains('disabled by policy'));
    });

    test('treats required policy-blocked features as blocking', () {
      final resolution = resolveCapabilityRequirement(
        const CapabilityRequirement(
          feature: TerminalFeature.osc52Clipboard,
          level: CapabilityLevel.required,
        ),
        TerminalCapabilities.defaultCapabilities,
        additionalAvailableFeatures: const <TerminalFeature>{
          TerminalFeature.osc52Clipboard,
        },
        policyBlockedFeatures: const <TerminalFeature>{
          TerminalFeature.osc52Clipboard,
        },
      );

      expect(resolution.state, CapabilityResolutionState.disabledByPolicy);
      expect(resolution.isBlocking, isTrue);
      expect(resolution.isSatisfied, isFalse);
    });

    test('exports semantic state for inspectors and tests', () {
      final resolution = resolveCapabilityRequirement(
        const CapabilityRequirement(
          feature: TerminalFeature.colorTruecolor,
          level: CapabilityLevel.preferred,
          fallback: CapabilityFallback(label: '256-color palette'),
        ),
        const TerminalCapabilities(colorMode: ColorMode.indexed256),
      );
      final state = resolution.toSemanticState();

      expect(state.terminalCapability, 'colorTruecolor');
      expect(state.capabilityRequirement, 'preferred');
      expect(state.capabilityResolution, 'degraded');
      expect(state.activeFallback, '256-color palette');
    });

    test('resolves requirement lists in order', () {
      final resolutions =
          resolveCapabilityRequirements(const <CapabilityRequirement>[
            CapabilityRequirement(
              feature: TerminalFeature.colorAnsi16,
              level: CapabilityLevel.required,
            ),
            CapabilityRequirement(
              feature: TerminalFeature.imageKitty,
              level: CapabilityLevel.optional,
            ),
          ], const TerminalCapabilities(colorMode: ColorMode.ansi16));

      expect(resolutions, hasLength(2));
      expect(resolutions[0].state, CapabilityResolutionState.available);
      expect(resolutions[1].state, CapabilityResolutionState.unsupported);
      expect(resolutions[1].isSatisfied, isTrue);
    });
  });
}
