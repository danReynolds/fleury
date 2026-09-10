// Lock test: CompletionTextInput popup uses bare BoundsAnchor like
// Autocomplete — no AnchoredFloat AbsorbPointer slot barrier.
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

Iterable<TextCompletionOption> _provider(TextCompletionRequest request) {
  final q = request.query.toLowerCase();
  return [
    const TextCompletionOption(label: 'alpha'),
    const TextCompletionOption(label: 'alpine'),
  ].where((o) => o.label.startsWith(q));
}

void main() {
  testWidgets('open CompletionTextInput popup blocks clicks underneath', (
    tester,
  ) {
    var presses = 0;
    tester.pumpWidget(
      Column(
        children: [
          SizedBox(
            height: 1,
            child: CompletionTextInput(provider: _provider, autofocus: true),
          ),
          Button(label: 'DELETE ALL', onPressed: () => presses++),
        ],
      ),
    );

    tester.type('al');
    expect(tester.overlay.entries.length, 2);

    final buf = tester.render(size: const CellSize(40, 12));
    var clickCol = -1;
    var clickRow = -1;
    for (var r = 0; r < buf.size.rows && clickCol < 0; r++) {
      for (var c = 0; c < buf.size.cols - 2; c++) {
        if (buf.atColRow(c, r).grapheme == 'L' &&
            buf.atColRow(c + 2, r).grapheme == ']') {
          clickCol = c;
          clickRow = r;
          break;
        }
      }
    }
    expect(clickCol, isNonNegative, reason: 'button remnant visible');

    tester.sendMouse(
      MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: clickCol,
        row: clickRow,
      ),
    );
    tester.sendMouse(
      MouseEvent(
        kind: MouseEventKind.up,
        button: MouseButton.left,
        col: clickCol,
        row: clickRow,
      ),
    );

    expect(
      presses,
      0,
      reason: 'CompletionTextInput popup must barrier clicks underneath',
    );
  });
}
