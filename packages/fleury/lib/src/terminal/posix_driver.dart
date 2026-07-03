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
import '../input/events.dart';
import 'input_parser.dart';
import '../runtime/remote_surface_sink.dart';
import 'terminal_driver.dart';
import 'terminal_probe.dart';
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

  // Image-protocol probe state. While [_probing] is true the stdin listener
  // diverts bytes into [_probeBuffer] (the terminal's reply to our query)
  // instead of the input parser. [_imageProtocolOverride], once a probe
  // confirms a native protocol the environment didn't advertise (e.g. Kitty
  // graphics under Warp), upgrades [capabilities].
  bool _probing = false;
  List<int> _probeBuffer = <int>[];
  ImageProtocol? _imageProtocolOverride;
  // Set once the ambiguous-width probe measures how the terminal sizes
  // ambiguous glyphs; a confirmed `narrow` lets the renderer drop the
  // defensive per-cell repositioning [capabilities] otherwise assumes.
  AmbiguousCharWidth? _ambiguousCharWidthOverride;
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
  TerminalCapabilities get capabilities {
    final base = detectTerminalCapabilitiesFromEnvironment(
      Platform.environment,
    );
    final override = _imageProtocolOverride;
    final merged =
        override == null ? base : base.copyWith(imageProtocol: override);
    final width = _ambiguousCharWidthOverride;
    return width == null ? merged : merged.copyWith(ambiguousCharWidth: width);
  }

  @override
  Stream<TuiEvent> get events => _events.stream;

  @override
  bool get isActive => _active;

  @override
  bool get isInteractive => _stdoutIsTerminal;

  @override
  RemoteSurfaceSink? get surfaceSink => null; // byte presentation only

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
        // During the startup image-protocol probe, the terminal's reply is for
        // us, not the app — divert it to the probe buffer so it isn't parsed
        // as keystrokes (and so a non-supporting terminal's reply is consumed
        // rather than leaked as garbage).
        if (_probing) {
          _probeBuffer.addAll(bytes);
          return;
        }
        _parser.feed(bytes, _sink);
        _scheduleFlush();
      },
      onError: (Object error, StackTrace stack) {
        _events.addError(error, stack);
      },
      cancelOnError: false,
    );

    // Actively confirm a native image protocol the environment didn't name
    // (e.g. Kitty graphics under Warp, which masquerades as xterm-256color).
    // Runs before the app renders so the first frame already uses the right
    // protocol; falls back silently when nothing replies.
    await _maybeProbeImageProtocol();
    await _maybeProbeAmbiguousWidth();

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

  /// When the environment doesn't already name a native image protocol, ask
  /// the terminal directly (a short, bounded query/response). A confirmed reply
  /// upgrades [capabilities] so [Image] widgets emit real pixels instead of
  /// cell art. Skipped unless we own a real terminal in raw mode (so the reply
  /// arrives byte-for-byte, not line-buffered) and the environment is
  /// inconclusive; any failure leaves the conservative fallback in place.
  Future<void> _maybeProbeImageProtocol() async {
    if (!_stdoutIsTerminal || !_changedStdin) return;
    // Escape hatch: `FLEURY_IMAGE_PROBE=0` disables the startup query for users
    // on a terminal where it misbehaves (the conservative env fallback stands).
    final flag = Platform.environment['FLEURY_IMAGE_PROBE'];
    if (flag == '0' || flag == 'false') return;
    if (detectImageProtocolFromEnvironment(Platform.environment) !=
        ImageProtocol.halfBlock) {
      return;
    }
    try {
      final detected = await probeImageProtocol(_DriverProbeTransport(this));
      if (detected != null) _imageProtocolOverride = detected;
    } on Object {
      // Probe failed (no terminal reply, write error, …): keep the fallback.
    } finally {
      _replayPostProbeInput();
    }
  }

  /// Measures how the terminal sizes ambiguous-width glyphs so the renderer can
  /// drop its defensive per-cell repositioning on terminals that draw them one
  /// column wide (the common case). Same terminal guards as the image probe;
  /// runs on the alternate screen and any failure leaves the safe `wide`
  /// default in place.
  Future<void> _maybeProbeAmbiguousWidth() async {
    if (!_stdoutIsTerminal || !_changedStdin) return;
    // Escape hatch: skip the probe and set the result directly.
    //   FLEURY_AMBIGUOUS_WIDTH=narrow|wide — force this rendering.
    //   FLEURY_AMBIGUOUS_WIDTH=0|off|false — skip; keep the conservative `wide`.
    final flag = Platform.environment['FLEURY_AMBIGUOUS_WIDTH']
        ?.toLowerCase()
        .trim();
    if (flag == 'narrow') {
      _ambiguousCharWidthOverride = AmbiguousCharWidth.narrow;
      return;
    }
    if (flag == 'wide') {
      _ambiguousCharWidthOverride = AmbiguousCharWidth.wide;
      return;
    }
    if (flag == '0' || flag == 'off' || flag == 'false') return;
    // ASCII-only output emits no ambiguous glyphs, so nothing needs sizing —
    // skip the round trip and the stray probe glyph.
    if (detectGlyphTierFromEnvironment(Platform.environment) ==
        GlyphTier.ascii) {
      return;
    }
    try {
      final detected = await probeAmbiguousWidth(_DriverProbeTransport(this));
      if (detected != null) _ambiguousCharWidthOverride = detected;
    } on Object {
      // Probe failed (no terminal reply, write error, …): keep the `wide`
      // default so ambiguous-wide terminals never garble.
    } finally {
      _replayPostProbeInput();
    }
  }

  /// Replays real keystrokes that arrived during the probe window. Everything
  /// the terminal captured after its Device-Attributes reply is user input (the
  /// reply is the last thing the terminal sends in response), so feed that tail
  /// to the parser instead of dropping it. Bytes at/before the reply are the
  /// terminal's own response and stay consumed; if no DA reply landed (timeout)
  /// nothing is replayed, since the buffer may hold a partial response.
  void _replayPostProbeInput() {
    final buf = _probeBuffer;
    _probeBuffer = <int>[];
    if (buf.isEmpty) return;
    final tailStart = _daReplyEnd(buf);
    if (tailStart < 0 || tailStart >= buf.length) return;
    _parser.feed(buf.sublist(tailStart), _sink);
    _scheduleFlush();
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

/// Probe transport over a [PosixTerminalDriver]'s live stdin/stdout. Writes the
/// query, then waits for the reply that the driver's stdin listener diverts
/// into its probe buffer. Because the query appends a Device Attributes request
/// (which every terminal answers), it stops as soon as that reply lands instead
/// of always blocking for the full timeout.
class _DriverProbeTransport implements TerminalProbeTransport {
  _DriverProbeTransport(this._driver);

  final PosixTerminalDriver _driver;

  @override
  Future<List<int>> request(String bytes, {required Duration timeout}) async {
    _driver._probing = true;
    _driver._probeBuffer = <int>[];
    try {
      _driver._stdout.write(bytes);
      await _driver._stdout.flush();
      final deadline = Stopwatch()..start();
      while (deadline.elapsed < timeout) {
        if (_looksComplete(_driver._probeBuffer)) break;
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
      return List<int>.unmodifiable(_driver._probeBuffer);
    } finally {
      _driver._probing = false;
    }
  }

  /// True once the buffer holds a Device Attributes reply — the terminal has
  /// processed our request, so any graphics reply is already in.
  static bool _looksComplete(List<int> buf) => _daReplyEnd(buf) >= 0;
}

/// Index just past a Device-Attributes reply's `c` terminator in [buf], or -1
/// if none is present yet. A DA reply is `ESC [` then CSI parameter/intermediate
/// bytes (0x20–0x3F) then the final byte `c` (0x63). Requiring valid CSI bytes
/// before the `c` stops a stray 0x63 in unrelated content (or a user keystroke
/// that leaked in) from being mistaken for the terminator. Used both to end the
/// probe wait and to find where real post-probe input begins.
int _daReplyEnd(List<int> buf) {
  for (var i = 0; i + 1 < buf.length; i++) {
    if (buf[i] != 0x1B || buf[i + 1] != 0x5B) continue; // ESC [
    var j = i + 2;
    while (j < buf.length && buf[j] >= 0x20 && buf[j] <= 0x3F) {
      j++; // CSI parameter / intermediate bytes
    }
    if (j >= buf.length) return -1; // final byte not arrived yet
    if (buf[j] == 0x63) return j + 1; // 'c' final byte → Device Attributes
    i = j; // some other CSI final byte — keep scanning past it
  }
  return -1;
}
