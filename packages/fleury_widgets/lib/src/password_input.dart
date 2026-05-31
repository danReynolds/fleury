import 'package:fleury/fleury.dart';

/// A [TextInput] tuned for password / secret entry: every typed grapheme
/// is rendered as a single `•` (or [obscuringCharacter]) regardless of
/// what's in the controller. The real text is unchanged; only the
/// displayed glyphs are masked.
///
/// This is a thin sugar over `TextInput(obscureText: true)` so the call
/// site reads as "this is a password," not "this is a text field that
/// happens to be obscured."
///
/// ```dart
/// PasswordInput(
///   placeholder: 'API token',
///   onSubmit: (text) => save(text),
/// )
/// ```
class PasswordInput extends StatelessWidget {
  const PasswordInput({
    super.key,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.onSubmit,
    this.onEscape,
    this.placeholder = '',
    this.placeholderStyle = const CellStyle(dim: true),
    this.style = CellStyle.empty,
    this.cursorStyle = const CellStyle(inverse: true),
    this.obscuringCharacter = '•',
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final void Function(String text)? onSubmit;
  final void Function()? onEscape;
  final String placeholder;
  final CellStyle placeholderStyle;
  final CellStyle style;
  final CellStyle cursorStyle;

  /// Glyph used in place of each typed grapheme. Defaults to `•`.
  final String obscuringCharacter;

  @override
  Widget build(BuildContext context) {
    return TextInput(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      onSubmit: onSubmit,
      onEscape: onEscape,
      placeholder: placeholder,
      placeholderStyle: placeholderStyle,
      style: style,
      cursorStyle: cursorStyle,
      obscureText: true,
      obscuringCharacter: obscuringCharacter,
    );
  }
}
