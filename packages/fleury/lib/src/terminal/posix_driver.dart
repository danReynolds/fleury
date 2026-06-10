// POSIX terminal driver: wires the framework's I/O contract to
// `dart:io` stdin/stdout. Owns raw-mode lifecycle, the input byte
// parser, resize detection via SIGWINCH, and emergency cleanup on
// SIGINT / SIGTERM.
//
// Status: ships, but lacks test coverage by design — driver tests need
// a real (or simulated) PTY, and that lives one slice further out.
// The byte-level work is delegated to [InputParser] which IS heavily
// tested.
//
// Windows: not supported in this driver. A WindowsTerminalDriver lives
// behind the same [TerminalDriver] interface in a future slice; the
// console-mode dance is different enough to be its own file.

import 'dart:async';
import 'dart:io';

import '../foundation/geometry.dart';
import 'capabilities.dart';
import 'events.dart';
import 'input_parser.dart';
import 'terminal_driver.dart';
import 'terminal_sequences.dart';

class PosixTerminalDriver implements TerminalDriver, TerminalHandoffDriver {
  PosixTerminalDriver({Stdin? stdinOverride, Stdout? stdoutOverride})
    : _stdin = stdinOverride ?? stdin,
      _stdout = stdoutOverride ?? stdout;

  final Stdin _stdin;
  final Stdout _stdout;

  // Snapshotted once: whether each standard stream is a real TTY. Output
  // governs whether we may emit screen-control sequences; input governs
  // whether raw mode is meaningful (and settable without throwing).
  late final bool _stdinIsTerminal = _stdin.hasTerminal;
  late final bool _stdoutIsTerminal = _stdout.hasTerminal;

  final InputParser _parser = InputParser();
  final StreamController<TuiEvent> _events =
      StreamController<TuiEvent>.broadcast();
  final _ParserSink _sink = _ParserSink();

  StreamSubscription<List<int>>? _stdinSubscription;
  StreamSubscription<ProcessSignal>? _resizeSubscription;
  StreamSubscription<ProcessSignal>? _intSubscription;
  StreamSubscription<ProcessSignal>? _termSubscription;
  StreamSubscription<ProcessSignal>? _tstpSubscription;
  StreamSubscription<ProcessSignal>? _contSubscription;
  Timer? _flushTimer;

  bool _active = false;
  bool _handoffActive = false;
  TerminalMode? _mode;
  bool _wroteEnterSequences = false;
  bool _changedStdin = false;
  bool? _originalLineMode;
  bool? _originalEchoMode;

  @override
  CellSize get size {
    int cols;
    int rows;
    try {
      cols = _stdout.terminalColumns;
      rows = _stdout.terminalLines;
    } on StdoutException {
      // No reportable size — happens under non-interactive PTYs (e.g.
      // `script` invocations without a controlling terminal) and CI
      // runners that haven't negotiated a window size. Fall back to
      // $COLUMNS / $LINES env vars; failing that, the conventional
      // 80x24 default.
      cols = _envInt('COLUMNS') ?? 80;
      rows = _envInt('LINES') ?? 24;
    }
    return CellSize(cols, rows);
  }

  static int? _envInt(String name) {
    final raw = Platform.environment[name];
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  StreamSubscription<ProcessSignal>? _watchSignal(
    ProcessSignal signal,
    void Function(ProcessSignal signal) onSignal,
  ) {
    try {
      return signal.watch().listen(onSignal);
    } on SignalException {
      return null;
    } on UnsupportedError {
      return null;
    }
  }

  @override
  TerminalCapabilities get capabilities =>
      detectTerminalCapabilitiesFromEnvironment(Platform.environment);

  @override
  Stream<TuiEvent> get events => _events.stream;

  @override
  bool get isActive => _active;

  @override
  bool get isInteractive => _stdoutIsTerminal;

  @override
  Future<void> enter(TerminalMode mode) async {
    if (_active) {
      throw StateError('PosixTerminalDriver.enter called on an active driver.');
    }
    _mode = mode;
    _sink.target = _events;

    // Raw mode only makes sense on a terminal stdin; reading lineMode/
    // echoMode throws on a pipe, so guard rather than catch. Piped input
    // (stdin not a terminal, e.g. scripted keystrokes) still streams in
    // via the listener below.
    if (mode.rawInput && _stdinIsTerminal) {
      _originalLineMode = _stdin.lineMode;
      _originalEchoMode = _stdin.echoMode;
      _setRawMode();
      _changedStdin = true;
    }

    // Screen-control sequences only when stdout is a real terminal — writing
    // them into a pipe or file would just corrupt it.
    final enter = _enterSequences(mode);
    if (_stdoutIsTerminal && enter.isNotEmpty) {
      _stdout.write(enter);
      _wroteEnterSequences = true;
    }

    _stdinSubscription = _stdin.listen(
      (bytes) {
        _parser.feed(bytes, _sink);
        _scheduleFlush();
      },
      onError: (Object error, StackTrace stack) {
        _events.addError(error, stack);
      },
      cancelOnError: false,
    );

    _resizeSubscription = _watchSignal(ProcessSignal.sigwinch, (_) {
      _events.add(ResizeEvent(size));
    });

    _intSubscription = _watchSignal(ProcessSignal.sigint, (_) async {
      await restore();
      exit(130); // 128 + SIGINT
    });
    _termSubscription = _watchSignal(ProcessSignal.sigterm, (_) async {
      await restore();
      exit(143); // 128 + SIGTERM
    });

    // Job control: on Ctrl+Z, hand the terminal back to the shell before
    // stopping; on `fg`, re-enter and repaint. SIGCONT is watched for the
    // whole session; SIGTSTP is dropped during the stop and re-armed on
    // resume (so the default stop action can fire).
    _contSubscription = _watchSignal(ProcessSignal.sigcont, (_) => _resume());
    _tstpSubscription = _watchSignal(ProcessSignal.sigtstp, (_) => _suspend());

    _active = true;
  }

  /// Builds the mode-entry escape sequence (alt screen, hide cursor,
  /// bracketed paste, Kitty keyboard, mouse), shared by [enter] and resume.
  String _enterSequences(TerminalMode mode) {
    return buildTerminalEnterSequences(mode);
  }

  /// Builds the mode-exit escape sequence, shared by [restore] and
  /// suspend. Disables mouse modes unconditionally (incl. all-motion
  /// 1003) so none leak back to the shell.
  String _exitSequences(TerminalMode mode) {
    return buildTerminalExitSequences(mode);
  }

  void _setRawMode() {
    try {
      _stdin.lineMode = false;
      _stdin.echoMode = false;
    } on StdinException {
      // ignore — terminal may have detached
    }
  }

  void _restoreCookedMode() {
    try {
      if (_originalLineMode != null) _stdin.lineMode = _originalLineMode!;
    } on StdinException {
      // ignore
    }
    try {
      if (_originalEchoMode != null) _stdin.echoMode = _originalEchoMode!;
    } on StdinException {
      // ignore
    }
  }

  /// SIGTSTP (Ctrl+Z): restore the terminal for the shell, then drop our
  /// handler and re-raise the stop so the process actually suspends.
  Future<void> _suspend() async {
    final mode = _mode;
    if (mode == null) return;
    if (_wroteEnterSequences) _stdout.write(_exitSequences(mode));
    if (_changedStdin) _restoreCookedMode();
    try {
      await _stdout.flush();
    } catch (_) {}
    await _tstpSubscription?.cancel();
    _tstpSubscription = null;
    Process.killPid(pid, ProcessSignal.sigtstp);
  }

  @override
  Future<T> runWithTerminalHandoff<T>(FutureOr<T> Function() operation) async {
    final mode = _mode;
    if (!_active || mode == null) return await operation();

    _handoffActive = true;
    if (_wroteEnterSequences) _stdout.write(_exitSequences(mode));
    if (_changedStdin) _restoreCookedMode();
    try {
      await _stdout.flush();
    } catch (_) {}

    try {
      return await operation();
    } finally {
      if (_active && identical(_mode, mode)) {
        if (_changedStdin) _setRawMode();
        if (_wroteEnterSequences) _stdout.write(_enterSequences(mode));
        try {
          await _stdout.flush();
        } catch (_) {}
        _handoffActive = false;
        _events.add(ResizeEvent(size));
      } else {
        _handoffActive = false;
      }
    }
  }

  /// SIGCONT (`fg`): re-enter the configured mode, re-arm SIGTSTP, and
  /// force a full repaint (the window may have resized while stopped).
  void _resume() {
    final mode = _mode;
    if (mode == null || !_active) return;
    if (_changedStdin) _setRawMode();
    if (_wroteEnterSequences) _stdout.write(_enterSequences(mode));
    _tstpSubscription ??= _watchSignal(
      ProcessSignal.sigtstp,
      (_) => _suspend(),
    );
    _events.add(ResizeEvent(size));
  }

  @override
  Future<void> restore() async {
    if (!_active && !_wroteEnterSequences && !_changedStdin) return;

    _handoffActive = false;
    _flushTimer?.cancel();
    _flushTimer = null;

    await _stdinSubscription?.cancel();
    _stdinSubscription = null;
    await _resizeSubscription?.cancel();
    _resizeSubscription = null;
    await _intSubscription?.cancel();
    _intSubscription = null;
    await _termSubscription?.cancel();
    _termSubscription = null;
    await _tstpSubscription?.cancel();
    _tstpSubscription = null;
    await _contSubscription?.cancel();
    _contSubscription = null;

    if (_changedStdin) {
      // Best-effort restoration of stdin modes. If stdin has been
      // closed or detached (e.g. the parent disconnected the TTY
      // between enter() and restore()), the setters can throw — handled
      // inside _restoreCookedMode. The important cleanup is the ANSI
      // cursor / alt-screen sequences below.
      _restoreCookedMode();
      _changedStdin = false;
    }

    if (_wroteEnterSequences) {
      // Disable input modes first so no stray sequences leak as the
      // terminal returns to the shell.
      _stdout.write(_exitSequences(_mode ?? TerminalMode.interactive));
      _wroteEnterSequences = false;
    }

    // Critical: flush stdout. Without this the cleanup sequences sit in
    // dart:io's buffer and never reach the terminal, leaving the user
    // in alt-screen / cursor-hidden state when the process exits.
    try {
      await _stdout.flush();
    } catch (_) {
      // Flush can throw if the stream is already closed; nothing we
      // can do at that point.
    }

    _active = false;
    _mode = null;
  }

  @override
  void write(String data) {
    if (_handoffActive) return;
    _stdout.write(data);
  }

  /// Schedules a flush of the parser. ESC-disambiguation needs a beat
  /// of idle time to decide a lone ESC isn't the start of a CSI
  /// sequence.
  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 30), () {
      _parser.flush(_sink);
    });
  }
}

class _ParserSink implements TuiEventSink {
  StreamController<TuiEvent>? target;

  @override
  void add(TuiEvent event) {
    target?.add(event);
  }
}
