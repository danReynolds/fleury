// Proposal feasibility probe. These helpers are local to this file, not API.
import 'dart:async';
import 'dart:convert';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';
import 'package:test/test.dart';

import '../../../website/examples/lib/testing_guide.dart';

extension ProposedControls on FleuryTester {
  ProposedButton button(String label) => ProposedButton(this, label);
}

class ProposedButton {
  ProposedButton(this.tester, this.label);

  final FleuryTester tester;
  final String label;

  SemanticNode get snapshot =>
      tester.semantics().single(role: SemanticRole.button, label: label);

  Future<void> press() async {
    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: label,
    );
    tester.pump();
  }
}

void main() {
  test('proposed button facade feasibility', runProbe);
}

Future<void> runProbe() async {
  final checks = <String>[];

  Future<void> probe(
    String name,
    Future<void> Function(FleuryTester tester) body,
  ) async {
    final tester = FleuryTester();
    try {
      await body(tester);
      checks.add(name);
    } finally {
      tester.dispose();
    }
  }

  await probe(
    'query resolves a replacement root rather than retaining a node',
    (tester) async {
      tester.pumpWidget(const Counter());
      final add = tester.button('Add one');
      await add.press();
      expect(tester.exists(text('Count: 1')), isTrue);
      tester.pumpWidget(const Text('Counter removed'));
      tester.pumpWidget(const Counter());
      await add.press();
      expect(tester.exists(text('Count: 1')), isTrue);
    },
  );

  await probe('duplicates are ambiguous even when only one is enabled', (
    tester,
  ) async {
    var called = false;
    tester.pumpWidget(
      Column(
        children: [
          Button(label: 'Save', onPressed: () => called = true),
          const Button(label: 'Save', onPressed: null),
        ],
      ),
    );
    await expectLater(
      tester.button('Save').press(),
      throwsA(
        isA<TestFailure>().having(
          (failure) => failure.toString(),
          'diagnostic',
          allOf(contains('ambiguous'), contains('Save')),
        ),
      ),
    );
    expect(called, isFalse);
  });

  await probe('logical press operates a custom semantic button', (
    tester,
  ) async {
    var called = false;
    tester.pumpWidget(
      Semantics(
        role: SemanticRole.button,
        label: 'Custom',
        actions: const {SemanticAction.activate},
        onAction: (_) => called = true,
        child: const Text('Custom control'),
      ),
    );
    await tester.button('Custom').press();
    expect(called, isTrue);
    // Deliberately has no pointer/key handler: this proves semantic dispatch,
    // not physical input coverage.
  });

  await probe('press completes layout without a separate render call', (
    tester,
  ) async {
    final done = ValueNotifier(false);
    try {
      tester.pumpWidget(
        ValueListenableBuilder<bool>(
          valueListenable: done,
          builder: (context, value, child) => value
              ? LayoutBuilder(
                  builder: (context, constraints) => const Text('Ready'),
                )
              : Button(label: 'Build', onPressed: () => done.value = true),
        ),
      );
      await tester.button('Build').press();
      expect(tester.exists(text('Ready')), isTrue);
    } finally {
      tester.pumpWidget(const Text('Unmounted'));
      done.dispose();
    }
  });

  await probe('save stays pending, rejects a repeat press, and can retry', (
    tester,
  ) async {
    var request = Completer<void>();
    var requests = 0;
    tester.pumpWidget(
      FleuryApp(
        title: 'Probe',
        home: DraftEditor(
          save: (_) {
            requests++;
            return request.future;
          },
        ),
      ),
    );
    final save = tester.button('Save');
    tester.type(' More detail.');
    await save.press();
    expect(tester.exists(text('Saving…')), isTrue);
    expect(save.snapshot.enabled, isFalse);
    await expectLater(
      save.press(),
      throwsA(
        isA<TestFailure>().having(
          (failure) => failure.toString(),
          'diagnostic',
          contains('disabled'),
        ),
      ),
    );
    expect(requests, 1);
    request.completeError(StateError('Offline'));
    await tester.settle();
    expect(tester.exists(text('Save failed. Your draft is safe.')), isTrue);
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.textArea, label: 'Draft')
          .value,
      'Ship the testing guide. More detail.',
    );
    expect(save.snapshot.enabled, isTrue);
    request = Completer<void>();
    await save.press();
    request.complete();
    await tester.settle();
    expect(requests, 2);
    expect(tester.exists(text('All changes saved')), isTrue);
  });

  print(
    const JsonEncoder.withIndent('  ').convert({
      'scope': 'local button facade feasibility; not a public implementation',
      'checked': checks,
      'count': checks.length,
    }),
  );
}
