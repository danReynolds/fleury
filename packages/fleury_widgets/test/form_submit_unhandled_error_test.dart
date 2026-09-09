// Lock test: an onSubmit throw must not kill the app through the semantic
// submit action, and must still be visible to a caller that awaits submit().
//
// runApp's runZonedGuarded treats an uncaught async error as FATAL — it
// restores the terminal and ends the session — so the fire-and-forget path
// (SemanticAction.submit, which nobody awaits) has to contain it.
//
// Containing it inside FormController._runSubmission instead made every
// failure look like a validation rejection: `submit()` returned false, which
// its own doc reserves for "validation rejected it", so an awaiting caller
// could not tell a network error from an invalid field and showed nothing.
import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('the semantic submit action contains an onSubmit throw', (
    tester,
  ) async {
    final controller = FormController();
    final text = TextEditingController(text: 'ok');
    final errors = <Object>[];

    await runZonedGuarded(() async {
      tester.pumpWidget(
        Form(
          controller: controller,
          onSubmit: () => throw StateError('submit failed'),
          child: FormField(
            child: TextInput(controller: text, semanticLabel: 'Name'),
          ),
        ),
      );
      tester.render(size: const CellSize(30, 4));

      // The real fire-and-forget path: nobody awaits this one.
      await tester.target(role: SemanticRole.form).submit();
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => errors.add(error));

    expect(
      errors.whereType<StateError>().any((e) => '$e'.contains('submit failed')),
      isFalse,
      reason:
          'an onSubmit throw reached through SemanticAction.submit escaped to '
          'the guarded zone, which ends the app: $errors',
    );

    tester.pumpWidget(const Text('gone'));
    controller.dispose();
    text.dispose();
  });

  testWidgets('an awaiting caller still sees the onSubmit error', (
    tester,
  ) async {
    final controller = FormController();
    final text = TextEditingController(text: 'ok');

    tester.pumpWidget(
      Form(
        controller: controller,
        onSubmit: () => throw StateError('network down'),
        child: FormField(
          child: TextInput(controller: text, semanticLabel: 'Name'),
        ),
      ),
    );
    tester.render(size: const CellSize(30, 4));

    Object? caught;
    // Validation runs across frames, so drive them rather than awaiting cold.
    final pending = controller.submit().then<void>(
      (_) {},
      onError: (Object e) => caught = e,
    );
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
      tester.pump();
    }
    await pending;

    expect(
      caught,
      isA<StateError>(),
      reason:
          'false means "validation rejected it"; a thrown onSubmit is a '
          'different outcome and the caller has to be able to tell them apart',
    );

    tester.pumpWidget(const Text('gone'));
    controller.dispose();
    text.dispose();
  });
}
