import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/input/file_actions.dart';
import 'pointer_test_helpers.dart';

void main() {
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
