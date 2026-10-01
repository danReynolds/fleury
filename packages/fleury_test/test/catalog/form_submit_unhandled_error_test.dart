// An onSubmit throw is an app error, and it must be reported, not lost.
//
// Every path that submits without awaiting the result (Enter in a field, a
// button, the semantic submit action) leaves the error to the zone, where
// runApp reports it (stderr, the error banner, the debug shell) and keeps
// running. The semantic action used to swallow it, on the reasoning that
// runApp ended the session on any uncaught async error; it no longer does.
//
// A caller that awaits submit() receives the error instead. Containing it
// inside FormController._runSubmission made every failure look like a
// validation rejection: `submit()` returned false, which its own doc
// reserves for "validation rejected it", so an awaiting caller could not
// tell a network error from an invalid field and showed nothing.
import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  /// The errors that reach the zone when [submitWith] submits a form whose
  /// onSubmit throws.
  Future<List<Object>> uncaughtFrom(
    FleuryTester tester,
    Future<void> Function(FormController controller) submitWith,
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
            child: TextInput(
              controller: text,
              autofocus: true,
              semanticLabel: 'Name',
              // Enter in the field submits and drops the result, like a
              // button's onPressed does.
              onSubmit: (_) => controller.submit(),
            ),
          ),
        ),
      );
      tester.render(size: const CellSize(30, 4));

      await submitWith(controller);
      // Validation runs across frames; drive them.
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
        tester.pump();
      }
    }, (error, _) => errors.add(error));

    tester.pumpWidget(const Text('gone'));
    controller.dispose();
    text.dispose();
    return errors;
  }

  testWidgets('the semantic submit action reports an onSubmit throw, as '
      'Enter in a field does', (tester) async {
    bool reportsFailure(List<Object> errors) => errors
        .whereType<StateError>()
        .any((e) => '$e'.contains('submit failed'));

    final fromEnter = await uncaughtFrom(tester, (_) async {
      tester.sendKey(const KeyEvent(KeyCode.enter));
    });
    expect(reportsFailure(fromEnter), isTrue, reason: 'the keyboard path');

    // The real fire-and-forget path: nobody awaits this one.
    final fromAction = await uncaughtFrom(
      tester,
      (_) => tester.target(role: SemanticRole.form).submit(),
    );
    expect(
      reportsFailure(fromAction),
      isTrue,
      reason: 'the semantic action lost the error: $fromAction',
    );
    expect(fromAction, hasLength(1), reason: 'reported once');
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
