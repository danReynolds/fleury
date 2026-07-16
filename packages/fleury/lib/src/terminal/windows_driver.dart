// Windows terminal driver: owns the same framework-facing contract as the
// POSIX driver, but uses Windows console mode flags for virtual terminal
// input/output and polling for resize notifications.

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
import 'terminal_sequences.dart';

class WindowsTerminalDriver
    with TerminalAttentionSequences
    implements TerminalDriver, TerminalHandoffDriver {
  WindowsTerminalDriver({
    Stdin? stdinOverride,
    Stdout? stdoutOverride,
    this.resizePollInterval = const Duration(milliseconds: 250),
  }) : _stdin = stdinOverride ?? stdin,
       _stdout = stdoutOverride ?? stdout,
       _consoleModeController = NativeWindowsConsoleModeController();

  final Stdin _stdin;
  final Stdout _stdout;
  final WindowsConsoleModeController _consoleModeController;
  final Duration resizePollInterval;

  late final bool _stdinIsTerminal = _stdin.hasTerminal;
  late final bool _stdoutIsTerminal = _stdout.hasTerminal;

  final InputParser _parser = InputParser();
  final StreamController<TuiEvent> _events =
      StreamController<TuiEvent>.broadcast();
  final _ParserSink _sink = _ParserSink();

  StreamSubscription<List<int>>? _stdinSubscription;
  Timer? _flushTimer;
  Timer? _resizePollTimer;

  bool _active = false;
  bool _handoffActive = false;
  Future<void> _handoffTail = Future<void>.value();
  TerminalMode? _mode;
  CellSize? _lastSize;
  bool _wroteEnterSequences = false;
  bool _changedStdin = false;
  bool? _originalLineMode;
  bool? _originalEchoMode;
  WindowsConsoleModeState? _consoleModeState;

  @override
  CellSize get size {
    int cols;
    int rows;
    try {
      cols = _stdout.terminalColumns;
      rows = _stdout.terminalLines;
    } on StdoutException {
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
  RemoteSurfaceSink? get surfaceSink => null; // byte presentation only

  @override
  Future<void> enter(TerminalMode mode) async {
    if (_active) {
      throw StateError(
        'WindowsTerminalDriver.enter called on an active driver.',
      );
    }
    _mode = mode;
    _sink.target = _events;

    _enableConsoleMode(mode);
    _enableRawInput(mode);

    final enter = buildTerminalEnterSequences(mode);
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
        if (!_events.isClosed) _events.addError(error, stack);
      },
      onDone: () {
        _flushTimer?.cancel();
        _flushTimer = null;
        _parser.finish(_sink);
        if (!_events.isClosed) unawaited(_events.close());
      },
      cancelOnError: false,
    );

    _lastSize = size;
    if (_stdoutIsTerminal && resizePollInterval > Duration.zero) {
      _resizePollTimer = Timer.periodic(
        resizePollInterval,
        (_) => _pollResize(),
      );
    }

    _active = true;
  }

  void _enableConsoleMode(TerminalMode mode) {
    _consoleModeState = _consoleModeController.enter(mode);
  }

  void _restoreConsoleMode() {
    final state = _consoleModeState;
    _consoleModeState = null;
    if (state != null) _consoleModeController.restore(state);
  }

  void _enableRawInput(TerminalMode mode) {
    if (!mode.rawInput || !_stdinIsTerminal) return;
    _originalLineMode ??= _stdin.lineMode;
    _originalEchoMode ??= _stdin.echoMode;
    _setRawMode();
    _changedStdin = true;
  }

  void _setRawMode() {
    try {
      // Windows requires echo to be disabled while line input is still
      // enabled; reversing this order can make the first setter fail and skip
      // both changes. The native console-mode path below is authoritative,
      // while these dart:io setters remain the detached/redirected fallback.
      _stdin.echoMode = false;
      _stdin.lineMode = false;
    } on StdinException {
      // ignore - console may have detached
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

  void _pollResize() {
    if (!_active || _handoffActive) return;
    final current = size;
    if (current == _lastSize) return;
    _lastSize = current;
    if (!_events.isClosed) _events.add(ResizeEvent(current));
  }

  @override
  Future<T> runWithTerminalHandoff<T>(FutureOr<T> Function() operation) async {
    if (Zone.current[this] == true) return await operation();

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

        final input = _stdinSubscription;
        if (input != null) {
          input.pause();
          stdinPaused = true;
        }
        if (_wroteEnterSequences) {
          _stdout.write(buildTerminalExitSequences(mode));
        }
        try {
          await _stdout.flush();
        } catch (_) {}
        if (_changedStdin) _restoreCookedMode();
        _restoreConsoleMode();

        return await runZoned(
          () => Future<T>.sync(operation),
          zoneValues: <Object?, Object?>{this: true},
        );
      } finally {
        if (didHandoff) {
          final mode = handoffMode!;
          final shouldReenter = _active && identical(_mode, mode);
          try {
            if (shouldReenter) {
              _enableConsoleMode(mode);
              if (_changedStdin) _setRawMode();
              if (_wroteEnterSequences) {
                _stdout.write(buildTerminalEnterSequences(mode));
              }
              try {
                await _stdout.flush();
              } catch (_) {}
              _lastSize = size;
            }
          } finally {
            try {
              if (stdinPaused) _stdinSubscription?.resume();
            } finally {
              _handoffActive = false;
              if (shouldReenter && !_events.isClosed) {
                _events.add(ResizeEvent(_lastSize ?? size));
              }
            }
          }
        }
      }
    } finally {
      if (!release.isCompleted) release.complete();
    }
  }

  @override
  Future<void> restore() async {
    if (!_active &&
        !_wroteEnterSequences &&
        !_changedStdin &&
        _consoleModeState == null) {
      return;
    }

    _active = false;
    _handoffActive = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    _resizePollTimer?.cancel();
    _resizePollTimer = null;

    try {
      await _stdinSubscription?.cancel();
    } catch (_) {}
    _stdinSubscription = null;

    if (_wroteEnterSequences) {
      try {
        _stdout.write(
          buildTerminalExitSequences(_mode ?? TerminalMode.interactive),
        );
      } catch (_) {}
      _wroteEnterSequences = false;
    }

    try {
      await _stdout.flush();
    } catch (_) {}

    if (_changedStdin) {
      _restoreCookedMode();
      _changedStdin = false;
    }
    _restoreConsoleMode();

    _mode = null;
    _sink.target = null;
  }

  @override
  void write(String data) {
    if (_handoffActive) return;
    _stdout.write(data);
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 30), () {
      _parser.flush(_sink);
    });
  }
}

@visibleForTesting
abstract interface class WindowsConsoleModeController {
  WindowsConsoleModeState enter(TerminalMode mode);
  void restore(WindowsConsoleModeState state);
}

@visibleForTesting
final class WindowsConsoleModeState {
  const WindowsConsoleModeState({
    required this.inputChanged,
    required this.outputChanged,
    this.inputHandle,
    this.outputHandle,
    this.originalInputMode,
    this.originalOutputMode,
  });

  static const none = WindowsConsoleModeState(
    inputChanged: false,
    outputChanged: false,
  );

  final bool inputChanged;
  final bool outputChanged;
  final int? inputHandle;
  final int? outputHandle;
  final int? originalInputMode;
  final int? originalOutputMode;

  bool get changed => inputChanged || outputChanged;
}

@visibleForTesting
final class WindowsConsoleModePlan {
  const WindowsConsoleModePlan({
    required this.inputChanged,
    required this.outputChanged,
    this.desiredInputMode,
    this.desiredOutputMode,
  });

  final bool inputChanged;
  final bool outputChanged;
  final int? desiredInputMode;
  final int? desiredOutputMode;

  bool get changed => inputChanged || outputChanged;
}

@visibleForTesting
WindowsConsoleModePlan planWindowsConsoleModes({
  required TerminalMode mode,
  required int? inputMode,
  required int? outputMode,
}) {
  int? desiredInputMode;
  var inputChanged = false;
  if (mode.rawInput && inputMode != null) {
    desiredInputMode =
        (inputMode | _enableVirtualTerminalInput | _enableExtendedFlags) &
        ~(_enableProcessedInput |
            _enableLineInput |
            _enableEchoInput |
            _enableQuickEditMode);
    inputChanged = desiredInputMode != inputMode;
  }

  int? desiredOutputMode;
  var outputChanged = false;
  if (outputMode != null) {
    desiredOutputMode =
        outputMode |
        _enableProcessedOutput |
        _enableVirtualTerminalProcessing |
        _disableNewlineAutoReturn;
    outputChanged = desiredOutputMode != outputMode;
  }

  return WindowsConsoleModePlan(
    inputChanged: inputChanged,
    outputChanged: outputChanged,
    desiredInputMode: desiredInputMode,
    desiredOutputMode: desiredOutputMode,
  );
}

@visibleForTesting
final class NativeWindowsConsoleModeController
    implements WindowsConsoleModeController {
  NativeWindowsConsoleModeController();

  _WindowsConsoleApi? _api;

  @override
  WindowsConsoleModeState enter(TerminalMode mode) {
    if (!Platform.isWindows) return WindowsConsoleModeState.none;
    final api = _api ??= _WindowsConsoleApi.open();
    if (api == null) return WindowsConsoleModeState.none;

    final input = api.mode(_stdInputHandle);
    final output = api.mode(_stdOutputHandle);
    final plan = planWindowsConsoleModes(
      mode: mode,
      inputMode: input.mode,
      outputMode: output.mode,
    );

    var inputChanged = false;
    var outputChanged = false;
    final desiredInputMode = plan.desiredInputMode;
    if (plan.inputChanged && desiredInputMode != null) {
      inputChanged = api.setMode(input.handle, desiredInputMode);
    }
    final desiredOutputMode = plan.desiredOutputMode;
    if (plan.outputChanged && desiredOutputMode != null) {
      outputChanged = api.setMode(output.handle, desiredOutputMode);
    }

    return WindowsConsoleModeState(
      inputChanged: inputChanged,
      outputChanged: outputChanged,
      inputHandle: input.handle,
      outputHandle: output.handle,
      originalInputMode: input.mode,
      originalOutputMode: output.mode,
    );
  }

  @override
  void restore(WindowsConsoleModeState state) {
    if (!state.changed || !Platform.isWindows) return;
    final api = _api ??= _WindowsConsoleApi.open();
    if (api == null) return;
    final inputHandle = state.inputHandle;
    final outputHandle = state.outputHandle;
    if (state.inputChanged &&
        inputHandle != null &&
        state.originalInputMode != null) {
      api.setMode(inputHandle, state.originalInputMode!);
    }
    if (state.outputChanged &&
        outputHandle != null &&
        state.originalOutputMode != null) {
      api.setMode(outputHandle, state.originalOutputMode!);
    }
  }
}

final class _WindowsConsoleApi {
  _WindowsConsoleApi._({
    required int Function(int) getStdHandle,
    required int Function(int, Pointer<Uint32>) getConsoleMode,
    required int Function(int, int) setConsoleMode,
  }) : _getStdHandle = getStdHandle,
       _getConsoleMode = getConsoleMode,
       _setConsoleMode = setConsoleMode;

  static _WindowsConsoleApi? open() {
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      return _WindowsConsoleApi._(
        getStdHandle: kernel32
            .lookupFunction<IntPtr Function(Int32), int Function(int)>(
              'GetStdHandle',
            ),
        getConsoleMode: kernel32
            .lookupFunction<
              Int32 Function(IntPtr, Pointer<Uint32>),
              int Function(int, Pointer<Uint32>)
            >('GetConsoleMode'),
        setConsoleMode: kernel32
            .lookupFunction<
              Int32 Function(IntPtr, Uint32),
              int Function(int, int)
            >('SetConsoleMode'),
      );
    } on Object {
      return null;
    }
  }

  final int Function(int) _getStdHandle;
  final int Function(int, Pointer<Uint32>) _getConsoleMode;
  final int Function(int, int) _setConsoleMode;

  ({int handle, int? mode}) mode(int stdHandle) {
    final handle = _getStdHandle(stdHandle);
    if (handle == 0 || handle == _invalidHandleValue) {
      return (handle: handle, mode: null);
    }
    final mode = calloc<Uint32>();
    try {
      if (_getConsoleMode(handle, mode) == 0) {
        return (handle: handle, mode: null);
      }
      return (handle: handle, mode: mode.value);
    } finally {
      calloc.free(mode);
    }
  }

  bool setMode(int handle, int mode) => _setConsoleMode(handle, mode) != 0;
}

class _ParserSink implements TuiEventSink {
  StreamController<TuiEvent>? target;

  @override
  void add(TuiEvent event) {
    final controller = target;
    if (controller != null && !controller.isClosed) controller.add(event);
  }
}

const _stdInputHandle = -10;
const _stdOutputHandle = -11;
const _invalidHandleValue = -1;

const _enableProcessedOutput = 0x0001;
const _enableVirtualTerminalProcessing = 0x0004;
const _disableNewlineAutoReturn = 0x0008;
const _enableVirtualTerminalInput = 0x0200;
const _enableProcessedInput = 0x0001;
const _enableLineInput = 0x0002;
const _enableEchoInput = 0x0004;
const _enableQuickEditMode = 0x0040;
const _enableExtendedFlags = 0x0080;
