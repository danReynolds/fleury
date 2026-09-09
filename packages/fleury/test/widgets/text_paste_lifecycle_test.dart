import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  for (final multiline in [false, true]) {
    Widget field(TextEditingController controller, TextPastePolicy policy) =>
        multiline
        ? TextArea(controller: controller, autofocus: true, pastePolicy: policy)
        : TextInput(
            controller: controller,
            autofocus: true,
            pastePolicy: policy,
          );

    testWidgets(
      'immediate paste survives external-controller unmount/remount, multiline=$multiline',
      (tester) {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final text = 'synthetic-value-' * 20000;
        tester.pumpWidget(field(controller, const TextPastePolicy.immediate()));
        tester.render(size: const CellSize(30, 4));
        tester.paste(text);
        // No frame/settle between delivery and removal: reproduce the real edge.
        expect(controller.text, text);
        tester.pumpWidget(const Text('Temporarily hidden'));
        tester.pumpAndSettle();
        expect(controller.text, text);
        tester.pumpWidget(field(controller, const TextPastePolicy.immediate()));
        tester.render(size: const CellSize(30, 4));
        expect(controller.text, text);
        tester.sendKey(
          const KeyEvent(KeyCode.z, modifiers: {KeyModifier.ctrl}),
        );
        expect(controller.text, isEmpty, reason: 'one undo transaction');
        tester.sendKey(
          const KeyEvent(
            KeyCode.z,
            modifiers: {KeyModifier.ctrl, KeyModifier.shift},
          ),
        );
        expect(controller.text, text);
        // The owner can deliberately cancel; no scheduled work repopulates it.
        controller.clear();
        tester.pumpWidget(const Text('Cancelled'));
        tester.pumpAndSettle();
        expect(controller.text, isEmpty);
        controller.text = 'external controller remains usable';
        expect(controller.text, 'external controller remains usable');
      },
    );

    testWidgets(
      'default chunked paste disposal still cancels pending input, multiline=$multiline',
      (tester) {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        tester.pumpWidget(field(controller, const TextPastePolicy()));
        tester.render(size: const CellSize(30, 4));
        tester.paste('x' * (256 * 1024));
        expect(controller.text.length, lessThan(256 * 1024));
        controller.clear();
        tester.pumpWidget(const Text('Cancelled'));
        tester.pumpAndSettle();
        expect(controller.text, isEmpty);
      },
    );
  }
}
