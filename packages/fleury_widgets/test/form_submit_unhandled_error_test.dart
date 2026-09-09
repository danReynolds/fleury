import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('unawaited submit does not leave onSubmit errors unhandled', (
    tester,
  ) async {
    final controller = FormController();
    final text = TextEditingController(text: 'ok');
    final errors = <Object>[];

    await runZonedGuarded(() async {
      tester.pumpWidget(
        Form(
          controller: controller,
          onSubmit: () {
            throw StateError('submit failed');
          },
          child: FormField(
            child: TextInput(controller: text, semanticLabel: 'Name'),
          ),
        ),
      );

      // Same fire-and-forget posture as SemanticAction.submit.
      unawaited(controller.submit());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => errors.add(error));

    expect(
      errors.whereType<StateError>().any((e) => '$e'.contains('submit failed')),
      isFalse,
      reason:
          'onSubmit threw and escaped as an unhandled async error via '
          'unawaited(submit()): $errors',
    );

    tester.pumpWidget(const Text('gone'));
    controller.dispose();
    text.dispose();
  });
}
