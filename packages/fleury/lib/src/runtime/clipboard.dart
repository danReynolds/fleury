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
//
// This file is platform-neutral (no dart:io): it holds the contract,
// the policies/reports, and the in-process default. The production
// SystemClipboard (paths 1 and 2 above) lives in system_clipboard.dart
// and is exported only from the native `fleury.dart` umbrella; each host
// owns an instance and shares it with widgets via ClipboardScope.

import 'dart:async';
import 'dart:convert';

import '../semantics/semantics.dart';
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

  /// The presenting surface's host accepted the payload — a served
  /// session's browser placed it on the USER's clipboard over the wire.
  hostSurface,
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
/// A host service, not a global. Each host owns a concrete instance —
/// `runApp` a `SystemClipboard` (platform tools + OSC 52), the browser
/// hosts a `WebClipboard`, `FleuryTester` an [InProcessClipboard] — and
/// shares it with widgets through `ClipboardScope`; call sites resolve it
/// with `ClipboardScope.of(context)`.
abstract class Clipboard {
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

/// Platform-neutral clipboard: writes populate the in-process
/// register only, never touching stdout or spawning subprocesses. The
/// test default (`FleuryTester` installs one and exposes it as
/// `tester.clipboard`) and the io-free fallback for embedders that have
/// no platform clipboard.
class InProcessClipboard extends Clipboard {
  String? _register;

  /// The text passed to the most recent [write], or null if nothing has
  /// been written — the assertion hook for tests.
  String? get lastWritten => _register;

  @override
  String? readInProcess() => _register;

  @override
  Future<ClipboardWriteReport> writeWithReport(
    String text, {
    ClipboardWritePolicy policy = ClipboardWritePolicy.standard,
  }) async {
    _register = text;
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
}
