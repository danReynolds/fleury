// TextArea: a multi-line editable text widget.
//
// Reuses TextEditingController (a newline is just another character in
// the shared editing value). On top of TextInput it adds:
//   - Enter inserts a newline.
//   - Up/Down move the cursor between lines (preserving the column).
//   - Home/End move within the current line.
//   - RenderTextArea lays the text out as rows and scrolls vertically to
//     keep the cursor line in view, and horizontally to keep the cursor
//     column in view.
//
// Not yet here: soft-wrap and a blinking cursor (solid while focused for now).

import 'dart:async' show scheduleMicrotask, unawaited;

import 'package:characters/characters.dart';

import '../editing/text_editing.dart';
import '../editing/text_keymap.dart';
import '../editing/text_paste.dart';
import '../foundation/geometry.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
import '../rendering/text_sanitizer.dart';
import '../rendering/width_resolver.dart';
import 'clipboard_scope.dart';
import '../semantics/semantics.dart';
import '../input/events.dart';
import 'focus.dart';
import 'framework.dart';
import 'text_input.dart'
    show TextClipboardPolicy, TextEditingController, textClipboardSemanticState;
import 'tui_binding.dart';

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
    this.enabled = true,
    this.readOnly = false,
    this.validationError,
    this.clipboardPolicy = TextClipboardPolicy.allowed,
    this.keymap = TextEditingKeymap.defaultMultiline,
    this.pastePolicy = const TextPastePolicy(),
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
  final bool enabled;
  final bool readOnly;
  final String? validationError;

  /// Policy future copy/cut actions should use for this area.
  final TextClipboardPolicy clipboardPolicy;

  /// Keymap used to resolve non-text key events into editing actions.
  final TextEditingKeymap keymap;

  /// Policy for chunking large bracketed paste payloads.
  final TextPastePolicy pastePolicy;

  @override
  State<TextArea> createState() => _TextAreaState();
}

class _TextAreaState extends State<TextArea>
    implements TextInputClaimant, TextCompositionClaimant {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  TextPasteSession? _pasteSession;
  TextPasteProgress _pasteProgress = TextPasteProgress.inactive;
  int _pasteGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onChange);
    _focusNode =
        widget.focusNode ??
        FocusNode(debugLabel: 'TextArea', canRequestFocus: widget.enabled);
    _syncClaimants();
    _ownsFocusNode = widget.focusNode == null;
  }

  /// Claim typed text only while enabled — mirrors TextInput: a disabled
  /// area declines printables (they fall through to chord matching), so a
  /// registered claimant would make the hint bar hide keys that still work.
  void _syncClaimants() {
    final claimant = widget.enabled ? this : null;
    _focusNode.textInputClaimant = claimant;
    _focusNode.textCompositionClaimant = claimant;
  }

  @override
  void didUpdateWidget(TextArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _cancelScheduledPaste();
      _controller.removeListener(_onChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? TextEditingController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      _focusNode.textInputClaimant = null;
      _focusNode.textCompositionClaimant = null;
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode =
          widget.focusNode ??
          FocusNode(debugLabel: 'TextArea', canRequestFocus: widget.enabled);
      _syncClaimants();
      _ownsFocusNode = widget.focusNode == null;
    }
    if (widget.enabled != oldWidget.enabled) {
      _syncClaimants();
    }
    if (_ownsFocusNode) {
      _focusNode.canRequestFocus = widget.enabled;
      if (!widget.enabled && _focusNode.hasFocus) {
        _focusNode.unfocus();
      }
    }
    if ((!widget.enabled || widget.readOnly) &&
        (oldWidget.enabled != widget.enabled ||
            oldWidget.readOnly != widget.readOnly)) {
      _cancelScheduledPaste();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Focus.maybeOf(context); // rebuild on focus change (cursor visibility)
  }

  void _onChange() => setState(() {});

  bool get _canEdit => widget.enabled && !widget.readOnly;

  void _cancelScheduledPaste() {
    _pasteGeneration++;
    _pasteSession = null;
    _pasteProgress = TextPasteProgress.inactive;
  }

  void _startPaste(String text) {
    _cancelScheduledPaste();
    if (text.isEmpty) return;

    if (!widget.pastePolicy.shouldChunk(text)) {
      _controller.paste(text);
      return;
    }

    final generation = _pasteGeneration;
    _pasteSession = TextPasteSession(text: text, policy: widget.pastePolicy);
    _applyNextPasteChunk(generation, firstChunk: true);
  }

  void _applyNextPasteChunk(int generation, {required bool firstChunk}) {
    if (!mounted || generation != _pasteGeneration) return;
    final session = _pasteSession;
    if (session == null) return;
    final chunk = session.nextChunk();
    if (chunk == null) {
      _finishScheduledPaste(generation);
      return;
    }

    _controller.paste(chunk, coalesce: !firstChunk);
    _pasteProgress = session.progress;
    if (session.isComplete) {
      _finishScheduledPaste(generation);
      return;
    }
    setState(() {});
    _scheduleNextPasteChunk(generation);
  }

  void _finishScheduledPaste(int generation) {
    if (generation != _pasteGeneration) return;
    _pasteSession = null;
    _pasteProgress = TextPasteProgress.inactive;
    if (mounted) setState(() {});
  }

  void _scheduleNextPasteChunk(int generation) {
    final binding = TuiBinding.maybeOf(context);
    if (binding == null) {
      scheduleMicrotask(() {
        _applyNextPasteChunk(generation, firstChunk: false);
      });
      return;
    }
    binding.addPostFrameCallback((_) {
      _applyNextPasteChunk(generation, firstChunk: false);
    });
  }

  String _redactClipboardText(String text) {
    return text.characters
        .map((grapheme) => grapheme == '\n' ? '\n' : '•')
        .join();
  }

  KeyEventResult _copyOrCutSelection({required bool cut}) {
    if (!widget.enabled) return KeyEventResult.ignored;
    final selected = _controller.selectedText;
    if (selected.isEmpty) return KeyEventResult.ignored;
    if (cut && !_canEdit) return KeyEventResult.handled;

    switch (widget.clipboardPolicy) {
      case TextClipboardPolicy.allowed:
        unawaited(ClipboardScope.of(context).write(selected));
        break;
      case TextClipboardPolicy.redacted:
        unawaited(
          ClipboardScope.of(context).write(_redactClipboardText(selected)),
        );
        break;
      case TextClipboardPolicy.disabled:
        return KeyEventResult.handled;
    }
    if (cut) {
      _cancelScheduledPaste();
      _controller.deleteSelection();
    }
    return KeyEventResult.handled;
  }

  void _handleSemanticAction(SemanticAction action) {
    switch (action) {
      case SemanticAction.focus:
        if (widget.enabled) _focusNode.requestFocus();
        return;
      case SemanticAction.clear:
        if (_canEdit) {
          _cancelScheduledPaste();
          _controller.clear();
        }
        return;
      case SemanticAction.copy:
        _copyOrCutSelection(cut: false);
        return;
      case _:
        return;
    }
  }

  /// Replaces the whole body in one call (the `setValue` path) — the multi-line
  /// counterpart to TextInput's, so an agent can set a TextArea without typing
  /// the text character by character.
  void _handleSemanticSetValue(Object? value) {
    if (!_canEdit) return;
    _cancelScheduledPaste();
    _controller.text = value?.toString() ?? '';
  }

  @override
  KeyEventResult onTextInput(String text) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (widget.readOnly) return KeyEventResult.handled;
    _cancelScheduledPaste();
    _controller.insert(text, coalesce: true);
    return KeyEventResult.handled;
  }

  @override
  KeyEventResult onPaste(String text) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (widget.readOnly) return KeyEventResult.handled;
    _startPaste(text);
    return KeyEventResult.handled;
  }

  @override
  KeyEventResult onTextCompositionUpdate(String text) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (widget.readOnly) return KeyEventResult.handled;
    _cancelScheduledPaste();
    _controller.updateComposingText(text);
    return KeyEventResult.handled;
  }

  @override
  KeyEventResult onTextCompositionCommit(String? text) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (widget.readOnly) return KeyEventResult.handled;
    _cancelScheduledPaste();
    _controller.commitComposing(text: text);
    return KeyEventResult.handled;
  }

  @override
  KeyEventResult onTextCompositionCancel() {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (widget.readOnly) return KeyEventResult.handled;
    _cancelScheduledPaste();
    _controller.cancelComposing();
    return KeyEventResult.handled;
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;
    final action = widget.keymap.resolve(event);
    if (action == null) return KeyEventResult.ignored;
    switch (action) {
      case TextEditingKeyAction.copy:
        return _copyOrCutSelection(cut: false);
      case TextEditingKeyAction.cut:
        return _copyOrCutSelection(cut: true);
      case TextEditingKeyAction.undo:
        if (widget.readOnly) return KeyEventResult.handled;
        _cancelScheduledPaste();
        _controller.undo();
        return KeyEventResult.handled;
      case TextEditingKeyAction.redo:
        if (widget.readOnly) return KeyEventResult.handled;
        _cancelScheduledPaste();
        _controller.redo();
        return KeyEventResult.handled;
      case TextEditingKeyAction.backspace:
        if (!_canEdit) return KeyEventResult.handled;
        _cancelScheduledPaste();
        _controller.backspace();
        return KeyEventResult.handled;
      case TextEditingKeyAction.deleteForward:
        if (!_canEdit) return KeyEventResult.handled;
        _cancelScheduledPaste();
        _controller.delete();
        return KeyEventResult.handled;
      case TextEditingKeyAction.killToLineEnd:
        if (!_canEdit) return KeyEventResult.handled;
        _cancelScheduledPaste();
        _controller.killToLineEnd();
        return KeyEventResult.handled;
      case TextEditingKeyAction.killToLineStart:
        if (!_canEdit) return KeyEventResult.handled;
        _cancelScheduledPaste();
        _controller.killToLineStart();
        return KeyEventResult.handled;
      case TextEditingKeyAction.killWordLeft:
        if (!_canEdit) return KeyEventResult.handled;
        _cancelScheduledPaste();
        _controller.killWordLeft();
        return KeyEventResult.handled;
      case TextEditingKeyAction.yank:
        if (!_canEdit) return KeyEventResult.handled;
        _cancelScheduledPaste();
        _controller.yank();
        return KeyEventResult.handled;
      case TextEditingKeyAction.moveLeft:
        _cancelScheduledPaste();
        _controller.moveCursorLeft(extend: event.hasShift);
        return KeyEventResult.handled;
      case TextEditingKeyAction.moveRight:
        _cancelScheduledPaste();
        _controller.moveCursorRight(extend: event.hasShift);
        return KeyEventResult.handled;
      case TextEditingKeyAction.moveWordLeft:
        _cancelScheduledPaste();
        _controller.moveCursorWordLeft(extend: event.hasShift);
        return KeyEventResult.handled;
      case TextEditingKeyAction.moveWordRight:
        _cancelScheduledPaste();
        _controller.moveCursorWordRight(extend: event.hasShift);
        return KeyEventResult.handled;
      case TextEditingKeyAction.moveUp:
        _cancelScheduledPaste();
        _controller.moveCursorLineUp(extend: event.hasShift);
        return KeyEventResult.handled;
      case TextEditingKeyAction.moveDown:
        _cancelScheduledPaste();
        _controller.moveCursorLineDown(extend: event.hasShift);
        return KeyEventResult.handled;
      case TextEditingKeyAction.moveLineStart:
        _cancelScheduledPaste();
        _controller.moveCursorToLineStart(extend: event.hasShift);
        return KeyEventResult.handled;
      case TextEditingKeyAction.moveLineEnd:
        _cancelScheduledPaste();
        _controller.moveCursorToLineEnd(extend: event.hasShift);
        return KeyEventResult.handled;
      case TextEditingKeyAction.moveDocumentStart:
        _cancelScheduledPaste();
        _controller.moveCursorToStart(extend: event.hasShift);
        return KeyEventResult.handled;
      case TextEditingKeyAction.moveDocumentEnd:
        _cancelScheduledPaste();
        _controller.moveCursorToEnd(extend: event.hasShift);
        return KeyEventResult.handled;
      case TextEditingKeyAction.insertNewline:
        if (!_canEdit) return KeyEventResult.handled;
        _cancelScheduledPaste();
        _controller.insert('\n');
        return KeyEventResult.handled;
      case TextEditingKeyAction.escape:
        if (widget.onEscape != null) {
          widget.onEscape!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case TextEditingKeyAction.previousVertical:
      case TextEditingKeyAction.nextVertical:
      case TextEditingKeyAction.acceptCompletion:
      case TextEditingKeyAction.submit:
        return KeyEventResult.ignored;
    }
  }

  @override
  void dispose() {
    _cancelScheduledPaste();
    _controller.removeListener(_onChange);
    if (_ownsController) _controller.dispose();
    _focusNode.textInputClaimant = null;
    _focusNode.textCompositionClaimant = null;
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return Semantics(
      role: SemanticRole.textArea,
      label: widget.placeholder.isEmpty ? null : widget.placeholder,
      value: widget.clipboardPolicy == TextClipboardPolicy.redacted
          ? null
          : _controller.text,
      enabled: widget.enabled,
      focused: focused,
      validationError: widget.validationError,
      actions: {
        if (widget.enabled) SemanticAction.focus,
        if (_canEdit) SemanticAction.clear,
        if (_canEdit) SemanticAction.setValue,
        if (widget.enabled &&
            _controller.hasSelection &&
            widget.clipboardPolicy != TextClipboardPolicy.disabled)
          SemanticAction.copy,
      },
      state: SemanticState({
        'selectionBase': _controller.textSelection.baseOffset,
        'selectionExtent': _controller.textSelection.extentOffset,
        'composingActive': _controller.hasComposingRange,
        'composingStart': _controller.composing.normalizedStart,
        'composingEnd': _controller.composing.normalizedEnd,
        'readOnly': widget.readOnly,
        'redactedValue': widget.clipboardPolicy == TextClipboardPolicy.redacted,
        ...textClipboardSemanticState(widget.clipboardPolicy),
        'pasteInProgress': _pasteProgress.active,
        'pasteInsertedLength': _pasteProgress.insertedLength,
        'pasteTotalLength': _pasteProgress.totalLength,
      }),
      onAction: _handleSemanticAction,
      onSetValue: _handleSemanticSetValue,
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocus && widget.enabled,
        // canRequestFocus is deliberately NOT passed: the enabled ↔
        // focusability sync applies only to a node this state OWNS (see the
        // `_ownsFocusNode` guard in didUpdateWidget) — a caller-provided
        // node's flags belong to the caller, and a non-null value here
        // would make the Focus widget overwrite them on every rebuild.
        onKey: _handleKey,
        child: _TextAreaDisplay(
          focusNode: _focusNode,
          text: _controller.text,
          selection: _controller.textSelection,
          placeholder: widget.placeholder,
          placeholderStyle: widget.enabled
              ? widget.placeholderStyle
              : widget.placeholderStyle.merge(const CellStyle(dim: true)),
          style: widget.enabled
              ? widget.style
              : widget.style.merge(const CellStyle(dim: true)),
          cursorStyle: widget.cursorStyle,
          cursorVisible: focused,
        ),
      ),
    );
  }
}

class _TextAreaDisplay extends LeafRenderObjectWidget {
  const _TextAreaDisplay({
    required this.focusNode,
    required this.text,
    required this.selection,
    required this.placeholder,
    required this.placeholderStyle,
    required this.style,
    required this.cursorStyle,
    required this.cursorVisible,
  });

  final FocusNode focusNode;
  final String text;
  final TextSelection selection;
  final String placeholder;
  final CellStyle placeholderStyle;
  final CellStyle style;
  final CellStyle cursorStyle;
  final bool cursorVisible;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderTextArea(
    focusNode: focusNode,
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
      ..focusNode = focusNode
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
    required FocusNode focusNode,
    required String text,
    required TextSelection selection,
    String placeholder = '',
    CellStyle placeholderStyle = const CellStyle(dim: true),
    CellStyle style = CellStyle.empty,
    CellStyle cursorStyle = const CellStyle(inverse: true),
    bool cursorVisible = true,
    WidthResolver widthResolver = const DefaultWidthResolver(),
    TerminalProfile profile = TerminalProfile.standard,
  }) : _focusNode = focusNode,
       _text = _sanitize(text),
       _selection = selection.normalizeForText(_sanitize(text)),
       _placeholder = _sanitize(placeholder),
       _placeholderStyle = placeholderStyle,
       _style = style,
       _cursorStyle = cursorStyle,
       _cursorVisible = cursorVisible,
       _widthResolver = widthResolver,
       _profile = profile;

  static String _sanitize(String value) =>
      value.split('\n').map(sanitizeForDisplay).join('\n');

  FocusNode _focusNode;
  String _text;
  TextSelection _selection;
  String _placeholder;
  CellStyle _placeholderStyle;
  CellStyle _style;
  CellStyle _cursorStyle;
  bool _cursorVisible;
  final WidthResolver _widthResolver;
  final TerminalProfile _profile;
  int _scrollTop = 0;
  int _scrollLeft = 0;

  set focusNode(FocusNode value) {
    if (identical(_focusNode, value)) return;
    _focusNode.caretRect = null;
    _focusNode = value;
    markNeedsPaintOnly();
  }

  set text(String value) {
    final s = _sanitize(value);
    if (s == _text) return;
    _text = s;
    _selection = _selection.normalizeForText(_text);
    markNeedsLayout();
  }

  set placeholder(String value) {
    final sanitized = _sanitize(value);
    if (_placeholder == sanitized) return;
    _placeholder = sanitized;
    markNeedsLayout();
  }

  set placeholderStyle(CellStyle value) {
    if (_placeholderStyle == value) return;
    _placeholderStyle = value;
    markNeedsPaintOnly();
  }

  set selection(TextSelection value) {
    final normalized = value.normalizeForText(_text);
    if (_selection == normalized) return;
    _selection = normalized;
    markNeedsLayout();
  }

  set style(CellStyle value) {
    if (_style == value) return;
    _style = value;
    markNeedsPaintOnly();
  }

  set cursorStyle(CellStyle value) {
    if (_cursorStyle == value) return;
    _cursorStyle = value;
    markNeedsPaintOnly();
  }

  set cursorVisible(bool value) {
    if (_cursorVisible == value) return;
    _cursorVisible = value;
    markNeedsPaintOnly();
  }

  bool get _showPlaceholder => _text.isEmpty && _placeholder.isNotEmpty;

  List<String> get _lines => _text.split('\n');

  /// (line, column) of the cursor within [_lines].
  (int, int) _cursorLineCol(List<String> lines) {
    var idx = 0;
    for (var i = 0; i < lines.length; i++) {
      final len = lines[i].length;
      final cursor = _selection.extentOffset;
      if (cursor <= idx + len) return (i, cursor - idx);
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

    final nextSize = constraints.constrain(CellSize(cols, rows));
    _syncHorizontalScroll(lines, nextSize.cols);
    return nextSize;
  }

  int _lineDisplayWidth(String line) =>
      _widthResolver.widthOfText(line, _profile);

  int _displayCellForLineOffset(String line, int textOffset) {
    var cell = 0;
    var codeUnitOffset = 0;
    for (final grapheme in line.characters) {
      if (textOffset <= codeUnitOffset) return cell;
      codeUnitOffset += grapheme.length;
      cell += _widthResolver.widthOfGrapheme(grapheme, _profile);
      if (textOffset <= codeUnitOffset) return cell;
    }
    return cell;
  }

  int _displayBoundaryAtOrAfter(String line, int cellOffset) {
    if (cellOffset <= 0) return 0;
    var cell = 0;
    for (final grapheme in line.characters) {
      final next = cell + _widthResolver.widthOfGrapheme(grapheme, _profile);
      if (cellOffset <= cell) return cell;
      if (cellOffset < next) return next;
      cell = next;
    }
    return cell;
  }

  void _syncHorizontalScroll(List<String> lines, int visibleCols) {
    if (_showPlaceholder || visibleCols <= 0 || lines.isEmpty) {
      _scrollLeft = 0;
      return;
    }
    final (cursorLine, cursorCol) = _cursorLineCol(lines);
    final line = lines[cursorLine];
    final lineWidth = _lineDisplayWidth(line) + 1; // trailing cursor cell
    if (lineWidth <= visibleCols) {
      _scrollLeft = 0;
      return;
    }
    final cursorCell = _displayCellForLineOffset(line, cursorCol);
    var next = _scrollLeft;
    if (cursorCell < next) {
      next = cursorCell;
    } else if (cursorCell >= next + visibleCols) {
      next = cursorCell - visibleCols + 1;
    }
    if (next < 0) next = 0;
    next = _displayBoundaryAtOrAfter(line, next);
    if (next > cursorCell) next = cursorCell;
    _scrollLeft = next;
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    if (size.isEmpty) {
      _focusNode.caretRect = null;
      return;
    }
    _focusNode.caretRect = _caretRect(screenOffset ?? offset, clipRect);

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
          final width = _widthResolver.widthOfGrapheme(g, _profile);
          if (col + width > maxCol) break;
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
    final selectionStart = _selection.start;
    final selectionEnd = _selection.end;
    final selectionCollapsed = _selection.isCollapsed;
    final visibleStart = _scrollLeft;
    final visibleEnd = _scrollLeft + size.cols;
    var lineStartOffset = 0;

    for (var r = 0; r < size.rows; r++) {
      final li = _scrollTop + r;
      if (li >= lines.length) break;
      lineStartOffset = _lineStartOffset(lines, li);
      final line = lines[li];
      final row = offset.row + r;
      var cu = 0;
      var paintedCursor = false;
      var displayCell = 0;

      for (final g in line.characters) {
        final globalStart = lineStartOffset + cu;
        final globalEnd = globalStart + g.length;
        final width = _widthResolver.widthOfGrapheme(g, _profile);
        final displayStart = displayCell;
        final displayEnd = displayStart + width;
        cu += g.length;
        displayCell = displayEnd;
        if (displayEnd <= visibleStart) continue;
        if (displayStart < visibleStart) continue;
        if (displayStart >= visibleEnd) break;
        if (displayEnd > visibleEnd) break;
        final atCursor =
            selectionCollapsed &&
            li == cursorLine &&
            globalStart == lineStartOffset + cursorCol;
        final selected =
            !selectionCollapsed &&
            globalStart >= selectionStart &&
            globalEnd <= selectionEnd;
        final st = ((atCursor && _cursorVisible) || selected)
            ? _style.merge(_cursorStyle)
            : _style;
        buffer.writeGrapheme(
          CellOffset(offset.col + (displayStart - visibleStart), row),
          g,
          style: st,
          widthResolver: _widthResolver,
          profile: _profile,
        );
        if (atCursor) paintedCursor = true;
      }

      if (selectionCollapsed && li == cursorLine && !paintedCursor) {
        final cursorCell = _displayCellForLineOffset(line, cursorCol);
        final cursorVisible =
            cursorCell >= visibleStart && cursorCell < visibleEnd;
        final col = offset.col + (cursorCell - visibleStart);
        if (!cursorVisible || col >= maxCol) continue;
        if (!_cursorVisible) continue;
        buffer.writeGrapheme(
          CellOffset(col, row),
          ' ',
          style: _style.merge(_cursorStyle),
        );
      }
    }
  }

  CellRect? _caretRect(CellOffset paintOffset, CellRect? clipRect) {
    final lines = _showPlaceholder ? _placeholder.split('\n') : _lines;
    if (lines.isEmpty) return null;
    final (cursorLine, cursorCol) = _cursorLineCol(lines);
    if (cursorLine < _scrollTop || cursorLine >= _scrollTop + size.rows) {
      return null;
    }
    final line = lines[cursorLine];
    final cursorCell = _displayCellForLineOffset(line, cursorCol);
    final visibleStart = _scrollLeft;
    final visibleEnd = _scrollLeft + size.cols;
    if (cursorCell < visibleStart || cursorCell >= visibleEnd) return null;
    final rect = CellRect(
      offset: CellOffset(
        paintOffset.col + cursorCell - visibleStart,
        paintOffset.row + cursorLine - _scrollTop,
      ),
      size: const CellSize(1, 1),
    );
    return clipRect == null ? rect : rect.intersect(clipRect);
  }

  int _lineStartOffset(List<String> lines, int lineIndex) {
    var offset = 0;
    for (var i = 0; i < lineIndex; i++) {
      offset += lines[i].length + 1;
    }
    return offset;
  }
}
