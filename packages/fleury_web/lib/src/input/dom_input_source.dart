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
    web.HTMLTextAreaElement? textArea,
    web.Document? document,
    WebFocusCoordinator? focusCoordinator,
    Clipboard? clipboard,
  }) : _hostElement = hostElement,
       _pointerTarget = pointerTarget ?? hostElement,
       _cellMetrics = cellMetrics,
       _document = document ?? web.document,
       _textArea = textArea,
       _focusCoordinator = focusCoordinator,
       _clipboard = clipboard,
       _ownsTextArea = textArea == null;

  final web.Element _hostElement;
  final web.Element _pointerTarget;
  final CellMetrics _cellMetrics;
  final web.Document _document;
  final web.HTMLTextAreaElement? _textArea;
  final WebFocusCoordinator? _focusCoordinator;
  final Clipboard? _clipboard;
  final bool _ownsTextArea;
  final List<_DomListener> _listeners = [];

  TuiInputSink? _onEvent;
  web.HTMLTextAreaElement? _activeTextArea;
  var _started = false;
  var _appendedTextArea = false;
  var _composing = false;
  String? _lastCompositionText;
  String? _pendingCompositionInput;
  String? _suppressNextInputText;
  MouseButton _pressedButton = MouseButton.none;

  @override
  void start(TuiInputSink onEvent) {
    if (_started) return;
    _started = true;
    _onEvent = onEvent;

    final textArea = _textArea ?? _createTextArea();
    _activeTextArea = textArea;
    if (textArea.parentNode == null) {
      _hostElement.appendChild(textArea);
      _appendedTextArea = true;
    }

    _add(textArea, 'keydown', _handleKeyDown);
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
    _add(_pointerTarget, 'lostpointercapture', _handlePointerCancel);
    _add(_pointerTarget, 'pointermove', _handlePointerMove);
    _add(_pointerTarget, 'wheel', _handleWheel);

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
    _pressedButton = MouseButton.none;
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

  void _handleKeyDown(web.Event raw) {
    final event = raw as web.KeyboardEvent;
    final tuiEvent = keyEventFromBrowser(event);
    if (tuiEvent == null) return;
    raw.preventDefault();
    _emit(tuiEvent);
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
      if (data == suppressNext) {
        raw.preventDefault();
        _clearTextArea();
        return;
      }
    }
    _clearTextArea();
    if (data == null || data.isEmpty) return;
    raw.preventDefault();
    _emit(TextInputEvent(data));
  }

  void _handleCompositionStart(web.Event raw) {
    _composing = true;
    _lastCompositionText = null;
    _pendingCompositionInput = null;
    _suppressNextInputText = null;
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
    _focusCoordinator?.handleBrowserFocusOut(WebFocusTarget.keyboardCapture);
  }

  void _handlePointerDown(web.Event raw) {
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
    final event = raw as web.PointerEvent;
    final button = _buttonFor(event.button);
    final cell = _cellForPointer(event);
    if (button == MouseButton.none || cell == null) return;
    try {
      if (_pointerTarget.hasPointerCapture(event.pointerId)) {
        _pointerTarget.releasePointerCapture(event.pointerId);
      }
    } catch (_) {
      // Best-effort counterpart to pointerdown capture.
    }
    _pressedButton = MouseButton.none;
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
  }

  void _handlePointerMove(web.Event raw) {
    final event = raw as web.PointerEvent;
    final cell = _cellForPointer(event);
    if (cell == null) return;
    final dragging = event.buttons != 0 && _pressedButton != MouseButton.none;
    raw.preventDefault();
    _emit(
      MouseEvent(
        kind: dragging ? MouseEventKind.drag : MouseEventKind.moved,
        button: dragging ? _pressedButton : MouseButton.none,
        col: cell.col,
        row: cell.row,
        modifiers: _modifiersFromMouse(event),
      ),
    );
  }

  void _handleWheel(web.Event raw) {
    final event = raw as web.WheelEvent;
    if (event.deltaY == 0) return;
    final cell = _cellForPointer(event);
    if (cell == null) return;
    raw.preventDefault();
    _emit(
      MouseEvent(
        kind: event.deltaY < 0
            ? MouseEventKind.scrollUp
            : MouseEventKind.scrollDown,
        button: MouseButton.none,
        col: cell.col,
        row: cell.row,
        modifiers: _modifiersFromMouse(event),
      ),
    );
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
    final x = event.clientX - box.cssCanvasLeft;
    final y = event.clientY - box.cssCanvasTop;
    return _cellMetrics.cellForPoint(x, y);
  }
}

/// Maps a browser keydown event to a Fleury key event.
///
/// Printable text without shortcut modifiers is intentionally ignored here; it
/// arrives through the textarea `input` channel as [TextInputEvent].
KeyEvent? keyEventFromBrowser(web.KeyboardEvent event) {
  if (event.isComposing) return null;
  final key = event.key;
  if (key == 'Dead' || key == 'Unidentified' || key.isEmpty) return null;

  final keyCode = _keyCodeFor(key);
  final modifiers = _modifiersFromKeyboard(event);
  final type = event.repeat ? KeyEventType.repeat : KeyEventType.down;
  if (_isBrowserPasteAccelerator(event, key, keyCode)) return null;
  if (keyCode != null) {
    return KeyEvent(keyCode: keyCode, modifiers: modifiers, type: type);
  }

  if (_isBrowserTextInputModifiedKey(event, key)) return null;

  final shortcut = event.ctrlKey || event.altKey || event.metaKey;
  if (!shortcut || key.length != 1) return null;
  return KeyEvent(
    char: _shortcutChar(key),
    modifiers: _shortcutModifiersFromKeyboard(event),
    type: type,
  );
}

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
