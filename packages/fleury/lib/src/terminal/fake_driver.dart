import 'dart:async';

import '../foundation/geometry.dart';
import 'capabilities.dart';
import 'events.dart';
import 'terminal_driver.dart';

/// A [TerminalDriver] for tests and offline rendering. No real I/O —
/// the driver buffers everything written, exposes the buffer for
/// assertions, and lets the test push events into the event stream.
final class FakeTerminalDriver implements TerminalDriver {
  FakeTerminalDriver({
    CellSize size = const CellSize(80, 24),
    this.capabilities = TerminalCapabilities.defaultCapabilities,
    this.isInteractive = true,
  }) : _size = size;

  /// Whether this fake stands in for an interactive terminal. Set false to
  /// exercise the non-TTY (piped/redirected) code paths.
  @override
  bool isInteractive;

  CellSize _size;
  @override
  CellSize get size => _size;

  @override
  final TerminalCapabilities capabilities;

  final StringBuffer _output = StringBuffer();
  final StreamController<TuiEvent> _events =
      StreamController<TuiEvent>.broadcast();

  bool _active = false;
  TerminalMode? _enteredMode;

  /// Number of times [enter] was called. Useful for asserting
  /// idempotency / lifecycle in tests.
  int enterCallCount = 0;

  /// Number of times [restore] was called.
  int restoreCallCount = 0;

  @override
  bool get isActive => _active;

  /// The mode passed to the most recent [enter] call (or null if the
  /// driver has never been entered).
  TerminalMode? get currentMode => _enteredMode;

  /// All bytes written via [write] since this driver was constructed.
  String get output => _output.toString();

  /// Clears the captured output. Useful for asserting on the bytes
  /// produced by a specific frame.
  void clearOutput() {
    _output.clear();
  }

  /// Pushes an event onto the event stream. Tests use this to simulate
  /// keystrokes, resizes, etc.
  void enqueue(TuiEvent event) {
    _events.add(event);
  }

  /// Updates the driver's reported size and fires a [ResizeEvent].
  void resize(CellSize newSize) {
    _size = newSize;
    _events.add(ResizeEvent(newSize));
  }

  @override
  Stream<TuiEvent> get events => _events.stream;

  @override
  Future<void> enter(TerminalMode mode) async {
    enterCallCount += 1;
    _active = true;
    _enteredMode = mode;
  }

  @override
  Future<void> restore() async {
    if (!_active) return;
    restoreCallCount += 1;
    _active = false;
  }

  @override
  void write(String data) {
    _output.write(data);
  }

  /// Closes the underlying stream. Call this in test teardown so
  /// listeners don't hang.
  Future<void> dispose() => _events.close();
}
