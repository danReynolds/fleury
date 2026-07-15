import 'package:meta/meta.dart';

import '../foundation/geometry.dart';
import '../rendering/text_sanitizer.dart';
import 'semantics.dart';

/// Machine-readable, redaction-aware semantic inspection snapshot.
///
/// This is the v0 protocol shape for tests, debug capture, and future
/// automation/agent adapters that need the meaning tree without scraping
/// rendered terminal cells.
final class SemanticInspectionSnapshot {
  /// Current semantic inspection protocol version emitted by Fleury.
  ///
  /// Version 1 is additive-forward-compatible: readers must ignore unknown
  /// top-level and node fields, while writers must preserve the stable fields
  /// listed in [stableJsonFields] and [SemanticInspectionNode.stableJsonFields]
  /// for the lifetime of the v1 protocol.
  static const int currentSchemaVersion = 1;

  /// Oldest semantic inspection protocol version this reader accepts.
  static const int minimumCompatibleSchemaVersion = 1;

  /// Stable top-level JSON keys for schema v1.
  static const Set<String> stableJsonFields = <String>{
    'schemaVersion',
    'nodeCount',
    'focusedNodeId',
    'roleCounts',
    'actionCount',
    'root',
  };

  SemanticInspectionSnapshot._({
    required this.schemaVersion,
    required this.root,
    required this.nodeCount,
    required this.focusedNodeId,
    required Map<String, int> roleCounts,
    required this.actionCount,
  }) : roleCounts = Map<String, int>.unmodifiable(roleCounts);

  factory SemanticInspectionSnapshot.fromTree(
    SemanticTree tree, {
    int schemaVersion = currentSchemaVersion,
  }) {
    final root = SemanticInspectionNode._fromSemanticNode(tree.root);
    return SemanticInspectionSnapshot._fromRoot(
      schemaVersion: schemaVersion,
      root: root,
      preferredFocusedNodeId: null,
    );
  }

  /// Parses a JSON semantic inspection snapshot.
  ///
  /// Unknown fields are intentionally ignored so v1 readers can tolerate
  /// additive producer changes. Aggregate counts are recomputed from [root]
  /// instead of trusting stale or malformed summary values.
  factory SemanticInspectionSnapshot.fromJson(Map<String, Object?> json) {
    final schemaVersion = _jsonInt(
      json['schemaVersion'],
      fallback: currentSchemaVersion,
    );
    if (!isSchemaVersionCompatible(schemaVersion)) {
      throw FormatException(
        'Unsupported semantic inspection schemaVersion $schemaVersion.',
      );
    }
    final rootJson = _jsonMap(json['root']);
    if (rootJson == null) {
      throw const FormatException('Semantic inspection JSON is missing root.');
    }
    return SemanticInspectionSnapshot._fromRoot(
      schemaVersion: schemaVersion,
      root: SemanticInspectionNode.fromJson(rootJson),
      preferredFocusedNodeId: _jsonString(json['focusedNodeId']),
    );
  }

  static bool isSchemaVersionCompatible(int schemaVersion) {
    return schemaVersion >= minimumCompatibleSchemaVersion;
  }

  factory SemanticInspectionSnapshot._fromRoot({
    required int schemaVersion,
    required SemanticInspectionNode root,
    required String? preferredFocusedNodeId,
  }) {
    final nodes = root.selfAndDescendants.toList(growable: false);
    var actionCount = 0;
    final roleCounts = <String, int>{};
    String? firstFocusedNodeId;

    for (final node in nodes) {
      roleCounts[node.role] = (roleCounts[node.role] ?? 0) + 1;
      actionCount += node.actions.length;
      if (firstFocusedNodeId == null && node.focused) {
        firstFocusedNodeId = node.id;
      }
    }

    final sortedRoleCounts = <String, int>{
      for (final role in roleCounts.keys.toList()..sort())
        role: roleCounts[role]!,
    };
    return SemanticInspectionSnapshot._(
      schemaVersion: schemaVersion,
      root: root,
      nodeCount: nodes.length,
      focusedNodeId:
          preferredFocusedNodeId != null &&
              nodes.any((node) => node.id == preferredFocusedNodeId)
          ? preferredFocusedNodeId
          : firstFocusedNodeId,
      roleCounts: sortedRoleCounts,
      actionCount: actionCount,
    );
  }

  final int schemaVersion;
  final SemanticInspectionNode root;
  final int nodeCount;
  final String? focusedNodeId;
  final Map<String, int> roleCounts;
  final int actionCount;

  // Per-snapshot lazy caches. A snapshot is immutable for its revision, so the
  // flattened node list and the id index are computed once on first use and
  // reused across every read AND the stale-reference guard — repeated lookups on
  // an unchanged revision do no further full-tree walk (WS-7).
  List<SemanticInspectionNode>? _nodeList;
  Map<String, List<SemanticInspectionNode>>? _idIndex;

  Iterable<SemanticInspectionNode> get nodes =>
      _nodeList ??= root.selfAndDescendants.toList(growable: false);

  /// id → the node(s) carrying it — usually one, but a list so the ambiguity
  /// guard (`where(id:)` returning >1) still works on duplicate ids.
  Map<String, List<SemanticInspectionNode>> get _byId {
    final cached = _idIndex;
    if (cached != null) return cached;
    final index = <String, List<SemanticInspectionNode>>{};
    for (final node in nodes) {
      (index[node.id] ??= <SemanticInspectionNode>[]).add(node);
    }
    return _idIndex = index;
  }

  SemanticInspectionNode? nodeById(String id) {
    final list = _byId[id];
    return (list == null || list.isEmpty) ? null : list.first;
  }

  Iterable<SemanticInspectionNode> where({
    String? id,
    String? role,
    String? label,
    String? labelContains,
    Object? value,
    String? action,
    bool? focused,
    bool? selected,
    bool? enabled,
    Map<String, Object?> stateContains = const <String, Object?>{},
  }) {
    // An id query starts from the O(1) index bucket instead of a full walk; the
    // bucket is already id-matched, so `_matches` re-applies the OTHER filters.
    final base = id == null
        ? nodes
        : (_byId[id] ?? const <SemanticInspectionNode>[]);
    return base.where(
      (node) => node._matches(
        id: id,
        role: role,
        label: label,
        labelContains: labelContains,
        value: value,
        action: action,
        focused: focused,
        selected: selected,
        enabled: enabled,
        stateContains: stateContains,
      ),
    );
  }

  SemanticInspectionNode single({
    String? id,
    String? role,
    String? label,
    String? labelContains,
    Object? value,
    String? action,
    bool? focused,
    bool? selected,
    bool? enabled,
    Map<String, Object?> stateContains = const <String, Object?>{},
  }) {
    final matches = where(
      id: id,
      role: role,
      label: label,
      labelContains: labelContains,
      value: value,
      action: action,
      focused: focused,
      selected: selected,
      enabled: enabled,
      stateContains: stateContains,
    ).toList(growable: false);
    if (matches.length == 1) return matches.single;
    final query = _queryDescription(
      id: id,
      role: role,
      label: label,
      labelContains: labelContains,
      value: value,
      action: action,
      focused: focused,
      selected: selected,
      enabled: enabled,
      stateContains: stateContains,
    );
    throw StateError(
      'Expected exactly one semantic inspection node, found '
      '${matches.length} for $query.\n\n${debugTree()}',
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'nodeCount': nodeCount,
    'focusedNodeId': focusedNodeId,
    'roleCounts': roleCounts,
    'actionCount': actionCount,
    'root': root.toJson(),
  };

  /// Like [toJson] but bounds the tree to at most [maxNodes] nodes — dropped
  /// subtrees carry `childrenTruncated` and the envelope carries `truncated:
  /// true`. For token-limited consumers (the MCP `get_ui` tool); the wire/serve
  /// path uses the unbounded [toJson]. `roleCounts`/`nodeCount` still describe
  /// the *full* tree so a consumer knows what it didn't see.
  /// [augment] is an optional per-node hook: its returned map (if any) is merged
  /// into that node's JSON. A generic extension point — the caller owns what it
  /// adds (e.g. the MCP server injects a normalized `valueSchema`); this keeps
  /// such consumer-specific fields out of the core node model while still
  /// respecting the budget walk.
  Map<String, Object?> toJsonCapped({
    required int maxNodes,
    Map<String, Object?>? Function(SemanticInspectionNode node)? augment,
  }) {
    final budget = _NodeBudget(maxNodes <= 1 ? 0 : maxNodes - 1);
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'nodeCount': nodeCount,
      if (nodeCount > maxNodes) 'truncated': true,
      'focusedNodeId': focusedNodeId,
      'roleCounts': roleCounts,
      'actionCount': actionCount,
      'root': root._toJsonCapped(budget, augment),
    };
  }

  /// Reconstructs a [SemanticTree] from this snapshot.
  ///
  /// The reconstructed tree mirrors the (already redacted) inspection view, so
  /// a consumer that presents it exposes exactly what the snapshot carries —
  /// sensitive values stay redacted. Used by the structured serve client to
  /// drive its accessible DOM presenter from a `SemanticsFrame`, so a served
  /// session stays screen-reader- and agent-readable without shipping the live
  /// widget tree.
  SemanticTree toSemanticTree() => SemanticTree(root: root.toSemanticNode());

  /// Returns a deterministic, redaction-aware tree summary for humans.
  ///
  /// Use [toJson] for protocol consumers. This string is intentionally optimized
  /// for failure messages, debug panels, and quick terminal output.
  String debugTree({bool includeState = true}) {
    final buffer = StringBuffer()
      ..write('SemanticInspectionSnapshot(')
      ..write('schemaVersion: ')
      ..write(schemaVersion)
      ..write(', nodeCount: ')
      ..write(nodeCount)
      ..write(', actionCount: ')
      ..write(actionCount)
      ..write(', focusedNodeId: ')
      ..write(focusedNodeId ?? 'none')
      ..write(', roleCounts: ')
      ..write(_debugMap(roleCounts))
      ..writeln(')');
    root._writeDebugTree(buffer, depth: 0, includeState: includeState);
    return buffer.toString().trimRight();
  }

  @override
  String toString() => debugTree();
}

/// Redacted, JSON-safe semantic node used by [SemanticInspectionSnapshot].
/// Mutable remaining-node budget threaded through
/// [SemanticInspectionNode._toJsonCapped].
class _NodeBudget {
  _NodeBudget(this.remaining);
  int remaining;
}

final class SemanticInspectionNode {
  /// Stable node JSON keys for semantic inspection schema v1.
  static const Set<String> stableJsonFields = <String>{
    'id',
    'role',
    'label',
    'value',
    'hint',
    'enabled',
    'focused',
    'selected',
    'checked',
    'expanded',
    'busy',
    'validationError',
    'bounds',
    'actions',
    'state',
    'children',
  };

  SemanticInspectionNode._({
    required this.id,
    required this.role,
    this.label,
    this.value,
    this.hint,
    required this.enabled,
    required this.focused,
    required this.selected,
    this.checked,
    this.expanded,
    required this.busy,
    this.validationError,
    this.bounds,
    required List<String> actions,
    required Map<String, Object?> state,
    required List<SemanticInspectionNode> children,
  }) : actions = List<String>.unmodifiable(actions),
       state = Map<String, Object?>.unmodifiable(state),
       children = List<SemanticInspectionNode>.unmodifiable(children);

  factory SemanticInspectionNode._fromSemanticNode(SemanticNode node) =>
      SemanticInspectionNode._redact(node, <SemanticInspectionNode>[
        for (final child in node.children)
          SemanticInspectionNode._fromSemanticNode(child),
      ]);

  /// Redacts one node's own fields WITHOUT recursing into children. The wire's
  /// O(changed) path needs a node's scalar form and its direct child ids, never
  /// the child subtrees; pairs with [flattenLiveNode].
  factory SemanticInspectionNode._fromSemanticNodeShallow(SemanticNode node) =>
      SemanticInspectionNode._redact(node, const <SemanticInspectionNode>[]);

  /// The one site that maps a live [SemanticNode] to its redacted, sanitized
  /// inspection form, adopting [children] as given — so the recursive
  /// ([_fromSemanticNode]) and shallow ([_fromSemanticNodeShallow])
  /// constructors cannot drift on the fields they share.
  factory SemanticInspectionNode._redact(
    SemanticNode node,
    List<SemanticInspectionNode> children,
  ) {
    final redacted = _redactsNode(node);
    return SemanticInspectionNode._(
      id: sanitizeForDisplay(node.id.value),
      role: node.role.name,
      label: node.label == null ? null : sanitizeForDisplay(node.label!),
      value: redacted ? '<redacted>' : _jsonValue(node.value),
      hint: node.hint == null ? null : sanitizeForDisplay(node.hint!),
      enabled: node.enabled,
      focused: node.focused,
      selected: node.selected,
      checked: node.checked,
      expanded: node.expanded,
      busy: node.busy,
      validationError: redacted
          ? (node.validationError == null ? null : '<redacted>')
          : (node.validationError == null
                ? null
                : sanitizeForDisplay(node.validationError!)),
      bounds: node.bounds,
      actions: [for (final action in node.actions) action.name]..sort(),
      state: _semanticStateToJson(node.state),
      children: children,
    );
  }

  /// The flat wire form — scalar fields plus sanitized `childIds` — of a single
  /// live [SemanticNode], redacting on demand without materializing its subtree.
  /// The O(changed) wire path flattens only the changed nodes through here; the
  /// result is byte-identical to flattening the node's full [_fromSemanticNode]
  /// form (the encoder's debug oracle asserts exactly this).
  @internal
  static Map<String, Object?> flattenLiveNode(SemanticNode node) {
    final json = SemanticInspectionNode._fromSemanticNodeShallow(
      node,
    ).toScalarJson(includeBounds: true);
    if (node.children.isNotEmpty) {
      json['childIds'] = <String>[
        for (final child in node.children) sanitizeForDisplay(child.id.value),
      ];
    }
    return json;
  }

  /// Parses a node from semantic inspection JSON.
  ///
  /// This constructor preserves the public v1 field contract while ignoring
  /// additive future fields. Redaction flags in [state] are re-applied during
  /// parsing so a consumer-created node cannot accidentally expose sensitive
  /// values when re-serialized.
  factory SemanticInspectionNode.fromJson(Map<String, Object?> json) {
    final id = _jsonString(json['id']);
    if (id == null || id.isEmpty) {
      throw const FormatException('Semantic inspection node is missing id.');
    }
    final role = _jsonString(json['role']);
    if (role == null || role.isEmpty) {
      throw const FormatException('Semantic inspection node is missing role.');
    }

    final state = _jsonSafeMap(json['state']);
    final redacted = _redactsStateMap(state);
    return SemanticInspectionNode._(
      id: sanitizeForDisplay(id),
      role: sanitizeForDisplay(role),
      label: _jsonSanitizedString(json['label']),
      value: redacted ? '<redacted>' : _jsonValue(json['value']),
      hint: _jsonSanitizedString(json['hint']),
      enabled: _jsonBool(json['enabled'], fallback: true),
      focused: json['focused'] == true,
      selected: json['selected'] == true,
      checked: _jsonNullableBool(json['checked']),
      expanded: _jsonNullableBool(json['expanded']),
      busy: json['busy'] == true,
      validationError: redacted && json['validationError'] != null
          ? '<redacted>'
          : _jsonSanitizedString(json['validationError']),
      bounds: _jsonCellRect(json['bounds']),
      actions: _jsonSortedStrings(json['actions']),
      state: redacted ? _redactSensitiveState(state) : state,
      children: _jsonNodeList(json['children']),
    );
  }

  final String id;
  final String role;
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
  final List<String> actions;
  final Map<String, Object?> state;
  final List<SemanticInspectionNode> children;

  Iterable<SemanticInspectionNode> get descendants sync* {
    for (final child in children) {
      yield child;
      yield* child.descendants;
    }
  }

  Iterable<SemanticInspectionNode> get selfAndDescendants sync* {
    yield this;
    yield* descendants;
  }

  Object? operator [](String key) => toJson()[key];

  Map<String, Object?> toJson() => <String, Object?>{
    ..._scalarJson(),
    if (children.isNotEmpty)
      'children': <Object?>[for (final child in children) child.toJson()],
  };

  /// This node's own fields, without children — the flat shape a consumer that
  /// *lists* matching nodes (e.g. an MCP `find_nodes`) wants, rather than the
  /// nested [toJson]. Computed by the same `_scalarJson` as [toJson], so the two
  /// can't drift on the fields they share; unlike [toJson], `includeBounds`
  /// defaults to false, so `bounds` is omitted unless asked for.
  Map<String, Object?> toScalarJson({bool includeBounds = false}) =>
      _scalarJson(includeBounds: includeBounds);

  /// This node's own fields without children — shared by [toJson] and the
  /// budgeted [_toJsonCapped].
  ///
  /// [includeBounds] / [dedupeValue] trim noise for token-limited agent
  /// consumers: an MCP agent dispatches by id, not pixels, so it doesn't need
  /// [bounds]; and a `value` that merely repeats `label` (a display node) is
  /// redundant. The wire/serve path keeps both (the accessible DOM mirror uses
  /// bounds), so these default to off only in the capped path.
  Map<String, Object?> _scalarJson({
    bool includeBounds = true,
    bool dedupeValue = false,
  }) => <String, Object?>{
    'id': id,
    'role': role,
    if (label != null) 'label': label,
    if (value != null && !(dedupeValue && value == label)) 'value': value,
    if (hint != null) 'hint': hint,
    'enabled': enabled,
    if (focused) 'focused': true,
    if (selected) 'selected': true,
    if (checked != null) 'checked': checked,
    if (expanded != null) 'expanded': expanded,
    if (busy) 'busy': true,
    if (validationError != null) 'validationError': validationError,
    if (includeBounds && bounds != null) 'bounds': _cellRectToJson(bounds!),
    if (actions.isNotEmpty) 'actions': actions,
    if (state.isNotEmpty) 'state': state,
  };

  /// Serializes this subtree depth-first, emitting at most [budget] more
  /// descendant nodes. A node whose children are dropped to stay within budget
  /// gets `childrenTruncated: <count>` so a consumer knows to drill in with a
  /// targeted query rather than assume it saw everything.
  Map<String, Object?> _toJsonCapped(
    _NodeBudget budget, [
    Map<String, Object?>? Function(SemanticInspectionNode node)? augment,
  ]) {
    final json = _scalarJson(includeBounds: false, dedupeValue: true);
    final extra = augment?.call(this);
    if (extra != null) json.addAll(extra);
    if (children.isEmpty) return json;
    final emitted = <Object?>[];
    for (final child in children) {
      if (budget.remaining <= 0) break;
      budget.remaining--;
      emitted.add(child._toJsonCapped(budget, augment));
    }
    if (emitted.isNotEmpty) json['children'] = emitted;
    final dropped = children.length - emitted.length;
    if (dropped > 0) json['childrenTruncated'] = dropped;
    return json;
  }

  /// Reconstructs a [SemanticNode] from this inspection node, recursively.
  ///
  /// Role and action names are matched back to their enums; an unrecognized
  /// role (e.g. one added by a newer server) falls back to [SemanticRole.text]
  /// and unrecognized actions are dropped, so an additive schema never crashes
  /// an older consumer. See [SemanticInspectionSnapshot.toSemanticTree].
  SemanticNode toSemanticNode() => SemanticNode(
    id: SemanticNodeId(id),
    role: _semanticRoleByName(role),
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
    bounds: bounds,
    actions: <SemanticAction>{
      for (final name in actions) ?_semanticActionByName(name),
    },
    children: <SemanticNode>[
      for (final child in children) child.toSemanticNode(),
    ],
    state: SemanticState(Map<String, Object?>.of(state)),
  );

  String _debugLine({required bool includeState}) {
    final parts = <String>[
      '$role#$id',
      if (label != null) 'label:${_debugValue(label)}',
      if (value != null) 'value:${_debugValue(value)}',
      if (hint != null) 'hint:${_debugValue(hint)}',
      if (!enabled) 'disabled',
      if (focused) 'focused',
      if (selected) 'selected',
      if (checked != null) 'checked:$checked',
      if (expanded != null) 'expanded:$expanded',
      if (busy) 'busy',
      if (validationError != null)
        'validationError:${_debugValue(validationError)}',
      if (actions.isNotEmpty) 'actions:[${actions.join(', ')}]',
      if (includeState && state.isNotEmpty) 'state:${_debugMap(state)}',
    ];
    return parts.join(' ');
  }

  void _writeDebugTree(
    StringBuffer buffer, {
    required int depth,
    required bool includeState,
  }) {
    buffer
      ..write(_debugIndent(depth))
      ..writeln(_debugLine(includeState: includeState));
    for (final child in children) {
      child._writeDebugTree(
        buffer,
        depth: depth + 1,
        includeState: includeState,
      );
    }
  }

  @override
  String toString() => _debugLine(includeState: true);

  bool _matches({
    String? id,
    String? role,
    String? label,
    String? labelContains,
    Object? value,
    String? action,
    bool? focused,
    bool? selected,
    bool? enabled,
    required Map<String, Object?> stateContains,
  }) {
    if (id != null && this.id != id) return false;
    if (role != null && this.role != role) return false;
    if (label != null && this.label != label) return false;
    if (labelContains != null &&
        !(this.label ?? '').toLowerCase().contains(
          labelContains.toLowerCase(),
        )) {
      return false;
    }
    if (value != null && this.value != value) return false;
    if (action != null && !actions.contains(action)) return false;
    if (focused != null && this.focused != focused) return false;
    if (selected != null && this.selected != selected) return false;
    if (enabled != null && this.enabled != enabled) return false;
    for (final entry in stateContains.entries) {
      if (!state.containsKey(entry.key) || state[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}

/// Convenience conversion from a live semantic tree to the inspection protocol.
extension SemanticTreeInspection on SemanticTree {
  SemanticInspectionSnapshot toInspectionSnapshot({
    int schemaVersion = SemanticInspectionSnapshot.currentSchemaVersion,
  }) {
    return SemanticInspectionSnapshot.fromTree(
      this,
      schemaVersion: schemaVersion,
    );
  }

  Map<String, Object?> toInspectionJson({
    int schemaVersion = SemanticInspectionSnapshot.currentSchemaVersion,
  }) {
    return toInspectionSnapshot(schemaVersion: schemaVersion).toJson();
  }

  /// Returns a deterministic, redaction-aware semantic tree summary for
  /// humans. This is the quickest way to inspect what tests, accessibility,
  /// command discovery, and debug capture can see.
  String debugTree({bool includeState = true}) {
    return toInspectionSnapshot().debugTree(includeState: includeState);
  }
}

String _queryDescription({
  required String? id,
  required String? role,
  required String? label,
  required String? labelContains,
  required Object? value,
  required String? action,
  required bool? focused,
  required bool? selected,
  required bool? enabled,
  required Map<String, Object?> stateContains,
}) {
  final parts = <String>[
    if (id != null) 'id:${_debugValue(id)}',
    if (role != null) 'role:${_debugValue(role)}',
    if (label != null) 'label:${_debugValue(label)}',
    if (labelContains != null) 'labelContains:${_debugValue(labelContains)}',
    if (value != null) 'value:${_debugValue(value)}',
    if (action != null) 'action:${_debugValue(action)}',
    if (focused != null) 'focused:$focused',
    if (selected != null) 'selected:$selected',
    if (enabled != null) 'enabled:$enabled',
    if (stateContains.isNotEmpty) 'stateContains:${_debugMap(stateContains)}',
  ];
  return parts.isEmpty ? 'unfiltered query' : parts.join(' ');
}

String _debugMap(Map<Object?, Object?> map) {
  if (map.isEmpty) return '{}';
  final entries = [
    for (final entry in map.entries)
      MapEntry(entry.key.toString(), entry.value),
  ]..sort((a, b) => a.key.compareTo(b.key));
  final parts = [
    for (final entry in entries) '${entry.key}: ${_debugValue(entry.value)}',
  ];
  return '{${parts.join(', ')}}';
}

String _debugIndent(int depth) => ''.padLeft(depth * 2);

String _debugValue(Object? value) {
  return switch (value) {
    null => 'null',
    String() => '"${_escapeDebugString(value)}"',
    num() || bool() => value.toString(),
    Iterable<Object?>() =>
      '[${[for (final item in value) _debugValue(item)].join(', ')}]',
    Map<Object?, Object?>() => _debugMap(value),
    _ => _debugValue(value.toString()),
  };
}

String _escapeDebugString(String value) {
  return value
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
}

bool _redactsNode(SemanticNode node) {
  return node.state.redactedValue == true ||
      node.state.obscureText == true ||
      node.state.clipboardRedacted == true;
}

Map<String, Object?> _semanticStateToJson(SemanticState state) {
  final redacted =
      state.redactedValue == true ||
      state.obscureText == true ||
      state.clipboardRedacted == true;
  return <String, Object?>{
    for (final entry in state.values.entries)
      sanitizeForDisplay(entry.key): redacted && _looksSensitive(entry.key)
          ? '<redacted>'
          : _jsonValue(entry.value),
  };
}

bool _redactsStateMap(Map<String, Object?> state) {
  return state['redactedValue'] == true ||
      state['obscureText'] == true ||
      state['clipboardRedacted'] == true;
}

Map<String, Object?> _redactSensitiveState(Map<String, Object?> state) {
  return <String, Object?>{
    for (final entry in state.entries)
      entry.key: _looksSensitive(entry.key) ? '<redacted>' : entry.value,
  };
}

bool _looksSensitive(String key) {
  final lower = key.toLowerCase();
  if (lower == 'redactedvalue' ||
      lower == 'obscuretext' ||
      lower == 'clipboardredacted') {
    return false;
  }
  return lower.contains('value') ||
      lower.contains('text') ||
      lower.contains('secret') ||
      lower.contains('password') ||
      lower.contains('token') ||
      lower.contains('query');
}

Object? _jsonValue(Object? value) {
  return switch (value) {
    null => null,
    String() => sanitizeForDisplay(value),
    num() || bool() => value,
    Iterable<Object?>() => <Object?>[
      for (final item in value) _jsonValue(item),
    ],
    Map<Object?, Object?>() => <String, Object?>{
      for (final entry in value.entries)
        sanitizeForDisplay(entry.key.toString()): _jsonValue(entry.value),
    },
    _ => sanitizeForDisplay(value.toString()),
  };
}

Map<String, Object?> _cellRectToJson(CellRect rect) {
  return <String, Object?>{
    'left': rect.left,
    'top': rect.top,
    'width': rect.size.cols,
    'height': rect.size.rows,
  };
}

CellRect? _jsonCellRect(Object? value) {
  final map = _jsonMap(value);
  if (map == null) return null;
  final left = map['left'];
  final top = map['top'];
  final width = map['width'];
  final height = map['height'];
  if (left is! int || top is! int || width is! int || height is! int) {
    return null;
  }
  if (width < 0 || height < 0) return null;
  return CellRect.fromLTWH(left, top, width, height);
}

Map<String, Object?>? _jsonMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  return null;
}

Map<String, Object?> _jsonSafeMap(Object? value) {
  final map = _jsonMap(value);
  if (map == null) return const <String, Object?>{};
  return <String, Object?>{
    for (final entry in map.entries)
      sanitizeForDisplay(entry.key): _jsonValue(entry.value),
  };
}

String? _jsonString(Object? value) => value is String ? value : null;

String? _jsonSanitizedString(Object? value) {
  return value is String ? sanitizeForDisplay(value) : null;
}

int _jsonInt(Object? value, {required int fallback}) {
  return value is int ? value : fallback;
}

bool _jsonBool(Object? value, {required bool fallback}) {
  return value is bool ? value : fallback;
}

bool? _jsonNullableBool(Object? value) => value is bool ? value : null;

List<String> _jsonSortedStrings(Object? value) {
  if (value is! Iterable) return const <String>[];
  return (value.whereType<String>().map(sanitizeForDisplay).toSet().toList()
    ..sort());
}

List<SemanticInspectionNode> _jsonNodeList(Object? value) {
  if (value is! Iterable) return const <SemanticInspectionNode>[];
  final nodes = <SemanticInspectionNode>[];
  for (final item in value) {
    final map = _jsonMap(item);
    if (map != null) nodes.add(SemanticInspectionNode.fromJson(map));
  }
  return nodes;
}

/// Matches a serialized role name back to its enum. An unknown name (a role
/// added by a newer producer) degrades to [SemanticRole.text] rather than
/// throwing, so [SemanticInspectionNode.toSemanticNode] tolerates an additive
/// schema.
SemanticRole _semanticRoleByName(String name) {
  for (final role in SemanticRole.values) {
    if (role.name == name) return role;
  }
  return SemanticRole.text;
}

/// Matches a serialized action name back to its enum, or null if unrecognized
/// (dropped by [SemanticInspectionNode.toSemanticNode]).
SemanticAction? _semanticActionByName(String name) {
  for (final action in SemanticAction.values) {
    if (action.name == name) return action;
  }
  return null;
}
