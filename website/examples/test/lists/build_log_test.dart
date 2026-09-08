import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/lists/build_log.dart';

void main() {
  testWidgets('reading older output pauses following until Latest', (
    tester,
  ) async {
    tester.pumpWidget(const SizedBox(width: 46, child: BuildLog()));
    tester.pump();
    expect(tester.renderToString(), contains('Step 12 complete'));

    tester.press(KeySequence.home);
    await tester.button('Append').press();
    tester.pump();
    final paused = tester.renderToString();
    expect(paused, contains('Paused · 1 new entries'));
    expect(paused, contains('Step 1 complete'));
    expect(paused, isNot(contains('Step 13 complete')));

    await tester.button('Grow last entry').press();
    tester.pump();
    expect(tester.renderToString(), contains('Step 1 complete'));
    expect(tester.renderToString(), isNot(contains('Detail 1')));

    await tester.button('Latest').press();
    tester.pump();
    expect(tester.renderToString(), contains('Step 13 complete'));
    expect(tester.exists(text('Following latest output')), isTrue);

    await tester.button('Append').press();
    tester.pump();
    expect(tester.renderToString(), contains('Step 14 complete'));
  });

  testWidgets('a growing last entry stays visible, even taller than the pane', (
    tester,
  ) async {
    tester.pumpWidget(const SizedBox(width: 46, child: BuildLog()));
    for (var i = 0; i < 8; i++) {
      await tester.button('Grow last entry').press();
    }
    tester.pump();
    expect(tester.renderToString(), contains('Detail 8'));
    expect(tester.exists(text('Following latest output')), isTrue);
  });
}
