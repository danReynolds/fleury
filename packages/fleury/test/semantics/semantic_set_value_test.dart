// SemanticAction.setValue — the one action that carries a payload.
//
// Pins the additive contract: the value is delivered via `onSetValue` /
// SemanticValueContributor (not the parameterless onAction), it is gated on the
// node advertising `setValue`, and TextInput applies it to its controller — one
// semantic call instead of focus-then-keystrokes.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  group('SemanticAction.setValue', () {
    testWidgets('delivers the payload to onSetValue', (tester) async {
      Object? received;
      var calls = 0;
      tester.pumpWidget(
        Semantics(
          id: const SemanticNodeId('field'),
          role: SemanticRole.textField,
          label: 'Name',
          actions: const <SemanticAction>{SemanticAction.setValue},
          onSetValue: (value) {
            received = value;
            calls++;
          },
          child: const Text('field'),
        ),
      );

      final result = await tester.invokeSemanticAction(
        SemanticAction.setValue,
        id: const SemanticNodeId('field'),
        payload: 'Ada',
      );

      expect(result.status, SemanticActionInvocationStatus.completed);
      expect(calls, 1);
      expect(received, 'Ada');
    });

    testWidgets('a non-string payload reaches the handler verbatim', (
      tester,
    ) async {
      Object? received;
      tester.pumpWidget(
        Semantics(
          id: const SemanticNodeId('slider'),
          role: SemanticRole.slider,
          actions: const <SemanticAction>{SemanticAction.setValue},
          onSetValue: (value) => received = value,
          child: const Text('s'),
        ),
      );

      await tester.invokeSemanticAction(
        SemanticAction.setValue,
        id: const SemanticNodeId('slider'),
        payload: 0.7,
      );
      expect(received, 0.7);
    });

    testWidgets('onAction is not invoked for a setValue dispatch', (
      tester,
    ) async {
      final seen = <SemanticAction>[];
      Object? setValueArg;
      tester.pumpWidget(
        Semantics(
          id: const SemanticNodeId('both'),
          role: SemanticRole.textField,
          actions: const <SemanticAction>{
            SemanticAction.activate,
            SemanticAction.setValue,
          },
          onAction: seen.add,
          onSetValue: (v) => setValueArg = v,
          child: const Text('x'),
        ),
      );

      await tester.invokeSemanticAction(
        SemanticAction.setValue,
        id: const SemanticNodeId('both'),
        payload: 'v',
      );
      // setValue routed to the value handler, never the action handler.
      expect(setValueArg, 'v');
      expect(seen, isEmpty);
    });

    testWidgets('a node that does not advertise setValue does not apply it', (
      tester,
    ) async {
      var called = false;
      tester.pumpWidget(
        Semantics(
          id: const SemanticNodeId('btn'),
          role: SemanticRole.button,
          actions: const <SemanticAction>{SemanticAction.activate},
          onSetValue: (_) => called = true,
          child: const Text('b'),
        ),
      );

      final result = await tester.invokeSemanticAction(
        SemanticAction.setValue,
        id: const SemanticNodeId('btn'),
        payload: 'x',
      );
      expect(result.status, isNot(SemanticActionInvocationStatus.completed));
      expect(called, isFalse);
    });

    testWidgets('advertised but no onSetValue handler is unsupported', (
      tester,
    ) async {
      tester.pumpWidget(
        const Semantics(
          id: SemanticNodeId('field'),
          role: SemanticRole.textField,
          actions: <SemanticAction>{SemanticAction.setValue},
          child: Text('f'),
        ),
      );

      final result = await tester.invokeSemanticAction(
        SemanticAction.setValue,
        id: const SemanticNodeId('field'),
        payload: 'x',
      );
      expect(result.status, SemanticActionInvocationStatus.unsupported);
    });

    testWidgets('TextInput applies setValue to its controller in one call', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'old');
      tester.pumpWidget(TextInput(controller: controller));

      final field = tester.semantics().single(role: SemanticRole.textField);
      expect(field.actions, contains(SemanticAction.setValue));

      final result = await tester.invokeSemanticAction(
        SemanticAction.setValue,
        id: field.id,
        payload: 'new value',
      );

      expect(result.status, SemanticActionInvocationStatus.completed);
      expect(controller.text, 'new value');
    });

    testWidgets('TextInput readOnly does not apply setValue', (tester) async {
      final controller = TextEditingController(text: 'frozen');
      tester.pumpWidget(TextInput(controller: controller, readOnly: true));

      final field = tester.semantics().single(role: SemanticRole.textField);
      expect(field.actions, isNot(contains(SemanticAction.setValue)));

      final result = await tester.invokeSemanticAction(
        SemanticAction.setValue,
        id: field.id,
        payload: 'hacked',
      );
      expect(result.status, isNot(SemanticActionInvocationStatus.completed));
      expect(controller.text, 'frozen');
    });
  });
}
