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
import '../input/keyboard_state.dart';
import 'input_parser.dart';
import 'terminal_driver.dart';
import 'terminal_probe.dart';
import 'terminal_query_runner.dart';
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
    _queryRunner = TerminalQueryRunner(
      parser: _parser,
      inputSink: _sink,
      write: (bytes) async {
        _stdout.write(bytes);
        await _stdout.flush();
      },
      lateResponseGrace: lateProbeGrace,
    );
  }

  final Stdin _stdin;

  // dart:io hands out the process-global stdin exactly once: after a session
  // listens to it and cancels (in [restore]), it can never be listened to
  // again. This static latches once the global stdin has been spent so a
  // second same-process [enter] fails with a clear message instead of the
  // opaque 'Stream has already been listened to'. Injected test streams are
  // exempt (each driver owns its own), so this never trips in unit tests.
  static bool _globalStdinConsumed = false;
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
  late final TerminalQueryRunner _queryRunner;

  StreamSubscription<List<int>>? _stdinSubscription;
  StreamSubscription<ProcessSignal>? _resizeSubscription;
  StreamSubscription<ProcessSignal>? _intSubscription;
  StreamSubscription<ProcessSignal>? _termSubscription;
  Timer? _flushTimer;
  Timer? _pasteIdleTimer;
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
  ActiveTerminalState? _terminalState;
  TerminalMode? get _mode => _terminalState?.effectiveMode;
  bool get _changedStdin => _terminalState?.rawInputOwned ?? false;
  bool get _wroteEnterSequences => _terminalState?.outputModesOwned ?? false;

  // A timed-out query keeps its response grammar active briefly so a slow SSH
  // reply cannot become input. Ordinary keystrokes continue through the parser
  // throughout; only complete response frames are consumed.
  @visibleForTesting
  static Duration lateProbeGrace = const Duration(milliseconds: 250);
  @visibleForTesting
  static Duration startupNegotiationBudget = const Duration(milliseconds: 500);
  static const _perProbeTimeout = Duration(milliseconds: 150);
  ImageProtocol? _imageProtocolOverride;
  bool _synchronizedOutput = false;
  // Set once the ambiguous-width probe measures how the terminal sizes
  // ambiguous glyphs; a confirmed `narrow` lets the renderer drop the
  // defensive per-cell repositioning [capabilities] otherwise assumes.
  AmbiguousCharWidth? _ambiguousCharWidthOverride;

  /// What the startup probe measured the terminal actually drawing. Reported
  /// through [capabilities] for diagnostics; null fields mean "unmeasured".
  WidthMeasurements _measuredGlyphWidths = const WidthMeasurements.empty();
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
    final withWidth = width == null
        ? merged
        : merged.copyWith(ambiguousCharWidth: width);
    return withWidth.copyWith(
      measuredWidths: _measuredGlyphWidths,
      // Fold measurements + FLEURY_* overrides into the one derived policy
      // every geometry consumer shares (RFC 0019 §6.2). Same inputs as the
      // ambiguousCharWidth resolution above, so the renderer's pin gate and
      // the layout policy can never disagree about the evidence.
      textPolicy: deriveTextPresentationPolicy(
        measurements: _measuredGlyphWidths,
        environment: environment,
      ),
    );
  }

  @override
  Stream<TuiEvent> get events => _events.stream;

  @override
  bool get isActive => _active;

  @override
  bool get isInteractive => _stdoutIsTerminal;

  @override
  Future<TerminalSessionProfile> enter(TerminalMode mode) async {
    if (_active) {
      throw StateError('PosixTerminalDriver.enter called on an active driver.');
    }
    // Reject a second same-process interactive session up front, before any
    // terminal mutation, so the terminal is left untouched and the failure is
    // legible (see [_globalStdinConsumed]).
    if (identical(_stdin, stdin) && _globalStdinConsumed) {
      throw StateError(
        'Fleury supports one interactive session per process: the terminal '
        'stdin was already consumed by an earlier runApp() and dart:io cannot '
        'hand it out again. Run each interactive session in its own process.',
      );
    }
    _restoring = false;
    _entering = true;
    final enterGeneration = ++_lifecycleGeneration;
    _terminalState = ActiveTerminalState(
      requestedMode: mode,
      effectiveMode: _effectiveMode(mode),
    );
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
      _terminalState!.rawInputOwned = true;
    }

    // Screen-control sequences only when stdout is a real terminal — writing
    // them into a pipe or file would just corrupt it.
    final enter = _enterSequences(_mode!);
    if (_stdoutIsTerminal && enter.isNotEmpty) {
      _stdout.write(enter);
      _terminalState!.outputModesOwned = true;
    }

    _stdinSubscription = _stdin.listen(
      (bytes) {
        _parser.feed(bytes, _sink, responseSink: _queryRunner);
        _scheduleFlush();
        _schedulePasteIdleFlush();
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
        _pasteIdleTimer?.cancel();
        _pasteIdleTimer = null;
        _parser.finish(_sink); // finalizes any in-progress paste at EOF
        if (!_events.isClosed) unawaited(_events.close());
      },
      cancelOnError: false,
    );

    // Actively confirm a native image protocol the environment didn't name
    // (e.g. Kitty graphics under Warp, which masquerades as xterm-256color).
    // Runs before the app renders so the first frame already uses the right
    // protocol; falls back silently when nothing replies.
    // Negotiation runs with the other startup probes — after the enter
    // sequences pushed our flags, and on the SAME screen buffer they were
    // pushed to (§8.1). It never blocks the app: an unanswered query
    // simply leaves capabilities conservative.
    //
    // A concurrent force-restore can complete while a bounded startup probe is
    // awaiting its reply (runApp's zone handler calls cleanup() on any uncaught
    // async error, and these probes hold the driver for up to ~500 ms). Never
    // reactivate a driver whose lifecycle moved on — and check BETWEEN the
    // probes, not only after them: `restore()` nulls `_terminalState`, so a
    // teardown that lands mid-negotiation must be reported as this StateError
    // rather than crashing on the next read of the state it tore down.
    final negotiationClock = Stopwatch()..start();
    await _negotiateKeyboard(negotiationClock);
    _checkStillEntering(enterGeneration);
    await _negotiateSynchronizedOutput(negotiationClock);
    _checkStillEntering(enterGeneration);
    await _maybeProbeImageProtocol(negotiationClock);
    final negotiated = _checkStillEntering(enterGeneration);
    await _maybeProbeAmbiguousWidth(
      negotiated.alternateScreen,
      negotiationClock,
    );
    _checkStillEntering(enterGeneration);

    _resizeSubscription = _watchSignal(ProcessSignal.sigwinch, (_) {
      if (!_events.isClosed) _events.add(ResizeEvent(size));
    });

    _active = true;
    _entering = false;
    _emitPendingSignalIfListened();
    final terminal = capabilities;
    return TerminalSessionProfile.ansi(
      terminal: terminal,
      keyboard: keyboardCapabilities,
      synchronizedOutput: _synchronizedOutput,
    );
  }

  /// Asserts that the `enter` identified by [enterGeneration] still owns the
  /// terminal, and returns the mode it owns it in.
  ///
  /// Called around every startup probe await. The generation check and the
  /// state read belong together: a completed `restore()` leaves `_restoring`
  /// false again but has bumped the generation AND nulled `_terminalState`, so
  /// reading the mode without checking first is exactly the null-check crash
  /// this replaces.
  TerminalMode _checkStillEntering(int enterGeneration) {
    final state = _terminalState;
    if (_restoring || enterGeneration != _lifecycleGeneration || state == null) {
      throw StateError(
        'PosixTerminalDriver was restored while enter was negotiating.',
      );
    }
    return state.effectiveMode;
  }

  Future<void> _negotiateSynchronizedOutput(Stopwatch negotiationClock) async {
    final override = synchronizedOutputOverrideFromEnvironment(
      Platform.environment,
    );
    if (override != null) {
      _synchronizedOutput = override;
      return;
    }
    _synchronizedOutput = false;
    if (!_stdoutIsTerminal || !_changedStdin) return;
    final timeout = _nextProbeTimeout(negotiationClock);
    if (timeout == null) return;
    try {
      _synchronizedOutput = await probeSynchronizedOutput(
        _queryRunner,
        timeout: timeout,
      );
    } on Object {
      _synchronizedOutput = false;
    }
  }

  /// When the environment doesn't already name a native image protocol, ask
  /// the terminal directly (a short, bounded query/response). A confirmed reply
  /// upgrades [capabilities] so [Image] widgets emit real pixels instead of
  /// cell art. Skipped unless we own a real terminal in raw mode (so the reply
  /// arrives byte-for-byte, not line-buffered) and the environment is
  /// inconclusive; any failure leaves the conservative fallback in place.
  /// The Kitty flags this terminal CONFIRMED, or null before/without a
  /// successful negotiation.
  int? _confirmedKeyboardFlags;

  KeyboardCapabilities get keyboardCapabilities {
    final flags = _confirmedKeyboardFlags;
    if (flags == null) return KeyboardCapabilities.legacy;
    return KeyboardCapabilities.fromKittyFlags(flags);
  }

  /// Negotiates the keyboard protocol: push (already done by the enter
  /// sequences), ask what stuck, and either commit or roll back.
  ///
  /// Rollback matters because a partial answer is not merely "less" — flag
  /// 8 stops the terminal sending text and flag 16 is what re-supplies it,
  /// so a terminal honouring 8 without 16 leaves the session unable to type
  /// at all. Reporting conservative capabilities cannot fix that; only
  /// leaving the mode can (§8.3).
  Future<void> _negotiateKeyboard(Stopwatch negotiationClock) async {
    if (!_stdoutIsTerminal || !_changedStdin) return;
    // Every `_terminalState` read in this method and its helpers is null-safe:
    // `restore()` can complete while a probe below is awaiting its reply, and
    // the caller's `_checkStillEntering` is what turns that into a legible
    // StateError. Bailing out quietly here lets it get there.
    final effective = _terminalState?.effectiveMode;
    if (effective == null) return;
    if (effective.keyboardProtocol == KeyboardProtocolMode.legacy) return;
    // Escape hatch for a terminal where the query itself misbehaves.
    final flag = Platform.environment['FLEURY_KEYBOARD_PROBE'];
    if (flag == '0' || flag == 'false') {
      await _restoreLegacyKeyboard(effective);
      return;
    }
    int? flags;
    final timeout = _nextProbeTimeout(negotiationClock);
    if (timeout == null) {
      await _restoreLegacyKeyboard(effective);
      return;
    }
    try {
      flags = await probeKeyboardFlags(_queryRunner, timeout: timeout);
    } on Object {
      flags = null;
    }
    if (flags == null) {
      // No answer confirms no enhanced keyboard tier. Pop the attempted frame
      // (ignored by terminals that never understood it) and claim only legacy
      // parsing.
      _confirmedKeyboardFlags = null;
      await _restoreLegacyKeyboard(effective);
      return;
    }
    if (effective.keyboardProtocol == KeyboardProtocolMode.lifecycle &&
        !_lifecycleIsSafe(flags)) {
      // Partial lifecycle: leave the mode before the app sees any input,
      // and re-establish the safe tier on the SAME screen buffer.
      _stdout.write(
        '\x1B[<1u'
        '\x1B[>${KeyboardProtocolMode.disambiguated.requestedFlags}u',
      );
      final state = _terminalState;
      if (state == null) return; // restored mid-probe
      state.effectiveMode = terminalModeWithKeyboardProtocol(
        effective,
        KeyboardProtocolMode.disambiguated,
      );
      await _stdout.flush();
      int? after;
      final fallbackTimeout = _nextProbeTimeout(negotiationClock);
      if (fallbackTimeout != null) {
        try {
          after = await probeKeyboardFlags(
            _queryRunner,
            timeout: fallbackTimeout,
          );
        } on Object {
          after = null;
        }
      }
      _confirmedKeyboardFlags = after;
      if (after == null || after & 0x01 == 0) {
        await _restoreLegacyKeyboard(effective);
      }
      return;
    }
    _confirmedKeyboardFlags = flags;
    if (flags & 0x01 == 0) {
      await _restoreLegacyKeyboard(effective);
    }
  }

  /// Returns to legacy input when Kitty disambiguation was not confirmed.
  ///
  /// Fleury parses modifyOtherKeys replies for compatibility with a mode the
  /// host or an outer application enabled, but never activates that ambiguous
  /// protocol itself. Pop the attempted Kitty frame so a partial
  /// implementation cannot remain stacked under the legacy parser.
  Future<void> _restoreLegacyKeyboard(TerminalMode effective) async {
    try {
      _stdout.write('\x1B[<1u');
      await _stdout.flush();
    } on Object {
      return;
    }
    _confirmedKeyboardFlags = null;
    final state = _terminalState;
    if (state == null) return; // restored while the pop was flushing
    state.effectiveMode = terminalModeWithKeyboardProtocol(
      effective,
      KeyboardProtocolMode.legacy,
    );
  }

  /// Lifecycle is only safe to keep when text survives it: event types (2),
  /// all-keys-as-escapes (8) and associated text (16) must ALL be active.
  /// Flag 4 is an optional positional enhancement.
  static bool _lifecycleIsSafe(int flags) =>
      flags & 0x02 != 0 && flags & 0x08 != 0 && flags & 0x10 != 0;

  Future<void> _maybeProbeImageProtocol(Stopwatch negotiationClock) async {
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
    final timeout = _nextProbeTimeout(negotiationClock);
    if (timeout == null) return;
    try {
      final detected = await probeImageProtocol(_queryRunner, timeout: timeout);
      if (detected != null) _imageProtocolOverride = detected;
    } on Object {
      // Probe failed (no terminal reply, write error, …): keep the fallback.
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
  Future<void> _maybeProbeAmbiguousWidth(
    bool onAlternateScreen,
    Stopwatch negotiationClock,
  ) async {
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
    final timeout = _nextProbeTimeout(negotiationClock);
    if (timeout == null) return;
    try {
      // One round trip measures every width class the field disagrees on, not
      // just ambiguous — same cost as the old single-glyph probe.
      final measured = await probeGlyphWidths(_queryRunner, timeout: timeout);
      _measuredGlyphWidths = measured;
      // Agreement across the ambiguous representatives, or keep the default:
      // one glyph is a signal, not proof (RFC 0019 §6.1).
      final ambiguous = ambiguousWidthFromMeasurements(measured);
      if (ambiguous != null) _ambiguousCharWidthOverride = ambiguous;
    } on Object {
      // Probe failed (no terminal reply, write error, …): keep the `wide`
      // default so ambiguous-wide terminals never garble.
    }
  }

  Duration? _nextProbeTimeout(Stopwatch negotiationClock) {
    final remaining = startupNegotiationBudget - negotiationClock.elapsed;
    if (remaining <= Duration.zero) return null;
    return remaining < _perProbeTimeout ? remaining : _perProbeTimeout;
  }

  /// Builds the mode-entry escape sequence (alt screen, hide cursor,
  /// bracketed paste, Kitty keyboard, mouse), shared by [enter] and resume.
  String _enterSequences(TerminalMode mode) =>
      buildTerminalEnterSequences(mode);

  /// Applies the fleet override before any sequence is built.
  ///
  /// `FLEURY_KEYBOARD=legacy|disambiguated|lifecycle` caps (or raises) the
  /// negotiated tier without touching app code — the lever a support
  /// channel needs when one terminal in a deployment misbehaves, and the
  /// one a bug report can be asked to set. Applied here rather than at the
  /// negotiation step so the PUSH itself is capped, not just the verdict.
  TerminalMode _effectiveMode(TerminalMode mode) {
    final tier = resolveKeyboardTier(
      requested: mode.keyboardProtocol,
      environment: Platform.environment,
    );
    if (tier == mode.keyboardProtocol) return mode;
    return terminalModeWithKeyboardProtocol(mode, tier);
  }

  /// Builds the mode-exit escape sequence, shared by [restore] and
  /// suspend. Disables mouse modes unconditionally (incl. all-motion
  /// 1003) so none leak back to the shell.
  String _exitSequences(TerminalMode mode) => buildTerminalExitSequences(mode);

  bool _interceptParsedEvent(TuiEvent event) {
    if (!_active ||
        !_nativeRawMode ||
        event is! KeyEvent ||
        event.code.character != 'z' ||
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
    // Before the early-return: query deadlines and late-reply quarantine must
    // never outlive terminal ownership.
    _queryRunner.dispose();
    if (!_active &&
        !_wroteEnterSequences &&
        !_changedStdin &&
        _stdinSubscription == null &&
        _resizeSubscription == null &&
        _intSubscription == null &&
        _termSubscription == null) {
      _terminalState = null;
      _sink.target = null;
      _restoring = false;
      return;
    }

    _handoffActive = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    _pasteIdleTimer?.cancel();
    _pasteIdleTimer = null;

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
    // Cancelling the process-global stdin spends it for the process lifetime;
    // latch that so a second enter() rejects cleanly rather than crashing.
    if (identical(_stdin, stdin)) _globalStdinConsumed = true;
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
      _terminalState?.rawInputOwned = false;
    }

    if (_wroteEnterSequences) {
      // Disable input modes first so no stray sequences leak as the
      // terminal returns to the shell.
      try {
        _stdout.write(_exitSequences(_mode ?? TerminalMode.interactive));
      } catch (_) {}
      _terminalState?.outputModesOwned = false;
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

    _terminalState = null;
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

  /// How long a bracketed paste may stall between reads before the driver
  /// finalizes it. Distinct from — and far longer than — the 30ms ESC flush
  /// debounce: a slow SSH paste pauses well under this, but an abandoned paste
  /// (`ESC[200~` with no `ESC[201~`, e.g. the paste source died) would otherwise
  /// swallow all later input forever, so it is force-finalized here.
  @visibleForTesting
  static Duration pasteIdleTimeout = const Duration(seconds: 5);

  /// (Re)arms the paste-inactivity deadline whenever input arrives while the
  /// parser is mid bracketed-paste. Each fresh read pushes the deadline out, so
  /// only a genuinely abandoned paste ever reaches it; a completed or
  /// EOF-finalized paste leaves the parser out of the paste state, cancelling it.
  void _schedulePasteIdleFlush() {
    _pasteIdleTimer?.cancel();
    if (!_parser.isPasting) {
      _pasteIdleTimer = null;
      return;
    }
    _pasteIdleTimer = Timer(pasteIdleTimeout, () {
      _pasteIdleTimer = null;
      _parser.flushPaste(_sink);
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

/// The keyboard tier this session actually pushes, from what the app asked for
/// and what the environment says.
///
/// Two rules, both about *pushing* rather than about the verdict — the flags
/// have to be capped before they go out, not after:
///
///  * `FLEURY_KEYBOARD=legacy|disambiguated|lifecycle` wins outright. It is the
///    lever a support channel can pull on a deployed binary, and the one a bug
///    report can be asked to set.
///  * Otherwise the default (`lifecycle`) is capped to the safe tier inside a
///    MULTIPLEXER. A raw query is not a reliable statement about the host
///    terminal there — the same reasoning the image probe uses — and tmux may
///    answer for itself, forward to a host that answers differently, or accept
///    the flags and fail to translate the enhanced input back. Lifecycle is the
///    one tier where being wrong costs the user their ability to type, so the
///    automatic upgrade holds back. An app that knows its deployment handles
///    the protocol can still force it through the env var.
KeyboardProtocolMode resolveKeyboardTier({
  required KeyboardProtocolMode requested,
  required Map<String, String> environment,
}) {
  final override = switch (environment['FLEURY_KEYBOARD']?.toLowerCase()) {
    'legacy' || 'off' || 'none' => KeyboardProtocolMode.legacy,
    'disambiguated' || 'default' => KeyboardProtocolMode.disambiguated,
    'lifecycle' || 'full' => KeyboardProtocolMode.lifecycle,
    _ => null,
  };
  if (override != null) return override;
  if (requested == KeyboardProtocolMode.lifecycle &&
      detectTerminalMultiplexerFromEnvironment(environment)) {
    return KeyboardProtocolMode.disambiguated;
  }
  return requested;
}
