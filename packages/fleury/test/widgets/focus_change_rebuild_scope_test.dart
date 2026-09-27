// A focus move rebuilds the controls whose focus changed — the one that lost
// it and the one that gained it — not every focusable control in the tree.
// Each control used to depend on the whole FocusManager, so one Tab in a
// form of N fields rebuilt all N.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

Widget _form(int rows) => FocusTraversalGroup(
  child: Column(
    children: [
      for (var i = 0; i < rows; i++)
        Row(
          children: [
            SizedBox(width: 12, child: TextInput(autofocus: i == 0)),
            Button(text: 'Go $i', onPressed: () {}),
          ],
        ),
      const SizedBox(width: 12, child: TextArea()),
    ],
  ),
);

int _rebuiltByNextFocus(FleuryTester tester) {
  tester.owner.flushBuild();
  tester.focusManager.focusNext();
  return tester.owner.flushBuild().rebuiltElementCount;
}

void main() {
  testWidgets('a focus move rebuilds only the controls it concerns', (tester) {
    tester.pumpWidget(_form(20));
    tester.render(size: const CellSize(40, 30));

    // TextInput 0 -> Button 0, then Button 0 -> TextInput 1.
    final toButton = _rebuiltByNextFocus(tester);
    final toField = _rebuiltByNextFocus(tester);

    expect(toButton, lessThan(8), reason: 'rebuilt $toButton elements');
    expect(toField, lessThan(8), reason: 'rebuilt $toField elements');
  });

  testWidgets('the focus cue still follows focus', (tester) {
    tester.pumpWidget(_form(2));
    tester.render(size: const CellSize(40, 8));
    final first = tester.focusManager.focusedNode;

    tester.focusManager.focusNext();
    tester.render(size: const CellSize(40, 8));

    expect(first?.hasFocus, isFalse);
    final semantics = tester.semantics();
    final focused = semantics.where(focused: true);
    expect(focused, hasLength(1));
    expect(focused.single.label, 'Go 0');
  });

  testWidgets('a click on a field does not make it depend on all focus', (
    tester,
  ) {
    tester.pumpWidget(_form(20));
    tester.render(size: const CellSize(40, 30));
    _rebuiltByNextFocus(tester); // field 0 -> button 0
    final baseline = _rebuiltByNextFocus(tester); // button 0 -> field 1

    // A click on field 0: its pointer handler asks the manager whether the
    // field can take focus, which must not subscribe it to every move.
    for (final kind in [MouseEventKind.down, MouseEventKind.up]) {
      tester.sendMouse(
        MouseEvent(kind: kind, button: MouseButton.left, col: 1, row: 0),
      );
    }
    tester.render(size: const CellSize(40, 30));
    _rebuiltByNextFocus(tester); // field 0 -> button 0
    final after = _rebuiltByNextFocus(tester); // button 0 -> field 1

    expect(after, baseline, reason: 'field 0 is not part of this move');
  });

  testWidgets('a node that takes focus back from an unmounted child shows it', (
    tester,
  ) {
    final parent = FocusNode(debugLabel: 'parent');
    final show = ValueNotifier(true);
    tester.pumpWidget(
      Focus(
        focusNode: parent,
        child: Column(
          children: [
            NotifierBuilder(
              notifier: show,
              builder: (_, show) => show.value
                  ? const Focus(autofocus: true, child: Text('child'))
                  : const Text('removed'),
            ),
            _Cue(parent),
          ],
        ),
      ),
    );
    tester.render(size: const CellSize(20, 4));
    expect(
      tester.renderToString(size: const CellSize(20, 4)),
      contains('idle'),
    );

    show.value = false;
    tester.pump();

    expect(parent.hasFocus, isTrue);
    expect(
      tester.renderToString(size: const CellSize(20, 4)),
      contains('FOCUSED'),
    );
  });

  testWidgets('a node that ExcludeFocus releases shows it', (tester) async {
    final node = FocusNode(debugLabel: 'excluded');
    final excluded = ValueNotifier(false);
    // One instance, so only the node's own notification rebuilds it.
    final focusedChild = Focus(
      focusNode: node,
      autofocus: true,
      child: _Cue(node),
    );
    tester.pumpWidget(
      NotifierBuilder(
        notifier: excluded,
        builder: (_, excluded) =>
            ExcludeFocus(excluding: excluded.value, child: focusedChild),
      ),
    );
    tester.render(size: const CellSize(20, 4));
    expect(
      tester.renderToString(size: const CellSize(20, 4)),
      contains('FOCUSED'),
    );

    excluded.value = true;
    tester.pump();
    await Future<void>.delayed(Duration.zero);
    tester.pump();

    expect(node.hasFocus, isFalse);
    expect(
      tester.renderToString(size: const CellSize(20, 4)),
      contains('idle'),
    );
  });
}

/// Shows whether [node] has focus, rebuilding only when it flips.
final class _Cue extends StatelessWidget {
  const _Cue(this.node);

  final FocusNode node;

  @override
  Widget build(BuildContext context) =>
      Text(context.listen(node).hasFocus ? 'FOCUSED' : 'idle');
}
