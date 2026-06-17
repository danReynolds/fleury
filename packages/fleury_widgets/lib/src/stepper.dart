import 'package:fleury/fleury.dart';

/// A numeric stepper: `[ − 42 + ]`. Focusable; arrow chords (and +/−)
/// adjust the value by [step], PageUp / PageDown by [largeStep], Home /
/// End jump to [min] / [max]. Clicking the `−` or `+` half also nudges
/// the value, so pointer users get the same affordance.
///
/// Controlled — hold the value yourself and update it from [onChanged].
/// Passing null for [onChanged] disables the stepper.
///
/// ```dart
/// Stepper(
///   value: count,
///   min: 0,
///   max: 100,
///   onChanged: (v) => setState(() => count = v),
/// )
/// ```
class Stepper extends StatefulWidget {
  const Stepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min,
    this.max,
    this.step = 1,
    this.largeStep = 10,
    this.formatter,
    this.label,
    this.focusNode,
    this.autofocus = false,
  });

  /// Current value.
  final num value;

  /// Called with the new value when the user nudges it.
  final void Function(num value)? onChanged;

  /// Lower bound. `null` means unbounded below.
  final num? min;

  /// Upper bound. `null` means unbounded above.
  final num? max;

  /// Amount added/subtracted on Up / Down / + / − or a click on a button.
  final num step;

  /// Amount added/subtracted on PageUp / PageDown. Should be ≥ [step].
  final num largeStep;

  /// Renders the value into the display string. Defaults to
  /// `v.toInt().toString()` for whole values and a one-decimal form
  /// otherwise — mirrors what BarChart uses, so the look matches.
  final String Function(num value)? formatter;

  /// Optional label shown to the left of the stepper.
  final String? label;

  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<Stepper> createState() => _StepperState();
}

class _StepperState extends State<Stepper> implements TextInputClaimant {
  late FocusNode _node;
  bool _owns = false;

  /// In-progress direct numeric entry. Null when not typing; the typed
  /// string otherwise (committed on Enter or focus loss, dropped on Esc).
  String? _buffer;

  bool get _enabled => widget.onChanged != null;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode(debugLabel: 'stepper');
    _node.textInputClaimant = this;
    _owns = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(Stepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _node.textInputClaimant = null;
      if (_owns) _node.dispose();
      _node = widget.focusNode ?? FocusNode(debugLabel: 'stepper');
      _node.textInputClaimant = this;
      _owns = widget.focusNode == null;
    }
  }

  void _handleFocusChange(bool hasFocus) {
    // Commit any pending entry when focus leaves the stepper.
    if (!hasFocus && _buffer != null) _commitBuffer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Focus.maybeOf(context); // rebuild on focus change
  }

  @override
  void dispose() {
    _node.textInputClaimant = null;
    if (_owns) _node.dispose();
    super.dispose();
  }

  num _clamp(num v) {
    if (widget.min != null && v < widget.min!) return widget.min!;
    if (widget.max != null && v > widget.max!) return widget.max!;
    return v;
  }

  void _nudge(num delta) {
    if (!_enabled) return;
    final next = _clamp(widget.value + delta);
    if (next != widget.value) widget.onChanged!(next);
  }

  void _jump(num target) {
    if (!_enabled) return;
    final next = _clamp(target);
    if (next != widget.value) widget.onChanged!(next);
  }

  /// Whether a single typed [text] character extends the entry buffer.
  /// Digits always; a decimal point only for a fractional stepper and only
  /// once. (A leading `-` is deliberately not consumed here — it keeps its
  /// existing meaning of "decrement".)
  bool _acceptsTyped(String text) {
    if (text.length != 1) return false;
    final code = text.codeUnitAt(0);
    if (code >= 0x30 && code <= 0x39) return true; // 0-9
    final fractional = widget.step != widget.step.truncate();
    if (text == '.' && fractional && !(_buffer ?? '').contains('.')) {
      return true;
    }
    return false;
  }

  void _commitBuffer() {
    final raw = _buffer;
    _buffer = null;
    final parsed = raw == null ? null : num.tryParse(raw);
    if (parsed != null) {
      final next = _clamp(parsed);
      if (next != widget.value) widget.onChanged!(next);
    }
    if (mounted) setState(() {});
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (!_enabled) return KeyEventResult.ignored;
    // Buffer-control keys take effect only while a direct entry is in flight,
    // so when idle they bubble (Esc closes overlays, Enter submits forms).
    switch (event.keyCode) {
      case KeyCode.enter:
        if (_buffer == null) return KeyEventResult.ignored;
        _commitBuffer();
        return KeyEventResult.handled;
      case KeyCode.escape:
        if (_buffer == null) return KeyEventResult.ignored;
        setState(() => _buffer = null);
        return KeyEventResult.handled;
      case KeyCode.backspace:
        if (_buffer == null) return KeyEventResult.ignored;
        setState(() {
          final next = _buffer!.substring(0, _buffer!.length - 1);
          _buffer = next.isEmpty ? null : next;
        });
        return KeyEventResult.handled;
      default:
        break;
    }
    // Any step/jump key commits a pending entry first, then acts on the value.
    if (_buffer != null) _commitBuffer();
    switch (event.keyCode) {
      // Up/Down adjust the value and bubble (escape) once pinned at a bound,
      // so the arrows that drive the stepper also carry focus off it.
      // (Left/Right are unused and already bubble for horizontal escape.)
      case KeyCode.arrowUp:
        return moveOrEscape(
          atEdge: _clamp(widget.value + widget.step) == widget.value,
          move: () => _nudge(widget.step),
        );
      case KeyCode.arrowDown:
        return moveOrEscape(
          atEdge: _clamp(widget.value - widget.step) == widget.value,
          move: () => _nudge(-widget.step),
        );
      case KeyCode.pageUp:
        _nudge(widget.largeStep);
        return KeyEventResult.handled;
      case KeyCode.pageDown:
        _nudge(-widget.largeStep);
        return KeyEventResult.handled;
      case KeyCode.home:
        if (widget.min != null) _jump(widget.min!);
        return KeyEventResult.handled;
      case KeyCode.end:
        if (widget.max != null) _jump(widget.max!);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  KeyEventResult onTextInput(String text) {
    if (!_enabled) return KeyEventResult.ignored;
    // Direct numeric entry: typing digits builds a value, committed on Enter
    // or focus loss — the spinbox convention. Checked before +/− so a typed
    // digit doesn't fall through.
    if (_acceptsTyped(text)) {
      setState(() => _buffer = (_buffer ?? '') + text);
      return KeyEventResult.handled;
    }
    // +/= add, -/_ subtract, mirroring conventions in spreadsheet apps.
    switch (text) {
      case '+':
      case '=':
        if (_buffer != null) _commitBuffer();
        _nudge(widget.step);
        return KeyEventResult.handled;
      case '-':
      case '_':
        if (_buffer != null) _commitBuffer();
        _nudge(-widget.step);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  KeyEventResult onPaste(String text) => KeyEventResult.ignored;

  String _format(num v) {
    final f = widget.formatter;
    if (f != null) return f(v);
    if (v == v.truncate()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = _enabled;
    final focused = _node.hasFocus;
    final canDec =
        enabled && (widget.min == null || widget.value > widget.min!);
    final canInc =
        enabled && (widget.max == null || widget.value < widget.max!);
    final muted = theme.mutedStyle;
    final focusStyle = !enabled
        ? muted
        : focused
        ? theme.focusedStyle
        : CellStyle.empty;
    final dim = const CellStyle(dim: true);
    Widget body() => Row(
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: muted),
          const Text(' '),
        ],
        Text('[', style: focusStyle),
        GestureDetector(
          onTap: enabled
              ? () {
                  _node.requestFocus();
                  _nudge(-widget.step);
                }
              : null,
          child: Text(' − ', style: canDec ? focusStyle : dim),
        ),
        Text(
          _buffer != null ? '$_buffer▏' : _format(widget.value),
          style: focusStyle,
        ),
        GestureDetector(
          onTap: enabled
              ? () {
                  _node.requestFocus();
                  _nudge(widget.step);
                }
              : null,
          child: Text(' + ', style: canInc ? focusStyle : dim),
        ),
        Text(']', style: focusStyle),
      ],
    );

    if (!enabled) {
      return Semantics(
        role: SemanticRole.spinButton,
        label: widget.label,
        value: widget.value,
        enabled: false,
        state: SemanticState({
          'numericValue': widget.value,
          if (widget.min != null) 'min': widget.min,
          if (widget.max != null) 'max': widget.max,
          'step': widget.step,
          'largeStep': widget.largeStep,
          'canIncrement': false,
          'canDecrement': false,
        }),
        child: body(),
      );
    }

    return Semantics(
      role: SemanticRole.spinButton,
      label: widget.label,
      value: widget.value,
      focused: focused,
      actions: {
        SemanticAction.focus,
        if (canInc) SemanticAction.increment,
        if (canDec) SemanticAction.decrement,
      },
      state: SemanticState({
        'numericValue': widget.value,
        if (widget.min != null) 'min': widget.min,
        if (widget.max != null) 'max': widget.max,
        'step': widget.step,
        'largeStep': widget.largeStep,
        'canIncrement': canInc,
        'canDecrement': canDec,
      }),
      onAction: (action) {
        switch (action) {
          case SemanticAction.focus:
            _node.requestFocus();
            return;
          case SemanticAction.increment:
            _node.requestFocus();
            if (canInc) _nudge(widget.step);
            return;
          case SemanticAction.decrement:
            _node.requestFocus();
            if (canDec) _nudge(-widget.step);
            return;
          case _:
            return;
        }
      },
      child: FocusWithin(
        onFocusChange: _handleFocusChange,
        child: Focus(
          focusNode: _node,
          autofocus: widget.autofocus,
          onKey: _onKey,
          // Wheel over the stepper nudges the value (the spinner convention).
          // It doesn't steal focus, so wheeling past it in a scrollable form
          // isn't disruptive.
          child: PointerScrollListener(
            router: PointerRouterScope.maybeOf(context),
            onScrollUp: () => _nudge(widget.step),
            onScrollDown: () => _nudge(-widget.step),
            child: GestureDetector(
              onTap: () => _node.requestFocus(),
              child: body(),
            ),
          ),
        ),
      ),
    );
  }
}
