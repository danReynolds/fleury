import 'dart:async' show scheduleMicrotask, unawaited;

import 'package:fleury/fleury_core.dart';

/// Protocol-neutral status for a node in a [TaskGraph].
enum TaskGraphStatus { pending, running, succeeded, failed, cancelled, skipped }

/// One node in a compact protocol-neutral task/plan graph.
final class TaskGraphNode {
  const TaskGraphNode({
    required this.id,
    required this.title,
    this.description,
    this.status = TaskGraphStatus.pending,
    this.dependsOn = const <String>[],
    this.progressCurrent,
    this.progressTotal,
    this.metadata = const <String, Object?>{},
  });

  /// Stable task identity used by semantics and selection preservation.
  final String id;

  /// Primary task label.
  final String title;

  /// Optional longer task description.
  final String? description;

  /// Current task lifecycle status.
  final TaskGraphStatus status;

  /// Task ids that must complete before this task.
  final List<String> dependsOn;

  /// Current progress value, when known.
  final num? progressCurrent;

  /// Total progress value, when known.
  final num? progressTotal;

  /// App-specific semantic state carried by the task.
  final Map<String, Object?> metadata;

  bool get busy => status == TaskGraphStatus.running;
}

/// Controller for [TaskGraph] selection and viewport state.
class TaskGraphController extends ChangeNotifier {
  TaskGraphController({int selectedIndex = 0})
    : _list = ListController(selectedIndex: selectedIndex) {
    _list.addListener(notifyListeners);
  }

  final ListController _list;
  bool _disposed = false;

  ListController get _listController => _list;

  int? get selectedIndex => _list.selectedIndex;
  set selectedIndex(int? value) {
    _checkNotDisposed();
    _list.selectedIndex = value;
  }

  ({int first, int last})? get visibleRange => _list.visibleRange;

  void jumpToIndex(int index) {
    _checkNotDisposed();
    _list.jumpToIndex(index);
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('TaskGraphController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _list.removeListener(notifyListeners);
    _list.dispose();
    super.dispose();
  }
}

/// Options for copying or exporting a task-graph node.
final class TaskGraphCopyOptions {
  const TaskGraphCopyOptions({
    this.includeDescription = true,
    this.includeDependencies = true,
    this.clipboardPolicy = ClipboardWritePolicy.standard,
  });

  /// Whether copied node text includes [TaskGraphNode.description].
  final bool includeDescription;

  /// Whether copied node text includes [TaskGraphNode.dependsOn].
  final bool includeDependencies;

  /// Clipboard write behavior for copied node text.
  final ClipboardWritePolicy clipboardPolicy;
}

/// Result delivered after [TaskGraph] copies the selected node.
final class TaskGraphCopyResult {
  const TaskGraphCopyResult({
    required this.nodeIndex,
    required this.node,
    required this.text,
    required this.report,
  });

  final int nodeIndex;
  final TaskGraphNode node;
  final String text;
  final ClipboardWriteReport report;
}

/// Exports one task node as sanitized text suitable for copy/debug evidence.
String exportTaskGraphNode(
  TaskGraphNode node, {
  TaskGraphCopyOptions options = const TaskGraphCopyOptions(),
}) {
  final lines = <String>[
    '${_statusMarker(node.status)} ${_sanitizeTaskText(node.title)}',
    'Status: ${node.status.name}',
  ];
  if (options.includeDescription && node.description != null) {
    lines.add('Description: ${_sanitizeTaskText(node.description!)}');
  }
  if (options.includeDependencies && node.dependsOn.isNotEmpty) {
    lines.add(
      'Depends on: ${node.dependsOn.map(_sanitizeTaskText).join(', ')}',
    );
  }
  if (node.progressCurrent != null || node.progressTotal != null) {
    lines.add(_progressText(node));
  }
  return lines.join('\n');
}

/// Compact task/plan graph for developer and agent-style workflows.
class TaskGraph extends StatefulWidget {
  const TaskGraph({
    super.key,
    required this.nodes,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel = 'Task graph',
    this.copySelection = true,
    this.copyOptions = const TaskGraphCopyOptions(),
    this.onCopy,
  });

  /// Source task nodes to display and copy.
  final List<TaskGraphNode> nodes;

  /// External selection and visible-range controller.
  final TaskGraphController? controller;

  /// Focus node used for keyboard navigation.
  final FocusNode? focusNode;

  /// Whether the graph should request focus when mounted.
  final bool autofocus;

  /// Semantic label (the accessibility name; not rendered) for the task graph.
  final String semanticLabel;

  /// Whether Ctrl+C and semantic copy export the selected task.
  final bool copySelection;

  /// Clipboard/export options for selected-task copy.
  final TaskGraphCopyOptions copyOptions;

  /// Called after a copy attempt completes.
  final void Function(TaskGraphCopyResult result)? onCopy;

  @override
  State<TaskGraph> createState() => _TaskGraphState();
}

class _TaskGraphState extends State<TaskGraph> {
  late TaskGraphController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  bool _focusedWithin = false;
  String? _pendingSelectedTaskId;
  int _selectionSyncGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TaskGraphController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'TaskGraph');
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(covariant TaskGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? TaskGraphController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'TaskGraph');
      _ownsFocusNode = widget.focusNode == null;
    }
    if (widget.nodes != oldWidget.nodes) {
      _syncSelectionAfterNodeUpdate(oldWidget.nodes);
    }
  }

  void _onControllerChange() => setState(() {});

  void _syncSelectionAfterNodeUpdate(List<TaskGraphNode> oldNodes) {
    _selectionSyncGeneration++;
    _pendingSelectedTaskId = null;
    if (widget.nodes.isEmpty) {
      _controller.selectedIndex = null;
      return;
    }
    final selectedIndex = _controller.selectedIndex;
    if (selectedIndex == null) {
      _controller.selectedIndex = 0;
      return;
    }
    if (selectedIndex >= 0 && selectedIndex < oldNodes.length) {
      final selectedId = oldNodes[selectedIndex].id;
      final nextIndex = widget.nodes.indexWhere(
        (node) => node.id == selectedId,
      );
      if (nextIndex != -1) {
        _selectIndexAfterListCountRefresh(selectedId, nextIndex);
        return;
      }
    }
    _controller.selectedIndex = selectedIndex.clamp(0, widget.nodes.length - 1);
  }

  void _selectIndexAfterListCountRefresh(String selectedId, int nextIndex) {
    final knownItemCount = _controller._listController.itemCount;
    if (knownItemCount == 0 || nextIndex < knownItemCount) {
      _controller.selectedIndex = nextIndex;
      return;
    }

    _pendingSelectedTaskId = selectedId;
    final generation = _selectionSyncGeneration;
    final binding = TuiBinding.maybeOf(context);
    if (binding == null) {
      scheduleMicrotask(() {
        _applyPendingSelection(generation, selectedId);
      });
      return;
    }
    binding.addPostFrameCallback((_) {
      _applyPendingSelection(generation, selectedId);
    });
  }

  void _applyPendingSelection(int generation, String selectedId) {
    if (!mounted || generation != _selectionSyncGeneration) return;
    if (_pendingSelectedTaskId != selectedId) return;
    final nextIndex = widget.nodes.indexWhere((node) => node.id == selectedId);
    if (nextIndex == -1) {
      _pendingSelectedTaskId = null;
      return;
    }
    _pendingSelectedTaskId = null;
    _controller.selectedIndex = nextIndex;
  }

  void _onFocusWithinChange(bool focused) {
    if (_focusedWithin == focused) return;
    setState(() {
      _focusedWithin = focused;
    });
  }

  void _focusGraph() {
    _focusNode.requestFocus();
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  Future<void> _copySelection({bool focusGraph = false}) async {
    if (!widget.copySelection || widget.nodes.isEmpty) return;
    if (focusGraph) _focusGraph();
    final selected = (_controller.selectedIndex ?? 0).clamp(
      0,
      widget.nodes.length - 1,
    );
    final node = widget.nodes[selected];
    final text = exportTaskGraphNode(node, options: widget.copyOptions);
    final report = await ClipboardScope.of(
      context,
    ).writeWithReport(text, policy: widget.copyOptions.clipboardPolicy);
    if (!mounted) return;
    widget.onCopy?.call(
      TaskGraphCopyResult(
        nodeIndex: selected,
        node: node,
        text: text,
        report: report,
      ),
    );
  }

  void _activateAt(int index) {
    if (index < 0 || index >= widget.nodes.length) return;
    _focusGraph();
    _controller.selectedIndex = index;
  }

  Future<void> _copyAt(int index) async {
    if (index < 0 || index >= widget.nodes.length) return;
    _focusGraph();
    _controller.selectedIndex = index;
    await _copySelection();
  }

  Future<void> _handleGraphAction(SemanticAction action) async {
    switch (action) {
      case SemanticAction.focus:
      case SemanticAction.navigate:
        _focusGraph();
        return;
      case SemanticAction.copy:
        await _copySelection(focusGraph: true);
        return;
      case _:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _controller.selectedIndex;
    final visibleRange = _controller.visibleRange;
    final copyEnabled = widget.copySelection && widget.nodes.isNotEmpty;
    final selectedNode =
        selectedIndex == null ||
            selectedIndex < 0 ||
            selectedIndex >= widget.nodes.length
        ? null
        : widget.nodes[selectedIndex];

    Widget list = ListView.builder(
      controller: _controller._listController,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      itemCount: widget.nodes.length,
      onSelect: _activateAt,
      itemBuilder: (context, index, activeSelected) {
        final selected = index == _controller.selectedIndex;
        return _TaskGraphRow(
          node: widget.nodes[index],
          index: index,
          selected: selected,
          activeSelection: activeSelected,
          copyEnabled: copyEnabled,
          onActivate: () => _activateAt(index),
          onCopy: () => _copyAt(index),
        );
      },
    );

    if (copyEnabled) {
      list = KeyBindings(
        bindings: [
          KeyBinding(
            KeyChord.ctrl.c,
            label: 'Copy task',
            onEvent: (_) => unawaited(_copySelection()),
          ),
        ],
        child: list,
      );
    }

    final counts = _statusCounts(widget.nodes);
    return FocusWithin(
      onFocusChange: _onFocusWithinChange,
      child: Semantics(
        role: SemanticRole.taskGraph,
        label: widget.semanticLabel,
        focused: _focusedWithin || _focusNode.hasFocus,
        actions: {
          SemanticAction.focus,
          SemanticAction.navigate,
          if (copyEnabled) SemanticAction.copy,
        },
        onAction: _handleGraphAction,
        state: SemanticState({
          'collectionRowCount': widget.nodes.length,
          'taskCount': widget.nodes.length,
          'pendingTaskCount': counts[TaskGraphStatus.pending] ?? 0,
          'runningTaskCount': counts[TaskGraphStatus.running] ?? 0,
          'succeededTaskCount': counts[TaskGraphStatus.succeeded] ?? 0,
          'failedTaskCount': counts[TaskGraphStatus.failed] ?? 0,
          'cancelledTaskCount': counts[TaskGraphStatus.cancelled] ?? 0,
          'skippedTaskCount': counts[TaskGraphStatus.skipped] ?? 0,
          'copyEnabled': copyEnabled,
          'clipboardPolicy': widget.copyOptions.clipboardPolicy.name,
          if (visibleRange != null) ...{
            'visibleRangeStart': visibleRange.first,
            'visibleRangeEnd': visibleRange.last,
          },
          'selectedIndex': ?selectedIndex,
          if (selectedNode != null) ...{
            'selectedTaskId': selectedNode.id,
            'selectedTaskStatus': selectedNode.status.name,
          },
        }),
        child: list,
      ),
    );
  }
}

class _TaskGraphRow extends StatelessWidget {
  const _TaskGraphRow({
    required this.node,
    required this.index,
    required this.selected,
    required this.activeSelection,
    required this.copyEnabled,
    required this.onActivate,
    required this.onCopy,
  });

  final TaskGraphNode node;
  final int index;
  final bool selected;
  final bool activeSelection;
  final bool copyEnabled;
  final VoidCallback onActivate;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final line = _renderLine(node);
    final style = _styleForStatus(node.status).merge(
      activeSelection
          ? Theme.of(context).selectionStyle
          : selected
          ? Theme.of(context).mutedStyle
          : CellStyle.empty,
    );
    return Semantics(
      role: SemanticRole.task,
      label: _sanitizeTaskText(node.title),
      value: node.status.name,
      selected: selected,
      busy: node.busy,
      validationError: node.status == TaskGraphStatus.failed
          ? node.description
          : null,
      actions: {
        SemanticAction.activate,
        if (selected && copyEnabled) SemanticAction.copy,
      },
      onAction: (action) async {
        switch (action) {
          case SemanticAction.activate:
            onActivate();
            return;
          case SemanticAction.copy:
            if (selected && copyEnabled) await onCopy();
            return;
          case _:
            return;
        }
      },
      state: SemanticState({
        'rowIndex': index,
        'viewIndex': index,
        'rowKey': node.id,
        'taskId': node.id,
        'taskLabel': node.title,
        'taskStatus': node.status.name,
        'dependencyCount': node.dependsOn.length,
        if (node.dependsOn.isNotEmpty) 'dependsOn': node.dependsOn.join(','),
        if (node.progressCurrent != null)
          'progressCurrent': node.progressCurrent,
        if (node.progressTotal != null) 'progressTotal': node.progressTotal,
        ...node.metadata,
      }),
      child: Text(line, style: style),
    );
  }
}

Map<TaskGraphStatus, int> _statusCounts(List<TaskGraphNode> nodes) {
  final counts = <TaskGraphStatus, int>{};
  for (final node in nodes) {
    counts[node.status] = (counts[node.status] ?? 0) + 1;
  }
  return counts;
}

String _renderLine(TaskGraphNode node) {
  final title = _sanitizeTaskText(node.title);
  final description = node.description == null
      ? ''
      : ' - ${_sanitizeTaskText(node.description!)}';
  final dependencies = node.dependsOn.isEmpty
      ? ''
      : ' (after ${node.dependsOn.map(_sanitizeTaskText).join(', ')})';
  final progress = node.progressCurrent == null && node.progressTotal == null
      ? ''
      : ' ${_progressText(node)}';
  return '${_statusMarker(node.status)} $title$description$dependencies$progress';
}

String _statusMarker(TaskGraphStatus status) {
  return switch (status) {
    TaskGraphStatus.pending => '[ ]',
    TaskGraphStatus.running => '[>]',
    TaskGraphStatus.succeeded => '[x]',
    TaskGraphStatus.failed => '[!]',
    TaskGraphStatus.cancelled => '[-]',
    TaskGraphStatus.skipped => '[~]',
  };
}

String _progressText(TaskGraphNode node) {
  final current = node.progressCurrent;
  final total = node.progressTotal;
  if (current != null && total != null) return 'Progress: $current / $total';
  // A known total with an unknown current reads as "— / total", not "pending".
  if (total != null) return 'Progress: — / $total';
  if (current != null) return 'Progress: $current';
  return 'Progress: pending';
}

String _sanitizeTaskText(String original) {
  if (!_needsTaskSanitization(original)) return original;
  return sanitizeSingleLine(original);
}

bool _needsTaskSanitization(String text) {
  for (final codeUnit in text.codeUnits) {
    if (codeUnit == 0x1b ||
        codeUnit == 0x9b ||
        codeUnit == 0x9d ||
        codeUnit == 0x90 ||
        codeUnit == 0x98 ||
        codeUnit == 0x9e ||
        codeUnit == 0x9f ||
        codeUnit == 0x0a ||
        codeUnit == 0x0d ||
        codeUnit == 0x09) {
      return true;
    }
  }
  return false;
}

CellStyle _styleForStatus(TaskGraphStatus status) {
  return switch (status) {
    TaskGraphStatus.pending => const CellStyle(dim: true),
    TaskGraphStatus.running => const CellStyle(foreground: AnsiColor(11)),
    TaskGraphStatus.succeeded => const CellStyle(foreground: AnsiColor(10)),
    TaskGraphStatus.failed => const CellStyle(foreground: AnsiColor(9)),
    TaskGraphStatus.cancelled => const CellStyle(foreground: AnsiColor(8)),
    TaskGraphStatus.skipped => const CellStyle(foreground: AnsiColor(8)),
  };
}
