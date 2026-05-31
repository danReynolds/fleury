import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  group('PasswordInput', () {
    testWidgets('renders typed characters as • not the real text', (tester) {
      tester.pumpWidget(const PasswordInput(autofocus: true));
      tester.type('secret');
      final out = tester
          .renderToString(size: const CellSize(10, 1), emptyMark: ' ')
          .trimRight();
      // Six dots for the six typed characters; the real text should not
      // appear anywhere.
      expect(out.contains('••••••'), isTrue);
      expect(out.contains('secret'), isFalse);
    });

    testWidgets('controller still holds the real text', (tester) {
      final ctrl = TextEditingController();
      tester.pumpWidget(PasswordInput(controller: ctrl, autofocus: true));
      tester.type('hunter2');
      expect(
        ctrl.text,
        'hunter2',
        reason: 'controller is the source of truth — only display is masked',
      );
    });

    testWidgets('onSubmit fires with the real text on Enter', (tester) {
      String? submitted;
      tester.pumpWidget(
        PasswordInput(autofocus: true, onSubmit: (t) => submitted = t),
      );
      tester.type('p@ss');
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(submitted, 'p@ss');
    });

    testWidgets('placeholder shows when empty (not masked)', (tester) {
      tester.pumpWidget(const PasswordInput(placeholder: 'API token'));
      final out = tester
          .renderToString(size: const CellSize(16, 1), emptyMark: ' ')
          .trimRight();
      expect(out.contains('API token'), isTrue);
    });

    testWidgets('custom obscuringCharacter is honored', (tester) {
      tester.pumpWidget(
        const PasswordInput(autofocus: true, obscuringCharacter: '*'),
      );
      tester.type('abc');
      final out = tester
          .renderToString(size: const CellSize(10, 1), emptyMark: ' ')
          .trimRight();
      expect(out.contains('***'), isTrue);
    });
  });
}
