import 'dart:async' show unawaited;
import 'dart:io' show ProcessSignal, ProcessStartMode;

import '../app/commands.dart';
import '../semantics/semantics.dart';
import '../terminal/terminal_driver.dart';
import '../widgets/framework.dart';
import '../widgets/key_bindings.dart';
import 'process_task.dart';
import 'task.dart';

/// App-command binding for a native [ProcessTaskController].
///
/// The runner starts and cancels process work through existing task state. It
/// intentionally does not store output or duplicate process lifecycle policy;
/// [ProcessTaskController] remains the source of truth.
final class ProcessCommandRunner {
  ProcessCommandRunner({
    required this.controller,
    required this.command,
    CommandId? startCommandId,
    CommandId? cancelCommandId,
    String? title,
    String? cancelTitle,
    this.description,
    this.cancelDescription,
    this.category = 'Process',
    this.shortcuts = const <KeyChord>[],
    this.cancelShortcuts = const <KeyChord>[],
    this.restart = false,
    this.terminalDriver,
    this.handoffTerminal = false,
    this.mode = ProcessStartMode.normal,
    this.cancelSignal = ProcessSignal.sigterm,
  }) : startCommandId =
           startCommandId ?? _defaultCommandId(controller, command, 'start'),
       cancelCommandId =
           cancelCommandId ?? _defaultCommandId(controller, command, 'cancel'),
       title = title ?? 'Run ${command.displayName}',
       cancelTitle = cancelTitle ?? 'Cancel ${command.displayName}';

  final ProcessTaskController controller;
  final ProcessTaskCommand command;
  final CommandId startCommandId;
  final CommandId cancelCommandId;
  final String title;
  final String cancelTitle;
  final String? description;
  final String? cancelDescription;
  final String category;
  final List<KeyChord> shortcuts;
  final List<KeyChord> cancelShortcuts;
  final bool restart;
  final TerminalDriver? terminalDriver;
  final bool handoffTerminal;
  final ProcessStartMode mode;
  final ProcessSignal cancelSignal;

  bool get canStart => restart || !controller.isRunning;
  bool get canCancel => controller.canCancel;

  Future<TaskResult<ProcessTaskResult>> start() {
    return controller.startProcess(
      command,
      restart: restart,
      terminalDriver: terminalDriver,
      handoffTerminal: handoffTerminal,
      mode: mode,
      cancelSignal: cancelSignal,
    );
  }

  void cancel() {
    controller.cancel();
  }

  AppCommand get startCommand {
    return AppCommand(
      id: startCommandId,
      title: title,
      description: description,
      category: category,
      shortcuts: shortcuts,
      enabled: (_) => canStart,
      semanticAction: SemanticAction.start,
      run: (_) {
        unawaited(start());
      },
    );
  }

  AppCommand get cancelCommand {
    return AppCommand(
      id: cancelCommandId,
      title: cancelTitle,
      description: cancelDescription,
      category: category,
      shortcuts: cancelShortcuts,
      enabled: (_) => canCancel,
      semanticAction: SemanticAction.cancel,
      run: (_) {
        cancel();
      },
    );
  }

  List<AppCommand> get commands => <AppCommand>[startCommand, cancelCommand];
}

/// Installs process start/cancel commands and refreshes them as task state
/// changes.
class ProcessCommandScope extends StatefulWidget {
  const ProcessCommandScope({
    super.key,
    required this.runner,
    required this.child,
    this.label = 'Process commands',
    this.enabled = true,
  });

  final ProcessCommandRunner runner;
  final Widget child;
  final String label;
  final bool enabled;

  @override
  State<ProcessCommandScope> createState() => _ProcessCommandScopeState();
}

class _ProcessCommandScopeState extends State<ProcessCommandScope> {
  @override
  void initState() {
    super.initState();
    widget.runner.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant ProcessCommandScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.runner.controller, oldWidget.runner.controller)) {
      oldWidget.runner.controller.removeListener(_onControllerChanged);
      widget.runner.controller.addListener(_onControllerChanged);
    }
  }

  void _onControllerChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    widget.runner.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommandScope(
      commands: widget.runner.commands,
      label: widget.label,
      enabled: widget.enabled,
      child: widget.child,
    );
  }
}

CommandId _defaultCommandId(
  ProcessTaskController controller,
  ProcessTaskCommand command,
  String action,
) {
  final base = controller.id ?? command.executable;
  return CommandId('process.${_commandIdPart(base)}.$action');
}

String _commandIdPart(String text) {
  final buffer = StringBuffer();
  var previousWasDash = false;
  for (final codeUnit in text.codeUnits) {
    final lower = _lowerAscii(codeUnit);
    final valid =
        (lower >= 0x61 && lower <= 0x7a) || (lower >= 0x30 && lower <= 0x39);
    if (valid) {
      buffer.writeCharCode(lower);
      previousWasDash = false;
      continue;
    }
    if (!previousWasDash && buffer.isNotEmpty) {
      buffer.write('-');
      previousWasDash = true;
    }
  }
  var result = buffer.toString();
  while (result.endsWith('-')) {
    result = result.substring(0, result.length - 1);
  }
  return result.isEmpty ? 'command' : result;
}

int _lowerAscii(int codeUnit) {
  if (codeUnit >= 0x41 && codeUnit <= 0x5a) return codeUnit + 0x20;
  return codeUnit;
}
