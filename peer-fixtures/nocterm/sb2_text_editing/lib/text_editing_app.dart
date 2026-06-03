import 'package:nocterm/nocterm.dart';

enum Sb2FocusTarget { composer, editor, secret }

final class Sb2TextEditingFixture {
  const Sb2TextEditingFixture({
    required this.composerText,
    required this.editorText,
    required this.secretText,
    required this.pasteText,
    required this.pasteMarker,
    required this.selectionReplacement,
    required this.historyEntries,
    required this.historyDraft,
  });

  factory Sb2TextEditingFixture.generate({int textChars = 10000}) {
    const pasteMarker = 'SB2_PASTE_MARKER';
    return Sb2TextEditingFixture(
      composerText: 'deploy service --target staging',
      editorText: _mixedText(
        targetChars: textChars,
        seed: 42,
        linePrefix: 'editor',
        includeNewlines: true,
      ),
      secretText: 'nocterm-secret-do-not-leak',
      pasteText:
          '$pasteMarker ${_mixedText(targetChars: 4096, seed: 77, linePrefix: 'paste', includeNewlines: false)}',
      pasteMarker: pasteMarker,
      selectionReplacement: '[edited]',
      historyEntries: const [
        'status --json',
        'logs --tail',
        'deploy --dry-run',
      ],
      historyDraft: 'draft command',
    );
  }

  final String composerText;
  final String editorText;
  final String secretText;
  final String pasteText;
  final String pasteMarker;
  final String selectionReplacement;
  final List<String> historyEntries;
  final String historyDraft;
}

class Sb2TextEditingApp extends StatefulComponent {
  const Sb2TextEditingApp({super.key, required this.fixture});

  final Sb2TextEditingFixture fixture;

  @override
  Sb2TextEditingState createState() => Sb2TextEditingState();
}

class Sb2TextEditingState extends State<Sb2TextEditingApp> {
  late final TextEditingController composer;
  late final TextEditingController editor;
  late final TextEditingController secret;

  Sb2FocusTarget _focus = Sb2FocusTarget.composer;
  final _undoStack = <String>[];
  final _redoStack = <String>[];
  late String _lastEditorText;
  bool _suppressEditorHistory = false;
  int? _historyIndex;
  String? _historyDraft;
  var completionAccepted = false;

  Sb2TextEditingFixture get fixture => component.fixture;
  Sb2FocusTarget get focusTarget => _focus;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  @override
  void initState() {
    super.initState();
    composer = TextEditingController(text: fixture.composerText);
    editor = TextEditingController(text: fixture.editorText);
    secret = TextEditingController(text: fixture.secretText);
    _lastEditorText = editor.text;
    editor.addListener(_recordEditorChange);
  }

  @override
  void dispose() {
    editor.removeListener(_recordEditorChange);
    composer.dispose();
    editor.dispose();
    secret.dispose();
    super.dispose();
  }

  void focusComposer() => _setFocus(Sb2FocusTarget.composer);
  void focusEditor() => _setFocus(Sb2FocusTarget.editor);
  void focusSecret() => _setFocus(Sb2FocusTarget.secret);

  void _setFocus(Sb2FocusTarget target) {
    setState(() {
      _focus = target;
    });
  }

  void setComposerText(String value) {
    composer.text = value;
    composer.selection = TextSelection.collapsed(offset: value.length);
    completionAccepted = false;
  }

  void moveEditorCursorToEnd() {
    editor.selection = TextSelection.collapsed(offset: editor.text.length);
  }

  bool _handleComposerKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.tab) {
      return _acceptCompletion();
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      return _showPreviousHistory();
    }
    if (event.logicalKey == LogicalKey.arrowDown) {
      return _showNextHistory();
    }
    return false;
  }

  bool _acceptCompletion() {
    if (!composer.text.endsWith('che')) return false;
    composer.text =
        '${composer.text.substring(0, composer.text.length - 3)}checkout';
    composer.selection = TextSelection.collapsed(offset: composer.text.length);
    completionAccepted = true;
    return true;
  }

  bool _showPreviousHistory() {
    if (fixture.historyEntries.isEmpty) return false;
    _historyDraft ??= composer.text;
    final next = _historyIndex == null
        ? fixture.historyEntries.length - 1
        : (_historyIndex! - 1).clamp(0, fixture.historyEntries.length - 1);
    _historyIndex = next;
    composer.text = fixture.historyEntries[next];
    composer.selection = TextSelection.collapsed(offset: composer.text.length);
    return true;
  }

  bool _showNextHistory() {
    final current = _historyIndex;
    if (current == null) return false;
    if (current >= fixture.historyEntries.length - 1) {
      composer.text = _historyDraft ?? '';
      composer.selection = TextSelection.collapsed(
        offset: composer.text.length,
      );
      _historyIndex = null;
      _historyDraft = null;
      return true;
    }
    _historyIndex = current + 1;
    composer.text = fixture.historyEntries[_historyIndex!];
    composer.selection = TextSelection.collapsed(offset: composer.text.length);
    return true;
  }

  bool _handleEditorKey(KeyboardEvent event) {
    if (event.matches(LogicalKey.keyZ, ctrl: true)) {
      return _undoEditor();
    }
    if (event.matches(LogicalKey.keyY, ctrl: true)) {
      return _redoEditor();
    }
    return false;
  }

  void _recordEditorChange() {
    if (_suppressEditorHistory) {
      _lastEditorText = editor.text;
      return;
    }
    if (editor.text == _lastEditorText) return;
    _undoStack.add(_lastEditorText);
    if (_undoStack.length > 200) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    _lastEditorText = editor.text;
  }

  bool _undoEditor() {
    if (_undoStack.isEmpty) return false;
    _redoStack.add(editor.text);
    _applyEditorText(_undoStack.removeLast());
    return true;
  }

  bool _redoEditor() {
    if (_redoStack.isEmpty) return false;
    _undoStack.add(editor.text);
    _applyEditorText(_redoStack.removeLast());
    return true;
  }

  void _applyEditorText(String value) {
    _suppressEditorHistory = true;
    editor.text = value;
    editor.selection = TextSelection.collapsed(offset: editor.text.length);
    _lastEditorText = editor.text;
    _suppressEditorHistory = false;
  }

  @override
  Component build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Nocterm SB.2 Text Editing'),
        const Text('Composer'),
        TextField(
          controller: composer,
          focused: _focus == Sb2FocusTarget.composer,
          width: 72,
          decoration: const InputDecoration(
            border: BoxBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 1),
          ),
          placeholder: 'Command composer',
          showCursor: true,
          cursorBlinkRate: null,
          onKeyEvent: _handleComposerKey,
        ),
        const Text('Editor'),
        TextField(
          controller: editor,
          focused: _focus == Sb2FocusTarget.editor,
          width: 72,
          height: 12,
          maxLines: 12,
          decoration: const InputDecoration(
            border: BoxBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 1),
          ),
          placeholder: 'Longform editor',
          showCursor: true,
          cursorBlinkRate: null,
          onKeyEvent: _handleEditorKey,
        ),
        const Text('Secret'),
        TextField(
          controller: secret,
          focused: _focus == Sb2FocusTarget.secret,
          width: 72,
          obscureText: true,
          decoration: const InputDecoration(
            border: BoxBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 1),
          ),
          placeholder: 'Secret token',
          showCursor: true,
          cursorBlinkRate: null,
        ),
      ],
    );
  }
}

String _mixedText({
  required int targetChars,
  required int seed,
  required String linePrefix,
  required bool includeNewlines,
}) {
  const emoji = '\u{1F642}';
  const cjk = '\u6F22\u5B57';
  const combining = 'e\u0301';
  const longToken =
      '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  final buffer = StringBuffer();
  var i = 0;
  while (buffer.length < targetChars) {
    final lane = (i + seed) % 5;
    buffer.write('$linePrefix-$i ');
    switch (lane) {
      case 0:
        buffer.write('ascii-$longToken ');
      case 1:
        buffer.write('emoji-$emoji ');
      case 2:
        buffer.write('cjk-$cjk ');
      case 3:
        buffer.write('combining-$combining ');
      default:
        buffer.write('wide-$cjk-$emoji-$combining ');
    }
    if (includeNewlines && i % 8 == 7) {
      buffer.write('\n');
    }
    i += 1;
  }
  return buffer.toString().substring(0, targetChars);
}
