import 'package:fleury/fleury.dart';

/// One choice in a [Select]. A disabled option is shown dimmed and skipped
/// by arrow navigation and Enter.
final class SelectOption<T> {
  const SelectOption({
    required this.value,
    required this.label,
    this.enabled = true,
  });

  final T value;
  final String label;
  final bool enabled;
}

/// A dropdown picker: a focusable trigger showing the current value (or a
/// [placeholder]) that, when activated, opens a floating list of [options]
/// anchored just below it.
///
/// Enter or Down — or a click — opens it; arrows move the highlight
/// (skipping disabled options), Enter or a click picks one (calling
/// [onChanged] and closing), Esc closes without changing the value. A
/// bullet marks the currently-selected option as you navigate. Focus is
/// trapped in the open list and returns to the trigger on close.
///
/// Controlled: hold [value] yourself and update it from [onChanged]. Built
/// on the anchored-overlay primitive ([Anchor] + [Follower]) so it floats
/// over everything and flips/clamps to stay on screen.
class Select<T> extends StatefulWidget {
  const Select({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.placeholder = 'Select…',
    this.focusNode,
    this.autofocus = false,
  });

  final List<SelectOption<T>> options;

  /// The currently-selected value, or null to show the [placeholder].
  final T? value;
  final void Function(T value) onChanged;
  final String placeholder;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<Select<T>> createState() => _SelectState<T>();
}

class _SelectState<T> extends State<Select<T>> {
  final AnchorLink _link = AnchorLink();
  late FocusNode _triggerFocus;
  bool _ownsFocus = false;
  OverlayEntry? _entry;
  FocusNode? _priorFocus;

  bool get _isOpen => _entry != null;

  @override
  void initState() {
    super.initState();
    _triggerFocus = widget.focusNode ?? FocusNode(debugLabel: 'select-trigger');
    _ownsFocus = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(Select<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocus) _triggerFocus.dispose();
      _triggerFocus =
          widget.focusNode ?? FocusNode(debugLabel: 'select-trigger');
      _ownsFocus = widget.focusNode == null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Focus.maybeOf(context); // rebuild on focus change (focus cue)
  }

  String get _currentLabel {
    for (final o in widget.options) {
      if (o.value == widget.value) return o.label;
    }
    return widget.placeholder;
  }

  int _initialIndex() {
    for (var i = 0; i < widget.options.length; i++) {
      if (widget.options[i].value == widget.value) return i;
    }
    for (var i = 0; i < widget.options.length; i++) {
      if (widget.options[i].enabled) return i;
    }
    return 0;
  }

  int _appliedIndex() {
    for (var i = 0; i < widget.options.length; i++) {
      if (widget.options[i].value == widget.value) return i;
    }
    return -1;
  }

  KeyEventResult _onTriggerKey(KeyEvent event) {
    if (_isOpen) return KeyEventResult.ignored;
    if (event.keyCode == KeyCode.enter || event.keyCode == KeyCode.arrowDown) {
      _open();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _open() {
    if (widget.options.isEmpty || _isOpen) return;
    final manager = Focus.of(context);
    final overlay = Overlay.of(context);
    final theme = Theme.of(
      context,
    ); // resolved in-tree, threaded into the overlay
    _priorFocus = manager.focusedNode;
    final entry = OverlayEntry(
      builder: (_) => Follower(
        link: _link,
        child: _SelectList<T>(
          options: widget.options,
          initialIndex: _initialIndex(),
          appliedIndex: _appliedIndex(),
          selectionStyle: theme.selectionStyle,
          mutedStyle: theme.mutedStyle,
          borderStyle: theme.borderStyle,
          onPicked: (value) {
            _close();
            widget.onChanged(value);
          },
          onDismiss: _close,
        ),
      ),
    );
    _entry = entry;
    manager.requestFocus(null); // let the list's autofocus claim focus
    overlay.insert(entry);
    setState(() {}); // flip the open indicator
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
    if (_ownsFocus) _triggerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focused = _triggerFocus.hasFocus;
    final style = focused ? theme.selectionStyle : CellStyle.empty;
    return Anchor(
      link: _link,
      child: GestureDetector(
        onTap: () {
          _triggerFocus.requestFocus();
          _open();
        },
        child: Focus(
          focusNode: _triggerFocus,
          autofocus: widget.autofocus,
          onKey: _onTriggerKey,
          child: Text('$_currentLabel ${_isOpen ? '▴' : '▾'}', style: style),
        ),
      ),
    );
  }
}

/// The floating option list opened by a [Select].
class _SelectList<T> extends StatefulWidget {
  const _SelectList({
    required this.options,
    required this.initialIndex,
    required this.appliedIndex,
    required this.selectionStyle,
    required this.mutedStyle,
    required this.borderStyle,
    required this.onPicked,
    required this.onDismiss,
  });

  final List<SelectOption<T>> options;
  final int initialIndex;
  final int appliedIndex;
  final CellStyle selectionStyle;
  final CellStyle mutedStyle;
  final BorderStyle borderStyle;
  final void Function(T value) onPicked;
  final void Function() onDismiss;

  @override
  State<_SelectList<T>> createState() => _SelectListState<T>();
}

class _SelectListState<T> extends State<_SelectList<T>> {
  late final ListController _list = ListController(
    selectedIndex: widget.initialIndex,
  );
  final FocusNode _focus = FocusNode(debugLabel: 'select-list');

  bool _enabled(int i) => widget.options[i].enabled;

  int? _step(int from, int dir) {
    var i = from + dir;
    while (i >= 0 && i < widget.options.length) {
      if (_enabled(i)) return i;
      i += dir;
    }
    return null;
  }

  int _firstEnabled() {
    for (var i = 0; i < widget.options.length; i++) {
      if (_enabled(i)) return i;
    }
    return 0;
  }

  int _lastEnabled() {
    for (var i = widget.options.length - 1; i >= 0; i--) {
      if (_enabled(i)) return i;
    }
    return widget.options.length - 1;
  }

  void _pick(int i) {
    if (_enabled(i)) widget.onPicked(widget.options[i].value);
  }

  KeyEventResult _onKey(KeyEvent event) {
    switch (event.keyCode) {
      case KeyCode.arrowUp:
        final n = _step(_list.selectedIndex ?? widget.options.length, -1);
        if (n != null) _list.selectedIndex = n;
        return KeyEventResult.handled;
      case KeyCode.arrowDown:
        final n = _step(_list.selectedIndex ?? -1, 1);
        if (n != null) _list.selectedIndex = n;
        return KeyEventResult.handled;
      case KeyCode.home:
        _list.selectedIndex = _firstEnabled();
        return KeyEventResult.handled;
      case KeyCode.end:
        _list.selectedIndex = _lastEnabled();
        return KeyEventResult.handled;
      case KeyCode.enter:
        final i = _list.selectedIndex;
        if (i != null) _pick(i);
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
    _list.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var labelWidth = 0;
    for (final o in widget.options) {
      if (o.label.length > labelWidth) labelWidth = o.label.length;
    }
    // Leading marker (2 cells: check + space) plus the label.
    final width = labelWidth + 2;

    return FocusScope(
      modal: true,
      suppressGlobals: true,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKey: _onKey,
        child: Container(
          border: BoxBorder(style: widget.borderStyle),
          child: SizedBox(
            width: width,
            height: widget.options.length,
            child: ListView.builder(
              controller: _list,
              itemCount: widget.options.length,
              itemBuilder: (_, i, selected) {
                final option = widget.options[i];
                // A width-1 marker keeps every row aligned and within the
                // computed panel width (a width-2 glyph would wrap).
                final marker = i == widget.appliedIndex ? '• ' : '  ';
                final text = '$marker${option.label}';
                if (!option.enabled) {
                  return Text(text, style: widget.mutedStyle);
                }
                return GestureDetector(
                  onTap: () => _pick(i),
                  child: Text(
                    text,
                    style: selected ? widget.selectionStyle : CellStyle.empty,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
