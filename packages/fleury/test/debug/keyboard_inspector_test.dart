// RFC 0020 §19 — the debug shell answers "why isn't my hold firing?".
//
// Every hard question this RFC creates turns on a fact the app cannot see:
// what the surface confirmed, which phase an event carried, whether a
// position came through, and whether a release was real or synthesized.

import 'package:fleury/fleury.dart';
import 'package:fleury/src/debug/debug_events.dart';
import 'package:test/test.dart';

String _summary(TuiEvent event) => InputDebugEvent.fromTuiEvent(event).summary;

void main() {
  group('the input feed shows the RFC 0020 facts', () {
    test('a phase is named, so a missing release is visible', () {
      // "My hold never ends" is nearly always a surface that reports no up.
      // A feed showing only downs cannot tell you that.
      expect(_summary(const KeyEvent(KeyCode.char('w'))), 'w');
      expect(
        _summary(const KeyEvent(KeyCode.char('w'), type: KeyEventType.up)),
        'w up',
      );
      expect(
        _summary(const KeyEvent(KeyCode.char('w'), type: KeyEventType.repeat)),
        'w repeat',
      );
    });

    test('positional identity is shown when it came through', () {
      // A positional binding that silently degraded to its US twin looks
      // identical to one matching properly — until you can see whether a
      // position arrived at all.
      expect(
        _summary(const KeyEvent(KeyCode.char('z'), position: KeyPosition.w)),
        'z @w',
      );
      expect(_summary(const KeyEvent(KeyCode.char('z'))), 'z');
    });

    test('a synthesized release is never mistaken for a real one', () {
      // Recovery invents releases on authority loss. Reading one as a
      // finger leaving a key sends you hunting for a bug that is not there.
      expect(
        _summary(
          const KeyEvent(
            KeyCode.char('w'),
            type: KeyEventType.up,
            synthesized: true,
          ),
        ),
        'w up (synthesized)',
      );
    });

    test('modifiers and special keys still read naturally', () {
      expect(
        _summary(
          const KeyEvent(KeyCode.char('s'), modifiers: {KeyModifier.ctrl}),
        ),
        'ctrl s',
      );
      expect(_summary(const KeyEvent(KeyCode.escape)), 'escape');
    });

    test('a batch shows its key half with the same detail as a bare key', () {
      // The correlated shape must not be the one that hides the position:
      // on a lifecycle terminal EVERY printable arrives batched, so a batch
      // summary that drops the position blinds the inspector exactly where
      // positions matter most.
      expect(
        _summary(
          const InputBatch(
            key: KeyEvent(KeyCode.char('z'), position: KeyPosition.w),
            committedText: 'z',
          ),
        ),
        'z @w "z"',
      );
    });

    test('a window focus change is reported — it is why keys stopped', () {
      expect(
        _summary(const TerminalFocusEvent(focused: false)),
        'window focus out',
      );
    });
  });
}
