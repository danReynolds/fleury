@TestOn('browser')
library;

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:fleury_web/src/input/dom_input_source.dart';
import 'package:fleury_web/src/metrics/cell_metrics.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  group('keyEventFromBrowser', () {
    test('maps navigation and shortcut keys', () {
      expect(
        keyEventFromBrowser(
          web.KeyboardEvent(
            'keydown',
            web.KeyboardEventInit(key: 'ArrowLeft', shiftKey: true),
          ),
        ),
        const KeyEvent(KeyCode.arrowLeft, modifiers: {KeyModifier.shift}),
      );

      expect(
        keyEventFromBrowser(
          web.KeyboardEvent(
            'keydown',
            web.KeyboardEventInit(
              key: 'S',
              ctrlKey: true,
              shiftKey: true,
              repeat: true,
            ),
          ),
        ),
        const KeyEvent(
          KeyCode.char('s'),
          modifiers: {KeyModifier.ctrl, KeyModifier.shift},
          type: KeyEventType.repeat,
        ),
      );
    });

    test('a plain printable is the lifecycle key half (text still rides '
        'the input channel)', () {
      // RFC 0020 P3: printables emit key events for held-state tracking;
      // committed text arrives separately and the dispatcher keeps the
      // unmodified key half out of the command lane.
      expect(
        keyEventFromBrowser(
          web.KeyboardEvent(
            'keydown',
            web.KeyboardEventInit(key: 'a', code: 'KeyA'),
          ),
        ),
        const KeyEvent(KeyCode.char('a'), position: KeyPosition.a),
      );
    });

    group('RFC 0020 lifecycle mapping', () {
      test('positions ride every mapped event; Unidentified stays null', () {
        expect(
          keyEventFromBrowser(
            web.KeyboardEvent(
              'keydown',
              web.KeyboardEventInit(key: 'z', code: 'KeyW'),
            ),
          ),
          // AZERTY: the QWERTY-W spot types 'z'.
          const KeyEvent(KeyCode.char('z'), position: KeyPosition.w),
        );
        expect(
          keyEventFromBrowser(
            web.KeyboardEvent(
              'keydown',
              web.KeyboardEventInit(key: 'ArrowUp', code: 'ArrowUp'),
            ),
          ),
          const KeyEvent(KeyCode.arrowUp, position: KeyPosition.arrowUp),
        );
        expect(
          keyEventFromBrowser(
            web.KeyboardEvent(
              'keydown',
              web.KeyboardEventInit(key: 'q', code: 'Unidentified'),
            ),
          ),
          const KeyEvent(KeyCode.char('q')),
        );
      });

      test('shifted printables carry the base letter plus the modifier', () {
        expect(
          keyEventFromBrowser(
            web.KeyboardEvent(
              'keydown',
              web.KeyboardEventInit(key: 'A', code: 'KeyA', shiftKey: true),
            ),
          ),
          const KeyEvent(
            KeyCode.char('a'),
            modifiers: {KeyModifier.shift},
            position: KeyPosition.a,
          ),
        );
      });

      test('shifted punctuation keeps produced text and physical position', () {
        expect(
          keyEventFromBrowser(
            web.KeyboardEvent(
              'keydown',
              web.KeyboardEventInit(key: r'$', code: 'Digit4', shiftKey: true),
            ),
          ),
          const KeyEvent(
            KeyCode.char(r'$'),
            modifiers: {KeyModifier.shift},
            position: KeyPosition.digit4,
          ),
        );
      });

      test('lone modifier keys are sided keys via their position', () {
        expect(
          keyEventFromBrowser(
            web.KeyboardEvent(
              'keydown',
              web.KeyboardEventInit(
                key: 'Shift',
                code: 'ShiftLeft',
                shiftKey: true,
              ),
            ),
          ),
          const KeyEvent(KeyCode.leftShift, position: KeyPosition.shiftLeft),
        );
        // No position → no sided identity → untrackable, skipped.
        expect(
          keyEventFromBrowser(
            web.KeyboardEvent(
              'keydown',
              web.KeyboardEventInit(key: 'Shift', code: ''),
            ),
          ),
          isNull,
        );
      });
    });

    test('normalizes Meta printable shortcuts to Fleury Ctrl shortcuts', () {
      expect(
        keyEventFromBrowser(
          web.KeyboardEvent(
            'keydown',
            web.KeyboardEventInit(key: 'z', metaKey: true),
          ),
        ),
        const KeyEvent(KeyCode.char('z'), modifiers: {KeyModifier.ctrl}),
      );
      expect(
        keyEventFromBrowser(
          web.KeyboardEvent(
            'keydown',
            web.KeyboardEventInit(key: 'Z', metaKey: true, shiftKey: true),
          ),
        ),
        const KeyEvent(
          KeyCode.char('z'),
          modifiers: {KeyModifier.ctrl, KeyModifier.shift},
        ),
      );
    });

    test('leaves AltGraph printable text to the input channel', () {
      final event = web.KeyboardEvent(
        'keydown',
        web.KeyboardEventInit(
          key: '@',
          ctrlKey: true,
          altKey: true,
          modifierAltGraph: true,
        ),
      );

      expect(event.getModifierState('AltGraph'), isTrue);
      expect(keyEventFromBrowser(event), isNull);
    });

    test('leaves Alt-only printable text to the input channel', () {
      expect(
        keyEventFromBrowser(
          web.KeyboardEvent(
            'keydown',
            web.KeyboardEventInit(key: 'å', altKey: true),
          ),
        ),
        isNull,
      );
    });

    test('leaves browser paste accelerators to the paste event', () {
      expect(
        keyEventFromBrowser(
          web.KeyboardEvent(
            'keydown',
            web.KeyboardEventInit(key: 'v', ctrlKey: true),
          ),
        ),
        isNull,
      );
      expect(
        keyEventFromBrowser(
          web.KeyboardEvent(
            'keydown',
            web.KeyboardEventInit(key: 'V', metaKey: true),
          ),
        ),
        isNull,
      );
      expect(
        keyEventFromBrowser(
          web.KeyboardEvent(
            'keydown',
            web.KeyboardEventInit(key: 'Insert', shiftKey: true),
          ),
        ),
        isNull,
      );
    });
  });

  test('a text-producing keydown keeps the browser default so the input '
      'channel still fires', () {
    // The regression this pins is invisible to trace fixtures, which
    // dispatch `keydown` and `input` as independent synthetic events: in a
    // REAL browser, preventDefault() on a printable keydown suppresses the
    // character insertion, the `input` event, and therefore all typing.
    // RFC 0020 §11: the source emits the key half for lifecycle tracking
    // but must leave text to the input channel.
    final events = <TuiEvent>[];
    final host = web.document.createElement('div');
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    web.document.body!.appendChild(host);
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      cellMetrics: _FakeMetrics(
        const MeasuredCellBox(
          cssCellWidth: 10,
          cssCellHeight: 20,
          cssCanvasWidth: 80,
          cssCanvasHeight: 60,
          cssCanvasLeft: 10,
          cssCanvasTop: 20,
          devicePixelRatio: 1,
          cols: 8,
          rows: 3,
        ),
      ),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
    });
    source.start(events.add);

    web.KeyboardEvent keydown(
      String key, {
      String code = '',
      bool ctrlKey = false,
      bool shiftKey = false,
    }) => web.KeyboardEvent(
      'keydown',
      web.KeyboardEventInit(
        key: key,
        code: code,
        ctrlKey: ctrlKey,
        shiftKey: shiftKey,
        bubbles: true,
        cancelable: true,
      ),
    );

    final plain = keydown('a', code: 'KeyA');
    textArea.dispatchEvent(plain);
    expect(
      plain.defaultPrevented,
      isFalse,
      reason: 'a plain printable must reach the textarea to produce `input`',
    );

    final shifted = keydown('A', code: 'KeyA', shiftKey: true);
    textArea.dispatchEvent(shifted);
    expect(shifted.defaultPrevented, isFalse, reason: 'Shift is still text');

    // Ours: chords and special keys never reach the textarea.
    final chord = keydown('s', code: 'KeyS', ctrlKey: true);
    textArea.dispatchEvent(chord);
    expect(chord.defaultPrevented, isTrue);

    final special = keydown('ArrowLeft', code: 'ArrowLeft');
    textArea.dispatchEvent(special);
    expect(special.defaultPrevented, isTrue);

    // The key halves were still emitted for lifecycle tracking.
    expect(events.whereType<KeyEvent>().map((e) => e.code).toList(), const [
      KeyCode.char('a'),
      KeyCode.char('a'),
      KeyCode.char('s'),
      KeyCode.arrowLeft,
    ]);
  });

  test('DomInputSource emits keyboard, composition, text, paste, pointer, and '
      'wheel events', () {
    final events = <TuiEvent>[];
    final host = web.document.createElement('div');
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    web.document.body!.appendChild(host);
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      cellMetrics: _FakeMetrics(
        const MeasuredCellBox(
          cssCellWidth: 10,
          cssCellHeight: 20,
          cssCanvasWidth: 80,
          cssCanvasHeight: 60,
          cssCanvasLeft: 10,
          cssCanvasTop: 20,
          devicePixelRatio: 1,
          cols: 8,
          rows: 3,
        ),
      ),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
    });

    source.start(events.add);

    textArea.dispatchEvent(
      web.KeyboardEvent(
        'keydown',
        web.KeyboardEventInit(key: 'Enter', bubbles: true, cancelable: true),
      ),
    );
    textArea.dispatchEvent(
      web.CompositionEvent(
        'compositionstart',
        web.CompositionEventInit(bubbles: true, cancelable: true),
      ),
    );
    textArea.dispatchEvent(
      web.CompositionEvent(
        'compositionupdate',
        web.CompositionEventInit(data: 'é', bubbles: true, cancelable: true),
      ),
    );
    textArea.dispatchEvent(
      web.CompositionEvent(
        'compositionend',
        web.CompositionEventInit(data: 'é', bubbles: true, cancelable: true),
      ),
    );
    textArea.dispatchEvent(
      web.InputEvent(
        'input',
        web.InputEventInit(
          data: 'é',
          inputType: 'insertText',
          bubbles: true,
          cancelable: true,
        ),
      ),
    );
    textArea.dispatchEvent(
      web.InputEvent(
        'input',
        web.InputEventInit(
          data: 'x',
          inputType: 'insertText',
          bubbles: true,
          cancelable: true,
        ),
      ),
    );
    final clipboardData = web.DataTransfer()..setData('text/plain', 'a\nb');
    textArea.dispatchEvent(
      web.ClipboardEvent(
        'paste',
        web.ClipboardEventInit(
          clipboardData: clipboardData,
          bubbles: true,
          cancelable: true,
        ),
      ),
    );
    host.dispatchEvent(
      web.PointerEvent(
        'pointerdown',
        web.PointerEventInit(
          pointerId: 1,
          clientX: 25,
          clientY: 65,
          button: 0,
          buttons: 1,
          bubbles: true,
          cancelable: true,
        ),
      ),
    );
    host.dispatchEvent(
      web.PointerEvent(
        'pointermove',
        web.PointerEventInit(
          pointerId: 1,
          clientX: 35,
          clientY: 45,
          button: 0,
          buttons: 1,
          bubbles: true,
          cancelable: true,
        ),
      ),
    );
    host.dispatchEvent(
      web.WheelEvent(
        'wheel',
        web.WheelEventInit(
          clientX: 15,
          clientY: 25,
          // One cell height (cssCellHeight: 20) of travel = one scroll step;
          // smaller deltas accumulate, so a trackpad's many tiny events don't
          // each scroll a row.
          deltaY: -20,
          bubbles: true,
          cancelable: true,
        ),
      ),
    );

    expect(events, [
      const KeyEvent(KeyCode.enter),
      const TextCompositionEvent.update('é'),
      const TextCompositionEvent.commit('é'),
      const TextInputEvent('x'),
      const PasteEvent('a\nb'),
      const MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: 1,
        row: 2,
      ),
      const MouseEvent(
        kind: MouseEventKind.drag,
        button: MouseButton.left,
        col: 2,
        row: 1,
      ),
      const MouseEvent(
        kind: MouseEventKind.scrollUp,
        button: MouseButton.none,
        col: 0,
        row: 0,
      ),
    ]);
    expect(textArea.value, isEmpty);
  });

  test(
    'DomInputSource closes the original press when pointerup is missing',
    () {
      final events = <TuiEvent>[];
      final host = web.document.createElement('div');
      final textArea =
          web.document.createElement('textarea') as web.HTMLTextAreaElement;
      web.document.body!.appendChild(host);
      final source = DomInputSource(
        hostElement: host,
        textArea: textArea,
        cellMetrics: _FakeMetrics(
          const MeasuredCellBox(
            cssCellWidth: 10,
            cssCellHeight: 20,
            cssCanvasWidth: 80,
            cssCanvasHeight: 60,
            cssCanvasLeft: 10,
            cssCanvasTop: 20,
            devicePixelRatio: 1,
            cols: 8,
            rows: 3,
          ),
        ),
      );
      addTearDown(() {
        source.dispose();
        host.parentNode?.removeChild(host);
      });

      source.start(events.add);

      host.dispatchEvent(
        web.PointerEvent(
          'pointerdown',
          web.PointerEventInit(
            pointerId: 1,
            clientX: 25,
            clientY: 65,
            button: 0,
            buttons: 1,
            bubbles: true,
            cancelable: true,
          ),
        ),
      );
      host.dispatchEvent(
        web.PointerEvent(
          'lostpointercapture',
          web.PointerEventInit(
            pointerId: 1,
            clientX: 25,
            clientY: 65,
            button: -1,
            buttons: 0,
            bubbles: true,
          ),
        ),
      );
      host.dispatchEvent(
        web.MouseEvent(
          'click',
          web.MouseEventInit(
            clientX: 25,
            clientY: 65,
            button: 0,
            bubbles: true,
            cancelable: true,
          ),
        ),
      );

      expect(events, [
        const MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: 1,
          row: 2,
        ),
        const MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: 1,
          row: 2,
        ),
      ]);
    },
  );

  test('DomInputSource synthesizes a full tap from click-only input', () {
    final events = <TuiEvent>[];
    final host = web.document.createElement('div');
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    web.document.body!.appendChild(host);
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      cellMetrics: _FakeMetrics(
        const MeasuredCellBox(
          cssCellWidth: 10,
          cssCellHeight: 20,
          cssCanvasWidth: 80,
          cssCanvasHeight: 60,
          cssCanvasLeft: 10,
          cssCanvasTop: 20,
          devicePixelRatio: 1,
          cols: 8,
          rows: 3,
        ),
      ),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
    });

    source.start(events.add);

    host.dispatchEvent(
      web.MouseEvent(
        'click',
        web.MouseEventInit(
          clientX: 25,
          clientY: 65,
          button: 0,
          detail: 1,
          bubbles: true,
          cancelable: true,
        ),
      ),
    );

    expect(events, [
      const MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: 1,
        row: 2,
      ),
      const MouseEvent(
        kind: MouseEventKind.up,
        button: MouseButton.left,
        col: 1,
        row: 2,
      ),
    ]);
  });

  test('DomInputSource ignores click fallback after normal pointerup', () {
    final events = <TuiEvent>[];
    final host = web.document.createElement('div');
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    web.document.body!.appendChild(host);
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      cellMetrics: _FakeMetrics(
        const MeasuredCellBox(
          cssCellWidth: 10,
          cssCellHeight: 20,
          cssCanvasWidth: 80,
          cssCanvasHeight: 60,
          cssCanvasLeft: 10,
          cssCanvasTop: 20,
          devicePixelRatio: 1,
          cols: 8,
          rows: 3,
        ),
      ),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
    });

    source.start(events.add);

    host.dispatchEvent(
      web.PointerEvent(
        'pointerdown',
        web.PointerEventInit(
          pointerId: 1,
          clientX: 25,
          clientY: 65,
          button: 0,
          buttons: 1,
          bubbles: true,
          cancelable: true,
        ),
      ),
    );
    host.dispatchEvent(
      web.PointerEvent(
        'pointerup',
        web.PointerEventInit(
          pointerId: 1,
          clientX: 25,
          clientY: 65,
          button: -1,
          buttons: 0,
          bubbles: true,
          cancelable: true,
        ),
      ),
    );
    host.dispatchEvent(
      web.MouseEvent(
        'click',
        web.MouseEventInit(
          clientX: 25,
          clientY: 65,
          button: 0,
          detail: 1,
          bubbles: true,
          cancelable: true,
        ),
      ),
    );

    expect(events, [
      const MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: 1,
        row: 2,
      ),
      const MouseEvent(
        kind: MouseEventKind.up,
        button: MouseButton.left,
        col: 1,
        row: 2,
      ),
    ]);
  });

  test(
    'DomInputSource keeps click suppression through lost pointer capture',
    () {
      final events = <TuiEvent>[];
      final host = web.document.createElement('div');
      final textArea =
          web.document.createElement('textarea') as web.HTMLTextAreaElement;
      web.document.body!.appendChild(host);
      final source = DomInputSource(
        hostElement: host,
        textArea: textArea,
        cellMetrics: _FakeMetrics(
          const MeasuredCellBox(
            cssCellWidth: 10,
            cssCellHeight: 20,
            cssCanvasWidth: 80,
            cssCanvasHeight: 60,
            cssCanvasLeft: 10,
            cssCanvasTop: 20,
            devicePixelRatio: 1,
            cols: 8,
            rows: 3,
          ),
        ),
      );
      addTearDown(() {
        source.dispose();
        host.parentNode?.removeChild(host);
      });

      source.start(events.add);

      host.dispatchEvent(
        web.PointerEvent(
          'pointerdown',
          web.PointerEventInit(
            pointerId: 1,
            clientX: 25,
            clientY: 65,
            button: 0,
            buttons: 1,
            bubbles: true,
            cancelable: true,
          ),
        ),
      );
      host.dispatchEvent(
        web.PointerEvent(
          'pointerup',
          web.PointerEventInit(
            pointerId: 1,
            clientX: 25,
            clientY: 65,
            button: -1,
            buttons: 0,
            bubbles: true,
            cancelable: true,
          ),
        ),
      );
      host.dispatchEvent(
        web.PointerEvent(
          'lostpointercapture',
          web.PointerEventInit(
            pointerId: 1,
            clientX: 25,
            clientY: 65,
            button: -1,
            buttons: 0,
            bubbles: true,
          ),
        ),
      );
      host.dispatchEvent(
        web.MouseEvent(
          'click',
          web.MouseEventInit(
            // A render between pointerup and click may move the painted
            // control under the browser's compatibility click. It is still
            // the same physical gesture and must not synthesize another tap.
            clientX: 35,
            clientY: 65,
            button: 0,
            detail: 1,
            bubbles: true,
            cancelable: true,
          ),
        ),
      );

      expect(events, [
        const MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: 1,
          row: 2,
        ),
        const MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: 1,
          row: 2,
        ),
      ]);
    },
  );

  test(
    'DomInputSource uses in-process clipboard when paste data is missing',
    () {
      final events = <TuiEvent>[];
      final host = web.document.createElement('div');
      final textArea =
          web.document.createElement('textarea') as web.HTMLTextAreaElement;
      final clipboard = _FakeClipboard('fallback\npaste');
      web.document.body!.appendChild(host);
      final source = DomInputSource(
        hostElement: host,
        textArea: textArea,
        cellMetrics: _FakeMetrics(
          const MeasuredCellBox(
            cssCellWidth: 10,
            cssCellHeight: 20,
            cssCanvasWidth: 80,
            cssCanvasHeight: 60,
            devicePixelRatio: 1,
            cols: 8,
            rows: 3,
          ),
        ),
        clipboard: clipboard,
      );
      addTearDown(() {
        source.dispose();
        host.parentNode?.removeChild(host);
      });

      source.start(events.add);
      textArea.value = 'browser residue';

      final event = web.ClipboardEvent(
        'paste',
        web.ClipboardEventInit(bubbles: true, cancelable: true),
      );
      textArea.dispatchEvent(event);

      expect(event.defaultPrevented, isTrue);
      expect(events, [const PasteEvent('fallback\npaste')]);
      expect(textArea.value, isEmpty);
    },
  );

  test(
    'DomInputSource does not replace empty event paste with fallback text',
    () {
      final events = <TuiEvent>[];
      final host = web.document.createElement('div');
      final textArea =
          web.document.createElement('textarea') as web.HTMLTextAreaElement;
      final clipboard = _FakeClipboard('stale fallback');
      final clipboardData = web.DataTransfer();
      web.document.body!.appendChild(host);
      final source = DomInputSource(
        hostElement: host,
        textArea: textArea,
        cellMetrics: _FakeMetrics(
          const MeasuredCellBox(
            cssCellWidth: 10,
            cssCellHeight: 20,
            cssCanvasWidth: 80,
            cssCanvasHeight: 60,
            devicePixelRatio: 1,
            cols: 8,
            rows: 3,
          ),
        ),
        clipboard: clipboard,
      );
      addTearDown(() {
        source.dispose();
        host.parentNode?.removeChild(host);
      });

      source.start(events.add);

      final event = web.ClipboardEvent(
        'paste',
        web.ClipboardEventInit(
          clipboardData: clipboardData,
          bubbles: true,
          cancelable: true,
        ),
      );
      textArea.dispatchEvent(event);

      expect(event.defaultPrevented, isFalse);
      expect(events, isEmpty);
    },
  );

  test('DomInputSource clears standalone paste input residue', () {
    final events = <TuiEvent>[];
    final host = web.document.createElement('div');
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    web.document.body!.appendChild(host);
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      cellMetrics: _FakeMetrics(
        const MeasuredCellBox(
          cssCellWidth: 10,
          cssCellHeight: 20,
          cssCanvasWidth: 80,
          cssCanvasHeight: 60,
          devicePixelRatio: 1,
          cols: 8,
          rows: 3,
        ),
      ),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
    });

    source.start(events.add);
    textArea.value = 'browser paste residue';

    final event = web.InputEvent(
      'input',
      web.InputEventInit(
        data: 'browser paste residue',
        inputType: 'insertFromPaste',
        bubbles: true,
        cancelable: true,
      ),
    );
    textArea.dispatchEvent(event);

    expect(event.defaultPrevented, isTrue);
    expect(textArea.value, isEmpty);
    expect(events, isEmpty);
  });

  test('DomInputSource restores keyboard capture on pointer down', () {
    final events = <TuiEvent>[];
    final host = web.document.createElement('div');
    final semantic = web.document.createElement('div') as web.HTMLElement;
    semantic.className = 'fleury-semantic-node';
    semantic.setAttribute('tabindex', '-1');
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    final focusCoordinator = WebFocusCoordinator();
    web.document.body!.appendChild(host);
    web.document.body!.appendChild(semantic);
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      focusCoordinator: focusCoordinator,
      cellMetrics: _FakeMetrics(
        const MeasuredCellBox(
          cssCellWidth: 10,
          cssCellHeight: 20,
          cssCanvasWidth: 80,
          cssCanvasHeight: 60,
          devicePixelRatio: 1,
          cols: 8,
          rows: 3,
        ),
      ),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
      semantic.parentNode?.removeChild(semantic);
    });

    source.start(events.add);
    expect(web.document.activeElement, same(textArea));
    expect(focusCoordinator.browserFocusTarget, WebFocusTarget.keyboardCapture);

    semantic.focus();
    expect(web.document.activeElement, same(semantic));
    expect(focusCoordinator.browserFocusTarget, isNull);

    host.dispatchEvent(
      web.PointerEvent(
        'pointerdown',
        web.PointerEventInit(
          pointerId: 2,
          clientX: 15,
          clientY: 25,
          button: 0,
          buttons: 1,
          bubbles: true,
          cancelable: true,
        ),
      ),
    );

    expect(web.document.activeElement, same(textArea));
    expect(focusCoordinator.browserFocusTarget, WebFocusTarget.keyboardCapture);
    expect(events, isNotEmpty);
  });

  test('DomInputSource restores capture after focus leaves the grid', () {
    final host = web.document.createElement('div');
    final overlay = web.document.createElement('div') as web.HTMLElement;
    overlay.setAttribute('tabindex', '-1');
    overlay.textContent = 'connecting…';
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    final focusCoordinator = WebFocusCoordinator();
    web.document.body!.appendChild(host);
    web.document.body!.appendChild(overlay);
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      focusCoordinator: focusCoordinator,
      cellMetrics: _FakeMetrics(
        const MeasuredCellBox(
          cssCellWidth: 10,
          cssCellHeight: 20,
          cssCanvasWidth: 80,
          cssCanvasHeight: 60,
          devicePixelRatio: 1,
          cols: 8,
          rows: 3,
        ),
      ),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
      overlay.parentNode?.removeChild(overlay);
    });

    source.start((_) {});
    expect(web.document.activeElement, same(textArea));

    overlay.focus();
    expect(
      web.document.activeElement,
      same(textArea),
      reason: 'focus outside the grid returns to the hidden textarea',
    );
    expect(focusCoordinator.browserFocusTarget, WebFocusTarget.keyboardCapture);
  });

  test('DomInputSource does not steal focus from a semantic AT target', () {
    final host = web.document.createElement('div');
    final semantic = web.document.createElement('div') as web.HTMLElement;
    semantic.className = 'fleury-semantic-node';
    semantic.setAttribute('data-fleury-semantic-id', 'run');
    semantic.setAttribute('tabindex', '-1');
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    web.document.body!.appendChild(host);
    web.document.body!.appendChild(semantic);
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      cellMetrics: _FakeMetrics(
        const MeasuredCellBox(
          cssCellWidth: 10,
          cssCellHeight: 20,
          cssCanvasWidth: 80,
          cssCanvasHeight: 60,
          devicePixelRatio: 1,
          cols: 8,
          rows: 3,
        ),
      ),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
      semantic.parentNode?.removeChild(semantic);
    });

    source.start((_) {});
    semantic.focus();
    expect(
      web.document.activeElement,
      same(semantic),
      reason: 'AT/semantic nodes keep browser focus',
    );
  });

  test('DomInputSource clears injected textarea at start and dispose', () {
    final host = web.document.createElement('div');
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      cellMetrics: _FakeMetrics(
        const MeasuredCellBox(
          cssCellWidth: 10,
          cssCellHeight: 20,
          cssCanvasWidth: 80,
          cssCanvasHeight: 60,
          devicePixelRatio: 1,
          cols: 8,
          rows: 3,
        ),
      ),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
    });

    web.document.body!.appendChild(host);
    host.appendChild(textArea);
    textArea.value = 'stale before start';

    source.start((_) {});

    expect(textArea.parentNode, same(host));
    expect(textArea.value, isEmpty);

    textArea.value = 'stale before dispose';
    source.dispose();

    expect(textArea.parentNode, same(host));
    expect(textArea.value, isEmpty);
  });

  test('DomInputSource clears keyboard capture focus on dispose', () {
    final host = web.document.createElement('div');
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    final focusCoordinator = WebFocusCoordinator();
    web.document.body!.appendChild(host);
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      focusCoordinator: focusCoordinator,
      cellMetrics: _FakeMetrics(
        const MeasuredCellBox(
          cssCellWidth: 10,
          cssCellHeight: 20,
          cssCanvasWidth: 80,
          cssCanvasHeight: 60,
          devicePixelRatio: 1,
          cols: 8,
          rows: 3,
        ),
      ),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
    });

    source.start((_) {});
    expect(focusCoordinator.browserFocusTarget, WebFocusTarget.keyboardCapture);

    source.dispose();

    expect(focusCoordinator.browserFocusTarget, isNull);
  });

  test('DomInputSource clears drag state on pointer cancellation', () {
    final events = <TuiEvent>[];
    final host = web.document.createElement('div');
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    web.document.body!.appendChild(host);
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      cellMetrics: _FakeMetrics(
        const MeasuredCellBox(
          cssCellWidth: 10,
          cssCellHeight: 20,
          cssCanvasWidth: 80,
          cssCanvasHeight: 60,
          cssCanvasLeft: 10,
          cssCanvasTop: 20,
          devicePixelRatio: 1,
          cols: 8,
          rows: 3,
        ),
      ),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
    });

    source.start(events.add);

    host.dispatchEvent(
      web.PointerEvent(
        'pointerdown',
        web.PointerEventInit(
          pointerId: 1,
          clientX: 25,
          clientY: 45,
          button: 0,
          buttons: 1,
          bubbles: true,
          cancelable: true,
        ),
      ),
    );
    host.dispatchEvent(
      web.PointerEvent(
        'lostpointercapture',
        web.PointerEventInit(pointerId: 1, bubbles: true, cancelable: true),
      ),
    );
    host.dispatchEvent(
      web.PointerEvent(
        'pointermove',
        web.PointerEventInit(
          pointerId: 1,
          clientX: 35,
          clientY: 65,
          button: 0,
          buttons: 1,
          bubbles: true,
          cancelable: true,
        ),
      ),
    );
    host.dispatchEvent(
      web.PointerEvent(
        'pointerdown',
        web.PointerEventInit(
          pointerId: 2,
          clientX: 25,
          clientY: 45,
          button: 0,
          buttons: 1,
          bubbles: true,
          cancelable: true,
        ),
      ),
    );
    host.dispatchEvent(
      web.PointerEvent(
        'pointercancel',
        web.PointerEventInit(pointerId: 2, bubbles: true, cancelable: true),
      ),
    );
    host.dispatchEvent(
      web.PointerEvent(
        'pointermove',
        web.PointerEventInit(
          pointerId: 2,
          clientX: 45,
          clientY: 65,
          button: 0,
          buttons: 1,
          bubbles: true,
          cancelable: true,
        ),
      ),
    );

    expect(events, [
      const MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: 1,
        row: 1,
      ),
      const MouseEvent(
        kind: MouseEventKind.moved,
        button: MouseButton.none,
        col: 2,
        row: 2,
      ),
      const MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: 1,
        row: 1,
      ),
      const MouseEvent(
        kind: MouseEventKind.moved,
        button: MouseButton.none,
        col: 3,
        row: 2,
      ),
    ]);
  });

  test('DomInputSource coalesces identical pointer moves', () {
    final events = <TuiEvent>[];
    final host = web.document.createElement('div');
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    web.document.body!.appendChild(host);
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      cellMetrics: _FakeMetrics(
        const MeasuredCellBox(
          cssCellWidth: 10,
          cssCellHeight: 20,
          cssCanvasWidth: 80,
          cssCanvasHeight: 60,
          cssCanvasLeft: 10,
          cssCanvasTop: 20,
          devicePixelRatio: 1,
          cols: 8,
          rows: 3,
        ),
      ),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
    });
    source.start(events.add);

    web.PointerEvent move(int clientX, int clientY) => web.PointerEvent(
      'pointermove',
      web.PointerEventInit(
        clientX: clientX,
        clientY: clientY,
        bubbles: true,
        cancelable: true,
      ),
    );

    host.dispatchEvent(move(25, 45));
    host.dispatchEvent(move(26, 46));
    host.dispatchEvent(move(35, 45));

    expect(events, [
      const MouseEvent(
        kind: MouseEventKind.moved,
        button: MouseButton.none,
        col: 1,
        row: 1,
      ),
      const MouseEvent(
        kind: MouseEventKind.moved,
        button: MouseButton.none,
        col: 2,
        row: 1,
      ),
    ]);
  });

  test('DomInputSource leaves ctrl and meta wheel to the browser', () {
    final events = <TuiEvent>[];
    final host = web.document.createElement('div');
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    web.document.body!.appendChild(host);
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      cellMetrics: _FakeMetrics(
        const MeasuredCellBox(
          cssCellWidth: 10,
          cssCellHeight: 20,
          cssCanvasWidth: 80,
          cssCanvasHeight: 60,
          cssCanvasLeft: 10,
          cssCanvasTop: 20,
          devicePixelRatio: 1,
          cols: 8,
          rows: 3,
        ),
      ),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
    });
    source.start(events.add);

    final ctrlWheel = web.WheelEvent(
      'wheel',
      web.WheelEventInit(
        clientX: 15,
        clientY: 25,
        deltaY: -20,
        ctrlKey: true,
        bubbles: true,
        cancelable: true,
      ),
    );
    host.dispatchEvent(ctrlWheel);
    expect(ctrlWheel.defaultPrevented, isFalse, reason: 'browser zoom');
    expect(events, isEmpty);

    final metaWheel = web.WheelEvent(
      'wheel',
      web.WheelEventInit(
        clientX: 15,
        clientY: 25,
        deltaY: 20,
        metaKey: true,
        bubbles: true,
        cancelable: true,
      ),
    );
    host.dispatchEvent(metaWheel);
    expect(metaWheel.defaultPrevented, isFalse, reason: 'browser zoom');
    expect(events, isEmpty);
  });

  test('DomInputSource shows a hand cursor over semantic click targets', () {
    final host = web.document.createElement('div') as web.HTMLElement;
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    host.style.setProperty('cursor', 'crosshair');
    web.document.body!.appendChild(host);
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      cellMetrics: _FakeMetrics(
        const MeasuredCellBox(
          cssCellWidth: 10,
          cssCellHeight: 20,
          cssCanvasWidth: 80,
          cssCanvasHeight: 60,
          cssCanvasLeft: 10,
          cssCanvasTop: 20,
          devicePixelRatio: 1,
          cols: 8,
          rows: 3,
        ),
      ),
      pointerCursorResolver: (cell) => cell == const CellOffset(1, 1),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
    });

    source.start((_) {});
    host.dispatchEvent(
      web.PointerEvent(
        'pointermove',
        web.PointerEventInit(
          clientX: 25,
          clientY: 45,
          bubbles: true,
          cancelable: true,
        ),
      ),
    );
    expect(host.style.getPropertyValue('cursor'), 'pointer');

    host.dispatchEvent(
      web.PointerEvent(
        'pointermove',
        web.PointerEventInit(
          clientX: 45,
          clientY: 45,
          bubbles: true,
          cancelable: true,
        ),
      ),
    );
    expect(host.style.getPropertyValue('cursor'), 'crosshair');

    source.dispose();
    expect(host.style.getPropertyValue('cursor'), 'crosshair');
  });

  test('DomInputSource delegates viewport coordinates to CellMetrics', () {
    final events = <TuiEvent>[];
    final host = web.document.createElement('div');
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    final metrics = _RecordingMetrics(
      const MeasuredCellBox(
        cssCellWidth: 10,
        cssCellHeight: 20,
        cssCanvasWidth: 80,
        cssCanvasHeight: 60,
        cssCanvasLeft: 12,
        cssCanvasTop: 30,
        devicePixelRatio: 1,
        cols: 8,
        rows: 3,
      ),
      mappedCell: const CellOffset(6, 2),
    );
    web.document.body!.appendChild(host);
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      cellMetrics: metrics,
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
    });

    source.start(events.add);

    host.dispatchEvent(
      web.PointerEvent(
        'pointerdown',
        web.PointerEventInit(
          pointerId: 7,
          clientX: 45,
          clientY: 95,
          button: 0,
          buttons: 1,
          bubbles: true,
          cancelable: true,
        ),
      ),
    );

    expect(metrics.pointCalls, 1);
    expect(metrics.lastClientX, 45);
    expect(metrics.lastClientY, 95);
    expect(events, [
      const MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: 6,
        row: 2,
      ),
    ]);
  });

  test('DomInputSource emits composition cancel without committed text', () {
    final events = <TuiEvent>[];
    final host = web.document.createElement('div');
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    web.document.body!.appendChild(host);
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      cellMetrics: _FakeMetrics(
        const MeasuredCellBox(
          cssCellWidth: 10,
          cssCellHeight: 20,
          cssCanvasWidth: 80,
          cssCanvasHeight: 60,
          devicePixelRatio: 1,
          cols: 8,
          rows: 3,
        ),
      ),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
    });

    source.start(events.add);

    textArea.dispatchEvent(
      web.CompositionEvent(
        'compositionstart',
        web.CompositionEventInit(bubbles: true, cancelable: true),
      ),
    );
    textArea.dispatchEvent(
      web.CompositionEvent(
        'compositionupdate',
        web.CompositionEventInit(data: 'あ', bubbles: true, cancelable: true),
      ),
    );
    textArea.dispatchEvent(
      web.CompositionEvent(
        'compositionend',
        web.CompositionEventInit(bubbles: true, cancelable: true),
      ),
    );

    expect(events, [
      const TextCompositionEvent.update('あ'),
      const TextCompositionEvent.cancel(),
    ]);
  });

  test('DomInputSource expires duplicate suppression when composition has no '
      'trailing input event', () async {
    final events = <TuiEvent>[];
    final host = web.document.createElement('div');
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    web.document.body!.appendChild(host);
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      cellMetrics: _FakeMetrics(
        const MeasuredCellBox(
          cssCellWidth: 10,
          cssCellHeight: 20,
          cssCanvasWidth: 80,
          cssCanvasHeight: 60,
          devicePixelRatio: 1,
          cols: 8,
          rows: 3,
        ),
      ),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
    });

    source.start(events.add);
    textArea.dispatchEvent(
      web.CompositionEvent(
        'compositionstart',
        web.CompositionEventInit(bubbles: true, cancelable: true),
      ),
    );
    textArea.dispatchEvent(
      web.CompositionEvent(
        'compositionupdate',
        web.CompositionEventInit(data: 'あ', bubbles: true, cancelable: true),
      ),
    );
    textArea.dispatchEvent(
      web.CompositionEvent(
        'compositionend',
        web.CompositionEventInit(data: 'あ', bubbles: true, cancelable: true),
      ),
    );

    // This valid browser sequence has no duplicate input after compositionend.
    // Move to the next event task, then type the same character normally: it
    // is user input, not the absent composition echo, and must not be dropped.
    await Future<void>.delayed(Duration.zero);
    textArea.dispatchEvent(
      web.InputEvent(
        'input',
        web.InputEventInit(
          data: 'あ',
          inputType: 'insertText',
          bubbles: true,
          cancelable: true,
        ),
      ),
    );

    expect(events, [
      const TextCompositionEvent.update('あ'),
      const TextCompositionEvent.commit('あ'),
      const TextInputEvent('あ'),
    ]);
  });

  test('DomInputSource positions textarea from caret geometry', () {
    final host = web.document.createElement('div');
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    web.document.body!.appendChild(host);
    final box = const MeasuredCellBox(
      cssCellWidth: 10,
      cssCellHeight: 20,
      cssCanvasWidth: 80,
      cssCanvasHeight: 60,
      cssCanvasLeft: 10,
      cssCanvasTop: 20,
      devicePixelRatio: 1,
      cols: 8,
      rows: 3,
    );
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      cellMetrics: _FakeMetrics(box),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
    });

    source.start((_) {});
    source.syncCaretGeometry(CellRect.fromLTWH(2, 1, 1, 1), box);

    var style = textArea.getAttribute('style')!;
    expect(style, contains('position:fixed'));
    expect(style, contains('left:30px'));
    expect(style, contains('top:40px'));
    expect(style, contains('width:10px'));
    expect(style, contains('height:20px'));
    expect(textArea.getAttribute('data-fleury-caret-state'), 'positioned');
    expect(textArea.getAttribute('data-fleury-caret-col'), '2');
    expect(textArea.getAttribute('data-fleury-caret-row'), '1');
    expect(textArea.getAttribute('data-fleury-caret-width-cells'), '1');
    expect(textArea.getAttribute('data-fleury-caret-height-cells'), '1');
    expect(textArea.getAttribute('data-fleury-caret-css-left'), '30px');
    expect(textArea.getAttribute('data-fleury-caret-css-top'), '40px');
    expect(textArea.getAttribute('data-fleury-caret-css-width'), '10px');
    expect(textArea.getAttribute('data-fleury-caret-css-height'), '20px');

    source.syncCaretGeometry(null, box);

    style = textArea.getAttribute('style')!;
    expect(style, contains('left:-10000px'));
    expect(style, contains('top:-10000px'));
    expect(textArea.getAttribute('data-fleury-caret-state'), 'hidden');
    expect(textArea.getAttribute('data-fleury-caret-col'), isNull);
    expect(textArea.getAttribute('data-fleury-caret-row'), isNull);
    expect(textArea.getAttribute('data-fleury-caret-css-left'), isNull);
    expect(textArea.getAttribute('data-fleury-caret-css-top'), isNull);
  });

  test('DomInputSource lets a cell-grid link click navigate natively', () {
    final events = <TuiEvent>[];
    final host = web.document.createElement('div');
    final textArea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    // A retained-grid link anchor lives under the grid root (.fleury-screen).
    final screen = web.document.createElement('div')
      ..className = 'fleury-screen';
    final anchor = web.document.createElement('a')
      ..setAttribute('href', 'https://fleury.dev')
      ..textContent = 'docs';
    screen.appendChild(anchor);
    host.appendChild(screen);
    web.document.body!.appendChild(host);
    final source = DomInputSource(
      hostElement: host,
      textArea: textArea,
      cellMetrics: _FakeMetrics(
        const MeasuredCellBox(
          cssCellWidth: 10,
          cssCellHeight: 20,
          cssCanvasWidth: 80,
          cssCanvasHeight: 60,
          cssCanvasLeft: 10,
          cssCanvasTop: 20,
          devicePixelRatio: 1,
          cols: 8,
          rows: 3,
        ),
      ),
    );
    addTearDown(() {
      source.dispose();
      host.parentNode?.removeChild(host);
    });

    source.start(events.add);

    // A click ON the link anchor: the browser must be free to navigate, so the
    // input source neither preventDefaults it nor routes it as an app tap.
    final linkClick = web.MouseEvent(
      'click',
      web.MouseEventInit(
        clientX: 25,
        clientY: 65,
        button: 0,
        bubbles: true,
        cancelable: true,
      ),
    );
    anchor.dispatchEvent(linkClick);
    expect(linkClick.defaultPrevented, isFalse, reason: 'navigation allowed');
    expect(events, isEmpty, reason: 'link click is not an app pointer event');

    // A click on a normal cell (not a link) still preventDefaults + routes.
    final cellClick = web.MouseEvent(
      'click',
      web.MouseEventInit(
        clientX: 25,
        clientY: 65,
        button: 0,
        bubbles: true,
        cancelable: true,
      ),
    );
    host.dispatchEvent(cellClick);
    expect(
      cellClick.defaultPrevented,
      isTrue,
      reason: 'app captures the click',
    );
    expect(events, isNotEmpty, reason: 'normal cell click routes as input');
  });
}

final class _FakeClipboard extends Clipboard {
  _FakeClipboard(this._text);

  String? _text;

  @override
  String? readInProcess() => _text;

  @override
  Future<ClipboardWriteReport> writeWithReport(
    String text, {
    ClipboardWritePolicy policy = ClipboardWritePolicy.standard,
  }) async {
    _text = text;
    return ClipboardWriteReport(
      result: ClipboardWriteResult.inProcessOnly,
      resolution: resolveCapabilityRequirement(
        const CapabilityRequirement(
          feature: TerminalFeature.clipboardWrite,
          level: CapabilityLevel.preferred,
          fallback: CapabilityFallback(label: 'in-process register'),
        ),
        const CapabilityTruth(
          feature: TerminalFeature.clipboardWrite,
          support: CapabilitySupport.unsupported,
          enablement: CapabilityEnablement.notApplicable,
          delivery: CapabilityDelivery.notApplicable,
          evidence: <CapabilityEvidence>[
            CapabilityEvidence(
              source: CapabilityEvidenceSource.fallback,
              detail: 'Test clipboard uses an in-process register.',
            ),
          ],
        ),
      ),
      policy: policy,
      payloadBytes: text.length,
      osc52EncodedLength: text.length,
      overSsh: false,
      inProcessUpdated: true,
      platformToolAttempted: false,
      osc52Attempted: false,
      osc52Emitted: false,
    );
  }
}

final class _FakeMetrics implements CellMetrics {
  const _FakeMetrics(this.box);

  final MeasuredCellBox box;

  @override
  MeasuredCellBox? get cachedMeasurement => box;

  @override
  MeasuredCellBox measure() => box;

  @override
  void startObserving(void Function() onMetricsDirty) {}

  @override
  void markDirty() {}

  @override
  CellOffset cellForPoint(double x, double y) {
    final col = (x / box.cssCellWidth).floor().clamp(0, box.cols - 1).toInt();
    final row = (y / box.cssCellHeight).floor().clamp(0, box.rows - 1).toInt();
    return CellOffset(col, row);
  }

  @override
  CellOffset? cellForViewportPoint(double clientX, double clientY) {
    if (box.cols <= 0 || box.rows <= 0) return null;
    return cellForPoint(
      clientX - box.cssCanvasLeft,
      clientY - box.cssCanvasTop,
    );
  }

  @override
  void dispose() {}
}

final class _RecordingMetrics implements CellMetrics {
  _RecordingMetrics(this.box, {required this.mappedCell});

  final MeasuredCellBox box;
  final CellOffset mappedCell;
  var pointCalls = 0;
  double? lastClientX;
  double? lastClientY;

  @override
  MeasuredCellBox? get cachedMeasurement => box;

  @override
  MeasuredCellBox measure() => box;

  @override
  void startObserving(void Function() onMetricsDirty) {}

  @override
  void markDirty() {}

  @override
  CellOffset cellForPoint(double x, double y) {
    pointCalls += 1;
    return mappedCell;
  }

  @override
  CellOffset? cellForViewportPoint(double clientX, double clientY) {
    pointCalls += 1;
    lastClientX = clientX;
    lastClientY = clientY;
    return mappedCell;
  }

  @override
  void dispose() {}
}
