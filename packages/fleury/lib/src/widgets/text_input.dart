// TextInput: a single-line editable text widget for terminal apps.
//
// Composed of three pieces:
//   - TextEditingController — a ChangeNotifier holding the current
//     TextEditingValue and compatibility text/cursor accessors.
//   - TextInput — the widget. Creates a Focus node tagged as a
//     TextInputClaimant, so the InputDispatcher routes
//     TextInputEvents (typed printable text) directly to it. Handles
//     special chords (Backspace, arrows, Enter, etc.) via Focus.onKey.
//   - RenderTextInput — paints the text plus a one-cell inverse
//     cursor at the current selection position.
//
// What's intentionally not here yet:
//   - Multi-line text (Enter inserts a newline + wraps); v0 is
//     single-line and Enter calls onSubmit.
//   - Command/submission history unless a TextHistoryController is supplied.

import 'dart:async' show scheduleMicrotask, unawaited;

import 'package:characters/characters.dart';

import '../animation/animation_policy.dart';
import '../animation/frame_ticker.dart';
import '../editing/text_completion.dart';
import '../editing/text_editing.dart';
import '../editing/text_history.dart';
import '../editing/text_keymap.dart';
import '../editing/text_paste.dart';
import '../foundation/change_notifier.dart';
import '../foundation/geometry.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
import '../rendering/text_sanitizer.dart';
import '../rendering/width_resolver.dart';
import '../runtime/clipboard.dart';
import '../semantics/semantics.dart';
import '../terminal/capabilities.dart';
import '../terminal/capability_requirements.dart';
import '../terminal/events.dart';
import 'focus.dart';
import 'framework.dart';
import 'tui_binding.dart';

/// How an editable text widget should treat copy/cut operations.
///
/// Field-level copy/cut commands use this policy so keyboard behavior,
/// semantics, inspectors, and future adapters agree on whether field content
/// is safe to copy.
enum TextClipboardPolicy {
  /// Plain text may be copied unchanged.
  allowed,

  /// Copy/cut commands should be unavailable for this field.
  disabled,

  /// Copy/cut commands should not expose the raw value.
  redacted,
}

CapabilityResolution resolveTextClipboardPolicy(TextClipboardPolicy policy) {
  return resolveCapabilityRequirement(
    const CapabilityRequirement(
      feature: TerminalFeature.clipboardWrite,
      level: CapabilityLevel.preferred,
      reason: 'Copy selected editable text.',
      fallback: CapabilityFallback(label: 'in-process register'),
    ),
    TerminalCapabilities.defaultCapabilities,
    policyBlockedFeatures: policy == TextClipboardPolicy.disabled
        ? const <TerminalFeature>{TerminalFeature.clipboardWrite}
        : const <TerminalFeature>{},
  );
}

Map<String, Object?> textClipboardSemanticState(TextClipboardPolicy policy) {
  final resolution = resolveTextClipboardPolicy(policy);
  return <String, Object?>{
    'clipboardPolicy': policy.name,
    'clipboardCapability': resolution.feature.name,
    'clipboardCapabilityResolution': resolution.state.name,
    if (resolution.fallbackLabel != null)
      'clipboardFallback': resolution.fallbackLabel,
    'clipboardRedacted': policy == TextClipboardPolicy.redacted,
  };
}

enum _EditTransaction { edit, typing, paste }

/// Mutable model for text input widgets.
///
/// The compatibility [selection] accessor remains a Dart string offset, but
/// writes and editing operations snap to extended-grapheme boundaries. This
/// prevents cursor movement and deletion from splitting emoji, combining
/// marks, or other multi-code-unit user-perceived characters.
class TextEditingController extends ChangeNotifier {
  TextEditingController({String text = ''})
    : _value = TextEditingValue(text: text);

  static const int _maxHistoryEntries = 200;

  TextEditingValue _value;
  TextEditingValue? _compositionBase;
  final List<TextEditingValue> _undoStack = <TextEditingValue>[];
  final List<TextEditingValue> _redoStack = <TextEditingValue>[];
  _EditTransaction? _lastTransaction;
  bool _disposed = false;

  TextEditingValue get value => _value;
  set value(TextEditingValue next) => _setValue(next, resetHistory: true);

  String get text => _value.text;
  set text(String text) {
    _setValue(_value.copyWith(text: text), resetHistory: true);
  }

  /// Cursor index as a Dart string offset. Always snapped to a grapheme
  /// boundary within `0..text.length`.
  int get selection => _value.selection.extentOffset;
  set selection(int offset) {
    _setValue(_value.copyWith(selection: TextSelection.collapsed(offset)));
  }

  TextSelection get textSelection => _value.selection;
  set textSelection(TextSelection selection) {
    _setValue(_value.copyWith(selection: selection));
  }

  TextRange get composing => _value.composing;
  bool get hasComposingRange => !_value.composing.isCollapsed;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get hasSelection => !_value.selection.isCollapsed;

  String get selectedText {
    if (!hasSelection) return '';
    final range = _value.selection.range.clamp(_value.text.length);
    return _value.text.substring(range.normalizedStart, range.normalizedEnd);
  }

  void clear() {
    _checkNotDisposed();
    _applyEdit(TextEditingValue.empty());
  }

  /// Inserts [s] at the current cursor and advances the cursor past
  /// the inserted text. No-op if [s] is empty.
  ///
  /// When [coalesce] is true, consecutive text-changing inserts are recorded
  /// as one undo transaction until cursor movement or another edit type breaks
  /// the run. Text widgets use this for typed input.
  void insert(String s, {bool singleLine = false, bool coalesce = false}) {
    _checkNotDisposed();
    _applyEdit(
      TextEditingModel.insert(_value, s, singleLine: singleLine),
      transaction: coalesce ? _EditTransaction.typing : _EditTransaction.edit,
    );
  }

  /// Inserts bracketed paste content as one undoable transaction.
  void paste(String s, {bool singleLine = false, bool coalesce = false}) {
    _checkNotDisposed();
    _applyEdit(
      TextEditingModel.insert(_value, s, singleLine: singleLine),
      transaction: _EditTransaction.paste,
      coalesceWithPrevious: coalesce,
    );
  }

  /// Deletes the character before the cursor and moves the cursor
  /// left. No-op when the cursor is at the start.
  void backspace() {
    _checkNotDisposed();
    _applyEdit(TextEditingModel.backspace(_value));
  }

  /// Deletes the character at the cursor (the one to its right).
  /// No-op when the cursor is at the end.
  void delete() {
    _checkNotDisposed();
    _applyEdit(TextEditingModel.delete(_value));
  }

  void deleteSelection() {
    _checkNotDisposed();
    if (!hasSelection) return;
    _applyEdit(TextEditingModel.replaceSelection(_value, ''));
  }

  void replaceRange(
    TextRange range,
    String replacement, {
    bool singleLine = false,
  }) {
    _checkNotDisposed();
    _applyEdit(
      TextEditingModel.replaceRange(
        _value,
        range,
        replacement,
        singleLine: singleLine,
      ),
    );
  }

  /// Marks [range] as the current composing range without changing text.
  ///
  /// This is intentionally an extension point for input-method adapters, not a
  /// terminal protocol implementation. The first composition change captures a
  /// base value so the composition can later be committed as one undo step or
  /// cancelled back to its original value.
  void setComposingRange(TextRange range) {
    _checkNotDisposed();
    _compositionBase ??= TextEditingModel.clearComposing(_value);
    _setValue(TextEditingModel.setComposingRange(_value, range));
  }

  /// Clears the visible composing range without changing the text.
  void clearComposing() {
    _checkNotDisposed();
    final next = TextEditingModel.clearComposing(_value);
    _compositionBase = null;
    _setValue(next);
  }

  /// Replaces the active composing range with [text].
  ///
  /// Interim composition updates are deliberately not undoable. A later
  /// [commitComposing] records the full composition as one undo transaction.
  void updateComposingText(String text, {bool singleLine = false}) {
    _checkNotDisposed();
    _compositionBase ??= TextEditingModel.clearComposing(_value);
    final next = TextEditingModel.updateComposing(
      _value,
      text,
      singleLine: singleLine,
    );
    _lastTransaction = null;
    _setValue(next, clearTransaction: false);
  }

  /// Commits the active composition.
  ///
  /// If [text] is supplied, it replaces the composing range before the commit.
  /// The completed composition is recorded as one undoable edit against the
  /// value captured before composition began.
  void commitComposing({String? text, bool singleLine = false}) {
    _checkNotDisposed();
    final base = _compositionBase;
    if (base == null) {
      final next = TextEditingModel.commitComposing(
        _value,
        text: text,
        singleLine: singleLine,
      );
      if (text == null) {
        _setValue(next);
      } else {
        _applyEdit(next);
      }
      return;
    }

    final next = TextEditingModel.commitComposing(
      _value,
      text: text,
      singleLine: singleLine,
    );
    _compositionBase = null;
    if (next.text != base.text) {
      _pushUndoValue(base);
      _redoStack.clear();
      _lastTransaction = _EditTransaction.edit;
    } else {
      _lastTransaction = null;
    }
    _setValue(next, clearTransaction: false);
  }

  /// Cancels the active composition and restores the pre-composition value.
  void cancelComposing() {
    _checkNotDisposed();
    final base = _compositionBase;
    _compositionBase = null;
    _lastTransaction = null;
    if (base != null) {
      _setValue(base);
    } else {
      _setValue(TextEditingModel.clearComposing(_value));
    }
  }

  void moveCursorLeft({bool extend = false}) {
    _checkNotDisposed();
    _setValue(TextEditingModel.moveLeft(_value, extend: extend));
  }

  void moveCursorRight({bool extend = false}) {
    _checkNotDisposed();
    _setValue(TextEditingModel.moveRight(_value, extend: extend));
  }

  void moveCursorWordLeft({bool extend = false}) {
    _checkNotDisposed();
    _setValue(TextEditingModel.moveWordLeft(_value, extend: extend));
  }

  void moveCursorWordRight({bool extend = false}) {
    _checkNotDisposed();
    _setValue(TextEditingModel.moveWordRight(_value, extend: extend));
  }

  void moveCursorToStart({bool extend = false}) {
    _checkNotDisposed();
    _setValue(TextEditingModel.moveToStart(_value, extend: extend));
  }

  void moveCursorToEnd({bool extend = false}) {
    _checkNotDisposed();
    _setValue(TextEditingModel.moveToEnd(_value, extend: extend));
  }

  void moveCursorToLineStart({bool extend = false}) {
    _checkNotDisposed();
    _setValue(TextEditingModel.moveToLineStart(_value, extend: extend));
  }

  void moveCursorToLineEnd({bool extend = false}) {
    _checkNotDisposed();
    _setValue(TextEditingModel.moveToLineEnd(_value, extend: extend));
  }

  void moveCursorLineUp({bool extend = false}) {
    _checkNotDisposed();
    _setValue(TextEditingModel.moveLineUp(_value, extend: extend));
  }

  void moveCursorLineDown({bool extend = false}) {
    _checkNotDisposed();
    _setValue(TextEditingModel.moveLineDown(_value, extend: extend));
  }

  void undo() {
    _checkNotDisposed();
    if (_compositionBase != null) {
      cancelComposing();
      return;
    }
    if (_undoStack.isEmpty) return;
    _redoStack.add(_value);
    _lastTransaction = null;
    _setValue(_undoStack.removeLast());
  }

  void redo() {
    _checkNotDisposed();
    if (_compositionBase != null) {
      cancelComposing();
      return;
    }
    if (_redoStack.isEmpty) return;
    _undoStack.add(_value);
    _lastTransaction = null;
    _setValue(_redoStack.removeLast());
  }

  void _pushUndoValue(TextEditingValue value) {
    _undoStack.add(value);
    if (_undoStack.length > _maxHistoryEntries) {
      _undoStack.removeAt(0);
    }
  }

  void _applyEdit(
    TextEditingValue next, {
    _EditTransaction transaction = _EditTransaction.edit,
    bool coalesceWithPrevious = false,
  }) {
    _checkNotDisposed();
    if (_value == next) return;
    _compositionBase = null;
    if (_value.text != next.text) {
      final shouldCoalesce =
          (transaction == _EditTransaction.typing &&
              _lastTransaction == _EditTransaction.typing) ||
          (coalesceWithPrevious && _lastTransaction == transaction);
      if (!shouldCoalesce) {
        _pushUndoValue(_value);
      }
      _redoStack.clear();
      _lastTransaction = transaction;
    } else {
      _lastTransaction = null;
    }
    _setValue(next, clearTransaction: false);
  }

  void _setValue(
    TextEditingValue next, {
    bool resetHistory = false,
    bool clearTransaction = true,
  }) {
    _checkNotDisposed();
    if (_value == next) return;
    _value = next;
    if (resetHistory) {
      _compositionBase = null;
      _undoStack.clear();
      _redoStack.clear();
    }
    if (resetHistory || clearTransaction) {
      _lastTransaction = null;
    }
    notifyListeners();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('TextEditingController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _compositionBase = null;
    _undoStack.clear();
    _redoStack.clear();
    _lastTransaction = null;
    super.dispose();
  }
}

/// A single-line editable text widget.
///
/// The widget claims insertable input (printable ASCII / Unicode,
/// arriving as [TextInputEvent]s from the parser) via
/// [TextInputClaimant], so an ancestor `KeyBindings` doesn't see
/// typed characters that should go into the text. Modifier chords
/// like `Ctrl+S` arrive as [KeyEvent]s and still bubble normally.
///
/// Special chords handled directly:
///   - Backspace, Delete, Arrow Left / Right, Home, End — edit the
///     controller's selection / text.
///   - Enter — fires [onSubmit] with the current text. Up to the
///     caller to clear the controller or keep the typed value.
///   - Escape — fires [onEscape], or bubbles if [onEscape] is null.
///   - Tab and other unhandled special chords — bubble.
class TextInput extends StatefulWidget {
  const TextInput({
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
    this.blinkInterval = const Duration(milliseconds: 500),
    this.enableBlink = true,
    this.obscureText = false,
    this.obscuringCharacter = '•',
    this.enabled = true,
    this.readOnly = false,
    this.validationError,
    this.semanticLabel,
    this.semanticState = SemanticState.empty,
    this.clipboardPolicy,
    this.historyController,
    this.commitHistoryOnSubmit = true,
    this.completionController,
    this.onCompletionAccepted,
    this.keymap = TextEditingKeymap.defaultSingleLine,
    this.pastePolicy = const TextPastePolicy(),
  });

  /// External controller for the text. If null, the widget creates
  /// its own and disposes it on unmount.
  final TextEditingController? controller;

  /// External [FocusNode]. Provide one when a parent needs to drive
  /// focus (e.g. Tab cycling between panes). If null, the widget
  /// creates its own and disposes it on unmount.
  final FocusNode? focusNode;

  /// Whether to request focus on first mount.
  final bool autofocus;

  /// Called with the current text when the user presses Enter.
  final void Function(String text)? onSubmit;

  /// Called when the user presses Escape. If null, Escape bubbles
  /// up the focus chain normally.
  final void Function()? onEscape;

  /// Hint text shown when the field is empty. Cleared as soon as the
  /// user types.
  final String placeholder;

  /// Style for the [placeholder] text. Defaults to dim.
  final CellStyle placeholderStyle;

  /// Base style for the rendered text.
  final CellStyle style;

  /// Style merged on top of [style] at the cursor cell. Defaults to
  /// `inverse: true` — a block cursor.
  final CellStyle cursorStyle;

  /// On/off cadence for the blinking cursor. Default matches
  /// native terminal conventions (~500 ms).
  final Duration blinkInterval;

  /// When true (default), the cursor blinks while the widget is
  /// focused. When false, the cursor is rendered solid whenever
  /// the widget is focused. The cursor is always suppressed when
  /// the widget is unfocused.
  final bool enableBlink;

  /// When true, each grapheme of the field's text is replaced with
  /// [obscuringCharacter] at paint time. The controller still holds
  /// the real text — only the displayed glyphs are masked. Use for
  /// password / secret entry.
  final bool obscureText;

  /// The glyph used to replace each character when [obscureText] is
  /// true. Defaults to `•`.
  final String obscuringCharacter;

  /// Whether the field can receive focus and handle input.
  final bool enabled;

  /// Whether the field can receive focus but refuses text mutations.
  ///
  /// Cursor movement and submit/escape callbacks still work while read-only.
  final bool readOnly;

  /// Validation error attached to the current value.
  ///
  /// Fleury does not run validators inside the widget yet; apps can compute
  /// validation externally and pass the current error here for semantics,
  /// tests, and inspector/debug surfaces.
  final String? validationError;

  /// Label exposed through the semantic app graph.
  ///
  /// When omitted, [placeholder] is used as the field label when non-empty.
  /// Use this when a visible form label sits outside the field or the
  /// placeholder is example text rather than the durable field name.
  final String? semanticLabel;

  /// Extra semantic state merged into the text-field node.
  ///
  /// Specialized fields can use this to expose stable domain facts such as
  /// numeric bounds while keeping the core text editing role and actions.
  final SemanticState semanticState;

  /// Policy future copy/cut actions should use for this field.
  ///
  /// When null, obscured fields default to [TextClipboardPolicy.redacted] and
  /// normal fields default to [TextClipboardPolicy.allowed].
  final TextClipboardPolicy? clipboardPolicy;

  /// Optional command/submission history for Up/Down navigation.
  ///
  /// History is opt-in so fields embedded in palettes, autocompletes, and
  /// other parent-owned navigation surfaces keep bubbling Up/Down by default.
  final TextHistoryController? historyController;

  /// Whether pressing Enter should commit the submitted value to
  /// [historyController] before [onSubmit] runs.
  final bool commitHistoryOnSubmit;

  /// Optional completion state for this field.
  ///
  /// Popup rendering and suggestion providers are layered separately. When a
  /// controller is supplied, this field can navigate active completion options
  /// with Up/Down and accept the selected option with Tab.
  final TextCompletionController? completionController;

  /// Called after a selected completion option is applied.
  final void Function(TextCompletionOption option)? onCompletionAccepted;

  /// Keymap used to resolve non-text key events into editing actions.
  final TextEditingKeymap keymap;

  /// Policy for chunking large bracketed paste payloads.
  final TextPastePolicy pastePolicy;

  @override
  State<TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<TextInput> implements TextInputClaimant {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  TextPasteSession? _pasteSession;
  TextPasteProgress _pasteProgress = TextPasteProgress.inactive;
  int _pasteGeneration = 0;

  /// Blink ticker — lazily created in [didChangeDependencies]
  /// because we need a `TuiBinding` to source the scheduler, which
  /// requires a `BuildContext` that's done its first dependency
  /// pass. Started/stopped from [_syncBlinkToFocus] as focus
  /// changes.
  FrameTicker? _blinkTicker;

  /// Latest "on" phase of the blink. Toggled on each ticker frame.
  /// `true` means the cursor cell renders with [cursorStyle]; false
  /// means it renders as normal text (or empty, if the cursor is
  /// past the last character).
  bool _blinkOn = true;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChange);
    widget.historyController?.addListener(_onHistoryChange);
    widget.completionController?.addListener(_onCompletionChange);
    // Note: don't set _focusNode.onKey here — the Focus widget's
    // State.initState assigns onKey from `widget.onKey`, overwriting
    // anything we set. We pass `_handleKey` to the Focus widget
    // below instead. We do set `textInputClaimant` since the Focus
    // widget never touches it.
    _focusNode =
        widget.focusNode ??
        FocusNode(debugLabel: 'TextInput', canRequestFocus: widget.enabled);
    _focusNode.textInputClaimant = this;
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(TextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _cancelScheduledPaste();
      _controller.removeListener(_onControllerChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? TextEditingController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChange);
    }
    if (widget.historyController != oldWidget.historyController) {
      oldWidget.historyController?.removeListener(_onHistoryChange);
      widget.historyController?.addListener(_onHistoryChange);
    }
    if (widget.completionController != oldWidget.completionController) {
      oldWidget.completionController?.removeListener(_onCompletionChange);
      widget.completionController?.addListener(_onCompletionChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      // Stop claiming text on the old node before letting it go.
      _focusNode.textInputClaimant = null;
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode =
          widget.focusNode ??
          FocusNode(debugLabel: 'TextInput', canRequestFocus: widget.enabled);
      _focusNode.textInputClaimant = this;
      _ownsFocusNode = widget.focusNode == null;
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
    if (widget.blinkInterval != oldWidget.blinkInterval ||
        widget.enableBlink != oldWidget.enableBlink) {
      _disposeBlinkTicker();
      // Recreate next didChangeDependencies / build pass.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Rebuild on focus change so cursor visibility flips.
    // dependOnInheritedWidgetOfExactType subscribes us to the
    // FocusManagerScope.
    Focus.maybeOf(context);
    _syncBlinkToFocus();
  }

  void _syncBlinkToFocus() {
    if (!widget.enableBlink) {
      _disposeBlinkTicker();
      _blinkOn = true; // solid cursor when blink disabled
      return;
    }
    if (!_focusNode.hasFocus) {
      _disposeBlinkTicker();
      _blinkOn = true; // resting state when unfocused
      return;
    }
    // Focused + blink enabled. Ensure ticker; mute under
    // AnimationPolicy.disabled (cursor stays solid; ticker
    // remains registered so we don't repeatedly create/destroy
    // it if the policy toggles).
    _ensureBlinkTicker();
    final policy =
        TuiBinding.maybeOf(context)?.animationPolicy ?? AnimationPolicy.enabled;
    if (policy == AnimationPolicy.disabled) {
      _blinkTicker?.muted = true;
      _blinkOn = true;
    } else {
      _blinkTicker?.muted = false;
    }
  }

  void _ensureBlinkTicker() {
    if (_blinkTicker != null) return;
    final binding = TuiBinding.maybeOf(context);
    if (binding == null) return; // no binding: no blink (tests, etc.)
    _blinkTicker =
        FrameTicker(
            interval: widget.blinkInterval,
            scheduler: binding.tickerScheduler,
          )
          ..addListener(_onBlink)
          ..start();
  }

  void _disposeBlinkTicker() {
    final t = _blinkTicker;
    if (t == null) return;
    t.removeListener(_onBlink);
    t.dispose();
    _blinkTicker = null;
  }

  void _onBlink() {
    if (!mounted) return;
    setState(() {
      _blinkOn = !_blinkOn;
    });
  }

  void _onControllerChange() {
    setState(() {
      // Typing resets the blink to ON so the cursor is immediately
      // visible after a keystroke — matches native terminal cursor
      // behavior. Without this, a cursor in its OFF phase would
      // briefly stay invisible during typing, which feels broken.
      _blinkOn = true;
    });
  }

  void _onHistoryChange() {
    if (!mounted) return;
    setState(() {});
  }

  void _onCompletionChange() {
    if (!mounted) return;
    setState(() {});
  }

  bool get _canEdit => widget.enabled && !widget.readOnly;

  TextClipboardPolicy get _effectiveClipboardPolicy =>
      widget.clipboardPolicy ??
      (widget.obscureText
          ? TextClipboardPolicy.redacted
          : TextClipboardPolicy.allowed);

  bool get _redactSemanticValue =>
      widget.obscureText ||
      _effectiveClipboardPolicy == TextClipboardPolicy.redacted;

  Object? get _semanticValue => _redactSemanticValue ? null : _controller.text;

  String _redactClipboardText(String text) {
    return text.characters
        .map((grapheme) => grapheme == '\n' ? '\n' : widget.obscuringCharacter)
        .join();
  }

  void _resetHistoryBrowsing() {
    widget.historyController?.resetBrowsing();
  }

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

  bool _completionIsOpenWithOptions() {
    final completion = widget.completionController;
    return completion != null &&
        completion.isOpen &&
        completion.selectedOption != null;
  }

  KeyEventResult _acceptCompletion() {
    final completion = widget.completionController;
    if (completion == null || !completion.isOpen) return KeyEventResult.ignored;
    final state = completion.state;
    final option = state.selectedOption;
    if (option == null) return KeyEventResult.ignored;
    if (!_canEdit) {
      return widget.enabled ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    _cancelScheduledPaste();
    _resetHistoryBrowsing();
    _controller.replaceRange(state.range, option.replacement, singleLine: true);
    completion.close();
    widget.onCompletionAccepted?.call(option);
    return KeyEventResult.handled;
  }

  KeyEventResult _moveCompletion(int delta) {
    final completion = widget.completionController;
    if (completion == null || !completion.isOpen) return KeyEventResult.ignored;
    if (completion.state.options.isEmpty) return KeyEventResult.ignored;
    completion.moveSelection(delta);
    return KeyEventResult.handled;
  }

  KeyEventResult _navigateHistory({required bool previous}) {
    final history = widget.historyController;
    if (history == null) return KeyEventResult.ignored;
    if (!_canEdit) {
      return widget.enabled ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    final next = previous
        ? history.navigatePrevious(_controller.value)
        : history.navigateNext();
    if (next == null) return KeyEventResult.ignored;
    _cancelScheduledPaste();
    _controller.value = next;
    return KeyEventResult.handled;
  }

  KeyEventResult _copyOrCutSelection({required bool cut}) {
    if (!widget.enabled) return KeyEventResult.ignored;
    final selected = _controller.selectedText;
    if (selected.isEmpty) return KeyEventResult.ignored;
    if (cut && !_canEdit) return KeyEventResult.handled;

    switch (_effectiveClipboardPolicy) {
      case TextClipboardPolicy.allowed:
        unawaited(Clipboard.instance.write(selected));
        break;
      case TextClipboardPolicy.redacted:
        unawaited(Clipboard.instance.write(_redactClipboardText(selected)));
        break;
      case TextClipboardPolicy.disabled:
        return KeyEventResult.handled;
    }
    if (cut) {
      _cancelScheduledPaste();
      _resetHistoryBrowsing();
      _controller.deleteSelection();
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _submitCurrentText() {
    _cancelScheduledPaste();
    final text = _controller.text;
    if (widget.onSubmit != null &&
        widget.commitHistoryOnSubmit &&
        widget.historyController != null) {
      widget.historyController!.commit(text);
    } else {
      widget.historyController?.resetBrowsing();
    }
    widget.onSubmit?.call(text);
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
          _resetHistoryBrowsing();
          _controller.clear();
        }
        return;
      case SemanticAction.copy:
        _copyOrCutSelection(cut: false);
        return;
      case SemanticAction.submit:
        if (widget.enabled && widget.onSubmit != null) {
          _submitCurrentText();
        }
        return;
      case _:
        return;
    }
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
        _resetHistoryBrowsing();
        _controller.undo();
        return KeyEventResult.handled;
      case TextEditingKeyAction.redo:
        if (widget.readOnly) return KeyEventResult.handled;
        _cancelScheduledPaste();
        _resetHistoryBrowsing();
        _controller.redo();
        return KeyEventResult.handled;
      case TextEditingKeyAction.backspace:
        if (!_canEdit) return KeyEventResult.handled;
        _cancelScheduledPaste();
        _resetHistoryBrowsing();
        _controller.backspace();
        return KeyEventResult.handled;
      case TextEditingKeyAction.deleteForward:
        if (!_canEdit) return KeyEventResult.handled;
        _cancelScheduledPaste();
        _resetHistoryBrowsing();
        _controller.delete();
        return KeyEventResult.handled;
      case TextEditingKeyAction.moveLeft:
        if (_shouldBubbleHorizontalBoundary(event, atStart: true)) {
          return KeyEventResult.ignored;
        }
        _cancelScheduledPaste();
        _controller.moveCursorLeft(extend: event.hasShift);
        return KeyEventResult.handled;
      case TextEditingKeyAction.moveRight:
        if (_shouldBubbleHorizontalBoundary(event, atStart: false)) {
          return KeyEventResult.ignored;
        }
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
      case TextEditingKeyAction.previousVertical:
        if (_completionIsOpenWithOptions()) return _moveCompletion(-1);
        return _navigateHistory(previous: true);
      case TextEditingKeyAction.nextVertical:
        if (_completionIsOpenWithOptions()) return _moveCompletion(1);
        return _navigateHistory(previous: false);
      case TextEditingKeyAction.acceptCompletion:
        return _acceptCompletion();
      case TextEditingKeyAction.moveDocumentStart:
        _cancelScheduledPaste();
        _controller.moveCursorToStart(extend: event.hasShift);
        return KeyEventResult.handled;
      case TextEditingKeyAction.moveDocumentEnd:
        _cancelScheduledPaste();
        _controller.moveCursorToEnd(extend: event.hasShift);
        return KeyEventResult.handled;
      case TextEditingKeyAction.submit:
        return _submitCurrentText();
      case TextEditingKeyAction.escape:
        final completion = widget.completionController;
        if (completion != null && completion.isOpen) {
          completion.close();
          return KeyEventResult.handled;
        }
        if (widget.onEscape != null) {
          widget.onEscape!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case TextEditingKeyAction.moveUp:
      case TextEditingKeyAction.moveDown:
      case TextEditingKeyAction.moveLineStart:
      case TextEditingKeyAction.moveLineEnd:
      case TextEditingKeyAction.insertNewline:
        return KeyEventResult.ignored;
    }
  }

  bool _shouldBubbleHorizontalBoundary(
    KeyEvent event, {
    required bool atStart,
  }) {
    if (event.hasShift || event.hasCtrl || event.hasAlt) return false;
    final selection = _controller.textSelection;
    if (!selection.isCollapsed) return false;
    final offset = selection.extentOffset;
    return atStart ? offset <= 0 : offset >= _controller.text.length;
  }

  @override
  KeyEventResult onTextInput(String text) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (widget.readOnly) return KeyEventResult.handled;
    _cancelScheduledPaste();
    _resetHistoryBrowsing();
    _controller.insert(text, singleLine: true, coalesce: true);
    return KeyEventResult.handled;
  }

  @override
  KeyEventResult onPaste(String text) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (widget.readOnly) return KeyEventResult.handled;
    _resetHistoryBrowsing();
    _startPaste(TextEditingModel.normalizeSingleLineInput(text));
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _disposeBlinkTicker();
    _cancelScheduledPaste();
    widget.historyController?.removeListener(_onHistoryChange);
    widget.completionController?.removeListener(_onCompletionChange);
    _controller.removeListener(_onControllerChange);
    if (_ownsController) _controller.dispose();
    _focusNode.textInputClaimant = null;
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Compute cursor visibility from focus + blink state. The
    // ticker (lazily started in didChangeDependencies) toggles
    // _blinkOn; when unfocused we suppress the cursor entirely.
    final focused = _focusNode.hasFocus;
    final cursorVisible = focused && (!widget.enableBlink || _blinkOn);
    final history = widget.historyController;
    final completion = widget.completionController;
    final completionState = completion?.state;
    return Semantics(
      role: SemanticRole.textField,
      label:
          widget.semanticLabel ??
          (widget.placeholder.isEmpty ? null : widget.placeholder),
      value: _semanticValue,
      enabled: widget.enabled,
      focused: focused,
      validationError: widget.validationError,
      actions: {
        if (widget.enabled) SemanticAction.focus,
        if (widget.enabled && !widget.readOnly) SemanticAction.clear,
        if (widget.enabled &&
            _controller.hasSelection &&
            _effectiveClipboardPolicy != TextClipboardPolicy.disabled)
          SemanticAction.copy,
        if (widget.enabled && widget.onSubmit != null) SemanticAction.submit,
      },
      state: widget.semanticState.merge({
        'selectionBase': _controller.textSelection.baseOffset,
        'selectionExtent': _controller.textSelection.extentOffset,
        'composingActive': _controller.hasComposingRange,
        'composingStart': _controller.composing.normalizedStart,
        'composingEnd': _controller.composing.normalizedEnd,
        'readOnly': widget.readOnly,
        'obscureText': widget.obscureText,
        'redactedValue': _redactSemanticValue,
        ...textClipboardSemanticState(_effectiveClipboardPolicy),
        if (history != null) 'historyCount': history.length,
        if (history != null && history.selectedIndex != null)
          'historyIndex': history.selectedIndex,
        if (history != null) 'historyBrowsing': history.isBrowsing,
        if (completionState != null) 'completionActive': completionState.active,
        if (completionState != null &&
            completionState.active &&
            !_redactSemanticValue)
          'completionQuery': completionState.query,
        if (completionState != null && completionState.active)
          'completionRangeStart': completionState.range.normalizedStart,
        if (completionState != null && completionState.active)
          'completionRangeEnd': completionState.range.normalizedEnd,
        if (completionState != null && completionState.active)
          'completionOptionCount': completionState.options.length,
        if (completionState != null &&
            completionState.active &&
            completionState.selectedIndex != null)
          'completionSelectedIndex': completionState.selectedIndex,
        'pasteInProgress': _pasteProgress.active,
        'pasteInsertedLength': _pasteProgress.insertedLength,
        'pasteTotalLength': _pasteProgress.totalLength,
      }),
      onAction: _handleSemanticAction,
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocus && widget.enabled,
        canRequestFocus: widget.enabled,
        onKey: _handleKey,
        child: _TextInputDisplay(
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
          cursorVisible: cursorVisible,
          obscureText: widget.obscureText,
          obscuringCharacter: widget.obscuringCharacter,
        ),
      ),
    );
  }
}

class _TextInputDisplay extends LeafRenderObjectWidget {
  const _TextInputDisplay({
    required this.text,
    required this.selection,
    required this.placeholder,
    required this.placeholderStyle,
    required this.style,
    required this.cursorStyle,
    required this.cursorVisible,
    required this.obscureText,
    required this.obscuringCharacter,
  });

  final String text;
  final TextSelection selection;
  final String placeholder;
  final CellStyle placeholderStyle;
  final CellStyle style;
  final CellStyle cursorStyle;
  final bool cursorVisible;
  final bool obscureText;
  final String obscuringCharacter;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderTextInput(
      text: text,
      selection: selection,
      placeholder: placeholder,
      placeholderStyle: placeholderStyle,
      style: style,
      cursorStyle: cursorStyle,
      cursorVisible: cursorVisible,
      obscureText: obscureText,
      obscuringCharacter: obscuringCharacter,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderTextInput renderObject,
  ) {
    renderObject
      ..text = text
      ..selection = selection
      ..placeholder = placeholder
      ..placeholderStyle = placeholderStyle
      ..style = style
      ..cursorStyle = cursorStyle
      ..cursorVisible = cursorVisible
      ..obscureText = obscureText
      ..obscuringCharacter = obscuringCharacter;
  }
}

/// Paints the [text] of a [TextInput] with a one-cell inverse cursor
/// at the current [selection] code-unit index.
///
/// Layout: width = text intrinsic width (in cells) + 1 for the
/// trailing cursor position, clipped to constraints. Height = 1.
class RenderTextInput extends RenderObject {
  RenderTextInput({
    required String text,
    required TextSelection selection,
    String placeholder = '',
    CellStyle placeholderStyle = const CellStyle(dim: true),
    CellStyle style = CellStyle.empty,
    CellStyle cursorStyle = const CellStyle(inverse: true),
    bool cursorVisible = true,
    bool obscureText = false,
    String obscuringCharacter = '•',
    WidthResolver widthResolver = const DefaultWidthResolver(),
    TerminalProfile profile = TerminalProfile.standard,
  }) : _text = sanitizeForDisplay(text),
       _selection = selection.normalizeForText(sanitizeForDisplay(text)),
       _placeholder = sanitizeForDisplay(placeholder),
       _placeholderStyle = placeholderStyle,
       _style = style,
       _cursorStyle = cursorStyle,
       _cursorVisible = cursorVisible,
       _obscureText = obscureText,
       _obscuringCharacter = obscuringCharacter,
       _widthResolver = widthResolver,
       _profile = profile;

  String _text;
  TextSelection _selection;
  String _placeholder;
  CellStyle _placeholderStyle;
  CellStyle _style;
  CellStyle _cursorStyle;
  bool _cursorVisible;
  bool _obscureText;
  String _obscuringCharacter;
  final WidthResolver _widthResolver;
  final TerminalProfile _profile;
  int _scrollLeft = 0;

  set text(String value) {
    final sanitized = sanitizeForDisplay(value);
    if (sanitized == _text) return;
    _text = sanitized;
    _selection = _selection.normalizeForText(_text);
    markNeedsLayout();
  }

  set placeholder(String value) {
    final sanitized = sanitizeForDisplay(value);
    if (sanitized == _placeholder) return;
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

  /// When false, the cursor cell renders with the regular [style]
  /// rather than [cursorStyle.merge(style)]. Used to implement
  /// cursor blink (toggle this off/on every ~500 ms) and to
  /// suppress the cursor when the input is unfocused.
  set cursorVisible(bool value) {
    if (_cursorVisible == value) return;
    _cursorVisible = value;
    markNeedsPaintOnly();
  }

  set obscureText(bool value) {
    if (_obscureText == value) return;
    _obscureText = value;
    markNeedsLayout();
  }

  set obscuringCharacter(String value) {
    if (_obscuringCharacter == value) return;
    _obscuringCharacter = value;
    markNeedsLayout();
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final intrinsic = _intrinsicWidth;
    final maxCols = constraints.maxCols;
    final cols = maxCols == null ? intrinsic : intrinsic.clamp(0, maxCols);
    final nextSize = constraints.constrain(CellSize(cols, 1));
    _syncHorizontalScroll(nextSize.cols, intrinsic);
    return nextSize;
  }

  int get _intrinsicWidth {
    if (_text.isEmpty && _placeholder.isNotEmpty) {
      return _widthResolver.widthOfText(_placeholder, _profile);
    }
    var width = 0;
    for (final grapheme in _text.characters) {
      width += _displayWidthOf(grapheme);
    }
    return width + 1; // trailing cursor cell
  }

  String _displayGrapheme(String grapheme) =>
      _obscureText ? _obscuringCharacter : grapheme;

  int _displayWidthOf(String grapheme) {
    return _widthResolver.widthOfGrapheme(_displayGrapheme(grapheme), _profile);
  }

  int _displayCellForTextOffset(int textOffset) {
    var cell = 0;
    var codeUnitOffset = 0;
    for (final grapheme in _text.characters) {
      if (textOffset <= codeUnitOffset) return cell;
      codeUnitOffset += grapheme.length;
      cell += _displayWidthOf(grapheme);
      if (textOffset <= codeUnitOffset) return cell;
    }
    return cell;
  }

  int _displayBoundaryAtOrAfter(int cellOffset) {
    if (cellOffset <= 0) return 0;
    var cell = 0;
    for (final grapheme in _text.characters) {
      final next = cell + _displayWidthOf(grapheme);
      if (cellOffset <= cell) return cell;
      if (cellOffset < next) return next;
      cell = next;
    }
    return cell;
  }

  void _syncHorizontalScroll(int visibleCols, int intrinsicWidth) {
    if (visibleCols <= 0 || intrinsicWidth <= visibleCols || _text.isEmpty) {
      _scrollLeft = 0;
      return;
    }
    final cursorCell = _displayCellForTextOffset(_selection.extentOffset);
    var next = _scrollLeft;
    if (cursorCell < next) {
      next = cursorCell;
    } else if (cursorCell >= next + visibleCols) {
      next = cursorCell - visibleCols + 1;
    }
    if (next < 0) next = 0;
    next = _displayBoundaryAtOrAfter(next);
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
    if (size.isEmpty) return;
    final row = offset.row;
    var col = offset.col;
    final maxCol = offset.col + size.cols;

    // Empty field: paint the placeholder (with the cursor over its first
    // cell when visible) instead of the text + trailing cursor.
    if (_text.isEmpty && _placeholder.isNotEmpty) {
      var first = true;
      for (final grapheme in _placeholder.characters) {
        if (col >= maxCol) break;
        final width = _widthResolver.widthOfGrapheme(grapheme, _profile);
        if (col + width > maxCol) break;
        final style = (first && _cursorVisible)
            ? _placeholderStyle.merge(_cursorStyle)
            : _placeholderStyle;
        buffer.writeGrapheme(
          CellOffset(col, row),
          grapheme,
          style: style,
          widthResolver: _widthResolver,
          profile: _profile,
        );
        col += _widthResolver.widthOfGrapheme(grapheme, _profile);
        first = false;
      }
      return;
    }

    var codeUnitOffset = 0;
    var paintedCursor = false;
    final selectionStart = _selection.start;
    final selectionEnd = _selection.end;
    final cursorOffset = _selection.extentOffset;
    final selectionCollapsed = _selection.isCollapsed;
    final visibleStart = _scrollLeft;
    final visibleEnd = _scrollLeft + size.cols;
    var displayCell = 0;

    for (final grapheme in _text.characters) {
      final graphemeStart = codeUnitOffset;
      final graphemeEnd = codeUnitOffset + grapheme.length;
      final displayed = _displayGrapheme(grapheme);
      final displayWidth = _widthResolver.widthOfGrapheme(displayed, _profile);
      final displayStart = displayCell;
      final displayEnd = displayStart + displayWidth;
      codeUnitOffset = graphemeEnd;
      displayCell = displayEnd;
      if (displayEnd <= visibleStart) continue;
      if (displayStart < visibleStart) continue;
      if (displayStart >= visibleEnd) break;
      if (displayEnd > visibleEnd) break;
      final atCursor = selectionCollapsed && graphemeStart == cursorOffset;
      final selected =
          !selectionCollapsed &&
          graphemeStart >= selectionStart &&
          graphemeEnd <= selectionEnd;
      // Only apply cursorStyle when the cursor is currently visible
      // (focused + blink-on). When invisible, the cursor cell
      // renders with the base style so the character underneath
      // (or a blank if past EOL) reads normally.
      final cellStyle = ((atCursor && _cursorVisible) || selected)
          ? _style.merge(_cursorStyle)
          : _style;
      // Mask the displayed glyph when obscureText is on. The real text
      // (and the cursor's code-unit position) is unchanged — only the
      // pixel rendering is replaced.
      col = offset.col + (displayStart - visibleStart);
      buffer.writeGrapheme(
        CellOffset(col, row),
        displayed,
        style: cellStyle,
        widthResolver: _widthResolver,
        profile: _profile,
      );
      if (atCursor) paintedCursor = true;
    }

    // Cursor past the last character.
    if (selectionCollapsed && !paintedCursor) {
      final cursorCell = _displayCellForTextOffset(cursorOffset);
      final cursorVisible =
          cursorCell >= visibleStart && cursorCell < visibleEnd;
      col = offset.col + (cursorCell - visibleStart);
      if (cursorVisible && col < maxCol) {
        if (_cursorVisible) {
          buffer.writeGrapheme(
            CellOffset(col, row),
            ' ',
            style: _style.merge(_cursorStyle),
          );
        }
        // When the cursor is invisible past-EOL, we deliberately
        // leave the cell empty — same as the rest of the trailing
        // space.
      }
    }
  }
}
