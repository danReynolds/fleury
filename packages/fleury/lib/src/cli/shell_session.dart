// `fleury shell`'s side of one attached app: the terminal the shell takes
// over for it, and the relay that moves bytes between the two.
//
// While an app is attached, the shell's terminal is the app's terminal, so it
// is set up exactly as the app's own native driver would set it up — with the
// same primitives: raw input through the native termios controller (no
// ISIG/ICANON/ECHO/IXON, so Ctrl+C and Ctrl+Z are bytes the app decides
// about, not signals that stop or kill the shell), the shared screen-mode
// sequences, and the cancellable native input borrow. The input the terminal
// reports — mouse, pastes, focus changes, the keyboard tier — is the app's
// to choose: its answer to the shell's INIT declares it, and the shell turns
// exactly that on. When the session ends, for any reason, the terminal is
// handed back exactly as it was found.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
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

/// The modes `fleury shell` takes its terminal over in, before the app has
/// said what input it reads: the full-screen mode the app's own native driver
/// enters, with the disambiguated keyboard tier the shell probes, and no
/// input reporting yet.
///
/// Flag 2 of that tier is what lets a binding behind the relay fire once per
/// press rather than once per auto-repeat, as it does in a local session
/// (RFC 0020 §8.1). The shell stops short of the lifecycle tier because
/// negotiating it takes the transactional fallback only the native driver
/// runs: a terminal that honours flag 8 without flag 16 sends no text at all.
/// The INIT declares what the terminal actually confirmed.
///
/// Mouse tracking, bracketed paste, and focus reports are the app's to ask
/// for: they come on once its answer declares them ([shellTerminalModeFor]).
const TerminalMode shellTerminalMode = TerminalMode.fullScreen(
  keyboardProtocol: KeyboardProtocolMode.disambiguated,
  bracketedPaste: false,
  focusReporting: false,
);

/// The modes the shell's terminal is in for an app that reads [input]: the
/// shell's screen ([shellTerminalMode]) with the app's mouse tracking,
/// bracketed paste, and focus reports, and the keyboard tier the shell
/// negotiated — or no keyboard flags, for an app that reads legacy keys, as
/// its own native driver would push none.
TerminalMode shellTerminalModeFor(TerminalInputModes input) =>
    terminalModeWithInput(
      shellTerminalMode,
      TerminalInputModes(
        mouse: input.mouse,
        mouseMotion: input.mouseMotion,
        bracketedPaste: input.bracketedPaste,
        focusReporting: input.focusReporting,
        keyboardProtocol: input.keyboardProtocol == KeyboardProtocolMode.legacy
            ? KeyboardProtocolMode.legacy
            : shellTerminalMode.keyboardProtocol,
      ),
    );

/// What the shell writes to its terminal, held in [shellTerminalMode], once
/// the attached app declares [input]: the input reporting the app reads, and
/// for an app that reads legacy keys, the pop of the keyboard flags the shell
/// pushed to probe with — on the screen it pushed them to (RFC 0020 §8.1).
String buildShellInputSequences(TerminalInputModes input) {
  final mode = shellTerminalModeFor(input);
  final dropKeyboard = shellTerminalMode.kittyKeyboard && !mode.kittyKeyboard;
  return '${dropKeyboard ? popKittyKeyboardFlags : ''}'
      '${buildTerminalInputReportingSequences(mode)}';
}

/// The terminal `fleury shell` draws an attached app in.
abstract interface class ShellTerminal {
  /// The terminal's size in cells.
  CellSize get size;

  /// Takes the terminal over for an app: raw input, [shellTerminalMode]'s
  /// screen modes, and a reader that passes every byte typed to [onInput].
  /// Input typed before the first acquisition, while no app was attached,
  /// is discarded: it was addressed to no app.
  ///
  /// [onGone] runs at most once, if the terminal itself goes away: its input
  /// ends or fails, which in raw mode means the terminal hung up. A failed
  /// acquisition may have changed part of the terminal; [release] still
  /// hands it back.
  Future<void> acquire({
    required void Function(Uint8List bytes) onInput,
    required void Function() onGone,
  });

  /// Turns on the input the attached app declared it reads, moving the
  /// terminal from [shellTerminalMode] to [shellTerminalModeFor] [input] with
  /// [buildShellInputSequences]. Called once per acquisition, when the app
  /// answers the handshake; [release] undoes it with the rest. A terminal
  /// that has gone away reports it through [acquire]'s `onGone` instead of
  /// throwing.
  void enterInput(TerminalInputModes input);

  /// Writes app output, or a terminal query, to the screen. A terminal that
  /// has gone away reports it through [acquire]'s `onGone` instead of
  /// throwing.
  void write(List<int> bytes);

  /// Hands the terminal back exactly as [acquire] found it, undoing whatever
  /// part of it is still held, the app's input included. Idempotent. Throws
  /// the first failure after attempting every step.
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
  bool _acquired = false;
  bool _rawModeOwned = false;
  bool _screenOwned = false;

  /// The modes the screen is held in while [_screenOwned]: [shellTerminalMode]
  /// from [acquire], then the app's ([enterInput]). Release leaves exactly
  /// these.
  TerminalMode _mode = shellTerminalMode;
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
    if (!_acquired) {
      _acquired = true;
      // Keys typed while the shell waited went to no app. Replayed into this
      // one, a stale Enter would press whatever it focuses first.
      _discardPendingInput();
    }
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
    _mode = shellTerminalMode;
    write(utf8.encode(buildTerminalEnterSequences(shellTerminalMode)));
    final input = _input = PosixInputLease(
      onBytes: onInput,
      onDone: terminalGone,
      onError: (_, _) => terminalGone(),
    );
    await input.start();
  }

  @override
  void enterInput(TerminalInputModes input) {
    if (!_screenOwned) return;
    // Own the obligation before the change, as [acquire] does: whatever part
    // of the write reaches the terminal, release turns off with the rest.
    _mode = shellTerminalModeFor(input);
    write(utf8.encode(buildShellInputSequences(input)));
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
    // The screen first. Leaving it stops the terminal's mouse, focus and
    // paste reports while the reader still drains them, and pops the keyboard
    // flags on the screen they were pushed to (RFC 0020 §8.1).
    if (_screenOwned) {
      _screenOwned = false;
      try {
        _output.write(buildTerminalExitSequences(_mode));
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

/// Discards input the terminal received but no one has read yet
/// (`tcflush(0, TCIFLUSH)`). Best-effort: a terminal that cannot flush keeps
/// its typeahead.
void _discardPendingInput() {
  try {
    _tcflush(0, Platform.isMacOS ? 1 : 0); // TCIFLUSH: 1 on Darwin, 0 on Linux
  } on Object {
    // No flush on this platform's libc; typeahead reaches the app instead.
  }
}

final int Function(int fd, int queue) _tcflush = DynamicLibrary.process()
    .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
      'tcflush',
    );

/// Why a [ShellSession] ended.
enum ShellSessionEndReason {
  /// The app said goodbye: it exited.
  appExited,

  /// The app's connection closed without a goodbye: it crashed, or was
  /// stopped or killed (an IDE's Stop and Restart).
  appDisconnected,

  /// The app never attached: it answered the shell's INIT at another version
  /// of the shell protocol (it and the shell come from different Fleury
  /// builds), answered with something else, or disconnected before
  /// answering. [ShellSessionEnd.error] is a [ShellHandshakeException] that
  /// says which.
  handshakeFailed,

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

  /// Why the session failed, for [ShellSessionEndReason.failed] and
  /// [ShellSessionEndReason.handshakeFailed].
  final Object? error;

  /// Why handing the terminal back failed, if it did.
  final Object? restoreError;
}

/// What an app did instead of answering the shell's INIT at
/// [shellProtocolVersion], worded to finish "the app could not attach: ".
final class ShellHandshakeException implements Exception {
  const ShellHandshakeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The remedy for a shell and an app from different Fleury builds: the
/// shell an app's package resolves is the one built with the app's Fleury.
const String _matchingShell =
    'run the shell from the app\'s package (`dart run fleury shell`) so both '
    'use the same Fleury';

/// One attached app: [run] takes the terminal over, relays until the app or
/// the shell ends the session, then hands the terminal back and closes
/// [transport].
///
/// The app attaches by answering the shell's INIT (shell protocol
/// [shellProtocolVersion]) with its own, which declares the input it reads;
/// the shell turns that on in its terminal and only then shows what the app
/// draws. An app that answers at another version, or not at all, ends the
/// session as [ShellSessionEndReason.handshakeFailed].
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

  /// Whether the app has answered the shell's INIT at this shell's protocol
  /// version. Until then nothing it sends reaches the screen: only the
  /// answer says it speaks this protocol at all.
  var _attached = false;

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

  void _turnAway(String why) => _end(
    ShellSessionEnd(
      ShellSessionEndReason.handshakeFailed,
      error: ShellHandshakeException(why),
    ),
  );

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
      // A socket error is the app going away: Linux resets the connection
      // when a killed app leaves input unread, as an IDE's Stop often does.
      // Anything else (a malformed frame, an overflowing send) is a failure.
      onError: (Object error) => error is SocketException
          ? _appGone()
          : _end(ShellSessionEnd(ShellSessionEndReason.failed, error: error)),
      onDone: _appGone,
      cancelOnError: true,
    );
  }

  /// The app's connection closed without a goodbye.
  void _appGone() {
    if (_attached) {
      _end(const ShellSessionEnd(ShellSessionEndReason.appDisconnected));
      return;
    }
    // An app that cannot decode this shell's INIT, such as one from another
    // Fleury build, rejects it and hangs up without a word.
    _turnAway(
      'it disconnected before answering the shell\'s handshake. If it was '
      'built with another Fleury than this shell, $_matchingShell',
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
    if (!_attached) {
      _onHandshake(frame);
      return;
    }
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

  /// The app's first frame: its answer to the shell's INIT, or a goodbye.
  /// Anything else means it does not speak this shell's protocol, and is
  /// turned away before any of it reaches the screen.
  void _onHandshake(RemoteFrame frame) {
    switch (frame) {
      case InitFrame(protocol: RemoteWireProtocol.structured):
        _turnAway(
          'it answered with the structured wire protocol '
          '(v${frame.protocolVersion}), not the `fleury shell` protocol',
        );
      case InitFrame(:final protocolVersion)
          when protocolVersion != shellProtocolVersion:
        _turnAway(
          'it speaks shell protocol v$protocolVersion, and this shell speaks '
          'v$shellProtocolVersion. To match them, $_matchingShell',
        );
      case InitFrame(:final terminalInput?):
        _attached = true;
        try {
          _terminal.enterInput(terminalInput);
        } catch (error) {
          _end(ShellSessionEnd(ShellSessionEndReason.failed, error: error));
        }
      case InitFrame():
        _turnAway('its answer declared no terminal input');
      case ByeFrame():
        _end(const ShellSessionEnd(ShellSessionEndReason.appExited));
      default:
        _turnAway(
          'it sent ${frame.runtimeType} before answering the shell\'s '
          'handshake',
        );
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
