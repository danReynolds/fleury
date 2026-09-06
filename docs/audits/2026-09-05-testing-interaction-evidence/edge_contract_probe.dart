// Read-only behavioral audit of existing contracts; no proposed public API.
import 'dart:convert';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';
import 'package:test/test.dart';

import '../../../website/examples/lib/testing_guide.dart';

void main() {
  test('existing contracts that constrain the testing-controls proposal', () async {
    final observations = <String>[];
    Future<void> probe(
      String name,
      Future<void> Function(FleuryTester) body,
    ) async {
      final tester = FleuryTester();
      try {
        await body(tester);
        observations.add(name);
      } finally {
        tester.dispose();
      }
    }

    await probe(
      'MultiSelect checkbox value is an option key; checked is boolean; setValue is unsupported',
      (tester) async {
        tester.pumpWidget(
          MultiSelect<String>(
            values: const {'red'},
            options: const [SelectOption(value: 'red', label: 'Red')],
            onChanged: (_) {},
          ),
        );
        final option = tester.semantics().single(
          role: SemanticRole.checkbox,
          label: 'Red',
        );
        expect(option.value, 'red');
        expect(option.checked, isTrue);
        expect(option.actions, contains(SemanticAction.activate));
        final result = await tester.invokeSemanticAction(
          SemanticAction.setValue,
          node: option,
          payload: false,
          allowFailure: true,
        );
        expect(result.status, SemanticActionInvocationStatus.unsupported);
      },
    );

    await probe(
      'Select reports completed dispatch for an unknown option while leaving its value unchanged',
      (tester) async {
        String? changed;
        tester.pumpWidget(
          Select<String>(
            value: 'red',
            semanticLabel: 'Color',
            options: const [SelectOption(value: 'red', label: 'Red')],
            onChanged: (value) => changed = value,
          ),
        );
        final result = await tester.invokeSemanticAction(
          SemanticAction.setValue,
          role: SemanticRole.button,
          label: 'Color',
          payload: 'No such option',
        );
        expect(result.completed, isTrue);
        expect(changed, isNull);
        expect(
          tester
              .semantics()
              .single(role: SemanticRole.button, label: 'Color')
              .value,
          'Red',
        );
      },
    );

    await probe(
      'NumberInput rejects invalid replacement through its normal controller listener',
      (tester) async {
        tester.pumpWidget(
          const NumberInput(initialValue: 12, semanticLabel: 'Count'),
        );
        final result = await tester.invokeSemanticAction(
          SemanticAction.setValue,
          role: SemanticRole.textField,
          label: 'Count',
          payload: 'invalid',
        );
        expect(result.completed, isTrue);
        expect(
          tester
              .semantics()
              .single(role: SemanticRole.textField, label: 'Count')
              .value,
          '12',
        );
      },
    );

    await probe(
      'the guide confirmation is a named region, not a dialog; covered editor controls are excluded',
      (tester) async {
        tester.pumpWidget(
          FleuryApp(
            title: 'Probe',
            home: DraftEditor(save: (_) async {}),
          ),
        );
        tester.type(' More detail.');
        await tester.invokeSemanticAction(
          SemanticAction.activate,
          role: SemanticRole.button,
          label: 'Discard',
        );
        await tester.settle();
        expect(tester.semantics().byRole(SemanticRole.dialog), isEmpty);
        expect(
          tester.semantics().single(
            role: SemanticRole.region,
            label: 'Discard changes?',
          ),
          isNotNull,
        );
        expect(
          tester.semantics().where(role: SemanticRole.button, label: 'Save'),
          isEmpty,
        );
        expect(
          tester.semantics().where(role: SemanticRole.textArea, label: 'Draft'),
          isEmpty,
        );
      },
    );

    await probe(
      'a standalone controlled Checkbox sends a change request without updating its supplied value',
      (tester) async {
        bool? changed;
        tester.pumpWidget(
          Checkbox(
            value: false,
            label: 'Terms',
            onChanged: (value) => changed = value,
          ),
        );
        await tester.invokeSemanticAction(
          SemanticAction.setValue,
          role: SemanticRole.checkbox,
          label: 'Terms',
          payload: true,
        );
        tester.pump();
        expect(changed, isTrue);
        expect(
          tester
              .semantics()
              .single(role: SemanticRole.checkbox, label: 'Terms')
              .checked,
          isFalse,
        );
      },
    );

    print(
      const JsonEncoder.withIndent('  ').convert({
        'scope':
            'Observed existing contracts, not proposed helper implementation or a full-suite run',
        'checked': observations,
        'count': observations.length,
      }),
    );
  });
}
