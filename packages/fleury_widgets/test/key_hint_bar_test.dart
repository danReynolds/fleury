import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
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
            KeyBinding(KeyChord.char('q'), onEvent: (_) {}, label: 'Quit'),
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
            KeyBinding(KeyChord.char('q'), onEvent: (_) {}, label: 'outer'),
          ],
          child: KeyBindings(
            bindings: [
              KeyBinding(KeyChord.char('q'), onEvent: (_) {}, label: 'inner'),
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
            KeyBinding(KeyChord.char('a'), onEvent: (_) {}),
            KeyBinding(
              KeyChord.char('b'),
              onEvent: (_) {},
              label: 'hidden',
              hideFromHintBar: true,
            ),
            KeyBinding(
              KeyChord.char('c'),
              onEvent: (_) {},
              label: 'off',
              enabled: false,
            ),
            KeyBinding(KeyChord.char('d'), onEvent: (_) {}, label: 'shown'),
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
              shortcuts: [KeyChord.ctrl.r],
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
}
