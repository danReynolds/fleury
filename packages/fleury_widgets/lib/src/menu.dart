import 'package:fleury/fleury_core.dart';

import 'option_label.dart';

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
    required this.onSelect,
    this.enabled = true,
  });

  /// Text displayed for this menu row.
  final String label;

  /// Called when the enabled item is activated.
  final void Function() onSelect;

  /// Whether the row can receive selection and be activated.
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

  /// Text displayed for this submenu row.
  final String label;

  /// Entries displayed when the submenu opens.
  final List<MenuEntry> items;

  /// Whether the row can receive selection and open its submenu.
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
    this.semanticLabel,
  });

  /// Widget that opens the menu when activated.
  final Widget trigger;

  /// Top-level entries displayed by the menu.
  final List<MenuEntry> items;

  /// Whether the trigger should request focus when mounted.
  final bool autofocus;

  /// Label for the menu trigger and root menu in semantic snapshots.
  ///
  /// The visible [trigger] can be any widget, so Fleury cannot reliably infer a
  /// human label from it. Pass this when tests, debug tools, prompt fallback, or
  /// future adapters need a stable menu name.
  final String? semanticLabel;

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
    if (!_isOpen && event.code == KeyCode.enter) {
      _open();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _open() {
    if (widget.items.isEmpty || _isOpen) return;
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
          semanticLabel: widget.semanticLabel,
          depth: 0,
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
    setState(() {});
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    final prior = _priorFocus;
    if (prior != null && prior.isAttached) prior.requestFocus();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _entry?.remove();
    _triggerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Focus.maybeOf(context); // Rebuild trigger semantics when focus moves.
    return Anchor(
      link: _link,
      child: Semantics(
        role: SemanticRole.button,
        label: widget.semanticLabel,
        focused: _triggerFocus.hasFocus,
        expanded: _isOpen,
        actions: <SemanticAction>{
          SemanticAction.focus,
          if (widget.items.isNotEmpty) SemanticAction.activate,
          if (widget.items.isNotEmpty)
            _isOpen ? SemanticAction.close : SemanticAction.open,
        },
        state: SemanticState({
          'menuItemCount': _menuItemCount(widget.items),
          'open': _isOpen,
        }),
        onAction: (action) {
          switch (action) {
            case SemanticAction.focus:
              _triggerFocus.requestFocus();
              return;
            case SemanticAction.activate:
              _isOpen ? _close() : _open();
              return;
            case SemanticAction.open:
              _open();
              return;
            case SemanticAction.close:
              _close();
              return;
            case _:
              return;
          }
        },
        child: GestureDetector(
          // Pointer users get the same affordance as keyboard (Enter) and
          // assistive tech (the activate action): a tap toggles the menu.
          // Focus the trigger first so [_open] records it as the prior focus
          // and closing returns focus here — matching the keyboard path.
          onTap: () {
            if (_isOpen) {
              _close();
            } else {
              _triggerFocus.requestFocus();
              _open();
            }
          },
          child: Focus(
            focusNode: _triggerFocus,
            autofocus: widget.autofocus,
            onKey: _onTriggerKey,
            child: widget.trigger,
          ),
        ),
      ),
    );
  }
}

/// One panel of a (possibly nested) menu. Recursive: opening a [SubMenu]
/// inserts a child `_MenuBody` in an overlay to the right.
class _MenuBody extends StatefulWidget {
  const _MenuBody({
    required this.entries,
    required this.semanticLabel,
    required this.depth,
    required this.selectionStyle,
    required this.mutedStyle,
    required this.borderStyle,
    required this.onLeafSelected,
    required this.onDismiss,
    this.canGoBack = false,
  });

  final List<MenuEntry> entries;
  final String? semanticLabel;
  final int depth;
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
  // Anchors the currently-selected submenu row so its child panel opens beside
  // *that row*, not the panel's top corner.
  final AnchorLink _submenuAnchor = AnchorLink();
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

  int _lastSelectable() {
    for (var i = widget.entries.length - 1; i >= 0; i--) {
      if (_selectable(i)) return i;
    }
    return 0;
  }

  /// One full-width row: `marker + label`, padded so the cascade `▸` indicator
  /// sits in its own right-aligned column with a trailing pad cell. Filling the
  /// whole [width] makes the selection highlight a clean full-row bar rather
  /// than a ragged block sized to the text.
  String _rowText(
    String label, {
    required bool selected,
    required bool isSub,
    required bool hasIndicator,
    required int width,
  }) {
    final marker = selected ? '› ' : '  ';
    // Trailing region: [▸ or blank][pad] when this menu has submenus, else
    // just a pad. Reserving it on every row keeps the ▸ column aligned.
    final trailing = hasIndicator ? (isSub ? '▸ ' : '  ') : ' ';
    final fillTo = width - trailing.length;
    var s = '$marker$label';
    s = s.length >= fillTo ? s.substring(0, fillTo) : s.padRight(fillTo);
    return '$s$trailing';
  }

  String? _entryLabel(int i) {
    final e = widget.entries[i];
    if (e is MenuItem) return e.label;
    if (e is SubMenu) return e.label;
    return null;
  }

  /// WAI-ARIA menu typeahead: jump to the next selectable item whose label
  /// starts with [ch] (wrapping from the current selection).
  KeyEventResult _typeahead(String ch) {
    final lower = ch.toLowerCase();
    final start = (_list.selectedIndex ?? -1) + 1;
    for (var k = 0; k < widget.entries.length; k++) {
      final i = (start + k) % widget.entries.length;
      if (!_selectable(i)) continue;
      final label = _entryLabel(i);
      if (label != null && label.toLowerCase().startsWith(lower)) {
        _list.selectedIndex = i;
        break;
      }
    }
    return KeyEventResult.handled;
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
      widget.onLeafSelected(entry.onSelect);
    }
  }

  void _openSubmenu(SubMenu sub) {
    if (sub.items.isEmpty || _childEntry != null) return;
    final overlay = Overlay.of(context);
    final manager = Focus.of(context);
    final entry = OverlayEntry(
      builder: (_) => Follower(
        link: _submenuAnchor,
        placement: FollowerPlacement.right,
        gap: 1,
        child: _MenuBody(
          entries: sub.items,
          semanticLabel: sub.label,
          depth: widget.depth + 1,
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
    setState(() {});
  }

  void _closeSubmenu() {
    _childEntry?.remove();
    _childEntry = null;
    if (mounted) _focus.requestFocus();
    if (mounted) setState(() {});
  }

  KeyEventResult _onKey(KeyEvent event) {
    switch (event.code) {
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
      case KeyCode.end:
        _list.selectedIndex = _lastSelectable();
        return KeyEventResult.handled;
      case KeyCode.enter:
        final i = _list.selectedIndex;
        if (i != null && _selectable(i)) _activate(i);
        return KeyEventResult.handled;
      case KeyCode.escape:
        widget.onDismiss();
        return KeyEventResult.handled;
      default:
        final ch = event.code.character;
        if (ch != null &&
            ch.length == 1 &&
            ch.codeUnitAt(0) >= 0x21 &&
            !event.hasCtrl &&
            !event.hasAlt) {
          return _typeahead(ch);
        }
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
    Focus.maybeOf(context); // Rebuild menu/item semantics when focus moves.
    final hasSubmenu = widget.entries.any((e) => e is SubMenu);
    // Row layout: a 2-cell leading marker (`› ` selected / blank), the label,
    // the cascade `▸` indicator right-aligned in its own column, and a trailing
    // pad cell so labels never hug the border.
    var labelWidth = 0;
    for (final e in widget.entries) {
      final label = sanitizeOptionLabel(switch (e) {
        MenuItem(:final label) => label,
        SubMenu(:final label) => label,
        MenuSeparator() => '',
      });
      if (label.length > labelWidth) labelWidth = label.length;
    }
    // 2 (marker) + label + a trailing region: 2 cells when any row is a
    // submenu (the ▸ column + a pad), else 1 (just the pad).
    final width = 2 + labelWidth + (hasSubmenu ? 2 : 1);

    return Semantics(
      role: SemanticRole.menu,
      label: widget.semanticLabel,
      focused: _focus.hasFocus,
      expanded: true,
      actions: const <SemanticAction>{
        SemanticAction.focus,
        SemanticAction.close,
      },
      state: SemanticState({
        'menuDepth': widget.depth,
        'menuItemCount': _menuItemCount(widget.entries),
        'selectedKey': _list.selectedIndex,
        'canGoBack': widget.canGoBack,
      }),
      onAction: (action) {
        switch (action) {
          case SemanticAction.focus:
            _focus.requestFocus();
            return;
          case SemanticAction.close:
            widget.onDismiss();
            return;
          case _:
            return;
        }
      },
      child: FocusScope(
        modal: true,
        suppressGlobals: true,
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          onKey: _onKey,
          child: Anchor(
            link: _selfLink,
            // A floating popup paints its own opaque background (Surface) so the
            // app underneath doesn't bleed through its frame.
            child: Surface(
              child: Container(
                border: BoxBorder(style: widget.borderStyle),
                child: SizedBox(
                  width: width,
                  height: widget.entries.length,
                  child: ListView.builder(
                    controller: _list,
                    selectionActive: true,
                    itemCount: widget.entries.length,
                    itemBuilder: (_, i, selected) {
                      final entry = widget.entries[i];
                      switch (entry) {
                        case MenuSeparator():
                          return Text('─' * width, style: widget.mutedStyle);
                        case MenuItem(:final label, :final enabled):
                          final sel = enabled && selected;
                          final child = Text(
                            _rowText(
                              sanitizeOptionLabel(label),
                              selected: sel,
                              isSub: false,
                              hasIndicator: hasSubmenu,
                              width: width,
                            ),
                            style: !enabled
                                ? widget.mutedStyle
                                : sel
                                ? widget.selectionStyle
                                : CellStyle.empty,
                          );
                          return _semanticMenuItem(
                            entry: entry,
                            index: i,
                            selected: selected,
                            child: child,
                          );
                        case SubMenu(:final label, :final enabled):
                          final sel = enabled && selected;
                          final child = Text(
                            _rowText(
                              sanitizeOptionLabel(label),
                              selected: sel,
                              isSub: true,
                              hasIndicator: hasSubmenu,
                              width: width,
                            ),
                            style: !enabled
                                ? widget.mutedStyle
                                : sel
                                ? widget.selectionStyle
                                : CellStyle.empty,
                          );
                          final item = _semanticMenuItem(
                            entry: entry,
                            index: i,
                            selected: selected,
                            child: child,
                          );
                          // Anchor the selected submenu row so its child panel
                          // opens aligned to it (not the panel corner).
                          return sel
                              ? Anchor(link: _submenuAnchor, child: item)
                              : item;
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _semanticMenuItem({
    required MenuEntry entry,
    required int index,
    required bool selected,
    required Widget child,
  }) {
    final label = sanitizeOptionLabel(switch (entry) {
      MenuItem(:final label) => label,
      SubMenu(:final label) => label,
      MenuSeparator() => '',
    });
    final enabled = switch (entry) {
      MenuItem(:final enabled) => enabled,
      SubMenu(:final enabled) => enabled,
      MenuSeparator() => false,
    };
    final submenu = entry is SubMenu;
    final expanded = submenu && selected && _childEntry != null;
    return Semantics(
      role: SemanticRole.menuItem,
      label: label,
      enabled: enabled,
      focused: _focus.hasFocus && selected,
      selected: selected,
      expanded: submenu ? expanded : null,
      actions: enabled
          ? <SemanticAction>{
              if (submenu) SemanticAction.open,
              SemanticAction.activate,
            }
          : const <SemanticAction>{},
      state: SemanticState({
        'menuDepth': widget.depth,
        'menuItemIndex': index,
        'menuItemPosition': _menuItemPosition(widget.entries, index),
        'menuItemCount': _menuItemCount(widget.entries),
        'entryKind': submenu ? 'submenu' : 'item',
        if (submenu) 'childMenuItemCount': _menuItemCount(entry.items),
      }),
      onAction: (action) {
        if (!enabled) return;
        switch (action) {
          case SemanticAction.open:
            if (submenu) {
              _list.selectedIndex = index;
              _openSubmenu(entry);
            }
            return;
          case SemanticAction.activate:
            _list.selectedIndex = index;
            _activate(index);
            return;
          case _:
            return;
        }
      },
      // Click an enabled item to activate it (open a submenu or invoke a
      // leaf) — the same outcome as Enter / Right, which run [_activate].
      child: enabled
          ? GestureDetector(
              onTap: () {
                _list.selectedIndex = index;
                _activate(index);
              },
              child: child,
            )
          : child,
    );
  }
}

int _menuItemCount(List<MenuEntry> entries) {
  var count = 0;
  for (final entry in entries) {
    if (entry is! MenuSeparator) count += 1;
  }
  return count;
}

int _menuItemPosition(List<MenuEntry> entries, int index) {
  var position = 0;
  for (var i = 0; i <= index && i < entries.length; i++) {
    if (entries[i] is! MenuSeparator) position += 1;
  }
  return position;
}
