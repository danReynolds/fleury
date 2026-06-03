import '../terminal/events.dart';

/// Semantic editing command resolved from a terminal [KeyEvent].
///
/// Text widgets decide whether an action is valid in their current state. The
/// keymap only answers "what editing intent does this key represent?".
enum TextEditingKeyAction {
  copy,
  cut,
  undo,
  redo,
  backspace,
  deleteForward,
  moveLeft,
  moveRight,
  moveWordLeft,
  moveWordRight,
  moveUp,
  moveDown,
  moveLineStart,
  moveLineEnd,
  moveDocumentStart,
  moveDocumentEnd,
  previousVertical,
  nextVertical,
  acceptCompletion,
  submit,
  insertNewline,
  escape,
}

/// One key-to-action binding inside a [TextEditingKeymap].
final class TextEditingKeyBinding {
  const TextEditingKeyBinding({
    required this.action,
    this.keyCode,
    this.char,
    this.modifiers = const <KeyModifier>{},
    this.allowShift = false,
  }) : assert(
         keyCode != null || char != null,
         'A text key binding must match a key code or character.',
       );

  final TextEditingKeyAction action;
  final KeyCode? keyCode;
  final String? char;
  final Set<KeyModifier> modifiers;

  /// Allows Shift in addition to [modifiers].
  ///
  /// Movement bindings use this so widgets can decide whether Shift extends
  /// selection without duplicating every arrow/home/end binding.
  final bool allowShift;

  bool matches(KeyEvent event) {
    if (event.type == KeyEventType.up) return false;
    if (keyCode != null && event.keyCode != keyCode) return false;
    if (char != null && event.char?.toLowerCase() != char) return false;
    for (final modifier in modifiers) {
      if (!event.modifiers.contains(modifier)) return false;
    }
    for (final modifier in event.modifiers) {
      if (modifier == KeyModifier.shift && allowShift) continue;
      if (!modifiers.contains(modifier)) return false;
    }
    return true;
  }
}

/// Ordered keymap for editable text widgets.
///
/// Bindings are checked in order. Put more-specific chords, such as
/// Ctrl+Shift+Z, before less-specific chords, such as Ctrl+Z.
final class TextEditingKeymap {
  const TextEditingKeymap(this.bindings);

  final List<TextEditingKeyBinding> bindings;

  static const defaultSingleLine = TextEditingKeymap(_defaultSingleLine);
  static const defaultMultiline = TextEditingKeymap(_defaultMultiline);
  static const emacsSingleLine = TextEditingKeymap(<TextEditingKeyBinding>[
    ..._emacsSingleLine,
    ..._defaultSingleLine,
  ]);
  static const emacsMultiline = TextEditingKeymap(<TextEditingKeyBinding>[
    ..._emacsMultiline,
    ..._defaultMultiline,
  ]);

  TextEditingKeyAction? resolve(KeyEvent event) {
    for (final binding in bindings) {
      if (binding.matches(event)) return binding.action;
    }
    return null;
  }
}

const _defaultSingleLine = <TextEditingKeyBinding>[
  TextEditingKeyBinding(
    action: TextEditingKeyAction.copy,
    char: 'c',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.cut,
    char: 'x',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.redo,
    char: 'z',
    modifiers: {KeyModifier.ctrl, KeyModifier.shift},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.undo,
    char: 'z',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.redo,
    char: 'y',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.backspace,
    keyCode: KeyCode.backspace,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.deleteForward,
    keyCode: KeyCode.delete,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveWordLeft,
    keyCode: KeyCode.arrowLeft,
    modifiers: {KeyModifier.ctrl},
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveWordRight,
    keyCode: KeyCode.arrowRight,
    modifiers: {KeyModifier.ctrl},
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveWordLeft,
    keyCode: KeyCode.arrowLeft,
    modifiers: {KeyModifier.alt},
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveWordRight,
    keyCode: KeyCode.arrowRight,
    modifiers: {KeyModifier.alt},
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveLeft,
    keyCode: KeyCode.arrowLeft,
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveRight,
    keyCode: KeyCode.arrowRight,
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.previousVertical,
    keyCode: KeyCode.arrowUp,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.nextVertical,
    keyCode: KeyCode.arrowDown,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.acceptCompletion,
    keyCode: KeyCode.tab,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveDocumentStart,
    keyCode: KeyCode.home,
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveDocumentEnd,
    keyCode: KeyCode.end,
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.submit,
    keyCode: KeyCode.enter,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.escape,
    keyCode: KeyCode.escape,
  ),
];

const _defaultMultiline = <TextEditingKeyBinding>[
  TextEditingKeyBinding(
    action: TextEditingKeyAction.copy,
    char: 'c',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.cut,
    char: 'x',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.redo,
    char: 'z',
    modifiers: {KeyModifier.ctrl, KeyModifier.shift},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.undo,
    char: 'z',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.redo,
    char: 'y',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.backspace,
    keyCode: KeyCode.backspace,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.deleteForward,
    keyCode: KeyCode.delete,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveWordLeft,
    keyCode: KeyCode.arrowLeft,
    modifiers: {KeyModifier.ctrl},
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveWordRight,
    keyCode: KeyCode.arrowRight,
    modifiers: {KeyModifier.ctrl},
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveWordLeft,
    keyCode: KeyCode.arrowLeft,
    modifiers: {KeyModifier.alt},
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveWordRight,
    keyCode: KeyCode.arrowRight,
    modifiers: {KeyModifier.alt},
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveLeft,
    keyCode: KeyCode.arrowLeft,
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveRight,
    keyCode: KeyCode.arrowRight,
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveUp,
    keyCode: KeyCode.arrowUp,
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveDown,
    keyCode: KeyCode.arrowDown,
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveDocumentStart,
    keyCode: KeyCode.home,
    modifiers: {KeyModifier.ctrl},
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveDocumentEnd,
    keyCode: KeyCode.end,
    modifiers: {KeyModifier.ctrl},
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveLineStart,
    keyCode: KeyCode.home,
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveLineEnd,
    keyCode: KeyCode.end,
    allowShift: true,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.insertNewline,
    keyCode: KeyCode.enter,
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.escape,
    keyCode: KeyCode.escape,
  ),
];

const _emacsSingleLine = <TextEditingKeyBinding>[
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveDocumentStart,
    char: 'a',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveDocumentEnd,
    char: 'e',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveLeft,
    char: 'b',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveRight,
    char: 'f',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveWordLeft,
    char: 'b',
    modifiers: {KeyModifier.alt},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveWordRight,
    char: 'f',
    modifiers: {KeyModifier.alt},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.deleteForward,
    char: 'd',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.backspace,
    char: 'h',
    modifiers: {KeyModifier.ctrl},
  ),
];

const _emacsMultiline = <TextEditingKeyBinding>[
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveLineStart,
    char: 'a',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveLineEnd,
    char: 'e',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveLeft,
    char: 'b',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveRight,
    char: 'f',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveWordLeft,
    char: 'b',
    modifiers: {KeyModifier.alt},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.moveWordRight,
    char: 'f',
    modifiers: {KeyModifier.alt},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.deleteForward,
    char: 'd',
    modifiers: {KeyModifier.ctrl},
  ),
  TextEditingKeyBinding(
    action: TextEditingKeyAction.backspace,
    char: 'h',
    modifiers: {KeyModifier.ctrl},
  ),
];
