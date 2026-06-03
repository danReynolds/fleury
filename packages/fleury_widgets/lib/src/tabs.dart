import 'package:fleury/fleury.dart';

/// One tab: a [label] for the strip and the [content] shown when active.
class TabItem {
  const TabItem({required this.label, required this.content});

  final String label;
  final Widget content;
}

/// Selected-tab state for a [Tabs]. Optional — [Tabs] creates its own when
/// none is given. `length` is set by the widget on each build.
class TabController extends ChangeNotifier {
  TabController({int initialIndex = 0})
    : _index = initialIndex < 0 ? 0 : initialIndex;

  int _index;
  int _length = 0;
  bool _disposed = false;

  int get index => _index;
  int get length => _length;

  set index(int value) {
    _checkNotDisposed();
    if (_length == 0) {
      _index = value < 0 ? 0 : value;
      return;
    }
    final clamped = value.clamp(0, _length - 1);
    if (clamped == _index) return;
    _index = clamped;
    notifyListeners();
  }

  /// Advances to the next tab, wrapping at the end.
  void next() {
    _checkNotDisposed();
    if (_length == 0) return;
    index = (_index + 1) % _length;
  }

  /// Moves to the previous tab, wrapping at the start.
  void previous() {
    _checkNotDisposed();
    if (_length == 0) return;
    index = (_index - 1) % _length;
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('TabController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

/// A tab strip over swappable content.
///
/// Renders a row of labels (the active one highlighted) above the active
/// tab's content. When the strip is focused, Left/Right switch tabs
/// (wrapping). Alt+1..Alt+9 jump straight to a tab from anywhere inside
/// the tab area, and you can drive [controller] directly for programmatic
/// switching. The active tab's focusable widgets join the normal focus
/// traversal, so Tab moves into them.
///
/// Every tab stays mounted, so each one's state (scroll position, typed
/// text, expanded nodes…) survives switching away and back. Inactive tabs
/// are hidden and excluded from focus traversal while they're off-screen.
class Tabs extends StatefulWidget {
  const Tabs({
    super.key,
    required this.tabs,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.activeStyle,
    this.inactiveStyle,
  });

  final List<TabItem> tabs;
  final TabController? controller;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Style for the active tab's label. Defaults to inverse video.
  final CellStyle? activeStyle;

  /// Style for inactive tab labels. Defaults to dim.
  final CellStyle? inactiveStyle;

  @override
  State<Tabs> createState() => _TabsState();
}

class _TabsState extends State<Tabs> {
  late TabController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TabController();
    _ownsController = widget.controller == null;
    _controller._length = widget.tabs.length;
    _controller.addListener(_onChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'Tabs');
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(Tabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? TabController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'Tabs');
      _ownsFocusNode = widget.focusNode == null;
    }
    _controller._length = widget.tabs.length;
    // Re-clamp through the setter so a shrunk tab list pulls the
    // selection back into range (and notifies if it moved).
    _controller.index = _controller.index;
  }

  void _onChange() => setState(() {});

  KeyEventResult _onKey(KeyEvent event) {
    switch (event.keyCode) {
      case KeyCode.arrowLeft:
        _controller.previous();
        return KeyEventResult.handled;
      case KeyCode.arrowRight:
        _controller.next();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Focus.maybeOf(context); // Rebuild tab semantics when focus moves.
    _controller._length = widget.tabs.length;
    if (widget.tabs.isEmpty) return const EmptyBox();
    final active = _controller.index.clamp(0, widget.tabs.length - 1);
    final theme = Theme.of(context);
    final activeStyle = widget.activeStyle ?? theme.selectionStyle;
    final inactiveStyle = widget.inactiveStyle ?? theme.mutedStyle;

    final body = Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKey: _onKey,
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < widget.tabs.length; i++)
                Semantics(
                  role: SemanticRole.tab,
                  label: widget.tabs[i].label,
                  focused: _focusNode.hasFocus && i == active,
                  selected: i == active,
                  actions: const <SemanticAction>{
                    SemanticAction.focus,
                    SemanticAction.select,
                    SemanticAction.activate,
                  },
                  state: SemanticState({
                    'tabIndex': i,
                    'tabPosition': i + 1,
                    'tabCount': widget.tabs.length,
                    'active': i == active,
                    if (i < 9) 'shortcut': 'Alt+${i + 1}',
                  }),
                  onAction: (action) {
                    switch (action) {
                      case SemanticAction.focus:
                        _focusNode.requestFocus();
                        return;
                      case SemanticAction.select:
                      case SemanticAction.activate:
                        _controller.index = i;
                        _focusNode.requestFocus();
                        return;
                      case _:
                        return;
                    }
                  },
                  child: Text(
                    ' ${widget.tabs[i].label} ',
                    style: i == active ? activeStyle : inactiveStyle,
                  ),
                ),
            ],
          ),
          // Keep every tab mounted (state survives switching) but paint
          // and traverse only the active one.
          IndexedStack(
            index: active,
            children: [
              for (var i = 0; i < widget.tabs.length; i++)
                ExcludeFocus(
                  excluding: i != active,
                  child: widget.tabs[i].content,
                ),
            ],
          ),
        ],
      ),
    );

    if (widget.tabs.length <= 1) return body;
    // Alt+1..Alt+9 jump straight to a tab from anywhere inside the tab
    // area (not just the focused strip). Modifier chords arrive as key
    // events, so they bypass any text field in the active tab's content.
    return KeyBindings(
      bindings: [
        for (var i = 0; i < widget.tabs.length && i < 9; i++)
          KeyBinding(
            KeyChord.alt.char('${i + 1}'),
            onEvent: (_) {
              _controller.index = i;
            },
            hideFromHintBar: true,
          ),
      ],
      child: body,
    );
  }
}
