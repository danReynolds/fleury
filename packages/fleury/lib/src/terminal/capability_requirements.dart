import 'package:meta/meta.dart';

import '../semantics/semantics.dart';

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

/// Whether the relevant terminal, surface, or transport supports a feature.
enum CapabilitySupport { unknown, supported, unsupported }

/// Whether Fleury actually enabled a supported feature for this session.
enum CapabilityEnablement { notApplicable, unknown, enabled, disabled }

/// Whether the requested behavior reached its destination.
///
/// Emitting a control sequence is [unverified], not [delivered]. Delivery can
/// only be claimed from an operation result or a behavioral receipt.
enum CapabilityDelivery { notApplicable, unverified, delivered, failed }

/// Origin of one fact in a [CapabilityTruth].
enum CapabilityEvidenceSource {
  surfaceProfile,
  environment,
  terminfo,
  appliedState,
  activeProbe,
  remoteDeclaration,
  operationResult,
  behavioralReceipt,
  policy,
  fallback,
  userOverride,
}

/// One inspectable provenance record for a capability fact.
@immutable
final class CapabilityEvidence {
  const CapabilityEvidence({required this.source, required this.detail});

  final CapabilityEvidenceSource source;
  final String detail;

  Map<String, Object?> toJson() => <String, Object?>{
    'source': source.name,
    'detail': detail,
  };
}

/// Runtime truth for one feature at one decision boundary.
///
/// This deliberately does not infer protocol state from a static terminal
/// summary. The component that observed support, applied a mode, received an
/// operation result, or enforced policy supplies the facts and their evidence.
@immutable
final class CapabilityTruth {
  const CapabilityTruth({
    required this.feature,
    required this.support,
    required this.enablement,
    required this.delivery,
    required this.evidence,
    this.policyBlocked = false,
    this.unsafe = false,
  });

  final TerminalFeature feature;
  final CapabilitySupport support;
  final CapabilityEnablement enablement;
  final CapabilityDelivery delivery;
  final bool policyBlocked;
  final bool unsafe;
  final List<CapabilityEvidence> evidence;

  bool get hasOperationalFailure =>
      support == CapabilitySupport.unsupported ||
      enablement == CapabilityEnablement.disabled ||
      delivery == CapabilityDelivery.failed;

  bool get isVerifiedAvailable =>
      support == CapabilitySupport.supported &&
      (enablement == CapabilityEnablement.enabled ||
          enablement == CapabilityEnablement.notApplicable) &&
      (delivery == CapabilityDelivery.delivered ||
          delivery == CapabilityDelivery.notApplicable);

  Map<String, Object?> toJson() => <String, Object?>{
    'feature': feature.name,
    'support': support.name,
    'enablement': enablement.name,
    'delivery': delivery.name,
    'policyBlocked': policyBlocked,
    'unsafe': unsafe,
    'evidence': <Object?>[for (final fact in evidence) fact.toJson()],
  };
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

/// Outcome of resolving a requirement against runtime truth and policy.
enum CapabilityResolutionState {
  available,
  unverified,
  degraded,
  disabledByPolicy,
  unsupported,
  unsafe,
}

/// Canonical capability result for diagnostics, semantics, and tests.
@immutable
final class CapabilityResolution {
  const CapabilityResolution._({
    required this.truth,
    required this.level,
    required this.state,
    this.fallbackLabel,
    this.warning,
  });

  final CapabilityTruth truth;
  TerminalFeature get feature => truth.feature;
  final CapabilityLevel level;
  final CapabilityResolutionState state;
  final String? fallbackLabel;
  final String? warning;

  CapabilitySupport get support => truth.support;
  CapabilityEnablement get enablement => truth.enablement;
  CapabilityDelivery get delivery => truth.delivery;
  bool get policyBlocked => truth.policyBlocked;
  bool get unsafe => truth.unsafe;
  List<CapabilityEvidence> get evidence => truth.evidence;

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
      'capabilitySupport': support.name,
      'capabilityEnablement': enablement.name,
      'capabilityDelivery': delivery.name,
      'capabilityPolicyBlocked': policyBlocked,
      'capabilityUnsafe': unsafe,
      'capabilityEvidence': <Object?>[
        for (final fact in evidence) fact.toJson(),
      ],
      if (fallbackLabel != null) 'activeFallback': fallbackLabel,
    });
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'feature': feature.name,
    'level': level.name,
    'state': state.name,
    'blocking': isBlocking,
    'truth': truth.toJson(),
    if (fallbackLabel != null) 'fallbackLabel': fallbackLabel,
    if (warning != null) 'warning': warning,
  };
}

/// Resolves one request against facts observed by the owning runtime domain.
CapabilityResolution resolveCapabilityRequirement(
  CapabilityRequirement requirement,
  CapabilityTruth truth,
) {
  if (requirement.feature != truth.feature) {
    throw ArgumentError.value(
      truth.feature,
      'truth.feature',
      'must match requirement.feature (${requirement.feature.name})',
    );
  }
  if (truth.evidence.isEmpty) {
    throw ArgumentError.value(
      truth.evidence,
      'truth.evidence',
      'must contain at least one provenance record',
    );
  }

  final feature = requirement.feature;
  final level = requirement.level;

  if (truth.unsafe) {
    return CapabilityResolution._(
      truth: truth,
      level: level,
      state: CapabilityResolutionState.unsafe,
      fallbackLabel: requirement.fallback?.label,
      warning: '${feature.name} is unsafe for this content source.',
    );
  }

  if (truth.policyBlocked || level == CapabilityLevel.prohibited) {
    return CapabilityResolution._(
      truth: truth,
      level: level,
      state: CapabilityResolutionState.disabledByPolicy,
      fallbackLabel: requirement.fallback?.label,
      warning: '${feature.name} is disabled by policy.',
    );
  }

  if (truth.hasOperationalFailure) {
    final fallback = requirement.fallback;
    if (level == CapabilityLevel.preferred && fallback != null) {
      return CapabilityResolution._(
        truth: truth,
        level: level,
        state: CapabilityResolutionState.degraded,
        fallbackLabel: fallback.label,
        warning: '${feature.name} failed; using ${fallback.label}.',
      );
    }
    return CapabilityResolution._(
      truth: truth,
      level: level,
      state: CapabilityResolutionState.unsupported,
      fallbackLabel: fallback?.label,
      warning: level == CapabilityLevel.required
          ? '${feature.name} is required but unavailable.'
          : null,
    );
  }

  if (truth.isVerifiedAvailable) {
    return CapabilityResolution._(
      truth: truth,
      level: level,
      state: CapabilityResolutionState.available,
    );
  }

  return CapabilityResolution._(
    truth: truth,
    level: level,
    state: CapabilityResolutionState.unverified,
    fallbackLabel: requirement.fallback?.label,
    warning: '${feature.name} has not been behaviorally verified.',
  );
}

/// Resolves several requirements in input order from an explicit truth map.
List<CapabilityResolution> resolveCapabilityRequirements(
  Iterable<CapabilityRequirement> requirements,
  Map<TerminalFeature, CapabilityTruth> truths,
) {
  return <CapabilityResolution>[
    for (final requirement in requirements)
      resolveCapabilityRequirement(
        requirement,
        truths[requirement.feature] ??
            (throw ArgumentError(
              'No capability truth supplied for ${requirement.feature.name}.',
            )),
      ),
  ];
}
