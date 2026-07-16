import 'package:fleury/fleury_core.dart';

import 'option_label.dart';

/// A text field with an anchored, live-filtered suggestion list.
///
/// As the user types, options whose display string matches the text
/// (case-insensitive substring) appear in a dropdown anchored just below
/// the field — via the [Anchor]/[Follower] primitive, so it floats over
/// content and stays on screen. The field keeps focus throughout: Up/Down
/// move the highlight, Enter fills the field with the highlighted option
/// (and calls [onSelect]), Esc closes the dropdown.
///
/// Options can be any type [T]; [displayStringForOption] maps each to the
/// text shown and matched against (defaults to `toString()`). `onSelect`
/// hands back the chosen option itself, not just its string.
class Autocomplete<T extends Object> extends StatefulWidget {
  const Autocomplete({
    super.key,
    required this.options,
    this.displayStringForOption = _defaultStringFor,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.onChanged,
    this.placeholder = '',
    this.fieldSemanticLabel,
    this.semanticLabel,
    this.semanticState = SemanticState.empty,
    this.onSelect,
    this.maxVisible = 6,
  });

  /// Source options matched against the current field text.
  final List<T> options;

  /// Maps an option to the text shown in the dropdown and filled into the
  /// field. Defaults to `option.toString()`.
  final String Function(T option) displayStringForOption;

  /// Text controller for the underlying input.
  final TextEditingController? controller;

  /// Focus node used by the underlying input.
  final FocusNode? focusNode;

  /// Whether the input should request focus when mounted.
  final bool autofocus;

  /// Called with the new text on every edit, including programmatic
  /// [controller] changes. See [TextInput.onChanged].
  final void Function(String text)? onChanged;

  /// Hint text passed to the underlying [TextInput].
  final String placeholder;

  /// Stable label for the underlying text field in semantic snapshots.
  ///
  /// Defaults to [placeholder] when provided. This is separate from
  /// [semanticLabel], which names the suggestion menu.
  final String? fieldSemanticLabel;

  /// Stable label for the suggestion menu in semantic snapshots.
  ///
  /// Defaults to [placeholder] when provided. Use this when tests, debug tools,
  /// prompt fallback, or future adapters need to refer to the suggestion menu
  /// independently from the current query text.
  final String? semanticLabel;

  /// Extra semantic state merged into the underlying text-field node.
  final SemanticState semanticState;

  /// Called with the selected option when the user picks a suggestion.
  final void Function(T value)? onSelect;

  /// Maximum visible suggestion rows before the list scrolls.
  final int maxVisible;

  static String _defaultStringFor(Object option) => option.toString();

  @override
  State<Autocomplete<T>> createState() => _AutocompleteState<T>();
}

class _AutocompleteState<T extends Object> extends State<Autocomplete<T>> {
  static final TextEditingKeymap _textKeymap = TextEditingKeymap(
    List<TextEditingKeyBinding>.unmodifiable(
      TextEditingKeymap.defaultSingleLine.bindings.where(
        (binding) => binding.action != TextEditingKeyAction.submit,
      ),
    ),
  );

  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;

  final AnchorLink _link = AnchorLink();
  final ListController _list = ListController(selectedIndex: 0);
  FocusManager? _manager;
  OverlayEntry? _entry;
  List<T> _filtered = const [];
  String _lastQuery = '';

  /// The text just filled in by a pick; suppresses suggestions until the
  /// text changes away from it, so a pick doesn't immediately re-suggest
  /// itself (e.g. on refocus).
  String? _justPicked;

  /// Query explicitly dismissed with Escape or the semantic close action.
  /// Parent rebuilds must not reopen it until the query changes or a new focus
  /// session starts.
  String? _dismissedQuery;

  // Captured from the in-tree theme on each build; the dropdown lives in
  // an Overlay (outside this subtree) so it can't read the theme itself.
  CellStyle _selectionStyle = const CellStyle(inverse: true);
  BorderStyle _borderStyle = BorderStyle.rounded;

  String _display(T option) => widget.displayStringForOption(option);

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _ownsController = widget.controller == null;
    _lastQuery = _controller.text;
    _controller.addListener(_onChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'Autocomplete');
    _ownsFocusNode = widget.focusNode == null;
    _refreshMatches(resetSelection: true);
  }

  @override
  void didUpdateWidget(Autocomplete<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = widget.controller != oldWidget.controller;
    if (controllerChanged) {
      final oldController = _controller;
      final disposeOldController = _ownsController;
      oldController.removeListener(_onChange);
      _controller = widget.controller ?? TextEditingController();
      _ownsController = widget.controller == null;
      _lastQuery = _controller.text;
      _justPicked = null;
      _dismissedQuery = null;
      _controller.addListener(_onChange);
      if (disposeOldController) oldController.dispose();
    }
    if (widget.focusNode != oldWidget.focusNode) {
      final oldFocusNode = _focusNode;
      final disposeOldFocusNode = _ownsFocusNode;
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'Autocomplete');
      _ownsFocusNode = widget.focusNode == null;
      _dismissedQuery = null;
      if (disposeOldFocusNode) oldFocusNode.dispose();
    }

    // Re-read the source on every widget update. This handles both a replaced
    // options list and a caller mutating a retained list before rebuilding.
    _refreshMatches(resetSelection: controllerChanged);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final manager = Focus.maybeOf(context);
    if (!identical(manager, _manager)) {
      _manager?.removeListener(_sync);
      _manager = manager;
      _manager?.addListener(_sync);
    }
  }

  void _onChange() {
    final query = _controller.text;
    if (query == _lastQuery) return;
    _lastQuery = query;
    _dismissedQuery = null;
    if (query != _justPicked) _justPicked = null;
    _refreshMatches(resetSelection: true);
    _sync();
  }

  void _refreshMatches({required bool resetSelection}) {
    final query = _controller.text;
    final selectedIndex = _list.selectedIndex;
    final selectedOption =
        !resetSelection &&
            selectedIndex != null &&
            selectedIndex >= 0 &&
            selectedIndex < _filtered.length
        ? _filtered[selectedIndex]
        : null;
    _filtered = (query.isEmpty || query == _justPicked)
        ? const []
        : [
            for (final o in widget.options)
              if (_display(o).toLowerCase().contains(query.toLowerCase())) o,
          ];
    final preservedIndex = selectedOption == null
        ? -1
        : _filtered.indexOf(selectedOption);
    _list.selectedIndex = _filtered.isEmpty
        ? null
        : preservedIndex >= 0
        ? preservedIndex
        : 0;
  }

  /// Opens, refreshes, or closes the dropdown to match the current
  /// matches + focus.
  void _sync() {
    if (!_focusNode.hasFocus) {
      _dismissedQuery = null;
      _close();
      return;
    }
    final shouldOpen =
        _filtered.isNotEmpty && _dismissedQuery != _controller.text;
    if (!shouldOpen) {
      _close();
      return;
    }
    if (_entry == null) {
      final entry = OverlayEntry(
        builder: (_) => Follower(link: _link, child: _suggestions()),
      );
      _entry = entry;
      Overlay.of(context).insert(entry);
    } else {
      _entry!.markNeedsBuild();
    }
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  void _dismiss() {
    _dismissedQuery = _controller.text;
    _close();
  }

  void _move(int delta) {
    if (_filtered.isEmpty) return;
    final current = _list.selectedIndex ?? 0;
    final n = _filtered.length;
    // Wrap like fzf / gum filter — Up from the first item lands on the last.
    _list.selectedIndex = ((current + delta) % n + n) % n;
    _entry?.markNeedsBuild();
  }

  void _pick() {
    if (_entry == null) return;
    final i = _list.selectedIndex;
    if (i == null || i < 0 || i >= _filtered.length) return;
    final option = _filtered[i];
    final text = _display(option);
    _justPicked = text; // set before mutating text so _onChange suppresses
    _controller.text = text;
    _controller.caretOffset = text.length;
    _close();
    widget.onSelect?.call(option);
  }

  Widget _suggestions() {
    var width = 0;
    for (final o in _filtered) {
      final len = sanitizeOptionLabel(_display(o)).length;
      if (len > width) width = len;
    }
    final height = _filtered.length > widget.maxVisible
        ? widget.maxVisible
        : _filtered.length;
    final label =
        widget.semanticLabel ??
        (widget.placeholder.isEmpty ? null : widget.placeholder);
    return Semantics(
      role: SemanticRole.menu,
      label: label,
      focused: _focusNode.hasFocus,
      expanded: true,
      actions: const <SemanticAction>{
        SemanticAction.focus,
        SemanticAction.close,
      },
      state: SemanticState({
        'menuDepth': 0,
        'menuItemCount': _filtered.length,
        'selectedKey': _list.selectedIndex,
        'completionQuery': _controller.text,
      }),
      onAction: (action) {
        switch (action) {
          case SemanticAction.focus:
            _focusNode.requestFocus();
            return;
          case SemanticAction.close:
            _dismiss();
            return;
          case _:
            return;
        }
      },
      child: Container(
        border: BoxBorder(style: _borderStyle),
        child: SizedBox(
          width: width + 2,
          height: height,
          child: ListView.builder(
            controller: _list,
            selectionActive: true,
            itemCount: _filtered.length,
            itemBuilder: (_, i, selected) {
              final label = sanitizeOptionLabel(_display(_filtered[i]));
              return Semantics(
                role: SemanticRole.menuItem,
                label: label,
                value: label,
                focused: _focusNode.hasFocus && selected,
                selected: selected,
                actions: const <SemanticAction>{
                  SemanticAction.select,
                  SemanticAction.activate,
                },
                state: SemanticState({
                  'menuDepth': 0,
                  'menuItemIndex': i,
                  'menuItemPosition': i + 1,
                  'menuItemCount': _filtered.length,
                  'entryKind': 'suggestion',
                  'completionQuery': _controller.text,
                }),
                onAction: (action) {
                  switch (action) {
                    case SemanticAction.select:
                    case SemanticAction.activate:
                      _list.selectedIndex = i;
                      _pick();
                      return;
                    case _:
                      return;
                  }
                },
                // Click a suggestion to accept it — the same select+pick the
                // keyboard's Tab/Enter performs.
                child: GestureDetector(
                  onTap: () {
                    _list.selectedIndex = i;
                    _pick();
                  },
                  child: Text(
                    '${selected ? '› ' : '  '}$label',
                    style: selected ? _selectionStyle : CellStyle.empty,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _close();
    _manager?.removeListener(_sync);
    _controller.removeListener(_onChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _selectionStyle = theme.selectionStyle;
    _borderStyle = theme.borderStyle;
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyChord.up,
          onEvent: (event) {
            if (_entry == null) {
              event.bubble();
              return;
            }
            _move(-1);
          },
          hideFromHintBar: true,
        ),
        KeyBinding(
          KeyChord.down,
          onEvent: (event) {
            if (_entry == null) {
              event.bubble();
              return;
            }
            _move(1);
          },
          hideFromHintBar: true,
        ),
        KeyBinding(
          KeyChord.escape,
          onEvent: (event) {
            if (_entry == null) {
              event.bubble();
              return;
            }
            _dismiss();
          },
          hideFromHintBar: true,
        ),
        // TextInput's local keymap intentionally leaves Enter unresolved so
        // this binding can accept a visible suggestion or bubble when the menu
        // is closed. A dismissed menu must never submit a hidden row.
        KeyBinding(
          KeyChord.enter,
          onEvent: (event) {
            if (_entry == null) {
              event.bubble();
              return;
            }
            _pick();
          },
          hideFromHintBar: true,
        ),
        // Tab accepts the highlighted suggestion when the menu is open — the
        // dominant shell/fzf completion convention. When closed, Tab bubbles
        // so it still moves focus between widgets.
        KeyBinding(
          KeyChord.tab,
          onEvent: (event) {
            if (_entry == null) {
              event.bubble();
              return;
            }
            _pick();
          },
          hideFromHintBar: true,
        ),
      ],
      child: Anchor(
        link: _link,
        child: TextInput(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          onChanged: widget.onChanged,
          placeholder: widget.placeholder,
          semanticLabel: widget.fieldSemanticLabel,
          semanticState: widget.semanticState,
          keymap: _textKeymap,
        ),
      ),
    );
  }
}
