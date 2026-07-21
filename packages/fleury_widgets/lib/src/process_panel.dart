import 'package:fleury/fleury.dart';

import 'log_region.dart';
import 'progress_bar.dart';

/// Converts task output into structured [LogRegion] entries.
List<LogEntry> buildProcessOutputLogEntries(Iterable<TaskOutput> output) {
  return List<LogEntry>.unmodifiable(
    output.map((entry) {
      return LogEntry(
        id: entry.sequence,
        severity: _severityForOutput(entry.severity),
        source: entry.source,
        message: entry.text,
        metadata: <String, Object?>{
          'taskOutputSequence': entry.sequence,
          'outputSanitized': entry.sanitized,
          'outputTruncated': entry.truncated,
          if (entry.originalLength != null)
            'outputOriginalLength': entry.originalLength,
        },
      );
    }),
  );
}

/// Process/task chrome with status semantics and a structured output region.
class ProcessPanel extends StatelessWidget {
  const ProcessPanel({
    super.key,
    required this.controller,
    this.command,
    this.label,
    this.outputController,
    this.focusNode,
    this.autofocus = false,
    this.outputFilter,
    this.copyOutput = true,
    this.copyOptions = const LogRegionCopyOptions(),
    this.onCopy,
    this.cancelShortcut = KeySequence.escape,
    this.showHeader = true,
    this.showProgress = true,
    this.border,
    this.padding,
  });

  /// Task controller that owns process status, progress, events, and output.
  final ProcessTaskController controller;

  /// Command metadata displayed in the panel header.
  final ProcessTaskCommand? command;

  /// Optional label overriding the controller label in the header and semantics.
  final String? label;

  /// External output-list controller.
  final LogRegionController? outputController;

  /// Focus node used by the output region.
  final FocusNode? focusNode;

  /// Whether the output region should request focus when mounted.
  final bool autofocus;

  /// Optional filter applied to process output rows.
  final LogRegionFilterDescriptor? outputFilter;

  /// Whether Ctrl+C and semantic copy export the selected output row.
  final bool copyOutput;

  /// Clipboard/export options for copied output.
  final LogRegionCopyOptions copyOptions;

  /// Called after a process-output copy attempt completes.
  final void Function(LogRegionCopyResult result)? onCopy;

  /// Shortcut that cancels the running process; null disables the binding.
  final KeySequence? cancelShortcut;

  /// Whether to render the status/command header above output.
  final bool showHeader;

  /// Whether to render a progress bar when progress is available.
  final bool showProgress;

  /// Optional border around the whole process panel.
  final BoxBorder? border;

  /// Optional padding inside [border].
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _buildPanel(context),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final command = _resolvedCommand(controller, this.command);
    final entries = buildProcessOutputLogEntries(controller.output);
    final progress = controller.progress;
    final title = label ?? controller.label ?? controller.id ?? 'Process';
    final canCancel = controller.canCancel;

    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) ...[
          _ProcessHeader(
            title: title,
            status: controller.status,
            command: command,
            progress: progress,
            showProgress: showProgress,
          ),
          const SizedBox(height: 1),
        ],
        Expanded(
          child: LogRegion(
            entries: entries,
            controller: outputController,
            focusNode: focusNode,
            autofocus: autofocus,
            semanticLabel: '$title output',
            filter: outputFilter,
            copySelection: copyOutput,
            copyOptions: copyOptions,
            onCopy: onCopy,
          ),
        ),
      ],
    );

    if (border != null || padding != null) {
      body = Container(border: border, padding: padding, child: body);
    }

    final shortcut = cancelShortcut;
    if (canCancel && shortcut != null) {
      body = KeyBindings(
        bindings: [
          KeyBinding(
            shortcut,
            label: 'Cancel process',
            onTrigger: () => controller.cancel(),
          ),
        ],
        child: body,
      );
    }

    return Semantics(
      role: SemanticRole.task,
      label: title,
      value: controller.status.name,
      busy: controller.isRunning,
      validationError: controller.error?.toString(),
      actions: {if (canCancel) SemanticAction.cancel},
      onAction: (action) {
        if (action == SemanticAction.cancel && controller.canCancel) {
          controller.cancel();
        }
      },
      state: SemanticState({
        if (controller.id != null) 'taskId': controller.id,
        if (controller.label != null) 'taskLabel': controller.label,
        'taskStatus': controller.status.name,
        'outputCount': controller.output.length,
        'taskEventCount': controller.events.length,
        if (controller.events.isNotEmpty)
          'lastTaskEventKind': controller.events.last.kind.name,
        'canCancel': canCancel,
        if (command != null) 'command': command.displayName,
        ..._processResultState(controller),
        ..._latestOutputState(controller.output),
        if (progress?.current != null) 'progressCurrent': progress!.current,
        if (progress?.total != null) 'progressTotal': progress!.total,
        if (progress?.label != null) 'progressLabel': progress!.label,
      }),
      child: body,
    );
  }
}

class _ProcessHeader extends StatelessWidget {
  const _ProcessHeader({
    required this.title,
    required this.status,
    required this.command,
    required this.progress,
    required this.showProgress,
  });

  final String title;
  final TaskStatus status;
  final ProcessTaskCommand? command;
  final TaskProgress? progress;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final command = this.command;
    final progress = this.progress;
    final fraction = progress?.fraction;
    final statusText = command == null
        ? '$title: ${status.name}'
        : '$title: ${status.name} - ${command.displayName}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(statusText, style: _styleForStatus(context, status)),
        if (progress?.label != null) Text(progress!.label!),
        if (showProgress && fraction != null)
          ProgressBar(
            value: fraction,
            filledStyle: _styleForStatus(context, status),
          ),
      ],
    );
  }
}

ProcessTaskCommand? _resolvedCommand(
  ProcessTaskController controller,
  ProcessTaskCommand? explicit,
) {
  if (explicit != null) return explicit;
  final value = controller.value;
  if (value != null) return value.command;
  final error = controller.error;
  if (error is ProcessTaskException) return error.result.command;
  return controller.command;
}

Map<String, Object?> _processResultState(ProcessTaskController controller) {
  final value = controller.value;
  if (value != null) {
    return <String, Object?>{
      'exitCode': value.exitCode,
      'processSucceeded': value.succeeded,
    };
  }
  final error = controller.error;
  if (error is ProcessTaskException) {
    return <String, Object?>{
      'exitCode': error.result.exitCode,
      'processSucceeded': error.result.succeeded,
    };
  }
  return const <String, Object?>{};
}

Map<String, Object?> _latestOutputState(List<TaskOutput> output) {
  if (output.isEmpty) return const <String, Object?>{};
  final latest = output.last;
  return <String, Object?>{
    'source': latest.source,
    'severity': latest.severity.name,
    'outputSanitized': latest.sanitized,
    'outputTruncated': latest.truncated,
    if (latest.originalLength != null)
      'outputOriginalLength': latest.originalLength,
  };
}

LogSeverity _severityForOutput(TaskOutputSeverity severity) {
  return switch (severity) {
    TaskOutputSeverity.info => LogSeverity.info,
    TaskOutputSeverity.warning => LogSeverity.warning,
    TaskOutputSeverity.error => LogSeverity.error,
  };
}

CellStyle _styleForStatus(BuildContext context, TaskStatus status) {
  final theme = Theme.of(context);
  return switch (status) {
    TaskStatus.idle => theme.mutedStyle,
    TaskStatus.running => CellStyle(
      bold: true,
      foreground: theme.colorScheme.primary,
    ),
    TaskStatus.succeeded => CellStyle(
      bold: true,
      foreground: theme.colorScheme.success,
    ),
    TaskStatus.failed => CellStyle(
      bold: true,
      foreground: theme.colorScheme.error,
    ),
    TaskStatus.canceled => theme.mutedStyle,
  };
}
