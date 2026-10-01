// Shared, web-safe source for the state guide's executable snippets and embeds.
// The guide shows the `#docregion` excerpts below, so they must stay readable.
import 'package:fleury/fleury_core.dart';

// #docregion local
class LocalCounter extends StatefulWidget {
  const LocalCounter({super.key});

  @override
  State<LocalCounter> createState() => _LocalCounterState();
}

class _LocalCounterState extends State<LocalCounter> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Count: $count'),
      Button(text: 'Increment', onPressed: () => setState(() => count++)),
    ],
  );
}
// #enddocregion local

// #docregion project
class Project {
  const Project(this.name);

  final String name;

  String get path => '~/projects/${name.toLowerCase()}';
}
// #enddocregion project

class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

// #docregion project-owner
class _ProjectScreenState extends State<ProjectScreen> {
  var project = const Project('Atlas');

  void switchProject() => setState(() {
    project = project.name == 'Atlas'
        ? const Project('Beacon')
        : const Project('Atlas');
  });

  @override
  Widget build(BuildContext context) => Scope(
    project,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ProjectTitle(),
        const ProjectPath(),
        Button(text: 'Switch project', onPressed: switchProject),
      ],
    ),
  );
}
// #enddocregion project-owner

// #docregion project-builder
class ProjectTitle extends StatelessWidget {
  const ProjectTitle({super.key});

  @override
  Widget build(BuildContext context) => ScopeBuilder<Project>(
    builder: (context, project) => Text('Project: ${project.name}'),
  );
}
// #enddocregion project-builder

// #docregion project-context
class ProjectPath extends StatelessWidget {
  const ProjectPath({super.key});

  @override
  Widget build(BuildContext context) {
    final project = context.scope<Project>();
    return Text('Path: ${project.path}');
  }
}
// #enddocregion project-context

// #docregion cart
class Cart extends Notifier {
  int _itemCount = 0;

  int get itemCount => _itemCount;

  void addItem() {
    _itemCount++;
    notify();
  }
}
// #enddocregion cart

// #docregion shop-owner
class Shop extends StatelessWidget {
  const Shop({super.key});

  @override
  Widget build(BuildContext context) =>
      Scope.create(Cart.new, child: const ShopScreen());
}

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CartBadge(),
      SizedBox(height: 1),
      AddToCartButton(product: 'coffee'),
      AddToCartButton(product: 'tea'),
    ],
  );
}
// #enddocregion shop-owner

// #docregion shop-readers
class CartBadge extends StatelessWidget {
  const CartBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.scope<Cart>();
    return Text('In cart: ${cart.itemCount}');
  }
}

class AddToCartButton extends StatelessWidget {
  const AddToCartButton({super.key, required this.product});

  final String product;

  @override
  Widget build(BuildContext context) {
    final cart = context.scope<Cart>();
    return Button(text: 'Add $product', onPressed: cart.addItem);
  }
}
// #enddocregion shop-readers

// #docregion cart-builder
class CartView extends StatelessWidget {
  const CartView({super.key, required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) => NotifierBuilder(
    notifier: cart,
    builder: (context, cart) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Items: ${cart.itemCount}'),
        Button(text: 'Add item', onPressed: cart.addItem),
      ],
    ),
  );
}
// #enddocregion cart-builder

// #docregion cart-listen
class CartContextView extends StatelessWidget {
  const CartContextView({super.key, required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final model = context.listen(cart);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Items: ${model.itemCount}'),
        Button(text: 'Add item', onPressed: model.addItem),
      ],
    );
  }
}
// #enddocregion cart-listen

// #docregion value-notifier
class CartValueView extends StatelessWidget {
  const CartValueView({super.key, required this.count});

  final ValueNotifier<int> count;

  @override
  Widget build(BuildContext context) {
    final items = context.listen(count).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Items: $items'),
        Button(text: 'Add item', onPressed: () => count.value++),
      ],
    );
  }
}
// #enddocregion value-notifier

// The two readers share a model owned by State, the third owner the guide
// lists: created once with the state, disposed with it.
class CartDemo extends StatefulWidget {
  const CartDemo({super.key});

  @override
  State<CartDemo> createState() => _CartDemoState();
}

// #docregion cart-owner
class _CartDemoState extends State<CartDemo> {
  final cart = Cart();

  @override
  void dispose() {
    cart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('NotifierBuilder', style: CellStyle(bold: true)),
      CartView(cart: cart),
      const SizedBox(height: 1),
      const Text('context.listen', style: CellStyle(bold: true)),
      CartContextView(cart: cart),
    ],
  );
}

// #enddocregion cart-owner
