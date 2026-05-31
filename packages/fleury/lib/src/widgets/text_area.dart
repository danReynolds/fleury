// TextArea: a multi-line editable text widget.
//
// Reuses TextEditingController (a newline is just another character in
// the text + code-unit cursor). On top of TextInput it adds:
//   - Enter inserts a newline.
//   - Up/Down move the cursor between lines (preserving the column).
//   - Home/End move within the current line.
//   - RenderTextArea lays the text out as rows and scrolls vertically to
//     keep the cursor line in view.
//
// Not yet here: horizontal scroll / soft-wrap (long lines clip at the
// right edge), grapheme-cluster cursor movement (code-unit indices, as in
// TextInput), and a blinking cursor (solid while focused for now).

import 'package:characters/characters.dart';

import '../foundation/geometry.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
import '../rendering/text_sanitizer.dart';
import '../rendering/width_resolver.dart';
import '../terminal/events.dart';
import 'focus.dart';
import 'framework.dart';
import 'text_input.dart' show TextEditingController;

/// A multi-line editable text widget. Pair with a [TextEditingController]
/// to read/drive the text; newlines live in the text like any character.
class TextArea extends StatefulWidget {
  const TextArea({
    super.key,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.onEscape,
    this.placeholder = '',
    this.placeholderStyle = const CellStyle(dim: true),
    this.style = CellStyle.empty,
    this.cursorStyle = const CellStyle(inverse: true),
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Called when the user presses Escape; bubbles if null.
  final void Function()? onEscape;

  /// Hint text shown while the area is empty. May contain newlines.
  final String placeholder;

  /// Style for the [placeholder] text. Defaults to dim.
  final CellStyle placeholderStyle;

  final CellStyle style;
  final CellStyle cursorStyle;

  @override
  State<TextArea> createState() => _TextAreaState();
}

class _TextAreaState extends State<TextArea> implements TextInputClaimant {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'TextArea');
    _focusNode.textInputClaimant = this;
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(TextArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? TextEditingController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      _focusNode.textInputClaimant = null;
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'TextArea');
      _focusNode.textInputClaimant = this;
      _ownsFocusNode = widget.focusNode == null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Focus.maybeOf(context); // rebuild on focus change (cursor visibility)
  }

  void _onChange() => setState(() {});

  @override
  KeyEventResult onTextInput(String text) {
    _controller.insert(text);
    return KeyEventResult.handled;
  }

  // ---- line-aware cursor movement -------------------------------------

  int _lineStart(String t, int sel) {
    if (sel <= 0) return 0;
    final nl = t.lastIndexOf('\n', sel - 1);
    return nl == -1 ? 0 : nl + 1;
  }

  int _lineEnd(String t, int sel) {
    final nl = t.indexOf('\n', sel);
    return nl == -1 ? t.length : nl;
  }

  void _moveUp() {
    final t = _controller.text;
    final sel = _controller.selection;
    final start = _lineStart(t, sel);
    if (start == 0) return;
    final col = sel - start;
    final prevEnd = start - 1;
    final prevStart = _lineStart(t, prevEnd);
    final prevLen = prevEnd - prevStart;
    _controller.selection = prevStart + (col < prevLen ? col : prevLen);
  }

  void _moveDown() {
    final t = _controller.text;
    final sel = _controller.selection;
    final end = _lineEnd(t, sel);
    if (end == t.length) return;
    final col = sel - _lineStart(t, sel);
    final nextStart = end + 1;
    final nextEnd = _lineEnd(t, nextStart);
    final nextLen = nextEnd - nextStart;
    _controller.selection = nextStart + (col < nextLen ? col : nextLen);
  }

  KeyEventResult _handleKey(KeyEvent event) {
    switch (event.keyCode) {
      case KeyCode.backspace:
        _controller.backspace();
        return KeyEventResult.handled;
      case KeyCode.delete:
        _controller.delete();
        return KeyEventResult.handled;
      case KeyCode.arrowLeft:
        _controller.moveCursorLeft();
        return KeyEventResult.handled;
      case KeyCode.arrowRight:
        _controller.moveCursorRight();
        return KeyEventResult.handled;
      case KeyCode.arrowUp:
        _moveUp();
        return KeyEventResult.handled;
      case KeyCode.arrowDown:
        _moveDown();
        return KeyEventResult.handled;
      case KeyCode.home:
        _controller.selection = _lineStart(
          _controller.text,
          _controller.selection,
        );
        return KeyEventResult.handled;
      case KeyCode.end:
        _controller.selection = _lineEnd(
          _controller.text,
          _controller.selection,
        );
        return KeyEventResult.handled;
      case KeyCode.enter:
        _controller.insert('\n');
        return KeyEventResult.handled;
      case KeyCode.escape:
        if (widget.onEscape != null) {
          widget.onEscape!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    if (_ownsController) _controller.dispose();
    _focusNode.textInputClaimant = null;
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKey: _handleKey,
      child: _TextAreaDisplay(
        text: _controller.text,
        selection: _controller.selection,
        placeholder: widget.placeholder,
        placeholderStyle: widget.placeholderStyle,
        style: widget.style,
        cursorStyle: widget.cursorStyle,
        cursorVisible: _focusNode.hasFocus,
      ),
    );
  }
}

class _TextAreaDisplay extends LeafRenderObjectWidget {
  const _TextAreaDisplay({
    required this.text,
    required this.selection,
    required this.placeholder,
    required this.placeholderStyle,
    required this.style,
    required this.cursorStyle,
    required this.cursorVisible,
  });

  final String text;
  final int selection;
  final String placeholder;
  final CellStyle placeholderStyle;
  final CellStyle style;
  final CellStyle cursorStyle;
  final bool cursorVisible;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderTextArea(
    text: text,
    selection: selection,
    placeholder: placeholder,
    placeholderStyle: placeholderStyle,
    style: style,
    cursorStyle: cursorStyle,
    cursorVisible: cursorVisible,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderTextArea renderObject,
  ) {
    renderObject
      ..text = text
      ..selection = selection
      ..placeholder = placeholder
      ..placeholderStyle = placeholderStyle
      ..style = style
      ..cursorStyle = cursorStyle
      ..cursorVisible = cursorVisible;
  }
}

/// Lays out text as rows and scrolls vertically to keep the cursor line
/// visible; paints a one-cell cursor at the selection.
class RenderTextArea extends RenderObject {
  RenderTextArea({
    required String text,
    required int selection,
    String placeholder = '',
    CellStyle placeholderStyle = const CellStyle(dim: true),
    CellStyle style = CellStyle.empty,
    CellStyle cursorStyle = const CellStyle(inverse: true),
    bool cursorVisible = true,
    WidthResolver widthResolver = const DefaultWidthResolver(),
    TerminalProfile profile = TerminalProfile.standard,
  }) : _text = _sanitize(text),
       _selection = selection.clamp(0, text.length),
       _placeholder = _sanitize(placeholder),
       _placeholderStyle = placeholderStyle,
       _style = style,
       _cursorStyle = cursorStyle,
       _cursorVisible = cursorVisible,
       _widthResolver = widthResolver,
       _profile = profile;

  static String _sanitize(String value) =>
      value.split('\n').map(sanitizeForDisplay).join('\n');

  String _text;
  int _selection;
  String _placeholder;
  CellStyle _placeholderStyle;
  CellStyle _style;
  CellStyle _cursorStyle;
  bool _cursorVisible;
  final WidthResolver _widthResolver;
  final TerminalProfile _profile;
  int _scrollTop = 0;

  set text(String value) {
    final s = _sanitize(value);
    if (s == _text) return;
    _text = s;
    _selection = _selection.clamp(0, _text.length);
  }

  set placeholder(String value) => _placeholder = _sanitize(value);
  set placeholderStyle(CellStyle value) => _placeholderStyle = value;
  set selection(int value) => _selection = value.clamp(0, _text.length);
  set style(CellStyle value) => _style = value;
  set cursorStyle(CellStyle value) => _cursorStyle = value;
  set cursorVisible(bool value) => _cursorVisible = value;

  bool get _showPlaceholder => _text.isEmpty && _placeholder.isNotEmpty;

  List<String> get _lines => _text.split('\n');

  /// (line, column) of the cursor within [_lines].
  (int, int) _cursorLineCol(List<String> lines) {
    var idx = 0;
    for (var i = 0; i < lines.length; i++) {
      final len = lines[i].length;
      if (_selection <= idx + len) return (i, _selection - idx);
      idx += len + 1; // + the newline
    }
    return (lines.length - 1, lines.isEmpty ? 0 : lines.last.length);
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final lines = _showPlaceholder ? _placeholder.split('\n') : _lines;
    var widest = 0;
    for (final line in lines) {
      final w = _widthResolver.widthOfText(line, _profile);
      if (w > widest) widest = w;
    }
    final cols = constraints.hasBoundedWidth ? constraints.maxCols! : widest;
    final rows = constraints.hasBoundedHeight
        ? constraints.maxRows!
        : lines.length;

    // Scroll so the cursor's line stays visible.
    final cursorLine = _cursorLineCol(lines).$1;
    if (cursorLine < _scrollTop) {
      _scrollTop = cursorLine;
    } else if (rows > 0 && cursorLine >= _scrollTop + rows) {
      _scrollTop = cursorLine - rows + 1;
    }
    final maxScroll = lines.length - rows;
    if (_scrollTop > maxScroll) _scrollTop = maxScroll;
    if (_scrollTop < 0) _scrollTop = 0;

    return constraints.constrain(CellSize(cols, rows));
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    if (size.isEmpty) return;

    // Empty: paint the (possibly multi-line) placeholder, with the
    // cursor over the very first cell when visible.
    if (_showPlaceholder) {
      final phLines = _placeholder.split('\n');
      final maxCol = offset.col + size.cols;
      for (var r = 0; r < size.rows && r < phLines.length; r++) {
        final row = offset.row + r;
        var col = offset.col;
        var first = r == 0;
        for (final g in phLines[r].characters) {
          if (col >= maxCol) break;
          final st = (first && _cursorVisible)
              ? _placeholderStyle.merge(_cursorStyle)
              : _placeholderStyle;
          buffer.writeGrapheme(
            CellOffset(col, row),
            g,
            style: st,
            widthResolver: _widthResolver,
            profile: _profile,
          );
          col += _widthResolver.widthOfGrapheme(g, _profile);
          first = false;
        }
      }
      return;
    }

    final lines = _lines;
    final (cursorLine, cursorCol) = _cursorLineCol(lines);
    final maxCol = offset.col + size.cols;

    for (var r = 0; r < size.rows; r++) {
      final li = _scrollTop + r;
      if (li >= lines.length) break;
      final line = lines[li];
      final row = offset.row + r;
      var col = offset.col;
      var cu = 0;
      var paintedCursor = false;

      for (final g in line.characters) {
        if (col >= maxCol) break;
        final atCursor = li == cursorLine && cu == cursorCol;
        final st = (atCursor && _cursorVisible)
            ? _style.merge(_cursorStyle)
            : _style;
        buffer.writeGrapheme(
          CellOffset(col, row),
          g,
          style: st,
          widthResolver: _widthResolver,
          profile: _profile,
        );
        col += _widthResolver.widthOfGrapheme(g, _profile);
        cu += g.length;
        if (atCursor) paintedCursor = true;
      }

      if (li == cursorLine &&
          !paintedCursor &&
          _cursorVisible &&
          col < maxCol) {
        buffer.writeGrapheme(
          CellOffset(col, row),
          ' ',
          style: _style.merge(_cursorStyle),
        );
      }
    }
  }
}
