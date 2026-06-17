import 'package:fleury/fleury.dart';

/// A [TextInput] tuned for password / secret entry: every typed grapheme
/// is rendered as a single `•` (or [obscuringCharacter]) regardless of
/// what's in the controller. The real text is unchanged; only the
/// displayed glyphs are masked.
///
/// When [canReveal] is set (the default), [revealChord] (Ctrl+R) toggles a
/// show / hide state while the field is focused, so a user can sanity-check
/// what they typed. The field *consumes* the chord, so it never reaches
/// app-level shortcuts. The clipboard and the semantic value stay redacted
/// even while revealed — revealing is a visual convenience only.
///
/// This is sugar over `TextInput(obscureText: true)` so the call site reads
/// as "this is a password," not "a text field that happens to be obscured."
///
/// ```dart
/// PasswordInput(
///   placeholder: 'API token',
///   onSubmit: (text) => save(text),
/// )
/// ```
class PasswordInput extends StatefulWidget {
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
    this.enabled = true,
    this.readOnly = false,
    this.canReveal = true,
    this.revealChord = const KeyChord.char('r', ctrl: true),
    this.validationError,
    this.semanticLabel,
    this.semanticState = SemanticState.empty,
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

  final bool enabled;
  final bool readOnly;

  /// When true, [revealChord] toggles the masked / plain rendering while the
  /// field is focused.
  final bool canReveal;

  /// The chord that toggles reveal. Defaults to Ctrl+R. The focused field
  /// consumes it, so it shadows any app-level binding on the same chord.
  final KeyChord revealChord;

  final String? validationError;

  /// Label exposed through the semantic app graph.
  final String? semanticLabel;

  /// Additional semantic metadata for app-specific secret fields.
  ///
  /// Secret-field facts owned by [PasswordInput], such as `fieldType` and
  /// redaction state, remain authoritative.
  final SemanticState semanticState;

  @override
  State<PasswordInput> createState() => _PasswordInputState();
}

class _PasswordInputState extends State<PasswordInput> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final field = TextInput(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onSubmit: widget.onSubmit,
      onEscape: widget.onEscape,
      placeholder: widget.placeholder,
      placeholderStyle: widget.placeholderStyle,
      style: widget.style,
      cursorStyle: widget.cursorStyle,
      obscureText: !_revealed,
      obscuringCharacter: widget.obscuringCharacter,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      validationError: widget.validationError,
      // Stays redacted even while visually revealed: showing the glyphs is a
      // local convenience, copying or reading the value out is not.
      clipboardPolicy: TextClipboardPolicy.redacted,
      semanticLabel: widget.semanticLabel,
      semanticState: widget.semanticState.merge(<String, Object?>{
        'fieldType': 'secret',
        'redacted': true,
        'revealed': _revealed,
      }),
    );
    if (!widget.canReveal || !widget.enabled) return field;
    return KeyBindings(
      bindings: <KeyBinding>[
        KeyBinding(
          widget.revealChord,
          onEvent: (_) => setState(() => _revealed = !_revealed),
          hideFromHintBar: true,
        ),
      ],
      child: field,
    );
  }
}
