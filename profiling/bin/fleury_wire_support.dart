import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/terminal/terminal_sequences.dart'
    show buildTerminalEnterSequences, buildTerminalExitSequences;

final class WireTerminalDriver implements TerminalDriver {
  @override
  RemoteSurfaceSink? get surfaceSink => null; // byte presentation only

  WireTerminalDriver() : _stdout = stdout;

  final Stdout _stdout;
  final StreamController<TuiEvent> _events =
      StreamController<TuiEvent>.broadcast();
  StreamSubscription<ProcessSignal>? _resizeSubscription;
  var _active = false;
  TerminalMode? _mode;

  Future<void> closeEvents() async {
    if (!_events.isClosed) await _events.close();
  }

  @override
  TerminalCapabilities get capabilities =>
      detectTerminalCapabilitiesFromEnvironment(Platform.environment);

  @override
  Stream<TuiEvent> get events => _events.stream;

  @override
  bool get isActive => _active;

  @override
  bool get isInteractive => _stdout.hasTerminal;

  @override
  CellSize get size {
    try {
      return CellSize(_stdout.terminalColumns, _stdout.terminalLines);
    } on StdoutException {
      return CellSize(_envInt('COLUMNS') ?? 120, _envInt('LINES') ?? 32);
    }
  }

  @override
  Future<void> enter(TerminalMode mode) async {
    if (_active) return;
    _mode = mode;
    _active = true;
    if (!Platform.isWindows) {
      _resizeSubscription ??= ProcessSignal.sigwinch.watch().listen((_) {
        if (!_events.isClosed) _events.add(ResizeEvent(size));
      });
    }
    final enter = buildTerminalEnterSequences(mode);
    if (enter.isNotEmpty) _stdout.write(enter);
  }

  @override
  Future<void> restore() async {
    if (!_active) return;
    final exit = buildTerminalExitSequences(_mode ?? TerminalMode.interactive);
    if (exit.isNotEmpty) _stdout.write(exit);
    try {
      await _stdout.flush();
    } catch (_) {}
    await _resizeSubscription?.cancel();
    _resizeSubscription = null;
    _active = false;
    _mode = null;
  }

  @override
  void write(String data) => _stdout.write(data);
}

int positiveInt(String arg, String prefix) {
  final parsed = int.tryParse(arg.substring(prefix.length));
  if (parsed == null || parsed <= 0) {
    throw ArgumentError('$prefix expects a positive integer');
  }
  return parsed;
}

int? _envInt(String name) => int.tryParse(Platform.environment[name] ?? '');
