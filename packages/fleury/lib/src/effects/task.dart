import 'dart:async' show Completer, FutureOr, Timer;

import '../foundation/change_notifier.dart';
import '../semantics/semantics.dart';
import '../widgets/basic.dart';
import '../widgets/framework.dart';
import '../widgets/listenable_builder.dart';

typedef TaskRunner<T> = FutureOr<T> Function(TaskContext context);

enum TaskStatus { idle, running, succeeded, failed, canceled }

enum TaskOutputSeverity { info, warning, error }

enum TaskEventKind {
  started,
  progress,
  output,
  succeeded,
  failed,
  canceled,
  reset,
}

final class TaskCanceled implements Exception {
  const TaskCanceled([this.message = 'Task canceled.']);

  final String message;

  @override
  String toString() => message;
}

final class TaskProgress {
  const TaskProgress({this.current, this.total, this.label});

  final num? current;
  final num? total;
  final String? label;

  double? get fraction {
    final current = this.current;
    final total = this.total;
    if (current == null || total == null || total <= 0) return null;
    return (current / total).clamp(0.0, 1.0).toDouble();
  }
}

final class TaskOutput {
  const TaskOutput({
    required this.sequence,
    required this.text,
    this.source = 'task',
    this.severity = TaskOutputSeverity.info,
    this.sanitized = false,
    this.truncated = false,
    this.originalLength,
  });

  final int sequence;
  final String source;
  final String text;
  final TaskOutputSeverity severity;
  final bool sanitized;
  final bool truncated;
  final int? originalLength;
}

final class TaskEvent<T> {
  const TaskEvent({
    required this.sequence,
    required this.runId,
    required this.kind,
    required this.status,
    this.progress,
    this.output,
    this.value,
    this.error,
    this.stackTrace,
  });

  final int sequence;
  final int runId;
  final TaskEventKind kind;
  final TaskStatus status;
  final TaskProgress? progress;
  final TaskOutput? output;
  final T? value;
  final Object? error;
  final StackTrace? stackTrace;
}

final class TaskResult<T> {
  const TaskResult._({
    required this.status,
    this.value,
    this.error,
    this.stackTrace,
  });

  factory TaskResult.succeeded(T value) {
    return TaskResult._(status: TaskStatus.succeeded, value: value);
  }

  factory TaskResult.failed(Object error, StackTrace stackTrace) {
    return TaskResult._(
      status: TaskStatus.failed,
      error: error,
      stackTrace: stackTrace,
    );
  }

  factory TaskResult.canceled() {
    return const TaskResult._(status: TaskStatus.canceled);
  }

  final TaskStatus status;
  final T? value;
  final Object? error;
  final StackTrace? stackTrace;

  bool get succeeded => status == TaskStatus.succeeded;
  bool get failed => status == TaskStatus.failed;
  bool get canceled => status == TaskStatus.canceled;
}

/// Yield policy for long-running cooperative [TaskController] work.
///
/// This does not move work to another isolate. It gives CPU-heavy tasks such as
/// indexing and filtering an explicit place to report progress, check
/// cancellation, and yield to the event loop before monopolizing input/render
/// handling.
final class TaskYieldPolicy {
  const TaskYieldPolicy({
    this.itemBudget = 2048,
    this.elapsedBudget = const Duration(milliseconds: 8),
  }) : assert(itemBudget > 0);

  /// Maximum processed item count before yielding.
  final int itemBudget;

  /// Maximum elapsed time before yielding.
  final Duration elapsedBudget;

  TaskYieldCheckpoint start(TaskContext context) {
    if (elapsedBudget.isNegative) {
      throw ArgumentError.value(
        elapsedBudget,
        'elapsedBudget',
        'must not be negative',
      );
    }
    return TaskYieldCheckpoint._(context, this);
  }
}

/// Mutable checkpoint created by [TaskYieldPolicy.start].
final class TaskYieldCheckpoint {
  TaskYieldCheckpoint._(this._context, this._policy) {
    _stopwatch.start();
  }

  final TaskContext _context;
  final TaskYieldPolicy _policy;
  final Stopwatch _stopwatch = Stopwatch();
  var _processedSinceYield = 0;

  /// Records processed work and yields when [TaskYieldPolicy] says to.
  Future<void> tick({
    int processed = 1,
    num? current,
    num? total,
    String? label,
  }) async {
    assert(processed > 0);
    _context.checkCancellation();
    _processedSinceYield += processed;
    if (_processedSinceYield < _policy.itemBudget &&
        _stopwatch.elapsed < _policy.elapsedBudget) {
      return;
    }
    await yieldNow(current: current, total: total, label: label);
  }

  /// Yields immediately, optionally reporting progress first.
  Future<void> yieldNow({num? current, num? total, String? label}) async {
    _context.checkCancellation();
    if (current != null || total != null || label != null) {
      _context.reportProgress(current: current, total: total, label: label);
    }
    await Future<void>.delayed(Duration.zero);
    _context.checkCancellation();
    _processedSinceYield = 0;
    _stopwatch
      ..reset()
      ..start();
  }
}

final class TaskContext {
  const TaskContext._(this._controller, this._runId);

  final TaskController<Object?> _controller;
  final int _runId;

  bool get isCancellationRequested =>
      _controller._isCurrent(_runId) && _controller._cancelRequested;

  void checkCancellation() {
    if (isCancellationRequested) throw const TaskCanceled();
  }

  void reportProgress({num? current, num? total, String? label}) {
    _controller._reportProgress(
      _runId,
      TaskProgress(current: current, total: total, label: label),
    );
  }

  void write(
    String text, {
    String source = 'task',
    TaskOutputSeverity severity = TaskOutputSeverity.info,
    bool sanitized = false,
    bool truncated = false,
    int? originalLength,
  }) {
    _controller._writeOutput(
      _runId,
      source: source,
      text: text,
      severity: severity,
      sanitized: sanitized,
      truncated: truncated,
      originalLength: originalLength,
    );
  }
}

class TaskController<T> extends ChangeNotifier {
  TaskController({
    this.id,
    this.label,
    this.maxOutputEntries = 200,
    this.maxEventEntries = 400,
  }) : assert(maxOutputEntries > 0),
       assert(maxEventEntries > 0);

  final String? id;
  final String? label;
  final int maxOutputEntries;
  final int maxEventEntries;

  var _runId = 0;
  var _outputSequence = 0;
  var _eventSequence = 0;
  var _status = TaskStatus.idle;
  var _cancelRequested = false;
  var _disposed = false;
  TaskProgress? _progress;
  T? _value;
  Object? _error;
  StackTrace? _stackTrace;
  Future<TaskResult<T>>? _activeRun;
  Completer<TaskResult<T>>? _activeCompleter;
  final List<TaskOutput> _output = <TaskOutput>[];
  final List<TaskEvent<T>> _events = <TaskEvent<T>>[];

  TaskStatus get status => _status;
  bool get isRunning => _status == TaskStatus.running;
  bool get isCancellationRequested => _cancelRequested;
  TaskProgress? get progress => _progress;
  T? get value => _value;
  Object? get error => _error;
  StackTrace? get stackTrace => _stackTrace;
  List<TaskOutput> get output => List<TaskOutput>.unmodifiable(_output);
  List<TaskEvent<T>> get events => List<TaskEvent<T>>.unmodifiable(_events);
  bool get canCancel => isRunning;

  Future<TaskResult<T>> start(TaskRunner<T> runner, {bool restart = true}) {
    _checkNotDisposed();
    if (isRunning) {
      if (!restart) {
        final active = _activeRun;
        if (active != null) return active;
      }
      cancel();
    }

    final runId = ++_runId;
    _cancelRequested = false;
    _status = TaskStatus.running;
    _progress = null;
    _value = null;
    _error = null;
    _stackTrace = null;
    _outputSequence = 0;
    _output.clear();
    _recordEvent(TaskEventKind.started);
    notifyListeners();

    final completer = Completer<TaskResult<T>>();
    _activeCompleter = completer;
    _activeRun = completer.future;
    _run(runId, runner, completer);
    return completer.future;
  }

  void cancel() {
    if (_disposed || !isRunning) return;
    _cancelRequested = true;
    _status = TaskStatus.canceled;
    _activeRun = null;
    _completeIfOpen(_activeCompleter, TaskResult<T>.canceled());
    _activeCompleter = null;
    _recordEvent(TaskEventKind.canceled);
    notifyListeners();
  }

  void reset() {
    _checkNotDisposed();
    _runId++;
    _completeIfOpen(_activeCompleter, TaskResult<T>.canceled());
    _cancelRequested = false;
    _status = TaskStatus.idle;
    _progress = null;
    _value = null;
    _error = null;
    _stackTrace = null;
    _activeRun = null;
    _activeCompleter = null;
    _output.clear();
    _recordEvent(TaskEventKind.reset);
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _runId++;
    _cancelRequested = true;
    final wasRunning = isRunning;
    if (wasRunning) {
      _status = TaskStatus.canceled;
      _recordEvent(TaskEventKind.canceled);
    }
    _activeRun = null;
    _completeIfOpen(_activeCompleter, TaskResult<T>.canceled());
    _activeCompleter = null;
    super.dispose();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('TaskController has been disposed.');
    }
  }

  Future<void> _run(
    int runId,
    TaskRunner<T> runner,
    Completer<TaskResult<T>> completer,
  ) async {
    try {
      final context = TaskContext._(this as TaskController<Object?>, runId);
      final value = await runner(context);
      if (!_isCurrent(runId)) {
        _completeIfOpen(completer, TaskResult<T>.canceled());
        return;
      }
      if (_cancelRequested || _status == TaskStatus.canceled) {
        _completeIfOpen(completer, TaskResult<T>.canceled());
        return;
      }
      _status = TaskStatus.succeeded;
      _value = value;
      _activeRun = null;
      _activeCompleter = null;
      _recordEvent(TaskEventKind.succeeded, value: value);
      notifyListeners();
      _completeIfOpen(completer, TaskResult<T>.succeeded(value));
    } on TaskCanceled {
      if (_isCurrent(runId)) {
        final alreadyCanceled = _status == TaskStatus.canceled;
        _cancelRequested = true;
        _status = TaskStatus.canceled;
        _activeRun = null;
        _activeCompleter = null;
        if (!alreadyCanceled) _recordEvent(TaskEventKind.canceled);
        notifyListeners();
      }
      _completeIfOpen(completer, TaskResult<T>.canceled());
    } catch (error, stackTrace) {
      if (!_isCurrent(runId)) {
        _completeIfOpen(completer, TaskResult<T>.canceled());
        return;
      }
      _status = TaskStatus.failed;
      _error = error;
      _stackTrace = stackTrace;
      _activeRun = null;
      _activeCompleter = null;
      _recordEvent(TaskEventKind.failed, error: error, stackTrace: stackTrace);
      notifyListeners();
      _completeIfOpen(completer, TaskResult<T>.failed(error, stackTrace));
    }
  }

  void _completeIfOpen(
    Completer<TaskResult<T>>? completer,
    TaskResult<T> result,
  ) {
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  bool _isCurrent(int runId) => runId == _runId;

  void _recordEvent(
    TaskEventKind kind, {
    TaskProgress? progress,
    TaskOutput? output,
    T? value,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _eventSequence += 1;
    _events.add(
      TaskEvent<T>(
        sequence: _eventSequence,
        runId: _runId,
        kind: kind,
        status: _status,
        progress: progress,
        output: output,
        value: value,
        error: error,
        stackTrace: stackTrace,
      ),
    );
    while (_events.length > maxEventEntries) {
      _events.removeAt(0);
    }
  }

  void _reportProgress(int runId, TaskProgress progress) {
    if (!_isCurrent(runId) || !isRunning) return;
    _progress = progress;
    _recordEvent(TaskEventKind.progress, progress: progress);
    notifyListeners();
  }

  void _writeOutput(
    int runId, {
    required String source,
    required String text,
    required TaskOutputSeverity severity,
    required bool sanitized,
    required bool truncated,
    required int? originalLength,
  }) {
    if (!_isCurrent(runId) || !isRunning) return;
    _outputSequence += 1;
    final output = TaskOutput(
      sequence: _outputSequence,
      source: source,
      text: text,
      severity: severity,
      sanitized: sanitized,
      truncated: truncated,
      originalLength: originalLength,
    );
    _output.add(output);
    while (_output.length > maxOutputEntries) {
      _output.removeAt(0);
    }
    _recordEvent(TaskEventKind.output, output: output);
    notifyListeners();
  }
}

/// Debounces restartable work while preserving [TaskController] semantics.
///
/// This is useful for typeahead, search, indexing, and other workflows where
/// many input changes should collapse into one cancellable task.
class DebouncedTaskController<T> extends ChangeNotifier {
  DebouncedTaskController({
    required this.delay,
    TaskController<T>? taskController,
    String? id,
    String? label,
    int maxOutputEntries = 200,
    int maxEventEntries = 400,
  }) : assert(!delay.isNegative),
       taskController =
           taskController ??
           TaskController<T>(
             id: id,
             label: label,
             maxOutputEntries: maxOutputEntries,
             maxEventEntries: maxEventEntries,
           ),
       _ownsTaskController = taskController == null {
    this.taskController.addListener(notifyListeners);
  }

  /// Delay applied before the latest scheduled runner starts.
  final Duration delay;

  /// Underlying task state used for progress, output, events, and semantics.
  final TaskController<T> taskController;

  final bool _ownsTaskController;
  Timer? _timer;
  Completer<TaskResult<T>>? _pendingCompleter;
  TaskRunner<T>? _pendingRunner;
  bool _disposed = false;

  bool get isPending => _timer?.isActive ?? false;
  bool get isRunning => taskController.isRunning;
  bool get canCancel => isPending || taskController.canCancel;
  TaskStatus get status => taskController.status;
  TaskProgress? get progress => taskController.progress;
  T? get value => taskController.value;
  Object? get error => taskController.error;
  StackTrace? get stackTrace => taskController.stackTrace;
  List<TaskOutput> get output => taskController.output;
  List<TaskEvent<T>> get events => taskController.events;

  /// Schedule [runner], replacing any pending run.
  ///
  /// By default this also cancels an active run, matching typeahead semantics:
  /// the latest request owns the result.
  Future<TaskResult<T>> schedule(
    TaskRunner<T> runner, {
    Duration? delay,
    bool cancelRunning = true,
  }) {
    assert(delay == null || !delay.isNegative);
    _checkNotDisposed();
    _cancelPending(notify: false);
    if (cancelRunning) taskController.cancel();

    final completer = Completer<TaskResult<T>>();
    _pendingCompleter = completer;
    _pendingRunner = runner;
    final effectiveDelay = delay ?? this.delay;
    if (effectiveDelay == Duration.zero) {
      _startPending();
    } else {
      _timer = Timer(effectiveDelay, _startPending);
      notifyListeners();
    }
    return completer.future;
  }

  /// Start [runner] immediately, replacing pending work.
  Future<TaskResult<T>> runNow(
    TaskRunner<T> runner, {
    bool cancelRunning = true,
  }) {
    _checkNotDisposed();
    _cancelPending(notify: false);
    if (cancelRunning) taskController.cancel();
    final result = taskController.start(runner, restart: cancelRunning);
    notifyListeners();
    return result;
  }

  /// Cancel pending work and the active task, if any.
  void cancel() {
    if (_disposed) return;
    final canceledPending = _cancelPending(notify: false);
    taskController.cancel();
    if (canceledPending) notifyListeners();
  }

  /// Clear pending work and reset the underlying task controller.
  void reset() {
    _checkNotDisposed();
    _cancelPending(notify: false);
    taskController.reset();
    notifyListeners();
  }

  void _startPending() {
    final completer = _pendingCompleter;
    final runner = _pendingRunner;
    _timer = null;
    _pendingCompleter = null;
    _pendingRunner = null;
    if (_disposed) {
      _completePending(completer);
      return;
    }
    if (completer == null || runner == null) {
      notifyListeners();
      return;
    }
    final result = taskController.start(runner);
    result.then(
      (value) {
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    notifyListeners();
  }

  bool _cancelPending({required bool notify}) {
    final hadPending = _pendingCompleter != null || _timer != null;
    _timer?.cancel();
    _timer = null;
    final completer = _pendingCompleter;
    _pendingCompleter = null;
    _pendingRunner = null;
    _completePending(completer);
    if (hadPending && notify && !_disposed) notifyListeners();
    return hadPending;
  }

  void _completePending(Completer<TaskResult<T>>? completer) {
    if (completer != null && !completer.isCompleted) {
      completer.complete(TaskResult<T>.canceled());
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('DebouncedTaskController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelPending(notify: false);
    taskController.removeListener(notifyListeners);
    if (_ownsTaskController) taskController.dispose();
    super.dispose();
  }
}

class TaskStatusView<T> extends StatelessWidget {
  const TaskStatusView({super.key, required this.controller, this.child});

  final TaskController<T> controller;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      animation: controller,
      builder: (context, _) {
        final progress = controller.progress;
        final latestOutput = controller.output.isEmpty
            ? null
            : controller.output.last;
        final label = controller.label ?? controller.id ?? 'Task';
        return Semantics(
          role: SemanticRole.task,
          label: label,
          value: controller.status.name,
          busy: controller.isRunning,
          validationError: controller.error?.toString(),
          actions: {if (controller.isRunning) SemanticAction.cancel},
          onAction: controller.isRunning
              ? (action) {
                  if (action == SemanticAction.cancel) controller.cancel();
                }
              : null,
          state: SemanticState({
            if (controller.id != null) 'taskId': controller.id,
            if (controller.label != null) 'taskLabel': controller.label,
            'taskStatus': controller.status.name,
            'outputCount': controller.output.length,
            'taskEventCount': controller.events.length,
            if (controller.events.isNotEmpty)
              'lastTaskEventKind': controller.events.last.kind.name,
            if (latestOutput != null) 'source': latestOutput.source,
            if (latestOutput != null) 'severity': latestOutput.severity.name,
            if (latestOutput != null) 'outputSanitized': latestOutput.sanitized,
            if (latestOutput != null) 'outputTruncated': latestOutput.truncated,
            if (latestOutput?.originalLength != null)
              'outputOriginalLength': latestOutput!.originalLength,
            if (progress?.current != null) 'progressCurrent': progress!.current,
            if (progress?.total != null) 'progressTotal': progress!.total,
            if (progress?.label != null) 'progressLabel': progress!.label,
          }),
          child: child ?? Text('$label: ${controller.status.name}'),
        );
      },
    );
  }
}
