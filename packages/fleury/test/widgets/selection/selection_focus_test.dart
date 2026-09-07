import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../../support/harness.dart';

void pointer(FleuryTester tester, MouseEventKind kind, int col, int row) {
  tester.sendMouse(
    MouseEvent(kind: kind, button: MouseButton.left, col: col, row: row),
  );
  tester.pump();
}

void select(FleuryTester tester, int row) {
  pointer(tester, MouseEventKind.down, 0, row);
  pointer(tester, MouseEventKind.drag, 3, row);
  pointer(tester, MouseEventKind.up, 3, row);
}

void main() {
  testWidgets('selection takes focus from a sibling and owns its shortcuts', (
    tester,
  ) {
    final region = FocusNode(skipTraversal: true);
    addTearDown(region.dispose);
    SelectedContent? selected;
    tester.pumpWidget(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionArea(
            focusNode: region,
            onSelectionChanged: (value) => selected = value,
            child: const Text('ABCDE'),
          ),
          const TextInput(semanticLabel: 'Reply', autofocus: true),
        ],
      ),
    );
    expect(tester.semantics().single(label: 'Reply').focused, isTrue);
    pointer(tester, MouseEventKind.moved, 1, 0);
    expect(
      tester.semantics().single(label: 'Reply').focused,
      isTrue,
      reason: 'hover does not take focus',
    );

    select(tester, 0);
    expect(region.hasFocus, isTrue);
    expect(selected?.plainText, 'ABC');
    tester.press(KeySequence.ctrl.c);
    expect(tester.clipboard.readInProcess(), 'ABC');
    tester.press(KeySequence.ctrl.a);
    expect(selected?.plainText, 'ABCDE');
    tester.press(KeySequence.escape);
    expect(selected, isNull);
    expect(tester.semantics().single(label: 'Reply').value, '');
  });

  testWidgets('each sibling region receives its own copy shortcut', (tester) {
    tester.pumpWidget(
      const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionArea(child: Text('First')),
          SelectionArea(child: Text('Second')),
          TextInput(semanticLabel: 'Reply', autofocus: true),
        ],
      ),
    );
    select(tester, 0);
    tester.press(KeySequence.ctrl.c);
    expect(tester.clipboard.readInProcess(), 'Fir');
    select(tester, 1);
    tester.press(KeySequence.ctrl.c);
    expect(tester.clipboard.readInProcess(), 'Sec');
  });

  testWidgets('nested fields retain their own focus and editing selection', (
    tester,
  ) {
    tester.pumpWidget(
      const SelectionArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ABCDE'),
            TextInput(semanticLabel: 'Reply'),
          ],
        ),
      ),
    );
    select(tester, 0);
    pointer(tester, MouseEventKind.down, 1, 1);
    pointer(tester, MouseEventKind.up, 1, 1);
    expect(tester.semantics().single(label: 'Reply').focused, isTrue);
    tester.type('Reply');
    tester.press(KeySequence.shift.home);
    tester.press(KeySequence.ctrl.c);
    expect(tester.clipboard.readInProcess(), 'Reply');
    expect(tester.semantics().single(label: 'Reply').value, 'Reply');
  });

  testWidgets('regions do not add Tab stops by default', (tester) {
    tester.pumpWidget(
      const FocusTraversalGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextInput(semanticLabel: 'First', autofocus: true),
            SelectionArea(child: Text('A note')),
            TextInput(semanticLabel: 'Last'),
          ],
        ),
      ),
    );
    tester.press(KeySequence.tab);
    expect(tester.semantics().single(label: 'Last').focused, isTrue);
    tester.press(KeySequence.tab);
    expect(tester.semantics().single(label: 'First').focused, isTrue);
  });

  testWidgets('a supplied node can opt a region into Tab traversal', (tester) {
    final region = FocusNode();
    addTearDown(region.dispose);
    tester.pumpWidget(
      FocusTraversalGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TextInput(semanticLabel: 'First', autofocus: true),
            SelectionArea(focusNode: region, child: const Text('A note')),
            const TextInput(semanticLabel: 'Last'),
          ],
        ),
      ),
    );
    tester.press(KeySequence.tab);
    expect(region.hasFocus, isTrue);
    tester.press(KeySequence.tab);
    expect(tester.semantics().single(label: 'Last').focused, isTrue);
  });

  testWidgets('supplied focus nodes detach on replacement and removal', (
    tester,
  ) {
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    tester.pumpWidget(
      SelectionArea(focusNode: first, child: const Text('ABCDE')),
    );
    select(tester, 0);
    expect(first.hasFocus, isTrue);
    tester.pumpWidget(
      SelectionArea(focusNode: second, child: const Text('ABCDE')),
    );
    expect(first.isAttached, isFalse);
    expect(second.isAttached, isTrue);
    second.requestFocus();
    expect(second.hasFocus, isTrue);
    tester.pumpWidget(const Text('Done'));
    expect(second.isAttached, isFalse);
    tester.pumpWidget(Focus(focusNode: first, child: const Text('Reused')));
    first.requestFocus();
    expect(first.hasFocus, isTrue);
  });

  testWidgets(
    'app-wide selection preserves app shortcuts after selecting text',
    (tester) {
      var appHits = 0;
      final appFocus = FocusNode();
      addTearDown(appFocus.dispose);
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeySequence.ctrl.a, onTrigger: (_) => appHits++),
          ],
          child: Focus(
            focusNode: appFocus,
            autofocus: true,
            child: const Text('ABCDE'),
          ),
        ),
      );
      select(tester, 0);
      tester.press(KeySequence.ctrl.c);
      expect(tester.clipboard.readInProcess(), 'ABC');
      expect(appFocus.hasFocus, isTrue);
      tester.press(KeySequence.ctrl.a);
      expect(appHits, 1);
    },
  );
}
