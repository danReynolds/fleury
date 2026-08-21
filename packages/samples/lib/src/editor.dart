// Editor: a small file editor you can drive as either nano or vim, toggling
// between the two live on the same buffer. It's the showcase for Fleury's
// key-binding discoverability:
//
//   * nano  — modeless; every command is a Ctrl-chord, and the always-on
//     shortcut bar (a `KeyHintBar`, fed by `KeyBindings.activeOf`) shows you
//     all of them. "Show everything, always."
//   * vim   — modal; NORMAL keys are commands, INSERT keys are text. Multi-key
//     commands (`dd`, `gg`, the `Space` leader) are revealed on demand by the
//     which-key popup (`WhichKey`, fed by `KeyBindings.pendingOf`).
//     "Reveal on demand."
//
// The two personalities also exercise the framework's two input-routing
// models: nano proves text and Ctrl-chords coexist with no modes (typing `k`
// inserts, `^K` cuts, because Ctrl-chords arrive as key events, not text);
// vim proves the modal claimant flip (NORMAL declines printables so they route
// to `KeyBindings` as commands; INSERT claims them as text).

import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

import 'scaffold.dart';

/// Which editor the keys behave as.
enum EditorPersonality { nano, vim }

/// Vim's input mode (irrelevant to nano, which is always text-accepting).
enum VimMode { normal, insert }

const String _sampleText =
    'The quick brown fox jumps over the lazy dog.\n'
    'Fleury renders this editor to a terminal and a browser alike.\n'
    'Toggle nano/vim with Ctrl+B — the same buffer, two keymaps.\n'
    'In vim, press d or the Space leader to see which-key.\n'
    'In nano, the shortcut bar shows every command.';

/// The editable document: lines, a cursor, the active personality/mode, and a
/// pending count register (vim `3dd`). A [ChangeNotifier] so the surface and
/// the status chrome rebuild on every edit.
class EditorModel with ChangeNotifier {
  EditorModel(String initial) : _lines = initial.split('\n');

  List<String> _lines;
  int _row = 0;
  int _col = 0;
  EditorPersonality personality = EditorPersonality.nano;
  VimMode vimMode = VimMode.normal;
  int _count = 0; // pending vim count (`3` in `3dd`); 0 = none
  String _clipboard = '';
  String status = '';

  /// Vim marks: a letter → the position `m<letter>` recorded.
  final Map<String, ({int row, int col})> _marks = {};

  /// The marks set so far, for the status line.
  Iterable<String> get markNames => _marks.keys.toList()..sort();

  List<String> get lines => List<String>.unmodifiable(_lines);
  int get row => _row;
  int get col => _col;
  int get pendingCount => _count;

  /// Whether typed text is inserted into the document right now: always in
  /// nano, only in INSERT under vim.
  bool get acceptsText =>
      personality == EditorPersonality.nano || vimMode == VimMode.insert;

  String get _line => _lines[_row];
  set _line(String value) => _lines[_row] = value;

  // A block cursor (vim NORMAL) can't sit past the last character; a bar
  // cursor (nano / INSERT) can sit at end-of-line.
  int get _maxCol {
    final len = _line.length;
    final capped = acceptsText ? len : len - 1;
    return capped < 0 ? 0 : capped;
  }

  void _clamp() {
    if (_row < 0) _row = 0;
    if (_row >= _lines.length) _row = _lines.length - 1;
    if (_col < 0) _col = 0;
    if (_col > _maxCol) _col = _maxCol;
  }

  void _changed() {
    _clamp();
    notifyListeners();
  }

  // ---- personality / mode -------------------------------------------------

  void togglePersonality() {
    personality = personality == EditorPersonality.nano
        ? EditorPersonality.vim
        : EditorPersonality.nano;
    // Entering vim starts in NORMAL; nano is always text-accepting.
    vimMode = VimMode.normal;
    _count = 0;
    status = personality == EditorPersonality.nano ? 'nano' : 'vim — NORMAL';
    _changed();
  }

  void enterInsert() {
    vimMode = VimMode.insert;
    _count = 0;
    status = '-- INSERT --';
    _changed();
  }

  void enterNormal() {
    vimMode = VimMode.normal;
    // Leaving insert, the block cursor steps back onto the last typed char.
    if (_col > 0 && _col > _maxCol) _col -= 1;
    status = '';
    _changed();
  }

  // ---- count register (vim `3dd`) ----------------------------------------

  void pushCountDigit(int digit) {
    _count = _count * 10 + digit;
    status = 'count: $_count';
    notifyListeners();
  }

  int _takeCount() {
    final n = _count == 0 ? 1 : _count;
    _count = 0;
    return n;
  }

  // ---- text edits ---------------------------------------------------------

  void insertText(String text) {
    _line = _line.substring(0, _col) + text + _line.substring(_col);
    _col += text.length;
    _changed();
  }

  void newline() {
    final before = _line.substring(0, _col);
    final after = _line.substring(_col);
    _line = before;
    _lines.insert(_row + 1, after);
    _row += 1;
    _col = 0;
    _changed();
  }

  void backspace() {
    if (_col > 0) {
      _line = _line.substring(0, _col - 1) + _line.substring(_col);
      _col -= 1;
    } else if (_row > 0) {
      final prevLen = _lines[_row - 1].length;
      _lines[_row - 1] += _line;
      _lines.removeAt(_row);
      _row -= 1;
      _col = prevLen;
    }
    _changed();
  }

  /// Delete the character under the cursor (vim `x`).
  void deleteCharUnderCursor() {
    if (_col < _line.length) {
      _line = _line.substring(0, _col) + _line.substring(_col + 1);
    }
    _changed();
  }

  /// Delete whole lines (vim `dd`, nano `^K`), honouring a pending count.
  void deleteLine() {
    final n = _takeCount();
    _clipboard = '';
    for (var i = 0; i < n && _lines.isNotEmpty; i++) {
      _clipboard += (i == 0 ? '' : '\n') + _lines[_row];
      _lines.removeAt(_row);
      if (_row >= _lines.length) _row = _lines.length - 1;
    }
    if (_lines.isEmpty) _lines = <String>[''];
    _col = 0;
    status = 'cut $n line${n == 1 ? '' : 's'}';
    _changed();
  }

  /// Delete from the cursor to the end of the current word (vim `dw`).
  void deleteWord() {
    final line = _line;
    var end = _col;
    while (end < line.length && line[end] != ' ') {
      end++;
    }
    while (end < line.length && line[end] == ' ') {
      end++;
    }
    _clipboard = line.substring(_col, end);
    _line = line.substring(0, _col) + line.substring(end);
    _changed();
  }

  /// Delete from the cursor to end of line (vim `d$`).
  void deleteToLineEnd() {
    _clipboard = _line.substring(_col);
    _line = _line.substring(0, _col);
    _changed();
  }

  /// Paste the last cut text after the cursor (nano `^U`, vim `p`).
  void paste() {
    if (_clipboard.contains('\n')) {
      final parts = _clipboard.split('\n');
      _lines.insertAll(_row + 1, parts);
      _row += 1;
      _col = 0;
    } else {
      insertText(_clipboard);
      return;
    }
    _changed();
  }

  void openLineBelow() {
    _lines.insert(_row + 1, '');
    _row += 1;
    _col = 0;
    enterInsert();
  }

  void openLineAbove() {
    _lines.insert(_row, '');
    _col = 0;
    enterInsert();
  }

  // ---- movement -----------------------------------------------------------

  void moveLeft() {
    _col -= 1;
    _changed();
  }

  void moveRight() {
    _col += 1;
    _changed();
  }

  void moveUp() {
    _row -= 1;
    _changed();
  }

  void moveDown() {
    _row += 1;
    _changed();
  }

  void lineStart() {
    _col = 0;
    _changed();
  }

  void lineEnd() {
    _col = _line.length;
    _changed();
  }

  void wordForward() {
    final line = _line;
    var i = _col;
    while (i < line.length && line[i] != ' ') {
      i++;
    }
    while (i < line.length && line[i] == ' ') {
      i++;
    }
    _col = i;
    _changed();
  }

  void wordBack() {
    final line = _line;
    var i = _col - 1;
    while (i > 0 && line[i - 1] == ' ') {
      i--;
    }
    while (i > 0 && line[i - 1] != ' ') {
      i--;
    }
    _col = i < 0 ? 0 : i;
    _changed();
  }

  /// `m<letter>` — records the cursor under a letter.
  void setMark(String letter) {
    _marks[letter] = (row: _row, col: _col);
    flash("mark '$letter set");
  }

  /// `'<letter>` — jumps to a recorded mark, or says why it cannot.
  void jumpToMark(String letter) {
    final mark = _marks[letter];
    if (mark == null) {
      flash("mark '$letter is not set");
      return;
    }
    _row = mark.row.clamp(0, _lines.length - 1);
    _col = mark.col.clamp(0, _maxColAt(_row));
    _changed();
    flash("jumped to '$letter");
  }

  int _maxColAt(int row) {
    final len = _lines[row].length;
    final capped = acceptsText ? len : len - 1;
    return capped < 0 ? 0 : capped;
  }

  void gotoTop() {
    _row = 0;
    _col = 0;
    _changed();
  }

  void gotoBottom() {
    _row = _lines.length - 1;
    _col = 0;
    _changed();
  }

  void pageUp() {
    _row -= 10;
    _changed();
  }

  void pageDown() {
    _row += 10;
    _changed();
  }

  // ---- misc ---------------------------------------------------------------

  void reportPosition() {
    status = 'line ${_row + 1}, col ${_col + 1}';
    notifyListeners();
  }

  void flash(String message) {
    status = message;
    notifyListeners();
  }
}

// ===========================================================================
// The app
// ===========================================================================

/// The nano/vim editor showcase — a self-contained root that runs in a
/// terminal or over `fleury serve`.
class EditorApp extends StatelessWidget {
  const EditorApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const SampleScaffold(child: _EditorBody());
}

class _EditorBody extends StatefulWidget {
  const _EditorBody();

  @override
  State<_EditorBody> createState() => _EditorBodyState();
}

class _EditorBodyState extends State<_EditorBody> implements TextInputClaimant {
  final EditorModel _model = EditorModel(_sampleText);
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'editor')..textInputClaimant = this;
    _model.addListener(_onModelChanged);
  }

  void _onModelChanged() => setState(() {});

  @override
  void dispose() {
    _model.removeListener(_onModelChanged);
    _focusNode.textInputClaimant = null;
    _focusNode.dispose();
    super.dispose();
  }

  // TextInputClaimant: the modal flip. Text is inserted into the document only
  // when the model accepts it (always in nano, only in vim INSERT); otherwise
  // it's declined so a printable routes to KeyBindings as a command.
  @override
  KeyEventResult onTextInput(String text) {
    if (!_model.acceptsText) return KeyEventResult.ignored;
    _model.insertText(text);
    return KeyEventResult.handled;
  }

  @override
  KeyEventResult onPaste(String text) {
    if (!_model.acceptsText) return KeyEventResult.ignored;
    _model.insertText(text);
    return KeyEventResult.handled;
  }

  bool get _isVim => _model.personality == EditorPersonality.vim;
  bool get _isNormal => _model.vimMode == VimMode.normal;

  @override
  Widget build(BuildContext context) {
    // Fleury's SelectionArea makes the rendered text drag-selectable and
    // copies on release (the terminal "select to copy" idiom) as well as on
    // Ctrl+C; over `fleury serve` it writes to the browser clipboard. Its keys
    // bubble when idle, so they coexist with the editor's own bindings.
    return SelectionArea(
      copyOnRelease: true,
      child: KeyBindings(
        bindings: _bindings(),
        child: WhichKey(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Focus(
                    focusNode: _focusNode,
                    autofocus: true,
                    child: _BufferView(model: _model),
                  ),
                ),
              ),
              _StatusLine(model: _model),
              _chrome(context),
            ],
          ),
        ),
      ),
    );
  }

  /// The discoverability chrome: nano's always-on shortcut bar (a `KeyHintBar`)
  /// vs vim's sparse hint (the which-key popup does the rest).
  Widget _chrome(BuildContext context) {
    final theme = Theme.of(context);
    if (!_isVim) {
      return Container(
        color: theme.colorScheme.foreground,
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: KeyHintBar(
          style: CellStyle(foreground: theme.colorScheme.background),
        ),
      );
    }
    final hint = _isNormal
        ? 'NORMAL · h j k l move · i insert · x del · press d, g or Space for more'
        : 'INSERT · type to edit · Esc for normal';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Text(
        hint,
        style: CellStyle(foreground: theme.colorScheme.primary),
      ),
    );
  }

  // ---- keymaps ------------------------------------------------------------

  List<KeyBinding> _bindings() {
    // Ctrl+B toggles the personality from anywhere: it's a key event (not
    // text), so it reaches the bindings even while nano/INSERT claims text,
    // and unlike a function key it isn't swallowed by the OS (macOS media
    // keys) or the browser.
    final toggle = KeyBinding(
      KeySequence.ctrl.b,
      label: _isVim ? 'nano' : 'vim',
      onTrigger: (_) => _model.togglePersonality(),
    );
    return switch (_model.personality) {
      EditorPersonality.nano => [toggle, ..._nanoBindings()],
      EditorPersonality.vim =>
        _isNormal
            ? [toggle, ..._vimNormalBindings()]
            : [toggle, ..._vimInsertBindings()],
    };
  }

  // Nano: modeless. Text inserts directly; every command is a Ctrl-chord, all
  // labeled so the KeyHintBar advertises them.
  /// Prompts for the single letter that names a mark, then applies [apply].
  ///
  /// The whole prompt is four lines because `nextKey` handles the hard parts:
  /// it outranks every routed lane while pending (so the editor's own `i` and
  /// Escape bindings do not steal the letter), it is never completed by a
  /// recovery-synthesized event (a blur must not silently "choose" a mark),
  /// and it completes null if this widget goes away.
  Future<void> _awaitMarkLetter(void Function(String letter) apply) async {
    _model.flash('mark: press a letter (Esc to cancel)');
    final key = await Keyboard.nextKey(context);
    if (key == null) return; // unmounted, or the scope went away
    if (key.code == KeyCode.escape) {
      _model.flash('');
      return;
    }
    final letter = key.code.character;
    if (letter == null || !RegExp(r'^[a-zA-Z]$').hasMatch(letter)) {
      _model.flash('marks are named by a letter');
      return;
    }
    apply(letter);
  }

  List<KeyBinding> _nanoBindings() => [
    KeyBinding(
      KeySequence.ctrl.o,
      label: 'Write Out',
      onTrigger: (_) => _model.flash('Saved ✓'),
    ),
    KeyBinding(
      KeySequence.ctrl.x,
      label: 'Exit',
      onTrigger: (_) => _model.flash('Ctrl+C to quit'),
    ),
    KeyBinding(
      KeySequence.ctrl.k,
      label: 'Cut',
      onTrigger: (_) => _model.deleteLine(),
    ),
    KeyBinding(
      KeySequence.ctrl.u,
      label: 'Paste',
      onTrigger: (_) => _model.paste(),
    ),
    KeyBinding(
      KeySequence.ctrl.a,
      label: 'Home',
      onTrigger: (_) => _model.lineStart(),
    ),
    KeyBinding(
      KeySequence.ctrl.e,
      label: 'End',
      onTrigger: (_) => _model.lineEnd(),
    ),
    KeyBinding(
      KeySequence.ctrl.y,
      label: 'Prev Pg',
      onTrigger: (_) => _model.pageUp(),
    ),
    KeyBinding(
      KeySequence.ctrl.v,
      label: 'Next Pg',
      onTrigger: (_) => _model.pageDown(),
    ),
    KeyBinding(
      KeySequence.ctrl.c,
      label: 'Where',
      onTrigger: (_) => _model.reportPosition(),
    ),
    ..._editingKeys(),
  ];

  // Vim NORMAL: printables are commands (the surface declines text). Multi-key
  // commands are sequences, so which-key reveals them.
  List<KeyBinding> _vimNormalBindings() => [
    KeyBinding(
      KeyCode.h,
      aliases: [KeyCode.arrowLeft],
      onTrigger: (_) => _model.moveLeft(),
      includeRepeats: true,
    ),
    KeyBinding(
      KeyCode.l,
      aliases: [KeyCode.arrowRight],
      onTrigger: (_) => _model.moveRight(),
      includeRepeats: true,
    ),
    KeyBinding(
      KeyCode.k,
      aliases: [KeyCode.arrowUp],
      onTrigger: (_) => _model.moveUp(),
      includeRepeats: true,
    ),
    KeyBinding(
      KeyCode.j,
      aliases: [KeyCode.arrowDown],
      onTrigger: (_) => _model.moveDown(),
      includeRepeats: true,
    ),
    KeyBinding(KeyCode.w, onTrigger: (_) => _model.wordForward()),
    KeyBinding(KeyCode.b, onTrigger: (_) => _model.wordBack()),
    KeyBinding(KeyCode.char('0'), onTrigger: (_) => _model.lineStart()),
    KeyBinding(KeyCode.char(r'$'), onTrigger: (_) => _model.lineEnd()),
    KeyBinding(
      KeyCode.x,
      label: 'delete char',
      onTrigger: (_) => _model.deleteCharUnderCursor(),
    ),
    KeyBinding(
      KeyCode.i,
      label: 'insert',
      onTrigger: (_) => _model.enterInsert(),
    ),
    KeyBinding(
      KeyCode.a,
      label: 'append',
      // Enter INSERT first so the cursor can advance past the last character
      // (a block cursor is clamped to len-1; a bar cursor reaches len).
      onTrigger: (_) {
        _model.enterInsert();
        _model.moveRight();
      },
    ),
    KeyBinding(
      KeyCode.char('A'),
      label: 'append at end',
      onTrigger: (_) {
        _model.enterInsert();
        _model.lineEnd();
      },
    ),
    KeyBinding(
      KeyCode.o,
      label: 'open below',
      onTrigger: (_) => _model.openLineBelow(),
    ),
    KeyBinding(
      KeyCode.char('O'),
      label: 'open above',
      onTrigger: (_) => _model.openLineAbove(),
    ),
    // Delete family — the `d` prefix reveals its completions in which-key.
    KeyBinding(
      KeySequence.d.d,
      label: 'delete line',
      onTrigger: (_) => _model.deleteLine(),
    ),
    KeyBinding(
      KeySequence.d.w,
      label: 'delete word',
      onTrigger: (_) => _model.deleteWord(),
    ),
    KeyBinding(
      KeySequence.d.char(r'$'),
      label: 'delete to end',
      onTrigger: (_) => _model.deleteToLineEnd(),
    ),
    // Marks — the case a declared sequence structurally cannot express.
    //
    // `m` takes ANY letter as its second step: 26 bindings would be a lie
    // (they would appear in the hint bar as 26 separate commands), and a
    // two-step `KeySequence` needs both steps named up front. So `m` is one
    // binding that then *awaits* one key. `nextKey` is scope-tied by
    // signature — if this editor unmounts mid-prompt the future completes
    // null, so the capture can never outlive the UI that started it and eat
    // the app's input (RFC 0020 §17.2).
    KeyBinding(
      KeyCode.m,
      label: 'set mark',
      onTrigger: (_) => _awaitMarkLetter(_model.setMark),
    ),
    KeyBinding(
      KeyCode.char("'"),
      label: 'jump to mark',
      onTrigger: (_) => _awaitMarkLetter(_model.jumpToMark),
    ),
    // Goto — `gg` top, `G` bottom.
    KeyBinding(
      KeySequence.g.g,
      label: 'go to top',
      onTrigger: (_) => _model.gotoTop(),
    ),
    KeyBinding(
      KeyCode.char('G'),
      label: 'go to bottom',
      onTrigger: (_) => _model.gotoBottom(),
    ),
    // Space leader — the actions menu, front and centre in which-key.
    KeyBinding(
      KeySequence.space.w,
      label: 'write / save',
      onTrigger: (_) => _model.flash('Saved ✓'),
    ),
    KeyBinding(
      KeySequence.space.q,
      label: 'quit',
      onTrigger: (_) => _model.flash('Ctrl+C to quit'),
    ),
    KeyBinding(
      KeySequence.space.p,
      label: 'paste',
      onTrigger: (_) => _model.paste(),
    ),
    // Count register: 1–9 accumulate (`3dd`). Hidden from any bar.
    for (var digit = 1; digit <= 9; digit++)
      KeyBinding(
        KeyCode.char('$digit'),
        onTrigger: (_) => _model.pushCountDigit(digit),
      ),
  ];

  // Vim INSERT: text is claimed by the surface; only the non-text keys are
  // bound here.
  List<KeyBinding> _vimInsertBindings() => [
    KeyBinding(KeyCode.escape, onTrigger: (_) => _model.enterNormal()),
    ..._editingKeys(),
  ];

  // Non-text editing keys shared by nano and vim INSERT (they arrive as key
  // events, so they route here regardless of the text claim).
  List<KeyBinding> _editingKeys() => [
    KeyBinding(
      KeyCode.arrowLeft,
      onTrigger: (_) => _model.moveLeft(),
      includeRepeats: true,
    ),
    KeyBinding(
      KeyCode.arrowRight,
      onTrigger: (_) => _model.moveRight(),
      includeRepeats: true,
    ),
    KeyBinding(
      KeyCode.arrowUp,
      onTrigger: (_) => _model.moveUp(),
      includeRepeats: true,
    ),
    KeyBinding(
      KeyCode.arrowDown,
      onTrigger: (_) => _model.moveDown(),
      includeRepeats: true,
    ),
    KeyBinding(KeyCode.home, onTrigger: (_) => _model.lineStart()),
    KeyBinding(KeyCode.end, onTrigger: (_) => _model.lineEnd()),
    KeyBinding(KeyCode.enter, onTrigger: (_) => _model.newline()),
    KeyBinding(KeyCode.backspace, onTrigger: (_) => _model.backspace()),
  ];
}

/// Renders the buffer with a block cursor (an inverted cell — the standard
/// TUI caret, which reads clearly in both the terminal and the browser).
class _BufferView extends StatelessWidget {
  const _BufferView({required this.model});

  final EditorModel model;

  @override
  Widget build(BuildContext context) {
    final lines = model.lines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var r = 0; r < lines.length; r++)
          _line(lines[r], r == model.row ? model.col : null),
      ],
    );
  }

  Widget _line(String text, int? cursorCol) {
    if (cursorCol == null) return Text(text.isEmpty ? ' ' : text);
    const cursorStyle = CellStyle(reverse: true);
    final char = cursorCol < text.length ? text[cursorCol] : ' ';
    final after = cursorCol < text.length ? text.substring(cursorCol + 1) : '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cursorCol > 0) Text(text.substring(0, cursorCol)),
        Text(char, style: cursorStyle),
        if (after.isNotEmpty) Text(after),
      ],
    );
  }
}

/// The mode/personality/count status line just above the chrome.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.model});

  final EditorModel model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = model.personality == EditorPersonality.nano ? 'nano' : 'vim';
    final left = model.status.isNotEmpty ? model.status : name;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              left,
              style: CellStyle(
                foreground: theme.colorScheme.primary,
                bold: true,
              ),
            ),
          ),
          Text('$name  ·  Ctrl+B to switch', style: theme.mutedStyle),
        ],
      ),
    );
  }
}
