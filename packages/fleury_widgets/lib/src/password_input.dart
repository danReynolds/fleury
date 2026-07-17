import 'package:fleury/fleury_core.dart';

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
    this.onChanged,
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

  /// Text controller holding the unredacted secret value.
  final TextEditingController? controller;

  /// Focus node used by the underlying text input.
  final FocusNode? focusNode;

  /// Whether the field should request focus when mounted.
  final bool autofocus;

  /// Called with the new unredacted text on every edit. See
  /// [TextInput.onChanged].
  final void Function(String text)? onChanged;

  /// Called with the unredacted text when the user submits.
  final void Function(String text)? onSubmit;

  /// Called when Escape is pressed.
  final void Function()? onEscape;

  /// Placeholder text shown when the field is empty.
  final String placeholder;

  /// Style used for [placeholder].
  final CellStyle placeholderStyle;

  /// Style used for entered text or obscuring glyphs.
  final CellStyle style;

  /// Style applied to the cursor cell.
  final CellStyle cursorStyle;

  /// Glyph used in place of each typed grapheme. Defaults to `•`.
  final String obscuringCharacter;

  /// Whether the field accepts focus and user input.
  final bool enabled;

  /// Whether the field can receive focus but not edit text.
  final bool readOnly;

  /// When true, [revealChord] toggles the masked / plain rendering while the
  /// field is focused.
  final bool canReveal;

  /// The chord that toggles reveal. Defaults to Ctrl+R. The focused field
  /// consumes it, so it shadows any app-level binding on the same chord.
  final KeyChord revealChord;

  /// Optional validation error displayed by the underlying input.
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
      onChanged: widget.onChanged,
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
