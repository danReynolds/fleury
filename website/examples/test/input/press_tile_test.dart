import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/input/press_tile.dart';
import 'pointer_test_helpers.dart';

void main() {
  testWidgets('cancelling another press preserves the current preview', (
    tester,
  ) {
    tester.pumpFleuryHome(const PressTile());
    tester.press(KeySequence.enter);
    pointer(tester, MouseEventKind.down, 3, 0);
    expect(tester.renderToString(), contains('Bring the sketches.'));
    pointer(tester, MouseEventKind.drag, 7, 0);
    pointer(tester, MouseEventKind.up, 7, 0);
    expect(tester.exists(text('Cancelled')), isTrue);
    expect(tester.renderToString(), contains('Bring the sketches.'));
    tester.press(KeySequence.i);
    pointer(tester, MouseEventKind.down, 3, 0);
    pointer(tester, MouseEventKind.cancel, 0, 0);
    expect(tester.exists(text('Cancelled')), isTrue);
    expect(tester.renderToString(), contains('Location: /notes'));
  });

  testWidgets('custom tile shows focus and opts its label out of selection', (
    tester,
  ) async {
    tester.pumpFleuryHome(const PressTile());
    expect(tester.render().atColRow(3, 0).style.underline, isTrue);
    tester.press(KeySequence.tab);
    expect(tester.render().atColRow(3, 0).style.underline, isFalse);
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.button, label: 'Details')
          .focused,
      isTrue,
    );
    tester.press(KeySequence.enter);
    expect(tester.exists(text('notes.md · Markdown · 2 KB')), isTrue);
    tester.press(KeySequence.shift.tab);
    tester.press(KeySequence.space);
    expect(tester.exists(text('Opened notes.md')), isTrue);
    tester.press(KeySequence.i);
    expect(tester.exists(text('notes.md · Markdown · 2 KB')), isTrue);
    pointer(tester, MouseEventKind.down, 3, 0);
    pointer(tester, MouseEventKind.drag, 7, 0);
    pointer(tester, MouseEventKind.up, 7, 0);
    expect(tester.exists(text('Cancelled')), isTrue);
    tester.press(KeySequence.ctrl.c);
    await tester.settle();
    expect((tester.clipboard as InProcessClipboard).lastWritten, isNull);
    pointer(tester, MouseEventKind.down, 3, 0);
    pointer(tester, MouseEventKind.cancel, 0, 0);
    pointer(tester, MouseEventKind.up, 3, 0);
    expect(tester.exists(text('Cancelled')), isTrue);
    expect(tester.exists(text('Pressed…')), isFalse);
  });

  testWidgets(
    'release outside cancels; primary and secondary clicks stay distinct',
    (tester) {
      tester.pumpWidget(const PressTile());
      pointer(tester, MouseEventKind.down, 3, 0);
      expect(tester.exists(text('Pressed…')), isTrue);
      pointer(tester, MouseEventKind.up, 30, 4);
      expect(tester.exists(text('Cancelled')), isTrue);
      pointer(tester, MouseEventKind.down, 3, 0);
      pointer(tester, MouseEventKind.up, 3, 0);
      expect(tester.exists(text('Opened notes.md')), isTrue);
      pointer(tester, MouseEventKind.down, 3, 0, button: MouseButton.right);
      pointer(tester, MouseEventKind.up, 3, 0, button: MouseButton.right);
      expect(tester.exists(text('notes.md · Markdown · 2 KB')), isTrue);
    },
  );
}
