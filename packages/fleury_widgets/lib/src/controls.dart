import 'package:fleury/fleury.dart';

import 'component_theme.dart';

/// Shared focus + activation chrome for the form controls. Focusable;
/// Enter or Space activates ([onActivate]) when enabled. The [builder] gets
/// whether the control currently holds focus and whether it is enabled so it
/// can show focus and disabled cues.
///
/// Enter arrives as a `KeyEvent`; Space arrives as inserted text, so the
/// control claims text input and consumes a single space (declining all
/// other text so it still bubbles).
class _FocusableControl extends StatefulWidget {
  const _FocusableControl({
    required this.onActivate,
    required this.builder,
    required this.semanticRole,
    this.semanticLabel,
    this.semanticValue,
    this.semanticChecked,
    this.semanticSelected = false,
    this.focusNode,
    this.autofocus = false,
  });

  final void Function()? onActivate;
  final Widget Function(bool focused, bool enabled) builder;
  final SemanticRole semanticRole;
  final String? semanticLabel;
  final Object? semanticValue;
  final bool? semanticChecked;
  final bool semanticSelected;
  final FocusNode? focusNode;
  final bool autofocus;

  bool get enabled => onActivate != null;

  @override
  State<_FocusableControl> createState() => _FocusableControlState();
}

class _FocusableControlState extends State<_FocusableControl>
    implements TextInputClaimant {
  late FocusNode _node;
  bool _owns = false;

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Focus.maybeOf(context); // rebuild on focus change (focus cue)
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event.keyCode == KeyCode.enter) {
      widget.onActivate!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  KeyEventResult onTextInput(String text) {
    // Claim Space as activation; decline everything else so it bubbles.
    if (text == ' ') {
      widget.onActivate!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  KeyEventResult onPaste(String text) => KeyEventResult.ignored;

  @override
  void dispose() {
    _node.textInputClaimant = null;
    if (_owns) _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return Semantics(
        role: widget.semanticRole,
        label: widget.semanticLabel,
        value: widget.semanticValue,
        selected: widget.semanticSelected,
        checked: widget.semanticChecked,
        enabled: false,
        child: widget.builder(false, false),
      );
    }

    return Semantics(
      role: widget.semanticRole,
      label: widget.semanticLabel,
      value: widget.semanticValue,
      focused: _node.hasFocus,
      selected: widget.semanticSelected,
      checked: widget.semanticChecked,
      enabled: true,
      actions: const {SemanticAction.focus, SemanticAction.activate},
      onAction: (action) {
        switch (action) {
          case SemanticAction.focus:
            _node.requestFocus();
            return;
          case SemanticAction.activate:
            _node.requestFocus();
            widget.onActivate!();
            return;
          case _:
            return;
        }
      },
      child: GestureDetector(
        // A click focuses the control and activates it, so pointer users get
        // the same affordance as keyboard users.
        onTap: () {
          _node.requestFocus();
          widget.onActivate!();
        },
        child: Focus(
          focusNode: _node,
          autofocus: widget.autofocus,
          onKey: _onKey,
          child: widget.builder(_node.hasFocus, true),
        ),
      ),
    );
  }
}

Widget _row(
  String indicator,
  String? label,
  bool focused,
  bool enabled,
  CellStyle focusStyle,
  CellStyle disabledStyle,
) {
  final style = !enabled
      ? disabledStyle
      : focused
      ? focusStyle
      : CellStyle.empty;
  return Row(
    children: [
      Text(indicator, style: style),
      if (label != null) Text(' $label', style: style),
    ],
  );
}

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
  });

  final bool value;
  final void Function(bool value)? onChanged;
  final String? label;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widgetTheme = FleuryWidgetTheme.from(theme);
    return _FocusableControl(
      focusNode: focusNode,
      autofocus: autofocus,
      onActivate: onChanged == null ? null : () => onChanged!(!value),
      semanticRole: SemanticRole.checkbox,
      semanticLabel: label,
      semanticValue: value,
      semanticChecked: value,
      builder: (focused, enabled) => _row(
        value ? '[x]' : '[ ]',
        label,
        focused,
        enabled,
        widgetTheme.resolveControlFocus(theme),
        widgetTheme.resolveDisabled(theme),
      ),
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
  });

  final bool value;
  final void Function(bool value)? onChanged;
  final String? label;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widgetTheme = FleuryWidgetTheme.from(theme);
    return _FocusableControl(
      focusNode: focusNode,
      autofocus: autofocus,
      onActivate: onChanged == null ? null : () => onChanged!(!value),
      semanticRole: SemanticRole.toggle,
      semanticLabel: label,
      semanticValue: value,
      semanticChecked: value,
      builder: (focused, enabled) => _row(
        value ? '[ o]' : '[o ]',
        label,
        focused,
        enabled,
        widgetTheme.resolveControlFocus(theme),
        widgetTheme.resolveDisabled(theme),
      ),
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
  });

  final bool value;
  final void Function(bool value)? onChanged;
  final String? label;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widgetTheme = FleuryWidgetTheme.from(theme);
    return _FocusableControl(
      focusNode: focusNode,
      autofocus: autofocus,
      onActivate: onChanged == null ? null : () => onChanged!(!value),
      semanticRole: SemanticRole.toggle,
      semanticLabel: label,
      semanticValue: value,
      semanticChecked: value,
      builder: (focused, enabled) {
        final disabledStyle = widgetTheme.resolveDisabled(theme);
        final trackStyle = !enabled
            ? disabledStyle
            : value
            ? widgetTheme.resolveSwitchOn(theme)
            : widgetTheme.resolveSwitchOff(theme);
        final focusBracket = !enabled
            ? disabledStyle
            : focused
            ? widgetTheme.resolveControlFocus(theme)
            : CellStyle.empty;
        return Row(
          children: [
            Text('[', style: focusBracket),
            Text(value ? '━━━●' : '●━━━', style: trackStyle),
            Text(']', style: focusBracket),
            if (label != null) Text(' $label', style: focusBracket),
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
  });

  final T value;
  final T? groupValue;
  final void Function(T value)? onChanged;
  final String? label;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final theme = Theme.of(context);
    final widgetTheme = FleuryWidgetTheme.from(theme);
    return _FocusableControl(
      focusNode: focusNode,
      autofocus: autofocus,
      onActivate: onChanged == null ? null : () => onChanged!(value),
      semanticRole: SemanticRole.radio,
      semanticLabel: label,
      semanticValue: value,
      semanticChecked: selected,
      semanticSelected: selected,
      builder: (focused, enabled) => _row(
        selected ? '(o)' : '( )',
        label,
        focused,
        enabled,
        widgetTheme.resolveControlFocus(theme),
        widgetTheme.resolveDisabled(theme),
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
class Button extends StatelessWidget {
  const Button({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.normal,
    this.focusNode,
    this.autofocus = false,
  });

  final String label;

  /// Pressed handler, or null to disable the button.
  final void Function()? onPressed;
  final ButtonVariant variant;
  final FocusNode? focusNode;
  final bool autofocus;

  static Color? _color(ButtonVariant variant, ColorScheme scheme) =>
      switch (variant) {
        ButtonVariant.normal => scheme.foreground,
        ButtonVariant.primary => scheme.primary,
        ButtonVariant.success => scheme.success,
        ButtonVariant.warning => scheme.warning,
        ButtonVariant.error => scheme.error,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widgetTheme = FleuryWidgetTheme.from(theme);
    final content = '[ $label ]';

    if (onPressed == null) {
      return Semantics(
        role: SemanticRole.button,
        label: label,
        enabled: false,
        child: Text(content, style: widgetTheme.resolveDisabled(theme)),
      );
    }
    final base = CellStyle(foreground: _color(variant, theme.colorScheme));
    return _FocusableControl(
      focusNode: focusNode,
      autofocus: autofocus,
      onActivate: onPressed!,
      semanticRole: SemanticRole.button,
      semanticLabel: label,
      builder: (focused, enabled) => Text(
        content,
        style: focused ? base.merge(theme.selectionStyle) : base,
      ),
    );
  }
}
