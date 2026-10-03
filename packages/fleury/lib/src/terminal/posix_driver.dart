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
import 'package:stdio/stdio.dart' as fd;

import '../foundation/geometry.dart';
import '../rendering/ansi_render_target.dart';
import 'capabilities.dart';
import '../input/events.dart';
import '../input/keyboard_state.dart';
import '../runtime/dev_signal_ack.dart';
import '../runtime/inline_terminal_lease.dart';
import 'input_parser.dart';
import 'inline_terminal_region.dart';
import 'terminal_driver.dart';
import 'terminal_probe.dart';
import 'terminal_query_runner.dart';
import 'terminal_sequences.dart';
import 'pointer_shapes.dart';
import 'posix_input_lease.dart';

/// Stops terminal-generated input before runtime teardown can yield. Kept out
/// of the public driver interface: other drivers need no ANSI mode writes.
@internal
void stopPosixInputReports(TerminalDriver driver) {
  if (driver is PosixTerminalDriver) driver._stopInputReports();
}

/// Suspends [driver]'s session for the shell's job control — restore the
/// terminal, stop, re-enter after `fg` — for a Ctrl+Z press the application
/// left unhandled. The runtime owns that rule (dispatch first, like Ctrl+C's
/// exit); the driver owns whether its session suspends at all.
///
/// Returns whether a suspension started. False for every driver without job
/// control (browser, served, remote, Windows), for
/// [PosixTerminalDriver.suspendOnCtrlZ] false, for a session without native
/// raw mode, whose Ctrl+Z the kernel handles before it is ever read, and for a
/// session no job-control shell started ([PosixJobControl.isShellJob]), which
/// nothing could continue once stopped. On false the chord stays an ordinary
/// key. The application's own request, `TerminalSession.suspend`, starts the
/// same suspension.
@internal
bool requestCtrlZSuspend(TerminalDriver driver) =>
    driver is PosixTerminalDriver && driver._suspendForCtrlZ();

/// Native POSIX terminal lifecycle and byte-input driver.
///
/// When a job-control shell started the app, a Ctrl+Z press the application
/// leaves unhandled suspends orderly: Fleury restores the terminal, stops the
/// app's job — with the hot-reload supervisor or launcher that runs the app,
/// see [PosixJobControl] — then re-enters after `fg` (see [suspendOnCtrlZ]).
/// The application can request the same suspension with
/// `TerminalSession.suspend`. Externally sending SIGTSTP is not a supported
/// lifecycle path because Dart cannot safely watch SIGTSTP/SIGCONT; it may
/// stop the process before Fleury can restore terminal modes.
class PosixTerminalDriver
    with TerminalAttentionSequences
    implements
        TerminalDriver,
        TerminalHandoffDriver,
        InlineTerminalDriver,
        TerminalSuspendDriver {
  PosixTerminalDriver({
    String? keypadDecimal,
    Stdin? stdinOverride,
    Stdout? stdoutOverride,
    this.signalGrace = const Duration(seconds: 5),
    this.suspendOnCtrlZ = true,
    @visibleForTesting void Function(int exitCode)? forceExitOverride,
    @visibleForTesting bool Function()? selfStopOverride,
    @visibleForTesting bool? shellJobOverride,
    @visibleForTesting PosixTerminalModeController? terminalModeController,
    @visibleForTesting
    StreamSubscription<ProcessSignal>? Function(
      ProcessSignal signal,
      void Function(ProcessSignal signal) onSignal,
    )?
    signalWatcherOverride,
  }) : _parser = InputParser(
         keypadDecimal:
             keypadDecimal ??
             Platform.environment['FLEURY_KEYPAD_DECIMAL'] ??
             '.',
       ),
       _stdin = stdinOverride ?? stdin,
       _stdout = stdoutOverride ?? _nativeOutput(),
       _forceExitOverride = forceExitOverride,
       _selfStopOverride = selfStopOverride,
       _shellJobOverride = shellJobOverride,
       _signalWatcherOverride = signalWatcherOverride,
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

  // Redirected/custom streams retain dart:io's source-specific contract.
  // Native macOS/Linux TTY input is a cancellable descriptor borrow instead.
  static bool _globalStdinConsumed = false;
  bool get _usesNativeInput =>
      identical(_stdin, stdin) &&
      _stdinIsTerminal &&
      (Platform.isMacOS || Platform.isLinux);
  // Native input temporarily sets O_NONBLOCK on a duplicated stdin. Shells
  // may share that open-file description with stdout, so dart:io's synchronous
  // terminal writes can fail with EAGAIN on a full queue. The same sink used
  // by runApp's fd capture retries partial writes/EINTR and polls on EAGAIN.
  // Borrow fd 1; the driver never closes it. Keep explicit/zone overrides intact.
  static Stdout _nativeOutput() =>
      IOOverrides.current == null ? fd.StdoutTerminalSink(1) : stdout;

  final Stdout _stdout;

  /// How long a delivered [SignalEvent] may remain unresolved before the
  /// driver force-terminates (restore → `exit(128+n)`). The ceiling on
  /// app-owned shutdown: a supervisor's SIGTERM must always end the
  /// process even when the app hangs mid-teardown.
  final Duration signalGrace;

  /// Whether a Ctrl+Z press the application leaves unhandled suspends the
  /// session: restore the terminal for the shell, stop the app's job, and
  /// re-enter after `fg`. It suspends only when a job-control shell started
  /// the app ([PosixJobControl.isShellJob]); otherwise nothing could continue
  /// the stopped app, and the press is an ordinary key whatever this says.
  ///
  /// Ctrl+Z is always dispatched to the application first, the way Ctrl+C is
  /// before it exits: a focused text field undoes, an app binding fires, and
  /// only a press nothing handled suspends. Set false for applications that
  /// must never be suspended by that press. The chord is then only an
  /// ordinary [KeyEvent], and raw terminal startup fails if native raw mode
  /// is unavailable: Dart's line/echo fallback leaves Ctrl+Z to the kernel's
  /// job control, which stops the process before the application could see
  /// the key.
  ///
  /// The application can still suspend on its own terms with
  /// `TerminalSession.suspend`, which this flag does not govern: an app that
  /// must close sensitive state first binds a key that does so and then
  /// requests the suspension. A Ctrl+Z binding fires only while no text field
  /// has focus — `TextInput` and `TextArea` take Ctrl+Z for undo — so pick a
  /// key the fields leave alone. This does not make external SIGTSTP/SIGCONT
  /// observable to Dart.
  final bool suspendOnCtrlZ;

  /// Test seam: replaces the `exit()` call in the force path so grace
  /// behavior is assertable without killing the test process.
  final void Function(int exitCode)? _forceExitOverride;

  /// Test seam: replaces the SIGSTOP job stop ([PosixJobControl.stopJob]) so
  /// [_suspend]'s gating/single-flight is assertable without actually
  /// stopping the test process. Returns whether the stop "took" — a test can
  /// return false to exercise the failed-stop un-gate path.
  final bool Function()? _selfStopOverride;

  /// Test seam: whether this session runs as a job of a job-control shell,
  /// in place of what [PosixJobControl.isShellJob] answers when the session
  /// enters. Faked stdio is no job of the test process's terminal, so a test
  /// that suspends through the Ctrl+Z gate or `TerminalSession.suspend` says
  /// whether a shell started it.
  final bool? _shellJobOverride;

  /// Owns the complete POSIX termios snapshot used by raw mode. Dart's
  /// `Stdin.lineMode` / `echoMode` API only toggles ICANON/ECHO and leaves ISIG
  /// enabled, so Ctrl+Z is consumed by the kernel as SIGTSTP before Fleury can
  /// restore the screen. The native controller uses cfmakeraw, making Ctrl+Z a
  /// parsed key: the application sees it first, and an unhandled press takes
  /// the orderly restore -> stop -> resume path.
  final PosixTerminalModeController _terminalModeController;

  // Snapshotted once: whether each standard stream is a real TTY. Output
  // governs whether we may emit screen-control sequences; input governs
  // whether raw mode is meaningful (and settable without throwing).
  late final bool _stdinIsTerminal = _stdin.hasTerminal;
  late final bool _stdoutIsTerminal = _stdout.hasTerminal;

  final InputParser _parser;
  late final StreamController<TuiEvent> _events;
  final _ParserSink _sink = _ParserSink();
  late final TerminalQueryRunner _queryRunner;

  PosixInputLease? _nativeInput;
  StreamSubscription<List<int>>? _stdinSubscription;
  Future<void>? _restoreFuture;
  StreamSubscription<ProcessSignal>? _resizeSubscription;
  StreamSubscription<ProcessSignal>? _intSubscription;
  StreamSubscription<ProcessSignal>? _termSubscription;
  StreamSubscription<ProcessSignal>? _hupSubscription;

  // A hangup is observed up to twice — a terminal stdin reaching its end and
  // SIGHUP — but it is one event. Delivering it twice would read as the user
  // overruling a slow shutdown and force-exit past the app's cleanup.
  bool _hangupDelivered = false;

  // Whether stdin is a terminal in raw mode. Only then does its input ending
  // mean a hangup: in cooked mode Ctrl+D at the start of a line is an EOF.
  bool _rawTerminalInput = false;
  Timer? _flushTimer;
  Timer? _pasteIdleTimer;
  Timer? _graceTimer;
  bool _forceExitStarted = false;
  AppSignal? _pendingSignal;
  bool _pendingSignalDelivered = false;

  bool _pointerShapes = false;
  bool _pointerStackOwned = false;
  (Object, StackTrace)? _protocolWriteFailure;
  Future<void> _modeWriteTail = Future<void>.value();
  bool _active = false;
  bool _entryUsed = false;
  bool _entering = false;
  bool _restoring = false;
  int _lifecycleGeneration = 0;
  bool _handoffActive = false;
  Future<void> _handoffTail = Future<void>.value();
  Future<bool> _suspendTail = Future<bool>.value(false);
  Future<void> _resumeTail = Future<void>.value();
  bool _resuming = false;
  // True from the moment Ctrl+Z restoration begins until foregrounding
  // continues after SIGSTOP and re-enters our mode. Like [_handoffActive], it
  // gates frame [write]s while the shell owns the terminal and single-flights
  // [_suspend].
  bool _suspended = false;
  ActiveTerminalState? _terminalState;
  TerminalMode? get _mode => _terminalState?.effectiveMode;
  InlineTerminalRegion? _inline;
  Future<void> _inlineTail = Future<void>.value();
  int _inlineChanges = 0;
  bool _inlineNeedsRepaint = false;

  /// A cursor report that arrived after suspend, handoff, or restore began
  /// taking the terminal, with the size it was asked at. The region's
  /// release uses it to clear where the region actually is.
  (CellSize, CellOffset)? _inlineReleaseAnchor;

  @override
  bool get isInline => _inline != null;

  @internal
  AnsiRenderTarget get renderTarget =>
      _inline?.target ?? const AnsiRenderTarget.fullScreen();

  @internal
  void recordInlineCursor(CellOffset cursor) {
    final inline = _inline;
    if (inline != null &&
        _inlineChanges == 0 &&
        !_suspended &&
        !_handoffActive &&
        inline.isAllocated &&
        _physicalSize == inline.terminalSize) {
      inline.recordCursor(cursor);
    }
  }

  bool get _changedStdin => _terminalState?.rawInputOwned ?? false;
  bool get _wroteEnterSequences => _terminalState?.outputModesOwned ?? false;

  // A timed-out query keeps its response grammar active briefly so a slow SSH
  // reply cannot become input. Ordinary keystrokes continue through the parser
  // throughout; only complete response frames are consumed.
  @visibleForTesting
  static Duration lateProbeGrace = const Duration(milliseconds: 250);

  /// Ceiling on the whole startup handshake BEFORE a round trip is known — so
  /// also the total a terminal that answers nothing at all can ever spend.
  /// Unchanged by the adaptive path: no answer means no measurement, and no
  /// measurement means no growth.
  @visibleForTesting
  static Duration startupNegotiationBudget = const Duration(milliseconds: 500);

  /// Ceiling on the handshake once an answer HAS measured the link. Startup
  /// stops being free at some point even when the terminal is co-operating;
  /// this is where. It binds from a measured 250 ms round trip upward
  /// (8 x 250 ms), and at the far end of the measurable range — a link near
  /// [firstProbeTimeout] — it can clip the last probe off the sequence, which
  /// is the intended trade: a capability is worth waiting for, but not
  /// unboundedly, and the axis that loses simply keeps its safe default.
  @visibleForTesting
  static Duration maxStartupNegotiationBudget = const Duration(seconds: 2);

  /// Deadline for the ONE probe that has nothing to scale from.
  ///
  /// This number decides which links can negotiate at all: a terminal whose
  /// reply lands after it is indistinguishable from a terminal that will never
  /// reply, and the session degrades. 400 ms admits the whole terrestrial SSH
  /// population an agent TUI actually runs over (transatlantic ~90-150 ms,
  /// transpacific ~150-250 ms, congested mobile/VPN to ~350 ms) — and costs
  /// nothing to raise, because what bounds a silent terminal's startup is
  /// [startupNegotiationBudget], not this: the probes after the first are
  /// clamped to the budget that is left. An unanswered handshake spends this
  /// on the first probe plus [lateProbeGrace] on the quarantine — about
  /// 650 ms, against 500 ms when this was 150 ms — and, with nothing
  /// measured, never grows toward [maxStartupNegotiationBudget].
  @visibleForTesting
  static Duration firstProbeTimeout = const Duration(milliseconds: 400);

  /// Floor on a measured-RTT probe deadline: the value every probe used before
  /// the deadline became adaptive, so a local terminal (RTT well under 50 ms)
  /// negotiates on exactly the timings it always did.
  static const _minProbeTimeout = Duration(milliseconds: 150);

  /// Ceiling on a measured-RTT probe deadline. A safety net rather than a
  /// working limit — 3 x [firstProbeTimeout] is 1200 ms, so only a probe that
  /// is pathologically slower than the one that measured the link reaches it.
  static const _maxProbeTimeout = Duration(milliseconds: 1500);

  /// A probe gets three measured round trips. One is the reply itself; the
  /// other two are headroom for the jitter a congested link routinely shows
  /// and for probes that ask the terminal to do real work before answering
  /// (the width battery draws eight glyphs and reports eight cursor positions,
  /// against DA1's nothing).
  static const _probeTimeoutRoundTrips = 3;

  /// The handshake gets eight. Five are the sequence itself — keyboard, the
  /// keyboard re-query after a lifecycle rollback, synchronized output, image
  /// protocol, width battery — and the rest is slack for write/flush and for
  /// one probe timing out and handing the next a quarantine to wait through.
  static const _budgetRoundTrips = 8;
  ImageProtocol? _imageProtocolOverride;
  bool _synchronizedOutput = false;

  /// What the startup probe measured the terminal actually drawing.
  ///
  /// The ONE probe output the driver keeps: [capabilities] folds it into the
  /// derived width policy, and every downstream answer — layout's cell widths,
  /// the renderer's pin gate, the reported `ambiguousCharWidth` — is read back
  /// out of that policy. Null fields mean "unmeasured".
  WidthMeasurements _measuredGlyphWidths = const WidthMeasurements.empty();
  bool _nativeRawMode = false;

  // Whether this session can suspend for job control at all — native raw mode
  // in a job a job-control shell started — decided once when the session
  // enters. The Ctrl+Z gate, `TerminalSession.suspend`, and
  // `TerminalSession.supportsSuspend` all read this one answer.
  bool _shellJob = false;
  bool? _originalLineMode;
  bool? _originalEchoMode;

  @override
  CellSize get size => _inline?.size ?? _physicalSize;

  CellSize get _physicalSize {
    int cols;
    int rows;
    try {
      cols = _stdout.terminalColumns;
      rows = _stdout.terminalLines;
    } on StdoutException {
      // A guessed size could make an inline clear reach shell-owned rows.
      // Zero is explicitly rejected on acquire/resize; release treats it as
      // unknown geometry and leaves the old rows alone.
      if (_inline != null) return CellSize.zero;
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

  final StreamSubscription<ProcessSignal>? Function(
    ProcessSignal signal,
    void Function(ProcessSignal signal) onSignal,
  )?
  _signalWatcherOverride;

  StreamSubscription<ProcessSignal>? _watchSignal(
    ProcessSignal signal,
    void Function(ProcessSignal signal) onSignal,
  ) {
    final override = _signalWatcherOverride;
    if (override != null) return override(signal, onSignal);
    try {
      return signal.watch().listen(onSignal);
    } on SignalException {
      return null;
    } on UnsupportedError {
      return null;
    }
  }

  /// 128 + signal number (SIGHUP=1, SIGINT=2, SIGTERM=15): the
  /// conventional death-by-signal exit codes.
  static int _signalExitCode(AppSignal signal) => switch (signal) {
    AppSignal.interrupt => 130,
    AppSignal.terminate => 143,
    AppSignal.hangup => 129,
  };

  static AppSignal _appSignalOf(ProcessSignal signal) =>
      signal == ProcessSignal.sighup
      ? AppSignal.hangup
      : signal == ProcessSignal.sigterm
      ? AppSignal.terminate
      : AppSignal.interrupt;

  /// Last resort: restore the terminal and end the process with the
  /// conventional code. Used when the app ignores a signal past
  /// [signalGrace] or the user sends the same signal twice.
  void _forceExit(AppSignal signal) {
    if (_forceExitStarted) return;
    _forceExitStarted = true;
    final code = _signalExitCode(signal);
    final force = _forceExitOverride;
    var finished = false;
    Timer? deadline;
    void finish() {
      if (finished) return;
      finished = true;
      deadline?.cancel();
      if (force != null) {
        force(code);
      } else {
        exit(code);
      }
    }

    // Forced escalation must not await an arbitrary handoff callback forever.
    // Ordinary restoration still drains it and never claims ownership early.
    deadline = Timer(const Duration(milliseconds: 250), finish);
    unawaited(
      restore().then(
        (_) => finish(),
        onError: (Object _, StackTrace _) => finish(),
      ),
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

  void _deliverHangup() {
    if (_hangupDelivered) return;
    _hangupDelivered = true;
    deliverSignal(AppSignal.hangup);
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
    // Fold measurements + FLEURY_* overrides into the one derived policy every
    // geometry consumer shares (RFC 0019 §6.2), then read the reported
    // ambiguous width back OUT of it. One agreement rule, applied once: the
    // renderer's pin gate, layout, and `fleury diagnose` cannot disagree about
    // the evidence because there is only one derivation of it. An unevidenced
    // axis leaves the env-derived (conservative `wide`) default standing.
    final textPolicy = deriveTextPresentationPolicy(
      measurements: _measuredGlyphWidths,
      environment: environment,
    );
    final width = evidencedAmbiguousCharWidth(textPolicy);
    final withWidth = width == null
        ? merged
        : merged.copyWith(ambiguousCharWidth: width);
    return withWidth.copyWith(
      imageProtocol: isInline
          ? ImageProtocol.halfBlock
          : withWidth.imageProtocol,
      measuredWidths: _measuredGlyphWidths,
      textPolicy: textPolicy,
    );
  }

  @override
  Stream<TuiEvent> get events => _events.stream;

  @override
  bool get isActive => _active;

  @override
  bool get isInteractive => _stdoutIsTerminal;

  /// A cursor position report request, closed by the DA1 sentinel every
  /// terminal answers, so a terminal that sends no report still ends the
  /// exchange.
  static const _inlineCursorQuery = '\x1B[6n\x1B[c';

  /// Every `CSI ... R` in a reply: the terminal's cursor report, or a key
  /// press the parser held as one ([_takeCursorReport]).
  static final _reportShaped = RegExp(r'\x1b\[[0-9;:]*R');
  static final _cursorReport = RegExp(r'^\x1b\[(\d+);(\d+)R$');

  /// How long a live inline session waits for the terminal to report its
  /// cursor before it gives up on the terminal.
  ///
  /// A live session needs a report whenever it must find its region again:
  /// after the window is resized, and when the app comes back from suspend
  /// or handoff. Until one arrives, frames and mouse input stay gated, and
  /// nothing is painted at a guessed origin. A slow report is not a missing
  /// one, so the wait is long. Ten seconds covers an emulator reflowing deep
  /// scrollback, a starved CI runner (where a reply has taken over a second),
  /// and an SSH link riding out a few seconds of lost packets on TCP's
  /// retransmission backoff. A terminal still silent after that has most
  /// likely stopped answering for good, and the session ends with an error
  /// rather than keep taking input for a UI nobody can see.
  ///
  /// The clock restarts with every report, so a long window drag, answered
  /// throughout with reports for sizes it has already left, is never cut
  /// short. Startup keeps its one-second deadline: a terminal that has not
  /// answered yet has not shown that it can.
  @visibleForTesting
  static Duration inlineCursorReportBudget = const Duration(seconds: 10);

  /// How much longer a cursor report still has to land once suspend,
  /// handoff, or restore takes the terminal while it is on its way: the
  /// second every cursor query had before a live session waited longer, or
  /// three measured round trips on a slower link ([probeTimeoutFor]).
  ///
  /// The reply is waited for, not abandoned. It is still the region's own
  /// evidence, and the release clears the region where it puts it
  /// ([_inlineReleaseAnchor]). A reply consumed here also can't reach the
  /// shell, a handed-off child, or the next query. So a stalled terminal
  /// holds a suspend for at most this long, plus the late-reply quarantine.
  Duration get _inlineCursorDrain {
    final roundTrips = probeTimeoutFor(_queryRunner.measuredRoundTrip);
    const floor = Duration(seconds: 1);
    return roundTrips > floor ? roundTrips : floor;
  }

  /// How often a wait for a cursor report checks whether suspend, handoff,
  /// or teardown has taken the terminal ([_awaitInlineReply]).
  static const _inlineLivenessPoll = Duration(milliseconds: 50);

  /// The terminal's cursor report in [reply], 0-based, or null when it has
  /// none: a terminal can close the exchange with its DA1 sentinel alone.
  ///
  /// The report is the last `CSI <row>;<col> R` before the sentinel. While a
  /// query is pending, the parser takes every sequence of that shape for the
  /// report. A legacy keyboard sends a modified F3 in that shape too: Shift+F3
  /// is `CSI 1;2R`. So a press typed while the report was on its way is in
  /// [reply], ahead of the report. Each such press goes back through a fresh
  /// parser and reaches the app as the key it was, after any keys typed
  /// since. A press is still lost if its exchange times out or it lands in a
  /// late-reply quarantine, and it is taken for the report itself when the
  /// terminal answers with its DA1 sentinel alone.
  CellOffset? _takeCursorReport(List<int> reply) {
    final frames = [
      for (final match in _reportShaped.allMatches(String.fromCharCodes(reply)))
        match[0]!,
    ];
    CellOffset? report;
    if (frames.isNotEmpty) {
      final match = _cursorReport.firstMatch(frames.last);
      final row = int.tryParse(match?[1] ?? '');
      final col = int.tryParse(match?[2] ?? '');
      if (row != null && col != null && row > 0 && col > 0) {
        report = CellOffset(col - 1, row - 1);
        frames.removeLast();
      }
    }
    if (frames.isNotEmpty) {
      final keys = InputParser(keypadDecimal: _parser.keypadDecimal);
      for (final frame in frames) {
        keys.feed(frame.codeUnits, _sink);
      }
      keys.flush(_sink);
    }
    return report;
  }

  static bool _isInside(CellSize physical, CellOffset cursor) =>
      cursor.col >= 0 &&
      cursor.col < physical.cols &&
      cursor.row >= 0 &&
      cursor.row < physical.rows;

  /// Rejects a [cursor] outside the [physical] size its report was asked
  /// under. An impossible coordinate at a stable size must never become a
  /// guessed allocation via clamping.
  static void _checkInlineCursor(CellSize physical, CellOffset cursor) {
    if (!_isInside(physical, cursor)) {
      throw StateError(
        'The terminal reported a cursor outside its '
        '${physical.cols}x${physical.rows} viewport. Inline mode cannot '
        'reserve a safe region.',
      );
    }
  }

  Future<CellOffset> _queryInlineCursor({
    Duration timeout = const Duration(seconds: 1),
  }) async {
    try {
      final reply = await _queryRunner.request(
        _inlineCursorQuery,
        timeout: timeout,
      );
      final cursor = _takeCursorReport(reply);
      if (cursor != null) return cursor;
    } on TimeoutException {
      // A cursor report is required ownership evidence, not an optional
      // capability probe. Do not paint at a guessed origin on failure.
    }
    throw StateError(
      'The terminal did not report its cursor position. Inline mode cannot '
      'reserve a safe region; use TerminalMode.interactive instead.',
    );
  }

  void _scheduleInlineResize() {
    unawaited(_changeInline().catchError((Object _) {}));
  }

  /// Startup's anchor, which inline mode cannot start without: each query
  /// has [_queryInlineCursor]'s fixed deadline, and a missing report fails
  /// entry. A live session waits longer ([_awaitInlineAnchor]).
  Future<(CellSize, CellOffset)> _queryInlineAnchor() async {
    // A cursor report belongs to the dimensions it was requested under. The
    // window can change size while that reply is in flight (e.g. SSH); ask
    // again until one report is stable. Each query is bounded and
    // cancellable by restore().
    final generation = _lifecycleGeneration;
    while ((_active || _entering) && generation == _lifecycleGeneration) {
      final physical = _physicalSize;
      if (physical.isEmpty) {
        throw StateError('Inline mode requires a reportable terminal size.');
      }
      final cursor = await _queryInlineCursor();
      if (physical != _physicalSize) continue;
      // Only validate against the dimensions that produced this report.
      _checkInlineCursor(physical, cursor);
      return (physical, cursor);
    }
    throw StateError('Inline cursor acquisition was cancelled by teardown.');
  }

  /// Finds the live region's origin again, after the window is resized or
  /// when the terminal comes back from suspend or handoff ([reacquire]).
  ///
  /// One cursor query is in flight at a time, and a slow reply is waited
  /// for, not asked for again. A report carries nothing that ties it to its
  /// query, and a terminal answers in the order it reads, so a second query
  /// is never answered sooner than the first. It only puts two replies on
  /// the way: the first is taken as the second query's answer, for a window
  /// that may since have changed size, and the second lands after both
  /// exchanges have ended, where the input parser reads a cursor report as
  /// an F3 press. The late-reply quarantine ([lateProbeGrace]) holds a
  /// timed-out query's reply only briefly, and a stalled terminal answers
  /// every query at once when it recovers. So the query waits out
  /// [inlineCursorReportBudget], and the driver asks again only once a reply
  /// is in: at once if the window changed size while it was on its way, and
  /// if the reply held no report, after a pause that starts at the
  /// round-trip deadline the startup probes use ([probeTimeoutFor]) and
  /// doubles.
  ///
  /// When restore, or (unless [reacquire]) a suspend or handoff, takes the
  /// terminal mid-wait, the reply still gets [_inlineCursorDrain] to land.
  /// A report that does land, for the size it was asked at, is returned for
  /// the region's release; otherwise this returns null. Each of those
  /// transitions releases the region, and a return acquires a fresh anchor.
  ///
  /// While the reply is pending, the parser also holds a bare `ESC [` for
  /// it, so in a legacy keyboard mode Alt+[ and the key typed after it are
  /// lost, as they are whenever both arrive in one read: `ESC [ b` is
  /// rxvt's Shift+Down as much as Alt+[ then b.
  Future<(CellSize, CellOffset)?> _awaitInlineAnchor({
    required bool reacquire,
  }) async {
    final generation = _lifecycleGeneration;
    bool live() =>
        _active &&
        !_restoring &&
        generation == _lifecycleGeneration &&
        (reacquire || (!_suspended && !_handoffActive));
    final budget = inlineCursorReportBudget;
    final sinceReport = Stopwatch()..start();
    var pause = probeTimeoutFor(_queryRunner.measuredRoundTrip);
    while (live()) {
      final physical = _physicalSize;
      if (physical.isEmpty) {
        throw StateError('Inline mode requires a reportable terminal size.');
      }
      final remaining = budget - sinceReport.elapsed;
      if (remaining <= Duration.zero) break;
      final List<int> reply;
      try {
        reply = await _awaitInlineReply(
          _queryRunner.request(
            _inlineCursorQuery,
            timeout: remaining,
            interruptTimeout: _inlineCursorDrain,
          ),
          live,
        );
      } on TimeoutException {
        if (!live()) return null;
        break;
      } on StateError {
        if (!live()) return null;
        rethrow;
      }
      final cursor = _takeCursorReport(reply);
      if (!live()) {
        // The terminal was taken while this reply was on its way, and it
        // landed within the drain. Painting has been gated since the query
        // went out, so a report for the size it was asked at still places
        // the region, and its release can clear exactly those rows.
        return cursor != null &&
                physical == _physicalSize &&
                _isInside(physical, cursor)
            ? (physical, cursor)
            : null;
      }
      if (cursor == null) {
        final left = budget - sinceReport.elapsed;
        if (left <= Duration.zero) break;
        if (!await _pauseInline(pause < left ? pause : left, live)) {
          return null;
        }
        pause = pause * 2 < _maxProbeTimeout ? pause * 2 : _maxProbeTimeout;
        continue;
      }
      sinceReport.reset();
      // A report belongs to the size it was asked under: a resize while it
      // was on its way needs a fresh one, and a stale one is never validated.
      if (physical != _physicalSize) continue;
      _checkInlineCursor(physical, cursor);
      return (physical, cursor);
    }
    if (!live()) return null;
    final waited = budget.inMilliseconds % 1000 == 0
        ? '${budget.inSeconds} s'
        : '${budget.inMilliseconds} ms';
    throw StateError(
      'The terminal stopped reporting its cursor position: no report in '
      '$waited. Inline mode cannot find its region without one, and it does '
      'not paint at a guessed position.',
    );
  }

  /// [request]'s reply, waited for while [live] holds.
  ///
  /// Suspend, handoff, and restore gate the session without a word to this
  /// wait, then wait for the geometry change it belongs to before they
  /// release the terminal. Checking [live] every [_inlineLivenessPoll] is
  /// how it finds out. It then cuts the exchange to [_inlineCursorDrain]
  /// ([TerminalQueryRunner.interrupt]), so the reply still resolves soon
  /// after, if it lands in that time.
  Future<List<int>> _awaitInlineReply(
    Future<List<int>> request,
    bool Function() live,
  ) {
    final poll = Timer.periodic(_inlineLivenessPoll, (timer) {
      if (live()) return;
      timer.cancel();
      _queryRunner.interrupt();
    });
    return request.whenComplete(poll.cancel);
  }

  /// Waits [pause], or less once [live] stops holding; returns whether it
  /// held throughout.
  Future<bool> _pauseInline(Duration pause, bool Function() live) async {
    final clock = Stopwatch()..start();
    while (live()) {
      final left = pause - clock.elapsed;
      if (left <= Duration.zero) return true;
      await Future<void>.delayed(
        left < _inlineLivenessPoll ? left : _inlineLivenessPoll,
      );
    }
    return false;
  }

  @override
  Future<void> resizeInline(int rows) {
    final inline = _inline;
    if (inline == null || !_active || _restoring) {
      throw StateError('No active inline terminal session.');
    }
    inline.requestRows(rows);
    return _changeInline();
  }

  Future<void> _changeInline({bool reacquire = false}) async {
    final inline = _inline;
    if (inline == null) return;
    final previous = _inlineTail;
    final released = Completer<void>();
    _inlineTail = released.future;
    _inlineChanges++;
    try {
      await previous;
      if (!_active ||
          _restoring ||
          (!reacquire && (_suspended || _handoffActive))) {
        return;
      }
      final generation = _lifecycleGeneration;
      final physical = _physicalSize;
      if (physical.isEmpty) {
        throw StateError('Inline viewport needs a nonempty terminal.');
      }
      if (inline.isAllocated &&
          physical == inline.terminalSize &&
          inline.size.rows == inline.requestedRows.clamp(1, physical.rows)) {
        return;
      }
      // Cancel capture before changing coordinate systems. Input can keep
      // updating widget state while frame writes and mouse reports are gated.
      if (!_events.isClosed) {
        _events.add(
          const MouseEvent(
            kind: MouseEventKind.cancel,
            button: MouseButton.none,
            col: 0,
            row: 0,
          ),
        );
      }
      _inlineReleaseAnchor = null;
      final anchor = inline.isAllocated && physical == inline.terminalSize
          ? (physical, inline.terminalCursor)
          : await _awaitInlineAnchor(reacquire: reacquire);
      if (anchor == null) return;
      if (!_active ||
          _restoring ||
          generation != _lifecycleGeneration ||
          (!reacquire && (_suspended || _handoffActive))) {
        // Suspend, handoff, or restore took the terminal while the report
        // was on its way. Each releases the region, and the report says
        // where it is; a return from suspend or handoff acquires anew.
        _inlineReleaseAnchor = anchor;
        return;
      }
      final (terminal, cursor) = anchor;
      _recordInlineLease(region: false);
      final bytes = inline.isAllocated
          ? inline.resize(terminal, cursor)
          : inline.acquire(terminal, cursor);
      _stdout.write(bytes);
      await _stdout.flush();
      if (!_active || _restoring || generation != _lifecycleGeneration) return;
      _recordInlineLease();
      _inlineNeedsRepaint = true;
    } catch (error, stack) {
      if (_active && !_restoring && !_events.isClosed) {
        _events.addError(error, stack);
      }
      rethrow;
    } finally {
      _inlineChanges--;
      released.complete();
      if (_inlineChanges == 0 && _inlineNeedsRepaint) {
        _inlineNeedsRepaint = false;
        if (_active && !_restoring && !_events.isClosed) {
          _events.add(ResizeEvent(size));
        }
      }
    }
  }

  void _releaseInline() {
    final inline = _inline;
    if (inline != null) {
      // Recovery metadata must never prevent ordinary terminal cleanup.
      try {
        _recordInlineLease(region: false);
      } catch (_) {}
      final physical = _physicalSize;
      _stdout.write(
        inline.release(physical, cursor: _takeInlineReleaseAnchor(physical)),
      );
    }
  }

  /// The report a pending resize received as the terminal was being taken
  /// ([_inlineReleaseAnchor]), if it was asked at [physical]. Painting has
  /// been gated since, so it still places the region.
  CellOffset? _takeInlineReleaseAnchor(CellSize physical) {
    final anchor = _inlineReleaseAnchor;
    _inlineReleaseAnchor = null;
    if (anchor == null || anchor.$1 != physical) return null;
    return anchor.$2;
  }

  /// Shutdown gates new frames first, but keeps the input lease until this
  /// bounded ownership check completes. A resize can arrive before SIGWINCH is
  /// processed or while another cursor query is pending. Settle that exchange,
  /// whose report places the region if the window kept the size it was asked
  /// at; otherwise use a fresh report. Either way, clear only the surviving
  /// rows, without reserving or repainting a new UI on the way out.
  Future<void> _releaseInlineForRestore() async {
    await _inlineTail;
    final inline = _inline;
    if (inline == null || !inline.isAllocated) return;
    final settled = _physicalSize;
    final reported = _takeInlineReleaseAnchor(settled);
    if (reported != null) {
      try {
        _recordInlineLease(region: false);
      } catch (_) {}
      _stdout.write(inline.release(settled, cursor: reported));
      return;
    }
    final clock = Stopwatch()..start();
    const budget = Duration(seconds: 1);
    while (_physicalSize != inline.terminalSize && clock.elapsed < budget) {
      final physical = _physicalSize;
      if (physical.isEmpty) break;
      try {
        final cursor = await _queryInlineCursor(
          timeout: budget - clock.elapsed,
        );
        if (physical != _physicalSize) continue;
        // Validation is part of release: invalid evidence cannot authorize a
        // clear. Recovery-file failure must not prevent terminal restoration.
        try {
          _recordInlineLease(region: false);
        } catch (_) {}
        if (physical != _physicalSize) continue;
        _stdout.write(inline.release(physical, cursor: cursor));
        return;
      } on StateError {
        // Missing or invalid reports retain the non-destructive fallback.
        break;
      }
    }
    _releaseInline();
  }

  void _recordInlineLease({
    bool active = true,
    bool region = true,
    TerminalMode? mode,
    bool stackStateUnknown = false,
  }) {
    final effective = mode ?? _mode;
    if (effective == null) return;
    final inline = _inline;
    final allocated = region && inline != null && inline.isAllocated;
    writeInlineTerminalLease(
      Platform.environment[inlineTerminalLeaseEnvironment],
      mode: effective,
      active: active,
      terminal: allocated ? inline.terminalSize : null,
      top: allocated ? inline.target.top : null,
      rows: allocated ? inline.size.rows : null,
      pointerStackOwned: _pointerStackOwned,
      stackStateUnknown: stackStateUnknown || _protocolWriteFailure != null,
    );
  }

  @override
  Future<TerminalSessionProfile> enter(TerminalMode mode) async {
    if (_active) {
      throw StateError('PosixTerminalDriver.enter called on an active driver.');
    }
    if (_entryUsed) {
      throw StateError(
        'PosixTerminalDriver has already been entered or restored. '
        'Create a new driver for each runApp invocation.',
      );
    }
    _entryUsed = true;
    if (mode.inlineRows != null) {
      if (!_stdinIsTerminal || !_stdoutIsTerminal) {
        throw StateError(
          'Inline mode requires terminal input and output for cursor reporting.',
        );
      }
      _inline = InlineTerminalRegion(mode.inlineRows!);
    }
    // Reject a second same-process interactive session up front, before any
    // terminal mutation, so the terminal is left untouched and the failure is
    // legible (see [_globalStdinConsumed]).
    if (!_usesNativeInput && identical(_stdin, stdin) && _globalStdinConsumed) {
      throw StateError(
        'This redirected stdin stream was already consumed by an earlier '
        'runApp(). Dart stdin streams can only be subscribed to once. '
        'Sequential native sessions require terminal input on macOS or Linux.',
      );
    }
    _restoring = false;
    _pointerShapes = false;
    _entering = true;
    final enterGeneration = ++_lifecycleGeneration;
    _terminalState = ActiveTerminalState(
      requestedMode: mode,
      effectiveMode: _effectiveMode(mode),
    );
    _sink.target = _events;

    // Arm process-termination signals BEFORE the first terminal mutation. The
    // startup probes below hold the driver for the negotiation budget (500 ms
    // on a silent terminal, up to 2 s on a measured slow link — see
    // [_nextProbeTimeout]); installing these afterward left a reproducible
    // window where SIGTERM killed the process after the alt screen was entered
    // but before any cleanup handler existed. A signal that lands before
    // runApp subscribes is retained and replayed by
    // [_deliverPendingSignalToNewListener].
    // The ack tells a dev supervisor that the OS delivered this signal HERE
    // (a tty Ctrl+C reaches the whole foreground group), so it must not
    // forward its own copy on top of an in-progress teardown. Posted from the
    // watcher rather than from [deliverSignal], which is also driven
    // synthetically by tests: only a real delivery is evidence.
    _intSubscription = _watchSignal(ProcessSignal.sigint, (_) {
      postDevSignalAck(ProcessSignal.sigint);
      deliverSignal(AppSignal.interrupt);
    });
    _termSubscription = _watchSignal(ProcessSignal.sigterm, (_) {
      postDevSignalAck(ProcessSignal.sigterm);
      deliverSignal(AppSignal.terminate);
    });
    // Unwatched, SIGHUP's default action kills the process on the spot: no
    // State.dispose, no app cleanup. The terminal is already gone then, so
    // restore's writes fail and are contained like any teardown fault.
    _hupSubscription = _watchSignal(ProcessSignal.sighup, (_) {
      postDevSignalAck(ProcessSignal.sighup);
      _deliverHangup();
    });

    // Raw mode only makes sense on a terminal stdin; reading lineMode/
    // echoMode throws on a pipe, so guard rather than catch. Piped input
    // (stdin not a terminal, e.g. scripted keystrokes) still streams in
    // via the listener below.
    if (mode.rawInput && _stdinIsTerminal) {
      _rawTerminalInput = true;
      // Acquisition can mutate termios and then throw. Retain the cleanup
      // obligation before calling it, just as we do before output writes.
      _terminalState!.rawInputOwned = true;
      _nativeRawMode = true;
      _nativeRawMode = _terminalModeController.enableRawMode();
      if (!_nativeRawMode && !suspendOnCtrlZ) {
        // The Dart fallback leaves ISIG enabled, so Ctrl+Z would stop the
        // process before the application's cleanup handler could see it.
        await restore();
        throw StateError(
          'Application-owned Ctrl+Z requires native POSIX raw mode.',
        );
      }
      if (!_nativeRawMode) {
        _originalLineMode = _stdin.lineMode;
        _originalEchoMode = _stdin.echoMode;
        if (!_setDartRawMode()) {
          throw StateError('Cannot enter terminal input mode.');
        }
      }
    }
    // Only a job-control shell can continue a stopped job. Without one — a
    // terminal emulator, a tmux pane, or `ssh -t host app` running the app
    // directly — a stop would be permanent, so this session never suspends.
    _shellJob =
        _nativeRawMode && (_shellJobOverride ?? PosixJobControl.isShellJob());

    // Screen-control sequences only when stdout is a real terminal — writing
    // them into a pipe or file would just corrupt it.
    await _enterOutputMode(_mode!);
    _checkStillEntering(enterGeneration);

    await _startInput();
    _checkStillEntering(enterGeneration);

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
    // async error, and these probes hold the driver for the negotiation
    // budget — 500 ms silent, up to 2 s on a measured slow link). Never
    // reactivate a driver whose lifecycle moved on — and check BETWEEN the
    // probes, not only after them: `restore()` nulls `_terminalState`, so a
    // teardown that lands mid-negotiation must be reported as this StateError
    // rather than crashing on the next read of the state it tore down.
    final negotiationClock = Stopwatch()..start();
    await _negotiateKeyboard(negotiationClock);
    final negotiated = _checkStillEntering(enterGeneration);
    await _probeCapabilities(negotiated.isFullScreen, negotiationClock);
    _checkStillEntering(enterGeneration);

    if (_inline != null) {
      try {
        final (terminal, cursor) = await _queryInlineAnchor();
        _checkStillEntering(enterGeneration);
        _recordInlineLease(region: false);
        _stdout.write(_inline!.acquire(terminal, cursor));
        await _stdout.flush();
        _checkStillEntering(enterGeneration);
        _recordInlineLease();
      } catch (_) {
        await restore();
        rethrow;
      }
    }

    _resizeSubscription = _watchSignal(ProcessSignal.sigwinch, (_) {
      if (isInline) {
        _scheduleInlineResize();
      } else if (!_events.isClosed) {
        _events.add(ResizeEvent(size));
      }
    });

    if (_pointerShapes && !_pointerStackOwned) {
      await _writeModeChange(
        pushPointerShape,
        changesStack: true,
        beforeWrite: () => _pointerStackOwned = true,
      );
      _checkStillEntering(enterGeneration);
    }
    _active = true;
    _entering = false;
    _emitPendingSignalIfListened();
    final terminal = capabilities;
    return TerminalSessionProfile.ansi(
      terminal: terminal,
      keyboard: keyboardCapabilities,
      synchronizedOutput: _synchronizedOutput,
      pointerShapes: _pointerShapes,
    );
  }

  Future<void> _startInput() async {
    if (_usesNativeInput) {
      if (_nativeInput != null) {
        throw StateError('Terminal input is already owned.');
      }
      final input = _nativeInput = PosixInputLease(
        onBytes: _receiveInput,
        onDone: _inputEnded,
        onError: _inputFailed,
      );
      await input.start();
    } else {
      final subscription = _stdinSubscription;
      if (subscription != null) {
        subscription.resume();
      } else {
        _stdinSubscription = _stdin.listen(
          _receiveInput,
          onError: _inputFailed,
          onDone: _inputEnded,
          cancelOnError: false,
        );
      }
    }
  }

  void _receiveInput(List<int> bytes) {
    _parser.feed(bytes, _sink, responseSink: _queryRunner);
    _scheduleFlush();
    _schedulePasteIdleFlush();
  }

  void _inputFailed(Object error, StackTrace stack) {
    if (_rawTerminalInput && isTerminalGoneError(error)) {
      _deliverHangup();
    } else if (!_events.isClosed) {
      _events.addError(error, stack);
    }
  }

  void _inputEnded() {
    _cancelInputTimers();
    _parser.finish(_sink);
    if (_rawTerminalInput) {
      _deliverHangup();
    } else if (!_events.isClosed) {
      unawaited(_events.close());
    }
  }

  void _cancelInputTimers() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pasteIdleTimer?.cancel();
    _pasteIdleTimer = null;
  }

  Future<void> _releaseInput({bool finalRelease = false}) async {
    // Keep consuming replies until the last bounded query/quarantine has
    // settled, then stop reading. A later owner must not inherit our parser.
    await _queryRunner.suspend();
    final input = _nativeInput;
    if (input != null) {
      await input.stop();
      if (identical(_nativeInput, input)) _nativeInput = null;
    }
    final subscription = _stdinSubscription;
    if (finalRelease) {
      await subscription?.cancel();
      _stdinSubscription = null;
      if (subscription != null && identical(_stdin, stdin)) {
        _globalStdinConsumed = true;
      }
    } else {
      subscription?.pause();
    }
    _cancelInputTimers();
    _parser.endInputOwnership(_sink);
  }

  Future<void> _reacquireInput() async {
    _queryRunner.resume();
    await _startInput();
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
    if (_restoring ||
        enterGeneration != _lifecycleGeneration ||
        state == null) {
      throw StateError(
        'PosixTerminalDriver was restored while enter was negotiating.',
      );
    }
    return state.effectiveMode;
  }

  /// Every capability query that does not feed the keyboard negotiation —
  /// synchronized output, the image protocol, glyph widths — in ONE exchange.
  ///
  /// They are independent of each other and gated only by the environment
  /// and by the terminal having answered at all (a silent terminal has no
  /// budget left here, so nothing is sent to it). Sent one after another they
  /// cost a round trip each, which over a slow link is most of startup;
  /// batched, the terminal answers them in order in one round trip and
  /// [TerminalQueryRunner.requestBatch] hands back one segment per query.
  /// The width probe paints glyphs and needs the alternate screen; a query
  /// the terminal does not answer leaves its capability conservative,
  /// exactly as a timed-out probe did. A terminal that answered nothing at
  /// all during keyboard negotiation is sent none of this ([_terminalSilent]):
  /// the sequential path relied on the remaining budget being shorter than
  /// the quarantine grace for that, which held by arithmetic, not by design.
  Future<void> _probeCapabilities(
    bool onAlternateScreen,
    Stopwatch negotiationClock,
  ) async {
    final syncOverride = synchronizedOutputOverrideFromEnvironment(
      Platform.environment,
    );
    _synchronizedOutput = syncOverride ?? false;
    _pointerShapes = false;
    if (!_stdoutIsTerminal || !_changedStdin) return;
    if (_terminalSilent) return;
    // Order matters twice over. Segmentation is positional, so a query the
    // terminal chokes on takes every later reply with it: the APC is the one
    // an unidentified terminal is most likely to mishandle, so it goes last,
    // where it can only cost itself. And each query that can leave marks on
    // screen ends with an erase — the width battery's own, and a cleanup
    // variant of the image query for a terminal that prints the APC as text.
    final queries = <(_CapabilityProbe, String)>[
      if (_mode!.mouseMotion &&
          !detectTerminalMultiplexerFromEnvironment(Platform.environment))
        (_CapabilityProbe.pointerShapes, pointerShapesQuery),
      if (syncOverride == null)
        (_CapabilityProbe.synchronizedOutput, synchronizedOutputQuery),
      if (onAlternateScreen &&
          widthProbeIsPermittedByEnvironment(Platform.environment))
        (_CapabilityProbe.glyphWidths, glyphWidthQuery),
      if (!isInline && _imageProbePermitted())
        (_CapabilityProbe.image, kittyGraphicsQueryWithCleanup),
    ];
    if (queries.isEmpty) return;
    final timeout = _nextProbeTimeout(negotiationClock);
    if (timeout == null) return;
    final clock = Stopwatch()..start();
    final List<List<int>?> replies;
    try {
      replies = await _queryRunner.requestBatch([
        for (final (_, query) in queries) query,
      ], timeout: timeout);
    } on Object {
      return;
    }
    for (var i = 0; i < queries.length; i++) {
      final reply = replies[i];
      if (reply == null) continue;
      switch (queries[i].$1) {
        case _CapabilityProbe.pointerShapes:
          _pointerShapes = parsePointerShapesReply(reply);
        case _CapabilityProbe.synchronizedOutput:
          _synchronizedOutput = parseSynchronizedOutputReply(
            reply,
            elapsed: clock.elapsed,
          );
        case _CapabilityProbe.image:
          final detected = parseImageProtocolReply(
            reply,
            elapsed: clock.elapsed,
          );
          if (detected != null) _imageProtocolOverride = detected;
        case _CapabilityProbe.glyphWidths:
          _measuredGlyphWidths = parseGlyphWidthReply(reply);
      }
    }
  }

  /// The image query is only sent where the environment gives no answer and
  /// no multiplexer sits in between (a multiplexer would swallow or garble
  /// the APC), and unless `FLEURY_IMAGE_PROBE=0`.
  bool _imageProbePermitted() {
    final flag = Platform.environment['FLEURY_IMAGE_PROBE'];
    if (flag == '0' || flag == 'false') return false;
    if (detectTerminalMultiplexerFromEnvironment(Platform.environment)) {
      return false;
    }
    return detectImageProtocolFromEnvironment(Platform.environment) ==
        ImageProtocol.halfBlock;
  }

  int? _confirmedKeyboardFlags;

  /// True once a keyboard probe was sent and the terminal never answered it:
  /// nothing else is worth asking, and an unrecognizing terminal would only
  /// print the later queries.
  bool _terminalSilent = false;

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
    _terminalSilent = false;
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
    if (flags == null && _queryRunner.measuredRoundTrip == null) {
      _terminalSilent = true;
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
      final state = _terminalState;
      if (state == null || _restoring) return; // restored mid-probe
      await _writeModeChange(
        '\x1B[<1u'
        '\x1B[>${KeyboardProtocolMode.disambiguated.requestedFlags}u',
        changesStack: true,
        onSuccess: () {
          state.effectiveMode = terminalModeWithKeyboardProtocol(
            effective,
            KeyboardProtocolMode.disambiguated,
          );
        },
      );
      if (_restoring || !identical(_terminalState, state)) return;
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
    final state = _terminalState;
    if (state == null || _restoring) return;
    await _writeModeChange(
      '\x1B[<1u',
      changesStack: true,
      onSuccess: () {
        _confirmedKeyboardFlags = null;
        state.effectiveMode = terminalModeWithKeyboardProtocol(
          effective,
          KeyboardProtocolMode.legacy,
        );
      },
    );
  }

  /// Lifecycle is only safe to keep when text survives it: event types (2),
  /// all-keys-as-escapes (8) and associated text (16) must ALL be active.
  /// Flag 4 is an optional positional enhancement.
  static bool _lifecycleIsSafe(int flags) =>
      flags & 0x02 != 0 && flags & 0x08 != 0 && flags & 0x10 != 0;

  /// The deadline for the next startup probe, or null when the handshake has
  /// no budget left and the remaining probes must be skipped.
  ///
  /// Deadlines are adaptive because a fixed one is a latency cliff: with every
  /// probe capped at 150 ms, a link slower than about 130 ms round trip timed
  /// ALL of them out and the session silently fell back on every axis at once
  /// — legacy keyboard, no synchronized output, no image protocol, `wide`
  /// ambiguous width — which is the ordinary condition of an agent TUI over
  /// SSH, not an edge case.
  ///
  /// The first answered exchange measures the link
  /// ([TerminalQueryRunner.measuredRoundTrip]); every probe after it, and the
  /// aggregate budget, scale to that measurement within fixed bounds. Until
  /// something answers there is nothing to scale from, so the first probe runs
  /// on [firstProbeTimeout] and the budget stays at
  /// [startupNegotiationBudget]: a terminal that never answers must not be
  /// able to hang startup, and it cannot lengthen its own deadline by staying
  /// silent.
  Duration? _nextProbeTimeout(Stopwatch negotiationClock) {
    final roundTrip = _queryRunner.measuredRoundTrip;
    final remaining =
        negotiationBudgetFor(roundTrip) - negotiationClock.elapsed;
    if (remaining <= Duration.zero) return null;
    final perProbe = probeTimeoutFor(roundTrip);
    return remaining < perProbe ? remaining : perProbe;
  }

  /// Per-probe deadline for a link measured at [measuredRoundTrip], or
  /// [firstProbeTimeout] when nothing has answered yet.
  @visibleForTesting
  static Duration probeTimeoutFor(Duration? measuredRoundTrip) {
    if (measuredRoundTrip == null) return firstProbeTimeout;
    final scaled = measuredRoundTrip * _probeTimeoutRoundTrips;
    if (scaled < _minProbeTimeout) return _minProbeTimeout;
    if (scaled > _maxProbeTimeout) return _maxProbeTimeout;
    return scaled;
  }

  /// Aggregate handshake budget for a link measured at [measuredRoundTrip], or
  /// [startupNegotiationBudget] when nothing has answered yet.
  @visibleForTesting
  static Duration negotiationBudgetFor(Duration? measuredRoundTrip) {
    if (measuredRoundTrip == null) return startupNegotiationBudget;
    final scaled = measuredRoundTrip * _budgetRoundTrips;
    if (scaled < startupNegotiationBudget) return startupNegotiationBudget;
    if (scaled > maxStartupNegotiationBudget) {
      return maxStartupNegotiationBudget;
    }
    return scaled;
  }

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

  /// Build only: ownership changes after the complete write and flush.
  String _exitSequences(TerminalMode mode) {
    if (_protocolWriteFailure != null) {
      // A failed stack operation may already have reached the terminal. A
      // second pop could remove our caller's frame. Common mode resets are
      // repeatable; they cannot prove the unknown stack was restored.
      return buildTerminalExitSequences(
        terminalModeWithKeyboardProtocol(mode, KeyboardProtocolMode.legacy),
      );
    }
    final pointer = _pointerStackOwned ? popPointerShape : '';
    return pointer + buildTerminalExitSequences(mode);
  }

  Future<void> _writeModeChange(
    String bytes, {
    required bool changesStack,
    bool restoring = false,
    void Function()? beforeWrite,
    void Function()? onSuccess,
  }) {
    final previous = _modeWriteTail;
    final completion = Completer<void>();
    // Publish before invoking a custom sink, which can synchronously request
    // restoration. The tail always settles, but only after the actual flush.
    _modeWriteTail = completion.future.then<void>(
      (_) {},
      onError: (Object _) {},
    );
    Future<void> write() async {
      await previous;
      if (_restoring && !restoring) {
        throw StateError('Terminal session closed before mode write.');
      }
      final failed = _protocolWriteFailure;
      if (changesStack && failed != null) {
        Error.throwWithStackTrace(failed.$1, failed.$2);
      }
      // Claim only after the queued operation has passed its cancellation
      // check. Successful mutation bookkeeping is part of this same drained
      // operation, including when restore starts while flush is pending.
      if (changesStack) {
        // Publish conservative recovery before touching a protocol stack. If
        // this write fails, no terminal mutation follows. A stale committed
        // journal must never authorize a second pop after a handled failure.
        _recordInlineLease(stackStateUnknown: true);
      }
      beforeWrite?.call();
      try {
        _stdout.write(bytes);
        await _stdout.flush();
      } catch (error, stack) {
        if (changesStack && !_savedOutputIsGone(error)) {
          _protocolWriteFailure ??= (error, stack);
          try {
            _recordInlineLease();
          } catch (_) {}
        }
        rethrow;
      }
      onSuccess?.call();
      _recordInlineLease(active: _wroteEnterSequences);
    }

    write().then(completion.complete, onError: completion.completeError);
    return completion.future;
  }

  void _stopInputReports() {
    final mode = _mode;
    if (mode == null || !_wroteEnterSequences || _handoffActive || _suspended) {
      return;
    }
    // These resets are repeatable. Do not pop the keyboard/pointer stacks or
    // restore cooked input here; those still belong to the ordered teardown.
    // Enqueue immediately without waiting for a flush or draining typeahead.
    _stdout.write(
      '\x1B[?1006l\x1B[?1003l\x1B[?1002l\x1B[?1000l'
      '${mode.focusReporting ? '\x1B[?1004l' : ''}'
      '${mode.bracketedPaste ? '\x1B[?2004l' : ''}',
    );
  }

  Future<void> _exitOutputMode(
    TerminalMode mode, {
    bool restoring = false,
  }) async {
    final uncertain = _protocolWriteFailure != null;
    final changesStack =
        !uncertain && (mode.kittyKeyboard || _pointerStackOwned);
    await _writeModeChange(
      _exitSequences(mode),
      changesStack: changesStack,
      restoring: restoring,
      onSuccess: () {
        if (!uncertain) _pointerStackOwned = false;
        _terminalState?.outputModesOwned = false;
      },
    );
  }

  bool _interceptParsedEvent(TuiEvent event) {
    final inline = _inline;
    if (inline != null && event is MouseEvent) {
      if (!_active ||
          _inlineChanges > 0 ||
          !inline.isAllocated ||
          _suspended ||
          _handoffActive ||
          _physicalSize != inline.terminalSize) {
        return true;
      }
      final local = inline.target.toLocal(CellOffset(event.col, event.row));
      if (!_events.isClosed) {
        _events.add(
          MouseEvent(
            kind: event.kind,
            button: event.button,
            col: local.col,
            row: local.row,
            modifiers: event.modifiers,
          ),
        );
      }
      return true;
    }
    // Everything else — Ctrl+Z included — is the application's input. A
    // Ctrl+Z press it leaves unhandled comes back as [requestCtrlZSuspend].
    return false;
  }

  /// [requestCtrlZSuspend]: the orderly suspend, when this session owns one.
  bool _suspendForCtrlZ() {
    if (!suspendOnCtrlZ) return false;
    final suspension = _requestSuspend();
    if (suspension == null) return false;
    unawaited(suspension);
    return true;
  }

  /// `TerminalSession.supportsSuspend`: whether this session can suspend at
  /// all — the keyboard in native raw mode, in a job a job-control shell
  /// started — as [_requestSuspend] decides it.
  @internal
  @override
  bool get supportsSuspend => _shellJob;

  /// `TerminalSession.suspend`: the suspension an unhandled Ctrl+Z starts, on
  /// the application's request. [suspendOnCtrlZ] governs only that press, so
  /// it does not refuse this.
  @internal
  @override
  Future<bool> suspend() => _requestSuspend() ?? Future<bool>.value(false);

  /// Starts the orderly suspend — or joins the one under way — when this
  /// session can suspend now; null when it can't. Completes with whether the
  /// job stopped.
  Future<bool>? _requestSuspend() {
    // cfmakeraw disables ISIG, so the terminal delivers Ctrl+Z as 0x1a rather
    // than the kernel stopping us; without native raw mode the kernel owns
    // job control and no press is ever read. Without a job-control shell,
    // nothing would continue the stopped job ([_shellJob] covers both). A
    // handed-off terminal belongs to the child until it returns.
    if (!_active || !_shellJob || _handoffActive) return null;
    // The transition publishes its failure on [events], where runApp treats
    // it as fatal. Do not also send it to the survivable widget-error zone.
    return _suspend().catchError((Object _) => false);
  }

  void _setRawMode() {
    // Configuration survives a handoff; rawInputOwned describes only the
    // current borrow. Retain ownership on partial failure so cleanup retries.
    _terminalState?.rawInputOwned = true;
    final ok = _nativeRawMode
        ? _terminalModeController.enableRawMode()
        : _setDartRawMode();
    if (!ok) throw StateError('Cannot re-enter terminal input mode.');
  }

  Future<void> _enterOutputMode(TerminalMode mode) async {
    if (!_stdoutIsTerminal) return;
    final pushesPointer = _pointerShapes && !_pointerStackOwned;
    final enter =
        buildTerminalEnterSequences(mode) +
        (pushesPointer ? pushPointerShape : '');
    if (enter.isEmpty) return;
    await _writeModeChange(
      enter,
      changesStack: mode.kittyKeyboard || pushesPointer,
      beforeWrite: () {
        _terminalState?.outputModesOwned = true;
        if (pushesPointer) _pointerStackOwned = true;
      },
    );
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
    if (!_changedStdin) return true;
    if (_nativeRawMode) {
      final ok = _terminalModeController.restoreMode();
      if (ok) _terminalState?.rawInputOwned = false;
      return ok;
    }
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
    if (ok) _terminalState?.rawInputOwned = false;
    return ok;
  }

  /// Ctrl+Z: restore the terminal for the shell, stop this process's job,
  /// then continue here after the shell's `fg` sends SIGCONT and repaint.
  /// Completes with whether the job stopped — in production, once it has
  /// been continued and re-entered.
  ///
  /// Dart deliberately does not allow watching SIGTSTP/SIGCONT. Production
  /// therefore reaches this method from a parsed Ctrl+Z press (ISIG is off in
  /// our cfmakeraw mode) that the application left unhandled — runApp calls
  /// [requestCtrlZSuspend] — or from the application's own request
  /// ([suspend]), and stops the job with uncatchable SIGSTOP
  /// ([PosixJobControl.stopJob]). An
  /// external `kill -TSTP` cannot be observed safely by pure Dart and may
  /// bypass this orderly path; callers should use the terminal's Ctrl+Z
  /// job-control chord.
  Future<bool> _suspend() {
    if (_suspended) return _suspendTail;
    return _suspendTail = _suspendImpl().catchError((
      Object error,
      StackTrace stack,
    ) {
      _failTerminalTransition(error, stack);
      Error.throwWithStackTrace(error, stack);
    });
  }

  void _failTerminalTransition(Object error, StackTrace stack) {
    if (!_active || _restoring) return;
    // A failed ownership transition is not a recoverable widget error. Stop
    // frames and new operations immediately, then let runApp restore the tty.
    _active = false;
    if (!_events.isClosed) _events.addError(error, stack);
  }

  Future<bool> _suspendImpl() async {
    final mode = _mode;
    if (mode == null) return false;
    final lifecycleGeneration = _lifecycleGeneration;
    // Single-flight: a rapid second Ctrl+Z (or one queued while the awaits
    // below run) must not re-write exit sequences or repeat the self-stop.
    if (_suspended) return false;
    // A native raw-mode controller is what makes Ctrl+Z observable as a byte;
    // production resumes inline after SIGSTOP/SIGCONT. Tests use the explicit
    // self-stop seam and drive debugResume themselves.
    // Parent stdin is paused during a child handoff, so production cannot
    // legitimately receive the chord then. A test seam or already-queued
    // callback must not stop the parent while the child owns the terminal.
    if ((!_nativeRawMode && _selfStopOverride == null) || _handoffActive) {
      return false;
    }
    _stopInputReports();
    _suspended = true;
    await _inlineTail;
    if (!_active || _restoring || lifecycleGeneration != _lifecycleGeneration) {
      return false;
    }
    // Input authority leaves with the terminal: whatever the user is holding
    // will be released into the shell, and this driver will never see the
    // release. Say so — the runtime recovers held keys on a focus-out (RFC
    // 0020 §10) — or every held key stays held across the suspend, a hold
    // never ends, and the first re-press of two stuck keys trips the
    // phase-violation counter and demotes an honest terminal to press-only.
    if (!_events.isClosed) {
      _events.add(const TerminalFocusEvent(focused: false));
    }
    await _releaseInput();
    if (!_active || _restoring || lifecycleGeneration != _lifecycleGeneration) {
      return false;
    }
    // Return a known terminal state before stopping. A partial output release
    // cannot safely hand the shell its terminal; propagate the failure to the
    // runtime's cleanup instead of self-stopping in an uncertain screen mode.
    if (!_handoffActive) {
      final inputRestored = !_changedStdin || _restoreCookedMode();
      _releaseInline();
      if (_wroteEnterSequences) {
        await _exitOutputMode(mode);
      } else {
        await _stdout.flush();
      }
      // restore() can run while the flush yields (SIGTERM, stdin EOF, or an
      // app-requested exit). A stale suspend continuation must never stop the
      // already-restored process.
      if (_handoffActive) {
        _suspended = false;
        return false;
      }
      if (!_active ||
          _restoring ||
          lifecycleGeneration != _lifecycleGeneration ||
          !identical(_mode, mode) ||
          !_suspended) {
        return false;
      }
      if (!inputRestored) {
        // Never stop while the shell would inherit a terminal we failed to
        // restore. Re-enter best-effort and leave the process running.
        await _resume();
        return false;
      }
    }
    final selfStop = _selfStopOverride;
    final bool stopped;
    if (selfStop != null) {
      stopped = selfStop();
    } else {
      // Returns only after `fg` sends SIGCONT; the resume below re-enters.
      stopped = PosixJobControl.stopJob();
    }
    if (!stopped) {
      // The stop didn't take (e.g. the signal failed) — re-enter immediately
      // rather than freeze or let frames target the restored shell.
      await _resume();
    } else if (selfStop == null) {
      await _resume();
    }
    return stopped;
  }

  /// Test seam: drive [_suspend] without a real job-control terminal.
  @visibleForTesting
  Future<void> debugSuspend() => _suspend();

  /// Test seam: drive [_resume] (`fg`) without a real SIGCONT.
  @visibleForTesting
  Future<void> debugResume() => _resume();

  /// Test seam: whether frame writes are currently gated by a Ctrl+Z suspend.
  @visibleForTesting
  bool get debugSuspended => _suspended;

  /// Hooks for runApp's fd capture: the operation may start only after pause
  /// succeeds, and capture must be resumed before the driver releases its borrow.
  Future<void> Function()? onHandoffStart;
  Future<void> Function()? onHandoffEnd;

  @override
  Future<T> runWithTerminalHandoff<T>(FutureOr<T> Function() operation) async {
    final inherited = Zone.current[this];
    if (inherited is _TerminalBorrow) {
      if (!inherited.active) throw StateError('Terminal handoff has ended.');
      return await operation();
    }
    if (!_active || _restoring || _suspended) {
      throw StateError('No active terminal session for handoff.');
    }
    final previous = _handoffTail;
    final release = Completer<void>();
    _handoffTail = release.future;
    var didHandoff = false;
    var captureReleased = false;
    var inputReleased = false;
    var operationStarted = false;
    var reentryFailed = false;
    final borrow = _TerminalBorrow();
    TerminalMode? handoffMode;
    try {
      await previous;
      if (!_active || _restoring || _suspended) {
        throw StateError('Terminal session closed before handoff could start.');
      }
      final mode = handoffMode = _mode!;
      _stopInputReports();
      _handoffActive = didHandoff = true;
      await _inlineTail;
      if (!_active || _restoring) {
        throw StateError('Terminal session closed before handoff could start.');
      }
      if (!_events.isClosed) {
        _events.add(const TerminalFocusEvent(focused: false));
      }
      await _releaseInput();
      inputReleased = true;
      // Restoration can start at any await. It drains this borrow, so do not
      // launch a new operation once closing has begun.
      if (!_active || _restoring) {
        throw StateError('Terminal session closed before handoff could start.');
      }
      if (_changedStdin && !_restoreCookedMode()) {
        throw StateError('Cannot restore terminal input for handoff.');
      }
      _releaseInline();
      if (_wroteEnterSequences) {
        await _exitOutputMode(mode);
      } else {
        await _stdout.flush();
      }
      if (!_active || _restoring) {
        throw StateError('Terminal session closed before handoff could start.');
      }
      captureReleased = true;
      await onHandoffStart?.call();
      if (!_active || _restoring) {
        throw StateError('Terminal session closed before handoff could start.');
      }
      operationStarted = true;
      return await runZoned(
        () => Future<T>.sync(operation),
        zoneValues: <Object?, Object?>{this: borrow},
      );
    } catch (error, stack) {
      if (didHandoff && !operationStarted && !_restoring) {
        // Preparation may have only partly released input, screen modes, or
        // capture. Re-entering here could push a second keyboard stack or
        // report focus with no reader. Let final cleanup resolve ownership.
        reentryFailed = true;
        _active = false;
        if (!_events.isClosed) _events.addError(error, stack);
      }
      rethrow;
    } finally {
      borrow.active = false;
      try {
        if (didHandoff) {
          try {
            if (captureReleased) await onHandoffEnd?.call();
            final mode = handoffMode!;
            if (_active && !_restoring && identical(_mode, mode)) {
              if (_rawTerminalInput) _setRawMode();
              await _enterOutputMode(mode);
              if (_active && !_restoring) {
                if (inputReleased) await _reacquireInput();
                if (isInline) await _changeInline(reacquire: true);
              }
            }
          } catch (error, stack) {
            // A failed operation may return to a healthy UI; failed terminal
            // reacquisition cannot. Keep frames gated and publish the failure
            // to runApp even if the caller catches its handoff Future.
            reentryFailed = true;
            _active = false;
            if (!_events.isClosed) _events.addError(error, stack);
            rethrow;
          } finally {
            _handoffActive = reentryFailed;
            if (_active && !_restoring && !_events.isClosed) {
              _events.add(const TerminalFocusEvent(focused: true));
              _events.add(ResizeEvent(size));
            }
          }
        }
      } finally {
        release.complete();
      }
    }
  }

  /// Foreground continuation: re-enter the configured mode and force a full
  /// repaint (the window may have resized while stopped).
  Future<void> _resume() {
    if (_resuming) return _resumeTail;
    _resuming = true;
    return _resumeTail = _resumeImpl()
        .catchError((Object error, StackTrace stack) {
          _failTerminalTransition(error, stack);
          Error.throwWithStackTrace(error, stack);
        })
        .whenComplete(() => _resuming = false);
  }

  Future<void> _resumeImpl() async {
    final mode = _mode;
    if (mode == null || !_active || _restoring || _handoffActive) return;
    final generation = _lifecycleGeneration;
    if (_rawTerminalInput) _setRawMode();
    await _enterOutputMode(mode);
    if (!_active || _restoring || generation != _lifecycleGeneration) return;
    await _reacquireInput();
    if (!_active || _restoring || generation != _lifecycleGeneration) return;
    if (isInline) await _changeInline(reacquire: true);
    if (!_active || _restoring || generation != _lifecycleGeneration) return;
    _suspended = false;
    if (!_events.isClosed) {
      _events.add(const TerminalFocusEvent(focused: true));
      _events.add(ResizeEvent(size));
    }
  }

  @override
  Future<void> restore() {
    final pending = _restoreFuture;
    if (pending != null) return pending;
    // Publish before the first synchronous write: a custom sink can request
    // restore from write(), including the early input-mode disables.
    final completion = Completer<void>();
    _restoreFuture = completion.future;
    _restore().then(completion.complete, onError: completion.completeError);
    return completion.future;
  }

  Future<void> _restore() async {
    _entryUsed = true;
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
    if (!_active &&
        !_wroteEnterSequences &&
        !_changedStdin &&
        _nativeInput == null &&
        _stdinSubscription == null &&
        _resizeSubscription == null &&
        _intSubscription == null &&
        _termSubscription == null &&
        _hupSubscription == null) {
      _queryRunner.dispose();
      _terminalState = null;
      _sink.target = null;
      _restoring = false;
      return;
    }

    _flushTimer?.cancel();
    _flushTimer = null;
    _pasteIdleTimer?.cancel();
    _pasteIdleTimer = null;

    // Shield the rest of restore from SIGINT/SIGTERM/SIGHUP. Cancelling the
    // LAST subscription to a signal restores the OS default disposition, so a
    // signal arriving while the remaining cleanup yields — the hot-reload
    // supervisor forwards one 300 ms after delivery — killed the process raw,
    // mid-restore: capture teardown skipped, nothing after `await runApp`
    // ran, and the emergency tty restore made it look like a clean quit. The
    // shield swallows it (we are already on the way out) and is dropped last.
    // Bounded: a second signal during the restore, or any signal once it
    // has already run for two seconds (a pty write blocked behind a dropped
    // SSH session or an XOFF), is the user overruling a hung teardown. It
    // ends the process with the conventional code — the alternative is a
    // process only SIGKILL can end, with nothing to restore the terminal.
    final restoreClock = Stopwatch()..start();
    var shieldedSignals = 0;
    final shields = <StreamSubscription<ProcessSignal>>[];
    for (final signal in const [
      ProcessSignal.sigint,
      ProcessSignal.sigterm,
      ProcessSignal.sighup,
    ]) {
      final shield = _watchSignal(signal, (received) {
        shieldedSignals++;
        if (shieldedSignals < 2 &&
            restoreClock.elapsed < const Duration(seconds: 2)) {
          return;
        }
        final code = _signalExitCode(_appSignalOf(received));
        final force = _forceExitOverride;
        if (force != null) {
          force(code);
        } else {
          exit(code);
        }
      });
      if (shield != null) shields.add(shield);
    }

    (Object, StackTrace)? failure;
    Future<void> attempt(
      FutureOr<void> Function() operation, {
      bool terminalOutput = false,
    }) async {
      try {
        await operation();
      } catch (error, stack) {
        // A revoked terminal has no modes left to restore. This exception is
        // only for completed terminal I/O, never reader/capture/child cleanup.
        // SIGHUP alone is not proof: callers can send it to a live terminal.
        if (terminalOutput && _savedOutputIsGone(error)) {
          return;
        }
        failure ??= (error, stack);
      }
    }

    // Stop reports before subscription cancellation or a slow reader release.
    // A child that currently owns the terminal must remain untouched.
    try {
      _stopInputReports();
    } catch (error, stack) {
      if (!_savedOutputIsGone(error)) failure ??= (error, stack);
    }

    // Keep the signal shields active while an existing child/operation still
    // owns the terminal. Queued handoffs observe closing and reject. Reaching
    // this method does not cancel an arbitrary operation Future.
    await attempt(() => _intSubscription?.cancel());
    _intSubscription = null;
    await attempt(() => _termSubscription?.cancel());
    _termSubscription = null;
    await attempt(() => _hupSubscription?.cancel());
    _hupSubscription = null;
    await attempt(() => _handoffTail);
    // A failed transition is the reason cleanup may be running. Wait for it
    // to settle, then judge ownership by the restoration below. Its earlier
    // error alone must not quarantine a terminal that we successfully restore.
    await _suspendTail.then<void>((_) {}, onError: (Object _) {});
    await _resumeTail.then<void>((_) {}, onError: (Object _) {});
    await _modeWriteTail;
    await attempt(() => _resizeSubscription?.cancel());
    _resizeSubscription = null;
    await attempt(_releaseInlineForRestore, terminalOutput: true);
    await attempt(() => _releaseInput(finalRelease: true));
    _queryRunner.dispose();
    if (_changedStdin) {
      await attempt(() {
        if (!_restoreCookedMode()) {
          throw StateError('Cannot restore terminal input mode.');
        }
        _terminalState?.rawInputOwned = false;
      });
    }
    if (_wroteEnterSequences) {
      await attempt(() async {
        await _exitOutputMode(
          _mode ?? TerminalMode.interactive,
          restoring: true,
        );
      }, terminalOutput: true);
    }
    await attempt(() async {
      await _stdout.flush();
      _terminalState?.outputModesOwned = false;
      _recordInlineLease(active: false, region: false);
    }, terminalOutput: true);
    _terminalState = null;
    _sink.target = null;
    _graceTimer?.cancel();
    _graceTimer = null;
    _pendingSignal = null;
    _pendingSignalDelivered = false;
    for (final shield in shields) {
      await attempt(shield.cancel);
    }
    _restoring = false;
    final protocolFailure = _protocolWriteFailure;
    if (protocolFailure != null && !_savedOutputIsGone(protocolFailure.$1)) {
      failure ??= protocolFailure;
    }
    final failed = failure;
    if (failed != null) Error.throwWithStackTrace(failed.$1, failed.$2);
  }

  bool _savedOutputIsGone(Object error) {
    // stdio 0.4 does not expose errno on its synchronous write exception.
    // Verify the saved output descriptor itself; do not parse error messages
    // or infer that output disappeared just because input hung up.
    final output = _stdout;
    if (!_stdoutIsTerminal) return false;
    if (error is fd.StdioException && output is fd.StdoutTerminalSink) {
      return posixDescriptorHungUp(output.fd);
    }
    return identical(output, stdout) &&
        error is StdoutException &&
        posixDescriptorHungUp(1);
  }

  @override
  void write(String data) {
    // Drop frames while the terminal is handed to a child ([_handoffActive])
    // or restored for the shell across a Ctrl+Z ([_suspended]) — writing them
    // would interleave ANSI with an editor's screen or the bare shell prompt.
    if (!_active || _restoring || _handoffActive || _suspended) return;
    final inline = _inline;
    if (inline != null) {
      if (_inlineChanges > 0) {
        // The renderer still commits its frame when output is gated. Even a
        // resize that coalesces back to the original geometry must repaint
        // those discarded bytes before normal frame diffs resume.
        _inlineNeedsRepaint = true;
        return;
      }
      if (!inline.isAllocated) return;
      if (_physicalSize != inline.terminalSize) {
        _inlineNeedsRepaint = true;
        _scheduleInlineResize();
        return;
      }
    }
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
  NativePosixTerminalModeController() : _bindings = PosixTermiosBindings.load();

  @visibleForTesting
  NativePosixTerminalModeController.withBindings(this._bindings);

  static const _termiosStorageBytes = 256;
  final PosixTermiosBindings? _bindings;
  List<int>? _original;
  int? _restoreFd;
  (Object, StackTrace)? _releaseFailure;

  void _checkReleaseFailure() {
    final failure = _releaseFailure;
    if (failure != null) Error.throwWithStackTrace(failure.$1, failure.$2);
  }

  @override
  bool enableRawMode() {
    _checkReleaseFailure();
    final bindings = _bindings;
    if (bindings == null) return false;
    // Own a close-on-exec descriptor independently of the caller's fd 0.
    // Failed native operations remain owned until restoreMode rolls them back;
    // a possibly partial raw-mode change must never become a Dart fallback.
    if (_restoreFd == null) {
      final fd = bindings.duplicate(0, Platform.isMacOS ? 67 : 1030, 0);
      if (fd < 0) {
        throw OSError('Cannot retain terminal input', bindings.errno().value);
      }
      _restoreFd = fd;
    }
    final fd = _restoreFd!;
    final storage = calloc<Uint8>(_termiosStorageBytes);
    try {
      final original = _original;
      if (original == null) {
        if (bindings.tcgetattr(fd, storage.cast<Void>()) != 0) {
          throw OSError(
            'Cannot read terminal input mode',
            bindings.errno().value,
          );
        }
        _original = List<int>.of(storage.asTypedList(_termiosStorageBytes));
      } else {
        storage.asTypedList(_termiosStorageBytes).setAll(0, original);
      }
      bindings.cfmakeraw(storage.cast<Void>());
      if (bindings.tcsetattr(fd, _tcsanow, storage.cast<Void>()) != 0) {
        throw OSError(
          'Cannot enter terminal input mode',
          bindings.errno().value,
        );
      }
      return true;
    } finally {
      calloc.free(storage);
    }
  }

  @override
  bool restoreMode() {
    _checkReleaseFailure();
    final bindings = _bindings;
    final fd = _restoreFd;
    // No successful duplicate means there was nothing to mutate or release.
    if (bindings == null || fd == null) return true;
    final original = _original;
    (Object, StackTrace)? failure;
    try {
      if (original != null) {
        final storage = calloc<Uint8>(_termiosStorageBytes);
        try {
          storage.asTypedList(_termiosStorageBytes).setAll(0, original);
          if (bindings.tcsetattr(fd, _tcsanow, storage.cast<Void>()) != 0) {
            final error = OSError(
              'Cannot restore terminal input mode',
              bindings.errno().value,
            );
            if (!bindings.descriptorHungUp(fd)) throw error;
          }
        } finally {
          calloc.free(storage);
        }
      }
    } catch (error, stack) {
      failure = (error, stack);
    } finally {
      // Retire the number even if close fails: retrying could close a reused
      // descriptor. The retained failure still prevents claiming restoration.
      _restoreFd = null;
      try {
        if (bindings.close(fd) != 0) {
          throw OSError(
            'Cannot close terminal input handle',
            bindings.errno().value,
          );
        }
      } catch (error, stack) {
        failure ??= (error, stack);
      }
    }
    _releaseFailure = failure;
    _checkReleaseFailure();
    return true;
  }

  static const _tcsanow = 0;
}

typedef _TcgetattrNative = Int32 Function(Int32, Pointer<Void>);
typedef _TcgetattrDart = int Function(int, Pointer<Void>);
typedef _TcsetattrNative = Int32 Function(Int32, Int32, Pointer<Void>);
typedef _TcsetattrDart = int Function(int, int, Pointer<Void>);
typedef _CfmakerawNative = Void Function(Pointer<Void>);
typedef _CfmakerawDart = void Function(Pointer<Void>);

/// Internal libc function table, exposed for deterministic syscall-fault tests.
@visibleForTesting
final class PosixTermiosBindings {
  const PosixTermiosBindings({
    required this.tcgetattr,
    required this.tcsetattr,
    required this.cfmakeraw,
    required this.duplicate,
    required this.close,
    required this.errno,
    this.descriptorHungUp = posixDescriptorHungUp,
  });

  static PosixTermiosBindings? load() {
    if (Platform.isWindows) return null;
    try {
      final libc = DynamicLibrary.process();
      return PosixTermiosBindings(
        tcgetattr: libc.lookupFunction<_TcgetattrNative, _TcgetattrDart>(
          'tcgetattr',
        ),
        tcsetattr: libc.lookupFunction<_TcsetattrNative, _TcsetattrDart>(
          'tcsetattr',
        ),
        cfmakeraw: libc.lookupFunction<_CfmakerawNative, _CfmakerawDart>(
          'cfmakeraw',
        ),
        duplicate: libc
            .lookupFunction<
              Int32 Function(Int32, Int32, VarArgs<(Int32,)>),
              int Function(int, int, int)
            >('fcntl'),
        close: libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
          'close',
        ),
        errno: libc
            .lookupFunction<
              Pointer<Int32> Function(),
              Pointer<Int32> Function()
            >(Platform.isMacOS ? '__error' : '__errno_location'),
      );
    } on Object {
      // Non-glibc/non-Darwin POSIX target: retain the old ICANON/ECHO fallback.
      // Ctrl+Z orderly suspension is unavailable there, but raw input/rendering
      // still work and no unsafe Dart FFI signal callback is installed.
      return null;
    }
  }

  final int Function(int, Pointer<Void>) tcgetattr;
  final int Function(int, int, Pointer<Void>) tcsetattr;
  final void Function(Pointer<Void>) cfmakeraw;
  final int Function(int, int, int) duplicate;
  final int Function(int) close;
  final Pointer<Int32> Function() errno;
  final bool Function(int) descriptorHungUp;
}

/// The shell's job control as a native session uses it: whether a job-control
/// shell started this process ([isShellJob]), and the Ctrl+Z stop
/// ([stopJob]), delivered the way the terminal's own SIGTSTP is: to the job,
/// not only to this process.
///
/// A shell runs a command as a job — a process group — and gets the terminal
/// back when the process it started stops or ends. That process is often not
/// the app: the hot-reload supervisor of a plain `dart run bin/app.dart`, the
/// `fleury run` launcher, or a wrapper such as `sh -c` runs the app as its
/// child in the same group. Stopping the app alone left that parent running in
/// the foreground, so the shell never printed its prompt, and `fg` had nothing
/// to continue. The whole group stops, exactly as a Ctrl+Z the kernel handled
/// would stop it, and `fg` continues all of it.
///
/// Only a job-control shell continues a stopped job, so a session stops only
/// as one's job. A terminal emulator, a tmux pane, or `ssh -t host app` that
/// runs the app directly makes it (or its supervisor) the session leader,
/// whose group nothing would continue: SIGSTOP, which the kernel never
/// discards, would leave it stopped for good.
@internal
final class PosixJobControl {
  const PosixJobControl._({
    required this.getpgrp,
    required this.getsid,
    required this.tcgetpgrp,
    required this.killpg,
  });

  static final PosixJobControl? _native = _load();

  static PosixJobControl? _load() {
    if (Platform.isWindows) return null;
    try {
      final libc = DynamicLibrary.process();
      return PosixJobControl._(
        getpgrp: libc.lookupFunction<Int32 Function(), int Function()>(
          'getpgrp',
        ),
        getsid: libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
          'getsid',
        ),
        tcgetpgrp: libc
            .lookupFunction<Int32 Function(Int32), int Function(int)>(
              'tcgetpgrp',
            ),
        killpg: libc
            .lookupFunction<
              Int32 Function(Int32, Int32),
              int Function(int, int)
            >('killpg'),
      );
    } on Object {
      return null;
    }
  }

  final int Function() getpgrp;
  final int Function(int pid) getsid;
  final int Function(int fd) tcgetpgrp;
  final int Function(int group, int signal) killpg;

  /// The operating system's SIGSTOP: 17 on Darwin, 19 on Linux. Not
  /// `ProcessSignal.sigstop.signalNumber`, which is Dart's own id for
  /// `Process.killPid` to translate — sent raw on macOS, that id is SIGCONT.
  static final int _sigstop = Platform.isMacOS || Platform.isIOS ? 17 : 19;

  /// Whether this process runs as a job of a job-control shell, which can
  /// continue it after a stop: [terminalFd] is its controlling terminal, its
  /// process group is that terminal's foreground group, and the group isn't
  /// the session leader's.
  ///
  /// A job-control shell runs each job in a process group of its own and
  /// gives that group the terminal, and it continues the job after a stop
  /// (as `sudo`, itself run as such a job, does for a command on a pty of its
  /// own). A command started with no shell stays in the session leader's
  /// group — the leader being the command itself, its supervisor, or a
  /// `sh -c` wrapper — and nothing above that group would continue it.
  /// Without a controlling terminal, nothing does job control at all.
  ///
  /// The test reads process groups only, so a launcher that gives the app a
  /// foreground group of its own without doing job control passes it too: a
  /// shell that `exec`s the app after moving itself into its own group, under
  /// a session leader that isn't a shell (fish does this beneath macOS's
  /// `login`; bash and zsh move back first), or a wrapper with no shell above
  /// it, such as `sudo` run directly by `ssh -t` or `docker run --init`.
  /// There a stopped app stays stopped until something sends it SIGCONT.
  static bool isShellJob({int terminalFd = 0}) {
    final native = _native;
    if (native == null) return false;
    final group = native.getpgrp();
    return group > 0 &&
        native.tcgetpgrp(terminalFd) == group &&
        native.getsid(0) != group;
  }

  /// Stops this process's job with SIGSTOP, which cannot be caught or
  /// discarded; the signal reaches this process before the call returns, and
  /// the call returns only after `fg` sends SIGCONT. Returns whether the stop
  /// was sent: false, stopping nothing, unless this process's group still
  /// owns the terminal's foreground, as a shell's job does ([isShellJob]).
  /// [terminalFd] is the session's terminal input.
  static bool stopJob({int terminalFd = 0}) {
    final native = _native;
    if (native == null) return false;
    final group = native.getpgrp();
    if (group <= 0 || native.tcgetpgrp(terminalFd) != group) return false;
    return native.killpg(group, _sigstop) == 0;
  }
}

/// Whether [error], from terminal I/O, says the terminal itself is
/// gone: EIO (Linux, a pty whose master closed) or ENXIO ("device not
/// configured", macOS after the tty is revoked). Both numbers are the same on
/// every POSIX platform Fleury runs on.
@internal
bool isTerminalGoneError(Object error) {
  final osError = switch (error) {
    OSError e => e,
    SocketException(:final osError) => osError,
    FileSystemException(:final osError) => osError,
    StdinException(:final osError) => osError,
    StdoutException(:final osError) => osError,
    _ => null,
  };
  return osError != null && (osError.errorCode == 5 || osError.errorCode == 6);
}

/// What each segment of the batched capability exchange answers.
enum _CapabilityProbe { synchronizedOutput, image, glyphWidths, pointerShapes }

// A delayed callback created by a finished handoff must not inherit permission
// to operate on the terminal after the driver has reclaimed it.
final class _TerminalBorrow {
  bool active = true;
}
