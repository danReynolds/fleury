import 'package:meta/meta.dart';

import '../foundation/geometry.dart';
import 'capabilities.dart';
import 'capability_requirements.dart';
import 'terminal_probe.dart';
import 'terminal_driver.dart';

/// Severity for machine-readable terminal diagnostic messages.
enum TerminalDiagnosticSeverity { info, warning, error }

/// A structured diagnostic message emitted by [TerminalDiagnosis].
@immutable
final class TerminalDiagnosticMessage {
  const TerminalDiagnosticMessage({
    required this.severity,
    required this.code,
    required this.message,
    this.details = const <String, Object?>{},
  });

  final TerminalDiagnosticSeverity severity;
  final String code;
  final String message;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'severity': severity.name,
      'code': code,
      'message': message,
    };
    if (details.isNotEmpty) json['details'] = details;
    return json;
  }
}

/// Terminal environment values and stream state relevant to Fleury rendering.
@immutable
final class TerminalProfileReport {
  const TerminalProfileReport({
    required this.size,
    required this.isInteractive,
    required this.stdinIsTerminal,
    required this.stdoutIsTerminal,
    this.term,
    this.termProgram,
    this.termProgramVersion,
    this.colorterm,
    this.lcTerminal,
    this.lcTerminalVersion,
    this.kittyWindowId,
  });

  final CellSize size;
  final bool isInteractive;
  final bool? stdinIsTerminal;
  final bool? stdoutIsTerminal;
  final String? term;
  final String? termProgram;
  final String? termProgramVersion;
  final String? colorterm;
  final String? lcTerminal;
  final String? lcTerminalVersion;
  final String? kittyWindowId;

  Map<String, Object?> toJson() => <String, Object?>{
    'term': term,
    'termProgram': termProgram,
    'termProgramVersion': termProgramVersion,
    'colorterm': colorterm,
    'lcTerminal': lcTerminal,
    'lcTerminalVersion': lcTerminalVersion,
    'kittyWindowId': kittyWindowId,
    'columns': size.cols,
    'rows': size.rows,
    'isInteractive': isInteractive,
    'stdinIsTerminal': stdinIsTerminal,
    'stdoutIsTerminal': stdoutIsTerminal,
  };
}

/// Boolean terminal/session conditions derived from environment variables.
@immutable
final class TerminalEnvironmentReport {
  const TerminalEnvironmentReport({
    required this.ssh,
    required this.tmux,
    required this.noColor,
    required this.clicolorForce,
    required this.ci,
  });

  final bool ssh;
  final bool tmux;
  final bool noColor;
  final bool clicolorForce;
  final bool ci;

  Map<String, Object?> toJson() => <String, Object?>{
    'ssh': ssh,
    'tmux': tmux,
    'noColor': noColor,
    'clicolorForce': clicolorForce,
    'ci': ci,
  };
}

/// Local runtime platform evidence serialized by `fleury diagnose --json`.
@immutable
final class TerminalPlatformReport {
  const TerminalPlatformReport({
    required this.operatingSystem,
    required this.operatingSystemVersion,
    required this.dartVersion,
  });

  final String operatingSystem;
  final String operatingSystemVersion;
  final String dartVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'operatingSystem': operatingSystem,
    'operatingSystemVersion': operatingSystemVersion,
    'dartVersion': dartVersion,
  };
}

/// Capability snapshot serialized by `fleury diagnose --json`.
@immutable
final class TerminalCapabilityReport {
  const TerminalCapabilityReport({
    required this.colorMode,
    required this.glyphTier,
    required this.imageProtocol,
    required this.alternateScreen,
    required this.hideCursor,
    required this.tmuxPassthrough,
    required this.ambiguousCharWidth,
    this.bracketedPaste = 'enabledByDefault',
    this.kittyKeyboard = 'attempted',
    this.mouse = 'availableOptIn',
    this.osc52Clipboard = 'policyGated',
    this.osc8Hyperlinks = 'policyGated',
  });

  TerminalCapabilityReport.fromCapabilities(TerminalCapabilities capabilities)
    : this(
        colorMode: capabilities.colorMode,
        glyphTier: capabilities.glyphTier,
        imageProtocol: capabilities.imageProtocol,
        alternateScreen: capabilities.supportsAlternateScreen,
        hideCursor: capabilities.supportsHidingCursor,
        tmuxPassthrough: capabilities.tmuxPassthrough,
        ambiguousCharWidth: capabilities.ambiguousCharWidth,
      );

  final ColorMode colorMode;
  final GlyphTier glyphTier;
  final ImageProtocol imageProtocol;
  final bool alternateScreen;
  final bool hideCursor;
  final String bracketedPaste;
  final String kittyKeyboard;
  final String mouse;
  final String osc52Clipboard;
  final String osc8Hyperlinks;
  final bool tmuxPassthrough;
  final AmbiguousCharWidth ambiguousCharWidth;

  TerminalCapabilities toCapabilities() {
    return TerminalCapabilities(
      colorMode: colorMode,
      glyphTier: glyphTier,
      imageProtocol: imageProtocol,
      supportsAlternateScreen: alternateScreen,
      supportsHidingCursor: hideCursor,
      tmuxPassthrough: tmuxPassthrough,
      ambiguousCharWidth: ambiguousCharWidth,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'colorMode': colorMode.name,
    'glyphTier': glyphTier.name,
    'ambiguousCharWidth': ambiguousCharWidth.name,
    'imageProtocol': imageProtocol.name,
    'alternateScreen': alternateScreen,
    'hideCursor': hideCursor,
    'bracketedPaste': bracketedPaste,
    'kittyKeyboard': kittyKeyboard,
    'mouse': mouse,
    'osc52Clipboard': osc52Clipboard,
    'osc8Hyperlinks': osc8Hyperlinks,
    'tmuxPassthrough': tmuxPassthrough,
  };
}

/// Relationship between passive capability detection and active probe evidence.
enum TerminalCompatibilityStatus {
  /// Passive detection and active probe evidence both indicate support.
  confirmed,

  /// An active probe confirmed support that passive detection did not claim.
  activeConfirmed,

  /// Passive detection claimed support, but active evidence did not confirm it.
  passiveUnverified,

  /// Active evidence indicates the feature is unsupported.
  unsupported,

  /// Probe evidence was skipped, missing, timed out, or errored.
  inconclusive,
}

/// Compatibility finding for one actively probed terminal feature.
@immutable
final class TerminalCompatibilityFinding {
  const TerminalCompatibilityFinding({
    required this.feature,
    required this.label,
    required this.passiveSupported,
    required this.passiveEvidence,
    required this.status,
    this.probeId,
    this.activeStatus,
    this.detail,
  });

  final TerminalFeature feature;
  final String label;
  final bool passiveSupported;
  final String passiveEvidence;
  final TerminalCompatibilityStatus status;
  final String? probeId;
  final TerminalProbeStatus? activeStatus;
  final String? detail;

  Map<String, Object?> toJson() => <String, Object?>{
    'feature': feature.name,
    'label': label,
    'passiveSupported': passiveSupported,
    'passiveEvidence': passiveEvidence,
    'status': status.name,
    if (probeId != null) 'probeId': probeId,
    if (activeStatus != null) 'activeStatus': activeStatus!.name,
    if (detail != null) 'detail': detail,
  };
}

/// Comparison report used by real-terminal compatibility matrix collection.
@immutable
final class TerminalCompatibilityReport {
  const TerminalCompatibilityReport({
    required this.findings,
    this.schemaVersion = 1,
    this.skippedReason,
  });

  final int schemaVersion;
  final String? skippedReason;
  final List<TerminalCompatibilityFinding> findings;

  TerminalCompatibilityFinding? findingFor(TerminalFeature feature) {
    for (final finding in findings) {
      if (finding.feature == feature) return finding;
    }
    return null;
  }

  /// Features that active probe comparison confirmed as available.
  ///
  /// This includes features confirmed by both passive and active evidence, plus
  /// active-only confirmations. Callers can pass this set to
  /// `resolveCapabilityRequirement(additionalAvailableFeatures: ...)` when
  /// using explicitly collected probe evidence for a session.
  Set<TerminalFeature> get confirmedAvailableFeatures {
    return Set<TerminalFeature>.unmodifiable(<TerminalFeature>{
      for (final finding in findings)
        if (finding.status == TerminalCompatibilityStatus.confirmed ||
            finding.status == TerminalCompatibilityStatus.activeConfirmed)
          finding.feature,
    });
  }

  /// Features the active probe confirmed even though passive detection did not.
  Set<TerminalFeature> get activeConfirmedFeatures {
    return Set<TerminalFeature>.unmodifiable(<TerminalFeature>{
      for (final finding in findings)
        if (finding.status == TerminalCompatibilityStatus.activeConfirmed)
          finding.feature,
    });
  }

  Map<String, int> get summary {
    final counts = <String, int>{
      for (final status in TerminalCompatibilityStatus.values) status.name: 0,
    };
    for (final finding in findings) {
      counts[finding.status.name] = (counts[finding.status.name] ?? 0) + 1;
    }
    return Map<String, int>.unmodifiable(counts);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    if (skippedReason != null) 'skippedReason': skippedReason,
    'summary': summary,
    'confirmedAvailableFeatures': <String>[
      for (final feature in confirmedAvailableFeatures) feature.name,
    ],
    'activeConfirmedFeatures': <String>[
      for (final feature in activeConfirmedFeatures) feature.name,
    ],
    'findings': <Object?>[for (final finding in findings) finding.toJson()],
  };
}

/// Machine-readable terminal diagnosis used by the CLI, tests, and demo apps.
@immutable
final class TerminalDiagnosis {
  const TerminalDiagnosis({
    required this.terminal,
    required this.environment,
    required this.capabilities,
    this.platform,
    this.schemaVersion = 1,
    this.fallbacks = const <TerminalDiagnosticMessage>[],
    this.warnings = const <TerminalDiagnosticMessage>[],
    this.unsupportedFeatures = const <String>[],
    this.activeProbes,
    this.compatibility,
  });

  final int schemaVersion;
  final TerminalProfileReport terminal;
  final TerminalEnvironmentReport environment;
  final TerminalPlatformReport? platform;
  final TerminalCapabilityReport capabilities;
  final List<TerminalDiagnosticMessage> fallbacks;
  final List<TerminalDiagnosticMessage> warnings;
  final List<String> unsupportedFeatures;
  final TerminalProbeReport? activeProbes;
  final TerminalCompatibilityReport? compatibility;

  TerminalCapabilities get passiveCapabilities => capabilities.toCapabilities();

  Set<TerminalFeature> get confirmedAvailableFeatures {
    return compatibility?.confirmedAvailableFeatures ??
        const <TerminalFeature>{};
  }

  TerminalDiagnosis withActiveProbes(TerminalProbeReport report) {
    return TerminalDiagnosis(
      schemaVersion: schemaVersion,
      terminal: terminal,
      environment: environment,
      platform: platform,
      capabilities: capabilities,
      fallbacks: fallbacks,
      warnings: warnings,
      unsupportedFeatures: unsupportedFeatures,
      activeProbes: report,
      compatibility: buildTerminalCompatibilityReport(
        capabilities: capabilities,
        activeProbes: report,
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'terminal': terminal.toJson(),
    'environment': environment.toJson(),
    if (platform != null) 'platform': platform!.toJson(),
    'capabilities': capabilities.toJson(),
    'fallbacks': <Object?>[for (final fallback in fallbacks) fallback.toJson()],
    'warnings': <Object?>[for (final warning in warnings) warning.toJson()],
    'unsupportedFeatures': unsupportedFeatures,
    if (activeProbes != null) 'activeProbes': activeProbes!.toJson(),
    if (compatibility != null) 'compatibility': compatibility!.toJson(),
  };
}

/// Compares passive terminal capability detection with active probe evidence.
TerminalCompatibilityReport buildTerminalCompatibilityReport({
  required TerminalCapabilityReport capabilities,
  TerminalProbeReport? activeProbes,
}) {
  final skippedReason = activeProbes?.skippedReason;
  return TerminalCompatibilityReport(
    skippedReason: skippedReason,
    findings: <TerminalCompatibilityFinding>[
      _buildCompatibilityFinding(
        feature: TerminalFeature.kittyKeyboard,
        label: 'Kitty keyboard protocol',
        passiveSupported: capabilities.kittyKeyboard == 'confirmed',
        passiveEvidence:
            'capabilities.kittyKeyboard=${capabilities.kittyKeyboard}',
        probe: activeProbes?.resultFor('kittyKeyboardStatus'),
        skippedReason: skippedReason,
      ),
      _buildCompatibilityFinding(
        feature: TerminalFeature.imageKitty,
        label: 'Kitty graphics protocol',
        passiveSupported: capabilities.imageProtocol == ImageProtocol.kitty,
        passiveEvidence:
            'capabilities.imageProtocol=${capabilities.imageProtocol.name}',
        probe: activeProbes?.resultFor('kittyGraphicsQuery'),
        skippedReason: skippedReason,
      ),
    ],
  );
}

TerminalCompatibilityFinding _buildCompatibilityFinding({
  required TerminalFeature feature,
  required String label,
  required bool passiveSupported,
  required String passiveEvidence,
  required TerminalProbeResult? probe,
  required String? skippedReason,
}) {
  final activeStatus = probe?.status;
  return TerminalCompatibilityFinding(
    feature: feature,
    label: label,
    passiveSupported: passiveSupported,
    passiveEvidence: passiveEvidence,
    probeId: probe?.id,
    activeStatus: activeStatus,
    status: _compatibilityStatus(
      passiveSupported: passiveSupported,
      activeStatus: activeStatus,
      skipped: skippedReason != null,
    ),
    detail: skippedReason ?? probe?.detail,
  );
}

TerminalCompatibilityStatus _compatibilityStatus({
  required bool passiveSupported,
  required TerminalProbeStatus? activeStatus,
  required bool skipped,
}) {
  if (skipped || activeStatus == null) {
    return TerminalCompatibilityStatus.inconclusive;
  }
  return switch (activeStatus) {
    TerminalProbeStatus.confirmed =>
      passiveSupported
          ? TerminalCompatibilityStatus.confirmed
          : TerminalCompatibilityStatus.activeConfirmed,
    TerminalProbeStatus.unsupported =>
      passiveSupported
          ? TerminalCompatibilityStatus.passiveUnverified
          : TerminalCompatibilityStatus.unsupported,
    TerminalProbeStatus.skipped ||
    TerminalProbeStatus.timeout ||
    TerminalProbeStatus.error => TerminalCompatibilityStatus.inconclusive,
  };
}

/// Builds a static/env-derived diagnosis for [driver].
TerminalDiagnosis diagnoseTerminal(
  TerminalDriver driver, {
  Map<String, String> environment = const <String, String>{},
  TerminalPlatformReport? platform,
  bool? stdinIsTerminal,
  bool? stdoutIsTerminal,
}) {
  final capabilities = driver.capabilities;
  final terminal = TerminalProfileReport(
    size: driver.size,
    isInteractive: driver.isInteractive,
    stdinIsTerminal: stdinIsTerminal,
    stdoutIsTerminal: stdoutIsTerminal ?? driver.isInteractive,
    term: _envOrNull(environment, 'TERM'),
    termProgram: _envOrNull(environment, 'TERM_PROGRAM'),
    termProgramVersion: _envOrNull(environment, 'TERM_PROGRAM_VERSION'),
    colorterm: _envOrNull(environment, 'COLORTERM'),
    lcTerminal: _envOrNull(environment, 'LC_TERMINAL'),
    lcTerminalVersion: _envOrNull(environment, 'LC_TERMINAL_VERSION'),
    kittyWindowId: _envOrNull(environment, 'KITTY_WINDOW_ID'),
  );
  final envReport = TerminalEnvironmentReport(
    ssh: _isSsh(environment),
    tmux: detectTerminalMultiplexerFromEnvironment(environment),
    noColor: (environment['NO_COLOR'] ?? '').isNotEmpty,
    clicolorForce: _clicolorForce(environment),
    ci: (environment['CI'] ?? '').isNotEmpty,
  );
  final capabilityReport = TerminalCapabilityReport.fromCapabilities(
    capabilities,
  );
  final fallbacks = _buildFallbacks(capabilities, terminal, envReport);
  final warnings = _buildWarnings(terminal, envReport);
  final unsupported = _buildUnsupportedFeatures(capabilities, terminal);
  return TerminalDiagnosis(
    terminal: terminal,
    environment: envReport,
    platform: platform,
    capabilities: capabilityReport,
    fallbacks: fallbacks,
    warnings: warnings,
    unsupportedFeatures: unsupported,
  );
}

String? _envOrNull(Map<String, String> environment, String name) {
  final value = environment[name];
  if (value == null || value.isEmpty) return null;
  return value;
}

bool _isSsh(Map<String, String> environment) {
  return (environment['SSH_TTY'] ?? '').isNotEmpty ||
      (environment['SSH_CONNECTION'] ?? '').isNotEmpty ||
      (environment['SSH_CLIENT'] ?? '').isNotEmpty;
}

bool _clicolorForce(Map<String, String> environment) {
  final value = environment['CLICOLOR_FORCE'];
  return value != null && value.isNotEmpty && value != '0';
}

List<TerminalDiagnosticMessage> _buildFallbacks(
  TerminalCapabilities capabilities,
  TerminalProfileReport terminal,
  TerminalEnvironmentReport environment,
) {
  final fallbacks = <TerminalDiagnosticMessage>[];
  if (capabilities.colorMode == ColorMode.none) {
    fallbacks.add(
      TerminalDiagnosticMessage(
        severity: TerminalDiagnosticSeverity.info,
        code: 'color_monochrome_fallback',
        message: 'Styled color output will degrade to monochrome text.',
        details: <String, Object?>{'noColor': environment.noColor},
      ),
    );
  }
  if (capabilities.imageProtocol == ImageProtocol.halfBlock) {
    fallbacks.add(
      const TerminalDiagnosticMessage(
        severity: TerminalDiagnosticSeverity.info,
        code: 'image_half_block_fallback',
        message: 'Native image output is unavailable; images use cell art.',
      ),
    );
  }
  if (capabilities.glyphTier == GlyphTier.ascii) {
    fallbacks.add(
      const TerminalDiagnosticMessage(
        severity: TerminalDiagnosticSeverity.info,
        code: 'glyph_ascii_fallback',
        message: 'Unicode drawing glyphs will degrade to ASCII output.',
      ),
    );
  }
  if (!capabilities.supportsAlternateScreen) {
    fallbacks.add(
      const TerminalDiagnosticMessage(
        severity: TerminalDiagnosticSeverity.warning,
        code: 'alternate_screen_unavailable',
        message: 'Fullscreen apps should fall back to inline rendering.',
      ),
    );
  }
  if (!capabilities.supportsHidingCursor) {
    fallbacks.add(
      const TerminalDiagnosticMessage(
        severity: TerminalDiagnosticSeverity.info,
        code: 'cursor_hiding_unavailable',
        message: 'The cursor will remain visible while apps render.',
      ),
    );
  }
  if (!terminal.isInteractive) {
    fallbacks.add(
      const TerminalDiagnosticMessage(
        severity: TerminalDiagnosticSeverity.warning,
        code: 'visual_output_unavailable',
        message: 'Visual TUI output is unavailable when stdout is not a TTY.',
      ),
    );
  }
  return fallbacks;
}

List<TerminalDiagnosticMessage> _buildWarnings(
  TerminalProfileReport terminal,
  TerminalEnvironmentReport environment,
) {
  final warnings = <TerminalDiagnosticMessage>[];
  if (!terminal.isInteractive) {
    warnings.add(
      const TerminalDiagnosticMessage(
        severity: TerminalDiagnosticSeverity.warning,
        code: 'non_interactive_stdout',
        message: 'Stdout is not interactive, so screen-control output is off.',
      ),
    );
  }
  if (terminal.stdinIsTerminal == false) {
    warnings.add(
      const TerminalDiagnosticMessage(
        severity: TerminalDiagnosticSeverity.warning,
        code: 'non_interactive_stdin',
        message: 'Stdin is not a terminal; raw key input may be unavailable.',
      ),
    );
  }
  if (environment.tmux) {
    warnings.add(
      const TerminalDiagnosticMessage(
        severity: TerminalDiagnosticSeverity.info,
        code: 'terminal_multiplexer',
        message: 'tmux/screen is active; rich protocols may need passthrough.',
      ),
    );
  }
  if (environment.ssh) {
    warnings.add(
      const TerminalDiagnosticMessage(
        severity: TerminalDiagnosticSeverity.info,
        code: 'remote_terminal',
        message: 'SSH is active; capabilities may reflect the local terminal.',
      ),
    );
  }
  return warnings;
}

List<String> _buildUnsupportedFeatures(
  TerminalCapabilities capabilities,
  TerminalProfileReport terminal,
) {
  final unsupported = <String>[];
  if (!terminal.isInteractive) unsupported.add('visualTuiOutput');
  if (capabilities.colorMode == ColorMode.none) unsupported.add('ansiColor');
  if (capabilities.imageProtocol == ImageProtocol.halfBlock) {
    unsupported.add('nativeImages');
  }
  if (!capabilities.supportsAlternateScreen) {
    unsupported.add('alternateScreen');
  }
  if (!capabilities.supportsHidingCursor) unsupported.add('cursorHiding');
  return unsupported;
}
