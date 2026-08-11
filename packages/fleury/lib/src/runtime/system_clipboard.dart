// SystemClipboard: the dart:io-backed production clipboard.
//
// Split out of clipboard.dart so the platform-neutral contract
// (Clipboard, policies, reports, the in-process register) stays free
// of dart:io. This file is exported only from the native `fleury.dart`
// umbrella; `runApp` owns a [SystemClipboard] (unless the app passed its
// own clipboard) and shares it with widgets via ClipboardScope.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../terminal/capability_requirements.dart';
import 'clipboard.dart';

/// Production clipboard backed by platform tools and OSC 52.
class SystemClipboard extends Clipboard {
  SystemClipboard({
    Map<String, String>? environment,
    void Function(String)? stdoutWrite,
    Future<bool> Function(String executable, List<String> args, String text)?
    runTool,
  }) : _env = environment ?? Platform.environment,
       _stdoutWrite = stdoutWrite ?? stdout.write,
       _runTool = runTool ?? _defaultRunTool;

  final Map<String, String> _env;
  final void Function(String) _stdoutWrite;
  final Future<bool> Function(String, List<String>, String) _runTool;
  String? _register;

  @override
  String? readInProcess() => _register;

  @override
  Future<ClipboardWriteReport> writeWithReport(
    String text, {
    ClipboardWritePolicy policy = ClipboardWritePolicy.standard,
  }) async {
    _register = text;
    final payloadBytes = utf8.encode(text).length;
    final encoded = base64Encode(utf8.encode(text));
    final overSsh = _isOverSsh;

    // Path 1: platform tool. Skipped when over SSH — the tool would
    // copy to the *remote* machine's clipboard, which is not what
    // the user expects.
    var platformToolAttempted = false;
    String? platformTool;
    if (policy.allowPlatformTool &&
        (!overSsh || policy.allowPlatformToolOverSsh)) {
      final tool = _findPlatformTool();
      if (tool != null) {
        platformToolAttempted = true;
        platformTool = tool.executable;
        try {
          if (await _runTool(tool.executable, tool.args, text)) {
            return ClipboardWriteReport(
              result: ClipboardWriteResult.platformTool,
              resolution: _deliveredClipboardResolution(
                TerminalFeature.clipboardWrite,
                '$platformTool exited successfully after consuming the payload.',
              ),
              policy: policy,
              payloadBytes: payloadBytes,
              osc52EncodedLength: encoded.length,
              overSsh: overSsh,
              inProcessUpdated: true,
              platformToolAttempted: platformToolAttempted,
              osc52Attempted: false,
              osc52Emitted: false,
              platformTool: platformTool,
            );
          }
        } catch (_) {
          // Fall through to OSC 52.
        }
      }
    }

    // Path 2: OSC 52. Safe cap is ~74KB raw (≈100KB base64). Larger
    // payloads are rejected rather than truncated — a partial copy
    // is worse than no copy.
    final osc52Allowed =
        policy.allowOsc52 && encoded.length <= policy.maxOsc52EncodedLength;
    if (!osc52Allowed) {
      return ClipboardWriteReport(
        result: ClipboardWriteResult.inProcessOnly,
        resolution: _blockedOsc52Resolution(),
        policy: policy,
        payloadBytes: payloadBytes,
        osc52EncodedLength: encoded.length,
        overSsh: overSsh,
        inProcessUpdated: true,
        platformToolAttempted: platformToolAttempted,
        osc52Attempted: false,
        osc52Emitted: false,
        platformTool: platformTool,
      );
    }
    _stdoutWrite('\x1b]52;c;$encoded\x07');
    return ClipboardWriteReport(
      result: ClipboardWriteResult.osc52,
      resolution: _unverifiedOsc52Resolution(),
      policy: policy,
      payloadBytes: payloadBytes,
      osc52EncodedLength: encoded.length,
      overSsh: overSsh,
      inProcessUpdated: true,
      platformToolAttempted: platformToolAttempted,
      osc52Attempted: true,
      osc52Emitted: true,
      platformTool: platformTool,
    );
  }

  bool get _isOverSsh =>
      _env['SSH_TTY'] != null ||
      _env['SSH_CONNECTION'] != null ||
      _env['SSH_CLIENT'] != null;

  /// Picks the first viable platform tool for the current OS.
  _PlatformTool? _findPlatformTool() {
    if (Platform.isMacOS) {
      return const _PlatformTool('pbcopy', <String>[]);
    }
    if (Platform.isWindows) {
      return const _PlatformTool('clip', <String>[]);
    }
    if (Platform.isLinux) {
      // Wayland preferred when both are present; xclip beats xsel on
      // historical reliability.
      if (_env['WAYLAND_DISPLAY'] != null) {
        return const _PlatformTool('wl-copy', <String>[]);
      }
      if (_env['DISPLAY'] != null) {
        return const _PlatformTool('xclip', <String>[
          '-selection',
          'clipboard',
        ]);
      }
    }
    return null;
  }
}

/// One platform-tool invocation: the executable name plus argv.
class _PlatformTool {
  const _PlatformTool(this.executable, this.args);
  final String executable;
  final List<String> args;
}

Future<bool> _defaultRunTool(
  String executable,
  List<String> args,
  String text,
) async {
  final Process proc;
  try {
    proc = await Process.start(executable, args);
  } on ProcessException {
    return false;
  }
  proc.stdin.write(text);
  await proc.stdin.flush();
  await proc.stdin.close();
  final code = await proc.exitCode;
  return code == 0;
}

CapabilityResolution _deliveredClipboardResolution(
  TerminalFeature feature,
  String detail,
) {
  return resolveCapabilityRequirement(
    CapabilityRequirement(
      feature: feature,
      level: CapabilityLevel.preferred,
      reason: 'Copy text to the user clipboard.',
      fallback: const CapabilityFallback(label: 'in-process register'),
    ),
    CapabilityTruth(
      feature: feature,
      support: CapabilitySupport.supported,
      enablement: CapabilityEnablement.notApplicable,
      delivery: CapabilityDelivery.delivered,
      evidence: <CapabilityEvidence>[
        CapabilityEvidence(
          source: CapabilityEvidenceSource.operationResult,
          detail: detail,
        ),
      ],
    ),
  );
}

CapabilityResolution _unverifiedOsc52Resolution() {
  return resolveCapabilityRequirement(
    const CapabilityRequirement(
      feature: TerminalFeature.osc52Clipboard,
      level: CapabilityLevel.preferred,
      reason:
          'Copy text through OSC 52 when platform clipboard is unavailable.',
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
          detail:
              'The OSC 52 sequence was emitted; the terminal does not acknowledge clipboard delivery.',
        ),
      ],
    ),
  );
}

CapabilityResolution _blockedOsc52Resolution() {
  return resolveCapabilityRequirement(
    const CapabilityRequirement(
      feature: TerminalFeature.osc52Clipboard,
      level: CapabilityLevel.preferred,
      reason:
          'Copy text through OSC 52 when platform clipboard is unavailable.',
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
          detail: 'The clipboard policy did not permit this OSC 52 write.',
        ),
      ],
    ),
  );
}
