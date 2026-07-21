// Backs website/src/content/docs/guides/state-management.md — sharing state
// across widgets with a ChangeNotifier model + ListenableBuilder, the same
// pattern Flutter uses. Kept as a real, analyzed program.
//
// Run it:  dart run doc_snippets/shared_state.dart

import 'package:fleury/fleury.dart';

/// A plain model — no framework base class beyond ChangeNotifier. Mutate
/// through methods and call notifyListeners(); every ListenableBuilder bound
/// to it rebuilds.
class CartModel extends ChangeNotifier {
  final List<String> _items = [];

  List<String> get items => List.unmodifiable(_items);
  int get count => _items.length;

  void add(String item) {
    _items.add(item);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}

void main() => runApp(const ShopApp());

class ShopApp extends StatefulWidget {
  const ShopApp({super.key});

  @override
  State<ShopApp> createState() => _ShopAppState();
}

class _ShopAppState extends State<ShopApp> {
  // The model outlives any single widget's build. Own it where it belongs
  // (here, the app root) and dispose it with the State.
  final _cart = CartModel();

  @override
  void dispose() {
    _cart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(
          const KeyCode.char('a'),
          onTrigger: () => _cart.add('Item ${_cart.count + 1}'),
        ),
        KeyBinding(const KeyCode.char('c'), onTrigger: () => _cart.clear()),
      ],
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Two widgets, one source of truth. Neither is a child of the
            // other — a ListenableBuilder rebuilds just its subtree when the
            // model changes, so the header and the list stay in sync without
            // threading state through constructors.
            _CartBadge(cart: _cart),
            const SizedBox(height: 1),
            const Text('a: add item   c: clear'),
            const SizedBox(height: 1),
            Expanded(child: _CartList(cart: _cart)),
          ],
        ),
      ),
    );
  }
}

class _CartBadge extends StatelessWidget {
  const _CartBadge({required this.cart});
  final CartModel cart;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) => Text('Cart: ${cart.count} item(s)'),
    );
  }
}

class _CartList extends StatelessWidget {
  const _CartList({required this.cart});
  final CartModel cart;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final item in cart.items) Text('• $item')],
      ),
    );
  }
}
