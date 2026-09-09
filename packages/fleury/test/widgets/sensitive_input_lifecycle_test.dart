import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  for (final multiline in [false, true]) {
    testWidgets('cleared sensitive text cannot return through keyboard undo, '
        'multiline=$multiline', (tester) {
      final key = GlobalKey<_SensitiveFormState>();
      tester.pumpWidget(_SensitiveForm(key: key, multiline: multiline));
      final controller = key.currentState!.controller;
      tester.type('discarded-secret');
      tester.press(.home);
      tester.press(.shift.end);
      tester.press(.backspace);
      expect(controller.text, isEmpty);
      controller.text = '';

      tester.press(.ctrl.z);
      expect(controller.text, isEmpty);
      tester.press(.ctrl.y);

      expect(controller.text, isEmpty);
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isFalse);
      expect(tester.renderToString(), isNot(contains('discarded-secret')));
      expect(tester.semantics().single(label: 'Sensitive').value, isNull);
      tester.type('fresh');
      tester.press(.ctrl.z);
      expect(controller.text, isEmpty, reason: 'new edits still support undo');
      tester.press(.ctrl.y);
      expect(controller.text, 'fresh');
    });

    testWidgets('closing a sensitive form releases its value and reopening '
        'starts without history, multiline=$multiline', (tester) {
      final key = GlobalKey<_SensitiveFormState>();
      tester.pumpWidget(_SensitiveForm(key: key, multiline: multiline));
      final retired = key.currentState!.controller;
      tester.type('discarded-secret');
      tester.press(.backspace);
      expect(retired.canUndo, isTrue);

      tester.pumpWidget(const Text('Closed'));
      tester.pumpAndSettle();

      expect(retired.value, TextEditingValue.empty());
      expect(retired.canUndo, isFalse);
      expect(retired.canRedo, isFalse);
      expect(() => retired.undo(), throwsStateError);
      final nextKey = GlobalKey<_SensitiveFormState>();
      tester.pumpWidget(_SensitiveForm(key: nextKey, multiline: multiline));
      tester.press(.ctrl.z);
      expect(nextKey.currentState!.controller.text, isEmpty);
      tester.press(.ctrl.y);
      expect(nextKey.currentState!.controller.text, isEmpty);
      expect(tester.renderToString(), isNot(contains('discarded')));
      expect(tester.semantics().single(label: 'Sensitive').value, isNull);
    });
  }
}

class _SensitiveForm extends StatefulWidget {
  const _SensitiveForm({super.key, required this.multiline});

  final bool multiline;

  @override
  State<_SensitiveForm> createState() => _SensitiveFormState();
}

class _SensitiveFormState extends State<_SensitiveForm> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.multiline
      ? TextArea(
          controller: controller,
          autofocus: true,
          obscureText: true,
          clipboardPolicy: TextClipboardPolicy.redacted,
          semanticLabel: 'Sensitive',
        )
      : TextInput(
          controller: controller,
          autofocus: true,
          obscureText: true,
          clipboardPolicy: TextClipboardPolicy.redacted,
          semanticLabel: 'Sensitive',
        );
}
