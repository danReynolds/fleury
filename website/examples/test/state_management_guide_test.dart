@TestOn('vm')
library;

import 'package:fleury/fleury.dart';
import 'package:fleury_doc_examples/registry.dart' as demos;
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

import '../lib/state_management_guide.dart' as guide;

class _CartService {
  _CartService(this.cart) {
    _cancel = cart.listen(() => observed.add(cart.itemCount));
  }

  final guide.Cart cart;
  final observed = <int>[];
  late final VoidCallback _cancel;

  void addItem() => cart.addItem();
  void dispose() => _cancel();
}

void main() {
  testWidgets('both project consumers use the nearest matching scope', (
    tester,
  ) {
    tester.pumpWidget(
      const Scope<guide.Project>(
        guide.Project('Atlas'),
        child: Column(
          children: [
            guide.ProjectName(),
            Scope<guide.Project>(
              guide.Project('Beacon'),
              child: Column(
                children: [guide.ProjectName(), guide.ProjectLabel()],
              ),
            ),
          ],
        ),
      ),
    );
    final output = tester.renderToString();
    expect('Project: Atlas'.allMatches(output).length, 1);
    expect('Project: Beacon'.allMatches(output).length, 2);
  });

  testWidgets('an external cart keeps serving its service after UI unmounts', (
    tester,
  ) {
    final cart = guide.Cart();
    addTearDown(cart.dispose);
    final service = _CartService(cart);
    addTearDown(service.dispose);
    expect(identical(service.cart, cart), isTrue);

    tester.pumpWidget(
      Column(
        children: [
          guide.CartView(cart: cart),
          guide.CartContextView(cart: cart),
        ],
      ),
    );
    service.addItem();
    tester.pump();
    expect('Items: 1'.allMatches(tester.renderToString()).length, 2);
    expect(service.observed, [1]);

    tester.pumpWidget(const SizedBox());
    service.addItem();
    expect(cart.itemCount, 2);
    expect(service.observed, [1, 2]);

    service.dispose();
    expect(cart.hasListeners, isFalse);
    cart.addItem();
    expect(cart.itemCount, 3);
    expect(service.observed, [1, 2]);
  });

  testWidgets('Notifier and ValueNotifier consumers produce the same updates', (
    tester,
  ) async {
    final builderCart = guide.Cart();
    final contextCart = guide.Cart();
    final count = ValueNotifier<int>(0);
    addTearDown(builderCart.dispose);
    addTearDown(contextCart.dispose);
    addTearDown(count.dispose);

    for (final (source, consumer) in <(Notifier, Widget)>[
      (builderCart, guide.CartView(cart: builderCart)),
      (contextCart, guide.CartContextView(cart: contextCart)),
      (count, guide.CartValueView(count: count)),
    ]) {
      tester.pumpWidget(FleuryApp(title: 'Shop', home: consumer));
      expect(tester.exists(text('Items: 0')), isTrue);
      await tester.button('Add item').press();
      expect(tester.exists(text('Items: 1')), isTrue);
      await tester.button('Add item').press();
      expect(tester.exists(text('Items: 2')), isTrue);
      tester.pumpWidget(const SizedBox());
      expect(source.hasListeners, isFalse);
    }
    expect(builderCart.itemCount, 2);
    expect(contextCart.itemCount, 2);
    expect(count.value, 2);
  });

  // The registry and runnable snippets import the same web-safe source.
  for (final (id, initial, action, updated, next) in [
    ('state.local-counter', 'Count: 0', 'Increment', 'Count: 1', 'Count: 2'),
    (
      'state.project-scope',
      'Project: Atlas',
      'Switch project',
      'Project: Beacon',
      'Project: Atlas',
    ),
    (
      'state.project-context',
      'Project: Atlas',
      'Switch project',
      'Project: Beacon',
      'Project: Atlas',
    ),
    ('state.cart-notifier', 'Items: 0', 'Add item', 'Items: 1', 'Items: 2'),
    ('state.cart-context', 'Items: 0', 'Add item', 'Items: 1', 'Items: 2'),
    ('state.cart-value', 'Items: 0', 'Add item', 'Items: 1', 'Items: 2'),
  ]) {
    final demo = demos.exampleList.singleWhere((demo) => demo.id == id);
    testWidgets(
      '$id remains interactive at its embedded size',
      (tester) async {
        final theme = demos.DocsExampleThemeController(
          demos.DocsExampleStyle.dark,
        );
        addTearDown(theme.dispose);
        tester.pumpWidget(demos.themedExampleRoot(demo.builder, theme));
        expect(tester.renderToString(), contains(initial));
        await tester.button(action).press();
        expect(tester.renderToString(), contains(updated));
        await tester.button(action).press();
        expect(tester.renderToString(), contains(next));
      },
      viewportSize: CellSize(demo.cols, demo.rows),
    );
  }
}
