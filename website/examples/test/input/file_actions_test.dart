import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/input/file_actions.dart';
import '../../lib/input/press_tile.dart';
import 'pointer_test_helpers.dart';

void main() {
  for (final (name, example, rows) in [
    ('button', const FileActions(), 14),
    ('tile', const PressTile(), 16),
  ]) {
    testWidgets(
      '$name preview fits the guide and can be closed',
      (tester) {
        tester.pumpFleuryHome(
          Padding(padding: const EdgeInsets.all(1), child: example),
        );
        tester.press(KeySequence.enter);
        expect(tester.renderToString(), contains('Bring the sketches.'));
        tester.press(KeySequence.tab);
        tester.press(KeySequence.enter);
        expect(tester.renderToString(), contains('Location: /notes'));
        tester.press(KeySequence.tab);
        tester.press(KeySequence.enter);
        expect(
          tester.renderToString(),
          contains('Your note will appear here.'),
        );
      },
      viewportSize: CellSize(38, rows),
    );
  }

  testWidgets('button keeps press, focus, secondary and keyboard behavior', (
    tester,
  ) async {
    tester.pumpFleuryHome(const FileActions());
    expect(tester.render().atColRow(2, 0).style.underline, isTrue);
    pointer(tester, MouseEventKind.down, 3, 0);
    expect(tester.render().atColRow(2, 0).style.inverse, isTrue);
    pointer(tester, MouseEventKind.up, 3, 0);
    expect(tester.exists(text('Opened notes.md')), isTrue);
    expect(tester.render().atColRow(2, 0).style.inverse, isFalse);
    pointer(tester, MouseEventKind.down, 3, 0, button: MouseButton.right);
    pointer(tester, MouseEventKind.up, 3, 0, button: MouseButton.right);
    expect(tester.exists(text('notes.md · Markdown · 2 KB')), isTrue);
    tester.press(KeySequence.enter);
    expect(tester.exists(text('Opened notes.md')), isTrue);
    tester.press(KeySequence.tab);
    expect(tester.render().atColRow(2, 0).style.underline, isFalse);
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.button, label: 'Details')
          .focused,
      isTrue,
    );
    tester.press(KeySequence.space);
    expect(tester.exists(text('notes.md · Markdown · 2 KB')), isTrue);
    pointer(tester, MouseEventKind.down, 3, 0);
    pointer(tester, MouseEventKind.drag, 7, 0);
    pointer(tester, MouseEventKind.up, 7, 0);
    tester.press(KeySequence.ctrl.c);
    await tester.settle();
    expect((tester.clipboard as InProcessClipboard).lastWritten, isNull);
    expect(
      tester.exists(text('notes.md · Markdown · 2 KB')),
      isTrue,
      reason: 'movement cancels activation without selecting the label',
    );
  });
}
