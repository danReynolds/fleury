import 'dart:js_interop';

import 'package:fleury/fleury_host.dart';
import 'package:web/web.dart' as web;

import 'semantic_presenter.dart';

/// Projects Fleury semantics into a hidden-but-accessible DOM tree.
///
/// This is the browser accessibility backstop for the retained DOM renderer.
/// It consumes a full [SemanticTree] snapshot today, while retaining DOM
/// elements by semantic id so stable nodes do not churn every frame. Retained
/// semantic ownership remains separate Phase 4 work behind the same
/// [SemanticFramePresenter] boundary.
final class SemanticDomPresenter
    implements SemanticFramePresenter, SemanticActionRequestSink {
  SemanticDomPresenter({required web.Element root, web.Document? document})
    : _root = root,
      _document = document ?? web.document {
    _configureRoot();
  }

  final web.Element _root;
  final web.Document _document;
  final Map<String, web.Element> _elementsById = {};
  final Map<String, Map<String, String>> _attributesById = {};
  final Map<String, String> _ownTextById = {};
  final Map<String, web.Text> _textNodesById = {};
  final Map<String, JSFunction> _clickListenersById = {};
  SemanticActionRequestHandler? _onSemanticActionRequest;

  web.Element get rootElement => _root;

  @override
  set onSemanticActionRequest(SemanticActionRequestHandler? handler) {
    _onSemanticActionRequest = handler;
  }

  @override
  SemanticPresentationStats present(
    SemanticTree tree, {
    SemanticTreeUpdate? update,
  }) {
    if (update != null && !update.hasChanges && _elementsById.isNotEmpty) {
      return SemanticPresentationStats.retained(nodeCount: tree.nodeCount);
    }
    if (update != null && _canPresentIncrementally(tree, update)) {
      return _presentIncremental(tree, update);
    }
    final stats = _SemanticDomMutationStats();
    final liveIds = <String>{};
    final rootElement = _nodeElement(tree.root, liveIds, stats);
    _root.textContent = '';
    _root.appendChild(rootElement);
    _sweepDetached(liveIds);
    return stats.toPresentationStats(update);
  }

  @override
  Future<void> dispose() async {
    _onSemanticActionRequest = null;
    _root.textContent = '';
    for (final entry in _clickListenersById.entries) {
      _elementsById[entry.key]?.removeEventListener('click', entry.value);
    }
    _elementsById.clear();
    _attributesById.clear();
    _ownTextById.clear();
    _textNodesById.clear();
    _clickListenersById.clear();
  }

  void _configureRoot() {
    _root.className = 'fleury-semantics';
    _root.removeAttribute('aria-hidden');
    _root.setAttribute('data-fleury-semantic-root', 'true');
    _root.setAttribute('style', _rootStyle);
  }

  web.Element _nodeElement(
    SemanticNode node,
    Set<String> liveIds,
    _SemanticDomMutationStats stats,
  ) {
    stats.nodeCount += 1;
    final id = node.id.value;
    liveIds.add(id);
    final element = _elementFor(node, stats);
    element.className = 'fleury-semantic-node';
    final valueText = _valueText(node.value);
    _applyAttributes(
      id,
      element,
      _attributesFor(node: node, valueText: valueText),
      stats,
    );
    _applyNativeControlAttributes(element, node.role, valueText);

    if (_allowsOwnText(node.role) || _allowsChildElements(node.role)) {
      element.textContent = '';
      _ownTextById[id] = '';
      _textNodesById.remove(id);
    }
    final ownText = _allowsOwnText(node.role)
        ? _ownText(node, valueText)
        : null;
    if (ownText != null && ownText.isNotEmpty) {
      _setOwnText(id, element, ownText);
    }
    if (_allowsChildElements(node.role)) {
      for (final child in node.children) {
        element.appendChild(_nodeElement(child, liveIds, stats));
      }
    }
    return element;
  }

  bool _canPresentIncrementally(SemanticTree tree, SemanticTreeUpdate update) {
    if (_elementsById.isEmpty) return false;
    if (update.added.isNotEmpty || update.removed.isNotEmpty) return false;
    if (update.updated.isEmpty) return false;

    if (update.previous == null) return false;
    final previousNodes = update.previousNodesById;
    final nextNodes = update.nextNodesById;
    for (final id in update.updated) {
      final previousNode = previousNodes[id];
      final nextNode = nextNodes[id];
      if (previousNode == null || nextNode == null) return false;
      if (!_elementsById.containsKey(id.value)) return false;
      if (_tagFor(previousNode.role) != _tagFor(nextNode.role)) return false;
      if (!_hasSameChildOrder(previousNode, nextNode)) return false;
      if (nextNode.children.isNotEmpty) {
        final previousText = _ownText(
          previousNode,
          _valueText(previousNode.value),
        );
        final nextText = _ownText(nextNode, _valueText(nextNode.value));
        if (previousText != nextText) return false;
      }
    }
    return true;
  }

  SemanticPresentationStats _presentIncremental(
    SemanticTree tree,
    SemanticTreeUpdate update,
  ) {
    final stats = _SemanticDomMutationStats()
      ..nodeCount = update.nextNodesById.length;
    final nextNodes = update.nextNodesById;
    for (final id in update.updated) {
      final node = nextNodes[id]!;
      final element = _elementsById[id.value]!;
      stats.reusedElementCount += 1;
      _updateNodeElement(node, element, stats);
    }
    return stats.toPresentationStats(update);
  }

  void _updateNodeElement(
    SemanticNode node,
    web.Element element,
    _SemanticDomMutationStats stats,
  ) {
    element.className = 'fleury-semantic-node';
    final valueText = _valueText(node.value);
    _applyAttributes(
      node.id.value,
      element,
      _attributesFor(node: node, valueText: valueText),
      stats,
    );
    _applyNativeControlAttributes(element, node.role, valueText);
    if (node.children.isEmpty || !_allowsChildElements(node.role)) {
      _replaceOwnText(node.id.value, element, node, valueText);
    }
  }

  web.Element _elementFor(SemanticNode node, _SemanticDomMutationStats stats) {
    final id = node.id.value;
    final tag = _tagFor(node.role);
    final existing = _elementsById[id];
    if (existing != null && existing.localName == tag) {
      stats.reusedElementCount += 1;
      return existing;
    }
    if (existing != null) _removeActionListener(id, existing);
    final element = _document.createElement(tag);
    _elementsById[id] = element;
    _attributesById.remove(id);
    _ownTextById.remove(id);
    _textNodesById.remove(id);
    _addActionListener(id, element);
    if (existing == null) {
      stats.createdElementCount += 1;
    } else {
      stats.replacedElementCount += 1;
    }
    return element;
  }

  Map<String, String> _attributesFor({
    required SemanticNode node,
    required String? valueText,
  }) {
    final attributes = <String, String>{
      'data-fleury-semantic-id': node.id.value,
      'data-fleury-semantic-role': node.role.name,
    };
    final ariaRole = _ariaRoleFor(node.role);
    if (ariaRole != null) attributes['role'] = ariaRole;
    final label = node.label;
    if (_shouldExposeLabelAttribute(node) &&
        label != null &&
        label.isNotEmpty) {
      attributes['aria-label'] = label;
    }
    final hint = node.hint;
    if (hint != null && hint.isNotEmpty) {
      attributes['aria-description'] = hint;
    }
    if (_shouldExposeValueAttribute(node) &&
        valueText != null &&
        valueText.isNotEmpty) {
      attributes['data-fleury-value'] = valueText;
    }
    final bounds = node.bounds;
    if (bounds != null) {
      attributes['data-fleury-bounds-left'] = '${bounds.left}';
      attributes['data-fleury-bounds-top'] = '${bounds.top}';
      attributes['data-fleury-bounds-width'] = '${bounds.size.cols}';
      attributes['data-fleury-bounds-height'] = '${bounds.size.rows}';
    }

    if (!node.enabled) attributes['aria-disabled'] = 'true';
    if (node.focused) {
      attributes['data-fleury-focused'] = 'true';
    }
    if (node.selected) attributes['aria-selected'] = 'true';
    final checked = node.checked;
    if (checked != null) attributes['aria-checked'] = '$checked';
    final expanded = node.expanded;
    if (expanded != null) attributes['aria-expanded'] = '$expanded';
    if (node.busy) attributes['aria-busy'] = 'true';
    if (node.validationError != null) {
      attributes['aria-invalid'] = 'true';
      attributes['data-fleury-validation-error'] = node.validationError!;
    }
    if (node.role == SemanticRole.textArea) {
      attributes['aria-multiline'] = 'true';
    }
    if (node.state.readOnly == true) {
      attributes['aria-readonly'] = 'true';
    }
    if (node.actions.isNotEmpty) {
      final actions = node.actions.map((action) => action.name).toList()
        ..sort();
      attributes['data-fleury-actions'] = actions.join(' ');
      attributes['data-fleury-primary-action'] = _primaryActionFor(
        node.actions,
      ).name;
    }
    _addLinkAttributes(attributes, node);
    if (_isNonTabbableMirror(node)) {
      attributes['tabindex'] = '-1';
    }
    _addLiveRegionAttributes(attributes, node.role);
    _addNativeControlAttributes(attributes, node.role);
    return attributes;
  }

  void _applyAttributes(
    String id,
    web.Element element,
    Map<String, String> attributes,
    _SemanticDomMutationStats stats,
  ) {
    final previous = _attributesById[id] ?? const <String, String>{};
    for (final name in previous.keys) {
      if (!attributes.containsKey(name)) {
        element.removeAttribute(name);
        stats.attributesRemovedCount += 1;
      }
    }
    for (final entry in attributes.entries) {
      if (previous[entry.key] != entry.value) {
        element.setAttribute(entry.key, entry.value);
        stats.attributesSetCount += 1;
      }
    }
    _attributesById[id] = Map<String, String>.unmodifiable(attributes);
  }

  void _sweepDetached(Set<String> liveIds) {
    final staleIds = [
      for (final id in _elementsById.keys)
        if (!liveIds.contains(id)) id,
    ];
    for (final id in staleIds) {
      final element = _elementsById.remove(id);
      if (element != null) _removeActionListener(id, element);
      _attributesById.remove(id);
      _ownTextById.remove(id);
      _textNodesById.remove(id);
    }
  }

  void _addActionListener(String id, web.Element element) {
    final callback = ((web.Event event) {
      if (element.getAttribute('aria-disabled') == 'true') {
        event.preventDefault();
        event.stopPropagation();
        return;
      }
      final actionName = element.getAttribute('data-fleury-primary-action');
      if (actionName == null) return;
      final action = _semanticActionByName(actionName);
      if (action == null) return;
      event.preventDefault();
      event.stopPropagation();
      _onSemanticActionRequest?.call(SemanticNodeId(id), action);
    }).toJS;
    element.addEventListener('click', callback);
    _clickListenersById[id] = callback;
  }

  void _removeActionListener(String id, web.Element element) {
    final callback = _clickListenersById.remove(id);
    if (callback == null) return;
    element.removeEventListener('click', callback);
  }

  void _applyNativeControlAttributes(
    web.Element element,
    SemanticRole role,
    String? valueText,
  ) {
    switch (role) {
      case SemanticRole.textField:
        final input = element as web.HTMLInputElement;
        final value = valueText ?? '';
        if (input.value != value) input.value = value;
        if (!input.readOnly) input.readOnly = true;
        return;
      case SemanticRole.textArea:
        final textArea = element as web.HTMLTextAreaElement;
        final value = valueText ?? '';
        if (textArea.value != value) textArea.value = value;
        if (!textArea.readOnly) textArea.readOnly = true;
        return;
      default:
        return;
    }
  }

  void _addNativeControlAttributes(
    Map<String, String> attributes,
    SemanticRole role,
  ) {
    switch (role) {
      case SemanticRole.textField:
        attributes['autocomplete'] = 'off';
        attributes['spellcheck'] = 'false';
        attributes['readonly'] = '';
        return;
      case SemanticRole.textArea:
        attributes['spellcheck'] = 'false';
        attributes['readonly'] = '';
        return;
      default:
        return;
    }
  }

  void _addLiveRegionAttributes(
    Map<String, String> attributes,
    SemanticRole role,
  ) {
    switch (role) {
      case SemanticRole.status:
      case SemanticRole.modelStatus:
      case SemanticRole.tokenMeter:
      case SemanticRole.progress:
        attributes['aria-live'] = 'polite';
        return;
      case SemanticRole.notification:
      case SemanticRole.diagnostic:
        attributes['aria-live'] = 'assertive';
        return;
      case SemanticRole.log:
        attributes['aria-live'] = 'polite';
        attributes['aria-relevant'] = 'additions text';
        return;
      default:
        return;
    }
  }

  bool _isNonTabbableMirror(SemanticNode node) {
    return node.focused ||
        node.actions.isNotEmpty ||
        node.role == SemanticRole.link ||
        node.role == SemanticRole.textField ||
        node.role == SemanticRole.textArea;
  }

  String? _ownText(SemanticNode node, String? valueText) {
    return switch (node.role) {
      SemanticRole.text ||
      SemanticRole.code ||
      SemanticRole.codeLine ||
      SemanticRole.markdown ||
      SemanticRole.markdownBlock ||
      SemanticRole.diffLine => valueText ?? node.label,
      SemanticRole.textField || SemanticRole.textArea => valueText,
      _ => node.label ?? valueText,
    };
  }

  bool _allowsOwnText(SemanticRole role) {
    return role != SemanticRole.textField && role != SemanticRole.textArea;
  }

  bool _allowsChildElements(SemanticRole role) {
    return role != SemanticRole.textField && role != SemanticRole.textArea;
  }

  String _tagFor(SemanticRole role) {
    return switch (role) {
      SemanticRole.link => 'a',
      SemanticRole.textField => 'input',
      SemanticRole.textArea => 'textarea',
      SemanticRole.text ||
      SemanticRole.code ||
      SemanticRole.codeLine ||
      SemanticRole.markdown ||
      SemanticRole.markdownBlock ||
      SemanticRole.diffLine => 'span',
      _ => 'div',
    };
  }

  String? _ariaRoleFor(SemanticRole role) {
    return switch (role) {
      SemanticRole.app => 'group',
      SemanticRole.screen ||
      SemanticRole.route ||
      SemanticRole.region ||
      SemanticRole.contextPanel ||
      SemanticRole.patchReview ||
      SemanticRole.formField => 'region',
      SemanticRole.navigation ||
      SemanticRole.conversationNavigator => 'navigation',
      SemanticRole.list || SemanticRole.messageList => 'list',
      SemanticRole.listItem ||
      SemanticRole.contextItem ||
      SemanticRole.fileMention ||
      SemanticRole.message ||
      SemanticRole.task ||
      SemanticRole.traceEvent ||
      SemanticRole.patchFile => 'listitem',
      SemanticRole.table => 'table',
      SemanticRole.tableRow => 'row',
      SemanticRole.tableCell => 'cell',
      SemanticRole.link => 'link',
      SemanticRole.image => 'img',
      SemanticRole.textField || SemanticRole.textArea => 'textbox',
      SemanticRole.button ||
      SemanticRole.command ||
      SemanticRole.approval => 'button',
      SemanticRole.checkbox => 'checkbox',
      SemanticRole.radio => 'radio',
      SemanticRole.toggle => 'switch',
      SemanticRole.spinButton => 'spinbutton',
      SemanticRole.slider => 'slider',
      SemanticRole.datePicker => 'group',
      SemanticRole.menu || SemanticRole.commandPalette => 'menu',
      SemanticRole.menuItem => 'menuitem',
      SemanticRole.dialog => 'dialog',
      SemanticRole.progress => 'progressbar',
      SemanticRole.log => 'log',
      SemanticRole.status ||
      SemanticRole.modelStatus ||
      SemanticRole.tokenMeter ||
      SemanticRole.notification ||
      SemanticRole.diagnostic => 'status',
      SemanticRole.tab => 'tab',
      SemanticRole.tree => 'tree',
      SemanticRole.treeItem || SemanticRole.jsonNode => 'treeitem',
      SemanticRole.form => 'form',
      SemanticRole.taskGraph => 'tree',
      SemanticRole.toolCall => 'status',
      SemanticRole.chart => 'img',
      SemanticRole.text ||
      SemanticRole.conversation ||
      SemanticRole.traceTimeline ||
      SemanticRole.fileMentionPicker ||
      SemanticRole.json ||
      SemanticRole.diff ||
      SemanticRole.diffLine ||
      SemanticRole.code ||
      SemanticRole.codeLine ||
      SemanticRole.markdown ||
      SemanticRole.markdownBlock => null,
    };
  }

  String? _valueText(Object? value) {
    return switch (value) {
      null => null,
      String() => value,
      num() || bool() => value.toString(),
      Iterable<Object?>() =>
        value.map((item) => _valueText(item) ?? '').join(', '),
      Map<Object?, Object?>() =>
        value.entries
            .map(
              (entry) =>
                  '${entry.key}: ${_valueText(entry.value) ?? entry.value}',
            )
            .join(', '),
      _ => value.toString(),
    };
  }

  bool _hasSameChildOrder(SemanticNode previous, SemanticNode next) {
    if (previous.children.length != next.children.length) return false;
    for (var index = 0; index < previous.children.length; index++) {
      if (previous.children[index].id != next.children[index].id) return false;
    }
    return true;
  }

  void _replaceOwnText(
    String id,
    web.Element element,
    SemanticNode node,
    String? valueText,
  ) {
    if (!_allowsOwnText(node.role)) return;
    final ownText = _ownText(node, valueText);
    final nextText = ownText == null || ownText.isEmpty ? '' : ownText;
    _setOwnText(id, element, nextText);
  }

  void _setOwnText(String id, web.Element element, String nextText) {
    final previousText = _ownTextById[id];
    final textNode = _textNodesById[id];
    if (nextText.isEmpty) {
      if (textNode != null) {
        textNode.remove();
        _textNodesById.remove(id);
      } else if (previousText != null && previousText.isNotEmpty) {
        element.textContent = '';
      }
      _ownTextById[id] = '';
      return;
    }
    if (textNode != null) {
      if (previousText != nextText || textNode.data != nextText) {
        textNode.data = nextText;
      }
      _ownTextById[id] = nextText;
      return;
    }
    final created = _document.createTextNode(nextText);
    element.appendChild(created);
    _textNodesById[id] = created;
    _ownTextById[id] = nextText;
  }
}

bool _shouldExposeLabelAttribute(SemanticNode node) {
  return !_usesOwnTextAsAccessibleContent(node.role);
}

bool _shouldExposeValueAttribute(SemanticNode node) {
  return !_usesOwnTextAsAccessibleContent(node.role);
}

bool _usesOwnTextAsAccessibleContent(SemanticRole role) {
  return switch (role) {
    SemanticRole.text ||
    SemanticRole.code ||
    SemanticRole.codeLine ||
    SemanticRole.markdown ||
    SemanticRole.markdownBlock ||
    SemanticRole.diffLine => true,
    _ => false,
  };
}

void _addLinkAttributes(Map<String, String> attributes, SemanticNode node) {
  if (node.role != SemanticRole.link) return;
  final url = _linkUrlFor(node);
  if (url == null || url.isEmpty) return;
  attributes['data-fleury-link-url'] = url;
  if (!node.enabled) return;
  if (!_isSafeLinkForBrowser(node, url)) return;
  attributes['href'] = url;
  attributes['target'] = '_blank';
  attributes['rel'] = 'noopener noreferrer';
}

String? _linkUrlFor(SemanticNode node) {
  final stateUrl = node.state['linkUrl'];
  if (stateUrl is String && stateUrl.isNotEmpty) return stateUrl;
  final value = node.value;
  if (value is String && value.isNotEmpty) return value;
  return null;
}

bool _isSafeLinkForBrowser(SemanticNode node, String url) {
  final explicit = node.state['safeLinkScheme'];
  if (explicit is bool) return explicit;
  final uri = Uri.tryParse(url);
  final scheme = uri?.scheme.toLowerCase();
  return scheme == 'https' || scheme == 'http' || scheme == 'mailto';
}

SemanticAction _primaryActionFor(Set<SemanticAction> actions) {
  for (final action in const [
    SemanticAction.activate,
    SemanticAction.focus,
    SemanticAction.submit,
    SemanticAction.navigate,
    SemanticAction.open,
    SemanticAction.select,
    SemanticAction.copy,
    SemanticAction.clear,
    SemanticAction.close,
    SemanticAction.dismiss,
    SemanticAction.start,
    SemanticAction.cancel,
    SemanticAction.increment,
    SemanticAction.decrement,
    SemanticAction.diagnose,
    SemanticAction.captureDebug,
  ]) {
    if (actions.contains(action)) return action;
  }
  final sorted = actions.toList()..sort((a, b) => a.name.compareTo(b.name));
  return sorted.first;
}

SemanticAction? _semanticActionByName(String name) {
  for (final action in SemanticAction.values) {
    if (action.name == name) return action;
  }
  return null;
}

const _rootStyle =
    'position:absolute;left:-10000px;top:auto;width:1px;height:1px;'
    'overflow:hidden;clip:rect(0 0 0 0);clip-path:inset(50%);'
    'white-space:normal';

final class _SemanticDomMutationStats {
  var nodeCount = 0;
  var createdElementCount = 0;
  var reusedElementCount = 0;
  var replacedElementCount = 0;
  var attributesSetCount = 0;
  var attributesRemovedCount = 0;

  SemanticPresentationStats toPresentationStats(SemanticTreeUpdate? update) {
    return SemanticPresentationStats(
      nodeCount: nodeCount,
      addedNodeCount: update?.added.length ?? 0,
      removedNodeCount: update?.removed.length ?? 0,
      updatedNodeCount: update?.updated.length ?? 0,
      createdElementCount: createdElementCount,
      reusedElementCount: reusedElementCount,
      replacedElementCount: replacedElementCount,
      attributesSetCount: attributesSetCount,
      attributesRemovedCount: attributesRemovedCount,
    );
  }
}
