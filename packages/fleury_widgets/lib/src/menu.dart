import 'package:fleury/fleury.dart';

/// A row in a [Menu]: a selectable [MenuItem], a nested [SubMenu], or a
/// [MenuSeparator].
sealed class MenuEntry {
  const MenuEntry();
}

/// A selectable menu row. A disabled item ([enabled] false) is shown
/// dimmed and skipped by arrow navigation and Enter.
final class MenuItem extends MenuEntry {
  const MenuItem({
    required this.label,
    required this.onSelected,
    this.enabled = true,
  });

  final String label;
  final void Function() onSelected;
  final bool enabled;
}

/// A row that opens a nested menu of [items] to the right. Right or Enter
/// opens it (and moves focus in); Left or Esc returns to the parent.
final class SubMenu extends MenuEntry {
  const SubMenu({
    required this.label,
    required this.items,
    this.enabled = true,
  });

  final String label;
  final List<MenuEntry> items;
  final bool enabled;
}

/// A non-selectable divider rule between groups of items.
final class MenuSeparator extends MenuEntry {
  const MenuSeparator();
}

/// A dropdown menu: a [trigger] that, when focused and activated (Enter),
/// opens a floating list of [items] anchored just below it. Arrows move
/// the selection (skipping separators and disabled items), Enter runs it
/// (and closes), Esc closes. Focus is trapped in the open menu and returns
/// to the trigger on close.
///
/// Items can nest via [SubMenu]: Right/Enter opens a cascading submenu to
/// the right, Left/Esc steps back out. Choosing any leaf item runs it and
/// closes the whole menu.
///
/// Built on the anchored-overlay primitive ([Anchor] + [Follower]), so it
/// floats over everything and flips/clamps to stay on screen — rather than
/// expanding inline and shoving content around.
class Menu extends StatefulWidget {
  const Menu({
    super.key,
    required this.trigger,
    required this.items,
    this.autofocus = false,
  });

  final Widget trigger;
  final List<MenuEntry> items;
  final bool autofocus;

  @override
  State<Menu> createState() => _MenuState();
}

class _MenuState extends State<Menu> {
  final AnchorLink _link = AnchorLink();
  final FocusNode _triggerFocus = FocusNode(debugLabel: 'menu-trigger');
  OverlayEntry? _entry;
  FocusNode? _priorFocus;

  bool get _isOpen => _entry != null;

  KeyEventResult _onTriggerKey(KeyEvent event) {
    if (!_isOpen && event.keyCode == KeyCode.enter) {
      _open();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _open() {
    final manager = Focus.of(context);
    final overlay = Overlay.of(context);
    _priorFocus = manager.focusedNode;
    final theme = Theme.of(
      context,
    ); // resolved in-tree, threaded into the overlay
    final entry = OverlayEntry(
      builder: (_) => Follower(
        link: _link,
        child: _MenuBody(
          entries: widget.items,
          selectionStyle: theme.selectionStyle,
          mutedStyle: theme.mutedStyle,
          borderStyle: theme.borderStyle,
          onLeafSelected: (action) {
            _close();
            action();
          },
          onDismiss: _close,
        ),
      ),
    );
    _entry = entry;
    // Clear focus so the menu's autofocusing handler can claim it.
    manager.requestFocus(null);
    overlay.insert(entry);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    final prior = _priorFocus;
    if (prior != null && prior.isAttached) prior.requestFocus();
  }

  @override
  void dispose() {
    _entry?.remove();
    _triggerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Anchor(
      link: _link,
      child: Focus(
        focusNode: _triggerFocus,
        autofocus: widget.autofocus,
        onKey: _onTriggerKey,
        child: widget.trigger,
      ),
    );
  }
}

/// One panel of a (possibly nested) menu. Recursive: opening a [SubMenu]
/// inserts a child `_MenuBody` in an overlay to the right.
class _MenuBody extends StatefulWidget {
  const _MenuBody({
    required this.entries,
    required this.selectionStyle,
    required this.mutedStyle,
    required this.borderStyle,
    required this.onLeafSelected,
    required this.onDismiss,
    this.canGoBack = false,
  });

  final List<MenuEntry> entries;
  final CellStyle selectionStyle;
  final CellStyle mutedStyle;
  final BorderStyle borderStyle;

  /// Runs the chosen leaf's action and closes the whole menu chain.
  final void Function(void Function() action) onLeafSelected;

  /// Closes this panel (root: the menu; submenu: back to the parent).
  final void Function() onDismiss;

  /// Whether Left steps back out of this panel (true for submenus).
  final bool canGoBack;

  @override
  State<_MenuBody> createState() => _MenuBodyState();
}

class _MenuBodyState extends State<_MenuBody> {
  late final ListController _list = ListController(
    selectedIndex: _firstSelectable(),
  );
  final FocusNode _focus = FocusNode(debugLabel: 'menu');
  final AnchorLink _selfLink = AnchorLink();
  OverlayEntry? _childEntry;

  bool _selectable(int i) {
    final e = widget.entries[i];
    return (e is MenuItem && e.enabled) || (e is SubMenu && e.enabled);
  }

  int _firstSelectable() {
    for (var i = 0; i < widget.entries.length; i++) {
      if (_selectable(i)) return i;
    }
    return 0;
  }

  int? _step(int from, int dir) {
    var i = from + dir;
    while (i >= 0 && i < widget.entries.length) {
      if (_selectable(i)) return i;
      i += dir;
    }
    return null;
  }

  void _activate(int i) {
    final entry = widget.entries[i];
    if (entry is SubMenu && entry.enabled) {
      _openSubmenu(entry);
    } else if (entry is MenuItem && entry.enabled) {
      widget.onLeafSelected(entry.onSelected);
    }
  }

  void _openSubmenu(SubMenu sub) {
    if (sub.items.isEmpty || _childEntry != null) return;
    final overlay = Overlay.of(context);
    final manager = Focus.of(context);
    final entry = OverlayEntry(
      builder: (_) => Follower(
        link: _selfLink,
        placement: FollowerPlacement.right,
        child: _MenuBody(
          entries: sub.items,
          selectionStyle: widget.selectionStyle,
          mutedStyle: widget.mutedStyle,
          borderStyle: widget.borderStyle,
          onLeafSelected: widget.onLeafSelected, // bubble to the root
          onDismiss: _closeSubmenu,
          canGoBack: true,
        ),
      ),
    );
    _childEntry = entry;
    manager.requestFocus(null); // hand focus to the nested panel
    overlay.insert(entry);
  }

  void _closeSubmenu() {
    _childEntry?.remove();
    _childEntry = null;
    if (mounted) _focus.requestFocus();
  }

  KeyEventResult _onKey(KeyEvent event) {
    switch (event.keyCode) {
      case KeyCode.arrowUp:
        final n = _step(_list.selectedIndex ?? 0, -1);
        if (n != null) _list.selectedIndex = n;
        return KeyEventResult.handled;
      case KeyCode.arrowDown:
        final n = _step(_list.selectedIndex ?? -1, 1);
        if (n != null) _list.selectedIndex = n;
        return KeyEventResult.handled;
      case KeyCode.arrowRight:
        final i = _list.selectedIndex;
        if (i != null && widget.entries[i] is SubMenu) _activate(i);
        return KeyEventResult.handled;
      case KeyCode.arrowLeft:
        if (widget.canGoBack) widget.onDismiss();
        return KeyEventResult.handled;
      case KeyCode.home:
        _list.selectedIndex = _firstSelectable();
        return KeyEventResult.handled;
      case KeyCode.enter:
        final i = _list.selectedIndex;
        if (i != null && _selectable(i)) _activate(i);
        return KeyEventResult.handled;
      case KeyCode.escape:
        widget.onDismiss();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  void dispose() {
    _childEntry?.remove();
    _list.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSubmenu = widget.entries.any((e) => e is SubMenu);
    // Width fits the longest label plus the marker (2) and, when any row
    // is a submenu, the trailing ' ▸' indicator (2).
    var labelWidth = 0;
    for (final e in widget.entries) {
      final label = switch (e) {
        MenuItem(:final label) => label,
        SubMenu(:final label) => label,
        MenuSeparator() => '',
      };
      if (label.length > labelWidth) labelWidth = label.length;
    }
    final width = labelWidth + 2 + (hasSubmenu ? 2 : 0);

    return FocusScope(
      modal: true,
      suppressGlobals: true,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKey: _onKey,
        child: Anchor(
          link: _selfLink,
          child: Container(
            border: BoxBorder(style: widget.borderStyle),
            child: SizedBox(
              width: width,
              height: widget.entries.length,
              child: ListView.builder(
                controller: _list,
                itemCount: widget.entries.length,
                itemBuilder: (_, i, selected) {
                  final entry = widget.entries[i];
                  switch (entry) {
                    case MenuSeparator():
                      return Text('─' * width, style: widget.mutedStyle);
                    case MenuItem(:final label, :final enabled):
                      if (!enabled) {
                        return Text('  $label', style: widget.mutedStyle);
                      }
                      return Text(
                        '${selected ? '› ' : '  '}$label',
                        style: selected
                            ? widget.selectionStyle
                            : CellStyle.empty,
                      );
                    case SubMenu(:final label, :final enabled):
                      if (!enabled) {
                        return Text('  $label ▸', style: widget.mutedStyle);
                      }
                      return Text(
                        '${selected ? '› ' : '  '}$label ▸',
                        style: selected
                            ? widget.selectionStyle
                            : CellStyle.empty,
                      );
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
