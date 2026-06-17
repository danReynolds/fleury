import 'package:fleury/fleury.dart';

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

class _ColorPickerState extends State<ColorPicker> {
  late FocusNode _node;
  bool _owns = false;

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
    _owns = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(ColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      if (_owns) _node.dispose();
      _node = widget.focusNode ?? FocusNode(debugLabel: 'color-picker');
      _owns = widget.focusNode == null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Focus.maybeOf(context);
  }

  @override
  void dispose() {
    if (_owns) _node.dispose();
    super.dispose();
  }

  int get _currentIndex {
    final i = _palette.indexOf(widget.value);
    return i >= 0 ? i : 0;
  }

  void _moveTo(int index) {
    if (!_enabled) return;
    if (index < 0 || index >= _palette.length) return;
    if (_palette[index] == widget.value) return;
    widget.onChanged!(_palette[index]);
  }

  void _selectIndex(int index) {
    if (!_enabled) return;
    if (index < 0 || index >= _palette.length) return;
    _node.requestFocus();
    _moveTo(index);
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
    final idx = _currentIndex;
    final cols = widget.columns;
    final n = _palette.length;
    switch (event.keyCode) {
      case KeyCode.arrowLeft:
        if (idx % cols == 0) return KeyEventResult.ignored;
        _moveTo(idx - 1);
        return KeyEventResult.handled;
      case KeyCode.arrowRight:
        if (idx + 1 >= n || (idx + 1) % cols == 0) {
          return KeyEventResult.ignored;
        }
        _moveTo(idx + 1);
        return KeyEventResult.handled;
      case KeyCode.arrowUp:
        if (idx - cols < 0) return KeyEventResult.ignored;
        _moveTo(idx - cols);
        return KeyEventResult.handled;
      case KeyCode.arrowDown:
        if (idx + cols >= n) return KeyEventResult.ignored;
        _moveTo(idx + cols);
        return KeyEventResult.handled;
      case KeyCode.home:
        _moveTo(0);
        return KeyEventResult.handled;
      case KeyCode.end:
        _moveTo(n - 1);
        return KeyEventResult.handled;
      case KeyCode.enter:
        // Already committed on each move — Enter just consumes.
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = _enabled;
    final focused = enabled && _node.hasFocus;
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
        final isSelected = idx == selectedIdx;
        // Selected cell: brackets around the swatch in focus style; non-
        // selected: plain swatch with a single-cell gap so the grid
        // breathes.
        final swatch = Text(
          '█' * widget.swatchWidth,
          style: CellStyle(
            foreground: color,
          ).merge(enabled ? CellStyle.empty : disabledStyle),
        );
        final swatchParts = <Widget>[];
        if (isSelected) {
          swatchParts.add(
            Text(
              '[',
              style: !enabled
                  ? disabledStyle
                  : focused
                  ? theme.focusedStyle
                  : theme.selectionStyle,
            ),
          );
          swatchParts.add(swatch);
          swatchParts.add(
            Text(
              ']',
              style: !enabled
                  ? disabledStyle
                  : focused
                  ? theme.focusedStyle
                  : theme.selectionStyle,
            ),
          );
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
            selected: isSelected,
            checked: isSelected,
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
      children: rows,
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
        child: GestureDetector(onTap: () => _node.requestFocus(), child: body),
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
