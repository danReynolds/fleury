// dart format width=60
import 'dart:async';
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/forms/save_project.dart';

void main() {
  testWidgets(
    'server field error preserves the draft and supports retry',
    (tester) async {
      var pending = Completer<SaveReply>();
      final savedNames = <String>[];
      tester.pumpWidget(
        SaveProject(
          save: (name, _) {
            savedNames.add(name);
            return pending.future;
          },
        ),
      );
      await tester.button('Save').press();
      await tester.settle();
      expect(tester.button('Saving…'), isDisabled);
      expect(
        tester.field('Name').snapshot.state.readOnly,
        isTrue,
      );
      expect(savedNames, ['Atlas']);

      pending.complete(SaveReply.nameTaken);
      await tester.settle();
      expect(
        tester.renderToString(),
        contains('That name is taken.'),
      );
      expect(tester.field('Name'), isFocused);
      expect(tester.field('Name'), hasValue('Atlas'));
      expect(tester.button('Save'), isEnabled);

      await tester.field('Name').fill('Fleury');
      await tester.settle();
      expect(
        tester.renderToString(),
        isNot(contains('That name is taken.')),
      );
      pending = Completer<SaveReply>();
      await tester.button('Save').press();
      await tester.settle();
      pending.complete(SaveReply.saved);
      await tester.settle();
      expect(savedNames, ['Atlas', 'Fleury']);
      expect(
        tester.renderToString(),
        contains('Saved Fleury'),
      );
    },
    viewportSize: const CellSize(40, 16),
  );

  testWidgets(
    'offline failure keeps the draft and Enter retries it',
    (tester) async {
      var offline = true;
      tester.pumpWidget(
        SaveProject(
          save: (_, _) async {
            if (offline) throw ServiceUnavailable();
            return SaveReply.saved;
          },
        ),
      );
      await tester.button('Save').press();
      await tester.settle();
      expect(
        tester.renderToString(),
        contains('Offline. Your draft is kept. Retry.'),
      );
      expect(tester.field('Name'), hasValue('Atlas'));
      expect(tester.button('Save'), isEnabled);

      offline = false;
      await tester.field('Name').focus();
      tester.press(KeySequence.enter);
      await tester.settle();
      expect(
        tester.renderToString(),
        contains('Saved Atlas'),
      );
    },
    viewportSize: const CellSize(40, 16),
  );

  testWidgets(
    'a pending save can finish after the form closes',
    (tester) async {
      final pending = Completer<SaveReply>();
      tester.pumpWidget(
        SaveProject(save: (_, _) => pending.future),
      );
      await tester.button('Save').press();
      await tester.settle();
      tester.pumpWidget(const Text('Closed'));
      pending.complete(SaveReply.saved);
      await tester.settle();
      expect(tester.renderToString(), contains('Closed'));
    },
  );
}
