import 'dart:convert' show Encoding, Utf8Codec;
import 'dart:io' show Process, ProcessSignal, ProcessStartMode;

import 'package:meta/meta.dart' show protected;

import '../rendering/text_sanitizer.dart';
import '../runtime/output_capture.dart';
import '../terminal/terminal_driver.dart';
import 'task.dart';

/// Command metadata for a native subprocess-backed task.
final class ProcessTaskCommand {
  const ProcessTaskCommand(this.executable, [this.arguments = const <String>[]])
    : workingDirectory = null,
      environment = null,
      includeParentEnvironment = true,
      runInShell = false;

  const ProcessTaskCommand.configured({
    required this.executable,
    this.arguments = const <String>[],
    this.workingDirectory,
    this.environment,
    this.includeParentEnvironment = true,
    this.runInShell = false,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final bool includeParentEnvironment;
  final bool runInShell;

  String get displayName {
    if (arguments.isEmpty) return executable;
    return '$executable ${arguments.join(' ')}';
  }
}

/// Successful subprocess outcome.
final class ProcessTaskResult {
  const ProcessTaskResult({required this.command, required this.exitCode});

  final ProcessTaskCommand command;
  final int exitCode;

  bool get succeeded => exitCode == 0;
}

/// Failure raised when a subprocess exits non-zero.
final class ProcessTaskException implements Exception {
  const ProcessTaskException(this.result);

  final ProcessTaskResult result;

  @override
  String toString() =>
      'Process `${result.command.displayName}` exited with '
      'code ${result.exitCode}.';
}

/// Native task controller for bounded subprocess work.
///
/// This lives behind `package:fleury/fleury.dart`, not `fleury_core.dart`,
/// because it depends on `dart:io`. The core task model remains portable.
class ProcessTaskController extends TaskController<ProcessTaskResult> {
  ProcessTaskController({
    super.id,
    super.label,
    super.maxOutputEntries,
    super.maxEventEntries,
    this.encoding = const Utf8Codec(allowMalformed: true),
    this.maxOutputLineLength = 4096,
  }) : assert(maxOutputLineLength > 0);

  final Encoding encoding;
  final int maxOutputLineLength;

  Process? _process;
  ProcessSignal _cancelSignal = ProcessSignal.sigterm;
  ProcessTaskCommand? _command;

  Process? get process => _process;
  ProcessTaskCommand? get command => _command;

  /// Starts [command] as a child process bound to this task.
  ///
  /// [mode] supports [ProcessStartMode.normal] (stdout/stderr are captured
  /// as task output) and [ProcessStartMode.inheritStdio] (the child talks to
  /// the terminal directly, typically combined with [handoffTerminal]).
  /// Detached modes are rejected with an [ArgumentError]: a detached child
  /// cannot report the exit code that settles the task.
  Future<TaskResult<ProcessTaskResult>> startProcess(
    ProcessTaskCommand command, {
    bool restart = true,
    TerminalDriver? terminalDriver,
    bool handoffTerminal = false,
    ProcessStartMode mode = ProcessStartMode.normal,
    ProcessSignal cancelSignal = ProcessSignal.sigterm,
  }) {
    if (mode == ProcessStartMode.detached ||
        mode == ProcessStartMode.detachedWithStdio) {
      throw ArgumentError.value(
        mode,
        'mode',
        'Detached processes cannot report the exit code that settles the '
            'task. Use Process.start directly for fire-and-forget children.',
      );
    }
    _cancelSignal = cancelSignal;
    _command = command;
    return start((context) {
      Future<ProcessTaskResult> run() =>
          _runProcess(context, command, mode, cancelSignal);
      if (handoffTerminal && terminalDriver != null) {
        return withTerminalHandoff(terminalDriver, run);
      }
      return run();
    }, restart: restart);
  }

  @override
  void cancel() {
    if (isRunning) {
      _process?.kill(_cancelSignal);
    }
    super.cancel();
  }

  @override
  void reset() {
    if (isRunning) {
      _process?.kill(_cancelSignal);
    }
    _process = null;
    _command = null;
    super.reset();
  }

  @override
  void dispose() {
    // The base dispose cancels the active run without going through the
    // virtual cancel(), so the subprocess kill must happen here.
    if (isRunning) {
      _process?.kill(_cancelSignal);
    }
    _process = null;
    super.dispose();
  }

  /// Spawns the child process for one [startProcess] run.
  ///
  /// Subclasses can override this to control spawn timing or substitute
  /// process construction in tests.
  @protected
  Future<Process> spawnProcess(
    ProcessTaskCommand command,
    ProcessStartMode mode,
  ) {
    return Process.start(
      command.executable,
      command.arguments,
      workingDirectory: command.workingDirectory,
      environment: command.environment,
      includeParentEnvironment: command.includeParentEnvironment,
      runInShell: command.runInShell,
      mode: mode,
    );
  }

  Future<ProcessTaskResult> _runProcess(
    TaskContext context,
    ProcessTaskCommand command,
    ProcessStartMode mode,
    ProcessSignal cancelSignal,
  ) async {
    final process = await spawnProcess(command, mode);
    if (context.isCancellationRequested) {
      // The run was canceled, superseded, or disposed while spawning: kill
      // the child and never let it become this controller's current process.
      process.kill(cancelSignal);
      await process.exitCode;
      context.checkCancellation();
    }
    _process = process;
    var exited = false;
    try {
      context.reportProgress(label: 'running');

      var stdoutDone = Future<void>.value();
      var stderrDone = Future<void>.value();
      OutputCapture? capture;
      if (mode == ProcessStartMode.normal) {
        // Only normal mode connects stdio pipes; an inheritStdio child talks
        // to the terminal directly and has nothing to capture.
        capture = OutputCapture(
          buffer: LogBuffer(),
          onLine: (line) {
            final sanitized = _sanitizeProcessLine(line.text);
            context.write(
              sanitized.text,
              source: line.source.name,
              severity: line.source == LogSource.stderr
                  ? TaskOutputSeverity.error
                  : TaskOutputSeverity.info,
              sanitized: sanitized.sanitized,
              truncated: sanitized.truncated,
              originalLength: sanitized.changed ? line.text.length : null,
            );
          },
        );
        stdoutDone = _pipeProcessOutput(
          process.stdout.transform(encoding.decoder),
          capture,
          LogSource.stdout,
        );
        stderrDone = _pipeProcessOutput(
          process.stderr.transform(encoding.decoder),
          capture,
          LogSource.stderr,
        );
      }

      final exitCode = await process.exitCode;
      exited = true;
      await Future.wait([stdoutDone, stderrDone]);
      capture?.flushPartials();
      final result = ProcessTaskResult(command: command, exitCode: exitCode);
      context.checkCancellation();
      if (exitCode != 0) throw ProcessTaskException(result);
      context.reportProgress(current: 1, total: 1, label: 'exited 0');
      return result;
    } finally {
      // A failure before the child exited must not orphan it.
      if (!exited) process.kill(cancelSignal);
      if (identical(_process, process)) _process = null;
    }
  }

  Future<void> _pipeProcessOutput(
    Stream<String> stream,
    OutputCapture capture,
    LogSource source,
  ) {
    final subscription = stream.listen(
      (chunk) => capture.addChunk(chunk, source),
      cancelOnError: true,
    );
    return subscription.asFuture<void>();
  }

  _SanitizedProcessLine _sanitizeProcessLine(String line) {
    var text = sanitizeForDisplay(line);
    final sanitized = text != line;
    var truncated = false;
    final runeLength = text.runes.length;
    if (runeLength > maxOutputLineLength) {
      text = String.fromCharCodes(text.runes.take(maxOutputLineLength));
      truncated = true;
    }
    return _SanitizedProcessLine(
      text: text,
      sanitized: sanitized,
      changed: sanitized || truncated,
      truncated: truncated,
    );
  }
}

final class _SanitizedProcessLine {
  const _SanitizedProcessLine({
    required this.text,
    required this.sanitized,
    required this.changed,
    required this.truncated,
  });

  final String text;
  final bool sanitized;
  final bool changed;
  final bool truncated;
}
