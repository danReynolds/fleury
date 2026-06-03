import 'package:fleury/fleury.dart';

/// A numeric stepper: `[ − 42 + ]`. Focusable; arrow chords (and +/−)
/// adjust the value by [step], PageUp / PageDown by [largeStep], Home /
/// End jump to [min] / [max]. Clicking the `−` or `+` half also nudges
/// the value, so pointer users get the same affordance.
///
/// Controlled — hold the value yourself and update it from [onChanged].
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
  final void Function(num value) onChanged;

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
    final next = _clamp(widget.value + delta);
    if (next != widget.value) widget.onChanged(next);
  }

  void _jump(num target) {
    final next = _clamp(target);
    if (next != widget.value) widget.onChanged(next);
  }

  KeyEventResult _onKey(KeyEvent event) {
    switch (event.keyCode) {
      case KeyCode.arrowUp:
        _nudge(widget.step);
        return KeyEventResult.handled;
      case KeyCode.arrowDown:
        _nudge(-widget.step);
        return KeyEventResult.handled;
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
    // +/= add, -/_ subtract, mirroring conventions in spreadsheet apps.
    switch (text) {
      case '+':
      case '=':
        _nudge(widget.step);
        return KeyEventResult.handled;
      case '-':
      case '_':
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
    final focused = _node.hasFocus;
    final canDec = widget.min == null || widget.value > widget.min!;
    final canInc = widget.max == null || widget.value < widget.max!;
    final muted = theme.mutedStyle;
    final focusStyle = focused ? theme.focusedStyle : CellStyle.empty;
    final dim = const CellStyle(dim: true);

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
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        onKey: _onKey,
        child: GestureDetector(
          onTap: () => _node.requestFocus(),
          child: Row(
            children: [
              if (widget.label != null) ...[
                Text(widget.label!, style: muted),
                const Text(' '),
              ],
              Text('[', style: focusStyle),
              GestureDetector(
                onTap: () {
                  _node.requestFocus();
                  _nudge(-widget.step);
                },
                child: Text(' − ', style: canDec ? focusStyle : dim),
              ),
              Text(_format(widget.value), style: focusStyle),
              GestureDetector(
                onTap: () {
                  _node.requestFocus();
                  _nudge(widget.step);
                },
                child: Text(' + ', style: canInc ? focusStyle : dim),
              ),
              Text(']', style: focusStyle),
            ],
          ),
        ),
      ),
    );
  }
}
