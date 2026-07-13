import 'package:meta/meta.dart';

import '../semantics/semantics.dart';
import 'capabilities.dart';

/// Terminal feature names that widgets and services can request.
enum TerminalFeature {
  colorAnsi16,
  colorIndexed256,
  colorTruecolor,
  unicodeWidthProfile,
  alternateScreen,
  hideCursor,
  bracketedPaste,
  kittyKeyboard,
  mouse,
  mouseMotion,
  clipboardWrite,
  osc52Clipboard,
  hyperlinks,
  osc8Hyperlinks,
  inlineImages,
  imageKitty,
  imageIterm2,
  imageSixel,
  imageGlyphFallback,
  tmuxPassthrough,
  sshSession,
  rawAnsiParsing,
  synchronizedOutput,
}

/// Strength of a capability request.
enum CapabilityLevel { required, preferred, optional, prohibited }

/// Human-readable fallback metadata for a capability requirement.
@immutable
final class CapabilityFallback {
  const CapabilityFallback({required this.label, this.description});

  final String label;
  final String? description;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    if (description != null) 'description': description,
  };
}

/// A widget or service request for one terminal feature.
@immutable
final class CapabilityRequirement {
  const CapabilityRequirement({
    required this.feature,
    required this.level,
    this.reason,
    this.fallback,
  });

  final TerminalFeature feature;
  final CapabilityLevel level;
  final String? reason;
  final CapabilityFallback? fallback;

  Map<String, Object?> toJson() => <String, Object?>{
    'feature': feature.name,
    'level': level.name,
    if (reason != null) 'reason': reason,
    if (fallback != null) 'fallback': fallback!.toJson(),
  };
}

/// Outcome of resolving a requirement against terminal capabilities and policy.
enum CapabilityResolutionState {
  available,
  degraded,
  disabledByPolicy,
  unsupported,
  unsafe,
}

/// Resolved capability state for diagnostics, semantics, and tests.
@immutable
final class CapabilityResolution {
  const CapabilityResolution({
    required this.feature,
    required this.level,
    required this.state,
    this.fallbackLabel,
    this.warning,
  });

  final TerminalFeature feature;
  final CapabilityLevel level;
  final CapabilityResolutionState state;
  final String? fallbackLabel;
  final String? warning;

  /// Whether this resolution should block the requesting surface.
  bool get isBlocking =>
      level == CapabilityLevel.required &&
      state != CapabilityResolutionState.available;

  bool get isSatisfied => !isBlocking;

  SemanticState toSemanticState() {
    return SemanticState(<String, Object?>{
      'terminalCapability': feature.name,
      'capabilityRequirement': level.name,
      'capabilityResolution': state.name,
      if (fallbackLabel != null) 'activeFallback': fallbackLabel,
    });
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'feature': feature.name,
    'level': level.name,
    'state': state.name,
    'blocking': isBlocking,
    if (fallbackLabel != null) 'fallbackLabel': fallbackLabel,
    if (warning != null) 'warning': warning,
  };
}

/// Resolves one capability requirement against current terminal capabilities.
CapabilityResolution resolveCapabilityRequirement(
  CapabilityRequirement requirement,
  TerminalCapabilities capabilities, {
  Set<TerminalFeature> additionalAvailableFeatures = const <TerminalFeature>{},
  Set<TerminalFeature> policyBlockedFeatures = const <TerminalFeature>{},
  Set<TerminalFeature> unsafeFeatures = const <TerminalFeature>{},
}) {
  final feature = requirement.feature;
  final level = requirement.level;
  final available = terminalFeatureAvailable(
    feature,
    capabilities,
    additionalAvailableFeatures: additionalAvailableFeatures,
  );

  if (unsafeFeatures.contains(feature)) {
    return CapabilityResolution(
      feature: feature,
      level: level,
      state: CapabilityResolutionState.unsafe,
      warning: '${feature.name} is unsafe for this content source.',
    );
  }

  if (policyBlockedFeatures.contains(feature) ||
      level == CapabilityLevel.prohibited && available) {
    return CapabilityResolution(
      feature: feature,
      level: level,
      state: CapabilityResolutionState.disabledByPolicy,
      fallbackLabel: requirement.fallback?.label,
      warning: '${feature.name} is disabled by policy.',
    );
  }

  if (available) {
    return CapabilityResolution(
      feature: feature,
      level: level,
      state: CapabilityResolutionState.available,
    );
  }

  final fallback = requirement.fallback;
  if (level == CapabilityLevel.preferred && fallback != null) {
    return CapabilityResolution(
      feature: feature,
      level: level,
      state: CapabilityResolutionState.degraded,
      fallbackLabel: fallback.label,
      warning: '${feature.name} is unavailable; using ${fallback.label}.',
    );
  }

  return CapabilityResolution(
    feature: feature,
    level: level,
    state: CapabilityResolutionState.unsupported,
    fallbackLabel: fallback?.label,
    warning: level == CapabilityLevel.required
        ? '${feature.name} is required but unavailable.'
        : null,
  );
}

/// Resolves several requirements in input order.
List<CapabilityResolution> resolveCapabilityRequirements(
  Iterable<CapabilityRequirement> requirements,
  TerminalCapabilities capabilities, {
  Set<TerminalFeature> additionalAvailableFeatures = const <TerminalFeature>{},
  Set<TerminalFeature> policyBlockedFeatures = const <TerminalFeature>{},
  Set<TerminalFeature> unsafeFeatures = const <TerminalFeature>{},
}) {
  return <CapabilityResolution>[
    for (final requirement in requirements)
      resolveCapabilityRequirement(
        requirement,
        capabilities,
        additionalAvailableFeatures: additionalAvailableFeatures,
        policyBlockedFeatures: policyBlockedFeatures,
        unsafeFeatures: unsafeFeatures,
      ),
  ];
}

/// Returns whether [feature] is available in the current capability summary.
bool terminalFeatureAvailable(
  TerminalFeature feature,
  TerminalCapabilities capabilities, {
  Set<TerminalFeature> additionalAvailableFeatures = const <TerminalFeature>{},
}) {
  if (additionalAvailableFeatures.contains(feature)) return true;
  switch (feature) {
    case TerminalFeature.colorAnsi16:
      return capabilities.colorMode != ColorMode.none;
    case TerminalFeature.colorIndexed256:
      return capabilities.colorMode == ColorMode.indexed256 ||
          capabilities.colorMode == ColorMode.truecolor;
    case TerminalFeature.colorTruecolor:
      return capabilities.colorMode == ColorMode.truecolor;
    case TerminalFeature.unicodeWidthProfile:
      return true;
    case TerminalFeature.alternateScreen:
      return capabilities.supportsAlternateScreen;
    case TerminalFeature.hideCursor:
      return capabilities.supportsHidingCursor;
    case TerminalFeature.bracketedPaste:
      return true;
    case TerminalFeature.kittyKeyboard:
      return true;
    case TerminalFeature.mouse:
    case TerminalFeature.mouseMotion:
      return true;
    case TerminalFeature.clipboardWrite:
    case TerminalFeature.hyperlinks:
      return true;
    case TerminalFeature.osc8Hyperlinks:
      // Derived from real detection (env allow-list, tmux-suppressed) rather
      // than a hardcoded constant. A supporting terminal reports
      // capabilities.hyperlinks == true; a browser peer's projection sets it
      // from the DOM surface. See detectHyperlinksFromEnvironment / RFC 0017.
      return capabilities.hyperlinks;
    case TerminalFeature.osc52Clipboard:
      return false;
    case TerminalFeature.inlineImages:
      return capabilities.imageProtocol != ImageProtocol.halfBlock;
    case TerminalFeature.imageKitty:
      return capabilities.imageProtocol == ImageProtocol.kitty;
    case TerminalFeature.imageIterm2:
      return capabilities.imageProtocol == ImageProtocol.iterm2;
    case TerminalFeature.imageSixel:
      return capabilities.imageProtocol == ImageProtocol.sixel;
    case TerminalFeature.imageGlyphFallback:
      return true;
    case TerminalFeature.tmuxPassthrough:
      return capabilities.tmuxPassthrough;
    case TerminalFeature.sshSession:
    case TerminalFeature.rawAnsiParsing:
    case TerminalFeature.synchronizedOutput:
      return false;
  }
}
