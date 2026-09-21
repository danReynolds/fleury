// Shared, web-safe source for the state guide's executable snippets and embeds.
import 'package:fleury/fleury_core.dart';

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

class Project {
  const Project(this.name);

  final String name;
}

class ProjectScopeScreen extends StatefulWidget {
  const ProjectScopeScreen({super.key});

  @override
  State<ProjectScopeScreen> createState() => _ProjectScopeScreenState();
}

class _ProjectScopeScreenState extends State<ProjectScopeScreen> {
  var project = const Project('Atlas');

  void switchProject() => setState(() {
    project = project.name == 'Atlas'
        ? const Project('Beacon')
        : const Project('Atlas');
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Scope(project, child: const ProjectName()),
      Button(text: 'Switch project', onPressed: switchProject),
    ],
  );
}

class ProjectName extends StatelessWidget {
  const ProjectName({super.key});

  @override
  Widget build(BuildContext context) => ScopeBuilder<Project>(
    builder: (context, project) => Text('Project: ${project.name}'),
  );
}

class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  var project = const Project('Atlas');

  void switchProject() => setState(() {
    project = project.name == 'Atlas'
        ? const Project('Beacon')
        : const Project('Atlas');
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Scope(project, child: const ProjectLabel()),
      Button(text: 'Switch project', onPressed: switchProject),
    ],
  );
}

class ProjectLabel extends StatelessWidget {
  const ProjectLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final project = context.scope<Project>();
    return Text('Project: ${project.name}');
  }
}

class Cart extends Notifier {
  int _itemCount = 0;

  int get itemCount => _itemCount;

  void addItem() {
    _itemCount++;
    notify();
  }
}

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

// Each embed owns an isolated model. The executable main creates a Cart outside
// the widget tree and lends it to these same consumers for the app's lifetime.
class CartDemo extends StatefulWidget {
  const CartDemo({super.key, this.contextReader = false});

  final bool contextReader;

  @override
  State<CartDemo> createState() => _CartDemoState();
}

class _CartDemoState extends State<CartDemo> {
  final cart = Cart();

  @override
  void dispose() {
    cart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.contextReader ? CartContextView(cart: cart) : CartView(cart: cart);
}

class CartValueDemo extends StatefulWidget {
  const CartValueDemo({super.key});

  @override
  State<CartValueDemo> createState() => _CartValueDemoState();
}

class _CartValueDemoState extends State<CartValueDemo> {
  final count = ValueNotifier<int>(0);

  @override
  void dispose() {
    count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CartValueView(count: count);
}
