import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  testWidgets(
    'local, tree, and global controls update their own state',
    (tester) async {
      tester.pumpFleuryHome(const StateManagementShowcaseApp());
      final painted = tester.renderToString();
      for (final label in [
        'Count: 0',
        'Increment',
        'Project: Atlas',
        'Active project: Atlas',
        'Switch project',
        'Items: 0',
        'Cart summary: 0 items',
        'Add item',
        'Click any button',
      ]) {
        expect(painted, contains(label));
      }
      expect(tester.exists(text('Count: 0')), isTrue);
      expect(tester.exists(text('Project: Atlas')), isTrue);
      expect(tester.exists(text('Active project: Atlas')), isTrue);
      expect(tester.exists(text('Items: 0')), isTrue);
      expect(tester.exists(text('Cart summary: 0 items')), isTrue);

      await tester.button('Increment').press();
      expect(tester.exists(text('Count: 1')), isTrue);
      expect(tester.exists(text('Project: Atlas')), isTrue);
      expect(tester.exists(text('Items: 0')), isTrue);

      await tester.button('Switch project').press();
      expect(tester.exists(text('Project: Beacon')), isTrue);
      expect(tester.exists(text('Active project: Beacon')), isTrue);
      expect(tester.exists(text('Count: 1')), isTrue);
      await tester.button('Switch project').press();
      expect(tester.exists(text('Project: Atlas')), isTrue);
      expect(tester.exists(text('Active project: Atlas')), isTrue);

      await tester.button('Add item').press();
      expect(tester.exists(text('Items: 1')), isTrue);
      expect(tester.exists(text('Cart summary: 1 items')), isTrue);
      expect(tester.exists(text('Count: 1')), isTrue);
      expect(tester.renderToString(), contains('Click any button'));
    },
    viewportSize: const CellSize(80, 28),
  );

  testWidgets('external changes reach both readers and survive unmount', (
    tester,
  ) {
    final cart = StateManagementCart();
    addTearDown(cart.dispose);
    tester.pumpWidget(StateManagementShowcaseApp(cart: cart));
    expect(cart.hasListeners, isTrue);

    // A service or controller can perform this without a BuildContext.
    cart.addItem();
    tester.pump();
    expect(tester.exists(text('Items: 1')), isTrue);
    expect(tester.exists(text('Cart summary: 1 items')), isTrue);

    tester.pumpWidget(const SizedBox());
    expect(cart.hasListeners, isFalse);
    cart.addItem();
    expect(cart.itemCount, 2);

    tester.pumpWidget(StateManagementShowcaseApp(cart: cart));
    expect(tester.exists(text('Items: 2')), isTrue);
    expect(tester.exists(text('Cart summary: 2 items')), isTrue);
  });

  testWidgets('replacing a borrowed cart follows the new model', (tester) {
    final first = StateManagementCart();
    final second = StateManagementCart()..addItem();
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    tester.pumpWidget(StateManagementShowcaseApp(cart: first));
    expect(tester.exists(text('Items: 0')), isTrue);
    tester.pumpWidget(StateManagementShowcaseApp(cart: second));
    expect(first.hasListeners, isFalse);
    expect(second.hasListeners, isTrue);
    expect(tester.exists(text('Items: 1')), isTrue);

    first.addItem();
    second.addItem();
    tester.pump();
    expect(tester.exists(text('Items: 2')), isTrue);
    expect(tester.exists(text('Cart summary: 2 items')), isTrue);

    tester.pumpWidget(const SizedBox());
    expect(second.hasListeners, isFalse);
    first.addItem();
    second.addItem();
    expect(first.itemCount, 2);
    expect(second.itemCount, 3);
  });
}
