import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_internal.dart';

import 'component_theme.dart';

/// Shared focus, hover, validation, and activation behavior for controls.
/// Enter or Space activates ([onActivate]) when enabled. The [builder] gets
/// the fully resolved style for the control's current state.
///
/// Enter arrives as a `KeyEvent`; Space arrives as inserted text, so the
/// control claims text input and consumes a single space (declining all
/// other text so it still bubbles).
class _FocusableControl extends StatefulWidget {
  const _FocusableControl({
    required this.onActivate,
    required this.builder,
    required this.semanticRole,
    required this.defaultStyle,
    this.semanticLabel,
    this.semanticValue,
    this.semanticChecked,
    this.semanticSelected = false,
    this.styleSelected = false,
    this.onSetValue,
    this.focusNode,
    this.autofocus = false,
    this.participatesInForm = false,
    this.validationError,
    this.style,
  });

  final void Function()? onActivate;
  final Widget Function(CellStyle style, bool enabled) builder;
  final CellStyle defaultStyle;
  final SemanticRole semanticRole;
  final String? semanticLabel;
  final Object? semanticValue;
  final bool? semanticChecked;
  final bool semanticSelected;
  final bool styleSelected;

  /// When non-null, the control advertises [SemanticAction.setValue] and routes
  /// the payload here — letting an agent set the value directly (idempotent),
  /// instead of toggling via [onActivate] and hoping it lands.
  final SemanticSetValueCallback? onSetValue;

  final FocusNode? focusNode;
  final bool autofocus;
  final bool participatesInForm;
  final String? validationError;
  final CellStyle? style;

  bool get enabled => onActivate != null;

  @override
  State<_FocusableControl> createState() => _FocusableControlState();
}

class _FocusableControlState extends State<_FocusableControl>
    implements TextInputClaimant {
  late FocusNode _node;
  bool _owns = false;
  bool _hovered = false;
  FormControlRegistration? _formRegistration;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode(debugLabel: 'control');
    _node.textInputClaimant = this;
    _owns = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(_FocusableControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _node.textInputClaimant = null;
      if (_owns) _node.dispose();
      _node = widget.focusNode ?? FocusNode(debugLabel: 'control');
      _node.textInputClaimant = this;
      _owns = widget.focusNode == null;
    }
    _syncFormClaim();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Focus.maybeOf(context); // rebuild on focus change (focus cue)
    final registration = FormControlScope.maybeOf(context);
    if (!identical(registration, _formRegistration)) {
      _formRegistration?.release(this);
      _formRegistration = widget.participatesInForm ? registration : null;
      _formRegistration?.claim(this, focusNode: _node, enabled: widget.enabled);
    } else {
      _syncFormClaim();
    }
  }

  void _syncFormClaim() => _formRegistration?.updateClaim(
    this,
    focusNode: _node,
    enabled: widget.enabled,
  );

  void _activate() {
    widget.onActivate!();
    _formRegistration?.controlValueChanged(this);
  }

  void _setValue(Object? payload) {
    widget.onSetValue?.call(payload);
    _formRegistration?.controlValueChanged(this);
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event.code == KeyCode.enter) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  KeyEventResult onTextInput(String text) {
    // Claim Space as activation; decline everything else so it bubbles.
    if (text == ' ') {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  KeyEventResult onPaste(String text) => KeyEventResult.ignored;

  @override
  void dispose() {
    _node.textInputClaimant = null;
    _formRegistration?.release(this);
    if (_owns) _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final validationError = _formRegistration?.error ?? widget.validationError;
    final focused = _node.hasFocus;
    final resolvedStyle = resolveCellStyle(
      cascade: [
        widget.defaultStyle,
        Theme.of(context).interactiveStyle,
        widget.style,
      ],
      states: {
        if (_hovered) CellStyleState.hovered,
        if (focused) CellStyleState.focused,
        if (widget.styleSelected) CellStyleState.selected,
        if (!widget.enabled) CellStyleState.disabled,
        if (validationError != null) CellStyleState.invalid,
      },
    );
    final Widget content = !widget.enabled
        ? Semantics(
            role: widget.semanticRole,
            label: widget.semanticLabel,
            value: widget.semanticValue,
            selected: widget.semanticSelected,
            checked: widget.semanticChecked,
            enabled: false,
            validationError: validationError,
            child: widget.builder(resolvedStyle, false),
          )
        : Semantics(
            role: widget.semanticRole,
            label: widget.semanticLabel,
            value: widget.semanticValue,
            focused: focused,
            selected: widget.semanticSelected,
            checked: widget.semanticChecked,
            enabled: true,
            validationError: validationError,
            actions: {
              SemanticAction.focus,
              SemanticAction.activate,
              if (widget.onSetValue != null) SemanticAction.setValue,
            },
            onAction: (action) {
              switch (action) {
                case SemanticAction.focus:
                  _node.requestFocus();
                  return;
                case SemanticAction.activate:
                  _node.requestFocus();
                  _activate();
                  return;
                case _:
                  return;
              }
            },
            onSetValue: widget.onSetValue == null ? null : _setValue,
            child: GestureDetector(
              // A click focuses the control and activates it, so pointer users
              // get the same affordance as keyboard users.
              onTap: () {
                _node.requestFocus();
                _activate();
              },
              child: KeyDetector(
                onKey: (event) {
                  if ((_onKey)(event) == KeyEventResult.handled) {
                    event.consume();
                  }
                },
                child: Focus(
                  focusNode: _node,
                  autofocus: widget.autofocus,
                  child: widget.builder(resolvedStyle, true),
                ),
              ),
            ),
          );
    // A form control is a styled, interactive component — not selectable text.
    // Opt its label out of the ambient text selection, the way a browser makes
    // `<button>` text non-selectable. Standalone Text stays selectable.
    return MouseRegion(
      onEnter: () {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: () {
        if (_hovered) setState(() => _hovered = false);
      },
      child: SelectionArea.disabled(child: content),
    );
  }
}

Widget _row(String indicator, String? label, CellStyle style) {
  return Row(
    children: [
      Text(indicator, style: style),
      if (label != null) Text(' $label', style: style),
    ],
  );
}

CellStyle _defaultControlStyle(ThemeData theme) => CellStyle.interactive(
  focused: theme.focusedStyle,
  disabled: theme.mutedStyle,
  invalid: theme.errorStyle,
);

/// A boolean checkbox: `[x]` checked, `[ ]` unchecked. Enter toggles when
/// focused, calling [onChanged] with the new value. A controlled widget —
/// hold the value yourself and update it from [onChanged]. Passing null
/// disables it.
class Checkbox extends StatelessWidget {
  const Checkbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.focusNode,
    this.autofocus = false,
    this.style,
  });

  /// Controlled checked state rendered by the checkbox.
  final bool value;

  /// Called with the requested next state on activation; null disables it.
  final void Function(bool value)? onChanged;

  /// Optional visible text and semantic label beside the indicator.
  final String? label;

  /// Optional externally owned focus node used for activation.
  final FocusNode? focusNode;

  /// Whether the checkbox requests focus when mounted.
  final bool autofocus;

  /// Base styling, plus optional hover, focus, selected, disabled, and invalid
  /// state entries from [CellStyle.interactive].
  final CellStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _FocusableControl(
      defaultStyle: _defaultControlStyle(theme),
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      onActivate: onChanged == null ? null : () => onChanged!(!value),
      onSetValue: onChanged == null
          ? null
          : (payload) {
              final next = coerceSemanticBool(payload);
              if (next != null) onChanged!(next);
            },
      semanticRole: SemanticRole.checkbox,
      semanticLabel: label,
      semanticValue: value,
      semanticChecked: value,
      styleSelected: value,
      participatesInForm: true,
      builder: (style, enabled) => _row(value ? '[x]' : '[ ]', label, style),
    );
  }
}

/// A boolean switch: `[ o]` on, `[o ]` off (the knob slides). Enter
/// toggles when focused. Like [Checkbox], controlled via [onChanged].
/// Passing null disables it.
class Toggle extends StatelessWidget {
  const Toggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.focusNode,
    this.autofocus = false,
    this.style,
  });

  /// Controlled on/off state rendered by the toggle.
  final bool value;

  /// Called with the requested next state on activation; null disables it.
  final void Function(bool value)? onChanged;

  /// Optional visible text and semantic label beside the indicator.
  final String? label;

  /// Optional externally owned focus node used for activation.
  final FocusNode? focusNode;

  /// Whether the toggle requests focus when mounted.
  final bool autofocus;

  /// Base styling, plus optional hover, focus, selected, disabled, and invalid
  /// state entries from [CellStyle.interactive].
  final CellStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _FocusableControl(
      defaultStyle: _defaultControlStyle(theme),
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      onActivate: onChanged == null ? null : () => onChanged!(!value),
      onSetValue: onChanged == null
          ? null
          : (payload) {
              final next = coerceSemanticBool(payload);
              if (next != null) onChanged!(next);
            },
      semanticRole: SemanticRole.toggle,
      semanticLabel: label,
      semanticValue: value,
      semanticChecked: value,
      styleSelected: value,
      participatesInForm: true,
      builder: (style, enabled) => _row(value ? '[ o]' : '[o ]', label, style),
    );
  }
}

/// A wider, accent-tinted boolean switch — visually distinct from
/// [Toggle] for cases where you want the on/off state to stand out at
/// a glance (settings panels, feature flags). When `value: true` the
/// track tints in the theme's primary color and the handle sits on the
/// right; when `false` the track is muted and the handle sits on the
/// left.
///
/// Off: `[●━━━]`, On (colored): `[━━━●]`. Enter / Space activates.
/// Passing null for [onChanged] disables the switch.
class Switch extends StatelessWidget {
  const Switch({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.focusNode,
    this.autofocus = false,
    this.style,
  });

  /// Controlled on/off state that positions and colors the switch handle.
  final bool value;

  /// Called with the requested next state on activation; null disables it.
  final void Function(bool value)? onChanged;

  /// Optional visible text and semantic label beside the track.
  final String? label;

  /// Optional externally owned focus node used for activation.
  final FocusNode? focusNode;

  /// Whether the switch requests focus when mounted.
  final bool autofocus;

  /// Base styling, plus optional hover, focus, selected, disabled, and invalid
  /// state entries from [CellStyle.interactive].
  final CellStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widgetTheme = FleuryWidgetTheme.from(theme);
    return _FocusableControl(
      defaultStyle: _defaultControlStyle(theme),
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      onActivate: onChanged == null ? null : () => onChanged!(!value),
      onSetValue: onChanged == null
          ? null
          : (payload) {
              final next = coerceSemanticBool(payload);
              if (next != null) onChanged!(next);
            },
      semanticRole: SemanticRole.toggle,
      semanticLabel: label,
      semanticValue: value,
      semanticChecked: value,
      styleSelected: value,
      participatesInForm: true,
      builder: (resolvedStyle, enabled) {
        final trackStyle = enabled
            ? widgetTheme
                  .resolveSwitchTrack(theme, selected: value)
                  .merge(resolvedStyle)
            : resolvedStyle;
        return Row(
          children: [
            Text('[', style: resolvedStyle),
            Text(value ? '━━━●' : '●━━━', style: trackStyle),
            Text(']', style: resolvedStyle),
            if (label != null) Text(' $label', style: resolvedStyle),
          ],
        );
      },
    );
  }
}

/// A single choice in a group: selected when [value] equals [groupValue]
/// (`(o)` selected, `( )` not). Enter selects when focused, calling
/// [onChanged] with this radio's [value]. Give every radio in the group
/// the same [groupValue] and [onChanged]. Passing null disables it.
class Radio<T> extends StatelessWidget {
  const Radio({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.label,
    this.focusNode,
    this.autofocus = false,
    this.style,
  }) : _validationError = null;

  const Radio._form({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required String? validationError,
    this.label,
    this.focusNode,
    this.autofocus = false,
    this.style,
  }) : _validationError = validationError;

  /// Value emitted when this radio is activated.
  final T value;

  /// Controlled group selection; equality with [value] selects this radio.
  final T? groupValue;

  /// Called with [value] on activation; null disables this radio.
  final void Function(T value)? onChanged;

  /// Optional visible text and semantic label beside the indicator.
  final String? label;

  /// Optional externally owned focus node used for activation.
  final FocusNode? focusNode;

  /// Whether this radio requests focus when mounted.
  final bool autofocus;

  /// Base styling, plus optional hover, focus, selected, and disabled state
  /// entries from [CellStyle.interactive].
  final CellStyle? style;

  final String? _validationError;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final theme = Theme.of(context);
    return _FocusableControl(
      defaultStyle: _defaultControlStyle(theme),
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      onActivate: onChanged == null ? null : () => onChanged!(value),
      semanticRole: SemanticRole.radio,
      semanticLabel: label,
      semanticValue: value,
      semanticChecked: selected,
      semanticSelected: selected,
      styleSelected: selected,
      validationError: _validationError,
      builder: (style, enabled) => _row(selected ? '(o)' : '( )', label, style),
    );
  }
}

/// A typed option for a [RadioGroup].
class RadioOption<T> {
  const RadioOption({required this.value, this.label, this.enabled = true});

  final T value;
  final String? label;
  final bool enabled;
}

/// A group of [Radio]s with the canonical roving-arrow behavior: arrow keys
/// move focus *and* selection to the adjacent enabled option (wrapping), so the
/// whole group is one Tab stop's worth of choice — the WAI-ARIA radiogroup
/// pattern (and Textual's RadioSet). Up/Left select the previous, Down/Right the
/// next. Controlled — hold the selected [value] and update it from [onChanged].
///
/// ```dart
/// RadioGroup<String>(
///   value: mode,
///   options: const [RadioOption(value: 'fast', label: 'Fast'),
///                   RadioOption(value: 'safe', label: 'Safe')],
///   onChanged: (v) => setState(() => mode = v),
/// )
/// ```
class RadioGroup<T> extends StatefulWidget {
  const RadioGroup({
    super.key,
    required this.value,
    required this.onChanged,
    required this.options,
    this.axis = Axis.vertical,
    this.spacing = 2,
    this.semanticLabel = 'Radio group',
    this.autofocus = false,
    this.style,
  });

  /// The currently selected value.
  final T? value;

  /// Called with the new value when the user moves or activates a radio.
  /// Passing null disables the whole group.
  final void Function(T value)? onChanged;

  /// Ordered choices; disabled options remain visible but navigation skips them.
  final List<RadioOption<T>> options;

  /// Whether options are stacked vertically or laid out in one row.
  /// All four directional arrows navigate in either layout.
  final Axis axis;

  /// Horizontal gap between options when [axis] is horizontal.
  final int spacing;

  /// Label exposed for the group through the semantic app graph.
  final String semanticLabel;

  /// Whether the selected enabled radio, or first enabled option, requests
  /// initial focus.
  final bool autofocus;

  /// Base styling for every radio, plus optional hover, focus, selected,
  /// disabled, and invalid state entries from [CellStyle.interactive].
  final CellStyle? style;

  @override
  State<RadioGroup<T>> createState() => _RadioGroupState<T>();
}

class _RadioGroupState<T> extends State<RadioGroup<T>> {
  late List<FocusNode> _nodes;
  FormControlRegistration? _formRegistration;

  @override
  void initState() {
    super.initState();
    _nodes = _makeNodes(widget.options.length);
  }

  List<FocusNode> _makeNodes(int count) =>
      List<FocusNode>.generate(count, (i) => FocusNode(debugLabel: 'radio-$i'));

  @override
  void didUpdateWidget(RadioGroup<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.length != widget.options.length) {
      for (final node in _nodes) {
        node.dispose();
      }
      _nodes = _makeNodes(widget.options.length);
    }
    _syncFormClaim();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registration = FormControlScope.maybeOf(context);
    if (!identical(registration, _formRegistration)) {
      _formRegistration?.release(this);
      _formRegistration = registration;
      final target = _formFocusNode;
      if (target != null) {
        registration?.claim(
          this,
          focusNode: target,
          enabled: widget.onChanged != null,
        );
      }
    } else {
      _syncFormClaim();
    }
  }

  FocusNode? get _formFocusNode {
    if (_nodes.isEmpty) return null;
    final selected = _selectedIndex;
    if (selected >= 0 && widget.options[selected].enabled) {
      return _nodes[selected];
    }
    final first = widget.options.indexWhere((option) => option.enabled);
    return first < 0 ? _nodes.first : _nodes[first];
  }

  void _syncFormClaim() {
    final target = _formFocusNode;
    if (target == null) return;
    _formRegistration?.updateClaim(
      this,
      focusNode: target,
      enabled: widget.onChanged != null,
    );
  }

  void _select(T value) {
    widget.onChanged?.call(value);
    _formRegistration?.controlValueChanged(this);
  }

  @override
  void dispose() {
    _formRegistration?.release(this);
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  int get _selectedIndex =>
      widget.options.indexWhere((option) => option.value == widget.value);

  void _move(int dir) {
    if (widget.onChanged == null) return;
    final focused = _nodes.indexWhere((node) => node.hasFocus);
    final from = focused >= 0
        ? focused
        : (_selectedIndex >= 0 ? _selectedIndex : 0);
    final n = widget.options.length;
    for (var k = 1; k <= n; k++) {
      final i = ((from + dir * k) % n + n) % n;
      if (widget.options[i].enabled) {
        _nodes[i].requestFocus();
        _select(widget.options[i].value);
        return;
      }
    }
  }

  KeyEventResult _onKey(KeyEvent event) {
    switch (event.code) {
      case KeyCode.arrowUp:
      case KeyCode.arrowLeft:
        _move(-1);
        return KeyEventResult.handled;
      case KeyCode.arrowDown:
      case KeyCode.arrowRight:
        _move(1);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex;
    final autofocusIndex =
        selectedIndex >= 0 && widget.options[selectedIndex].enabled
        ? selectedIndex
        : widget.options.indexWhere((option) => option.enabled);
    final radios = <Widget>[
      for (var i = 0; i < widget.options.length; i++)
        Radio<T>._form(
          value: widget.options[i].value,
          groupValue: widget.value,
          label: widget.options[i].label,
          focusNode: _nodes[i],
          autofocus: widget.autofocus && i == autofocusIndex,
          style: widget.style,
          validationError: _formRegistration?.error,
          onChanged: widget.options[i].enabled && widget.onChanged != null
              ? _select
              : null,
        ),
    ];
    final Widget layout = widget.axis == Axis.vertical
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: radios)
        : Row(
            children: <Widget>[
              for (var i = 0; i < radios.length; i++) ...[
                if (i > 0) SizedBox(width: widget.spacing),
                radios[i],
              ],
            ],
          );
    // The group's onKey is closer to the focused radio than the app's root
    // directional traversal, so consuming the arrows here adds selection.
    final validationError = _formRegistration?.error;
    return Semantics(
      role: SemanticRole.region,
      label: widget.semanticLabel,
      validationError: validationError,
      child: KeyDetector(
        onKey: (event) {
          if ((_onKey)(event) == KeyEventResult.handled) event.consume();
        },
        child: Focus(canRequestFocus: false, child: layout),
      ),
    );
  }
}

/// Accent for a [Button], resolved against the active [ColorScheme].
enum ButtonVariant { normal, primary, success, warning, error }

/// A pressable button: `[ Label ]`. Focusable; Enter/Space or a click
/// fires [onPressed]. Passing a null [onPressed] disables it — shown
/// muted and not focusable.
///
/// [variant] tints the label from the theme's [ColorScheme] (primary for
/// the default action, error for a destructive one, etc.); when focused
/// the button shows the theme's selection highlight.
///
/// A button is normally as wide as its label. Give it a tight width, such as
/// `SizedBox(width: 14, child: Button(...))`, to center the label and expand
/// the bracketed button to that width.
class Button extends StatelessWidget {
  const Button({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.normal,
    this.focusNode,
    this.autofocus = false,
    this.style,
  });

  /// Text shown inside the `[ … ]` button frame.
  final String label;

  /// Pressed handler, or null to disable the button.
  final void Function()? onPressed;

  /// Accent applied to the label, resolved from the theme's [ColorScheme].
  final ButtonVariant variant;

  /// Focus node for the button.
  final FocusNode? focusNode;

  /// Whether the button requests focus when mounted.
  final bool autofocus;

  /// Base styling, plus optional hover, focus, and disabled state entries from
  /// [CellStyle.interactive].
  final CellStyle? style;

  static Color? _color(ButtonVariant variant, ColorScheme scheme) =>
      switch (variant) {
        ButtonVariant.normal => scheme.foreground,
        ButtonVariant.primary => scheme.primary,
        ButtonVariant.success => scheme.success,
        ButtonVariant.warning => scheme.warning,
        ButtonVariant.error => scheme.error,
      };

  static const WidthResolver _widthResolver = DefaultWidthResolver();

  Widget _text(BuildContext context, String content, CellStyle style) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final maxCols = constraints.maxCols;
          final tightWidth = maxCols != null && constraints.minCols == maxCols
              ? maxCols
              : null;
          if (tightWidth == null) {
            return Text(content, allowSelect: false, style: style);
          }

          final policy = MediaQuery.textPolicyOf(context).widths;
          final contentWidth = _widthResolver.widthOfText(content, policy);
          if (contentWidth >= tightWidth) {
            return Text(content, allowSelect: false, style: style);
          }

          final slack = tightWidth - contentWidth;
          final before = slack ~/ 2;
          final after = slack - before;
          return Text(
            '[ ${' ' * before}$label${' ' * after} ]',
            allowSelect: false,
            style: style,
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = '[ $label ]';
    final base = CellStyle(foreground: _color(variant, theme.colorScheme));
    return _FocusableControl(
      defaultStyle: CellStyle.interactive(
        base: base,
        focused: theme.selectionStyle,
        disabled: theme.mutedStyle,
      ),
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      onActivate: onPressed,
      semanticRole: SemanticRole.button,
      semanticLabel: label,
      builder: (style, enabled) => _text(context, content, style),
    );
  }
}
