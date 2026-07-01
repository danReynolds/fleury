import 'package:fleury/fleury_core.dart';

/// A node in a [Tree]: a [label] to display, an optional [value] payload,
/// and any [children]. A node with children is a branch (expandable); one
/// without is a leaf.
///
/// The [value] is handed back to `onSelect`, so the caller can act on the
/// underlying datum without keeping a label→data map of its own. Leave
/// `T` unspecified (it defaults to `dynamic`) when you only need labels.
///
/// Expansion is tracked by node **identity**, so hold a stable [roots]
/// list (build it once, e.g. as `const` or in `initState`). If you
/// rebuild `roots` into fresh `TreeNode` instances each frame, expansion
/// state resets — the old instances are no longer in the tree.
class TreeNode<T> {
  const TreeNode(this.label, {this.value, this.children = const []});

  final String label;
  final T? value;
  final List<TreeNode<T>> children;

  bool get isBranch => children.isNotEmpty;
}

/// A keyboard-navigable, collapsible tree.
///
/// Flattens the expanded hierarchy into rows and renders them through a
/// `ListView` (so it inherits selection, scrolling, and auto-scroll for
/// free). On top of that:
///   - Up/Down move the selection, Home/End jump (from `ListView`).
///   - Right expands a collapsed branch, or steps into the first child of
///     an expanded one.
///   - Left collapses an expanded branch, or steps out to the parent.
///   - Enter toggles a branch, or fires [onSelect] for a leaf.
///
/// Left/Right return to the focus chain when they'd do nothing (a leaf, a
/// top-level collapsed node), so the tree composes with pane traversal.
class Tree<T> extends StatefulWidget {
  const Tree({
    super.key,
    required this.roots,
    this.label = 'Tree',
    this.focusNode,
    this.autofocus = false,
    this.onSelect,
    this.selectedStyle,
  });

  final List<TreeNode<T>> roots;
  final String label;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Called when Enter activates a leaf node.
  final void Function(TreeNode<T> node)? onSelect;

  /// Style for the highlighted row. Defaults to inverse video.
  final CellStyle? selectedStyle;

  @override
  State<Tree<T>> createState() => _TreeState<T>();
}

class _TreeState<T> extends State<Tree<T>> {
  final Set<TreeNode<T>> _expanded = Set<TreeNode<T>>.identity();
  final ListController _list = ListController(selectedIndex: 0);
  List<_TreeRow<T>> _flat = const [];
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'Tree');
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(covariant Tree<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode == oldWidget.focusNode) return;
    if (_ownsFocusNode) _focusNode.dispose();
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'Tree');
    _ownsFocusNode = widget.focusNode == null;
  }

  List<_TreeRow<T>> _flatten() {
    final out = <_TreeRow<T>>[];
    void visit(TreeNode<T> node, int depth, String key) {
      out.add(_TreeRow<T>(node: node, depth: depth, key: key));
      if (_expanded.contains(node)) {
        for (var i = 0; i < node.children.length; i++) {
          visit(node.children[i], depth + 1, '$key.$i');
        }
      }
    }

    for (var i = 0; i < widget.roots.length; i++) {
      visit(widget.roots[i], 0, '$i');
    }
    return out;
  }

  _TreeRow<T>? get _selected {
    final i = _list.selectedIndex;
    if (i == null || i < 0 || i >= _flat.length) return null;
    return _flat[i];
  }

  KeyEventResult _expandOrEnter() {
    final sel = _selected;
    final i = _list.selectedIndex;
    if (sel == null || i == null) return KeyEventResult.ignored;
    final node = sel.node;
    if (!node.isBranch) return KeyEventResult.ignored;
    if (!_expanded.contains(node)) {
      setState(() => _expanded.add(node));
      return KeyEventResult.handled;
    }
    // Already expanded → step into the first child.
    _list.selectedIndex = i + 1;
    return KeyEventResult.handled;
  }

  /// Jump to the next visible node whose label starts with [ch] (wrapping) —
  /// WAI-ARIA treeview typeahead; essential for navigating long trees.
  KeyEventResult _typeahead(String ch) {
    if (_flat.isEmpty) return KeyEventResult.handled;
    final lower = ch.toLowerCase();
    final start = (_list.selectedIndex ?? -1) + 1;
    for (var k = 0; k < _flat.length; k++) {
      final i = (start + k) % _flat.length;
      if (_flat[i].node.label.toLowerCase().startsWith(lower)) {
        _list.selectedIndex = i;
        break;
      }
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _collapseOrParent() {
    final sel = _selected;
    final i = _list.selectedIndex;
    if (sel == null || i == null) return KeyEventResult.ignored;
    final node = sel.node;
    final depth = sel.depth;
    if (node.isBranch && _expanded.contains(node)) {
      setState(() => _expanded.remove(node));
      return KeyEventResult.handled;
    }
    for (var j = i - 1; j >= 0; j--) {
      if (_flat[j].depth < depth) {
        _list.selectedIndex = j;
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onEnter(int index) {
    if (index < 0 || index >= _flat.length) return;
    final node = _flat[index].node;
    if (node.isBranch) {
      setState(() {
        if (!_expanded.remove(node)) _expanded.add(node);
      });
    } else {
      widget.onSelect?.call(node);
    }
  }

  void _openRow(int index) {
    if (index < 0 || index >= _flat.length) return;
    _focusNode.requestFocus();
    _list.selectedIndex = index;
    final node = _flat[index].node;
    if (!node.isBranch) return;
    setState(() => _expanded.add(node));
  }

  void _closeRow(int index) {
    if (index < 0 || index >= _flat.length) return;
    _focusNode.requestFocus();
    _list.selectedIndex = index;
    final node = _flat[index].node;
    if (!node.isBranch) return;
    setState(() => _expanded.remove(node));
  }

  void _activateRow(int index) {
    if (index < 0 || index >= _flat.length) return;
    _focusNode.requestFocus();
    _list.selectedIndex = index;
    final node = _flat[index].node;
    if (node.isBranch) {
      _openRow(index);
    } else {
      widget.onSelect?.call(node);
    }
  }

  void _handleTreeAction(SemanticAction action) {
    switch (action) {
      case SemanticAction.focus:
      case SemanticAction.navigate:
        _focusNode.requestFocus();
        setState(() {});
        return;
      case _:
        return;
    }
  }

  @override
  void dispose() {
    _list.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _flat = _flatten();
    final selectedStyle =
        widget.selectedStyle ?? Theme.of(context).selectionStyle;
    // Use Focus.onKey (not KeyBindings) so a no-op Left/Right returns
    // `ignored` and bubbles to the focus chain — letting an enclosing
    // FocusTraversalGroup move between panes at the tree's edges. (A
    // matched KeyBinding is terminal even when it returns ignored.)
    return Semantics(
      role: SemanticRole.tree,
      label: widget.label,
      focused: _focusNode.hasFocus,
      actions: const {SemanticAction.focus, SemanticAction.navigate},
      onAction: _handleTreeAction,
      state: SemanticState({
        'collectionRowCount': _flat.length,
        'rootCount': widget.roots.length,
        'expandedCount': _expanded.length,
        if (_list.visibleRange != null) ...{
          'visibleRangeStart': _list.visibleRange!.first,
          'visibleRangeEnd': _list.visibleRange!.last,
        },
        if (_list.selectedIndex != null) 'selectedIndex': _list.selectedIndex,
        if (_selected != null) 'selectedKey': _selected!.key,
      }),
      child: Focus(
        canRequestFocus: false,
        onKey: (event) {
          switch (event.keyCode) {
            case KeyCode.arrowRight:
              return _expandOrEnter();
            case KeyCode.arrowLeft:
              return _collapseOrParent();
            default:
              final ch = event.char;
              if (ch != null &&
                  ch.length == 1 &&
                  ch.codeUnitAt(0) >= 0x21 &&
                  !event.hasCtrl &&
                  !event.hasAlt) {
                return _typeahead(ch);
              }
              return KeyEventResult.ignored;
          }
        },
        child: ListView.builder(
          controller: _list,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          itemCount: _flat.length,
          onSelect: _onEnter,
          itemBuilder: (context, i, activeSelected) {
            final row = _flat[i];
            final selected = i == _list.selectedIndex;
            return _TreeRowWidget<T>(
              row: row,
              rowIndex: i,
              selected: selected,
              activeSelection: activeSelected,
              expanded: _expanded.contains(row.node),
              selectedStyle: selectedStyle,
              hasOnSelect: widget.onSelect != null,
              onOpen: () => _openRow(i),
              onClose: () => _closeRow(i),
              onActivate: () => _activateRow(i),
            );
          },
        ),
      ),
    );
  }
}

final class _TreeRow<T> {
  const _TreeRow({required this.node, required this.depth, required this.key});

  final TreeNode<T> node;
  final int depth;
  final String key;
}

class _TreeRowWidget<T> extends StatelessWidget {
  const _TreeRowWidget({
    required this.row,
    required this.rowIndex,
    required this.selected,
    required this.activeSelection,
    required this.expanded,
    required this.selectedStyle,
    required this.hasOnSelect,
    required this.onOpen,
    required this.onClose,
    required this.onActivate,
  });

  final _TreeRow<T> row;
  final int rowIndex;
  final bool selected;
  final bool activeSelection;
  final bool expanded;
  final CellStyle selectedStyle;
  final bool hasOnSelect;
  final void Function() onOpen;
  final void Function() onClose;
  final void Function() onActivate;

  @override
  Widget build(BuildContext context) {
    final node = row.node;
    final label = _sanitizeTreeText(node.label);
    final marker = node.isBranch ? (expanded ? '▾ ' : '▸ ') : '  ';
    return Semantics(
      role: SemanticRole.treeItem,
      label: label,
      selected: selected,
      enabled: true,
      actions: {
        // A collapsed branch offers `open`, an expanded one `close` — the
        // symmetric pair an agent needs (collapsing was Left-arrow-only).
        if (node.isBranch && !expanded) SemanticAction.open,
        if (node.isBranch && expanded) SemanticAction.close,
        if (!node.isBranch && hasOnSelect) SemanticAction.activate,
      },
      onAction: (action) {
        switch (action) {
          case SemanticAction.open:
            if (node.isBranch) onOpen();
            return;
          case SemanticAction.close:
            if (node.isBranch) onClose();
            return;
          case SemanticAction.activate:
            if (!node.isBranch && hasOnSelect) onActivate();
            return;
          case _:
            return;
        }
      },
      state: SemanticState({
        'rowIndex': rowIndex,
        'rowKey': row.key,
        'depth': row.depth,
        'isBranch': node.isBranch,
        'expanded': expanded,
        'childCount': node.children.length,
        'outputSanitized': label != node.label,
      }),
      child: Text(
        '${'  ' * row.depth}$marker$label',
        style: activeSelection
            ? selectedStyle
            : selected
            ? Theme.of(context).mutedStyle
            : CellStyle.empty,
      ),
    );
  }
}

final _treeLineBreakPattern = RegExp(r'[\r\n\t]');

String _sanitizeTreeText(String text) {
  return sanitizeForDisplay(text.replaceAll(_treeLineBreakPattern, ' '));
}
