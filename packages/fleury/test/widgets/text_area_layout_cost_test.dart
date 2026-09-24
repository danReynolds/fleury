// A caret move or keystroke in a TextArea lays out without measuring the
// whole document. The widest line only sizes an unbounded-width area; a
// bounded one threw that measure away after walking every grapheme, so each
// arrow key cost time in proportion to the document.
import 'package:fleury/fleury.dart';
import 'package:fleury/src/widgets/text_area.dart' show RenderTextArea;
import 'package:test/test.dart';

final class _CountingResolver implements WidthResolver {
  var calls = 0;

  @override
  int widthOfGrapheme(String grapheme, CellWidthPolicy policy) {
    calls++;
    return const DefaultWidthResolver().widthOfGrapheme(grapheme, policy);
  }

  @override
  int widthOfText(String text, CellWidthPolicy policy) =>
      const DefaultWidthResolver().widthOfText(text, policy);
}

void main() {
  const line = 60;
  late _CountingResolver resolver;
  late RenderTextArea area;

  setUp(() {
    resolver = _CountingResolver();
    area = RenderTextArea(
      focusNode: FocusNode(),
      text: List.filled(500, 'x' * line).join('\n'),
      selection: const TextSelection.collapsed(offset: 0),
      widthResolver: resolver,
    );
  });

  test('a caret move in a bounded area measures its line, not the text', () {
    const constraints = CellConstraints(maxCols: 80, maxRows: 10);
    area.layout(constraints);
    resolver.calls = 0;

    area.selection = const TextSelection.collapsed(offset: 5);
    area.layout(constraints);

    expect(
      resolver.calls,
      lessThan(2 * line),
      reason: 'the caret line, not 500',
    );
  });

  test('a keystroke in a bounded area measures no more than its line', () {
    const constraints = CellConstraints(maxCols: 80, maxRows: 10);
    area.layout(constraints);
    resolver.calls = 0;

    // New text, so a new line list: no memo can answer for it.
    area.text = '${'x' * line}\n' * 499 + 'x' * line + 'y';
    area.layout(constraints);

    expect(
      resolver.calls,
      lessThan(2 * line),
      reason: 'the caret line, not 500',
    );
  });

  test('an unbounded area measures its document once per text', () {
    const constraints = CellConstraints(maxRows: 10);
    area.layout(constraints);
    expect(area.size.cols, line);
    resolver.calls = 0;

    area.selection = const TextSelection.collapsed(offset: 5);
    area.layout(constraints);

    expect(
      resolver.calls,
      lessThan(2 * line),
      reason: 'the caret line, not 500',
    );
    expect(area.size.cols, line);
  });
}
