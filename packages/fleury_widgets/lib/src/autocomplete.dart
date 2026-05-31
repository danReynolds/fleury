import 'package:fleury/fleury.dart';

/// A text field with an anchored, live-filtered suggestion list.
///
/// As the user types, options whose display string matches the text
/// (case-insensitive substring) appear in a dropdown anchored just below
/// the field — via the [Anchor]/[Follower] primitive, so it floats over
/// content and stays on screen. The field keeps focus throughout: Up/Down
/// move the highlight, Enter fills the field with the highlighted option
/// (and calls [onSelected]), Esc closes the dropdown.
///
/// Options can be any type [T]; [displayStringForOption] maps each to the
/// text shown and matched against (defaults to `toString()`). `onSelected`
/// hands back the chosen option itself, not just its string.
class Autocomplete<T extends Object> extends StatefulWidget {
  const Autocomplete({
    super.key,
    required this.options,
    this.displayStringForOption = _defaultStringFor,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.onSelected,
    this.maxVisible = 6,
  });

  final List<T> options;

  /// Maps an option to the text shown in the dropdown and filled into the
  /// field. Defaults to `option.toString()`.
  final String Function(T option) displayStringForOption;

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final void Function(T value)? onSelected;
  final int maxVisible;

  static String _defaultStringFor(Object option) => option.toString();

  @override
  State<Autocomplete<T>> createState() => _AutocompleteState<T>();
}

class _AutocompleteState<T extends Object> extends State<Autocomplete<T>> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;

  final AnchorLink _link = AnchorLink();
  final ListController _list = ListController(selectedIndex: 0);
  FocusManager? _manager;
  OverlayEntry? _entry;
  List<T> _filtered = const [];

  /// The text just filled in by a pick; suppresses suggestions until the
  /// text changes away from it, so a pick doesn't immediately re-suggest
  /// itself (e.g. on refocus).
  String? _justPicked;

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
    _controller.addListener(_onChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'Autocomplete');
    _ownsFocusNode = widget.focusNode == null;
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
    if (query != _justPicked) _justPicked = null;
    _filtered = (query.isEmpty || query == _justPicked)
        ? const []
        : [
            for (final o in widget.options)
              if (_display(o).toLowerCase().contains(query.toLowerCase())) o,
          ];
    _list.selectedIndex = _filtered.isEmpty ? null : 0;
    _sync();
  }

  /// Opens, refreshes, or closes the dropdown to match the current
  /// matches + focus.
  void _sync() {
    final shouldOpen = _focusNode.hasFocus && _filtered.isNotEmpty;
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

  void _move(int delta) {
    if (_filtered.isEmpty) return;
    final current = _list.selectedIndex ?? 0;
    _list.selectedIndex = (current + delta).clamp(0, _filtered.length - 1);
    _entry?.markNeedsBuild();
  }

  void _pick() {
    final i = _list.selectedIndex;
    if (i == null || i < 0 || i >= _filtered.length) return;
    final option = _filtered[i];
    final text = _display(option);
    _justPicked = text; // set before mutating text so _onChange suppresses
    _controller.text = text;
    _controller.selection = text.length;
    _close();
    widget.onSelected?.call(option);
  }

  Widget _suggestions() {
    var width = 0;
    for (final o in _filtered) {
      final len = _display(o).length;
      if (len > width) width = len;
    }
    final height = _filtered.length > widget.maxVisible
        ? widget.maxVisible
        : _filtered.length;
    return Container(
      border: BoxBorder(style: _borderStyle),
      child: SizedBox(
        width: width + 2,
        height: height,
        child: ListView.builder(
          controller: _list,
          itemCount: _filtered.length,
          itemBuilder: (_, i, selected) => Text(
            '${selected ? '› ' : '  '}${_display(_filtered[i])}',
            style: selected ? _selectionStyle : CellStyle.empty,
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
            _close();
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
          onSubmit: (_) => _pick(),
        ),
      ),
    );
  }
}
