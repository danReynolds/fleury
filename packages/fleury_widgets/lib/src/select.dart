import 'package:fleury/fleury_core.dart';

import 'option_label.dart';

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
/// over everything and flips/clamps to stay on screen. Passing null for
/// [onChanged] disables the picker.
class Select<T> extends StatefulWidget {
  const Select({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.placeholder = 'Select…',
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
  });

  /// Choices shown in the opened dropdown.
  final List<SelectOption<T>> options;

  /// The currently-selected value, or null to show the [placeholder].
  final T? value;

  /// Called when the user picks an enabled option; null disables the picker.
  final void Function(T value)? onChanged;

  /// Text shown when [value] is null.
  final String placeholder;

  /// Focus node used by the closed trigger.
  final FocusNode? focusNode;

  /// Whether the closed trigger should request focus when mounted.
  final bool autofocus;

  /// Stable label for semantic snapshots.
  ///
  /// The visible collapsed value changes as the user picks options, so pass a
  /// label such as "Environment" or "Color" when tests, debug tools, prompt
  /// fallback, or future adapters need to refer to the picker itself.
  final String? semanticLabel;

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
    if (widget.onChanged == null && oldWidget.onChanged != null) {
      _entry?.remove();
      _entry = null;
    }
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
      if (o.value == widget.value) return sanitizeOptionLabel(o.label);
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
    if (widget.onChanged == null) return KeyEventResult.ignored;
    if (_isOpen) return KeyEventResult.ignored;
    if (event.keyCode == KeyCode.enter || event.keyCode == KeyCode.arrowDown) {
      _open();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _open() {
    if (widget.onChanged == null) return;
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
          semanticLabel: widget.semanticLabel,
          initialIndex: _initialIndex(),
          appliedIndex: _appliedIndex(),
          selectionStyle: theme.selectionStyle,
          mutedStyle: theme.mutedStyle,
          borderStyle: theme.borderStyle,
          onPicked: (value) {
            _close();
            widget.onChanged?.call(value);
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

  /// Picks the option matching [payload] (by label or value string) without
  /// opening the dropdown — the one-call `setValue` path an agent uses instead
  /// of open → read options → select. Prefers an exact match, then a
  /// case-insensitive one; only enabled options match.
  void _selectByPayload(Object? payload) {
    if (widget.onChanged == null) return;
    final wanted = payload?.toString().trim();
    if (wanted == null || wanted.isEmpty) return;
    final lower = wanted.toLowerCase();
    SelectOption<T>? fuzzy;
    for (final o in widget.options) {
      if (!o.enabled) continue;
      final label = sanitizeOptionLabel(o.label);
      if (label == wanted || '${o.value}' == wanted) {
        if (o.value != widget.value) widget.onChanged!(o.value);
        return;
      }
      fuzzy ??=
          (label.toLowerCase() == lower || '${o.value}'.toLowerCase() == lower)
          ? o
          : null;
    }
    if (fuzzy != null && fuzzy.value != widget.value) {
      widget.onChanged!(fuzzy.value);
    }
  }

  @override
  void dispose() {
    _entry?.remove();
    if (_ownsFocus) _triggerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Focus.maybeOf(context); // Rebuild trigger semantics when focus moves.
    final theme = Theme.of(context);
    final enabled = widget.onChanged != null;
    final focused = _triggerFocus.hasFocus;
    final style = !enabled
        ? theme.mutedStyle
        : focused
        ? theme.selectionStyle
        : CellStyle.empty;
    final text = '$_currentLabel ${_isOpen ? '▴' : '▾'}';
    if (!enabled) {
      return Anchor(
        link: _link,
        child: Semantics(
          role: SemanticRole.button,
          label: widget.semanticLabel ?? _currentLabel,
          value: _currentLabel,
          enabled: false,
          expanded: false,
          state: SemanticState({
            'menuItemCount': widget.options.length,
            'open': false,
            'selectedKey': widget.value,
            'selectedOptionLabel': _currentLabel,
          }),
          child: Text(text, style: style),
        ),
      );
    }
    return Anchor(
      link: _link,
      child: Semantics(
        role: SemanticRole.button,
        label: widget.semanticLabel ?? _currentLabel,
        value: _currentLabel,
        focused: _triggerFocus.hasFocus,
        expanded: _isOpen,
        actions: <SemanticAction>{
          SemanticAction.focus,
          if (widget.options.isNotEmpty) SemanticAction.activate,
          if (widget.options.isNotEmpty)
            _isOpen ? SemanticAction.close : SemanticAction.open,
          if (widget.options.isNotEmpty) SemanticAction.setValue,
        },
        state: SemanticState({
          'menuItemCount': widget.options.length,
          'open': _isOpen,
          'selectedKey': widget.value,
          'selectedOptionLabel': _currentLabel,
          // The settable domain: each enabled option's label and stringified
          // value, in the exact forms `_selectByPayload` matches on, so an agent
          // (and the WS-9 valueSchema) sees precisely what set_value accepts.
          'options': <Object?>[
            for (final o in widget.options)
              if (o.enabled)
                <String, Object?>{
                  'label': sanitizeOptionLabel(o.label),
                  'value': '${o.value}',
                },
          ],
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
        onSetValue: _selectByPayload,
        child: GestureDetector(
          onTap: () {
            _triggerFocus.requestFocus();
            _open();
          },
          child: Focus(
            focusNode: _triggerFocus,
            autofocus: widget.autofocus,
            onKey: _onTriggerKey,
            child: Text(text, style: style),
          ),
        ),
      ),
    );
  }
}

/// A keyboard-navigable list of checkable options.
///
/// Controlled: hold [values] yourself and update them from [onChanged]. Enter,
/// Space, or a click toggles the highlighted option. Disabled options remain
/// visible but cannot be toggled. Passing null for [onChanged] disables the
/// whole widget.
class MultiSelect<T> extends StatefulWidget {
  const MultiSelect({
    super.key,
    required this.options,
    required this.values,
    required this.onChanged,
    this.semanticLabel = 'Multi-select',
    this.emptyLabel = 'No options',
    this.focusNode,
    this.autofocus = false,
  });

  final List<SelectOption<T>> options;
  final Set<T> values;
  final void Function(Set<T> values)? onChanged;
  final String semanticLabel;
  final String emptyLabel;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<MultiSelect<T>> createState() => _MultiSelectState<T>();
}

class _MultiSelectState<T> extends State<MultiSelect<T>>
    implements TextInputClaimant {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  int _highlightedIndex = 0;

  bool get _enabled => widget.onChanged != null;

  @override
  void initState() {
    super.initState();
    _attachFocusNode(widget.focusNode);
    _highlightedIndex = _initialIndex();
  }

  @override
  void didUpdateWidget(covariant MultiSelect<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _detachFocusNode();
      _attachFocusNode(widget.focusNode);
    }
    _highlightedIndex = _clampToEnabled(_highlightedIndex);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Focus.maybeOf(context);
  }

  void _attachFocusNode(FocusNode? node) {
    _focusNode = node ?? FocusNode(debugLabel: 'multi-select');
    _ownsFocusNode = node == null;
    _focusNode.textInputClaimant = this;
  }

  void _detachFocusNode() {
    _focusNode.textInputClaimant = null;
    if (_ownsFocusNode) _focusNode.dispose();
  }

  int _initialIndex() {
    for (var i = 0; i < widget.options.length; i++) {
      if (widget.values.contains(widget.options[i].value) &&
          widget.options[i].enabled) {
        return i;
      }
    }
    return _clampToEnabled(0);
  }

  int _clampToEnabled(int index) {
    if (widget.options.isEmpty) return 0;
    final clamped = index.clamp(0, widget.options.length - 1);
    if (widget.options[clamped].enabled) return clamped;
    for (var i = clamped + 1; i < widget.options.length; i++) {
      if (widget.options[i].enabled) return i;
    }
    for (var i = clamped - 1; i >= 0; i--) {
      if (widget.options[i].enabled) return i;
    }
    return clamped;
  }

  int? _step(int direction) {
    var i = _highlightedIndex + direction;
    while (i >= 0 && i < widget.options.length) {
      if (widget.options[i].enabled) return i;
      i += direction;
    }
    return null;
  }

  void _moveTo(int index) {
    if (!_enabled) return;
    setState(() => _highlightedIndex = _clampToEnabled(index));
  }

  void _toggle(int index) {
    if (!_enabled || widget.options.isEmpty) return;
    final option = widget.options[index];
    if (!option.enabled) return;
    final next = Set<T>.of(widget.values);
    if (!next.add(option.value)) next.remove(option.value);
    widget.onChanged!(Set<T>.unmodifiable(next));
  }

  void _toggleHighlighted() {
    if (widget.options.isEmpty) return;
    _toggle(_highlightedIndex);
  }

  /// Ctrl+A toggles all enabled options on, or off if they are all already
  /// selected — the standard multi-selection bulk action (W3C APG listbox).
  void _selectAll() {
    if (!_enabled) return;
    final enabledValues = <T>{
      for (final o in widget.options)
        if (o.enabled) o.value,
    };
    if (enabledValues.isEmpty) return;
    final allSelected = enabledValues.every(widget.values.contains);
    final next = Set<T>.of(widget.values);
    if (allSelected) {
      next.removeAll(enabledValues);
    } else {
      next.addAll(enabledValues);
    }
    widget.onChanged!(Set<T>.unmodifiable(next));
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (!_enabled) return KeyEventResult.ignored;
    switch (event.keyCode) {
      case KeyCode.arrowUp:
        final previous = _step(-1);
        if (previous != null) _moveTo(previous);
        return KeyEventResult.handled;
      case KeyCode.arrowDown:
        final next = _step(1);
        if (next != null) _moveTo(next);
        return KeyEventResult.handled;
      case KeyCode.home:
        _moveTo(0);
        return KeyEventResult.handled;
      case KeyCode.end:
        _moveTo(widget.options.length - 1);
        return KeyEventResult.handled;
      case KeyCode.enter:
        _toggleHighlighted();
        return KeyEventResult.handled;
      default:
        if (event.char == 'a' && event.hasCtrl && !event.hasAlt) {
          _selectAll();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
    }
  }

  @override
  KeyEventResult onTextInput(String text) {
    if (!_enabled) return KeyEventResult.ignored;
    if (text == ' ') {
      _toggleHighlighted();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  KeyEventResult onPaste(String text) => KeyEventResult.ignored;

  @override
  void dispose() {
    _detachFocusNode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Focus.maybeOf(context);
    final theme = Theme.of(context);
    final enabled = _enabled;
    final focused = enabled && _focusNode.hasFocus;
    final child = widget.options.isEmpty
        ? Text(widget.emptyLabel, style: theme.mutedStyle)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < widget.options.length; i++)
                _optionRow(theme, i, focused, enabled),
            ],
          );
    final semantics = Semantics(
      role: SemanticRole.list,
      label: widget.semanticLabel,
      focused: focused,
      enabled: enabled,
      actions: enabled
          ? const <SemanticAction>{
              SemanticAction.focus,
              SemanticAction.navigate,
            }
          : const <SemanticAction>{},
      state: SemanticState({
        'itemCount': widget.options.length,
        'selectedCount': widget.values.length,
        'highlightedIndex': widget.options.isEmpty ? null : _highlightedIndex,
      }),
      onAction: enabled
          ? (action) {
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
          : null,
      child: child,
    );
    if (!enabled) return semantics;
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKey: _onKey,
      child: semantics,
    );
  }

  Widget _optionRow(ThemeData theme, int index, bool focused, bool enabled) {
    final option = widget.options[index];
    final optionEnabled = enabled && option.enabled;
    final selected = widget.values.contains(option.value);
    final highlighted = focused && index == _highlightedIndex;
    final style = !optionEnabled
        ? theme.mutedStyle
        : highlighted
        ? theme.selectionStyle
        : CellStyle.empty;
    final safeLabel = sanitizeOptionLabel(option.label);
    final text = '${selected ? '[x]' : '[ ]'} $safeLabel';
    final row = optionEnabled
        ? GestureDetector(
            onTap: () {
              _focusNode.requestFocus();
              setState(() => _highlightedIndex = index);
              _toggle(index);
            },
            child: Text(text, style: style),
          )
        : Text(text, style: style);
    return Semantics(
      role: SemanticRole.checkbox,
      label: safeLabel,
      value: option.value,
      enabled: optionEnabled,
      focused: highlighted,
      selected: selected,
      checked: selected,
      actions: optionEnabled
          ? const <SemanticAction>{
              SemanticAction.focus,
              SemanticAction.activate,
            }
          : const <SemanticAction>{},
      state: SemanticState({
        'itemIndex': index,
        'itemPosition': index + 1,
        'itemCount': widget.options.length,
      }),
      onAction: optionEnabled
          ? (action) {
              switch (action) {
                case SemanticAction.focus:
                  _focusNode.requestFocus();
                  setState(() => _highlightedIndex = index);
                  return;
                case SemanticAction.activate:
                  _focusNode.requestFocus();
                  setState(() => _highlightedIndex = index);
                  _toggle(index);
                  return;
                case _:
                  return;
              }
            }
          : null,
      child: row,
    );
  }
}

/// The floating option list opened by a [Select].
class _SelectList<T> extends StatefulWidget {
  const _SelectList({
    required this.options,
    required this.semanticLabel,
    required this.initialIndex,
    required this.appliedIndex,
    required this.selectionStyle,
    required this.mutedStyle,
    required this.borderStyle,
    required this.onPicked,
    required this.onDismiss,
  });

  final List<SelectOption<T>> options;
  final String? semanticLabel;
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
  }

  /// Jump to the next enabled option whose label starts with [ch] (wrapping) —
  /// the type-to-search convention (Textual Select, W3C APG combobox).
  KeyEventResult _typeahead(String ch) {
    final lower = ch.toLowerCase();
    final start = (_list.selectedIndex ?? -1) + 1;
    for (var k = 0; k < widget.options.length; k++) {
      final i = (start + k) % widget.options.length;
      if (!_enabled(i)) continue;
      if (sanitizeOptionLabel(
        widget.options[i].label,
      ).toLowerCase().startsWith(lower)) {
        _list.selectedIndex = i;
        break;
      }
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _list.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Focus.maybeOf(context); // Rebuild list/item semantics when focus moves.
    var labelWidth = 0;
    for (final o in widget.options) {
      final labelLength = sanitizeOptionLabel(o.label).length;
      if (labelLength > labelWidth) labelWidth = labelLength;
    }
    // Leading marker (2 cells: check + space) plus the label.
    final width = labelWidth + 2;

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
        'menuDepth': 0,
        'menuItemCount': widget.options.length,
        'selectedKey': _list.selectedIndex,
        'appliedIndex': widget.appliedIndex,
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
          child: Container(
            border: BoxBorder(style: widget.borderStyle),
            child: SizedBox(
              width: width,
              height: widget.options.length,
              child: ListView.builder(
                controller: _list,
                selectionActive: true,
                itemCount: widget.options.length,
                itemBuilder: (_, i, selected) {
                  final option = widget.options[i];
                  // A width-1 marker keeps every row aligned and within the
                  // computed panel width (a width-2 glyph would wrap).
                  final marker = i == widget.appliedIndex ? '• ' : '  ';
                  final safeLabel = sanitizeOptionLabel(option.label);
                  final text = '$marker$safeLabel';
                  final row = option.enabled
                      ? GestureDetector(
                          onTap: () => _pick(i),
                          child: Text(
                            text,
                            style: selected
                                ? widget.selectionStyle
                                : CellStyle.empty,
                          ),
                        )
                      : Text(text, style: widget.mutedStyle);
                  return Semantics(
                    role: SemanticRole.menuItem,
                    label: safeLabel,
                    value: option.value,
                    enabled: option.enabled,
                    focused: _focus.hasFocus && selected,
                    selected: selected,
                    checked: i == widget.appliedIndex,
                    actions: option.enabled
                        ? const <SemanticAction>{
                            SemanticAction.select,
                            SemanticAction.activate,
                          }
                        : const <SemanticAction>{},
                    state: SemanticState({
                      'menuDepth': 0,
                      'menuItemIndex': i,
                      'menuItemPosition': i + 1,
                      'menuItemCount': widget.options.length,
                      'entryKind': 'option',
                      'applied': i == widget.appliedIndex,
                    }),
                    onAction: (action) {
                      if (!option.enabled) return;
                      switch (action) {
                        case SemanticAction.select:
                        case SemanticAction.activate:
                          _list.selectedIndex = i;
                          _pick(i);
                          return;
                        case _:
                          return;
                      }
                    },
                    child: row,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
