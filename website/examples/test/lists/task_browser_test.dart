import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/lists/task_browser.dart';

void main() {
  testWidgets(
    'arrows browse; Enter selects; scrolling keeps the current item',
    (tester) async {
      tester.pumpWidget(const SizedBox(width: 40, child: TaskBrowser()));
      expect(tester.renderToString(), contains('Task 25'));
      expect(tester.exists(text('Selected: None')), isTrue);
      tester.press(KeySequence.down);
      expect(tester.exists(text('Selected: None')), isTrue);
      expect(tester.exists(text('Focused: Task 26')), isTrue);
      tester.press(KeySequence.enter);
      tester.pump();
      expect(tester.exists(text('Selected: Task 26')), isTrue);
      expect(tester.exists(text('✓ Task 26')), isTrue);

      tester.press(KeySequence.down);
      expect(tester.exists(text('✓ Task 26')), isTrue);

      await tester.button('Go to 25').press();
      tester.pump();
      expect(tester.renderToString(), contains('Current: 25 / 1000'));
      expect(tester.renderToString(), contains('Task 25'));
      expect(tester.exists(text('Focused: outside list')), isTrue);
      expect(tester.exists(text('Selected: Task 26')), isTrue);

      await tester.button('Scroll to 500').press();
      tester.pump();
      final screen = tester.renderToString();
      expect(screen, contains('Current: 25 / 1000'));
      expect(screen, contains('Showing: 500–509'));
      expect(screen, contains('Task 500'));
      expect(screen, isNot(contains('  Task 25\n')));
      expect(screen, contains('Focused: outside list'));

      await tester.button('Go to 25').press();
      tester.pump();
      expect(tester.renderToString(), contains('Task 25'));
      expect(tester.exists(text('Selected: Task 26')), isTrue);
    },
  );

  testWidgets('a completed click selects the visible row', (tester) {
    tester.pumpWidget(const SizedBox(width: 40, child: TaskBrowser()));
    tester.press(KeySequence.home);
    tester.pump();
    for (final kind in [MouseEventKind.down, MouseEventKind.up]) {
      tester.sendMouse(
        MouseEvent(kind: kind, button: MouseButton.left, col: 3, row: 5),
      );
      tester.pump();
    }
    expect(tester.exists(text('Selected: Task 3')), isTrue);
    expect(tester.exists(text('✓ Task 3')), isTrue);
    tester.press(KeySequence.down);
    tester.press(KeySequence.enter);
    tester.pump();
    expect(tester.exists(text('✓ Task 4')), isTrue);
    expect(tester.exists(text('✓ Task 3')), isFalse);
  });
}
