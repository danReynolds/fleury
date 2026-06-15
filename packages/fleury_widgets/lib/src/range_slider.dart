import 'package:fleury/fleury.dart';

/// Which of the two handles a [RangeSlider] is editing.
enum _ActiveHandle { low, high }

/// A two-handle slider for picking a numeric `(low, high)` range. The
/// selected interval is shown as a filled bar on the track; the inactive
/// region uses a dim block. Tab swaps the active handle; Left/Right move
/// it by [step]; PageUp/PageDown by [largeStep]; Home/End jump to [min]/
/// [max] (still clamped so the handles can't cross).
///
/// Controlled — hold the values yourself and update them from [onChanged].
/// Passing null for [onChanged] disables the slider.
///
/// ```dart
/// RangeSlider(
///   values: (10, 80),
///   min: 0,
///   max: 100,
///   onChanged: (r) => setState(() => range = r),
/// )
/// ```
class RangeSlider extends StatefulWidget {
  const RangeSlider({
    super.key,
    required this.values,
    required this.onChanged,
    required this.min,
    required this.max,
    this.step = 1,
    this.largeStep = 10,
    this.label,
    this.focusNode,
    this.autofocus = false,
  }) : assert(min < max, 'min must be < max'),
       assert(step > 0, 'step must be > 0');

  /// `(low, high)` in data space. `low <= high` is enforced — values
  /// passed reversed will be normalized at paint time.
  final (num low, num high) values;

  /// Called with the new `(low, high)` tuple when either handle moves.
  final void Function((num low, num high) values)? onChanged;

  /// Lower and upper bounds of the slider's range.
  final num min;
  final num max;

  /// Granularity of arrow-key moves.
  final num step;

  /// Granularity of PageUp/PageDown moves.
  final num largeStep;

  /// Optional label exposed through the semantic app graph.
  final String? label;

  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<RangeSlider> createState() => _RangeSliderState();
}

class _RangeSliderState extends State<RangeSlider> {
  late FocusNode _node;
  bool _owns = false;
  _ActiveHandle _active = _ActiveHandle.low;

  bool get _enabled => widget.onChanged != null;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode(debugLabel: 'range-slider');
    _owns = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(RangeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      if (_owns) _node.dispose();
      _node = widget.focusNode ?? FocusNode(debugLabel: 'range-slider');
      _owns = widget.focusNode == null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Focus.maybeOf(context); // rebuild on focus change
  }

  @override
  void dispose() {
    if (_owns) _node.dispose();
    super.dispose();
  }

  (num, num) get _normalized {
    final (a, b) = widget.values;
    return a <= b ? (a, b) : (b, a);
  }

  void _nudge(num delta) {
    if (!_enabled) return;
    final (lo, hi) = _normalized;
    if (_active == _ActiveHandle.low) {
      final next = (lo + delta).clamp(widget.min, hi);
      if (next != lo) widget.onChanged!((next, hi));
    } else {
      final next = (hi + delta).clamp(lo, widget.max);
      if (next != hi) widget.onChanged!((lo, next));
    }
  }

  void _jump(num target) {
    if (!_enabled) return;
    final (lo, hi) = _normalized;
    if (_active == _ActiveHandle.low) {
      final next = target.clamp(widget.min, hi);
      if (next != lo) widget.onChanged!((next, hi));
    } else {
      final next = target.clamp(lo, widget.max);
      if (next != hi) widget.onChanged!((lo, next));
    }
  }

  /// Whether nudging the active handle by [delta] would actually move it
  /// (i.e. it is not pinned against its bound).
  bool _canNudge(num delta) {
    final (lo, hi) = _normalized;
    return _active == _ActiveHandle.low
        ? (lo + delta).clamp(widget.min, hi) != lo
        : (hi + delta).clamp(lo, widget.max) != hi;
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (!_enabled) return KeyEventResult.ignored;
    switch (event.keyCode) {
      // Left/Right adjust the active handle and bubble (escape) once it's
      // pinned against its bound, so the arrows that drive the slider also
      // carry focus off it.
      case KeyCode.arrowLeft:
        return moveOrEscape(
          atEdge: !_canNudge(-widget.step),
          move: () => _nudge(-widget.step),
        );
      case KeyCode.arrowRight:
        return moveOrEscape(
          atEdge: !_canNudge(widget.step),
          move: () => _nudge(widget.step),
        );
      // The two handles form a 2-cell vertical axis (low below, high above):
      // Up selects the high handle, Down the low one, and each bubbles once
      // already at that end — so Up/Down both switch handles AND escape
      // vertically, and Tab is free to move between widgets like everywhere
      // else.
      case KeyCode.arrowUp:
        return moveOrEscape(
          atEdge: _active == _ActiveHandle.high,
          move: () => setState(() => _active = _ActiveHandle.high),
        );
      case KeyCode.arrowDown:
        return moveOrEscape(
          atEdge: _active == _ActiveHandle.low,
          move: () => setState(() => _active = _ActiveHandle.low),
        );
      case KeyCode.pageDown:
        _nudge(-widget.largeStep);
        return KeyEventResult.handled;
      case KeyCode.pageUp:
        _nudge(widget.largeStep);
        return KeyEventResult.handled;
      case KeyCode.home:
        _jump(widget.min);
        return KeyEventResult.handled;
      case KeyCode.end:
        _jump(widget.max);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = _enabled;
    final (lo, hi) = _normalized;
    final canDecrement = enabled && _active == _ActiveHandle.low
        ? lo > widget.min
        : enabled && hi > lo;
    final canIncrement = enabled && _active == _ActiveHandle.low
        ? lo < hi
        : enabled && hi < widget.max;
    final slider = _RawRangeSlider(
      values: _normalized,
      min: widget.min,
      max: widget.max,
      active: _active,
      focused: enabled && _node.hasFocus,
      selectedStyle: enabled
          ? CellStyle(foreground: theme.colorScheme.primary)
          : theme.mutedStyle,
      trackStyle: theme.mutedStyle,
    );
    if (!enabled) {
      return Semantics(
        role: SemanticRole.slider,
        label: widget.label,
        value: '$lo-$hi',
        enabled: false,
        state: SemanticState({
          'lowValue': lo,
          'highValue': hi,
          'min': widget.min,
          'max': widget.max,
          'step': widget.step,
          'largeStep': widget.largeStep,
          'activeHandle': _active.name,
          'canIncrement': false,
          'canDecrement': false,
        }),
        child: slider,
      );
    }
    return Semantics(
      role: SemanticRole.slider,
      label: widget.label,
      value: '$lo-$hi',
      focused: _node.hasFocus,
      actions: {
        SemanticAction.focus,
        if (canIncrement) SemanticAction.increment,
        if (canDecrement) SemanticAction.decrement,
      },
      state: SemanticState({
        'lowValue': lo,
        'highValue': hi,
        'min': widget.min,
        'max': widget.max,
        'step': widget.step,
        'largeStep': widget.largeStep,
        'activeHandle': _active.name,
        'canIncrement': canIncrement,
        'canDecrement': canDecrement,
      }),
      onAction: (action) {
        switch (action) {
          case SemanticAction.focus:
            _node.requestFocus();
            return;
          case SemanticAction.increment:
            _node.requestFocus();
            if (canIncrement) _nudge(widget.step);
            return;
          case SemanticAction.decrement:
            _node.requestFocus();
            if (canDecrement) _nudge(-widget.step);
            return;
          case _:
            return;
        }
      },
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        onKey: _onKey,
        child: slider,
      ),
    );
  }
}

class _RawRangeSlider extends LeafRenderObjectWidget {
  const _RawRangeSlider({
    required this.values,
    required this.min,
    required this.max,
    required this.active,
    required this.focused,
    required this.selectedStyle,
    required this.trackStyle,
  });

  final (num, num) values;
  final num min;
  final num max;
  final _ActiveHandle active;
  final bool focused;
  final CellStyle selectedStyle;
  final CellStyle trackStyle;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderRangeSlider(
    values: values,
    min: min,
    max: max,
    active: active,
    focused: focused,
    selectedStyle: selectedStyle,
    trackStyle: trackStyle,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderRangeSlider r,
  ) {
    r
      ..values = values
      ..rmin = min
      ..rmax = max
      ..active = active
      ..focused = focused
      ..selectedStyle = selectedStyle
      ..trackStyle = trackStyle;
  }
}

class _RenderRangeSlider extends RenderObject {
  _RenderRangeSlider({
    required (num, num) values,
    required num min,
    required num max,
    required _ActiveHandle active,
    required bool focused,
    required CellStyle selectedStyle,
    required CellStyle trackStyle,
  }) : _values = values,
       _min = min,
       _max = max,
       _active = active,
       _focused = focused,
       _selectedStyle = selectedStyle,
       _trackStyle = trackStyle;

  (num, num) _values;
  set values((num, num) v) {
    if (_values == v) return;
    _values = v;
    markNeedsPaintOnly();
  }

  num _min;
  set rmin(num v) {
    if (_min == v) return;
    _min = v;
    markNeedsPaintOnly();
  }

  num _max;
  set rmax(num v) {
    if (_max == v) return;
    _max = v;
    markNeedsPaintOnly();
  }

  _ActiveHandle _active;
  set active(_ActiveHandle v) {
    if (_active == v) return;
    _active = v;
    markNeedsPaintOnly();
  }

  bool _focused;
  set focused(bool v) {
    if (_focused == v) return;
    _focused = v;
    markNeedsPaintOnly();
  }

  CellStyle _selectedStyle;
  set selectedStyle(CellStyle v) {
    if (_selectedStyle == v) return;
    _selectedStyle = v;
    markNeedsPaintOnly();
  }

  CellStyle _trackStyle;
  set trackStyle(CellStyle v) {
    if (_trackStyle == v) return;
    _trackStyle = v;
    markNeedsPaintOnly();
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final cols = constraints.hasBoundedWidth ? constraints.maxCols! : 20;
    return constraints.constrain(CellSize(cols, 1));
  }

  @override
  int computeMaxIntrinsicHeight(int? width) => 1;

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final w = size.cols;
    if (w == 0 || size.rows == 0) return;
    if (offset.row < 0 || offset.row >= buffer.size.rows) return;

    final (lo, hi) = _values;
    final span = _max - _min;
    final loCol = ((lo - _min) / span * (w - 1)).round();
    final hiCol = ((hi - _min) / span * (w - 1)).round();
    const track = '─';
    const fill = '━';
    const handle = '●';
    const handleActive = '◉';

    for (var c = 0; c < w; c++) {
      final tgt = offset.col + c;
      if (tgt < 0 || tgt >= buffer.size.cols) continue;
      String glyph;
      CellStyle style;
      if (c == loCol || c == hiCol) {
        final isActive =
            _focused &&
            ((c == loCol && _active == _ActiveHandle.low) ||
                (c == hiCol && _active == _ActiveHandle.high));
        glyph = isActive ? handleActive : handle;
        style = _selectedStyle;
      } else if (c > loCol && c < hiCol) {
        glyph = fill;
        style = _selectedStyle;
      } else {
        glyph = track;
        style = _trackStyle;
      }
      buffer.writeGrapheme(CellOffset(tgt, offset.row), glyph, style: style);
    }
  }
}
