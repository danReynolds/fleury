// `fleury shell`'s side of one attached app: the terminal the shell takes
// over for it, and the relay that moves bytes between the two.
//
// While an app is attached, the shell's terminal is the app's terminal, so it
// is set up exactly as the app's own native driver would set it up — with the
// same primitives: raw input through the native termios controller (no
// ISIG/ICANON/ECHO/IXON, so Ctrl+C and Ctrl+Z are bytes the app decides
// about, not signals that stop or kill the shell), the shared screen-mode
// sequences, and the cancellable native input borrow. When the session ends,
// for any reason, the terminal is handed back exactly as it was found.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:stdio/stdio.dart' as fd;

import '../foundation/geometry.dart';
import '../input/keyboard_state.dart';
import '../remote/remote_protocol.dart';
import '../remote/remote_transport.dart';
import '../remote/shell_init.dart';
import '../terminal/capabilities.dart';
import '../terminal/posix_driver.dart' show NativePosixTerminalModeController;
import '../terminal/posix_input_lease.dart';
import '../terminal/terminal_driver.dart';
import '../terminal/terminal_probe.dart';
import '../terminal/terminal_sequences.dart';

/// The screen modes `fleury shell` enters for an attached app: the full-screen
/// mode the app's own native driver enters, with the disambiguated keyboard
/// tier.
///
/// Flag 2 of that tier is what lets a binding behind the relay fire once per
/// press rather than once per auto-repeat, as it does in a local session
/// (RFC 0020 §8.1). The shell stops short of the lifecycle tier because
/// negotiating it takes the transactional fallback only the native driver
/// runs: a terminal that honours flag 8 without flag 16 sends no text at all.
/// The INIT declares what the terminal actually confirmed.
const TerminalMode shellTerminalMode = TerminalMode.fullScreen(
  keyboardProtocol: KeyboardProtocolMode.disambiguated,
);

/// The terminal `fleury shell` draws an attached app in.
abstract interface class ShellTerminal {
  /// The terminal's size in cells.
  CellSize get size;

  /// Takes the terminal over for an app: raw input, [shellTerminalMode]'s
  /// screen modes, and a reader that passes every byte typed to [onInput].
  ///
  /// [onGone] runs at most once, if the terminal itself goes away: its input
  /// ends or fails, which in raw mode means the terminal hung up. A failed
  /// acquisition may have changed part of the terminal; [release] still
  /// hands it back.
  Future<void> acquire({
    required void Function(Uint8List bytes) onInput,
    required void Function() onGone,
  });

  /// Writes app output, or a terminal query, to the screen. A terminal that
  /// has gone away reports it through [acquire]'s `onGone` instead of
  /// throwing.
  void write(List<int> bytes);

  /// Hands the terminal back exactly as [acquire] found it, undoing whatever
  /// part of it is still held. Idempotent. Throws the first failure after
  /// attempting every step.
  Future<void> release();
}

/// The shell's own terminal: stdin and stdout of a macOS or Linux process.
final class NativeShellTerminal implements ShellTerminal {
  NativeShellTerminal()
    // The native input borrow sets O_NONBLOCK on a duplicate of stdin, which
    // a terminal often shares with stdout; dart:io's stdout would then fail a
    // write with EAGAIN when the terminal's queue fills. This sink retries,
    // as the native driver's does. It borrows fd 1 and never closes it.
    : _output = fd.StdoutTerminalSink(1),
      // One snapshot per session: restoration returns the terminal to the
      // state this attach found, and a failed restore cannot poison the next
      // session's attach.
      _modes = NativePosixTerminalModeController();

  final fd.StdoutTerminalSink _output;
  final NativePosixTerminalModeController _modes;
  PosixInputLease? _input;
  void Function()? _onGone;
  bool _rawModeOwned = false;
  bool _screenOwned = false;
  Future<void> _releaseTail = Future<void>.value();

  @override
  CellSize get size {
    final cols = _output.columns;
    final rows = _output.rows;
    return cols == null || rows == null || cols <= 0 || rows <= 0
        ? const CellSize(80, 24)
        : CellSize(cols, rows);
  }

  @override
  Future<void> acquire({
    required void Function(Uint8List bytes) onInput,
    required void Function() onGone,
  }) async {
    // Own the obligation before the change: raw mode can fail part-way, and
    // release must still roll back whatever did change.
    _rawModeOwned = true;
    if (!_modes.enableRawMode()) {
      throw StateError(
        'fleury shell needs native terminal control (termios), which this '
        'platform does not provide.',
      );
    }
    var gone = false;
    void terminalGone() {
      if (gone) return;
      gone = true;
      onGone();
    }

    _onGone = terminalGone;
    _screenOwned = true;
    write(utf8.encode(buildTerminalEnterSequences(shellTerminalMode)));
    final input = _input = PosixInputLease(
      onBytes: onInput,
      onDone: terminalGone,
      onError: (_, _) => terminalGone(),
    );
    await input.start();
  }

  @override
  void write(List<int> bytes) {
    try {
      _output.add(bytes);
    } catch (_) {
      if (!posixDescriptorHungUp(1)) rethrow;
      _onGone?.call();
    }
  }

  @override
  Future<void> release() {
    final released = _releaseTail.then((_) => _release());
    _releaseTail = released.then<void>((_) {}, onError: (Object _) {});
    return released;
  }

  Future<void> _release() async {
    (Object, StackTrace)? failure;
    // The screen first. Leaving it stops the terminal's focus and paste
    // reports while the reader still drains them, and pops the keyboard flags
    // on the screen they were pushed to (RFC 0020 §8.1).
    if (_screenOwned) {
      _screenOwned = false;
      try {
        _output.write(buildTerminalExitSequences(shellTerminalMode));
      } catch (error, stack) {
        // A terminal that hung up has no screen left to restore.
        if (!posixDescriptorHungUp(1)) failure ??= (error, stack);
      }
    }
    final input = _input;
    _input = null;
    if (input != null) {
      try {
        await input.stop();
      } catch (error, stack) {
        failure ??= (error, stack);
      }
    }
    if (_rawModeOwned) {
      _rawModeOwned = false;
      try {
        _modes.restoreMode();
      } catch (error, stack) {
        failure ??= (error, stack);
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure.$1, failure.$2);
  }
}

/// Why a [ShellSession] ended.
enum ShellSessionEndReason {
  /// The app said goodbye: it exited.
  appExited,

  /// The app's connection closed without a goodbye: it crashed, or was
  /// stopped or killed (an IDE's Stop and Restart).
  appDisconnected,

  /// The shell's terminal went away.
  terminalGone,

  /// The shell is exiting.
  shutdown,

  /// The session could not continue; [ShellSessionEnd.error] says why.
  failed,
}

/// How a [ShellSession] ended, and whether the terminal came back cleanly.
final class ShellSessionEnd {
  const ShellSessionEnd(this.reason, {this.error, this.restoreError});

  final ShellSessionEndReason reason;

  /// Why the session failed, for [ShellSessionEndReason.failed].
  final Object? error;

  /// Why handing the terminal back failed, if it did.
  final Object? restoreError;
}

/// One attached app: [run] takes the terminal over, relays until the app or
/// the shell ends the session, then hands the terminal back and closes
/// [transport].
///
/// Every byte typed is forwarded, including Ctrl+C and Ctrl+Z: the app
/// decides what they mean, as it does in a terminal of its own. Window-size
/// changes are forwarded as RESIZE frames.
final class ShellSession {
  ShellSession(
    this.transport, {
    ShellTerminal? terminal,
    Stream<Object?>? resizes,
    Map<String, String>? environment,
  }) : _terminal = terminal ?? NativeShellTerminal(),
       _resizeSignals = resizes ?? ProcessSignal.sigwinch.watch(),
       _environment = environment ?? Platform.environment;

  final RemoteFrameTransport transport;
  final ShellTerminal _terminal;
  final Stream<Object?> _resizeSignals;
  final Map<String, String> _environment;
  final _ended = Completer<ShellSessionEnd>();
  _ShellKeyboardProbe? _probe;
  StreamSubscription<RemoteFrame>? _frames;
  StreamSubscription<Object?>? _resizes;
  Future<ShellSessionEnd>? _run;

  /// Runs the session, completing once the terminal is handed back and the
  /// connection closed. Calling it again returns the same run.
  Future<ShellSessionEnd> run() => _run ??= _runSession();

  /// Ends the session because the shell is exiting. [run] completes once the
  /// terminal is handed back and the app has been told goodbye. The terminal
  /// comes back first, so an app that is not reading (paused in a debugger)
  /// cannot keep the terminal raw.
  void shutdown() =>
      _end(const ShellSessionEnd(ShellSessionEndReason.shutdown));

  void _end(ShellSessionEnd end) {
    if (!_ended.isCompleted) _ended.complete(end);
  }

  Future<ShellSessionEnd> _runSession() async {
    try {
      await _start();
    } catch (error) {
      _end(ShellSessionEnd(ShellSessionEndReason.failed, error: error));
    }
    final end = await _ended.future;
    await _frames?.cancel();
    await _resizes?.cancel();
    Object? restoreError;
    try {
      await _terminal.release();
    } catch (error) {
      restoreError = error;
    }
    if (end.reason != ShellSessionEndReason.appExited &&
        end.reason != ShellSessionEndReason.appDisconnected) {
      try {
        transport.send(const ByeFrame());
      } catch (_) {
        // The app may already be gone; closing below still ends it.
      }
    }
    try {
      await transport.close();
    } catch (_) {
      // Best-effort: the peer may have reset the connection already.
    }
    return restoreError == null
        ? end
        : ShellSessionEnd(
            end.reason,
            error: end.error,
            restoreError: restoreError,
          );
  }

  Future<void> _start() async {
    final probe = _probe = _ShellKeyboardProbe(_terminal);
    await _terminal.acquire(
      onInput: _onInput,
      onGone: () =>
          _end(const ShellSessionEnd(ShellSessionEndReason.terminalGone)),
    );
    if (_ended.isCompleted) return;

    // Ask the real terminal what actually stuck: the app behind the relay
    // needs a keyboard declaration it can trust rather than an inference
    // from the wire version (RFC 0020 §11).
    final keyboard = await probe.run(_environment);
    if (_ended.isCompleted) return;

    // What the app needs to lay out its first frame: the actual size, and
    // the capabilities of the user's real terminal.
    transport.send(
      buildShellInitFrame(
        size: _terminal.size,
        capabilities: detectTerminalCapabilitiesFromEnvironment(_environment),
        keyboard: keyboard,
      ),
    );
    // Only now may typed input flow: the app discards input that arrives
    // before the handshake, so keys typed during the probe wait until here.
    final typedDuringProbe = probe.finish();
    if (typedDuringProbe.isNotEmpty) {
      _send(InputFrame(Uint8List.fromList(typedDuringProbe)));
    }

    _resizes = _resizeSignals.listen((_) => _send(ResizeFrame(_terminal.size)));
    _frames = transport.incoming.listen(
      _onFrame,
      onError: (Object error) =>
          _end(ShellSessionEnd(ShellSessionEndReason.failed, error: error)),
      onDone: () =>
          _end(const ShellSessionEnd(ShellSessionEndReason.appDisconnected)),
      cancelOnError: true,
    );
  }

  void _onInput(Uint8List bytes) {
    final relayed = _probe!.absorb(bytes);
    if (relayed != null) _send(InputFrame(relayed));
  }

  void _send(RemoteFrame frame) {
    if (_ended.isCompleted) return;
    try {
      transport.send(frame);
    } catch (error) {
      _end(ShellSessionEnd(ShellSessionEndReason.failed, error: error));
    }
  }

  void _onFrame(RemoteFrame frame) {
    if (_ended.isCompleted) return;
    switch (frame) {
      case OutputFrame(:final bytes):
        try {
          _terminal.write(bytes);
        } catch (error) {
          _end(ShellSessionEnd(ShellSessionEndReason.failed, error: error));
        }
      case ByeFrame():
        _end(const ShellSessionEnd(ShellSessionEndReason.appExited));
      default:
        // Every other frame type flows the other way, or belongs to a
        // structured peer. A malformed app must not crash the shell.
        break;
    }
  }
}

/// Probes which keyboard flags the real terminal honours, over the session's
/// one input reader: while it runs, typed bytes are held here instead of
/// being relayed, and the reply is stripped from them.
final class _ShellKeyboardProbe implements TerminalProbeTransport {
  _ShellKeyboardProbe(this._terminal);

  final ShellTerminal _terminal;
  final List<int> _buffer = <int>[];
  var _active = true;

  /// Whether the probe has its reply (the DA1 that brackets it).
  bool get _replyComplete => daReplyEndN(_buffer, 1) >= 0;

  /// Routes one chunk of input. Returns the bytes to relay, or null while
  /// the probe still owns the input.
  Uint8List? absorb(Uint8List bytes) {
    if (!_active) return bytes;
    _buffer.addAll(bytes);
    return null;
  }

  @override
  Future<List<int>> request(String bytes, {required Duration timeout}) async {
    _terminal.write(utf8.encode(bytes));
    final deadline = Stopwatch()..start();
    while (deadline.elapsed < timeout) {
      if (_replyComplete) break;
      await Future<void>.delayed(const Duration(milliseconds: 4));
    }
    return List<int>.unmodifiable(_buffer);
  }

  Future<KeyboardCapabilities?> run(Map<String, String> environment) async {
    final override = environment['FLEURY_KEYBOARD_PROBE'];
    if (override == '0' || override == 'false') return null;
    try {
      final flags = await probeKeyboardFlags(this);
      if (flags == null) return null;
      return KeyboardCapabilities.fromKittyFlags(flags);
    } on Object {
      return null;
    }
  }

  /// Ends the probe and returns what the user typed during it.
  ///
  /// Only the tail past the reply is real input. If no reply landed, all of
  /// it is: a terminal that does not speak the protocol answered nothing.
  List<int> finish() {
    _active = false;
    final tailStart = daReplyEndN(_buffer, 1);
    final tail = tailStart >= 0
        ? _buffer.sublist(tailStart)
        : List<int>.of(_buffer);
    _buffer.clear();
    return tail;
  }
}
