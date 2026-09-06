import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart' as support;
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

Widget _control({
  bool enabled = true,
  bool actionable = true,
  bool fails = false,
}) => Semantics(
  role: SemanticRole.button,
  label: 'Save',
  enabled: enabled,
  includeChildren: false,
  actions: actionable ? {SemanticAction.activate} : {},
  onAction: (_) {
    if (fails) throw StateError('disk full');
  },
  child: const Text('Save'),
);

void main() {
  final cases = <SemanticActionInvocationStatus, Widget>{
    SemanticActionInvocationStatus.notFound: const Text('Editor'),
    // One is actionable and the other is disabled: identity is still ambiguous.
    SemanticActionInvocationStatus.ambiguous: Column(
      children: [_control(), _control(enabled: false, actionable: false)],
    ),
    SemanticActionInvocationStatus.disabled: _control(
      enabled: false,
      actionable: false,
    ),
    SemanticActionInvocationStatus.unsupported: _control(actionable: false),
    SemanticActionInvocationStatus.failed: _control(fails: true),
  };

  for (final entry in cases.entries) {
    testWidgets('${entry.key.name} fails with action, selector and tree', (
      tester,
    ) async {
      tester.pumpWidget(entry.value);
      await expectLater(
        tester.invokeSemanticAction(
          SemanticAction.activate,
          role: SemanticRole.button,
          label: 'Save',
        ),
        throwsA(
          isA<TestFailure>().having(
            (error) => error.message,
            'message',
            allOf([
              contains('activate'),
              contains('Save'),
              contains(entry.key.name),
              contains('app'),
              if (entry.key == SemanticActionInvocationStatus.failed)
                contains('StateError'),
              isNot(contains('disk full')),
            ]),
          ),
        ),
      );

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.button,
        label: 'Save',
        allowFailure: true,
      );
      expect(result.status, entry.key);
      if (entry.key == SemanticActionInvocationStatus.failed) {
        expect(
          result.error,
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'disk full',
          ),
        );
      }
    });

    test('package-neutral harness returns ${entry.key.name}', () async {
      final tester = support.FleuryTester();
      addTearDown(tester.dispose);
      tester.pumpWidget(entry.value);
      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.button,
        label: 'Save',
      );
      expect(result.status, entry.key);
      if (entry.key == SemanticActionInvocationStatus.ambiguous) {
        expect(
          result.error,
          isA<SemanticQueryError>().having((e) => e.matchCount, 'matches', 2),
        );
      }
    });
  }

  testWidgets('successful actions still return their result', (tester) async {
    var calls = 0;
    tester.pumpWidget(
      Semantics(
        role: SemanticRole.button,
        label: 'Save',
        actions: {SemanticAction.activate},
        onAction: (_) => calls++,
        child: const Text('Save'),
      ),
    );
    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Save',
    );
    expect(result.completed, isTrue);
    expect(calls, 1);
  });

  testWidgets('query errors identify matches and keep tree values redacted', (
    tester,
  ) {
    tester.pumpWidget(
      Column(
        children: [
          _control(),
          _control(),
          const Semantics(
            role: SemanticRole.textField,
            label: 'Password',
            value: 'secret-password',
            state: SemanticState({'redactedValue': true}),
            child: EmptyBox(),
          ),
        ],
      ),
    );
    for (final label in ['Missing', 'Save']) {
      expect(
        () =>
            tester.semantics().single(role: SemanticRole.button, label: label),
        throwsA(
          isA<SemanticQueryError>().having(
            (e) => e.message,
            'message',
            allOf([
              contains(label),
              contains('button'),
              contains('Password'),
              contains('<redacted>'),
              isNot(contains('secret-password')),
              if (label == 'Save') contains('Matches:'),
            ]),
          ),
        ),
      );
    }
  });

  testWidgets('failed setValue does not print the action payload', (
    tester,
  ) async {
    tester.pumpWidget(const Text('Editor'));
    await expectLater(
      tester.invokeSemanticAction(
        SemanticAction.setValue,
        label: 'Password',
        payload: 'secret-password',
      ),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          allOf(contains('Password'), isNot(contains('secret-password'))),
        ),
      ),
    );
  });

  testWidgets('query failures redact value filters for zero and many matches', (
    tester,
  ) async {
    const secret = 'private-match-value';
    const absentSecret = 'private-absent-value';
    tester.pumpWidget(
      const Column(
        children: [
          Semantics(
            role: SemanticRole.textField,
            label: 'Password',
            value: secret,
            state: SemanticState({'redactedValue': true}),
            child: EmptyBox(),
          ),
          Semantics(
            role: SemanticRole.textField,
            label: 'Password',
            value: secret,
            state: SemanticState({'redactedValue': true}),
            child: EmptyBox(),
          ),
        ],
      ),
    );
    for (final value in [secret, absentSecret]) {
      final safeMessage = allOf(
        contains('Password'),
        contains('textField'),
        contains('value: <redacted>'),
        isNot(contains(secret)),
        isNot(contains(absentSecret)),
      );
      expect(
        () => tester.semantics().single(
          role: SemanticRole.textField,
          label: 'Password',
          value: value,
        ),
        throwsA(
          isA<SemanticQueryError>().having(
            (error) => error.message,
            'message',
            safeMessage,
          ),
        ),
      );
      await expectLater(
        tester.invokeSemanticAction(
          SemanticAction.setValue,
          role: SemanticRole.textField,
          label: 'Password',
          value: value,
          payload: 'replacement',
        ),
        throwsA(
          isA<TestFailure>().having(
            (error) => error.message,
            'message',
            safeMessage,
          ),
        ),
      );
    }
  });

  for (final flag in ['redactedValue', 'obscureText', 'clipboardRedacted']) {
    testWidgets('$flag validation-error selectors stay private', (
      tester,
    ) async {
      const secret = 'private-validation-input';
      const absentSecret = 'private-absent-validation-input';
      const validationError = 'Invalid input: $secret';
      const absentValidationError = 'Invalid input: $absentSecret';
      Widget protectedField() => Semantics(
        role: SemanticRole.textField,
        label: 'Password',
        value: secret,
        validationError: validationError,
        enabled: false,
        state: SemanticState({flag: true}),
        child: const EmptyBox(),
      );
      final safeMessage = allOf(
        contains('Password'),
        contains('textField'),
        contains('validationError: <redacted>'),
        isNot(contains(secret)),
        isNot(contains(absentSecret)),
      );

      tester.pumpWidget(Column(children: [protectedField(), protectedField()]));
      for (final query in {
        validationError: 2,
        absentValidationError: 0,
      }.entries) {
        expect(
          () => tester.semantics().single(
            role: SemanticRole.textField,
            label: 'Password',
            validationError: query.key,
          ),
          throwsA(
            isA<SemanticQueryError>()
                .having((error) => error.matchCount, 'matches', query.value)
                .having((error) => error.message, 'message', safeMessage),
          ),
        );
        await expectLater(
          tester.invokeSemanticAction(
            SemanticAction.setValue,
            role: SemanticRole.textField,
            label: 'Password',
            validationError: query.key,
            payload: 'replacement',
          ),
          throwsA(
            isA<TestFailure>().having(
              (error) => error.message,
              'message',
              safeMessage,
            ),
          ),
        );
      }

      // Matching still uses the original message, and an explicitly requested
      // result retains the target's original validation details.
      tester.pumpWidget(protectedField());
      expect(
        tester
            .semantics()
            .single(validationError: validationError)
            .validationError,
        validationError,
      );
      await expectLater(
        tester.invokeSemanticAction(
          SemanticAction.setValue,
          role: SemanticRole.textField,
          label: 'Password',
          validationError: validationError,
          payload: 'replacement',
        ),
        throwsA(
          isA<TestFailure>().having(
            (error) => error.message,
            'message',
            allOf(safeMessage, contains('disabled')),
          ),
        ),
      );
      final result = await tester.invokeSemanticAction(
        SemanticAction.setValue,
        role: SemanticRole.textField,
        label: 'Password',
        validationError: validationError,
        payload: 'replacement',
        allowFailure: true,
      );
      expect(result.status, SemanticActionInvocationStatus.disabled);
      expect(result.node!.validationError, validationError);
    });
  }

  testWidgets(
    'handler messages stay private while explicit results retain errors',
    (tester) async {
      const secret = 'private-handler-input';
      final failures = [
        StateError('Rejected $secret'),
        SemanticQueryError(0, 'Rejected $secret'),
      ];
      for (final failure in failures) {
        tester.pumpWidget(
          Semantics(
            role: SemanticRole.textField,
            label: 'Password',
            actions: {SemanticAction.setValue},
            onSetValue: (_) => throw failure,
            child: const EmptyBox(),
          ),
        );
        await expectLater(
          tester.invokeSemanticAction(
            SemanticAction.setValue,
            label: 'Password',
            payload: secret,
          ),
          throwsA(
            isA<TestFailure>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('Password'),
                contains('setValue'),
                contains('failed'),
                contains(failure.runtimeType.toString()),
                isNot(contains(secret)),
              ),
            ),
          ),
        );
        final result = await tester.invokeSemanticAction(
          SemanticAction.setValue,
          label: 'Password',
          payload: secret,
          allowFailure: true,
        );
        expect(result.status, SemanticActionInvocationStatus.failed);
        expect(result.error, same(failure));
      }
    },
  );
}
