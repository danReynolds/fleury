import 'dart:async';

import '../foundation/geometry.dart';
import 'capabilities.dart';
import '../input/events.dart';
import '../runtime/remote_surface_sink.dart';
import 'terminal_driver.dart';

/// A [TerminalDriver] for tests and offline rendering. No real I/O —
/// the driver buffers everything written, exposes the buffer for
/// assertions, and lets the test push events into the event stream.
final class FakeTerminalDriver
    implements TerminalDriver, TerminalHandoffDriver {
  FakeTerminalDriver({
    CellSize size = const CellSize(80, 24),
    this.capabilities = TerminalCapabilities.defaultCapabilities,
    bool isInteractive = true,
  }) : _size = size,
       _isInteractive = isInteractive;

  /// Whether this fake stands in for an interactive terminal. Set false to
  /// exercise the non-TTY (piped/redirected) code paths.
  @override
  bool get isInteractive => _isInteractive;

  @override
  RemoteSurfaceSink? get surfaceSink => null; // byte presentation only
  set isInteractive(bool value) {
    _checkNotDisposed();
    _isInteractive = value;
  }

  CellSize _size;
  bool _isInteractive;
  @override
  CellSize get size => _size;

  @override
  final TerminalCapabilities capabilities;

  final StringBuffer _output = StringBuffer();
  final StreamController<TuiEvent> _events =
      StreamController<TuiEvent>.broadcast();

  bool _active = false;
  bool _handoffActive = false;
  bool _disposed = false;
  TerminalMode? _enteredMode;

  /// Number of times [enter] was called. Useful for asserting
  /// idempotency / lifecycle in tests.
  int enterCallCount = 0;

  /// Number of times [restore] was called.
  int restoreCallCount = 0;

  /// Number of terminal handoff operations run through this driver.
  int handoffCallCount = 0;

  /// Number of times an active fake terminal was suspended for handoff.
  int handoffSuspendCallCount = 0;

  /// Number of times an active fake terminal was resumed after handoff.
  int handoffResumeCallCount = 0;

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
    _checkNotDisposed();
    _output.clear();
  }

  /// Pushes an event onto the event stream. Tests use this to simulate
  /// keystrokes, resizes, etc.
  void enqueue(TuiEvent event) {
    _checkNotDisposed();
    _events.add(event);
  }

  /// Updates the driver's reported size and fires a [ResizeEvent].
  void resize(CellSize newSize) {
    _checkNotDisposed();
    _size = newSize;
    _events.add(ResizeEvent(newSize));
  }

  @override
  Stream<TuiEvent> get events => _events.stream;

  @override
  Future<void> enter(TerminalMode mode) async {
    _checkNotDisposed();
    enterCallCount += 1;
    _active = true;
    _enteredMode = mode;
  }

  @override
  Future<void> restore() async {
    if (!_active && !_handoffActive) return;
    restoreCallCount += 1;
    _active = false;
    _handoffActive = false;
  }

  @override
  Future<T> runWithTerminalHandoff<T>(FutureOr<T> Function() operation) async {
    _checkNotDisposed();
    handoffCallCount += 1;
    if (!_active) return await operation();

    handoffSuspendCallCount += 1;
    _handoffActive = true;
    _active = false;
    try {
      return await operation();
    } finally {
      if (_handoffActive) {
        _handoffActive = false;
        _active = true;
        handoffResumeCallCount += 1;
        _events.add(ResizeEvent(size));
      }
    }
  }

  @override
  void write(String data) {
    _checkNotDisposed();
    if (_handoffActive) return;
    _output.write(data);
  }

  /// Closes the underlying stream. Call this in test teardown so
  /// listeners don't hang.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _active = false;
    _handoffActive = false;
    await _events.close();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('FakeTerminalDriver has been disposed.');
    }
  }
}
