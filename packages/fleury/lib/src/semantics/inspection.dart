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

  Iterable<SemanticInspectionNode> get nodes => root.selfAndDescendants;

  SemanticInspectionNode? nodeById(String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  Iterable<SemanticInspectionNode> where({
    String? id,
    String? role,
    String? label,
    Object? value,
    String? action,
    bool? focused,
    bool? selected,
    bool? enabled,
    Map<String, Object?> stateContains = const <String, Object?>{},
  }) {
    return nodes.where(
      (node) => node._matches(
        id: id,
        role: role,
        label: label,
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

  /// Alias for [debugTree] kept for call sites that prefer a string-conversion
  /// name. Prefer [debugTree] in new tests and diagnostics.
  String toDebugString({bool includeState = true}) {
    return debugTree(includeState: includeState);
  }

  @override
  String toString() => toDebugString();
}

/// Redacted, JSON-safe semantic node used by [SemanticInspectionSnapshot].
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

  factory SemanticInspectionNode._fromSemanticNode(SemanticNode node) {
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
      children: [
        for (final child in node.children)
          SemanticInspectionNode._fromSemanticNode(child),
      ],
    );
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
    'id': id,
    'role': role,
    if (label != null) 'label': label,
    if (value != null) 'value': value,
    if (hint != null) 'hint': hint,
    'enabled': enabled,
    if (focused) 'focused': true,
    if (selected) 'selected': true,
    if (checked != null) 'checked': checked,
    if (expanded != null) 'expanded': expanded,
    if (busy) 'busy': true,
    if (validationError != null) 'validationError': validationError,
    if (bounds != null) 'bounds': _cellRectToJson(bounds!),
    if (actions.isNotEmpty) 'actions': actions,
    if (state.isNotEmpty) 'state': state,
    if (children.isNotEmpty)
      'children': <Object?>[for (final child in children) child.toJson()],
  };

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
