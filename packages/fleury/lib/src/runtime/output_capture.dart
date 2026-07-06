// Consumer side of stray-output handling: sanitizes lines, buffers them for
// the in-app log surface ([LogBuffer] -> OutputCaptureView), routes them to a
// caller hook, and powers runApp's replay-on-exit. It does NOT capture
// anything itself — its feeders are:
//
//   - runApp's fd-level capture (package:stdio): fd 1/2 are dup2-moved before
//     the driver binds stdout, so EVERY writer — Dart print, loggers,
//     native/FFI libraries, inheritStdio children, code outside any zone — is
//     caught at the descriptor and streamed here as assembled lines. The
//     driver renders through the saved real-terminal handle, so frames are
//     never captured.
//   - process tasks ([ProcessTaskController]): child-process pipe chunks feed
//     [addChunk], which assembles them into lines.
//
// Where the fd capture doesn't engage (remote/serve sessions, custom drivers,
// Windows, FLEURY_FD_CAPTURE=0) stray output flows wherever fd 1/2 point —
// there is deliberately no weaker in-process fallback.

import '../foundation/change_notifier.dart';
import '../rendering/text_sanitizer.dart';

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
  bool _disposed = false;

  List<LogLine> get lines => List.unmodifiable(_lines);
  bool get isEmpty => _lines.isEmpty;
  int get length => _lines.length;

  void add(LogLine line) {
    _checkNotDisposed();
    _lines.add(line);
    if (_lines.length > capacity) {
      _lines.removeRange(0, _lines.length - capacity);
    }
    notifyListeners();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('LogBuffer has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

/// Routes intercepted output into a [LogBuffer] (and an optional live
/// [onLine] hook), assembling byte/string chunks into whole lines.
class OutputCapture {
  OutputCapture({
    required this.buffer,
    this.onLine,
    this.sanitizeForTerminal = false,
  });

  final LogBuffer buffer;
  final void Function(LogLine line)? onLine;
  final bool sanitizeForTerminal;

  final Map<LogSource, StringBuffer> _pending = {
    LogSource.stdout: StringBuffer(),
    LogSource.stderr: StringBuffer(),
  };

  void _emit(LogLine line) {
    final safeLine = sanitizeForTerminal
        ? LogLine(sanitizeForDisplay(line.text), line.source)
        : line;
    buffer.add(safeLine);
    onLine?.call(safeLine);
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

}
