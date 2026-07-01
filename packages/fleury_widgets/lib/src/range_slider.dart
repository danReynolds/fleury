import 'package:fleury/fleury_core.dart';

/// Which of the two handles a [RangeSlider] is editing.
enum _ActiveHandle { low, high }

/// Painted track geometry: the render object writes it each paint and the
/// pointer handlers read it to map an absolute column → slider value (the
/// write-at-paint / read-elsewhere idiom shared with Scrollbar).
class _SliderGeometry {
  int left = 0;
  int width = 0;
}

/// A two-handle slider for picking a numeric `(low, high)` range. The
/// selected interval is a filled bar between a solid active handle (`●`)
/// and a hollow inactive one (`○`). Left/Right move between the two
/// handles (they sit low-left, high-right); Up/Down change the active
/// handle's value by [step], PageUp/PageDown by [largeStep], Home/End jump
/// to [min]/[max] (still clamped so the handles can't cross). Each arrow
/// bubbles at its edge so focus can leave the widget — Left/Right past the
/// outer handle, Up/Down once the value is pinned — and Tab is left free
/// for traversal.
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
    this.showValues = false,
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

  /// When true, renders a `low–high` readout above the track (the active
  /// handle's value is emphasized) and the `min`/`max` endpoints below it, so
  /// the numbers behind the bar are legible. Adds two rows of height.
  final bool showValues;

  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<RangeSlider> createState() => _RangeSliderState();
}

class _RangeSliderState extends State<RangeSlider> {
  late FocusNode _node;
  bool _owns = false;
  _ActiveHandle _active = _ActiveHandle.low;

  // Painted track geometry (written by the render object) and the handle a
  // press grabbed, so a drag keeps moving that handle even past the track edge.
  final _SliderGeometry _geom = _SliderGeometry();
  _ActiveHandle? _dragHandle;

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

  /// Sets one handle to an absolute [value] (the other stays put), clamped so
  /// the handles can't cross — used by click/drag, where the target isn't a
  /// relative nudge.
  void _setHandle(_ActiveHandle which, num value) {
    if (!_enabled) return;
    final (lo, hi) = _normalized;
    if (which == _ActiveHandle.low) {
      final next = value.clamp(widget.min, hi);
      if (next != lo) widget.onChanged!((next, hi));
    } else {
      final next = value.clamp(lo, widget.max);
      if (next != hi) widget.onChanged!((lo, next));
    }
  }

  /// The slider value under absolute column [col], snapped to the [step] grid.
  num _valueForColumn(int col) {
    final width = _geom.width;
    if (width <= 1) return widget.min;
    final local = (col - _geom.left).clamp(0, width - 1);
    final fraction = local / (width - 1);
    final raw = widget.min + fraction * (widget.max - widget.min);
    final steps = ((raw - widget.min) / widget.step).round();
    final snapped = widget.min + steps * widget.step;
    return snapped.clamp(widget.min, widget.max);
  }

  /// The handle whose painted column is nearest absolute column [col]; ties at
  /// the edges resolve to the handle on that side.
  _ActiveHandle _nearestHandle(int col) {
    final width = _geom.width;
    if (width <= 1) return _active;
    final (lo, hi) = _normalized;
    final span = widget.max - widget.min;
    final loCol = _geom.left + ((lo - widget.min) / span * (width - 1)).round();
    final hiCol = _geom.left + ((hi - widget.min) / span * (width - 1)).round();
    if (col <= loCol) return _ActiveHandle.low;
    if (col >= hiCol) return _ActiveHandle.high;
    return (col - loCol) <= (hiCol - col)
        ? _ActiveHandle.low
        : _ActiveHandle.high;
  }

  /// A press or drag-start: grab the nearest handle, make it active, and move
  /// it to the pressed value.
  void _grabAt(int col) {
    if (!_enabled) return;
    _node.requestFocus();
    final handle = _nearestHandle(col);
    _dragHandle = handle;
    if (_active != handle) setState(() => _active = handle);
    _setHandle(handle, _valueForColumn(col));
  }

  /// Continuing a drag: keep moving the grabbed handle (no re-pick), so a drag
  /// past the other handle doesn't hand off to it.
  void _dragTo(int col) {
    if (!_enabled) return;
    _setHandle(_dragHandle ?? _active, _valueForColumn(col));
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (!_enabled) return KeyEventResult.ignored;
    switch (event.keyCode) {
      // Up/Down adjust the active handle's value — the universal slider
      // convention (Up = increase, Down = decrease). They bubble (escape)
      // once the handle is pinned against its bound, so arrow-based focus
      // traversal can still pass through vertically.
      case KeyCode.arrowUp:
        return moveOrEscape(
          atEdge: !_canNudge(widget.step),
          move: () => _nudge(widget.step),
        );
      case KeyCode.arrowDown:
        return moveOrEscape(
          atEdge: !_canNudge(-widget.step),
          move: () => _nudge(-widget.step),
        );
      // Left/Right move between the two handles, which sit low-left and
      // high-right on the track. At the outer handle the arrow bubbles so
      // focus can leave the widget horizontally — Left past the low handle,
      // Right past the high one.
      case KeyCode.arrowLeft:
        return moveOrEscape(
          atEdge: _active == _ActiveHandle.low,
          move: () => setState(() => _active = _ActiveHandle.low),
        );
      case KeyCode.arrowRight:
        return moveOrEscape(
          atEdge: _active == _ActiveHandle.high,
          move: () => setState(() => _active = _ActiveHandle.high),
        );
      case KeyCode.pageUp:
        _nudge(widget.largeStep);
        return KeyEventResult.handled;
      case KeyCode.pageDown:
        _nudge(-widget.largeStep);
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
      geometry: _geom,
      selectedStyle: enabled
          ? CellStyle(foreground: theme.colorScheme.primary)
          : theme.mutedStyle,
      trackStyle: theme.mutedStyle,
    );
    if (!enabled) {
      return _decorate(
        context,
        Semantics(
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
        ),
      );
    }
    return _decorate(
      context,
      Semantics(
        role: SemanticRole.slider,
        label: widget.label,
        value: '$lo-$hi',
        focused: _node.hasFocus,
        actions: {
          SemanticAction.focus,
          if (canIncrement) SemanticAction.increment,
          if (canDecrement) SemanticAction.decrement,
          SemanticAction.setValue,
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
        // Set the *active* handle to an exact value (clamped so the handles can't
        // cross). Which handle is active is in `state['activeHandle']`; switch it
        // with Left/Right (press_key) before setting the other one.
        onSetValue: (payload) {
          final next = coerceSemanticNum(payload);
          if (next != null) _setHandle(_active, next);
        },
        child: Focus(
          focusNode: _node,
          autofocus: widget.autofocus,
          onKey: _onKey,
          // Click the track to move the nearest handle there; drag to slide it.
          // The drag is captured, so the handle keeps following past the ends.
          child: GestureDetector(
            // A press grabs the nearest handle; the drag (always preceded by the
            // press) then just slides that same grabbed handle.
            onTapDown: (col, _) => _grabAt(col),
            onDragStart: (col, _) => _dragTo(col),
            onDragUpdate: (col, _) => _dragTo(col),
            onDragEnd: () => _dragHandle = null,
            child: slider,
          ),
        ),
      ),
    );
  }

  /// Wraps the interactive track with a value readout and endpoint labels when
  /// [RangeSlider.showValues] is set; otherwise returns the track unchanged.
  Widget _decorate(BuildContext context, Widget interactive) {
    if (!widget.showValues) return interactive;
    final theme = Theme.of(context);
    final (lo, hi) = _normalized;
    final active = CellStyle(foreground: theme.colorScheme.primary, bold: true);
    final idle = theme.mutedStyle;
    final lowActive = _enabled && _active == _ActiveHandle.low;
    final highActive = _enabled && _active == _ActiveHandle.high;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (widget.label != null) ...[
              Text(widget.label!),
              const Text('  '),
            ],
            Text(_fmt(lo), style: lowActive ? active : idle),
            Text(' – ', style: idle),
            Text(_fmt(hi), style: highActive ? active : idle),
            // Teach the key model, but only while focused so it doesn't
            // clutter a resting slider.
            if (_enabled && _node.hasFocus)
              Text('   ↑↓ value · ←→ ends', style: idle),
          ],
        ),
        interactive,
        Row(
          children: <Widget>[
            Text(_fmt(widget.min), style: idle),
            const Expanded(child: SizedBox()),
            Text(_fmt(widget.max), style: idle),
          ],
        ),
      ],
    );
  }

  String _fmt(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

class _RawRangeSlider extends LeafRenderObjectWidget {
  const _RawRangeSlider({
    required this.values,
    required this.min,
    required this.max,
    required this.active,
    required this.focused,
    required this.geometry,
    required this.selectedStyle,
    required this.trackStyle,
  });

  final (num, num) values;
  final num min;
  final num max;
  final _ActiveHandle active;
  final bool focused;
  final _SliderGeometry geometry;
  final CellStyle selectedStyle;
  final CellStyle trackStyle;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderRangeSlider(
    values: values,
    min: min,
    max: max,
    active: active,
    focused: focused,
    geometry: geometry,
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
      ..geometry = geometry
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
    required _SliderGeometry geometry,
    required CellStyle selectedStyle,
    required CellStyle trackStyle,
  }) : _values = values,
       _min = min,
       _max = max,
       _active = active,
       _focused = focused,
       _geometry = geometry,
       _selectedStyle = selectedStyle,
       _trackStyle = trackStyle;

  _SliderGeometry _geometry;
  set geometry(_SliderGeometry v) {
    if (identical(_geometry, v)) return;
    _geometry = v;
    markNeedsPaintOnly();
  }

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
    // Record the painted track span so the State's pointer handlers can map an
    // absolute column back to a value (written even when off-screen below).
    _geometry
      ..left = offset.col
      ..width = w;
    if (w == 0 || size.rows == 0) return;
    if (offset.row < 0 || offset.row >= buffer.size.rows) return;

    final (lo, hi) = _values;
    final span = _max - _min;
    final loCol = ((lo - _min) / span * (w - 1)).round();
    final hiCol = ((hi - _min) / span * (w - 1)).round();
    const track = '─';
    const fill = '━';
    const activeHandle = '●'; // solid: the handle the arrows move
    const inactiveHandle = '○'; // hollow: the handle Up/Down switches to

    for (var c = 0; c < w; c++) {
      final tgt = offset.col + c;
      if (tgt < 0 || tgt >= buffer.size.cols) continue;
      String glyph;
      CellStyle style;
      if (c == loCol || c == hiCol) {
        // The active handle is always the solid mark so it reads as the
        // stronger of the two; focus only adds bold emphasis.
        final isActive =
            (c == loCol && _active == _ActiveHandle.low) ||
            (c == hiCol && _active == _ActiveHandle.high);
        glyph = isActive ? activeHandle : inactiveHandle;
        style = isActive && _focused
            ? _selectedStyle.merge(const CellStyle(bold: true))
            : _selectedStyle;
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
