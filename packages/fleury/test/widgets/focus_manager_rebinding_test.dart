import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('manager replacement preserves sibling trap activation order', (
    tester,
  ) {
    final first = FocusManager();
    final second = FocusManager();
    final earlier = FocusNode();
    final later = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget contents(bool trapEarlier) => Column(
      children: [
        FocusScope(
          trapFocus: trapEarlier,
          child: Focus(focusNode: earlier, child: const Text('earlier')),
        ),
        FocusScope(
          trapFocus: true,
          child: Focus(focusNode: later, child: const Text('later')),
        ),
      ],
    );
    tester.pumpWidget(
      FocusManagerScope(manager: first, child: contents(false)),
    );
    // Activate the earlier sibling LAST. Its trap must remain on top even
    // though dependency rebuilds visit it before the later sibling.
    final child = contents(true);
    tester.pumpWidget(FocusManagerScope(manager: first, child: child));
    expect(first.isUnderActiveFocusTrap(later), isFalse);
    tester.pumpWidget(FocusManagerScope(manager: second, child: child));
    tester.pump();
    expect(second.isUnderActiveFocusTrap(later), isFalse);
    expect(second.requestFocus(earlier), isTrue);
    expect(second.requestFocus(later), isFalse);
  });

  testWidgets('exclusion changes notify only the replacement manager', (
    tester,
  ) async {
    final first = FocusManager();
    final second = FocusManager();
    final node = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget contents(bool excluding) => ExcludeFocus(
      excluding: excluding,
      child: Focus(focusNode: node, child: const Text('field')),
    );
    final child = contents(true);
    tester.pumpWidget(FocusManagerScope(manager: first, child: child));
    tester.pumpWidget(FocusManagerScope(manager: second, child: child));
    await tester.settle();
    expect(second.requestFocus(node), isFalse);
    var oldNotifications = 0;
    var newNotifications = 0;
    first.addListener(() => oldNotifications++);
    second.addListener(() => newNotifications++);
    tester.pumpWidget(
      FocusManagerScope(manager: second, child: contents(false)),
    );
    await tester.settle();
    expect(oldNotifications, 0);
    expect(newNotifications, greaterThan(0));
    expect(second.requestFocus(node), isTrue);
  });

  testWidgets('focus manager rejects a node owned by another session', (
    tester,
  ) {
    final first = FocusManager();
    final second = FocusManager();
    final node = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    tester.pumpWidget(
      FocusManagerScope(
        manager: first,
        child: Focus(focusNode: node, child: const Text('field')),
      ),
    );

    expect(second.requestFocus(node), isFalse);
    expect(second.focusedNode, isNull);
    expect(second.isClickable(node), isFalse);
    expect(second.isTraversable(node), isFalse);
    node.requestFocus();
    expect(first.focusedNode, same(node));
  });

  for (final disposeOld in [false, true]) {
    testWidgets('retained focus nodes rebind to a replacement manager '
        '(old disposed: $disposeOld)', (tester) {
      final first = FocusManager();
      final second = FocusManager();
      final node = FocusNode();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      var keys = 0;
      final child = KeyDetector(
        onKey: (event) {
          keys++;
          event.consume();
        },
        child: Focus(focusNode: node, child: const Text('field')),
      );
      tester.pumpWidget(FocusManagerScope(manager: first, child: child));
      node.requestFocus();
      if (disposeOld) first.dispose();
      tester.pumpWidget(FocusManagerScope(manager: second, child: child));
      tester.pump();

      expect(first.attachedNodes, isEmpty);
      expect(first.focusedNode, isNull);
      expect(second.attachedNodes, contains(node));
      node.requestFocus();
      expect(second.focusedNode, same(node));
      final dispatcher = InputDispatcher(focusManager: second);
      addTearDown(dispatcher.dispose);
      dispatcher.dispatch(const KeyEvent(KeyCode.enter));
      expect(keys, 1, reason: 'ancestor detector must rebind too');
      first.dispose();
      expect(node.isAttached, isTrue);
      tester.pumpWidget(const EmptyBox());
      expect(second.attachedNodes, isEmpty);
    });
  }

  testWidgets('retained focus traps move to the replacement manager', (tester) {
    final first = FocusManager();
    final second = FocusManager();
    final outside = FocusNode();
    final inside = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final child = Column(
      children: [
        Focus(focusNode: outside, child: const Text('outside')),
        FocusScope(
          trapFocus: true,
          child: Focus(focusNode: inside, child: const Text('inside')),
        ),
      ],
    );
    tester.pumpWidget(FocusManagerScope(manager: first, child: child));
    tester.pumpWidget(FocusManagerScope(manager: second, child: child));
    tester.pump();

    expect(second.isUnderActiveFocusTrap(outside), isFalse);
    expect(second.requestFocus(outside), isFalse);
    expect(second.requestFocus(inside), isTrue);
    expect(
      first.isUnderActiveFocusTrap(outside),
      isTrue,
      reason: 'old manager must release its retained trap',
    );
    tester.pumpWidget(const EmptyBox());
    expect(second.isUnderActiveFocusTrap(outside), isTrue);
  });
}
