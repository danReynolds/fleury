// The Testing guide's checks beyond the tests it shows. The guide shows each
// file under testing/ whole, as the reader's own test, and the docs gate runs
// that directory alongside this file. Like those tests, this file imports the
// examples through package: URIs only, so each library loads once.
import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury_doc_examples/testing_guide.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

import 'scenarios/preferences_tests.dart';

void main() {
  // The guide's "Run test" button replays the shared scenario, pausing on each
  // step, beside the test the guide shows. Both must be the same steps.
  test('the walkthrough runs the preferences test the guide shows', () {
    final scenario =
        RegExp(
              r'// #docregion preferences-test\n([\s\S]*?)\n *// #enddocregion',
            )
            .firstMatch(
              File('test/scenarios/preferences_tests.dart').readAsStringSync(),
            )!
            .group(1)!;
    final shown =
        RegExp(
              r"testWidgets\('edits only the work preferences', \(tester\) async \{\n"
              r'([\s\S]*?)\n  \}\);',
            )
            .firstMatch(
              File('test/testing/preferences_test.dart').readAsStringSync(),
            )!
            .group(1)!;
    final steps = scenario
        .split('\n')
        .where((line) => !line.trim().startsWith('yield '))
        .join('\n');

    expect(_dedent(shown), _dedent(steps));
  });

  testWidgets('the walkthrough scenario runs to completion', (tester) async {
    await runPreferencesTest(tester, expect: expect).drain<void>();
  });

  testWidgets('walkthrough pauses on real intermediate frames', (tester) async {
    final steps = StreamIterator(runPreferencesTest(tester, expect: expect));
    addTearDown(steps.cancel);
    await steps.moveNext();
    expect(steps.current, PreferencesTestStep.mounted);
    final work = tester.target(key: const ValueKey('work'));
    expect(work.field('Name'), hasValue(''));
    expect(work.checkbox('Email updates'), isUnchecked);

    await steps.moveNext();
    expect(steps.current, PreferencesTestStep.filled);
    expect(work.field('Name'), hasValue('Ada'));
    expect(work.checkbox('Email updates'), isUnchecked);

    await steps.moveNext();
    expect(steps.current, PreferencesTestStep.checked);
    expect(work.checkbox('Email updates'), isChecked);
  });

  testWidgets('walkthrough fails if an assertion no longer holds', (
    tester,
  ) async {
    final steps = StreamIterator(runPreferencesTest(tester, expect: expect));
    addTearDown(steps.cancel);
    for (var i = 0; i < 3; i++) {
      await steps.moveNext();
    }
    await tester
        .target(key: const ValueKey('work'))
        .field('Name')
        .fill('Grace');
    await expectLater(steps.moveNext(), throwsA(isA<TestFailure>()));
  });

  testWidgets('work preferences start ready for keyboard input', (tester) {
    // The application shell supplies the standard Tab traversal bindings.
    tester.pumpWidget(FleuryApp(title: 'Preferences', home: preferencesPair()));
    final work = tester.target(key: const ValueKey('work'));
    expect(work.field('Name'), isFocused);
    tester.type('Ada');
    expect(work.field('Name'), hasValue('Ada'));
    tester.press(KeySequence.tab);
    expect(work.checkbox('Email updates'), isFocused);
    final personal = tester.target(key: const ValueKey('personal'));
    expect(personal.field('Name'), hasValue(''));
  });

  testWidgets('shows a failed save and allows retry', (tester) async {
    var request = Completer<void>();
    tester.pumpWidget(SaveStatus(save: () => request.future));
    await tester.button('Save').press();

    request.completeError(StateError('Offline'));
    await tester.settle();
    expect(tester.exists(text('Save failed')), isTrue);
    expect(tester.button('Save'), isEnabled);

    request = Completer<void>();
    await tester.button('Save').press();
    expect(tester.exists(text('Saving…')), isTrue);
    request.complete();
    await tester.settle();
    expect(tester.exists(text('Saved')), isTrue);
  });

  testWidgets('observes a custom async handler before it completes', (
    tester,
  ) async {
    final started = Completer<void>();
    final request = Completer<void>();
    tester.pumpWidget(
      PublishControl(
        publish: () => request.future,
        onStarted: started.complete,
      ),
    );
    final publish = tester.button('Publish');
    final action = publish.press();
    await started.future;
    tester.pump();
    expect(publish, hasValue('Publishing…'));
    expect(publish, isDisabled);
    request.complete();
    await action;
    expect(publish, hasValue('Published'));
    expect(publish, isEnabled);
  });

  testWidgets('fills and saves a draft', (tester) async {
    String? saved;
    tester.pumpWidget(
      FleuryApp(
        title: 'Draft editor',
        home: DraftEditor(save: (text) async => saved = text),
      ),
    );
    final editor = tester.target(type: DraftEditor);
    await editor.field('Draft').fill('Ready for review.');
    expect(editor.button('Save'), isEnabled);
    await editor.button('Save').press();
    await tester.settle();
    expect(saved, 'Ready for review.');
    expect(editor.button('Save'), isDisabled);
  });

  testWidgets('keeps the draft after a failed save, then retries', (
    tester,
  ) async {
    var request = Completer<void>();
    final submitted = <String>[];
    tester.pumpWidget(
      FleuryApp(
        title: 'Draft editor',
        home: DraftEditor(
          save: (text) {
            submitted.add(text);
            return request.future;
          },
        ),
      ),
    );
    final editor = tester.target(type: DraftEditor);
    await editor.field('Draft').fill('Ready for review.');
    await editor.button('Save').press();

    expect(tester.exists(text('Saving…')), isTrue);
    expect(editor.button('Save'), isDisabled);
    tester.press(KeySequence.ctrl.s);
    expect(submitted, ['Ready for review.']);

    request.completeError(StateError('Offline'));
    await tester.settle();
    expect(tester.exists(text('Save failed. Your draft is safe.')), isTrue);
    expect(editor.field('Draft'), hasValue('Ready for review.'));
    expect(editor.button('Save'), isEnabled);

    request = Completer<void>();
    await editor.button('Save').press();
    request.complete();
    await tester.settle();
    expect(submitted, ['Ready for review.', 'Ready for review.']);
    expect(tester.exists(text('All changes saved')), isTrue);
  });

  testWidgets('cancels a discard and restores focus to its button', (
    tester,
  ) async {
    tester.pumpWidget(
      FleuryApp(
        title: 'Draft editor',
        home: DraftEditor(save: (_) async {}),
      ),
    );
    final editor = tester.target(type: DraftEditor);
    tester.type(' More detail.');
    await editor.button('Discard').press();
    tester.pumpAndSettle();

    final dialog = tester.target(
      role: SemanticRole.dialog,
      label: 'Discard changes?',
    );
    expect(dialog.button('Keep editing'), isFocused);
    // A type scope cannot expose controls covered by the modal.
    expect(editor.field('Draft'), hasCount(0));
    expect(editor.button('Save'), hasCount(0));
    tester.press(KeySequence.escape);
    await tester.settle();

    expect(dialog, hasCount(0));
    expect(editor.button('Discard'), isFocused);
    expect(editor.field('Draft'), hasValue(contains('More detail.')));
  });

  testWidgets('discards only after confirmation', (tester) async {
    tester.pumpWidget(
      FleuryApp(
        title: 'Draft editor',
        home: DraftEditor(save: (_) async {}),
      ),
    );
    final editor = tester.target(type: DraftEditor);
    await editor.field('Draft').fill('Unsaved draft');
    await editor.button('Discard').press();
    tester.pumpAndSettle();
    final dialog = tester.target(
      role: SemanticRole.dialog,
      label: 'Discard changes?',
    );
    await dialog.button('Discard draft').press();
    await tester.settle();

    expect(dialog, hasCount(0));
    expect(editor.field('Draft'), hasValue('Ship the testing guide.'));
    expect(tester.exists(text('Changes discarded')), isTrue);
  });

  testWidgets('renders the editor at a compact size', (tester) {
    tester.viewportSize = const CellSize(42, 12);
    tester.pumpWidget(
      FleuryApp(
        title: 'Draft editor',
        home: DraftEditor(save: (_) async {}),
      ),
    );
    expect(tester.renderToString(), matchesGolden('testing/editor.txt'));
  });

  testWidgets('advances an animation without waiting on wall time', (tester) {
    Widget progress(double target) => AnimationBuilder<double>(
      target,
      curve: Curves.linear,
      duration: const Duration(seconds: 1),
      builder: (context, value, child) => Text('${(value * 100).round()}%'),
    );
    tester.pumpWidget(progress(0));
    tester.pumpWidget(progress(1));
    tester.pump(const Duration(milliseconds: 500));
    expect(tester.exists(text('50%')), isTrue);
    tester.pumpAndSettle();
    expect(tester.exists(text('100%')), isTrue);
  });
}

/// [code] without the indentation its lines share.
String _dedent(String code) {
  final lines = code.split('\n');
  final indent = lines
      .where((line) => line.trim().isNotEmpty)
      .map((line) => line.length - line.trimLeft().length)
      .fold<int?>(null, (min, n) => min == null || n < min ? n : min);
  return [
    for (final line in lines)
      line.trim().isEmpty ? '' : line.substring(indent ?? 0),
  ].join('\n');
}
