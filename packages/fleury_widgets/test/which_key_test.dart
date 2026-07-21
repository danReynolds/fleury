import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _render(FleuryTester tester) =>
    tester.renderToString(size: const CellSize(40, 14), emptyMark: ' ');

Widget _app({Duration showDelay = Duration.zero}) => WhichKey(
  showDelay: showDelay,
  child: KeyBindings(
    bindings: [
      KeyBinding(KeySequence.space.f, label: 'Find file', onTrigger: () {}),
      KeyBinding(KeySequence.space.b, label: 'Buffers', onTrigger: () {}),
      // Unlabeled: fires but must not be advertised in the popup.
      KeyBinding(KeySequence.space.x, onTrigger: () {}),
    ],
    child: const Focus(autofocus: true, child: Text('body')),
  ),
);

void main() {
  group('WhichKey', () {
    testWidgets('is a pass-through until a leader is pressed', (tester) {
      tester.pumpWidget(_app());
      tester.render();
      final out = _render(tester);
      expect(out, contains('body'));
      expect(out, isNot(contains('Find file')));
    });

    testWidgets('shows labeled completions for a pending leader', (tester) {
      tester.pumpWidget(_app());
      tester.render();

      tester.press(KeySequence.space); // leader
      final out = _render(tester);
      expect(out, contains('Space'), reason: 'the prefix titles the popup');
      expect(out, contains('Find file'));
      expect(out, contains('Buffers'));
      expect(out, contains('body'), reason: 'the app stays visible underneath');
    });

    testWidgets('hides again once the sequence completes', (tester) {
      tester.pumpWidget(_app());
      tester.render();

      tester.press(KeySequence.space);
      expect(_render(tester), contains('Find file'));

      tester.press(KeySequence.f); // completes .space.f
      expect(_render(tester), isNot(contains('Find file')));
    });

    testWidgets('caps the list with a "+N more" for a large keymap', (tester) {
      // 20 distinct next-keys under one leader → 20 live completions.
      final letters = 'abcdefghijklmnopqrst'.split('');
      tester.pumpWidget(
        WhichKey(
          showDelay: Duration.zero,
          maxCompletions: 5,
          child: KeyBindings(
            bindings: [
              for (final letter in letters)
                KeyBinding(
                  KeySequence.space.char(letter),
                  label: 'Cmd $letter',
                  onTrigger: () {},
                ),
            ],
            child: const Focus(autofocus: true, child: Text('body')),
          ),
        ),
      );
      tester.render();
      tester.press(KeySequence.space);
      final out = tester.renderToString(
        size: const CellSize(40, 24),
        emptyMark: ' ',
      );
      expect(out, contains('+15 more'), reason: '20 completions, cap 5');
    });

    testWidgets('a non-zero delay suppresses a fast sequence', (tester) async {
      tester.pumpWidget(_app(showDelay: const Duration(milliseconds: 40)));
      tester.render();

      // Leader down, then completed before the reveal delay elapses — the
      // popup must never have flashed.
      tester.press(KeySequence.space);
      expect(
        _render(tester),
        isNot(contains('Find file')),
        reason: 'not shown before the delay',
      );
      tester.press(KeySequence.f); // completes fast
      await Future<void>.delayed(const Duration(milliseconds: 60));
      tester.pump();
      expect(_render(tester), isNot(contains('Find file')));
    });
  });
}
