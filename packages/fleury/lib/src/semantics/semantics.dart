import 'dart:async' show FutureOr;

import '../foundation/geometry.dart';
import '../foundation/key.dart' show Key, ValueKey;
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_error_boundary.dart';
import '../rendering/render_object.dart';
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
  errorBoundary,
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

  /// Set the node's value to a payload supplied with the invocation (text into
  /// a field, a slider position, a selected option). Unlike every action above,
  /// it carries an argument — delivered via [SemanticSetValueCallback] /
  /// [SemanticValueContributor], not the parameterless [SemanticActionCallback].
  setValue,
}

typedef SemanticActionCallback = FutureOr<void> Function(SemanticAction action);

/// Carries a [SemanticAction.setValue] payload to the node it targets. The
/// payload is a JSON-friendly scalar (string, num, bool, or null); a widget
/// coerces/validates it for its role (a slider expects a num, a field a string).
typedef SemanticSetValueCallback = FutureOr<void> Function(Object? value);

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

  /// Returns true when this state and [other] carry equivalent typed values.
  ///
  /// This avoids forcing hot semantic diff paths through [values], which
  /// defensively allocates an unmodifiable map for public callers.
  bool hasSameValues(SemanticState other) {
    if (identical(this, other)) return true;
    if (_values.length != other._values.length) return false;
    for (final entry in _values.entries) {
      if (!other._values.containsKey(entry.key)) return false;
      if (!_semanticStateValueEquals(entry.value, other._values[entry.key])) {
        return false;
      }
    }
    return true;
  }

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

bool _semanticStateValueEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!_semanticStateValueEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  if (a is Iterable && b is Iterable) {
    final left = a.iterator;
    final right = b.iterator;
    while (true) {
      final hasLeft = left.moveNext();
      final hasRight = right.moveNext();
      if (hasLeft != hasRight) return false;
      if (!hasLeft) return true;
      if (!_semanticStateValueEquals(left.current, right.current)) {
        return false;
      }
    }
  }
  return a == b;
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
    this.bounds,
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
  final CellRect? bounds;
  final Set<SemanticAction> actions;
  final List<SemanticNode> children;
  final SemanticState state;

  SemanticNode copyWith({List<SemanticNode>? children, CellRect? bounds}) {
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
      bounds: bounds ?? this.bounds,
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
  const SemanticTree({required this.root}) : _elementsById = null;

  SemanticTree._({
    required this.root,
    required Map<SemanticNodeId, Element> elementsById,
  }) : _elementsById = elementsById;

  factory SemanticTree.fromElement(Element root) {
    final elements = <SemanticNodeId, Element>{};
    final children = _collectFrom(root, elements);
    return SemanticTree._(
      root: SemanticNode(
        id: const SemanticNodeId('root'),
        role: SemanticRole.app,
        children: children,
      ),
      elementsById: elements,
    );
  }

  final SemanticNode root;

  /// The mounted [Element] that contributes each node id, captured during the
  /// [fromElement] build walk. Lets action dispatch resolve a target id to its
  /// owning contributor in O(1) — without a second element walk, whose id
  /// recompute can drift from the snapshot's. Null for a tree built via the
  /// const constructor (a value snapshot with no backing elements).
  final Map<SemanticNodeId, Element>? _elementsById;

  /// The mounted [Element] that contributes node [id], or null when this tree
  /// has no element backing or [id] is unknown. The owning contributor for a
  /// node a widget synthesizes itself (e.g. a `DataTable` row/cell) is that
  /// widget's element, matching how the node's id was minted.
  Element? elementById(SemanticNodeId id) => _elementsById?[id];

  /// Flattened semantic nodes in depth-first order.
  ///
  /// The tree is immutable, so the flattened list is cached per tree instance.
  /// Runtime hosts walk this list multiple times per frame for coverage, focus,
  /// diffing, and presentation; sharing the flattening keeps those passes from
  /// recursively re-traversing the same snapshot.
  Iterable<SemanticNode> get nodes => _cachedNodes(this);

  /// Number of nodes in this snapshot.
  int get nodeCount => _cachedNodes(this).length;

  /// Semantic nodes keyed by id.
  ///
  /// This map is cached with [nodes] so diff/presenter consumers do not each
  /// rebuild their own id index for the same immutable snapshot.
  Map<SemanticNodeId, SemanticNode> get nodesById => _cachedNodesById(this);

  Iterable<SemanticNode> byRole(SemanticRole role) =>
      nodes.where((node) => node.role == role);

  Iterable<SemanticNode> byLabel(String label) =>
      nodes.where((node) => node.label == label);

  SemanticNode? nodeById(SemanticNodeId id) {
    return nodesById[id];
  }

  /// Returns a tree with the matching semantic nodes replaced.
  ///
  /// This is intentionally a semantic-tree operation rather than an
  /// element-tree walk. Hosts that receive precise dirty semantic leaf nodes can
  /// produce the next snapshot by rewriting only the retained semantic model,
  /// then still run the normal coverage, focus, diff, and presentation stages
  /// against a complete immutable tree.
  SemanticTree replaceNodes(Map<SemanticNodeId, SemanticNode> replacements) {
    if (replacements.isEmpty) return this;
    final replacement = _replaceSemanticNode(root, replacements);
    if (identical(replacement, root)) return this;
    // The element map is intentionally NOT carried forward: action dispatch
    // always resolves against a fresh `fromElement` tree built from the live
    // root (terminal, web, and tester paths all do this), so a retained-leaf
    // snapshot never needs to back dispatch — and carrying a prior frame's
    // elements risks pointing at since-unmounted ones.
    final tree = SemanticTree(root: replacement);
    _cacheLeafReplacementTree(this, tree, replacements);
    return tree;
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

SemanticNode _replaceSemanticNode(
  SemanticNode node,
  Map<SemanticNodeId, SemanticNode> replacements,
) {
  final replacement = replacements[node.id];
  if (replacement != null) return replacement;

  List<SemanticNode>? children;
  for (var index = 0; index < node.children.length; index++) {
    final child = node.children[index];
    final nextChild = _replaceSemanticNode(child, replacements);
    if (!identical(nextChild, child)) {
      children ??= node.children.toList(growable: false);
      children[index] = nextChild;
    }
  }
  if (children == null) return node;
  return node.copyWith(children: List<SemanticNode>.unmodifiable(children));
}

void _cacheLeafReplacementTree(
  SemanticTree previous,
  SemanticTree next,
  Map<SemanticNodeId, SemanticNode> replacements,
) {
  final previousNodes = _semanticTreeNodes[previous];
  if (previousNodes == null) return;

  List<SemanticNode>? nextNodes;
  for (var index = 0; index < previousNodes.length; index++) {
    final previousNode = previousNodes[index];
    final replacement = replacements[previousNode.id];
    if (replacement == null) continue;
    if (previousNode.children.isNotEmpty || replacement.children.isNotEmpty) {
      return;
    }
    nextNodes ??= previousNodes.toList(growable: false);
    nextNodes[index] = replacement;
  }
  if (nextNodes == null) return;

  final cachedNodes = List<SemanticNode>.unmodifiable(nextNodes);
  _semanticTreeNodes[next] = cachedNodes;

  final previousNodesById = _semanticTreeNodesById[previous];
  final nextNodesById = previousNodesById == null
      ? <SemanticNodeId, SemanticNode>{
          for (final node in cachedNodes) node.id: node,
        }
      : Map<SemanticNodeId, SemanticNode>.of(previousNodesById);
  for (final entry in replacements.entries) {
    nextNodesById[entry.key] = entry.value;
  }
  _semanticTreeNodesById[next] = Map<SemanticNodeId, SemanticNode>.unmodifiable(
    nextNodesById,
  );
}

final Expando<List<SemanticNode>> _semanticTreeNodes =
    Expando<List<SemanticNode>>('fleury.SemanticTree.nodes');
final Expando<Map<SemanticNodeId, SemanticNode>> _semanticTreeNodesById =
    Expando<Map<SemanticNodeId, SemanticNode>>('fleury.SemanticTree.nodesById');

List<SemanticNode> _cachedNodes(SemanticTree tree) {
  final cached = _semanticTreeNodes[tree];
  if (cached != null) return cached;
  final collected = <SemanticNode>[];
  void collect(SemanticNode node) {
    collected.add(node);
    for (final child in node.children) {
      collect(child);
    }
  }

  collect(tree.root);
  final nodes = List<SemanticNode>.unmodifiable(collected);
  _semanticTreeNodes[tree] = nodes;
  return nodes;
}

Map<SemanticNodeId, SemanticNode> _cachedNodesById(SemanticTree tree) {
  final cached = _semanticTreeNodesById[tree];
  if (cached != null) return cached;
  final nodesById = Map<SemanticNodeId, SemanticNode>.unmodifiable({
    for (final node in _cachedNodes(tree)) node.id: node,
  });
  _semanticTreeNodesById[tree] = nodesById;
  return nodesById;
}

/// Invokes [action] on the semantic node [id] by dispatching through the
/// mounted element tree rooted at [root].
///
/// This is the runtime counterpart to semantic-test action invocation. Hosts
/// such as the web semantic DOM can use it to route assistive-technology or
/// mirrored-control activation back into the real Fleury widget tree.
Future<SemanticActionInvocationResult> invokeSemanticActionFromElement({
  required SemanticTree tree,
  required SemanticNodeId id,
  required SemanticAction action,
  Object? value,
}) async {
  final target = tree.nodeById(id);
  if (target == null) return SemanticActionInvocationResult.notFound(action);
  if (!target.enabled) {
    return SemanticActionInvocationResult.disabled(target, action);
  }
  if (!target.actions.contains(action)) {
    return SemanticActionInvocationResult.unsupported(target, action);
  }
  // Resolve the id to the element that contributed it — built in the same walk
  // that minted the id, so it matches exactly — and dispatch straight there. No
  // second element walk, so a contributor can never be handed an action meant
  // for a sibling (the cross-fire the per-widget self-checks used to guard).
  final element = tree.elementById(id);
  if (element == null) {
    return SemanticActionInvocationResult.unsupported(target, action);
  }
  try {
    final dispatchResult = _dispatchSemanticActionOnElement(
      element,
      target,
      action,
      value,
    );
    final handled = dispatchResult is Future<bool>
        ? await dispatchResult
        : dispatchResult;
    return handled
        ? SemanticActionInvocationResult.completed(target, action)
        : SemanticActionInvocationResult.unsupported(target, action);
  } catch (error, stackTrace) {
    return SemanticActionInvocationResult.failed(
      target,
      action,
      error: error,
      stackTrace: stackTrace,
    );
  }
}

FutureOr<bool> _dispatchSemanticActionOnElement(
  Element element,
  SemanticNode target,
  SemanticAction action,
  Object? value,
) {
  // `setValue` carries a payload, so it routes to the opt-in value contributor
  // rather than the parameterless action handler. A node that advertises
  // setValue but doesn't implement [SemanticValueContributor] simply goes
  // unhandled (→ unsupported), like any other unhandled action.
  if (action == SemanticAction.setValue &&
      element is SemanticValueContributor) {
    return (element as SemanticValueContributor).handleSemanticSetValue(
      target,
      value,
    );
  }
  if (element is! SemanticActionContributor) return false;
  final contributor = element as SemanticActionContributor;
  return contributor.handleSemanticAction(target, action);
}

/// A stable, position-derived identity anchor for [element], folding the chain
/// of keyed ancestors (the same `Key`s reconciliation uses) with a positional
/// `~<index>` segment for each unkeyed step *below* the nearest key.
///
/// Returns null when no foldable key exists anywhere above [element] — the
/// caller then keeps the snapshot-local `element-<hash>` form. Unlike that hash,
/// this anchor is derived from keys + tree position rather than element
/// instance identity, so it is identical across rebuilds: a node under a keyed
/// list row keeps its id wherever the row moves. `GlobalKey`s are treated as
/// transparent (they have no stable string and survive reparenting on their
/// own), so anchoring lands on the nearest value key, which is what stays put
/// under a `GlobalKey` move.
///
/// The *full* keyed chain is folded (not just the nearest key) deliberately: it
/// keeps ids globally unique — no false "ambiguous" rejections — and gives even
/// unkeyed nodes a session-stable anchor (the runtime/overlay root is keyed), at
/// the cost of a constant, opaque framework-key prefix on every id. Ids are
/// opaque handles, so that prefix is harmless; trimming it would trade that
/// uniqueness and stability for cosmetics.
///
/// Privacy: a folded key value is the same identifier the app already chose for
/// reconciliation, and a keyed ancestor already exposes it as *its own* node id,
/// so folding it into descendant ids reveals no value the snapshot didn't
/// already carry. Ids are display-sanitized at the inspection boundary; like the
/// own-`key:` form, this scheme treats `Key`s as structural identifiers, not a
/// place to encode secrets.
/// Escapes a folded key value so it cannot inject the `/` segment separator or
/// the `~` positional marker into a derived id (see [semanticAnchorOf]).
///
/// Without this, an app `Key` whose string form contains `~` (e.g.
/// `ValueKey('a~b')`, a path/range) would make a *stable* id look positional to
/// the stale-reference guard, and a `/` would inject phantom segments that break
/// uniqueness. Percent-style so the escape introduces no `/` or `~` of its own;
/// `~` in a derived id then unambiguously means "positional segment", never key
/// content. Contributors that mint child ids from a key (e.g. `DataTable` rows)
/// must apply this too.
String escapeSemanticIdSegment(String segment) => segment
    .replaceAll('%', '%25')
    .replaceAll('~', '%7E')
    .replaceAll('/', '%2F');

/// Renders a [Key] compactly for a derived id (already escaped by the caller).
///
/// A [ValueKey]'s `toString` wraps its value — `ValueKey<String>(row-3)` — which
/// is ~17 bytes of boilerplate that says nothing the value (`row-3`) doesn't.
/// Folded onto *every* descendant's id, that boilerplate dominates the get_ui
/// token cost, so derived ids carry just the value. An object-valued key (e.g.
/// the overlay entry, whose `toString` is the verbose `Instance of '…'`) renders
/// as a short, session-stable identity token instead.
String _renderSemanticKeySegment(Key key) {
  if (key is! ValueKey) return '$key';
  final Object? value = key.value;
  if (value is String) return value;
  if (value is num || value is bool) return '$value';
  // Object-valued key: its toString is verbose; use a session-stable token.
  return '${value.runtimeType}#${identityHashCode(value).toRadixString(36)}';
}

String? semanticAnchorOf(Element element) {
  final scope = <String>[]; // keyed segments, leaf→root
  final tail =
      <String>[]; // positional segments below the nearest key, leaf→root
  var sawKey = false;
  Element? e = element;
  while (e != null) {
    final key = e.widget.key;
    if (key != null && key is! GlobalKey) {
      scope.add(escapeSemanticIdSegment(_renderSemanticKeySegment(key)));
      sawKey = true;
    } else if (!sawKey) {
      tail.add('~${_childIndexOf(e)}');
    }
    e = e.elementParent;
  }
  if (!sawKey) return null;
  return 'auto:${[...scope.reversed, ...tail.reversed].join('/')}';
}

/// Whether [id] is an auto-generated *positional* id — one that can come to
/// denote a different logical node when the tree shifts, so a held reference to
/// it may go stale. Two forms qualify: the `element-<hash>` snapshot-local
/// fallback, and a derived `auto:…` id carrying a `~` positional segment (see
/// [semanticAnchorOf]). App-assigned, `key:…`, and fully-keyed `auto:` ids (no
/// `~`) track their logical node and are stable.
///
/// Lives beside the encoding so the id scheme has a single owner: consumers that
/// guard against stale references (e.g. `fleury_mcp`) ask here rather than
/// re-deriving the prefix rules.
bool isPositionalSemanticId(String id) =>
    id.startsWith('element-') || (id.startsWith('auto:') && id.contains('~'));

/// [element]'s index among its parent's children, in `visitChildren` order.
/// Element-local and reproducible: the leaf-update path and dispatch both
/// recompute the id from the live element, and a position change is always a
/// structural change (a full rebuild), so the index is only ever read while the
/// tree shape is stable.
int _childIndexOf(Element element) {
  final parent = element.elementParent;
  if (parent == null) return 0;
  var index = 0;
  var result = -1;
  parent.visitChildren((child) {
    if (identical(child, element)) result = index;
    index++;
  });
  // Not found ⇒ the id is being derived mid-reparent, before this child is
  // listed under its (new) parent — a transient, legitimate window (e.g.
  // SemanticsElement.update during a move). Return an out-of-range index (the
  // child count) rather than a silent 0 that would alias the genuine first
  // sibling; the id re-derives correctly once the move settles.
  return result >= 0 ? result : index;
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

/// Implemented by semantic contributors that can apply a [SemanticAction
/// .setValue] payload. Opt-in and additive: only value-bearing nodes implement
/// it, so the existing [SemanticActionContributor]s are untouched. Return true
/// if the value was applied.
abstract interface class SemanticValueContributor {
  FutureOr<bool> handleSemanticSetValue(SemanticNode target, Object? value);
}

/// Frame-local semantic invalidations collected while the element/render tree
/// updates.
///
/// The dirty signal is deliberately conservative. Leaf semantic annotations can
/// be rebuilt directly from the mounted [SemanticsElement]; structural changes,
/// child-inclusive semantics, moves, mounts, unmounts, or stale elements force
/// hosts back to [SemanticTree.fromElement].
final class SemanticDirtyTracker {
  bool _requiresFullRebuild = false;
  final Map<SemanticNodeId, SemanticsElement> _dirtyLeafElements =
      <SemanticNodeId, SemanticsElement>{};

  /// Whether any dirt has accumulated since the last [takeDirtySnapshot].
  ///
  /// A cheap peek for hosts deciding whether to schedule a deferred semantic
  /// flush; it does not validate or consume the accumulated state.
  bool get hasDirt => _requiresFullRebuild || _dirtyLeafElements.isNotEmpty;

  void recordStructureDirty() {
    _requiresFullRebuild = true;
    _dirtyLeafElements.clear();
  }

  void recordLeafDirty(SemanticsElement element) {
    if (_requiresFullRebuild) return;
    if (!element._canBuildRetainedLeaf) {
      recordStructureDirty();
      return;
    }
    _dirtyLeafElements[element._nodeId] = element;
  }

  SemanticDirtySnapshot takeDirtySnapshot() {
    if (_requiresFullRebuild) {
      _requiresFullRebuild = false;
      _dirtyLeafElements.clear();
      return const SemanticDirtySnapshot.fullRebuild();
    }
    if (_dirtyLeafElements.isEmpty) {
      return const SemanticDirtySnapshot.clean();
    }

    final dirtyElements = Map<SemanticNodeId, SemanticsElement>.of(
      _dirtyLeafElements,
    );
    _dirtyLeafElements.clear();
    final leafUpdates = <SemanticNodeId, SemanticNode>{};
    for (final entry in dirtyElements.entries) {
      final element = entry.value;
      if (!element.mounted ||
          !element._canBuildRetainedLeaf ||
          element._nodeId != entry.key) {
        return const SemanticDirtySnapshot.fullRebuild();
      }
      leafUpdates[entry.key] = element._buildRetainedLeafSemanticNode();
    }
    return SemanticDirtySnapshot.leafUpdates(leafUpdates);
  }

  void reset() {
    _requiresFullRebuild = false;
    _dirtyLeafElements.clear();
  }
}

final Expando<SemanticDirtyTracker> _semanticDirtyTrackers =
    Expando<SemanticDirtyTracker>('fleury.BuildOwner.semanticDirtyTracker');

/// Per-[BuildOwner] semantic dirty tracking.
///
/// [SemanticsElement]s record into their owner's tracker, so two Fleury
/// runtimes in one isolate never observe each other's semantic dirt. The
/// tracker accumulates marks across frames until [SemanticDirtyTracker
/// .takeDirtySnapshot] consumes them, which lets deferred semantic
/// presentation coalesce several frames into one flush. Attached lazily via
/// an [Expando] (the same per-instance idiom [SemanticTree]'s caches use) so
/// the widgets layer takes no dependency on semantics.
extension SemanticDirtyOwner on BuildOwner {
  SemanticDirtyTracker get semanticDirtyTracker =>
      _semanticDirtyTrackers[this] ??= SemanticDirtyTracker();
}

/// Semantic dirty state captured for one rendered frame.
final class SemanticDirtySnapshot {
  const SemanticDirtySnapshot._({
    required this.requiresFullRebuild,
    required this.leafUpdates,
  });

  const SemanticDirtySnapshot.clean()
    : this._(
        requiresFullRebuild: false,
        leafUpdates: const <SemanticNodeId, SemanticNode>{},
      );

  const SemanticDirtySnapshot.fullRebuild()
    : this._(
        requiresFullRebuild: true,
        leafUpdates: const <SemanticNodeId, SemanticNode>{},
      );

  SemanticDirtySnapshot.leafUpdates(
    Map<SemanticNodeId, SemanticNode> leafUpdates,
  ) : this._(
        requiresFullRebuild: false,
        leafUpdates: Map<SemanticNodeId, SemanticNode>.unmodifiable(
          leafUpdates,
        ),
      );

  final bool requiresFullRebuild;
  final Map<SemanticNodeId, SemanticNode> leafUpdates;

  bool get isClean => !requiresFullRebuild && leafUpdates.isEmpty;
}

/// App-authored semantic annotation.
///
/// First-party widgets should contribute semantics automatically where
/// possible. Use this wrapper for app-specific regions, custom controls, and
/// early demo-app annotations.
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
    this.onSetValue,
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

  /// Handler for a [SemanticAction.setValue] invocation. A node that advertises
  /// `setValue` in [actions] provides this to receive the payload (e.g. a text
  /// field sets its controller, a slider its position).
  final SemanticSetValueCallback? onSetValue;

  @override
  SemanticsElement createElement() => SemanticsElement(this);
}

final class SemanticsElement extends ComponentElement
    implements
        SemanticContributor,
        SemanticChildrenProvider,
        SemanticActionContributor,
        SemanticValueContributor {
  SemanticsElement(Semantics super.widget);

  CellRect? _bounds;
  SemanticNode? _cachedSemanticNode;

  @override
  Semantics get widget => super.widget as Semantics;

  @override
  void mount(Element? parent) {
    super.mount(parent);
    owner.semanticDirtyTracker.recordStructureDirty();
  }

  @override
  void update(covariant Semantics newWidget) {
    final oldId = _nodeId;
    final oldIncludeChildren = widget.includeChildren;
    super.update(newWidget);
    if (oldId != _nodeId || oldIncludeChildren || newWidget.includeChildren) {
      owner.semanticDirtyTracker.recordStructureDirty();
    } else {
      owner.semanticDirtyTracker.recordLeafDirty(this);
    }
    rebuild(force: true);
  }

  @override
  void deactivate() {
    owner.semanticDirtyTracker.recordStructureDirty();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    owner.semanticDirtyTracker.recordStructureDirty();
  }

  @override
  void unmount() {
    owner.semanticDirtyTracker.recordStructureDirty();
    super.unmount();
  }

  @override
  Widget buildChild() {
    return _SemanticBounds(onPaintBounds: _updateBounds, child: widget.child);
  }

  /// The node's identity. An explicit [Semantics.id] wins; otherwise a [Key] on
  /// the widget yields a stable, deterministic id (`key:<key>`) that survives
  /// rebuilds — the identity a future incremental/observable backend, a remote
  /// mirror, or a durable test selector needs.
  ///
  /// With neither, the id is *derived from the keyed-ancestor chain*
  /// ([semanticAnchorOf]): a node under a keyed list row gets an `auto:…` id
  /// that tracks the row wherever it moves, instead of a churning element hash.
  /// Only when nothing above the node is keyed does it fall back to the
  /// snapshot-local `element-<hash>` form (still NOT stable across rebuilds;
  /// see [SemanticNodeId]).
  ///
  /// Recomputed on every read (it is O(depth)): the value is position-dependent,
  /// so caching it would need a freshness signal that covers *non-Semantics*
  /// reshuffles — which shift a positional segment without any
  /// [SemanticsElement] lifecycle event. That signal (a build-owner structure
  /// generation) is folded into the deferred A3 work; until then, always-fresh
  /// is the only provably correct choice.
  SemanticNodeId get _nodeId {
    final explicitId = widget.id;
    if (explicitId != null) return explicitId;
    final key = widget.key;
    if (key != null) {
      return SemanticNodeId(
        'key:${escapeSemanticIdSegment(_renderSemanticKeySegment(key))}',
      );
    }
    final anchor = semanticAnchorOf(this);
    if (anchor == null) return SemanticNodeId('element-$hashCode');
    return SemanticNodeId('$anchor/${widget.role.name}');
  }

  bool get _canBuildRetainedLeaf => !widget.includeChildren;

  void _updateBounds(CellRect? bounds) {
    if (_bounds == bounds) return;
    _bounds = bounds;
    _cachedSemanticNode = null;
    if (_canBuildRetainedLeaf) {
      owner.semanticDirtyTracker.recordLeafDirty(this);
    } else {
      owner.semanticDirtyTracker.recordStructureDirty();
    }
  }

  SemanticNode _buildRetainedLeafSemanticNode() {
    return buildSemanticNode(const <SemanticNode>[]);
  }

  @override
  void visitSemanticChildren(void Function(Element child) visitor) {
    if (!widget.includeChildren) return;
    visitChildren(visitor);
  }

  @override
  SemanticNode buildSemanticNode(List<SemanticNode> children) {
    final semanticChildren = widget.includeChildren
        ? children
        : const <SemanticNode>[];
    final id = _nodeId;
    final cached = _cachedSemanticNode;
    if (cached != null &&
        semanticChildren.isEmpty &&
        cached.children.isEmpty &&
        cached.id == id &&
        cached.role == widget.role &&
        cached.label == widget.label &&
        cached.value == widget.value &&
        cached.hint == widget.hint &&
        cached.enabled == widget.enabled &&
        cached.focused == widget.focused &&
        cached.selected == widget.selected &&
        cached.checked == widget.checked &&
        cached.expanded == widget.expanded &&
        cached.busy == widget.busy &&
        cached.validationError == widget.validationError &&
        cached.bounds == _bounds &&
        identical(cached.actions, widget.actions) &&
        cached.state.hasSameValues(widget.state)) {
      return cached;
    }
    final node = SemanticNode(
      id: id,
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
      bounds: _bounds,
      actions: widget.actions,
      children: semanticChildren,
      state: widget.state,
    );
    if (semanticChildren.isEmpty) _cachedSemanticNode = node;
    return node;
  }

  @override
  Future<bool> handleSemanticAction(
    SemanticNode target,
    SemanticAction action,
  ) async {
    final callback = widget.onAction;
    if (callback == null || target.id != _nodeId) return false;
    if (!widget.enabled || !widget.actions.contains(action)) return false;
    await callback(action);
    return true;
  }

  @override
  Future<bool> handleSemanticSetValue(
    SemanticNode target,
    Object? value,
  ) async {
    final callback = widget.onSetValue;
    if (callback == null || target.id != _nodeId) return false;
    if (!widget.enabled || !widget.actions.contains(SemanticAction.setValue)) {
      return false;
    }
    await callback(value);
    return true;
  }
}

/// Drops [child]'s whole subtree from the semantic tree (while still rendering
/// it) when [excluding] is true.
///
/// The semantic tree is what a screen reader, the web accessible-DOM mirror,
/// and an MCP agent read and drive — so this is how an app hides content from
/// *them* without hiding it visually: a closed-but-mounted drawer, decorative
/// chrome that isn't actionable, or the background behind a modal an agent
/// shouldn't touch. Toggling [excluding] is a structural change; the subtree
/// re-appears verbatim when it flips back to false.
///
/// It contributes no node of its own (unlike [Semantics]); it only gates
/// whether its descendants are collected, via [SemanticChildrenProvider].
final class ExcludeSemantics extends ProxyWidget {
  const ExcludeSemantics({
    super.key,
    this.excluding = true,
    required super.child,
  });

  /// When true (the default), [child]'s semantic subtree is omitted from
  /// collection. When false, this widget is transparent.
  final bool excluding;

  @override
  Element createElement() => _ExcludeSemanticsElement(this);
}

final class _ExcludeSemanticsElement extends ComponentElement
    implements SemanticChildrenProvider {
  _ExcludeSemanticsElement(ExcludeSemantics super.widget);

  @override
  ExcludeSemantics get widget => super.widget as ExcludeSemantics;

  @override
  void mount(Element? parent) {
    super.mount(parent);
    owner.semanticDirtyTracker.recordStructureDirty();
  }

  @override
  void update(covariant ExcludeSemantics newWidget) {
    final wasExcluding = widget.excluding;
    super.update(newWidget);
    // Flipping exclusion adds or removes the whole subtree — a shape change.
    if (wasExcluding != newWidget.excluding) {
      owner.semanticDirtyTracker.recordStructureDirty();
    }
    rebuild(force: true);
  }

  @override
  void deactivate() {
    owner.semanticDirtyTracker.recordStructureDirty();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    owner.semanticDirtyTracker.recordStructureDirty();
  }

  @override
  void unmount() {
    owner.semanticDirtyTracker.recordStructureDirty();
    super.unmount();
  }

  @override
  Widget buildChild() => widget.child;

  @override
  void visitSemanticChildren(void Function(Element child) visitor) {
    if (widget.excluding) return;
    visitChildren(visitor);
  }
}

final class _SemanticBounds extends SingleChildRenderObjectWidget {
  const _SemanticBounds({
    required this.onPaintBounds,
    required Widget super.child,
  });

  final void Function(CellRect? bounds) onPaintBounds;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSemanticBounds(onPaintBounds: onPaintBounds);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSemanticBounds renderObject,
  ) {
    renderObject.onPaintBounds = onPaintBounds;
  }
}

final class _RenderSemanticBounds extends RenderObject
    implements RenderObjectWithSingleChild {
  _RenderSemanticBounds({
    required void Function(CellRect? bounds) onPaintBounds,
  }) : _onPaintBounds = onPaintBounds;

  void Function(CellRect? bounds) _onPaintBounds;
  set onPaintBounds(void Function(CellRect? bounds) value) {
    _onPaintBounds = value;
  }

  RenderObject? _child;

  @override
  RenderObject? get child => _child;

  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) dropChild(_child!);
    _child = value;
    if (value != null) adoptChild(value);
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final child = _child;
    if (child == null) return constraints.constrain(CellSize.zero);
    return child.layout(constraints);
  }

  @override
  int computeMaxIntrinsicWidth(int? height) {
    return _child?.computeMaxIntrinsicWidth(height) ?? 0;
  }

  @override
  int computeMinIntrinsicWidth(int? height) {
    return _child?.computeMinIntrinsicWidth(height) ?? 0;
  }

  @override
  int computeMaxIntrinsicHeight(int? width) {
    return _child?.computeMaxIntrinsicHeight(width) ?? 0;
  }

  @override
  int computeMinIntrinsicHeight(int? width) {
    return _child?.computeMinIntrinsicHeight(width) ?? 0;
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final localRect = CellRect(offset: offset, size: size);
    final rect = CellRect(offset: screenOffset ?? offset, size: size);
    SemanticPaintBoundsCapture.record(_onPaintBounds, localRect);
    _onPaintBounds(clipRect == null ? rect : rect.intersect(clipRect));
    _child?.paint(
      buffer,
      offset,
      screenOffset: screenOffset ?? offset,
      clipRect: clipRect,
    );
  }
}

List<SemanticNode> _collectFrom(
  Element element, [
  Map<SemanticNodeId, Element>? elements,
]) {
  final nodes = <SemanticNode>[];
  _collectInto(element, nodes, elements);
  return nodes;
}

void _collectInto(
  Element element,
  List<SemanticNode> output,
  Map<SemanticNodeId, Element>? elements,
) {
  // An errored containment boundary: its subtree's elements are mounted
  // but its content is NOT on screen (the boundary paints the error
  // presentation instead). Projecting the descendants would let AT and
  // agents see — and actuate — invisible UI, so the walk emits a single
  // errorBoundary node with the presentation's bounds and drops the rest.
  // Actions against dropped ids resolve notFound: fail-closed, matching
  // the stale-id posture.
  if (element is RenderObjectElement) {
    final render = element.renderObject;
    if (render is RenderErrorContainment) {
      final contained = (render as RenderErrorContainment).containedError;
      if (contained != null) {
        // Synthesized id, positional like the coverage-fallback scheme:
        // anchored to the presentation's screen position so two errored
        // boundaries never collide, stable while the boundary stays put.
        final region = contained.paintedRegion;
        output.add(
          SemanticNode(
            id: SemanticNodeId(
              '__fleury_error_boundary_'
              '${region?.top ?? 0}_${region?.left ?? 0}',
            ),
            role: SemanticRole.errorBoundary,
            label: 'Rendering failed: ${contained.error}',
            state: SemanticState({
              'error': '${contained.error}',
              'phase': contained.phase.name,
            }),
            bounds: contained.paintedRegion,
          ),
        );
        return;
      }
    }
  }
  if (element is SemanticChildrenProvider) {
    if (element is SemanticContributor) {
      final children = <SemanticNode>[];
      (element as SemanticChildrenProvider).visitSemanticChildren(
        (child) => _collectInto(child, children, elements),
      );
      final node = (element as SemanticContributor).buildSemanticNode(children);
      output.add(node);
      _indexOwnedIds(node, element, children, elements);
      return;
    }
    (element as SemanticChildrenProvider).visitSemanticChildren(
      (child) => _collectInto(child, output, elements),
    );
    return;
  }

  if (element is SemanticContributor) {
    final children = <SemanticNode>[];
    element.visitChildren((child) => _collectInto(child, children, elements));
    final node = (element as SemanticContributor).buildSemanticNode(children);
    output.add(node);
    _indexOwnedIds(node, element, children, elements);
  } else {
    element.visitChildren((child) => _collectInto(child, output, elements));
  }
}

/// Maps every id in [node]'s subtree that [element] *itself* contributed — i.e.
/// not a node grafted in from a child contributor (those are in
/// [graftedChildren] and get mapped to their own element when walked) — to
/// [element]. A widget that synthesizes its own descendants (a `DataTable`'s
/// rows/cells) owns those ids, so an action on one routes to that widget.
void _indexOwnedIds(
  SemanticNode node,
  Element element,
  List<SemanticNode> graftedChildren,
  Map<SemanticNodeId, Element>? elements,
) {
  if (elements == null) return;
  final graftedIds = graftedChildren.isEmpty
      ? const <SemanticNodeId>{}
      : <SemanticNodeId>{for (final child in graftedChildren) child.id};
  void walk(SemanticNode n) {
    if (graftedIds.contains(n.id)) return; // owned by a child contributor
    final existing = elements[n.id];
    if (existing != null && !identical(existing, element)) {
      // Two DIFFERENT contributors derived the same id — e.g. a reused key under
      // distinct unkeyed parents, which `semanticAnchorOf` can fold to one
      // `auto:` id. Drop it so dispatch fails CLOSED (elementById → null →
      // "unsupported") instead of silently routing to whichever was walked last.
      // The snapshot's `where(id:)` still sees both nodes, so the MCP layer
      // already rejects the id as ambiguous; this gives the terminal/AT dispatch
      // path the same fail-closed behaviour. (Ids dup'd WITHIN one contributor
      // map to the same element and are kept; a 3+-way collision — vanishingly
      // rare — degrades to the last writer, still caught by the MCP guard.)
      elements.remove(n.id);
    } else {
      elements[n.id] = element;
    }
    for (final child in n.children) {
      walk(child);
    }
  }

  walk(node);
}
