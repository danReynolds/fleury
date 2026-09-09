@TestOn('browser')
library;

// Lock test (audit 14.c): Alt-only printables are dropped by
// keyEventFromBrowser, so first-party Tabs Alt+1..9 shortcuts never fire on
// the browser/serve surface.
import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/input/dom_input_source.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  test('Alt+1 maps to KeyEvent(char(1), alt) for Tabs accelerators', () {
    final event = keyEventFromBrowser(
      web.KeyboardEvent(
        'keydown',
        web.KeyboardEventInit(key: '1', code: 'Digit1', altKey: true),
      ),
    );
    expect(
      event,
      const KeyEvent(
        KeyCode.char('1'),
        modifiers: {KeyModifier.alt},
        position: KeyPosition.digit1,
      ),
      reason:
          'Tabs ships Alt+1..9; dropping Alt-only printables makes that '
          'shortcut dead on serve/browser',
    );
  });
}
