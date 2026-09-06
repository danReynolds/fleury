// Derived geometry hosts follow the widget lifecycle: an app-owned FocusNode
// reports a rect and a caret only while the widget that carries it is in the
// tree, and reports them again after a remount.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('a FocusNode reports no rect after its Focus unmounts', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    Widget app({required bool mounted}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('header'),
        if (mounted) Focus(focusNode: node, child: const Text('target')),
      ],
    );

    tester.pumpWidget(app(mounted: true));
    expect(node.rect, CellRect.fromLTWH(0, 1, 6, 1));

    tester.mountWidget(app(mounted: false));
    expect(node.rect, isNull, reason: 'unmounted: no host to derive from');
    tester.render();
    expect(node.rect, isNull);

    tester.pumpWidget(app(mounted: true));
    expect(node.rect, CellRect.fromLTWH(0, 1, 6, 1), reason: 'remounted');
  });

  testWidgets('a FocusNode reports no caret after its TextInput unmounts', (
    tester,
  ) async {
    final node = FocusNode();
    final controller = TextEditingController(text: 'ab');
    addTearDown(node.dispose);
    addTearDown(controller.dispose);
    Widget app({required bool mounted}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('header'),
        if (mounted)
          SizedBox(
            width: 6,
            height: 1,
            child: TextInput(
              controller: controller,
              focusNode: node,
              autofocus: true,
            ),
          ),
      ],
    );

    tester.pumpWidget(app(mounted: true));
    expect(node.caretRect, CellRect.fromLTWH(2, 1, 1, 1));

    tester.mountWidget(app(mounted: false));
    expect(node.caretRect, isNull, reason: 'unmounted: no caret host');
    tester.render();
    expect(node.caretRect, isNull);

    tester.pumpWidget(app(mounted: true));
    expect(node.caretRect, CellRect.fromLTWH(2, 1, 1, 1), reason: 'remounted');
  });
}
