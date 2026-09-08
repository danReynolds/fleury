// dart format width=60
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/lists/file_list.dart';

void main() {
  testWidgets('arrows focus a row; Enter selects it', (
    tester,
  ) {
    tester.pumpWidget(const FileList());
    tester.press(KeySequence.down);
    expect(tester.renderToString(), contains('› notes.md'));
    expect(tester.exists(text('Selected: None')), isTrue);
    tester.press(KeySequence.enter);
    expect(
      tester.exists(text('Selected: notes.md')),
      isTrue,
    );
    tester.press(KeySequence.down);
    expect(
      tester.renderToString(),
      contains('› sketches.txt'),
    );
    expect(
      tester.exists(text('Selected: notes.md')),
      isTrue,
    );
  });

  testWidgets('a completed click selects a row', (tester) {
    tester.pumpWidget(const FileList());
    for (final kind in [
      MouseEventKind.down,
      MouseEventKind.up,
    ]) {
      tester.sendMouse(
        MouseEvent(
          kind: kind,
          button: MouseButton.left,
          col: 3,
          row: 2,
        ),
      );
      tester.pump();
    }
    expect(
      tester.exists(text('Selected: sketches.txt')),
      isTrue,
    );
  });
}
