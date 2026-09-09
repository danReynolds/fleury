import '../rendering/cell.dart';
import '../rendering/width_resolver.dart';
import '../semantics/semantics.dart';
import 'basic.dart';
import 'focus.dart';
import 'focusable_control.dart';
import 'framework.dart';
import 'layout_builder.dart';
import 'media_query.dart';
import 'theme.dart';

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
    return FocusableControl(
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
      builder: (style, enabled, states) => _text(context, content, style),
    );
  }
}
