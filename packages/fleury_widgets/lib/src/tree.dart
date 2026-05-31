import 'package:fleury/fleury.dart';

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
    this.focusNode,
    this.autofocus = false,
    this.onSelect,
    this.selectedStyle,
  });

  final List<TreeNode<T>> roots;
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
  List<(TreeNode<T>, int)> _flat = const [];

  List<(TreeNode<T>, int)> _flatten() {
    final out = <(TreeNode<T>, int)>[];
    void visit(TreeNode<T> node, int depth) {
      out.add((node, depth));
      if (_expanded.contains(node)) {
        for (final child in node.children) {
          visit(child, depth + 1);
        }
      }
    }

    for (final root in widget.roots) {
      visit(root, 0);
    }
    return out;
  }

  (TreeNode<T>, int)? get _selected {
    final i = _list.selectedIndex;
    if (i == null || i < 0 || i >= _flat.length) return null;
    return _flat[i];
  }

  KeyEventResult _expandOrEnter() {
    final sel = _selected;
    final i = _list.selectedIndex;
    if (sel == null || i == null) return KeyEventResult.ignored;
    final node = sel.$1;
    if (!node.isBranch) return KeyEventResult.ignored;
    if (!_expanded.contains(node)) {
      setState(() => _expanded.add(node));
      return KeyEventResult.handled;
    }
    // Already expanded → step into the first child.
    _list.selectedIndex = i + 1;
    return KeyEventResult.handled;
  }

  KeyEventResult _collapseOrParent() {
    final sel = _selected;
    final i = _list.selectedIndex;
    if (sel == null || i == null) return KeyEventResult.ignored;
    final (node, depth) = sel;
    if (node.isBranch && _expanded.contains(node)) {
      setState(() => _expanded.remove(node));
      return KeyEventResult.handled;
    }
    for (var j = i - 1; j >= 0; j--) {
      if (_flat[j].$2 < depth) {
        _list.selectedIndex = j;
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onEnter(int index) {
    if (index < 0 || index >= _flat.length) return;
    final node = _flat[index].$1;
    if (node.isBranch) {
      setState(() {
        if (!_expanded.remove(node)) _expanded.add(node);
      });
    } else {
      widget.onSelect?.call(node);
    }
  }

  @override
  void dispose() {
    _list.dispose();
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
    return Focus(
      canRequestFocus: false,
      onKey: (event) => switch (event.keyCode) {
        KeyCode.arrowRight => _expandOrEnter(),
        KeyCode.arrowLeft => _collapseOrParent(),
        _ => KeyEventResult.ignored,
      },
      child: ListView.builder(
        controller: _list,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        itemCount: _flat.length,
        onSelect: _onEnter,
        itemBuilder: (context, i, selected) {
          final (node, depth) = _flat[i];
          final marker = node.isBranch
              ? (_expanded.contains(node) ? '▾ ' : '▸ ')
              : '  ';
          return Text(
            '${'  ' * depth}$marker${node.label}',
            style: selected ? selectedStyle : CellStyle.empty,
          );
        },
      ),
    );
  }
}
