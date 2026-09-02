import 'dart:async';
import 'dart:js_interop';

import 'package:fleury/fleury_host.dart';
import 'package:web/web.dart' as web;

import '../focus/web_focus_coordinator.dart';
import '../metrics/cell_metrics.dart';
import 'input_source.dart';

/// Browser DOM input source for the retained web host.
///
/// Event listeners normalize browser keyboard, text, paste, pointer, and wheel
/// events into Fleury events. They never dispatch into the widget tree
/// directly; [runTuiSurface] drains the queued events during the frame update
/// phase.
final class DomInputSource implements TuiInputSource, KeyboardCaptureTarget {
  DomInputSource({
    required web.Element hostElement,
    required CellMetrics cellMetrics,
    web.Element? pointerTarget,
    this.pointerCursorResolver,
    web.HTMLTextAreaElement? textArea,
    web.Document? document,
    WebFocusCoordinator? focusCoordinator,
    Clipboard? clipboard,
    bool captureKeyboardFromDocument = false,
  }) : _hostElement = hostElement,
       _pointerTarget = pointerTarget ?? hostElement,
       _cellMetrics = cellMetrics,
       _document = document ?? web.document,
       _textArea = textArea,
       _focusCoordinator = focusCoordinator,
       _clipboard = clipboard,
       _captureKeyboardFromDocument = captureKeyboardFromDocument,
       _ownsTextArea = textArea == null;

  final web.Element _hostElement;
  final web.Element _pointerTarget;
  final bool Function(CellOffset cell)? pointerCursorResolver;
  final CellMetrics _cellMetrics;
  final web.Document _document;
  final web.HTMLTextAreaElement? _textArea;
  final WebFocusCoordinator? _focusCoordinator;
  final Clipboard? _clipboard;

  /// Whether a pointerdown ANYWHERE in the document should re-acquire
  /// keyboard capture. True only for `fleury serve`'s page, where the page IS
  /// the app and its chrome (the `#status` line) lives outside the host. An
  /// embedded surface is a guest on someone else's page: it recovers capture
  /// from its own host, never from the rest of the document.
  final bool _captureKeyboardFromDocument;
  final bool _ownsTextArea;

  // Whether the most recent keydown was an auto-repeat. The text half of a
  // printable key arrives on the `input` event, separately, and must carry
  // the same phase (RFC 0020 §14.4: a repeat never advances a sequence).
  var _lastKeyDownRepeat = false;
  final List<_DomListener> _listeners = [];

  TuiInputSink? _onEvent;
  web.HTMLTextAreaElement? _activeTextArea;
  var _started = false;
  var _appendedTextArea = false;
  var _composing = false;
  String? _lastCompositionText;
  String? _pendingCompositionInput;
  String? _suppressNextInputText;
  var _compositionSuppressionGeneration = 0;
  MouseButton _pressedButton = MouseButton.none;
  MouseButton _captureLostButton = MouseButton.none;
  var _suppressNextPointerClick = false;
  String? _cursorBeforeStart;

  // The last move this source emitted, so an identical re-emit can be
  // dropped. Browsers fire pointermove at 60-120 Hz while the grid's
  // resolution is a CELL: every sample landing in the same cell with the same
  // buttons and modifiers is indistinguishable to the app, but on the served
  // path each one costs an InputEventFrame on the wire, a full host-side
  // dispatch, and a scheduled frame. Null kind means "no previous move" —
  // the state every gesture boundary resets to.
  MouseEventKind? _lastMoveKind;
  var _lastMoveCol = -1;
  var _lastMoveRow = -1;
  var _lastMoveButtons = -1;
  Set<KeyModifier> _lastMoveModifiers = const {};
  // Identity of the measurement the last move was mapped through: a
  // re-measure (resize, font swap, DPR change) hands out a NEW box, so this
  // also drops the filter whenever the cell grid itself changed underneath.
  MeasuredCellBox? _lastMoveMetrics;

  @override
  void start(TuiInputSink onEvent) {
    if (_started) return;
    _started = true;
    _onEvent = onEvent;
    _cursorBeforeStart = _pointerStyle?.getPropertyValue('cursor');

    final textArea = _textArea ?? _createTextArea();
    _activeTextArea = textArea;
    if (textArea.parentNode == null) {
      _hostElement.appendChild(textArea);
      _appendedTextArea = true;
    }

    _add(textArea, 'keydown', _handleKeyDown);
    _add(textArea, 'keyup', _handleKeyUp);
    _add(web.document, 'visibilitychange', _handleVisibilityChange);
    _add(textArea, 'compositionstart', _handleCompositionStart);
    _add(textArea, 'compositionupdate', _handleCompositionUpdate);
    _add(textArea, 'compositionend', _handleCompositionEnd);
    _add(textArea, 'input', _handleInput);
    _add(textArea, 'paste', _handlePaste);
    _add(textArea, 'focusin', _handleTextAreaFocusIn);
    _add(textArea, 'focusout', _handleTextAreaFocusOut);
    _add(_pointerTarget, 'pointerdown', _handlePointerDown);
    _add(_pointerTarget, 'pointerup', _handlePointerUp);
    _add(_pointerTarget, 'pointercancel', _handlePointerCancel);
    _add(_pointerTarget, 'lostpointercapture', _handleLostPointerCapture);
    _add(_pointerTarget, 'pointermove', _handlePointerMove);
    _add(_pointerTarget, 'pointerleave', _handlePointerLeave);
    _add(_pointerTarget, 'click', _handleClick);
    _add(_pointerTarget, 'wheel', _handleWheel);
    // Capture recovery, one layer out from the grid. The keyboard listeners
    // are on the hidden textarea above, and only a pointerdown on the GRID
    // re-focuses it — so a click on the host's own chrome (its padding ring,
    // or any host area the grid does not cover) blurs the textarea, which
    // sweeps held keys and drops the coordinator, and the session goes
    // keyboard-dead with no cue until a click happens to land back on the
    // grid. Skipped when the grid IS the host: the grid listener above
    // already covers every pointerdown that could reach this one.
    if (!identical(_pointerTarget, _hostElement)) {
      _add(_hostElement, 'pointerdown', _handleCapturePointerDown);
    }
    if (_captureKeyboardFromDocument) {
      _add(_document, 'pointerdown', _handleCapturePointerDown);
    }

    _clearTextArea();
    textArea.focus();
    _focusCoordinator?.handleBrowserFocusIn(WebFocusTarget.keyboardCapture);
  }

  @override
  void ensureKeyboardCapture() {
    if (!_started) return;
    _activeTextArea?.focus();
    _focusCoordinator?.handleBrowserFocusIn(WebFocusTarget.keyboardCapture);
  }

  @override
  void dispose() {
    _sweepOpenPresses();
    _restorePointerCursor();
    for (final listener in _listeners.reversed) {
      listener.target.removeEventListener(listener.type, listener.callback);
    }
    _listeners.clear();
    _onEvent = null;
    _started = false;
    _composing = false;
    _lastCompositionText = null;
    _pendingCompositionInput = null;
    _suppressNextInputText = null;
    _compositionSuppressionGeneration += 1;
    _pressedButton = MouseButton.none;
    _captureLostButton = MouseButton.none;
    _suppressNextPointerClick = false;
    _forgetLastMove();
    _cursorBeforeStart = null;
    _focusCoordinator?.handleBrowserFocusOut(WebFocusTarget.keyboardCapture);
    _clearTextArea();
    final textArea = _activeTextArea;
    if (textArea != null && (_ownsTextArea || _appendedTextArea)) {
      textArea.parentNode?.removeChild(textArea);
    }
    _activeTextArea = null;
    _appendedTextArea = false;
  }

  void _add(
    web.EventTarget target,
    String type,
    void Function(web.Event event) handler,
  ) {
    final callback = ((web.Event event) {
      if (!_started) return;
      handler(event);
    }).toJS;
    target.addEventListener(type, callback);
    _listeners.add(_DomListener(target, type, callback));
  }

  web.HTMLTextAreaElement _createTextArea() {
    final textArea =
        _document.createElement('textarea') as web.HTMLTextAreaElement;
    textArea.setAttribute('aria-hidden', 'true');
    textArea.setAttribute('autocomplete', 'off');
    textArea.setAttribute('autocorrect', 'off');
    textArea.setAttribute('autocapitalize', 'off');
    textArea.setAttribute('spellcheck', 'false');
    textArea.setAttribute('tabindex', '-1');
    textArea.setAttribute('style', _textAreaStyle(_textAreaPlacement()));
    return textArea;
  }

  @override
  void syncCaretGeometry(CellRect? caretRect, MeasuredCellBox? metrics) {
    final textArea = _activeTextArea;
    if (textArea == null) return;
    final placement = _textAreaPlacement(
      caretRect: caretRect,
      metrics: metrics,
    );
    textArea.setAttribute('style', _textAreaStyle(placement));
    _syncCaretPlacementAttributes(textArea, placement);
  }

  _TextAreaPlacement _textAreaPlacement({
    CellRect? caretRect,
    MeasuredCellBox? metrics,
  }) {
    var left = -10000.0;
    var top = -10000.0;
    var width = 1.0;
    var height = 1.0;
    if (caretRect != null && metrics != null) {
      left = metrics.cssCanvasLeft + caretRect.left * metrics.cssCellWidth;
      top = metrics.cssCanvasTop + caretRect.top * metrics.cssCellHeight;
      width = _cssCellExtent(caretRect.size.cols, metrics.cssCellWidth);
      height = _cssCellExtent(caretRect.size.rows, metrics.cssCellHeight);
    }
    return _TextAreaPlacement(
      caretRect: caretRect,
      positioned: caretRect != null && metrics != null,
      left: left,
      top: top,
      width: width,
      height: height,
    );
  }

  String _textAreaStyle(_TextAreaPlacement placement) {
    return 'position:fixed;'
        'left:${_cssPx(placement.left)};top:${_cssPx(placement.top)};'
        'width:${_cssPx(placement.width)};'
        'height:${_cssPx(placement.height)};'
        'opacity:0;pointer-events:none;resize:none;overflow:hidden;';
  }

  void _syncCaretPlacementAttributes(
    web.HTMLTextAreaElement textArea,
    _TextAreaPlacement placement,
  ) {
    textArea.setAttribute(
      'data-fleury-caret-state',
      placement.positioned ? 'positioned' : 'hidden',
    );
    if (!placement.positioned) {
      for (final name in _caretPlacementAttributeNames) {
        textArea.removeAttribute(name);
      }
      return;
    }
    final caretRect = placement.caretRect!;
    textArea.setAttribute('data-fleury-caret-col', '${caretRect.left}');
    textArea.setAttribute('data-fleury-caret-row', '${caretRect.top}');
    textArea.setAttribute(
      'data-fleury-caret-width-cells',
      '${caretRect.size.cols}',
    );
    textArea.setAttribute(
      'data-fleury-caret-height-cells',
      '${caretRect.size.rows}',
    );
    textArea.setAttribute('data-fleury-caret-css-left', _cssPx(placement.left));
    textArea.setAttribute('data-fleury-caret-css-top', _cssPx(placement.top));
    textArea.setAttribute(
      'data-fleury-caret-css-width',
      _cssPx(placement.width),
    );
    textArea.setAttribute(
      'data-fleury-caret-css-height',
      _cssPx(placement.height),
    );
  }

  double _cssCellExtent(int cells, double cellSize) {
    final count = cells <= 0 ? 1 : cells;
    return count * cellSize;
  }

  String _cssPx(double value) {
    if (value == value.roundToDouble()) return '${value.toInt()}px';
    var text = value.toStringAsFixed(3);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
    return '${text}px';
  }

  void _emit(TuiEvent event) {
    _onEvent?.call(event);
  }

  /// Presses this source has reported a `down` for and not yet closed,
  /// keyed by DOM `code` (or `key` when code is unavailable). The source's
  /// own bookkeeping — what IT told the runtime — used to pair keyups to
  /// their downs with down-time identity, to sweep on blur/visibility loss,
  /// and to run the macOS Meta regime (RFC 0020 §10).
  final Map<String, KeyEvent> _openPresses = {};

  String _pressIdentity(web.KeyboardEvent event) =>
      event.code.isNotEmpty && event.code != 'Unidentified'
      ? event.code
      : 'key:${event.key}';

  /// Whether the browser's default action must be allowed to run so the
  /// textarea produces the `input` event carrying this key's committed text.
  ///
  /// Plain and Shift-only printables are text-producing: RFC 0020 has the
  /// source emit their key half for lifecycle tracking, but the text itself
  /// still arrives through the input channel (§11 — "keydown never inserts
  /// text; the browser's input events stay authoritative for IME and
  /// dead-key correctness"). Calling `preventDefault()` on those keydowns
  /// would suppress the insertion, the `input` event, and therefore ALL
  /// typing on this surface.
  static bool _needsBrowserTextDefault(
    web.KeyboardEvent event,
    KeyEvent mapped,
  ) =>
      mapped.code.isCharacter &&
      !event.ctrlKey &&
      !event.altKey &&
      !event.metaKey;

  void _handleKeyDown(web.Event raw) {
    final event = raw as web.KeyboardEvent;
    final tuiEvent = keyEventFromBrowser(event);
    if (tuiEvent == null) return;
    _lastKeyDownRepeat = event.repeat;

    // Special keys and shortcut chords are ours; text-producing printables
    // keep their default action (see above).
    if (!_needsBrowserTextDefault(event, tuiEvent)) raw.preventDefault();

    if (event.metaKey && !_isModifierKey(event.key)) {
      // macOS browsers swallow keyup for non-modifier keys while Cmd is
      // held (cross-engine, RFC 0020 §10): keys under Meta get press-only
      // semantics — the down, then an immediate synthesized release —
      // rather than an unclosable press. Hold durations under Meta are
      // undefined by contract.
      _emit(tuiEvent);
      if (tuiEvent.type != KeyEventType.up) {
        // Repeats close too. The session's repeat-without-down repair OPENS a
        // held record for an auto-repeat it never saw a down for (§22); under
        // this regime nothing else will ever close it, so the key would wedge
        // held for the session — and the next genuine press would regularize
        // to `repeat`, which the command lane filters out by default, killing
        // that key's bindings.
        _emit(
          KeyEvent(
            tuiEvent.code,
            modifiers: tuiEvent.modifiers,
            type: KeyEventType.up,
            position: tuiEvent.position,
            synthesized: true,
          ),
        );
      }
      return;
    }
    if (tuiEvent.type != KeyEventType.up) {
      // Repeats re-open the press too. A sweep (Meta tap, tab hide, blur)
      // closes presses the user may still be physically holding; the
      // session's repeat-without-down repair re-opens its record on the
      // next auto-repeat, so this side must re-open in lockstep or the
      // eventual real keyup finds nothing to close and the key wedges as
      // permanently held (RFC 0020 §22's stuck-key criterion).
      _openPresses[_pressIdentity(event)] = tuiEvent;
    }
    _emit(tuiEvent);
  }

  void _handleKeyUp(web.Event raw) {
    _lastKeyDownRepeat = false;
    final event = raw as web.KeyboardEvent;
    if (event.key == 'Meta') {
      // Meta's OWN release is physical and must be reported as such — a
      // synthesized one could never complete a `nextKey` capture (§6's
      // taxonomy), making Cmd unbindable in a rebind UI. Emit it first,
      // then sweep the rest: the swallow can also eat releases of keys
      // pressed BEFORE Meta went down, and a key genuinely still held
      // re-appears via auto-repeat and the session's repair.
      final metaDown = _openPresses.remove(_pressIdentity(event));
      if (metaDown != null) {
        _emit(
          KeyEvent(
            metaDown.code,
            type: KeyEventType.up,
            position: metaDown.position,
          ),
        );
      }
      _sweepOpenPresses();
      return;
    }
    final down = _openPresses.remove(_pressIdentity(event));
    if (down == null) return; // press-only'd, or downed before attach
    // No preventDefault: a keyup has no text-producing default action, and
    // suppressing it could only interfere with the input channel.
    _emit(
      KeyEvent(
        // Down-time identity: layout/modifier state may have changed
        // mid-press; the release closes the press that opened.
        down.code,
        modifiers: _modifiersFromKeyboard(event),
        type: KeyEventType.up,
        position: down.position,
      ),
    );
  }

  /// Closes every open press with a synthesized release — the web
  /// authority-loss triggers (§6): keyboard-capture blur, tab visibility
  /// loss, Meta-up sweep, disposal.
  void _sweepOpenPresses() {
    if (_openPresses.isEmpty) return;
    final open = List.of(_openPresses.values);
    _openPresses.clear();
    for (final down in open) {
      _emit(
        KeyEvent(
          down.code,
          type: KeyEventType.up,
          position: down.position,
          synthesized: true,
        ),
      );
    }
  }

  void _handleVisibilityChange(web.Event raw) {
    if (web.document.visibilityState == 'hidden') _sweepOpenPresses();
  }

  void _handleInput(web.Event raw) {
    final event = raw as web.InputEvent;
    final data = event.data;
    if (event.inputType == 'insertFromPaste') {
      raw.preventDefault();
      _clearTextArea();
      return;
    }
    if (event.isComposing || _composing) {
      if (data != null && data.isNotEmpty) {
        _pendingCompositionInput = data;
      }
      return;
    }
    final suppressNext = _suppressNextInputText;
    if (suppressNext != null) {
      _suppressNextInputText = null;
      _compositionSuppressionGeneration += 1;
      if (data == suppressNext) {
        raw.preventDefault();
        _clearTextArea();
        return;
      }
    }
    _clearTextArea();
    if (data == null || data.isEmpty) return;
    raw.preventDefault();
    _emit(TextInputEvent(data, repeat: _lastKeyDownRepeat));
  }

  void _handleCompositionStart(web.Event raw) {
    _composing = true;
    _lastCompositionText = null;
    _pendingCompositionInput = null;
    _suppressNextInputText = null;
    _compositionSuppressionGeneration += 1;
  }

  void _handleCompositionUpdate(web.Event raw) {
    final event = raw as web.CompositionEvent;
    _composing = true;
    final text = event.data;
    _lastCompositionText = text;
    _emit(TextCompositionEvent.update(text));
  }

  void _handleCompositionEnd(web.Event raw) {
    final event = raw as web.CompositionEvent;
    final hadComposition =
        _composing ||
        _lastCompositionText != null ||
        _pendingCompositionInput != null;
    final commitText = event.data.isNotEmpty
        ? event.data
        : _pendingCompositionInput;
    _composing = false;
    _lastCompositionText = null;
    _pendingCompositionInput = null;
    _clearTextArea();
    if (!hadComposition) return;
    if (commitText == null || commitText.isEmpty) {
      _suppressNextInputText = null;
      _emit(const TextCompositionEvent.cancel());
      return;
    }
    _suppressNextInputText = commitText;
    final suppressionGeneration = ++_compositionSuppressionGeneration;
    Timer.run(() {
      // A browser that echoes the committed composition as a trailing `input`
      // dispatches it in the same native event task. Keep the one-shot guard for
      // that echo, but do not let it suppress an unrelated identical character
      // typed later when an engine emits no trailing input at all.
      if (!_started ||
          suppressionGeneration != _compositionSuppressionGeneration) {
        return;
      }
      _suppressNextInputText = null;
    });
    _emit(TextCompositionEvent.commit(commitText));
  }

  void _handlePaste(web.Event raw) {
    final event = raw as web.ClipboardEvent;
    final text = _pasteText(event);
    if (text.isEmpty) return;
    raw.preventDefault();
    _clearTextArea();
    _emit(PasteEvent(text));
  }

  void _handleTextAreaFocusIn(web.Event raw) {
    _focusCoordinator?.handleBrowserFocusIn(WebFocusTarget.keyboardCapture);
  }

  void _handleTextAreaFocusOut(web.Event raw) {
    // Keyboard-capture blur is authority loss for held keys: the release
    // will be delivered to whatever got focus, never to us.
    _sweepOpenPresses();
    _focusCoordinator?.handleBrowserFocusOut(WebFocusTarget.keyboardCapture);
  }

  /// Re-acquires keyboard capture for a pointerdown that landed outside the
  /// cell grid (see the listener registration in [start]). Deliberately does
  /// nothing else: this event is chrome, not app input.
  void _handleCapturePointerDown(web.Event raw) {
    // A cell-grid link owns its whole gesture — same exemption as
    // [_handlePointerDown]; focusing the textarea mid-gesture could retarget
    // the anchor's click away from the browser's native navigation.
    if (_cellGridLinkAnchor(raw) != null) return;
    ensureKeyboardCapture();
  }

  void _handlePointerDown(web.Event raw) {
    // A new physical gesture supersedes any orphaned compatibility-click
    // marker left by a prior gesture (for example, if the browser omitted its
    // click because the original target detached).
    _suppressNextPointerClick = false;
    _captureLostButton = MouseButton.none;
    _forgetLastMove();
    // A cell-grid link owns its whole gesture: let the browser navigate the
    // href natively. Capturing the pointer here would retarget the click away
    // from the anchor, and routing it as an app pointer event would consume it.
    if (_cellGridLinkAnchor(raw) != null) return;
    ensureKeyboardCapture();
    final event = raw as web.PointerEvent;
    final button = _buttonFor(event.button);
    final cell = _cellForPointer(event);
    if (button == MouseButton.none || cell == null) return;
    _pressedButton = button;
    try {
      _pointerTarget.setPointerCapture(event.pointerId);
    } catch (_) {
      // Synthetic test events and some browser/device combinations may not
      // have an active pointer capture target. Drag routing still works
      // through the host-level listener and Fleury's PointerRouter capture.
    }
    raw.preventDefault();
    _emit(
      MouseEvent(
        kind: MouseEventKind.down,
        button: button,
        col: cell.col,
        row: cell.row,
        modifiers: _modifiersFromMouse(event),
      ),
    );
  }

  void _handlePointerUp(web.Event raw) {
    // Counterpart to the pointerdown exemption: a cell-grid link is the
    // browser's to navigate, so don't preventDefault or route it.
    if (_cellGridLinkAnchor(raw) != null) return;
    _forgetLastMove();
    final event = raw as web.PointerEvent;
    var button = _buttonFor(event.button);
    if (button == MouseButton.none && _pressedButton != MouseButton.none) {
      button = _pressedButton;
    }
    if (button == MouseButton.none && _captureLostButton != MouseButton.none) {
      button = _captureLostButton;
    }
    final cell = _cellForPointer(event);
    if (button == MouseButton.none || cell == null) return;
    try {
      if (_pointerTarget.hasPointerCapture(event.pointerId)) {
        _pointerTarget.releasePointerCapture(event.pointerId);
      }
    } catch (_) {
      // Best-effort counterpart to pointerdown capture.
    }
    _suppressNextPointerClick = true;
    _pressedButton = MouseButton.none;
    _captureLostButton = MouseButton.none;
    raw.preventDefault();
    _emit(
      MouseEvent(
        kind: MouseEventKind.up,
        button: button,
        col: cell.col,
        row: cell.row,
        modifiers: _modifiersFromMouse(event),
      ),
    );
  }

  void _handlePointerCancel(web.Event raw) {
    final event = raw as web.PointerEvent;
    try {
      if (_pointerTarget.hasPointerCapture(event.pointerId)) {
        _pointerTarget.releasePointerCapture(event.pointerId);
      }
    } catch (_) {
      // Best-effort counterpart to pointerdown capture.
    }
    _pressedButton = MouseButton.none;
    _captureLostButton = MouseButton.none;
    _suppressNextPointerClick = false;
    _forgetLastMove();
  }

  void _handleLostPointerCapture(web.Event _) {
    // Pointer capture is normally released between pointerup and click. If it
    // arrives earlier, stop drag routing but remember which press still needs
    // its up event. `pointercancel` owns true cancellation; a later pointerup or
    // compatibility click can close this interrupted press without emitting a
    // second down.
    _forgetLastMove();
    if (_pressedButton != MouseButton.none) {
      _captureLostButton = _pressedButton;
      _pressedButton = MouseButton.none;
    }
  }

  void _handlePointerMove(web.Event raw) {
    final event = raw as web.PointerEvent;
    final cell = _cellForPointer(event);
    if (cell == null) {
      _restorePointerCursor();
      return;
    }
    _syncPointerCursor(cell);
    final dragging = event.buttons != 0 && _pressedButton != MouseButton.none;
    raw.preventDefault();
    final kind = dragging ? MouseEventKind.drag : MouseEventKind.moved;
    final modifiers = _modifiersFromMouse(event);
    if (_isRepeatedMove(kind, cell, event.buttons, modifiers)) return;
    _emit(
      MouseEvent(
        kind: kind,
        button: dragging ? _pressedButton : MouseButton.none,
        col: cell.col,
        row: cell.row,
        modifiers: modifiers,
      ),
    );
  }

  /// Whether this move is indistinguishable from the last one emitted — and,
  /// when it is not, records it as the new baseline.
  bool _isRepeatedMove(
    MouseEventKind kind,
    CellOffset cell,
    int buttons,
    Set<KeyModifier> modifiers,
  ) {
    final metrics = _cellMetrics.cachedMeasurement;
    if (_lastMoveKind == kind &&
        _lastMoveCol == cell.col &&
        _lastMoveRow == cell.row &&
        _lastMoveButtons == buttons &&
        identical(_lastMoveMetrics, metrics) &&
        _sameModifiers(_lastMoveModifiers, modifiers)) {
      return true;
    }
    _lastMoveKind = kind;
    _lastMoveCol = cell.col;
    _lastMoveRow = cell.row;
    _lastMoveButtons = buttons;
    _lastMoveModifiers = modifiers;
    _lastMoveMetrics = metrics;
    return false;
  }

  /// Forgets the last emitted move. Every gesture boundary calls this so a
  /// press, release, or cancellation can never leave the next move looking
  /// like a duplicate of the one before it.
  void _forgetLastMove() {
    _lastMoveKind = null;
    _lastMoveModifiers = const {};
    _lastMoveMetrics = null;
  }

  static bool _sameModifiers(Set<KeyModifier> a, Set<KeyModifier> b) =>
      a.length == b.length && a.containsAll(b);

  void _handlePointerLeave(web.Event _) => _restorePointerCursor();

  web.CSSStyleDeclaration? get _pointerStyle =>
      _pointerTarget.isA<web.HTMLElement>()
      ? (_pointerTarget as web.HTMLElement).style
      : null;

  void _syncPointerCursor(CellOffset cell) {
    final style = _pointerStyle;
    if (style == null) return;
    if (pointerCursorResolver?.call(cell) ?? false) {
      style.setProperty('cursor', 'pointer');
    } else {
      _restorePointerCursor();
    }
  }

  void _restorePointerCursor() {
    final style = _pointerStyle;
    if (style == null) return;
    final previous = _cursorBeforeStart;
    if (previous == null || previous.isEmpty) {
      style.removeProperty('cursor');
    } else {
      style.setProperty('cursor', previous);
    }
  }

  void _handleClick(web.Event raw) {
    final event = raw as web.MouseEvent;
    if (event.button != 0) return;
    final followsCompletedPointerGesture = _suppressNextPointerClick;
    _suppressNextPointerClick = false;
    if (followsCompletedPointerGesture && event.detail > 0) {
      // The pointer gesture already produced the app tap. Suppress its browser
      // compatibility click even if rendering changed the cell or DOM target
      // between pointerup and click.
      raw.preventDefault();
      return;
    }
    // The critical link fix: a click on a cell-grid link anchor must reach the
    // browser's default action (navigation). preventDefault() below would cancel
    // it, so bail before then — and don't route it as an app tap either.
    if (_cellGridLinkAnchor(raw) != null) return;
    final cell = _cellForPointer(event);
    if (cell == null) return;
    raw.preventDefault();
    final modifiers = _modifiersFromMouse(event);
    final openButton = _pressedButton != MouseButton.none
        ? _pressedButton
        : _captureLostButton;
    if (openButton != MouseButton.none) {
      _emit(
        MouseEvent(
          kind: MouseEventKind.up,
          button: openButton,
          col: cell.col,
          row: cell.row,
          modifiers: modifiers,
        ),
      );
      _pressedButton = MouseButton.none;
      _captureLostButton = MouseButton.none;
      return;
    }
    _emit(
      MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: cell.col,
        row: cell.row,
        modifiers: modifiers,
      ),
    );
    _emit(
      MouseEvent(
        kind: MouseEventKind.up,
        button: MouseButton.left,
        col: cell.col,
        row: cell.row,
        modifiers: modifiers,
      ),
    );
    _pressedButton = MouseButton.none;
  }

  // Accumulated wheel travel (CSS px) toward the next scroll step. Browsers —
  // trackpads especially — fire many small wheel events per gesture; emitting
  // one scroll step per event makes the list race. Accumulating pixel delta
  // and stepping once per row of travel ties scroll speed to finger distance,
  // not event count.
  double _wheelAccumY = 0;

  void _handleWheel(web.Event raw) {
    final event = raw as web.WheelEvent;
    // ctrl/Cmd + wheel is the browser's zoom gesture — and Chrome delivers a
    // trackpad PINCH as ctrl+wheel. This listener is non-passive and (on the
    // served page) covers the whole viewport, so consuming these would make
    // zoom impossible anywhere on the page. Leave the gesture to the browser
    // and don't feed it into the scroll accumulator either.
    if (event.ctrlKey || event.metaKey) return;
    if (event.deltaY == 0) return;
    final cell = _cellForPointer(event);
    if (cell == null) return;
    raw.preventDefault();

    // One scroll step per row of travel (content-following). Fall back to a
    // sane line height before the canvas has been measured.
    final box = _cellMetrics.cachedMeasurement;
    final stepPx = (box != null && box.cssCellHeight > 0)
        ? box.cssCellHeight
        : 18.0;
    final px = _wheelDeltaToPixels(event);
    // Reset on direction reversal so a stale remainder can't fire a late step
    // the wrong way.
    if (_wheelAccumY != 0 && px.sign != _wheelAccumY.sign) _wheelAccumY = 0;
    _wheelAccumY += px;

    var steps = _wheelAccumY.abs() ~/ stepPx;
    if (steps == 0) return;
    // Cap a single event's burst so a page-sized delta can't fire dozens.
    if (steps > 8) steps = 8;
    final up = _wheelAccumY < 0;
    _wheelAccumY -= (up ? -1 : 1) * steps * stepPx;

    final kind = up ? MouseEventKind.scrollUp : MouseEventKind.scrollDown;
    for (var i = 0; i < steps; i++) {
      _emit(
        MouseEvent(
          kind: kind,
          button: MouseButton.none,
          col: cell.col,
          row: cell.row,
          modifiers: _modifiersFromMouse(event),
        ),
      );
    }
  }

  /// Normalizes a wheel event's deltaY to CSS pixels regardless of its
  /// `deltaMode` (0 = pixel, 1 = line, 2 = page).
  static double _wheelDeltaToPixels(web.WheelEvent event) {
    final d = event.deltaY;
    return switch (event.deltaMode) {
      1 => d * 16.0, // DOM_DELTA_LINE — ~one text line
      2 => d * 400.0, // DOM_DELTA_PAGE — ~one viewport
      _ => d, // DOM_DELTA_PIXEL
    };
  }

  void _clearTextArea() {
    final textArea = _activeTextArea;
    if (textArea != null) textArea.value = '';
  }

  String _clipboardText(web.DataTransfer data) {
    final plain = data.getData('text/plain');
    if (plain.isNotEmpty) return plain;
    return data.getData('text');
  }

  String _pasteText(web.ClipboardEvent event) {
    final clipboardData = event.clipboardData;
    if (clipboardData != null) return _clipboardText(clipboardData);
    return _clipboard?.readInProcess() ?? '';
  }

  CellOffset? _cellForPointer(web.MouseEvent event) {
    final box = _cellMetrics.cachedMeasurement;
    if (box == null || box.cols <= 0 || box.rows <= 0) return null;
    // Read coordinates as doubles: package:web types clientX/clientY as
    // `int`, but pointer events deliver sub-pixel (fractional) values on
    // HiDPI/Retina displays. Reading those as `int` makes dart2js assert
    // integer-ness and throw, which would drop every pointer event (wheel
    // events report integer coords, so they slip through — exactly the
    // "scroll works, click doesn't" symptom).
    final coords = _PointerCoords(event as JSObject);
    return _cellMetrics.cellForViewportPoint(coords.clientX, coords.clientY);
  }
}

/// Reinterprets a pointer/mouse event to read its coordinates as `double`,
/// avoiding the integer assertion `package:web`'s `int`-typed `clientX`/
/// `clientY` would trigger on fractional (sub-pixel) values.
extension type _PointerCoords(JSObject _event) implements JSObject {
  external double get clientX;
  external double get clientY;
}

/// Maps a browser keydown event to a Fleury key event.
///
/// Maps a browser keydown to its Fleury key event (RFC 0020 web backend).
///
/// Every mapped event carries the positional identity from
/// `KeyboardEvent.code` when the browser knew it (`Unidentified` → null —
/// per-event nullability, §13.3). Printables emit key events with their
/// committed text still arriving through the textarea `input` channel as
/// [TextInputEvent] — the dispatcher's routing keeps unmodified printable
/// key halves out of the command lane so character bindings fire once.
KeyEvent? keyEventFromBrowser(web.KeyboardEvent event) {
  if (event.isComposing) return null;
  final key = event.key;
  if (key == 'Dead' || key == 'Unidentified' || key.isEmpty) return null;

  final position = event.code.isEmpty ? null : positionByDomCode[event.code];

  final keyCode = _keyCodeFor(key);
  final modifiers = _modifiersFromKeyboard(event);
  final type = event.repeat ? KeyEventType.repeat : KeyEventType.down;
  if (_isBrowserPasteAccelerator(event, key, keyCode)) return null;
  if (keyCode != null) {
    return KeyEvent(
      keyCode,
      modifiers: modifiers,
      type: type,
      position: position,
    );
  }

  // Lone modifier keys are keys (§5.7: modifier lifecycle rides the pressed
  // set wherever held state works). Sided identity comes from the position;
  // without one the press is untrackable and is skipped.
  if (_isModifierKey(key)) {
    final twin = position?.usTwin;
    if (twin == null) return null;
    return KeyEvent(twin, type: type, position: position);
  }

  if (_isBrowserTextInputModifiedKey(event, key)) return null;

  final shortcut = event.ctrlKey || event.altKey || event.metaKey;
  if (shortcut && key.length == 1) {
    return KeyEvent(
      KeyCode.forCharacter(_shortcutChar(key)),
      modifiers: _shortcutModifiersFromKeyboard(event),
      type: type,
      position: position,
    );
  }
  if (key.length != 1) return null;

  // An unmodified (or shift-only) printable: the lifecycle key half. Base
  // identity is the lowercase letter (terminal convention: Shift rides the
  // modifier set, the produced character rides the text channel).
  return KeyEvent(
    KeyCode.forCharacter(_shortcutChar(key)),
    modifiers: modifiers,
    type: type,
    position: position,
  );
}

bool _isModifierKey(String key) => switch (key) {
  'Shift' || 'Control' || 'Alt' || 'Meta' || 'AltGraph' => true,
  _ => false,
};

bool _isBrowserPasteAccelerator(
  web.KeyboardEvent event,
  String key,
  KeyCode? keyCode,
) {
  if (keyCode == KeyCode.insert) {
    return event.shiftKey && !event.ctrlKey && !event.altKey && !event.metaKey;
  }
  if (key.length != 1 || key.toLowerCase() != 'v') return false;
  return (event.ctrlKey || event.metaKey) && !event.altKey;
}

bool _isBrowserTextInputModifiedKey(web.KeyboardEvent event, String key) {
  if (key.length != 1) return false;
  if (event.getModifierState('AltGraph')) return true;
  return event.altKey && !event.ctrlKey && !event.metaKey;
}

KeyCode? _keyCodeFor(String key) => switch (key) {
  'Enter' => KeyCode.enter,
  'Tab' => KeyCode.tab,
  'Backspace' => KeyCode.backspace,
  'Escape' || 'Esc' => KeyCode.escape,
  'ArrowUp' || 'Up' => KeyCode.arrowUp,
  'ArrowDown' || 'Down' => KeyCode.arrowDown,
  'ArrowLeft' || 'Left' => KeyCode.arrowLeft,
  'ArrowRight' || 'Right' => KeyCode.arrowRight,
  'Home' => KeyCode.home,
  'End' => KeyCode.end,
  'PageUp' => KeyCode.pageUp,
  'PageDown' => KeyCode.pageDown,
  'Insert' => KeyCode.insert,
  'Delete' || 'Del' => KeyCode.delete,
  'F1' => KeyCode.f1,
  'F2' => KeyCode.f2,
  'F3' => KeyCode.f3,
  'F4' => KeyCode.f4,
  'F5' => KeyCode.f5,
  'F6' => KeyCode.f6,
  'F7' => KeyCode.f7,
  'F8' => KeyCode.f8,
  'F9' => KeyCode.f9,
  'F10' => KeyCode.f10,
  'F11' => KeyCode.f11,
  'F12' => KeyCode.f12,
  _ => null,
};

String _shortcutChar(String key) {
  if (key.length == 1 &&
      key.codeUnitAt(0) >= 0x41 &&
      key.codeUnitAt(0) <= 0x5A) {
    return key.toLowerCase();
  }
  return key;
}

MouseButton _buttonFor(int button) => switch (button) {
  0 => MouseButton.left,
  1 => MouseButton.middle,
  2 => MouseButton.right,
  _ => MouseButton.none,
};

Set<KeyModifier> _modifiersFromKeyboard(web.KeyboardEvent event) => _modifiers(
  shift: event.shiftKey,
  ctrl: event.ctrlKey,
  alt: event.altKey,
  meta: event.metaKey,
);

Set<KeyModifier> _shortcutModifiersFromKeyboard(web.KeyboardEvent event) {
  if (event.metaKey && !event.ctrlKey && !event.altKey) {
    return {KeyModifier.ctrl, if (event.shiftKey) KeyModifier.shift};
  }
  return _modifiersFromKeyboard(event);
}

Set<KeyModifier> _modifiersFromMouse(web.MouseEvent event) => _modifiers(
  shift: event.shiftKey,
  ctrl: event.ctrlKey,
  alt: event.altKey,
  meta: event.metaKey,
);

Set<KeyModifier> _modifiers({
  required bool shift,
  required bool ctrl,
  required bool alt,
  required bool meta,
}) => {
  if (shift) KeyModifier.shift,
  if (ctrl) KeyModifier.ctrl,
  if (alt) KeyModifier.alt,
  if (meta) KeyModifier.superKey,
};

/// The cell-grid link anchor (`<a href>` inside the retained grid root
/// `.fleury-screen`) that [event] targets, or null.
///
/// A click on one of these must navigate **natively** — the browser opens the
/// href — so the input source neither `preventDefault`s it nor routes it as an
/// app pointer event. The semantic-overlay anchors (`a.fleury-semantic-node`,
/// under `.fleury-semantics`) are deliberately excluded: they live off-screen
/// and carry their own click handler, so they never reach here.
web.Element? _cellGridLinkAnchor(web.Event event) {
  final target = event.target;
  if (target == null || !target.isA<web.Element>()) return null;
  final anchor = (target as web.Element).closest('a[href]');
  if (anchor == null) return null;
  return anchor.closest('.fleury-screen') != null ? anchor : null;
}

final class _DomListener {
  const _DomListener(this.target, this.type, this.callback);

  final web.EventTarget target;
  final String type;
  final JSFunction callback;
}

const _caretPlacementAttributeNames = <String>[
  'data-fleury-caret-col',
  'data-fleury-caret-row',
  'data-fleury-caret-width-cells',
  'data-fleury-caret-height-cells',
  'data-fleury-caret-css-left',
  'data-fleury-caret-css-top',
  'data-fleury-caret-css-width',
  'data-fleury-caret-css-height',
];

final class _TextAreaPlacement {
  const _TextAreaPlacement({
    required this.caretRect,
    required this.positioned,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final CellRect? caretRect;
  final bool positioned;
  final double left;
  final double top;
  final double width;
  final double height;
}
