import 'package:fleury/fleury_host.dart';

/// A grid of color swatches. The currently-selected swatch is bordered
/// with the theme's focus style; arrow chords move between cells; Enter
/// confirms (selection already committed on each move, like
/// `CalendarHeatmap`'s navigation pattern).
///
/// Defaults to the 16 base ANSI colors laid out in 2 rows × 8 cols.
/// Pass [colors] for a custom palette (e.g. a 256-color picker, brand
/// colors, theme variants) and [columns] to control the grid shape.
///
/// ```dart
/// ColorPicker(
///   value: const AnsiColor(4),
///   onChanged: (c) => setState(() => accent = c),
/// )
/// ```
///
/// Passing null for [onChanged] disables the picker.
class ColorPicker extends StatefulWidget {
  const ColorPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.colors,
    this.columns = 8,
    this.swatchWidth = 3,
    this.semanticLabel = 'Colors',
    this.semanticColorLabelBuilder,
    this.focusNode,
    this.autofocus = false,
  }) : assert(columns >= 1, 'columns must be >= 1'),
       assert(swatchWidth >= 1, 'swatchWidth must be >= 1');

  /// Currently-selected color. The first matching entry in [colors] (or
  /// the default palette) becomes the highlighted cell.
  final Color value;

  /// Called with the new color when the cursor moves or on Enter.
  final void Function(Color color)? onChanged;

  /// Palette to pick from. `null` uses the 16 base ANSI colors.
  final List<Color>? colors;

  /// Grid width — palette cells wrap after this many. Default 8 (matches
  /// the natural split of the 16-color ANSI palette into 2 × 8).
  final int columns;

  /// Cell width per swatch (≥ 1). Wider swatches read more clearly at
  /// the cost of horizontal space.
  final int swatchWidth;

  /// Label exposed through the semantic app graph for the picker.
  final String semanticLabel;

  /// Optional semantic label builder for custom palette entries.
  final String Function(Color color, int index)? semanticColorLabelBuilder;

  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> implements TextInputClaimant {
  late FocusNode _node;
  bool _owns = false;

  /// The highlighted candidate — where the keyboard cursor sits. Arrows move
  /// this *without* committing; Enter / Space / a click commit it to
  /// [widget.value]. Separating preview from commit is what lets you browse the
  /// palette and Tab away without changing the value.
  int _cursor = 0;

  /// The committed colour when focus was gained, so Esc can cancel back to it.
  Color? _initial;

  /// Tracks focus transitions in [build] (FocusNode has no listener API) so we
  /// can snapshot [_initial] the moment the picker gains focus.
  bool _wasFocused = false;

  /// Anchor + overlay for the `#` hex-entry popover.
  final AnchorLink _link = AnchorLink();
  OverlayEntry? _hexEntry;

  bool get _enabled => widget.onChanged != null;

  // The 16 standard ANSI colors. Indices 0..15 match the terminal's
  // base palette: 0-7 normal, 8-15 bright.
  static const _ansi16 = <Color>[
    AnsiColor(0),
    AnsiColor(1),
    AnsiColor(2),
    AnsiColor(3),
    AnsiColor(4),
    AnsiColor(5),
    AnsiColor(6),
    AnsiColor(7),
    AnsiColor(8),
    AnsiColor(9),
    AnsiColor(10),
    AnsiColor(11),
    AnsiColor(12),
    AnsiColor(13),
    AnsiColor(14),
    AnsiColor(15),
  ];

  List<Color> get _palette => widget.colors ?? _ansi16;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode(debugLabel: 'color-picker');
    _node.textInputClaimant = this;
    _owns = widget.focusNode == null;
    _cursor = _indexOf(widget.value);
  }

  @override
  void didUpdateWidget(ColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _node.textInputClaimant = null;
      if (_owns) _node.dispose();
      _node = widget.focusNode ?? FocusNode(debugLabel: 'color-picker');
      _node.textInputClaimant = this;
      _owns = widget.focusNode == null;
    }
    // Follow an externally-driven value change while not actively browsing.
    if (widget.value != oldWidget.value && !_node.hasFocus) {
      _cursor = _indexOf(widget.value);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Focus.maybeOf(context);
  }

  @override
  void dispose() {
    _hexEntry?.remove();
    _node.textInputClaimant = null;
    if (_owns) _node.dispose();
    super.dispose();
  }

  int _indexOf(Color color) {
    final i = _palette.indexOf(color);
    return i >= 0 ? i : 0;
  }

  int get _currentIndex => _indexOf(widget.value);

  /// Moves the preview cursor to [index] without committing.
  void _moveCursor(int index) {
    if (!_enabled || index < 0 || index >= _palette.length) return;
    setState(() => _cursor = index);
  }

  /// Commits the cursor's colour — the "lock in" Enter / Space / a click do.
  void _commit() {
    if (!_enabled || _cursor < 0 || _cursor >= _palette.length) return;
    final color = _palette[_cursor];
    if (color != widget.value) widget.onChanged!(color);
  }

  /// Esc: abandon the in-progress browse, restoring the colour (and cursor)
  /// from when focus was gained.
  void _cancel() {
    final initial = _initial ?? widget.value;
    setState(() => _cursor = _indexOf(initial));
    if (_enabled && initial != widget.value) widget.onChanged!(initial);
  }

  void _selectIndex(int index) {
    if (!_enabled || index < 0 || index >= _palette.length) return;
    _node.requestFocus();
    setState(() => _cursor = index);
    _commit();
  }

  void _handlePickerAction(SemanticAction action) {
    switch (action) {
      case SemanticAction.focus:
      case SemanticAction.navigate:
        _node.requestFocus();
        setState(() {});
        return;
      case _:
        return;
    }
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (!_enabled) return KeyEventResult.ignored;
    final idx = _cursor;
    final cols = widget.columns;
    final n = _palette.length;
    switch (event.keyCode) {
      // Arrows move the preview cursor; at the grid edge they bubble so
      // directional focus traversal carries you out of the picker (the same
      // moveOrEscape convention RangeSlider/DatePicker use).
      case KeyCode.arrowLeft:
        return moveOrEscape(
          atEdge: idx % cols == 0,
          move: () => _moveCursor(idx - 1),
        );
      case KeyCode.arrowRight:
        return moveOrEscape(
          atEdge: idx + 1 >= n || (idx + 1) % cols == 0,
          move: () => _moveCursor(idx + 1),
        );
      case KeyCode.arrowUp:
        return moveOrEscape(
          atEdge: idx - cols < 0,
          move: () => _moveCursor(idx - cols),
        );
      case KeyCode.arrowDown:
        return moveOrEscape(
          atEdge: idx + cols >= n,
          move: () => _moveCursor(idx + cols),
        );
      case KeyCode.home:
        _moveCursor(0);
        return KeyEventResult.handled;
      case KeyCode.end:
        _moveCursor(n - 1);
        return KeyEventResult.handled;
      case KeyCode.enter:
        _commit(); // lock in the highlighted colour
        return KeyEventResult.handled;
      case KeyCode.escape:
        _cancel();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  KeyEventResult onTextInput(String text) {
    if (!_enabled) return KeyEventResult.ignored;
    if (text == ' ') {
      _commit(); // Space also locks in the highlighted colour
      return KeyEventResult.handled;
    }
    if (text == '#') {
      _openHex();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  KeyEventResult onPaste(String text) => KeyEventResult.ignored;

  /// Opens a small popover anchored to the picker for typing a hex code.
  void _openHex() {
    if (_hexEntry != null) return;
    final manager = Focus.of(context);
    final overlay = Overlay.of(context);
    final theme = Theme.of(context);
    final entry = OverlayEntry(
      builder: (_) => Follower(
        link: _link,
        placement: FollowerPlacement.below,
        child: _HexEntry(
          initial: widget.value.toRgb(),
          background: theme.colorScheme.background,
          borderStyle: theme.borderStyle,
          onSubmit: (color) {
            _closeHex();
            if (_enabled && color != widget.value) widget.onChanged!(color);
          },
          onDismiss: _closeHex,
        ),
      ),
    );
    _hexEntry = entry;
    manager.requestFocus(null); // hand focus to the popover's autofocus field
    overlay.insert(entry);
  }

  void _closeHex() {
    _hexEntry?.remove();
    _hexEntry = null;
    if (mounted) _node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = _enabled;
    final focused = enabled && _node.hasFocus;
    // Snapshot the committed colour at focus-in (so Esc can restore it) and
    // drop it on blur — tracked here since FocusNode exposes no listener.
    if (focused && !_wasFocused) _initial = widget.value;
    if (!focused) _initial = null;
    _wasFocused = focused;
    final disabledStyle = theme.mutedStyle;
    final selectedIdx = _currentIndex;
    final cols = widget.columns;
    final palette = _palette;

    final rows = <Widget>[];
    for (var r = 0; r * cols < palette.length; r++) {
      final cells = <Widget>[];
      for (var c = 0; c < cols && r * cols + c < palette.length; c++) {
        final idx = r * cols + c;
        final color = palette[idx];
        // The cursor (candidate) gets bright `[ ]` brackets; the committed
        // colour, when the cursor has moved off it, gets dim `‹ ›` markers so
        // you can see your locked-in pick while browsing. Plain swatches get a
        // one-cell gap so the grid breathes.
        final isCursor = idx == _cursor;
        final isCommitted = idx == selectedIdx;
        final swatch = Text(
          '█' * widget.swatchWidth,
          style: CellStyle(
            foreground: color,
          ).merge(enabled ? CellStyle.empty : disabledStyle),
        );
        final markStyle = !enabled
            ? disabledStyle
            : isCursor
            ? (focused ? theme.focusedStyle : theme.selectionStyle)
            : theme.mutedStyle;
        final swatchParts = <Widget>[];
        if (isCursor || isCommitted) {
          swatchParts.add(Text(isCursor ? '[' : '‹', style: markStyle));
          swatchParts.add(swatch);
          swatchParts.add(Text(isCursor ? ']' : '›', style: markStyle));
        } else {
          swatchParts.add(const Text(' '));
          swatchParts.add(swatch);
          swatchParts.add(const Text(' '));
        }
        cells.add(
          Semantics(
            role: SemanticRole.radio,
            label: _colorLabel(color, idx),
            value: _colorValue(color),
            selected: isCommitted,
            checked: isCommitted,
            enabled: enabled,
            actions: enabled
                ? const {SemanticAction.select, SemanticAction.activate}
                : const <SemanticAction>{},
            onAction: enabled
                ? (action) {
                    switch (action) {
                      case SemanticAction.select:
                      case SemanticAction.activate:
                        _selectIndex(idx);
                        return;
                      case _:
                        return;
                    }
                  }
                : null,
            state: SemanticState({
              'colorIndex': idx,
              'colorPosition': idx + 1,
              'colorCount': palette.length,
              'colorKind': _colorKind(color),
              ..._colorComponents(color),
            }),
            // Click a swatch to select it (focus first, so the arrow keys keep
            // working afterward). The whole-body tap below only grabs focus.
            child: enabled
                ? GestureDetector(
                    onTap: () {
                      _node.requestFocus();
                      _selectIndex(idx);
                    },
                    child: Row(children: swatchParts),
                  )
                : Row(children: swatchParts),
          ),
        );
      }
      rows.add(Row(children: cells));
    }

    final rowCount = (palette.length + cols - 1) ~/ cols;
    final visibleColumns = palette.length < cols ? palette.length : cols;
    final selectedColor = palette.isEmpty ? null : palette[selectedIdx];
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...rows,
        // Spell out the model while focused: navigating only previews; you
        // commit with Enter/Space (or a click) and back out with Esc.
        if (focused)
          Text(
            '↑↓←→ preview · Enter/Space lock in · Esc cancel · # hex',
            style: theme.mutedStyle,
          ),
      ],
    );
    if (!enabled) {
      return Semantics(
        role: SemanticRole.list,
        label: widget.semanticLabel,
        value: selectedColor == null
            ? null
            : _colorLabel(selectedColor, selectedIdx),
        enabled: false,
        state: SemanticState({
          'collectionRowCount': rowCount,
          'collectionColumnCount': visibleColumns,
          'colorCount': palette.length,
          if (selectedColor != null) ...{
            'selectedIndex': selectedIdx,
            'selectedKey': _colorValue(selectedColor),
            'selectedColorLabel': _colorLabel(selectedColor, selectedIdx),
            'selectedColorKind': _colorKind(selectedColor),
          },
        }),
        child: body,
      );
    }
    return Semantics(
      role: SemanticRole.list,
      label: widget.semanticLabel,
      value: selectedColor == null
          ? null
          : _colorLabel(selectedColor, selectedIdx),
      focused: focused,
      actions: const {SemanticAction.focus, SemanticAction.navigate},
      onAction: _handlePickerAction,
      state: SemanticState({
        'collectionRowCount': rowCount,
        'collectionColumnCount': visibleColumns,
        'colorCount': palette.length,
        if (selectedColor != null) ...{
          'selectedIndex': selectedIdx,
          'selectedKey': _colorValue(selectedColor),
          'selectedColorLabel': _colorLabel(selectedColor, selectedIdx),
          'selectedColorKind': _colorKind(selectedColor),
        },
      }),
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        onKey: _onKey,
        child: Anchor(
          link: _link,
          child: GestureDetector(
            onTap: () => _node.requestFocus(),
            child: body,
          ),
        ),
      ),
    );
  }

  String _colorLabel(Color color, int index) {
    final builder = widget.semanticColorLabelBuilder;
    if (builder != null) return sanitizeForDisplay(builder(color, index));
    return _defaultColorLabel(color);
  }
}

String _defaultColorLabel(Color color) {
  return switch (color) {
    AnsiColor(:final index) => 'ANSI color $index ${_ansiColorNames[index]}',
    IndexedColor(:final index) => 'Indexed color $index',
    RgbColor(:final r, :final g, :final b) => 'RGB color $r $g $b',
  };
}

String _colorValue(Color color) {
  return switch (color) {
    AnsiColor(:final index) => 'ansi:$index',
    IndexedColor(:final index) => 'indexed:$index',
    RgbColor(:final r, :final g, :final b) => 'rgb:$r,$g,$b',
  };
}

String _colorKind(Color color) {
  return switch (color) {
    AnsiColor() => 'ansi',
    IndexedColor() => 'indexed',
    RgbColor() => 'rgb',
  };
}

Map<String, Object?> _colorComponents(Color color) {
  return switch (color) {
    AnsiColor(:final index) => <String, Object?>{'ansiColorIndex': index},
    IndexedColor(:final index) => <String, Object?>{'indexedColorIndex': index},
    RgbColor(:final r, :final g, :final b) => <String, Object?>{
      'red': r,
      'green': g,
      'blue': b,
    },
  };
}

/// A small popover, anchored under the picker, for typing a hex colour code.
/// Enter applies it as an [RgbColor]; Esc dismisses without changing anything.
class _HexEntry extends StatefulWidget {
  const _HexEntry({
    required this.initial,
    required this.background,
    required this.borderStyle,
    required this.onSubmit,
    required this.onDismiss,
  });

  final RgbColor initial;
  final Color? background;
  final BorderStyle borderStyle;
  final void Function(Color color) onSubmit;
  final void Function() onDismiss;

  @override
  State<_HexEntry> createState() => _HexEntryState();
}

class _HexEntryState extends State<_HexEntry> {
  late final TextEditingController _controller;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _hexOf(widget.initial));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final color = _parseHex(text);
    if (color == null) {
      setState(() => _invalid = true);
      return;
    }
    widget.onSubmit(color);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: widget.background,
      border: BoxBorder(style: widget.borderStyle),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: SizedBox(
        width: 12,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _invalid ? 'Use RRGGBB' : 'Hex code',
              style: _invalid
                  ? CellStyle(foreground: theme.colorScheme.error)
                  : theme.mutedStyle,
            ),
            Row(
              children: [
                Text('#', style: theme.mutedStyle),
                Expanded(
                  child: TextInput(
                    controller: _controller,
                    autofocus: true,
                    placeholder: 'RRGGBB',
                    onSubmit: _submit,
                    onEscape: widget.onDismiss,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _hexOf(RgbColor c) =>
    c.r.toRadixString(16).padLeft(2, '0') +
    c.g.toRadixString(16).padLeft(2, '0') +
    c.b.toRadixString(16).padLeft(2, '0');

/// Parses `#RRGGBB`, `RRGGBB`, or 3-digit shorthand into an [RgbColor].
Color? _parseHex(String text) {
  var s = text.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 3) {
    s = s.split('').map((ch) => '$ch$ch').join();
  }
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return null;
  return RgbColor((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
}

const _ansiColorNames = <String>[
  'black',
  'red',
  'green',
  'yellow',
  'blue',
  'magenta',
  'cyan',
  'white',
  'bright black',
  'bright red',
  'bright green',
  'bright yellow',
  'bright blue',
  'bright magenta',
  'bright cyan',
  'bright white',
];
