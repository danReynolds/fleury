import 'dart:async' show FutureOr;

import '../widgets/framework.dart';

/// Identity of a semantic node.
///
/// Ids are unique within a [SemanticTree] snapshot. For identity that is also
/// STABLE ACROSS REBUILDS — required by future incremental/observable semantic
/// backends, remote/agent mirrors, and durable test selectors — give the node
/// an explicit [Semantics.id] or a [Key]; the auto-generated fallback
/// (`element-<hash>`) is snapshot-local and must not be relied on across
/// frames.
final class SemanticNodeId {
  const SemanticNodeId(this.value);

  final String value;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is SemanticNodeId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// The durable meaning of a semantic node.
enum SemanticRole {
  app,
  screen,
  route,
  region,
  navigation,
  list,
  listItem,
  conversationNavigator,
  conversation,
  contextPanel,
  contextItem,
  traceTimeline,
  traceEvent,
  patchReview,
  patchFile,
  messageList,
  message,
  table,
  tableRow,
  tableCell,
  chart,
  fileMentionPicker,
  fileMention,
  text,
  link,
  image,
  textField,
  textArea,
  button,
  checkbox,
  radio,
  toggle,
  spinButton,
  slider,
  datePicker,
  menu,
  menuItem,
  commandPalette,
  command,
  modelStatus,
  tokenMeter,
  taskGraph,
  task,
  toolCall,
  dialog,
  approval,
  progress,
  log,
  json,
  jsonNode,
  diff,
  diffLine,
  code,
  codeLine,
  markdown,
  markdownBlock,
  diagnostic,
  status,
  notification,
  tab,
  tree,
  treeItem,
  form,
  formField,
}

/// Actions a semantic node exposes to tests, inspectors, and future adapters.
enum SemanticAction {
  focus,
  activate,
  submit,
  select,
  copy,
  clear,
  open,
  close,
  dismiss,
  navigate,
  increment,
  decrement,
  start,
  cancel,
  diagnose,
  captureDebug,
}

typedef SemanticActionCallback = FutureOr<void> Function(SemanticAction action);

enum SemanticActionInvocationStatus {
  completed,
  disabled,
  notFound,
  unsupported,
  failed,
}

/// Result of a semantic action invocation through tests or future adapters.
final class SemanticActionInvocationResult {
  const SemanticActionInvocationResult._({
    required this.action,
    required this.status,
    this.node,
    this.error,
    this.stackTrace,
  });

  factory SemanticActionInvocationResult.completed(
    SemanticNode node,
    SemanticAction action,
  ) {
    return SemanticActionInvocationResult._(
      node: node,
      action: action,
      status: SemanticActionInvocationStatus.completed,
    );
  }

  factory SemanticActionInvocationResult.disabled(
    SemanticNode node,
    SemanticAction action,
  ) {
    return SemanticActionInvocationResult._(
      node: node,
      action: action,
      status: SemanticActionInvocationStatus.disabled,
    );
  }

  factory SemanticActionInvocationResult.notFound(SemanticAction action) {
    return SemanticActionInvocationResult._(
      action: action,
      status: SemanticActionInvocationStatus.notFound,
    );
  }

  factory SemanticActionInvocationResult.unsupported(
    SemanticNode node,
    SemanticAction action,
  ) {
    return SemanticActionInvocationResult._(
      node: node,
      action: action,
      status: SemanticActionInvocationStatus.unsupported,
    );
  }

  factory SemanticActionInvocationResult.failed(
    SemanticNode node,
    SemanticAction action, {
    required Object error,
    required StackTrace stackTrace,
  }) {
    return SemanticActionInvocationResult._(
      node: node,
      action: action,
      status: SemanticActionInvocationStatus.failed,
      error: error,
      stackTrace: stackTrace,
    );
  }

  final SemanticNode? node;
  final SemanticAction action;
  final SemanticActionInvocationStatus status;
  final Object? error;
  final StackTrace? stackTrace;

  bool get completed => status == SemanticActionInvocationStatus.completed;
}

/// Extensible typed state carried by semantic nodes.
///
/// The backing store stays map-shaped so early framework work can add narrow
/// state without growing the public constructor constantly. Prefer the typed
/// getters below for common fields.
final class SemanticState {
  const SemanticState([Map<String, Object?> values = const <String, Object?>{}])
    : _values = values;

  static const empty = SemanticState();

  final Map<String, Object?> _values;

  Map<String, Object?> get values => Map.unmodifiable(_values);

  Object? operator [](String key) => _values[key];

  String? get routeName => _string('routeName');
  String? get screenId => _string('screenId');
  String? get screenShortTitle => _string('screenShortTitle');
  String? get activeScreenId => _string('activeScreenId');
  int? get screenCount => _int('screenCount');
  String? get commandId => _string('commandId');
  String? get commandCategory => _string('commandCategory');
  int? get commandCount => _int('commandCount');
  String? get lastCommandId => _string('lastCommandId');
  String? get lastCommandStatus => _string('lastCommandStatus');
  String? get workflowId => _string('workflowId');
  String? get workflowTitle => _string('workflowTitle');
  String? get workflowHealth => _string('workflowHealth');
  int? get messageCount => _int('messageCount');
  int? get toolCallCount => _int('toolCallCount');
  int? get approvalCount => _int('approvalCount');
  int? get activeToolCallCount => _int('activeToolCallCount');
  int? get failedToolCallCount => _int('failedToolCallCount');
  int? get activeMessageCount => _int('activeMessageCount');
  int? get failedMessageCount => _int('failedMessageCount');
  bool? get modelBusy => _bool('modelBusy');
  String? get modelName => _string('modelName');
  String? get modelProvider => _string('modelProvider');
  String? get modelStatus => _string('modelStatus');
  String? get modelMode => _string('modelMode');
  int? get modelLatencyMs => _int('modelLatencyMs');
  int? get modelQueueDepth => _int('modelQueueDepth');
  String? get filePath => _string('filePath');
  String? get fileKind => _string('fileKind');
  String? get fileLanguage => _string('fileLanguage');
  String? get mentionText => _string('mentionText');
  String? get selectedFilePath => _string('selectedFilePath');
  int? get fileMentionCount => _int('fileMentionCount');
  String? get conversationId => _string('conversationId');
  String? get conversationStatus => _string('conversationStatus');
  String? get selectedConversationId => _string('selectedConversationId');
  int? get conversationCount => _int('conversationCount');
  int? get unreadConversationCount => _int('unreadConversationCount');
  int? get conversationUnreadCount => _int('conversationUnreadCount');
  int? get conversationMessageCount => _int('conversationMessageCount');
  Object? get messageId => _values['messageId'];
  Object? get selectedMessageId => _values['selectedMessageId'];
  String? get contextItemId => _string('contextItemId');
  String? get contextItemKind => _string('contextItemKind');
  String? get selectedContextItemId => _string('selectedContextItemId');
  int? get contextItemTokenCount => _int('contextItemTokenCount');
  int? get contextItemCount => _int('contextItemCount');
  int? get contextTokenCount => _int('contextTokenCount');
  String? get contextItemPriority => _string('contextItemPriority');
  String? get traceId => _string('traceId');
  String? get traceKind => _string('traceKind');
  String? get traceStatus => _string('traceStatus');
  String? get selectedTraceId => _string('selectedTraceId');
  int? get traceEventCount => _int('traceEventCount');
  int? get activeTraceEventCount => _int('activeTraceEventCount');
  int? get failedTraceEventCount => _int('failedTraceEventCount');
  int? get warningTraceEventCount => _int('warningTraceEventCount');
  int? get traceDurationMs => _int('traceDurationMs');
  String? get patchId => _string('patchId');
  String? get patchStatus => _string('patchStatus');
  String? get patchFilePath => _string('patchFilePath');
  String? get patchFileStatus => _string('patchFileStatus');
  String? get selectedPatchFilePath => _string('selectedPatchFilePath');
  int? get patchFileCount => _int('patchFileCount');
  int? get reviewIssueCount => _int('reviewIssueCount');
  int? get logEntryCount => _int('logEntryCount');
  int? get warningLogEntryCount => _int('warningLogEntryCount');
  int? get errorLogEntryCount => _int('errorLogEntryCount');
  int? get tokenInput => _int('tokenInput');
  int? get tokenOutput => _int('tokenOutput');
  int? get tokenCached => _int('tokenCached');
  int? get tokenTotal => _int('tokenTotal');
  int? get contextUsed => _int('contextUsed');
  int? get contextLimit => _int('contextLimit');
  int? get contextRemaining => _int('contextRemaining');
  int? get contextRatioPercent => _int('contextRatioPercent');
  String? get taskId => _string('taskId');
  String? get taskStatus => _string('taskStatus');
  String? get taskLabel => _string('taskLabel');
  String? get selectedTaskId => _string('selectedTaskId');
  String? get selectedTaskStatus => _string('selectedTaskStatus');
  int? get taskCount => _int('taskCount');
  int? get activeTaskCount => _int('activeTaskCount');
  int? get failedTaskCount => _int('failedTaskCount');
  int? get taskEventCount => _int('taskEventCount');
  int? get taskRunId => _int('taskRunId');
  int? get taskEventSequence => _int('taskEventSequence');
  String? get taskEventKind => _string('taskEventKind');
  String? get lastTaskEventKind => _string('lastTaskEventKind');
  int? get taskOutputSequence => _int('taskOutputSequence');
  String? get taskOutputSource => _string('taskOutputSource');
  String? get taskOutputSeverity => _string('taskOutputSeverity');
  bool? get taskOutputSanitized => _bool('taskOutputSanitized');
  bool? get taskOutputTruncated => _bool('taskOutputTruncated');
  int? get taskOutputOriginalLength => _int('taskOutputOriginalLength');
  int? get outputCount => _int('outputCount');
  bool? get outputSanitized => _bool('outputSanitized');
  bool? get outputTruncated => _bool('outputTruncated');
  int? get outputOriginalLength => _int('outputOriginalLength');
  String? get shortcut => _string('shortcut');
  num? get progressCurrent => _num('progressCurrent');
  num? get progressTotal => _num('progressTotal');
  String? get progressLabel => _string('progressLabel');
  String? get chartType => _string('chartType');
  int? get chartRowCount => _int('chartRowCount');
  int? get chartColumnCount => _int('chartColumnCount');
  int? get chartSeriesCount => _int('chartSeriesCount');
  int? get chartPointCount => _int('chartPointCount');
  int? get chartRecordedPointCount => _int('chartRecordedPointCount');
  int? get chartBarCount => _int('chartBarCount');
  int? get chartSegmentCount => _int('chartSegmentCount');
  num? get chartMinValue => _num('chartMinValue');
  num? get chartMaxValue => _num('chartMaxValue');
  num? get chartLatestValue => _num('chartLatestValue');
  num? get chartXMin => _num('chartXMin');
  num? get chartXMax => _num('chartXMax');
  num? get chartYMin => _num('chartYMin');
  num? get chartYMax => _num('chartYMax');
  int? get chartCursorIndex => _int('chartCursorIndex');
  int? get chartCursorCount => _int('chartCursorCount');
  num? get chartCursorX => _num('chartCursorX');
  int? get chartReferenceCount => _int('chartReferenceCount');
  bool? get chartInteractive => _bool('chartInteractive');
  String? get chartStartDate => _string('chartStartDate');
  String? get chartEndDate => _string('chartEndDate');
  String? get chartWeekStart => _string('chartWeekStart');
  String? get canvasMarker => _string('canvasMarker');
  num? get canvasMinX => _num('canvasMinX');
  num? get canvasMaxX => _num('canvasMaxX');
  num? get canvasMinY => _num('canvasMinY');
  num? get canvasMaxY => _num('canvasMaxY');
  int? get collectionRowCount => _int('collectionRowCount');
  int? get collectionColumnCount => _int('collectionColumnCount');
  int? get visibleRangeStart => _int('visibleRangeStart');
  int? get visibleRangeEnd => _int('visibleRangeEnd');
  Object? get selectedKey => _values['selectedKey'];
  String? get sortColumn => _string('sortColumn');
  String? get sortDirection => _string('sortDirection');
  String? get filterText => _string('filterText');
  String? get selectionMode => _string('selectionMode');
  int? get selectedColumnIndex => _int('selectedColumnIndex');
  String? get selectedColumnId => _string('selectedColumnId');
  int? get selectionStartRow => _int('selectionStartRow');
  int? get selectionEndRow => _int('selectionEndRow');
  int? get selectionStartColumn => _int('selectionStartColumn');
  int? get selectionEndColumn => _int('selectionEndColumn');
  int? get selectionRowCount => _int('selectionRowCount');
  int? get selectionColumnCount => _int('selectionColumnCount');
  String? get terminalCapability => _string('terminalCapability');
  String? get capabilityRequirement => _string('capabilityRequirement');
  String? get capabilityResolution => _string('capabilityResolution');
  String? get activeFallback => _string('activeFallback');
  String? get statusId => _string('statusId');
  int? get statusCount => _int('statusCount');
  String? get severity => _string('severity');
  String? get source => _string('source');
  int? get tabIndex => _int('tabIndex');
  int? get tabPosition => _int('tabPosition');
  int? get tabCount => _int('tabCount');
  int? get menuDepth => _int('menuDepth');
  int? get menuItemIndex => _int('menuItemIndex');
  int? get menuItemPosition => _int('menuItemPosition');
  int? get menuItemCount => _int('menuItemCount');
  int? get selectionBase => _int('selectionBase');
  int? get selectionExtent => _int('selectionExtent');
  int? get historyCount => _int('historyCount');
  int? get historyIndex => _int('historyIndex');
  bool? get historyBrowsing => _bool('historyBrowsing');
  bool? get completionActive => _bool('completionActive');
  String? get completionQuery => _string('completionQuery');
  int? get completionRangeStart => _int('completionRangeStart');
  int? get completionRangeEnd => _int('completionRangeEnd');
  int? get completionOptionCount => _int('completionOptionCount');
  int? get completionSelectedIndex => _int('completionSelectedIndex');
  bool? get pasteInProgress => _bool('pasteInProgress');
  int? get pasteInsertedLength => _int('pasteInsertedLength');
  int? get pasteTotalLength => _int('pasteTotalLength');
  bool? get composingActive => _bool('composingActive');
  int? get composingStart => _int('composingStart');
  int? get composingEnd => _int('composingEnd');
  bool? get readOnly => _bool('readOnly');
  bool? get obscureText => _bool('obscureText');
  bool? get redactedValue => _bool('redactedValue');
  String? get clipboardPolicy => _string('clipboardPolicy');
  String? get clipboardCapability => _string('clipboardCapability');
  String? get clipboardCapabilityResolution =>
      _string('clipboardCapabilityResolution');
  String? get clipboardFallback => _string('clipboardFallback');
  bool? get clipboardRedacted => _bool('clipboardRedacted');
  String? get clipboardTransport => _string('clipboardTransport');

  SemanticState merge(Map<String, Object?> values) =>
      SemanticState(<String, Object?>{..._values, ...values});

  String? _string(String key) {
    final value = _values[key];
    return value is String ? value : null;
  }

  int? _int(String key) {
    final value = _values[key];
    return value is int ? value : null;
  }

  num? _num(String key) {
    final value = _values[key];
    return value is num ? value : null;
  }

  bool? _bool(String key) {
    final value = _values[key];
    return value is bool ? value : null;
  }

  @override
  String toString() => _values.toString();
}

/// Immutable semantic description of a mounted UI node.
final class SemanticNode {
  const SemanticNode({
    required this.id,
    required this.role,
    this.label,
    this.value,
    this.hint,
    this.enabled = true,
    this.focused = false,
    this.selected = false,
    this.checked,
    this.expanded,
    this.busy = false,
    this.validationError,
    this.actions = const <SemanticAction>{},
    this.children = const <SemanticNode>[],
    this.state = SemanticState.empty,
  });

  final SemanticNodeId id;
  final SemanticRole role;
  final String? label;
  final Object? value;
  final String? hint;
  final bool enabled;
  final bool focused;
  final bool selected;
  final bool? checked;
  final bool? expanded;
  final bool busy;
  final String? validationError;
  final Set<SemanticAction> actions;
  final List<SemanticNode> children;
  final SemanticState state;

  SemanticNode copyWith({List<SemanticNode>? children}) {
    return SemanticNode(
      id: id,
      role: role,
      label: label,
      value: value,
      hint: hint,
      enabled: enabled,
      focused: focused,
      selected: selected,
      checked: checked,
      expanded: expanded,
      busy: busy,
      validationError: validationError,
      actions: actions,
      children: children ?? this.children,
      state: state,
    );
  }

  Iterable<SemanticNode> get descendants sync* {
    for (final child in children) {
      yield child;
      yield* child.descendants;
    }
  }

  Iterable<SemanticNode> get selfAndDescendants sync* {
    yield this;
    yield* descendants;
  }

  @override
  String toString() {
    final labelPart = label == null ? '' : ', label: $label';
    return 'SemanticNode($role$labelPart, id: $id)';
  }
}

/// Immutable semantic snapshot of a mounted Fleury app.
///
/// This is a read-only value snapshot: every query ([byRole], [where],
/// [nodeById], …) is model-agnostic. [SemanticTree.fromElement] is the current
/// producer — a full element-tree walk. The [SemanticTree.new] constructor
/// deliberately accepts a pre-built [root] so a future incremental/observable
/// backend can produce the same query surface from a maintained tree without
/// committing callers to the walk.
final class SemanticTree {
  const SemanticTree({required this.root});

  factory SemanticTree.fromElement(Element root) {
    return SemanticTree(
      root: SemanticNode(
        id: const SemanticNodeId('root'),
        role: SemanticRole.app,
        children: _collectFrom(root),
      ),
    );
  }

  final SemanticNode root;

  Iterable<SemanticNode> get nodes => root.selfAndDescendants;

  Iterable<SemanticNode> byRole(SemanticRole role) =>
      nodes.where((node) => node.role == role);

  Iterable<SemanticNode> byLabel(String label) =>
      nodes.where((node) => node.label == label);

  SemanticNode? nodeById(SemanticNodeId id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  Iterable<SemanticNode> where({
    SemanticNodeId? id,
    SemanticRole? role,
    String? label,
    Object? value,
    SemanticAction? action,
    bool? focused,
    bool? selected,
    bool? enabled,
    bool? checked,
    bool? busy,
    String? validationError,
    String? capabilityRequirement,
    String? activeFallback,
  }) {
    return nodes.where((node) {
      if (id != null && node.id != id) return false;
      if (role != null && node.role != role) return false;
      if (label != null && node.label != label) return false;
      if (value != null && node.value != value) return false;
      if (action != null && !node.actions.contains(action)) return false;
      if (focused != null && node.focused != focused) return false;
      if (selected != null && node.selected != selected) return false;
      if (enabled != null && node.enabled != enabled) return false;
      if (checked != null && node.checked != checked) return false;
      if (busy != null && node.busy != busy) return false;
      if (validationError != null && node.validationError != validationError) {
        return false;
      }
      if (capabilityRequirement != null &&
          node.state.capabilityRequirement != capabilityRequirement) {
        return false;
      }
      if (activeFallback != null &&
          node.state.activeFallback != activeFallback) {
        return false;
      }
      return true;
    });
  }

  SemanticNode single({
    SemanticNodeId? id,
    SemanticRole? role,
    String? label,
    Object? value,
    SemanticAction? action,
    bool? focused,
    bool? selected,
    bool? enabled,
    bool? checked,
    bool? busy,
    String? validationError,
    String? capabilityRequirement,
    String? activeFallback,
  }) {
    final matches = where(
      id: id,
      role: role,
      label: label,
      value: value,
      action: action,
      focused: focused,
      selected: selected,
      enabled: enabled,
      checked: checked,
      busy: busy,
      validationError: validationError,
      capabilityRequirement: capabilityRequirement,
      activeFallback: activeFallback,
    ).toList(growable: false);
    if (matches.length == 1) return matches.single;
    throw StateError(
      'Expected exactly one semantic node, found ${matches.length}.',
    );
  }
}

/// Implemented by elements that contribute a semantic node.
abstract interface class SemanticContributor {
  SemanticNode buildSemanticNode(List<SemanticNode> children);
}

/// Implemented by elements whose semantic subtree differs from their mounted
/// element subtree.
///
/// Widgets such as `IndexedStack` keep inactive children mounted for state
/// retention, but only one child is visible. Semantic collection follows the
/// visible/meaningful subtree rather than every mounted child.
abstract interface class SemanticChildrenProvider {
  void visitSemanticChildren(void Function(Element child) visitor);
}

/// Implemented by semantic contributors that can execute semantic actions.
abstract interface class SemanticActionContributor {
  FutureOr<bool> handleSemanticAction(
    SemanticNode target,
    SemanticAction action,
  );
}

/// App-authored semantic annotation.
///
/// First-party widgets should contribute semantics automatically where
/// possible. Use this wrapper for app-specific regions, custom controls, and
/// early proof-app annotations.
final class Semantics extends ProxyWidget {
  const Semantics({
    super.key,
    this.id,
    required this.role,
    this.label,
    this.value,
    this.hint,
    this.enabled = true,
    this.focused = false,
    this.selected = false,
    this.checked,
    this.expanded,
    this.busy = false,
    this.validationError,
    this.actions = const <SemanticAction>{},
    this.state = SemanticState.empty,
    this.includeChildren = true,
    this.onAction,
    required super.child,
  });

  final SemanticNodeId? id;
  final SemanticRole role;
  final String? label;
  final Object? value;
  final String? hint;
  final bool enabled;
  final bool focused;
  final bool selected;
  final bool? checked;
  final bool? expanded;
  final bool busy;
  final String? validationError;
  final Set<SemanticAction> actions;
  final SemanticState state;
  final bool includeChildren;
  final SemanticActionCallback? onAction;

  @override
  SemanticsElement createElement() => SemanticsElement(this);
}

final class SemanticsElement extends ComponentElement
    implements SemanticContributor, SemanticActionContributor {
  SemanticsElement(Semantics super.widget);

  @override
  Semantics get widget => super.widget as Semantics;

  @override
  void update(covariant Semantics newWidget) {
    super.update(newWidget);
    rebuild(force: true);
  }

  @override
  Widget buildChild() => widget.child;

  /// The node's identity. An explicit [Semantics.id] wins; otherwise a [Key] on
  /// the widget yields a stable, deterministic id (`key:<key>`) that survives
  /// rebuilds — the identity a future incremental/observable backend, a remote
  /// mirror, or a durable test selector needs. With neither, the id falls back
  /// to an element-instance hash, which is snapshot-local and NOT stable across
  /// rebuilds (see [SemanticNodeId]).
  SemanticNodeId get _nodeId {
    final explicitId = widget.id;
    if (explicitId != null) return explicitId;
    final key = widget.key;
    if (key != null) return SemanticNodeId('key:$key');
    return SemanticNodeId('element-$hashCode');
  }

  @override
  SemanticNode buildSemanticNode(List<SemanticNode> children) {
    return SemanticNode(
      id: _nodeId,
      role: widget.role,
      label: widget.label,
      value: widget.value,
      hint: widget.hint,
      enabled: widget.enabled,
      focused: widget.focused,
      selected: widget.selected,
      checked: widget.checked,
      expanded: widget.expanded,
      busy: widget.busy,
      validationError: widget.validationError,
      actions: widget.actions,
      children: widget.includeChildren ? children : const <SemanticNode>[],
      state: widget.state,
    );
  }

  @override
  Future<bool> handleSemanticAction(
    SemanticNode target,
    SemanticAction action,
  ) async {
    final callback = widget.onAction;
    if (callback == null || target.id != _nodeId) return false;
    await callback(action);
    return true;
  }
}

List<SemanticNode> _collectFrom(Element element) {
  final children = <SemanticNode>[];
  void visitChild(Element child) {
    children.addAll(_collectFrom(child));
  }

  if (element is SemanticChildrenProvider) {
    (element as SemanticChildrenProvider).visitSemanticChildren(visitChild);
  } else {
    element.visitChildren(visitChild);
  }

  if (element is SemanticContributor) {
    return <SemanticNode>[
      (element as SemanticContributor).buildSemanticNode(children),
    ];
  }
  return children;
}
