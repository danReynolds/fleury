import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _render(FleuryTester tester, {int cols = 60, int rows = 2}) =>
    tester.renderToString(size: CellSize(cols, rows), emptyMark: ' ');

void main() {
  group('KeyHintBar', () {
    testWidgets('shows currently active focused bindings', (tester) {
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyCode.char('q'), onTrigger: (_) {}, label: 'Quit'),
          ],
          child: const Column(
            children: [
              Expanded(child: Focus(autofocus: true, child: Text('Body'))),
              KeyHintBar(),
            ],
          ),
        ),
      );

      expect(_render(tester), contains('[q] Quit'));
    });

    testWidgets('dedupes duplicate chords — nearer binding wins', (tester) {
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyCode.char('q'), onTrigger: (_) {}, label: 'outer'),
          ],
          child: KeyBindings(
            bindings: [
              KeyBinding(KeyCode.char('q'), onTrigger: (_) {}, label: 'inner'),
            ],
            child: const Column(
              children: [
                Expanded(child: Focus(autofocus: true, child: Text('Body'))),
                KeyHintBar(),
              ],
            ),
          ),
        ),
      );

      final out = _render(tester);
      expect(out, contains('[q] inner'));
      expect(out, isNot(contains('outer')));
    });

    testWidgets('hides label-less, hidden, and disabled bindings', (tester) {
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyCode.char('a'), onTrigger: (_) {}),
            KeyBinding(
              KeyCode.char('b'),
              onTrigger: (_) {},
              label: 'hidden',
              hideFromHintBar: true,
            ),
            KeyBinding(
              KeyCode.char('c'),
              onTrigger: (_) {},
              label: 'off',
              enabled: false,
            ),
            KeyBinding(KeyCode.char('d'), onTrigger: (_) {}, label: 'shown'),
          ],
          child: const Column(
            children: [
              Expanded(child: Focus(autofocus: true, child: Text('Body'))),
              KeyHintBar(),
            ],
          ),
        ),
      );

      final out = _render(tester);
      expect(out, contains('[d] shown'));
      expect(out, isNot(contains('hidden')));
      expect(out, isNot(contains('off')));
    });

    testWidgets('app command shortcuts appear in the bar', (tester) {
      tester.pumpWidget(
        FleuryApp(
          title: 'Ops Console',
          commands: [
            AppCommand(
              id: const CommandId('go.runs'),
              title: 'Go to Runs',
              shortcuts: [KeySequence.ctrl.r],
              run: (_) {},
            ),
          ],
          child: const Column(
            children: [
              Expanded(child: Focus(autofocus: true, child: Text('Body'))),
              KeyHintBar(),
            ],
          ),
        ),
      );

      final out = tester.renderToString(
        size: const CellSize(40, 2),
        emptyMark: ' ',
      );
      expect(out.contains('[Ctrl+R] Go to Runs'), isTrue);
    });
  });

  group('F8: overflow + combined labels', () {
    testWidgets('a multi-alias binding renders one combined chord label', (
      tester,
    ) {
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyCode.arrowUp,
              aliases: [KeyCode.arrowDown],
              label: 'move',
              onTrigger: (_) {},
            ),
          ],
          child: const Column(
            children: [
              Expanded(child: Focus(autofocus: true, child: Text('Body'))),
              KeyHintBar(),
            ],
          ),
        ),
      );
      expect(_render(tester), contains('[↑↓] move'));
    });

    testWidgets('overflow drops whole bindings with a trailing +N, never '
        'clipping a label', (tester) {
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            for (var i = 0; i < 6; i++)
              KeyBinding(KeyCode.char('$i'), label: 'act$i', onTrigger: (_) {}),
          ],
          child: const Column(
            children: [
              Expanded(child: Focus(autofocus: true, child: Text('Body'))),
              KeyHintBar(),
            ],
          ),
        ),
      );
      // Wide: everything fits, no marker.
      final wide = _render(tester, cols: 80);
      expect(wide, contains('[5] act5'));
      expect(wide, isNot(contains('+')));
      // Narrow: the leading binding(s) fit; the rest collapse into "+N", and no
      // label is clipped mid-word.
      final narrow = _render(tester, cols: 20);
      expect(narrow, contains('[0] act0'));
      expect(narrow, contains('+'), reason: 'a +N marker signals the drop');
      expect(narrow, isNot(contains('act5')), reason: 'act5 collapsed into +N');
    });

    testWidgets('unbounded width shows every binding (no +N)', (tester) {
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            for (var i = 0; i < 4; i++)
              KeyBinding(KeyCode.char('$i'), label: 'act$i', onTrigger: (_) {}),
          ],
          // A non-Expanded bar in a Row receives an unbounded width.
          child: Row(
            children: const [
              Focus(autofocus: true, child: Text('x')),
              KeyHintBar(),
            ],
          ),
        ),
      );
      final out = _render(tester, cols: 80);
      expect(out, contains('act3'), reason: 'all bindings show, none dropped');
      expect(out, isNot(contains('+')), reason: 'nothing dropped, no +N');
    });

    testWidgets('the +N count includes bindings the maxBindings cap dropped', (
      tester,
    ) {
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            for (var i = 0; i < 20; i++)
              KeyBinding(
                KeyCode.char(String.fromCharCode(97 + i)),
                label: 'a$i',
                onTrigger: (_) {},
              ),
          ],
          child: const Column(
            children: [
              Expanded(child: Focus(autofocus: true, child: Text('Body'))),
              KeyHintBar(),
            ],
          ),
        ),
      );
      // 20 bindings, cap 12 — even at a very wide width the 8 beyond the cap
      // show as "+8" rather than silently vanishing.
      expect(_render(tester, cols: 200), contains('+8'));
    });
  });

  group('layout-honest labels (RFC 0020 §9)', () {
    testWidgets('an unknown layout falls back to the US twin', (tester) {
      // Degraded but actionable. A blank hint helps nobody, and the US name
      // is what the position is documented as.
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyPosition.w, onTrigger: (_) {}, label: 'Thrust'),
          ],
          child: const Column(
            children: [
              Expanded(child: Focus(autofocus: true, child: Text('Body'))),
              KeyHintBar(),
            ],
          ),
        ),
      );
      expect(_render(tester), contains('[w] Thrust'));
    });

    testWidgets('once the terminal reports a position, the REAL cap shows', (
      tester,
    ) {
      // The bar exists to tell people what to press, so it must not be the
      // thing that misleads them: on AZERTY the key at QWERTY-W is capped Z.
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyPosition.w, onTrigger: (_) {}, label: 'Thrust'),
          ],
          child: const Column(
            children: [
              Expanded(child: Focus(autofocus: true, child: Text('Body'))),
              KeyHintBar(),
            ],
          ),
        ),
      );
      expect(_render(tester), contains('[w] Thrust'));

      // A press that carries positional identity IS the mapping, observed.
      tester.sendKey(
        const KeyEvent(KeyCode.char('z'), position: KeyPosition.w),
      );
      tester.pump();
      expect(_render(tester), contains('[z] Thrust'));
      expect(_render(tester), isNot(contains('[w] Thrust')));
    });

    testWidgets('a logical binding is never rewritten', (tester) {
      // Only positions are spots. `q` IS the cap, on every layout.
      tester.pumpWidget(
        KeyBindings(
          bindings: [KeyBinding(KeyCode.q, onTrigger: (_) {}, label: 'Quit')],
          child: const Column(
            children: [
              Expanded(child: Focus(autofocus: true, child: Text('Body'))),
              KeyHintBar(),
            ],
          ),
        ),
      );
      tester.sendKey(
        const KeyEvent(KeyCode.char('a'), position: KeyPosition.q),
      );
      tester.pump();
      expect(_render(tester), contains('[q] Quit'));
    });
  });
}
