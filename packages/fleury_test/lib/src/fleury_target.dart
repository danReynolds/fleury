part of 'fleury_tester.dart';

/// A reusable query for a widget scope or a published semantic control.
///
/// Type/key queries count widgets and establish scopes, including custom
/// composites without their own semantic node. Select a semantic child before
/// invoking actions or reading [snapshot]. Semantic queries match exact roles,
/// labels (case-sensitive), and IDs. They do not use the browser's ARIA mapping.
///
/// Every operation resolves afresh. Single-control operations and parent scopes
/// reject zero or multiple matches. Queries never choose the first enabled node,
/// retry, scroll, or reveal hidden routes. Popups outside a widget subtree are
/// selected from the tester root.
final class FleuryTarget {
  FleuryTarget._(
    this._tester, {
    FleuryTarget? parent,
    Type? type,
    Key? key,
    support.SemanticRole? role,
    String? label,
    support.SemanticNodeId? id,
    bool textField = false,
  }) : _parent = parent,
       _type = type,
       _key = key,
       _role = role,
       _label = label,
       _id = id,
       _textField = textField;

  static FleuryTarget _create(
    FleuryTester tester,
    FleuryTarget? parent,
    Type? type,
    Key? key,
    support.SemanticRole? role,
    String? label,
    support.SemanticNodeId? id,
  ) {
    final structural = type != null || key != null;
    final semantic = role != null || label != null || id != null;
    if (!structural && !semantic) {
      throw ArgumentError('target requires a type, key, role, label, or id.');
    }
    if (structural) {
      if (parent != null && !parent._structural) {
        throw ArgumentError(
          'Widget queries need a root or widget scope. '
          'Use a new tester.target(type: ...) query.',
        );
      }
      final scope = FleuryTarget._(
        tester,
        parent: parent,
        type: type,
        key: key,
      );
      if (!semantic) return scope;
      parent = scope;
    }
    return FleuryTarget._(
      tester,
      parent: parent,
      role: role,
      label: label,
      id: id,
    );
  }

  final FleuryTester _tester;
  final FleuryTarget? _parent;
  final Type? _type;
  final Key? _key;
  final support.SemanticRole? _role;
  final String? _label;
  final support.SemanticNodeId? _id;
  final bool _textField;

  bool get _structural => _type != null || _key != null;

  /// Narrows to descendants of exactly one scope. Type and key combine with
  /// AND; combining them with semantic criteria is shorthand for two queries.
  FleuryTarget target({
    Type? type,
    Key? key,
    support.SemanticRole? role,
    String? label,
    support.SemanticNodeId? id,
  }) => _create(_tester, this, type, key, role, label, id);

  FleuryTarget button(String label) =>
      target(role: support.SemanticRole.button, label: label);

  /// Matches text-editable meaning, independently of availability.
  FleuryTarget field(String label) =>
      FleuryTarget._(_tester, parent: this, label: label, textField: true);

  FleuryTarget checkbox(String label) =>
      target(role: support.SemanticRole.checkbox, label: label);

  /// Current number of widget matches or published semantic-node matches.
  /// Parents must still match exactly once, including when this count is zero.
  int get count => _resolve().length;

  /// Exactly one current semantic node. Type/key-only scopes have no implicit
  /// semantic snapshot; select a control inside the scope first.
  support.SemanticNode get snapshot {
    _requireSemantic();
    final result = _resolve();
    return _singleNode(result);
  }

  /// All current semantic matches. Retained snapshots are historical values.
  List<support.SemanticNode> get snapshots {
    _requireSemantic();
    return List.unmodifiable(_resolve().nodes);
  }

  _TargetResolution _resolve([support.SemanticTree? tree]) {
    if (tree == null) {
      try {
        tree = _tester.semantics();
      } on StateError catch (error) {
        _fail(error.message.toString());
      }
    }
    final parent = _parent;
    Element? widgetScope;
    support.SemanticNode? semanticScope;
    if (parent != null) {
      final scope = parent._resolve(tree);
      parent._requireOne(scope);
      if (parent._structural) {
        widgetScope = scope.elements.single;
      } else {
        semanticScope = scope.nodes.single;
      }
    }
    if (_structural) {
      final root = widgetScope ?? _tester.root!;
      final elements = <Element>[];
      void visit(Element element) {
        if ((_type == null || element.widget.runtimeType == _type) &&
            (_key == null || element.widget.key == _key)) {
          elements.add(element);
        }
        element.visitChildren(visit);
      }

      if (widgetScope == null) {
        visit(root);
      } else {
        root.visitChildren(visit);
      }
      return _TargetResolution(tree, elements: elements);
    }
    final candidates = semanticScope?.descendants ?? tree.nodes;
    final idCounts = <support.SemanticNodeId, int>{};
    if (widgetScope != null) {
      for (final node in tree.nodes) {
        idCounts.update(node.id, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final nodes = <support.SemanticNode>[];
    for (final node in candidates) {
      if ((_role != null && node.role != _role) ||
          (_label != null && node.label != _label) ||
          (_id != null && node.id != _id) ||
          (_textField && !_isTextField(node))) {
        continue;
      }
      if (widgetScope != null) {
        // The artificial tree root has no widget owner. ExcludeSemantics also
        // publishes ownerless coverage markers, not queryable child controls.
        if (identical(node, tree.root) ||
            node.state['semanticExcluded'] == true) {
          continue;
        }
        if (idCounts[node.id] != 1) {
          _fail(
            'Cannot resolve widget scope: ambiguous contributor ownership for '
            'semantic id "${node.id.value}". Each published node needs a '
            'unique semantic id.',
            tree: tree,
            node: node,
          );
        }
        final owner = tree.elementById(node.id);
        if (owner == null) {
          _fail(
            'Cannot resolve widget scope: missing contributor ownership for '
            'semantic id "${node.id.value}". Query this published node from '
            'the tester root instead.',
            tree: tree,
            node: node,
          );
        }
        if (!_inside(owner, widgetScope)) continue;
      }
      nodes.add(node);
    }
    return _TargetResolution(tree, nodes: nodes);
  }

  static bool _inside(Element? element, Element scope) {
    while (element != null) {
      if (identical(element, scope)) return true;
      element = element.elementParent;
    }
    return false;
  }

  static bool _isTextField(support.SemanticNode node) =>
      node.state.textEditable ??
      (node.role == support.SemanticRole.textField ||
          node.role == support.SemanticRole.textArea);

  void _requireSemantic() {
    if (_structural) {
      _fail(
        'This query is a widget scope. Select a semantic control inside it '
        'before reading semantic state or performing an action. '
        'Use count for widget matches or existing finders for widget inspection.',
      );
    }
  }

  void _requireOne(_TargetResolution result) {
    if (result.length != 1) {
      _fail(
        'Expected exactly one ${_structural ? 'widget' : 'semantic node'}, '
        'found ${result.length}. Matching is exact and case-sensitive.',
        tree: result.tree,
      );
    }
  }

  support.SemanticNode _singleNode(_TargetResolution result) {
    _requireOne(result);
    return result.nodes.single;
  }

  void _requireAction(
    support.SemanticNode node,
    support.SemanticAction action,
    support.SemanticTree tree,
  ) {
    if (!node.enabled) {
      _fail(
        'Cannot ${action.name}: target is disabled.',
        tree: tree,
        node: node,
      );
    }
    if (!node.actions.contains(action)) {
      _fail('Unsupported action ${action.name}.', tree: tree, node: node);
    }
  }

  Future<void> _dispatch(
    support.SemanticNode node,
    support.SemanticAction action, {
    Object? payload,
    bool frame = true,
  }) async {
    final result = await _tester.invokeSemanticAction(
      action,
      id: node.id,
      payload: payload,
      allowFailure: true,
    );
    if (!result.completed) {
      // User callbacks can include their input in thrown messages. Never
      // include handler messages or payloads in this facade's diagnostics.
      _fail(
        '${action.name} did not complete: ${result.status.name}'
        '${result.error == null ? '' : ' (${result.error.runtimeType})'}.',
        node: result.node ?? node,
      );
    }
    if (frame) _tester.pump();
  }

  /// Invokes an advertised semantic action once, awaits its handler, and
  /// completes one frame. No input simulation, retries, time advance, or settle.
  /// A handler's returned Future is awaited; separately started work may remain
  /// pending. Completion does not imply an application accepted the request.
  Future<void> perform(support.SemanticAction action, {Object? payload}) async {
    _requireSemantic();
    if (payload != null && action != support.SemanticAction.setValue) {
      throw ArgumentError('Only setValue accepts a payload.');
    }
    final result = _resolve();
    final node = _singleNode(result);
    _requireAction(node, action, result.tree);
    await _dispatch(node, action, payload: payload);
  }

  /// Requests a value update. Widgets may normalize, clamp, or reject it;
  /// assert the observed outcome. Does not focus the control.
  Future<void> setValue(Object? value) =>
      perform(support.SemanticAction.setValue, payload: value);

  /// Performs the control's logical primary action, not a mouse or key press.
  Future<void> press() => perform(support.SemanticAction.activate);
  Future<void> open() => perform(support.SemanticAction.open);
  Future<void> close() => perform(support.SemanticAction.close);
  Future<void> select() => perform(support.SemanticAction.select);
  Future<void> submit() => perform(support.SemanticAction.submit);
  Future<void> copy() => perform(support.SemanticAction.copy);

  /// Requests and verifies focus on the same live semantic control.
  Future<void> focus() async {
    _requireSemantic();
    final before = _resolve();
    final node = _singleNode(before);
    _requireAction(node, support.SemanticAction.focus, before.tree);
    await _dispatch(node, support.SemanticAction.focus);
    final current = _continued(before, node);
    if (!current.focused) {
      _fail('Focus was refused.', node: current);
    }
  }

  support.SemanticNode _continued(
    _TargetResolution before,
    support.SemanticNode node,
  ) {
    final after = _resolve();
    final current = _singleNode(after);
    if (current.id != node.id ||
        current.role != node.role ||
        current.label != node.label ||
        !identical(
          before.tree.elementById(node.id),
          after.tree.elementById(current.id),
        )) {
      _fail(
        'Target was replaced during the operation. No input was sent to '
        'the replacement. Resolve it in a separate operation.',
        tree: after.tree,
        node: current,
      );
    }
    // Action tokens also encode capabilities. A live control may legitimately
    // remove focus after gaining it, or disable itself after being checked.
    // The contributing element and semantic identity establish continuity;
    // callers validate the capabilities needed for their next step separately.
    return current;
  }

  /// Focuses and requests text replacement through the normal semantic handler.
  /// Requires text-editable meaning, enabled/non-read-only state, and focus and
  /// setValue capabilities. Filtering/validation still apply. Does not simulate
  /// typing, paste, undo, or composition. Never logs the replacement text.
  Future<void> fill(String text) async {
    _requireSemantic();
    final before = _resolve();
    final node = _singleNode(before);
    if (!_isTextField(node) || node.state.readOnly == true) {
      _fail(
        'fill requires a text-editable, non-read-only control.',
        tree: before.tree,
        node: node,
      );
    }
    _requireAction(node, support.SemanticAction.focus, before.tree);
    _requireAction(node, support.SemanticAction.setValue, before.tree);
    await _dispatch(node, support.SemanticAction.focus, frame: false);
    final focused = _continued(before, node);
    if (!focused.focused) {
      _fail('Focus was refused; text was not sent.', node: focused);
    }
    if (!_isTextField(focused) || focused.state.readOnly == true) {
      _fail('Target is no longer text-editable after focus.', node: focused);
    }
    _requireAction(
      focused,
      support.SemanticAction.setValue,
      _tester.semantics(),
    );
    await _dispatch(focused, support.SemanticAction.setValue, payload: text);
  }

  /// Ensures checked state. Already-correct state succeeds without dispatch,
  /// including on a disabled control. Otherwise verifies the resulting state.
  Future<void> check() => _setChecked(true);
  Future<void> uncheck() => _setChecked(false);

  Future<void> _setChecked(bool value) async {
    _requireSemantic();
    final result = _resolve();
    final node = _singleNode(result);
    if (node.checked == null) _fail('Target has no checked state.', node: node);
    if (node.checked == value) return;
    _requireAction(node, support.SemanticAction.setValue, result.tree);
    await _dispatch(node, support.SemanticAction.setValue, payload: value);
    final current = _continued(result, node);
    if (current.checked != value) {
      _fail(
        'Requested checked=$value, observed checked=${current.checked}. '
        'A controlled widget needs its owner to apply the change. '
        'For callback tests use setValue and assert the callback.',
        node: current,
      );
    }
  }

  Never _fail(
    String message, {
    support.SemanticTree? tree,
    support.SemanticNode? node,
  }) {
    final details = <String>[
      '$this: $message',
      if (node != null)
        'Matched ${node.role.name}; enabled=${node.enabled}; '
            'actions=[${node.actions.map((action) => action.name).join(', ')}].',
      if (tree != null)
        ...tree.debugTree(includeState: false).split('\n').take(50),
    ];
    throw pkg_test.TestFailure(details.join('\n'));
  }

  @override
  String toString() {
    final parts = [
      if (_type != null) 'type: $_type',
      if (_key != null) 'key: $_key',
      if (_role != null) 'role: ${_role.name}',
      if (_textField) 'text-editable field',
      if (_label != null) 'label: "$_label"',
      if (_id != null) 'id: ${_id.value}',
    ];
    return '${_parent ?? 'tester'}.target(${parts.join(', ')})';
  }
}

final class _TargetResolution {
  _TargetResolution(
    this.tree, {
    this.elements = const [],
    this.nodes = const [],
  });
  final support.SemanticTree tree;
  final List<Element> elements;
  final List<support.SemanticNode> nodes;
  int get length => elements.length + nodes.length;
}
