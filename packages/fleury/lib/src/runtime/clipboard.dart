// Clipboard: layered write strategy for cross-terminal compatibility.
//
//   1. Platform tool (pbcopy / wl-copy / xclip / clip.exe) when not
//      over SSH — most reliable locally, gets the system clipboard
//      directly.
//   2. OSC 52 base64 escape — broadly supported across modern
//      terminals (alacritty, foot, iTerm2, Kitty, tmux passthrough,
//      WezTerm, Windows Terminal, Ghostty, Zellij). The only path
//      that survives SSH/tmux nesting.
//   3. In-process register — always populated, so a paste-within-app
//      always works regardless of terminal capabilities.
//
// Reads from the system clipboard are not provided: OSC 52 reads are
// widely disabled for security, and the in-process register is the
// reliable cross-terminal alternative.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../semantics/semantics.dart';
import '../terminal/capabilities.dart';
import '../terminal/capability_requirements.dart';

/// Which transport actually placed the clipboard payload.
enum ClipboardWriteResult {
  /// A native platform tool (pbcopy / wl-copy / xclip / xsel /
  /// clip.exe) was found and successfully consumed the payload.
  platformTool,

  /// An OSC 52 escape sequence was emitted to stdout; the terminal
  /// is expected to interpret it and update its clipboard.
  osc52,

  /// Only the in-process register was populated — no usable
  /// transport. Either the payload exceeded the safe OSC 52 cap or
  /// every other path failed.
  inProcessOnly,
}

/// Policy for one clipboard write operation.
final class ClipboardWritePolicy {
  const ClipboardWritePolicy({
    this.name = 'custom',
    this.allowPlatformTool = true,
    this.allowPlatformToolOverSsh = false,
    this.allowOsc52 = true,
    this.maxOsc52EncodedLength = 100000,
  });

  static const standard = ClipboardWritePolicy(name: 'standard');

  static const inProcessOnly = ClipboardWritePolicy(
    name: 'inProcessOnly',
    allowPlatformTool: false,
    allowOsc52: false,
  );

  final String name;
  final bool allowPlatformTool;
  final bool allowPlatformToolOverSsh;
  final bool allowOsc52;
  final int maxOsc52EncodedLength;
}

/// Structured result for diagnostics, semantics, and tests.
final class ClipboardWriteReport {
  const ClipboardWriteReport({
    required this.result,
    required this.resolution,
    required this.policy,
    required this.payloadBytes,
    required this.osc52EncodedLength,
    required this.overSsh,
    required this.inProcessUpdated,
    required this.platformToolAttempted,
    required this.osc52Attempted,
    required this.osc52Emitted,
    this.platformTool,
  });

  final ClipboardWriteResult result;
  final CapabilityResolution resolution;
  final ClipboardWritePolicy policy;
  final int payloadBytes;
  final int osc52EncodedLength;
  final bool overSsh;
  final bool inProcessUpdated;
  final bool platformToolAttempted;
  final bool osc52Attempted;
  final bool osc52Emitted;
  final String? platformTool;

  SemanticState toSemanticState() {
    return resolution.toSemanticState().merge(<String, Object?>{
      'clipboardTransport': result.name,
      'clipboardPolicy': policy.name,
      'clipboardPayloadBytes': payloadBytes,
      'clipboardOsc52EncodedLength': osc52EncodedLength,
      'clipboardOverSsh': overSsh,
      'clipboardInProcessUpdated': inProcessUpdated,
      'clipboardPlatformToolAttempted': platformToolAttempted,
      'clipboardOsc52Attempted': osc52Attempted,
      'clipboardOsc52Emitted': osc52Emitted,
      if (platformTool != null) 'clipboardPlatformTool': platformTool,
    });
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'result': result.name,
        'policy': policy.name,
        'payloadBytes': payloadBytes,
        'osc52EncodedLength': osc52EncodedLength,
        'overSsh': overSsh,
        'inProcessUpdated': inProcessUpdated,
        'platformToolAttempted': platformToolAttempted,
        'osc52Attempted': osc52Attempted,
        'osc52Emitted': osc52Emitted,
        if (platformTool != null) 'platformTool': platformTool,
        'resolution': resolution.toJson(),
      };
}

/// System-clipboard interop.
///
/// Default implementation routes through whichever layer is most
/// reliable for the current environment. Tests can replace
/// [Clipboard.instance] with [TestClipboard] to capture writes
/// without emitting escape sequences to stdout.
abstract class Clipboard {
  /// The active clipboard implementation. Defaults to
  /// [SystemClipboard]; replace with [TestClipboard] in tests or
  /// with a custom subclass for app-specific behavior.
  static Clipboard instance = SystemClipboard();

  /// Writes [text] to the system clipboard and the in-process
  /// register. Returns the transport that actually delivered it.
  Future<ClipboardWriteResult> write(String text) async {
    final report = await writeWithReport(text);
    return report.result;
  }

  /// Writes [text] and returns a structured diagnostic report.
  Future<ClipboardWriteReport> writeWithReport(
    String text, {
    ClipboardWritePolicy policy = ClipboardWritePolicy.standard,
  });

  /// Reads the in-process register. Cross-terminal clipboard reads
  /// via OSC 52 are widely disabled for security, so this is the
  /// only reliable read path. Returns null when nothing has been
  /// written this session.
  String? readInProcess();
}

/// Production clipboard backed by platform tools and OSC 52.
class SystemClipboard extends Clipboard {
  SystemClipboard({
    Map<String, String>? environment,
    void Function(String)? stdoutWrite,
    Future<bool> Function(String executable, List<String> args, String text)?
        runTool,
  })  : _env = environment ?? Platform.environment,
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
              resolution: _availableClipboardResolution(
                TerminalFeature.clipboardWrite,
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
      resolution: _availableClipboardResolution(TerminalFeature.osc52Clipboard),
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

/// Test-only clipboard: writes go into the in-process register only,
/// never touching stdout or spawning subprocesses. The last write is
/// inspectable via [lastWritten].
class TestClipboard extends Clipboard {
  String? _last;

  /// The text passed to the most recent [write], or null if nothing
  /// has been written.
  String? get lastWritten => _last;

  @override
  Future<ClipboardWriteReport> writeWithReport(
    String text, {
    ClipboardWritePolicy policy = ClipboardWritePolicy.standard,
  }) async {
    _last = text;
    return ClipboardWriteReport(
      result: ClipboardWriteResult.inProcessOnly,
      resolution: const CapabilityResolution(
        feature: TerminalFeature.clipboardWrite,
        level: CapabilityLevel.preferred,
        state: CapabilityResolutionState.degraded,
        fallbackLabel: 'in-process register',
      ),
      policy: policy,
      payloadBytes: utf8.encode(text).length,
      osc52EncodedLength: base64Encode(utf8.encode(text)).length,
      overSsh: false,
      inProcessUpdated: true,
      platformToolAttempted: false,
      osc52Attempted: false,
      osc52Emitted: false,
    );
  }

  @override
  String? readInProcess() => _last;
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

CapabilityResolution _availableClipboardResolution(TerminalFeature feature) {
  return resolveCapabilityRequirement(
    CapabilityRequirement(
      feature: feature,
      level: CapabilityLevel.preferred,
      reason: 'Copy text to the user clipboard.',
      fallback: const CapabilityFallback(label: 'in-process register'),
    ),
    TerminalCapabilities.defaultCapabilities,
    additionalAvailableFeatures: <TerminalFeature>{feature},
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
    TerminalCapabilities.defaultCapabilities,
    policyBlockedFeatures: const <TerminalFeature>{
      TerminalFeature.osc52Clipboard,
    },
  );
}
