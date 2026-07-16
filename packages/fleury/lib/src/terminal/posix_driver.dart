// POSIX terminal driver: wires the framework's I/O contract to
// `dart:io` stdin/stdout. Owns raw-mode lifecycle, the input byte
// parser, resize detection via SIGWINCH, and signal delivery: SIGINT /
// SIGTERM become [SignalEvent]s so the app owns its shutdown, backed by
// a grace deadline that force-terminates a hung app (restore → exit).
//
// Lifecycle behavior is covered at two levels: deterministic fake-stdio tests
// pin mode ownership, EOF, signals, suspend, and handoff invariants; the PTY
// integration tier proves actual terminal entry/restoration bytes.
//
// Windows uses its own console-mode driver behind the same [TerminalDriver]
// interface; the console-mode dance is different enough to stay separate.

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import '../foundation/geometry.dart';
import 'capabilities.dart';
import '../input/events.dart';
import 'input_parser.dart';
import '../runtime/remote_surface_sink.dart';
import 'terminal_driver.dart';
import 'terminal_probe.dart';
import 'terminal_sequences.dart';

/// Native POSIX terminal lifecycle and byte-input driver.
///
/// Interactive Ctrl+Z is handled orderly: Fleury restores the terminal,
/// self-stops, then re-enters after `fg`. Externally sending SIGTSTP is not a
/// supported lifecycle path because Dart cannot safely watch SIGTSTP/SIGCONT;
/// it may stop the process before Fleury can restore terminal modes.
class PosixTerminalDriver
    with TerminalAttentionSequences
    implements TerminalDriver, TerminalHandoffDriver {
  PosixTerminalDriver({
    Stdin? stdinOverride,
    Stdout? stdoutOverride,
    this.signalGrace = const Duration(seconds: 5),
    @visibleForTesting void Function(int exitCode)? forceExitOverride,
    @visibleForTesting bool Function()? selfStopOverride,
    @visibleForTesting PosixTerminalModeController? terminalModeController,
  }) : _stdin = stdinOverride ?? stdin,
       _stdout = stdoutOverride ?? stdout,
       _forceExitOverride = forceExitOverride,
       _selfStopOverride = selfStopOverride,
       _terminalModeController =
           terminalModeController ?? NativePosixTerminalModeController() {
    _events = StreamController<TuiEvent>.broadcast(
      onListen: _deliverPendingSignalToNewListener,
    );
    _sink
      ..target = _events
      ..intercept = _interceptParsedEvent;
  }

  final Stdin _stdin;
  final Stdout _stdout;

  /// How long a delivered [SignalEvent] may remain unresolved before the
  /// driver force-terminates (restore → `exit(128+n)`). The ceiling on
  /// app-owned shutdown: a supervisor's SIGTERM must always end the
  /// process even when the app hangs mid-teardown.
  final Duration signalGrace;

  /// Test seam: replaces the `exit()` call in the force path so grace
  /// behavior is assertable without killing the test process.
  final void Function(int exitCode)? _forceExitOverride;

  /// Test seam: replaces the SIGSTOP self-stop (`Process.killPid`) so
  /// [_suspend]'s gating/single-flight is assertable without actually
  /// stopping the test process. Returns whether the stop "took" — a test can
  /// return false to exercise the failed-stop un-gate path.
  final bool Function()? _selfStopOverride;

  /// Owns the complete POSIX termios snapshot used by raw mode. Dart's
  /// `Stdin.lineMode` / `echoMode` API only toggles ICANON/ECHO and leaves ISIG
  /// enabled, so Ctrl+Z is consumed by the kernel as SIGTSTP before Fleury can
  /// restore the screen. The native controller uses cfmakeraw, making Ctrl+Z a
  /// parsed byte that can take the orderly restore -> stop -> resume path.
  final PosixTerminalModeController _terminalModeController;

  // Snapshotted once: whether each standard stream is a real TTY. Output
  // governs whether we may emit screen-control sequences; input governs
  // whether raw mode is meaningful (and settable without throwing).
  late final bool _stdinIsTerminal = _stdin.hasTerminal;
  late final bool _stdoutIsTerminal = _stdout.hasTerminal;

  final InputParser _parser = InputParser();
  late final StreamController<TuiEvent> _events;
  final _ParserSink _sink = _ParserSink();

  StreamSubscription<List<int>>? _stdinSubscription;
  StreamSubscription<ProcessSignal>? _resizeSubscription;
  StreamSubscription<ProcessSignal>? _intSubscription;
  StreamSubscription<ProcessSignal>? _termSubscription;
  Timer? _flushTimer;
  Timer? _graceTimer;
  AppSignal? _pendingSignal;
  bool _pendingSignalDelivered = false;

  bool _active = false;
  bool _entering = false;
  bool _restoring = false;
  int _lifecycleGeneration = 0;
  bool _handoffActive = false;
  Future<void> _handoffTail = Future<void>.value();
  // True from the moment Ctrl+Z restoration begins until foregrounding
  // continues after SIGSTOP and re-enters our mode. Like [_handoffActive], it
  // gates frame [write]s while the shell owns the terminal and single-flights
  // [_suspend].
  bool _suspended = false;
  TerminalMode? _mode;

  // Image-protocol probe state. While [_probing] is true the stdin listener
  // diverts bytes into [_probeBuffer] (the terminal's reply to our query)
  // instead of the input parser. [_imageProtocolOverride], once a probe
  // confirms a native protocol the environment didn't advertise (e.g. Kitty
  // graphics under Warp), upgrades [capabilities].
  bool _probing = false;
  List<int> _probeBuffer = <int>[];
  // Late-reply drain: a probe that timed out may still get its reply on a slow
  // link (SSH). While draining, stdin keeps diverting into [_probeBuffer] —
  // instead of being parsed as keystrokes — until the DA terminator lands
  // (then real input after it replays) or [lateProbeGrace] expires. Without
  // this, a Kitty/DA reply arriving after the probe window types garbage
  // (`Gi=31,...`) into the focused widget.
  bool _drainingLateProbe = false;
  Timer? _lateProbeTimer;
  @visibleForTesting
  static Duration lateProbeGrace = const Duration(milliseconds: 250);
  // A real probe reply is a few bytes; cap the drain buffer so a terminal
  // spraying without a DA terminator can't grow it (and the per-batch rescan)
  // for the whole grace — give up early instead.
  static const _maxProbeBufferBytes = 4096;
  ImageProtocol? _imageProtocolOverride;
  // Set once the ambiguous-width probe measures how the terminal sizes
  // ambiguous glyphs; a confirmed `narrow` lets the renderer drop the
  // defensive per-cell repositioning [capabilities] otherwise assumes.
  AmbiguousCharWidth? _ambiguousCharWidthOverride;
  bool _wroteEnterSequences = false;
  bool _changedStdin = false;
  bool _nativeRawMode = false;
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

  /// 128 + signal number (SIGINT=2, SIGTERM=15): the conventional
  /// death-by-signal exit codes.
  static int _signalExitCode(AppSignal signal) => switch (signal) {
    AppSignal.interrupt => 130,
    AppSignal.terminate => 143,
  };

  /// Last resort: restore the terminal and end the process with the
  /// conventional code. Used when the app ignores a signal past
  /// [signalGrace] or the user sends the same signal twice.
  void _forceExit(AppSignal signal) {
    final code = _signalExitCode(signal);
    final force = _forceExitOverride;
    unawaited(
      restore().whenComplete(() {
        if (force != null) {
          force(code);
        } else {
          exit(code);
        }
      }),
    );
  }

  /// Delivers [signal] to the app as a [SignalEvent] and arms the grace
  /// deadline: an app that neither exits nor finishes its claimed
  /// shutdown within [signalGrace] is force-terminated (restore →
  /// `exit(128+n)`), so a supervisor's SIGTERM always ends the process.
  /// A second delivery of the SAME pending signal forces immediately —
  /// the second Ctrl+C / `kill` is the user overruling a slow shutdown.
  ///
  /// On the orderly path the app exits, `runApp`'s cleanup calls
  /// [restore], and [restore] disarms the deadline.
  @visibleForTesting
  void deliverSignal(AppSignal signal) {
    // Teardown is already the terminal condition. A watcher callback queued
    // just before cancellation must not re-arm the grace timer or publish into
    // an event stream whose owner is going away.
    if (_restoring) return;
    if (_pendingSignal == signal) {
      // During enter() there is not yet an app event listener to own shutdown.
      // Keep the latest signal pending instead of racing an asynchronous
      // restore against the still-running terminal handshake. The ordinary
      // second-signal force contract begins once enter() has completed.
      if (_entering && !_active) {
        _graceTimer?.cancel();
        _graceTimer = Timer(signalGrace, () => _forceExit(signal));
        return;
      }
      _forceExit(signal);
      return;
    }
    _pendingSignal = signal;
    _pendingSignalDelivered = false;
    _emitPendingSignalIfListened();
    _graceTimer?.cancel();
    _graceTimer = Timer(signalGrace, () => _forceExit(signal));
  }

  void _emitPendingSignalIfListened() {
    final signal = _pendingSignal;
    if (signal == null ||
        _pendingSignalDelivered ||
        !_events.hasListener ||
        _events.isClosed) {
      return;
    }
    _pendingSignalDelivered = true;
    _events.add(SignalEvent(signal));
  }

  /// Replays a signal received during enter() to runApp's first listener.
  ///
  /// The controller is broadcast, so adding synchronously from `onListen`
  /// risks firing before the first subscription is fully installed. One
  /// microtask preserves the signal without that ordering ambiguity.
  void _deliverPendingSignalToNewListener() {
    if (_pendingSignal == null || _pendingSignalDelivered) return;
    scheduleMicrotask(_emitPendingSignalIfListened);
  }

  @override
  TerminalCapabilities get capabilities {
    final environment = Platform.environment;
    final base = detectTerminalCapabilitiesFromEnvironment(environment);
    final override = _imageProtocolOverride;
    final merged = override == null
        ? base
        : base.copyWith(
            imageProtocol: resolveImageProtocolForEnvironment(
              override,
              environment,
            ),
          );
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
    _restoring = false;
    _entering = true;
    final enterGeneration = ++_lifecycleGeneration;
    _mode = mode;
    _sink.target = _events;

    // Arm process-termination signals BEFORE the first terminal mutation. The
    // startup probes below can take up to ~300ms; installing these afterward
    // left a reproducible window where SIGTERM killed the process after the alt
    // screen was entered but before any cleanup handler existed. A signal that
    // lands before runApp subscribes is retained and replayed by
    // [_deliverPendingSignalToNewListener].
    _intSubscription = _watchSignal(
      ProcessSignal.sigint,
      (_) => deliverSignal(AppSignal.interrupt),
    );
    _termSubscription = _watchSignal(
      ProcessSignal.sigterm,
      (_) => deliverSignal(AppSignal.terminate),
    );

    // Raw mode only makes sense on a terminal stdin; reading lineMode/
    // echoMode throws on a pipe, so guard rather than catch. Piped input
    // (stdin not a terminal, e.g. scripted keystrokes) still streams in
    // via the listener below.
    if (mode.rawInput && _stdinIsTerminal) {
      _nativeRawMode = _terminalModeController.enableRawMode();
      if (!_nativeRawMode) {
        _originalLineMode = _stdin.lineMode;
        _originalEchoMode = _stdin.echoMode;
        _setDartRawMode();
      }
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
        if (_drainingLateProbe) {
          // A probe timed out; its reply may still be arriving. Keep diverting
          // until the DA terminator lands (then replay real input after it),
          // rather than parsing the reply as keystrokes.
          _probeBuffer.addAll(bytes);
          if (_daReplyEnd(_probeBuffer) >= 0) {
            _finishLateProbeDrain();
          } else if (_probeBuffer.length > _maxProbeBufferBytes) {
            // A terminal spraying without a DA terminator: a real reply is
            // tiny, so give up now rather than grow the buffer (and rescan it)
            // for the full grace. Nothing real is lost — a genuine reply would
            // have terminated far under this bound.
            _giveUpLateProbeDrain();
          }
          return;
        }
        _parser.feed(bytes, _sink);
        _scheduleFlush();
      },
      onError: (Object error, StackTrace stack) {
        if (!_events.isClosed) _events.addError(error, stack);
      },
      onDone: () {
        // stdin EOF / PTY disconnect is the end of a local terminal session.
        // Closing the driver event stream lets runApp's onDone path exit and
        // restore instead of waiting forever on an input source that vanished.
        _flushTimer?.cancel();
        _flushTimer = null;
        _parser.finish(_sink);
        if (!_events.isClosed) unawaited(_events.close());
      },
      cancelOnError: false,
    );

    // Actively confirm a native image protocol the environment didn't name
    // (e.g. Kitty graphics under Warp, which masquerades as xterm-256color).
    // Runs before the app renders so the first frame already uses the right
    // protocol; falls back silently when nothing replies.
    await _maybeProbeImageProtocol();
    await _maybeProbeAmbiguousWidth(mode.alternateScreen);

    // A concurrent force-restore can complete while a bounded startup probe is
    // awaiting its reply. Never reactivate a driver whose lifecycle moved on.
    if (_restoring || enterGeneration != _lifecycleGeneration) return;

    _resizeSubscription = _watchSignal(ProcessSignal.sigwinch, (_) {
      if (!_events.isClosed) _events.add(ResizeEvent(size));
    });

    _active = true;
    _entering = false;
    _emitPendingSignalIfListened();
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
    // A raw query is not a reliable statement about the host terminal through
    // a multiplexer, and an accepted reply must not upgrade the conservative
    // multiplexer fallback.
    if (detectTerminalMultiplexerFromEnvironment(Platform.environment)) return;
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
  /// column wide (the common case). Same terminal guards as the image probe,
  /// plus an alternate-screen gate: the probe paints a scratch glyph at the home
  /// cell (then erases it) — invisible on the alt buffer, but under an
  /// `alternateScreen: false` mode it would land on the user's real screen and
  /// scrollback. So it runs only when [onAlternateScreen] is true; the safety is
  /// now enforced by this gate rather than being a consequence of call ordering.
  /// Any failure leaves the safe `wide` default in place.
  Future<void> _maybeProbeAmbiguousWidth(bool onAlternateScreen) async {
    if (!_stdoutIsTerminal || !_changedStdin) return;
    if (!onAlternateScreen) return;
    final env = Platform.environment;
    // An explicit FLEURY_AMBIGUOUS_WIDTH=narrow|wide is already reflected in the
    // env-derived base capabilities (detectAmbiguousCharWidthFromEnvironment),
    // so there is nothing to measure. FLEURY_AMBIGUOUS_WIDTH=0|off|false
    // disables the probe and keeps the conservative `wide` default.
    if (detectAmbiguousCharWidthFromEnvironment(env) != null) return;
    final flag = env['FLEURY_AMBIGUOUS_WIDTH']?.toLowerCase().trim();
    if (flag == '0' || flag == 'off' || flag == 'false') return;
    // ASCII-only output emits no ambiguous glyphs, so nothing needs sizing —
    // skip the round trip and the stray probe glyph.
    if (detectGlyphTierFromEnvironment(env) == GlyphTier.ascii) return;
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
    final tailStart = _daReplyEnd(_probeBuffer);
    if (tailStart >= 0) {
      // The DA reply already landed within the probe window — everything after
      // it is real input; feed that tail to the parser.
      final buf = _probeBuffer;
      _probeBuffer = <int>[];
      if (tailStart < buf.length) {
        _parser.feed(buf.sublist(tailStart), _sink);
        _scheduleFlush();
      }
      return;
    }
    // No DA terminator yet. On a slow link the reply may still be en route;
    // parsing it as keystrokes would type garbage into the app. Keep diverting
    // stdin (the listener routes to the drain) until the DA lands or a short
    // grace expires. On a terminal that already replied the DA was found
    // above; on a no-reply terminal the grace simply elapses and the buffer is
    // discarded.
    _drainingLateProbe = true;
    _lateProbeTimer = Timer(lateProbeGrace, _giveUpLateProbeDrain);
  }

  /// The late DA terminator arrived while draining: stop diverting, discard the
  /// reply, and replay any real input that trailed it.
  void _finishLateProbeDrain() {
    _lateProbeTimer?.cancel();
    _lateProbeTimer = null;
    _drainingLateProbe = false;
    final buf = _probeBuffer;
    _probeBuffer = <int>[];
    final tailStart = _daReplyEnd(buf);
    if (tailStart >= 0 && tailStart < buf.length) {
      _parser.feed(buf.sublist(tailStart), _sink);
      _scheduleFlush();
    }
  }

  /// The grace elapsed with no DA terminator (a terminal that doesn't answer
  /// DA, or a malformed reply): discard the buffer rather than parse it as
  /// keystrokes. Real input typed during the grace is dropped too, but the
  /// window is bounded and only opens after a probe already timed out.
  void _giveUpLateProbeDrain() {
    _lateProbeTimer = null;
    _drainingLateProbe = false;
    _probeBuffer = <int>[];
  }

  /// A fresh probe supersedes any pending late-drain (its own diversion takes
  /// over); called when a probe request begins.
  void _cancelLateProbeDrain() {
    _lateProbeTimer?.cancel();
    _lateProbeTimer = null;
    _drainingLateProbe = false;
  }

  /// Test seam: whether stdin is currently diverting a late probe reply.
  @visibleForTesting
  bool get debugDrainingLateProbe => _drainingLateProbe;

  /// Test seam: enter the late-drain state as a timed-out probe would, with an
  /// optional [partial] already in the buffer — modelling a reply that began
  /// arriving before the timeout (e.g. `ESC [ ? 6 2` with the `c` still in
  /// flight), so the post-timeout tail must reassemble across the boundary.
  @visibleForTesting
  void debugBeginLateProbeDrain([List<int> partial = const <int>[]]) {
    _probeBuffer = List<int>.of(partial);
    _replayPostProbeInput();
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

  bool _interceptParsedEvent(TuiEvent event) {
    if (!_active ||
        !_nativeRawMode ||
        event is! KeyEvent ||
        event.char != 'z' ||
        event.type != KeyEventType.down ||
        event.modifiers.length != 1 ||
        !event.hasCtrl) {
      return false;
    }
    // cfmakeraw disables ISIG, so the terminal delivers Ctrl+Z as 0x1a and the
    // parser turns it into this chord. Consume the terminal job-control chord
    // here: app dispatch must not race the restore/stop sequence.
    unawaited(_suspend());
    return true;
  }

  bool _setRawMode() {
    if (_nativeRawMode) return _terminalModeController.enableRawMode();
    return _setDartRawMode();
  }

  bool _setDartRawMode() {
    var ok = true;
    try {
      _stdin.lineMode = false;
      _stdin.echoMode = false;
    } on StdinException {
      // ignore — terminal may have detached
      ok = false;
    }
    return ok;
  }

  bool _restoreCookedMode() {
    if (_nativeRawMode) return _terminalModeController.restoreMode();
    var ok = true;
    try {
      if (_originalLineMode != null) _stdin.lineMode = _originalLineMode!;
    } on StdinException {
      // ignore
      ok = false;
    }
    try {
      if (_originalEchoMode != null) _stdin.echoMode = _originalEchoMode!;
    } on StdinException {
      // ignore
      ok = false;
    }
    return ok;
  }

  /// Ctrl+Z: restore the terminal for the shell, stop this process, then
  /// continue here after the shell's `fg` sends SIGCONT and repaint.
  ///
  /// Dart deliberately does not allow watching SIGTSTP/SIGCONT. Production
  /// therefore reaches this method from the parsed Ctrl+Z byte (ISIG is off in
  /// our cfmakeraw mode) and self-stops with uncatchable SIGSTOP. An external
  /// `kill -TSTP` cannot be observed safely by pure Dart and may bypass this
  /// orderly path; callers should use the terminal's Ctrl+Z job-control chord.
  Future<void> _suspend() async {
    final mode = _mode;
    if (mode == null) return;
    final lifecycleGeneration = _lifecycleGeneration;
    // Single-flight: a rapid second Ctrl+Z (or one queued while the awaits
    // below run) must not re-write exit sequences or repeat the self-stop.
    if (_suspended) return;
    // A native raw-mode controller is what makes Ctrl+Z observable as a byte;
    // production resumes inline after SIGSTOP/SIGCONT. Tests use the explicit
    // self-stop seam and drive debugResume themselves.
    // Parent stdin is paused during a child handoff, so production cannot
    // legitimately receive the chord then. A test seam or already-queued
    // callback must not stop the parent while the child owns the terminal.
    if ((!_nativeRawMode && _selfStopOverride == null) || _handoffActive) {
      return;
    }
    _suspended = true;
    // Restore the terminal for the shell. Guarded so a failing write/flush
    // still reaches the stop below: a half-suspend that never stops (and so
    // is never resumed) would otherwise wedge the gate forever.
    if (!_handoffActive) {
      final inputRestored = !_changedStdin || _restoreCookedMode();
      try {
        if (_wroteEnterSequences) _stdout.write(_exitSequences(mode));
        await _stdout.flush();
      } catch (_) {}
      // restore() can run while the flush yields (SIGTERM, stdin EOF, or an
      // app-requested exit). A stale suspend continuation must never stop the
      // already-restored process.
      if (_handoffActive) {
        _suspended = false;
        return;
      }
      if (!_active ||
          _restoring ||
          lifecycleGeneration != _lifecycleGeneration ||
          !identical(_mode, mode) ||
          !_suspended) {
        return;
      }
      if (!inputRestored) {
        // Never stop while the shell would inherit a terminal we failed to
        // restore. Re-enter best-effort and leave the process running.
        _resume();
        return;
      }
    }
    final selfStop = _selfStopOverride;
    final bool stopped;
    if (selfStop != null) {
      stopped = selfStop();
    } else {
      // SIGSTOP cannot be caught or discarded. For a self-signal it takes
      // effect before this isolate executes more Dart; after `fg` sends
      // SIGCONT, killPid returns and the inline resume below re-enters Fleury.
      stopped = Process.killPid(pid, ProcessSignal.sigstop);
    }
    if (!stopped) {
      // The stop didn't take (e.g. killPid failed) — re-enter immediately
      // rather than freeze or let frames target the restored shell.
      _resume();
    } else if (selfStop == null) {
      _resume();
    }
  }

  /// Test seam: drive [_suspend] without a real job-control terminal.
  @visibleForTesting
  Future<void> debugSuspend() => _suspend();

  /// Test seam: drive [_resume] (`fg`) without a real SIGCONT.
  @visibleForTesting
  void debugResume() => _resume();

  /// Test seam: whether frame writes are currently gated by a Ctrl+Z suspend.
  @visibleForTesting
  bool get debugSuspended => _suspended;

  /// Invoked inside [runWithTerminalHandoff] after the terminal is restored
  /// and before the operation runs (start) / after it completes and before
  /// the driver re-enters its mode (end). `runApp` wires these to pause and
  /// resume the fd-level stray-output capture, so a child the operation
  /// spawns with `ProcessStartMode.inheritStdio` (an `$EDITOR`, a pager)
  /// inherits the *real* descriptors instead of the capture pipe. Failures
  /// are swallowed — a handoff must proceed even if the capture is already
  /// shutting down.
  Future<void> Function()? onHandoffStart;
  Future<void> Function()? onHandoffEnd;

  @override
  Future<T> runWithTerminalHandoff<T>(FutureOr<T> Function() operation) async {
    // A helper invoked from inside an existing handoff is already in the safe
    // restored-terminal zone; nesting must not restore/re-enter a second time.
    if (Zone.current[this] == true) return await operation();

    // Distinct concurrent handoffs (two process tasks launched together) must
    // not overlap. With a single boolean, the first completion re-entered and
    // ungated Fleury frames while the second child still owned the terminal.
    final previous = _handoffTail;
    final release = Completer<void>();
    _handoffTail = release.future;

    var didHandoff = false;
    var stdinPaused = false;
    TerminalMode? handoffMode;
    try {
      await previous;
      try {
        final mode = _mode;
        if (!_active || mode == null) return await operation();
        handoffMode = mode;
        didHandoff = true;
        _handoffActive = true;

        // Stop the parent subscription before terminal modes change so it
        // never races an inherited-stdio editor/pager for tty input.
        final input = _stdinSubscription;
        if (input != null) {
          input.pause();
          stdinPaused = true;
        }
        try {
          if (_wroteEnterSequences) _stdout.write(_exitSequences(mode));
        } catch (_) {}
        if (_changedStdin) _restoreCookedMode();
        try {
          await _stdout.flush();
        } catch (_) {}

        final hs = onHandoffStart;
        if (hs != null) {
          try {
            await hs();
          } catch (_) {}
        }

        return await runZoned(
          () => Future<T>.sync(operation),
          zoneValues: <Object?, Object?>{this: true},
        );
      } finally {
        if (didHandoff) {
          var shouldReenter = false;
          try {
            final he = onHandoffEnd;
            if (he != null) {
              try {
                await he();
              } catch (_) {}
            }
            final mode = handoffMode!;
            shouldReenter = _active && identical(_mode, mode);
            if (shouldReenter) {
              if (_changedStdin) _setRawMode();
              try {
                if (_wroteEnterSequences) _stdout.write(_enterSequences(mode));
                await _stdout.flush();
              } catch (_) {}
            }
          } finally {
            try {
              if (stdinPaused) _stdinSubscription?.resume();
            } finally {
              _handoffActive = false;
              if (shouldReenter && !_events.isClosed) {
                _events.add(ResizeEvent(size));
              }
            }
          }
        }
      }
    } finally {
      if (!release.isCompleted) release.complete();
    }
  }

  /// Foreground continuation: re-enter the configured mode and force a full
  /// repaint (the window may have resized while stopped).
  void _resume() {
    final mode = _mode;
    if (mode == null || !_active) return;
    // Clear the write gate BEFORE re-entering so the repaint below can paint.
    _suspended = false;
    // A nested suspend seam during an editor handoff must not re-enter our mode
    // while the child owns the screen. The handoff's own finally re-enters.
    if (_handoffActive) return;
    if (_changedStdin) _setRawMode();
    if (_wroteEnterSequences) _stdout.write(_enterSequences(mode));
    if (!_events.isClosed) _events.add(ResizeEvent(size));
  }

  @override
  Future<void> restore() async {
    _restoring = true;
    _lifecycleGeneration++;
    _active = false;
    _suspended = false;
    // Disarm the signal-grace deadline unconditionally (even when there's
    // nothing else to restore): an orderly shutdown that reaches restore()
    // must never be shot down by a stale timer afterwards.
    _graceTimer?.cancel();
    _graceTimer = null;
    _pendingSignal = null;
    _pendingSignalDelivered = false;
    _entering = false;
    // Before the early-return: a late-probe drain timer must never outlive
    // restore(), even on the nothing-else-to-restore path.
    _cancelLateProbeDrain();
    if (!_active &&
        !_wroteEnterSequences &&
        !_changedStdin &&
        _stdinSubscription == null &&
        _resizeSubscription == null &&
        _intSubscription == null &&
        _termSubscription == null) {
      _mode = null;
      _sink.target = null;
      _restoring = false;
      return;
    }

    _handoffActive = false;
    _flushTimer?.cancel();
    _flushTimer = null;

    // Termination watchers go first. This closes the only path that can re-arm
    // signal grace while the remaining asynchronous cleanup yields.
    try {
      await _intSubscription?.cancel();
    } catch (_) {}
    _intSubscription = null;
    try {
      await _termSubscription?.cancel();
    } catch (_) {}
    _termSubscription = null;

    try {
      await _stdinSubscription?.cancel();
    } catch (_) {}
    _stdinSubscription = null;
    try {
      await _resizeSubscription?.cancel();
    } catch (_) {}
    _resizeSubscription = null;
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
      try {
        _stdout.write(_exitSequences(_mode ?? TerminalMode.interactive));
      } catch (_) {}
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

    _mode = null;
    _sink.target = null;
    // Belt-and-suspenders against a callback already queued before watcher
    // cancellation. Successful teardown must leave no force-exit timer behind.
    _graceTimer?.cancel();
    _graceTimer = null;
    _pendingSignal = null;
    _pendingSignalDelivered = false;
    _restoring = false;
  }

  @override
  void write(String data) {
    // Drop frames while the terminal is handed to a child ([_handoffActive])
    // or restored for the shell across a Ctrl+Z ([_suspended]) — writing them
    // would interleave ANSI with an editor's screen or the bare shell prompt.
    if (_handoffActive || _suspended) return;
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
  bool Function(TuiEvent event)? intercept;

  @override
  void add(TuiEvent event) {
    if (intercept?.call(event) ?? false) return;
    final controller = target;
    if (controller != null && !controller.isClosed) controller.add(event);
  }
}

/// Testable ownership boundary for the complete POSIX terminal mode.
///
/// Unlike Dart's ICANON/ECHO-only setters, [enableRawMode] must disable ISIG so
/// Ctrl+Z reaches Fleury as a byte. [restoreMode] restores the exact snapshot
/// captured by the first successful enable and intentionally retains it across
/// suspend/handoff cycles.
@visibleForTesting
abstract interface class PosixTerminalModeController {
  bool enableRawMode();
  bool restoreMode();
}

/// libc-backed termios controller. The termios object is intentionally opaque:
/// tcgetattr/cfmakeraw/tcsetattr own its ABI, so Fleury does not encode Darwin
/// vs Linux field offsets. A generously sized byte buffer is safe because libc
/// reads/writes only `sizeof(struct termios)`.
final class NativePosixTerminalModeController
    implements PosixTerminalModeController {
  NativePosixTerminalModeController()
    : _bindings = _PosixTermiosBindings.load();

  static const _termiosStorageBytes = 256;
  final _PosixTermiosBindings? _bindings;
  List<int>? _original;

  @override
  bool enableRawMode() {
    final bindings = _bindings;
    if (bindings == null) return false;
    final storage = calloc<Uint8>(_termiosStorageBytes);
    try {
      final original = _original;
      if (original == null) {
        if (bindings.tcgetattr(0, storage.cast<Void>()) != 0) return false;
        _original = List<int>.of(storage.asTypedList(_termiosStorageBytes));
      } else {
        storage.asTypedList(_termiosStorageBytes).setAll(0, original);
      }
      bindings.cfmakeraw(storage.cast<Void>());
      return bindings.tcsetattr(0, _tcsanow, storage.cast<Void>()) == 0;
    } on Object {
      return false;
    } finally {
      calloc.free(storage);
    }
  }

  @override
  bool restoreMode() {
    final bindings = _bindings;
    final original = _original;
    if (bindings == null || original == null) return false;
    final storage = calloc<Uint8>(_termiosStorageBytes);
    try {
      storage.asTypedList(_termiosStorageBytes).setAll(0, original);
      return bindings.tcsetattr(0, _tcsanow, storage.cast<Void>()) == 0;
    } on Object {
      return false;
    } finally {
      calloc.free(storage);
    }
  }

  static const _tcsanow = 0;
}

typedef _TcgetattrNative = Int32 Function(Int32, Pointer<Void>);
typedef _TcgetattrDart = int Function(int, Pointer<Void>);
typedef _TcsetattrNative = Int32 Function(Int32, Int32, Pointer<Void>);
typedef _TcsetattrDart = int Function(int, int, Pointer<Void>);
typedef _CfmakerawNative = Void Function(Pointer<Void>);
typedef _CfmakerawDart = void Function(Pointer<Void>);

final class _PosixTermiosBindings {
  const _PosixTermiosBindings({
    required this.tcgetattr,
    required this.tcsetattr,
    required this.cfmakeraw,
  });

  static _PosixTermiosBindings? load() {
    if (Platform.isWindows) return null;
    try {
      final libc = DynamicLibrary.process();
      return _PosixTermiosBindings(
        tcgetattr: libc.lookupFunction<_TcgetattrNative, _TcgetattrDart>(
          'tcgetattr',
        ),
        tcsetattr: libc.lookupFunction<_TcsetattrNative, _TcsetattrDart>(
          'tcsetattr',
        ),
        cfmakeraw: libc.lookupFunction<_CfmakerawNative, _CfmakerawDart>(
          'cfmakeraw',
        ),
      );
    } on Object {
      // Non-glibc/non-Darwin POSIX target: retain the old ICANON/ECHO fallback.
      // Ctrl+Z orderly suspension is unavailable there, but raw input/rendering
      // still work and no unsafe Dart FFI signal callback is installed.
      return null;
    }
  }

  final _TcgetattrDart tcgetattr;
  final _TcsetattrDart tcsetattr;
  final _CfmakerawDart cfmakeraw;
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
    _driver._cancelLateProbeDrain(); // a new probe supersedes any pending drain
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
