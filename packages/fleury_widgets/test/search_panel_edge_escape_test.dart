// Regression (RFC 0018 binding-constructor pass): up-arrow at the top result
// of a focused SearchPanel list must return focus to the query field above,
// rather than clamping and swallowing the key.

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('up at the top result returns focus to the query field', (
    tester,
  ) {
    final queryFocus = FocusNode(debugLabel: 'query');
    final resultsFocus = FocusNode(debugLabel: 'results');
    final queryController = TextEditingController();
    final listController = ListController(selectedIndex: 0);

    tester.pumpWidget(
      FocusTraversalGroup(
        child: SizedBox(
          height: 8,
          child: SearchPanel(
            results: const <SearchResult>[
              SearchResult(title: 'Alpha', id: 'a'),
              SearchResult(title: 'Beta', id: 'b'),
              SearchResult(title: 'Gamma', id: 'c'),
            ],
            queryController: queryController,
            controller: listController,
            queryFocusNode: queryFocus,
            resultsFocusNode: resultsFocus,
            width: 28,
            fillHeight: true,
            onActivate: (result, _) {},
          ),
        ),
      ),
    );
    tester.render(size: const CellSize(30, 10));

    // Focus the results list at its top item.
    resultsFocus.requestFocus();
    tester.render(size: const CellSize(30, 10));
    expect(resultsFocus.hasFocus, isTrue, reason: 'results list focused');

    // Up at the top edge should escape back to the query field above.
    tester.sendKey(KeyEvent(KeyCode.arrowUp));
    tester.render(size: const CellSize(30, 10));

    expect(
      queryFocus.hasFocus,
      isTrue,
      reason: 'up at the top result should return focus to the query',
    );
  });
}
