// Captures stray output — `print()` and direct stdout/stderr writes from
// app or library code — while a TUI session owns the terminal, so it can't
// interleave with the rendered frame and corrupt the display.
//
// The driver holds the *real* stdout (resolved before these overrides take
// effect), so framework frames bypass capture entirely; only foreign writes
// inside the run zone are intercepted and buffered. `runTui` replays the
// buffer once the terminal is restored (or hands each line to a caller hook).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../foundation/change_notifier.dart';

/// Which standard stream a captured [LogLine] came from.
enum LogSource { stdout, stderr }

/// One captured logical line of stray output.
class LogLine {
  const LogLine(this.text, this.source);

  final String text;
  final LogSource source;

  @override
  String toString() => text;
}

/// A bounded, observable record of captured stray output. The oldest lines
/// are dropped once [capacity] is exceeded. Notifies listeners on each
/// append so a log view can repaint.
class LogBuffer extends ChangeNotifier {
  LogBuffer({this.capacity = 1000}) : assert(capacity > 0);

  final int capacity;
  final List<LogLine> _lines = <LogLine>[];

  List<LogLine> get lines => List.unmodifiable(_lines);
  bool get isEmpty => _lines.isEmpty;
  int get length => _lines.length;

  void add(LogLine line) {
    _lines.add(line);
    if (_lines.length > capacity) {
      _lines.removeRange(0, _lines.length - capacity);
    }
    notifyListeners();
  }
}

/// Routes intercepted output into a [LogBuffer] (and an optional live
/// [onLine] hook), assembling byte/string chunks into whole lines.
class OutputCapture {
  OutputCapture({required this.buffer, this.onLine});

  final LogBuffer buffer;
  final void Function(LogLine line)? onLine;

  final Map<LogSource, StringBuffer> _pending = {
    LogSource.stdout: StringBuffer(),
    LogSource.stderr: StringBuffer(),
  };

  void _emit(LogLine line) {
    buffer.add(line);
    onLine?.call(line);
  }

  /// A complete `print()` line (which may itself span multiple lines).
  void addLine(String text, LogSource source) => addChunk('$text\n', source);

  /// A raw write chunk, possibly with no trailing newline; the remainder is
  /// held until the rest of the line arrives (or [flushPartials]).
  void addChunk(String text, LogSource source) {
    final pending = _pending[source]!;
    final parts = (pending.toString() + text).split('\n');
    pending.clear();
    pending.write(parts.removeLast()); // trailing partial (no newline yet)
    for (final line in parts) {
      _emit(LogLine(line, source));
    }
  }

  /// Emits any held partial lines — call once the session ends so trailing
  /// output without a newline isn't lost.
  void flushPartials() {
    for (final source in LogSource.values) {
      final pending = _pending[source]!;
      if (pending.isNotEmpty) {
        _emit(LogLine(pending.toString(), source));
        pending.clear();
      }
    }
  }

  /// A [Stdout] stand-in that funnels everything written to it into this
  /// capture, tagged with [source]. Used via `IOOverrides`.
  Stdout sinkFor(LogSource source) => _CaptureSink(this, source);
}

/// A [Stdout] that captures instead of writing to a real terminal. Reports
/// itself as a non-terminal (no ANSI, no size) so well-behaved callers route
/// plain text through it; the size getters still return sane defaults rather
/// than throwing, so a logger probing them can't crash the session.
class _CaptureSink implements Stdout {
  _CaptureSink(this._capture, this._source);

  final OutputCapture _capture;
  final LogSource _source;

  void _text(String s) => _capture.addChunk(s, _source);

  @override
  Encoding encoding = utf8;

  @override
  void write(Object? object) => _text('$object');

  @override
  void writeln([Object? object = '']) => _text('$object\n');

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _text(objects.join(separator));

  @override
  void writeCharCode(int charCode) => _text(String.fromCharCode(charCode));

  @override
  void add(List<int> data) => _text(utf8.decode(data, allowMalformed: true));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(add);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  bool get hasTerminal => false;

  @override
  bool get supportsAnsiEscapes => false;

  @override
  int get terminalColumns => 80;

  @override
  int get terminalLines => 24;

  @override
  IOSink get nonBlocking => this;

  @override
  String get lineTerminator => '\n';

  @override
  set lineTerminator(String value) {}
}
