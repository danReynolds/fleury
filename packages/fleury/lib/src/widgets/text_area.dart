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
import 'dart:collection' show Queue;

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
    this.onChanged,
    this.onEscape,
    this.onSubmit,
    this.placeholder = '',
    this.placeholderStyle = const CellStyle(dim: true),
    this.style = CellStyle.empty,
    this.cursorStyle = const CellStyle(inverse: true),
    this.enabled = true,
    this.readOnly = false,
    this.validationError,
    this.semanticLabel,
    this.semanticState = SemanticState.empty,
    this.clipboardPolicy = TextClipboardPolicy.allowed,
    this.keymap = TextEditingKeymap.defaultMultiline,
    this.pastePolicy = const TextPastePolicy(),
    this.minLines = 1,
    this.maxLines,
  }) : assert(minLines >= 1, 'minLines must be at least 1'),
       assert(
         maxLines == null || maxLines >= minLines,
         'maxLines must be >= minLines',
       );

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Called with the new text whenever the controller text changes.
  ///
  /// Like [TextInput.onChanged], this includes typing, deletion, paste,
  /// semantic edits, and programmatic controller writes, but excludes
  /// cursor-only and selection-only changes.
  final void Function(String text)? onChanged;

  /// Called when the user presses Escape; bubbles if null.
  final void Function()? onEscape;

  /// Called with the current text when the keymap resolves a submit action
  /// (e.g. Enter under [TextEditingKeymap.chat]); bubbles if null. The default
  /// [TextEditingKeymap.defaultMultiline] never emits submit, so this only
  /// fires under a submit-oriented keymap.
  final void Function(String value)? onSubmit;

  /// Hint text shown while the area is empty. May contain newlines.
  final String placeholder;

  /// Style for the [placeholder] text. Defaults to dim.
  final CellStyle placeholderStyle;

  final CellStyle style;
  final CellStyle cursorStyle;
  final bool enabled;
  final bool readOnly;
  final String? validationError;

  /// Label exposed through the semantic app graph.
  ///
  /// When omitted, [placeholder] is used when non-empty. Use this when the
  /// placeholder is example text rather than the durable field name.
  final String? semanticLabel;

  /// Extra semantic state merged into the text-area node.
  final SemanticState semanticState;

  /// Policy future copy/cut actions should use for this area.
  final TextClipboardPolicy clipboardPolicy;

  /// Keymap used to resolve non-text key events into editing actions.
  final TextEditingKeymap keymap;

  /// Policy for chunking large bracketed paste payloads.
  final TextPastePolicy pastePolicy;

  /// Auto-grow floor: the area is at least this many rows tall. Default 1.
  final int minLines;

  /// Auto-grow cap. When non-null, the area's height tracks its content
  /// between [minLines] and [maxLines] rows — a composer that grows with the
  /// draft — and a bounded parent caps it further. When null (default), height
  /// is unchanged: it fills a bounded parent, otherwise sizes to its content.
  final int? maxLines;

  @override
  State<TextArea> createState() => _TextAreaState();
}

class _TextAreaState extends State<TextArea>
    implements TextInputClaimant, PasteEventClaimant, TextCompositionClaimant {
  static const int _maxQueuedPasteCodeUnits = 64 * 1024;
  static const int _maxQueuedPasteSegments = 256;

  late TextEditingController _controller;
  late FocusNode _focusNode;
  late String _lastNotifiedText;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  TextPasteSession? _pasteSession;
  final Queue<({String text, bool isFinal})> _queuedPasteSegments =
      Queue<({String text, bool isFinal})>();
  int _queuedPasteCodeUnits = 0;
  bool _pasteActive = false;
  bool _pasteFinalReceived = false;
  bool _pasteTransactionStarted = false;
  bool _currentPasteSegmentIsFinal = false;
  bool _pasteChunkScheduled = false;
  int? _activePasteId;
  int _pasteInsertedLength = 0;
  int _pasteTotalLength = 0;
  TextPasteProgress _pasteProgress = TextPasteProgress.inactive;
  int _pasteGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _ownsController = widget.controller == null;
    _lastNotifiedText = _controller.text;
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
      _discardScheduledPaste();
      _controller.removeListener(_onChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? TextEditingController();
      _ownsController = widget.controller == null;
      _lastNotifiedText = _controller.text;
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
      _discardScheduledPaste();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Focus.maybeOf(context); // rebuild on focus change (cursor visibility)
  }

  void _onChange() {
    setState(() {});
    final text = _controller.text;
    if (text != _lastNotifiedText) {
      _lastNotifiedText = text;
      widget.onChanged?.call(text);
    }
  }

  bool get _canEdit => widget.enabled && !widget.readOnly;

  void _discardScheduledPaste() {
    _pasteGeneration++;
    _pasteSession = null;
    _queuedPasteSegments.clear();
    _queuedPasteCodeUnits = 0;
    _pasteActive = false;
    _pasteFinalReceived = false;
    _pasteTransactionStarted = false;
    _currentPasteSegmentIsFinal = false;
    _pasteChunkScheduled = false;
    _activePasteId = null;
    _pasteInsertedLength = 0;
    _pasteTotalLength = 0;
    _pasteProgress = TextPasteProgress.inactive;
  }

  /// Finishes an accepted paste before the next editing transaction.
  ///
  /// Frame chunking is a responsiveness policy, not permission to discard the
  /// unapplied tail when a second paste or key action arrives.
  void _cancelScheduledPaste() {
    if (!_pasteActive) {
      _discardScheduledPaste();
      return;
    }
    final pending = StringBuffer();
    final session = _pasteSession;
    if (session != null) {
      final remaining = session.takeRemaining();
      if (remaining != null) pending.write(remaining);
    }
    while (_queuedPasteSegments.isNotEmpty) {
      pending.write(_queuedPasteSegments.removeFirst().text);
    }
    final text = pending.toString();
    if (text.isNotEmpty) _applyBulkPaste(text);
    _completePaste();
  }

  void _startPaste(PasteEvent event, String text) {
    final continuesActivePaste =
        _pasteActive &&
        !event.isFirst &&
        !_pasteFinalReceived &&
        event.pasteId == _activePasteId;
    if (!continuesActivePaste) {
      _cancelScheduledPaste();
      _pasteActive = true;
      _activePasteId = event.pasteId;
    }

    _queuedPasteSegments.addLast((text: text, isFinal: event.isFinal));
    _queuedPasteCodeUnits += text.length;
    _pasteTotalLength += text.length;
    if (event.isFinal) _pasteFinalReceived = true;

    final generation = _pasteGeneration;
    if (_pasteSession == null) _applyNextPasteChunk(generation);
    _drainQueuedPasteToBound(generation);
    _updatePasteProgress();
    if (mounted) setState(() {});
    _scheduleNextPasteChunk(generation);
  }

  bool get _hasPendingPasteWork =>
      _pasteSession != null || _queuedPasteSegments.isNotEmpty;

  bool get _pasteQueueIsOverBound =>
      _queuedPasteCodeUnits > _maxQueuedPasteCodeUnits ||
      _queuedPasteSegments.length > _maxQueuedPasteSegments;

  void _drainQueuedPasteToBound(int generation) {
    // TuiEventSink is synchronous, so it cannot signal parser backpressure.
    // Collapse only the active tail under pressure, in one controller edit,
    // then promote a queued parser segment to the separately bounded active
    // slot. This avoids hundreds of synchronous 2 KiB edits per segment.
    while (_pasteQueueIsOverBound &&
        generation == _pasteGeneration &&
        _pasteActive) {
      if (_pasteSession == null && !_activateNextPasteSegment(generation)) {
        break;
      }
      if (!_pasteQueueIsOverBound || generation != _pasteGeneration) break;
      final session = _pasteSession!;
      final remaining = session.takeRemaining();
      if (remaining != null) _applyBulkPaste(remaining);
      _pasteSession = null;
      if (_currentPasteSegmentIsFinal) _completePaste();
    }
  }

  bool _activateNextPasteSegment(int generation) {
    while (_pasteSession == null &&
        _pasteActive &&
        generation == _pasteGeneration) {
      if (_queuedPasteSegments.isEmpty) return false;
      final segment = _queuedPasteSegments.removeFirst();
      _queuedPasteCodeUnits -= segment.text.length;
      _currentPasteSegmentIsFinal = segment.isFinal;
      if (segment.text.isEmpty) {
        if (segment.isFinal) _completePaste();
        continue;
      }
      _pasteSession = TextPasteSession(
        text: segment.text,
        policy: widget.pastePolicy,
      );
    }
    return _pasteSession != null;
  }

  void _applyBulkPaste(String text) {
    _controller.paste(text, coalesce: _pasteTransactionStarted);
    _pasteTransactionStarted = true;
    _pasteInsertedLength += text.length;
    _updatePasteProgress();
  }

  bool _applyNextPasteChunk(int generation) {
    if (!mounted || generation != _pasteGeneration || !_pasteActive) {
      return false;
    }

    // Skip empty phase markers iteratively. A paste whose last data segment
    // lands exactly on the parser byte cap ends with an empty `end` event that
    // must close (not add to) the undo transaction.
    while (_pasteActive && generation == _pasteGeneration) {
      if (_pasteSession == null && !_activateNextPasteSegment(generation)) {
        return false;
      }
      if (!_pasteActive || generation != _pasteGeneration) return false;

      final session = _pasteSession!;
      final chunk = session.nextChunk();
      if (chunk == null) {
        _pasteSession = null;
        if (_currentPasteSegmentIsFinal) _completePaste();
        continue;
      }

      _controller.paste(chunk, coalesce: _pasteTransactionStarted);
      _pasteTransactionStarted = true;
      _pasteInsertedLength += chunk.length;
      if (session.isComplete) {
        _pasteSession = null;
        if (_currentPasteSegmentIsFinal) _completePaste();
      }
      _updatePasteProgress();
      return true;
    }
    return false;
  }

  void _completePaste() {
    _pasteGeneration++;
    _pasteSession = null;
    _queuedPasteSegments.clear();
    _queuedPasteCodeUnits = 0;
    _pasteActive = false;
    _pasteFinalReceived = false;
    _pasteTransactionStarted = false;
    _currentPasteSegmentIsFinal = false;
    _pasteChunkScheduled = false;
    _activePasteId = null;
    _pasteInsertedLength = 0;
    _pasteTotalLength = 0;
    _pasteProgress = TextPasteProgress.inactive;
  }

  void _updatePasteProgress() {
    _pasteProgress = _pasteActive
        ? TextPasteProgress(
            active: true,
            insertedLength: _pasteInsertedLength,
            totalLength: _pasteTotalLength,
          )
        : TextPasteProgress.inactive;
  }

  void _scheduleNextPasteChunk(int generation) {
    if (generation != _pasteGeneration ||
        !_pasteActive ||
        !_hasPendingPasteWork ||
        _pasteChunkScheduled) {
      return;
    }
    _pasteChunkScheduled = true;
    final binding = TuiBinding.maybeOf(context);
    if (binding == null) {
      scheduleMicrotask(() => _runScheduledPasteChunk(generation));
      return;
    }
    binding.addPostFrameCallback((_) => _runScheduledPasteChunk(generation));
  }

  void _runScheduledPasteChunk(int generation) {
    if (!mounted || generation != _pasteGeneration) return;
    _pasteChunkScheduled = false;
    _applyNextPasteChunk(generation);
    _updatePasteProgress();
    if (mounted) setState(() {});
    _scheduleNextPasteChunk(generation);
  }

  String _redactClipboardText(String text) {
    return text.characters
        .map((grapheme) => grapheme == '\n' ? '\n' : '•')
        .join();
  }

  KeyEventResult _copyOrCutSelection({required bool cut}) {
    if (!widget.enabled) return KeyEventResult.ignored;
    // Clipboard actions read selection/text synchronously. They must observe
    // all paste content the area has already accepted, not a rendered prefix.
    _cancelScheduledPaste();
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
      case SemanticAction.submit:
        if (widget.enabled && widget.onSubmit != null) {
          _cancelScheduledPaste();
          widget.onSubmit!(_controller.text);
        }
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
    _startPaste(
      PasteEvent(text),
      TextEditingModel.normalizeMultilineInput(text),
    );
    return KeyEventResult.handled;
  }

  @override
  KeyEventResult onPasteEvent(PasteEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (widget.readOnly) return KeyEventResult.handled;
    _startPaste(event, TextEditingModel.normalizeMultilineInput(event.text));
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
    if (action == null) {
      // An ancestor binding may synchronously inspect the controller or unmount
      // this area. Preserve input ordering before bubbling any later key.
      _cancelScheduledPaste();
      return KeyEventResult.ignored;
    }
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
        // Escape still bubbles when no callback is installed, but an ancestor
        // may inspect the value or unmount this area synchronously.
        _cancelScheduledPaste();
        if (widget.onEscape != null) {
          widget.onEscape!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case TextEditingKeyAction.submit:
        // Submission may bubble to an app-level binding. It must observe the
        // complete accepted transaction whether or not this area has a callback.
        _cancelScheduledPaste();
        if (widget.onSubmit != null) {
          widget.onSubmit!(_controller.text);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case TextEditingKeyAction.previousVertical:
      case TextEditingKeyAction.nextVertical:
      case TextEditingKeyAction.acceptCompletion:
        _cancelScheduledPaste();
        return KeyEventResult.ignored;
    }
  }

  @override
  void dispose() {
    _discardScheduledPaste();
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
      label:
          widget.semanticLabel ??
          (widget.placeholder.isEmpty ? null : widget.placeholder),
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
        if (widget.enabled && widget.onSubmit != null) SemanticAction.submit,
      },
      state: widget.semanticState.merge({
        'selectionBase': _controller.selection.baseOffset,
        'selectionExtent': _controller.selection.extentOffset,
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
          selection: _controller.selection,
          placeholder: widget.placeholder,
          placeholderStyle: widget.enabled
              ? widget.placeholderStyle
              : widget.placeholderStyle.merge(const CellStyle(dim: true)),
          style: widget.enabled
              ? widget.style
              : widget.style.merge(const CellStyle(dim: true)),
          cursorStyle: widget.cursorStyle,
          cursorVisible: focused,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
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
    required this.minLines,
    required this.maxLines,
  });

  final FocusNode focusNode;
  final String text;
  final TextSelection selection;
  final String placeholder;
  final CellStyle placeholderStyle;
  final CellStyle style;
  final CellStyle cursorStyle;
  final bool cursorVisible;
  final int minLines;
  final int? maxLines;

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
    minLines: minLines,
    maxLines: maxLines,
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
      ..cursorVisible = cursorVisible
      ..minLines = minLines
      ..maxLines = maxLines;
  }
}

/// Line-split activity observed in [RenderTextArea] over one stats window.
final class TextAreaFrameStats {
  const TextAreaFrameStats({required this.lineSplitCount});

  static const empty = TextAreaFrameStats(lineSplitCount: 0);

  /// Document/placeholder line splits performed while the window was open —
  /// i.e. misses of the memoized split. A window over frames whose text did
  /// not change records 0.
  final int lineSplitCount;
}

/// Debug-only collector for [RenderTextArea]'s memoized line split.
///
/// Mirrors the RenderLayoutDebugStats / RepaintBoundaryDebugStats collectors:
/// opt-in per window, so production frames pay only a branch at the memo's
/// recompute site; tests enable it around the frames they want to inspect and
/// read the result with [takeFrameStats].
final class TextAreaDebugStats {
  TextAreaDebugStats._();

  static bool _enabled = false;
  static int _lineSplitCount = 0;

  static void beginFrame({required bool enabled}) {
    _enabled = enabled;
    _lineSplitCount = 0;
  }

  static TextAreaFrameStats takeFrameStats() {
    if (!_enabled) return TextAreaFrameStats.empty;
    final stats = TextAreaFrameStats(lineSplitCount: _lineSplitCount);
    _enabled = false;
    _lineSplitCount = 0;
    return stats;
  }

  static void recordLineSplit() {
    if (!_enabled) return;
    _lineSplitCount += 1;
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
    int minLines = 1,
    int? maxLines,
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
       _minLines = minLines,
       _maxLines = maxLines,
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
  int _minLines;
  int? _maxLines;
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

  set minLines(int value) {
    if (_minLines == value) return;
    _minLines = value;
    markNeedsLayout();
  }

  set maxLines(int? value) {
    if (_maxLines == value) return;
    _maxLines = value;
    markNeedsLayout();
  }

  bool get _showPlaceholder => _text.isEmpty && _placeholder.isNotEmpty;

  // Memoized line split. [_text] and [_placeholder] are immutable strings
  // that are only ever reassigned (the setters produce a fresh instance via
  // [_sanitize] whenever the value changes), so identity of the source
  // string is a sound O(1) cache key. Layout, paint, and caret derivation
  // each need the same split every frame; without the memo each pass
  // re-split the whole document — O(doc) work per frame at editor scale for
  // cursor moves that change no text. Only one source is consulted per
  // frame (placeholder when the document is empty, the text otherwise), so
  // a single entry suffices.
  String? _cachedLinesSource;
  List<String> _cachedLines = const [];

  /// Lines of [source], memoized by string identity. Treat the returned
  /// list as immutable: it is shared across layout/paint passes. Recomputes
  /// are reported to [TextAreaDebugStats] when a stats window is open.
  List<String> _linesOf(String source) {
    if (!identical(_cachedLinesSource, source)) {
      _cachedLinesSource = source;
      _cachedLines = source.split('\n');
      TextAreaDebugStats.recordLineSplit();
    }
    return _cachedLines;
  }

  List<String> get _lines => _linesOf(_text);

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
    final lines = _showPlaceholder ? _linesOf(_placeholder) : _lines;
    var widest = 0;
    for (final line in lines) {
      final w = _widthResolver.widthOfText(line, _profile);
      if (w > widest) widest = w;
    }
    final cols = constraints.hasBoundedWidth ? constraints.maxCols! : widest;
    int rows;
    if (_maxLines != null) {
      // Auto-grow: height tracks the content between minLines and maxLines.
      rows = lines.length.clamp(_minLines, _maxLines!);
    } else if (constraints.hasBoundedHeight) {
      rows = constraints.maxRows!;
    } else {
      rows = lines.length < _minLines ? _minLines : lines.length;
    }
    // Cap to a bounded parent BEFORE the scroll math below. That math and the
    // paint loop both use `rows`, so it must equal the final viewport height —
    // otherwise constrain() would shrink the painted size afterwards, desyncing
    // the two and scrolling the cursor line off-screen under a parent tighter
    // than maxLines.
    if (constraints.hasBoundedHeight && rows > constraints.maxRows!) {
      rows = constraints.maxRows!;
    }

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
    final screen = screenOffset ?? offset;
    final screenCaret = _caretRect(screen, null);
    if (screenCaret != null && FocusGeometryCapture.isActive) {
      FocusGeometryCapture.record(
        _replayCaret,
        screenCaret,
        clipRect: clipRect,
      );
    }
    _focusNode.caretRect = clipRect == null
        ? screenCaret
        : screenCaret?.intersect(clipRect);

    // Empty: paint the (possibly multi-line) placeholder, with the
    // cursor over the very first cell when visible.
    if (_showPlaceholder) {
      final phLines = _linesOf(_placeholder);
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
    final lines = _showPlaceholder ? _linesOf(_placeholder) : _lines;
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

  // ignore: prefer_function_declarations_over_variables
  late final FocusGeometryCallback _replayCaret = (bounds) {
    _focusNode.caretRect = _focusNode.acceptsInput ? bounds : null;
  };

  int _lineStartOffset(List<String> lines, int lineIndex) {
    var offset = 0;
    for (var i = 0; i < lineIndex; i++) {
      offset += lines[i].length + 1;
    }
    return offset;
  }
}
