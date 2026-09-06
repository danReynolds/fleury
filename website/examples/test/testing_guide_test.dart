import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

import '../lib/testing_guide.dart';

void main() {
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

  testWidgets('adds one', (tester) async {
    tester.pumpWidget(const Counter());
    await tester.button('Add one').press();
    expect(tester.exists(text('Count: 1')), isTrue);
  });

  testWidgets('adds one using the keyboard', (tester) {
    tester.pumpWidget(const Counter());
    expect(tester.button('Add one'), isFocused);
    tester.press(KeySequence.enter);
    expect(tester.exists(text('Count: 1')), isTrue);
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

  testWidgets('saves the draft with Ctrl+S', (tester) async {
    String? saved;
    tester.pumpWidget(
      FleuryApp(
        title: 'Draft editor',
        home: DraftEditor(save: (text) async => saved = text),
      ),
    );
    final editor = tester.target(type: DraftEditor);
    expect(editor.field('Draft'), isFocused);
    tester.type(' Ready for review.');
    tester.press(KeySequence.ctrl.s);
    await tester.settle();

    expect(saved, 'Ship the testing guide. Ready for review.');
    expect(tester.exists(text('All changes saved')), isTrue);
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
