import 'semantics.dart';

/// A text-first accessibility/fallback snapshot derived from semantic nodes.
///
/// This is not an OS screen-reader bridge. It is the shared, portable
/// structure Fleury can use for prompt fallback, tests, debug capture, and
/// future accessibility adapters without reinterpreting rendered cells.
final class AccessibilitySnapshot {
  const AccessibilitySnapshot({required this.root});

  final AccessibilityNode root;

  Iterable<AccessibilityNode> get nodes => root.selfAndDescendants;
  AccessibilitySnapshotSummary get summary =>
      AccessibilitySnapshotSummary._from(this);

  AccessibilityNode? get focusedNode {
    for (final node in nodes) {
      if (node.focused) return node;
    }
    return null;
  }

  Iterable<AccessibilityNode> get actionableNodes =>
      nodes.where((node) => node.actions.isNotEmpty);

  Iterable<AccessibilityNode> get validationErrorNodes => nodes.where(
    (node) => node.validationError != null && node.validationError!.isNotEmpty,
  );

  Iterable<AccessibilityNode> get redactedValueNodes =>
      nodes.where((node) => node.valueRedacted);

  AccessibilityNode? nodeBySourceId(SemanticNodeId sourceId) {
    for (final node in nodes) {
      if (node.sourceId == sourceId) return node;
    }
    return null;
  }

  Iterable<AccessibilityNode> byRole(SemanticRole role) {
    return nodes.where((node) => node.role == role);
  }

  Iterable<AccessibilityNode> where({
    SemanticRole? role,
    String? label,
    Object? value,
    SemanticAction? action,
    bool? focused,
    bool? selected,
    bool? enabled,
    bool? checked,
    bool? expanded,
    bool? busy,
    bool? valueRedacted,
    String? validationError,
    String? state,
  }) {
    return nodes.where((node) {
      if (role != null && node.role != role) return false;
      if (label != null && node.label != label) return false;
      if (value != null && node.value != value) return false;
      if (action != null && !node.actions.contains(action)) return false;
      if (focused != null && node.focused != focused) return false;
      if (selected != null && node.selected != selected) return false;
      if (enabled != null && node.enabled != enabled) return false;
      if (checked != null && node.checked != checked) return false;
      if (expanded != null && node.expanded != expanded) return false;
      if (busy != null && node.busy != busy) return false;
      if (valueRedacted != null && node.valueRedacted != valueRedacted) {
        return false;
      }
      if (validationError != null && node.validationError != validationError) {
        return false;
      }
      if (state != null && !node.states.contains(state)) return false;
      return true;
    });
  }

  AccessibilityNode single({
    SemanticRole? role,
    String? label,
    Object? value,
    SemanticAction? action,
    bool? focused,
    bool? selected,
    bool? enabled,
    bool? checked,
    bool? expanded,
    bool? busy,
    bool? valueRedacted,
    String? validationError,
    String? state,
  }) {
    final matches = where(
      role: role,
      label: label,
      value: value,
      action: action,
      focused: focused,
      selected: selected,
      enabled: enabled,
      checked: checked,
      expanded: expanded,
      busy: busy,
      valueRedacted: valueRedacted,
      validationError: validationError,
      state: state,
    ).toList(growable: false);
    if (matches.length == 1) return matches.single;
    throw StateError(
      'Expected exactly one accessibility node, found ${matches.length}.',
    );
  }

  String toPlainText() {
    final lines = <String>[];
    void visit(AccessibilityNode node, int depth) {
      lines.add('${List.filled(depth, '  ').join()}${node.announcement}');
      for (final child in node.children) {
        visit(child, depth + 1);
      }
    }

    visit(root, 0);
    return lines.join('\n');
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'summary': summary.toJson(),
    'root': root.toJson(),
  };
}

/// Aggregate facts for an accessibility/fallback snapshot.
///
/// This keeps prompt fallback, debug capture, tests, and future adapters from
/// hand-walking the tree for common questions such as "what is focused?",
/// "how many nodes expose actions?", or "did any safe validation errors leak
/// through?"
final class AccessibilitySnapshotSummary {
  AccessibilitySnapshotSummary._({
    required this.nodeCount,
    required Map<SemanticRole, int> roleCounts,
    required this.selectedCount,
    required this.disabledCount,
    required this.busyCount,
    required this.validationErrorCount,
    required this.redactedValueCount,
    required this.actionableNodeCount,
    required this.actionCount,
    this.focusedNodeId,
    this.focusedLabel,
  }) : roleCounts = Map<SemanticRole, int>.unmodifiable(roleCounts);

  factory AccessibilitySnapshotSummary._from(AccessibilitySnapshot snapshot) {
    final roleCounts = <SemanticRole, int>{};
    var nodeCount = 0;
    var selectedCount = 0;
    var disabledCount = 0;
    var busyCount = 0;
    var validationErrorCount = 0;
    var redactedValueCount = 0;
    var actionableNodeCount = 0;
    var actionCount = 0;
    SemanticNodeId? focusedNodeId;
    String? focusedLabel;

    for (final node in snapshot.nodes) {
      nodeCount += 1;
      roleCounts[node.role] = (roleCounts[node.role] ?? 0) + 1;
      if (node.focused && focusedNodeId == null) {
        focusedNodeId = node.sourceId;
        focusedLabel = node.label;
      }
      if (node.selected) selectedCount += 1;
      if (!node.enabled) disabledCount += 1;
      if (node.busy) busyCount += 1;
      if (node.validationError != null && node.validationError!.isNotEmpty) {
        validationErrorCount += 1;
      }
      if (node.valueRedacted) redactedValueCount += 1;
      if (node.actions.isNotEmpty) {
        actionableNodeCount += 1;
        actionCount += node.actions.length;
      }
    }

    return AccessibilitySnapshotSummary._(
      nodeCount: nodeCount,
      roleCounts: roleCounts,
      selectedCount: selectedCount,
      disabledCount: disabledCount,
      busyCount: busyCount,
      validationErrorCount: validationErrorCount,
      redactedValueCount: redactedValueCount,
      actionableNodeCount: actionableNodeCount,
      actionCount: actionCount,
      focusedNodeId: focusedNodeId,
      focusedLabel: focusedLabel,
    );
  }

  final int nodeCount;
  final Map<SemanticRole, int> roleCounts;
  final SemanticNodeId? focusedNodeId;
  final String? focusedLabel;
  final int selectedCount;
  final int disabledCount;
  final int busyCount;
  final int validationErrorCount;
  final int redactedValueCount;
  final int actionableNodeCount;
  final int actionCount;

  int roleCount(SemanticRole role) => roleCounts[role] ?? 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'nodeCount': nodeCount,
    'roleCounts': <String, Object?>{
      for (final entry in roleCounts.entries) entry.key.name: entry.value,
    },
    if (focusedNodeId != null) 'focusedNodeId': focusedNodeId!.value,
    if (focusedLabel != null) 'focusedLabel': focusedLabel,
    'selectedCount': selectedCount,
    'disabledCount': disabledCount,
    'busyCount': busyCount,
    'validationErrorCount': validationErrorCount,
    'redactedValueCount': redactedValueCount,
    'actionableNodeCount': actionableNodeCount,
    'actionCount': actionCount,
  };
}

/// One node in a text-first accessibility/fallback snapshot.
final class AccessibilityNode {
  const AccessibilityNode({
    required this.sourceId,
    required this.role,
    required this.roleLabel,
    this.label,
    this.value,
    this.hint,
    this.validationError,
    this.enabled = true,
    this.focused = false,
    this.selected = false,
    this.checked,
    this.expanded,
    this.busy = false,
    this.valueRedacted = false,
    this.states = const <String>[],
    this.actions = const <SemanticAction>[],
    this.children = const <AccessibilityNode>[],
  });

  final SemanticNodeId sourceId;
  final SemanticRole role;
  final String roleLabel;
  final String? label;
  final String? value;
  final String? hint;
  final String? validationError;
  final bool enabled;
  final bool focused;
  final bool selected;
  final bool? checked;
  final bool? expanded;
  final bool busy;
  final bool valueRedacted;
  final List<String> states;
  final List<SemanticAction> actions;
  final List<AccessibilityNode> children;

  Iterable<AccessibilityNode> get descendants sync* {
    for (final child in children) {
      yield child;
      yield* child.descendants;
    }
  }

  Iterable<AccessibilityNode> get selfAndDescendants sync* {
    yield this;
    yield* descendants;
  }

  String get announcement {
    final parts = <String>[
      roleLabel,
      if (label != null && label!.isNotEmpty) label!,
      if (value != null && value!.isNotEmpty && value != label) value!,
      if (hint != null && hint!.isNotEmpty) hint!,
      ...states,
      if (validationError != null && validationError!.isNotEmpty)
        'error: $validationError',
      if (actions.isNotEmpty)
        'actions: ${actions.map((action) => action.name).join(', ')}',
    ];
    return parts.join(' | ');
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'sourceId': sourceId.value,
    'role': role.name,
    'roleLabel': roleLabel,
    if (label != null) 'label': label,
    if (value != null) 'value': value,
    if (hint != null) 'hint': hint,
    if (validationError != null) 'validationError': validationError,
    'enabled': enabled,
    if (focused) 'focused': true,
    if (selected) 'selected': true,
    if (checked != null) 'checked': checked,
    if (expanded != null) 'expanded': expanded,
    if (busy) 'busy': true,
    if (valueRedacted) 'valueRedacted': true,
    if (states.isNotEmpty) 'states': states,
    if (actions.isNotEmpty)
      'actions': <String>[for (final action in actions) action.name],
    if (children.isNotEmpty)
      'children': <Object?>[for (final child in children) child.toJson()],
  };
}

/// Builds a text-first accessibility/fallback snapshot from [tree].
AccessibilitySnapshot buildAccessibilitySnapshot(SemanticTree tree) {
  return AccessibilitySnapshot(root: _buildNode(tree.root));
}

/// Convenience extension for accessibility/fallback snapshots.
extension SemanticTreeAccessibility on SemanticTree {
  AccessibilitySnapshot toAccessibilitySnapshot() {
    return buildAccessibilitySnapshot(this);
  }
}

AccessibilityNode _buildNode(SemanticNode node) {
  final value = _safeValue(node);
  return AccessibilityNode(
    sourceId: node.id,
    role: node.role,
    roleLabel: _roleLabel(node.role),
    label: node.label,
    value: value,
    hint: node.hint,
    validationError: _redactsValue(node) ? null : node.validationError,
    enabled: node.enabled,
    focused: node.focused,
    selected: node.selected,
    checked: node.checked,
    expanded: node.expanded,
    busy: node.busy,
    valueRedacted: _redactsValue(node),
    states: _statesFor(node),
    actions: node.actions.toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name)),
    children: <AccessibilityNode>[
      for (final child in node.children) _buildNode(child),
    ],
  );
}

String? _safeValue(SemanticNode node) {
  if (_redactsValue(node)) return null;
  final value = node.value;
  if (value == null) return null;
  return value.toString();
}

bool _redactsValue(SemanticNode node) {
  return node.state.redactedValue == true ||
      node.state.obscureText == true ||
      node.state.clipboardRedacted == true;
}

List<String> _statesFor(SemanticNode node) {
  final states = <String>[];
  if (!node.enabled) states.add('disabled');
  if (node.focused) states.add('focused');
  if (node.selected) states.add('selected');
  if (node.busy) states.add('busy');
  if (node.checked != null) {
    states.add(node.checked! ? 'checked' : 'unchecked');
  }
  if (node.expanded != null) {
    states.add(node.expanded! ? 'expanded' : 'collapsed');
  }
  if (_redactsValue(node)) states.add('value redacted');

  final state = node.state;
  final appKernel = _appKernelState(state);
  if (appKernel != null) states.add(appKernel);

  final workflow = _workflowState(state);
  if (workflow != null) states.add(workflow);

  final command = _commandState(state);
  if (command != null) states.add(command);

  final menu = _menuState(state);
  if (menu != null) states.add(menu);

  final model = _modelStatusState(state);
  if (model != null) states.add(model);

  final task = _taskState(state);
  if (task != null) states.add(task);

  final taskEvent = _taskEventState(state);
  if (taskEvent != null) states.add(taskEvent);

  final taskGraph = _taskGraphState(state);
  if (taskGraph != null) states.add(taskGraph);

  final toolCall = _toolCallState(state);
  if (toolCall != null) states.add(toolCall);

  final form = _formState(state);
  if (form != null) states.add(form);

  final field = _formFieldState(state);
  if (field != null) states.addAll(field);

  final progress = _progressState(state);
  if (progress != null) states.add(progress);

  final chart = _chartState(state);
  if (chart != null) states.add(chart);

  final canvas = _canvasState(state);
  if (canvas != null) states.add(canvas);

  final tokenMeter = _tokenMeterState(state);
  if (tokenMeter != null) states.add(tokenMeter);

  final numericControl = _numericControlState(state);
  if (numericControl != null) states.add(numericControl);

  final dateControl = _dateControlState(state);
  if (dateControl != null) states.add(dateControl);

  final collection = _collectionState(state);
  if (collection != null) states.add(collection);

  final search = _searchState(state);
  if (search != null) states.add(search);

  final log = _logState(state);
  if (log != null) states.add(log);

  final conversation = _conversationState(state);
  if (conversation != null) states.add(conversation);

  final contextState = _contextState(state);
  if (contextState != null) states.add(contextState);

  final trace = _traceState(state);
  if (trace != null) states.add(trace);

  final patch = _patchState(state);
  if (patch != null) states.add(patch);

  final fileMention = _fileMentionState(state);
  if (fileMention != null) states.add(fileMention);

  final selection = _selectionState(state);
  if (selection != null) states.add(selection);

  final view = _viewState(state, redacted: _redactsValue(node));
  if (view != null) states.add(view);

  final rowCell = _rowCellState(state, redacted: _redactsValue(node));
  if (rowCell != null) states.add(rowCell);

  final document = _documentState(state);
  if (document != null) states.add(document);

  final output = _outputState(state);
  if (output != null) states.add(output);

  final message = _messageState(state);
  if (message != null) states.add(message);

  final capability = _capabilityState(state);
  if (capability != null) states.add(capability);

  final diagnostic = _diagnosticState(state);
  if (diagnostic != null) states.add(diagnostic);

  final clipboard = _clipboardState(state);
  if (clipboard != null) states.add(clipboard);

  final status = _statusState(state);
  if (status != null) states.add(status);

  final notification = _notificationState(state);
  if (notification != null) states.add(notification);

  final tab = _tabState(state);
  if (tab != null) states.add(tab);

  final approval = _approvalState(state);
  if (approval != null) states.add(approval);

  if (state.pasteInProgress == true) {
    final inserted = state.pasteInsertedLength;
    final total = state.pasteTotalLength;
    if (inserted != null && total != null) {
      states.add('paste $inserted of $total');
    } else {
      states.add('paste in progress');
    }
  }

  return states;
}

String? _appKernelState(SemanticState state) {
  final parts = <String>[
    if (state.screenCount case final count?) '$count screens',
    if (state.activeScreenId case final active?) 'active screen $active',
    if (state.commandCount case final count?) '$count commands',
    if (state.lastCommandId case final id?)
      'last command $id${state.lastCommandStatus == null ? '' : ' ${state.lastCommandStatus}'}',
  ];
  if (parts.isEmpty) return null;
  return parts.join(', ');
}

String? _workflowState(SemanticState state) {
  final id = state.workflowId;
  final title = state.workflowTitle;
  final health = state.workflowHealth;
  if (id == null && title == null && health == null) return null;

  final parts = <String>[
    if (id != null) 'id $id',
    if (title != null) 'title $title',
    if (health != null) 'health $health',
    if (state.messageCount case final count?) _countLabel(count, 'message'),
    if (state.activeMessageCount case final count? when count > 0)
      _countLabel(count, 'active message'),
    if (state.failedMessageCount case final count? when count > 0)
      _countLabel(count, 'failed message'),
    if (state.toolCallCount case final count?) _countLabel(count, 'tool call'),
    if (state.activeToolCallCount case final count? when count > 0)
      _countLabel(count, 'active tool call'),
    if (state.failedToolCallCount case final count? when count > 0)
      _countLabel(count, 'failed tool call'),
    if (state.approvalCount case final count? when count > 0)
      _countLabel(count, 'approval'),
    if (state.taskCount case final count?) _countLabel(count, 'task'),
    if (state.activeTaskCount case final count? when count > 0)
      _countLabel(count, 'active task'),
    if (state.failedTaskCount case final count? when count > 0)
      _countLabel(count, 'failed task'),
    if (state.modelStatus case final status?) 'model $status',
    if (state.modelBusy == true) 'model busy',
    if (state.contextItemCount case final count?)
      _countLabel(count, 'context item'),
    if (state.contextTokenCount case final count?) '$count context tokens',
    if (state.fileMentionCount case final count?)
      _countLabel(count, 'file mention'),
    if (state.conversationCount case final count?)
      _countLabel(count, 'conversation'),
    if (state.unreadConversationCount case final count? when count > 0)
      _countLabel(count, 'unread conversation'),
    if (state.traceEventCount case final count?)
      _countLabel(count, 'trace event'),
    if (state.activeTraceEventCount case final count? when count > 0)
      _countLabel(count, 'active trace event'),
    if (state.failedTraceEventCount case final count? when count > 0)
      _countLabel(count, 'failed trace event'),
    if (state.warningTraceEventCount case final count? when count > 0)
      _countLabel(count, 'trace warning'),
    if (state.patchFileCount case final count?)
      _countLabel(count, 'patch file'),
    if (state.reviewIssueCount case final count? when count > 0)
      _countLabel(count, 'review issue'),
    if (state.logEntryCount case final count? when count > 0)
      _countLabel(count, 'log entry', 'log entries'),
    if (state.warningLogEntryCount case final count? when count > 0)
      _countLabel(count, 'log warning'),
    if (state.errorLogEntryCount case final count? when count > 0)
      _countLabel(count, 'log error'),
  ];
  return 'workflow ${parts.join(', ')}';
}

String? _commandState(SemanticState state) {
  final parts = <String>[
    ?state.commandId,
    ?state.commandCategory,
    ?state.shortcut,
  ];
  if (parts.isEmpty) return null;
  return 'command ${parts.join(', ')}';
}

String? _menuState(SemanticState state) {
  final count = state.menuItemCount;
  final position = state.menuItemPosition;
  final childCount = state['childMenuItemCount'];
  if (count == null && position == null && childCount == null) return null;
  final parts = <String>[
    if (position != null && count != null) 'item $position of $count',
    if (position == null && count != null) '$count items',
    if (childCount is int) '$childCount child items',
  ];
  return 'menu ${parts.join(', ')}';
}

String? _modelStatusState(SemanticState state) {
  final name = state.modelName;
  final provider = state.modelProvider;
  final status = state.modelStatus;
  final mode = state.modelMode;
  final latency = state.modelLatencyMs;
  final queueDepth = state.modelQueueDepth;
  if (name == null &&
      provider == null &&
      status == null &&
      mode == null &&
      latency == null &&
      queueDepth == null) {
    return null;
  }
  final parts = <String>[
    if (name != null) 'model $name',
    if (provider != null) 'provider $provider',
    if (status != null) 'status $status',
    if (mode != null) 'mode $mode',
    if (latency != null) '${latency}ms latency',
    if (queueDepth != null) 'queue $queueDepth',
  ];
  return 'model status ${parts.join(', ')}';
}

String? _taskState(SemanticState state) {
  final parts = <String>[
    ?state.taskId,
    ?state.taskStatus,
    if (state.taskEventCount case final count?) '$count events',
    if (state.lastTaskEventKind case final kind?) 'last $kind',
    if (state.outputCount case final count?) '$count outputs',
    if (state['dependencyCount'] case final int count) '$count dependencies',
    if (state['command'] case final String command) 'command $command',
    if (state['exitCode'] case final int exitCode) 'exit $exitCode',
    if (state['processSucceeded'] case final bool succeeded)
      succeeded ? 'process succeeded' : 'process failed',
    if (state['canCancel'] == true) 'can cancel',
  ];
  if (parts.isEmpty) return null;
  if (state.source case final source?) parts.add('source $source');
  return 'task ${parts.join(', ')}';
}

String? _taskEventState(SemanticState state) {
  final kind = state.taskEventKind;
  final runId = state.taskRunId;
  final sequence = state.taskEventSequence;
  final status = state.taskStatus;
  final outputSequence = state.taskOutputSequence;
  final outputSource = state.taskOutputSource;
  final outputSeverity = state.taskOutputSeverity;
  final outputSanitized = state.taskOutputSanitized;
  final outputTruncated = state.taskOutputTruncated;
  final outputOriginalLength = state.taskOutputOriginalLength;
  if (kind == null &&
      runId == null &&
      sequence == null &&
      outputSequence == null &&
      outputSource == null &&
      outputSeverity == null &&
      outputSanitized == null &&
      outputTruncated == null &&
      outputOriginalLength == null) {
    return null;
  }
  final progressParts = <String>[
    if (state.progressCurrent case final current?) '$current',
    if (state.progressTotal case final total?) 'of $total',
  ];
  final parts = <String>[
    ?kind,
    if (runId != null) 'run $runId',
    if (sequence != null) 'sequence $sequence',
    if (status != null) 'status $status',
    if (progressParts.isNotEmpty) 'progress ${progressParts.join(' ')}',
    if (state.progressLabel case final label?) 'label $label',
    if (outputSequence != null) 'output sequence $outputSequence',
    if (outputSource != null) 'output source $outputSource',
    if (outputSeverity != null) 'severity $outputSeverity',
    if (outputSanitized == true) 'output sanitized',
    if (outputTruncated == true) 'output truncated',
    if (outputOriginalLength != null)
      'original output $outputOriginalLength chars',
  ];
  return 'task event ${parts.join(', ')}';
}

String? _taskGraphState(SemanticState state) {
  final taskCount = state['taskCount'];
  final running = state['runningTaskCount'];
  final succeeded = state['succeededTaskCount'];
  final failed = state['failedTaskCount'];
  final pending = state['pendingTaskCount'];
  final selected = state['selectedTaskId'];
  if (taskCount == null &&
      running == null &&
      succeeded == null &&
      failed == null &&
      pending == null &&
      selected == null) {
    return null;
  }
  final parts = <String>[
    if (taskCount is int) '$taskCount tasks',
    if (running is int && running > 0) '$running running',
    if (succeeded is int && succeeded > 0) '$succeeded succeeded',
    if (failed is int && failed > 0) '$failed failed',
    if (pending is int && pending > 0) '$pending pending',
    if (selected != null) 'selected $selected',
  ];
  return 'task graph ${parts.join(', ')}';
}

String? _toolCallState(SemanticState state) {
  final id = state['toolCallId'];
  final name = state['toolName'];
  final status = state['toolStatus'];
  final argumentCount = state['argumentCount'];
  final canCancel = state['canCancel'];
  if (id == null &&
      name == null &&
      status == null &&
      argumentCount == null &&
      canCancel == null) {
    return null;
  }
  final parts = <String>[
    if (id != null) 'id $id',
    if (name != null) 'tool $name',
    if (status != null) 'status $status',
    if (argumentCount is int) '$argumentCount arguments',
    if (canCancel == true) 'can cancel',
  ];
  return 'tool call ${parts.join(', ')}';
}

String? _formState(SemanticState state) {
  final fieldCount = state['fieldCount'];
  final visibleFieldCount = state['visibleFieldCount'];
  final errorCount = state['errorCount'];
  final layout = state['layout'];
  final activeFieldId = state['activeFieldId'];
  final stepCount = state['stepCount'];
  final currentStepPosition = state['currentStepPosition'];
  final currentStepId = state['currentStepId'];
  final currentStepTitle = state['currentStepTitle'];
  final canGoBack = state['canGoBack'];
  final canGoForward = state['canGoForward'];
  final completed = state['completed'];
  final cancelled = state['cancelled'];
  final validating = state['validating'];
  final hasAsyncValidators = state['hasAsyncValidators'];
  final parts = <String>[
    if (fieldCount is int) '$fieldCount fields',
    if (visibleFieldCount is int) '$visibleFieldCount visible fields',
    if (errorCount is int && errorCount > 0) '$errorCount errors',
    if (layout is String) 'layout $layout',
    if (activeFieldId is String) 'active field $activeFieldId',
    if (currentStepPosition is int && stepCount is int)
      'step $currentStepPosition of $stepCount',
    if (currentStepTitle is String) 'current step $currentStepTitle',
    if (currentStepId is String) 'current step id $currentStepId',
    if (canGoBack == true) 'can go back',
    if (canGoForward == true) 'can go forward',
    if (validating == true) 'validating',
    if (hasAsyncValidators == true) 'async validation',
    if (completed == true) 'completed',
    if (cancelled == true) 'cancelled',
  ];
  if (parts.isEmpty) return null;
  return parts.join(', ');
}

List<String>? _formFieldState(SemanticState state) {
  final states = <String>[];
  final fieldType = state['fieldType'];
  final promptPosition = state['promptPosition'];
  final promptCount = state['promptCount'];
  final optionCount = state['optionCount'];
  final pathKind = state['pathKind'];
  final mustExist = state['mustExist'];
  final allowRelative = state['allowRelative'];
  final hasAsyncValidator = state['hasAsyncValidator'];
  final validating = state['validating'];
  final selectedOptionCount = state['selectedOptionCount'];
  final minSelected = state['minSelected'];
  final maxSelected = state['maxSelected'];

  if (state['required'] == true) states.add('required');
  if (state['redacted'] == true) states.add('secret');
  if (fieldType is String) states.add('field type $fieldType');
  if (state['activePrompt'] == true) states.add('active prompt');
  if (hasAsyncValidator == true) states.add('async validation');
  if (validating == true) states.add('validating');
  if (promptPosition is int && promptCount is int) {
    states.add('prompt $promptPosition of $promptCount');
  }
  if (optionCount is int) states.add('$optionCount options');
  if (pathKind is String) states.add('path kind $pathKind');
  if (mustExist == true) states.add('must exist');
  if (allowRelative == false) states.add('absolute path required');
  if (selectedOptionCount is int) states.add('$selectedOptionCount selected');
  if (minSelected is int) states.add('minimum $minSelected selected');
  if (maxSelected is int) states.add('maximum $maxSelected selected');

  return states.isEmpty ? null : states;
}

String? _progressState(SemanticState state) {
  final current = state.progressCurrent;
  final total = state.progressTotal;
  final label = state.progressLabel;
  if (current == null && total == null && label == null) return null;
  final parts = <String>[
    ?label,
    if (current != null && total != null) '$current of $total',
    if (current != null && total == null) '$current',
  ];
  return 'progress ${parts.join(' ')}'.trim();
}

String? _chartState(SemanticState state) {
  final type = state.chartType;
  final rows = state.chartRowCount;
  final columns = state.chartColumnCount;
  final series = state.chartSeriesCount;
  final points = state.chartPointCount;
  final recorded = state.chartRecordedPointCount;
  final bars = state.chartBarCount;
  final segments = state.chartSegmentCount;
  final min = state.chartMinValue;
  final max = state.chartMaxValue;
  final latest = state.chartLatestValue;
  final xMin = state.chartXMin;
  final xMax = state.chartXMax;
  final yMin = state.chartYMin;
  final yMax = state.chartYMax;
  final references = state.chartReferenceCount;
  final interactive = state.chartInteractive;
  final cursorIndex = state.chartCursorIndex;
  final cursorCount = state.chartCursorCount;
  final cursorX = state.chartCursorX;
  final startDate = state.chartStartDate;
  final endDate = state.chartEndDate;
  final weekStart = state.chartWeekStart;
  if (type == null &&
      rows == null &&
      columns == null &&
      series == null &&
      points == null &&
      recorded == null &&
      bars == null &&
      segments == null &&
      min == null &&
      max == null &&
      latest == null &&
      xMin == null &&
      xMax == null &&
      yMin == null &&
      yMax == null &&
      references == null &&
      interactive == null &&
      cursorIndex == null &&
      cursorCount == null &&
      cursorX == null &&
      startDate == null &&
      endDate == null &&
      weekStart == null) {
    return null;
  }
  final parts = <String>[
    ?type,
    if (rows != null) _countLabel(rows, 'row'),
    if (columns != null) _countLabel(columns, 'column'),
    if (series != null) _countLabel(series, 'series', 'series'),
    if (points != null) _countLabel(points, 'point'),
    if (recorded != null) '$recorded recorded',
    if (bars != null) _countLabel(bars, 'bar'),
    if (segments != null) _countLabel(segments, 'segment'),
    if (min != null) 'min $min',
    if (max != null) 'max $max',
    if (latest != null) 'latest $latest',
    if (xMin != null && xMax != null) 'x $xMin-$xMax',
    if (yMin != null && yMax != null) 'y $yMin-$yMax',
    if (references != null) _countLabel(references, 'reference'),
    if (interactive == true) 'interactive',
    if (cursorIndex != null && cursorCount != null)
      'cursor ${cursorIndex + 1} of $cursorCount',
    if (cursorX != null) 'cursor x $cursorX',
    if (startDate != null && endDate != null) '$startDate to $endDate',
    if (weekStart != null) 'week starts $weekStart',
  ];
  return 'chart ${parts.join(', ')}';
}

String? _canvasState(SemanticState state) {
  final marker = state.canvasMarker;
  final minX = state.canvasMinX;
  final maxX = state.canvasMaxX;
  final minY = state.canvasMinY;
  final maxY = state.canvasMaxY;
  if (marker == null &&
      minX == null &&
      maxX == null &&
      minY == null &&
      maxY == null) {
    return null;
  }
  final parts = <String>[
    if (marker != null) 'marker $marker',
    if (minX != null && maxX != null) 'x $minX-$maxX',
    if (minY != null && maxY != null) 'y $minY-$maxY',
  ];
  return 'canvas ${parts.join(', ')}';
}

String? _tokenMeterState(SemanticState state) {
  final used = state.contextUsed;
  final limit = state.contextLimit;
  final remaining = state.contextRemaining;
  final ratio = state.contextRatioPercent;
  final total = state.tokenTotal;
  final input = state.tokenInput;
  final output = state.tokenOutput;
  final cached = state.tokenCached;
  if (used == null &&
      limit == null &&
      remaining == null &&
      ratio == null &&
      total == null &&
      input == null &&
      output == null &&
      cached == null) {
    return null;
  }
  final parts = <String>[
    if (used != null && limit != null) '$used of $limit context',
    if (used != null && limit == null) '$used context',
    if (remaining != null) '$remaining remaining',
    if (ratio != null) '$ratio%',
    if (total != null) '$total tokens',
    if (input != null) '$input input',
    if (output != null) '$output output',
    if (cached != null) '$cached cached',
    if (state['contextNearLimit'] == true) 'near limit',
    if (state['contextOverLimit'] == true) 'over limit',
  ];
  return 'token meter ${parts.join(', ')}';
}

String? _numericControlState(SemanticState state) {
  final value = state['numericValue'];
  final low = state['lowValue'];
  final high = state['highValue'];
  final min = state['min'];
  final max = state['max'];
  final step = state['step'];
  final largeStep = state['largeStep'];
  final activeHandle = state['activeHandle'];
  final canIncrement = state['canIncrement'];
  final canDecrement = state['canDecrement'];
  if (value == null &&
      low == null &&
      high == null &&
      min == null &&
      max == null &&
      step == null &&
      largeStep == null &&
      activeHandle == null &&
      canIncrement == null &&
      canDecrement == null) {
    return null;
  }
  final parts = <String>[
    if (value != null) 'value $value',
    if (low != null && high != null) 'range $low-$high',
    if (min != null) 'min $min',
    if (max != null) 'max $max',
    if (step != null) 'step $step',
    if (largeStep != null) 'large step $largeStep',
    if (activeHandle != null) 'active handle $activeHandle',
    if (canIncrement == false) 'cannot increment',
    if (canDecrement == false) 'cannot decrement',
  ];
  return parts.join(', ');
}

String? _dateControlState(SemanticState state) {
  final selectedDate = state['selectedDate'];
  final visibleMonth = state['visibleMonth'];
  final visibleYear = state['visibleYear'];
  final weekStartsOn = state['weekStartsOn'];
  final firstDate = state['firstDate'];
  final lastDate = state['lastDate'];
  final canIncrement = state['canIncrement'];
  final canDecrement = state['canDecrement'];
  if (selectedDate == null &&
      visibleMonth == null &&
      visibleYear == null &&
      weekStartsOn == null &&
      firstDate == null &&
      lastDate == null &&
      canIncrement == null &&
      canDecrement == null) {
    return null;
  }
  final parts = <String>[
    if (selectedDate != null) 'selected date $selectedDate',
    if (visibleMonth != null) 'visible month $visibleMonth',
    if (visibleYear != null) 'visible year $visibleYear',
    if (weekStartsOn != null) 'week starts $weekStartsOn',
    if (firstDate != null) 'first date $firstDate',
    if (lastDate != null) 'last date $lastDate',
    if (canIncrement == false) 'cannot increment',
    if (canDecrement == false) 'cannot decrement',
  ];
  return parts.join(', ');
}

String? _collectionState(SemanticState state) {
  final rows = state.collectionRowCount;
  final columns = state.collectionColumnCount;
  final start = state.visibleRangeStart;
  final end = state.visibleRangeEnd;
  if (rows == null && columns == null && start == null && end == null) {
    return null;
  }
  final parts = <String>[
    if (rows != null) '$rows rows',
    if (columns != null) '$columns columns',
    if (start != null && end != null) 'visible $start-$end',
  ];
  return parts.join(', ');
}

String? _searchState(SemanticState state) {
  final total = state['totalResultCount'];
  final filtered = state['filteredResultCount'];
  final selectedIndex = state['selectedIndex'];
  final selectedCategory = state['selectedCategory'];
  final selectedSource = state['selectedSource'];
  final resultCategory = state['resultCategory'];
  final resultSource = state['resultSource'];
  final hasSearchMarker =
      total != null ||
      filtered != null ||
      selectedCategory != null ||
      resultCategory != null ||
      resultSource != null;
  if (!hasSearchMarker) return null;
  if (total == null &&
      filtered == null &&
      selectedIndex == null &&
      selectedCategory == null &&
      selectedSource == null &&
      resultCategory == null &&
      resultSource == null) {
    return null;
  }
  final parts = <String>[
    if (total is int) '$total results',
    if (filtered is int) '$filtered filtered',
    if (selectedIndex is int) 'selected index $selectedIndex',
    if (selectedCategory is String) 'selected category $selectedCategory',
    if (selectedSource is String) 'selected source $selectedSource',
    if (resultCategory is String) 'category $resultCategory',
    if (resultSource is String) 'source $resultSource',
  ];
  return 'search ${parts.join(', ')}';
}

String? _logState(SemanticState state) {
  final total = state['totalEntryCount'];
  final filtered = state['filteredEntryCount'];
  final filterActive = state['filterActive'];
  final filterSources = state['filterSources'];
  final filterSeverities = state['filterSeverities'];
  final filterCaseSensitive = state['filterCaseSensitive'];
  final followTail = state['followTail'];
  final copyIncludesPrefix = state['copyIncludesPrefix'];
  final selectedIndex = state['selectedIndex'];
  final lastKey = state['lastKey'];
  if (total == null &&
      filtered == null &&
      filterActive == null &&
      filterSources == null &&
      filterSeverities == null &&
      filterCaseSensitive == null &&
      followTail == null &&
      copyIncludesPrefix == null &&
      selectedIndex == null &&
      lastKey == null) {
    return null;
  }
  final parts = <String>[
    if (total is int) '$total entries',
    if (filtered is int) '$filtered filtered',
    if (filterActive == true) 'filter active',
    if (filterSources is String) 'sources $filterSources',
    if (filterSeverities is String) 'severities $filterSeverities',
    if (filterCaseSensitive == true) 'case sensitive',
    if (followTail == true) 'follow tail',
    if (copyIncludesPrefix == true) 'copy includes prefix',
    if (selectedIndex is int) 'selected index $selectedIndex',
    if (lastKey != null) 'last $lastKey',
  ];
  return 'log ${parts.join(', ')}';
}

String? _fileMentionState(SemanticState state) {
  final path = state.filePath;
  final selectedPath = state.selectedFilePath;
  final kind = state.fileKind;
  final language = state.fileLanguage;
  final mention = state.mentionText;
  final line = state['line'];
  final column = state['column'];
  if (path == null &&
      selectedPath == null &&
      kind == null &&
      language == null &&
      mention == null &&
      line == null &&
      column == null) {
    return null;
  }
  final parts = <String>[
    if (path != null) 'path $path',
    if (selectedPath != null) 'selected $selectedPath',
    if (kind != null) 'kind $kind',
    if (language != null) 'language $language',
    if (mention != null) 'mention $mention',
    if (line is int) 'line $line',
    if (column is int) 'column $column',
  ];
  return 'file mention ${parts.join(', ')}';
}

String? _conversationState(SemanticState state) {
  final id = state.conversationId;
  final selectedId = state.selectedConversationId;
  final status = state.conversationStatus;
  final unread = state.conversationUnreadCount;
  final messages = state.conversationMessageCount;
  final pinned = state['pinned'];
  if (id == null &&
      selectedId == null &&
      status == null &&
      unread == null &&
      messages == null &&
      pinned == null) {
    return null;
  }
  final parts = <String>[
    if (id != null) 'id $id',
    if (selectedId != null) 'selected $selectedId',
    if (status != null) 'status $status',
    if (unread != null) '$unread unread',
    if (messages != null) '$messages messages',
    if (pinned == true) 'pinned',
  ];
  return 'conversation ${parts.join(', ')}';
}

String? _contextState(SemanticState state) {
  final id = state.contextItemId;
  final selectedId = state.selectedContextItemId;
  final kind = state.contextItemKind;
  final tokens = state.contextItemTokenCount;
  final priority = state.contextItemPriority;
  final itemCount = state['contextItemCount'];
  final totalTokens = state['contextTokenCount'];
  final pinned = state['pinned'];
  final source = state.source;
  final hasContextMarker =
      id != null ||
      selectedId != null ||
      kind != null ||
      tokens != null ||
      priority != null ||
      itemCount != null ||
      totalTokens != null ||
      pinned != null;
  if (!hasContextMarker) {
    return null;
  }
  final parts = <String>[
    if (itemCount is int) '$itemCount items',
    if (totalTokens is int) '$totalTokens tokens',
    if (id != null) 'id $id',
    if (selectedId != null) 'selected $selectedId',
    if (kind != null) 'kind $kind',
    if (tokens != null) '$tokens tokens',
    if (priority != null) 'priority $priority',
    if (pinned == true) 'pinned',
    if (source != null) 'source $source',
  ];
  return 'context ${parts.join(', ')}';
}

String? _traceState(SemanticState state) {
  final id = state.traceId;
  final selectedId = state.selectedTraceId;
  final kind = state.traceKind;
  final status = state.traceStatus;
  final duration = state.traceDurationMs;
  final count = state['traceEventCount'];
  final running = state['runningTraceEventCount'];
  final failed = state['failedTraceEventCount'];
  final warning = state['warningTraceEventCount'];
  final source = state.source;
  final hasTraceMarker =
      id != null ||
      selectedId != null ||
      kind != null ||
      status != null ||
      duration != null ||
      count != null ||
      running != null ||
      failed != null ||
      warning != null;
  if (!hasTraceMarker) {
    return null;
  }
  final parts = <String>[
    if (count is int) '$count events',
    if (running is int && running > 0) '$running running',
    if (failed is int && failed > 0) '$failed failed',
    if (warning is int && warning > 0) '$warning warnings',
    if (id != null) 'id $id',
    if (selectedId != null) 'selected $selectedId',
    if (kind != null) 'kind $kind',
    if (status != null) 'status $status',
    if (duration != null) '${duration}ms',
    if (source != null) 'source $source',
  ];
  return 'trace ${parts.join(', ')}';
}

String? _patchState(SemanticState state) {
  final id = state.patchId;
  final status = state.patchStatus;
  final count = state['patchFileCount'];
  final additions = state['patchAdditionCount'];
  final deletions = state['patchDeletionCount'];
  final hunks = state['patchHunkCount'];
  final selected = state.selectedPatchFilePath;
  final file = state.patchFilePath;
  final fileStatus = state.patchFileStatus;
  final approved = state['approvedPatchFileCount'];
  final changesRequested = state['changesRequestedPatchFileCount'];
  if (id == null &&
      status == null &&
      count == null &&
      additions == null &&
      deletions == null &&
      hunks == null &&
      selected == null &&
      file == null &&
      fileStatus == null &&
      approved == null &&
      changesRequested == null) {
    return null;
  }
  final parts = <String>[
    if (id != null) 'id $id',
    if (status != null) 'status $status',
    if (count is int) '$count files',
    if (additions is int) '$additions additions',
    if (deletions is int) '$deletions deletions',
    if (hunks is int) '$hunks hunks',
    if (approved is int && approved > 0) '$approved approved',
    if (changesRequested is int && changesRequested > 0)
      '$changesRequested changes requested',
    if (selected != null) 'selected file $selected',
    if (file != null) 'file $file',
    if (fileStatus != null) 'file status $fileStatus',
  ];
  return 'patch ${parts.join(', ')}';
}

String? _selectionState(SemanticState state) {
  final base = state.selectionBase;
  final extent = state.selectionExtent;
  final rows = state.selectionRowCount;
  final columns = state.selectionColumnCount;
  if (base != null && extent != null && base != extent) {
    return 'selection $base-$extent';
  }
  if (rows != null || columns != null) {
    final parts = <String>[
      if (rows != null) '$rows rows selected',
      if (columns != null) '$columns columns selected',
    ];
    return parts.join(', ');
  }
  return null;
}

String? _viewState(SemanticState state, {required bool redacted}) {
  final parts = <String>[
    if (!redacted && state.selectedKey != null) 'selected ${state.selectedKey}',
    if (state.filterText case final filter?) 'filter "$filter"',
    if (state.sortColumn case final sort?)
      'sort $sort${state.sortDirection == null ? '' : ' ${state.sortDirection}'}',
    if (state.source case final source?) 'source $source',
  ];
  if (parts.isEmpty) return null;
  return parts.join(', ');
}

String? _rowCellState(SemanticState state, {required bool redacted}) {
  final parts = <String>[
    if (state['rowIndex'] case final int rowIndex) 'row $rowIndex',
    if (state['viewIndex'] case final int viewIndex) 'view row $viewIndex',
    if (state['columnIndex'] case final int columnIndex) 'column $columnIndex',
    if (!redacted && state['rowKey'] != null) 'row key ${state['rowKey']}',
    if (state['columnId'] case final String columnId) 'column $columnId',
    if (state['depth'] case final int depth) 'depth $depth',
    if (state['treeDepth'] case final int depth) 'tree depth $depth',
    if (state['isBranch'] == true) 'branch',
    if (state['header'] == true) 'header',
  ];
  if (parts.isEmpty) return null;
  return parts.join(', ');
}

String? _documentState(SemanticState state) {
  final parts = <String>[
    ..._jsonState(state),
    ..._diffState(state),
    ..._codeState(state),
    ..._markdownState(state),
    if (state['expandedCount'] case final int count) '$count expanded',
  ];
  if (parts.isEmpty) return null;
  return parts.join(', ');
}

List<String> _jsonState(SemanticState state) {
  return <String>[
    if (state['rootType'] case final String type) 'json root $type',
    if (state['selectedPath'] case final String path) 'selected path $path',
    if (state['jsonPath'] case final String path) 'json path $path',
  ];
}

List<String> _diffState(SemanticState state) {
  return <String>[
    if (state['fileCount'] case final int count) '$count files',
    if (state['hunkCount'] case final int count) '$count hunks',
    if (state['additionCount'] case final int count) '$count additions',
    if (state['deletionCount'] case final int count) '$count deletions',
    if (state['selectedDiffKind'] case final String kind) 'selected $kind',
    if (state['selectedFilePath'] case final String path) 'selected file $path',
    if (state['selectedOldLine'] case final int line) 'old line $line',
    if (state['selectedNewLine'] case final int line) 'new line $line',
    if (state['oldLine'] case final int line) 'old line $line',
    if (state['newLine'] case final int line) 'new line $line',
  ];
}

List<String> _codeState(SemanticState state) {
  return <String>[
    if (state['language'] case final String language) 'language $language',
    if (state['filePath'] case final String path) 'file $path',
    if (state['lineCount'] case final int count) '$count lines',
    if (state['nonEmptyLineCount'] case final int count) '$count non-empty',
    if (state['commentCount'] case final int count) '$count comments',
    if (state['blankCount'] case final int count) '$count blanks',
    if (state['selectedCodeLineKind'] case final String kind) 'selected $kind',
    if (state['lineNumber'] case final int line) 'line $line',
  ];
}

List<String> _markdownState(SemanticState state) {
  return <String>[
    if (state['blockCount'] case final int count) '$count blocks',
    if (state['headingCount'] case final int count) '$count headings',
    if (state['listItemCount'] case final int count) '$count list items',
    if (state['linkCount'] case final int count) '$count links',
    if (state['codeBlockCount'] case final int count) '$count code blocks',
    if (state['codeLineCount'] case final int count) '$count code lines',
    if (state['selectedMarkdownBlockKind'] case final String kind)
      'selected $kind',
    if (state['markdownBlockKind'] case final String kind) 'block $kind',
    if (state['markdownBlockIndex'] case final int index) 'block index $index',
  ];
}

String? _outputState(SemanticState state) {
  final parts = <String>[
    if (state.outputSanitized == true) 'sanitized',
    if (state.outputTruncated == true) 'truncated',
    if (state.outputOriginalLength case final length?) 'original $length chars',
  ];
  if (parts.isEmpty) return null;
  return 'output ${parts.join(', ')}';
}

String? _messageState(SemanticState state) {
  final role = state['messageRole'];
  final status = state['messageStatus'];
  final author = state['author'];
  final id = state['messageId'];
  if (role == null && status == null && author == null && id == null) {
    return null;
  }
  final parts = <String>[
    if (role != null) 'role $role',
    if (status != null) 'status $status',
    if (author != null) 'author $author',
    if (id != null) 'id $id',
  ];
  return 'message ${parts.join(', ')}';
}

String? _capabilityState(SemanticState state) {
  final feature = state.terminalCapability ?? state.capabilityRequirement;
  final resolution = state.capabilityResolution;
  final fallback = state.activeFallback;
  if (feature == null && resolution == null && fallback == null) return null;
  final parts = <String>[
    ?feature,
    ?resolution,
    if (fallback != null) 'fallback $fallback',
  ];
  return 'capability ${parts.join(' ')}';
}

String? _diagnosticState(SemanticState state) {
  final columns = state['terminalColumns'];
  final rows = state['terminalRows'];
  final colorMode = state['terminalColorMode'];
  final imageProtocol = state['imageProtocol'];
  final fallbackCount = state['fallbackCount'];
  final warningCount = state['warningCount'];
  final unsupportedFeatureCount = state['unsupportedFeatureCount'];
  final capabilityRowCount = state['capabilityRowCount'];
  final debugCaptureCount = state['debugCaptureCount'];
  final streaming = state['streaming'];
  final osc52Policy = state['osc52Policy'];
  final osc8Policy = state['osc8Policy'];
  if (columns == null &&
      rows == null &&
      colorMode == null &&
      imageProtocol == null &&
      fallbackCount == null &&
      warningCount == null &&
      unsupportedFeatureCount == null &&
      capabilityRowCount == null &&
      debugCaptureCount == null &&
      streaming == null &&
      osc52Policy == null &&
      osc8Policy == null) {
    return null;
  }
  final parts = <String>[
    if (columns is int && rows is int) '${columns}x$rows',
    if (colorMode is String) 'color $colorMode',
    if (imageProtocol is String) 'images $imageProtocol',
    if (capabilityRowCount is int) '$capabilityRowCount capability rows',
    if (fallbackCount is int) '$fallbackCount fallbacks',
    if (warningCount is int) '$warningCount warnings',
    if (unsupportedFeatureCount is int) '$unsupportedFeatureCount unsupported',
    if (debugCaptureCount is int) 'debug captures $debugCaptureCount',
    if (streaming is bool) streaming ? 'streaming' : 'not streaming',
    if (osc52Policy is String) 'OSC 52 $osc52Policy',
    if (osc8Policy is String) 'OSC 8 $osc8Policy',
  ];
  return 'diagnostic ${parts.join(', ')}';
}

String? _clipboardState(SemanticState state) {
  final policy = state.clipboardPolicy;
  final resolution = state.clipboardCapabilityResolution;
  final fallback = state.clipboardFallback;
  if (policy == null && resolution == null && fallback == null) return null;
  final parts = <String>[
    ?policy,
    ?resolution,
    if (fallback != null) 'fallback $fallback',
  ];
  return 'clipboard ${parts.join(' ')}';
}

String? _statusState(SemanticState state) {
  final count = state['statusCount'];
  final id = state['statusId'];
  final severity = state.severity;
  if (count == null && id == null && severity == null) return null;
  if (count == null && id == null) return 'severity $severity';
  final parts = <String>[
    if (count is int) '$count items',
    if (id is String) 'id $id',
    if (severity != null) 'severity $severity',
  ];
  return 'status ${parts.join(', ')}';
}

String? _notificationState(SemanticState state) {
  final index = state['notificationIndex'];
  final count = state['notificationCount'];
  final actionLabel = state['notificationActionLabel'];
  final actionKey = state['notificationActionKey'];
  final autoDismissMs = state['autoDismissMs'];
  if (index == null &&
      count == null &&
      actionLabel == null &&
      actionKey == null &&
      autoDismissMs == null) {
    return null;
  }
  final parts = <String>[
    if (index is int && count is int) '$index of $count',
    if (actionLabel != null) 'action $actionLabel',
    if (actionKey != null) 'key $actionKey',
    if (autoDismissMs is int) 'auto dismiss ${autoDismissMs}ms',
  ];
  return 'notification ${parts.join(', ')}';
}

String? _tabState(SemanticState state) {
  final position = state.tabPosition;
  final count = state.tabCount;
  final shortcut = state.shortcut;
  if (position == null && count == null && shortcut == null) return null;
  final parts = <String>[
    if (position != null && count != null) '$position of $count',
    if (shortcut != null) 'shortcut $shortcut',
  ];
  return 'tab ${parts.join(', ')}';
}

String? _approvalState(SemanticState state) {
  final id = state['approvalId'];
  final subject = state['approvalSubject'];
  final detailCount = state['detailCount'];
  final confirmLabel = state['confirmLabel'];
  final cancelLabel = state['cancelLabel'];
  if (id == null &&
      subject == null &&
      detailCount == null &&
      confirmLabel == null &&
      cancelLabel == null) {
    return null;
  }
  final parts = <String>[
    if (id != null) 'id $id',
    if (subject != null) 'subject $subject',
    if (detailCount is int) '$detailCount details',
    if (confirmLabel != null) 'approve $confirmLabel',
    if (cancelLabel != null) 'deny $cancelLabel',
  ];
  return 'approval ${parts.join(', ')}';
}

String _countLabel(int count, String singular, [String? plural]) {
  if (count == 1) return '1 $singular';
  return '$count ${plural ?? '${singular}s'}';
}

String _roleLabel(SemanticRole role) {
  switch (role) {
    case SemanticRole.app:
      return 'application';
    case SemanticRole.errorBoundary:
      return 'rendering error';
    case SemanticRole.screen:
      return 'screen';
    case SemanticRole.route:
      return 'route';
    case SemanticRole.region:
      return 'region';
    case SemanticRole.navigation:
      return 'navigation';
    case SemanticRole.list:
      return 'list';
    case SemanticRole.listItem:
      return 'list item';
    case SemanticRole.conversationNavigator:
      return 'conversation navigator';
    case SemanticRole.conversation:
      return 'conversation';
    case SemanticRole.contextPanel:
      return 'context panel';
    case SemanticRole.contextItem:
      return 'context item';
    case SemanticRole.traceTimeline:
      return 'trace timeline';
    case SemanticRole.traceEvent:
      return 'trace event';
    case SemanticRole.patchReview:
      return 'patch review';
    case SemanticRole.patchFile:
      return 'patch file';
    case SemanticRole.messageList:
      return 'message list';
    case SemanticRole.message:
      return 'message';
    case SemanticRole.table:
      return 'table';
    case SemanticRole.tableRow:
      return 'table row';
    case SemanticRole.tableCell:
      return 'table cell';
    case SemanticRole.chart:
      return 'chart';
    case SemanticRole.fileMentionPicker:
      return 'file mention picker';
    case SemanticRole.fileMention:
      return 'file mention';
    case SemanticRole.text:
      return 'text';
    case SemanticRole.link:
      return 'link';
    case SemanticRole.image:
      return 'image';
    case SemanticRole.textField:
      return 'text field';
    case SemanticRole.textArea:
      return 'text area';
    case SemanticRole.button:
      return 'button';
    case SemanticRole.checkbox:
      return 'checkbox';
    case SemanticRole.radio:
      return 'radio';
    case SemanticRole.toggle:
      return 'toggle';
    case SemanticRole.spinButton:
      return 'spin button';
    case SemanticRole.slider:
      return 'slider';
    case SemanticRole.datePicker:
      return 'date picker';
    case SemanticRole.menu:
      return 'menu';
    case SemanticRole.menuItem:
      return 'menu item';
    case SemanticRole.commandPalette:
      return 'command palette';
    case SemanticRole.command:
      return 'command';
    case SemanticRole.modelStatus:
      return 'model status';
    case SemanticRole.tokenMeter:
      return 'token meter';
    case SemanticRole.taskGraph:
      return 'task graph';
    case SemanticRole.task:
      return 'task';
    case SemanticRole.toolCall:
      return 'tool call';
    case SemanticRole.dialog:
      return 'dialog';
    case SemanticRole.approval:
      return 'approval';
    case SemanticRole.progress:
      return 'progress';
    case SemanticRole.log:
      return 'log';
    case SemanticRole.json:
      return 'json document';
    case SemanticRole.jsonNode:
      return 'json node';
    case SemanticRole.diff:
      return 'diff';
    case SemanticRole.diffLine:
      return 'diff line';
    case SemanticRole.code:
      return 'code';
    case SemanticRole.codeLine:
      return 'code line';
    case SemanticRole.markdown:
      return 'markdown document';
    case SemanticRole.markdownBlock:
      return 'markdown block';
    case SemanticRole.diagnostic:
      return 'diagnostic';
    case SemanticRole.status:
      return 'status';
    case SemanticRole.notification:
      return 'notification';
    case SemanticRole.tab:
      return 'tab';
    case SemanticRole.tree:
      return 'tree';
    case SemanticRole.treeItem:
      return 'tree item';
    case SemanticRole.form:
      return 'form';
    case SemanticRole.formField:
      return 'form field';
  }
}
