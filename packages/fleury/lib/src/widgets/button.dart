import '../foundation/geometry.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
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

/// Framing independent of a button's content and color role.
enum ButtonAppearance {
  /// Brackets and padding, centered when given a tight width.
  bracketed,

  /// Unframed, left-aligned content; interaction styling fills its bounds.
  plain,
}

/// A pressable button: `[ content ]`. Provide exactly one of [text] or [child].
/// [text] is the convenience form for a plain label; [child] accepts composed
/// content with the same frame and interaction styling. [appearance] defaults
/// to [ButtonAppearance.bracketed]; [ButtonAppearance.plain] removes the frame
/// and left-aligns either content form. Do not put other
/// interactive controls inside [child].
///
/// Focusable; Enter/Space or a click
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
    this.text,
    this.child,
    this.semanticLabel,
    required this.onPressed,
    this.variant = ButtonVariant.normal,
    this.appearance = ButtonAppearance.bracketed,
    this.focusNode,
    this.autofocus = false,
    this.style,
  }) : assert(
         (text == null) != (child == null),
         'Button requires exactly one of text or child.',
       );

  /// Text shown using [appearance].
  final String? text;

  /// Composed content shown using the same [appearance] as [text].
  ///
  /// Text descendants inherit the button's resolved interaction style.
  /// Mutually exclusive with [text].
  final Widget? child;

  /// Accessible action name. Defaults to [text] for a plain-text button.
  ///
  /// Supply this for composed content whose name is not conveyed by its
  /// descendant semantics, or to omit decorative shortcuts from the name.
  /// An explicit name replaces descendant semantics, not visible content.
  final String? semanticLabel;

  /// Pressed handler, or null to disable the button.
  final void Function()? onPressed;

  /// Accent applied to the label, resolved from the theme's [ColorScheme].
  final ButtonVariant variant;

  /// Visual frame, independent of [variant] and the text/child choice.
  final ButtonAppearance appearance;

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
            '[ ${' ' * before}$text${' ' * after} ]',
            allowSelect: false,
            style: style,
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    // Keep the const constructor, while enforcing the contract in release
    // builds as well as assertion-enabled development builds.
    if ((text == null) == (child == null)) {
      throw ArgumentError('Button requires exactly one of text or child.');
    }
    final theme = Theme.of(context);
    final name = semanticLabel ?? text;
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
      semanticLabel: name,
      builder: (style, enabled, states) => ExcludeSemantics(
        excluding: name != null,
        child: child == null && appearance == ButtonAppearance.bracketed
            ? _text(context, '[ $text ]', style)
            : DefaultTextStyle.merge(
                style: style,
                child: _ButtonSurface(
                  style: DefaultTextStyle.of(context).merge(style),
                  appearance: appearance,
                  child: child ?? Text(text!, allowSelect: false),
                ),
              ),
      ),
    );
  }
}

// Padding between composed content and its brackets must carry the same
// focus/disabled style as the glyphs, including inverse-video themes.
class _ButtonSurface extends SingleChildRenderObjectWidget {
  const _ButtonSurface({
    required this.style,
    required this.appearance,
    required super.child,
  });

  final CellStyle style;
  final ButtonAppearance appearance;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderButtonSurface(style, appearance);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderButtonSurface renderObject,
  ) {
    renderObject
      ..style = style
      ..appearance = appearance;
  }
}

class _RenderButtonSurface extends RenderObject
    implements RenderObjectWithSingleChild {
  _RenderButtonSurface(this._style, this._appearance);

  ButtonAppearance _appearance;
  int get _inset => _appearance == ButtonAppearance.bracketed ? 2 : 0;

  set appearance(ButtonAppearance value) {
    if (_appearance == value) return;
    _appearance = value;
    markNeedsLayout();
  }

  CellStyle _style;
  set style(CellStyle value) {
    if (_style == value) return;
    _style = value;
    markNeedsPaintOnly();
  }

  RenderObject? _child;
  CellOffset _childOffset = CellOffset.zero;
  @override
  CellOffset childOffsetOf(RenderObject child) => _childOffset;

  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) dropChild(_child!);
    _child = value;
    if (value != null) adoptChild(value);
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final maxCols = constraints.maxCols;
    final contentSize =
        _child?.layout(
          CellConstraints(
            maxCols: maxCols == null
                ? null
                : (maxCols - 2 * _inset).clamp(0, maxCols),
            maxRows: constraints.maxRows,
          ),
        ) ??
        CellSize.zero;
    final result = constraints.constrain(
      CellSize(
        contentSize.cols + 2 * _inset,
        contentSize.rows < 1 ? 1 : contentSize.rows,
      ),
    );
    _childOffset = CellOffset(
      _inset == 0
          ? 0
          : _inset +
                ((result.cols - 2 * _inset - contentSize.cols).clamp(
                      0,
                      result.cols,
                    ) ~/
                    2),
      (result.rows - contentSize.rows) ~/ 2,
    );
    return result;
  }

  @override
  int computeMaxIntrinsicWidth(int? height) =>
      (_child?.computeMaxIntrinsicWidth(height) ?? 0) + 2 * _inset;

  @override
  int computeMinIntrinsicWidth(int? height) =>
      (_child?.computeMinIntrinsicWidth(height) ?? 0) + 2 * _inset;

  @override
  int computeMaxIntrinsicHeight(int? width) =>
      _child?.computeMaxIntrinsicHeight(
        width == null ? null : (width - 2 * _inset).clamp(0, width),
      ) ??
      1;

  @override
  int computeMinIntrinsicHeight(int? width) =>
      _child?.computeMinIntrinsicHeight(
        width == null ? null : (width - 2 * _inset).clamp(0, width),
      ) ??
      1;

  @override
  void performPaint(CellBuffer buffer, CellOffset offset) {
    if (size.isEmpty) return;
    buffer.fillRect(
      CellRect(offset: offset, size: size),
      style: _style,
    );
    final row = offset.row + (size.rows - 1) ~/ 2;
    if (_appearance == ButtonAppearance.bracketed) {
      buffer.writeGrapheme(CellOffset(offset.col, row), '[', style: _style);
      if (size.cols > 1) {
        buffer.writeGrapheme(
          CellOffset(offset.col + size.cols - 1, row),
          ']',
          style: _style,
        );
      }
    }
    _child?.paint(buffer, offset + _childOffset);
  }
}
