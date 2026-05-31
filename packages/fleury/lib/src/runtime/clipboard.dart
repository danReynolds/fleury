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
  Future<ClipboardWriteResult> write(String text);

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
  Future<ClipboardWriteResult> write(String text) async {
    _register = text;

    // Path 1: platform tool. Skipped when over SSH — the tool would
    // copy to the *remote* machine's clipboard, which is not what
    // the user expects.
    if (!_isOverSsh) {
      final tool = _findPlatformTool();
      if (tool != null) {
        try {
          if (await _runTool(tool.executable, tool.args, text)) {
            return ClipboardWriteResult.platformTool;
          }
        } catch (_) {
          // Fall through to OSC 52.
        }
      }
    }

    // Path 2: OSC 52. Safe cap is ~74KB raw (≈100KB base64). Larger
    // payloads are rejected rather than truncated — a partial copy
    // is worse than no copy.
    final encoded = base64Encode(utf8.encode(text));
    if (encoded.length > 100000) {
      return ClipboardWriteResult.inProcessOnly;
    }
    _stdoutWrite('\x1b]52;c;$encoded\x07');
    return ClipboardWriteResult.osc52;
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
  Future<ClipboardWriteResult> write(String text) async {
    _last = text;
    return ClipboardWriteResult.inProcessOnly;
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
